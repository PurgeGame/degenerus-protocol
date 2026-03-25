# Unit 10: BURNIE Token + Coinflip -- Mad Genius Attack Report

**Attacker:** Claude Opus 4.6 (1M context)
**Phase:** 112-burnie-token-coinflip
**Contracts:** BurnieCoin.sol, BurnieCoinflip.sol
**Date:** 2026-03-25

---

## TIER 1 FUNCTIONS (Highest Risk)

---

## B2: BurnieCoin::transfer (L408-412)

### Call Tree
```
transfer(to, amount) [L408] -- external
  +-> _claimCoinflipShortfall(msg.sender, amount) [L409, -> L590]
  |     +-> if amount == 0: return [L591]
  |     +-> if degenerusGame.rngLocked(): return [L592] -- EXTERNAL CALL to Game
  |     +-> balance = balanceOf[msg.sender] [L593] -- STORAGE READ
  |     +-> if balance >= amount: return [L594]
  |     +-> IBurnieCoinflip(coinflipContract).claimCoinflipsFromBurnie(msg.sender, amount - balance) [L596]
  |           -> EXTERNAL CALL to BurnieCoinflip
  |           -> BurnieCoinflip._claimCoinflipsAmount(player, amount, true) [L339]
  |             +-> _claimCoinflipsInternal(player, false) [L379] -- full day processing loop
  |             +-> state.claimableStored = uint128(stored - toClaim) [L388]
  |             +-> burnie.mintForCoinflip(player, toClaim) [L393] -- CALLBACK to BurnieCoin
  |                   -> BurnieCoin.mintForCoinflip(player, toClaim) [L537]
  |                     +-> if msg.sender != coinflipContract: revert [L529]
  |                     +-> _mint(player, toClaim) [L539]
  |                       +-> _supply.totalSupply += amount128 [L489]
  |                       +-> balanceOf[player] += amount [L490]
  +-> _transfer(msg.sender, to, amount) [L410, -> L453]
        +-> if from == address(0) || to == address(0): revert ZeroAddress [L454]
        +-> balanceOf[from] -= amount [L456] -- UNDERFLOW CHECK by Solidity 0.8+
        +-> if to == VAULT: vault redirect path [L458-467]
        +-> balanceOf[to] += amount [L471]
```

### Storage Writes (Full Tree)
- `balanceOf[msg.sender]` -- increased by _mint (via callback), decreased by _transfer
- `balanceOf[to]` -- increased by _transfer
- `_supply.totalSupply` -- increased by _mint (via callback)
- **BurnieCoinflip side:** `coinflipBalance[day][player]` cleared, `playerState[player].lastClaim` updated, `playerState[player].autoRebuyCarry` updated, `playerState[player].claimableStored` updated

### Cached-Local-vs-Storage Check
**Critical pair:** `_claimCoinflipShortfall` reads `balanceOf[msg.sender]` at L593 to determine shortfall. The callback chain then calls `_mint` which writes to `balanceOf[msg.sender]`. However, the local variable `balance` is only used to compute the shortfall amount passed to `claimCoinflipsFromBurnie`. After the callback returns, `_transfer` reads `balanceOf[from]` fresh from storage at L456. **No stale cache -- the storage read in _transfer happens AFTER the mint completes.**

**Verdict: SAFE.** The `balance` local in `_claimCoinflipShortfall` is read-once, used to compute a delta, then discarded. The subsequent `_transfer` reads storage directly.

### Attack Analysis

**1. State coherence (BAF pattern):** SAFE -- analyzed above. No stale cache.

**2. Access control:** SAFE -- transfer is public, callable by anyone for their own tokens. No elevated privilege.

**3. RNG manipulation:** SAFE -- rngLocked check in _claimCoinflipShortfall prevents auto-claim during VRF resolution. If rngLocked, shortfall is skipped, transfer proceeds with existing balance (reverts if insufficient).

**4. Cross-contract state desync:** SAFE -- the callback to mintForCoinflip and back to _mint is atomic within the transaction. No other contract can interleave.

**5. Edge cases:**
- amount = 0: _claimCoinflipShortfall returns early (L591), _transfer succeeds with 0 transfer. **SAFE.**
- from == to: valid, balance -= then += for same address. Net zero. **SAFE.**
- to == VAULT: _transfer redirects to vault escrow path. balanceOf[from] decremented, _supply.totalSupply decremented, _supply.vaultAllowance incremented. **SAFE** -- supply invariant maintained.

**6. Silent failures:** SAFE -- Solidity 0.8+ underflow reverts if balance insufficient.

**VERDICT: SAFE**

---

## B3: BurnieCoin::transferFrom (L422-441)

### Call Tree
```
transferFrom(from, to, amount) [L422] -- external
  +-> if msg.sender != GAME: [L428]
  |     +-> allowed = allowance[from][msg.sender] [L429]
  |     +-> if allowed != max && amount != 0: [L431]
  |           +-> newAllowance = allowed - amount [L433] -- reverts on underflow
  |           +-> allowance[from][msg.sender] = newAllowance [L434]
  +-> _claimCoinflipShortfall(from, amount) [L438] -- same chain as B2
  +-> _transfer(from, to, amount) [L439]
```

