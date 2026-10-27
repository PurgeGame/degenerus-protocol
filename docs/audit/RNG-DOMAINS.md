# Randomness inputs and domain separation

Initially reviewed 2026-09-21; Decimator and jackpot battle descriptions updated
against `3c79c1486` on 2026-09-28, and the Decimator entries for the battle rewrite on
2026-09-29. Hash preimages, tags and storage positions below describe the current source
revision; see `snapshot.json` for the supplied source identity.
Every derivation below is `EntropyLib.hashN(RngTags.X, ...)` with the numeric domain
constant first, defined once in `contracts/libraries/RngTags.sol`; the registry of hash
sites is `scripts/rng-shape-manifest.json`. The single exception is the coinflip win bit
(raw word bit 0 of the coin word, see below).
The trust boundary is request → fulfillment → consumption: hashing supplies
domain separation, not fresh entropy or protection for inputs chosen after a word
is known. Existing commitment guards remain necessary.

## Changes in this snapshot

- Jackpot ETH shares and ticket award sizes no longer enter winner seeds. Each
  trait bucket derives from the unchanged root and its trait ordinal; skipping or
  changing an earlier bucket's award does not shift subsequent buckets.
- Ordinary lootbox size, redemption chunk value and AFKing amount
  no longer enter box seeds. Amounts still determine awards and applicable tables.
- Decimator battle draws use the full 256-bit published session word. Distinct dice, board,
  sample and tie tags separate draws; dice exclude entry identity. Sampling hashes a
  rotation and stratum offset; board/tie roots include the nonoverlapping entry ID.
- Craps bounty boost uses the immutable window identifier instead of the battle
  key containing financial terms.
- BAF ticket awards derive by fixed winner ordinal instead of consuming one
  mutable stream a variable number of times for previous awards.
- Unrelated boon/scatter, quest, trait-board, skim, Coinflip reward, BAF winner,
  hero-symbol, craps schedule/tie/rounding and Degenerette auxiliary draws have
  explicit domains. Numeric ordinals, owners and period identifiers provide
  uniqueness within those domains; they are not sources of entropy.

## Compact lootbox orders on 2026-10-17

Ordinary purchases carry one box type, and the queue packs three 85-bit orders per word.
Every seed keeps its logical identity: the queued root hashes the buffer's published session
word and the logical position, the event tag carries `position << 1 | buffer`, and each
order's box nonces run from 1. The packed word, the word index and the lane number enter no seed.
The frozen activity score is stored as a 12-bit code and the opener uses its decoded value;
the score is a payout input, never a seed input. Redemption, AFKing and direct box seeds are
unchanged.

## Jackpot price and hidden subsidy on 2026-10-05

The public jackpot price decodes the low two bits of the period-five
schedule root `H(CRAPS_SCHEDULE, dailyWord, 5)`. This period was already separate
from ordinary-window and high-multiple draws. Price freezes in the opening terms
and is copied into the round at request lock; the original word can later retire.

The hidden subsidy uses `H(CRAPS_SUBSIDY, battleWord)`
and buckets modulo 100 at 60/90/99. The event multiplier uses
`H(CRAPS_JACKPOT_MULT, battleWord)` with its own buckets. Both consume the
future committed battle word, not the known opening word. The field, fee, award
target, baseline and reserve contribution lock before that future word; preparation
persists the two results once, across resumed chunks. The extra hash is domain
separation, not an additional VRF request.

## Ticket checkpoint generator V2 (2026-10-02)

Ticket materialization is owned by `DegenerusGameTicketModule`. This is an
intentional predeployment change to ordinary ticket outcomes: legacy seeds
contained remaining owed and call-local progress, so changing a batch split
changed the traits. The new output must be identical across every successful
stopping schedule, including lower transaction gas, cold/warm storage and access
lists. The invariant compares each trait bucket’s **ordered owner lanes**, final
round counter, consumed debts and downstream fixed-input samples, not merely
owner/trait histograms.

An ordinary solo identity packs:

| Bits | Value |
| --- | --- |
| 248–255 | `0x20` ordinary half zero; `0x21` ordinary half one; `0x22` frozen future |
| 224–247 | Absolute level |
| 192–223 | Frozen queue position |
| 64–191 | Zero |
| 32–63 | Owner's wallet ID (event only; zeroed before hashing) |
| 0–31 | Zero while hashing the identity |

For absolute **solo** offset `i`, a sixteen-entry group uses
`H(TICKET_TRAITS, committedWord, identity, i / 16)` with the wallet-ID field zeroed, and the
existing uint64 LCG/distribution within that group. Solo offset starts at zero when an
owner first enters solo processing, including a survivor of canonical seated
rounds. It never includes the mutable remaining balance, wallet ID, global registry ID,
transaction gas, call count or an unrelated write-cohort mutation. Unfinished
solo runs stop only after a multiple of sixteen entries. The final tail resolves
its fraction and clears debt and progress atomically; a winning fraction is one
additional emitted entry, not one additional whole debt to subtract.

