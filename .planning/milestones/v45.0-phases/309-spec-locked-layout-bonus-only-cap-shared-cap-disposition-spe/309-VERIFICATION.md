---
phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
verified: 2026-05-20T12:00:00Z
status: passed
score: 5/5
overrides_applied: 0
re_verification: false
---

# Phase 309: SPEC Verification Report

**Phase Goal:** Lock the v45.0 design BEFORE any contract change and grep-verify every call-graph claim against contract HEAD. Produce 309-SPEC.md covering SPEC-01 (packed-slot layout), SPEC-02 (bonus-only cap), SPEC-03 (allocation-time tally + open-apply formula), SPEC-04 (shared-cap disposition backward-trace + SLOAD enumeration). Every cited file:line grep-verified against HEAD; zero "by construction" claims. ZERO `contracts/` + ZERO `test/` mutations.
**Verified:** 2026-05-20T12:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Phase Invariant Check

**`git status --porcelain contracts/ test/`** — returns empty output. ZERO code or test mutations confirmed. The phase invariant holds.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1 — §1 LOCKS the packed-slot layout: field widths (`adjustedPortion = uint64`, NOT `uint96`), exact bit offsets `[0:16]`/`[16:80]`/`[80:104]`/`[104:256]`, pack/unpack helper signatures, baseLevel co-pack (D-02), lootboxDay rejection (D-03), rename to `lootboxPurchasePacked` (D-05), and explicit no-new-slot (net -1 slot) attestation (D-07) | VERIFIED | §1.1 table has all four bit ranges. §1.2 states `uint64`, marks fix-plan `uint96` as SUPERSEDED. §1.3 states net -1 slot. §1.4 records D-03 REJECTED with seed-input reason citing :545. §1.5 records D-04 negative finding. §1.6 names `lootboxPurchasePacked`. §1.7 gives both helper signatures with correct param types. §1.8 is the no-new-slot attestation section. |
| 2 | SC2 — §2 states the bonus-only cap rule exactly as `<= LOOTBOX_EV_NEUTRAL_BPS` early-return returning `(amount * evMultiplierBps) / 10_000`, confirmed for all three callers (open/resolveLootboxDirect/resolveRedemptionLootbox) | VERIFIED | SPEC:313 `if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {`. SPEC:314 `return (amount * evMultiplierBps) / 10_000;`. §2.2 table cites call lines 559 (openLootBox), 675 (resolveLootboxDirect), 711 (resolveRedemptionLootbox) by name. §0.C confirms grep returns exactly four lines: 475 (def) + 559/675/711 = three callers. |
| 3 | SC3 — §3 LOCKS the allocation-time tally (first-deposit + subsequent branches, both Mint and Whale shapes), the openLootBox frozen-apply formula `scaled = mult <= NEUTRAL ? amount*mult/1e4 : adj*mult/1e4 + (amount - adj)` with NO cap SLOAD/SSTORE, and the zero-at-open whole-slot clear | VERIFIED | §3.1 covers both tally branches. §3.2 covers first vs subsequent. §3.3 cites both Mint/Whale shapes including DIV-1 and DIV-2 divergences. §3.4 states formula verbatim with "NO cap SLOAD/SSTORE". §3.4 states whole packed slot cleared in single SSTORE (§1.8), replacing the two separate clears at :570/:571. |
| 4 | SC4 — §4 LOCKS the shared-cap disposition: a word-independence BACKWARD-TRACE (frozen activityScore drives the multiplier, not rngWord) + a COMPLETE in-window SLOAD enumeration for all three callers showing no known-word ordering edge through lootboxEvBenefitUsedByLevel; fix-or-accept disposition ACCEPT documented | VERIFIED | §4.A delivers the four-point backward-trace: (1) activityScore-not-rngWord with line citations :674/:710, per-caller commitment times named (decimator=bucket-at-burn, degenerette=bet-time, redemption=burn-submission), (2) seed uses raw amount :671/:707, (3) purchased boxes allocate pre-word, (4) residual order-steering classified as word-independent accepted self-MEV. §4.B tables cover all 11 openLootBox in-window SLOADs, and 3 each for resolveLootboxDirect and resolveRedemptionLootbox. §4.B.4 confirms `lootboxEvBenefitUsedByLevel` is the SOLE shared mutable — enumerated, not assumed. §4.C ACCEPT verdict. INV-05 and INV-06 both stated preserved. |
| 5 | SC5 — every cited file:line is grep-verified against HEAD (§0 evidence matrix), with zero "by construction" / "single fn reaches all paths" claims | VERIFIED | §0 opens "grep-verified against HEAD `6f0ba2963a10654ba554a8c333c5ee80c54a8349`". §0.K attestation: "Zero 'by construction' / 'single fn reaches all paths' claims — every cited site in §0.A through §0.J is grep-verified above with its matched substring". §4 preamble: "NO 'by construction' / 'single fn reaches all paths' claim is made anywhere in §4". 5 task commits (4f743f68, 4482dfa8, 5b8a9fad, ee2f98d1, 2e525f69) verified in git log. |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/309-.../309-SPEC.md` | Locked v45.0 design spec — §0 call-graph evidence + §1 SPEC-01 + §2 SPEC-02 + §3 SPEC-03 + §4 SPEC-04 | VERIFIED | File exists, 641 lines. All five sections present. Contains `lootboxPurchasePacked`, `lootboxEvBenefitUsedByLevel`, the baseline HEAD hash, and the §0.K no-by-construction attestation. |

---

## Requirements Coverage

| Requirement | Plan | Description | Status | Evidence |
|-------------|------|-------------|--------|----------|
| SPEC-01 | 309-01 | Packed-slot layout locked (uint64, offsets, co-pack, rejection, rename, helpers, no-new-slot) | SATISFIED | §1 fully covers all D-01..D-07 decisions. REQUIREMENTS.md marks `[x] SPEC-01` as Complete. |
| SPEC-02 | 309-01 | Bonus-only cap semantics locked (`<= NEUTRAL` early-return, all three callers) | SATISFIED | §2 covers D-08 exactly. REQUIREMENTS.md marks `[x] SPEC-02` as Complete. |
| SPEC-03 | 309-01 | Allocation-time tally + open-time application locked | SATISFIED | §3 covers D-09 with both tally branches, both module shapes, formula, no-cap-SLOAD-at-open, whole-slot clear. REQUIREMENTS.md marks `[x] SPEC-03` as Complete. |
| SPEC-04 | 309-02 | Shared-cap disposition locked (backward-trace + SLOAD enumeration + ACCEPT verdict) | SATISFIED | §4 (§4.A + §4.B + §4.C) delivers the proof. REQUIREMENTS.md marks `[x] SPEC-04` as Complete. |

All four phase requirement IDs accounted for. No orphaned requirements. IMPL-01..05, INV-01..06, TST-01..05, SWP-01..02, AUDIT-01..02, CLS-01 are correctly mapped to later phases (310-313) and are not in scope for this phase.

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| §0 call-graph evidence | Contract HEAD `6f0ba296` | grep-verified file:line + matched substring per cited ref | VERIFIED | §0.A-§0.J cover all CONTEXT.md canonical refs. §0.J line-number reconciliation records the one divergence (621 `amountEth` vs plan `amount`) and confirms all others matched. §0.K attestation closes the section. |
| §4.A backward-trace | `_lootboxEvMultiplierFromScore(activityScore)` at :674/:710 | grep-verified frozen-score citation proving rngWord-independence | VERIFIED | SPEC:465 cites `:674` with matched substring `uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));`. Same pattern at :710. Both are grep-verified in §0.E. |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | No debt markers (TBD/FIXME/XXX), no stubs, no placeholder returns. The only file modified is 309-SPEC.md (a planning document). |

One intentional divergence was recorded and NOT normalized: the `:621` seed uses `amountEth` not `amount` (BURNIE path). The SPEC records this as a DISCREPANCY box in §0.F and correctly instructs IMPL-05 to preserve `amountEth` at :621. This is correct audit discipline, not an anti-pattern.

---

## Behavioral Spot-Checks

Step 7b: SKIPPED — This is a documentation-only (SPEC) phase. No runnable entry points were produced. The "behavior" to verify is document content, checked exhaustively in the truth verification above.

---

## Probe Execution

Step 7c: SKIPPED — No probes declared or applicable. This is a SPEC-only phase; no scripts/tests/probe-*.sh files exist or are required.

---

## Human Verification Required

None. This is a pure document-content verification phase. All five success criteria are observable programmatically by reading the SPEC file. No UI behavior, real-time behavior, or external service integration is involved.

---

## Gaps Summary

No gaps. All five ROADMAP success criteria are satisfied by the content of `309-SPEC.md`. The phase invariant (zero `contracts/` and zero `test/` mutations) is confirmed by `git status --porcelain`. All four requirement IDs (SPEC-01..04) are fully covered and marked Complete in REQUIREMENTS.md.

---

_Verified: 2026-05-20T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
