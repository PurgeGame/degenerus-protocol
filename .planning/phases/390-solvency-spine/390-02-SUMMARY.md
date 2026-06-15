---
phase: 390-solvency-spine
plan: 02
subsystem: audit / solvency-spine
tags: [audit, solvency, claimablePool, sdgnrs-backing, redemption, CEI, dual-net, byte-frozen]
requires:
  - 390-01-COUNCIL-NET.md (NET 1 — council on record)
  - 388 FOUNDATION (byte-frozen subject a8b702a7 + REGRESSION-BASELINE-v63 854/0/110)
  - 388-02-FINDING-CANDIDATES.md (FC-390-01..07 + 5 inherited cross-refs)
provides:
  - 390-02-CLAUDE-NET.md (NET 2 — independent Claude adversarial net)
  - 390-FINDINGS.md (the phase-390 adjudication: both nets on record + skeptic gate + verdict table)
  - SOLV-01..07 ATTESTED at a8b702a7 (0 CONFIRMED contract findings)
affects:
  - phase 391 (RNG-SPINE) — next dual-net sweep
  - 392/393 — cross-ref ECON/ACCESS halves recorded (FC-390-06 dilution, FC-392-08 EV, FC-393-02/-03 access)
tech-stack:
  added: []
  patterns: [dual-net adjudication, skeptic dual-gate, wei-level cross-model divergence resolution]
key-files:
  created:
    - .planning/phases/390-solvency-spine/390-02-CLAUDE-NET.md
    - .planning/phases/390-solvency-spine/390-FINDINGS.md
    - .planning/phases/390-solvency-spine/390-02-SUMMARY.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md
decisions:
  - "SOLV-07 whalePassCost divergence RESOLVED at frozen source: single-counted (paidDailyEth includes wpSpent at JackpotModule:1214-1215, so unpaidDailyEth excludes it) — gemini HIGH lead REFUTED, NET 2 sides with codex"
  - "0 CONFIRMED contract findings on the solvency spine; SOLV-01..07 attested document-only at a8b702a7"
  - "EthSolvency redemption-leg invariant gap routed as a test-hardening note (not a contract change)"
metrics:
  duration: ~25m
  completed: 2026-06-15
  tasks: 2
  files: 4
---

# Phase 390 Plan 02: SOLVENCY-SPINE NET 2 + Dual-Net Adjudication Summary

Independent Claude adversarial net (NET 2) over the byte-frozen solvency spine plus the full both-nets
adjudication: every SOLV-01..07 req, every FC-390-01..07 lead, and all 5 inherited cross-refs settled
REFUTED/BY-DESIGN with the cross-model SOLV-07 `whalePassCost` divergence resolved at wei-level — 0
CONFIRMED contract findings, subject byte-frozen at `a8b702a7`.

## What was built

- **`390-02-CLAUDE-NET.md`** (NET 2, 549 lines): an independent per-item attack pass run BEFORE reading
  the council outputs. Each of the 19 items (7 reqs + 7 owned leads + 5 cross-refs) carries PROPERTY ·
  attack/call-sequence · STATE VAR + file:line@`a8b702a7` · settling bound · provisional verdict. The
  three §6-prime targets got dedicated rigorous treatment:
  - **SOLV-05/FC-390-01** — a multi-tx liveness-ordering analysis (interleavings a/b/c) showing the claim
    side is safe-by-construction: redemption ETH is segregated OUT of the game at submit so the
    `handleGameOverDrain` `totalFunds` snapshot never reserves it; EVM tx atomicity + single `isGameOver`
    snapshot + atomic release/slot-delete prevent strand/double-credit.
  - **SOLV-04/FC-390-02** — a dust-forfeit backing proof: the GAME pulls `forfeitEth − msg.value` as
    stETH (reverts if short) before crediting, so the `claimablePool += forfeitEth` is always backed by
    `forfeitEth` of value leaving sDGNRS under the MAX(175%) reservation; fail-closed, no phantom bump.
  - **SOLV-06** — a CEI-ordering trace over all 4 changed payout legs (claimWinnings,
    `_payoutWithStethFallback`, sDGNRS `_payEth`, pullRedemptionReserve) confirming state-debit-before-call
    + stETH-out-before-untrusted-ETH-call; reentrant `distributeYieldSurplus` cannot read in-flight stETH
    as surplus.
- **`390-FINDINGS.md`** (the adjudication, 178 lines): both-nets-on-record attestation, the per-item
  verdict table (NET-1 result · NET-2 result · ADJUDICATED VERDICT · settling cite), the skeptic dual-gate
  (with the SOLV-07 divergence as its load-bearing entry), and the routing block. Matches the proven
  389-FINDINGS shape.
