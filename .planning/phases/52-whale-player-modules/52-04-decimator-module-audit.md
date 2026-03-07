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

---

## Internal/Private Functions

### `_consumeDecClaim(address player, uint24 lvl)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _consumeDecClaim(address player, uint24 lvl) internal returns (uint256 amountWei)` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): claiming player; `lvl` (uint24): level to claim from |
| **Returns** | `amountWei` (uint256): pro-rata payout amount |

**State Reads:** `lastDecClaimRound.lvl`, `lastDecClaimRound.totalBurn`, `lastDecClaimRound.poolWei`, `decBurn[lvl][player]` (DecEntry: burn, bucket, subBucket, claimed), `decBucketOffsetPacked[lvl]`

**State Writes:** `decBurn[lvl][player].claimed = 1`

**Callers:** `consumeDecClaim` (external, GAME-only), `claimDecimatorJackpot` (external, public self-claim)

**Callees:** `_decClaimableFromEntry` (pro-rata calculation)

**ETH Flow:** None directly. Returns amount; callers handle crediting.

**Invariants:**
- `lastDecClaimRound.lvl != lvl` -> `DecClaimInactive`
- `e.claimed != 0` -> `DecAlreadyClaimed`
- `amountWei == 0` (not winner) -> `DecNotWinner`
- Sets `e.claimed = 1` to prevent double-claiming
- Pro-rata formula: `(poolWei * playerBurn) / totalBurn`

**NatSpec Accuracy:** Accurate. Correctly documents internal validation, revert conditions, and claim marking.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_creditDecJackpotClaimCore(address account, uint256 amount, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditDecJackpotClaimCore(address account, uint256 amount, uint256 rngWord) private returns (uint256 lootboxPortion)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `account` (address): player to credit; `amount` (uint256): total claim amount; `rngWord` (uint256): VRF entropy for lootbox |
| **Returns** | `lootboxPortion` (uint256): amount routed to lootbox (caller must add to futurePrizePool) |

**State Reads:** `autoRebuyState[account]`, `decimatorAutoRebuyDisabled[account]`, `level` (via `_addClaimableEth` -> `_processAutoRebuy`), `claimablePool`

**State Writes:** `claimableWinnings[account]` (ETH half via `_addClaimableEth`), `claimablePool` (decremented by lootboxPortion), `whalePassClaims[account]` (if lootbox > threshold), `ticketsOwedPacked` / `ticketQueue` (auto-rebuy path), `nextPrizePool` / `futurePrizePool` (auto-rebuy path)

**Callers:** `creditDecJackpotClaimBatch`, `creditDecJackpotClaim`, `claimDecimatorJackpot` (all in non-gameover mode)

**Callees:** `_addClaimableEth` (ETH half), `_awardDecimatorLootbox` (lootbox half)

**ETH Flow:**
- Split: `ethPortion = amount >> 1` (floor division), `lootboxPortion = amount - ethPortion` (ceiling)
- ETH half -> `_addClaimableEth` -> `claimableWinnings[account]` or auto-rebuy
- Lootbox half: `claimablePool -= lootboxPortion`, then resolved via `_awardDecimatorLootbox`
- `lootboxPortion` returned to caller for `futurePrizePool` addition

**Invariants:**
- Callers ensure `amount != 0` and `account != address(0)` (NatSpec documents this precondition)
- Odd-wei split: ETH gets floor, lootbox gets ceiling (1 wei favors lootbox -- negligible)
- `claimablePool` decremented by lootbox portion (no longer reserved as claimable ETH)

**NatSpec Accuracy:** Accurate. Documents preconditions, split logic, and return value semantics.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_processAutoRebuy(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processAutoRebuy(address beneficiary, uint256 weiAmount, uint256 entropy) private returns (bool handled)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): player to process; `weiAmount` (uint256): ETH to potentially convert; `entropy` (uint256): RNG seed for level selection |
| **Returns** | `handled` (bool): true if auto-rebuy processed funds |

**State Reads:** `autoRebuyState[beneficiary]` (.autoRebuyEnabled, .takeProfit, .afKingMode), `decimatorAutoRebuyDisabled[beneficiary]`, `level` (via `_calcAutoRebuy`)

**State Writes:** `claimableWinnings[beneficiary]` (reserved portion via `_creditClaimable`), `futurePrizePool` (if `calc.toFuture`), `nextPrizePool` (if not `calc.toFuture`), `claimablePool` (decremented by `calc.ethSpent`), `ticketsOwedPacked[calc.targetLevel][beneficiary]` / `ticketQueue[calc.targetLevel]` (via `_queueTickets`)

**Callers:** `_addClaimableEth`

**Callees:** `_calcAutoRebuy` (PayoutUtils, pure calculation), `_creditClaimable` (reserved amount + fallback if no tickets), `_queueTickets` (ticket queuing)

**ETH Flow:**
- If auto-rebuy disabled (either globally or decimator-specific): returns false (not handled)
- If `_calcAutoRebuy` returns `!hasTickets`: full `weiAmount` -> `_creditClaimable` (fallback), returns true
- If `calc.hasTickets`: `calc.ethSpent` -> `nextPrizePool` or `futurePrizePool` (75% future, 25% next via entropy); `calc.reserved` (take-profit) -> `_creditClaimable`; `claimablePool -= calc.ethSpent`
- Tickets queued at `calc.targetLevel` with bonus (130% normal, 145% afKing)

**Invariants:**
- `decimatorAutoRebuyDisabled` provides per-player opt-out for decimator-specific auto-rebuy
- Take-profit reserving happens before ticket conversion
- `claimablePool` only decremented by `ethSpent` (ticket conversion), not by reserved amount (reserved stays in claimable pool via `_creditClaimable`)
- Event `AutoRebuyProcessed` emitted with full details

**NatSpec Accuracy:** Accurate. Documents auto-rebuy processing, entropy usage, return semantics.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): player to credit; `weiAmount` (uint256): ETH amount; `entropy` (uint256): RNG seed for auto-rebuy |
| **Returns** | none |

