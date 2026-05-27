# Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression - Context

**Gathered:** 2026-05-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the v49 unified keeper-router composition behaviorally correct **empirically**, and
restore a clean **NON-WIDENING** v49 regression baseline against the GAS-calibrated constants
(landed Phase 331). Five proofs (TST-01..05):

1. **TST-01** — freeze-invariant fuzz (extends the v43 `RngLockDeterminism` harness): the router
   advance-consume reads only frozen state mid-tx (the `totalFlipReversals` class), even when fired
   in the same tx as `autoBuy`/`autoOpen`; ADDS autoBuy-during-rngLock SAFE, autoOpen-blocked +
   no-marooned-boxes, unified one-category / no-double-pay.
2. **TST-02** — one-category / no-bounty-stacking + the router→game→`creditFlip` double-pay
   disposition; plus the parameterless-`doWork()` default-batch / remainder behavior + standalone
   UNREWARDED `autoBuy(count)`/`autoOpen(count)` escapes.
3. **TST-03** — `advanceGame` UNREWARDED standalone vs REWARDED via `doWork` (multiplier honored,
   mid-day partial-drain leg rewarded) + the two GASOPT micro-opts same-results.
4. **TST-04** — full-suite NON-WIDENING regression vs the v48.0 baseline (`0cc5d10f`, 632/42).
5. **TST-05** — `degeneretteResolve` rename + re-peg: flat ~1 BURNIE/tx (not per-item), ≥3-gate,
   revert-on-no-work, WWXRP excluded from gate + reward, byte-identical RESULTS.

**Posture:** NO `contracts/*.sol` (mainnet) mutation — this is `test/` + `.planning/` work, and tests
are agent-committable (`feedback_no_contract_commits`). The audit subject is FROZEN at the committed
v49 source (`63bc16ca` + the 331 GAS constants). If a proof surfaces a contract defect, STOP and
surface it — do not patch a mainnet contract under a TST phase.

</domain>

<decisions>
## Implementation Decisions

