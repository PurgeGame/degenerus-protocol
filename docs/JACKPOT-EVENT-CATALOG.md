# Jackpot Event Catalog (Post-Split)

This document catalogs every event emitted during jackpot operations in the Degenerus Protocol. Each entry includes the exact Solidity signature, field descriptions, emitting code paths, and cross-references to the [Jackpot Payout Reference](JACKPOT-PAYOUT-REFERENCE.md).

**Last verified against:** commit `fa2b9c39`

---

## JackpotModule Events

### A. JackpotEthWin

**Solidity signature:**

```solidity
event JackpotEthWin(
    address indexed winner,
    uint24 indexed level,
    uint16 indexed traitId,
    uint256 amount,
    uint256 entryIndex
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 63

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the jackpot winner receiving ETH credit |
| `level` | `uint24` | Yes | Game level when the jackpot was triggered |
| `traitId` | `uint16` | Yes | Winning trait ID for the bucket; sentinel values ≥256 indicate non-trait sources (e.g. `BAF_TRAIT_SENTINEL` = 420) |
| `amount` | `uint256` | No | ETH (wei) credited to the winner |
| `entryIndex` | `uint256` | No | Index in `lvlTraitEntry[level][traitId]` used for winner selection (0 for BAF) |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_handleSoloBucketWinner` | JackpotModule | 1424 | Solo bucket winner in daily ETH distribution (ETH portion via `_processSoloBucketWinner`) |
| 2 | `_payNormalBucket` | JackpotModule | 1470 | Normal bucket winners in daily ETH distribution |
| 3 | `runBafJackpot` | JackpotModule | 2028 | BAF large winner: ETH half of split payout |
| 4 | `runBafJackpot` | JackpotModule | 2060 | BAF small winner (even index): 100% ETH payout |

**Cross-reference:** Payout Reference Sections 3 (Daily Normal), 5 (Daily Final), 6 (Early-Burn), 8 (Terminal), 10 (BAF Jackpot)

---

### B. JackpotTicketWin

**Solidity signature:**

```solidity
event JackpotTicketWin(
    address indexed winner,
    uint24 indexed entryLevel,
    uint16 indexed traitId,
    uint32 entryCount,
    uint24 sourceLevel,
    uint256 entryIndex,
    bool roundedUp
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 78

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the entry winner |
| `entryLevel` | `uint24` | Yes | Level the awarded entries are for (typically sourceLevel+1) |
| `traitId` | `uint16` | Yes | Winning trait ID for the bucket (sentinel ≥256 for non-trait sources, e.g. BAF) |
| `entryCount` | `uint32` | No | Number of entries credited to the winner |
| `sourceLevel` | `uint24` | No | Jackpot level that generated this entry award |
| `entryIndex` | `uint256` | No | Index in the burn entry pool used for winner selection (0 for BAF) |
| `roundedUp` | `bool` | No | True iff the BAF Bernoulli sub-roll incremented the whole-ticket count |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_runEarlyBirdLootboxJackpot` | JackpotModule | 692 | Early-bird lootbox ticket winners (called from `payDailyJackpot`) |
| 2 | `_distributeTicketsToBucket` | JackpotModule | 994 | Daily and carryover lootbox ticket distribution (called via `_distributeTicketJackpot` from `payDailyJackpotCoinAndTickets` and `payDailyJackpot`) |
| 3 | `runBafJackpot` | JackpotModule | 2014 | BAF small winner lootbox: immediate ticket award |
| 4 | `runBafJackpot` | JackpotModule | 2038 | BAF small winner (odd index): 100% lootbox payout |

**Cross-reference:** Payout Reference Sections 3 (Daily Normal), 5 (Daily Final), 6 (Early-Burn), 10 (BAF Jackpot)

---

### C. JackpotFlipWin

**Solidity signature:**

