# Preferred craps boards and the jackpot battle

Each wallet has one preference across all levels. New comp tickets and the daily jackpot battle use it. A comp ticket snapshots the preference when created; later edits do not change that ticket.

## Reservations and settlement deadline

Future day tickets and window reservations can cover tomorrow through 30 days ahead. Every day in a paid or pass-funded batch must fit; an invalid day reverts the whole purchase. Automatic awards bank unused pass credits when they cannot reserve a day. Unspent pass credits do not expire.

Scheduled day D can settle, or receive its unopened-day pass refund, through D+30. Starting D+31, remaining work is skipped without payment or refund, including unfinished jackpot fields. Payments already made stand. This deadline also applies after a prolonged RNG outage. Custom battles keep their existing lifecycle.

Scheduled bets and each wallet's day-seat record reuse 64 day banks. Public bet IDs and event identities retain the actual day. Once a bank is overwritten, old bet/seat data is unavailable; use events for history. Per-day budgets, boards and jackpot accounting keep their logical keys.

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

## Automatic entries

`deliverPasses` and vault comp kinds 0, 1, 2 and 5 snapshot the recipient's preference. Kind 3 upgrades the existing ticket without changing its board; kind 4 banks passes. Window-ahead batches reserve before the future day's terms are known. Protocol house/vault seats retain their existing house-random and vault-board/opt-out policies.

## The jackpot battle

The jackpot battle is the day's sixth window (period 5, slot `day * 8 + 6`). It is one craps battle with two kinds of seat:

- **Paid seats.** A direct entry or a day ticket costs a fixed 8,000 FLIP, burned at entry. The seat plays the board it was entered with, and a high seat counts as its day's high multiple of units.
- **Awarded seats.** The Game draws these from the far-future ticket queues of the next 99 levels. Each award plays the wallet's saved preference, and a wallet drawn twice gets two separate seats.

Warm-up and skipped days have no paid field. Their award-only battle uses the otherwise unused slot `day * 8 + 7`.

### Lock and funding

The daily RNG request locks the field before its word exists:

- the paid entries and day tickets;
- the **Added** allocation: 0.5% of the recorded prize pool at the level's ticket price, raised to 150,000 FLIP while the Game's `level` is 0 or 1 and to 50,000 after.

Preference edits freeze with the lock. The lock stays held, across midnight too, until the battle has finished.

At lock, `floor(Added / 20)` funds the high-roller reserve. When the word lands,
one roll multiplies the remaining pool,
`(paid units × 8,000 + Added - floor(Added / 20)) × multiplier`:

| Probability | Multiplier |
| --- | ---: |
| 90% | 0.5× |
| 9% | 3× |
| 0.9% | 20× |
| 0.1% | 100× |

The expected multiplier is 1. The roll is `uint256(keccak256(abi.encode(battleWord, uint256(tag)))) % 1000` with tag `0x436f696e447261774d756c7469706c696572` ("CoinDrawMultiplier"). Buckets 0–899, 900–989, 990–998 and 999 map to the four tiers.

Awards come from Added alone: one per 10,000 FLIP of Added, at most 500. Paid volume and the multiplier never change the count.

### Draw and seal

The Game draws awards in chunks of up to 50 entries. An advance keeps processing
chunks while enough gas remains for another complete chunk; otherwise it saves the
cursor and resumes on the next advance.

- Each visit picks a level uniformly among eligible nonempty far-future queues, chooses a starting position, and walks that level's whole queue circularly. Levels are picked with replacement between visits. Chunk boundaries preserve the unfinished visit.
- The Game reads all distinct wallets' saved boards in one `extsload(bytes32[])` call. It passes one word per entry: address in bits 0–159, the compact board in 160–179, one unit at bit 180. The battle makes no storage callbacks, and a malformed or empty entry forfeits its award.

The chunk that reaches the award target, or finds no eligible level, seals the field.
Each paid seat has one base place in the Added-funded main pool; extra high units
receive a separate fee-only allocation under the same multiplier. With N base
paid seats plus awarded seats:

