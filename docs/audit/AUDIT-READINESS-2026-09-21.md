# Audit readiness — 2026-09-21

## Scope

This review covers the 26 local commits after `8330d94dbfd0cb946131f39cc90c56ee2784cdda`,
through base HEAD `1a4d06d08aa1c5e2a15575039dd66e9c8cc1e0b3`, plus the seed cleanup and
verification changes in this working tree. `snapshot.json` and `source-sha256.txt`
identify the supplied source exactly. This is preparation for external review,
not an external audit or a deployment attestation.

The recent changes include packed ticket sampling/queues, split advance stages,
genesis deities and protocol boons, VRF stall handling, foil word binding,
terminal affiliate allocation, vault comp funding and sDGNRS whale purchases.
The historical September 20 review remains available with its superseded finding
marked at the top. The proposed VRF/deadman redesign is a future plan, not part
of the implementation being verified.

## Randomness changes

Removed award amounts from jackpot recipient, ordinary box, presale, redemption
and AFKing seed preimages. Craps bounty multipliers now bind the immutable window
rather than the financial battle key. Jackpot buckets derive independently, and
BAF award roots bind the winner ordinal, so earlier award sizes cannot shift
later roots.

Separated unrelated streams for trait boards, quests, skim rates/variance,
Coinflip reward percentages, BAF recipients, hero selection, box boons and craps
schedule/scatter/ties/rounding. Decimator claim snapshots store a tagged 32-bit seed (`keccak(word, DECIMATOR_BOX_TAG)`
narrowed) in the same packed slot as before, and the claim-box root re-hashes it
with the level. No storage layout changed.
Both skim variance draws now use full-width
hashes; the previous second draw was limited to the top 64 bits of the raw word.
Degenerette auxiliary rolls bind owner and bet nonce under separate tags. Its
ETH/FLIP result boards remain shared by every player in an RNG period. The
intentional WWXRP rig remains in place. `PRESALE_BOX_TAG` is a named constant;
the literal hash is constant-foldable and no longer written inline at the call.

See `RNG-DOMAINS.md` for exact encodings, intended sharing and retained
exceptions. Hashing is domain separation, not additional entropy. Existing
commitment guards and economic weighting remain necessary. The terminal
100% versus 98% + 2% regression now requires identical recipients; the disclosed
allocation-timing edge case is retained as accepted behavior.

## Verification status

Final full-suite reconciliation is recorded in `../VERIFICATION.md`. Raw run
logs, successful affected-suite reruns, file lists, analyzer summaries and size
tables are supplied in the evidence archive. Initial failing runs are retained:
fixture repairs do not erase their history. Skips and pending tests are not passes.

Reference fixtures were updated for the new domains without raising a gas cap
or removing non-vacuity requirements. Exact all-gold board preimages are checked
against the production hash on every use. Early-bird stress still requires 128
distinct recipients, both hero draws, and 44 distinct packed source words.
Century thresholds still require all 107 distinct BAF recipients, the exact
85/108/104/100/50/0 ticket-roll shapes and 0/1/3/5/30/55 whale deferrals. The
regenerated destination-heavy word has 106 distinct recipient/level pairs and
14 far-future rolls; assertions retain at least the prior fixture's 104 and 13.

Some old references contained errors independent of the seed change: terminal
sampling used `targetLevel + 1` in its oracle; the golden-grand oracle omitted
100-FLIP truncation; a mixed-bet payout oracle omitted recursive WWXRP box spins;
and the sDGNRS bank test omitted normal passes won from lootboxes. Their checks
now include those production behaviors while preserving exact comparisons.

## Static analysis disposition

Slither 0.11.5 scanned 183 contracts with 95 detectors: 3,888 results, including
200 High, 517 Medium, 555 Low, 2,560 Informational and 56 Optimization. Aderyn
0.6.8 reports 10 High and 23 Low **categories**, not ten individual occurrences.
These are analyzer outputs requiring auditor triage, not 200 confirmed exploits
or a claim that every finding is closed.

The Slither High inventory is:

| Class | Count | Review context |
| --- | ---: | --- |
| uninitialized-state | 153 | Shared storage is read and written across delegatecall modules; inspect the whole call/storage graph |
| weak-prng | 21 | Predominantly clock/day gates; VRF-derived arithmetic is also flagged |
| incorrect-shift | 6 | Yul packed queue/bucket operations; source operand order and packing regressions are the relevant evidence |
| arbitrary-send-eth | 4 | Game, vault and sDGNRS claim/payment paths; authorization and computed claim amount need review |
| delegatecall-loop | 4 | Lootbox spin dispatch to pinned modules |
| reentrancy-balance / reentrancy-eth | 6 / 3 | Advance settlement composition and external protocol calls |
| encode-packed-collision | 2 | Subscription renderer string assembly |
| incorrect-exp | 1 | Quest pairing deliberately uses `slot ^ 1` |

