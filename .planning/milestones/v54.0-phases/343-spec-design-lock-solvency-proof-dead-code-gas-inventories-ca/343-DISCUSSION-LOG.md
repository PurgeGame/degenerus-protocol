# Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca
**Areas discussed:** GAS-01 inventory depth, De-custody finalization, BatchBuy funder-split correction (found mid-discussion)

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Solvency proof rigor | Paper-attest vs front-load adversarial red-team at SPEC | (skipped → resolved by rec) |
| GAS-01 inventory depth | Scavenger-now vs hand-enumerate; blast radius | ✓ |
| SPEC deliverable shape | Single SPEC.md vs 334 multi-doc | (skipped → resolved by rec) |
| De-custody finalization | poolOf delete-vs-shim; v48 recovery remove-vs-noop | ✓ |

**Note:** the design itself was DESIGN-LOCKED in PLAN-V54 before discussion (Decisions A2 + B, no-new-aggregate,
packing deferred), so all gray areas were about SPEC-phase rigor / deliverable shape, not the mechanism.

---

## GAS-01 inventory depth

### Build method
| Option | Description | Selected |
|--------|-------------|----------|
| Run /gas-scavenger now | Thorough advisory candidate list at SPEC (no validation here; 345 = gas-skeptic) | ✓ |
| Hand-enumerate obvious wins | Light SPEC; 345 runs full scavenger | |
| Scavenger, tightly scoped | Restrict to diff-touched files only | |

### Blast radius
| Option | Description | Selected |
|--------|-------------|----------|
| Touched files only | Just the v54-edited files | |
| Touched + accounting spine | Add the yield-surplus / drain / final-sweep / stETH-stake / sDGNRS sites the proof walks | ✓ |

**User's choice:** Run /gas-scavenger now, reaching touched files + the accounting spine.
**Notes:** Codebase-wide CLEANUP-03 sweep stays in 345; packing candidate documented/flagged for 345 only.

---

## De-custody finalization

### poolOf(player) view
| Option | Description | Selected |
|--------|-------------|----------|
| Delete it | Canonical = game.keeperFundingOf; smallest AfKing surface | ✓ |
| Keep as delegating shim | poolOf returns game.keeperFundingOf; preserves AfKing-centric ABI | |

### v48 stuck-pool recovery
| Option | Description | Selected |
|--------|-------------|----------|
| Hard-remove (after dead-proof) | Delete all three legs once CLEANUP-01 grep-proves each orphaned (DECUSTODY-04) | ✓ |
| Leave as no-ops | Keep inert signatures; lower diff risk, leaves dead surface | |

**User's choice:** Delete poolOf; hard-remove the v48 recovery after CLEANUP-01 dead-proof.
**Notes:** Pre-launch redeploy-fresh, no live integrators to break.

---

## BatchBuy funder-split correction (found mid-discussion)

Surfaced by reading the v53 AfKing/Game wiring: PLAN-V54 §4 + REQUIREMENTS AUTOBUY-02 debit
`keeperFunding[b.player]`, but `b.player` is the purchaseWith beneficiary while the funding identity is `src`
(`AfKing.sol:686`). The OPEN-E operator-funded case (`src ≠ player`) would debit the wrong/empty bucket.

| Option | Description | Selected |
|--------|-------------|----------|
| Add a funder field to BatchBuy | Game debits keeperFunding[b.funder], purchaseWith(b.player); keeps OPEN-E src-keyed funding verbatim | ✓ |
| Re-key OPEN-E to subscriber's bucket | Simpler struct, but funds become withdrawable by subscriber not source — contradicts DECUSTODY-03 | |
| Lock invariant, defer mechanism | Lock "debit keys off src," leave struct to planner | |

**User's choice:** Add a `funder` field to BatchBuy.
**Notes:** Corrects REQUIREMENTS AUTOBUY-02 + PLAN-V54 §4 (both say b.player). VAULT/SDGNRS exemption stays
keyed on `player`. Both BatchBuy structs change together (redeploy-fresh). Sibling must-reconcile captured in
CONTEXT (D-MR-01): extended keeperSnapshot returns keeperFunding[player] = keeperFunding[src] only when
src==player; OPEN-E src≠player needs one extra keeperFundingOf(src) read.

---

## Claude's Discretion
- Multi-doc SPEC filenames/split (keep five concerns discrete).
- Which adversarial skill(s) red-team the solvency proof (/economic-analyst and/or /contract-auditor).
- /gas-scavenger prompt aggressiveness (advisory; 345 is the validation gate).

## Resolved-by-recommendation (skipped areas)
- Solvency proof rigor → front-load a focused adversarial red-team on the SOLVENCY-01/03 proof at SPEC.
- SPEC deliverable shape → v50/Phase-334 multi-doc pattern (SOLVENCY-PROOF + GREP-ATTESTATION + CLEANUP-INVENTORY
  + GAS-INVENTORY + IMPL-EDIT-ORDER-MAP, indexed by 343-SPEC-INDEX).

## Deferred Ideas
- CLEANUP-03 codebase-wide sweep → 345.
- GAS-02 validation + application → 345.
- claimableWinnings packing evaluation → 345 gas-skeptic.
- Generalized operator-spend-of-claimableWinnings → out of v54 (Future Requirements).
