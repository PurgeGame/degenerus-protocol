---
phase: 291-mintcln-regression-fixture-tst-mintcln
status: passed
verified: 2026-05-17
verifier: orchestrator-inline (tight-scope test phase)
requirements_total: 5
requirements_verified: 5
requirements_failed: 0
---

# Phase 291 VERIFICATION

## Phase goal

Ship the TST-MINTCLN-01..05 regression fixture under `test/edge/` covering
the contract changes that landed in Phase 290 (audit-subject commit
`e5665117` — MINTCLN cleanup batch). Single USER-APPROVED batched test
commit; zero `contracts/` mutations.

**Result: passed.** Commit `a1404efd` shipped the fixture; 4 tests pass; all
5 requirements satisfied.

## Requirement traceability

| Req | Test name | Status |
|-----|-----------|--------|
| TST-MINTCLN-01 | `TST-MINTCLN-01 — multi-call drain trait-multiset equivalence …` | ✓ pass |
| TST-MINTCLN-02 | `TST-MINTCLN-02 — each emission decodes to (player, baseKey, take) …` | ✓ pass |
| TST-MINTCLN-03 | `TST-MINTCLN-03 anchor — whale-bundle drain emits TraitsGenerated at lvl=1 (Path B) AND at lvl>=2 (Path A) …` | ✓ pass |
| TST-MINTCLN-04 | `ticketsOwedPacked[rk][player] slot reads decode to …` (under sibling describe `TST-MINTCLN-04 — storage-layout regression at runtime`) | ✓ pass |
| TST-MINTCLN-05 | JSDoc header at the top of `test/edge/MintCleanupRegression.test.js` (no separate test case; satisfied structurally per plan and explicit per-test-mapping line in the header) | ✓ pass |

## Verification evidence

```
$ npx hardhat test test/edge/MintCleanupRegression.test.js
  MintCleanupRegression — Phase 291 v42.0 MINTCLN regression fixture
    TST-MINTCLN-01..04 — end-to-end whale-bundle multi-call drain via advanceGame()
      ✔ TST-MINTCLN-03 anchor … path-accumulator=A|B discrimination
      ✔ TST-MINTCLN-02 … (player, baseKey, take) 3-tuple decode … v42 topic-hash
      ✔ TST-MINTCLN-01 … v42 3-input JS-replay reconstructs on-chain credited multiset
    TST-MINTCLN-04 — storage-layout regression at runtime
      ✔ ticketsOwedPacked[rk][player] slot reads decode to the expected (rem | (owed<<8)) 40-bit packed form …
  4 passing (24s)
```

TST-MINTCLN-01 path-accumulator output (cross-call seed separation +
multiset equivalence at all 5 exercised levels):

```
[W2 lvl=1] num-emissions=31 | emitted-count-sum=8400 | on-chain=8400 | reconstructed=8400 | path-accumulator=B
[W2 lvl=2] num-emissions=3  | emitted-count-sum=400  | on-chain=400  | reconstructed=400  | path-accumulator=A
[W2 lvl=3] num-emissions=3  | emitted-count-sum=400  | on-chain=400  | reconstructed=400  | path-accumulator=A
[W2 lvl=4] num-emissions=3  | emitted-count-sum=400  | on-chain=400  | reconstructed=400  | path-accumulator=A
[W2 lvl=5] num-emissions=3  | emitted-count-sum=400  | on-chain=400  | reconstructed=400  | path-accumulator=A
```

TST-MINTCLN-04 storage-slot decode evidence (queued state, owed > 0 at all
5 exercised levels — validates the 40-bit packed-form layout against the
runtime `_tqWriteKey(lvl)` outer-mapping key):

```
[TST-MINTCLN-04 storage-slot lvl=1 path=B rk=0x1 slot=…413 packed=0x20d000 rem=0 owed=8400]
[TST-MINTCLN-04 storage-slot lvl=2 path=A rk=0x2 slot=…6d3 packed=0x019000 rem=0 owed=400]
[TST-MINTCLN-04 storage-slot lvl=3 path=A rk=0x3 slot=…f35 packed=0x019000 rem=0 owed=400]
[TST-MINTCLN-04 storage-slot lvl=4 path=A rk=0x4 slot=…047 packed=0x019000 rem=0 owed=400]
[TST-MINTCLN-04 storage-slot lvl=5 path=A rk=0x5 slot=…38f packed=0x019000 rem=0 owed=400]
```

`forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage
storage-layout` confirms `ticketsOwedPacked` at slot 13 (BLK-2 lock honored).

## Must-haves cross-check

- ✓ Phase 290 audit-subject commit `e5665117` is the regression target.
- ✓ Zero `contracts/` mutations (`git diff --name-only HEAD~1 HEAD -- contracts/` empty).
- ✓ Phase 282 `MintBatchDeterminism.test.js` UNTOUCHED at v41-closure HEAD
  (`git diff --name-only HEAD~1 HEAD -- test/edge/MintBatchDeterminism.test.js` empty).
  NB: that fixture's pre-existing broken state (since Phase 290 `e5665117`
  changed the event signature; verified via stash round-trip during Plan 01)
  is documented in `291-01-SUMMARY.md` and surfaced at the USER-APPROVED
  checkpoint — out of scope for Phase 291; ship-or-document decision deferred
  to user.
- ✓ Single USER-APPROVED batched commit (`a1404efd`) ships both Plan 01 +
  Plan 02 deliverables in one diff.
- ✓ D-291-GAS-01 SKIP-GAS posture honored — strictly zero `gas` tokens in
  code lines of either deliverable.
- ✓ JSDoc header (TST-MINTCLN-05) cites both topic hashes + both anchor IDs
  + Phase 297 §9 forward-cite.

## Cross-phase regression check

`npx hardhat test test/edge/MintCleanupRegression.test.js test/edge/HeroOverrideDayIndex.test.js test/edge/BackfillIdempotency.test.js`
→ 14 passing. No regressions in prior-phase fixtures sampled. Phase 282's
fixture remains in its pre-Phase-291 broken state (Phase 290 inheritance,
not a Phase 291 regression).

## Disposition

Phase 291 GOAL ACHIEVED. Ready for roadmap mark-complete.
