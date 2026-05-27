# Phase 333: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure - Context

**Gathered:** 2026-05-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the v49.0 milestone (Unified Keeper Router + Bounty Recalibration + AfKing Keeper
Sweep). Four requirements, no contract mutation:

1. **SWEEP-01** — run the 3-skill genuine-PARALLEL adversarial sweep against the FROZEN v49
   subject, charged with the v49-novel surfaces (advance-timing MEV / same-tx bundling, bounty
   economics, faucet-drain on the unified router, the unrewarded-advance liveness backstop),
   every elevation through the skeptic dual-gate.
2. **SWEEP-02** — delta-audit NON-WIDENING vs the v48.0 baseline `0cc5d10f`; every `contracts/`
   + `test/` diff attributable to a v49 work item across the blast radius.
3. **SWEEP-03** — author `audit/FINDINGS-v49.0.md` (9-section, mirroring v44/v46/v47/v48,
   chmod 444), folding the delta-audit (§3/§5) + the sweep disposition (§4).
4. **BATCH-03** — the closure flip: re-attest all 36 v49.0 requirements, emit
   `MILESTONE_V49_AT_HEAD_<sha>`, apply the atomic 5-doc flip (ROADMAP + STATE + MILESTONES +
   PROJECT + REQUIREMENTS) under a single blocking `autonomous:false` USER gate.

**Posture:** DOC-ONLY phase. ZERO `contracts/*.sol` edits — the audit subject is FROZEN
(see D-08). The sweep + delta read the frozen subject READ-ONLY; the FINDINGS + closure flip
touch only `audit/` + `.planning/`. If the sweep surfaces a contract defect it is NOT patched
here — it is surfaced to the USER closure gate for adjudication (any fix = a NEW contract phase
needing USER approval). **Nothing is pushed.** This is the 4th repetition of the v44/v46/v47/v48
TERMINAL pattern — the mechanics below are precedent-locked; the v49-specific judgment is in
`<decisions>`.

</domain>

<decisions>
## Implementation Decisions

> **The USER delegated this phase to Claude's judgment** ("use your judgement"). Every decision
> below is resolved from the v44→v48 TERMINAL precedent + the v49-specific context (the 332 carry-
> forwards, the 329-SPEC invariants, the redesign blast radius). None require re-asking.

### Adversarial sweep charge (SWEEP-01)
- **D-01 (charge weighting by v49-novelty — the unified router is the new surface):** the 3-skill
  charge is weighted toward what v49 actually *changed*, not a uniform re-sweep:
  - **TIER-A (deepest probing) — advance-timing MEV / same-tx bundling.** The unified `doWork()`
    can consume the advance-leg (which requests/reveals RNG) and route to autoBuy/autoOpen, and a
    caller can bundle `advanceGame` + buy/open in one bundle/tx. `/zero-day-hunter` is **explicitly
    charged with Pitfall 3 (same-tx bundling of advance-consume + buy/open)** per SC1. Question: can
    ordering/sandwiching the advance-consume capture the freshly-revealed RNG or the bounty? The
    structural defense is invariant (b) frozen-advance-consume (ADV-04), proven empirically by
    TST-01 — the sweep re-attests it adversarially.
  - **TIER-A — bounty economics (`/economic-analyst` lead): stall-multiplier abuse + bounty-stacking
    + faucet self-crank on the unified surface.** Can the 1/2/4/6 stall multiplier be gamed (induce
    an artificial stall to harvest a fat advance bounty)? Can two categories be credited in one tx
    (NO — invariant (a) one-category early-return + the single `creditFlip` CEI-last, proven by
    TST-02 D-02; the sweep re-attests structurally)? Does re-homing the advance bounty into `doWork`
    + the flat-per-tx D-07 peg reopen the faucet self-crank that the 331 gas-weighted autoOpen
    budget closed?
  - **TIER-B (re-attest, do NOT hunt) — composed reentrancy (router→game→`creditFlip`).**
    `/zero-day-hunter` is **explicitly charged with Pitfall 6** per SC1, BUT the disposition is the
    USER's locked 332 stance ([[v49-keeper-router-redesign]] D-01): *"reentrancy is not an issue,
    nothing here pays ETH and this only interacts with trusted contracts."* No ETH push, every
    external call targets a pinned `ContractAddresses.*`, the single `creditFlip` is CEI-last after
    the one-category early-return. Record as **SAFE_BY_DESIGN / structural attestation**, NOT an
    active attacker harness.
  - **TIER-B — unrewarded-advance liveness backstop.** Invariant (c) free-fallback callers (the
    30-min permissionless bypass `AdvanceModule:1012`, `DegenerusVault.gameAdvance():527`,
    `StakedDegenerusStonk.gameAdvance():421`, the ~120-day death-clock `:109`/`:1199-1200`/`:1898`)
    are intact under autoBuy-first ordering. Re-attest that re-homing the bounty removed NO
    structural caller (329-SPEC invariant (c) / D-04a).
