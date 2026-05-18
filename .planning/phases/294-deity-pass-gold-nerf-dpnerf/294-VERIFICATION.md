---
phase: 294-deity-pass-gold-nerf-dpnerf
verified: 2026-05-17T23:00:00Z
status: gaps_found
score: 4/6 must-haves verified
overrides_applied: 0
gaps:
  - truth: "BURNIE near-future coin jackpot path covered by the gold-tier nerf (virtualCount = 1 on color==7)"
    status: failed
    reason: "_awardDailyCoinToTraitWinners (L1822-1905) has its own inline winner-selection loop with its own virtualCount computation at L1864-1867 (the v41 max(len/50, 2) formula). This function does NOT call _randTraitTicket. payDailyCoinJackpot (L1773) calls _awardDailyCoinToTraitWinners directly. The gold nerf in _randTraitTicket L1732-1737 is unreachable from the BURNIE near-future path."
    artifacts:
      - path: "contracts/modules/DegenerusGameJackpotModule.sol"
        issue: "_awardDailyCoinToTraitWinners at L1864-1867 still contains the v41 unpatched formula: virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2 — with no gold-tier branch. The function is self-contained and never delegates to _randTraitTicket."
    missing:
      - "Apply the gold-tier branch (if (((trait_i >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }) at L1864-1867 in _awardDailyCoinToTraitWinners. Alternatively, extract the virtualCount logic to a shared helper so both paths stay in sync."
  - truth: "Intentional EV reduction covers all 8 colors at all callsites including BURNIE"
    status: failed
    reason: "DPNERF-03 requires deity earns less total EV across all 8 colors. Because _awardDailyCoinToTraitWinners retains the v41 max(len/50, 2) formula, the BURNIE near-future coin jackpot path still over-extracts EV for gold-tier deity holders at the same 3-7% rate as v41. The EV-reduction claim is false for the BURNIE path."
    artifacts:
      - path: "contracts/modules/DegenerusGameJackpotModule.sol"
        issue: "L1864-1867 in _awardDailyCoinToTraitWinners: the un-nerfed v41 gold-tier behavior persists on this path (coins paid out via payDailyCoinJackpot)."
    missing:
      - "The gold-tier branch fix must be applied to _awardDailyCoinToTraitWinners so that the deity EV reduction holds for the full BURNIE near-future path. The ETH paths through _randTraitTicket are correctly nerfed; only the BURNIE path is missing the fix."
---

# Phase 294: Deity-Pass Gold Nerf (DPNERF) Verification Report

**Phase Goal:** Single-function body change in `DegenerusGameJackpotModule.sol:1671-1710` `_randTraitTicket` — when winning trait color is gold (`(trait >> 3) & 7 == 7`) set `virtualCount = 1` (skip the existing `max(len/50, 2)` floor); common-tier path unchanged. Both ETH + BURNIE coin jackpot paths covered via single function change. Intentional EV reduction (no common-tier compensation per D-42N-DEITY-EV-01). Ship DPNERF-01..06 with zero storage / ABI changes.

**Verified:** 2026-05-17T23:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                        | Status    | Evidence                                                                                                                                                                                     |
|----|--------------------------------------------------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1  | Gold-tier branch `if (((trait >> 3) & 7) == 7) { virtualCount = 1; }` exists inside `_randTraitTicket`       | ✓ VERIFIED | `contracts/modules/DegenerusGameJackpotModule.sol` L1732: `if (((trait >> 3) & 7) == 7) {` L1733: `virtualCount = 1;`. Sits inside the `if (deity != address(0))` guard at L1731.             |
| 2  | BURNIE near-future coin jackpot path covered by the gold nerf                                                 | ✗ FAILED  | `_awardDailyCoinToTraitWinners` (L1822-1905) has its own inline virtualCount at L1864-1867 (`virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2`) and does NOT call `_randTraitTicket`. The gold nerf at L1732-1737 is unreachable from the BURNIE path. |
| 3  | Common-tier `else` branch in `_randTraitTicket` byte-identical to v41 `max(len/50, 2)`                        | ✓ VERIFIED | `contracts/modules/DegenerusGameJackpotModule.sol` L1734-1737: `else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }`. Matches v41 formula verbatim.                   |
| 4  | No common-tier compensation logic added anywhere (intentional EV reduction)                                    | ✓ VERIFIED | No new commons-boost anywhere in the contract per grep; `_randTraitTicket` else branch retains v41 formula. Code review (`294-REVIEW.md`) confirmed: `else` branch byte-for-byte verbatim.  |
| 5  | Deity earns less total EV across **all** 8 colors (BURNIE path included)                                       | ✗ FAILED  | ETH paths through `_randTraitTicket` are nerfed. The BURNIE near-future coin path via `payDailyCoinJackpot` → `_awardDailyCoinToTraitWinners` retains the un-nerfed v41 formula at L1864-1867. Gold-tier deity EV is unchanged on the BURNIE path.                     |
| 6  | Storage byte-identical to v41 close `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`                                | ✓ VERIFIED | `294-01-MEASUREMENT.md` §2 STATUS: PASS — `forge inspect storageLayout` diff EMPTY at both module + storage targets (171-line byte-identical). §6 grep-proof confirms identical SSTORE/SLOAD counts pre/post.                                                          |
| 7  | Public ABI byte-identical to v41 close                                                                         | ✓ VERIFIED | `294-01-MEASUREMENT.md` §4 STATUS: PASS — `forge inspect methodIdentifiers` diff EMPTY; 10/10 public selectors UNCHANGED; `payDailyCoinJackpot` `0xdbedb1c1` UNCHANGED.                    |
| 8  | Decision anchors (D-42N-GOLD-FLOOR-01, D-42N-DEITY-EV-01, D-42N-PATH-COVERAGE-01, D-294-CALLER-UNIFORM-01, D-294-NATSPEC-01) recorded BEFORE the contract patch | ✓ VERIFIED | `294-01-DESIGN-INTENT-TRACE.md` committed at `109fc9e1`; contract patch committed at `47936e0c`. Git log confirms `109fc9e1` precedes `47936e0c` by multiple commits. All 5 anchors present in trace doc (confirmed by SUMMARY self-check). |

