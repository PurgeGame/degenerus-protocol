# Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants - Context

**Gathered:** 2026-05-26 (original) · **RE-SPEC revised:** 2026-05-26 (v49.0 keeper-router pivot)
**Status:** Ready for planning

> ⚠️ **RE-SPEC.** The original 329 SPEC + Phase 330 IMPL executed and verified, then the held 330
> batched diff was **superseded at the 330-07 hand-review** when the user pivoted to a keeper-router
> REDESIGN. The held diff sits uncommitted on the working tree (HEAD `c255cf54`) as the re-IMPL base.
> This CONTEXT is **updated in place** to drive a re-SPEC. The prior `329-SPEC.md`,
> `329-ATTEST-*.md`, and `329-0[1-3]-SUMMARY.md` reflect the OLD design and are **superseded** — the
> planner regenerates them from this CONTEXT. Carry-forward decisions are preserved; reversed/dissolved
> ones are marked. Full pivot capture:
> `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-ROUTER-REDESIGN-INTENT.md`.

<domain>
## Phase Boundary

The v49.0 design-lock phase (direct analog of v48's Phase 325). Produce a re-issued `329-SPEC.md` —
a **paper-only** reconciliation, **zero `contracts/*.sol` mutation** — that lets Phase 330 re-author
ONE fully-reconciled batched diff with no "by construction" assumptions, now reflecting the
keeper-router REDESIGN. Jobs:

1. **Lock the 4 structural invariants** (BATCH-01) under the REDESIGNED router composition: (a)
   one-category structural early-return; (b) frozen advance-consume (`v45-vrf-freeze-invariant`
   re-attested under the new autoBuy→advance→autoOpen order + the dropped rngLock guards, incl. the
   player-controllable `totalFlipReversals` nudge); (c) guaranteed free-fallback `advanceGame()`
   caller (re-attested under autoBuy-highest-priority); (d) single day-start epoch — now **satisfied
   by deletion** (advance is the SOLE stall epoch; see D-03).
2. **Settle the shared signatures** for the redesigned surface: `advanceGame` `(uint8 mult, bool
   rewardable)` (mult = stall ladder NEW-DAY only, `1` for mid-day partial-drain); **parameterless
   `doWork()`**; the rngLock-aware O(1) discovery views; the unified-bounty leg-return shapes
   (`autoOpen`/`autoBuy` return raw counts; advance returns `(mult, rewardable)`).
3. **Lock the redesign** (the 5 locked changes + the simplified flat-per-tx bounty model + the 3
   new GASOPT DOs) — captured in `<decisions>` below.
4. **Grep-attest every cited `file:line`** against the frozen v48.0-closure HEAD `0cc5d10f`; correct
   drift; confirm the producer-before-consumer edit-order map for the re-IMPL (survivors vs reworked).

**No research** — milestone design LOCKED. Security / RNG-freeze floor over gas
(`feedback_security_over_gas` + `v45-vrf-freeze-invariant`).

</domain>

<decisions>
## Implementation Decisions

### REDESIGN BASIS — the 5 locked changes (carried forward from the 330-07 pivot; SPEC-locks them)
Source: `330-ROUTER-REDESIGN-INTENT.md`. Line refs are held-tree/redesign-doc anchors — the SPEC
author RE-GREPS each against `0cc5d10f` and corrects drift.
- **RD-1 — routing order `autoBuy → advance → autoOpen`.** autoBuy runs first so subscriber boxes
  queue at day-open *before* advance requests the day's RNG → same-cycle reveal + same-day quest
  credit. Still one-category-per-call (invariant a). REVERSES the original ROUTER-02 order
  (advance→open→buy).
- **RD-2 — `autoBuy` = normal buy; drop the rngLock guards.** Remove BOTH the `AfKing._autoBuy`
  rngLock guard (`:717`) AND the game-side `batchPurchase` rngLock pre-check (`:1693`); **KEEP the
  `gameOver` check (`:1694`)**. Q1 RESOLVED SAFE: the guard was v46 batch-hygiene (Phase 317
  `df4ef365`), NOT orphan-index defense; buying is freeze-safe by construction (box queues at current
  `LR_INDEX`, word lands at `LR_INDEX-1`, `LR_INDEX` only advances in `advanceGame`); v45 orphan
  hazard is defended on the RESOLUTION side. **Q5 (SPEC author grep): confirm `batchPurchase:1693`
  has no other dependent before removing** (it gates all `batchPurchase` callers, not just the keeper).
- **RD-3 — block `autoOpen` during rngLock.** `boxesPending()` returns false while `rngLocked` so the
  open leg no-ops during the freeze; the dropped-try/catch entry-gate enforces it at the function
  too. The open leg STILL opens **mid-day-resolved** boxes (user: "I do want this to open those") —
  the block applies only to the *currently-pending* round (open whenever a round's word has landed and
  we are not currently locked).
- **RD-4 — unify the bounty into `doWork`.** Pull the `autoOpen` (`:1719`) + `autoBuy` (`:846`)
  in-callee `creditFlip`s out into `doWork`: one bounty policy, one `creditFlip` site; legs return
  their reward basis; direct (non-router) calls to advance/autoOpen/autoBuy become **unrewarded**.
  REVERSES the original R4 ("legs keep their own bounty"). Requires signature changes to
  `autoOpen`/`autoBuy` + `IDegenerusGame`.
- **RD-5 — drop `autoOpen` try/catch + add an entry-gate.** Q2 RE-RESOLVED → DROP. The open path has
  EXACTLY TWO revert sources — `rngLock` and the deliberate terminal-jackpot control `_queueTickets →
  if(_livenessTriggered()) revert E()` (`DegenerusGameStorage:571`, intentional, stays for direct
  `openLootBox`). Fix: `autoOpen(...) { if (IGame.rngLocked() || _livenessTriggered()) return; …
  _autoOpenBox(index, player) /* INTERNAL — no this./try-catch */ }`. Recovers per-box CALL gas,
  brick-proof (both sources excluded pre-loop, neither flips mid-tx), no marooning, terminal-jackpot
  guard intact for direct opens. Trade (USER-accepted): trusts rngLock+liveness are the ONLY revert
  sources forever (frozen contract; trace high-confidence). The entry-gate is MANDATORY if try/catch
  goes — else an atomic-loop revert at queue pos K rolls back `boxCursor`..K and freezes the tail.
- **`rewardable` flag: KEEP** (gameover-only false path, worthless coin by design; `doWork` uses it).

### D-07 — Simplified flat-per-tx bounty model (NEW — user, this discussion; the headline simplification)
- **`doWork()` is PARAMETERLESS.** It determines the work cap itself (a fixed per-leg default batch),
  so there is no `maxCount`. Routing/priority (RD-1), one-category early-return, and the single
  `creditFlip` are unchanged. **This SUPERSEDES D-06** (no `maxCount==0` sentinel exists anymore).
- **Keep the standalone `autoOpen(count)` / `autoBuy(count)` parametered + UNREWARDED** — emergency /
  manual clears (consistent with RD-4: direct calls are unrewarded). (`degeneretteResolve(players[],
  betIds[])` already stays parametered with its own flat ≥3 reward — D-05.)
- **Flat per-tx bounty, per-category multiples of a unit `1×`** where `1×` ≈ the BURNIE flip-credit
  worth of a max-laden batch's gas at 0.5 gwei:

  | Leg | Reward | Gate / scaling | Faucet basis |
  |---|---|---|---|
  | **advance** | `2× × mult` | none | `mult` = stall ladder (1/2/4/6) **NEW-DAY path only**; mid-day partial-drain returns `mult=1` (NO escalation — user: "no multi for mid-day ticket batches"). Real ticket batches (can't be fabricated), liveness-critical, multi-call drain. |
  | **buy** | `1.5×` | none | once/day/sub + the 2 standing protocol auto-subs + any farmer must fund real subscription buys ≫ bounty. "No real faucet ability there" (user). |
  | **open** | `1×` | **pro-rate below the knee:** `1× × min(opened, KNEE)/KNEE` (per-box up to the knee, flat `1×` at/above) | mid-day round resolutions give frequent, small open opportunities (RD-3) → the pro-rate kills the small-batch corner. |

- **One base unit, one conversion** (`× PRICE_COIN_UNIT / mp`), one `creditFlip` in `doWork`,
  one-category early-return preserved.
- **Calibration → GAS-331 (USER-gated), these are SPEC starting estimates:** the `1×` unit, the
  `1 / 1.5 / 2` ratios (relative per-category max-laden gas at 0.5 gwei), and the open `KNEE` (~5).
  Faucet-safety constraint GAS-331 must satisfy + WR-01/GAS-05 must re-prove: the implied per-box
  reward below the open knee (`1× / KNEE`) ≤ a one-box tx's gas at 0.5 gwei → even a tiny mid-day
  open is −EV at any real gas. ("Those numbers are fine to start with" — user.)
- **Faucet doctrine for advance/buy = no gate:** advance work is real ticket-queue batches that can't
  be faked and is liveness-critical (we WANT small remainders cranked); `advanceDue()` gates genuine
  work; advance is a multi-call drain (several rewarded calls/day). buy is bounded once/day/sub +
  real-subscription-cost. Neither needs the open leg's pro-rate.

### D-03 — single day-start epoch (DISSOLVED by D-07)
- **GAS-03 is now satisfied by DELETION, not single-sourcing.** Dropping the autoBuy stall multiplier
  (D-07: only advance escalates) removes AfKing's autoBuy stall ladder (`:823-838`) + its absolute-day
  stall epoch (`:992-993`). Advance becomes the SOLE stall epoch → there are no two epochs to
  "collapse." The original D-03 ("keep both, single-source via design-1") is moot. (Pre-redesign D-03
  text retained in git history; do not re-litigate the dual-epoch — it no longer exists.)

### D-06 — `doWork(maxCount==0)` fixed default count (SUPERSEDED by D-07)
- **Superseded.** `doWork` is parameterless (D-07); there is no `maxCount` sentinel. The fixed per-leg
  default batch is now intrinsic to the parameterless `doWork`; the standalone parametered
  `autoOpen(count)`/`autoBuy(count)` are the manual/emergency escape. D-06d's "manual smaller-count
  retry on OOG" maps to those standalone parametered functions.

### D-01 / ROUTER-07 — router reentrancy disposition (re-grounded on the unified creditFlip)
- **NO `nonReentrant` guard on `doWork`** (carries forward; the unified model makes it STRONGER).
  Under RD-4 there is exactly ONE `creditFlip` in `doWork`, CEI-last, fed by legs that return
  counts/mult and never credit themselves. Every external call in the composition is to a
  pinned-trusted `ContractAddresses.*` contract; the reward is flip-credit (ledger), never an
  untrusted ETH push; player winnings flow through the pull-pattern `claimableWinnings`. Nothing to
  re-enter through.
- **D-01a (attestation obligation, amended):** grep-attest the "no untrusted ETH send" claim **per
  leg** (advance / autoOpen / `_autoBuy`) AND for the single `doWork` `creditFlip`, against `0cc5d10f`.
  Formal basis to record: *keeper-never-a-payee + no untrusted ETH send + one-category structural
  early-return + single-`creditFlip`-last CEI ordering*.
- **D-01b:** TST-02's `router→game→creditFlip` double-pay regression stays (roadmap SC for Phase 332),
  now near-trivial to satisfy (legs structurally cannot credit; only `doWork` credits once after the
  early-return).

### D-04 — guaranteed free-fallback `advanceGame()` caller (accepted; amended for the new order)
- **Rely on existing structural paths — add NO new fallback mechanism**
  (`feedback_frozen_contracts_no_future_proofing`). **NO advance-preemption carve-out** — a carve-out
  would conflict with RD-1's same-cycle-reveal rationale (preempting advance before buys queue defeats
  buying-into-the-closing-round). Backstop hierarchy: PRIMARY = the rewarded router advance leg;
  SECONDARY = permissionless `advanceGame()` 30+ min after the boundary (`_enforceDailyMintGate` tier-2
  bypass) + `DegenerusVault.gameAdvance()` / `StakedDegenerusStonk.gameAdvance()`; TERTIARY = the
  ~120-day death-clock.
- **D-04a (amended under autoBuy-highest-priority):** while subscriber buys pend, the router's
  *rewarded* advance leg is blocked. Buys drain monotonically (finite subscriber set, cursor advances
  each call), so advance runs once buys clear; worst case advance waits until buys drain or the 30-min
  permissionless fallback opens — a bounded delay, ACCEPTED (death-clock tolerates it; daily mechanics
  tolerate a ≤30-min delay). The original D-04 claim "the router bounty covers the first 30 min" is
  **amended**: under autoBuy-first, first-30-min advance during a buy backlog relies on the
  participant/pass/DGVE-majority bypass tiers + (at 30 min) the permissionless fallback, NOT the router
  bounty. The SPEC must re-attest invariant (c) under this order.

### D-05 — `autoResolve` → `degeneretteResolve` rename + flat ~1-BURNIE re-peg (CARRIED FORWARD, unchanged)
- Survives the redesign verbatim. Rename `autoResolve` → `degeneretteResolve` (+ `_autoResolveBet` →
  `_degeneretteResolveBet`, interfaces, tests). Re-peg from per-item break-even to a flat literal ~1
  BURNIE (1e18) flip-credit ONCE per tx (count-independent) gated at **≥3 NON-WWXRP** resolutions;
  revert `NoWork()` on zero; 1–2 resolved → resolved but UNPAID (lean = do-NOT-revert, don't strand a
  trailing tail). WWXRP excluded from BOTH the gate count and the reward (AUTO-04); AUTO-02 probe +
  per-item try/catch + self-resolve-allowed (REW-04) preserved. KEPT SEPARATE (router-fold OUT —
  blocked by caller-supplied `(players[], betIds[])`, no O(1) discovery; "one button" = frontend). The
  D-05c real-gas exploitability basis + the D-05f losing-bet-liveness grep (verified INERT-SAFE in the
  prior 329 run) carry forward. Rides BATCH-02 (330); GAS-06 (331 sanity check); TST-05 (332 proof).
  See the prior `329-ATTEST-DEGENERETTE-RESOLVE.md` (regenerate, do not assume).

### D-08 — new keeper-gas DOs (NEW — user, this discussion; all 3 in scope as GASOPT-03/04/05 in 330)
Registered as new GASOPT REQ-IDs owned by Phase 330 IMPL (structural contract changes → ride the ONE
batched diff alongside the router rework).
- **GASOPT-03 — batched keeper read.** NEW game-side `batchPurchaseForKeeper` / `keeperSnapshot`
  collapsing the per-player `claimableWinningsOf` STATICCALLs (held tree `AfKing:854` + `:888`) into
  ONE batched call (~2-3k/player). New function + interface surface. **SUBSUMES GASOPT-02** (it is the
  superset of the per-iteration `claimableWinningsOf` hoist) — fold GASOPT-02 into GASOPT-03.
- **GASOPT-04 — drop the per-player `AutoBought` event** (~1.5k/player). **NON-TRIVIAL test coupling:**
  `keccak256("AutoBought(address,uint32,uint256)")` is the per-player buy oracle across
  `AfKingConcurrency.t.sol`, `AfKingSubscription.t.sol`, `AfKingFundingWaterfall.t.sol`,
  `SweepPerPlayerWorstCaseGas.t.sol` (drained via `getRecordedLogs()`). The event-removal AND the
  test-oracle migration **must land together in 330** (the suite breaks the moment the event is gone).
  The migration is NOT purely mechanical: the concurrency suite proves *no-double-buy* via
  `_countAutoBoughtFor(sub)==1`, so the SPEC must specify re-expressing that invariant in
  `lastAutoBoughtDay` storage + pool/balance-delta terms WITHOUT weakening the SAFE-03 / H-CANCEL-SWAP
  proofs. The "no off-chain/frontend consumer" condition rests on the USER's confirmation (they own the
  keeper).
