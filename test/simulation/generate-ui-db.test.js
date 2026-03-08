import hre from "hardhat";
import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { PlayerManager } from "../helpers/player-manager.js";
import { StatsTracker } from "../helpers/stats-tracker.js";
import {
  getLastVRFRequestId,
  fulfillVRF,
} from "../helpers/testUtils.js";

const { ethers, network } = hre;

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, "..", "..");
const JACKPOT_RESET_TIME = 82620n;
const TARGET_LEVEL = 10;

// =========================================================================
// Helpers (from simulation-5-levels.test.js)
// =========================================================================

function createRng(seed) {
  let state = BigInt(ethers.keccak256(ethers.toUtf8Bytes(seed)));
  const mask = (1n << 256n) - 1n;
  const next = () => {
    state ^= (state << 7n) & mask;
    state ^= state >> 9n;
    state ^= (state << 8n) & mask;
    return state & mask;
  };
  return { next };
}

function jackpotTimestamp(deployDayBoundary, dayIndex) {
  return (
    (BigInt(deployDayBoundary) + BigInt(dayIndex) - 1n) * 86400n +
    JACKPOT_RESET_TIME +
    1n
  );
}

async function warpToDayBoundary(deployDayBoundary, dayIndex) {
  const targetTs = jackpotTimestamp(deployDayBoundary, dayIndex);
  const block = await ethers.provider.getBlock("latest");
  const currentTs = BigInt(block.timestamp);
  const nextTs = targetTs > currentTs ? targetTs : currentTs + 1n;
  await network.provider.send("evm_setNextBlockTimestamp", [Number(nextTs)]);
  await network.provider.send("evm_mine");
}

async function fulfillVrfCycle(mockVRF, rng) {
  try {
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      const word = rng.next();
      await fulfillVRF(mockVRF, requestId, word);
      return true;
    }
  } catch {}
  return false;
}

// =========================================================================
// Module artifact paths for building merged GAME ABI
// =========================================================================

const MODULE_ARTIFACTS = [
  "modules/DegenerusGameAdvanceModule.sol/DegenerusGameAdvanceModule.json",
  "modules/DegenerusGameBoonModule.sol/DegenerusGameBoonModule.json",
  "modules/DegenerusGameDecimatorModule.sol/DegenerusGameDecimatorModule.json",
  "modules/DegenerusGameDegeneretteModule.sol/DegenerusGameDegeneretteModule.json",
  "modules/DegenerusGameEndgameModule.sol/DegenerusGameEndgameModule.json",
  "modules/DegenerusGameGameOverModule.sol/DegenerusGameGameOverModule.json",
  "modules/DegenerusGameJackpotModule.sol/DegenerusGameJackpotModule.json",
  "modules/DegenerusGameLootboxModule.sol/DegenerusGameLootboxModule.json",
  "modules/DegenerusGameMintModule.sol/DegenerusGameMintModule.json",
  "modules/DegenerusGameWhaleModule.sol/DegenerusGameWhaleModule.json",
];

const CONTRACT_ARTIFACTS = {
  COIN: "BurnieCoin.sol/BurnieCoin.json",
  COINFLIP: "BurnieCoinflip.sol/BurnieCoinflip.json",
  VAULT: "DegenerusVault.sol/DegenerusVault.json",
  AFFILIATE: "DegenerusAffiliate.sol/DegenerusAffiliate.json",
  JACKPOTS: "DegenerusJackpots.sol/DegenerusJackpots.json",
  QUESTS: "DegenerusQuests.sol/DegenerusQuests.json",
  DGNRS: "DegenerusStonk.sol/DegenerusStonk.json",
  ADMIN: "DegenerusAdmin.sol/DegenerusAdmin.json",
  DEITY_PASS: "DegenerusDeityPass.sol/DegenerusDeityPass.json",
  WWXRP: "WrappedWrappedXRP.sol/WrappedWrappedXRP.json",
};

function loadArtifact(relativePath) {
  const fullPath = path.join(
    PROJECT_ROOT,
    "artifacts",
    "contracts",
    relativePath
  );
  if (!fs.existsSync(fullPath)) return null;
  return JSON.parse(fs.readFileSync(fullPath, "utf8"));
}

