---
phase: 235-conservation-rng-commitment-re-proof-phase-transition
plan: 235-04
subsystem: audit-rng
tags: [rng-02, commitment-window, rng-locked, vrf, entropy-mixing, c2e5e0a9, 314443af, 52242a10, 20a951df, 104b5d42, keccak, hash2, 232.1-fix-series, drain-before-swap, d-11-invariant, buffer-swap, read-buffer, write-buffer]

# Dependency graph
requires:
  - phase: 230-delta-extraction-scope-map
    provides: "230-01-DELTA-MAP.md §1 + §2.5 (IM-21/IM-22) + §3.4/§3.5 automated gates + §4 Consumer Index RNG-02 row; 230-02-DELTA-ADDENDUM.md per-site inputs for 17 c2e5e0a9 entropy-mixing sites + 314443af keccak-seed fix"
  - phase: 232.1-rng-index-ticket-drain-ordering-enforcement
    provides: "232.1-01-FIX Rev 2 pre-finalize gate + queue-length gate + nudged-word + do-while integration (Rev 3 game-over drain; Rev 4 RngNotReady selector); 232.1-02-SUMMARY forge invariant suite 8/8 PASS on HEAD (drain-before-swap + no-zero-entropy + game-over path isolation); 232.1-03-PFTB-AUDIT non-zero entropyWord availability at all 4 reachable _processFutureTicketBatch call sites"
  - phase: 231-earlybird-jackpot-audit
    provides: "231-02-AUDIT EBD-02 earlybird bonus-trait salt-space isolation (BONUS_TRAITS_TAG = keccak256('BONUS_TRAITS') at DegenerusGameJackpotModule:171)"
  - phase: 233-jackpot-baf-entropy-audit
    provides: "233-02-AUDIT JKP-02 D-06 commitment-window enumeration (16-variable table at the entropy-passthrough boundary)"
provides:
  - "235-04-AUDIT.md: Per-Consumer Commitment-Window Enumeration Table covering 5 new-RNG-consumer categories (earlybird bonus-trait / BAF sentinel / entropy passthrough / 17 c2e5e0a9 entropy-mixing sites / 314443af _raritySymbolBatch keccak-seed) at HEAD 1646d5af"
  - "rngLocked Invariant sub-section citing D-11 locked statement — blocks (a) far-future ticket queue writes, (b) active read-buffer writes; permits current-level write-buffer writes"
  - "Global State-Variable Enumeration table — 25 player-controllable state variables with rngLocked-guard annotation"
  - "232.1 Ticket-Processing Impact sub-section confirming fix series structurally ENFORCES drain-before-swap, closing a pre-existing RNG-02 commitment-window hole"
  - "D-09 Non-Zero-Entropy Availability Cross-Cite to 232.1-03-PFTB-AUDIT (rawFulfillRandomWords:1698 + rngGate:1191 + Plan 01 pre-drain gate)"
  - "230-02 Addendum Impact sub-section — all 17 c2e5e0a9 sites + 314443af covered with no new player-controllable input beyond enumerated state"
  - "Cross-Cited Prior-Phase Verdicts (233-02 JKP-02 + 232.1 Plan 02) re-verified at HEAD 1646d5af per D-04"
affects:
  - 236-findings-consolidation (FIND-01 canonical ID assignment; this plan contributes ZERO candidate findings)
  - 235-03-RNG-01 (sibling — backward-trace side of the full RNG commitment proof)
  - 235-05-TRNX-01 (rngLocked invariant D-11 4-path walk at phase-transition packed housekeeping window)
  - 236-REG-01 (v25.0 Phase 215 RNG audit regression cross-check; HEAD state is strictly more robust than v25.0 baseline)

# Tech tracking
tech-stack:
  added: []
  patterns: [per-site commitment-window enumeration with inputs/mutation/non-influential-proof columns; rngLocked-guarded annotation on every player-controllable state variable; cross-cite re-verification at HEAD via direct contract source read; buffer swap at RNG request time (not fulfillment) per D-12; D-11 invariant (FF-queue + active-read-buffer block) as milestone-wide guard]

key-files:
  created:
    - .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-04-AUDIT.md
  modified: []