### Storage Writes (Full Tree)
Same as B2, plus: `allowance[from][msg.sender]` updated.

### Cached-Local-vs-Storage Check
Same as B2 -- no stale cache. The `allowed` local is used only for allowance math, not balance.

### Attack Analysis

**1. Game contract bypass:** The game contract (msg.sender == ContractAddresses.GAME) skips the allowance check entirely. This gives the game unlimited transfer authority. **By design** -- the game executes via delegatecall modules that need to move BURNIE. The address is a compile-time constant, not configurable. **SAFE (intentional trust model).**

**2. Allowance race condition:** Standard ERC20 approve/transferFrom race. The approve function allows setting to any value (not just increase/decrease). This is a known ERC20 design limitation, not a protocol-specific vulnerability. **INFO-level only.**

**3. Cross-contract callback:** Same analysis as B2 -- _claimCoinflipShortfall callback is safe.

**VERDICT: SAFE**

---

## B12: BurnieCoin::vaultMintTo (L705-717)

### Call Tree
```
vaultMintTo(to, amount) [L705] -- external, onlyVault
  +-> if to == address(0): revert ZeroAddress [L706]
  +-> amount128 = _toUint128(amount) [L707] -- reverts if > uint128.max
  +-> allowanceVault = _supply.vaultAllowance [L708] -- STORAGE READ
  +-> if amount128 > allowanceVault: revert Insufficient [L709]
  +-> unchecked:
  |     _supply.vaultAllowance = allowanceVault - amount128 [L711]
  |     _supply.totalSupply += amount128 [L712]
  |     balanceOf[to] += amount [L713]
  +-> emit VaultAllowanceSpent, Transfer
```

### Storage Writes (Full Tree)
- `_supply.vaultAllowance` -- decreased
- `_supply.totalSupply` -- increased
- `balanceOf[to]` -- increased

### Cached-Local-vs-Storage Check
`allowanceVault` is cached locally at L708, then used for the subtraction at L711. No descendant call writes to `_supply.vaultAllowance` between the read and write. **SAFE.**

### Attack Analysis

**1. Supply invariant:** vaultAllowance decreases by X, totalSupply increases by X. Net sum unchanged. **SAFE.**

**2. Access control:** onlyVault modifier checks `msg.sender != ContractAddresses.VAULT`. Compile-time constant. **SAFE.**

**3. Unchecked arithmetic:** The unchecked block at L710-714 contains:
- `vaultAllowance = allowanceVault - amount128`: Safe because `amount128 <= allowanceVault` checked at L709.
- `totalSupply += amount128`: Could theoretically overflow uint128. However, totalSupply + vaultAllowance = supplyIncUncirculated, and the subtraction from vaultAllowance ensures the sum stays constant. **No overflow possible** given invariant holds.
- `balanceOf[to] += amount`: Uses uint256, overflow requires ~2^256 tokens. **Impractical.**

**4. to == VAULT path:** Not blocked. If vault mints to itself, balanceOf[VAULT] increases. But _mint redirects VAULT mints to allowance increase -- however, vaultMintTo does NOT call _mint, it has inline logic. This means VAULT can mint tokens to itself as circulating supply while also having vault allowance. **INVESTIGATE: Is this reachable?** The vault contract would need to call vaultMintTo(VAULT, amount). If it does, the vault gets real tokens AND vault allowance was reduced. The total supply invariant still holds: vaultAllowance decreased, totalSupply increased, balanceOf[VAULT] increased. On the next transfer from VAULT, _transfer would redirect to vault escrow (L458-467), which decreases totalSupply and increases vaultAllowance. Net effect is the vault effectively burned and re-escrowed. **No economic impact, but semantically odd.**

**VERDICT: SAFE** (with INFO note on vault-to-self path)

---

## B18: BurnieCoin::burnCoin (L869-875)

### Call Tree
```
burnCoin(target, amount) [L869] -- external, onlyTrustedContracts
  +-> consumed = _consumeCoinflipShortfall(target, amount) [L873, -> L603]
  |     +-> if amount == 0: return 0 [L604]
  |     +-> if degenerusGame.rngLocked(): return 0 [L605]
  |     +-> balance = balanceOf[target] [L606]
  |     +-> if balance >= amount: return 0 [L607]
  |     +-> IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(target, amount - balance) [L609]
  |           -> BurnieCoinflip._claimCoinflipsAmount(player, amount, false) [L369]
  |             -> mintTokens = false: NO callback to BurnieCoin
  |             -> returns consumed amount (claimableStored reduced internally)
  +-> _burn(target, amount - consumed) [L874]
        +-> balanceOf[target] -= (amount - consumed) [L512] -- reverts on underflow
        +-> _supply.totalSupply -= (amount - consumed) [L513]
```

### Storage Writes (Full Tree)
- `balanceOf[target]` -- decreased by _burn
- `_supply.totalSupply` -- decreased by _burn
- **BurnieCoinflip side:** `playerState[target].claimableStored` decreased by consumed amount

