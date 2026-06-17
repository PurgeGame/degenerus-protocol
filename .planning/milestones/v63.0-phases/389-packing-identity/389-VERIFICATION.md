---
phase: 389-packing-identity
verified: 2026-06-14T20:30:00Z
status: passed
score: 12/12 must-haves verified
overrides_applied: 0
---

# Phase 389: PACKING-IDENTITY Verification Report

**Phase Goal:** Prove the packing and gas refactors are value-/behavior-identical (no silent truncation, no co-resident clobber, no slot collision, no diverging refactor); BOTH finding nets on record.
**Verified:** 2026-06-14T20:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | NET 1 (cross-model council) on record for the STORAGE slice | VERIFIED | `389-01-COUNCIL-NET.md` records both gemini + codex available, 0 skipped; `council/storage.{gemini,codex}.txt` are substantive (25 + 39 lines of source-traced analysis); `storage.council.json` models=["gemini","codex"] skipped=[] |
| 2 | NET 1 (cross-model council) on record for the GASID slice | VERIFIED | `council/gasid.{gemini,codex}.txt` are substantive (47 + 62 lines including the full 30-row selector recompute and 0-mismatch nibble-table differential); `gasid.council.json` models=["gemini","codex"] skipped=[] |
| 3 | Council prompts charged neutrally against frozen subject a8b702a7 with by-design rulings excluded | VERIFIED | Both prompt files reference `a8b702a7` and instruct reading via `git show a8b702a7:contracts/...`; KNOWN-BY-DESIGN exclusion list present; each prompt names its FC leads without pre-stating any verdict; verified by grep and direct content inspection |
| 4 | Both gemini+codex outputs present per slice, or skipped CLIs recorded in council.json | VERIFIED | Both CLIs available on both slices; `skipped: []` in both manifests; all four `.txt` output files non-empty |
| 5 | Subject byte-frozen throughout — `git diff a8b702a7 -- contracts/` empty after the council fan-out | VERIFIED | Confirmed: `git diff a8b702a7 -- contracts/` returns empty; `git status --porcelain contracts/` also empty; all six phase commits (`4c4043ca`, `32556a05`, `b5bf1b6f`, `bbd7721c`, `c25978a0`, `68ff69dd`) touch only `.planning/` docs and `test/REGRESSION-BASELINE-v63.md` — zero `contracts/*.sol` files |
| 6 | NET 2 (Claude adversarial net) on record, independent of the council, for the full STORAGE + GASID surface | VERIFIED | `389-02-CLAUDE-NET.md` is 449 lines; contains per-item attack attempt + provisional verdict for all STORAGE-01..07, GASID-01..05, and FC-389-01..09; explicitly states it attacked independently before reading council outputs; council fold section appears at the end |
| 7 | Every STORAGE-01..07 and GASID-01..05 requirement has an explicit adjudicated verdict in 389-FINDINGS.md | VERIFIED | All 12 req IDs confirmed present in 389-FINDINGS.md (grep check: all 12 PRESENT); each carries a CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict with file:line settling cite |
| 8 | Every FC-389-01..09 lead has an explicit adjudicated verdict | VERIFIED | All 9 FC leads confirmed present in 389-FINDINGS.md (grep check: all 9 PRESENT); verdicts and source cites present for each |
| 9 | STORAGE-04 / FC-389-01 (two-window EV-cap eviction) settled by cursor-lag proof or confirmed finding — not hand-waved | VERIFIED | 389-02-CLAUDE-NET.md §STORAGE-04 carries a 7-site write-trace table plus a two-fact proof: (a) deferred `openBoxes` writes NO EV cap (LootboxModule:567-579), (b) every cap write keys live `level+1`, (c) `level` is +1-monotone (AdvanceModule:1701-1709); conclusion: no third live key reachable; 10 ETH cap cannot be re-earned. 389-FINDINGS.md §2a STORAGE-04 row cites all sites. NOT hand-waved. |
| 10 | STORAGE-07 (capBucketCounts) and GASID-02/03/04 carry concrete equivalence arguments, not assertions | VERIFIED | STORAGE-07: JackpotBucketLib.sol:140-204 trim/remainder derivation; +4 is a test-slack constant not a contract property; 250-clamp double-defense cited. GASID-02: operand-width rule applied per migrated site, address padding equality proved numerically. GASID-03: nibble-table 0x4333222111 equivalence derived + council 0-mismatch recompute over level∈[0,99999]. GASID-04: single-hero roll trace vs baseline two-call; `_farFutureSeed` literal extraction at MintStreakUtils:232. |
| 11 | Any CONFIRMED finding is documented + routed (not fixed in this phase); subject stays byte-frozen | VERIFIED | R-389-01 (STORAGE-06 / FC-389-04): 2 stale test harnesses documented in 389-FINDINGS.md §4a with full fix shape. Marked as routed to a separate gated boundary. No `contracts/*.sol` touched in any phase commit. Box-cursor stale-slot candidate correctly REFUTED by fresh `forge inspect` evidence. |
| 12 | Both nets on record before the verdict; skeptic gate run before any CATASTROPHE/HIGH | VERIFIED | 389-FINDINGS.md §1 contains the both-nets-on-record attestation table per slice; §3 contains the skeptic gate explicitly applied to FC-389-01 and STORAGE-06; outcome = 0 items reach CATASTROPHE/HIGH; the one CONFIRMED item is LOW oracle-integrity |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact | Min Lines | Actual Lines | Status | Key Content Verified |
|----------|-----------|-------------|--------|----------------------|
| `389-01-COUNCIL-PROMPT-STORAGE.md` | 30 | 116 | VERIFIED | References a8b702a7; names FC-389-01..04; KNOWN-BY-DESIGN exclusion list present; neutral vocabulary |
| `389-01-COUNCIL-PROMPT-GASID.md` | 30 | 113 | VERIFIED | References a8b702a7; names FC-389-05..09; per-finding output format present |
| `389-01-COUNCIL-NET.md` | 20 | 121 | VERIFIED | "NET 1 ON RECORD" line confirmed; available/skipped per slice; byte-freeze attestation; raw leads for 389-02 |
| `council/storage.gemini.txt` | — | 25 | VERIFIED | Source-traced STORAGE-01..07 analysis; STORAGE-04 deferred-opens reasoning |
| `council/storage.codex.txt` | — | 39 | VERIFIED | 3 STORAGE-06 stale-harness findings with call sequences and slot cites |
| `council/gasid.gemini.txt` | — | 47 | VERIFIED | GASID-01..05 + FC-389-05..09 full analysis |
| `council/gasid.codex.txt` | — | 62 | VERIFIED | Full 30-row selector table; PriceLookupLib 0-mismatch differential over level∈[0,99999] |
| `council/storage.council.json` | — | 7 | VERIFIED | models=["gemini","codex"], skipped=[] |
| `council/gasid.council.json` | — | 7 | VERIFIED | models=["gemini","codex"], skipped=[] |
| `389-02-CLAUDE-NET.md` | 60 | 449 | VERIFIED | Independent attack pass; cursor-lag proof; STORAGE-06 vs forge inspect; capBucketCounts trim/remainder derivation; council fold section |
| `389-FINDINGS.md` | 80 | 180 | VERIFIED | Both-nets table; 21-item verdict table; skeptic gate; routing §4a; re-attestation §5 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `389-01-COUNCIL-PROMPT-STORAGE.md` | `council/storage.{gemini,codex}.txt` | council.sh --label storage | VERIFIED | council.json records `storage` label; both .txt files present and substantive |
| `389-01-COUNCIL-PROMPT-GASID.md` | `council/gasid.{gemini,codex}.txt` | council.sh --label gasid | VERIFIED | council.json records `gasid` label; both .txt files present and substantive |
| `389-FINDINGS.md` | council/*.txt (NET 1) | both-nets-on-record fold | VERIFIED | §1 attestation table cites 389-01-COUNCIL-NET.md + council/*.txt per slice; each verdict row cites NET 1 result |
| `389-FINDINGS.md` | STORAGE-01..07 + GASID-01..05 + FC-389-01..09 | per-item verdict rows | VERIFIED | All 21 IDs grep-confirmed present; each row has a CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict + file:line cite |
| `389-FINDINGS.md` | STORAGE-04/FC-389-01 cursor-lag proof | STORAGE-04 row | VERIFIED | Cites LootboxModule:567-579/:877/:966/:1089 + AdvanceModule:1701-1709; proof not assertion |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| STORAGE-01 | 389-01, 389-02 | No silent truncating cast | ATTESTED | 389-FINDINGS §2a; 389-02-CLAUDE-NET §STORAGE-01 (10-field enumeration with bounds) |
| STORAGE-02 | 389-01, 389-02 | Masked RMW preserves co-residents | ATTESTED | 389-FINDINGS §2a; mask construction + green baseline pokes |
| STORAGE-03 | 389-01, 389-02 | Cross-module conventions agree | ATTESTED | Single inherited base + single-sourced helpers |
| STORAGE-04 | 389-01, 389-02 | Two-window eviction under cursor lag | ATTESTED | Cursor-lag proof (3 independent facts) |
| STORAGE-05 | 389-01, 389-02 | ABI getters preserved | ATTESTED | sDGNRS + Admin getters confirmed |
| STORAGE-06 | 389-01, 389-02 | No harness hardcodes moved slot | FINDING R-389-01 | 2 stale harnesses confirmed; LOW oracle-integrity; test-only fix routed |
| STORAGE-07 | 389-01, 389-02 | capBucketCounts exactness | ATTESTED | trim/remainder bounds to ≤maxTotal; +4 is test-slack only |
| GASID-01 | 389-01, 389-02 | delegatecall selector + ABI identity | ATTESTED | 30/30 selectors; shared ABI decoder |
| GASID-02 | 389-01, 389-02 | hash1/hash2 preimage identity | ATTESTED | Operand-width rule; 0 sub-word operands |
| GASID-03 | 389-01, 389-02 | PriceLookup nibble-table identity | ATTESTED | 0 mismatches over domain (council + NET 2) |
| GASID-04 | 389-01, 389-02 | trait-roll + _farFutureSeed equivalence | ATTESTED | Single-hero trace + literal extraction |
| GASID-05 | 389-01, 389-02 | No externally-observable behavior change | ATTESTED | Anchored on GASID-01..04 + green baseline 854/0/110 |

REQUIREMENTS.md cross-reference: all 12 IDs confirmed present in REQUIREMENTS.md (lines 25-38, 116-117) with attestation annotations or the R-389-01 finding note. No orphaned requirements.

---

### Anti-Patterns Found

| File | Pattern | Severity | Disposition |
|------|---------|----------|-------------|
| — | TBD/FIXME/XXX scan: NONE found in phase planning docs | — | No blockers |

No placeholder implementations, stub returns, or hardcoded empty data found in the analysis documents. The CONFIRMED finding (R-389-01) is documented and routed per the audit-only posture.

---

### Probe Execution / Behavioral Spot-Checks

**Step 7b: SKIPPED** — this is an audit-documentation phase with no runnable entry points produced. The phase is read-only over the byte-frozen subject; the applicable behavioral check is the git diff attestation (confirmed empty) and the forge baseline reference (854/0/110, green baseline at a8b702a7, carried by reference from Phase 388).

**Byte-freeze verification (the audit's equivalent of a behavioral check):**

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Subject byte-frozen | `git diff a8b702a7 -- contracts/` | EMPTY | PASS |
| Working tree clean | `git status --porcelain contracts/` | EMPTY | PASS |
| Phase commits touch only .planning/ | git show --name-only on all 6 commits | no `contracts/*.sol` in any commit | PASS |
| Council manifests record 0 skipped CLIs | `storage.council.json` + `gasid.council.json` | skipped=[] on both | PASS |

---

### Human Verification Required

None. All must-haves for this audit-documentation phase are verifiable programmatically:
- artifact existence and line counts are mechanical checks
- council manifest structure is inspectable
- git diff for the byte-freeze is deterministic
- REQUIREMENTS.md cross-reference is a grep check
- presence of all 21 verdict IDs in FINDINGS.md is a grep check

The one CONFIRMED finding (R-389-01) is a test-only oracle-integrity item routed to a gated fix boundary per the audit-only posture — no human verification of user-facing behavior is needed for an audit sweep phase.

---

## Gaps Summary

None. All 12 must-haves are verified. The one CONFIRMED finding (R-389-01 — two stale slot-hardcoded test harnesses) is correctly documented and routed per the audit-only posture, not buried or auto-fixed. The phase achieves its goal.

The following items were settled with the required rigor:

- **STORAGE-04 / FC-389-01** (the prime MED-attention target): settled by a 7-site call-graph trace and a two-fact cursor-lag proof, not hand-waved. Both nets converge: REFUTED.
- **STORAGE-07 / capBucketCounts**: settled by a trim/remainder derivation showing Σcapped ≤ maxTotal; the "+4" is proved to be a test-slack constant, not a contract property. Both nets converge: REFUTED.
- **GASID-02/03/04**: each carries a concrete differential or property argument (operand-width enumeration; 0-mismatch recompute over the full nibble-table domain; single-hero roll trace). Both nets converge: REFUTED.

One council divergence (codex's claim that box-cursor harnesses poke moved slots 59/60) was correctly adjudicated by fresh `forge inspect` evidence in NET 2 — the box cursors live at slot 58 offsets 7/13 and slot 59, making the harnesses correct. This is the single NET-1/NET-2 divergence in the phase and was resolved by concrete evidence rather than deference to either model.

---

_Verified: 2026-06-14T20:30:00Z_
_Verifier: Claude (gsd-verifier)_
