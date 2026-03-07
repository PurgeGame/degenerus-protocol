# DegenerusGameDecimatorModule.sol -- Function-Level Audit

**Contract:** DegenerusGameDecimatorModule
**File:** contracts/modules/DegenerusGameDecimatorModule.sol
**Lines:** 748
**Solidity:** 0.8.34
**Inherits:** DegenerusGamePayoutUtils (-> DegenerusGameStorage)
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

Handles decimator jackpot tracking (burn recording per bucket/subbucket), jackpot resolution (VRF-based winning subbucket selection per denominator 2-12), and claim distribution (pro-rata based on burn share within winning subbuckets). Supports auto-rebuy for claim winnings. Credits decimator jackpot claims from JACKPOTS contract. Manages 50/50 ETH/lootbox split for non-gameover claims; 100% ETH for gameover claims. Multiplier cap at 200 BURNIE mint equivalents prevents unlimited compounding.

## Function Audit

### `creditDecJackpotClaimBatch(address[] accounts, uint256[] amounts, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditDecJackpotClaimBatch(address[] calldata accounts, uint256[] calldata amounts, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `accounts` (address[] calldata): array of player addresses to credit; `amounts` (uint256[] calldata): corresponding wei amounts per player; `rngWord` (uint256): VRF random word for lootbox entropy |
| **Returns** | none |

**State Reads:** `gameOver` (bool), `claimablePool` (via `_creditClaimable`, `_processAutoRebuy`, `_creditDecJackpotClaimCore`), `autoRebuyState[account]` (via `_processAutoRebuy`), `decimatorAutoRebuyDisabled[account]` (via `_processAutoRebuy`), `level` (via `_processAutoRebuy`)

**State Writes:** `claimableWinnings[account]` (via `_creditClaimable` or `_addClaimableEth`), `futurePrizePool` (lootbox portion aggregated across batch, and via `_processAutoRebuy`), `nextPrizePool` (via `_processAutoRebuy`), `claimablePool` (decremented by lootbox portion in `_creditDecJackpotClaimCore`, decremented by auto-rebuy ethSpent in `_processAutoRebuy`), `ticketsOwedPacked` / `ticketQueue` (via `_queueTickets` in auto-rebuy path), `whalePassClaims[account]` (via `_queueWhalePassClaimCore` in lootbox path)

**Callers:** DegenerusJackpots contract (external call, not delegatecall)

**Callees:**
- GameOver path: `_addClaimableEth` -> `_processAutoRebuy` -> `_calcAutoRebuy`, `_creditClaimable`, `_queueTickets` OR `_creditClaimable`
- Normal path: `_creditDecJackpotClaimCore` -> `_addClaimableEth` (for ETH half), `_awardDecimatorLootbox` (for lootbox half)

**ETH Flow:**
- GameOver: full `amounts[i]` from claimablePool -> `claimableWinnings[account]` (or auto-rebuy tickets)
- Normal: 50% ETH portion from claimablePool -> `claimableWinnings[account]` (or auto-rebuy); 50% lootbox portion deducted from `claimablePool`, resolved via lootbox or whale pass claim; aggregate `totalLootbox` added to `futurePrizePool` at end

**Access Control:** `msg.sender != ContractAddresses.JACKPOTS` reverts with `E()`. Array length mismatch also reverts with `E()`.

**Invariants:**
- `accounts.length == amounts.length` enforced
- Zero amounts and zero-address accounts silently skipped (no credit, no revert)
- In normal mode, lootbox portions are batched and added to `futurePrizePool` once at end (gas optimization)
- `claimablePool` must be >= total credited + lootbox portions (pre-reserved by caller)

**NatSpec Accuracy:** Accurate. NatSpec correctly describes batch crediting, gameover vs normal split, JACKPOTS-only access, and VRF usage for lootbox derivation.

**Gas Flags:**
- Optimization: `totalLootbox` accumulated in memory, single `futurePrizePool` write at end
- `unchecked { ++i; }` used for loop counter (safe, bounded by array length)
- `unchecked { totalLootbox += lootboxPortion; }` -- potential overflow if extremely large batch, but practically safe given ETH supply constraints

