import { ethers } from 'ethers';
import { BaseStrategy, GAS_LIMIT, GAS_LIMIT_LOW } from './base.js';

/**
 * Sepolia advancer strategy: the game clock with mock VRF fulfillment.
 *
 * Uses creatorAdvanceDay() instead of evm_increaseTime.
 * Fulfills VRF instantly via MockVRFCoordinator (no Chainlink dependency).
 *
 * State machine phases:
 *   'ready'    → call advanceDay(), enter 'activity'
 *   'activity' → wait for buyers, then call advanceGame() to request VRF
 *                on success → 'vrf'; on failure → stay in 'activity' and retry
 *   'vrf'      → fulfillVrf() + advanceGame() to consume (instant, no polling)
 *                when rngLocked becomes false → 'ready'
 *
 * CRITICAL: Never advance the day without completing the VRF cycle.
 * advanceGame() rotates lootboxRngIndex; skipping it causes lootbox
 * storedDay != currentDay reverts (E()) for all buyers.
 */

// How long (ms) to wait after advancing the day before requesting VRF.
const DAY_ACTIVITY_WINDOW_MS = 10_000;

// How long (ms) to wait before retrying a failed advanceGame().
const ADVANCE_RETRY_DELAY_MS = 10_000;

export class AdvancerSepoliaStrategy extends BaseStrategy {
  constructor(opts) {
    super({ ...opts, name: opts.name || 'advancer-sepolia' });
    this.gameAddress = opts.gameAddress;
    this.stethAddress = opts.stethAddress;
    this._phase = 'init';  // 'init' | 'ready' | 'activity' | 'vrf'
    this._phaseStartTime = 0;
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
   * If advanceDay() fails (e.g. rate limited), stay in 'ready' and retry next tick.
   */
  async _doAdvanceDay() {
    const result = await this.safeSend('advanceDay',
      this.game.advanceDay({ gasLimit: 100_000 })
    );
    if (!result.success) {
      this.log('advanceDay failed — will retry next tick');
      return; // stay in 'ready' phase
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
      return;
    }

    const result = await this.safeSend('advanceGame (request VRF)',
      this.game.advanceGame({ gasLimit: GAS_LIMIT })
    );

    if (result.success) {
      this._phase = 'vrf';
      this._advanceRetries = 0;
    } else {
      this._advanceRetries++;
      this._phaseStartTime = Date.now(); // reset timer for retry
      if (this._advanceRetries <= 3) {
        this.log(`advanceGame failed (attempt ${this._advanceRetries}) — retrying in ${ADVANCE_RETRY_DELAY_MS / 1000}s`);
      } else if (this._advanceRetries >= 10) {
        // Too many failures — likely advanceDay didn't actually go through. Reset to ready.
        this.log(`advanceGame failed ${this._advanceRetries} times — resetting to ready phase`);
        this._phase = 'ready';
      } else {
        this.log(`advanceGame failed ${this._advanceRetries} times — still retrying`);
      }
    }
  }

  /**
   * 'vrf' phase: Fulfill VRF via mock coordinator and drive advanceGame().
   * Instant — no polling or waiting for Chainlink.
   */
  async _doVrfPhase() {
    for (let step = 0; step < 20; step++) {
      const [locked, fulfilled] = await Promise.all([
        this.game.rngLocked(),
        this.game.isRngFulfilled(),
      ]);

      if (!locked) {
        this._phase = 'ready';
        this.log('VRF cycle complete — ready for next day');
        return;
      }

      if (!fulfilled) {
        await this.fulfillVrf();
        continue;
      }

      // VRF fulfilled — consume it
      await this.safeSend('advanceGame (consume VRF)',
        this.game.advanceGame({ gasLimit: GAS_LIMIT })
      );
    }
  }

  /**
   * Fulfill VRF using MockVRFCoordinator.
   * Calls fulfillRandomWords(requestId, randomWord) which invokes
   * rawFulfillRandomWords on the game contract.
   */
  async rebaseSteth() {
    try {
      const steth = new ethers.Contract(
        this.stethAddress,
        ['function rebase() external'],
        this.wallet
      );
      await this.safeSend('stETH rebase',
        steth.rebase({ gasLimit: 100_000 })
      );
    } catch (err) {
      this.log(`stETH rebase error: ${err.message?.slice(0, 80)}`);
    }
  }

  async fulfillVrf() {
    try {
      const vrfCoord = this.contracts.vrf_coordinator.connect(this.wallet);
      const requestId = await vrfCoord.lastRequestId();

      if (requestId === 0n) {
        this.log('VRF: no requests yet');
        return;
      }

      const randomWord = BigInt(ethers.hexlify(ethers.randomBytes(32)));
      const result = await this.safeSend(`VRF fulfill #${requestId}`,
        vrfCoord.fulfillRandomWords(requestId, randomWord, { gasLimit: GAS_LIMIT_LOW })
      );

      if (result.success) {
        this.log(`VRF fulfilled with word: ${randomWord.toString().slice(0, 20)}...`);
      }
    } catch (err) {
      this.log(`VRF error: ${err.message}`);
    }
  }

}