The fraction uses
`H(TICKET_REMAINDER, committedWord, identity) % 100 < remainder`, with the wallet-ID field of
`identity` zeroed.
Round and solo engines use that same immutable fractional identity. Round traits
use `H(TICKET_ROUND, committedWord, level, globalRound)`. A round must
first fill eight live seats or reach the actual frozen frontier; incomplete
selection cannot roll or send waiting entries through the solo engine. Surviving
seats preserve rotated queue order. No other work may change the global round counter.

Each frozen ordinary or future queue starts at
`H(TICKET_ROTATION, committedWord, queueKey) % frozenLength`
and wraps once. The start is recomputed, not stored. Checkpoint cursors and seats
use logical positions in that rotation; fractional and solo stream identities
continue to use the original physical queue index. Changing gas cannot select a
new start. This removes permanent front-of-queue priority without shuffling or
promising equal per-ticket odds. Producer priority and the foil FIFO remain as
specified below.

`TraitsGenerated(uint32 indexed walletId, uint256 baseKey, uint32 take)`. The emitted key is
`identity | absoluteStartOffset | goldSixTakenFlag`. Bit 255 is an event-only flag
indicating that gold Dice 6 was already present before this solo run. A decoder
clears both that bit and the low32 offset before group hashing; the base domain
is still `0x20`–`0x22`. It applies the cap while replaying this run, using the flag
as its initial state. The event’s count includes any final fractional bonus; no prior event in
the transaction is required to recover the offset. Widened local arithmetic
allows the final group to end at `2^32` without wrapping. Foil events use domain
`0x23` and offset zero with the buyer's wallet ID at bits 32–63; their four buy-time-boosted
lines use `H(FOIL_LINES, word, buyerWalletId << 24 | level, line)`.
Seated `EntryTraitsRevealed` events directly reveal the credited entries and their ordered
owners; each nonzero topic is `(level << 160) | walletId`.

Gold Dice 6 (trait 253) keeps only its first natural occurrence at each full
level, shared by solo, round and foil producers. The existing live-bucket bit,
authenticated against the full buffer level, is the claim marker: production
appends always add nonzero entries and never remove them from an active level.
Solo runs read this once and share the result with event replay; round and foil
producers read it only on a gold-six candidate. A local flag covers unflushed
solo and foil entries. A level may have no
gold six. Later occurrences become one of traits 248–252, 254 or 255, selected by
`H(GOLD_REPLACEMENT, seed) % 7`. The seed is the candidate's LCG state
for solo entries, the full round seed for seated entries (at most one candidate
per round), and the full foil-line seed for packs. All replacements retain gold
color. Retired foil levels redirect every candidate because their old unique
slot can no longer be authenticated from the recycled buffer. Stored foil lines
and bucket entries agree. Gold six receives zero virtual deity entries in every
jackpot and pass sampler; a deity wallet's actual entry remains eligible.

A natural daily jackpot gold-six roll survives when
`H(GOLD_DAILY, word) % 6 == 0`; the other five outcomes select from
that same seven-die replacement pool using the separate replacement domain.
The final daily board is shared by ETH, coin, ticket and foil-match paths.
When that final board contains gold six, Dice receives the solo pool ahead of
every other gold trait. Without gold six, the existing gold tie-break and
no-gold rotation apply. The shared selector also gives natural terminal gold six
this priority; the one-in-six survival gate remains specific to daily boards.
Terminal boards retain their existing distribution. All Dice are excluded from
Degenerette hero selection and jackpot hero boosts, while natural Degenerette
spin boards retain their dice and original match odds.

Producer order is also part of the invariant. Normally ordinary queues precede
the committed future pool and foil FIFO. If a parity dependency starts foil early,
its continuation keeps precedence across transactions, even after its first pack
makes a buffer ready. Only the exact older queue blocking the FIFO head may
interrupt it. Foil levels need not be monotonic. Terminal continuation preserves
an active solo offset and seats when finishing the same old cohort on its old
word; genuine repoints, completed queues and retired buffers clear progress.

Each indivisible miner operation needs a conservative cold-path bound, including
its complete call, checkpoint and return tail. Admission requires that bound to fit
the remaining worker allowance and actual available gas. A transaction may perform
several admitted operations. Available gas may select an earlier safe checkpoint,
with the complete flush reserved; it must not change the final ticket inventory.
Actual failures still revert atomically, and an OOG failure cannot become an
allowed terminal or prize-delivery fallback. Miner compensation prices measured
execution gas above each call's first unpaid 1M and requires successful nonterminal
progress; entry gas is not an eligibility condition.

