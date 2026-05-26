---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 08
status: held-for-hand-review
requirements: [BATCH-02]
files_modified: []
committed: false
---

# 326-08 VERIFY + HOLD — the ONE batched v48 contract diff, at the hand-review gate

## Build (authoritative, whole tree)
`forge build --sizes` → **0 errors**. Both at-risk contracts under EIP-170 (24,576 B):
- DegenerusGame **22,508 B** (margin 2,068 B) — SWAP relocated to a module freed ~1 KB vs the 23,535 B inline version.
- DegenerusGameMintModule **22,078 B** (margin 2,498 B) — absorbed the SWAP logic.
All other contracts comfortable. (USER raised the size concern mid-execution → SWAP moved to MintModule.)

## Test suite (no-NEW-breakage gate)
`forge test` → **594 succeeded / 42 failed** (total 636). The documented v47.0-closure baseline carried
~44 pre-existing failures, so the count did NOT increase → no net regression. Classification:
- **Pre-existing baseline (don't chase):** `VRFPathInvariants` (3 — gap-day/coordinator-swap/stall-recovery;
  VRF path, untouched by v48) + the carried VRF/baseline failures. v48 touched no VRF/Advance code.
- **KNOWN-TST-DEFERRED (HERO):** Degenerette payout-table tests fail because the byte-exact S∈{0..9}
  constants are intentional placeholders (S=8 = 0; packed = old M-indexed; WWXRP factors = old) that
  Phase 327's `derive_5_tables.py` byte-reproduces under PASS_ALL. NOT v48 regressions.
- **NEW v48 (class-c, must be 0):** none indicated (count ≤ baseline; clean compile). Full per-suite
  failing list captured separately for confirmation.

## BATCH-01 cross-item reconciliation joint-checks (per-plan greps; recorded in 326-01..07 SUMMARYs)
- R1 (RFALL): exactly ONE `pullRedemptionReserve`, SDGNRS-gated, pure-ETH-OR-pure-stETH, CHECKED; single `pendingRedemptionEthValue`. ✓
- R2 (KEEP): crank*/sweep purged from AfKing + DegenerusGame (grep 0); `bytes32("DGNRS")` wired, no `bytes32(0),payKind`, no `bytes32("VAULT")`. ✓
- R3 (SWAP): ONE `sellFarFutureTickets` (thin game wrapper → MintModule) + ONE `_removeFarFutureTickets`; inline CHECKED claimable debit to ≥1 ETH; no `pendingRedemptionEthValue`/daily-cap; jitter reads `rngWordByDay[currentDay-1]`; rngLocked-gated. ✓
- R4 (sStonk co-edit): RFALL item-2 comment + POOL receive()/burnAtGameOver/interface coexist; single tracker intact. ✓
- R5 (VAULT co-edit): `recoverAfKingPool()` + `gameSellFarFutureTickets` + `withdraw`/`poolOf`/`sellFarFutureTickets` interface entries; no conflict. ✓
- C-checks: PFIX `400 * 1 ether` (C1); affiliate at the game self-call not AfKing (C2); BTOMB checked-add + one-shot, not the :370 path (C4); HERO `FT_HERO_SHIFT`+`heroQuadrant>=4` kept, multiplier net-deleted (C5); `dailyHeroWagers`/`_rollHeroSymbol` untouched (C6); unit basis `priceForLevel(currentLevel)` not /4 (C8). ✓
- AfKing scope: item-3 sweep→autoBuy rename only; item-4 left it byte-unchanged. ✓
- No-arb: no band widened; ceiling 16.5%@d6 < ~21% acquisition (noted; SWAP-08 empirical proof is TST). ✓
- Samplers + JackpotModule byte-unchanged (swap-pop maintains membership⟺packed). ✓

## HOLD — nothing committed
Task 3 (`autonomous:false`, blocking-human) reached. The batched `contracts/*.sol` diff is HELD at the
commit boundary for the single USER hand-review (`git diff -- contracts/`). Commit only after explicit
approval (sanctioned `CONTRACTS_COMMIT_APPROVED=1` bypass), then the `.planning/` SUMMARYs follow.

## USER steers applied during execution (beyond the locked plan/SPEC — review)
1. SWAP ticket leg = normal recycled mint (suppression relaxed).
2. SWAP logic relocated to MintModule (EIP-170 headroom).
3. NEW `previewSellFarFutureTickets` quote view added (net-new surface).
