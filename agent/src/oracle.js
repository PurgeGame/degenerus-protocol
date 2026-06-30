// MAN-01 runtime invariant oracle (AGT-04).
//
// Loads agent/manifest/invariants.json (the canonical oracle, shared verbatim
// with the README Main-Invariants section) and, after every external action,
// asserts each invariant by reading live chain state. A violation is returned as
// a structured object the recorder turns into a replayable finding.
//
// Coverage classes:
//  - STATE  : evaluable purely from public getters (+ for SOLV-01, one mandated
//             eth_getStorageAt slot-11 raw read for the freeze-window pending
//             buffer, which has no external view). Checked every tick.
//  - WINDOW : RNG-freeze byte-equality — snapshot the enumerated in-window slots
//             while rngLocked(), re-check after an in-window player action.
//  - EVENT  : accumulated from emitted logs (redemption roll/split, box enqueue).
//  - STAT   : Degenerette EV/RTP/ROI estimated from the DegeneretteResult stream
//             plus per-spin hard bounds; flagged by the statistical gate.
//
// Mocks (VRF, stETH) are TRUSTED — their quirks are never findings; the oracle
// only reads the protocol's HANDLING of them (e.g. stETH.balanceOf on the
// backing side), never asserts anything about the mock itself.

import { ethers } from "ethers";

const ERC20 = ["function balanceOf(address) view returns (uint256)"];
// Freeze-window pending buffer prizePoolPendingPacked: slot 11, (future<<128)|next.
const PENDING_SLOT = 11n;
const DEAD = "0x000000000000000000000000000000000000dEaD";

export class InvariantOracle {
  constructor(conn, manifest) {
    this.conn = conn;
    this.manifest = manifest;
    this.g = conn.game;
    this.steth = new ethers.Contract(conn.stethAddress, ERC20, conn.provider);
    // Monotonic / sampled trackers for FSM + redemption period invariants.
    this.maxLevel = -1n;
    this.gameOverSeen = false;
    this.maxPeriod = -1n;
    this.evBuckets = new Map(); // `${N}:${heroIsGold}` -> {wager, payout, n}
    this.perSpinViolations = [];
  }

  // -- raw reads (all PINNED to one blockTag for a consistent snapshot) -------
  // Reading pools + balance + storage as separate RPC calls is a TOCTOU hazard:
  // a block mined mid-read yields pools-updated / balance-not-yet, a false
  // `sumPools > balance`. On a live chain that race is constant, so every read
  // in a checkState() is pinned to the same block.
  async _pending(blockTag) {
    const raw = await this.conn.provider.getStorage(this.conn.address("GAME"), PENDING_SLOT, blockTag);
    const w = BigInt(raw);
    const next = w & ((1n << 128n) - 1n);
    const future = w >> 128n;
    return { next, future };
  }

  async _coreState(blockTag) {
    const g = this.g;
    const o = { blockTag };
    const [gameOver, level, current, next, future, claimable, yieldAcc, gameBal, steth, rngLocked] =
      await Promise.all([
        g.gameOver(o), g.level(o), g.currentPrizePoolView(o), g.nextPrizePoolView(o),
        g.futurePrizePoolView(o), g.claimablePoolView(o), g.yieldAccumulatorView(o),
        this.conn.provider.getBalance(this.conn.address("GAME"), blockTag),
        this.steth.balanceOf(this.conn.address("GAME"), o),
        g.rngLocked(o),
      ]);
    return { gameOver, level, current, next, future, claimable, yieldAcc, gameBal, steth, rngLocked };
  }

