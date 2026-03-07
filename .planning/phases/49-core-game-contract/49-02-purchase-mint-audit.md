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
