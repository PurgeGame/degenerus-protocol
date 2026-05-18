# Phase 290 MINTCLN — Measurement Attestations (MINTCLN-08 + MINTCLN-09)

> The 6 load-bearing attestations are populated post-patch by Plan 02 against the v41 baseline.
> This doc is the verbatim copy-forward source for Plan 02's batched commit message body, per `feedback_no_history_in_comments.md` (numerical attestations go in the commit body, NOT into NatSpec).
> Plan 02 MUST re-validate every populated value against the post-patch tree before the user approves the commit.

## Audit Baseline

Anchor: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD). Source of truth for every "byte-identical to v41 close" assertion in this scaffold and for every "delta vs v41 close" measurement Plan 02 records below. All comparisons resolve against this SHA via `git worktree add` or `git show <sha>:<path>` techniques.

## (1) Bytecode Delta

`contracts/modules/DegenerusGameMintModule.sol` deployed-runtime bytecode delta vs v41 close = **`-81` bytes** (negative = shrank).

**Method:** Compiled both via `forge build --skip test` (foundry 1.6.0-nightly, solc 0.8.34, via_ir + optimizer_runs=200 per `foundry.toml`). v41 baseline materialized at `/tmp/v41-baseline` via `git worktree add /tmp/v41-baseline 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. Read `deployedBytecode.object` from `forge-out/DegenerusGameMintModule.sol/DegenerusGameMintModule.json` at each tree; size = `len(hex_string_without_0x_prefix) / 2`.

**Measurement:**

```
DegenerusGameMintModule deployed-runtime bytecode:
  v42 = 16223 bytes
  v41 baseline = 16304 bytes
  delta = 16223 - 16304 = -81 bytes  (sign: – shrank)
