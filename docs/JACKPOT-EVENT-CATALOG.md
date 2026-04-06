# Jackpot Event Catalog (Post-Split)

This document catalogs every event emitted during jackpot operations in the Degenerus Protocol. Each entry includes the exact Solidity signature, field descriptions, emitting code paths, and cross-references to the [Jackpot Payout Reference](JACKPOT-PAYOUT-REFERENCE.md).

**Last verified against:** commit `f0dc4c99`

---

## JackpotModule Events

### A. JackpotTicketWinner

**Solidity signature:**

```solidity
event JackpotTicketWinner(
    address indexed winner,
    uint24 indexed level,
    uint8 indexed traitId,
    uint256 amount,
    uint256 ticketIndex
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 78

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the jackpot winner receiving ETH or BURNIE credit |
| `level` | `uint24` | Yes | Game level when the jackpot was triggered |
| `traitId` | `uint8` | Yes | Winning trait ID for the bucket this winner was drawn from (0-255, encodes quadrant + color + symbol) |
| `amount` | `uint256` | No | ETH (wei) or BURNIE (units) credited to the winner |
| `ticketIndex` | `uint256` | No | Index in `traitBurnTicket[level][traitId]` used for winner selection; `uint256.max` for deity virtual entries |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_processDailyEth` | JackpotModule | 1244 | Daily jackpot (days 1-5): each normal bucket winner with non-zero address |
| 2 | `_resolveTraitWinners` (payCoin=true) | JackpotModule | 1406 | Coin distribution path: each BURNIE winner with non-zero address |
| 3 | `_resolveTraitWinners` (payCoin=false, solo) | JackpotModule | 1439 | Solo bucket winner in early-burn/terminal paths (ETH via `_processSoloBucketWinner`) |
| 4 | `_resolveTraitWinners` (payCoin=false, normal) | JackpotModule | 1458 | Normal bucket winners in early-burn/terminal paths |
| 5 | `_awardDailyCoinToTraitWinners` | JackpotModule | 2213 | Near-future BURNIE coin winners (daily coin jackpot) |

**Cross-reference:** Payout Reference Sections 3 (Daily Normal), 5 (Daily Final), 6 (Early-Burn), 8 (Terminal), 11 (BURNIE Coin near-future)

**Note:** This is a unified event for both ETH and BURNIE payouts. The `amount` field contains ETH (wei) when emitted from paths 1, 3, 4, and BURNIE units when emitted from paths 2, 5. Consumers must differentiate by the emitting context (daily ETH vs coin jackpot stage).

---

### B. FarFutureCoinJackpotWinner

**Solidity signature:**

```solidity
event FarFutureCoinJackpotWinner(
    address indexed winner,
    uint24 indexed currentLevel,
    uint24 indexed winnerLevel,
    uint256 amount
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 69

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the BURNIE recipient (drawn from `ticketQueue`) |
| `currentLevel` | `uint24` | Yes | Game level when the jackpot ran |
| `winnerLevel` | `uint24` | Yes | Far-future level the winner's ticket was queued for (5-99 levels ahead of current) |
| `amount` | `uint256` | No | BURNIE credited via `coinflip.creditFlipBatch` |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_awardFarFutureCoinJackpot` | JackpotModule | 2314 | Each far-future coin winner found (up to `FAR_FUTURE_COIN_SAMPLES`=10 samples, one winner per sampled level) |

**Cross-reference:** Payout Reference Section 11 (BURNIE Coin far-future)

---

### C. AutoRebuyProcessed (JackpotModule)

**Solidity signature:**

```solidity
event AutoRebuyProcessed(
    address indexed player,
    uint24 targetLevel,
    uint32 ticketCount,
    uint256 ethSpent,
    uint256 remainder
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 59

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `player` | `address` | Yes | Address of the auto-rebuy recipient |
| `targetLevel` | `uint24` | No | Level tickets were purchased for (current+1 or current+2, 50/50 chance) |
| `ticketCount` | `uint32` | No | Number of tickets credited (includes 30% or 45% bonus when afKing active) |
| `ethSpent` | `uint256` | No | ETH spent on ticket purchases (moved to next/future pool) |
| `remainder` | `uint256` | No | ETH returned to `claimableWinnings` (reserved amount + dust from fractional tickets) |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_processAutoRebuy` | JackpotModule | 839 | Any jackpot ETH winner with auto-rebuy enabled (daily, early-burn, terminal, BAF ETH portion) |

**Cross-reference:** Payout Reference Sections 3, 5, 6, 8, 10 (all ETH-distributing jackpots when winner has auto-rebuy)

---

### D. RewardJackpotsSettled (JackpotModule declaration)