**Verdict:** CORRECT

---

### `creditDecJackpotClaim(address account, uint256 amount, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditDecJackpotClaim(address account, uint256 amount, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `account` (address): player address to credit; `amount` (uint256): wei amount to credit; `rngWord` (uint256): VRF random word for lootbox entropy |
| **Returns** | none |

**State Reads:** `gameOver`, `claimablePool` (via helpers), `autoRebuyState[account]`, `decimatorAutoRebuyDisabled[account]`, `level`

**State Writes:** `claimableWinnings[account]` (via `_creditClaimable`), `futurePrizePool` (lootbox portion, and auto-rebuy future path), `nextPrizePool` (auto-rebuy next path), `claimablePool` (decremented), `ticketsOwedPacked` / `ticketQueue` (auto-rebuy), `whalePassClaims[account]` (whale pass path)

**Callers:** DegenerusJackpots contract (external call)

**Callees:**
- GameOver: `_addClaimableEth`
- Normal: `_creditDecJackpotClaimCore` -> `_addClaimableEth` (ETH half) + `_awardDecimatorLootbox` (lootbox half)

**ETH Flow:**
- GameOver: full `amount` from claimablePool -> `claimableWinnings[account]` (or auto-rebuy)
- Normal: 50% -> `claimableWinnings[account]` (or auto-rebuy); 50% lootbox deducted from `claimablePool`, `lootboxPortion` added to `futurePrizePool`

**Access Control:** `msg.sender != ContractAddresses.JACKPOTS` reverts with `E()`.

**Invariants:**
- Zero amount or zero address returns early (no-op)
- Single-account version of batch function with identical semantics

**NatSpec Accuracy:** Accurate. Correctly describes single credit, gameover/normal split, JACKPOTS-only access.

**Gas Flags:** None. Clean single-account path.

**Verdict:** CORRECT

---

### `recordDecBurn(address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordDecBurn(address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps) external returns (uint8 bucketUsed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): burning player; `lvl` (uint24): current game level; `bucket` (uint8): denominator choice 2-12; `baseAmount` (uint256): burn amount before multiplier; `multBps` (uint256): multiplier in BPS (10000 = 1x) |
| **Returns** | `bucketUsed` (uint8): actual bucket used (may differ from requested if not an improvement) |

**State Reads:** `decBurn[lvl][player]` (full DecEntry: burn, bucket, subBucket, claimed)

**State Writes:** `decBurn[lvl][player].burn` (new accumulated burn), `decBurn[lvl][player].bucket` (set or migrated), `decBurn[lvl][player].subBucket` (set or migrated), `decBucketBurnTotal[lvl][denom][sub]` (updated via `_decUpdateSubbucket`, decremented via `_decRemoveSubbucket` on migration)

**Callers:** BurnieCoin contract (external call via `ContractAddresses.COIN`)

**Callees:** `_decSubbucketFor` (deterministic assignment), `_decRemoveSubbucket` (migration removal), `_decUpdateSubbucket` (aggregate increment), `_decEffectiveAmount` (multiplier cap calculation)

**ETH Flow:** None. Pure burn accounting -- no ETH moves.

**Access Control:** `msg.sender != ContractAddresses.COIN` reverts with `OnlyCoin()`.

**Invariants:**
- First burn (bucket==0): sets bucket and subbucket deterministically
- Better bucket (bucket != 0 && bucket < current): migrates -- removes old aggregate, assigns new subbucket, carries burn
- Same or worse bucket: ignored (existing bucket used)
- Burn accumulates with `uint192` saturation (capped at `type(uint192).max`)
- Delta (newBurn - prevBurn) added to subbucket aggregate only if non-zero
- Event emitted only when delta != 0
- `effectiveAmount` subject to multiplier cap (DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT)

**NatSpec Accuracy:** Accurate. Documents first-burn behavior, better-bucket migration, uint192 saturation, multiplier cap at 200 mints, COIN-only access.