## Century-refill amendment (2026-09-22)

The century refill uses the committed transition word already passed through
`advanceGame`, retained locally across `_unlockRng`. It draws an integer percentage
from 25 through 75, inclusive, with a domain specific to this mechanism and level.
Burn amounts size the mint but do not enter the draw. The result is public once
the word is known; permissionless settlement retains its existing live-pool timing.
Repeated calls cannot reroll a completed century.

## Daily retention and foil cohorts (2026-10-01)

The game retains two full daily words under `day & 1`, authenticated by two
logical uint24 day tags in storage slot 25. `rngWordForDay` exposes the latest applied
result and its predecessor, returning zero for future, expired, or mismatched tags.
An unresolved request does not retire a published result. Internal
processing readers authenticate the same tags without a calendar cutoff: a
committed daily advance consumer can finish after midnight. AFKing boxes and
Decimator settlement use the active published session word instead of historical
daily words or separate round words. The ordinary read-completion gate waits for
AFKing boxes, live sDGNRS redemption settlement and Decimator rounds, along with
committed tickets/foil, human boxes/bets and read-bound Craps. An AFKing stamp
cannot open before its day is sealed, even while the preceding word is retained.
Craps freezes its opened window tier, high multiplier, and existing stake echo in
the scoreboard, so delayed scheduled cleanup reconstructs identical terms after
the opening-day word retires without storing another word.

Foil purchases freeze level, boost, and activity score and join the foil write
cohort, which has its own toggle. Only the next daily request (or the single
terminal swap) freezes that cohort; a mid-day request never moves foil packs, so
every pack generates from a daily word and its grand is sized inside the daily
pool freeze. Purchases made after the daily request require a later daily word. Materialization stores four uint32 lines in the
existing foil record, together with readiness, first eligible draw, and the pack's
actual generation day. Claims never reconstruct pack lines from a daily word.
Each `dailyFoilDraw[day & 1]` keeps board bits 0–31 and level bits 64–87, plus a
128-bit payout seed in bits 88–215, a format flag at bit 216, and the exact day
in bits 217–240. Every reader authenticates the day tag. The seed is
`uint128(H(FOIL_PAYOUT, committedWord))` and seals
with the board in one write. A same-day or newer tagged record makes the writer
return without changing state, emitting a replacement board, or reverting the advance. Match
currency and spin hash this saved seed with the ticket index under the separate
`FOIL_CURRENCY` and `FOIL_SPIN` tags; they do not depend on retained daily words. A zero seed is valid
with the flag set; unseeded records are rejected. This is a predeployment format
change, with no legacy-state migration.

Foil match retention advances only with published foil draws. Claims on D remain
open through the published draw frontier D+1 and expire at D+2. Calendar resets
and outstanding requests cannot expire them. Internal jackpot processing may
still read an older, exactly tagged logical day while completing a stalled draw.
Pack readiness, first-eligible draw, and exact level checks still apply. Each
player's match markers occupy one reusable word: two day-tagged lanes, each with
four ticket bits. The liveness/game-over cutoff still closes claims. Golden foil claims retain the
generation-day and next-day window measured against published daily results;
WWXRP payouts retain resolving day D and D+1 (where D is participation day plus
one) against that same result frontier. Both expire at published D+2. The foil
grand remains a push during materialization.

Pack metadata and all four lines share four reusable slots per player, keyed by
`level & 3` and authenticated by the full level in bits 208–231. Gold-paid state
lives in bit 232 of that same record. A new purchase can overwrite an occupied
slot only after its previous pack has generated, its level is below the current
game level, its generation-day gold window is closed, and neither today's nor
yesterday's sealed board references its level. This protects late generation
and fast or stalled transitions without assuming a maximum level rate. A live
collision rejects only the new purchase; it does not block the advance. Events
provide historical reconstruction after records are reused.

The stored seed fixes the board, currency, and primary spin, not all proceeds.
Stake pricing uses the draw's historical level and the pack's saved activity score.
An ETH spin still caps its ETH share at 10% of the live unfrozen future pool;
overflow is recirculated using the live lootbox state. High-score ETH spins award
sDGNRS from the current Reward pool. Waiting for pool replenishment or a different
level within the claim window can therefore change ETH, sDGNRS, and recirculation
proceeds; unclaimed matches do not reserve funds.
Claims during frozen pools retain the existing pending-pool solvency check.

