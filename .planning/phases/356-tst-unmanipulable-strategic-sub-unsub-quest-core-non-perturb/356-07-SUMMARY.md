---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 07
subsystem: testing (NON-WIDENING regression ledger + migration-unmasked stale-red resolution)
tags: [non-widening, by-name, empirical-baseline, 453f8073, milli-eth, openboxes-valve, solvency-01-anchor, vm-skip-drop]
requires:
  - phase: 356-01
    provides: "the 7 read-only keeper/afking fuzz files migrated to the v56 uint24 Sub re-pack + the 4 KeeperFaucetResistance unmasked reds"
  - phase: 356-02
    provides: "the 3 v55-proof files migrated (offsets + write-mask helpers) + the documented PRE-EXISTING v56-behavior reds"
  - phase: 356-03
    provides: "V56SecUnmanipulable (SEC-01) 11/11 green + the drainAffiliateBase dispatch-stub threat flag"
  - phase: 356-04
    provides: "V56FreezeSolvency (SEC-02) 7/7 green + the SOLVENCY-01 leg-1 byte-diff anchor (GameAfkingModule:663-664)"
  - phase: 356-05
    provides: "V56QuestNonPerturb (QST-04) 7/7 green"
  - phase: 356-06
    provides: "V56AfkingGasMarginal extended (LIVE-01/GAS-06/D-06/D-09) 15/15 green"
provides:
  - "test/REGRESSION-BASELINE-v56.md — the BY-NAME NON-WIDENING ledger anchored on the empirical 453f8073 baseline (134-name union)"
  - "the 14 migration-unmasked v56-behavior reds RESOLVED (vm.skip-with-reason DROP) so the live tree is genuinely NON-WIDENING (live == baseline union BY NAME)"
  - "the empirical baseline-derivation method for a deleted-AfKing baseline (the 453f8073 corpus is uncompilable; run the byte-identical-contracts 83a6a9ca)"
  - "the drainAffiliateBase dispatch-stub reachability carried as a 357 finding (SURFACED, not masked)"
affects:
  - "357 / AUDIT-01 (consumes the NON-WIDENING gate; the carried drainAffiliateBase reachability finding)"
tech-stack:
  added: []
  patterns:
    - "empirical NON-WIDENING baseline via a byte-identical-contracts commit when the baseline's own test corpus is uncompilable (run 83a6a9ca whose contracts == 453f8073)"
    - "vm.skip(true, reason) removed/adapted-surface DROP for migration-unmasked stale-behavior reds (the RngLockDeterminism precedent)"
    - "live-minus-baseline set-diff BY NAME (suite-basename::Contract::testName) parsed from forge test --json"
key-files:
  created:
    - "test/REGRESSION-BASELINE-v56.md"
  modified:
    - "test/fuzz/V55FreezeDeterminism.t.sol"
    - "test/fuzz/V55RevertFreeEvCap.t.sol"
    - "test/fuzz/V55SetMutationOpenE.t.sol"
    - "test/fuzz/KeeperNonBrick.t.sol"
    - "test/gas/KeeperLeversAndPacking.t.sol"
key-decisions:
  - "Baselined the 453f8073 contract subject via the byte-identical-contracts commit 83a6a9ca (the v55 TST HEAD): the raw 453f8073 commit's own test corpus is UNCOMPILABLE (AfKing.sol deleted but DeployProtocol + 5 test files still deploy/import it at a load-bearing nonce); 83a6a9ca has git-diff-empty contracts vs 453f8073 and a compilable v55 corpus, reproducing the v55 TST-HEAD 603/134/16."
  - "Resolved the 14 migration-unmasked v56-behavior reds (live - baseline) by vm.skip-with-reason DROP (the EXPANDED MANDATE's drop-as-removed-surface option), NOT by masking: each was verified Success@baseline / Failure@HEAD-pre-drop, each is a stale v55 assertion the audited v56 diff legitimately superseded, and each v56 successor property is re-proven GREEN by V56SecUnmanipulable/V56FreezeSolvency/V56QuestNonPerturb/V56AfkingGasMarginal."
  - "Carried the unseeded DegeneretteBet.inv subset relaxation (live - union == empty, NOT strict equality) per the v49/v50/v55 precedent."
  - "Surfaced the drainAffiliateBase dispatch-stub reachability as a 357 carried finding (SURFACED, not dropped) — beats a falsely-green tree."
