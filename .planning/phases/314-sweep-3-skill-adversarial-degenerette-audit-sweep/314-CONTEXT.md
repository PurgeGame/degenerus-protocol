# Phase 314: SWEEP — 3-Skill Adversarial + Degenerette Audit (SWEEP) - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning

<domain>
## Phase Boundary

An **audit-only adversarial verification pass** over the v45.0 contract changes — no new
capability, no design. The pass:

1. **Red-teams the landed VRF-rotation fix** (`a303ae18` — `updateVrfCoordinatorAndSub` detect-
   preserve-re-issue, `_setVrfConfig` / `_requestVrfWord` helpers) — SWP-01.
2. **Composition-tests the consolidated delta surfaces** — V-081 `9bcd582d`, jackpot pending-pool
   `6e5acd7e` + regression `f3e21064`, degenerette `92b110bf` — for any cross-surface or differential
   attack — SWP-02.
3. **Audits the degenerette refactor** (`92b110bf`) — DGAUD-01..04.

**Roster (LOCKED, carried forward — not reopened):** `/contract-auditor` + `/zero-day-hunter` +
`/economic-analyst` per `D-302-INVOKE-01`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`;
`/economic-analyst` IN per `D-271-ADVERSARIAL-03`. Two-tier consensus per `D-302-CONSENSUS-01`
(Tier 1 any-skill FINDING_CANDIDATE → AskUserQuestion PAUSE; Tier 2 3-of-3 → auto-elevate +
RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01`). Skeptic-reviewer filter per
`feedback_skeptic_pass_before_catastrophe` BEFORE any user-pause.

**Output:** 1 AGENT-COMMITTED `.planning/phases/314-*/314-01-ADVERSARIAL-LOG.md` (CHARGE +
per-skill dispositions + integrated disposition section, **incl. the degenerette audit folded in** —
see D-04). **Zero `contracts/` + zero `test/` mutation** during Phase 314 unless a Tier-1 user-
approved or Tier-2 auto-elevated FINDING_CANDIDATE triggers a RE-PASS (any RE-PASS contract diff is
USER-APPROVED + batched per `feedback_no_contract_commits` / `feedback_batch_contract_approval` /
`feedback_never_preapprove_contracts`; `feedback_pause_at_contract_phase_boundaries` applies —
confirm direction at this sensitive-contract boundary even with auto_advance ON).

**Posture:** lean **verification-formality** with full disposition enumeration, expecting
unanimous-NEGATIVE like v42 P296 / v43 P302 / v44 P307. The genuinely-new surface is the VRF re-issue
contract code; everything else is re-attestation of already-landed deltas.

</domain>

<decisions>
## Implementation Decisions

> Most of this phase is locked by milestone-level decisions (above). The decisions below are the
> phase-specific gray areas resolved in this discussion. Anchor convention: D-NN.

### SWP-01 — Re-issue red-team vectors (the new VRF contract surface)

- **D-01 (LINK-funding order = SPOT-CHECK, not deep trace):** The re-issue fires
  `requestRandomWords` on the NEW coordinator BEFORE LINK lands; the diff comment asserts
  DegenerusAdmin funds it atomically in the same `_executeSwap` tx (`transferAndCall`), and VER-01
  was resolved at IMPL. The red-team **confirms DegenerusAdmin funds same-tx and records
  SAFE_BY_DESIGN** — it does NOT perform a deep cross-contract `_executeSwap` trace. The documented
  rationale carries it; `retryLootboxRng` is the standing failsafe if the new coordinator stalls.