The logical day starts at 1 and advances exactly once when a fresh daily VRF
request is accepted, first to 2. Coinflip receives the same requested-day mirror
atomically. Retry, coordinator replacement, midday requests and elapsed calendar
windows never increment it. Only one fresh daily request may be accepted in each
22:57 UTC reset window; unused windows create no rounds or recovery results.
Coinflip win/loss is bit 0 of the coin word (the raw daily word plus the frozen nudge
count), and every settled logical round receives its ordinary tagged reward-percent draw. There is no gap backfill, bitmap of
rolled days, recovery-bit allocation, or recovery-word domain.

The full daily certificate follows the final normal read consumer. It records
the actual completion timestamp independently of word application and jackpot
unlock. Level 0 uses purchase baseline 9: thirty completed main-game rounds reach
39, and normal expiry waits for the next real reset after completion. Later
levels use the same thirty-round rule. A funded target rescues normal expiry.
Fourteen real days since full daily completion force the hard ending before any
normal work, including during a broken consumer or funded jackpot and even while the
coordinator still answers. That ending is deterministic: it settles no loans and sends no
terminal request. Terminal entry never invokes Craps and never follows a normal payout in
the same mining call.

Live sDGNRS redemptions pin the final settlement session word for both manual
claims and the mandatory bounded miner drain. Half the rolled ETH credits
game claimable and half opens a redemption lootbox, subject to the existing dust
rule; surviving escrow FLIP credits its owner. Terminal redemptions retain their
roll, receipt, and global ETH reservation until an authorized withdrawal. They
have no expiry and need no historical RNG for that withdrawal.

Miner compensation is separate from these outcome domains. It measures execution gas,
requires more than 1M gas and successful nonterminal progress, and uses capped
`block.basefee` with an age-based FLIP multiplier. The age anchor is the later of the latest
VRF request time and the current 22:57 UTC reset; no entropy derivation or consumer payout
reads it, and the VRF callback writes no state other than the raw word. Admin transport
retries are outside the mining chain and receive no miner compensation. The miner
entry (`mineRun`) is caller-independent; a mid-day request whose pending value is below the
threshold is the only path that spends mid-day request credit, and it spends the caller's
own credit (minted by `donateVrf`, one quarter of the donated wei). Gas price, work age and the
multiplier affect miner stake compensation only.

## Request, callback and nudges

VRF requests are paid in native ETH from the coordinator subscription. `rawFulfillRandomWords`
runs in the Game itself (no delegatecall) and does three things: it requires the coordinator as
`msg.sender`; it compares the low 64 bits of the request ID with the stored `vrfRequestId`, which
is packed above the coordinator address in one storage slot (ID 0 and superseded IDs are ignored,
not reverted); and it stores the raw word. Raw words 0 and 1 are refused, which leaves the request
pending for its retry. A request whose returned ID has zero low 64 bits is refused at request
time. A consumed session keeps its answered ID, and `LootboxRngApplied.requestId` is the low 64
bits. Publication, nudge application and every consumer run later in `mineRun`.

`reverseFlip` queues nudges only while RNG is unlocked. At the daily apply, the raw word is
recorded for every consumer and `DailyRngApplied(day, word, nudges)` reports the frozen nudge
count; only the returned coin word, `word + nudges`, is used for the coinflip.

## Degenesis cohort binding

Degenesis orders draw from the daily word of the request that follows their cohort's pricing.
Every outcome input is fixed before that request:

- Order lanes (wallet ID, amount units, seconds-into-day) are written at purchase and a cohort is
  sealed once its day index is below the request day, so no order joins a cohort whose word was
  requested.
- `prepareDegenesis_g47(day)` runs in `prepareRequestBoundary` before the request: it splits sealed
  cohorts, then prices at most one nonempty cohort from its volume `V` and the `Pool.Degenesis`
  balance, writing `degenesisActive` with the bound day. Pricing requires the previous cohort to have
  closed, so a backlog delays the binding word and cannot alter a rate.
- `_recordDailyRng` copies the word into `degenesisWord` when `degenesisClosed < 7` and the bound day
  equals the recorded logical day on the daily apply path. The copy is the only way a word
  reaches the module; mid-day words never bind.
- `_degenesisOutcome` is pure in (`degenesisWord`, cohort day, `V`, `Q`, lane, index): reordering or
  partitioning settlement calls cannot change any order's reward, and the cursor only selects which
  index is paid next.
- Settlement amounts depend on `Q` and `V` frozen at pricing, never on the live pool, and category,
  size, pass side and rounding come from distinct tags on the order seed.

## Domain map

