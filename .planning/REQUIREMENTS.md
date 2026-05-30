# Requirements: Degenerus Protocol — v54.0 Game-Side Keeper-Funding Ledger + AfKing De-Custody

**Milestone:** v54.0 (started 2026-05-30)
**Audit baseline → subject:** v53 HEAD `83a84431` (the atomic `BatchBuy[]` batchPurchase) → v54.0 closure HEAD. Every cited `file:line` MUST be re-attested vs the v53 HEAD before any patch. Supersedes v53's cross-contract value-plumbing (v53's atomic `BatchBuy[]` shape KEPT; only the funding location changes).
**Scope source:** the design-locked doc `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` (SPEC source of truth) + the milestone init (2026-05-30) + USER additions (dead-code cleanup + further gas optimization). No research (a fully-specced internal contract refactor).
**Posture:** the ledger + de-custody + cleanup ship as ONE batched USER-APPROVED `contracts/*.sol` diff; HARD STOP at the commit boundary (`feedback_batch_contract_approval` / `feedback_never_preapprove_contracts` / `feedback_no_contract_commits`); `ContractAddresses.sol` freely modifiable. **Security/solvency floor over gas** (`feedback_security_over_gas`): the keeper bucket rides inside `claimablePool` (no new reserved aggregate) → it inherits the already-correct solvency wiring; the master invariant `balance + steth.balanceOf(this) >= claimablePool` is re-proven, not assumed. Pre-launch redeploy-fresh (storage break fine, no migration; no live AfKing pools).

---

## v54.0 Requirements

### Game-Side keeperFunding Ledger (LEDGER)
- [ ] **LEDGER-01**: A new per-player `mapping(address => uint256) keeperFunding` exists on the Game (`DegenerusGameStorage.sol`), segregated from `claimableWinnings` — no human-purchase path, no `_settleClaimableShortfall`, no claim path reads it (except the post-gameOver merge, GAMEOVER-01). Only the AF_KING-gated `batchPurchase` may spend it.
- [ ] **LEDGER-02**: `keeperFunding` has NO separate aggregate — its systemwide total rides inside the existing `claimablePool`. Every `keeperFunding` mutation (deposit / withdraw / auto-buy spend / gameOver claim) moves `claimablePool` in tandem, so `claimablePool == Σ claimableWinnings[*] + Σ keeperFunding[*]`. The storage invariant comment (`DegenerusGameStorage.sol:344-352` + `DegenerusGame.sol:18`) is updated to name the keeper component (the existing invariant is already stated as `>=`, so this is consistent).
- [ ] **LEDGER-03**: `depositKeeperFunding(address player) external payable` credits `keeperFunding[player] += msg.value` AND `claimablePool += msg.value` (reverts on `player == address(0)`, zero-value no-op, emits `KeeperFunded`). The Game's bare `receive()` (which routes to the prize pool) is NOT used for keeper deposits.
- [ ] **LEDGER-04**: `withdrawKeeperFunding(uint256 amount) external` is un-brickable (strict CEI — debit `keeperFunding[msg.sender]` + `claimablePool` BEFORE the `.call`, so a re-entrant second call reverts on the debit), available ALWAYS (mid-game, after cancel, post-gameOver), reverts on `amount > balance`, zero-value no-op, emits `KeeperWithdrew`. Inherits the USER-locked "cancel-then-withdraw always succeeds / never strands ETH" invariant.
- [ ] **LEDGER-05**: `keeperFundingOf(address) external view returns (uint256)` exposes the per-player balance (the aggregate is just `claimablePool`).

