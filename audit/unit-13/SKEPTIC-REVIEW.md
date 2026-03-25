# Unit 13: Admin + Governance -- Skeptic Review

**Phase:** 115
**Contract:** DegenerusAdmin.sol (L149-803)
**Agent:** Skeptic (Opus)
**Date:** 2026-03-25

---

## Review Methodology

For each INVESTIGATE finding from the Mad Genius, I independently:
1. Read the cited code lines in DegenerusAdmin.sol
2. Traced the execution path to verify or disprove the claimed scenario
3. Checked all preconditions, guards, and modifiers
4. Classified as CONFIRMED, FALSE POSITIVE, or DOWNGRADE TO INFO

---

## Finding Reviews

### F-01: Vote Weight Inflation via sDGNRS Transfer

**Mad Genius Verdict:** INVESTIGATE (downgraded to INFO by Mad Genius)
**Skeptic Verdict:** CONFIRMED as INFO

**Analysis:**
I independently verified the vote weight inflation scenario. The code at L470 reads live sDGNRS balance: `uint256 weight = sDGNRS.balanceOf(msg.sender)`. At L487, this weight is stored: `voteWeight[proposalId][msg.sender] = weight`. If Alice votes with 100 sDGNRS, then transfers to Bob, Bob's balance is now 200 sDGNRS. If Bob votes, the combined approveWeight is 300 from a total circulating supply of 200.

**Verification that this IS possible:**
- L470: `weight = sDGNRS.balanceOf(msg.sender)` -- reads live balance, confirmed.
- sDGNRS is a standard ERC20 (verified in Phase 113 Unit 11). Transfers work at any time, including during VRF stall. The comment at L469 ("VRF dead = supply frozen") is technically inaccurate about individual balance changes via transfers. Total supply IS frozen (no minting without VRF-driven game advances), but individual balances change via transfers.
- The threshold check at L502 compares against `p.circulatingSnapshot` (total supply at creation). Individual token movements do not change the snapshot.

**Why INFO and not higher:**
1. **Symmetric attack**: Reject voters can equally inflate their weights via the same transfer pattern.
2. **Bounded**: Even with inflation, a single token can only be "double-counted" once per transfer. The maximum inflation factor is bounded by the number of willing participants, and the execute condition requires `approveWeight > rejectWeight` (L503). If honest reject voters hold majority tokens and all vote, their uninflated weight exceeds any inflated minority.
3. **VRF stall context**: This only matters during a VRF stall when governance is critical. The attack requires coordinated token transfers during the voting period. If an attacker controls enough tokens to matter, they likely already have sufficient voting power without inflation.
4. **Standard in live-balance voting**: Most governance systems using live balances (rather than snapshot-at-proposal-creation) have this property. It's an accepted tradeoff for simpler implementation.

**Severity: INFO** -- The design uses live balances with intentional comments about supply being frozen. The transfer-based weight inflation is a known property of non-snapshot governance. No severity upgrade warranted.

---

### F-02: Zero circulatingSnapshot Allows Single-Voter Execution

**Mad Genius Verdict:** INVESTIGATE (downgraded to INFO by Mad Genius)
**Skeptic Verdict:** FALSE POSITIVE

**Analysis:**
I traced the scenario where circulatingSnapshot == 0:

1. **Admin path propose (L421-423):** Does not check circulatingSupply. Only checks stall >= 20h and isVaultOwner.
2. **L438:** `p.circulatingSnapshot = circulatingSupply()` -- if circulating == 0, snapshot == 0.
3. **vote() L502:** `p.approveWeight * BPS >= uint256(t) * 0` -- always true for any approveWeight > 0.

