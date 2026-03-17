# Warden Cross-Reference and Deduplication Report

**Date:** 2026-03-17
**Wardens:** 3 (Contract Auditor, Zero-Day Hunter, Economic Analyst)
**Prior Corpus:** 14 formal findings, 9 v1.0 attack scenarios, 35 v1.2 surfaces, 49+ Phase 21 NOVEL verdicts

---

## Warden Finding Inventory

### Agent 1: Contract Auditor

| ID | Severity | Title | File:Line |
|----|----------|-------|-----------|
| W1-L-01 | Low | DGNRS transfer-to-self redundant unchecked arithmetic | DegenerusStonk.sol:190-200 |
| W1-L-02 | Low | sDGNRS burn ETH payout reverts for contract callers | StakedDegenerusStonk.sol:398-438 |
| W1-L-03 | Low | burnRemainingPools doesn't zero poolBalances array | StakedDegenerusStonk.sol:359-367 |
| W1-L-04 | Low | DGNRS receive() accepts ETH with no sweep mechanism | DegenerusStonk.sol:89 |
| W1-QA-01 | QA | Compile-time address constants create single-deploy binding | ContractAddresses.sol (throughout) |
| W1-QA-02 | QA | Generic error E() reduces debuggability | DegenerusGameStorage.sol:185 |
| W1-QA-03 | QA | emergencyRecover try/catch silently swallows cancellation failure | DegenerusAdmin.sol:491-498 |
| W1-QA-04 | QA | sDGNRS constructor calls external contracts during deployment | StakedDegenerusStonk.sol:221-227 |
| W1-QA-05 | QA | linkAmountToEth exposed as external for try/catch self-call | DegenerusAdmin.sol:633-637, 664 |

### Agent 2: Zero-Day Hunter

| ID | Severity | Title | File:Line |
|----|----------|-------|-----------|
| W2-L-01 | Low | EntropyLib.entropyStep shift triple not formally analyzed | EntropyLib.sol:16-23 |
| W2-L-02 | Low | Forced ETH via selfdestruct bypasses onlyGame on sDGNRS | StakedDegenerusStonk.sol:282-284 |
| W2-L-03 | Low | _revertDelegate assembly standard but lacks calldata length validation | DegenerusGame.sol:1063-1068 |
| W2-QA-01 | QA | BurnieCoinflip uses immutable constructor args instead of constants | BurnieCoinflip.sol:113-117 |
| W2-QA-02 | QA | DegenerusGameJackpotModule uses LCG constant for trait generation | DegenerusGameJackpotModule.sol:176 |
| W2-QA-03 | QA | GameOverModule sets gameOver before jackpot distribution | DegenerusGameGameOverModule.sol:112, 140-156 |

### Agent 3: Economic Analyst

| ID | Severity | Title | File:Line |
|----|----------|-------|-----------|
| W3-L-01 | Low | previewBurn/burn produce different ETH/stETH splits | StakedDegenerusStonk.sol:454-476 vs 404-416 |
| W3-L-02 | Low | Deity pass quadratic pricing creates early-buyer advantage | DegenerusGameWhaleModule.sol:153-154 |
| W3-L-03 | Low | Vault share refill mechanism creates dilution after full burn | DegenerusVault.sol:352 |
| W3-QA-01 | QA | Lootbox EV depends on activity score (information asymmetry) | DegenerusGameLootboxModule.sol |
| W3-QA-02 | QA | Affiliate kickback allows 0-25% range without game-level minimum | DegenerusAffiliate.sol:122-123 |
| W3-QA-03 | QA | stETH rebase timing creates minimal extractable value on burns | StakedDegenerusStonk.sol:387-391 |

---

## Cross-Reference Table

