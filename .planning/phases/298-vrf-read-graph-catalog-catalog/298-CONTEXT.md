# Phase 298: VRF Read-Graph Catalog (CATALOG) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Pure-analysis catalog phase that backward-traces from every VRF-derived-entropy consumer site (every read of `randomness` / `rngWord` / every keccak/xorshift chain rooted at the VRF word) per `feedback_rng_backward_trace.md`. For each consumer, walks every reachable SLOAD inside the resolution code path with explicit file:line enumeration per `feedback_verify_call_graph_against_source.md` (no "by construction" / "covered by single fn" claims; Phase 294 BURNIE gap precedent). For each unique participating slot identified, enumerates every external/public function (game-action writers + ERC20/ERC721 inherited writers + admin/owner writers + affiliate writers + anything reachable from a non-internal entry point) that writes it. Produces per-(slot × writer × callsite) verdict table with classification `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` per the v43.0 milestone goal's 3 explicit exempt entry points. Per VIOLATION row recommends ONE remediation tactic from the menu (gated-revert / snapshot-anchor / pre-lock reorder / immutable) + 1-line rationale. Catalog completeness gate independently grep-sweeps `contracts/` to attest no participating slot or writer is missed. Output: `.planning/RNGLOCK-CATALOG.md` artifact + cross-reference entry in `audit/FINDINGS-v43.0.md` §3 at the terminal phase. Wave shape: 1 AGENT-COMMITTED catalog artifact. **Zero `contracts/` + zero `test/` mutations.** Requirements CAT-01..06 (6).

</domain>

<decisions>
## Implementation Decisions

### Consumer Enumeration Scope (CAT-01)

- **D-298-CONSUMER-LIST-01:** **Locked verbatim 13-entry VRF-consumer trace-root list.** CAT-01 backward-trace starts from each of these entries; entries are listed in execution-order for the 13 parallel sub-agents per D-298-EXEC-SHAPE-01:
  1. `JackpotModule.payDailyJackpot` (`contracts/modules/DegenerusGameJackpotModule.sol:339`) — daily ETH/whalepass distribution (Phase 287 JPSURF prior coverage)
  2. `JackpotModule.payDailyJackpotCoinAndTickets` (`:596`) — daily coin/tickets distribution
  3. `JackpotModule.runTerminalJackpot` (`:278`) — game-over ETH terminal jackpot
  4. `DecimatorModule.runTerminalDecimatorJackpot` (`contracts/modules/DegenerusGameDecimatorModule.sol:755`) — game-over decimator terminal
  5. `GameOverModule` rngWordByDay substitution path (`contracts/modules/DegenerusGameGameOverModule.sol:100`) — game-over RNG-substitution
  6. `LootboxModule.resolveRedemptionLootbox` (`contracts/modules/DegenerusGameLootboxModule.sol:707`) — auto-resolved lootbox roll
  7. `LootboxModule._resolveLootboxCommon` / `_resolveLootboxRoll` (`:960` / `:1623`) — manual-path lootbox roll
  8. `DegeneretteModule._resolveLootboxDirect` (`contracts/modules/DegenerusGameDegeneretteModule.sol:797`) + inline degenerette consumer at `:594`
  9. `AdvanceModule.retryLootboxRng` (`contracts/modules/DegenerusGameAdvanceModule.sol:1132`) — failsafe; classified EXEMPT-RETRYLOOTBOXRNG per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A
  10. `MintModule` trait-generation consumer (Phase 290 MINTCLN audit-subject surface — 3-input keccak with owed-in-baseKey)
  11. `BurnieCoinflip._resolveFlip` (`contracts/BurnieCoinflip.sol:807`) — BURNIE coin-flip resolution + `:837` `(rngWord & 1)` win-decode
  12. `StakedDegenerusStonk.resolveRedemptionPeriod` (`contracts/StakedDegenerusStonk.sol:585`) + `:670` `rngWordForDay(claimPeriodIndex)` redemption entropy consumer
  13. `DecimatorModule._awardDecimatorLootbox` callsite cluster (`contracts/modules/DegenerusGameDecimatorModule.sol:573` rngWord param consumer + `:771` `decClaimRounds[lvl].rngWord` cross-call re-read)

  **Why:** v43.0 milestone goal explicitly precludes SAFE_BY_DESIGN dispositions for participating slots; the consumer list must be exhaustive. Terminal-jackpot + game-over substitution paths (entries 3, 4, 5) are IN SCOPE despite EXC-01..03 KI-envelope NEGATIVE-scope carry — the freeze invariant applies regardless of the prior milestone's catastrophy-class disposition. BURNIE coinflip (11) + sStonk redemption (12) + decimator (13) extend coverage beyond Phase 287 JPSURF's jackpot-only scope. **How to apply:** Plan-phase 298 authors a Task per consumer-entry; each Task dispatches a sub-agent rooted at that consumer entry per `D-298-EXEC-SHAPE-01`. Catalog sections §1..§13 in the output artifact mirror this list 1:1.

