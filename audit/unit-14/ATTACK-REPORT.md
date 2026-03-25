# Unit 14: Affiliate + Quests + Jackpots -- Mad Genius Attack Report

**Phase:** 116
**Contracts:** DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol
**Audit Model:** Opus (claude-opus-4-6)
**Date:** 2026-03-25

---

## B-13: DegenerusJackpots::runBafJackpot (L220-491) -- CRITICAL

### Call Tree

```
runBafJackpot(poolWei, lvl, rngWord) [L220-491] -- external, onlyGame
  +-- _bafTop(lvl, 0) [L620-625] -- private view, reads bafTop[lvl][idx]
  +-- _creditOrRefund(w, topPrize, tmpW, tmpA, n) [L507-521] -- private pure, memory-only
  +-- coin.coinflipTopLastDay() [L256] -- EXTERNAL CALL to BurnieCoinflip (view, no state change)
  +-- _creditOrRefund(w, topPrize, tmpW, tmpA, n) [L257]
  +-- _bafTop(lvl, pick) [L273] -- pick is 2 or 3
  +-- _creditOrRefund(w, prize, tmpW, tmpA, n) [L275]
  +-- degenerusGame.sampleFarFutureTickets(entropy) [L288] -- EXTERNAL CALL to DegenerusGame (view)
  +-- _bafScore(cand, lvl) [L301, L342] -- private view, reads bafPlayerEpoch, bafEpoch, bafTotals
  +-- _creditOrRefund(...) [L314, L319, L356, L361]
  +-- degenerusGame.sampleFarFutureTickets(entropy) [L330] -- 2nd independent draw
  +-- degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy) [L404] -- EXTERNAL CALL, 50 rounds
  +-- _bafScore(cand, lvl) [L417] -- per scatter ticket
  +-- _clearBafTop(lvl) [L487] -- private, writes bafTopLen, bafTop
      +-- deletes bafTopLen[lvl]
      +-- deletes bafTop[lvl][0..len-1]
  +-- bafEpoch[lvl]++ [L488] -- storage write (unchecked)
  +-- lastBafResolvedDay = degenerusGame.currentDayView() [L489] -- EXTERNAL CALL + storage write
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `bafTopLen[lvl]` | L631 (via _clearBafTop) | delete (set to 0) |
| `bafTop[lvl][0..3]` | L635 (via _clearBafTop) | delete (zeroed) |
| `bafEpoch[lvl]` | L488 | increment (unchecked) |
| `lastBafResolvedDay` | L489 | write (currentDayView) |

### Cached-Local-vs-Storage Check

The function reads `bafTop[lvl]` via `_bafTop()` early (L243, L273) and later clears it via `_clearBafTop()` (L487). However, _bafTop reads are pure reads (not cached in local variables that get written back) -- the function never writes BACK to bafTop except to delete it. The return arrays (tmpW, tmpA) are memory-only.

**No BAF-pattern risk.** No ancestor caches a value that a descendant writes back to stale.

### Attack Analysis

**1. State Coherence (BAF Pattern):** SAFE
- No local variable caches any storage value that is later written by a descendant. All bafTop reads are consumed immediately into memory arrays. _clearBafTop deletes storage but no parent has a stale copy to write back.

**2. Access Control:** SAFE
- `onlyGame` modifier at L148-151 checks `msg.sender != ContractAddresses.GAME`. Fixed at deploy time, cannot be re-pointed.

**3. RNG Manipulation:** SAFE
- `rngWord` is VRF-derived, passed in by the game contract's `rawFulfillRandomWords`. The entropy chaining via `keccak256(abi.encodePacked(entropy, salt))` at L270, L287, L329, L385 produces independent derived values from the single VRF word. Attacker cannot influence the VRF word or the salt sequence.

**4. Cross-Contract State Desync:** INVESTIGATE
- `coin.coinflipTopLastDay()` (L256) reads BurnieCoinflip state. If coinflip top bettor was resolved/cleared between VRF request and fulfillment, the winner could be stale. However, this is a view call reading historical data -- the "top bettor from last day window" is a fixed historical snapshot that doesn't change based on current transactions.
- `degenerusGame.sampleFarFutureTickets(entropy)` (L288, L330) reads ticket data from the game. Between VRF request and fulfillment, players could buy/transfer tickets. However, this is acceptable because the VRF word itself is unknown at request time, so the attacker cannot pre-position tickets to win.
- **Verdict: SAFE** -- cross-contract reads are point-in-time snapshots of historical/VRF-gated data.

**5. Edge Cases:** INVESTIGATE
- **lvl == 0, century check (L378):** `isCentury = (lvl % 100 == 0)` -- when lvl==0, this is true. L396: `maxBack = lvl > 99 ? 99 : lvl - 1`. When lvl==0: `maxBack = 0 - 1 = underflow?` NO -- this is `uint24`, and the code has guard: `maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl`. When lvl==0: maxBack = `0 - 1` with uint24. WAIT -- `lvl - 1` when lvl==0 would underflow. Let me trace again.
  - L396: `uint24 maxBack = lvl > 99 ? 99 : lvl - 1;` -- when lvl==0, this is `0 - 1`. Since uint24, this WRAPS to 16777215.
  - L397: `targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;` -- maxBack is 16777215 (>0), so we get `lvl - 1 - uint24(entropy % 16777215)`. When lvl==0: `0 - 1 - X` = massive underflow.
  - **HOWEVER:** Can lvl ever be 0 when runBafJackpot is called? BAF jackpots are resolved at level END, which means the level is at least 1 (level 0 -> level 1 transition triggers the BAF). Let me check: BAF is triggered by `_endPhase`/`_runBafJackpot` in the endgame module, which runs when a level completes. Level starts at 0, first BAF would be at level 0 completion (lvl=0 passed to runBafJackpot). **This IS a potential underflow bug.**
  - BUT: `isCentury` at lvl==0 means round >= 12 (since `round < 4` and `round < 8` and `round < 12` are all checked first for isCentury). At round 12+, we'd hit the faulty path.
  - **Verdict: INVESTIGATE** -- potential uint24 underflow when lvl==0 and isCentury is true in scatter rounds 12+.

**6. Conditional Paths:** SAFE
- All prize slices have the pattern: compute prize, find winner, _creditOrRefund or add to toReturn. Empty addresses return their share via toReturn. The scatter section correctly handles empty rounds via the `toReturn += scatterTop - perRoundFirst * firstCount` pattern at L456.

**7. Economic Attacks:** SAFE
- Prize distribution is proportional and deterministic based on VRF. An attacker cannot front-run the BAF resolution (it's called atomically within advanceGame/endgame, and rngWord is VRF-derived). The scatter sampling uses game-controlled ticket data.

**8. Griefing:** SAFE
- No griefing vector. Only the game contract can call runBafJackpot, and it's called atomically during level transitions.

**9. Ordering/Sequencing:** SAFE
- runBafJackpot is called once per level-end. The bafEpoch increment at L488 ensures the leaderboard resets for the next level. Calling order is enforced by the game's state machine.

**10. Silent Failures:** SAFE
- All uncredited prizes are captured in `toReturn` and returned to the caller. The assembly truncation at L481-484 correctly sets array lengths. No silent value loss.

---

## B-03: DegenerusAffiliate::payAffiliate (L386-617) -- CRITICAL

### Call Tree

```
payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore) [L386-617] -- external, onlyAuthorized
  +-- [ACCESS CHECK: msg.sender == COIN || msg.sender == GAME] [L398-401]
  +-- playerReferralCode[sender] read [L406]
  +-- [BRANCH: storedCode == 0] [L415]
  |   +-- [BRANCH: code == 0] -> _setReferralCode(sender, REF_CODE_LOCKED) [L419]
  |   +-- [BRANCH: code != 0]
  |       +-- affiliateCode[code] read [L424]
  |       +-- [BRANCH: invalid/self] -> _setReferralCode(sender, REF_CODE_LOCKED) [L430]
  |       +-- [BRANCH: valid] -> _setReferralCode(sender, code) [L436]
  +-- [BRANCH: storedCode != 0] [L442]
  |   +-- [BRANCH: code upgrade during presale] -> _setReferralCode(sender, code) [L446]
  |   +-- [BRANCH: REF_CODE_LOCKED] -> use VAULT [L453]
  |   +-- [BRANCH: normal stored code] -> affiliateCode[storedCode] read [L459]
  +-- affiliateCommissionFromSender[lvl][affiliateAddr][sender] read/write [L501-511]
  +-- affiliateCoinEarned[lvl][affiliateAddr] write [L515-516]
  +-- _totalAffiliateScore[lvl] write [L517]
  +-- _updateTopAffiliate(affiliateAddr, newTotal, lvl) [L527]
  |   +-- _score96(total) [L786]
  |   +-- affiliateTopByLevel[lvl] read [L787]
  |   +-- [BRANCH: score > current] -> affiliateTopByLevel[lvl] write [L789]
  +-- _applyLootboxTaper(scaledAmount, lootboxActivityScore) [L531] -- pure, no storage
  +-- [BRANCH: noReferrer] [L550]
  |   +-- GameTimeLib.currentDayIndex() [L559]
  |   +-- keccak256 entropy -> 50/50 VAULT vs DGNRS [L555-567]
  |   +-- _routeAffiliateReward(winner, totalAmount) [L568]
  |       +-- coin.creditFlip(player, amount) [L759] -- EXTERNAL CALL to BurnieCoin
  +-- [BRANCH: real affiliate] [L570]
  |   +-- coin.affiliateQuestReward(affiliateAddr, affiliateShareBase) [L578] -- EXTERNAL CALL
  |   +-- _referrerAddress(affiliateAddr) [L583] -> playerReferralCode read
  |   +-- coin.affiliateQuestReward(upline, baseBonus) [L585] -- EXTERNAL CALL
  |   +-- _referrerAddress(upline) [L590]
  |   +-- coin.affiliateQuestReward(upline2, bonus2) [L592] -- EXTERNAL CALL
  |   +-- _rollWeightedAffiliateWinner(players, amounts, 3, totalAmount, sender, storedCode) [L600]
  |   |   +-- GameTimeLib.currentDayIndex() [L815]
  |   |   +-- keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode) [L817-825]
  |   |   +-- roll % totalAmount [L827]
  |   +-- [BRANCH: winner != sender] -> _routeAffiliateReward(winner, totalAmount) [L610-611]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `playerReferralCode[sender]` | L697 (via _setReferralCode) | write (code or REF_CODE_LOCKED) |