function buildGameMergedAbi() {
  const gameArtifact = loadArtifact(
    "DegenerusGame.sol/DegenerusGame.json"
  );
  if (!gameArtifact) throw new Error("DegenerusGame artifact not found");

  const mergedAbi = [...gameArtifact.abi];
  const seenSigs = new Set();

  for (const item of mergedAbi) {
    if (item.type === "event") {
      const types = item.inputs.map((i) => i.type).join(",");
      seenSigs.add(`${item.name}(${types})`);
    }
  }

  for (const modulePath of MODULE_ARTIFACTS) {
    const artifact = loadArtifact(modulePath);
    if (!artifact) continue;
    for (const item of artifact.abi.filter((a) => a.type === "event")) {
      const types = item.inputs.map((i) => i.type).join(",");
      const sig = `${item.name}(${types})`;
      if (!seenSigs.has(sig)) {
        seenSigs.add(sig);
        mergedAbi.push(item);
      }
    }
  }

  return mergedAbi;
}

// =========================================================================
// SQLite event capture
// =========================================================================

function createEventsDb(dbPath) {
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = NORMAL");
  db.exec(`
    CREATE TABLE IF NOT EXISTS events (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      block_number    INTEGER NOT NULL,
      tx_hash         TEXT NOT NULL,
      log_index       INTEGER NOT NULL,
      contract_address TEXT NOT NULL,
      contract_name   TEXT,
      event_name      TEXT,
      event_signature TEXT,
      decoded_args    TEXT,
      block_timestamp INTEGER,
      UNIQUE(tx_hash, log_index)
    );
    CREATE INDEX IF NOT EXISTS idx_events_block ON events(block_number);
    CREATE INDEX IF NOT EXISTS idx_events_contract ON events(contract_address);
    CREATE INDEX IF NOT EXISTS idx_events_name ON events(event_name);

    CREATE TABLE IF NOT EXISTS event_indexed_args (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id    INTEGER NOT NULL REFERENCES events(id),
      arg_name    TEXT NOT NULL,
      arg_value   TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_indexed_args_event ON event_indexed_args(event_id);
    CREATE INDEX IF NOT EXISTS idx_indexed_args_value ON event_indexed_args(arg_name, arg_value);

    CREATE TABLE IF NOT EXISTS sync_state (
      id                    INTEGER PRIMARY KEY CHECK (id = 1),
      last_processed_block  INTEGER NOT NULL DEFAULT 0,
      updated_at            TEXT DEFAULT (datetime('now'))
    );
    INSERT OR IGNORE INTO sync_state (id, last_processed_block) VALUES (1, 0);

    CREATE TABLE IF NOT EXISTS contracts (
      address   TEXT PRIMARY KEY,
      name      TEXT NOT NULL,
      abi_hash  TEXT
    );

    CREATE TABLE IF NOT EXISTS game_state (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      block_number  INTEGER NOT NULL,
      level         INTEGER,
      jackpot_phase INTEGER,
      game_over     INTEGER,
      mint_price    TEXT,
      current_pool  TEXT,
      next_pool     TEXT,
      future_pool   TEXT,
      claimable_pool TEXT,
      rng_locked    INTEGER,
      snapshot_at   TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS player_state (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      block_number    INTEGER NOT NULL,
      player_address  TEXT NOT NULL,
      eth_balance     TEXT,
      burnie_balance  TEXT,
      activity_score  INTEGER,
      mint_streak     INTEGER,
      claimable       TEXT,
      dgnrs_balance   TEXT,
      wwxrp_balance   TEXT,
      snapshot_at     TEXT DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_player_state_addr ON player_state(player_address);

    CREATE TABLE IF NOT EXISTS actor_log (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      actor_name  TEXT NOT NULL,
      action      TEXT NOT NULL,
      tx_hash     TEXT,
      success     INTEGER NOT NULL,
      gas_used    INTEGER,
      error_msg   TEXT,
      logged_at   TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS token_ownership (
      token_id    INTEGER PRIMARY KEY,
      owner       TEXT NOT NULL,
      burned      INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS queued_tickets (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      player_address  TEXT NOT NULL,
      target_level    INTEGER NOT NULL,
      source          TEXT NOT NULL,
      quantity_scaled INTEGER NOT NULL,
      tx_hash         TEXT NOT NULL,
      block_number    INTEGER NOT NULL,
      log_index       INTEGER NOT NULL,
      UNIQUE(tx_hash, log_index, source)
    );
    CREATE INDEX IF NOT EXISTS idx_qt_player_level ON queued_tickets(player_address, target_level);

    CREATE TABLE IF NOT EXISTS trait_entries (
      player_address  TEXT NOT NULL,
      level           INTEGER NOT NULL,
      trait_id        INTEGER NOT NULL,
      count           INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (player_address, level, trait_id)
    );
    CREATE INDEX IF NOT EXISTS idx_te_level_trait ON trait_entries(level, trait_id);
  `);
  return db;
}