- **D-298-TRACE-DEPTH-01:** **All-source contracts in scope; stops only at no-source external interfaces.** Backward trace walks transitively into every contract under `contracts/` (top-level + `contracts/modules/` + `contracts/libraries/` + `contracts/storage/`). Stops only at external interfaces with no source available (Chainlink VRF coordinator, external oracle mocks). SLOADs inside `IVault.depositXxx`, `IBurnieCoinflip.*`, `IStakedDegenerusStonk.*`, `IBurnieCoin.*`, `IGNRUS.*` are enumerated alongside in-module SLOADs whenever reached from a consumer's resolution path. Cross-module call boundary is NOT a trace stop — the call graph is followed across every Solidity contract under `contracts/`. **Why:** v43.0 milestone goal `Every VRF Input Frozen at Commitment` reads literally: every SLOAD reached during resolution is a potential participation site; module-boundary stops risk missing the F-41-02/03-class cross-module read/write races + Phase 296 SWEEP composition-attack hypothesis class. Maximally aggressive coverage matches `feedback_rng_window_storage_read_freshness.md` discipline. **How to apply:** Per-consumer sub-agent's prompt explicitly states "trace walks into every source contract under `contracts/`; stop only at external interfaces with no source available." Sub-agent enumerates every SLOAD reached with file:line citation regardless of which contract under `contracts/` it lives in.

