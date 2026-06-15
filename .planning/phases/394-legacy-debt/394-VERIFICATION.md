---
phase: 394-legacy-debt
verified: 2026-06-15T03:00:00Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
---

# Phase 394: Legacy Debt Verification Report

**Phase Goal:** the long-deferred v50/v51 surface is swept and its FINDINGS deliverables authored; BOTH finding nets on record.
**Verified:** 2026-06-15T03:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | BOTH nets on record for v50 slice (council NET 1 + Claude NET 2) | VERIFIED | `v50.council.json` `skipped:[]` — both gemini (22 lines) and codex (38 lines) returned substantive traced audits; `394-01-COUNCIL-NET.md` carries the "NET 1 ON RECORD" line; `394-03-CLAUDE-NET.md` is the independent Claude NET 2 with per-item attack + provisional verdicts |
| 2 | BOTH nets on record for v51 slice (council NET 1 = codex; gemini skip documented → 396; Claude NET 2) | VERIFIED | `v51.council.json` `models:["codex"]`, `skipped:["gemini"]` — codex returned a substantive 19-line per-item traced audit; gemini non-responsive documented in `v51.gemini.err` (rc=124 timeout ×2); `394-02-COUNCIL-NET.md` records the skip + carries the re-run flag → 396; `394-04-CLAUDE-NET.md` is the independent Claude NET 2 |
| 3 | DIVERGENT v50 leads RESOLVED: LEGACY-01 claim-time horizon (codex FINDING vs gemini SOUND) — BY-DESIGN with the D-04 doc tie-breaker | VERIFIED | `394-03-CLAUDE-NET.md` §LEGACY-01: the `_activateWhalePass` D-04 doc comment confirmed at `LootboxModule:1483-1485` in the frozen source (`git show a8b702a7`): "D-04 — timing shifts from open-time to claim-time…"; skeptic dual-gate applied — count identical at any level, direction neutral-or-self-harming, not extractable, freeze-independent; gemini "value-equivalent" outcome and codex "horizon shifts" mechanism reconciled under documented intent; `audit/FINDINGS-v50.0.md` records the BY-DESIGN verdict with the settling cite |
| 4 | DIVERGENT v50 leads RESOLVED: LEGACY-02b MINTDIV processed-reset (gemini FINDING vs codex SOUND) — REFUTED with index arithmetic | VERIFIED | `394-03-CLAUDE-NET.md` §LEGACY-02b: gemini's mechanical observation (quadrant `i` restarts per call) confirmed accurate; codex's "lockstep holds" verdict confirmed accurate on COUNT; the settling reason — the quadrant is a random-distribution mechanism over the `address[][256]` jackpot buckets, NOT a per-player ordering invariant — was supplied by NET 2 (both council models missed it); `MintBatchDeterminism.test.js` corroboration confirmed (GREEN 854/0, resets `processed` per call identically to the contract, asserts trait-by-trait over all 256 ids including quadrant bits 6-7) |
| 5 | v51 premise settled: jackpot final-day Pool.Reward deletion is VACUOUS — grep-enumeration of every Pool.Reward reference shows no such path | VERIFIED | `394-04-CLAUDE-NET.md` §LEGACY-04b: `git grep -n -E 'Pool\.Reward\|poolBalances\['` ran over the frozen source and found exactly 6 sites — genesis seeding + Bingo + Degenerette + coinflip bounty + doc comments — NONE in AdvanceModule or JackpotModule; the AdvanceModule final-day affiliate draw confirmed to target `Pool.Affiliate` (`:753-763`), not `Pool.Reward`; JackpotModule has zero sDGNRS pool touch (grep empty); `v51.codex.txt` independently reached the same "no final-day Reward path" conclusion |
| 6 | LEGACY-03 claimBingo freeze-safety/dedup/tier adjudicated — 0 CONFIRMED | VERIFIED | `394-04-CLAUDE-NET.md` §§1-2: backward-trace of every `traitBurnTicket[level]` writer enumerates exactly ONE writer (`MintModule:_raritySymbolBatch @789-812`) running in the swapped/frozen read buffer (`Storage:780-805`, `AdvanceModule:389`); CEI dedup + tier-precedence + empty-pool + gameOver verified bit-for-bit at frozen source; codex NET 1 convergent SOUND |
| 7 | LEGACY-04a BPS rebalance adjudicated — split-conservation verified | VERIFIED | `394-04-CLAUDE-NET.md` §3: BPS re-summed at frozen source `StakedStonk:305-312`: 2000+1000+3000+2000+1000+1000 = 10000 = BPS_DENOM; `INITIAL_SUPPLY = 1e30` divisible by 10_000 (exact integer, dust branch no-op); `transferFromPool` clamps verified (`StakedStonk:548-570`); all three Reward consumers confirmed reading the LIVE pool balance; codex NET 1 convergent SOUND |
| 8 | FINDINGS deliverables authored: `audit/FINDINGS-v50.0.md` (LEGACY-05) and `audit/FINDINGS-v51.0.md` (LEGACY-06) | VERIFIED | Both files exist in `audit/`, tracked by git (confirmed `git ls-files`); `FINDINGS-v50.0.md` = 149 lines authored at commit `dd867ab0`; `FINDINGS-v51.0.md` = 172 lines authored at commit `4e1e73a0`; both carry the executive summary table, per-item adjudicated verdicts, both-nets attestation section, and byte-freeze attestation matching the `audit/FINDINGS-v62.0.md` format |
| 9 | AUDIT-ONLY: no contract source modified | VERIFIED | `git diff a8b702a7 -- contracts/` = 0 lines; `git status --porcelain contracts/` = empty; `git log --oneline a8b702a7..HEAD -- 'contracts/*.sol'` = empty; all four plans read source exclusively via `git show a8b702a7:contracts/…` |
| 10 | By-design rulings respected: claimBingo no-level-guard, AFSUB inclusive boundary, OPEN-E, lootbox timing — not re-flagged | VERIFIED | `audit/FINDINGS-v50.0.md` records the AFSUB inclusive boundary, OPEN-E operator-approval, and whale-pass/WWXRP economics as BY-DESIGN entries in the refuted/by-design section, not as findings; `audit/FINDINGS-v51.0.md` records claimBingo no-level-guard and bingo one-shot dedup as BY-DESIGN; both docs explicitly cite the standing rulings (`[[afking-pass-eviction-inclusive-boundary-intended]]`, `[[open-e-operator-approval-trust-boundary]]`, `[[claimbingo-no-level-guard]]`, `[[lootbox-resolution-timing-by-design]]`) |