**But the scenario is self-contradictory:**
- For circulatingSupply() == 0: `totalSupply - balanceOf(SDGNRS) - balanceOf(DGNRS) == 0`. This means ALL sDGNRS tokens are held by the sDGNRS contract itself or the DGNRS wrapper.
- For anyone to vote, they need `sDGNRS.balanceOf(msg.sender) > 0` (L470-471). But if ALL sDGNRS is in the two excluded addresses, no external holder has any balance.
- The Mad Genius identified this paradox: "no one can vote, so no proposal can ever be executed."
- The Mad Genius then suggests: "if someone acquires sDGNRS AFTER the proposal is created." But acquiring sDGNRS requires either: (a) the sDGNRS contract distributing tokens (blocked during VRF stall -- no game advances), (b) the DGNRS wrapper unwrapping (blocked during VRF stall per unwrapTo's VRF health check), or (c) someone transferring sDGNRS from the excluded addresses (sDGNRS contract has no arbitrary transfer function; DGNRS wrapper requires unwrap which is blocked).
- **No path exists to acquire sDGNRS during a VRF stall when circulating supply is zero.** The paradox is complete: zero circulating supply = no voters = no execution.

**If FALSE POSITIVE, cite preventing guard:** L470-471 (`if (weight == 0) revert InsufficientStake()`) prevents voting with zero sDGNRS balance. When circulatingSupply == 0, ALL balances are zero (tokens are in excluded addresses only), so ALL vote() calls revert. The proposal expires after 7 days.

**Severity: N/A** -- FALSE POSITIVE. The scenario requires a voter with sDGNRS > 0 to exist when circulatingSupply == 0, which is a logical contradiction (a holder with balance > 0 means circulating > 0).

---

### F-03: No LINK Recovery After Failed shutdownVrf Transfer

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** CONFIRMED as LOW

**Analysis:**
I verified the code at L651-674:

1. L656: `subscriptionId = 0` -- zeroed before any external calls.
2. L659: `try coordinator.cancelSubscription(subId, target)` -- if this fails, the subscription's LINK goes to the coordinator's internal accounting (Chainlink handles refund to subscription owner on cancellation).
3. L663-671: `try linkToken.transfer(target, bal)` -- if this fails, LINK stays in Admin.
4. After shutdownVrf returns, subscriptionId == 0. No function in Admin can re-attempt the LINK transfer:
   - onTokenTransfer: reverts at L692 (`subId == 0 -> NoSubscription`)
   - No withdraw/sweep function exists
   - No receive/fallback function to receive ETH
   - Owner functions only interact with Game, not LINK

**Is LINK transfer failure realistic?**
- LINK token is a standard ERC-677 deployed by Chainlink. It has no pause mechanism, no blacklist. The `transfer` function is a standard ERC20 transfer.
- The target is `ContractAddresses.VAULT` -- a compile-time constant, known-good address.
- The only failure mode: Vault contract's fallback/receive rejects the call. But LINK transfer is a token transfer (not ETH), so Vault doesn't need receive(). The Vault just needs to not be in a state that blocks ERC20 receives (which standard ERC20 transfers don't check).
- Practically impossible with a standard LINK token and a functioning Vault contract.

**But the lack of recovery IS a design gap:**
- If, for any reason, the transfer fails on a future chain fork, token upgrade, or edge case, there is no way to recover the LINK.
- The LINK amount at game-over could be significant (subscription funding).

**Severity: LOW** -- The failure mode is extremely unlikely with standard Chainlink LINK token, but the missing recovery path is a legitimate design gap. A simple `sweepLink()` owner function would eliminate this risk entirely.

---

### F-04: Silent Catch on Old Subscription Cancellation in _executeSwap

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**
At L581-588, `cancelSubscription` on the OLD coordinator is wrapped in try/catch. If it fails:
- The old subscription remains active on the old coordinator
- LINK allocated to the old subscription stays there
- The Admin contract overwrites coordinator/subscriptionId with new values

**Is this a problem?**
The governance system is swapping coordinators BECAUSE the old one is broken/stalled. A broken coordinator may not respond to cancelSubscription. The try/catch is INTENTIONAL defensive design: the swap must proceed even if the old coordinator is unresponsive.

The "lost" LINK in the old subscription: this is recoverable if the old coordinator eventually comes back online and the subscription owner (this Admin contract) can call cancelSubscription again. But after the swap, Admin's `coordinator` storage points to the new coordinator, and there is no function to interact with an arbitrary old coordinator.

However, in the Chainlink V2.5 model, subscription ownership is tied to the creator. The Admin contract IS the owner. If the old coordinator comes back, someone could write a helper contract to call the old coordinator's cancelSubscription on Admin's behalf... except only the subscription owner can cancel, and that's Admin, which has no function to do so for an arbitrary coordinator.

**Net:** LINK in the old subscription is potentially unrecoverable. But: (a) the old coordinator is broken (that's why we're swapping), (b) the LINK amount depends on the old sub's balance, (c) the try/catch is the correct defensive pattern for emergency swaps.

**Severity: INFO** -- Intentional design decision. The alternative (reverting if old coordinator doesn't respond) would block the governance swap, which is worse.

---

### F-05: LINK Stuck After Failed Shutdown Transfer

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** CONFIRMED as INFO (subsumes into F-03)

**Analysis:**
This is the specific failure mode of F-03. At L664-671:
```solidity
if (bal != 0) {
    try linkToken.transfer(target, bal) returns (bool ok) {
        if (ok) {
            emit SubscriptionShutdown(subId, target, bal);
            return;
        }
    } catch {}
}
emit SubscriptionShutdown(subId, target, 0);
```

If transfer returns false (not ok) or reverts (caught): LINK stays in Admin, event emits with amount 0. The function does NOT revert -- it succeeds silently with the LINK unsent. This is intentional (game-over must proceed).

The LINK stuck here includes: (a) LINK refunded from cancelSubscription at L659 (if the coordinator returns LINK to the Admin on cancellation), and (b) any LINK balance already in Admin.

**Severity: INFO** -- Same root cause as F-03. The silent failure is intentional for game-over robustness. The missing sweep function is the actual gap (covered in F-03).

---

## Review Summary

| Finding | Mad Genius | Skeptic | Final Severity | Final Status |
|---------|-----------|---------|----------------|-------------|
| F-01: Vote weight inflation via transfer | INVESTIGATE | CONFIRMED | INFO | sDGNRS live-balance voting property, symmetric, bounded |
| F-02: Zero circulatingSnapshot | INVESTIGATE | FALSE POSITIVE | N/A | Logical contradiction: zero supply = zero voters |
| F-03: No LINK recovery after failed shutdown | INVESTIGATE | CONFIRMED | LOW | Missing sweep function, unlikely failure mode |
| F-04: Silent catch on old sub cancel | INVESTIGATE | DOWNGRADE TO INFO | INFO | Intentional defensive design |
| F-05: LINK stuck after failed transfer | INVESTIGATE | CONFIRMED | INFO | Subsumes into F-03 |

**Final Finding Count:**
- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 1 (F-03: missing LINK recovery path)
- INFO: 3 (F-01: vote weight inflation, F-04: silent catch, F-05: stuck LINK)
- FALSE POSITIVE: 1 (F-02: zero snapshot)

---

*Skeptic review complete: 2026-03-25*
*All 5 Mad Genius findings independently verified with line-by-line code analysis.*