- **D-298-SLOT-CLASSIFICATION-01:** **Two-tier slot classification: enumerate all SLOADs in CAT-02; classify only participating subset in CAT-04 verdict matrix.** Every SLOAD reached during resolution per `feedback_rng_window_storage_read_freshness.md` is enumerated in the per-consumer SLOAD table (CAT-02). Non-participating SLOADs (those whose values do NOT influence any VRF-derived output — e.g., `claimablePool` SLOAD inside `_addClaimableEth` for accounting; `yieldAccumulator` for yield obligation calc) are listed with `NON-PARTICIPATING` flag + 1-line attestation explaining why the value drives no VRF output. Participating SLOADs proceed to CAT-03 writer enumeration + CAT-04 verdict-matrix classification. **Why:** `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent demands every SLOAD enumerated (non-VRF reads consumed alongside RNG are a distinct bug class); the milestone goal targets `slots that participate in deriving VRF-influenced output` — narrower than `every SLOAD in resolution`. Two-tier preserves both: full enumeration discipline (no F-41-02/03-class blindness) + verdict-matrix scope alignment with milestone goal (avoids false-positive VIOLATION on every accounting aggregate). Phase 287 JPSURF format precedent (`Load-bearing for winner-selection?` column). **How to apply:** Per-consumer SLOAD table has columns: `Slot | Read-site (file:line) | Read context | Participating? (YES/NO) | Attestation if NO`. Verdict matrix CAT-04 omits NON-PARTICIPATING rows; per-slot writer enumeration CAT-03 is only run on participating slots.

### EXEMPT-ADVANCEGAME Reach (CAT-04)

- **D-298-EXEMPT-REACH-01:** **Stack-rooted strict + per-call-site classification.** Writer function F is `EXEMPT-ADVANCEGAME` IFF the specific call site C is reachable as a static call-graph descendant of `advanceGame()` AND originates from the VRF-callback-driven resolution stack. The SAME function F can be classified `EXEMPT-ADVANCEGAME` at one callsite + `VIOLATION` at another callsite if a separate external entry point also reaches F. Verdict table is per-(slot × writer × callsite), not per-(slot × writer). **Why:** Phase 287 JPSURF dealt with this for `_creditClaimable` (advanceGame-stack-reached, writes `claimableWinnings`) vs `claimWinnings` (EOA-reached, also writes `claimableWinnings`). Strict + per-callsite captures the dual-entry-point risk explicitly; the literal CAT-04 text reads `every non-exempt writer = VIOLATION. No discretionary classifications` — per-callsite ensures the non-exempt entry point of a shared internal helper is classified VIOLATION even if other callsites of the same helper are EXEMPT. **How to apply:** CAT-04 verdict-matrix rows are keyed on `(slot, writer-function, callsite-file-line)` tuples. Per-consumer sub-agent enumerates every callsite of each writer of each participating slot it touches; main-context integration dedupes the writer-function set + cross-classifies per callsite during verdict-matrix authoring.

- **D-298-EXEMPT-CROSSCONTRACT-01:** **Cross-contract EXEMPT preserved when callsite traces to EXEMPT stack.** A writer callsite C in contract Y reached from contract X's `advanceGame()`-rooted resolution stack is classified `EXEMPT-ADVANCEGAME` provided Y's source is under `contracts/` (no source = trace stop per `D-298-TRACE-DEPTH-01`; opaque external = NOT counted as a writer). The static call graph is followed across contract boundaries; the EXEMPT classification follows the call-graph descendancy regardless of which contract the writer lives in. Cross-contract verdict rows are NOT dual-classified by default — the per-callsite locked in `D-298-EXEMPT-REACH-01` captures any non-EXEMPT entry point of the same writer at a separate callsite row. **Why:** Cross-contract EXEMPT must propagate or the JackpotModule → IVault.depositXxx (and similar) callstacks are spuriously flagged VIOLATION on every callsite — defeating the purpose of explicit EXEMPT classification. The dual-entry-point risk is already captured via per-callsite under `D-298-EXEMPT-REACH-01`. **How to apply:** Verdict-matrix authoring rule: walk the static call graph from advanceGame (and from VRF callback + from retryLootboxRng); every writer callsite reached gets `EXEMPT-{ADVANCEGAME|VRFCALLBACK|RETRYLOOTBOXRNG}` (whichever stack reached it); writer callsites NOT reached from any of the 3 EXEMPT stacks get `VIOLATION`.

### Catalog Artifact Structure (CAT-05)

- **D-298-CATALOG-LAYOUT-01:** **Per-consumer + per-slot + verdict-matrix layout** [Claude's-discretion default per user `You decide` 2026-05-18]. `.planning/RNGLOCK-CATALOG.md` section structure:
  - §0 — Executive Summary (metrics: # consumers, # participating slots, # writers enumerated, # VIOLATION rows, # EXEMPT rows by class; headline + top-line recommendation if any structural pattern is visible)
  - §1..§13 — One section per VRF consumer (entry function file:line + traced call-set list + per-consumer SLOAD table with `Slot | Read-site (file:line) | Read context | Participating? (YES/NO) | Attestation if NO`)
  - §14 — Unique-slot index (deduplicated participating-slot list with backref columns: which consumers §1..§13 SLOAD this slot)
  - §15 — Per-slot writer enumeration (each unique participating slot → every external/public writer function reached, per-callsite, with file:line)
  - §16 — (slot × writer × callsite) verdict matrix sorted by slot; columns: `Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification | Recommended tactic | Rationale`
  - §17 — CAT-06 completeness-gate attestation (each grep pattern → hit count → cross-reference to catalog rows or deliberate-exclusion attestation; per `D-298-GREP-GATE-01`)

  **Why:** Per-consumer sections preserve trace-context for each VRF-derived-output surface (matches Phase 287 JPSURF precedent at scaled-up granularity); unique-slot index + verdict matrix enable Phase 299 FIX sub-phase planning to iterate VIOLATIONs directly (one sub-phase per VIOLATION row or per-slot grouping per planner discretion). Single mega-table or per-module organization were considered + rejected because (a) per-consumer trace context is load-bearing for understanding WHY each SLOAD is reached + (b) per-module loses cross-module dependency visibility that the verdict-matrix needs. **How to apply:** Main-context integration agent authors §0 + §14 + §15 + §16 + §17 after collecting per-consumer §1..§13 outputs from the 13 sub-agents.

- **D-298-RECOMMEND-DEPTH-01:** **ONE recommended tactic per VIOLATION row + 1-line rationale.** Each VIOLATION row in §16 verdict matrix gets a single recommended tactic from the menu `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + 1-line rationale citing design intent or cross-callsite consequence. Phase 287 JPSURF §0 R2-snapshot precedent (one-line "eliminates ALL cross-call re-derivation, not just hero-override branch; zero new storage slot"). No ranked-menu A>B>C>D + pros/cons table; no design-intent backward-cite line by default (Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline at plan-phase time). **Why:** Slimmer artifact; matches Phase 287 §0 precedent; the user has the final call at each FIX sub-phase approval per `feedback_never_preapprove_contracts.md`. Ranked-menu was considered + rejected for trade-off paralysis risk at sub-phase planning. **How to apply:** Verdict-matrix `Recommended tactic` column = single letter `(a|b|c|d)`; `Rationale` column = ≤ 80 chars.

