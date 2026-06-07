---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 06
subsystem: testing
tags: [foundry, forge, rng-freeze, solvency, invariant, two-block-determinism, snapshot-replay, prevrandao, claimablePool, afpay-waterfall, proving-tests]

# Dependency graph
requires:
  - phase: 376-impl-the-one-batched-contract-diff
    provides: "the shipped v61 impl (b97a7a2e) — _settleShortfall + the balancesPacked accessors (no rngWord), maybeCurse/decurse/smite/_applyCurseStack (activity-score/curse-counter only), the call-site claimablePool pairing in _processMintPayment (:1140/:1150) + _settleShortfall (:869/:878) + depositAfkingFunding (:1631)"
  - phase: 378-01-tst-foundation
    provides: "the authoritative v61 storage layout (balancesPacked root slot 7 [afking:hi128|claimable:lo128], claimablePool slot 1 byte 16, mintPacked_ slot 9, CURSE_COUNT_SHIFT 215, dailyIdx slot 0 byte 3)"
  - phase: 378-04-proving-tests
    provides: "the live-purchase + canonical-layout seeders (claimable/afking paired, dailyIdx, AfkingSpent log-scan, prize-pool-delta) reused by SEC-01/02"
  - phase: 378-05-proving-tests
    provides: "the real-deity-pass mint + BURNIE mint patterns reused by the smite legs"
provides:
  - "V61RngFreezeIntact.t.sol — SEC-01: a two-block determinism replay (snapshot/revert + perturbed prevrandao/coinbase/number/timestamp) proving the AFPAY waterfall, the cashout-curse SET, and smite produce byte-identical outcomes across block contexts; the curse*100 bps penalty proven a pure function of curseCount; a complementary static grep leg attesting no rngWord token in the maybeCurse/decurse/smite/_settleShortfall/accessor bodies"
  - "V61AfkingSpendHandler.sol — the SEC-02 invariant handler driving the new afking spend paths (afking-funded buy, packed credit/debit, stale cashout, smite, decurse, advance) via REAL paired entrypoints (no vm.stored balances), with ghost accounting"
  - "V61SolvencyAfpay.inv.t.sol — SEC-02: invariant_v61PoolEqualsSumOfHalves (claimablePool == Σ claimable+afking halves, read from the real slot 7) + invariant_v61PoolNeverExceedsBacking (claimablePool <= bal + stETH), both 256×128 with 0 reverts, plus 4 focused scenarios for the named SEC-02 paths"