**State Reads:** (delegated to `_processAutoRebuy` and `_creditClaimable`)

**State Writes:** (delegated to `_processAutoRebuy` or `_creditClaimable`)

**Callers:** `creditDecJackpotClaimBatch` (gameover path), `creditDecJackpotClaim` (gameover path), `claimDecimatorJackpot` (gameover path), `_creditDecJackpotClaimCore` (ETH half in normal mode)

**Callees:** `_processAutoRebuy`, `_creditClaimable`

**ETH Flow:**
- `weiAmount == 0`: returns immediately (no-op)
- Auto-rebuy enabled and handles: `_processAutoRebuy` routes to tickets
- Otherwise: `_creditClaimable` adds to `claimableWinnings[beneficiary]`

**Invariants:**
- Zero-amount guard prevents unnecessary processing
- Auto-rebuy takes priority over direct crediting

**NatSpec Accuracy:** Accurate. Simple routing function documented correctly.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_decEffectiveAmount(uint256 prevBurn, uint256 baseAmount, uint256 multBps)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _decEffectiveAmount(uint256 prevBurn, uint256 baseAmount, uint256 multBps) private pure returns (uint256 effectiveAmount)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `prevBurn` (uint256): previous accumulated burn; `baseAmount` (uint256): new burn before multiplier; `multBps` (uint256): multiplier in BPS |
| **Returns** | `effectiveAmount` (uint256): burn amount after capped multiplier |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `recordDecBurn`

**Callees:** None.

**ETH Flow:** None. Pure math.

**Invariants:**
- `baseAmount == 0` -> returns 0
- `multBps <= BPS_DENOMINATOR` (multiplier <= 1x) -> returns `baseAmount` (no multiplier benefit)
- `prevBurn >= DECIMATOR_MULTIPLIER_CAP` -> returns `baseAmount` (cap already reached, 1x only)
- `remaining = CAP - prevBurn` (how much capacity left for multiplied burns)
- If `fullEffective <= remaining`: entire burn fits under cap, returns `fullEffective = (baseAmount * multBps) / BPS_DENOMINATOR`
- If `fullEffective > remaining`: partial split -- `maxMultBase` gets multiplied, remainder at 1x
  - `maxMultBase = (remaining * BPS_DENOMINATOR) / multBps` -- base amount that fits within remaining cap
  - `multiplied = (maxMultBase * multBps) / BPS_DENOMINATOR` -- multiplied portion
  - `effectiveAmount = multiplied + (baseAmount - maxMultBase)` -- multiplied part + 1x remainder
- DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT = 200 * 1000 ether = 200,000 BURNIE (200 mint equivalents)

**NatSpec Accuracy:** Accurate. Documents cap behavior, partial split logic.

**Gas Flags:**
- Double division in partial split path (`remaining * BPS_DENOMINATOR / multBps` then `maxMultBase * multBps / BPS_DENOMINATOR`) introduces rounding, but always rounds down -- player gets slightly less than cap, which is conservative/safe.

**Verdict:** CORRECT

---

### `_decWinningSubbucket(uint256 entropy, uint8 denom)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _decWinningSubbucket(uint256 entropy, uint8 denom) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF-derived randomness; `denom` (uint8): denominator (2-12) |
| **Returns** | winning subbucket index (uint8), range 0 to denom-1 |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `runDecimatorJackpot`

**Callees:** None.

**ETH Flow:** None.

**Invariants:**
- `denom == 0`: returns 0 (guard against division by zero)
- Hash: `keccak256(abi.encodePacked(entropy, denom))` ensures unique randomness per denom from same seed
- Result: `hash % denom` gives uniform distribution over [0, denom-1] (modulo bias negligible for small denom values 2-12 against 256-bit hash)

**NatSpec Accuracy:** Accurate. Documents deterministic selection from VRF.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_packDecWinningSubbucket(uint64 packed, uint8 denom, uint8 sub)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _packDecWinningSubbucket(uint64 packed, uint8 denom, uint8 sub) private pure returns (uint64)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `packed` (uint64): current packed value; `denom` (uint8): denominator to pack (2-12); `sub` (uint8): winning subbucket |
| **Returns** | updated packed value (uint64) |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `runDecimatorJackpot`

**Callees:** None.

**ETH Flow:** None.

**Invariants:**
- Layout: 4 bits per denom, starting at bit 0 for denom 2
- Shift: `(denom - 2) << 2` = `(denom - 2) * 4`
- For denom 2: bits 0-3, denom 3: bits 4-7, ..., denom 12: bits 40-43
- Total: 44 bits used (11 denoms * 4 bits), fits in uint64
- Maximum subbucket value: denom-1 = 11 (for denom 12), needs 4 bits (max 15) -- fits
- Mask-and-set: clears target 4-bit slot, then ORs new value

**NatSpec Accuracy:** Accurate. Documents 4-bit packing layout.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_unpackDecWinningSubbucket(uint64 packed, uint8 denom)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _unpackDecWinningSubbucket(uint64 packed, uint8 denom) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `packed` (uint64): packed winning subbuckets; `denom` (uint8): denominator to unpack (2-12) |
| **Returns** | winning subbucket for this denom (uint8) |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `_decClaimableFromEntry`

**Callees:** None.

**ETH Flow:** None.

**Invariants:**
- `denom < 2`: returns 0 (guard for invalid denom)
- Shift: `(denom - 2) << 2` = same layout as pack
- Extract: `(packed >> shift) & 0xF` = 4-bit value
- Inverse of `_packDecWinningSubbucket` -- symmetry verified

**NatSpec Accuracy:** Accurate. Documents unpacking from same layout.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_decClaimableFromEntry(uint256 poolWei, uint256 totalBurn, DecEntry storage e, uint64 packedOffsets)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _decClaimableFromEntry(uint256 poolWei, uint256 totalBurn, DecEntry storage e, uint64 packedOffsets) private view returns (uint256 amountWei)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `poolWei` (uint256): total pool; `totalBurn` (uint256): total qualifying burn; `e` (DecEntry storage): player's entry; `packedOffsets` (uint64): packed winning subbuckets |
| **Returns** | `amountWei` (uint256): player's pro-rata share (0 if not winner) |

**State Reads:** `e.bucket`, `e.subBucket`, `e.burn` (from storage reference)

**State Writes:** None (view function).

**Callers:** `_consumeDecClaim`, `_decClaimable`

**Callees:** `_unpackDecWinningSubbucket`

**ETH Flow:** None (view computation).

**Invariants:**
- `totalBurn == 0` -> returns 0
- `denom == 0` (no participation) -> returns 0
- `entryBurn == 0` -> returns 0
- Subbucket mismatch (`sub != winningSub`) -> returns 0
- Winner: `amountWei = (poolWei * entryBurn) / totalBurn` -- standard pro-rata
- Rounding: integer division rounds down (player gets <= fair share, total distributed <= poolWei)