### Agent Execution Shape

- **D-298-EXEC-SHAPE-01:** **13 parallel sub-agents per consumer + main-context integration.** Plan-phase authors 13 sub-agent dispatch Tasks (one per VRF consumer per `D-298-CONSUMER-LIST-01`), each producing that consumer's CAT-02 SLOAD list + CAT-03 contributing writer set (per-participating-slot writers reached from THAT consumer's resolution stack). Main-context integration agent then: (i) dedupes the cross-consumer participating-slot set into §14 unique-slot index; (ii) merges per-consumer writer enumerations into §15 per-slot writer table (cross-consumer writer set per slot); (iii) authors §16 verdict matrix applying `D-298-EXEMPT-REACH-01` + `D-298-EXEMPT-CROSSCONTRACT-01` classification rules per-callsite; (iv) runs §17 CAT-06 grep-gate self-attestation per `D-298-GREP-GATE-01`; (v) authors §0 executive summary. Per-consumer sub-agent prompt mandates explicit file:line citations per `feedback_verify_call_graph_against_source.md` (no "by construction" / "covered by single fn" claims; Phase 294 BURNIE gap precedent). **Why:** ~13× wall-clock speedup vs main-context end-to-end (Phase 287 precedent at scaled scope); per-agent context isolated to one consumer's resolution path keeps the file:line-enumeration discipline tractable. Cross-consumer slot deduplication + verdict-matrix authoring benefit from main-context full-catalog visibility (preserves the integration step that the per-module-decomposition option would scatter across module boundaries). **How to apply:** Plan-phase Task layout: Task 1 = author per-consumer sub-agent prompt template (explicit-enumeration discipline; output schema); Tasks 2..14 = dispatch 13 sub-agents in parallel via single-message multi-Task block (one per consumer; identical prompt with consumer-specific anchor); Task 15 = main-context integration (§0 + §14 + §15 + §16 + §17 authoring); Task 16 = CAT-06 grep-gate self-attestation; Task 17 = AGENT-COMMIT catalog artifact bundle + STATE.md update.