- each base seat's bankroll is half the main pool per seat, rounded down to a multiple of 300 FLIP (at least 1,800, and capped at the engine's chip limit);
- the rest of each unit's share is its bounty, in 100-FLIP granules, never above its bankroll;
- rounding dust stays in the pot.

Only the base seats' fee-funded bankroll is booked as the day's craps action, and
the comp lane earns 2% of it, both once at seal. Extra high fees earn comps equal
to 9.6% of their pre-roll at-risk value: all extra fees for a sole high seat, half
for a contested high field. These extras, Added and multiplier gains never enter
the action books.

### Settlement

Every seat throws the same dice. Seats settle through the table's normal resolver in one order: paid window seats, then day tickets, then awarded seats.

- An awarded seat keys its scatter, survival coin and shooter boost to its own bet id rather than to the wallet. Repeat awards to one wallet are therefore separate runs.
- Each advance settles seats on a 1,500-unit work budget. The call that seals the field first charges its own draw (110 units plus 10 per entry) against that budget and settles on the rest.
- Every run has the shared 600-roll between-shooter budget (1,111-roll ceiling), like every slip.

Scoring, the pot, the high-roller lane and payment follow any scheduled battle. The last seat finalizes the field once:

- The best-ranked run takes the pot: the bounties plus the seal's remainder.
- A contested high lane pays its winner.
- The pot winner's high point can also claim RIU. At **25×** it pays **5%** of the live progressive pool; at **120×** it pays **10%** instead. RIU keeps its usual pass/liquid split and the fixed standing of 100.
- At **100×** or more, a strict improvement claims the biggest Dice Run record, with its FLIP, sDGNRS and trophy awards.
- Nothing doubles the jackpot's RIU shares.
- A separate field-wide 1-in-10 roll pays the high-roller reserve to one uniformly sampled paid high seat, excluding sDGNRS. If there is no eligible seat or the roll misses, the reserve carries forward. This Coinflip credit creates no extra action, comps or passes.

### Advance stages

1. The daily request locks the field.
2. Stage 18 applies the fresh word and does nothing else.
3. Each later advance runs one battle step: stage 16 on jackpot days, 17 on purchase days. A step is a draw chunk (the sealing chunk also starts settling) or a settle batch.

Once the field completes, the day continues with its usual stages. Advance clients should keep calling while `advanceDue()` is true.

### Reads and events

Call these at the **CRAPS address**; the table delegates their selectors to `JackpotBattle`:

```solidity
function jackpotEntryPrice() external pure returns (uint256);
function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete);
function jackpotBattleOf(uint64 slot) external view returns (JackpotRound memory round, uint256 board, uint64 cursor);

event JackpotBattleLocked(uint64 indexed slot, uint24 requestDay, uint256 added, uint256 paidEntries);
event JackpotBattleEntry(uint64 indexed slot, uint256 indexed betId, address indexed player, uint256 units, uint32 chips);
event JackpotBattleStarted(uint64 indexed slot, uint24 level, uint256 drawnEntries, uint256 drawnUnits, uint256 word);
```

- `JackpotBattleEntry.chips` is the canonical 30-bit board the award plays. An indexer can replay a run after the wallet changes its preference.
- `JackpotRound` carries the raw Added, the rolled pool, the multiplier in basis points, the unit bankroll and bounty, the pot remainder, paid and drawn counts, the award target, the draw cursor and the committed word.
- Settlement and payment use the table's ordinary events: `CrapsBetSettled`, `CrapsBattleFinalized`, `CrapsBattlePaid`, `CrapsHighRollerPaid`, `CrapsProgressivePaid` and `CrapsProtocolAwardSplit`. Record claims appear as `BigRecordUpdated` and the trophy events.
- `CrapsSlipPlaced` records the board of each paid ticket.

## Gas checks

`test/fuzz/JackpotMergeAdvance.t.sol` exercises full draw chunks and asserts a
10M transaction ceiling. See [Verification](VERIFICATION.md) for cold gas checks.
