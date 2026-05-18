---
phase: 298-vrf-read-graph-catalog-catalog
plan: 07
subsystem: vrf-read-graph-catalog
tags: [audit-only, rng-lock, manual-lootbox, lootbox-module, freshness-violation, F-41-02-class, multi-tx-window]
requires: []
provides:
  - "§7 catalog entry for LootboxModule._resolveLootboxCommon / _resolveLootboxRoll (manual lootbox-roll consumer cluster)"
  - "35 VIOLATION rows across 25 participating slots and ~80 writer-callsite tuples consolidated into 56 (slot × writer × callsite) verdict rows"
affects: []
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-07-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-07-SUMMARY.md
  modified: []
decisions:
  - "Consumer cluster: both _resolveLootboxCommon (:960) and _resolveLootboxRoll (:1623) traced together since they are the same RNG-consumption code path for the manual EOA shells openLootBox + openBurnieLootBox"
  - "Per D-298-EXEMPT-REACH-01 per-callsite: _resolveLootboxCommon is shared across 4 dispatchers (manual openLootBox/openBurnieLootBox + auto resolveLootboxDirect/resolveRedemptionLootbox); §7 scope is the manual-path classification only — auto-resolve rows are §6 scope"
  - "Self-stack writes inside the consumer's resolution (D-1, D-15, D-18, D-23, D-28, D-29, D-33, D-41, D-42) classified VIOLATION audit-conservatively despite intra-tx-only mutation timing; Phase 299 may downgrade per design-intent trace"
  - "35 VIOLATION rows partition across remediation clusters: (a) rngLockedFlag-gated revert (×14), (b) snapshot/anchor at allocation (×16), (c) pre-lock reorder of self-stack boon side-effects (×3); zero (d) immutable recommendations because every participating slot is legitimately mutable across the game lifecycle"
  - "Cross-contract participating SLOADs (dgnrs.poolBalance, affiliate.affiliateBonusPointsBest, questView.playerQuestStates) enumerated per D-298-TRACE-DEPTH-01 all-source scope"
metrics:
  duration_minutes: 24
  tasks: 1
  files_created: 2
  source_mutations: 0
  test_mutations: 0
completed: 2026-05-18
---

# Phase 298 Plan 07: VRF Read-Graph Catalog — LootboxModule._resolveLootboxCommon / _resolveLootboxRoll Summary

VRF-derived-entropy backward-trace from the manual-path lootbox-roll consumer cluster (`_resolveLootboxCommon` at `:960` and `_resolveLootboxRoll` at `:1623`, reached via the `openLootBox` and `openBurnieLootBox` external shells) enumerated 29 reachable SLOADs / 25 participating / ~80 writer-callsites consolidated into 56 (slot × writer × callsite) verdict tuples, of which **35 are VIOLATION** because participating slots are mutated by EOA-reachable paths during the open commitment window between VRF callback (`lootboxRngWordByIndex[index]` SSTORE) and the player-discretion `openLootBox` invocation.