affects: [379-terminal-delta-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-block RNG-freeze determinism via vm.snapshotState/vm.revertToState: run an op from a byte-identical seeded pre-state at two perturbed block contexts (roll/warp + prevrandao/coinbase), assert the observable outcome (struct of ledger deltas / curse count / score) is byte-identical — a real VRF/block read would diverge"
    - "Replay discipline: hold the storage-field staleness basis (dailyIdx) FIXED across the replay; perturb ONLY the block entropy the surface should ignore (a block.* read would be caught; dailyIdx is not block state)"
    - "Falsifiable solvency invariant from REAL slots: sum (claimable low half + afking high half of balancesPacked) over a complete tracked-address set and assert == claimablePool (not a parallel mirror that could drift)"
    - "Genuine end-to-end balance creation in the invariant handler: credit ONLY through real paired entrypoints (depositAfkingFunding pairs claimablePool +=; the waterfall debits pair claimablePool -=; jackpot wins pair the credit) — never vm.store a balance into existence (which would test the seeder, not the contract)"
    - "Complete tracked-set closure: the actor pool are the sole ticket buyers ⇒ the sole jackpot winners; + VAULT/SDGNRS/GNRUS (deploy self-subscribes + protocol quarter-shares) ⇒ no untracked address can ever receive a credit"
    - "Bounded source-region grep via vm.readFile (fs_permissions read ./contracts) anchored between two function markers, with a non-vacuity sanity (the region DOES contain a token known present) — a static no-rngWord attestation complementing the dynamic proof"

key-files:
  created:
    - "test/fuzz/V61RngFreezeIntact.t.sol"
    - "test/fuzz/handlers/V61AfkingSpendHandler.sol"
    - "test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol"
  modified: []

key-decisions:
  - "SEC-01 + SEC-02 BOTH PROVEN against the shipped v61 impl — NO CONTRACT-CHANGE-NEEDED. The v61 AFPAY/PACK/CURSE/SMITE surfaces read no VRF/block entropy in a player-manipulable window (empirical two-block determinism), and the SOLVENCY-01 master identity (claimablePool == Σ halves) + the bal+stETH backing bound hold across every afking spend path."
  - "The two-block replay holds dailyIdx (the maybeCurse staleness basis, a monotonic advance counter — NOT block.timestamp) FIXED across runs; only block.number/timestamp/prevrandao/coinbase are perturbed, since those are exactly the entropy the surfaces must be insensitive to. Moving dailyIdx would legitimately change staleness and is not a block-state read."
  - "The SEC-02 handler creates balances ONLY via real paired entrypoints (depositAfkingFunding for afking, jackpot wins for claimable) so the half-sum identity is a genuine end-to-end property; the focused stale-cashout scenario seeds claimable paired (identity holds going in) then verifies the contract's real claimWinnings debit keeps it paired going out."
  - "The tracked-address set (5 actors + 1 deity + VAULT/SDGNRS/GNRUS) is a complete cover for every balance mutation: actors are the only ticket buyers (⇒ the only jackpot winners), and the protocol addresses take the deploy self-subscribes + jackpot quarter-shares — so the Σ over the tracked set is exact, not approximate."

patterns-established:
  - "Falsifiability spot-check per requirement: SEC-01 — inverting the AFPAY freeze assertion to require DIVERGENCE FAILS (proving the replay genuinely perturbs the block AND the outcome is genuinely block-invariant); SEC-02 — a 1-wei unpaired-debit corruption (claimablePool bumped without a matching balance) breaks the half-sum identity (proving a dropped paired claimablePool -= would be caught)"

requirements-completed: [SEC-01, SEC-02]

# Metrics
duration: 70min
completed: 2026-06-07
---

# Phase 378 Plan 06: SEC-01 RNG-Freeze + SEC-02 SOLVENCY-01 (the v61 hard security floor) Summary

**Three new forge files (13 tests — 6 SEC-01 + 7 SEC-02, all GREEN against the shipped v61 impl) empirically certify the milestone's two USER-locked hard-floor invariants: the AFPAY/PACK/CURSE/SMITE surfaces carry NO VRF/block entropy in a player-manipulable window (two-block determinism replay), and `claimablePool == Σ(claimable+afking halves)` + `claimablePool <= bal+stETH` hold across every afking spend path (a 256×128 invariant campaign + 4 focused scenarios) — both proofs falsifiable, ZERO contract edits (tree-hash `87e3b45b…` / fingerprint `fcdd999c…` preserved).**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-06-07T10:50:00Z (approx)
- **Completed:** 2026-06-07T12:00:00Z (approx)
- **Tasks:** 2
- **Files created:** 3 (test-only)

## Accomplishments

- **SEC-01 (V61RngFreezeIntact.t.sol, 6 tests):** Proves the RNG-freeze property for the v61 surfaces by a two-block determinism replay — each operation runs twice from a byte-identical seeded pre-state (`vm.snapshotState`/`vm.revertToState`) at two DIFFERENT block contexts (perturbed `block.number`/`block.timestamp`/`block.prevrandao`/`block.coinbase`), asserting the observable outcome is byte-identical: the AFPAY waterfall (a Combined buy drawing all three tiers via the live `_processMintPayment`) over a 5-field outcome struct (claimable delta, afking delta, claimablePool delta, prizeContribution, AfkingSpent amount) — both a fixed-context test AND a 1000-run fuzz; the cashout-curse SET (the resulting curseCount + the post-curse public activity score); a smite (the resulting curseCount); and the `curse*100` bps penalty as a pure function of curseCount (a 1000-run fuzz proving the score is block-invariant for a fixed count AND tracks `base - curse*100` exactly). A complementary static leg greps the production `maybeCurse`/`decurse`/`smite`/`_applyCurseStack`/`_settleShortfall`/accessor bodies (via `vm.readFile`) and asserts no `rngWord` token, with a non-vacuity sanity (the region DOES contain the `claimablePool` token it pairs each debit with).
- **SEC-02 (V61AfkingSpendHandler.sol + V61SolvencyAfpay.inv.t.sol, 7 tests):** Proves SOLVENCY-01 across the new afking spend paths. `invariant_v61PoolEqualsSumOfHalves` reads the RAW `balancesPacked` slot (slot 7) for each tracked address, sums both halves, and asserts the total equals `claimablePoolView()` — 256 runs × 128 depth = 32768 calls, 0 reverts. `invariant_v61PoolNeverExceedsBacking` asserts `claimablePool <= address(game).balance + stETH` (same campaign). The handler drives all six action types (afking-funded buy, packed credit/debit via depositAfkingFunding, stale cashout, smite, decurse, advance) thousands of times each with 0 reverts, creating balances ONLY through real paired entrypoints. 4 focused scenarios prove each named SEC-02 path: an afking-funded buy drops claimablePool by exactly the afking drawn (paired debit, identity intact); a packed credit/debit round-trips with the claimable/afking halves correctly isolated; a real stale cashout via `claimWinnings` pays out to the sentinel + sets the curse + keeps the pool paired; and a smite + a decurse are pool-neutral (claimablePool moves by EXACTLY zero).
- **Both proven against the shipped v61 impl** — no contract change required; the v61 behavior matches the design-lock hard floor (SPEC §1 Hard Floor: RNG-freeze intact + SOLVENCY-01 centralized).

## Task Commits

Each task was committed atomically (test-only, hooks run, not pushed):

1. **Task 1: SEC-01 RNG-freeze determinism** — `56976c38` (test)
2. **Task 2: SEC-02 SOLVENCY-01 invariant + handler** — `d2c35ff2` (test)

**Plan metadata:** (this commit) `docs(378-06): complete SEC-01/SEC-02 hard-floor plan`

## Files Created/Modified

- `test/fuzz/V61RngFreezeIntact.t.sol` (522 lines, 6 tests) — SEC-01 RNG-freeze two-block determinism proof
- `test/fuzz/handlers/V61AfkingSpendHandler.sol` (~290 lines) — SEC-02 invariant handler (afking spend paths, real paired entrypoints, ghost accounting)
- `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol` (~310 lines, 7 tests) — SEC-02 SOLVENCY-01 invariants + focused scenarios

No `contracts/*.sol` modified (test-only phase; contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` / fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` preserved throughout; `git status --porcelain contracts/` empty at every commit).

## Decisions Made

- **No CONTRACT-CHANGE-NEEDED.** SEC-01 (6) + SEC-02 (7) all pass against the shipped v61 impl. The PROVING_TEST escalation (a provably-correct failing test contradicting the spec → a real v61 finding) was NOT triggered — RNG-freeze and the solvency identity both hold.
- **Replay perturbs block entropy, holds dailyIdx fixed.** `maybeCurse`'s staleness basis is `_currentMintDay()` == `dailyIdx` (a monotonic advance counter in slot 0, NOT `block.timestamp` — confirmed in `GameAfkingModule.sol:1679` reading `_currentMintDay()` and `DegenerusGameStorage.sol:1379`). The two-block replay perturbs `block.number`/`timestamp`/`prevrandao`/`coinbase` (the entropy a VRF leak would consume) while holding `dailyIdx` constant, so the curse outcome is compared apples-to-apples; a surface reading any perturbed value would diverge and fail.
- **The grep BACKWARD-traced the v61 surfaces.** The only `rngWord` references in `GameAfkingModule.sol` are in the afking-BOX auto-buy path (`_deliverAfkingBuy`, lines ~761-1488 — out of v61 scope, documented freeze-safe); `maybeCurse`/`decurse`/`smite`/`_applyCurseStack`, `_settleShortfall`, and the `_claimableOf`/`_afkingOf`/`_credit*`/`_debit*` accessors read none. The static leg bounds its grep to those bodies specifically.
- **The SEC-02 identity is read from the real slot, end-to-end.** The handler never `vm.store`s a balance into existence (which would test the seeder); afking is credited via the real `depositAfkingFunding` (pairs `claimablePool +=`), drawn via the real waterfall (pairs `-=`), and claimable is credited via real jackpot wins (paired) — so a green invariant is a genuine contract property. The one `vm.store` in a focused test (seeding claimable for the stale-cashout scenario) is paired with claimablePool so the identity holds going IN, and the test then verifies the contract's own `claimWinnings` debit keeps it paired going OUT.

## Deviations from Plan

None affecting scope — the plan was executed as written (2 TDD test tasks, each authored + verified + falsifiability-checked + committed atomically). One test-side authoring refinement (not a contract deviation):

### Test-side refinement (within Task 2 authoring)

**1. [Test-setup] The focused stale-cashout scenario seeds claimable (paired) rather than mining a real jackpot win**
- **Found during:** Task 2 (the `testScenarioStaleCashoutKeepsIdentity` focused test)
- **Issue:** The cleanest real claimable source for a single focused test is a jackpot win, which is heavy to drive deterministically in isolation. (`depositAfkingFunding` credits the afking half, not claimable.)
- **Fix:** Seed claimable via a `vm.store` PAIRED with `claimablePool` (the SOLVENCY-01 identity holds going IN), seed `dailyIdx` so the claimant is stale, then drive the REAL public `claimWinnings` and assert the contract's own claim debit keeps the pairing (payout to the sentinel, claimablePool down by exactly the payout, curse set +2, identity intact AFTER). The EXACT stale-cashout-from-real-winnings coverage additionally lives in the invariant campaign (the handler's `advance` action credits real jackpot claimable that `staleCashout` then drains).
- **Verification:** `testScenarioStaleCashoutKeepsIdentity` green; the invariant campaign's `staleCashout` ran 5460 times with 0 reverts and the half-sum identity held across all 32768 calls.

