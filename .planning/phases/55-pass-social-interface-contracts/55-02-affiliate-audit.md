# DegenerusAffiliate.sol -- Function-Level Audit

**Contract:** DegenerusAffiliate
**File:** contracts/DegenerusAffiliate.sol
**Lines:** 931
**Solidity:** 0.8.34
**Implements:** IDegenerusAffiliate
**Audit date:** 2026-03-07

## Summary

Multi-tier affiliate referral system with configurable rakeback. Features: affiliate code creation (permanent, first-come-first-served), 3-tier referral binding (player -> affiliate -> upline1 -> upline2), reward routing via three payout modes (Coinflip FLIP credit, Degenerette credit bucket, 50/50 coin split), leaderboard tracking per level, lootbox activity taper (linear 100% to 50% floor), weighted winner selection for multi-recipient payouts, per-referrer commission cap (0.5 ETH BURNIE/sender/level), and degenerette credit consumption. Fresh ETH reward rates: 25% (levels 0-3), 20% (levels 4+). Recycled ETH: 5% all levels.

## Function Audit

---

### Public/External -- Code Management

---

### `createAffiliateCode(bytes32 code_, uint8 rakebackPct)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function createAffiliateCode(bytes32 code_, uint8 rakebackPct) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `code_` (bytes32): affiliate code to claim; `rakebackPct` (uint8): rakeback percentage (0-25) |
| **Returns** | none |

**State Reads:** `affiliateCode[code_].owner` (via `_createAffiliateCode`)
**State Writes:** `affiliateCode[code_]` (via `_createAffiliateCode`)

**Callers:** Any external account (no access control)
**Callees:** `_createAffiliateCode(msg.sender, code_, rakebackPct)`

**ETH Flow:** None
**Invariants:** (1) Code cannot be bytes32(0) or REF_CODE_LOCKED; (2) Code must not already be taken; (3) rakeback <= 25
**NatSpec Accuracy:** Accurate. NatSpec correctly describes validation rules and permanence.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `setAffiliatePayoutMode(bytes32 code_, PayoutMode mode)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAffiliatePayoutMode(bytes32 code_, PayoutMode mode) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `code_` (bytes32): affiliate code to configure; `mode` (PayoutMode): routing mode enum |
| **Returns** | none |

**State Reads:** `affiliateCode[code_].owner`, `affiliateCode[code_].payoutMode`
**State Writes:** `affiliateCode[code_].payoutMode` (only if changed)

**Callers:** Any external account, but only code owner succeeds
**Callees:** None

**ETH Flow:** None
**Invariants:** Only the code owner can change payout mode; mode is one of {Coinflip=0, Degenerette=1, SplitCoinflipCoin=2}
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Event emitted even when mode is unchanged (no-op write skipped, but event always fires). Minor gas waste on redundant calls; informational only.
**Verdict:** CORRECT

---

### `affiliatePayoutMode(bytes32 code_)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliatePayoutMode(bytes32 code_) external view returns (PayoutMode mode)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `code_` (bytes32): affiliate code to query |
| **Returns** | `mode` (PayoutMode): current payout mode |

**State Reads:** `affiliateCode[code_].payoutMode`
**State Writes:** None

**Callers:** Any external account
**Callees:** None

**ETH Flow:** None
**Invariants:** Read-only; always returns a valid PayoutMode cast
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Public/External -- Referral System

---

### `referPlayer(bytes32 code_)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function referPlayer(bytes32 code_) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `code_` (bytes32): affiliate code to register under |
| **Returns** | none |

**State Reads:** `affiliateCode[code_].owner`, `playerReferralCode[msg.sender]`, (via `_vaultReferralMutable`) `game.lootboxPresaleActiveFlag()`
**State Writes:** `playerReferralCode[msg.sender]` (via `_setReferralCode`)

**Callers:** Any external account
**Callees:** `_vaultReferralMutable(existing)`, `_setReferralCode(msg.sender, code_)`

