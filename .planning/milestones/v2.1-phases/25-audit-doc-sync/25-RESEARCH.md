# Phase 25: Audit Doc Sync - Research

**Researched:** 2026-03-17
**Domain:** Smart contract audit documentation maintenance -- ensuring all audit artifacts reflect v2.1 governance changes
**Confidence:** HIGH

## Summary

Phase 25 is a documentation synchronization task, not a code change task. The entire body of audit documentation (10+ files, ~15,000+ lines) was written against the v1.0/v2.0 codebase. Phase 24 introduced VRF governance (propose/vote/execute replacing `emergencyRecover`) and produced comprehensive verdicts in `v2.1-governance-verdicts.md`. Now all Tier 1 (findings/known-issues), Tier 2 (function audits/parameter reference), and Tier 3 (delta docs/warden refs) audit documents must be updated to reflect the current codebase state.

The research identified 64 stale references across 10 files (matching `emergencyRecover`, `EmergencyRecovered`, `_threeDayRngGap`, and `18 hours`). The `v2.1-governance-verdicts.md` file itself contains 24 of these as legitimate historical references that must be preserved, leaving 40 stale references in 9 other files. Additionally, ~9 new governance function entries are needed in `state-changing-function-audits.md`, governance constants must be added to `v1.1-parameter-reference.md`, and FINAL-FINDINGS-REPORT.md needs structural updates to its severity distribution, findings, and phase/plan counts.

**Primary recommendation:** Tier the work by document importance -- Tier 1 docs (FINAL-FINDINGS-REPORT.md, KNOWN-ISSUES.md) first since C4A wardens read these, then Tier 2 (state-changing-function-audits.md, parameter-reference.md), then Tier 3 (footnotes in delta/warden/regression docs), with a final cross-reference validation sweep.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOCS-01 | FINAL-FINDINGS-REPORT.md updated -- M-02 status changed, governance findings added, plan/phase counts updated | Research catalogs all M-02 stale text (8 hits), identifies severity distribution changes (Medium->Low for M-02, new known issues from GOV-07/VOTE-03/WAR-01/WAR-02/WAR-06), and documents plan/phase count deltas (13->15 phases, 72->80 plans, 56+8+26=90 requirements) |
| DOCS-02 | KNOWN-ISSUES.md updated -- emergencyRecover refs replaced, governance known issues added | Research identifies 2 stale refs in KNOWN-ISSUES.md and catalogs 5 new known issues from Phase 24 verdicts |
| DOCS-03 | state-changing-function-audits.md updated -- ~8 new, ~7 updated, ~5 verified | Research enumerates exact functions: 8 new (propose, vote, _executeSwap, _voidAllActive, anyProposalActive, circulatingSupply, threshold, canExecute), 3 updated (emergencyRecover->removed, updateVrfCoordinatorAndSub, _handleGameOverPath), 1 new in DegenerusStonk (unwrapTo), and identifies DegenerusGameStorage.lastVrfProcessedTimestamp |
| DOCS-04 | parameter-reference.md updated -- governance constants added | Research identifies 5 constants (ADMIN_STALL_THRESHOLD, COMMUNITY_STALL_THRESHOLD, COMMUNITY_PROPOSE_BPS, PROPOSAL_LIFETIME, BPS) plus threshold decay schedule |
| DOCS-05 | Tier 2 reference docs updated -- economic flow, VRF lifecycle, admin function refs | Research identifies stale refs in v1.2-rng-data-flow.md (3 hits), v1.2-rng-functions.md (2 hits), EXTERNAL-AUDIT-PROMPT.md (1 hit) |
| DOCS-06 | Tier 3 footnotes added -- delta audit docs, warden reports | Research identifies stale refs in regression-check-v2.0.md (13 hits), warden-01-contract-auditor.md (1 hit), warden-cross-reference-v2.0.md (3 hits) |
| DOCS-07 | Cross-reference integrity verified -- zero stale refs for target terms | Research provides baseline: 64 total hits across 10 files, 24 in governance-verdicts.md (legitimate), 40 in other files needing update/annotation |
</phase_requirements>

## Standard Stack

This phase involves no code changes or library dependencies. The "stack" is the set of audit documents and their formats.

### Audit Document Inventory

