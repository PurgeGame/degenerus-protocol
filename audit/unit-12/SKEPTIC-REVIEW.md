# Unit 12: Vault + WWXRP -- Skeptic Review

**Phase:** 114
**Agent:** Skeptic (Opus)
**Date:** 2026-03-25
**Input:** ATTACK-REPORT.md (Mad Genius)

---

## Review Methodology

The Mad Genius reported ZERO VULNERABLE or INVESTIGATE findings. Per the Skeptic mandate, I must independently verify the 4 areas the Mad Genius flagged for review, plus perform my own adversarial analysis on the highest-risk functions. I read every cited code section myself and traced execution paths independently.

---

## Area 1: burnEth Reentrancy via _payEth (L1032)

**Mad Genius Claim:** CEI is followed -- shares are burned at L867 before _payEth at L875. Reentrancy produces correct results.

**Skeptic Independent Verification:**

I read _burnEthFor (L833-876) line by line. Execution order:
1. L840: Read balances (ethBal, stBal, combined) -- view calls
2. L841-848: Read claimable -- view call
3. L849-851: Compute supplyBefore, reserve, claimValue -- pure arithmetic
4. L853-857: CONDITIONAL external call (claimWinnings) + balance refresh
5. L859-865: Compute ethOut/stEthOut -- pure arithmetic
6. L867: **share.vaultBurn(player, amount)** -- STATE CHANGE (shares burned)
7. L868-870: Conditional refill -- STATE CHANGE
8. L872: emit Claim -- EVENT
9. L874: _paySteth -- EXTERNAL CALL (stETH transfer)
10. L875: _payEth -- EXTERNAL CALL (ETH transfer via .call)

CEI ordering: Checks (L838-865) -> Effects (L867-872) -> Interactions (L874-875). **CONFIRMED CORRECT.**

At the point of _payEth (L875/L1032), all state changes are complete:
- Shares burned (totalSupply and balanceOf updated)
- Refill minted if applicable
- Claim event emitted

If player reenters burnEth:
- share.totalSupply() returns the POST-burn value
- address(this).balance is POST-ethOut (reduced)
- steth.balanceOf is POST-stEthOut (reduced)
- Fresh computation uses updated state