- **D-298-GREP-GATE-01:** **Main-context self-attestation for CAT-06.** After per-consumer sub-agents complete + main-context integration drafts the catalog through §16, main-context runs the 5 CAT-06 grep patterns AS A FRESH SWEEP (not relying on sub-agent outputs):
  1. `grep -rn "function .*external" contracts/ --include="*.sol"`
  2. `grep -rn "function .*public" contracts/ --include="*.sol"`
  3. `grep -rn "slot:" contracts/ --include="*.sol"` (inline assembly slot directives)
  4. `grep -rn "assembly { sstore" contracts/ --include="*.sol"` (inline assembly raw sstore)
  5. Every storage variable declaration sweep — grep `^\s*(mapping|uint|int|address|bool|bytes|struct)\s.*;` per top-level + per-module contract file
  Each pattern's hit count + per-hit cross-reference to a catalog row (or deliberate-exclusion attestation if the hit is structurally not a writer of any participating slot, e.g., a pure view function under `function .*external`). Recorded in §17. **Why:** Same-agent grep is `independent` in the sense that it's a fresh sweep with the literal CAT-06 patterns, NOT relying on the per-consumer sub-agent enumeration that produced §1..§13. The integrating main-context agent is the natural site for cross-deduplication + completeness attestation. Independent-verification-sub-agent option was considered + rejected per cost-vs-coverage trade-off (the per-consumer sub-agent decomposition already provides one layer of independence; main-context self-attestation provides the second). **How to apply:** Plan-phase Task 16 = run all 5 grep patterns + author §17 attestation + cross-reference every hit to a catalog row OR a deliberate-exclusion attestation; integrating-main-context agent owns the gate.

### Claude's Discretion (planner & executor latitude)

The following gray areas inherit prior-phase defaults; planner uses these without re-asking the user:

- **D-298-WAVE-SHAPE-01 — Single AGENT-COMMITTED catalog artifact bundle.** REQUIREMENTS CAT-NN + ROADMAP Phase 298 entry both lock wave shape: 1 AGENT-COMMITTED commit shipping `.planning/RNGLOCK-CATALOG.md`. Zero `contracts/` + zero `test/` mutations BY DEFAULT (Phase 298 is analysis-only). Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`: if any FIX-class contract change emerges as an obvious mid-catalog correction, it gets surfaced for explicit user approval + becomes a Phase 299 sub-phase, NOT pre-approved or folded into Phase 298. Plan-phase 298 finalizes the artifact bundle commit message.

- **D-298-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Per `feedback_skip_research_test_phases.md` lineage. Phase 298 methodology is locked by CONTEXT.md (this file) + REQUIREMENTS CAT-01..06 + prior-milestone feedback memory (`feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` + `feedback_rng_window_storage_read_freshness.md` + `feedback_verify_call_graph_against_source.md`). No research-agent needed; plan-phase authors the per-consumer sub-agent prompt template + Task layout directly.

- **D-298-KI-01 — KNOWN-ISSUES.md UNMODIFIED.** Mirrors v40+ default-zero-promotion path. Phase 303 TERMINAL handles KNOWN-ISSUES.md disposition per `D-43N-KI-NN` lock (deferred to plan-phase 303). Phase 298 default: catalog artifact does NOT modify KNOWN-ISSUES.md.

- **D-298-SUB-AGENT-PROMPT-01 — Per-consumer sub-agent prompt template (planner finalizes).** Template skeleton (planner refines language + adds per-consumer anchor):
  ```
  Task: Backward-trace VRF-derived entropy from {CONSUMER_ENTRY_FN} at {FILE:LINE}. Walk every reachable SLOAD inside the resolution code path with EXPLICIT file:line citation (per feedback_verify_call_graph_against_source.md — NO "by construction" / "covered by single fn" claims). Trace walks into every source contract under contracts/; stops only at external interfaces with no source available.
  Output structure:
    §A — Traced function set (every internal/external function reached transitively from entry)
    §B — SLOAD table: Slot | Read-site (file:line) | Read context | Participating? (YES/NO) | Attestation if NO
    §C — For each PARTICIPATING slot in §B: enumerate every external/public function (in any contract under contracts/) that writes this slot, with callsite file:line; include OZ-inherited writers (transfer/transferFrom/approve/_mint/_burn) where applicable.
  Read-only: do NOT modify contracts/ or test/. Output to .planning/phases/298-*/298-consumer-NN-{slug}.md.
  ```
  Plan-phase 298 finalizes wording + per-consumer anchor substitution + sub-agent-type selection (Explore vs general-purpose vs Plan).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 298 Anchors
- `.planning/ROADMAP.md` — Phase 298 entry (6 success criteria; CAT-01..06 verbatim; wave shape 1 AGENT-COMMITTED catalog artifact; zero `contracts/` + `test/` mutations; **READ:** lines 28-41 + the v43.0 milestone goal prose above the `<details>` block at lines 30-32)
- `.planning/REQUIREMENTS.md` — CAT-01..06 verbatim (lines 27-32); FIX-01..05 envelope (lines 36+) for downstream consumption context; phase-numbering note at line 135 (Phase 299 envelope may expand into 299a/299b/... after CATALOG output)
- `.planning/PROJECT.md` — v43.0 milestone goal: `Every VRF Input Frozen at Commitment`; 3 explicit exempt entry points (advanceGame() + VRF coordinator callback + retryLootboxRng() per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A)
- `.planning/STATE.md` — Phase 298 next-position marker (lines 23-30); v42.0 closure HEAD `81d7c94bc924edb3429f6dc16ee33280fc11c7c2` (audit baseline)

### Methodology Feedback Memory (load-bearing for trace discipline)
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_window_storage_read_freshness.md` — enumerate ALL SLOADs inside rng-window, not just VRF-derived seeds (F-41-02/03 precedent)
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_verify_call_graph_against_source.md` — explicit grep-verified enumeration; no "by construction" / "single fn reaches all paths" claims (Phase 294 BURNIE gap precedent)
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md` — trace original design intent + actor game-theory before any deletion/restructure (applies to remediation-tactic selection at Phase 299 FIX sub-phase planning, NOT to Phase 298 catalog authoring per `D-298-RECOMMEND-DEPTH-01`)
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md` — NEVER commit contracts/ or test/ changes without explicit user approval (applies even though Phase 298 is analysis-only — guards mid-catalog accidental edits)
- `/home/zak/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_skip_research_test_phases.md` — skip research-agent dispatch for mechanical phases (`D-298-RESEARCH-AGENT-01` carry)

### Prior-Phase Catalog Precedent (load-bearing for shape inheritance)
- `.planning/milestones/v41.0-phases/287-jackpot-influence-surface-closure-jpsurf/287-01-JPSURF-AUDIT.md` — Phase 287 JPSURF audit deliverable: §0 executive summary + §1 jackpot READ-SET catalog (27 SLOADs with `Load-bearing for winner-selection?` column) + §2 mutator-set enumeration + §3 (slot × function) verdict table + §4 follow-up residuals + §5 closure recommendation. Phase 298 catalog layout (`D-298-CATALOG-LAYOUT-01`) scales this format from 2-consumer to 13-consumer scope.
- `.planning/milestones/v41.0-phases/287-jackpot-influence-surface-closure-jpsurf/287-01-SUMMARY.md` — Phase 287 closure narrative + 3 residuals flagged (F-41-03 candidate + N-5 boundary-race + N-9 COMPRESSED-mode partial); precedent for the closure recommendation pattern in §0.

### v42.0 Surface-Phase Carry-Forward Artifacts (referenced by CAT-01 consumer entries)

**MINTCLN (Phase 290, consumer entry 10):**
- `.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-CONTEXT.md` — MINTCLN-01..10 decisions; 3-input keccak + owed-in-baseKey collapse; `D-42N-EVT-BREAK-01`
- `.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — owed-in-baseKey design rationale

