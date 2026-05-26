# Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants - Context

**Gathered:** 2026-05-26
**Status:** Ready for planning

<domain>
## Phase Boundary

The v49.0 design-lock phase (direct analog of v48's Phase 325 / v47's Phase 321). Produce
`329-SPEC.md` — a **paper-only** reconciliation, **zero `contracts/*.sol` mutation** — that lets
Phase 330 author ONE fully-reconciled batched diff with no "by construction" assumptions. Four
jobs (REQ owners BATCH-01, ROUTER-07, ADV-04, GAS-03):

1. **Lock the 4 structural invariants** (BATCH-01): (a) one-category structural early-return; (b)
   frozen advance-consume (`v45-vrf-freeze-invariant` re-attested under the new router composition,
   incl. the player-controllable `totalFlipReversals` nudge `AdvanceModule.sol ~:1838-1844`); (c)
   guaranteed free-fallback `advanceGame()` caller (so re-homing the bounty creates no single-point
   liveness risk); (d) single day-start epoch (GAS-03).
2. **Settle the shared signatures** so no downstream file ships an intermediate broken state: the
   `advanceGame` return shape (design-1 `(uint8 mult, bool rewardable)`), the `doWork(maxCount)`
   signature + its no-work signal (ROUTER-06), and the O(1) discovery views (`advanceDue()` covering
   both new-day AND mid-day partial-drain, `boxesPending()`, buys-pending via AfKing-local cursor
   reads — ROUTER-04, no unbounded scans).
3. **Decide the two flagged dispositions** (ROUTER-07 reentrancy / OPEN-C + GAS-03 single epoch) on
   paper — captured in `<decisions>` below.
4. **Grep-attest every cited `file:line`** across the SUMMARY + the milestone scope against the
   v48.0-closure HEAD `0cc5d10f`; correct any drift in the SPEC; no "single fn reaches all paths"
   claim survives un-grepped (the `DegenerusGame` mint/jackpot inline-duplication precedent,
   `feedback_verify_call_graph_against_source`). Confirm the producer-before-consumer edit-order map
   for IMPL.

**No research** — the milestone design is LOCKED in `.planning/research/SUMMARY.md` (HIGH
confidence) + the milestone discussion. This phase is attestation + design-finalization +
shared-signature reconciliation only. Security / RNG-freeze floor over gas
(`feedback_security_over_gas` + `v45-vrf-freeze-invariant`).

</domain>

<decisions>
## Implementation Decisions

### ROUTER-07 — router reentrancy disposition (DISCUSSED — user 2026-05-26)
- **D-01: NO `nonReentrant` guard on `doWork`.** Preserve AfKing's documented invariant
  (`AfKing.sol:100` — *"No reentrancy guard — strict CEI everywhere; the keeper is never a payee in
  any contract it calls"*). The user's basis, accepted: `doWork` never sends ETH to `msg.sender`
  (the bounty pays as `creditFlip` *flip-credit* to the player; `burnForKeeper` burns — the keeper
  is never a payee), and the composition sends ETH only to **pinned-trusted** `ContractAddresses.*`
  protocol contracts, **never to an untrusted address** (player winnings flow through the
  pull-pattern `claimableWinnings` ledger, not a synchronous push). With no untrusted control-flow
  handoff anywhere in the composition, there is nothing to re-enter through; a guard would guard
  nothing.
- **D-01a (attestation obligation):** per the milestone's no-"by construction" rule, the SPEC author
  MUST grep-attest the "no untrusted ETH send" claim **per leg** (`advance` / `autoOpen` /
  `_autoBuy`) against `0cc5d10f` — verify each leg routes player value through `claimableWinnings`
  (pull) and sends ETH only to `ContractAddresses.*` — so the disposition rests on a checked fact,
  not an assumption. Record the formal basis in `329-SPEC.md` as: *keeper-never-a-payee + no
  untrusted ETH send + one-category structural early-return + `creditFlip`-last CEI ordering*.
- **D-01b:** TST-02's `router→game→creditFlip` double-pay reentrancy regression stays as the
  empirical backstop **regardless** of the guard decision (it is a roadmap success criterion for
  Phase 332). The SPEC must scope it to prove the no-guard disposition empirically.

### ROUTER-06 — `doWork` no-work signal (DISCUSSED — user 2026-05-26)
- **D-02: Revert with a dedicated `NoWork()` error** at the `doWork` level — consistent with
  AfKing's existing anti-spam revert idiom (`EmptyAutoBuy` on `autoBuy(0)`; `NoSubscribersAutoBought`
  when `successfulPlayers == 0`). The revert fires ONLY when all three O(1) predicates are empty (no
  advance due, no boxes pending, no buys pending); because `doWork` enters a leg only when that
  leg's predicate has work, the leg's own internal revert never trips. NOT a bool/sentinel return
  (rejected: breaks the established idiom; the discovery views are the keeper's pre-call probe).

### GAS-03 — single day-start epoch (DISCUSSED — user 2026-05-26)
- **D-03: Design-1 satisfies GAS-03 — do NOT physically merge the two epoch formulas.** The advance
  stall multiplier is computed ONCE in `AdvanceModule` (`:243-246`, game-day epoch
  `(day-1+DEPLOY_DAY_BOUNDARY)*1days+82620`) and **returned** via design-1; the router consumes the
  returned value and never recomputes — so the money-path "no-recompute / no off-by-one" goal
  (Pitfall 4) is met. AfKing's autoBuy stall epoch (`:824-826`, absolute-day
  `today*1days+82620` where `today=_currentDay()`) is left **untouched** — it is a *different
  category's* multiplier, self-contained, correct, and not duplicated anywhere.