The only scenario where reentrancy could cause unexpected behavior is if between _paySteth (L874) and _payEth (L875), the stETH transfer callback triggers a reentrant call. In this case:
- ethOut worth of ETH has NOT yet been sent (happens at L875)
- But ethOut is a local variable, already computed
- address(this).balance still includes ethOut
- A reentrant burnEth call would see the full ETH balance (hasn't been sent yet)
- The reentrant call would compute its own claimValue and ethOut based on the current state (shares already reduced from first call)
- This could over-spend ETH if the vault doesn't have enough after both calls

**INVESTIGATE deeper:** After stETH transfer at L874 but before ETH transfer at L875:
- Vault's ETH balance = original ethBal (minus any ETH sent by claimWinnings callback, but claimWinnings ADDS to balance)
- Reentrant call reads address(this).balance = includes first call's ethOut (not yet sent)
- Reentrant call computes its claimValue based on remaining shares and current reserve
- Reentrant call tries to send ethOut2 of ETH
- First call then tries to send ethOut1 of ETH
- Total ETH sent = ethOut1 + ethOut2. Does the vault have enough?

The key question: after the first call's vaultBurn at L867, totalSupply decreased by `amount`. The reentrant call's claimValue is `(reserve' * amount2) / supplyAfterFirstBurn`. But reserve' at this point is `ethBal_current + stBal_current + claimable`. ethBal_current still includes the first call's ethOut (not sent yet). So the reentrant call "sees" ETH that the first call is about to send.

However: the first call already burned its shares. The reentrant call uses the updated totalSupply. The proportional math works correctly because:
- supplyAfterFirstBurn = supplyBefore - amount1
- reentrant claimValue = (reserve * amount2) / (supplyBefore - amount1)
- But reserve still includes first call's ethOut

This means the reentrant call gets a slightly larger share than it should, because the reserve hasn't been reduced by the first call's payment yet.

**Wait.** Let me re-examine. The reserve used in the reentrant call is computed from live balance reads: `ethBal = address(this).balance` (which still holds the first call's ethOut) plus stBal (already reduced by stEthOut from L874). So the reentrant call's reserve = (ethBal_including_first_ethOut) + (stBal_after_first_stEthOut) + claimable.

The first call committed to sending ethOut1. If the reentrant call also computes a nonzero ethOut2, and both succeed, the vault sent ethOut1 + ethOut2 + stEthOut1 + stEthOut2. The vault balance must cover this.

But: does the math ensure this? The first call: claimValue1 = (reserve * amount1) / supply. The reentrant call: claimValue2 = (reserve' * amount2) / (supply - amount1). Where reserve' = ethBal + stBal_after_stEthOut1 + claimable'.

For this to be exploitable, the attacker needs stETH to trigger a callback. Lido's stETH is an ERC20 without transfer hooks (no ERC777 callbacks). The steth.transfer at L1040 is a standard ERC20 transfer. **Standard Lido stETH does NOT have transfer callbacks.** Therefore, L874 (_paySteth) does not transfer execution control.

The only external call that transfers execution control is _payEth at L875 (low-level .call). At this point, stETH has already been sent. A reentrant call from the ETH transfer:
- Reads ethBal = address(this).balance (now reduced by ethOut from first call -- because .call SENDS the ETH before running the recipient's fallback)
- Reads stBal = reduced by stEthOut from first call
- Supply is reduced by amount from first call's vaultBurn
- Math is proportionally correct with the reduced state

**VERDICT: CONFIRMED SAFE.** The .call at L1032 transfers ETH (reducing balance) BEFORE the callback executes. So the reentrant call sees the post-transfer balance. Combined with shares already burned, the math is correct. And stETH has no transfer hooks.

---

## Area 2: donate Ordering (L318 vs L323)

**Mad Genius Claim:** External call before storage write is safe because untracked wXRP cannot be extracted.

**Skeptic Independent Verification:**

I read donate (L314-326):
- L318: wXRP.transferFrom(msg.sender, address(this), amount) -- EXTERNAL CALL
- L323: wXRPReserves += amount -- STATE UPDATE

The ordering violates CEI. During the transferFrom callback (if wXRP has hooks):
- wXRP tokens are now in the WWXRP contract
- wXRPReserves has NOT been incremented

Can the attacker extract value during this window?
- unwrap: requires wXRPReserves >= amount. Reserves haven't been incremented. Can only unwrap up to the OLD reserves value. The extra wXRP is invisible to unwrap.
- donate (reentrant): would transfer more wXRP, still not increment reserves until each donate finishes.
- Any other function? No other function reads wXRP.balanceOf(address(this)). All wXRP accounting goes through wXRPReserves.

**VERDICT: CONFIRMED SAFE.** Even though CEI is technically violated, the untracked wXRP surplus cannot be extracted because unwrap is gated by wXRPReserves, not by actual wXRP balance. The surplus is effectively locked until wXRPReserves is incremented at L323.

**Classification:** INFO -- the ordering could be improved for best practice (move transferFrom after reserves increment, or use a reentrancy guard), but it is not exploitable given the current code. Not worth reporting as a finding because wXRP (standard ERC20) has no transfer hooks.

---

## Area 3: Refill + Immediate Re-burn

**Mad Genius Claim:** Safe because re-burning user gets proportional share of remaining reserves.

**Skeptic Independent Verification:**

Scenario: User holds ALL DGVB shares. Burns all shares.
- supplyBefore = X (whatever the current supply is)
- coinBal = total BURNIE reserves
- coinOut = (coinBal * X) / X = coinBal -- gets ALL reserves
- vaultBurn: totalSupply = 0
- Refill: totalSupply = 1T*1e18, balanceOf[user] = 1T*1e18
- Payment waterfall pays out coinBal to user

Now user calls burnCoin again with all 1T shares:
- _syncCoinReserves: reads fresh allowance. If previous call used vaultMintTo for some of the payout, allowance is now LOWER.
- coinBal = new allowance (lower) + vaultBal (maybe 0) + claimable (maybe 0)
- coinOut = (coinBal * 1T) / 1T = coinBal -- gets ALL remaining reserves

Is this a problem? No -- the user is the ONLY shareholder. They're entitled to 100% of reserves. The reserves are genuinely lower after the first burn paid out.

**Edge case:** What if another user deposits between the two burns?
- Only GAME can deposit (onlyGame). So this requires a game deposit transaction between the two burns.
- After deposit, reserves increase. User holds 1T shares (100%). They'd get the new deposit too.
- But deposits don't mint new shares -- the existing 1T shares absorb the deposit.
- This is INTENDED -- the refill holder controls 100% of the share class.

**Could an attacker exploit refill to steal deposits?**
1. Attacker acquires all DGVB shares (requires buying from all holders).
2. Burns all shares -- gets all reserves + refill.
3. New game deposit increases reserves.
4. Attacker burns refill shares -- gets the new deposit.

This requires the attacker to OWN all shares first. They're already the sole beneficiary. No theft from others is possible because there are no other shareholders.

**VERDICT: CONFIRMED SAFE.** Refill mechanism cannot be weaponized against other shareholders because it only triggers when ALL shares are burned (meaning the burner is the sole shareholder).

---

## Area 4: _syncCoinReserves Accuracy

**Mad Genius Claim:** Always reads fresh from coinToken, no permanent stale state.

**Skeptic Independent Verification:**

I read _syncCoinReserves (L980-983):
```
synced = coinToken.vaultMintAllowance()
coinTracked = synced
return synced
```

Called from:
1. deposit (L456) -- syncs before adding new escrow
2. _burnCoinFor (L766) -- syncs before computing reserves

Between calls, coinTracked could drift if:
- BurnieCoin's vault mint allowance changes externally (e.g., another contract calls vaultMintTo)
- BUT: only the vault itself calls vaultMintTo on BurnieCoin (via the vault's _burnCoinFor at L799). The vault controls its own allowance consumption.

Actually, let me check: does BurnieCoin's vaultMintTo reduce the allowance? Looking at the IVaultCoin interface, vaultMintTo is called by the vault to mint BURNIE to a player. This reduces the mint allowance on the BurnieCoin side. The vault then decrements coinTracked at L798. On the next _syncCoinReserves call, coinTracked re-syncs.

Is there a path where someone else reduces the vault's mint allowance? The vault allowance on BurnieCoin is specific to the vault contract. Only the vault can call vaultMintTo (access-controlled on BurnieCoin side). So only the vault can reduce its own allowance.

**What about vaultEscrow?** deposit calls coinToken.vaultEscrow(coinAmount) which INCREASES the allowance. Then coinTracked += coinAmount at L458. Between _syncCoinReserves (L456) and the increment (L458), the escrow call at L457 has already increased the allowance on BurnieCoin. But coinTracked was just synced to the PRE-escrow value. Then L458 adds coinAmount. So coinTracked = pre-escrow allowance + coinAmount = post-escrow allowance. Consistent.

**VERDICT: CONFIRMED SAFE.** coinTracked stays consistent because: (1) _syncCoinReserves re-reads on every entry point, (2) only the vault itself modifies the allowance, (3) deposit properly syncs before escrow + increment.

---

## Independent Skeptic Analysis: Additional Areas

### A. Vault Owner Threshold Manipulation

The `onlyVaultOwner` modifier checks `balance * 1000 > supply * 501` at L418. This means >50.1% of DGVE supply.

**Can ownership be manipulated within a single transaction?**
A contract could:
1. Receive DGVE via transfer
2. Call a vault function (passes onlyVaultOwner)
3. Return DGVE

This requires a willing DGVE holder to: (a) transfer shares to the attacker's contract, (b) the contract acts as vault owner, (c) contract returns shares.

But: this is just delegation. The DGVE holder is choosing to delegate vault-owner actions. They could do the same actions directly. Not an attack -- it's the holder's prerogative.

**Flash loan DGVE?** DegenerusVaultShare has no flash loan functionality. No ERC-3156 flash mint. No flash borrow. The only way to temporarily hold DGVE is through a regular transfer, which requires the sender to willingly give up their shares (even temporarily).

**VERDICT: SAFE.** No flash-loan vector. Delegation via transfer is a holder's choice, not an exploit.

### B. View Function Accuracy for Frontends

previewCoin, previewEth, previewBurnForCoinOut, previewBurnForEthOut are view functions. They can diverge from actual burn results if state changes between the preview call and the burn transaction. This is standard in DeFi (same issue with AMM quotes). Not a vulnerability -- callers should use slippage protection.

**VERDICT: INFO** -- standard preview-vs-execution divergence. Not a finding.

### C. stETH Rebase in _syncEthReserves

stETH rebases daily, changing balances. _syncEthReserves reads `steth.balanceOf(address(this))` which reflects the latest rebase. Since the vault uses live balance reads (not cached), rebases are automatically reflected. Positive rebases increase DGVE backing (good for holders). Negative rebases (slashing) decrease it.

**VERDICT: SAFE.** Live balance reads handle rebases correctly.

### D. burnCoin Rounding Direction Verification

`coinOut = (coinBal * amount) / supplyBefore` at L773.

Solidity integer division truncates (rounds down). This means the vault KEEPS the dust. Example: coinBal=100, amount=3, supplyBefore=7. coinOut = 300/7 = 42 (not 42.857). Vault retains 0.857-equivalent. This is correct -- rounding should favor the pool, not the withdrawer.

**VERDICT: SAFE.** Rounding favors the vault (correct direction for all users).

### E. Multiple Share Class Independence

DGVB and DGVE are independent share tokens with independent supplies. Burning DGVB does not affect DGVE reserves or supply, and vice versa. The vault correctly separates:
- ETH + stETH -> DGVE claims
- BURNIE mint allowance (+ balance + claimable) -> DGVB claims

Cross-contamination would be: burning DGVB to get ETH, or burning DGVE to get BURNIE. I verified:
- burnCoin only pays BURNIE (L786, L793, L799). Never sends ETH.
- burnEth only pays ETH/stETH (L874-875). Never mints BURNIE.

**VERDICT: SAFE.** Share classes are properly isolated.

---

## Findings Summary

**ZERO VULNERABLE findings from Mad Genius report (no findings to validate).**

**Skeptic independently verified all 4 flagged areas: all CONFIRMED SAFE.**

**Skeptic independent analysis found ZERO additional vulnerabilities.**

| Area | Mad Genius Verdict | Skeptic Verdict | Final |
|------|-------------------|-----------------|-------|
| burnEth reentrancy | SAFE | CONFIRMED SAFE | SAFE |
| donate ordering | SAFE | CONFIRMED SAFE (INFO) | SAFE |
| Refill + re-burn | SAFE | CONFIRMED SAFE | SAFE |
| _syncCoinReserves | SAFE | CONFIRMED SAFE | SAFE |
| Vault owner manipulation | (not flagged) | SAFE | SAFE |
| View function accuracy | (not flagged) | INFO | INFO |
| stETH rebase | (not flagged) | SAFE | SAFE |
| Rounding direction | (not flagged) | SAFE | SAFE |
| Share class independence | (not flagged) | SAFE | SAFE |

---

## Skeptic Final Verdict

**The Mad Genius report is thorough and accurate.** All SAFE verdicts are independently confirmed. The contracts follow correct patterns (CEI, proper access control, correct math, no stale caches). No findings to escalate.

The only observation worth noting (INFO level) is the donate function's external-call-before-state-update ordering, which while technically a CEI violation, is not exploitable given the wXRPReserves gating mechanism on unwrap.
