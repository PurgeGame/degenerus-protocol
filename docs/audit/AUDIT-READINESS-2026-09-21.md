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
