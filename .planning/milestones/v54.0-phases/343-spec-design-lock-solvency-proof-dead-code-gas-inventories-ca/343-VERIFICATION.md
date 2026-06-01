---
phase: 343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca
verified: 2026-05-30T00:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation

**Phase Goal:** The funding-ledger bundle's shapes are settled in writing so the IMPL phase authors a fully reconciled diff with zero "by construction" assumptions, and the load-bearing solvency concern is PROVEN before any code is written.
**Verified:** 2026-05-30
**Status:** passed
**Re-verification:** No — initial verification

---

## Critical Pre-Check: ZERO contracts/ mutation

`git diff --numstat 83a84431 HEAD -- contracts/` returns EMPTY. The working tree is byte-identical to the v53 HEAD `83a84431`. This is the defining constraint for a paper-only SPEC phase. VERIFIED.

---

## Goal Achievement

### Observable Truths (ROADMAP Phase-343 Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|--------------------------|--------|----------|
| SC1 | The full ledger design is settled in writing (BATCH-01): non-payable `batchPurchase(BatchBuy[])` + `depositKeeperFunding` / CEI `withdrawKeeperFunding` / `keeperFundingOf` signatures + `mapping(address => uint256) keeperFunding` storage shape + extended `keeperSnapshot` + Decision-B `_claimWinningsInternal` merge + producer-before-consumer edit-order map | ✓ VERIFIED | `343-IMPL-EDIT-ORDER-MAP.md` Sections 1-4 lock every signature with actual file:line anchors; the D-01 `funder` field, GO_SWEPT guard, and D-06 kill ordering are all carried |
| SC2 | SOLVENCY-01 PROVEN: all 5 "free ETH = totalBal − reserved" sites shown to reserve `claimablePool` (inclusive of the keeper total) with NO change | ✓ VERIFIED | `343-SOLVENCY-PROOF.md` Section A walks all 5 by name (distributeYieldSurplus, drain pre-refund, drain post-refund, adminStakeEthForStEth, handleFinalSweep), each with actual file:line; red-team probes 1-5 all NEGATIVE-VERIFIED / SAFE_BY_DESIGN in `343-SOLVENCY-REDTEAM.md` |
| SC3 | SOLVENCY-03 PROVEN + OPEN-E carry-over confirmed: sDGNRS redemption valuation is unchanged + correct; keeper ETH invisible to sDGNRS own-balance valuation; OPEN-E 4-protection disposition carries over verbatim | ✓ VERIFIED | `343-SOLVENCY-PROOF.md` Sections C and D prove the valuation formula reads only sDGNRS's own balance + `claimableWinningsOf(sDGNRS)` at `:955-958`; the OPEN-E consent gate `:403-408` + src resolution `:686` confirmed unchanged |
| SC4 | CLEANUP-01 dead-code inventory produced: grep-attested 14-item kill-set with repo-wide caller greps proving orphan-after-removal; D-06 integrity gate; D-05 AfKing.poolOf deleted entirely | ✓ VERIFIED | `343-CLEANUP-INVENTORY.md` documents all 14 items with actual file:line and re-run grep commands; `recoverAfKingPool` confirmed 0 external callers; `poolOf`/`withdraw` gated on v48 recovery-leg removal; `game.keeperFundingOf` named as the canonical replacement |
| SC5 | GAS-01 gas-opportunity inventory produced + every cited file:line grep-attested vs `83a84431` with drift corrected | ✓ VERIFIED | `343-GAS-INVENTORY.md` has 11 SCAV candidates (ADVISORY / UNVALIDATED, 345 gas-skeptic named as the gate) + packing candidate under `feedback_security_over_gas` framing; `343-GREP-ATTESTATION.md` overturns 2 RESEARCH claims (`payAffiliate` EXISTS at `:388`; invariant is single-copy at `:18` not `:5 AND :18`) and re-pins all milestone-scope anchors |

**Score: 5/5 truths verified**

---

### Required Artifacts