### Non-Payable Batched Auto-Buy (AUTOBUY)
- [ ] **AUTOBUY-01**: `batchPurchase(BatchBuy[] calldata buys)` is NON-payable (the `payable` modifier + the `spent == msg.value` exact-funding guard are removed). It stays AF_KING-gated, `!gameOver`-pre-checked, `len != 0`.
- [ ] **AUTOBUY-02**: Per slice, `batchPurchase` debits `keeperFunding[b.player] -= b.ethValue` AND `claimablePool -= b.ethValue` (revert if `keeperFunding[b.player] < ethValue`), then delegatecalls `purchaseWith(b.player, …, b.ethValue)` — the ETH is already in the Game's balance, so it becomes prize-pool / vault-share ETH exactly as a fresh `msg.value` buy. `_purchaseForWith` / `purchaseWith` / `_settleClaimableShortfall` are UNCHANGED.
- [ ] **AUTOBUY-03**: Keeper buys earn the **fresh** affiliate rate (20-25%, `isFreshEth=true`), NOT the recycled 5% — because the keeper ETH is spent as `ethValue` (DirectEth), preserving the fresh/recycled labeling. No affiliate-bonus rework (PLAN-V54 §10).
- [ ] **AUTOBUY-04**: Atomic non-brick is preserved — a reverting slice rolls back the WHOLE batch (no per-slice try/catch), which is benign because `advanceGame()` is an independent permissionless entrypoint (the game never freezes; subscribers retry next cycle).
- [ ] **AUTOBUY-05**: AfKing's funding-skip gate reads `keeperFunding[src]` from the Game via an EXTENDED `keeperSnapshot` (ONE staticcall per player — GASOPT-03 preserved); the two-tier branching (VAULT/SDGNRS exempt-skip reason 3; NORMAL sub auto-pause reason 1) is byte-identical; the local CEI debit `_poolOf[src] -= ethValue` (`AfKing.sol:719`) is removed; `GAME.batchPurchase{value: totalValue}(buys)` becomes the non-value `GAME.batchPurchase(buys)`.

### AfKing De-Custody (DECUSTODY)
- [ ] **DECUSTODY-01**: AfKing holds NO ETH — `_poolOf` (slot 0), `receive()`, `deposit()`, `depositFor()`, `withdraw()` (`AfKing.sol:214,298-341`) are deleted; the `sum(_poolOf) <= address(this).balance` invariant is retired; `poolOf(player)` delegates to `game.keeperFundingOf(player)` (or is removed).
- [ ] **DECUSTODY-02**: `subscribe` stays `payable` and FORWARDS `msg.value` → `game.depositKeeperFunding{value}(subscriber)` (Decision A2) — AfKing never retains ETH. Standalone top-ups go directly to `game.depositKeeperFunding`.
- [ ] **DECUSTODY-03**: The OPEN-E `fundingSource` storage + the subscribe-time operator-approval consent gate (`AfKing.sol:400-409`) + the `src` resolution (`:682`) are UNCHANGED; the 4-protection OPEN-E disposition (`open-e-operator-approval-trust-boundary`) carries over verbatim (funding-source ETH is now `keeperFunding[src]`, withdrawable by the source via `withdrawKeeperFunding`).
- [ ] **DECUSTODY-04**: The now-moot v48 stuck-pool recovery is removed — `DegenerusVault.recoverAfKingPool()` (`Vault:512`), the `StakedStonk.burnAtGameOver()` AfKing-withdraw leg (`StakedStonk:533`), and the AfKing `receive()` AF_KING relaxation — confirmed dead by the de-custody (VAULT/sDGNRS funding is now game-side `keeperFunding`, withdrawable directly).

### Unified Terminal Claim (GAMEOVER)
- [ ] **GAMEOVER-01**: Post-gameOver, `claimWinnings` (`_claimWinningsInternal`, `DegenerusGame.sol:1471`) ALSO pays the caller's `keeperFunding` (lazy per-player merge — no unbounded loop): payout = `claimableWinnings[caller] + keeperFunding[caller]`, zeroing both and debiting `claimablePool` for the combined amount. `withdrawKeeperFunding` remains available too (both zero the bucket → no double-spend).
- [ ] **GAMEOVER-02**: The final sweep (`GameOverModule:215`, 30 days post-end) sweeps the keeper reservation with `claimablePool` (same forfeiture lifecycle — keeperFunding is claimable-equivalent post-gameOver). Both withdraw/claim paths stay open until that sweep.