```solidity
event JackpotFlipWin(
    address indexed winner,
    uint24 indexed level,
    uint8 indexed traitId,
    uint256 amount,
    uint256 entryIndex
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 89

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the FLIP recipient |
| `level` | `uint24` | Yes | Game level when the FLIP jackpot ran |
| `traitId` | `uint8` | Yes | Winning trait ID for the bucket |
| `amount` | `uint256` | No | FLIP units credited via `coinflip.creditFlip` |
| `entryIndex` | `uint256` | No | Index in the burn entry pool used for winner selection |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_awardDailyCoinToTraitWinners` | JackpotModule | 1653 | Near-future FLIP winners (daily FLIP jackpot, trait-matched) |

**Cross-reference:** Payout Reference Section 11 (FLIP Jackpot near-future)

---

### E. JackpotWhalePassWin

**Solidity signature:**

```solidity
event JackpotWhalePassWin(
    address indexed winner,
    uint24 indexed level,
    uint256 halfPassCount
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 100

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address receiving whale pass credit |
| `level` | `uint24` | Yes | Game level when the whale pass was awarded |
| `halfPassCount` | `uint256` | No | Number of half-whale-passes credited (ETH spent / `HALF_WHALE_PASS_PRICE`) |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_handleSoloBucketWinner` | JackpotModule | 1436 | Solo bucket winner: 25% of payout routed to whale passes (via `_processSoloBucketWinner`) |
| 2 | `runBafJackpot` | JackpotModule | 2044 | BAF large winner: lootbox half exceeds `LOOTBOX_CLAIM_THRESHOLD`, deferred as whale pass claim |

**Cross-reference:** Payout Reference Sections 3-5 (Daily solo bucket), 10 (BAF Jackpot large winner)

---

### F. FarFutureFlipJackpotWinner

**Solidity signature:**

```solidity
event FarFutureFlipJackpotWinner(
    address indexed winner,
    uint24 indexed currentLevel,
    uint24 indexed winnerLevel,
    uint256 amount
);
```

**Declared:** `DegenerusGameJackpotModule.sol` line 53