**HRROLL (Phase 292, sub-consumer of entry 1/2):**
- `.planning/milestones/v42.0-phases/292-hero-override-weighted-roll-hrroll/292-CONTEXT.md` — ×1.5 leader-bonus + bit-slice non-collision; `D-292-HRROLL-*`
- `.planning/milestones/v42.0-phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` — leader-bonus + rngLocked window design

**DPNERF (Phase 294, sub-consumer of entry 1/2):**
- `.planning/milestones/v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-CONTEXT.md` — `D-294-CALLER-UNIFORM-01` + BURNIE gap-closure (Phase 298 must enumerate both ETH + BURNIE callsites for hero-override-derived slot writes per the BURNIE gap precedent)

**RETRY_LOOTBOX_RNG (Phase 296, consumer entry 9):**
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md` — Phase 296 SWEEP integrated `retryLootboxRng` as 4th audit-subject surface; `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A locks EXEMPT-RETRYLOOTBOXRNG as a verdict class

**Cross-call seed-separation (Phase 281, applies to entries 1/2/10):**
- `.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-CONTEXT.md` — owed-salt 4th-keccak-input invariant; collapsed into baseKey low 32 bits at Phase 290 MINTCLN; participating-slot read-set candidate
- `.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`

**Day-index snapshot (Phase 288, applies to entries 1/2):**
- `.planning/milestones/v41.0-phases/288-hero-override-day-index-snapshot-fix-fix-jpsurf/` — `dailyIdx` structural snapshot at lock-time; precedent for tactic (b) snapshot/anchor pattern in remediation menu