**Score:** 10/10 truths verified (includes the 6 LEGACY-req truths and the structural preconditions)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/394-legacy-debt/394-01-COUNCIL-PROMPT-V50.md` | Neutral v50 council prompt (min 45 lines) | VERIFIED | 250 lines; references `a8b702a7`; names LEGACY-01 and LEGACY-02; three numbered break-targets (whale-pass O(1)/freeze, AFSUB/OPEN-E, MINTDIV alignment); KNOWN-BY-DESIGN exclusion list present |
| `.planning/phases/394-legacy-debt/394-01-COUNCIL-NET.md` | v50 NET 1 capture record with "NET 1 ON RECORD" (min 20 lines) | VERIFIED | 244 lines; carries the "NET 1 ON RECORD for the v50 LEGACY-DEBT slice" heading; manifest table; byte-freeze attestation; no codex skip for this run (codex reset confirmed) |
| `.planning/phases/394-legacy-debt/council/v50.gemini.txt` | Substantive gemini output | VERIFIED | 22 lines, non-empty; per-item traces on all 3 break-targets |
| `.planning/phases/394-legacy-debt/council/v50.codex.txt` | Substantive codex output | VERIFIED | 38 lines, non-empty; per-item traces on all 3 break-targets (FINDING on LEGACY-01 horizon, SOUND on MINTDIV, SOUND on AFSUB) |
| `.planning/phases/394-legacy-debt/council/v50.council.json` | Council manifest with available/skipped | VERIFIED | `models:["gemini","codex"]`, `skipped:[]` |
| `.planning/phases/394-legacy-debt/394-02-COUNCIL-NET.md` | v51 NET 1 capture record | VERIFIED | 242 lines; codex on record, gemini skip documented (non-responsive ×2, rc=124); post-responsive gemini re-run flagged → 396 |
| `.planning/phases/394-legacy-debt/council/v51.codex.txt` | Substantive codex v51 output | VERIFIED | 19 lines, non-empty; all 3 break-targets VERIFIED SOUND by codex; stale-comment refinement noted |
| `.planning/phases/394-legacy-debt/council/v51.council.json` | v51 council manifest with gemini in skipped[] | VERIFIED | `models:["codex"]`, `skipped:["gemini"]` |
| `.planning/phases/394-legacy-debt/394-03-CLAUDE-NET.md` | Claude NET 2 for v50 slice | VERIFIED | 313 lines; independent per-item attacks before council fold-in; both divergent leads resolved with settling reasons; byte-freeze attestation |
| `.planning/phases/394-legacy-debt/394-04-CLAUDE-NET.md` | Claude NET 2 for v51 slice | VERIFIED | 349 lines; independent per-item attacks; LEGACY-04b grep-enumeration; council fold-in; byte-freeze attestation |
| `.planning/phases/394-legacy-debt/394-FINDINGS.md` | Consolidated index attesting LEGACY-01..06 | VERIFIED | 96 lines; per-req verdict table rows for LEGACY-01..06 with ATTESTED/DISCHARGED status; both-nets rollup table; 0 CONFIRMED findings across both slices |
| `.planning/phases/394-legacy-debt/394-FINDINGS-V50.md` | Per-slice v50 adjudication | VERIFIED | 134 lines; per-item verdicts for LEGACY-01a/01-horizon/01b/02a/02b; divergent leads resolved |
| `.planning/phases/394-legacy-debt/394-FINDINGS-V51.md` | Per-slice v51 adjudication | VERIFIED | 142 lines; per-item verdicts for LEGACY-03a/03b/04a/04b; final-day premise vacuousness established |
| `audit/FINDINGS-v50.0.md` | Deferred v50 FINDINGS deliverable (LEGACY-05) | VERIFIED | 149 lines; tracked by git (committed `dd867ab0`); executive summary table; per-item section for LEGACY-01/02; lower-severity/INFO; refuted/by-design; both-nets attestation |
| `audit/FINDINGS-v51.0.md` | Deferred v51 FINDINGS deliverable (LEGACY-06) | VERIFIED | 172 lines; tracked by git (committed `4e1e73a0`); executive summary table; per-item section for LEGACY-03/04; lower-severity/INFO; refuted/by-design; both-nets attestation; byte-freeze attestation |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `394-01-COUNCIL-PROMPT-V50.md` | `council/v50.gemini.txt` + `council/v50.codex.txt` | `council.sh --label v50` | WIRED | `394-01-COUNCIL-NET.md` records the fan-out narrative; both `.txt` files non-empty; `v50.council.json` confirms both models ran |
| `394-02-COUNCIL-PROMPT-V51.md` | `council/v51.codex.txt` (gemini skipped) | `council.sh --label v51` | WIRED | `394-02-COUNCIL-NET.md` records codex OK + gemini timeout; `v51.council.json` confirms |
| `394-01-COUNCIL-NET.md` + `394-03-CLAUDE-NET.md` | `audit/FINDINGS-v50.0.md` via `394-FINDINGS-V50.md` | adjudication fold-in | WIRED | `audit/FINDINGS-v50.0.md` "Both-nets attestation" section cites NET 1 = `394-01` and NET 2 = `394-03-CLAUDE-NET.md`; `394-FINDINGS.md` §2 verdict table ties LEGACY-01/02 rows to both NET files |
| `394-02-COUNCIL-NET.md` + `394-04-CLAUDE-NET.md` | `audit/FINDINGS-v51.0.md` via `394-FINDINGS-V51.md` | adjudication fold-in | WIRED | `audit/FINDINGS-v51.0.md` "Both-nets-on-record attestation" table cites NET 1 (codex + gemini skip → 396) and NET 2 (`394-04`); `394-FINDINGS.md` §2 ties LEGACY-03/04 rows to both NET files |
| `394-FINDINGS.md` | REQUIREMENTS.md LEGACY-01..06 | per-req verdict table | WIRED | All 6 LEGACY reqs have explicit ATTESTED/DISCHARGED entries in the consolidated index; REQUIREMENTS.md LEGACY-01..06 all checked (`[x]`) with the specific audit citations |

---

### Data-Flow Trace (Level 4)

Not applicable. This is an audit-documentation phase; no runtime data flows to trace. All artifacts are static analysis documents, not components that render dynamic data.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `audit/FINDINGS-v50.0.md` exists, is non-empty, and is git-tracked | `git ls-files audit/FINDINGS-v50.0.md` | `audit/FINDINGS-v50.0.md` | PASS |
| `audit/FINDINGS-v51.0.md` exists, is non-empty, and is git-tracked | `git ls-files audit/FINDINGS-v51.0.md` | `audit/FINDINGS-v51.0.md` | PASS |
| Byte-freeze holds throughout: contracts unmodified from baseline | `git diff a8b702a7 -- contracts/` | 0 lines | PASS |
| `v50.council.json` skipped list is empty (both models ran) | `cat council/v50.council.json | grep skipped` | `"skipped": []` | PASS |
| `v51.council.json` records gemini in skipped[] | `cat council/v51.council.json | grep skipped` | `"skipped": ["gemini"]` | PASS |
| D-04 doc comment exists at the cited location in frozen source | `git show a8b702a7:contracts/modules/DegenerusGameLootboxModule.sol` lines 1480-1490 | "D-04 — timing shifts from open-time to claim-time…" confirmed at LootboxModule:1483-1485 | PASS |
| Both FINDINGS deliverables committed to git | `git log --oneline --follow -- audit/FINDINGS-v50.0.md` | `dd867ab0 docs(394-03): synthesize both nets + author the deferred v50 FINDINGS` | PASS |

---

### Probe Execution

Step 7c: SKIPPED — no `probe-*.sh` files declared or discoverable for this phase. This is a pure audit-documentation phase with no runnable build scripts.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| LEGACY-01 | 394-01-PLAN.md | v50 whale-pass O(1) deferred-claim path + box-open record | SATISFIED | `394-FINDINGS-V50.md` + `audit/FINDINGS-v50.0.md`: value-equivalence REFUTED (no non-equivalence), claim-time horizon BY-DESIGN (D-04/D-20), box-record freeze REFUTED; REQUIREMENTS.md `[x]` |
| LEGACY-02 | 394-01-PLAN.md | v50 AFSUB pass-gating + OPEN-E re-attest + MINTDIV index alignment | SATISFIED | `394-FINDINGS-V50.md` + `audit/FINDINGS-v50.0.md`: AFSUB as-coded BY-DESIGN-confirmed, MINTDIV quadrant REFUTED (distribution not ordering), count-lockstep exact; REQUIREMENTS.md `[x]` |
| LEGACY-03 | 394-02-PLAN.md | v51 claimBingo color-completion / BingoModule — 3-tier + dedup + freeze | SATISFIED | `394-FINDINGS-V51.md` + `audit/FINDINGS-v51.0.md`: freeze REFUTED (sole writer in swapped/frozen buffer), tier-precedence + dedup + CEI + empty-pool + gameOver all REFUTED; REQUIREMENTS.md `[x]` |
| LEGACY-04 | 394-02-PLAN.md | v51 sDGNRS Pool.Reward rebalance + jackpot final-day Pool.Reward deletion | SATISFIED | `394-FINDINGS-V51.md` + `audit/FINDINGS-v51.0.md`: rebalance REFUTED (BPS sum = 10000 = BPS_DENOM), final-day deletion REFUTED premise VACUOUS (no sDGNRS Reward path in AdvanceModule or JackpotModule); REQUIREMENTS.md `[x]` |
| LEGACY-05 | 394-03-PLAN.md | `audit/FINDINGS-v50.0.md` authored (the deferred v50 deliverable) | SATISFIED | `audit/FINDINGS-v50.0.md` exists, 149 lines, tracked, committed `dd867ab0`; matches FINDINGS-v62.0 format (header, exec summary, per-item, refuted/by-design, both-nets attestation sections); REQUIREMENTS.md `[x]` |
| LEGACY-06 | 394-04-PLAN.md | `audit/FINDINGS-v51.0.md` authored (the deferred v51 deliverable) | SATISFIED | `audit/FINDINGS-v51.0.md` exists, 172 lines, tracked, committed `4e1e73a0`; matches FINDINGS-v62.0 format; byte-freeze attestation section included; REQUIREMENTS.md `[x]` |

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| (none) | — | — | No TBD/FIXME/XXX/PLACEHOLDER/TODO markers found in the phase deliverables or the `audit/FINDINGS-v50.0.md` / `audit/FINDINGS-v51.0.md` files |

The INFO items identified in the audit (the stale `MintBatchDeterminism.test.js` Path-B comment and the two stale `JackpotModule` DGNRS-on-final-day comments) are correctly documented as INFO/doc-only and explicitly ROUTED to a post-audit hygiene pass — they are not unresolved debt markers in the phase deliverables themselves.

---

### Human Verification Required

None. The audit methodology, adjudication logic, and deliverable format are all verifiable from the codebase artifacts. The key source-code citations (D-04 doc comment, `_swapAndFreeze` gate, BPS constants, `Pool.Reward` grep enumeration) were independently re-checked against the frozen source during verification. No visual, real-time, or external-service behavior is claimed.

---

## Gaps Summary

No gaps. All 6 LEGACY requirements (LEGACY-01..06) are satisfied with both nets on record for each slice, explicit per-item verdicts across the three deliverable levels (per-slice internal docs, consolidated index, and the two `audit/FINDINGS-v*.0.md` files), real adjudication reasoning anchored to the frozen source (not pre-stated verdicts), divergent leads resolved with settling reasons, and zero contract source mutation throughout.

The single open carry item — the post-responsive gemini second-source re-run of the v51 codex SOUND verdicts — is correctly documented and routed to Phase 396 (the terminal close). It is not a gap in the phase-394 goal; the single-available-model rule is satisfied by codex + Claude NET 2, and the skip is transparently recorded.

---

_Verified: 2026-06-15T03:00:00Z_
_Verifier: Claude (gsd-verifier)_
