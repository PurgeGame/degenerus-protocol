---
phase: 394-legacy-debt
plan: 04
subsystem: audit-legacy-debt-v51
tags: [audit, legacy-debt, v51, claimBingo, bingo-module, pool-reward, jackpot-final-day, dual-net, cross-model, freeze, conservation]
requires: ["394-02 (NET 1 council v51 on record)", "394-03 (v50 slice adjudicated + audit/FINDINGS-v50.0.md)"]
provides: ["NET 2 v51 adversarial net", "v51 slice dual-net adjudication", "audit/FINDINGS-v51.0.md (LEGACY-06)", "consolidated 394-FINDINGS.md index"]
affects: ["LEGACY-03", "LEGACY-04", "LEGACY-06", "Phase 394 closure"]
tech_stack_added: []
patterns: ["dual-net (council + Claude) adjudication", "grep-enumeration to settle a vacuous premise", "freeze backward-trace (enumerate every writer)", "BPS split-conservation proof", "skeptic dual-gate"]
key_files_created:
  - .planning/phases/394-legacy-debt/394-04-CLAUDE-NET.md
  - .planning/phases/394-legacy-debt/394-FINDINGS-V51.md
  - audit/FINDINGS-v51.0.md
  - .planning/phases/394-legacy-debt/394-FINDINGS.md
key_files_modified:
  - .planning/STATE.md
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
decisions:
  - "LEGACY-04b premise VACUOUS: no sDGNRS Pool.Reward final-day deletion path exists; grep-enumerated 6 sites (genesis + 3 draws + doc), none in Advance/Jackpot; AdvanceModule final-day draw targets Pool.Affiliate"
  - "The vacuous premise is the expected residue of the v51 D-12 orphaning (Phase 339-03 removed the old FINAL_DAY_DGNRS_BPS/JackpotDgnrsWin branch)"
  - "claimBingo is strictly msg.sender-only (no operator path) — tighter than the council model; the NotApproved/_resolvePlayer belongs to claimAffiliateDgnrsReward"
  - "Both nets converge SOUND on all 3 v51 break-targets; gemini skip (non-responsive) documented → 396 second-source"
  - "0 CONFIRMED contract findings; 1 INFO doc-hygiene (the two stale JackpotModule:1047/:1160 comments)"
metrics:
  duration: ~50min
  completed: 2026-06-15
  tasks: 2
  commits: 2
  files_created: 4
  files_modified: 3
---

# Phase 394 Plan 04: v51 LEGACY-DEBT Dual-Net Adjudication + FINDINGS-v51.0 + Consolidated Index Summary

NET 2 (the independent Claude adversarial net) swept the v51 surface (claimBingo/BingoModule freeze + tier-precedence + dedup + CEI; the sDGNRS Pool.Reward rebalance; the jackpot final-day Pool.Reward deletion) against the byte-frozen subject `a8b702a7`, folded the NET-1 council leads, authored the deferred `audit/FINDINGS-v51.0.md` (LEGACY-06), and wrote the consolidated `394-FINDINGS.md` index tying both slices (v50 + v51) — **0 CONFIRMED contract findings; both nets converge SOUND; the jackpot final-day Pool.Reward deletion premise is VACUOUS; Phase 394 is closed.**

## What was built

- **`394-04-CLAUDE-NET.md`** (349 lines) — the independent per-item adversarial net: the claimBingo freeze backward-trace (every `traitBurnTicket[level]` writer enumerated → the sole writer `_raritySymbolBatch` runs in the swap+frozen read buffer before the word), the tier-precedence/dedup/CEI/empty-pool/gameOver attack, the Pool.Reward 8-BPS-sum split-conservation proof, the jackpot final-day grep-enumeration (the premise shown VACUOUS) + the ETH-path FUZZ-05 backing-conservation, the skeptic dual-gate, and the council fold-in.
- **`394-FINDINGS-V51.md`** (142 lines) — the v51 slice dual-net adjudication: the both-nets-on-record table, the per-item verdict table (LEGACY-03a/-03b/-04a/-04b each with a CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict + settling cite), the skeptic gate, the routing (0 CONFIRMED + 1 INFO), the re-attestation line.
- **`audit/FINDINGS-v51.0.md`** (172 lines, LEGACY-06) — the deferred v51 deliverable matching the FINDINGS-v62.0 format: frozen subject `a8b702a7` + the v51 close history + the disposition table + the surface coverage + the refuted/by-design section + the prior mitigations + the both-nets attestation.
- **`394-FINDINGS.md`** (96 lines) — the consolidated phase index tying v50 + v51: the both-nets rollup for both slices, the all-6-LEGACY-reqs re-attestation table, the consolidated routed-list, the byte-freeze attestation.

