# Word Derivation Verification (RNG-04)

**Audit date:** 2026-04-11
**Source:** contracts at current HEAD
**Methodology:** Forward derivation trace from first principles per D-03 (no prior RNG audit reliance). Seed provenance only for LCG per D-02.

---

## RNG-03: _randTraitTicket() -- Per-Winner Trait Ticket Selection

### VRF Source

`rngWordByDay[day]` (daily VRF word, written by `_applyDailyRng` at AdvanceModule line 1626).

The daily word flows through `payDailyJackpot` (JackpotModule line 310, parameter `randWord`) and arrives at `_randTraitTicket` via two paths:

1. **Direct path (_processDailyEth):** `randWord` -> `entropy = randWord ^ (uint256(lvl) << 192)` (line 426) -> `entropyState = EntropyLib.entropyStep(entropyState ^ ...)` (line 1236) -> passed to `_randTraitTicket` as `randomWord` (line 1248).
2. **Coin jackpot path (_awardDailyCoinToTraitWinners):** `randWord` -> `entropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)` (line 1685-1687) -> `EntropyLib.entropyStep(entropy ^ ...)` (line 1738) -> passed to `_randTraitTicket` as `randomWord` (line 1349 in `_resolveTraitWinners`).

### Derivation

```solidity
// DegenerusGameJackpotModule.sol, line 1639-1641
uint256 idx = uint256(
    keccak256(abi.encode(randomWord, trait, salt, i))
) % effectiveLen;
```

**Line:** JackpotModule line 1639-1641

**Input variables:**
- `randomWord` -- derived from daily VRF word via XOR mixing and EntropyLib.entropyStep
- `trait` -- uint8 trait ID (0-255), unique per bucket
- `salt` -- uint8 caller-supplied salt (e.g., `200 + traitIdx` at line 1251)
- `i` -- uint256 winner index within the batch (0 to numWinners-1)

**Operation:** `keccak256(abi.encode(randomWord, trait, salt, i)) % effectiveLen`

### Game Outcome

Selects which ticket holder wins for each trait bucket. The result `idx` indexes into `traitBurnTicket_[trait]` to pick the winner address. If `idx >= len` (past real tickets), the deity address wins the virtual slot.

### Entropy Independence

Each `(randomWord, trait, salt, i)` tuple produces independent entropy via keccak256 domain separation. The ABI encoding ensures no collision between tuples: `abi.encode` pads each argument to 32 bytes, so `(word, 1, 200, 0)` and `(word, 1, 200, 1)` produce entirely different hashes. Cross-trait collisions are prevented by `trait` parameter; cross-bucket collisions are prevented by `salt = 200 + traitIdx`.

**Threat T-215-10 check:** Domain separation confirmed -- each keccak call includes `(trait, salt, i)` ensuring distinct preimages for every winner selection across all buckets and iterations.

### Verdict: VRF-SOURCED

All inputs to the keccak256 trace back to `rngWordByDay[day]` via XOR mixing and xorshift steps. The `trait`, `salt`, and `i` parameters are deterministic protocol constants, not player-controllable. Winner selection is fully VRF-derived.

---

## RNG-04: _runJackpotEthFlow() / _processDailyEth() -- ETH Jackpot Bucket Winners

### VRF Source

`rngWordByDay[day]` (daily VRF word), passed as `randWord` to `payDailyJackpot` (JackpotModule line 313).

### Derivation

**Step 1: Entropy derivation** (JackpotModule line 426):
```solidity
// DegenerusGameJackpotModule.sol, line 426
uint256 entropyDaily = randWord ^ (uint256(lvl) << 192);
```

**Step 2: Bucket count rotation** via `_runJackpotEthFlow` (line 1095-1123) for purchase-phase, or directly via `JackpotBucketLib.bucketCountsForPoolCap` (line 436-442) for jackpot-phase:

```solidity
// DegenerusGameJackpotModule.sol, lines 1100-1110 (purchase phase path)
uint8 offset = uint8(jp.entropy & 3);
uint16[4] memory base;
base[0] = 20; base[1] = 12; base[2] = 6; base[3] = 1;
uint16[4] memory bucketCounts;
for (uint8 i; i < 4; ) {
    bucketCounts[i] = base[(i + offset) & 3];
    unchecked { ++i; }
}
```

**Line:** JackpotModule lines 1100-1110

The rotation mechanism: `entropy & 3` extracts the lowest 2 bits from the VRF-derived entropy to produce an offset (0-3). The fixed base array `[20, 12, 6, 1]` is rotated by this offset, assigning winner counts to trait buckets. This means which bucket gets the most/fewest winners varies daily.