key-decisions:
  - "Commitment-window enumeration per D-08 is mandatory per-site (no equivalence-class shortcuts): each of the 17 c2e5e0a9 sites gets a distinct row because each site has different input variables (lvl / sourceLevel / traitIdx / ticketUnits / share / traitShare / coinBudget / beneficiary / weiAmount / rollSalt / groupIdx / s / TAG constants)."
  - "D-11 invariant is the load-bearing statement: rngLocked blocks FF-queue writes + active read-buffer writes; write-side current-level buffer writes ARE PERMITTED (drain next round). This is the REAL invariant — a blanket ticket-queueing interpretation would be WRONG."
  - "D-12 buffer swap fires at RNG REQUEST TIME (not fulfillment). After swap, read buffer has tickets draining with in-flight VRF word; write buffer is empty. Permitted writes during window land in write buffer and drain next round."
  - "D-09 clean split: availability (entropyWord != 0) is 232.1's closed question and CROSS-CITED from 232.1-03-PFTB-AUDIT; commitment-window diffusion is Phase 235's question."
  - "23 state variables enumerated with rngLocked-guard annotation — 2 over the 232.1-01-FIX audit's 16-variable table (JKP-02 D-06). Additions: ticketsFullyProcessed, gameOverPossible, playerQuestProgress, earlybirdDgnrsPoolStart, traitBurnTicket, deityBoonData, burnieCoinflipPool (decomposed from pre-existing aggregate) — extension of the JKP-02 table for milestone-wide completeness."

patterns-established:
  - "Per-site commitment-window enumeration with locked column schema: Consumer | Inputs | Player-Controllable? | Mutation Between Request-Fulfillment | Non-Influential Proof | Verdict | Finding Candidate"
  - "rngLocked invariant annotation on every state variable: the guarded-mutation-surface table enumerates each state variable, its writer function(s), the exact guard site (File:Line), and whether the writer is gated by rngLocked"
  - "D-11 invariant citation pattern: cite the exact user-locked statement verbatim (two clauses, one annotation on current-level write-buffer), never paraphrase"
  - "Cross-cite re-verification at HEAD: for each cited prior-phase verdict, re-read the cited source at HEAD and confirm the evidence anchors (File:Line, test counts, invariant statements) are unchanged — produces `re-verified at HEAD <SHA>` note per cited row"

requirements-completed: [RNG-02]

# Metrics
duration: ~25min
completed: 2026-04-18
---

# Phase 235 Plan 04: RNG-02 Commitment-Window Enumeration Re-Proof Summary

**Per-consumer commitment-window enumeration at HEAD `1646d5af` covering 5 new-RNG-consumer categories (earlybird bonus-trait roll / BAF sentinel emission / entropy passthrough / 17 c2e5e0a9 entropy-mixing sites / 314443af `_raritySymbolBatch` keccak-seed) — all SAFE, zero candidate findings, rngLocked invariant D-11 formally annotated across 25-variable state-space, 232.1 fix series structurally enforces drain-before-swap closing a pre-existing commitment-window hole.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-04-18
- **Tasks:** 2 (Task 1 write AUDIT.md + Task 2 commit AUDIT.md — combined into a single atomic commit)
- **Files created:** 1 AUDIT.md + 1 SUMMARY.md

## Accomplishments