## Outputs

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-07-CATALOG-section.md` — §A traced-fn set (42 fns) + §B SLOAD table (29 rows) + §C writer enumeration (23 slot groups) + §D verdict matrix (56 rows) + §E remediation matrix (35 VIOLATION rows; tactics across clusters a/b/c).

## Trace Result

- **Consumer cluster:** `LootboxModule._resolveLootboxCommon` (`:960`) and `LootboxModule._resolveLootboxRoll` (`:1623`); both `private` helpers reached via four `external` dispatchers, two of which are the manual EOA path in §7 scope: `openLootBox` (`:526`) and `openBurnieLootBox` (`:607`).
- **Top-level call chain (manual path):**
  - TX A: `DegenerusGame.buyTickets` (or BURNIE-coin callback for BURNIE-priced lootboxes / `buyWhaleBundle` for whale-allocated ETH lootboxes) writes the per-index commitment quad — `lootboxEth[index][player]`, `lootboxDay[index][player]`, `lootboxBaseLevelPacked[index][player]`, `lootboxEvScorePacked[index][player]`, `lootboxDistressEth[index][player]` — and reserves an RNG index.
  - TX B: `AdvanceModule.rawFulfillRandomWords` (Chainlink VRF callback) writes `lootboxRngWordByIndex[index] = rngWord` either directly (mid-day branch) or via `_finalizeLootboxRng` on the daily-advance branch. From this SSTORE forward, the per-index seed is final and publicly readable.
  - TX C: Player-discretion `DegenerusGame.openLootBox(player, index)` → `LootboxModule.openLootBox:526` → derives `seed = keccak256(rngWord, player, day, amount)` at `:554` → calls `_resolveLootboxCommon:583` → `_accumulateLootboxRolls:1004` → `_resolveLootboxRoll` (one or two invocations; second uses `EntropyLib.hash2(seed, 1)`).
- **Critical commitment-window property:** the manual path opens TX C at the player's discretion AFTER TX B publishes the RNG word. The `seed` recipe binds only `(rngWord, player, day, amount)` — but every OTHER SLOAD reached during resolution (player activity score, EV-cap accumulator, level, dgnrs pool balance, decimator window, boon storage, deity-pass count, presale state, …) is sampled at TX C time, NOT at TX A purchase time. That is the structural source of the VIOLATION population.
- **Reachable SLOAD count:** 29 enumerated in §B (in-contract storage + 3 cross-contract: `dgnrs.poolBalance`, `affiliate.affiliateBonusPointsBest`, `questView.playerQuestStates`).
- **Participating SLOAD count:** 25 (per §B `Participating? = YES`).
- **Non-participating attestations (4):** `lootboxEthBase` (dead read after `:546`); `dailyIdx` (only reached on whale-pass boon branch post-roll); `ticketsOwedPacked[wk][buyer]` and `ticketQueue[wk].length` (output-accounting accumulators inside `_queueTickets`, both post-roll-commit).

## Writer Enumeration

23 §C slot groups covering 25 participating slots (B-10/B-11 share `mintPacked_` writer set; B-18/B-19 share `boonPacked` writer set). Writer enumeration grep-verified via `grep -rn "<slot>\s*=\|<slot>\.push\|<slot>\[.*\]\s*=" contracts/ --include="*.sol"` for each participating slot. Key writer-population highlights:

- **`lootboxRngWordByIndex`** (B-2 → C-2): 3 writer callsites — all on `advanceGame()` / VRF coordinator stacks. ZERO non-EXEMPT writers.
- **`level`** (B-6 → C-5), **`rngLockedFlag`** (B-25 → C-21), **`decWindowOpen`** (B-16 → C-13), **`gameOverPossible`** (B-7 → C-6), **`lastPurchaseDay`** (B-21 → C-17), **`jackpotPhaseFlag`** (B-22 → C-18), **`purchaseStartDay`** (B-23 → C-19): all written exclusively from `advanceGame()` or constructor. ZERO non-EXEMPT writers.
- **`rngRequestTime`** (B-24 → C-20): 8 writer callsites — 6 EXEMPT-ADVANCEGAME, 1 EXEMPT-VRFCALLBACK, 1 EXEMPT-RETRYLOOTBOXRNG (per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A locking `retryLootboxRng` as one of the 3 explicit EXEMPT entry points).
- **`lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxDistressEth`, `lootboxBurnie`** (per-index purchase-time mappings): each has multiple writers from EOA mint / whale flows (`MintModule._allocateLootbox`, `MintModule._burnieAllocate`, `WhaleModule._whaleLootboxAllocate`). Self-stack zero-out writes inside `openLootBox` / `openBurnieLootBox` are own-callsite — classified VIOLATION audit-conservatively.
- **`presaleStatePacked`** (B-4 → C-4): two writers — MintModule cap-eval (VIOLATION reach) + AdvanceModule phase transition (EXEMPT).
- **`mintPacked_`** (B-10/B-11 → C-9): nine writer groups across MintStreakUtils, MintModule, BoonModule, WhaleModule, AdvanceModule, constructor, and Storage `_applyWhalePassStats`. Player can mutate his own score via mint / whale-bundle / deity-pass purchase / quest completion / affiliate recording during the open window.
- **`lootboxEvBenefitUsedByLevel`** (B-13 → C-11): single writer `_applyEvMultiplierWithCap:511`, reached from each lootbox-resolution dispatcher. CROSS-RESOLUTION accumulator — successive `openLootBox` calls at the same level mutate it for the next call (D-32).
- **`boonPacked`** (B-18/B-19 → C-15): writers across LootboxModule._applyBoon, WhaleModule, MintModule, BoonModule.checkAndClearExpiredBoon / consumeActivityBoon, plus the `issueDeityBoon` cross-EOA path (deity-pass holder writes another player's `boonPacked[player]`).
- **`deityPassOwners`** (B-17 → C-14): single writer `WhaleModule._buyDeityPass:596` (`push`); monotonically growing.
- **`dgnrs.poolBalance(Lootbox)`** cross-contract (B-20 → C-16): multi-writer surface; EOA-reachable mutations possible via sDGNRS `transferIn` / admin / cross-lootbox-resolution drains.
- **`affiliate.affiliateBonusPointsBest`** cross-contract (B-28 → C-22) and **`questView.playerQuestStates`** cross-contract (B-29 → C-23): both EOA-mutable during the open window via mint flows / quest claims.

## Verdict

56 (slot × writer × callsite) tuples → **35 VIOLATION**, 21 EXEMPT (18 EXEMPT-ADVANCEGAME + 2 EXEMPT-VRFCALLBACK + 1 EXEMPT-RETRYLOOTBOXRNG).

VIOLATION partitioning by participating-slot family:

| Slot family | VIOLATION row count | Reason |
| --- | --- | --- |
| `lootboxEth` / `lootboxDay` / `lootboxBaseLevelPacked` / `lootboxEvScorePacked` / `lootboxDistressEth` / `lootboxBurnie` (per-index purchase-time mappings) | 17 (D-1, D-2, D-3, D-7, D-8, D-9, D-15, D-16, D-17, D-18, D-19, D-20, D-29, D-30, D-31, D-33, D-34) | EOA-allocated at TX A but mutated by other EOA-reachable allocation calls between TX B (VRF callback) and TX C (open); also self-zeroed inside the consumer post-amount-capture |
| `presaleStatePacked` | 1 (D-10) | MintModule cumulative-cap evaluation runs per-EOA-mint inside the open window |
| `mintPacked_` (activity score input) | 6 (D-21, D-22, D-23, D-24, D-25, D-28) | mintCount / streak / whale-bundle / affiliate / deity-pass / activity-boon all EOA-writable in window |
| `lootboxEvBenefitUsedByLevel` (cross-resolution accumulator) | 1 (D-32) | sequence-of-opens at same level shifts the cap remaining for the next open |
| `deityPassOwners` (boon-roll space) | 1 (D-37) | `buyDeityPass` push during the window shifts `deityEligible` flag + boon-roll weight set |
| `boonPacked` (boon-roll & boon-consume state) | 6 (D-38, D-39, D-40, D-41, D-42, D-43) | LootboxModule._applyBoon + WhaleModule + MintModule + BoonModule externals + self-stack expiry-clear + activity-consume + other-externals — all reachable in window |
| `dgnrs.poolBalance(Lootbox)` (DGNRS reward magnitude) | 1 (D-44) | cross-resolution / admin / cross-contract pool mutation shifts B-20 between opens |
| `affiliate.affiliateBonusPointsBest` (score input) | 1 (D-55) | EOA-mintable affiliate-points record |
| `questView.playerQuestStates` (score input) | 1 (D-56) | EOA-completable quest claim shifts streak |
| **TOTAL VIOLATION** | **35** | |

## Remediation Recommendation

35 VIOLATION rows × ONE tactic each from `{(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable}` + ≤80-char rationale (D-298-RECOMMEND-DEPTH-01). Cluster shape:

| Cluster | Count | Pattern precedent | Description |
| --- | --- | --- | --- |
| (a) rngLockedFlag-gated revert | 14 | Phase 290 MINTCLN `MintModule.sol:1221` | Block any mutator of a participating slot once per-index `lootboxRngWordByIndex[index] != 0` (or for global slots, once any open-window lootbox index exists with RNG fulfilled). Direct, minimal, no new storage. |
| (b) snapshot/anchor at allocation | 16 | Phase 281 owed-salt + Phase 288 dailyIdx snapshot | For values that legitimately vary across players' lifecycle (activity score, affiliate points, quest streak, distress flag, presale flag, base level, EV cap, pool balance) — freeze the value at lootbox-allocation timestamp into a per-index storage cell. One new SSTORE at allocation; one new storage slot per index per snapshotted variable. |
| (c) pre-lock reorder | 3 (D-23, D-28, D-42) | None — pure code-ordering | Reorder self-stack writes inside `_resolveLootboxCommon` that mutate participating slots BEFORE the final-emission point but AFTER seed derivation, to execute AFTER the roll commits its outputs. Zero new storage. |
| (d) immutable | 0 | — | Every participating slot is legitimately mutable across the game lifecycle; no immutable recommendation applies. |

Cluster (b) is the dominant pattern (16 rows) reflecting the structural mismatch between TX A allocation (where the player has committed his stake) and TX C resolution (where every other piece of contributing state is sampled live). Cluster (a) is the secondary pattern for global state slots whose value should remain global but whose mutators must close during open-window. Cluster (c) is the minimal pattern for own-stack mutations that simply need to fire AFTER the roll outputs commit.

Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline before locking the final tactic on each of E-1..E-35. Self-stack VIOLATION rows (D-1, D-15, D-18, D-23, D-28, D-29, D-33, D-41, D-42) are downgrade candidates per Phase 299 game-theory review (intra-tx mutations cannot be exploited across the actor-set in v43.0's audit model).

## Methodology Discipline

- `feedback_rng_backward_trace.md` — traced backward from both consumer entries (`:960` and `:1623`); verified RNG word unknown at every prior writer-callsite commitment time when the writer is on an EXEMPT stack, and confirmed the RNG word IS known at write-time for every VIOLATION writer-callsite (these writers run between TX B and TX C, hence after RNG publish).
- `feedback_rng_window_storage_read_freshness.md` — enumerated ALL SLOADs in the resolution path, not just VRF-derived seeds; identified 25 participating + 4 non-participating reads (covering F-41-02/03-class non-VRF-derived freshness gaps). Both the cross-contract reads (`dgnrs.poolBalance`, `affiliate.affiliateBonusPointsBest`, `questView.playerQuestStates`) and the cross-resolution-accumulator read (`lootboxEvBenefitUsedByLevel`) are F-41-02/03-class participants in this catalog.
- `feedback_rng_commitment_window.md` — confirmed the open commitment window between `lootboxRngWordByIndex[index]` SSTORE (TX B, `AdvanceModule.sol:1256` or `:1761`) and the player-discretion `openLootBox` invocation (TX C) spans an unbounded number of blocks (no on-chain rate-gate, no cooldown, no `rngLockedFlag` guard inside `openLootBox`/`openBurnieLootBox` themselves); every participating slot whose writer is reachable from a non-EXEMPT EOA stack within this window classifies VIOLATION.
- `feedback_verify_call_graph_against_source.md` — every claim grep-verified pre-write; 42 functions enumerated by file:line in §A; cross-module SLOADs cited at exact lines (BoonModule, MintStreakUtils, sDGNRS interface, Affiliate interface, QuestView). No "by construction" / "covered by single fn" shortcuts.
- `feedback_no_contract_commits.md` — zero `contracts/` + zero `test/` mutations (AUDIT-ONLY phase per D-43N-AUDIT-ONLY-01).

## Deviations from Plan

None — plan executed exactly as written. Task 7.1 emitted the required §A..§E sections with no `SAFE_BY_DESIGN` dispositions in §D, 35 VIOLATION rows in §D, and 35 corresponding §E rows each with tactic ∈ {(a), (b), (c)} + ≤80-char rationale.

## Threat Flags

None — this plan is pure analysis; no new contract surface introduced.

## Self-Check: PASSED

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-07-CATALOG-section.md` exists (verified `test -f`).
- `## CAT-01`, `## CAT-02`, `## CAT-03`, `## CAT-04`, `## CAT-06` sub-headings present (verified `grep -c` returns 5).
- `SAFE_BY_DESIGN` absent from catalog section (verified `grep -c SAFE_BY_DESIGN` returns 0).
- Every §D verdict row ∈ {`EXEMPT-ADVANCEGAME`, `EXEMPT-VRFCALLBACK`, `EXEMPT-RETRYLOOTBOXRNG`, `VIOLATION`}.
- Every §E VIOLATION row has tactic ∈ {(a), (b), (c)} (no (d)) and rationale ≤80 chars (verified by awk-based length check across all 35 rows).
- Zero `contracts/` + zero `test/` modifications (verified `git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` returns 0).
- No `STATE.md` / `ROADMAP.md` edits in this plan's commit (parallel-dispatch session — STATE.md updates are out of scope).