---

**Total deviations:** 0 contract deviations; 1 test-setup refinement (no scope change).
**Impact on plan:** None — SEC-01 and SEC-02 are both proven exactly as specified, falsifiably, against the frozen impl.

## Falsifiability Verification (T-378-06-01/02/03 mitigations)

Each requirement's proof was confirmed falsifiable by a temporary inversion (then restored; contracts re-verified clean at `87e3b45b`):

- **SEC-01 (T-378-06-01/03):** Inverting the AFPAY freeze assertion to require the two perturbed-block runs to DIVERGE (`assertTrue(o1.afkingDelta != o2.afkingDelta)`) FAILED — proving (a) the replay genuinely perturbs the block context, and (b) the AFPAY outcome is genuinely block-invariant, so the real `assertEq` would catch a real VRF/block-entropy leak (which WOULD diverge). The two-block replay is the PRIMARY evidence; the source-grep is complementary (and has its own non-vacuity sanity).
- **SEC-02 (T-378-06-02):** A 1-wei unpaired-debit corruption (claimablePool bumped by 1 with NO matching balance — the footprint of a dropped paired `claimablePool -=`) made the half-sum identity check FAIL (`10000000000000000001 != 10000000000000000000`) — proving the invariant is computed from the real slots and would catch a real solvency-accounting bug, not a mirror that could drift green.