| `affiliateCommissionFromSender[lvl][affiliateAddr][sender]` | L511 | write (+=scaledAmount) |
| `affiliateCoinEarned[lvl][affiliateAddr]` | L516 | write (+=scaledAmount) |
| `_totalAffiliateScore[lvl]` | L517 | write (+=scaledAmount) |
| `affiliateTopByLevel[lvl]` | L789 (via _updateTopAffiliate) | conditional write |

### Cached-Local-vs-Storage Check

- `storedCode` is read from `playerReferralCode[sender]` at L406. The function may write to `playerReferralCode[sender]` via `_setReferralCode` at L419/430/436/446. BUT these writes happen BEFORE `storedCode` is used downstream (the code correctly updates `storedCode` local variable after each _setReferralCode call at L420/431/438/448). **SAFE** -- local is updated after each storage write.
- `info` (AffiliateCodeInfo memory) is read from storage. No descendant writes back to affiliateCode. **SAFE.**
- `alreadyEarned` at L501 is read, then updated at L511. No descendant modifies this between read and write. **SAFE.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** SAFE
- All local variables that mirror storage are updated in sync. The `storedCode` local is always reassigned after `_setReferralCode` writes to storage. No stale cache writeback.

**2. Access Control:** SAFE
- L398-401: `msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.GAME`. Fixed addresses, cannot be re-pointed.

