import hre from "hardhat";
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

const JACKPOT_RESET_TIME = 82620n;

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

describe("5 Level Simulation with Player Strategies", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  it("runs 5 levels with Deity/Whale/Conservative strategies", async function () {
    await network.provider.send("hardhat_reset");

    console.log("Deploying contracts...");
    const fixture = await deployFullProtocol();

    const contracts = {
      game: fixture.game,
      coin: fixture.coin,
      coinflip: fixture.coinflip,
      affiliate: fixture.affiliate,
      mockVRF: fixture.mockVRF,
      admin: fixture.admin,
    };

    const caller = fixture.deployer;
    const rng = createRng("5-level-strategies");

    // Initialize PlayerManager with strategies
    console.log("Initializing players with strategies...");
    await warpToDayBoundary(fixture.deployDayBoundary, 1);

    const signers = await ethers.getSigners();
    const players = new PlayerManager({
      signers,
      contracts,
      stats: null
    });
    await players.initPlayers();

    const stats = new StatsTracker(players.players);
    players.stats = stats;

    // Hardhat signers start with 10,000 ETH each - no extra funding needed
    console.log("Players pre-funded by Hardhat (10,000 ETH each)");

    // Setup referrals and mint BURNIE
    console.log("Setting up referrals...");
    await players.setupReferrals();

    console.log("Minting BURNIE to all players...");
    await players.mintBurnieToAll(ethers.parseEther("10000000"));

    // Initialize game state
    console.log("Initializing game state...");
    await warpToDayBoundary(fixture.deployDayBoundary, 2);

    // Advance to get RNG request
    try {
      await contracts.game.connect(caller).advanceGame();
    } catch {}

    // Fulfill VRF and advance to PURCHASE state
    for (let i = 0; i < 50; i++) {
      const fulfilled = await contracts.game.isRngFulfilled();
      if (!fulfilled) {
        await fulfillVrfCycle(contracts.mockVRF, rng);
      }

      const inJackpotPhase = await contracts.game.jackpotPhase();
      if (!inJackpotPhase) {
        console.log(`Game initialized to PURCHASE state after ${i + 1} iterations`);
        break;
      }

      try {
        await contracts.game.connect(caller).advanceGame();
      } catch {}
    }

    // Get initial game parameters
    const initialPrice = await contracts.game.mintPrice();
    const initialTarget = await contracts.game.prizePoolTargetView();

    console.log(`\n${"=".repeat(70)}`);
    console.log("SIMULATION PARAMETERS");
    console.log("=".repeat(70));
    console.log(`Initial Mint Price: ${ethers.formatEther(initialPrice)} ETH`);
    console.log(`Initial Pool Target: ${ethers.formatEther(initialTarget)} ETH`);
    console.log(`Ticket Price: ${ethers.formatEther(initialPrice / 4n)} ETH`);
    console.log("");
    console.log("PLAYER GROUPS:");
    console.log("  Deity (0-9):        Aggressive tickets (200 per day)");
    console.log("  Whale (10-14):      Moderate tickets (100 per day)");
    console.log("  Conservative (15-19): Cautious tickets (50 per day)");
    console.log("=".repeat(70));

    const TARGET_LEVEL = 5;
    let currentDay = 2;
    const levelStartDays = { 1: currentDay };

    // Helper to capture pool snapshot with ticket counts
    async function capturePoolSnapshot(day) {
      const level = Number(await contracts.game.level());

      let currentLevelTickets = 0n;
      let futureLevelTickets = 0n;

      for (const player of players.players) {
        const currentOwed = await contracts.game.ticketsOwedView(level, player.address);
        currentLevelTickets += currentOwed;

        for (let futureLevel = level + 1; futureLevel <= level + 5; futureLevel++) {
          const futureOwed = await contracts.game.ticketsOwedView(futureLevel, player.address);
          futureLevelTickets += futureOwed;
        }
      }

      return {
        day,
        currentPrizePool: await contracts.game.currentPrizePoolView(),
        nextPrizePool: await contracts.game.nextPrizePoolView(),
        futurePrizePool: await contracts.game.rewardPoolView(),
        claimablePool: await contracts.game.claimablePoolView(),
        yieldPool: await contracts.game.yieldPoolView(),
        target: await contracts.game.prizePoolTargetView(),
        currentLevelTickets,
        futureLevelTickets
      };
    }

    // Capture initial level 1 snapshot
    stats.recordLevelSnapshot(1, "start", await capturePoolSnapshot(currentDay));

    // Main simulation loop
    while (true) {
      const currentLevel = Number(await contracts.game.level());
      const inJackpotPhase = await contracts.game.jackpotPhase();
      const gameOver = await contracts.game.gameOver();

      if (currentLevel > TARGET_LEVEL) {
        console.log(`\nReached level ${currentLevel}, stopping.`);
        break;
      }

      if (currentDay > 400) {
        console.log("\nDay limit reached, stopping.");
        break;
      }

      currentDay++;
      await warpToDayBoundary(fixture.deployDayBoundary, currentDay);

      // Advance game cycle
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
          const msg = e?.shortMessage || e?.message?.split('\n')[0] || "";
          if (msg.includes("NotTimeYet")) break;
        }

        // Check for level change
        const newLevel = Number(await contracts.game.level());
        const newInJackpotPhase = await contracts.game.jackpotPhase();
        const newGameOver = await contracts.game.gameOver();
        if (newLevel !== currentLevel && !levelStartDays[newLevel]) {
          // Capture end snapshot for previous level
          stats.recordLevelSnapshot(currentLevel, "end", await capturePoolSnapshot(currentDay));

          levelStartDays[newLevel] = currentDay;
          const newPrice = await contracts.game.mintPrice();
          const newTarget = await contracts.game.prizePoolTargetView();
          const currentPool = await contracts.game.nextPrizePoolView();

          // Capture start snapshot for new level
          stats.recordLevelSnapshot(newLevel, "start", await capturePoolSnapshot(currentDay));

          console.log(`\n${"*".repeat(70)}`);
          console.log(`LEVEL TRANSITION: ${currentLevel} -> ${newLevel} on day ${currentDay}`);
          const compressed = await contracts.game.isCompressedJackpot();
          const stateStr = newGameOver ? 'GAMEOVER' : newInJackpotPhase ? (compressed ? 'JACKPOT (COMPRESSED)' : 'JACKPOT') : 'PURCHASE';
          console.log(`  New State: ${stateStr}`);
          console.log(`  New Mint Price: ${ethers.formatEther(newPrice)} ETH`);
          console.log(`  New Pool Target: ${ethers.formatEther(newTarget)} ETH`);
          console.log(`  Current Pool: ${ethers.formatEther(currentPool)} ETH`);
          console.log("*".repeat(70));
        }
      }

      // Check if we can purchase
      const rngLocked = await contracts.game.rngLocked();
      const inJackpotPhaseNow = await contracts.game.jackpotPhase();
      const gameOverNow = await contracts.game.gameOver();
      const level = Number(await contracts.game.level());

      // Log state when not in purchase mode
      if ((inJackpotPhaseNow || gameOverNow) && currentDay % 10 === 0) {
        const pool = await contracts.game.nextPrizePoolView();
        const target = await contracts.game.prizePoolTargetView();
        const rngFulfilled = await contracts.game.isRngFulfilled();
        const compressedNow = await contracts.game.isCompressedJackpot();
        const stateLabel = gameOverNow ? "GAMEOVER" : inJackpotPhaseNow ? (compressedNow ? "JACKPOT (COMPRESSED)" : "JACKPOT") : "PURCHASE";
        console.log(`Day ${currentDay}: Level ${level}, State ${stateLabel}, Pool ${ethers.formatEther(pool)}/${ethers.formatEther(target)} ETH, rngLocked=${rngLocked}, rngFulfilled=${rngFulfilled}`);
      }

      if (!rngLocked && !inJackpotPhaseNow && !gameOverNow && level <= TARGET_LEVEL) {
        const target = await contracts.game.prizePoolTargetView();

        // Deity players (0-9): Buy aggressively - 200 tickets each
        for (let p = 0; p <= 9; p++) {
          const currentPool = await contracts.game.nextPrizePoolView();
          if (currentPool >= target) break;
          await players.purchaseTickets({ playerIndex: p, ticketCount: 200n });
        }

        // Whale players (10-14): Buy moderately - 100 tickets each
        for (let p = 10; p <= 14; p++) {
          const currentPool = await contracts.game.nextPrizePoolView();
          if (currentPool >= target) break;
          await players.purchaseTickets({ playerIndex: p, ticketCount: 100n });
        }

        // Conservative players (15-19): Buy cautiously - 50 tickets each
        for (let p = 15; p <= 19; p++) {
          const currentPool = await contracts.game.nextPrizePoolView();
          if (currentPool >= target) break;
          await players.purchaseTickets({ playerIndex: p, ticketCount: 50n });
        }

        // Progress report every 5 days
        if (currentDay % 5 === 0) {
          const currentPool = await contracts.game.nextPrizePoolView();
          const pct = target > 0n ? (currentPool * 100n / target) : 0n;
          console.log(`Day ${currentDay}: Level ${level}, Pool ${ethers.formatEther(currentPool)}/${ethers.formatEther(target)} ETH (${pct}%)`);
        }
      }
    }

    // Capture final level end snapshot
    const finalLevel = Number(await contracts.game.level());
    stats.recordLevelSnapshot(finalLevel, "end", await capturePoolSnapshot(currentDay));

    // Refresh claimables
    await stats.refreshCoinflipClaimables(contracts.coin);
    await stats.refreshClaimableWinnings(contracts.game);

    // Get final mint price for ticket value calculation
    const finalMintPrice = await contracts.game.mintPrice();

    console.log("\n" + "=".repeat(70));
    console.log("FINAL TICKET OWNERSHIP BY LEVEL");
    console.log("=".repeat(70));

    for (let lvl = 1; lvl <= Math.min(finalLevel, TARGET_LEVEL + 1); lvl++) {
      console.log(`\n--- Level ${lvl} ---`);
      let levelTotal = 0n;

      const groups = {
        Deity: { players: [], total: 0n },
        Whale: { players: [], total: 0n },
        Conservative: { players: [], total: 0n }
      };

      for (let p = 0; p < 20; p++) {
        const owed = await contracts.game.ticketsOwedView(lvl, players.players[p].address);
        const group = players.players[p].group;
        groups[group].players.push({ index: p, owed });
        groups[group].total += owed;
        levelTotal += owed;
      }

      for (const [groupName, groupData] of Object.entries(groups)) {
        const playersWithOwed = groupData.players.filter(p => p.owed > 0n);
        if (playersWithOwed.length > 0 || groupData.total > 0n) {
          console.log(`  ${groupName}: ${groupData.total} tickets owed`);
          for (const p of playersWithOwed) {
            console.log(`    Player ${p.index}: ${p.owed} owed`);
          }
        }
      }
      console.log(`  TOTAL OWED: ${levelTotal}`);
    }

    // Print stats report
    console.log("\n");
    console.log(stats.renderReport({ totalDays: currentDay, finalLevel, mintPrice: finalMintPrice }));

    // Print level pool report
    console.log(stats.renderLevelPoolReport());

    // Level transition timing
    console.log("\n" + "=".repeat(70));
    console.log("LEVEL TRANSITION TIMING");
    console.log("=".repeat(70));
    const levels = Object.keys(levelStartDays).map(Number).sort((a, b) => a - b);
    for (let i = 0; i < levels.length; i++) {
      const lvl = levels[i];
      const startDay = levelStartDays[lvl];
      const nextLvl = levels[i + 1];
      const endDay = nextLvl ? levelStartDays[nextLvl] - 1 : currentDay;
      const duration = endDay - startDay + 1;
      console.log(`  Level ${lvl}: Days ${startDay}-${endDay} (${duration} days)`);
    }

    console.log("\n" + "=".repeat(70));
    console.log(`Final Level: ${finalLevel}`);
    console.log(`Total Days: ${currentDay}`);
    console.log("=".repeat(70));
  });
});
