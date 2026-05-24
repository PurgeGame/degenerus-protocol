# Phase 320: AUDIT — Adversarial Sweep + Add/Remove Delta Audit + Closure (TERMINAL) - Context

**Gathered:** 2026-05-24
**Status:** Ready for planning

<domain>
## Phase Boundary

The v46.0 **TERMINAL** phase. SOURCE-TREE FROZEN — zero `contracts/` + zero `test/` mutations during Phase 320 **unless** a Tier-1 user-approved or Tier-2 auto-elevated FINDING_CANDIDATE triggers a RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01`. Three workstreams, all re-attesting (owning 0 primarily) the milestone's 46 requirements at closure:

1. **3-skill adversarial sweep** — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (`/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) charged with the full ROADMAP §"Phase 320" surface list: composition, subscription-trigger griefing, coinflip-credit recycle, BURNIE-supply interaction, the `burnForKeeper`/`creditFlip`/`batchPurchase` authority surface, the two-tier skip-kill identity, the **OPEN-E shared-funding-source surface (Phase 319.1)**, faucet round-trip, and the REMOVE surface (ETH-auto-rebuy strand, BURNIE 75bps collapse, JGAS jackpot two-call-split removal). Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` BEFORE any user-pause; two-tier consensus (Tier-1 any-skill → AskUserQuestion PAUSE; Tier-2 3-of-3 → auto-elevate + RE-PASS).
2. **Add/remove delta-audit** — every v45→v46 `contracts/` change (the 317 batched ADD+REMOVE diff + the 319.1 OPEN-E diff + the JGAS jackpot-split removal) audited together; add surfaces (PROTO/CRANK/REW/SUB + OPEN-E funding-source routing) and remove surfaces (RM + JGAS) compose cleanly — no orphaned/double-credited winnings; daily ETH jackpot pays all 305 winners in one call with nothing stranded by the dropped `resumeEthPool` carry.
3. **Regression + closure** — RNG-freeze intact under permissionless resolve AND the freeze obligations RETIRED by the ETH-auto-rebuy removal; faucet bounded; v44.0 + v45.0 closure surfaces NON-WIDENING; `KNOWN_ISSUES` + the BURNIE win/loss RNG path UNMODIFIED. Emit `MILESTONE_V46_AT_HEAD_<sha>` + atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS).

**The phase's *what* is locked** by ROADMAP §"Phase 320" (goal + 5 success criteria + the verbatim charged-surface list) and REQUIREMENTS.md (all 46 reqs; Phase 320 re-attests all, owns 0). This discussion settled only the *process/deliverable SHAPE* choices that diverged across recent milestones. No scope creep — anything outside the closure verdict belongs to a future milestone.

</domain>

<decisions>
## Implementation Decisions

### OPEN-E BURNIE-funding disposition (the discussed area)

- **D-01 — Operator-approval IS the trust boundary (load-bearing threat-model assumption).** Any `M` holding `setOperatorApproval(S, M) = true` is, by assumption, **either the same person as `S` (multi-wallet) or a fixed/known contract `S` deliberately integrated with.** There is no "tricked into granting" actor in the threat model. The user's framing: *"approve the wrong guy and you prob getting rekt so just dont do that"* — granting approval to a malicious party is user-error, the protocol's only job is to enforce the gate exists; the consent *scope* is the grantor's responsibility (caveat emptor on the grant).
- **D-02 — The BURNIE-funding overload is ACCEPTED-BY-DESIGN / SAFE_BY_DESIGN.** OPENE-04's caveat — that the operator-approval also authorizes `M`'s subscription to burn `S`'s general-wallet BURNIE + pending coinflip (sharper than the pre-funded ETH escrow `_poolOf[S]` the gate was originally chosen for) — is consensual by construction under D-01. The sweep documents it as accepted with rationale; it is NOT a FINDING_CANDIDATE to be elevated. (Equivalent to "pre-dispose accepted-by-design," justified by the explicit trust assumption rather than asserted blind.)
- **D-02a — The `allowBurnieFunding[S][M]` opt-in flag is DROPPED.** Under D-01 it adds nothing (S already chose to trust M with the whole grant). It is NOT future work — explicitly out, not deferred.
- **D-03 — Residual STRUCTURAL must-pass charges (NOT waived by D-01/D-02).** These are the gate that makes the trust assumption hold, so the sweep MUST still prove each — failure of any is a genuine FINDING_CANDIDATE → Tier-1 PAUSE → potential RE-PASS contract fix (the one path that could break SOURCE-TREE FROZEN):
  1. **No cross-account draw without consent** — a non-approved `M` pointing `fundingSource = S` MUST revert (`NotApproved`); `isOperatorApproved(S, M)` is genuinely enforced **at `subscribe()`** (subscribe-only auth — never per-draw, never at day-31 renewal).
  2. **Default-self identity** — `fundingSource == 0` (self) stays byte-for-byte behavior-identical to pre-OPEN-E (short-circuits the approval read; same single `_poolOf` slot SLOADed; per-draw gas unchanged).
  3. **No escalation beyond the grant** — `M` cannot redirect to drain a *different*, non-approving address, and the `fundingSource` redirect cannot spoof the Vault/sDGNRS subscriber-identity skip-kill exemption (the two-tier skip-kill exemption is keyed on the un-spoofable SUBSCRIBER identity, never the source).
  4. **Trust-the-sub temporal bound (documented, accepted)** — a later `setOperatorApproval(M, false)` revoke does NOT retroactively stop an active sub; an active funding sub's drain is bounded only by sub lifetime + `S`-defunding (`_poolOf[S]` ETH / spending down BURNIE) or `M` cancelling. This by-design posture is the accepted bound, not a defect.

### Process / deliverable SHAPE (NOT discussed this session — locked to precedent defaults; override at plan-phase if desired)

These three were surfaced as gray areas; the user chose not to discuss them, so they are locked to the precedent-derived defaults below and stated to the user. The planner may revisit any of them.

- **D-04 — Findings deliverable: FULL `audit/FINDINGS-v46.0.md`.** Ship the 9-section TERMINAL deliverable (`chmod 444` at close), matching the v40–v44 pattern (`audit/FINDINGS-v44.0.md` is the structural template). **Rationale for reverting v45's minimal-close precedent:** v45.0 was a narrow consolidate-forward audit and the user explicitly WAIVED its formal doc; v46.0 is a FEATURE milestone with real contract additions, a brand-new in-tree contract (`AfKing.sol`), and a new attack surface (OPEN-E funding-source) — it warrants a publishable findings record.
- **D-05 — Sweep execution mode: ADAPTIVE PARALLEL→HYBRID.** Attempt GENUINE `PARALLEL_SUBAGENT` (like v45 Phase 314 ran inline holding the Task tool); HYBRID-fallback to `SEQUENTIAL_MAIN_CONTEXT` if the executor lacks the Task tool (v42 P296 / v43 P302 / v44 P307 precedent). Skills locked: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`. Persona fidelity via dedicated per-skill MD files with verbatim CHARGE regardless of mode.
- **D-06 — Closure-flip authorization: GATED (NOT pre-authorized).** The 2-commit closure flip + `MILESTONE_V46_AT_HEAD_<sha>` propagation requires an explicit user approval at the closure moment — do NOT adopt the `D-44N-CLOSURE-PREAUTH-01` autonomous pattern. **Rationale:** matches `feedback_pause_at_contract_phase_boundaries` + `feedback_wait_for_approval` (confirm direction at a milestone-ending / security-gated boundary). The terminal is doc-only (source-tree frozen), so the gate is cheap.