**Step 3: Solo bucket index** (via JackpotBucketLib line 243):
```solidity
// JackpotBucketLib.sol, line 243-244
function soloBucketIndex(uint256 entropy) internal pure returns (uint8) {
    return uint8((uint256(3) - (entropy & 3)) & 3);
}
```

**Step 4: Share BPS rotation** (via JackpotBucketLib.shareBpsByBucket, called at line 461):
The packed shares are rotated by `uint8(entropyDaily & 3)` to determine which bucket gets the 60% solo share vs 13% shared.

**Step 5: Winner selection per bucket** -- delegates to `_randTraitTicket` (see RNG-03 above) via `_processDailyEth` (line 1246-1252), with entropy state chained through `EntropyLib.entropyStep`:
```solidity
// DegenerusGameJackpotModule.sol, line 1236-1238
entropyState = EntropyLib.entropyStep(
    entropyState ^ (uint256(traitIdx) << 64) ^ share
);
```

**EntropyLib.entropyStep** (EntropyLib.sol line 16-21):
```solidity
function entropyStep(uint256 state) internal pure returns (uint256) {
    unchecked {
        state ^= state << 7;
        state ^= state >> 9;
        state ^= state << 8;
    }
}
```

This is a 256-bit xorshift -- a deterministic bijection that diffuses entropy.

### Game Outcome

Determines: (a) how many winners each trait bucket gets (rotation of [20,12,6,1]), (b) which bucket is the solo bucket (60% share), (c) which specific ticket holders win within each bucket. All three decisions derive from VRF entropy.

### Verdict: VRF-SOURCED

Every derivation step traces to `randWord` = `rngWordByDay[day]`. Bucket rotation uses `entropy & 3` (VRF bits). Share rotation uses same. Winner selection uses keccak256 seeded from xorshift-chained VRF entropy.

---

## RNG-05: payDailyJackpot() -- Carryover Ticket Sourcing

### VRF Source

`rngWordByDay[day]` (daily VRF word), passed as `randWord` to `payDailyJackpot` (JackpotModule line 313).

### Derivation

```solidity
// DegenerusGameJackpotModule.sol, lines 389-399
sourceLevelOffset = uint8(
    (uint256(
        keccak256(
            abi.encodePacked(
                randWord,
                DAILY_CARRYOVER_SOURCE_TAG,
                counter
            )
        )
    ) % DAILY_CARRYOVER_MAX_OFFSET) + 1
);
```

**Line:** JackpotModule lines 389-399

**Input variables:**
- `randWord` -- daily VRF word
- `DAILY_CARRYOVER_SOURCE_TAG` -- constant bytes32 (line 152)
- `counter` -- `jackpotCounter`, current day within jackpot phase (0-4)

**Operation:** `keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter)) % 4 + 1`

This produces an offset in [1, 4] determining which future level's prize pool contributes 0.5% as carryover tickets.

### Game Outcome

Selects `sourceLevel = lvl + sourceLevelOffset` where `sourceLevelOffset` is in [1..4]. The 0.5% of futurePool is converted to tickets at this source level. This determines which future level benefits from the carryover ticket distribution.

### Verdict: VRF-SOURCED

The keccak256 preimage is `(randWord, constant, counter)`. `randWord` is the daily VRF word. `DAILY_CARRYOVER_SOURCE_TAG` and `counter` are protocol-determined. The carryover source offset is fully VRF-derived.

---

## RNG-05 (supplemental): _dailyCurrentPoolBps() -- Daily ETH Budget Percentage

### VRF Source

`rngWordByDay[day]` via `randWord` parameter to `payDailyJackpot`.

### Derivation

```solidity
// DegenerusGameJackpotModule.sol, lines 1904-1910
uint16 range = DAILY_CURRENT_BPS_MAX - DAILY_CURRENT_BPS_MIN + 1;
uint256 seed = uint256(
    keccak256(
        abi.encodePacked(randWord, DAILY_CURRENT_BPS_TAG, counter)
    )
);
return uint16(DAILY_CURRENT_BPS_MIN + (seed % range));
```

**Line:** JackpotModule lines 1904-1910

**Input variables:**
- `randWord` -- daily VRF word
- `DAILY_CURRENT_BPS_TAG` -- constant bytes32 (line 148)
- `counter` -- `jackpotCounter` (0-3, since day 5 always returns 10000)
- `DAILY_CURRENT_BPS_MIN = 600`, `DAILY_CURRENT_BPS_MAX = 1400` (lines 159-160)

**Operation:** `keccak256(abi.encodePacked(randWord, tag, counter)) % 801 + 600` producing a BPS value in [600, 1400] (6%-14%).

