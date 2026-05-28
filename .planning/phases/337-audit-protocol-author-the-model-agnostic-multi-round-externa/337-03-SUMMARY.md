---
phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa
plan: 03
subsystem: audit-deliverable
tags: [rng-audit-kit, packaging, chunk-manifest, model-agnostic, package-only, docs]
requires:
  - "audit/rng-audit-kit/RNG-AUDIT-KIT.md (protocol head + context pack — 337-01/02)"
  - "audit/rng-audit-kit/337-ANCHOR-ATTESTATION.md (HEAD-resolved anchor table)"
provides:
  - "audit/rng-audit-kit/CHUNK-MANIFEST.md — contract-corpus chunking map (inventory + sizes + 3 groups + Storage-travels rule)"
  - "RNG-AUDIT-KIT.md model-agnostic feeding recipe (Gemini/GPT one-feed + ChatGPT-web 3-group chunked) + explicit PACKAGE-ONLY/future-cycle scope"
affects:
  - "Phase 337-04 validation (manifest-sum lint + self-containment + no-answer-key greps over audit/rng-audit-kit/)"
tech-stack:
  added: []
  patterns:
    - "Facts-not-verdicts: corpus sizes + grouping are neutral locators; no freeze conclusion"
    - "Storage-travels-with-every-chunk: DegenerusGameStorage.sol re-attaches to each chunked group"
    - "Layout B: paste-into-model artifact (kit) separated from human-ops manual (manifest)"
key-files:
  created:
    - "audit/rng-audit-kit/CHUNK-MANIFEST.md"
  modified:
    - "audit/rng-audit-kit/RNG-AUDIT-KIT.md"
decisions:
  - "Inventory Lines/Chars written as RAW integers (no thousands separators) so they match wc -l/-c literally — required for the 337-04 manifest-sum lint to re-derive (the comma-formatted form failed the facade live-line-count grep)"
  - "DegenerusQuests.sol INCLUDED in the corpus (RESEARCH §5 A3 default) — named rollLevelQuest VRF consume site; total ≈280K tokens"
  - "Feeding recipe added a per-model window table (RESEARCH §6) for operator usability; the two appended sections are complete at 33 section-lines (no padding to the soft min_lines:40 floor — would degrade the tight-artifact intent)"
metrics:
  duration: "~10 min"
  completed: "2026-05-28"
  tasks: 2
  files: 2
  commits: 2
---

# Phase 337 Plan 03: Author the Model-Agnostic Feeding Recipe + Chunk Manifest (Packaging Layer) Summary

Completed the RNGAUDIT-04 packaging layer of the external-LLM RNG-audit kit: a neutral operator chunk-manifest that inventories the frozen post-v50 contract corpus with live HEAD sizes and defines the three feeding groups (with Storage travelling in every chunked group), plus a model-agnostic feeding recipe and an explicit PACKAGE-ONLY / future-cycle scope statement appended to the paste-into-model kit. Layout B is now complete: `RNG-AUDIT-KIT.md` is the paste-into-model artifact (protocol + context pack + recipe), `CHUNK-MANIFEST.md` is the operator's attachment manual.

## What Was Built

### Task 1 — `audit/rng-audit-kit/CHUNK-MANIFEST.md` (commit `5860bb67`)
The operator's chunking/feeding manual, kept separate from the kit so the paste-into-model artifact carries no human-ops noise. Three sections:
- **Corpus Inventory** — a table over the 18-file core set + `DegenerusQuests.sol` (File · Lines · Chars · ~Tokens · Group). Lines/Chars are the live `wc -l`/`wc -c` values re-run against HEAD `0060d4d4` (contracts byte-frozen at the v50.0 IMPL point `e756a6f3`), written as **raw integers** so the 337-04 manifest-sum lint re-derives. ~Tokens = ceil(Chars/3.6), basis stated. SUBTOTAL (18-file core) = 20595 L / 925382 C / ~257060 tok; TOTAL-with-Quests = 22510 L / 1007094 C / ~279758 tok.
- **Chunk Groups** — the three groups defined exactly: RNG-CORE (Storage + Advance + Mint + Lootbox + Quests; ~114297 tok; labelled "the irreducible core — never split it"), CONSUME-B (Jackpot + Degenerette + Decimator + Whale + Boon + GameOver + MintStreakUtils + PayoutUtils; ~72472 tok), FACADE+PERIPHERAL-C (DegenerusGame facade + AfKing + BurnieCoin + BurnieCoinflip + DegenerusJackpots + GNRUS; ~92989 tok). Group sums add to 279758 = the TOTAL row.
- **The Storage-Travels Rule** — DegenerusGameStorage.sol (~23729 tok) must re-attach to every chunked group because the delegatecall facade puts a slot's writer and reader in different files; effective 3-group cost ≈ 327216 tok (279758 + 2×23729) stated so the operator expects the repetition. Plus an operator checklist.

