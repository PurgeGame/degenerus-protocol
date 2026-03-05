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

| Severity | Description |
|----------|-------------|
| Critical | Direct loss of funds exploitable without privileged access |
| High | Material risk to protocol integrity or significant fund-at-risk scenarios |
| Medium | Conditional risk requiring specific circumstances, or correctness issue with limited user-facing impact |
| Low | Minor issues, testing gaps, or theoretical concerns with negligible financial risk |
| Informational | Code quality, documentation, design observations; no security impact |

**v2.0 Note on Admin-Key Findings:** For v2.0 admin-key findings, Code4rena severity formula applies: IMPACT x LIKELIHOOD. Admin-key-required findings have LOW likelihood by C4 convention (trusted admin), so CRITICAL impact + LOW likelihood = MEDIUM. All four v2.0 MEDIUM findings share this classification.

---

## Critical Findings

No critical findings were identified in the v2.0 adversarial audit.

---

## High Findings

No high findings were identified in the v2.0 adversarial audit. The four admin-key-dependent scenarios (M-v2-01 through M-v2-04) were rated MEDIUM under Code4rena severity methodology because they require admin-key compromise as a precondition.

---

## Medium Findings

### M-v2-01: wireVrf Mid-Game Coordinator Substitution

**Severity:** MEDIUM (admin-key-required; CRITICAL impact x LOW likelihood per C4 methodology)
**Affected Contract:** DegenerusGameAdvanceModule.sol:298 (`wireVrf`)
**Requirement:** ADMIN-02
**Discovered:** Phase 10, Plan 10-02

**Description:**
`wireVrf` is callable by ADMIN at any time without a stall gate. An attacker controlling the CREATOR EOA (or >30% DGVE via `isVaultOwner`) can immediately substitute any address as the VRF coordinator. The sole guard for `rawFulfillRandomWords` is `require(msg.sender == vrfCoordinator, ...)` -- once `vrfCoordinator` is set to an attacker-controlled contract, the attacker can supply arbitrary random words to every subsequent game day's RNG resolution.

**Root Cause:**
`wireVrf` performs an unconditional overwrite of the coordinator address with no stall gate requirement. `updateVrfCoordinatorAndSub` (the intended emergency-rotation function) requires a 3-day observable stall first; `wireVrf` does not. The NatSpec at line 294 claims "Idempotent after first wire (repeats must match)" but no such guard is implemented in the code.

**Impact:**
Full RNG manipulation for the remainder of the game. Attacker controls jackpot winner selection, trait rarities, and lootbox outcomes on every game day. Prize pools range from dozens to hundreds of ETH; a malicious coordinator grants the attacker full control over their distribution.

**Coded PoC (Transaction Sequence):**
1. Attacker controls CREATOR EOA (or acquires >30% DGVE to satisfy `isVaultOwner`)
2. Attacker deploys `AttackerCoordinator` -- a contract that implements `requestRandomWords` (returns any requestId) and relays `rawFulfillRandomWords` calls with a chosen word
3. `DegenerusAdmin.wireVrfForGame(AttackerCoordinatorAddr, anySubId, anyKeyHash)` -- no stall gate, executes immediately; sets `vrfCoordinator = AttackerCoordinatorAddr`
4. Next `advanceGame()` call triggers `_requestRng` -> `vrfCoordinator.requestRandomWords(...)` on `AttackerCoordinator`
5. Attacker calls `DegenerusGame.rawFulfillRandomWords(requestId, [chosenWord])` from `AttackerCoordinator`; `msg.sender == vrfCoordinator` check passes
6. `chosenWord` flows into jackpot winner selection, trait rarities, lootbox outcomes; attacker repeats each game day

**Distinguishing factor vs. `updateVrfCoordinatorAndSub`:** The emergency rotation function requires a 3-day observable stall (attackers cannot act silently). `wireVrf` has no stall gate and can be called silently during any active game day.

**Remediation:** Add a stall gate to `wireVrf` (require `_threeDayRngGap()` before allowing coordinator change), or document clearly that `wireVrf` is an initial-wiring-only function and add `require(vrfCoordinator == address(0), "already wired")`.

### M-v2-02: wireVrf-Based Indefinitely Repeatable Stall Griefing Loop

**Severity:** MEDIUM (admin-key-required; CRITICAL impact x LOW likelihood per C4 methodology)
**Affected Contract:** DegenerusGameAdvanceModule.sol:298 (`wireVrf`) + `updateVrfCoordinatorAndSub`
**Requirement:** ADMIN-03
**Discovered:** Phase 10, Plan 10-03

**Description:**
Admin can call `wireVrf` with a reverting coordinator address to halt `advanceGame()` for 3 game days (the emergency stall window), then call `updateVrfCoordinatorAndSub` to recover and reset the stall gate, then repeat -- creating an indefinitely repeatable griefing loop requiring only one admin call per 3-day cycle. No observable external event (such as Chainlink outage) is required.