**ETH Flow:** None
**Invariants:** (1) Code must exist (owner != address(0)); (2) No self-referral; (3) Cannot overwrite existing referral unless currently VAULT/LOCKED during presale
**NatSpec Accuracy:** Accurate. Correctly describes one-time setting with presale override.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `getReferrer(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getReferrer(address player) external view returns (address)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to look up |
| **Returns** | `address`: referrer address, or address(0) if none |

**State Reads:** `playerReferralCode[player]`, `affiliateCode[code].owner` (via `_referrerAddress`)
**State Writes:** None

**Callers:** Any external account
**Callees:** `_referrerAddress(player)`

**ETH Flow:** None
**Invariants:** Returns address(0) for unset referrals; returns VAULT address for locked/VAULT codes
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Public/External -- Credit System

---

### `pendingDegeneretteCreditOf(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function pendingDegeneretteCreditOf(address player) external view returns (uint256 amount)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): address to query |
| **Returns** | `amount` (uint256): pending credit balance (18 decimals) |

**State Reads:** `pendingDegeneretteCredit[player]`
**State Writes:** None

**Callers:** Any external account
**Callees:** None

**ETH Flow:** None
**Invariants:** Read-only view of credit balance
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `consumeDegeneretteCredit(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDegeneretteCredit(address player, uint256 amount) external returns (uint256 consumed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `amount` (uint256): amount requested to consume |
| **Returns** | `consumed` (uint256): amount actually consumed |

**State Reads:** `pendingDegeneretteCredit[player]`
**State Writes:** `pendingDegeneretteCredit[player]`

**Callers:** DegenerusGame contract only (onlyGame check via `msg.sender != ContractAddresses.GAME`)
**Callees:** None

**ETH Flow:** None
**Invariants:** (1) Only GAME can call; (2) consumed <= balance; (3) consumed <= amount; (4) newBalance = balance - consumed; (5) Returns 0 for address(0) or amount=0 or balance=0
**NatSpec Accuracy:** Accurate. NatSpec correctly states game-only access.
**Gas Flags:** None. `unchecked` block is safe since `consumed <= balance` is guaranteed.
**Verdict:** CORRECT

---

### Public/External -- Payout

---

### `payAffiliate(uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payAffiliate(uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore) external returns (uint256 playerRakeback)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): base reward amount; `code` (bytes32): affiliate code from tx; `sender` (address): purchasing player; `lvl` (uint24): current game level; `isFreshEth` (bool): fresh vs recycled; `lootboxActivityScore` (uint16): buyer's lootbox activity score for taper |
| **Returns** | `playerRakeback` (uint256): rakeback amount to credit to player |

**State Reads:** `playerReferralCode[sender]`, `affiliateCode[code]`, `affiliateCode[storedCode]`, `affiliateCode[AFFILIATE_CODE_VAULT]` (constructed inline), `affiliateCoinEarned[lvl][affiliateAddr]`, `affiliateCommissionFromSender[lvl][affiliateAddr][sender]`, `affiliateTopByLevel[lvl]`, `playerReferralCode[affiliateAddr]` (upline1), `playerReferralCode[upline]` (upline2)
**State Writes:** `playerReferralCode[sender]` (if resolving referral), `affiliateCoinEarned[lvl][affiliateAddr]`, `affiliateCommissionFromSender[lvl][affiliateAddr][sender]`, `affiliateTopByLevel[lvl]` (if new top), `pendingDegeneretteCredit[player]` (if Degenerette mode, via `_routeAffiliateReward`)

**Callers:** COIN or GAME contracts only (`msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.GAME`)
**Callees:** `_setReferralCode`, `_vaultReferralMutable`, `_updateTopAffiliate`, `_applyLootboxTaper`, `_referrerAddress` (x2, for upline1 and upline2), `coin.affiliateQuestReward` (x1-3), `_rollWeightedAffiliateWinner`, `_routeAffiliateReward`