**Score:** 4/6 must-haves verified (Truths 2 and 5 failed; Truths 1, 3, 4, 6, 7, 8 verified — DPNERF-01, DPNERF-03, DPNERF-04, DPNERF-05, DPNERF-06 pass; DPNERF-02 fails)

---

### Required Artifacts

| Artifact                                                                  | Expected                                                          | Status     | Details                                                                                                                                                |
|---------------------------------------------------------------------------|-------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `contracts/modules/DegenerusGameJackpotModule.sol`                        | Gold-tier branch in `_randTraitTicket`; storage/ABI byte-identical | ✓ VERIFIED | Gold-tier branch at L1732-1737 matches locked shape. 4 callsites verified (L698, L988, L1296, L1399). BURNIE path NOT covered — see gap.               |
| `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md` | DPNERF-06 4-section trace + 5 anchors                    | ✓ VERIFIED | 206 lines. All 5 anchors present. All 4 trace sections (i-iv) present. Committed at `109fc9e1` before contract patch `47936e0c`.                       |
| `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md`  | §2 storage PASS + §4 ABI PASS + §5 bytecode delta + §6 grep-proof  | ✓ VERIFIED | §2 STATUS: PASS; §4 STATUS: PASS; §5 empirical +86 bytes USER-ACCEPTED; §6 STATUS: PASS. All placeholders populated.                                  |

---

### Key Link Verification

| From                                   | To                                               | Via                                       | Status      | Details                                                                                                                                                                                              |
|----------------------------------------|--------------------------------------------------|-------------------------------------------|-------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `_randTraitTicket` gold-tier branch     | `virtualCount = 1`                               | `if (((trait >> 3) & 7) == 7)` at L1732  | ✓ WIRED     | L1732-1733 confirmed in source.                                                                                                                                                                      |
| `_randTraitTicket` else-branch          | v41 `max(len/50, 2)` formula                     | L1734-1737                                | ✓ WIRED     | L1735: `virtualCount = len / 50;` L1736: `if (virtualCount < 2) virtualCount = 2;`                                                                                                                  |
| ETH callsites (L698, L988, L1296, L1399)| gold-tier nerf via `_randTraitTicket`            | 4 confirmed callsite greps               | ✓ WIRED     | All 4 callsites confirmed by grep; single function-body change reaches all 4 by construction.                                                                                                       |
| `payDailyCoinJackpot` (L1773)           | gold-tier nerf                                   | `_awardDailyCoinToTraitWinners` → `_randTraitTicket` | ✗ NOT_WIRED | `payDailyCoinJackpot` calls `_awardDailyCoinToTraitWinners` (L1789). `_awardDailyCoinToTraitWinners` has its own inline virtualCount at L1864-1867 — the v41 un-nerfed formula. It does NOT call `_randTraitTicket`. The gold nerf is not reached from the BURNIE path. |
| `294-01-DESIGN-INTENT-TRACE.md`        | committed before contract patch                  | git chronology                            | ✓ WIRED     | `109fc9e1` (trace) appears before `47936e0c` (contract patch) in git log.                                                                                                                           |

---

### Data-Flow Trace (Level 4)