Jackpot-phase quadrant conversion starts from the allocation root
`H(JACKPOT_ALLOCATION, word, level)` (solo-adjusted), the unchanged quadrant seed source.
Each quadrant seed is `H(JACKPOT_QUADRANT, allocationRoot, quadrant)`. The pass recipient is
`H(WHALE_QUADRANT, quadrantSeed) % (realLength + virtualDeityCount)` over that quadrant's
official winning-trait bucket, resolving a real owner or the virtual deity entry; a ticket-leg
pass draws the same way under `H(WHALE_TICKET, quadrantSeed)` from the ticket plan's root. The
caller fixes the leg (`ticketLeg`). The roots exclude allocation size and pass quantity, and
never select from the ETH recipient list. The solo ETH winner remains the golden-ticket
candidate. A single recipient needs no grouped word cursor. It reads the same frozen source
inventory and official hero-adjusted board as the ticket leg. Pool size, pass quantity and
previous ticket winners are excluded. The ticket-leg sampling salts (239, 241 and 242 by leg
kind) feed `BUCKET_SAMPLE` below. There is no additional VRF request, and an empty eligible set
consumes the pending award.

`H` means Keccak-256 over 32-byte ABI words (`EntropyLib.hash1`..`hash4`). `RngTags.X` is the
numeric domain, always the first word. The few other keccak uses in the table are named where
they appear (Craps seed domain, WWXRP bucket, affiliate roll) and are registered as non-RNG or
constant entries in the manifest.