- **D-03a (rationale to record in SPEC):** the two formulas are NOT duplicating the same number —
  they intentionally measure different things: AfKing's autoBuy multiplier = elapsed since the start
  of the *current absolute day* (resets at the 22:57 boundary each midnight — correct for a per-day
  buying window); AdvanceModule's advance multiplier = elapsed since the start of the *lagging
  game-day `dailyIdx`* (keeps growing across a multi-day stall — correct for advance liveness
  escalation). The SPEC must grep-attest both formulas vs `0cc5d10f` and explicitly document why
  they differ, so a future auditor does not flag the divergence as a bug. Rejected: physical
  unification (risks shifting AfKing's tested autoBuy escalation timing + conflates two semantics)
  and the constant-only DRY middle ground.

### Invariant (c) — guaranteed free-fallback `advanceGame()` caller (DISCUSSED — user 2026-05-26)
- **D-04: Rely on existing structural paths — add NO new fallback mechanism**
  (`feedback_frozen_contracts_no_future_proofing`). After the advance bounty re-homes to the router,
  the SPEC attests invariant (c) on the existing structure, designated backstop hierarchy:
  - **PRIMARY (rewarded):** the router's advance leg keeps the stall-escalating advance bounty — the
    primary liveness incentive is *preserved*, just re-homed from standalone `advanceGame()` into
    `doWork`. Re-homing reduces no structural caller; it only moves the payment.
  - **SECONDARY (structurally-guaranteed, unrewarded):** standalone `advanceGame()` is permissionless
    to **anyone 30+ min after the day boundary** (`AdvanceModule._enforceDailyMintGate` tier-2
    bypass `~:1008`, `if (elapsed >= 30 minutes) return;` — unconditional). The first-30-min window
    is covered with no gap by the router bounty (escalating 2× at 20 min) + the participant/pass /
    DGVE-majority bypass tiers. Plus the explicit protocol-owned wrappers `DegenerusVault.gameAdvance()`
    (`onlyVaultOwner`, calls `advanceGame()` at `DegenerusVault.sol:528` — always-bypass via DGVE
    majority) and `StakedDegenerusStonk.gameAdvance()` (permissionless wrapper, calls `advanceGame()`
    at `StakedDegenerusStonk.sol:422`).
  - **TERTIARY (failsafe):** the ~120-day death-clock (`AdvanceModule.sol:109` L1+ 120-day; extends
    by stall duration `:1198`) latches gameOver if the game is truly abandoned.

### autoResolve → degeneretteResolve rename + flat ~1-BURNIE "lose" re-peg (DISCUSSED — user 2026-05-26; scope addition)
- **D-05: Rename `autoResolve` → `degeneretteResolve` and re-peg its bounty from per-item
  break-even to a flat literal ~1 BURNIE flip-credit per tx (regardless of how many bets resolve),
  gated at ≥3 successfully-resolved NON-WWXRP bets — KEEP it a separate call (NOT folded into the
  router).** `autoResolve` (`DegenerusGame.sol:1587`) already is a permissionless, faucet-safe
  keeper bounty (per-item break-even `_ethToBurnieValue(AUTO_RESOLVE_BET_GAS_UNITS *
  AUTO_GAS_PRICE_REF, …)`, WWXRP excluded AUTO-04, self-resolve allowed REW-04, AUTO-02 probe,
  per-item try/catch). It is NOT foldable into `doWork` on-chain: pending bets live in
  `degeneretteBets[player][betId]` with NO O(1) enumeration — it requires caller-supplied
  `(players[], betIds[])` from off-chain indexing; enumerating on-chain = unbounded scan = violates
  ROUTER-04. The unified "one button" is therefore a FRONTEND concern (the keeper UI, separate
  track, already indexes the arrays and can fire `doWork()` + `degeneretteResolve(...)` together) —
  NO router/signature change.
- **D-05a (rename surface):** rename the external `autoResolve` → `degeneretteResolve` + the
  `onlySelf` internal wrapper `_autoResolveBet` (`:1684`) → `_degeneretteResolveBet`, plus the
  `IDegenerusGame`/`IDegenerusGameModules` signatures and any callers/tests. It deliberately leaves
  the `auto*` family — it is no longer a gas-pegged router/keeper action; it is a distinct
  flat-"lose" Degenerette-resolution helper. (Mechanical rename rides BATCH-02.)
- **D-05b (payment shape + gate):** pay a flat literal ~1 BURNIE (1e18) flip-credit ONCE per tx
  (NOT per-item, count-independent) IFF ≥3 NON-WWXRP bets resolve successfully in the call; revert
  `NoWork()` when ZERO bets resolve (the user's revert-on-no-work). **Lean for the 1–2-resolved
  case: still resolve them, pay 0 (below the ≥3 pay-gate) — do NOT revert below 3, so a legit
  trailing 1–2-bet tail is never stranded/un-resolved (revert would roll back the resolutions).**
  The revert-vs-unpaid boundary at 1–2 is a SPEC/IMPL detail to confirm (lean = resolve-always,
  pay-at-≥3, revert-only-at-0).
- **D-05c (the "never remotely exploitable" basis — CORRECTED):** an earlier draft wrongly compared
  1 BURNIE against the 0.5-gwei *pegging reference* (`AUTO_GAS_PRICE_REF`, a deliberately
  below-market accounting figure) as if it were real gas — USER correctly pushed back. The real
  basis: the keeper pays REAL tx gas (base 21k + ≥3 resolutions + overhead) on every call at the
  PREVAILING gas price (typically 5–50+ gwei), while 1 BURNIE flip-credit is worth at most
  `mintPrice/1000` ETH by the protocol's own (generous) peg (≤ 0.00024 ETH even at the 0.24-ETH
  milestone price) AND is illiquid (locked in coinflip → real extractable value is a fraction). So
  1 BURNIE sits far below the real cost of even the 3-resolution minimum → every qualifying tx is a
  net loss → no positive-EV farm. The ≥3 gate only widens the margin. The only theoretical
  positive corner — {late game (mintPrice 0.24) ∧ gas < ~3.6 gwei ∧ flip-credit fully extractable
  at the peg} — is gated by an almost-certainly-false illiquidity assumption.
- **D-05d (WWXRP + existing invariants preserved):** WWXRP (currency==3) stays excluded — the ≥3
  count is NON-WWXRP only (WWXRP still earns zero and does NOT count toward the gate), so a
  WWXRP-only batch can't trip it (AUTO-04 intent). AUTO-02 probe (item-0 already-resolved →
  `BatchAlreadyTaken`), per-item try/catch isolation, and self-resolve-allowed (REW-04 — even safer
  now that the reward is a flat "lose") all unchanged.
