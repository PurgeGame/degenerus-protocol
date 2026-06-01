---
phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code-
plan: 02
subsystem: game-resident-storage (ARCH-01 Step 2 of the single batched v55.0 fold diff — the STORAGE PRODUCER)
tags: [arch-01, afking-relocate, sub-stamp, d-348-07, freeze-02, solvency-01, layout-safe-append]
requires:
  - "349-01 applied (DegenerusGame.sol / DegenerusGameBingoModule.sol / IDegenerusGameModules.sol uncommitted in the working tree)"
  - "the v54 afkingFunding ledger present at DegenerusGameStorage.sol:410 (REUSED, not re-declared)"
provides:
  - "the relocated AfKing subscriber set (_subOf/_subscribers/_subscriberIndex) on the shared base as `internal` — in-context SLOADs for the GameAfkingModule (349-03/04) + the AdvanceModule STAGE (349-05)"
  - "the process-STAGE cursor (_subCursor) + the open-leg cursor (_subOpenCursor) + subsFullyProcessed (the FREEZE-02 no-interleave chunk gate, CONFIRMED-NEW — authored here)"
  - "the Sub record extended with the D-348-07 5-field box stamp (index/amount/day/scorePlus1/baseLevelPlus1) + the lastAutoBoughtDay/lastOpenedIndex markers, no adj"
  - "⚠ LAYOUT REVISED post-execution (orchestrator, USER-directed) — the SOURCE (contracts/storage/DegenerusGameStorage.sol) is authoritative; the 'Slot A/B/C' prose further down this SUMMARY is SUPERSEDED: (1) `amount` is now `uint96` (max ~79e9 ETH, never truncates) not uint256 → the WHOLE Sub is 2 slots (Slot 1 = config+scorePlus1+baseLevelPlus1 = 256b exact; Slot 2 = index+day+lastAutoBoughtDay+lastOpenedIndex+amount96 = 256b exact); (2) `_subCursor`/`_subOpenCursor` are `uint16` (not uint256) and pack with `subsFullyProcessed` into ONE slot → active subs CAPPED at 65,535 (the GameAfkingModule `subscribe` MUST revert at the cap, a 349-03 obligation). Net appended storage 6 slots → 3."
affects:
  - contracts/storage/DegenerusGameStorage.sol
tech-stack:
  added: []
  patterns:
    - "layout-safe append (never reorder) of the relocated subscriber set + cursors + the per-buy stamp into the shared delegatecall storage base"
    - "single-SSTORE stamp word: index(48)+day(32)+scorePlus1(16)+baseLevelPlus1(24)+lastAutoBoughtDay(32)+lastOpenedIndex(48) = 200 bits packed into one slot; amount in its own slot"
key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
decisions:
  - "Sub packing = 3 slots: Slot A config (dailyQuantity8+validThroughLevel32+reinvestPct8+flags8+fundingSource160 = 216b) + Slot B stamp/markers (200b, single SSTORE) + Slot C amount (full uint256). The doc's '2-slot' framing = the 2-slot EXTENSION (B+C) added on top of the original config slot (A); must_haves line 14 '40 bits into slot-2's spare, same single SSTORE, 2-slot-feasible' is satisfied (200 < 256)."
  - "lastAutoBoughtDay (already on the v54 Sub) RELOCATED within the struct to sit in the stamp/markers word so the 200-bit single-SSTORE word matches 348-INVARIANT-CARRY §3-ii verbatim (redeploy-fresh ⇒ in-struct reorder is a permitted layout decision)."
  - "amount given its own full uint256 slot (NOT packed with a purchaseLevel headroom field) — the doc allows either; full slot is the simplest 32-byte-fidelity carrier for the abi.encode(rngWord,player,day,amount) box seed, and the spend-only stamp has no second field to co-pack."
  - "open-leg cursor named _subOpenCursor (executor discretion per the plan); _subCursor is the process-STAGE cursor."
  - "Sub declared as a contract-level struct inside DegenerusGameStorage (not file-scope as in AfKing) — its natural home is the base that owns the layout; inheriting modules see it directly."
metrics:
  duration: ~9m
  completed: 2026-05-30
  tasks_completed: 2
  files_modified: 1
---

# Phase 349 Plan 02: STORAGE PRODUCER (relocate AfKing subscriber set + cursors + subsFullyProcessed + the D-348-07 5-field Sub stamp) Summary