| Document | Lines | Tier | Stale Refs | Update Type |
|----------|-------|------|-----------|-------------|
| FINAL-FINDINGS-REPORT.md | 451 | 1 | 8 | Major rewrite of M-02, add findings, update counts |
| KNOWN-ISSUES.md | 51 | 1 | 2 | Replace M-02 section, add 5 governance known issues |
| state-changing-function-audits.md | 13,598 | 2 | 7 | Add ~9 new entries, update ~3 existing, mark 1 removed |
| v1.1-parameter-reference.md | 737 | 2 | 0 | Add governance constants section |
| v1.2-rng-data-flow.md | ~730 | 2 | 3 | Annotate stale VRF flow refs |
| v1.2-rng-functions.md | ~300 | 2 | 2 | Annotate stale function refs |
| EXTERNAL-AUDIT-PROMPT.md | ~260 | 2 | 1 | Update time constants |
| regression-check-v2.0.md | ~170 | 3 | 13 | Add v2.1 annotations (historical doc) |
| warden-01-contract-auditor.md | ~300 | 3 | 1 | Add v2.1 annotation |
| warden-cross-reference-v2.0.md | ~110 | 3 | 3 | Add v2.1 annotations |
| v2.1-governance-verdicts.md | ~2340 | N/A | 24 | NO CHANGES -- legitimate historical refs |

### Update Tier Strategy

| Tier | Documents | Priority | Rationale |
|------|-----------|----------|-----------|
| Tier 1 | FINAL-FINDINGS-REPORT.md, KNOWN-ISSUES.md | Highest | C4A wardens read these first; must be accurate |
| Tier 2 | state-changing-function-audits.md, v1.1-parameter-reference.md | High | Function-level reference docs used in external audit |
| Tier 2b | v1.2-rng-data-flow.md, v1.2-rng-functions.md, EXTERNAL-AUDIT-PROMPT.md | Medium | Supporting reference docs |
| Tier 3 | regression-check-v2.0.md, warden-01, warden-cross-ref | Lower | Historical docs -- annotate, don't rewrite |
| Validate | All audit docs | Final | Grep sweep confirms zero stale refs |

## Architecture Patterns

### Pattern 1: Historical Document Annotation

**What:** For Tier 3 docs that describe historical audit results (regression-check-v2.0.md, warden reports), do NOT delete stale references. Instead, add inline annotations:

**When to use:** Documents that describe past findings/analyses that referenced now-removed functionality.

**Example:**
```markdown
> **v2.1 Note:** `emergencyRecover` was removed in v2.1 and replaced by governance
> (propose/vote/execute). This historical reference is preserved for audit traceability.
> See v2.1-governance-verdicts.md for current behavior.
```

This preserves audit history while making clear the reference is stale.

### Pattern 2: Active Document Replacement

**What:** For Tier 1 and Tier 2 docs that serve as current reference material, fully replace stale content with current governance equivalents.

**When to use:** FINAL-FINDINGS-REPORT.md, KNOWN-ISSUES.md, state-changing-function-audits.md, parameter-reference.md.

**Example for M-02 rewrite:**
```markdown
### M-02: VRF Coordinator Swap Security (Downgraded to Low)

**Original Severity:** MEDIUM (v1.0-v2.0)
**Revised Severity:** LOW (v2.1, governance mitigation)
**Status:** Mitigated by v2.1 governance -- downgraded from Medium to Low
```

### Pattern 3: New State-Changing Function Audit Entry Format

**What:** Follow the exact format of existing entries in state-changing-function-audits.md for new governance functions.

**When to use:** All ~9 new function entries (propose, vote, _executeSwap, _voidAllActive, anyProposalActive, circulatingSupply, threshold, canExecute, unwrapTo).

**Template:**
```markdown
### `functionName(params)` [visibility]

| Field | Value |
|-------|-------|
| **Signature** | `function ...` |
| **Visibility** | external/public/internal |
| **Mutability** | state-changing / view |
| **Parameters** | ... |
| **Returns** | ... |

**State Reads:** ...
**State Writes:** ...
**Callers:** ...
**Callees:** ...
**ETH Flow:** ...
**Invariants:** ...
**NatSpec Accuracy:** ...
**Gas Flags:** ...
**Verdict:** CORRECT (verified in Phase 24 governance audit)
```

### Anti-Patterns to Avoid