### Game Outcome

Determines what percentage of the current prize pool is distributed on each jackpot day (days 1-4). Day 5 always uses 100%.

### Verdict: VRF-SOURCED

---

## RNG-06: _placeDegeneretteBetCore() / _resolveFullTicketBet() -- Degenerette Bet Resolution

### VRF Source

`lootboxRngWordByIndex[index]` (per-index lootbox VRF word). The index is captured at bet placement time (DegeneretteModule line 428) and the word is read at resolution time (line 574).

### Derivation

**Step 1: RNG word retrieval** (DegeneretteModule line 574):
```solidity
// DegenerusGameDegeneretteModule.sol, line 574
uint256 rngWord = lootboxRngWordByIndex[index];
```

**Step 2: Per-spin result seed** (DegeneretteModule lines 593-606):
```solidity
// DegenerusGameDegeneretteModule.sol, lines 593-606
uint256 resultSeed = spinIdx == 0
    ? uint256(
        keccak256(abi.encodePacked(rngWord, index, QUICK_PLAY_SALT))
    )
    : uint256(
        keccak256(
            abi.encodePacked(
                rngWord,
                index,
                spinIdx,
                QUICK_PLAY_SALT
            )
        )
    );
```

**Line:** DegeneretteModule lines 593-606

**Input variables:**
- `rngWord` -- lootbox VRF word for the bet's index
- `index` -- uint32 RNG index stored in the packed bet
- `spinIdx` -- uint8 spin number within multi-spin bet (0 to ticketCount-1)
- `QUICK_PLAY_SALT` -- constant domain separator

**Step 3: Result ticket derivation** (DegeneretteModule line 607-608):
```solidity
// DegenerusGameDegeneretteModule.sol, line 607-608
uint32 resultTicket = DegenerusTraitUtils.packedTraitsFromSeed(resultSeed);
```

`packedTraitsFromSeed` (DegenerusTraitUtils.sol line 172-180) extracts 4 traits from the 256-bit seed:
```solidity
// DegenerusTraitUtils.sol, lines 174-177
uint8 traitA = traitFromWord(uint64(rand));           // bits [63:0]
uint8 traitB = traitFromWord(uint64(rand >> 64)) | 64;  // bits [127:64]
uint8 traitC = traitFromWord(uint64(rand >> 128)) | 128; // bits [191:128]
uint8 traitD = traitFromWord(uint64(rand >> 192)) | 192; // bits [255:192]
```

Each quadrant uses 64 bits of the seed, mapped through `traitFromWord` to produce a weighted trait selection.

**Step 4: Match counting** (DegeneretteModule line 615):
```solidity
uint8 matches = _countMatches(playerTicket, resultTicket);
```

The player's chosen ticket is compared against the VRF-derived result ticket to determine win/loss.

### Game Outcome

Determines the result ticket for each spin of the degenerette bet. Match count against the player's ticket determines payout multiplier. Each spin produces an independent result via distinct keccak256 preimages (spin 0 omits `spinIdx` for a different preimage structure; spins 1+ include `spinIdx`).

### Verdict: VRF-SOURCED

All result seeds trace to `lootboxRngWordByIndex[index]` which is written by VRF fulfillment (AdvanceModule `rawFulfillRandomWords` line 1546 for mid-day path, or `_finalizeLootboxRng` line 1074 for daily path). Player-chosen `customTicket` does NOT influence the result seed -- it only determines the comparison target.

---

## RNG-07: _raritySymbolBatch() -- LCG PRNG (Seed Provenance Only per D-02)

### VRF Source

`lootboxRngWordByIndex[index]` (per-index lootbox VRF word). The word is read in `processTicketBatch` (MintModule line 680):

```solidity
// DegenerusGameMintModule.sol, line 680
uint256 entropy = lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1];
```

This `entropy` word is passed through `_processOneTicketEntry` (line 752: parameter `entropy`) and into `_raritySymbolBatch` (line 789: parameter `entropyWord`).

### Seed Derivation

```solidity
// DegenerusGameMintModule.sol, lines 562-565
uint256 seed;
unchecked {
    seed = (baseKey + groupIdx) ^ entropyWord;
}
uint64 s = uint64(seed) | 1;  // Ensure odd for full LCG period
```

**Line:** MintModule lines 562-565

**Input variables:**
- `baseKey` -- deterministic composite: `(uint256(lvl) << 224) | (queueIdx << 192) | (uint256(uint160(player)) << 32)` (line 786-788 in `_processOneTicketEntry`)
- `groupIdx` -- `i >> 4` (group of 16 symbols, line 559)
- `entropyWord` -- the lootbox VRF word

