# Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition — Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Analytical re-proof phase over the full v29.0 delta. Five requirements:

- **CONS-01** — ETH conservation across every new/modified SSTORE touching `currentPrizePool` / `nextPrizePool` / `futurePrizePool` / `claimablePool` / `decimatorPool`; sum-before = sum-after at every path endpoint.
- **CONS-02** — BURNIE conservation across `BurnieCoin.sol` + quest changes; no new mint site bypasses `mintForGame`; mint/burn accounting closes end-to-end.
- **RNG-01** — Backward trace from every new RNG consumer in the delta proving the VRF word was unknown at input commitment time.
- **RNG-02** — Commitment-window analysis: every player-controllable state variable between VRF request and fulfillment enumerated and verified non-influential for every new consumer.
- **TRNX-01** — `_unlockRng(day)` removal at `DegenerusGameAdvanceModule:425` (commit `2471f8e7`) — rngLocked invariant preserved across the newly-packed housekeeping step, no exploitable state-changing path, no missed/double unlock on any reachable path.

Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 236 (FIND-01/02/03); Phase 235 produces per-function verdicts + per-SSTORE catalogs + per-consumer backward-trace + commitment-window tables + 4-path walk for TRNX-01 that become the finding-candidate pool.

Scope source is `230-01-DELTA-MAP.md` + `230-02-DELTA-ADDENDUM.md` (both READ-only per Phase 230 D-06).

**Mid-milestone changes explicitly in scope:** the 232.1 fix series (pre-finalize gate, queue-length gate, nudged-word, do-while integration, game-over best-effort drain, RngNotReady selector correction) AND the 230-02 addendum commits (`314443af` `_raritySymbolBatch` keccak-seed fix, `c2e5e0a9` 17-site XOR→keccak entropy-mixing replacement) are all audited at HEAD. Ticket-processing surface moved under three phases (230 baseline → 232.1 fix series → HEAD) and Phase 235 proofs MUST reflect the final shape, not the baseline shape. HEAD anchor is current HEAD at phase start, locked in every plan's frontmatter.

</domain>

<decisions>
## Implementation Decisions

### Plan Shape
- **D-01 (5 plans, strict per-requirement):** Five plan files mapping 1:1 to the five requirements — `235-01-PLAN.md` CONS-01 (ETH), `235-02-PLAN.md` CONS-02 (BURNIE), `235-03-PLAN.md` RNG-01 (backward trace), `235-04-PLAN.md` RNG-02 (commitment window), `235-05-PLAN.md` TRNX-01 (phase transition). Matches the 231/232/233 one-plan-per-requirement precedent exactly; each plan is self-contained and independently auditable.
- **D-02 (all parallel, Wave 1):** Plans have no cross-dependencies — each audits a different surface and cites the 230 catalog + addendum directly. Same parallelization pattern used for Phases 233 + 234.

### Evidence Reuse
- **D-03 (fresh re-prove + cross-cite prior):** Phase 235 re-runs the full backward-trace + full SSTORE catalog + full path walks independently at HEAD, produces its own verdicts, and CROSS-CITES (does not reuse) verdicts from Phases 231/232/233/234 as corroborating evidence. Per v25.0 Phase 215 D-03 and Phase 216 D-01 "fresh from scratch" precedent — catches cases where a narrower prior-phase question missed something a milestone-wide lens would catch.
- **D-04 (cite + re-verify at HEAD):** When citing a prior-phase verdict, include a one-line `re-verified at HEAD <SHA>` note per cited row. HEAD has moved substantially since Phases 231/232 executed (232.1 Rev 4 selector fix + 230-02 addendum commits + 233/234 verified autonomously on 2026-04-19) — re-verification catches any regression introduced between the cited audit and the Phase 235 audit.
- **D-05 (HEAD anchor = current HEAD at phase start):** Resolve HEAD SHA when planning starts and lock it as the audit baseline in every plan's frontmatter (same pattern as Phase 230 D-06). Any subsequent commit is out-of-scope unless explicitly re-addended.