- **`390-02-SUMMARY.md`** + STATE.md / ROADMAP.md updates.

## The PRIORITY item — SOLV-07 `whalePassCost` divergence (RESOLVED)

The council DIVERGED: gemini flagged a HIGH `whalePassCost` double-credit (research-stage lead); codex
refuted it as single-counted. I pinned the exact frozen lines (gemini's ~1284, codex's @1265-1275, and
the prompt's @1247 all resolve to `_processSoloBucketWinner` @ `DegenerusGameJackpotModule.sol:1246-1281`)
and traced the wei-level flow end to end:

- `_processSoloBucketWinner` credits `claimablePool` with ONLY `ethAmount = perWinner − whalePassCost`
  (:1268-1269); `whalePassCost` goes to `futurePrizePool` ONCE via `_addFuturePrizePool` (:1274); the
  whale pass is a NON-ETH claim redeemed for TICKETS (`whalePassClaims` → `claimWhalePass` →
  `_queueTicketRange`, WhaleModule:991-1007 — no claimablePool, no ETH).
- `_handleSoloBucketWinner` adds `wpSpent` into `paidDelta` (:1214-1215), so **`paidDailyEth` INCLUDES
  `whalePassCost`**. Therefore `payDailyJackpot`'s `unpaidDailyEth = dailyEthBudget − paidDailyEth`
  (:443) EXCLUDES it, and the non-final-day `currentPrizePool -= paidDailyEth` (:451) DOES remove it.
- **Gemini's load-bearing premise — that `paidDailyEth` counts only the ETH portion — is FALSE at frozen
  source.** No double-credit; no phantom inflation.

Skeptic dual-gate: fails reachability condition (1) — the double-credit is not present in code. Even
hypothetically it would inflate `futurePrizePool` (a pool obligation OUTSIDE the `claimablePool` solvency
identity, and INCLUDED in the `distributeYieldSurplus` obligations sum at :691, so conservative — fewer
funds distributed), never an underbacked payout. **Verdict: REFUTED — single-counted; NET 2 sides with
codex.** Made unmistakable in `390-FINDINGS.md` §2a/§3a and the return summary.

## Verdict rollup

All 19 items REFUTED / BY-DESIGN / VERIFIED with both nets on record:
SOLV-01..07 REFUTED · FC-390-01/-02/-03/-04/-06/-07 REFUTED · FC-390-05 VERIFIED-equivalent ·
FC-389-02/-08 REFUTED (solvency half) · FC-392-08 REFUTED (solvency/CEI half) · FC-393-02 BY-DESIGN/REFUTED
(non-extractive timing) · FC-393-03 REFUTED (partial-balance burst). **0 CONFIRMED contract findings.**

## Deviations from Plan

None — plan executed exactly as written. Both tasks (NET 2 doc, then both-nets adjudication) ran in order;
the SOLV-07 divergence was settled at frozen source per the PRIORITY_ADJUDICATION protocol; no contract
source touched; no architectural decision needed.

## Carried INFO / routed items (no contract change)

- SOLV-07 gemini HIGH lead → REFUTED-recorded (don't re-derive).
- Decimator pre-reservation slack (codex caveat) → conservative over-reservation, distinct from the
  daily-jackpot fold; no interaction.
- EthSolvency invariant's action set lacks the redemption credit legs (388-02 #5) → routed as a later
  test-hardening note (oracle-completeness, NOT a contract defect; the EXERCISED RedemptionStethFallback
  10/10 + RedemptionAccounting tests + the NET 2 traces already prove every leg).
- Cross-phase owned halves recorded: FC-390-06 BURNIE dilution → ACCESS-02/393; FC-392-08 ECON EV → 392;
  FC-393-02/-03 access → 393.

## Byte-freeze attestation

`git diff a8b702a7 -- contracts/` EMPTY before and after every task; all source read via
`git show a8b702a7:contracts/<File>.sol`; hardhat never invoked. T-390-04/05/06/07 mitigations satisfied
(no tampering, both nets on record, skeptic gate run, 0 CONFIRMED → nothing fixed in-phase).

## Commits

- `fc97d904` — docs(390-02): NET 2 Claude adversarial net over the solvency spine
- `09274eaf` — docs(390-02): 390-FINDINGS solvency-spine adjudication, both nets on record

## Self-Check: PASSED

- `390-02-CLAUDE-NET.md` FOUND · `390-FINDINGS.md` FOUND · `390-02-SUMMARY.md` FOUND
- commits `fc97d904`, `09274eaf` present in `git log`
- all 19 item-IDs present in both deliverables; both-nets table + skeptic gate present
- `git diff a8b702a7 -- contracts/` EMPTY