| Consumer | Root or domain | Sharing / fixed inputs |
| --- | --- | --- |
| Queued entry root | `H(BOX_ORDER, sessionWord, position)` | One 85-bit entry per purchase, three per storage word; `sessionWord` is the published word of the entry's buffer; `position` is the logical entry position (never the word index or lane); buffer and position fixed by the append before the buffer's word is requested, so identical orders sharing a word keep distinct roots |
| Ordinary box roll | `H(BOX_OPEN, entryRoot, nonce)` | Nonce is the box's 1-based position in its one-type order; size excluded; the owner's wallet ID is read from the entry and is not a hash input |
| Ordinary box boon | `H(BOX_BOON, entryRoot)` then `H(BOX_BOON_LANE, boonSeed, nonce + lane)` | Separate from reward rolls and craps scatter; box `n` draws at boon nonce `n - 1` |
| Degenesis order | `seed = H(DEGENESIS_ORDER, degenesisWord, index)`; category `H(DEGENESIS_CATEGORY, seed) % 100`, size `H(DEGENESIS_SIZE, seed)`, pass side `H(DEGENESIS_PASS, seed) & 1`, plus `DEGENESIS_ROUND` and `DEGENESIS_PASS_ROUND` on `seed`; boons `H(DEGENESIS_BOON, degenesisWord, index)` then `DEGENESIS_BOON_EXTRA` / `DEGENESIS_BOON_TYPE` | `degenesisWord` is the daily word of the cohort's bound day (one word per cohort); `index` the order's position in its cohort; the lane's reward account and amount are excluded from the seed. Separate from the queued-entry root and every box tag |
| Redemption box | `redemptionWord = H(REDEMPTION_BOX, batchWord, beneficiaryWalletId)` in sDGNRS is the entry root of the same `BOX_OPEN` / `BOX_BOON` rolls | Claim keyed by the beneficiary ID at the burn; no queue position. Roll amount `H(REDEMPTION_AMOUNT, word)`; surviving-escrow FLIP roll `H(REDEMPTION_FLIP, word)` |
| AFKing box | `H(BOX_AFKING, sessionWord, subscriberWalletId)` | `sessionWord` is the published session word at open; the stamp is recorded before fulfillment and gates when the box may open; amount excluded |
| Decimator battle | dice `H(DECIMATOR_DICE, word)`; board `H(DECIMATOR_BOARD, word, entryId)`; tie `H(DECIMATOR_TIE, word, entryId)` | `word` is the published session word; dice omit entry id, board/tie include it; engine survival salt is the entry's committed wallet ID (generated entries: the 160-bit `uint160(H(DECIMATOR_GENERATED, word, id))`); hot activation follows shared dice duration |
| Decimator survivor sample | rotation `H(DECIMATOR_ROTATION, word) % T`; stratum offset `H(DECIMATOR_SAMPLE, word, stratum)` | No-stratum hash rotates by modulo T; stratum hash selects one offset in [floor(i*T/S),floor((i+1)*T/S)); S=min(1000,ceil(T/2)); exact distinct set shared by locked generated and unlocked original workers |
| Decimator generated entries | owner `H(DECIMATOR_OWNER, word, id) % effectiveLen`; board/tie/salt as above with the generated id | IDs N+1..N+M share the original board/tie domains; allocation is fixed cumulative rounding; recipients/preferences read only for sampled entries under the daily RNG lock |
| Direct reward box | `H(BOX_DIRECT, callerDerivedWord)` | ETH bet caller binds the relevant bet (`BET_BOX`); this is not an independent raw-word consumer |
| Box secondary draws | `BOX_WWXRP_SPIN`, `BOX_FLIP_SPIN`, `BOX_ETH_SPIN`, `BOX_PASS_SPIN`, `BOX_PASS_ROUND`, `BOX_ROUND` | Each `H(tag, boxSeed)`; derive from that box's seed, stake only sizes payout |
| Degenerette result board | house `H(BET_HOUSE, word, spinIndex)` | **Shared by all ETH/FLIP players and bets in an RNG period**, including different stakes, hero symbols and currencies. Only ETH/FLIP bets use it; WWXRP is not a bet currency |
| Degenerette player ticket | `H(BET_PLAYER, word, heroSymbol, spinIndex)`, then `H(SPIN_PLAYER, seed)` for colors | Shared across owners, bet ids, stakes and spin counts for the same hero; different heroes regenerate the other cells; no settlement inputs |
| Degenerette spin internals | `SPIN_HOUSE`, `SPIN_HERO`, `SPIN_RIG`, `SPIN_RIG_PICK`, `SPIN_FLIP_ROUND`, `SPIN_SURVIVAL`, `SPIN_ROUND`, `SPIN_RECIRC` | Each `H(tag, seed)` (flip chain `H(SPIN_FLIP_ROUND, seed, i)`); internal box and foil reward spins only (no player-funded WWXRP bets); rig `H(SPIN_RIG, spinSeed)` |
| Degenerette survival / rounding / record | `H(BET_SURVIVAL \| BET_ROUND \| BET_BOX \| BET_RECORD, word, betId)` | Index-scoped bet id (queue position + 1, see DEGENERETTE-BET-QUEUE.md); settlement batch excluded |
| Craps dice / shooter | dice `H(CRAPS_DICE, word, bound)`; shooter `H(CRAPS_SHOOTER, seed)`; per roll `H(CRAPS_ROLL, seed, i)`, hand `H(CRAPS_HAND, seed, i)` | Shared table sequence; rotating shooter retained |
| Craps board / survival | board `H(CRAPS_BOARD, word, key)`; scatter `H(CRAPS_SCATTER_CHIP, word, i)`; survival `H(CRAPS_SURVIVAL, seed, round, salt)` | `key` and `salt` = the paid entry's committed owner wallet ID (bet word bits 0–31; protocol seats sDGNRS 2 / Vault 1), `uint160(H(CRAPS_AWARDED, word, betId))` for awarded entries; per-owner board, distinct from lootbox boon |
| Craps bounty boost | `H(CRAPS_BOOST, word, bound)` | Window identity; battle financial key excluded |
| Craps schedule | `H(CRAPS_SCHEDULE, word, period)`; high multiple `H(CRAPS_HIGH, word)` | Fixed scheduled period |
| Craps ties / rounding | `H(CRAPS_TIE, word, bound<<64 \| betId)` / `H(CRAPS_ROUND, word, betId)` | Fixed window and entry; separate domains |
| Daily trait board | `H(JACKPOT_BOARD, word)`; gold six `H(GOLD_DAILY, word)` and `H(GOLD_REPLACEMENT, seed)` | Four disjoint six-bit slices, then gold-six keep/redirect; one board per day, re-rolled identically by later legs |
| Hero symbol | `H(JACKPOT_HERO, heroEntropy)` | Committed day's frozen wager weights and effective distribution |
| Jackpot recipient sampling | `H(BUCKET_SAMPLE, word, salt, pull)`; FLIP level `H(FLIP_LEVEL, word, pull)`; daily share `H(JACKPOT_DAILY_BPS, word)`; ticket roll `H(JACKPOT_TICKET_ROLL, entropy)`; direct ticket groups `H(TICKET_DIRECT, root, q<<32 \| i, round)` | Source salts distinguish ETH/current/early-bird/purchase draws; prize size excluded; packed-sampler padding `H(SAMPLE_PADDING, entropy, used)` |
| Jackpot battle field | `battleWord = H(FUTURE_BATTLE, word)`, then `H(FUTURE_BATTLE_VISIT, battleWord, visitOrdinal)` | Each visit chooses an eligible level and circular start, then walks that level once; continuation preserves the visit across chunks |
| Jackpot pool multiplier / subsidy | `H(CRAPS_JACKPOT_MULT, battleWord)` / `H(CRAPS_SUBSIDY, battleWord)` | Fixed battle root; the 5% high-reserve contribution is removed before this multiplier |
| High-roller reserve gate / recipient | `H(CRAPS_RESERVE_DRAW, battleWord, slot)` / `H(CRAPS_RESERVE_WINNER, battleWord, slot<<32 \| eligibleOrdinal)` | One field-wide 1-in-10 gate; reservoir sampling over canonical paid high seats, excluding sDGNRS; resumable cursor and nominee, no caller-chosen candidate |
| BAF head awards | slot 1 `H(BAF_HEAD, word)` over the armed day's weighted depositors (Coinflip); slot 2 `H(BAF_HEAD_SIDE, word) & 1` picks third or fourth place | Frozen board and armed day; slot 0 is the top bettor |
| BAF scatter rounds | near rounds `H(BAF_NEAR_ROUND, word, round)`; far pairs `H(BAF_FAR_PAIR, word, pair)`, then `H(BAF_FUTURE_ATTEMPT, entropy, attempt)` per sampled future queue | Fixed bracket and round count |
| BAF ticket award | `H(BAF_TICKET, word, winnerOrdinal)` | Previous awards cannot move this root |
| Daily / level quests | `H(QUEST_DAILY, word)` / `H(QUEST_LEVEL, word)` | Global quests; forced-type policy unchanged |
| Pool skim / variance / keep | `H(POOL_SKIM, word)`; variance `H(POOL_VARIANCE_A, word)` and `H(POOL_VARIANCE_B, word)`; x00 keep `H(POOL_FUTURE_KEEP, word)`; BAF gate `H(BAF_GATE, word) & 1` | Independent tags on the same level-transition word |
| sDGNRS century refill | `25 + H(CENTURY_REFILL, word) % 51` | Fixed level and transition word; no caller, amount, timestamp or pool balance in seed |
| Coinflip reward percent | `H(FLIP_REWARD, coinWord)` | One result per accepted logical daily request; win/loss is bit 0 of the coin word |
| Foil packs | lines `H(FOIL_LINES, committedWord, buyerWalletId << 24 \| level, line)`; payout seed `uint128(H(FOIL_PAYOUT, committedWord))`; claims `H(FOIL_CURRENCY, seed, ticketIndex)` / `H(FOIL_SPIN, seed, ticketIndex)` | Stored lines bind the buyer's wallet ID, level and line ordinal; payout binds the draw's saved seed and ticket ordinal |
| Deity boon menu | `H(DEITY_MENU, dailyWord, deityWalletId << 24 \| day, slot)` | Protocol issuers use their constant IDs (VAULT 1, SDGNRS 2); `DeityBoonViewer` reads the deity's ID from the Game |
| Protocol boon winners | `H(PROTOCOL_BOON_WINNER, winnerWord, issuerWalletId, slot)` | Issuer wallet-ID domain (VAULT 1, SDGNRS 2); winner cohort closed before request |
| AFKing subscriber draw | `H(SUBSCRIBER_DRAW, word)` | The day's recorded daily word; the draw index is `1 + hash % (length - 1)`, so the Vault seat (position 0) is never drawn |
| WWXRP draw | `H(WWXRP_BIG \| WWXRP_SMALL \| WWXRP_BUCKET \| WWXRP_WINNER, word)` | Gates, bucket and winner roll use independent tags on the draw word |
| WWXRP draw bucket | packed `keccak256(abi.encodePacked(bytes32("WWXRP_DRAW_BUCKET"), chainid, wwxrp, uint24(day), uint32(walletId))) % 10` | The entrant's admitted wallet ID (`enterDraw` registers before hashing); no VRF word; `bucketOf(day, 0)` returns 10 (no bucket) |
| Incinerator | `H(WWXRP_INCINERATOR, word)` | Weighted stake intervals choose probability, not hash input entropy |