- **D-05e (GAS-06 sanity check — NOT a blocker):** at Phase 331, confirm the literal ~1 BURNIE
  stays below the REAL gas of a 3-resolution tx across the plausible gas-band — specifically the
  low-gas/high-mintPrice corner — factoring flip-credit illiquidity; only lower the constant or add
  a scaled gate if a *realistic* corner actually flips positive-EV. (The exact constant is soft —
  "1 burnie or something like that" — confirmed-sub-real-gas at GAS.)
- **D-05f (liveness nuance the SPEC author MUST verify):** a flat "lose" removes the rational-keeper
  incentive to resolve LOSING bets (winning bets are still self-resolved by owners claiming
  winnings). The SPEC author MUST grep-verify whether the protocol REQUIRES losing Degenerette bets
  to be resolved for ANY invariant/accounting/RNG-slot/cleanup reason. If inert cruft → safe; if a
  backlog/invariant risk → surface to USER (do NOT silently starve a needed path). NOTE: a flat
  count-independent reward actually NUDGES clearing the whole backlog in one tx (max work per paid
  tx), which helps backlog liveness.
- **D-05g (scope):** NEW v49.0 item — registered as **GAS-06** (rename + flat-~1-BURNIE re-peg +
  ≥3 gate + the real-gas sanity check, Phase 331) + **TST-05** (prove rename + flat-not-per-item +
  ≥3 pay-gate + revert-on-no-work + WWXRP-excluded-from-count + same resolution results, Phase
  332); the bounty-logic + rename code change rides the ONE batched diff (BATCH-02, Phase 330).
  ROUTER-05's "keeps its own in-game bounty unchanged" is amended to "…RENAMED + RE-PEGGED per
  GAS-06 (still a separate call)." `degeneretteResolve` stays out of the router.

