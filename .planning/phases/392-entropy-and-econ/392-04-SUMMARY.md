---
phase: 392-entropy-and-econ
plan: 04
subsystem: audit / BURNIE-coinflip-rework adjudication
tags: [audit, burnie, coinflip, redemption-backing, dual-net, byte-frozen, audit-only]
requires:
  - 392-02 (NET 1 council BURNIE — gemini on record, codex skipped)
  - 392-03 (NET 2 + adjudication ECON slice — for the consolidated index)
  - 391-FINDINGS (FC-392-11 RNG-lock half attested)
  - 390-FINDINGS (FC-392-08 solvency-CEI half cross-ref)
provides:
  - 392-04-CLAUDE-NET.md (NET 2 BURNIE adversarial net)
  - 392-FINDINGS-BURNIE.md (BURNIE slice adjudication, both nets)
  - 392-FINDINGS.md (consolidated phase-392 index)
  - 2 CONFIRMED MED findings routed to a gated USER-hand-review boundary
affects:
  - 396 (terminal council — post-reset codex second-source for the 2 BURNIE prime leads)
  - the gated contract-fix boundary (USER hand-review of BURNIE-04 + BURNIE-05)
tech-stack:
  added: []
  patterns: [dual-net-both-on-record, skeptic-dual-gate, exhaustive-backing-trace, byte-frozen-read-only-audit]
key-files:
  created:
    - .planning/phases/392-entropy-and-econ/392-04-CLAUDE-NET.md
    - .planning/phases/392-entropy-and-econ/392-FINDINGS-BURNIE.md
    - .planning/phases/392-entropy-and-econ/392-FINDINGS.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
decisions:
  - "BURNIE-04/FC-392-16 carry strand = CONFIRMED MED (under-credit/strand, conservative, off the ETH spine) — routed, USER may rule BY-DESIGN"
  - "BURNIE-05/FC-392-17 VAULT seed window-aging = CONFIRMED-as-risk MED (lost-emission window, runbook-contingent) — routed, USER may rule BY-DESIGN with a deploy-runbook MUST"
  - "BURNIE-01/-02/-03/-06 + FC-392-11/-12/-13/-18/-19/-20 = REFUTED/MONITOR/INFO, both nets on record"
  - "0 HIGH; both prime leads bounded off the ETH spine (no money pump, no supply break, no ETH insolvency, no attacker profit)"
  - "codex skipped (hard cap) — post-reset second-source for the 2 CONFIRMED prime leads carried to 396"
metrics:
  duration: ~50m
  completed: 2026-06-15
  tasks: 2
  files_created: 3
  confirmed_findings: 2
---

# Phase 392 Plan 04: BURNIE-coinflip-rework NET 2 + Adjudication + Phase Index Summary

NET 2 (the independent Claude adversarial net) is on record for the full BURNIE/coinflip-rework surface; both
prime backing leads CONFIRM as MED (bounded off the ETH spine) and route to a gated USER-hand-review fix; the
consolidated 392-FINDINGS.md ties the ECON + BURNIE slices into the phase-392 verdict — all 12 reqs
adjudicated, both nets on record for both slices, the subject byte-frozen throughout.

## What was built

- **392-04-CLAUDE-NET.md (NET 2):** an independent per-item adversarial pass over BURNIE-01..06 + FC-392-16..20
  + the cross-ref backing-dynamics leads FC-392-11/-12/-13, run BEFORE folding the council leads. The two prime
  backing leads got dedicated rigorous treatment: §1 the EXHAUSTIVE carry-backing trace (burnieOwed →
  previewClaimCoinflips → the redeemBurnieShare waterfall → autoRebuyCarry), §2 the VAULT seed-stake 30-day
  window-aging determination. Plus the emission-conservation re-verification (§3), the per-source
  survive-before-mint enumeration (§4), the monotone-latch proof (§5), the packed-lane round-trip (§6), the
  loss-sequence backing model (§7), the LOW-INFO leads (§8), and the council fold-in (§9).
- **392-FINDINGS-BURNIE.md:** the BURNIE slice adjudication — both-nets-on-record table, a per-item verdict row
  for every req + owned lead + cross-ref lead, the skeptic dual-gate run on the two prime leads + the
  loss-sequence lead, the two prime leads settled with full accounting (§4), and the routing of both CONFIRMED
  findings to a gated USER-hand-review boundary (§5).
