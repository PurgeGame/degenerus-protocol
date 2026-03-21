# Degenerus Protocol -- Security Audit Report

**Audit Date:** February--March 2026
**Auditor:** Claude (AI-assisted security analysis, Claude Opus 4.6)
**Scope:** 14 core contracts + 10 delegatecall modules (24 deployable) + 7 libraries + 3 shared abstract contracts (~25,300 lines Solidity)
**Solidity:** 0.8.34 (ContractAddresses: ^0.8.26), viaIR enabled, optimizer runs=200

---

## Executive Summary

**Overall Assessment: SOUND. No open findings.**

No code path allows unauthorized extraction of ETH or tokens. Accounting invariants hold at all 15 claimablePool mutation sites. CEI is correctly implemented at all 48 state-changing entry points. All 46 delegatecall sites use a uniform safe pattern.

All findings identified during the audit have been resolved. v3.3 identified four findings in the gambling burn redemption system (three High, one Medium) -- all fixed in code. v3.4 audited the futurepool skim redesign and 50/50 redemption lootbox split -- no High, Medium, or Low findings. Five INFO-level documentation notes remain (bit-field overlap comments, rounding dust, uint96 headroom). Four Low-severity issues from earlier milestones were also fixed (CEI ordering, proposal count overflow, spam-propose griefing, dead code removal). No open findings remain.

**Key Strengths:**
1. **VRF integrity.** Chainlink VRF V2.5 sole randomness source. Lock semantics prevent manipulation. Zero MEV extractable value.
2. **CEI throughout.** All 48 state-changing entry points safe against reentrancy. No `ReentrancyGuard` needed.
3. **Delegatecall safety.** All 46 sites use uniform safe pattern with zero deviations.
4. **Tight accounting.** BPS remainder pattern provably wei-exact. stETH rounding strengthens solvency invariant.
5. **Economic robustness.** Sybil, activity score inflation, affiliate extraction, and MEV vectors all structurally unprofitable.

---

## Findings

**No open findings.** All issues identified during the audit were resolved in code.

### v3.3 Findings (Gambling Burn Redemption System)

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| CP-08 | HIGH | `_deterministicBurnFrom` missing pending redemption deduction | FIXED |
| CP-06 | HIGH | `_gameOverEntropy` missing `resolveRedemptionPeriod` call | FIXED |
| Seam-1 | HIGH | `DGNRS.burn()` orphans gambling claim under contract address | FIXED |
| CP-07 | MEDIUM | Coinflip dependency blocks ETH claim at game boundary | FIXED |

**CP-08 (HIGH -- FIXED):** `_deterministicBurnFrom` did not subtract `pendingRedemptionEthValue` and `pendingRedemptionBurnie` from the total reserves before computing proportional share. Post-gameOver burns could double-spend ETH/BURNIE already reserved for pending gambling claims. Fix: deduct pending reserves in both `totalMoney` and `totalBurnie` calculations (StakedDegenerusStonk.sol).

**CP-06 (HIGH -- FIXED):** `_gameOverEntropy` in DegenerusGameAdvanceModule.sol did not call `resolveRedemptionPeriod()`, permanently stranding any gambling burn claims pending at game-over. Fix: added redemption resolution blocks to both VRF and fallback paths in `_gameOverEntropy`, mirroring `rngGate`.

**Seam-1 (HIGH -- FIXED):** `DGNRS.burn()` during active game submitted a gambling claim recorded under the DGNRS contract address (not the actual user). The claim could never be claimed, trapping the user's share of backing. Fix: `DegenerusStonk.burn()` reverts with `GameNotOver()` during active game. Users must use `burnWrapped()` which correctly routes through sDGNRS.

**CP-07 (MEDIUM -- FIXED):** `claimRedemption()` required full coinflip resolution before paying any portion. If the coinflip for a period hadn't resolved yet, both ETH and BURNIE were stuck. Fix: split claim -- ETH is always claimable once the period is resolved; BURNIE payout is conditional on coinflip resolution (paid on win, forfeited on loss, deferred if unresolved).

### v3.4 Findings (Skim Redesign + Redemption Lootbox)

No High, Medium, or Low findings. Five INFO-level notes documented in `v3.4-findings-consolidated.md`:

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| F-50-01 | INFO | Additive random uses full 256-bit modulo (not bit-isolated) | DOCUMENTED |
| F-50-02 | INFO | roll1/roll2 share bits [192:255] (independent via modulo) | DOCUMENTED |
| F-50-03 | INFO | Level-1 test uses unreachable lastPool=0 | DOCUMENTED |
| F-51-01 | INFO | Rounding dust in pendingRedemptionEthValue (negligible) | DOCUMENTED |
| F-51-02 | INFO | burnieOwed uint96 cast safe under realistic economics | DOCUMENTED |

