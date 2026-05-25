---
phase: 321-spec-design-lock-call-graph-attestation-reconciliation
plan: 01
subsystem: spec
tags: [design-lock, call-graph-attestation, shared-surface-reconciliation, claimable-invariant, rng-freeze, ledger-reconciliation]

# Dependency graph
requires:
  - phase: v46.0-closure
    provides: "frozen audit baseline HEAD MILESTONE_V46_AT_HEAD_16e9668a (v47.0 delta-audit baseline)"
  - phase: PLAN-V47-MILESTONE-SCOPE
    provides: "the 7-item manifest + the 7 per-item plan docs (presale/lootbox-boon/dgas/cpay/redeem/dspin/tomb)"
provides:
  - "321-SPEC.md §0 — BATCH-02 attestation verdict: 0 IMPL blockers; carried corrections C1–C9"
  - "321-SPEC.md §1 — BATCH-01 reconciliation R1–R7 (final resolveRedemptionLootbox signature + apply-order; _resolveLootboxCommon 5→2 bool reduction; _creditBoxProceeds + pullRedemptionReserve claimable joint-check; presale-box RNG freeze; single DegeneretteModule edit; earlybird→presale-box swap; AfKing cancel-tombstone)"
  - "321-SPEC.md §2 — per-item IMPL blueprint + file/edit-order map (load-bearing input to Phase 322)"
  - "four 321-ATTEST-*.md — per-anchor grep verification tables (1,707 lines total)"
affects: [322-IMPL-batched-diff, 323-TST-proofs, 324-TERMINAL-delta-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Call-graph verification against source pre-patch (feedback_verify_call_graph_against_source): every 'by construction' / 'single fn reaches all paths' claim grep-verified, not assumed"
    - "RNG backward-trace + commitment-window + window-SLOAD-freshness (feedback_rng_*): presale-box payout entropy proven unknown at buy-commit and frozen request→unlock"

key-files:
  created:
    - .planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-SPEC.md
    - .planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-ATTEST-PRESALE.md
    - .planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-ATTEST-LOOT-DGAS-DSPIN.md
    - .planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-ATTEST-REDEEM-CPAY.md
    - .planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-ATTEST-TOMB.md
  modified: []
---

# Phase 321 — Plan 01 SUMMARY: SPEC Design-Lock + Call-Graph Attestation + Reconciliation

**Status:** complete — delivered via direct design-lock authoring, committed `779eacc3`.
**Attested baseline HEAD:** `2a18d622` (2026-05-24). **Source mutated:** none (SPEC is paper-only).

## What was delivered

The full v47.0 design-lock for the single batched contract diff, in five committed docs:

- **`321-SPEC.md`** (§0 attestation verdict + C1–C9 · §1 R1–R7 reconciliation · §2 per-item
  IMPL blueprint + file/edit-order map · §3 success criteria, all 5 ✅).
- **Four `321-ATTEST-*.md`** — the BATCH-02 per-anchor grep tables behind the §0 verdict.

## Headline outcomes

- **BATCH-02 verdict: 0 IMPL blockers.** Every cited `file:line` exists in source; all drift
  is line-number-only (≤ a few lines, re-grep at edit time). No "by construction" claim relies
  on absent code. Nine material clarifications captured as carried corrections **C1–C9** that
  override the plan prose (notably: `_resolveLootboxCommon` keeps `emitLootboxEvent` +
  `payColdBustConsolation`; `CURRENCY_WWXRP = 3`; slot-0 has exactly 2 free bytes; the
  200-ETH presale auto-end keys on `LOOTBOX_PRESALE_ETH_CAP`).
- **R1 — `resolveRedemptionLootbox` single settled signature:** `external payable`,
  SDGNRS-gated, credits `futurePrizePool` from `msg.value`, delegatecalls the now-boon-rolling
  common resolver. Apply-order recorded: REDEEM-03 (payable + delete unchecked claimable debit)
  FIRST, then LOOT-03 (boon roll, achieved via R2 not a call-site flag).
- **R3 — claimable-balance invariant joint-check:** new `_creditBoxProceeds` (80/20 box-ETH
  ledger move) + new SDGNRS-gated CHECKED `pullRedemptionReserve` + canonical CPAY shortfall
  pattern, proven to keep `claimablePool == Σ claimableWinnings` across PRESALE-06 / CPAY-01/02/03
  / REDEEM-01/03 together; no `unchecked` claimable subtraction survives the redemption path.
- **R4 — presale-box RNG freeze:** payout entropy reuses the committed index/day word with
  domain salt `keccak256(rngWord,"PRESALE_BOX")`; combined lootbox+box share one index / two
  domain-separated draws; freeze-safe by the existing lootbox argument (secure-phase re-verify
  flagged for Phase 322).
- **R2/R5/R6/R7** — `_resolveLootboxCommon` 5→2 bool reduction (fixes the 10% haircut); the
  single DegeneretteModule edit (DGAS write-batching + DSPIN per-currency caps 25/15/5); the
  earlybird→presale-box subsystem swap with grep-confirmed dead-flag removal scope; and the
  isolated AfKing cancel-tombstone (in-sweep reclaim of a `dailyQuantity==0` tombstone,
  resolving H-CANCEL-SWAP-MISS).

## Ledger reconciliation

This SUMMARY + `321-01-PLAN.md` + `321-VERIFICATION.md` close the GSD ledger against the
already-committed deliverable (the power outage interrupted closure after `779eacc3`). No new
design was authored during reconciliation.

## Handoff to Phase 322

`321-SPEC.md` §2 (per-item blueprint + file/edit-order map) is the load-bearing input. Phase 322
applies the ONE batched `contracts/*.sol` diff — HELD at the contract-commit boundary for
explicit user hand-review (no contract commit without it).
