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
