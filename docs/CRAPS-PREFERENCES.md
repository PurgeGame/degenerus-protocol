# Preferred craps boards and the jackpot battle

Each wallet has one preference across all levels. New comp tickets and the daily jackpot battle use it. A comp ticket snapshots the preference when created; later edits do not change that ticket.

## UI interface

```solidity
function setPreferredBoard(uint32 chips) external;
function preferredBoardOf(address player) external view returns (uint32 chips);
event CrapsPreferredBoardSet(address indexed player, uint32 chips);
```

Use the same canonical encoding as paid entries: three bits per leg, from least significant upward:

| Index | Leg |
| --- | --- |
| 0 | passLine |
| 1 | place4 |
| 2 | place5 |
| 3 | place6 |
| 4 | place8 |
| 5 | place9 |
| 6 | place10 |
| 7 | hard4 |
| 8 | hard8 |
| 9 | dontPass |

Encode as `sum(count[i] << (3 * i))`. Each count is 0–3, the total is at most seven, and passLine and dontPass cannot both be named. Bits 30–31 must be zero. The dice scatter the remaining chips to reach ten. Zero means entirely random; unset preferences also read as zero.

Successful calls to `enterBattle`, `enterBonusBattle`, `enterBonusDay`, `buyFutureCrapsDays`, `applyCrapsPasses`, and `amendSlip` remember the supplied board. Explicit entry data always controls that ticket, including zero. Saving the already initialized board causes no preference write, event, or RNG lookup.

While `Game.rngLocked()` is true, the setter rejects initialization and changes with `BetLocked()`. Automatic saving skips the update while the paid entry or amendment retains its existing rules. This freeze continues after VRF fulfillment until the daily advance fully unlocks. Reads and initialized equal-board calls remain available.

## Storage

`CrapsBattle._passCredits[player]` remains at mapping base slot 15. Its packed word is:

| Bits | Value |
| --- | --- |
| 0–31 | Normal passes |
| 32–63 | High passes |
| 64–83 | Ten two-bit chip counts |
| 84 | Permanent initialized sentinel |
| 85–255 | Reserved |

The sentinel is set on the first successful manual or automatic save, including zero. Clearing the board or spending the final pass preserves it. Awards and comp tickets do not initialize it. All balance and preference writes preserve the other fields.

The **20-bit storage encoding differs from the 30-bit API encoding**. Use `preferredBoardOf` for UI reads. Raw readers use `extsload(keccak256(abi.encode(player, uint256(15))))` and extract each two-bit count. Do not pass that compact field directly to a paid-entry API.

## Automatic entries and events

`deliverPasses` and vault comp kinds 0, 1, 2 and 5 snapshot the recipient's preference. Kind 3 upgrades the existing ticket without changing its board; kind 4 banks passes. Window-ahead batches reserve before the future day’s terms are known. Protocol house/vault seats retain their existing house-random and vault-board/opt-out policies.

The Game truncates the draw to its affordable entry count, groups repeated wallets in first-drawn order, and reads all distinct played wallets in one `extsload(bytes32[])` call. It passes one packed word per wallet into `JackpotBattle`: address in bits 0–159, compact board in 160–179, and entry count starting at bit 180. The battle makes no storage callbacks. It uses the normal scheduled shooter-boost row for the number of named chips. With zero preference, the existing dice, scatter and boost are unchanged.

The complete jackpot battle has its own advance transaction in both phases. Purchase days run **6 → 17 → 15**: RNG and ETH/level-one trait awards, then battle selection/play/credits/jackpots, then tickets and seal. If no ticket leg is pending, stage 17 seals the day itself. A zero previous prize pool skips the battle stage. Jackpot days retain their existing battle stage 16. This adds one advance on funded purchase days, with no new VRF request or storage slot; both phases reuse bit 72 of the existing daily budget word. The RNG lock stays held until the last stage, including across midnight. Advance clients should recognize stage 17 and continue while `advanceDue()` is true.

The run event appends the canonical board, so an indexer can reconstruct a run after the wallet changes its preference:

```solidity
event JackpotBattleRun(
    uint24 indexed level, address indexed player,
    uint256 units, uint256 bankrollOut, uint256 rolls, uint256 paid,
    uint32 chips
);
```

Update event subscriptions to this signature. `CrapsSlipPlaced` already records the board snapshotted into ticketed entries.

## Draw payout multiplier

Every nonempty jackpot battle rolls one multiplier from its existing word, shared by all run payouts and the winner's pot:

| Probability | Multiplier |
| --- | ---: |
| 90% | 0.5× |
| 9% | 3× |
| 0.9% | 20× |
| 0.1% | 100× |

The expected multiplier is `0.90 × 0.5 + 0.09 × 3 + 0.009 × 20 + 0.001 × 100 = 1`. This preserves pre-rounding expected ordinary payouts; existing award rounding still discards fractional-FLIP dust. The separate domain is `uint256(keccak256(abi.encode(battleWord, uint256(tag)))) % 1000`, where the numeric tag is `0x436f696e447261774d756c7469706c696572` ("CoinDrawMultiplier"). Buckets 0–899, 900–989, 990–998 and 999 map to the four tiers respectively.

The base budget still determines affordability, entry units, starting bankrolls and the base pot. Compute each raw run payout (`out × units`) and raw pot, multiply by the shared factor, then apply the existing two-band rounding. No paid run still means no pot. The multiplier adds no VRF request, storage write, participant or dice roll. Selection, dice and rounding retain their existing salts.