- **GASOPT-05 — remove the per-iteration `isOperatorApproved(player, AfKing)` check** (held tree
  `AfKing:838`, ~2.8k/player). The SUB is the consent unit (revoke = `setDailyQuantity(0)` →
  tombstone-skip; matches OPEN-E "consent-gate-at-subscribe + trust-the-sub"). **KEEP the subscribe-time
  `isOperatorApproved(fundingSource, subscriber)` gate (`:443`)**. **BLOCKING CONDITION:** the 333
  SWEEP must re-attest the 4 OPEN-E protections hold without `:838` BEFORE closure; if it fails, this
  removal is reverted before the milestone ships. Lands in 330, gated at 333.

### Claude's Discretion — resolved by reading source + grep against `0cc5d10f` (NOT user decisions)
- **Attestation baseline + held-diff disposition (user delegated):** attest all `file:line` against the
  **frozen v48.0-closure HEAD `0cc5d10f`** (the audit subject), noting line-drift vs the held-330 tree
  where it differs. The held 330 diff is the re-IMPL base: 330 re-IMPL **keeps the survivors** (advance
  bounty re-home + `(mult, rewardable)` tuple; `degeneretteResolve` rename + ≥3 re-peg; GASOPT-01
  MintModule `[rk]` hoists; the interface tuple + `advanceDue()`/`boxesPending()` views) and **reworks
  the now-superseded bounty implementation** (the held diff shipped the OLD per-item + two-stall-epoch +
  `doWork(maxCount)` + autoOpen gas-units model — all superseded by D-07). Whether the planner reworks
  the held diff in place or re-derives the bounty portions clean on top of the survivors is a 330
  tactical call.