- **392-FINDINGS.md:** the consolidated phase-392 index — the both-nets rollup for BOTH slices, the 12-req
  phase-verdict rollup, the consolidated routed-findings list, and the FC-392-08/-11 cross-ref consistency
  notes (390/391/393 alignment confirmed).

## The two prime backing leads — verdicts

- **BURNIE-04 / FC-392-16 — sDGNRS auto-rebuy carry stranded from redemption backing: CONFIRMED MED.** After
  day 20 sDGNRS is on perpetual 0-take-profit auto-rebuy; every win rolls into `autoRebuyCarry`, which is
  invisible to `previewClaimCoinflips` (= `_viewClaimableCoin` + `claimableStored`, neither reads the carry)
  AND has no sDGNRS-reachable liquidation path (grep-clean `claimCoinflipCarry(sDGNRS)` /
  `setCoinflipAutoRebuy(sDGNRS)`). Steady-state `burnieOwed` reflects only the held seed-window balance, so
  redeemers are progressively under-credited for carry-resident BURNIE. Conservative (no over-credit, no
  insolvency, off the ETH spine). The design comment documents the carry as "structurally zero return" to
  redeemers, a strong BY-DESIGN signal — but the value is proportionally owed under the `burnieOwed` formula's
  own premise. ROUTED (USER may rule BY-DESIGN).
- **BURNIE-05 / FC-392-17 — VAULT seed-stake 30-day window-aging: CONFIRMED-as-risk MED.** The VAULT seed
  (days 1-20, ~2M expected BURNIE) is silently and irreversibly forfeited if the VAULT owner does not claim OR
  arm within the first 30 resolved days — there is no auto-claim safety net (asymmetric vs sDGNRS) and no
  on-chain warning. Bounded by: the VAULT is protocol-controlled (prompt operator claim is the realistic
  timeline) + two escape hatches (claim by day≤30, or arm before day 51 which changes
  `minClaimableDay=autoRebuyStartDay` and escapes the clamp). NOT an attacker exploit. BY-DESIGN only if the
  deploy runbook GUARANTEES the within-30-day action (operational, not enforced in code). ROUTED — the lead
  most likely to warrant a contract change.

## Deviations from Plan

None - plan executed exactly as written. Both tasks ran autonomously, no checkpoints, no architectural
changes, no auth gates. No contract source was touched (audit-only posture); both CONFIRMED findings are
DOCUMENTED + ROUTED, never fixed.

A clarifying note (not a deviation): both prime leads CONFIRMED rather than REFUTED. The plan's
PRIORITY_ADJUDICATION anticipated this ("a CONFIRMED finding here is most likely MED") and required CONFIRMED
MED/LOW to be DOCUMENTED + ROUTED (not fixed) — which is exactly what was done. Severity is MED for both
(bounded off the ETH spine; no HIGH/CATASTROPHE), so no orchestrator-pause-for-USER-review elevation was
triggered.

## Known Stubs

None. These are documentation deliverables; no code, no UI, no data wiring.

## Threat Flags

None. No contract source was created or modified; no new network/auth/file/schema surface was introduced (the
findings are about EXISTING frozen surface). Subject byte-frozen at `a8b702a7` throughout.

## Routed findings (gated USER hand-review, NOT fixed here)

| # | Finding | Weight | Routing |
|---|---------|--------|---------|
| 1 | BURNIE-04 / FC-392-16 carry strand (under-credit/strand, no liquidation) | MED (off the ETH spine) | gated USER hand-review, batched; fix = count carry in `burnieOwed` / add sDGNRS carry liquidation / rule BY-DESIGN |
| 2 | BURNIE-05 / FC-392-17 VAULT window-aging (lost-emission window) | MED (off the ETH spine, runbook-contingent) | gated USER hand-review, batched; fix = auto-claim/arm-at-deploy / widen window / accept BY-DESIGN + deploy-runbook MUST |

Post-reset codex second-source RECOMMENDED for both prime leads before any gated fix; carried to 396.

## Self-Check: PASSED

- 392-04-CLAUDE-NET.md — FOUND
- 392-FINDINGS-BURNIE.md — FOUND
- 392-FINDINGS.md — FOUND
- commit 26ac18b6 (NET 2) — present
- commit fb70886e (findings) — present
- `git diff a8b702a7 -- contracts/` — EMPTY (subject byte-frozen)