### Claude's Discretion
- Sweep CHARGE authoring detail, disposition-table column shape, and which beyond-charge hypotheses each skill explores — left to the planner/executor, mirroring the v45 P314 artifact structure.
- Exact `forge inspect` / `git diff` commands used to prove SOURCE-TREE FROZEN + NON-WIDENING regression — technical verification mechanics.
- Re-grep-verification of every cited `AfKing.sol` / module file:line against HEAD before the audit writes any claim (mandatory per `feedback_verify_call_graph_against_source.md`, but the HOW is execution detail).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked instruction set (read FIRST)
- `.planning/ROADMAP.md` §"Phase 320: AUDIT — Adversarial Sweep + Add/Remove Delta Audit + Closure (TERMINAL)" — the TERMINAL goal, the verbatim charged-adversarial-surface list (incl. the full OPEN-E `fundingSource` probe set), and the 5 success criteria. The non-negotiable instruction set for this phase.
- `.planning/REQUIREMENTS.md` — all 46 v46.0 requirement IDs + the **OPENE-01..04 section** (the funding-source contract: `Sub.fundingSource` set only via `subscribe()`, ETH-pool draw routing, both `burnForKeeper` sites incl. window-1, operator-approval-at-subscribe auth) + the Traceability table (Phase 320 re-attests all 46, primary-owns 0) + the §"Phase 320 TERMINAL" coverage note.

