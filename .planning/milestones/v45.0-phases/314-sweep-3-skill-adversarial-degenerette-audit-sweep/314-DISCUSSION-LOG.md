# Phase 314: SWEEP — 3-Skill Adversarial + Degenerette Audit (SWEEP) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-23
**Phase:** 314-sweep-3-skill-adversarial-degenerette-audit-sweep
**Areas discussed:** Re-issue red-team vectors, Degenerette audit track
**Areas defaulted (not selected for deep-dive):** VRF-04 omission re-validation, Invocation + posture

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| VRF-04 omission re-validation | Re-prove the dropped wireVrf-lock "constructor-only-reachable" claim, or treat as settled | |
| Re-issue red-team vectors | Which re-issue surfaces to charge: freeze re-break / LINK-order / rotation-spam / rngWordCurrent edge | ✓ |
| Degenerette audit track | Deterministic track vs charge to contract-auditor; DGAUD-03 acceptance bar | ✓ |
| Invocation + posture | PARALLEL-with-fallback vs SEQUENTIAL-direct; verification-formality vs hunt-hard | |

---

## Re-issue red-team vectors

### LINK-funding order probe depth

| Option | Description | Selected |
|--------|-------------|----------|
| Headline hypothesis | Deep cross-contract trace of DegenerusAdmin._executeSwap; prove request survives-or-atomically-reverts | |
| Spot-check only | Rationale documented + VER-01 resolved; confirm same-tx funding, record SAFE_BY_DESIGN | ✓ |
| You decide | Planner/red-team calibrates depth | |

**User's choice:** Spot-check only
**Notes:** The re-issue fires requestRandomWords before LINK lands, but the diff comment + resolved VER-01 already carry the same-tx atomic-funding rationale. No deep trace needed.

### Daily/mid-day exclusivity (VER-03) adversarial re-validation

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit named hypothesis | Standalone "both flags set → silent daily-drop → permanent freeze?" disposition row | |
| Fold into freeze disposition | Cover inside the general freeze-invariant row; exclusivity confirmed at IMPL | |
| You decide | Red-team decides standalone-row need after tracing flag set/clear sites | ✓ |

**User's choice:** You decide
**Notes:** Delegated to the red-team — standalone row only if tracing the LR_MID_DAY / rngLockedFlag set-clear sites warrants it.

### Rotation-spam griefing line

| Option | Description | Selected |
|--------|-------------|----------|
| SAFE_BY_DESIGN row | Keep the line; document admin-gated + freeze-exempt structural protection | ✓ |
| Repurpose to admin-cost | Repoint at LINK-leak from repeated rotations abandoning in-flight requests | |
| You decide | Economic-analyst decides | |

**User's choice:** SAFE_BY_DESIGN row
**Notes:** updateVrfCoordinatorAndSub is ADMIN-only + freeze-exempt, so player rotation-spam is structurally moot. Keep the row for enumerate-everything completeness (v44 72-row precedent).

---

## Degenerette audit track

### DGAUD-01..04 structure + recording

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic track + note | Separate main-context verification track producing a standalone degenerette-audit-note | |
| Fold into contract-auditor | Charge into contract-auditor's scope alongside SWP-02; single integrated table; section of the LOG | ✓ |
| You decide | Planner chooses placement | |

**User's choice:** Fold into contract-auditor
**Notes:** Degenerette coverage becomes a section of 314-01-ADVERSARIAL-LOG.md, not a separate note file — deviation from the ROADMAP "+ degenerette-audit-note bundle" phrase.

### DGAUD-03 "reconstruction viable" bar

| Option | Description | Selected |
|--------|-------------|----------|
| Full field-level decode | Prove BetPlaced rebuilds BOTH removed mappings; resolve/flag the index→level recoverability | |
| Viable-in-principle | Confirm BetPlaced fires with player + amount; per-level grouping reconstructable off-chain by convention | ✓ |
| You decide | Auditor judges after decoding packed | |

**User's choice:** Viable-in-principle
**Notes:** BetPlaced carries only the lootbox index, not game level; the index→level derivation is an accepted off-chain-indexer convention, NOT a finding. Do not escalate the gap.

### DGAUD-02 "byte-identical" framing

| Option | Description | Selected |
|--------|-------------|----------|
| Behavioral identity | Attest the dailyHeroWagers SSTORE computation unchanged (whitespace + scope-brace only) | ✓ |
| Literal byte-identical | Hold to literal bytes (would fail on de-indentation) + documented deviation note | |
| You decide | Auditor picks framing | |

**User's choice:** Behavioral identity
**Notes:** 92b110bf de-indented the block and dropped the enclosing brace when removing the sibling per-player/per-level block; the SSTORE logic is line-for-line unchanged.

---

## Claude's Discretion

- Daily/mid-day exclusivity standalone-row decision (D-02) — delegated to the red-team after tracing flag set/clear sites.
- Disposition-table layout, per-skill MD structure, CHARGE wording — planner/executor, matching v44 P307 shape.
- SWP-02 beyond-charge hypotheses (economic-analyst MEV/coordination angles) — skill discretion, subject to the skeptic filter.
- VRF-04 omission default (D-04): drop the stale wireVrf-lock charge line; keep the mandatory call-graph re-proof.
- Invocation default (D-10): SEQUENTIAL_MAIN_CONTEXT-direct, PARALLEL only if Task genuinely available.

## Deferred Ideas

- Deep cross-contract _executeSwap LINK-funding trace — deferred to a spot-check (D-01).
- Escalating the degenerette index→level off-chain reconstruction gap to a FINDING_CANDIDATE — declined (D-06).
- The ~115 non-VRF v44 backlog anchors — stay deferred in FINDINGS-v44.0.md §9d for a future milestone.
- Phase 315 TERMINAL consolidate-forward delta audit + closure — the next phase.