### Cached-Local-vs-Storage Check
`consumed` is returned from the coinflip call. `_burn(target, amount - consumed)` then reads `balanceOf[target]` directly from storage. No stale cache.

**Key insight:** consumeCoinflipsForBurn passes `mintTokens=false`, so BurnieCoin.mintForCoinflip is NEVER called back. No callback chain. The coinflip contract reduces claimableStored internally but does not mint tokens.

**The arithmetic: amount - consumed <= balance[target].** Why? consumed = min(claimableStored, shortfall) where shortfall = amount - balance. So amount - consumed = amount - min(claimable, amount - balance). If consumed = amount - balance, then amount - consumed = balance. If consumed < amount - balance, then amount - consumed > balance and _burn reverts on underflow. **Correct behavior -- reverts if insufficient total (balance + claimable).**

### Attack Analysis

**1. CEI pattern:** The consume shortfall call happens BEFORE _burn. This means the coinflip state is settled first, then the burn occurs. No reentrancy risk because consumeCoinflipsForBurn does not call back. **SAFE.**

**2. consumed > amount:** Impossible. consumeCoinflipsForBurn requests `amount - balance` and returns `min(claimable, requested)`. consumed <= amount - balance, so amount - consumed >= balance. **SAFE.**

**VERDICT: SAFE**

---

## B19: BurnieCoin::decimatorBurn (L890-966)

### Call Tree
```
decimatorBurn(player, amount) [L890] -- external
  +-> resolve caller (self or approved operator) [L891-899]
  +-> if amount < DECIMATOR_MIN: revert [L901]
  +-> (open, lvl) = degenerusGame.decWindow() [L903] -- EXTERNAL: check window
  +-> if !open: revert [L904]
  +-> consumed = _consumeCoinflipShortfall(caller, amount) [L906]
  +-> _burn(caller, amount - consumed) [L908] -- CEI: burn before downstream
  +-> questModule.handleDecimator(caller, amount) [L916] -- EXTERNAL: quest
  +-> _questApplyReward(...) [L918] -- event only
  +-> if questReward != 0: coinflipContract.creditFlip(caller, questReward) [L927] -- EXTERNAL
  +-> degenerusGame.playerActivityScore(caller) [L933] -- EXTERNAL
  +-> _decimatorBurnMultiplier(bonusBps) [L938] -- pure
  +-> _adjustDecimatorBucket(bonusBps, minBucket) [L942] -- pure
  +-> degenerusGame.consumeDecimatorBoon(caller) [L948] -- EXTERNAL
  +-> degenerusGame.recordDecBurn(caller, lvl, bucket, baseAmount, decBurnMultBps) [L957] -- EXTERNAL
  +-> emit DecimatorBurn
```

### Storage Writes (Full Tree)
- `balanceOf[caller]` -- decreased by _burn
- `_supply.totalSupply` -- decreased by _burn
- **BurnieCoinflip side:** claimableStored adjusted via consume (if shortfall)
- **External side:** game.recordDecBurn writes to Game storage (out of scope for this unit)

### Cached-Local-vs-Storage Check
No BurnieCoin storage is cached before _burn. After _burn completes, no further BurnieCoin storage writes occur. The `amount`, `consumed`, `baseAmount`, `bucket` are all local variables computed from external calls. **SAFE.**

### Attack Analysis

**1. CEI order:** _burn happens at L908, BEFORE quest processing (L916), credit flip (L927), and record (L957). If any downstream call reverts, the burn is also reverted (atomic tx). **SAFE.**

**2. Operator approval check:** Uses `degenerusGame.isOperatorApproved(player, msg.sender)` at L895. Delegates to Game's operator system. **SAFE (assuming Game operator system is correct -- verified in Unit 1).**

**3. Quest reward amount:** questReward is credited as flip stake, not minted as tokens. The reward comes from the quest module's reward calculation. No token inflation. **SAFE.**

**4. baseAmount inflation:** baseAmount = amount + questReward + boon boost. The boon boost is capped at 50k BURNIE worth (DECIMATOR_BOON_CAP). The questReward is protocol-controlled. No player-controlled inflation beyond the boon cap. **SAFE.**

**5. Bucket manipulation:** _adjustDecimatorBucket uses bonusBps from playerActivityScore (Game storage). A player cannot directly manipulate their activity score within the same transaction. **SAFE.**

**VERDICT: SAFE**

---

## B22: BurnieCoinflip::depositCoinflip (L225-239)

