---
phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6
verified: 2026-06-06T22:00:00Z
status: passed
score: 5/5
overrides_applied: 0
---

# Phase 375: SPEC — Design-Lock Verification Report

**Phase Goal:** The open design decisions are settled so IMPL authors a fully reconciled diff with zero "by construction" assumptions.
**Verified:** 2026-06-06T22:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The open knobs are LOCKED in writing (D-01 packing sequencing, D-02 AfkingSpent breadth, D-03 curse cap, D-04 protocol-addr skip, D-05 staleness basis, purchaseWith-dead, self-smite) | VERIFIED | `SPEC-V61-DESIGN-LOCK.md` §1 contains a distinct clearly-headed subsection for each of D-01..D-05 with LOCKED value + rationale + affected REQ-IDs; both verification verdicts (purchaseWith DEAD, self-smite HARMLESS-BY-DESIGN) are present citing `375-ANCHOR-REATTESTATION.md`. All 17 keywords confirmed present via grep. |
| 2 | Every cited anchor is re-attested against `2bee6d6f` with drift corrected | VERIFIED | `375-ANCHOR-REATTESTATION.md` covers 29 anchors across 13 files with per-row CONFIRMED/CORRECTED status and git evidence. The 4 material corrections (claimablePool decl at :365, cure host `_purchaseForWith` at :1093, `_recordLootboxMintDay` at :1000, sDGNRS read at :932) are adopted verbatim in `SPEC-V61-DESIGN-LOCK.md` §2 and §3; the SPEC explicitly states it uses the re-attested lines, not the stale `~:NNN` from CONTEXT.md. |
| 3 | The producer-before-consumer edit order is mapped (Track A: PACK accessor before repack before AFPAY; Track B: CURSE before SMITE; CURE-vs-PACK-repack write-after-write cross-check; SOLVENCY accessor location) | VERIFIED | `SPEC-V61-DESIGN-LOCK.md` §4 contains Track A (PACK-01 → PACK-02 → AFPAY-01 → AFPAY-02..06 → AFPAY-07) and Track B (CURSE-01 → CURSE-02 → CURSE-03 → CURSE-04 → CURSE-05 → CURSE-06 → CURSE-07 → SMITE-01) in order, plus an explicit cross-check proving CURE mutates `mintPacked_` curse bits while PACK repack mutates the balances mapping (different slots, no write-after-write conflict). SOLVENCY home pinned to Storage:358/365/851 + PayoutUtils:25/39/63 + GameAfkingModule afking pair. |
| 4 | SPEC-01 requirement is satisfied and accounted for in both plans | VERIFIED | Both `375-01-PLAN.md` and `375-02-PLAN.md` frontmatter list `requirements: [SPEC-01]`. REQUIREMENTS.md marks SPEC-01 `[x]` Complete, phase tracking table shows `SPEC-01 | 375 | SPEC | Complete`. SPEC-01 is the phase's sole requirement. |
| 5 | ZERO `contracts/*.sol` modified by the phase | VERIFIED | `git diff 0deb869c..HEAD -- 'contracts/*.sol'` returns empty. `git status --porcelain contracts/` is clean. All 6 phase commits (f6db9181, 8e4edff5, 797e39f9, efa15561, 26d803af, b5e1d544/24af399a) touch only `.planning/` paths. |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/375-.../375-ANCHOR-REATTESTATION.md` | Re-attested anchor table (every CONTEXT.md anchor with CONFIRMED/CORRECTED line vs `2bee6d6f`) + three verification-item results | VERIFIED | File exists. 29 anchors across 13 files. 4 CORRECTED rows (claimablePool decl :365, `_purchaseForWith` :1093, `_recordLootboxMintDay` :1000, sDGNRS read :932) — exactly the 4 SUMMARY claims. `[215-222]` free-gap proof present (12 mintPacked_ writers shown as field-isolated RMW). All three verification items resolved with verdict + reasoning chain. |
| `.planning/SPEC-V61-DESIGN-LOCK.md` | Design-lock SPEC: locked knobs D-01..D-05 + re-attested anchor table + producer-before-consumer edit-order map + Coverage section. Contains "accessor-first". min_lines: 80 | VERIFIED | File exists. 285 lines (well above the 80-line minimum). Contains all required keywords: D-01..D-05, accessor-first, CURSE_COUNT_CAP = 20, AfkingSpent, _currentMintDay, 2bee6d6f, Track A, Track B, CURSE_COUNT_SHIFT = 215, _settleShortfall, write-after-write, _recordLootboxMintDay, Coverage. §5 Coverage section present with all three SC-mapped. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `SPEC-V61-DESIGN-LOCK.md` anchor citations | `375-ANCHOR-REATTESTATION.md` | The re-attested table folded/cited into the SPEC; pattern `2bee6d6f` | WIRED | The SPEC explicitly states in its preamble: "Every contract anchor cited in this document is grounded on `2bee6d6f` via the re-attested table in §3, **not** the pre-attestation `~:NNN` values in `375-CONTEXT.md`." §2 records the 4 corrections by their baseline lines. §3 embeds the full 29-anchor table sourced from the re-attestation artifact. Both verification verdicts cite `375-ANCHOR-REATTESTATION.md` explicitly. |
| `SPEC-V61-DESIGN-LOCK.md` edit-order map | The 17 contract requirements (AFPAY/PACK/CURSE/SMITE) | Track A + Track B ordered REQ-ID sequences | WIRED | §4 Track A maps PACK-01 → PACK-02 → AFPAY-01 → AFPAY-02..06 → AFPAY-07. §4 Track B maps CURSE-01 → CURSE-02 → CURSE-03 → CURSE-04 → CURSE-05 → CURSE-06 → CURSE-07 → SMITE-01. Every REQ-ID in both tracks present in the document. |

---

### Data-Flow Trace (Level 4)

Not applicable. This is a paper-only SPEC phase — no dynamic data-rendering components. Both artifacts are planning documents with static content.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED (no runnable entry points — paper-only SPEC phase producing `.planning/` documents only).

---

### Probe Execution

Step 7c: SKIPPED (no probe scripts declared in either PLAN, no `scripts/*/tests/probe-*.sh` for a SPEC phase).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SPEC-01 | 375-01-PLAN.md, 375-02-PLAN.md | Re-attest every anchor vs `2bee6d6f`; lock open knobs; map producer-before-consumer edit order; paper-only ZERO `contracts/*.sol` | SATISFIED | REQUIREMENTS.md marks `[x]` and the tracking table shows `Complete`. Both artifacts exist and cover every enumerated item in the SPEC-01 description: anchors re-attested (29 rows, 4 CORRECTED), all 5 knobs locked in writing, edit order mapped as two independent tracks with cross-check, zero contract files touched. |

---

### Anti-Patterns Found

Scanned `375-ANCHOR-REATTESTATION.md` and `SPEC-V61-DESIGN-LOCK.md` for debt markers (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER) and empty-implementation patterns.
<br>

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None found | — | — | — |

No TBD, FIXME, XXX, TODO, HACK, PLACEHOLDER, or stub patterns found in either artifact. The documents are complete specifications with substantive content. No `return null` / `return {}` / `return []` patterns applicable (not code files). No hardcoded empty props applicable.

---

### Human Verification Required

None. This phase's deliverables are planning documents (a re-attestation table and a design-lock SPEC). All three ROADMAP Success Criteria are verifiable by reading the documents against the codebase and the git history:

1. **Knobs locked in writing** — confirmed by reading SPEC §1 against the CONTEXT.md decisions list.
2. **Anchors re-attested** — confirmed by reading the anchor table rows and the 4 CORRECTED entries.
3. **Edit order mapped** — confirmed by reading SPEC §4 Track A / Track B sequences.

No visual UI, real-time behavior, external service, or UX-quality check is involved.

---

### Gaps Summary

No gaps. All five must-haves are verified:

- SC1 (locked knobs): All five D-decisions + both verification verdicts present in SPEC §1 with LOCKED values, rationale, and REQ-IDs.
- SC2 (re-attested anchors): The anchor table exists with 29 rows, 4 CORRECTED rows matching the claimed corrections (claimablePool :365, `_purchaseForWith` :1093, `_recordLootboxMintDay` :1000, sDGNRS read :932). The SPEC adopts these corrected lines rather than the stale CONTEXT.md `~:NNN` values — confirmed by grep.
- SC3 (edit order): Track A and Track B present in SPEC §4 with the full ordered sequences, plus the write-after-write cross-check and the SOLVENCY accessor-invariant location.
- SPEC-01 requirement: Marked `[x]` Complete in REQUIREMENTS.md. Declared in both plan frontmatters. The requirement's enumerated items (anchor re-attestation + 5 knobs + edit-order map + paper-only) are all satisfied.
- Zero contracts/*.sol modified: Git diff confirms the phase diff from `0deb869c..HEAD` touches only `.planning/` paths. Working tree is clean for `contracts/`.

The phase goal — "The open design decisions are settled so IMPL authors a fully reconciled diff with zero 'by construction' assumptions" — is achieved. Every decision is written down with a locked value. Every anchor the IMPL diff will need is grounded on `2bee6d6f`. The edit order is laid out as two independent tracks with an explicit write-after-write safety check. Phase 376 IMPL can author the batched diff mechanically from `SPEC-V61-DESIGN-LOCK.md` without re-deriving any of these items.

---

_Verified: 2026-06-06T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
