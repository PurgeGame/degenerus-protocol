# Randomness inputs and domain separation

Every hash that derives a value from VRF entropy is `EntropyLib.hashN(RngTags.X, ...)`:
Keccak-256 over 32-byte ABI words (`hash1`..`hash4`), with the numeric domain constant first. The
113 domains are defined once in [`contracts/libraries/RngTags.sol`](../../contracts/libraries/RngTags.sol)
(values 1–115; 58 and 68 are unassigned). A tagged hash takes either the raw word or a seed
already derived from it: the payout seed stored with each [foil pack](#foil-packs) and the
direct-award round seed feed later tagged hashes, and the uint64 LCG inside each sixteen-entry
[ticket group](#ticket-generation) expands a tagged seed without further hashing. The only use of
a raw word bit is the coinflip win bit, bit 0 of the coin word ([below](#coin-word-and-nudges)).

The trust boundary is request → fulfillment → consumption. Hashing supplies domain separation,
not fresh entropy and not protection for inputs chosen after a word is known; the commitment
guards described below remain necessary. See `snapshot.json` for the supplied source identity.

## Registry gate

`scripts/check-rng-shape.py` checks the source against `scripts/rng-shape-manifest.json`:

- every `keccak256` and `EntropyLib.hashN` site in production contracts (excluding
  `interfaces/`, `mocks/`, `test/`) is registered by file, function and exact expression, and
  classed `RNG`, `NON-RNG` (storage addressing, commitments, identities), `CONSTANT` or
  `HASH-IMPLEMENTATION`; an unregistered or stale site fails;
- every tag is a named nonzero constant, values are unique, and every tag is used;
- the first argument of every `EntropyLib` call is a single `RngTags` constant (or the one
  `ticketLeg ? RngTags.WHALE_TICKET : RngTags.WHALE_QUADRANT` selector), and the argument count
  matches the hash width;
- no tagged hash takes `address(`, `ContractAddresses.`, `block.`, `tx.`, `chainid()`,
  `blockhash(` or `gasleft(`; the only exempt argument is the Lens expression
  `issuer == ContractAddresses.VAULT ? VAULT_WALLET_ID : SDGNRS_WALLET_ID`, which maps an issuer
  to its constant wallet ID;
- `rawBitExceptions` holds exactly one entry, `bool win = (rngWord & 1) == 1;` in
  `CoinflipCore.processCoinflipPayouts`, and that statement must appear exactly once there.

The registry is a reviewed source inventory, not a whole-program taint proof; the companion
`check-rng-taint.sh` and `check-rng-window.sh` cover transported words and publication.

## Request, callback and publication

VRF requests are paid in native ETH from the coordinator subscription. `rawFulfillRandomWords`
runs in the Game itself (no delegatecall) and does three things: it requires the coordinator as
`msg.sender`; it compares the low 64 bits of the request ID with the stored `vrfRequestId`, which
is packed above the coordinator address in one storage slot (slot 21); and it stores the raw word
in `rngWordCurrent`. ID 0 and superseded IDs return without reverting. Raw words 0 and 1 are
ignored, which leaves the request pending for its retry. A request whose returned ID has zero low
64 bits is treated as refused at request time (`_boundedVrfRequest`). A consumed session keeps
its answered ID, and `LootboxRngApplied(index, word, requestId)` reports the low 64 bits.
Publication, nudge application and every consumer run later in `mineRun`.

The logical day starts at 1 and advances exactly once when a fresh daily VRF request is
accepted. Coinflip receives the same requested-day mirror atomically. Retry, coordinator
replacement, mid-day requests and elapsed calendar windows never increment it. Only one fresh
daily request is accepted in each 22:57 UTC reset window; unused windows create no rounds or
recovery results. There is no gap backfill and no recovery-word domain.

A mid-day request whose pending value is below the threshold is the only path that spends
mid-day request credit, and it spends the caller's own credit (`middayRngCredit`, credited by
`Admin.donateVrf` at one quarter of the donated wei).

## Coin word and nudges

`reverseFlip(expectedCost)` burns FLIP to queue one nudge. It reverts while `rngLockedFlag` is set
or after liveness has fired, and the count is capped at 255 (`RNG_NUDGE_CAP`). The cost is 100
FLIP, multiplied by 1.5 per nudge already queued. `prepareRequestBoundary` sets `rngLockedFlag`
before the daily request, so the count is frozen from the request until the word is applied.

At the daily apply (`DegenerusGameAdvanceModule.applyDailyWord_g1652`), `_applyDailyRng(day, word)`:

1. computes `coinWord = word + nudges` (unchecked), so each nudge reverses bit 0;
2. clears the nudge count;
3. records the raw `word` for the day (`_recordDailyRng`);
4. emits `DailyRngApplied(day, word, nudges)`.

The coin word goes only to `Coinflip.processCoinflipPayouts(bonus, coinWord, day)`, which uses
it twice: `win = (coinWord & 1) == 1`, and the reward percent
`FlipRoundLib.coinflipRewardPercent(bonus, coinWord, day)`, whose seed is
`H(FLIP_REWARD, coinWord)` (`seed % 20`: 0 → 50, 1 → 150, otherwise `78 + seed % 38`, plus the
bonus). No other derivation sees nudges. The recorded daily word, the session word, jackpots,
quests, WWXRP, Craps, Degenesis and the terminal word are all the raw word. The terminal path
calls `_applyDailyRng` and discards the coin word, because no daily coinflip resolves after
liveness.

## Words and their consumers

- **Recorded daily word.** The Game retains two daily words in `rngWordByDay[day & 1]`,
  authenticated by two uint24 day tags in `rngDayTags` (slot 25). `rngWordForDay` exposes the
  latest applied result and its predecessor and returns zero for future, expired or mismatched
  tags. Internal readers authenticate the same tags without a calendar cutoff, so a committed
  daily consumer can finish after midnight.
- **Session word.** The published read-buffer word (`_lootboxWord(_rngReadBuffer())`), from a
  daily or mid-day request. Queued boxes, AFKing boxes, redemption settlement and Decimator
  rounds use it. The read-completion gate waits for AFKing boxes, live sDGNRS redemption
  settlement and Decimator rounds, along with committed tickets/foil, human boxes/bets and
  read-bound Craps. An AFKing stamp cannot open before its day is sealed.
- **Craps windows** freeze their opened tier, high multiple and stake echo in the scoreboard, so
  scheduled cleanup reconstructs identical terms after the opening-day word retires.

### Degenesis cohort binding

Degenesis orders draw from the daily word of the request that follows their cohort's pricing.
Every outcome input is fixed before that request:

- Order lanes (wallet ID, amount units, seconds-into-day) are written at purchase, and a cohort
  is sealed once its day index is below the request day, so no order joins a cohort whose word
  was requested.
- `prepareDegenesis_g47(day)` runs in `prepareRequestBoundary` before the request: it splits
  sealed cohorts, then prices at most one nonempty cohort from its volume `V` and the
  `Pool.Degenesis` balance, writing `degenesisActive` with the bound day. Pricing requires the
  previous cohort to have closed, so a backlog delays the binding word and cannot alter a rate.
- `_recordDailyRng` copies the word into `degenesisWord` when `degenesisClosed < DEGENESIS_DAYS`
  (7) and the bound day equals the recorded day. The copy is the only way a word reaches the
  module; mid-day words are never recorded as daily words.
- `_degenesisOutcome(cohort, lane, index)` is pure in `degenesisWord`, the cohort terms and the
  order: reordering or partitioning settlement calls cannot change any order's reward, and the
  cursor only selects which index is paid next.
- Settlement amounts depend on `Q` and `V` frozen at pricing, never on the live pool; category,
  size, pass side and rounding come from distinct tags on the order seed.

### Ticket generation

Ticket materialization is owned by `DegenerusGameTicketModule`. Output is identical across every
successful stopping schedule, including lower transaction gas, cold/warm storage and access
lists. The invariant covers each trait bucket's ordered owner lanes, the final round counter,
consumed debts and downstream fixed-input samples.

A solo stream identity (`TicketEntropy.identity`) packs:

| Bits | Value |
| --- | --- |
| 248–255 | `0x20` ordinary half zero; `0x21` ordinary half one; `0x22` frozen future |
| 224–247 | Absolute level |
| 192–223 | Physical queue index |
| 64–191 | Zero |
| 32–63 | Owner's wallet ID (masked to zero before hashing) |
| 0–31 | Zero in the identity; the event key carries the run's start offset here |

For absolute solo offset `i`, each sixteen-entry group uses
`H(TICKET_TRAITS, committedWord, identity, i / 16)` with the wallet-ID field zeroed, expanded by
the uint64 LCG within the group. Solo offset starts at zero when an owner first enters solo
processing, including a survivor of seated rounds. It never includes the remaining balance,
wallet ID, transaction gas or call count. Unfinished solo runs stop only on a multiple of sixteen
entries. The final tail resolves its fraction and clears debt and progress atomically; the
fraction `H(TICKET_REMAINDER, committedWord, identity) % 100 < remainder` (wallet-ID field
zeroed) adds at most one emitted entry.

Round traits use `H(TICKET_ROUND, committedWord, level, globalRound)`. A round first fills eight
live seats or reaches the frozen frontier; incomplete selection cannot roll or send waiting
entries through the solo engine. Surviving seats preserve rotated queue order, and nothing else
changes the global round counter.

Each frozen ordinary or future queue starts at `H(TICKET_ROTATION, committedWord, queueKey) %
frozenLength` and wraps once. The start is recomputed, not stored. Cursors and seats use logical
positions in that rotation; fractional and solo identities use the physical queue index.

`TraitsGenerated(uint32 indexed walletId, uint256 baseKey, uint32 take)` emits
`identity | absoluteStartOffset | goldSixTakenFlag`. Bit 255 (`GOLD_SIX_TAKEN`) is an event-only
flag recording that gold Dice 6 was already present before the run; a decoder clears it and the
low 32 bits before group hashing and uses it as the replay's initial cap state. The count
includes any final fractional entry. Foil events use domain `0x23`, offset zero and the buyer's
wallet ID at bits 32–63. Seated `EntryTraitsRevealed` events reveal credited entries and owners
directly; each nonzero topic is `(level << 160) | walletId`.

Jackpot ticket awards paid directly into a level run in rounds of up to 32 winners
(`_materializeJackpotRound`), seeded `H(TICKET_DIRECT, allocationRoot, q << 32 | i, round)`.
Quadrants 1–3 reorder the winners before assigning traits: a full batch of 32 uses
`PackedTicketShuffle.shuffle` with `H(TICKET_SHUFFLE, seed, q)`; a smaller batch runs a
Fisher–Yates walk chaining `H(TICKET_SHUFFLE_STEP, entropy, left)`. Each group of eight takes its
quadrant's trait from 64-bit slice `q` of `H(TICKET_GROUP, seed, group)`.
`JackpotTicketBatchTraits` reveals the result.

### Gold Dice 6

Gold Dice 6 (trait 253) keeps only its first natural occurrence at each full level, shared by
solo, round and foil producers. The live-bucket bit, authenticated against the full buffer level,
is the claim marker: production appends always add nonzero entries and never remove them from an
active level. Later occurrences become one of traits 248–252, 254 or 255, selected by
`H(GOLD_REPLACEMENT, seed) % 7`, where `seed` is the candidate's LCG state for solo entries, the
round seed for seated entries and the foil-line seed for packs. Retired foil levels redirect every
candidate. Gold six receives zero virtual deity entries in every jackpot and pass sampler; a deity
wallet's actual entry remains eligible.

A natural daily-board gold six survives when `H(GOLD_DAILY, word) % 6 == 0`; otherwise it is
replaced from the same seven-die pool with `H(GOLD_REPLACEMENT, word)`. The final daily board is
shared by the ETH, coin, ticket and foil-match paths. When it contains gold six, Dice receives the
solo pool ahead of every other gold trait; the shared selector gives natural terminal gold six the
same priority, while the one-in-six survival gate applies to daily boards only. All Dice are
excluded from Degenerette hero selection and jackpot hero boosts; Degenerette boards keep their
dice and match odds.

Producer order is part of the invariant. Ordinary queues precede the committed future pool and
foil FIFO. If a parity dependency starts foil early, its continuation keeps precedence across
transactions; only the exact older queue blocking the FIFO head may interrupt it. Terminal
continuation preserves an active solo offset and seats when finishing the same cohort on its
word; repoints, completed queues and retired buffers clear progress.

Each indivisible miner operation is admitted only when its conservative cold-path bound,
including its call, checkpoint and return tail, fits the remaining allowance and available gas.
Available gas may select an earlier safe checkpoint; it never changes the final ticket inventory.

### Foil packs

Foil purchases freeze level, boost and activity score and join the foil write cohort, which has
its own toggle. Only the next daily request (or the single terminal swap) freezes that cohort; a
mid-day request never moves foil packs, so every pack generates from a daily word and its grand is
sized inside the daily pool freeze. Materialization stores four uint32 lines
`H(FOIL_LINES, committedWord, buyerWalletId << 24 | level, line)` in the pack record, together with
readiness, first eligible draw and actual generation day. Claims never reconstruct lines from a
daily word.

Each `dailyFoilDraw[day & 1]` holds the board in bits 0–31, the level in bits 64–87, a 128-bit
payout seed `uint128(H(FOIL_PAYOUT, committedWord))` in bits 88–215, a seeded flag at bit 216 and
the exact day in bits 217–240, sealed in one write. Every reader authenticates the day tag. A
same-day or newer record makes the writer return without changing state or reverting the advance.
Match currency and spin hash the saved seed with the ticket index under `FOIL_CURRENCY` and
`FOIL_SPIN`; they never read retained daily words. A zero seed is valid with the flag set.

Claims on draw day D stay open through the published frontier D+1 and expire at D+2; calendar
resets and outstanding requests cannot expire them. Each player's match markers occupy one word:
two day-tagged lanes with four ticket bits each. Golden foil claims use the generation-day and
next-day window against published daily results; WWXRP draw payouts use resolving day D and D+1
(D = participation day + 1) against the same frontier. Both expire at published D+2. The
liveness/game-over cutoff closes claims.

Pack metadata and lines share four reusable records per player, keyed by `level & 3` and
authenticated by the full level in bits 208–231; gold-paid state is bit 232. A purchase can reuse
an occupied record only after its pack has generated, its level is below the current level, its
gold window is closed, and neither of the two latest sealed boards references its level
(`_foilRecordReusable`). A live collision rejects only the new purchase.

The stored seed fixes the board, currency and primary spin, not all proceeds. Stake pricing uses
the draw's level and the pack's saved activity score. An ETH spin caps its ETH share at 10% of the
live unfrozen future pool, with overflow recirculated through live lootbox state, and high-score
ETH spins award sDGNRS from the live Reward pool, so claim timing within the window can change ETH,
sDGNRS and recirculation proceeds. Claims during frozen pools keep the pending-pool solvency check.

### Jackpot battle, price and subsidy

The jackpot battle's entry price decodes the low two bits of the period-five schedule root
`H(CRAPS_SCHEDULE, dailyWord, 5)` (`CrapsPriceLib.jackpotPrice`: 6,000 / 8,000 / 8,000 / 10,000).
Price freezes in the opening terms and is copied into the round at lock.

The battle field, pool multiplier and subsidy consume `battleWord = H(FUTURE_BATTLE, word)` of a
later committed word, not the known opening word. `JackpotBattle._prepare` draws the multiplier
from `H(CRAPS_JACKPOT_MULT, battleWord) % 1000` and the subsidy from
`H(CRAPS_SUBSIDY, battleWord) % 100` (buckets at 60/90/99), after the field, fee, award target,
baseline and reserve contribution have locked; preparation persists both once across resumed
chunks.

### Century refill

The sDGNRS century refill uses the committed transition word passed through `advanceGame`. It
draws `25 + H(CENTURY_REFILL, word) % 51` percent (25–75 inclusive). Burn amounts size the mint
but do not enter the draw, and `lastRecycledCentury` prevents a completed century from rolling
again.

### Redemptions

Live sDGNRS redemptions settle on the published session word that answered the request closing
their batch, for both manual claims and the bounded miner drain. One synthetic flip per batch uses
`H(REDEMPTION_FLIP, word)`: bit 0 decides the win and the same hash feeds the coinflip
reward-percent mapping. Half the rolled ETH credits game claimable and half opens a redemption
lootbox, subject to the dust rule. Terminal redemptions keep their roll, receipt and ETH
reservation until withdrawal and need no historical RNG for it.

### Endings without a word

There is no entropy fallback. A VRF request whose word is not in use (published by `mineRun`) 14
days after it was sent ends the game deterministically with no word, whether the word never came
or came and was never published; a word delivered after that point is discarded, and the terminal
level's tickets share the pot (`claimDeadVrf`). Fourteen days without a completed daily session
end the game on the same path even while the coordinator answers; that ending settles no loans
and sends no terminal request. A normal ending draws only on a terminal word it requested itself
after liveness froze purchases. Terminal entry never invokes Craps. The NatSpec of
`_endingReason`, `_vrfDeadmanFired`, `_vrfDead` and `_handleGameOverPath` states the implemented
behaviour.

### Miner compensation

Miner compensation is separate from every outcome domain. It prices execution gas above
`MineFlipGas.MIN_REWARDED_GAS` (1M) at `block.basefee` with an age-based FLIP multiplier, and
requires successful nonterminal progress. The age anchor is the later of the latest VRF request
time and the current 22:57 UTC reset. No entropy derivation or consumer payout reads gas price,
work age or the multiplier, and the VRF callback writes no state other than the raw word.

## Domain map

`H` is `EntropyLib.hashN`; the tag is always the first word.

| Consumer | Root or domain | Sharing / fixed inputs |
| --- | --- | --- |
| Queued box entry root | `H(BOX_ORDER, sessionWord, position)` | One 85-bit entry per purchase, three per storage word; `sessionWord` is the published word of the entry's buffer; `position` is the logical entry position (never the word index or lane), fixed by the append before the buffer's word is requested. The event tag is `1 << 46 \| position << 1 \| buffer`. The frozen activity score is a 12-bit code and is a payout input, never a seed input |
| Ordinary box roll | `H(BOX_OPEN, entryRoot, nonce)` | Nonce is the box's 1-based position in its order; size excluded; the wallet ID is read from the entry and is not a hash input |
| Ordinary box boon | `H(BOX_BOON, entryRoot)`, then `H(BOX_BOON_LANE, boonSeed, nonceBase + i)` | Box `n` draws at boon nonce `n - 1`; separate from reward rolls and craps scatter |
| Box secondary draws | `BOX_WWXRP_SPIN`, `BOX_FLIP_SPIN`, `BOX_ETH_SPIN`, `BOX_PASS_SPIN`, `BOX_PASS_ROUND`, `BOX_ROUND` | Each `H(tag, boxSeed)`; stake only sizes the payout |
| Direct reward box | `H(BOX_DIRECT, word)` | The caller supplies a bound word: `H(BET_BOX, betWord, betId)` for a Degenerette bet, `H(SPIN_RECIRC, spinSeed)` for an ETH-spin recirculation |
| AFKing box | `H(BOX_AFKING, sessionWord, subscriberWalletId)` | Published session word at open; the stamp is recorded before fulfillment; amount excluded |
| Redemption box | `H(REDEMPTION_BOX, sessionWord, beneficiaryWalletId)` (sDGNRS) is the entry root of the same `BOX_OPEN` / `BOX_BOON` rolls | Beneficiary ID committed at the burn; roll amount `H(REDEMPTION_AMOUNT, word)`; synthetic flip `H(REDEMPTION_FLIP, word)` |
| Degenesis order | `seed = H(DEGENESIS_ORDER, degenesisWord, index)`; category `H(DEGENESIS_CATEGORY, seed) % 100`, size `H(DEGENESIS_SIZE, seed)`, pass side `H(DEGENESIS_PASS, seed) & 1`, rounding `DEGENESIS_ROUND` / `DEGENESIS_PASS_ROUND` on `seed`; boons `boonSeed = H(DEGENESIS_BOON, degenesisWord, index)`, then `H(DEGENESIS_BOON_EXTRA, boonSeed)` and `H(DEGENESIS_BOON_TYPE, boonSeed, slot)` | One word per cohort; `index` is the order's position in its cohort; reward account and amount excluded |
| Decimator battle | dice `H(DECIMATOR_DICE, word)`; board `H(DECIMATOR_BOARD, word, entryId)`; tie key `H(DECIMATOR_TIE, word, entryId)` (high 192 bits) | `word` is the published session word; dice omit the entry id; the engine survival salt is the entry's committed wallet ID (generated entries: `uint160(H(DECIMATOR_GENERATED, word, id))`) |
| Decimator survivor sample | rotation `H(DECIMATOR_ROTATION, word) % T`; stratum offset `H(DECIMATOR_SAMPLE, word, stratum)` | `S = min(1000, ceil(T/2))` strata; stratum `i` selects one position in `[floor(i*T/S), floor((i+1)*T/S))`, then rotates; `T` counts original and generated entries |
| Decimator generated entries | owner `H(DECIMATOR_OWNER, word, id) % effectiveLen` | IDs `N+1..N+M` share the board/tie domains; recipients and preferences are read only for sampled entries under the daily lock |
| Degenerette result board | `H(BET_HOUSE, word, spinIndex)` | Shared by all ETH/FLIP bets in an RNG period, across stakes, heroes and currencies; ETH (0) and FLIP (1) are the only bet currencies |
| Degenerette player ticket | `H(BET_PLAYER, word, heroSymbol, spinIndex)`, then `H(SPIN_PLAYER, seed)` for colors | Shared across owners, bet ids, stakes and spin counts for the same hero |
| Degenerette spin internals | `SPIN_HOUSE`, `SPIN_HERO`, `SPIN_RIG`, `SPIN_RIG_PICK`, `SPIN_SURVIVAL`, `SPIN_ROUND`, `SPIN_RECIRC`; flip chain `H(SPIN_FLIP_ROUND, seed, i)` | Each `H(tag, seed)`; internal box and foil reward spins; the WWXRP rig `H(SPIN_RIG, spinSeed)` applies only to WWXRP reward spins |
| Degenerette survival / rounding / box / record | `H(BET_SURVIVAL \| BET_ROUND \| BET_BOX \| BET_RECORD, word, betId)` | `betId` is the queue position + 1 within the bet's index ([bet queue](../DEGENERETTE-BET-QUEUE.md)); settlement batch excluded |
| Craps dice / shooter | `seed = H(CRAPS_DICE, word, bound)`; rotation `H(CRAPS_SHOOTER, seed) % n`; hand `h` `H(CRAPS_HAND, seed, h)`; roll `i` `H(CRAPS_ROLL, handSeed, i)` | `bound` is the window slot; every seat of a field throws the same dice; `JackpotBattle.payBattlePot` re-derives the same seed and rotation from the slot |
| Craps board / survival | board `boardRoot = H(CRAPS_BOARD, word, key)`; scatter `H(CRAPS_SCATTER_CHIP, boardRoot, i) % 10`; survival `H(CRAPS_SURVIVAL, seed, hand, key)` | `key` is the paid entry's committed owner wallet ID (bet header bits 0–31; protocol seats Vault 1, sDGNRS 2), or `uint160(H(CRAPS_AWARDED, word, betId))` for awarded entries |
| Craps bounty boost | `H(CRAPS_BOOST, word, bound) % 1000` | Window slot; battle financial key excluded |
| Craps schedule / high multiple | `H(CRAPS_SCHEDULE, word, period)` (period 4 reuses period 0); `H(CRAPS_HIGH, word)` | Fixed scheduled period; period 5 prices the jackpot battle |
| Craps ties / rounding | `H(CRAPS_TIE, word, bound << 64 \| betId)` / `H(CRAPS_ROUND, word, betId)` | Fixed window and entry |
| Craps hot bonus | none | Duration-based: seats share hot activation after the twelfth surviving roll; rotation adds 30 percentage points from roll 13 on |
| Jackpot allocation / quadrants | `allocationRoot = H(JACKPOT_ALLOCATION, word, level)` (solo-adjusted on the ETH path); quadrant seed `H(JACKPOT_QUADRANT, allocationRoot, q)` | Pool size, pass quantity and previous winners excluded |
| Whale pass recipient | `H(WHALE_QUADRANT \| WHALE_TICKET, quadrantSeed) % (len + virtualDeityCount)` | One draw over the quadrant's official winning-trait bucket; the caller fixes the leg (`ticketLeg`); never selects from the ETH recipient list; an empty set consumes the award |
| Jackpot recipient sampling | `H(BUCKET_SAMPLE, root, salt, pull)`; padding `H(SAMPLE_PADDING, entropy, used)` | Salts distinguish ETH/current/early-bird/purchase draws; ticket legs use quadrant seed and salt `239`/`241`/`242` + `q` by leg kind; prize size excluded |
| Jackpot FLIP / shares | FLIP level `H(FLIP_LEVEL, word, pull)`; daily current-pool share `H(JACKPOT_DAILY_BPS, word)`; ticket roll `H(JACKPOT_TICKET_ROLL, entropy)` | Fixed pull ordinals |
| Direct jackpot ticket rounds | `seed = H(TICKET_DIRECT, allocationRoot, q << 32 \| i, round)`; `H(TICKET_SHUFFLE, seed, q)`; `H(TICKET_SHUFFLE_STEP, entropy, left)`; `H(TICKET_GROUP, seed, group)` | See [Ticket generation](#ticket-generation); caller gas and the global round counter are not inputs |
| Ticket generation | `TICKET_TRAITS`, `TICKET_REMAINDER`, `TICKET_ROUND`, `TICKET_ROTATION` | See [Ticket generation](#ticket-generation) |
| Daily trait board | `H(JACKPOT_BOARD, word)`; `H(GOLD_DAILY, word)`; `H(GOLD_REPLACEMENT, seed)` | Four six-bit slices, then gold-six keep/redirect; one board per day, re-derived identically by later legs |
| Hero symbol | `H(JACKPOT_HERO, word) % effectiveTotal` | The committed day's frozen wager weights |
| Jackpot battle field | `battleWord = H(FUTURE_BATTLE, word)`, then `H(FUTURE_BATTLE_VISIT, battleWord, visitOrdinal)` | Each visit chooses an eligible level and walks it once from a circular start; continuation preserves the visit across chunks |
| Jackpot multiplier / subsidy | `H(CRAPS_JACKPOT_MULT, battleWord)` / `H(CRAPS_SUBSIDY, battleWord)` | The 5% high-reserve contribution is removed before the subsidy |
| High-roller reserve | gate `H(CRAPS_RESERVE_DRAW, battleWord, slot) % 10 == 0`; nominee `H(CRAPS_RESERVE_WINNER, battleWord, slot << 32 \| eligibleOrdinal) % eligibleOrdinal == 0` | Reservoir sampling over paid high seats in canonical order, excluding sDGNRS; resumable cursor |
| BAF head awards | slot 1 `H(BAF_HEAD, word)` over the armed day's weighted depositors (Coinflip); slot 2 `H(BAF_HEAD_SIDE, word) & 1` picks third or fourth place | Frozen board and armed day; slot 0 is the top bettor |
| BAF scatter rounds | near `H(BAF_NEAR_ROUND, word, round)`; far `H(BAF_FAR_PAIR, word, pair)`, then `H(BAF_FUTURE_ATTEMPT, entropy, attempt)` per sampled queue | Fixed bracket and round count |
| BAF ticket award | `H(BAF_TICKET, word, winnerOrdinal)` | Previous awards cannot move this root |
| Daily / level quests | `H(QUEST_DAILY, word)` / `H(QUEST_LEVEL, word)` | Global quests; forced types bypass the roll |
| Pool skim / variance / keep / BAF gate | `H(POOL_SKIM, word)`; `H(POOL_VARIANCE_A, word)`, `H(POOL_VARIANCE_B, word)`; x00 keep `H(POOL_FUTURE_KEEP, word)`; `H(BAF_GATE, word) & 1` | Independent tags on the level-transition word |
| sDGNRS century refill | `25 + H(CENTURY_REFILL, word) % 51` | No caller, amount, timestamp or pool balance |
| Coinflip day | win `coinWord & 1`; reward `H(FLIP_REWARD, coinWord)` | The only consumers of the coin word ([Coin word and nudges](#coin-word-and-nudges)) |
| Foil packs | lines `H(FOIL_LINES, word, buyerWalletId << 24 \| level, line)`; seed `uint128(H(FOIL_PAYOUT, word))`; claims `H(FOIL_CURRENCY, seed, ticketIndex)` / `H(FOIL_SPIN, seed, ticketIndex)` | See [Foil packs](#foil-packs) |
| Deity boon menu | `H(DEITY_MENU, menuWord, deityWalletId << 24 \| day, slot)` | `menuWord` is the preceding day's recorded word (the award-day word for a protocol draw with none); protocol issuers use their constant IDs (Vault 1, sDGNRS 2); `DeityBoonViewer` mirrors it |
| Protocol boon winners | `H(PROTOCOL_BOON_WINNER, awardDayWord, issuerWalletId, slot) % totalWeight` | Issuer ID 1 or 2; the wager cohort closed before the request |
| AFKing subscriber draw | `1 + H(SUBSCRIBER_DRAW, word) % (length - 1)` | The day's recorded word; position 0 (the Vault) is never drawn |
| WWXRP daily draw | `H(WWXRP_BIG \| WWXRP_SMALL \| WWXRP_BUCKET \| WWXRP_WINNER, word)` | `word = rngWordForDay(day + 1)`; independent tags for the gates, bucket and winner roll |
| WWXRP century incinerator | `H(WWXRP_INCINERATOR, word) % total` | Weighted stake intervals |

### Hashes outside the tag registry

These are registered `NON-RNG` in the manifest and take no VRF input:

- WWXRP draw bucket: `keccak256(abi.encodePacked(bytes32("WWXRP_DRAW_BUCKET"), block.chainid,
  address(this), uint24 day, uint32 walletId)) % 10`, over the entrant's admitted wallet ID;
  `bucketOf(day, 0)` returns 10 (no bucket).
- Affiliate payout roll: `keccak256(abi.encodePacked(AFFILIATE_ROLL_TAG,
  GameTimeLib.currentDayIndex(), buyerWalletId, code))`, deterministic and public by design.

## Intended sharing

- Every RNG period has one Degenerette house board for all ETH/FLIP bets. WWXRP reward spins apply
  the tagged rig, which can adjust the displayed board based on the player's pick.
- The packed ticket sampler groups eight draws from one sampled storage word. Equal marginal
  probabilities do not imply independent winners.
- Ticket materialization binds the physical queue index and an absolute solo offset; remaining
  debt and gas budgets do not enter the seed.
- Weighted populations, effective symbol totals and probability denominators remain inputs to
  selection arithmetic. Keeping financial values out of hash preimages does not remove economic
  weighting or eligibility conditions.

## Verification

See [Verification](../VERIFICATION.md) to run these tests and for their limits. They do not
establish statistical independence.

- `test/fuzz/JackpotEightWinnerGroups.t.sol`: ticket winners under different award budgets.
- `test/fuzz/RandomnessSeedInputs.t.sol`: box resolutions after changing only the amount.
- `test/fuzz/DegeneretteFreezeResolution.t.sol`: shared boards across owners, currencies, stakes
  and bet ids; `test/fuzz/DegeneretteFlipRoundAntiGrind.t.sol`: payout invariance under batch
  changes.
- `test/fuzz/DecimatorBattle.t.sol`: replay from the shared dice seed, exact-sample exclusion,
  payout conservation and settlement invariance across batch sizes;
  `test/fuzz/DecimatorJackpotIntegration.t.sol`: frozen preferences, generated identities,
  caller/gas partitions, allocation, ranking and per-ID payouts.
- `test/fuzz/GoldSixRules.t.sol`, `test/fuzz/TicketCheckpointDeterminism.t.sol`,
  `test/fuzz/FoilGenerationCohort.t.sol`, `test/fuzz/GoldenTicketArmResolve.t.sol`,
  `test/gas/GoldSixGas.t.sol`, `test/gas/TicketDrainWorstCaseBound.t.sol`: gold-six rules,
  checkpoint determinism (including checkpoint fuzzing) and queue rotation.
- `test/edge/MintBatchDeterminism.test.js`: reconstructs live entry buckets from the flagged solo
  events and seated reveals.
- `scripts/check-rng-shape.py`, `scripts/check-rng-taint.sh`, `scripts/check-rng-window.sh`: the
  source registry gates.
- Request, callback, retry, re-issue, nudge and deadline assertions:
  [Properties](../PROPERTIES.md#rng) and [Properties: ending](../PROPERTIES.md#terminal-ordering-and-deadlines).