**Field descriptions:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `winner` | `address` | Yes | Address of the FLIP recipient (drawn from `ticketQueue`) |
| `currentLevel` | `uint24` | Yes | Game level when the jackpot ran |
| `winnerLevel` | `uint24` | Yes | Far-future level the winner's ticket was queued for (5-99 levels ahead of current) |
| `amount` | `uint256` | No | FLIP credited via `coinflip.creditFlipBatch` |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_awardFarFutureCoinJackpot` | JackpotModule | 1730 | Each far-future FLIP winner found (up to `FAR_FUTURE_FLIP_SAMPLES`=10 samples, one winner per sampled level) |

**Cross-reference:** Payout Reference Section 11 (FLIP Jackpot far-future)

---

## AdvanceModule Events

### G. Advance

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
| `STAGE_JACKPOT_ETH_RESUME` | 8 | Call 2 completed: resumed ETH distribution (mid buckets) |
| `STAGE_JACKPOT_COIN_TICKETS` | 9 | Call 2 completed: coin + ticket distribution done |
| `STAGE_JACKPOT_PHASE_ENDED` | 10 | All 5 jackpot days complete, level transitioning |
| `STAGE_JACKPOT_DAILY_STARTED` | 11 | Call 1 completed: daily ETH distribution done |

Other stages (not jackpot-specific): `STAGE_GAMEOVER` (0), `STAGE_RNG_REQUESTED` (1), `STAGE_TRANSITION_WORKING` (2), `STAGE_TRANSITION_DONE` (3), `STAGE_FUTURE_TICKETS_WORKING` (4), `STAGE_TICKETS_WORKING` (5), `STAGE_PURCHASE_DAILY` (6).

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `advanceGame` | AdvanceModule | 184 | Game over detected (`STAGE_GAMEOVER`) |
| 2 | `advanceGame` | AdvanceModule | 211 | Ticket processing working (`STAGE_TICKETS_WORKING`) |
| 3 | `advanceGame` | AdvanceModule | 253 | Ticket processing working (alternate path) |
| 4 | `advanceGame` | AdvanceModule | 440 | End of every `advanceGame` call (final stage emitted) |

**Cross-reference:** Payout Reference Section 13 (Two-Call Split stage machine)

**Note:** Path 4 (line 440) is the primary emit -- it fires at the end of every `advanceGame` call with the final stage reached. Paths 1-3 are early-break emits for specific stages that exit before reaching line 440.

---

### H. RewardJackpotsSettled

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

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `lvl` | `uint24` | Yes | Level being settled (indexed for `Advance` event correlation) |
| `futurePool` | `uint256` | No | Authoritative post-resolution `futurePrizePool` value |
| `claimableDelta` | `uint256` | No | Total ETH moved to `claimablePool` during resolution (BAF + affiliate + pool accounting) |

**Emitting paths:**

| # | Function | File | Line | Condition |
|---|----------|------|------|-----------|
| 1 | `_consolidatePoolsAndRewardJackpots` | AdvanceModule | 804 | After BAF + affiliate + pool accounting completes |

**Cross-reference:** Payout Reference Sections 10 (BAF Jackpot), 12 (Pool Flow Summary)

---

## DecimatorModule Events

### I. DecBurnRecorded

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
| 1 | `recordDecBurn` | DecimatorModule | 187 | When a player's burn delta is non-zero (burn amount increased) |

**Cross-reference:** Payout Reference Section 9 (Decimator Jackpot)

---

### J. TerminalDecBurnRecorded

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

**Declared:** `DegenerusGameDecimatorModule.sol` line 676

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
| 1 | `recordTerminalDecBurn` | DecimatorModule | 778 | Each terminal decimator burn recording |

**Cross-reference:** Payout Reference Section 9 (Decimator Jackpot)

---

## Event-to-Path Matrix

| Event | Daily (1-4) | Daily (5) | Early-Burn | Terminal | Decimator | BAF | FLIP Jackpot |
|-------|:-----------:|:---------:|:----------:|:--------:|:---------:|:---:|:------------:|
| `JackpotEthWin` | X | X | X | X | -- | X | -- |
| `JackpotTicketWin` | X | X | X | -- | -- | X | -- |
| `JackpotFlipWin` | -- | -- | -- | -- | -- | -- | X (near) |
| `JackpotWhalePassWin` | X | X | X | X | -- | X | -- |
| `FarFutureFlipJackpotWinner` | -- | -- | -- | -- | -- | -- | X (far) |
| `Advance` | X | X | -- | -- | -- | -- | -- |
| `RewardJackpotsSettled` | -- | -- | -- | -- | -- | X | -- |
| `DecBurnRecorded` | -- | -- | -- | -- | X | -- | -- |
| `TerminalDecBurnRecorded` | -- | -- | -- | -- | X (*) | -- | -- |

**Legend:** X = emitted during this jackpot type. -- = not emitted.

(*) `TerminalDecBurnRecorded` is emitted during terminal decimator burn recording at x00 levels, not at claim/resolution time. `DecBurnRecorded` is for standard (non-terminal) decimator burns.

---

## Cross-Consistency Check

Events referenced in `JACKPOT-PAYOUT-REFERENCE.md` and their catalog entries:

| Event in Payout Reference | Catalog Entry | Status |
|---------------------------|---------------|--------|
| `JackpotEthWin` (Sections 3, 5, 6, 8, 10) | A | Matched |
| `JackpotTicketWin` (Sections 3, 5, 6, 10) | B | Matched |
| `JackpotFlipWin` (Section 11) | C | Matched |
| `JackpotWhalePassWin` (Sections 3, 5, 10) | E | Matched |
| `FarFutureFlipJackpotWinner` (Section 11) | F | Matched |
| `RewardJackpotsSettled` (Section 10) | H | Matched |
| `DecBurnRecorded` (Section 9) | I | Matched |
| `TerminalDecBurnRecorded` (Section 9) | J | Matched |
| `Advance` (Section 13) | G | Matched |
| `PlayerCredited` (Section 10) | Not cataloged (*) | N/A |

(*) `PlayerCredited` is a general-purpose crediting event from `DegenerusGamePayoutUtils.sol`, not jackpot-specific. It fires when `_queueWhalePassClaimCore` has a remainder (rounding dust) and during various other crediting paths across the codebase.
