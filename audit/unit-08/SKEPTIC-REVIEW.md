# Unit 8: Degenerette Betting -- Skeptic Review

**Agent:** Skeptic
**Target:** DegenerusGameDegeneretteModule.sol (1,179 lines)
**Input:** ATTACK-REPORT.md findings F-01, F-03, F-05 (INVESTIGATE verdicts)
**Methodology:** Independent code reading, execution path tracing, precondition verification

---

## Finding Reviews

### F-01: ETH Claimable Pull Uses `<=` Instead of `<`

**Mad Genius Verdict:** INVESTIGATE (LOW)
**Skeptic Verdict:** CONFIRMED (LOW)

**Independent Analysis:**

I read `_collectBetFunds` at lines 541-574. The relevant code at L549-554:

```solidity
if (ethPaid > totalBet) revert InvalidBet();
if (ethPaid < totalBet) {
    uint256 fromClaimable = totalBet - ethPaid;
    if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();
    claimableWinnings[player] -= fromClaimable;
    claimablePool -= fromClaimable;
}
```

The check `claimableWinnings[player] <= fromClaimable` means the player must have STRICTLY MORE than the required amount in their claimable balance. When `ethPaid = 0` and `totalBet = claimableWinnings[player]`, the condition `claimableWinnings <= totalBet` evaluates to TRUE and the bet reverts.

**Trace of exact-balance scenario:**
1. Player has `claimableWinnings[player] = 0.1 ether`
2. Player calls `placeFullTicketBets` with `msg.value = 0`, `amountPerTicket = 0.01 ether`, `ticketCount = 10` (totalBet = 0.1 ether)
3. `ethPaid (0) < totalBet (0.1e18)` -> enters claimable pull block
4. `fromClaimable = 0.1e18 - 0 = 0.1e18`
5. `claimableWinnings[player] (0.1e18) <= fromClaimable (0.1e18)` -> TRUE -> reverts

The player cannot use their exact full claimable balance. They need at least 1 wei more.

**Is this intentional?** Possibly. Using `<=` instead of `<` guarantees that `claimableWinnings[player]` remains non-zero after the deduction. This prevents a state where a player fully drains their claimable via a bet. However, it also means a player cannot efficiently use all their winnings for a new bet without adding 1 wei of msg.value.

Looking at the subtraction at L553: `claimableWinnings[player] -= fromClaimable`. If the check were `<` instead of `<=`, and `claimableWinnings == fromClaimable`, the subtraction would result in 0. This is a valid state. No invariant prevents claimableWinnings from being 0.

**Impact:** A player with X claimable ETH cannot place a bet costing exactly X from claimable alone. They must either:
- Send at least 1 wei as msg.value (reducing fromClaimable to X-1, so claimable > X-1)
- Place a slightly smaller bet

This is a LOW severity usability issue, not a funds-at-risk bug.

**Severity:** LOW -- user can work around it by sending 1 wei or placing a slightly smaller bet.

---

### F-03: ETH Bet Resolution Blocked During prizePoolFrozen

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** CONFIRMED (INFO)

**Independent Analysis:**

I read `_distributePayout` at L680-715. The guard at L685:

```solidity
if (prizePoolFrozen) revert E();
```

This blocks ALL ETH payout distributions when `prizePoolFrozen` is true. The flag is set during `advanceGame` in the AdvanceModule when jackpot math is in progress.

**Duration of freeze:** The `prizePoolFrozen` flag is set and cleared within a single `advanceGame` transaction. It is never left true across transactions. Therefore, the block on ETH resolution is transient -- lasting only for the duration of the advanceGame call in the same block.

**Can an attacker exploit this?** No. The freeze occurs during `advanceGame` which is called by anyone (external, permissionless). If advanceGame is called in block N, the freeze exists only during that call. Any `resolveBets` call in the same block but in a different transaction would not see the freeze (it's already cleared). A `resolveBets` call within the same transaction as `advanceGame` would only happen via a contract that calls both, and such a contract would see the freeze.

**Practical impact:** Essentially zero. The freeze is within a single transaction's execution. External callers never see a frozen state between transactions.

**Additional note:** BURNIE and WWXRP resolutions are unaffected by the freeze (they don't touch prize pools).

**Severity:** INFO -- by design, no practical impact. The freeze is transient within a single transaction.

---

### F-05: uint128 Cast Truncation on totalBet Pool Addition

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** FALSE POSITIVE

**Independent Analysis:**

The code at L560 and L563:
```solidity
_setPendingPools(pNext, pFuture + uint128(totalBet));
_setPrizePools(next, future + uint128(totalBet));
```

`totalBet = uint256(amountPerTicket) * uint256(ticketCount)` (L479). `amountPerTicket` is uint128 (max 3.4e38). `ticketCount` max 10. So `totalBet` max = 3.4e38 * 10 = 3.4e39, which exceeds uint128.max (3.4e38).

**However:** For the truncation to actually occur, `amountPerTicket` must be > uint128.max / 10 = 3.4e37. In ETH terms, that's 3.4e19 ETH, roughly 34 quintillion ETH. The total Ether supply is ~120 million ETH (~1.2e26 wei). So `amountPerTicket` in wei cannot exceed ~1.2e26, and `totalBet` cannot exceed 1.2e27. Both fit comfortably in uint128.

For BURNIE and WWXRP: same argument. No token has a supply anywhere close to uint128.max / 10.

**Precondition for truncation is economically impossible.** The cast is always safe in practice.

**Why FALSE POSITIVE and not INFO?** The Mad Genius raised this as a theoretical concern. But the impossibility of the precondition is not just "unlikely" -- it is mathematically provable from the total ETH supply. A finding that requires more ETH than exists is not a finding at all. It cannot be exploited under any circumstances.

---

## Summary

| ID | Mad Genius Verdict | Skeptic Verdict | Severity |
|----|-------------------|-----------------|----------|
| F-01 | INVESTIGATE (LOW) | CONFIRMED (LOW) | LOW |
| F-02 | SAFE | -- (not reviewed, already SAFE) | -- |
| F-03 | INVESTIGATE (INFO) | CONFIRMED (INFO) | INFO |
| F-04 | SAFE | -- (not reviewed, already SAFE) | -- |
| F-05 | INVESTIGATE (INFO) | FALSE POSITIVE | -- |
| F-06 | SAFE | -- (not reviewed, already SAFE) | -- |

**CONFIRMED findings:** 2 (F-01 LOW, F-03 INFO)
**FALSE POSITIVE:** 1 (F-05 -- economically impossible precondition)