- `advanceGame` return encoding — confirm `(uint8 mult, bool rewardable)`; mult = stall ladder
  (new-day) vs `1` (mid-day partial-drain `day==dailyIdx`) vs the gameover-path `mult=1` rewardable;
  decode in the `DegenerusGame.advanceGame` wrapper.
- The 3 advance-bounty `creditFlip` sites (`AdvanceModule:189/225/468`) — grep-confirm + classify (which
  are rewardable advance-leg work vs not) + confirm deletion leaves `advanceGame` functional + unrewarded
  standalone.
- Discovery-view forms (all O(1), no unbounded scans): `advanceDue()` (`_simulatedDayIndex() != dailyIdx
  || LR_MID_DAY != 0` — covers new-day AND mid-day partial-drain); `boxesPending()` (rngLock-aware per
  RD-3 — boxes pending at an unlocked, word-available round, incl. mid-day-resolved rounds); buys-pending
  via AfKing-local cursor reads (true even during rngLock per RD-2).
- The deletion surface for D-07/D-03: AfKing autoBuy stall ladder (`:823-838`) + stall epoch (`:992-993`);
  autoOpen gas-units machinery (`AUTO_OPEN_BOX_GAS_UNITS`, the open-leg `_ethToBurnieValue`/`priceForLevel`
  in the bounty path) — grep, classify dead-after-redesign, confirm no other dependent.