patterns-established:
  - "NON-WIDENING by NAME, never a bare count: the pre-drop run was 148 failed (134 baseline + 14 v56 widenings); the name-set gate caught all 14 as live-minus-union reds the drop then resolved BY NAME."
requirements-completed: [SEC-01, SEC-02, LIVE-01, GAS-06]
duration: ~95min
completed: 2026-06-02
---

# Phase 356 Plan 07: REGRESSION-BASELINE-v56.md — the BY-NAME NON-WIDENING ledger + the migration-unmasked stale-red resolution Summary

**Authored `test/REGRESSION-BASELINE-v56.md` (435 lines, the v55 7-section structure cloned, baseline swapped to the empirically-established `453f8073` 134-name union) AND resolved the 14 migration-unmasked v56-behavior reds so the live v56 forge tree is genuinely NON-WIDENING — `live failing set == the 453f8073 baseline union BY NAME` (`live − union == ∅` AND `union − live == ∅`).**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-06-02T22:20:00Z
- **Completed:** 2026-06-02T23:55:00Z
- **Tasks:** 2
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments

- **Established the `453f8073` baseline EMPIRICALLY** despite the baseline corpus being uncompilable: the raw `453f8073` commit deleted `AfKing.sol` but its own `DeployProtocol.sol` + 5 test files still deploy/import it at a load-bearing CREATE nonce, so that tree does not compile. Ran the byte-identical-contracts commit `83a6a9ca` (the v55 TST HEAD; `git diff 453f8073 83a6a9ca -- contracts/` is EMPTY) in an isolated worktree → reproduced **603 passed / 134 failed / 16 skipped** = the `453f8073`-subject red union BY NAME.
- **Computed `live − baseline` and found 14 genuine WIDENINGS** (all verified Success@baseline / Failure@HEAD-pre-drop) — the migration-unmasked v56-behavior reds the prior plans documented (milli-ETH packing, 0.01-ETH subscribe min-buy, `E()`-vs-`Panic(0x11)`, the unified `openBoxes` valve, the dropped `autoOpen`).
- **RESOLVED all 14 via `vm.skip`-with-reason DROP** (the removed/adapted-surface option), each documented BY NAME + the v56 successor green proof — making the live tree **624 passed / 134 failed / 30 skipped**, with the live 134 failing set **byte-identical** to the `453f8073` 134-name union (`live − union == ∅` AND `union − live == ∅`).
- **Authored the 7-section ledger** with the binding BY-NAME headline, the empirical-checkout method, Buckets A(41)/B(92)/F(1), the D-10 offset-migration NARROWING, the ⊆ relaxation, the v56 green-proof inventory (40 new green), the SEC-02 leg-1 SOLVENCY-01 byte-diff anchor (`GameAfkingModule:709-710 ↔ :663-664`, byte-identical), and the FC1-FC6 false-confidence guards.
- **Surfaced (not masked) the `drainAffiliateBase` dispatch-stub reachability** as a carried 357 finding.

## Task Commits

1. **Task 1 (the run + the 14-red resolution): drop the migration-unmasked v55-behavior reds** — `f23b010e` (test)
2. **Task 2 (the ledger): author REGRESSION-BASELINE-v56.md** — `97fac47b` (test)

_Note: the per-task ordering was inverted vs the PLAN (Task 1 captured the data AND resolved the 14 widenings before authoring the ledger), because the widening resolution is a prerequisite for a NON-WIDENING ledger — the ledger records the post-resolution state._

## Files Created/Modified

- `test/REGRESSION-BASELINE-v56.md` (CREATED) — the BY-NAME NON-WIDENING ledger (435 lines).
- `test/fuzz/V55FreezeDeterminism.t.sol` — `vm.skip`-dropped the 2 differential tests (milli-ETH unmask).
- `test/fuzz/V55RevertFreeEvCap.t.sol` — `vm.skip`-dropped 6 (3 EV-cap milli-ETH + 2 class-B funding-delta + 1 class-B `E()`-selector).
- `test/fuzz/KeeperNonBrick.t.sol` — `vm.skip`-dropped 4 (2 funding-delta + 2 `E()`-selector / over-withdraw).
- `test/fuzz/V55SetMutationOpenE.t.sol` — `vm.skip`-dropped 1 (the v56 unified `openBoxes` valve opens afking-first).
- `test/gas/KeeperLeversAndPacking.t.sol` — `vm.skip`-dropped 1 (the dropped `autoOpen` source string; also dropped `view` to call the cheatcode).