**NatSpec Accuracy:** Accurate. Documents pro-rata calculation and winner verification.

**Gas Flags:** None. Clean view calculation.

**Verdict:** CORRECT

---

### `_decClaimable(LastDecClaimRound storage round, address player, uint24 lvl)` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function _decClaimable(LastDecClaimRound storage round, address player, uint24 lvl) internal view returns (uint256 amountWei, bool winner)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | `round` (LastDecClaimRound storage): claim round reference; `player` (address): address to check; `lvl` (uint24): level number |
| **Returns** | `amountWei` (uint256): claimable amount; `winner` (bool): true if winner |

**State Reads:** `round.totalBurn`, `round.poolWei`, `decBurn[lvl][player]` (DecEntry: claimed, burn, bucket, subBucket), `decBucketOffsetPacked[lvl]`

**State Writes:** None (view function).

**Callers:** `decClaimable` (external view)

**Callees:** `_decClaimableFromEntry`

**ETH Flow:** None (view function).

**Invariants:**
- `totalBurn == 0` -> (0, false)
- `e.claimed != 0` -> (0, false) -- already claimed
- `amountWei == 0` from `_decClaimableFromEntry` -> winner = false
- `amountWei > 0` -> winner = true

**NatSpec Accuracy:** Accurate. Documents internal view helper role.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_decUpdateSubbucket(uint24 lvl, uint8 denom, uint8 sub, uint192 delta)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _decUpdateSubbucket(uint24 lvl, uint8 denom, uint8 sub, uint192 delta) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level; `denom` (uint8): denominator bucket; `sub` (uint8): subbucket index; `delta` (uint192): burn amount to add |
| **Returns** | none |

**State Reads:** `decBucketBurnTotal[lvl][denom][sub]` (implicit in +=)

**State Writes:** `decBucketBurnTotal[lvl][denom][sub] += uint256(delta)`

**Callers:** `recordDecBurn` (new burn delta, migration carry-over)

**Callees:** None.

**ETH Flow:** None. Burn accounting only.

**Invariants:**
- `delta == 0` or `denom == 0` -> returns early (no-op)
- Arithmetic: checked addition (Solidity 0.8.34 default), reverts on overflow
- `decBucketBurnTotal` is `uint256`, `delta` is `uint192` -- overflow would require existing total near uint256.max, economically impossible

**NatSpec Accuracy:** Accurate.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_decRemoveSubbucket(uint24 lvl, uint8 denom, uint8 sub, uint192 delta)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _decRemoveSubbucket(uint24 lvl, uint8 denom, uint8 sub, uint192 delta) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level; `denom` (uint8): denominator bucket; `sub` (uint8): subbucket index; `delta` (uint192): burn amount to remove |
| **Returns** | none |

**State Reads:** `decBucketBurnTotal[lvl][denom][sub]`

**State Writes:** `decBucketBurnTotal[lvl][denom][sub] = slotTotal - uint256(delta)`

**Callers:** `recordDecBurn` (bucket migration -- removes from old subbucket)

**Callees:** None.

**ETH Flow:** None. Burn accounting only.

**Invariants:**
- `delta == 0` or `denom == 0` -> returns early (no-op)
- Underflow check: `slotTotal < uint256(delta)` -> reverts with `E()` -- prevents negative aggregate
- Safe subtraction after check

**NatSpec Accuracy:** Accurate. Documents removal with underflow protection.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_decSubbucketFor(address player, uint24 lvl, uint8 bucket)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _decSubbucketFor(address player, uint24 lvl, uint8 bucket) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `player` (address): player address; `lvl` (uint24): level; `bucket` (uint8): denominator |
| **Returns** | subbucket index (uint8), range 0 to bucket-1 |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `recordDecBurn` (first burn assignment, migration reassignment)

**Callees:** None.

**ETH Flow:** None.

**Invariants:**
- `bucket == 0` -> returns 0 (guard against division by zero)
- Hash: `keccak256(abi.encodePacked(player, lvl, bucket))` -- deterministic, consistent across calls
- Result: `hash % bucket` gives uniform distribution over [0, bucket-1]
- Same player+lvl+bucket always gets same subbucket -- essential for claim validation

