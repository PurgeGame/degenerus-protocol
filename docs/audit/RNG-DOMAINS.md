# Randomness inputs and domain separation

Initially reviewed 2026-09-21; Decimator and jackpot battle descriptions updated
against `3c79c1486` on 2026-09-28, and the Decimator entries for the battle rewrite on
2026-09-29. See `snapshot.json` for the supplied source identity.
The trust boundary is request → fulfillment → consumption: hashing supplies
domain separation, not fresh entropy or protection for inputs chosen after a word
is known. Existing commitment guards remain necessary.

## Changes in this snapshot

- Jackpot ETH shares and ticket award sizes no longer enter winner seeds. Each
  trait bucket derives from the unchanged root and its trait ordinal; skipping or
  changing an earlier bucket's award does not shift subsequent buckets.
- Ordinary lootbox size, presale value, redemption chunk value and AFKing amount
  no longer enter box seeds. Amounts still determine awards and applicable tables.
- Decimator battle snapshots retain the full 256-bit word. Distinct dice, board,
  final-coin and tie tags separate draws; dice exclude entry identity, the other roots include it.
- Craps bounty boost uses the immutable window identifier instead of the battle
  key containing financial terms.
- BAF ticket awards derive by fixed winner ordinal instead of consuming one
  mutable stream a variable number of times for previous awards.
- Unrelated boon/scatter, quest, trait-board, skim, Coinflip reward, BAF winner,
  hero-symbol, craps schedule/tie/rounding and Degenerette auxiliary draws have
  explicit domains. Numeric ordinals, owners and period identifiers provide
  uniqueness within those domains; they are not sources of entropy.

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
| 32–191 | Player address |
| 0–31 | Zero while hashing the identity |

For absolute **solo** offset `i`, a sixteen-entry group uses
`keccak256(abi.encode(identity, committedWord, uint256(i / 16)))` and the existing
uint64 LCG/distribution within that group. Solo offset starts at zero when an
owner first enters solo processing, including a survivor of canonical seated
rounds. It never includes the mutable remaining balance, global registry ID,
transaction gas, call count or an unrelated write-cohort mutation. Unfinished
solo runs stop only after a multiple of sixteen entries. The final tail resolves
its fraction and clears debt and progress atomically; a winning fraction is one
additional emitted entry, not one additional whole debt to subtract.

The fraction uses
`keccak256(abi.encode(uint256(keccak256("DEGENERUS_TICKET_REMAINDER_V2")), identity, committedWord)) % 100 < remainder`.
Round and solo engines use that same immutable fractional identity. Round traits
retain `keccak256(abi.encode(level, globalRound, committedWord))`. A round must
first fill eight live seats or reach the actual frozen frontier; incomplete
selection cannot roll or send waiting entries through the solo engine. Surviving
seats preserve queue order. No other work may change the global round counter.

`TraitsGenerated(address,uint256,uint32)` retains its ABI. The emitted key is
`identity | absoluteStartOffset`, so a decoder clears its low32 bits before group
hashing. The event’s count includes any final fractional bonus; no prior event in
the transaction is required to recover the offset. Widened local arithmetic
allows the final group to end at `2^32` without wrapping. Foil events use domain
`0x23` and offset zero; they retain their existing four-line, buy-time-boosted
`FOIL_SEED_TAG` algorithm. Seated `EntryTraitsRevealed` events directly reveal the
credited entries and their ordered owners.

Producer order is also part of the invariant. Normally ordinary queues precede
the committed future pool and foil FIFO. If a parity dependency starts foil early,
its continuation keeps precedence across transactions, even after its first pack
makes a buffer ready. Only the exact older queue blocking the FIFO head may
interrupt it. Foil levels need not be monotonic. Terminal continuation preserves
an active solo offset and seats when finishing the same old cohort on its old
word; genuine repoints, completed queues and retired buffers clear progress.

Each indivisible miner operation, including its complete checkpoint tail, must
fit within 10M gas. There is no fixed transaction gas cap: a transaction may
perform several operations. Available gas may select an earlier safe checkpoint,
with the complete flush reserved; it must not change the final ticket inventory.
Actual failures still revert atomically, and an OOG failure cannot become an
allowed terminal or prize-delivery fallback. Miner compensation requires at least
1M measured execution gas and successful nonterminal progress; entry gas is not
an eligibility condition.

## Century-refill amendment (2026-09-22)

The century refill uses the committed transition word already passed through
`advanceGame`, retained locally across `_unlockRng`. It draws an integer percentage
from 25 through 75, inclusive, with a domain specific to this mechanism and level.
Burn amounts size the mint but do not enter the draw. The result is public once
the word is known; permissionless settlement retains its existing live-pool timing.
Repeated calls cannot reroll a completed century.