- v48 KEEP-04 affiliate-code passthrough survival (`bytes32("DGNRS")` two-tier 75/20/5) valid at v49 HEAD
  so the `autoBuy` affiliate-code passthrough survives the `_autoBuy` refactor (ROUTER-05 pre-condition).
- `AfKing` CEI invariant + cursor sites (`:99-106`, cursor, `creditFlip`) + `BOUNTY_ETH_TARGET` —
  edit-order anchors.
- The exact `329-SPEC.md` section structure + the producer-before-consumer (survivors-vs-reworked)
  edit-order map; plan/wave decomposition.

### REQUIREMENTS.md / ROADMAP.md amendments the planner MUST make (enumerated)
The redesign reverses/dissolves/adds requirements. Re-issue the SPEC with these, and amend
`.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md` (count moves from 31 → ~34):
- **ROUTER-01** — `doWork(maxCount)` → **parameterless `doWork()`** (D-07). Drop the `maxCount==0`
  sentinel language (D-06 superseded). Add the standalone parametered+unrewarded `autoOpen(count)` /
  `autoBuy(count)` emergency path.
- **ROUTER-02** — order → **autoBuy → advance → autoOpen** (RD-1).
- **ROUTER-04** — `boxesPending()` is **rngLock-aware** (RD-3) and covers mid-day-resolved rounds;
  buys-pending true during rngLock (RD-2). Still O(1).