### Mid-Milestone Scope Inclusion — CRITICAL
- **D-06 (232.1 + addendum in scope; per-requirement ticket-processing sub-section):** Every plan (CONS-01/02, RNG-01/02, TRNX-01) MUST include a named "232.1 ticket-processing impact" sub-section walking the 232.1 fix series changes (pre-finalize gate, queue-length gate, nudged-word, do-while integration, game-over best-effort drain, RngNotReady selector) against that requirement. Cannot be silently skipped. Rationale: ticket processing moved under three phases (230 baseline → 232.1 fix series → HEAD) and RNG / conservation proofs MUST reflect the final shape, not the baseline shape. Addendum commits (`314443af`, `c2e5e0a9`) are surfaced via D-07/D-08/D-09 and additionally cited here where their call sites interact with ticket processing.

### Addendum Treatment (c2e5e0a9 + 314443af)
- **D-07 (c2e5e0a9 17 sites — full per-site backward-trace):** Each of the 17 new `EntropyLib.hash2` / `keccak256(abi.encode(...))` entropy-mixing sites from `c2e5e0a9` is treated as a NEW RNG CONSUMER for RNG-01 purposes. Backward-trace from each site proves the VRF word was unknown at input commitment time. Per the `feedback_rng_backward_trace.md` methodology rule applied to every consumer. No equivalence-class shortcuts — each site is its own table row.
- **D-08 (c2e5e0a9 17 sites — full commitment-window enumeration):** Each of the 17 sites enumerates player-controllable state reads inside the `hash2` / `keccak` inputs and verifies non-influential. Per the `feedback_rng_commitment_window.md` methodology rule applied to every consumer. Paired with D-07 — backward-trace answers "was the word known at commit time" and commitment-window answers "can an attacker change state between request and fulfillment that influences the output".
- **D-09 (314443af `_raritySymbolBatch` keccak-seed fix — RNG-01/02 include; cross-cite 232.1-03):** RNG-01/02 audit the new keccak-seed diffusion (`baseKey + entropyWord + groupIdx` via `keccak256(abi.encode(...))`) as a NEW RNG CONSUMER property. Non-zero-entropy-at-call-site is CROSS-CITED (not re-derived) from `232.1-03-PFTB-AUDIT.md`, which already proved non-zero entropy at all 4 reachable `_processFutureTicketBatch` call sites via the `rawFulfillRandomWords` L1698 zero-guard + `rngGate` L291 sentinel-1 break + Plan 01 pre-drain gate. Clean split — diffusion is Phase 235's question; availability is 232.1's closed question.

### TRNX-01 Audit Depth & Invariant
- **D-10 (TRNX-01 medium depth: invariant + state-path enumeration):** The TRNX-01 plan proves (a) rngLocked invariant preservation — the flag reaches the same end-state via the downstream `_unlockRng` that still fires, (b) enumerates every state mutation in the now-packed housekeeping window between `_endPhase()` and the next `_unlockRng` reactivation, (c) verifies no exploitable state-changing path inside that window, (d) no missed or double unlock on any reachable path.
- **D-11 (rngLocked invariant — exact statement per user):** During the rngLocked window (VRF request → fulfillment), across the newly-packed housekeeping step: **(a) NO far-future ticket queue write may occur, AND (b) NO write may land in the active (read-side) buffer.** Writes to the write-side buffer at the current level ARE PERMITTED — they drain next round with the next VRF word. rngLocked is NOT a blanket ticket-queueing block. This is the REAL invariant; any audit that models rngLocked as a general ticket-queueing lock is incorrect.
- **D-12 (buffer model):** There are two ticket buffers — a read buffer (currently being drained against the in-flight VRF word) and a write buffer (accepting new tickets at the current level). The buffer **SWAP fires at RNG REQUEST TIME** (not at fulfillment): the buffer that was being written-into becomes the read buffer; the previous read buffer empties and becomes the new write buffer. TRNX-01 plan must cite the buffer-swap code site concretely and verify swap timing is consistent across the packed housekeeping window on every path enumerated in D-13.
- **D-13 (paths traced end-to-end):** TRNX-01 explicitly walks four paths:
  - **Normal:** jackpot-phase day N → packed housekeeping → purchase-phase day 1 of next level. Covers the load-bearing `_unlockRng` deletion point.
  - **Gameover:** game-over triggered during jackpot phase. Housekeeping correctly runs or is skipped; rngLocked end-state matches terminal expectations. 232.1 Plan 01 Rev 3 liveness-triggered ticket block lives on this path.
  - **Skip-split:** jackpot-phase skip-split variant (`JACKPOT_LEVEL_CAP` branch conditions differ). No missed / no double unlock.
  - **Phase-transition freeze:** the `phaseTransitionActive` branch at `DegenerusGameAdvanceModule:283`. Verify `_unlockRng` is NOT reachable inside the branch AND the packed housekeeping step does NOT introduce a second `_unlockRng` site.