## Adjudication outcome (the priority)

- **LEGACY-04b — jackpot final-day Pool.Reward deletion = REFUTED, PREMISE VACUOUS.** `git grep -n Pool.Reward a8b702a7` shows `Pool.Reward` at EXACTLY 6 sites — genesis seed (`StakedStonk:408`), the 3 live draws (Bingo `:188/190`, Degenerette `:1221/1230`, coinflip bounty `Game:466/472`), the BPS constant + doc comments — and NOWHERE in `DegenerusGameAdvanceModule` or `DegenerusGameJackpotModule`. The AdvanceModule final-day pool draw (`_rewardTopAffiliate :753-763`) targets `Pool.Affiliate`, not `Pool.Reward`; `JackpotModule` has ZERO sDGNRS pool touch. The surviving solo-bucket "final day" path (`_handleSoloBucketWinner`→`_processSoloBucketWinner`) pays 75% ETH + 25% whale-passes only. The premise is the expected residue of the v51 D-12 orphaning (Phase 339-03). The two STALE "DGNRS on final day" comments (`JackpotModule:1047` + `:1160`) are the only residue = INFO doc-hygiene.
- **LEGACY-03a — claimBingo freeze = REFUTED.** Backward-trace: the SOLE `traitBurnTicket[level]` writer is `_raritySymbolBatch` (`MintModule:789-812`), draining the swap+frozen read buffer (`Storage:780-805`, `AdvanceModule:389`) before the word; far-future sale rng-locked (`MintModule:1214`). `claimBingo` is strictly msg.sender-only (no operator path).
- **LEGACY-03b — tier/dedup/CEI/empty/gameOver = REFUTED.** CEI-tight: the dedup bit (`:151`) + tier bits (`:166-169`/`:174`) set before the calls (`:188-196`); quadrant-first marks BOTH bits suppressing the symbol bonus; empty-pool clamp-to-0 no-op; gameOver `:122`.
- **LEGACY-04a — Pool.Reward rebalance = REFUTED.** 8-BPS sum 2000+1000+3000+2000+1000+1000 = 10000 = BPS_DENOM; `1e30÷1e4` exact (dust branch no-op); `transferFromPool`/`transferBetweenPools` clamp; every consumer reads the LIVE balance — no stale-split hardcode.

Both nets CONVERGE SOUND on all 3 break-targets; the gemini skip (non-responsive) is documented → 396 second-source. The skeptic dual-gate ran on the 3 value-bearing items (DOMINANT bingo freeze + the 2 SPINE conservation surfaces) → nothing reaches HIGH.

## Deviations from Plan

None — plan executed exactly as written. The PRIORITY adjudication (grep-enumerate every Pool.Reward reference to settle the vacuous premise; backward-trace every traitBurnTicket writer for the freeze; LEGACY-03/-04a/-04b adjudicated with both nets + the skeptic gate) was carried out in full. Both nets converged with no DIVERGENT lead.

## Known Stubs

None. All four deliverables are fully authored with substantive per-item analysis + settling source cites; no placeholder/empty data. No contract source was touched (audit-only posture; subject byte-frozen).

## Authentication gates

None.

## Byte-freeze + tree-clean attestation

`git diff a8b702a7 -- contracts/` is EMPTY at the start and end of both tasks; `git status --porcelain` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` (unrelated). Hardhat was never invoked (the ContractAddresses-regeneration landmine avoided). No contract source edited; no CONFIRMED finding fixed in-phase.

## Phase 394 closure

All 4 plans complete; both nets on record for BOTH slices (v50 + v51); 0 CONFIRMED contract findings across both; LEGACY-01..06 attested/discharged; the two deferred FINDINGS deliverables (audit/FINDINGS-v50.0.md + audit/FINDINGS-v51.0.md) authored; the consolidated 394-FINDINGS.md ties both slices. NEXT = Phase 395 (MUTATION). Carried to 396: the gemini v51 second-source + the prior 392/393 codex second-source + the routed test-hardening + the stale-comment INFO items.

## Commits
- `550493c0` — docs(394-04): NET 2 independent v51 adversarial net
- `4e1e73a0` — docs(394-04): adjudicate v51 slice + author FINDINGS-v51.0 + consolidated 394 index

## Self-Check: PASSED
- All 5 created files exist (394-04-CLAUDE-NET.md, 394-FINDINGS-V51.md, audit/FINDINGS-v51.0.md, 394-FINDINGS.md, 394-04-SUMMARY.md).
- Both task commits present (`550493c0`, `4e1e73a0`).
- `git diff a8b702a7 -- contracts/` EMPTY — subject byte-frozen; no contract source edited.
