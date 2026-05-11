# Phase 270: Post-v32.0 Deferred-Commit Adversarial Sub-Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-11
**Phase:** 270-post-v32-0-deferred-commit-adversarial-sub-audit
**Areas discussed:** Adversarial-skill dispatch posture, Sweep coherence anchor

---

## Adversarial-Skill Dispatch Posture

Phase 270 sweeps two long-deferred contract-tree commits (`002bde55` presale auto-deactivate + `2713ce61` setDecimatorAutoRebuy removal). ROADMAP §270 uses "adversarial" 3× but never names a specific skill tool. Phase 271 §4 has scheduled `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL pass over the FULL surface table (which includes Phase 270's two-commit carry-forward declarations as surface rows).

| Option | Description | Selected |
|---|---|---|
| Pure agent grep-sweep | Phase 270 stays a feeder phase; pure agent-driven adversarial sweep with grep-cited evidence per ROADMAP surface enumeration; `/contract-auditor` + `/zero-day-hunter` run in Phase 271 §4 over the full surface table. Avoids duplicating Phase 271 §4 work. | ✓ |
| `/contract-auditor` per commit | Spawn `/contract-auditor` once per commit (2 dispatches) against each commit's diff + surrounding surfaces. Phase 271 §4 still runs its own pass later. Adds attack-vector depth now; partial duplication with Phase 271. | |
| `/contract-auditor` + `/zero-day-hunter` per commit | Spawn both skill agents per commit (4 dispatches). Maximum depth. Phase 271 §4 will re-audit the same surfaces. Strongest pre-emption of Phase 271 work but maximum duplication; commits are small and well-trodden so marginal-find probability is low. | |

**User's choice:** Pure agent grep-sweep (Recommended)
**Notes:** Locks D-270-ADVERSARIAL-01. Phase 270 stays a feeder phase. Adversarial-skill pass canonically lives in Phase 271 §4 SEQUENTIAL per ROADMAP §271 D-NN-ADVERSARIAL-02 carry. `/economic-analyst` + `/degen-skeptic` inclusion deferred to Phase 271 discuss-phase per Phase 269 precedent.

---

## Sweep Coherence Anchor

Target commits are 3+ months old: `002bde55` landed 2026-05-02 (during v32.0 work); `2713ce61` landed 2026-05-05 (during v33.0 work). Surfaces have evolved through ~80 phases. ROADMAP DELTA-01/02 blends both "commit-hash anchor" landing-SHA evidence + "residual callsite proof of zero" current-HEAD grep. Question: how deep does the HEAD-state re-verification go?

| Option | Description | Selected |
|---|---|---|
| Landing-SHA + HEAD invariant re-verification per surface ("β-deep") | For each ROADMAP-enumerated adversarial surface: BOTH read the commit hunk at landing-SHA + classify per taxonomy AND grep-cite the invariant still holds at v37.0 current HEAD. ~4-5 extra grep recipes per commit (8-10 total). Closes the v33→v37 carry-forward gap fully. Each surface row carries dual evidence. | ✓ |
| Landing-SHA + minimum-ROADMAP HEAD checks only ("β-light") | Read commit hunks + classify + sweep landing-time surfaces. At HEAD, only run what ROADMAP explicitly cites (DELTA-02 residual-callsite zero-grep for 2713ce61; nothing specific for 002bde55). Faster but the HEAD-survival question for 002bde55 stays implicit. | |
| Landing-SHA delta only ("α") | Read commit hunks; classify; sweep surfaces as they existed at landing-SHA. No HEAD-state checks beyond what's strictly required for DELTA-02. Fastest but ignores that the audit was deferred 4 milestones for this exact reason. | |

**User's choice:** Landing-SHA + HEAD invariant re-verification per surface (Recommended)
**Notes:** Locks D-270-COHERENCE-01. Every Phase 270 surface row in `270-01-DELTA-SURFACE.md` carries DUAL evidence: landing-time hunk + v37.0 HEAD invariant grep cite. ~8-10 grep recipes total for both commits. Closes the v33→v37 carry-forward deferral gap; produces a clean Phase 271 §3.A input. `feedback_design_intent_before_deletion.md` actor-game-theory walk methodology applies per commit per surface (D-270-DESIGN-INTENT-METHOD-01).

---

## Claude's Discretion (planner refines)

- Per-commit working-file structure (single combined `270-01-DELTA-SURFACE.md` vs two sub-files).
- Adversarial-surface table shape (markdown table with dual-evidence columns vs prose per-surface sections).
- Pickaxe trace depth for design-intent traces (single `git log -p -S "<string>"` per distinctive string vs full commit-history walk of affected function).
- Inline NatSpec vs prose for actor-game-theory walks per surface.
- Atomic-commit count: 2-3 AGENT-COMMITTED commits combining sub-audit chore commits + final working-file commit + phase-close, or splitting per-commit chore commits.

## Default Lockings (areas not explicitly selected during AskUserQuestion multiSelect; defaults applied per analysis)

- **D-270-DEPTH-01:** Stay strictly within ROADMAP per-commit surface enumeration. No scope expansion. Additional surfaces spotted during sweep → routed to `<deferred>` in CONTEXT.md or v38+ backlog, NOT added to Phase 270 deliverable. Matches feeder-phase framing.
- **D-270-FCFORMAT-01:** FINDING_CANDIDATE rows (default expectation: zero) stubbed Phase-271-§3.A-block-ready (severity-tier candidate + surface description + exploit path + defensive argument + grep-cited evidence). Phase 271 §3.A can promote directly without re-authoring.

## Deferred Ideas

- Phase 271 §4 adversarial-skill pass over the full v37.0 surface table (re-audits Phase 270's declarations).
- `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion → Phase 271 discuss-phase.
- Additional adversarial surfaces beyond ROADMAP enumeration (e.g., flag-clear-vs-write race in 002bde55 MintModule SSTORE; ABI-consumer breakage from 2713ce61 selector removal; gas-cost claim audit for 002bde55) → v38+ backlog unless Phase 271 promotes.
- BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 (v38+ candidate; carried from Phase 269 deferred-ideas, NOT a Phase 270 concern).
- `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry) — out of v37.0 scope.
- `runrewardjackpots` module-misplacement — out of v37.0 scope.
- Game-over thorough hardening — out of v37.0 scope.