### Finding-ID Emission
- **D-14 (no F-29-NN IDs emitted):** Phase 235 does NOT emit `F-29-NN` finding IDs. Plans produce per-function verdicts + per-SSTORE catalogs + per-consumer backward-trace + commitment-window tables + 4-path walks that become the finding-candidate pool. Phase 236 (FIND-01/02/03) owns ID assignment, severity classification, and consolidation into `audit/FINDINGS-v29.0.md`. Every verdict cites commit SHA + file:line so Phase 236 can anchor without re-discovery. Mirrors the D-11 pattern of Phases 231/232/233 and the D-14 pattern of Phase 234.

### Scope-Guard Handoff
- **D-15 (230 catalog READ-only — scope-guard deferral rule):** If any Phase 235 plan discovers a gap that would require editing `230-01-DELTA-MAP.md` or `230-02-DELTA-ADDENDUM.md`, the plan records a scope-guard deferral in its own SUMMARY following the D-227-10 → D-228-09 → Phase 230 D-06 precedent rather than editing the catalog in place.
- **D-16 (no regression sweep — Phase 236 REG-01/02):** Phase 235 does NOT re-verify prior-milestone findings (v25.0, v26.0, v27.0). Regression is Phase 236's REG-01/REG-02 deliverable.
- **D-17 (READ-only scope; no contracts/ or test/ writes):** Any test-coverage gap discovered is documented as a candidate finding for Phase 236 routing, not addressed in-phase. Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` — no contract / test changes without explicit user approval, and orchestrator never pre-approves on user's behalf.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 230 catalog — exclusive scope source per D-15
- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md`
  - §1 (all pool-mutating SSTORE sites) — CONS-01 catalog source
  - §1.1 `_consolidatePoolsAndRewardJackpots`, `_finalizeEarlybird` — CONS-01 ETH mutation sites
  - §1.1 `advanceGame` MODIFIED by `2471f8e7` + `52242a10` — TRNX-01 + RNG-02 entry points
  - §1.1 `_processFutureTicketBatch` / `_prepareFutureTickets` — RNG-01/02 + TRNX-01 buffer swap
  - §1.2 `_runEarlyBirdLootboxJackpot` + `runBafJackpot` — RNG-01 (bonus-trait + BAF sentinel emission)
  - §1.3 `claimDecimatorJackpot` — CONS-01 `decimatorPool` mutation sites
  - §1.4 MintModule `processFutureTicketBatch` + `_raritySymbolBatch` — RNG-01 + `314443af`
  - §1.4 MintModule quest credit chain — CONS-02 (BURNIE routing through `mintForGame`)
  - §1.6 `recordMint` — CONS-01 pool-mutation sites
  - §1.7 `DegenerusQuests.handlePurchase` — CONS-02 (`mint_ETH` quest credit)
  - §1.8 `BurnieCoin.decimatorBurn` — CONS-02 BURNIE mint/burn accounting
  - §2 (all pool-SSTORE-producing chains) — CONS-01 flow traces
  - §2.3 IM-10 through IM-16 — RNG-01/02 consumer chains
  - §2.5 IM-21 (the deleted `_unlockRng(day)` call at `advanceGame:425` pre-`2471f8e7`) — TRNX-01
  - §2.5 IM-22 (entropy-commitment boundary replay row) — RNG-01/02 passthrough boundary
  - §3.4 + §3.5 (automated gate status) — corroborating structural baseline at HEAD
  - §4 Consumer Index CONS-01 / CONS-02 / RNG-01 / RNG-02 / TRNX-01 rows — scope routing