### Source Anchors for Consumer Entry List (D-298-CONSUMER-LIST-01)
- `contracts/modules/DegenerusGameJackpotModule.sol` — entries 1, 2, 3 (lines 278, 339, 596; `_rollHeroSymbol` at 1639; `_awardJackpotTickets` at 2194 are sub-consumers reached transitively)
- `contracts/modules/DegenerusGameDecimatorModule.sol` — entries 4, 13 (lines 755, 573; `decClaimRounds[lvl].rngWord` re-read at 771)
- `contracts/modules/DegenerusGameGameOverModule.sol` — entry 5 (lines 98-100; `rngWordByDay[day]` substitution path at 100)
- `contracts/modules/DegenerusGameLootboxModule.sol` — entries 6, 7 (lines 707, 960, 1623)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — entry 8 (lines 594, 797)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — entry 9 (`retryLootboxRng` at 1132; classified EXEMPT-RETRYLOOTBOXRNG)
- `contracts/modules/DegenerusGameMintModule.sol` — entry 10 (Phase 290 MINTCLN audit-subject surface; `cachedJpFlag && rngLockedFlag` gate at 1221 is part of the consumer's resolution path)
- `contracts/BurnieCoinflip.sol` — entry 11 (lines 807, 837)
- `contracts/StakedDegenerusStonk.sol` — entry 12 (lines 585, 670; `game.rngWordForDay(claimPeriodIndex)` re-read)

### Phase 299 FIX Sub-Phase Handoff Anchors (forward-cite only)
- ROADMAP Phase 299 entry — envelope phase; sub-phase count + numbering determined by CATALOG output (`.planning/RNGLOCK-CATALOG.md` §16 VIOLATION-row count). Phase 299 plan-phase consumes the verdict matrix to determine sub-phase shape (one sub-phase per VIOLATION OR per-slot grouping per planner discretion).
- ROADMAP Phase 300 entry — ADMIN/owner path lockdown depends on Phase 298 CAT-03 writer table to identify which admin functions write participating slots.
- ROADMAP Phase 301 entry — FUZZ harness depends on CAT-01 consumer surface enumeration for ≥1-fuzz-case-per-consumer coverage attestation.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 287 JPSURF audit format** — `.planning/milestones/v41.0-phases/287-jackpot-influence-surface-closure-jpsurf/287-01-JPSURF-AUDIT.md` provides the table column structure, the `Load-bearing for winner-selection?` participating-flag column, and the §0 + §1 + §2 + §3 section organization that `D-298-CATALOG-LAYOUT-01` scales up.
- **rngLockedFlag gate at writer-callsite** — Phase 290 MINTCLN already implements this pattern at `DegenerusGameMintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag) {...}`). Tactic (a) `gated-revert` recommendations in the verdict matrix reference this implementation pattern.
- **snapshot/anchor pattern (Phase 281 owed-salt + Phase 288 dailyIdx)** — pre-existing precedents for tactic (b) recommendations; verdict-matrix `Rationale` column cites the relevant precedent in ≤80 chars.

### Established Patterns
- **3 EXEMPT entry-point classes** — `advanceGame()` + VRF coordinator callback + `retryLootboxRng()`. Locked by v43.0 milestone goal prose; downstream verdict-matrix classification labels mirror this 3-class set verbatim.
- **AGENT-COMMIT artifact bundle for analysis-only phases** — Phase 287 JPSURF + Phase 283 SWEEP + Phase 296 SWEEP precedent. Phase 298 follows: single AGENT-COMMIT shipping `.planning/RNGLOCK-CATALOG.md` + the 13 per-consumer sub-agent output files at `.planning/phases/298-*/298-consumer-NN-{slug}.md` + the planning artifacts (this CONTEXT.md + PLAN.md + DISCUSSION-LOG.md).
- **Per-consumer sub-agent file naming convention** — `.planning/phases/298-*/298-consumer-{NN}-{slug}.md` where `NN` is the consumer-list ordinal (01..13) per `D-298-CONSUMER-LIST-01` and `slug` is a kebab-case mnemonic (e.g., `298-consumer-01-pay-daily-jackpot.md`, `298-consumer-09-retry-lootbox-rng.md`).

