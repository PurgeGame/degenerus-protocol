# Phase 330: IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts) - Context

> ⚠️ **STALE — PRE-REDESIGN (do NOT plan from the body below as-is).** This context was gathered
> `2026-05-26 10:43` BEFORE the keeper-router redesign pivot (the 330-07 hand-review). The body still
> describes the OLD design (`advance→open→buy`, `doWork(maxCount)`, dual-epoch single-source,
> legs-keep-their-own-bounty, GASOPT-01/02, 13 reqs).
>
> **Authoritative design for the 330 re-plan = `../329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md` (§1 redesigned signatures, §2 invariants + dispositions, §3 producer-before-consumer IMPL edit-order map) + `330-ROUTER-REDESIGN-INTENT.md` (the locked RD-1..RD-5 + D-07 + D-08 changes, traced).** The redesign: `autoBuy→advance→autoOpen`, parameterless `doWork()` + `NoWork()` + unrewarded standalone escapes, dropped rngLock guards (RD-2), block-autoOpen-during-rngLock + drop try/catch + entry-gate (RD-3/RD-5), unified single `creditFlip` in `doWork` (RD-4), D-07 flat-per-tx bounty, GAS-03 satisfied-by-deletion. Owned reqs are now **ROUTER-01/02/03/04/05/06/08/09/10, ADV-01/02/03/05, GASOPT-01/03/04/05, BATCH-02 (18, GASOPT-02 SUBSUMED into GASOPT-03)** — see ROADMAP/REQUIREMENTS (36-req set).
>
> **Before re-planning:** the 7 PLAN.md files + their SUMMARYs in this dir are the SUPERSEDED pre-redesign plans (their execution produced the held-330 working-tree diff). Re-plan with `/gsd-plan-phase 330 --force`. And decide whether to discard the held-330 diff (6 contracts/*.sol + 7 test/* files, still dirty) before the redesigned diff is applied — it's the old design.

**Gathered:** 2026-05-26 (pre-redesign — see staleness banner above)
**Status:** STALE pre-redesign — needs re-plan against 329-SPEC + 330-ROUTER-REDESIGN-INTENT

<domain>
## Phase Boundary

Apply the single reconciled `contracts/*.sol` diff in **producer-before-consumer order**, then HALT
at the contract-commit boundary for explicit user hand-review. This is the ONE contract phase of
v49.0 (the v48 Phase 326 analog). It owns 13 requirements: **ROUTER-01..06, ADV-01/02/03/05,
GASOPT-01/02, BATCH-02**.

The diff (edit-order from `329-SPEC.md` §3):
1. **`modules/DegenerusGameAdvanceModule.sol`** — delete the 3 caller-reward `creditFlip` sites
   (new-day / mid-day partial-drain ADV-05 / main new-day; the SDGNRS merge-credit STAYS) + add the
   design-1 `(uint8 mult, bool rewardable)` return to `advanceGame()`. **PRODUCER FIRST.**
2. **`DegenerusGame.sol`** — the `advanceGame` wrapper decode of the delegatecall `data` into the
   tuple on the success branch + the new O(1) `advanceDue()` / `boxesPending()` discovery views + the
   GASOPT-01 MintModule pointer reference. **(BATCH-02 rides here:** the `autoResolve` →
   `degeneretteResolve` + `_autoResolveBet` → `_degeneretteResolveBet` rename + the flat ~1-BURNIE /
   ≥3-NON-WWXRP-gate / revert-on-zero re-peg + the `RESOLVE_FLAT_BURNIE` constant.)
3. **`interfaces/IDegenerusGame.sol` + `interfaces/IDegenerusGameModules.sol`** — the new view
   signatures + the updated `advanceGame` tuple signature. **NO `degeneretteResolve` interface row**
   (C6: both symbols are defined directly on `DegenerusGame.sol`, never via an interface).
4. **`AfKing.sol`** — the `doWork(uint256 maxCount)` router (advance→autoOpen→autoBuy, one-category
   structural early-return) + the `NoWork()` error decl + the `autoBuy`→internal `_autoBuy` refactor
   hosting the D-06 fixed default-count + the re-peg/default-count placeholders + the GASOPT-02
   `claimableWinningsOf` hoist. **CONSUMER LAST.**
5. **`modules/DegenerusGameMintModule.sol`** — the GASOPT-01 `rk`-loop-invariant storage-pointer
   hoist (independent, gas-only; lands with step 2's pointer reference).

`DegenerusVault.sol` / `StakedDegenerusStonk.sol` (invariant-(c) fallback wrappers) and
`modules/DegenerusGameDegeneretteModule.sol` (the D-05 resolution path / `delete` :634) are
**read-only — NOT modified.**

**What this phase does NOT do:** set the final gas/count/BURNIE constants (placeholders here,
calibrated at Phase 331 GAS under a SECOND user-approved gate); write the behavioral test proofs
(Phase 332 TST). The diff is **locally compiled + tested but NEVER committed without explicit user
hand-review.**

</domain>

<spec_lock>
## Requirements (locked via 329-SPEC.md)

**13 requirements locked.** The full design — the 4 structural invariants, the R1–R4 shared
signatures, the dispositions, the per-item IMPL blueprint, and the producer-before-consumer
edit-order map — lives in
`.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md`.
**Downstream agents (researcher/planner/executor) MUST read 329-SPEC.md before planning or
implementing.** Requirements are NOT duplicated here.

**Locked by 329-SPEC (carried forward — do NOT re-decide):**
- **4 invariants** (CODE invariants, not comments): (a) one-category structural early-return; (b)
  frozen advance-consume (router consumes the design-1 RETURN, adds NO new in-window SLOAD; ADV-04);
  (c) guaranteed free-fallback `advanceGame()` caller from EXISTING paths only (D-04); (d) single
  day-start epoch via design-1 (GAS-03 — do NOT merge the two epochs; document why they differ).
- **R1** `advanceGame() returns (uint8 mult, bool rewardable)` (`mult` single-sourced at the
  AdvanceModule `:243-254` band; `rewardable` a DISTINCT bool, NOT implied by `mult>0`) + the `:275`
  wrapper `abi.decode` on the success branch.
- **R2** `doWork(uint256 maxCount)` + the `NoWork()` revert (fires only when all 3 O(1) predicates
  empty) + per-leg `maxCount` (advance self-bounded NO count; `autoOpen(maxCount)`,
  `_autoBuy(maxCount)`) + **D-06** `maxCount==0` → FIXED per-leg default count (plain
  `while (processed < DEFAULT_COUNT && cursor < len)`, NOT `gasleft()`; `EmptyAutoBuy`
  removed/repurposed so `0`=default everywhere; worst-case OOG = clean revert + manual retry,
  liveness-not-security).
- **R3** the 3 O(1) discovery views: `advanceDue()` (new-day `currentDayView() != dailyIdx` OR
  mid-day `LR_MID_DAY != 0`) + `boxesPending()` (`boxPlayers[idx].length > boxCursor` AND
  `lootboxRngWordByIndex[idx] != 0`) on `DegenerusGame`; buys-pending AfKing-local cursor. No
  unbounded scans (ROUTER-04).
- **R4** ONE `creditFlip` per `doWork` tx — the router pays ONLY the re-homed advance bounty (CEI,
  fired LAST, scaled by `mult`, gated on `rewardable`); the autoOpen/autoBuy legs keep their OWN
  in-callee bounty; no double-pay. KEEP-04 affiliate-code passthrough (`bytes32("DGNRS")` 75/20/5 at
  `DegenerusGame.sol:1781`, game-side) survives the `_autoBuy` refactor untouched (C1).
- **ROUTER-07 = NO `nonReentrant` guard** on `doWork`/any leg (D-01; basis: keeper-never-a-payee +
  no untrusted ETH send + one-category early-return + `creditFlip`-last CEI). Keep strict CEI.
- **D-05 `degeneretteResolve`** rename + flat ~1-BURNIE / ≥3-NON-WWXRP-resolved gate / resolve-and-pay-0
  for 1–2 / revert `NoWork()` at 0; per-item peg at `:1611-1614` → `++successCount`; post-loop
  `:1622` → `if (successCount >= 3) creditFlip(msg.sender, RESOLVE_FLAT_BURNIE)`; WWXRP stays
  excluded from the count; the router-fold is OUT (separate call). D-05f losing-bet liveness =
  **INERT-SAFE, no USER gate.**
- **GASOPT-01** (`MintModule` `rk`-pointer hoist in `processFutureTicketBatch` `:398` +
  `processTicketBatch` `:671`) + **GASOPT-02** (`AfKing.autoBuy` `claimableWinningsOf` hoist
  `:691`/`:722`) — both behavior-identical, gas-only.

**Out of scope (deferred to other v49.0 phases):** final peg/count/BURNIE constant calibration →
Phase 331 GAS (GAS-01/02/04/05/06); all behavioral test proofs → Phase 332 TST (TST-01..05); the
router-fold of `degeneretteResolve` → architecturally blocked (frontend concern, NOT this milestone).

> **Re-grep at edit time.** Every `file:line` in 329-SPEC §0 (incl. corrections C1–C6) shifts once
> the batched diff lands. IMPL re-anchors against live `contracts/` — NO un-grepped "by
> construction" claim survives (`feedback_verify_call_graph_against_source`). Baseline HEAD for any
> re-attest: `0cc5d10f` (live tree byte-identical to baseline).

</spec_lock>

<decisions>
## Implementation Decisions

### Placeholder strategy for the GAS-deferred constants (DISCUSSED — user 2026-05-26)
- **D-01: Best-guess + flagged constant.** The 330 diff must compile + run tests now, but the SPEC
  defers calibration to Phase 331. For the NEW constants with no prior calibration —
  `RESOLVE_FLAT_BURNIE`, `GAS_BUDGET`, `DEFAULT_AUTO_OPEN_COUNT`, `DEFAULT_AUTO_BUY_COUNT` — land
  **SPEC-derived realistic estimates** so tests run against meaningful values:
  `RESOLVE_FLAT_BURNIE = 1e18` (~1 BURNIE, D-05b), `GAS_BUDGET ≈ 10_000_000`, `DEFAULT_*_COUNT =
  floor(~10M / rough-avg)` (a round placeholder, e.g. 100 each — exact at 331).
- **D-01a (existing constants UNCHANGED):** the already-calibrated v46/v48 constants stay as-is —
  `AUTO_GAS_PRICE_REF = 0.5 gwei` (`:1539`), `AUTO_RESOLVE_BET_GAS_UNITS = 66_528` (`:1545`),
  `AUTO_OPEN_BOX_GAS_UNITS` (`:1546`). Phase 331 re-derives them against the applied diff; they are
  NOT zeroed or sentinel-ized at 330. (Note: `AUTO_RESOLVE_BET_GAS_UNITS` likely goes DEAD once the
  D-05b per-item peg is removed — grep at IMPL, D-05e; do NOT pre-delete on assumption.)
- **D-01b (flagged-marker block — the 331 re-anchor):** group the NEW placeholder constants under a
  named, greppable marker so Phase 331 has an unambiguous re-calibration target (e.g. a labelled
  block of declarations the GAS phase locates by name). **Comment-form constraint
  (`feedback_no_history_in_comments`):** any marker comment MUST describe what IS — e.g.
  `// SPEC placeholder; calibrated at the GAS phase` — NOT history ("was X", "changed from Y").
- **D-01c (recalibration guarantee is PROCEDURAL, not a code tripwire):** the user chose best-guess +
  marker, **NOT** the option-3 failing-placeholder test. So there is NO extra test scaffolding at 330
  that fails on un-calibrated constants. The guarantee that 331 recalibrates rests on: (i) the
  D-01b flagged-marker block, (ii) Phase 331's own GAS scope (GAS-01/02/04/05/06 explicitly
  calibrate), and (iii) the ROADMAP 331-depends-on-330 note *"tests must exercise calibrated
  constants, not placeholders."* This is consistent with the D-02 test-scope decision.

### Test work riding the 330 diff (DISCUSSED — user 2026-05-26)
- **D-02: Rename-fixes + parity only.** Do ONLY the mechanical test edits required to keep the suite
  compiling + green at v48-baseline parity: the 5 test files / 57 references to `autoResolve` /
  `_autoResolveBet`, INCLUDING the LITERAL source-string assertions in `CrankLeversAndPacking.t.sol`
  (`_countOccurrences(game_, "function autoResolve(")` at :277/:290/:415 and
  `"function _autoResolveBet("` at :381) which must flip to `"function degeneretteResolve("` /
  `"function _degeneretteResolveBet("`. **NO `doWork` smoke test at 330.**
- **D-02a (behavioral proofs deferred to Phase 332):** ALL behavioral test proofs are written at the
  dedicated TST phase — TST-01 freeze fuzz (the `totalFlipReversals` class), TST-02 one-category /
  double-pay reentrancy regression (the D-01b empirical no-guard backstop), TST-03 advance-routing /
  GASOPT same-results, TST-04, TST-05 the `degeneretteResolve` rename + flat-not-per-item / ≥3-gate /
  revert-on-no-work / WWXRP-excluded / same-results. This mirrors the v48 Phase 326 IMPL → 327 TST
  split exactly (IMPL keeps the suite green; TST writes the new proofs against the calibrated
  constants).

### Claude's Discretion (precedent-locked / grep-resolved — NOT user decisions)
- **Verification / green bar before hand-review:** local compile + forge **net-zero regression** vs
  the v48 baseline (last-known 632/42) + Hardhat parity (last-known 21/0). "Net-zero" = equal
  pass-count *after* the mandatory D-02 rename-fixes (the rename CHANGES test source, so it is
  parity-after-rename, not a byte-identical test tree). The CrankLeversAndPacking literal-string
  assertions must re-green to the new function names. Established v46/v48 precedent — no user
  question needed.
- **Plan / wave decomposition:** the SPEC mandates ONE atomic batched commit in producer-before-
  consumer order; worktrees are EXCLUDED for contract-touching plans
  (`no_worktree_paths: ["contracts"]`, [[worktrees-reenabled-contracts-gate]]). So the contract edits
  run SEQUENTIALLY in main — there is NO cross-file parallelism (the edits share files + a strict
  apply-order, and an intermediate where the advance bounty is deleted but the router has not
  re-homed it must never SHIP). The planner MAY split into per-work-area PLAN.md files, but they all
  funnel into the single HELD commit. MintModule GASOPT-01 + the D-02 test-rename-fixes can be
  authored alongside.
- **Exact ABI/encoding mechanics:** the `:275` wrapper success-branch `abi.decode(data, (uint8,
  bool))`; the `rewardable`-flag mapping over the 3 deleted `creditFlip` sites; the `EmptyAutoBuy`
  removal/repurpose; the `delegatecall` return-encoding from AdvanceModule — all resolved in
  329-SPEC §1/§2. Re-grep line anchors at edit time.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The locked design (READ FIRST — the binding input to this phase)
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md` —
  the 4 invariants + R1–R4 shared signatures + ROUTER-07/GAS-03/D-05/D-06 dispositions + §3 per-item
  IMPL blueprint + the producer-before-consumer edit-order map. **The MUST-read for IMPL.**
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-CONTEXT.md` —
  the decision provenance D-01..D-06g (router reentrancy, no-work signal, single epoch, fallback
  caller, `degeneretteResolve` rename/re-peg, the `maxCount==0` default).
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md`
  + `.../329-ATTEST-DEGENERETTE-RESOLVE.md` — the per-anchor grep tables (34 router/advance anchors +
  the D-05 surface) the IMPL re-anchors against.

### Scope + requirements + roadmap
- `.planning/REQUIREMENTS.md` — the 13 phase-330 owners (ROUTER-01..06, ADV-01/02/03/05,
  GASOPT-01/02, BATCH-02) + the Traceability table + the Out-of-Scope list.
- `.planning/ROADMAP.md` — Phase 330 goal + downstream Phases 331/332/333; the BATCH-02 contract-
  commit HARD STOP + the placeholder-calibrated-at-GAS rule.
- `.planning/PROJECT.md` — "Current Milestone: v49.0" (work items, locked design, shared-surface map,
  key constraints).

### v48 precedent (the established IMPL shape to mirror)
- `.planning/milestones/v48.0-phases/326-*/326-*.md` — the ONE batched USER-APPROVED diff `f50cc634`,
  producer-before-consumer, held for hand-review (the structural template for this phase).

### Audit baseline (the frozen HEAD any re-attest greps against)
- v48.0-closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (`0cc5d10f`);
  the live `contracts/` tree is byte-identical to baseline.

### Source (read from `contracts/` ONLY — stale copies elsewhere must be ignored, [[feedback_contract_locations]])
- `contracts/AfKing.sol` — the `doWork` router home; CEI invariant `:99-106`/`:100-101`, autoBuy
  stall ladder `:823-838` + `creditFlip` `:846`, cursor `:577`, `EmptyAutoBuy` `:143`/`:569`,
  `NoSubscribersAutoBought` `:146`, the GASOPT-02 `claimableWinningsOf` reads `:691`/`:722`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame()` `:155`, the 3 caller-reward
  `creditFlip` sites `:189`/`:225`/`:468` (the SDGNRS merge `:876` STAYS), the multiplier band
  `:243-254`, `totalFlipReversals` nudge `:1838`/reset `:1844` in `_applyDailyRng` `:1834`, the
  30-min bypass `:1012`, the death-clock `:109`/`:1200`.
- `contracts/DegenerusGame.sol` — the `advanceGame` wrapper `:275`, the gas-peg constants
  `:1539-1546`, `currentDayView` `:462`, `boxCursor` `:1551` / `boxPlayers` `:1562` /
  `lootboxRngWordByIndex` open-gate `:1647` / `autoOpen` loop `:1656` + bounty `:1676`, the
  `autoResolve` `:1587` / `_autoResolveBet` `:1684` / self-call `:1606` / per-item peg `:1611-1614` /
  post-loop creditFlip `:1622`, the KEEP-04 affiliate wiring `:1781`.
- `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol` — the
  new view signatures + the updated `advanceGame` tuple land here (NO `degeneretteResolve` row, C6).
- `contracts/modules/DegenerusGameMintModule.sol` — GASOPT-01 targets: `processFutureTicketBatch`
  `:393`/`rk` set `:398`; `processTicketBatch` `:670`/`rk` set `:671`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — read-only for D-05 (`delete` `:634`
  UNCHANGED); the 8 `degeneretteBets` consumers proving D-05f INERT-SAFE.
- `contracts/DegenerusVault.sol` (`gameAdvance` → `advanceGame()` `:527-528`) +
  `contracts/StakedDegenerusStonk.sol` (`gameAdvance` → `advanceGame()` `:421-422`) — invariant-(c)
  fallback wrappers (read-only — confirm, do NOT modify).
- `contracts/ContractAddresses.sol` — freely modifiable ([[feedback_contractaddresses_policy.md]]),
  but not expected to change at IMPL.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **AfKing anti-spam reverts** (`EmptyAutoBuy` `:143`, `NoSubscribersAutoBought` `:146`): the
  precedent idiom for ROUTER-06's new `NoWork()` revert (D-02/329).
- **AfKing autoBuy stall ladder** (`:823-838`, the 1/2/4/6 escalation): mirrors the advance leg's
  re-homed bounty SHAPE — but the advance multiplier comes from `advanceGame()`'s RETURN (design-1),
  NOT a copy of this block.
- **The existing `autoResolve` per-item loop** (`:1587-1622`): the flat re-peg is a localized
  arithmetic + boundary swap on it (per-item currency decode + WWXRP fork + try/catch + single
  post-loop `creditFlip` all already exist).
- **The v48 326 batched-diff workflow**: the established "author the full diff, compile/test locally,
  HOLD for one hand-review approval, then one commit" pattern.

### Established Patterns
- **AfKing CEI-everywhere, no-guard, keeper-never-a-payee** (`:99-106`): D-01 preserves it — all
  state effects before external calls, `creditFlip` LAST in each leg.
- **Pull-pattern winnings (`claimableWinnings`)**: the reason there is no untrusted ETH send in the
  `doWork` composition (the ROUTER-07 no-guard basis).
- **One gas-pegged `creditFlip` per tx, never per-item** (`:840-846`): the faucet bound the
  one-category early-return (invariant a) preserves.
- **Placeholder-then-recalibrate-at-GAS** (the v46 Phase 319 CR-01 "peg to the marginal, never a
  single total" discipline): the precedent for D-01's deferred-constant strategy.

### Integration Points
- `doWork(maxCount)` (NEW, `AfKing.sol`) → `IGame.advanceGame()` (returns `(mult, rewardable)`) /
  `IGame.autoOpen(maxCount)` / internal `_autoBuy(maxCount)` → ONE `creditFlip` for the re-homed
  advance bounty (open/buy legs keep their own in-callee bounty).
- `DegenerusGame.advanceGame` wrapper (`:275`) decodes + forwards the new delegatecall tuple — the
  PRODUCER the interfaces + the AfKing router consume.

</code_context>

<specifics>
## Specific Ideas

- This phase is the direct structural analog of v48's Phase 326 — author the ONE batched
  USER-APPROVED `contracts/*.sol` diff, compile + test locally, then HARD STOP at the commit
  boundary for explicit hand-review. Never commit `contracts/*.sol` without it
  ([[feedback_batch_contract_approval]], [[feedback_never_preapprove_contracts]],
  [[feedback_manual_review_before_push]], [[feedback_no_contract_commits]]).
- **Commit-ordering hazard** ([[feedback_contract_commit_guard_hook]]): a PreToolUse hook blocks ALL
  commits while `contracts/*.sol` is dirty. Commit every planning doc (CONTEXT / PLAN / etc.) BEFORE
  touching `.sol`; `.planning/` is gitignored → force-add. Defer the diff commit until after the
  approved batched contract commit.
- Auto-advance is HELD at the SPEC→IMPL contract boundary ([[feedback_pause_at_contract_phase_boundaries]]) —
  the user explicitly triggered `/gsd-discuss-phase 330`, satisfying that gate.
- Placeholder constants land as best-guess realistic estimates with a greppable flagged-marker block;
  comments describe what IS, not history ([[feedback_no_history_in_comments]]).

</specifics>

<deferred>
## Deferred Ideas

- **`degeneretteResolve` folded INTO the on-chain router** — architecturally blocked
  (`degeneretteBets` is a nested mapping with no O(1) enumeration; on-chain discovery is impossible
  or unbounded). The unified "one button" is a FRONTEND concern (the keeper UI indexes the arrays
  from events). Only the rename + flat re-peg are in scope here (GAS-06/TST-05). (Carried from
  329-CONTEXT.)
- **A failing-placeholder tripwire test** (the option-3 alternative to D-01) — considered and NOT
  chosen; the user preferred best-guess + a flagged marker, with the recalibration guarantee resting
  procedurally on Phase 331's GAS scope. Recorded so 331 knows there is no code tripwire enforcing it.
- Other milestone-level out-of-scope items (the `Sub` memory-snapshot gas opt, `batchPurchase`
  try/catch bypass, `1 ether - decayN` unchecked, SWAP cash-share tighten, standing profit-margin
  bounty, external keeper networks) are in `.planning/REQUIREMENTS.md` § Out of Scope — no re-capture.

</deferred>

---

*Phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic*
*Context gathered: 2026-05-26*