**Gas Flags:**
- Memory copy of DecEntry (`DecEntry memory m = e;`) avoids repeated SLOADs during bucket comparison logic -- good optimization
- Three separate storage writes for `e.burn`, `e.bucket`, `e.subBucket` instead of a single packed write. However, Solidity compiler packs these into one slot (burn=uint192 + bucket=uint8 + subBucket=uint8 + claimed=uint8 = 210 bits < 256 bits), so the compiler should handle this efficiently with a single SSTORE under optimization.

**Verdict:** CORRECT

---

### `runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external returns (uint256 returnAmountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): total ETH prize pool for this level; `lvl` (uint24): level being resolved; `rngWord` (uint256): VRF-derived randomness seed |
| **Returns** | `returnAmountWei` (uint256): amount to return to caller (non-zero if no winners or already snapshotted, 0 if held for claims) |

**State Reads:** `lastDecClaimRound.lvl` (double-snapshot check), `decBucketBurnTotal[lvl][denom][winningSub]` (per-denom subbucket burn totals for denoms 2-12)

**State Writes:** `decBucketOffsetPacked[lvl]` (packed winning subbuckets), `lastDecClaimRound.lvl`, `lastDecClaimRound.poolWei`, `lastDecClaimRound.totalBurn`, `lastDecClaimRound.rngWord`

**Callers:** DegenerusGame contract (via `ContractAddresses.GAME` -- delegatecall from advance flow)

**Callees:** `_decWinningSubbucket` (VRF-based winner selection per denom), `_packDecWinningSubbucket` (4-bit packing)

**ETH Flow:**
- If already snapshotted (`lastDecClaimRound.lvl == lvl`): returns full `poolWei` to caller (no state change)
- If no qualifying burns (`totalBurn == 0`): returns full `poolWei` to caller
- If `totalBurn > type(uint232).max`: returns full `poolWei` (defensive, economically impossible)
- Otherwise: holds all `poolWei` in `lastDecClaimRound` for claim distribution, returns 0

**Access Control:** `msg.sender != ContractAddresses.GAME` reverts with `OnlyGame()`.

**Invariants:**
- Double-snapshot prevention: if `lastDecClaimRound.lvl == lvl`, returns pool immediately
- Previous claims expire when new snapshot overwrites `lastDecClaimRound` (intentional -- only last level claimable)
- `totalBurn` capped check at `uint232.max` prevents overflow when stored as `uint232`
- Winning subbucket selected deterministically from VRF per denom -- reproducible from same rngWord
- All 11 denoms (2-12) processed in single call

**NatSpec Accuracy:** Accurate. Correctly describes snapshot behavior, deferred claim distribution, return-on-no-winners, GAME-only access.

**Gas Flags:**
- Loop over 11 denominations (2-12) is fixed-cost, no unbounded iteration
- `decSeed` (renamed `rngWord`) used directly without re-hashing at loop level -- `_decWinningSubbucket` hashes internally with `(entropy, denom)` so each denom gets unique randomness. Correct.

**Verdict:** CORRECT

---

### `consumeDecClaim(address player, uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecClaim(address player, uint24 lvl) external returns (uint256 amountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player claiming; `lvl` (uint24): level to claim from |
| **Returns** | `amountWei` (uint256): pro-rata payout amount |

**State Reads:** `lastDecClaimRound.lvl` (active round check), `lastDecClaimRound.totalBurn`, `lastDecClaimRound.poolWei`, `decBurn[lvl][player]` (DecEntry: burn, bucket, subBucket, claimed), `decBucketOffsetPacked[lvl]` (packed winning subbuckets)

**State Writes:** `decBurn[lvl][player].claimed = 1` (marks claimed)

**Callers:** DegenerusGame contract (via `ContractAddresses.GAME`)

**Callees:** `_consumeDecClaim` (internal validation and marking)

**ETH Flow:** None directly. Returns `amountWei` for caller to handle crediting. The actual ETH movement happens in the caller (GAME contract) which routes through credit functions.

**Access Control:** `msg.sender != ContractAddresses.GAME` reverts with `OnlyGame()`.

