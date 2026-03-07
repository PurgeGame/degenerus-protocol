# DegenerusGame.sol -- Purchase & Mint Payment Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines audited:** 386-1111
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

All purchase entry points and mint payment processing. These are the primary ETH ingress paths. Players purchase tickets (ETH or BURNIE), lootboxes, whale bundles, lazy passes, and deity passes. Internal helpers handle payment validation, prize pool splits, and delegatecall to mint/whale modules.

**Key constants:**
- `PURCHASE_TO_FUTURE_BPS = 1000` (10% to futurePrizePool, 90% to nextPrizePool)
- `TICKET_SCALE = 100` (1 ticket = 100 scaled units)
- `PRICE_COIN_UNIT = 1000 ether` (BURNIE price conversion)
- `MintPaymentKind: { DirectEth: 0, Claimable: 1, Combined: 2 }`

## Function Audit

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
**Invariants:** Buyer resolved. Symbol ID 0-31 enforced in WhaleModule. Max 24 deity passes (one per symbol per quadrant). WhaleModule validates no duplicate symbol ownership.
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

### `_revertDelegate(bytes)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _revertDelegate(bytes memory reason) private pure` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `reason` (bytes): error data from failed delegatecall |
| **Returns** | never returns (always reverts) |

**State Reads:** none
**State Writes:** none

**Callers:** All delegatecall wrappers: `_purchaseFor`, `purchaseCoin`, `purchaseBurnieLootbox`, `_purchaseWhaleBundleFor`, `_purchaseLazyPassFor`, `_purchaseDeityPassFor`, `onDeityPassTransfer`, `_recordMintDataModule`, and all other delegatecall patterns in the contract
**Callees:** none

**ETH Flow:** None. Pure revert propagation.
**Invariants:** If `reason.length == 0`, reverts with generic `E()` error. Otherwise, uses assembly to bubble up the original revert data preserving custom error selectors and revert strings from module code.
**NatSpec Accuracy:** ACCURATE. Correctly describes delegatecall error propagation and assembly usage.
**Gas Flags:** Assembly block is marked `"memory-safe"`. The `revert(add(32, reason), mload(reason))` pattern is standard for error bubbling -- skips the 32-byte length prefix of the bytes array to revert with raw error data.
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

## Delegatecall Dispatch Table

All delegatecall dispatches from purchase-related functions in DegenerusGame.sol:

| Caller Function | Target Module | Target Function | Selector | Pattern |
|----------------|---------------|-----------------|----------|---------|
| `_purchaseFor` | GAME_MINT_MODULE | `IDegenerusGameMintModule.purchase` | `purchase.selector` | Ticket + lootbox ETH/claimable purchase |
| `purchaseCoin` | GAME_MINT_MODULE | `IDegenerusGameMintModule.purchaseCoin` | `purchaseCoin.selector` | BURNIE ticket + lootbox purchase |
| `purchaseBurnieLootbox` | GAME_MINT_MODULE | `IDegenerusGameMintModule.purchaseBurnieLootbox` | `purchaseBurnieLootbox.selector` | Low-EV BURNIE lootbox |
| `_purchaseWhaleBundleFor` | GAME_WHALE_MODULE | `IDegenerusGameWhaleModule.purchaseWhaleBundle` | `purchaseWhaleBundle.selector` | 100-level whale bundle |
| `_purchaseLazyPassFor` | GAME_WHALE_MODULE | `IDegenerusGameWhaleModule.purchaseLazyPass` | `purchaseLazyPass.selector` | 10-level lazy pass |
| `_purchaseDeityPassFor` | GAME_WHALE_MODULE | `IDegenerusGameWhaleModule.purchaseDeityPass` | `purchaseDeityPass.selector` | Deity pass (symbol-bound) |
| `onDeityPassTransfer` | GAME_WHALE_MODULE | `IDegenerusGameWhaleModule.handleDeityPassTransfer` | `handleDeityPassTransfer.selector` | Deity pass ERC721 transfer callback |
| `_recordMintDataModule` | GAME_MINT_MODULE | `IDegenerusGameMintModule.recordMintData` | `recordMintData.selector` | Mint data recording + BURNIE reward |