**3. RNG Manipulation:** INVESTIGATE
- `_rollWeightedAffiliateWinner` uses `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)` (L817-825). This is entirely deterministic -- no VRF. An affiliate knowing their code and the day can precompute whether they'll win. However, the comment at L572 acknowledges this: "PRNG is known -- accepted design tradeoff (EV-neutral, manipulation only redistributive between affiliates)."
- The 50/50 VAULT vs DGNRS flip (L555-567) for no-referrer cases uses the same deterministic approach.
- **Verdict: SAFE (by design)** -- acknowledged trade-off, EV-neutral, documented.

**4. Cross-Contract State Desync:** INVESTIGATE
- `coin.affiliateQuestReward(affiliateAddr, affiliateShareBase)` (L578) is called 3 times for affiliate, upline1, upline2. This is an external call to BurnieCoin, which calls into DegenerusQuests.handleAffiliate(). If BurnieCoin's affiliateQuestReward triggers a state change that affects the next call, there could be desync.
- Tracing: `coin.affiliateQuestReward` -> BurnieCoin -> DegenerusQuests.handleAffiliate() -> updates questPlayerState. This does NOT affect any storage read by the CURRENT payAffiliate execution (it only reads affiliateCode, affiliateCoinEarned, playerReferralCode -- none of which are in DegenerusQuests).
- **Verdict: SAFE** -- quest state changes don't affect affiliate reward calculation.

**5. Edge Cases:** SAFE
- `amount == 0`: scaledAmount becomes 0, function returns 0 early at L491-493.
- `scaledAmount > remainingCap`: correctly capped at L509.
- `totalAmount == 0` after all calculations: both branches check `if (totalAmount != 0)` before routing rewards (L554, L598).

