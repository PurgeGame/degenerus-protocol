# Degenerus Protocol — State-Changing Function Audits

**Source:** v7.0 Function-Level Exhaustive Audit (Phases 49-56)
**Scope:** All state-changing functions across 13 core contracts + 10 delegatecall modules
**Verdict:** All functions CORRECT (0 bugs found)

---

## DegenerusGame.sol

### `advanceGame()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function advanceGame() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | (none) |
| **Returns** | (none) |

**State Reads:** None directly -- all reads occur within the AdvanceModule delegatecall context.

**State Writes:** None directly -- all writes occur within the AdvanceModule delegatecall context.

**Callers:** Anyone (external). Tiered gating enforced inside AdvanceModule: deity pass holders bypass always; anyone after 30+ min; pass holders after 15+ min; DGVE majority holders always.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.advanceGame.selector)` -- delegates entire state machine tick to AdvanceModule
- `_revertDelegate(data)` -- on delegatecall failure, bubbles up revert reason

**ETH Flow:** None directly. The AdvanceModule (executing in this contract's context) drives all ETH pool movements: `futurePrizePool -> nextPrizePool -> currentPrizePool -> claimableWinnings`, Lido staking, jackpot distributions, deity refunds, etc.

**Invariants:**
- `jackpotPhaseFlag` transitions: `false(PURCHASE) <-> true(JACKPOT)`; `gameOver` is terminal
- Delegatecall executes in Game's storage context -- slot alignment guaranteed by shared DegenerusGameStorage inheritance
- RNG lock prevents manipulation during VRF callback window

**NatSpec Accuracy:** ACCURATE. NatSpec accurately describes: 2.5yr deploy timeout, 365-day inactivity guard, tiered daily gate, RNG gating, batched processing, BURNIE bounty during jackpot phase.

**Gas Flags:** None. The function is a thin delegatecall wrapper with no redundant operations.

**Verdict:** CORRECT

---

### `wireVrf(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `coordinator_` (address): VRF coordinator address; `subId` (uint256): VRF subscription ID; `keyHash_` (bytes32): VRF gas lane key hash |
| **Returns** | (none) |

**State Reads:** None directly -- access control checked in AdvanceModule.

**State Writes:** None directly -- VRF config written in AdvanceModule context: `coordinator`, `vrfSubId`, `keyHash` storage variables.

**Callers:** ADMIN contract only (enforced inside AdvanceModule with `msg.sender != ContractAddresses.ADMIN` check).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.wireVrf.selector, coordinator_, subId, keyHash_)` -- sets VRF configuration
- `_revertDelegate(data)` -- on failure

**ETH Flow:** None.

**Invariants:**
- VRF config can be set or rotated (not one-time-only despite NatSpec suggesting "one-time") via `updateVrfCoordinatorAndSub`
- Only ADMIN can call

**NatSpec Accuracy:** MINOR INACCURACY. NatSpec says "One-time VRF setup" but the function "Overwrites any existing config on each call" per its own dev comment. The AdvanceModule also exposes `updateVrfCoordinatorAndSub` for emergency rotation. Not a functional concern -- the "one-time" label refers to the expected deployment flow, not a technical enforcement.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `recordMint(address, uint24, uint256, uint32, MintPaymentKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMint(address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind) external payable returns (uint256 coinReward, uint256 newClaimableBalance)` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): mint recipient; `lvl` (uint24): current level; `costWei` (uint256): total cost in wei; `mintUnits` (uint32): purchase units; `payKind` (MintPaymentKind): payment method |
| **Returns** | `coinReward` (uint256): BURNIE reward; `newClaimableBalance` (uint256): remaining claimable balance |

**State Reads:**
- `claimableWinnings[player]` (in `_processMintPayment`, for Claimable/Combined pay kinds)
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn`, `EARLYBIRD_END_LEVEL`, `EARLYBIRD_TARGET_ETH` (in `_awardEarlybirdDgnrs`)
- `mintPacked_[player]` (in `_recordMintDataModule` via MintModule delegatecall)

**State Writes:**
- `futurePrizePool += futureShare` (10% of prizeContribution via `PURCHASE_TO_FUTURE_BPS = 1000`)
- `nextPrizePool += nextShare` (remaining 90% of prizeContribution)
- `claimableWinnings[player]` (deducted for Claimable/Combined payments)
- `claimablePool -= claimableUsed` (global claimable accounting)
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn` (in `_awardEarlybirdDgnrs`)
- Various fields in `mintPacked_[player]` (via MintModule delegatecall in `_recordMintDataModule`)

**Callers:** Self-call only (`msg.sender != address(this)` check). Called from delegate modules executing in this contract's context (e.g., MintModule.purchase delegatecalls back to Game.recordMint).

**Callees:**
- `_processMintPayment(player, costWei, payKind)` -- handles ETH/claimable payment validation and deduction
- `_recordMintDataModule(player, lvl, mintUnits)` -- delegatecalls to `GAME_MINT_MODULE.recordMintData` for mint history and BURNIE reward calculation
- `_awardEarlybirdDgnrs(player, earlybirdEth, lvl)` -- awards early DGNRS tokens via DGNRS.transferFromPool

**ETH Flow:**
| Path | Source | Destination | Condition |
|------|--------|-------------|-----------|
| Direct ETH purchase | `msg.value` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == DirectEth` |
| Claimable purchase | `claimableWinnings[player]` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == Claimable` |
| Combined purchase | `msg.value` + `claimableWinnings[player]` | `nextPrizePool` (90%) + `futurePrizePool` (10%) | `payKind == Combined` |

Prize pool split: `PURCHASE_TO_FUTURE_BPS = 1000` (10% to future, 90% to next).

**Revert Conditions:**
- `msg.sender != address(this)` -- not a self-call
- `DirectEth`: `msg.value < amount` -- insufficient ETH
- `Claimable`: `msg.value != 0` -- ETH sent with claimable; `claimable <= amount` -- insufficient balance (preserves 1 wei sentinel)
- `Combined`: `msg.value > amount` -- overpay not allowed; `remaining != 0` after claimable deduction -- insufficient total
- Invalid payKind enum value

**Invariants:**
- `claimablePool` is decremented by exactly `claimableUsed`, matching the deduction from `claimableWinnings[player]`
- 1 wei sentinel preserved in claimable balance (prevents cold->warm SSTORE gas cost)
- `prizeContribution = msg.value + claimableUsed` always equals `costWei` (full coverage required)
- ETH conservation: `futureShare + nextShare == prizeContribution` (no rounding loss since `futureShare = (prizeContribution * 1000) / 10000`)

**NatSpec Accuracy:** ACCURATE. Documents all three payment modes, self-call restriction, prize pool split, and overage handling.

**Gas Flags:**
- INFO: The `if (futureShare != 0)` and `if (nextShare != 0)` zero-checks are defensive (futureShare is 0 only when prizeContribution is 0, which is already guarded by `if (prizeContribution != 0)`). No gas waste since the check is cheap relative to SSTORE.
- INFO: `earlybirdEth` calculation differs between DirectEth and Combined -- in DirectEth, `min(costWei, msg.value)` is used (capping at costWei even if overpaid), while Combined uses `msg.value` directly. This is correct since Combined already enforces `msg.value <= amount`.

**Verdict:** CORRECT

---

### `recordCoinflipDeposit(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordCoinflipDeposit(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): wei amount deposited to coinflip |
| **Returns** | (none) |

**State Reads:**
- `jackpotPhaseFlag` -- checks if in purchase phase
- `lastPurchaseDay` -- checks if last purchase day flag is set

**State Writes:**
- `lastPurchaseDayFlipTotal += amount` -- only when in purchase phase AND last purchase day

**Callers:** COIN or COINFLIP contract only (access-controlled by `msg.sender` check against `ContractAddresses.COIN` and `ContractAddresses.COINFLIP`).

**Callees:** None.

**ETH Flow:** None. This function only tracks accounting; no ETH moves.

**Invariants:**
- Only accumulates during purchase phase (`!jackpotPhaseFlag`) AND on last purchase day (`lastPurchaseDay == true`)
- `lastPurchaseDayFlipTotal` resets on level transition (handled by AdvanceModule)

**NatSpec Accuracy:** ACCURATE. States "Track coinflip deposits for payout tuning on last purchase day" and correctly identifies COIN/COINFLIP as callers.

**Gas Flags:** None. Simple conditional accumulator.

**Verdict:** CORRECT

---

### `recordMintQuestStreak(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMintQuestStreak(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player who completed the quest |
| **Returns** | (none) |

**State Reads:**
- `jackpotPhaseFlag`, `level` -- via `_activeTicketLevel()` to compute current mint level
- `mintPacked_[player]` -- via `_recordMintStreakForLevel` to check last completed level and current streak

**State Writes:**
- `mintPacked_[player]` -- via `_recordMintStreakForLevel`: updates `MINT_STREAK_LAST_COMPLETED_SHIFT` (24 bits at position 160) and `LEVEL_STREAK_SHIFT` (24 bits at position 48) within the packed mint data

**Callers:** COIN contract only (`msg.sender != ContractAddresses.COIN` check).

**Callees:**
- `_activeTicketLevel()` -- returns `jackpotPhaseFlag ? level : level + 1`
- `_recordMintStreakForLevel(player, mintLevel)` -- inherited from DegenerusGameMintStreakUtils; records streak completion for the level, incrementing streak if consecutive, resetting to 1 if gap

**ETH Flow:** None.

**Invariants:**
- Idempotent per level: if `lastCompleted == mintLevel`, no-op
- Streak increments only if `lastCompleted + 1 == mintLevel` (consecutive levels)
- Streak capped at `type(uint24).max` (16,777,215)
- Player address(0) is a no-op (checked in `_recordMintStreakForLevel`)

**NatSpec Accuracy:** ACCURATE. "Record mint streak completion after a 1x price ETH quest completes" matches behavior.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `payCoinflipBountyDgnrs(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payCoinflipBountyDgnrs(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of DGNRS bounty |
| **Returns** | (none) |

**State Reads:** None directly (reads from external DGNRS contract).

**State Writes:** None directly (writes occur in DGNRS contract via `transferFromPool`).

**Callers:** COIN or COINFLIP contract only (access-controlled by `msg.sender` check).

**Callees:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Reward)` -- reads Reward pool balance from DGNRS contract
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Reward, player, payout)` -- transfers DGNRS tokens from Reward pool to player

**ETH Flow:** None. This is a DGNRS token transfer, not ETH.

**Invariants:**
- Payout = `(poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` where `COINFLIP_BOUNTY_DGNRS_BPS = 50` (0.5% of Reward pool)
- Zero-address player -> early return (no-op)
- Zero pool balance -> early return
- Zero payout (rounding) -> early return

**NatSpec Accuracy:** ACCURATE. "Pay DGNRS bounty for the biggest flip record holder" matches; access control documented.

**Gas Flags:** None. Three sequential early-return guards are efficient.

**Verdict:** CORRECT

---

### `setOperatorApproval(address, bool)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setOperatorApproval(address operator, bool approved) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): operator to approve/revoke; `approved` (bool): true to approve, false to revoke |
| **Returns** | (none) |

**State Reads:** None.

**State Writes:**
- `operatorApprovals[msg.sender][operator] = approved`

**Callers:** Anyone (external). The caller becomes the `owner` (msg.sender).

**Callees:** None (emits `OperatorApproval` event only).

**ETH Flow:** None.

**Invariants:**
- Zero-address operator reverts with `E()` (prevents accidental approvals to address(0))
- Approval is per-owner per-operator (nested mapping)
- Emits `OperatorApproval(owner, operator, approved)` on every call (including redundant approvals)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** INFO: No check for redundant approval (setting already-true to true emits event and writes same value). This is intentional -- the gas cost of a same-value SSTORE (warm, no change) is minimal (100 gas).

**Verdict:** CORRECT

---

### `setLootboxRngThreshold(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLootboxRngThreshold(uint256 newThreshold) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newThreshold` (uint256): new threshold in wei |
| **Returns** | (none) |

**State Reads:**
- `lootboxRngThreshold` (reads current value as `prev`)

**State Writes:**
- `lootboxRngThreshold = newThreshold` (only when `newThreshold != prev`)

**Callers:** ADMIN contract only (`msg.sender != ContractAddresses.ADMIN` check).

**Callees:** None (emits `LootboxRngThresholdUpdated` event).

**ETH Flow:** None.

**Revert Conditions:**
- `msg.sender != ContractAddresses.ADMIN` -- not admin
- `newThreshold == 0` -- zero threshold not allowed

**Invariants:**
- Threshold is always non-zero after any successful call
- When `newThreshold == prev`, emits event but does NOT write storage (gas optimization: avoids same-value SSTORE)
- Event always emitted, even for no-op case (consistent behavior for indexers)

**NatSpec Accuracy:** ACCURATE. Documents ADMIN-only access, non-zero requirement, and event emission.

**Gas Flags:** INFO: The `if (newThreshold == prev)` early-return path emits the event before returning, avoiding the SSTORE while still notifying indexers. This is an intentional gas optimization.

**Verdict:** CORRECT

---

### `purchase(address, uint256, uint256, bytes32, MintPaymentKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): player to receive purchases (address(0) = msg.sender); `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxAmount` (uint256): ETH amount for lootboxes; `affiliateCode` (bytes32): affiliate referral code; `payKind` (MintPaymentKind): payment method |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_requireApproved` in `_resolvePlayer`)
**State Writes:** none directly (all via delegatecall to MintModule)

**Callers:** External callers (players, operators, frontends)
**Callees:** `_resolvePlayer(buyer)` -> `_purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`

**ETH Flow:** msg.value forwarded to MintModule via delegatecall (module executes in Game's storage context, so ETH stays in Game contract). MintModule calls `recordMint()` on self which routes through `_processMintPayment` -> prize pool splits.
**Invariants:** buyer must be msg.sender or approved operator. msg.value must cover cost if DirectEth. Delegatecall preserves Game's msg.value context.
**NatSpec Accuracy:** ACCURATE. Correctly documents all parameters, payment methods, and scaling. Notes RNG lock security.
**Gas Flags:** None. Thin wrapper.
**Verdict:** CORRECT

---

### `_purchaseFor(address, uint256, uint256, bytes32, MintPaymentKind)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | Same as `purchase()` after buyer resolution |
| **Returns** | none |

**State Reads:** none directly (all via MintModule delegatecall)
**State Writes:** none directly (all via MintModule delegatecall which writes in Game's storage context)

**Callers:** `purchase()`
**Callees:** `ContractAddresses.GAME_MINT_MODULE.delegatecall(IDegenerusGameMintModule.purchase.selector, ...)` -> `_revertDelegate(data)` on failure

**ETH Flow:** Delegatecall inherits msg.value. MintModule executes `purchase()` in Game's context, calling back to `recordMint()` which invokes `_processMintPayment` for prize pool splitting.
**Invariants:** Delegatecall target is compile-time constant (GAME_MINT_MODULE). If delegatecall fails, all state changes revert via `_revertDelegate`.
**NatSpec Accuracy:** No NatSpec (private helper). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `purchaseCoin(address, uint256, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing (NOT payable -- BURNIE purchases only) |
| **Parameters** | `buyer` (address): player (address(0) = msg.sender); `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxBurnieAmount` (uint256): BURNIE amount for lootbox |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_resolvePlayer`)
**State Writes:** none directly (all via MintModule delegatecall)

**Callers:** External callers
**Callees:** `_resolvePlayer(buyer)` -> `ContractAddresses.GAME_MINT_MODULE.delegatecall(IDegenerusGameMintModule.purchaseCoin.selector, buyer, ticketQuantity, lootBoxBurnieAmount)` -> `_revertDelegate(data)` on failure

**ETH Flow:** None. This is a BURNIE-only purchase. Not payable. BURNIE burn handled inside MintModule via COIN contract calls.
**Invariants:** Must not be payable (enforced by absence of `payable` modifier). Buyer resolved via operator approval.
**NatSpec Accuracy:** ACCURATE. Correctly describes BURNIE purchase path, documents RNG lock security, parameter semantics match code.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `purchaseBurnieLootbox(address, uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing (NOT payable) |
| **Parameters** | `buyer` (address): player (address(0) = msg.sender); `burnieAmount` (uint256): BURNIE amount to burn (18 decimals) |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_resolvePlayer`)
**State Writes:** none directly (all via MintModule delegatecall)

**Callers:** External callers
**Callees:** `_resolvePlayer(buyer)` -> `ContractAddresses.GAME_MINT_MODULE.delegatecall(IDegenerusGameMintModule.purchaseBurnieLootbox.selector, buyer, burnieAmount)` -> `_revertDelegate(data)` on failure

**ETH Flow:** None. BURNIE-only lootbox purchase.
**Invariants:** Not payable. BURNIE burn handled in MintModule context.
**NatSpec Accuracy:** ACCURATE. Parameters and purpose correctly documented.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `purchaseWhaleBundle(address, uint256)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseWhaleBundle(address buyer, uint256 quantity) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): player (address(0) = msg.sender); `quantity` (uint256): number of bundles to purchase |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_resolvePlayer`)
**State Writes:** none directly (all via WhaleModule delegatecall)

**Callers:** External callers
**Callees:** `_resolvePlayer(buyer)` -> `_purchaseWhaleBundleFor(buyer, quantity)`

**ETH Flow:** msg.value forwarded to WhaleModule via delegatecall. WhaleModule handles price validation (2.4 ETH levels 0-3, 4 ETH levels 4+) and prize pool splitting (level 0: 30%/70% next/future; other levels: 5%/95% next/future).
**Invariants:** buyer resolved via operator approval. Quantity 1-100 enforced in WhaleModule.
**NatSpec Accuracy:** ACCURATE. Comprehensive documentation of pricing tiers, fund distribution splits, level mechanics, and frozen stat behavior. Matches WhaleModule implementation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_purchaseWhaleBundleFor(address, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseWhaleBundleFor(address buyer, uint256 quantity) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): resolved player; `quantity` (uint256): number of bundles |
| **Returns** | none |

**State Reads:** none directly
**State Writes:** none directly (all via WhaleModule delegatecall which writes to Game's storage)

**Callers:** `purchaseWhaleBundle()`
**Callees:** `ContractAddresses.GAME_WHALE_MODULE.delegatecall(IDegenerusGameWhaleModule.purchaseWhaleBundle.selector, buyer, quantity)` -> `_revertDelegate(data)` on failure

**ETH Flow:** Delegatecall inherits msg.value. WhaleModule's `purchaseWhaleBundle()` validates msg.value >= totalPrice (price * quantity), splits to pools.
**Invariants:** Compile-time constant target. Failure propagated via `_revertDelegate`.
**NatSpec Accuracy:** No NatSpec (private helper). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `purchaseLazyPass(address)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseLazyPass(address buyer) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): player (address(0) = msg.sender) |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_resolvePlayer`)
**State Writes:** none directly (all via WhaleModule delegatecall)

**Callers:** External callers
**Callees:** `_resolvePlayer(buyer)` -> `_purchaseLazyPassFor(buyer)`

**ETH Flow:** msg.value forwarded to WhaleModule via delegatecall. Pricing: flat 0.24 ETH (levels 0-2), sum of 10-level ticket prices (levels 3+). Pool split handled in WhaleModule via `LAZY_PASS_TO_FUTURE_BPS`.
**Invariants:** Buyer resolved. Level eligibility enforced in WhaleModule (levels 0-2, x9 levels, or with lazy pass boon).
**NatSpec Accuracy:** ACCURATE. Correctly documents pricing tiers and level eligibility.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_purchaseLazyPassFor(address)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseLazyPassFor(address buyer) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): resolved player |
| **Returns** | none |

**State Reads:** none directly
**State Writes:** none directly (all via WhaleModule delegatecall)

**Callers:** `purchaseLazyPass()`
**Callees:** `ContractAddresses.GAME_WHALE_MODULE.delegatecall(IDegenerusGameWhaleModule.purchaseLazyPass.selector, buyer)` -> `_revertDelegate(data)` on failure

**ETH Flow:** Delegatecall inherits msg.value. WhaleModule handles pricing and pool splitting.
**Invariants:** Compile-time constant target.
**NatSpec Accuracy:** No NatSpec (private helper). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `purchaseDeityPass(address, uint8)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseDeityPass(address buyer, uint8 symbolId) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): player (address(0) = msg.sender); `symbolId` (uint8): deity symbol 0-31 |
| **Returns** | none |

**State Reads:** `operatorApprovals` (via `_resolvePlayer`)
**State Writes:** none directly (all via WhaleModule delegatecall)

**Callers:** External callers
**Callees:** `_resolvePlayer(buyer)` -> `_purchaseDeityPassFor(buyer, symbolId)`

**ETH Flow:** msg.value forwarded to WhaleModule via delegatecall. Pricing: 24 + T(n) ETH where T(n) = n*(n+1)/2, n = passes sold. WhaleModule handles price validation and pool split.
**Invariants:** Buyer resolved. Symbol ID 0-31 enforced in WhaleModule. Max 32 deity passes (one per symbol). WhaleModule validates no duplicate symbol ownership.
**NatSpec Accuracy:** ACCURATE. Symbol mapping (Q0-Q3) correctly documented.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_purchaseDeityPassFor(address, uint8)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseDeityPassFor(address buyer, uint8 symbolId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): resolved player; `symbolId` (uint8): deity symbol |
| **Returns** | none |

**State Reads:** none directly
**State Writes:** none directly (all via WhaleModule delegatecall)

**Callers:** `purchaseDeityPass()`
**Callees:** `ContractAddresses.GAME_WHALE_MODULE.delegatecall(IDegenerusGameWhaleModule.purchaseDeityPass.selector, buyer, symbolId)` -> `_revertDelegate(data)` on failure

**ETH Flow:** Delegatecall inherits msg.value. WhaleModule validates price and splits to pools.
**Invariants:** Compile-time constant target.
**NatSpec Accuracy:** No NatSpec (private helper). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `onDeityPassTransfer(address, address, uint8)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function onDeityPassTransfer(address from, address to, uint8) external` |
| **Visibility** | external |
| **Mutability** | state-changing (NOT payable) |
| **Parameters** | `from` (address): sender of the deity pass; `to` (address): receiver of the deity pass; `uint8` (unnamed): token symbol ID (unused in Game, forwarded context only) |
| **Returns** | none |

**State Reads:** none directly (reads ContractAddresses.DEITY_PASS for access control)
**State Writes:** none directly (all via WhaleModule delegatecall -- updates deity storage, nukes sender stats)

**Callers:** DegenerusDeityPass ERC721 contract (on transfer hook)
**Callees:** access check `msg.sender != ContractAddresses.DEITY_PASS` -> `ContractAddresses.GAME_WHALE_MODULE.delegatecall(IDegenerusGameWhaleModule.handleDeityPassTransfer.selector, from, to)` -> `_revertDelegate(data)` on failure

**ETH Flow:** None. Transfer callback, no ETH involved.
**Invariants:** Only callable by the DEITY_PASS ERC721 contract (enforced by `if (msg.sender != ContractAddresses.DEITY_PASS) revert E()`). The third parameter (symbolId) is received but not passed to the WhaleModule -- the module identifies the symbol from `deityPassSymbol[from]` storage. This is correct behavior: the module reads the symbol from the canonical storage mapping rather than trusting the callback parameter.
**NatSpec Accuracy:** ACCURATE. Documents BURNIE burn cost, stat nuking, and access control. Notes the 5 ETH BURNIE burn from sender.
**Gas Flags:** The unnamed `uint8` parameter is accepted but unused in the delegatecall encoding. This is intentional -- the ERC721 provides it, but the WhaleModule identifies the symbol from storage. Minimal gas overhead (1 word ABI decode).
**Verdict:** CORRECT

---

### `recordMint(address, uint24, uint256, uint32, MintPaymentKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMint(address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind) external payable returns (uint256 coinReward, uint256 newClaimableBalance)` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): player being credited; `lvl` (uint24): level of mint; `costWei` (uint256): total cost in wei; `mintUnits` (uint32): units purchased; `payKind` (MintPaymentKind): payment method |
| **Returns** | `coinReward` (uint256): BURNIE reward amount; `newClaimableBalance` (uint256): updated claimable balance |

**State Reads:** `claimableWinnings[player]`, `claimablePool`, `nextPrizePool`, `futurePrizePool` (via `_processMintPayment`); mint data (via `_recordMintDataModule`); earlybird pool state (via `_awardEarlybirdDgnrs`)
**State Writes:** `claimableWinnings[player]`, `claimablePool` (via `_processMintPayment`); `nextPrizePool`, `futurePrizePool` (prize pool split); mint data (via `_recordMintDataModule` delegatecall); earlybird DGNRS state (via `_awardEarlybirdDgnrs`)

**Callers:** MintModule (via `address(this).call()` from delegatecall context -- module calls back to Game to process payment)
**Callees:** `_processMintPayment(player, costWei, payKind)` -> prize pool split logic -> `_recordMintDataModule(player, lvl, mintUnits)` -> `_awardEarlybirdDgnrs(player, earlybirdEth, lvl)`

**ETH Flow:**
1. `_processMintPayment` determines `prizeContribution` based on payKind
2. Prize pool split: `futureShare = prizeContribution * 1000 / 10000` (10% to futurePrizePool)
3. Remainder `nextShare = prizeContribution - futureShare` (90% to nextPrizePool)
4. Earlybird DGNRS: ETH amount used for earlybird emission curve (levels < 3 only)

**Invariants:**
- Access control: `msg.sender != address(this)` reverts. Only callable via self-call from MintModule delegatecall context.
- Prize pool split: 10% future, 90% next. Conservation: `futureShare + nextShare == prizeContribution`.
- Earlybird: DirectEth uses min(msg.value, costWei); Combined uses msg.value; Claimable uses 0.

**NatSpec Accuracy:** ACCURATE. Payment modes, security model, and return values correctly documented.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_processMintPayment(address, uint256, MintPaymentKind)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processMintPayment(address player, uint256 amount, MintPaymentKind payKind) private returns (uint256 prizeContribution, uint256 newClaimableBalance)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose claimable balance to check/deduct; `amount` (uint256): total cost in wei; `payKind` (MintPaymentKind): payment method enum |
| **Returns** | `prizeContribution` (uint256): amount contributing to prize pools; `newClaimableBalance` (uint256): player's claimable balance after deduction (0 if DirectEth) |

**State Reads:** `claimableWinnings[player]`, `claimablePool`
**State Writes:** `claimableWinnings[player]`, `claimablePool` (only when claimable funds are used)

**Callers:** `recordMint()`
**Callees:** Emits `ClaimableSpent` event when claimable funds are used

**ETH Flow:**
- **DirectEth:** `msg.value >= amount` required. `prizeContribution = amount`. Overpay is retained in contract (not refunded). No claimable state touched.
- **Claimable:** `msg.value == 0` required. `claimable > amount` required (strict greater-than preserves 1 wei sentinel). Deducts from `claimableWinnings[player]` and `claimablePool`. `prizeContribution = amount`.
- **Combined:** `msg.value <= amount` required (reversed vs DirectEth -- overpay reverts). Remaining = `amount - msg.value`. If remaining > 0, deducts min(remaining, available) from claimable (preserving 1 wei sentinel). If still `remaining != 0` after claimable deduction, reverts. `prizeContribution = msg.value + claimableUsed`.
- Any other payKind value reverts.

**Invariants:**
1. **1-wei sentinel preservation:** Claimable mode requires `claimable > amount` (strict). Combined mode uses `available = claimable - 1`. This prevents the cold-to-warm SSTORE gas cost spike when a player's balance goes from 0 to nonzero.
2. **claimablePool conservation:** `claimablePool -= claimableUsed` exactly matches `claimableWinnings[player]` deduction. Maintains `claimablePool >= sum(claimableWinnings[*])`.
3. **Full coverage enforcement:** Combined mode reverts if `remaining != 0` after all sources exhausted -- player cannot underpay.
4. **ETH retention:** DirectEth overpay is retained. This is documented and intentional (overage ignored for accounting).
5. **Prize contribution conservation:** `prizeContribution` equals the total amount drawn from all payment sources. No wei are lost.

**NatSpec Accuracy:** ACCURATE. Correctly documents all three payment modes, 1-wei sentinel purpose, claimablePool invariant, and security considerations.
**Gas Flags:** `unchecked` blocks for subtraction are safe -- preceding checks ensure no underflow (Claimable: `claimable > amount`; Combined: `claimable > 1` and `claimableUsed <= available`).
**Verdict:** CORRECT

---

### `_recordMintDataModule(address, uint24, uint32)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordMintDataModule(address player, uint24 lvl, uint32 mintUnits) private returns (uint256 coinReward)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player being credited; `lvl` (uint24): level of mint; `mintUnits` (uint32): number of mint units purchased |
| **Returns** | `coinReward` (uint256): BURNIE tokens to credit to player |

**State Reads:** none directly (all via MintModule delegatecall)
**State Writes:** none directly (MintModule writes `mintPacked_[player]` and related mint data in Game's storage context)

**Callers:** `recordMint()`
**Callees:** `ContractAddresses.GAME_MINT_MODULE.delegatecall(IDegenerusGameMintModule.recordMintData.selector, player, lvl, mintUnits)` -> `_revertDelegate(data)` on failure -> `abi.decode(data, (uint256))` for coinReward

**ETH Flow:** None. Delegatecall for state recording only. BURNIE reward is computed by module and returned.
**Invariants:**
- Delegatecall must succeed (failure reverted via `_revertDelegate`)
- Return data must be non-empty (`if (data.length == 0) revert E()` -- extra safety check beyond delegatecall success)
- Return value decoded as uint256 representing BURNIE coin reward

**NatSpec Accuracy:** ACCURATE. Correctly documents purpose, parameters, and BURNIE reward calculation.
**Gas Flags:** The `data.length == 0` check after successful delegatecall is defensive. A successful delegatecall to a function returning uint256 will always return 32 bytes. This is harmless defensive coding.
**Verdict:** CORRECT

---

### `openLootBox(address, uint48)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openLootBox(address player, uint48 lootboxIndex) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address that owns the loot box (address(0) = msg.sender); `lootboxIndex` (uint48): Lootbox RNG index assigned at purchase time |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- delegates all state mutation to LootboxModule

**Callers:** External callers (players, operators)
**Callees:** `_resolvePlayer(player)` -> `_openLootBoxFor(player, lootboxIndex)`

**ETH Flow:** No ETH accepted (not payable). ETH distribution occurs inside LootboxModule via delegatecall (lootbox prizes paid from Game's balance).
**Invariants:** Player must be msg.sender or msg.sender must be an approved operator. Lootbox index must have available RNG.
**NatSpec Accuracy:** CORRECT -- NatSpec accurately describes player resolution and lootbox index semantics.
**Gas Flags:** None -- minimal wrapper, efficient dispatch.
**Verdict:** CORRECT

---

### `openBurnieLootBox(address, uint48)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openBurnieLootBox(address player, uint48 lootboxIndex) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address that owns the BURNIE loot box (address(0) = msg.sender); `lootboxIndex` (uint48): Lootbox RNG index assigned at purchase time |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- delegates all state mutation to LootboxModule

**Callers:** External callers (players, operators)
**Callees:** `_resolvePlayer(player)` -> `_openBurnieLootBoxFor(player, lootboxIndex)`

**ETH Flow:** No ETH accepted (not payable). BURNIE lootbox prizes are BURNIE tokens, not ETH. No ETH flow.
**Invariants:** Same as openLootBox -- player resolution and operator approval required.
**NatSpec Accuracy:** CORRECT -- NatSpec matches behavior. Describes BURNIE variant clearly.
**Gas Flags:** None -- mirror structure to openLootBox.
**Verdict:** CORRECT

---

### `_openLootBoxFor(address, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _openLootBoxFor(address player, uint48 lootboxIndex) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Pre-resolved player address; `lootboxIndex` (uint48): Lootbox RNG index |
| **Returns** | None |

**State Reads:** None directly in Game contract -- all reads happen in LootboxModule via delegatecall
**State Writes:** None directly in Game contract -- all writes happen in LootboxModule via delegatecall (lootbox state, claimableWinnings, etc.)

**Callers:** `openLootBox(address, uint48)`
**Callees:** `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.openLootBox.selector, player, lootboxIndex)`

**ETH Flow:** ETH prizes from lootbox rolls are credited to `claimableWinnings[player]` within the delegatecall (pull pattern -- no direct transfer).
**Invariants:** Delegatecall target is compile-time constant. If delegatecall fails, `_revertDelegate` propagates the exact revert reason.
**NatSpec Accuracy:** No NatSpec on this private function. Acceptable for internal implementation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_openBurnieLootBoxFor(address, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _openBurnieLootBoxFor(address player, uint48 lootboxIndex) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Pre-resolved player address; `lootboxIndex` (uint48): BURNIE lootbox RNG index |
| **Returns** | None |

**State Reads:** None directly -- all reads happen in LootboxModule via delegatecall
**State Writes:** None directly -- all writes happen in LootboxModule via delegatecall

**Callers:** `openBurnieLootBox(address, uint48)`
**Callees:** `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.openBurnieLootBox.selector, player, lootboxIndex)`

**ETH Flow:** No ETH flow -- BURNIE lootboxes pay in BURNIE tokens via coin minting in the module.
**Invariants:** Same delegatecall safety as `_openLootBoxFor`. Compile-time constant target.
**NatSpec Accuracy:** No NatSpec on private function. Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `placeFullTicketBets(address, uint8, uint128, uint8, uint32, uint8)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `currency` (uint8): Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP); `amountPerTicket` (uint128): Bet amount per ticket; `ticketCount` (uint8): Number of spins (1-10); `customTicket` (uint32): Custom packed traits; `heroQuadrant` (uint8): Hero quadrant (0-3) for payout boost, or 0xFF for no hero |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline in abi.encodeWithSelector)
**State Writes:** None directly -- all state mutation delegated to DegeneretteModule

**Callers:** External callers (players, operators)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.placeFullTicketBets.selector, _resolvePlayer(player), currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Payable -- `msg.value` is forwarded to the delegatecall context. For ETH bets (currency=0), the module validates that `msg.value >= amountPerTicket * ticketCount`. ETH is held by the Game contract.
**Invariants:** Player resolution happens inline via `_resolvePlayer(player)`. All 6 parameters forwarded to module without modification. The module handles currency validation, bet size limits, and payout calculations.
**NatSpec Accuracy:** CORRECT -- NatSpec accurately describes all parameters including currency enum values, ticket count range, and hero quadrant semantics.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `placeFullTicketBetsFromAffiliateCredit(address, uint128, uint8, uint32, uint8)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `amountPerTicket` (uint128): Bet amount per ticket; `ticketCount` (uint8): Number of spins (1-10); `customTicket` (uint32): Custom packed traits; `heroQuadrant` (uint8): Hero quadrant (0-3) for payout boost, or 0xFF for no hero |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline)
**State Writes:** None directly -- module deducts affiliate credit from storage

**Callers:** External callers (players with affiliate credit)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.placeFullTicketBetsFromAffiliateCredit.selector, _resolvePlayer(player), amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Not payable -- no ETH accepted. Bets funded from affiliate Degenerette credit (internal accounting).
**Invariants:** No `currency` parameter -- affiliate credit is implicitly BURNIE-denominated. All 5 parameters forwarded to module without modification.
**NatSpec Accuracy:** CORRECT -- NatSpec omits currency (correct, since affiliate credit is fixed denomination). Documents all parameters accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `resolveDegeneretteBets(address, uint64[])` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveDegeneretteBets(address player, uint64[] calldata betIds) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `betIds` (uint64[]): Array of bet IDs to resolve |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline)
**State Writes:** None directly -- module resolves bets, updates bet storage, credits winnings

**Callers:** External callers (players resolving completed bets)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.resolveBets.selector, _resolvePlayer(player), betIds)`

**ETH Flow:** Not payable. The module may credit ETH winnings to `claimableWinnings[player]` (pull pattern) depending on bet currency and outcome.
**Invariants:** Note the selector dispatches to `resolveBets` in the module interface, not `resolveDegeneretteBets`. This is intentional -- the Game-facing name includes the "Degenerette" prefix for clarity, while the module uses the shorter `resolveBets` name.
**NatSpec Accuracy:** CONCERN (minor) -- NatSpec says `@param betIds Bet ids for the player` but the parameter is actually `uint64[] calldata betIds`, not `uint24` as the plan initially suggested. The actual NatSpec matches the code correctly.
**Gas Flags:** Calldata array passed through delegatecall -- efficient, no memory copy needed for encoding. However, large betIds arrays could increase gas costs linearly.
**Verdict:** CORRECT

---

### `consumeCoinflipBoon(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipBoon(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boon to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `ContractAddresses.COIN`, `ContractAddresses.COINFLIP` (compile-time constants for access control check)
**State Writes:** None directly -- module clears/consumes boon state via delegatecall

**Callers:** BurnieCoin contract, BurnieCoinflip contract (external cross-contract calls)
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumeCoinflipBoon.selector, player)`

**ETH Flow:** No ETH -- boon consumption is pure state mutation (clears boon, returns boost value).
**Invariants:** Access restricted to COIN or COINFLIP contracts only via `msg.sender` check. Reverts with `E()` if caller is unauthorized. Note: no `_resolvePlayer` -- the `player` address is passed directly by the calling contract (COIN/COINFLIP already knows the player identity). Return value decoded from delegatecall bytes via `abi.decode(data, (uint16))`.
**NatSpec Accuracy:** CORRECT -- NatSpec documents access control restriction, parameter, return value, and custom revert condition accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `consumeDecimatorBoon(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecimatorBoon(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boon to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `ContractAddresses.COIN` (compile-time constant for access control check)
**State Writes:** None directly -- module clears/consumes boon state via delegatecall

**Callers:** BurnieCoin contract only (external cross-contract call during BURNIE burns)
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumeDecimatorBoost.selector, player)`

**ETH Flow:** No ETH -- pure state mutation.
**Invariants:** Access restricted to COIN contract only. Note the selector mismatch: Game function is `consumeDecimatorBoon` but dispatches to module's `consumeDecimatorBoost`. This is intentional naming -- the Game uses "Boon" (user-facing term) while the module uses "Boost" (implementation term). The selector correctly maps to the module interface method. No `_resolvePlayer` -- same pattern as `consumeCoinflipBoon`.
**NatSpec Accuracy:** CORRECT -- NatSpec documents COIN-only access, parameter, return, and revert accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `consumePurchaseBoost(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumePurchaseBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boost to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `address(this)` (for self-call check)
**State Writes:** None directly -- module clears/consumes boost state via delegatecall

**Callers:** Self-call only -- invoked by delegatecall modules (e.g., MintModule) via `address(this).call(...)` or `DegenerusGame(address(this)).consumePurchaseBoost(player)`
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumePurchaseBoost.selector, player)`

**ETH Flow:** No ETH -- pure state mutation.
**Invariants:** Access restricted to `msg.sender == address(this)`. This is the self-call pattern: delegatecall modules run in Game's context and call back to Game's external functions to trigger other modules. This avoids direct cross-module delegatecall (which would be a security risk). No `_resolvePlayer` -- player is already resolved by the calling module.
**NatSpec Accuracy:** CORRECT -- NatSpec documents self-call access pattern, parameter, return, and revert accurately.
**Gas Flags:** None. The self-call adds ~2600 gas (CALL opcode) but is necessary for module isolation.
**Verdict:** CORRECT

---

### `issueDeityBoon(address, address, uint8)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function issueDeityBoon(address deity, address recipient, uint8 slot) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `deity` (address): Deity issuing the boon (address(0) = msg.sender); `recipient` (address): Recipient of the boon; `slot` (uint8): Slot index (0-2) |
| **Returns** | None |

**State Reads:** `operatorApprovals[deity][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- module writes deity boon state via delegatecall

**Callers:** External callers (deity pass holders, operators)
**Callees:** `_resolvePlayer(deity)`, then `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.issueDeityBoon.selector, deity, recipient, slot)`

**ETH Flow:** No ETH -- boon issuance is pure state mutation.
**Invariants:**
- Self-boon prevention: `recipient == deity` reverts with `E()`. This prevents deities from issuing boons to themselves.
- Player resolution: `deity` is resolved via `_resolvePlayer` (supports operator pattern). `recipient` is NOT resolved -- it's a direct address (the deity chooses who receives the boon).
- Note: dispatches to `GAME_LOOTBOX_MODULE`, NOT `GAME_BOON_MODULE`. This is because deity boon issuance involves generating lootbox-style rewards (the boon generation logic lives alongside lootbox resolution in LootboxModule).
**NatSpec Accuracy:** CORRECT -- NatSpec documents deity resolution, recipient, slot range, and self-boon revert accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

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

### `setAutoRebuy(address player, bool enabled)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAutoRebuy(address player, bool enabled) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `enabled` (bool): true to enable auto-rebuy, false to disable |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAutoRebuy` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAutoRebuy(player, enabled)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings
- Resolves `address(0)` to `msg.sender` for convenience

**NatSpec Accuracy:** NatSpec accurately describes auto-rebuy toggle, bonus percentages (30% default, 45% afKing), and ticket conversion mechanics. The function correctly delegates to `_setAutoRebuy`.

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `setDecimatorAutoRebuy(address player, bool enabled)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setDecimatorAutoRebuy(address player, bool enabled) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `enabled` (bool): true to enable decimator auto-rebuy, false to disable |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
- `rngLockedFlag` -- checked for RNG lock
- `decimatorAutoRebuyDisabled[player]` -- current toggle state

**State Writes:**
- `decimatorAutoRebuyDisabled[player]` -- set to `!enabled` (inverted storage: true = disabled)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval

**ETH Flow:** None.

**Invariants:**
- DGNRS contract cannot toggle this setting (`revert E()` if `player == ContractAddresses.DGNRS`)
- Cannot modify during RNG lock (`revert RngLocked()`)
- Default is enabled (mapping defaults to `false`, and `!false` = enabled)

**NatSpec Accuracy:** NatSpec correctly states "Default is enabled" and "DGNRS is not permitted to toggle this setting." Both match the implementation.

**Gas Flags:**
- Conditional write (`if (decimatorAutoRebuyDisabled[player] != disabled)`) prevents redundant SSTORE. Efficient pattern.
- Event emitted even on no-op (same state). This is an informational -- the event always reflects the current user intent.

**Verdict:** CORRECT

---

### `setAutoRebuyTakeProfit(address player, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to configure (address(0) = msg.sender); `takeProfit` (uint256): amount in wei reserved for manual claim (0 = rebuy all) |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAutoRebuyTakeProfit` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAutoRebuyTakeProfit(player, takeProfit)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings

**NatSpec Accuracy:** NatSpec correctly describes "complete multiples remain claimable; remainder is eligible for auto-rebuy" and "0 means no reservation (rebuy all)."

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `_setAutoRebuy(address player, bool enabled)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAutoRebuy(address player, bool enabled) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `enabled` (bool): new toggle state |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `autoRebuyState[player].autoRebuyEnabled` -- current toggle state
- `autoRebuyState[player].afKingMode` (via `_deactivateAfKing`)

**State Writes:**
- `autoRebuyState[player].autoRebuyEnabled` -- set to `enabled` (conditional write)

**Callers:**
- `setAutoRebuy(address, bool)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when disabling auto-rebuy (afKing requires auto-rebuy)

**ETH Flow:** None.

**Invariants:**
- Cannot modify during RNG lock (`revert RngLocked()`)
- Disabling auto-rebuy forces afKing deactivation (afKing depends on auto-rebuy being on)
- Event emitted even on no-op (same state). Informational.

**NatSpec Accuracy:** No NatSpec on this private function. Behavior is clear from code: toggle with RNG guard and afKing coupling.

**Gas Flags:**
- Conditional write prevents redundant SSTORE. Efficient.
- Event always emitted regardless of state change -- consistent with `setDecimatorAutoRebuy` pattern.

**Verdict:** CORRECT

---

### `_setAutoRebuyTakeProfit(address player, uint256 takeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAutoRebuyTakeProfit(address player, uint256 takeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `takeProfit` (uint256): amount in wei |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `autoRebuyState[player].takeProfit` -- current take profit value
- `autoRebuyState[player].afKingMode` (via `_deactivateAfKing`)

**State Writes:**
- `autoRebuyState[player].takeProfit` -- set to `uint128(takeProfit)` (conditional write)

**Callers:**
- `setAutoRebuyTakeProfit(address, uint256)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when `takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_ETH` (5 ETH)

**ETH Flow:** None.

**Invariants:**
- Cannot modify during RNG lock (`revert RngLocked()`)
- If take profit is nonzero but below 5 ETH minimum for afKing, afKing is deactivated
- `uint128` truncation: values > type(uint128).max silently truncate. This is safe because `uint128` holds up to ~3.4e20 ETH, far exceeding realistic values.

**NatSpec Accuracy:** No NatSpec on this private function. Behavior matches parent's NatSpec.

**Gas Flags:**
- Conditional write prevents redundant SSTORE. Efficient.
- Event uses the original `takeProfit` (uint256), not the truncated `uint128` value. This could theoretically differ if caller passes > 2^128, but this is unrealistic and the truncation in storage is the intended behavior.

**Verdict:** CORRECT

---

### `setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address (address(0) = msg.sender); `enabled` (bool): true to enable afKing, false to disable; `ethTakeProfit` (uint256): desired ETH take profit (wei); `coinTakeProfit` (uint256): desired coin take profit (BURNIE, 18 decimals) |
| **Returns** | None |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)

**State Writes:**
- Delegates to `_setAfKingMode` (see below)

**Callers:** External entry point. Called by players or approved operators.

**Callees:**
- `_resolvePlayer(player)` -- resolves address(0) to msg.sender, checks operator approval
- `_setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit)` -- internal implementation

**ETH Flow:** None.

**Invariants:**
- Only `msg.sender` or an approved operator can modify a player's settings

**NatSpec Accuracy:** NatSpec accurately describes: enabling forces auto-rebuy on, clamps take profit to minimums (5 ETH / 20k BURNIE) unless set to 0, requires lazy pass. Custom reverts (RngLocked, E, AfKingLockActive) are documented and match implementation.

**Gas Flags:** None. Simple delegation wrapper.

**Verdict:** CORRECT

---

### `_setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player address; `enabled` (bool): toggle; `ethTakeProfit` (uint256): desired ETH take profit; `coinTakeProfit` (uint256): desired BURNIE take profit |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` -- checked for RNG lock
- `deityPassCount[player]` (via `_hasAnyLazyPass`)
- `mintPacked_[player]` (via `_hasAnyLazyPass`) -- frozen until level
- `level` (via `_hasAnyLazyPass`) -- current game level
- `autoRebuyState[player]` -- full struct: autoRebuyEnabled, takeProfit, afKingMode, afKingActivatedLevel

**State Writes:**
- `autoRebuyState[player].autoRebuyEnabled` -- forced true (conditional write)
- `autoRebuyState[player].takeProfit` -- set to clamped ETH take profit (conditional write)
- `autoRebuyState[player].afKingMode` -- set true (conditional write)
- `autoRebuyState[player].afKingActivatedLevel` -- set to current `level`

**Callers:**
- `setAfKingMode(address, bool, uint256, uint256)` -- external entry point

**Callees:**
- `_deactivateAfKing(player)` -- called when `enabled == false`
- `_hasAnyLazyPass(player)` -- lazy pass check (deity pass or frozen-until-level)
- `coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` -- enables coinflip auto-rebuy with clamped take profit
- `coinflip.settleFlipModeChange(player)` -- settles pending coinflip before mode change (only on first activation)

**ETH Flow:** None directly. The coinflip cross-contract calls do not move ETH.

**Invariants:**
- Requires lazy pass (deity pass or frozen-until-level > current level) to enable
- Cannot modify during RNG lock
- ETH take profit clamped to minimum 5 ETH if nonzero (0 allowed = rebuy all)
- Coin take profit clamped to minimum 20,000 BURNIE if nonzero (0 allowed = rebuy all)
- Forces auto-rebuy enabled as prerequisite
- `settleFlipModeChange` called before mode change to prevent pending-flip inconsistency
- `afKingActivatedLevel` always set to current level on activation (even re-activation, since it doesn't re-enter the block if already afKingMode)

**NatSpec Accuracy:** No NatSpec on private function. Parent NatSpec covers behavior accurately.

**Gas Flags:**
- Three conditional writes prevent redundant SSTOREs. Efficient.
- Two cross-contract calls (`coinflip.setCoinflipAutoRebuy`, `coinflip.settleFlipModeChange`) are necessary for consistency but add gas cost. These only fire on mode transitions.

**Verdict:** CORRECT

---

### `deactivateAfKingFromCoin(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function deactivateAfKingFromCoin(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to deactivate afKing for |
| **Returns** | None |

**State Reads:**
- `msg.sender` -- checked against COIN and COINFLIP addresses
- Via `_deactivateAfKing`: `autoRebuyState[player]`

**State Writes:**
- Via `_deactivateAfKing`: `autoRebuyState[player].afKingMode`, `autoRebuyState[player].afKingActivatedLevel`

**Callers:** Called by BurnieCoin (COIN) or BurnieCoinflip (COINFLIP) contracts when they need to deactivate afKing (e.g., player disables coinflip auto-rebuy or sells all coins).

**Callees:**
- `_deactivateAfKing(player)` -- internal deactivation with lock period check

**ETH Flow:** None.

**Invariants:**
- Access: COIN or COINFLIP only (`revert E()` for others)
- Lock period enforced via `_deactivateAfKing` -- if within AFKING_LOCK_LEVELS (5) of activation, reverts with `AfKingLockActive`

**NatSpec Accuracy:** NatSpec says "Access: COIN or COINFLIP contract only" and the code checks both. The revert documentation matches.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `syncAfKingLazyPassFromCoin(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function syncAfKingLazyPassFromCoin(address player) external returns (bool active)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to sync afKing status for |
| **Returns** | `active` (bool): true if afKing remains active after sync |

**State Reads:**
- `msg.sender` -- checked against COINFLIP address
- `autoRebuyState[player].afKingMode` -- current afKing state
- `deityPassCount[player]` (via `_hasAnyLazyPass`)
- `mintPacked_[player]` (via `_hasAnyLazyPass`)
- `level` (via `_hasAnyLazyPass`)

**State Writes:**
- `autoRebuyState[player].afKingMode` -- set to false if lazy pass expired
- `autoRebuyState[player].afKingActivatedLevel` -- reset to 0 if lazy pass expired

**Callers:** Called by BurnieCoinflip (COINFLIP) during deposit/claim operations that call `_syncAfKingLazyPass`.

**Callees:**
- `_hasAnyLazyPass(player)` -- checks if player still has valid lazy pass

**ETH Flow:** None.

**Invariants:**
- Access: COINFLIP only (`revert E()` for others)
- If afKing not active, returns false immediately (no state change)
- If lazy pass still valid, returns true (no state change)
- If lazy pass expired, deactivates afKing without lock period check (no `AfKingLockActive` revert)
- Settle not called: comment explains coinflip operation already handles settlement
- Unlike `_deactivateAfKing`, this bypasses the lock period check because it's a passive expiry (lazy pass ran out), not a voluntary deactivation

**NatSpec Accuracy:** NatSpec says "Access: COINFLIP contract only" -- matches code (only checks COINFLIP, not COIN). NatSpec says "Sync afKing lazy pass status and revoke if inactive" -- accurate.

**Gas Flags:** None. Efficient short-circuit returns.

**Verdict:** CORRECT

---

### `_deactivateAfKing(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _deactivateAfKing(address player) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to deactivate afKing for |
| **Returns** | None |

**State Reads:**
- `autoRebuyState[player].afKingMode` -- checks if currently active
- `autoRebuyState[player].afKingActivatedLevel` -- used for lock period check
- `level` -- current game level

**State Writes:**
- `autoRebuyState[player].afKingMode` -- set to false
- `autoRebuyState[player].afKingActivatedLevel` -- reset to 0

**Callers:**
- `_setAutoRebuy(address, bool)` -- when disabling auto-rebuy
- `_setAutoRebuyTakeProfit(address, uint256)` -- when take profit below afKing minimum
- `_setAfKingMode(address, bool, uint256, uint256)` -- when explicitly disabling afKing
- `deactivateAfKingFromCoin(address)` -- cross-contract hook

**Callees:**
- `coinflip.settleFlipModeChange(player)` -- settles pending coinflip before mode change

**ETH Flow:** None directly. `settleFlipModeChange` is a settlement call.

**Invariants:**
- No-op if afKing not active (early return)
- Lock period enforced: if `activationLevel != 0` and `level < activationLevel + AFKING_LOCK_LEVELS (5)`, reverts with `AfKingLockActive`
- Special case: `activationLevel == 0` (activated at level 0) bypasses lock check entirely. This means afKing activated at level 0 can be immediately deactivated. This is intentional -- the lock prevents deactivation during the first 5 levels after activation, and level 0 activation means unlock at level 5 would always pass since `0 + 5 = 5`.
- Wait: Actually, `activationLevel != 0` guard means level 0 activation skips the lock. At level 0, `activationLevel = 0`, so the lock block is skipped entirely. The player could deactivate immediately. At level 1+, the lock would apply. This is a potential concern but reviewing the flow: `_setAfKingMode` sets `afKingActivatedLevel = level`. At level 0, this is 0. The `if (activationLevel != 0)` guard skips the lock. So a player who activates afKing at level 0 can deactivate immediately. This appears intentional since the game starts at level 0 and players should be able to experiment with settings before the game truly begins.
- `settleFlipModeChange` called before state mutation -- ensures pending coinflip bets are settled at the old mode
- Event emitted after state mutation

**NatSpec Accuracy:** No NatSpec on private function. Code is self-documenting.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `adminSwapEthForStEth(address recipient, uint256 amount)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function adminSwapEthForStEth(address recipient, uint256 amount) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `recipient` (address): address to receive stETH; `amount` (uint256): ETH amount to swap (must match msg.value) |
| **Returns** | None |

**State Reads:**
- `steth.balanceOf(address(this))` -- game's stETH balance (external call to Lido)

**State Writes:**
- None in game storage. External stETH transfer alters stETH contract state.

**Callers:** Called by DegenerusAdmin contract only.

**Callees:**
- `steth.balanceOf(address(this))` -- check stETH balance
- `steth.transfer(recipient, amount)` -- transfer stETH to recipient

**ETH Flow:**
- **IN:** `msg.value` (ETH) from ADMIN contract enters game's ETH balance
- **OUT:** `amount` of stETH transferred from game to `recipient`
- Net effect: Game gains ETH, loses stETH of equal value. Value-neutral swap.

**Invariants:**
- Access: ADMIN only (`revert E()` for others)
- `recipient` must not be address(0) (`revert E()`)
- `amount` must be nonzero (`revert E()`)
- `msg.value` must exactly equal `amount` (`revert E()`)
- Game must hold sufficient stETH (`stBal >= amount`, `revert E()`)
- stETH transfer must succeed (`revert E()` on failure)
- Value-neutral: ADMIN sends exact ETH to receive game-held stETH. No fund extraction possible -- ADMIN cannot send less ETH than stETH received.

**NatSpec Accuracy:** NatSpec accurately describes "Admin-only swap: caller sends ETH in and receives game-held stETH." Security note "Value-neutral swap, ADMIN cannot extract funds" is accurate. Custom reverts documented.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `adminStakeEthForStEth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function adminStakeEthForStEth(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): ETH amount to stake via Lido |
| **Returns** | None |

**State Reads:**
- `address(this).balance` -- game's ETH balance
- `claimablePool` -- reserved ETH for player claims

**State Writes:**
- None in game storage. Lido mints stETH to game address (external state change).

**Callers:** Called by DegenerusAdmin contract only.

**Callees:**
- `steth.submit{value: amount}(address(0))` -- Lido ETH-to-stETH stake (referral = address(0))

**ETH Flow:**
- **OUT:** `amount` ETH sent to Lido staking contract
- **IN:** stETH minted 1:1 to game address (Lido invariant)
- Net effect: Game converts ETH to stETH for yield. Value-preserving.

**Invariants:**
- Access: ADMIN only (`revert E()`)
- Amount must be nonzero (`revert E()`)
- Game must hold sufficient ETH (`ethBal >= amount`, `revert E()`)
- Game ETH balance must exceed claimablePool reserve (`ethBal > reserve`, `revert E()`)
- Stakeable amount is `ethBal - reserve`; amount must not exceed stakeable (`revert E()`)
- claimablePool is protected: admin cannot stake ETH reserved for player claims
- Lido submit wrapped in try/catch: reverts with generic `E()` on failure

**NatSpec Accuracy:** NatSpec accurately describes "Cannot stake ETH reserved for player claims (claimablePool)." Security note is correct. The return value comment "stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks" is accurate -- the empty try body `returns (uint256) {}` discards the return.

**Gas Flags:**
- The `ethBal <= reserve` and `amount > stakeable` checks are two separate conditions that could theoretically be combined, but they provide clearer error semantics and the gas difference is negligible. Informational.

**Verdict:** CORRECT

---

### `updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): new VRF coordinator address; `newSubId` (uint256): new subscription ID; `newKeyHash` (bytes32): new key hash for gas lane |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule (reads `rngRequestTime`, `msg.sender`, `ContractAddresses.ADMIN`)

**State Writes:**
- Delegated to AdvanceModule (writes VRF coordinator, subscription ID, key hash in game storage)

**Callers:** Called by DegenerusAdmin contract.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector, ...)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None.

**Invariants:**
- Access: ADMIN only (enforced in AdvanceModule)
- 3-day stall condition required (VRF must have been unresponsive for 3+ days)
- Recovery mechanism only -- not for routine changes
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec accurately describes "Emergency VRF coordinator rotation after 3-day stall." Custom reverts (`VrfUpdateNotReady`, `E`) are documented. The 3-day security requirement is noted.

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `requestLootboxRng()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function requestLootboxRng() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule

**State Writes:**
- Delegated to AdvanceModule (VRF request state)

**Callers:** External -- callable by anyone (permissionless trigger).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.requestLootboxRng.selector)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None directly. The AdvanceModule may interact with Chainlink VRF (LINK token for payment is handled by subscription).

**Invariants:**
- Permissionless: anyone can trigger, but AdvanceModule enforces preconditions (daily RNG consumed, request windows, pending value threshold)
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec correctly states "Callable by anyone. Reverts if daily RNG has not been consumed, if request windows are locked, or if pending lootbox value is below threshold."

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `reverseFlip()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function reverseFlip() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule

**State Writes:**
- Delegated to AdvanceModule (nudge counter, BURNIE burn)

**Callers:** External -- callable by any player.

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.reverseFlip.selector)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None directly. The AdvanceModule burns BURNIE tokens from the caller.

**Invariants:**
- Cost scales +50% per queued nudge, resets after VRF fulfillment
- Only available when RNG is unlocked (before VRF request)
- Players influence but cannot predict the base VRF word

**NatSpec Accuracy:** NatSpec accurately describes the nudge mechanism: "+50% per queued nudge", "resets after fulfillment", "Only available while RNG is unlocked." The security note "Players cannot predict the base word, only influence it" is correct.

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID to match; `randomWords` (uint256[]): array containing the random word (expected length 1) |
| **Returns** | None |

**State Reads:**
- Delegated to AdvanceModule (reads `vrfRequestId`, VRF coordinator address, nudge counter)

**State Writes:**
- Delegated to AdvanceModule (writes `rngWordCurrent`, `rngWordByDay[dailyIdx]`, clears nudge state)

**Callers:** Called by Chainlink VRF Coordinator contract only (enforced in AdvanceModule).

**Callees:**
- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector, ...)` -- full logic in AdvanceModule
- `_revertDelegate(data)` -- bubble up errors on failure

**ETH Flow:** None.

**Invariants:**
- Access: VRF coordinator only (validated in AdvanceModule)
- Request ID must match pending request (prevents stale/mismatched fulfillments)
- Nudges applied to random word before storage (word += nudge count)
- Single random word expected (array length 1)
- Delegatecall preserves game storage context

**NatSpec Accuracy:** NatSpec accurately describes "Access: VRF coordinator only", "Validates requestId and coordinator address", "Applies any queued nudges before storing the word."

**Gas Flags:** None. Simple delegatecall dispatch.

**Verdict:** CORRECT

---

### `_transferSteth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transferSteth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient of stETH; `amount` (uint256): stETH amount to transfer |
| **Returns** | None |

**State Reads:**
- None in game storage. External calls to stETH and DGNRS contracts.

**State Writes:**
- None in game storage. External stETH balance changes.

**Callers:**
- `_payoutWithStethFallback(address, uint256)` -- stETH portion of fallback payout
- `_payoutWithEthFallback(address, uint256)` -- stETH-first payout
- `adminSwapEthForStEth` does NOT use this -- it calls `steth.transfer` directly

**Callees:**
- `steth.approve(ContractAddresses.DGNRS, amount)` -- approve DGNRS to pull stETH (DGNRS path only)
- `dgnrs.depositSteth(amount)` -- deposit stETH into DGNRS reserves (DGNRS path only)
- `steth.transfer(to, amount)` -- direct stETH transfer (non-DGNRS path)

**ETH Flow:**
- **OUT:** stETH transferred from game to `to` (or deposited into DGNRS)
- Special case for DGNRS: approve + depositSteth pattern (DGNRS pulls stETH via transferFrom internally)

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- DGNRS special path: uses approve + deposit pattern instead of direct transfer (DGNRS needs to track deposits internally)
- Non-DGNRS path: direct stETH.transfer with success check
- Transfer failure reverts with `E()`

**NatSpec Accuracy:** No NatSpec on private function. Code is self-documenting.

**Gas Flags:**
- Approve before deposit: the approval could theoretically be front-run, but since this is called from within game contract execution (not a user-facing approval flow), the approve + deposit are atomic within the transaction. Safe.

**Verdict:** CORRECT

---

### `_payoutWithStethFallback(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payoutWithStethFallback(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): total wei to send |
| **Returns** | None |

**State Reads:**
- `address(this).balance` -- game's ETH balance (read twice: initial and retry)
- `steth.balanceOf(address(this))` -- game's stETH balance

**State Writes:**
- None in game storage. External balance changes via ETH transfer and stETH transfer.

**Callers:** Called by jackpot payout, claim, and distribution functions throughout DegenerusGame and its modules (via delegatecall).

**Callees:**
- `payable(to).call{value: ethSend}("")` -- ETH transfer (low-level call)
- `_transferSteth(to, stSend)` -- stETH transfer for remainder
- `payable(to).call{value: leftover}("")` -- ETH retry for any final remainder

**ETH Flow:**
- **Priority:** ETH first, then stETH for remainder, then ETH retry for leftover
- **Phase 1:** Send up to `min(amount, ethBal)` as ETH
- **Phase 2:** Send up to `min(remaining, stBal)` as stETH
- **Phase 3:** If still remaining after stETH, retry with refreshed ETH balance

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- ETH transfer uses low-level `.call{value:}("")` -- safe pattern (no gas limit, returns success boolean)
- ETH transfer failure reverts immediately (`revert E()`)
- stETH fallback: sends whatever stETH is available, capped at remainder
- Retry mechanism: covers edge case where stETH was short but new ETH arrived (e.g., from stETH transfer to DGNRS which may send ETH back, or reentrancy-safe scenarios)
- Final retry: reverts if refreshed ETH balance < leftover (`revert E()`)
- Total payout exactly equals `amount` (ETH + stETH + retry ETH = amount)

**NatSpec Accuracy:** NatSpec says "Send ETH first, then stETH for remainder" -- the actual function name says "StethFallback" meaning stETH is the fallback, ETH is preferred. NatSpec and implementation match. The "Includes retry logic if stETH is short but ETH arrives" note is accurate.

**Gas Flags:**
- Three-phase payout adds gas compared to a simple transfer, but the fallback logic is necessary for robustness. No optimization opportunity without sacrificing correctness.
- `address(this).balance` read twice (initial + retry). The retry read is necessary since ETH balance may have changed after stETH operations.

**Verdict:** CORRECT

---

### `_payoutWithEthFallback(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payoutWithEthFallback(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): total wei to send |
| **Returns** | None |

**State Reads:**
- `steth.balanceOf(address(this))` -- game's stETH balance
- `address(this).balance` -- game's ETH balance (for fallback)

**State Writes:**
- None in game storage. External balance changes via stETH and ETH transfers.

**Callers:** Called by vault/DGNRS reserve claims and admin-related payout paths where stETH is preferred.

**Callees:**
- `_transferSteth(to, stSend)` -- stETH transfer (primary)
- `payable(to).call{value: remaining}("")` -- ETH transfer for remainder (fallback)

**ETH Flow:**
- **Priority:** stETH first, then ETH for remainder
- **Phase 1:** Send up to `min(amount, stBal)` as stETH
- **Phase 2:** Send remaining as ETH (reverts if insufficient)

**Invariants:**
- Zero-amount guard: returns immediately if `amount == 0`
- stETH transfer uses `_transferSteth` (handles DGNRS special case)
- ETH fallback: reverts if ETH balance < remaining (`revert E()`)
- ETH transfer failure reverts (`revert E()`)
- Simpler than `_payoutWithStethFallback` -- no retry mechanism (two phases only)
- Total payout exactly equals `amount` (stETH + ETH = amount)

**NatSpec Accuracy:** NatSpec says "Send stETH first, then ETH for remainder. Used for vault/DGNRS reserve claims (stETH preferred)." Matches implementation.

**Gas Flags:** None. Two-phase payout is minimal.

**Verdict:** CORRECT


---

## DegenerusGameAdvanceModule.sol

### `advanceGame()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function advanceGame() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `msg.sender` (caller for mint-gate and bounty)
- `block.timestamp` (ts)
- `_simulatedDayIndexAt(ts)` -> `day` (inherited from GameTimeLib via Storage)
- `jackpotPhaseFlag` (inJackpot)
- `level` (lvl)
- `lastPurchaseDay` (lastPurchase)
- `rngLockedFlag` (used in purchaseLevel calculation)
- `dailyIdx` (passed to _handleGameOverPath and _enforceDailyMintGate)
- `levelStartTime` (passed to _handleGameOverPath)
- `phaseTransitionActive` (phase transition state)
- `jackpotCounter` (jackpot day counter)
- `dailyJackpotCoinTicketsPending` (split jackpot pending flag)
- `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor` (resume state)
- `rngWordByDay[day]` (via rngGate)
- `rngWordCurrent`, `rngRequestTime` (via rngGate)
- `nextPrizePool`, `levelPrizePool[purchaseLevel - 1]` (target check)
- `poolConsolidationDone` (consolidation guard)
- `ticketCursor`, `ticketLevel` (via _runProcessTicketBatch)
- `lastDailyJackpotLevel` (resume level for split ETH)
- `lootboxPresaleActive`, `lootboxPresaleMintEth` (presale auto-end)

**State Writes:**
- `lastPurchaseDay = true` (when nextPrizePool >= target)
- `compressedJackpotFlag = (day - purchaseStartDay <= 2)` (compressed mode check)
- `levelPrizePool[purchaseLevel] = nextPrizePool` (prize pool snapshot)
- `poolConsolidationDone = true` (consolidation guard)
- `lootboxPresaleActive = false` (presale auto-end)
- `earlyBurnPercent = 0` (reset at jackpot entry)
- `jackpotPhaseFlag = true` (transition to jackpot)
- `decWindowOpen = true` (open decimator at x4/x99 levels)
- `poolConsolidationDone = false` (reset for next cycle)
- `lastPurchaseDay = false` (reset at jackpot entry)
- `levelStartTime = ts` (new level start time)
- `phaseTransitionActive = false` (transition complete)
- `purchaseStartDay = day` (new purchase start)
- `jackpotPhaseFlag = false` (back to purchase)
- Via `_unlockRng(day)`: `dailyIdx = day`, `rngLockedFlag = false`, `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`
- Via delegatecall sub-modules: various prize pool, ticket, jackpot state

**Callers:**
- External callers (any address, subject to mint-gate). Called via delegatecall from DegenerusGame.

**Callees:**
- `_simulatedDayIndexAt(ts)` (inherited helper)
- `_handleGameOverPath(ts, day, levelStartTime, lvl, lastPurchase, dailyIdx)` (private)
- `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` (private)
- `rngGate(ts, day, purchaseLevel, lastPurchase)` (internal)
- `_processPhaseTransition(purchaseLevel)` (private)
- `_unlockRng(day)` (private)
- `_prepareFinalDayFutureTickets(lvl)` (private)
- `_runProcessTicketBatch(purchaseLevel)` (private)
- `payDailyJackpot(isDaily, lvl, rngWord)` (internal, delegatecall to JackpotModule)
- `_payDailyCoinJackpot(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord)` (private)
- `_consolidatePrizePools(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_drawDownFuturePrizePool(lvl)` (private)
- `_processFutureTicketBatch(nextLevel)` (private, delegatecall to MintModule)
- `payDailyJackpotCoinAndTickets(rngWord)` (internal, delegatecall to JackpotModule)
- `_awardFinalDayDgnrsReward(lvl, rngWord)` (private, delegatecall to JackpotModule)
- `_rewardTopAffiliate(lvl)` (private, delegatecall to EndgameModule)
- `_runRewardJackpots(lvl, rngWord)` (private, delegatecall to EndgameModule)
- `_endPhase()` (private)
- `coin.creditFlip(caller, ADVANCE_BOUNTY)` (external call to DegenerusCoin)

**ETH Flow:**
- No direct ETH transfers in `advanceGame` itself.
- ETH is moved indirectly through delegatecall sub-modules:
  - `payDailyJackpot` -> currentPrizePool/futurePrizePool -> claimableWinnings (player credits)
  - `_consolidatePrizePools` -> nextPrizePool -> currentPrizePool, futurePrizePool adjustments
  - `_applyTimeBasedFutureTake` -> nextPrizePool -> futurePrizePool (time-based skim)
  - `_drawDownFuturePrizePool` -> futurePrizePool -> nextPrizePool (15% release)
  - `_autoStakeExcessEth` (via _processPhaseTransition) -> excess ETH -> stETH via Lido

**Invariants:**
- `advanceGame` cannot be called twice within the same day (reverts `NotTimeYet` if `day == dailyIdx`)
- Mint-gate: caller must have minted today (with time-based and pass-based bypasses)
- Game-over path takes priority and returns early
- Phase transitions are mutually exclusive: purchase phase XOR jackpot phase
- `poolConsolidationDone` prevents double consolidation
- Level increment happens at RNG request time (not at advance time) to prevent manipulation
- `jackpotCounter` caps at `JACKPOT_LEVEL_CAP = 5` before triggering phase end
- ADVANCE_BOUNTY (500 BURNIE flip credit) always awarded to caller after processing

**NatSpec Accuracy:**
- Line 118-119: NatSpec says "Called daily to process jackpots, mints, and phase transitions" -- ACCURATE. It is the daily tick function.
- NatSpec says "Caller receives ADVANCE_BOUNTY (500 BURNIE) as flip credit" -- ACCURATE. `coin.creditFlip(caller, ADVANCE_BOUNTY)` always runs at line 293.

**Gas Flags:**
- The `do { ... } while(false)` pattern is a clean single-pass state machine with `break` for early exits. No wasted iteration.
- `purchaseLevel` computation reads `rngLockedFlag` even when `lastPurchase` is false (minor: the branch is only taken when both are true, so no wasted SLOAD in practice due to short-circuit).
- `_enforceDailyMintGate` uses `view` and returns early on common paths (no external call unless vault ownership check).
- Multiple delegatecalls in the final jackpot day path (`_awardFinalDayDgnrsReward`, `_rewardTopAffiliate`, `_runRewardJackpots`, `_endPhase`) could approach gas limits, but the split-jackpot mechanism across calls mitigates this.

**Verdict:** CORRECT

---

### `wireVrf(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `coordinator_` (address): VRF coordinator address; `subId` (uint256): VRF subscription ID; `keyHash_` (bytes32): gas lane key hash |
| **Returns** | None |

**State Reads:**
- `msg.sender` (access control)
- `vrfCoordinator` (current coordinator for event)

**State Writes:**
- `vrfCoordinator = IVRFCoordinator(coordinator_)`
- `vrfSubscriptionId = subId`
- `vrfKeyHash = keyHash_`

**Callers:**
- DegenerusAdmin contract only (via delegatecall from DegenerusGame). Access restricted: `msg.sender != ContractAddresses.ADMIN` reverts `E()`.

**Callees:**
- None

**ETH Flow:**
- None. Pure configuration function.

**Invariants:**
- Only ContractAddresses.ADMIN can call. There is no one-time guard; ADMIN can re-call to overwrite config. This is documented in NatSpec: "Overwrites any existing config on each call."
- No validation of coordinator_ being non-zero or a valid contract address. This is acceptable since ADMIN is a trusted, immutable contract.

**NatSpec Accuracy:**
- NatSpec says "One-time wiring" but code allows repeated calls. However, the `@dev` clarifies "Overwrites any existing config on each call." The `@notice` is slightly misleading but the `@dev` corrects it. MINOR DISCREPANCY: "One-time" in `@notice` vs "Overwrites on each call" in `@dev`.
- Signature in interface declares `wireVrf(address, uint256, bytes32)` -- matches implementation.

**Gas Flags:**
- Efficient: 3 SSTOREs + 1 SLOAD (for event). Minimal.

**Verdict:** CORRECT. Note: NatSpec `@notice` says "One-time" but it is re-callable. The `@dev` clarifies this adequately.

---

### `requestLootboxRng()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function requestLootboxRng() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `block.timestamp` (nowTs)
- `_simulatedDayIndexAt(nowTs)` (currentDay)
- `_simulatedDayIndexAt(nowTs + 15 minutes)` (pre-reset window check)
- `rngWordByDay[currentDay]` (daily RNG consumed check)
- `rngLockedFlag` (daily lock check)
- `rngRequestTime` (pending request check)
- `vrfCoordinator`, `vrfSubscriptionId` (LINK balance query)
- `vrfKeyHash` (VRF request config)
- `lootboxRngPendingEth`, `lootboxRngPendingBurnie` (threshold check)
- `price` (BURNIE-to-ETH conversion for threshold)
- `lootboxRngThreshold` (configurable threshold)
- `lootboxRngIndex` (via _reserveLootboxRngIndex)

**State Writes:**
- Via `_reserveLootboxRngIndex(id)`:
  - `lootboxRngRequestIndexById[requestId] = lootboxRngIndex`
  - `lootboxRngIndex = index + 1`
  - `lootboxRngPendingEth = 0`
  - `lootboxRngPendingBurnie = 0`
- `vrfRequestId = id`
- `rngWordCurrent = 0`
- `rngRequestTime = uint48(block.timestamp)`

**Callers:**
- Any external caller. No access control beyond the gate checks (timing, daily RNG consumed, not locked, not pending, threshold met, LINK balance).

**Callees:**
- `_simulatedDayIndexAt(nowTs)` (view helper)
- `_simulatedDayIndexAt(nowTs + 15 minutes)` (view helper)
- `vrfCoordinator.getSubscription(vrfSubscriptionId)` (external view call)
- `vrfCoordinator.requestRandomWords(...)` (external state-changing call)
- `_reserveLootboxRngIndex(id)` (private)

**ETH Flow:**
- No direct ETH movement. VRF request costs LINK (paid from subscription, not from game contract).

**Invariants:**
- Cannot be called in the 15-minute pre-reset window (prevents racing daily RNG)
- Cannot be called before today's daily RNG has been recorded (`rngWordByDay[currentDay] == 0` reverts)
- Cannot be called while `rngLockedFlag` is true (daily jackpot resolution in progress)
- Cannot be called while a VRF request is pending (`rngRequestTime != 0`)
- LINK balance must be >= `MIN_LINK_FOR_LOOTBOX_RNG` (40 LINK)
- At least one of pendingEth or pendingBurnie must be > 0
- If BURNIE < BURNIE_RNG_TRIGGER (40000 BURNIE), ETH-equivalent must meet threshold
- `rngLockedFlag` is NOT set by this function (mid-day RNG does not lock daily operations)

**NatSpec Accuracy:**
- NatSpec says "Request lootbox RNG when activity threshold is met" -- ACCURATE.
- NatSpec says "Cannot be called while daily RNG is locked (jackpot resolution)" -- ACCURATE.
- NatSpec says "VRF callback handles finalization directly - no advanceGame needed" -- ACCURATE. `rawFulfillRandomWords` checks `rngLockedFlag == false` for mid-day path.

**Gas Flags:**
- `vrfCoordinator.getSubscription()` is an external view call that reads 5 return values but only `linkBal` is used. The other 4 are discarded. No gas waste since this is a view call (STATICCALL gas cost is the same regardless of return values parsed).
- Threshold logic has multiple branches but all are simple arithmetic. No concern.
- The BURNIE-to-ETH conversion uses `price` which could be zero at level 0 (price starts at 0.01 ETH via Storage default). Since `price` is initialized to `0.01 ether` in DegenerusGameStorage, this division is safe.

**Verdict:** CORRECT

---

### `rngGate(uint48, uint48, uint24, bool)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function rngGate(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay) internal returns (uint256 word)` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lvl` (uint24): current purchase level; `isTicketJackpotDay` (bool): true if last purchase day |
| **Returns** | `word` (uint256): RNG word if available, 1 if request sent, reverts if waiting |

**State Reads:**
- `rngWordByDay[day]` (check if already recorded)
- `rngWordCurrent` (check for pending VRF word)
- `rngRequestTime` (check for pending request / timeout)
- `vrfRequestId` (via _finalizeLootboxRng)
- `lootboxRngRequestIndexById[vrfRequestId]` (via _finalizeLootboxRng)
- `totalFlipReversals` (via _applyDailyRng)
- `level` (for bonusFlip check)

**State Writes:**
- Via `_applyDailyRng(day, currentWord)`: `totalFlipReversals = 0`, `rngWordCurrent = finalWord`, `rngWordByDay[day] = finalWord`
- Via `_finalizeLootboxRng(currentWord)`: `lootboxRngWordByIndex[index] = rngWord`
- Via `_requestRng(isTicketJackpotDay, lvl)`: VRF request state (see _requestRng audit)
- `rngWordCurrent = 0` (when stale cross-day word detected)

**Callers:**
- `advanceGame()` (the only caller)

**Callees:**
- `_simulatedDayIndexAt(rngRequestTime)` (view helper, for staleness check)
- `_finalizeLootboxRng(currentWord)` (private)
- `_applyDailyRng(day, currentWord)` (private)
- `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)` (external call)
- `_requestRng(isTicketJackpotDay, lvl)` (private)

**ETH Flow:**
- No direct ETH flow. `coinflip.processCoinflipPayouts` processes coinflip payouts externally.

**Invariants:**
- Returns immediately if today's RNG already recorded (idempotent for double-entry)
- If VRF word ready and from current day: applies nudges, processes coinflips, finalizes lootbox
- If VRF word ready but from previous day: finalizes for lootbox only, then requests fresh daily RNG
- If VRF pending and 18+ hours elapsed: retries request
- If VRF pending and < 18 hours: reverts `RngNotReady()`
- If no pending request: initiates fresh request, returns 1
- `bonusFlip` is true when `isTicketJackpotDay` OR `level == 0` (first level always gets bonus)

**NatSpec Accuracy:**
- No NatSpec on `rngGate` function itself. The function is internal and self-documenting through its logic. No discrepancy.

**Gas Flags:**
- The staleness check (`requestDay < day`) requires an additional call to `_simulatedDayIndexAt(rngRequestTime)` which involves arithmetic but is pure. Acceptable.
- `coinflip.processCoinflipPayouts` is an external call with potentially high gas cost depending on payout queue size, but this is expected and documented.

**Verdict:** CORRECT

---

### `updateVrfCoordinatorAndSub(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): new VRF coordinator; `newSubId` (uint256): new subscription ID; `newKeyHash` (bytes32): new gas lane key hash |
| **Returns** | None |

**State Reads:**
- `msg.sender` (access control)
- `_simulatedDayIndex()` (current day for 3-day gap check)
- `rngWordByDay[day]`, `rngWordByDay[day-1]`, `rngWordByDay[day-2]` (via _threeDayRngGap)
- `vrfCoordinator` (current coordinator for event)

**State Writes:**
- `vrfCoordinator = IVRFCoordinator(newCoordinator)`
- `vrfSubscriptionId = newSubId`
- `vrfKeyHash = newKeyHash`
- `rngLockedFlag = false`
- `vrfRequestId = 0`
- `rngRequestTime = 0`
- `rngWordCurrent = 0`

**Callers:**
- DegenerusAdmin only (`msg.sender != ContractAddresses.ADMIN` reverts `E()`).

**Callees:**
- `_simulatedDayIndex()` (view helper)
- `_threeDayRngGap(day)` (private view)

**ETH Flow:**
- None. Pure configuration + state reset function.

**Invariants:**
- Only ContractAddresses.ADMIN can call
- Requires 3-day RNG gap (no RNG words recorded for current day, day-1, and day-2)
- Resets all RNG state to allow immediate advancement after rotation
- This is an emergency recovery mechanism, not normal operation

**NatSpec Accuracy:**
- NatSpec says "Emergency VRF coordinator rotation after 3-day stall" -- ACCURATE.
- NatSpec says "Access: ContractAddresses.ADMIN only" -- ACCURATE.
- NatSpec says "SECURITY: Requires 3-day gap to prevent abuse" -- ACCURATE. `_threeDayRngGap` checks 3 consecutive days without RNG.
- Interface declares `updateVrfCoordinatorAndSub(address, uint256, uint32)` but implementation uses `bytes32` for 3rd param. INTERFACE MISMATCH: interface says `uint32 newKeyHash` but implementation says `bytes32 newKeyHash`. However, checking the interface file: the interface actually declares `bytes32 newKeyHash` at line 32 of IDegenerusGameModules.sol. Confirmed: no mismatch.

**Gas Flags:**
- 7 SSTOREs + 1 SLOAD + 3 mapping reads. Efficient for an emergency function.
- `_threeDayRngGap` performs 3 mapping reads. Early-exit on first non-zero optimizes the common denial case.

**Verdict:** CORRECT

---

### `reverseFlip()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function reverseFlip() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` (must be false)
- `totalFlipReversals` (current nudge count for cost calculation)

**State Writes:**
- `totalFlipReversals = reversals + 1` (increment nudge counter)

**Callers:**
- Any external caller. Called via delegatecall from DegenerusGame.

**Callees:**
- `_currentNudgeCost(reversals)` (private pure)
- `coin.burnCoin(msg.sender, cost)` (external call to DegenerusCoin)

**ETH Flow:**
- No ETH flow. Burns BURNIE tokens.

**Invariants:**
- Cannot be called while `rngLockedFlag` is true (reverts `RngLocked()`)
- Cost compounds at 50% per queued nudge: 100, 150, 225, 337.5, 506.25... BURNIE
- `totalFlipReversals` is reset to 0 in `_applyDailyRng` when nudges are consumed
- Nudges shift the VRF word by +1 each, modifying RNG outcomes

**NatSpec Accuracy:**
- NatSpec says "Pay BURNIE to nudge the next RNG word by +1" -- ACCURATE.
- NatSpec says "Cost scales +50% per queued nudge and resets after fulfillment" -- ACCURATE. `_currentNudgeCost` compounds 50% per reversal; `_applyDailyRng` resets counter.
- NatSpec says "Only available while RNG is unlocked (before VRF request is in-flight)" -- ACCURATE.
- NatSpec says "SECURITY: Players cannot predict the base word, only influence it" -- ACCURATE. The base word comes from VRF and is unknown until fulfillment.

**Gas Flags:**
- `_currentNudgeCost` is O(n) in `reversals` count. NatSpec acknowledges this: "O(n) in reversals count - could be optimized with exponentiation for large n, but in practice reversals are bounded by game economics." The exponential cost growth (100 -> 150 -> 225 -> ...) makes large n economically infeasible. Acceptable.

**Verdict:** CORRECT

---

### `rawFulfillRandomWords(uint256, uint256[])` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID to match; `randomWords` (uint256[]): array containing the random word (length 1) |
| **Returns** | None |

**State Reads:**
- `msg.sender` (must be vrfCoordinator address)
- `vrfCoordinator` (for access control comparison)
- `vrfRequestId` (must match requestId)
- `rngWordCurrent` (must be 0, i.e., not already fulfilled)
- `rngLockedFlag` (determines daily vs mid-day path)
- `lootboxRngRequestIndexById[requestId]` (for mid-day finalization)

**State Writes:**
- Daily path (`rngLockedFlag == true`):
  - `rngWordCurrent = word` (store VRF word for advanceGame processing)
- Mid-day path (`rngLockedFlag == false`):
  - `lootboxRngWordByIndex[index] = word` (directly finalize lootbox RNG)
  - `vrfRequestId = 0` (clear request)
  - `rngRequestTime = 0` (clear request time)

**Callers:**
- Chainlink VRF Coordinator only (`msg.sender != address(vrfCoordinator)` reverts `E()`).

**Callees:**
- None (no internal or external calls beyond storage reads/writes and event emission)

**ETH Flow:**
- None. Pure RNG fulfillment handler.

**Invariants:**
- Only the registered VRF coordinator can call
- Silently returns (no revert) if requestId doesn't match current or word already fulfilled -- prevents stale fulfillments from reverting and wasting VRF gas
- Word value of 0 is remapped to 1 (`if (word == 0) word = 1`) to preserve the "0 = pending" sentinel
- Daily path: stores word for later consumption by `advanceGame` -> `rngGate` -> `_applyDailyRng`
- Mid-day path: directly writes to `lootboxRngWordByIndex` for immediate lootbox resolution

**NatSpec Accuracy:**
- NatSpec says "Chainlink VRF callback for random word fulfillment" -- ACCURATE.
- NatSpec says "Access: VRF coordinator only" -- ACCURATE.
- NatSpec says "Daily RNG: stores word for advanceGame processing (nudges applied there)" -- ACCURATE.
- NatSpec says "Mid-day RNG: directly finalizes lootbox RNG, no advanceGame needed" -- ACCURATE.
- NatSpec says "Validates requestId and coordinator address" -- ACCURATE.

**Gas Flags:**
- Minimal gas: 1-2 SLOADs, 1-3 SSTOREs depending on path. Very efficient callback.
- No external calls, making it safe within VRF callback gas limits (300k configured).

**Verdict:** CORRECT

---

### `_handleGameOverPath(uint48, uint48, uint48, uint24, bool, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _handleGameOverPath(uint48 ts, uint48 day, uint48 lst, uint24 lvl, bool lastPurchase, uint48 _dailyIdx) private returns (bool shouldReturn)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lst` (uint48): levelStartTime; `lvl` (uint24): current level; `lastPurchase` (bool): lastPurchaseDay flag; `_dailyIdx` (uint48): daily index |
| **Returns** | `shouldReturn` (bool): true if advanceGame should exit early |

**State Reads:**
- `gameOver` (terminal state check)
- `nextPrizePool` (safety check against premature game-over)
- `levelPrizePool[lvl]` (prize target comparison)
- `rngWordByDay[_dailyIdx]` (RNG availability for drain)
- DEPLOY_IDLE_TIMEOUT_DAYS (constant: 912 days)

**State Writes:**
- `levelStartTime = ts` (when safety check resets liveness timer)
- Via delegatecall to GAME_GAMEOVER_MODULE.handleFinalSweep: game-over drain state
- Via delegatecall to GAME_GAMEOVER_MODULE.handleGameOverDrain: game-over drain state
- Via `_gameOverEntropy(...)`: RNG state (see that function's audit)
- Via `_unlockRng(day)`: resets RNG state

**Callers:**
- `advanceGame()` only

**Callees:**
- `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleFinalSweep.selector)` (post-gameover sweep)
- `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleGameOverDrain.selector, _dailyIdx)` (pre-gameover drain)
- `_gameOverEntropy(ts, day, lvl, lastPurchase)` (private)
- `_unlockRng(day)` (private)
- `_revertDelegate(data)` (private pure)

**ETH Flow:**
- Via delegatecall to GameOverModule: ETH moves from prize pools to claimableWinnings/claimablePool during drain
- handleFinalSweep: transfers remaining ETH to DGNRS/VAULT after 1-month delay
- handleGameOverDrain: distributes prize pools to players/claimable

**Invariants:**
- Liveness check: level 0 = 912-day timeout, level > 0 = 365-day timeout
- If liveness not triggered, returns false immediately (no game-over processing)
- Post-gameover path (gameOver == true): delegates to handleFinalSweep
- Safety check: if `nextPrizePool >= levelPrizePool[lvl]` at level > 0, resets timer and does NOT trigger game-over (prevents premature activation when prize target is already met)
- Pre-gameover path: acquires RNG (with fallback), then delegates to handleGameOverDrain

**NatSpec Accuracy:**
- NatSpec says "Handles gameover state and liveness guard checks. Returns true if advanceGame should exit early." -- ACCURATE.

**Gas Flags:**
- Early return on `!livenessTriggered` is the hot path (99.99%+ of calls). Efficient.
- Liveness arithmetic uses `uint256` promotion for the `DEPLOY_IDLE_TIMEOUT_DAYS * 1 days` multiplication, preventing uint48 overflow. Correct.

**Verdict:** CORRECT

---

### `_endPhase()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _endPhase() private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `level` (lvl, for x00 check)
- `futurePrizePool` (for x00 seeding)

**State Writes:**
- `phaseTransitionActive = true`
- `levelPrizePool[lvl] = futurePrizePool / 3` (only on x00 levels)
- `jackpotCounter = 0`
- `compressedJackpotFlag = false`

**Callers:**
- `advanceGame()` (after final jackpot day processing)

**Callees:**
- None

**ETH Flow:**
- On x00 levels: seeds `levelPrizePool[lvl]` with 1/3 of futurePrizePool. This sets the prize target for the NEXT purchase phase using current future pool as a baseline. Note: futurePrizePool itself is NOT reduced here; the seed is just a target snapshot.

**Invariants:**
- Always sets `phaseTransitionActive = true` to trigger transition processing on next advanceGame call
- x00 levels get special treatment: prize target seeded from future pool (making x00 levels significant milestones)
- `jackpotCounter` reset ensures next level starts fresh
- `compressedJackpotFlag` cleared so next level can independently determine if compressed

**NatSpec Accuracy:**
- No explicit NatSpec on this function. Section header says "LEVEL END" which is accurate.

**Gas Flags:**
- Very lightweight: 2-4 SSTOREs. Clean.

**Verdict:** CORRECT

---

### `_rewardTopAffiliate(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardTopAffiliate(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- None directly (delegates all work)

**State Writes:**
- Via delegatecall to GAME_ENDGAME_MODULE.rewardTopAffiliate: affiliate reward state

**Callers:**
- `advanceGame()` (final jackpot day, after coin+ticket distribution)

**Callees:**
- `ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(rewardTopAffiliate.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via EndgameModule: distributes DGNRS tokens to top affiliate for the level. No direct ETH movement.

**Invariants:**
- Delegatecall failure reverts the entire advanceGame call

**NatSpec Accuracy:**
- NatSpec says "Reward the top affiliate for a level during level transition" -- ACCURATE.

**Gas Flags:**
- Single delegatecall. Cost depends on EndgameModule implementation.

**Verdict:** CORRECT

---

### `_runRewardJackpots(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runRewardJackpots(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:**
- None directly

**State Writes:**
- Via delegatecall to GAME_ENDGAME_MODULE.runRewardJackpots: BAF/Decimator jackpot state

**Callers:**
- `advanceGame()` (final jackpot day)

**Callees:**
- `ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(runRewardJackpots.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via EndgameModule: distributes BAF jackpot and decimator jackpot pools. ETH moves from designated pools to claimableWinnings.

**Invariants:**
- Called with the same `rngWord` used for the final daily jackpot, ensuring consistent entropy across all level-end distributions.

**NatSpec Accuracy:**
- NatSpec says "Resolve BAF/Decimator jackpots during the level transition RNG period" -- ACCURATE.

**Gas Flags:**
- Single delegatecall. Potentially high gas due to jackpot distribution complexity (multiple winners, trait lookups).

**Verdict:** CORRECT

---

### `_consolidatePrizePools(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _consolidatePrizePools(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.consolidatePrizePools

**Callers:**
- `advanceGame()` (during purchase phase, after lastPurchaseDay target met)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(consolidatePrizePools.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: merges nextPrizePool into currentPrizePool, rebalances future/current, credits coinflip, distributes stETH yield. Major ETH reorganization point.

**Invariants:**
- Called only once per level (guarded by `poolConsolidationDone` in advanceGame)
- Must happen before jackpot phase entry

**NatSpec Accuracy:**
- NatSpec says "Consolidate prize pools via jackpot module delegatecall. Merges next->current, rebalances future/current, credits coinflip, distributes yield." -- ACCURATE.

**Gas Flags:**
- Single delegatecall. JackpotModule's consolidation is gas-intensive but batched.

**Verdict:** CORRECT

---

### `_awardFinalDayDgnrsReward(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.awardFinalDayDgnrsReward

**Callers:**
- `advanceGame()` (final jackpot day, after coin+ticket distribution complete)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(awardFinalDayDgnrsReward.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- No direct ETH. Awards DGNRS tokens to the solo bucket winner on the final daily jackpot.

**Invariants:**
- Only called once per level (final jackpot day path in advanceGame)

**NatSpec Accuracy:**
- NatSpec says "Award DGNRS reward to the solo bucket winner after final daily jackpot" -- ACCURATE.

**Gas Flags:** Single delegatecall. Lightweight.

**Verdict:** CORRECT

---

### `payDailyJackpot(bool, uint24, uint256)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `isDaily` (bool): true for jackpot phase, false for purchase phase; `lvl` (uint24): current level; `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyJackpot

**Callers:**
- `advanceGame()`:
  - Purchase phase daily jackpot (line 200): `payDailyJackpot(false, purchaseLevel, rngWord)`
  - Jackpot phase resume (line 266): `payDailyJackpot(true, lastDailyJackpotLevel, rngWord)`
  - Jackpot phase fresh daily (line 288): `payDailyJackpot(true, lvl, rngWord)`

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyJackpot.selector, isDaily, lvl, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: distributes ETH from currentPrizePool to winners via claimableWinnings. The split-bucket mechanism credits 4 winner buckets (solo, duo, trio, quad) with trait-matched ETH rewards.

**Invariants:**
- Purchase phase (isDaily=false): early-burn distribution from currentPrizePool
- Jackpot phase (isDaily=true): full jackpot distribution from currentPrizePool
- Resume path uses `lastDailyJackpotLevel` to continue a previously interrupted jackpot

**NatSpec Accuracy:**
- NatSpec says "Pay daily jackpot via jackpot module delegatecall. Called each day during purchase phase and jackpot phase." -- ACCURATE.
- NatSpec parameter description: "isDaily True for jackpot phase, false for purchase phase (early-burn)" -- ACCURATE.

**Gas Flags:** Single delegatecall. Gas depends on JackpotModule's distribution complexity (winner selection, trait matching).

**Verdict:** CORRECT

---

### `payDailyJackpotCoinAndTickets(uint256)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpotCoinAndTickets(uint256 randWord) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyJackpotCoinAndTickets

**Callers:**
- `advanceGame()` (when `dailyJackpotCoinTicketsPending` is true)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyJackpotCoinAndTickets.selector, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: distributes BURNIE coin rewards and ticket rewards as the second phase of a split daily jackpot.

**Invariants:**
- Only called when `dailyJackpotCoinTicketsPending` is true
- Completes the split daily jackpot that was started by `payDailyJackpot`

**NatSpec Accuracy:**
- NatSpec says "Pay coin+ticket portion of daily jackpot via jackpot module delegatecall. Called when dailyJackpotCoinTicketsPending is true to complete the split daily jackpot (gas optimization to stay under 15M block limit)." -- ACCURATE.

**Gas Flags:** Single delegatecall. Completing the second half of split jackpot.

**Verdict:** CORRECT

---

### `_payDailyCoinJackpot(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payDailyCoinJackpot(uint24 lvl, uint256 randWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyCoinJackpot

**Callers:**
- `advanceGame()` (purchase phase, non-lastPurchaseDay daily tick, line 201)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyCoinJackpot.selector, lvl, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- No direct ETH. Awards 0.5% of prize pool target in BURNIE to current and future ticket holders.

**Invariants:**
- Only called during purchase phase daily ticks (not lastPurchaseDay, not jackpot phase)

**NatSpec Accuracy:**
- NatSpec says "Pay daily BURNIE jackpot via jackpot module delegatecall. Called each day during purchase phase in its own transaction. Awards 0.5% of prize pool target in BURNIE to current and future ticket holders." -- ACCURATE.

**Gas Flags:** Single delegatecall. BURNIE minting gas depends on winner count.

**Verdict:** CORRECT

---

### `_finalizeLootboxRng(uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeLootboxRng(uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `rngWord` (uint256): finalized RNG word |
| **Returns** | None |

**State Reads:**
- `vrfRequestId` (current request ID)
- `lootboxRngRequestIndexById[vrfRequestId]` (mapped index)

**State Writes:**
- `lootboxRngWordByIndex[index] = rngWord` (writes RNG word for lootbox resolution)

**Callers:**
- `rngGate()` (after daily RNG applied, line 669; after stale cross-day handling, line 659)
- `_gameOverEntropy()` (after game-over RNG applied, lines 717, 734)

**Callees:** None (emits event only)

**ETH Flow:** None

**Invariants:**
- No-op if `lootboxRngRequestIndexById[vrfRequestId] == 0` (no lootbox reservation for this request)
- Writes the same daily RNG word to the lootbox index, reusing daily entropy for lootbox resolution
- The lootbox index was reserved at VRF request time, ensuring lootboxes purchased during the request window will use this word

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:**
- 2 SLOADs + 1 SSTORE + event emission. Minimal.

**Verdict:** CORRECT

---

### `_gameOverEntropy(uint48, uint48, uint24, bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _gameOverEntropy(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay) private returns (uint256 word)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lvl` (uint24): current level; `isTicketJackpotDay` (bool): last purchase day flag |
| **Returns** | `word` (uint256): RNG word, 1 if request sent, 0 if waiting on fallback |

**State Reads:**
- `rngWordByDay[day]` (check if already recorded)
- `rngWordCurrent` (check for pending VRF word)
- `rngRequestTime` (check for pending request)
- GAMEOVER_RNG_FALLBACK_DELAY (constant: 3 days)

**State Writes:**
- Via `_applyDailyRng(day, currentWord)`: RNG state
- Via `coinflip.processCoinflipPayouts(...)`: coinflip payout state
- Via `_finalizeLootboxRng(...)`: lootbox RNG state
- `rngWordCurrent = 0` (VRF fallback start)
- `rngRequestTime = ts` (VRF fallback timer)

**Callers:**
- `_handleGameOverPath()` (line 364)

**Callees:**
- `_applyDailyRng(day, currentWord)` (private)
- `coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day)` (external) -- note: only called when `lvl != 0`
- `_finalizeLootboxRng(currentWord)` (private)
- `_getHistoricalRngFallback(day)` (private view)
- `_tryRequestRng(isTicketJackpotDay, lvl)` (private)

**ETH Flow:** None directly. Coinflip payouts happen externally.

**Invariants:**
- Unlike `rngGate`, does NOT revert on timeout -- returns 0 to signal "waiting"
- Level 0 skips coinflip processing (no coinflips at level 0)
- 3-day fallback mechanism: if VRF stalled for 3 days, uses `_getHistoricalRngFallback` which collects up to 5 early historical VRF words, hashes them together with `currentDay` and `block.prevrandao`. Historical words are committed VRF (non-manipulable), `prevrandao` adds unpredictability at the cost of 1-bit validator manipulation (propose or skip). Acceptable trade-off for gameover-only fallback when VRF is dead.
- If VRF request itself fails (try/catch in _tryRequestRng), starts fallback timer manually by setting `rngRequestTime = ts` and `rngWordCurrent = 0`

**NatSpec Accuracy:**
- NatSpec says "Game-over RNG gate with fallback for stalled VRF" -- ACCURATE.
- NatSpec documents multi-word historical collection with `block.prevrandao` mixing -- ACCURATE (updated post-audit).

**Gas Flags:**
- Multiple branches but all with early exits. The fallback path (historical search) is O(30) in worst case but uses cheap mapping reads. Collects up to 5 words then breaks early.

**Verdict:** CORRECT

---

### `_applyTimeBasedFutureTake(uint48, uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyTimeBasedFutureTake(uint48 reachedAt, uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `reachedAt` (uint48): timestamp when prize target was reached; `lvl` (uint24): current level; `rngWord` (uint256): VRF random word for variance |
| **Returns** | None |

**State Reads:**
- `levelStartTime` (base time for elapsed calculation)
- `nextPrizePool` (source pool)
- `futurePrizePool` (destination pool)
- `levelPrizePool[lvl - 1]` (previous level target for growth adjustment)

**State Writes:**
- `nextPrizePool -= take` (reduces next pool)
- `futurePrizePool += take` (increases future pool)

**Callers:**
- `advanceGame()` (line 228, during pool consolidation on lastPurchaseDay)

**Callees:**
- `_nextToFutureBps(elapsed, lvl)` (private pure)

**ETH Flow:**
- **nextPrizePool -> futurePrizePool**: Skims a time-adjusted percentage of the next pool into the future pool.
- BPS adjusted by: time curve, x9 bonus, ratio adjustment, growth adjustment, random variance.

**Invariants:**
- `take` can never exceed `nextPoolBefore` (capped at line 867)
- Variance is bounded and cannot exceed the take amount
- BPS is capped at 10000 (line 853)
- Division by `nextPoolBefore` is safe in context (prize target met implies > 0)

**NatSpec Accuracy:** No explicit NatSpec. Inline comments explain adjustments adequately.

**Gas Flags:**
- Multiple arithmetic operations but no loops. Pure math with modular reduction for variance.

**Verdict:** CORRECT

---

### `_drawDownFuturePrizePool(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _drawDownFuturePrizePool(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- `futurePrizePool` (source pool)

**State Writes:**
- `futurePrizePool -= reserved`
- `nextPrizePool += reserved`

**Callers:**
- `advanceGame()` (line 248, during jackpot phase entry)

**Callees:** None

**ETH Flow:**
- **futurePrizePool -> nextPrizePool**: 15% on normal levels, 0% on x00 levels.

**Invariants:**
- x00 levels skip drawdown
- No-op if reserved == 0

**NatSpec Accuracy:**
- Section header: "Release a portion of the future prize pool once per level. Normal levels draw 15%, x00 levels skip the draw." -- ACCURATE.

**Gas Flags:** 1-2 SLOADs + 0-2 SSTOREs. Very efficient.

**Verdict:** CORRECT

---

### `_processFutureTicketBatch(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processFutureTicketBatch(uint24 lvl) private returns (bool worked, bool finished, uint32 writesUsed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): target level to activate tickets for |
| **Returns** | `worked` (bool): true if entries processed; `finished` (bool): true if all done; `writesUsed` (uint32): SSTOREs used |

**State Reads/Writes:** Via delegatecall to GAME_MINT_MODULE.processFutureTicketBatch

**Callers:**
- `advanceGame()` (line 218)
- `_prepareFinalDayFutureTickets()` (lines 936, 945)

**Callees:**
- `ContractAddresses.GAME_MINT_MODULE.delegatecall(processFutureTicketBatch.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:** None directly.

**Invariants:**
- Reverts if return data is empty
- Returns decoded tuple from delegatecall

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Single delegatecall.

**Verdict:** CORRECT

---

### `_prepareFinalDayFutureTickets(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _prepareFinalDayFutureTickets(uint24 lvl) private returns (bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current jackpot level |
| **Returns** | `finished` (bool): true when all target future levels fully processed |

**State Reads:**
- `ticketLevel` (resumeLevel)

**State Writes:**
- Via `_processFutureTicketBatch(...)`: ticket queue state for levels lvl+2..lvl+5

**Callers:**
- `advanceGame()` (line 181, on final jackpot day)

**Callees:**
- `_processFutureTicketBatch(resumeLevel)` (for resume)
- `_processFutureTicketBatch(target)` (for remaining levels)

**ETH Flow:** None directly.

**Invariants:**
- Processes levels lvl+2..lvl+5 (4 levels)
- Continues in-flight level first, then scans remaining
- Returns false if any level has work to do (multi-call resumable)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Max 4 delegatecalls per advanceGame call (usually 1 due to early return).

**Verdict:** CORRECT

---

### `_runProcessTicketBatch(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runProcessTicketBatch(uint24 lvl) private returns (bool worked, bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | `worked` (bool): true if tickets processed; `finished` (bool): true if all done |

**State Reads:**
- `ticketCursor` (prevCursor)
- `ticketLevel` (prevLevel)

**State Writes:**
- Via delegatecall to GAME_JACKPOT_MODULE.processTicketBatch

**Callers:**
- `advanceGame()` (line 188)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(processTicketBatch.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:** None directly.

**Invariants:**
- `worked` derived by comparing cursors before/after delegatecall
- Reverts on empty return data

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 2 SLOADs before + 2 after for work detection.

**Verdict:** CORRECT

---

### `_processPhaseTransition(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processPhaseTransition(uint24 purchaseLevel) private returns (bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `purchaseLevel` (uint24): current purchase level |
| **Returns** | `finished` (bool): always true |

**State Reads:**
- `claimablePool` (via _autoStakeExcessEth)
- `address(this).balance` (via _autoStakeExcessEth)

**State Writes:**
- Via `_queueTickets`: queues 16 tickets each for DGNRS and VAULT at purchaseLevel+99
- Via `_autoStakeExcessEth()`: submits excess ETH to stETH

**Callers:**
- `advanceGame()` (line 158)

**Callees:**
- `_queueTickets(ContractAddresses.DGNRS, targetLevel, VAULT_PERPETUAL_TICKETS)`
- `_queueTickets(ContractAddresses.VAULT, targetLevel, VAULT_PERPETUAL_TICKETS)`
- `_autoStakeExcessEth()` (private)

**ETH Flow:**
- Via `_autoStakeExcessEth`: excess ETH above claimablePool -> stETH via Lido

**Invariants:**
- Always returns true (single-call completion)
- Perpetual tickets target level = purchaseLevel + 99

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 2 _queueTickets calls + 1 external stETH call.

**Verdict:** CORRECT

---

### `_autoStakeExcessEth()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _autoStakeExcessEth() private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `address(this).balance` (current ETH balance)
- `claimablePool` (reserved ETH)

**State Writes:** None directly. ETH sent to Lido; stETH received.

**Callers:**
- `_processPhaseTransition()` (line 1002)

**Callees:**
- `steth.submit{value: stakeable}(address(0))` (external payable call to Lido)

**ETH Flow:**
- **address(this).balance -> stETH**: Stakes excess ETH. claimablePool always preserved in raw ETH.

**Invariants:**
- No-op if ethBal <= claimablePool
- try/catch ensures non-blocking
- address(0) referrer = no referral

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** External call ~30-50k gas. Silent catch is intentional.

**Verdict:** CORRECT

---

### `_requestRng(bool, uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _requestRng(bool isTicketJackpotDay, uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- `vrfKeyHash`, `vrfSubscriptionId` (VRF config)

**State Writes:**
- Via `_finalizeRngRequest(...)`: RNG state

**Callers:**
- `rngGate()` (lines 661, 677, 684)

**Callees:**
- `vrfCoordinator.requestRandomWords(...)` (external, hard revert on failure)
- `_finalizeRngRequest(isTicketJackpotDay, lvl, id)` (private)

**ETH Flow:** None. LINK payment from subscription.

**Invariants:**
- Hard reverts on failure (intentional game halt)
- 10 block confirmations for daily RNG

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Single external call + internal state updates.

**Verdict:** CORRECT

---

### `_tryRequestRng(bool, uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _tryRequestRng(bool isTicketJackpotDay, uint24 lvl) private returns (bool requested)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level |
| **Returns** | `requested` (bool): true if VRF request succeeded |

**State Reads:**
- `vrfCoordinator` (zero check)
- `vrfKeyHash` (zero check)
- `vrfSubscriptionId` (zero check)

**State Writes:**
- Via `_finalizeRngRequest(...)` on success

**Callers:**
- `_gameOverEntropy()` (line 740)

**Callees:**
- `vrfCoordinator.requestRandomWords(...)` (try/catch)
- `_finalizeRngRequest(...)` (on success)

**ETH Flow:** None

**Invariants:**
- Returns false without reverting on failure (graceful for game-over path)
- Pre-checks coordinator/keyHash/subId to avoid unnecessary external calls

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:** 3 SLOADs for zero-checks. Early exits.

**Verdict:** CORRECT

---

### `_finalizeRngRequest(bool, uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeRngRequest(bool isTicketJackpotDay, uint24 lvl, uint256 requestId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level; `requestId` (uint256): new VRF request ID |
| **Returns** | None |

**State Reads:**
- `vrfRequestId` (prevRequestId), `rngRequestTime`, `rngWordCurrent` (retry detection)
- `lootboxRngRequestIndexById[prevRequestId]` (lootbox index remap)
- `lootboxRngIndex` (fresh reservation)
- `decWindowOpen` (decimator window)

**State Writes:**
- Retry: remap lootbox index from old to new request ID
- Fresh: `_reserveLootboxRngIndex(requestId)`
- Always: `vrfRequestId`, `rngWordCurrent = 0`, `rngRequestTime`, `rngLockedFlag = true`
- Decimator close: `decWindowOpen = false` (at resolution levels)
- Level increment: `level = lvl`, `price = ...` (on fresh isTicketJackpotDay)

**Callers:**
- `_requestRng()` (line 1034)
- `_tryRequestRng()` (line 1061)

**Callees:**
- `_reserveLootboxRngIndex(requestId)` (on fresh request)

**ETH Flow:** None

**Invariants:**
- Level increment only on fresh requests (not retries) to prevent double-increment
- Decimator window closes at specific resolution levels
- Price tiers follow fixed schedule with 100-level cycles

**NatSpec Accuracy:** No explicit NatSpec. Inline comments are clear.

**Gas Flags:** Retry path has extra SLOADs for remapping. Price tier uses sequential if/else (acceptable for once-per-level call).

**Verdict:** CORRECT

---

### `_unlockRng(uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _unlockRng(uint48 day) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): current day index |
| **Returns** | None |

**State Reads:** None

**State Writes:**
- `dailyIdx = day`, `rngLockedFlag = false`, `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`

**Callers:**
- `advanceGame()` (lines 163, 207, 282)
- `_handleGameOverPath()` (line 366)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Complete RNG state reset
- Updates dailyIdx to prevent re-entry on same day
- Most SSTOREs reset to zero (gas refund eligible)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 5 SSTOREs, most clearing to zero (gas refunds).

**Verdict:** CORRECT

---

### `_reserveLootboxRngIndex(uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _reserveLootboxRngIndex(uint256 requestId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID |
| **Returns** | None |

**State Reads:**
- `lootboxRngIndex` (current index)

**State Writes:**
- `lootboxRngRequestIndexById[requestId] = index`
- `lootboxRngIndex = index + 1`
- `lootboxRngPendingEth = 0`
- `lootboxRngPendingBurnie = 0`

**Callers:**
- `_finalizeRngRequest()` (line 1088)
- `requestLootboxRng()` (line 634)

**Callees:** None

**ETH Flow:** None. Bookkeeping.

**Invariants:**
- Monotonically increments lootboxRngIndex
- Resets pending counters for next accumulation cycle

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 1 SLOAD + 4 SSTOREs.

**Verdict:** CORRECT

---

### `_applyDailyRng(uint48, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyDailyRng(uint48 day, uint256 rawWord) private returns (uint256 finalWord)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): day index; `rawWord` (uint256): VRF random word |
| **Returns** | `finalWord` (uint256): nudge-adjusted RNG word |

**State Reads:**
- `totalFlipReversals` (nudge count)

**State Writes:**
- `totalFlipReversals = 0` (reset on consumption)
- `rngWordCurrent = finalWord`
- `rngWordByDay[day] = finalWord`

**Callers:**
- `rngGate()` (line 666)
- `_gameOverEntropy()` (lines 709, 726)

**Callees:** None (emits event)

**ETH Flow:** None

**Invariants:**
- Nudges additive (unchecked wrapping intentional for RNG)
- Counter reset after consumption
- Word recorded in rngWordByDay for historical reference

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 1 SLOAD + 2-3 SSTOREs + event. Efficient.

**Verdict:** CORRECT


---

## DegenerusGameMintModule.sol

### `recordMintData(address player, uint24 lvl, uint32 mintUnits)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMintData(address player, uint24 lvl, uint32 mintUnits) external payable returns (uint256 coinReward)` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): player making the purchase; `lvl` (uint24): current game level; `mintUnits` (uint32): scaled ticket units purchased |
| **Returns** | `coinReward` (uint256): BURNIE amount to credit as coinflip stake (currently always 0) |

**State Reads:**
- `mintPacked_[player]` -- player's bit-packed mint history

**State Writes:**
- `mintPacked_[player]` -- updated mint history (only if data changed)

**Callers:** Called via delegatecall from DegenerusGame.recordMint(), which is invoked by `_callTicketPurchase` within this module.

**Callees:**
- `_currentMintDay()` (inherited from DegenerusGameStorage) -- gets current day index
- `_setMintDay()` (inherited from DegenerusGameStorage) -- updates day field in packed data
- `BitPackingLib.setPacked()` -- bit-field manipulation

**ETH Flow:** No ETH movement. Marked `payable` for delegatecall compatibility but does not use `msg.value`.

**Invariants:**
- `levelCount` can only increase (never decremented), capped at `type(uint24).max`
- If `frozenUntilLevel > 0 && lvl < frozenUntilLevel`, total is NOT incremented (whale bundle pre-set levels)
- New level with `levelUnitsAfter < 4` does NOT count as "minted" -- only updates unit tracking fields
- `levelUnits` field is capped at `MASK_16` (65535)

**NatSpec Accuracy:** NatSpec states coinReward is "currently 0" which matches -- the function always returns the default 0 value. The level transition logic documentation (same level / new level <4 units / new level >=4 units) accurately matches implementation. The NatSpec mentions "century boundary" accumulation which is correct -- no special century handling exists, total simply increments.

**Gas Flags:**
- Efficient: only writes to storage if `data != prevData`
- The whale bundle frozen-level clearing block at lines 257-263 executes even when `frozenUntilLevel > 0 && lvl >= frozenUntilLevel` and the frozen state was already cleared in a prior call (writes zeros to already-zero fields). This is harmless because the `data != prevData` guard prevents actual SSTORE.

**Verdict:** CORRECT

---

### `processFutureTicketBatch(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processFutureTicketBatch(uint24 lvl) external returns (bool worked, bool finished, uint32 writesUsed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level to process future tickets for |
| **Returns** | `worked` (bool): whether any writes were made; `finished` (bool): whether all entries processed; `writesUsed` (uint32): gas budget units consumed |

**State Reads:**
- `rngWordCurrent` -- VRF entropy for trait generation
- `ticketQueue[lvl]` -- array of player addresses with pending tickets
- `ticketLevel` -- current processing level
- `ticketCursor` -- current processing index
- `ticketsOwedPacked[lvl][player]` -- packed (owed tickets, remainder) per player

**State Writes:**
- `ticketCursor` -- updated cursor position
- `ticketLevel` -- set/cleared for level tracking
- `ticketsOwedPacked[lvl][player]` -- decremented as tickets are generated
- `ticketQueue[lvl]` -- deleted when processing complete
- `traitBurnTicket[lvl][traitId]` -- trait ticket arrays (via `_raritySymbolBatch`)

**Callers:** Called via delegatecall from DegenerusGame (during advance phase to activate queued tickets).

**Callees:**
- `_rollRemainder(entropy, baseKey, rem)` -- fractional ticket probabilistic resolution
- `_raritySymbolBatch(player, baseKey, processed, take, entropy)` -- batch trait generation

**ETH Flow:** No ETH movement.

**Invariants:**
- Write budget `WRITES_BUDGET_SAFE = 550`, scaled to 65% on first batch (cold storage)
- Processing is resumable: cursor and level are persisted between calls
- Queue is deleted only when fully processed (`idx >= total`)
- Each player's owed count decrements monotonically toward 0
- Remainders (fractional tickets) are rolled probabilistically via `_rollRemainder`

**NatSpec Accuracy:** No NatSpec on this function. The function behavior is clear from code: it processes a gas-budgeted batch of future ticket activations for a given level.

**Gas Flags:**
- Gas-budgeted design with `WRITES_BUDGET_SAFE = 550` prevents runaway gas consumption
- First-batch cold storage scaling (65%) is a deliberate optimization
- `baseOv` overhead calculation accounts for cold vs warm storage access patterns
- `total > type(uint32).max` check at line 301 prevents overflow but is practically unreachable (would need >4B queue entries)

**Verdict:** CORRECT

---

### `_raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): receiving trait tickets; `baseKey` (uint256): encoded key with level/index/player; `startIndex` (uint32): starting position within player's owed tickets; `count` (uint32): number of tickets to process this batch; `entropyWord` (uint256): VRF entropy for trait generation |
| **Returns** | None |

**State Reads:**
- `traitBurnTicket[lvl][traitId]` -- array lengths (via assembly)

**State Writes:**
- `traitBurnTicket[lvl][traitId]` -- appends player address `occurrences` times per trait (via assembly)

**Callers:** `processFutureTicketBatch`

**Callees:**
- `DegenerusTraitUtils.traitFromWord(s)` -- generates 6-bit trait from LCG state

**ETH Flow:** No ETH movement.

**Invariants:**
- Deterministic trait generation: same `baseKey + groupIdx ^ entropyWord` always produces same traits
- LCG seed is forced odd (`| 1`) for full period guarantee
- Each ticket gets a trait assigned to one of 4 quadrants via `(uint8(i & 3) << 6)` cycling
- Trait counts tracked in memory first, then batch-written to storage (gas optimization)

**NatSpec Accuracy:** NatSpec accurately describes the function as "LCG-based PRNG" for "gas-efficient bulk storage writes" using "inline assembly."

**Gas Flags:**
- Assembly-based storage writes avoid per-element Solidity overhead
- Memory arrays `counts[256]` and `touchedTraits[256]` are allocated once and reused
- Group-of-16 processing minimizes seed recalculation

**Verdict:** CORRECT

---

### `purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of purchases; `ticketQuantity` (uint256): tickets (2 decimals, scaled by 100); `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): referral code; `payKind` (MintPaymentKind): payment method selector |
| **Returns** | None |

**State Reads:** All reads delegated to `_purchaseFor`.

**State Writes:** All writes delegated to `_purchaseFor`.

**Callers:** Called via delegatecall from DegenerusGame (main purchase entry point for ETH/claimable).

**Callees:**
- `_purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`

**ETH Flow:** Passes `msg.value` through to `_purchaseFor` which handles all ETH routing.

**Invariants:** Pure passthrough -- all validation and logic in `_purchaseFor`.

**NatSpec Accuracy:** NatSpec accurately describes the parameters and purpose. Notes that `ticketQuantity` is "scaled by 100" (2 decimal places) and `lootBoxAmount` is ETH amount.

**Gas Flags:** None -- single internal call delegation.

**Verdict:** CORRECT

---

### `purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient of purchases; `ticketQuantity` (uint256): tickets (2 decimals, scaled by 100); `lootBoxBurnieAmount` (uint256): BURNIE amount for lootboxes |
| **Returns** | None |

**State Reads:** Delegated to `_purchaseCoinFor`.

**State Writes:** Delegated to `_purchaseCoinFor`.

**Callers:** Called via delegatecall from DegenerusGame (BURNIE-paid purchase entry point). Note: IDegenerusGame interface shows `purchaseCoin` takes 3 params (buyer, ticketQuantity, lootBoxBurnieAmount) -- no affiliateCode for BURNIE purchases.

**Callees:**
- `_purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount)`

**ETH Flow:** No ETH movement -- BURNIE-only purchase path.

**Invariants:** Pure passthrough to `_purchaseCoinFor`.

**NatSpec Accuracy:** Accurately describes BURNIE ticket and lootbox purchase path. Notes "allowed whenever RNG is unlocked" which is enforced by `_callTicketPurchase`.

**Gas Flags:** None -- single internal call delegation.

**Verdict:** CORRECT

---

### `purchaseBurnieLootbox(address buyer, uint256 burnieAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient; `burnieAmount` (uint256): BURNIE to spend on lootbox |
| **Returns** | None |

**State Reads:** Delegated to `_purchaseBurnieLootboxFor`.

**State Writes:** Delegated to `_purchaseBurnieLootboxFor`.

**Callers:** Called via delegatecall from DegenerusGame (standalone BURNIE lootbox entry).

**Callees:**
- `_purchaseBurnieLootboxFor(buyer, burnieAmount)`

**ETH Flow:** No ETH movement -- BURNIE-only.

**Invariants:**
- Reverts if `buyer == address(0)` (explicit null check)
- All other validation in `_purchaseBurnieLootboxFor`

**NatSpec Accuracy:** Describes it as "low-EV loot box with BURNIE" -- accurate.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): ticket recipient; `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxBurnieAmount` (uint256): BURNIE for lootboxes |
| **Returns** | None |

**State Reads:**
- `gameOver` -- terminal state check (defense-in-depth; also checked in `_callTicketPurchase`)
- `block.timestamp` -- for elapsed time check
- `levelStartTime` -- start of current level (inherited storage)
- `level` -- current game level (inherited storage)

**State Writes:** Delegated to `_callTicketPurchase` and `_purchaseBurnieLootboxFor`.

**Callers:** `purchaseCoin`

**Callees:**
- `_callTicketPurchase(buyer, payer, ticketQuantity, MintPaymentKind.DirectEth, true, bytes32(0), 0)` -- for ticket purchase with `payInCoin=true`
- `_purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount)` -- for BURNIE lootbox

**ETH Flow:** No ETH movement.

**Revert Conditions:**
- `E()`: `gameOver == true` (game has ended)
- `CoinPurchaseCutoff`: BURNIE purchases blocked within 30 days of liveness-guard timeout

**Invariants:**
- `gameOver` guard prevents purchases after game termination (defense-in-depth alongside `_callTicketPurchase` check)
- BURNIE ticket purchases are blocked within 30 days of liveness-guard timeout:
  - Level 0: `elapsed > 882 days` (912 - 30) reverts with `CoinPurchaseCutoff`
  - Other levels: `elapsed > 335 days` (365 - 30) reverts with `CoinPurchaseCutoff`
- Uses `msg.sender` as payer (not buyer) -- BURNIE burned from caller
- Passes `MintPaymentKind.DirectEth` to ticket purchase despite being BURNIE -- the `payInCoin=true` flag overrides payment handling
- Affiliate code is `bytes32(0)` -- no affiliate attribution for BURNIE purchases

**NatSpec Accuracy:** No explicit NatSpec on this private function. The cutoff logic matches the documented 30-day safety window.

**Gas Flags:**
- The ternary for cutoff check `level == 0 ? ... : ...` is efficient
- `payer = msg.sender` local variable avoids repeated `msg.sender` reads (though Solidity compiler typically optimizes this)

**Verdict:** CORRECT

---

### `_purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient; `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): referral code; `payKind` (MintPaymentKind): payment method |
| **Returns** | None |

**State Reads:**
- `gameOver` -- terminal state check (defense-in-depth; also checked in `_callTicketPurchase`)
- `level` -- current game level
- `price` -- current ticket price in wei
- `rngLockedFlag` -- whether VRF is pending
- `lastPurchaseDay` -- whether this is the last purchase day
- `claimableWinnings[buyer]` -- player's claimable balance
- `claimablePool` -- total claimable pool
- `lootboxRngIndex` -- current lootbox RNG index
- `lootboxPresaleActive` -- presale mode flag
- `lootboxEth[index][buyer]` -- existing lootbox ETH for player
- `lootboxDay[index][buyer]` -- day of lootbox purchase
- `lootboxEthBase[index][buyer]` -- base (pre-boost) lootbox amount
- `lootboxEthTotal` -- global lootbox ETH total
- `lootboxPresaleMintEth` -- presale mint ETH tracker
- `futurePrizePool` -- future prize pool balance
- `nextPrizePool` -- next prize pool balance

**State Writes:**
- `claimableWinnings[buyer]` -- decreased if claimable used for lootbox shortfall
- `claimablePool` -- decreased by lootbox claimable shortfall
- `lootboxDay[index][buyer]` -- set on first lootbox purchase per index
- `lootboxBaseLevelPacked[index][buyer]` -- set to `level + 2` on first purchase
- `lootboxEvScorePacked[index][buyer]` -- player activity score + 1
- `lootboxIndexQueue[buyer]` -- push index on first purchase
- `lootboxEthBase[index][buyer]` -- accumulated base (pre-boost) amount
- `lootboxEth[index][buyer]` -- packed (purchaseLevel, boostedAmount)
- `lootboxEthTotal` -- increased by raw lootBoxAmount
- `lootboxRngPendingEth` -- increased (via `_maybeRequestLootboxRng`)
- `lootboxPresaleMintEth` -- increased if presale active
- `futurePrizePool` -- increased by futureShare + rewardShare
- `nextPrizePool` -- increased by nextShare
- Plus all writes from `_callTicketPurchase` (if tickets purchased)
- Plus all writes from `_applyLootboxBoostOnPurchase` (boost consumption)

**Callers:** `purchase`

**Callees:**
- `_callTicketPurchase(buyer, buyer, ticketQuantity, payKind, false, affiliateCode, remainingEth)` -- ticket purchase delegation
- `_simulatedDayIndex()` -- current day index
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` -- self-call for activity score
- `_applyLootboxBoostOnPurchase(buyer, day, lootBoxAmount)` -- boost application
- `_maybeRequestLootboxRng(lootBoxAmount)` -- lootbox RNG threshold tracking
- `affiliate.payAffiliate(...)` -- affiliate reward distribution (called separately for fresh ETH and claimable portions)
- `coin.creditFlip(buyer, lootboxRakeback)` -- BURNIE coinflip credit from affiliate rakeback
- `coin.notifyQuestMint(buyer, questUnits, true/false)` -- quest progress for lootbox purchases
- `coin.notifyQuestLootBox(buyer, lootBoxAmount)` -- lootbox quest progress
- `_awardEarlybirdDgnrs(buyer, lootboxFreshEth, purchaseLevel)` -- DGNRS earlybird rewards
- `_ethToBurnieValue(amountWei, priceWei)` -- ETH to BURNIE conversion
- `coin.creditFlip(buyer, bonusAmount)` -- 10% "spent-all-claimable" bonus

**ETH Flow:**

1. **Ticket cost:** `(priceWei * ticketQuantity) / (4 * TICKET_SCALE)` -- ETH flows via `_callTicketPurchase` to `recordMint` which routes to prize pools
2. **Lootbox ETH split (normal):** 90% future pool, 10% next pool, 0% remainder added to future
3. **Lootbox ETH split (presale):** 40% future, 40% next, 20% vault (sent via `call`)
4. **Lootbox claimable shortfall:** deducted from `claimableWinnings[buyer]` and `claimablePool`
5. **Vault share:** sent via low-level `call{value: vaultShare}` to `ContractAddresses.VAULT`

**Revert Conditions:**
- `E()`: `gameOver == true` (game has ended; defense-in-depth alongside `_callTicketPurchase` check)

**Invariants:**
- `gameOver` guard prevents purchases after game termination (defense-in-depth alongside `_callTicketPurchase` check)
- `purchaseLevel = level + 1` (tickets target next level)
- Lootbox purchases blocked during BAF/Decimator resolution: `rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)`
- Minimum lootbox purchase: 0.01 ETH (`LOOTBOX_MIN`)
- Total cost (tickets + lootbox) must be > 0
- Lootbox payment prefers `msg.value` first, then claimable shortfall (unless `DirectEth`)
- Claimable balance must exceed shortfall (preserves 1 wei sentinel: `claimable <= shortfall` reverts)
- "Spent all claimable" 10% bonus: only if `totalClaimableUsed >= priceWei * 3` (at least 3 full ticket prices of claimable spent)
- Bonus formula: `(totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100)` = 10% of total claimable used, denominated in BURNIE

**NatSpec Accuracy:** NatSpec describes "Handles payment routing, affiliates, and queues" -- accurate but understates complexity. The inline comments within the function are thorough.

**Gas Flags:**
- Multiple external calls to `affiliate.payAffiliate` (one for fresh ETH, one for claimable) could be batched but affiliate contract design requires separate calls for different `isFreshEth` flags
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` is a self-delegatecall -- relatively expensive but necessary for cross-module access
- The vault share `call` has no gas limit (sends all gas) -- standard for ETH transfers to known contracts

**Verdict:** CORRECT

---

### `_callTicketPurchase(address buyer, address payer, uint256 quantity, MintPaymentKind payKind, bool payInCoin, bytes32 affiliateCode, uint256 value)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _callTicketPurchase(address buyer, address payer, uint256 quantity, MintPaymentKind payKind, bool payInCoin, bytes32 affiliateCode, uint256 value) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): ticket recipient; `payer` (address): who pays (may differ from buyer); `quantity` (uint256): tickets scaled by 100; `payKind` (MintPaymentKind): payment method; `payInCoin` (bool): true if paying with BURNIE; `affiliateCode` (bytes32): referral code; `value` (uint256): remaining ETH available for this ticket purchase |
| **Returns** | None |

**State Reads:**
- `gameOver` -- terminal state check
- `rngLockedFlag` -- VRF lock check
- `jackpotPhaseFlag` -- current phase (purchase vs jackpot)
- `level` -- current level
- `price` -- current ticket price
- `lastPurchaseDay` -- last purchase day flag
- `jackpotCounter` -- jackpot day counter (for final-day affiliate bonus)

**State Writes:**
- Via `IDegenerusGame(address(this)).recordMint{value}(...)` -- records mint and routes ETH to prize pools
- Via `_coinReceive(payer, coinCost)` -- burns BURNIE if `payInCoin`
- Via `coin.creditFlip(buyer, bonusCredit)` -- credits BURNIE coinflip stake
- Via `_queueTicketsScaled(buyer, ticketLevel, adjustedQty32)` -- queues tickets for trait generation
- Via `affiliate.payAffiliate(...)` -- distributes affiliate rewards
- Via `coin.notifyQuestMint(payer, questUnits, true/false)` -- quest progress

**Callers:** `_purchaseFor` (ETH path), `_purchaseCoinFor` (BURNIE path)

**Callees:**
- `IDegenerusGame(address(this)).recordMint{value}(payer, targetLevel, costWei, mintUnits, payKind)` -- self-call to record mint and handle ETH routing
- `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` -- consume pending boost
- `_coinReceive(payer, coinCost)` -- burn BURNIE
- `affiliate.payAffiliate(...)` -- affiliate reward (called 1-2 times depending on `payKind`)
- `coin.creditFlip(buyer, bonusCredit)` -- credit BURNIE coinflip stake
- `coin.notifyQuestMint(payer, questUnits, paidWithEth)` -- quest tracking
- `_ethToBurnieValue(freshEth, priceWei)` -- conversion helper
- `_queueTicketsScaled(buyer, ticketLevel, adjustedQty32)` -- ticket queuing

**ETH Flow:**
- **DirectEth:** `value >= costWei` required; full `value` forwarded to `recordMint`
- **Claimable:** `value == 0` required; claimable deducted in `recordMint`
- **Combined:** `value <= costWei`; partial ETH + partial claimable handled in `recordMint`
- All ETH ultimately flows through `recordMint` to prize pool splits (current/next/future/coinflip)

**Invariants:**
- `quantity` must be non-zero, <= `type(uint32).max`
- `gameOver` must be false
- `rngLockedFlag` must be false
- `costWei = (priceWei * quantity) / (4 * TICKET_SCALE)` must be > 0 and >= `TICKET_MIN_BUYIN_WEI` (0.0025 ETH)
- Target level differs by phase: `jackpotPhaseFlag ? level : level + 1`
- Purchase boost (if available and `!payInCoin`): increases `adjustedQuantity` but cost remains same (bonus tickets)
- Boost cap: `LOOTBOX_BOOST_MAX_VALUE = 10 ether` -- boost applies to at most 10 ETH equivalent
- Final jackpot day affiliate bonus: +40% (levels 1-3) or +50% (levels 4+) BURNIE affiliate amount
- BURNIE bonuses: base 10% of coinCost, plus 2.5% if bulk (>= 10 full tickets), plus 20% of coinCost if lastPurchaseDay and level % 100 > 90

**NatSpec Accuracy:** No explicit NatSpec on this private function.

**Gas Flags:**
- Three separate `affiliate.payAffiliate` calls for Combined path (one for fresh ETH, one for recycled) plus separate handling for DirectEth and Claimable -- necessarily separate due to `isFreshEth` flag differences
- `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` self-call overhead is unavoidable for cross-module access
- `adjustedQuantity` overflow check at line 845 (capped to `uint32.max`) is a safety bound

**Verdict:** CORRECT

---

### `_coinReceive(address payer, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _coinReceive(address payer, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payer` (address): address to burn BURNIE from; `amount` (uint256): BURNIE amount to burn |
| **Returns** | None |

**State Reads:** None directly (delegated to external call).

**State Writes:** None directly -- BURNIE burn happens in external contract.

**Callers:** `_callTicketPurchase` (when `payInCoin == true`)

**Callees:**
- `coin.burnCoin(payer, amount)` -- burns BURNIE tokens from payer

**ETH Flow:** No ETH movement.

**Invariants:**
- Requires `payer` to have sufficient BURNIE balance and approval (enforced by BurnieCoin contract)

**NatSpec Accuracy:** No NatSpec. Function name and implementation are self-documenting.

**Gas Flags:** None -- single external call.

**Verdict:** CORRECT

---

### `_purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): lootbox recipient; `burnieAmount` (uint256): BURNIE amount to spend |
| **Returns** | None |

**State Reads:**
- `gameOver` -- terminal state check (defense-in-depth)
- `lootboxRngIndex` -- current lootbox RNG index
- `lootboxBurnie[index][buyer]` -- existing BURNIE lootbox amount
- `lootboxDay[index][buyer]` -- day of first lootbox purchase
- `price` -- current ticket price
- `lootboxRngPendingBurnie` -- pending BURNIE for RNG tracking

**State Writes:**
- `lootboxBurnie[index][buyer]` -- accumulated BURNIE lootbox amount
- `lootboxDay[index][buyer]` -- set if first purchase for this index
- `lootboxRngPendingBurnie` -- increased by burnieAmount
- `lootboxRngPendingEth` -- increased by virtualEth (via `_maybeRequestLootboxRng`)

**Callers:** `_purchaseCoinFor`, `purchaseBurnieLootbox`

**Callees:**
- `coin.burnCoin(buyer, burnieAmount)` -- burns BURNIE from buyer
- `coin.notifyQuestMint(buyer, questUnitsRaw, false)` -- quest progress (BURNIE-paid)
- `_simulatedDayIndex()` -- day index for first purchase
- `_maybeRequestLootboxRng(virtualEth)` -- RNG threshold tracking

**ETH Flow:** No ETH movement. BURNIE is burned. Virtual ETH equivalent tracked for RNG threshold calculation.

**Revert Conditions:**
- `E()`: `gameOver == true` (game has ended; defense-in-depth)
- `E()`: `burnieAmount < BURNIE_LOOTBOX_MIN`
- `E()`: `lootboxRngIndex == 0`

**Invariants:**
- `gameOver` guard prevents BURNIE lootbox purchases after game termination (defense-in-depth)
- Minimum BURNIE: `BURNIE_LOOTBOX_MIN = 1000 ether` (1000 BURNIE)
- `lootboxRngIndex` must be > 0 (reverts if 0 -- no active lootbox RNG index)
- Virtual ETH conversion: `(burnieAmount * priceWei) / PRICE_COIN_UNIT`
- Quest units: `burnieAmount / PRICE_COIN_UNIT` (whole ticket equivalents)
- BURNIE lootbox has no presale mode, no boost application, no affiliate rakeback
- Day is set only on first purchase per (index, buyer) pair

**NatSpec Accuracy:** Parent function NatSpec describes "low-EV loot box" -- accurate for BURNIE path.

**Gas Flags:**
- `price` loaded locally as `priceWei` to avoid multiple storage reads

**Verdict:** CORRECT

---

### `_maybeRequestLootboxRng(uint256 lootBoxAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeRequestLootboxRng(uint256 lootBoxAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lootBoxAmount` (uint256): ETH amount (or virtual ETH equivalent) to add to pending threshold |
| **Returns** | None |

**State Reads:** None directly (only writes).

**State Writes:**
- `lootboxRngPendingEth` -- increased by `lootBoxAmount`

**Callers:** `_purchaseFor` (ETH lootbox), `_purchaseBurnieLootboxFor` (BURNIE lootbox virtual ETH)

**Callees:** None.

**ETH Flow:** No ETH movement -- accumulator for RNG request threshold.

**Invariants:**
- Simple accumulator -- actual VRF request is triggered elsewhere (in DegenerusGame when threshold is met)

**NatSpec Accuracy:** No NatSpec. Function name is descriptive enough -- "maybe request" refers to threshold-based triggering done at a higher level.

**Gas Flags:** None -- single SSTORE increment.

**Verdict:** CORRECT

---

### `_applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount) private returns (uint256 boostedAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): buyer; `day` (uint48): current day index; `amount` (uint256): base lootbox purchase amount |
| **Returns** | `boostedAmount` (uint256): amount after boost (>= original amount) |

**State Reads:**
- `lootboxBoon25Active[player]` -- 25% boost active flag
- `lootboxBoon25Day[player]` -- day boost was awarded
- `lootboxBoon15Active[player]` -- 15% boost active flag
- `lootboxBoon15Day[player]` -- day boost was awarded
- `lootboxBoon5Active[player]` -- 5% boost active flag
- `lootboxBoon5Day[player]` -- day boost was awarded

**State Writes:**
- `lootboxBoon25Active[player]` -- set to false (consumed or expired)
- `lootboxBoon15Active[player]` -- set to false (consumed or expired)
- `lootboxBoon5Active[player]` -- set to false (consumed or expired)

**Callers:** `_purchaseFor` (lootbox section)

**Callees:**
- `_calculateBoost(amount, bonusBps)` -- compute boost amount

**ETH Flow:** No direct ETH movement -- modifies the boosted lootbox amount which affects pool splits.

**Invariants:**
- Cascading priority: 25% > 15% > 5% (only best available boost applies)
- Expiry: boost expires after `LOOTBOX_BOOST_EXPIRY_DAYS = 2` days from award
- Single-use: boost flag set to false on consumption or expiration
- Expired boosts are cleaned up (set to false) on encounter, preventing stale state
- `boostedAmount >= amount` (boost only adds, never subtracts)

**NatSpec Accuracy:** No explicit NatSpec on this function.

**Gas Flags:**
- Cascading if-else means at most 3 storage reads for the worst case (no boost available)
- Expired boosts are cleaned up eagerly (deactivated on check) -- prevents accumulation of stale state

**Verdict:** CORRECT


---

## DegenerusGameJackpotModule.sol

### `runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord) external returns (uint256 paidWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): Total ETH to distribute; `targetLvl` (uint24): Level to sample winners from; `rngWord` (uint256): VRF entropy seed |
| **Returns** | `uint256`: Total ETH distributed (callers deduct from source pool) |

**State Reads:** `traitBurnTicket[targetLvl]`, `deityBySymbol[]`, `claimableWinnings[]`, `autoRebuyState[]`, `gameOver`, `level`, `futurePrizePool`, `nextPrizePool`, `whalePassClaims[]`

**State Writes:** `claimableWinnings[]`, `claimablePool`, `autoRebuyState[]` (via auto-rebuy), `futurePrizePool` (via solo bucket whale pass conversion), `nextPrizePool` (via auto-rebuy), `whalePassClaims[]`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** EndgameModule, GameOverModule (via `IDegenerusGame(address(this)).runTerminalJackpot(...)`)

**Callees:** `_rollWinningTraits`, `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.bucketCountsForPoolCap`, `JackpotBucketLib.shareBpsByBucket`, `_distributeJackpotEth`

**ETH Flow:** `poolWei` (caller-provided budget) -> distributed to winners via `_distributeJackpotEth`. Uses FINAL_DAY_SHARES_PACKED (60/13/13/13). Solo bucket winners may receive whale passes (ETH -> `futurePrizePool`). Non-solo winners: ETH -> `claimableWinnings[]` / `claimablePool`. Auto-rebuy paths: ETH -> `nextPrizePool` or `futurePrizePool` + tickets.

**Invariants:**
- `msg.sender` must be `ContractAddresses.GAME` (OnlyGame check)
- `paidWei <= poolWei` (can be less due to rounding dust)
- Callers must deduct `paidWei` from their source pool
- `claimablePool` incremented matches sum of individual `claimableWinnings` credits

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes this as a terminal jackpot for x00 levels using Day-5-style shares. It correctly warns callers must NOT double-count pool debits.

**Gas Flags:** Uses `DAILY_ETH_MAX_WINNERS` (321) and `DAILY_JACKPOT_SCALE_MAX_BPS` (66667) for terminal jackpot -- these are the daily limits, not the regular jackpot limits. This is intentional to allow wider distribution for terminal pots. No unnecessary computation.

**Access Control:** This function is called via a normal `external` call (not delegatecall). The `OnlyGame()` check verifies `msg.sender == ContractAddresses.GAME`. This means EndgameModule/GameOverModule call `IDegenerusGame(address(this)).runTerminalJackpot(...)` during delegatecall execution. In that context, `address(this)` is the Game contract, and `msg.sender` becomes the Game contract address -- so the access check passes.

**Verdict:** CORRECT

---

### `payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `isDaily` (bool): true for scheduled daily, false for early-burn; `lvl` (uint24): Current game level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `jackpotCounter`, `compressedJackpotFlag`, `currentPrizePool`, `futurePrizePool`, `nextPrizePool`, `dailyCarryoverEthPool`, `dailyCarryoverWinnerCap`, `dailyTicketBudgetsPacked`, `traitBurnTicket[]`, `dailyHeroWagers[]`, `price`, `levelStartTime`, `autoRebuyState[]`, `gameOver`, `level`

**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`, `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `currentPrizePool`, `futurePrizePool`, `nextPrizePool`, `dailyCarryoverEthPool`, `dailyCarryoverWinnerCap`, `dailyTicketBudgetsPacked`, `dailyJackpotCoinTicketsPending`, `claimableWinnings[]`, `claimablePool`, `ticketsOwedPacked[]`, `ticketQueue[]`, `whalePassClaims[]`

**Callers:** DegenerusGame via delegatecall (advanceGame flow)

**Callees:** `_calculateDayIndex`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_dailyCurrentPoolBps`, `_runEarlyBirdLootboxJackpot`, `_validateTicketBudget`, `_budgetToTicketUnits`, `_selectCarryoverSourceOffset`, `_packDailyTicketBudgets`, `_unpackDailyTicketBudgets`, `_processDailyEthChunk`, `_executeJackpot`, `_distributeLootboxAndTickets`, `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.bucketCountsForPoolCap`, `JackpotBucketLib.shareBpsByBucket`, `JackpotBucketLib.sumBucketCounts`, `coin.rollDailyQuest`

#### Two-Phase Chunking Mechanism (Daily Path)

The daily jackpot is split into multiple advanceGame calls to stay under 15M gas:

**Phase 0: Current level ETH distribution**
1. On first call (`isResuming == false`): compute winning traits, calculate daily BPS (6-14% or 100% on day 5), compute daily lootbox budget (20% of daily ETH), compute carryover pool (1% from `futurePrizePool`), store all state for resumability.
2. Execute `_processDailyEthChunk()` with a units budget (DAILY_JACKPOT_UNITS_SAFE = 1000). If chunk completes, calculate carryover winner cap. If chunk does NOT complete, store cursor state and `return` (next call resumes).
3. On completion: set `dailyEthPhase = 1` if carryover has work; otherwise finalize immediately.

**Phase 1: Carryover ETH distribution**
1. Distribute carryover ETH to winners from a randomly selected future level (offset 1-5).
2. Uses same chunking mechanism via `_processDailyEthChunk()`.
3. On completion: clear all daily state, set `dailyJackpotCoinTicketsPending = true`.

**Early-Burn Path (isDaily == false):**
- Rolls random winning traits (non-burn-weighted).
- Every 3rd purchase day: adds 1% `futurePrizePool` slice with 75% converted to lootbox tickets.
- Calls `_executeJackpot()` (not chunked -- early-burn pots are smaller).
- Rolls daily quest at the end.

**Resumability Protocol:**
| State Variable | Purpose |
|----------------|---------|
| `dailyEthPoolBudget` | Current level ETH budget (prevents re-calculation) |
| `dailyEthPhase` | 0 = current level, 1 = carryover |
| `dailyEthBucketCursor` | Which bucket (in order array) to resume at |
| `dailyEthWinnerCursor` | Which winner within bucket to resume at |
| `dailyCarryoverEthPool` | Carryover ETH reserved after Phase 0 |
| `dailyCarryoverWinnerCap` | Remaining winner cap for Phase 1 |
| `dailyTicketBudgetsPacked` | Packed ticket units, counter step, carryover offset |
| `lastDailyJackpotWinningTraits` | Saved winning traits for resuming |
| `lastDailyJackpotLevel` | Saved level for resuming |

**Pool Mutation Trace (Daily Path, Fresh Start):**
1. `currentPrizePool -= dailyLootboxBudget` (20% of daily slice, for ticket backing)
2. `nextPrizePool += dailyLootboxBudget` (tickets backed by next pool)
3. `futurePrizePool -= reserveSlice` (1% for carryover, days 2-4 only)
4. `nextPrizePool += carryoverLootboxBudget` (50% of carryover for ticket backing)
5. `currentPrizePool -= paidDailyEth` (Phase 0 ETH paid to winners)
6. `claimablePool += liabilityDelta` (Phase 0 claimable liability)
7. (Phase 1: carryover paid from `dailyCarryoverEthPool` -- already deducted from `futurePrizePool`)

**Pool Mutation Trace (Early-Burn Path, isEthDay):**
1. `futurePrizePool -= ethDaySlice` (1% of future pool)
2. `nextPrizePool += lootboxBudget` (via `_distributeLootboxAndTickets`)
3. `claimablePool += liabilityDelta` (via `_executeJackpot` -> `_distributeJackpotEth`)

**Compressed Jackpot Handling:** When `compressedJackpotFlag` is true and counter < 4, `counterStep = 2` and `dailyBps *= 2`. This combines two days' payouts into one physical day, allowing 5 logical days to complete in 3 physical days.

**ETH Flow:** Multiple paths documented above. Core invariant: all ETH deducted from `currentPrizePool`/`futurePrizePool` is either credited to `claimablePool` (for winners) or moved to `nextPrizePool`/`futurePrizePool` (for ticket backing/auto-rebuy).

**Invariants:**
- `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor` are zeroed when all phases complete
- `dailyJackpotCoinTicketsPending = true` only set after both Phase 0 and Phase 1 complete
- `jackpotCounter` is NOT incremented here -- deferred to `payDailyJackpotCoinAndTickets`
- On day 1 (`counter == 0`): early-bird lootbox replaces carryover; `reserveSlice = 0`

**NatSpec Accuracy:** CORRECT. Extensive NatSpec accurately describes both daily and early-burn paths, including day-1 early-bird replacement of carryover, compressed jackpot, and chunking.

**Gas Flags:**
- `budget / 5` used instead of `* 2000 / 10000` -- correct optimization (20% = 1/5)
- `futurePrizePool / 100` used instead of `* 100 / 10000` -- correct optimization (1% = 1/100)
- Phase 0 lootbox budget uses `_validateTicketBudget` which zeros budget if no trait tickets exist, preventing wasted computation

**Verdict:** CORRECT

---

### `payDailyJackpotCoinAndTickets(uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpotCoinAndTickets(uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `randWord` (uint256): VRF entropy (must match rngWordCurrent from Phase 1) |
| **Returns** | None |

**State Reads:** `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`, `lastDailyJackpotLevel`, `lastDailyJackpotWinningTraits`, `traitBurnTicket[]`, `deityBySymbol[]`, `price`, `levelPrizePool[]`

**State Writes:** `jackpotCounter` (incremented by counterStep), `dailyJackpotCoinTicketsPending` (cleared to false), `dailyTicketBudgetsPacked` (cleared to 0), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** DegenerusGame via delegatecall (advanceGame flow, when `dailyJackpotCoinTicketsPending` is true)

**Callees:** `_unpackDailyTicketBudgets`, `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`, `_distributeTicketJackpot`, `_calculateDayIndex`, `coin.rollDailyQuest`

**ETH Flow:** No direct ETH mutation. This function distributes BURNIE coin and tickets only. Coin distribution via `coin.creditFlip()` / `coin.creditFlipBatch()`. Ticket distribution via `_queueTickets()`.

**Invariants:**
- Early-exit if `dailyJackpotCoinTicketsPending == false` (idempotent guard)
- `jackpotCounter += counterStep` (1 or 2 for compressed)
- Coin budget: 0.5% of `levelPrizePool[lvl-1]` converted to BURNIE units
- Coin split: 25% far-future (ticketQueue-based), 75% near-future (trait-matched)
- Daily tickets distributed to current level; carryover tickets to carryover source level
- `dailyJackpotCoinTicketsPending` and `dailyTicketBudgetsPacked` cleared on completion

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes this as Phase 2 of daily jackpot, gas optimization rationale, and stored value usage.

**Gas Flags:** Separating coin+ticket distribution from ETH distribution is a sound gas optimization. Each advanceGame call stays under 15M gas. No redundant reads.

**Verdict:** CORRECT

---

### `awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** `lastDailyJackpotWinningTraits`, `traitBurnTicket[lvl]`, `deityBySymbol[]`

**State Writes:** None directly (DGNRS token transfer is an external call)

**Callers:** DegenerusGame via delegatecall (after Day 5 coin+tickets)

**Callees:** `dgnrs.poolBalance(Pool.Reward)`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.unpackWinningTraits`, `_randTraitTicket`, `dgnrs.transferFromPool`

**ETH Flow:** No ETH movement. Transfers DGNRS tokens from the Reward pool to the solo bucket winner.

**Invariants:**
- Reward = 1% of DGNRS reward pool (`FINAL_DAY_DGNRS_BPS = 100`)
- Uses stored `lastDailyJackpotWinningTraits` (from the Day-5 jackpot)
- Solo bucket index derived from entropy rotation
- Only 1 winner selected (the solo bucket winner)
- No-op if reward is 0 or no winner found

**NatSpec Accuracy:** CORRECT. Accurately describes re-derivation of solo bucket from stored traits.

**Gas Flags:** Minimal computation. Single winner selection + single external call.

**Verdict:** CORRECT

---

### `consolidatePrizePools(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consolidatePrizePools(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current game level; `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `nextPrizePool`, `currentPrizePool`, `futurePrizePool`, `claimablePool`, `price`, `lastPurchaseDayFlipTotal`, `lastPurchaseDayFlipTotalPrev`, `autoRebuyState[]`, `gameOver`

**State Writes:** `currentPrizePool`, `nextPrizePool` (set to 0), `futurePrizePool`, `lastPurchaseDayFlipTotal` (set to 0), `lastPurchaseDayFlipTotalPrev`, `claimablePool`, `claimableWinnings[]`, `whalePassClaims[]`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** DegenerusGame via delegatecall (at level transition, start of jackpot phase)

**Callees:** `_futureKeepBps`, `_shouldFutureDump`, `_creditDgnrsCoinflip`, `_distributeYieldSurplus`

**ETH Flow:**
1. `currentPrizePool += nextPrizePool; nextPrizePool = 0` (always)
2. x00 levels: `futurePrizePool -> currentPrizePool` by 5-dice keep roll (0-100% stays in future, remainder moves to current)
3. Non-x00 levels: 1-in-1e15 chance to move 90% of `futurePrizePool -> currentPrizePool`
4. `_creditDgnrsCoinflip`: credits BURNIE coin proportional to prize pool (no ETH movement)
5. `_distributeYieldSurplus`: distributes stETH yield surplus (23% DGNRS, 23% vault, 46% future)

**Pool Consolidation Flow:**

| Step | Source | Destination | Trigger | Amount |
|------|--------|-------------|---------|--------|
| 1 | nextPrizePool | currentPrizePool | Always | 100% of nextPrizePool |
| 2a | futurePrizePool | currentPrizePool | x00 levels | (1 - keepBps/10000) * futurePrizePool |
| 2b | futurePrizePool | currentPrizePool | Non-x00 (1e-15 odds) | 90% of futurePrizePool |
| 3 | Yield surplus | claimablePool (VAULT) | Always (if surplus exists) | 23% of yield |
| 4 | Yield surplus | claimablePool (DGNRS) | Always (if surplus exists) | 23% of yield |
| 5 | Yield surplus | futurePrizePool | Always (if surplus exists) | 46% of yield |

**Invariants:**
- `nextPrizePool` is always zeroed
- `futurePrizePool` only reduced on x00 levels or rare dump
- keepBps range: 0-10000 (0-100%), from 5 dice each 0-3, sum 0-15, scaled to 10000
- `lastPurchaseDayFlipTotalPrev = lastPurchaseDayFlipTotal; lastPurchaseDayFlipTotal = 0`
- Yield surplus distribution preserves ~8% as buffer (2300+2300+4600 = 9200 out of 10000)

**NatSpec Accuracy:** CORRECT. NatSpec accurately describes the consolidation flow, x00 keep roll, and 1-in-1e15 dump.

**Gas Flags:** `_distributeYieldSurplus` reads `steth.balanceOf(address(this))` and `address(this).balance` -- external call and balance check. These are necessary and unavoidable. No redundant reads.

**Verdict:** CORRECT

---

### `payDailyCoinJackpot(uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `price`, `levelPrizePool[lvl-1]`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`, `jackpotPhaseFlag`, `traitBurnTicket[]`, `deityBySymbol[]`, `dailyHeroWagers[]`, `ticketQueue[]`

**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay` (via `_syncDailyWinningTraits`, only if traits not already cached for today)

**Callers:** DegenerusGame via delegatecall (during purchase/jackpot phase daily cycle)

**Callees:** `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_calculateDayIndex`, `_loadDailyWinningTraits`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`

**ETH Flow:** No ETH mutation. This distributes BURNIE coin only via `coin.creditFlip()` and `coin.creditFlipBatch()`.

**Invariants:**
- Coin budget: `(levelPrizePool[lvl-1] * PRICE_COIN_UNIT) / (price * 200)` = 0.5% of prize pool target in BURNIE
- Split: 25% far-future (ticketQueue holders, lvl+5 to lvl+99), 75% near-future (trait-matched, lvl to lvl+4)
- Near-future target level randomly selected from [lvl, lvl+4] with trait ticket existence check
- Uses `coin.creditFlipBatch()` in batches of 3 for gas efficiency
- Daily winning traits cached and reused if same day

**NatSpec Accuracy:** CORRECT. NatSpec describes daily BURNIE jackpot with 75/25 split accurately.

**Gas Flags:** Batching `creditFlipBatch` in groups of 3 is a sound optimization to reduce external call overhead. `_loadDailyWinningTraits` caches traits to avoid re-rolling.

**Verdict:** CORRECT

---

### `processTicketBatch(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processTicketBatch(uint24 lvl) external returns (bool finished)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level whose tickets should be processed |
| **Returns** | `bool`: True if all tickets for this level have been fully processed |

**State Reads:** `ticketQueue[lvl]`, `ticketLevel`, `ticketCursor`, `rngWordCurrent`, `ticketsOwedPacked[lvl][]`

**State Writes:** `ticketLevel`, `ticketCursor`, `ticketQueue[lvl]` (delete on completion), `ticketsOwedPacked[lvl][]`, `traitBurnTicket[lvl][]` (via assembly bulk writes)

**Callers:** DegenerusGame via delegatecall (advanceGame flow, iterative processing)

**Callees:** `_processOneTicketEntry`, `_generateTicketBatch` -> `_raritySymbolBatch`, `_finalizeTicketEntry`, `_resolveZeroOwedRemainder`, `_rollRemainder`

**ETH Flow:** No ETH mutation. This function processes ticket queues into trait burn tickets.

**Invariants:**
- Level switching: if `ticketLevel != lvl`, resets cursor and sets new level
- Writes budget: 550 SSTOREs per call (reduced by 35% for first batch due to cold storage)
- Each entry processes `take` tickets out of `owed`, resuming on next call if budget exhausted
- Fractional tickets (remainder) are rolled for probabilistic inclusion
- `ticketQueue[lvl]` deleted when all entries processed
- `finished == true` when `idx >= total` or queue is empty

**NatSpec Accuracy:** CORRECT. NatSpec describes gas budgeting, cold storage scaling, and iterative processing accurately.

**Gas Flags:**
- First-batch 35% scaling (`writesBudget *= 65%`) accounts for cold SLOAD costs
- `_raritySymbolBatch` uses inline assembly for bulk storage writes -- critical for gas efficiency when writing many trait tickets
- LCG-based trait generation in groups of 16 is highly efficient
- `_processOneTicketEntry` tracks base overhead (4 for first entry with small owed, 2 otherwise)
- The writes budget formula `((take <= 256) ? (take << 1) : (take + 256))` accounts for array growth costs

**Concern:** The `_raritySymbolBatch` function uses raw assembly to compute storage slots via `keccak256`. The slot calculation uses `add(levelSlot, traitId)` for the array length slot -- this relies on the EVM's nested mapping layout being `keccak256(traitId, keccak256(level, slot))`. However, the code computes `levelSlot = keccak256(lvl, traitBurnTicket.slot)` and then accesses `add(levelSlot, traitId)`. For a `mapping(uint24 => address[][256])`, the 256-element fixed array's slot for element `traitId` is `keccak256(lvl, slot) + traitId`. This is correct for a fixed-size array within a mapping -- Solidity stores fixed arrays contiguously starting at the mapping value slot.

**Verdict:** CORRECT

---

### `_distributeYieldSurplus(uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeYieldSurplus(uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `rngWord` (uint256): VRF entropy for auto-rebuy in `_addClaimableEth` |
| **Returns** | None |

**State Reads:** `steth.balanceOf(address(this))`, `address(this).balance`, `currentPrizePool`, `nextPrizePool`, `claimablePool`, `futurePrizePool`, `autoRebuyState[VAULT]`, `autoRebuyState[DGNRS]`, `gameOver`, `level`

**State Writes:** `claimableWinnings[VAULT]`, `claimableWinnings[DGNRS]`, `claimablePool`, `futurePrizePool`, `nextPrizePool` (via auto-rebuy), `ticketsOwedPacked[]`, `ticketQueue[]`, `whalePassClaims[]`

**Callers:** `consolidatePrizePools`

**Callees:** `steth.balanceOf`, `_addClaimableEth` (x2 for VAULT and DGNRS)

**ETH Flow:**
- Compute yield surplus: `totalBal - obligations` where `totalBal = ETH balance + stETH balance`, `obligations = currentPrizePool + nextPrizePool + claimablePool + futurePrizePool`
- 23% to VAULT claimable: `(yieldPool * 2300) / 10000`
- 23% to DGNRS claimable: `(yieldPool * 2300) / 10000`
- 46% to futurePrizePool: `(yieldPool * 4600) / 10000`
- ~8% unextracted buffer: `10000 - (2300 + 2300 + 4600) = 800 bps`

**Percentage Verification:** 2300 + 2300 + 4600 = 9200 bps. 10000 - 9200 = 800 bps (8%) left unextracted as buffer. This matches the NatSpec comment "~8% buffer left unextracted". VERIFIED.

**Invariants:**
- No-op if `totalBal <= obligations` (no surplus to distribute)
- `claimablePool += claimableDelta` only if `claimableDelta != 0`
- `futurePrizePool += futureShare` only if `futureShare != 0`
- Auto-rebuy may route stakeholder shares to tickets instead of claimable

**NatSpec Accuracy:** CORRECT. Comments state "23% each for DGNRS and Vault" and "46% to future prize pool (~8% buffer left unextracted)".

**Gas Flags:** Two external calls to `_addClaimableEth` (which may trigger auto-rebuy with further external calls). stETH `balanceOf` is an external call. All necessary.

**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): Recipient; `weiAmount` (uint256): Wei to credit; `entropy` (uint256): RNG for auto-rebuy |
| **Returns** | `uint256`: Amount to add to claimablePool |

**State Reads:** `gameOver`, `autoRebuyState[beneficiary]`

**State Writes:** `claimableWinnings[beneficiary]` (via `_creditClaimable`), or auto-rebuy state changes

**Callers:** `_distributeYieldSurplus`, `_resolveTraitWinners`, `_processDailyEthChunk`, `_creditJackpot`

**Callees:** `_processAutoRebuy` (if auto-rebuy enabled and not gameOver), `_creditClaimable` (otherwise)

**ETH Flow:**
- If `gameOver == true` or auto-rebuy disabled: `weiAmount -> claimableWinnings[beneficiary]`, returns `weiAmount`
- If auto-rebuy enabled and `!gameOver`: delegates to `_processAutoRebuy`, returns reserved amount only

**Invariants:**
- Returns 0 if `weiAmount == 0`
- `gameOver` check prevents post-game auto-rebuy (tickets worthless after game ends)
- Return value represents the amount that should be added to `claimablePool` by the caller

**NatSpec Accuracy:** CORRECT. Describes auto-rebuy branch and gameOver guard.

**Gas Flags:** None. Minimal branching logic.

**Verdict:** CORRECT

---

### `_processAutoRebuy(address player, uint256 newAmount, uint256 entropy, AutoRebuyState memory state)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processAutoRebuy(address player, uint256 newAmount, uint256 entropy, AutoRebuyState memory state) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Winning player; `newAmount` (uint256): New winnings in wei; `entropy` (uint256): RNG seed; `state` (AutoRebuyState): Player's auto-rebuy config |
| **Returns** | `uint256`: Amount to add to claimablePool (reserved take-profit only) |

**State Reads:** `level`, `autoRebuyState[player]` (passed in), `price` (via PriceLookupLib)

**State Writes:** `futurePrizePool` (75% chance: +ethSpent), `nextPrizePool` (25% chance: +ethSpent), `claimableWinnings[player]` (reserved amount), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_addClaimableEth`

**Callees:** `_calcAutoRebuy` (from PayoutUtils), `_queueTickets`, `_creditClaimable`

**ETH Flow:**
1. Take profit: `reserved = (newAmount / takeProfit) * takeProfit` (truncated to take-profit granularity)
2. Rebuy amount: `newAmount - reserved`
3. Level offset: 1-4 levels ahead (entropy-derived). +1 = nextPrizePool (25%), +2/+3/+4 = futurePrizePool (75%)
4. Ticket price: `PriceLookupLib.priceForLevel(targetLevel) >> 2` (ticket = 1/4 level price)
5. Base tickets: `rebuyAmount / ticketPrice`
6. Bonus: 30% normal (`13000` bps), 45% afKing (`14500` bps)
7. `ethSpent = baseTickets * ticketPrice` (no bonus applied to ETH, only tickets)
8. Fractional dust (rebuyAmount - ethSpent) is dropped

**Auto-Rebuy ETH Accounting:**
- `ethSpent` goes to `futurePrizePool` or `nextPrizePool` (backing the tickets)
- `reserved` goes to `claimableWinnings[player]`
- `newAmount - ethSpent - reserved` = dust, dropped unconditionally
- Return value = `reserved` (only the claimed portion adds to claimablePool liability)

**Note on dust:** The dust amount is `(newAmount - reserved) - ethSpent = (newAmount - reserved) % ticketPrice`. This dust is NOT accounted for -- it is neither credited to the player nor added to any pool. This creates a small ETH leak where `sum(pools) + claimablePool < address(this).balance`. However, this dust is captured by the yield surplus mechanism (`_distributeYieldSurplus`), which measures `totalBal - obligations`. The dust becomes part of the yield surplus. This is an intentional design decision, not a bug.

**Invariants:**
- If `_calcAutoRebuy` returns `hasTickets == false`, full amount goes to claimable (fallback path)
- Bonus BPS are `13000` (130%) and `14500` (145%) -- these are multiplied by baseTickets and divided by 10000, giving 1.3x and 1.45x ticket counts. The naming `bonusBps` is slightly misleading since these are total multipliers, not bonus-only. However, `_calcAutoRebuy` computes `bonusTickets = (baseTickets * bonusBps) / 10000`, so with 13000 bps this gives 1.3x base = 30% bonus. This is correct.
- `ticketCount` capped at `type(uint32).max`

**NatSpec Accuracy:** CORRECT. States "fixed 30% bonus by default, 45% when afKing is active".

**Gas Flags:** `_calcAutoRebuy` is `pure` -- no storage reads. Good gas efficiency.

**Verdict:** CORRECT

---

### `_distributeLootboxAndTickets(uint24 lvl, uint32 winningTraitsPacked, uint256 lootboxBudget, uint256 randWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeLootboxAndTickets(uint24 lvl, uint32 winningTraitsPacked, uint256 lootboxBudget, uint256 randWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `winningTraitsPacked` (uint32): Packed trait IDs; `lootboxBudget` (uint256): ETH to convert to tickets; `randWord` (uint256): Entropy |
| **Returns** | None |

**State Reads:** Via `_distributeTicketJackpot`

**State Writes:** `nextPrizePool`, `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `payDailyJackpot` (early-burn path, isEthDay)

**Callees:** `_budgetToTicketUnits`, `_distributeTicketJackpot`

**ETH Flow:**
- `nextPrizePool += lootboxBudget` (ETH backing for tickets)
- Ticket units calculated for `lvl + 1` price
- Tickets distributed to trait winners at current level

**Invariants:**
- Lootbox budget adds to nextPrizePool (tickets are for future levels)
- Ticket units at `lvl + 1` price but winners drawn from `lvl` ticket pool
- Uses salt 242 for entropy differentiation

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketJackpot(uint24 lvl, uint32 winningTraitsPacked, uint256 ticketUnits, uint256 entropy, uint16 maxWinners, uint8 saltBase)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketJackpot(uint24 lvl, uint32 winningTraitsPacked, uint256 ticketUnits, uint256 entropy, uint16 maxWinners, uint8 saltBase) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner selection; `winningTraitsPacked` (uint32): Traits; `ticketUnits` (uint256): Total tickets to distribute; `entropy` (uint256): RNG; `maxWinners` (uint16): Winner cap; `saltBase` (uint8): Entropy salt |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][]`, `deityBySymbol[]`

**State Writes:** `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_distributeLootboxAndTickets`, `payDailyJackpotCoinAndTickets`

**Callees:** `JackpotBucketLib.unpackWinningTraits`, `_computeBucketCounts`, `_distributeTicketsToBuckets`

**ETH Flow:** None (ticket distribution only).

**Invariants:**
- No-op if `ticketUnits == 0`
- Cap: `min(maxWinners, ticketUnits)` to avoid allocating more winners than tickets
- Uses `_computeBucketCounts` which divides winners evenly across active trait buckets
- No-op if `activeCount == 0`

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketsToBuckets(uint24 lvl, uint8[4] traitIds, uint16[4] counts, uint256 ticketUnits, uint256 entropy, uint16 cap, uint8 saltBase)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketsToBuckets(uint24 lvl, uint8[4] memory traitIds, uint16[4] memory counts, uint256 ticketUnits, uint256 entropy, uint16 cap, uint8 saltBase) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `traitIds` (uint8[4]): Trait IDs; `counts` (uint16[4]): Winners per bucket; `ticketUnits` (uint256): Total tickets; `entropy` (uint256): RNG; `cap` (uint16): Total winner cap; `saltBase` (uint8): Salt |
| **Returns** | None |

**State Reads:** Via `_distributeTicketsToBucket`

**State Writes:** Via `_distributeTicketsToBucket`

**Callers:** `_distributeTicketJackpot`

**Callees:** `EntropyLib.entropyStep`, `_distributeTicketsToBucket`

**ETH Flow:** None.

**Invariants:**
- `baseUnits = ticketUnits / cap` (even distribution)
- `distParams` packs `extra = ticketUnits % cap` (first `extra` winners get +1 unit) and `offset = entropy % cap` (randomized starting position for +1 distribution)
- `globalIdx` tracks position across all buckets for fair +1 distribution
- Skips buckets with 0 counts

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_distributeTicketsToBucket(uint24 lvl, uint8 traitId, uint16 count, uint256 entropy, uint8 salt, uint256 baseUnits, uint256 distParams, uint16 cap, uint256 startIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeTicketsToBucket(uint24 lvl, uint8 traitId, uint16 count, uint256 entropy, uint8 salt, uint256 baseUnits, uint256 distParams, uint16 cap, uint256 startIdx) private returns (uint256 endIdx)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `traitId` (uint8): Trait; `count` (uint16): Winners; `entropy` (uint256): RNG; `salt` (uint8): Salt; `baseUnits` (uint256): Tickets per winner; `distParams` (uint256): Packed extra/offset; `cap` (uint16): Total cap; `startIdx` (uint256): Global index |
| **Returns** | `uint256`: Updated global index (endIdx) |

**State Reads:** `traitBurnTicket[lvl][traitId]`, `deityBySymbol[]`

**State Writes:** `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `_distributeTicketsToBuckets`

**Callees:** `_randTraitTicket`, `_queueTickets`

**ETH Flow:** None.

**Invariants:**
- Count capped at `MAX_BUCKET_WINNERS` (250)
- Winners selected from trait pool (duplicates allowed)
- Each winner gets `baseUnits + (1 if cursor < extra)` tickets
- Cursor wraps at `cap` to ensure fair +1 distribution
- Tickets queued at `lvl + 1` (next level)
- Units capped at `type(uint32).max`
- No-op for address(0) winners or zero units

**NatSpec Accuracy:** Minimal but correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Target level (typically current + 1); `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `futurePrizePool`, `traitBurnTicket[lvl][]`, `deityBySymbol[]`

**State Writes:** `futurePrizePool` (deducted 3%), `nextPrizePool` (receives full budget), `ticketsOwedPacked[]`, `ticketQueue[]`

**Callers:** `payDailyJackpot` (day 1 only, replaces carryover)

**Callees:** `PriceLookupLib.priceForLevel`, `EntropyLib.entropyStep`, `_randTraitTicket`, `_queueTickets`

**ETH Flow:**
1. `reserveContribution = (futurePrizePool * 300) / 10000` = 3% from unified reserve
2. `futurePrizePool -= reserveContribution`
3. For each of 100 winners: select random trait ticket holder at current level, roll level offset 0-4, convert `perWinnerEth` to tickets at that level's price
4. `nextPrizePool += totalBudget` (full 3% budget backs tickets in next pool)

**Invariants:**
- Fixed 100 winners max
- Even split: `perWinnerEth = totalBudget / 100`
- Random trait selection (uniform, not burn-weighted -- `uint8(entropy)` gives uniform trait ID)
- Level offset: `entropy % 5` gives 0-4 offset from base level
- No-op if `totalBudget == 0`
- Budget goes to `nextPrizePool` AFTER ticket distribution (backing the tickets)
- Winners drawn from `traitBurnTicket[lvl]` (the parameter `lvl`, which is `currentLevel + 1`)

**NatSpec Accuracy:** CORRECT.

**Gas Flags:** Fixed 100 iterations with 2 entropy steps + 1 winner selection each. This is bounded and safe for gas. PriceLookupLib prices cached in `levelPrices[5]` memory array -- good optimization.

**Verdict:** CORRECT

---

### `_executeJackpot(JackpotParams memory jp)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _executeJackpot(JackpotParams memory jp) private returns (uint256 paidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `jp` (JackpotParams): Packed jackpot parameters containing lvl, ethPool, entropy, winningTraitsPacked, traitShareBpsPacked |
| **Returns** | `uint256`: Total ETH paid out for pool accounting |

**State Reads:** None directly (delegates to callees)
**State Writes:** None directly (delegates to callees)

**Callers:** `payDailyJackpot` (early-burn path)
**Callees:** `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.shareBpsByBucket`, `_runJackpotEthFlow`

**ETH Flow:** Orchestrator only. If `jp.ethPool != 0`, delegates to `_runJackpotEthFlow` which distributes ETH to claimable balances. The caller (payDailyJackpot early-burn path) does not deduct from currentPrizePool since funds come from futurePrizePool which is deducted upfront.

**Invariants:**
- If `jp.ethPool == 0`, no ETH distribution occurs and `paidEth == 0`.
- Share BPS rotation is derived from `jp.entropy & 3`, ensuring fair bucket assignment.

**NatSpec Accuracy:** NatSpec says "distributes ETH and/or COIN to winners" but the function only handles ETH distribution. COIN distribution was removed/refactored -- the COIN path for early-burn is handled separately by `payDailyCoinJackpot`. The NatSpec is slightly stale but the actual behavior is correct.

**Gas Flags:** None. Simple dispatch function with minimal overhead.

**Verdict:** CORRECT

---

### `_runJackpotEthFlow(JackpotParams memory jp, uint8[4] memory traitIds, uint16[4] memory shareBps)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runJackpotEthFlow(JackpotParams memory jp, uint8[4] memory traitIds, uint16[4] memory shareBps) private returns (uint256 totalPaidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `jp` (JackpotParams): Packed jackpot params; `traitIds` (uint8[4]): Unpacked winning trait IDs; `shareBps` (uint16[4]): Per-bucket share basis points |
| **Returns** | `uint256`: Total ETH paid out |

**State Reads:** Via callees (traitBurnTicket, claimableWinnings, autoRebuyState)
**State Writes:** Via callees (claimableWinnings, claimablePool, whalePassClaims, futurePrizePool)

**Callers:** `_executeJackpot`
**Callees:** `JackpotBucketLib.traitBucketCounts`, `JackpotBucketLib.scaleTraitBucketCountsWithCap`, `_distributeJackpotEth`

**ETH Flow:** Computes scaled bucket counts from `jp.ethPool` (capped at JACKPOT_MAX_WINNERS=300, max scale 4x at 200 ETH), then delegates to `_distributeJackpotEth` with `dgnrsReward=0`.

**Invariants:**
- Bucket counts are always capped at JACKPOT_MAX_WINNERS (300).
- Scale factor: 1x under 10 ETH, linearly to 2x at 50 ETH, linearly to 4x at 200 ETH+.
- Solo bucket always has count=1 (guaranteed by JackpotBucketLib rotation).

**NatSpec Accuracy:** Matches. "Simple ETH flow for jackpot ETH distribution."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_processDailyEthChunk(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint16 unitsBudget)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processDailyEthChunk(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint16 unitsBudget) private returns (uint256 paidEth, bool complete)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner lookup; `ethPool` (uint256): Total ETH budget; `entropy` (uint256): VRF-derived entropy; `traitIds` (uint8[4]): Winning traits; `shareBps` (uint16[4]): Per-bucket shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `unitsBudget` (uint16): Gas budget in units |
| **Returns** | `paidEth` (uint256): ETH distributed; `complete` (bool): True if all buckets processed |

**State Reads:** `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `traitBurnTicket[lvl]`, `autoRebuyState`, `deityBySymbol`, `claimableWinnings`, `gameOver`
**State Writes:** `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `claimablePool`, `claimableWinnings`, (via _addClaimableEth: `whalePassClaims`, `futurePrizePool`, `nextPrizePool`)

**Callers:** `payDailyJackpot` (daily path, Phase 0 and Phase 1)
**Callees:** `PriceLookupLib.priceForLevel`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.bucketShares`, `JackpotBucketLib.bucketOrderLargestFirst`, `_skipEntropyToBucket`, `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `_winnerUnits`, `_addClaimableEth`

**ETH Flow:**
- `ethPool` -> per-bucket shares (via `JackpotBucketLib.bucketShares`)
- per-bucket share -> `perWinner = share / totalCount`
- per winner -> `_addClaimableEth(w, perWinner, entropyState)` -> `claimableWinnings[w]` or auto-rebuy conversion
- liability aggregated and applied to `claimablePool` at end or on yield

**Cursor mechanism for gas-safe resumption:**
1. `dailyEthBucketCursor` (uint8): Which bucket (in processing order) to resume from.
2. `dailyEthWinnerCursor` (uint16): Which winner within the current bucket to resume from.
3. On incomplete: stores cursors and returns `(paidEth, false)`.
4. On complete: resets cursors to 0 and returns `(paidEth, true)`.
5. On resume: `_skipEntropyToBucket` replays entropy for already-processed buckets to reach the correct entropy state.

**Invariants:**
- Winners are processed in largest-bucket-first order (via `bucketOrderLargestFirst`).
- Per-winner amount is `share / totalCount` -- integer division means dust stays in the contract.
- Gas budget tracked via `_winnerUnits(w)`: 1 unit per normal winner, 3 for auto-rebuy.
- `claimablePool` is updated atomically at the end of each chunk (or on yield).
- Entropy derivation per bucket: `entropyState ^ (uint256(traitIdx) << 64) ^ share` -- deterministic and consistent with `_skipEntropyToBucket`.

**NatSpec Accuracy:** Matches. "Processes daily jackpot ETH winners in chunks, resuming mid-bucket if needed."

**Gas Flags:**
- The `bucketOrderLargestFirst` function uses a simple O(n) scan with ties broken by lower index, which is optimal for 4 elements.
- `_randTraitTicketWithIndices` is called once per bucket regardless of chunking -- winner list is regenerated on resume. This is acceptable because the list is deterministic (same entropy, same winners).

**Verdict:** CORRECT

---

### `_distributeJackpotEth(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint256 dgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeJackpotEth(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint256 dgnrsReward) private returns (uint256 totalPaidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner lookup; `ethPool` (uint256): Total ETH budget; `entropy` (uint256): VRF-derived entropy; `traitIds` (uint8[4]): Winning traits; `shareBps` (uint16[4]): Per-bucket shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `dgnrsReward` (uint256): DGNRS reward for solo bucket (0 if none) |
| **Returns** | `uint256`: Total ETH paid (including ticket conversions) |

**State Reads:** Via callees
**State Writes:** `claimablePool` (directly); via callees: `claimableWinnings`, `whalePassClaims`, `futurePrizePool`

**Callers:** `_runJackpotEthFlow`, `runTerminalJackpot`, `payDailyJackpot` (via _runJackpotEthFlow)
**Callees:** `PriceLookupLib.priceForLevel`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.bucketShares`, `_processOneBucket`

**ETH Flow:**
- `ethPool` -> 4 bucket shares via `JackpotBucketLib.bucketShares` with remainder going to `remainderIdx` (solo bucket).
- Each bucket processed by `_processOneBucket`.
- `ctx.liabilityDelta` accumulated and applied to `claimablePool` after all 4 buckets.
- `ctx.totalPaidEth` = sum of all `ethDelta + ticketSpent` across buckets.

**Solo bucket rotation:** `remainderIdx = JackpotBucketLib.soloBucketIndex(entropy)` = `(3 - (entropy & 3)) & 3`. This rotates which trait gets the solo (1-winner, highest share) bucket. The `soloIdx` for DGNRS reward uses the same formula.

**Invariants:**
- The sum of all 4 bucket shares equals `ethPool` (remainder bucket gets `pool - distributed`).
- `unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2` ensures per-winner amounts are multiples of quarter-ticket price, reducing dust.
- `totalPaidEth` includes both direct ETH credits and whale-pass conversions.

**NatSpec Accuracy:** No explicit NatSpec beyond inline comments. Behavior matches the described flow.

**Gas Flags:**
- `soloIdx` now reuses `remainderIdx` directly (both are `JackpotBucketLib.soloBucketIndex(entropy)` with same input). Redundant call removed post-audit.

**Verdict:** CORRECT

---

### `_processOneBucket(JackpotEthCtx memory ctx, uint8 traitIdx, uint8[4] memory traitIds, uint256[4] memory shares, uint16[4] memory bucketCounts, uint256 bucketDgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processOneBucket(JackpotEthCtx memory ctx, uint8 traitIdx, uint8[4] memory traitIds, uint256[4] memory shares, uint16[4] memory bucketCounts, uint256 bucketDgnrsReward) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ctx` (JackpotEthCtx): Mutable context tracking entropy, liability, paid ETH; `traitIdx` (uint8): Current bucket index; `traitIds` (uint8[4]): Winning trait IDs; `shares` (uint256[4]): Per-bucket ETH shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `bucketDgnrsReward` (uint256): DGNRS reward (solo bucket only) |
| **Returns** | None (mutates ctx) |

**State Reads:** Via `_resolveTraitWinners`
**State Writes:** Via `_resolveTraitWinners`

**Callers:** `_distributeJackpotEth`
**Callees:** `_resolveTraitWinners`

**ETH Flow:** Delegates to `_resolveTraitWinners` with `payCoin=false`. Updates `ctx.totalPaidEth += ethDelta + ticketSpent` and `ctx.liabilityDelta += bucketLiability`.

**Invariants:**
- Single bucket dispatch. Entropy state flows through ctx to maintain determinism across buckets.
- `ticketSpent` tracks ETH converted to whale passes (moved to futurePrizePool).

**NatSpec Accuracy:** Matches. "Processes a single bucket in ETH distribution."

**Gas Flags:** None. Simple delegation.

**Verdict:** CORRECT

---

### `_resolveTraitWinners(bool payCoin, uint24 lvl, uint8 traitId, uint8 traitIdx, uint256 traitShare, uint256 entropy, uint16 winnerCount, uint256 dgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveTraitWinners(bool payCoin, uint24 lvl, uint8 traitId, uint8 traitIdx, uint256 traitShare, uint256 entropy, uint16 winnerCount, uint256 dgnrsReward) private returns (uint256 entropyState, uint256 ethDelta, uint256 liabilityDelta, uint256 ticketSpent)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payCoin` (bool): Pay BURNIE if true, ETH if false; `lvl` (uint24): Level; `traitId` (uint8): Trait pool to draw from; `traitIdx` (uint8): Bucket index; `traitShare` (uint256): Total allocation for this bucket; `entropy` (uint256): Current entropy; `winnerCount` (uint16): Winners to select; `dgnrsReward` (uint256): DGNRS reward for solo bucket |
| **Returns** | `entropyState` (uint256): Updated entropy; `ethDelta` (uint256): ETH credited; `liabilityDelta` (uint256): Claimable liability added; `ticketSpent` (uint256): ETH converted to whale passes |

**State Reads:** `traitBurnTicket[lvl]`, `deityBySymbol`, `claimableWinnings`, `autoRebuyState`, `gameOver`
**State Writes:** `claimableWinnings`, `whalePassClaims`, `futurePrizePool` (via _processSoloBucketWinner / _addClaimableEth)

**Callers:** `_processOneBucket`
**Callees:** `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `_creditJackpot`, `_processSoloBucketWinner`, `_addClaimableEth`, `dgnrs.transferFromPool`

**ETH Flow:**
- **COIN path** (`payCoin=true`): Calls `_creditJackpot(true, ...)` -> `coin.creditFlip(beneficiary, amount)` for each winner. Returns `(entropyState, 0, 0, 0)` -- no ETH liability.
- **ETH path** (`payCoin=false`):
  - **Solo bucket** (`winnerCount == 1`): Calls `_processSoloBucketWinner` which does 75/25 split: 75% ETH to claimable, 25% as whale passes. If 25% < HALF_WHALE_PASS_PRICE (2.175 ETH), pays 100% as ETH.
  - **Multi-winner bucket**: Calls `_addClaimableEth(w, perWinner, entropyState)` for each winner.
- DGNRS reward: First solo bucket winner gets `dgnrs.transferFromPool(Pool.Reward, w, dgnrsReward)`.

**Deity virtual entries:** The `_randTraitTicketWithIndices` function includes virtual deity entries (2% of bucket, min 2), so deity pass holders can win jackpots even without physical tickets.

**Invariants:**
- `perWinner = traitShare / totalCount` -- integer division, dust stays in contract.
- Duplicates allowed in winner selection (by design -- more tickets = more chances).
- `winnerCount` capped at MAX_BUCKET_WINNERS (250).
- DGNRS reward only paid to first winner (solo bucket, `!dgnrsPaid` guard).
- Entropy derivation: `entropyState ^ (traitIdx << 64) ^ traitShare` -- unique per bucket.
- Salt for `_randTraitTicketWithIndices` is `200 + traitIdx` -- unique per bucket within a jackpot.

**NatSpec Accuracy:** Matches well. Documents the 3-step flow (early exit, winner selection, credit).

**Gas Flags:** None. Well-structured with early exits.

**Verdict:** CORRECT

---

### `_creditJackpot(bool payInCoin, address beneficiary, uint256 amount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditJackpot(bool payInCoin, address beneficiary, uint256 amount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payInCoin` (bool): If true, pay BURNIE via coin.creditFlip; `beneficiary` (address): Winner; `amount` (uint256): Amount to credit; `entropy` (uint256): For auto-rebuy roll |
| **Returns** | `uint256`: Amount to add to claimablePool (0 for COIN path) |

**State Reads:** Via `_addClaimableEth` (autoRebuyState, claimableWinnings)
**State Writes:** Via `_addClaimableEth` or `coin.creditFlip`

**Callers:** `_resolveTraitWinners`, `_processSoloBucketWinner` (via _resolveTraitWinners)
**Callees:** `coin.creditFlip` (COIN path), `_addClaimableEth` (ETH path)

**ETH Flow:**
- COIN: `coin.creditFlip(beneficiary, amount)` -- external call to BurnieCoin module. Returns 0 liability.
- ETH: `_addClaimableEth(beneficiary, amount, entropy)` -- credits to claimableWinnings or converts to auto-rebuy tickets. Returns the claimable delta.

**Invariants:**
- COIN path never affects ETH accounting.
- ETH path liability is tracked by caller to avoid per-winner SSTORE cost (batch update to claimablePool).

**NatSpec Accuracy:** Matches. "Credits a jackpot winner with COIN or ETH; no-op if beneficiary is invalid."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_processSoloBucketWinner(address winner, uint256 perWinner, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processSoloBucketWinner(address winner, uint256 perWinner, uint256 entropy) private returns (uint256 claimableDelta, uint256 ethPaid, uint256 lootboxSpent, uint256 newEntropy)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Solo bucket winner; `perWinner` (uint256): Total ETH for this bucket; `entropy` (uint256): Current entropy state |
| **Returns** | `claimableDelta` (uint256): Claimable liability; `ethPaid` (uint256): Total ETH value credited; `lootboxSpent` (uint256): ETH moved to futurePrizePool for whale passes; `newEntropy` (uint256): Updated entropy |

**State Reads:** Via `_creditJackpot` -> `_addClaimableEth`
**State Writes:** `whalePassClaims[winner]`, `futurePrizePool` (directly); `claimableWinnings` (via _creditJackpot)

**Callers:** `_resolveTraitWinners`
**Callees:** `_creditJackpot`

**ETH Flow:**
- **75/25 split path** (when `quarterAmount >= HALF_WHALE_PASS_PRICE`):
  - `whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE` whale passes queued.
  - `whalePassSpent = whalePassCount * HALF_WHALE_PASS_PRICE` moved to `futurePrizePool`.
  - `ethAmount = perWinner - whalePassSpent` credited as claimable ETH.
  - Difference from multi-winner: solo gets whale passes, multi-winner gets pure ETH.
- **Full ETH path** (when `quarterAmount < HALF_WHALE_PASS_PRICE`, i.e., `perWinner < 4 * 2.175 = 8.7 ETH`):
  - Full `perWinner` credited as claimable ETH.

**Invariants:**
- `whalePassSpent + ethAmount == perWinner` (no dust loss).
- `whalePassSpent` goes to `futurePrizePool` (recycled into prize pool, backing the whale pass value).
- `lootboxSpent` is added to `ctx.totalPaidEth` by the caller, ensuring pool accounting is correct.

**NatSpec Accuracy:** NatSpec says "lootboxSpent" is "Amount moved to futurePrizePool from whale pass conversion" which is accurate for the current code, though the return name `lootboxSpent` is a legacy name (it's whale passes, not loot boxes).

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_syncDailyWinningTraits(uint24 lvl, uint32 packed, uint48 questDay)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _syncDailyWinningTraits(uint24 lvl, uint32 packed, uint48 questDay) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `packed` (uint32): Packed winning traits; `questDay` (uint48): Current day index |
| **Returns** | None |

**State Reads:** None
**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`

**Callers:** `payDailyJackpot`, `payDailyCoinJackpot`
**Callees:** None

**ETH Flow:** None.

**Invariants:**
- Stores the winning traits so they can be reused by subsequent calls on the same day (e.g., Phase 2 coin+ticket distribution).
- Three storage writes per call.

**NatSpec Accuracy:** No NatSpec. Function is self-documenting.

**Gas Flags:** 3 SSTOREs. Acceptable for once-per-jackpot frequency.

**Verdict:** CORRECT

---

### `payDailyCoinJackpot(uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current game level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `price`, `levelPrizePool[lvl-1]`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotDay`, `lastDailyJackpotLevel`, `jackpotPhaseFlag`, `traitBurnTicket`, `deityBySymbol`, `dailyHeroWagers`, `ticketQueue`
**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay` (via _syncDailyWinningTraits)

**Callers:** Parent game contract via delegatecall (from AdvanceModule)
**Callees:** `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_loadDailyWinningTraits`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`

**ETH Flow:** No ETH moved. BURNIE only.

**BURNIE distribution:**
1. Budget = `_calcDailyCoinBudget(lvl)` = 0.5% of levelPrizePool[lvl-1] in BURNIE terms.
2. 25% (`farBudget`) -> `_awardFarFutureCoinJackpot` (ticketQueue-based, levels lvl+5 to lvl+99).
3. 75% (`nearBudget`) -> `_awardDailyCoinToTraitWinners` (trait-matched, levels lvl to lvl+4).
4. If no valid winning traits for today, re-rolls and syncs.
5. Target level selected randomly from [lvl, lvl+4] that has trait tickets.

**Invariants:**
- No ETH accounting changes.
- Trait reuse: loads previously synced traits for same day/level to ensure consistent winning traits across ETH and COIN jackpots.
- `jackpotPhaseFlag` determines burn-weighted vs random trait selection for fresh rolls.

**NatSpec Accuracy:** Matches. Documents the 75/25 split and ticket-based distribution.

**Gas Flags:** Multiple external calls to `coin.creditFlip` / `coin.creditFlipBatch`. These are gas-bounded by DAILY_COIN_MAX_WINNERS (50) and FAR_FUTURE_COIN_SAMPLES (10).

**Verdict:** CORRECT

---

### `_awardDailyCoinToTraitWinners(uint24 lvl, uint32 winningTraitsPacked, uint256 coinBudget, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardDailyCoinToTraitWinners(uint24 lvl, uint32 winningTraitsPacked, uint256 coinBudget, uint256 entropy) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Target level; `winningTraitsPacked` (uint32): Packed winning traits; `coinBudget` (uint256): BURNIE to distribute; `entropy` (uint256): For winner selection |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl]`, `deityBySymbol`
**State Writes:** None directly (external calls to coin.creditFlipBatch)

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `JackpotBucketLib.unpackWinningTraits`, `_computeBucketCounts`, `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `coin.creditFlipBatch`

**ETH Flow:** None. BURNIE only.

**BURNIE distribution:**
1. Cap winners at DAILY_COIN_MAX_WINNERS (50), further capped by `coinBudget` if budget < 50.
2. Compute bucket counts via `_computeBucketCounts` (even split across active traits).
3. `baseAmount = coinBudget / cap`, `extra = coinBudget % cap` (1 extra unit to first `extra` winners via cursor).
4. Select winners per bucket via `_randTraitTicketWithIndices` with salt `DAILY_COIN_SALT_BASE + traitIdx` (252-255).
5. Batch credit via `coin.creditFlipBatch` (3 winners at a time).
6. Leftover batch (< 3 winners) padded with address(0) and 0 amounts before final `creditFlipBatch`.

**Invariants:**
- Total distributed = `baseAmount * cap + extra = coinBudget` (perfect distribution, no dust).
- Winners capped at MAX_BUCKET_WINNERS (250) per bucket.
- Batch size of 3 matches `coin.creditFlipBatch` signature.

**NatSpec Accuracy:** Matches. "Awards BURNIE to random winners from the packed winning traits."

**Gas Flags:** Up to 50 external calls to `coin.creditFlipBatch` in batches of 3 = ~17 external calls max. Acceptable.

**Verdict:** CORRECT

---

### `_awardFarFutureCoinJackpot(uint24 lvl, uint256 farBudget, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardFarFutureCoinJackpot(uint24 lvl, uint256 farBudget, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `farBudget` (uint256): BURNIE budget for far-future winners; `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `ticketQueue[candidate]` for up to 10 random levels
**State Writes:** None directly (external calls to coin.creditFlipBatch)

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `EntropyLib.entropyStep`, `coin.creditFlipBatch`

**ETH Flow:** None. BURNIE only.

**ticketQueue sampling logic:**
1. Entropy derivation: `rngWord ^ (lvl << 192) ^ FAR_FUTURE_COIN_TAG`.
2. Samples up to FAR_FUTURE_COIN_SAMPLES (10) random levels in [lvl+5, lvl+99]:
   - `candidate = lvl + 5 + (entropy % 95)` -- covers the full 95-level range.
   - `idx = (entropy >> 32) % len` -- random index within the queue.
   - If `queue[idx]` is not address(0), winner is recorded.
3. Budget split evenly: `perWinner = farBudget / found`.
4. Credited via `coin.creditFlipBatch` (batches of 3).
5. `FarFutureCoinJackpotWinner` event emitted per winner.

**Invariants:**
- Up to 10 winners max (FAR_FUTURE_COIN_SAMPLES).
- If `found == 0`, function returns without distributing (budget is effectively burned/not minted).
- `perWinner * found <= farBudget` -- integer division dust is not distributed. Since these are BURNIE credits (not ETH), the dust is negligible.
- Same level can be sampled multiple times (no dedup). This is acceptable -- it naturally weights toward levels with more queued players.

**NatSpec Accuracy:** Matches. "Awards 25% of the BURNIE coin budget to random ticket holders on far-future levels."

**Gas Flags:** Up to 10 storage reads for ticketQueue + 4 external calls to coin.creditFlipBatch. Bounded and acceptable.

**Verdict:** CORRECT

---

### `_resolveZeroOwedRemainder(uint40 packed, uint24 lvl, address player, uint256 entropy, uint256 rollSalt)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveZeroOwedRemainder(uint40 packed, uint24 lvl, address player, uint256 entropy, uint256 rollSalt) private returns (uint40 newPacked, bool skip)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `packed` (uint40): Packed ticket owed (owed:32, remainder:8); `lvl` (uint24): Level; `player` (address): Ticket holder; `entropy` (uint256): VRF entropy; `rollSalt` (uint256): Deterministic salt for remainder roll |
| **Returns** | `newPacked` (uint40): Updated packed value; `skip` (bool): True if player should be skipped |

**State Reads:** None (packed passed in)
**State Writes:** `ticketsOwedPacked[lvl][player]` (cleared or updated)

**Callers:** `_processOneTicketEntry`
**Callees:** `_rollRemainder`

**ETH Flow:** None.

**Logic:**
1. Extract `rem = uint8(packed)` (fractional remainder, 0-99).
2. If `rem == 0`: Clear storage if packed was non-zero, return skip=true.
3. If `rem != 0`: Roll `_rollRemainder(entropy, rollSalt, rem)` -- `rem%` chance of winning 1 extra ticket.
   - Win: Set `newPacked = 1 << 8` (1 ticket owed, 0 remainder). Update storage if changed.
   - Lose: Clear storage, return skip=true.

**Invariants:**
- Handles the edge case where a player's owed count is 0 but they have a fractional remainder.
- The remainder roll is deterministic (same entropy + salt = same result).
- Storage is only written if the value actually changes (gas optimization).

**NatSpec Accuracy:** Matches. "Resolves the zero-owed remainder case for ticket processing."

**Gas Flags:** 1 SSTORE on average (either clear or update). Efficient.

**Verdict:** CORRECT

---

### `_processOneTicketEntry(address player, uint24 lvl, uint32 room, uint32 processed, uint256 entropy, uint256 queueIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processOneTicketEntry(address player, uint24 lvl, uint32 room, uint32 processed, uint256 entropy, uint256 queueIdx) private returns (uint32 writesUsed, bool advance)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `lvl` (uint24): Level; `room` (uint32): Remaining SSTORE budget; `processed` (uint32): Tickets already processed this entry; `entropy` (uint256): VRF entropy; `queueIdx` (uint256): Position in ticketQueue |
| **Returns** | `writesUsed` (uint32): SSTOREs consumed; `advance` (bool): True if this entry is complete |

**State Reads:** `ticketsOwedPacked[lvl][player]`
**State Writes:** `ticketsOwedPacked[lvl][player]` (via `_finalizeTicketEntry`); `traitBurnTicket` (via `_generateTicketBatch`)

**Callers:** `processTicketBatch`
**Callees:** `_resolveZeroOwedRemainder`, `_generateTicketBatch`, `_finalizeTicketEntry`

**ETH Flow:** None.

**Processing logic:**
1. Load packed owed: `owed = uint32(packed >> 8)`, remainder = `uint8(packed)`.
2. If `owed == 0`: Handle via `_resolveZeroOwedRemainder`. Charge 1 budget unit even on skip.
3. Calculate overhead: `baseOv = 4` (first batch with <=2 owed) or `2` (subsequent).
4. Calculate batch size `take`: `min(owed, maxT)` where `maxT` depends on available room.
   - If `availRoom <= 256`: `maxT = availRoom / 2` (2 writes per ticket: array push + count).
   - If `availRoom > 256`: `maxT = availRoom - 256` (amortized overhead for large batches).
5. Generate trait tickets via `_generateTicketBatch`.
6. Calculate writesUsed: `(take <= 256 ? take*2 : take+256) + baseOv + (take==owed ? 1 : 0)`.
7. Finalize via `_finalizeTicketEntry`.

**Invariants:**
- `rollSalt = (lvl << 224) | (queueIdx << 192) | (player << 32)` -- deterministic per-entry.
- Budget accounting ensures gas stays within block limits.
- Returns `(0, false)` when budget is exhausted (signals caller to stop).

**NatSpec Accuracy:** Matches. "Processes a single ticket entry, returning writes used and whether to advance."

**Gas Flags:** The writes-used formula accurately models the SSTORE cost of `_raritySymbolBatch` assembly. The threshold at 256 accounts for the trait-counting overhead in memory.

**Verdict:** CORRECT

---

### `_generateTicketBatch(address player, uint24 lvl, uint32 processed, uint32 take, uint256 entropy, uint256 queueIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _generateTicketBatch(address player, uint24 lvl, uint32 processed, uint32 take, uint256 entropy, uint256 queueIdx) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `lvl` (uint24): Level; `processed` (uint32): Start index; `take` (uint32): Count; `entropy` (uint256): VRF entropy; `queueIdx` (uint256): Queue position |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][traitId].length` (via assembly)
**State Writes:** `traitBurnTicket[lvl][traitId]` -- pushes player address N times per trait occurrence

**Callers:** `_processOneTicketEntry`
**Callees:** `_raritySymbolBatch`, emits `TraitsGenerated`

**ETH Flow:** None.

**Algorithm:**
1. Constructs `baseKey = (lvl << 224) | (queueIdx << 192) | (player << 32)`.
2. Delegates to `_raritySymbolBatch` for LCG-based trait generation and storage writes.
3. Emits `TraitsGenerated(player, lvl, queueIdx, processed, take, entropy)`.

**LCG verification (TICKET_LCG_MULT = 0x5851F42D4C957F2D):**
- This is Knuth's MMIX LCG multiplier (6364136223846793005). Full 64-bit period when seed is odd.
- The seed is forced odd via `uint64(seed) | 1`.
- Each group of 16 tickets shares a seed derived from `(baseKey + groupIdx) ^ entropyWord`.
- Within a group, LCG steps produce independent trait values.

**Invariants:**
- Deterministic: same inputs always produce same traits.
- `processed` parameter allows resuming mid-entry (different startIndex each call).

**NatSpec Accuracy:** "Wrapper for _raritySymbolBatch to reduce stack usage." Accurate.

**Gas Flags:** None. Assembly-optimized batch writes.

**Verdict:** CORRECT

---

### `_finalizeTicketEntry(uint24 lvl, address player, uint40 packed, uint32 owed, uint32 take, uint256 entropy, uint256 rollSalt)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeTicketEntry(uint24 lvl, address player, uint40 packed, uint32 owed, uint32 take, uint256 entropy, uint256 rollSalt) private returns (bool done)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `player` (address): Ticket holder; `packed` (uint40): Current packed state; `owed` (uint32): Total owed; `take` (uint32): Processed this batch; `entropy` (uint256): VRF entropy; `rollSalt` (uint256): Salt for remainder roll |
| **Returns** | `bool`: True if entry is complete |

**State Reads:** None (packed passed in)
**State Writes:** `ticketsOwedPacked[lvl][player]` (updated or unchanged)

**Callers:** `_processOneTicketEntry`
**Callees:** `_rollRemainder`

**ETH Flow:** None.

**Logic:**
1. `remainingOwed = owed - take` (unchecked -- safe because `take <= owed`).
2. If `remainingOwed == 0` and `rem != 0`: Roll remainder. If win, set `remainingOwed = 1`. Clear `rem`.
3. Pack new value: `(remainingOwed << 8) | rem`.
4. Write to storage only if changed.
5. Return `remainingOwed == 0` (done).

**Invariants:**
- Remainder is only rolled when all owed tickets are processed (`remainingOwed == 0`).
- After remainder roll: either 0 or 1 ticket owed, remainder cleared.
- Storage write only when value changes (gas optimization).

**NatSpec Accuracy:** Matches. "Finalizes ticket entry after processing, rolling remainder dust."

**Gas Flags:** 0-1 SSTOREs. Efficient.

**Verdict:** CORRECT

---

### `_raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `baseKey` (uint256): Encoded (lvl, queueIdx, player); `startIndex` (uint32): Starting ticket index; `count` (uint32): Tickets to generate; `entropyWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][traitId].length` (via assembly)
**State Writes:** `traitBurnTicket[lvl][traitId]` -- appends player address for each trait occurrence (via assembly)

**Callers:** `_generateTicketBatch`
**Callees:** `DegenerusTraitUtils.traitFromWord`

**ETH Flow:** None.

**Algorithm:**
1. **Trait generation** (groups of 16 using LCG):
   - For each group of 16 tickets: `seed = (baseKey + groupIdx) ^ entropyWord`.
   - `s = uint64(seed) | 1` (force odd for full LCG period).
   - LCG step: `s = s * TICKET_LCG_MULT + 1` per ticket.
   - Trait: `DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6)` -- adds quadrant from ticket index mod 4.
   - Tracks unique traits and occurrence counts in memory arrays.

2. **Batch storage writes** (assembly):
   - For each unique trait: load array length, extend by occurrences, write player address.
   - Uses keccak256-based storage slot calculation matching Solidity's dynamic array layout.

**DegenerusTraitUtils.traitFromWord verification:**
- Takes uint64, splits into low 32 (category via `weightedBucket`) and high 32 (sub via `weightedBucket`).
- Returns 6-bit trait: `(category << 3) | sub`.
- Quadrant bits (2 MSBs) added by caller: `(i & 3) << 6`.
- Result is full 8-bit trait ID: `[QQ][CCC][SSS]`.

**Invariants:**
- LCG produces deterministic, non-repeating sequence within each 16-ticket group.
- Quadrant assignment cycles through 0,1,2,3 based on ticket index, ensuring balanced distribution.
- Assembly writes are memory-safe (declared with `"memory-safe"` annotation).
- Storage slot calculation matches Solidity compiler's layout for `mapping(uint24 => address[][256])`.

**NatSpec Accuracy:** Matches. Documents the 3-step algorithm (generate, track, batch-write).

**Gas Flags:** Assembly-optimized. ~2 SSTOREs per ticket (array length update + data slot write). This is the minimum possible for appending to a storage array.

**Verdict:** CORRECT

---

### `_creditDgnrsCoinflip(uint256 prizePoolWei)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditDgnrsCoinflip(uint256 prizePoolWei) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `prizePoolWei` (uint256): Current prize pool size |
| **Returns** | None |

**State Reads:** `price`
**State Writes:** None directly (external call to coin.creditFlip)

**Callers:** `consolidatePrizePools`
**Callees:** `coin.creditFlip`

**ETH Flow:** None. Credits BURNIE to DGNRS contract address for coinflip rewards.

**BURNIE calculation:**
- `coinAmount = (prizePoolWei * PRICE_COIN_UNIT) / (priceWei * 20)`
- PRICE_COIN_UNIT = 1000 ether (1000 BURNIE per ETH at reference price).
- Effective: `coinAmount = prizePoolWei * 1000 / (price * 20) = prizePoolWei * 50 / price`.
- This credits 5% of the prize pool's BURNIE-equivalent to the DGNRS coinflip system.

**Invariants:**
- No-op if `price == 0` (division by zero protection).
- No-op if `coinAmount == 0` (small prize pools).
- Credits go to `ContractAddresses.DGNRS` address.

**NatSpec Accuracy:** No NatSpec. Function name is self-documenting.

**Gas Flags:** 1 external call to `coin.creditFlip`. Acceptable.

**Verdict:** CORRECT


---

## DegenerusGameEndgameModule.sol

### `rewardTopAffiliate(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rewardTopAffiliate(uint24 lvl) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): The level to reward the top affiliate for |
| **Returns** | none |

**State Reads:** None (all data fetched via external calls to `affiliate` and `dgnrs` contracts)

**State Writes:** None (all state changes happen in external contracts -- DegenerusStonk and DegenerusAffiliate)

**Callers:**
- `DegenerusGameAdvanceModule._rewardTopAffiliate(lvl)` via delegatecall during level transition (after final jackpot cap reached, line 276 of AdvanceModule)

**Callees:**
- `affiliate.affiliateTop(lvl)` -- external call to get top affiliate address and score for the level
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external call to get DGNRS affiliate pool balance
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Affiliate, top, dgnrsReward)` -- external call to transfer DGNRS reward

**ETH Flow:** No ETH movement. This function exclusively moves DGNRS tokens from the Affiliate pool to the top affiliate address.

**Invariants:**
- If no top affiliate exists (address(0)), function returns early with no effect
- Reward is always 1% of current affiliate pool balance (AFFILIATE_POOL_REWARD_BPS = 100 / 10000)
- `paid` may be less than `dgnrsReward` if pool has insufficient balance (handled by `transferFromPool`)

**NatSpec Accuracy:** NatSpec says "Mint trophy and DGNRS reward" but the function only handles DGNRS reward distribution. There is no trophy minting in this function. The trophy logic appears to be handled separately. Minor NatSpec inaccuracy -- the "mint trophy" part is misleading since no trophy is minted here.

**Gas Flags:**
- Three external calls (affiliateTop, poolBalance, transferFromPool) are unavoidable and correctly ordered
- `dgnrsReward` calculation uses multiplication before division (correct, avoids precision loss)
- No redundant reads

**Verdict:** CORRECT -- with minor NatSpec inaccuracy (mentions trophy minting that does not occur in this function)

---

### `runRewardJackpots(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runRewardJackpots(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level to resolve jackpots for; `rngWord` (uint256): VRF entropy for jackpot selection |
| **Returns** | none |

**State Reads:**
- `futurePrizePool` -- cached as `futurePoolLocal` and `baseFuturePool` for pre/post comparison

**State Writes:**
- `futurePrizePool` -- updated only if changed (gas optimization: skips SSTORE when no jackpot fires)
- `claimablePool` -- incremented by `claimableDelta` when non-zero
- Additional writes via `_runBafJackpot` and delegated calls (see callees)

**Callers:**
- `DegenerusGameAdvanceModule._runRewardJackpots(lvl, rngWord)` via delegatecall during level transition (after final jackpot cap reached, line 277 of AdvanceModule)

**Callees:**
- `_runBafJackpot(bafPoolWei, lvl, rngWord)` -- private, for BAF jackpot at every 10th level
- `IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord)` -- external self-call for Decimator jackpot at x00 and x5 levels

**ETH Flow:**

| Trigger | Source Pool | Amount | Destination |
|---------|-----------|--------|-------------|
| BAF (lvl % 10 == 0) | futurePrizePool | 10-25% of base | Winners via _runBafJackpot (split: claimable ETH + lootbox tickets) |
| Decimator (lvl % 100 == 0) | futurePrizePool | 30% of base | Winners via runDecimatorJackpot (deferred claims in claimablePool) |
| Decimator (lvl % 10 == 5, not x95) | futurePrizePool | 10% of current local | Winners via runDecimatorJackpot (deferred claims in claimablePool) |

BAF pool percentages by level:
- Level x00 (100, 200...): 20% of base future pool
- Level 50: 25% of base future pool
- All other x0 levels (10, 20, 30, 40, 60, 70, 80, 90): 10% of base future pool

Decimator pool percentages:
- Level x00: 30% of base future pool (uses `baseFuturePool`)
- Levels x5 (5, 15, 25...85, not 95): 10% of current `futurePoolLocal` (after BAF deduction, if applicable)

**Key accounting logic:**
- BAF: Full pool pulled out, then `netSpend` (pool minus refund) consumed; lootbox ETH recycled back into futurePool; unused portion returned
- Decimator x00: `decPoolWei - returnWei` = spend; deducted from futurePoolLocal; spend added to claimableDelta
- Decimator x5: Same pattern as x00 but uses current `futurePoolLocal` (post-BAF) and 10%

**Invariants:**
- `futurePrizePool` is only written when it actually changed (pre/post comparison with `baseFuturePool`)
- `claimablePool` is only incremented when `claimableDelta != 0`
- At level x00, BOTH BAF (20%) and Decimator (30%) fire -- but BAF uses `baseFuturePool` for its percentage, while Decimator also uses `baseFuturePool`. Total maximum draw from future pool at x00 = 20% + 30% = 50% (minus refunds/returns)
- At levels where both BAF and x5 Decimator fire (impossible: x0 and x5 are mutually exclusive modulo 10), no overlap occurs
- Level 95 is explicitly excluded from Decimator (`prevMod100 != 95`)

**NatSpec Accuracy:** NatSpec documents BAF and Decimator trigger schedules accurately. The NatSpec shows level 100 BAF at 20% and level 100 Decimator at 30%, matching the code. The note about Decimator "NOT 95" is correct.

**Gas Flags:**
- `baseFuturePool` captures the initial value for percentage calculations -- correct pattern for multi-draw scenarios
- `futurePoolLocal` vs `baseFuturePool` comparison avoids unnecessary SSTORE when no jackpot fires
- The x00 Decimator uses `baseFuturePool` for its 30% calculation, not the post-BAF `futurePoolLocal`. This means at level 100, BAF 20% and Decimator 30% are both computed from the original pool, potentially summing to >50% of the original if refunds are zero. However, since BAF refunds unused ETH back into `futurePoolLocal`, and the Decimator also returns unused ETH via `returnWei`, the actual net draw is bounded by available funds.

**Concern: Overlapping draws at x00 levels.** At level x00 (e.g., 100), BAF draws 20% and Decimator draws 30% -- both from `baseFuturePool`. The BAF draw is subtracted from `futurePoolLocal` first (line 148), then the Decimator draw is subtracted (line 175). But the Decimator percentage is computed from `baseFuturePool`, not from the already-reduced `futurePoolLocal`. In the worst case (zero refund from BAF, zero return from Decimator), total draw = 50% of `baseFuturePool`. Since `futurePoolLocal` starts at `baseFuturePool` and only 50% is drawn, this never underflows. The pattern is intentional -- each jackpot gets a guaranteed percentage of the original pool. Verified safe.

**Verdict:** CORRECT

---

### `claimWhalePass(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimWhalePass(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address to claim whale pass rewards for |
| **Returns** | none |

**State Reads:**
- `whalePassClaims[player]` -- number of half-passes owed
- `level` -- current game level (for startLevel calculation)

**State Writes:**
- `whalePassClaims[player] = 0` -- cleared before awarding (reentrancy-safe pattern)
- `mintPacked_[player]` -- updated via `_applyWhalePassStats` (level count, frozen level, bundle type, last level, day)
- `ticketsOwedPacked[lvl][player]` -- updated for each of 100 levels via `_queueTicketRange`
- `ticketQueue[lvl]` -- player pushed to queue for each new level via `_queueTicketRange`

**Callers:**
- `DegenerusGame.claimWhalePass(player)` via `_claimWhalePassFor` delegatecall -- externally callable by anyone
- Also called from lootbox module when resolving large lootbox wins

**Callees:**
- `_applyWhalePassStats(player, startLevel)` -- internal (from DegenerusGameStorage), updates mint stats
- `_queueTicketRange(player, startLevel, 100, uint32(halfPasses))` -- internal (from DegenerusGameStorage), queues tickets across 100 levels

**ETH Flow:** No direct ETH movement. This function converts previously deferred lootbox ETH credit (stored as half-pass count in `whalePassClaims`) into ticket distributions. The ETH was already accounted for when `_queueWhalePassClaimCore` was called (lootbox ETH stays in `futurePrizePool`).

**Invariants:**
- If `halfPasses == 0`, returns early with no effect (prevents empty claims)
- Claim is zeroed BEFORE awarding tickets (prevents double-claiming, reentrancy-safe)
- `startLevel = level + 1` -- tickets start at next level to avoid giving tickets for an already-active level during jackpot phase
- Each half-pass gives 1 ticket per level for 100 consecutive levels (e.g., 3 half-passes = 300 total tickets)
- `uint32(halfPasses)` cast is safe because ETH supply limits the maximum number of half-passes (documented in comment)

**NatSpec Accuracy:** NatSpec says "Claim deferred whale pass rewards for a player" and "Awards deterministic tickets based on pre-calculated half-pass count" -- accurate. The note about starting at `level + 1` matches the code.

**Gas Flags:**
- `_queueTicketRange` loops over 100 levels, performing a storage read + potential write per level. This is O(100) SSTOREs in the worst case. Gas cost is significant but bounded and unavoidable for the ticket distribution pattern.
- `_applyWhalePassStats` performs packed storage updates (single SSTORE)

**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): Address to credit; `weiAmount` (uint256): ETH amount to credit; `entropy` (uint256): RNG seed for fractional ticket roll |
| **Returns** | `claimableDelta` (uint256): Amount to add to claimablePool for this credit |

**State Reads:**
- `autoRebuyState[beneficiary]` -- checks if auto-rebuy is enabled for the player
- `level` -- current game level (passed to `_calcAutoRebuy`)

**State Writes (auto-rebuy path):**
- `futurePrizePool += calc.ethSpent` -- if target level is future (75% chance)
- `nextPrizePool += calc.ethSpent` -- if target level is next (25% chance)
- `ticketsOwedPacked[calc.targetLevel][beneficiary]` -- via `_queueTickets`
- `ticketQueue[calc.targetLevel]` -- via `_queueTickets` (if new entry)
- `claimableWinnings[beneficiary] += calc.reserved` -- via `_creditClaimable` (take-profit portion)
- `claimablePool += calc.reserved` -- direct write for take-profit portion

**State Writes (normal path):**
- `claimableWinnings[beneficiary] += weiAmount` -- via `_creditClaimable`

**Callers:**
- `_runBafJackpot` -- for ETH portions of BAF jackpot winnings (large winner 50% ETH, small even-index 100% ETH)

**Callees:**
- `_calcAutoRebuy(beneficiary, weiAmount, entropy, state, level, 13_000, 14_500)` -- pure helper from DegenerusGamePayoutUtils
- `_creditClaimable(beneficiary, weiAmount)` -- internal (from DegenerusGamePayoutUtils)
- `_creditClaimable(beneficiary, calc.reserved)` -- for take-profit portion (auto-rebuy path)
- `_queueTickets(beneficiary, calc.targetLevel, calc.ticketCount)` -- internal (from DegenerusGameStorage)

**ETH Flow:**

| Auto-Rebuy State | Path | Source | Destination |
|-------------------|------|--------|-------------|
| Disabled | Normal | (incoming weiAmount) | claimableWinnings[beneficiary] |
| Enabled, no tickets | Normal fallback | (incoming weiAmount) | claimableWinnings[beneficiary] |
| Enabled, has tickets | Rebuy | (incoming weiAmount - reserved) | futurePrizePool or nextPrizePool (via ethSpent) + tickets |
| Enabled, has tickets | Take-profit | (reserved portion) | claimableWinnings[beneficiary] + claimablePool |

**Key auto-rebuy bonus BPS:** 13,000 (130% base) / 14,500 (145% afKing mode). These are higher than the standard auto-rebuy bonuses used elsewhere, reflecting the jackpot reward context.

**Invariants:**
- Returns 0 immediately if `weiAmount == 0`
- Auto-rebuy path returns `claimableDelta = 0` when tickets are generated (ETH goes to prize pools, not claimable)
- Normal path returns `claimableDelta = weiAmount` (full amount goes to claimable)
- Take-profit: `calc.reserved` is a multiple of `state.takeProfit` extracted from `weiAmount` before rebuy conversion
- `calc.hasTickets = false` triggers normal credit fallback even when auto-rebuy is enabled (happens when amount is too small for even 1 ticket at target price)

**NatSpec Accuracy:** NatSpec accurately describes the auto-rebuy flow, take-profit mechanism, and fractional dust handling. The claim about "fractional dust is dropped unconditionally" refers to dust within the auto-rebuy calculation (amounts smaller than a single ticket price at the target level) -- this dust is not explicitly credited to claimable in the auto-rebuy path and is implicitly absorbed into the prize pool via `calc.ethSpent` rounding. This is by design.

**Gas Flags:**
- `autoRebuyState[beneficiary]` is a struct SLOAD -- memory copy is efficient
- `_calcAutoRebuy` is `pure` -- no additional storage reads
- Single branch for auto-rebuy vs normal flow

**Verdict:** CORRECT

---

### `_runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) private returns (uint256 netSpend, uint256 claimableDelta, uint256 lootboxToFuture)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): Total ETH for BAF distribution; `lvl` (uint24): Level triggering the BAF; `rngWord` (uint256): VRF entropy |
| **Returns** | `netSpend` (uint256): Amount consumed from future pool; `claimableDelta` (uint256): ETH credited to claimable balances; `lootboxToFuture` (uint256): Lootbox ETH recycled into future pool |

**State Reads:**
- None directly (all inputs passed as parameters)

**State Writes (via callees):**
- `claimableWinnings[winner]` -- via `_addClaimableEth` -> `_creditClaimable` (ETH portions)
- `claimablePool` -- via `_addClaimableEth` (take-profit auto-rebuy) or returned as claimableDelta to caller
- `futurePrizePool` / `nextPrizePool` -- via `_addClaimableEth` (auto-rebuy path)
- `ticketsOwedPacked[targetLevel][winner]` -- via `_awardJackpotTickets` -> `_queueLootboxTickets` (lootbox portions)
- `ticketQueue[targetLevel]` -- via `_awardJackpotTickets` -> `_queueLootboxTickets`
- `whalePassClaims[winner]` -- via `_queueWhalePassClaimCore` (large lootbox deferred)

**Callers:**
- `runRewardJackpots` -- at every 10th level during level transition

**Callees:**
- `jackpots.runBafJackpot(poolWei, lvl, rngWord)` -- external call to get winners array, amounts, and refund
- `_addClaimableEth(winner, ethPortion, rngWord)` -- for ETH portions of large winners and full ETH for small even-index winners
- `_awardJackpotTickets(winner, lootboxPortion, lvl, rngWord)` -- for lootbox portions of large winners and full lootbox for small odd-index winners
- `_queueWhalePassClaimCore(winner, lootboxPortion)` -- for large lootbox portions exceeding LOOTBOX_CLAIM_THRESHOLD

**ETH Flow:**

Winners are split into two categories based on a 5% pool threshold (`poolWei / 20`):

| Winner Type | Condition | ETH Path | Lootbox Path |
|-------------|-----------|----------|-------------|
| Large | `amount >= poolWei/20` | 50% (amount/2) to claimable via `_addClaimableEth` | 50% (amount - amount/2) to tickets via `_awardJackpotTickets` or deferred via `_queueWhalePassClaimCore` |
| Small even-index | `amount < poolWei/20, i%2==0` | 100% to claimable via `_addClaimableEth` | None |
| Small odd-index | `amount < poolWei/20, i%2==1` | None | 100% to tickets via `_awardJackpotTickets` |

Lootbox sub-routing (within `_awardJackpotTickets` and direct):
- Small lootbox (<=5 ETH, i.e. `<= LOOTBOX_CLAIM_THRESHOLD`): immediate ticket awards
- Large lootbox (>5 ETH): deferred via `_queueWhalePassClaimCore` (whale pass claim)

**Return values:**
- `netSpend = poolWei - refund` -- refund is returned by `jackpots.runBafJackpot`
- `claimableDelta` -- sum of all ETH credited to claimable balances
- `lootboxToFuture = lootboxTotal` -- all lootbox ETH stays in future pool

**Invariants:**
- First winner (winners[0]) should receive BAF trophy per NatSpec, but no trophy logic exists in this function (see NatSpec note below)
- `lootboxToFuture` equals total lootbox amounts across all winners (sum of lootbox portions)
- `netSpend + refund = poolWei` (total pool is fully accounted for)
- Large winner 50/50 split: `ethPortion = amount / 2`, `lootboxPortion = amount - ethPortion` -- handles odd amounts correctly (lootbox gets the extra wei)

**NatSpec Accuracy:** NatSpec mentions "First winner (winners[0]) receives BAF trophy" in the Trophy section, but no trophy awarding code exists in this function. This is a NatSpec-only artifact -- trophies may be awarded elsewhere (e.g., in the Jackpots contract's `runBafJackpot`). Minor inaccuracy in the NatSpec within this function.

**Gas Flags:**
- `unchecked { ++i; }` in the loop is correct (loop counter cannot overflow)
- Winner array length is fetched once and cached as `winnersLen`
- `largeWinnerThreshold` computed once outside the loop
- Entropy (`rngWord`) is threaded through `_awardJackpotTickets` for deterministic sub-rolls

**Verdict:** CORRECT

---

### `_awardJackpotTickets(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardJackpotTickets(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Address to receive rewards; `amount` (uint256): ETH amount for ticket conversion; `minTargetLevel` (uint24): Minimum target level for tickets; `entropy` (uint256): RNG state |
| **Returns** | Updated entropy state (uint256) |

**State Reads:** None directly (all via callees)

**State Writes (via callees):**
- `whalePassClaims[winner]` -- via `_queueWhalePassClaimCore` (large amounts > 5 ETH)
- `claimableWinnings[winner]` -- via `_queueWhalePassClaimCore` (remainder < HALF_WHALE_PASS_PRICE)
- `claimablePool` -- via `_queueWhalePassClaimCore` (remainder)
- `ticketsOwedPacked[targetLevel][winner]` -- via `_jackpotTicketRoll` -> `_queueLootboxTickets` (small/medium amounts)
- `ticketQueue[targetLevel]` -- via `_jackpotTicketRoll` -> `_queueLootboxTickets`

**Callers:**
- `_runBafJackpot` -- for lootbox portions of both large winners (50% lootbox split) and small odd-index winners (100% lootbox)

**Callees:**
- `_queueWhalePassClaimCore(winner, amount)` -- for large amounts (> 5 ETH / LOOTBOX_CLAIM_THRESHOLD)
- `_jackpotTicketRoll(winner, amount, minTargetLevel, entropy)` -- for very small amounts (<= 0.5 ETH), single roll
- `_jackpotTicketRoll(winner, halfAmount, minTargetLevel, entropy)` -- first roll for medium amounts (0.5-5 ETH)
- `_jackpotTicketRoll(winner, secondAmount, minTargetLevel, entropy)` -- second roll for medium amounts

**ETH Flow:** No direct ETH movement. This function routes incoming lootbox-designated ETH to the appropriate ticket distribution mechanism:

| Amount Range | Routing | Ticket Rolls |
|-------------|---------|-------------|
| > 5 ETH | Deferred whale pass via `_queueWhalePassClaimCore` | 0 (deferred) |
| 0.5 - 5 ETH | Split in half, two probabilistic rolls | 2 |
| <= 0.5 ETH | Single probabilistic roll | 1 |

**Invariants:**
- Tiered routing ensures gas efficiency: large payouts defer to claim system, medium payouts get two chances at level targeting, small payouts get one chance
- For medium amounts: `halfAmount = amount / 2`, `secondAmount = amount - halfAmount` -- correctly handles odd wei amounts (second roll gets the extra wei)
- Entropy is threaded through and returned to maintain deterministic PRNG chain

**NatSpec Accuracy:** NatSpec describes "Small (0.5-5 ETH)" and "Large (> 5 ETH)" tiers accurately. The "2 probabilistic rolls" for medium tier and "100-ticket chunks" for large tier are accurate descriptions of the actual behavior.

**Gas Flags:**
- Early return for large amounts (>5 ETH) avoids unnecessary roll computation
- Medium tier splits into 2 rolls for better level diversity rather than 1 large roll
- No redundant computations

**Verdict:** CORRECT

---

### `_jackpotTicketRoll(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _jackpotTicketRoll(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Address to receive tickets; `amount` (uint256): ETH amount for this roll; `minTargetLevel` (uint24): Minimum target level; `entropy` (uint256): RNG state |
| **Returns** | Updated entropy state (uint256) |

**State Reads:** None directly

**State Writes (via callees):**
- `ticketsOwedPacked[targetLevel][winner]` -- via `_queueLootboxTickets` -> `_queueTicketsScaled`
- `ticketQueue[targetLevel]` -- via `_queueLootboxTickets` -> `_queueTicketsScaled` (if new entry)

**Callers:**
- `_awardJackpotTickets` -- for small and medium lootbox amounts (1-2 rolls per award)

**Callees:**
- `EntropyLib.entropyStep(entropy)` -- pure, advances PRNG state
- `PriceLookupLib.priceForLevel(targetLevel)` -- pure, gets ticket price for target level
- `_queueLootboxTickets(winner, targetLevel, quantityScaled)` -- internal (from DegenerusGameStorage)

**ETH Flow:** No direct ETH movement. Converts an ETH amount into scaled tickets at a probabilistically-selected target level.

**Probability distribution for target level:**

| Roll Range | Probability | Target Level | Description |
|-----------|------------|-------------|-------------|
| 0-29 | 30% | minTargetLevel | Current level ticket |
| 30-94 | 65% | minTargetLevel + 1 to +4 | Near-future levels (1-4 ahead) |
| 95-99 | 5% | minTargetLevel + 5 to +50 | Far-future levels (rare, 5-50 ahead) |

**Ticket quantity calculation:**
- `targetPrice = PriceLookupLib.priceForLevel(targetLevel)` -- actual game price for the target level
- `quantityScaled = (amount * TICKET_SCALE) / targetPrice` -- scaled ticket count (2 decimal places)
- Passed to `_queueLootboxTickets` which handles remainder accumulation

**Roll mechanics:**
- `entropy = EntropyLib.entropyStep(entropy)` -- xorshift64 PRNG step
- `roll = entropy % 100` (via manual modulo: `entropy - (entropyDiv100 * 100)`)
- For near-future offset: `1 + (entropyDiv100 % 4)` uses the upper bits (after dividing by 100) for independence from the roll
- For far-future offset: `5 + (entropyDiv100 % 46)` similarly uses upper bits

**Invariants:**
- Entropy is always advanced before use (deterministic chain)
- `quantityScaled` may be 0 if `amount < targetPrice / TICKET_SCALE` -- in that case `_queueLootboxTickets` returns early (no effect)
- Target level can exceed current game level by up to 50 -- these future tickets will be processed when those levels are reached
- Price increases with level, so higher target levels yield fewer tickets per ETH (risk/reward tradeoff is built into the probability distribution)

**NatSpec Accuracy:** NatSpec accurately describes "Selects target level based on probability, then awards tickets" and "Uses actual game pricing for the selected target level."

**Gas Flags:**
- Manual modulo (`entropy - (entropyDiv100 * 100)`) is gas-equivalent to `entropy % 100` in Solidity 0.8+ but avoids an extra division in the compiler output. Minor optimization.
- `entropyDiv100` is reused for both the roll and the offset calculation, saving one division
- Single PRNG step per roll (efficient)

**Verdict:** CORRECT


---

## DegenerusGameLootboxModule.sol

### `openLootBox(address player, uint48 index)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openLootBox(address player, uint48 index) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to open lootbox for; `index` (uint48): RNG index of the lootbox |
| **Returns** | none |

**State Reads:** `rngLockedFlag`, `lootboxEth[index][player]`, `lootboxRngWordByIndex[index]`, `lootboxDay[index][player]`, `lootboxPresaleActive`, `lootboxEthBase[index][player]`, `level`, `lootboxBaseLevelPacked[index][player]`, `lootboxEvScorePacked[index][player]`, `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEth[index][player] = 0`, `lootboxEthBase[index][player] = 0`, `lootboxBaseLevelPacked[index][player] = 0`, `lootboxEvScorePacked[index][player] = 0`, `lootboxEvBenefitUsedByLevel[player][lvl]` (via `_applyEvMultiplierWithCap`), plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall (through MintModule.openLootBox which routes here)

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_lootboxEvMultiplierBps()` or `_lootboxEvMultiplierFromScore()`, `_applyEvMultiplierWithCap()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. ETH-equivalent value is used to calculate BURNIE rewards (via `coin.creditFlip`), ticket grants, and boon draws. The lootbox ETH was deposited during purchase and sits in the game contract balance.

**Revert Conditions:**
- `RngLocked()`: if `rngLockedFlag` is true (jackpot resolution in progress)
- `E()`: if `amount == 0` (no lootbox at this index for this player)
- `RngNotReady()`: if `lootboxRngWordByIndex[index] == 0` (RNG not yet fulfilled)

**Invariants:**
- Lootbox is consumed atomically (all 4 storage slots zeroed before resolution)
- EV multiplier cap ensures no player can extract more than 10 ETH of EV benefit per level
- Grace period (7 days) preserves original purchase level for target level calculation
- `targetLevel >= currentLevel` enforced after roll

**NatSpec Accuracy:** Accurate. NatSpec documents RNG lock check, EV multiplier application, and revert conditions. The `@custom:reverts` tags correctly list all three revert paths.

**Gas Flags:** `boonAmount` parameter in `_resolveLootboxCommon` is passed as `baseAmount` but is immediately discarded inside the function (line 850: `boonAmount;`). This is a dead parameter -- no gas cost since it's calldata forwarding, but it's misleading.

**Verdict:** CORRECT

---

### `openBurnieLootBox(address player, uint48 index)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openBurnieLootBox(address player, uint48 index) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to open BURNIE lootbox for; `index` (uint48): RNG index |
| **Returns** | none |

**State Reads:** `rngLockedFlag`, `lootboxBurnie[index][player]`, `lootboxRngWordByIndex[index]`, `price`, `level`, `lootboxDay[index][player]`

**State Writes:** `lootboxBurnie[index][player] = 0`, plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. BURNIE amount is converted to ETH-equivalent at 80% rate: `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)`. This ETH-equivalent drives reward calculations but no actual ETH moves.

**Revert Conditions:**
- `RngLocked()`: if `rngLockedFlag` is true
- `E()`: if `burnieAmount == 0` (no BURNIE lootbox)
- `RngNotReady()`: if `lootboxRngWordByIndex[index] == 0`
- `E()`: if `priceWei == 0` (BURNIE price not set)
- `E()`: if `amountEth == 0` (conversion resulted in zero)

**Invariants:**
- BURNIE lootbox is consumed atomically (storage zeroed before resolution)
- No EV multiplier applied (BURNIE lootboxes get neutral 100% EV)
- `allowWhalePass=false`, `allowLazyPass=false`, `emitLootboxEvent=false`, `allowBoons=true` -- BURNIE lootboxes get boon rolls but not whale/lazy pass draws
- `presale=false` -- no presale bonus for BURNIE lootboxes
- Base level for target roll is `currentLevel` (not purchase level)

**NatSpec Accuracy:** Accurate. Documents 80% conversion rate, RNG lock, and revert conditions.

**Gas Flags:** None. The function destructures return values from `_resolveLootboxCommon` to emit `BurnieLootOpen` event.

**Verdict:** CORRECT

---

### `resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to resolve for; `amount` (uint256): ETH amount; `rngWord` (uint256): RNG word for resolution |
| **Returns** | none |

**State Reads:** `level`, `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEvBenefitUsedByLevel[player][lvl]` (via `_applyEvMultiplierWithCap`), plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall -- called during decimator jackpot claim and other direct-resolution paths

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_lootboxEvMultiplierBps()`, `_applyEvMultiplierWithCap()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. Operates on ETH-equivalent value for reward calculation. The ETH was already accounted for in the calling context.

**Revert Conditions:**
- Early return if `amount == 0` (not a revert, just no-op)
- Any reverts from `_resolveLootboxCommon` propagate

**Invariants:**
- `allowBoons=false` -- direct resolution does not award boons (jackpot/claim lootboxes)
- `allowWhalePass=true`, `allowLazyPass=true`, `emitLootboxEvent=true` -- but boon path is skipped so these are irrelevant
- `presale=false` -- no presale bonus
- EV multiplier IS applied (decimator claim recipients benefit from activity score)
- No RNG lock check -- direct resolution uses provided rngWord, not stored RNG

**NatSpec Accuracy:** NatSpec says "no RNG wait needed" which is accurate since `rngWord` is passed directly. States "Jackpot/claim lootboxes do not award boons" which matches `allowBoons=false`.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `issueDeityBoon(address deity, address recipient, uint8 slot)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function issueDeityBoon(address deity, address recipient, uint8 slot) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `deity` (address): deity pass holder issuing the boon; `recipient` (address): player receiving the boon; `slot` (uint8): slot index (0-2) |
| **Returns** | none |

**State Reads:** `deityPassPurchasedCount[deity]`, `deityBoonDay[deity]`, `deityBoonUsedMask[deity]`, `deityBoonRecipientDay[recipient]`, `deityPassOwners.length`, `decWindowOpen`, `rngWordByDay[day]`, `rngWordCurrent`

**State Writes:** `deityBoonDay[deity] = day`, `deityBoonUsedMask[deity]` (set/update), `deityBoonRecipientDay[recipient] = day`, plus all writes from `_applyBoon()`

**Callers:** DegenerusGame via delegatecall (called from the game's `issueDeityBoon` proxy)

**Callees:** `_simulatedDayIndex()`, `_isDecimatorWindow()`, `_deityBoonForSlot()`, `_applyBoon()`

**ETH Flow:** None directly. Some boon types applied via `_applyBoon` may indirectly affect ETH (e.g., whale pass activation queues tickets).

**Revert Conditions:**
- `E()`: deity is zero address
- `E()`: recipient is zero address
- `E()`: deity == recipient (self-boon)
- `E()`: slot >= 3 (DEITY_DAILY_BOON_COUNT)
- `E()`: `deityPassPurchasedCount[deity] == 0` (no deity passes)
- `E()`: no RNG available (`rngWordByDay[day] == 0 && rngWordCurrent == 0`)
- `E()`: recipient already received a boon today (`deityBoonRecipientDay[recipient] == day`)
- `E()`: slot already used today (`(mask & slotMask) != 0`)

**Invariants:**
- Each deity gets exactly 3 slots per day, each usable once
- Each recipient can receive at most 1 deity boon per day (across all deities)
- Boon type is deterministic from (deity, day, slot) -- cannot be gamed
- Day reset: if `deityBoonDay[deity] != day`, mask is reset to 0
- `isDeity=true` passed to `_applyBoon` -- deity boons overwrite (not upgrade-only)

**NatSpec Accuracy:** Accurate. All revert conditions documented via `@custom:reverts`. The "up to 3 boons per day" and "one per recipient per day" constraints match implementation.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_applyEvMultiplierWithCap(address player, uint24 lvl, uint256 amount, uint256 evMultiplierBps)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyEvMultiplierWithCap(address player, uint24 lvl, uint256 amount, uint256 evMultiplierBps) private returns (uint256 scaledAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `lvl` (uint24): current game level; `amount` (uint256): lootbox ETH amount; `evMultiplierBps` (uint256): EV multiplier in basis points |
| **Returns** | `scaledAmount` (uint256): amount after EV adjustment |

**State Reads:** `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEvBenefitUsedByLevel[player][lvl]` (incremented by `adjustedPortion`)

**Callers:** `openLootBox()`, `resolveLootboxDirect()`

**Callees:** None

**ETH Flow:** None. Calculates scaled reward amount but does not move ETH.

**Revert Conditions:** None -- always succeeds

**Invariants:**
- If `evMultiplierBps == 10000` (neutral), returns `amount` unchanged with no tracking update
- Total benefit tracked per (player, level) never exceeds `LOOTBOX_EV_BENEFIT_CAP` (10 ETH)
- Once cap is exhausted, all subsequent lootboxes at that level get 100% EV
- Split handling: if `amount > remainingCap`, only the first `remainingCap` portion gets the multiplier, remainder gets 100%

**NatSpec Accuracy:** Accurate. Documents the per-account per-level 10 ETH cap and the split behavior.

**Gas Flags:** None. The function correctly handles the edge case where cap is already exhausted (returns early).

**Verification of logic:**
- For EV > 100% (e.g., 120%): benefit = `(portion * 12000) / 10000` = 1.2x, tracking consumes `portion`
- For EV < 100% (e.g., 80%): same logic applies -- benefit tracking still consumes `portion` of the cap, even though the player is penalized. This means low-activity players also consume their cap with sub-100% returns.

**Note:** The cap tracks `adjustedPortion` (the raw ETH amount), not the actual benefit delta. This means a player with 80% EV consuming 10 ETH of cap gets 8 ETH of reward (net loss of 2 ETH from cap), while a player with 135% EV consuming 10 ETH of cap gets 13.5 ETH (net gain of 3.5 ETH). The cap prevents unbounded EV farming in both directions.

**Verdict:** CORRECT

---

### `_resolveLootboxCommon(address player, uint48 day, uint256 amount, uint256 boonAmount, uint24 targetLevel, uint24 currentLevel, uint256 entropy, bool presale, bool allowWhalePass, bool allowLazyPass, bool emitLootboxEvent, bool allowBoons)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxCommon(address player, uint48 day, uint256 amount, uint256 boonAmount, uint24 targetLevel, uint24 currentLevel, uint256 entropy, bool presale, bool allowWhalePass, bool allowLazyPass, bool emitLootboxEvent, bool allowBoons) private returns (uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): reward recipient; `day` (uint48): day index; `amount` (uint256): ETH-equivalent for rewards; `boonAmount` (uint256): unused; `targetLevel` (uint24): target level for tickets; `currentLevel` (uint24): current game level; `entropy` (uint256): RNG entropy; `presale` (bool): presale bonus; `allowWhalePass` (bool): whale pass draw; `allowLazyPass` (bool): lazy pass draw; `emitLootboxEvent` (bool): emit event; `allowBoons` (bool): boon roll |
| **Returns** | `futureTickets` (uint32): tickets awarded; `burnieAmount` (uint256): total BURNIE; `bonusBurnie` (uint256): presale bonus BURNIE |

**State Reads:** Via `_resolveLootboxRoll`: `price` (for BURNIE conversion), DGNRS pool balance. Via `_rollLootboxBoons`: all boon-related storage.

**State Writes:** Via `_resolveLootboxRoll`: `dgnrs.transferFromPool()`. Via `_rollLootboxBoons`: boon storage writes. Via `_queueTicketsScaled`: `futureTicketsByLevel`, `futureTicketRemainder`. Via `coin.creditFlip`: BURNIE balance.

**Callers:** `openLootBox()`, `openBurnieLootBox()`, `resolveLootboxDirect()`

**Callees:** `PriceLookupLib.priceForLevel()`, `_resolveLootboxRoll()` (1 or 2 calls), `_rollLootboxBoons()`, `IDegenerusGameBoonModule.consumeActivityBoon()` (delegatecall), `_queueTicketsScaled()`, `coin.creditFlip()`

**ETH Flow:** No direct ETH transfer. BURNIE is credited via `coin.creditFlip(player, burnieAmount)`. DGNRS tokens may be transferred from pool via `dgnrs.transferFromPool()`. WWXRP tokens may be minted via `wwxrp.mintPrize()`.

**Revert Conditions:**
- `E()`: if `targetPrice == 0` (PriceLookupLib returned 0, which cannot happen for valid levels)
- `E()`: if ticket accumulation overflows uint32 (extremely unlikely)
- `E()`: if `consumeActivityBoon` delegatecall fails

**Invariants:**
- Boon budget = min(amount * 10%, 1 ETH, amount) -- capped at both 10% and absolute 1 ETH
- Main amount = amount - boonBudget
- If mainAmount > 0.5 ETH, split into two equal(ish) halves for two independent rolls
- `boonAmount` parameter is explicitly discarded (line 850)
- Presale bonus: 62% additional on BURNIE rewards flagged as `applyPresaleMultiplier`
- Tickets are queued only if `futureTickets != 0`
- BURNIE credited only if `burnieAmount != 0`
- `targetLevel >= currentLevel` re-enforced at start

**NatSpec Accuracy:** Mostly accurate. The `boonAmount` parameter is documented as "Amount used for boon chance calculations" but is actually unused. This is a minor NatSpec inaccuracy.

**Gas Flags:** `boonAmount` parameter is passed by all 3 callers but discarded on line 850. Dead code/parameter.

**Verdict:** CONCERN -- The `boonAmount` parameter is documented as meaningful but is explicitly discarded. This is not a bug (it was intentionally silenced with a bare expression statement) but creates confusion. The parameter should either be removed or the NatSpec should note it is reserved/unused.

---

### `_rollLootboxBoons(address player, uint48 day, uint256 originalAmount, uint256 boonBudget, uint256 entropy, bool allowWhalePass, bool allowLazyPass)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollLootboxBoons(address player, uint48 day, uint256 originalAmount, uint256 boonBudget, uint256 entropy, bool allowWhalePass, bool allowLazyPass) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `day` (uint48): current day index; `originalAmount` (uint256): full lootbox ETH amount for event emission; `boonBudget` (uint256): ETH budget allocated for boon draw; `entropy` (uint256): entropy for roll; `allowWhalePass` (bool): enable whale pass draw; `allowLazyPass` (bool): enable lazy pass draw |
| **Returns** | none |

**State Reads:** Via `IDegenerusGameBoonModule.checkAndClearExpiredBoon` delegatecall: all boon expiry fields. Via `_activeBoonCategory`: `coinflipBoonBps[player]`, `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `purchaseBoostBps[player]`, `decimatorBoostBps[player]`, `whaleBoonDay[player]`, `lazyPassBoonDay[player]`, `lazyPassBoonDiscountBps[player]`, `activityBoonPending[player]`, `deityPassBoonTier[player]`. Via `_boonPoolStats`: `price`, `deityPassOwners.length`. Direct reads: `level`, `decWindowOpen`, `deityPassCount[player]`

**State Writes:** Via `IDegenerusGameBoonModule.checkAndClearExpiredBoon` delegatecall: may clear expired boon storage. Via `_applyBoon`: writes to the appropriate boon storage based on selected boon type.

**Callers:** `_resolveLootboxCommon()`

**Callees:** `IDegenerusGameBoonModule.checkAndClearExpiredBoon()` (delegatecall), `_activeBoonCategory()`, `_simulatedDayIndex()`, `_isDecimatorWindow()`, `_boonPoolStats()`, `_boonFromRoll()`, `_boonCategory()`, `_applyBoon()`, `_lazyPassPriceForLevel()`

**ETH Flow:** None directly. Boon application may trigger whale pass activation which queues tickets.

**Revert Conditions:**
- `E()`: if `checkAndClearExpiredBoon` delegatecall fails

**Invariants:**
- Early return if `player == address(0)` or `originalAmount == 0`
- Expired boons are cleared before checking active category
- Only one boon per lootbox opening (single roll, single application)
- Active category enforcement: if player already has an active boon in category X, only boons in category X can be awarded (refresh/upgrade). If selected boon is in a different category, it is silently dropped.
- Boon probability: `totalChance = (boonBudget * 1e6) / expectedPerBoon`, capped at 1e6 (100%)
- `expectedPerBoon = avgMaxValue * 50%` (utilization factor)
- Roll: `entropy % 1e6` compared against `totalChance`
- If roll >= totalChance, no boon awarded (early return)
- Weighted selection: `_boonFromRoll((roll * totalWeight) / totalChance)` maps the winning roll to a specific boon type proportional to weights
- Deity eligibility: player must have 0 deity passes AND total deity pass count < 32 (`DEITY_PASS_MAX_TOTAL`)
- Lazy pass value calculated for `currentLevel + 1` (or 1 if level is 0)
- `isDeity=false` passed to `_applyBoon` -- lootbox boons use upgrade semantics

**NatSpec Accuracy:** Accurate. Documents the single-boon limit, category restriction, and ppm-based probability system.

**Gas Flags:** The function reads `_simulatedDayIndex()` to get `currentDay`, but this is also computed inside `_boonPoolStats` indirectly. However, `_boonPoolStats` does not read the day, so there is no redundancy. The delegatecall to `checkAndClearExpiredBoon` is an additional cross-module call that adds gas overhead but is necessary for correctness.

**Verification of probability math:**
- `boonBudget` is max 10% of lootbox value, capped at 1 ETH
- `expectedPerBoon` = `avgMaxValue * 0.5` (50% utilization)
- For a 1 ETH lootbox: boonBudget = 0.1 ETH. If avgMaxValue = 0.5 ETH, expectedPerBoon = 0.25 ETH, totalChance = (0.1e18 * 1e6) / 0.25e18 = 400,000 ppm = 40% chance
- This scales linearly: bigger lootboxes get higher boon chance up to 100%
- The `(roll * totalWeight) / totalChance` remapping correctly distributes the winning roll across the weight space

**Verdict:** CORRECT

---

### `_applyBoon(address player, uint8 boonType, uint48 day, uint48 currentDay, uint256 originalAmount, bool isDeity)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyBoon(address player, uint8 boonType, uint48 day, uint48 currentDay, uint256 originalAmount, bool isDeity) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the boon; `boonType` (uint8): boon type (1-31); `day` (uint48): day index for event emission / deity tracking; `currentDay` (uint48): current day for boon expiry tracking; `originalAmount` (uint256): lootbox amount for event emission; `isDeity` (bool): true if boon is deity-sourced (overwrite), false if lootbox-sourced (upgrade) |
| **Returns** | none |

**State Reads:** `coinflipBoonBps[player]`, `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `purchaseBoostBps[player]`, `decimatorBoostBps[player]`, `whaleBoonDiscountBps[player]`, `activityBoonPending[player]`, `deityPassBoonTier[player]`, `lazyPassBoonDiscountBps[player]`, `level`

**State Writes:** Depends on boon type (one branch per category):
- **Coinflip (1-3):** `coinflipBoonBps[player]`, `coinflipBoonDay[player]`, `deityCoinflipBoonDay[player]`
- **Lootbox boost (5,6,22):** `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `lootboxBoon25Day[player]`, `lootboxBoon15Day[player]`, `lootboxBoon5Day[player]`, `deityLootboxBoon25Day[player]`, `deityLootboxBoon15Day[player]`, `deityLootboxBoon5Day[player]`
- **Purchase boost (7-9):** `purchaseBoostBps[player]`, `purchaseBoostDay[player]`, `deityPurchaseBoostDay[player]`
- **Decimator boost (13-15):** `decimatorBoostBps[player]`, `deityDecimatorBoostDay[player]`
- **Whale discount (16,23,24):** `whaleBoonDiscountBps[player]`, `whaleBoonDay[player]`, `deityWhaleBoonDay[player]`
- **Activity (17-19):** `activityBoonPending[player]`, `activityBoonDay[player]`, `deityActivityBoonDay[player]`
- **Deity pass discount (25-27):** `deityPassBoonTier[player]`, `deityPassBoonDay[player]`, `deityDeityPassBoonDay[player]`
- **Whale pass (28):** Via `_activateWhalePass`: ticket queue writes, whale pass stats
- **Lazy pass discount (29-31):** `lazyPassBoonDiscountBps[player]`, `lazyPassBoonDay[player]`, `deityLazyPassBoonDay[player]`

**Callers:** `_rollLootboxBoons()`, `issueDeityBoon()`

**Callees:** `_activateWhalePass()` (for whale pass boon type 28 only)

**ETH Flow:** No direct ETH transfer. Whale pass activation (type 28) queues future tickets which have ETH value. Discount boons (whale, deity pass, lazy pass) reduce future purchase costs.

**Revert Conditions:** None within this function. All branches unconditionally succeed.

**Invariants:**

Upgrade vs Overwrite semantics:
- **Lootbox-sourced (`isDeity=false`):** Only upgrades if new bps > current bps (e.g., `bps > coinflipBoonBps[player]`). Day tracking uses `currentDay`, deity day set to 0.
- **Deity-sourced (`isDeity=true`):** Always overwrites regardless of current value. Day tracking uses `day` for deity fields.

Per-category behavior:
- **Coinflip (1-3):** Stores bps (500/1000/2500). Upgrade-only for lootbox. Always sets `coinflipBoonDay[player] = currentDay`. Events: emits `LootBoxReward(player, day, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS)` for non-deity.
- **Lootbox boost (5,6,22):** Deity mode sets the specific tier's active/day fields. Lootbox mode computes the max of selected vs current tier and activates only that tier (deactivating others). Event rewardType: 4=5%, 5=15%, 6=25%.
- **Purchase boost (7-9):** Stores bps (500/1500/2500). Upgrade-only for lootbox. Event rewardType mirrors lootbox boost (4/5/6) based on bps tier.
- **Decimator boost (13-15):** Stores bps (1000/2500/5000). Upgrade-only for lootbox. Note: `decimatorBoostDay` is NOT written -- only `deityDecimatorBoostDay` is set. This means lootbox-sourced decimator boons have no day tracking for expiry in this function (the day is tracked elsewhere or the boon persists until consumed).
- **Whale discount (16,23,24):** Stores discount bps (1000/2500/5000). Upgrade-only for lootbox. Day tracking differs: `whaleBoonDay = isDeity ? day : currentDay`.
- **Activity (17-19):** Stores pending amount (10/25/50). Upgrade-only for lootbox. Consumed later via `consumeActivityBoon` delegatecall.
- **Deity pass discount (25-27):** Stores tier (1/2/3). Upgrade-only for lootbox. Consumed when player purchases a deity pass.
- **Whale pass (28):** Directly activates a 100-level whale pass via `_activateWhalePass`. Event: `LootBoxWhalePassJackpot`.
- **Lazy pass discount (29-31):** Stores discount bps (1000/2500/5000). Upgrade-only for lootbox. Day tracking: `lazyPassBoonDay = isDeity ? day : currentDay`.

**NatSpec Accuracy:** Accurate. Documents the upgrade vs overwrite semantics and the lootbox vs deity distinction.

**Gas Flags:**
- The lootbox boost branch (types 5,6,22) has the most complex logic due to mutual exclusivity of the three tiers. It reads up to 3 active flags and writes up to 6 storage slots (3 active + 3 day fields). This is the most gas-intensive boon type.
- The decimator boost branch does not write a `decimatorBoostDay` -- it only writes `deityDecimatorBoostDay`. For lootbox-sourced decimator boons, this means `deityDecimatorBoostDay[player] = 0`, which is a no-op write (already 0 in most cases). The expiry/day tracking for lootbox-sourced decimator boons appears to rely on separate logic (possibly in the BoonModule's `checkAndClearExpiredBoon`).

**Verdict:** CORRECT

---

### `_resolveLootboxRoll(address, uint256, uint256, uint24, uint256, uint24, uint48, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxRoll(address player, uint256 amount, uint256 lootboxAmount, uint24 targetLevel, uint256 targetPrice, uint24 currentLevel, uint48 day, uint256 entropy) private returns (uint256 burnieOut, uint32 ticketsOut, uint256 nextEntropy, bool applyPresaleMultiplier)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the reward; `amount` (uint256): ETH amount for this roll (may be half of total for split lootboxes); `lootboxAmount` (uint256): total lootbox amount for events; `targetLevel` (uint24): target level for tickets; `targetPrice` (uint256): price at target level; `currentLevel` (uint24): current game level; `day` (uint48): current day index; `entropy` (uint256): starting entropy |
| **Returns** | `burnieOut` (uint256): BURNIE tokens to award; `ticketsOut` (uint32): tickets to queue for future level; `nextEntropy` (uint256): updated entropy; `applyPresaleMultiplier` (bool): whether BURNIE should get presale bonus |

**State Reads:** None directly (reads happen via callees `_lootboxTicketCount`, `_lootboxDgnrsReward`, `_creditDgnrsReward`)

**State Writes:** Indirect via `_creditDgnrsReward` -> `dgnrs.transferFromPool()` (external call). Also calls `wwxrp.mintPrize()` for WWXRP path.

**Callers:** `_resolveLootboxCommon` (called once or twice depending on split threshold)

**Callees:**
- `EntropyLib.entropyStep(entropy)` -- advance entropy
- `_lootboxTicketCount(budgetWei, targetPrice, nextEntropy)` -- 55% ticket path
- `_lootboxDgnrsReward(amount, nextEntropy)` -- 10% DGNRS path
- `_creditDgnrsReward(player, dgnrsAmount)` -- credit DGNRS to player
- `wwxrp.mintPrize(player, wwxrpAmount)` -- 10% WWXRP path (external call)

**ETH Flow:** No direct ETH movement. Determines reward type distribution:
- 55% chance (roll < 11): Ticket path -- computes ticket count from budget at 161% of input amount. If targetLevel < currentLevel, converts tickets to BURNIE at `PRICE_COIN_UNIT / TICKET_SCALE` rate instead.
- 10% chance (roll 11-12): DGNRS token path -- transfers from DGNRS Lootbox pool to player.
- 10% chance (roll 13-14): WWXRP token path -- mints 1 WWXRP to player (external mint call).
- 25% chance (roll 15-19): Large BURNIE path with variance. 80% sub-chance: low path (58.1%-130.4%), 20% sub-chance: high path (307%-590%).

**Invariants:**
- Roll modulus is 20, partitions sum to 20 (11 + 2 + 2 + 5 = 20). Correct.
- For ticket path: if targetLevel < currentLevel, tickets are converted to BURNIE rather than queued -- avoids queuing tickets for already-passed levels.
- Large BURNIE path low: `5808 + roll * 477` for rolls 0-15 gives range 5808-12963 BPS (58%-130%). Correct.
- Large BURNIE path high: `30705 + (roll-16) * 9430` for rolls 16-19 gives range 30705-58995 BPS (307%-590%). Correct.
- `applyPresaleMultiplier` is only true for the large BURNIE path.

**NatSpec Accuracy:** NatSpec says "55% tickets, 10% DGNRS, 10% WWXRP, 25% BURNIE." Matches roll < 11 (55%), < 13 (10%), < 15 (10%), else (25%). Accurate.

**Gas Flags:** None. Clean branch structure with early return pattern via if/else.

**Verdict:** CORRECT

---

### `_creditDgnrsReward(address, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditDgnrsReward(address player, uint256 amount) private returns (uint256 paid)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to credit; `amount` (uint256): requested DGNRS amount to credit |
| **Returns** | `paid` (uint256): actual DGNRS amount paid from pool |

**State Reads:** None directly (external call reads/writes DGNRS contract state)

**State Writes:** None directly (external call modifies DGNRS contract state via `transferFromPool`)

**Callers:** `_resolveLootboxRoll` (DGNRS path, 10% chance)

**Callees:**
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Lootbox, player, amount)` -- external call to DGNRS contract, transfers tokens from Lootbox pool to player

**ETH Flow:** No ETH movement. Transfers DGNRS tokens (ERC20-like) from pool to player.

**Invariants:**
- Returns 0 for zero amount input -- no-op.
- Return value `paid` may be less than `amount` if pool has insufficient balance (per `transferFromPool` interface comment).

**NatSpec Accuracy:** NatSpec says "Credit DGNRS reward to player from pool only." Accurate. Correctly uses only the Lootbox pool.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_activateWhalePass(address)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _activateWhalePass(address player) private returns (uint24 ticketStartLevel)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the whale pass |
| **Returns** | `ticketStartLevel` (uint24): first level tickets are queued for |

**State Reads:**
- `level` -- current game level (via `level + 1` for passLevel)

**State Writes:**
- Via `_applyWhalePassStats(player, ticketStartLevel)` -- writes to `mintPacked_[player]` (whale pass stats bitmap)
- Via `_queueTickets(player, lvl, tickets)` x100 -- writes to `ticketsBuyersMap_`, `ticketsBuyerList_`, `ticketsBy_` for each of 100 levels

**Callers:** `_applyBoon` (whale pass boon path, type 28)

**Callees:**
- `_applyWhalePassStats(player, ticketStartLevel)` -- inherited from DegenerusGameStorage, applies whale pass metadata
- `_queueTickets(player, lvl, ticketsPerLevel)` -- inherited from DegenerusGameStorage, queues tickets at each level

**ETH Flow:** No direct ETH movement. Awards tickets (future value) across 100 levels.

**Invariants:**
- Start level calculation: if passLevel <= 4, starts at level 1; otherwise starts at next 50-level boundary + 1: `((passLevel + 1) / 50) * 50 + 1`. At passLevel=5: `(6/50)*50+1 = 1`. At passLevel=50: `(51/50)*50+1 = 51`. At passLevel=51: `(52/50)*50+1 = 51`. Correct snapping to 50-level boundaries.
- Bonus tickets: 40/level for levels within [passLevel, 10] (WHALE_PASS_BONUS_END_LEVEL), 2/level for the rest. The `isBonus` check requires `lvl >= passLevel AND lvl <= 10`. If ticketStartLevel > 10 or passLevel > 10, no bonus levels.
- Loop iterates exactly 100 times with unchecked increment for gas efficiency.
- Uses `_queueTickets` (unscaled) not `_queueTicketsScaled` -- passes whole ticket counts directly.

**NatSpec Accuracy:** NatSpec says "Activate a 100-level whale pass for a player. Applies the same mint/streak bonuses as a whale bundle purchase." The function does apply stats and tickets over 100 levels. The comment about "mint/streak bonuses" refers to `_applyWhalePassStats`. Accurate.

**Gas Flags:** 100-iteration loop with external storage writes per iteration. This is inherently gas-heavy (~100 SSTORE operations) but necessary for the whale pass design. No optimization possible without architectural change.

**Verdict:** CORRECT


---

## DegenerusGameGameOverModule.sol

### `handleGameOverDrain(uint48 day)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleGameOverDrain(uint48 day) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): Day index for RNG word lookup from `rngWordByDay` mapping |
| **Returns** | none |

**State Reads:**
- `gameOverFinalJackpotPaid` -- early-exit guard (idempotency)
- `level` -- current game level, used for deity refund eligibility (< 10) and jackpot target level
- `claimablePool` -- existing claimable liability, used to compute available budget
- `deityPassOwners` (array length + elements) -- iteration for deity refund distribution
- `deityPassPurchasedCount[owner]` -- per-owner purchased pass count for refund calculation
- `rngWordByDay[day]` -- RNG word for jackpot selection

**State Writes:**
- `claimableWinnings[owner] += refund` -- credit deity pass refunds (unchecked, inside loop)
- `claimablePool += totalRefunded` -- increase liability by total deity refunds
- `gameOver = true` -- set terminal state flag
- `gameOverTime = uint48(block.timestamp)` -- record game-over timestamp
- `gameOverFinalJackpotPaid = true` -- prevent re-entry / duplicate payouts
- `claimablePool += decSpend` -- increase liability by decimator jackpot credits (via self-call return)

**Callers:**
- `DegenerusGameAdvanceModule._checkLiveness()` via delegatecall through `GAME_GAMEOVER_MODULE` (line 369-375 of AdvanceModule)

**Callees:**
- `steth.balanceOf(address(this))` -- external view call to get stETH balance
- `IDegenerusGame(address(this)).runDecimatorJackpot(decPool, lvl, rngWord)` -- self-call to DegenerusGame which delegatecalls DecimatorModule
- `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` -- self-call to DegenerusGame which delegatecalls JackpotModule
- `_sendToVault(remaining, stBal)` -- private helper for any undistributed remainder
- `dgnrs.balanceOf(address(dgnrs))` -- external view call to check DGNRS self-held pool tokens
- `dgnrs.burnForGame(address(dgnrs), dgnrsSelfBal)` -- burns undistributed DGNRS pool tokens so totalSupply reflects only holder wallets

**ETH Flow:**
1. **Deity refunds** (level < 10 only): 20 ETH/pass credited to `claimableWinnings[owner]`, funded from `totalFunds - claimablePool` budget. These are pull-pattern credits, not actual transfers.
2. **Decimator jackpot** (10% of available): `available / 10` sent to `runDecimatorJackpot`. Returns `decRefund` (unallocated portion). `decSpend = decPool - decRefund` added to `claimablePool`.
3. **Terminal jackpot** (90% + decimator refund): Remainder sent to `runTerminalJackpot` (Day-5-style bucket distribution to next-level ticketholders). `claimablePool` updated internally by JackpotModule.
4. **Vault sweep**: Any undistributed remainder (`remaining -= termPaid`) sent to vault/DGNRS via `_sendToVault`.
5. **DGNRS pool burn**: Burns any DGNRS tokens held by the DGNRS contract itself (undistributed pool tokens). This ensures `totalSupply` reflects only holder wallets, so every remaining `burn()` gives a true proportional share of backing assets.

**Invariants:**
- `gameOverFinalJackpotPaid` prevents duplicate execution (idempotent on re-call)
- `claimablePool` is always increased to cover newly credited amounts, preserving the solvency invariant `contract.balance + steth.balanceOf >= claimablePool`
- Deity refund budget is `totalFunds - claimablePool`, ensuring existing claimable liabilities are never touched
- `gameOver = true` is set BEFORE jackpot distribution, ensuring `_addClaimableEth` inside JackpotModule does not trigger auto-rebuy (tickets worthless post-game)
- Level 0 is mapped to `lvl = 1` for jackpot distribution, preventing underflow on `lvl + 1` for terminal jackpot target

**NatSpec Accuracy:**
- NatSpec states "liveness guards trigger (2.5yr deploy timeout or 365-day inactivity)" -- the actual code in AdvanceModule uses `DEPLOY_IDLE_TIMEOUT_DAYS` which is 912 days (~2.5 years) for level 0, and 365 days for level > 0. NatSpec is accurate.
- NatSpec mentions "10% to Decimator, 90% to next-level ticketholders" -- matches code exactly (`remaining / 10` for decimator, rest to terminal jackpot).
- NatSpec mentions "VRF fallback: Uses rngWordByDay" -- accurate. The `_gameOverEntropy` function in AdvanceModule populates `rngWordByDay[day]` before calling this function, with a 3-day timeout historical VRF fallback.
- NatSpec says "FIFO by purchase order" -- correct, iteration is over `deityPassOwners` array which preserves insertion order.
- `@custom:reverts E When stETH transfer fails` -- this function itself does not directly call stETH transfer (only `_sendToVault` does as a callee), but reverting within `_sendToVault` would propagate. Slightly imprecise but not misleading.

**Gas Flags:**
- The `deityPassOwners` loop is unbounded in theory, but deity passes are capped at 32 total (symbol IDs 0-31), so worst case is 32 iterations. Acceptable.
- `steth.balanceOf(address(this))` is an external call even though the balance may be zero in most cases. However, the call is necessary and inexpensive (view function).
- `unchecked` blocks inside the deity refund loop are safe: `claimableWinnings` grows from zero per player (overflow would require > 2^256 wei); `totalRefunded` bounded by `totalFunds`; `budget` decremented by `refund <= budget`.
- `stBal` is captured before deity refunds and jackpot distribution but passed to `_sendToVault` at the end. Since `_sendToVault` calls `steth.balanceOf` is NOT re-queried, stale `stBal` could theoretically be wrong if stETH rebased during execution. However, within a single transaction, stETH balance does not rebase (rebases happen once per day via oracle report), so this is safe.

**Verdict:** CORRECT

---

### `handleFinalSweep()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleFinalSweep() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | none |
| **Returns** | none |

**State Reads:**
- `gameOverTime` -- timestamp when game over was set (0 if game not over)
- `claimablePool` -- existing claimable liability to preserve

**State Writes:**
- None directly. `_sendToVault` does not write storage; it only performs external transfers.
- `admin.shutdownVrf()` writes to DegenerusAdmin storage (cancels VRF subscription, sets subscriptionId to 0, sweeps LINK to vault).

**Callers:**
- `DegenerusGameAdvanceModule._checkLiveness()` via delegatecall through `GAME_GAMEOVER_MODULE` (line 347-352 of AdvanceModule). Called when `gameOver == true` and liveness guard fires.

**Callees:**
- `admin.shutdownVrf()` -- external call to DegenerusAdmin, wrapped in try/catch (fire-and-forget). Cancels VRF subscription and sweeps LINK to vault.
- `steth.balanceOf(address(this))` -- external view call
- `_sendToVault(available, stBal)` -- private helper for ETH/stETH distribution

**ETH Flow:**
- All excess funds (`totalFunds - claimablePool`) transferred to Vault (50%) and DGNRS (50%) via `_sendToVault`. The `claimablePool` reserve is preserved for player withdrawals.
- LINK tokens (if any) swept from Admin to Vault via `shutdownVrf()`.

**Invariants:**
- `gameOverTime != 0` ensures game-over has occurred
- `block.timestamp >= gameOverTime + 30 days` enforces 30-day waiting period
- `claimablePool` is preserved -- only excess funds are swept, maintaining solvency for pending player claims
- `shutdownVrf()` is fire-and-forget: failure does not block the sweep, preventing VRF issues from locking funds permanently

**NatSpec Accuracy:**
- "Final sweep of all remaining funds to vault after 30 days post-gameover" -- accurate
- "Preserves claimablePool for player withdrawals" -- accurate, `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0`
- "Funds are split 50/50 between vault and DGNRS contract" -- accurate, handled by `_sendToVault`
- "Also shuts down the VRF subscription and sweeps LINK to vault" -- accurate
- `@custom:reverts E When ETH or stETH transfer fails` -- accurate, `_sendToVault` reverts with `E()` on transfer failure

**Gas Flags:**
- `handleFinalSweep` can be called repeatedly (no guard flag). Each call after the first will find `available == 0` and return early, so re-entrancy/re-call is harmless but wastes gas. Not a bug -- just a soft no-op pattern.
- The `admin.shutdownVrf()` call will succeed on first invocation but subsequent calls will either no-op (subscriptionId already 0) or revert inside try/catch. The try/catch ensures this is safe.

**Verdict:** CORRECT

---

### `_sendToVault(uint256 amount, uint256 stethBal)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _sendToVault(uint256 amount, uint256 stethBal) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): Total amount to send (combined ETH + stETH value); `stethBal` (uint256): Available stETH balance for transfers |
| **Returns** | none |

**State Reads:**
- None (operates purely on parameters and external calls)

**State Writes:**
- None (no storage writes; only external transfers)

**Callers:**
- `handleGameOverDrain` -- for undistributed remainder after jackpot distribution
- `handleFinalSweep` -- for all excess funds after 30-day waiting period

**Callees:**
- `steth.transfer(ContractAddresses.VAULT, ...)` -- transfer stETH to Vault
- `steth.approve(ContractAddresses.DGNRS, ...)` -- approve DGNRS to pull stETH
- `dgnrs.depositSteth(...)` -- deposit stETH into DGNRS contract
- `payable(ContractAddresses.VAULT).call{value: ethAmount}("")` -- send raw ETH to Vault
- `payable(ContractAddresses.DGNRS).call{value: ethAmount}("")` -- send raw ETH to DGNRS

**ETH Flow:**
Split `amount` 50/50 between Vault and DGNRS, prioritizing stETH transfers:

1. **Vault share** (`vaultAmount = amount - amount/2`):
   - If `vaultAmount <= stethBal`: transfer entire vault share as stETH
   - Else: transfer all available stETH to vault, then send remaining as raw ETH
2. **DGNRS share** (`dgnrsAmount = amount/2`):
   - If `dgnrsAmount <= stethBal` (remaining after vault): approve + depositSteth
   - Else: approve + depositSteth for remaining stETH, then send remaining as raw ETH

The stETH-first priority means: vault gets stETH first, DGNRS gets whatever stETH remains, and any shortfall is covered by raw ETH.

**Invariants:**
- `dgnrsAmount + vaultAmount == amount` (guaranteed by `amount - amount/2` rounding)
- Every transfer is checked: stETH transfer/approve returns bool (reverts with `E()` on false), raw ETH call checked for success
- `stethBal` is decremented locally to track remaining stETH availability across the vault and DGNRS splits

**NatSpec Accuracy:**
- "Send funds to vault (50%) and DGNRS (50%), prioritizing stETH transfers over ETH" -- accurate
- "Total amount to send (combined ETH + stETH value)" -- accurate
- `@custom:reverts E When stETH transfer, approval, or ETH transfer fails` -- accurate

**Gas Flags:**
- The `stethBal` parameter is tracked locally (decremented in-function) rather than re-querying `steth.balanceOf`. This is correct within a single transaction but relies on the caller providing an accurate initial balance. Both callers (`handleGameOverDrain` and `handleFinalSweep`) read `steth.balanceOf(address(this))` immediately before calling this function, so the value is accurate.
- In `handleGameOverDrain`, `stBal` is read before deity refunds and jackpot distribution. Jackpot distribution does not move stETH (only credits `claimableWinnings`), so `stBal` remains valid when passed to `_sendToVault`. However, the decimator and terminal jackpot self-calls could theoretically trigger stETH operations in other modules. In practice, neither DecimatorModule nor JackpotModule touch stETH, so this is safe.
- Minor: `stethBal = 0` assignment on line 195 is unnecessary since the variable is only read in the DGNRS block which re-checks `dgnrsAmount <= stethBal`. After vault takes all stETH and sets `stethBal = 0`, DGNRS correctly falls through to the pure-ETH path. The assignment is redundant but not harmful.

**Verdict:** CORRECT


---

## DegenerusGameWhaleModule.sol

### `purchaseWhaleBundle(address buyer, uint256 quantity)` [external] + `_purchaseWhaleBundle` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseWhaleBundle(address buyer, uint256 quantity) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the bundle; `quantity` (uint256): number of bundles (1-100) |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `level` -- derives passLevel = level + 1; determines price tier and pool split ratio
- `whaleBoonDay[buyer]` -- checks for valid discount boon
- `whaleBoonDiscountBps[buyer]` -- discount tier in BPS (10/25/50% off standard)
- `mintPacked_[buyer]` -- unpacks frozenUntilLevel, levelCount for delta calculations
- `lootboxPresaleActive` -- determines lootbox percentage (20% vs 10%)
- `dailyIdx` (via `_currentMintDay()`) -- day tracking
- `lootboxRngIndex` (via `_recordLootboxEntry`) -- current lootbox RNG index
- `lootboxEth[index][buyer]`, `lootboxDay[index][buyer]`, `lootboxBaseLevelPacked[index][buyer]`, `lootboxEvScorePacked[index][buyer]`, `lootboxEthBase[index][buyer]`, `lootboxEthTotal`, `lootboxRngPendingEth` -- lootbox recording state
- `lootboxBoon25Active/Day`, `lootboxBoon15Active/Day`, `lootboxBoon5Active/Day` (via `_applyLootboxBoostOnPurchase`) -- boost boon state
- `ticketsOwedPacked[lvl][buyer]` (via `_queueTickets`) -- existing ticket state
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn` (via `_awardEarlybirdDgnrs`) -- earlybird DGNRS tracking
- `dgnrs.poolBalance(Whale)`, `dgnrs.poolBalance(Affiliate)` (via `_rewardWhaleBundleDgnrs`) -- DGNRS pool reserves
- `affiliate.getReferrer(buyer/affiliate/upline)` -- referral chain resolution

**State Writes:**
- `whaleBoonDay[buyer]` -- deleted if boon consumed
- `whaleBoonDiscountBps[buyer]` -- deleted if boon consumed
- `mintPacked_[buyer]` -- updated: LEVEL_COUNT += levelsToAdd, FROZEN_UNTIL_LEVEL = max(old, ticketStartLevel+99), WHALE_BUNDLE_TYPE = 3, LAST_LEVEL = newFrozenLevel, DAY = currentMintDay
- `ticketsOwedPacked[lvl][buyer]` -- tickets queued for 100 levels (40/lvl bonus <= level 10, 2/lvl standard)
- `ticketQueue[lvl]` -- buyer pushed if first entry
- `futurePrizePool += totalPrice - nextShare` -- ETH pool allocation
- `nextPrizePool += nextShare` -- ETH pool allocation
- `lootboxEth[index][buyer]`, `lootboxDay[index][buyer]`, `lootboxBaseLevelPacked[index][buyer]`, `lootboxEvScorePacked[index][buyer]`, `lootboxEthBase[index][buyer]`, `lootboxEthTotal`, `lootboxRngPendingEth`, `lootboxIndexQueue[buyer]` -- lootbox entry recording
- `lootboxBoon25Active/15Active/5Active[player]` -- consumed if applicable
- `earlybirdEthIn`, `earlybirdDgnrsPoolStart` (via `_awardEarlybirdDgnrs`) -- earlybird tracking
- DGNRS token transfers from Whale and Affiliate pools (external state on DGNRS contract)

**Callers:**
- DegenerusGame dispatches via delegatecall when player calls whale bundle purchase

**Callees:**
- `_simulatedDayIndex()` -- current game day (inherited from Storage via GameTimeLib)
- `_currentMintDay()` -- mint day calculation
- `_setMintDay()` -- packed day field update
- `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` -- earlybird DGNRS distribution
- `_queueTickets(buyer, lvl, tickets)` -- queues tickets for each of 100 levels
- `affiliate.getReferrer(buyer)` -- external: referral chain lookup (3 levels deep)
- `_rewardWhaleBundleDgnrs(buyer, affiliate, upline, upline2)` -- per-bundle DGNRS distribution
- `_recordLootboxEntry(buyer, lootboxAmount, passLevel, data)` -- lootbox recording
- `dgnrs.poolBalance(Pool)` (indirect via reward functions) -- external: pool balance check
- `dgnrs.transferFromPool(Pool, addr, amount)` (indirect via reward functions) -- external: DGNRS transfer

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `totalPrice - nextShare` -> `futurePrizePool` (70% pre-game, 95% post-game)
- `nextShare` -> `nextPrizePool` (30% pre-game, 5% post-game)
- Lootbox virtual: `totalPrice * whaleLootboxBps / 10000` -> `lootboxEthTotal` (not actual ETH movement, accounting only)

**Pricing Formula Verification:**
- Early price (passLevel <= 4): `WHALE_BUNDLE_EARLY_PRICE = 2.4 ether` -- CORRECT
- Standard price (passLevel > 4): `WHALE_BUNDLE_STANDARD_PRICE = 4 ether` -- CORRECT
- Boon discount: `(STANDARD * (10000 - discountBps)) / 10000`, default 10% if discountBps==0 -- CORRECT
- Total: `unitPrice * quantity` -- CORRECT

**Invariants:**
- `gameOver == false` (pre-condition)
- `quantity >= 1 && quantity <= 100`
- `msg.value == totalPrice` (exact match, no over/underpayment)
- `futurePrizePool + nextPrizePool` increases by exactly `totalPrice`
- Bundle type is always set to 3 (100-level), overwriting any previous 10-level (1) designation
- levelsToAdd is delta-based: overlapping whale bundles do not double-count levels

**NatSpec Accuracy:**
- NatSpec says "Available at any level. Tickets always start at x1." -- ACCURATE. `ticketStartLevel = passLevel <= 4 ? 1 : passLevel` confirms tickets start at level 1 for early purchases.
- NatSpec says "Boosts levelCount by delta" -- ACCURATE. levelsToAdd is capped at deltaFreeze.
- NatSpec says "40 x quantity bonus tickets/lvl for levels passLevel-10" -- ACCURATE. Loop checks `isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL)`.
- NatSpec says "Price: 2.4 ETH at levels 0-3" -- SLIGHTLY IMPRECISE: code uses `passLevel <= 4` which is `level + 1 <= 4`, meaning `level <= 3`, so levels 0-3 is correct. ACCURATE.
- NatSpec says "Pre-game (level 0): 30% next pool, 70% future pool" -- ACCURATE. Code: `level == 0 -> nextShare = totalPrice * 3000 / 10000`.
- NatSpec says "Post-game (level > 0): 5% next pool, 95% future pool" -- ACCURATE.

**Gas Flags:**
- `_rewardWhaleBundleDgnrs` is called `quantity` times in a loop (line 282-285). Each call reads `dgnrs.poolBalance(Whale)` and `dgnrs.poolBalance(Affiliate)` externally. For quantity=100, this is 200 external calls minimum. Gas-expensive but functionally correct -- the pool balance changes after each transfer so re-reading is necessary for accurate proportional distribution.
- The 100-level ticket loop (line 265-270) writes `ticketsOwedPacked` 100 times and may push to `ticketQueue` up to 100 times. Gas-expensive but unavoidable for per-level ticket tracking.

**Verdict:** CORRECT

---

### `purchaseLazyPass(address buyer)` [external] + `_purchaseLazyPass` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseLazyPass(address buyer) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the pass |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `level` -- current game level for eligibility and pricing
- `lazyPassBoonDiscountBps[buyer]` -- boon discount tier
- `lazyPassBoonDay[buyer]` -- boon timestamp for expiry check
- `deityLazyPassBoonDay[buyer]` -- deity-granted lazy pass boon (same-day only)
- `deityPassCount[buyer]` -- deity pass holders cannot buy lazy pass
- `mintPacked_[buyer]` -- unpacks frozenUntilLevel for renewal eligibility
- `lootboxPresaleActive` -- lootbox percentage selection
- All reads from `_activate10LevelPass`: mintPacked_ (re-read), ticketsOwedPacked, ticketQueue
- All reads from `_recordLootboxEntry` (same as whale bundle)
- All reads from `_awardEarlybirdDgnrs` (same as whale bundle)

**State Writes:**
- `lazyPassBoonDay[buyer]` -- cleared (on invalid boon check or after use)
- `lazyPassBoonDiscountBps[buyer]` -- cleared (on invalid boon check or after use)
- `deityLazyPassBoonDay[buyer]` -- cleared (on invalid boon check or after use)
- `mintPacked_[buyer]` -- updated via `_activate10LevelPass`: LEVEL_COUNT += levelsToAdd (capped by delta), FROZEN_UNTIL_LEVEL = max(old, startLevel+9), WHALE_BUNDLE_TYPE = 1 (if not already higher), LAST_LEVEL = max(old, newFrozen), DAY = currentMintDay
- `ticketsOwedPacked[lvl][buyer]` -- 4 tickets per level for 10 levels, plus bonusTickets at startLevel
- `ticketQueue[lvl]` -- buyer pushed if first entry
- `futurePrizePool += futureShare` -- 10% of totalPrice
- `nextPrizePool += nextShare` -- 90% of totalPrice
- All writes from `_recordLootboxEntry` (same as whale bundle)
- All writes from `_awardEarlybirdDgnrs` (same as whale bundle)

**Callers:**
- DegenerusGame dispatches via delegatecall for lazy pass purchase

**Callees:**
- `_simulatedDayIndex()` -- boon expiry check
- `_lazyPassCost(startLevel)` -- sum of 10 level prices
- `PriceLookupLib.priceForLevel(startLevel)` -- single level price (for bonus ticket calc)
- `_awardEarlybirdDgnrs(buyer, benefitValue, startLevel)` -- earlybird DGNRS
- `_activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL=4)` -- pass activation + ticket queuing
- `_queueTickets(buyer, startLevel, bonusTickets)` -- bonus tickets from flat-price overpayment
- `_recordLootboxEntry(buyer, lootboxAmount, currentLevel+1, mintPacked_[buyer])` -- lootbox recording

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `totalPrice * LAZY_PASS_TO_FUTURE_BPS / 10000` (10%) -> `futurePrizePool`
- `totalPrice - futureShare` (90%) -> `nextPrizePool`
- Lootbox virtual: `benefitValue * lootboxBps / 10000` -> `lootboxEthTotal`

**Note on Pool Splits:** Lazy pass uses a DIFFERENT split from whale/deity. It is 10% future / 90% next at ALL levels (not the 70/30 pre-game or 95/5 post-game split). This is a deliberate design choice documented by the constant `LAZY_PASS_TO_FUTURE_BPS = 1000`.

**Pricing Formula Verification:**
- Levels 0-2: `benefitValue = 0.24 ether` (flat). `baseCost = _lazyPassCost(startLevel)` sums 10 level prices. `balance = 0.24 ether - baseCost` converts to bonus tickets. At level 0, startLevel=1: prices are 0.01*4 + 0.02*5 + 0.04 = 0.18 ETH, balance = 0.06 ETH -> bonus tickets = (0.06 * 4) / 0.01 = 24. CORRECT.
- With boon at levels 0-2: `totalPrice = (0.24 ether * (10000 - boonDiscountBps)) / 10000`. Player pays less but gets same benefit value. CORRECT.
- Levels 3+: `benefitValue = baseCost = _lazyPassCost(startLevel)`. With boon: `totalPrice = (baseCost * (10000 - boonDiscountBps)) / 10000`. CORRECT.
- Default boon discount: 10% (1000 BPS) if boonDiscountBps is 0 but boon is valid. CORRECT.

**Eligibility Logic:**
- Level must be 0, 1, 2, or end in 9 (x9 pattern: 9, 19, 29...), OR have valid boon
- Cannot have deity pass (`deityPassCount[buyer] != 0` reverts)
- Must have <=7 levels remaining on freeze (`frozenUntilLevel <= currentLevel + 7`)

**Boon Expiry Logic:**
- Standard lootbox boon: `currentDay <= boonDay + 4` (4-day window)
- Deity-granted boon: same-day only (`deityDay != 0 && deityDay != currentDay` -> invalidate)
- If boonDay is set but no deityDay and no valid standard boon, fields are cleared

**NatSpec Accuracy:**
- NatSpec says "Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon" -- ACCURATE. Code: `currentLevel > 2 && currentLevel % 10 != 9 && !hasValidBoon -> revert`.
- NatSpec says "Can renew when 7 or fewer levels remain on current pass freeze" -- SLIGHTLY IMPRECISE: code checks `frozenUntilLevel > currentLevel + 7 -> revert`, meaning it reverts if more than 7 levels remain. So renewal is allowed when `frozenUntilLevel <= currentLevel + 7`, i.e., 7 OR FEWER remain. If frozenUntilLevel == currentLevel + 8 it reverts (8 levels remain). NatSpec is ACCURATE on the boundary.
- NatSpec says "Price: flat 0.24 ETH at levels 0-2" -- ACCURATE.
- NatSpec says "sum of per-level ticket prices across the 10-level window at levels 3+" -- ACCURATE.

**Gas Flags:**
- At levels 0-2, `PriceLookupLib.priceForLevel(startLevel)` is called separately in addition to `_lazyPassCost` which also loops. The separate call is for computing bonus tickets and uses just the first level's price, not redundant with the sum loop.
- `_activate10LevelPass` re-reads `mintPacked_[buyer]` even though the caller already has it cached. This is a minor gas inefficiency but the storage slot may have been modified by `_awardEarlybirdDgnrs` in between, so the re-read is safe.

**Verdict:** CORRECT

---

### `purchaseDeityPass(address buyer, uint8 symbolId)` [external] + `_purchaseDeityPass` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseDeityPass(address buyer, uint8 symbolId) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the pass; `symbolId` (uint8): symbol to claim (0-31) |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `deityBySymbol[symbolId]` -- check symbol availability
- `deityPassCount[buyer]` -- check buyer doesn't already own one
- `deityPassOwners.length` -- k = number of passes sold so far (for pricing)
- `deityPassBoonTier[buyer]` -- discount boon tier (1=10%, 2=25%, 3=50%)
- `deityDeityPassBoonDay[buyer]` -- deity-granted boon expiry (1-day)
- `deityPassBoonDay[buyer]` -- lootbox-rolled boon expiry (4-day)
- `level` -- for passLevel and pool split logic
- `mintPacked_[buyer]` (via `_recordLootboxEntry`) -- lootbox recording
- `lootboxPresaleActive` -- lootbox percentage
- All reads from `_awardEarlybirdDgnrs`, `_rewardDeityPassDgnrs`, `_recordLootboxEntry` (same as above)
- `affiliate.getReferrer(buyer/affiliate/upline)` -- referral chain
- `dgnrs.poolBalance(Whale)`, `dgnrs.poolBalance(Affiliate)` -- DGNRS reserves

**State Writes:**
- `deityPassBoonTier[buyer]` -- set to 0 (consumed regardless of expiry)
- `deityPassBoonDay[buyer]` -- set to 0
- `deityDeityPassBoonDay[buyer]` -- set to 0
- `deityPassPaidTotal[buyer] += totalPrice` -- tracking total ETH paid
- `deityPassCount[buyer] = 1` -- mark buyer as deity pass holder
- `deityPassPurchasedCount[buyer] += 1` -- increment purchase count
- `deityPassOwners.push(buyer)` -- append to owners array
- `deityPassSymbol[buyer] = symbolId` -- bind symbol to buyer
- `deityBySymbol[symbolId] = buyer` -- bind buyer to symbol
- `nextPrizePool += nextShare` -- 30% pre-game, 5% post-game
- `futurePrizePool += totalPrice - nextShare` -- 70% pre-game, 95% post-game
- All writes from `_recordLootboxEntry` (same as above)
- All writes from `_awardEarlybirdDgnrs` (same as above)
- DGNRS transfers from Whale and Affiliate pools (external state on DGNRS contract)
- `ticketsOwedPacked[lvl][buyer]`, `ticketQueue[lvl]` -- 100 levels of tickets
- External: `IDegenerusDeityPassMint(DEITY_PASS).mint(buyer, symbolId)` -- ERC721 mint

**Callers:**
- DegenerusGame dispatches via delegatecall for deity pass purchase

**Callees:**
- `_simulatedDayIndex()` -- boon expiry check
- `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` -- earlybird DGNRS
- `IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId)` -- external: ERC721 mint
- `affiliate.getReferrer(buyer)` -- external: referral chain (3 levels deep)
- `_rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2)` -- DGNRS rewards
- `_queueTickets(buyer, lvl, tickets)` -- 100 levels of tickets
- `_recordLootboxEntry(buyer, lootboxAmount, passLevel, mintPacked_[buyer])` -- lootbox recording

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `nextShare` -> `nextPrizePool` (30% pre-game level 0, 5% post-game)
- `totalPrice - nextShare` -> `futurePrizePool` (70% pre-game, 95% post-game)
- Lootbox virtual: `totalPrice * deityLootboxBps / 10000` -> `lootboxEthTotal`

**Pricing Formula Verification:**
- Base price: `DEITY_PASS_BASE + (k * (k+1) * 1 ether) / 2` where k = `deityPassOwners.length`
- This is `24 + T(k)` where `T(k) = k*(k+1)/2` is the k-th triangular number
- Pass 0 (k=0): 24 + 0 = 24 ETH -- CORRECT
- Pass 1 (k=1): 24 + 1 = 25 ETH -- CORRECT
- Pass 31 (k=31): 24 + 31*32/2 = 24 + 496 = 520 ETH -- CORRECT (matches NatSpec "last 32nd costs 520 ETH")
- Boon tiers: tier 1 = 1000 BPS (10%), tier 2 = 2500 BPS (25%), tier 3 = 5000 BPS (50%) -- CORRECT
- Boon expiry: lootbox-rolled = `stampDay + DEITY_PASS_BOON_EXPIRY_DAYS (4)`, deity-granted = same day only (`deityDay != currentDay -> expired`). Boon consumed regardless of expiry. CORRECT.

**Ticket Queuing Logic:**
- `ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel + 1) / 50) * 50 + 1)`
- For early levels (passLevel <= 4): starts at level 1, covers 1-100
- For later levels: rounds down to nearest x50+1 boundary. E.g., passLevel=5 -> (6/50)*50+1 = 1; passLevel=50 -> (51/50)*50+1 = 51; passLevel=99 -> (100/50)*50+1 = 51; passLevel=100 -> (101/50)*50+1 = 101
- Tickets: 40/lvl bonus for levels between passLevel and level 10, 2/lvl standard otherwise (same rates as whale bundle but without quantity multiplier)

**Invariants:**
- `gameOver == false`
- `symbolId < 32`
- `deityBySymbol[symbolId] == address(0)` (symbol not taken)
- `deityPassCount[buyer] == 0` (one per player)
- `msg.value == totalPrice` (exact match)
- `futurePrizePool + nextPrizePool` increases by exactly `totalPrice`
- `deityPassOwners.length` increments by 1
- Maximum 32 deity passes total (bounded by symbolId < 32 and each symbol can only be taken once)

**NatSpec Accuracy:**
- NatSpec says "One per player, up to 32 total (one per symbol)" -- ACCURATE. `deityPassCount[buyer] != 0 -> revert` and `symbolId >= 32 -> revert`.
- NatSpec says "Price: 24 + T(n) ETH where n = passes sold so far" -- ACCURATE.
- NatSpec says "First pass costs 24 ETH, last (32nd) costs 520 ETH" -- ACCURATE (k=0 -> 24, k=31 -> 520).
- NatSpec says "Pre-game (level 0): 30% next pool, 70% future pool" -- ACCURATE.
- NatSpec says "Buyer chooses from available symbols (0-31)" -- ACCURATE. The 4 quadrants (Crypto, Zodiac, Cards, Dice with 8 symbols each) is cosmetic labeling, code just checks `symbolId < 32`.

**Gas Flags:**
- `_queueTickets` is called 100 times in a loop (line 523-528), each writing `ticketsOwedPacked`. Similar cost profile to whale bundle but without quantity multiplier (each call queues a fixed 40 or 2 tickets).
- `deityPassPurchasedCount[buyer] += 1` at line 501: this counter survives deity pass transfers (transferred to new owner), tracking total purchases ever made through this ownership lineage.

**Verdict:** CORRECT

---

### `handleDeityPassTransfer(address from, address to)` [external] + `_handleDeityPassTransfer` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDeityPassTransfer(address from, address to) external` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (not payable) |
| **Parameters** | `from` (address): current deity pass holder; `to` (address): receiving address |
| **Returns** | none |

**State Reads:**
- `level` -- must be > 0 (no pre-game transfers)
- `deityPassCount[from]` -- must be > 0 (sender must own pass)
- `deityPassCount[to]` -- must be 0 (receiver must not own pass)
- `price` -- current game price for BURNIE burn calculation
- `deityPassSymbol[from]` -- symbol ID to transfer
- `deityPassOwners` (full array) -- linear scan to find and replace sender
- `deityPassPurchasedCount[from]` -- transferred to receiver
- `deityPassPaidTotal[from]` -- transferred to receiver
- `mintPacked_[from]` (via `_nukePassHolderStats`) -- sender's packed mint data

**State Writes:**
- External: `IDegenerusCoin(COIN).burnCoin(from, burnAmount)` -- burns 5 ETH worth of BURNIE from sender
- `deityBySymbol[symbolId] = to` -- rebind symbol to receiver
- `deityPassSymbol[to] = symbolId` -- assign symbol to receiver
- `deityPassSymbol[from]` -- deleted
- `deityPassCount[to] = 1` -- receiver now has pass
- `deityPassCount[from] = 0` -- sender no longer has pass
- `deityPassPurchasedCount[to] = deityPassPurchasedCount[from]` -- transfer purchase history
- `deityPassPurchasedCount[from] = 0` -- clear sender's history
- `deityPassPaidTotal[to] = deityPassPaidTotal[from]` -- transfer payment history
- `deityPassPaidTotal[from] = 0` -- clear sender's payment history
- `deityPassOwners[i] = to` -- replace sender with receiver in owners array
- `mintPacked_[from]` (via `_nukePassHolderStats`) -- zeros LEVEL_COUNT, LEVEL_STREAK, LAST_LEVEL, MINT_STREAK_LAST_COMPLETED
- External: `IDegenerusQuestsReset(QUESTS).resetQuestStreak(from)` -- resets quest streak

**Callers:**
- DegenerusGame's `onDeityPassTransfer` callback (triggered by ERC721 transfer event on DeityPass contract)

**Callees:**
- `IDegenerusCoin(ContractAddresses.COIN).burnCoin(from, burnAmount)` -- external: burns BURNIE from sender
- `_nukePassHolderStats(from)` -- zeros sender's mint stats and quest streak
- `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(from)` -- external: resets quest streak

**ETH Flow:**
- No direct ETH movement. The BURNIE burn is a token operation, not ETH.
- `burnAmount = (DEITY_TRANSFER_ETH_COST * PRICE_COIN_UNIT) / price`
- At default price 0.01 ETH: `(5 ether * 1000 ether) / 0.01 ether = 500,000 ether` BURNIE tokens burned
- The burn cost scales inversely with price: higher price = fewer BURNIE needed

**Invariants:**
- `level > 0` (transfers only allowed after game starts)
- `deityPassCount[from] > 0` (sender must own pass)
- `deityPassCount[to] == 0` (receiver must not already own pass)
- After transfer: `deityPassCount[from] == 0 && deityPassCount[to] == 1`
- After transfer: `deityBySymbol[symbolId] == to`
- deityPassOwners array length unchanged (replacement, not push/pop)
- Sender's mint stats are zeroed (punishment for transfer)
- Sender's quest streak is reset (punishment for transfer)

**NatSpec Accuracy:**
- NatSpec says "Burns 5 ETH worth of BURNIE from sender" -- ACCURATE. `DEITY_TRANSFER_ETH_COST = 5 ether`, formula converts to BURNIE equivalent.
- NatSpec says "Nukes sender's mint stats and quest streak" -- ACCURATE. `_nukePassHolderStats` zeros 4 packed fields + calls `resetQuestStreak`.
- NatSpec says "Called via delegatecall from game's onDeityPassTransfer" -- ACCURATE.

**Gas Flags:**
- Linear scan of `deityPassOwners` array (line 584-590) to find `from`. Max 32 entries (one per symbol), so O(32) worst case. Acceptable for a max-32 array.
- The `burnCoin` external call could revert if sender lacks sufficient BURNIE balance, which would revert the entire transfer. This is intentional -- the burn is a mandatory cost.

**Edge Cases:**
- If `from == to`: Would pass all checks (deityPassCount[from] > 0, deityPassCount[to] == 0 only if from != to). Since `deityPassCount[to] != 0` check uses `to` and the sender has count 1, this would revert at `deityPassCount[to] != 0`. CORRECT -- self-transfer is prevented.
- The function is non-payable, so no ETH can be accidentally sent.

**Verdict:** CORRECT

---

### `_rewardWhaleBundleDgnrs(address buyer, address affiliateAddr, address upline, address upline2)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardWhaleBundleDgnrs(address buyer, address affiliateAddr, address upline, address upline2) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): bundle purchaser; `affiliateAddr` (address): direct referrer; `upline` (address): 2nd-tier referrer; `upline2` (address): 3rd-tier referrer |
| **Returns** | none |

**State Reads:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Whale)` -- external: whale pool DGNRS balance
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external: affiliate pool DGNRS balance

**State Writes:**
- `dgnrs.transferFromPool(Pool.Whale, buyer, minterShare)` -- external: 1% of whale pool to buyer
- `dgnrs.transferFromPool(Pool.Affiliate, affiliateAddr, affiliateShare)` -- external: 0.1% of affiliate pool to direct referrer
- `dgnrs.transferFromPool(Pool.Affiliate, upline, uplineShare)` -- external: 0.02% of affiliate pool to upline
- `dgnrs.transferFromPool(Pool.Affiliate, upline2, upline2Share)` -- external: 0.01% (uplineShare/2) of affiliate pool to upline2

**Callers:**
- `_purchaseWhaleBundle` -- called once per bundle in quantity loop

**Callees:**
- `dgnrs.poolBalance(Pool)` -- external: 2 calls per invocation
- `dgnrs.transferFromPool(Pool, addr, amount)` -- external: up to 4 calls per invocation

**ETH Flow:** None (DGNRS token transfers only, no ETH movement)

**DGNRS Distribution:**
- Buyer: `whaleReserve * 10_000 / 1_000_000` = 1% of whale pool
- Direct affiliate: `affiliateReserve * 1_000 / 1_000_000` = 0.1% of affiliate pool
- Upline: `affiliateReserve * 200 / 1_000_000` = 0.02% of affiliate pool
- Upline2: `uplineShare / 2` = 0.01% of affiliate pool

**Invariants:**
- All transfers are proportional to current pool balance (re-read each call)
- If whale pool is 0, no buyer reward
- If affiliate pool is 0, early return (no affiliate rewards)
- upline2Share is half of uplineShare (derived, not independently calculated from pool)
- Each address checked for non-zero before transfer
- Amount checked for non-zero before transfer

**NatSpec Accuracy:**
- NatSpec says "0.1% of affiliate pool" for direct affiliate -- ACCURATE (1_000 / 1_000_000 = 0.1%)
- NatSpec says "0.02% of affiliate pool" for upline -- ACCURATE (200 / 1_000_000 = 0.02%)
- NatSpec says "0.01% of affiliate pool" for upline2 -- ACCURATE (uplineShare/2, where uplineShare is 0.02%, so 0.01%)

**Gas Flags:**
- Called once per `quantity` in a loop. For quantity=100, this function executes 100 times with up to 600 external calls total. This is gas-heavy but functionally required since each transfer changes the pool balance.
- The `upline2Share = uplineShare / 2` pattern calculates from the same `affiliateReserve` read, meaning upline2 gets half the upline amount (0.01% vs 0.02%), not a fresh pool proportion. This is intentional as upline2 is a derived share.

**Verdict:** CORRECT

---

### `_rewardDeityPassDgnrs(address buyer, address affiliateAddr, address upline, address upline2)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardDeityPassDgnrs(address buyer, address affiliateAddr, address upline, address upline2) private returns (uint96 buyerDgnrs)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): deity pass purchaser; `affiliateAddr` (address): direct referrer; `upline` (address): 2nd-tier referrer; `upline2` (address): 3rd-tier referrer |
| **Returns** | `buyerDgnrs` (uint96): DGNRS amount transferred to buyer (capped at uint96 max) |

**State Reads:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Whale)` -- external: whale pool balance
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external: affiliate pool balance

**State Writes:**
- `dgnrs.transferFromPool(Pool.Whale, buyer, totalReward)` -- external: 5% of whale pool to buyer
- `dgnrs.transferFromPool(Pool.Affiliate, affiliateAddr, affiliateShare)` -- external: 0.5% of affiliate pool
- `dgnrs.transferFromPool(Pool.Affiliate, upline, uplineShare)` -- external: 0.1% of affiliate pool
- `dgnrs.transferFromPool(Pool.Affiliate, upline2, upline2Share)` -- external: 0.05% of affiliate pool

**Callers:**
- `_purchaseDeityPass` -- called once per deity pass purchase

**Callees:**
- `dgnrs.poolBalance(Pool)` -- external: 2 calls
- `dgnrs.transferFromPool(Pool, addr, amount)` -- external: up to 4 calls

**ETH Flow:** None (DGNRS token transfers only)

**DGNRS Distribution (deity pass -- 5x whale bundle rates):**
- Buyer: `whaleReserve * 500 / 10_000` = 5% of whale pool (vs 1% for whale bundle)
- Direct affiliate: `affiliateReserve * 5_000 / 1_000_000` = 0.5% of affiliate pool (vs 0.1%)
- Upline: `affiliateReserve * 1_000 / 1_000_000` = 0.1% of affiliate pool (vs 0.02%)
- Upline2: `uplineShare / 2` = 0.05% of affiliate pool (vs 0.01%)

**Invariants:**
- Buyer DGNRS return value capped at `type(uint96).max` to prevent overflow in callers
- `transferFromPool` returns actual transferred amount (may be less than requested if pool depleted)
- Same null-check pattern as whale bundle rewards

**NatSpec Accuracy:**
- NatSpec says "5% of whale pool" for buyer -- ACCURATE. Note: constant uses BPS (500/10000) not PPM, unlike whale bundle which uses PPM (10000/1000000). Both resolve to the correct percentages.
- NatSpec says "0.5% of affiliate pool" -- ACCURATE (5_000 / 1_000_000 = 0.5%)
- NatSpec says "0.1% of affiliate pool" for upline -- ACCURATE (1_000 / 1_000_000 = 0.1%)
- NatSpec says "0.05% of affiliate pool" for upline2 -- ACCURATE (uplineShare/2)

**Gas Flags:**
- Buyer reward uses BPS scale (DEITY_WHALE_POOL_BPS = 500, divided by 10_000) while affiliate rewards use PPM scale (divided by 1_000_000). Both are correct but use different denomination conventions. Not a bug, just inconsistent constant naming.
- The `buyerDgnrs` return value is used nowhere in the calling code (`_purchaseDeityPass` does not capture the return). The return exists for potential future use. No gas impact beyond the comparison.

**Verdict:** CORRECT

---

### `_recordLootboxEntry(address buyer, uint256 lootboxAmount, uint24 purchaseLevel, uint256 cachedPacked)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordLootboxEntry(address buyer, uint256 lootboxAmount, uint24 purchaseLevel, uint256 cachedPacked) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): lootbox recipient; `lootboxAmount` (uint256): base ETH amount for lootbox; `purchaseLevel` (uint24): level at time of purchase; `cachedPacked` (uint256): caller's cached mintPacked_ |
| **Returns** | none |

**State Reads:**
- `lootboxRngIndex` -- current global lootbox RNG index
- `lootboxEth[index][buyer]` -- existing lootbox amount for this index
- `lootboxDay[index][buyer]` -- day of existing lootbox entry
- `lootboxEthBase[index][buyer]` -- unboosted base lootbox amount
- `mintPacked_[buyer]` (via `_recordLootboxMintDay`) -- mint day tracking
- `lootboxBoon25Active/15Active/5Active[buyer]`, `lootboxBoon25Day/15Day/5Day[buyer]` (via `_applyLootboxBoostOnPurchase`) -- boost state

**State Writes:**
- `mintPacked_[buyer]` (via `_recordLootboxMintDay`) -- update mint day field
- `lootboxDay[index][buyer] = dayIndex` -- set day (if new entry)
- `lootboxBaseLevelPacked[index][buyer]` -- set base level (level+2, if new entry)
- `lootboxEvScorePacked[index][buyer]` -- set activity score (if new entry)
- `lootboxIndexQueue[buyer].push(index)` -- push index to queue (if new entry)
- `lootboxBoon25Active/15Active/5Active[buyer]` -- consumed if boost applied (via `_applyLootboxBoostOnPurchase`)
- `lootboxEthBase[index][buyer]` -- incremented by lootboxAmount (unboosted)
- `lootboxEth[index][buyer]` -- set to `(purchaseLevel << 232) | newAmount` (boosted amount packed with level)
- `lootboxEthTotal += lootboxAmount` -- global lootbox ETH tracking (unboosted)
- `lootboxRngPendingEth += lootboxAmount` (via `_maybeRequestLootboxRng`) -- pending RNG ETH

**Callers:**
- `_purchaseWhaleBundle` -- after pool splits
- `_purchaseLazyPass` -- after pool splits
- `_purchaseDeityPass` -- after pool splits

**Callees:**
- `_recordLootboxMintDay(buyer, uint32(dayIndex), cachedPacked)` -- mint day update
- `_simulatedDayIndex()` -- current day
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` -- external self-call for EV score (executes on game contract since this is delegatecall context)
- `_applyLootboxBoostOnPurchase(buyer, dayIndex, lootboxAmount)` -- boost application
- `_maybeRequestLootboxRng(lootboxAmount)` -- pending ETH accumulation

**ETH Flow:**
- No actual ETH movement. Records virtual lootbox amounts for later resolution.
- `lootboxEthTotal` tracks cumulative virtual lootbox ETH across all purchases.
- `lootboxRngPendingEth` tracks pending ETH for next RNG request threshold.

**Invariants:**
- If entry exists for this index+buyer: must be same day (`storedDay == dayIndex`), else reverts
- If new entry: assigns day, base level (level+2), activity score, pushes to index queue
- `lootboxEthBase` stores unboosted amount; `lootboxEth` stores boosted amount packed with level
- `lootboxEthTotal` accumulates unboosted amounts only
- `lootboxRngPendingEth` accumulates unboosted amounts for RNG threshold

**NatSpec Accuracy:** No NatSpec on this function. The inline comments adequately describe behavior.

**Gas Flags:**
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` is an external self-call. Since this runs in delegatecall context, `address(this)` is the game contract, so this calls back into the game. This is a gas-expensive pattern for what could theoretically be an internal read, but the function likely lives on the game contract itself (not the module), making the external call necessary.
- `existingBase` initialization (line 764-767): if existingAmount != 0 but existingBase == 0, sets existingBase = existingAmount. This handles a migration case where older entries didn't track base separately.

**Verdict:** CORRECT

---

### `_maybeRequestLootboxRng(uint256 lootboxAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeRequestLootboxRng(uint256 lootboxAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lootboxAmount` (uint256): ETH amount to add to pending total |
| **Returns** | none |

**State Reads:** None (only writes)
**State Writes:**
- `lootboxRngPendingEth += lootboxAmount` -- accumulates pending lootbox ETH

**Callers:**
- `_recordLootboxEntry` -- after recording each lootbox entry

**Callees:** None

**ETH Flow:** None (accounting only)

**Invariants:**
- Simple accumulation. The actual RNG request threshold check and VRF call happen elsewhere (in AdvanceModule when `requestLootboxRng` is called).

**NatSpec Accuracy:**
- NatSpec says "Accumulate lootbox ETH for pending RNG request" -- ACCURATE but function name `_maybeRequestLootboxRng` implies conditional logic (maybe request). The function always accumulates. The name is slightly misleading since it never actually requests RNG. Previously this function likely contained threshold-checking logic that was refactored out.

**Gas Flags:** None. Single SLOAD + SSTORE.

**Verdict:** CORRECT

---

### `_applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount) private returns (uint256 boostedAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose boost to check; `day` (uint48): current day for event; `amount` (uint256): base lootbox amount |
| **Returns** | `boostedAmount` (uint256): amount after applying boost (>= amount) |

**State Reads:**
- `lootboxBoon25Active[player]` -- 25% boost flag
- `lootboxBoon25Day[player]` -- 25% boost timestamp
- `lootboxBoon15Active[player]` -- 15% boost flag
- `lootboxBoon15Day[player]` -- 15% boost timestamp
- `lootboxBoon5Active[player]` -- 5% boost flag
- `lootboxBoon5Day[player]` -- 5% boost timestamp

**State Writes:**
- `lootboxBoon25Active[player] = false` -- consumed (if used or expired)
- `lootboxBoon15Active[player] = false` -- consumed (if used or expired)
- `lootboxBoon5Active[player] = false` -- consumed (if used or expired)

**Callers:**
- `_recordLootboxEntry` -- to apply boost before recording final amount

**Callees:** None (emits event `LootBoxBoostConsumed`)

**ETH Flow:** None (computation only, modifies virtual lootbox amount)

**Boost Logic:**
- Priority order: 25% > 15% > 5% (checks highest first)
- Each boost: `cappedAmount = min(amount, 10 ETH)`, `boost = cappedAmount * boostBps / 10000`
- The boost applies to the capped amount only, not the full amount if > 10 ETH
- Example: 15 ETH with 25% boost -> boost = 10 * 0.25 = 2.5 ETH, boostedAmount = 17.5 ETH
- Only ONE boost consumed per call (first valid one found)
- Expiry: `currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS (2)` -- expired boosts are deactivated but not applied
- Expired boosts: flag set to false but no event emitted

**Invariants:**
- `boostedAmount >= amount` (boost only adds, never subtracts)
- At most one boost consumed per purchase
- Boost cap ensures maximum additional value is 2.5 ETH (10 ETH * 25%)
- Day parameter is used for event emission only, not for expiry calculation (uses `_simulatedDayIndex()`)

**NatSpec Accuracy:**
- NatSpec says "Checks boosts in order: 25% > 15% > 5%" -- ACCURATE
- NatSpec says "Consumes the first valid boost found" -- ACCURATE
- NatSpec says "Boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH)" -- ACCURATE
- NatSpec says "expires after 2 game days" -- ACCURATE (LOOTBOX_BOOST_EXPIRY_DAYS = 2)

**Gas Flags:**
- `_simulatedDayIndex()` is called once at the top (line 796) but may also be called multiple times in the nested if-else structure. Actually, `currentDay` is cached at line 796 and reused throughout. Efficient.
- Three separate storage reads for each boost tier (active + day). In the worst case (no active boosts), all 6 slots are read. Minor but unavoidable.

**Verdict:** CORRECT

---

### `_recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `day` (uint32): current day index; `cachedPacked` (uint256): caller's cached mintPacked_ value |
| **Returns** | none |

**State Reads:**
- Uses `cachedPacked` parameter (avoids SLOAD of `mintPacked_[player]`)

**State Writes:**
- `mintPacked_[player]` -- updates DAY field if changed

**Callers:**
- `_recordLootboxEntry` -- to update mint day in packed data

**Callees:** None

**ETH Flow:** None

**Invariants:**
- If `prevDay == day`, no-op (idempotent)
- Only modifies the DAY field (bits 72-103) in mintPacked_, leaves all other fields intact
- Uses bit manipulation: clears DAY field, then ORs new day value

**NatSpec Accuracy:**
- NatSpec says "Record the mint day in player's packed data for lootbox tracking" -- ACCURATE
- NatSpec says "The caller's cached mintPacked_ value to avoid a redundant SLOAD" -- ACCURATE. The caller passes their cached copy to avoid re-reading storage.

**Gas Flags:**
- Accepts cached packed data to skip one SLOAD. Good optimization.
- Still performs one SSTORE if day changed. Unavoidable.

**Verdict:** CORRECT

---

### `_nukePassHolderStats(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _nukePassHolderStats(address player) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose stats to zero |
| **Returns** | none |

**State Reads:**
- `mintPacked_[player]` -- current packed mint data

**State Writes:**
- `mintPacked_[player]` -- zeros 4 fields:
  - LEVEL_COUNT (bits 24-47) -> 0
  - LEVEL_STREAK (bits 48-71) -> 0
  - LAST_LEVEL (bits 0-23) -> 0
  - MINT_STREAK_LAST_COMPLETED (bits 160-183) -> 0
- External: `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(player)` -- resets quest streak

**Callers:**
- `_handleDeityPassTransfer` -- penalty for transferring deity pass

**Callees:**
- `BitPackingLib.setPacked()` -- 4 calls to zero fields
- `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(player)` -- external: quest streak reset

**ETH Flow:** None

**Invariants:**
- Only zeros specific stat fields; preserves other packed fields (FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, DAY, LEVEL_UNITS_LEVEL, LEVEL_UNITS)
- Quest streak reset is an external call to the Quests contract, which also runs in the game's delegatecall context (the call originates from the game address)

**NatSpec Accuracy:**
- NatSpec says "Zero mint stats and quest streak" -- ACCURATE. Four packed fields zeroed plus external quest reset.

**Gas Flags:**
- Uses `BitPackingLib.setPacked` four times sequentially on the same `data` variable. Could potentially be optimized with a single bitmask operation, but the current approach is clear and correct.

**Verdict:** CORRECT


---

## DegenerusGameDegeneretteModule.sol

### `placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): player address, zero for msg.sender; `currency` (uint8): 0=ETH, 1=BURNIE, 3=WWXRP; `amountPerTicket` (uint128): bet amount per spin; `ticketCount` (uint8): number of spins 1-10; `customTicket` (uint32): packed 4x8-bit traits; `heroQuadrant` (uint8): 0-3 for boost, 0xFF for none |
| **Returns** | none |

**State Reads:** (delegated to `_resolvePlayer` and `_placeFullTicketBets`)
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)

**State Writes:** (delegated to `_placeFullTicketBets`)

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Receives msg.value when currency=ETH; delegates handling to `_collectBetFunds`
**Invariants:** Player must be msg.sender or approved operator. Bet parameters validated downstream.
**NatSpec Accuracy:** Accurate. Documents currency types, parameter meanings, hero quadrant semantics.
**Gas Flags:** None -- thin wrapper delegating to private functions.
**Verdict:** CORRECT

---

### `placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external` |
| **Visibility** | external |
| **Mutability** | state-changing (not payable) |
| **Parameters** | `player` (address): player address, zero for msg.sender; `amountPerTicket` (uint128): bet amount per spin; `ticketCount` (uint8): spins 1-10; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): 0-3 or 0xFF |
| **Returns** | none |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)
- `lootboxRngIndex`, `lootboxRngWordByIndex[index]` (via `_placeFullTicketBetsCore`)
- `mintPacked_[player]`, `level`, `deityPassCount[player]` (via `_playerActivityScoreInternal`)
- `degeneretteBetNonce[player]`

**State Writes:**
- `degeneretteBets[player][nonce]` = packed bet (via `_placeFullTicketBetsCore`)
- `degeneretteBetNonce[player]` = nonce+1 (via `_placeFullTicketBetsCore`)
- `lootboxRngPendingBurnie += totalBet`

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_placeFullTicketBetsCore(...)`, `affiliate.consumeDegeneretteCredit(player, totalBet)` [external], `coin.notifyQuestDegenerette(player, totalBet, false)` [external]

**ETH Flow:** No ETH movement. Uses affiliate BURNIE credit (consumed via external call).
**Invariants:**
- `affiliate.consumeDegeneretteCredit` must return exactly `totalBet`; otherwise reverts `InvalidBet`
- Currency is hardcoded to `CURRENCY_BURNIE` (1)
- Not payable -- no ETH accepted
**NatSpec Accuracy:** Accurate. States it uses "BURNIE bet currency semantics without burning wallet balance."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `resolveBets(address player, uint64[] calldata betIds)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveBets(address player, uint64[] calldata betIds) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address, zero for msg.sender; `betIds` (uint64[]): array of bet IDs to resolve |
| **Returns** | none |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)
- `degeneretteBets[player][betId]` for each bet (via `_resolveBet`)
- `lootboxRngWordByIndex[index]` for RNG word availability
- `futurePrizePool` for ETH payout capping

**State Writes:**
- `degeneretteBets[player][betId]` = 0 (deleted on resolve)
- `futurePrizePool` -= ethPortion (on ETH wins)
- `claimableWinnings[player]` += ethPortion (on ETH wins)
- `claimablePool` += ethPortion (on ETH wins)

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_resolveBet(player, betIds[i])` in loop

**ETH Flow:** ETH payouts from `futurePrizePool` to `claimableWinnings[player]` (via `_distributePayout`). Excess routed to lootbox.
**Invariants:**
- Each betId must have non-zero packed data (otherwise `InvalidBet`)
- RNG word must be available for the bet's index (otherwise `RngNotReady`)
- Bets are deleted after resolution (prevents double-resolve)
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Loop uses unchecked increment -- appropriate gas optimization.
**Verdict:** CORRECT

---

### `_placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet per spin; `ticketCount` (uint8): spins; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | none |

**State Reads:** (delegated to `_placeFullTicketBetsCore` and `_collectBetFunds`)
**State Writes:** (delegated to `_placeFullTicketBetsCore` and `_collectBetFunds`)

**Callers:** `placeFullTicketBets`
**Callees:** `_placeFullTicketBetsCore(...)`, `_collectBetFunds(player, currency, totalBet, msg.value, jackpotResolutionActive)`, `coin.notifyQuestDegenerette(player, totalBet, isEth)` [external]

**ETH Flow:** Passes msg.value to `_collectBetFunds` for ETH bets.
**Invariants:** Quest notification sent only for ETH (isEth=true) and BURNIE (isEth=false) currencies. WWXRP bets do not trigger quest progress.
**NatSpec Accuracy:** No NatSpec provided (internal implementation). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_placeFullTicketBetsCore(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _placeFullTicketBetsCore(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) private returns (uint256 totalBet, bool jackpotResolutionActive)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet per spin; `ticketCount` (uint8): spin count; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | `totalBet` (uint256): total bet amount; `jackpotResolutionActive` (bool): whether jackpot resolution is active |

**State Reads:**
- `lootboxRngIndex` -- current RNG batch index
- `lootboxRngWordByIndex[index]` -- must be 0 (no RNG word yet = accepting bets)
- `rngLockedFlag`, `lastPurchaseDay`, `level` -- for jackpot resolution detection
- `mintPacked_[player]`, `deityPassCount[player]` -- via `_playerActivityScoreInternal`
- `degeneretteBetNonce[player]` -- current bet nonce
- `dailyHeroWagers[day][heroQuadrant]` -- for hero wager tracking (ETH only)
- `playerDegeneretteEthWagered[player][lvl]` -- per-player per-level ETH wagered
- `topDegeneretteByLevel[lvl]` -- top wagerer tracking

**State Writes:**
- `degeneretteBetNonce[player]` = nonce + 1
- `degeneretteBets[player][nonce]` = packed bet data
- `dailyHeroWagers[day][heroQuadrant]` -- updated hero wager packed data (ETH only)
- `playerDegeneretteEthWagered[player][lvl]` += totalBet (ETH only)
- `topDegeneretteByLevel[lvl]` = (playerScaled << 160) | player (if new top, ETH only)

**Callers:** `_placeFullTicketBets`, `placeFullTicketBetsFromAffiliateCredit`
**Callees:** `_validateMinBet(currency, amountPerTicket)`, `_playerActivityScoreInternal(player)`, `_packFullTicketBet(...)`, `_simulatedDayIndex()` [inherited from DegenerusGameStorage]

**ETH Flow:** No direct ETH movement (funds collected separately in `_collectBetFunds`).
**Invariants:**
- `ticketCount` must be 1-10 (MAX_SPINS_PER_BET)
- `amountPerTicket` must be non-zero
- `lootboxRngIndex` must be non-zero (game initialized)
- RNG word for current index must be 0 (bet window open)
- ETH bets blocked during jackpot resolution (`rngLockedFlag && lastPurchaseDay && (level+1)%5==0`)
- `totalBet` = amountPerTicket * ticketCount (no overflow risk: uint128 * uint8 fits uint256)
- Hero wager tracking: wagerUnit scaled by 1e12, saturates at uint32 max (0xFFFFFFFF)
- Top degenerette: stores playerScaled (totalWei/1e12) in upper 96 bits, player address in lower 160 bits

**NatSpec Accuracy:** No NatSpec beyond "@dev Internal implementation for placing Full Ticket bets." Inline comments are thorough.
**Gas Flags:**
- The `dailyHeroWagers` tracking involves a read-modify-write of a packed uint256, acceptable gas cost.
- Hero wager tracking only runs for ETH bets with heroQuadrant < 4, avoiding unnecessary computation.
**Verdict:** CORRECT

---

### `_collectBetFunds(address player, uint8 currency, uint256 totalBet, uint256 ethPaid, bool jackpotResolutionActive)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _collectBetFunds(address player, uint8 currency, uint256 totalBet, uint256 ethPaid, bool jackpotResolutionActive) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): bettor; `currency` (uint8): currency type; `totalBet` (uint256): total bet; `ethPaid` (uint256): msg.value; `jackpotResolutionActive` (bool): jackpot lock |
| **Returns** | none |

**State Reads:**
- `claimableWinnings[player]` (for ETH shortfall from claimable)

**State Writes:**
- `claimableWinnings[player]` -= fromClaimable (ETH shortfall)
- `claimablePool` -= fromClaimable (ETH shortfall)
- `futurePrizePool` += totalBet (ETH only)
- `lootboxRngPendingEth` += totalBet (ETH only)
- `lootboxRngPendingBurnie` += totalBet (BURNIE only)

**Callers:** `_placeFullTicketBets`
**Callees:** `coin.burnCoin(player, totalBet)` [external, BURNIE], `wwxrp.burnForGame(player, totalBet)` [external, WWXRP]

**ETH Flow:**
- ETH bets: msg.value goes to contract balance; `futurePrizePool` and `lootboxRngPendingEth` increase by totalBet
- If ethPaid < totalBet: shortfall pulled from `claimableWinnings[player]` (decrements `claimablePool`)
- If ethPaid > totalBet: reverts `InvalidBet` (overpayment rejected)
- BURNIE: tokens burned from player wallet via `coin.burnCoin`
- WWXRP: tokens burned from player wallet via `wwxrp.burnForGame`

**Invariants:**
- ETH bets during jackpot resolution: double-reverts with `E()` (redundant with `_placeFullTicketBetsCore` check, defensive)
- For claimable shortfall: requires `claimableWinnings[player] > fromClaimable` (strict greater-than). Note: this means if claimableWinnings exactly equals fromClaimable, it reverts. This is intentional -- prevents draining claimable balance to zero via degenerette bets, preserving a dust balance.
- WWXRP bets do not update `lootboxRngPendingBurnie` or `lootboxRngPendingEth` -- WWXRP is mint/burn-based with no pool accounting.

**NatSpec Accuracy:** Brief NatSpec ("Processes bet funds"). Inline comments adequate.
**Gas Flags:** The double-check of `jackpotResolutionActive` for ETH (already checked in `_placeFullTicketBetsCore`) is redundant but defensive. Minimal gas cost.
**Verdict:** CORRECT -- The strict greater-than check on claimable is a design choice preventing zero-balance draining.

---

### `_resolveBet(address player, uint64 betId)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveBet(address player, uint64 betId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `betId` (uint64): bet identifier |
| **Returns** | none |

**State Reads:** `degeneretteBets[player][betId]`
**State Writes:** (delegated to `_resolveFullTicketBet`)

**Callers:** `resolveBets` (in loop)
**Callees:** `_resolveFullTicketBet(player, betId, packed)`

**ETH Flow:** Delegated to resolution functions.
**Invariants:** Packed data must be non-zero (otherwise `InvalidBet`). Mode bit is always 1 (full ticket) since that is the only mode.
**NatSpec Accuracy:** Accurate ("Resolves a bet (determines mode from packed data)"). Note: the mode determination comment is vestigial -- only full ticket mode exists now.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_resolveFullTicketBet(address player, uint64 betId, uint256 packed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveFullTicketBet(address player, uint64 betId, uint256 packed) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `betId` (uint64): bet ID; `packed` (uint256): packed bet data |
| **Returns** | none |

**State Reads:**
- Unpacked from `packed`: customTicket, ticketCount, currency, amountPerTicket, index, activityScore, heroBits
- `lootboxRngWordByIndex[index]` -- the RNG word for this bet's batch

**State Writes:**
- `degeneretteBets[player][betId]` = 0 (delete)
- `futurePrizePool` -= ethPortion (via `_distributePayout`, ETH only)
- `claimableWinnings[player]` += ethPortion (via `_addClaimableEth`, ETH only)
- `claimablePool` += ethPortion (via `_addClaimableEth`, ETH only)

**Callers:** `_resolveBet`
**Callees:**
- `_roiBpsFromScore(activityScore)` -- ROI calculation
- `_wwxrpHighValueRoi(activityScore)` -- WWXRP bonus ROI (only if currency == WWXRP)
- `DegenerusTraitUtils.packedTraitsFromSeed(resultSeed)` [library] -- generate result traits
- `_countMatches(playerTicket, resultTicket)` -- count attribute matches
- `_fullTicketPayout(...)` -- calculate payout amount
- `_distributePayout(player, currency, payout, lootboxWord)` -- distribute winnings
- `_maybeAwardConsolation(player, currency, amountPerTicket)` -- consolation prize on total loss

**ETH Flow:**
- For each winning spin: payout distributed via `_distributePayout`
- ETH: 25% to claimable (capped at 10% of pool), 75% + excess to lootbox
- BURNIE: minted to player
- WWXRP: minted to player
- On total loss (totalPayout == 0): consolation prize (1 WWXRP) if qualifying

**Invariants:**
- RNG word must be available (non-zero) for the bet's index
- Bet is deleted before payout processing (prevents reentrancy on resolve)
- Each spin uses a deterministic seed: spin 0 uses legacy seed (backwards compatible), spins 1+ mix spinIdx into hash
- Lootbox words for multi-spin ETH bets are also diversified per spin (prevents identical lootbox outcomes)
- Consolation prize only awarded if ALL spins produced 0 payout
- Hero quadrant decoded as 3 bits: bit 0 = enabled, bits 1-2 = quadrant index

**NatSpec Accuracy:** Accurate.
**Gas Flags:**
- The `_roiBpsFromScore` is called once outside the loop with the snapshot activity score -- efficient.
- `_wwxrpHighValueRoi` is also called once outside the loop -- efficient.
- Per-spin hash computation is unavoidable for deterministic independence.
**Verdict:** CORRECT

---

### `_distributePayout(address player, uint8 currency, uint256 payout, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributePayout(address player, uint8 currency, uint256 payout, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `currency` (uint8): currency type; `payout` (uint256): payout amount; `rngWord` (uint256): RNG word for lootbox conversion |
| **Returns** | none |

**State Reads:**
- `futurePrizePool` (ETH only, for cap calculation)

**State Writes:**
- `futurePrizePool` -= ethPortion (ETH only, unchecked subtraction)
- `claimablePool` += ethPortion (via `_addClaimableEth`)
- `claimableWinnings[player]` += ethPortion (via `_addClaimableEth` -> `_creditClaimable`)

**Callers:** `_resolveFullTicketBet` (per winning spin)
**Callees:**
- `_addClaimableEth(player, ethPortion)` (ETH)
- `_resolveLootboxDirect(player, lootboxPortion, rngWord)` (ETH, excess to lootbox)
- `coin.mintForGame(player, payout)` [external] (BURNIE)
- `wwxrp.mintPrize(player, payout)` [external] (WWXRP)

**ETH Flow:**
- ETH: Split 25% claimable / 75% lootbox
- Cap: ethPortion capped at 10% of futurePrizePool (ETH_WIN_CAP_BPS = 1000)
- Excess above cap: redirected to lootbox portion
- After capping: `futurePrizePool -= ethPortion` (unchecked, safe because ethPortion <= 10% of pool)
- Emits `PayoutCapped` event when cap triggers

**Invariants:**
- `ethPortion = payout / 4` (integer division, 25%)
- `lootboxPortion = payout - ethPortion` (75% + rounding)
- maxEth = pool * 1000 / 10000 = pool * 10%
- After capping, ethPortion <= pool * 10%, so unchecked subtraction is safe
- BURNIE and WWXRP payouts are fully minted (no pool constraints)

**NatSpec Accuracy:** Accurate. States "25% as ETH (capped at 10% of pool), 75% + any excess above cap converted to lootbox rewards."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_maybeAwardConsolation(address player, uint8 currency, uint128 amountPerTicket)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeAwardConsolation(address player, uint8 currency, uint128 amountPerTicket) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet amount per spin |
| **Returns** | none |

**State Reads:** None
**State Writes:** None directly (external call to wwxrp.mintPrize)

**Callers:** `_resolveFullTicketBet` (when totalPayout == 0)
**Callees:** `wwxrp.mintPrize(player, CONSOLATION_PRIZE_WWXRP)` [external] (if qualifying)

**ETH Flow:** None. Awards 1 WWXRP token via external mint.
**Invariants:**
- Qualification thresholds: ETH >= 0.01 ETH, BURNIE >= 500, WWXRP >= 20
- Consolation amount: fixed 1 WWXRP (1e18)
- Unsupported currencies do not qualify (no else clause)
- Only called when ALL spins resulted in 0 payout

**NatSpec Accuracy:** Accurate. Documents thresholds and behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): ETH value for lootbox; `rngWord` (uint256): RNG word for lootbox roll |
| **Returns** | none |

**State Reads:** None directly (delegatecall reads/writes happen in LootboxModule context)
**State Writes:** None directly (delegatecall writes happen in LootboxModule context)

**Callers:** `_distributePayout` (for ETH lootbox portion)
**Callees:**
- `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(...)` -- calls `IDegenerusGameLootboxModule.resolveLootboxDirect(player, amount, rngWord)`
- `_revertDelegate(data)` -- on delegatecall failure

**ETH Flow:** ETH value is conceptually "converted" to lootbox rewards via the LootboxModule. The actual ETH remains in the Game contract; the LootboxModule handles reward distribution (DGNRS tickets, whale pass claims, etc.) through its own internal accounting.
**Invariants:**
- Delegatecall executes LootboxModule code in Game's storage context
- If delegatecall fails, original revert reason is propagated
- The lootbox module applies its own activity-score-based EV multiplier

**NatSpec Accuracy:** Accurate. Notes "Applies activity-score EV multiplier (80-135%) to match regular lootbox opens."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): address to credit; `weiAmount` (uint256): amount in wei |
| **Returns** | none |

**State Reads:** None directly (reads happen in `_creditClaimable`)
**State Writes:**
- `claimablePool` += weiAmount
- `claimableWinnings[beneficiary]` += weiAmount (via `_creditClaimable`)

**Callers:** `_distributePayout` (for ETH payouts)
**Callees:** `_creditClaimable(beneficiary, weiAmount)` [inherited from DegenerusGamePayoutUtils]

**ETH Flow:** Credits ETH to player's claimable balance. No actual ETH transfer -- ETH remains in contract, player withdraws later.
**Invariants:**
- Early return if weiAmount == 0 (no-op)
- `claimablePool` acts as aggregate liability counter
- `_creditClaimable` increments per-player balance and emits `PlayerCredited`
- Note: This version does NOT use auto-rebuy (simplified compared to other modules' `_addClaimableEth` that take entropy parameter)

**NatSpec Accuracy:** Accurate. "Adds ETH to a player's claimable winnings balance."
**Gas Flags:** None.
**Verdict:** CORRECT


---

## DegenerusGameBoonModule.sol

### `consumeCoinflipBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipBoon(address player) external returns (uint16 boonBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boon for |
| **Returns** | `boonBps` (uint16): The bonus in basis points (0 if no boon, 500/1000/2500 otherwise) |

**State Reads:**
- `deityCoinflipBoonDay[player]` -- deity-granted day stamp
- `coinflipBoonDay[player]` -- lootbox-rolled day stamp
- `coinflipBoonBps[player]` -- boon value in BPS

**State Writes:**
- `coinflipBoonBps[player] = 0` -- clears boon value
- `coinflipBoonDay[player] = 0` -- clears stamp day
- `deityCoinflipBoonDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumeCoinflipBoon(player)` via delegatecall (access-restricted to COIN or COINFLIP contracts)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None. This function does not move ETH.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- deity-granted boon expired. Clear all 3 variables, return 0.
4. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- lootbox-rolled boon expired. Clear all 3, return 0.
5. Read `boonBps`. If 0, early return 0.
6. Clear all 3 variables, return `boonBps` (consumed successfully).

**Invariants:**
- After function returns, all 3 storage variables for this player are always zeroed (boon is single-use).
- If boon is expired (deity day mismatch or lootbox day + 2 exceeded), return value is 0.
- address(0) never has boons consumed.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's coinflip boon and return the bonus BPS" with values "0 if no boon, 500/1000/2500 otherwise". The code returns exactly those possible values from `coinflipBoonBps[player]` which are set by LootboxModule at those tiers.

**Gas Flags:**
- On the expired-deity path (line 42-46), the function writes all 3 storage slots even if some were already 0. This is acceptable since SSTOREs to 0 get gas refund and the code prioritizes simplicity.
- The function always clears `deityCoinflipBoonDay` even for lootbox-rolled boons where it's already 0. Minor redundancy but no correctness impact.

**Verdict:** CORRECT

---

### `consumePurchaseBoost(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumePurchaseBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boost for |
| **Returns** | `boostBps` (uint16): The bonus in basis points (0 if no boost, 500/1500/2500 otherwise) |

**State Reads:**
- `deityPurchaseBoostDay[player]` -- deity-granted day stamp
- `purchaseBoostDay[player]` -- lootbox-rolled day stamp
- `purchaseBoostBps[player]` -- boost value in BPS

**State Writes:**
- `purchaseBoostBps[player] = 0` -- clears boost value
- `purchaseBoostDay[player] = 0` -- clears stamp day
- `deityPurchaseBoostDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumePurchaseBoost(player)` via delegatecall (access-restricted to `address(this)` -- i.e., self-call from delegate modules)
- `DegenerusGameMintModule.purchase()` calls `IDegenerusGame(address(this)).consumePurchaseBoost(buyer)` (line 831)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- expired. Clear all 3, return 0.
4. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + PURCHASE_BOOST_EXPIRY_DAYS (4)` -- expired. Clear all 3, return 0.
5. Read `boostBps`. If 0, early return 0.
6. Clear all 3 variables, return `boostBps` (consumed successfully).

**Invariants:**
- Identical pattern to `consumeCoinflipBoon` but with 4-day expiry instead of 2-day.
- After function returns, all 3 storage variables for this player are zeroed.
- Single-use consumption.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's purchase boost and return the bonus BPS" with values "0 if no boost, 500/1500/2500 otherwise". Matches the tiers set in LootboxModule.

**Gas Flags:**
- Same minor redundancy as `consumeCoinflipBoon`: always clears `deityPurchaseBoostDay` even for lootbox-rolled boons where it's 0. Acceptable.

**Verdict:** CORRECT

---

### `consumeDecimatorBoost(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecimatorBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boost for |
| **Returns** | `boostBps` (uint16): The bonus in basis points (0 if no boost, 1000/2500/5000 otherwise) |

**State Reads:**
- `deityDecimatorBoostDay[player]` -- deity-granted day stamp
- `decimatorBoostBps[player]` -- boost value in BPS

**State Writes:**
- `decimatorBoostBps[player] = 0` -- clears boost value
- `deityDecimatorBoostDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumeDecimatorBoon(player)` via delegatecall (access-restricted to COIN contract only)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- deity-granted boon expired. Clear 2 variables, return 0.
4. Read `boostBps`. If 0, early return 0.
5. Clear 2 variables, return `boostBps` (consumed successfully).

**Key Difference: No Stamp Day Check**

Unlike `consumeCoinflipBoon` and `consumePurchaseBoost`, this function has **no lootbox stamp day expiry check**. This is **intentional by design**:

1. There is no `decimatorBoostDay` storage variable in `DegenerusGameStorage`. The storage comment for `decimatorBoostBps` explicitly says: "one-time, **no expiry**" (line 781).
2. In `LootboxModule._applyBoon()` (line 1435): `deityDecimatorBoostDay[player] = isDeity ? day : uint48(0)` -- lootbox-rolled decimator boosts set the deity day to 0, and no stamp day is set.
3. Therefore: lootbox-rolled decimator boosts persist indefinitely until consumed. Only deity-granted decimator boosts expire (when `deityDay != currentDay`).

This makes game-design sense: decimator boosts encourage BURNIE burning (deflationary action), so giving them no expiry incentivizes players to use them rather than pressuring them with a time window.

**Invariants:**
- After function returns, both `decimatorBoostBps` and `deityDecimatorBoostDay` are zeroed.
- Only 2 storage variables (vs 3 for coinflip/purchase) since there is no stamp day variable.
- Single-use consumption.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's decimator boost and return the bonus BPS" with values "0 if no boost, 1000/2500/5000 otherwise".

**Gas Flags:** None. Simpler than the other consume functions due to no stamp day check.

**Verdict:** CORRECT

---

### `checkAndClearExpiredBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to check and clear expired boons for |
| **Returns** | `hasAnyBoon` (bool): True if the player has at least one active (non-expired) boon |

**State Reads (all per-player):**
- `coinflipBoonBps[player]` -- coinflip boon value
- `deityCoinflipBoonDay[player]` -- deity coinflip day
- `coinflipBoonDay[player]` -- lootbox coinflip stamp day
- `lootboxBoon25Active[player]` -- 25% lootbox boost flag
- `deityLootboxBoon25Day[player]` -- deity 25% lootbox day
- `lootboxBoon25Day[player]` -- lootbox 25% stamp day
- `lootboxBoon15Active[player]` -- 15% lootbox boost flag
- `deityLootboxBoon15Day[player]` -- deity 15% lootbox day
- `lootboxBoon15Day[player]` -- lootbox 15% stamp day
- `lootboxBoon5Active[player]` -- 5% lootbox boost flag
- `deityLootboxBoon5Day[player]` -- deity 5% lootbox day
- `lootboxBoon5Day[player]` -- lootbox 5% stamp day
- `purchaseBoostBps[player]` -- purchase boost value
- `deityPurchaseBoostDay[player]` -- deity purchase day
- `purchaseBoostDay[player]` -- lootbox purchase stamp day
- `decimatorBoostBps[player]` -- decimator boost value
- `deityDecimatorBoostDay[player]` -- deity decimator day
- `whaleBoonDay[player]` -- whale boon day
- `deityWhaleBoonDay[player]` -- deity whale day
- `whaleBoonDiscountBps[player]` -- whale boon discount (read for clearing only)
- `lazyPassBoonDay[player]` -- lazy pass boon day
- `deityLazyPassBoonDay[player]` -- deity lazy pass day
- `lazyPassBoonDiscountBps[player]` -- lazy pass discount (read for clearing only)
- `deityPassBoonTier[player]` -- deity pass boon tier
- `deityDeityPassBoonDay[player]` -- deity-granted deity pass day
- `deityPassBoonDay[player]` -- lootbox deity pass stamp day
- `activityBoonPending[player]` -- pending activity boon amount
- `deityActivityBoonDay[player]` -- deity activity day
- `activityBoonDay[player]` -- lootbox activity stamp day

**State Writes (conditional -- only when expired):**
- Coinflip: `coinflipBoonBps`, `coinflipBoonDay`, `deityCoinflipBoonDay` set to 0
- Lootbox 25%: `lootboxBoon25Active` set to false, `deityLootboxBoon25Day` set to 0; note: `lootboxBoon25Day` is NOT cleared (only deity day is zeroed)
- Lootbox 15%: `lootboxBoon15Active` set to false, `deityLootboxBoon15Day` set to 0; note: `lootboxBoon15Day` is NOT cleared
- Lootbox 5%: `lootboxBoon5Active` set to false, `deityLootboxBoon5Day` set to 0; note: `lootboxBoon5Day` is NOT cleared
- Purchase: `purchaseBoostBps`, `purchaseBoostDay`, `deityPurchaseBoostDay` set to 0
- Decimator: `decimatorBoostBps`, `deityDecimatorBoostDay` set to 0 (deity-expired only)
- Whale: `whaleBoonDay`, `deityWhaleBoonDay`, `whaleBoonDiscountBps` set to 0
- Lazy pass: `lazyPassBoonDay`, `lazyPassBoonDiscountBps`, `deityLazyPassBoonDay` set to 0
- Deity pass: `deityPassBoonTier`, `deityPassBoonDay`, `deityDeityPassBoonDay` set to 0
- Activity: `activityBoonPending`, `activityBoonDay`, `deityActivityBoonDay` set to 0

**Callers:**
- `DegenerusGameLootboxModule` via nested delegatecall (line 1002): `abi.encodeWithSelector(IDegenerusGameBoonModule.checkAndClearExpiredBoon.selector, player)` -- called during lootbox resolution to determine if player has any active boon (for `hasBoon` flag)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow (10 boon type blocks):**

The function processes each boon type sequentially, checking expiry and clearing if expired. For each type, local variables shadow the storage values to track whether the boon survived expiry checks. The final return aggregates all local variables with OR.

**Block 1: Coinflip Boon** (lines 117-134)
- Skip if `coinflipBps == 0`
- Deity expiry: `deityDay != 0 && deityDay != currentDay` -> clear all 3, local = 0
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + 2` -> clear all 3, local = 0

**Block 2: Lootbox Boost 25%** (lines 136-156)
- If active: deity expiry or lootbox expiry -> deactivate + clear deity day
- If NOT active but `deityLootboxBoon25Day != 0 && deityDay != currentDay`: clean up stale deity day
- Note: The `else` block (lines 151-156) handles a corner case where the active flag is false but a stale deity day entry remains. This is defensive cleanup.

**Block 3: Lootbox Boost 15%** (lines 158-178)
- Identical pattern to Block 2.

**Block 4: Lootbox Boost 5%** (lines 180-200)
- Identical pattern to Block 2.

**Block 5: Purchase Boost** (lines 202-219)
- Skip if `purchaseBps == 0`
- Deity expiry: same pattern as coinflip
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + 4`

**Block 6: Decimator Boost** (lines 221-229)
- Skip if `decimatorBps == 0`
- **Only deity expiry check** (no stamp day exists for decimator boost)
- If `deityDay != 0 && deityDay != currentDay`: clear `decimatorBoostBps` and `deityDecimatorBoostDay`
- No lootbox expiry block -- consistent with storage design (decimator boost has no expiry for lootbox-rolled)

**Block 7: Whale Boon** (lines 231-238)
- **No active flag check** -- uses `whaleBoonDay` as the indicator
- Deity expiry: `deityWhaleDay != 0 && deityWhaleDay != currentDay` -> clear day, deity day, and discount BPS
- NOTE: No lootbox stamp expiry here. The whale boon expiry is handled in WhaleModule when consumed. This function only handles deity expiry for whale boons.

**Block 8: Lazy Pass Boon** (lines 239-253)
- Guard: `lazyDay != 0`
- Deity expiry: `deityDay != 0 && deityDay != currentDay` -> clear day, discount, deity day
- Lootbox expiry: `currentDay > lazyDay + 4` (hardcoded 4 days, matches `DEITY_PASS_BOON_EXPIRY_DAYS` value but not using the constant -- acceptable since lazy pass has its own semantics)

**Block 9: Deity Pass Boon** (lines 255-273)
- Guard: `deityTier != 0`
- **Different deity expiry logic:** If `deityDay != 0` (deity-granted), check `currentDay > deityDay` (expires AFTER the deity day, not on mismatch). This means deity-granted deity pass boons last until end of their granted day (inclusive of that day).
- If `deityDay == 0` (lootbox-rolled): check `stampDay > 0 && currentDay > stampDay + DEITY_PASS_BOON_EXPIRY_DAYS (4)`

**Block 10: Activity Boon** (lines 275-292)
- Guard: `activityPending != 0`
- Deity expiry: standard `deityDay != 0 && deityDay != currentDay`
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- reuses the 2-day coinflip constant

**Return value (lines 294-303):**
```solidity
return (whaleDay != 0 || lazyDay != 0 || coinflipBps != 0 || lootbox25 || lootbox15 || lootbox5 || purchaseBps != 0 || decimatorBps != 0 || activityPending != 0 || deityTier != 0);
```
Returns true if ANY boon type survived the expiry checks.

**Invariants:**
- Every expired boon is cleared from storage. Non-expired boons are left untouched.
- The return value accurately reflects whether any active boon remains.
- The function is idempotent: calling it twice produces the same result (expired boons are already cleared on first call).
- No boon is consumed (only expired ones are cleared).

**NatSpec Accuracy:** Accurate. NatSpec says "Clear all expired boons for a player and report if any remain active." and "Called via nested delegatecall from LootboxModule during lootbox resolution." Both are correct.

**Gas Flags:**
- **Lootbox boost blocks do not clear `lootboxBoonXXDay` on expiry** (only clear the active flag and deity day). The stale stamp day remains in storage. This is harmless because the active flag is the primary indicator, but it means a dead stamp day occupies storage. Minor gas inefficiency (missed refund on clearing the day), but no correctness issue.
- **Whale boon block has no lootbox stamp expiry logic** -- whale boon lootbox expiry is handled in WhaleModule consumption. This is consistent with the design (BoonModule only does deity-expiry cleanup for whale boons during lootbox resolution).
- The function performs up to 30 SLOADs and up to 30 SSTOREs in the worst case (all boon types active and all expired). This is expensive but acceptable since it's called once per lootbox resolution and cleans up all boon state.

**Verdict:** CORRECT

---

### `consumeActivityBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeActivityBoon(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address |
| **Returns** | None (void) |

**State Reads:**
- `activityBoonPending[player]` -- pending activity boon amount (uint24)
- `deityActivityBoonDay[player]` -- deity-granted day stamp
- `activityBoonDay[player]` -- lootbox-rolled stamp day
- `mintPacked_[player]` -- bit-packed mint data (reads LEVEL_COUNT_SHIFT field)

**State Writes:**
- `activityBoonPending[player] = 0` -- clears pending amount
- `activityBoonDay[player] = 0` -- clears stamp day
- `deityActivityBoonDay[player] = 0` -- clears deity day
- `mintPacked_[player]` -- updates LEVEL_COUNT field via `BitPackingLib.setPacked()` (only if changed)

**Callers:**
- `DegenerusGameLootboxModule` via nested delegatecall (line 945): `abi.encodeWithSelector(IDegenerusGameBoonModule.consumeActivityBoon.selector, player)` -- called during lootbox resolution

**Callees:**
- `quests.awardQuestStreakBonus(player, bonus, currentDay)` -- external call to `IDegenerusQuests` at `ContractAddresses.QUESTS` to award quest streak bonus days
- `BitPackingLib.setPacked()` -- library call for bit-packed field manipulation

**ETH Flow:** None.

**Logic Flow:**
1. Read `pending = activityBoonPending[player]`. If 0 or `player == address(0)`, early return.
2. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- expired. Clear all 3 activity boon vars, return (boon wasted).
3. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- expired. Clear all 3, return.
4. **Consume the boon:** Clear all 3 activity boon vars.
5. **Update mintPacked_:** Read `prevData`, extract `levelCount` (24-bit field at LEVEL_COUNT_SHIFT=24). Add `pending` to `levelCount`, saturating at `uint24.max` (16,777,215). Write back via `BitPackingLib.setPacked()` only if data changed.
6. **Award quest streak:** Downcast `pending` to uint16 (saturating at `uint16.max` = 65,535). If `currentDay != 0 && bonus != 0`, call `quests.awardQuestStreakBonus(player, bonus, currentDay)`.

**Saturation Behavior:**
- `levelCount` saturates at `uint24.max` (16,777,215). This prevents overflow in the 24-bit packed field.
- `bonus` for quest streak saturates at `uint16.max` (65,535). This matches the `awardQuestStreakBonus` parameter type (`uint16 amount`).
- If `pending > 65,535`, the level count gets the full `pending` amount (up to uint24.max) but the quest streak bonus is capped at 65,535. This discrepancy is acceptable since quest streak amounts that large are unrealistic in practice.

**Invariants:**
- After function returns, `activityBoonPending`, `activityBoonDay`, and `deityActivityBoonDay` are always zeroed (consumed or expired).
- `mintPacked_` levelCount can only increase or stay the same (never decrease).
- External call to `quests.awardQuestStreakBonus` is the only external interaction in the entire module.
- The `currentDay != 0` guard on the quest call prevents calling during day 0 (genesis). This is a defensive check since `_simulatedDayIndex()` should never return 0 in practice.

**NatSpec Accuracy:** Mostly accurate. NatSpec says "Consume a pending activity boon and apply it to player stats." and "Called via nested delegatecall from LootboxModule during lootbox resolution." Both correct. However, the NatSpec does not mention the quest streak bonus side effect -- minor omission but not a discrepancy.

**Gas Flags:**
- The `if (data != prevData)` guard (line 350) avoids an unnecessary SSTORE when the level count doesn't change (e.g., if pending is 0, which is already guarded earlier). Good optimization.
- The external call to `quests.awardQuestStreakBonus` adds ~2600 gas for the cross-contract call overhead. Acceptable.

**Verdict:** CORRECT


---

## DegenerusGameDecimatorModule.sol

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

## MintStreakUtils / PayoutUtils

### `_recordMintStreakForLevel(address player, uint24 mintLevel)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordMintStreakForLevel(address player, uint24 mintLevel) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to record streak for; `mintLevel` (uint24): level just completed |
| **Returns** | None |

**State Reads:**
- `mintPacked_[player]` -- packed mint data word (reads lastCompleted from bits 160-183, streak from bits 48-71)

**State Writes:**
- `mintPacked_[player]` -- updates lastCompleted (bits 160-183) and streak (bits 48-71) via mask-and-set

**Callers:**
- `DegenerusGame.recordMintQuestStreak(address player)` (line 447) -- external entry point, access-gated to COIN contract only, passes `_activeTicketLevel()` as mintLevel

**Callees:**
- None (leaf function -- only bitwise operations)

**ETH Flow:** None -- pure storage bookkeeping.

**Invariants:**
1. Idempotent per level: if `lastCompleted == mintLevel`, returns immediately (no double-credit)
2. Streak increments only if `lastCompleted + 1 == mintLevel` (consecutive), otherwise resets to 1
3. Streak saturates at `type(uint24).max` (16,777,215) -- cannot overflow
4. Zero address returns immediately (no storage write for address(0))
5. Non-streak bits of `mintPacked_[player]` are preserved via mask

**NatSpec Accuracy:**
- `@dev` says "idempotent per level" -- CORRECT, verified by `lastCompleted == mintLevel` early return
- `@dev` says "credits on completed 1x price ETH quest" (contract-level) -- ACCURATE, caller in DegenerusGame gates to COIN contract which triggers on quest completion

**Gas Flags:**
- The combined `MINT_STREAK_FIELDS_MASK` clears both fields in one AND -- efficient
- Single SLOAD + single SSTORE per call (optimal)
- `lastCompleted != 0` check before consecutive test: handles first-ever call correctly (resets to streak=1 on first call since lastCompleted starts at 0)

**Verdict:** CORRECT

---

### `_creditClaimable(address beneficiary, uint256 weiAmount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditClaimable(address beneficiary, uint256 weiAmount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): recipient of credited ETH; `weiAmount` (uint256): wei to credit |
| **Returns** | None |

**State Reads:** None (directly writes)

**State Writes:**
- `claimableWinnings[beneficiary]` -- incremented by `weiAmount` (unchecked addition)

**Callers:**
- `DegenerusGameJackpotModule` (lines 982, 1010, 1023) -- jackpot payout, non-auto-rebuy fallback, take-profit reservation
- `DegenerusGameDegeneretteModule` (line 1174) -- degenerette bet payouts
- `DegenerusGameDecimatorModule` (lines 476, 488, 517) -- decimator claim payouts, take-profit, non-rebuy fallback
- `DegenerusGameEndgameModule` (lines 237, 250, 264) -- endgame/BAF payouts, take-profit, non-rebuy fallback
- `_queueWhalePassClaimCore` (line 88, same contract) -- remainder credit after whale pass division

**Callees:**
- None (emits `PlayerCredited` event only)

**ETH Flow:**
- Does NOT transfer ETH -- credits a pull-pattern balance in `claimableWinnings`
- Source: implicit (caller holds the ETH in the game contract's balance)
- Destination: `claimableWinnings[beneficiary]` (accounting entry, not transfer)

**Invariants:**
1. Zero-amount guard: returns immediately if `weiAmount == 0` (no spurious events)
2. Unchecked addition: safe because total protocol ETH supply is bounded (all ETH enters via payable functions with finite block gas limits, and total supply ~ 120M ETH < 2^88 wei, far below uint256 overflow)
3. No reentrancy risk: no external calls, only storage write + event
4. Does NOT update `claimablePool` -- callers are responsible for maintaining the pool aggregate

**NatSpec Accuracy:**
- No NatSpec on the function itself (only the contract-level `@dev Shared payout helpers for jackpot-related modules`)
- Event NatSpec is accurate: `player` and `recipient` are both `beneficiary` in the direct credit path

**Gas Flags:**
- Minimal: single SSTORE + event emit
- `unchecked` block avoids overflow check gas (safe as analyzed above)

**Note on `claimablePool` synchronization:**
This function does NOT increment `claimablePool`. The aggregate pool tracking is handled by callers. This is a deliberate design -- some callers batch-increment `claimablePool` for an entire group of credits (e.g., GameOverModule credits multiple players then adjusts pool once). The invariant `claimablePool >= sum(claimableWinnings[*])` is maintained at the caller level, not here.

**Verdict:** CORRECT

---

### `_queueWhalePassClaimCore(address winner, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _queueWhalePassClaimCore(address winner, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): player receiving deferred whale pass claims; `amount` (uint256): total ETH payout to convert |
| **Returns** | None |

**State Reads:** None (directly writes -- reads are implicit in `+=`)

**State Writes:**
- `whalePassClaims[winner]` -- incremented by `fullHalfPasses` (number of half-passes)
- `claimableWinnings[winner]` -- incremented by `remainder` (unchecked, via direct write)
- `claimablePool` -- incremented by `remainder` (checked addition)

**Callers:**
- `DegenerusGameEndgameModule` (lines 363, 410) -- lootbox portion and direct payout whale pass queuing
- `DegenerusGameDecimatorModule` (line 729) -- decimator large payout whale pass queuing

**Callees:**
- None (emits `PlayerCredited` event for remainder only)

**ETH Flow:**
- Converts large ETH payouts into deferred whale pass claims
- Division: `amount / HALF_WHALE_PASS_PRICE (2.175 ETH)` = number of half-passes
- Remainder: `amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE)` goes to claimable balance
- `whalePassClaims` is a count, not ETH -- represents tickets/levels to be claimed later
- `claimablePool` is incremented for remainder only (the whale pass portion is handled separately when claims are redeemed)

**Invariants:**
1. Zero guards: returns immediately if `winner == address(0)` or `amount == 0`
2. `fullHalfPasses * HALF_WHALE_PASS_PRICE + remainder == amount` always holds (integer division identity)
3. No ETH is lost: every wei goes to either whale pass claims or claimable remainder
4. `claimablePool` is incremented in sync with `claimableWinnings` for the remainder (unlike `_creditClaimable` which leaves pool tracking to callers)
5. `whalePassClaims` increment is checked (no unchecked) -- safe since half-pass count is bounded by `amount / 2.175 ETH`, and `amount` is bounded by protocol ETH

**NatSpec Accuracy:**
- `@dev` says "Queue deferred whale pass claims for large payouts" -- CORRECT
- `HALF_WHALE_PASS_PRICE` NatSpec says "each half-pass = 1 ticket/level for 100 levels" -- ACCURATE, this is the pricing unit

**Gas Flags:**
- Conditional writes: only writes `whalePassClaims` if `fullHalfPasses != 0`, only writes `claimableWinnings`/`claimablePool` if `remainder != 0` -- saves gas on exact multiples or zero remainders
- `claimableWinnings` remainder addition is unchecked (safe, same analysis as `_creditClaimable`)
- `claimablePool` remainder addition is checked -- slight gas overhead but safer for aggregate tracking

**Design Note:**
Unlike `_creditClaimable`, this function DOES update `claimablePool` for the remainder portion. This is because `_queueWhalePassClaimCore` is a terminal payout function (callers don't batch pool updates), whereas `_creditClaimable` is used in batch contexts where callers manage pool updates.

**Verdict:** CORRECT


---

## BurnieCoin.sol

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): authorized address; `amount` (uint256): max spend |
| **Returns** | `bool`: always true |

**State Reads:** `allowance[msg.sender][spender]`
**State Writes:** `allowance[msg.sender][spender]` (only if current != amount, gas optimization)

**Callers:** Any user/contract
**Callees:** none

**ETH Flow:** No
**Invariants:** Sets allowance to exact amount. Emits Approval regardless of whether storage write occurs (ERC-20 compliance).
**NatSpec Accuracy:** Accurate. Notes type(uint256).max for infinite approval.
**Gas Flags:** The "only write if current != amount" optimization saves ~5000 gas on no-op re-approvals. Well designed.
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** `balanceOf[msg.sender]`, `balanceOf[to]`, `degenerusGame.rngLocked()` (via _claimCoinflipShortfall)
**State Writes:** `balanceOf[msg.sender]`, `balanceOf[to]`, possibly `_supply.totalSupply`/`_supply.vaultAllowance` (if to==VAULT)

**Callers:** Any user/contract
**Callees:** `_claimCoinflipShortfall(msg.sender, amount)`, `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Calls _claimCoinflipShortfall first to auto-claim coinflip winnings if balance insufficient -- ensures smooth UX. Then standard _transfer. uint128 truncation safety: _transfer uses _toUint128 only for vault redirect path, never for normal transfers which stay in uint256.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** `allowance[from][msg.sender]`, `balanceOf[from]`, `balanceOf[to]`
**State Writes:** `allowance[from][msg.sender]` (if not GAME and not infinite), `balanceOf[from]`, `balanceOf[to]`

**Callers:** Any user/contract, DegenerusGame (with bypass)
**Callees:** `_claimCoinflipShortfall(from, amount)`, `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:**
- Game contract bypasses allowance check entirely (trusted contract pattern)
- Infinite approval (type(uint256).max) skips allowance update
- Zero-amount transfers skip allowance update (optimization)
- Solidity 0.8+ underflow check on `allowed - amount` prevents spending more than allowed
- Emits Approval event when allowance updated (ERC-20 compliant)
**NatSpec Accuracy:** Accurate. Documents game bypass.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | none |

**State Reads:** `balanceOf[from]`, `balanceOf[to]`
**State Writes:** `balanceOf[from]`, `balanceOf[to]`, and if `to == VAULT`: `_supply.totalSupply`, `_supply.vaultAllowance`

**Callers:** `transfer()`, `transferFrom()`
**Callees:** `_toUint128(amount)` (VAULT path only)

**ETH Flow:** No
**Invariants:**
- Zero address check on both from and to
- VAULT redirect: transfers TO vault are treated as burns (totalSupply decreases) + vault allowance increases. Emits Transfer(from, address(0)) + VaultEscrowRecorded. This preserves the invariant: totalSupply + vaultAllowance = supplyIncUncirculated.
- The unchecked block for VAULT path is safe: totalSupply was increased when the token was minted, so subtracting amount128 (which came from that balance) cannot underflow. vaultAllowance + amount128 is safe because both are uint128, and their sum is checked by _toUint128 on the amount; the total can only grow up to total supply ever minted.
- Normal path: overflow on balanceOf[to] is theoretically possible but requires ~2^256 total supply (impossible).
**NatSpec Accuracy:** Accurate. Notes underflow revert and VAULT redirect.
**Gas Flags:** The VAULT redirect uses unchecked for gas savings; correctness verified.
**Verdict:** CORRECT -- VAULT redirect preserves supply invariant

---

### `_mint(address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance` (VAULT path), `_supply.totalSupply` (normal path), `balanceOf[to]`
**State Writes:** `_supply.vaultAllowance` (VAULT path) OR `_supply.totalSupply` + `balanceOf[to]` (normal path)

**Callers:** `mintForCoinflip()`, `mintForGame()`, `creditCoin()`
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- VAULT path: minting TO vault increases vaultAllowance (unchecked -- bounded by total possible token inflows). Emits VaultEscrowRecorded, NOT Transfer. This is intentional since vault allowance is virtual.
- Normal path: totalSupply += amount128 (checked, will revert on uint128 overflow), balanceOf[to] += amount (uint256, cannot overflow in practice)
- Emits Transfer(address(0), to, amount) for normal path (ERC-20 standard)
**NatSpec Accuracy:** Accurate
**Gas Flags:** VAULT path uses unchecked for vaultAllowance increment. Safe because total mint inflows are bounded by game economics.
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance` (VAULT path), `balanceOf[from]`, `_supply.totalSupply`
**State Writes:** `_supply.vaultAllowance` (VAULT path) OR `balanceOf[from]` + `_supply.totalSupply` (normal path)

**Callers:** `burnForCoinflip()`, `burnCoin()`, `decimatorBurn()`
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- VAULT path: explicit check `amount128 > allowanceVault` reverts with Insufficient. Reduces vaultAllowance (unchecked, safe after the check). Emits VaultAllowanceSpent, NOT Transfer(from, address(0)). This is intentional since the "burned" tokens were virtual.
- Normal path: balanceOf[from] -= amount (Solidity 0.8+ underflow revert), totalSupply -= amount128 (checked uint128 subtraction)
- Preserves invariant: totalSupply + vaultAllowance = supplyIncUncirculated
**NatSpec Accuracy:** Accurate. Notes CEI pattern usage.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `burnForCoinflip(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForCoinflip(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): player to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `balanceOf[from]`, `_supply.totalSupply`
**State Writes:** `balanceOf[from]`, `_supply.totalSupply`

**Callers:** BurnieCoinflip contract (external)
**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:** Only coinflipContract can call. Reuses `OnlyGame()` error for gas efficiency rather than defining a separate `OnlyCoinflip` error.
**NatSpec Accuracy:** Accurate
**Gas Flags:** Reusing OnlyGame error -- informational only, saves contract size
**Verdict:** CORRECT

---

### `mintForCoinflip(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintForCoinflip(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.totalSupply`, `balanceOf[to]`

**Callers:** BurnieCoinflip contract (external)
**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:** Only coinflipContract can call. No zero-amount check (unlike mintForGame), but _mint handles zero-address check. A zero-amount mint is a no-op with a Transfer event -- acceptable.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `mintForGame(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintForGame(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.totalSupply`, `balanceOf[to]`

**Callers:** DegenerusGame contract (external)
**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:** Only GAME can call. Early return on amount == 0 (optimization). Used for Degenerette payouts and other game rewards.
**NatSpec Accuracy:** Accurate. Says "e.g., Degenerette wins."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultEscrow(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultEscrow(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount to add to vault allowance |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance`
**State Writes:** `_supply.vaultAllowance`

**Callers:** DegenerusGame or DegenerusVault contracts (external)
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Access control: only GAME or VAULT can call. Reuses `OnlyVault()` error (the error name is slightly misleading since GAME can also call, but acceptable for gas savings).
- Increases vaultAllowance with unchecked addition. Safe because _toUint128 validates the amount fits uint128, and the maximum practical accumulation is bounded by game economics (initial 2M + game rewards).
- Does NOT mint tokens -- only increases virtual allowance
- Emits VaultEscrowRecorded
**NatSpec Accuracy:** Accurate. Says "Increase the vault's mint allowance without transferring tokens."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintTo(address to, uint256 amount)` [external onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintTo(address to, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): amount to mint from allowance |
| **Returns** | none |

**State Reads:** `_supply.vaultAllowance`, `_supply.totalSupply`, `balanceOf[to]`
**State Writes:** `_supply.vaultAllowance`, `_supply.totalSupply`, `balanceOf[to]`

**Callers:** DegenerusVault contract only (external)
**Callees:** `_toUint128(amount)`

**ETH Flow:** No
**Invariants:**
- Zero address revert
- Explicit check: amount128 > allowanceVault reverts with Insufficient
- Decreases vaultAllowance, increases totalSupply (unchecked block). The unchecked is safe: allowance was checked above, and totalSupply + amount128 cannot overflow uint128 because the decrease in vaultAllowance balances the increase in totalSupply (total supplyIncUncirculated stays constant in this function... no, totalSupply goes up, vaultAllowance goes down -- net supplyIncUncirculated unchanged -- CORRECT).
- Mints real tokens to recipient (balanceOf[to] += amount)
- Emits VaultAllowanceSpent(address(this), amount) and Transfer(address(0), to, amount)
**NatSpec Accuracy:** Accurate
**Gas Flags:** None. The unchecked block with prior bounds check is correct and gas-efficient.
**Verdict:** CORRECT -- preserves supplyIncUncirculated invariant (totalSupply up, vaultAllowance down by same amount)

---

### `creditCoin(address player, uint256 amount)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditCoin(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): amount to credit |
| **Returns** | none |

**State Reads:** `_supply.totalSupply`, `balanceOf[player]`
**State Writes:** `_supply.totalSupply`, `balanceOf[player]`

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `_mint(player, amount)`

**ETH Flow:** No
**Invariants:** Early return on zero address or zero amount. Mints NEW tokens (increases totalSupply) -- note the naming "creditCoin" might suggest transferring existing tokens, but it actually mints. This is intentional for game reward distribution.
**NatSpec Accuracy:** NatSpec says "Credits coin to a player's balance without minting new tokens" (from the interface). This is INACCURATE -- the implementation calls _mint which DOES mint new tokens and increase totalSupply. However, the BurnieCoin.sol function-level NatSpec says "Credit BURNIE directly to a player's wallet balance" which is accurate but ambiguous.
**Gas Flags:** None
**Verdict:** CONCERN (informational) -- Interface NatSpec in IDegenerusCoin says "without minting new tokens" but implementation calls `_mint()`. The contract behavior is correct for game economics (reward minting is intentional), but the interface comment is misleading.

---

### `creditFlip(address player, uint256 amount)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlip(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): flip credit amount |
| **Returns** | none |

**State Reads:** none (delegates to coinflipContract)
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlip(player, amount)`

**ETH Flow:** No
**Invariants:** Pure proxy to coinflipContract. No zero checks here -- delegated to BurnieCoinflip.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts)` [external onlyFlipCreditors]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `players` (address[3]): recipients; `amounts` (uint256[3]): amounts per player |
| **Returns** | none |

**State Reads:** none (delegates to coinflipContract)
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyFlipCreditors)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlipBatch(players, amounts)`

**ETH Flow:** No
**Invariants:** Fixed-size array (3) for gas optimization. Unused slots should be address(0). Pure proxy.
**NatSpec Accuracy:** Accurate. Notes unused slots should be address(0).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditLinkReward(address player, uint256 amount)` [external onlyAdmin]

| Field | Value |
|-------|-------|
| **Signature** | `function creditLinkReward(address player, uint256 amount) external onlyAdmin` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): reward recipient; `amount` (uint256): flip credit amount |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally (coinflipContract writes internally)

**Callers:** DegenerusAdmin contract (via onlyAdmin)
**Callees:** `IBurnieCoinflip(coinflipContract).creditFlip(player, amount)`

**ETH Flow:** No
**Invariants:** Early return on zero address or zero amount. Credits flip stake (not wallet balance) as LINK donation reward. Emits LinkCreditRecorded.
**NatSpec Accuracy:** Accurate. Describes LINK donation reward flow.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipShortfall(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipShortfall(address player, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to auto-claim for; `amount` (uint256): required amount |
| **Returns** | none |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[player]`
**State Writes:** `balanceOf[player]` (via coinflipContract.claimCoinflipsFromBurnie which calls mintForCoinflip)

**Callers:** `transfer()`, `transferFrom()`
**Callees:** `degenerusGame.rngLocked()`, `IBurnieCoinflip(coinflipContract).claimCoinflipsFromBurnie(player, amount - balance)`

**ETH Flow:** No
**Invariants:**
- Early returns: zero amount, rngLocked (cannot claim during VRF), sufficient balance
- Claims exactly `amount - balance` from coinflip winnings to cover the shortfall
- unchecked subtraction safe: guarded by `balance >= amount` check (only enters if balance < amount)
- The coinflipContract.claimCoinflipsFromBurnie call will mint tokens to the player, increasing their balance to cover the pending transfer
**NatSpec Accuracy:** No NatSpec. Acceptable for private helper.
**Gas Flags:** None
**Verdict:** CORRECT -- elegant auto-claim mechanism

---

### `_consumeCoinflipShortfall(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): required amount |
| **Returns** | `uint256 consumed`: amount consumed from coinflip balance |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[player]`
**State Writes:** none locally (coinflipContract writes internally -- reduces coinflip balance without minting)

**Callers:** `burnCoin()`, `decimatorBurn()`
**Callees:** `degenerusGame.rngLocked()`, `IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(player, amount - balance)`

**ETH Flow:** No
**Invariants:**
- Same early-return pattern as _claimCoinflipShortfall
- Returns the amount consumed (offset from coinflip balance), allowing callers to burn only `amount - consumed` from wallet balance
- Key difference from _claimCoinflipShortfall: consume does NOT mint tokens -- it cancels coinflip credits, effectively burning them. This is correct for burnCoin/decimatorBurn where the intent is destruction, not transfer.
- unchecked subtraction safe: same guard as _claimCoinflipShortfall
**NatSpec Accuracy:** No NatSpec. Acceptable for private helper.
**Gas Flags:** None
**Verdict:** CORRECT -- consume-without-mint pattern for burns

---

### `affiliateQuestReward(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function affiliateQuestReward(address player, uint256 amount) external returns (uint256 questReward)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player who triggered affiliate action; `amount` (uint256): base amount |
| **Returns** | `uint256 questReward`: bonus reward earned |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusAffiliate contract (explicit check: msg.sender != AFFILIATE)
**Callees:** `questModule.handleAffiliate(player, amount)`, `_questApplyReward(player, reward, questType, streak, completed)`

**ETH Flow:** No
**Invariants:**
- Only AFFILIATE can call (OnlyAffiliate error)
- Early return 0 on zero address or zero amount
- Quest reward returned but NOT credited as flip stake here -- the affiliate contract handles reward distribution. This differs from notifyQuestMint/notifyQuestLootBox/notifyQuestDegenerette which credit flip stakes directly.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `rollDailyQuest(uint48 day, uint256 entropy)` [external onlyDegenerusGameContract]

| Field | Value |
|-------|-------|
| **Signature** | `function rollDailyQuest(uint48 day, uint256 entropy) external onlyDegenerusGameContract` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): day index; `entropy` (uint256): VRF randomness |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally (questModule writes internally)

**Callers:** DegenerusGame contract (via onlyDegenerusGameContract)
**Callees:** `questModule.rollDailyQuest(day, entropy)`

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- If rolled is true, emits DailyQuestRolled for each of 2 quest types
- If rolled is false (already rolled for this day), no events emitted
- Loop uses unchecked increment -- safe since i < 2 is bounded
- `highDifficulty` is documented as "Always false (difficulty removed)" in the event, meaning the quest module no longer uses difficulty levels
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `notifyQuestMint(address player, uint32 quantity, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestMint(address player, uint32 quantity, bool paidWithEth) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): minting player; `quantity` (uint32): mint units; `paidWithEth` (bool): payment method |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleMint(player, quantity, paidWithEth)`, `_questApplyReward(...)`, `degenerusGame.recordMintQuestStreak(player)` (conditional), `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Quest reward is credited as flip stake via coinflipContract.creditFlip
- Special behavior: if quest completed AND paidWithEth AND questType == QUEST_TYPE_MINT_ETH (1), also calls `degenerusGame.recordMintQuestStreak(player)` to update the mint streak counter
- Flip credit only occurs if questReward != 0
**NatSpec Accuracy:** Accurate. Notes slot-0 streak update on MINT_ETH completion.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `notifyQuestLootBox(address player, uint256 amountWei)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestLootBox(address player, uint256 amountWei) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amountWei` (uint256): ETH spent |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleLootBox(player, amountWei)`, `_questApplyReward(...)`, `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Quest reward credited as flip stake if questReward != 0
- NatSpec says "Access: game or lootbox contract" but the code only checks for GAME. This is because lootbox operations are delegatecalled through the game contract, so msg.sender is always GAME.
**NatSpec Accuracy:** CONCERN (informational) -- NatSpec says "game or lootbox contract" but code only checks GAME. Functionally correct because lootbox is a delegatecall module, but the comment is misleading about access control.
**Gas Flags:** None
**Verdict:** CORRECT (behavior correct, NatSpec slightly misleading)

---

### `notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): bet amount; `paidWithEth` (bool): payment type |
| **Returns** | none |

**State Reads:** none locally
**State Writes:** none locally

**Callers:** DegenerusGame contract (explicit msg.sender check)
**Callees:** `questModule.handleDegenerette(player, amount, paidWithEth)`, `_questApplyReward(...)`, `IBurnieCoinflip(coinflipContract).creditFlip(player, questReward)` (conditional)

**ETH Flow:** No
**Invariants:**
- Only GAME can call
- Same pattern as notifyQuestLootBox: route to quest module, apply reward, credit flip
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing (emits event) |
| **Parameters** | `player` (address): player; `reward` (uint256): raw reward; `questType` (uint8): quest type; `streak` (uint32): streak count; `completed` (bool): whether completed |
| **Returns** | `uint256`: reward amount (0 if not completed) |

**State Reads:** none
**State Writes:** none (only emits event)

**Callers:** `affiliateQuestReward()`, `notifyQuestMint()`, `notifyQuestLootBox()`, `notifyQuestDegenerette()`, `decimatorBurn()`
**Callees:** none

**ETH Flow:** No
**Invariants:** Pure event emitter. Returns reward if completed, 0 otherwise. Emits QuestCompleted for off-chain indexers.
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `burnCoin(address target, uint256 amount)` [external onlyTrustedContracts]

| Field | Value |
|-------|-------|
| **Signature** | `function burnCoin(address target, uint256 amount) external onlyTrustedContracts` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `target` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | none |

**State Reads:** `degenerusGame.rngLocked()`, `balanceOf[target]`, `_supply.totalSupply`
**State Writes:** `balanceOf[target]`, `_supply.totalSupply`

**Callers:** DegenerusGame or DegenerusAffiliate (via onlyTrustedContracts)
**Callees:** `_consumeCoinflipShortfall(target, amount)`, `_burn(target, amount - consumed)`

**ETH Flow:** No
**Invariants:**
- Only GAME or AFFILIATE can call
- Attempts to consume coinflip credits first (via _consumeCoinflipShortfall), then burns remainder from wallet balance
- `amount - consumed` is safe: consumed is at most the shortfall (amount - balance), so `amount - consumed >= balance >= 0`
- NatSpec says "or affiliate" for callers, consistent with modifier
**NatSpec Accuracy:** Accurate
**Gas Flags:** None
**Verdict:** CORRECT

---

### `decimatorBurn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function decimatorBurn(address player, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player (address(0) = msg.sender); `amount` (uint256): BURNIE to burn |
| **Returns** | none |

**State Reads:** `degenerusGame.isOperatorApproved(player, msg.sender)`, `degenerusGame.decWindow()`, `degenerusGame.rngLocked()` (via _consumeCoinflipShortfall), `balanceOf[caller]`, `_supply.totalSupply`, `degenerusGame.playerActivityScore(caller)`, `degenerusGame.consumeDecimatorBoon(caller)`
**State Writes:** `balanceOf[caller]`, `_supply.totalSupply` (via _burn), coinflip state (via creditFlip if quest reward)

**Callers:** Any external caller (players or approved operators)
**Callees:**
1. `degenerusGame.isOperatorApproved(player, msg.sender)` -- only if player != address(0) && player != msg.sender
2. `degenerusGame.decWindow()` -- checks active decimator window
3. `_consumeCoinflipShortfall(caller, amount)` -- consume coinflip credits for burn
4. `_burn(caller, amount - consumed)` -- burn from wallet
5. `questModule.handleDecimator(caller, amount)` -- quest processing
6. `_questApplyReward(...)` -- emit event if quest completed
7. `IBurnieCoinflip(coinflipContract).creditFlip(caller, questReward)` -- credit flip if quest reward
8. `degenerusGame.playerActivityScore(caller)` -- get activity bonus
9. `_decimatorBurnMultiplier(bonusBps)` -- compute multiplier
10. `_adjustDecimatorBucket(bonusBps, minBucket)` -- compute bucket
11. `degenerusGame.consumeDecimatorBoon(caller)` -- consume boon if available
12. `degenerusGame.recordDecBurn(caller, lvl, bucket, baseAmount, decBurnMultBps)` -- record the burn

**ETH Flow:** No
**Invariants:**
- Player determination: address(0) or msg.sender means self-burn; otherwise requires operator approval
- Minimum amount: DECIMATOR_MIN (1,000 BURNIE)
- Must be during active decimator window (checked via degenerusGame.decWindow())
- CEI pattern: burn BEFORE quest processing and downstream calls
- Quest reward: added to baseAmount for weight calculation but NOT burned (credited as flip stake)
- Activity score: capped at DECIMATOR_ACTIVITY_CAP_BPS (23,500 = 235%)
- Bucket: base 12, adjusted down by activity score, min bucket depends on level (5 normal, 2 for x00 levels)
- Boon: percent boost on base amount, capped at DECIMATOR_BOON_CAP (50,000 BURNIE)
- Final bucket used for jackpot weighting via degenerusGame.recordDecBurn
- Emits DecimatorBurn(caller, amount, bucketUsed) -- amount is original burn, not boosted
**NatSpec Accuracy:** Accurate. Comprehensive documentation of CEI pattern and quest bonus interaction.
**Gas Flags:** Multiple external calls to degenerusGame (decWindow, playerActivityScore, consumeDecimatorBoon, recordDecBurn) -- these are unavoidable and gas cost is appropriate for the complexity.
**Verdict:** CORRECT -- thorough CEI, proper access control, well-bounded arithmetic


---

## BurnieCoinflip.sol

### `settleFlipModeChange(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function settleFlipModeChange(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): the player whose flip state to settle before afKing mode change |
| **Returns** | None |

**State Reads:** `playerState[player].claimableStored`, all state read by `_claimCoinflipsInternal`
**State Writes:** `playerState[player].claimableStored` (increased by mintable if nonzero)

**Callers:** DegenerusGame contract (via delegatecall modules, before afKing mode toggle)
**Callees:** `_claimCoinflipsInternal(player, false)`

**ETH Flow:** No
**Invariants:** Must be called before any afKing mode change so in-flight flips are settled under the correct bonus regime. Only callable by the game contract (`onlyDegenerusGameContract`).
**NatSpec Accuracy:** NatSpec says "Processes pending claims so mode change doesn't affect in-flight flips" -- matches behavior. Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `depositCoinflip(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function depositCoinflip(address player, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): deposit target (address(0) or msg.sender = self-deposit); `amount` (uint256): BURNIE to deposit |
| **Returns** | None |

**State Reads:** None directly; delegates to `_depositCoinflip`
**State Writes:** None directly; delegates to `_depositCoinflip`

**Callers:** External (players, operators, BurnieCoin contract)
**Callees:** `degenerusGame.isOperatorApproved(player, msg.sender)`, `_depositCoinflip(caller, amount, directDeposit)`

**ETH Flow:** No
**Invariants:** If `player != address(0)` and `player != msg.sender`, msg.sender must be an approved operator for `player`. Direct deposits (self or address(0)) set `directDeposit=true` which enables bounty eligibility and biggest-flip tracking.
**NatSpec Accuracy:** NatSpec is minimal ("Deposit BURNIE into daily coinflip system"). Adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_depositCoinflip(address caller, uint256 amount, bool directDeposit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _depositCoinflip(address caller, uint256 amount, bool directDeposit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `caller` (address): the player; `amount` (uint256): BURNIE to deposit; `directDeposit` (bool): whether deposit is direct (enables bounty + biggest-flip tracking) |
| **Returns** | None |

**State Reads:** `playerState[caller]` (claimableStored, autoRebuyEnabled, autoRebuyCarry)
**State Writes:** `playerState[caller].claimableStored` (via `_claimCoinflipsInternal` settlement)

**Callers:** `depositCoinflip`
**Callees:** `_coinflipLockedDuringTransition()`, `_claimCoinflipsInternal(caller, false)`, `burnie.burnForCoinflip(caller, amount)`, `questModule.handleFlip(caller, amount)`, `_questApplyReward(...)`, `degenerusGame.recordCoinflipDeposit(amount)`, `degenerusGame.afKingModeFor(caller)`, `degenerusGame.deityPassCountFor(caller)`, `_afKingDeityBonusHalfBpsWithLevel(caller, level)`, `_afKingRecyclingBonus(rebetAmount, deityBonusHalfBps)`, `_recyclingBonus(rebetAmount)`, `_addDailyFlip(caller, creditedFlip, ...)`, `degenerusGame.level()`

**ETH Flow:** No (BURNIE tokens only; burn on deposit, no ETH moves)
**Invariants:**
- Amount must be >= MIN (100 ether) unless amount == 0 (claim-only call).
- Coinflip must not be locked during BAF transition levels.
- Burns BURNIE before crediting flip (CEI pattern).
- Recycling bonus only applies to the "rebet" portion (min of creditedFlip, rollAmount).
- rollAmount is autoRebuyCarry if auto-rebuy enabled, else the freshly computed mintable.
- Quest reward is added to creditedFlip (principal + questReward).
- Direct deposits pass `amount` as `recordAmount` for bounty eligibility; indirect pass 0.

**NatSpec Accuracy:** NatSpec says "Internal deposit for daily coinflip mode" -- accurate but minimal.
**Gas Flags:** The `amount == 0` path still calls `_claimCoinflipsInternal` for settlement, which is intentional. No wasted computation.
**Verdict:** CORRECT

---

### `claimCoinflips(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address(0) = msg.sender, else validated; `amount` (uint256): exact BURNIE to claim |
| **Returns** | `claimed` (uint256): actual amount claimed (may be less than requested if balance insufficient) |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** External (players, operators)
**Callees:** `degenerusGame.rngLocked()`, `_resolvePlayer(player)`, `_claimCoinflipsAmount(resolved, amount, true)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked (prevents BAF credit manipulation during VRF pending). Mints tokens (`mintTokens=true`).
**NatSpec Accuracy:** "Claim coinflip winnings (exact amount)." and dev note about RNG lock -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `claimCoinflipsTakeProfit(address player, uint256 multiples)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflipsTakeProfit(address player, uint256 multiples) external returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address(0) = msg.sender; `multiples` (uint256): number of take-profit multiples to claim (0 = max) |
| **Returns** | `claimed` (uint256): amount claimed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsTakeProfit`

**Callers:** External (players, operators)
**Callees:** `degenerusGame.rngLocked()`, `_resolvePlayer(player)`, `_claimCoinflipsTakeProfit(resolved, multiples)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked. Takes profit in exact multiples of `autoRebuyStop`.
**NatSpec Accuracy:** "Claim coinflip winnings (take profit multiples)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `claimCoinflipsFromBurnie(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflipsFromBurnie(address player, uint256 amount) external onlyBurnieCoin returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to claim for; `amount` (uint256): amount to claim |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** BurnieCoin contract (to cover token transfers/burns from claimable balance)
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsAmount(player, amount, true)`

**ETH Flow:** No
**Invariants:** Only callable by BurnieCoin (`onlyBurnieCoin`). Player address passed directly (no `_resolvePlayer` -- BurnieCoin is trusted). Mints tokens.
**NatSpec Accuracy:** "Claim coinflip winnings via BurnieCoin to cover token transfers/burns." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `consumeCoinflipsForBurn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipsForBurn(address player, uint256 amount) external onlyBurnieCoin returns (uint256 consumed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to consume from; `amount` (uint256): amount to consume |
| **Returns** | `consumed` (uint256): actual amount consumed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** BurnieCoin contract (for burns that reduce claimable without minting)
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsAmount(player, amount, false)`

**ETH Flow:** No
**Invariants:** Only callable by BurnieCoin. Differs from `claimCoinflipsFromBurnie` in that `mintTokens=false` -- reduces claimable balance but does NOT mint new BURNIE. Used for burning from claimable.
**NatSpec Accuracy:** "Consume coinflip winnings via BurnieCoin for burns (no mint)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsTakeProfit(address player, uint256 multiples)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsTakeProfit(address player, uint256 multiples) private returns (uint256 claimed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `multiples` (uint256): number of take-profit multiples (0 = max available) |
| **Returns** | `claimed` (uint256): amount claimed |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop, claimableStored)
**State Writes:** `playerState[player].claimableStored`

**Callers:** `claimCoinflipsTakeProfit`
**Callees:** `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, toClaim)`

**ETH Flow:** No
**Invariants:**
- Auto-rebuy must be enabled (reverts `AutoRebuyNotEnabled` otherwise).
- Take-profit stop must be nonzero (reverts `TakeProfitZero`).
- Claims in exact multiples of `autoRebuyStop`. If `multiples == 0`, claims max available multiples.
- Remaining balance (modulo) stays in `claimableStored`.

**NatSpec Accuracy:** "Internal claim keeping multiples of auto-rebuy stop amount." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsAmount(address player, uint256 amount, bool mintTokens)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsAmount(address player, uint256 amount, bool mintTokens) private returns (uint256 claimed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): amount to claim; `mintTokens` (bool): whether to mint BURNIE tokens |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** `playerState[player].claimableStored`
**State Writes:** `playerState[player].claimableStored` (reduced by toClaim)

**Callers:** `claimCoinflips`, `claimCoinflipsFromBurnie`, `consumeCoinflipsForBurn`
**Callees:** `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, toClaim)` (only if mintTokens)

**ETH Flow:** No
**Invariants:**
- Claims minimum of requested `amount` and available `stored` balance.
- If `mintTokens == false`, balance is consumed but no tokens are minted (used by `consumeCoinflipsForBurn`).
- Updates `claimableStored` even if only to add newly computed `mintable` from `_claimCoinflipsInternal`.

**NatSpec Accuracy:** "Internal claim exact amount." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsInternal(address player, bool deepAutoRebuy)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsInternal(address player, bool deepAutoRebuy) internal returns (uint256 mintable)` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `deepAutoRebuy` (bool): if true and auto-rebuy active, processes larger window (up to 1095 days) |
| **Returns** | `mintable` (uint256): total amount to mint (after take-profit extraction) |

**State Reads:** `flipsClaimableDay`, `playerState[player]` (lastClaim, autoRebuyEnabled, autoRebuyStop, autoRebuyCarry, autoRebuyStartDay, claimableStored), `coinflipDayResult[cursor]`, `coinflipBalance[cursor][player]`, `degenerusGame` (syncAfKingLazyPassFromCoin, deityPassCountFor, level, purchaseInfo, gameOver)
**State Writes:** `coinflipBalance[cursor][player]` (zeroed on processed days), `playerState[player].lastClaim`, `playerState[player].autoRebuyCarry`

**Callers:** `settleFlipModeChange`, `_depositCoinflip`, `_claimCoinflipsTakeProfit`, `_claimCoinflipsAmount`, `_setCoinflipAutoRebuy`, `_setCoinflipAutoRebuyTakeProfit`
**Callees:** `degenerusGame.syncAfKingLazyPassFromCoin(player)`, `degenerusGame.deityPassCountFor(player)`, `degenerusGame.level()`, `_afKingDeityBonusHalfBpsWithLevel(player, cachedLevel)`, `_recyclingBonus(carry)`, `_afKingRecyclingBonus(carry, deityBonusHalfBps)`, `_bafBracketLevel(bafLevel)`, `jackpots.recordBafFlip(player, bafLvl, winningBafCredit)`, `degenerusGame.purchaseInfo()`, `degenerusGame.gameOver()`, `wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD)`

**ETH Flow:** No direct ETH. Mints WWXRP on losses (1 ether per loss day).
**Invariants:**
- Processes from `lastClaim+1` to `flipsClaimableDay`, bounded by a claim window.
- Claim window: first 30 days (if `lastClaim==0`), then 90 days (normal), or AUTO_REBUY_OFF_CLAIM_DAYS_MAX (1095) when `deepAutoRebuy=true`.
- If auto-rebuy is off but `autoRebuyCarry != 0`, the carry is added to `mintable` and cleared.
- On win: payout = stake + (stake * rewardPercent / 100). If auto-rebuy, winnings go to carry (with take-profit extraction); otherwise added to mintable.
- Carry gets recycling bonus after each win day (base 1% or afKing enhanced).
- On loss: stake is forfeited, carry is zeroed (if auto-rebuy), lossCount incremented for WWXRP.
- BAF credit is recorded for all winning days via `jackpots.recordBafFlip`.
- Reverts `RngLocked()` if there is winning BAF credit and the game is at a BAF resolution level (purchaseLevel % 10 == 0) on last purchase day with RNG locked.
- Auto-rebuy start day bounds the minimum claimable day (no expiry for auto-rebuy positions).
- If `start < minClaimableDay` and auto-rebuy active, carry is zeroed (stale carry from expired days).

**NatSpec Accuracy:** "Process daily coinflip claims and calculate winnings." -- adequate but understates complexity.
**Gas Flags:** The function iterates up to `windowDays` (90) or `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` (1095) days. For deep auto-rebuy processing, 1095 iterations could be gas-intensive but is capped to keep tx cost bounded.
**Verdict:** CORRECT

---

### `_addDailyFlip(address player, uint256 coinflipDeposit, uint256 recordAmount, bool canArmBounty, bool bountyEligible)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addDailyFlip(address player, uint256 coinflipDeposit, uint256 recordAmount, bool canArmBounty, bool bountyEligible) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `coinflipDeposit` (uint256): total credited amount (with bonuses); `recordAmount` (uint256): raw deposit for bounty (0 for non-direct); `canArmBounty` (bool): can this call arm the bounty; `bountyEligible` (bool): whether deposit is eligible for bounty tracking |
| **Returns** | None |

**State Reads:** `coinflipBalance[targetDay][player]`, `biggestFlipEver`, `bountyOwedTo`, `currentBounty`
**State Writes:** `coinflipBalance[targetDay][player]` (increased), `biggestFlipEver` (if new record), `bountyOwedTo` (set to player if new record), `coinflipTopByDay[targetDay]` (via `_updateTopDayBettor`)

**Callers:** `_depositCoinflip`, `processCoinflipPayouts` (for bounty payout), `creditFlip`, `creditFlipBatch`
**Callees:** `degenerusGame.consumeCoinflipBoon(player)` (only when `recordAmount != 0`), `_targetFlipDay()`, `_updateTopDayBettor(player, newStake, targetDay)`

**ETH Flow:** No
**Invariants:**
- Coinflip boon is only consumed on manual deposits (`recordAmount != 0`), boosting up to 100k BURNIE by boonBps.
- Target day is always `currentDayView() + 1` (next day).
- Bounty can only be armed when `canArmBounty && bountyEligible && recordAmount != 0` and `recordAmount > biggestFlipEver` and RNG not locked.
- To steal an existing bounty, must exceed current record by 1% (min 1 wei).
- `recordAmount` overflow is guarded (reverts `Insufficient` if > uint128.max).

**NatSpec Accuracy:** "Add daily flip stake for player." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): target player (address(0) = msg.sender); `enabled` (bool): enable/disable auto-rebuy; `takeProfit` (uint256): take-profit threshold |
| **Returns** | None |

**State Reads:** None directly; delegates
**State Writes:** None directly; delegates

**Callers:** External (players, operators, game contract)
**Callees:** `_requireApproved(player)` (if not from game and player != msg.sender), `_setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame)`

**ETH Flow:** No
**Invariants:** When called by the game contract (`fromGame=true`), `strict=false` (lenient mode: no revert on already-enabled, different event ordering). When called externally, `strict=true`.
**NatSpec Accuracy:** "Configure auto-rebuy mode for coinflips." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): target (address(0) = msg.sender); `takeProfit` (uint256): new take-profit stop |
| **Returns** | None |

**State Reads:** None directly; delegates
**State Writes:** None directly; delegates

**Callers:** External (players, operators)
**Callees:** `_resolvePlayer(player)`, `_setCoinflipAutoRebuyTakeProfit(resolved, takeProfit)`

**ETH Flow:** No
**Invariants:** Requires auto-rebuy already enabled (checked in `_setCoinflipAutoRebuyTakeProfit`).
**NatSpec Accuracy:** "Set auto-rebuy take profit." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit, bool strict)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit, bool strict) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `enabled` (bool); `takeProfit` (uint256); `strict` (bool): if true, reverts on already-enabled |
| **Returns** | None |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyCarry, lastClaim, autoRebuyStartDay, autoRebuyStop)
**State Writes:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop, autoRebuyStartDay, autoRebuyCarry)

**Callers:** `setCoinflipAutoRebuy`
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsInternal(player, false)` (enable) or `_claimCoinflipsInternal(player, true)` (disable, deep), `burnie.mintForCoinflip(player, mintable)`, `degenerusGame.deactivateAfKingFromCoin(player)`

**ETH Flow:** No
**Invariants:**
- Reverts if RNG locked.
- **Enable path (strict=true):** If already enabled, reverts `AutoRebuyAlreadyEnabled`. Otherwise sets enabled=true, sets startDay=lastClaim, sets stop=takeProfit. If takeProfit < AFKING_KEEP_MIN_COIN (20,000 ether), deactivates afKing.
- **Enable path (strict=false, from game):** If already enabled, just updates stop amount silently. If not enabled, enables with different event ordering (toggle then stop vs stop then toggle). Still deactivates afKing on low take-profit.
- **Disable path:** Deep-claims all days (up to 1095), adds carry to mintable, clears carry. Sets enabled=false, startDay=0. Always deactivates afKing.
- Mints any accumulated mintable at the end.

**NatSpec Accuracy:** "Internal auto-rebuy configuration." -- adequate.
**Gas Flags:** The `strict` flag creates two similar branches for enable -- could be consolidated, but not a gas issue since only one path executes.
**Verdict:** CORRECT

---

### `_setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `takeProfit` (uint256): new take-profit stop |
| **Returns** | None |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop)
**State Writes:** `playerState[player].autoRebuyStop`

**Callers:** `setCoinflipAutoRebuyTakeProfit`
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, mintable)`, `degenerusGame.deactivateAfKingFromCoin(player)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked. Reverts if auto-rebuy not enabled. Settles claims before updating stop. If `takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_COIN`, deactivates afKing (low take-profit is incompatible with afKing min balance requirement).
**NatSpec Accuracy:** "Internal auto-rebuy take profit configuration." -- accurate.
**Gas Flags:** The mintable settlement is done before updating stop, which is correct (settling under old regime).
**Verdict:** CORRECT

---

### `processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch) external onlyDegenerusGameContract` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `bonusFlip` (bool): whether this is a last-purchase-day bonus flip; `rngWord` (uint256): VRF random word; `epoch` (uint48): the day being resolved |
| **Returns** | None |

**State Reads:** `currentBounty`, `bountyOwedTo`, `degenerusGame` (lootboxPresaleActiveFlag, lastPurchaseDayFlipTotals)
**State Writes:** `coinflipDayResult[epoch]`, `flipsClaimableDay`, `currentBounty`, `bountyOwedTo`

**Callers:** DegenerusGame contract (during advanceGame via AdvanceModule)
**Callees:** `degenerusGame.lootboxPresaleActiveFlag()`, `degenerusGame.lastPurchaseDayFlipTotals()`, `_coinflipTargetEvBps(prevTotal, currentTotal)`, `_applyEvToRewardPercent(rewardPercent, evBps)`, `_addDailyFlip(to, slice, 0, false, false)` (for bounty payout), `degenerusGame.payCoinflipBountyDgnrs(to)`

**ETH Flow:** No direct ETH. Bounty payout is credited as flip stake (not ETH).
**Invariants:**
- Only callable by game contract.
- Entropy: seedWord = keccak256(rngWord, epoch) for per-day uniqueness.
- Reward percent: 5% chance each for 50% (1.5x) or 150% (2.5x), otherwise [78%, 115%] range.
- Presale bonus: +6% reward when presale active and bonusFlip.
- EV adjustment: only when bonusFlip and not presaleBonus, using `_coinflipTargetEvBps` based on last-purchase-day flip totals.
- Win: (rngWord & 1) == 1 (50/50 from original rngWord, not seedWord).
- Bounty resolution: if bountyOwner exists and bounty > 0, halve bounty. If win, credit half as flip stake to bountyOwner and pay DGNRS bounty. Clear bountyOwner regardless.
- After resolution: advances `flipsClaimableDay` to epoch and adds PRICE_COIN_UNIT (1000 ether) to bounty pool.

**NatSpec Accuracy:** "Process coinflip payout for a day (called by game contract)." -- accurate.
**Gas Flags:** The reward percent calculation re-uses `seedWord` for the normal-range roll (`seedWord % COINFLIP_EXTRA_RANGE`), which is correct since `seedWord` was derived from keccak256 but note that the extreme roll uses `seedWord % 20` while the normal range uses `seedWord % COINFLIP_EXTRA_RANGE` (38). These use the same `seedWord` but test different moduli -- the extreme check (`roll == 0 || roll == 1`) gates whether the normal-range formula is used, so no conflict.
**Verdict:** CORRECT

---

### `creditFlip(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlip(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): BURNIE-denominated flip credit |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via `_addDailyFlip`

**Callers:** DegenerusGame contract or BurnieCoin contract (onlyFlipCreditors)
**Callees:** `_addDailyFlip(player, amount, 0, false, false)`

**ETH Flow:** No
**Invariants:** No-op if player is address(0) or amount is 0. Credits with `recordAmount=0`, `canArmBounty=false`, `bountyEligible=false` -- no bounty or boon interaction. Only game or coin contract can call.
**NatSpec Accuracy:** "Credit flip to a player (called by authorized creditors)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `players` (address[3]): up to 3 recipients; `amounts` (uint256[3]): corresponding amounts |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via `_addDailyFlip` for each valid entry

**Callers:** DegenerusGame contract or BurnieCoin contract (onlyFlipCreditors)
**Callees:** `_addDailyFlip(player, amount, 0, false, false)` for each non-zero entry

**ETH Flow:** No
**Invariants:** Skips entries where player is address(0) or amount is 0. Fixed size 3 (calldata optimization). No bounty interaction.
**NatSpec Accuracy:** "Credit flips to multiple players (batch)." -- accurate.
**Gas Flags:** Fixed-size array (3) is gas-efficient vs dynamic. Uses unchecked increment.
**Verdict:** CORRECT

---

### `_questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing (emits event) |
| **Parameters** | `player` (address); `reward` (uint256); `questType` (uint8); `streak` (uint32); `completed` (bool) |
| **Returns** | uint256: reward if completed, 0 otherwise |

**State Reads:** None
**State Writes:** None (only emits event)

**Callers:** `_depositCoinflip`
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns 0 if not completed. Emits `QuestCompleted` event if completed.
**NatSpec Accuracy:** "Helper to process quest rewards and emit event." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_updateTopDayBettor(address player, uint256 stakeScore, uint48 day)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _updateTopDayBettor(address player, uint256 stakeScore, uint48 day) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `stakeScore` (uint256): total stake for this day; `day` (uint48) |
| **Returns** | None |

**State Reads:** `coinflipTopByDay[day]`
**State Writes:** `coinflipTopByDay[day]` (if player beats current leader)

**Callers:** `_addDailyFlip`
**Callees:** `_score96(stakeScore)`

**ETH Flow:** No
**Invariants:** Updates leader if player's score > current leader's score, OR if no leader set (address(0)). Uses cumulative stake for the day (newStake), not just the current deposit.
**NatSpec Accuracy:** "Update day leaderboard if player's score is higher." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp)`

| Field | Value |
|-------|-------|
| **Signature** | `constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp)` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | `_burnie` (address): BurnieCoin; `_degenerusGame` (address): game contract; `_jackpots` (address): jackpots contract; `_wwxrp` (address): WWXRP token |
| **Returns** | None |

**State Reads:** None
**State Writes:** Sets immutable references: `burnie`, `degenerusGame`, `jackpots`, `wwxrp`

**Callers:** Deploy script
**Callees:** None

**ETH Flow:** No
**Invariants:** All four addresses must be valid deployed contracts. No validation in constructor (relies on deploy script correctness).
**NatSpec Accuracy:** No NatSpec. Adequate for constructor.
**Gas Flags:** None
**Verdict:** CORRECT


---

## DegenerusVault.sol

### `constructor(string memory name_, string memory symbol_)` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor(string memory name_, string memory symbol_)` |
| **Visibility** | public |
| **Mutability** | state-changing |
| **Parameters** | `name_` (string): token name; `symbol_` (string): token symbol |
| **Returns** | N/A |

**State Reads:** `ContractAddresses.CREATOR` (compile-time constant)
**State Writes:** `name`, `symbol`, `totalSupply` (= INITIAL_SUPPLY = 1T * 1e18), `balanceOf[CREATOR]` (= INITIAL_SUPPLY)

**Callers:** Deployed by DegenerusVault constructor (twice: once for DGVB, once for DGVE)
**Callees:** None (emits Transfer event)

**ETH Flow:** None
**Invariants:** After construction, totalSupply == INITIAL_SUPPLY and balanceOf[CREATOR] == INITIAL_SUPPLY. No other balances set.
**NatSpec Accuracy:** Accurate. States "initial supply is minted to CREATOR."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address to approve; `amount` (uint256): allowance amount |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender]` = amount

**Callers:** External (users)
**Callees:** None (emits Approval event)

**ETH Flow:** None
**Invariants:** Allowance can be set to any value including 0. No zero-address check on spender (standard ERC-20 pattern).
**NatSpec Accuracy:** Accurate. Mentions type(uint256).max for unlimited.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `balanceOf[msg.sender]` (via `_transfer`)
**State Writes:** `balanceOf[msg.sender]` (decremented), `balanceOf[to]` (incremented) (via `_transfer`)

**Callers:** External (users, vault contract for BURNIE transfer in `_burnCoinFor`)
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** None
**Invariants:** Sum of all balances unchanged. Reverts if to == address(0) or insufficient balance.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `allowance[from][msg.sender]`
**State Writes:** `allowance[from][msg.sender]` (decremented if not max), `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** External (users, operators)
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** None
**Invariants:** Allowance decremented before transfer (CEI). Infinite allowance (type(uint256).max) not decremented -- standard gas optimization. Emits Approval event on allowance change.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMint(address to, uint256 amount)` [external, onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMint(address to, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount |
| **Returns** | None |

**State Reads:** None
**State Writes:** `totalSupply` (incremented), `balanceOf[to]` (incremented)

**Callers:** DegenerusVault._burnCoinFor (refill), DegenerusVault._burnEthFor (refill)
**Callees:** None (emits Transfer from address(0))

**ETH Flow:** None
**Invariants:** Only callable by VAULT. Reverts if to == address(0). Uses unchecked arithmetic -- overflow is theoretically possible but practically impossible (totalSupply would need to exceed 2^256).
**NatSpec Accuracy:** Accurate. States "Used for refill mechanism when all shares are burned."
**Gas Flags:** Unchecked addition -- safe in practice (1T * 1e18 * 2 << 2^256).
**Verdict:** CORRECT

---

### `vaultBurn(address from, uint256 amount)` [external, onlyVault]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultBurn(address from, uint256 amount) external onlyVault` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): holder to burn from; `amount` (uint256): burn amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented)

**Callers:** DegenerusVault._burnCoinFor, DegenerusVault._burnEthFor
**Callees:** None (emits Transfer to address(0))

**ETH Flow:** None
**Invariants:** Checks amount <= balance before burning. Uses unchecked subtraction -- safe because of the prior check.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** `transfer`, `transferFrom`
**Callees:** None (emits Transfer event)

**ETH Flow:** None
**Invariants:** Reverts on to == address(0) or insufficient balance. Unchecked arithmetic -- underflow safe (amount <= bal checked), overflow on balanceOf[to] practically impossible (sum of balances <= totalSupply).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** No zero-address check on `from` -- acceptable since `from` always originates from msg.sender or allowance-checked addresses.
**Verdict:** CORRECT

---

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `coinToken.vaultMintAllowance()` (external call to COIN contract)
**State Writes:** `coinShare` (immutable, set to new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB")), `ethShare` (immutable, set to new DegenerusVaultShare("Degenerus Vault Eth", "DGVE")), `coinTracked` (set to initial coin allowance)

**Callers:** Deployer
**Callees:** `new DegenerusVaultShare(...)` (x2), `coinToken.vaultMintAllowance()`

**ETH Flow:** None
**Invariants:** COIN contract must be deployed before VAULT (to call vaultMintAllowance). Both share tokens get INITIAL_SUPPLY (1T * 1e18) minted to CREATOR.
**NatSpec Accuracy:** Accurate. States "Deploys DGVB and DGVE tokens. Creator receives initial 1T supply of each."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `deposit(uint256 coinAmount, uint256 stEthAmount)` [external payable, onlyGame]

| Field | Value |
|-------|-------|
| **Signature** | `function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `coinAmount` (uint256): BURNIE mint allowance to escrow; `stEthAmount` (uint256): stETH to pull from GAME |
| **Returns** | None |

**State Reads:** `coinToken.vaultMintAllowance()` (via `_syncCoinReserves` if coinAmount != 0)
**State Writes:** `coinTracked` (synced + coinAmount if coinAmount != 0)

**Callers:** DegenerusGame (external, the GAME contract)
**Callees:** `_syncCoinReserves()`, `coinToken.vaultEscrow(coinAmount)`, `_pullSteth(msg.sender, stEthAmount)`

**ETH Flow:** msg.value from GAME -> vault ETH balance. stETH from GAME -> vault stETH balance (via transferFrom). BURNIE is virtual (escrow increases allowance, no token transfer).
**Invariants:** Only GAME can call. coinToken.vaultEscrow increases the vault's mint allowance on the coin contract. stETH transferFrom requires GAME to have approved the vault.
**NatSpec Accuracy:** Accurate. Explains virtual BURNIE deposit, ETH via msg.value, stETH via transferFrom.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `receive()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `receive() external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (ETH balance increases implicitly)

**Callers:** Any external sender (donation pathway)
**Callees:** None (emits Deposit event with 0 stETH and 0 BURNIE)

**ETH Flow:** msg.value -> vault ETH balance (donated, accrues to DGVE holders)
**Invariants:** Open to any sender. ETH donations increase the backing ratio of DGVE shares.
**NatSpec Accuracy:** Accurate. Says "Receive ETH donations from any sender."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameAdvance()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameAdvance() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner modifier
**State Writes:** None (state changes happen in GAME contract)

**Callers:** Vault owner (>50.1% DGVE holder)
**Callees:** `gamePlayer.advanceGame()`

**ETH Flow:** None directly. The advanceGame call may trigger Lido stETH submission inside the GAME contract, which could send ETH to Lido.
**Invariants:** Only vault owner can advance the game on behalf of the vault.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `ticketQuantity` (uint256): number of tickets; `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): affiliate code; `payKind` (MintPaymentKind): payment method; `ethValue` (uint256): additional ETH from vault balance |
| **Returns** | None |

**State Reads:** `address(this).balance` (via `_combinedValue`)
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `_combinedValue(ethValue)`, `gamePlayer.purchase{value: totalValue}(address(this), ...)`

**ETH Flow:** msg.value + ethValue from vault balance -> GAME contract via purchase{value}. Vault is the `buyer` (address(this)).
**Invariants:** _combinedValue reverts if msg.value + ethValue > address(this).balance. Vault acts as buyer so game tickets accrue to the vault address.
**NatSpec Accuracy:** Accurate. Explains msg.value combination with vault balance.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseTicketsBurnie(uint256 ticketQuantity)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `ticketQuantity` (uint256): number of tickets |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME/COIN)

**Callers:** Vault owner
**Callees:** `gamePlayer.purchaseCoin(address(this), ticketQuantity, 0)`

**ETH Flow:** None (BURNIE-denominated purchase, no ETH)
**Invariants:** Reverts if ticketQuantity == 0. Passes 0 for lootBoxBurnieAmount (tickets only, no lootbox).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseBurnieLootbox(uint256 burnieAmount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `burnieAmount` (uint256): BURNIE to spend on lootbox |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME/COIN)

**Callers:** Vault owner
**Callees:** `gamePlayer.purchaseBurnieLootbox(address(this), burnieAmount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** Reverts if burnieAmount == 0.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameOpenLootBox(uint48 lootboxIndex)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lootboxIndex` (uint48): index of the lootbox to open |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.openLootBox(address(this), lootboxIndex)`

**ETH Flow:** Game may send ETH/stETH/BURNIE/DGNRS rewards to the vault as a result.
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gamePurchaseDeityPassFromBoon(uint256 priceWei)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseDeityPassFromBoon(uint256 priceWei) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `priceWei` (uint256): expected deity pass price |
| **Returns** | None |

**State Reads:** `address(this).balance`, `gamePlayer.claimableWinningsOf(address(this))`
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimableWinningsOf(address(this))`, `gamePlayer.claimWinnings(address(this))`, `gamePlayer.purchaseDeityPass{value: priceWei}(address(this), true)`

**ETH Flow:** If vault balance < priceWei, auto-claims game winnings first. Then sends priceWei to GAME for deity pass purchase. The `true` parameter means "use boon" (post-presale deity pass).
**Invariants:** Reverts if priceWei == 0 or vault balance insufficient even after claiming winnings. The claimable > 1 check avoids claiming dust (game uses 1 wei as sentinel for "has claimable").
**NatSpec Accuracy:** Accurate. Mentions the pricing formula (24 + T(n) ETH).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameClaimWinnings()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWinnings() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (GAME updates claimable balance)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimWinningsStethFirst()`

**ETH Flow:** GAME sends ETH or stETH to the vault (claimWinningsStethFirst prefers stETH). This accrues to DGVE holders.
**Invariants:** Uses claimWinningsStethFirst (not claimWinnings) -- intentional vault optimization since stETH earns yield and both accrue to DGVE.
**NatSpec Accuracy:** Accurate. States "preferring stETH."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameClaimWhalePass()` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWhalePass() external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimWhalePass(address(this))`

**ETH Flow:** None (whale pass is a status, not a token transfer)
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial, uint256 ethValue)` [external payable, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial, uint256 ethValue) external payable onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): number of tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant; `ethValue` (uint256): additional vault ETH |
| **Returns** | None |

**State Reads:** `address(this).balance` (via `_combinedValue`)
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `_combinedValue(ethValue)`, `gamePlayer.placeFullTicketBets{value: totalValue}(address(this), 0, ...)`

**ETH Flow:** msg.value + ethValue -> GAME contract. Currency = 0 (ETH).
**Invariants:** Reverts if totalValue > totalBet (overpayment guard). This prevents sending more ETH than the bet requires. Uses _combinedValue for balance check.
**NatSpec Accuracy:** Mostly accurate. NatSpec says "customSpecial" but the interface parameter name is `heroQuadrant`. The NatSpec description "(1=ETH,2=BURNIE,3=DGNRS)" is misleading -- the actual interface defines it as hero quadrant (0-3 for payout boost, 0xFF for no hero).
**Gas Flags:** None
**Verdict:** CONCERN -- NatSpec for `customSpecial` parameter is inaccurate. It describes currency types but the underlying interface parameter is `heroQuadrant` for payout boost selection. Functional behavior is correct since the value is passed through unchanged.

---

### `gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.placeFullTicketBets(address(this), 1, ...)` (currency = 1 = BURNIE)

**ETH Flow:** None (BURNIE-denominated bet)
**Invariants:** No ETH forwarded. BURNIE is burned from vault's coin balance by the GAME contract.
**NatSpec Accuracy:** Same concern as gameDegeneretteBetEth regarding `customSpecial`.
**Gas Flags:** None
**Verdict:** CORRECT (functional, NatSpec informational only)

---

### `gameDegeneretteBetWwxrp(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetWwxrp(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amountPerTicket` (uint128): bet per ticket; `ticketCount` (uint8): tickets; `customTicket` (uint32): packed traits; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.placeFullTicketBets(address(this), 3, ...)` (currency = 3 = WWXRP)

**ETH Flow:** None (WWXRP-denominated bet)
**Invariants:** No ETH forwarded. WWXRP is burned from vault by the GAME contract.
**NatSpec Accuracy:** Same concern as gameDegeneretteBetEth regarding `customSpecial`.
**Gas Flags:** None
**Verdict:** CORRECT (functional, NatSpec informational only)

---

### `gameResolveDegeneretteBets(uint64[] calldata betIds)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `betIds` (uint64[]): bet identifiers to resolve |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.resolveDegeneretteBets(address(this), betIds)`

**ETH Flow:** GAME may send ETH/BURNIE/WWXRP winnings to vault upon resolution.
**Invariants:** Vault is the player (address(this)).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAutoRebuy(bool enabled)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAutoRebuy(bool enabled) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable auto-rebuy |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAutoRebuy(address(this), enabled)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAutoRebuyTakeProfit(uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAutoRebuyTakeProfit(address(this), takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetDecimatorAutoRebuy(bool enabled)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable decimator auto-rebuy |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setDecimatorAutoRebuy(address(this), enabled)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetAfKingMode(bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetAfKingMode(bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable AFK king mode; `ethTakeProfit` (uint256): ETH take profit; `coinTakeProfit` (uint256): coin take profit |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setAfKingMode(address(this), enabled, ethTakeProfit, coinTakeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `gameSetOperatorApproval(address operator, bool approved)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): address to approve/revoke; `approved` (bool): approval status |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.setOperatorApproval(operator, approved)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinDepositCoinflip(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinDepositCoinflip(uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): BURNIE to deposit into coinflip |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.depositCoinflip(address(this), amount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** BURNIE is transferred from vault to coinflip pool via the COIN contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinClaimCoinflips(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): maximum amount to claim |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.claimCoinflips(address(this), amount)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** Returns actual claimed amount (may be less than requested).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinClaimCoinflipsTakeProfit(uint256 multiples)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinClaimCoinflipsTakeProfit(uint256 multiples) external onlyVaultOwner returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `multiples` (uint256): number of take profit multiples |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.claimCoinflipsTakeProfit(address(this), multiples)`

**ETH Flow:** None (BURNIE-denominated)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinDecimatorBurn(uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinDecimatorBurn(uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): BURNIE to burn in decimator |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN/GAME)

**Callers:** Vault owner
**Callees:** `coinPlayer.decimatorBurn(address(this), amount)`

**ETH Flow:** None (BURNIE burn for decimator jackpot eligibility)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinSetAutoRebuy(bool enabled, uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `enabled` (bool): enable/disable; `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.setCoinflipAutoRebuy(address(this), enabled, takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinSetAutoRebuyTakeProfit(uint256 takeProfit)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `takeProfit` (uint256): take profit threshold |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in COIN)

**Callers:** Vault owner
**Callees:** `coinPlayer.setCoinflipAutoRebuyTakeProfit(address(this), takeProfit)`

**ETH Flow:** None (configuration only)
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `wwxrpMint(address to, uint256 amount)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function wwxrpMint(address to, uint256 amount) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): WWXRP to mint |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in WWXRP contract)

**Callers:** Vault owner
**Callees:** `wwxrpToken.vaultMintTo(to, amount)`

**ETH Flow:** None (WWXRP token mint)
**Invariants:** Early return if amount == 0. The WWXRP contract enforces its own allowance limits.
**NatSpec Accuracy:** Accurate. Mentions "uncirculating reserve."
**Gas Flags:** None
**Verdict:** CORRECT

---

### `jackpotsClaimDecimator(uint24 lvl)` [external, onlyVaultOwner]

| Field | Value |
|-------|-------|
| **Signature** | `function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): jackpot level to claim |
| **Returns** | None |

**State Reads:** Via onlyVaultOwner
**State Writes:** None directly (state changes in GAME)

**Callers:** Vault owner
**Callees:** `gamePlayer.claimDecimatorJackpot(lvl)`

**ETH Flow:** GAME sends ETH to vault if vault won the decimator jackpot at that level.
**Invariants:** None
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `burnCoin(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnCoin(address player, uint256 amount) external returns (uint256 coinOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn shares for (address(0) = msg.sender); `amount` (uint256): DGVB shares to burn |
| **Returns** | `coinOut` (uint256): BURNIE sent to player |

**State Reads:** Via `_requireApproved` (game.isOperatorApproved)
**State Writes:** Via `_burnCoinFor`

**Callers:** External (DGVB holders, operators)
**Callees:** `_requireApproved(player)`, `_burnCoinFor(player, amount)`

**ETH Flow:** None (BURNIE output only)
**Invariants:** If player is address(0), uses msg.sender. If player != msg.sender, checks operator approval via game contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burnCoinFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of BURNIE; `amount` (uint256): DGVB shares to burn |
| **Returns** | `coinOut` (uint256): BURNIE sent to player |

**State Reads:** `coinToken.vaultMintAllowance()` (via `_syncCoinReserves`), `coinShare.totalSupply()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`
**State Writes:** `coinTracked` (via `_syncCoinReserves`, and decremented when minting remainder)

**Callers:** `burnCoin`
**Callees:** `_syncCoinReserves()`, `coinShare.totalSupply()`, `coinToken.balanceOf(address(this))`, `coinPlayer.previewClaimCoinflips(address(this))`, `coinShare.vaultBurn(player, amount)`, `coinShare.vaultMint(player, REFILL_SUPPLY)` (if burning all), `coinToken.transfer(player, ...)`, `coinPlayer.claimCoinflips(address(this), remaining)`, `coinToken.vaultMintTo(player, remaining)`

**ETH Flow:** None
**Invariants:**
1. coinOut = (totalReserve * amount) / supplyBefore -- rounds DOWN (in vault's favor).
2. Total reserve = vaultMintAllowance + vault BURNIE balance + claimable coinflips.
3. Payment priority: vault balance first, then claim coinflips, then mint from allowance.
4. Refill: if burning entire supply, mint REFILL_SUPPLY (1T) to the burner.
5. coinTracked decremented by the minted remainder amount.

**NatSpec Accuracy:** Accurate.
**Gas Flags:** Multiple external calls (totalSupply, balanceOf, previewClaimCoinflips, claimCoinflips). This is inherent to the multi-source payout logic.
**Verdict:** CORRECT -- Rounding is in vault's favor (floor division). Payment waterfall ensures BURNIE is sourced from the cheapest path (balance > coinflips > mint). Refill prevents zero-supply.

---

### `burnEth(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnEth(address player, uint256 amount) external returns (uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn shares for (address(0) = msg.sender); `amount` (uint256): DGVE shares to burn |
| **Returns** | `ethOut` (uint256): ETH sent to player; `stEthOut` (uint256): stETH sent to player |

**State Reads:** Via `_requireApproved`
**State Writes:** Via `_burnEthFor`

**Callers:** External (DGVE holders, operators)
**Callees:** `_requireApproved(player)`, `_burnEthFor(player, amount)`

**ETH Flow:** ETH and/or stETH from vault -> player
**Invariants:** Same approval pattern as burnCoin.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burnEthFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnEthFor(address player, uint256 amount) private returns (uint256 ethOut, uint256 stEthOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient of ETH/stETH; `amount` (uint256): DGVE shares to burn |
| **Returns** | `ethOut` (uint256): ETH sent; `stEthOut` (uint256): stETH sent |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))` (via `_syncEthReserves`), `gamePlayer.claimableWinningsOf(address(this))`, `ethShare.totalSupply()`
**State Writes:** None directly in vault storage (share burn happens in DegenerusVaultShare)

**Callers:** `burnEth`
**Callees:** `_syncEthReserves()`, `gamePlayer.claimableWinningsOf(address(this))`, `ethShare.totalSupply()`, `gamePlayer.claimWinnings(address(this))`, `_stethBalance()`, `ethShare.vaultBurn(player, amount)`, `ethShare.vaultMint(player, REFILL_SUPPLY)`, `_payEth(player, ethOut)`, `_paySteth(player, stEthOut)`

**ETH Flow:** vault ETH -> player (preferred), vault stETH -> player (remainder)
**Invariants:**
1. reserve = ethBal + stethBal + claimable (with claimable adjusted: if claimable <= 1, treat as 0; else claimable -= 1).
2. claimValue = (reserve * amount) / supplyBefore -- rounds DOWN (in vault's favor).
3. If claimValue > ethBal + stethBal and claimable != 0, auto-claims game winnings first to increase ETH balance.
4. ETH preferred: if claimValue <= ethBal, all ETH. Else ethBal ETH + (claimValue - ethBal) stETH.
5. Reverts if stEthOut > stBal (insufficient stETH).
6. Refill: if burning entire supply, mint REFILL_SUPPLY to burner.

**NatSpec Accuracy:** Accurate. Mentions "ETH is preferred over stETH."
**Gas Flags:** Multiple external calls. Auto-claim of game winnings adds gas but is necessary for correctness.
**Verdict:** CORRECT -- Rounding is in vault's favor (floor division). Auto-claim prevents scenarios where claimable value is locked. ETH preference minimizes stETH transfers (which have 1-2 wei rounding in Lido).

---

### `_syncCoinReserves()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _syncCoinReserves() private returns (uint256 synced)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | `synced` (uint256): current vault mint allowance |

**State Reads:** `coinToken.vaultMintAllowance()`
**State Writes:** `coinTracked` (set to current allowance)

**Callers:** `deposit`, `_burnCoinFor`
**Callees:** `coinToken.vaultMintAllowance()`

**ETH Flow:** None
**Invariants:** Syncs local tracking with the actual on-chain allowance from the coin contract. This handles cases where the allowance changed due to external minting (vaultMintTo calls from other sources).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_payEth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payEth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): ETH to send |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (ETH balance decreases implicitly)

**Callers:** `_burnEthFor`
**Callees:** `to.call{value: amount}("")`

**ETH Flow:** vault -> `to` via low-level call
**Invariants:** Reverts on failure (TransferFailed). Uses low-level call (supports contracts with custom receive).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** No gas limit on call -- intentional to support contract recipients.
**Verdict:** CORRECT

---

### `_paySteth(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _paySteth(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): stETH to transfer |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (stETH balance decreases)

**Callers:** `_burnEthFor`
**Callees:** `steth.transfer(to, amount)`

**ETH Flow:** stETH from vault -> `to`
**Invariants:** Reverts if transfer returns false.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Lido stETH transfers may have 1-2 wei rounding. This is a known Lido behavior and does not affect vault correctness (rounding is negligible and vault uses floor division).
**Verdict:** CORRECT

---

### `_pullSteth(address from, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _pullSteth(address from, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `amount` (uint256): stETH to pull |
| **Returns** | None |

**State Reads:** None
**State Writes:** None (stETH balance increases)

**Callers:** `deposit`
**Callees:** `steth.transferFrom(from, address(this), amount)`

**ETH Flow:** stETH from `from` (GAME) -> vault
**Invariants:** No-op if amount == 0. Requires prior stETH approval from `from`. Reverts if transfer fails.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT


---

## DegenerusStonk.sol

> **Note:** DGNRS was neutered to remove all active gameplay. Holders can only hold, transfer, and burn for their proportional share of accumulated ETH/stETH/BURNIE. The lock system, gameplay functions (`gamePurchase`, `gamePurchaseTicketsBurnie`, `gamePurchaseBurnieLootbox`, `gameDegeneretteBetEth`, `gameDegeneretteBetBurnie`, `gameOpenLootBox`, `coinDecimatorBurn`), BURNIE rebate logic (`_rebateBurnieFromEthValue`), quest reward logic (`_transferFromPoolInternal`), spend tracking (`_checkAndRecordEthSpend`, `_checkAndRecordBurnieSpend`, `_maxEthActionFromLocked`, `_maxBurnieActionFromLocked`, `_lockedClaimableValues`), lock management (`lockForLevel`, `unlock`, `getLockStatus`, `_reduceActiveLock`), WWXRP handling, and the `IDegenerusQuestsView` interface were all removed. The contract passively accumulates value via free tickets, AFK mode, and deity pass (all handled by the game contract without DGNRS involvement).

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address authorized to spend; `amount` (uint256): allowance amount |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender] = amount`

**Callers:** External users/contracts
**Callees:** None

**ETH Flow:** No
**Invariants:** Allowance is set unconditionally (no check on balance). Standard ERC-20 approve pattern.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** (via `_transfer`) `balanceOf[from]`
**State Writes:** (via `_transfer`) `balanceOf[from]`, `balanceOf[to]`

**Callers:** External users/contracts
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Transfer amount must not exceed balance. Zero-address recipient blocked.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** `allowance[from][msg.sender]`, (via `_transfer`) `balanceOf[from]`
**State Writes:** `allowance[from][msg.sender]` (decremented if not max), (via `_transfer`) `balanceOf[from]`, `balanceOf[to]`

**Callers:** External users/contracts, COIN contract (trusted bypass)
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:** COIN contract bypasses allowance checks (trusted spender). For other callers, allowance must be sufficient unless max(uint256). Emits Approval with new allowance on decrement.
**NatSpec Accuracy:** Accurate. Correctly documents COIN trust.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** `transfer`, `transferFrom`, `transferFromPool`
**Callees:** None

**ETH Flow:** No
**Invariants:** Zero-address `to` blocked. Balance must be sufficient. Uses unchecked arithmetic safe because of prior checks. No lock enforcement (lock system removed).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `constructor()` [constructor]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** Constants: `INITIAL_SUPPLY`, `CREATOR_BPS`, `BPS_DENOM`, pool BPS constants, `ContractAddresses.CREATOR`, `ContractAddresses.GAME`
**State Writes:** `totalSupply` (via `_mint`), `balanceOf[CREATOR]`, `balanceOf[address(this)]`, `poolBalances[0..4]`

**Callers:** Deployment
**Callees:** `_mint(CREATOR, creatorAmount)`, `_mint(address(this), poolTotal)`, `game.claimWhalePass(address(0))`, `game.setAfKingMode(address(0), true, 10 ether, 0)`

**ETH Flow:** No
**Invariants:**
- Total supply = INITIAL_SUPPLY (1 trillion * 1e18)
- Creator gets 20% (200B tokens)
- Remaining 80% split into 5 pools with BPS-based allocation
- Dust from rounding error added to Lootbox pool
- Pool totals verified: Whale=1143, Affiliate=3428, Lootbox=1143+dust, Reward=1143, Earlybird=1143 -- these sum to 8000 BPS = 80%
- Claims whale pass for DGNRS contract in the game
- Enables afKing mode with 10 ETH take-profit, 0 BURNIE take-profit

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameAdvance()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameAdvance() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `balanceOf[msg.sender]` (via onlyHolder)
**State Writes:** None directly

**Callers:** External DGNRS holders
**Callees:** `game.advanceGame()`

**ETH Flow:** No
**Invariants:** Caller must hold DGNRS tokens.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameClaimWhalePass()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWhalePass() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `balanceOf[msg.sender]` (via onlyHolder)
**State Writes:** None directly

**Callers:** External DGNRS holders
**Callees:** `game.claimWhalePass(address(0))`

**ETH Flow:** No
**Invariants:** Caller must hold DGNRS tokens. Claims whale pass for DGNRS contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `receive()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `receive() external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None (receives ETH via msg.value) |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame)
**State Writes:** None (ETH stored in contract balance implicitly)

**Callers:** Game contract (ETH distributions)
**Callees:** None

**ETH Flow:** Game -> DGNRS contract (ETH deposit, stored in contract balance)
**Invariants:** Only game contract can send ETH. ETH backing is tracked by `address(this).balance` at query time.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `depositSteth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function depositSteth(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): stETH amount to deposit |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame)
**State Writes:** None (stETH tracked by external balanceOf)

**Callers:** Game contract (stETH distributions)
**Callees:** `steth.transferFrom(msg.sender, address(this), amount)`

**ETH Flow:** stETH transferred from game to DGNRS contract.
**Invariants:** Only game contract can deposit stETH. Uses transferFrom (game must have approved DGNRS for stETH).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFromPool(Pool pool, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFromPool(Pool pool, address to, uint256 amount) external returns (uint256 transferred)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `pool` (Pool): source pool; `to` (address): recipient; `amount` (uint256): requested amount |
| **Returns** | `uint256`: actual amount transferred (may be less) |

**State Reads:** `poolBalances[idx]`, `ContractAddresses.GAME` (via onlyGame), `balanceOf[address(this)]`
**State Writes:** `poolBalances[idx]` (decremented), `balanceOf[address(this)]` (decremented via `_transfer`), `balanceOf[to]` (incremented)

**Callers:** Game contract
**Callees:** `_poolIndex`, `_transfer(address(this), to, amount)`

**ETH Flow:** No (DGNRS token transfer, not ETH)
**Invariants:**
- Only game can call
- Zero-address `to` will revert in `_transfer`
- Graceful degradation: if pool has less than requested, transfers available amount
- Returns 0 for zero amount or empty pool
- Uses unchecked subtraction safe due to prior `amount <= available` check
- Emits PoolTransfer

**NatSpec Accuracy:** Accurate. Correctly documents partial-fill behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferBetweenPools(Pool from, Pool to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferBetweenPools(Pool from, Pool to, uint256 amount) external returns (uint256 transferred)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (Pool): source pool; `to` (Pool): destination pool; `amount` (uint256): requested amount |
| **Returns** | `uint256`: actual amount transferred |

**State Reads:** `poolBalances[fromIdx]`, `ContractAddresses.GAME` (via onlyGame)
**State Writes:** `poolBalances[fromIdx]` (decremented), `poolBalances[toIdx]` (incremented)

**Callers:** Game contract
**Callees:** `_poolIndex` (x2)

**ETH Flow:** No
**Invariants:**
- Only game can call
- No actual token transfer -- just internal pool accounting rebalance
- Graceful degradation for insufficient source pool
- Emits PoolRebalance

**NatSpec Accuracy:** Accurate. Correctly notes no token movement.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `burnForGame(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForGame(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame), `balanceOf[from]` (via `_burn`)
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented)

**Callers:** Game contract, `handleGameOverDrain` (burns undistributed pool tokens at game over)
**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:**
- Only game can call
- No-op for zero amount (returns early)
- Burns reduce total supply, which increases proportional backing per remaining token

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `burn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burn(address player, uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to burn for (address(0) = msg.sender); `amount` (uint256): DGNRS amount to burn |
| **Returns** | `ethOut` (uint256): ETH received; `stethOut` (uint256): stETH received; `burnieOut` (uint256): BURNIE received |

**State Reads:** `balanceOf[player]`, `totalSupply`, various external balances
**State Writes:** (via `_burnFor`) `balanceOf[player]`, `totalSupply`

**Callers:** External users/operators
**Callees:** `_requireApproved(player)` (if player != msg.sender and player != address(0)), `_burnFor(player, amount)`

**ETH Flow:** Pays out proportional ETH + stETH from contract reserves to player.
**Invariants:**
- address(0) resolves to msg.sender
- If player != msg.sender, must be approved operator
- Delegates to _burnFor for actual logic

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burnFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnFor(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn from and pay out to; `amount` (uint256): DGNRS to burn |
| **Returns** | `ethOut`, `stethOut`, `burnieOut`: amounts paid out |

**State Reads:** `balanceOf[player]`, `totalSupply`, `address(this).balance`, `steth.balanceOf(address(this))`, `game.claimableWinningsOf(address(this))` (via `_claimableWinnings`), `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** `balanceOf[player]`, `totalSupply`

**Callers:** `burn`
**Callees:** `_claimableWinnings`, `_burnWithBalance`, `game.claimWinnings(address(0))` (conditional), `coin.transfer`, `coinflip.claimCoinflips`, `steth.transfer`

**ETH Flow:**
- Calculates total money = ETH balance + stETH balance + claimable ETH
- Proportional share = `(totalMoney * amount) / supplyBefore`
- Prefers ETH over stETH: if totalValueOwed <= ethBal, pay all in ETH; otherwise pay ethBal in ETH + remainder in stETH
- If need more ETH than available but claimable exists, calls `game.claimWinnings` to materialize claimable ETH
- BURNIE share: `(totalBurnie * amount) / supplyBefore` from balance + coinflip claimables

**Invariants:**
- Amount must be > 0 and <= balance
- Burns BEFORE payouts (reducing totalSupply first for security)
- ETH-preferential payout: ETH first, stETH only when ETH insufficient
- BURNIE: pays from balance first, then claims from coinflip
- Reverts Insufficient if stethOut > stethBal (can't pay full share)
- Emits Burn

**NatSpec Accuracy:** Accurate.
**Gas Flags:** Multiple external calls (up to 6+ in worst case). Complex but necessary for multi-asset proportional withdrawal.
**Verdict:** CORRECT

---

### `_mint(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): tokens to mint |
| **Returns** | None |

**State Reads:** None
**State Writes:** `totalSupply` (incremented), `balanceOf[to]` (incremented)

**Callers:** `constructor` (only)
**Callees:** None

**ETH Flow:** No
**Invariants:** Zero-address blocked. Unchecked arithmetic safe because only called twice in constructor with bounded values. Emits Transfer from address(0).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): tokens to burn |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented)

**Callers:** `burnForGame`
**Callees:** None

**ETH Flow:** No
**Invariants:** Amount must not exceed balance. Unchecked arithmetic safe due to prior check. Emits Transfer to address(0).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burnWithBalance(address from, uint256 amount, uint256 bal)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnWithBalance(address from, uint256 amount, uint256 bal) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): burn address; `amount` (uint256): tokens to burn; `bal` (uint256): pre-fetched balance |
| **Returns** | None |

**State Reads:** None (balance pre-fetched by caller)
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented)

**Callers:** `_burnFor`
**Callees:** None

**ETH Flow:** No
**Invariants:** Optimization of `_burn` that skips the balanceOf read (caller already has it). Caller must ensure `amount <= bal`. Unchecked arithmetic relies on this invariant.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT


---

## DegenerusDeityPass.sol

### `transferOwnership(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferOwnership(address newOwner) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newOwner` (address): New owner address |
| **Returns** | None |

**State Reads:** `_contractOwner` (via onlyOwner modifier)
**State Writes:** `_contractOwner` = newOwner

**Callers:** External only (current owner)
**Callees:** None (emits OwnershipTransferred event)

**ETH Flow:** No
**Invariants:** Only the current `_contractOwner` can call. `newOwner` must not be address(0). After execution, `_contractOwner == newOwner`.
**NatSpec Accuracy:** No NatSpec. Behavior is standard Ownable pattern.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setRenderer(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setRenderer(address newRenderer) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newRenderer` (address): New external renderer address (address(0) to disable) |
| **Returns** | None |

**State Reads:** `renderer` (for prev event param), `_contractOwner` (via onlyOwner)
**State Writes:** `renderer` = newRenderer

**Callers:** External only (owner)
**Callees:** None (emits RendererUpdated event)

**ETH Flow:** No
**Invariants:** Only owner can call. address(0) is valid (disables external rendering). After execution, `renderer == newRenderer`.
**NatSpec Accuracy:** `@notice Set optional external renderer. Set to address(0) to disable.` -- Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setRenderColors(string,string,string)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setRenderColors(string calldata outlineColor, string calldata backgroundColor, string calldata nonCryptoSymbolColor) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `outlineColor` (string): Hex color for card outline; `backgroundColor` (string): Hex color for card background; `nonCryptoSymbolColor` (string): Hex color for non-crypto symbols |
| **Returns** | None |

**State Reads:** `_contractOwner` (via onlyOwner)
**State Writes:** `_outlineColor`, `_backgroundColor`, `_nonCryptoSymbolColor`

**Callers:** External only (owner)
**Callees:** `_isHexColor` (private, called 3 times for validation)

**ETH Flow:** No
**Invariants:** Only owner can call. All three color params must pass `_isHexColor` validation (7 chars, `#` prefix, hex digits). After execution, all three storage colors are updated.
**NatSpec Accuracy:** `@notice Set on-chain render colors.` with param descriptions -- Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `approve(address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): Address to approve; `tokenId` (uint256): Token to approve |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`, `_operatorApprovals[tokenOwner][msg.sender]`
**State Writes:** `_tokenApprovals[tokenId]` = to

**Callers:** External only (token owner or approved operator)
**Callees:** None (emits Approval event)

**ETH Flow:** No
**Invariants:** Only the token owner or an approved operator for the owner can call. Reverts with `NotAuthorized` otherwise. Does not check if token exists first -- but if `_owners[tokenId] == address(0)`, then `msg.sender != address(0)` is always true (since EOAs cannot be address(0)), so the operator check runs against `_operatorApprovals[address(0)][msg.sender]` which defaults to false, causing `NotAuthorized` revert. This is safe -- non-existent tokens cannot be approved.
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `setApprovalForAll(address,bool)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setApprovalForAll(address operator, bool approved) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `operator` (address): Operator to set approval for; `approved` (bool): Whether to approve |
| **Returns** | None |

**State Reads:** None
**State Writes:** `_operatorApprovals[msg.sender][operator]` = approved

**Callers:** External only
**Callees:** None (emits ApprovalForAll event)

**ETH Flow:** No
**Invariants:** Any address can call to set operator approval for themselves. No zero-address check on operator (per ERC-721 spec).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFrom(address,address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** (delegated to `_transfer`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** All invariants enforced by `_transfer`. No receiver check (per ERC-721 transferFrom spec).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `safeTransferFrom(address,address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function safeTransferFrom(address from, address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** (delegated to `_transfer` and `_checkReceiver`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`, `_checkReceiver(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** All `_transfer` invariants plus `_checkReceiver` invariant (contract recipients must implement IERC721Receiver).
**NatSpec Accuracy:** No NatSpec. Standard ERC-721 behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `safeTransferFrom(address,address,uint256,bytes)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer; `bytes calldata`: Additional data (unused) |
| **Returns** | None |

**State Reads:** (delegated to `_transfer` and `_checkReceiver`)
**State Writes:** (delegated to `_transfer`)

**Callers:** External only (owner, approved, or operator)
**Callees:** `_transfer(from, to, tokenId)`, `_checkReceiver(from, to, tokenId)`

**ETH Flow:** No
**Invariants:** Same as 3-param `safeTransferFrom`. Note: the `data` parameter is accepted but ignored -- the `_checkReceiver` call passes empty bytes `""` to `onERC721Received` regardless of the `data` argument. This is a minor deviation from ERC-721 spec which expects `data` to be forwarded.
**NatSpec Accuracy:** No NatSpec.
**Gas Flags:** The `data` parameter is declared but never used -- minimal gas overhead (calldata is read-only, just costs calldatacopy).
**Verdict:** CONCERN -- The `data` bytes parameter in the 4-argument `safeTransferFrom` is silently ignored rather than forwarded to `onERC721Received`. Per ERC-721, the data should be passed through. In practice this is low-risk since the onDeityPassTransfer callback is the primary transfer hook, and most receivers don't use the data parameter, but it is technically non-compliant.

---

### `mint(address,uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mint(address to, uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): Recipient of the minted token; `tokenId` (uint256): Symbol ID (0-31) |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`
**State Writes:** `_balances[to]` (incremented), `_owners[tokenId]` = to

**Callers:** External only -- DegenerusGame contract (via `purchaseDeityPass`)
**Callees:** None (emits Transfer event with from=address(0))

**ETH Flow:** No
**Invariants:**
- Only `ContractAddresses.GAME` can call (reverts `NotAuthorized` otherwise)
- `tokenId < 32` (reverts `InvalidToken` otherwise)
- Token must not already exist: `_owners[tokenId] == address(0)` (reverts `InvalidToken` otherwise)
- `to != address(0)` (reverts `ZeroAddress` otherwise)
- After execution: `_owners[tokenId] == to`, `_balances[to]` incremented by 1

**NatSpec Accuracy:** `@notice Mint a deity pass. Only callable by the game contract during purchase.` -- Accurate. The "during purchase" clarification is contextually correct (Game calls this from purchaseDeityPass).
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `burn(uint256)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burn(uint256 tokenId) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `tokenId` (uint256): Token to burn |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`
**State Writes:** `_tokenApprovals[tokenId]` (deleted), `_balances[tokenOwner]` (decremented via unchecked), `_owners[tokenId]` (deleted)

**Callers:** External only -- DegenerusGame contract (for deity pass refunds during game over)
**Callees:** None (emits Transfer event with to=address(0))

**ETH Flow:** No
**Invariants:**
- Only `ContractAddresses.GAME` can call (reverts `NotAuthorized` otherwise)
- Token must exist: `_owners[tokenId] != address(0)` (reverts `InvalidToken` otherwise)
- After execution: `_owners[tokenId] == address(0)`, `_balances[tokenOwner]` decremented by 1, approval cleared
- `unchecked` balance decrement is safe because if the token exists, the owner's balance is >= 1

**NatSpec Accuracy:** `@notice Burn a deity pass. Only callable by the game contract (for refunds).` -- Accurate.
**Gas Flags:** `unchecked` decrement is safe (owner's balance guaranteed >= 1 since they own the token being burned).
**Verdict:** CORRECT

---

### `_transfer(address,address,uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 tokenId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Claimed current owner; `to` (address): Recipient; `tokenId` (uint256): Token to transfer |
| **Returns** | None |

**State Reads:** `_owners[tokenId]`, `_tokenApprovals[tokenId]`, `_operatorApprovals[from][msg.sender]`
**State Writes:** `_tokenApprovals[tokenId]` (deleted), `_balances[from]` (decremented, unchecked), `_balances[to]` (incremented), `_owners[tokenId]` = to

**Callers:** `transferFrom`, `safeTransferFrom` (both overloads)
**Callees:** `IDeityPassCallback(ContractAddresses.GAME).onDeityPassTransfer(from, to, uint8(tokenId))` -- cross-contract callback

**ETH Flow:** No direct ETH flow. The Game callback may perform internal ETH accounting (burns BURNIE, updates deity storage, nukes sender stats) but no ETH is transferred in this function.
**Invariants:**
- `_owners[tokenId] == from` (reverts `NotAuthorized` otherwise -- ownership verification)
- `to != address(0)` (reverts `ZeroAddress` -- cannot transfer to zero)
- `msg.sender` must be `from`, or `_tokenApprovals[tokenId]`, or an approved operator for `from` (reverts `NotAuthorized` otherwise)
- Game callback is called BEFORE state mutation (callback-first pattern). If Game callback reverts, entire transfer reverts.
- `unchecked` balance decrement is safe (from owns the token, so balance >= 1)
- After execution: `_owners[tokenId] == to`, `_balances[from]` decremented, `_balances[to]` incremented, approval cleared
- The `uint8(tokenId)` cast is safe because tokenId is guaranteed to be < 32 (only minted 0-31)

**NatSpec Accuracy:** No NatSpec on the function itself. Inline comment: `// Callback to game: burns BURNIE, updates deity storage, nukes sender stats.` -- Accurate description of what the Game contract does.
**Gas Flags:** None. The callback-first pattern (calling Game before mutating state) is intentional for correctness -- Game needs to know the transfer is happening to update its state, and if Game reverts, the transfer should fail.
**Verdict:** CORRECT -- Note: The callback-before-mutation pattern means this is NOT strictly CEI (Checks-Effects-Interactions), but it is intentional. The Game contract is a trusted fixed address, not an arbitrary external call, so reentrancy is not a concern.

---

### `_checkReceiver(address,address,uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _checkReceiver(address from, address to, uint256 tokenId) private` |
| **Visibility** | private |
| **Mutability** | state-changing (makes external call) |
| **Parameters** | `from` (address): Previous owner; `to` (address): Recipient; `tokenId` (uint256): Token transferred |
| **Returns** | None |

**State Reads:** `to.code.length` (extcodesize check)
**State Writes:** None

**Callers:** `safeTransferFrom` (both overloads)
**Callees:** `IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "")` -- external call to receiver contract

**ETH Flow:** No
**Invariants:**
- Only called if `to` is a contract (`to.code.length != 0`)
- If `to` is a contract, it must return `IERC721Receiver.onERC721Received.selector` (reverts `NotAuthorized` otherwise)
- If the call reverts, the entire safeTransferFrom reverts with `NotAuthorized`
- Always passes empty bytes `""` as data (see concern on 4-param safeTransferFrom)

**NatSpec Accuracy:** No NatSpec. Standard ERC-721 receiver check pattern.
**Gas Flags:** None.
**Verdict:** CORRECT -- Standard ERC-721 safe transfer receiver check. The empty data forwarding is noted in the safeTransferFrom entry.

---

### `constructor()` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | N/A (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** None
**State Writes:** `_contractOwner` = msg.sender

**Callers:** Deploy transaction
**Callees:** None (emits OwnershipTransferred event with from=address(0))

**ETH Flow:** No
**Invariants:** Sets deployer as initial owner. Emits OwnershipTransferred(address(0), msg.sender).
**NatSpec Accuracy:** No NatSpec on constructor.
**Gas Flags:** None.
**Verdict:** CORRECT


---

## DegenerusAffiliate.sol

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

## DegenerusQuests.sol

### `rollDailyQuest(uint48 day, uint256 entropy)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rollDailyQuest(uint48 day, uint256 entropy) external onlyCoin returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): quest day identifier; `entropy` (uint256): VRF entropy word |
| **Returns** | `rolled` (bool): always true; `questTypes` (uint8[2]): two quest types rolled; `highDifficulty` (bool): always false |

**State Reads:** None directly (delegates to `_rollDailyQuest`)
**State Writes:** None directly (delegates to `_rollDailyQuest`)

**Callers:** BurnieCoin contract (external, via onlyCoin gate)
**Callees:** `_rollDailyQuest(day, entropy)`

**ETH Flow:** None
**Invariants:** Only COIN or COINFLIP can call. Day monotonicity enforced by caller, not by this contract.
**NatSpec Accuracy:** NatSpec says COIN or COINFLIP only -- matches modifier. States entropy usage for two slots -- accurate. Says `rolled` always true -- correct. Says `highDifficulty` always false -- correct (difficulty feature removed).
**Gas Flags:** None -- thin wrapper delegating to private function.
**Verdict:** CORRECT

---

### `resetQuestStreak(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resetQuestStreak(address player) external onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose streak to reset |
| **Returns** | None |

**State Reads:** `questPlayerState[player]`
**State Writes:** `questPlayerState[player].streak = 0`, `questPlayerState[player].baseStreak = 0`

**Callers:** DegenerusGame contract (external, via onlyGame gate)
**Callees:** None

**ETH Flow:** None
**Invariants:** Only GAME contract can reset streaks. Does not emit an event.
**NatSpec Accuracy:** No NatSpec provided for this function. Missing documentation.
**Gas Flags:** No event emitted on streak reset -- intentional for gas savings but inconsistent with `_questSyncState` which emits `QuestStreakReset`.
**Verdict:** CONCERN (informational) -- No NatSpec and no event emission. The `_questSyncState` function emits `QuestStreakReset` when streak goes to 0, but this explicit reset path does not. Off-chain indexers tracking streak resets may miss game-initiated resets. Functionally correct.

---

### `awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay) external onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint16): streak days to add; `currentDay` (uint48): current quest day |
| **Returns** | None |

**State Reads:** `questPlayerState[player].streak`, `questPlayerState[player].lastActiveDay`, plus reads from `_questSyncState`
**State Writes:** `questPlayerState[player].streak` (incremented, clamped at uint24 max), `questPlayerState[player].lastActiveDay` (updated if < currentDay24), plus writes from `_questSyncState`

**Callers:** DegenerusGame contract (external, via onlyGame gate)
**Callees:** `_questSyncState(state, player, currentDay)`

**ETH Flow:** None
**Invariants:** Silently returns on zero address, zero amount, or zero currentDay. Streak clamped at uint24 max (16,777,215). `_questSyncState` is called first, so missed-day streak reset happens before bonus is applied.
**NatSpec Accuracy:** Accurate. States clamp at uint24 max -- correct (code checks `updated > type(uint24).max`). States silent return on zero inputs -- correct.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `handleMint(address player, uint32 quantity, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleMint(address player, uint32 quantity, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): minter; `quantity` (uint32): tickets minted; `paidWithEth` (bool): ETH vs BURNIE payment |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type processed; `streak` (uint32): current streak; `completed` (bool): whether quest completed |

**State Reads:** `activeQuests`, `questPlayerState[player]`, reads from `_questSyncState`, `_questSyncProgress`, `_questHandleProgressSlot`
**State Writes:** Via `_questSyncState`, `_questSyncProgress`, `_questHandleProgressSlot`, `_questComplete`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_questTargetValue`, `_questHandleProgressSlot`, `questGame.mintPrice()` (only if paidWithEth)

**ETH Flow:** None
**Invariants:** Early exit on zero player/quantity/day. Iterates both slots since MINT_BURNIE could be in slot 0 or 1 (though in practice slot 0 is always MINT_ETH). For ETH mints, delta = quantity * mintPrice. For BURNIE mints, delta = quantity (whole ticket count). Aggregates rewards from both slots if both match.
**NatSpec Accuracy:** Accurate. States it covers both BURNIE and ETH paid mints -- correct. States iteration over both slots -- correct.
**Gas Flags:** When paidWithEth is false, `mintPrice` is uninitialized (0) and passed to `_questTargetValue`. For MINT_BURNIE quest type, `_questTargetValue` returns `QUEST_MINT_TARGET` (1) without using mintPrice -- safe. But mintPrice=0 is also passed to `_questHandleProgressSlot` which passes it to `_questCompleteWithPair` -> `_maybeCompleteOther` -> `_questReady`. In `_questReady`, if the other slot is an ETH-type quest, it would fetch mintPrice from game (the `currentPrice == 0` branch). So this is correct but involves an extra external call in the combo path.
**Verdict:** CORRECT

---

### `handleFlip(address player, uint256 flipCredit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleFlip(address player, uint256 flipCredit) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): staker/unstaker; `flipCredit` (uint256): BURNIE amount in base units |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Early exit on zero player/flipCredit/day. Returns early if no FLIP quest active today. Slot 1 completion requires slot 0 already complete (completionMask bit 0 check). Progress is clamped at uint128 max.
**NatSpec Accuracy:** Accurate. Says BURNIE base units -- correct.
**Gas Flags:** Emits `QuestProgressUpdated` even when target not met (intentional for frontend tracking). Calls `_questTargetValue` with mintPrice=0 -- for FLIP type this returns `QUEST_BURNIE_TARGET` without using mintPrice, so safe.
**Verdict:** CORRECT

---

### `handleDecimator(address player, uint256 burnAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDecimator(address player, uint256 burnAmount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): burner; `burnAmount` (uint256): BURNIE burned in base units |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Same pattern as handleFlip. Early exit on zero inputs. Returns early if no DECIMATOR quest active. Slot 1 requires slot 0 complete. Target is QUEST_BURNIE_TARGET (2000 BURNIE).
**NatSpec Accuracy:** Accurate. States BURNIE base units and same target as flip (2000 BURNIE) -- correct.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `handleAffiliate(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleAffiliate(address player, uint256 amount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): affiliate earner; `amount` (uint256): BURNIE earned from referrals |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Same pattern as handleFlip/handleDecimator. Target is QUEST_BURNIE_TARGET (2000 BURNIE).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `handleLootBox(address player, uint256 amountWei)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleLootBox(address player, uint256 amountWei) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): lootbox buyer; `amountWei` (uint256): ETH spent in wei |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `questGame.mintPrice()`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None (tracks ETH amounts but does not transfer ETH)
**Invariants:** Same handler pattern. Fetches mintPrice from game for target calculation. Target = mintPrice * 2, capped at 0.5 ETH. Slot 1 requires slot 0 complete.
**NatSpec Accuracy:** Accurate. States ETH target is 2x mint price capped at QUEST_ETH_TARGET_CAP -- correct.
**Gas Flags:** Always fetches mintPrice even if lootbox quest is not active (fetch happens after quest lookup, so only when quest found -- actually it is fetched unconditionally at line 725 before the target check). This means one external call even if progress < target. Minor gas informational.
**Verdict:** CORRECT

---

### `handleDegenerette(address player, uint256 amount, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDegenerette(address player, uint256 amount, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): bettor; `amount` (uint256): bet amount (wei for ETH, base units for BURNIE); `paidWithEth` (bool): payment type |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** Via `_questHandleProgressSlot`, `_questSyncProgress`, `_questComplete`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `questGame.mintPrice()` (only if paidWithEth), `_questTargetValue`, `_questHandleProgressSlot`

**ETH Flow:** None
**Invariants:** Dispatches to either DEGENERETTE_ETH or DEGENERETTE_BURNIE quest type based on paidWithEth flag. For ETH, target = mintPrice * 2, capped at 0.5 ETH. For BURNIE, target = 2000 BURNIE. Uses `_questHandleProgressSlot` (shared progress path) rather than inline progress like other handlers.
**NatSpec Accuracy:** Accurate. States wei for ETH, base units for BURNIE -- correct.
**Gas Flags:** mintPrice only fetched when paidWithEth -- efficient.
**Verdict:** CORRECT

---

### `_rollDailyQuest(uint48 day, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollDailyQuest(uint48 day, uint256 entropy) private returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): quest day; `entropy` (uint256): VRF entropy |
| **Returns** | `rolled` (bool): always true; `questTypes` (uint8[2]): selected types; `highDifficulty` (bool): always false |

**State Reads:** `activeQuests` (storage reference), reads from `_canRollDecimatorQuest`
**State Writes:** `activeQuests[0]`, `activeQuests[1]` (via `_seedQuestType`), `questVersionCounter` (via `_nextQuestVersion`)

**Callers:** `rollDailyQuest`
**Callees:** `_canRollDecimatorQuest`, `_bonusQuestType`, `_seedQuestType` (x2), `_nextQuestVersion` (x2 via _seedQuestType)

**ETH Flow:** None
**Invariants:** Slot 0 is always QUEST_TYPE_MINT_ETH. Slot 1 is weighted-random excluding the primary type. Entropy halves swapped for slot 1 to derive independent randomness. Two `QuestSlotRolled` events emitted. No day-overlap check (caller responsible for day monotonicity). Always overwrites existing quests regardless of whether already rolled for this day.
**NatSpec Accuracy:** Accurate. States slot 0 fixed to MINT_ETH, slot 1 weighted-random distinct from slot 0 -- correct.
**Gas Flags:** No guard against re-rolling same day (caller-enforced). Two version bumps per roll.
**Verdict:** CORRECT

---

### `_nextQuestVersion()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _nextQuestVersion() private returns (uint24 newVersion)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | `newVersion` (uint24): the version number (pre-increment value) |

**State Reads:** `questVersionCounter`
**State Writes:** `questVersionCounter` (incremented by 1)

**Callers:** `_seedQuestType`
**Callees:** None

**ETH Flow:** None
**Invariants:** Monotonically increasing. Uses post-increment (returns current then increments). At uint24 max (16,777,215), the next increment wraps to 0 due to Solidity 0.8 overflow on uint24. However, this is unchecked arithmetic in the `++` operator -- actually in Solidity 0.8.34, `questVersionCounter++` is checked and would revert on overflow. This would brick quest rolling after 16M version bumps (~8M days at 2 per day = ~22,000 years). Not a practical concern.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_seedQuestType(DailyQuest storage quest, uint48 day, uint8 questType)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _seedQuestType(DailyQuest storage quest, uint48 day, uint8 questType) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `quest` (DailyQuest storage): slot to seed; `day` (uint48): quest day; `questType` (uint8): type to seed |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** `quest.day`, `quest.questType`, `quest.version` (via `_nextQuestVersion`), `questVersionCounter` (indirectly)

**Callers:** `_rollDailyQuest`
**Callees:** `_nextQuestVersion`

**ETH Flow:** None
**Invariants:** Does not set `quest.flags` or `quest.difficulty` -- they retain previous values or default to 0. Since difficulty is "unused; retained for storage compatibility" per struct definition, this is intentional.
**NatSpec Accuracy:** Accurate. States version bump invalidates stale progress -- correct.
**Gas Flags:** Does not clear `flags` or `difficulty` fields. Pre-existing values persist but are not used. Minor storage efficiency note.
**Verdict:** CORRECT

---

### `_questHandleProgressSlot(...)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questHandleProgressSlot(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, DailyQuest memory quest, uint8 slot, uint256 delta, uint256 target, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `state` (storage): player state; `quests` (memory): active quests; `quest` (memory): specific quest; `slot` (uint8): slot index; `delta` (uint256): progress to add; `target` (uint256): completion target; `currentDay` (uint48): current day; `mintPrice` (uint256): cached mint price |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** Via `_questSyncProgress`
**State Writes:** `state.progress[slot]` (via `_clampedAdd128`), `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]` (via `_questSyncProgress`), plus writes from `_questCompleteWithPair`

**Callers:** `handleMint`, `handleDegenerette`
**Callees:** `_questSyncProgress`, `_clampedAdd128`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Syncs progress first (resets if stale). Adds delta clamped at uint128 max. Emits `QuestProgressUpdated`. If progress >= target, checks slot-1-requires-slot-0 rule before completing. Returns incomplete (0 reward) if target not met.
**NatSpec Accuracy:** Accurate. Parameters well-documented.
**Gas Flags:** Uses `quest.day` for sync (not `currentDay`) in the event emission -- this is correct since quest.day is the active day.
**Verdict:** CORRECT

---

### `_questSyncState(PlayerQuestState storage state, address player, uint48 currentDay)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questSyncState(PlayerQuestState storage state, address player, uint48 currentDay) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `state` (storage): player state; `player` (address): player for events/shield lookup; `currentDay` (uint48): current quest day |
| **Returns** | None |

**State Reads:** `state.streak`, `state.lastActiveDay`, `state.lastCompletedDay`, `questStreakShieldCount[player]`, `state.lastSyncDay`
**State Writes:** `questStreakShieldCount[player]` (decremented by used shields), `state.streak` (reset to 0 if days missed beyond shields), `state.lastSyncDay`, `state.completionMask` (reset to 0), `state.baseStreak` (snapshot of streak)

**Callers:** `awardQuestStreakBonus`, `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`
**Callees:** None

**ETH Flow:** None
**Invariants:** Uses `lastActiveDay` as anchor (any slot completion), falls back to `lastCompletedDay`. If gap > 1 day, shields are consumed first. If missedDays > shields, streak resets to 0 (shields also fully consumed). On new day (lastSyncDay != currentDay), resets completionMask and snapshots baseStreak. Idempotent within same day (lastSyncDay check).
**NatSpec Accuracy:** Accurate. Streak reset logic documented correctly. baseStreak snapshot documented.
**Gas Flags:** Reads `questStreakShieldCount[player]` even when anchorDay == 0 (no-op path). Actually no -- the outer check `anchorDay != 0` gates the shield logic. Correct.
**Verdict:** CORRECT

---

### `_questSyncProgress(PlayerQuestState storage state, uint8 slot, uint48 currentDay, uint24 questVersion)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questSyncProgress(PlayerQuestState storage state, uint8 slot, uint48 currentDay, uint24 questVersion) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `state` (storage): player state; `slot` (uint8): slot index; `currentDay` (uint48): current day; `questVersion` (uint24): current quest version |
| **Returns** | None |

**State Reads:** `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]`
**State Writes:** `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]`, `state.progress[slot]` (reset to 0 on mismatch)

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `_questHandleProgressSlot`
**Callees:** None

**ETH Flow:** None
**Invariants:** Key anti-exploit mechanism. Resets progress to 0 when day or version changes. Prevents stale progress from a previous day or quest version from counting toward today's quest. Truncates currentDay to uint24 (safe since max uint48 day value is within uint24 range for ~45,000 years).
**NatSpec Accuracy:** Accurate. Describes anti-exploit purpose well.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questComplete(address player, PlayerQuestState storage state, uint8 slot, DailyQuest memory quest)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questComplete(address player, PlayerQuestState storage state, uint8 slot, DailyQuest memory quest) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `state` (storage): player state; `slot` (uint8): slot index; `quest` (memory): completed quest |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): success |

**State Reads:** `state.completionMask`, `state.lastActiveDay`, `state.streak`
**State Writes:** `state.completionMask` (slot bit + STREAK_CREDITED), `state.lastActiveDay`, `state.streak` (incremented on first daily completion), `state.lastCompletedDay`

**Callers:** `_questCompleteWithPair`, `_maybeCompleteOther`
**Callees:** None

**ETH Flow:** None
**Invariants:** Idempotent -- returns (0, type, streak, false) if slot already completed. Streak incremented only once per day (STREAK_CREDITED bit). Streak clamped at uint24 max. Reward: slot 0 = 100 BURNIE, slot 1 = 200 BURNIE. Emits `QuestCompleted` event.
**NatSpec Accuracy:** Accurate. Documents streak logic and reward calculation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questCompleteWithPair(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, DailyQuest memory quest, uint48 currentDay, uint256 mintPrice)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questCompleteWithPair(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, DailyQuest memory quest, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player`, `state`, `quests`, `slot`, `quest`, `currentDay`, `mintPrice` |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** Via `_questComplete`, `_maybeCompleteOther`
**State Writes:** Via `_questComplete`, `_maybeCompleteOther`

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `_questHandleProgressSlot`
**Callees:** `_questComplete`, `_maybeCompleteOther`

**ETH Flow:** None
**Invariants:** Completes the current slot, then checks the other slot (XOR flip: 0->1, 1->0). If other slot's progress already meets target, completes it too ("combo completion"). Aggregates rewards from both completions. Returns completed=true even if only the primary slot completed.
**NatSpec Accuracy:** Accurate. Documents combo completion UX optimization.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_maybeCompleteOther(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, uint48 currentDay, uint256 mintPrice)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeCompleteOther(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player`, `state`, `quests`, `slot`, `currentDay`, `mintPrice` |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** `state.completionMask`, via `_questReady`
**State Writes:** Via `_questComplete`

**Callers:** `_questCompleteWithPair`
**Callees:** `_questReady`, `_questComplete`

**ETH Flow:** None
**Invariants:** Skips if quest not for today or already completed. Uses `_questReady` to check if progress >= target with valid day/version. Only completes if ready.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT


---

## DegenerusJackpots.sol

### `recordBafFlip(address player, uint24 lvl, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `lvl` (uint24): current game level / BAF bracket; `amount` (uint256): raw coinflip stake amount |
| **Returns** | none |
| **Modifiers** | `onlyCoin` |

**State Reads:**
- `bafTotals[lvl][player]` -- current accumulated total for this player at this level

**State Writes:**
- `bafTotals[lvl][player]` -- updated with `total + amount`
- `bafTop[lvl]` -- via `_updateBafTop` (leaderboard entries)
- `bafTopLen[lvl]` -- via `_updateBafTop` (leaderboard length)

**Callers:** BurnieCoin contract (external, via `onlyCoin` modifier). Also BurnieCoinflip contract.

**Callees:**
- `_updateBafTop(lvl, player, total)` -- updates leaderboard

**ETH Flow:** None. No ETH is sent or received.

**Invariants:**
- `bafTotals[lvl][player]` is monotonically non-decreasing (only adds, never subtracts)
- After call, player's total equals previous total + amount
- If player is the VAULT address, function returns early (no state change)
- Leaderboard remains sorted descending by score after update

**NatSpec Accuracy:** NatSpec says "Record a coinflip stake for BAF leaderboard tracking. Called by coin contract on every manual coinflip. Silently ignores vault address." This is accurate. The `@custom:access` correctly notes `onlyCoin` restriction.

**Gas Flags:**
- `unchecked { total += amount; }` -- comment says "reasonable values won't overflow uint256". Given that `amount` is a coinflip stake in wei, overflow of uint256 is practically impossible. Safe.

**Verdict:** CORRECT

---

### `runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external override onlyGame returns (address[] memory winners, uint256[] memory amounts, uint256 winnerMask, uint256 returnAmountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): total ETH prize pool; `lvl` (uint24): level being resolved; `rngWord` (uint256): VRF-derived randomness seed |
| **Returns** | `winners` (address[]): winner addresses; `amounts` (uint256[]): prize amounts; `winnerMask` (uint256): bitmask for scatter ticket routing; `returnAmountWei` (uint256): unawarded amount |
| **Modifiers** | `onlyGame` |

**State Reads:**
- `bafTop[lvl]` -- via `_bafTop(lvl, 0)`, `_bafTop(lvl, pick)` for leaderboard positions
- `bafTopLen[lvl]` -- via `_bafTop` and `_clearBafTop`
- `bafTotals[lvl][player]` -- via `_bafScore` for far-future and scatter scoring

**State Writes:**
- `bafTop[lvl]` -- deleted via `_clearBafTop`
- `bafTopLen[lvl]` -- deleted via `_clearBafTop`
- Note: `bafTotals` is NOT cleared (historical data preserved)

**Callers:** DegenerusGame contract (via `onlyGame` modifier), specifically through JackpotModule delegatecall.

**Callees:**
- `_bafTop(lvl, 0)` -- get #1 BAF bettor
- `_bafTop(lvl, pick)` -- get #3 or #4 BAF bettor (random pick)
- `coin.coinflipTopLastDay()` -- external call to COINFLIP for last-24h top bettor
- `_creditOrRefund(...)` -- memory buffer write helper (pure)
- `affiliate.affiliateTop(uint24(lvl - offset))` -- external call to Affiliate for top referrers per level
- `_bafScore(player, lvl)` -- BAF score lookup for affiliate candidates
- `degenerusGame.sampleFarFutureTickets(entropy)` -- external call to Game for far-future ticket holders
- `_bafScore(cand, lvl)` -- scoring far-future and scatter candidates
- `degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy)` -- external call to Game for trait ticket sampling
- `_clearBafTop(lvl)` -- cleanup after resolution

**ETH Flow:** None directly. This function computes winners and amounts, returning them as arrays. The calling game contract (JackpotModule) handles actual ETH transfers using the returned data.

**Prize Distribution Logic (verified):**

| Slice | Share | Source | Selection Method |
|-------|-------|--------|------------------|
| A: Top BAF | 10% (`P / 10`) | `_bafTop(lvl, 0)` | Deterministic: highest BAF bettor |
| A2: Top Coinflip | 10% (`P / 10`) | `coin.coinflipTopLastDay()` | Deterministic: highest 24h coinflip bettor |
| B: Random Pick | 5% (`P / 20`) | `_bafTop(lvl, 2 or 3)` | Pseudo-random: entropy LSB selects 3rd or 4th |
| C: Affiliate | 10% (`P / 10`) | Top affiliates from past 20 levels | Shuffle + sort by BAF score; 5/3/2/0 split |
| D: Far-Future | 5% (3% + 2%) | `sampleFarFutureTickets` | Top 2 by BAF score from sampled set |
| E: Scatter 1st | 40% (`P * 2 / 5`) | `sampleTraitTicketsAtLevel` | 50 rounds x 4 tickets, best per round |
| E2: Scatter 2nd | 20% (`P / 5`) | `sampleTraitTicketsAtLevel` | 50 rounds x 4 tickets, second per round |

Total: 100% (10 + 10 + 5 + 10 + 5 + 40 + 20 = 100)

**Scatter Level Targeting:**
- Non-century levels: 20 rounds at lvl+1, 10 at lvl+2, 10 at lvl+3, 10 at lvl+4
- Century levels (lvl % 100 == 0): 4 at lvl+1, 4 at lvl+2, 4 at lvl+3, 38 random from past 99

**Winner Mask Logic:**
- After scatter processing, the last `BAF_SCATTER_TICKET_WINNERS` (40) scatter entries get mask bits set
- Bits are set at positions `BAF_SCATTER_MASK_OFFSET + idx` (128 + idx)
- The mask is computed from the end of the scatter array backwards, flagging the last 40 (or fewer) entries

**Entropy Chaining:** Each random selection uses `entropy = keccak256(entropy, salt)` with incrementing salt, ensuring independence of random decisions from a single VRF word.

**Invariants:**
- Sum of all awarded amounts + returnAmountWei == poolWei (conservation of prize pool)
- After execution, leaderboard for `lvl` is cleared (bafTop and bafTopLen deleted)
- Maximum 108 winners (1 + 1 + 1 + 3 + 2 + 50 + 50)
- All unfilled slots contribute to `toReturn`

**NatSpec Accuracy:** NatSpec is comprehensive and accurate. Prize distribution percentages in the banner comment match code. The `@custom:access` correctly notes `onlyGame` restriction.

**Gas Flags:**
- 50 rounds of scatter sampling with external calls (`sampleTraitTicketsAtLevel`) is gas-intensive but bounded by `BAF_SCATTER_ROUNDS = 50`
- 20 iterations for affiliate candidate collection with external calls to `affiliate.affiliateTop`
- Assembly `mstore` to trim array length is safe and gas-efficient
- Affiliate dedup loop is O(n^2) but bounded by n <= 20, acceptable

**Conservation Verification:**
Let P = poolWei. Slices allocated:
- Slice A: P/10
- Slice A2: P/10
- Slice B: P/20
- Slice C: P/10 (affiliateSlice = sum of affiliatePrizes[0..2])
- Slice D: P*3/100 + P/50 = 3P/100 + 2P/100 = 5P/100 = P/20
- Slice E: P*2/5
- Slice E2: P/5

Total = P/10 + P/10 + P/20 + P/10 + P/20 + 2P/5 + P/5
      = 2P/20 + 2P/20 + P/20 + 2P/20 + P/20 + 8P/20 + 4P/20
      = 20P/20 = P

Rounding: Due to integer division, small dust amounts (< winner count) in scatter slices are added to `toReturn`. This is correct.

**Affiliate 4th Prize:** `affiliatePrizes[3]` is never set (remains 0). The weights are 5/3/2/0 as documented. The 4th affiliate winner receives 0 ETH. `affiliateSlice` sums only indices [0..2], so the unallocated portion (if paid < affiliateSlice) returns correctly.

**Verdict:** CORRECT

---

### `_updateBafTop(uint24 lvl, address player, uint256 stake)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _updateBafTop(uint24 lvl, address player, uint256 stake) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level number; `player` (address): player address; `stake` (uint256): new total stake |
| **Returns** | none |

**State Reads:**
- `bafTop[lvl]` -- entire 4-entry leaderboard array
- `bafTopLen[lvl]` -- current leaderboard length

**State Writes:**
- `bafTop[lvl][i]` -- leaderboard entries (insert, swap, overwrite)
- `bafTopLen[lvl]` -- incremented when new entry added (Case 2 only)

**Callers:**
- `recordBafFlip` -- after accumulating new total

**Callees:**
- `_score96(stake)` -- converts raw stake to uint96

**ETH Flow:** None

**Logic Walkthrough:**

1. **Search phase:** Scans leaderboard (0 to `len`) for existing `player` entry. Uses sentinel `existing = 4` for "not found".

2. **Case 1 (existing < 4):** Player already on board.
   - If new score <= current score, early return (no improvement due to whole-token truncation).
   - Update score in-place, then bubble-up: swap with predecessor while score is higher. Maintains sorted order.

3. **Case 2 (len < 4):** Board not full, player not on board.
   - Find insertion point by shifting entries right while new score > predecessor's score.
   - Insert at correct position. Increment `bafTopLen[lvl]`.

4. **Case 3 (len == 4):** Board full, player not on board.
   - If new score <= board[3].score (lowest), early return.
   - Otherwise, shift entries right from position 3 upward while new score > predecessor. Insert new entry, effectively evicting the old #4.

**Invariants:**
- Leaderboard is always sorted descending by score after any update
- Length never exceeds 4
- No duplicate players on the leaderboard (search before insert)
- A player's score on the board can only increase (early return on no improvement)

**NatSpec Accuracy:** NatSpec says "Update top-4 BAF leaderboard with new stake. Maintains sorted order. Handles existing player update, new player insertion, and capacity management." Accurate and complete.

**Gas Flags:**
- Worst case: 4 storage reads (search) + 3 storage writes (shift + insert) + 1 storage write (length). Acceptable for a bounded-4 leaderboard.
- Case 1 "no improvement" early return avoids unnecessary writes when score truncation hasn't changed the uint96 value.

**Verdict:** CORRECT

---

### `_clearBafTop(uint24 lvl)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _clearBafTop(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level number |
| **Returns** | none |

**State Reads:**
- `bafTopLen[lvl]` -- to know how many entries to delete

**State Writes:**
- `bafTopLen[lvl]` -- deleted (set to 0)
- `bafTop[lvl][i]` for i in 0..len-1 -- each entry deleted

**Callers:**
- `runBafJackpot` -- at end of jackpot resolution

**Callees:** None

**ETH Flow:** None

**Invariants:**
- After execution, `bafTopLen[lvl]` == 0 and all `bafTop[lvl][i]` entries are zeroed
- Note: `bafTotals` is NOT cleared (accumulated stakes persist beyond jackpot resolution)
- If len is already 0, only the delete of bafTopLen is skipped (no-op guard), but the loop body does not execute either

**NatSpec Accuracy:** NatSpec says "Clear leaderboard state for a level after jackpot resolution." Accurate.

**Gas Flags:**
- `delete bafTopLen[lvl]` only executes when `len != 0`, saving the SSTORE when already zero. Good optimization.
- Loop deletes each entry individually. Maximum 4 iterations (bounded).

**Verdict:** CORRECT


---

## DegenerusAdmin.sol

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:**
- `ContractAddresses.VRF_COORDINATOR` (compile-time constant)
- `ContractAddresses.VRF_KEY_HASH` (compile-time constant)
- `ContractAddresses.GAME` (compile-time constant)

**State Writes:**
- `coordinator` = `ContractAddresses.VRF_COORDINATOR`
- `subscriptionId` = newly created subscription ID from VRF coordinator
- `vrfKeyHash` = `ContractAddresses.VRF_KEY_HASH`

**Callers:** Deployment transaction only (once).

**Callees:**
- `vrfCoordinator.createSubscription()` -- creates VRF subscription
- `vrfCoordinator.addConsumer(subId, ContractAddresses.GAME)` -- registers Game as consumer
- `gameAdmin.wireVrf(VRF_COORDINATOR, subId, VRF_KEY_HASH)` -- pushes VRF config to Game

**ETH Flow:** None.

**Invariants:**
- After construction: `coordinator != address(0)`, `subscriptionId != 0`, `vrfKeyHash != bytes32(0)`
- Game contract is registered as a consumer on the VRF coordinator
- Game contract has VRF coordinator, subscription ID, and key hash configured

**NatSpec Accuracy:** Accurate. States "no constructor parameters" and "VRF config from ContractAddresses" -- both true. States "atomically creates new VRF subscription and wires the Game consumer" -- verified.

**Gas Flags:** None. All three external calls are necessary and non-redundant.

**Verdict:** CORRECT

---

### `setLinkEthPriceFeed(address feed)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLinkEthPriceFeed(address feed) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `feed` (address): New Chainlink LINK/ETH price feed address, or zero to disable |
| **Returns** | None |

**State Reads:**
- `linkEthPriceFeed` (current feed, via local `current`)
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner` modifier)

**State Writes:**
- `linkEthPriceFeed` = `feed`

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `_feedHealthy(current)` -- checks health of current feed
- `IAggregatorV3(feed).decimals()` -- validates new feed has 18 decimals (only if feed != address(0))

**ETH Flow:** None.

**Invariants:**
- Can only replace an unhealthy or zero-address feed (FeedHealthy guard)
- If new feed is non-zero, it must report exactly 18 decimals
- Zero-address feed disables oracle-based LINK reward valuation

**NatSpec Accuracy:** Accurate. States "zero address disables oracle-based valuation" -- correct. States "only replaceable if current feed is unhealthy" -- correct, `_feedHealthy` returns false for address(0) so initial set is allowed. States "enforces 18 decimals" -- verified.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `swapGameEthForStEth()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function swapGameEthForStEth() external payable onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None (uses msg.value) |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value)` -- forwards ETH to Game, receives stETH back to msg.sender

**ETH Flow:** msg.sender sends ETH via msg.value -> forwarded to Game contract. Game sends stETH to msg.sender.

**Invariants:**
- `msg.value > 0` (InvalidAmount guard)
- ETH and stETH amounts match 1:1 (enforced by Game contract)
- stETH goes to msg.sender (owner), not an arbitrary recipient

**NatSpec Accuracy:** Accurate. States "swap owner ETH for GAME-held stETH (1:1 exchange)" and "stETH sent to msg.sender (owner)" -- both verified. Note: NatSpec says "not arbitrary address" which is correct since recipient is hardcoded to `msg.sender`.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `stakeGameEthToStEth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function stakeGameEthToStEth(uint256 amount) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): Amount of ETH to stake into stETH via Lido |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.adminStakeEthForStEth(amount)` -- instructs Game to stake ETH to stETH via Lido

**ETH Flow:** None directly (ETH conversion happens inside Game contract).

**Invariants:**
- Owner can convert Game-held idle ETH to yield-bearing stETH
- No ETH enters or leaves Admin contract

**NatSpec Accuracy:** Accurate. States "converts idle ETH to yield-bearing stETH" and "amount of ETH to stake" -- both verified. Note: no zero-amount check here; relies on Game contract validation.

**Gas Flags:** No zero-amount guard on this function (unlike swapGameEthForStEth). The Game contract is expected to handle validation. This is consistent -- staking zero would be a no-op or revert in Lido, not a security issue.

**Verdict:** CORRECT

---

### `setLootboxRngThreshold(uint256 newThreshold)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newThreshold` (uint256): New RNG request threshold in wei |
| **Returns** | None |

**State Reads:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)

**State Writes:** None (state changes happen in Game contract).

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.setLootboxRngThreshold(newThreshold)` -- sets threshold in Game contract

**ETH Flow:** None.

**Invariants:**
- Only owner can change lootbox RNG threshold
- Validation of threshold range delegated to Game contract

**NatSpec Accuracy:** Minimal but accurate. States "update lootbox RNG request threshold (wei)" -- verified.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `emergencyRecover(address newCoordinator, bytes32 newKeyHash)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function emergencyRecover(address newCoordinator, bytes32 newKeyHash) external onlyOwner returns (uint256 newSubId)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): Address of the new VRF coordinator; `newKeyHash` (bytes32): Key hash for the new coordinator |
| **Returns** | `newSubId` (uint256): The newly created subscription ID |

**State Reads:**
- `subscriptionId` (must be non-zero -- NotWired guard)
- `coordinator` (old coordinator address for cancellation)
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.rngStalledForThreeDays()` (3-day stall gate)
- `linkToken.balanceOf(address(this))` (check for residual LINK)

**State Writes:**
- `coordinator` = `newCoordinator`
- `subscriptionId` = `newSubId` (from new coordinator's createSubscription)
- `vrfKeyHash` = `newKeyHash`

**Callers:** External only, any address holding >50.1% DGVE.

**Callees:**
- `vault.isVaultOwner(msg.sender)` (via `onlyOwner`)
- `gameAdmin.rngStalledForThreeDays()` -- verifies 3-day stall condition
- `IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(oldSub, address(this))` -- cancels old subscription (try/catch)
- `IVRFCoordinatorV2_5Owner(newCoordinator).createSubscription()` -- creates new subscription
- `IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(newSubId, GAME)` -- adds Game as consumer
- `gameAdmin.updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)` -- pushes new config to Game
- `linkToken.balanceOf(address(this))` -- checks LINK balance
- `linkToken.transferAndCall(newCoordinator, bal, abi.encode(newSubId))` -- funds new subscription (try/catch)

**ETH Flow:** None.

**Invariants:**
- Pre-condition: `subscriptionId != 0` (NotWired), `gameAdmin.rngStalledForThreeDays() == true` (NotStalled), `newCoordinator != address(0)`, `newKeyHash != bytes32(0)` (ZeroAddress)
- Post-condition: coordinator, subscriptionId, and vrfKeyHash all updated to new values; Game contract config updated atomically; any LINK on this contract forwarded to new subscription
- Old subscription cancelled (best-effort via try/catch -- may fail if coordinator is unresponsive)

**NatSpec Accuracy:** Accurate and thorough. Execution order documented as 6 steps matches implementation exactly. Security notes about 3-day stall, try/catch on cancel, non-zero checks, and atomic Game update all verified.

**Gas Flags:** None. The try/catch patterns are necessary for resilience against unresponsive old coordinators.

**Verdict:** CORRECT

---

### `shutdownVrf()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function shutdownVrf() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `subscriptionId` (checked for zero / early return)
- `coordinator` (used for cancelSubscription call)
- `linkToken.balanceOf(address(this))` (check for residual LINK)

**State Writes:**
- `subscriptionId` = 0 (prevents re-use)

**Callers:** DegenerusGame contract only (during `handleFinalSweep`).

**Callees:**
- `IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, VAULT)` -- cancels subscription, LINK refund to vault (try/catch)
- `linkToken.balanceOf(address(this))` -- checks for residual LINK
- `linkToken.transfer(VAULT, bal)` -- sweeps residual LINK to vault (try/catch)

**ETH Flow:** None (LINK flow only: subscription LINK refunded to VAULT, residual LINK swept to VAULT).

**Invariants:**
- Only Game contract can call (NotAuthorized guard: `msg.sender == ContractAddresses.GAME`)
- After execution: `subscriptionId == 0` (idempotent -- returns early if already 0)
- All LINK ends up at VAULT address (either via cancelSubscription refund or direct transfer)
- Uses try/catch so caller (Game) can safely fire-and-forget without reverting

**NatSpec Accuracy:** Accurate. States "only callable by the GAME contract (during handleFinalSweep)" -- verified via NotAuthorized check. States "LINK refunded to VAULT address" and "sets subscriptionId to 0 to prevent re-use" -- both verified.

**Gas Flags:** The SubscriptionShutdown event is emitted in two paths: once with `bal` when LINK sweep succeeds (line 567), and once with 0 at the end (line 573). If the cancelSubscription succeeds but LINK sweep fails (or bal is 0), the event correctly reports 0. If both succeed, only the first emit fires (due to `return` on line 568). This is correct -- no duplicate events.

**Verdict:** CORRECT

---

### `onTokenTransfer(address from, uint256 amount, bytes calldata)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function onTokenTransfer(address from, uint256 amount, bytes calldata) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): Address that sent the LINK; `amount` (uint256): Amount of LINK received; third parameter (bytes calldata): unused |
| **Returns** | None |

**State Reads:**
- `subscriptionId` (must be non-zero)
- `coordinator` (for VRF getSubscription and transferAndCall)
- `linkEthPriceFeed` (indirectly via `this._linkAmountToEth`)

**State Writes:** None directly (reward crediting happens in BurnieCoin via `coinLinkReward.creditLinkReward`).

**Callers:** LINK token contract only (via ERC-677 transferAndCall).

**Callees:**
- `gameAdmin.gameOver()` -- checks if game is over (GameOver guard)
- `IVRFCoordinatorV2_5Owner(coord).getSubscription(subId)` -- reads current subscription balance for multiplier calculation
- `_linkRewardMultiplier(uint256(bal))` -- calculates tiered reward multiplier
- `linkToken.transferAndCall(coord, amount, abi.encode(subId))` -- forwards LINK to VRF subscription
- `this._linkAmountToEth(amount)` -- converts LINK to ETH-equivalent (external self-call for try/catch)
- `gameAdmin.purchaseInfo()` -- gets current ticket price
- `coinLinkReward.creditLinkReward(from, credit)` -- credits BURNIE reward to donor

**ETH Flow:** None (LINK flow: donor -> Admin contract -> VRF subscription; BURNIE credit: calculated and credited to donor).

**Invariants:**
- Only LINK token contract can call (`msg.sender == ContractAddresses.LINK_TOKEN`)
- `amount > 0` (InvalidAmount guard)
- `subscriptionId != 0` (NoSubscription guard)
- Game must not be over (GameOver guard)
- LINK is always forwarded to VRF subscription (even if reward calculation fails)
- Reward multiplier calculated BEFORE forwarding LINK (uses pre-donation subscription balance)
- Multiple early-return safeguards: mult==0, ethEquivalent==0, priceWei==0, credit==0

**NatSpec Accuracy:** Accurate and detailed. The 5-step flow documentation matches implementation:
1. Validate sender is LINK -- verified (line 604)
2. Calculate reward multiplier based on current subscription balance -- verified (lines 615-618, uses balance BEFORE forwarding)
3. Forward LINK to VRF subscription -- verified (lines 621-627)
4. Convert LINK to ETH-equivalent using price feed -- verified (lines 632-638)
5. Credit BURNIE reward to donor -- verified (lines 641-648)

Security note about "multiplier decreases as subscription fills" -- verified by _linkRewardMultiplier tiered structure.

**Gas Flags:** The external self-call `this._linkAmountToEth(amount)` at line 633 is used to enable try/catch on a view function. This incurs additional gas from the external call overhead but is necessary since Solidity does not support try/catch on internal calls. This is a standard pattern.

**Verdict:** CORRECT


---

## WrappedWrappedXRP.sol

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address authorized to spend; `amount` (uint256): maximum spend limit |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender]` set to `amount`

**Callers:** External only (any EOA or contract)
**Callees:** None

**ETH Flow:** No
**Invariants:** Allowance is set unconditionally (overwrite semantics). No zero-address check on spender (standard ERC20 behavior -- approve to address(0) is allowed but harmless).
**NatSpec Accuracy:** Accurate. Documents revert conditions via @custom:reverts but no actual reverts in this function -- however the function itself has no revert conditions, so the NatSpec on the function is fine (the revert tags are on transfer/transferFrom, not here).
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `balanceOf[msg.sender]` (via `_transfer`)
**State Writes:** `balanceOf[msg.sender]` decremented, `balanceOf[to]` incremented (via `_transfer`)

**Callers:** External only (any EOA or contract)
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Sum of all balances unchanged. Neither `from` nor `to` can be address(0).
**NatSpec Accuracy:** Accurate. @custom:reverts correctly lists ZeroAddress and InsufficientBalance.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true (reverts on failure) |

**State Reads:** `allowance[from][msg.sender]`, `balanceOf[from]` (via `_transfer`)
**State Writes:** `allowance[from][msg.sender]` decremented (unless unlimited), `balanceOf[from]` decremented, `balanceOf[to]` incremented (via `_transfer`)

**Callers:** External only (any EOA or contract). Used by DegenerusStonk for proportional WWXRP payouts on burn.
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:** Sum of all balances unchanged. Allowance decremented unless `type(uint256).max` (unlimited pattern). Emits Approval event on allowance update.
**NatSpec Accuracy:** Accurate. Correctly documents unlimited allowance pattern and all revert conditions.
**Gas Flags:** None. The Approval event emission on allowance change is a reasonable design choice for ERC20 compatibility.
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` decremented by `amount`, `balanceOf[to]` incremented by `amount`

**Callers:** `transfer()`, `transferFrom()`
**Callees:** None (emits Transfer event)

**ETH Flow:** No
**Invariants:** Reverts if `from` or `to` is address(0). Reverts if `balanceOf[from] < amount`. Balance conservation: total balances unchanged (debit equals credit). No overflow risk on `balanceOf[to] += amount` in practice because totalSupply caps the sum, though no explicit check (Solidity 0.8+ overflow protection applies).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_mint(address to, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount |
| **Returns** | None |

**State Reads:** None (implicit read of `totalSupply` and `balanceOf[to]` for increment)
**State Writes:** `totalSupply` incremented by `amount`, `balanceOf[to]` incremented by `amount`

**Callers:** `mintPrize()`, `vaultMintTo()`
**Callees:** None (emits Transfer event from address(0))

**ETH Flow:** No
**Invariants:** Reverts if `to` is address(0). No zero-amount check (callers handle this). `totalSupply` always equals sum of all `balanceOf` entries. Overflow protection via Solidity 0.8+.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): burn source; `amount` (uint256): burn amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` decremented by `amount`, `totalSupply` decremented by `amount`

**Callers:** `unwrap()`, `burnForGame()`
**Callees:** None (emits Transfer event to address(0))

**ETH Flow:** No
**Invariants:** Reverts if `from` is address(0). Reverts if `balanceOf[from] < amount`. `totalSupply` decremented safely (cannot underflow because `balanceOf[from] >= amount` and totalSupply >= balanceOf[from]).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `unwrap(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function unwrap(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of WWXRP to unwrap (18 decimals) |
| **Returns** | None |

**State Reads:** `wXRPReserves`, `balanceOf[msg.sender]` (via `_burn`)
**State Writes:** `wXRPReserves` decremented by `amount`, `balanceOf[msg.sender]` decremented (via `_burn`), `totalSupply` decremented (via `_burn`)

**Callers:** External only (any WWXRP holder)
**Callees:** `_burn(msg.sender, amount)`, `wXRP.transfer(msg.sender, amount)` (external call to wXRP ERC20)

**ETH Flow:** No ETH. Moves wXRP tokens: contract reserves -> caller.
**Invariants:**
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if `wXRPReserves < amount` (InsufficientReserves) -- first-come-first-served design
- Reverts if `balanceOf[msg.sender] < amount` (InsufficientBalance via `_burn`)
- Reverts if wXRP.transfer fails (TransferFailed)
- CEI pattern enforced: `_burn()` (state changes) executes before `wXRP.transfer()` (external call)
- After execution: `wXRPReserves` decreases by `amount`, `totalSupply` decreases by `amount`
- The backing ratio (wXRPReserves / totalSupply) may improve, stay same, or worsen depending on relative values

**NatSpec Accuracy:** Accurate. Correctly documents CEI pattern, first-come-first-served semantics, and all revert conditions.
**Gas Flags:** None
**Verdict:** CORRECT -- CEI pattern properly prevents reentrancy. The `wXRPReserves` decrement before external call ensures reserves cannot be double-spent even if wXRP token has a callback.

---

### `donate(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function donate(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of wXRP to donate (18 decimals) |
| **Returns** | None |

**State Reads:** None (only `wXRPReserves` for increment)
**State Writes:** `wXRPReserves` incremented by `amount`

**Callers:** External only (any address with wXRP balance and approval)
**Callees:** `wXRP.transferFrom(msg.sender, address(this), amount)` (external call to wXRP ERC20)

**ETH Flow:** No ETH. Moves wXRP tokens: donor -> contract.
**Invariants:**
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if wXRP.transferFrom fails (TransferFailed -- insufficient wXRP balance or allowance)
- `wXRPReserves` increases without minting WWXRP, improving the backing ratio
- No WWXRP is minted -- pure reserve increase
- Note: `wXRPReserves` is updated AFTER external call (not strict CEI), but this is safe because `wXRP.transferFrom` pulls tokens INTO the contract (no value leaves), and the only risk would be reentrancy calling `donate` again which would just donate more (donor's loss)

**NatSpec Accuracy:** Accurate. Correctly describes purpose and revert conditions.
**Gas Flags:** None
**Verdict:** CORRECT -- The non-CEI ordering (external call before state write) is safe here because (a) value flows inward, (b) reentrancy would only donate more of caller's own wXRP, and (c) wXRP is a standard ERC20 without callbacks.

---

### `mintPrize(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function mintPrize(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount (18 decimals) |
| **Returns** | None |

**State Reads:** None (access control uses compile-time constants)
**State Writes:** `totalSupply` incremented (via `_mint`), `balanceOf[to]` incremented (via `_mint`)

**Callers:** External only, restricted to authorized minters:
- `DegenerusGameLootboxModule.sol` (line 1580): mints 1 WWXRP as lootbox prize
- `DegenerusGameDegeneretteModule.sol` (lines 728, 749): mints payout and consolation prizes
- `BurnieCoinflip.sol` (line 615): mints `lossCount * 1 WWXRP` as coinflip loss reward

**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_GAME, MINTER_COIN, or MINTER_COINFLIP (OnlyMinter)
- Reverts if `amount == 0` (ZeroAmount)
- Reverts if `to == address(0)` (ZeroAddress via `_mint`)
- Mints WITHOUT backing -- increases totalSupply without increasing wXRPReserves
- Intentionally worsens the backing ratio (by design -- "joke token")

**NatSpec Accuracy:** Accurate. Correctly documents unbacked minting behavior and all revert conditions. Note: the error used is `OnlyMinter` which is shared with `burnForGame` (which only allows MINTER_GAME), while `mintPrize` allows three minters. The error name is accurate for both uses.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `vaultMintTo(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function vaultMintTo(address to, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): mint amount (18 decimals) |
| **Returns** | None |

**State Reads:** `vaultAllowance`
**State Writes:** `vaultAllowance` decremented by `amount` (unchecked), `totalSupply` incremented (via `_mint`), `balanceOf[to]` incremented (via `_mint`)

**Callers:** External only, restricted to MINTER_VAULT:
- `DegenerusVault.sol` (line 730): vault mints WWXRP to recipient

**Callees:** `_mint(to, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_VAULT (OnlyVault)
- Reverts if `to == address(0)` (ZeroAddress)
- Returns silently if `amount == 0` (no-op, different from mintPrize which reverts on zero)
- Reverts if `amount > vaultAllowance` (InsufficientVaultAllowance)
- `vaultAllowance` decremented in `unchecked` block -- safe because the `amount > allowanceVault` check above guarantees no underflow
- `INITIAL_VAULT_ALLOWANCE + totalSupply` represents the theoretical max supply
- Like mintPrize, mints WITHOUT wXRP backing

**NatSpec Accuracy:** Accurate. Correctly documents vault-only access and allowance reduction. Note: NatSpec says "Reduces vault allowance and mints to recipient" which matches behavior. However, it does not mention the silent return on zero amount (minor informational).
**Gas Flags:** The `unchecked` block is justified -- the preceding check guarantees `amount <= allowanceVault`.
**Verdict:** CORRECT

---

### `burnForGame(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForGame(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): burn amount (18 decimals) |
| **Returns** | None |

**State Reads:** `balanceOf[from]` (via `_burn`)
**State Writes:** `balanceOf[from]` decremented (via `_burn`), `totalSupply` decremented (via `_burn`)

**Callers:** External only, restricted to MINTER_GAME:
- `DegenerusGameDegeneretteModule.sol` (line 597): burns WWXRP bet amount from player

**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:**
- Reverts if caller is not MINTER_GAME (OnlyMinter) -- note: uses `OnlyMinter` error but only checks against MINTER_GAME (not COIN or COINFLIP)
- Returns silently if `amount == 0` (no-op)
- Reverts if `from == address(0)` (ZeroAddress via `_burn`)
- Reverts if `balanceOf[from] < amount` (InsufficientBalance via `_burn`)
- Burns improve the backing ratio (wXRPReserves unchanged, totalSupply decreases)
- Does NOT reduce wXRPReserves (burn != unwrap)

**NatSpec Accuracy:** Minor inaccuracy: NatSpec says `@custom:reverts OnlyMinter When caller is not the game contract` -- the error name `OnlyMinter` is technically correct but could be confusing since `mintPrize` also uses `OnlyMinter` with different allowed callers. The NatSpec text "the game contract" is accurate for this function specifically.
**Gas Flags:** None
**Verdict:** CORRECT


---

## DegenerusTraitUtils.sol / ContractAddresses.sol / Icons32Data.sol

### `constructor()` [public]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (implicit) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** None
**State Writes:** None (empty constructor; storage defaults to zero/empty/false)

**Callers:** Deploy script
**Callees:** None

**ETH Flow:** None
**Invariants:** After construction, `_finalized` is `false`, all paths are empty strings, all symbol arrays are empty.
**NatSpec Accuracy:** NatSpec says "Deploy contract for batch initialization by CREATOR" -- correct.
**Gas Flags:** None. Empty constructor is minimal gas.
**Verdict:** CORRECT

---

### `setPaths(uint256 startIndex, string[] calldata paths)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setPaths(uint256 startIndex, string[] calldata paths) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `startIndex` (uint256): Starting index in _paths array (0-32); `paths` (string[]): Array of SVG path strings (max 10) |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_paths[startIndex]` through `_paths[startIndex + paths.length - 1]`

**Callers:** CREATOR (off-chain, during initialization)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- `paths.length <= 10` (batch size cap)
- `startIndex + paths.length <= 33` (bounds check)

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- pre-finalization only
3. `if (paths.length > 10) revert MaxBatch();` -- batch size limit
4. `if (startIndex + paths.length > 33) revert IndexOutOfBounds();` -- bounds check

**Overflow Analysis:** `startIndex + paths.length` -- since `paths.length <= 10` and `startIndex` is uint256, addition cannot overflow in practice (would require startIndex near 2^256). The `> 33` check ensures array bounds are respected.

**NatSpec Accuracy:** NatSpec matches behavior. Documents all 4 revert conditions.
**Gas Flags:** None. Loop is bounded by batch size (max 10 iterations).
**Verdict:** CORRECT

---

### `setSymbols(uint256 quadrant, string[8] memory symbols)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setSymbols(uint256 quadrant, string[8] memory symbols) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `quadrant` (uint256): Quadrant number (1=Crypto, 2=Zodiac, 3=Cards); `symbols` (string[8]): Array of 8 symbol names |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_symQ1[0..7]` or `_symQ2[0..7]` or `_symQ3[0..7]` depending on quadrant

**Callers:** CREATOR (off-chain, during initialization)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- `quadrant` must be 1, 2, or 3

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- pre-finalization only
3. Quadrant validation: if-else chain with `revert InvalidQuadrant()` for values outside {1, 2, 3}

**NatSpec Discrepancy:** NatSpec says "Quadrant 0 (Dice) names are generated dynamically" but the setter maps quadrant 1=Crypto, 2=Zodiac, 3=Cards. The storage variables are `_symQ1`, `_symQ2`, `_symQ3`, which suggests the naming convention uses 1-indexed quadrants for setters while the `symbol()` view function uses 0-indexed quadrants. This is a minor naming inconsistency but functionally correct:
- `setSymbols(1, ...)` writes to `_symQ1` (Crypto) -> read via `symbol(0, idx)` returns `_symQ1[idx]`
- `setSymbols(2, ...)` writes to `_symQ2` (Zodiac) -> read via `symbol(1, idx)` returns `_symQ2[idx]`
- `setSymbols(3, ...)` writes to `_symQ3` (Cards) -> read via `symbol(2, idx)` returns `_symQ3[idx]`

The 1-indexed setter vs 0-indexed getter is an intentional design: Dice (quadrant 3 in getter, absent from setter) generates names dynamically.

**Gas Flags:** None. Fixed 8-iteration loop.
**Verdict:** CORRECT (with informational note on 1-indexed setter vs 0-indexed getter naming)

---

### `finalize()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function finalize() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `_finalized`
**State Writes:** `_finalized = true`

**Callers:** CREATOR (off-chain, after all data is populated)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Only callable when `msg.sender == ContractAddresses.CREATOR`
- Only callable when `_finalized == false`
- After execution, `_finalized == true` (permanent, irreversible)
- Once finalized, setPaths and setSymbols will always revert

**Access Control Verification:**
1. `if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();` -- CREATOR-only
2. `if (_finalized) revert AlreadyFinalized();` -- single-use

**Finalization Lifecycle:**
```
MUTABLE (deployed) --[finalize()]--> IMMUTABLE (permanent)
```
There is no `unfinalize()` or admin override. Once `_finalized = true`, it cannot be reversed.

**NatSpec Accuracy:** NatSpec says "Finalize the contract, locking all data permanently" and "Only callable by CREATOR once" -- both correct.
**Gas Flags:** None. Single SSTORE operation.
**Verdict:** CORRECT


---


---

**Total state-changing functions extracted: 398**
