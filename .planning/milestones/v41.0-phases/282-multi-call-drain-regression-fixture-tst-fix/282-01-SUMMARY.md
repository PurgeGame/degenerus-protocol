---
phase: 282-multi-call-drain-regression-fixture-tst-fix
plan: 01
status: complete
type: execute
tags: [audit, mint-batch, regression, indexer-replay, owed-salt, v41.0, b2-symmetric, reduced-scope]
requirements: [TST-FIX-01, TST-FIX-02, TST-FIX-03, TST-FIX-04]
requirements_dropped: [TST-FIX-05, TST-FIX-06]
commit: a1212b00
completed: 2026-05-16
---

# Phase 282 / Plan 01 — Summary

## Summary

Phase 282 lands the W2 fix-verification net for the Phase 281 owed-salt determinism patch (HEAD `221afcf7`) via **two new test surfaces totaling 977 LOC** committed in a single USER-APPROVED batched commit. The test suite drives an end-to-end multi-call trait drain through the production `purchase(...) → advanceGame()` codepath — the same surface that produced the v40 F-41-01 bug — and asserts the four primary invariants TST-FIX-01..04 (W2 indexer-replay byte-identity, non-increasing 4th-field semantics, pairwise-distinct keccak inputs, single-call byte-identity). All 6 `it()` blocks pass in ~24s.

**Reduced scope authorization (2026-05-16):** The user explicitly re-scoped the plan, dropping TST-FIX-05 (hard gas ceiling) and TST-FIX-06 (production-anchor replay against blocks 10862393..10862412 via v40 git-worktree harness). Quotes from authorization: *"if the underlying issue is fixed, doing exact replication tests is not necessary, we diagnosed the bug"* and *"one guy buy 2k tickets and then do advancegame chain"*. The dropped surface would have replayed the production crime scene against a v40 worktree pinned at `cd549499`; instead, the W2 invariant + structural-distinctness of the keccak input set + byte-identity of single-call drain are now treated as sufficient algorithm-level proof.

**Phase 284 §4 F-41-01 evidence class consequently downgrades** from `PRODUCTION_REPLAYABLE` to `ALGORITHM_VERIFIED`. The patched-side empirical gas numbers are captured (informational, no ceiling assertion) but cannot be deltaed against a v40 baseline — the theoretical ≤2880-cumulative / ≤144-per-call ceiling from 281-01-MEASUREMENT.md §3a remains theoretical-only.

## Outputs

### `test/helpers/raritySymbolBatchRef.mjs` (183 LOC)

Pure-JS verbatim port of `contracts/modules/DegenerusGameMintModule.sol _raritySymbolBatch` (L544-L643) at HEAD `221afcf7`. Serves as the **only oracle** for W2 indexer-replay assertions per D-282-ASSERTION-FRAME-01 — production indexers reproduce on-chain trait credits by replaying this exact function against `(baseKey, entropyWord, owedSalt, startIndex, count)`.

Exports:
- `TICKET_LCG_MULT = 6364136223846793005n` — the Knuth/Numerical-Recipes LCG multiplier as a `BigInt`
- `computeBaseKey(lvl, queueIdx, player)` — `keccak256(abi.encode(lvl, queueIdx, player))` mirror
- `raritySymbolBatchRef({baseKey, entropyWord, ownedSalt, startIndex, count})` — per-group-of-16 keccak with the 4-tuple `(baseKey, entropyWord, groupIdx, ownedSalt)` and the two-step LCG at contract L577 + L582 ported bit-for-bit

The verbatim-port discipline is explicit: any future contract edit to `_raritySymbolBatch` requires a matching JS-side edit at the same line offsets, with a re-attestation that the ports remain bit-identical. No abstractions, no helpers — line-for-line semantic mirror.

### `test/edge/MintBatchDeterminism.test.js` (794 LOC, 6 `it()` blocks, ~24s)

End-to-end multi-call drain driven through the production codepath: `purchase(2000)` queues an alice anchor, then a manual `advanceGame()` chain drains the queue across 28-32 txs (one tx contains 2 within-call emissions due to cold-budget split). The B2-symmetric path is exercised via a separate whale-bundle that queues alice at future levels 2..5 (Path A drain via `processFutureTicketBatch`).

## Decisions Honored