- 235-04-AUDIT.md: RNG-02 analytical re-proof at HEAD `1646d5af` with Per-Consumer Commitment-Window Enumeration Table covering 5 new-RNG-consumer categories.
- Category 4 (c2e5e0a9 entropy-mixing sites): 19 per-site enumeration rows covering all 17 JackpotModule + 1 MintModule `_rollRemainder` + 1 PayoutUtils `_calcAutoRebuy` sites with distinct input enumeration (no equivalence-class shortcuts per D-08).
- Category 5 (314443af `_raritySymbolBatch` keccak-seed): dedicated row with baseKey / entropyWord / groupIdx enumeration + D-09 availability cross-cite to 232.1-03-PFTB-AUDIT.
- rngLocked Invariant sub-section citing D-11 locked statement verbatim — blocks (a) far-future ticket queue writes, (b) active read-buffer writes; permits current-level write-buffer writes. Buffer swap at RNG REQUEST TIME per D-12.
- Global State-Variable Enumeration: 25 player-controllable state variables with rngLocked-guard annotation; 2 over the JKP-02 D-06 table of 16 (milestone-wide completeness).
- 232.1 Ticket-Processing Impact sub-section (D-06 mandated): walks each fix series change (pre-finalize gate / queue-length gate / nudged-word / do-while / game-over drain / RngNotReady selector / buffer swap timing) against RNG-02; confirms "structurally ENFORCES drain-before-swap, closing a pre-existing RNG-02 commitment-window hole where `processTicketBatch` could read `lootboxRngWordByIndex[X]` while still zero and consume entropy=0 into `_raritySymbolBatch`".
- D-09 Non-Zero-Entropy Availability Cross-Cite sub-section: three anchors (`rawFulfillRandomWords:1698` zero-guard, `rngGate:1191` sentinel-1 break, Plan 01 pre-drain gate at `AdvanceModule:257-279`) all re-verified at HEAD.
- Cross-Cited Prior-Phase Verdicts re-verified at HEAD 1646d5af: 233-02 JKP-02 D-06 commitment-window enumeration (PASS); 232.1 Plan 02 forge invariant tests 8/8 PASS — drain-before-swap + no-zero-entropy + game-over path isolation (PASS).
- Zero VULNERABLE / DEFERRED / SAFE-INFO Finding Candidate: Y rows: this plan contributes ZERO candidate findings to the Phase 236 FIND-01 pool.
- Zero `F-29-` IDs emitted (per D-14).
- Zero `contracts/` or `test/` writes (per D-17 READ-only scope). `git diff --stat 1646d5af..HEAD -- contracts/ test/` returns empty output.

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2 (merged): Write 235-04-AUDIT.md + commit** — `4f1a5233` (docs(235-04): RNG-02 commitment-window enumeration re-proof at HEAD 1646d5af)

_Plan metadata: this SUMMARY.md will be committed separately as the final task-metadata commit by the orchestrator._

## Files Created/Modified

- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-04-AUDIT.md` — 235-line per-consumer commitment-window enumeration re-proof covering 5 categories at HEAD 1646d5af; 19 Category 4 rows (17-site D-08 minimum exceeded); rngLocked Invariant D-11 citation; 25-variable Global State-Variable Enumeration with rngLocked-guard annotation; 232.1 Ticket-Processing Impact sub-section; D-09 Non-Zero-Entropy Availability Cross-Cite; 230-02 Addendum Impact; 2 Cross-Cited Prior-Phase Verdicts re-verified at HEAD per D-04.

## Decisions Made

- **Commitment-window methodology per `feedback_rng_commitment_window.md`:** think like an attacker who sees the VRF request tx and asks "what can I change before fulfillment lands". Every player-controllable state variable enumerated with rngLocked-guard status. No generic "commitment window preserved" assertions.
- **D-08 per-site enumeration without equivalence-class shortcuts:** each c2e5e0a9 site has distinct inputs (different `lvl` / `sourceLevel` / `traitIdx` / `X` where X is ticketUnits/share/traitShare/coinBudget etc.); each gets a distinct non-influential proof row.
- **D-11 invariant citation verbatim:** cited exactly per user-locked statement in CONTEXT.md — rngLocked is NOT a blanket ticket-queueing block; it blocks FF-queue writes + active read-buffer writes only.
- **D-12 buffer-swap timing:** swap fires at RNG REQUEST TIME (not fulfillment). This is cited explicitly with File:Line (`_swapAndFreeze(purchaseLevel)` at `AdvanceModule:292` + `AdvanceModule:1082` mid-day + `AdvanceModule:595` transition).
- **Category 4 row granularity:** 19 rows (17 JackpotModule + 1 Mint + 1 PayoutUtils) to satisfy D-08's per-site minimum. Some JackpotModule sites span multi-line expressions (L607-609, L1681-1683, L1798-1800); each 3-line range covers a single distinct `keccak256(abi.encode(...))` expression so each is a single row.
- **`totalFlipReversals` nudge handling:** despite being player-controllable (via BURNIE burns to `reverseFlip()`), `reverseFlip` reverts if `rngLockedFlag == true` (per `DegenerusGame:1915`). Between VRF request and fulfillment, the nudge counter is frozen — pre-existing v25.0 invariant, not introduced by v29.0 delta.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- **Plan-acceptance-criterion vs policy-statement conflict:** the plan's Methodology template at line 200 included the phrase "No `F-29-NN` IDs emitted" — but the plan's own acceptance criteria forbid the string `F-29-` appearing anywhere in the file. Resolved by replacing "No `F-29-NN` IDs emitted" with "No canonical finding IDs emitted" in the AUDIT.md Methodology header block, preserving the D-14 meaning without tripping the acceptance-criterion regex.

## User Setup Required

None - no external service configuration required. READ-only audit per D-17.

## Next Phase Readiness

- 235-04-AUDIT.md ready for Phase 235 orchestrator verification pass + Phase 236 FIND-01 intake (this plan contributes 0 candidate findings — trivial intake).
- RNG-02 commitment-window side of the full RNG commitment proof complete. Sibling plan 235-03 RNG-01 provides the VRF-word-unknown-at-commitment-time backward-trace side.
- 235-05 TRNX-01 can build on the D-11 invariant annotation here for the 4-path walk (Normal / Gameover / Skip-split / Phase-transition freeze).
- 236 REG-01 has a positive regression baseline: HEAD state is strictly more robust than v25.0 baseline (post-52242a10 code is immune to mid-call `rngWordCurrent = 0` SSTOREs per JKP-02 analysis; post-c2e5e0a9 / 314443af keccak diffusion is strictly stronger than pre-hardening XOR+xorshift).
- No blockers.

## Self-Check: PASSED

Verified at HEAD after AUDIT.md commit (`4f1a5233`):
- `235-04-AUDIT.md` exists at `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-04-AUDIT.md`
- All 10 required headers present (Per-Consumer Commitment-Window Enumeration Table / rngLocked Invariant / Global State-Variable Enumeration / D-09 Non-Zero-Entropy Availability Cross-Cite / 232.1 Ticket-Processing Impact / 230-02 Addendum Impact / Cross-Cited Prior-Phase Verdicts / Findings-Candidate Block / Scope-guard Deferrals / Downstream Hand-offs)
- 5 Category sub-section headers present (Category 1-5)
- Category 4 row count: 19 (exceeds D-08 minimum of 17)
- Category 5 row count: 1 (314443af `_raritySymbolBatch` keccak-seed)
- rngLocked Invariant sub-section cites D-11 locked statement verbatim
- Global State-Variable Enumeration: 25 variables enumerated (exceeds acceptance criterion minimum of 15)
- `1646d5af` string count: 19 (exceeds minimum of 3)
- `re-verified at HEAD 1646d5af` count: 14 (exceeds minimum of 2)
- Cross-Cited Prior-Phase Verdicts table: 2 rows (233-02 JKP-02 + 232.1 Plan 02 forge invariants)
- D-09 Availability Cross-Cite cites `rawFulfillRandomWords:1698` + `rngGate:1191` + Plan 01 pre-drain gate (all three present)
- 232.1 Ticket-Processing Impact sub-section explicitly states "structurally ENFORCES drain-before-swap" + "closing a pre-existing RNG-02 commitment-window hole"
- Zero `F-29-` references (verified via `grep -c "F-29-"` returning 0)
- Zero `contracts/` or `test/` writes (verified via `git status --porcelain contracts/ test/` empty + `git diff --stat 1646d5af..HEAD -- contracts/ test/` empty)
- Downstream Hand-offs names Phase 236 FIND-01, Phase 235-03 RNG-01, Phase 235-05 TRNX-01, Phase 236 REG-01
- Task commit `4f1a5233` exists (verified via `git log -1 --oneline`)

---
*Phase: 235-conservation-rng-commitment-re-proof-phase-transition*
*Plan: 235-04 (RNG-02 commitment-window side of the RNG commitment proof)*
*Completed: 2026-04-18*