### doWork(maxCount=0) — fixed gas-budget-sized default count, "do max work, never OOG (common case)" (DISCUSSED — user 2026-05-26; scope addition)
- **D-06: `maxCount == 0` is a SENTINEL resolving to a FIXED per-leg default count, calibrated as
  `≈ GAS_BUDGET / avg_marginal_cost_per_atomic_op` (GAS_BUDGET ~10M gas — PLACEHOLDER), applied to the
  count-bounded legs (`autoOpen`, `_autoBuy`).** A plain `while (processed < DEFAULT_COUNT && cursor <
  len)` — NOT a per-iteration `gasleft()`-bounded loop, NOT a gas-unrelated item count, NOT an unbounded
  process-all. Today at `0cc5d10f` `doWork(0)` would be a footgun (`autoBuy(0)` reverts `EmptyAutoBuy`
  `AfKing.sol:569`; `autoOpen(0)` no-ops — the `:1656` loop `while (cursor < qlen && opened < maxCount)`
  never enters); D-06 makes `0` a friendly "do a sensible budget of work" default.
- **D-06a (why fixed-count, not `gasleft()`):** `gasleft()` is NOT the cost concern — the `GAS` opcode is
  2 gas, negligible. The reason to prefer a fixed default count is SIMPLICITY: no per-iteration branch and
  no fragile per-iteration **reserve-floor** constant (a `gasleft` loop only "never OOGs" if its reserve
  floor is ≥ the true worst-case single iteration + finalization — the same worst-case-estimation problem,
  just relocated). The trade: the fixed-count never-OOG is STATISTICAL, not ABSOLUTE (see D-06d).
