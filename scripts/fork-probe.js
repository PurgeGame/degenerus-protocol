// Mainnet-fork post-deploy probe.
//
// Runs AFTER scripts/deploy.js has deployed the full DEPLOY_ORDER against an
// anvil mainnet fork, and asserts the three external integrations that every
// mock-based run structurally cannot cover:
//
//   A. Chainlink VRF V2.5 — createSubscription/addConsumer already ran inside
//      DegenerusAdmin's constructor (a wrong-version coordinator reverts the
//      deploy outright), so here we verify the subscription state, fund it with
//      real LINK through the ERC-677 rail, and issue a real requestRandomWords.
//   B. The 300,000 callback budget — MockVRFCoordinator discards the request
//      struct and forwards ALL gas to rawFulfillRandomWords, so VRF_CALLBACK_GAS_LIMIT
//      has never been applied to anything. Here we deliver the callback from the
//      real coordinator address with EXACTLY that much gas.
//   C. Lido — _autoStakeExcessEth() submits the whole excess in one call at every
//      jackpot->purchase transition. MockStETH.submit() cannot revert; real Lido
//      reverts on STAKE_LIMIT and when paused, and the try/catch degradation path
//      has never executed on any deployed chain.
//   D. ENS — the constructor setName calls are one-shot and unrepeatable.
//
// Every check reports PASS/FAIL/SKIP independently so one run gives the whole
// picture rather than stopping at the first problem.
//
// Usage (see scripts/fork-run.sh, which orchestrates the whole thing):
//   npx hardhat run scripts/fork-probe.js --network localhost

import hre from "hardhat";
import { readdirSync, readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Real mainnet addresses. Overridable so the same probe runs against a fork of
// any chain that has these contracts.
const MAINNET = {
  LINK: process.env.LINK_TOKEN || "0x514910771AF9Ca656af840dff83E8264EcF986CA",
  STETH: process.env.STETH_TOKEN || "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  VRF_COORDINATOR: process.env.VRF_COORDINATOR,
  ENS_REVERSE_REGISTRAR: process.env.ENS_REVERSE_REGISTRAR,
};

// The callback budget the game requests. Must track
// DegenerusGameAdvanceModule.VRF_CALLBACK_GAS_LIMIT.
const VRF_CALLBACK_GAS_LIMIT = 300_000n;

const ZERO_BYTES32 =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

const results = [];
function record(id, status, detail) {
  results.push({ id, status, detail });
  const tag = { PASS: "  PASS", FAIL: "  FAIL", SKIP: "  SKIP", WARN: "  WARN" }[
    status
  ];
  console.log(`${tag}  ${id}${detail ? ` — ${detail}` : ""}`);
}

/**
 * Load the newest deployment manifest this fork run produced.
 */
function loadManifest() {
  const dir = resolve(__dirname, "../deployments");
  const network = hre.network.name;
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(`${network}-`) && f.endsWith(".json"))
    .sort();
  if (files.length === 0) {
    throw new Error(
      `No ${network}-*.json manifest in deployments/. Run scripts/deploy.js first.`
    );
  }
  const path = resolve(dir, files[files.length - 1]);
  console.log(`Manifest: ${path}\n`);
  return JSON.parse(readFileSync(path, "utf8"));
}

/**
 * Give `holder` a balance of an ERC-20 by locating its balance mapping slot and
 * writing storage directly. Brute-forces slots 0..12, which covers LINK (1) and
 * every mainstream layout, without depending on a whale whose balance drifts
 * block to block.
 */
async function dealToken(token, holder, amount) {
  const erc20 = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    token
  );
  const coder = hre.ethers.AbiCoder.defaultAbiCoder();
  for (let slot = 0; slot < 13; slot++) {
    const key = hre.ethers.keccak256(
      coder.encode(["address", "uint256"], [holder, slot])
    );
    const before = await hre.network.provider.send("eth_getStorageAt", [
      token,
      key,
      "latest",
    ]);
    await hre.network.provider.send("hardhat_setStorageAt", [
      token,
      key,
      hre.ethers.toBeHex(amount, 32),
    ]);
    if ((await erc20.balanceOf(holder)) === amount) return slot;
    // Not the balance slot — put it back before trying the next one.
    await hre.network.provider.send("hardhat_setStorageAt", [token, key, before]);
  }
  throw new Error(`Could not locate balance slot for ${token}`);
}