- `.planning/phases/230-delta-extraction-scope-map/230-02-DELTA-ADDENDUM.md`
  - §"Commits added to v29.0 scope" — `314443af` + `c2e5e0a9` per-site verdict tables (starting evidence set; Phase 235 re-verifies from HEAD per D-04)
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — Phase 230 deliverables snapshot + "Handoff to Phases 231-236" block naming Phase 235 consumers

### Phase 232.1 artifacts — MUST re-verify at HEAD per D-06
- `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-CONTEXT.md` — locked invariants for the fix series (drain-before-swap, no-zero-entropy, ticket↔RNG binding)
- `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-01-FIX.md` — pre-finalize gate + queue-length gate + nudged-word + do-while + game-over drain + RngNotReady selector (4 revisions)
- `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-02-SUMMARY.md` — forge invariant + binding + game-over path-isolation suite (8/8 PASS at HEAD)
- `.planning/phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-SIM-REPLAY.md` + `232.1-03-PFTB-AUDIT.md` — non-zero entropy at all 4 reachable `_processFutureTicketBatch` call sites (CROSS-CITE source for D-09)

### Prior Phase 231/232/233/234 verdicts — cross-cited per D-03, re-verified per D-04
- `.planning/phases/231-earlybird-jackpot-audit/231-01-AUDIT.md` + `231-02-AUDIT.md` + `231-03-AUDIT.md` — EBD-01/02/03 verdicts (earlybird CEI, salt-space isolation, trait-alignment rewrite, combined state machine across orthogonal storage namespaces)
- `.planning/phases/232-decimator-audit/232-01-AUDIT.md` — DCM-01 burn-key refactor (`decimatorPool` SSTORE sites; BurnieCoin sum-in/sum-out handoff to Phase 235 CONS-02 per D-14 of Phase 232)
- `.planning/phases/232-decimator-audit/232-02-AUDIT.md` — DCM-02 event emission (CEI positions post-SSTORE; no new pool mutation)
- `.planning/phases/232-decimator-audit/232-03-AUDIT.md` — DCM-03 terminal-claim passthrough (no new ETH mutation; no new RNG consumer)
- `.planning/phases/233-jackpot-baf-entropy-audit/233-01-AUDIT.md` — JKP-01 BAF `traitId=420` sentinel (event widening; no trait-space collision)
- `.planning/phases/233-jackpot-baf-entropy-audit/233-02-AUDIT.md` — JKP-02 entropy passthrough (backward-trace + commitment-window applied per D-06 of Phase 233 at the passthrough boundary)
- `.planning/phases/233-jackpot-baf-entropy-audit/233-03-AUDIT.md` — JKP-03 cross-path `bonusTraitsPacked` consistency
- `.planning/phases/234-quests-boons-misc-audit/234-01-AUDIT.md` — QST-01/02/03 (`mint_ETH` wei credit, `boonPacked` exposure, `BurnieCoin.sol` change; BURNIE supply conservation handoff to Phase 235 CONS-02 per D-11 of Phase 234)

### Milestone scope
- `.planning/REQUIREMENTS.md` §"ETH / BURNIE Conservation + RNG Commitment Re-Proof" (CONS-01/02, RNG-01/02) + §"Phase Transition (RNG Lock)" (TRNX-01)
- `.planning/ROADMAP.md` Phase 235 block (Goal, `Depends on: Phase 231, Phase 232, Phase 233, Phase 234`, 5 Success Criteria)
- `.planning/PROJECT.md` Current Milestone v29.0 — in-scope commits list + audit target `contracts/` directory per `feedback_contract_locations.md`

