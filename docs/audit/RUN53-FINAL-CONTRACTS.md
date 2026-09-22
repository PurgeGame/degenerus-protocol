# Run #53 final contract verification

Baseline: `6d02e4bfa25157987159eee225e7c3673a384fd1`, with the already committed indexed
`EntryOwnerRegistered.owner` and `CrapsBattle.extsload`. This pass changes contracts and
tests without committing. Existing verification/snapshot documentation edits are separate.

## Direct player reveals

`RoundTraitsGenerated` is replaced by `EntryTraitsRevealed`, an anonymous event with four
indexed `uint256` player keys and one ABI-encoded `uint144` word. A full eight-seat round
emits it twice; a four-seat round emits once. The second event pads absent player topics
with zero. Each populated topic is `(uint256(level) << 160) | uint160(player)`.

The data word contains sixteen trait bytes in bits 0–127 and sixteen presence bits in
bits 128–143. Byte `4*j+q` belongs to topic/player `j`, quadrant `q`; presence bit
`128+4*j+q` determines whether that byte is an entry. Trait zero is valid. A trait already
contains its quadrant in its top two bits. There is no round number, registry position,
card identity or purchase-cohort identifier in the event. Presence bits describe real
entries, not a persistent partial-card object.

The simplification reduces meaningful data from the prototype's 176 bits to 144, but ABI
encoding still occupies 32 bytes. Raw logging costs are:

* Removed full-round LOG2: `375 + 2*375 + 128*8 = 2,149` gas.
* Two new LOG4s: `2*(375 + 4*375 + 32*8) = 4,262` gas.
* Raw-log increase: 2,113 gas per 32-entry full round, before the changed packing code.

`EntryRevealGas` compares the exact pre-change runtime against the candidate from identical
snapshots. For each distribution it drains 4,096 entries with a deliberately large *test*
budget, isolating event cost from changed production chunk limits. It asserts identical
ordered storage writes and decoded player/trait inventory. This is not a production gas-cap
test; production-sized chunks are measured separately.

| Entries per buyer | Before drain gas | After drain gas | Delta | Delta / entry |
|---:|---:|---:|---:|---:|
| 4 | 21,577,921 | 21,820,605 | 242,684 | 59.2490234375 |
| 32 | 19,926,817 | 20,169,501 | 242,684 | 59.2490234375 |
| 128 | 19,749,913 | 19,992,597 | 242,684 | 59.2490234375 |

The same suite runs 1,000 fuzz cases covering partial quantities, remainders, mixed seat
counts and trailing topics. No per-entry storage writes were introduced.

### Decoder and RPC compatibility

`node scripts/check-entry-reveal-decoder.mjs` passes against the **actual website browser
bundle**, `website/app/vendor/ethers-app.mjs`, ethers 6.16.0. JSON ABI fragments with
`anonymous: true`, explicit `decodeEventLog`, and `encodeFilterTopics` all work. Automatic
`Interface.parseLog` returns null and must not be used for these logs.

Query the Game address in all four topic positions, using the composite key. Union by
transaction hash + log index, then decode every matching player position in each retained
log. Anvil's Osaka `eth_getLogs` was tested for every player across all five possible
seated counts (4–8), including topic position zero, with no signature topic. All passed.
Cross-level wallet history requires enumerating level keys; composite topics do not offer
a wallet-only wildcard. Normal block/transaction/log ordering survives, but round IDs and
registry positions are intentionally absent from this inventory event.
No block explorer's automatic ABI decoding is relied on; existing explorer hyperlinks do
not participate in inventory discovery. The website still needs its new explicit reader
when the ABI is vendored; this pass does not silently convert its existing `parseLog` calls.

Named `TraitsGenerated` remains the player-filterable batch event for the thin-tail and
foil paths. Its existing RNG/batch replay is separate from the direct seated reveals.
Bingo proof **bucket positions** still come from persistent bucket storage; the new
inventory events promise player/trait/quadrant, not proof indices.

## First generation-window block

`ticketGenerationStartBlock` is a `mapping(uint256 => uint256)` appended at storage slot
**70**. Read level `L` through
`extsload(keccak256(abi.encode(uint256(L), uint256(70))))`.