## Intended sharing and retained exceptions

- The WWXRP Degenerette rig remains intentional: a tagged adjustment can change
  its displayed board based on the player's pick. The ETH/FLIP shared-board rule
  does not remove that mechanic.
- Coinflip win/loss is the only consumer of a raw word bit: bit 0 of the coin word, which
  is the raw daily word plus the nudge count frozen at the request (`reverseFlip`). Nudges
  reach no other derivation: the recorded daily word, session and lootbox words, jackpots,
  quests, WWXRP, Craps and the terminal word are all the raw word. Every other consumer
  hashes a unique `RngTags` domain with the raw word, so none is described as consuming an
  independent raw bit slice.
- The packed ticket sampler intentionally groups eight draws from one sampled
  storage word. Equal marginal probabilities do not imply independent winners.
- Ticket materialization binds the original physical queue index and an absolute
  solo offset. Remaining debt and gas budgets do not enter the seed. The event-only
  gold-six flag supplies cap state for independent replay and is stripped before
  hashing the immutable identity.
- Weighted populations, effective symbol totals and probability denominators
  remain inputs to selection arithmetic. Removing financial values from hash
  preimages does not remove economic weighting or eligibility conditions.
- Affiliate selection (`keccak256(abi.encodePacked(AFFILIATE_ROLL_TAG, wallResetWindowIndex,
  buyerWalletId, code))`) is intentionally deterministic/public; it is not a fresh VRF draw.