### Methodology precedent
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/215-02-BACKWARD-TRACE.md` — direct template for RNG-01 per-consumer backward-trace table shape
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/215-03-COMMITMENT-WINDOW.md` — direct template for RNG-02 commitment-window enumeration
- `.planning/milestones/v25.0-phases/216-pool-eth-accounting/216-01-ETH-CONSERVATION.md` — template for CONS-01 algebraic + flow-trace ETH conservation
- `.planning/milestones/v25.0-phases/216-pool-eth-accounting/216-02-POOL-MUTATION-SSTORE.md` — template for CONS-01 per-SSTORE catalog format
- `.planning/milestones/v25.0-phases/216-pool-eth-accounting/216-03-CROSS-MODULE-FLOWS.md` — template for end-to-end flow verification
- `.planning/phases/233-jackpot-baf-entropy-audit/233-02-SUMMARY.md` — JKP-02 D-06 backward-trace + commitment-window application at the entropy-passthrough boundary (the scoped version of Phase 235 RNG-01/02)

### User-feedback rules applied
- `feedback_rng_backward_trace.md` — applied in D-07 + RNG-01 methodology (mandatory per-consumer backward trace)
- `feedback_rng_commitment_window.md` — applied in D-08 + RNG-02 methodology (player-controllable state between VRF request and fulfillment)
- `feedback_skip_research_test_phases.md` — no standalone research plan (obvious/mechanical audit phase)
- `feedback_no_contract_commits.md` — READ-only scope (D-17); no `contracts/` or `test/` writes
- `feedback_never_preapprove_contracts.md` — orchestrator must never tell subagents contract changes are pre-approved
- `feedback_contract_locations.md` — read contracts only from `contracts/`; stale copies exist elsewhere

