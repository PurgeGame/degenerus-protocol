# Gas round-4 packet — advance

Line numbers reference the AUDIT-TIME source (three gas rounds ago) — locate by code content, NOT line number.


## ADVANCE-05 [redundant_external_call / cold] L745-L770 — file: modules/DegenerusGameAdvanceModule.sol
**Description:** _rewardTopAffiliate calls dgnrs.poolBalance(Pool.Affiliate) twice — once before transferFromPool (L749) and again after (L764) to compute the remaining pool. transferFromPool (StakedDegenerusStonk.sol L493-516) returns the exact amount deducted from poolBalances ('return amount;' after 'poolBalances[idx] = available - amount'), with no reentrancy hooks in between, so the post-transfer balance is derivable as poolBalance - paid. When top == address(0) the first read is skipped, so restructuring to one unconditional read covers both branches.
**Change:** Read 'uint256 poolBalance = dgnrs.poolBalance(Pool.Affiliate);' once at function entry. If top != address(0): compute reward, call transferFromPool, then 'poolBalance -= paid;'. Use poolBalance as remainingPool for the levelDgnrsAllocation snapshot. Removes the second external call.
**Excerpt (audit-time):**
```solidity
uint256 paid = dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Affiliate, top, dgnrsReward);
...
uint256 remainingPool = dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Affiliate);
```
**Risk notes:** Verified transferFromPool's return equals the pool decrement (clamped-to-available path included) and recipient credit has no callback. Solvency math unchanged — same values, one fewer read.
**Skeptic reasoning:** Independently verified transferFromPool (StakedDegenerusStonk.sol L493-516): on every non-reverting path the returned 'amount' equals the exact poolBalances decrement — including the clamp (L499-501) and the early 0-returns (amount==0, available==0: zero returned, zero decremented). Recipient credit is an internal balance write with events only — no callbacks, no reentrancy hooks. to==address(0) reverts but the call site guards top != address(0). So poolBalance_after == poolBalance_before - paid always, and 'poolBalance -= paid' (not dgnrsReward) is the correct restructure, which the recommendation specifies. Same values reach levelDgnrsAllocation — solvency math identical, one fewer external call.
**Implementation notes:** Must subtract the RETURNED paid (clamped), not the requested dgnrsReward — the recommendation already gets this right. top == address(0) branch: single unconditional read is gas-equal to today.
**Invariant impact:** none | **Risk:** low