- **ROUTER-05** — `_autoBuy` refactor + the dropped rngLock guard (RD-2) + the unified bounty (RD-4);
  `degeneretteResolve` rename/re-peg unchanged (D-05).
- **NEW: autoBuy = normal buy / drop rngLock guards (RD-2)** — needs a REQ home (extend ROUTER-05 or a
  new ROUTER-08); includes the `batchPurchase:1693` removal + the Q5 dependent grep.
- **NEW: block autoOpen during rngLock + drop try/catch + entry-gate (RD-3/RD-5)** — needs a REQ home
  (new ROUTER-09 / ADV-adjacent).
- **NEW: unify bounty into doWork (RD-4)** — needs a REQ home (new ROUTER-10); reverses old R4.
- **ADV-02 / GAS-03** — advance returns mult with mid-day `mult=1` (no escalation); GAS-03 now
  "satisfied by deletion — advance is the sole stall epoch" (D-03 dissolved).
- **GAS-02** — "per-item MARGINAL break-even" → **flat-per-tx per-category** (D-07: advance `2×·mult`,
  buy `1.5×`, open `1×` pro-rated below the knee). GAS-01 still derives the per-category max-laden
  marginal (sizes `1×` + ratios + the open knee).
- **GAS-04** — stall ladder (1/2/4/6) kept, **advance-only**.
- **GAS-05 / WR-01** — re-prove no +EV loop under flat-per-tx, especially the open small-batch +
  low-gas corner.