- **D-02 (topology + dual-gate — precedent-locked, restated for the planner):** genuine
  **PARALLEL_SUBAGENT**, run **INLINE in the main orchestrator context** (which holds the
  Task/Agent tool) so all 3 skills launch as concurrent background spawns — NOT nested inside a
  `gsd-executor` (which lacks Task → forces the HYBRID/SEQUENTIAL fallback). This is the hard-won
  314/324/328 lesson. `/degen-skeptic` is **OUT** (D-271-ADVERSARIAL-02); the skeptic FUNCTION is
  the mandatory **dual-gate** applied to every elevation: (1) structural-protection lens, (2)
  3-condition EV lens (manifests without an attacker / material magnitude / survives the re-read).
  Each subagent probes the FROZEN subject via `git show <sha>:contracts/...` (not from memory),
  READ-ONLY, every cited `file:line` re-grep-verified against the frozen SHA.

### Findings verdict posture (SWEEP-03)
- **D-03 (target `0 NEW_FINDINGS`, but a genuine hunt):** the working target is the v45/v48
  clean-closure outcome (`0 NEW_FINDINGS`, KNOWN_ISSUES_UNMODIFIED) — but the sweep is a real hunt,
  ready to surface and defer. The `0 NEW_FINDINGS` clause is amended ONLY by a FINDING_CANDIDATE
  that survives the dual-gate.
- **D-04 (default disposition leaning if a MEDIUM+ survives = DEFER→v50, fix design locked):** the
  v46→v47 / v47→v48 precedent. The subject is FROZEN, so the terminal NEVER halt-and-fixes — a fix
  is a NEW contract phase needing USER approval. A surviving FINDING_CANDIDATE is recorded in the
  adversarial log + FINDINGS §4, surfaced to the **USER closure gate** (D-07), where the USER makes
  the actual call: **DEFER→v50** (default leaning, with the fix design locked) / **FIX-as-new-phase**
  (closure HALTS, a new contract phase is planned) / **ACCEPT_AS_DOCUMENTED**.
- **D-05 (informational/advisory ≠ finding, NO stop):** a sub-finding / advisory (the class of the
  v48 SWAP cash-share doc-drift, USER-accepted ≤60% canonical) is RECORDED in the log + FINDINGS but
  is NOT a finding and does NOT amend the verdict or stop closure. The **v48 SWAP cash-share advisory
  is carried-forward-unmodified** verbatim (SC2).