### Contract source — current HEAD at phase start (SHA resolved by planner per D-05)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame` (phase-transition site), `_processFutureTicketBatch`, `_prepareFutureTickets`, `rngGate`, `_finalizeRngRequest`, `_unlockRng`, `phaseTransitionActive` branch
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_runEarlyBirdLootboxJackpot`, `runBafJackpot`, `payDailyJackpot`, `_rollWinningTraits`, 16 `c2e5e0a9` entropy-mixing sites
- `contracts/modules/DegenerusGameMintModule.sol` — `processFutureTicketBatch`, `_raritySymbolBatch` (`314443af`), `recordMint`, `_rollRemainder` (`c2e5e0a9`)
- `contracts/modules/DegenerusGameDecimatorModule.sol` — `claimDecimatorJackpot`, `claimTerminalDecimatorJackpot`, `_creditClaimable`, `_consumeTerminalDecClaim`
- `contracts/libraries/EntropyLib.sol` — `hash2` helper (NEW via `c2e5e0a9`)
- `contracts/modules/DegenerusGamePayoutUtils.sol` — `_calcAutoRebuy` (`c2e5e0a9` site)
- `contracts/modules/DegenerusGameGameOverModule.sol` — `handleGameOverDrain` (gameover path for TRNX-01 D-13)
- `contracts/DegenerusGame.sol` — external wrappers (ETH entry points, delegatecall targets)
- `contracts/storage/DegenerusGameStorage.sol` — `prizePoolsPacked`, `claimableWinnings`, `decimatorPool`, `rngLocked`, `lootboxRngWordByIndex`, `earlybirdDgnrsPoolStart`
- `contracts/BurnieCoin.sol` — `mintForGame`, `decimatorBurn`, burn/mint accounting (CONS-02)
- `contracts/DegenerusQuests.sol` — `handlePurchase`, `_isLevelQuestEligible`, `mint_ETH` handler (CONS-02 BURNIE routing)

</canonical_refs>

<code_context>
## Existing Code Insights

### CONS-01 Surface (ETH Conservation — from 230 Consumer Index)
- Phase 230 catalog §1 identifies every modified/new SSTORE touching prize-pool slots.
- Primary surface: `_consolidatePoolsAndRewardJackpots` (consolidated batching), `_runEarlyBirdLootboxJackpot` (futurePool → nextPool, per Phase 231 EBD-02), `claimDecimatorJackpot` (decPool → claimable, per Phase 232 DCM-01), `_purchaseFor` (ETH ingress), `recordMint` (fresh-ETH accounting, per Phase 231 EBD-01 award-block removal), `_finalizeEarlybird` (external `StakedDegenerusStonk.transferBetweenPools`).
- 232.1 ticket-processing impact (per D-06): `processTicketBatch` writes to the active buffer must be correctly gated by the pre-finalize + queue-length + do-while gates — CONS-01 must confirm no ETH leaks into ticket state during the rngLocked window, and that any ETH held in pool slots is correctly attributed across the buffer swap at RNG request time.

### CONS-02 Surface (BURNIE Conservation)
- Primary mint invariant: `BurnieCoin.mintForGame` — every BURNIE creation must flow through this function.
- Quest credit path: `DegenerusQuests.handlePurchase` → `mint_ETH` handler → `mintForGame` (`d5284be5` 1:1 wei-credit fix).
- Decimator burn path: `BurnieCoin.decimatorBurn` (`3ad0f8d3` burn-key refactor — inherited via QST-03 + DCM-01 handoffs).
- 232.1 impact (per D-06): lootbox BURNIE redirect to far-future key space (bit 22 per v11.0) + `mintForGame` gating during `gameOverPossible` drip projection — CONS-02 must confirm no new mint site was added inside the 232.1 fix series.

### RNG-01 / RNG-02 Surface (Backward-Trace + Commitment-Window)
- New RNG consumers in the v29.0 delta (from 230 Consumer Index RNG-01/02 rows + 230-02 addendum):
  1. Earlybird bonus-trait roll (`_runEarlyBirdLootboxJackpot` via `_rollWinningTraits(rngWord, true)`, commit `20a951df`)
  2. BAF sentinel emission (`runBafJackpot`, commit `104b5d42`)
  3. `processFutureTicketBatch` entropy passthrough (commit `52242a10`)
  4. 17 `c2e5e0a9` entropy-mixing sites (hash2 / keccak256) — per D-07/D-08
  5. `_raritySymbolBatch` keccak-seed fix (commit `314443af`) — per D-09
- 232.1 ticket-processing impact (per D-06): Plan 01 Rev 4 `RngNotReady` selector fix at L207 + L263 changes the commitment-window boundary shape. Pre-fix the commitment window could deadlock on a wrong-selector revert; post-fix the gate opens correctly and the window narrows via the pre-drain check. The do-while integration + queue-length gate together enforce drain-before-swap structurally.
- Buffer model (per D-12): read buffer + write buffer for final ticket production. **Swap fires at RNG REQUEST TIME.** rngLocked guards (per D-11): no far-future queue writes, no active-buffer writes during the rngLocked window.

### TRNX-01 Surface (_unlockRng Removal — from 230 IM-21)
- Pre-`2471f8e7`: `advanceGame` at source line 425 called `_unlockRng(day)` in the `JACKPOT_LEVEL_CAP` branch.
- Post-`2471f8e7`: the call is REMOVED; the next downstream `_unlockRng` invocation (existing) handles the packed housekeeping step.
- Load-bearing question: what state mutations now live INSIDE the packed window that didn't before, and do any create an exploitable commitment-window widening?
- Paths per D-13: Normal / Gameover / Skip-split / Phase-transition freeze.
- Buffer-swap site per D-12: TRNX-01 plan must cite the concrete file:line where swap fires and verify it is not reachable inside the `phaseTransitionActive` branch with inconsistent pre-conditions.

### Shared Cross-Phase Evidence
- Phase 233 JKP-02 applied backward-trace + commitment-window rules to the entropy-passthrough specifically (Phase 233 D-06) — Phase 235 RNG-01/02 extends this to the milestone-wide consumer set per D-03.
- Phase 231 EBD-02 proved the earlybird bonus-trait roll is salt-space isolated from the coin jackpot (`BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS")` at `DegenerusGameJackpotModule:171`) — cross-cited by RNG-01 for the earlybird consumer per D-04.
- Phase 232.1 Plan 02 forge invariant tests (8/8 PASS at HEAD) — cross-cited by TRNX-01 + RNG-01 as structural verification of drain-before-swap + no-zero-entropy invariants.
- Phase 232.1 Plan 03 PFTB-AUDIT — CROSS-CITE source for D-09 non-zero-entropy guarantee at the 4 reachable `_processFutureTicketBatch` call sites.
- Automated-gate state at HEAD (corroborating, per Phase 230 §3.4/§3.5): `check-interfaces` PASS, `check-delegatecall` 44/44 (or 46/46 post-232.1 per 232.1 Plan 01 Rev 4 output), `check-raw-selectors` PASS, `forge build` PASS — structural baseline for Phase 235's semantic-equivalence questions.