- **Wholesale deletion of stale content in historical docs:** Warden reports and regression checks are audit artifacts. Deleting references destroys traceability. Always annotate, never delete.
- **Updating v2.1-governance-verdicts.md:** This file's references to `emergencyRecover` are INTENTIONAL -- it documents the transition FROM the old system. Do not modify.
- **Changing line references in historical docs:** v1.0/v2.0 docs reference file:line numbers from those versions. Adding "v2.1 note: this line has changed" is correct; updating the line number would be wrong (it references the version that was audited).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stale reference detection | Manual reading of 15,000+ lines | `grep -r` / `rg` for known stale terms | Exact match search is reliable and fast |
| New function audit content | Write from scratch | Extract from v2.1-governance-verdicts.md + contract source | Phase 24 already verified all governance functions; reuse verdict evidence |
| Severity distribution | Manually count | Derive from REQUIREMENTS.md + STATE.md decisions | All verdicts are recorded in State decisions |

## Common Pitfalls

### Pitfall 1: Missing the "18 hours" Ambiguity

**What goes wrong:** Grepping for "18 hours" matches legitimate non-VRF-retry references (e.g., "119d 18h" in endgame timing).
**Why it happens:** "18 hours" appears in timing descriptions unrelated to the VRF retry timeout.
**How to avoid:** Contextual review of each "18 hours" hit. Only the VRF retry timeout (now 12h) references are stale. The `v1.1-endgame-and-activity.md` references to "18h" in endgame timelines are unrelated to VRF.
**Warning signs:** Changing "18h" in endgame/activity contexts would introduce errors.

Specific legitimate "18 hours" references (DO NOT change):
- `v1.1-endgame-and-activity.md:446` -- "119d 18h" is an endgame timeline, not VRF
- `v1.1-endgame-and-activity.md:456` -- "364d 18h" is an endgame timeline, not VRF

Stale "18 hours" references (DO change/annotate):
- `state-changing-function-audits.md:2318` -- "VRF pending and < 18 hours" -> now 12 hours
- `FINAL-FINDINGS-REPORT.md:157` -- "VRF retry (18h timeout)" -> now 12h
- `EXTERNAL-AUDIT-PROMPT.md:246` -- "Time constants: ... 18 hours" -> now 12 hours
- `v1.2-rng-functions.md:291` -- "revert if <18h or retry if >=18h" -> now 12h

### Pitfall 2: _threeDayRngGap Still Exists in DegenerusGame.sol

**What goes wrong:** Someone removes all `_threeDayRngGap` references from docs, not realizing the function still exists in DegenerusGame.sol as a private helper for the `rngStalledForThreeDays()` public view.
**Why it happens:** XCON-04 verdict says "_threeDayRngGap removal verified" but this refers to removal from governance paths, not from all code.
**How to avoid:** Keep references to `_threeDayRngGap` in docs that describe DegenerusGame's monitoring functions. Remove/annotate only in docs that describe governance/emergency recovery paths.
**Warning signs:** `rngStalledForThreeDays()` still calls `_threeDayRngGap` per DegenerusGame.sol.

### Pitfall 3: I-22 is RESOLVED (Verified)

**What:** I-22 states `_threeDayRngGap()` is "duplicated in DegenerusGame + AdvanceModule." Research verified via grep that `_threeDayRngGap` is **completely removed from AdvanceModule** (zero matches in `contracts/modules/DegenerusGameAdvanceModule.sol`). The function only exists in DegenerusGame.sol now.
**Action required:** I-22 must be marked as RESOLVED in FINAL-FINDINGS-REPORT.md. The duplication no longer exists.

### Pitfall 4: Plan/Phase Count Arithmetic

**What goes wrong:** FINAL-FINDINGS-REPORT.md states "72 plans examining approximately 16,500 lines" and "13-phase manual code review." These must be updated to include Phase 24 (8 plans) and Phase 25 (7 plans).
**Why it happens:** Multiple locations reference these counts.
**How to avoid:** Search for "72 plans", "13-phase", "16,500 lines" and update all instances. New totals: 15 phases (or 16 with v2.0), 87 plans (72+8+7), ~16,500 lines (unchanged -- governance is same codebase).

### Pitfall 5: emergencyRecover Entry in state-changing-function-audits.md

**What goes wrong:** The `emergencyRecover` entry (line 12998) is left as-is, implying the function still exists.
**Why it happens:** It's a large file and the entry is deep in DegenerusAdmin section.
**How to avoid:** Mark the entry as REMOVED with a v2.1 annotation pointing to the governance replacement (propose/vote/_executeSwap). Do NOT delete the entry -- it provides historical audit evidence.

