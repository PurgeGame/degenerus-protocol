# Phase 348 — Deferred Items (out-of-scope discoveries)

Items discovered during 348 execution that are NOT in scope for this paper-only SPEC phase
(348 authors `.planning/` markdown only; touches ZERO `contracts/` and ZERO `test/`). Logged for
the owning phase, NOT fixed here.

| Item | Discovered during | Owner | Detail |
|---|---|---|---|
| Stale `AfKing.poolOf` test references | 348-02 Task 1 (`forge build`) | **v55 351 TST** | v54's de-custody (`20ca1f79`) deleted `AfKing.poolOf` (→ Game-side `afkingFundingOf`, `DegenerusGame.sol:1540`), but 5 test files still call `afKing.poolOf(...)`: `test/fuzz/AfKingConcurrency.t.sol` (`:516`), `AfKingSubscription.t.sol`, `AfKingFundingWaterfall.t.sol`, `KeeperNonBrick.t.sol`, `RedemptionStethFallback.t.sol`. Stale because v54.0 was CLOSED-as-superseded with **346 TST dropped** (STATE.md) → the suite was never re-synced to the de-custody. A bare `forge build`/`forge test` halts on this. **Workaround used at 348:** `forge build --sizes --skip "test/**" --skip "*.t.sol"` (contracts compile cleanly; the size measurement is unaffected). 351 TST owns re-syncing the AfKing test suite to the v55 in-Game subscriber surface (the `poolOf` reads become Game-side `afkingFundingOf` / in-context reads). |