* Levels 0–5 receive the deployment block in the Game constructor.
* When a fresh last-purchase daily RNG request advances the stored level to `L`, it stamps
  `L+5` with that request's block. This is an inclusive, conservative lower bound: it can
  precede the first actual generation. The request returns before ticket draining.
* Retry requests skip the level-advance branch and preserve the first block. Ordinary
  drains, future drains, and terminal drains never write this mapping.
* Every production bucket append is in Mint's per-entry generator or FoilPack's seated/
  foil generator. Ordinary targets stay in the six-level window; promoted far-future
  targets are stamped before activation; foil/terminal targets are already in that window.

A permanent mapping is used instead of recycling a tagged ring. Old levels can remain
Bingo-claimable until game over; discarding their bound would reintroduce historical
discovery work. This retains one word per **level**, not one word per entry.

Each level costs one cold zero-to-nonzero SSTORE (**22,100 gas**) plus mapping-key hashing
and short setup; the constructor performs six such writes (**132,600 gas** in SSTORE
costs). No per-entry or per-drain SSTORE is added. Runtime size grows by 15 bytes in
Advance; Game's runtime is unchanged and its initcode grows by 58 bytes.

The request uses the plain assignment
`ticketGenerationStartBlock[uint256(lvl) + 5] = block.number`. A checked uint24 addition
made Advance 24,581 bytes, five over EIP-170. Widening the new mapping's key retains the
same 32-byte key/hash for every level and makes the sum bounded by `2^24 + 4`, with no
narrowing or raw assembly SSTORE. Advance now fits at 24,558 bytes, with 18 bytes spare.
Both writes are visible to the ownership extractor: constructor `INIT`, request `OWNER`.

The layout oracle passes: all previous entries retain exactly their slot, offset and type
in Game and all 12 delegatecall modules, and each appends the same slot 70. The new
request/retry tests check initialization, unopened levels, a fresh stamp before any reveal,
retry preservation, and retention of older bounds. The first test draft needed
`vm.getBlockNumber()` to prevent via-IR rematerializing `block.number` across `vm.roll`;
that was a test-expectation issue, not a rewritten on-chain bound.

## Re-derived drain charges

The old analytical model is retained for unchanged storage operations. The changed emitter
is bounded independently, rather than treating the old unit-table test as evidence.

The optimized emitter has no input-dependent loops. Its only successful-path choices are
the seated count (4–8), the second-log condition and the three optional trailing topics.
Offsets are fixed at 0 and 4; topic values and traits do not change the instruction path.
All five cases were traced in the compiled Solidity 0.8.34 / via-IR / optimizer-1000 / Osaka
runtime. The measured region starts after the final bucket SSTORE and includes the tail of
quadrant bookkeeping through the last LOG4, so it overcounts the emitter itself:

| Seats | LOG4s | Instructions in measured region | Region gas |
|---:|---:|---:|---:|
| 4 | 1 | 314 | 3,171 |
| 5 | 2 | 433 | 5,696 |
| 6 | 2 | 457 | 5,764 |
| 7 | 2 | 481 | 5,832 |
| 8 | 2 | 500 | 5,886 |

For the production envelope, at most `1000/4 = 250` rounds can execute even if all other
charges were free. Round seeds allocate 128 bytes each; the fixed seat/frame allocation
plus these seeds stays below 64 KiB. The emitter uses one scratch ABI word without
advancing the free-memory pointer. At that bound a one-word memory expansion is at most
12 gas; a 64-gas extra memory allowance is conservative. The **10,000-gas complete emitter
allowance** therefore covers all five paths with substantial slack. The removed owner
packing loop receives no credit in the derivation.

New reveal/loop bound: `25,000 - 2,149 + 10,000 = 32,851`. `_runRound` now charges **4**
compute/event units instead of 3, and `ROUND_UNITS` rises **37 → 38**. The fully split
reservation rises **165 → 166** units; split pricing itself is unchanged.