**ETH Flow:** No direct ETH movement. Rewards are BURNIE-denominated FLIP/COIN credits or degenerette credit storage. No `msg.value` or ETH transfers.
**Invariants:**
1. Only COIN or GAME can call
2. Referral resolution: unset slots resolve to VAULT (locked) on first purchase; VAULT/LOCKED referrals mutable during presale only
3. `scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR` where rewardScaleBps is 2500/2000/500
4. Per-referrer commission capped at 0.5 ETH BURNIE per sender per level
5. Leaderboard tracks full untapered amount; payout uses tapered amount
6. Rakeback = `(scaledAmount * rakebackPct) / 100` where rakebackPct <= 25
7. Upline1 gets 20% of scaledAmount (post-taper); Upline2 gets 4% of scaledAmount (post-taper)
8. Multi-recipient payout: weighted random winner gets combined total (preserves per-recipient EV)
9. Quest rewards added on top of each tier's base

**NatSpec Accuracy:** NatSpec header says "ACCESS: coin or game only" which matches implementation. The NatSpec says "Fresh ETH (levels 0-3): 25%" matching the code `lvl <= 3`. The interface NatSpec says "levels 1-3" which is slightly inconsistent with implementation (levels 0-3), but the contract NatSpec is correct.

**Gas Flags:**
1. `vaultInfo` is constructed as a memory struct even when not needed (e.g., valid stored code path). Minor gas cost.
2. The `infoSet` boolean tracking adds ~40 gas; negligible.

**Verdict:** CORRECT -- Complex but well-structured. The referral resolution covers all edge cases (no code, invalid code, self-referral, presale mutability). Per-referrer cap prevents whale domination. Weighted winner selection preserves EV across tiers. One minor NatSpec inconsistency in the interface (levels 1-3 vs 0-3) is informational only.

---

### Public/External -- Leaderboard Views

---

### `affiliateTop(uint24 lvl)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliateTop(uint24 lvl) external view returns (address player, uint96 score)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): game level to query |
| **Returns** | `player` (address): top affiliate; `score` (uint96): their score |

**State Reads:** `affiliateTopByLevel[lvl]`
**State Writes:** None

**Callers:** Any external account; used by JackpotModule for affiliate trophies
**Callees:** None