**One-liner:** Appended (layout-safe, EOF, never a reorder) to `DegenerusGameStorage.sol` the relocated AfKing subscriber set (`_subOf`/`_subscribers`/`_subscriberIndex` as `internal`), the process-STAGE cursor `_subCursor` + the open-leg cursor `_subOpenCursor`, the CONFIRMED-NEW `subsFullyProcessed` FREEZE-02 no-interleave gate, and the relocated `Sub` struct carrying the D-348-07 5-field box stamp `(index, amount, day, scorePlus1, baseLevelPlus1)` + the `lastAutoBoughtDay`/`lastOpenedIndex` markers — no `adj`, single-SSTORE 200-bit stamp word, `validThroughLevel`/`fundingSource` preserved. The v54 `afkingFunding` ledger (`:410`) is reused with NO new aggregate; `claimablePool` (`:355`) + the invariant comment (`:348`) are byte-untouched. All edits uncommitted (contract-boundary hold).

---

## ⛔ Git posture — NOTHING COMMITTED (mandatory for this whole phase)

Per the v55.0 milestone discipline (the ONLY action needing approval is committing `contracts/*.sol`, and the orchestrator owns that gate), **NO git mutation ran** — no `git commit`, `git add`, `git rm`, `git stash`, `git reset`, `git checkout -- <file>`, or `git restore`. The single batched 349 contract diff is HELD for explicit USER approval at 349-05. Only read-only `git diff`/`git status`/`git log` + `grep`/read + the plan's `<verify>` greps were used. This SUMMARY is written with the Write tool and left **uncommitted**.

The `autonomous: false` checkpoint was run **hands-off** (per the project rule: only a `contracts/*.sol` commit needs approval) — both tasks executed straight through, no pause. There is **no `forge build`** in this plan; the authoritative build over the whole diff is 349-05.

---

## Re-pin attestation (inherited from 349-01, re-grepped against the post-349-01 tree)

349-01's SUMMARY flagged that its R1 edit shifted `DegenerusGame.sol` lines below `:1553` and that 349-02..05 must re-pin against the **post-349-01** tree, NOT the stale `20ca1f79` lines. **This plan touches only `DegenerusGameStorage.sol`, which 349-01 did NOT edit** — so the Storage anchors are still byte-identical to `20ca1f79`. Re-grepped (read-only) and CONFIRMED:

```
$ git diff --numstat 20ca1f79 -- contracts/storage/DegenerusGameStorage.sol   → EMPTY (Storage unchanged vs baseline before this plan)
```

| Anchor | Doc line | Live (pre-edit) | Matched text | Status |
|---|---|---|---|---|
| `afkingFunding` ledger (REUSE, do NOT re-declare) | :410 | **:410** | `mapping(address => uint256) internal afkingFunding;` | MATCH |
| invariant comment (names the afking component) | :348 | **:348** | `INVARIANT: claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` | MATCH |
| `claimablePool` decl (UNCHANGED) | :355 | **:355** | `uint128 internal claimablePool;` | MATCH |
| `TICKET_SCALE` (= 100; the cost-unit divisor base) | :166 | **:166** | `uint256 internal constant TICKET_SCALE = 100;` | MATCH |
| `subsFullyProcessed` repo-wide | — | **0 matches** | CONFIRMED-NEW (349 authors it) | MATCH |
| `afkingFundingPool` / any new aggregate repo-wide | — | **0 matches** | none exists; none introduced | MATCH |
| `_subCursor` / `lastOpenedIndex` repo-wide | — | **0 matches** | CONFIRMED-NEW | MATCH |
| the set to relocate (AfKing.sol) | :210/:214/:218 | **:210/:214/:218** | `_subOf`/`_subscribers`/`_subscriberIndex` (all `private`) | MATCH |

The append landed at EOF (before the final contract `}`), so every original anchor's line number is **unchanged** (re-confirmed post-edit: :166/:348/:355/:410 all identical). File grew 1826 → 1909 (+83, pure append).

---

## Task 1 — Append the subscriber set + cursors + subsFullyProcessed (DONE)

Appended `internal` (so every inheriting module — Game + all delegatecall modules — shares them in-context):