### Solvency Spine (SOLVENCY)
- [ ] **SOLVENCY-01**: PROVEN (not assumed) at SPEC: because the keeper total rides inside `claimablePool`, every "free ETH = totalBal − reserved" site already reserves it with NO change — `distributeYieldSurplus` (`:691-707`, the prior-omission site [[project_yield_surplus_omits_pending_pools]], now structurally immune), the gameOver drain (`:98-99/:164`), and `adminStakeEthForStEth` (`:2113-2123`, keeper ETH never staked-away). The SPEC attests each reserves `claimablePool` (inclusive of keeper) unchanged.
- [ ] **SOLVENCY-02**: The master invariant `balance + steth.balanceOf(this) >= claimablePool` (with `claimablePool` now including the keeper total) holds across the full lifecycle — deposit → autobuy → withdraw → `distributeYieldSurplus` → gameOver-drain → claim → final-sweep — proven by test.
- [ ] **SOLVENCY-03**: The sDGNRS redemption valuation (`StakedStonk:612/772/861`, `ethBal + stethBal + claimableEth − pendingRedemptionEthValue`) is UNCHANGED and CORRECT — keeper ETH lives in the Game's balance (not sDGNRS's), invisible to sDGNRS's own-balance valuation (same as the external AfKing pool today); attested at SPEC.

### Dead-Code Cleanup (CLEANUP)
- [ ] **CLEANUP-01**: SPEC produces a dead-code inventory of everything the de-custody orphans (the AfKing ETH entrypoints / `_poolOf`, the v48 recovery, any now-unused helpers / events / errors / constants, the `IGame.batchPurchase` payable ABI, stale `_poolOf`-referencing comments) — each with a grep-attested kill-set vs the v53 HEAD.
- [ ] **CLEANUP-02**: Every item in the CLEANUP-01 inventory is removed in the batched diff with the kill-set grep-confirmed empty; no orphaned references remain (forge build clean).
- [ ] **CLEANUP-03**: A broader unused-code audit across the keeper/funding blast radius + adjacent surface (a gas-scavenger dead-code pass beyond the de-custody orphans) — anything found is removed (gas-skeptic-validated) or documented NEGATIVE with reasoning.

### Further Gas Optimization (GAS)
- [ ] **GAS-01**: SPEC produces a gas-opportunity inventory for the keeper/funding blast radius (beyond the ~9k/buy already saved by removing the per-batch value call), each tagged behavior-identical / same-results.
- [ ] **GAS-02**: The validated behavior-identical, no-cost gas wins from GAS-01 (gas-scavenger → gas-skeptic, under the security-over-gas floor) are applied; each is gas-only and proven same-results in TST. Wins that trade an invariant or aren't real are REJECTED with reasoning (do not re-litigate).
- [ ] **GAS-03**: The `claimableWinnings` packing candidate (`{uint128 normal, uint128 keeper}` instead of a separate `keeperFunding` mapping) is EVALUATED by gas-skeptic against the security floor — landing as an ISOLATED change only if the slot/gas saving survives the blast-radius cost on the central accounting variable (~15+ access sites); otherwise documented NEGATIVE (PLAN-V54 §2 deferral). Default expectation: keep the separate mapping (hot-path-neutral; large spine refactor).

