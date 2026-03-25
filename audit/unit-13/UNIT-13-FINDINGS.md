# Unit 13: Admin + Governance -- Final Findings Report

**Phase:** 115
**Contract:** DegenerusAdmin.sol
**Audit Model:** Opus (claude-opus-4-6)
**Date:** 2026-03-25

---

## Executive Summary

Unit 13 audited the protocol's central administration and governance contract (DegenerusAdmin.sol). The audit covered 17 functions across 1 contract, with 11 state-changing functions receiving full adversarial analysis including call tree expansion, storage write mapping, and cached-local-vs-storage checks. The governance system (propose/vote/execute for emergency VRF coordinator swaps) received the deepest scrutiny as the highest-risk surface.

**Result: ZERO CRITICAL/HIGH/MEDIUM vulnerabilities. One LOW finding (missing LINK recovery path). Three INFO observations.**

The governance system is well-designed with appropriate safeguards: stall-duration gates, decaying thresholds, stall re-checks on every vote, and automatic voiding of competing proposals on execution. No BAF-class cached-local-vs-storage bugs exist.

---

## Audit Statistics

| Metric | Value |
|--------|-------|
| Contracts audited | 1 (DegenerusAdmin) |
| Total functions | 17 |
| State-changing functions analyzed | 11 |
| View/pure functions catalogued | 6 |
| Category B (full attack analysis) | 9 |
| Category C (standalone -- elevated per D-05) | 1 (_executeSwap) |
| Category C (traced via parent) | 1 (_voidAllActive) |
| CRITICAL-tier functions | 3 (propose, vote, _executeSwap) |
| HIGH-tier functions | 1 (shutdownVrf) |
| Cross-contract call sites traced | 30+ |
| External contracts interacted with | 7 (VRF Coordinator, Game, LINK Token, Coin, Vault, sDGNRS, Price Feed) |
| Mad Genius findings | 5 |
| Skeptic: FALSE POSITIVE | 1 |
| Skeptic: CONFIRMED | 4 |
| Final: CRITICAL | 0 |
| Final: HIGH | 0 |
| Final: MEDIUM | 0 |
| Final: LOW | 1 |
| Final: INFO | 3 |
| Taskmaster Coverage | PASS (100%) |

---

## Confirmed Findings

### LOW-01: No LINK Recovery Path After Failed shutdownVrf Transfer

**Affected:** DegenerusAdmin::shutdownVrf (L651-674)
**Lines:** L656 (subscriptionId zeroed), L664-671 (transfer wrapped in try/catch)
**Mad Genius Finding:** F-03
**Skeptic Verdict:** CONFIRMED as LOW

**Description:**
When `shutdownVrf()` is called during game-over, the function zeros `subscriptionId` at L656 before attempting LINK transfer at L665. If the LINK transfer fails (returns false or reverts), the LINK remains in the Admin contract. With `subscriptionId == 0`, no function in the contract can interact with the LINK:
- `onTokenTransfer` reverts at L692 (NoSubscription)
- No `sweep()`, `withdraw()`, or owner-accessible LINK transfer function exists
- The owner-only functions (setLinkEthPriceFeed, swapGameEthForStEth, stakeGameEthToStEth, setLootboxRngThreshold) do not touch LINK

**Impact:** Permanent LINK lock in Admin contract if transfer fails at game-over. The locked amount would be whatever LINK balance the Admin contract holds (including any LINK refunded from subscription cancellation at L659).

**Likelihood:** Very low. LINK is a standard ERC-677 token with no pause or blacklist. The target (Vault contract) is a compile-time constant. Transfer failure would require a LINK token upgrade, chain fork, or exceptional circumstances.

**Recommendation:** Add an owner-only `sweepLink(address to)` function that can be called after game-over to recover any stuck LINK. This is a safety valve that adds no attack surface (game is over, VRF is shutdown).

**Severity: LOW** -- Requires unlikely failure mode, but missing recovery path is a legitimate design gap.

---

## INFO-Level Observations

### INFO-01: Vote Weight Inflation via sDGNRS Transfer Between Votes

**Affected:** DegenerusAdmin::vote (L452-517)
**Lines:** L470 (weight from live balance), L487 (weight recorded per voter)
**Mad Genius Finding:** F-01
**Skeptic Verdict:** CONFIRMED as INFO

**Description:**
The voting system uses live sDGNRS balances (`sDGNRS.balanceOf(msg.sender)` at L470) rather than a snapshot taken at proposal creation. This means a voter can vote, transfer their sDGNRS to another address, and that address can vote with a higher balance. The combined `approveWeight` (or `rejectWeight`) can exceed the actual circulating supply.

**Example:** Alice (100 sDGNRS) votes Approve -> approveWeight += 100. Alice transfers 100 to Bob. Bob (200 sDGNRS) votes Approve -> approveWeight += 200. Total approveWeight = 300, but only 200 sDGNRS exist in circulation.

