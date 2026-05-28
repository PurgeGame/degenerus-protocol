<!--
================================================================================
CHUNK-MANIFEST.md — the operator's chunking / file-attachment manual (Layout B).

This file is the HUMAN-OPS companion to RNG-AUDIT-KIT.md. It is NOT pasted into
the model; it tells the operator which `contracts/` files to attach, how big they
are, and how to group them so the cross-module read-graph survives a chunked feed.

It is a NEUTRAL operations manual: file paths + sizes + grouping rationale ONLY.
It carries no freeze conclusion about any slot and no pointer to any internal
findings/catalog document. The kit and this manifest together stand alone on the
attached source.

Sizes below were measured with `wc -l` / `wc -c` against the working tree at the
authoring HEAD (the contract tree is byte-frozen at the v50.0 IMPL point — see the
companion 337-ANCHOR-ATTESTATION.md "Frozen-Subject Fact"). Re-run wc if any
`contracts/` commit lands after that point.
================================================================================
-->

# Degenerus Protocol — RNG-Audit Kit: Contract-Corpus Chunk Manifest

This manifest inventories the contract corpus the RNG-Audit Kit asks an independent model to read, sizes every file at the authoring HEAD, and defines the three feeding groups so a chunked feed never severs the cross-module read-graph. Pair it with `RNG-AUDIT-KIT.md` (the paste-into-model artifact) and its feeding recipe.

**Token basis (stated so the counts are re-derivable):** `~Tokens = ceil(Chars / 3.6)`. Dense Solidity with long identifiers tokenises at roughly 3.4–3.8 chars/token; **3.6 is used throughout and rounded up** for a conservative (slightly high) estimate. Re-run `wc -c <file>` and divide by 3.6 to reproduce any row. **Lines and Chars are written as raw integers (no thousands separators) so they match `wc -l` / `wc -c` output literally** — re-run the two `wc` commands against any row to confirm.

## Corpus Inventory

The 18-file core set (11 game modules + the shared storage + the facade + 5 peripheral contracts) plus `DegenerusQuests.sol` (the named `rollLevelQuest` VRF consume site). Lines/Chars are the live `wc -l` / `wc -c` values at the frozen authoring HEAD.

| File | Lines | Chars | ~Tokens | Group |
|------|------:|------:|--------:|-------|
| `contracts/storage/DegenerusGameStorage.sol` | 1798 | 85421 | ~23729 | RNG-CORE |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1886 | 83648 | ~23236 | RNG-CORE |
| `contracts/modules/DegenerusGameMintModule.sol` | 1699 | 69065 | ~19185 | RNG-CORE |
| `contracts/modules/DegenerusGameLootboxModule.sol` | 1896 | 91613 | ~25449 | RNG-CORE |
| `contracts/DegenerusQuests.sol` | 1915 | 81712 | ~22698 | RNG-CORE |
| `contracts/modules/DegenerusGameJackpotModule.sol` | 2149 | 86605 | ~24057 | CONSUME-B |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | 1160 | 53270 | ~14798 | CONSUME-B |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | 951 | 37938 | ~10539 | CONSUME-B |
| `contracts/modules/DegenerusGameWhaleModule.sol` | 1043 | 43017 | ~11950 | CONSUME-B |
| `contracts/modules/DegenerusGameBoonModule.sol` | 329 | 13930 | ~3870 | CONSUME-B |
| `contracts/modules/DegenerusGameGameOverModule.sol` | 264 | 12185 | ~3385 | CONSUME-B |
| `contracts/modules/DegenerusGameMintStreakUtils.sol` | 243 | 11224 | ~3118 | CONSUME-B |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | 62 | 2718 | ~755 | CONSUME-B |
| `contracts/DegenerusGame.sol` | 2908 | 137384 | ~38163 | FACADE+PERIPHERAL-C |
| `contracts/AfKing.sol` | 978 | 54083 | ~15024 | FACADE+PERIPHERAL-C |
| `contracts/BurnieCoin.sol` | 722 | 34232 | ~9509 | FACADE+PERIPHERAL-C |
| `contracts/BurnieCoinflip.sol` | 1129 | 45809 | ~12725 | FACADE+PERIPHERAL-C |
| `contracts/DegenerusJackpots.sol` | 669 | 28834 | ~8010 | FACADE+PERIPHERAL-C |
| `contracts/GNRUS.sol` | 709 | 34406 | ~9558 | FACADE+PERIPHERAL-C |
| **SUBTOTAL (18-file core set)** | **20595** | **925382** | **~257060** | |
| **TOTAL with `DegenerusQuests.sol`** | **22510** | **1007094** | **~279758** | |

> **Include `DegenerusQuests.sol` (default).** `rollLevelQuest(uint256 entropy)` is a named VRF consume site (it receives the resolution word from the consume driver), so omitting the file leaves the read-graph incomplete. Total corpus ≈ **280K tokens**. An operator who scopes the kit to the game-storage modules only may drop it; the default is to include it.

## Chunk Groups