### Call Tree
```
depositCoinflip(player, amount) [L225] -- external
  +-> resolve caller + directDeposit flag [L226-237]
  +-> _depositCoinflip(caller, amount, directDeposit) [L238, -> L242]
        +-> state = playerState[caller] [L247]
        +-> if amount != 0:
        |     if amount < MIN: revert [L249]
        |     if _coinflipLockedDuringTransition(): revert [L252]
        +-> mintable = _claimCoinflipsInternal(caller, false) [L255] -- full claim loop
        +-> if mintable != 0: state.claimableStored += mintable [L257]
        +-> if amount == 0: emit, return [L260-263]
        +-> burnie.burnForCoinflip(caller, amount) [L266] -- EXTERNAL: burn tokens
        |     -> BurnieCoin._burn(caller, amount) -- burns from player balance
        +-> questModule.handleFlip(caller, amount) [L275] -- EXTERNAL: quest
        +-> questReward = _questApplyReward(...) [L276]
        +-> creditedFlip = amount + questReward [L286]
        +-> rollAmount = autoRebuy ? carry : mintable [L287-289]
        +-> rebetAmount = min(creditedFlip, rollAmount) [L290-292]
        +-> if rebetAmount != 0: calculate recycling bonus [L293-306]
        +-> _addDailyFlip(caller, creditedFlip, ...) [L308-314]
              +-> consumeCoinflipBoon [L619] -- EXTERNAL to Game
              +-> coinflipBalance[targetDay][caller] += coinflipDeposit [L637]
              +-> _updateTopDayBettor [L638]
              +-> bounty logic: biggestFlipEver, bountyOwedTo [L643-666]
        +-> emit CoinflipDeposit
```

### Storage Writes (Full Tree)
- **BurnieCoin:** balanceOf[caller] decreased (via burnForCoinflip)
- **BurnieCoinflip:** playerState[caller].claimableStored, lastClaim, autoRebuyCarry (via _claimCoinflipsInternal)
- **BurnieCoinflip:** coinflipBalance[targetDay][caller] (via _addDailyFlip)
- **BurnieCoinflip:** coinflipTopByDay[targetDay] (via _updateTopDayBettor)
- **BurnieCoinflip:** biggestFlipEver, bountyOwedTo (via bounty logic in _addDailyFlip)

### Cached-Local-vs-Storage Check
`state` is a storage pointer (L247): `PlayerCoinflipState storage state = playerState[caller]`. All writes through `state.` go directly to storage. `mintable` is a local computed from _claimCoinflipsInternal. `creditedFlip`, `rollAmount`, `rebetAmount` are all locals derived from other locals and external calls. **No stale cache risk.**

### Attack Analysis

**1. Coinflip lock during BAF:** _coinflipLockedDuringTransition() at L252 checks `!inJackpotPhase && !gameOver && lastPurchaseDay && rngLocked && (purchaseLevel % 10 == 0)`. This blocks deposits during BAF resolution levels. **SAFE.**

**2. Bounty arming + RNG:** In _addDailyFlip, bounty arming requires `canArmBounty && bountyEligible && recordAmount != 0` (L643). For directDeposit=true, canArmBounty=true, bountyEligible=true. The `!game.rngLocked()` check at L645 prevents arming when RNG outcome is known. **SAFE.**

**3. Auto-rebuy carry as rollAmount:** When autoRebuy is enabled, rollAmount = carry (L288). The carry from previous wins determines the recycling bonus. No manipulation vector -- carry is protocol-computed. **SAFE.**

**4. Quest reward manipulation:** questReward comes from questModule.handleFlip, which is a trusted contract. No player-controlled inflation. **SAFE.**

**5. Zero-amount deposit path:** amount=0 triggers claim settlement only (L260-263). No burn, no stake change. Used for "settle without depositing." **SAFE.**

**VERDICT: SAFE**

---

## B23: BurnieCoinflip::claimCoinflips (L326-329)

### Call Tree
```
claimCoinflips(player, amount) [L326] -- external
  +-> _resolvePlayer(player) [L329] -- operator check
  +-> _claimCoinflipsAmount(resolved, amount, true) [L329, -> L373]
        +-> state = playerState[player] [L378]
        +-> mintable = _claimCoinflipsInternal(player, false) [L379]
        +-> stored = state.claimableStored + mintable [L380]
        +-> if stored == 0: return 0 [L381]
        +-> toClaim = min(amount, stored) [L383-386]
        +-> state.claimableStored = uint128(stored - toClaim) [L388]
        +-> burnie.mintForCoinflip(player, toClaim) [L393] -- CALLBACK to BurnieCoin._mint
```

### Storage Writes (Full Tree)
- playerState[player].claimableStored -- updated
- playerState[player].lastClaim -- via _claimCoinflipsInternal
- coinflipBalance[day][player] -- cleared via _claimCoinflipsInternal
- playerState[player].autoRebuyCarry -- via _claimCoinflipsInternal
- **BurnieCoin:** balanceOf[player] increased, _supply.totalSupply increased (via mintForCoinflip)

### Cached-Local-vs-Storage Check
`stored = state.claimableStored + mintable` uses `state.claimableStored` from storage. After `_claimCoinflipsInternal` runs, claimableStored may have been modified (via settleFlipModeChange paths that call the same internal). But `_claimCoinflipsInternal` writes to `lastClaim` and `autoRebuyCarry`, not `claimableStored`. The `claimableStored` is only written at L388 after the calculation. **SAFE.**

The `mintForCoinflip` callback at L393 goes to BurnieCoin._mint, which does not call back into BurnieCoinflip. No circular callback. **SAFE.**

### Attack Analysis