Phase 294 is a contract-source modification phase. Level 4 data-flow trace not applicable (no dynamic-rendering artifact). The gap identified in Level 3 (key-link verification) is more fundamental: the BURNIE path does not pass through the patched function.

---

### Behavioral Spot-Checks

| Behavior                                                                 | Command                                                                                                        | Result             | Status   |
|--------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|--------------------|----------|
| Gold-tier branch exists in `_randTraitTicket`                            | `grep -n "if (((trait >> 3) & 7) == 7)" contracts/modules/DegenerusGameJackpotModule.sol`                     | 1 match @ L1732    | ✓ PASS   |
| `virtualCount = 1` (gold path)                                           | `grep -n "virtualCount = 1" contracts/modules/DegenerusGameJackpotModule.sol`                                  | 1 match @ L1733    | ✓ PASS   |
| 4 `_randTraitTicket` callsites at expected lines                         | `grep -n "_randTraitTicket" contracts/modules/DegenerusGameJackpotModule.sol`                                  | L698, L988, L1296, L1399, L1707 | ✓ PASS   |
| `_awardDailyCoinToTraitWinners` calls `_randTraitTicket`                 | `grep "_randTraitTicket" <_awardDailyCoinToTraitWinners body L1822-1905>`                                      | 0 matches          | ✗ FAIL   |
| BURNIE path has un-nerfed `max(len/50, 2)` inline at `_awardDailyCoinToTraitWinners` | `sed -n '1864,1867p' contracts/modules/DegenerusGameJackpotModule.sol`                          | v41 formula present at L1864-1867 | ✗ FAIL   |
| No prohibited refactors (GOLD_COLOR constant, local color cache)         | `grep -n "GOLD_COLOR\|uint8 color = " contracts/modules/DegenerusGameJackpotModule.sol`                        | 0 matches          | ✓ PASS   |
| No history language in patched NatSpec                                   | `grep -n "TBD\|FIXME\|XXX\|TODO\|previously\|formerly" contracts/modules/DegenerusGameJackpotModule.sol`       | 0 matches          | ✓ PASS   |
| Comment-block 5-line two-tier shape present at L1721-1725                | `sed -n '1721,1725p' contracts/modules/DegenerusGameJackpotModule.sol`                                         | 5-line two-tier shape confirmed | ✓ PASS   |

---

### Probe Execution

Phase 294 is a contract-source modification phase with no project-defined `scripts/*/tests/probe-*.sh` probes. The compile attestation and MEASUREMENT.md attestations serve as the phase's runnable verification surface. TST-DPNERF-01..05 runtime probes are deferred to Phase 295.

---

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                                                                    | Status        | Evidence                                                                                                                                                                                                  |
|-------------|-------------|------------------------------------------------------------------------------------------------------------------------------------------------|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| DPNERF-01   | 294-02      | `_randTraitTicket` body adds gold-tier check; `virtualCount = 1` on color==7; common-tier `max(len/50, 2)` unchanged                           | ✓ SATISFIED   | Gold-tier branch at L1732-1737 in `_randTraitTicket`. Both arms verified verbatim. Locked shape matches CONTEXT.md `<specifics>`.                                                                         |
| DPNERF-02   | 294-02      | Both ETH + BURNIE coin jackpot paths covered; single function change; no callsite flag                                                          | ✗ BLOCKED     | ETH paths (L698, L988, L1296, L1399) satisfied by construction. BURNIE path fails: `payDailyCoinJackpot` → `_awardDailyCoinToTraitWinners` (L1822) does NOT call `_randTraitTicket`; has own inline virtualCount at L1864-1867 retaining the v41 un-nerfed formula. |
| DPNERF-03   | 294-02      | Intentional EV reduction; no common-tier compensation; deity earns less total EV across all 8 colors                                           | ✗ BLOCKED     | ETH paths: correctly nerfed. BURNIE path: gold-tier deity EV unchanged (un-nerfed v41 formula in `_awardDailyCoinToTraitWinners`). The "total EV across all 8 colors" reduction claim does not hold across the BURNIE path.                                      |
| DPNERF-04   | 294-02      | Storage byte-identical; zero new slots / SSTORE / SLOAD                                                                                        | ✓ SATISFIED   | `294-01-MEASUREMENT.md` §2 STATUS: PASS — `forge inspect storageLayout` EMPTY diff at both targets. §6 grep-proof confirms identical SSTORE/SLOAD counts.                                                |
| DPNERF-05   | 294-02      | Public ABI byte-identical; all 10 selectors UNCHANGED vs v41 close                                                                             | ✓ SATISFIED   | `294-01-MEASUREMENT.md` §4 STATUS: PASS — `forge inspect methodIdentifiers` EMPTY diff; 10/10 selectors UNCHANGED.                                                                                       |
| DPNERF-06   | 294-01      | DPNERF-scope decision anchors recorded BEFORE the contract patch per `feedback_design_intent_before_deletion.md`                               | ✓ SATISFIED   | `294-01-DESIGN-INTENT-TRACE.md` committed at `109fc9e1` (docs, before `47936e0c` contract patch). All 5 anchors present (D-42N-GOLD-FLOOR-01, D-42N-DEITY-EV-01, D-42N-PATH-COVERAGE-01, D-294-CALLER-UNIFORM-01, D-294-NATSPEC-01). 4 trace sections (i-iv) confirmed. |

