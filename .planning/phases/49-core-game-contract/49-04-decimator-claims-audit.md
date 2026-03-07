# DegenerusGame.sol -- Decimator & Claims Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines audited:** 1115-1805
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

Decimator jackpot crediting/running/claiming and ETH claims (winnings, stETH, affiliate DGNRS, whale pass). These are the primary ETH exit paths. The decimator functions delegate to DecimatorModule; claim functions handle ETH/stETH payout with fallback patterns.

Key patterns:
- All delegatecall wrappers follow the same `(ok, data) = MODULE.delegatecall(...)` + `_revertDelegate` pattern
- CEI enforced on all ETH claim paths (state update before external call)
- 1-wei sentinel optimization on claimableWinnings for gas-efficient SSTORE
- Access control either via `msg.sender != address(this)` (self-call) or enforced in the delegatecall module

## Function Audit

### `creditDecJackpotClaimBatch(address[], uint256[], uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditDecJackpotClaimBatch(address[] calldata accounts, uint256[] calldata amounts, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `accounts` (address[]): player addresses to credit; `amounts` (uint256[]): wei amounts per player (total before split); `rngWord` (uint256): VRF random word for lootbox derivation |
| **Returns** | none |

**State Reads:** None directly in wrapper (all reads in DecimatorModule via delegatecall)
**State Writes:** None directly in wrapper (all writes in DecimatorModule via delegatecall: `claimableWinnings`, `claimablePool`, lootbox state)