Three groups. The whole corpus fits one large-context model in a single feed (see the kit's feeding recipe); the groups exist for the chunked path (a web chat UI, or a model whose standard window sits below ~280K). Group token sums use the inventory rows above.

### Group RNG-CORE (~114297 tokens) — the irreducible core; never split it

| File | ~Tokens |
|------|--------:|
| `contracts/storage/DegenerusGameStorage.sol` | ~23729 |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | ~23236 |
| `contracts/modules/DegenerusGameMintModule.sol` | ~19185 |
| `contracts/modules/DegenerusGameLootboxModule.sol` | ~25449 |
| `contracts/DegenerusQuests.sol` | ~22698 |

This group holds the slot layout + the three write-time gates (`DegenerusGameStorage.sol`), the lock lifecycle + the VRF entry/callback + the consume driver (`DegenerusGameAdvanceModule.sol`), the trait derivation that consumes the committed lootbox word (`DegenerusGameMintModule.sol`), the box-open path + the per-index word read (`DegenerusGameLootboxModule.sol`), and the named `rollLevelQuest` consume site (`DegenerusQuests.sol`). **Keep these five together — this is the irreducible core; never split it.** Splitting it would put the lock gate and the slot it gates in different feeds.

### Group CONSUME-B (~72472 tokens) — downstream consumers + the whale-claim materializer (re-attach Storage)

| File | ~Tokens |
|------|--------:|
| `contracts/modules/DegenerusGameJackpotModule.sol` | ~24057 |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | ~14798 |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | ~10539 |
| `contracts/modules/DegenerusGameWhaleModule.sol` | ~11950 |
| `contracts/modules/DegenerusGameBoonModule.sol` | ~3870 |
| `contracts/modules/DegenerusGameGameOverModule.sol` | ~3385 |
| `contracts/modules/DegenerusGameMintStreakUtils.sol` | ~3118 |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | ~755 |

The downstream modules the resolution word and the participating slots reach, including the `claimWhalePass` materializer in `DegenerusGameWhaleModule.sol` and the whale-claim counter writers in `DegenerusGamePayoutUtils.sol` / `DegenerusGameJackpotModule.sol`. **Re-attach `DegenerusGameStorage.sol` with this group** (see the Storage-Travels Rule below).

### Group FACADE+PERIPHERAL-C (~92989 tokens) — the dispatcher + peripheral contracts (re-attach Storage)

| File | ~Tokens |
|------|--------:|
| `contracts/DegenerusGame.sol` | ~38163 |
| `contracts/AfKing.sol` | ~15024 |
| `contracts/BurnieCoin.sol` | ~9509 |
| `contracts/BurnieCoinflip.sol` | ~12725 |
| `contracts/DegenerusJackpots.sol` | ~8010 |
| `contracts/GNRUS.sol` | ~9558 |

The delegatecall facade/dispatcher (`DegenerusGame.sol` — it also hosts the VRF-callback dispatch, the `rngLocked()` view, `autoOpen`, `enqueueBoxForAutoOpen`, and the `lazyPassHorizon` view) plus the peripheral contracts the read-graph touches: the keeper (`AfKing.sol`), the BURNIE token whose shortfall paths mirror `rngLocked()` (`BurnieCoin.sol`), coinflip resolution (`BurnieCoinflip.sol`), jackpot helper state (`DegenerusJackpots.sol`), and the soulbound charity token (`GNRUS.sol`). **Re-attach `DegenerusGameStorage.sol` with this group** too.

**Group sum check:** 114297 (RNG-CORE, includes Storage) + 72472 (CONSUME-B) + 92989 (FACADE+PERIPHERAL-C) = **279758** = the TOTAL-with-Quests inventory row.

## The Storage-Travels Rule

`contracts/storage/DegenerusGameStorage.sol` (~23729 tokens) MUST re-attach to **every** chunked group. The Degenerus game executes through a delegatecall facade: the dispatcher in `DegenerusGame.sol` delegatecalls into the specialized module files, and they all share the one storage layout declared in `DegenerusGameStorage.sol`. A consequence the operator must respect when chunking: **the writer and the reader of a single storage slot frequently live in different module files.** The slot layout, the three write-time gates, and the terminal-freeze predicate all live in `DegenerusGameStorage.sol` — so it is the shared anchor every cross-module trace and every freeze claim must resolve against. If `DegenerusGameStorage.sol` is missing from a chunked group, the model cannot resolve that group's writers/readers against the slot declarations or the gates, and the read-graph is severed.

`DegenerusGameStorage.sol` already sits inside the RNG-CORE group. For the chunked path it must additionally travel with CONSUME-B and with FACADE+PERIPHERAL-C. The effective token cost of 3-group chunking is therefore the corpus plus two extra Storage copies:

> ~279758 (corpus) + 2 × ~23729 (Storage re-attached to CONSUME-B and FACADE+PERIPHERAL-C) ≈ **~327216 effective tokens** across the three-group feed.

The operator should expect this repetition — it is deliberate, not waste. (Equivalently, in the 18-file-core framing without Quests: ~257060 + 2 × ~23729 ≈ ~304518.) A single-feed large-context model pays the corpus once (~280K) and needs no Storage repetition; only the chunked path incurs the extra two copies.

## Operator Checklist

1. Attach files **by path** from the working tree — the kit references the contracts by path, it does not inline them.
2. One-feed model (whole corpus fits): attach all 19 files once; no Storage repetition needed.
3. Chunked path: feed **RNG-CORE → CONSUME-B → FACADE+PERIPHERAL-C**, re-attaching `DegenerusGameStorage.sol` with CONSUME-B and FACADE+PERIPHERAL-C.
4. If any `contracts/` commit lands after the frozen authoring HEAD, re-run `wc -l` / `wc -c` and refresh the inventory before feeding.
