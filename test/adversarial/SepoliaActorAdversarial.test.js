import { expect } from "chai";
import hre from "hardhat";
import Database from "better-sqlite3";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const RUN_ACTOR_TESTS = process.env.RUN_SEPOLIA_ACTOR_TESTS === "1";
const FORK_URL = process.env.HARDHAT_FORK_URL || process.env.RPC_URL;
const EVENTS_DB_PATH =
  process.env.SEPOLIA_EVENTS_DB || resolve(process.cwd(), "runs/sepolia/events.db");
const MANIFEST_PATH = resolve(
  process.cwd(),
  "deployments/sepolia-testnet.json"
);
const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const BURNIE_UNIT = hre.ethers.parseEther("1");

function normalizeAddress(value) {
  if (typeof value !== "string") return null;
  if (!value.startsWith("0x") || value.length !== 42) return null;
  try {
    return hre.ethers.getAddress(value);
  } catch {
    return null;
  }
}

function topicToAddress(topic) {
  return hre.ethers.getAddress(`0x${topic.slice(26)}`);
}

function parseEvent(receipt, iface, name) {
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog({ topics: log.topics, data: log.data });
      if (parsed?.name === name) return parsed;
    } catch {
      // Ignore logs from other contracts.
    }
  }
  return null;
}

function parseEvents(receipt, iface, name) {
  const out = [];
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog({ topics: log.topics, data: log.data });
      if (parsed?.name === name) out.push(parsed);
    } catch {
      // Ignore logs from other contracts.
    }
  }
  return out;
}

async function withImpersonated(address, fn) {
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x1000000000000000000",
  ]);
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  const signer = await hre.ethers.getSigner(address);
  try {
    return await fn(signer);
  } finally {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [address],
    });
  }
}

function loadManifest() {
  return JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
}

function systemAddressSet(manifest) {
  return new Set([
    manifest.deployer.toLowerCase(),
    ...Object.values(manifest.contracts).map((a) => a.toLowerCase()),
    ...Object.values(manifest.mocks || {}).map((a) => a.toLowerCase()),
  ]);
}

function loadActorCountsFromDb(manifest) {
  if (!existsSync(EVENTS_DB_PATH)) return [];

  const db = new Database(EVENTS_DB_PATH, { readonly: true });
  try {
    const trackedContracts = [
      manifest.contracts.GAME,
      manifest.contracts.COINFLIP,
      manifest.contracts.AFFILIATE,
    ].map((a) => a.toLowerCase());
    const placeholders = trackedContracts.map(() => "?").join(", ");
    const rows = db
      .prepare(
        `SELECT decoded_args
         FROM events
         WHERE lower(contract_address) IN (${placeholders})`
      )
      .all(...trackedContracts);

    const keys = [
      "buyer",
      "player",
      "sender",
      "recipient",
      "affiliate",
      "winner",
      "target",
      "from",
      "to",
      "referrer",
    ];
    const counts = new Map();

    for (const row of rows) {
      if (!row.decoded_args) continue;
      let decoded;
      try {
        decoded = JSON.parse(row.decoded_args);
      } catch {
        continue;
      }
      for (const key of keys) {
        const addr = normalizeAddress(decoded[key]);
        if (!addr) continue;
        if (addr === hre.ethers.ZeroAddress) continue;
        counts.set(addr, (counts.get(addr) || 0) + 1);
      }
    }

    return [...counts.entries()].sort((a, b) => b[1] - a[1]);
  } finally {
    db.close();
  }
}