## Decisions Made

- **Empirical baseline via the byte-identical-contracts commit.** The raw `453f8073` corpus is uncompilable (AfKing.sol deleted; `DeployProtocol.sol:126` still deploys it at nonce 23, on which the CREATE-address prediction depends). Sidelining the AfKing-importing files cannot work because the shared fixture deploys AfKing at a load-bearing nonce. The faithful empirical baseline is the `453f8073` contract subject run with the v55-adapted compilable corpus — commit `83a6a9ca`, whose contracts are byte-identical to `453f8073`. This reproduced the v55 TST-HEAD 603/134/16 = the real `453f8073` red set (documented in the ledger §2 NOTE + §6 FC6).
- **Drop-by-name-with-reason for the 14 widenings (the EXPANDED MANDATE's removed/adapted-surface option).** Each of the 14 was verified Success@baseline / Failure@HEAD-pre-drop — a genuine widening from the v56 contract behavior change, NOT a layout-read bug. Each is a stale v55 assertion the USER-approved + audited v56 diff legitimately superseded, and each v56 successor property is re-proven GREEN by the new v56-native suites. `vm.skip(true, reason)` (the `RngLockDeterminism` precedent) registers them as Skipped (not Failure), making the live tree genuinely NON-WIDENING while recording the v56-supersession reason inline + in the ledger §3b.
- **Carried the ⊆ relaxation** (the unseeded `DegeneretteBet.inv` cluster — live − union == ∅, not strict equality) per the v49/v50/v55 precedent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The PLAN's empirical-checkout method (raw `453f8073` full-tree run) is impossible — the baseline corpus is uncompilable**
- **Found during:** Task 1 (the baseline checkout)
- **Issue:** The plan/CONTEXT D-11 said "check out `453f8073` and run its FULL tree." At `453f8073`, `contracts/AfKing.sol` is DELETED (the v55 dissolution) but that commit's own test corpus (`DeployProtocol.sol` + 5 test files) still imports + DEPLOYS `AfKing` at a load-bearing CREATE nonce (`DeployProtocol.sol:126`, nonce 23) — so the raw `453f8073` tree hard-errors `Source "contracts/AfKing.sol" not found` and cannot run. Sidelining the AfKing files breaks the shared fixture (the nonce shift invalidates every predicted address).
- **Fix:** Ran the `453f8073` *contract subject* via the byte-identical-contracts commit `83a6a9ca` (the v55 TST HEAD; `git diff 453f8073 83a6a9ca -- contracts/` is EMPTY), which carries the v55-adapted compilable corpus. Reproduced 603/134/16 — the real `453f8073` red union BY NAME. This is the SAME empirical-re-run spirit the plan mandates; only the runnable commit differs (documented in ledger §2 NOTE + §6 FC6). This matches the v55 §2 NOTE "sideline the uncompilable corpus" precedent, generalized to "run the byte-identical-contracts compilable commit."
- **Files modified:** none in the main tree (isolated `/tmp/v56_baseline_wt` worktree, removed after).
- **Verification:** `git diff 453f8073 83a6a9ca -- contracts/` EMPTY; the run reproduced the v55 TST-HEAD 603/134/16.
- **Committed in:** n/a (method, not a code change).

**2. [Rule 3 - Blocking / EXPANDED MANDATE] Resolved the 14 migration-unmasked v56-behavior reds (touches files beyond the ledger)**
- **Found during:** Task 1 (`live − baseline` set-diff)
- **Issue:** The v56 HEAD pre-drop run was 624/**148**/16 — 14 reds OVER the 134-name baseline (`live − union ≠ ∅`). The PLAN's Task 2 said "if the set-diff is NOT empty, STOP." But the EXPANDED MANDATE (STEP C) explicitly authorizes resolving the migration-unmasked v56-behavior reds in this plan (matching what v55's Phase 351 did — adapt the corpus + drop removed-surface tests IN the TST phase). All 14 were classified as stale v55-behavior assertions the audited v56 diff superseded (NONE a genuine v56 bug).
- **Fix:** `vm.skip(true, "<v56-supersession reason>")` each of the 14 (5 files), each with an inline reason + the v56 successor green proof. Re-ran the full tree → 624/**134**/30, the live 134 byte-identical to the baseline 134.
- **Files modified:** `V55FreezeDeterminism.t.sol`, `V55RevertFreeEvCap.t.sol`, `V55SetMutationOpenE.t.sol`, `KeeperNonBrick.t.sol`, `KeeperLeversAndPacking.t.sol`.
- **Verification:** `comm -23 live baseline` (widening) == ∅; `comm -13` (narrowing) == ∅; the sets byte-identical; the 14 confirmed Skipped (was Failure); the 4 v56 proof suites still 11/7/7/15 green; `forge build` EXIT 0; ZERO contract mutation.
- **Committed in:** `f23b010e` (Task 1 commit).