**Callers:** DegenerusJackpots contract (access enforced in DecimatorModule)
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(creditDecJackpotClaimBatch.selector, ...)`, `_revertDelegate(data)`

**ETH Flow:** No direct ETH movement. Credits `claimableWinnings[account]` for each account (ETH accounting only). During gameover, credits 100% ETH; otherwise splits 50/50 ETH/lootbox.
**Invariants:** `claimablePool` must increase by the sum of ETH credited. Array lengths must match (enforced in module).
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes batch crediting, JACKPOTS-only access, 50/50 split, gameover 100% ETH, and VRF lootbox derivation.
**Gas Flags:** None. Thin delegatecall wrapper with no redundant operations.
**Verdict:** CORRECT

---

### `creditDecJackpotClaim(address, uint256, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditDecJackpotClaim(address account, uint256 amount, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `account` (address): player address to credit; `amount` (uint256): wei amount (total before split); `rngWord` (uint256): VRF random word for lootbox derivation |
| **Returns** | none |

**State Reads:** None directly in wrapper
**State Writes:** None directly in wrapper (DecimatorModule writes: `claimableWinnings[account]`, `claimablePool`, lootbox state)

**Callers:** DegenerusJackpots contract (access enforced in DecimatorModule)
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(creditDecJackpotClaim.selector, ...)`, `_revertDelegate(data)`

**ETH Flow:** No direct ETH movement. Credits `claimableWinnings[account]` for the single account. Split logic same as batch variant.
**Invariants:** Same as batch variant -- `claimablePool` increases by ETH portion credited.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes single-credit variant, JACKPOTS-only access, 50/50 split, gameover 100% ETH, VRF lootbox derivation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `recordDecBurn(address, uint24, uint8, uint256, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordDecBurn(address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps) external returns (uint8 bucketUsed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): burner; `lvl` (uint24): current game level; `bucket` (uint8): chosen denominator 2-12; `baseAmount` (uint256): burn amount before multiplier; `multBps` (uint256): multiplier in basis points (10000 = 1x) |
| **Returns** | `bucketUsed` (uint8): actual bucket used (may differ if not an improvement) |

**State Reads:** None directly in wrapper
**State Writes:** None directly in wrapper (DecimatorModule writes: `decBurn[lvl][player]`, `decBucketBurnTotal[lvl][bucket][sub]`)

**Callers:** BurnieCoin contract (COIN -- access enforced in DecimatorModule)
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(recordDecBurn.selector, ...)`, `_revertDelegate(data)`, `abi.decode(data, (uint8))`

**ETH Flow:** None. Records BURNIE burn for future jackpot eligibility.
**Invariants:** DecEntry for player at this level must reflect the best (lowest) bucket. Return value must be non-empty (`data.length == 0` reverts with `E()`).
**NatSpec Accuracy:** ACCURATE. NatSpec correctly documents COIN-only access, parameter semantics, and return value behavior. Note: NatSpec lists `(address, uint24, uint256, uint256)` in plan but actual signature includes `uint8 bucket` -- the contract signature `(address, uint24, uint8, uint256, uint256)` matches the interface `IDegenerusGameDecimatorModule.recordDecBurn`.
**Gas Flags:** None. Extra `data.length == 0` check is defensive (module always returns data on success).
**Verdict:** CORRECT

---

### `runDecimatorJackpot(uint256, uint24, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external returns (uint256 returnAmountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): total ETH prize pool for this level; `lvl` (uint24): level being resolved; `rngWord` (uint256): VRF-derived randomness seed |
| **Returns** | `returnAmountWei` (uint256): amount to return (non-zero if no winners or already snapshotted) |

**State Reads:** None directly in wrapper. Module reads: `decBucketBurnTotal[lvl]`, `decBurn[lvl]`
**State Writes:** None directly in wrapper. Module writes: `lastDecClaimRound` (snapshot), `decBucketOffsetPacked[lvl]`, `claimablePool`

**Callers:** Game self-call only (`msg.sender != address(this)` guard). Called during jackpot phase advancement.
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(runDecimatorJackpot.selector, ...)`, `_revertDelegate(data)`, `abi.decode(data, (uint256))`

**ETH Flow:** No direct ETH movement. Snapshots decimator winners for deferred claims. `poolWei` is allocated from decimator jackpot pool. If no winners, `returnAmountWei` returns the pool for redistribution.
**Invariants:** Only one snapshot per level (re-snapshot returns full pool). `lastDecClaimRound` must be set atomically with `decBucketOffsetPacked`. Return value must be non-empty (`data.length == 0` reverts).
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes self-call access, snapshot semantics, return value meaning, and callers' responsibility not to double-count.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `runTerminalJackpot(uint256, uint24, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord) external returns (uint256 paidWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): total ETH to distribute; `targetLvl` (uint24): level to sample winners from; `rngWord` (uint256): VRF entropy seed |
| **Returns** | `paidWei` (uint256): total ETH distributed |

**State Reads:** None directly in wrapper. JackpotModule reads ticket/burn arrays for winner selection.
**State Writes:** None directly in wrapper. JackpotModule writes: `claimableWinnings[winner]`, `claimablePool`

**Callers:** Game self-call only (`msg.sender != address(this)` guard). Called during x00-level jackpot resolution.
**Callees:** `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(runTerminalJackpot.selector, ...)` (note: JackpotModule, not DecimatorModule), `_revertDelegate(data)`, `abi.decode(data, (uint256))`

**ETH Flow:** Distributes `poolWei` via Day-5-style bucket distribution to `claimableWinnings[winner]`. Returns `paidWei` (total distributed). Module updates `claimablePool` internally.
**Invariants:** `paidWei <= poolWei`. NatSpec warns callers must NOT double-count claimablePool since module updates it internally. Return value must be non-empty.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly documents self-call access, Day-5-style distribution, internal claimablePool update, and the critical "callers must NOT double-count" warning.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `consumeDecClaim(address, uint24)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecClaim(address player, uint24 lvl) external returns (uint256 amountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to claim for; `lvl` (uint24): level to claim from |
| **Returns** | `amountWei` (uint256): pro-rata payout amount |

**State Reads:** None directly in wrapper. DecimatorModule reads: `lastDecClaimRound`, `decBurn[lvl][player]`, `decBucketOffsetPacked[lvl]`
**State Writes:** None directly in wrapper. DecimatorModule writes: `decBurn[lvl][player].claimed`, `claimableWinnings[player]`, `claimablePool`

**Callers:** Game self-call only (`msg.sender != address(this)` guard). Called during auto-rebuy processing.
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(consumeDecClaim.selector, ...)`, `_revertDelegate(data)`, `abi.decode(data, (uint256))`

**ETH Flow:** Credits `claimableWinnings[player]` with pro-rata share of decimator jackpot pool. No direct ETH transfer.
**Invariants:** Player's `DecEntry.claimed` must be set to prevent double-claim. Return value must be non-empty.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes self-call access, player address, level, and pro-rata payout semantics.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `claimDecimatorJackpot(uint24)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimDecimatorJackpot(uint24 lvl) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level to claim from (must be the last decimator round) |
| **Returns** | none |

**State Reads:** None directly in wrapper. DecimatorModule reads: `lastDecClaimRound`, `decBurn[lvl][msg.sender]`, `decBucketOffsetPacked[lvl]`
**State Writes:** None directly in wrapper. DecimatorModule writes: `decBurn[lvl][msg.sender].claimed`, `claimableWinnings[msg.sender]`, `claimablePool`

**Callers:** Any external caller (player claiming their own jackpot). No access restriction in wrapper -- module enforces winner validation.
**Callees:** `ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(claimDecimatorJackpot.selector, ...)`, `_revertDelegate(data)`

**ETH Flow:** Credits `claimableWinnings[msg.sender]` with pro-rata share. Player must subsequently call `claimWinnings()` to withdraw ETH. Two-step pull pattern.
**Invariants:** Only winners (matching subbucket) can claim. Only claimable once per player per level. Only the last decimator round is claimable (earlier rounds expire).
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes caller-initiated claim and the "must be last decimator" constraint.
**Gas Flags:** None. No return value expected (no `data.length == 0` check needed since module reverts on invalid claims).
**Verdict:** CORRECT

---

### `decClaimable(address, uint24)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function decClaimable(address player, uint24 lvl) external view returns (uint256 amountWei, bool winner)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): address to check; `lvl` (uint24): level to check |
| **Returns** | `amountWei` (uint256): claimable amount (0 if not eligible); `winner` (bool): true if player is a winner |

**State Reads:** `lastDecClaimRound.lvl`, `lastDecClaimRound.totalBurn`, `lastDecClaimRound.poolWei`, `decBurn[lvl][player]` (burn, bucket, subBucket, claimed), `decBucketOffsetPacked[lvl]`
**State Writes:** None (view function)

**Callers:** Any external caller (UI/frontend query). Also called internally by DecimatorModule.
**Callees:** `_unpackDecWinningSubbucket(packedOffsets, denom)`

**ETH Flow:** None (view only). Computes hypothetical pro-rata share: `(poolWei * entryBurn) / totalBurn`.
**Invariants:** Returns (0, false) for: wrong level, zero totalBurn, already claimed, zero bucket/burn, non-winning subbucket.

**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes the view semantics, return values, and conditions for zero return.

**Gas Flags:** None. View function with minimal reads (6 storage reads).

**Logic Review:**
1. `lastDecClaimRound.lvl != lvl` -> (0, false): Only last round claimable -- CORRECT
2. `totalBurn == 0` -> (0, false): No qualifying burns -- CORRECT
3. `e.claimed != 0` -> (0, false): Already claimed -- CORRECT
4. `denom == 0 || entryBurn == 0` -> (0, false): No valid entry -- CORRECT
5. `sub != winningSub` -> (0, false): Not a winner -- CORRECT
6. Pro-rata: `(poolWei * entryBurn) / totalBurn` -- CORRECT (totalBurn > 0 guaranteed by check 2)
7. `winner = amountWei != 0` -- CORRECT (possible rounding to 0 for dust entries)

**Verdict:** CORRECT

---

### `_unpackDecWinningSubbucket(uint64, uint8)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _unpackDecWinningSubbucket(uint64 packed, uint8 denom) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `packed` (uint64): packed winning subbuckets (4 bits each for denom 2-12); `denom` (uint8): denominator to unpack (2-12) |
| **Returns** | `uint8`: winning subbucket for this denominator |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `decClaimable` (view function in DegenerusGame)
**Callees:** None

**ETH Flow:** None
**Invariants:** `denom < 2` returns 0 (defensive, denom 0/1 are invalid). Shift: `(denom - 2) * 4` bits. Mask: `0xF` (4 bits). For denom 2-12, shift range is 0-40 bits (fits within uint64's 64 bits).

**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes unpacking logic and denom range.

**Gas Flags:** None. Pure bitwise operations, extremely gas-efficient.

**Logic Review:**
- `denom < 2` -> 0: Defensive guard for invalid denoms -- CORRECT
- `shift = (denom - 2) << 2`: Equivalent to `(denom - 2) * 4`. For denom 12: shift = 40. Max packed bit accessed = 43 (40 + 3), well within uint64 (63). -- CORRECT
- `(packed >> shift) & 0xF`: Extracts 4-bit subbucket value. Max subbucket value = 15, but valid range is 0..(denom-1). Module ensures valid packing. -- CORRECT

**Verdict:** CORRECT

---

## ETH Claims Functions

### `claimWinnings(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimWinnings(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to claim for (address(0) = msg.sender) |
| **Returns** | none |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly (delegates to `_claimWinningsInternal`)

**Callers:** Any external caller. Supports operator-approved claims via `_resolvePlayer`.
**Callees:** `_resolvePlayer(player)`, `_claimWinningsInternal(player, false)`

**ETH Flow:** Triggers ETH transfer to player via `_claimWinningsInternal` with `stethFirst=false` (ETH preferred, stETH fallback).
**Invariants:** Player must have `claimableWinnings[player] > 1` (sentinel). Operator must be approved if claiming on behalf of another.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes pull pattern, CEI, gas optimization (1-wei sentinel), and address(0) self-resolution.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `claimWinningsStethFirst()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimWinningsStethFirst() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | none |
| **Returns** | none |

**State Reads:** None directly (access check uses compile-time constants `ContractAddresses.VAULT`, `ContractAddresses.DGNRS`)
**State Writes:** None directly (delegates to `_claimWinningsInternal`)

**Callers:** Only VAULT or DGNRS contracts. Access enforced inline: `player != ContractAddresses.VAULT && player != ContractAddresses.DGNRS` reverts E().
**Callees:** `_claimWinningsInternal(msg.sender, true)`

**ETH Flow:** Triggers payout to msg.sender via `_claimWinningsInternal` with `stethFirst=true` (stETH preferred, ETH fallback). Used by VAULT/DGNRS to receive stETH (for yield).
**Invariants:** msg.sender must be VAULT or DGNRS. No player parameter -- self-claim only for trusted contracts.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes VAULT/DGNRS restriction and stETH-first semantics.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_claimWinningsInternal(address, bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimWinningsInternal(address player, bool stethFirst) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to pay out; `stethFirst` (bool): if true, send stETH first (ETH fallback); if false, send ETH first (stETH fallback) |
| **Returns** | none |

**State Reads:** `claimableWinnings[player]`
**State Writes:** `claimableWinnings[player]` (set to 1, sentinel), `claimablePool` (decremented by payout)

**Callers:** `claimWinnings(address)`, `claimWinningsStethFirst()`
**Callees:** `_payoutWithEthFallback(player, payout)` (when stethFirst=true), `_payoutWithStethFallback(player, payout)` (when stethFirst=false)

**ETH Flow:**
1. Read `amount = claimableWinnings[player]`
2. Revert if `amount <= 1` (nothing to claim beyond sentinel)
3. Set `claimableWinnings[player] = 1` (leave sentinel)
4. Compute `payout = amount - 1`
5. Decrement `claimablePool -= payout` (CEI: state before interaction)
6. Emit `WinningsClaimed(player, msg.sender, payout)`
7. Transfer: stethFirst -> `_payoutWithEthFallback`; else -> `_payoutWithStethFallback`

**Invariants:**
- CEI VERIFIED: `claimableWinnings[player]` set to 1 and `claimablePool` decremented BEFORE any external call
- Solvency: `claimablePool` decremented by exactly `payout`, maintaining `balance >= claimablePool`
- Sentinel: 1-wei sentinel prevents zero-to-nonzero SSTORE on future credits (20k gas savings)
- Reentrancy: CEI pattern makes reentrancy safe -- re-entering `claimWinnings` would see `claimableWinnings[player] = 1` and revert

**NatSpec Accuracy:** N/A (private function, no NatSpec). Logic matches the calling functions' documented behavior.

**Gas Flags:** `unchecked` block for sentinel math is safe: `amount > 1` guaranteed by preceding check, so `amount - 1` cannot underflow.

**Security Analysis:**
- The naming convention is slightly counterintuitive: `stethFirst=true` calls `_payoutWithEthFallback` (which sends stETH first, ETH fallback) and `stethFirst=false` calls `_payoutWithStethFallback` (which sends ETH first, stETH fallback). This is correct behavior -- the function names describe what is used as the FALLBACK, not the primary.

**Verdict:** CORRECT

---

### `claimAffiliateDgnrs(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimAffiliateDgnrs(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): affiliate address to claim for (address(0) = msg.sender) |
| **Returns** | none |

**State Reads:** `level`, `affiliateDgnrsClaimedBy[prevLevel][player]`, `deityPassCount[player]`, `levelPrizePool[prevLevel]`
**State Writes:** `affiliateDgnrsClaimedBy[prevLevel][player]` (set to true)

**Callers:** Any external caller. Supports operator-approved claims via `_resolvePlayer`.
**Callees:** `_resolvePlayer(player)`, `affiliate.affiliateScore(prevLevel, player)`, `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)`, `dgnrs.transferFromPool(Affiliate, player, reward)`, `coin.creditFlip(player, bonus)` (if deity pass holder with nonzero score)

**ETH Flow:** No ETH movement. Transfers DGNRS tokens from the Affiliate pool to the player. Optionally credits BURNIE flip via `coin.creditFlip` for deity pass holders.

**Logic Flow:**
1. Resolve player via `_resolvePlayer`
2. Require `level > 1` (must have a previous level to claim for)
3. Check `affiliateDgnrsClaimedBy[prevLevel][player]` -- revert if already claimed
4. Get affiliate score for previous level. Deity pass holders bypass minimum score requirement.
5. Compute denominator from `levelPrizePool[prevLevel]` (fallback to `BOOTSTRAP_PRIZE_POOL = 50 ETH`)
6. Compute `levelShare = (poolBalance * 500) / 10000` = 5% of affiliate DGNRS pool
7. Compute `reward = (levelShare * score) / denominator`
8. Transfer reward via `dgnrs.transferFromPool` -- revert if 0
9. If deity pass holder with nonzero score: credit `(score * 2000) / 10000` = 20% bonus as BURNIE flip credit
10. Set `affiliateDgnrsClaimedBy[prevLevel][player] = true`
11. Emit `AffiliateDgnrsClaimed`

**Invariants:**
- One claim per affiliate per level (enforced by mapping)
- Minimum score check bypassed for deity pass holders (intentional -- deity pass guarantees affiliate rewards)
- Reward proportional to affiliate score relative to level prize pool
- DGNRS pool can only decrease (no minting, only transfers from pool)

**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes previous-level claim, minimum score requirement, approximate denominator usage, and 5% pool share.

**Gas Flags:** None. Score is fetched via external call to Affiliate contract (necessary for cross-contract state).

**Verdict:** CORRECT

---

### `claimWhalePass(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimWhalePass(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to claim for (address(0) = msg.sender) |
| **Returns** | none |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)
**State Writes:** None directly (delegates to `_claimWhalePassFor`)

**Callers:** Any external caller. Supports operator-approved claims via `_resolvePlayer`.
**Callees:** `_resolvePlayer(player)`, `_claimWhalePassFor(player)`

**ETH Flow:** Delegates to EndgameModule which handles whale pass reward payout. Credits `claimableWinnings` for large lootbox wins above 5 ETH threshold.
**Invariants:** Player must have pending whale pass rewards. Operator must be approved if claiming on behalf.
**NatSpec Accuracy:** ACCURATE. NatSpec correctly describes deferred whale pass rewards, >5 ETH threshold, and unified claim function.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_claimWhalePassFor(address)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimWhalePassFor(address player) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to claim whale pass for |
| **Returns** | none |

**State Reads:** None directly in wrapper (EndgameModule reads whale pass state)
**State Writes:** None directly in wrapper (EndgameModule writes whale pass state, may update `claimableWinnings`, `claimablePool`)

**Callers:** `claimWhalePass(address)`
**Callees:** `ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(IDegenerusGameEndgameModule.claimWhalePass.selector, player)`, `_revertDelegate(data)`

**ETH Flow:** Delegates to EndgameModule for whale pass pricing and payout logic. The module handles crediting `claimableWinnings` based on whale pass pricing at the current level.
**Invariants:** Delegatecall must succeed. Module handles all validation (pending claims, eligibility).
**NatSpec Accuracy:** N/A (private function, no NatSpec). Behavior matches `claimWhalePass` documentation.
**Gas Flags:** None. Thin delegatecall wrapper.
**Verdict:** CORRECT

---

## Delegatecall Dispatch Table

| Source Function | Target Module | Target Selector | Access Control |
|----------------|---------------|-----------------|----------------|
| `creditDecJackpotClaimBatch` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.creditDecJackpotClaimBatch` | JACKPOTS only (enforced in module) |
| `creditDecJackpotClaim` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.creditDecJackpotClaim` | JACKPOTS only (enforced in module) |
| `recordDecBurn` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.recordDecBurn` | COIN only (enforced in module) |
| `runDecimatorJackpot` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.runDecimatorJackpot` | self-call only (wrapper) |
| `runTerminalJackpot` | GAME_JACKPOT_MODULE | `IDegenerusGameJackpotModule.runTerminalJackpot` | self-call only (wrapper) |
| `consumeDecClaim` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.consumeDecClaim` | self-call only (wrapper) |
| `claimDecimatorJackpot` | GAME_DECIMATOR_MODULE | `IDegenerusGameDecimatorModule.claimDecimatorJackpot` | any (module validates winner) |
| `_claimWhalePassFor` | GAME_ENDGAME_MODULE | `IDegenerusGameEndgameModule.claimWhalePass` | any (via `claimWhalePass` entry point) |

**Notes:**
- 6 of 8 delegatecalls target DecimatorModule; 1 targets JackpotModule (`runTerminalJackpot`); 1 targets EndgameModule (`_claimWhalePassFor`)
- Self-call guard (`msg.sender != address(this)`) is used for 3 functions that are called internally during game advancement
- Module-enforced access control is used for functions called by other protocol contracts (JACKPOTS, COIN)
- `claimDecimatorJackpot` has no wrapper access control -- module validates the caller is a winner

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function | CEI |
|------|--------|-------------|---------|----------|-----|
| Winnings claim (ETH) | `claimableWinnings[player]` | player address (ETH) | `claimWinnings()` | `_claimWinningsInternal` -> `_payoutWithStethFallback` | YES |
| Winnings claim (stETH-first) | `claimableWinnings[player]` | player address (stETH preferred) | `claimWinningsStethFirst()` | `_claimWinningsInternal` -> `_payoutWithEthFallback` | YES |
| Decimator credit (single) | `decJackpotPool` (via module) | `claimableWinnings[account]` | jackpot resolution | `creditDecJackpotClaim` -> DecimatorModule | N/A (accounting) |
| Decimator credit (batch) | `decJackpotPool` (via module) | `claimableWinnings[accounts[i]]` | jackpot resolution | `creditDecJackpotClaimBatch` -> DecimatorModule | N/A (accounting) |
| Decimator jackpot snapshot | `poolWei` (parameter) | `lastDecClaimRound` (deferred) | x100-level advancement | `runDecimatorJackpot` -> DecimatorModule | N/A (snapshot) |
| Decimator claim (player) | `lastDecClaimRound.poolWei` (pro-rata) | `claimableWinnings[msg.sender]` | player action | `claimDecimatorJackpot` -> DecimatorModule | N/A (accounting) |
| Decimator claim (auto-rebuy) | `lastDecClaimRound.poolWei` (pro-rata) | `claimableWinnings[player]` | auto-rebuy processing | `consumeDecClaim` -> DecimatorModule | N/A (accounting) |
| Terminal jackpot | `poolWei` (parameter) | `claimableWinnings[winner]` | x00-level advancement | `runTerminalJackpot` -> JackpotModule | N/A (accounting) |
| Whale pass claim | whale pass rewards | `claimableWinnings[player]` | player action | `claimWhalePass` -> EndgameModule | Module-internal |
| Affiliate DGNRS | DGNRS Affiliate pool | player (DGNRS tokens) | player action | `claimAffiliateDgnrs` | YES (claim flag set before transfer) |
| Affiliate deity bonus | N/A | player (BURNIE flip credit) | player action (deity holders) | `claimAffiliateDgnrs` -> `coin.creditFlip` | N/A (credit, no ETH) |

**Key observations:**
1. All direct ETH exits go through `_claimWinningsInternal` which enforces CEI (sentinel set + claimablePool decremented before external call)
2. Decimator/terminal jackpot paths are two-phase: first credit `claimableWinnings` (accounting), then player withdraws via `claimWinnings` (ETH)
3. `claimAffiliateDgnrs` is a DGNRS (ERC20) exit, not ETH -- but uses claim-flag-before-transfer pattern
4. Solvency invariant `address(this).balance + steth.balanceOf(address(this)) >= claimablePool` is maintained because every `claimablePool` increment has a corresponding ETH deposit, and every decrement has a corresponding payout

## Findings Summary

### Severity Counts

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | -- |
| CONCERN | 0 | -- |
| GAS (informational) | 0 | -- |
| NatSpec (informational) | 0 | -- |

### Overall Assessment

All 15 audited functions (9 decimator + 6 claim) are **CORRECT** with no bugs, concerns, or gas issues found.

**Key security properties verified:**
1. **CEI pattern**: `_claimWinningsInternal` enforces checks-effects-interactions on all ETH exits (state updated before external call)
2. **Reentrancy safety**: Sentinel pattern (set to 1 before transfer) prevents re-entrant claims
3. **Solvency invariant**: `claimablePool` is always decremented by exactly the payout amount before ETH leaves the contract
4. **Access control**: Self-call guards on internal jackpot functions, module-enforced access on cross-contract calls, operator approval on player-facing claims
5. **Pull pattern**: All ETH exits use the two-step pull pattern (credit to claimableWinnings, then explicit claim)
6. **Delegatecall safety**: All 8 delegatecall wrappers follow the same pattern with `_revertDelegate` for error propagation
7. **Sentinel optimization**: 1-wei sentinel on claimableWinnings avoids zero-to-nonzero SSTORE (20k gas savings per subsequent credit)
8. **Dual payout fallback**: Both `_payoutWithStethFallback` and `_payoutWithEthFallback` handle insufficient primary balance by falling back to the secondary asset
