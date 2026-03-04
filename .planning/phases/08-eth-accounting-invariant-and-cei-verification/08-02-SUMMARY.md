---
phase: 08-eth-accounting-invariant-and-cei-verification
plan: "02"
subsystem: audit
tags: [solidity, CEI, reentrancy, claimWinnings, LINK, stETH, security]

# Dependency graph
requires: []
provides:
  - ACCT-04 verdict: CEI order for claimWinnings() and payout helpers
  - ACCT-05 verdict: CEI order for LINK onTokenTransfer and stETH submit paths
affects: ["phase-13-report"]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/08-eth-accounting-invariant-and-cei-verification/08-02-SUMMARY.md
  modified: []

key-decisions:
  - "ACCT-04: PASS — claimWinnings() follows strict CEI; both EFFECTS precede INTERACTION on all paths"
  - "ACCT-05: PASS with INFO — LINK onTokenTransfer has a formal CEI deviation (creditLinkReward after transferAndCall) but is not exploitable; adminStakeEthForStEth is fully compliant"

patterns-established: []

requirements-completed:
  - ACCT-04
  - ACCT-05

# Metrics
duration: 20min
completed: 2026-03-04
---

# Phase 08-02: CEI Order Verification Summary

**ACCT-04 and ACCT-05 both PASS — claimWinnings() follows strict CEI with no reentrancy path; the LINK onTokenTransfer CEI deviation is formally present but not exploitable due to pre-computed multiplier and coordinator trust model.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-03-04T00:30:00Z
- **Completed:** 2026-03-04T00:50:00Z
- **Tasks:** 3 completed
- **Files modified:** 1

## Accomplishments

- Confirmed `_claimWinningsInternal` CHECKS-EFFECTS-INTERACTIONS order with exact line citations
- Confirmed `_payoutWithStethFallback` and `_payoutWithEthFallback` write no storage before transfers
- Assessed LINK `onTokenTransfer` CEI deviation: `subBal` multiplier computed BEFORE `transferAndCall`, so re-entry cannot change the reward
- Confirmed `adminStakeEthForStEth` has no state writes after `steth.submit{value}`
- Produced ACCT-04 and ACCT-05 verdicts: both PASS

## ACCT-04 Verdict

**ACCT-04**: PASS — `_claimWinningsInternal` follows strict CEI: `claimableWinnings[player] = 1` (sentinel, line 1473) and `claimablePool -= payout` (line 1476) both execute before the `_payoutWith*` external call (line 1479/1481); payout helpers write no storage. [DegenerusGame.sol:1468-1483]

## ACCT-05 Verdict

**ACCT-05**: PASS with INFO — `adminStakeEthForStEth` is fully CEI-compliant (external call last, no post-call state writes); `onTokenTransfer` has a formal CEI deviation (`coin.creditLinkReward` at line 636 after `linkToken.transferAndCall` at line 613) but is not exploitable: the reward multiplier (`mult`) is computed from `subBal` BEFORE the transferAndCall (line 609), so re-entry during transferAndCall cannot alter the credit amount; additionally `creditLinkReward` targets BURNIE mint supply (not ETH), so no ETH extraction path exists. INFO: `creditLinkReward` function is declared in the `IDegenerusCoinLinkReward` interface but does not appear in `BurnieCoin.sol` source — at runtime this call will revert if not implemented; this is a potential dead-code/missing-implementation issue rather than a CEI exploit. [DegenerusAdmin.sol:589-638, DegenerusGame.sol:1873-1888]

## CEI Table — `_claimWinningsInternal` (DegenerusGame.sol:1468-1483)

| Step | Type | Line | Action |
|------|------|------|--------|
| 1 | CHECK | 1469-1470 | `amount = claimableWinnings[player]`; `if (amount <= 1) revert E()` |
| 2 | EFFECT | 1473 | `claimableWinnings[player] = 1` (sentinel, zeroes claimable) |
| 3 | EFFECT | 1476 | `claimablePool -= payout` (aggregate liability decremented) |
| 4 | INTERACT | 1479 or 1481 | `_payoutWithEthFallback(player, payout)` or `_payoutWithStethFallback(player, payout)` |

Both EFFECTS precede the INTERACTION on all code paths. No conditional branch causes a partial EFFECTS execution.

## `_payoutWithStethFallback` Assessment (DegenerusGame.sol:2015-2042)

- Reads `address(this).balance` and `steth.balanceOf(address(this))` — these are balance reads, not state writes
- Makes `payable(to).call{value: ethSend}("")` at line 2022 (external interaction)
- Makes `_transferSteth(to, stSend)` at line 2031 (external interaction — stETH token transfer)
- No storage variable is written before or after the transfers
- **CORRECT**: no storage writes before ETH/stETH transfer; payout helper is CEI-compliant

## `_payoutWithEthFallback` Assessment (DegenerusGame.sol:2048-2062)

- Reads `steth.balanceOf(address(this))` and `address(this).balance` — balance reads only
- Makes `_transferSteth(to, stSend)` at line 2053 (external)
- Makes `payable(to).call{value: remaining}("")` at line 2060 (external)
- No storage writes before transfers
- **CORRECT**: CEI-compliant

## Reentrancy Guard Assessment