### Integration Points
- **Phase 299 FIX envelope expansion** — `.planning/RNGLOCK-CATALOG.md` §16 verdict matrix is the load-bearing input for Phase 299 sub-phase count + numbering. ROADMAP line 53 + REQUIREMENTS line 135 both flag this dependency.
- **Phase 300 ADMIN lockdown** — depends on CAT-03 writer-enumeration column to identify which admin/owner functions write participating slots; ROADMAP Phase 300 dependency note at line 45.
- **Phase 301 FUZZ harness coverage attestation** — depends on CAT-01 consumer surface enumeration (one fuzz case per consumer per FUZZ-04); ROADMAP Phase 301 dependency note at line 47.
- **Phase 303 TERMINAL FINDINGS-v43.0.md §3 cross-reference** — catalog artifact gets a §3 entry in the terminal-phase findings deliverable per CAT-05 + the v43.0 milestone closure pattern.

</code_context>

<specifics>
## Specific Ideas

- **Phase 287 JPSURF format scaled up** — the user has authored / commissioned this exact catalog shape before (Phase 287 audit subject was jackpot-only 27 SLOADs). Phase 298 scales the same shape to all-VRF-consumer scope. Catalog layout decisions inherit Phase 287 column structure + table cell density.
- **13 parallel sub-agents per consumer** — execution-shape decision favors parallel decomposition over Phase 287 main-context-end-to-end because Phase 298 scope is ~5–10× Phase 287; the per-consumer sub-agent isolation matches `feedback_verify_call_graph_against_source.md` discipline (each sub-agent owns its consumer's explicit-enumeration commitment).
- **Per-callsite verdict-matrix granularity** — explicit choice over per-(slot × writer-function) coarse to capture the dual-entry-point risk (shared internal helper reached from both EXEMPT and non-EXEMPT ancestors); Phase 287 implicit pattern made explicit at the v43 catalog granularity.

</specifics>

<deferred>
## Deferred Ideas

- **Independent-verification sub-agent for CAT-06 grep gate** — considered + rejected per `D-298-GREP-GATE-01` cost-vs-coverage trade-off. If a future milestone surfaces a CAT-06 false-negative (a missed writer caught at FIX time), revisit by adding the 14th independent-verification sub-agent.
- **Ranked-menu A>B>C>D remediation recommendation** — considered + rejected per `D-298-RECOMMEND-DEPTH-01`. If Phase 299 sub-phase planning struggles with tactic-selection on multiple violations, revisit by enriching the §16 verdict-matrix rationale column at a future catalog refresh.
- **Per-module organization for catalog layout** — considered + rejected per `D-298-CATALOG-LAYOUT-01`. Cross-module dependency visibility favors the per-consumer + per-slot + verdict-matrix layout.
- **Pre-existing snapshotted slots (Phase 281 owed-salt, Phase 288 dailyIdx) catalog treatment** — NOT explicitly locked. Default treatment: include in catalog with `Participating? = YES` + writer enumeration shows the snapshot/anchor pattern + verdict-matrix classifies the snapshot-time write as EXEMPT-ADVANCEGAME (or VIOLATION-IF-ANY) per the same rules. Plan-phase may surface this for explicit attestation if the catalog hits such a slot.
- **Pre-deployment writers (constructor / initializer)** — NOT explicitly locked. Default treatment: included in CAT-03 writer enumeration if reachable from non-internal entry points; classified separately as `EXEMPT-CONSTRUCTOR` or absorbed into VIOLATION-vs-EXEMPT classification per static call-graph analysis. Plan-phase may surface for explicit attestation.

</deferred>

---

*Phase: 298-VRF-Read-Graph-Catalog-CATALOG*
*Context gathered: 2026-05-18*
