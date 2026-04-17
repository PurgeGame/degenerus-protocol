# Phase 233: Jackpot/BAF + Entropy Audit — Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** auto (defaults locked from Phase 230 catalog + v25.0 precedent)

<domain>
## Phase Boundary

Adversarial audit of the v29.0 jackpot-side + entropy-passthrough delta surface. The phase covers exactly three requirements against a tightly-scoped slice of the 230 catalog:

- **JKP-01 — BAF `traitId=420` sentinel.** Owning commit `104b5d42`. The BAF payout paths in `DegenerusGameJackpotModule.runBafJackpot` now tag four `emit` sites (two `JackpotEthWin`, two `JackpotTicketWin`) with the new file-scope constant `uint16 private constant BAF_TRAIT_SENTINEL = 420;` instead of a literal `0`. The event `traitId` field was widened `uint8 → uint16` to fit the sentinel above the real 0-255 trait space. Audit must confirm (a) no collision with the 0-255 trait domain, (b) no downstream on-chain branch treats 420 as a real trait id, (c) event-consumer tolerance is characterised.
- **JKP-02 — Explicit entropy passthrough to `processFutureTicketBatch`.** Owning commit `52242a10`. `IDegenerusGameMintModule.processFutureTicketBatch` gained a second parameter `uint256 entropy`; the implementer removed the `uint256 entropy = rngWordCurrent;` SLOAD at the top of the function body; three call sites in `DegenerusGameAdvanceModule.advanceGame` + `_consolidatePoolsAndRewardJackpots` now thread `rngWord` forward through `_processFutureTicketBatch` → `abi.encodeWithSelector(IDegenerusGameMintModule.processFutureTicketBatch.selector, lvl, entropy)`. Audit must verify (a) the passed entropy is cryptographically equivalent to the prior `rngWordCurrent` derivation, (b) the commitment window is not widened, (c) no re-use of the same word across calls in the same transaction produces bias.
- **JKP-03 — Cross-path `bonusTraitsPacked` consistency.** The three jackpot caller sites that read `bonusTraitsPacked` (purchase-phase path, jackpot-phase path, and today's earlybird rewrite in `_runEarlyBirdLootboxJackpot`) must produce an identical 4-trait set for the same VRF word. Commit ownership is shared between `104b5d42` (BAF sentinel emission paths) and `20a951df` (earlybird trait-alignment rewrite). The earlybird rewrite is PRIMARILY owned by Phase 231 EBD-02; Phase 233 JKP-03 audits the CROSS-PATH consistency aspect only. Phase 231 EBD-02 and Phase 233 JKP-03 both cite `20a951df` for different aspects — this is expected per ROADMAP.

Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 236 (FIND-01/02/03); Phase 233 produces per-function verdicts + cross-path proofs that become the finding-candidate pool.

The Phase 230 catalog (`230-01-DELTA-MAP.md`) is the exclusive scope source. Section / row anchors listed below in `<canonical_refs>`.

</domain>

<decisions>
## Implementation Decisions

### Deliverable Shape
- **D-01 (plan count):** Three plans, one per requirement. `233-01-PLAN.md` → JKP-01 (BAF sentinel), `233-02-PLAN.md` → JKP-02 (entropy passthrough), `233-03-PLAN.md` → JKP-03 (cross-path bonus-trait consistency). Default chosen because each requirement has a distinct methodology (domain-collision sweep vs entropy-equivalence proof vs cross-path property-test), and the v25.0 Phase 214 precedent (5 plans for 5 adversarial-audit sub-surfaces) already establishes per-requirement plan granularity for audit phases. Not collapsed into a single plan because the JKP-02 commitment-window proof and the JKP-03 property-test share no reusable evidence set with the JKP-01 sentinel sweep.

### Audit Methodology
- **D-02 (verdict format):** Per-function verdict table per plan, columns `Function | Commit SHA | File:Line | Verdict | Evidence | Notes`. Mirrors v25.0 Phase 214 per-function verdict pattern. Plan 233-01 tables the four `emit` call-sites inside `runBafJackpot`; Plan 233-02 tables the three call sites in AdvanceModule (FF-promotion at `advanceGame:298-303`, near-future prep at `advanceGame:321-326`, post-transition FF at `_consolidatePoolsAndRewardJackpots:392`) plus the MintModule receiver `processFutureTicketBatch`; Plan 233-03 tables the three `bonusTraitsPacked` reader/writer sites across purchase-phase, jackpot-phase, and earlybird paths.
- **D-03 (scope-guard deferral rule):** Phase 230 catalog is READ-only (D-06 of Phase 230). If any Phase 233 plan discovers a gap that would require editing 230-01-DELTA-MAP.md, the plan records a scope-guard deferral in its own SUMMARY following the D-227-10 → D-228-09 → Phase 230 D-06 precedent rather than editing the catalog in place.

### JKP-01 Methodology (BAF sentinel)
- **D-04 (domain-collision check):** The real trait space is 0-255 by existing design (trait ids are stored/read as `uint8` in every non-event code path; the event-side widening to `uint16` is solely to carry the sentinel). 420 is therefore out-of-domain BY CONSTRUCTION — the audit's job is to confirm no downstream code path treats 420 as a real trait id, NOT to confirm 420 is outside the domain (that is a static property of the type system). Plan 233-01 enumerates every on-chain reader of an event `traitId` field + every on-chain read of `winningTraitsPacked` / `bonusTraitsPacked` and confirms each either (a) narrows to `uint8` before indexing a trait table, (b) treats the sentinel as an opaque tag, or (c) doesn't exist (off-chain indexer territory). Event-consumer tolerance (off-chain indexers, UI) is characterised as a note — the on-chain contracts MUST NOT branch on `traitId == 420` as if it were a trait.

### JKP-02 Methodology (entropy passthrough + RNG rules)
- **D-05 (entropy-equivalence proof method):** Plan 233-02 proves the passed `entropy` value is byte-identical to the value the old code would have SLOAD'd from `rngWordCurrent` at the same logical point, for every one of the three call sites. The proof is a forward-trace from the `rngWord` local in `advanceGame` / `_consolidatePoolsAndRewardJackpots` (derived from `rngGate` return) to the delegatecall payload, cross-referenced against the old SLOAD semantics from `rngWordCurrent`. Equivalence must hold at every call site; any divergence is a finding candidate.
- **D-06 (backward-trace + commitment-window rules — EXPLICIT for JKP-02):** Per user feedback (`feedback_rng_backward_trace.md` and `feedback_rng_commitment_window.md`), every RNG audit MUST (a) trace BACKWARD from each consumer to verify the VRF word was unknown at input commitment time, and (b) enumerate every player-controllable state variable that can change between VRF request and fulfillment and verify non-influential for each new consumer. Plan 233-02 applies BOTH rules explicitly to the entropy-passthrough boundary. This is NOT deferred to Phase 235 for this narrow question: Phase 235 RNG-01 / RNG-02 does the milestone-wide proof across all new RNG consumers; Phase 233 JKP-02 does the PASSTHROUGH-SPECIFIC check (entropy-in == entropy-out, no silent transformation widens the commitment window). Phase 235 will re-cite JKP-02's evidence via `§2.5 IM-22` in the 230 catalog when it builds its milestone-wide proof.
- **D-07 (no re-use bias check):** Plan 233-02 also verifies that when the same `rngWord` is passed to multiple consumers within the same transaction (e.g. FF-promotion call + near-future prep in the same `advanceGame` invocation), no bias is introduced by the shared seed. Documented via a salt-space / domain-separation audit of each consumer's use of `entropy`.

### JKP-03 Methodology (cross-path property)
- **D-08 (cross-path property):** For the same VRF word, the three call sites that read `bonusTraitsPacked` must derive the identical 4-trait set. Plan 233-03 enumerates the three sites from `230-01-DELTA-MAP.md §2.3` (IM-14 coin-jackpot bonus roll path via `runBafJackpot` caller chain, IM-15 the BAF emit path, IM-16 `_runEarlyBirdLootboxJackpot` → `_rollWinningTraits(rngWord, true)`) and the purchase-phase reader path surfaced by the 20a951df rewrite. For each, the trait-derivation is traced back to a shared helper (`JackpotBucketLib.unpackWinningTraits` / `_rollWinningTraits`) called with the same `(rngWord, true)` flag. Any divergence — different salt, different flag, different bit unpacking — is a finding candidate.
- **D-09 (overlap with Phase 231 EBD-02):** Commit `20a951df` is PRIMARILY owned by Phase 231 EBD-02 (the trait-alignment rewrite itself: parity, salt isolation, fixed-level queueing, futurePool→nextPool conservation). Phase 233 JKP-03 cites `20a951df` for a DIFFERENT aspect: cross-path consistency (three paths, same VRF word → same 4-trait set). SHA-sharing is expected and correct per ROADMAP; the aspects are non-overlapping. Plan 233-03 does not re-audit EBD-02's aspects and does not block on Phase 231.

### Interface / Scope Classification
- **D-10 (selector signature bump classification):** The `IDegenerusGameModules.IDegenerusGameMintModule.processFutureTicketBatch` parameter-list change (gained `uint256 entropy`) is recorded as `ID-103 PASS` in 230-01 §3.3.f — interface and implementer moved in lockstep in commit 52242a10. Phase 233 JKP-02 audits the SEMANTIC equivalence of the new selector's entropy argument; the PURE INTERFACE DRIFT question (does the declaration match the implementation at HEAD?) is already PASS'd in §3 and does not need re-verification. Phase 233 cites ID-103 once as evidence that the interface-drift subquestion is closed and focuses all remaining analysis on the semantic passthrough.

### Findings Discipline
- **D-11 (no finding IDs emitted):** Phase 233 does NOT emit `F-29-NN` finding IDs. Plans produce per-function verdicts + cross-path proofs that become the finding-candidate pool. Phase 236 (FIND-01/02/03) owns ID assignment, severity classification, and consolidation into `audit/FINDINGS-v29.0.md`. Every verdict Phase 233 produces cites commit SHA + file:line so Phase 236 can anchor without re-discovery.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 230 catalog (exclusive scope source per D-03)
- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md`
  - `§1.2` DegenerusGameJackpotModule — `_runEarlyBirdLootboxJackpot` MODIFIED by `20a951df`, `runBafJackpot` MODIFIED by `104b5d42`, event widenings + `BAF_TRAIT_SENTINEL` constant declaration
  - `§1.1` DegenerusGameAdvanceModule — `advanceGame` MODIFIED by `52242a10` (FF-promotion + near-future prep call sites), `_processFutureTicketBatch` / `_prepareFutureTickets` signature bumps, `_consolidatePoolsAndRewardJackpots` MODIFIED
  - `§1.4` DegenerusGameMintModule — `processFutureTicketBatch` MODIFIED by `52242a10` (signature + SLOAD removal)
  - `§1.11` IDegenerusGameModules — `IDegenerusGameMintModule.processFutureTicketBatch` signature bump
  - `§2.3` Jackpot/BAF/Entropy-related chains — IM-10 through IM-16 (the seven Phase 233 consumer rows)
  - `§2.5` IM-22 — the entropy-commitment boundary replay row (shared with Phase 235 RNG-01/02)
  - `§3.3.f ID-103` — interface-drift PASS for `processFutureTicketBatch(uint24 lvl, uint256 entropy)` selector
  - `§3.3.c ID-84` — interface-drift PASS for `runBafJackpot` (body MODIFIED, signature unchanged)
  - `§4` Consumer Index — JKP-01, JKP-02, JKP-03 rows pointing to exactly the above sections
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — Phase 230 deliverables snapshot + "Handoff to Phases 231-236" block naming Phase 233 consumers

### Milestone scope
- `.planning/REQUIREMENTS.md` — JKP-01 / JKP-02 / JKP-03 definitions (§"Adversarial Audit — Jackpot/BAF + Entropy")
- `.planning/ROADMAP.md` — Phase 233 block (Goal, `Depends on: Phase 230`, 4 Success Criteria)
- `.planning/PROJECT.md` — Current Milestone section (v29.0 in-scope commits list)

### Methodology precedent
- `.planning/milestones/v25.0-phases/214-adversarial-audit/` — per-function verdict table pattern; 5-plan / 5-sub-surface structure informing D-01
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — RNG commitment-window audit style; 215-02-BACKWARD-TRACE.md and 215-03-COMMITMENT-WINDOW.md are the direct templates for JKP-02's D-06 backward-trace + commitment-window application
- `.planning/phases/230-delta-extraction-scope-map/230-CONTEXT.md` — CONTEXT.md shape mirrored here

### User-feedback rules applied
- `feedback_rng_backward_trace.md` — backward trace from every RNG consumer (applied in D-06)
- `feedback_rng_commitment_window.md` — player-controllable state between VRF request and fulfillment (applied in D-06)
- `feedback_skip_research_test_phases.md` — obvious audit phase; no standalone research plan

</canonical_refs>

<code_context>
## Existing Code Insights (from Phase 230 Consumer Index)

Bulleted observations drawn from `230-01-DELTA-MAP.md §4` Consumer Index rows JKP-01, JKP-02, JKP-03:

- **JKP-01 surface (per §4 row):** §1.2 `runBafJackpot` MODIFIED body + widened events + new `BAF_TRAIT_SENTINEL = 420` file-scope constant; §2.3 IM-14 (self-call from `_consolidatePoolsAndRewardJackpots` to `DegenerusGame.runBafJackpot`) + IM-15 (delegatecall from Game wrapper to module implementer). Consumer intent: no collision with real trait IDs (0-255 domain), event consumers tolerate sentinel, no downstream logic treats 420 as a real trait.
- **JKP-02 surface (per §4 row):** §1.4 `processFutureTicketBatch` MODIFIED (signature + SLOAD removal); §1.1 `_processFutureTicketBatch` / `_prepareFutureTickets` / `advanceGame` MODIFIED; §1.11 interface signature bump; §3.3.f ID-103 interface-drift PASS; §2.3 IM-10 / IM-11 / IM-12 / IM-13 (three caller-side rows + the delegatecall selector boundary); §2.5 IM-22 (the entropy-commitment-boundary replay row for Phase 235 cross-reference). Consumer intent: cryptographic equivalence to prior `rngWordCurrent` SLOAD derivation, no commitment-window widening, no intra-transaction re-use bias.
- **JKP-03 surface (per §4 row):** §1.2 `_runEarlyBirdLootboxJackpot` + all jackpot-side `bonusTraitsPacked` readers/writers; §2.3 IM-14 / IM-15 / IM-16 (all bonus-trait chains). Consumer intent: every jackpot caller using `bonusTraitsPacked` produces an identical 4-trait set for the same VRF word across purchase-phase, jackpot-phase, and earlybird paths.
- **Shared-SHA note:** `20a951df` appears in both the Phase 231 scope (EBD-02 trait-alignment rewrite itself) and the Phase 233 scope (JKP-03 cross-path consistency). The ROADMAP explicitly permits shared-SHA citation across phases when aspects differ — Phase 231 audits the rewrite's correctness; Phase 233 audits that the rewritten path agrees with the other two paths on output given the same input.
- **Event-surface side effect:** The `104b5d42` event widening `uint8 traitId → uint16 traitId` on `JackpotEthWin` + `JackpotTicketWin` changes the event signature hash. Topic encoding is unchanged (32 bytes regardless of declared width). Off-chain ABI consumers must regenerate — flagged in §1.2 non-function declarations block, not a Phase 233 on-chain finding but a note for Phase 236 / indexer team.
- **Automated-gate state (from §3.4/§3.5 at HEAD `e5b4f974`):** `make check-interfaces` PASS, `make check-delegatecall` PASS (44/44), `make check-raw-selectors` PASS, `forge build` PASS. No drift entered via the 10-commit delta; Phase 233's semantic-equivalence question starts from a clean structural baseline.

</code_context>

<specifics>
## Specific Ideas — 3-Plan Shape

Per D-01, three plans. Each cites its anchor rows directly from `230-01-DELTA-MAP.md`.

### Plan 233-01-PLAN.md — JKP-01 BAF `traitId=420` Sentinel
- **Anchor citations:** `§1.2` (runBafJackpot body + events + BAF_TRAIT_SENTINEL constant); `§2.3 IM-14` + `IM-15`; `§3.3.c ID-84`; §4 JKP-01 row. Commit `104b5d42`.
- **Per-function verdict table:** four `emit` call-sites inside `runBafJackpot` (two `JackpotEthWin`, two `JackpotTicketWin`); one verdict per call-site confirming the 420 sentinel is passed, no payout-math change, no CEI shift. Plus a domain-collision sweep covering every on-chain reader of `traitId` event fields or `bonusTraitsPacked` / `winningTraitsPacked` storage — each reader checked for `uint8` narrowing / opaque-tag treatment / non-existence.
- **Output:** per-function verdict table + domain-collision sweep table + one-paragraph event-consumer note (off-chain ABI regeneration required; not an on-chain finding).

### Plan 233-02-PLAN.md — JKP-02 Explicit Entropy Passthrough
- **Anchor citations:** `§1.1` (advanceGame + _processFutureTicketBatch + _prepareFutureTickets + _consolidatePoolsAndRewardJackpots call sites); `§1.4` (MintModule processFutureTicketBatch body + SLOAD removal); `§1.11` (interface signature bump); `§2.3 IM-10` / `IM-11` / `IM-12` / `IM-13`; `§2.5 IM-22`; `§3.3.f ID-103`; §4 JKP-02 row. Commit `52242a10`.
- **Per-function verdict table:** four call-site rows (AdvanceModule × 3 caller sites + MintModule receiver) plus the delegatecall boundary row. Each verdict proves D-05 equivalence (passed `entropy` == what the old code would have SLOAD'd from `rngWordCurrent` at the same logical point) and D-07 no-re-use-bias (shared-seed salt-space analysis).
- **D-06 explicit application:** a dedicated sub-section applies the backward-trace rule (VRF word unknown at input commitment time) and the commitment-window rule (player-controllable state between VRF request and fulfillment enumerated and verified non-influential) to the passthrough. This is the PASSTHROUGH-specific check; Phase 235 RNG-01/02 does the milestone-wide proof and will re-cite this plan.
- **Output:** per-function verdict table + backward-trace sub-section + commitment-window enumeration table + no-re-use-bias note.

### Plan 233-03-PLAN.md — JKP-03 Cross-Path `bonusTraitsPacked` Consistency
- **Anchor citations:** `§1.2` (`_runEarlyBirdLootboxJackpot` rewrite + all jackpot-side `bonusTraitsPacked` readers/writers); `§2.3 IM-14` + `IM-15` + `IM-16`; §4 JKP-03 row. Shared SHAs: `104b5d42` (BAF emit path), `20a951df` (earlybird rewrite — different aspect per D-09).
- **Property-test-style audit:** enumerate the three call sites that read `bonusTraitsPacked` (purchase-phase path surfaced by 20a951df, jackpot-phase coin-jackpot path via `_rollWinningTraits(rngWord, true)`, earlybird path via the rewritten `_runEarlyBirdLootboxJackpot`). Prove each call site derives the 4-trait set via the same helper (`JackpotBucketLib.unpackWinningTraits` / `_rollWinningTraits`) with identical `(rngWord, true)` arguments. Any divergence (different salt, different flag, different bit-unpacking order) is a finding candidate.
- **D-09 overlap note:** Plan includes an explicit "Non-overlap with Phase 231 EBD-02" paragraph stating Phase 231 audits the rewrite's internal correctness (parity, salt isolation, fixed-level queueing, budget conservation); Phase 233 audits the cross-path agreement. The two phases cite the same SHA for non-overlapping aspects.
- **Output:** cross-path derivation table (3 sites × columns `Path | File:Line | Helper | Salt Arguments | Flag | Verdict`) + D-09 overlap disclosure paragraph.

</specifics>

<deferred>
## Deferred Ideas

- **Milestone-wide RNG proof → Phase 235 RNG-01 / RNG-02.** The full enumeration of every new RNG consumer in the v29.0 delta (earlybird bonus-trait roll, BAF sentinel emission, entropy passthrough, phase-transition `_unlockRng` removal) with a unified backward-trace + commitment-window proof is Phase 235's job. Phase 233 JKP-02 does the passthrough-specific slice; Phase 235 re-cites JKP-02's evidence via §2.5 IM-22.
- **Pool conservation proof → Phase 235 CONS-01.** Any SSTORE-side effects of the BAF payout paths or the earlybird `_runEarlyBirdLootboxJackpot` rewrite (futurePool → nextPool, claimablePool deltas) are catalogued by Phase 235 CONS-01. Phase 233 JKP-03 verifies the trait-set property; it does NOT re-audit the budget algebra.
- **Findings consolidation + `F-29-NN` ID assignment → Phase 236 FIND-01 / FIND-02 / FIND-03.** Per D-11, Phase 233 produces candidate verdicts only. Phase 236 severity-classifies, assigns stable IDs, updates KNOWN-ISSUES, and publishes the executive summary table.
- **Regression sweep against v25.0 / v26.0 / v27.0 RNG findings → Phase 236 REG-01 / REG-02.** Phase 233 does not re-verify prior-milestone findings; that sweep is Phase 236's deliverable.
- **Off-chain event-consumer ABI regeneration.** Flagged in JKP-01 as a note (event-signature-hash change from `uint8 → uint16` traitId widening). Off-chain / indexer / UI migration is out of scope for the on-chain audit; tagged as a Phase 236 candidate note if anyone picks it up.
- **`boonPacked` interface-completeness gap.** §3.1 note in 230-01 flags that the auto-generated `boonPacked(address)` getter is not declared on `IDegenerusGame.sol`. That question belongs to Phase 234 QST-02 (and possibly Phase 236 as an INFO finding), not Phase 233.

</deferred>

---

*Phase: 233-jackpot-baf-entropy-audit*
*Context gathered: 2026-04-17*