async function etherscanJson(params) {
  const apiKey = process.env.ETHERSCAN_API_KEY;
  if (!apiKey) return null;

  const qs = new URLSearchParams({
    chainid: "11155111",
    apikey: apiKey,
    ...params,
  });
  const resp = await fetch(`https://api.etherscan.io/v2/api?${qs}`);
  const text = await resp.text();
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function loadActorCountsFromEtherscan(manifest) {
  const apiKey = process.env.ETHERSCAN_API_KEY;
  if (!apiKey) return [];

  let fromBlock = Number(process.env.SEPOLIA_ACTOR_FROM_BLOCK || 0);
  if (fromBlock === 0) {
    const creation = await etherscanJson({
      module: "contract",
      action: "getcontractcreation",
      contractaddresses: manifest.contracts.GAME,
    });
    const createdAt = Number(creation?.result?.[0]?.blockNumber || 0);
    if (createdAt !== 0) {
      fromBlock = createdAt;
    }
  }
  if (fromBlock === 0) {
    const latest = await hre.ethers.provider.getBlockNumber();
    fromBlock = Math.max(0, latest - Number(process.env.SEPOLIA_ACTOR_LOOKBACK || 800));
  }

  const maxPages = Number(process.env.SEPOLIA_ETHERSCAN_MAX_PAGES || 20);
  const specs = [
    {
      address: manifest.contracts.GAME,
      topic: hre.ethers.id("TicketsQueued(address,uint24,uint32)"),
    },
    {
      address: manifest.contracts.GAME,
      topic: hre.ethers.id("BetPlaced(address,uint48,uint64,uint256)"),
    },
    {
      address: manifest.contracts.COINFLIP,
      topic: hre.ethers.id("CoinflipDeposit(address,uint256)"),
    },
    {
      address: manifest.contracts.AFFILIATE,
      topic: hre.ethers.id("ReferralUpdated(address,bytes32,address,bool)"),
    },
  ];
  const counts = new Map();

  for (const spec of specs) {
    for (let page = 1; page <= maxPages; page++) {
      const data = await etherscanJson({
        module: "logs",
        action: "getLogs",
        address: spec.address,
        topic0: spec.topic,
        fromBlock: String(fromBlock),
        toBlock: "latest",
        page: String(page),
        offset: "1000",
      });
      if (!data) break;
      const resultText = typeof data.result === "string" ? data.result : "";
      if (data.status !== "1") {
        if (
          data.message?.includes("No records") ||
          resultText.includes("No records")
        ) {
          break;
        }
        break;
      }

      const logs = Array.isArray(data.result) ? data.result : [];
      for (const log of logs) {
        const topic1 = log.topics?.[1];
        if (!topic1) continue;
        const addr = topicToAddress(topic1);
        if (addr === hre.ethers.ZeroAddress) continue;
        counts.set(addr, (counts.get(addr) || 0) + 1);
      }
      if (logs.length < 1000) break;
    }
  }

  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

async function loadActorCountsFromRpc(manifest) {
  const lookback = Number(process.env.SEPOLIA_ACTOR_LOOKBACK || 800);
  const chunk = Number(process.env.SEPOLIA_ACTOR_LOG_CHUNK || 10);
  const minActors = Number(process.env.SEPOLIA_MIN_ACTORS || 3);
  const latest = await hre.ethers.provider.getBlockNumber();
  const fromBlock = Math.max(0, latest - lookback);

  const specs = [
    {
      address: manifest.contracts.GAME,
      topic: hre.ethers.id("TicketsQueued(address,uint24,uint32)"),
    },
    {
      address: manifest.contracts.GAME,
      topic: hre.ethers.id("BetPlaced(address,uint48,uint64,uint256)"),
    },
    {
      address: manifest.contracts.COINFLIP,
      topic: hre.ethers.id("CoinflipDeposit(address,uint256)"),
    },
    {
      address: manifest.contracts.AFFILIATE,
      topic: hre.ethers.id("ReferralUpdated(address,bytes32,address,bool)"),
    },
  ];
  const counts = new Map();

  for (let end = latest; end >= fromBlock; end -= chunk) {
    const start = Math.max(fromBlock, end - chunk + 1);
    for (const spec of specs) {
      let logs;
      try {
        logs = await hre.ethers.provider.getLogs({
          address: spec.address,
          fromBlock: start,
          toBlock: end,
          topics: [spec.topic],
        });
      } catch {
        continue;
      }

      for (const log of logs) {
        if (!log.topics[1]) continue;
        const addr = topicToAddress(log.topics[1]);
        if (addr === hre.ethers.ZeroAddress) continue;
        counts.set(addr, (counts.get(addr) || 0) + 1);
      }
    }

    if (counts.size >= minActors) {
      break;
    }
  }

  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

const describeIf = RUN_ACTOR_TESTS ? describe : describe.skip;

describeIf("Sepolia Actor Adversarial Suite", function () {
  this.timeout(600_000);

  let manifest;
  let actorCounts;
  let actors;
  let game;
  let admin;
  let vault;
  let coin;
  let coinflip;

  before(async function () {
    if (!FORK_URL) {
      throw new Error("Set HARDHAT_FORK_URL or RPC_URL for Sepolia fork tests.");
    }

    manifest = loadManifest();
    const forking = { jsonRpcUrl: FORK_URL };
    if (process.env.SEPOLIA_FORK_BLOCK) {
      forking.blockNumber = Number(process.env.SEPOLIA_FORK_BLOCK);
    }
    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [{ forking }],
    });

    actorCounts = loadActorCountsFromDb(manifest);
    if (actorCounts.length === 0) {
      actorCounts = await loadActorCountsFromEtherscan(manifest);
    }
    if (actorCounts.length === 0) {
      actorCounts = await loadActorCountsFromRpc(manifest);
    }
    actors = actorCounts.map(([addr]) => addr);
    if (actors.length === 0) {
      throw new Error(
        `No actors found for ${manifest.contracts.GAME}. ` +
          "Backfill events or increase SEPOLIA_ACTOR_LOOKBACK."
      );
    }

    game = await hre.ethers.getContractAt(
      [
        "function advanceDay() external",
        "function advanceDays(uint48 n) external",
        "function setAutoRebuy(address player, bool enabled) external",
        "function setDecimatorAutoRebuy(address player, bool enabled) external",
        "function isOperatorApproved(address owner, address operator) external view returns (bool)",
        "function afKingModeFor(address player) external view returns (bool)",
        "function autoRebuyEnabledFor(address player) external view returns (bool)",
        "function deityPassCountFor(address player) external view returns (uint16)",
        "function purchaseInfo() external view returns (uint24 lvl, bool inJackpotPhase, bool lastPurchaseDay, bool rngLocked, uint256 priceWei)",
      ],
      manifest.contracts.GAME
    );

    admin = await hre.ethers.getContractAt(
      ["function shutdownVrf() external"],
      manifest.contracts.ADMIN
    );

    vault = await hre.ethers.getContractAt(
      ["function burnCoin(address player, uint256 amount) external"],
      manifest.contracts.VAULT
    );

    coin = await hre.ethers.getContractAt(
      [
        "function vaultEscrow(uint256 amount) external",
        "function vaultMintTo(address to, uint256 amount) external",
      ],
      manifest.contracts.COIN
    );

    coinflip = await hre.ethers.getContractAt(
      [
        "event CoinflipStakeUpdated(address indexed player, uint48 indexed day, uint256 amount, uint256 newTotal)",
        "event QuestCompleted(address indexed player, uint8 questType, uint32 streak, uint256 reward)",
        "function depositCoinflip(address player, uint256 amount) external",
        "function processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch) external",
      ],
      manifest.contracts.COINFLIP
    );
  });

  it("discovers active real actors from Sepolia event history", function () {
    expect(actors.length).to.be.gte(1);
    expect(actorCounts[0][1]).to.be.gte(1);
  });

  it("blocks privileged pathways for top real actors", async function () {
    const system = systemAddressSet(manifest);
    const topActors = actors
      .filter((a) => !system.has(a.toLowerCase()))
      .slice(0, 3);
    if (topActors.length === 0) this.skip();

    for (const actor of topActors) {
      await withImpersonated(actor, async (signer) => {
        await expect(game.connect(signer).advanceDay()).to.be.reverted;
        await expect(game.connect(signer).advanceDays(2n)).to.be.reverted;
        await expect(admin.connect(signer).shutdownVrf()).to.be.reverted;
        await expect(vault.connect(signer).burnCoin(actor, 1n)).to.be.reverted;
      });
    }
  });

  it("prevents real actors from toggling other actors' settings without approval", async function () {
    if (actors.length < 2) this.skip();

    let pair = null;
    for (const attacker of actors.slice(0, 8)) {
      for (const victim of actors.slice(0, 8)) {
        if (attacker === victim) continue;
        const approved = await game.isOperatorApproved(victim, attacker);
        if (!approved) {
          pair = { attacker, victim };
          break;
        }
      }
      if (pair) break;
    }
    if (!pair) this.skip();

    await withImpersonated(pair.attacker, async (signer) => {
      await expect(
        game.connect(signer).setAutoRebuy(pair.victim, true)
      ).to.be.reverted;
      await expect(
        game.connect(signer).setDecimatorAutoRebuy(pair.victim, true)
      ).to.be.reverted;
    });
  });

  it("holds the non-deity recycling bonus cap for a real actor replay", async function () {
    let actor = null;
    for (const candidate of actors.slice(0, 16)) {
      if (await game.afKingModeFor(candidate)) continue;
      if (await game.autoRebuyEnabledFor(candidate)) continue;
      if ((await game.deityPassCountFor(candidate)) !== 0n) continue;
      actor = candidate;
      break;
    }
    if (!actor) this.skip();

    const info = await game.purchaseInfo();
    if (!info.inJackpotPhase && info.lastPurchaseDay && info.rngLocked) {
      this.skip();
    }

    const totalFunding = hre.ethers.parseEther("2000000");
    await withImpersonated(manifest.contracts.VAULT, async (vaultSigner) => {
      await coin.connect(vaultSigner).vaultEscrow(totalFunding);
      await coin.connect(vaultSigner).vaultMintTo(actor, totalFunding);
    });

    const firstStake = hre.ethers.parseEther("500000");
    const secondStake = hre.ethers.parseEther("200000");

    let targetDay;
    await withImpersonated(actor, async (actorSigner) => {
      const tx1 = await coinflip
        .connect(actorSigner)
        .depositCoinflip(ZERO_ADDRESS, firstStake);
      const rc1 = await tx1.wait();
      const ev1 = parseEvent(rc1, coinflip.interface, "CoinflipStakeUpdated");
      expect(ev1).to.not.equal(null);
      targetDay = ev1.args.day;
    });

    await withImpersonated(manifest.contracts.GAME, async (gameSigner) => {
      await coinflip
        .connect(gameSigner)
        .processCoinflipPayouts(false, 1n, targetDay);
    });

    await withImpersonated(actor, async (actorSigner) => {
      const tx2 = await coinflip
        .connect(actorSigner)
        .depositCoinflip(ZERO_ADDRESS, secondStake);
      const rc2 = await tx2.wait();
      const ev2 = parseEvent(rc2, coinflip.interface, "CoinflipStakeUpdated");
      expect(ev2).to.not.equal(null);

      const questEvents = parseEvents(rc2, coinflip.interface, "QuestCompleted");
      const questReward = questEvents.reduce(
        (sum, ev) => sum + ev.args.reward,
        0n
      );

      const observedBonus = ev2.args.amount - secondStake - questReward;
      expect(observedBonus).to.equal(1000n * BURNIE_UNIT);
    });
  });
});