### Delta-audit attestations (SWEEP-02)
- **D-06 (go beyond bare NON-WIDENING — re-attest the structural spine):** the FINDINGS §3 (delta)
  / §5 attest, not just the diff-attribution table, but the structural invariants that survived the
  redesign:
  - **Blast-radius attribution table** — every `contracts/` + `test/` diff vs `0cc5d10f` → a v49
    work item: AfKing router/`_autoBuy`/re-peg/micro-opt (`63bc16ca` + the 331 `4c9f9d9b` GAS split),
    AdvanceModule bounty-removal + `advanceGame(uint8 mult)` return-shape, DegenerusGame wrapper +
    discovery views (`advanceDue()`/`boxesPending()`/`keeperSnapshot()`) + the MintModule
    nested-mapping pointer, the interface updates, and the `test/` de-crank renames + the 17
    reward-rehoming deletions (cite `test/REGRESSION-BASELINE-v49.md` as authoritative — see D-09).
  - **The 4 structural invariants (329-SPEC §2)** re-attested intact at the closure HEAD, cross-ref'd
    to their empirical proofs: (a) one-category early-return [TST-02], (b) frozen advance-consume
    [ADV-04 / TST-01], (c) guaranteed free-fallback caller [D-04a], (d) single day-start epoch
    SATISFIED-BY-DELETION [GAS-03 / autoBuy stall ladder deleted].
  - **The OPEN-E 4-protection BLOCKING re-attestation (GASOPT-05).** GASOPT-05 dropped the
    per-iteration `isOperatorApproved` (`:676`) and kept the subscribe-time gate (`:401`). The sweep
    MUST re-attest the **4 OPEN-E structural protections** (consent-gate-at-subscribe / default-self
    byte-identical / no-escalation / trust-the-sub temporal bound) as a HARD blocking condition
    before closure, per [[open-e-operator-approval-trust-boundary]] + the ROADMAP coverage note.
  - **VRF/RNG-freeze INTACT under the router composition** (the v45 north-star
    [[v45-vrf-freeze-invariant]]; ADV-04 / TST-01) — no in-window SLOAD introduced by the unified
    same-tx path.
- **D-08 (frozen-subject anchor CONFIRMED):** the v49 audit subject = the contract diff `63bc16ca`
  (the 330 batched router/advance redesign) + `4c9f9d9b` (the 331 GAS calibration of `AfKing.sol` +
  `DegenerusGame.sol`). **The subject is FROZEN at `4c9f9d9b`** — `git diff 4c9f9d9b HEAD --
  contracts/*.sol` is EMPTY (verified 2026-05-27; 331/332 since then are doc + test only). The
  delta-audit baseline is `0cc5d10f` (the v48.0 closure HEAD). Re-verify `git diff 4c9f9d9b HEAD --
  contracts/` empty before the closure commit (T-CONTRACTS guard).
