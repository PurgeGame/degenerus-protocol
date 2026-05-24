# Phase 320: AUDIT — Adversarial Sweep + Add/Remove Delta Audit + Closure (TERMINAL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-24
**Phase:** 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
**Areas discussed:** OPEN-E BURNIE-funding disposition (the other 3 gray areas were surfaced but the user chose not to discuss them — locked to precedent defaults)

---

## Gray-area selection

Four shape-decisions were surfaced (the phase's *what* is locked by ROADMAP/REQUIREMENTS). The user selected ONE to discuss:

| Gray area | Description | Selected |
|-----------|-------------|----------|
| Findings deliverable shape | Full `audit/FINDINGS-v46.0.md` 9-section + chmod 444 vs v45-style minimal close | (not discussed → D-04 precedent default: full doc) |
| Sweep execution mode | GENUINE PARALLEL_SUBAGENT vs HYBRID-fallback SEQUENTIAL_MAIN_CONTEXT | (not discussed → D-05 precedent default: adaptive PARALLEL→HYBRID) |
| Closure-flip authorization | Pre-authorize 2-commit flip vs gate at closure | (not discussed → D-06 precedent default: GATED) |
| OPEN-E BURNIE-funding disposition | Accepted-by-design vs leave genuinely open for the sweep | ✓ |

---

## OPEN-E BURNIE-funding disposition

The OPENE-04 caveat: source `S`'s `setOperatorApproval(M, true)` grant authorizes `M`'s subscription to burn `S`'s general-wallet BURNIE + pending coinflip at both `burnForKeeper` sites — broader than the pre-funded ETH escrow (`_poolOf[S]`) the gate was originally chosen for. Documented as intended (same-owner multi-wallet) with a `allowBurnieFunding[S][M]` opt-in flag as the named alternative.

| Option | Description | Selected |
|--------|-------------|----------|
| Leave genuinely OPEN | Sweep charges as a real FINDING_CANDIDATE; skeptic-filter + two-tier; ready to land `allowBurnieFunding` opt-in as a RE-PASS fix if it survives | |
| Pre-dispose accepted-by-design | Sweep documents SAFE_BY_DESIGN with same-owner rationale; opt-in flag stays deferred | ✓ (via explicit trust-model assumption) |
| You decide | Apply security-floor-first posture and pick | |

**User's choice:** First requested clarification of the question, then supplied the deciding threat-model assumption directly: *"assume anyone with approval is the same person or a fixed contract"* and *"approve the wrong guy and you prob getting rekt so just dont do that."*

**Notes:** The clarification resolved the crux (whether the general-purpose `setOperatorApproval` primitive could be exploited by a non-consenting grant). Under the user's assumption, the operator-approval grant IS the trust boundary — grantee is the same person or a fixed/known contract. Therefore:
- The BURNIE-funding OVERLOAD is **accepted-by-design / SAFE_BY_DESIGN** (D-02); consensual by construction.
- The `allowBurnieFunding[S][M]` opt-in flag is **DROPPED**, not deferred (D-02a) — adds nothing under the assumption.
- The sweep STILL must prove four STRUCTURAL protections that make the assumption hold (D-03): (1) no cross-account draw without `isOperatorApproved(S,M)` at `subscribe()`; (2) `fundingSource==0` default-self byte-identical; (3) no escalation to a different non-approving address + no skip-kill-exemption spoof via the source redirect; (4) the trust-the-sub temporal bound (revoke not retroactive) is the accepted posture. A failure of any structural charge = a genuine FINDING_CANDIDATE (the only path that breaks SOURCE-TREE FROZEN).

---

## Claude's Discretion

- The three unselected shape-decisions were locked to precedent-derived defaults and stated to the user (who did not object): D-04 full `audit/FINDINGS-v46.0.md`, D-05 adaptive PARALLEL→HYBRID sweep, D-06 GATED closure flip. The planner may revisit any.
- Sweep CHARGE authoring detail / disposition-table shape / beyond-charge hypotheses — left to planner/executor, mirroring v45 Phase 314.
- `forge inspect` / `git diff` verification mechanics for SOURCE-TREE FROZEN + NON-WIDENING.

## Deferred Ideas

- `allowBurnieFunding[S][M]` opt-in flag — DROPPED (not deferred) under the trust-boundary assumption.
- None else — discussion stayed within the TERMINAL boundary.
