# Degenerus Protocol — Testing Best Practices

Reference for AI agents writing Foundry (Solidity) tests against the Degenerus Protocol.
Read this before writing any test. It will save you from the most common mistakes.

---

## Testing Philosophy: Play the Game

**Test the game by playing it, not by poking its internals.**

- Use real purchase flows to fund prize pools and earn tokens
- Advance through levels by buying tickets and completing daily cycles
- Earn BURNIE through coinflip resolution, not by pranking the COIN contract
- Accumulate claimable winnings through actual ticket processing and jackpots
- If you need to be at level N, skip there by playing through N levels with a helper
- Only use `vm.prank` for player identity (`vm.prank(buyer)`) and admin operations
  (`vm.prank(address(admin))`), not to bypass access control on internal contracts

**The only exceptions** where low-level access is acceptable:
- `vm.prank(address(admin))` for VRF coordinator management (admin-only)
- `vm.load()` for storage inspection to verify internal state (read-only)
- Direct mock calls like `mockVRF.fulfillRandomWords()` (VRF is external infrastructure)

---

## Table of Contents

1. [Environment & Toolchain](#1-environment--toolchain)
2. [Test File Boilerplate](#2-test-file-boilerplate)
3. [Protocol Deployment](#3-protocol-deployment)
4. [Available Contracts & References](#4-available-contracts--references)
5. [Actor Management](#5-actor-management)
6. [VRF / Randomness](#6-vrf--randomness) (daily cycle + mid-day lootbox RNG)
7. [Time Manipulation](#7-time-manipulation) (jackpot reset at 22:57 UTC)
8. [Purchases — All Types](#8-purchases--all-types) (ETH, BURNIE, whale, lazy, deity, lootbox)
8.5. [Quests](#85-quests)
9. [Advancing the Game — Realistic Flows](#9-advancing-the-game--realistic-flows) (skip-to-level, coinflip, decimator, redemption)
10. [Storage Inspection](#10-storage-inspection) (read-only verification)
11. [Testing Reverts](#11-testing-reverts)
12. [Testing Events](#12-testing-events)
13. [Invariant Testing](#13-invariant-testing)
14. [Fuzz Testing](#14-fuzz-testing)
15. [Common Gotchas](#15-common-gotchas)
16. [Trouble Log](#16-trouble-log) (append-only — log stuck/broken test experiences here)
17. [Running Tests](#17-running-tests)

---

## 1. Environment & Toolchain

| Setting | Value |
|---------|-------|
| Framework | Foundry (forge) |
| Solidity version | `0.8.34` |
| EVM target | `paris` |
| Optimizer | `via_ir = true`, 2 runs |
| Test directory | `test/fuzz/` (Foundry only reads this) |
| Source directory | `contracts/` |
| Gas limit | `30_000_000_000` (high, for multi-level game tests) |
| Fuzz runs | 1000 default, 10000 on `profile.deep` |
| Invariant depth | 128 default, 256 on `profile.deep` |

Config file: `foundry.toml`

**Hardhat tests** live in `test/unit/`, `test/integration/`, etc. but are a separate
test suite (JS/TS). This guide covers **Foundry tests only**.

---

## 2. Test File Boilerplate

Every Foundry test file follows this pattern:

```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title MyTest -- Brief description of what this tests
/// @notice Covers TICKET-XX (audit finding reference)
contract MyTest is DeployProtocol {

    function setUp() public {
        _deployProtocol();
        // Additional test-specific setup here
    }

    function testSomething() public {
        // ...
    }
}
```

**Key rules:**
- Always inherit `DeployProtocol` (not `Test` directly) — it deploys the full protocol
- Always call `_deployProtocol()` as the first line of `setUp()`
- Place file in `test/fuzz/` (or a subdirectory) — Foundry won't find it elsewhere
- Import production contracts from `../../contracts/`, never from stale copies
- Use `pragma solidity ^0.8.26;` (caret) for tests, not the exact `0.8.34`

---

## 3. Protocol Deployment

`DeployProtocol` is an abstract base contract at `test/fuzz/helpers/DeployProtocol.sol`.

Calling `_deployProtocol()` does:
1. Warps time to `block.timestamp = 86400` (matches build script's address prediction)
2. Deploys 5 mock contracts (nonces 1–5)
3. Deploys 23 protocol contracts (nonces 6–28) in exact order

**The deployment order is critical.** Contract addresses are predicted at build time
by `patchForFoundry.js` and baked into `ContractAddresses.sol`. If you deploy contracts
in a different order or add extra deployments before calling `_deployProtocol()`, all
addresses will be wrong and everything will revert silently.

**DO:**
```solidity
function setUp() public {
    _deployProtocol();              // Always first
    myHelper = new SomeHelper();    // Extra contracts AFTER
}
```

**DON'T:**
```solidity
function setUp() public {
    SomeHelper h = new SomeHelper(); // BAD: shifts all nonces
    _deployProtocol();               // All addresses will be wrong
}
```

After `_deployProtocol()`, all contract references are available as public fields:
- Mocks: `mockVRF`, `mockStETH`, `mockLINK`, `mockWXRP`, `mockFeed`
- Protocol: `game`, `coin`, `coinflip`, `vault`, `sdgnrs`, `dgnrs`, `admin`,
  `affiliate`, `jackpots`, `quests`, `deityPass`, `wwxrp`
- Modules: `mintModule`, `advanceModule`, `whaleModule`, `jackpotModule`,
  `decimatorModule`, `endgameModule`, `gameOverModule`, `lootboxModule`,
  `boonModule`, `degeneretteModule`

---

## 4. Available Contracts & References

### Mock Contracts (`contracts/mocks/`)

| Mock | Purpose | Key Test Methods |
|------|---------|-----------------|
| `MockVRFCoordinator` | Chainlink VRF v2.5 | `fulfillRandomWords(reqId, word)`, `lastRequestId()`, `fulfillRandomWordsRaw(reqId, consumer, word)` |
| `MockStETH` | Lido stETH | Standard ERC20 |
| `MockLinkToken` | LINK token | Standard ERC20 + `onTokenTransfer` |
| `MockWXRP` | Wrapped XRP | Standard ERC20 |
| `MockLinkEthFeed` | Price feed | Returns fixed price set in constructor |

### Key Interfaces to Import

```solidity
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
```

`MintPaymentKind` is an enum required for `purchase()` calls:
- `MintPaymentKind.DirectEth` — most common in tests

---

## 5. Actor Management

### Simple Tests (named actors)

```solidity
address buyer1;
address buyer2;

function setUp() public {
    _deployProtocol();
    buyer1 = makeAddr("buyer1");
    buyer2 = makeAddr("buyer2");
    vm.deal(buyer1, 50_000 ether);
    vm.deal(buyer2, 50_000 ether);
}

function testPurchase() public {
    vm.prank(buyer1);
    game.purchase{value: 1 ether}(buyer1, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
}
```

### Handler Tests (deterministic actor arrays)

Each handler uses a unique address range to prevent collisions when multiple
handlers are targeted in the same invariant test:

| Handler | Address Range | Purpose |
|---------|---------------|---------|
| `GameHandler` | `0xA0000+` | Core game ops |
| `FSMHandler` | `0xF0000+` | FSM state tracking |
| `WhaleHandler` | `0xB0000+` | Whale/deity operations |
| `RedemptionHandler` | `0xD0000+` | Burn/claim lifecycle |

**Pattern:**
```solidity
address[] public actors;
address internal currentActor;

modifier useActor(uint256 seed) {
    currentActor = actors[bound(seed, 0, actors.length - 1)];
    _;
}

constructor(DegenerusGame game_, uint256 numActors) {
    game = game_;
    for (uint256 i = 0; i < numActors; i++) {
        address actor = address(uint160(0xA0000 + i));
        actors.push(actor);
        vm.deal(actor, 100 ether);
    }
}
```

**Fund actors generously.** Gas-only tests need ~1 ETH. Purchase tests need 50–100 ETH
per actor to cover multiple purchases at varying price levels.

---

## 6. VRF / Randomness

The `MockVRFCoordinator` gives you full control over randomness. No real Chainlink
involved.

### Basic VRF Fulfillment

```solidity
// 1. Trigger a VRF request (usually via advanceGame)
game.advanceGame();

// 2. Get the request ID
uint256 reqId = mockVRF.lastRequestId();

// 3. Fulfill with a specific random word
mockVRF.fulfillRandomWords(reqId, 0xDEAD0001);

// 4. Drive advances until RNG lock clears
for (uint256 i = 0; i < 50; i++) {
    if (!game.rngLocked()) break;
    game.advanceGame();
}
```

### The `_completeDay()` Helper

Most tests that need to advance through days use this internal helper.
Copy it into your test contract:

```solidity
/// @dev Complete a full day: advanceGame -> VRF fulfill -> loop until unlocked.
function _completeDay(uint256 vrfWord) internal {
    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    mockVRF.fulfillRandomWords(reqId, vrfWord);
    for (uint256 i = 0; i < 50; i++) {
        if (!game.rngLocked()) break;
        game.advanceGame();
    }
}
```

### VRF Handler (for invariant tests)

Use `VRFHandler` from `test/fuzz/helpers/VRFHandler.sol`:

```solidity
import {VRFHandler} from "./helpers/VRFHandler.sol";

VRFHandler public vrfHandler;

function setUp() public {
    _deployProtocol();
    vrfHandler = new VRFHandler(mockVRF, game);
    targetContract(address(vrfHandler));
}
```

VRFHandler provides:
- `fulfillVrf(uint256 randomWord)` — fulfills latest pending request (no-ops if none/already fulfilled)
- `warpPastVrfTimeout()` — warps 18h+1s ahead (past the 12h retry timeout)
- `warpTime(uint256 delta)` — bounded warp `[1 min, 30 days]`

### Raw Fulfillment (bypassing request tracking)

For testing stale/replayed request IDs:

```solidity
mockVRF.fulfillRandomWordsRaw(staleId, address(game), randomWord);
```

This calls `rawFulfillRandomWords` on the consumer without checking the pending
request mapping. Useful for adversarial tests.

### Checking VRF State

```solidity
// Is a VRF request pending?
assertTrue(game.rngLocked(), "should be rngLocked after advanceGame");

// Has the request been fulfilled?
(, , bool fulfilled) = mockVRF.pendingRequests(reqId);
```

### Mid-Day Lootbox RNG Requests

The daily VRF cycle (section above) handles end-of-day randomness via `advanceGame()`.
**Mid-day RNG** is a separate flow triggered by `game.requestLootboxRng()` to resolve
pending lootbox purchases without waiting for the next daily cycle.

**Key differences from the daily VRF cycle:**

| | Daily VRF | Mid-Day Lootbox VRF |
|---|-----------|---------------------|
| Trigger | `advanceGame()` on new day | `game.requestLootboxRng()` |
| RNG lock | Sets `rngLockedFlag` | Does NOT set `rngLockedFlag` |
| Word storage | `rngWordCurrent` → processed via `advanceGame` loop | Written directly to `lootboxRngWordByIndex[index]` |
| After fulfillment | Must loop `advanceGame()` to clear lock | No follow-up calls needed |
| LINK required | No (native payment) | Yes (`MIN_LINK_FOR_LOOTBOX_RNG` balance check) |
| Pending ETH required | No | Yes (`lootboxRngPendingEth > 0` or `pendingBurnie >= threshold`) |
| Day requirement | Must be a new day vs `dailyIdx` | Must be same day AND `rngWordByDay[today] != 0` |
| 15-min pre-reset block | No | Yes (blocked within 15 min of next day boundary) |

**Prerequisites for mid-day RNG:**
1. Today's daily RNG must already be completed (`rngWordByDay[today] != 0`)
2. No other RNG request is in-flight (`rngRequestTime == 0`)
3. Game is NOT `rngLocked`
4. VRF subscription has LINK balance >= `MIN_LINK_FOR_LOOTBOX_RNG`
5. There is pending lootbox ETH or BURNIE (from purchases with lootbox amounts)
6. Not within 15 minutes of the next day boundary (to avoid colliding with daily jackpot)

### The `_setupForMidDayRng()` Helper

This is the standard setup used across tests. Copy it into your test contract:

```solidity
/// @dev Setup for mid-day lootbox RNG: complete two days, make a lootbox purchase,
///      fund VRF subscription with LINK.
function _setupForMidDayRng() internal returns (uint256 ts) {
    // Complete day 1
    _completeDay(0xDEAD0001);

    // Warp to day 2
    vm.warp(block.timestamp + 1 days);

    // Complete day 2 so rngWordByDay[day2] != 0
    _completeDay(0xDEAD0002);

    // Purchase WITH lootbox amount to create pending lootbox ETH
    address buyer = makeAddr("lootboxBuyer");
    vm.deal(buyer, 100 ether);
    vm.prank(buyer);
    game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

    // Fund VRF subscription with LINK (subscription 1 was created during deploy)
    mockVRF.fundSubscription(1, 100e18);

    ts = block.timestamp;
}
```

### Mid-Day RNG Request + Fulfillment

```solidity
_setupForMidDayRng();

uint48 indexBefore = game.lootboxRngIndexView();

// Trigger mid-day VRF request
game.requestLootboxRng();

// Fulfill — word is written DIRECTLY to lootboxRngWordByIndex (no advanceGame loop needed)
uint256 reqId = mockVRF.lastRequestId();
mockVRF.fulfillRandomWords(reqId, 0xBEEF);

// Verify the word was stored at the correct index
uint256 storedWord = game.lootboxRngWord(indexBefore);
assertEq(storedWord, 0xBEEF, "Mid-day word stored at correct lootbox index");
```

### lootboxRngIndex Tracking

Both daily and mid-day VRF requests share the `lootboxRngIndex` counter. Key rules:

| Event | Index Behavior |
|-------|---------------|
| Fresh daily request (`advanceGame` on new day) | Increments by 1 |
| Mid-day `requestLootboxRng()` | Increments by 1 |
| Timeout retry (12h+ stale request) | Does NOT increment |
| Coordinator swap | Does NOT change index |

```solidity
// Read the current lootbox RNG index
uint48 index = game.lootboxRngIndexView();

// Read the stored word at a specific index
uint256 word = game.lootboxRngWord(index);
```

### Mid-Day RNG Gotchas

1. **Must complete today's daily cycle first** — `requestLootboxRng()` requires
   `rngWordByDay[today] != 0`. If you skip the daily `advanceGame` + fulfill, the
   mid-day request will revert.

2. **Must fund VRF subscription with LINK** — Mid-day requests check LINK balance.
   Daily requests use native payment and don't need LINK.
   ```solidity
   mockVRF.fundSubscription(1, 100e18);  // subscription ID 1 from deploy
   ```

3. **Must have pending lootbox ETH** — Purchases with `lootboxAmt = 0` don't
   accumulate `lootboxRngPendingEth`. You need at least one purchase with a nonzero
   lootbox amount since the last mid-day RNG.

4. **No `advanceGame` loop after fulfillment** — Unlike daily VRF, mid-day fulfillment
   writes the word directly to `lootboxRngWordByIndex`. Don't loop `advanceGame` —
   it's unnecessary and may trigger unexpected state changes.

5. **15-minute pre-reset blackout** — `requestLootboxRng()` reverts if you're within
   15 minutes of the next day boundary (22:57 UTC). In tests, just don't warp to
   exactly the boundary edge.

6. **Zero-guard** — If VRF delivers `word = 0`, it's stored as `1` (same as daily).

---

## 7. Time Manipulation

### Day Boundaries — JACKPOT_RESET_TIME (22:57 UTC)

**This is the single most important thing to understand about time in this protocol.**

Days do NOT reset at midnight. They reset at **22:57 UTC** (82620 seconds from midnight).
This is `JACKPOT_RESET_TIME` in `GameTimeLib.sol`.

The day index is calculated as:
```
dayBoundary = (timestamp - 82620) / 86400
dayIndex = dayBoundary - DEPLOY_DAY_BOUNDARY + 1
```

### Deployment Timestamp

All tests start at `block.timestamp = 86400` (one day after epoch). This is set by
`_deployProtocol()` and must not be changed. At this timestamp:
- Day boundary = `(86400 - 82620) / 86400 = 0`
- Day index = `0 - 0 + 1 = 1` → **Day 1**

The next day boundary is at `ts = 82620 + 86400 = 169020`.

### Advancing to the Next Day

To cross into the next day, warp past the next jackpot reset time. From the
deployment timestamp (86400), the first day boundary crossing is at 169020:

```solidity
// From deploy time (86400), jump to day 2
vm.warp(block.timestamp + 1 days);  // 172800 > 169020, so crosses into day 2
```

**`+1 days` works from deploy time** because 86400 + 86400 = 172800 > 169020. But if
you're at an arbitrary timestamp, don't assume `+1 days` crosses a boundary. The safe
pattern is to warp to a known absolute timestamp:

```solidity
// Absolute day boundaries (guaranteed to be in the right day)
for (uint8 d = 1; d <= numDays; d++) {
    vm.warp(uint256(d) * 86400);      // each is past the jackpot reset for that day
    _completeDay(uint256(0xDEAD0000 + d));
}
```

### `advanceGame()` Day Gating

`advanceGame()` checks `_simulatedDayIndexAt(block.timestamp)` against `dailyIdx`.
If you're still in the same day, it takes the **mid-day path** (ticket draining only).
To trigger the **new-day path** (jackpot + VRF request), you must warp past the
next 22:57 UTC boundary.

Additionally, `_enforceDailyMintGate` has a time-based caller gate after the boundary:
- **Deity pass holders**: always allowed
- **Anyone**: allowed 30 minutes after reset (elapsed >= 1800s from day start)
- **Pass holders**: allowed 15 minutes after reset
- **DGVE majority**: always allowed via governance

In practice, warp well past the boundary (e.g., `+1 days` or absolute timestamps)
to avoid hitting these caller gates in tests.

### VRF Timeout

The VRF retry timeout is 12 hours. To test timeout behavior:

```solidity
vm.warp(block.timestamp + 13 hours);  // past the 12h timeout
```

Or use the VRFHandler:
```solidity
vrfHandler.warpPastVrfTimeout();      // warps 18h + 1s
```

### Bounded Time Warps (fuzz inputs)

```solidity
delta = bound(delta, 1 minutes, 30 days);
vm.warp(block.timestamp + delta);
```

### Important: Never warp backward

`vm.warp` sets absolute time. Going backward breaks game day tracking. Always
move forward.

---

## 8. Purchases — All Types

There are 6 distinct purchase entry points on `DegenerusGame`. Each has different
parameters, payment methods, and prerequisites.

### 8a. `purchase()` — ETH Ticket + Optional Lootbox

The most common operation. Buys tickets with ETH and optionally allocates ETH
to a lootbox.

```solidity
vm.prank(buyer);
game.purchase{value: totalCost}(
    buyer,              // recipient (address(0) = msg.sender)
    qty,                // ticket quantity (2 decimals: 400 = 4.00 tickets)
    lootboxAmt,         // ETH for lootbox (0 if none)
    bytes32(0),         // affiliate code (bytes32(0) = none)
    MintPaymentKind.DirectEth
);
```

**MintPaymentKind options:**
- `DirectEth` — pay entirely with `msg.value`
- `Claimable` — pay entirely from accrued claimable winnings (no ETH sent)
- `Combined` — pay with both ETH + claimable (grants a purchase bonus)

**Calculating cost:**
```solidity
(, , , , uint256 priceWei) = game.purchaseInfo();
uint256 ticketCost = (priceWei * qty) / 400;
uint256 totalCost = ticketCost + lootboxAmt;
```

**Bounded fuzz inputs:**
```solidity
qty = bound(qty, 100, 4000);
lootboxAmt = bound(lootboxAmt, 0, 2 ether);
```

**Guards before purchasing:**
```solidity
if (game.gameOver()) return;       // can't purchase after game over
if (game.rngLocked()) return;      // can't purchase during VRF resolution
if (totalCost > buyer.balance) return; // insufficient funds
```

**Quick helper:**
```solidity
function _buyTickets(address buyer, uint256 qty) internal {
    (, , , , uint256 priceWei) = game.purchaseInfo();
    uint256 cost = (priceWei * qty) / 400;
    vm.prank(buyer);
    game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth);
}
```

### 8b. `purchaseCoin()` — BURNIE Ticket + Optional Lootbox

Mirrors `purchase()` but pays with BURNIE tokens instead of ETH.

```solidity
vm.prank(buyer);
game.purchaseCoin(
    buyer,              // recipient
    ticketQuantity,     // ticket quantity (2 decimals)
    lootBoxBurnieAmt    // BURNIE amount for lootbox (18 decimals, 0 to skip)
);
```

**Prerequisite:** Buyer must have BURNIE balance. BURNIE is earned through gameplay
(coinflip, quest rewards, lootbox wins). In tests, you can seed BURNIE by:
- Running game cycles that award BURNIE
- Using `vm.prank(address(game))` to call BURNIE-minting functions if available

No `msg.value` required. No `MintPaymentKind` parameter.

### 8c. `purchaseBurnieLootbox()` — BURNIE-Only Lootbox

Low-EV lootbox paid with BURNIE only (no tickets).

```solidity
vm.prank(buyer);
game.purchaseBurnieLootbox(
    buyer,              // recipient
    burnieAmount        // BURNIE to burn (18 decimals)
);
```

### 8d. `purchaseWhaleBundle()` — Premium Multi-Level Package

Queues 400 tickets across 100 levels starting from current level, includes lootbox allocation.

```solidity
uint256 cost = 2.4 ether * qty;  // levels 0-3 price
// uint256 cost = 4 ether * qty; // levels 4+ price

vm.prank(buyer);
game.purchaseWhaleBundle{value: cost}(
    buyer,              // recipient
    qty                 // number of bundles (1-100)
);
```

**Pricing:**
- Levels 0–3: 2.4 ETH per bundle
- Levels 4+: 4 ETH per bundle (or discounted with boon)

**Fuzz bounds:** `qty = bound(qty, 1, 5);`

**What it does:** Queues 4 tickets for each of 100 future levels. Includes lootbox
(20% of price during presale, 10% after). Player stats are frozen until the game
reaches the frozen level.

### 8e. `purchaseLazyPass()` — 10-Level Auto-Advance Pass

Pays for automatic advancement across 10 levels.

```solidity
uint256 cost = 0.24 ether;  // levels 0-2 flat price

vm.prank(buyer);
game.purchaseLazyPass{value: cost}(buyer);
```

**Availability:** Levels 0–2 or x9 levels (9, 19, 29...), or with a valid lazy pass boon.

**Pricing:**
- Levels 0–2: flat 0.24 ETH
- Levels 3+: sum of per-level ticket prices across a 10-level window

### 8f. `purchaseDeityPass()` — Soulbound Deity NFT

Purchases a deity pass for a specific symbol (0–31), granting activity bonuses.

```solidity
vm.prank(buyer);
game.purchaseDeityPass{value: deityPrice}(
    buyer,
    symbolId            // 0-31: Q0 Crypto, Q1 Zodiac, Q2 Cards, Q3 Dice
);
```

**Note:** Only 32 deity passes exist total (one per symbol). Once minted, they are
soulbound and cannot be transferred.

### 8g. Opening Lootboxes

After a lootbox purchase, the lootbox must be opened once its VRF word is available:

```solidity
// lootboxIndex was recorded at purchase time
vm.prank(player);
game.openLootBox(player, lootboxIndex);
```

**Prerequisite:** `game.lootboxRngWord(lootboxIndex) != 0` — the VRF word for that
index must have been fulfilled (either via daily cycle or mid-day RNG).

### Purchase Type Summary

| Function | Payment | Tickets | Lootbox | Affiliate | Level Restriction |
|----------|---------|---------|---------|-----------|-------------------|
| `purchase()` | ETH / Claimable / Combined | Yes | Optional (ETH) | Yes | None |
| `purchaseCoin()` | BURNIE | Yes | Optional (BURNIE) | No | None |
| `purchaseBurnieLootbox()` | BURNIE | No | Yes (BURNIE) | No | None |
| `purchaseWhaleBundle()` | ETH | Yes (100 levels) | Included | No | None |
| `purchaseLazyPass()` | ETH | No | No | No | 0-2 or x9 levels |
| `purchaseDeityPass()` | ETH | No | No | No | None (32 max) |

---

## 8.5. Quests

Quests are managed by `DegenerusQuests` (standalone contract, not delegatecall).
All quest handler functions are **COIN-gated** — only callable via the BurnieCoin
contract as part of normal gameplay, not directly.

### Quest Lifecycle

1. **Roll:** Quests auto-roll during daily cycle (COIN calls `rollDailyQuest`)
   - Slot 0: always a fixed "deposit new ETH" quest
   - Slot 1: weighted-random quest from remaining types
2. **Progress:** Player actions trigger quest progress automatically:
   - ETH purchase → `handleMint(player, qty, true)`
   - BURNIE purchase → `handleMint(player, qty, false)`
   - Coinflip deposit/claim → `handleFlip(player, flipCredit)`
3. **Complete:** Progress accumulates until target met; streak increments once per day
4. **Streak:** Missing a day resets streak to zero (streak shields available for 3x misses)

### Testing Quests — Play the Game

Quest progress happens automatically when you perform game actions. Just play normally:

```solidity
// ETH purchase triggers quest progress for "deposit new ETH" quest (slot 0)
vm.prank(buyer);
game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth);
// Internally: purchase → COIN.handleMint → Quests.handleMint (quest progress updated)

// Coinflip actions trigger flip-related quest progress
vm.prank(buyer);
coinflip.depositCoinflip(buyer, flipAmount);
// On resolution: COIN flow → Quests.handleFlip (quest progress updated)
```

**To test streak mechanics:** Make purchases on consecutive days:
```solidity
for (uint256 d = 0; d < streakDays; d++) {
    vm.warp(block.timestamp + 1 days);
    _completeDay(uint256(keccak256(abi.encode(d))));

    // Make a purchase to trigger quest progress for this day
    vm.prank(buyer);
    game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth);
}
```

### Key Quest Rules

- **Auto-triggered:** All quest progress happens through normal gameplay actions
- **Version-gated progress:** Quest version bumps each day; stale progress auto-resets
- **Streak shields:** `useStreakShield()` prevents streak reset for up to 3 missed days
- **No ETH handling:** Quest contract holds no ETH and makes no external calls

---

## 9. Advancing the Game — Realistic Flows

### Core Principle

Every test should reach its target state by **playing the game forward** — buying
tickets, completing daily cycles, fulfilling VRF. This ensures all side effects
(quest progress, coinflip resolution, jackpot payouts, prize pool accumulation)
happen naturally, matching production behavior.

### The Daily Cycle

A complete day transition requires:
1. **Purchase tickets** (during purchase phase)
2. **Warp past the next jackpot reset** (22:57 UTC boundary)
3. **Call `advanceGame()`** (triggers VRF request if new day)
4. **Fulfill VRF** (via mock coordinator)
5. **Loop `advanceGame()`** until `!game.rngLocked()` (processes tickets, jackpots)

```solidity
/// @dev Complete one full day: advanceGame → VRF fulfill → drain rngLock.
function _completeDay(uint256 vrfWord) internal {
    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    mockVRF.fulfillRandomWords(reqId, vrfWord);
    for (uint256 i = 0; i < 50; i++) {
        if (!game.rngLocked()) break;
        game.advanceGame();
    }
}
```

### Skipping to a Level — By Playing Through

Use `_skipToLevel()` to reach any target level with realistic game state. This
purchases tickets, advances days, fulfills VRF, and processes jackpots — the
same path a live game takes. All prize pools, claimable winnings, coinflip
state, and quest progress accumulate naturally.

```solidity
/// @dev Skip to at least `targetLevel` by repeatedly purchasing + completing daily cycles.
///      Uses heavy purchases (4000 tickets + 1 ETH lootbox per day) to guarantee advancement.
///      After completion, the game is in PURCHASE phase at >= targetLevel with realistic state.
function _skipToLevel(uint24 targetLevel) internal {
    address whale = makeAddr("level_driver");
    vm.deal(whale, 10_000_000 ether);

    uint256 ts = block.timestamp;
    for (uint256 day = 0; day < 200 && game.level() < targetLevel; day++) {
        if (game.gameOver()) break;

        // Purchase heavily to fill prize pool and trigger level advancement
        if (!game.rngLocked()) {
            (, , , , uint256 priceWei) = game.purchaseInfo();
            uint256 ticketCost = (priceWei * 4000) / 400;
            uint256 totalCost = ticketCost + 1 ether; // tickets + lootbox
            if (totalCost <= whale.balance) {
                vm.prank(whale);
                game.purchase{value: totalCost}(
                    whale, 4000, 1 ether, bytes32(0), MintPaymentKind.DirectEth
                );
            }
        }

        // Advance to next day (past jackpot reset boundary)
        ts += 1 days;
        vm.warp(ts);

        // Complete the daily cycle (VRF request → fulfill → process)
        try game.advanceGame() {} catch { continue; }

        if (game.rngLocked()) {
            uint256 reqId = mockVRF.lastRequestId();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(day))));

            for (uint256 j = 0; j < 50; j++) {
                if (!game.rngLocked()) break;
                try game.advanceGame() {} catch { break; }
            }
        }
    }
}
```

**Using it:** Skip to level 4, then start your actual test from there:
```solidity
function setUp() public {
    _deployProtocol();
    _skipToLevel(4);
    // Game is now at level 4+ with realistic prize pools, processed tickets, etc.
}
```

### Playing with Multiple Actors

For tests that need diverse player state (different claimable balances,
different purchase histories, etc.), have multiple actors purchase across
multiple days:

```solidity
function _setupDiversePlayers(address[] memory players) internal {
    uint256 ts = block.timestamp;
    for (uint256 d = 0; d < 5; d++) {
        // Each player buys different amounts each day
        for (uint256 p = 0; p < players.length; p++) {
            if (game.rngLocked()) break;
            uint256 qty = 400 * (p + 1);  // 400, 800, 1200...
            (, , , , uint256 priceWei) = game.purchaseInfo();
            uint256 cost = (priceWei * qty) / 400;
            vm.prank(players[p]);
            game.purchase{value: cost}(
                players[p], qty, 0, bytes32(0), MintPaymentKind.DirectEth
            );
        }

        ts += 1 days;
        vm.warp(ts);
        _completeDay(uint256(keccak256(abi.encode(d))));
    }
    // Players now have varied ticket counts, claimable winnings, quest progress
}
```

### Realistic Lootbox Flow

Purchase with lootbox amount → wait for VRF → open:

```solidity
// 1. Purchase with lootbox allocation
vm.prank(buyer);
game.purchase{value: 2 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);
// Records lootbox at current lootboxRngIndex

// 2. Record the lootbox index assigned to this purchase
uint48 myLootboxIndex = game.lootboxRngIndexView();
// (Index is the one active at purchase time, before any VRF request increments it)

// 3. Complete a daily cycle (VRF fulfillment writes word for the lootbox index)
vm.warp(block.timestamp + 1 days);
_completeDay(0xDEAD);

// 4. Open the lootbox (now that the RNG word is available)
vm.prank(buyer);
game.openLootBox(buyer, myLootboxIndex);
```

### Realistic Coinflip Flow

Coinflip is BURNIE-denominated. Players earn BURNIE through ticket processing
rewards, then stake it in coinflip:

```solidity
// 1. Play through enough days to earn BURNIE via ticket processing rewards
_skipToLevel(2);  // Several days of play accumulates BURNIE for players

// 2. Check player's BURNIE balance (earned through gameplay)
uint256 burnieBalance = coin.balanceOf(player);

// 3. Deposit into coinflip
if (burnieBalance >= 100 ether) {  // MIN deposit = 100 BURNIE
    vm.prank(player);
    coinflip.depositCoinflip(player, 100 ether);
}

// 4. Next daily cycle resolves the flip
vm.warp(block.timestamp + 1 days);
_completeDay(0xBEEF);

// 5. Claim winnings (mints BURNIE to player based on roll)
vm.prank(player);
coinflip.claimCoinflips(player, coinflip.previewClaimCoinflips(player));
```

### Realistic Whale Bundle Flow

`purchaseWhaleBundle()` and `claimWhalePass()` are **two different things**:

- **`purchaseWhaleBundle()`** — Immediately queues 4 tickets per level across 100
  future levels. No claim step needed. The tickets get processed as the game
  naturally advances through those levels.
- **`claimWhalePass()`** — Converts accumulated `whalePassClaims` (earned from
  jackpot wins or large lootbox payouts) into queued tickets. This is a reward
  mechanism, not related to the bundle purchase.

**Testing a whale bundle purchase:**
```solidity
// Buy whale bundle — tickets are queued immediately for 100 levels
vm.prank(buyer);
game.purchaseWhaleBundle{value: 2.4 ether}(buyer, 1);  // 2.4 ETH at levels 0-3

// Verify: as the game advances, whale tickets get processed at each level
// Other players' purchases and daily cycles advance the game naturally
```

**Testing whale pass claims (earned through gameplay):**
```solidity
// 1. Play through levels — jackpot wins and large lootbox payouts accumulate whalePassClaims
_skipToLevel(5);

// 2. Check if any player earned whale pass claims from jackpots/lootboxes
uint256 claims = game.whalePassClaimAmount(player);

// 3. If they have claims, convert them to queued tickets
if (claims > 0) {
    vm.prank(player);
    game.claimWhalePass(player);
}
```

### Realistic Decimator Flow

The decimator window opens at level 4. Players burn BURNIE for a chance at the
decimator jackpot:

```solidity
// 1. Play to level 4+ to open decimator window
_skipToLevel(4);

// 2. Verify window is open
(bool open, ) = game.decWindow();
assertTrue(open, "Decimator window should be open");

// 3. Player needs BURNIE (earned through gameplay from _skipToLevel)
uint256 burnieBalance = coin.balanceOf(player);

// 4. Burn BURNIE in decimator
if (burnieBalance >= 1000 ether) {  // DECIMATOR_MIN = 1000 BURNIE
    vm.prank(player);
    coin.decimatorBurn(player, 1000 ether);
}

// 5. Complete the level to resolve decimator jackpot
_skipToLevel(5);

// 6. Check if player won and claim
(uint256 payout, bool winner) = game.decClaimable(player, 4);
if (winner) {
    vm.prank(player);
    game.claimDecimatorJackpot(4);
}
```

### Realistic sDGNRS Redemption Flow

sDGNRS is a soulbound token — players can only get it through specific game
mechanics (not transfers). The burn/redemption flow:

```solidity
// 1. Play through several levels (sDGNRS accumulates through game mechanics)
_skipToLevel(5);

// 2. Check sDGNRS balance
uint256 sdgnrsBalance = sdgnrs.balanceOf(player);

// 3. Burn sDGNRS (submits gambling claim, waits for resolution)
if (sdgnrsBalance > 0) {
    vm.prank(player);
    sdgnrs.burn(sdgnrsBalance);
}

// 4. Complete a daily cycle to resolve the redemption period
vm.warp(block.timestamp + 1 days);
_completeDay(0xFEED);

// 5. Claim resolved redemption (roll-based payout)
vm.prank(player);
sdgnrs.claimRedemption();
```

### VRF Coordinator Swap

For testing stall recovery:

```solidity
function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
    newVRF = new MockVRFCoordinator();
    uint256 newSubId = newVRF.createSubscription();
    newVRF.addConsumer(newSubId, address(game));
    vm.prank(address(admin));
    game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
}
```

After a swap, use `newVRF` (not `mockVRF`) for subsequent fulfillments.

---

## 10. Storage Inspection

For verifying internal state that has no public getter, read storage slots directly.

### Verify Slot Numbers First

Run this before using any slot constant:
```bash
forge inspect DegenerusGame storage-layout
```

### Common Slot Constants

```solidity
// DegenerusGame packed slots
uint256 constant SLOT_PACKED_0 = 0;          // timing/flags (packed)
uint256 constant SLOT_PACKED_1 = 1;          // price/buffer (packed)
uint256 constant SLOT_RNG_WORD_CURRENT = 4;  // rngWordCurrent (uint256)
uint256 constant SLOT_VRF_REQUEST_ID = 5;    // vrfRequestId (uint256)
uint256 constant TICKET_QUEUE_SLOT = 15;     // ticket queue mapping
uint256 constant TICKETS_OWED_PACKED_SLOT = 16;
uint256 constant PRIZE_POOLS_PACKED_SLOT = 3;

// StakedDegenerusStonk
uint256 constant SLOT_PENDING_BURNIE = 10;
uint256 constant SLOT_PERIOD_INDEX = 14;
uint256 constant SLOT_PERIOD_BURNED = 15;
uint256 constant SLOT_SUPPLY_SNAPSHOT = 13;

// Bit masks for packed slot 0
uint256 constant LEVEL_SHIFT = 144;          // uint24 at byte offset 18
uint256 constant LEVEL_MASK = 0xFFFFFF;
```

### Reading a Full-Slot Value

```solidity
function _readVrfRequestId() internal view returns (uint256) {
    return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
}
```

### Reading a Packed Field

```solidity
/// @dev Read level (uint24) from packed slot 0, bytes [18:21].
function _readLevel() internal view returns (uint24) {
    uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
    return uint24(packed >> LEVEL_SHIFT);
}

/// @dev Read rngRequestTime (uint48) from packed slot 0, bytes [12:18].
function _readRngRequestTime() internal view returns (uint48) {
    uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
    return uint48(packed >> 96);
}
```

### Reading a Mapping Slot

For `mapping(uint24 => TicketQueue)` at base slot N:
```solidity
bytes32 mapSlot = keccak256(abi.encode(uint256(key), uint256(TICKET_QUEUE_SLOT)));
uint256 value = uint256(vm.load(address(game), mapSlot));
```

### Important

- **Always verify slots** against `forge inspect` output before using them.
  Storage layout can change if contract fields are reordered.
- **Solidity packs right-to-left** within a slot. The first declared field in a
  packed group occupies the lowest bytes.

---

## 11. Testing Reverts

### Standard Pattern

```solidity
vm.expectRevert();
game.someFunction();
```

### With Specific Error Selector

```solidity
vm.expectRevert(DegenerusGameStorage.E.selector);
game.someFunction();
```

### Testing Access Control

```solidity
vm.prank(address(0xdead));  // random unauthorized address
vm.expectRevert();
game.rawFulfillRandomWords(reqId, words);
```

### Try-Catch (in handlers / when you expect mixed success/failure)

```solidity
vm.prank(currentActor);
try game.purchase{value: cost}(currentActor, qty, 0, bytes32(0), MintPaymentKind.DirectEth) {
    ghost_successfulPurchases++;
} catch {}
```

Use `try/catch` in **handlers** (invariant tests) — never `vm.expectRevert`.
The fuzzer needs to continue through failures.

---

## 12. Testing Events

This project does **not** use `vm.expectEmit`. Instead, events are captured via
`vm.recordLogs()` and parsed manually:

```solidity
vm.recordLogs();

vm.prank(actor);
someContract.someAction();

Vm.Log[] memory logs = vm.getRecordedLogs();
bytes32 targetSig = keccak256("EventName(address,uint256,bool)");

for (uint256 i = 0; i < logs.length; i++) {
    if (logs[i].topics[0] == targetSig) {
        // Decode indexed params from topics[1..], non-indexed from data
        (uint256 amount, bool flag) = abi.decode(logs[i].data, (uint256, bool));
        // Assert on decoded values
    }
}
```

This is more verbose than `vm.expectEmit` but gives you access to the decoded
values for ghost variable tracking in handlers.

---

## 13. Invariant Testing

Invariant tests prove properties hold across **all possible sequences** of
handler calls. The Foundry fuzzer calls handler functions in random order with
random inputs.

### Architecture: Test → Handler → Ghost Variables → Invariant Assertions

```
┌─────────────────────┐     targets     ┌──────────────────┐
│  InvariantTest.sol  │ ──────────────> │  Handler.sol     │
│  (extends Deploy)   │                 │  (extends Test)  │
│                     │                 │                  │
│  invariant_xxx() ───┤  reads ghosts   │  ghost_xxx ◄─────│── updated during actions
│  invariant_yyy() ───┤ <────────────── │  ghost_yyy       │
└─────────────────────┘                 └──────────────────┘
```

### File Naming Convention

- Invariant tests: `test/fuzz/invariant/MyProperty.inv.t.sol`
- Handlers: `test/fuzz/handlers/MyHandler.sol`

### Invariant Test Boilerplate

```solidity
contract MyInvariant is DeployProtocol {
    MyHandler public handler;

    function setUp() public {
        _deployProtocol();
        handler = new MyHandler(game, mockVRF, 10);
        targetContract(address(handler));  // Only fuzz this handler
    }

    /// @notice Property: X never decreases
    function invariant_xNeverDecreases() public view {
        assertEq(handler.ghost_xDecreaseCount(), 0, "X decreased");
    }
}
```

### Handler Boilerplate

```solidity
contract MyHandler is Test {
    DegenerusGame public game;

    // Ghost variables — public so invariant test can read them
    uint256 public ghost_totalX;
    uint256 public ghost_violationCount;

    // Call counters — useful for debugging coverage
    uint256 public calls_action1;
    uint256 public calls_action2;

    // Actor management
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, uint256 numActors) {
        game = game_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xMY000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    function action1(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        calls_action1++;

        // Guard: skip if game state prevents this action
        if (game.gameOver()) return;
        if (game.rngLocked()) return;

        // Bound fuzz inputs
        amount = bound(amount, 1, 1000);

        // Snapshot state before
        uint256 before = /* ... */;

        // Try the action (never revert in handlers!)
        vm.prank(currentActor);
        try game.someAction(amount) {
            ghost_totalX += amount;

            // Check property inline
            uint256 after_ = /* ... */;
            if (after_ < before) ghost_violationCount++;
        } catch {}
    }
}
```

### Key Invariant Testing Rules

1. **`fail_on_revert = false`** — handlers must use `try/catch`, not `vm.expectRevert`
2. **Ghost variables track violations** — don't `assert` inside handlers
3. **Early returns** for invalid states — don't let the fuzzer waste depth on no-ops
4. **Bound all fuzz inputs** — unbounded values cause massive revert rates
5. **Use unique address ranges** per handler — prevents actor collisions
6. **Register handlers with `targetContract()`** — fuzzer only calls targeted contracts
7. **Multiple handlers** can be targeted in one invariant test:

```solidity
targetContract(address(gameHandler));
targetContract(address(vrfHandler));
targetContract(address(whaleHandler));
```

---

## 14. Fuzz Testing

Standard fuzz tests use parametric inputs but run a single scenario per input.

### Naming Convention

- Fuzz test functions: `testFuzz_description(uint256 x, ...)`
- Concrete test functions: `testDescription()`

**Note:** Foundry treats any `test` function with parameters as a fuzz test.

### Bounding Inputs

Always bound fuzz inputs to realistic ranges:

```solidity
function testFuzz_purchaseQty(uint256 qty) public {
    qty = bound(qty, 100, 4000);
    // ...
}
```

Common bounds used in this project:

| Input | Lower | Upper | Rationale |
|-------|-------|-------|-----------|
| `qty` (tickets) | 100 | 4000 | Min mint qty / max per tx |
| `lootboxAmt` | 0 | 2 ether | Reasonable lootbox range |
| `timeDelta` | 1 minutes | 30 days | Meaningful time progression |
| `randomWord` | (unbounded) | (unbounded) | Full uint256 entropy space |
| `actorSeed` | 0 | actors.length - 1 | Actor array index |

### Fuzz + VRF Combination

When fuzz-testing VRF-dependent outcomes, use the fuzz input as the VRF word:

```solidity
function testFuzz_vrfOutcome(uint256 vrfWord) public {
    _buyTickets(buyer, 4000);
    vm.warp(block.timestamp + 1 days);
    _completeDay(vrfWord);
    // Assert properties that must hold for ANY random word
}
```

### Diverse Seeds for Multiple VRF Calls

When completing multiple days, use distinct seeds:

```solidity
for (uint256 d = 0; d < numDays; d++) {
    vm.warp(block.timestamp + 1 days);
    _completeDay(uint256(keccak256(abi.encode(d, baseSeed))));
}
```

---

## 15. Common Gotchas

### 1. Deploying contracts before `_deployProtocol()`

Any `new` call before `_deployProtocol()` shifts the deployer nonce and breaks
all address predictions. All protocol contracts will get wrong addresses.

### 2. Forgetting `vm.prank` before user calls

`purchase()`, `burn()`, and other user-facing functions check `msg.sender`.
Without `vm.prank`, the test contract itself is `msg.sender`, which may have
unexpected permissions or balances.

### 3. Not draining `rngLocked` after VRF fulfillment

After `mockVRF.fulfillRandomWords()`, the game may still be `rngLocked`.
You **must** loop `advanceGame()` until `!game.rngLocked()` or subsequent
purchases/actions will revert:

```solidity
for (uint256 i = 0; i < 50; i++) {
    if (!game.rngLocked()) break;
    game.advanceGame();
}
```

### 4. Using stale `reqId` after coordinator swap

After a VRF coordinator swap, `mockVRF.lastRequestId()` returns the old
coordinator's last ID. Use the **new** coordinator's `lastRequestId()`.

### 5. Not warping time for daily advancement

`advanceGame()` is gated by time-of-day checks. If you don't warp at least
1 day forward, it may no-op or revert.

### 6. Asserting inside handlers

Handlers are called by the invariant fuzzer. If you `assert` or `revert` inside
a handler, the entire invariant run may stop or behave unexpectedly with
`fail_on_revert = false`. Track violations in ghost variables instead.

### 7. Price changes between levels

`purchaseInfo()` returns the current price. When the game advances a level,
the price changes. If you pre-compute cost and then advance, the cost may be
stale.

### 8. The `try/catch` swallows details

In handlers, `try {} catch {}` hides revert reasons. If debugging, temporarily
change to `catch (bytes memory reason)` and log the reason.

### 9. Storage slot drift

If a contract's storage layout changes (fields added/removed/reordered),
hardcoded slot constants will be wrong. Always verify with:
```bash
forge inspect ContractName storage-layout
```

### 10. Admin-only functions need `vm.prank(address(admin))`

Functions like `updateVrfCoordinatorAndSub` are admin-gated. Use:
```solidity
vm.prank(address(admin));
game.updateVrfCoordinatorAndSub(...);
```

### 11. Don't bypass access control — play through instead

Functions like `sdgnrs.transferFromPool()` are game-gated. Instead of pranking as
the game contract, trigger the flow that naturally calls these functions. For example,
to get sDGNRS to a player, have them earn it through ticket processing and jackpot
wins by playing through levels with `_skipToLevel()`.

If you absolutely must seed state for a focused unit test, document why:
```solidity
// EXCEPTION: Seeding sDGNRS directly because this test isolates burn math only
vm.prank(address(game));
sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, recipient, amount);
```

### 12. Lootbox resolution needs funded VRF subscription

Mid-day lootbox RNG requests require the VRF subscription to have LINK balance.
Fund it if testing lootbox resolution:
```solidity
mockVRF.fundSubscription(subId, 100 ether);
```

---

## 16. Trouble Log

When a test gets stuck, reverts unexpectedly, or takes hours to debug, **add an
entry here** so the next person (or AI) doesn't repeat the same mistake. This
section is append-only — never remove entries, only add.

### Format

```
#### TROUBLE-NNN: Short title
- **Symptom:** What you observed (revert message, hang, wrong value, etc.)
- **Cause:** What was actually wrong
- **Fix:** What you changed to make it work
- **Lesson:** One-line rule to avoid this in the future
```

### Entries

*(Add new entries below this line. Number sequentially.)*

---

## 17. Running Tests

### All Foundry tests (default profile)

```bash
forge test
```

### Specific test file

```bash
forge test --match-path test/fuzz/VRFCore.t.sol
```

### Specific test function

```bash
forge test --match-test testVrfTimeoutRetry
```

### With verbose output (show logs, traces)

```bash
forge test -vvvv --match-test testVrfTimeoutRetry
```

### Deep profile (10x more runs)

```bash
FOUNDRY_PROFILE=deep forge test
```

### Invariant tests only

```bash
forge test --match-path "test/fuzz/invariant/*"
```

### Check storage layout

```bash
forge inspect DegenerusGame storage-layout
forge inspect StakedDegenerusStonk storage-layout
```

### Gas snapshot

```bash
forge snapshot --match-path test/fuzz/SomeGasTest.t.sol
```

---

## Quick Reference: Copy-Paste Snippets

### Reusable helpers (copy into your test contract)

```solidity
/// @dev Complete one full day: advanceGame → VRF fulfill → drain rngLock.
function _completeDay(uint256 vrfWord) internal {
    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    mockVRF.fulfillRandomWords(reqId, vrfWord);
    for (uint256 i = 0; i < 50; i++) {
        if (!game.rngLocked()) break;
        game.advanceGame();
    }
}

/// @dev Skip to at least `targetLevel` by purchasing + completing daily cycles.
function _skipToLevel(uint24 targetLevel) internal {
    address whale = makeAddr("level_driver");
    vm.deal(whale, 10_000_000 ether);
    uint256 ts = block.timestamp;
    for (uint256 day = 0; day < 200 && game.level() < targetLevel; day++) {
        if (game.gameOver()) break;
        if (!game.rngLocked()) {
            (, , , , uint256 priceWei) = game.purchaseInfo();
            uint256 totalCost = (priceWei * 4000) / 400 + 1 ether;
            if (totalCost <= whale.balance) {
                vm.prank(whale);
                game.purchase{value: totalCost}(
                    whale, 4000, 1 ether, bytes32(0), MintPaymentKind.DirectEth
                );
            }
        }
        ts += 1 days;
        vm.warp(ts);
        try game.advanceGame() {} catch { continue; }
        if (game.rngLocked()) {
            uint256 reqId = mockVRF.lastRequestId();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(day))));
            for (uint256 j = 0; j < 50; j++) {
                if (!game.rngLocked()) break;
                try game.advanceGame() {} catch { break; }
            }
        }
    }
}

/// @dev Buy tickets for a player.
function _buyTickets(address buyer, uint256 qty) internal {
    (, , , , uint256 priceWei) = game.purchaseInfo();
    uint256 cost = (priceWei * qty) / 400;
    vm.prank(buyer);
    game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth);
}

/// @dev Buy tickets with lootbox for a player.
function _buyWithLootbox(address buyer, uint256 qty, uint256 lootboxEth) internal {
    (, , , , uint256 priceWei) = game.purchaseInfo();
    uint256 cost = (priceWei * qty) / 400 + lootboxEth;
    vm.prank(buyer);
    game.purchase{value: cost}(buyer, qty, lootboxEth, bytes32(0), MintPaymentKind.DirectEth);
}

/// @dev Setup for mid-day lootbox RNG (see section 6 for details).
function _setupForMidDayRng() internal returns (uint256 ts) {
    _completeDay(0xDEAD0001);
    vm.warp(block.timestamp + 1 days);
    _completeDay(0xDEAD0002);
    address buyer = makeAddr("lootboxBuyer");
    vm.deal(buyer, 100 ether);
    vm.prank(buyer);
    game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);
    mockVRF.fundSubscription(1, 100e18);
    ts = block.timestamp;
}
```

### Minimal test — purchase + daily cycle

```solidity
contract MinimalExample is DeployProtocol {
    address buyer;

    function setUp() public {
        _deployProtocol();
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
    }

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function testBasicCycle() public {
        // Play: buy tickets
        vm.prank(buyer);
        game.purchase{value: 1 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);

        // Advance past jackpot reset boundary
        vm.warp(block.timestamp + 1 days);

        // Complete the daily cycle
        _completeDay(0xCAFE);

        // Assert
        assertFalse(game.rngLocked(), "should be unlocked");
    }
}
```

### Test starting at a specific level

```solidity
contract LevelFourTest is DeployProtocol {
    address buyer;

    function setUp() public {
        _deployProtocol();
        _skipToLevel(4);
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
    }

    function testDecimatorOpensAtLevel4() public {
        (bool open, ) = game.decWindow();
        assertTrue(open, "Decimator should be open at level 4");
    }

    // ... _skipToLevel and _completeDay helpers from above ...
}
```

### Minimal invariant test

```solidity
// test/fuzz/invariant/MyProperty.inv.t.sol
contract MyPropertyInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;

    function setUp() public {
        _deployProtocol();
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
    }

    function invariant_totalDepositedNonNegative() public view {
        assertTrue(gameHandler.ghost_totalDeposited() >= 0);
    }
}
```