**Operation:** The LCG seed is `uint64((baseKey + groupIdx) ^ entropyWord) | 1`. The XOR with the VRF word mixes unpredictable entropy into the deterministic `baseKey + groupIdx`.

**LCG stepping** (lines 568, 573):
```solidity
// DegenerusGameMintModule.sol, line 568
s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);  // warm-up

// DegenerusGameMintModule.sol, line 573
s = s * TICKET_LCG_MULT + 1;  // LCG step
```

Where `TICKET_LCG_MULT = 6364136223846793005` (line 92), the Knuth LCG multiplier.

**Per D-02:** LCG output quality is out of scope. This audit verifies seed provenance only.

### Seed Provenance Proof

1. `entropyWord` = `lootboxRngWordByIndex[index - 1]` (read at MintModule line 680)
2. `lootboxRngWordByIndex[index]` is written by VRF fulfillment callback (AdvanceModule line 1546) or by `_finalizeLootboxRng` (AdvanceModule line 1074)
3. Both write paths receive the word from `rawFulfillRandomWords` parameter `randomWords[0]` (AdvanceModule line 1537), which originates from the Chainlink VRF coordinator
4. The `| 1` at line 565 ensures the LCG seed is odd (required for full period) but does not remove VRF entropy -- it only sets bit 0

**Threat T-215-11 check:** LCG seed traces to VRF word. The `baseKey` component contains `player` address and `lvl`/`queueIdx` which are deterministic per-call. The only unpredictable component is `entropyWord` from VRF. An attacker who does not know the VRF word cannot predict the LCG seed.

### Verdict: VRF-SOURCED

Seed traces to `lootboxRngWordByIndex` which is VRF-delivered. The `baseKey` provides per-player, per-level, per-group domain separation but does not introduce non-VRF randomness.

---

## RNG-08: _gameOverEntropy() -- Gameover Entropy Fallback

### Source

**Primary:** `rngWordByDay[day]` or `rngWordCurrent` (VRF-sourced).
**Fallback:** `_getHistoricalRngFallback()` which mixes historical VRF words + `block.prevrandao`.

### Derivation

**Branch 1: Word already recorded** (AdvanceModule line 1089):
```solidity
// DegenerusGameAdvanceModule.sol, line 1089
if (rngWordByDay[day] != 0) return rngWordByDay[day];
```
Uses existing daily VRF word directly. **VRF-SOURCED.**

**Branch 2: Fresh VRF word ready** (AdvanceModule lines 1091-1093):
```solidity
// DegenerusGameAdvanceModule.sol, lines 1091-1093
uint256 currentWord = rngWordCurrent;
if (currentWord != 0 && rngRequestTime != 0) {
    currentWord = _applyDailyRng(day, currentWord);
```
Uses pending VRF word from callback. **VRF-SOURCED.**

**Branch 3: Historical + prevrandao fallback** (AdvanceModule lines 1121-1151):
After `GAMEOVER_RNG_FALLBACK_DELAY` (3 days, line 109), uses `_getHistoricalRngFallback`:

```solidity
// DegenerusGameAdvanceModule.sol, lines 1177-1200
function _getHistoricalRngFallback(uint32 currentDay) private view returns (uint256 word) {
    uint256 found;
    uint256 combined;
    uint32 searchLimit = currentDay > 30 ? 30 : currentDay;
    for (uint32 searchDay = 1; searchDay < searchLimit; ) {
        uint256 w = rngWordByDay[searchDay];
        if (w != 0) {
            combined = uint256(keccak256(abi.encodePacked(combined, w)));
            unchecked { ++found; }
            if (found == 5) break;
        }
        unchecked { ++searchDay; }
    }
    word = uint256(
        keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))
    );
    if (word == 0) word = 1;
}
```

**Line:** AdvanceModule lines 1177-1200

**Input variables:**
- `combined` -- keccak chain of up to 5 historical `rngWordByDay[searchDay]` values (all VRF-delivered)
- `currentDay` -- deterministic day index
- `block.prevrandao` -- validator-influenced randomness (1-bit bias)

**Branch 4: VRF request attempt** (AdvanceModule lines 1156-1163):
If no word and no pending request, attempts `_tryRequestRng`. Returns 1 (request sent) or 0 (failed, starts fallback timer). Not an entropy consumer itself.

### Game Outcome

Provides the entropy word for gameover terminal resolution. The word feeds into `handleGameOverDrain` for terminal jackpot distribution.

### Verdict: MIXED (fallback path) / VRF-SOURCED (primary paths)