async function impersonate(addr, ethForGas = hre.ethers.parseEther("100")) {
  await hre.network.provider.send("hardhat_impersonateAccount", [addr]);
  await hre.network.provider.send("hardhat_setBalance", [
    addr,
    hre.ethers.toBeHex(ethForGas),
  ]);
  return await hre.ethers.getSigner(addr);
}

async function main() {
  const manifest = loadManifest();
  const c = manifest.contracts;
  const [deployer, alice, bob] = await hre.ethers.getSigners();

  const coordAddr = MAINNET.VRF_COORDINATOR;
  if (!coordAddr) {
    throw new Error(
      "VRF_COORDINATOR not set. This probe is meaningless without the REAL " +
        "V2.5 coordinator — that is the whole point of the fork run."
    );
  }

  console.log("=".repeat(72));
  console.log("  Mainnet-fork probe — real Chainlink / Lido / ENS");
  console.log("=".repeat(72));
  console.log(`  Coordinator: ${coordAddr}`);
  console.log(`  LINK:        ${MAINNET.LINK}`);
  console.log(`  stETH:       ${MAINNET.STETH}`);
  console.log(`  Block:       ${await hre.ethers.provider.getBlockNumber()}`);
  console.log("");

  const game = await hre.ethers.getContractAt("DegenerusGame", c.GAME);
  const admin = await hre.ethers.getContractAt("DegenerusAdmin", c.ADMIN);

  // ── A. VRF subscription state ────────────────────────────────────────────
  console.log("A. Chainlink VRF V2.5 subscription");
  let subId;
  try {
    subId = await admin.subscriptionId();
    if (subId === 0n) {
      record("A1 subscription created", "FAIL", "subscriptionId is 0");
    } else {
      record("A1 subscription created", "PASS", `subId=${subId}`);
    }
  } catch (e) {
    record("A1 subscription created", "FAIL", e.shortMessage || e.message);
  }

  const coordinator = await hre.ethers.getContractAt(
    [
      "function getSubscription(uint256) view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] consumers)",
      "event RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed, uint256 indexed subId, uint16 minimumRequestConfirmations, uint32 callbackGasLimit, uint32 numWords, bytes extraArgs, address indexed sender)",
    ],
    coordAddr
  );

  if (subId) {
    try {
      const sub = await coordinator.getSubscription(subId);
      const consumers = sub.consumers.map((a) => a.toLowerCase());
      if (consumers.includes(c.GAME.toLowerCase())) {
        record("A2 GAME is a consumer", "PASS", `${consumers.length} consumer(s)`);
      } else {
        record("A2 GAME is a consumer", "FAIL", `consumers=${consumers}`);
      }
      if (sub.owner.toLowerCase() === c.ADMIN.toLowerCase()) {
        record("A3 ADMIN owns the sub", "PASS");
      } else {
        record("A3 ADMIN owns the sub", "WARN", `owner=${sub.owner}`);
      }
    } catch (e) {
      record("A2 GAME is a consumer", "FAIL", e.shortMessage || e.message);
    }
  }

  // ── A4. Fund the subscription with real LINK via the ERC-677 rail ────────
  const linkAmount = hre.ethers.parseEther("100");
  try {
    await dealToken(MAINNET.LINK, deployer.address, linkAmount);
    const link = await hre.ethers.getContractAt(
      [
        "function transferAndCall(address,uint256,bytes) returns (bool)",
        "function balanceOf(address) view returns (uint256)",
      ],
      MAINNET.LINK
    );
    // DegenerusAdmin.onTokenTransfer forwards to the coordinator subscription.
    await (
      await link.connect(deployer).transferAndCall(c.ADMIN, linkAmount, "0x")
    ).wait();
    const sub = await coordinator.getSubscription(subId);
    if (sub.balance > 0n) {
      record(
        "A4 LINK funding rail",
        "PASS",
        `sub balance=${hre.ethers.formatEther(sub.balance)} LINK`
      );
    } else {
      record("A4 LINK funding rail", "FAIL", "sub balance still 0");
    }
  } catch (e) {
    record("A4 LINK funding rail", "FAIL", e.shortMessage || e.message);
  }

  // ── Drive the game to a real VRF request ─────────────────────────────────
  console.log("\nB. Real requestRandomWords + the 300k callback budget");
  let requestId = null;
  let requestedCallbackGas = null;
  try {
    const price = await game.mintPrice();
    const costFor = (qty) => (price * BigInt(qty)) / 400n;
    await (
      await game
        .connect(deployer)
        .purchase(deployer.address, 400, 0, ZERO_BYTES32, 0, false, {
          value: costFor(400),
        })
    ).wait();
    if (alice) {
      await (
        await game
          .connect(alice)
          .purchase(alice.address, 200, 0, ZERO_BYTES32, 0, false, {
            value: costFor(200),
          })
      ).wait();
    }
    if (bob) {
      await (
        await game
          .connect(bob)
          .purchase(bob.address, 100, 0, ZERO_BYTES32, 0, false, {
            value: costFor(100),
          })
      ).wait();
    }

    await hre.network.provider.send("evm_increaseTime", [86400]);
    await hre.network.provider.send("evm_mine", []);

    const rc = await (await game.connect(deployer).advanceGame()).wait();

    // Pull the requestId straight out of the REAL coordinator's event.
    for (const log of rc.logs) {
      if (log.address.toLowerCase() !== coordAddr.toLowerCase()) continue;
      try {
        const parsed = coordinator.interface.parseLog(log);
        if (parsed?.name === "RandomWordsRequested") {
          requestId = parsed.args.requestId;
          requestedCallbackGas = parsed.args.callbackGasLimit;
          break;
        }
      } catch {}
    }

    if (requestId !== null) {
      record(
        "B1 real requestRandomWords",
        "PASS",
        `requestId=${requestId}, callbackGasLimit=${requestedCallbackGas}`
      );
      if (BigInt(requestedCallbackGas) !== VRF_CALLBACK_GAS_LIMIT) {
        record(
          "B2 callbackGasLimit as coded",
          "WARN",
          `coordinator saw ${requestedCallbackGas}, expected ${VRF_CALLBACK_GAS_LIMIT}`
        );
      } else {
        record("B2 callbackGasLimit as coded", "PASS");
      }
    } else {
      record(
        "B1 real requestRandomWords",
        "FAIL",
        "no RandomWordsRequested event from the coordinator"
      );
    }
  } catch (e) {
    record("B1 real requestRandomWords", "FAIL", e.shortMessage || e.message);
  }

  // ── B3. THE assertion: deliver the callback with exactly 300,000 gas ─────
  //
  // Real Chainlink calls rawFulfillRandomWords inside a gas-limited call and
  // does NOT revert if it fails — it emits RandomWordsFulfilled(success:false),
  // charges the subscription, and consumes the request. The word never lands,
  // rngLockedFlag stays set, and the 12h retry re-requests into the same wall.
  // MockVRFCoordinator does the opposite (all gas + require(ok)), so this is the
  // single most important thing a fork run buys you.
  if (requestId !== null) {
    try {
      const coordSigner = await impersonate(coordAddr);
      const word =
        98765432101234567890123456789012345678901234567890123456789012345n %
        (2n ** 256n);
      const tx = await game
        .connect(coordSigner)
        .rawFulfillRandomWords(requestId, [word], {
          gasLimit: VRF_CALLBACK_GAS_LIMIT,
        });
      const rc = await tx.wait();
      const headroom = VRF_CALLBACK_GAS_LIMIT - rc.gasUsed;
      const pct = (Number(rc.gasUsed) / Number(VRF_CALLBACK_GAS_LIMIT)) * 100;
      if (rc.status === 1) {
        record(
          "B3 callback fits in 300k",
          headroom < 30_000n ? "WARN" : "PASS",
          `gasUsed=${rc.gasUsed} (${pct.toFixed(1)}% of budget, ${headroom} spare)`
        );
      } else {
        record("B3 callback fits in 300k", "FAIL", "callback reverted");
      }
    } catch (e) {
      record(
        "B3 callback fits in 300k",
        "FAIL",
        `${e.shortMessage || e.message} — on mainnet this is a SILENT stall, not a revert`
      );
    }
  } else {
    record("B3 callback fits in 300k", "SKIP", "no requestId to fulfill");
  }

  // ── C. Lido ──────────────────────────────────────────────────────────────
  console.log("\nC. Lido auto-stake (_autoStakeExcessEth, every level)");
  const steth = await hre.ethers.getContractAt(
    [
      "function balanceOf(address) view returns (uint256)",
      "function getCurrentStakeLimit() view returns (uint256)",
      "function isStakingPaused() view returns (bool)",
    ],
    MAINNET.STETH
  );
  try {
    const paused = await steth.isStakingPaused();
    const limit = await steth.getCurrentStakeLimit();
    record(
      "C1 Lido reachable",
      "PASS",
      `stakingPaused=${paused}, currentStakeLimit=${hre.ethers.formatEther(limit)} ETH`
    );
  } catch (e) {
    record("C1 Lido reachable", "FAIL", e.shortMessage || e.message);
  }

  try {
    // Drain the RNG lock so the game reaches a jackpot->purchase transition,
    // which is where _processPhaseTransition calls _autoStakeExcessEth.
    let drains = 0;
    for (let i = 0; i < 40; i++) {
      if (!(await game.rngLocked())) break;
      await (await game.connect(deployer).advanceGame()).wait();
      drains++;
    }
    const stBal = await steth.balanceOf(c.GAME);
    if (stBal > 0n) {
      record(
        "C2 real stETH minted to GAME",
        "PASS",
        `${hre.ethers.formatEther(stBal)} stETH after ${drains} drain call(s)`
      );
    } else {
      record(
        "C2 real stETH minted to GAME",
        "WARN",
        `0 stETH after ${drains} drain call(s) — either no excess above claimablePool ` +
          `yet, or submit() reverted into the try/catch (check for StEthStakeFailed)`
      );
    }
  } catch (e) {
    record("C2 real stETH minted to GAME", "FAIL", e.shortMessage || e.message);
  }

  // ── D. ENS ───────────────────────────────────────────────────────────────
  console.log("\nD. ENS reverse names (constructor-only, one shot)");
  if (!MAINNET.ENS_REVERSE_REGISTRAR) {
    record(
      "D1 reverse name set",
      "SKIP",
      "ENS_REVERSE_REGISTRAR unset — constructors skipped setName entirely"
    );
  } else {
    try {
      const registrar = await hre.ethers.getContractAt(
        ["function node(address) view returns (bytes32)"],
        MAINNET.ENS_REVERSE_REGISTRAR
      );
      const registry = await hre.ethers.getContractAt(
        ["function resolver(bytes32) view returns (address)"],
        "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
      );
      const node = await registrar.node(c.GAME);
      const resolverAddr = await registry.resolver(node);
      if (resolverAddr === hre.ethers.ZeroAddress) {
        record("D1 reverse name set", "FAIL", "no resolver on GAME's reverse node");
      } else {
        const resolver = await hre.ethers.getContractAt(
          ["function name(bytes32) view returns (string)"],
          resolverAddr
        );
        const nm = await resolver.name(node);
        record(
          "D1 reverse name set",
          nm ? "PASS" : "FAIL",
          nm ? `GAME -> "${nm}"` : "empty name record"
        );
      }
    } catch (e) {
      record("D1 reverse name set", "FAIL", e.shortMessage || e.message);
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  const fails = results.filter((r) => r.status === "FAIL");
  const warns = results.filter((r) => r.status === "WARN");
  console.log("\n" + "=".repeat(72));
  console.log(
    `  ${results.filter((r) => r.status === "PASS").length} pass, ` +
      `${fails.length} fail, ${warns.length} warn, ` +
      `${results.filter((r) => r.status === "SKIP").length} skip`
  );
  console.log("=".repeat(72));
  if (fails.length) {
    console.log("\nFAILURES:");
    for (const f of fails) console.log(`  - ${f.id}: ${f.detail}`);
    process.exitCode = 1;
  }
  if (warns.length) {
    console.log("\nWARNINGS:");
    for (const w of warns) console.log(`  - ${w.id}: ${w.detail}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