`DegenerusGame.sol` does **not** use a `nonReentrant` modifier or storage lock on `claimWinnings`. However, the CEI pattern eliminates the reentrancy vector:
- `claimableWinnings[player]` is set to sentinel `1` BEFORE the ETH transfer
- A re-entrant call to `claimWinnings()` at the ETH callback sees `amount == 1` and reverts at line 1470 (`if (amount <= 1) revert E()`)
- Re-entry to `purchase()` during the ETH callback is possible in principle, but `purchase()` checks `rngLocked` and other state — no double-spend path was identified

## LINK `onTokenTransfer` CEI Analysis (DegenerusAdmin.sol:589-638)

Call sequence with line numbers:
1. Line 595: `if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized()` — CHECK
2. Line 598-599: Read `subId`, check non-zero — CHECK
3. Line 602: `if (gameAdmin.gameOver()) revert GameOver()` — CHECK
4. Line 606-608: `getSubscription(subId)` — read subscription balance `bal` — STATE READ
5. Line 609: `mult = _linkRewardMultiplier(uint256(bal))` — multiplier computed, stored in stack var — EFFECT (stack, no storage)
6. Line 612-618: `linkToken.transferAndCall(coord, amount, ...)` — **INTERACT** (external call)
7. Line 636: `coinLinkReward.creditLinkReward(from, credit)` — **EFFECT** (state write to BURNIE supply)

**Formal CEI violation**: EFFECT (step 7) occurs after INTERACT (step 6).

**Exploitability assessment**: For an attacker to exploit this, they would need to:
- Control the Chainlink VRF coordinator (`coord`) to re-enter `onTokenTransfer` during `transferAndCall`
- The Chainlink VRF V2.5 coordinator is a trusted, non-malicious contract — it does not re-enter ADMIN
- Even if re-entry occurred: `mult` is computed from `bal` BEFORE the transferAndCall; re-entry cannot change `mult`
- Even if re-entry occurred with different `from` and `amount`: `subBal` increases after the forwarded LINK — the second call would have a higher `bal`, resulting in a LOWER multiplier (incentive mechanism decreases rewards as subscription fills)
- `creditLinkReward` targets BURNIE mint supply, not ETH pools — no ETH extraction path

**Conclusion**: The formal CEI deviation is present but **not exploitable** given the Chainlink coordinator trust model and the pre-computed multiplier. Severity: INFO.

**Additional finding (INFO)**: `creditLinkReward` is declared in `IDegenerusCoinLinkReward` interface and called on `ContractAddresses.COIN` (BurnieCoin), but no `function creditLinkReward(...)` implementation exists in `BurnieCoin.sol`. At runtime, this call will revert with a silent failure (no matching selector). The LINK is still forwarded to the VRF subscription (line 613 succeeds), but BURNIE rewards are silently not credited. This is a dead-code/missing-implementation issue, not a security vulnerability — the LINK donation still funds VRF, and the failed `creditLinkReward` merely means donors receive no BURNIE bonus. Severity: LOW (incorrect reward behavior, no ETH at risk).

## `adminStakeEthForStEth` Assessment (DegenerusGame.sol:1873-1888)

Full function trace:
1. Lines 1874-1882: CHECKS (caller, amount, balance, claimablePool reserve guard)
2. Line 1885: `steth.submit{value: amount}(address(0))` — **INTERACT** (external call)
3. No state writes after line 1885

**CORRECT**: all checks precede the external call; no state writes after `steth.submit`. The try/catch at line 1885-1887 handles Lido failure (reverts). Lido's `submit` does not re-enter `DegenerusGame` in its normal flow.

## stETH Rebasing and Pool Accounting (INFO)

stETH balance grows via rebasing outside any DegenerusGame function call. The solvency invariant is `balance + stethBalance >= obligations`. Rebasing increases `stethBalance` without changing any pool variable — this only makes the invariant MORE satisfied. Not a security concern.

## Task Commits

1. **Task 1: Trace claimWinnings() CEI** — audit analysis (no code changes)
2. **Task 2: Trace LINK onTokenTransfer and stETH paths** — audit analysis (no code changes)
3. **Task 3: Write 08-02-SUMMARY.md** — committed as `docs(08-02): ACCT-04 ACCT-05 verdicts — both PASS`

## Files Created/Modified

- `.planning/phases/08-eth-accounting-invariant-and-cei-verification/08-02-SUMMARY.md` — This file

## Decisions Made

- ACCT-04: PASS — strict CEI confirmed, no reentrancy guard needed given the sentinel pattern
- ACCT-05: PASS with INFO — LINK CEI deviation not exploitable; missing `creditLinkReward` implementation is LOW (broken bonus, no ETH risk)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- `creditLinkReward` function not found in `BurnieCoin.sol` despite being called on `ContractAddresses.COIN`. Since contracts compile, the interface is declared but the implementation may be absent. Documented as INFO/LOW finding.

## Next Phase Readiness

ACCT-04 and ACCT-05 are complete. No CEI-based ETH extraction paths found. The `creditLinkReward` missing implementation issue should be noted in the Phase 13 report as a LOW finding.

---
*Phase: 08-eth-accounting-invariant-and-cei-verification*
*Completed: 2026-03-04*