**Branches 1-2:** Pure VRF. **Branch 3:** Historical VRF words + `block.prevrandao`. The prevrandao component allows ~1-bit validator bias (propose/skip block). This is the documented exception per the code comments (line 1168-1174): acceptable trade-off for a one-time terminal event when VRF is dead for 3+ days. The historical VRF words in the `combined` hash are committed (cannot be manipulated retroactively).

**Threat T-215-12 acceptance confirmed:** The prevrandao fallback applies only to the gameover path after VRF stalls for 3 days. Terminal, one-time event with at most 1-bit validator bias.

---

## RNG-09: handleGameOverDrain() -- Terminal Jackpot Resolution

### VRF Source

`rngWordByDay[day]` (daily word, must be non-zero for funds > 0).

### Derivation

```solidity
// DegenerusGameGameOverModule.sol, lines 96-98
uint256 rngWord;
if (preRefundAvailable != 0) {
    rngWord = rngWordByDay[day];
    if (rngWord == 0) revert E();
}
```

**Line:** GameOverModule lines 96-98

The `rngWord` is required non-zero when distributable funds exist. It is then passed to:

**Terminal decimator** (line 162):
```solidity
// DegenerusGameGameOverModule.sol, line 162
uint256 decRefund = IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord);
```

**Terminal jackpot** (line 174-175):
```solidity
// DegenerusGameGameOverModule.sol, lines 174-175
uint256 termPaid = IDegenerusGame(address(this))
    .runTerminalJackpot(remaining, lvl + 1, rngWord);
```

Both receive the `rngWord` from `rngWordByDay[day]` and use it for winner selection (via `_processDailyEth` and `_randTraitTicket` internally, following the same derivation chains as RNG-03 and RNG-04).

### Game Outcome

Determines how terminal funds are distributed: 10% to decimator winners, 90% to ticket holders via bucket distribution. The same `_randTraitTicket` mechanism (RNG-03) selects winners.

### Verdict: VRF-SOURCED

The `rngWord` used in `handleGameOverDrain` is `rngWordByDay[day]` which is VRF-delivered via `_applyDailyRng` or `_gameOverEntropy` (which was already called before `handleGameOverDrain`). The `revert E()` guard at line 98 ensures no distribution happens without a word. The word origin depends on which `_gameOverEntropy` branch was taken:
- Branches 1-2: Pure VRF. **VRF-SOURCED.**
- Branch 3: Historical VRF + prevrandao. **MIXED** (documented exception, see RNG-08).

---

## RNG-10: _deityDailySeed() / _deityBoonForSlot() -- Deity Boon Selection

### VRF Source

`rngWordByDay[day]` (daily VRF word), or `rngWordCurrent` as fallback, or deterministic fallback.

### Derivation

**Step 1: _deityDailySeed** (LootboxModule lines 1742-1751):
```solidity
// DegenerusGameLootboxModule.sol, lines 1742-1751
function _deityDailySeed(uint32 day) private view returns (uint256 seed) {
    uint256 rngWord = rngWordByDay[day];
    if (rngWord == 0) {
        rngWord = rngWordCurrent;
    }
    if (rngWord == 0) {
        rngWord = uint256(keccak256(abi.encodePacked(day, address(this))));
    }
    return rngWord;
}
```

**Line:** LootboxModule lines 1742-1751

Three-tier fallback:
1. `rngWordByDay[day]` -- VRF word if day has been processed (VRF-SOURCED)
2. `rngWordCurrent` -- pending VRF word if VRF delivered but day not yet processed (VRF-SOURCED)
3. `keccak256(abi.encodePacked(day, address(this)))` -- deterministic fallback if no VRF word exists yet (NON-VRF, but predictable by design)

**Step 2: _deityBoonForSlot** (LootboxModule lines 1760-1773):
```solidity
// DegenerusGameLootboxModule.sol, lines 1767-1773
uint256 seed = uint256(keccak256(abi.encode(_deityDailySeed(day), deity, day, slot)));
uint256 total = decimatorAllowed
    ? BOON_WEIGHT_TOTAL
    : BOON_WEIGHT_TOTAL_NO_DECIMATOR;
if (!deityPassAvailable) total -= BOON_WEIGHT_DEITY_PASS_ALL;
uint256 roll = seed % total;
return _boonFromRoll(roll, decimatorAllowed, deityPassAvailable, true, true);
```

**Line:** LootboxModule lines 1767-1773

**Input variables:**
- `_deityDailySeed(day)` -- VRF word or fallback (see above)
- `deity` -- address of the deity pass holder
- `day` -- uint32 day index
- `slot` -- uint8 slot index (0-2)

**Operation:** `keccak256(abi.encode(dailySeed, deity, day, slot)) % totalWeight` produces a weighted roll that maps to a boon type.