| Step | Charge gas | Re-derived worst gas | Headroom |
|---|---:|---:|---:|
| Seated round, no split | 380,000 | 282,000 + 56,800 + 32,851 = **371,651** | **8,349** |
| Split quadrant, extra | 320,000 | 8 × 48,400 − 70,500 = **316,700** | **3,300** |
| Seat join | 20,000 | 14,200 | 5,800 |
| Dust skip | 10,000 | 9,200 | 800 |
| Seats word write | 30,000 | 22,100 | 7,900 |
| Per-entry occurrence, first 256 | 60,000 | 51,600 | 8,400 |
| Per-entry occurrence, beyond 256 | 10,000 | 3,200 | 6,800 |
| Foil pack | 830,000 | 814,400 | 15,600 |
| Fully split round | 1,660,000 | **1,638,451** | **21,549** |

`UNIT_GAS_BOUND=10,000` and `WRITES_BUDGET_SAFE=1000` remain unchanged. The analytical
ceiling remains **11,000,000 gas**, **5,777,216 below 16,777,216**. The new block metadata
is written in the constructor/request transaction, not in this drain envelope. Transition
housekeeping is separate from charged steps and runs only before the cold first future
chunk; the 35% first-chunk derate provides 3.5M of unused budget for that leg. The resumed
future chunks do not repeat the deity grants. The cold 32-deity renewal plus full future
drain fixture measures **5,657,278 gas including intrinsic** and passes its resume check.

`TicketDrainWorstCaseBound` checks the revised model's arithmetic; its pass is **not** a
measurement or independent proof of the model. The obsolete assertion about a drain-time
owner registration was removed: no such charged operation exists.

### Throughput and measured production-size work

These paired round-worker cases use identical seeded inputs and the same RNG. A row's gas
can decrease when the new charge stops one round earlier; it must not be read as a cheaper
event. "650" is the cold-first-chunk budget, not a claim that same-test seeding left storage
cold.

| Entries/buyer | Budget units | Entries before → after | Gas before → after |
|---:|---:|---:|---:|
| 4 | 1000 | 480 → 480 | 3,587,191 → 3,615,624 |
| 4 | 650 | 256 → 256 | 2,262,714 → 2,277,875 |
| 32 | 1000 | 800 → 800 | 5,277,969 → 5,325,362 |
| 32 | 650 | 448 → 448 | 3,184,605 → 3,211,142 |
| 128 | 1000 | 896 → 864 (**−32; −3.5714%**) | 5,670,573 → 5,597,448 |
| 128 | 650 | 480 → 480 | 3,366,061 → 3,394,494 |

There is no universal entries-per-call decrement: joins, bucket writes, rare splits and
survivors set the actual charge. The precise change is one more charged unit per executed
round and one more reserved unit before starting a round.

Separately, cold full-budget production-worker fixtures measure **5,225,011** gas for
single-ticket buyers, **6,641,898** for dust, and **7,034,039** for whales. These are measured
execution figures, not the 11M analytical ceiling.

## Application data recoverability

The field-by-field application audit found **no additional overwritten historical contract
value lacking both live storage and filterable event coverage**. It covers 1,028 response
fields: 49 storage, 770 indexed-event and 209 NEITHER. The NEITHER fields are service/profile/
ENS data, API presentation metadata and legacy card attribution, not lost contract history.

The detailed audit and field table are maintained with their source schemas in the database
repository: `docs/audit/RUN53-ONCHAIN-RECOVERABILITY.md` and
`docs/audit/RUN53-SCHEMA-FIELDS.tsv`. No additional contract event was required.

## EntryOwnerRegistered budget classification

| Emit site (original task coordinate) | Caller/path checked | Verdict |
|---|---|---|
| Storage:1348, `_registerEntryOwner` (now :1356 after edits) | `_queueEntries`, `_queueEntriesScaled`, `_queueEntryRangeStridedCore`, on first queue push | **Outside; no step charge affected.** Zero registry emits in a charged drain step. |
| FoilPack:99 | `queuePerpetualTickets`, at most 32 deity owners; Advance transition housekeeping precedes initialization of the future-drain budget | **Outside; no step charge affected.** Up to 32 emits in the uncharged housekeeping call, not 32 inside one charged step. |
| FoilPack:477 | `buyFoilPack` registers the owner when the buyer is enqueued; the drain reads the stored position | **Outside; no step charge affected.** |
| Whale:1057 | `_queueGenesisDeities`: two protocol owners per level, called over 100 levels by initialization | **Outside; no step charge affected.** Up to 200 initialization emits, not a drain-step multiplier. |