### Task 2 — feeding recipe + PACKAGE-ONLY scope appended to `RNG-AUDIT-KIT.md` (commit `c94820d7`)
Two sections after the context pack:
- **`## Feeding the Contracts (Model-Agnostic Recipe)`** — a per-model window table (Gemini 2.5 Pro / GPT-5.5 / GPT-4.1 / GPT-5.4 / ChatGPT-web, RESEARCH §6) and four feeding paths: (a) Gemini 2.5 Pro recommended primary one-feed (R1→R4 in one session); (b) GPT-5.5/GPT-4.1 one-feed, file-upload preferred; (c) ChatGPT-web 3-group chunked RNG-CORE→CONSUME-B→FACADE+PERIPHERAL-C re-attaching Storage each group, R1-after-all-three or per-group-then-reconcile; (d) general persist-R1-catalog note. References `CHUNK-MANIFEST.md` by name for the file list/sizes; contracts attached BY PATH. Names the frozen post-v50 surface (O(1) whale-pass claim, MintModule advance realignment, AfKing pass-gating views) as files to feed — with no freeze conclusion stated.
- **`## Scope — PACKAGE-ONLY`** — states unmissably that authoring the kit is the deliverable; running it through Gemini/ChatGPT + triaging output is a FUTURE cycle, OUT of v50.0. Uses the literal tokens `PACKAGE-ONLY` and `future cycle`.

## Verification Results

Plan `<verification>` + `<success_criteria>` + 337-04 lints (all clean):

| Check | Result |
|-------|--------|
| Task 1 automated (manifest exists + 3 groups + Quests + facade live line count + self-containment) | PASS |
| Every inventory row's raw Lines+Chars match `wc` at HEAD AND appear literally in the manifest | ALL_ROWS_MATCH_WC_AT_HEAD |
| Group token sums add up (114297 + 72472 + 92989 = 279758 = TOTAL row) | PASS |
| Task 2 automated (Gemini + ChatGPT + RNG-CORE + PACKAGE-ONLY + future cycle present; self-containment) | PASS |
| Recipe references CHUNK-MANIFEST by name (5×) + RNG-CORE group (key_link) | PASS |
| Self-containment over both files (`FINDINGS-v[0-9]\|audit/FINDINGS\|RNGLOCK-CATALOG`) | 0 (clean) |
| No-answer-key, strict line-131 net (`safe by construction\|no (writer )?escape\|the invariant holds`) over both files | 0 (clean) |
| No-answer-key, wider RESEARCH §8 net (`is frozen because\|we (found\|verified\|confirmed)`) over the kit | 0 (clean) |
| CRITICAL-LESSON stale pre-v50 literals (`:716`, `1250-1260`, `OPEN_NORMAL_GAS_UNIT`) in the two authored files | 0 (clean) |
| Zero `contracts/*.sol` modified (working tree + vs e756a6f3) | empty (clean) |

Note: `OPEN_NORMAL_GAS_UNIT` appears in the pre-existing `337-ANCHOR-ATTESTATION.md` (its DRIFT INDEX legitimately documents the constant as DELETED) — that file was NOT touched by this plan and is the source-of-truth telling later plans not to cite the stale value. The two files this plan authored are clean of it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Comma-formatted inventory counts failed the facade live-line-count grep**
- **Found during:** Task 1 verification (the automated check returned exit 1)
- **Issue:** The first draft wrote Lines/Chars with thousands separators (e.g. `2,908`). The Task 1 acceptance grep (and the 337-04 manifest-sum lint) greps for the raw `wc -l` output `2908` with no comma, so `grep -c "2908"` returned 0 and the size-matches-HEAD check failed.
- **Fix:** Rewrote the inventory table, the per-group token tables, the group-sum line, and the Storage-Travels effective-cost line to use raw integers (no separators); added an explicit note that Lines/Chars are raw so they match `wc` literally. Re-verified every row against live `wc` (ALL_ROWS_MATCH_WC_AT_HEAD).
- **Files modified:** audit/rng-audit-kit/CHUNK-MANIFEST.md
- **Commit:** `5860bb67` (fix applied before the Task 1 commit)

### Other notes (not deviations)
- The artifact spec lists `min_lines: 40` for the RNG-AUDIT-KIT.md append. The two appended sections are complete and substantive at 33 section-lines (recipe with per-model table + 4 paths + general note + post-v50 framing + 2-paragraph scope). A per-model window table was added for operator usability (RESEARCH §6), bringing real content rather than padding. The soft floor was not force-met by filler — doing so would degrade the deliverable's tight-artifact intent; all four `must_haves.truths` and both artifact `provides` clauses are fully satisfied.

## Authentication Gates
None.

## Known Stubs
None. Both files are complete deliverables; no placeholder/empty-data patterns.

## Self-Check: PASSED
- FOUND: audit/rng-audit-kit/CHUNK-MANIFEST.md
- FOUND: audit/rng-audit-kit/RNG-AUDIT-KIT.md (appended)
- FOUND commit: 5860bb67 (Task 1)
- FOUND commit: c94820d7 (Task 2)