- **D-09 (regression ledger numbers — cite the ledger, don't hardcode):** `forge test` at the v49
  TST HEAD = **666 passed / 42 failed / 17 skipped**; the 42-failing set **== the v48.0 §2 union BY
  NAME** (net-zero new regression); **17 reward-rehoming reds DELETED** + 5 `Crank*`→`Keeper*`
  renames. `test/REGRESSION-BASELINE-v49.md` is AUTHORITATIVE (note: the 332-CONTEXT pre-execution
  estimate of "16 deletions" became 17 at execution — use the ledger).

### Closure mechanics (BATCH-03)
- **D-10 (mirror v44/v46/v47/v48 VERBATIM):**
  - **2-commit sequential-SHA orchestration** — the `MILESTONE_V49_AT_HEAD_<sha>` placeholder
    resolves to the **closure commit's own SHA**; propagate VERBATIM in ONE pass across:
    FINDINGS-v49.0.md frontmatter (`closure_signal` + `audit_subject_head`) + §1 + §9b/§9c, ROADMAP,
    STATE (Last Shipped), MILESTONES (archive), PROJECT, REQUIREMENTS. A final grep confirms ZERO
    unresolved `MILESTONE_V49_AT_HEAD_<sha>` placeholders remain (T-SHADRIFT guard).
  - **chmod 444** `audit/FINDINGS-v49.0.md` at the closure HEAD.
  - **autonomous:false single blocking USER gate** — present the closure verdict (FINDINGS §9a) +
    the proposed signal string + any new_findings disposition; WAIT for explicit USER approval BEFORE
    resolving the SHA / propagating / flipping. Do NOT auto-advance even if `auto_advance` is on.
    HELD at the closure boundary per [[feedback_wait_for_approval]] /
    `feedback_pause_at_contract_phase_boundaries`.
  - **Doc-only flip** — `.planning/` is gitignored → force-add planning docs;
    `audit/FINDINGS-v49.0.md` is tracked; the commit-guard hook does not block (no `.sol` in the
    diff); Co-Authored-By trailer per the global convention. **Nothing pushed.**
  - **Re-attest all 36 v49.0 requirements** at closure (the §13e-style milestone-wide "uncovered"
    warnings are EXPECTED false alarms — SWEEP-01/02/03 + BATCH-03 re-prove the full set).

### Claude's Discretion
- **Plan shape (D-11):** mirror the 328 4-plan structure — `333-01 DELTA-AUDIT` (SWEEP-02) ∥
  `333-02 ADVERSARIAL-SWEEP` (SWEEP-01) can run as a parallel wave (both READ-ONLY against the frozen
  subject), then `333-03 FINDINGS-v49.0.md` (SWEEP-03, consumes 01 + 02), then `333-04 CLOSURE-FLIP`
  (BATCH-03, `autonomous:false`, LAST). The planner finalizes wave grouping.
- **Worktrees / execution (D-12):** sequential-on-main, NO worktrees — matching 332
  ([[v49-keeper-router-redesign]]; the submodule + node_modules constraint). The only writes are
  `.planning/` + `audit/` docs + the atomic closure flip; no contract edits, so the
  `no_worktree_paths: ["contracts"]` gate is moot, but the closure flip must be atomic on main.
- **FINDINGS §-structure (D-13):** mirror the v48 `audit/FINDINGS-v48.0.md` 9-section layout exactly
  (the planner reads it as the structural template).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope + requirements + roadmap (the closure bar)
- `.planning/ROADMAP.md` — Phase 333 goal + the 4 Success Criteria (the exact sweep charge, the
  NON-WIDENING bar, the FINDINGS §-shape, the closure-flip gate) + the 36-req coverage tables +
  the §13e "uncovered = expected false alarm" note.
- `.planning/REQUIREMENTS.md` — SWEEP-01/02/03 + BATCH-03 exact wording (lines 54–61) + the 36-req
  status table (the rows to flip at closure).
- `.planning/PROJECT.md` — the v49.0 milestone section (the 5+1 work items, the locked design
  decisions, the out-of-scope list) — the closure flip updates "Current Milestone" → "Completed".

### The frozen subject — source (read from `contracts/` ONLY; FROZEN at `4c9f9d9b`)
- `contracts/AfKing.sol` — `doWork` (one-category `else-if` + single `creditFlip` CEI-last
  `:913-918`), `_autoBuy`, the standalone UNREWARDED `autoBuy(count)`/`autoOpen(count)` escapes,
  `BOUNTY_ETH_TARGET` + the ratio/knee/`BUY_BATCH`/`OPEN_BATCH` constants, the dropped `:676`
  `isOperatorApproved` (kept `:401`), the deleted autoBuy stall ladder.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `advanceGame(uint8 mult)` return-shape, the
  removed in-callee `creditFlip` sites, the mid-day `mult=1` partial-drain leg, the free-fallback
  callers (`:1012`, death-clock `:109`/`:1199-1200`/`:1898`), the `totalFlipReversals` nudge.
- `contracts/DegenerusGame.sol` — the `advanceGame` wrapper, `autoOpen`, the discovery views
  (`advanceDue()`/`boxesPending()`/`keeperSnapshot()` GASOPT-03), `degeneretteResolve` (the rename +
  flat re-peg), the MintModule pointer hoist.
- The frozen subject is reached via `git show 63bc16ca:contracts/...` (structural) +
  `git show 4c9f9d9b:contracts/...` (GAS-calibrated) — the latter is the closure-audit anchor.

### Design lock + invariants (what the delta-audit re-attests)
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md`
  — §2 the 4 structural invariants (a)/(b)/(c)/(d); ROUTER-07 no-guard disposition; ADV-04
  frozen-advance-consume; the grep-attestation roll-up.
- `.planning/phases/332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg/332-CONTEXT.md`
  — D-01 the structural-reentrancy disposition (the USER stance the sweep re-attests); D-04/D-05/D-09
  the deletion + ledger arithmetic the delta-audit attributes.

### The regression ledger (the NON-WIDENING gate — AUTHORITATIVE)
- `test/REGRESSION-BASELINE-v49.md` — 666/42/17, the 42-red carried-forward union BY NAME, the 17
  deletions with re-homing justification, the 5 `Crank*`→`Keeper*` renames, the net-zero arithmetic.
- `test/REGRESSION-BASELINE-v48.md` §2 — the AUTHORITATIVE 42-red enumeration the v49 set carries
  forward unchanged.

### The TERMINAL pattern to mirror (the v48 template)
- `audit/FINDINGS-v48.0.md` — the 9-section layout + the §9a verdict shape + the §9b/§9c closure-
  signal propagation pattern + chmod 444 (the structural template for FINDINGS-v49.0.md).
- `.planning/milestones/v48.0-phases/328-terminal-delta-audit-3-skill-adversarial-sweep-closure/`
  — `328-01-DELTA-AUDIT.md` (the delta-audit shape), `328-02-ADVERSARIAL-LOG.md` (§A charge / §C
  disposition table / §D dual-gate attestation — the genuine-PARALLEL topology note in §A.2),
  `328-04-PLAN.md` (the closure-flip plan: the SHA orchestration, the autonomous:false gate, the
  threat model T-PREMATURE/T-SHADRIFT/T-CONTRACTS).
- `.planning/MILESTONES.md` — the archive target the closure flip appends to.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The 3 audit skills — `/contract-auditor`, `/zero-day-hunter`, `/economic-analyst` — each with a
  dedicated `SKILL.md` preserving persona fidelity across the genuine-PARALLEL spawns.
- `git show <sha>:contracts/...` — the read-only frozen-subject access the sweep + delta use (probe
  the actual `4c9f9d9b` source, never from memory).
- `audit/FINDINGS-v48.0.md` + the 328 plan/log set — the directly-reusable structural templates for
  every 333 deliverable (the 4th repetition of the same shape).

### Established Patterns
- The adversarial-log structure: §A CHARGE + §B raw per-skill output + §C per-probe disposition
  table + §D dual-gate Skeptic-Reviewer Filter Attestation (the 320/324/328 shape).
- The closure-flip pattern: single autonomous:false USER gate → resolve placeholder SHA → atomic
  5-doc flip in one pass → chmod 444 → grep zero unresolved placeholders → nothing pushed.
- NON-WIDENING = strict failing-NAME-set equality vs the v48 §2 union (not a count); file-path churn
  (renames) is attributable via the ledger, not a regression.

### Integration Points
- The sweep + delta READ the frozen subject (`contracts/` at `4c9f9d9b`); they WRITE only `.planning/`
  logs + `audit/FINDINGS-v49.0.md`. ZERO `contracts/*.sol` edits in the entire phase.
- The closure flip WRITES the 5 docs (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS) + chmod-444s
  the findings; it depends on the FINDINGS verdict (§9a) + the USER gate approval.

</code_context>

<specifics>
## Specific Ideas

- **The USER delegated the whole phase to Claude's judgment** ("use your judgement") — every
  decision above is resolved from the v44→v48 precedent + the v49 context, not from new user input.
  The ONE remaining USER touchpoint is the `autonomous:false` closure gate (D-10): the verdict +
  signal-string + any new_findings disposition is approved there before the flip.
- The genuinely-NEW v49 attack surface is the **unified router's same-tx composition** (advance-
  consume + buy/open in one tx) — that is where the sweep spends its deepest effort (D-01 TIER-A).
- Reentrancy is **re-attest-only**, per the USER's locked 332 stance — the sweep records it
  SAFE_BY_DESIGN, it does not build an attacker harness (D-01 TIER-B).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the TERMINAL phase scope. (Any FINDING_CANDIDATE that surfaces in
the sweep is, by default, DEFER→v50 with its fix design locked — adjudicated at the USER closure
gate per D-04, not in this discussion.)

</deferred>

---

*Phase: 333-terminal-delta-audit-3-skill-adversarial-sweep-closure*
*Context gathered: 2026-05-27*