The drain does update owed bits in an **existing** registry record. The old comment saying
it never writes a registry slot was imprecise and is corrected; it never allocates a record
or emits `EntryOwnerRegistered`. Thus `N × 104` is **0 for every charged step** at all four
sites. The foil-grand path banks pass claims rather than registering new queued owners.

## Build sizes and tests

`forge build --sizes` was run with production contracts only (empty Foundry test/script
roots), before and after. Runtime byte counts and headroom below EIP-170's 24,576 bytes:

| Contract | Before | After | Delta | Headroom |
|---|---:|---:|---:|---:|
| DegenerusGame | 24,220 | 24,220 | 0 | 356 |
| DegenerusGameFoilPackModule | 19,227 | 19,787 | +560 | 4,789 |
| DegenerusGameWhaleModule | 22,575 | 22,575 | 0 | 2,001 |
| CrapsBattle | 24,331 | 24,331 | 0 | 245 |
| DegenerusGameAdvanceModule | 24,543 | 24,558 | +15 | **18** |
| DegenerusGameMintModule | 24,538 | 24,538 | 0 | **38** |

Full Foundry suite before the ownership-gate cleanup: **2,557 distinct tests passed,
0 failed, 103 existing skips** (2,660
distinct tests). All 2,653 tests from the preceding verification remain covered with the
same statuses; seven new tests pass. The repository's bounded compilation runner invokes
`forge test -vv` for every assigned source group, with isolated Foundry address pins. The
group totals contain 40 duplicate passing executions from imported suites; these are
excluded from the distinct total.

| Group | Passed | Failed | Skipped |
|---|---:|---:|---:|
| integration-gas | 687 | 0 | 13 |
| repro-symbolic (final corrected test) | 177 | 0 | 0 |
| fuzz-1 | 436 | 0 | 22 |
| fuzz-2 | 331 | 0 | 23 |
| fuzz-3 | 402 | 0 | 15 |
| fuzz-4 | 431 | 0 | 30 |
| invariants | 133 | 0 | 0 |

The storage-layout oracle, browser decoder check and all raw-RPC anonymous filters pass.

The ownership-gate cleanup replaces the metadata assembly write with the ordinary
assignment above and updates the two writer rows. The unchecked manifest removes the
deleted owner-packing block and renumbers the three following blocks, preserving their
bounds. The source gates and targeted metadata/reveal/transition tests are rerun for this
cleanup: **all eleven source gates pass**, with **141 live writer pairings / 141 manifest
rows** and **159 live unchecked blocks / 159 manifest rows**. The isolated targeted
Foundry run passes **16/16**, zero failures or skips, including six imported support tests.
The three 4,096-entry reveal measurements remain unchanged at +242,684 gas each, and
the cold deity/transition fixture remains 5,657,278 gas including intrinsic. The complete
suite was not rerun after this cleanup; its preceding result is listed above.

The layout oracle was rerun against this source tree with a dedicated fresh output/cache
directory, not the main tree's mixed artifacts: **all 27 layout goldens match**, including
Game and all 12 delegatecall modules. Only the newly added slot 70 key type changed from
the first draft; every pre-existing slot, offset and type is unchanged.

No production test decodes `EntryOwnerRegistered.owner` from event data. The positional
`RoundTraitsGenerated` consumers were `test/fuzz/RoundDrain.t.sol` and
`test/fuzz/SnapValve.t.sol`; both now decode the anonymous format. The rare-color test still
checks distinct symbols across all eight players, combining both logs. `QueueWordCache`
compares raw event bytes and therefore its **independent uncached** reference was refreshed
only for the event/charge change. The newly added `EntryRevealGas` intentionally decodes
the old event from its pinned pre-change reference to prove inventory parity.

Evidence directory: `/home/zak/.cache/purgegame-tmp/run53-final/` (paired measurements,
opcode traces, raw-RPC filter checks, build logs, field inventory and isolated suite logs).
Cleanup evidence: `/home/zak/.cache/purgegame-tmp/run53-gate-closeout/` (fresh production
artifacts, sizes, layout oracle, source gates and targeted regression tests).

Final-set verdict: **This contract set is final for the requested scope; Part 4 opened no
new contract question.** No commits were made.