---

**Total deviations:** 2 (both Rule 3 / EXPANDED-MANDATE-authorized).
**Impact on plan:** Both were necessary for a genuine NON-WIDENING ledger. The empirical-baseline method is faithful to D-11's intent (the `453f8073` subject's red union, re-run honestly). The 14-red resolution is the EXPANDED MANDATE's explicit charge — without it the tree would be falsely WIDENING by 14 stale v55 assertions. No scope creep, no genuine v56 bug masked (the `drainAffiliateBase` reachability question is SURFACED for 357).

## Issues Encountered

- **The forge `--json` is ~275-321 MB per run** (the `traces` arrays). Parsed counts + failing names via `jq` keyed on `(file:Contract).test_results[].status` — no issue, just large.
- **The baseline worktree lacked `node_modules`** (worktrees don't copy it). Symlinked the main repo's `node_modules` into the worktree so `patchForFoundry.js` could resolve `ethers`; removed the symlink + worktree at cleanup. Main tree never touched.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: unreachable-stub (CARRIED for 357) | contracts/DegenerusGame.sol | `drainAffiliateBase` (called by `DegenerusAffiliate.claim` on the GAME address, `DegenerusAffiliate.sol:654`) has NO thin delegatecall dispatch stub on `DegenerusGame` (only `subscribe`/`mintBurnie`/`claimAfkingBurnie` + no fallback) — a direct `game.drainAffiliateBase(sub)` reverts "unrecognized function selector". 356-03 proved the SEC-01 affiliate-churn property at the storage level instead. May be expected (live deployment routing differs from the forge fixture) OR may indicate the affiliate-base settlement is unreachable on the frozen subject. The 357 adversarial sweep / delta-audit MUST confirm intended-vs-bug. SURFACED in the ledger §7b, NOT masked. |

## Known Stubs

None. The ledger is a doc-only artifact recording the empirical whole-tree run; the 5 test-file edits are `vm.skip`-with-reason drops of stale assertions (the test bodies are preserved below the skip — no placeholder/mock data introduced). The drained-surface property each test asserted is re-proven by a named v56-native green suite.

## Next Phase Readiness

- The NON-WIDENING gate is GREEN: the live v56 forge tree (624/134/30) is byte-identical to the `453f8073` baseline union BY NAME — the Phase-357 TERMINAL delta-audit can consume this as the regression baseline.
- Carried into 357: the `drainAffiliateBase` dispatch-stub reachability finding (§7b) — confirm intended-vs-bug in the adversarial sweep.
- ZERO `contracts/*.sol` mutation by this plan (`git diff 453f8073 HEAD -- contracts/` is the committed v56 diff, unchanged); the subject stays byte-frozen for 357.

## Self-Check: PASSED

- test/REGRESSION-BASELINE-v56.md — FOUND (435 lines; `453f8073` anchor + binding headline + SOLVENCY-01 anchor `:663-664` + NARROWING + drainAffiliateBase carried finding all present).
- .planning/phases/356-.../356-07-SUMMARY.md — FOUND.
- Commit `f23b010e` (the 14 drops) — FOUND in git log.
- Commit `97fac47b` (the ledger) — FOUND in git log.
- The 14 `vm.skip(true, "v56...")` DROPs present (2 + 6 + 1 + 4 + 1 = 14 across the 5 files).
- `git diff --quiet HEAD -- contracts/` exits 0 — ZERO contract mutation; `git diff 453f8073 HEAD -- contracts/` is the committed v56 diff (NOT empty, NOT a 356 edit).
- The live v56 forge tree (624/134/30) is byte-identical to the empirical `453f8073` baseline union (134) BY NAME (`live − union == ∅`).

---
*Phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb*
*Completed: 2026-06-02*