- **D-06b (sizing + headroom):** per-leg `DEFAULT_AUTO_OPEN_COUNT` / `DEFAULT_AUTO_BUY_COUNT` constants
  `= floor(~10M / avg-marginal-per-item)`. Sizing the default to a ~10M budget while a keeper can supply
  up to the block gas limit (~30M on mainnet) leaves generous headroom (≈3×) — a batch whose items
  average well above the mean (the user's ~67% overcost figure and beyond) still completes under the
  supplied limit. Exact budget + per-leg counts calibrated at GAS (331).
- **D-06c (advance leg unaffected):** `advanceGame()` takes NO count arg and already does its own
  internally-bounded ticket batch (incl. the mid-day partial-drain `AdvanceModule.sol:225`) — D-06 applies
  ONLY to the `autoOpen` + `_autoBuy` legs; `maxCount` does not map to advance.
- **D-06d (worst-case OOG is non-catastrophic + manually fixable — ACCEPTED):** if a pathological
  worst-case-clustered batch exceeds the supplied gas, the tx reverts OUT-OF-GAS — which rolls back ALL
  state cleanly (no fund loss, no invariant break, no partial corruption); the keeper retries with a
  smaller EXPLICIT `maxCount` (the manual escape hatch). never-OOG here is keeper-UX/liveness, NOT a
  security invariant, so the statistical (not absolute) guarantee is acceptable under the security floor.
  Advance liveness has its own independent fallbacks (D-04), unaffected. (Minor accepted trade vs
  `gasleft`: a fixed count is calibrated at deploy and does not auto-adapt to a post-deploy gas-schedule
  repricing; rare, still manually fixable — `feedback_frozen_contracts_no_future_proofing`.)
- **D-06e (EmptyAutoBuy reconciliation):** under `count==0`-means-default, the router's `_autoBuy(0)`
  path MUST NOT revert `EmptyAutoBuy` — it processes the default-count batch. SPEC author settles whether
  the standalone external `autoBuy(uint256)` also adopts `0`=default (dropping/repurposing `EmptyAutoBuy`)
  or keeps its revert with only `_autoBuy`/`doWork` applying the default. Lean: the default lives in the
  shared internal `_autoBuy`, so `0`=default everywhere and `EmptyAutoBuy` is removed/repurposed — confirm
  at SPEC, verify at TST.
- **D-06f (faucet-safety — NOT a new faucet):** the autoBuy/autoOpen bounties are per-item break-even
  (GAS-02 per-item MARGINAL; `AfKing.sol:845` `bountyEarned = batchLen * peg`). A larger default batch
  pays proportionally more bounty AND costs proportionally more gas → still per-item break-even, NO
  positive-EV from batching; the GAS-05 WR-01 round-trip guard must hold at the MAX default-count batch.
  The one-category early-return (invariant a) is preserved: `doWork(0)` does ONE category's default batch,
  one `creditFlip` per tx.
- **D-06g (placeholders + handoffs + traceability):** GAS_BUDGET (~10M) + the per-leg DEFAULT_*_COUNT
  constants are SPEC PLACEHOLDERS — calibrated at GAS (331) from GAS-01's avg + worst-case marginal
  per-item gas (avg sizes the count; worst-case sizes the headroom margin; the v46 Phase 319 CR-01
  "peg to the marginal, never a single total" discipline applies to the avg estimate). The
  never-OOG-in-the-common-case + manual-smaller-count fallback proof is a TST (332) item. D-06 **REFINES**
  the in-scope ROUTER-01 (`doWork(maxCount)` signature — IMPL 330) + GAS-01 (marginal/avg gas calibration
  — 331) + TST-02 (router behavior proof — 332); **NO new REQ-IDs minted** (refines the existing
  `doWork(maxCount)` signature, unlike D-05's separate `degeneretteResolve` function).

### Claude's Discretion — pure attestations resolved by reading source (NOT user decisions)
The SPEC author resolves these from the live `contracts/` + grep against `0cc5d10f`; they were
intentionally NOT put to the user (grep/derive/fact-check work, not design choices):
- **`advanceGame` return encoding:** confirm design-1 `(uint8 mult, bool rewardable)` — whether
  `rewardable` is a distinct bool (it is: a leg can do work but be non-rewardable, and `mult` can be
  ≥1 independent of rewardability) vs implied by `mult>0`. Settle the exact tuple/packing and decode
  in the `DegenerusGame.advanceGame` wrapper (`:275`).
- **The 3 advance-bounty `creditFlip` sites** (`AdvanceModule.sol:189` new-day / `:225` mid-day
  partial-drain / `:468`): grep-confirm all three exist at `0cc5d10f`, classify each (which are
  rewardable advance-leg work the `rewardable` flag must cover — incl. the ADV-05 mid-day
  partial-drain `:225` site — vs any that should NOT be router-rewardable), and confirm deletion
  leaves `advanceGame` fully functional + unrewarded standalone.
- **Discovery-view signatures + location:** `advanceDue()` must cover BOTH new-day
  (`currentDayView() != dailyIdx`) AND mid-day partial-drain (`day == dailyIdx` but
  tickets-not-fully-processed); `boxesPending()` (`boxPlayers[activeIndex].length > boxCursor` AND
  `lootboxRngWordByIndex[activeIndex] != 0`); buys-pending via AfKing-local cursor reads. Settle
  whether advance/boxes views live on `DegenerusGame` and buys on `AfKing`-local — all O(1), no
  unbounded scans.
- **`maxCount` semantics across legs:** how `doWork(maxCount)` maps `maxCount` onto each routed leg
  (advance / `autoOpen(maxCount)` / `_autoBuy(maxCount)`). The `maxCount == 0` default is now the LOCKED
  decision **D-06** (fixed gas-budget-sized default count); this Discretion item is the grep-attestation
  of the CURRENT count-handling sites D-06 builds on — `autoBuy(0)` revert `AfKing.sol:569`, `autoOpen(0)`
  no-op loop `DegenerusGame.sol:1656`, `advanceGame` no-count — and confirming no existing fixed-default /
  gas-bounded-loop pattern exists (so D-06 is a NEW IMPL behavior at 330).
- **v48 KEEP-04 affiliate-code passthrough survival:** confirm the VAULT registered-affiliate-code
  wiring (`bytes32("DGNRS")` two-tier 75/20/5) is valid at v49 HEAD so the `autoBuy` affiliate-code
  passthrough survives the `_autoBuy` internal refactor (ROUTER-05 pre-condition).
- **`AfKing` CEI invariant + cursor sites** (`:99-106`, `:577` cursor, `:846` `creditFlip`) and the
  `BOUNTY_ETH_TARGET` (`:263`) — grep-attest as the SPEC's edit-order anchors.
- **Producer-before-consumer edit-order map** + the exact section structure of `329-SPEC.md`; the
  break-even peg targets land as SPEC *placeholders* (calibrated at the GAS phase 331).
- **Plan/wave decomposition** for the SPEC deliverables.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner producing 329-SPEC.md) MUST read these before planning.**

### Scope + requirements + roadmap
- `.planning/ROADMAP.md` — Phase 329 goal + 4 success criteria (the SPEC's acceptance bar);
  Phases 330/331/332/333 for downstream awareness; the milestone cross-cutting rule + posture (§ v49.0).
- `.planning/REQUIREMENTS.md` — the 29 v49.0 REQ-IDs; phase-329 owners BATCH-01, ROUTER-07, ADV-04,
  GAS-03; the SPEC/IMPL/GAS/TST/TERMINAL split (§ Traceability); the Out-of-Scope list.
- `.planning/PROJECT.md` — "Current Milestone: v49.0" section (5 work items, locked design
  decisions, shared-surface map, key constraints).

### The locked milestone research (the binding design — no research sub-phase)
- `.planning/research/SUMMARY.md` — HIGH-confidence synthesis: router-on-AfKing decision, design-1
  recommendation, the 8 pitfalls + phase-to-prevention mapping, the 5 SPEC-time "Gaps to Address"
  (OPEN-C reentrancy, KEEP-04 passthrough, mid-day predicate form, stall-ceiling process,
  break-even placeholders).
- `.planning/research/ARCHITECTURE.md` — router-on-AfKing tradeoff table; design-1 vs alternatives;
  the files-touched map + edit-order rationale.
- `.planning/research/PITFALLS.md` — the 8 source-anchored pitfalls (Pitfall 1 VRF-freeze, 2
  bounty-stacking, 3 mis-calibration, 4 dual-epoch off-by-one, 5 unrewarded-advance liveness).
- `.planning/research/FEATURES.md` — must/should/defer feature list.
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` — §7 the three faucet locks; §9 OPEN-C/OPEN-D (the
  reentrancy disposition this phase closes for the router).
- `.planning/PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` — the v48 KEEP-04 VAULT affiliate-code wiring
  (ROUTER-05 passthrough pre-condition to re-confirm at v49 HEAD).

### v48 precedent (the established SPEC shape to mirror)
- `.planning/milestones/v48.0-phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-SPEC.md`
  — the §0 corrections / §1 reconciliation / §2 blueprint + edit-order-map structure to emulate.
- `.planning/milestones/v48.0-phases/325-.../325-CONTEXT.md` — the decisions / Claude's-Discretion /
  canonical-refs split this CONTEXT mirrors.
- `.planning/milestones/v48.0-phases/325-.../325-ATTEST-*.md` — the per-anchor grep-table format for
  the `file:line` attestations.

### Audit baseline (the frozen HEAD all attestations grep against)
- v48.0-closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (`0cc5d10f`).

### Source (read from `contracts/` ONLY — stale copies elsewhere must be ignored)
- `contracts/AfKing.sol` — the router's home; CEI invariant `:99-106`, autoBuy stall ladder
  `:823-838` + bounty/`creditFlip` `:846`, `_currentDay()` `:886`, cursor `:577`, `BOUNTY_ETH_TARGET`
  `:263`, the `EmptyAutoBuy`/`NoSubscribersAutoBought` anti-spam reverts.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame()` `:155`, `ADVANCE_BOUNTY_ETH`
  `:147`, the 3 `creditFlip` sites `:189/:225/:468`, stall multiplier + day-start `:238-255`,
  `_enforceDailyMintGate` 30-min bypass `~:1008`, `totalFlipReversals` nudge `~:1838-1844`,
  death-clock `:109/:1198`.
- `contracts/DegenerusGame.sol` — `advanceGame` wrapper `:275`, autoOpen/autoResolve + gas-peg
  constants `:1539-1546`, `currentDayView` `:462`.
- `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol` —
  current signatures (new views + updated `advanceGame` signature land here).
- `contracts/DegenerusVault.sol` (`gameAdvance` → `advanceGame()` call `:528`) +
  `contracts/StakedDegenerusStonk.sol` (`gameAdvance` → `advanceGame()` call `:422`) — the
  invariant-(c) protocol-owned fallback wrappers (read-only — confirm, do not modify).
- `contracts/ContractAddresses.sol` — pinned addresses + `DEPLOY_DAY_BOUNDARY` (freely modifiable
  per `feedback_contractaddresses_policy`, but not touched at SPEC).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **AfKing autoBuy stall ladder** (`:823-838`): the 1/2/4/6 escalation pattern the advance leg's
  re-homed bounty mirrors — but the advance multiplier comes from `advanceGame`'s return (design-1),
  NOT a copy of this block.
- **AfKing anti-spam reverts** (`EmptyAutoBuy`, `NoSubscribersAutoBought`): the precedent for
  ROUTER-06's `NoWork()` revert idiom (D-02).
- **`_enforceDailyMintGate` bypass ladder** (`~:983-1008`): the structural guarantee underpinning
  invariant (c) (D-04) — the 30-min universal bypass makes standalone `advanceGame()` permissionless
  to everyone for ~23.5h/day.
- **`DegenerusVault.gameAdvance()` / `StakedDegenerusStonk.gameAdvance()`**: the explicit
  protocol-owned unrewarded fallback callers (D-04).

### Established Patterns
- **AfKing CEI-everywhere, no-guard, keeper-never-a-payee** (`:99-106`): the invariant D-01 preserves
  — `doWork` must keep all state effects before external calls and `creditFlip` last.
- **Pull-pattern winnings (`claimableWinnings`)**: why there is no untrusted ETH send anywhere in
  the `doWork` composition (D-01) — the SPEC must grep-attest this per leg.
- **One gas-pegged `creditFlip` per tx, never per-item** (`:840-846`): the bounty-payment shape the
  router's one-category early-return preserves (invariant a + the faucet bound).
- **Two intentionally-distinct day epochs** (AfKing absolute-day `:824` vs AdvanceModule game-day
  `:243`): D-03 — design-1 single-sources the advance multiplier so they need not be merged.

### Integration Points
- `doWork(maxCount)` (NEW, `AfKing.sol`) → `IGame.advanceGame()` (returns `(mult, rewardable)`,
  design-1) / `IGame.autoOpen(maxCount)` / internal `_autoBuy(maxCount)` → one `creditFlip` for the
  re-homed advance bounty (open/buy legs keep their own in-callee bounty — router does NOT
  double-pay).
- `DegenerusGame.advanceGame` wrapper (`:275`) decodes + forwards the new delegatecall return to
  external callers — the producer that interfaces + the AfKing router consume.

</code_context>

<specifics>
## Specific Ideas

- The SPEC is the direct structural analog of v48's `325-SPEC.md` — same §0 corrections / §1
  reconciliation / §2 blueprint + edit-order-map shape, with per-anchor `ATTEST` grep-tables.
- Zero `contracts/*.sol` mutation this phase — paper-only. The break-even peg constants are SPEC
  placeholders; the real numbers are derived at the GAS phase (331) from worst-case marginal gas
  (the v46 Phase 319 CR-01 precedent).

</specifics>

<deferred>
## Deferred Ideas

- **`autoResolve` FOLDED INTO the on-chain router** — deferred (architecturally blocked by the
  caller-supplied-arrays requirement, D-05); the unified "one button" is a frontend concern. NOTE:
  the autoResolve *bounty re-peg* (D-05) is NOT deferred — it is an in-scope v49.0 addition
  (GAS-06 + TST-05). Only the router-fold is deferred.

Other milestone-level out-of-scope items — the `Sub` memory-snapshot gas opt, `batchPurchase`
try/catch bypass, `1 ether - decayN` unchecked, SWAP cash-share tighten, standing profit-margin
bounty, external keeper networks — are recorded in `.planning/REQUIREMENTS.md` § Out of Scope and
need no re-capture here.

</deferred>

---

*Phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria*
*Context gathered: 2026-05-26*
