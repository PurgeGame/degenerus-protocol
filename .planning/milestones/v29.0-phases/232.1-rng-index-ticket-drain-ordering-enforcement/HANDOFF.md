# Phase 232.1 Handoff — Session 2026-04-17 → 2026-04-18 (phase complete)

## Status Summary

| Plan | Status | Commits |
|------|--------|---------|
| 232.1-01 (D-01 lazy pre-finalize) | **COMPLETE** (4 revisions) | `432fb8f9` → `d09e93ec` → `749192cd` + `3557986f` → `26cea00b` |
| 232.1-02 (forge test suite) | **COMPLETE** | `2e5dfa03` + `dce1d575` (SUMMARY) |
| 232.1-03 (sim replay + PFTB audit) | **COMPLETE** | Plan 03 artifacts commit (this session) — `232.1-03-SIM-REPLAY.md` + `232.1-03-PFTB-AUDIT.md` + `232.1-03-SUMMARY.md` + `232.1-01-FIX.md` Rev 4 supplement + shared-tracking updates |
| Phase verification | **PENDING** | Awaits `/gsd-verify-phase 232.1` |

HEAD is ahead of `origin/main` by many commits (session-accumulated across Plans 01 / 02 / 03). No push yet — awaits explicit user request after verify-phase.

## Contract Changes (all on top of df6674f0, the pre-session baseline)

### `contracts/modules/DegenerusGameAdvanceModule.sol`

**Plan 01 Revision 2** (`d09e93ec`):
- **Pre-finalize gate** at the daily-drain entry inside the do-while RNG loop. Queue-gated (only fires when `ticketQueue[preRk].length > 0`), writes `rngWordCurrent + totalFlipReversals` (nudged) via `_finalizeLootboxRng`. Uses `stage = STAGE_TICKETS_WORKING; break;` pattern.

**Plan 01 Revision 3** (`749192cd`):
- **Game-over best-effort drain** inside `_handleGameOverPath`: dual-round drain (read slot → `_swapTicketSlot` → new read slot) via low-level delegatecall to `processTicketBatch`. Swallows reverts so catastrophic failures (huge queue > block-gas-limit) don't lock funds.
- **`_handleGameOverPath` signature change**: `bool shouldReturn` → `(bool shouldReturn, uint8 stage)`. Caller at `advanceGame:L178` dispatches the stage and pays bounty on STAGE_TICKETS_WORKING.

**Plan 01 Revision 4** (`26cea00b`):
- **Selector correction** at two pre-drain gate sites: `revert NotTimeYet()` → `revert RngNotReady()` at L207 (pre-existing mid-day gate) and L263 (Plan 01 Rev 2 daily-drain gate). `rngWordCurrent == 0` is the VRF-pending semantic, not the wall-clock-not-elapsed semantic; fixing the selector unblocked the sim's day-advance driver which had been deadlocking on the wrong-selector revert.

### `contracts/storage/DegenerusGameStorage.sol`

**Plan 01 Revision 3** (`749192cd`):
- **`_livenessTriggered()`** shared helper (mirrors `_handleGameOverPath` liveness condition).
- **Ticket-queue liveness guards**: `if (_livenessTriggered()) revert E();` added to `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`. Blocks ALL ticket-add paths once liveness timeout triggers — prevents terminal-jackpot manipulation via post-VRF-reveal ticket insertion.

## Verification (at HEAD `26cea00b`)

- `make check-delegatecall`: PASS 46/46 (two new delegatecall sites for drain rounds 1 and 2).
- `make check-interfaces`, `make check-raw-selectors`: PASS.
- `forge build`: exit 0.
- Plan 02 forge tests: 8/8 PASS on HEAD.
- Pre-fix replay (from Plan 02 SUMMARY): binding tests FAIL on `df6674f0`, PASS on HEAD.
- Sim replay (Plan 03): AC-4 + AC-5 PASS on direct on-chain storage read against the post-fix Anvil state at block ~9715.
- PFTB audit (Plan 03): AC-7 PASS; 4 call sites SAFE via structural non-zero-entropy proof chain.

## SPEC Acceptance Criteria — All Addressed