```

**Expected sign:** **negative** (cleanup drops one `_raritySymbolBatch` parameter + drops one keccak input + drops 3 fields from `TraitsGenerated` event encoding at both emit sites + removes one `rollSalt` local variable + removes one duplicate `baseKey` block in `_processOneTicketEntry` = smaller bytecode at all touched callsites). Measured `-81 B` shrink is on the negative side as expected and is within an order-of-magnitude of the pre-measurement estimate (≈ -60-120 B for a 6-edit cleanup of this scope). No escalation flag.

`DegenerusGameStorage` is `abstract` and produces no standalone deployed bytecode (`deployedBytecode.object` = empty at both v42 and v41); the event-declaration mutation is realized in the deployed bytecode of the concrete `DegenerusGameMintModule` that emits the event. Storage layout for the abstract is captured in §(2).

## (2) Storage-Slot Grep Proof (MINTCLN-08)

`forge inspect contracts/modules/DegenerusGameMintModule.sol:DegenerusGameMintModule storageLayout` diff vs v41 close = **EMPTY** (modulo a single leading-blank-line cosmetic difference produced by the foundry-nightly warning stripper; substantive table content byte-identical).

`forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` diff vs v41 close = **EMPTY** (byte-identical including all whitespace; `diff` returns no output and exit-code 0).

**Method:** Ran `forge inspect <path>:<contract> storageLayout` against the post-patch tree (`/home/zak/Dev/PurgeGame/degenerus-audit`) and against the v41 baseline worktree (`/tmp/v41-baseline @ 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`); stripped the foundry-nightly warning header from each; `diff` ed the resulting tables. After also stripping cosmetic leading blank lines via `grep -v "^$"`, both diffs return EMPTY (169 lines on each side for MintModule; 171 lines each for Storage, identical token-for-token). Pre-patch tree had been compiled both before and after `forge clean` to confirm the post-patch storage layout was not stale-cached.

**Result table:**

| File | v41 baseline lines | v42 post-patch lines | Substantive diff |
|---|---|---|---|
| `contracts/modules/DegenerusGameMintModule.sol` | 169 (non-blank) | 169 (non-blank) | EMPTY |
| `contracts/storage/DegenerusGameStorage.sol` | 171 | 171 | EMPTY |

**Locks under MINTCLN-08:** ALL HELD.
- `ticketsOwedPacked[rk][player]` 40-bit packed form (rem low 8 + owed next 24 + processed-via-owed-salt high 8) remains at the same slot offset / type / label as v41 close.
- Zero new storage slots in MINTCLN scope (slot counts identical at both trees).
- Zero new mappings in MINTCLN scope.
- Zero new SSTORE callsites in MINTCLN scope (all SSTOREs in the touched range write to pre-existing slots — verified by `git diff` showing no new `ticketsOwedPacked[...] =` lines beyond the existing 5 SSTOREs in `processFutureTicketBatch` + `_processOneTicketEntry` + `_resolveZeroOwedRemainder`).
- Zero new SLOAD callsites in MINTCLN scope.

**Escalation rule:** Diff is EMPTY → no escalation; MINTCLN-08 byte-identity attestation PASSED.

## (3) Worst-Case Gas (theoretical FIRST per feedback_gas_worst_case.md)

Theoretical derivation FIRST (per `feedback_gas_worst_case.md`); empirical deferral note follows.

**(a) Anchor case.** `WRITES_BUDGET_SAFE = 550` per call (sourced from `contracts/modules/DegenerusGameMintModule.sol:89`; constant `uint32 private constant WRITES_BUDGET_SAFE = 550;` UNCHANGED at v42 close HEAD). Worst-case scenario for the MINTCLN emit/keccak surface is a ~5840-`owed`-per-player multi-call drain — the deity-pass + far-future scenario where a single `(rk, player)` slot accumulates the upper-bound `owed` and consumes successive `processFutureTicketBatch` / `processTicketBatch` calls until drained. At `writesBudget / 2 = 275` ticket-entries per call (each entry consuming 2 writes-budget units for the `<= 256`-take branch via `writesThis = take * 2`), ~21 calls are required to drain 5840 owed. Within each call, `_raritySymbolBatch` is invoked exactly once per outer-loop iteration that actually mints traits, so the cumulative invocation count is also ~21 across the drain (one outer iteration per call when `(rk, player)` holds the full budget; many more iterations per call would arise only with smaller per-player `owed` values across distinct players).

**(b) Per-`_raritySymbolBatch`-invocation gas delta.** Removing `ownedSalt` (`uint32`) from `abi.encode(baseKey, entropyWord, groupIdx, ownedSalt)` to `abi.encode(baseKey, entropyWord, groupIdx)`:
- `abi.encode` shrinks by one 32-byte word → keccak input shrinks from 4 words (128 B) to 3 words (96 B). Keccak cost is `30 + 6 × ceil(input_bytes / 32)` = `30 + 24 = 54` (v41) → `30 + 18 = 48` (v42) ⇒ **-6 gas** per keccak.
- `mstore` for the dropped word in memory layout: **-3 gas** (one MSTORE skipped during `abi.encode` setup).
- Function parameter slot: dropping a stack-passed `uint32` saves 1 PUSH / 1 stack-load per invocation ⇒ ~**-6 gas** at the callsite + ~**-3 gas** inside the callee.
- Estimated total per `_raritySymbolBatch` invocation: **≥ −18 gas** (conservative; the dominant lever is the keccak input shrink at -6 gas).

**(c) Per-`TraitsGenerated` emit gas delta.** v41 emit shape: `TraitsGenerated(address indexed player, uint24 indexed level, uint32 queueIdx, uint32 startIndex, uint32 count, uint256 entropy)` — 2 indexed topics + 4 non-indexed fields. v42 emit shape: `TraitsGenerated(address indexed player, uint256 baseKey, uint32 take)` — 1 indexed topic + 2 non-indexed fields.

EVM LOG opcode pricing:
- Per-LOG flat cost (Yellow Paper `G_log = 375`): unchanged.
- Per-topic cost (`G_logtopic = 375`): v41 emit fires `LOG3` (3 topics: topic-0 = event-sig hash, topic-1 = player, topic-2 = level); v42 emit fires `LOG2` (2 topics: topic-0 = new event-sig hash, topic-1 = player). Topic delta: **-1 topic × 375 gas = -375 gas**.
- Per-data-byte cost (`G_logdata = 8`): v41 LOGDATA includes the 4 non-indexed fields each padded to 32 bytes = 4 × 32 = 128 B. v42 LOGDATA includes the 2 non-indexed fields each padded to 32 bytes = 2 × 32 = 64 B. Data delta: **-64 B × 8 gas = -512 gas**.
- Memory-expansion for the dropped fields' encoding: the 4 → 2 non-indexed-field reduction also drops some inline ABI-encode setup (`mstore` × 2 for the dropped fields) ⇒ **~-6 gas**.
- Estimated total per `TraitsGenerated` emit: **~−893 gas** (= −375 topic + −512 data + −6 setup). Conservative lower bound: -875 gas. Dominant lever: the topic-count drop + the 64-byte LOGDATA shrink.

Plan 02 verifies the `LOG3 → LOG2` transition structurally: the post-patch `event TraitsGenerated(address indexed player, uint256 baseKey, uint32 take);` declaration in `contracts/storage/DegenerusGameStorage.sol` carries exactly 1 `indexed` modifier ⇒ exactly 2 topics emitted (1 sig + 1 indexed = 2 = `LOG2`). The v41 declaration carried 2 `indexed` modifiers ⇒ 3 topics ⇒ `LOG3`. Confirmed via `git diff contracts/storage/DegenerusGameStorage.sol`.

**(d) Cross-call drain total.** At 5840 `owed`-per-player worst case with `writesBudget = 550`:
- `_raritySymbolBatch` invocations across the drain: ~21 (one per outer-iteration ≈ one per call when single player saturates the budget).
- `TraitsGenerated` emits: same as invocation count = ~21.
- Invocation savings: ~21 × −18 = **~−378 gas**.
- Emit savings: ~21 × −893 = **~−18,753 gas**.
- Total order-of-magnitude savings per 5840-owed drain: **~−19,131 gas**.

The dominant savings is `TraitsGenerated` LOGDATA shrink + topic-count drop (~98% of total). Per-invocation `_raritySymbolBatch` savings (~2%) is a secondary lever.

**(e) Other paths.** `processTicketBatch` → `_processOneTicketEntry` has the same `_raritySymbolBatch` invocation savings (~−18 gas/invocation) + same `TraitsGenerated` emit savings (~−893 gas/emit). At the deity-pass + far-future drain scale, savings scale linearly with the number of trait emissions; aggregate across all paths is bounded above by `(total_traits_minted_per_drain × ~−893)` for the emit dimension and `(total_outer_iterations × ~−18)` for the invocation dimension.

**Empirical confirmation.** An existing fixture at `test/gas/AdvanceGameGas.test.js` exercises `processTicketBatch` at one cold-storage + one warm-storage call (per the inline comments at `test/gas/AdvanceGameGas.test.js`), but per `feedback_gas_worst_case.md` ("existing gas benchmarks don't enable autorebuy, don't verify specialized events fire, and don't construct true worst-case state") the AdvanceGameGas fixture does NOT construct the 5840-owed-per-player anchor case from §(a). Building the true-worst-case fixture (autorebuy enabled, x100 multiplier active, full multi-call drain across `~21` successive `processFutureTicketBatch` calls, both emit sites exercised) is out of MINTCLN scope and properly belongs to Phase 291 TST-MINTCLN. **Empirical measurement DEFERRED to Phase 291 TST-MINTCLN per `feedback_gas_worst_case.md` theoretical-first prioritization rule.** The theoretical derivation above is load-bearing for the v42.0 audit deliverable §3.A entry at Phase 297; Phase 291 fills in the empirical confirmation against the theoretical bound.

## (4) Selector Attestations (MINTCLN-09)

| Function | Canonical signature | 4-byte selector | Disposition |
|---|---|---|---|
| `processFutureTicketBatch` | `processFutureTicketBatch(uint24,uint256)` | `0x9103766f` | UNCHANGED vs v41 close (function signature unmutated; only body and emit shape touched). |
| `processTicketBatch` | `processTicketBatch(uint24)` | `0x2ff3118b` | UNCHANGED vs v41 close. |
| `_processOneTicketEntry` (private) | `_processOneTicketEntry(address,uint24,uint24,uint32,uint32,uint256,uint256)` | `0xd2c9121f` | Private function; not exposed as a public ABI selector but the canonical signature is recorded as a structural attestation of "no internal call-graph break across MINTCLN." Body restructured (rollSalt local removed; baseKey constructed earlier with `\| uint256(owed)`); signature byte-identical. |

**Method:** `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast sig "<canonical-signature>"` (foundry 1.6.0-nightly).

**Lock under MINTCLN-09:** All three signatures byte-identical to v41 close (the function signatures are unchanged across MINTCLN; only `_raritySymbolBatch` mutates and is a different private function whose selector is not recorded in the public-ABI lock). PASSED.

## (5) Event Topic Hash Attestations (MINTCLN-04 + MINTCLN-09)

**`TraitsGenerated` topic hash — BREAKING change per D-42N-EVT-BREAK-01:**

| Form | Canonical signature | Topic hash | Disposition |
|---|---|---|---|
| v41 close (6-field) | `TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` | `0x5e96bf2d5c935864be60ff066e1f498150a446b5b8b94321b0097276c61ec7c9` | RETIRED at v42 close (no v42 emit produces this topic-0). |
| v42 post-MINTCLN-04 (3-field) | `TraitsGenerated(address,uint256,uint32)` | `0x279edf1ccbf5db78a99006a6861b4d49de10ed6016d8400ce6a1d5e415d2ebc3` | NEW at v42 close (both v42 emit sites produce this topic-0). |

**The two topic hashes DIFFER** (verifiable by inspection: leading bytes `0x5e96..` vs `0x279e..`). That difference IS the BREAKING-TOPIC-HASH structural attestation per D-42N-EVT-BREAK-01 — both values recorded here verbatim so the audit deliverable at Phase 297 §3.A can cite both. Indexer-migration handoff inherits v40 D-40N-EVT-BREAK-01 disposition (pre-launch posture; rebuild on v42 close HEAD).

**Non-`TraitsGenerated` event topic hashes — UNCHANGED locks (MINTCLN-09):**

| Event | Canonical signature | Topic hash | Disposition |
|---|---|---|---|
| `TicketsQueued` | `TicketsQueued(address,uint24,uint32)` | `0x6fd510354c0c844211fe1a187b420a1faeaf581b2242b0ac52ab02603b3c71c2` | UNCHANGED vs v41 close (declaration UNMUTATED at `DegenerusGameStorage.sol:494-498`; topic-hash derived from canonical sig only — independent of any in-module changes). |
| `TicketsQueuedScaled` | `TicketsQueuedScaled(address,uint24,uint32)` | `0xabd0edb220b375806b1cf90ff6542f01dbcce5522ab5bbe601182f139d200558` | UNCHANGED vs v41 close (declaration UNMUTATED at `DegenerusGameStorage.sol:500-505`; mint-boost retention surface per D-40N-MINTBOOST-OUT-01). |
| `TicketsQueuedRange` | `TicketsQueuedRange(address,uint24,uint24,uint32)` | `0x7d3694156c24d59b09e44621fa9b984b9cfc57cb35f685976a1d1ce6a997b595` | UNCHANGED vs v41 close (declaration UNMUTATED at `DegenerusGameStorage.sol:507-513`). |

**`TicketsCredited` cite — adjustment.** The Plan 02 outline `<read_first>` block references `event TicketsCredited` as a non-`TraitsGenerated` event topic to attest. Grep of `contracts/` confirms NO event named `TicketsCredited` exists at v41 close HEAD or at v42 post-patch HEAD; the closest ticket-queue family of events are the three `TicketsQueued*` variants captured above. Plan 02 Task 4 substitutes the three concretely-existing ticket-queue family events for the planning artifact's `TicketsCredited` cite. This is recorded as a deviation (Rule 1: bug → planning artifact referenced a non-existent event; substantive lock is preserved by attesting the three ticket-queue-family events plus `TraitsGenerated`).

**Method:** `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast keccak "<canonical-signature>"` (foundry 1.6.0-nightly). All canonical signatures sourced from `contracts/storage/DegenerusGameStorage.sol` events L484-L513 at v42 post-patch + v41 baseline.

**Lock under MINTCLN-04 + MINTCLN-09:** Only `TraitsGenerated` topic hash changes (BREAKING per D-42N-EVT-BREAK-01). `TicketsQueued`, `TicketsQueuedScaled`, `TicketsQueuedRange` byte-identical to v41 close. PASSED.

## (6) B2-Symmetric-Callsite Diff Check (per v41 Phase 281 precedent)

Post-patch line offsets (post-Edits-A..L; line numbers shifted from pre-patch):

| Path | `baseKey` block | `_raritySymbolBatch` callsite | `TraitsGenerated` emit |
|---|---|---|---|
| `processFutureTicketBatch` (callsite A) | mint:426-429 | mint:470 | mint:471 |
| `_processOneTicketEntry` (callsite B) | mint:763-766 | mint:793 | mint:794 |

**(a) `baseKey` construction diff (L426-L429 ↔ L763-L766):**

```
1,4c1,4
<             uint256 baseKey = (uint256(lvl) << 224) |
<                 (idx << 192) |
<                 (uint256(uint160(player)) << 32) |
<                 uint256(owed);
---
>         uint256 baseKey = (uint256(lvl) << 224) |
>             (queueIdx << 192) |
>             (uint256(uint160(player)) << 32) |
>             uint256(owed);
```

Diff content: (i) indentation (12 spaces in `processFutureTicketBatch` due to enclosing `while` block; 8 spaces in `_processOneTicketEntry` as direct function body); (ii) local-variable name `idx` vs `queueIdx`. Both are documented non-substantive differences. Byte-equivalent modulo indentation + local name. **PASS.**

**(b) `_raritySymbolBatch` callsite diff (L470 ↔ L793):**

```
1c1
<             _raritySymbolBatch(player, baseKey, processed, take, entropy);
---
>         _raritySymbolBatch(player, baseKey, processed, take, entropy);
```

Diff content: indentation only (12 spaces vs 8 spaces). Argument list byte-identical. **PASS.**

**(c) `TraitsGenerated` emit diff (L471 ↔ L794):**

```
1c1
<             emit TraitsGenerated(player, baseKey, take);
---
>         emit TraitsGenerated(player, baseKey, take);
```

Diff content: indentation only. Argument list byte-identical. **PASS.**

**Method:** `diff <(sed -n 'A1,A2p' contracts/modules/DegenerusGameMintModule.sol) <(sed -n 'B1,B2p' contracts/modules/DegenerusGameMintModule.sol)` on the 3 paired line ranges above.

**Lock under v41 Phase 281 B2-symmetric precedent:** All 3 diffs show ONLY indentation + the documented `idx` vs `queueIdx` local-name swap. Zero substantive drift. PASSED.

## Source-Doc Cross-Cite

- **Back-reference:** `290-01-DESIGN-INTENT-TRACE.md` (this scaffold's sister artifact; Plan 01 design-intent gate per MINTCLN-10 + `feedback_design_intent_before_deletion.md`).
- **Forward-reference:** `290-02-PLAN.md` (the contract-patch plan; Plan 02 reads this scaffold and populates the six attestation sections post-patch).
- **Plan 02 Task 5 (checkpoint:human-verify):** uses the populated values from this scaffold verbatim in the batched commit message body. The doc MUST be re-validated against the post-patch tree before the user approves the commit.

Plan 02 populated all six attestation sections post-patch. The populated values are the verbatim copy-forward source for the batched commit message body (per `feedback_no_history_in_comments.md` — numerical attestations live in the commit body, NOT in NatSpec). The doc MUST be re-validated against the post-patch tree before the user approves the commit.