## Daily retention and foil cohorts (2026-10-01)

The game retains two full daily words under `day & 1`, authenticated by two
absolute uint24 day tags in slot 34. `rngWordForDay` exposes only today and
yesterday, returning zero for future, expired, or mismatched tags. Internal
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

Foil purchases freeze level, boost, and activity score and join the normal ticket
write cohort. The next request freezes that cohort; purchases made after the
request require a later word. Materialization stores four uint32 lines in the
existing foil record, together with readiness, first eligible draw, and the pack's
actual generation day. Claims never reconstruct pack lines from a daily word.
Each `dailyFoilDraw[day & 1]` keeps board bits 0–31 and level bits 64–87, plus a
128-bit payout seed in bits 88–215, a format flag at bit 216, and the exact day
in bits 217–240. Every reader authenticates the day tag. The seed is
`uint128(H(committedWord, logicalDay, keccak256("foil-payout-seed")))` and seals
with the board in one write. A same-day or newer tagged record makes the writer
return without changing state, emitting a replacement board, or reverting the advance. Match
currency and spin hash this saved seed with day, ticket index, and their existing
separate tags; they no longer depend on retained daily words. A zero seed is valid
with the flag set; unseeded records are rejected. This is a predeployment format
change, with no legacy-state migration.

Foil match claims are open on the draw day and following day, and expire on D+2
even if the record has not yet been overwritten. Internal jackpot processing may
still read an older, exactly tagged logical day while completing a stalled draw.
Pack readiness, first-eligible draw, and exact level checks still apply. Each
player's match markers occupy one reusable word: two day-tagged lanes, each with
four ticket bits. The liveness/game-over cutoff still closes claims. Golden foil claims retain the
generation-day and next-day window; WWXRP payouts retain resolving day D and D+1
(where D is participation day plus one). Both expire on D+2. The foil grand remains
a push during materialization. The initial level-0 idle deadline is 250 days.

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

Recovery takes Coinflip wins directly from bits 1 through 31 of the committed
raw recovery word, leaving bit 0 for the recovery day's normal flip. Each gap
bit is anchored to the originally requested start day, even when retrying an
already-settled prefix. Gap rewards are fixed at 100% profit: double the stake
on a win, zero on a loss, before the existing auto-rebuy bonus. The recovery day's
normal reward draw is unchanged. Ordered backing and
record-pool settlement is unchanged. The eight-bit results are stored in batches
of 32 days per storage word. Other daily consumers retain only the final gap
day's derived word, `H(rawRoot, gapDay)`; its parity does not specify that day's
Coinflip outcome. Coinflip result history continues independently of the two
full-word slots; old gap words have no archive.

Live sDGNRS redemptions pin the final settlement session word for both manual
claims and the mandatory bounded keeper drain. Half the rolled ETH credits
game claimable and half opens a redemption lootbox, subject to the existing dust
rule; surviving escrow FLIP credits its owner. Terminal redemptions retain their
roll, receipt, and global ETH reservation until an authorized withdrawal. They
have no expiry and need no historical RNG for that withdrawal.

Miner compensation is separate from these outcome domains. It measures execution gas,
requires at least 1M gas and successful nonterminal progress, and uses capped
`block.basefee` with an age-based FLIP multiplier. The accepted callback timestamp
occupies the low 48 bits of `lootboxRngPacked` solely as a reward-age anchor; no
entropy derivation or consumer payout reads those bits. Partial work preserves
that timestamp. New daily requests and scheduled maintenance use their own due-time
anchors, and optional standalone midday requests use the base tier. Admin transport
retries are outside the mining chain and receive no miner compensation. The miner
selector is caller-independent; only explicit donor requests can spend LINK credit.
Gas price, work age and the multiplier affect miner stake compensation only.

## Domain map

Jackpot-phase quadrant conversion uses
`H(bucketEntropy, keccak256("jackpot-quadrant-whale"), dailyIdx, level)` as its
pass root, where `bucketEntropy = H(effectiveEthDrawEntropy, quadrant)` is the
unchanged quadrant seed. `H(passRoot, 1)` selects one real or virtual deity entry
in that quadrant's official winning trait. The separate root excludes allocation
and pass quantity, and never selects from the ETH recipient list. The solo ETH
winner remains the golden-ticket candidate. `WhaleModule.awardWhalePass` uses
this domain for quadrant mode and the existing early-bird domain below for its
early-bird mode; the caller fixes the mode.

