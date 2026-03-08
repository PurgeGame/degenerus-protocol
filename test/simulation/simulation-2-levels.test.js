import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { PlayerManager } from "../helpers/player-manager.js";
import { StatsTracker } from "../helpers/stats-tracker.js";
import {
  advanceToNextDay,
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

function formatEth(wei) {
  if (wei === 0n) return "0";
  const str = ethers.formatEther(wei);
  const [whole, frac = ""] = str.split(".");
  return frac ? `${whole}.${frac.slice(0, 4)}` : whole;
}

function phaseName(inJackpotPhase, gameOver, compressedJackpot) {
  if (gameOver) return "GAMEOVER";
  if (inJackpotPhase) return compressedJackpot ? "JACKPOT (COMPRESSED)" : "JACKPOT";
  return "PURCHASE";
}

describe("2 Level Detailed Simulation", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  it("runs 2 levels with daily stats and action logging", async function () {
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

    const advanceModule = fixture.advanceModule;
    const jackpotModule = fixture.jackpotModule;
    const gameAddress = await contracts.game.getAddress();
    const caller = fixture.deployer;
    const rng = createRng("2-level-detailed");

    // Initialize PlayerManager
    console.log("Initializing players...");
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

    // Helper to get daily stats
    async function getDailyStats() {
      const level = Number(await contracts.game.level());
      const inJackpotPhase = await contracts.game.jackpotPhase();
      const gameOver = await contracts.game.gameOver();
      const target = await contracts.game.prizePoolTargetView();
      const claimable = await contracts.game.claimablePoolView();
      const next = await contracts.game.nextPrizePoolView();
      const current = await contracts.game.currentPrizePoolView();
      const future = await contracts.game.rewardPoolView();
      const yieldPool = await contracts.game.yieldPoolView();
      const rngLocked = await contracts.game.rngLocked();
      const rngFulfilled = await contracts.game.isRngFulfilled();
      const compressedJackpot = await contracts.game.isCompressedJackpot();

      let currentLevelTickets = 0n;
      let futureLevelTickets = 0n;
      for (const player of players.players) {
        currentLevelTickets += await contracts.game.ticketsOwedView(level, player.address);
        for (let fl = level + 1; fl <= level + 5; fl++) {
          futureLevelTickets += await contracts.game.ticketsOwedView(fl, player.address);
        }
      }

      return {
        level,
        inJackpotPhase,
        gameOver,
        stateName: phaseName(inJackpotPhase, gameOver, compressedJackpot),
        target,
        claimable,
        next,
        current,
        future,
        yieldPool,
        rngLocked,
        rngFulfilled,
        compressedJackpot,
        currentLevelTickets,
        futureLevelTickets
      };
    }

    function printDailyHeader(day, dailyStats) {
      console.log(`\n${"=".repeat(80)}`);
      console.log(`DAY ${day} - Level ${dailyStats.level} - ${dailyStats.stateName}`);
      console.log(`${"=".repeat(80)}`);
      console.log(`  RNG: locked=${dailyStats.rngLocked}, fulfilled=${dailyStats.rngFulfilled}`);
      console.log(`  POOLS:`);
      console.log(`    Target:    ${formatEth(dailyStats.target)} ETH`);
      console.log(`    Claimable: ${formatEth(dailyStats.claimable)} ETH`);
      console.log(`    Next:      ${formatEth(dailyStats.next)} ETH (${dailyStats.target > 0n ? (dailyStats.next * 100n / dailyStats.target) : 0n}% of target)`);
      console.log(`    Current:   ${formatEth(dailyStats.current)} ETH`);
      console.log(`    Future:    ${formatEth(dailyStats.future)} ETH`);
      console.log(`    Yield:     ${formatEth(dailyStats.yieldPool)} ETH`);
      console.log(`  TICKETS:`);
      console.log(`    Current Level (${dailyStats.level}): ${dailyStats.currentLevelTickets}`);
      console.log(`    Future Levels: ${dailyStats.futureLevelTickets}`);
    }

    let dailyActions = [];

    function logAction(action) {
      dailyActions.push(action);
      console.log(`    ${action}`);
    }

    // Custom purchase that logs
    async function purchaseTicketsLogged(playerIndex, ticketCount) {
      const player = players.getPlayer(playerIndex);
      const mintPrice = await contracts.game.mintPrice();
      const ticketQuantity = ticketCount * 100n;
      const cost = (mintPrice * ticketQuantity) / 400n;

      try {
        await contracts.game.connect(player.signer).purchase(
          player.address,
          ticketQuantity,
          0,
          ethers.ZeroHash,
          0,
          { value: cost }
        );
        stats.recordEthSpend(playerIndex, cost);
        stats.recordTickets(playerIndex, ticketCount);
        logAction(`Player ${playerIndex} (${player.group}) bought ${ticketCount} tickets for ${formatEth(cost)} ETH`);
        return true;
      } catch (e) {
        const msg = e?.shortMessage || e?.message?.split('\n')[0] || "unknown";
        logAction(`Player ${playerIndex} (${player.group}) FAILED to buy tickets: ${msg}`);
        return false;
      }
    }

    const TARGET_LEVEL = 2;
    let currentDay = 2;
    const levelStartDays = { 1: currentDay };

    // Print initial state
    let dailyStats = await getDailyStats();
    printDailyHeader(currentDay, dailyStats);
    console.log(`  ACTIONS:`);
    console.log(`    [Game initialized]`);

    // Main simulation loop
    while (true) {
      const currentLevel = Number(await contracts.game.level());

      if (currentLevel > TARGET_LEVEL) {
        console.log(`\n${"#".repeat(80)}`);
        console.log(`SIMULATION COMPLETE - Reached level ${currentLevel}`);
        console.log(`${"#".repeat(80)}`);
        break;
      }

      if (currentDay > 100) {
        console.log("\nDay limit reached, stopping.");
        break;
      }

      currentDay++;
      dailyActions = [];
      await warpToDayBoundary(fixture.deployDayBoundary, currentDay);

      dailyStats = await getDailyStats();
      printDailyHeader(currentDay, dailyStats);
      console.log(`  ACTIONS:`);

      // Advance game cycle
      let levelChanged = false;
      for (let i = 0; i < 50; i++) {
        const rngLocked = await contracts.game.rngLocked();
        const rngFulfilled = await contracts.game.isRngFulfilled();

        if (rngLocked && !rngFulfilled) {
          const fulfilled = await fulfillVrfCycle(contracts.mockVRF, rng);
          if (fulfilled) {
            logAction(`VRF fulfilled`);
          }
          continue;
        }

        try {
          const txResult = await contracts.game.connect(caller).advanceGame();
          const receipt = await txResult.wait();

          for (const log of receipt.logs) {
            // Try advance module events (Advance stage emitted via delegatecall)
            try {
              const parsed = advanceModule.interface.parseLog(log);
              if (parsed && parsed.name === "Advance") {
                logAction(`ADVANCE: stage=${parsed.args.stage} level=${parsed.args.lvl}`);
              }
            } catch {}
            // Try jackpot module events
            try {
              const parsed = jackpotModule.interface.parseLog(log);
              if (parsed) {
                if (parsed.name === "JackpotTicketWinner") {
                  logAction(`JACKPOT: Ticket winner ${parsed.args.winner.slice(0, 10)}... - ${formatEth(parsed.args.amount)} ETH (trait ${parsed.args.traitId})`);
                } else if (parsed.name === "DailyCarryoverStarted") {
                  logAction(`JACKPOT: Daily carryover started (level ${parsed.args.jackpotLevel} from ${parsed.args.carryoverSourceLevel})`);
                } else if (parsed.name === "FarFutureCoinJackpotWinner") {
                  logAction(`JACKPOT: Far-future BURNIE winner ${parsed.args.winner.slice(0, 10)}... - ${formatEth(parsed.args.amount)} BURNIE`);
                }
              }
            } catch {}
          }
        } catch (e) {
          const msg = e?.shortMessage || e?.message?.split('\n')[0] || "";
          if (msg.includes("NotTimeYet")) {
            break;
          }
        }

        const newLevel = Number(await contracts.game.level());
        if (newLevel !== currentLevel && !levelStartDays[newLevel]) {
          const endSnapshot = await getDailyStats();
          stats.recordLevelSnapshot(currentLevel, "end", {
            day: currentDay,
            currentPrizePool: endSnapshot.current,
            nextPrizePool: endSnapshot.next,
            futurePrizePool: endSnapshot.future,
            claimablePool: endSnapshot.claimable,
            yieldPool: endSnapshot.yieldPool,
            target: endSnapshot.target,
            currentLevelTickets: endSnapshot.currentLevelTickets,
            futureLevelTickets: endSnapshot.futureLevelTickets
          });
          levelStartDays[newLevel] = currentDay;
          levelChanged = true;
        }
      }

      // Player purchases if in PURCHASE state
      const inJackpotPhaseNow = await contracts.game.jackpotPhase();
      const gameOverNow = await contracts.game.gameOver();
      const rngLocked = await contracts.game.rngLocked();
      const level = Number(await contracts.game.level());

      if (!rngLocked && !inJackpotPhaseNow && !gameOverNow && level <= TARGET_LEVEL) {
        const target = await contracts.game.prizePoolTargetView();

        // Deity players (0-9): Buy 50 tickets each per day
        for (let p = 0; p <= 9; p++) {
          const pool = await contracts.game.nextPrizePoolView();
          if (pool >= target) {
            logAction(`Pool target reached, stopping purchases`);
            break;
          }
          await purchaseTicketsLogged(p, 50n);
        }

        // Whale players (10-14): Buy 25 tickets each per day
        for (let p = 10; p <= 14; p++) {
          const pool = await contracts.game.nextPrizePoolView();
          if (pool >= target) break;
          await purchaseTicketsLogged(p, 25n);
        }

        // Conservative players (15-19): Buy 10 tickets each per day
        for (let p = 15; p <= 19; p++) {
          const pool = await contracts.game.nextPrizePoolView();
          if (pool >= target) break;
          await purchaseTicketsLogged(p, 10n);
        }
      } else if (inJackpotPhaseNow || gameOverNow) {
        logAction(`Not in PURCHASE state (${phaseName(inJackpotPhaseNow, gameOverNow)}), no purchases`);
      }

      // End of day stats
      const endStats = await getDailyStats();
      console.log(`  END OF DAY:`);
      console.log(`    Pool: ${formatEth(endStats.next)}/${formatEth(endStats.target)} ETH (${endStats.target > 0n ? (endStats.next * 100n / endStats.target) : 0n}%)`);
      console.log(`    Tickets: current=${endStats.currentLevelTickets}, future=${endStats.futureLevelTickets}`);

      if (levelChanged) {
        console.log(`\n  *** LEVEL CHANGED TO ${endStats.level} ***`);
      }
    }

    // Final summary
    const finalLevel = Number(await contracts.game.level());
    const finalStats = await getDailyStats();

    stats.recordLevelSnapshot(finalLevel, "end", {
      day: currentDay,
      currentPrizePool: finalStats.current,
      nextPrizePool: finalStats.next,
      futurePrizePool: finalStats.future,
      claimablePool: finalStats.claimable,
      yieldPool: finalStats.yieldPool,
      target: finalStats.target,
      currentLevelTickets: finalStats.currentLevelTickets,
      futureLevelTickets: finalStats.futureLevelTickets
    });

    await stats.refreshCoinflipClaimables(contracts.coin);
    await stats.refreshClaimableWinnings(contracts.game);

    const finalMintPrice = await contracts.game.mintPrice();

    console.log("\n");
    console.log(stats.renderReport({ totalDays: currentDay, finalLevel, mintPrice: finalMintPrice }));
    console.log(stats.renderLevelPoolReport());

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