- There is no entropy fallback. A VRF request whose word is not in use (published
  by `mineRun`) 14 days after it was sent ends the game deterministically with no
  word at all, whether the word never came or came and was never published; a word
  delivered after that point is discarded: the terminal level's tickets share
  the pot (`claimDeadVrf`). Fourteen days without a completed daily session end the game
  on the same deterministic path even if the coordinator still answers. A normal ending
  draws only on a terminal word it requested itself after liveness froze purchases. The
  NatSpec of `_endingReason`, `_vrfDeadmanFired`, `_vrfDead` and
  `_handleGameOverPath` states the implemented behavior.

## Regression evidence

`JackpotEightWinnerGroups.t.sol` compares ticket winners
under different award budgets. `RandomnessSeedInputs.t.sol` compares production
box resolutions after changing only amount. `DegeneretteFreezeResolution.t.sol`
checks shared boards across owners, currencies, stakes and bet ids;
`DegeneretteFlipRoundAntiGrind.t.sol` checks payout invariance under batch changes.
`DecimatorBattle.t.sol` checks real-engine replay from the shared full-word dice seed,
exact-sample exclusion, payout conservation and settlement invariance across batch sizes.
`DecimatorJackpotIntegration.t.sol` additionally checks frozen preferences, synthetic
run identities, caller/gas partitions, proportional eligibility, matching/allocation,
independent single-entry ranking and per-ID payouts. Field size includes original and
generated entries; above 2,000 the eligibility hash uses `hash % fieldEntries < 1000`
without another coin flip. This numeric rate binds at deterministic jackpot planning;
it is not claimed to be known before the word arrives.
See [Verification](../VERIFICATION.md) to run these tests and understand their
limits. This inventory does not establish statistical independence.

Gold-six and queue-rotation verification: `GoldSixRules.t.sol`,
`TicketCheckpointDeterminism.t.sol`, `FoilGenerationCohort.t.sol`,
`GoldenTicketArmResolve.t.sol`, `GoldSixGas.t.sol`, and
`TicketDrainWorstCaseBound.t.sol` passed 67 tests on 2026-10-02, including 1,000
checkpoint-fuzz runs. Both Hardhat `MintBatchDeterminism.test.js` checks also
passed, reconstructing live entry buckets from the flagged solo events and
direct seated reveals. In fixed, cold-account drain fixtures, round generation
rose from 2,609,018 to 2,612,643 gas (+0.14%) and solo generation from 2,233,247 to
2,243,071 gas (+0.44%). These are representative batch comparisons, not universal
upper bounds. The older `RoundDrainChunkGas.t.sol` transaction-wide-cap failures
also reproduce before this change; the current engine limits each indivisible
step and may execute several steps per transaction.

The subsequent gas review (2026-10-02, figures at that revision) reuses the live-bucket bit directly, shares each solo
cap read with its replay event, defers round/foil cap reads until an actual
candidate, and hashes queue rotation without allocating ABI memory. The common
round path no longer computes its rotation twice. Outcomes and hash preimages
are unchanged. The same cold-storage `GoldSixGas.t.sol` fixtures measured:

| Fixture | Initial gold-six implementation | After cleanup | Saved |
| --- | ---: | ---: | ---: |
| 128 solo entries | 2,243,168 | 2,242,682 | 486 |
| 320 seated entries | 2,612,734 | 2,612,081 | 653 |
| 128 solo entries, gold six already taken | 2,207,072 | 2,204,342 | 2,730 |
| Eight foil packs, gold six already taken | 2,541,830 | 2,533,070 | 8,760 |

The cleanup passed 47 focused Foundry tests, including 1,000 randomized hash
parity cases and 1,000 checkpoint-fuzz cases, plus both Hardhat ticket-replay
checks (49 passing checks total). The gas-read and RNG-taint registry checks
also passed. The extra bitmap lookup adds no storage field or write. It
is valid because all production bucket appends have positive counts and an
active level's entries are append-only; the full level stamp prevents parity
reuse from carrying an old cap forward.

## Duration-based craps hot bonus

The natural `ShooterBoost` random draw is removed. All eligible seats share hot
activation after the twelfth surviving roll; only profit on roll 13 onward gets
the seat's picked-chip percentage. Dice, scatter, survival, and rotation domains
are unchanged. Rotation adds 30 percentage points to the picked-chip bonus on
the same eligible profit from roll 13 onward; it does not boost earlier profit.