### Locked design (delta-audit "intended" reference)
- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` — THE locked v46.0 add+remove+JGAS design across all 42 (signatures, work-type encoding, RM-01..06 footprint, the compounded −2 storage slot-shift, JGAS-01/02 decision, SUB-09 permanent-deity, the grep-verified Call-Graph Attestation). What the delta-audit confirms the diff matches.

### OPEN-E surface (the headline new attack surface — Phase 319.1)
- `contracts/AfKing.sol` — the keeper. `subscribe()` `fundingSource` param + `isOperatorApproved(S, M)` gate; window-1 `burnForKeeper` (cited ~`:396`), day-31 auto-extract `burnForKeeper` (cited ~`:587`); the ETH `_poolOf[fundingSource]` draw routing; the two-tier subscriber-identity skip-kill. **Re-grep every cited file:line vs HEAD before writing any audit claim.**
- `contracts/DegenerusVault.sol` + `contracts/StakedDegenerusStonk.sol` — the SUB-09 protocol self-subscribe callers (both pass `fundingSource = address(0)` = self); the subscribe-signature ripple subjects.
- `.planning/phases/319.1-impl-open-e-shared-funding-source-burnie-and-eth-pool/319.1-RESEARCH.md` — the fundingSource design substrate (offsets, routing, gate placement).
- `.planning/phases/319.1-.../319.1-VERIFICATION.md` — 13/13 verification (what OPENE-01..04 already prove; the audit re-attests, doesn't re-derive).
- `.planning/phases/319.1-.../319.1-REVIEW.md` — code-review disposition (WR-01 indexed `fundingSource` event added; WR-02 stale-docstring fix).
- `.planning/phases/319.1-.../319.1-HUMAN-UAT.md` — the human-decision UAT items for the OPEN-E surface.

### Adversarial-sweep precedent (structure to mirror — D-05)
- `.planning/milestones/v45.0-phases/314-sweep-3-skill-adversarial-degenerette-audit-sweep/314-ADVERSARIAL-CHARGE.md` — the verbatim-charge format.
- `.planning/milestones/v45.0-phases/314-.../314-ADVERSARIAL-CONTRACT-AUDITOR.md` + `…-ZERO-DAY-HUNTER.md` + `…-ECONOMIC-ANALYST.md` — the per-skill MD pattern (genuine-PARALLEL precedent).
- `.planning/milestones/v45.0-phases/314-.../314-01-ADVERSARIAL-LOG.md` — the integrated LOG + disposition-table + skeptic-filter application (v45 unanimous-NEGATIVE; 33 rows, 0 FINDING_CANDIDATE).

### Findings-doc template + closure mechanics (D-04, D-06)
- `audit/FINDINGS-v44.0.md` — the last full 9-section deliverable (`chmod 444`): §3.A delta-surface table, §3.B per-exempt-entry attestation matrix, §3.C/§3.F conservation/invariant matrices, §4 adversarial disposition, §5 LEAN regression, §6 KI walkthrough, §9 closure verdict + §9d handoff register. The structural template for `audit/FINDINGS-v46.0.md`.
- `.planning/MILESTONES.md` — the archive target for the v46.0 closure entry (part of the atomic 5-doc flip).
- `.planning/ROADMAP.md` §"Phase 308" (D-44N-CLOSURE-01 full 2-commit closure flip) vs §"Phase 315" (the v45 minimal-close precedent) — the two closure patterns; D-04/D-06 picks the full-doc + gated-flip combination.

### Design rationale (background)
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` — the ADD-half (crank + subscription) rationale.
- `.planning/PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` — the REMOVE-half (legacy AFKing + free ETH auto-rebuy) rationale.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The v45 Phase 314 adversarial-log bundle (CHARGE + 3 per-skill MDs + integrated LOG + disposition section) is the proven artifact skeleton — copy its structure for the Phase 320 sweep (D-05).
- `audit/FINDINGS-v44.0.md` 9-section layout is the proven deliverable skeleton for `audit/FINDINGS-v46.0.md` (D-04).