**Root Cause:**
The 3-day stall gate on `updateVrfCoordinatorAndSub` was designed to allow emergency coordinator rotation after an external failure, but it does not distinguish between a coordinator that failed externally and one that was deliberately swapped to a reverting address. The recovery function serves as its own stall-gate reset.

**Five-Path Stall Taxonomy:**
- Path A: LINK subscription drain (external; no admin key required)
- Path B: Chainlink coordinator outage (external; non-adversarial)
- Path C: Admin subscription neglect (passive)
- Path D: Admin deploys reverting coordinator via `wireVrf` (active; 1 call)
- Path E: Admin repeats Path D after recovery -- **indefinite loop**

**Impact:**
Each cycle halts the game for 3+ game days. `rngWordByDay` for halted days remains zero. ETH purchases can still occur during a stall but are not processed until game resumes. A persistent attacker creates arbitrarily long game delays with minimal cost (gas for two admin calls per 3-day cycle).

**Coded PoC (Transaction Sequence -- Path D + E):**
1. Day 0: Attacker calls `wireVrf(revertingAddr, validSubId, validKeyHash)` -- no guard enforced
2. Any `advanceGame()` call hard-reverts at `_requestRng` ("Hard revert if Chainlink request fails")
3. Days D+1, D+2: Same; `rngWordByDay` for these days remains zero; game is halted
4. Day D+3: `_threeDayRngGap()` returns `true`; `updateVrfCoordinatorAndSub` becomes callable
5. Attacker calls `updateVrfCoordinatorAndSub(realCoordinatorAddr, subId, keyHash)` -- resets RNG state; game resumes
6. Attacker returns to step 1 on any subsequent game day -- loop is indefinitely repeatable

**Remediation:** Separate the "initial wiring" path from the "emergency rotation" path. Add `require(vrfCoordinator == address(0), "use updateVrfCoordinatorAndSub for rotation")` to `wireVrf`. This forces all mid-game coordinator changes through the observable 3-day stall gate.

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

### Scope

The Degenerus Protocol v2.0 Adversarial Audit covers Phases 8-12 only. v1.0 findings (Phases 1-7) are documented in the Phase 7 Final Findings Report. The 22 deployable contracts and 10 delegatecall modules remain in scope; testnet-specific contracts, mock contracts, deployment scripts, and frontend code are excluded (per v1.0 out-of-scope boundary).

### 48 Requirements Across 5 Domains

| Domain | Requirements | Phase |
|--------|-------------|-------|
| ETH Accounting Integrity | ACCT-01 through ACCT-10 | Phase 8 |
| Gas Analysis and Sybil Bloat | GAS-01 through GAS-07 | Phase 9 |
| Admin Power and VRF Griefing | ADMIN-01 through ADMIN-06 | Phase 10 |
| Assembly Safety | ASSY-01 through ASSY-03 | Phase 10 |
| Token Security and Economic Attacks | TOKEN-01 through TOKEN-08 | Phase 11 |
| Vault and Stonk Economics | VAULT-01, VAULT-02 | Phase 11 |
| Timestamp and Timing Attacks | TIME-01, TIME-02 | Phase 11 |
| Cross-Function Reentrancy and Unchecked Blocks | REENT-01 through REENT-07 | Phase 12 |
| Final Report | REPORT-01 through REPORT-03 | Phase 13 |

### Methodology

Manual code review using static analysis (Slither was used in v1.0 as a reference baseline). Gas measurements taken on Hardhat local network via adversarial harnesses in `test/gas/AdvanceGameGas.test.js`. No fuzzing campaigns were run in v2.0 (deferred to v3.0).

### Audit Commits Verified

Three fix commits introduced during the audit period were each tested for bypass:

| Commit | Fix Description | Bypass Test Result |
|--------|----------------|-------------------|
| `4592d8c` | BURNIE purchase cutoff -- `COIN_PURCHASE_CUTOFF` added to `_purchaseCoinFor()`; uses `block.timestamp`, not `msg.sender`; fires at `ticketQuantity != 0`; lootbox correctly exempted; no level-boundary off-by-one | **PASS** |
| `cbbafa0` | Degenerette sentinel -- `<` changed to `<=` in `claimableWinnings[player] <= fromClaimable`; exactly one `fromClaimable` site in DegeneretteModule; sentinel value 1 preserved | **PASS** |
| `9539c6d` | capBucketCounts underflow guard -- excess subtraction guarded by `if (scaledTotal > nonSoloCap)` precondition; trim loop uses `excess != 0` guard; entropy-rotated trim selection; 20-winner floor overcommit is intentional (see 9539c6d-INFO-01) | **PASS** |