### TST-02 — One-category / reentrancy disposition
- **D-01 (reentrancy is structural, no attacker harness):** `doWork` pays only minted FLIP CREDIT
  (`creditFlip`), makes **no ETH push**, and every external call targets a pinned
  `ContractAddresses.*` (GAME / COINFLIP). There is no untrusted call to re-enter through, so a
  synthetic reentrant attacker has no hook. TST-02's "router→game→`creditFlip` double-pay
  regression" (roadmap SC + 329 `D-01b`) is satisfied by a **STRUCTURAL ATTESTATION** — grep-proven:
  (a) no untrusted external call in any leg (`_autoBuy` / `advanceGame` / `autoOpen`), and (b) the
  single `creditFlip` site is **CEI-last after the one-category early-return** (`AfKing.sol:913-918`).
  **NO attacker harness is built.** *(User verbatim: "reentrancy is not an issue, nothing here pays
  eth and this only interacts with trusted contracts.")*
- **D-02 (no-stacking proven by counting `creditFlip` calls):** Assert **EXACTLY one**
  `COINFLIP.creditFlip` call per `doWork()` tx (via `vm.expectCall` / `vm.recordLogs`) across all
  three category branches (autoBuy / advance / autoOpen), **including the `bountyEarned==0` skip
  path** — a buy chunk that walked only already-bought subs runs the category but credits nothing
  (zero `creditFlip` calls, still no revert). This directly proves the `else-if` chain can never
  credit two categories in one tx. (NOT exact-amount assertions; NOT both.)
- **D-03 (rest of TST-02 = planner territory):** The parameterless-`doWork()` default-batch /
  remainder-for-next-call (no-OOG) proof per `D-07`, and the standalone parametered UNREWARDED
  `autoBuy(count)`/`autoOpen(count)` emergency escapes, are well-specified by the requirement text —
  left to the planner to construct.

### TST-04 — Deferred-red disposition + NON-WIDENING ledger
- **D-04 (delete + re-author fresh — NOT repair-in-place, NOT hybrid):** DELETE all **16
  reward-rehoming reds** and RE-AUTHOR the v49 invariants fresh in the new proof files. The
  no-double-buy invariant is **re-expressed in storage-oracle terms** (`lastAutoBoughtDay` storage /
  pool-balance-delta per GASOPT-04) — **SAFE-03 / H-CANCEL-SWAP MUST be PRESERVED, not weakened**
  (TST-04 hard constraint). The retired per-item *summed*-reward premise is replaced by the
  flat-per-tx one-credit-per-tx proof (`D-02`).
- **D-05 (ledger arithmetic):** After deleting the 16 (all red at 330's 616/58), failing returns to
  **EXACTLY the 42 v48.0-baseline reds** — net-zero new regression, the binding headline. Passing
  baseline after deletion = 616, then `+N` fresh green proofs. The 42-red union (enumerated by name
  in `REGRESSION-BASELINE-v48.md §2`) carries forward **UNCHANGED**; any forge red NOT in that union
  is a NEW regression → STOP. The 16 deletions are recorded with a per-test re-homing justification
  (superseded by the `doWork` bounty unification).
- **D-06 (author `test/REGRESSION-BASELINE-v49.md`):** Mirror `test/REGRESSION-BASELINE-v48.md` —
  record (a) the 42-red carried-forward union by name, (b) the 16 deletions with re-homing
  justification, (c) the new green proof files, (d) the `Crank*`→keeper-* file renames (so the
  file-path churn is attributable; NON-WIDENING is about the red-set / behavior, not file names).
- **D-07 (de-crank the test tree):** Rename the 5 surviving `Crank*`-named files to keeper-* names
  + their internal contract/symbol names — pure rename (`git mv` + reference update), **zero
  behavioral change**, recorded in the v49 ledger. Files: `test/fuzz/CrankFaucetResistance.t.sol`,
  `test/fuzz/CrankNonBrick.t.sol`, `test/gas/CrankLeversAndPacking.t.sol`,
  `test/gas/CrankOpenBoxWorstCaseGas.t.sol`, `test/gas/CrankResolveBetWorstCaseGas.t.sol`. (Matches
  the v48 contract rename that purged "crank" + the user's stated dislike of "crank".)

### Claude's Discretion
- **Proof-file homes (TST-02/03/05):** planner picks closest-analog homes per the pattern-mapper —
  some new files, some extensions (TST-01 extends `RngLockDeterminism.t.sol`, which is locked by the
  roadmap). *(User: "you decide.")*
- **Freeze-fuzz depth (TST-01):** routine suite under the **default** foundry profile (fuzz runs
  1000 / invariant 256×128); gate the **deep** freeze proof under `FOUNDRY_PROFILE=deep` (fuzz 10000
  / invariant 1000×256) — the v44 INV precedent. Add a dedicated stateful invariant handler for the
  same-tx-with-`autoBuy`/`autoOpen` perturbation if the extension needs one. *(User delegated "the
  rest I'll resolve by precedent.")*
- **Same-results methodology (TST-03 GASOPT + TST-05 byte-identical):** the GASOPT micro-opts
  (MintModule pointer + AfKing claimable-hoist) are gas-only and touch no RNG/result → prove via
  **Foundry behavioral-equality**. `degeneretteResolve` byte-identical RESULTS → prove via **Foundry
  RESULTS-equality** (BURNIE/WWXRP mints, claimable/pool deltas, RNG draws identical vs the
  pre-rename per-item logic) **plus** the existing Hardhat Degenerette stat tests
  (`DegeneretteProducerChi2` / `DegeneretteBonusEv` / `DegenerettePerNEvExactness`) stay green
  (chi²/EV-exactness unchanged). Mirrors the v48 Phase 327 same-results approach.
- **Hardhat parity:** keep the Hardhat side green at its v48 last-known parity (precedent-locked); the
  Foundry NON-WIDENING ledger is the authoritative regression gate.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope + requirements + roadmap
- `.planning/ROADMAP.md` — Phase 332 goal + the 5 Success Criteria (the proof bar) + the v49 posture.
- `.planning/REQUIREMENTS.md` — TST-01..05 exact wording (incl. the redesign Q4 additions on TST-01
  and the GASOPT-04 oracle migration on TST-04).

### The regression baseline (the ledger to mirror + the 42-red union)
- `test/REGRESSION-BASELINE-v48.md` — the AUTHORITATIVE 42-red enumeration (§2, three named buckets)
  + the net-zero-new-regression arithmetic + the ledger shape `REGRESSION-BASELINE-v49.md` mirrors.

### Prior-phase context (the binding design + deferral scope)
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-CONTEXT.md`
  — `<decisions>` lines 245-248 (TST-01 / TST-04 guidance); `D-01`/`D-01a`/`D-01b` reentrancy
  disposition (lines 122-133); the `AutoBought`-keyed test list (lines 302-304).
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-CONTEXT.md`
  — `D-02a` (behavioral proofs deferred to 332, lines 141-147).
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-08-SUMMARY.md`
  + `330-VERIFICATION.md` — the 16 reward-rehoming reds (the two named examples + the 616/58 vs 632/42
  arithmetic).
- `.planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/331-CONTEXT.md`
  + the 331 SUMMARYs — the GAS-calibrated constants the tests exercise (`BUY_BATCH`/`OPEN_BATCH`/
  `OPEN_KNEE`/`RESOLVE_FLAT_BURNIE`/the advance+buy+open ratios) and `[[v49-phase331-rescope-keeper-buy-gas]]`.

### v48 precedent (the TST shape + same-results approach to mirror)
- `.planning/milestones/v48.0-phases/327-*/` — the SPEC→IMPL→TST split, the same-results / Degenerette
  byte-reproduce gate, and `327-06` (the full-suite regression-gate plan that produced the v48 ledger).

### Audit subject — source (read from `contracts/` ONLY; FROZEN at the committed v49 source)
- `contracts/AfKing.sol` — `doWork` (`:883-919`, the one-category `else-if` + single `creditFlip`
  CEI-last `:913-918`), `_autoBuy` (`:561`), the standalone `autoBuy(count)`/`autoOpen(count)`
  escapes (`:923/:929`), `BOUNTY_ETH_TARGET` + the ratio/knee constants.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame` `(uint8 mult)` return, the
  removed in-callee `creditFlip` sites, the mid-day `mult=1` partial-drain leg, the `totalFlipReversals`
  nudge, the death-clock backstop.
- `contracts/DegenerusGame.sol` — the `advanceGame` wrapper, `autoOpen`, `keeperSnapshot` (`:2628`,
  GASOPT-03), `degeneretteResolve` (D-05 rename + re-peg), `advanceDue()`/`boxesPending()` views.
- `test/fuzz/RngLockDeterminism.t.sol` — the v43 freeze-determinism harness TST-01 extends.
- `foundry.toml` — `[fuzz]`/`[invariant]` default vs `[profile.deep.*]` (the depth knobs).
- The 5 `Crank*` files (the de-crank rename targets; see `D-07`).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `test/fuzz/RngLockDeterminism.t.sol` — the v43 harness; TST-01 extends it (perturb every in-window
  SLOAD between rng-request and unlock, assert byte-identical consumed VRF output) under the new
  router composition.
- `test/fuzz/DegeneretteFreezeResolution.t.sol` + `test/fuzz/DegeneretteHeroScore.t.sol` + the Hardhat
  stat tests (`test/stat/Degenerette*.test.js`) — analogs for the TST-05 `degeneretteResolve`
  RESULTS-equality + chi²/EV-exactness proofs.
- `vm.expectCall` / `vm.recordLogs` on `COINFLIP.creditFlip` — the one-credit-per-tx counting oracle
  (D-02).
- `foundry.toml` `profile.deep` — the gated deep-fuzz lever for the TST-01 freeze proof.

### Established Patterns
- One-category `else-if` chain + a single `creditFlip` CEI-last (`AfKing.sol:883-919`) — the structure
  the no-stacking + structural-reentrancy proofs key on.
- `keeperSnapshot(address[])` view (GASOPT-03) — batch claimable/price/lock reads.
- Storage oracle `lastAutoBoughtDay` (GASOPT-04) — the no-double-buy observation mechanism that
  replaces the retired `AutoBought` event (the re-authored TST-04 tests assert against this, not the
  event).

### Integration Points
- All proofs drive `GAME` / `COINFLIP` / `AfKing` at the committed v49 source + the 331-calibrated
  constants; **zero `contracts/` edits** in this phase.
- The de-crank rename (`D-07`) touches test file paths + internal symbols only — the regression diff
  records the renames so file-path churn stays attributable.

</code_context>

<specifics>
## Specific Ideas

- User verbatim: **"reentrancy is not an issue, nothing here pays eth and this only interacts with
  trusted contracts."** → drives the structural-attestation disposition (D-01); no attacker harness.
- User dislikes "crank" → de-crank the test tree (D-07), completing the v48 contract-rename into
  `test/`.
- User chose the cleanest disposition (delete + re-author fresh) over repair-in-place and hybrid (D-04).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg*
*Context gathered: 2026-05-27*