The High composition differs from September 18 by +12 shared-state reports,
+4 packed-shift reports, -2 arbitrary-send reports and -1 XOR report. Raw counts
are not normalized for compiler/framework/source changes. Aderyn's weak-randomness
instance is the already disclosed catastrophic terminal `prevrandao` fallback.
Its added Low category is unused state variables. The current RNG taint inventory
contains 245 classified sites; source/interface gates and the 27-contract storage
layout oracle pass.

## Delivery tooling and limits

The audit scope now includes `PackedTicketSampleLib.sol`. The Foundry runner
covers every Solidity test in bounded compilation groups, rejects unassigned
sources and restores the exact original address pins. CI builds production
contracts with checked-in pins before testing; build failures and missing, stale,
unlinked or oversized deployment artifacts fail the size gate. The gate checks
all 32 deployment names, including `DegenerusVaultShare`.

Production runtime checks pass with checked-in and test pins. The tightest
Foundry builds are Mint at 24,546 bytes (30 spare) and Advance at 24,543 (33 spare).
Hardhat fixture pins produce Mint at 24,551 (25 spare) and Advance at 24,560
(16 spare). Further changes require a fresh build with the actual deployment pins.

The statistical suite retains its two previously disclosed red tests: the
obsolete v36 protected-source byte-identity baseline and STAT-03's empty-bucket
skip-rate expectation. The ordinary suites do not execute independent Halmos
proofs or the separate deep invariant profile. Existing accepted scheduling,
terminal fallback and settlement-order assumptions remain in `KNOWN-ISSUES.md`.

## Addendum — event-index revision `91cc40e39`

One line changed after the review above: `EntryOwnerRegistered(uint24 indexed lvl,
uint32 idx, address indexed owner)`. The game keeps the full ticket registry on chain
but no event let a wallet ask which registry positions are its own; both registry
events were indexed by level only, so a per-wallet question meant walking a whole
level. Indexing `owner` makes that lookup chain-native before the ABI freezes at
deployment. The signature and `topic0` do not change; decoders must read `owner`
from the third topic and `idx` as the only data word.

Cost was measured, not estimated, by snapshotting every Foundry test at the base
revision and again at this one under the same fixture pins: +95 gas per registration
on the canonical `_registerEntryOwner` path and +104 on the foil-buy path (a LOG topic
costs 375, the removed 32 data bytes save 256, and encoding one word instead of two
saves the rest). The largest single-test change is +0.31%. `DegenerusGameWhaleModule`
shrank by 90 bytes and `DegenerusGameFoilPackModule` grew by 6 under via-IR; every
other registry sink lost 8 bytes; `DegenerusGame` is unchanged. The full sweep,
Hardhat, the statistical suite, the eleven gates, the storage oracle and both
analyzers were re-run at this revision; the results are in `../VERIFICATION.md` and
the supplementary evidence archive. Slither and Aderyn cannot see event indexing;
their outputs are compared to the seed-domain run to show nothing else moved.

Two related events were evaluated and left alone. Emitting per-trait bucket start
offsets in `RoundTraitsGenerated` would add three to four data words (+768 to
+1,024 gas) to every seated round and still leave a wallet scanning every round of
the level, because seat owners are packed in the data and cannot be a topic.
Indexing `sender` on `DegenerusAffiliate.Affiliate` would close the same class of
gap for per-player referral history at about +119 gas per affiliated purchase; it is
a product decision and is not part of this revision. `GNRUS.LevelResolved` and the
admin proposal events are low-volume and already filterable.

Run #53 supersedes the round-event discussion above: `RoundTraitsGenerated` is replaced
by anonymous four-player `EntryTraitsRevealed` logs with composite player/level topics.
Wallet inventory now uses four topic-position filters per level and explicit anonymous
ABI decoding. The old +768..1,024-gas offset estimate applied to the removed event; it
does not price the new format. The new logs expose traits and presence, with no bucket
offsets, registry positions or round ID; Bingo proof positions remain storage reads.
`RUN53-FINAL-CONTRACTS.md` records the revised gas bounds and verification results.

## Addendum — craps extsload revision `6d02e4bfa`

`CrapsBattle` gains `extsload(bytes32) external view returns (bytes32)`, the raw storage
slot reader `DegenerusGame` already exposes. Craps had no read surface beyond
`progressivePool`, so any lens, viewer or client replay of table state had to index
history or use `eth_getStorageAt`; this mirrors that visibility to `eth_call` and
`staticcall` consumers. It is read-only, adds no storage or event, costs nothing on any
existing path, and adds 42 bytes of runtime: 24,331 bytes with checked-in pins and
24,399 with Hardhat-style fixture pins, both under the 24,576-byte limit. The
headroom rail in `test/craps/CrapsGas.t.sol` was raised from 24,300 to 24,400; it is a
project margin, not the EIP-170 limit, and had been set against a build 45 bytes smaller
than the shipped table. The full suites, gates, oracle, sizes and analyzers were re-run at
this revision; see `../VERIFICATION.md`.

## Addendum — reveal and incinerator revision `72325bd64`

Two changes merged on top of the craps extsload revision.

