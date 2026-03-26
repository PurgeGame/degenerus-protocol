# Requirements: Degenerus Protocol v6.0

**Defined:** 2026-03-25
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v6.0 Requirements

Requirements for Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity milestone.

### Test Suite Cleanup

- [x] **TEST-01**: All 14 failing Foundry tests either fixed or intentionally deleted with justification
- [x] **TEST-02**: `forge test` achieves 100% pass rate (green baseline)
- [ ] **TEST-03**: `npx hardhat test` achieves 100% pass rate (green baseline)
- [ ] **TEST-04**: LCOV coverage report generated for both suites documenting per-contract line coverage

### Contract Fixes

- [x] **FIX-01**: `lastLootboxRngWord` storage variable deprecated (slot preserved, 3 writes deleted, 1 read redirected to `lootboxRngWordByIndex[lootboxRngIndex - 1]`)
- [ ] **FIX-02**: Double `_getFuturePrizePool()` SLOAD eliminated in earlybird and early-burn paths (cache first read, reuse local)
- [ ] **FIX-03**: `RewardJackpotsSettled` event emits post-reconciliation value (`futurePoolLocal + rebuyDelta`)
- [ ] **FIX-04**: Degenerette ETH resolution succeeds during `prizePoolFrozen` via pending pool routing through `_setPendingPools`
- [x] **FIX-05**: BitPackingLib NatSpec corrected ("bits 152-154" to "bits 152-153")
- [x] **FIX-06**: Deity boon application checks existing tier and does not downgrade any boon type
- [x] **FIX-07**: `advanceBounty` computed at payout time using current price and escalation multiplier (3 locations)
- [x] **FIX-08**: Delta audit proves `lootboxRngWordByIndex[lootboxRngIndex - 1]` returns the identical value as `lastLootboxRngWord` in every code path (normal VRF, mid-day, stall backfill, coordinator swap, game-over fallback)

### DegenerusCharity Contract

- [ ] **CHAR-01**: `DegenerusCharity.sol` deployed as standalone contract at nonce N+23
- [ ] **CHAR-02**: Soulbound GNRUS token (name="Degenerus Charity", symbol="GNRUS", 18 decimals, no transfer/transferFrom/approve) with 1T supply minted to contract
- [ ] **CHAR-03**: Proportional burn-for-ETH/stETH redemption (`amount/totalSupply` share of both assets)
- [ ] **CHAR-04**: Per-level sDGNRS-weighted governance (propose, vote, resolveLevel)
- [ ] **CHAR-05**: `ContractAddresses.sol` updated with CHARITY address constant
- [ ] **CHAR-06**: Deploy pipeline updated (predictAddresses.js, patchForFoundry.js, DeployProtocol.sol)
- [ ] **CHAR-07**: DeployCanary.t.sol passes with new CHARITY address prediction

### Game Integration

- [ ] **INTG-01**: `_distributeYieldSurplus` routes charity share (2300 BPS) via `_addClaimableEth(CHARITY, ...)`
- [ ] **INTG-02**: `resolveLevel` hook in `_finalizeRngRequest` with try/catch and explicit gas cap
- [ ] **INTG-03**: CHARITY added to `claimWinningsStethFirst` allowlist in DegenerusGame
- [ ] **INTG-04**: `claimYield()` permissionless function on DegenerusCharity pulls accumulated yield

### Test Suite Pruning

- [ ] **PRUNE-01**: Redundancy audit identifies duplicate coverage across Foundry/Hardhat suites with justification
- [ ] **PRUNE-02**: Redundant tests deleted
- [ ] **PRUNE-03**: No coverage gaps introduced (LCOV before/after comparison shows zero lost lines)
- [ ] **PRUNE-04**: Final green baseline established for both suites with documented pass/fail counts

## Future Requirements

Deferred to subsequent milestones.

### Formal Verification

- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)

## Out of Scope

| Feature | Reason |
|---------|--------|
| OpenZeppelin ERC20/Governor for CHARITY | Protocol uses custom implementations; OZ imports unused transfer surfaces |
| wstETH integration | Protocol committed to rebasing stETH; mixing wstETH creates two Lido patterns |
| Automated cross-framework test deduplication | No tool compares Hardhat JS to Foundry Solidity semantics; LCOV manual comparison |
| OZ 5.6.x upgrade | Breaking Strings changes with zero benefit for this milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TEST-01 | Phase 120 | Complete |
| TEST-02 | Phase 120 | Complete |
| TEST-03 | Phase 120 | Pending |
| TEST-04 | Phase 120 | Pending |
| FIX-01 | Phase 121 | Complete |
| FIX-02 | Phase 121 | Pending |
| FIX-03 | Phase 121 | Pending |
| FIX-04 | Phase 122 | Pending |
| FIX-05 | Phase 121 | Complete |
| FIX-06 | Phase 121 | Complete |
| FIX-07 | Phase 121 | Complete |
| FIX-08 | Phase 121 | Complete |
| CHAR-01 | Phase 123 | Pending |
| CHAR-02 | Phase 123 | Pending |
| CHAR-03 | Phase 123 | Pending |
| CHAR-04 | Phase 123 | Pending |
| CHAR-05 | Phase 123 | Pending |
| CHAR-06 | Phase 123 | Pending |
| CHAR-07 | Phase 123 | Pending |
| INTG-01 | Phase 124 | Pending |
| INTG-02 | Phase 124 | Pending |
| INTG-03 | Phase 124 | Pending |
| INTG-04 | Phase 124 | Pending |
| PRUNE-01 | Phase 125 | Pending |
| PRUNE-02 | Phase 125 | Pending |
| PRUNE-03 | Phase 125 | Pending |
| PRUNE-04 | Phase 125 | Pending |

**Coverage:**
- v6.0 requirements: 27 total
- Mapped to phases: 27
- Unmapped: 0

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation*