- **NEW: GASOPT-03 / GASOPT-04 / GASOPT-05** (D-08); fold GASOPT-02 into GASOPT-03.
- **TST-01** (freeze fuzz) — add: autoBuy-during-rngLock safe, autoOpen-blocked-during-rngLock + no
  marooned boxes, unified-bounty one-category / no-double-pay (Q4).
- **TST-04 (regression)** — the GASOPT-04 test-oracle migration (event → storage/balance) must keep the
  suite net-zero vs the v48 baseline.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner re-issuing 329-SPEC.md) MUST read these before planning.**

### The redesign (the binding re-SPEC input)
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-ROUTER-REDESIGN-INTENT.md`
  — the 5 locked changes, Q1/Q2/Q5 resolutions, the autoBuy-gas analysis (the GASOPT-03/04/05 source),
  the survivors-vs-reworked split.
- `.planning/phases/329-.../329-DISCUSS-CHECKPOINT.json` — this discussion's decision accumulator
  (cleaned up after the canonical CONTEXT/SPEC are written).

### Scope + requirements + roadmap
- `.planning/ROADMAP.md` — Phase 329 goal + SCs (the SPEC's bar) + Phases 330-333; the cross-cutting
  rule + posture (§ v49.0). **Amend per the enumerated list in `<decisions>`.**
- `.planning/REQUIREMENTS.md` — the v49.0 REQ-IDs + Traceability + Out-of-Scope. **Amend (31 → ~34).**
- `.planning/PROJECT.md` — "Current Milestone: v49.0".

### Locked milestone research (no research sub-phase)
- `.planning/research/SUMMARY.md` — router-on-AfKing, the 8 pitfalls, the SPEC-time gaps.
- `.planning/research/ARCHITECTURE.md` · `.planning/research/PITFALLS.md` · `.planning/research/FEATURES.md`.
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` — §7 faucet locks; §9 OPEN-C/OPEN-D.
- `.planning/PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` — v48 KEEP-04 affiliate wiring (ROUTER-05 pre-cond).

### v48 precedent (the SPEC shape to mirror)
- `.planning/milestones/v48.0-phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-SPEC.md`
  (+ its `325-CONTEXT.md` + `325-ATTEST-*.md`) — §0 corrections / §1 reconciliation / §2 blueprint +
  edit-order-map + per-anchor ATTEST grep-tables.

### Audit baseline (the frozen HEAD all attestations grep against)
- v48.0-closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (`0cc5d10f`).

