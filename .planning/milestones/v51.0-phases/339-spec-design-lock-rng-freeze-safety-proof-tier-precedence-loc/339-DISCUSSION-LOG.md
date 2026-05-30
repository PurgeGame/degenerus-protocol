# Phase 339: SPEC — Design-Lock + RNG-Freeze-Safety Proof + Tier-Precedence Lock + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc
**Areas discussed:** Slot-arg width, Bingo soundness, Whale-race lock

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Slot-arg width | Lock the claimBingo arg type (uint32[8] vs uint256[8]) — "Open before SPEC" #2 | ✓ |
| Freeze-proof depth | How rigorous the BINGO-06 RNG-freeze proof must be | (skipped → Claude default) |
| Bingo soundness | How deeply the SPEC proves the traitBurnTicket read is unspoofable (BINGO-01 foundation) | ✓ |
| Whale-race lock | Whether the SPEC enshrines whale-frontrunning as a written accepted-by-design non-finding | ✓ |

**User's choice:** Slot-arg width, Bingo soundness, Whale-race lock (freeze-proof depth left to Claude's discretion).
**Notes:** The design is heavily pre-locked in `PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md`, so discussion was intentionally narrow — only the genuinely-open SPEC decisions.

---

## Slot-arg width

| Option | Description | Selected |
|--------|-------------|----------|
| uint32[8] | Cheap calldata; caps the inner-array index at ~4.29B entries per (level,traitId) — unreachable. Plan-doc default. | ✓ |
| uint256[8] | Native array-index width, zero overflow/cap risk, ~4× the calldata. | |

**User's choice:** uint32[8]
**Notes:** → CONTEXT D-01. The SPEC must state the cap explicitly so the audit has a written disposition (not silence).

---

## Bingo soundness

| Option | Description | Selected |
|--------|-------------|----------|
| Full write-site attestation | SPEC reads the actual population sites (JackpotModule:654 + DegenerusGame:2701/2730/2813), proves appears-iff-owned, addresses duplicate-append + transfer/burn semantics. | ✓ |
| Precedent-based | SPEC attests the read is sound by citing that jackpot winner-selection already trusts the map post-resolution, without re-deriving the population mechanics. | |

**User's choice:** Full write-site attestation
**Notes:** → CONTEXT D-02. This is the heart of whether claimBingo can be spoofed → gets the most rigorous treatment in the SPEC.

---

## Whale-race lock

| Option | Description | Selected |
|--------|-------------|----------|
| Write it as a locked non-finding | SPEC records "whale frontrunning on the per-VRF trait-resolution batch ACCEPTED BY DESIGN" with rationale, so the deferred v52 sweep treats it as already-dispositioned. | ✓ |
| Leave to v52 | SPEC only locks the race-start semantics; the accept/flag disposition is left entirely to the v52 sweep. | |

**User's choice:** Write it as a locked non-finding
**Notes:** → CONTEXT D-03. Race-start semantics also locked: claimable the moment level-N entry traits are RNG-resolved.

---

## Claude's Discretion

- **Freeze-proof depth (BINGO-06)** — user skipped this gray area. Defaulted to a rigorous structured per-slot SSTORE/SLOAD enumeration (not prose alone), consistent with the USER-LOCKED audit weighting where RNG/freeze is the DOMINANT axis. → CONTEXT D-04. User may downgrade to lighter prose on request.
- Exact SPEC.md section structure (mirror the v50.0 Phase 334 SPEC layout precedent).

## Deferred Ideas

- Bingo progress view helper (frontend read-only) — out of v51 scope, deferred follow-up.
- The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` — DEFERRED → v52 consolidated audit.
- Cross-level/multi-level bingo, 2nd/3rd-place ladders, commit-reveal anti-MEV, Pool.Reward refill automation — explicit non-goals.
- Q3 (Dice) special-case naming — UI string only, no contract effect.

(All deferred items were pre-recorded non-goals; no scope creep arose during discussion.)