### Established Patterns
- **2-commit sequential-SHA closure orchestration** (`D-44N-CLOSURE-01` / `D-303-CLOSURE-01` / `D-297-CLOSURE-01` lineage): Commit 1 ships the deliverable with a `<commit-1-sha>` placeholder; Commit 2 resolves the placeholder + propagates `MILESTONE_V46_AT_HEAD_<sha>` verbatim to the FINDINGS verbatim-locations + cross-doc targets + `chmod 444` + the atomic 5-doc closure flip (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS). **D-06 gates this behind explicit user approval** (no pre-auth).
- **SOURCE-TREE FROZEN terminal**: zero `contracts/` + zero `test/` mutations during Phase 320, verified via `git diff` returning no in-phase source-tree change — UNLESS a Tier-1/Tier-2 FINDING_CANDIDATE (e.g., a D-03 structural-charge failure) triggers a RE-PASS contract fix.
- **Skeptic-reviewer filter BEFORE any user-pause** (`feedback_skeptic_pass_before_catastrophe.md`): structural-protection check + 3-condition EV lens applied before any Tier-1 AskUserQuestion.

### Integration Points
- Delta-audit subject set = the batched Phase 317 ADD+REMOVE diff (`df4ef365` + keeper remap `8e137e2` + slot gap-closure) **+** the Phase 319.1 OPEN-E diff (`42140ceb` + WR-01 event `e1baa978`) **+** the Phase 319 GAS peg constants (`e4014f91` + CR-01 fix `795e679d`) **+** the JGAS jackpot-split removal across `DegenerusGameAdvanceModule` + `DegenerusGameJackpotModule`. Baseline → subject: v45 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` → v46 closure HEAD.
- Test baseline for the NON-WIDENING / RNG-freeze regression: suite 559 pass / 44 fail = EXACT v45 baseline (the 44 are unrelated pre-existing failures; zero v46 regression). Any new failure is a regression signal.

</code_context>

<specifics>
## Specific Ideas

- **OPEN-E disposition, in the user's words:** *"assume anyone with approval is the same person or a fixed contract"* and *"approve the wrong guy and you prob getting rekt so just dont do that."* The operator-approval grant is the trust boundary; the protocol enforces the gate, not the wisdom of the grant. → D-01/D-02.
- v45.0 set a minimal-close precedent (no `FINDINGS-v45.0.md`); v46.0 deliberately reverts to the full v44-style deliverable (D-04) because it is a feature milestone with new contract code + a new attack surface, not a narrow consolidate-forward.

</specifics>

<deferred>
## Deferred Ideas

- **`allowBurnieFunding[S][M]` opt-in flag** — DROPPED, not deferred. Under the D-01 trust-boundary assumption it adds nothing; explicitly out of scope (not a future-milestone item).
- None else outside scope — discussion stayed within the TERMINAL boundary.

</deferred>

---

*Phase: 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi*
*Context gathered: 2026-05-24*