### Pitfall 6: Severity Distribution in FINAL-FINDINGS-REPORT.md

**What goes wrong:** The executive summary says "Medium: 1" and "Low: 0". After v2.1, M-02 is downgraded to Low, and multiple new known issues exist at Low severity.
**Why it happens:** The severity distribution section is near the top and easy to overlook in a focused edit.
**How to avoid:** Update the severity distribution block:
- Medium: 2 (WAR-01, WAR-02)
- Low: 4 (M-02 downgraded + GOV-07 + VOTE-03 + WAR-06)

### Pitfall 7: I-09 Rationale is Stale

**What goes wrong:** I-09 says wireVrf lacks re-init guard, "intentional, `emergencyRecover` reuses this path." With emergencyRecover removed, this rationale is wrong.
**How to avoid:** Update I-09 to note that wireVrf is now truly one-time deployment only. Governance uses `updateVrfCoordinatorAndSub` (not wireVrf) for coordinator rotation.

## Code Examples

No code changes in this phase. All work is documentation.

### New Governance Constants for parameter-reference.md

Source: DegenerusAdmin.sol (verified against contract source)

| Constant | Value | Human | Purpose | File:Line |
|----------|-------|-------|---------|-----------|
| ADMIN_STALL_THRESHOLD | 20 hours (72000s) | 20h | VRF stall duration for admin to propose | DegenerusAdmin.sol:297 |
| COMMUNITY_STALL_THRESHOLD | 7 days (604800s) | 7d | VRF stall duration for community to propose | DegenerusAdmin.sol:300 |
| COMMUNITY_PROPOSE_BPS | 50 | 0.5% | Min sDGNRS share of circulating to propose (community path) | DegenerusAdmin.sol:303 |
| PROPOSAL_LIFETIME | 168 hours (604800s) | 7d | Max lifetime before proposal expires | DegenerusAdmin.sol:306 |
| BPS | 10000 | 100% | BPS denominator for vote threshold calculations | DegenerusAdmin.sol:309 |
| PRICE_COIN_UNIT | 1000 ether | 1000 BURNIE | BURNIE conversion constant | DegenerusAdmin.sol:284 |
| LINK_ETH_FEED_DECIMALS | 18 | 18 decimals | Expected oracle decimals | DegenerusAdmin.sol:287 |
| LINK_ETH_MAX_STALE | 1 days | 24h | Max oracle staleness | DegenerusAdmin.sol:290 |

### Threshold Decay Schedule

| Elapsed | Threshold (BPS) | Human |
|---------|----------------|-------|
| 0-24h | 6000 | 60% |
| 24-48h | 5000 | 50% |
| 48-72h | 4000 | 40% |
| 72-96h | 3000 | 30% |
| 96-120h | 2000 | 20% |
| 120-144h | 1000 | 10% |
| 144-168h | 500 | 5% |
| 168h+ | 0 | 0% (expired, unreachable in practice) |

### New Governance Functions for state-changing-function-audits.md

8 new entries needed in DegenerusAdmin.sol section:

| Function | Visibility | Mutability | Key Detail |
|----------|-----------|------------|------------|
| `propose(address, bytes32)` | external | state-changing | Creates governance proposal, increments activeProposalCount |
| `vote(uint256, bool)` | external | state-changing | Records vote, checks execute/kill conditions |
| `_executeSwap(uint256)` | internal | state-changing | Executes VRF coordinator swap, voids other proposals |
| `_voidAllActive(uint256)` | internal | state-changing | Marks all active proposals as Killed |
| `anyProposalActive()` | external | view | Returns activeProposalCount > 0 |
| `circulatingSupply()` | public | view | sDGNRS totalSupply minus undistributed pools |
| `threshold(uint256)` | public | view | Returns decaying threshold for proposal |
| `canExecute(uint256)` | external | view | Checks if proposal meets execution conditions |

1 new entry needed in DegenerusStonk.sol section:

| Function | Visibility | Mutability | Key Detail |
|----------|-----------|------------|------------|
| `unwrapTo(address, uint256)` | external | state-changing | Creator-only DGNRS unwrap with VRF stall guard (>20h blocks) |

### Functions Needing Update (not new, but stale content)