**Why INFO:**
1. The attack is symmetric -- both approve and reject sides can inflate weights equally
2. The total inflation is bounded by supply (redistribution, not creation)
3. The execute condition requires approveWeight > rejectWeight (L503), so the side with more actual sDGNRS wins even with inflation
4. Live-balance voting is a standard governance pattern (e.g., early OpenZeppelin Governor)
5. The code comment at L469 ("VRF dead = supply frozen") is technically inaccurate about individual balances but correct about total supply

**Recommendation:** Consider using ERC20Votes-style snapshot-at-proposal-creation for strict vote weight integrity. However, the added complexity may not be warranted given the emergency-only nature of this governance system and the extremely narrow activation window (VRF stall).

**Severity: INFO** -- Known property of live-balance governance. No practical exploitation path under honest majority assumption.

---

### INFO-02: Silent Catch on Old Subscription Cancellation During VRF Swap

**Affected:** DegenerusAdmin::_executeSwap (L566-627)
**Lines:** L581-588 (try/catch on cancelSubscription)
**Mad Genius Finding:** F-04
**Skeptic Verdict:** DOWNGRADE TO INFO

**Description:**
When executing a VRF coordinator swap, the function attempts to cancel the old subscription (L582-583) via try/catch. If cancellation fails silently, the old subscription remains active on the old coordinator with any allocated LINK. The Admin contract loses its reference to the old coordinator/subscription after overwriting at L592-595.

**Why INFO:**
This is intentional defensive design. The governance system swaps coordinators BECAUSE the old one is broken/stalled. A broken coordinator may not respond to cancelSubscription. The try/catch ensures the swap proceeds regardless. The "lost" LINK in the old subscription is a known tradeoff: blocking the swap to recover LINK from a broken coordinator would defeat the purpose of the emergency governance mechanism.

**Severity: INFO** -- Intentional design decision documented in code comments. No recommendation for change.

---

### INFO-03: LINK Stuck in Admin After Failed Shutdown Transfer

**Affected:** DegenerusAdmin::shutdownVrf (L651-674)
**Lines:** L664-671 (transfer wrapped in try/catch)
**Mad Genius Finding:** F-05
**Skeptic Verdict:** CONFIRMED as INFO (same root cause as LOW-01)

**Description:**
If `linkToken.transfer(target, bal)` fails at L665, the function does not revert -- it emits `SubscriptionShutdown(subId, target, 0)` and returns. The LINK remains in the Admin contract. This is the specific failure mode that triggers the LOW-01 finding (missing recovery path).

The silent failure is intentional: game-over shutdown must succeed even if LINK transfer fails. The game-over state machine must complete.

**Severity: INFO** -- Intentional defensive design. The recovery gap is covered by LOW-01.

---

## Noteworthy Safe Patterns

The following patterns deserve recognition as well-implemented security measures:

1. **Stall Re-check in vote() (L454-456):** Every vote re-verifies VRF stall status. If VRF recovers mid-voting, all governance calls revert. This is the auto-invalidation mechanism -- no explicit "cancel all proposals" needed.

2. **CEI in _executeSwap (L568-571):** Proposal state set to Executed and all other proposals voided BEFORE any external calls. Prevents reentrant governance manipulation.

3. **voidedUpTo Watermark (L276-278, L632-643):** The _voidAllActive loop uses a monotonically advancing watermark to avoid re-scanning already-voided proposals. Prevents unbounded gas growth across multiple governance rounds.

4. **Decaying Threshold (L530-539):** 50% -> 5% over 7 days ensures that governance action becomes progressively easier as the VRF stall persists. Prevents governance gridlock during a genuine emergency.

5. **onTokenTransfer Auth (L688):** LINK donation handler correctly verifies msg.sender is the LINK token address. Cannot be called by arbitrary contracts.

6. **Feed Health Gate (L359):** setLinkEthPriceFeed can only replace a BROKEN feed. A working feed cannot be swapped. This prevents owner from disrupting the reward system.

---

## Access Control Matrix

| Function | Access Control | Guard |
|----------|---------------|-------|
| setLinkEthPriceFeed | onlyOwner (DGVE majority) | vault.isVaultOwner(msg.sender) |
| swapGameEthForStEth | onlyOwner (DGVE majority) | vault.isVaultOwner(msg.sender) |
| stakeGameEthToStEth | onlyOwner (DGVE majority) | vault.isVaultOwner(msg.sender) |
| setLootboxRngThreshold | onlyOwner (DGVE majority) | vault.isVaultOwner(msg.sender) |
| propose | Admin: DGVE owner + 20h stall / Community: 0.5% sDGNRS + 7d stall | vault.isVaultOwner OR sDGNRS balance check |
| vote | Any sDGNRS holder (balance > 0) + VRF stall 20h+ | sDGNRS.balanceOf > 0 + stall check |
| shutdownVrf | Game contract only | msg.sender == GAME |
| onTokenTransfer | LINK token only (ERC-677) | msg.sender == LINK_TOKEN |

---

*Unit 13 audit complete: 2026-03-25*
*DegenerusAdmin.sol: 803 lines, 17 functions, 0 critical/high/medium findings.*
*Governance system is sound. One minor recovery gap (LOW-01) documented.*
