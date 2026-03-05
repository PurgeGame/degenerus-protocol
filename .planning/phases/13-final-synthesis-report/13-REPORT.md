# Degenerus Protocol v2.0 Adversarial Audit -- Final Findings Report

**Audit Period:** March 2026
**Auditor:** Claude (AI-assisted security analysis)
**Scope:** Phases 8-12 (v2.0 adversarial audit only; v1.0 findings documented in Phase 7 report)
**Methodology:** 5-domain adversarial analysis, 48 requirements, Phases 8-12
**Solidity:** 0.8.26/0.8.28, viaIR enabled, optimizer runs=2
**Audit Commits Verified:** `4592d8c` (BURNIE purchase cutoff), `cbbafa0` (Degenerette sentinel), `9539c6d` (capBucketCounts underflow guard)

---

## Executive Summary

### Overall Assessment

**SOUND with centralization risks.** The v2.0 adversarial audit examined 5 domains across 48 requirements: ETH accounting integrity, gas analysis and Sybil bloat, admin power and VRF griefing, token security and economic attacks, and cross-function reentrancy integration. No critical or high findings emerged. All 4 findings above LOW severity share the same precondition class: admin-key compromise (CREATOR EOA or >30% DGVE). Under Code4rena methodology, admin-key-required findings are classified MEDIUM regardless of impact severity because the likelihood of a trusted admin acting maliciously is LOW by convention.

### Severity Distribution (v2.0 New Findings Only)

| Severity | Count | Notes |
|----------|-------|-------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 4 | All admin-key-required; see M-v2-01 (ADMIN-02), M-v2-02 (ADMIN-03), M-v2-03 (ADMIN-01-F1), M-v2-04 (ADMIN-01-F2) |
| Low | 1 | ACCT-05-L1: creditLinkReward not implemented |
| Gas | -- | See standalone Gas Report section |
| QA / Informational | 7 | NatSpec discrepancies, design observations |

### Key Differences from v1.0 Audit

Findings from the v1.0 audit (H-01, M-01 through M-03, L-01 through L-06) are documented in the Phase 7 Final Findings Report and are NOT repeated here. The v2.0 audit used the v1.0 pass verdicts as a baseline and focused on adversarial extensions: deep ETH accounting invariants (Phase 8), gas DoS modeling (Phase 9), admin privilege abuse (Phase 10), token/vault economics (Phase 11), and cross-function reentrancy integration (Phase 12).

### Key Strengths

- **ETH solvency invariant confirmed:** `sum(deposits) == prizePool + futurePool + claimablePool + fees` holds across all 7 tested state sequences (ACCT-01, ACCT-08 PASS)
- **Gas DoS is structurally impossible:** WRITES_BUDGET_SAFE=550 architecture caps single-call gas at ~7.4M (46.2% of 16M block limit); worst measured path is 6,284,995 gas (STAGE_TICKETS_WORKING)
- **Reentrancy matrix complete:** All 8 ETH-transfer sites across 4 contracts confirmed CEI-safe; ERC721 callback path formally safe; 40 JackpotModule unchecked blocks verified (REENT-01 through REENT-07 all PASS)
- **Assembly verified correct:** JackpotModule and MintModule `traitBurnTicket` slot calculations match actual Solidity storage layout; no storage corruption (ASSY-01, ASSY-02, ASSY-03 PASS)

### Areas Requiring Attention

- **wireVrf has no stall gate** -- admin can substitute a malicious VRF coordinator during an active game, granting full RNG manipulation (M-v2-01)
- **wireVrf-based griefing loop** -- admin can halt the game for 3 game days, recover via `updateVrfCoordinatorAndSub`, and repeat indefinitely (M-v2-02)
- **setLinkEthPriceFeed malicious oracle** -- admin can inflate or suppress BURNIE rewards for LINK donors by substituting a rigged price feed (M-v2-03)
- **setLootboxRngThreshold freeze** -- admin can set threshold to `uint256.max`, permanently freezing lootbox resolution (M-v2-04)

---

## Severity Definitions

*[Content in Task 2]*

---

## Critical Findings

*[Content in Task 2]*

---

## High Findings

*[Content in Task 2]*

---

## Medium Findings

*[Content in Plan 13-02]*

---

## Low Findings

*[Content in Plan 13-03]*

---

## Gas Report

*[Content in Plan 13-04]*

---

## QA / Informational Findings

*[Content in Plan 13-03]*

---

## Fix Commit Verifications

*[Content in Plan 13-03]*

---

## Requirement Coverage Matrix (v2.0)

*[Content in Plan 13-04]*

---

## Scope and Methodology

*[Content in Task 2]*