## ADVANCE-08 [redundant_sload / warm] L189-L225, L348-L352, L201-L213, L466 — file: modules/DegenerusGameAdvanceModule.sol
**Description:** advanceGame re-reads several slot-0-packed fields where a stack cache would do: (a) dailyIdx is read twice at L189 in one expression, again at L225, and twice more at L351-352 — its only writers anywhere in contracts/ are _unlockRng (this module, L1812) and the Game constructor, so no delegatecall on these paths can change it; (b) rngLockedFlag read at L201 and L213 with only unrelated bool stores between (same packed slot, so the optimizer must re-read after the L206-208 stores); (c) lastPurchaseDay read at L201, L211, and again at L466 where the local 'lastPurchase' already equals it inside the !inJackpot branch (lastPurchaseDay has no writers outside this module).
**Change:** Cache 'uint24 di = dailyIdx;' and 'bool locked = rngLockedFlag;' at function entry and use them at L189/L225/L351-352 and L213; replace 'if (!lastPurchaseDay)' at L466 with 'if (!lastPurchase)'. Track the L206 turbo write in the local before computing lastPurchase.
**Excerpt (audit-time):**
```solidity
if (day > dailyIdx + 1 && rngWordByDay[dailyIdx + 1] != 0) { day = dailyIdx + 1; }
...
if (day == dailyIdx) {
...
if (!lastPurchaseDay) {
```
**Risk notes:** Same-expression duplicate reads (L189, L351) may already be CSE'd by via_ir; the cross-statement reads after same-slot bool stores (L213, L225, L466) cannot be. Caching dailyIdx across the _runSubscriberStage delegatecall relies on the afking module never writing dailyIdx — verified by grep (only _unlockRng and Game constructor write it). Skeptic should re-confirm the afking module's full call tree.
**Skeptic reasoning:** All three caches verified safe. (a) dailyIdx: grep over ALL of contracts/ confirms exactly two writers — _unlockRng (module L1812) and the Game constructor (L207). The delegatecalls crossed by the cache (mint-module processTicketBatch, afking processSubscriberStage) cannot write it, and the only nested route to _unlockRng is a reentrant advanceGame — but no peer contract calls advanceGame (Vault/sDGNRS carry only interface declarations; grep found zero call sites), and the intervening callees hand control only to protocol contracts: BurnieCoinflip has zero .call{/.transfer( anywhere (credit-based payouts), resolveRedemptionPeriod is pure storage accounting (L673-698), no safeMint/onERC721Received in mint/afking modules. (b) rngLockedFlag L201→L213: only the turbo block's unrelated bool stores intervene — no calls at all; writers are _finalizeRngRequest/_unlockRng, neither reachable. (c) lastPurchaseDay→L466: writers are only L206 (before the L211 read), L494, L536 (both after L466); same no-reentry argument covers the rngGate externals. Additionally, any hypothetical nested advance that could mutate these fields would already double-pay the daily jackpot under CURRENT code, so the cache weakens nothing the system doesn't already require.
**Implementation notes:** The L189 same-expression pair is likely already CSE'd by via_ir — the real wins are L225 (post-store re-read), L351-352, and L466. For L466, lastPurchase computed at L211 already incorporates the L206 turbo write (storage read after the write), so no extra tracking is needed beyond using the existing local.
**Invariant impact:** none | **Risk:** low

## ADVANCE-09 [bytecode_dedup / warm] L1154-L1163, L1199-L1208, L1640-L1650 (helper at L1677-L1688) — file: modules/DegenerusGameAdvanceModule.sol
**Description:** The VRFRandomWordsRequest struct construction + requestRandomWords call is inlined in 5 places, but the private helper _requestVrfWord(uint16 confirmations) already exists (L1677) and is only used at 2 of them (L1786, L1792). requestLootboxRng (L1154), retryLootboxRng (L1199), and _requestRng (L1640) duplicate it byte-for-byte (only confirmations differ). _tryRequestRng must stay inlined because try/catch requires a direct external call expression.
**Change:** In requestLootboxRng: 'uint256 id = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);'. In retryLootboxRng: same. In _requestRng: '_finalizeRngRequest(isTicketJackpotDay, lvl, _requestVrfWord(VRF_REQUEST_CONFIRMATIONS));'.
**Excerpt (audit-time):**
```solidity
uint256 id = vrfCoordinator.requestRandomWords(
    VRFRandomWordsRequest({ keyHash: vrfKeyHash, subId: vrfSubscriptionId, requestConfirmations: VRF_MIDDAY_CONFIRMATIONS, callbackGasLimit: VRF_CALLBACK_GAS_LIMIT, numWords: 1, extraArgs: hex"" })
);
```
**Risk notes:** Identical external call semantics — same coordinator/keyhash/sub reads, same revert-on-failure behavior. No RNG semantics change.
**Skeptic reasoning:** Verified: _requestVrfWord (L1677-1688) exists and is used only at L1786/L1792; the inline copies at L1154, L1199 (VRF_MIDDAY_CONFIRMATIONS), and L1640 (VRF_REQUEST_CONFIRMATIONS) are field-for-field identical to the helper modulo the confirmations argument — same keyHash/subId/callback-limit/numWords/extraArgs reads, same revert-on-failure (no try/catch at those three sites). _tryRequestRng correctly stays inlined: Solidity's try/catch requires a direct external call expression, so it cannot route through the internal helper. Pure bytecode dedup with identical external-call semantics; no RNG semantics change.
**Implementation notes:** 
**Invariant impact:** none | **Risk:** none

## ADVANCE-12 [redundant_sload / cold] L986-L990 — file: modules/DegenerusGameAdvanceModule.sol
**Description:** _consolidatePoolsAndRewardJackpots reads the storage variable 'level' inside PriceLookupLib.priceForLevel(level) although the lvl parameter equals storage level on every reachable path: level is written only in _finalizeRngRequest (which breaks out before consolidation) and by no peer module (grep across JackpotModule/DecimatorModule/MintModule/GameAfkingModule shows zero writes to 'level'), so between the L193 'lvl = level' read and L989 the value cannot change.
**Change:** Replace 'PriceLookupLib.priceForLevel(level)' with 'PriceLookupLib.priceForLevel(lvl)'.
**Excerpt (audit-time):**
```solidity
coinflip.creditFlip(
    ContractAddresses.SDGNRS,
    (memCurrent * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 20)
);
```
**Risk notes:** Relies on no delegatecalled module (distributeYieldSurplus, runBafJackpot, runDecimatorJackpot) writing 'level' — grep-verified. Skeptic should confirm the jackpots peer contract path (jackpots.markBafSkipped) cannot reenter a level write (it cannot: level writers are this module + constructor only).
**Skeptic reasoning:** Independently verified the load-bearing claim: grep over all of contracts/ shows 'level' is written ONLY at module L1741 (_finalizeRngRequest) plus its storage declaration initializer — no peer module, no Game-side writer. _finalizeRngRequest is unreachable on the consolidation path (its only routes, _requestRng/_tryRequestRng, break out of advanceGame with word==1 before consolidation). The self-calls inside _consolidate (runBafJackpot→JackpotModule, runDecimatorJackpot→DecimatorModule) and jackpots.markBafSkipped cannot write level (no writer exists in their code), and no peer contract calls advanceGame, so no nested request path exists. Therefore lvl (read from level at L193) == level at L989 on every reachable path; substituting lvl is value-identical.
**Implementation notes:** 
**Invariant impact:** none | **Risk:** low

## ADVANCE-14 [other / cold] L1081-L1091 (call site L468) — file: modules/DegenerusGameAdvanceModule.sol
**Description:** _emitDailyWinningTraits is a trivial private wrapper around the self-call IDegenerusGame(address(this)).emitDailyWinningTraits with exactly one call site (L468, the purchaseLevel==1 branch). The indirection adds a function body for no reuse.
**Change:** Inline the self-call at L468 ('IDegenerusGame(address(this)).emitDailyWinningTraits(1, rngWord, 1);') and delete the wrapper.
**Excerpt (audit-time):**
```solidity
function _emitDailyWinningTraits(uint24 lvl, uint256 randWord, uint24 bonusTargetLevel) private {
    IDegenerusGame(address(this)).emitDailyWinningTraits(lvl, randWord, bonusTargetLevel);
}
```
**Risk notes:** Mechanical inline; the Game-side wrapper and its OnlyGame self-call check are untouched.
**Skeptic reasoning:** Verified: _emitDailyWinningTraits (L1081-1091) is a pure pass-through to the self-call and has exactly one call site (L468, purchaseLevel==1 branch — level-0 gameplay only). Inlining 'IDegenerusGame(address(this)).emitDailyWinningTraits(1, rngWord, 1);' is mechanically identical; the Game-side wrapper and its OnlyGame self-call boundary are untouched.
**Implementation notes:** 
**Invariant impact:** none | **Risk:** none

## ADVANCE-18 [redundant_sload / cold] L711-L719 (call site L553) — file: modules/DegenerusGameAdvanceModule.sol
**Description:** _endPhase re-reads storage 'level' although its single caller (L553, jackpot-phase block) already holds lvl from L193, and level cannot have changed on that path (its only writer _finalizeRngRequest is on the request-break path; no peer module writes level).
**Change:** Change to '_endPhase(lvl)' / 'function _endPhase(uint24 lvl) private' and drop the 'uint24 lvl = level;' line.
**Excerpt (audit-time):**
```solidity
function _endPhase() private {
    uint24 lvl = level;
    phaseTransitionActive = true;
```
**Risk notes:** Single private call site; level-write path analysis as in ADVANCE-12. payDailyJackpotCoinAndTickets delegatecall precedes it — grep-verified that no module writes 'level'.
**Skeptic reasoning:** Verified: _endPhase has exactly one call site (L553) and re-reads 'level' which provably equals the caller's lvl from L193 — grep confirms level's only writer is _finalizeRngRequest (L1741), unreachable on this path (rngGate returned a real word, so no request/break occurred this tx), and the intervening payDailyJackpotCoinAndTickets delegatecall (JackpotModule) contains no level write; no peer contract can reach advanceGame to trigger one nested. Passing lvl as a parameter is value-identical.
**Implementation notes:** 
**Invariant impact:** none | **Risk:** low

## RT-IDIOMS-09 [redundant_sload / warm] L1244 (also L189, L225, L351-L352, L1257) — file: modules/DegenerusGameAdvanceModule.sol
**Description:** Two repeated-SLOAD spots on the daily advance chain. (a) rngGate's first line reads the same mapping slot twice: `if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);` — the second read is a guaranteed-warm duplicate. (b) advanceGame reads `dailyIdx` 4-6 times per call (L189 twice, L225, L351-352, and again inside rngGate L1257); dailyIdx is only written by _unlockRng, which runs after every one of these reads, so a function-entry local is safe. Interleaved external calls and SSTOREs defeat IR-level CSE for both.
**Change:** (a) `uint256 w = rngWordByDay[day]; if (w != 0) return (w, 0);`. (b) In advanceGame, hoist `uint24 dIdx = dailyIdx;` at entry and use it at L189/L225/L351; pass it into rngGate (or hoist the same local at rngGate entry) for the L1257 read.
**Excerpt (audit-time):**
```solidity
if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);
```
**Risk notes:** dailyIdx writes occur only in _unlockRng, strictly after the last cached read on every branch (verified: STAGE_SUBS/STAGE_GAP breaks return before _unlockRng; jackpot/purchase branches call _unlockRng after rngGate). No RNG-window state is consumed differently — same values, fewer loads.
**Skeptic reasoning:** (a) Verified: rngGate's first line (AdvanceModule L1244) reads rngWordByDay[day] twice in one statement with no intervening write/call — caching is trivially safe. (b) Verified the dailyIdx write set is exactly two sites: the Game CONSTRUCTOR (DegenerusGame.sol:207, unreachable at runtime) and _unlockRng (AdvanceModule L1812). All advanceGame reads (L189 x2, L225, L351-352) and rngGate's read (L1257) occur strictly before any _unlockRng call site (L428/L499/L557 are post-rngGate; the only other site, _handleGameOverPath L704, is immediately followed by return(true,...) which makes advanceGame return 0 at L220 with no further dailyIdx reads). In-path delegatecalls (_runProcessTicketBatch, _runSubscriberStage) and external calls reach only pinned protocol contracts, none of which re-enters advanceGame, so a function-entry local is safe on every branch including the gap-backfill, gameover, and mid-day paths. One correction: rngGate ALREADY caches dailyIdx into a local at L1257 (`uint24 idx = dailyIdx;`), so the rngGate half of the claim is largely done — threading the advanceGame local as a parameter saves only one further warm SLOAD at the cost of a signature change.
**Implementation notes:** Do (a) and the advanceGame-entry local for (b). Skip the rngGate signature change (already locally cached; marginal benefit does not justify churn on the RNG gate).
**Invariant impact:** none | **Risk:** low

## RT-IDIOMS-10 [redundant_sload / warm] L1716-L1723 (also L1166-L1172 in requestLootboxRng; DegenerusGameMintModule.sol L1244+L1267; GameAfkingModule.sol L959+L1016-L1021) — file: modules/DegenerusGameAdvanceModule.sol
**Description:** The packed lootbox-request slot helpers (_lrRead/_lrWrite) each do a full SLOAD (+SSTORE for writes) of the SAME storage word. Several sites chain 3+ helper calls back-to-back on that one slot: _finalizeRngRequest does _lrRead(INDEX)+_lrWrite(INDEX) then _lrWrite(PENDING_ETH,0) then _lrWrite(PENDING_BURNIE,0) = 4 SLOADs + 3 SSTOREs where 1 SLOAD + 1 SSTORE suffices; requestLootboxRng L1166-1172 is the same triple; the mint module's lootbox branch reads the slot at L1244 (INDEX) and again at L1267 (PENDING_ETH read + write); the afking cover-box does the same pair (L959, L1016-1021). The interleaved external/self calls prevent the optimizer from coalescing.
**Change:** Add a storage-base helper that updates multiple fields in one read-modify-write, e.g. `_lrBump(): uint256 p = lootboxRequestPacked; p = setField(p, INDEX, getField(p, INDEX)+1); p = clearField(p, PENDING_ETH); p = clearField(p, PENDING_BURNIE); lootboxRequestPacked = p;` and use it at _finalizeRngRequest and requestLootboxRng. In the mint module, read the packed word once into a local, extract INDEX and PENDING_ETH from it, and write the updated word once.
**Excerpt (audit-time):**
```solidity
_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1);
_lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
_lrWrite(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK, 0);  // 4 SLOADs + 3 SSTOREs on ONE slot
```
**Risk notes:** Pure read-modify-write coalescing of one slot; field masks/shifts unchanged. In the mint-module case the packed word is not mutated by enqueueBoxForAutoOpen (it only pushes to boxPlayers), so a pre-read local remains valid across it.
**Skeptic reasoning:** Verified all cited sites operate on the single packed slot lootboxRngPacked via _lrRead/_lrWrite (DegenerusGameStorage.sol:1510-1517, each a full SLOAD / SLOAD+SSTORE). _finalizeRngRequest L1715-1723 and requestLootboxRng L1166-1172 each do the consecutive INDEX-increment + two field-clears = 4 SLOADs + 3 SSTOREs on one slot with no interleaved calls — coalescing to one read-modify-write is exact. Mint-module pair (L1244 read INDEX, L1267 RMW PENDING_ETH) and afking cover-box pair (L959, L1016-1021): the only operation between the slot accesses is the enqueueBoxForAutoOpen self-call, whose body (Game L1719) only pushes to boxPlayers and provably never touches lootboxRngPacked, so a pre-read local stays valid across it. Field masks/shifts unchanged; RNG semantics identical (same values, fewer loads).
**Implementation notes:** Implement the _lrBump-style combined helper for the two consecutive triples and locals for the two cross-call pairs. If RT-IDIOMS-02 lands first, the mint/afking pairs become fully consecutive and the optimizer may handle them — re-measure before hand-coding.
**Invariant impact:** none | **Risk:** low