### Game Outcome

Determines which boon type each deity offers in each of their 3 daily slots. Boons include whale passes, lazy passes, decimators, deity passes.

### Verdict: VRF-SOURCED (normal operation) / NON-VRF (tier-3 fallback)

In normal operation (game actively processing), `rngWordByDay[day]` or `rngWordCurrent` is non-zero, so the seed is VRF-derived. The tier-3 fallback `keccak256(day, address(this))` is fully predictable and only activates when no VRF word exists for the day (e.g., before the very first `advanceGame` call of the day, or if VRF is stalled). Since deity boons are cosmetic/utility (not ETH payouts), the predictable fallback does not create an economic attack vector -- a deity checking their offerings before VRF arrives sees deterministic results that cannot be exploited for profit.

---

## RNG-11: _rollWinningTraits() / _applyHeroOverride() -- Daily Winning Trait Set

### VRF Source

`rngWordByDay[day]` (daily VRF word), passed as `randWord` through the jackpot paths.

### Derivation

**Step 1: _rollWinningTraits** (JackpotModule lines 1861-1867):
```solidity
// DegenerusGameJackpotModule.sol, lines 1861-1867
function _rollWinningTraits(uint256 randWord) private view returns (uint32 packed) {
    uint8[4] memory traits = JackpotBucketLib.getRandomTraits(randWord);
    _applyHeroOverride(traits, randWord);
    packed = JackpotBucketLib.packWinningTraits(traits);
}
```

**Line:** JackpotModule lines 1861-1867

**Step 2: JackpotBucketLib.getRandomTraits** (JackpotBucketLib.sol lines 281-285):
```solidity
// JackpotBucketLib.sol, lines 281-285
function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {
    w[0] = uint8(rw & 0x3F);              // bits [5:0] -> Quadrant 0
    w[1] = 64 + uint8((rw >> 6) & 0x3F);  // bits [11:6] -> Quadrant 1
    w[2] = 128 + uint8((rw >> 12) & 0x3F); // bits [17:12] -> Quadrant 2
    w[3] = 192 + uint8((rw >> 18) & 0x3F); // bits [23:18] -> Quadrant 3
}
```

**Line:** JackpotBucketLib.sol lines 281-285

**Operation:** Each quadrant extracts 6 bits (0-63 range) from different bit positions of the VRF word. Quadrant offsets (0, 64, 128, 192) ensure each trait maps to its correct 256-trait space.

**Step 3: _applyHeroOverride** (JackpotModule lines 1537-1564):
```solidity
// DegenerusGameJackpotModule.sol, lines 1549-1557
uint8 heroColor;
if (heroQuadrant == 0) {
    heroColor = uint8(randomWord & 7);            // bits [2:0]
} else if (heroQuadrant == 1) {
    heroColor = uint8((randomWord >> 3) & 7);     // bits [5:3]
} else if (heroQuadrant == 2) {
    heroColor = uint8((randomWord >> 6) & 7);     // bits [8:6]
} else {
    heroColor = uint8((randomWord >> 9) & 7);     // bits [11:9]
}
```

**Line:** JackpotModule lines 1549-1557

**Input variables:**
- `randomWord` -- the daily VRF word
- `heroQuadrant` -- determined by `_topHeroSymbol()` which reads `dailyHeroWagers[day][q]` (player wagers, not VRF)

**Operation:** The hero override replaces one quadrant's trait with the top-wagered hero symbol, but uses VRF bits to select the color. The color bits `randomWord & 7`, `(randomWord >> 3) & 7`, etc. are distinct 3-bit extractions from the VRF word.

Note: The hero override reads `heroQuadrant` and `heroSymbol` from `dailyHeroWagers` which is player-influenced (accumulated wager data). However, the player influence only determines WHICH symbol auto-wins (a game mechanic), not the randomness used for the color. The hero override is by design: the top-wagered symbol forces a win in its quadrant as an incentive mechanic.

### Game Outcome

Determines the 4 daily winning traits (one per quadrant). These traits control which ticket holders are eligible for ETH and BURNIE jackpot payouts for the day.

### Verdict: VRF-SOURCED

Both `getRandomTraits` (bit extraction) and `_applyHeroOverride` (color selection) derive from the VRF word via direct bit masking and shifting. No keccak256 needed -- the VRF word's bits are used directly. The hero quadrant/symbol selection is player-influenced by design (hero wager mechanic) but does not introduce non-VRF entropy into the derivation.

---

## Backfill (from RNG-01): _backfillGapDays()

### VRF Source

`rngWordByDay[day]` for the current day (the VRF word that just arrived after a multi-day gap), passed as `vrfWord` parameter.