/**
 * Capture all events from the hardhat provider and write to SQLite.
 */
async function captureAllEvents(db, addressIndex, contractAddresses) {
  const latestBlock = await ethers.provider.getBlockNumber();
  console.log(`  Capturing events from blocks 0-${latestBlock}...`);

  // Fetch all logs for all tracked contract addresses
  const logs = await ethers.provider.getLogs({
    fromBlock: 0,
    toBlock: latestBlock,
    address: contractAddresses,
  });

  console.log(`  Found ${logs.length} raw logs`);

  const insertEvent = db.prepare(`
    INSERT OR IGNORE INTO events
      (block_number, tx_hash, log_index, contract_address, contract_name,
       event_name, event_signature, decoded_args, block_timestamp)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertIndexedArg = db.prepare(
    "INSERT INTO event_indexed_args (event_id, arg_name, arg_value) VALUES (?, ?, ?)"
  );

  let decoded = 0;
  let failed = 0;

  const tx = db.transaction(() => {
    for (const log of logs) {
      const addrLower = log.address.toLowerCase();
      const entry = addressIndex.get(addrLower);
      if (!entry) {
        failed++;
        continue;
      }

      let eventName = null;
      let eventSig = null;
      let decodedArgs = null;
      let indexedArgs = null;

      try {
        const parsed = entry.iface.parseLog({
          topics: log.topics,
          data: log.data,
        });
        if (parsed) {
          eventName = parsed.name;
          eventSig = parsed.signature;
          decodedArgs = {};
          indexedArgs = {};
          for (let i = 0; i < parsed.fragment.inputs.length; i++) {
            const input = parsed.fragment.inputs[i];
            let value = parsed.args[i];
            if (typeof value === "bigint") value = value.toString();
            else if (Array.isArray(value))
              value = value.map((v) =>
                typeof v === "bigint" ? v.toString() : v
              );
            decodedArgs[input.name] = value;
            if (input.indexed) indexedArgs[input.name] = String(value);
          }
          decoded++;
        }
      } catch {
        failed++;
      }

      const result = insertEvent.run(
        log.blockNumber,
        log.transactionHash,
        log.index,
        log.address,
        entry.name,
        eventName,
        eventSig,
        decodedArgs ? JSON.stringify(decodedArgs) : null,
        null
      );

      if (result.changes > 0 && indexedArgs) {
        for (const [name, value] of Object.entries(indexedArgs)) {
          insertIndexedArg.run(result.lastInsertRowid, name, String(value));
        }
      }
    }
  });

  tx();

  // Update sync state
  db.prepare(
    "UPDATE sync_state SET last_processed_block = ?, updated_at = datetime('now') WHERE id = 1"
  ).run(latestBlock);

  console.log(`  Decoded: ${decoded}, Failed/unknown: ${failed}`);
  return { total: logs.length, decoded, failed };
}

// =========================================================================
// Test
// =========================================================================

describe("Generate UI Database", function () {
  this.timeout(1_200_000); // 20 minutes

  after(function () {
    restoreAddresses();
  });

  it("runs 10-level sim with diverse activity and exports DB", async function () {
    await network.provider.send("hardhat_reset");

    // =================================================================
    // 1. Deploy
    // =================================================================
    console.log("Deploying contracts...");
    const fixture = await deployFullProtocol();

    const contracts = {
      game: fixture.game,
      coin: fixture.coin,
      coinflip: fixture.coinflip,
      affiliate: fixture.affiliate,
      mockVRF: fixture.mockVRF,
      admin: fixture.admin,
      vault: fixture.vault,
      dgnrs: fixture.dgnrs,
      deityPass: fixture.deityPass,
      wwxrp: fixture.wwxrp,
      quests: fixture.quests,
      jackpots: fixture.jackpots,
    };

    const caller = fixture.deployer;
    const rng = createRng("ui-db-10-levels");

    // =================================================================
    // 2. Initialize players
    // =================================================================
    console.log("Initializing players...");
    await warpToDayBoundary(fixture.deployDayBoundary, 1);

    const signers = await ethers.getSigners();
    const players = new PlayerManager({
      signers,
      contracts,
      stats: null,
    });
    await players.initPlayers();

    const stats = new StatsTracker(players.players);
    players.stats = stats;

    console.log("Players pre-funded by Hardhat (10,000 ETH each)");

    // =================================================================
    // 3. Setup referrals & BURNIE
    // =================================================================
    console.log("Setting up referrals...");
    await players.setupReferrals();

    console.log("Minting BURNIE to all players...");
    await players.mintBurnieToAll(ethers.parseEther("10000000"));

    // =================================================================
    // 4. Bootstrap game state
    // =================================================================
    console.log("Bootstrapping game state...");
    await warpToDayBoundary(fixture.deployDayBoundary, 2);

    try {
      await contracts.game.connect(caller).advanceGame();
    } catch {}

    for (let i = 0; i < 50; i++) {
      const fulfilled = await contracts.game.isRngFulfilled();
      if (!fulfilled) {
        await fulfillVrfCycle(contracts.mockVRF, rng);
      }
      const inJackpotPhase = await contracts.game.jackpotPhase();
      if (!inJackpotPhase) {
        console.log(
          `Game initialized to PURCHASE state after ${i + 1} iterations`
        );
        break;
      }
      try {
        await contracts.game.connect(caller).advanceGame();
      } catch {}
    }

    // =================================================================
    // 5. Purchase deity passes (players 0-5)
    // =================================================================
    console.log("Purchasing deity passes...");
    const gameAddr = await contracts.game.getAddress();
    for (let i = 0; i <= 5; i++) {
      const symbolId = i;
      try {
        // Exact price: 24 ETH + k*(k+1)/2 ETH where k = passes already sold
        const k = BigInt(i);
        const price = ethers.parseEther("24") + (k * (k + 1n) * ethers.parseEther("1")) / 2n;
        await contracts.game
          .connect(players.getPlayer(i).signer)
          .purchaseDeityPass(ethers.ZeroAddress, symbolId, { value: price });
        console.log(`  Player ${i} bought deity pass #${symbolId} for ${ethers.formatEther(price)} ETH`);
      } catch (e) {
        console.log(`  Player ${i} deity pass failed: ${e.shortMessage || e.message?.split('\n')[0]}`);
      }
    }

    // =================================================================
    // 6. Purchase whale bundles (players 10-14)
    // =================================================================
    console.log("Purchasing whale bundles...");
    const whalePrice = ethers.parseEther("2.4");
    for (let i = 10; i <= 14; i++) {
      try {
        await contracts.game
          .connect(players.getPlayer(i).signer)
          .purchaseWhaleBundle(ethers.ZeroAddress, 1, { value: whalePrice });
        console.log(`  Player ${i} bought whale bundle`);
      } catch (e) {
        console.log(`  Player ${i} whale bundle failed: ${e.shortMessage || e.message?.split('\n')[0]}`);
      }
    }

    // =================================================================
    // 7. Main simulation loop: 10 levels
    // =================================================================
    // Build merged game interface for parsing module events (BetPlaced etc.)
    const mergedGameAbiForSim = buildGameMergedAbi();
    const mergedGameIface = new ethers.Interface(mergedGameAbiForSim);

    const initialPrice = await contracts.game.mintPrice();
    console.log(`\n${"=".repeat(70)}`);
    console.log(`SIMULATION: ${TARGET_LEVEL} levels`);
    console.log(`Initial Mint Price: ${ethers.formatEther(initialPrice)} ETH`);
    console.log("=".repeat(70));

    let currentDay = 2;
    const levelStartDays = { 1: currentDay };
    let pendingDegeneretteBets = []; // track { player, betId } for resolution
    let pendingLootboxes = []; // track { playerIndex, lootboxIndex } for deferred opens

    while (true) {
      const currentLevel = Number(await contracts.game.level());
      const inJackpotPhase = await contracts.game.jackpotPhase();
      const gameOver = await contracts.game.gameOver();

      if (currentLevel > TARGET_LEVEL || currentDay > 600 || gameOver) {
        console.log(
          `\nStopping: level=${currentLevel}, day=${currentDay}, gameOver=${gameOver}`
        );
        break;
      }

      currentDay++;
      await warpToDayBoundary(fixture.deployDayBoundary, currentDay);

      // ---- Advance game cycle ----
      for (let i = 0; i < 50; i++) {
        const rngLocked = await contracts.game.rngLocked();
        const rngFulfilled = await contracts.game.isRngFulfilled();

        if (rngLocked && !rngFulfilled) {
          await fulfillVrfCycle(contracts.mockVRF, rng);
          continue;
        }

        try {
          await contracts.game.connect(caller).advanceGame();
        } catch (e) {
          const msg = e?.shortMessage || e?.message?.split("\n")[0] || "";
          if (msg.includes("NotTimeYet")) break;
        }

        const newLevel = Number(await contracts.game.level());
        if (newLevel !== currentLevel && !levelStartDays[newLevel]) {
          levelStartDays[newLevel] = currentDay;
          const newPrice = await contracts.game.mintPrice();
          console.log(
            `\n*** LEVEL ${currentLevel} -> ${newLevel} on day ${currentDay} (price: ${ethers.formatEther(newPrice)} ETH) ***`
          );
        }
      }

      // ---- Check if we can do actions ----
      const rngLocked = await contracts.game.rngLocked();
      const inJackpotPhaseNow = await contracts.game.jackpotPhase();
      const gameOverNow = await contracts.game.gameOver();
      const level = Number(await contracts.game.level());

      if (rngLocked || inJackpotPhaseNow || gameOverNow || level > TARGET_LEVEL)
        continue;

      const target = await contracts.game.prizePoolTargetView();

      // ---- Deity players (0-9): Aggressive tickets ----
      for (let p = 0; p <= 9; p++) {
        const currentPool = await contracts.game.nextPrizePoolView();
        if (currentPool >= target) break;
        await players.purchaseTickets({ playerIndex: p, ticketCount: 200n });
      }

      // ---- Whale players (10-14): Moderate tickets ----
      for (let p = 10; p <= 14; p++) {
        const currentPool = await contracts.game.nextPrizePoolView();
        if (currentPool >= target) break;
        await players.purchaseTickets({ playerIndex: p, ticketCount: 100n });
      }

      // ---- Conservative players (15-19): Cautious tickets ----
      for (let p = 15; p <= 19; p++) {
        const currentPool = await contracts.game.nextPrizePoolView();
        if (currentPool >= target) break;
        await players.purchaseTickets({ playerIndex: p, ticketCount: 50n });
      }

      // ---- Open pending lootboxes (from previous day, after VRF cycle) ----
      if (pendingLootboxes.length > 0) {
        const toOpen = [...pendingLootboxes];
        pendingLootboxes = [];
        for (const { playerIndex: p, lootboxIndex: idx } of toOpen) {
          try {
            await players.openLootbox({ playerIndex: p, lootboxIndex: idx });
          } catch {
            // RNG word may still not be available, re-queue
            pendingLootboxes.push({ playerIndex: p, lootboxIndex: idx });
          }
        }
      }

      // ---- Lootbox purchases (every 3rd day, players 2-4) ----
      // Buy tickets + lootbox together via purchase() (lootbox-only reverts E() in some states)
      if (currentDay % 3 === 0) {
        const mintPrice = await contracts.game.mintPrice();
        for (let p = 2; p <= 4; p++) {
          const lootboxAmt = ethers.parseEther((0.1 + p * 0.05).toFixed(2));
          const ticketQty = 100n; // 1 full ticket
          const ticketCost = (mintPrice * ticketQty) / 400n;
          const totalValue = ticketCost + lootboxAmt;
          try {
            const lbIdx = await contracts.game.lootboxRngIndexView();
            await contracts.game
              .connect(players.getPlayer(p).signer)
              .purchase(
                players.getPlayer(p).signer.address,
                ticketQty,
                lootboxAmt,
                ethers.ZeroHash,
                0, // DirectEth
                { value: totalValue }
              );
            pendingLootboxes.push({ playerIndex: p, lootboxIndex: lbIdx });
          } catch (e) {
            console.log(`  lootbox failed (player ${p}): ${e.shortMessage || e.message?.split('\n')[0]}`);
          }
        }
      }

      // ---- Coinflip deposits (every 2nd day, whale + conservative) ----
      // Coinflip burns BURNIE tokens, minimum 100 BURNIE (100e18)
      if (currentDay % 2 === 0) {
        for (let p = 10; p <= 17; p++) {
          const flipAmt = ethers.parseEther("500");
          try {
            await players.depositCoinflip({
              playerIndex: p,
              amount: flipAmt,
              targetDay: currentDay,
            });
          } catch {}
        }
      }

      // ---- Resolve pending degenerette bets (after VRF cycle above) ----
      if (pendingDegeneretteBets.length > 0) {
        const toResolve = [...pendingDegeneretteBets];
        pendingDegeneretteBets = [];
        for (const { player: p, betId } of toResolve) {
          try {
            await contracts.game
              .connect(players.getPlayer(p).signer)
              .resolveDegeneretteBets(ethers.ZeroAddress, [betId]);
          } catch {
            // RNG may not be available yet, re-queue
            pendingDegeneretteBets.push({ player: p, betId });
          }
        }
      }

      // ---- Degenerette bets (every 4th day, players 5-8) ----
      if (currentDay % 4 === 0) {
        for (let p = 5; p <= 8; p++) {
          try {
            // ETH bet: 0.01 ETH per ticket, 3 tickets
            const betAmount = ethers.parseEther("0.01");
            const tx = await contracts.game
              .connect(players.getPlayer(p).signer)
              .placeFullTicketBets(
                ethers.ZeroAddress,
                0, // currency ETH
                betAmount,
                3, // ticketCount
                0, // customTicket (0 = random)
                0xff // no hero
              , { value: betAmount * 3n });
            const receipt = await tx.wait();
            // Extract betId from BetPlaced event
            for (const log of receipt.logs) {
              try {
                const parsed = mergedGameIface.parseLog(log);
                if (parsed && parsed.name === "BetPlaced") {
                  pendingDegeneretteBets.push({
                    player: p,
                    betId: parsed.args.betId,
                  });
                }
              } catch {}
            }
          } catch {}
        }

        // Also BURNIE bets from players 6-7
        for (let p = 6; p <= 7; p++) {
          try {
            const burnieBet = ethers.parseEther("200"); // 200 BURNIE per ticket
            // Approve BURNIE spending
            await contracts.coin
              .connect(players.getPlayer(p).signer)
              .approve(gameAddr, burnieBet * 3n);
            const tx = await contracts.game
              .connect(players.getPlayer(p).signer)
              .placeFullTicketBets(
                ethers.ZeroAddress,
                1, // currency BURNIE
                burnieBet,
                2, // ticketCount
                0,
                0xff
              );
            const receipt = await tx.wait();
            for (const log of receipt.logs) {
              try {
                const parsed = mergedGameIface.parseLog(log);
                if (parsed && parsed.name === "BetPlaced") {
                  pendingDegeneretteBets.push({
                    player: p,
                    betId: parsed.args.betId,
                  });
                }
              } catch {}
            }
          } catch {}
        }
      }

      // ---- Progress report ----
      if (currentDay % 5 === 0) {
        const currentPool = await contracts.game.nextPrizePoolView();
        const pct = target > 0n ? (currentPool * 100n) / target : 0n;
        console.log(
          `Day ${currentDay}: Level ${level}, Pool ${ethers.formatEther(currentPool)}/${ethers.formatEther(target)} ETH (${pct}%)`
        );
      }
    }

    // Resolve any remaining degenerette bets
    for (const { player: p, betId } of pendingDegeneretteBets) {
      try {
        await contracts.game
          .connect(players.getPlayer(p).signer)
          .resolveDegeneretteBets(ethers.ZeroAddress, [betId]);
      } catch {}
    }

    console.log("\n" + "=".repeat(70));
    console.log("SIMULATION COMPLETE");
    console.log("=".repeat(70));

    const finalLevel = Number(await contracts.game.level());
    console.log(`Final Level: ${finalLevel}`);
    console.log(`Total Days: ${currentDay}`);

    // =================================================================
    // 8. Capture events and build databases
    // =================================================================
    console.log("\n" + "=".repeat(70));
    console.log("CAPTURING EVENTS TO DATABASE");
    console.log("=".repeat(70));

    // Create run directory
    const runTs = new Date()
      .toISOString()
      .replace(/[:.]/g, "-")
      .slice(0, 19);
    const runDir = path.join(PROJECT_ROOT, "runs", runTs);
    fs.mkdirSync(runDir, { recursive: true });
    console.log(`Run directory: ${runDir}`);

    // Build address index (contract address -> { name, iface })
    const addressIndex = new Map();
    const contractAddresses = [];

    // GAME gets merged ABI (own events + all module events via delegatecall)
    const gameAddress = await contracts.game.getAddress();
    const mergedGameAbi = buildGameMergedAbi();
    const gameIface = new ethers.Interface(mergedGameAbi);
    addressIndex.set(gameAddress.toLowerCase(), {
      name: "GAME",
      iface: gameIface,
    });
    contractAddresses.push(gameAddress);

    // Individual contracts
    const contractMap = {
      COIN: contracts.coin,
      COINFLIP: contracts.coinflip,
      AFFILIATE: contracts.affiliate,
      VAULT: contracts.vault,
      DGNRS: contracts.dgnrs,
      DEITY_PASS: contracts.deityPass,
      WWXRP: contracts.wwxrp,
      QUESTS: contracts.quests,
      JACKPOTS: contracts.jackpots,
      ADMIN: contracts.admin,
    };

    const deploymentContracts = { GAME: gameAddress };

    for (const [key, contract] of Object.entries(contractMap)) {
      if (!contract) continue;
      const addr = await contract.getAddress();
      deploymentContracts[key] = addr;

      // Load artifact for ABI (skip if already have the game merged ABI for GAME)
      const artifactPath = CONTRACT_ARTIFACTS[key];
      if (artifactPath) {
        const artifact = loadArtifact(artifactPath);
        if (artifact) {
          const iface = new ethers.Interface(artifact.abi);
          addressIndex.set(addr.toLowerCase(), { name: key, iface });
          contractAddresses.push(addr);
        }
      }
    }

    // Mock contracts
    const mockAddresses = {};
    const mockVRFAddr = await contracts.mockVRF.getAddress();
    mockAddresses.VRF_COORDINATOR = mockVRFAddr;

    console.log(`Tracking ${contractAddresses.length} contracts`);

    // Create events.db
    const eventsDbPath = path.join(runDir, "events.db");
    const eventsDb = createEventsDb(eventsDbPath);

    // Register contracts
    const registerStmt = eventsDb.prepare(
      "INSERT OR REPLACE INTO contracts (address, name, abi_hash) VALUES (?, ?, ?)"
    );
    for (const [addr, entry] of addressIndex) {
      registerStmt.run(addr, entry.name, null);
    }

    // Capture all events
    const result = await captureAllEvents(
      eventsDb,
      addressIndex,
      contractAddresses
    );
    console.log(
      `Events captured: ${result.total} total, ${result.decoded} decoded`
    );

    // Event breakdown
    const eventBreakdown = eventsDb
      .prepare(
        "SELECT event_name, COUNT(*) as cnt FROM events WHERE event_name IS NOT NULL GROUP BY event_name ORDER BY cnt DESC"
      )
      .all();
    console.log("\nEvent breakdown:");
    for (const row of eventBreakdown.slice(0, 20)) {
      console.log(`  ${row.event_name}: ${row.cnt}`);
    }

    eventsDb.close();

    // Write deployment.json
    const deploymentJson = {
      contracts: deploymentContracts,
      mocks: mockAddresses,
      deployBlock: 0,
      deployDayBoundary: Number(fixture.deployDayBoundary),
      generatedAt: new Date().toISOString(),
      targetLevel: TARGET_LEVEL,
      totalDays: currentDay,
      finalLevel,
    };
    const deploymentJsonPath = path.join(runDir, "deployment.json");
    fs.writeFileSync(deploymentJsonPath, JSON.stringify(deploymentJson, null, 2));
    console.log(`\nDeployment manifest: ${deploymentJsonPath}`);

    // Write a symlink/marker for latest run
    const latestPath = path.join(PROJECT_ROOT, "runs", "latest");
    try {
      if (fs.existsSync(latestPath)) fs.unlinkSync(latestPath);
      fs.symlinkSync(runTs, latestPath);
    } catch {
      // Windows doesn't support symlinks easily
      fs.writeFileSync(latestPath, runTs);
    }

    console.log(`\nRun directory: ${runDir}`);
    console.log("Events DB ready for build-analysis-db.js");
  });
});