| Artifact | Plan | Status | Key Evidence |
|----------|------|--------|--------------|
| `343-GREP-ATTESTATION.md` | 343-01 | ✓ VERIFIED | Contains "83a84431"; batchPurchase :1824 drift recorded; handleAffiliate/payAffiliate both recorded; AfKing.sol:43 single-interface finding; `:5`/`:18` double-comment finding (RESEARCH-OVERTURNED: single copy); keeperFunding CONFIRMED-NEW; no-by-construction attestation present |
| `343-SOLVENCY-PROOF.md` | 343-02 | ✓ VERIFIED | All 5 reservation sites walked with source quotes; GO_SWEPT withdraw-guard LOCKED (Section B); SOLVENCY-03 valuation proof (Section C); OPEN-E carry-over (Section D); charged probes list for red-team |
| `343-SOLVENCY-REDTEAM.md` | 343-02 | ✓ VERIFIED | `/contract-auditor` + `/economic-analyst` lenses; GO_SWEPT probe present and NEGATIVE-VERIFIED; ZERO FINDING_CANDIDATE across all 12 probes; USER auto-approved (operator's fully-autonomous direction) |
| `343-CLEANUP-INVENTORY.md` | 343-03 | ✓ VERIFIED | 14-item kill-set; recoverAfKingPool 0 callers confirmed; D-06 integrity gate; D-05 (poolOf deleted entirely → game.keeperFundingOf canonical); IGame payable ABI narrowed to AfKing.sol:43 + comment; new IGame ABI additions listed |
| `343-GAS-INVENTORY.md` | 343-03 | ✓ VERIFIED | gas-scavenger lens declared; 11 SCAV candidates (behavior-identical tagged, ADVISORY/UNVALIDATED); ~9k/buy baseline noted; packing candidate framed with blast-radius and security_over_gas reasoning; 345 gas-skeptic named as gate; no scope-reduction language |
| `343-IMPL-EDIT-ORDER-MAP.md` | 343-04 | ✓ VERIFIED | Final signatures locked with actual file:line; D-01 `BatchBuy.funder` correction recorded (explicit correction to AUTOBUY-02 and PLAN-V54 §4); D-MR-01 src carve-out (keeperFundingOf(src)/:809); handleAffiliate/payAffiliate correction; double-invariant-comment finding; producer-before-consumer edit order with D-06 sequencing; no scope-reduction language |
| `343-SPEC-INDEX.md` | 343-05 | ✓ VERIFIED | Indexes all 6 sibling docs; requirement → doc traceability table (all 5 reqs COVERED); success-criterion → doc table (all 5 SCs COVERED); SPEC verdict section (PASS, DESIGN-LOCKED, SOLVENCY proven, D-07 SURVIVES, GO_SWEPT LOCKED, ZERO contract mutation); 344 hand-off with 4 carry-forwards |

---

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| `343-GREP-ATTESTATION.md` | v53 HEAD `83a84431` | `git diff --numstat` empty + per-anchor grep/Read on live tree | ✓ WIRED — all row greps confirmed against live tree |
| `343-SOLVENCY-PROOF.md` | 5 SOLVENCY-01 reservation sites | claimablePool inclusion (D-CF-03), source-quoted per site | ✓ WIRED — each site walked with source lines quoted |
| `343-SOLVENCY-PROOF.md` | `343-SOLVENCY-REDTEAM.md` | charged-probes list in Section E handed to red-team | ✓ WIRED — redteam dispositions every probe from the list |
| `343-CLEANUP-INVENTORY.md` | AfKing.withdraw / AfKing.poolOf | D-06 gate (orphaned only after StakedStonk:539 + Vault:517 removal) | ✓ WIRED — explicitly recorded with the kill ordering constraint |
| `343-IMPL-EDIT-ORDER-MAP.md` | `343-SOLVENCY-PROOF.md` Section B | GO_SWEPT guard "carried verbatim" into withdrawKeeperFunding signature | ✓ WIRED — withdrawKeeperFunding signature in Section 1.4 has the guard as line 1 |
| `343-IMPL-EDIT-ORDER-MAP.md` | `343-CLEANUP-INVENTORY.md` | D-06 kill-set order carried into edit-order Section 4 | ✓ WIRED — producer-before-consumer order names recovery-leg removal before poolOf/withdraw deletion |
| `343-SPEC-INDEX.md` | All 6 sibling docs + 5 requirements + 5 ROADMAP success criteria | traceability tables | ✓ WIRED — all 6 docs indexed; all 5 reqs and 5 SCs traced to docs |

---

### Requirements Coverage

| Requirement | Plan(s) | Covering Doc(s) | REQUIREMENTS.md Status | Satisfied by Evidence |
|-------------|---------|-----------------|------------------------|-----------------------|
| BATCH-01 | 343-01, 343-04, 343-05 | `343-IMPL-EDIT-ORDER-MAP.md` + `343-GREP-ATTESTATION.md` | ✅ Complete | Final signatures, storage shape, edit-order map locked; all cited anchors grep-attested vs 83a84431 with drift corrected |
| SOLVENCY-01 | 343-02 | `343-SOLVENCY-PROOF.md` (Section A) + `343-SOLVENCY-REDTEAM.md` | ✅ Complete | All 5 reservation sites walked against source; D-07 red-team NEGATIVE-VERIFIED/SAFE_BY_DESIGN on all reservation probes |
| SOLVENCY-03 | 343-02 | `343-SOLVENCY-PROOF.md` (Sections C + D) | ✅ Complete | sDGNRS valuation formula quoted; keeper ETH invisibility proven; OPEN-E carry-over confirmed |
| CLEANUP-01 | 343-03 | `343-CLEANUP-INVENTORY.md` | ✅ Complete | 14-item grep-attested kill-set; repo-wide caller greps re-run and recorded; D-06 gate and D-05 deletion recorded |
| GAS-01 | 343-01, 343-03 | `343-GAS-INVENTORY.md` + `343-GREP-ATTESTATION.md` | ✅ Complete | 11 SCAV candidates + packing candidate with PLAN-V54 §2 framing; all anchors re-pinned |

All 5 Phase-343 requirements are SATISFIED by their delivered docs. REQUIREMENTS.md confirms all 5 at ✅ Complete status.

**Orphaned requirements check:** REQUIREMENTS.md maps 5 requirements to Phase 343 (BATCH-01, SOLVENCY-01, SOLVENCY-03, CLEANUP-01, GAS-01). All 5 appear in plan `requirements` fields and are satisfied. No orphaned requirements.

---

### Anti-Patterns Found

Files modified by Phase 343 are exclusively Markdown planning docs (no `contracts/*.sol`). The deliverable docs were scanned for stub indicators.

| Pattern | Result |
|---------|--------|
| TBD / FIXME / XXX | None found in any deliverable doc |
| Placeholder / "not yet implemented" | None — every section contains substantive content |
| Empty implementations | N/A — paper-only docs, not code |
| Scope-reduction language ("v1", "simplified", "for now") | Explicitly absent; both 343-03-PLAN.md and 343-04-PLAN.md prohibit it and greps confirm compliance |
| "by construction" surviving un-checked | Explicitly guarded against — the GREP-ATTESTATION doc ends with the no-by-construction attestation; two RESEARCH claims were overturned by source verification |

No blockers or warnings.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — paper-only SPEC phase; no runnable entry points. All deliverables are Markdown documents; no code was modified or executed.

---

### Probe Execution

Step 7c: No probes declared in PLAN docs. No conventional `scripts/*/tests/probe-*.sh` files for a SPEC phase. SKIPPED (applicable only to migration/tooling phases or phases with declared probes).

---

### Human Verification Required

None. This is a paper-only SPEC phase. All success criteria are verifiable by document inspection and grep, which were performed above. There are no UI behaviors, real-time interactions, or external service integrations requiring human testing.

---

## Summary

Phase 343 is a paper-only SPEC phase delivering 7 Markdown artifacts (6 content docs + 1 index). Every must-have is met:

- **contracts/ byte-identical to v53 HEAD `83a84431`** — confirmed by empty `git diff --numstat 83a84431 HEAD -- contracts/`. Zero contracts/ mutation throughout the phase.
- **BATCH-01 (SC1):** `343-IMPL-EDIT-ORDER-MAP.md` locks all final signatures, the `keeperFunding` storage shape, and the producer-before-consumer edit order, with four explicit RESEARCH corrections (D-01 funder, D-MR-01 src carve-out, `payAffiliate` canonical symbol, GO_SWEPT guard). `343-GREP-ATTESTATION.md` re-pins every milestone-scope anchor against the live tree, overturning two RESEARCH claims.
- **SOLVENCY-01 (SC2):** `343-SOLVENCY-PROOF.md` walks all 5 free-ETH reservation sites against source, each reserving `claimablePool` (inclusive of the keeper total) with zero edits. The GO_SWEPT withdraw-guard gap is identified and locked. The D-07 red-team in `343-SOLVENCY-REDTEAM.md` disposes all 12 charged probes NEGATIVE-VERIFIED or SAFE_BY_DESIGN — ZERO FINDING_CANDIDATE.
- **SOLVENCY-03 (SC3):** `343-SOLVENCY-PROOF.md` proves the sDGNRS redemption valuation is unchanged and correct; keeper ETH is invisible to sDGNRS's own-balance valuation. The OPEN-E 4-protection carry-over is confirmed with actual file:line.
- **CLEANUP-01 (SC4):** `343-CLEANUP-INVENTORY.md` provides a 14-item grep-attested kill-set with re-run caller grep commands. `recoverAfKingPool` has 0 external callers. `AfKing.poolOf`/`withdraw` are gated on the D-06 integrity ordering. `AfKing.poolOf` is flagged for complete deletion (D-05), with `game.keeperFundingOf(player)` as the canonical replacement.
- **GAS-01 (SC5):** `343-GAS-INVENTORY.md` delivers 11 SCAV candidates (all ADVISORY/UNVALIDATED, 345 gas-skeptic as the sole gate) plus the packing candidate framed under `feedback_security_over_gas` (default = keep the separate mapping). No scope-reduction language. All anchors are the re-pinned lines from `343-GREP-ATTESTATION.md`.

All 5 requirements confirmed ✅ Complete in `REQUIREMENTS.md`. All 5 ROADMAP success criteria traceable to their satisfying docs. Phase goal achieved.

---

_Verified: 2026-05-30_
_Verifier: Claude (gsd-verifier)_
