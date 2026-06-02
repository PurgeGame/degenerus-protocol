---
phase: 355-gas-measure-tune-per-buy-per-open-per-settle-marginals-accum
plan: 01
status: complete
contract_commit: 3b9df3fb
baseline_sha: 453f8073
---

# 355-01 SUMMARY — v56 gas-marginal measurement harness

## Self-Check: PASSED (with mid-execute re-scope, USER-directed)

## What landed

`test/gas/V56AfkingGasMarginal.t.sol` — the v56 per-buy / per-open / per-settle marginal harness on the
IMPL-applied tree, measuring every everyday-afking marginal via the loop-N-divide form (never a single-item
total) and the worst-case per-tx chunk for each batched loop with the dual bound (< 10M target / ≤ 16.7M
hard ceiling). Task-1 baseline harness committed `3b9df3fb`.

MEASURED (current tree, 5/5 green): per-buy lootbox **6,887**; per-buy ticket **54,279** (off the ~262k
`purchaseWith`); per-open afking box **70,200**; OPEN_BATCH=130 open chunk **9,288,591** (max-safe 140);
STAGE all-ticket chunk @ weight-budget 1000 **6,822,837** (max-safe budget 1464). GAS-02 proven: the
per-buy accrue is a warm in-slot SLOAD-mask-SSTORE, no new cold per-buy SSTORE.

## Mid-execute re-scope (USER, 2026-06-01)

The original plan was halted after Task 1 (`3b9df3fb` = the before-baseline). The USER re-scoped the GAS
phase (deferred-quest two-batch redesign + GAS-05 `pendingBurnie` accrual) — see
[[v56-deferred-quest-payout-two-batch-redesign]] and 355-02/355-03. The harness was finalized against the
re-scoped tree (the weighted SUB_STAGE budget + single-roll afking open).

## Requirements

GAS-01 (marginals measured under 16.7M) + GAS-02 (no new cold per-buy SSTORE) — empirically met by the harness.