```solidity
event JackpotBattleMultiplier(
    uint24 indexed level, uint256 baseBudget, uint256 multiplierBps
);
```

This event precedes the run events; empty fields emit none. Basis-point values are 5,000, 30,000, 200,000 or 1,000,000. `JackpotBattleRun.bankrollOut` remains the actual unscaled run result, while `paid` and `JackpotBattlePot.pot` include the multiplier and rounding. RIU awards and biggest-run scoring use the actual unscaled peak and starting bankroll; the payout multiplier cannot qualify a run for either award or multiply those separate pool awards.

## Jackpot battle RIU and biggest Dice Run awards

The pot winner is the sole jackpot candidate. Its score is the completed-shooter peak of one run divided by that run's starting bankroll, in basis points. Extra entries multiply ordinary winnings only. A run that reaches a cap without latching Goal has no qualifying peak.

- At **25×**, RIU pays **5%** of the live progressive pool.
- At **120×**, RIU pays **10%**, replacing the common share.
- At **100×** or higher, a strict improvement can claim the existing biggest Dice Run record, including its FLIP, sDGNRS, and trophy awards.

These awards draw from the existing pools in addition to the draw's normal budget. RIU uses the usual pass/liquid split and the fixed standing of 100 used by other Game-funded awards. A battle victory does not stamp a routine-window victory or activate the event's repeat-win doubling.

The Game calls `CrapsBattle.rewardJackpotBattle` once for a qualifying winner, after crediting the battle's result. The function is Game-only; the Game's existing advance stages prevent replay. Ordinary fields below 25× make no award call. The progressive event uses bet ID zero and the domain-separated battle word as its key: `keccak256(abi.encode(dailyWord, level, keccak256("far-future-coin")))`. `BigRecordUpdated` and the existing trophy events describe any record claim.

## Measured cost and deployment

With solc 0.8.34, via IR, optimizer runs 1,000 and Osaka, the table runtime is 24,440 bytes (136 below EIP-170 and under the existing 24,450-byte rail). Custom-table definition validation now runs in the existing stateless `CrapsEngine`, sharing its bounds and packing constants through `CrapsCustomTerms`. This adds a call when creating a custom battle; scheduled advances keep their existing local preset calculation. No storage slots move.

The controlled custom-entry fixture measures raw execution gas below. Each scenario restores the same entry state; this excludes transaction intrinsic gas and refunds. Named-board cases also include their board-handling work. These are examples, not fixed transaction quotes.

| Preference state | Entry gas | Versus initialized random |
| --- | ---: | ---: |
| Initialized, unchanged random | 200,141 | — |
| First save, random | 224,329 | +24,188 |
| First save, named | 224,790 | +24,649 |
| Changed to named | 207,690 | +7,549 |
| Cleared to random | 207,229 | +7,088 |
| Locked, save skipped | 203,306 | +3,165 |

Both manual and paid initialized-equal paths are tested for no preference SSTORE, no preference event and no RNG lock query. The preference comparison still reads the existing pass-credit slot.

Jackpot battle gas tests include Game-side grouping, the cold batch preference read, packing and resolution. The existing 7,475,000-gas model allowance is checked across saved boards, all eight boost rows, collisions and budget truncation. It is an empirically tested allowance, not an exhaustive proof over all possible words. Full purchase-day and jackpot-stage tests also retain their transaction-cap checks. `PreferredBoardAdvanceStress.t.sol` preserves a reachable expensive advance; `JackpotBattleAwardsGas.t.sol` measures the additional award path through the real contracts.

Component measurements with the payout multiplier: 2,172,138 gas for the 50-distinct-wallet sample (+5,797) and 90,497 for 50 entries sharing one wallet (+1,938), including preparation, resolution and the multiplier event. The repeated-wallet test allowance increases from 90,000 to 92,000 specifically for this added work; the 7.475M battle allowance remains unchanged. These microbenchmarks run the preparation and battle in the same call context, as production does. The isolated full RIU-plus-record path, with a high-pass award, fresh record/recipient, maximum accrued record share, sDGNRS and trophy, uses 216,861 execution gas. These are measured cases, not a proven global maximum.

`AdvanceNestedFullCompositionGas.t.sol` now measures fresh RNG, vault-history work, golden grand, redemption and 49 ETH awards separately from the 50-run battle, including mineFlip routing. `FOUNDRY_ISOLATE=true` gives successive calls separate transaction access lists. The measurement includes intrinsic gas once. The max-chip battle model removes the battle's nested execution cost, substitutes the 7,475,000 allowance, and adds 400,000 for jackpot awards. The nested replay excludes both test-wrapper memory expansion and top-level calldata intrinsic. Each measured battle stage and the modeled one must stay below 10.5M; this remains an empirical model, not an exhaustive maximum proof. The earlier combined-transaction 14.18M estimate is superseded.

| Split-stage fixture | Gas including intrinsic |
| --- | ---: |
| Heavy daily stage: fresh RNG, vault history, golden grand, redemption, ETH | 5,035,459 |
| Max-chip battle: 50 distinct paying wallets | 6,341,754 |
| Saved-board battle: 50 wallets sharing a low address byte | 7,829,017 |
| Separate 120-winner ticket stage, heavy fixture | 7,401,002 |
| Max-chip battle model with battle and jackpot allowances | 9,676,284 |

The model arithmetic is `6,341,754 - 4,540,470 + 7,475,000 + 400,000`. Splitting adds transaction overhead and one keeper advance on funded purchase days; its purpose is to lower the largest transaction, not the total work.