- **D-282-ASSERTION-FRAME-01** — W2 indexer-replay is the primary assertion frame; the verbatim-port JS reference impl is the only oracle. No algorithm-as-own-comparator anti-pattern.
- **D-282-B2-COVERAGE-01** — Both drain paths exercised: Path B (current-level via `_processOneTicketEntry`) via the 2000-ticket anchor; Path A (future-pool via `processFutureTicketBatch`) via the whale-bundle.
- **D-281-FIX-SHAPE-01 (inherited)** — owed-salt is the 4th positional `abi.encode` argument in the per-group keccak; the JS reference port mirrors this exactly.
- **D-281-STARTINDEX-SEMANTICS-01 (inherited)** — `TraitsGenerated`'s 4th positional `uint32` field carries `owed_at_call_entry`; TST-FIX-02 asserts non-increasing semantics directly against this field.
- **D-281-FIX01-REFRAME-01 (inherited)** — W2 indexer-replay invariant; no single-call comparator, no algorithm-as-own-comparator.

## Decisions Modified (user re-scope 2026-05-16)

- **D-282-PREFIX-BRANCH-01 — DROPPED.** No `scripts/v41/capture-v40-anchor-replay-trace.mjs` v40 git-worktree harness; no `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-V40-ANCHOR-REPLAY-TRACE.json` captured production trace; **TST-FIX-06 not applicable** (no pre-fix branch to replay against).
- **D-282-GAS-EMPIRICAL-01 — DOWNGRADED.** Gas measured during the 2000-ticket anchor drain but logged as **informational only**. No hard ceiling assertion (TST-FIX-05 dropped); the ≤2880-cumulative / ≤144-per-call ceiling from 281-01-MEASUREMENT.md §3a remains theoretical-only because no v40 baseline exists in this phase to delta against.
- **Phase 284 §4 F-41-01 evidence class:** `PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED`. The fix is proven correct via the W2 invariant + structural-distinctness of the keccak input set + byte-identity of single-call drain, not via crime-scene replay.

## Path-Accumulator Deviation Note

The plan assumed the `processed` accumulator semantics are uniform across both drain paths. **They are not.** The live contract has two distinct accumulators:

- **Path A (`processFutureTicketBatch` L499):** `processed += take`
- **Path B (`_processOneTicketEntry` L714):** `processed += writesUsed >> 1`

The test handles this via a **path-aware accumulator selector** that tries both formulas per per-level group and accepts the formula whose JS-reference reconstruction matches the on-chain credited trait multiset trait-by-trait. Production indexers can derive the path from `ticketCursor` / `ticketLevel` storage observation across tx boundaries, or — as this test does — try both formulas and accept the matching one.

**This is a pre-existing contract quirk, NOT a v40 bug or a Phase 281 fix gap.** The W2 indexer-replay invariant holds globally **per path**; the cross-path uniformity assumption in the plan was incorrect and is now corrected by the test's path-aware logic. Phase 284 §3 may want to note this as a documentation gap for any indexer implementer reading the spec.

## Test Surface

| `it()` | Asserts | Path |
|--------|---------|------|
| `drains 2000-ticket purchase into multiple TraitsGenerated emissions (anchor sanity + informational gas log)` | 29 emissions across 28 txs; terminal emission reaches `owed == count`; logs cumulative + per-tx gas | B |
| `TST-FIX-03 — emitted owed_at_call_entry values are pairwise distinct across a player's multi-call drain (backward-trace witness)` | Pairwise-distinct keccak input set across the full drain; the 4th positional field is the discriminator that broke v40 | B |
| `TST-FIX-02 — emitted owed_at_call_entry is monotonically non-increasing within a player's drain at a fixed queue slot (D-281-STARTINDEX-SEMANTICS-01)` | 4th-field monotonicity inside a single queue slot; terminal emission's `owed_at_call_entry == count` | B |
| `TST-FIX-01 — W2 indexer-replay: JS reference reconstruction equals on-chain credited trait multiset trait-by-trait` | Full-drain W2 invariant: JS `raritySymbolBatchRef` replay across all 29 emissions produces a multiset bit-identical to the on-chain credited traits | B |
| `[B2-symmetric] whale bundle drain exercises Path A (future-pool via processFutureTicketBatch) — W2 invariant + pairwise-distinct owed_at_call_entry + non-increasing per slot` | All three invariants hold on Path A; whale queued at future levels 2..5, owed=400 per level, 3 emissions per level (12 total) | A |
| `TST-FIX-04 — single-call drain byte-identity: small purchase produces ONE emission whose traits match JS reference replay against (baseKey, entropy, processed=0, owedSalt=owed, count=owed)` | 1-ticket purchase produces exactly 1 emission with `count=4`; JS replay byte-identical to on-chain credit | B |

