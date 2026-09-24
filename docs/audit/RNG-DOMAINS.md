# Randomness inputs and domain separation

Reviewed 2026-09-21 against the working-tree snapshot in `snapshot.json`.
The trust boundary is request → fulfillment → consumption: hashing supplies
domain separation, not fresh entropy or protection for inputs chosen after a word
is known. Existing commitment guards remain necessary.

## Changes in this snapshot

- Jackpot ETH shares and ticket award sizes no longer enter winner seeds. Each
  trait bucket derives from the unchanged root and its trait ordinal; skipping or
  changing an earlier bucket's award does not shift subsequent buckets.
- Ordinary lootbox size, presale value, redemption chunk value and AFKing amount
  no longer enter box seeds. Amounts still determine awards and applicable tables.
- Decimator claim snapshots store the low 32 bits of `keccak(word, DECIMATOR_BOX_TAG)`
  in their existing packed slot; claim-box roots re-hash that seed with the tag and the
  fixed level before the owner is mixed in.
- Craps bounty boost uses the immutable window identifier instead of the battle
  key containing financial terms.
- BAF ticket awards derive by fixed winner ordinal instead of consuming one
  mutable stream a variable number of times for previous awards.
- Unrelated boon/scatter, quest, trait-board, skim, Coinflip reward, BAF winner,
  hero-symbol, craps schedule/tie/rounding and Degenerette auxiliary draws have
  explicit domains. Numeric ordinals, owners and period identifiers provide
  uniqueness within those domains; they are not sources of entropy.

## Century-refill amendment (2026-09-22)

The century refill uses the committed transition word already passed through
`advanceGame`, retained locally across `_unlockRng`. It draws an integer percentage
from 25 through 75, inclusive, with a domain specific to this mechanism and level.
Burn amounts size the mint but do not enter the draw. The result is public once
the word is known; permissionless settlement retains its existing live-pool timing.
Repeated calls cannot reroll a completed century. See
[the random-refill verification](SDGNRS-CENTURY-RANDOM-2026-09-22.md).

## Domain map

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
| Decimator claim box | `H(roundWord, DECIMATOR_BOX_TAG, level)` then direct box resolver | Full 256-bit snapshot in the second round slot; no truncated seed or cross-round reuse |
| Direct reward box | `H(callerDerivedWord, player)` | Decimator/ETH bet caller binds the relevant level or bet; this is not an independent raw-word consumer |
| Box secondary draws | `BOX_*_SPIN_TAG`, `BOX_PASS_ROUND_TAG`, `FLIP_ROUND_TAG` | Derive from that box's root; stake only sizes payout |
| Degenerette result board | packed `H(word, uint32(index), QUICK_PLAY_SALT)` for spin 0; add `uint8(spin)` for later spins | **Shared by all ETH/FLIP players and bets in an RNG period**, including different stakes, hero symbols and currencies; WWXRP uses the same house formula on its segregated draw word |
| Degenerette player ticket | `H(H(drawWord, index, heroSymbol, spin), PLAYER_TICKET_TAG)` | Shared across owners, nonces, stakes and spin counts for the same hero; different heroes regenerate the other cells; no settlement inputs |
| Degenerette WWXRP stream | `drawWord = H(word, WWXRP_DRAW_TAG)` | Separate player and natural-house stream from ETH/FLIP; rig `H(spinSeed, WWXRP_RIG_SALT)` is shared for the same hero/round/spin |
| Degenerette survival / rounding / record | `H(word, player, betId, respectiveTag)` | Owner + per-owner bet nonce; tags `BET_SURVIVAL_TAG`, `FLIP_ROUND_TAG`, `RECORD_SPIN_TAG`; settlement batch excluded |
| Craps dice | `_crapsSeed(word, bound)` | Shared table sequence; existing engine domains and rotating shooter retained |
| Craps scatter | `H(word, SCATTER_TAG, player)` | Per-owner board, distinct from lootbox boon |
| Craps bounty boost | `H(word, bound, BOOST_TAG)` | Window identity; battle financial key excluded |
| Craps schedule | `H(word, SCHEDULE_TAG, period)` | Fixed scheduled period |
| Craps ties / rounding | `H(word, TIE_TAG, bound<<64 | seat)` / `H(word, CRAPS_ROUND_TAG, betId)` | Fixed window and entry; separate domains |
| Daily trait board | `H(word, TRAIT_BOARD_TAG)` | Four disjoint six-bit slices of a tagged word; bonus board additionally uses `BONUS_TRAITS_TAG` |
| Hero symbol | `H(heroEntropy, HERO_SYMBOL_TAG, day)` | Committed day and effective distribution |
| Jackpot recipient sampling | bucket root + trait + source salt + pull | Source salts distinguish ETH/current/carryover/purchase/far-future draws; prize size excluded |
| BAF winner list | `H(word, BAF_WINNERS_TAG)` then ordinal chain | Fixed qualified cohorts |
| BAF ticket award | `H(word, level, BAF_TICKET_TAG, winnerOrdinal)` | Previous awards cannot move this root |
| Daily / level quests | `H(word, DAILY_QUEST_TAG)` / `H(word, LEVEL_QUEST_TAG)` | Global quests; forced-type policy unchanged |
| Skim bps / variance | `H(word, SKIM_BPS_TAG)` / `H(word, SKIM_VARIANCE_TAG)` | Second variance draw hashes the first variance word |
| sDGNRS century refill | `H(word, CENTURY_REFILL_TAG XOR completedLevel) % 51 + 25` | Tag = `H("sdgnrs.century.refill")`; fixed level and transition word; no caller, amount, timestamp or pool balance in seed |
| Coinflip reward percent | packed `H(REWARD_PERCENT_TAG, word, uint24(epoch))` | Separate from gap-word and other ordinal derivations |
| Foil packs | `FOIL_SEED_TAG`, `FOIL_SPIN_TAG`, per-draw tags | Buyer, committed level/day and ticket/draw ordinal |
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
  requested itself after liveness froze purchases. `../VRF-STALL-AND-DEADMAN-PLAN.md`
  is an earlier design; the NatSpec of `_livenessTriggered`, `_vrfDead` and
  `_handleGameOverPath` states the implemented behavior.

## Regression evidence

`TerminalAffiliateKnownWord.t.sol` compares actual terminal settlements with
100 ETH versus 98 ETH plus a 2 ETH affiliate award and requires identical
recipient identities. `JackpotEightWinnerGroups.t.sol` compares ticket winners
under different award budgets. `RandomnessSeedInputs.t.sol` compares production
box resolutions after changing only amount. `DegeneretteFreezeResolution.t.sol`
checks shared boards across owners, currencies, stakes and bet nonces;
`DegeneretteFlipRoundAntiGrind.t.sol` checks payout invariance under batch changes. `DecimatorEntropy.t.sol` checks full-word
snapshot storage and the actual claim-box delegatecall for words sharing their low
32 bits and for different rounds.
See the current verification report for execution status; the inventory itself
is not a proof of statistical independence or an external audit clearance.