DPNERF-01, DPNERF-04, DPNERF-05, DPNERF-06: SATISFIED.
DPNERF-02, DPNERF-03: BLOCKED — root cause is the same: `_awardDailyCoinToTraitWinners` has an independent inline virtualCount that bypasses `_randTraitTicket`.

---

### Anti-Patterns Found

| File                                                       | Line      | Pattern                                                                                | Severity | Impact                                |
|------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------|----------|---------------------------------------|
| `contracts/modules/DegenerusGameJackpotModule.sol`         | L1864-1867 | `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2` — un-nerfed v41 formula in `_awardDailyCoinToTraitWinners` | 🛑 Blocker | BURNIE near-future coin jackpot path retains gold-tier over-extraction EV; defeats the stated goal of DPNERF-02 + DPNERF-03. |

---

### Out-of-Scope Verification

`git diff 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4..HEAD -- contracts/storage/ contracts/modules/DegenerusGameDegeneretteModule.sol contracts/modules/DegenerusGameWhaleModule.sol contracts/DegenerusDeityPass.sol contracts/modules/DegenerusGameBoonModule.sol contracts/interfaces/ test/ KNOWN-ISSUES.md` shows changes in `contracts/storage/DegenerusGameStorage.sol` (Phase 290 MINTCLN), `test/edge/HeroOverrideWeightedRoll.test.js` and related test helpers (Phase 293 TST-HRROLL). These predate Phase 294. Phase 294's commit `47936e0c` only modified `contracts/modules/DegenerusGameJackpotModule.sol` and `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md` — confirmed via `git show --name-only 47936e0c`. No Phase-294-caused out-of-scope regressions.

`_pickSoloQuadrant` at L1098-1115 (post-patch numbering) is untouched by Phase 294 — the established gold-tier idiom `((traits[i] >> 3) & 7) == 7` at L1105 is preserved as precedent.

**Bytecode-delta disposition:** `294-01-MEASUREMENT.md` §5 records the +86 byte empirical delta with explicit `🚨 BYTECODE-DELTA EXCEEDS ANALYTICAL ESTIMATE` flag and USER-ACCEPTED disposition. The bytecode flag is not a verification failure per the acceptance criteria.

---

### Human Verification Required

None beyond the identified gap. The BURNIE path failure is fully observable via static analysis — no runtime execution needed to confirm the missing gold-tier branch in `_awardDailyCoinToTraitWinners`.

---

### Gaps Summary

**1 root-cause gap blocking 2 requirements (DPNERF-02 + DPNERF-03).**

The phase design-intent trace (§iv Path-Coverage Trade-Offs in `294-01-DESIGN-INTENT-TRACE.md`) and the CONTEXT.md callsite enumeration treated the BURNIE path as resolving "through callsite 2 or 3 depending on the BURNIE distribution sub-shape." This architectural claim was incorrect: `_awardDailyCoinToTraitWinners` is a self-contained winner-selection loop that inlines its own virtual-entry allocation at L1864-1867 and does not delegate to `_randTraitTicket`. The single-function-body-change strategy that achieves coverage uniformity across the 4 ETH callsites does NOT achieve coverage of the BURNIE near-future path.

**Root cause:** `_awardDailyCoinToTraitWinners` was written as a specialized inlined loop (with its own level-sampling, storage access, and virtualCount computation) rather than a wrapper that calls `_randTraitTicket`. The BURNIE path is NOT architecturally reachable through `_randTraitTicket`.

**Fix required:** Apply the gold-tier branch to `_awardDailyCoinToTraitWinners` L1864-1867 — replacing `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2;` inside the `if (deity != address(0))` block with `if (((trait_i >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }`. This is an additional `+8/-2` hunk in the same file, analogous to the `_randTraitTicket` patch. No ABI / storage impact (same function is private, inline local variables only).

**DPNERF-01, DPNERF-04, DPNERF-05, DPNERF-06: all pass.** The `_randTraitTicket` patch shape is correct; the design-intent trace is in place; storage and ABI are byte-identical. The gap is bounded to the BURNIE-path miss.

---

_Verified: 2026-05-17T23:00:00Z_
_Verifier: Claude (gsd-verifier)_