The early-bird surplus pass draw uses
`H(word, keccak256("early-bird-whale"), dailyIdx, level + 1)` to select among
the eligible gold traits of the day's board outside its solo quadrant, or all
eligible traits there when none is gold; the solo quadrant serves only when it is
the one eligible bucket. The solo quadrant is the ETH leg's pick, from
`H(word, level)`, passed in by the caller. Entry selection uses
`H(root, 1) % (realLength + virtualDeityCount)` directly, then resolves the packed
owner or deity. A single recipient needs no grouped word cursor. It reads the same
frozen source inventory and official hero-adjusted board as the ticket leg. Pool
size, pass quantity and previous ticket winners are excluded.
The existing early-bird ticket salts 239–242 remain unchanged. There is no
additional VRF request, and an empty eligible set consumes the pending award.

`H` means Keccak-256. Unless marked packed, fields use 32-byte ABI words;
`EntropyLib.hashN` and the craps `_hashN` helpers use that same layout. Tags are
named constants in the consumer; full string hashes are constant expressions.

| Consumer | Root or domain | Sharing / fixed inputs |
| --- | --- | --- |
| Ordinary box roll | `H(word, player, BOX_OPEN_TAG, nonce)` | Nonce advances across tiers in the stored order; size excluded |
| Ordinary box boon | `H(word, player, BOX_BOON_TAG, index)` | Separate from reward rolls and craps scatter; tier nonce for each boon draw |
| Presale box | packed `H(word, PRESALE_BOX_TAG, player, uint48(index))` | One record per owner/index; amount excluded |
| Redemption box | `H(chunkWord, player, REDEMPTION_BOX_TAG)` | Chunk word advances by `H(word)`; upstream redemption word fixed |
| AFKing box | `H(word, player, AFKING_BOX_TAG, stampedDay)` | Day recorded before fulfillment; amount excluded |
| Decimator battle | `H(tag, fullWord, level[, entryId])` | Tags `decimator.battle.dice.v1`, `.board.v1`, `.final-coin.v1`, `.tie.v1`; dice omit entry id, others include it; engine survival/boost uses frozen owner |
| Direct reward box | `H(callerDerivedWord, player)` | ETH bet caller binds the relevant bet; this is not an independent raw-word consumer |
| Box secondary draws | `BOX_*_SPIN_TAG`, `BOX_PASS_ROUND_TAG`, `FLIP_ROUND_TAG` | Derive from that box's root; stake only sizes payout |
| Degenerette result board | packed `H(word, uint32(index), QUICK_PLAY_SALT)` for spin 0; add `uint8(spin)` for later spins | **Shared by all ETH/FLIP players and bets in an RNG period**, including different stakes, hero symbols and currencies. Only ETH/FLIP bets use it; WWXRP is not a bet currency |
| Degenerette player ticket | `H(H(word, index, heroSymbol, spin), PLAYER_TICKET_TAG)` | Shared across owners, bet ids, stakes and spin counts for the same hero; different heroes regenerate the other cells; no settlement inputs |
| WWXRP box/foil spin | `H(boxSpinSeed, WWXRP_DRAW_TAG)`, result `H(that, RESULT_TICKET_TAG)` | Internal box and foil reward spins only (no player-funded WWXRP bets); derived from that box's root, separate from the ETH/FLIP board; rig `H(spinSeed, WWXRP_RIG_SALT)` |
| Degenerette survival / rounding / record | `H(word, player, betId, respectiveTag)` | Owner + index-scoped bet id (queue position + 1, see DEGENERETTE-BET-QUEUE.md); tags `BET_SURVIVAL_TAG`, `FLIP_ROUND_TAG`, `RECORD_SPIN_TAG`; settlement batch excluded |
| Craps dice | `_crapsSeed(word, bound)` | Shared table sequence; existing engine domains and rotating shooter retained |
| Craps scatter | `H(word, SCATTER_TAG, player)` | Per-owner board, distinct from lootbox boon |
| Craps bounty boost | `H(word, bound, BOOST_TAG)` | Window identity; battle financial key excluded |
| Craps schedule | `H(word, SCHEDULE_TAG, period)` | Fixed scheduled period |
| Craps ties / rounding | `H(word, TIE_TAG, bound<<64 | seat)` / `H(word, CRAPS_ROUND_TAG, betId)` | Fixed window and entry; separate domains |
| Daily trait board | `H(word, TRAIT_BOARD_TAG)` | Four disjoint six-bit slices of a tagged word; one board per day, re-rolled identically by the day's later legs |
| Hero symbol | `H(heroEntropy, HERO_SYMBOL_TAG, day)` | Committed day and effective distribution |
| Jackpot recipient sampling | bucket root + trait + source salt + pull | Source salts distinguish ETH/current/early-bird/purchase draws; prize size excluded |
| Jackpot battle field | `H(word', level, FAR_FUTURE_FLIP_TAG)`, then `H(battleWord, visitOrdinal)` | `word'` is the day word, or on level 1's purchase days `H(word, LEVEL_ONE_FILL_SALT)`; each visit chooses an eligible level and circular start, then walks that level once; continuation preserves the visit across chunks |
| Jackpot pool multiplier | `H(battleWord, JACKPOT_MULT_TAG)` | Fixed battle root; the 5% high-reserve contribution is removed before this multiplier |
| High-roller reserve gate / recipient | `H(battleWord, HIGH_RESERVE_DRAW_TAG, slot)` / `H(battleWord, HIGH_RESERVE_WINNER_TAG, slot<<32 \| eligibleOrdinal)` | One field-wide 1-in-10 gate; reservoir sampling over canonical paid high seats, excluding sDGNRS; resumable cursor and nominee, no caller-chosen candidate |
| BAF winner list | `H(word, BAF_WINNERS_TAG)` then ordinal chain | Fixed qualified cohorts |
| BAF ticket award | `H(word, level, BAF_TICKET_TAG, winnerOrdinal)` | Previous awards cannot move this root |
| Daily / level quests | `H(word, DAILY_QUEST_TAG)` / `H(word, LEVEL_QUEST_TAG)` | Global quests; forced-type policy unchanged |
| Skim bps / variance | `H(word, SKIM_BPS_TAG)` / `H(word, SKIM_VARIANCE_TAG)` | Second variance draw hashes the first variance word |
| sDGNRS century refill | `H(word, CENTURY_REFILL_TAG XOR completedLevel) % 51 + 25` | Tag = `H("sdgnrs.century.refill")`; fixed level and transition word; no caller, amount, timestamp or pool balance in seed |
| Coinflip reward percent | packed `H(REWARD_PERCENT_TAG, word, uint24(epoch))` | Normally resolved days only; gap rewards are fixed at 100% profit, with win/loss from raw recovery bits |
| Foil packs | `FOIL_SEED_TAG` on frozen normal cohort word; `FOIL_CCY_TAG` / `FOIL_SPIN_TAG` on immutable packed payout seed | Stored lines bind buyer, level and ticket ordinal; payout binds draw day and ticket ordinal |
| Protocol/deity boons | existing issuer/day/slot domains | Shared issuer menu intentional; winner cohort closed before request |
| Incinerator / WWXRP draws | existing contract/day/draw domains | Weighted stake intervals choose probability, not hash input entropy |

