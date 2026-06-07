---
phase: 378-tst-proving-tests-rng-freeze-solvency
verified: 2026-06-07T11:36:33Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  note: initial verification
---

# Phase 378: TST — One Proving Test per Surface (TST-01..06) + RNG-Freeze Intact + SOLVENCY-01 Re-Attested (SEC-01/02) — Verification Report

**Phase Goal:** The milestone proven behaviorally correct + the hard floor proven empirically vs `2bee6d6f`.
**Verified:** 2026-06-07T11:36:33Z
**Status:** passed
**Re-verification:** No — initial verification

This was a TEST-ONLY phase (zero contract edits permitted). Verification was done GOAL-BACKWARD and
EMPIRICALLY: every proving test was RUN (not trusted from SUMMARY), the non-widening gate was
recomputed BY NAME from a fresh full-suite run (not from the ledger's counts), the contract boundary
was re-checked before and after all forge runs, and each proof was read line-by-line for
falsifiability (tautology / ceremonial-pass detection).

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | TST-01 AFPAY waterfall proven by a real, falsifiable test | ✓ VERIFIED | `V61AfpayWaterfall.t.sol` RUN: 10 passed / 0 failed. ARM A drives the production `_settleShortfall` body via `SettleClaimableShortfallTester` (verified it `return _settleShortfall(...)` — NOT a re-impl); ARM B drives live `purchase()`→`_processMintPayment` across all 3 pay-kinds. Exact draw-ordering, strict 1-wei sentinel (`==1`, not `<=1`), pinned `AfkingSpent` amount, paired pool debit, both-short revert, AFPAY-03 lootbox shortfall, no-double-draw (AfkingSpent count == 0 on auto-buy path while afking still moves). 38 assertions. |
| 2 | TST-02 PACK accessors round-trip / no cross-bleed / Σ identity | ✓ VERIFIED | `V61Pack.t.sol` RUN: 8 passed / 0 failed. Reads the RAW packed slot 7 and splits in-test (proves the OTHER half at storage level, not just accessor return). Cross-half non-interference, no-carry at supply bound, gameOver infra afking-half preservation, two-mapping value equivalence vs plain counters. 34 assertions. |
| 3 | TST-03 cashout-curse SET + exemptions + penalty + stacking | ✓ VERIFIED | `V61CurseSet.t.sol` RUN: 13 passed / 0 failed. EVERY exemption proven BY CONTRAST (exempt==0 vs otherwise-identical non-exempt==2) — a removed bail flips the contrast and fails. Penalty pinned to `base-curse*100` (not `<=base`), floor-at-zero, frozen-snapshot consumer, stacking saturation pinned at exactly 20 (no uint8 wrap), same-day-second-claim revert. 28 assertions. |
| 4 | TST-04 CURE + bounty-stamp + decurse | ✓ VERIFIED | `V61CureBountyDecurse.t.sol` RUN: 13 passed / 0 failed. Cure on every `purchase()` host path × {fresh ETH, claimable}; cure-before-score by contrast (`curedScore-notCuredScore == curse*100`); whale-bundle pass-host proven NOT to cure (curse=6 survives) — boundary falsifiable both directions; sub-ticket DAY_SHIFT stamp + manual-lootbox bounty eligibility; decurse exact 100-BURNIE burn + Decursed emit + revert-if-0 (BURNIE unchanged) + permissionless. 31 assertions. |
| 5 | TST-05 SMITE gate / immunity / ceiling / shared counter | ✓ VERIFIED | `V61Smite.t.sol` RUN: 10 passed / 0 failed. All 4 revert legs assert BURNIE UNCHANGED (pre-burn validation). Success pins 200-BURNIE burn + exactly +2 + Smited emit. Shared counter proven by SUM (cashout 4 + smite 2 == 6). Single-buy + decurse both clear combined. Self-smite allowed. 30 assertions. |
| 6 | SEC-01 RNG-freeze intact across all v61 surfaces | ✓ VERIFIED | `V61RngFreezeIntact.t.sol` RUN: 6 passed / 0 failed (incl. 2 fuzz). Two-block determinism replay: snapshot/revert from byte-identical pre-state, perturb `prevrandao`/`coinbase`/`number`/`timestamp`, assert byte-identical outcome — a real block-entropy read WOULD diverge. Non-vacuity guards (`assertGt(claimableDelta,0)`), exact anchors (`curse==2`, `score==600-200`). Static no-`rngWord` leg has its own non-vacuity sanity. Premise independently confirmed: every `rngWord` ref in GameAfkingModule is ≤ line 1488 (auto-buy box path), all ABOVE `maybeCurse`(1668)/`decurse`(1696)/`smite`(1710). 27 assertions. |
| 7 | SEC-02 SOLVENCY-01 re-attested across afking spend paths | ✓ VERIFIED | `V61SolvencyAfpay.inv.t.sol` (+ handler) RUN: 7 passed / 0 failed. `invariant_v61PoolEqualsSumOfHalves` + `invariant_v61PoolNeverExceedsBacking` each 256 runs × 32768 calls / 0 reverts, reading the REAL slot 7 + REAL `claimablePoolView()` (no parallel mirror). Handler creates balances ONLY via real paired entrypoints (verified: never `vm.store`s a balance; the one `vm.store` is the deity-score bit). All 6 spend paths exercised 5285–5560 calls each. Pairing premise confirmed in contract (claimablePool ±= at Storage:869/878, Game:1140/1150/1631/1648). 17 assertions. |
| 8 | TST-06 suite NON-WIDENING by name vs `2bee6d6f` | ✓ VERIFIED | Full `forge test` RUN at HEAD: 66 failing / 724 succeeded. Live red NAMES extracted independently (60 `test*` + 3 `invariant_*` = 63 this run) and set-diffed against `UNION` (172 §3 baseline ∪ 3 class-(c) ∪ 3 VRFPath invariants = 178). **`live − UNION == ∅` (recomputed = 0).** NONE of the 8 V61 proving tests are red. |

**Score:** 8/8 truths verified

### ROADMAP Success Criteria (the binding contract)

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | One proving test per surface passes | ✓ VERIFIED | TST-01..05 all green (54 tests); each exercises real production code with falsifiable assertions |
| 2 | RNG-freeze intact across all changes | ✓ VERIFIED | SEC-01 two-block determinism replay green; static grep premise confirmed (no rngWord in v61 curse/smite region) |
| 3 | SOLVENCY-01 re-attested (`claimablePool == Σ`, never exceeds `bal+stETH`) | ✓ VERIFIED | SEC-02 both invariants green from real slots, 256×32768/0 reverts; contract pairing confirmed at the call sites |
| 4 | Suite NON-WIDENING by name vs `2bee6d6f` | ✓ VERIFIED | `live − UNION == ∅` independently recomputed from a fresh full-suite run |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/V61AfpayWaterfall.t.sol` | TST-01 proof | ✓ VERIFIED | 487 lines, 10 tests green, 38 assertions, no debt markers |
| `test/fuzz/V61Pack.t.sol` | TST-02 proof | ✓ VERIFIED | 291 lines, 8 tests green, 34 assertions |
| `test/fuzz/V61CurseSet.t.sol` | TST-03 proof | ✓ VERIFIED | 503 lines, 13 tests green, 28 assertions |
| `test/fuzz/V61CureBountyDecurse.t.sol` | TST-04 proof | ✓ VERIFIED | 481 lines, 13 tests green, 31 assertions |
| `test/fuzz/V61Smite.t.sol` | TST-05 proof | ✓ VERIFIED | 366 lines, 10 tests green, 30 assertions |
| `test/fuzz/V61RngFreezeIntact.t.sol` | SEC-01 proof | ✓ VERIFIED | 522 lines, 6 tests green, 27 assertions |
| `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol` | SEC-02 proof | ✓ VERIFIED | 318 lines, 7 tests green, 17 assertions |
| `test/fuzz/handlers/V61AfkingSpendHandler.sol` | SEC-02 handler | ✓ VERIFIED | 283 lines; real paired entrypoints only (no vm.store balances) |
| `378-05-NONWIDENING-LEDGER.md` | TST-06 by-name ledger | ✓ VERIFIED | States `live − (union ∪ documented) == ∅` BY NAME; 178-name union; class-(c) + VRFPath documented |
| `test/REGRESSION-BASELINE-v61.md §7` | TST-06 verdict fold | ✓ VERIFIED | §3 enumerates 172 baseline names; §7 folds the 378-05 verdict |
| `378-03-CANDIDATE-FINDINGS.md` | class-(a/b/c) triage | ✓ VERIFIED | C-1/C-2 documented as accepted-staleness, NOT contract bugs; no CONTRACT-CHANGE-NEEDED |

All artifacts committed (git ls-files confirms all 8 test files tracked).

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `V61AfpayWaterfall` ARM A / `V61Pack` | production `_settleShortfall` / `_credit*`/`_debit*` | `SettleClaimableShortfallTester` inherits `DegenerusGameStorage`, `settle()` returns `_settleShortfall(...)` | ✓ WIRED | Real production body, not a re-implementation — verified in source |
| `V61AfkingSpendHandler` | live `depositAfkingFunding`/`purchase`/`claimWinnings`/`advanceGame` | real paired entrypoints | ✓ WIRED | Never vm.stores a balance; SEC-02 identity is genuine end-to-end |
| SEC-02 invariant | real slot 7 + `claimablePoolView()` | `vm.load(keccak256(abi.encode(addr,7)))` + view | ✓ WIRED | No parallel mirror; contract pairs claimablePool at Storage:869/878, Game:1140/1150/1631/1648 |
| SEC-01 static leg | `contracts/modules/GameAfkingModule.sol` etc. | `vm.readFile` bounded between fn anchors | ✓ WIRED | All rngWord refs ≤ line 1488, above the v61 curse/smite region (≥1668) — premise true |

### Behavioral Spot-Checks (the empirical gate — all tests RUN, not trusted)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| TST-01 | `forge test --match-path V61AfpayWaterfall.t.sol --no-match-test invariant` | 10 passed; 0 failed | ✓ PASS |
| TST-02 | `forge test --match-path V61Pack.t.sol` | 8 passed; 0 failed | ✓ PASS |
| TST-03 | `forge test --match-path V61CurseSet.t.sol` | 13 passed; 0 failed | ✓ PASS |
| TST-04 | `forge test --match-path V61CureBountyDecurse.t.sol` | 13 passed; 0 failed | ✓ PASS |
| TST-05 | `forge test --match-path V61Smite.t.sol` | 10 passed; 0 failed | ✓ PASS |
| SEC-01 | `forge test --match-path V61RngFreezeIntact.t.sol` | 6 passed; 0 failed | ✓ PASS |
| SEC-02 | `forge test --match-path invariant/V61SolvencyAfpay.inv.t.sol` | 7 passed; 0 failed (2 invariants 256×32768/0 reverts + 4 scenarios) | ✓ PASS |
| TST-06 | `forge test` (full) + independent name set-diff | 66 fail / 724 pass; `live − UNION == ∅` | ✓ PASS |

### TST-06 Non-Widening — Independent By-Name Recomputation (the decisive empirical check)

The ledger's verdict was NOT trusted. I ran the full suite fresh and recomputed the gate from raw output:

```
live HEAD unique red names (this run): 63   (60 test* + 3 invariant_)
UNION (172 §3 baseline ∪ 3 class-(c) ∪ 3 VRFPath invariants, deduped): 178
live − UNION  (THE GATE, must be ∅):    0   ← EMPTY (recomputed via comm -23)
```

- **`live − UNION == ∅`** — every live HEAD red name is accounted for. NON-WIDENING holds.
- **NONE of the 8 V61 proving tests appear in the live red set** (grep-confirmed by name).
- **Count discrepancy (63 vs the ledger's 66) explained and benign:** the 3 class-(c) candidates
  (`testFuzzTwoBlockOpenNoBlockEntropy`, `test_gapBackfillEntropyUnique_fuzz`,
  `test_gapBackfillWithMidDayPending_fuzz`) are FUZZ tests that came up GREEN in my run — exactly the
  bucket-A fuzz-seed variance the ledger documented. They are in the UNION regardless, so the gate is
  unaffected. Their intermittency *strengthens* the non-bug judgment: a deterministic contract bug
  would fail every run.
- The 3 VRFPath invariants (`invariant_allGapDaysBackfilled`/`rngUnlockedAfterSwap`/`stallRecoveryValid`)
  are RED this run, in the union (proven red @ baseline `2bee6d6f` per the ledger's non-destructive
  reproduction). The v61 diff touches none of that logic (`DegenerusGameAdvanceModule`, untouched).
- The class-(c) in-union siblings (`testStampedDayOpenAtTwoBlocksByteIdentical`,
  `testSubscribeMinBuyStampsNoInlineResolve`, `test_gapBackfillSingleDayGap`, `test_stallSwapResume`)
  are all present in the 172-name baseline union — confirming the "shared root with carried siblings"
  basis of the class-(c) dispositions.

### Contract Boundary (the milestone's hard rule) — VERIFIED BEFORE AND AFTER ALL RUNS

| Check | Expected | Result | Status |
|-------|----------|--------|--------|
| `git status --porcelain contracts/` (before runs) | empty | empty | ✓ |
| `git rev-parse HEAD:contracts` | `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` | `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` | ✓ |
| Any 378-01..06 commit touched `contracts/*.sol`? | none | none (5de3ccb8→fe0a9a43 all "no contracts/*.sol changed"; only contract-touching commit is `b97a7a2e` = phase 376 IMPL) | ✓ |
| `git status --porcelain contracts/` (after full forge runs) | empty | empty | ✓ |
| `git rev-parse HEAD:contracts` (after runs) | `87e3b45b...` | `87e3b45b...` | ✓ |

ZERO contract change. The contract subject is byte-identical to HEAD throughout. (Note:
`contracts/test/SettleClaimableShortfallTester.sol` is an inherited-storage test harness that was
last modified by the v61 IMPL commit `b97a7a2e`, NOT by any 378 commit, and is byte-identical to HEAD
— it genuinely delegates to the production `_settleShortfall`/accessor bodies, so the tests that use
it exercise real contract code.)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TST-01 | 378-04 | AFPAY waterfall (DirectEth skips claimable; Claimable/Combined draw claimable→sentinel→afking; fresh-rate affiliate/lootbox; AfkingSpent; both-short revert; no double-draw) | ✓ SATISFIED | V61AfpayWaterfall 10/10 green; all clauses asserted |
| TST-02 | 378-04 | PACK round-trips at every site; `claimablePool == Σ`; gameOver preserves infra afking; no cross-half carry; behavior-identical to two-mapping | ✓ SATISFIED | V61Pack 8/8 green; raw-slot split + equivalence proofs |
| TST-03 | 378-04 | CURSE SET +2 only on stale cashout; all exemptions; penalty floored 0; stacking min(2N,cap); same-day revert | ✓ SATISFIED | V61CurseSet 13/13 green; exemptions by contrast |
| TST-04 | 378-05 | CURE on ≥1-ticket buy (all paths, both fundings); sub-ticket stamps DAY_SHIFT no cure; manual lootbox bounty-eligible; decurse 100 BURNIE + Decursed + revert-if-0 | ✓ SATISFIED | V61CureBountyDecurse 13/13 green; whale-bundle no-cure contrast |
| TST-05 | 378-05 | SMITE ownerOf gate; active-afker immunity; 5-stack ceiling; 200-BURNIE + +2 saturating + Smited; shared counter; single cure clears both | ✓ SATISFIED | V61Smite 10/10 green; all revert legs assert no burn |
| TST-06 | 378-01/02/03/05 | NON-WIDENING by name vs `2bee6d6f` | ✓ SATISFIED | `live − UNION == ∅` independently recomputed |
| SEC-01 | 378-06 | RNG-freeze intact; no new player-manipulable VRF read | ✓ SATISFIED | V61RngFreezeIntact 6/6 green; two-block determinism + static premise confirmed |
| SEC-02 | 378-06 | SOLVENCY-01 re-attested (`claimablePool == Σ`, never exceeds `bal+stETH`) | ✓ SATISFIED | V61SolvencyAfpay 7/7 green; real-slot invariants 256×32768/0 reverts |

No orphaned requirements — every phase-378 requirement in REQUIREMENTS.md is declared in a plan's
`requirements` field and proven.

### Data-Flow Trace (Level 4)

Not applicable in the usual UI sense (test-only phase). The equivalent concern — "do the proofs read
REAL state vs a mirror that could drift green?" — was checked and PASSES:
- SEC-02 reads the real `balancesPacked` slot 7 and real `claimablePoolView()`; the handler creates
  balances only through real paired entrypoints. Confirmed in source.
- The class-(c) candidates and VRFPath invariants were traced to pre-existing roots (encoding-width
  mismatch / fixture-driver materialization / bucket-A fuzz variance), not v61 data-flow regressions.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all 8 V61 test files) | — | TODO/FIXME/XXX/TBD/HACK/PLACEHOLDER | none | ✓ Clean — zero debt markers |
| (all 8 V61 test files) | — | tautological / no-op assertions | none | ✓ 17–38 falsifiable assertions per file; exact-value anchors, by-contrast exemptions, non-vacuity guards, pre-burn balance checks |

### Skeptic Pass on the Hard-Floor Proofs (SEC-01, SEC-02) — genuinely falsifiable, not ceremonial

- **SEC-01 is genuinely falsifiable.** The two-block replay reverts to a byte-identical pre-state and
  perturbs exactly the entropy a VRF leak would consume (`prevrandao`/`coinbase`/`number`/`timestamp`),
  holding the legitimate `dailyIdx` staleness basis fixed. A real block-entropy read would diverge one
  of the tracked deltas and fail the byte-identity. Non-vacuity guards prove the waterfall actually
  ran. The static grep leg is complementary (with its own non-vacuity sanity) and its premise is
  independently true (no rngWord in the v61 region). 378-06-SUMMARY documents the inversion check
  (requiring divergence FAILED) — consistent with the design.
- **SEC-02 is genuinely falsifiable.** The invariant is computed from the real slot + real view (no
  mirror). The handler never fabricates a balance via vm.store, so the `claimablePool == Σ(halves)`
  identity is a real end-to-end property of the contract's call-site pairing (confirmed present at 6
  sites). 378-06-SUMMARY documents the inversion (a 1-wei unpaired-debit broke the identity).
- **One honest note (not a gap):** `V61Smite::testSmiteCannotExceedItsOwnCeiling` proves smite
  saturates at its OWN 10-point ceiling and explicitly delegates the 20-cap-saturation proof to
  `V61CurseSet::testFuzzStackingSaturatesAtCapNoWrap` (which is green). This is correct test
  decomposition (the smite ceiling means smite alone can never reach 20), honestly documented in the
  test, not a missing proof.

### Class-(c) Candidate Assessment (would any feed 379 as a contract bug?)

| Candidate | Judgment | Reason |
|-----------|----------|--------|
| C-1 `testFuzzTwoBlockOpenNoBlockEntropy` | NOT a contract bug | Afking-box `LootBoxOpened` does not materialize under the `_openAfkingBoxAt` FIXTURE driver (the stamp lands; the open leg is fixture-deferred). Identical root to two in-union carried siblings (both confirmed in the 172-name baseline union). Lootbox queue-then-materialize is USER by-design (MEMORY: `project_lootbox_delayed_finalization_intentional`, `lootbox-resolution-timing-by-design`). Came up GREEN in my run (fuzz variance) — reinforces non-determinism, not a bug. |
| C-2 gap-backfill fuzz variants | NOT a contract bug | TEST-side encoding-width mismatch: test computes `keccak256(abi.encodePacked(resumeWord, uint32(day)))`; contract derives `...uint24(gapDay)` (`DegenerusGameAdvanceModule.sol:1844`). The `uint24 gapDay` typing predates v61 (`c3e84b792`, before `b97a7a2e`); in-union siblings red @ baseline. The contract is internally consistent (uint24 field). Both variants GREEN in my run (fuzz variance). |

Neither class-(c) candidate is a contract bug. There is **nothing to feed 379 as a v61 finding** from
this phase's triage. (379 will still re-attest RNG-freeze + SOLVENCY-01 adversarially; these proofs
are its empirical backing.)

### Human Verification Required

None. Every must-have was empirically verifiable and verified programmatically:
- All 8 proving tests RUN green (foreground forge runs, exit 0).
- The non-widening gate recomputed BY NAME from raw full-suite output (`live − UNION == ∅`).
- The contract boundary checked via git (empty porcelain + tree-hash match) before and after.
- Falsifiability assessed by reading every proof's assertions and confirming the contract premises
  (claimablePool pairing present; no rngWord in the v61 curse/smite region).

### Gaps Summary

No gaps. The phase goal — "the milestone proven behaviorally correct + the hard floor proven
empirically vs `2bee6d6f`" — is achieved:

1. **Behaviorally correct:** TST-01..05 (54 tests) all green, each exercising real production code
   (`_settleShortfall`/accessors via the inherited-storage tester; live `purchase()`/`claimWinnings`/
   `smite`/`decurse`) with falsifiable assertions (exact values, by-contrast exemptions, pre-burn
   balance checks, non-vacuity guards) — not tautologies.
2. **Hard floor proven empirically:** SEC-01 (RNG-freeze, two-block determinism + true static premise)
   and SEC-02 (SOLVENCY-01, real-slot invariants 256×32768/0 reverts) both green and both genuinely
   falsifiable (inversions documented; premises confirmed in the contract).
3. **Non-widening vs `2bee6d6f`:** independently recomputed `live − UNION == ∅` BY NAME from a fresh
   full run; no V61 proving test is red; the only out-of-union concerns (class-(c) fuzz variants, 3
   VRFPath invariants) are pre-existing and in the union.
4. **Contract boundary intact:** byte-identical to HEAD (`87e3b45b...`), empty porcelain before and
   after all runs; no 378 commit touched any `contracts/*.sol`.

---

_Verified: 2026-06-07T11:36:33Z_
_Verifier: Claude (gsd-verifier)_