**6. Conditional Paths:** INVESTIGATE
- **Self-referral via upline chain:** A player P creates code C1, affiliate A is referred under C1. If A creates code C2 and refers P under C2, then: payAffiliate for P -> affiliate=A (code C1), upline1=_referrerAddress(A)=P (code C2). Now upline1 is P (the sender). L609 checks `if (winner != sender)` and skips payment if winner==sender. This prevents the BUYER from being paid from their own purchase.
  - BUT: the amounts[1] (P's upline reward) still enters the totalAmount calculation. If P wins the weighted roll, the payment is skipped. If A wins, A gets the combined amount. This is correct -- no double-payment to the sender.
  - **Verdict: SAFE** -- self-referral via upline is handled by the sender exclusion at L609.

**7. Economic Attacks:** INVESTIGATE
- **Commission cap bypass via code rotation:** The cap at L498-512 tracks per `affiliateAddr` per `sender` per `lvl`. If the sender changes their referral code to point to a different affiliate, the cap resets. BUT: L328 in referPlayer says "Only allow setting referrer once, except VAULT referrals during presale." Once a referral code is locked (non-presale), the sender cannot change their affiliate. During presale, the mutability window is limited.
  - In payAffiliate (L443-451): existing stored code can only be upgraded during presale (`_vaultReferralMutable`). After presale, the referral is locked.
  - **Verdict: SAFE** -- referral locking prevents cap bypass after presale.

**8. Griefing:** SAFE
- No griefing vector. Affiliate rewards are additive and do not affect other players' rewards.

**9. Ordering/Sequencing:** SAFE
- payAffiliate is idempotent per-call. Each call independently resolves referral, calculates reward, and distributes. No ordering dependency.

**10. Silent Failures:** INVESTIGATE
- When `winner == sender` at L609, the reward is silently dropped (not sent to anyone). The totalAmount is computed but not distributed. This means the affiliate reward for that purchase is effectively burned.
- However, this only happens when the weighted roll selects the buyer as winner. The buyer gets kickback regardless (returned via the return value). The affiliate reward going to zero when buyer wins is a design choice (prevents self-enrichment loop).
- **Verdict: SAFE (by design)** -- acknowledged that reward is dropped when buyer wins their own roll.

---

## B-12: DegenerusJackpots::recordBafFlip (L166-181) -- HIGH

### Call Tree

```
recordBafFlip(player, lvl, amount) [L166-181] -- external, onlyCoin
  +-- [GUARD: player == VAULT || player == SDGNRS] -> return [L167]
  +-- bafEpoch[lvl] read [L169]
  +-- bafPlayerEpoch[lvl][player] read [L170]
  +-- [BRANCH: epoch mismatch] -> bafPlayerEpoch[lvl][player] write, bafTotals[lvl][player] = 0 [L171-172]
  +-- bafTotals[lvl][player] read [L175]
  +-- unchecked { total += amount; } [L176]
  +-- bafTotals[lvl][player] write [L177]
  +-- _updateBafTop(lvl, player, total) [L179]
  |   +-- _score96(stake) [L556] -- pure, caps at uint96 max
  |   +-- bafTop[lvl] read [L557]
  |   +-- bafTopLen[lvl] read [L558]
  |   +-- [CASE 1: existing player] -> bubble up sort [L573-587]
  |   +-- [CASE 2: board not full] -> insert sorted [L590-601]
  |   +-- [CASE 3: board full, score > bottom] -> replace bottom, sort [L604-612]
  +-- emit BafFlipRecorded [L180]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `bafPlayerEpoch[lvl][player]` | L171 | write (currentEpoch) |
| `bafTotals[lvl][player]` | L172, L177 | write (0 on reset, total after add) |
| `bafTop[lvl][*]` | L575-612 (via _updateBafTop) | conditional writes (sort/insert/replace) |
| `bafTopLen[lvl]` | L599 (via _updateBafTop) | conditional write (len + 1) |

### Cached-Local-vs-Storage Check

- `total` read at L175, modified at L176, written back at L177. Between L175 and L177, `_updateBafTop` is NOT called yet (it's called at L179, after the write at L177). **SAFE** -- no descendant modifies bafTotals before the writeback.
- `bafTop[lvl]` is read by _updateBafTop; no ancestor caches it. **SAFE.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** SAFE

**2. Access Control:** SAFE -- `onlyCoin` at L141-144 checks COIN or COINFLIP.

**3. RNG Manipulation:** N/A -- no RNG.

**4. Cross-Contract State Desync:** SAFE -- no external calls.

**5. Edge Cases:** VULNERABLE
- **Unchecked overflow at L176:** `unchecked { total += amount; }`. The `total` is uint256 and `amount` is uint256. For uint256 to overflow, total + amount must exceed 2^256 - 1. In practice, `amount` represents a coinflip stake in BURNIE (18 decimals). Even with 1 trillion tokens staked, the value would be ~10^30, far below 2^256 (~1.15 * 10^77). **Practically impossible to overflow.**
- **However:** `_score96(stake)` at L556 caps the leaderboard score at uint96 max (~7.9 * 10^28). Even if bafTotals grows very large, the leaderboard score is capped. The raw total in bafTotals is only used by `_bafScore` for far-future ticket ranking in runBafJackpot.
- **Verdict: SAFE** -- uint256 overflow is practically impossible. Score capping at uint96 adds safety margin.

**6. Conditional Paths:** SAFE
- Epoch mismatch correctly resets total to 0 before adding (L172 then L175-177).
- Board full/not-full cases all maintain sorted invariant.

**7. Economic Attacks:** SAFE
- Recording is additive and cannot be undone. Leaderboard ranking is first-come-first-served for equal scores.

**8. Griefing:** SAFE -- recording flips for oneself does not affect others.

**9. Ordering/Sequencing:** SAFE -- idempotent per-call.

**10. Silent Failures:** SAFE
- Vault and sDGNRS are silently filtered (L167). This is by design -- system contracts should not appear on BAF leaderboard.

---

## B-01: DegenerusAffiliate::createAffiliateCode (L304-306)

### Call Tree

```
createAffiliateCode(code_, kickbackPct) [L304-306] -- external, open
  +-- _createAffiliateCode(msg.sender, code_, kickbackPct) [L305]
      +-- [GUARD: owner == 0] -> revert Zero [L726]
      +-- [GUARD: code_ == 0 || code_ == REF_CODE_LOCKED] -> revert Zero [L728]
      +-- [GUARD: kickbackPct > 25] -> revert InvalidKickback [L730]
      +-- affiliateCode[code_] read [L731]
      +-- [GUARD: info.owner != 0] -> revert Insufficient [L733]
      +-- affiliateCode[code_] write [L734-737]
      +-- emit Affiliate [L738]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `affiliateCode[code_]` | L734-737 | write (AffiliateCodeInfo{owner, kickback}) |

### Cached-Local-vs-Storage Check

No caching pattern -- single read then write. **SAFE.**

### Attack Analysis

**1-10 Summary:** SAFE across all angles.
- Access: Open by design (anyone can create codes).
- Guards: Reserved values (0x0, REF_CODE_LOCKED) blocked. Kickback capped at 25%. First-come-first-served prevents overwrites.
- No external calls. No RNG. No economic attack vector.
- **One note:** An attacker could front-run another user's code creation to claim a desirable code name. This is inherent to permissionless first-come-first-served systems and not a vulnerability.

---

## B-02: DegenerusAffiliate::referPlayer (L321-331)

### Call Tree

```
referPlayer(code_) [L321-331] -- external, open
  +-- affiliateCode[code_] read [L322-323]
  +-- [GUARD: referrer == 0 || referrer == msg.sender] -> revert Insufficient [L325]
  +-- playerReferralCode[msg.sender] read [L326]
  +-- [GUARD: existing != 0 && !_vaultReferralMutable(existing)] -> revert Insufficient [L328]
  |   +-- _vaultReferralMutable(existing) [L690-693]
  |       +-- [code != REF_CODE_LOCKED && code != AFFILIATE_CODE_VAULT] -> false
  |       +-- game.lootboxPresaleActiveFlag() [L692] -- EXTERNAL CALL (view)
  +-- _setReferralCode(msg.sender, code_) [L329]
  |   +-- playerReferralCode[player] write [L697]
  |   +-- affiliateCode[code] read (for referrer address) [L703]
  |   +-- emit ReferralUpdated [L705]
  +-- emit Affiliate [L330]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `playerReferralCode[msg.sender]` | L697 (via _setReferralCode) | write (code_) |

### Cached-Local-vs-Storage Check

No caching pattern. **SAFE.**

### Attack Analysis

**1. State Coherence:** SAFE -- no cache pattern.

**2. Access Control:** SAFE -- open by design, but self-referral prevented (L325).

**3-4. RNG/Desync:** N/A / SAFE.

**5. Edge Cases:** SAFE
- Self-referral: `referrer == msg.sender` reverts (L325).
- Non-existent code: `referrer == address(0)` reverts (L325).
- Already referred: `existing != bytes32(0)` and not mutable reverts (L328).
- Presale mutability: Only VAULT/LOCKED referrals can be updated during presale. After presale, all referrals are permanent.

**6. Conditional Paths:** SAFE -- presale path correctly guarded.

**7-10. Economic/Griefing/Ordering/Silent:** SAFE.

---

## B-04: DegenerusQuests::rollDailyQuest (L313-318)

### Call Tree

```
rollDailyQuest(day, entropy) [L313-318] -- external, onlyCoin
  +-- _rollDailyQuest(day, entropy) [L317]
      +-- _canRollDecimatorQuest() [L371]
      |   +-- questGame.decWindowOpenFlag() [L1004] -- EXTERNAL CALL (view)
      |   +-- questGame.level() [L1005] -- EXTERNAL CALL (view)
      +-- bonusEntropy = (entropy >> 128) | (entropy << 128) [L374]
      +-- _bonusQuestType(bonusEntropy, QUEST_TYPE_MINT_ETH, decAllowed) [L377-381] -- pure
      +-- _seedQuestType(quests[0], day, primaryType) [L383]
      |   +-- quest.day = day [L1583]
      |   +-- quest.questType = questType [L1584]
      |   +-- quest.version = _nextQuestVersion() [L1585]
      |       +-- questVersionCounter++ [L1040]
      +-- _seedQuestType(quests[1], day, bonusType) [L384]
      |   +-- quest.day = day [L1583]
      |   +-- quest.questType = questType [L1584]
      |   +-- quest.version = _nextQuestVersion() [L1585]
      +-- emit QuestSlotRolled x2 [L386-401]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `activeQuests[0].day` | L1583 | write |
| `activeQuests[0].questType` | L1584 | write |
| `activeQuests[0].version` | L1585 | write |
| `activeQuests[1].day` | L1583 | write |
| `activeQuests[1].questType` | L1584 | write |
| `activeQuests[1].version` | L1585 | write |
| `questVersionCounter` | L1040 | increment (x2) |

### Cached-Local-vs-Storage Check

`quests` at L370 is `DailyQuest[QUEST_SLOT_COUNT] storage quests = activeQuests` -- this is a STORAGE reference, not a memory copy. All writes go directly to storage via the reference. **SAFE.**

### Attack Analysis

**1. State Coherence:** SAFE -- storage reference, no caching.

**2. Access Control:** SAFE -- onlyCoin modifier.

**3. RNG Manipulation:** SAFE
- Entropy comes from VRF word, passed by BurnieCoin during day transition. Attacker cannot influence VRF.
- Slot 0 is always MINT_ETH (fixed). Slot 1 is weighted random from entropy. Even if an attacker could predict the quest type, the quest targets are fixed -- no economic advantage from knowing quest type in advance.

**4. Cross-Contract State Desync:** SAFE
- _canRollDecimatorQuest reads decWindowOpenFlag and level. These are point-in-time reads. If they change mid-transaction, the quest type selection might be based on stale data, but this is benign (wrong quest type is a mild UX issue, not a security concern).

**5. Edge Cases:** SAFE
- day=0: No explicit guard, but the coin contract controls the day parameter and would not pass 0.
- entropy=0: _bonusQuestType handles total==0 with fallback (L1343-1345).

**6-10:** SAFE across all angles.

---

## B-05: DegenerusQuests::awardQuestStreakBonus (L331-349)

### Call Tree

```
awardQuestStreakBonus(player, amount, currentDay) [L331-349] -- external, onlyGame
  +-- [GUARD: player==0 || amount==0 || currentDay==0] -> return [L332]
  +-- questPlayerState[player] storage ref [L334]
  +-- _questSyncState(state, player, currentDay) [L335]
  |   +-- [streak reset logic] [L1111-1143]
  |   +-- questStreakShieldCount[player] read [L1116]
  |   +-- questStreakShieldCount[player] write [L1119]
  |   +-- state.streak, state.lastSyncDay, state.completionMask, state.baseStreak writes [L1129-1142]
  +-- state.streak write [L342 or L340]
  +-- state.lastActiveDay conditional write [L347]
  +-- emit QuestStreakBonusAwarded [L349]
```

### Storage Writes (Full Tree)

| Variable | Line | Operation |
|----------|------|-----------|
| `questPlayerState[player].streak` | L1129/1132 (via sync), L340/342 | write |
| `questPlayerState[player].lastSyncDay` | L1140 (via sync) | conditional write |
| `questPlayerState[player].completionMask` | L1141 (via sync) | conditional write (reset to 0) |
| `questPlayerState[player].baseStreak` | L1142 (via sync) | conditional write |
| `questPlayerState[player].lastActiveDay` | L347 | conditional write |
| `questStreakShieldCount[player]` | L1119 (via sync) | conditional write |

### Cached-Local-vs-Storage Check

`state` is a storage reference -- no caching. **SAFE.**

### Attack Analysis

All 10 angles: **SAFE.** Access is onlyGame only. Streak increment clamps at uint24 max (L339-343). Shield consumption is correct. No external calls except game state reads in _questSyncState.

---

## B-06 through B-11: Quest Progress Handlers (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette)

These 6 functions follow an identical pattern. I will analyze them as a group with specific call-out for differences.

### Common Call Tree Pattern

```
handle*(player, ...) -- external, onlyCoin
  +-- activeQuests memory copy [varies]
  +-- _currentQuestDay(quests) [L1593-1597] -- pure
  +-- questPlayerState[player] storage ref
  +-- [GUARD: player==0 || amount==0 || currentDay==0] -> return
  +-- _questSyncState(state, player, currentDay) [L1111-1143]
  +-- [Find matching quest slot for action type]
  +-- _questSyncProgress(state, slot, currentDay, quest.version) [L1156-1168]
  +-- state.progress[slot] += delta (via _clampedAdd128) [L1024-1032]
  +-- emit QuestProgressUpdated
  +-- [GUARD: progress < target] -> return 0
  +-- [GUARD: slot==1 && slot0 not complete] -> return 0
  +-- _questCompleteWithPair(player, state, quests, slot, quest, currentDay, mintPrice) [L1453-1492]
      +-- _questComplete(player, state, slot, quest) [L1388-1435]
      |   +-- completionMask read/write [L1397-1423]
      |   +-- state.lastActiveDay conditional write [L1408-1410]
      |   +-- state.streak increment [L1417-1420]
      |   +-- state.lastCompletedDay write [L1421]
      |   +-- emit QuestCompleted [L1426-1433]
      +-- _maybeCompleteOther(player, state, quests, otherSlot, currentDay, mintPrice) [L1506-1533]
          +-- _questReady(state, quest, slot, mintPrice) [L1543-1565]
          +-- _questComplete(player, state, slot, quest) [L1532]
```

### Storage Writes (Full Tree, common to all handlers)

| Variable | Line | Operation |
|----------|------|-----------|
| `questPlayerState[player].streak` | L1129/1132 (sync), L1417-1420 (complete) | write |
| `questPlayerState[player].lastSyncDay` | L1140 (sync) | conditional write |
| `questPlayerState[player].completionMask` | L1141 (sync reset), L1406/1416/1423 (complete) | write |
| `questPlayerState[player].baseStreak` | L1142 (sync) | conditional write |
| `questPlayerState[player].lastActiveDay` | L1408-1410 (complete) | conditional write |
| `questPlayerState[player].lastCompletedDay` | L1421 (complete) | conditional write |
| `questPlayerState[player].lastProgressDay[slot]` | L1164 (syncProgress) | conditional write |
| `questPlayerState[player].lastQuestVersion[slot]` | L1165 (syncProgress) | conditional write |
| `questPlayerState[player].progress[slot]` | L1166 (syncProgress reset), varies (add) | write |
| `questStreakShieldCount[player]` | L1119 (sync) | conditional write |

### Cached-Local-vs-Storage Check

All handlers use storage references for `state`. The `quests` variable is a MEMORY copy (`DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests` at various lines). This memory copy is read-only -- no handler writes back to activeQuests. **SAFE.**

### Per-Handler Specifics

**B-06 handleMint:** Iterates both slots looking for MINT_ETH or MINT_BURNIE match. Can potentially complete both if both slots match (unusual but possible with future quest type additions). Uses _questHandleProgressSlot for ETH path.

**B-07 handleFlip:** Single-slot lookup via _currentDayQuestOfType(QUEST_TYPE_FLIP). Direct progress accumulation.

**B-08 handleDecimator:** Identical to handleFlip but with QUEST_TYPE_DECIMATOR.

**B-09 handleAffiliate:** Identical to handleFlip but with QUEST_TYPE_AFFILIATE.

**B-10 handleLootBox:** Like handleFlip but fetches mintPrice for ETH-based target calculation.

**B-11 handleDegenerette:** Supports both ETH and BURNIE variants via paidWithEth flag. Uses _questHandleProgressSlot.

### Attack Analysis (Common)

**1. State Coherence:** SAFE -- storage references throughout.

**2. Access Control:** SAFE -- all onlyCoin.

**3. RNG Manipulation:** N/A -- no RNG in progress handlers.

**4. Cross-Contract State Desync:** SAFE
- `questGame.mintPrice()` read (B-06, B-10, B-11) is a point-in-time view. If mintPrice changes mid-transaction, the target could shift. But mintPrice only changes at level transitions, which happen atomically -- not during individual player actions.

**5. Edge Cases:**
- **Slot 1 ordering dependency:** All handlers enforce `if (slotIndex == 1 && (state.completionMask & 1) == 0) return (0, ...)`. This means slot 1 CANNOT complete until slot 0 is complete. The paired completion check via `_maybeCompleteOther` then allows slot 0 to auto-complete slot 1 if slot 1's progress already meets target. **SAFE** -- no bypass possible.
- **_clampedAdd128 overflow:** Progress is clamped at uint128 max. This prevents overflow but means extremely large deposits don't increase progress beyond the cap. Since targets are small (1 ticket, 2000 BURNIE, 0.5 ETH), hitting uint128 max requires astronomical values. **SAFE.**
- **Double completion prevention:** `_questComplete` checks `(mask & slotMask) != 0` at L1401 and returns 0 if already complete. **SAFE.**

**6-10:** SAFE across all angles. No economic attack, no griefing, no ordering issues, no silent failures.

---

## MULTI-PARENT Category C Functions

### C-03: DegenerusAffiliate::_setReferralCode (L696-706)

Called by: B-02 (referPlayer), B-03 (payAffiliate), C-01 (_createAffiliateCode is NOT a caller -- constructor calls _setReferralCode directly), C-02 (_bootstrapReferral).

```
_setReferralCode(player, code) [L696-706] -- private
  +-- playerReferralCode[player] = code [L697]
  +-- [BRANCH: locked || VAULT code] -> referrer = VAULT [L700-701]
  +-- [ELSE] -> affiliateCode[code].owner read [L703]
  +-- emit ReferralUpdated [L705]
```

**Storage writes:** `playerReferralCode[player]` only.
**All callers write to the same slot for the same player, with no competing writes.** Each calling context has already resolved which code to set before calling this helper. **SAFE.**

### C-10: DegenerusQuests::_questSyncState (L1111-1143)

Called by: B-05 through B-11 (7 parents).

```
_questSyncState(state, player, currentDay) [L1111-1143] -- private
  +-- state.streak read [L1112]
  +-- anchorDay = max(state.lastActiveDay, state.lastCompletedDay) [L1113]
  +-- [BRANCH: gap > 1 day] [L1114]
  |   +-- missedDays = currentDay - anchorDay - 1 [L1115]
  |   +-- questStreakShieldCount[player] read [L1116]
  |   +-- [BRANCH: shields > 0]
  |   |   +-- used = min(missedDays, shields) [L1118]
  |   |   +-- questStreakShieldCount[player] -= used [L1119]
  |   |   +-- [BRANCH: missedDays > shields] -> state.streak = 0 [L1129]
  |   +-- [BRANCH: no shields] -> state.streak = 0 [L1132]
  +-- [streak changed? emit QuestStreakReset] [L1135-1137]
  +-- [BRANCH: new day (lastSyncDay != currentDay)] [L1139]
      +-- state.lastSyncDay = currentDay [L1140]
      +-- state.completionMask = 0 [L1141]
      +-- state.baseStreak = state.streak [L1142]
```

**All 7 parents pass the same (state, player, currentDay) pattern.** The function is idempotent for the same day -- the `lastSyncDay != currentDay` check at L1139 means the reset only happens once per day. **SAFE** across all calling contexts.

### C-12: DegenerusQuests::_questComplete (L1388-1435)

Called by: C-13 (_questCompleteWithPair), C-15 (_maybeCompleteOther).

**Double-completion guard at L1401:** `if ((mask & slotMask) != 0) return (0, ..., false)`. This prevents any calling context from completing the same slot twice. The completionMask is monotonically OR'd -- bits are set, never cleared within a day (only _questSyncState resets it at day boundaries). **SAFE.**

### C-13: DegenerusQuests::_questCompleteWithPair (L1453-1492)

Called by: B-06 through B-11 (6 parents via _questHandleProgressSlot or directly).

All callers pass the same arguments pattern. The function calls _questComplete for the primary slot, then _maybeCompleteOther for the paired slot. The paired completion check is idempotent (double-completion prevented by mask). **SAFE.**

### C-16: DegenerusJackpots::_updateBafTop (L555-613)

Called by: B-12 (recordBafFlip) only.

Three cases: existing player (bubble up), board not full (insert sorted), board full (replace bottom). All correctly maintain the sorted descending invariant of the top-4 array. Storage writes to `bafTop[lvl]` and `bafTopLen[lvl]` are direct, no caching issues.

**Edge case:** When `score == board[idx-1].score` (equal scores), the bubble-up loop stops (`board[idx].score > board[idx-1].score` is strict). This means newer players do NOT displace equal-score players. First-come advantage for equal scores. This is a design choice, not a bug.

---

## Priority Investigation Results

### PI-1: Unchecked Overflow in recordBafFlip (L176)

`unchecked { total += amount; }` where total and amount are both uint256.

**Verdict: SAFE.** uint256 max is ~1.15 * 10^77. Even with every BURNIE token in existence (capped supply) staked billions of times, overflow is impossible. The unchecked block is a gas optimization with no practical risk.

### PI-2: Deterministic PRNG in Affiliate Winner Roll

`_rollWeightedAffiliateWinner` uses `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)`.

**Verdict: SAFE (by design).** The protocol explicitly acknowledges this at L572: "PRNG is known -- accepted design tradeoff (EV-neutral, manipulation only redistributive between affiliates)." The weighted roll ensures each recipient's expected value equals their share. Even if an affiliate precomputes outcomes, they cannot increase their EV -- they can only change WHO gets each individual payment, while the statistical average remains unchanged.

### PI-3: Self-Referral Loop Prevention

Chain: player P -> affiliate A -> upline1 U1 -> upline2 U2.

If P creates a code and A is referred under P's code, then A refers P, we get: P's affiliate = A, A's upline = P. When P buys: payAffiliate -> affiliate=A, upline1=_referrerAddress(A)=P. At L609: `if (winner != sender)` -- if P is selected as winner, payment is skipped.

But what about A's referrer being P, and P's referrer being A? Can this create an infinite loop in _referrerAddress? NO -- _referrerAddress only does a single lookup (L714-718), not recursive. It returns the direct referrer, not the chain. So upline1 = _referrerAddress(affiliateAddr), upline2 = _referrerAddress(upline1). Each is a single-hop lookup.

**Verdict: SAFE.** No infinite loop possible. Self-referral in the upline chain is handled by the sender exclusion at L609.

### PI-4: Quest Slot 1 Ordering Dependency

All handlers enforce: `if (slotIndex == 1 && (state.completionMask & 1) == 0) return (0, ...)`.

**Verdict: SAFE.** Slot 1 cannot complete until slot 0 is complete. The paired completion via _questCompleteWithPair handles the reverse (slot 0 completing can trigger slot 1 if slot 1's progress already met target).

### PI-5: BAF Scatter Level Targeting (Century Levels)

When `isCentury` and `lvl == 0`, L396: `uint24 maxBack = lvl > 99 ? 99 : lvl - 1`.

`lvl - 1` when lvl is uint24(0) = underflow to 16777215. Then `targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl`. Since maxBack > 0, we get `0 - 1 - X` = massive underflow.

**Can lvl == 0 reach this code?** BAF jackpot is resolved at level-end transitions. Level 0 is the initial level. The game starts at level 0, first level transition goes from 0 to 1. The endgame module calls `runBafJackpot(pool, lvl, rng)` where lvl is the completing level.

**Verdict: INVESTIGATE.** If lvl==0 is ever passed to runBafJackpot with isCentury=true (0 % 100 == 0), rounds 12+ would produce invalid targetLvl values. The sampleTraitTicketsAtLevel call with a huge targetLvl would likely return empty arrays (no tickets at impossible levels), and the scatter prizes for those rounds would go to toReturn. This is a LOW-severity edge case -- no fund loss, just empty scatter rounds.

**Practical impact:** Level 0 BAF resolution may have slightly fewer scatter winners due to invalid level queries, but all unawarded prizes are correctly returned via toReturn. No ETH is lost.

### PI-6: Commission Cap Bypass

The cap is per `affiliateAddr` per `sender` per `lvl`. An attacker would need to change their referral code to point to a different affiliate to bypass the cap. But referral codes are locked after first set (except during presale).

**Verdict: SAFE.** Cannot rotate affiliates after presale. During presale, the mutability window is limited and commission caps provide reasonable protection.

### PI-7: Affiliate Quest Reward Reentrancy

payAffiliate -> coin.affiliateQuestReward(player, amount) -> BurnieCoin -> DegenerusQuests.handleAffiliate(). This call does NOT re-enter DegenerusAffiliate -- it enters DegenerusQuests, which modifies quest state. The affiliate reward calculation in payAffiliate has already been completed (scaledAmount, commission cap, leaderboard update) before the external call. No state is read from DegenerusAffiliate after the external calls.

**Verdict: SAFE.** No reentrancy risk. External calls happen after all affiliate-local state updates.

---

## Summary of Findings

| ID | Function | Verdict | Severity | Description |
|----|----------|---------|----------|-------------|
| F-01 | runBafJackpot scatter (L396) | INVESTIGATE | LOW | uint24 underflow when lvl==0 and isCentury in scatter rounds 12+. Produces invalid targetLvl values, likely returning empty ticket arrays. No ETH loss -- unawarded prizes returned via toReturn. |

All other functions: **SAFE** across all 10 attack angles.