**ETH Flow:** None
**Invariants:** Returns (address(0), 0) for levels with no affiliate activity
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `affiliateScore(uint24 lvl, address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliateScore(uint24 lvl, address player) external view returns (uint256 score)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): game level; `player` (address): affiliate address |
| **Returns** | `score` (uint256): base affiliate score (18 decimals) |

**State Reads:** `affiliateCoinEarned[lvl][player]`
**State Writes:** None

**Callers:** Any external account
**Callees:** None

**ETH Flow:** None
**Invariants:** Returns 0 for players with no activity at the given level
**NatSpec Accuracy:** Accurate. Correctly notes exclusion of upline rewards and quest bonuses.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `affiliateBonusPointsBest(uint24 currLevel, address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `currLevel` (uint24): current game level; `player` (address): player to evaluate |
| **Returns** | `points` (uint256): bonus points (0 to 50) |

**State Reads:** `affiliateCoinEarned[lvl][player]` for up to 5 previous levels
**State Writes:** None

**Callers:** Any external account; used by MintModule for trait roll bonus
**Callees:** None

**ETH Flow:** None
**Invariants:** (1) Returns 0 for address(0) or currLevel=0; (2) Sums scores for levels (currLevel-5) through (currLevel-1); (3) 1 point per 1 ETH of summed score; (4) Capped at AFFILIATE_BONUS_MAX=50

**NatSpec Accuracy:** Accurate. Says "previous 5 levels" which matches the loop offset 1..5.

**Gas Flags:** The loop condition `if (currLevel <= offset) break` means for currLevel=1, only level 0 is checked (offset=1, lvl=0). For currLevel=2, levels 0 and 1 are checked. This is correct. The `unchecked` block around the entire loop body including the `sum +=` is safe because affiliateCoinEarned values are bounded by the per-referrer cap system and realistic total supply.

**Verdict:** CORRECT

---

### Constructor

---

### `constructor(address[] bootstrapOwners, bytes32[] bootstrapCodes, uint8[] bootstrapRakebacks, address[] bootstrapPlayers, bytes32[] bootstrapReferralCodes)` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor(address[] memory bootstrapOwners, bytes32[] memory bootstrapCodes, uint8[] memory bootstrapRakebacks, address[] memory bootstrapPlayers, bytes32[] memory bootstrapReferralCodes)` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | `bootstrapOwners` (address[]): pre-registered code owners; `bootstrapCodes` (bytes32[]): codes to create; `bootstrapRakebacks` (uint8[]): rakeback percentages; `bootstrapPlayers` (address[]): players to pre-refer; `bootstrapReferralCodes` (bytes32[]): codes to assign to players |
| **Returns** | none |

**State Reads:** None initially; `affiliateCode[code].owner` via `_createAffiliateCode` and `_bootstrapReferral`
**State Writes:** `affiliateCode[AFFILIATE_CODE_VAULT]`, `affiliateCode[AFFILIATE_CODE_DGNRS]`, `playerReferralCode[VAULT]`, `playerReferralCode[DGNRS]`, plus all bootstrapped codes and referrals

**Callers:** Deploy transaction only
**Callees:** `_setReferralCode` (x2 for VAULT<->DGNRS), `_createAffiliateCode` (loop), `_bootstrapReferral` (loop)

**ETH Flow:** None
**Invariants:** (1) Array lengths must match (owners/codes/rakebacks); (2) VAULT and DGNRS codes permanently reserved; (3) VAULT refers DGNRS and vice versa; (4) All bootstrap codes validated through `_createAffiliateCode`

**NatSpec Accuracy:** No explicit NatSpec on constructor; contract-level NatSpec describes the system adequately.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Private -- Referral Internals

---

### `_vaultReferralMutable(bytes32 code)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _vaultReferralMutable(bytes32 code) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `code` (bytes32): stored referral code to check |
| **Returns** | `bool`: true if referral can be overridden |

**State Reads:** `game.lootboxPresaleActiveFlag()` (external call)
**State Writes:** None

**Callers:** `referPlayer`, `payAffiliate`
**Callees:** `game.lootboxPresaleActiveFlag()` (external)

**ETH Flow:** None
**Invariants:** Returns true only if (code is REF_CODE_LOCKED or AFFILIATE_CODE_VAULT) AND presale is active. This allows players who were auto-assigned to VAULT during presale to switch affiliates.
**NatSpec Accuracy:** Dev comment says "Allow VAULT-referred players to update referral only during presale" -- accurate.
**Gas Flags:** External call to game contract for each check; necessary for correctness.
**Verdict:** CORRECT

---

### `_setReferralCode(address player, bytes32 code)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setReferralCode(address player, bytes32 code) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to set referral for; `code` (bytes32): referral code or REF_CODE_LOCKED |
| **Returns** | none |

**State Reads:** `affiliateCode[code].owner` (for non-locked, non-VAULT codes)
**State Writes:** `playerReferralCode[player]`

**Callers:** `referPlayer`, `payAffiliate`, `constructor`, `_bootstrapReferral`
**Callees:** None (only emits event)

**ETH Flow:** None
**Invariants:** (1) Emits ReferralUpdated with normalized referrer (VAULT address for locked/VAULT codes); (2) `locked` flag is true only for REF_CODE_LOCKED
**NatSpec Accuracy:** Dev comment "Set player's referral code and emit a normalized event for indexers" -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_referrerAddress(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _referrerAddress(address player) private view returns (address)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player to look up |
| **Returns** | `address`: referrer address or address(0) |

**State Reads:** `playerReferralCode[player]`, `affiliateCode[code].owner`
**State Writes:** None

**Callers:** `getReferrer`, `payAffiliate` (for upline1, upline2)
**Callees:** None

**ETH Flow:** None
**Invariants:** (1) Returns address(0) for unset (bytes32(0)) referrals; (2) Returns VAULT for REF_CODE_LOCKED or AFFILIATE_CODE_VAULT; (3) Otherwise returns code owner
**NatSpec Accuracy:** NatSpec says "@notice Get the referrer's address for a player" and "@dev Returns address(0) if player has no valid referrer" -- accurate. Note: LOCKED codes return VAULT (not address(0)), which is intentional since locked players still earn for VAULT.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_createAffiliateCode(address owner, bytes32 code_, uint8 rakebackPct)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _createAffiliateCode(address owner, bytes32 code_, uint8 rakebackPct) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `owner` (address): code owner; `code_` (bytes32): code to register; `rakebackPct` (uint8): rakeback percentage |
| **Returns** | none |

**State Reads:** `affiliateCode[code_].owner`
**State Writes:** `affiliateCode[code_]`

**Callers:** `createAffiliateCode`, `constructor`
**Callees:** None (only emits event)

**ETH Flow:** None
**Invariants:** (1) owner != address(0); (2) code != bytes32(0) and code != REF_CODE_LOCKED; (3) rakebackPct <= 25; (4) Code must not already exist (first-come-first-served); (5) payoutMode defaults to Coinflip
**NatSpec Accuracy:** Dev comment "Shared code registration logic for user-created and constructor-bootstrapped codes" -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_bootstrapReferral(address player, bytes32 code_)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _bootstrapReferral(address player, bytes32 code_) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to assign referral; `code_` (bytes32): code to assign |
| **Returns** | none |

**State Reads:** `affiliateCode[code_].owner`, `playerReferralCode[player]`
**State Writes:** `playerReferralCode[player]` (via `_setReferralCode`)

**Callers:** `constructor` only
**Callees:** `_setReferralCode(player, code_)`

**ETH Flow:** None
**Invariants:** (1) player != address(0); (2) code must exist; (3) no self-referral; (4) player must not already have a referral set
**NatSpec Accuracy:** Dev comment "Referral assignment logic for constructor bootstrapping" -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Private -- Reward Routing

---

### `_routeAffiliateReward(address player, uint256 amount, uint8 modeRaw)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _routeAffiliateReward(address player, uint256 amount, uint8 modeRaw) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): reward recipient; `amount` (uint256): reward amount; `modeRaw` (uint8): payout mode |
| **Returns** | none |

**State Reads:** `pendingDegeneretteCredit[player]` (Degenerette mode only)
**State Writes:** `pendingDegeneretteCredit[player]` (Degenerette mode only)

**Callers:** `payAffiliate`
**Callees:** `coin.creditCoin(player, coinAmount)` (SplitCoinflipCoin mode), `coin.creditFlip(player, amount)` (Coinflip mode)

**ETH Flow:** No ETH transferred. Routes BURNIE-denominated rewards through:
- **Coinflip (mode 0):** `coin.creditFlip(player, amount)` -- full amount as FLIP credit
- **Degenerette (mode 1):** stores in `pendingDegeneretteCredit[player]` -- full amount
- **SplitCoinflipCoin (mode 2):** `coin.creditCoin(player, amount >> 1)` -- 50% as COIN; remaining 50% is discarded (not credited anywhere)

**Invariants:** (1) No-op for address(0) or amount=0; (2) SplitCoinflipCoin intentionally discards 50% (deflationary); (3) `amount >> 1` is equivalent to `amount / 2` (rounds down for odd amounts)

**NatSpec Accuracy:** Dev comment says "Route affiliate rewards by code-configured payout mode" and "Amounts are already BURNIE-denominated" -- accurate. The event NatSpec for PayoutMode says mode 2 = "50% coin (rest discarded)" which matches the code.

**Gas Flags:** For SplitCoinflipCoin, the discarded 50% is never minted/burned, just never credited. This is the intended deflationary mechanic.
**Verdict:** CORRECT

---

### `_score96(uint256 s)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _score96(uint256 s) private pure returns (uint96)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `s` (uint256): raw amount |
| **Returns** | `uint96`: capped score |

**State Reads:** None
**State Writes:** None

**Callers:** `_updateTopAffiliate`
**Callees:** None

**ETH Flow:** None
**Invariants:** Caps at `type(uint96).max` (~79.2 billion tokens at 18 decimals). Prevents truncation on unsafe downcast.
**NatSpec Accuracy:** Accurate. Correctly documents uint96 max and purpose.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Private -- Leaderboard

---

### `_updateTopAffiliate(address player, uint256 total, uint24 lvl)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _updateTopAffiliate(address player, uint256 total, uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): affiliate; `total` (uint256): new total earnings; `lvl` (uint24): game level |
| **Returns** | none |

**State Reads:** `affiliateTopByLevel[lvl]`
**State Writes:** `affiliateTopByLevel[lvl]` (only if new score > current top)

**Callers:** `payAffiliate`
**Callees:** `_score96(total)`

**ETH Flow:** None
**Invariants:** (1) Only updates if strictly greater (ties do not replace); (2) Uses uint96-capped score for comparison and storage; (3) Emits AffiliateTopUpdated on change
**NatSpec Accuracy:** Accurate. "Only updates storage if score exceeds current top."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_applyLootboxTaper(uint256 amt, uint16 score)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyLootboxTaper(uint256 amt, uint16 score) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `amt` (uint256): pre-taper reward amount; `score` (uint16): lootbox activity score |
| **Returns** | `uint256`: tapered amount |

**State Reads:** None
**State Writes:** None

**Callers:** `payAffiliate` (only when `lootboxActivityScore >= LOOTBOX_TAPER_START_SCORE`)
**Callees:** None

**ETH Flow:** None
**Invariants:**
1. score >= LOOTBOX_TAPER_END_SCORE (25500): returns `amt * 5000 / 10000` = 50% floor
2. score in [15000, 25500): linear interpolation from 100% down to 50%
3. Formula: `reductionBps = (10000 - 5000) * excess / range` where `excess = score - 15000`, `range = 25500 - 15000 = 10500`
4. Result: `amt * (10000 - reductionBps) / 10000`

**Verification of taper formula:**
- At score=15000: excess=0, reductionBps=0, result=amt (100%)
- At score=20250: excess=5250, reductionBps=5000*5250/10500=2500, result=amt*7500/10000=75%
- At score=25500: hits first branch, result=amt*5000/10000=50%

**NatSpec Accuracy:** Dev comment "Linear taper: 100% at score 15000 -> 50% at score 25500+" -- accurate.
**Gas Flags:** Called only when `score >= 15000` (caller checks). No division by zero possible since range=10500 is constant.
**Verdict:** CORRECT

---

### Private -- Weighted Selection

---

### `_rollWeightedAffiliateWinner(address[3] players, uint256[3] amounts, uint256 count, uint256 totalAmount, address sender, bytes32 storedCode)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollWeightedAffiliateWinner(address[3] memory players, uint256[3] memory amounts, uint256 count, uint256 totalAmount, address sender, bytes32 storedCode) private view returns (address winner)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `players` (address[3]): recipient addresses; `amounts` (uint256[3]): per-recipient amounts; `count` (uint256): active recipients (2 or 3); `totalAmount` (uint256): sum of amounts; `sender` (address): purchasing player; `storedCode` (bytes32): resolved affiliate code |
| **Returns** | `winner` (address): selected recipient |

**State Reads:** None directly; `GameTimeLib.currentDayIndex()` reads `block.timestamp`
**State Writes:** None

**Callers:** `payAffiliate` (only when cursor > 1, i.e., multiple recipients)
**Callees:** `GameTimeLib.currentDayIndex()`

**ETH Flow:** None
**Invariants:**
1. Entropy source: `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)`
2. `roll = entropy % totalAmount`; selects winner by cumulative weight scan
3. P(player_i wins) = amounts[i] / totalAmount -- preserves per-recipient EV
4. Fallback `return players[0]` is theoretically unreachable for totalAmount > 0

**NatSpec Accuracy:** Dev comment "Select one recipient with probability proportional to their amount" -- accurate.

**Gas Flags:** The entropy is deterministic for a given (day, sender, code) tuple. This means the same sender purchasing multiple times on the same day with the same code will always select the same winner. This is by design -- it makes the system deterministic and gas-efficient (no need for VRF). However, it means outcome is predictable once parameters are known. Since this is FLIP/BURNIE credit (not ETH), manipulation incentive is low.

**Verdict:** CORRECT -- Deterministic weighted selection is acceptable for non-ETH reward distribution. The same-day determinism is a conscious design tradeoff documented in the architecture.

---

### Events, Errors, Types, and Constants (non-function entries for completeness)

---

### Events

| Event | Parameters | Emitted By |
|-------|-----------|------------|
| `Affiliate(uint256 amount, bytes32 indexed code, address sender)` | amount: context-dependent (1=created, 0=referred, >1=base input) | `createAffiliateCode`, `referPlayer`, `payAffiliate`, constructor |
| `ReferralUpdated(address indexed player, bytes32 indexed code, address indexed referrer, bool locked)` | Normalized referral event | `_setReferralCode` |
| `AffiliateEarningsRecorded(uint24 indexed level, address indexed affiliate, uint256 amount, uint256 newTotal, address indexed sender, bytes32 code, bool isFreshEth)` | Leaderboard tracking event | `payAffiliate` |
| `AffiliateTopUpdated(uint24 indexed level, address indexed player, uint96 score)` | New top affiliate | `_updateTopAffiliate` |
| `AffiliatePayoutModeUpdated(address indexed owner, bytes32 indexed code, uint8 mode)` | Mode change | `setAffiliatePayoutMode` |
| `DegeneretteCreditUpdated(address indexed player, bool credited, uint256 amount, uint256 newBalance)` | Credit add/consume | `_routeAffiliateReward`, `consumeDegeneretteCredit` |

### Errors

| Error | Thrown By | Condition |
|-------|----------|-----------|
| `OnlyAuthorized()` | `payAffiliate`, `consumeDegeneretteCredit` | Caller is not COIN/GAME |
| `Zero()` | `_createAffiliateCode` | Owner is address(0) or code is reserved |
| `Insufficient()` | `_createAffiliateCode`, `referPlayer`, `_bootstrapReferral`, `setAffiliatePayoutMode` | Code taken, invalid referral, not owner |
| `InvalidRakeback()` | `_createAffiliateCode` | rakebackPct > 25 |

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `AFFILIATE_BONUS_MAX` | 50 | Max bonus points from affiliate activity |
| `MAX_RAKEBACK_PCT` | 25 | Max rakeback percentage |
| `REWARD_SCALE_FRESH_L1_3_BPS` | 2500 | 25% reward rate for fresh ETH, levels 0-3 |
| `REWARD_SCALE_FRESH_L4P_BPS` | 2000 | 20% reward rate for fresh ETH, levels 4+ |
| `REWARD_SCALE_RECYCLED_BPS` | 500 | 5% reward rate for recycled ETH |
| `BPS_DENOMINATOR` | 10000 | Basis point denominator |
| `LOOTBOX_TAPER_START_SCORE` | 15000 | Taper begins at this activity score |
| `LOOTBOX_TAPER_END_SCORE` | 25500 | Taper floor reached at this score |
| `LOOTBOX_TAPER_MIN_BPS` | 5000 | 50% floor for taper |
| `MAX_COMMISSION_PER_REFERRER_PER_LEVEL` | 0.5 ether | Per-sender commission cap per level |
| `REF_CODE_LOCKED` | bytes32(uint256(1)) | Sentinel: referral permanently locked |
| `AFFILIATE_CODE_VAULT` | bytes32("VAULT") | Reserved VAULT affiliate code |
| `AFFILIATE_CODE_DGNRS` | bytes32("DGNRS") | Reserved DGNRS affiliate code |
| `AFFILIATE_ROLL_TAG` | keccak256("affiliate-payout-roll-v1") | Domain separator for weighted roll entropy |
