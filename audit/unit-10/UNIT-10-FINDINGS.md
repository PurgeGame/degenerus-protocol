# Unit 10: BURNIE Token + Coinflip -- Final Findings Report

**Phase:** 112-burnie-token-coinflip
**Contracts:** BurnieCoin.sol (~1,075 lines), BurnieCoinflip.sol (~1,129 lines)
**Auditors:** Mad Genius, Skeptic, Taskmaster (Claude Opus 4.6, 1M context)
**Date:** 2026-03-25
**Methodology:** Three-agent adversarial system per ULTIMATE-AUDIT-DESIGN.md

---

## Executive Summary

Unit 10 covers BurnieCoin (the BURNIE ERC20 token) and BurnieCoinflip (the daily coinflip wagering system). Together, these standalone contracts manage token supply, transfer mechanics, vault escrow accounting, daily flip deposits/claims, auto-rebuy carry, bounty system, and quest integration.

**Scope:** 71 functions (31 external state-changing, 12 internal state-changing, 28 view/pure) across 2 contracts totaling ~2,204 lines.

**Key attack surfaces investigated:**
1. Auto-claim callback chain (transfer -> coinflip claim -> mint -> transfer resumes)
2. Supply invariant (totalSupply + vaultAllowance) across 6 vault redirect paths
3. RNG lock guard completeness for carry extraction, bounty arming, BAF credit
4. processCoinflipPayouts entropy quality and bias
5. uint128 truncation risks in PlayerCoinflipState
6. Game contract transferFrom allowance bypass

**Result: No CRITICAL, HIGH, MEDIUM, or LOW findings.** The contracts are well-structured with appropriate access controls, CEI patterns, and timing guards. The auto-claim callback chain -- the primary concern -- is correctly ordered. Three INFO-level observations are documented below.

---

## Findings Summary

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| INFO-01 | INFO | ERC20 Approve Race Condition | Confirmed (by design) |
| INFO-02 | INFO | Vault Self-Mint Semantic Oddity | Confirmed (no impact) |
| INFO-03 | INFO | Misleading Error Name in Coinflip Gate | Confirmed (cosmetic) |

---

## Confirmed Findings

### INFO-01: ERC20 Approve Race Condition

**Severity:** INFO
**Affected Code:** BurnieCoin.sol, `approve()` L394-401, `transferFrom()` L422-441
**Category:** Code Quality

**Description:** Standard ERC20 approve/transferFrom race condition. A spender could front-run an approve change to spend both the old and new allowance. This is a well-known ERC20 design characteristic shared by all standard ERC20 implementations.

**Impact:** None specific to the Degenerus protocol. The game contract bypasses allowance entirely (trusted contract pattern at L428).

**Recommendation:** No action required. This is inherent to the ERC20 standard. Users mitigate by setting allowance to 0 before changing to a new value.

---

### INFO-02: Vault Self-Mint Semantic Oddity

**Severity:** INFO
**Affected Code:** BurnieCoin.sol, `vaultMintTo()` L705-717
**Category:** Code Quality

**Description:** The vault can call `vaultMintTo(VAULT, amount)`, which would reduce vaultAllowance, increase totalSupply, and increase balanceOf[VAULT]. This creates circulating tokens held by the vault. On subsequent transfer from VAULT, `_transfer` redirects to vault escrow (L458-467), effectively undoing the operation.

**Impact:** No economic impact. The supply invariant is maintained throughout. The net effect of mint-then-transfer is a no-op for the supply accounting.

**Recommendation:** No action required. The path is unreachable in normal vault operations and produces no adverse effects if triggered.

---

### INFO-03: Misleading Error Name in Coinflip Gate Functions

**Severity:** INFO
**Affected Code:** BurnieCoin.sol, `burnForCoinflip()` L529, `mintForCoinflip()` L538
**Category:** Code Quality

**Description:** Both functions revert with `OnlyGame()` error when the caller is not the coinflip contract. The error name implies the caller should be the game contract, but the actual check is `msg.sender != coinflipContract`.

**Impact:** None. The access control logic is correct -- only the coinflip contract can call these functions. The error name is misleading for debugging but does not affect security.

**Recommendation:** Consider renaming to a coinflip-specific error for clarity, though this is purely cosmetic.

---

## False Positive Log

No VULNERABLE or INVESTIGATE findings were raised by the Mad Genius. The following attack surfaces were investigated and found SAFE:

| Attack Surface | Why Safe |
|---------------|----------|
| Auto-claim callback stale cache | _transfer reads balanceOf fresh from storage after mint callback completes |
| Supply invariant violation | All 6 vault redirect paths maintain totalSupply + vaultAllowance invariant |
| Carry extraction via RNG knowledge | rngLocked() check in setCoinflipAutoRebuy prevents toggling during VRF |
| Bounty arming after RNG known | rngLocked() check in _addDailyFlip prevents record-setting during VRF |
| BAF credit front-running | _coinflipLockedDuringTransition blocks deposits during BAF resolution |
| uint128 overflow in claimableStored | Bounded by token supply economics (uint128 max = 3.4e38 >> any realistic supply) |
| Game transferFrom bypass abuse | Game address is compile-time constant (ContractAddresses.GAME), not configurable |
| processCoinflipPayouts RNG bias | Modulo bias is ~1.7e-76, cryptographically negligible |
| vaultEscrow unchecked overflow | Access restricted to GAME/VAULT, amounts bounded by game economics |

---

## Coverage Attestation

**Taskmaster Verdict: PASS**

- 31 Category B functions: ALL analyzed with full call trees, storage write maps, cached-local-vs-storage checks
- 12 Category C functions: ALL analyzed as part of parent call chains
- 28 Category D functions: ALL catalogued (view/pure, no state changes)
- No state-changing functions omitted from either contract
- No shortcuts, batch dismissals, or "similar to above" elisions
- All 8 priority investigation targets addressed

**Skeptic Verdict: ALL SAFE VERDICTS CONFIRMED**

- Auto-claim callback chain: independently verified safe
- Supply invariant: independently verified across all 6 paths
- RNG lock guards: independently verified comprehensive (7 guard points)
- RNG entropy quality: independently verified with modular arithmetic

---

## Recommendations for Integration Phase

1. **Phase 113 (sDGNRS):** Verify that `claimCoinflipsForRedemption` is called correctly during sDGNRS redemption flow and that the sDGNRS BAF exclusion at L556 is appropriate.
2. **Phase 114 (Vault):** Verify that vault share calculations use `supplyIncUncirculated()` correctly and that `vaultMintTo` / `vaultEscrow` amounts are economically bounded.
3. **Phase 116 (Quests):** Verify that quest reward amounts from `handleFlip`, `handleMint`, etc. are bounded and cannot inflate token supply.
4. **Phase 118 (Integration):** Cross-contract state coherence between BurnieCoin and BurnieCoinflip should be verified end-to-end, particularly the auto-claim callback chain under concurrent transaction scenarios.

---

*Unit 10 audit complete. No actionable findings.*