**1. uint128 truncation at L388:** `state.claimableStored = uint128(stored - toClaim)`. Since toClaim <= stored, the result is >= 0. Since stored = claimableStored(uint128) + mintable, if mintable is very large, stored could exceed uint128 max. **INVESTIGATE:** Can mintable exceed uint128 max (3.4e38)? mintable accumulates payout = stake + stake * rewardPercent / 100 for each winning day. Max rewardPercent = 156 (150 + 6 presale). Max payout per day = stake * 2.56. Over 1095 days (AUTO_REBUY_OFF_CLAIM_DAYS_MAX), if every day is a win with max payout, and max carry compounds: this is exponential. However, totalSupply is uint128, so no player can have more than uint128 tokens at stake. The compounding is bounded by MAX = 2.56^1095 * initial_stake, but the actual token supply caps this. **In practice, uint128 max = 3.4e38. Max circulating supply is far below this.** The initial vault allowance is 2M ether = 2e24. Even with extreme compounding, hitting 3.4e38 is unrealistic given supply bounds. **SAFE (theoretical, but economically unreachable).**

**VERDICT: SAFE**

---

## B24: BurnieCoinflip::claimCoinflipsFromBurnie (L335-339)

### Call Tree
Same as B23's inner path (_claimCoinflipsAmount), but with `onlyBurnieCoin` access control.

### Attack Analysis
**1. Access control:** onlyBurnieCoin modifier at L338 checks `msg.sender != address(burnie)`. `burnie` is immutable, set in constructor. **SAFE.**

**2. Callback chain:** This is called FROM BurnieCoin._claimCoinflipShortfall. The returned claimed amount is then used by BurnieCoin to complete the transfer. Same analysis as B2. **SAFE.**

**VERDICT: SAFE**

---

## B27: BurnieCoinflip::setCoinflipAutoRebuy (L674-686)

### Call Tree
```
setCoinflipAutoRebuy(player, enabled, takeProfit) [L674] -- external
  +-> fromGame = (msg.sender == GAME) [L679]
  +-> resolve player [L680-685]
  +-> _setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame) [L686, -> L698]
        +-> if degenerusGame.rngLocked(): revert RngLocked [L706]
        +-> if enabled:
        |     mintable = _claimCoinflipsInternal(player, false) [L709]
        |     configure autoRebuy state [L710-731]
        |     if takeProfit < AFKING_KEEP_MIN_COIN: deactivateAfKingFromCoin [L730]
        +-> if !enabled (disabling):
        |     mintable = _claimCoinflipsInternal(player, true) [L733] -- deep=true
        |     carry = state.autoRebuyCarry [L734]
        |     if carry != 0: mintable += carry; state.autoRebuyCarry = 0 [L735-737]
        |     state.autoRebuyEnabled = false [L739]
        |     state.autoRebuyStartDay = 0 [L740]
        |     degenerusGame.deactivateAfKingFromCoin(player) [L742]
        +-> if mintable != 0: burnie.mintForCoinflip(player, mintable) [L746]
```

### Storage Writes (Full Tree)
- playerState[player].autoRebuyEnabled, autoRebuyStop, autoRebuyStartDay, autoRebuyCarry
- playerState[player].lastClaim (via _claimCoinflipsInternal)
- coinflipBalance cleared (via _claimCoinflipsInternal)
- **BurnieCoin:** balanceOf[player], _supply.totalSupply (via mintForCoinflip)

### Cached-Local-vs-Storage Check
`state` is a storage pointer. `mintable` is local. `carry` is read from `state.autoRebuyCarry` at L734 after `_claimCoinflipsInternal` has already run. `_claimCoinflipsInternal` may update `autoRebuyCarry` (L593). So `carry` at L734 reflects the post-claim value. **SAFE.**

### Attack Analysis

**1. RNG lock protection:** `degenerusGame.rngLocked()` at L706 prevents toggling during VRF resolution. This prevents extracting carry before a known loss. **SAFE.**

**2. Carry extraction on disable:** When disabling, `_claimCoinflipsInternal(player, true)` uses deep=true, which processes up to AUTO_REBUY_OFF_CLAIM_DAYS_MAX (1095) days. This ensures all carry is settled. Then carry is added to mintable and zeroed. The player receives all accumulated value. **SAFE -- by design, disabling auto-rebuy mints all accumulated value.**

**3. Re-enable manipulation:** If autoRebuy is already enabled and `strict=true`, the code reverts with AutoRebuyAlreadyEnabled (L711). If `strict=false` (from game), it just updates takeProfit (L712-713). **SAFE.**

**4. afKing deactivation on disable:** Always calls `deactivateAfKingFromCoin(player)` at L742 when disabling. Also calls at L730 when enabling with low takeProfit. Covers all paths. **SAFE.**

**VERDICT: SAFE**

---

## B29: BurnieCoinflip::processCoinflipPayouts (L778-862)

