# Unit 11: sDGNRS + DGNRS -- Taskmaster Coverage Review

**Reviewer:** Taskmaster (per ULTIMATE-AUDIT-DESIGN.md)
**Date:** 2026-03-25
**Method:** Independent function scan of both contracts, cross-reference against COVERAGE-CHECKLIST.md and ATTACK-REPORT.md

---

## Independent Function Scan

### StakedDegenerusStonk.sol -- Functions Found

I scanned every function declaration in the contract:

| # | Function | Visibility | In Checklist? | In Attack Report? |
|---|----------|-----------|--------------|-------------------|
| 1 | constructor() | - | YES | YES (constructor analysis) |
| 2 | receive() payable | external | YES (B10) | YES |
| 3 | wrapperTransferTo() | external | YES (B8) | YES |
| 4 | gameAdvance() | external | YES (B11) | YES |
| 5 | gameClaimWhalePass() | external | YES (B12) | YES |
| 6 | depositSteth() | external | YES (B9) | YES |
| 7 | poolBalance() | external view | YES (D4) | YES (view notes) |
| 8 | transferFromPool() | external | YES (B5) | YES |
| 9 | transferBetweenPools() | external | YES (B6) | YES |
| 10 | burnRemainingPools() | external | YES (B7) | YES |
| 11 | burn() | external | YES (B1) | YES |
| 12 | burnWrapped() | external | YES (B2) | YES |
| 13 | hasPendingRedemptions() | external view | YES (D2) | YES (view notes) |
| 14 | resolveRedemptionPeriod() | external | YES (B4) | YES |
| 15 | claimRedemption() | external | YES (B3) | YES |
| 16 | previewBurn() | external view | YES (D1) | YES (view notes) |
| 17 | burnieReserve() | external view | YES (D3) | YES (view notes) |
| 18 | _submitGamblingClaim() | private | YES (trivial wrapper) | YES (traced in B1 call tree) |
| 19 | _submitGamblingClaimFrom() | private | YES (C2) | YES (standalone MULTI-PARENT) |
| 20 | _deterministicBurn() | private | YES (trivial wrapper) | YES (traced in B1 call tree) |
| 21 | _deterministicBurnFrom() | private | YES (C1) | YES (standalone MULTI-PARENT) |
| 22 | _payEth() | private | YES (C3) | YES (traced in B3 call tree) |
| 23 | _payBurnie() | private | YES (C4) | YES (traced in B3 call tree) |
| 24 | _claimableWinnings() | private view | YES (D5) | YES (view notes) |
| 25 | _poolIndex() | private pure | YES (D6) | YES (implicit in pool functions) |
| 26 | _mint() | private | YES (C5) | YES (constructor analysis) |

**sDGNRS: 26/26 functions covered. No gaps.**

### DegenerusStonk.sol -- Functions Found

| # | Function | Visibility | In Checklist? | In Attack Report? |
|---|----------|-----------|--------------|-------------------|
| 1 | constructor() | - | YES | YES (constructor analysis) |
| 2 | receive() payable | external | YES (B19) | YES |
| 3 | transfer() | external | YES (B16) | YES |
| 4 | transferFrom() | external | YES (B17) | YES |
| 5 | approve() | external | YES (B18) | YES |
| 6 | unwrapTo() | external | YES (B14) | YES |
| 7 | burn() | external | YES (B13) | YES |
| 8 | previewBurn() | external view | YES (D7) | YES (view notes, delegates to sDGNRS) |
| 9 | _transfer() | private | YES (C6) | YES (standalone MULTI-PARENT) |
| 10 | _burn() | private | YES (C7) | YES (standalone MULTI-PARENT) |
| 11 | burnForSdgnrs() | external | YES (B15) | YES |

**DGNRS: 11/11 functions covered. No gaps.**

---

## Coverage Verification Matrix

### Call Trees

| Function | Call Tree Present? | Fully Expanded? | Notes |
|----------|--------------------|-----------------|-------|
| B1 burn | YES | YES | Both deterministic and gambling paths traced |
| B2 burnWrapped | YES | YES | Cross-contract call to DGNRS.burnForSdgnrs traced |
| B3 claimRedemption | YES | YES | All conditional paths (gameOver, flipResolved, lootbox) traced |
| B4 resolveRedemptionPeriod | YES | YES | No external calls, simple tree |
| B5 transferFromPool | YES | YES | Internal only |
| B6 transferBetweenPools | YES | YES | Internal only |
| B7 burnRemainingPools | YES | YES | Internal only |
| B8 wrapperTransferTo | YES | YES | Internal only |
| B9 depositSteth | YES | YES | Single external call |
| B10 receive | YES | YES | No calls |
| B11 gameAdvance | YES | YES | Single proxy call |
| B12 gameClaimWhalePass | YES | YES | Single proxy call |
| B13 DGNRS.burn | YES | YES | Cross-contract to sDGNRS.burn traced |
| B14 unwrapTo | YES | YES | VRF guard + cross-contract traced |
| B15 burnForSdgnrs | YES | YES | Internal only |
| B16 transfer | YES | YES | Delegates to _transfer |
| B17 transferFrom | YES | YES | Allowance + _transfer |
| B18 approve | YES | YES | Single storage write |
| B19 DGNRS.receive | YES | YES | Access check only |
| C1 _deterministicBurnFrom | YES | YES | MULTI-PARENT analysis complete |
| C2 _submitGamblingClaimFrom | YES | YES | MULTI-PARENT analysis complete |
| C6 _transfer | YES | YES | MULTI-PARENT analysis complete |
| C7 _burn | YES | YES | MULTI-PARENT analysis complete |