</code_context>

<specifics>
## Specific Ideas — 5-Plan Shape

Per D-01, five plans, one per requirement. Each cites its anchor rows from `230-01-DELTA-MAP.md` + `230-02-DELTA-ADDENDUM.md` directly.

### Plan 235-01-PLAN.md — CONS-01 ETH Conservation
- **Anchor citations:** §1.1 (`_consolidatePoolsAndRewardJackpots`, `_finalizeEarlybird`), §1.2 (`_runEarlyBirdLootboxJackpot`, `runBafJackpot`), §1.3 (`claimDecimatorJackpot`), §1.4 (MintModule quest credit chain), §1.6 (`recordMint`), §2 (all pool-SSTORE-producing chains), §4 CONS-01 row.
- **Deliverable structure:** per-SSTORE catalog (`Site | File:Line | Pool | Direction | Guard | Mutation | Verdict`) + per-path algebraic proof (sum-before = sum-after at every endpoint) + 232.1 ticket-processing impact sub-section per D-06.
- **Cross-cites (re-verified at HEAD per D-04):** 231-01-AUDIT EBD-01 (`recordMint` award-block removal), 231-02-AUDIT EBD-02 (futurePool → nextPool in earlybird), 231-03-AUDIT EBD-03 (cross-commit invariant reduction to orthogonal storage namespaces), 232-01-AUDIT DCM-01 (decPool consolidated block).

### Plan 235-02-PLAN.md — CONS-02 BURNIE Conservation
- **Anchor citations:** §1.4 (MintModule quest credit chain), §1.7 (`Quests.handlePurchase`), §1.8 (`BurnieCoin.decimatorBurn`), §2 (all burn/mint chains crossing the `BurnieCoin` boundary), §4 CONS-02 row.
- **Deliverable structure:** per-mint-site catalog confirming every creation flows through `mintForGame` + per-burn-site catalog + quest credit algebra + 232.1 ticket-processing impact sub-section per D-06.
- **Cross-cites (re-verified at HEAD per D-04):** 232-01-AUDIT DCM-01 (BURNIE sum-in/sum-out handoff acceptance), 234-01-AUDIT QST-01/02/03 (`mint_ETH` quest wei, `boonPacked` exposure, `BurnieCoin` change handoff acceptance).

### Plan 235-03-PLAN.md — RNG-01 Backward Trace
- **Anchor citations:** §1.1 (entropy threading), §1.2 (earlybird bonus-trait + BAF sentinel), §1.4 (`processFutureTicketBatch` + `_raritySymbolBatch`), 230-02-ADDENDUM (17 `c2e5e0a9` sites + `314443af`), §2.3 IM-10..IM-16, §2.5 IM-22, §4 RNG-01 row.
- **Deliverable structure:** per-consumer backward-trace table (`Consumer | Site | File:Line | Commitment Point | Input Variables | Proof Word-Was-Unknown | Verdict`) covering all 5 new-consumer categories (earlybird bonus-trait + BAF sentinel + entropy passthrough + 17 c2e5e0a9 hash2/keccak sites + `_raritySymbolBatch` keccak-seed) + 232.1 ticket-processing impact sub-section per D-06.
- **Cross-cites (re-verified at HEAD per D-04):** 233-02-AUDIT JKP-02 D-06 (entropy-passthrough backward-trace), 231-02-AUDIT EBD-02 (earlybird bonus-trait salt isolation), 232.1-03-PFTB-AUDIT (non-zero entropy at `_processFutureTicketBatch` call sites per D-09).