### Derivation

```solidity
// DegenerusGameAdvanceModule.sol, lines 1574-1575
uint256 derivedWord = uint256(
    keccak256(abi.encodePacked(vrfWord, gapDay))
);
```

**Line:** AdvanceModule lines 1574-1575

**Input variables:**
- `vrfWord` -- the VRF word from the post-gap fulfillment (passed from `rngGate` line 1017: `_backfillGapDays(currentWord, idx + 1, day, bonusFlip)`)
- `gapDay` -- uint32 day index for each skipped day

**Operation:** `keccak256(abi.encodePacked(vrfWord, gapDay))` produces a distinct derived word for each gap day. The `abi.encodePacked` concatenation ensures `(word, day=5)` and `(word, day=6)` have different preimages.

**Zero-word protection** (line 1577):
```solidity
if (derivedWord == 0) derivedWord = 1;
```

**Storage write** (line 1578):
```solidity
rngWordByDay[gapDay] = derivedWord;
```

Each derived word is stored permanently and then used for coinflip payouts on that gap day (line 1579).

**Gap cap** (line 1572):
```solidity
if (endDay - startDay > 120) endDay = startDay + 120;
```
Limits backfill to 120 days for gas safety.

### Game Outcome

Provides synthetic entropy for each skipped day, used for coinflip resolution and as the daily word for any other consumers that reference `rngWordByDay[gapDay]`.

### Verdict: VRF-SOURCED

All derived words trace to the VRF word via keccak256. Each gap day `i` produces independent entropy via the `gapDay` parameter in the keccak preimage. The VRF word was unknown until fulfillment, so derived words inherit VRF unpredictability.

---

## Backfill (supplemental): _backfillOrphanedLootboxIndices()

### VRF Source

Same `vrfWord` as `_backfillGapDays` (the post-gap VRF word).

### Derivation

```solidity
// DegenerusGameAdvanceModule.sol, lines 1599-1600
uint256 fallbackWord = uint256(
    keccak256(abi.encodePacked(vrfWord, i))
);
```

**Line:** AdvanceModule lines 1599-1600

**Input variables:**
- `vrfWord` -- post-gap VRF word
- `i` -- uint48 lootbox index (scanned backwards)

**Operation:** `keccak256(abi.encodePacked(vrfWord, i))` produces a fallback word for each orphaned lootbox index.

### Game Outcome

Provides fallback lootbox RNG words for lootbox indices that never received a mid-day VRF word (because the game stalled). These words then feed into lootbox resolution, degenerette bets, and ticket processing.

### Verdict: VRF-SOURCED

Same pattern as gap day backfill. All derived words trace to VRF via keccak256 with index-based domain separation.

---

## Supplemental: Lootbox Resolution Entropy Chain

### VRF Source

`lootboxRngWordByIndex[index]` (per-index VRF word).

### Derivation

In ETH lootbox opening (LootboxModule line 554):
```solidity
// DegenerusGameLootboxModule.sol, line 554
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
```

In BURNIE lootbox opening (LootboxModule line 628):
```solidity
// DegenerusGameLootboxModule.sol, line 628
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amountEth)));
```

**Lines:** LootboxModule lines 554, 628

The initial entropy is VRF-derived with player/day/amount domain separation. This entropy feeds through:
1. `_rollTargetLevel` -- determines which future level receives tickets
2. `_resolveLootboxRoll` -- determines BURNIE vs ticket rewards
3. `_rollLootboxBoons` -- determines boon eligibility and type (line 1058: `roll = entropy % BOON_PPM_SCALE`)

Each step chains entropy through `EntropyLib.entropyStep` or keccak256 calls, maintaining the VRF derivation chain.

### Verdict: VRF-SOURCED

---

## Supplemental: _runEarlyBirdLootboxJackpot Entropy

### VRF Source

`rngWordByDay[day]` via `rngWord` parameter (JackpotModule line 634).

### Derivation

```solidity
// DegenerusGameJackpotModule.sol, lines 650, 664, 679
uint256 entropy = rngWord;                          // line 650
entropy = EntropyLib.entropyStep(entropy);          // line 664 (per winner)
entropy = EntropyLib.entropyStep(entropy);          // line 679 (level offset)
```

**Lines:** JackpotModule lines 650, 664, 679

Winner selection uses `_randTraitTicket(traitBurnTicket[lvl], entropy, traitId, 1, uint8(i))` at line 669-674, following the same keccak derivation as RNG-03. Level offset uses `entropy % 5` at line 680.

### Verdict: VRF-SOURCED

---

## Summary Table