`EntryTraitsRevealed` replaces `RoundTraitsGenerated`. Each of the four indexed topics is
`(level << 160) | player`, so a wallet's entries at a level are four topic-position
filters against one anonymous event; the data word carries sixteen trait bytes and sixteen
presence bits, and an eight-seat round emits two logs. The event is anonymous so that all
four topics can name players; consumers must decode by explicit ABI, never by signature
discovery, and the repository's decoder check exercises the shipped browser bundle for
exactly that. `ticketGenerationStartBlock[level]` (slot 70, appended, read via
`extsload`) is stamped at deploy for levels 0 to 5 and at each fresh level-promoting RNG
request for level+5, an inclusive lower block bound for the level's first generation
window. The round's charged work rises from 37 to 38 units with the reveal emitter bounded
at 10,000 gas and no credit taken for the removed owner loop; a pinned pre-reveal FoilPack
runtime compares storage writes and decoded inventory old against new.

The x00 century incinerator no longer pays ETH. When the century flip loses, WWXRP draws
its burn-weighted winner as before and credits 10% of the FLIP that the armed BAF day's
direct depositors burned from their wallets and forfeited on that flip, as flip credit
through the coinflip's creditor lane. The basis is the coinflip's existing draw book for
the armed day (whole FLIP per deposit; bonuses, recycled stake, auto-rebuy carry and the
protocol seeds carry no weight), so no new accounting was added, and the would-be BAF pool
rolls forward whole in `futurePool` on a skip. `IncineratorResolved`'s third field is
renamed `poolWei` to `flipAward` with the same type; `resolveIncinerator` takes two
arguments. Moving the lookup and credit into WWXRP and dropping the crank's unused return
decode shrank `DegenerusGameAdvanceModule` by 160 bytes; a first attempt that kept them in
the advance module went 216 bytes over EIP-170 and was discarded.

## Addendum — WWXRP registry and decimator cap revision `d3ddb0c07`

`WWXRP.setTrustedMinter(address, bool)` is callable only by the vault owner, the DGVE-majority
check the record bounty and seat token already use, and emits `TrustedMinterSet`. A registered
address may mint any amount to any address through `mintPrize` and burn any balance from any
address through `burnForGame`, exactly as the pinned game contracts can; revocation removes both.
There is no cap, rate limit or timelock. This is intentional and total: WWXRP is the protocol's
inflationary side coin, future games are meant to pay and take it, and the vault is its
sovereign. `ECONOMIC_DISCLOSURES.md` now says WWXRP supply is at the vault owner's discretion.
The mapping is appended at slot 9 and the WWXRP layout golden re-captured.

The decimator's activity multiplier cap moves from 200,000 to 500,000 FLIP and is measured on
base burned at the level rather than on multiplied weight: a player's first 500,000 FLIP of
base carries the multiplier, base beyond it counts 1x. The per-level record gains a 40-bit
tracker in thousandths of a FLIP (each burn floored to the unit, saturating) in the free bits
of its existing slot, so the storage layout is unchanged. The weight the multiplier can add is
correspondingly larger than under the old weight-measured cap, which is the intended effect.

## Addendum — single-symbol Degenerette revision `a5d4d2cdc`

Degenerette's ticket input becomes one hero symbol (0..31; its quadrant is the hero quadrant).
The other three symbols and all four colors are generated fresh per spin from committed,
domain-separated draws, so every pick has identical expected value and no full-ticket
selection remains. Colors score independently of symbols (hero symbol 2 points, other symbols
1, each color 1; maximum 9); each gold-on-gold color match adds 25% to the payout (1x to 2x).
One shared table serves every currency: scores 2 to 9 pay 0.5x, 3x, 10x, 25x, 125x, 625x,
23,470.36x and 100,000x, a neutral return of 99.99999794% before the shared 90 to 99.9%
activity curve; ETH keeps its five extra points through four recalibrated high-tier factors;
WWXRP keeps a 5% help gate that forces one unmatched non-hero axis when 2 to 6 axes match, and
keeps its own return curve: its rigged, gold-adjusted base is normalised to exactly 70% at zero
activity, and the activity premium (to 124%, 127.6% and 130% at the shared knees) is allocated
10/30/30/30 to scores 6 to 9 through four WWXRP-specific factors, so its scheduled return runs
70% to 130%. The nine-point jackpot is 1 in 16,777,216 for every hero. Foil awards carry one seed-selected symbol of the matched line as the hero and
reroll everything else, so a boosted foil color mix cannot move the spin EV. The eight
per-gold-count tables and the separate WWXRP rig tables are gone; the module shrinks by about a
third. The exact-arithmetic model (`scripts/data/degenerette_single_symbol_math.py`), a
harness and a reference implementation test the table, the gold boost and the rig against full
enumeration. The table, the gold boost, the rig lift, both factor tables, the WWXRP floor constant and the
70% and 130% endpoints were re-derived independently by full enumeration and match the committed
constants exactly. Reviewers should note one consequence: the sDGNRS high-score award rates fire
about 1.9x as often under the new score distribution unless recalibrated.
