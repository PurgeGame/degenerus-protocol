# Phase 180: Storage Layout & Configuration Verification - Context

**Gathered:** 2026-04-04 (assumptions mode, --auto)
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify storage layout identity across all DegenerusGameStorage inheritors after v16.0 repack and rngBypass changes. Verify rngBypass parameter usage is correct — all `true` callers internal to advanceGame, all `false` callers external-facing. Verify ContractAddresses alignment after GAME_ENDGAME_MODULE removal.

</domain>

<decisions>
## Implementation Decisions

### Storage Layout Verification (DELTA-02)
- **D-01:** Run `forge inspect <Contract> storage-layout` on all 13 contracts that inherit DegenerusGameStorage: DegenerusGame, AdvanceModule, MintModule, JackpotModule, LootboxModule, BoonModule, DegeneretteModule, DecimatorModule, WhaleModule, GameOverModule, MintStreakUtils, PayoutUtils, and the Storage contract itself
- **D-02:** Diff each layout against DegenerusGameStorage.sol — all slot offsets, types, and sizes must be byte-identical. Any divergence is a CRITICAL finding.
- **D-03:** This was previously verified at v16.0 (Phase 172 delta verification) — this phase confirms no drift since then through v17.0/v17.1 changes

### rngBypass Verification (DELTA-03)
- **D-04:** Trace UPWARD from the 4 rngBypass-accepting functions in DegenerusGameStorage.sol (_queueTickets:553, _queueTicketsScaled:582, _queueTicketRange:630, wrapper:666) to every call site
- **D-05:** Classify each caller as `true` (internal/advanceGame path) or `false` (external/player-facing). Known callers from codebase scan:
  - `true` callers: JackpotModule:863 (BAF jackpot), JackpotModule:1070 (jackpot winner) — both only reachable from advanceGame delegatecall
  - `false` callers: DegenerusGame:213-214 (init), Storage:1100 (internal), LootboxModule:974/1097, MintModule:816, WhaleModule:313/482/625/979, AdvanceModule:1299/1305, DecimatorModule:391 — all external or player-initiated
- **D-06:** Verify no path exists where a `true` caller is reachable from an external transaction (non-advanceGame entry point)

### ContractAddresses Alignment (DELTA-04)
- **D-07:** Verify every address label in ContractAddresses.sol maps to the correct contract — read-only audit, NEVER modify the file (per standing feedback: user manages deploy addresses manually)
- **D-08:** Confirm GAME_ENDGAME_MODULE (line 16) is dead — no contract references this address after EndgameModule deletion in v16.0. If any reference exists, that's a finding.
- **D-09:** Check all other labels against their consumers via grep — each label should be used by at least one live contract

### Claude's Discretion
- Exact output format for the storage layout diff (table vs inline diff)
- Whether to include the full forge inspect output or just the diff summary
- Grouping of rngBypass callers (by contract vs by true/false classification)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Storage Layout
- `contracts/storage/DegenerusGameStorage.sol` — Base storage contract; all modules inherit this layout
- `.planning/milestones/v16.0-phases/168-storage-repack/` — v16.0 storage repack implementation (slot 0 filled to 32/32 bytes, currentPrizePool downsized)

### rngBypass Refactor
- `contracts/storage/DegenerusGameStorage.sol:549-670` — All 4 rngBypass-accepting functions
- `.planning/phases/179-change-surface-inventory/179-02-FUNCTION-VERDICTS.md` — Phase 179 verdicts (all 50 SAFE) — rngBypass functions already received initial SAFE verdict

### ContractAddresses
- `contracts/ContractAddresses.sol` — Address label registry; GAME_ENDGAME_MODULE still present at line 16
- `.planning/milestones/v16.0-phases/171-delete-endgamemodule/` — EndgameModule deletion context

### Prior Audit Baseline
- `.planning/REQUIREMENTS.md` — DELTA-02, DELTA-03, DELTA-04 define this phase's requirements
- `.planning/phases/179-change-surface-inventory/179-01-DIFF-INVENTORY.md` — Complete diff inventory of all changes since v15.0

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `forge inspect <Contract> storage-layout` — Foundry storage inspection tool, used in v16.0 Phase 172 to confirm identical layouts across 11 contracts
- Phase 179 diff inventory and function verdicts — provides the complete change surface that this phase verifies

### Established Patterns
- Storage layout verification: `forge inspect` JSON output, slot-by-slot comparison
- rngBypass was introduced to replace `phaseTransitionActive` guard — the old guard silently skipped far-future rolls during phase transitions, new parameter makes bypass explicit
- ContractAddresses.sol is managed by user — audit-only, never modify

### Integration Points
- 13 contracts inherit DegenerusGameStorage — all must have identical storage layout
- rngBypass callers span 7 modules (AdvanceModule, MintModule, JackpotModule, LootboxModule, WhaleModule, DecimatorModule, DegenerusGame) plus Storage internal calls
- ContractAddresses is imported by 26 contracts across the protocol

</code_context>

<specifics>
## Specific Ideas

- The v16.0 Phase 172 verification already confirmed identical layout across 11 contracts — this is a re-verification after v17.0/v17.1 changes (which should not affect storage but must be confirmed)
- GAME_ENDGAME_MODULE at ContractAddresses.sol:16 is the expected dead reference — verify no live contract uses it
- AdvanceModule lines 1299/1305 and LootboxModule line 1097 need the full call context checked — the grep was truncated and the rngBypass value wasn't visible in the initial scan

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope

</deferred>

---

*Phase: 180-storage-layout-configuration-verification*
*Context gathered: 2026-04-04*