## Issues Encountered

- **`--match-path` is single-valued (it takes the last one).** A combined run was done via a brace glob `test/fuzz/{V61RngFreezeIntact.t.sol,invariant/V61SolvencyAfpay.inv.t.sol}` — both suites green together (13 tests).
- **The invariant metric tables truncate the per-invariant PASS lines under `tail`.** Confirmed `invariant_v61PoolEqualsSumOfHalves` green by name via a `--match-test` run (256 runs, 32768 calls, 0 reverts).

## User Setup Required

None — test-only phase, no external service configuration.

## Next Phase Readiness

- SEC-01 + SEC-02 are the LAST two of the eight 378 TST proofs (TST-01..06 + SEC-01/02 now ALL complete). Phase 378 TST is fully proven. Ready for **379 TERMINAL** (the delta-audit + the 3-skill genuine-PARALLEL adversarial sweep + `audit/FINDINGS-v61.0.md` + the atomic closure flip with the `MILESTONE_V61_AT_HEAD_<sha>` signal).
- 379's delta-audit re-attests RNG-freeze + the SOLVENCY-01 identity with anchors; these two proofs are now the empirical backing it carries (the SPEC §1 Hard Floor is proven, not asserted). The reusable two-block-replay harness + the real-paired-entrypoint invariant handler are established for any further adversarial probing of the afking solvency accounting + the curse/smite activity-score path.
- The contract subject remains byte-frozen (tree-hash `87e3b45b…`); these are NEW test files — they add green and characterize the v61 hard-floor surfaces positively (the carried-red regression set from TST-06 is unaffected).
- No blockers.

## Self-Check: PASSED

- Files: V61RngFreezeIntact.t.sol, V61AfkingSpendHandler.sol, V61SolvencyAfpay.inv.t.sol, 378-06-SUMMARY.md — all FOUND.
- Commits: `56976c38`, `d2c35ff2` — all FOUND in git history.
- Contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` (fingerprint `fcdd999c…`) — preserved; `git status --porcelain contracts/` empty.
- SEC-01 6/6 green (incl. 2×1000-run fuzz); SEC-02 7/7 green (3 invariants 256×128 / 32768 calls / 0 reverts + 4 focused scenarios). Falsifiability spot-checked for both requirements.

---
*Phase: 378-tst-proving-tests-rng-freeze-solvency*
*Completed: 2026-06-07*