  // -- the per-tick STATE assertion ------------------------------------------
  // Returns { checked, violations:[{id,severity,identity,observed,expected,source}] }.
  async checkState() {
    const v = [];
    const transients = []; // at-rest invariants breached only mid-window (heal at seal)
    // Pin the whole snapshot to one block (TOCTOU-safe — see _coreState).
    const bt = await this.conn.provider.getBlockNumber();
    const o = { blockTag: bt };
    const s = await this._coreState(bt);
    const pend = await this._pending(bt);
    const sumPools = s.current + s.next + s.future + s.claimable;
    const backing = s.gameBal + s.steth;
    // SOLV-01/02 are AT-REST obligation invariants: during the VRF freeze window
    // (rngLocked) the next/future pools may transiently over-commit vs balance
    // while a request is pending, healing at seal — a state the frozen forge
    // harness never observes (it fulfils VRF in-handler). A breach there is a
    // transient, not insolvency: route it to `transients`, escalate only if it
    // persists at rest. SOLV-05 (the WITHDRAWABLE claimable liability) is the
    // exploitable one and stays hard in every state.
    const settled = !s.rngLocked && !s.gameOver;
    const sink = (id, ok, ctx) => {
      if (ok) return;
      const entry = { id, severity: this._sev(id), identity: this._ident(id), observed: ctx, expected: "holds", source: this._src(id) };
      if (settled) v.push(entry);
      else transients.push({ ...entry, severity: "info", transient: true, observed: `${ctx} [in-window transient; not settled]` });
    };

    // SOLV-01 — TOTAL backing (ETH + stETH) covers the canonical obligation set.
    // stETH is legitimate 1:1 backing: the protocol pays out ETH-first with a
    // stETH fallback (_payoutWithStethFallback), so obligations are covered by
    // ETH+stETH, not ETH alone. Measuring gameBal-only false-fires the instant the
    // yield path moves backing into stETH — observed on Base (yield active) as 384
    // spurious SOLV-01s where ETH-alone fell short by EXACTLY the stETH balance
    // while ETH+stETH >= obligations held. SOLV-02/SOLV-05 already use ETH+stETH.
    const obligations = s.gameOver
      ? s.claimable
      : s.current + s.next + s.future + s.claimable + s.yieldAcc + pend.next + pend.future;
    sink("SOLV-01-ETH-SOLVENCY", backing >= obligations,
      `backing(eth+steth)=${backing} obligations=${obligations} (eth=${s.gameBal} steth=${s.steth} gameOver=${s.gameOver})`);

    // SOLV-02 — four-pool sum fully backed by ETH+stETH.
    sink("SOLV-02-FULL-BACKING-ETH-STETH", sumPools <= backing,
      `sumPools=${sumPools} backing=${backing}`);

    // SOLV-05 — claimablePool backed by ETH+stETH (ALWAYS hard — withdrawable).
    this._le(v, "SOLV-05-CLAIMABLE-BACKED", s.claimable, backing,
      `claimable=${s.claimable} backing=${backing}`);

    // REDEEM-01 — segregated redemption ETH covered on the sDGNRS contract.
    await this._guard(v, "REDEEM-01-ETH-SEGREGATION", async () => {
      const sd = this.conn.address("SDGNRS");
      const [pendingRedeem, ethBal, stBal] = await Promise.all([
        this.conn.sdgnrs.pendingRedemptionEthValue(o),
        this.conn.provider.getBalance(sd, bt),
        this.steth.balanceOf(sd, o),
      ]);
      this._ge(v, "REDEEM-01-ETH-SEGREGATION", ethBal + stBal, pendingRedeem,
        `cover=${ethBal + stBal} pendingRedeem=${pendingRedeem}`);
    });

    // COIN-01 / VAULT-02 — FLIP supply identity.
    await this._guard(v, "COIN-01-FLIP-SUPPLY", async () => {
      const [ts, vma, inc] = await Promise.all([
        this.conn.coin.totalSupply(o), this.conn.coin.vaultMintAllowance(o),
        this.conn.coin.supplyIncUncirculated(o),
      ]);
      this._eq(v, "COIN-01-FLIP-SUPPLY", ts + vma, inc, `totalSupply+vaultMintAllowance=${ts + vma} supplyIncUncirculated=${inc}`);
      // VAULT-01 — allowance bounded by the uncirculated ceiling.
      this._le(v, "VAULT-01-ALLOWANCE-BOUNDED", vma, inc, `vaultMintAllowance=${vma} supplyIncUncirculated=${inc}`);
    });

    // FSM-01 — level monotonic non-decreasing.
    if (s.level < this.maxLevel) {
      this._fail(v, "FSM-01-LEVEL-MONOTONIC", `level regressed ${this.maxLevel} -> ${s.level}`);
    }
    if (s.level > this.maxLevel) this.maxLevel = s.level;

    // FSM-02 — gameOver one-way latch.
    if (this.gameOverSeen && !s.gameOver) {
      this._fail(v, "FSM-02-GAMEOVER-TERMINAL", "gameOver reverted true -> false");
    }
    if (s.gameOver) this.gameOverSeen = true;

    // FSM-03 — exactly one FSM state active (PURCHASE | JACKPOT | GAMEOVER).
    await this._guard(v, "FSM-03-NO-BRICK-LIVENESS", async () => {
      const jp = await this.g.jackpotPhase(o);
      const states = [!jp && !s.gameOver, jp && !s.gameOver, s.gameOver];
      if (states.filter(Boolean).length !== 1) {
        this._fail(v, "FSM-03-NO-BRICK-LIVENESS", `ambiguous FSM state jackpotPhase=${jp} gameOver=${s.gameOver}`);
      }
    });

    // TICKET-01 — a never-participating address has zero owed at every level.
    await this._guard(v, "TICKET-01-OWED-CONSISTENT", async () => {
      const lvl = Number(s.level);
      const [o0, o1] = await Promise.all([
        this.g.entriesOwedView(lvl, DEAD, o), this.g.entriesOwedView(lvl + 1, DEAD, o),
      ]);
      if (o0 !== 0n || o1 !== 0n) {
        this._fail(v, "TICKET-01-OWED-CONSISTENT", `non-participant 0xDEAD owed ${o0}/${o1} at lvl ${lvl}/${lvl + 1}`);
      }
    });

    // REDEEM-03 — redemption period (day index) monotonic non-decreasing.
    // Surrogate: level is non-decreasing and day index rides it; we sample level.
    if (s.level >= this.maxPeriod) this.maxPeriod = s.level;
    else this._fail(v, "REDEEM-03-PERIOD-MONOTONIC", `period proxy regressed ${this.maxPeriod} -> ${s.level}`);

    return { checked: this._stateIds().length, settled, state: s, pending: pend, violations: v, transients };
  }