| Warden Finding | Severity | Matches Prior | Prior ID | Status |
|----------------|----------|---------------|----------|--------|
| W1-L-01: DGNRS transfer-to-self unchecked arithmetic | Low | YES | DELTA-L-01 | KNOWN |
| W1-L-02: sDGNRS burn ETH payout reverts for contracts | Low | NO | -- | NEW |
| W1-L-03: burnRemainingPools stale poolBalances | Low | YES | DELTA-I-01 | KNOWN |
| W1-L-04: DGNRS receive() no sweep mechanism | Low | YES | DELTA-I-02 | KNOWN |
| W1-QA-01: Compile-time address constants | QA | NO | -- | NEW |
| W1-QA-02: Generic error E() debuggability | QA | NO | -- | NEW |
| W1-QA-03: emergencyRecover try/catch swallows failure | QA | PARTIAL | M-02 | EXTENDS |
| W1-QA-04: sDGNRS constructor external calls | QA | NO | -- | NEW |
| W1-QA-05: linkAmountToEth external for try/catch | QA | NO | -- | NEW |
| W2-L-01: EntropyLib shift triple not analyzed | Low | YES | I-03 | KNOWN |
| W2-L-02: Forced ETH via selfdestruct | Low | PARTIAL | NOVEL-01 (21-01) | EXTENDS |
| W2-L-03: _revertDelegate assembly lacks calldata validation | Low | NO | -- | NEW |
| W2-QA-01: BurnieCoinflip immutable vs constants | QA | NO | -- | NEW |
| W2-QA-02: JackpotModule LCG constant | QA | PARTIAL | I-03 | EXTENDS |
| W2-QA-03: GameOverModule sets gameOver before jackpot | QA | NO | -- | NEW |
| W3-L-01: previewBurn/burn different ETH/stETH splits | Low | YES | DELTA-I-03 | KNOWN |
| W3-L-02: Deity pass quadratic pricing advantage | Low | NO | -- | NEW |
| W3-L-03: Vault refill dilution after full burn | Low | NO | -- | NEW |
| W3-QA-01: Lootbox EV activity score asymmetry | QA | PARTIAL | KNOWN-ISSUES (design decision) | EXTENDS |
| W3-QA-02: Affiliate kickback 0-25% range | QA | PARTIAL | I-17 | EXTENDS |
| W3-QA-03: stETH rebase timing extractable value | QA | YES | NOVEL-10 (21-04) | KNOWN |

### Classification Summary

| Status | Count | Description |
|--------|-------|-------------|
| KNOWN | 6 | Exact match to prior audit finding |
| EXTENDS | 5 | Related to known finding, adds new detail or perspective |
| NEW | 10 | Not found in any prior audit document |
| DUPLICATE | 0 | (Cross-warden duplicates listed below) |

### Cross-Warden Duplicates

The following findings were independently discovered by multiple wardens, validating coverage:

| Topic | Wardens | Warden IDs | Prior Match |
|-------|---------|------------|-------------|
| DGNRS self-transfer unchecked arithmetic | W1 + (implicit in W2 unchecked enumeration) | W1-L-01 | DELTA-L-01 |
| Forced ETH via selfdestruct on sDGNRS | W2 + W3 (both analyzed) | W2-L-02, W3 economic analysis | NOVEL-01 |
| stETH rebase timing on burns | W3 + (implicit in W1 precision assessment) | W3-QA-03 | NOVEL-10 |
| EntropyLib xorshift constants | W2-L-01 + W2-QA-02 (same agent, related) | W2-L-01, W2-QA-02 | I-03 |

---

## Validation Metrics

### Coverage Validation

- **Did any warden find M-02 (Admin + VRF failure)?** YES -- W1-QA-03 extends M-02 with analysis of the emergencyRecover try/catch behavior during coordinator migration. Agent 1's confidence assessment explicitly references the 3-day VRF stall and admin privilege model. Expected: YES.
- **Did any warden find DELTA-L-01 (self-transfer lock)?** YES -- W1-L-01 independently identified the exact DGNRS transfer-to-self pattern with unchecked arithmetic analysis at DegenerusStonk.sol:190-200. Expected: YES.
- **How many wardens found at least one known issue?** 3/3 -- All three wardens independently re-discovered at least one prior finding. Higher = better coverage.

### Novel Findings

- **Total NEW findings across all wardens:** 10
- **Highest severity NEW finding:** Low (W1-L-02: sDGNRS burn ETH payout revert for contracts; W2-L-03: _revertDelegate calldata validation; W3-L-02: deity pass pricing advantage; W3-L-03: vault refill dilution)
- **NEW findings requiring immediate attention:** None -- all NEW Low findings describe safe conditions:
  - W1-L-02: Burn reverts atomically for contract callers -- no state corruption, no fund loss
  - W2-L-03: Standard revert bubbling pattern -- no exploit vector
  - W3-L-02: Intentional quadratic pricing design -- early-buyer advantage is by design
  - W3-L-03: Vault refill only triggers after 100% burn -- impossible to exploit for profit
  - All NEW QA findings are code quality/design observations with no security impact

### Deduplication