### Source (read from `contracts/` ONLY — and re-grep vs `0cc5d10f`; the working tree is the held diff)
- `contracts/AfKing.sol` — `doWork`/`autoBuy`/`_autoBuy`, the `:717` rngLock guard (RD-2 remove), the
  `:823-838` autoBuy stall ladder + `:992-993` epoch (D-07/D-03 delete), `:838` isOperatorApproved
  (GASOPT-05 remove), `:443` subscribe-time gate (KEEP), `:854/:888` `claimableWinningsOf` (GASOPT-03),
  the `AutoBought` event `:186/:954` (GASOPT-04), CEI `:99-106`, `BOUNTY_ETH_TARGET`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame` `(mult, rewardable)`, the 3
  `creditFlip` sites `:189/225/468` (ADV-01 delete), the new-day stall block + mid-day `mult=1` path,
  `totalFlipReversals` nudge, 30-min bypass, death-clock.
- `contracts/DegenerusGame.sol` — `advanceGame` wrapper, `autoOpen` (`:1701/1707/1719` try/catch + the
  open-leg gas-units bounty — RD-4/RD-5/D-07 rework), `batchPurchase` `:1693`/`:1694` (RD-2),
  `advanceDue()`/`boxesPending()` views, `degeneretteResolve` (D-05).
- `contracts/interfaces/IDegenerusGame.sol` + `IDegenerusGameModules.sol` — `autoOpen`/`autoBuy`
  return-shape changes (RD-4) + the new `keeperSnapshot`/`batchPurchaseForKeeper` (GASOPT-03) + the
  advance tuple + views.
- `contracts/DegenerusVault.sol` / `contracts/StakedDegenerusStonk.sol` — `gameAdvance()` fallback
  wrappers (D-04, read-only confirm).
- `contracts/DegenerusGameStorage.sol` — `_queueTickets → _livenessTriggered()` revert `:571` (RD-5
  entry-gate basis; KEEP for direct opens).
- Tests keyed on `AutoBought` (GASOPT-04 migration): `test/fuzz/AfKingConcurrency.t.sol`,
  `test/fuzz/AfKingSubscription.t.sol`, `test/fuzz/AfKingFundingWaterfall.t.sol`,
  `test/gas/SweepPerPlayerWorstCaseGas.t.sol`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Shared per-item base + conversion** (`BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mp`, held tree
  `doWork:618` advance + `:1022` autoBuy): advance + autoBuy ALREADY share this base — D-07 unifies
  autoOpen onto it (deleting the open-leg gas-units conversion) and flattens to per-tx.
- **`degeneretteResolve` flat ≥3-gate re-peg** (D-05): the precedent for D-07's flat-per-tx faucet
  doctrine (flat reward kept below real gas; gate where a small-batch corner exists).
- **`advanceDue()` / `boxesPending()` O(1) views** (held tree `DegenerusGame:479/492`): the discovery
  predicates `doWork` routes on; `boxesPending` gains rngLock-awareness (RD-3).
- **`_enforceDailyMintGate` 30-min bypass + `DegenerusVault.gameAdvance()` / `StakedDegenerusStonk.
  gameAdvance()`**: invariant-(c) fallbacks (D-04).
- **`lastAutoBoughtDay` storage stamp** (`AfKing:92/953`): the GASOPT-04 no-double-buy oracle
  replacement for the dropped `AutoBought` event.

### Established Patterns
- **AfKing CEI-everywhere, no-guard, keeper-never-a-payee** (`:99-106`): D-01 preserves it; the
  unified single-`creditFlip`-in-`doWork` (RD-4) makes the no-guard case cleaner.
- **One gas-pegged `creditFlip` per tx, never per-item**: the faucet-bound shape D-07's flat-per-tx +
  one-category early-return preserves.
- **advanceGame is an incremental multi-call drain** (`_runProcessTicketBatch` per call, returns
  `STAGE_TICKETS_WORKING` + `rewardable=true`, `revert NotTimeYet()` only when done): several rewarded
  advance calls per day; the stall block is commented "new-day path only" → mid-day returns `mult=1`.

### Integration Points
- `doWork()` (parameterless, `AfKing.sol`) → `IGame.advanceGame()` `(mult, rewardable)` /
  `IGame.autoOpen()` (returns raw open-count) / internal `_autoBuy()` (returns raw buy-count) → ONE
  `creditFlip` from the per-category flat formula. Direct calls unrewarded.
- `keeperSnapshot` / `batchPurchaseForKeeper` (NEW, GASOPT-03) on `DegenerusGame` + interface — the
  batched per-player read the `_autoBuy` loop consumes.

</code_context>

<specifics>
## Specific Ideas

- "Make this whole thing simpler" → the flat-per-tx model (D-07): `doWork()` parameterless, per-category
  multiples `1× / 1.5× / 2×` of "an average max-laden tx at 0.5 gwei worth of BURNIE flip," advance
  scaled by the stall multiplier (new-day only), open pro-rated below ~5 boxes. "Those numbers are fine
  to start with."
- The SPEC is the structural analog of v48's `325-SPEC.md` (§0 corrections / §1 reconciliation / §2
  blueprint + edit-order-map, per-anchor ATTEST grep-tables). Paper-only; peg numbers are GAS-331
  placeholders.

</specifics>

<deferred>
## Deferred Ideas

- **`degeneretteResolve` FOLDED INTO the on-chain router** — deferred (caller-supplied-arrays, no O(1)
  discovery; the unified "one button" is a frontend concern). The re-peg itself (D-05) is in scope.
- The keeper off-chain indexer / webpage stays a separate frontend track (OUT of scope, per PROJECT.md).
- Other milestone-level out-of-scope items (`Sub` memory-snapshot opt, `batchPurchase` try/catch bypass,
  `1 ether - decayN` unchecked, SWAP cash-share tighten, standing profit-margin bounty, external keeper
  networks) — see `.planning/REQUIREMENTS.md` § Out of Scope.

</deferred>

---

*Phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria*
*Context gathered: 2026-05-26 (original) · re-SPEC revised: 2026-05-26*