REDM-06-A (originally flagged MEDIUM: unchecked subtraction in `resolveRedemptionLootbox`) was downgraded to false positive. The drain path (`_deterministicBurnFrom` → `claimWinnings`) only executes at gameOver; lootbox resolution only executes during active game. The paths are mutually exclusive.

---

## External Dependencies

The protocol depends on two external systems. Neither dependency creates a vulnerability -- the protocol remains solvent if either fails.

**Chainlink VRF V2.5.** Sole randomness source. If VRF goes down, the game stalls but no funds are at risk. A governance mechanism (propose/vote/execute with sDGNRS-weighted community approval) allows VRF coordinator rotation during extended stalls. The governance threshold decays over time to prevent permanent lockout. Execution requires approve weight to exceed reject weight and meet the threshold -- reject voters holding more sDGNRS than approvers block the proposal.

**Lido stETH.** Prize pool growth depends on staking yield. If yield goes to zero, the positive-sum margin disappears but the solvency invariant (`balance + stETH >= claimablePool`) does not depend on yield. If stETH transfers were ever paused, player claims that require stETH (when ETH balance alone is less than claimable, such as at termination) would also be blocked until transfers resume. This is not a realistic concern -- Lido is the largest DeFi protocol by TVL and has never paused transfers.

---

## Risk Assessment

| Risk Area | Rating | Justification |
|-----------|--------|---------------|
| Fund Loss | **Very Low** | No unauthorized extraction path. Invariants verified at all 15 mutation sites. |
| RNG Manipulation | **Very Low** | VRF sole source; lock semantics; zero block proposer influence. |
| Accounting Drift | **Very Low** | Remainder pattern wei-exact. stETH rounding strengthens invariant. |
| Economic Exploitation | **Very Low** | Sybil, MEV, affiliate, whale vectors all structurally unprofitable. |
| Access Control | **Low** | DGVE-based admin with CREATOR as fixed deployer. Module isolation complete. |
| Availability | **Low** | All stuck states have recovery. Worst case: 120-day timeout + VRF failure. |
| Cross-Contract | **Very Low** | All 46 delegatecall sites verified. Constructor ordering verified. |
| Gambling Burn | **Very Low** | Four findings found and fixed; invariant test suite provides regression coverage. |
| Futurepool Skim | **Very Low** | 5-step pipeline proven correct; ETH conservation holds algebraically and under fuzz. |
| Redemption Lootbox | **Very Low** | 50/50 split conservation proven; daily cap, slot packing, access control all verified. |

---

## Scope

**Core Contracts (14):** DegenerusGame, DegenerusAdmin, DegenerusAffiliate, BurnieCoin, BurnieCoinflip, StakedDegenerusStonk, DegenerusStonk, DegenerusVault, DegenerusJackpots, DegenerusQuests, DegenerusDeityPass, DeityBoonViewer, Icons32Data, WrappedWrappedXRP

**Delegatecall Modules (10):** AdvanceModule, MintModule, WhaleModule, JackpotModule, DecimatorModule, EndgameModule, GameOverModule, LootboxModule, BoonModule, DegeneretteModule

**Libraries/Shared (10):** ContractAddresses, DegenerusTraitUtils, DegenerusGameStorage, MintStreakUtils, PayoutUtils, BitPackingLib, EntropyLib, GameTimeLib, JackpotBucketLib, PriceLookupLib

**v3.3 Gambling Burn Scope:** StakedDegenerusStonk.sol (gambling burn functions: burn, burnWrapped, claimRedemption, resolveRedemptionPeriod, hasPendingRedemptions), DegenerusStonk.sol (Seam-1 fix: GameNotOver guard), BurnieCoinflip.sol (claimCoinflipsForRedemption), DegenerusGameAdvanceModule.sol (redemption resolution in rngGate and _gameOverEntropy)

**v3.4 New Feature Scope:** DegenerusGameAdvanceModule.sol (futurepool skim redesign: _applyTimeBasedFutureTake 5-step pipeline with overshoot surcharge, triangular variance, 80% cap), StakedDegenerusStonk.sol (50/50 redemption lootbox split, 160 ETH daily cap, activity score snapshot), DegenerusGame.sol (resolveRedemptionLootbox cross-contract call chain), DegenerusGameLootboxModule.sol (lootbox resolution delegatecall)

**Tools:** Manual line-by-line review, Slither 0.11.5, Foundry `forge inspect`, 1,463 Hardhat tests + 27 Foundry harnesses, 11 Foundry invariant tests (7 redemption + 4 skim), multi-agent adversarial warden simulation

**Out of scope:** Formal verification, coverage-guided fuzzing, frontend/off-chain code, testnet-specific behavior, mocks, deployment scripts