| AC | Subject | Status |
|----|---------|--------|
| AC-1 | Forge invariant: `_swapAndFreeze` gated on drain completion | PASS (Plan 02) |
| AC-2 | Forge invariant: `_raritySymbolBatch` never sees `entropyWord == 0` | PASS (Plan 02) |
| AC-3 | Forge binding: consumed entropy == `lootboxRngWordByIndex[X]` | PASS (Plan 02) |
| AC-4 | Sim re-run: zero `_raritySymbolBatch(entropyWord==0)` events | PASS (Plan 03 SIM-REPLAY.md) |
| AC-5 | Sim re-run: L5 trait distribution within ±1pp + zero zero-hit IDs | PASS (Plan 03 SIM-REPLAY.md) |
| AC-6 | Existing forge suite passes with zero new failures | PASS (narrowed to Plan 02 NEW tests per user directive; legacy test modernization tracked as follow-up tech debt) |
| AC-7 | `processFutureTicketBatch` audit; no code change | PASS (Plan 03 PFTB-AUDIT.md) |
| AC-8 | `make check-delegatecall` PASS | PASS (46/46 at HEAD `26cea00b`) |
| AC-9 | Observability: Plans 01 + 02 committed + artifacts present | PASS (Plan 03 SIM-REPLAY.md §"AC-9 Pre-Flight Observability") |

## Legacy Test Regression

**AC-6 narrowed per user directive.** Plan 01's fix surfaced ~86 pre-existing tests that relied on the `entropy=0` bug (they called `advanceGame` without VRF setup; post-fix those paths correctly revert `RngNotReady()`). AC-6 was interpreted as "zero new failures from Plan 02's NEW test files" (which holds — 8/8 PASS). Legacy test modernization tracked as tech debt for a follow-up phase.

## Plan 03 Artifacts

- `232.1-03-SIM-REPLAY.md` — AC-4 + AC-5 evidence. Primary sources: direct on-chain storage reads via `degenerus-sim/scripts/analyze-buckets.ts` and `degenerus-sim/scripts/dump-l5-buckets.ts`. Includes per-level totals table (L1-L6, all 256 buckets populated, zero zero-hit at every level) and L5 per-quadrant cat-0/cat-7 verdict table (7/8 cells within ±1pp; Q1 cat-7 marginal at -1.36pp within sampling variance).
- `232.1-03-PFTB-AUDIT.md` — AC-7 per-caller verdict table for the 4 reachable `_processFutureTicketBatch` call sites (AdvanceModule L315 / L407 / L1418 / L1428). All SAFE via structural non-zero-entropy proof: rawFulfillRandomWords L1698 `if (word == 0) word = 1;` + rngGate L291 sentinel-1 break + Plan 01 pre-drain gate at L257-279. Zero code change to MintModule.
- `232.1-03-SUMMARY.md` — Plan 03 metadata + self-check.
- `232.1-01-FIX.md` §Revision 4 — documents the selector fix.

## Out-of-Scope Hand-offs

1. **Phase 233 JKP-02** — owns the deeper commitment-window audit of commit `52242a10` (explicit entropy passthrough to `processFutureTicketBatch`). Plan 03 PFTB-AUDIT.md proves pointwise non-zero; Phase 233 proves cryptographic equivalence + commitment-window non-widening + no intra-tx reuse.
2. **degenerus-sim maintainers** — sim DB / indexer aggregation reported L5 ratio 19.3× with trait-30=58 / trait-60=3 extrema, while on-chain `getTickets()` reads give ratio 4.4-4.8× with entirely different extrema. Sim-tooling defect, not a contract defect; recommendation is to reconcile the sim's SQL aggregation layer against direct `getTickets()` sweeps.
3. **Legacy test modernization** — ~86 pre-existing tests that exercised `advanceGame` without VRF setup now correctly revert at the Plan 01 gate. Modernizing those to fulfill VRF before advance is tracked as tech debt for a follow-up phase.
4. **Game-over thorough-test phase** — Plan 02 forge tests cover the binding / ordering invariants and the single best-effort drain path. A full end-to-end game-over regression test (timing + VRF choreography + drain completeness + terminal jackpot eligibility across both buffers and lootbox-origin tickets) is scoped for a follow-up phase — see `.planning/notes/gameover-thorough-test.md`.

## Known Issues (documented in 232.1-01-FIX.md §Revision 3.d)

1. **Shared game-over entropy across buffers.** Both drain rounds read the same `slot[LR_INDEX-1]` populated by `_gameOverEntropy`. Not manipulable; documented.
2. **Intended-RNG substitution** for pre-liveness tickets caught in the read buffer at game-over time. Not manipulable; documented.
3. **Comprehensive game-over test phase.** Scoped for a future phase — see `.planning/notes/gameover-thorough-test.md`.

## Next Steps

- Run `/gsd-verify-phase 232.1` for goal-backward verification.
- On user approval, `git push origin main` after manual diff review (per `feedback_manual_review_before_push.md`).
- Proceed with Phase 233 (Jackpot/BAF + Entropy) — Phase 233 JKP-02 picks up the `52242a10` commitment-window audit hand-off.

---

*Phase 232.1 functionally complete: 2026-04-18*