**Solidity signature:**

```solidity
event RewardJackpotsSettled(
    uint24 indexed lvl,
    uint256 futurePool,
    uint256 claimableDelta
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 92 (duplicate declaration for delegatecall ABI compatibility; emitted from AdvanceModule)

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `lvl` | `uint24` | Yes | Level being settled (indexed for `Advance` event correlation) |
| `futurePool` | `uint256` | No | Authoritative post-resolution `futurePrizePool` value |
| `claimableDelta` | `uint256` | No | Total ETH moved to `claimablePool` during resolution (BAF + affiliate + pool accounting) |

**Emitting paths:**

See AdvanceModule entry (Section G) -- emitted only from `_consolidatePoolsAndRewardJackpots`.

**Cross-reference:** Payout Reference Section 10 (BAF Jackpot)

---

## AdvanceModule Events

### E. Advance

**Solidity signature:**

```solidity
event Advance(uint8 stage, uint24 lvl);
```

**Declared:** `DegenerusGameAdvanceModule.sol` line 51

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `stage` | `uint8` | No | Stage constant identifying the phase of game progression |
| `lvl` | `uint24` | No | Current game level |

**Stage constants relevant to jackpot flow:**

| Constant | Value | Meaning |
|----------|-------|---------|
| `STAGE_ENTERED_JACKPOT` | 7 | Jackpot phase entered (level transition complete) |
| `STAGE_JACKPOT_COIN_TICKETS` | 9 | Call 2 completed: coin + ticket distribution done |
| `STAGE_JACKPOT_PHASE_ENDED` | 10 | All 5 jackpot days complete, level transitioning |
| `STAGE_JACKPOT_DAILY_STARTED` | 11 | Call 1 completed: daily ETH distribution done |

Other stages (not jackpot-specific): `STAGE_GAMEOVER` (0), `STAGE_RNG_REQUESTED` (1), `STAGE_TRANSITION_WORKING` (2), `STAGE_TRANSITION_DONE` (3), `STAGE_FUTURE_TICKETS_WORKING` (4), `STAGE_TICKETS_WORKING` (5), `STAGE_PURCHASE_DAILY` (6).

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `advanceGame` | AdvanceModule | 180 | Game over detected (`STAGE_GAMEOVER`) |
| 2 | `advanceGame` | AdvanceModule | 207 | Ticket processing working (`STAGE_TICKETS_WORKING`) |
| 3 | `advanceGame` | AdvanceModule | 249 | Ticket processing working (alternate path) |
| 4 | `advanceGame` | AdvanceModule | 429 | End of every `advanceGame` call (final stage emitted) |

**Cross-reference:** Payout Reference Section 13 (Two-Call Split stage machine)

**Note:** Path 4 (line 429) is the primary emit -- it fires at the end of every `advanceGame` call with the final stage reached. Paths 1-3 are early-break emits for specific stages that exit before reaching line 429.

---

### F. RewardJackpotsSettled (AdvanceModule)

**Solidity signature:**

```solidity
event RewardJackpotsSettled(
    uint24 indexed lvl,
    uint256 futurePool,
    uint256 claimableDelta
);
```

**Declared:** `DegenerusGameAdvanceModule.sol` line 52

**Field descriptions:**

(Same as JackpotModule declaration -- see Section D)

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_consolidatePoolsAndRewardJackpots` | AdvanceModule | 808 | After BAF + affiliate + pool accounting, only if `futurePrizePool` changed from storage or `claimableDelta != 0` |

**Cross-reference:** Payout Reference Sections 10 (BAF Jackpot), 12 (Pool Flow Summary)

---

## DecimatorModule Events

### G. DecBurnRecorded

**Solidity signature:**

```solidity
event DecBurnRecorded(
    address indexed player,
    uint24 indexed lvl,
    uint8 bucket,
    uint8 subBucket,
    uint256 effectiveAmount,
    uint256 newTotalBurn
);
```

**Declared:** `DegenerusGameDecimatorModule.sol` line 44

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `player` | `address` | Yes | Address of the player burning into the decimator |
| `lvl` | `uint24` | Yes | Game level of the burn |
| `bucket` | `uint8` | No | Denominator bucket used (2-12) |
| `subBucket` | `uint8` | No | Deterministic subbucket assigned (0 to bucket-1) |
| `effectiveAmount` | `uint256` | No | Burn amount after multiplier, capped at uint192 saturation |
| `newTotalBurn` | `uint256` | No | Player's updated cumulative burn for this level |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `decimatorBurn` | DecimatorModule | 177 | When a player's burn delta is non-zero (burn amount increased) |

**Cross-reference:** Payout Reference Section 9 (Decimator Jackpot)