**Notes:**
- All targets are compile-time constants from `ContractAddresses.sol` (immutable after deployment)
- All dispatches follow identical error handling: `if (!ok) _revertDelegate(data)`
- MintModule dispatches additionally include a callback: module calls `address(this).recordMint()` which invokes `_processMintPayment` for ETH handling
- WhaleModule dispatches handle their own ETH validation and prize pool splitting internally (no callback to Game)

## ETH Mutation Path Map

All ETH flow paths through purchase functions:

| Path | Source | Destination | Trigger | Handler |
|------|--------|-------------|---------|---------|
| ETH ticket purchase | msg.value | nextPrizePool (90%) + futurePrizePool (10%) | `purchase()` with DirectEth | `_processMintPayment` -> `recordMint` pool split |
| Claimable ticket purchase | claimableWinnings[player] | nextPrizePool (90%) + futurePrizePool (10%) | `purchase()` with Claimable | `_processMintPayment` deducts claimable, credits pools |
| Combined ticket purchase | msg.value + claimableWinnings[player] | nextPrizePool (90%) + futurePrizePool (10%) | `purchase()` with Combined | `_processMintPayment` uses ETH first, claimable for rest |
| BURNIE ticket purchase | none (BURNIE burned) | no ETH flow | `purchaseCoin()` | MintModule burns BURNIE via COIN contract |
| BURNIE lootbox purchase | none (BURNIE burned) | no ETH flow | `purchaseBurnieLootbox()` | MintModule burns BURNIE via COIN contract |
| ETH lootbox (within purchase) | msg.value portion | nextPrizePool + futurePrizePool (90/10 or 40/40/20 presale) | `purchase()` lootBoxAmount > 0 | MintModule lootbox ETH split (audited in Phase 50) |
| Whale bundle | msg.value | nextPrizePool (30%@L0, 5%@L1+) + futurePrizePool (70%@L0, 95%@L1+) | `purchaseWhaleBundle()` | WhaleModule pool split |
| Lazy pass | msg.value | nextPrizePool + futurePrizePool (split via LAZY_PASS_TO_FUTURE_BPS) | `purchaseLazyPass()` | WhaleModule pool split |
| Deity pass | msg.value | prize pools via WhaleModule | `purchaseDeityPass()` | WhaleModule pool split |
| Deity pass transfer | none (BURNIE burned from sender) | no ETH flow | `onDeityPassTransfer()` | WhaleModule burns 5 ETH worth of BURNIE |

**Conservation property:** Every ETH wei entering through `msg.value` in a purchase function is either:
1. Split into `nextPrizePool` + `futurePrizePool` (the primary path), or
2. Retained as DirectEth overpay in the contract balance (documented intentional behavior -- overpay is held by contract)

**Claimable conservation:** Every wei deducted from `claimableWinnings[player]` is matched by an equal deduction from `claimablePool`, maintaining the pool invariant.

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | -- |
| CONCERN | 0 | -- |
| INFORMATIONAL | 2 | See below |

### Informational

**1. DirectEth overpay retention**
- **Location:** `_processMintPayment`, DirectEth branch
- **Description:** When `msg.value > amount` for DirectEth purchases, the excess ETH remains in the contract. NatSpec documents this as intentional ("overage ignored for accounting"). The excess contributes to the contract's ETH balance but is not tracked in any pool variable.
- **Impact:** None. The ETH is effectively a donation to the protocol's balance. UIs should prevent overpay.
- **Severity:** INFORMATIONAL

**2. Defensive data.length check in `_recordMintDataModule`**
- **Location:** `_recordMintDataModule`, line 1109
- **Description:** After a successful delegatecall, `data.length == 0` is checked. For a function returning `uint256`, the ABI guarantees 32 bytes of return data on success. This check is unreachable in normal operation.
- **Impact:** None. 3 gas for the length check. Defensive pattern is acceptable.
- **Severity:** INFORMATIONAL

### Audit Totals

- **Functions audited:** 15 (12 in Task 1 + 3 in Task 2)
- **Verdicts:** 15 CORRECT, 0 CONCERN, 0 BUG
- **Delegatecall dispatch paths:** 8
- **ETH mutation paths:** 10
- **NatSpec accuracy:** All 15 functions verified accurate (private helpers have no NatSpec, which is acceptable)
