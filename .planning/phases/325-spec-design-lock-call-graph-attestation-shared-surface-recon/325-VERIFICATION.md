---
phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
verified: 2026-05-25T23:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "KEEP-04 owner attribution inverted in 325-ATTEST-KEEP-POOL.md K5 and 325-SPEC.md §0/§1/§2/§3 — corrected via commit 315ee441; docs now match DegenerusAffiliate.sol:243-250 source (bytes32('DGNRS')==owner SDGNRS, bytes32('VAULT')==owner VAULT); two-tier routing primary→SDGNRS/secondary→VAULT USER-LOCKED 2026-05-25"
  gaps_remaining: []
  regressions: []
---

# Phase 325: SPEC Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation Verification Report

**Phase Goal:** SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation. Settle the final shared signatures across DegenerusGame/StakedDegenerusStonk/DegenerusVault, grep-attest every cited file:line vs the v47.0-closure HEAD da5c9d50, and resolve every SPEC-time open item (RFALL-04, KEEP-04/05, POOL-06, BTOMB packing, HERO-04 shape+packing, SWAP-03 jitter source, SWAP-08 acquisition-floor re-confirm) before any patch.
**Verified:** 2026-05-25T23:00:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure (commit 315ee441)

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every cited file:line anchor across the seven v48.0 plan docs has a grep-verified MATCH/SHIFTED/ABSENT verdict resolved at HEAD da5c9d50 | ✓ VERIFIED | 60 anchors attested across 4 ATTEST docs (58 MATCH / 2 immaterial SHIFTED / 0 ABSENT). Spot-checks confirmed: LootboxModule.sol:720 `/(1_000 * 1 ether)`, DegenerusGame.sol:1888 `pullRedemptionReserve`, BurnieCoin.sol:557-567 `vaultEscrow`. Zero IMPL blockers. |
| 2 | The SWAP-08 no-arb inequality is re-derived at the jitter-band CEILING with a numeric margin and a STOP-if-violated rule, and the verdict HELD | ✓ VERIFIED | 325-ATTEST-SWAP.md §A: fractionBps(6)=1500 → 15% face × 110% ceiling = 16.50%; cheapest acquisition ~21% (re-derived from LootboxModule source); margin +4.50pp > 0; STOP rule present and NOT triggered. |
| 3 | 325-SPEC.md settles ONE final signature per multi-item shared construct (R1-R6) with an explicit apply-order | ✓ VERIFIED | SPEC §1 contains R1-R6, each naming co-editing items and intra-file apply-order. Unchanged from initial pass. |
| 4 | Every SPEC-time open item is resolved on paper: RFALL-04, KEEP-05, POOL-06, BTOMB packing, HERO-04 shape+packing; and KEEP-04 produces a correct IMPL instruction | ✓ VERIFIED | KEEP-04 gap CLOSED via commit 315ee441. ATTEST K5 and SPEC §0/§2/§1 R2/§1 R5 now state: bytes32("DGNRS") is owned by SDGNRS (:247-250); bytes32("VAULT") is owned by VAULT (:243-246); wire bytes32("DGNRS") for primary→SDGNRS / secondary→VAULT; do NOT wire bytes32("VAULT"). Source-confirmed at DegenerusAffiliate.sol:243-250/254-255/583-603/692-695. USER-LOCKED 2026-05-25. All other open items (RFALL-04/KEEP-05/POOL-06/BTOMB/HERO-04) unchanged correct. |
| 5 | The matches 0-8 to 0-9 event-range widening is FLAGGED as a frontend/indexer out-of-scope concern | ✓ VERIFIED | SPEC §3 out-of-scope flag present and unchanged. |

**Score:** 5/5 truths verified

---

### KEEP-04 Gap Closure Detail

**Prior gap:** The ATTEST K5 row and SPEC §2 KEEP-04 (plus §0 discretion table, §1 R2, §1 R5) had the affiliate code owner mapping inverted — claiming bytes32("DGNRS") was owned by VAULT when the source shows it is owned by SDGNRS.

**Fix delivered (commit 315ee441):** Both 325-ATTEST-KEEP-POOL.md and 325-SPEC.md were corrected. Verified against source:

| Claim in corrected docs | Source (DegenerusAffiliate.sol) | Match? |
|-------------------------|----------------------------------|--------|
| `affiliateCode[AFFILIATE_CODE_VAULT].owner = ContractAddresses.VAULT` (:243-246) | Lines 243-246 confirm exactly this | ✓ |
| `affiliateCode[AFFILIATE_CODE_DGNRS].owner = ContractAddresses.SDGNRS` (:247-250) | Lines 247-250 confirm exactly this | ✓ |
| VAULT's referral code = "DGNRS" (upline = SDGNRS) at :254 | `:254 _setReferralCode(ContractAddresses.VAULT, AFFILIATE_CODE_DGNRS)` | ✓ |
| SDGNRS's referral code = "VAULT" (upline = VAULT) at :255 | `:255 _setReferralCode(ContractAddresses.SDGNRS, AFFILIATE_CODE_VAULT)` | ✓ |
| 75/20/5 roll at :583-603 for bytes32("DGNRS") player → 75% SDGNRS / 20% VAULT / 5% SDGNRS | Lines 583-603 confirm 75/20/5 winner-takes-all; upline1 of bytes32("DGNRS") owner (SDGNRS) = VAULT (via :255); upline2 of VAULT = SDGNRS (via :254) | ✓ |
| `_vaultReferralMutable("DGNRS") == false` always (:692-695); permanent from purchase #1 | `:692-695` returns false unless `code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT`; "DGNRS" is neither → always false | ✓ |
| bytes32("VAULT") is presale-mutable (`_vaultReferralMutable` returns true during presale) | `AFFILIATE_CODE_VAULT` matches the condition → returns `game.lootboxPresaleActiveFlag()` → mutable during presale | ✓ |
| IMPL instruction: wire bytes32("DGNRS") at DegenerusGame.sol:1778; do NOT wire bytes32("VAULT") | Design decision correct given above — bytes32("DGNRS") routes primary to protocol (SDGNRS), is permanently immutable | ✓ |

**No residual inverted claim found:** A full grep across both corrected files for any remaining "DGNRS owner VAULT" or "primary to VAULT" assertion returned zero hits. Every occurrence consistently states bytes32("DGNRS") → owner SDGNRS (primary revenue), bytes32("VAULT") → owner VAULT (secondary, presale-mutable).

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `325-ATTEST-PFIX-RFALL.md` | Per-anchor grep tables for items 1+2 | ✓ VERIFIED | Unchanged from initial pass; 13 anchors all MATCH; 0 blockers |
| `325-ATTEST-KEEP-POOL.md` | Per-anchor tables for items 3+4 incl. KEEP-04/05/POOL-05 | ✓ VERIFIED | Gap corrected in K5; all owner attributions now source-accurate; K3/K6 and POOL anchors unchanged |
| `325-ATTEST-BTOMB-HERO.md` | Per-anchor tables for items 5+6 incl. BTOMB feasibility + HERO-06 no-leak | ✓ VERIFIED | Unchanged; 26 anchors (24 MATCH / 2 SHIFTED / 0 ABSENT); no regression |
| `325-ATTEST-SWAP.md` | SWAP-08 no-arb re-derivation + SWAP-03 jitter pin + SWAP-06 swap-pop enumeration + units | ✓ VERIFIED | Unchanged; margin +4.5pp holds; STOP not triggered |
| `325-SPEC.md` | Reconciled v48.0 design-lock blueprint with sections 0/1/2/3 | ✓ VERIFIED | KEEP-04 corrected in §0 (discretion table), §1 R2 (affiliate wiring), §1 R5 (VAULT secondary attribution), §2 KEEP-04 (verdict + routing + IMPL instruction); no other sections modified |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| 7 plan docs' cited file:line anchors | contracts/ source at HEAD da5c9d50 | `git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` returns EMPTY; grep live tree | ✓ WIRED | Confirmed zero contracts/.sol drift; spot-checked anchors land correctly |
| fractionBps(6) jitter-ceiling payout (16.5%) | cheapest far-future-entry acquisition (~21%) | re-derivation from PriceLookupLib + LootboxModule source | ✓ WIRED | margin +4.5pp; STOP not triggered |
| ATTEST verdict roll-ups | SPEC §0 and §1 | four ATTEST docs folded into SPEC | ✓ WIRED | C1-C8 corrections propagated; KEEP-04 now consistently correct across all folded locations |
| DegenerusGame.sol items 2+3+7 joint edits | one settled signature + apply-order (R1→R2→R3) | section 1 reconciliation R-rows | ✓ WIRED | R1/R2/R3 jointly cover the file with explicit intra-file order |

---

### Data-Flow Trace (Level 4)