---

### H. TerminalDecBurnRecorded

**Solidity signature:**

```solidity
event TerminalDecBurnRecorded(
    address indexed player,
    uint24 indexed lvl,
    uint8 bucket,
    uint8 subBucket,
    uint256 effectiveAmount,
    uint256 weightedAmount,
    uint256 timeMultBps
);
```

**Declared:** `DegenerusGameDecimatorModule.sol` line 665

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `player` | `address` | Yes | Address of the player burning into the terminal decimator |
| `lvl` | `uint24` | Yes | Game level (x00 level during death clock phase) |
| `bucket` | `uint8` | No | Denominator bucket (2-12, base from `TERMINAL_DEC_BUCKET_BASE`) |
| `subBucket` | `uint8` | No | Deterministic subbucket (0 to bucket-1) |
| `effectiveAmount` | `uint256` | No | Raw burn amount (before time multiplier) |
| `weightedAmount` | `uint256` | No | Burn after time multiplier application |
| `timeMultBps` | `uint256` | No | Time multiplier in basis points (higher = burned earlier in death clock) |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | Terminal decimator burn function | DecimatorModule | 767 | Each terminal decimator burn recording |

**Cross-reference:** Payout Reference Section 9 (Decimator Jackpot)

---

### I. AutoRebuyProcessed (DecimatorModule)

**Solidity signature:**

```solidity
event AutoRebuyProcessed(
    address indexed player,
    uint24 targetLevel,
    uint32 ticketsAwarded,
    uint256 ethSpent,
    uint256 remainder
);
```

**Declared:** `DegenerusGameDecimatorModule.sol` line 29

**Field descriptions:**

(Same semantics as JackpotModule declaration -- see Section C. Note: field name is `ticketsAwarded` here vs `ticketCount` in JackpotModule, but the ABI is identical.)

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | Decimator auto-rebuy handler | DecimatorModule | 400 | When a decimator claim triggers auto-rebuy (player has enabled auto-rebuy and claim has ticket conversion) |

**Cross-reference:** Payout Reference Section 9 (Decimator Jackpot)

---

## Event-to-Path Matrix

| Event | Daily (1-4) | Daily (5) | Early-Burn | Terminal | Decimator | BAF | BURNIE Coin |
|-------|:-----------:|:---------:|:----------:|:--------:|:---------:|:---:|:-----------:|
| `JackpotTicketWinner` | X | X | X | X | -- | -- | X (near) |
| `FarFutureCoinJackpotWinner` | -- | -- | -- | -- | -- | -- | X (far) |
| `AutoRebuyProcessed` (JackpotMod) | X | X | X | -- (*) | -- | X | -- |
| `AutoRebuyProcessed` (DecMod) | -- | -- | -- | -- | X | -- | -- |
| `Advance` | X | X | -- | -- | -- | -- | -- |
| `RewardJackpotsSettled` | -- | -- | -- | -- | -- | X | -- |
| `DecBurnRecorded` | -- | -- | -- | -- | X | -- | -- |
| `TerminalDecBurnRecorded` | -- | -- | -- | -- | X (**) | -- | -- |

**Legend:** X = emitted during this jackpot type. -- = not emitted.

(*) Terminal jackpot runs at game over where `gameOver = true`, so `_addClaimableEth` skips auto-rebuy. No `AutoRebuyProcessed` from terminal ETH path.

(**) `TerminalDecBurnRecorded` is emitted during terminal decimator burn recording at x00 levels, not at claim/resolution time. `DecBurnRecorded` is for standard (non-terminal) decimator burns.

---

## Cross-Consistency Check

Events referenced in `JACKPOT-PAYOUT-REFERENCE.md` and their catalog entries:

| Event in Payout Reference | Catalog Entry | Status |
|---------------------------|---------------|--------|
| `JackpotTicketWinner` (Sections 3, 5, 6, 8, 11) | A | Matched |
| `AutoRebuyProcessed` (Sections 3, 5, 6, 9, 10) | C, I | Matched |
| `FarFutureCoinJackpotWinner` (Section 11) | B | Matched |
| `RewardJackpotsSettled` (Section 10) | D, F | Matched |
| `DecBurnRecorded` (Section 9) | G | Matched |
| `TerminalDecBurnRecorded` (Section 9) | H | Matched |
| `Advance` (Section 13) | E | Matched |
| `PlayerCredited` (Section 10) | Not cataloged (*) | N/A |

(*) `PlayerCredited` is a general-purpose crediting event from `DegenerusGamePayoutUtils.sol`, not jackpot-specific. It fires when `_queueWhalePassClaimCore` has a remainder (rounding dust) and during various other crediting paths across the codebase.