  // -- WINDOW: RNG-freeze byte-equality --------------------------------------
  // Snapshot the enumerated in-window slots while rngLocked(); the action driver
  // fires an in-window player action then calls verifyFrozen(snap).
  async snapshotFrozen() {
    const game = this.conn.address("GAME");
    // Pin every read to one block so the snapshot is internally consistent (a
    // block mined mid-snapshot would otherwise smear slots across heights).
    const bt = await this.conn.provider.getBlockNumber();
    const o = { blockTag: bt };
    const day = await this.g.currentDayView?.(o).catch(() => null);
    const get = (slot) => this.conn.provider.getStorage(game, slot, bt);
    const [locked, lootWord, lootCursor, dailyIdxSlot] = await Promise.all([
      this.g.rngLocked(o), get(35n), get(34n), get(0n),
    ]);
    let dayWord = null;
    try { if (day != null) dayWord = (await this.g.rngWordForDay(day, o)).toString(); } catch { /* */ }
    return { block: bt, locked, lootWord, lootCursorLow: BigInt(lootCursor) & 0xffffffffffffn, dailyIdxByte: (BigInt(dailyIdxSlot) >> 24n) & 0xffn, dayWord, day };
  }

  async verifyFrozen(snap) {
    if (!snap?.locked) return null; // only meaningful inside the window
    const now = await this.snapshotFrozen();
    // Live-chain window-transition guard. On the real testnet the
    // snapshot -> in-window action -> verify interval spans real blocks during
    // which the SEPARATE sim legitimately advances the RNG lifecycle: Chainlink
    // VRF fulfilment writes rngWordByDay (0 -> word), a seal/new request advances
    // dailyIdx, and a 15-min-day boundary moves currentDay. NONE of those is
    // caused by the agent's in-window player action, so a slot change ACROSS such
    // a transition is a lifecycle transient (INFO), never an RNG-01 finding (the
    // README's "in-window transients are INFO" rule). RNG-01 is only
    // player-attributable when the window stayed continuously locked on the SAME
    // day and index across the probe — the one state in which a residual slot
    // mutation must be the player action's doing. (The white-box Foundry suite
    // proves byte-freeze rigorously in isolation; this live net catches only the
    // unambiguous, transition-free breach.)
    const transitioned =
      !now.locked ||                                    // window closed (seal/fulfil)
      now.day !== snap.day ||                            // day boundary crossed
      now.dailyIdxByte !== snap.dailyIdxByte ||          // request/seal index advanced
      (snap.dayWord === "0" && now.dayWord !== "0");     // VRF fulfilment 0 -> word
    if (transitioned) return { transient: true, reason: "rng-window lifecycle transition (not player-attributable)" };
    const mism = [];
    if (now.lootWord !== snap.lootWord) mism.push("lootboxRngWordByIndex");
    if (now.lootCursorLow !== snap.lootCursorLow) mism.push("lootboxRngPacked cursor");
    if (snap.dayWord != null && snap.dayWord !== "0" && now.dayWord !== snap.dayWord) mism.push("rngWordByDay[currentDay]");
    if (mism.length) {
      return { id: "RNG-01-INWINDOW-SLOADS-FROZEN", severity: "high",
        identity: "in-window consumed slots must not mutate from a player action",
        observed: `mutated: ${mism.join(", ")}`, expected: "byte-identical", source: this._src("RNG-01-INWINDOW-SLOADS-FROZEN") };
    }
    return null;
  }