| Function | File | What Changed |
|----------|------|-------------|
| `emergencyRecover(address, bytes32)` | DegenerusAdmin.sol | REMOVED in v2.1 -- mark as removed, annotate |
| `updateVrfCoordinatorAndSub(address, uint256, bytes32)` | AdvanceModule | `_threeDayRngGap` guard removed; now called by governance `_executeSwap` not `emergencyRecover` |
| `_handleGameOverPath(...)` | AdvanceModule | Now calls `anyProposalActive()` to pause death clock |
| `rngGate(...)` | AdvanceModule | VRF retry timeout changed from 18h to 12h |
| `wireVrf(...)` (NatSpec note) | DegenerusGame.sol | I-09 note references `emergencyRecover` reusing this path -- now governance uses `updateVrfCoordinatorAndSub` instead |

### New Known Issues from Phase 24

From STATE.md decisions:

| ID | Severity | Description | Source |
|----|----------|-------------|--------|
| GOV-07 | Low | `_executeSwap` CEI violation -- theoretical sibling-proposal reentrancy via malicious coordinator. Requires pre-existing governance control. | Phase 24-04 |
| VOTE-03 | Low | uint8 `activeProposalCount` overflow at 256 proposals wraps to 0, unpausing death clock. ~$3,000 cost. | Phase 24-05 |
| WAR-01 | Medium | Compromised admin key + 7-day community absence can swap VRF coordinator. DGVE/sDGNRS separation is primary defense. | Phase 24-07 |
| WAR-02 | Medium | 5% cartel at day-6 threshold feasible with concentrated sDGNRS. Single reject voter blocks. | Phase 24-07 |
| WAR-06 | Low | Admin spam-propose can bloat `_voidAllActive` gas cost. Per-proposer cooldown recommended. | Phase 24-07 |

### v2.1 Severity Distribution (Updated)

| Severity | Count | Details |
|----------|-------|---------|
| Critical | 0 | Unchanged |
| High | 0 | Unchanged |
| Medium | 2 | WAR-01 (compromised admin + community absence), WAR-02 (colluding cartel at low threshold) |
| Low | 4 | M-02 (downgraded from Medium), GOV-07 (_executeSwap CEI), VOTE-03 (uint8 overflow), WAR-06 (spam-propose) |
| Informational | 8+ | 8 from v1.0-v1.2, 2 from v2.0, plus governance informationals (XCON-03 boundary, WAR-03 oscillation, WAR-04 unwrapTo timing, WAR-05 post-execute loop) |

Note: The planner must decide whether WAR-01/WAR-02 are "new findings" or "known issues" (they are already documented in v2.1-governance-verdicts.md as KNOWN-ISSUE). They should be listed in both FINAL-FINDINGS-REPORT.md and KNOWN-ISSUES.md.

## State of the Art

| Old Approach (v1.0-v2.0) | Current Approach (v2.1) | Impact on Docs |
|---------------------------|-------------------------|----------------|
| `emergencyRecover` single-admin call | `propose/vote/execute` governance | All M-02 text rewritten |
| `_threeDayRngGap` in AdvanceModule as governance guard | `lastVrfProcessedTimestamp` 20h/7d threshold | updateVrfCoordinatorAndSub entry updated |
| `_threeDayRngGap` duplicated in Game + AdvanceModule | `_threeDayRngGap` only in DegenerusGame.sol (I-22 RESOLVED) | I-22 finding marked resolved |
| 18h VRF retry timeout | 12h VRF retry timeout | RNG-06, rngGate refs updated |
| `EmergencyRecovered` event | `ProposalCreated/VoteCast/ProposalExecuted/ProposalKilled` events | Event refs updated |
| No death clock pause during governance | `anyProposalActive()` pauses death clock | _handleGameOverPath entry updated |
| No unwrapTo stall guard | unwrapTo blocked during >20h VRF stall | New function entry added |
| Medium severity for M-02 | Low severity for M-02 | Severity distribution updated |

## Open Questions

1. **Exact plan/phase count arithmetic**
   - What we know: v1.0-v1.2 = 72 plans, Phase 24 = 8 plans, Phase 25 = 7 plans (per ROADMAP)
   - What's unclear: Whether "13-phase" in FINAL-FINDINGS-REPORT refers to original 7 phases or includes v2.0 phases
   - Recommendation: The current text says "13-phase manual code review" (phases 1-7 + 19-23 = 12 phases, but audit methodology header says "13 phases"). Adding Phase 24-25 makes 15 phases total. Verify exact count during execution by checking the methodology table in FINAL-FINDINGS-REPORT.md.