Not applicable: this is a paper-only phase producing planning documents, not code artifacts that render dynamic data.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Zero contracts/*.sol drift from baseline | `git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` | empty (no output) | ✓ PASS |
| KEEP-04 affiliate code owner mapping — bytes32("VAULT").owner | `DegenerusAffiliate.sol:243-246` | `affiliateCode[AFFILIATE_CODE_VAULT] = AffiliateCodeInfo({ owner: ContractAddresses.VAULT, kickback: 0 })` | ✓ PASS |
| KEEP-04 affiliate code owner mapping — bytes32("DGNRS").owner | `DegenerusAffiliate.sol:247-250` | `affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({ owner: ContractAddresses.SDGNRS, kickback: 0 })` | ✓ PASS |
| KEEP-04 cross-referral wiring | `DegenerusAffiliate.sol:254-255` | `:254 _setReferralCode(VAULT, AFFILIATE_CODE_DGNRS)` / `:255 _setReferralCode(SDGNRS, AFFILIATE_CODE_VAULT)` | ✓ PASS |
| KEEP-04 75/20/5 routing | `DegenerusAffiliate.sol:583-603` | Roll 0-14=affiliate(75%), 15-18=upline1(20%), 19=upline2(5%); winner-takes-all | ✓ PASS |
| KEEP-04 permanence of bytes32("DGNRS") | `DegenerusAffiliate.sol:692-695` | `_vaultReferralMutable` returns false unless code==REF_CODE_LOCKED or code==AFFILIATE_CODE_VAULT; "DGNRS" is neither → always immutable | ✓ PASS |
| Corrected docs contain no residual "DGNRS owner VAULT" claim | grep across ATTEST-KEEP-POOL.md + SPEC.md | zero hits for any inverted ownership or "primary to VAULT" claim | ✓ PASS |

---

### Probe Execution

No probes declared for this paper-only SPEC phase.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BATCH-01 | Plans 01+02+03 | Single SPEC design-lock, all 7 items attested, shared surfaces reconciled | ✓ SATISFIED | 4 ATTEST docs + 325-SPEC.md with R1-R6 and edit-order map produced; 60 anchors attested |
| RFALL-04 | Plan 03 | pendingRedemptionEthValue accounting shape decided at SPEC | ✓ SATISFIED | SPEC §2 RFALL-04: D-06 single value, pure-ETH OR pure-stETH, fail-closed |
| KEEP-04 | Plans 01+03 | Confirm VAULT holds a registered affiliate code; confirm correct literal + owner | ✓ SATISFIED | YES — bytes32("DGNRS") / AFFILIATE_CODE_DGNRS is the correct code; owner=SDGNRS (:247-250); two-tier routing primary→SDGNRS/secondary→VAULT; permanent from purchase #1; USER-LOCKED 2026-05-25. Prior inversion corrected in commit 315ee441. |
| KEEP-05 | Plans 01+03 | Confirm autoOpen is existing or new | ✓ SATISFIED | EXISTING — autoOpen renames crankBoxes/crankOpenBox at DegenerusGame.sol:1636/1705 |
| POOL-06 | Plan 03 | Post-gameOver re-stranding decision | ✓ SATISFIED | SPEC §2 POOL-06: D-04 accept-as-minor, no second sweep, documented donor-only residual |

---

### Anti-Patterns Found

No TBD/FIXME/XXX debt markers found in phase documents. No anti-patterns detected. Prior BLOCKER patterns in ATTEST-KEEP-POOL.md and SPEC.md (the inverted owner rows) are resolved in commit 315ee441 and confirmed source-accurate in this re-verification.

---

### Human Verification Required

None. All claims are grep-verifiable against source code. No visual, real-time, or external-service behaviors are involved.

---

## Gaps Summary

No gaps. The single gap from the initial pass (KEEP-04 affiliate code owner mapping inversion) is RESOLVED via commit 315ee441. Both corrected documents (325-ATTEST-KEEP-POOL.md K5 and 325-SPEC.md §0/§1 R2/§1 R5/§2 KEEP-04) now accurately state:

- `bytes32("DGNRS")` (= `AFFILIATE_CODE_DGNRS`) has `owner = ContractAddresses.SDGNRS` — the protocol/"house" contract (distinct from `ContractAddresses.DGNRS`).
- `bytes32("VAULT")` (= `AFFILIATE_CODE_VAULT`) has `owner = ContractAddresses.VAULT`.
- Routing for an AfKing-captured player carrying `"DGNRS"`: **75% → SDGNRS (primary protocol), 20% → VAULT (secondary upline), 5% → SDGNRS**.
- Capture is **permanent from purchase #1** (`_vaultReferralMutable("DGNRS") == false` always).
- IMPL instruction correctly specifies `bytes32("DGNRS")` at `DegenerusGame.sol:1778`; explicitly prohibits `bytes32("VAULT")`.

This is the USER-LOCKED two-tier routing design confirmed 2026-05-25: primary revenue to the protocol contract (SDGNRS), secondary to VAULT.

All other must-haves (60-anchor attestation, SWAP-08 no-arb margin +4.5pp, R1-R6 shared signatures with apply-order, all SPEC-time open items resolved, out-of-scope flag) are unchanged from the initial pass and confirmed intact — no regressions introduced by the KEEP-04 correction. Zero contracts/*.sol mutation confirmed (`git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` returns empty).

---

_Verified: 2026-05-25T23:00:00Z_
_Verifier: Claude (gsd-verifier)_