**NatSpec Accuracy:** Accurate. Documents deterministic assignment from hash.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_awardDecimatorLootbox(address winner, uint256 amount, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardDecimatorLootbox(address winner, uint256 amount, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): lootbox recipient; `amount` (uint256): lootbox portion in wei; `rngWord` (uint256): VRF random word |
| **Returns** | none |

**State Reads:** `LOOTBOX_CLAIM_THRESHOLD` (constant = 5 ether)

**State Writes:** `whalePassClaims[winner]` (via `_queueWhalePassClaimCore` if amount > threshold), `claimableWinnings[winner]` (remainder via `_queueWhalePassClaimCore`), `claimablePool` (remainder via `_queueWhalePassClaimCore`), lootbox module storage (via delegatecall if amount <= threshold)

**Callers:** `_creditDecJackpotClaimCore`

**Callees:**
- `amount > LOOTBOX_CLAIM_THRESHOLD` (5 ETH): `_queueWhalePassClaimCore` (converts to whale pass half-passes, credits remainder)
- `amount <= LOOTBOX_CLAIM_THRESHOLD`: delegatecall to `GAME_LOOTBOX_MODULE.resolveLootboxDirect(winner, amount, rngWord)`

**ETH Flow:**
- Large amounts (> 5 ETH): converted to whale pass claims (half-passes at 2.175 ETH each), remainder -> `claimableWinnings[winner]`
- Small amounts (<= 5 ETH): resolved via LootboxModule delegatecall (lootbox rolls determine outcome)

**Invariants:**
- `winner == address(0)` or `amount == 0` -> returns early (no-op)
- Delegatecall failure propagated via `_revertDelegate`
- Threshold at 5 ETH prevents extremely large lootbox rolls

**NatSpec Accuracy:** Accurate. Documents routing logic between whale pass and lootbox resolution.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_revertDelegate(bytes memory reason)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _revertDelegate(bytes memory reason) private pure` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `reason` (bytes memory): revert data from failed delegatecall |
| **Returns** | never returns (always reverts) |

**State Reads:** None (pure function).

**State Writes:** None (pure function).

**Callers:** `_awardDecimatorLootbox` (delegatecall failure path)

**Callees:** None.

**ETH Flow:** None. Error propagation only.

**Invariants:**
- Empty reason (`reason.length == 0`): reverts with `E()` (generic error)
- Non-empty reason: assembly revert with original error data, preserving custom error selectors from delegatecall target
- `"memory-safe"` annotation: correct, only reads from `reason` memory pointer

**NatSpec Accuracy:** Accurate. Documents revert propagation purpose.

**Gas Flags:** None. Standard delegatecall error forwarding pattern.

**Verdict:** CORRECT

---

## Inherited Functions (from DegenerusGamePayoutUtils)

The following functions are defined in `DegenerusGamePayoutUtils` and used by DecimatorModule via inheritance. Audited for correctness in the context of DecimatorModule usage.

### `_creditClaimable(address beneficiary, uint256 weiAmount)` [internal, inherited]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditClaimable(address beneficiary, uint256 weiAmount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |

**State Writes:** `claimableWinnings[beneficiary] += weiAmount` (unchecked addition)

**Callers (in DecimatorModule):** `_processAutoRebuy` (reserved amount, no-ticket fallback), `_addClaimableEth` (non-auto-rebuy path)

**ETH Flow:** Adds to player's claimable balance. Does NOT modify `claimablePool` (caller responsible for pool accounting).

**Invariants:**
- `weiAmount == 0` -> returns early
- Unchecked addition: safe because total ETH supply < uint256.max
- Emits `PlayerCredited(beneficiary, beneficiary, weiAmount)`

**Verdict:** CORRECT (in DecimatorModule context)

---

### `_calcAutoRebuy(...)` [internal pure, inherited]

| Field | Value |
|-------|-------|
| **Signature** | `function _calcAutoRebuy(address beneficiary, uint256 weiAmount, uint256 entropy, AutoRebuyState memory state, uint24 currentLevel, uint16 bonusBps, uint16 bonusBpsAfKing) internal pure returns (AutoRebuyCalc memory c)` |
| **Visibility** | internal |
| **Mutability** | pure |

**Callers (in DecimatorModule):** `_processAutoRebuy`

**Returns:** `AutoRebuyCalc` with: `toFuture` (75% future, 25% next), `hasTickets`, `targetLevel`, `ticketCount` (with bonus), `ethSpent`, `reserved` (take-profit), `rebuyAmount`

**Invariants:**
- Take-profit: rounded down to nearest `takeProfit` multiple
- Level offset: 1-4 levels ahead (entropy-derived), +1 = next (25%), +2/+3/+4 = future (75%)
- Bonus: 130% (AUTO_REBUY_BONUS_BPS) or 145% (AFKING_AUTO_REBUY_BONUS_BPS)
- `ticketCount` capped at `uint32.max`

**Verdict:** CORRECT (in DecimatorModule context)

---

### `_queueWhalePassClaimCore(address winner, uint256 amount)` [internal, inherited]

| Field | Value |
|-------|-------|
| **Signature** | `function _queueWhalePassClaimCore(address winner, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |

**State Writes:** `whalePassClaims[winner] += fullHalfPasses`, `claimableWinnings[winner] += remainder`, `claimablePool += remainder`

**Callers (in DecimatorModule):** `_awardDecimatorLootbox` (for amounts > 5 ETH)

**ETH Flow:** Converts ETH to whale pass half-passes (2.175 ETH each), remainder credited to claimable. `claimablePool` incremented by remainder to maintain solvency invariant.

**Verdict:** CORRECT (in DecimatorModule context)

---

## Decimator Mechanics Summary

### Bucket/Subbucket System

- Player's denominator (bucket) is chosen implicitly: the first burn sets it, and only strictly lower denominators can upgrade it
- Valid denominators: 2-12 inclusive (11 total)
- Subbucket deterministically assigned: `keccak256(player, lvl, bucket) % bucket` ensures consistent, verifiable assignment
- Better bucket (lower denom) triggers migration: old aggregate decremented via `_decRemoveSubbucket`, new subbucket assigned via `_decSubbucketFor`, existing burn carried over to new aggregate via `_decUpdateSubbucket`
- Same or worse bucket: new bucket parameter ignored, existing bucket retained
- Lower denominator = fewer subbuckets = higher chance of winning subbucket match, but also more competitors per subbucket

### Winning Subbucket Selection

- Winning subbucket per denom selected via VRF: `keccak256(rngWord, denom) % denom`
- All 11 denoms (2-12) processed in single `runDecimatorJackpot` call
- Packed into uint64 (4 bits per denom, 44 bits total) for gas-efficient storage
- Winning subbuckets stored per-level in `decBucketOffsetPacked[lvl]`

### Pro-Rata Claims

- Pool distributed proportionally: `(poolWei * playerBurn) / totalBurn`
- `totalBurn` = sum of burns across all winning subbuckets (all denoms)
- Only winners (player's subbucket matches winning subbucket for their denom) can claim
- Claims expire when next decimator runs (lastDecClaimRound overwritten with new level)
- Double-claim prevented by `claimed` flag in DecEntry
- Rounding: integer division rounds down, so total distributed <= poolWei (dust remains)

### Multiplier Cap

- Burns multiplied by `multBps` (from coin contract) up to DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT = 200,000 BURNIE (200 mint equivalents)
- Below cap: full multiplier applied (`baseAmount * multBps / BPS_DENOMINATOR`)
- At or beyond cap: additional burns counted at 1x (`baseAmount` only)
- Partial split: when burn partially crosses cap, `maxMultBase` portion gets multiplier, remainder at 1x
- Rounding in partial split is conservative (rounds down) -- player receives <= cap worth of multiplied burns

### Auto-Rebuy Integration

- Decimator-specific auto-rebuy opt-out via `decimatorAutoRebuyDisabled[player]`
- When enabled, ETH winnings converted to tickets at 130% bonus (145% for afKing mode)
- Target level: 1-4 levels ahead (entropy-derived, 75% future / 25% next)
- Take-profit reserving honored: portion reserved before ticket conversion
- If no tickets affordable from remaining amount, full amount falls back to `_creditClaimable`

### Claim Distribution Modes

- **GameOver mode (`gameOver == true`):** 100% ETH credited via `_addClaimableEth`
- **Normal mode:** 50/50 split -- half ETH (via `_addClaimableEth`), half lootbox (via `_awardDecimatorLootbox`)
- Lootbox portion: <= 5 ETH resolved via LootboxModule delegatecall, > 5 ETH converted to whale pass half-passes

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| Batch credit (gameover) | claimablePool (pre-reserved) | claimableWinnings[account] or auto-rebuy tickets | creditDecJackpotClaimBatch (gameOver=true) | _addClaimableEth |
| Batch credit (normal ETH half) | claimablePool (pre-reserved) | claimableWinnings[account] or auto-rebuy tickets | creditDecJackpotClaimBatch (gameOver=false) | _creditDecJackpotClaimCore -> _addClaimableEth |
| Batch credit (normal lootbox half) | claimablePool (decremented) | futurePrizePool (aggregate) + lootbox resolution | creditDecJackpotClaimBatch (gameOver=false) | _creditDecJackpotClaimCore -> _awardDecimatorLootbox |
| Single credit (gameover) | claimablePool (pre-reserved) | claimableWinnings[account] or auto-rebuy tickets | creditDecJackpotClaim (gameOver=true) | _addClaimableEth |
| Single credit (normal ETH half) | claimablePool (pre-reserved) | claimableWinnings[account] or auto-rebuy tickets | creditDecJackpotClaim (gameOver=false) | _creditDecJackpotClaimCore -> _addClaimableEth |
| Single credit (normal lootbox half) | claimablePool (decremented) | futurePrizePool + lootbox resolution | creditDecJackpotClaim (gameOver=false) | _creditDecJackpotClaimCore -> _awardDecimatorLootbox |
| Self-claim (gameover) | lastDecClaimRound.poolWei (pro-rata share) | claimableWinnings[msg.sender] or auto-rebuy tickets | claimDecimatorJackpot (gameOver=true) | _addClaimableEth |
| Self-claim (normal ETH half) | lastDecClaimRound.poolWei (pro-rata share, half) | claimableWinnings[msg.sender] or auto-rebuy tickets | claimDecimatorJackpot (gameOver=false) | _creditDecJackpotClaimCore -> _addClaimableEth |
| Self-claim (normal lootbox half) | lastDecClaimRound.poolWei (pro-rata share, half) | futurePrizePool + lootbox resolution | claimDecimatorJackpot (gameOver=false) | _creditDecJackpotClaimCore -> _awardDecimatorLootbox |
| Auto-rebuy ticket conversion | claimablePool (decremented by ethSpent) | nextPrizePool (25%) or futurePrizePool (75%) + tickets queued | _processAutoRebuy (auto-rebuy enabled) | _processAutoRebuy -> _queueTickets |
| Auto-rebuy take-profit | claimablePool (pre-reserved) | claimableWinnings[beneficiary] | _processAutoRebuy (takeProfit > 0) | _creditClaimable |
| Lootbox large amount routing | claimablePool (via _creditDecJackpotClaimCore) | whalePassClaims[winner] + claimableWinnings remainder | _awardDecimatorLootbox (amount > 5 ETH) | _queueWhalePassClaimCore |
| Lootbox small amount routing | claimablePool (via _creditDecJackpotClaimCore) | LootboxModule resolution (tickets, BURNIE, ETH outcomes) | _awardDecimatorLootbox (amount <= 5 ETH) | delegatecall resolveLootboxDirect |
| Jackpot snapshot hold | caller pool allocation | lastDecClaimRound.poolWei (held for claims) | runDecimatorJackpot (has winners) | runDecimatorJackpot |
| Jackpot return (no winners) | poolWei passed in | returned to caller (returnAmountWei) | runDecimatorJackpot (totalBurn==0) | runDecimatorJackpot |

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 1 | Rounding in _decEffectiveAmount partial split (conservative, no impact) |
| CORRECT | 24 | All 24 functions verified correct (7 external + 14 internal/private in contract + 3 inherited from PayoutUtils) |

**Overall Assessment:** All 24 functions audited are CORRECT. The decimator module implements a well-designed bucket/subbucket system with deterministic VRF-based winner selection, pro-rata claim distribution, and proper access control. The 50/50 ETH/lootbox split in normal mode and 100% ETH in gameover mode are correctly implemented. Auto-rebuy integration with decimator-specific opt-out provides flexibility. No bugs, no security concerns.