**Invariants:**
- Delegates to `_consumeDecClaim` which enforces: active round match, not-already-claimed, winner verification
- Returns pro-rata share: `(poolWei * playerBurn) / totalBurn`

**NatSpec Accuracy:** Accurate. Correctly describes game-initiated claim consumption, GAME-only access.

**Gas Flags:** None. Simple wrapper around `_consumeDecClaim`.

**Verdict:** CORRECT

---

### `claimDecimatorJackpot(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimDecimatorJackpot(uint24 lvl) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level to claim from (must be last decimator) |
| **Returns** | none |

**State Reads:** `gameOver`, `lastDecClaimRound` (.lvl, .totalBurn, .poolWei, .rngWord), `decBurn[lvl][msg.sender]` (DecEntry), `decBucketOffsetPacked[lvl]`, `autoRebuyState[msg.sender]`, `decimatorAutoRebuyDisabled[msg.sender]`, `level`

**State Writes:** `decBurn[lvl][msg.sender].claimed = 1`, `claimableWinnings[msg.sender]` (via `_creditClaimable` or auto-rebuy), `futurePrizePool` (lootbox portion or auto-rebuy future), `nextPrizePool` (auto-rebuy next), `claimablePool` (decremented), `ticketsOwedPacked` / `ticketQueue` (auto-rebuy), `whalePassClaims[msg.sender]` (whale pass path)

**Callers:** Any external account (public self-claim for `msg.sender`)

**Callees:**
- `_consumeDecClaim` (validation + marking)
- GameOver: `_addClaimableEth` (100% ETH)
- Normal: `_creditDecJackpotClaimCore` (50/50 split)

**ETH Flow:**
- GameOver: `amountWei` from `lastDecClaimRound.poolWei` (pro-rata share) -> `claimableWinnings[msg.sender]` or auto-rebuy tickets
- Normal: 50% ETH -> `claimableWinnings[msg.sender]` or auto-rebuy; 50% lootbox deducted from `claimablePool`, resolved via `_awardDecimatorLootbox`, `lootboxPortion` added to `futurePrizePool`

**Access Control:** Public -- any address can call for themselves. No access restriction (self-claim only via `msg.sender`).

**Invariants:**
- Must pass `_consumeDecClaim` validation (active round, not claimed, winner)
- Self-claim only (`msg.sender` used throughout)
- GameOver uses `lastDecClaimRound.rngWord` for auto-rebuy entropy
- Normal mode uses `lastDecClaimRound.rngWord` for lootbox entropy

**NatSpec Accuracy:** Accurate. Correctly describes public self-claim, claimable balance crediting, claim expiration.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `decClaimable(address player, uint24 lvl)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function decClaimable(address player, uint24 lvl) external view returns (uint256 amountWei, bool winner)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): address to check; `lvl` (uint24): level to check |
| **Returns** | `amountWei` (uint256): claimable amount (0 if not winner/claimed/expired); `winner` (bool): true if player is winner for this level |

**State Reads:** `lastDecClaimRound.lvl` (active round check), `lastDecClaimRound.totalBurn`, `lastDecClaimRound.poolWei`, `decBurn[lvl][player]` (DecEntry), `decBucketOffsetPacked[lvl]`

**State Writes:** None (view function).

**Callers:** External UI/frontend, other contracts querying claimability.

**Callees:** `_decClaimable` (internal view helper) -> `_decClaimableFromEntry` -> `_unpackDecWinningSubbucket`

**ETH Flow:** None (view function).

**Access Control:** None -- public view function.

**Invariants:**
- Returns (0, false) if lvl is not the active decimator round
- Returns (0, false) if player already claimed (e.claimed != 0)
- Returns (0, false) if player's subbucket doesn't match winning subbucket
- Returns (proRataShare, true) if player is unclaimed winner
- Pro-rata: `(poolWei * playerBurn) / totalBurn`

**NatSpec Accuracy:** Accurate. Correctly describes view function purpose, return values, expiration behavior.

**Gas Flags:** None. Clean view function.

**Verdict:** CORRECT