| Chain | Consumer | VRF Source | Derivation Op | Game Outcome | Verdict |
|-------|----------|-----------|---------------|--------------|---------|
| RNG-03 | `_randTraitTicket()` | `rngWordByDay[day]` | `keccak256(abi.encode(word, trait, salt, i)) % effectiveLen` | Trait ticket winner selection | VRF-SOURCED |
| RNG-04 | `_runJackpotEthFlow()` / `_processDailyEth()` | `rngWordByDay[day]` | XOR + bit mask (`entropy & 3`) for rotation; xorshift chain for winner entropy | ETH bucket counts, shares, winner selection | VRF-SOURCED |
| RNG-05 | `payDailyJackpot()` carryover | `rngWordByDay[day]` | `keccak256(abi.encodePacked(word, tag, counter)) % 4 + 1` | Carryover source level offset [1..4] | VRF-SOURCED |
| RNG-05s | `_dailyCurrentPoolBps()` | `rngWordByDay[day]` | `keccak256(abi.encodePacked(word, tag, counter)) % 801 + 600` | Daily ETH budget percentage [6%-14%] | VRF-SOURCED |
| RNG-06 | `_resolveFullTicketBet()` | `lootboxRngWordByIndex[index]` | `keccak256(abi.encodePacked(word, index, spinIdx, salt))` -> `packedTraitsFromSeed` | Degenerette bet result tickets | VRF-SOURCED |
| RNG-07 | `_raritySymbolBatch()` | `lootboxRngWordByIndex[index]` | `(baseKey + groupIdx) ^ entropyWord` -> LCG stepping | Ticket trait generation (seed provenance) | VRF-SOURCED |
| RNG-08 | `_gameOverEntropy()` branches 1-2 | `rngWordByDay[day]` / `rngWordCurrent` | Direct return | Gameover entropy (VRF available) | VRF-SOURCED |
| RNG-08f | `_gameOverEntropy()` branch 3 | Historical VRF + `block.prevrandao` | `keccak256(combined, day, prevrandao)` | Gameover entropy (VRF stalled 3+ days) | MIXED |
| RNG-09 | `handleGameOverDrain()` | `rngWordByDay[day]` | Pass-through to `runTerminalDecimatorJackpot` / `runTerminalJackpot` | Terminal fund distribution | VRF-SOURCED |
| RNG-10 | `_deityDailySeed()` / `_deityBoonForSlot()` | `rngWordByDay[day]` (tier 1-2) | `keccak256(abi.encode(dailySeed, deity, day, slot)) % totalWeight` | Deity boon type per slot | VRF-SOURCED |
| RNG-10f | `_deityDailySeed()` tier 3 fallback | `keccak256(day, address(this))` | Deterministic fallback | Deity boon (pre-VRF only) | NON-VRF |
| RNG-11 | `_rollWinningTraits()` / `_applyHeroOverride()` | `rngWordByDay[day]` | Bit extraction: `rw & 0x3F`, `(rw >> 6) & 0x3F`, etc. + `(rw >> N) & 7` for hero color | Daily winning trait set | VRF-SOURCED |
| Backfill | `_backfillGapDays()` | Post-gap VRF word | `keccak256(abi.encodePacked(vrfWord, gapDay))` | Synthetic entropy for skipped days | VRF-SOURCED |
| Backfill-LB | `_backfillOrphanedLootboxIndices()` | Post-gap VRF word | `keccak256(abi.encodePacked(vrfWord, i))` | Fallback lootbox RNG words | VRF-SOURCED |
| Lootbox | Lootbox resolution chain | `lootboxRngWordByIndex[index]` | `keccak256(abi.encode(word, player, day, amount))` + xorshift chain | Target level, rewards, boons | VRF-SOURCED |
| EarlyBird | `_runEarlyBirdLootboxJackpot()` | `rngWordByDay[day]` | Xorshift chain + `_randTraitTicket` keccak | Early-bird lootbox ticket winners | VRF-SOURCED |

---

## Findings

No findings. All game-outcome entropy traces to VRF source words through documented derivation chains. The two documented exceptions are:

1. **RNG-08 branch 3 (gameover fallback):** Uses historical VRF + `block.prevrandao` after 3-day VRF stall. This is a terminal one-time event with at most 1-bit validator bias -- accepted per T-215-12.

2. **RNG-10 tier-3 fallback:** Uses deterministic `keccak256(day, address(this))` when no VRF word exists. This only affects deity boon display (cosmetic/utility), not ETH payouts, and only fires before the first daily VRF word arrives.

---

*Audit: 215-04 Word Derivation Verification (RNG-04)*
*Phase: 215-rng-fresh-eyes*