### Plan 235-04-PLAN.md — RNG-02 Commitment Window
- **Anchor citations:** §1 (all player-controllable state reads inside new/modified RNG consumers), §2.5 IM-21 + IM-22, §3.4 + §3.5 (automated gates), 230-02-ADDENDUM per-site inputs, §4 RNG-02 row.
- **Deliverable structure:** per-consumer commitment-window enumeration table (`Consumer | Inputs | Player-Controllable? | Mutation Between Request-Fulfillment | Non-Influential Proof`) covering all 5 new-consumer categories + 232.1 ticket-processing impact sub-section per D-06.
- **Cross-cites (re-verified at HEAD per D-04):** 233-02-AUDIT JKP-02 D-06 commitment-window enumeration, 232.1 Plan 02 forge invariant tests (drain-before-swap + no-zero-entropy).

### Plan 235-05-PLAN.md — TRNX-01 Phase Transition
- **Anchor citations:** §1.1 (`advanceGame` MODIFIED by `2471f8e7`), §2.5 IM-21 (deleted `_unlockRng` call), commit `2471f8e7` rows, §4 TRNX-01 row.
- **Deliverable structure:** D-11 invariant statement restated + 4-path walk table (Normal / Gameover / Skip-split / Phase-transition freeze, each with `State-Mutations-In-Packed-Window | rngLocked-End-State | Missed-Or-Double-Unlock-Check | Buffer-Swap-Consistency`) + buffer-swap site citation per D-12 + 232.1 ticket-processing impact sub-section per D-06.
- **Cross-cites (re-verified at HEAD per D-04):** 232.1-01-FIX (pre-finalize gate + queue-length gate + game-over drain + RngNotReady selector — all live inside the packed window), 232.1-02 forge invariant tests (game-over path-isolation suite).

</specifics>

<deferred>
## Deferred Ideas

- **Regression sweep of v25.0 / v26.0 / v27.0 findings → Phase 236 REG-01/REG-02.** Phase 235 does not re-verify prior-milestone findings; that sweep is Phase 236's deliverable.
- **Findings severity classification + `F-29-NN` ID assignment → Phase 236 FIND-01/02/03.** Per D-14, Phase 235 produces candidate verdicts only.
- **Test-coverage gap remediation.** Any test gap Phase 235 discovers is documented as a candidate finding for Phase 236 routing. No `contracts/` or `test/` writes per D-17.
- **Off-chain ABI regeneration.** Phase 233 flagged the BAF event-signature widening (`uint8 → uint16` traitId) as a note. If Phase 235 RNG-01 surfaces any similar off-chain consumer gap, same routing to Phase 236.
- **Standalone gas-only phase.** Out of scope per `PROJECT.md` v29.0 out-of-scope table. Gas notes from Phase 235 audits only appear if they're finding-relevant, not as a dedicated plan.
- **Contracts unchanged since v27.0.** Audited in prior milestones; re-audit unnecessary without a delta. Phase 235 only audits the v29.0 delta surface catalogued by Phase 230 + addendum.
- **CONS-02 BurnieCoin scope breadth.** Not discussed in detail; the working scope is the union of (a) 232 DCM-01 BURNIE sum-in/sum-out handoff, (b) 234 QST-03 BURNIE supply conservation handoff, (c) any new mint site in the 232.1 fix series (expected: none). If the planner finds the scope too broad or too narrow, surface it at plan review.
- **Conservation-proof format (algebraic vs change-set table).** Not discussed in detail; defaulting to the v25.0 Phase 216 precedent (algebraic proof + flow-trace evidence). If the planner finds the DELTA audit needs a leaner per-SSTORE change-set table instead, surface at plan review.

</deferred>

---

*Phase: 235-conservation-rng-commitment-re-proof-phase-transition*
*Context gathered: 2026-04-18*