### Call Tree
```
processCoinflipPayouts(bonusFlip, rngWord, epoch) [L778] -- external, onlyDegenerusGameContract
  +-> seedWord = keccak256(rngWord, epoch) [L784]
  +-> roll = seedWord % 20 [L789]
  +-> if roll == 0: rewardPercent = 50 [L791]
  +-> if roll == 1: rewardPercent = 150 [L793]
  +-> else: rewardPercent = (seedWord % 38) + 78 [L797-798]
  +-> if presaleBonus: rewardPercent += 6 [L805]
  +-> win = (rngWord & 1) == 1 [L810]
  +-> coinflipDayResult[epoch] = CoinflipDayResult{rewardPercent, win} [L813-816]
  +-> bounty resolution [L819-838]:
  |     if bountyOwner != address(0) && currentBounty > 0:
  |       slice = currentBounty >> 1
  |       currentBounty -= slice
  |       if win: _addDailyFlip(bountyOwner, slice, 0, false, false) -- no bounty arming
  |       bountyOwedTo = address(0)
  +-> flipsClaimableDay = epoch [L842]
  +-> currentBounty += PRICE_COIN_UNIT (1000 ether) [L847]
  +-> emit CoinflipDayResolved
  +-> _claimCoinflipsInternal(SDGNRS, false) [L861] -- keep sDGNRS cursor current
```

### Storage Writes (Full Tree)
- coinflipDayResult[epoch] -- new day result
- bountyOwedTo -- cleared to address(0)
- currentBounty -- decremented by slice, then incremented by 1000 ether
- flipsClaimableDay -- advanced to epoch
- coinflipBalance[targetDay][bountyOwner] -- via _addDailyFlip (if win + bounty)
- coinflipTopByDay[targetDay] -- via _addDailyFlip
- playerState[SDGNRS].lastClaim, autoRebuyCarry -- via _claimCoinflipsInternal

### Cached-Local-vs-Storage Check
`currentBounty_` cached at L819, used for slice calculation and update. Between cache and write, `_addDailyFlip` is called (L832). `_addDailyFlip` does NOT write to `currentBounty`. **SAFE.**

### Attack Analysis

**1. RNG bias -- rewardPercent:** `seedWord % 20` for extreme outcomes: 1/20 (5%) for 50%, 1/20 (5%) for 150%, 18/20 (90%) for normal range. Normal: `seedWord % 38 + 78` gives [78, 115]. The seedWord is keccak256(vrfWord, epoch). Since vrfWord is VRF-provided (256 bits) and epoch is deterministic, keccak output is uniformly distributed. `% 38` has negligible bias (2^256 mod 38 is uniformly distributed for practical purposes). **SAFE.**

**2. RNG bias -- win/loss:** `(rngWord & 1) == 1` -- checks the LSB of the raw VRF word. VRF produces uniformly random 256-bit values. LSB is unbiased. **SAFE.** Note: rngWord is used directly (not seedWord), so the win determination is independent of the reward calculation.

**3. Bounty payout timing:** Bounty is credited as flip stake via `_addDailyFlip(to, slice, 0, false, false)`. The last two false parameters mean canArmBounty=false and bountyEligible=false. So the bounty payout cannot re-arm the bounty. **SAFE.**

**4. currentBounty overflow:** At L847: `currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT)`. PRICE_COIN_UNIT = 1000 ether = 1e21. uint128 max = 3.4e38. The bounty accumulates 1000 BURNIE per day. To overflow: 3.4e38 / 1e21 = 3.4e17 days = 9.3e14 years. **SAFE -- physically impossible.**

**5. sDGNRS cursor update:** The `_claimCoinflipsInternal(SDGNRS, false)` at L861 keeps sDGNRS's claim cursor current. sDGNRS is excluded from BAF in jackpots (comment at L553-555). This call happens within `processCoinflipPayouts` which is called during `advanceGame` when rngLocked might be true. The BAF section in `_claimCoinflipsInternal` checks `player != ContractAddresses.SDGNRS` at L556, so the rngLocked revert at L576 is never reached. **SAFE.**

**6. Presale bonus stacking:** `if presaleBonus: rewardPercent += 6`. bonusFlip is passed by the game contract. If `bonusFlip && lootboxPresaleActiveFlag()`, the bonus applies. The game controls the bonusFlip parameter. **SAFE.**

**VERDICT: SAFE**

---

## TIER 2 FUNCTIONS

---

## B4: BurnieCoin::burnForCoinflip (L528-531)

### Call Tree
```
burnForCoinflip(from, amount) [L528] -- external
  +-> if msg.sender != coinflipContract: revert OnlyGame [L529]
  +-> _burn(from, amount) [L530]
```

### Attack Analysis
**1. Access control:** Checks `msg.sender != coinflipContract` where `coinflipContract = ContractAddresses.COINFLIP` (compile-time constant). **SAFE.**
**2. Error reuse:** Reverts with OnlyGame() instead of a coinflip-specific error. Cosmetic issue only. **INFO.**

**VERDICT: SAFE**

## B5: BurnieCoin::mintForCoinflip (L537-540)

Same structure as B4 with _mint. Access control: coinflipContract only. **VERDICT: SAFE**

## B6: BurnieCoin::mintForGame (L546-550)

Access control: GAME only. Zero-amount guard returns early. **VERDICT: SAFE**

## B7: BurnieCoin::creditCoin (L556-559)

Access control: onlyFlipCreditors (GAME, AFFILIATE). Zero-address/amount guard. Mints directly. **VERDICT: SAFE**

## B8/B9: BurnieCoin::creditFlip/creditFlipBatch (L566-576)