## Intended sharing and retained exceptions

- The WWXRP Degenerette rig remains intentional: a tagged adjustment can change
  its displayed board based on the player's pick. The ETH/FLIP shared-board rule
  does not remove that mechanic.
- Coinflip win/loss and the BAF fire gate intentionally share raw bit 0.
  Redemption's raw `(word >> 8)` roll excludes that bit. Hash-derived consumers
  must not be described as consuming independent raw bit slices.
- The packed ticket sampler intentionally groups eight draws from one sampled
  storage word. Equal marginal probabilities do not imply independent winners.
- Ticket materialization includes `owed` in its packed base key. It is the
  emission/resume cursor as well as a remaining quantity; removing it would
  repeat batch streams. Queue position, group index and fixed work budgets remain
  part of deterministic materialization.
- Weighted populations, effective symbol totals and probability denominators
  remain inputs to selection arithmetic. Removing financial values from hash
  preimages does not remove economic weighting or eligibility conditions.
- Affiliate selection and salvage quotes are intentionally deterministic/public;
  they are not fresh VRF draws.
- There is no entropy fallback. A VRF request unanswered for 14 days ends the
  game deterministically with no word at all: the terminal level's tickets share
  the pot (`claimDeadVrf`). A normal ending draws only on a terminal word it
  requested itself after liveness froze purchases. The NatSpec of
  `_livenessTriggered`, `_vrfDead` and
  `_handleGameOverPath` states the implemented behavior.

## Regression evidence

`TerminalAffiliateKnownWord.t.sol` compares actual terminal settlements with
100 ETH versus 98 ETH plus a 2 ETH affiliate award and requires identical
recipient identities. `JackpotEightWinnerGroups.t.sol` compares ticket winners
under different award budgets. `RandomnessSeedInputs.t.sol` compares production
box resolutions after changing only amount. `DegeneretteFreezeResolution.t.sol`
checks shared boards across owners, currencies, stakes and bet ids;
`DegeneretteFlipRoundAntiGrind.t.sol` checks payout invariance under batch changes.
`DecimatorBattle.t.sol` checks real-engine replay from the shared full-word dice seed,
final-coin exclusion, payout conservation and settlement invariance across batch sizes.
See [Verification](../VERIFICATION.md) to run these tests and understand their
limits. This inventory does not establish statistical independence.