**23/23 call trees present and fully expanded.**

### Storage Write Maps

| Function | Storage Map Present? | Complete? | Notes |
|----------|---------------------|-----------|-------|
| B1-B19 | YES | YES | All storage writes listed with line numbers |
| C1-C2 | YES | YES | MULTI-PARENT storage writes from both callers documented |
| C6-C7 | YES | YES | Simple storage writes documented |

**All storage write maps present and complete.**

### Cached-Local-vs-Storage Checks

| Function | Cache Check Present? | Complete? | Notes |
|----------|---------------------|-----------|-------|
| B1 | YES | YES | bal, supplyBefore, ethBal all verified |
| B2 | YES | YES | Cross-contract cache verified |
| B3 | YES | YES | roll, claimPeriodIndex, claimActivityScore, totalRolledEth, ethDirect all verified |
| B4 | YES | YES | period, rolledEth verified |
| B5-B8 | YES | YES | available/bal caches verified |
| B9-B12 | YES | YES (trivial) | No cached locals |
| B13-B19 | YES | YES | bal, allowed caches verified |
| C1-C2 | YES | YES | MULTI-PARENT divergence analysis included |

**All cached-local-vs-storage checks present.**

---

## Interrogation Questions

### Q1: _payEth stETH fallback path
"In _payEth (L772-794), you traced the stETH fallback at L786-792. But you didn't analyze what happens if the game.claimWinnings() call at L778 sends LESS ETH than expected (e.g., game has a minimum withdrawal). Does the stETH fallback handle this correctly?"

**Answer (from attack report B3):** claimWinnings is documented to send the full claimable amount (minus 1 wei dust). After claimWinnings, ethBal is re-read at L779. If ethBal is still < amount, the stETH fallback engages. The fallback computes stethOut = amount - ethBal, which is correct regardless of how much ETH was recovered. **Verified: COMPLETE.**

### Q2: resolveRedemptionPeriod roll range
"You noted roll range is 25-175 but only checked the game trust assumption. What if the game passes roll=0? The math at L547 produces rolledEth=0, and L548 sets pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + 0 = effectively releasing all base. But redemptionPeriods[period].roll = 0, which is the 'unresolved' sentinel. Players calling claimRedemption would get NotResolved at L579."

**Answer (from attack report B4):** This is noted -- if game passes roll=0, the period is "resolved" from sDGNRS's accounting perspective (bases zeroed) but claimRedemption would revert because roll=0 is the unresolved sentinel. Players' ETH would be released from segregation but never claimable. This is a game-level bug (not sDGNRS's responsibility). The game enforces roll range. **Verified: correctly identified as game trust assumption.**

### Q3: burnWrapped DGNRS-sDGNRS supply invariant
"You claimed sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply is maintained. Walk through the burnWrapped flow to verify."

**Verification:**
1. Start: sDGNRS.balanceOf[DGNRS] = X, DGNRS.totalSupply = X (invariant holds)
2. burnWrapped(amount): DGNRS.burnForSdgnrs reduces DGNRS.totalSupply by amount (X - amount)
3. Then either _deterministicBurnFrom or _submitGamblingClaimFrom burns sDGNRS from DGNRS balance: sDGNRS.balanceOf[DGNRS] reduced by amount (X - amount)
4. End: both reduced by amount. Invariant holds. **VERIFIED.**

---

## Verdict: PASS

**Coverage: 37/37 functions catalogued, 30/30 non-trivial functions analyzed**
- All call trees fully expanded with line numbers
- All storage write maps complete
- All cached-local-vs-storage checks present
- All MULTI-PARENT functions have standalone analysis
- No functions skipped or dismissed with "standard" or "similar"
- All 10 attack angles applied to every Tier 1 and Tier 2 function
- Cross-contract call matrix independently verified

**No coverage gaps found. Unit 11 Taskmaster coverage PASSES.**