2. **I-09 (wireVrf re-initialization) rationale update**
   - Verified: `_executeSwap` calls `gameAdmin.updateVrfCoordinatorAndSub()`, NOT `wireVrf()`.
   - Action: I-09 rationale should change from "intentional, emergencyRecover reuses this path" to "wireVrf is deployment-only; governance coordinator rotation uses updateVrfCoordinatorAndSub".

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hardhat + Mocha/Chai |
| Config file | hardhat.config.js |
| Quick run command | `npx hardhat test --grep "pattern"` |
| Full suite command | `npx hardhat test` |

### Phase Requirements -> Test Map

This phase has NO code changes, so there are no automated tests to run. Validation is entirely grep-based:

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOCS-01 | FINAL-FINDINGS-REPORT.md updated | manual + grep | `grep -c 'emergencyRecover\|EmergencyRecovered' audit/FINAL-FINDINGS-REPORT.md` (expect 0) | N/A |
| DOCS-02 | KNOWN-ISSUES.md updated | manual + grep | `grep -c 'emergencyRecover' audit/KNOWN-ISSUES.md` (expect 0) | N/A |
| DOCS-03 | state-changing-function-audits.md updated | manual + grep | `grep -c 'propose\|_executeSwap' audit/state-changing-function-audits.md` (expect >0) | N/A |
| DOCS-04 | parameter-reference.md updated | manual + grep | `grep -c 'ADMIN_STALL_THRESHOLD\|COMMUNITY_STALL_THRESHOLD' audit/v1.1-parameter-reference.md` (expect >0) | N/A |
| DOCS-05 | Tier 2 refs updated | manual + grep | `grep -rn 'emergencyRecover\|18 hours' audit/v1.2-*.md audit/EXTERNAL-AUDIT-PROMPT.md` (expect annotations or 0) | N/A |
| DOCS-06 | Tier 3 footnotes added | manual + grep | `grep -c 'v2.1 Note\|v2.1 note' audit/regression-check-v2.0.md audit/warden-*.md` (expect >0) | N/A |
| DOCS-07 | Zero stale refs | grep | See validation command below | N/A |

DOCS-07 validation command (must return 0 non-annotated hits):
```bash
grep -rn 'emergencyRecover\|EmergencyRecovered\|_threeDayRngGap\|18 hours' audit/ --include='*.md' \
  | grep -v 'v2.1-governance-verdicts.md' \
  | grep -v 'v2.1 Note' \
  | grep -v 'v2.1 note' \
  | grep -v 'endgame' \
  | grep -v 'v2.1 RESOLVED' \
  | grep -v 'REMOVED in v2.1' \
  | grep -v 'rngStalledForThreeDays'
```

Note: The grep exclusions account for: (1) governance-verdicts.md is intentional, (2) annotated refs contain "v2.1 Note/note", (3) endgame timing refs are unrelated, (4) resolved findings, (5) removed function markers, (6) `_threeDayRngGap` in DegenerusGame monitoring still exists.

### Sampling Rate
- **Per task commit:** Grep for stale terms in modified files
- **Per wave merge:** Full grep sweep across all audit docs
- **Phase gate:** DOCS-07 full sweep returns zero non-annotated, non-governance-verdicts hits

### Wave 0 Gaps
None -- no test infrastructure needed for documentation-only phase.

## Stale Reference Inventory (Complete)

This section provides the exact file:line inventory the planner needs to ensure nothing is missed.

### FINAL-FINDINGS-REPORT.md (8 hits -- Tier 1, REPLACE)

| Line | Term | Context | Action |
|------|------|---------|--------|
| 73 | emergencyRecover | M-02 description | Rewrite M-02 for governance |
| 76 | emergencyRecover | Scenario A description | Rewrite for governance |
| 79 | emergencyRecover | Scenario B description | Rewrite for governance |
| 89 | emergencyRecover + EmergencyRecovered | Mitigating factors | Replace with governance event references |
| 92 | EmergencyRecovered | Status section | Replace |
| 96 | emergencyRecover | GAMEOVER fallback | Rewrite fallback context |
| 115 | emergencyRecover | I-09 finding | Update I-09 rationale |
| 157 | 18h | RNG-06 requirement | Change to 12h |