- `mapping(address => Sub) internal _subOf;` — per-subscriber record (the iterable set's value; carries the stamp).
- `address[] internal _subscribers;` — insertion-ordered iterable set (swap-pop tombstone on cancel — the H-CANCEL-SWAP-MISS membership class).
- `mapping(address => uint256) internal _subscriberIndex;` — 1-indexed membership ⟺ packed-index (0 = not in set); the swap-pop bookkeeping.
- `uint256 internal _subCursor;` — process-STAGE cursor (chunked drain of the set across `advanceGame` calls during the pre-RNG stamp pass).
- `uint256 internal _subOpenCursor;` — open-leg cursor (the OPEN_BATCH-style post-RNG box-open drain; its own router-category cursor — name at executor discretion per the plan).
- `bool internal subsFullyProcessed;` — the FREEZE-02 no-interleave chunk gate (CONFIRMED-NEW; authored here). Doc comment states its contract: while `false`, the mid-day lootbox RNG index-advance is blocked so a separate-tx request cannot land between the stamp pass and the index it bound; set `true` once the STAGE has drained the set this cycle.

The v54 `afkingFunding` mapping (`:410`) is PRESENT and REUSED — **NOT** re-declared (grep count = 1) and **NO** new aggregate (`afkingFundingPool` or any other) introduced (non-comment grep = 0). The systemwide afking total continues to ride inside `claimablePool` (`:355`, unchanged); the invariant comment (`:348`) still names the afking component. SOLVENCY-01's omittable-pool class stays structurally impossible.

### Verify (read-only)
- Plan `<verify>` (Task 1): emitted **`SET+CURSORS+GATE-APPENDED NO-AGGREGATE`** ✅
- Dupe check: each of `struct Sub` / `_subOf` / `_subscribers` / `_subscriberIndex` / `_subCursor` / `_subOpenCursor` / `subsFullyProcessed` declared exactly once; `afkingFunding` decl count = 1 (reused).

---

## Task 2 — Extend Sub with the D-348-07 5-field stamp + the two markers (DONE)

The relocated `Sub` struct (now on the storage base) carries — preserving the carried-over `validThroughLevel` (CONSENT-01 pass-gating) + `fundingSource` (CONSENT-01 funder), and the carried-over `dailyQuantity`/`reinvestPct`/`flags`:

| Field | Type | Role |
|---|---|---|
| `index` | `uint48` | stamp — pre-RNG lootbox `LR_INDEX` bound at process (FREEZE-02 frozen seed input) |
| `amount` | `uint256` (own slot) | stamp — spend in wei (boons off ⇒ amount == spend); full 32-byte fidelity for the `abi.encode(rngWord, player, day, amount)` box seed |
| `day` | `uint32` | stamp — boundary-pinned process day (FREEZE-03; mirrors the per-index `lootboxDay` of human boxes) |
| `scorePlus1` | `uint16` | stamp — FROZEN activityScore+1 (D-348-07; the EV-multiplier input at open) |
| `baseLevelPlus1` | `uint24` | stamp — FROZEN baseLevel+1 (D-348-07; the target-level roll floor at open) |
| `lastAutoBoughtDay` | `uint32` | success-marker (written only AFTER a successful `afkingFunding` debit) |
| `lastOpenedIndex` | `uint48` | monotonic no-double-open guard (open materializes only indices strictly past it) |

This is the **5-field shape** `(index, amount, day, scorePlus1, baseLevelPlus1)` per D-348-07 — score+baseLevel are stamped-frozen at process and read FROM the stamp at open, NOT live (the analog of the human deposit-time freeze of `scorePlus1`/`baseLevelPlus1` in `lootboxPurchasePacked`, `LB:529-530`). It SUPERSEDES the earlier 3-field `(index, amount, day)` framing. **NO `adj` field** is carried (the afking open passes the full stamped `amount` to `_applyEvMultiplierWithCap` and derives the cap-adjusted portion live) — the human precedent unpacks `(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)`; the afking stamp reuses the two widths but drops `adj`.

### Slot packing (the executor's layout decision — redeploy-fresh ⇒ storage break is fine)

Field declaration order produces this Solidity sequential packing:

- **Slot A (config, 216 bits):** `dailyQuantity`(8) + `validThroughLevel`(32) + `reinvestPct`(8) + `flags`(8) + `fundingSource`(160) = 216. (`index` 48 would overflow → new slot.)
- **Slot B (stamp + markers, 200 bits — SINGLE SSTORE):** `index`(48) + `day`(32) + `scorePlus1`(16) + `baseLevelPlus1`(24) + `lastAutoBoughtDay`(32) + `lastOpenedIndex`(48) = 200 < 256. The 40 D-348-07 bits (scorePlus1 16 + baseLevelPlus1 24) sit in this word's spare — same single SSTORE, no third stamp slot.
- **Slot C (spend):** `amount` — full `uint256`.

The doc's "2-slot Sub append / 2-slot-feasible" framing = the **2-slot EXTENSION** (Slot B + Slot C) added on top of the original config slot (Slot A). `must_haves` line 14 ("the 40 D-348-07 bits drop into the slot-2 word's spare bits — same single SSTORE, still 2-slot-feasible") is satisfied exactly: Slot B is the single-SSTORE stamp/markers word at 200 < 256 bits.

> **Layout note (recorded deviation-class decision, not a plan deviation):** `lastAutoBoughtDay` already existed on the v54 AfKing `Sub`; it was RELOCATED within the struct (declared adjacent to the other markers/stamp fields) so the 200-bit single-SSTORE word matches 348-INVARIANT-CARRY §3-ii verbatim. In-struct reordering is an explicit executor layout choice the SPEC permits (pre-launch redeploy-fresh, no migration). `amount` was given its own full slot rather than a packed `purchaseLevel`-headroom layout — the doc allows either; a spend-only stamp has no second field to co-pack, so a full slot is the simplest 32-byte-fidelity carrier.

### Verify (read-only)
- Plan `<verify>` (Task 2): emitted **`5-FIELD-STAMP NO-ADJ`** ✅
- The `awk` struct slice captured the complete, well-formed struct (11 fields, closing `}` reached); `uint16 scorePlus1`, `uint24 baseLevelPlus1`, `uint48 index`, `uint48 lastOpenedIndex`, `uint32 lastAutoBoughtDay` all present; no `uint64 adj` in the struct.
- The only `adj` matches in the file are the pre-existing `_packLootboxPurchase`/`_unpackLootboxPurchase` human-deposit helpers (`:1360-1417`, untouched — the very precedent the docs cite) + my own explanatory doc comment (`:1850`); none is a Sub field.

---

## Deviations from Plan

**None affecting behavior or scope.** The two tasks were executed exactly as written. The two layout choices (relocating the pre-existing `lastAutoBoughtDay` within the struct to land it in the single-SSTORE stamp word; `amount` in its own slot) are explicit executor layout decisions the SPEC delegates ("the exact packing is a 349 layout decision") — recorded above for traceability, not Rule-1/2/3 auto-fixes. No bug, no missing critical functionality, no blocking issue, no architectural change. `autonomous: false` checkpoint run hands-off per the project rule (no `contracts/*.sol` commit was made).

### Authentication gates
None.

---

## Known Stubs
None. This plan is pure storage layout (state declarations + struct definition). No data sources, no UI, no placeholder values. `subsFullyProcessed`/`_subCursor`/`_subOpenCursor` default to `false`/`0` — those are the correct initial values (not stubs): the gate starts open-blocking-false and the cursors start at the head of the set; the GameAfkingModule (349-03/04) and the AdvanceModule STAGE (349-05) read/write them.

---

## Threat Flags
None new. The append stays within the plan's threat register:
- **T-349-02-AGG** (stray aggregate / solvency): mitigated — `afkingFunding` reused (`:410`), NO new aggregate (non-comment grep = 0); the afking total rides inside `claimablePool` (`:355`, unchanged). The omittable-pool class stays structurally impossible (SOLVENCY-01).
- **T-349-02-FRZ** (stamp shape): mitigated — the 5-field D-348-07 shape (`scorePlus1`+`baseLevelPlus1` present); the open reads them FROM the stamp, not live (FREEZE-01 holds for those fields). NOT the superseded 3-field shape.
- **T-349-02-LAYOUT** (slot collision): mitigated — append-only (never a reorder); EOF insertion left all prior slots/lines untouched; the 2-slot extension is sized (200-bit stamp word < 256) so markers + stamp share one SSTORE.
- **T-349-02-SC** (package installs): N/A — Solidity edits only, no package-manager installs.

---

## Self-Check: PASSED

- `contracts/storage/DegenerusGameStorage.sol` — exists; `struct Sub` present (1) with the 5-field stamp + 2 markers + preserved `validThroughLevel`/`fundingSource`, no `adj`; `_subOf`/`_subscribers`/`_subscriberIndex` `internal` (1 each); `_subCursor`/`_subOpenCursor`/`subsFullyProcessed` present (1 each); `afkingFunding` reused (1 decl, not re-declared); `claimablePool`/invariant comment byte-untouched (:355/:348). ✅
- Both plan `<verify>` commands emitted their success sentinels (`SET+CURSORS+GATE-APPENDED NO-AGGREGATE` / `5-FIELD-STAMP NO-ADJ`). ✅
- `.planning/phases/349-…/349-02-SUMMARY.md` — this file (written, uncommitted). ✅
- **No commit hashes** — by design (contract-boundary hold; the orchestrator owns the single batched-diff commit gate after the USER approval at 349-05). `git status` shows the Wave-1 three (`DegenerusGame.sol`, `IDegenerusGameModules.sol`, `DegenerusGameBingoModule.sol`) + this plan's `DegenerusGameStorage.sol` as uncommitted working-tree changes — the single batched diff accumulating for 349-03. ✅
- AfKing.sol untouched (`git diff --numstat -- contracts/AfKing.sol` EMPTY) — the relocated set is now the canonical game-resident copy; the AfKing-side de-duplication is a later wave, not 349-02. ✅
- STATE.md / ROADMAP.md NOT touched by this executor (orchestrator-owned). ✅