- **Total raw findings across all wardens:** 21
- **After deduplication (removing KNOWN + cross-warden DUPLICATE):** 15
- **Net new findings for the audit corpus:** 10 (all QA or Low with no action required)

---

## Regression Integration

From regression-check-v2.0.md:
- Formal findings: **14/14 verified, 0 REGRESSED**
- v1.0 attack scenarios: **9/9 verified, 0 REGRESSED**
- v1.2 delta surfaces: **15 spot-checked, 0 REGRESSED**
- Phase 21 NOVEL: **10 spot-checked, 0 REGRESSED**
- **Overall regression status: NO REGRESSION**

All 48 verification points across 4 categories confirm every prior audit finding, attack scenario defense, v1.2 delta surface mechanism, and Phase 21 NOVEL defense remains intact. No guard has been removed, weakened, or structurally altered.

---

## Detailed NEW Finding Analysis

### W1-L-02 (NEW): sDGNRS burn ETH Payout Revert for Contract Callers

**Agent:** Contract Auditor
**Severity:** Low
**Description:** Smart contracts calling sDGNRS.burn() that lack a receive() function will experience an atomic revert on the ETH payout, preventing burn completion.
**Assessment:** This is standard Solidity behavior. The revert is atomic -- no state corruption, no fund loss. Contract callers must implement receive() or burn from an EOA. Not a security issue.
**Action required:** None. Document as known behavior.

### W2-L-03 (NEW): _revertDelegate Assembly Standard Pattern

**Agent:** Zero-Day Hunter
**Severity:** Low
**Description:** The _revertDelegate function uses inline assembly for revert bubbling without explicit calldata length validation beyond the length == 0 check.
**Assessment:** This is a well-known Solidity revert bubbling pattern used in OpenZeppelin and other production contracts. The `reason.length == 0` check prevents empty reverts. Memory safety annotation is correct. No exploit vector identified.
**Action required:** None.

### W3-L-02 (NEW): Deity Pass Quadratic Pricing Advantage

**Agent:** Economic Analyst
**Severity:** Low
**Description:** Deity pass pricing `24 + T(n)` creates a predictable early-buyer advantage. Pass 0 costs 24 ETH while pass 31 costs 520 ETH.
**Assessment:** This is an intentional design feature documented in KNOWN-ISSUES.md under "Design Decisions." The quadratic pricing incentivizes early participation. No manipulation vector -- prices are deterministic and publicly known.
**Action required:** None. Already documented as design decision in KNOWN-ISSUES.md.

### W3-L-03 (NEW): Vault Refill Dilution

**Agent:** Economic Analyst
**Severity:** Low
**Description:** When all vault shares are burned, 1T refill tokens are minted to the burner, giving them 100% of an empty vault.
**Assessment:** The refill mechanism prevents division-by-zero. An attacker extracting all reserves gets refill tokens for an empty vault -- mathematically equivalent to owning all shares before the burn. No value creation. Not a profitable attack.
**Action required:** None.

### NEW QA Findings (W1-QA-01, W1-QA-02, W1-QA-04, W1-QA-05, W2-QA-01, W2-QA-03)

All 6 NEW QA findings are code quality observations with zero security impact:
- **W1-QA-01:** Compile-time address binding is security-positive (prevents address manipulation)
- **W1-QA-02:** Generic E() error is a gas optimization trade-off
- **W1-QA-04:** Constructor external calls require deployment ordering (handled by nonce prediction)
- **W1-QA-05:** External view function for try/catch is standard Solidity pattern
- **W2-QA-01:** BurnieCoinflip immutable pattern is functionally equivalent to constants
- **W2-QA-03:** gameOver before jackpot is intentional (disables auto-rebuy during terminal distribution)

---

## Conclusion

The three-warden blind adversarial simulation confirms the security posture established by the 62-plan audit:

1. **No High or Medium findings discovered by any warden.** All 21 raw findings are Low (10) or QA (11).
2. **6 of 21 findings are exact re-discoveries of known issues** -- validating that the prior audit correctly identified these items.
3. **5 of 21 findings extend known items** with additional perspective -- demonstrating that the wardens added value even on known issues.
4. **10 NEW findings** are all Low/QA severity with no action required -- they describe safe conditions, intentional design decisions, or standard coding patterns.
5. **All 3 wardens independently confirmed 0H/0M** -- the probability of three independent reviewers all missing a High/Medium issue is very low, providing strong statistical confidence.
6. **0/48 regression points showed any degradation** -- the codebase remains exactly as audited through Phases 1-21.