### KNOWN-ISSUES.md (2 hits -- Tier 1, REPLACE)

| Line | Term | Context | Action |
|------|------|---------|--------|
| 13 | emergencyRecover | M-02 description | Rewrite for governance |
| 21 | EmergencyRecovered | Mitigating factors | Replace with governance events |

### state-changing-function-audits.md (7 hits -- Tier 2, UPDATE/ANNOTATE)

| Line | Term | Context | Action |
|------|------|---------|--------|
| 2318 | 18 hours | rngGate invariants | Change to 12 hours |
| 2346 | _threeDayRngGap | updateVrfCoordinatorAndSub reads | Update for v2.1 changes |
| 2363 | _threeDayRngGap | updateVrfCoordinatorAndSub callees | Update |
| 2377 | _threeDayRngGap | NatSpec accuracy | Update |
| 2382 | _threeDayRngGap | Gas flags | Update |
| 12998 | emergencyRecover | Function entry header | Mark as REMOVED in v2.1 |
| 13002-13043 | emergencyRecover (full entry) | Function body | Annotate as removed |

### regression-check-v2.0.md (13 hits -- Tier 3, ANNOTATE)

Historical document. Add v2.1 annotations, do not rewrite.

### warden-01-contract-auditor.md (1 hit -- Tier 3, ANNOTATE)

Line 192: QA-03 finding about emergencyRecover try/catch. Add annotation that emergencyRecover was removed in v2.1.

### warden-cross-reference-v2.0.md (3 hits -- Tier 3, ANNOTATE)

Historical document. Add v2.1 annotations.

### v1.2-rng-data-flow.md (3 hits -- Tier 2b, ANNOTATE)

| Line | Term | Context | Action |
|------|------|---------|--------|
| 665 | _threeDayRngGap | updateVrfCoordinatorAndSub flow | Annotate: guard removed in v2.1, governance uses lastVrfProcessedTimestamp |
| 675 | _threeDayRngGap | Guards section | Annotate |
| 718 | _threeDayRngGap | Entry Point Matrix | Annotate |

### v1.2-rng-functions.md (2+1 hits -- Tier 2b, ANNOTATE)

| Line | Term | Context | Action |
|------|------|---------|--------|
| 33 | _threeDayRngGap | AdvanceModule function table | Mark as REMOVED from AdvanceModule in v2.1 |
| 128 | _threeDayRngGap | DegenerusGame function table | Keep (function still exists in Game for rngStalledForThreeDays monitoring view) |
| 291 | 18h | rngGate timeout description | Change to 12h |

### EXTERNAL-AUDIT-PROMPT.md (1 hit -- Tier 2b, UPDATE)

Line 246: "Time constants: 912 days, 365 days, 18 hours, 3 days, 30 days" -> update to include: "12 hours (VRF retry), 20 hours (admin stall), 7 days (community stall), 168 hours (proposal lifetime)"

## Sources

### Primary (HIGH confidence)
- DegenerusAdmin.sol contract source -- governance function signatures, constants, logic
- DegenerusGameAdvanceModule.sol contract source -- verified `_threeDayRngGap` fully removed (zero grep matches), modified functions, lastVrfProcessedTimestamp writes, 12h retry timeout
- DegenerusStonk.sol contract source -- unwrapTo function with VRF stall guard (>20h)
- v2.1-governance-verdicts.md -- all Phase 24 verdicts, finding IDs, severity assessments
- STATE.md -- all Phase 24 decisions with requirement verdicts

### Secondary (MEDIUM confidence)
- Line numbers in stale reference inventory -- verified by grep at research time, but may shift if docs are edited between research and execution

## Metadata

**Confidence breakdown:**
- Document inventory: HIGH -- exhaustive grep scan, all files enumerated
- Stale reference locations: HIGH -- verified by ripgrep with exact line numbers
- New function list: HIGH -- verified against contract source
- Severity distribution: HIGH -- derived from STATE.md Phase 24 decisions
- I-22 resolution: HIGH -- verified via grep that `_threeDayRngGap` is absent from AdvanceModule
- Plan/phase count arithmetic: MEDIUM -- "13-phase" reference needs verification during execution

**Research date:** 2026-03-17
**Valid until:** Indefinitely (documentation task, not library-dependent)