- **D-02 (daily/mid-day exclusivity = red-team DISCRETION):** The branch is
  `if (LR_MID_DAY) {re-issue mid-day} else if (rngLockedFlag) {re-issue daily if rngWordCurrent==0}`
  — mid-day wins, so a daily re-issue is skipped when `LR_MID_DAY` is set (VER-03 exclusivity is the
  load-bearing assumption). The red-team gives this a **standalone hypothesis row** ("can both flags
  be set so a daily word is silently dropped → permanent post-rotation freeze?") **only if** tracing
  the `LR_MID_DAY` / `rngLockedFlag` set-clear sites shows it warrants one; otherwise it folds into
  the general freeze-invariant disposition. Treat the invariant as attackable, not assumed
  (`feedback_verify_call_graph_against_source`).

- **D-03 (rotation-spam = SAFE_BY_DESIGN row, kept):** `updateVrfCoordinatorAndSub` is ADMIN-only
  (`:1717` `if (msg.sender != ContractAddresses.ADMIN) revert E();`) and admin rotation is freeze-
  EXEMPT (`v45-vrf-freeze-invariant`), so player-driven rotation-spam is structurally impossible.
  **Keep the ROADMAP "rotation-spam griefing" line as an explicit SAFE_BY_DESIGN disposition row**
  (admin-gated + freeze-exempt) — enumerate-everything precedent (v44 P307's 72-row table). Do NOT
  drop it.

### SWP-01 — VRF-04 omission (the dropped wireVrf init-lock)

- **D-04 (drop the stale charge line; KEEP the call-graph re-proof):** The landed fix `a303ae18`
  **intentionally omitted** the `wireVrf` init-only lock (SPEC D-03 / VRF-04), user-approved, on the
  claim that `wireVrf` is reachable only from the DegenerusAdmin constructor. So the ROADMAP SWP-01
  charge line *"a `wireVrf`-lock that breaks a legitimate ops path"* is **stale and is dropped — there
  is no lock to break.** The red-team instead **re-proves the "wireVrf is constructor-only-reachable"
  call-graph claim** (mandatory regardless per `feedback_verify_call_graph_against_source` — "by
  construction" claims are exactly what gets attacked), recorded as a SWP-01 SAFE_BY_DESIGN/NEGATIVE
  disposition row.

### DGAUD-01..04 — Degenerette refactor audit

- **D-05 (placement = FOLD into `/contract-auditor`, not a separate track):** DGAUD-01..04 are charged
  **into the `/contract-auditor` skill's scope alongside SWP-02** with a single integrated disposition
  table. The degenerette coverage becomes a **section of `314-01-ADVERSARIAL-LOG.md`, NOT a separate
  `degenerette-audit-note` file** — a deliberate deviation from the ROADMAP wave-shape phrase
  "+ degenerette-audit-note bundle".

- **D-06 (DGAUD-03 bar = VIABLE-IN-PRINCIPLE):** Confirm `BetPlaced(player indexed, index indexed,
  betId indexed, packed)` still fires on every ETH bet path carrying **player + amount** (`packed`
  holds the 128-bit amount; `player` is indexed). The removed `topDegeneretteByLevel` was keyed by
  **game level**, and only the lootbox `index` (not `level`) is in the event — the **index→level
  derivation is an ACCEPTED off-chain-indexer convention, NOT a finding**. Do not escalate the
  level-recoverability gap to a FINDING_CANDIDATE; it is the user's own off-chain-leaderboard design.

- **D-07 (DGAUD-02 bar = BEHAVIORAL identity, not literal bytes):** The ROADMAP says
  `dailyHeroWagers` "byte-identical", but `92b110bf` de-indented the block and dropped the enclosing
  `{}` scope when it removed the sibling per-player/per-level block. Attest **semantic/behavioral
  identity** — the day / heroSymbol / wagerUnit / pack-unpack SSTORE computation is unchanged
  (whitespace + scope-brace removal only). This is what the diff shows; literal byte-identity would
  spuriously "fail".

- **D-08 (DGAUD-01 + DGAUD-04 = deterministic):** DGAUD-01 — `forge build` recompile-clean +
  storage-slot-shift safe (dangling-ref grep already returns **ZERO** for
  `playerDegeneretteEthWagered` / `topDegeneretteByLevel` / `getPlayerDegeneretteWager` /
  `getTopDegenerette`). DGAUD-04 — re-verify HANDOFF-01/02/03 (S-02 `dailyHeroWagers`) + HANDOFF-18
  (V-031 prizePool degenerette-bet) + HANDOFF-81 (V-142 `degeneretteBets`) + HANDOFF-82 (V-147
  `prizePoolPendingPacked` frozen-branch) against the refactored module; expected disposition: the
  refactor surface does not intersect these anchors (`dailyHeroWagers` / prizePool / pending all
  untouched), so dispositions carry forward.

### SWP-02 — Composition pass (carried verbatim from ROADMAP)

- **D-09:** Cross-surface composition across V-081 allocation/packing (`9bcd582d`), jackpot pending-
  pool obligations (`6e5acd7e` + `f3e21064`), and degenerette removal (`92b110bf`) — any differential
  behaviour or cross-surface attack an attacker can game. No special framing chosen; standard
  enumerate-and-dispose. (User did not select this area for deep-dive; ROADMAP charge is sufficient.)

### Invocation mechanics

- **D-10 (SEQUENTIAL_MAIN_CONTEXT-direct, PARALLEL only if Task truly available):** Plan
  SEQUENTIAL_MAIN_CONTEXT as the primary path — every prior SWEEP (v42 P296 / v43 P302 / v44 P307)
  fell back to it because the executor invocation context lacked the Task tool. Attempt
  PARALLEL_SUBAGENT only if the executor genuinely has Task; persona fidelity preserved via dedicated
  per-skill MD files with the verbatim CHARGE either way (HYBRID-fallback acceptable per ROADMAP SC-2).

### Claude's Discretion

- **D-02** explicitly delegates the daily/mid-day exclusivity standalone-row decision to the red-team
  after it traces the flag set/clear sites.
- Exact disposition-table layout, per-skill MD structure, and CHARGE wording — planner/executor
  discretion, matching the v44 P307 artifact bundle shape.
- Whether SWP-02 surfaces any beyond-charge hypotheses (economic-analyst MEV/coordination angles) —
  skill discretion, subject to the skeptic filter before any pause.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### Phase scope + requirements (read first)
- `.planning/ROADMAP.md` §Phase 314 — the SWP-01..02 + DGAUD-01..04 verbatim charges, 5 success
  criteria, depends-on (312 IMPL + 313 TST), and wave shape (1 AGENT-COMMITTED `314-01-ADVERSARIAL-
  LOG.md`). NOTE the SWP-01 "wireVrf-lock" line is stale per D-04; the "+ degenerette-audit-note
  bundle" wave phrase is superseded by D-05 (folded into the LOG).
- `.planning/REQUIREMENTS.md` — SWP-01..02 (lines ~84-85), DGAUD-01..04 (lines ~61-64), DELTA-04
  (degenerette delta, cross-refs DGAUD), and the Traceability rows mapping these to Phase 314/315.
- `.planning/STATE.md` — milestone v45.0 status; baseline `MILESTONE_V44_AT_HEAD_6f0ba296…`.

### The landed contract surfaces under audit (the red-team / DGAUD subjects)
- Commit `a303ae18` — **VRF-rotation fix** (`fix(312-01)`): the detect-preserve-re-issue rework of
  `updateVrfCoordinatorAndSub`, the `_setVrfConfig` (internal) + `_requestVrfWord` (private) helpers,
  and the documented VRF-04 omission rationale (constructor-only-reachable). SWP-01 primary subject.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `updateVrfCoordinatorAndSub` (the re-issue +
  branch precedence `LR_MID_DAY` → `rngLockedFlag`/`rngWordCurrent==0`), `wireVrf` (`:503` ADMIN guard;
  the constructor-only-reachable claim D-04 re-proves), `_setVrfConfig`, `_requestVrfWord`,
  `rawFulfillRandomWords` (`:1761` requestId/word guard; `:1768` daily / `:1772` mid-day branches),
  `retryLootboxRng` (failsafe + LINK precheck), `_backfillOrphanedLootboxIndices`.
- `contracts/DegenerusAdmin.sol` `_executeSwap` (`addConsumer :894` → `updateVrf :901` →
  `transferAndCall :907-912`) — the same-tx LINK funding D-01 spot-checks.
- Commit `92b110bf` — **degenerette refactor**: removed `playerDegeneretteEthWagered` +
  `topDegeneretteByLevel` mappings + their per-bet SSTOREs + `getPlayerDegeneretteWager` /
  `getTopDegenerette` views (+ interface decls); `dailyHeroWagers` untouched. DGAUD subject.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `_placeDegeneretteBet` (`dailyHeroWagers`
  write at ~`:489-497`; `BetPlaced` emit at `:480`), `event BetPlaced` (`:69`, fields for DGAUD-03).
- Commits `9bcd582d` (V-081 EV-cap), `6e5acd7e` (jackpot pending-pool yield-surplus obligations),
  `f3e21064` (jackpot regression) — SWP-02 composition delta surfaces.

### Locked design + prior-phase context the red-team validates against
- `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` — the locked VRF design +
  §0 grep-verified call-graph manifest (the claims the red-team re-proves), §3 freeze disposition.
- `.planning/phases/312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl/312-CONTEXT.md`
  — D-06/D-07/D-08 code-org decisions, VER-01..04 (LINK order, `rngWordCurrent!=0`, daily/mid-day
  exclusivity, pre-patch re-grep) and the wireVrf reachability reasoning behind D-04.

### §9d backlog anchors (closed/re-verified by this milestone)
- `audit/FINDINGS-v44.0.md` §9d.2 — HANDOFF-78/85/87/89/91 (freeze), HANDOFF-86/88/90 (wireVrf lock).
- `audit/FINDINGS-v44.0.md` §9d.4 — ADMA-01 (`wireVrf` seal), ADMA-02 (`updateVrfCoordinatorAndSub`
  vault-routed reach).
- `audit/FINDINGS-v44.0.md` §9d — HANDOFF-01/02/03 (S-02 `dailyHeroWagers`), HANDOFF-18 (V-031),
  HANDOFF-81 (V-142 `degeneretteBets`), HANDOFF-82 (V-147 `prizePoolPendingPacked`) — DGAUD-04 re-verify set.

### Memory / methodology (must apply)
- `feedback_skeptic_pass_before_catastrophe` — structural-protection check + 3-condition EV lens
  BEFORE any Tier-1 user-pause.
- `feedback_verify_call_graph_against_source` — re-grep every cited line; "by construction" claims
  (the wireVrf reachability per D-04) must be adversarially re-proven, not asserted.
- `feedback_security_over_gas`, `feedback_pause_at_contract_phase_boundaries`,
  `feedback_no_contract_commits` / `feedback_batch_contract_approval` /
  `feedback_never_preapprove_contracts` — govern any RE-PASS contract diff.
- `v45-vrf-freeze-invariant` — admin rotation EXEMPT, consumed-this-cycle word is the fresh re-issued
  one, old word abandoned via `:1761` guard (grounds D-03 + the freeze re-break disposition).
- `project_rnglock_audit_disposition` — §9d anchors are a maximalist catalog, NOT live player vectors;
  disposition rigor without over-framing.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Prior SWEEP precedent** (v42 P296 / v43 P302 / v44 P307) — the artifact bundle shape (CHARGE +
  per-skill MD + integrated LOG + disposition table) and the HYBRID→SEQUENTIAL_MAIN_CONTEXT fallback
  are established; reuse the structure. v44 P307 was 72/72 disposition rows, unanimous-NEGATIVE.
- **Skill MDs** — `/contract-auditor`, `/zero-day-hunter`, `/economic-analyst` exist as project skills;
  invoke per the locked roster. DGAUD-01..04 fold into the `/contract-auditor` charge (D-05).

### Established Patterns
- `updateVrfCoordinatorAndSub` and `wireVrf` are both ADMIN-gated (`ContractAddresses.ADMIN`). The
  re-issue is freeze-safe via the `:1761` `requestId`/`rngWordCurrent` guard (old word abandoned).
- `BetPlaced.packed` is the canonical packed-bet layout (amount @ `FT_AMOUNT_SHIFT`, 128 bits;
  index @ `FT_INDEX_SHIFT`, 32 bits) — the off-chain reconstruction substrate for DGAUD-03 (D-06).
- Degenerette dangling-ref grep is already clean (ZERO matches) — DGAUD-03 first-half + DGAUD-01
  dangling check are pre-confirmed; the audit re-attests rather than discovers.

### Integration Points
- This is an audit phase: it READS `contracts/` + git history, WRITES only `.planning/phases/314-*/`.
  A finding that survives the skeptic filter is the ONLY path to a `contracts/`/`test/` touch (RE-PASS,
  USER-APPROVED batched diff).

</code_context>

<specifics>
## Specific Ideas

- The user's posture throughout this discussion was **lean / verification-formality**: accept
  documented rationales (D-01 LINK-order spot-check), document structural protections as SAFE_BY_DESIGN
  rather than hunt them exhaustively (D-03 rotation-spam), and accept the off-chain-leaderboard design
  as a convention rather than escalate the level-recoverability gap to a finding (D-06). This mirrors
  the prior unanimous-NEGATIVE SWEEPs — the bar is rigorous full enumeration, not adversarial
  over-reach.
- Two ROADMAP-charge mismatches were caught and resolved here so the planner inherits clean charges:
  the stale `wireVrf-lock` SWP-01 line (D-04) and the "byte-identical" DGAUD-02 phrasing (D-07).

</specifics>

<deferred>
## Deferred Ideas

- **Deep cross-contract `_executeSwap` LINK-funding trace** — considered (D-01) and DEFERRED to a
  spot-check; the same-tx funding rationale is documented and VER-01 was resolved at IMPL. Revisit only
  if the spot-check surfaces an anomaly.
- **Escalating the degenerette per-level (`index→level`) off-chain reconstruction gap to a
  FINDING_CANDIDATE** — considered (D-06) and DECLINED; it is the user's accepted off-chain-indexer
  convention, not a defect.
- **The ~115 non-VRF v44 backlog anchors** (HANDOFF-01..77 less the DGAUD-04 re-verify set, 79..110,
  118..119; ADMA-03..22; ADMA-ERRATUM-01) — stay deferred in `audit/FINDINGS-v44.0.md` §9d for a future
  milestone per `.planning/REQUIREMENTS.md`. Out of scope for Phase 314.
- **Phase 315 TERMINAL consolidate-forward delta audit + closure** (DELTA-01..04 + AUDIT-01 + REG-01 +
  CLS-01) — the next phase consumes Phase 314's §4 adversarial disposition; not this phase.

</deferred>

---

*Phase: 314-sweep-3-skill-adversarial-degenerette-audit-sweep*
*Context gathered: 2026-05-23*