Forwards to BurnieCoinflip.creditFlip/creditFlipBatch. Access: onlyFlipCreditors. **VERDICT: SAFE**

## B10: BurnieCoin::creditLinkReward (L584-588)

Access: onlyAdmin. Credits flip stake via coinflipContract.creditFlip. Zero guards. **VERDICT: SAFE**

## B11: BurnieCoin::vaultEscrow (L688-699)

### Call Tree
```
vaultEscrow(amount) [L688] -- external
  +-> if sender != GAME && sender != VAULT: revert [L692-693]
  +-> amount128 = _toUint128(amount) [L694]
  +-> unchecked: _supply.vaultAllowance += amount128 [L696]
```

### Attack Analysis
**1. Unchecked overflow:** `_supply.vaultAllowance += amount128` in unchecked. If called repeatedly with large amounts, vaultAllowance could overflow uint128 and wrap. **INVESTIGATE:** Who calls this? Game contract (via modules) and Vault. The game calls vaultEscrow when virtual BURNIE is allocated to the vault (e.g., from prize pool contributions). The amounts are bounded by game economics. Max single-call amount is bounded by _toUint128 (uint128.max). But cumulative additions could wrap. However, the supply invariant would be violated if vaultAllowance wraps. In practice, total virtual BURNIE (2M initial + game-accrued) is far below uint128 max. **SAFE in practice, but the unchecked is technically a risk if called with adversarial amounts. Access control limits callers to GAME and VAULT, both trusted.**

**VERDICT: SAFE**

## B13-B17: Quest Hub Functions

All follow the same pattern: access control (GAME or AFFILIATE), call questModule.handle*(), apply reward, credit flip if completed. No BurnieCoin storage writes beyond quest routing. **VERDICT: SAFE for all.**

## B20: BurnieCoin::terminalDecimatorBurn (L981-1007)

Same structure as B19 but simpler: no quest processing, no bucket calculation, no boon. Just burn + record. **VERDICT: SAFE**

## B21: BurnieCoinflip::settleFlipModeChange (L215-222)

Access: onlyDegenerusGameContract. Processes pending claims via `_claimCoinflipsInternal(player, false)`, stores mintable to claimableStored. No external callback. **VERDICT: SAFE**

## B25: BurnieCoinflip::claimCoinflipsForRedemption (L345-351)

Access: sDGNRS only (ContractAddresses.SDGNRS). Same as claimCoinflips internally. The comment says "skips RNG lock" -- but examining the code, `_claimCoinflipsAmount` calls `_claimCoinflipsInternal` which does NOT check rngLocked at the top level. The rngLocked check is only in the BAF credit section (L570-577). For sDGNRS, the BAF section is skipped (L556 `player != ContractAddresses.SDGNRS`). So sDGNRS can always claim. **SAFE -- by design.**

## B26: BurnieCoinflip::consumeCoinflipsForBurn (L365-370)

Access: onlyBurnieCoin. Same as _claimCoinflipsAmount but with `mintTokens=false`. No callback. **VERDICT: SAFE**

## B28: BurnieCoinflip::setCoinflipAutoRebuyTakeProfit (L689-693)

Calls `_setCoinflipAutoRebuyTakeProfit` which checks rngLocked, verifies autoRebuy enabled, claims pending, updates stop amount. If takeProfit < AFKING_KEEP_MIN_COIN, deactivates afKing. **VERDICT: SAFE**

## B30/B31: BurnieCoinflip::creditFlip/creditFlipBatch (L869-892)

Access: onlyFlipCreditors (GAME, BurnieCoin). Simple stake credit via _addDailyFlip with canArmBounty=false, bountyEligible=false. **VERDICT: SAFE**

---

## TIER 3 FUNCTIONS

## B1: BurnieCoin::approve (L394-401)

Standard ERC20 approve. Writes allowance mapping. **VERDICT: SAFE**

---

## CATEGORY C: Internal Functions

### C1: BurnieCoin::_transfer (L453-473) [MULTI-PARENT]

Called by B2 (transfer) and B3 (transferFrom).

**Vault redirect path (L458-467):** When `to == VAULT`:
- `balanceOf[from] -= amount` (L456)
- `_supply.totalSupply -= amount128` (L462)
- `_supply.vaultAllowance += amount128` (L463)
- Emits Transfer(from, address(0), amount) -- treated as burn
- Emits VaultEscrowRecorded(from, amount)

**Supply invariant check:** totalSupply decreases by X, vaultAllowance increases by X. Sum unchanged. **SAFE.**

**Unchecked block (L461-464):** Both operations are in unchecked. `totalSupply -= amount128` is safe because `balanceOf[from] >= amount` (checked by underflow at L456), and totalSupply >= sum(balanceOf). `vaultAllowance += amount128` could theoretically overflow uint128, but only if vaultAllowance is near max, which requires ~3.4e38 tokens escrowed. **SAFE in practice.**

### C2: BurnieCoin::_mint (L479-492) [MULTI-PARENT]

**Vault mint path (L482-488):** When `to == VAULT`:
- Only `_supply.vaultAllowance += amount128` (unchecked)
- No balanceOf change, no totalSupply change
- Emits VaultEscrowRecorded

