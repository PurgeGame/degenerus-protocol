# Requirements: Degenerus Protocol — Backfill Idempotency + purchaseLevel Underflow Audit (v32.0)

**Defined:** 2026-04-30
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

**Goal:** Prove the two testnet bugs in `DegenerusGameAdvanceModule.sol` are correctly fixed by the WIP guards (backfill double-execution → underflow; turbo-vs-rngLockedFlag race → `purchaseLevel = 0` panic 0x11), and sweep AdvanceModule + delegating modules for sibling-pattern races between `rngLockedFlag` / `lastPurchaseDay` / `jackpotPhaseFlag` / `dailyIdx` that could produce other underflows, double-execution, or skipped updates.

**Audit baseline:** v31.0 HEAD `cc68bfc7` → current HEAD `48554f8f` + WIP working-tree changes (`contracts/ContractAddresses.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, new `test/edge/LastPurchaseDayRace.test.js`).

**Trigger context (testnet panic 0x11 reproduced at blocks 10759449 + 10761786):**

- **Backfill double-execution:** `dailyIdx` is only updated by `_unlockRng`. During multi-day VRF stalls, `rngGate`'s fresh-word path can re-enter the backfill branch on each new wall-clock day before `_unlockRng` fires, re-processing the same gap range — doubling `purchaseStartDay`, re-running coinflip payouts for already-resolved days, and ultimately underflowing.
- **`purchaseLevel = 0` race:** Turbo block at AdvanceModule:167 fires while `rngLockedFlag = true`. The `rngGate` fresh-word path runs instead of `_requestRng`, so the level pre-increment is missed. Then the ternary at AdvanceModule:185 computes `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` → returns `lvl = 0` → `purchaseLevel = 0` → panic 0x11 at `levelPrizePool[uint24(0) - 1]`.

**Post-v31.0 commits in scope (already landed; included for delta sanity-check):**

1. `8bdeabc2` — fix(liveness): pause death clock during productive multi-call window (`DegenerusGameAdvanceModule.sol`)
2. `ad41973c` — test(liveness): cover productive-phase pause regression (`test/edge/LivenessProductivePause.test.js`)
3. `6a63705b` — fix(mint): charge buyer not operator for purchaseCoin tickets (`DegenerusGameMintModule.sol`)
4. `48554f8f` — refactor(vault): decouple share redemption from game operator approval (`DegenerusVault.sol`, `DegenerusGameStorage.sol`, vault tests + fuzz)

**WIP work-tree changes in scope (proposed fixes, audit target):**

- `contracts/modules/DegenerusGameAdvanceModule.sol` — `!rngLockedFlag` turbo guard at L167; `rngWordByDay[idx + 1] == 0` backfill idempotency guard at L1167
- `test/edge/LastPurchaseDayRace.test.js` — new reproduction test (untracked)
- `contracts/ContractAddresses.sol` — deploy address regeneration only (no logic delta)

**Write policy:** READ-only LIFTED for v32.0 (was held continuously v28.0–v31.0). Audit-then-commit. WIP turbo guard, backfill guard, and reproduction test land via explicit per-commit user approval per `feedback_no_contract_commits.md`. Any new contract or test changes surfaced by the sibling-pattern sweep also require explicit approval.

**Deliverable:** `audit/FINDINGS-v32.0.md` — executive summary, per-phase sections, F-32-NN finding blocks, lean regression appendix, fix-readiness signal for committable changes.

**Accepted RNG exceptions** (RE_VERIFIED non-widening at HEAD; no acceptance re-litigation):

1. EXC-01 — Non-VRF entropy for affiliate winner roll (KNOWN-ISSUES.md). Affiliate roll path NOT delta-touched.
2. EXC-02 — Gameover prevrandao fallback (`_getHistoricalRngFallback`; KNOWN-ISSUES.md). RE_VERIFY only if delta widens envelope.
3. EXC-03 — Gameover RNG substitution for mid-cycle write-buffer tickets / F-29-04 class (KNOWN-ISSUES.md). RE_VERIFY against backfill-guard interaction.
4. EXC-04 — EntropyLib XOR-shift PRNG (KNOWN-ISSUES.md). LootboxModule entropyStep call sites NOT delta-touched.

---

## v32.0 Requirements

### DELTA — Delta Extraction & Classification (3 REQs)

- [x] **DELTA-01**: Enumerate every function / state variable / event changed across the post-v31.0 surface (4 landed commits + WIP guards) with per-source and aggregate counts. Reproducible with `git diff cc68bfc7..HEAD` plus working-tree diff. — COMPLETE in Phase 247 Plan 247-01 (audit/v32-247-DELTA-SURFACE.md §1 + §4 + §5; 16 D-247-C### rows + 1 D-247-S### storage-layout UNCHANGED row).
- [x] **DELTA-02**: Classify each changed function as {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} with hunk-level evidence. — COMPLETE in Phase 247 Plan 247-01 (audit/v32-247-DELTA-SURFACE.md §2; 11 D-247-F### rows: 8 MODIFIED_LOGIC + 3 DELETED + 0 NEW/REFACTOR_ONLY/RENAMED; D-247-07 pre-locked floors honored zero deviations).
- [x] **DELTA-03**: Identify every downstream call site of each changed function and interface across `contracts/` (grep-reproducible inventory). — COMPLETE in Phase 247 Plan 247-01 (audit/v32-247-DELTA-SURFACE.md §3; 30 D-247-X### rows; D-247-19 grep-reproducibility mandate honored).

### BFL — Backfill Idempotency Proof (6 REQs)

- [x] **BFL-01**: Enumerate every code path that reaches `_backfillGapDays` (sole call site at AdvanceModule:1176 inside `rngGate` fresh-word branch). Prove the new `rngWordByDay[idx + 1] == 0` guard makes the call idempotent across every reachable `advanceGame` re-entry within a single VRF lock window. — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §1; 7 BFL-01-VNN rows + 3 BFL-01-MNN multiplier rows; commit b79f3eac).
- [x] **BFL-02**: Enumerate all state writes inside `_backfillGapDays` (`purchaseStartDay`, coinflip pool credits, `rngWordByDay[d]`, daily ticket processing side effects). For each write, prove the guard correctly skips repeated execution and that the `rngWordByDay[idx + 1]` chosen index is the correct sentinel (no off-by-one vs `idx` or `day`). — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §2; D-248-09 broadens scope to WHOLE guarded block L1174-1186; 6 BFL-02-VNN rows + 5 out-of-scope BFL-02-XNN rows + sentinel-correctness 4-step proof; commit b79f3eac).
- [x] **BFL-03**: Multi-day VRF stall scenario — adversarially construct the testnet underflow sequence (lock window crosses ≥2 wall-clock days; fresh-word path re-enters before `_unlockRng`). Prove the underflow is impossible with the guard, and produce a worked numeric example. — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §3; testnet blocks 10759449 + 10761786 seeded; 15 BFL-03-VNN rows split §3.1 pre-fix walk + §3.2 post-fix walk; commit 838631a8).
- [x] **BFL-04**: `dailyIdx` ↔ `rngWordByDay[idx]` ↔ `_unlockRng` invariant — prove `dailyIdx` only advances inside `_unlockRng` AND that `rngWordByDay[idx + 1]` correctly identifies "backfill not yet run for this lock window." — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §4; grep-cited universe attestation per D-248-15; 4 BFL-04-VNN rows including DegenerusGame.sol:219 constructor write recorded for completeness; AdvanceModule:1703 confirmed runtime sole writer; commit 838631a8).
- [x] **BFL-05**: RE_VERIFY EXC-02 (prevrandao fallback) and EXC-03 (gameover RNG substitution) envelopes against the backfill guard. The guard MUST NOT widen either envelope; if it does, either narrow the guard or update KNOWN-ISSUES.md per D-09 gating. — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §5; 2 BFL-05-VNN dual-carrier attestation rows per D-248-13; both verdicts NON-WIDENING; KNOWN-ISSUES.md UNCHANGED per D-248-04; commit 3be95bfe).
- [x] **BFL-06**: Conservation proof — total ETH credited to coinflip pools across the gap range equals expected non-doubled amount; `purchaseStartDay` increments exactly once per gap day; sDGNRS / DGNRS / BURNIE supplies invariant across the lock window. — COMPLETE in Phase 248 Plan 248-01 (audit/v32-248-BFL.md §6; conservation algebra block + 10 BFL-06-VNN per-mutation rows; D-248-10 boundary cite for BurnieCoinflip.sol::processCoinflipPayouts; sDGNRS / DGNRS / BURNIE supply invariance verified via grep — 0 _mint/_burn hits in guarded block; commit 5545b125).

### PLV — purchaseLevel Correctness Proof (6 REQs)

- [x] **PLV-01**: Enumerate every read site of `purchaseLevel` in AdvanceModule (~30+ readsites grep-confirmed) and in any module that delegates into AdvanceModule. Tag each readsite with the local invariant it requires (`≥1`, `> level`, `level + 1`, etc.).
- [x] **PLV-02**: 4-dimensional state-space sweep across `(lastPurchaseDay ∈ {false, true}) × (rngLockedFlag ∈ {false, true}) × (jackpotPhaseFlag ∈ {false, true}) × (level ∈ {0, 1, 2, …, levelMax})` enumerating every reachable combination. For each, prove `purchaseLevel` evaluates to a well-defined value `≥ 1` at the line where it is bound (AdvanceModule:185).
- [x] **PLV-03**: Specifically prove the ternary `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` cannot return 0 once the new `!rngLockedFlag` turbo guard at L167 is in place. Show the unreachable state is `(lastPurchase = true ∧ rngLockedFlag = true ∧ lvl = 0)` and prove turbo no longer fires there.
- [x] **PLV-04**: Underflow audit — every callsite that performs arithmetic on `purchaseLevel` (notably `purchaseLevel - 1` at AdvanceModule:748 `levelPrizePool[uint24(0) - 1]`, plus `+1`, `+4`, `_tqReadKey(purchaseLevel)`, etc.) is checked for underflow / overflow / out-of-bounds at every reachable purchaseLevel value.
- [x] **PLV-05**: Verify the `!rngLockedFlag` turbo guard prevents the testnet panic 0x11 at blocks 10759449 + 10761786 — reproduce the trigger sequence symbolically and show the guard short-circuits it before the ternary executes.
- [x] **PLV-06**: After the turbo guard, prove the daily-jackpot path (lines 372–404 region) correctly handles target-met detection and unlocks within the same call — i.e. the guard does not strand state in a "target met but never resolves" condition.

### SIB — Sibling-Pattern Sweep (5 REQs)

- [x] **SIB-01**: Enumerate every other location in `DegenerusGameAdvanceModule.sol` where `rngLockedFlag` interacts with another piece of game state (`lastPurchaseDay`, `jackpotPhaseFlag`, `dailyIdx`, `level`, `purchaseStartDay`, `rngWordByDay[*]`, `phaseTransitionActive`, etc.).
- [x] **SIB-02**: For each interaction, classify whether it has the same race shape as the two known bugs: (a) "turbo-class" — control flow takes one branch under one flag combination but a sibling branch unexpectedly fires under another; (b) "backfill-class" — write executes idempotently expected once, but actually re-enters because index advance is gated on a different signal.
- [x] **SIB-03**: Audit modules that delegate into AdvanceModule (`DegenerusGameMintModule`, `DegenerusGameJackpotModule`, `DegenerusGameWhaleModule`, `DegenerusGameLootboxModule`, `DegenerusGameDegenetteModule`, `DegenerusGameBoonModule`, `DegenerusGameDecimatorModule`, `DegenerusGameGameOverModule`) for the same patterns reading the same state.
- [x] **SIB-04**: Cross-check the 4 post-v31.0 landed commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) for the same patterns — particularly `8bdeabc2` (liveness pause during productive multi-call window) which is conceptually adjacent.
- [x] **SIB-05**: Document any new sibling bugs found with reproducible trigger sequences and proposed fixes. Each new bug requires its own F-32-NN finding block, severity classification, and explicit user approval before any contract edit lands.

### TST — Reproduction Tests (4 REQs)

- [x] **TST-01**: Verify `test/edge/LastPurchaseDayRace.test.js` (untracked, in WIP) triggers panic 0x11 reliably WITHOUT the `!rngLockedFlag` turbo guard — confirm the test fails on the pre-fix code.
- [x] **TST-02**: Verify `test/edge/LastPurchaseDayRace.test.js` PASSES on the post-fix code with both WIP guards applied.
- [x] **TST-03**: Verify `test/edge/LivenessProductivePause.test.js` and `test/edge/LivenessMidJackpot.test.js` (committed in `8bdeabc2` / `ad41973c`) still pass against the WIP guards — no regression from the new turbo / backfill guards.
- [x] **TST-04**: Add a reproduction test for the backfill double-execution underflow if `LastPurchaseDayRace.test.js` does not already cover it. The test must fail on pre-fix code (no backfill guard) and pass on post-fix code.

### POST31 — Post-v31.0 Landed-Commit Sanity (2 REQs)

- [ ] **POST31-01**: Delta-sanity verify the 4 landed post-v31.0 commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) do not widen the bug envelopes being fixed — i.e. the liveness pause, vault redemption refactor, and mint buyer-charge fix do not introduce new turbo-class or backfill-class races.
- [ ] **POST31-02**: RE_VERIFY the productive-phase liveness pause behavior (`8bdeabc2`) against the new `!rngLockedFlag` turbo guard — confirm both fixes compose correctly and there is no interaction where the death clock fails to pause OR resumes prematurely.

### FIND — Findings Consolidation (4 REQs)

- [ ] **FIND-01**: Publish `audit/FINDINGS-v32.0.md` with executive summary, per-phase sections, F-32-NN finding blocks (v29/v30/v31 shape preserved), lean regression appendix, and HEAD anchor.
- [ ] **FIND-02**: Every finding classified under the D-08 5-bucket severity rubric (CRITICAL / HIGH / MEDIUM / LOW / INFO).
- [ ] **FIND-03**: `KNOWN-ISSUES.md` updated if D-09 3-predicate gating passes (accepted-design + non-exploitable + sticky); otherwise UNMODIFIED with Non-Promotion Ledger documenting the gating decision.
- [ ] **FIND-04**: Emit fix-readiness signal `MILESTONE_V32_AT_HEAD_<sha>` once the WIP guards + reproduction tests are committed and tests pass. The deliverable's commit-readiness section names every contract / test path landed during the milestone with its review-and-approval audit trail.

### REG — Lean Regression Appendix (2 REQs)

- [ ] **REG-01**: Spot-check regression — re-verify any prior finding (v29 / v30 / v31) directly touched by the WIP fixes or the post-v31 commits. Specifically: any F-3X-NN entry that referenced `_backfillGapDays`, `purchaseLevel`, `rngLockedFlag`, `lastPurchaseDay`, `dailyIdx`, or the turbo block. Verdicts: PASS / REGRESSED / SUPERSEDED.
- [ ] **REG-02**: Document any prior finding superseded by the WIP fixes (e.g. an earlier F-NN-NN that flagged a related pattern and is now structurally closed by the new guards).

---

## Traceability

| REQ-ID | Target Phase | Status |
|--------|--------------|--------|
| DELTA-01 | Phase 247 | COMPLETE (Plan 247-01 / commit e2cacc5c — §1 + §4 + §5 of audit/v32-247-DELTA-SURFACE.md) |
| DELTA-02 | Phase 247 | COMPLETE (Plan 247-01 / commit 8e7e1f7c — §2 of audit/v32-247-DELTA-SURFACE.md; D-247-07 floors honored) |
| DELTA-03 | Phase 247 | COMPLETE (Plan 247-01 / commit 4cc1f829 — §3 of audit/v32-247-DELTA-SURFACE.md; D-247-19 grep-reproducibility honored) |
| BFL-01 | Phase 248 | COMPLETE (Plan 248-01 / commit b79f3eac — §1 of audit/v32-248-BFL.md; 7 V-rows + 3 multiplier rows) |
| BFL-02 | Phase 248 | COMPLETE (Plan 248-01 / commit b79f3eac — §2 of audit/v32-248-BFL.md; 6 V-rows; sentinel-index correctness verified) |
| BFL-03 | Phase 248 | COMPLETE (Plan 248-01 / commit 838631a8 — §3 of audit/v32-248-BFL.md; 15 V-rows; testnet blocks 10759449 + 10761786 seeded) |
| BFL-04 | Phase 248 | COMPLETE (Plan 248-01 / commit 838631a8 — §4 of audit/v32-248-BFL.md; 4 V-rows; D-248-15 grep-reproducibility honored) |
| BFL-05 | Phase 248 | COMPLETE (Plan 248-01 / commit 3be95bfe — §5 of audit/v32-248-BFL.md; 2 V-rows NON-WIDENING; KI UNCHANGED) |
| BFL-06 | Phase 248 | COMPLETE (Plan 248-01 / commit 5545b125 — §6 of audit/v32-248-BFL.md; 10 V-rows; conservation algebra closes) |
| PLV-01 | Phase 249 | Complete |
| PLV-02 | Phase 249 | Complete |
| PLV-03 | Phase 249 | Complete |
| PLV-04 | Phase 249 | Complete |
| PLV-05 | Phase 249 | Complete |
| PLV-06 | Phase 249 | Complete |
| SIB-01 | Phase 250 | Complete |
| SIB-02 | Phase 250 | Complete |
| SIB-03 | Phase 250 | Complete |
| SIB-04 | Phase 250 | Complete |
| SIB-05 | Phase 250 | Complete |
| TST-01 | Phase 251 | COMPLETE (Plan 251-01 / commit c73c8add — §1 of audit/v32-251-TST.md; 2 V-rows SAFE; pre-fix panic 0x11 reproduced) |
| TST-02 | Phase 251 | COMPLETE (Plan 251-01 / commit 6bc9c525 — §2 of audit/v32-251-TST.md; 2 V-rows SAFE; PLV-03 empirical confirmation) |
| TST-03 | Phase 251 | COMPLETE (Plan 251-01 / commit 6bc9c525 — §3 of audit/v32-251-TST.md; 2 V-rows SAFE; SIB-04-V01 carrier integrity) |
| TST-04 | Phase 251 | COMPLETE (Plan 251-01 / commit 33e7d7c5 — §4 of audit/v32-251-TST.md; 2 V-rows SAFE; BFL §7.1 + BFL-03 empirical confirmation) |
| POST31-01 | Phase 252 | Pending |
| POST31-02 | Phase 252 | Pending |
| FIND-01 | Phase 253 | Pending |
| FIND-02 | Phase 253 | Pending |
| FIND-03 | Phase 253 | Pending |
| FIND-04 | Phase 253 | Pending |
| REG-01 | Phase 253 | Pending |
| REG-02 | Phase 253 | Pending |

(Phase numbering FINAL — set by v32.0 roadmap 2026-04-30.)

---

## Out of Scope

- **Non-AdvanceModule subsystems unrelated to the two bugs** — full audit of vault, jackpot, lootbox, degenerette, boon, charity, governance, etc. is NOT in scope. Only POST31-01 sanity-check the 4 landed commits and SIB-03 cross-module sweep for the specific patterns.
- **ETH / BURNIE / sDGNRS / DGNRS conservation on non-delta surfaces** — covered in v25.0/v29.0/v30.0/v31.0; not re-proven globally. BFL-06 conservation proof is scoped to the lock window only.
- **Indexer / database / sim / frontend** — covered in v28.0; NOT in scope.
- **Re-litigating the 4 accepted KNOWN-ISSUES RNG exceptions** — acceptance NOT re-litigated; envelope re-verify only (BFL-05).
- **Storage layout audit on non-delta contracts** — only delta-affected layouts checked.
- **Gas optimization** — not in scope; bug fixes prioritized over gas.
- **Full v31.0-style 33-row regression sweep** — replaced by REG-01 LEAN spot-check (only prior findings touched by deltas).

## Future Requirements (rolled forward to v33.0+)

- TBD at milestone close.