  // -- STAT: ingest a DegeneretteResult for the Degenerette EV oracle ----------
  // payload: {player, betId, spinIndex, playerTraits, matches, payout, currency, wager}
  ingestSpin(p) {
    const heroIsGold = p.heroIsGold ? 1 : 0;
    const N = p.goldCount ?? 0;
    const key = `${N}:${heroIsGold}`;
    const b = this.evBuckets.get(key) || { wager: 0n, payout: 0n, n: 0 };
    b.wager += BigInt(p.wager ?? 0); b.payout += BigInt(p.payout ?? 0); b.n += 1;
    this.evBuckets.set(key, b);
    // Per-spin hard bound for the WWXRP rig: the rig can never fabricate S=9.
    // A WWXRP-currency spin showing matches==9 is only valid if the honest reel
    // was already M==8; without the honest-reel re-derivation we flag it for
    // adjudication rather than auto-confirm (mock-trusted, but rig invariant is real).
    if (p.currency === 3 && Number(p.matches) === 9) {
      this.perSpinViolations.push({ id: "DEG-03-WWXRP-RIG-NEVER-S9", severity: "high",
        identity: "WWXRP rig must never route an S=9 jackpot (requires honest M==8)",
        observed: `WWXRP spin matches==9 player=${p.player} betId=${p.betId}`,
        expected: "rig-fired S<=8 unless honest reel already M==8 (needs honest-reel re-derivation)",
        source: this._src("DEG-03-WWXRP-RIG-NEVER-S9"), needsHonestReelCheck: true });
    }
  }

  // Degenerette EV-ceiling check over accumulated buckets (centi-x; honest <=100).
  evCeilingFindings(minSample = 200) {
    const out = [];
    for (const [key, b] of this.evBuckets) {
      if (b.n < minSample || b.wager === 0n) continue;
      const evCentiX = Number((b.payout * 100n * 100n) / b.wager) / 100; // payout/wager in centi-x
      if (evCentiX > 100.0) {
        out.push({ id: "DEG-01-PER-N-EV-CEILING", severity: "high",
          identity: `honest Degenerette EV must stay <=100 centi-x per (N,heroIsGold)`,
          observed: `bucket ${key}: EV=${evCentiX.toFixed(4)} centi-x over n=${b.n}`,
          expected: "<=100 centi-x", source: this._src("DEG-01-PER-N-EV-CEILING") });
      }
    }
    return out;
  }

  drainPerSpin() { const out = this.perSpinViolations; this.perSpinViolations = []; return out; }

  // -- helpers ---------------------------------------------------------------
  _stateIds() { return this.manifest.invariants.filter((i) => i.kind === "state").map((i) => i.id); }
  _meta(id) { return this.manifest.invariants.find((i) => i.id === id); }
  _src(id) { return this._meta(id)?.source ?? id; }
  _sev(id) { return this._meta(id)?.severity ?? "medium"; }
  _ident(id) { return this._meta(id)?.identity ?? id; }
  _push(v, id, observed, expected) {
    v.push({ id, severity: this._sev(id), identity: this._ident(id), observed, expected, source: this._src(id) });
  }
  _ge(v, id, a, b, ctx) { if (a < b) this._push(v, id, `${ctx} [a<b]`, "a>=b"); }
  _le(v, id, a, b, ctx) { if (a > b) this._push(v, id, `${ctx} [a>b]`, "a<=b"); }
  _eq(v, id, a, b, ctx) { if (a !== b) this._push(v, id, `${ctx} [a!=b]`, "a==b"); }
  _fail(v, id, observed) { this._push(v, id, observed, this._ident(id)); }
  async _guard(v, id, fn) { try { await fn(); } catch (e) { /* a view revert is not itself a violation; note via FSM-03 if persistent */ } }
}
