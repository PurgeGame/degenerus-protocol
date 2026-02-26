import { BaseStrategy, GAS_LIMIT } from './base.js';

/**
 * Sepolia advancer strategy: the game clock for real Chainlink VRF.
 *
 * Uses creatorAdvanceDay() instead of evm_increaseTime, and waits for
 * real Chainlink VRF fulfillment instead of mock fulfillment.
 *
 * State machine phases:
 *   'ready'    → call advanceDay(), enter 'activity'
 *   'activity' → wait for buyers, then call advanceGame() to request VRF
 *                on success → 'vrf'; on failure → stay in 'activity' and retry
 *   'vrf'      → poll isRngFulfilled(), call advanceGame() to consume
 *                when rngLocked becomes false → 'ready'
 *
 * CRITICAL: Never advance the day without completing the VRF cycle.
 * advanceGame() rotates lootboxRngIndex; skipping it causes lootbox
 * storedDay != currentDay reverts (E()) for all buyers.
 */

// How long (ms) to wait after advancing the day before requesting VRF.
const DAY_ACTIVITY_WINDOW_MS = 10_000;

// How often (ms) to poll for VRF fulfillment.
const VRF_POLL_INTERVAL_MS = 4_000;

// Max time (ms) to wait for VRF fulfillment before logging a warning.
const VRF_TIMEOUT_MS = 180_000; // 3 minutes

// How long (ms) to wait before retrying a failed advanceGame().
const ADVANCE_RETRY_DELAY_MS = 10_000;

export class AdvancerSepoliaStrategy extends BaseStrategy {
  constructor(opts) {
    super({ ...opts, name: opts.name || 'advancer-sepolia' });
    this.gameAddress = opts.gameAddress;
    this.stethAddress = opts.stethAddress;
    this._phase = 'init';  // 'init' | 'ready' | 'activity' | 'vrf'
    this._phaseStartTime = 0;
    this._vrfWaitStart = 0;
    this._advanceRetries = 0;
  }

  async tick() {
    if (!this.state?.game) return;

    // On first tick or after recovery, check if game is mid-VRF from a previous run
    if (this._phase === 'init') {
      const rngLocked = await this.game.rngLocked();
      if (rngLocked) {
        this.log('game is mid-VRF from previous session — driving VRF cycle');
        this._phase = 'vrf';
        this._vrfWaitStart = Date.now();
      } else {
        this._phase = 'ready';
      }
    }

    switch (this._phase) {
      case 'ready':
        await this._doAdvanceDay();
        break;

      case 'activity':
        await this._doActivityPhase();
        break;

      case 'vrf':
        await this._doVrfPhase();
        break;
    }
  }

  /**
   * 'ready' phase: Advance the simulated day, enter activity window.
   */
  async _doAdvanceDay() {
    const result = await this.safeSend('advanceDay',
      this.game.advanceDay({ gasLimit: 100_000 })
    );
    if (!result.success) {
      this.log('advanceDay failed — may already be advanced or not CREATOR');
    }
    if (this.stethAddress) await this.rebaseSteth();

    this._phase = 'activity';
    this._phaseStartTime = Date.now();
    this._advanceRetries = 0;

    const level = await this.game.level();
    this.log(`day advanced at L${level} — waiting ${DAY_ACTIVITY_WINDOW_MS / 1000}s for activity`);
  }

  /**
   * 'activity' phase: Wait for buyers, then request VRF via advanceGame().
   * On failure, STAY in this phase and retry — never advance the day.
   */
  async _doActivityPhase() {
    const elapsed = Date.now() - this._phaseStartTime;

    // First attempt: wait full activity window
    // Retries: wait a shorter delay
    const waitTime = this._advanceRetries === 0 ? DAY_ACTIVITY_WINDOW_MS : ADVANCE_RETRY_DELAY_MS;
    if (elapsed < waitTime) return;

    // Check if rng got locked by another caller (e.g., helpAdvance from an actor)
    const rngLocked = await this.game.rngLocked();
    if (rngLocked) {
      this.log('rng already locked (another actor called advanceGame?) — entering VRF phase');
      this._phase = 'vrf';
      this._vrfWaitStart = Date.now();
      return;
    }

    const result = await this.safeSend('advanceGame (request VRF)',
      this.game.advanceGame({ gasLimit: GAS_LIMIT })
    );

    if (result.success) {
      this._phase = 'vrf';
      this._vrfWaitStart = Date.now();
      this._advanceRetries = 0;
    } else {
      this._advanceRetries++;
      this._phaseStartTime = Date.now(); // reset timer for retry
      if (this._advanceRetries <= 3) {
        this.log(`advanceGame failed (attempt ${this._advanceRetries}) — retrying in ${ADVANCE_RETRY_DELAY_MS / 1000}s`);
      } else {
        this.log(`advanceGame failed ${this._advanceRetries} times — still retrying (check pool/target)`);
      }
    }
  }

  /**
   * 'vrf' phase: Wait for Chainlink VRF fulfillment and drive advanceGame().
   */
  async _doVrfPhase() {
    for (let step = 0; step < 30; step++) {
      const [locked, fulfilled] = await Promise.all([
        this.game.rngLocked(),
        this.game.isRngFulfilled(),
      ]);

      if (!locked) {
        this._vrfWaitStart = 0;
        this._phase = 'ready';
        this.log('VRF cycle complete — ready for next day');
        return;
      }

      if (!fulfilled) {
        const waited = Date.now() - (this._vrfWaitStart || Date.now());
        if (waited > VRF_TIMEOUT_MS) {
          // Contract has 5-minute VRF retry: calling advanceGame re-requests VRF
          this.log(`VRF not fulfilled after ${Math.round(waited / 1000)}s — triggering contract retry`);
          const retryResult = await this.safeSend('advanceGame (VRF retry)',
            this.game.advanceGame({ gasLimit: GAS_LIMIT })
          );
          if (retryResult.success) {
            this.log('VRF re-requested via contract retry mechanism');
            this._vrfWaitStart = Date.now(); // reset timer for new request
          } else {
            this.log('VRF retry failed — will try again next cycle');
          }
        }
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