**Normal path:** `_supply.totalSupply += amount128` (checked), `balanceOf[to] += amount`.

**Supply invariant:** Normal: totalSupply increases, vaultAllowance unchanged. Vault: vaultAllowance increases, totalSupply unchanged. Both maintain the invariant. **SAFE.**

### C3: BurnieCoin::_burn (L499-515) [MULTI-PARENT]

**Vault burn path (L502-509):** When `from == VAULT`:
- `allowanceVault = _supply.vaultAllowance`
- `if amount128 > allowanceVault: revert Insufficient`
- `_supply.vaultAllowance = allowanceVault - amount128` (unchecked, safe due to check)
- No balanceOf change, no totalSupply change

**Normal path:** `balanceOf[from] -= amount` (checked underflow), `_supply.totalSupply -= amount128` (checked).

**Supply invariant:** Normal: totalSupply decreases. Vault: vaultAllowance decreases. Both maintain invariant. **SAFE.**

### C8: BurnieCoinflip::_claimCoinflipsInternal (L400-601) [MULTI-PARENT] CRITICAL

This is the most complex function in the system. 200 lines of daily claim processing.

**Key logic:**
1. Reads flipsClaimableDay (latest resolved day) and playerState.lastClaim (cursor)
2. Enforces claim window: 90 days for normal, 30 for first, unlimited for auto-rebuy (from startDay)
3. Iterates day-by-day from cursor to latest, processing wins/losses
4. For wins with auto-rebuy: carry += payout (+ recycling bonus), take-profit reserves extracted to mintable
5. For losses with auto-rebuy: carry = 0
6. Records BAF credit for winning days post-bafResolvedDay
7. Updates lastClaim, autoRebuyCarry
8. Mints WWXRP consolation for losses

**BAF credit section (L556-584):** If player has winning BAF credit AND player != SDGNRS:
- Checks purchaseInfo for BAF resolution lock (every 10th level, last purchase day, rng locked)
- If locked: reverts with RngLocked -- prevents front-running BAF leaderboard
- Records BAF flip via jackpots.recordBafFlip

**INVESTIGATE: BAF credit revert during normal claims.** If a player has accumulated winning BAF credit and tries to claim during a BAF resolution level (every 10th), the entire claim reverts. This means:
- A player cannot claim coinflip winnings during BAF resolution
- But: claimCoinflipsForRedemption (sDGNRS path) is excluded from this check (sDGNRS is excluded at L556)
- And: the rngLocked check at L570-577 requires `!inJackpotPhase && !over && lastPurchaseDay_ && rngLocked_ && (purchaseLevel_ % 10 == 0)` -- all must be true
- This is the SAME condition as _coinflipLockedDuringTransition but checked AFTER processing days, not before

**Concern:** A player claiming on a non-BAF-resolution level might process days that accumulated BAF credit from earlier days, then revert because the current state happens to be in BAF resolution. The player's claim is blocked despite the BAF credit being from a prior period.

**Assessment:** This is by design -- the rngLocked guard prevents BAF leaderboard manipulation. If the player has any winning BAF credit from ANY day in their claim window and the current state is in BAF resolution, the claim reverts. The player can wait until BAF resolution completes. The lockout period is brief (one advanceGame cycle). **SAFE -- conservative guard by design.**

**VERDICT: SAFE**

### C11: BurnieCoinflip::_addDailyFlip (L608-667) [MULTI-PARENT]

**Boon consumption (L619):** `game.consumeCoinflipBoon(player)` -- external call to Game. If recordAmount == 0 (quest credits, bounty payouts), this is skipped. Only triggered on direct deposits with nonzero recordAmount. **SAFE.**

**Bounty threshold (L654-660):** When bountyOwedTo != address(0), a new record must exceed old record by 1% to steal the bounty. `threshold = record + max(record/100, 1)`. **SAFE -- prevents micro-increment theft.**

**VERDICT: SAFE**

---

## SUMMARY OF FINDINGS

| ID | Function | Verdict | Severity | Description |
|----|----------|---------|----------|-------------|
| - | All Tier 1 | SAFE | - | No vulnerabilities found |
| - | All Tier 2 | SAFE | - | No vulnerabilities found |
| - | All Tier 3 | SAFE | - | No vulnerabilities found |
| INFO-01 | B3 transferFrom | INFO | INFO | Standard ERC20 approve race condition (by design, not protocol-specific) |
| INFO-02 | B12 vaultMintTo | INFO | INFO | Vault can mint to itself (no economic impact, semantically odd) |
| INFO-03 | B4 burnForCoinflip | INFO | INFO | Error reuse: OnlyGame() for coinflip access control |

**Overall Assessment:** BurnieCoin and BurnieCoinflip are well-structured with appropriate access controls, CEI patterns, and RNG lock guards. The auto-claim callback chain (the primary concern) is correctly ordered -- the mint completes before the transfer reads the balance. The supply invariant (totalSupply + vaultAllowance = supplyIncUncirculated) is maintained across all 6 vault redirect paths. No BAF-class cache-overwrite bugs found. The uint128 truncation risks are bounded by token supply economics.
