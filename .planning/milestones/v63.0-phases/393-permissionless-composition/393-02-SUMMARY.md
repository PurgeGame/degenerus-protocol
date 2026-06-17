---
phase: 393-permissionless-composition
plan: 02
subsystem: audit / permissionless-access adjudication
tags: [audit, access-control, keeper-bounty, burst-solvency, forced-timing, reentrancy, dual-net, byte-frozen]
requires:
  - 393-01 NET 1 council (gemini on record; codex skipped — usage cap)
  - 390-FINDINGS (FC-390-03/-06, FC-392-08, FC-393-02/-03 solvency halves)
  - 392-FINDINGS (FC-392-08 ECON half, FC-392-20 gas INFO)
  - 388-02 finding-candidate ledger (FC-393-01..04 + cross-refs)
  - test/REGRESSION-BASELINE-v63.md (green oracle 854/0/110)
provides:
  - 393-02-CLAUDE-NET.md (NET 2 independent adversarial net)
  - 393-FINDINGS.md (the phase-393 adjudication — ACCESS-01..05 attested, 0 CONFIRMED)
affects:
  - REQUIREMENTS.md ACCESS-01..05 (attested)
  - 395/396 (4 routed un-netted test-hardening items + post-reset codex second-source)
tech-stack:
  added: []
  patterns: [dual-net audit, skeptic dual-gate, cross-ref consistency, byte-frozen subject, audit-only routing]
key-files:
  created:
    - .planning/phases/393-permissionless-composition/393-02-CLAUDE-NET.md
    - .planning/phases/393-permissionless-composition/393-FINDINGS.md
    - .planning/phases/393-permissionless-composition/393-02-SUMMARY.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
decisions:
  - "Redemption keeper bounty is 24e12 wei (StakedDegenerusStonk.sol:348), DISTINCT from the decimator 15e12 (DecimatorModule:117) — the surface-map/plan-cite 'both 15e12 identical' was WRONG; gemini's 24e12 was RIGHT. ACCESS-02 net-negative holds at the TRUE constants (both sized to per-box settle gas → identical reward-to-real-gas ratio)."
  - "claimCoinflipCarry entry is BurnieCoinflip.sol:754, rngLocked gate :759, mint-to-player :777 (neither the plan's @366 nor gemini's :787) — ACCESS-01 carry verdict rests on the corrected lines."
  - "0 CONFIRMED contract findings — ACCESS-01..05 attested at a8b702a7, document-only; subject byte-frozen throughout."
metrics:
  tasks_completed: 2
  duration: ~40m
  completed_date: 2026-06-15
---

# Phase 393 Plan 02: PERMISSIONLESS-COMPOSITION NET 2 + Adjudication Summary

Independent Claude adversarial net (NET 2) over the full permissionless/keeper surface, then the
both-nets adjudication of ACCESS-01..05 + FC-393-01..04 + 4 inherited cross-refs vs the byte-frozen
subject `a8b702a7` — **0 CONFIRMED contract findings; ACCESS-01..05 attested.**

## What was delivered

- **393-02-CLAUDE-NET.md (NET 2, 442 lines)** — independent per-item attack + provisional verdict over
  every entrypoint (`claimDecimatorJackpot`/`Many`, `claimRedemption`/`Many`, `claimCoinflipCarry`), with:
  - the **2 NET-1 cite-drifts reconciled at the frozen source** (redemption bounty = 24e12, NOT 15e12;
    carry entry :754 / mint :777);
  - **ACCESS-02 dedicated real-gas economics** — 10x/40x/100x under-water @5/20/50 gwei × ~0.30
    flip-credit illiquidity, un-manufacturable (each box requires a real burn), issuance bounded
    (FC-390-06), `_mintPriceInContext()` price-independent;
  - **ACCESS-04 dedicated same-block leg accounting** — Σ legs == Σ rolled == Σ released; each leg
    fresh-`bal` + stETH-remainder fail-closed; MAX(175%) reservation covers; ETH-drain shifts to the
    stETH leg of the same held reservation (no strand/under-pull);
  - **ACCESS-03 forced-timing on the magnitude** — reward magnitude frozen, offset distribution
    frozen-seed-invariant, only the level anchor moves, forced earlier = beneficial/neutral;
  - **ACCESS-05 gate + reentrancy CEI enumeration** per entrypoint (freeze/rngLocked/gameOver gates;
    slot-delete + ledger-debit + stETH-first/ETH-last; SDGNRS-gated callees; internal-only yield-surplus;
    V62-03 reorder intact);
  - the council leads folded in at the end (all convergent-SOUND, 0 findings).
