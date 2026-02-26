import { BaseStrategy, GAS_LIMIT } from './base.js';

/**
 * Sepolia advancer strategy: the game clock for real Chainlink VRF.
 *
 * Uses creatorAdvanceDay() instead of evm_increaseTime, and waits for
 * real Chainlink VRF fulfillment instead of mock fulfillment.
 *
 * Flow per level:
 *   1. advanceDay() — simulated day offset ++
 *   2. [ACTIVITY WINDOW] — wait for actors to buy/bet/flip
 *   3. advanceGame() — requests VRF from Chainlink
 *   4. Poll isRngFulfilled() until Chainlink fulfills (~2 blocks ≈ 24s)
 *   5. advanceGame() — consumes VRF word, processes stage
 *   6. If still locked, goto 4
 *   7. If rngLocked becomes false, goto 1
 */

// How long (ms) to wait after advancing the day before requesting VRF.
const DAY_ACTIVITY_WINDOW_MS = 30_000;

// How often (ms) to poll for VRF fulfillment.
const VRF_POLL_INTERVAL_MS = 6_000;

// Max time (ms) to wait for VRF fulfillment before logging a warning.
const VRF_TIMEOUT_MS = 300_000; // 5 minutes

export class AdvancerSepoliaStrategy extends BaseStrategy {
  constructor(opts) {
    super({ ...opts, name: opts.name || 'advancer-sepolia' });
    this.gameAddress = opts.gameAddress;
    this.stethAddress = opts.stethAddress;
    this.dayAdvancedAt = 0;
    this._vrfWaitStart = 0;
  }

  async tick() {
    if (!this.state?.game) return;

    // Phase 1: Waiting for activity window after advancing day
    if (this.dayAdvancedAt > 0) {
      const elapsed = Date.now() - this.dayAdvancedAt;
      if (elapsed < DAY_ACTIVITY_WINDOW_MS) return;
      // Window expired -> request VRF
      this.dayAdvancedAt = 0;
      await this.safeSend('advanceGame (request VRF)',
        this.game.advanceGame({ gasLimit: GAS_LIMIT })
      );
      this._vrfWaitStart = Date.now();
      return;
    }

    // Phase 2: If rng is locked, wait for Chainlink fulfillment + drive cycle
    const rngLocked = await this.game.rngLocked();
    if (rngLocked) {
      await this._driveVrfCycle();
      return;
    }

    // Phase 3: Game is idle -> advance day via contract call
    await this._advanceDay();
    if (this.stethAddress) await this.rebaseSteth();
    this.dayAdvancedAt = Date.now();

    const level = await this.game.level();
    this.log(`day advanced via advanceDay() at L${level} — waiting ${DAY_ACTIVITY_WINDOW_MS / 1000}s for activity`);
  }

  /**
   * Advance the simulated day using the CREATOR-only advanceDay() function.
   */
  async _advanceDay() {
    const result = await this.safeSend('advanceDay',
      this.game.advanceDay({ gasLimit: 100_000 })
    );
    if (!result.success) {
      this.log('advanceDay failed — may already be advanced or not CREATOR');
    }
  }

  /**
   * Wait for real Chainlink VRF fulfillment and drive advanceGame() calls.
   * No mock fulfill — just poll isRngFulfilled() until Chainlink delivers.
   */
  async _driveVrfCycle() {
    for (let step = 0; step < 30; step++) {
      const [locked, fulfilled] = await Promise.all([
        this.game.rngLocked(),
        this.game.isRngFulfilled(),
      ]);

      if (!locked) {
        this._vrfWaitStart = 0;
        return; // cycle complete
      }

      if (!fulfilled) {
        // Still waiting for Chainlink to fulfill
        const waited = Date.now() - (this._vrfWaitStart || Date.now());
        if (waited > VRF_TIMEOUT_MS) {
          this.log(`WARNING: VRF not fulfilled after ${Math.round(waited / 1000)}s — check LINK balance and subscription`);
          this._vrfWaitStart = Date.now(); // reset to avoid spamming
        }
        // Wait and re-poll
        await new Promise(r => setTimeout(r, VRF_POLL_INTERVAL_MS));
        continue;
      }

      // VRF fulfilled — consume it
      await this.safeSend('advanceGame (consume VRF)',
        this.game.advanceGame({ gasLimit: GAS_LIMIT })
      );
    }
  }

  async rebaseSteth() {
    try {
      const { ethers } = await import('ethers');
      const steth = new ethers.Contract(
        this.stethAddress,
        ['function rebase() external'],
        this.wallet
      );
      await this.safeSend('stETH rebase',
        steth.rebase({ gasLimit: 500_000 })
      );
    } catch (err) {
      this.log(`stETH rebase error: ${err.message?.slice(0, 80)}`);
    }
  }
}