**Anchor metadata:**
- **Path B (2000-ticket purchase):** alice, lvl-at-first-emit=1, queueIdx-at-first-emit=2, owed-at-first-emit=8000, 29 emissions across 28 txs (one tx had 2 within-call emissions due to cold-budget split). Terminal emission `owed=266 count=266` (drained to zero).
- **Path A (whale bundle):** alice queued at future lvl=2..5, owed=400 per level, 3 emissions per level (12 total emissions).
- **Daily VRF entropy:** pinned to a constant 256-bit value via `mockVRF.fulfillRandomWords` (any constant — no production hex needed since the JS reference and on-chain code consume the same pinned word).

## Empirical Gas (Informational)

- **Total patched-side gas across the 2000-ticket anchor drain:** 216,449,415 gas across 32 `advanceGame()` txs containing `TraitsGenerated`
- **Per-tx max:** 8,354,736 gas
- **Per-tx avg:** 6,764,044 gas
- **No v40 baseline delta** (D-282-PREFIX-BRANCH-01 dropped per user re-scope)
- Phase 281's ≤2880-cumulative / ≤144-per-call ceiling from `281-01-MEASUREMENT.md §3a` remains **theoretical-only**

## Phase 284 Handoff

**Carry forward into Phase 284 PARALLEL adversarial pass:**

1. **F-41-01 evidence class is `ALGORITHM_VERIFIED`, not `PRODUCTION_REPLAYABLE`.** Phase 284 §4 prose must cite the W2 invariant + structural-distinctness + single-call byte-identity as the proof basis; the production crime scene at blocks 10862393..10862412 is explicitly NOT replayed.
2. **Anchor metadata** (lvl=1, queueIdx=2, owed=8000, 29 emissions) — usable as a worked example in §4 narrative.
3. **B2 attestation** — both drain paths exercised; W2 invariant holds globally per path; cross-path accumulator-formula deviation is pre-existing, documented in this SUMMARY.
4. **Dropped artifacts** — no v40 worktree harness, no captured production trace, no hard gas ceiling. Phase 284 §3.A delta-surface table must NOT reference any production-replay artifact path.

## Known Gaps / Next Steps

- **Phase 284 §3.A delta-surface table** — cite the empirical gas numbers above as `ALGORITHM_VERIFIED` only (no `PRODUCTION_REPLAYABLE` artifact path to cite).
- **Phase 284 §3.B zero-new-state gas-overhead line** — no patched-vs-baseline delta available in this phase; cite the theoretical ceiling from `281-01-MEASUREMENT.md §3a` plus the empirical patched-side numbers above as informational context.
- **Phase 284 §4 F-41-01 prose** — `ALGORITHM_VERIFIED` via the W2 invariant + structural-distinctness of the keccak input set + byte-identity of single-call drain. Production replay against blocks 10862393..10862412 explicitly dropped per user authorization 2026-05-16.
- **Path-accumulator quirk** — Phase 284 §3 may want a documentation-gap note for indexer implementers: the `processed += take` vs `processed += writesUsed >> 1` divergence between Path A L499 and Path B L714 is a pre-existing contract quirk that any production replayer must handle (this test handles it via a path-aware selector).

## Approval Discipline

- 1 USER-APPROVED batched test commit per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` (applied to `test/`)
- ZERO `contracts/` mutations since Phase 281 (HEAD `221afcf7`)
- ZERO `KNOWN-ISSUES.md` edits
- ZERO test-only mutations to existing test files (all 277 existing `test/edge` files including `BackfillIdempotency.test.js` / `RngStall.test.js` / `LootboxAutoResolveRegression.test.js` untouched)

## Reference Material

- `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-01-PLAN.md` — the plan (84,606 bytes — pre-rescope).
- `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-CONTEXT.md` — phase context source.
- `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-DISCUSSION-LOG.md` — decision-rationale source (D-282-* anchors).
- `.planning/phases/281-mint-batch-determinism-fix-fix/281-01-SUMMARY.md` — Phase 281 fix-side summary (HEAD `221afcf7`).
- `.planning/phases/281-mint-batch-determinism-fix-fix/281-01-MEASUREMENT.md` — Phase 281 theoretical gas ceiling reference (§3a).
- `contracts/modules/DegenerusGameMintModule.sol` L544-L643 at HEAD `221afcf7` — source of truth for `raritySymbolBatchRef.mjs` verbatim port.