- **393-FINDINGS.md (201 lines)** — both-nets attestation; the per-item verdict table (13 rows, each with
  verdict + settling cite); the cite reconciliation; the skeptic gate on the 3 substantive/attention
  items; the cross-ref consistency block (each ACCESS half vs its 390/392 counterpart); routing; the
  re-attestation line.

## Adjudication outcome (13 items, all REFUTED / BY-DESIGN)

| Item | Verdict |
|------|---------|
| ACCESS-01 (beneficiary-only) | REFUTED |
| ACCESS-02 (keeper-bounty real-gas) | REFUTED (net-negative + un-manufacturable + bounded) |
| ACCESS-03 / FC-393-01 (forced-timing magnitude) | BY-DESIGN/REFUTED (MONITOR posture) |
| ACCESS-04 / FC-393-03 (partial-balance burst) | REFUTED (Σ identity + MAX reservation) |
| ACCESS-05 (gates + reentrancy) | REFUTED |
| FC-393-02 (forfeit-to-self extractability) | BY-DESIGN/REFUTED |
| FC-393-04 / FC-392-20 (claim-loop gas) | REFUTED/INFO |
| FC-390-03 (ACCESS half) | REFUTED (consistent w/ 390) |
| FC-390-06 (ACCESS half) | REFUTED (consistent w/ 390) |
| FC-392-08 (ACCESS half) | REFUTED (consistent w/ 390/392) |

**0 CATASTROPHE/HIGH. 0 CONFIRMED contract findings.** Access/reentrancy/MEV is the LOW/confirmatory
class; the two substantive primes (ACCESS-02, ACCESS-04) passed the skeptic gate (a faucet would need
net-positive-at-real-gas + manufacturability; a burst strand would need a broken Σ identity — neither
holds).

## Deviations from Plan

**Cite-drift resolution corrected the surface-map, not just gemini.** The plan + surface-map §2 asserted
"both bounties identical 15e12"; the frozen source shows the redemption bounty is 24e12 (sDGNRS:348) — so
gemini's "drifted" 24e12 was actually CORRECT and the plan/map cite was wrong. The ACCESS-02 net-negative
conclusion holds at the true constants (both sized to per-box settle gas → identical reward-to-real-gas
ratio). The carry entry/mint lines (:754/:777) differ from BOTH the plan (@366) and gemini (:787).
Documented in 393-FINDINGS §3 + 393-02-CLAUDE-NET §0. No contract impact (audit-only).

No other deviations — no contract source touched (audit-only posture); subject byte-frozen throughout.

## Routed items (NOT contract changes; → 395/396)

- **4 un-netted test-hardening items:** (1) explicit real-gas-net-negative-after-illiquidity number +
  (2) a redemption-bounty (24e12) regression mirror; (3) a same-block-burst burst-solvency invariant;
  (4) a fresh packed-layout 365/1460 worst-case gas measurement. All oracle/gas completeness.
- **Post-reset codex second-source** of the gemini SOUND verdicts (especially ACCESS-02 / ACCESS-04) → 396.

## Cross-ref consistency

Each ACCESS half is consistent with its 390 (solvency/CEI) / 392 (ECON cap-RMW + gas INFO) counterpart —
no half contradicts the already-settled solvency/ECON adjudication (390 §2b/§2c, 392 §4).

## Verification

- 393-02-CLAUDE-NET.md: all 13 IDs present; gas / manufacturability / burst / beneficiary / magnitude
  keyword gates pass; 442 lines (≥ 90 min).
- 393-FINDINGS.md: all 13 IDs present; both-nets / skeptic / gas / burst keyword gates pass; 201 lines.
- `git diff a8b702a7 -- contracts/` EMPTY before and after every task; tree clean (only the pre-existing
  untracked `PLAYER-PURCHASE-REWARDS.html`).

## Self-Check: PASSED