### Test Proofs (TST)
- [ ] **TST-01**: Deposit/withdraw — `depositKeeperFunding` credits `keeperFunding` + `claimablePool`; `withdrawKeeperFunding` is un-brickable (re-entrant double-withdraw reverts on the debit; pool fully restored), drains to zero, never strands ETH (fuzz any pool / partial-withdraw), and works mid-game + post-cancel + post-gameOver.
- [ ] **TST-02**: Auto-buy with zero value transfer — `batchPurchase(buys)` (no value) debits each slice's `keeperFunding` + `claimablePool` by `ethValue`, lands the buy (ticket or lootbox per `isTicket`), draws claimable for the Combined/Claimable remainder (the v52 Finding A/B regressions — ticket-mode buys tickets, claimable funding is actually drawn), and reverts the WHOLE batch atomically on a poisoned slice (no partial landing); the game stays un-bricked via `advanceGame()`.
- [ ] **TST-03**: Fresh affiliate rate — a keeper buy credits the affiliate at the FRESH rate (20-25%, `isFreshEth=true`), not the recycled 5% — proving keeper-funded ETH is labeled fresh.
- [ ] **TST-04**: Solvency reservation — `distributeYieldSurplus` / `adminStakeEthForStEth` / the gameOver-drain never spend reserved keeper ETH (a yield-surplus run with outstanding `keeperFunding` distributes 0 of it; a stake call cannot stake below the keeper reserve).
- [ ] **TST-05**: Terminal claim merge — post-gameOver `claimWinnings` pays `claimableWinnings + keeperFunding` in one call (both zeroed, `claimablePool` debited by the sum); the final sweep zeroes the keeper reservation; no double-spend vs `withdrawKeeperFunding`.
- [ ] **TST-06**: NON-WIDENING regression vs the v53 baseline — the reconceived keeper suite (`KeeperNonBrick`, `KeeperBatchAffiliateDeltaAudit`, the 3 `test/gas/*`) compiles + passes against the ledger model; net-zero new regression (any pre-existing reds enumerated BY NAME); no test asserts strict `claimablePool == Σ claimableWinnings` across a keeper op. Baseline → `REGRESSION-BASELINE-v54.md`.

### Cross-Cutting — SPEC + IMPL + TERMINAL (BATCH)
- [ ] **BATCH-01**: SPEC design-lock (343) — re-attest the PLAN-V54 design vs the v53 HEAD (every `file:line`); lock the final `batchPurchase` / `purchaseWith` / extended `keeperSnapshot` signatures + the `keeperFunding` storage shape + the deposit/withdraw/claim-merge wiring; produce the SOLVENCY-01/03 proofs + the CLEANUP-01 + GAS-01 inventories; confirm the OPEN-E carry-over. ZERO `contracts/*.sol` mutation at SPEC.
- [ ] **BATCH-02**: IMPL (344) — the ONE batched USER-APPROVED `contracts/*.sol` diff (ledger + de-custody + the CLEANUP-02 orphan removal); HARD STOP at the contract-commit boundary (applied + locally compiled, never committed without explicit user hand-review); forge build clean.
- [ ] **BATCH-03**: TERMINAL (347) — delta-audit (every v54 surface NON-WIDENING vs v53; the master invariant + OPEN-E re-attested) + the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) focused on the funding-ledger + de-custody surface + `audit/FINDINGS-v54.0.md` (chmod 444) + atomic 5-doc closure flip.

---

## Future Requirements (deferred)
- Generalized "any operator-approved party may spend my `claimableWinnings`" (larger blast radius; PLAN-V54 §10).
- The `claimableWinnings` packing optimization if GAS-03 lands NEGATIVE this milestone (revisit only with a measured win).

## Out of Scope
- The v52 consolidated cross-model audit (separate track; v54's surface folds into it).
- Off-chain indexer / webpage (separate frontend track).
- Any contract surface beyond the keeper-funding ledger, AfKing de-custody, and the gas/cleanup sweep.
- The v44 §9d 135-anchor maximalist register (carries forward unchanged; NOT live vectors).

## Traceability
| REQ-ID | Phase | Status |
|--------|-------|--------|
| _(filled by the roadmapper — phase ↔ requirement mapping)_ | | |
