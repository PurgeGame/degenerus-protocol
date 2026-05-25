# Phase 323 — Deferred Items (out-of-scope, pre-existing v46)

Discovered while running the hardhat suite for 323-02. These are PRE-EXISTING v46-baseline
test-vs-contract mismatches (verified by running the same file at the v46 closure HEAD
`16e9668a` in a throwaway worktree). They are NOT v47-deltas and are out of 323-02's
non-widening repair scope. Logged, not fixed.

## test/unit/DegenerusVault.test.js — 2 pre-existing failures

- `gameSetAutoRebuy reverts when caller is not vault owner` — `vault.gameSetAutoRebuy is not a function`
- `gameSetAutoRebuyTakeProfit accessible by vault owner` — `vault.gameSetAutoRebuyTakeProfit is not a function`

Both functions exist in NEITHER the v46 nor the v47 `DegenerusVault.sol` (the legacy
ETH-auto-rebuy surface was removed in v46.0's "Legacy AFKing/ETH-Auto-Rebuy Removal"),
but the test still references them. Confirmed FAILING at v46 closure HEAD (47 pass / 2 fail
there; the same 2 failures). Non-widening at v47. A future test-hygiene pass should remove
or retarget these 2 `it()` blocks; out of scope for the v47-delta repair.

## test/gas/Phase268GasRegression.test.js — 1 pre-existing failure

- `v37.0 SURF-06 — advanceGame STAGE_PURCHASE_DAILY gas within ±2K of v36.0 baseline`:
  measured ~693_858 gas vs the stale pinned `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320`
  (a v36.0 baseline). Drift ~214K.

Confirmed FAILING at v46 closure HEAD with a near-identical measurement (693_459 vs the same
908_320 REF, drift 214_861). The v47 vs v46 measurement differs by ~400 gas (codegen noise),
so this is NOT a v47 regression — it is a stale gas-baseline pin that was already drifting at
v46, on the `advanceGame` stage-6 path (NOT the Degenerette spin-cap path 323-02 edited). A
future gas-hygiene pass should re-pin or retire the v36.0 baseline; out of scope here.

(The file's 1 `pending` is the SURF-06 worst-case Degenerette spin test soft-skipping because
`WORST_CASE_RNG_WORDS` is unpinned and the inline brute-force budget is exhausted — the
documented REF-CAPTURE soft-skip, expected, not a failure.)

## Shared-fixture note (FIXED in 323-02, recorded for traceability)

`test/helpers/deployFixture.js` `getConstructorArgs` returned `[]` for the `AF_KING` key
even though `AfKing` has a 3-arg constructor (inserted into DEPLOY_ORDER at Phase 318,
v46). This bricked EVERY fixture-based hardhat test (deploy threw "incorrect number of
arguments to constructor") at BOTH v46 and v47 — a pre-existing v46 break. Because it blocks
the entire in-scope hardhat suite from running, 323-02 applied the one-line fix (supply the
same 3 args the foundry helper `test/fuzz/helpers/DeployProtocol.sol:126` uses). This is a
test-helper-only repair; no contract change.
