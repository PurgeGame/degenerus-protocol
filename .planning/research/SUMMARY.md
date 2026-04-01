# Project Research Summary

**Project:** Degenerus Protocol — v9.0 C4A Contest Dry Run
**Domain:** Competitive smart contract audit simulation (on-chain ETH game, 24 contracts, ~25K lines Solidity)
**Researched:** 2026-03-28
**Confidence:** HIGH (all four research areas grounded in official C4A documentation, verified code review, and documented prior audit history)

---

## Executive Summary

The v9.0 milestone simulates a realistic Code4rena competitive audit against a 25-milestone, heavily self-audited protocol. The core challenge is not "does the code have bugs" but "can fresh-eyes wardens find things that 25 internal passes missed." Research across all four domains converges on a single dominant threat: **monoculture analytical bias**. Every prior audit used the same Claude agent framework with the same reasoning patterns, meaning any fundamental misunderstanding baked in at milestone 1 has been faithfully reproduced through milestone 25. Simulated wardens must be designed to challenge — not confirm — prior SAFE verdicts.

The highest-probability surfaces for new payable findings are cross-module state transitions during `advanceGame`, bit-packing correctness in packed storage slots, token accounting round-trips across the sDGNRS/DGNRS/BURNIE ecosystem, and precision gaps in KNOWN-ISSUES.md that leave documented issues gameable by adjacent attack constructions. The VRF commitment window and delegatecall storage layout, despite being visually alarming surfaces, are the most exhaustively verified and least likely to yield new findings. The real opportunity for wardens is in the seams: behaviors that emerge from the interaction of multiple correct components, particularly around the split daily jackpot path, the game-over state transition boundary, and delta additions (v3.9+, v6.0) that postdate the deepest VRF and storage audits.

C4A rules create sharp incentive effects that must be embedded in simulated warden behavior. The downgrade penalty (H/M submitted at wrong severity = zero payout, no QA credit) means severity must be conservative. The exponential payout decay (0.85^n per duplicate) means a solo Medium is worth more than a High with 5 duplicates. Every H/M submission requires a coded, runnable Foundry PoC — no PoC means automatic rejection regardless of finding quality. Gas optimization is explicitly out of scope and would be rejected.

---

## Key Findings

### C4A Rules Engine (from STACK.md)

C4A uses three severity tiers: High (assets at direct risk, 10 base shares), Medium (protocol function impacted, 3 base shares), QA (bulk report, 4% pool, top 3 only). There is no Critical tier — the contest README's "critical finding" language maps to C4A High.

**Core rules with direct simulation impact:**

- **Coded PoC required** for all H/M submissions. Vague impact analysis = automatic rejection.
- **Downgrade penalty:** H/M downgraded to Low = zero payout, zero QA credit. Wardens must be severity-conservative; borderline findings go to QA, not Medium.
- **Known issue exclusion:** Anything in KNOWN-ISSUES.md or the contest README = automatic rejection. Wardens must internalize KNOWN-ISSUES.md before submitting.
- **Gas reports out of scope:** Gas optimization findings would be rejected outright.
- **Duplicate payout decay:** `Pie = severity_base * 0.85^(n-1) / n`. A solo Medium (3.0 shares) beats a High with 5 duplicates (1.04 shares each). Hunt for unique, non-obvious issues.
- **Partial credit:** Submitting root cause with incomplete impact = 25-75% of shares. Still counted as one duplicate in the decay formula.

**Severity mapping for this contest:**

| Contest README Language | C4A Severity | Base Shares |
|---|---|---|
| RNG manipulation, unauthorized ETH extraction ("critical finding") | High | 10 |
| Gas ceiling breach attackers can force | High | 10 |
| Admin damage without governance approval ("medium finding") | Medium | 3 |
| Everything else | QA or rejected | 4% pool, top 3 only |

**Warden time allocation model (for simulation design):**
- 10-15%: Reconnaissance (read README, KNOWN-ISSUES.md, map architecture)
- 60-70%: Deep analysis (trace money flows, permissions, state transitions; build PoCs)
- 15-25%: Systematic coverage (standard vuln classes, event emissions)
- 5-10%: Write-up and submission

### Exploit Pattern Catalog (from FEATURES.md)

11 patterns ranked by hit rate for this specific architecture. Top patterns by probability of a NEW payable finding:

**Highest probability:**

1. **Cross-module state inconsistency via delegatecall** (VERY HIGH hit rate): Storage slots written by one module, read stale by another during `advanceGame`. The BAF cache-overwrite bug (v4.4) proves this class is real in this codebase. Fresh wardens re-derive the cross-module write map independently and may find paths the systematic adversarial audit missed. The split daily jackpot path (`dailyJackpotCoinTicketsPending` spanning multiple `advanceGame` calls) is the richest unexplored seam.

2. **Rounding / precision loss in BPS splits and pool arithmetic** (VERY HIGH hit rate): ETH from purchases splits across 5+ pools via BPS arithmetic. The "all rounding favors solvency" claim is proven per-operation; the chain of chains under adversarial amounts has not been end-to-end fuzz tested. A warden who demonstrates "sum of BPS splits != msg.value" for a specific input amount produces a High finding.

3. **Token accounting round-trip asymmetry** (HIGH hit rate): DGNRS wrap/unwrap, BURNIE auto-claim during `_transfer`, sDGNRS gambling burn reservation lifecycle. Cross-contract value conservation paths that per-contract audits may not trace end-to-end.

4. **Bit packing / storage field corruption** (MEDIUM hit rate, HIGH value for fresh eyes): `BoonPacked`, `prizePoolsPacked`, `ticketQueuePacked` (bit 22 far-future flag) use custom masks. A single off-by-one in a mask width or shift creates a real finding and no automated tool catches it. Prior auditors develop blind spots on frequently-revisited packed fields.

5. **KNOWN-ISSUES.md precision gaps**: Documented issues with imprecise bounds give wardens attack surface. Entries without quantified worst-case values or explicit composability warnings are gameable.

**Lower probability but non-zero:**

- VRF commitment window delta additions (v3.9+, v6.0 additions postdate the deepest commitment window proof)
- Game-over state transition boundary (both triggers — endgame and 120-day inactivity)
- Cross-function reentrancy through ETH send callbacks in delegatecall context

**Low probability (pre-disclosed or deeply verified):**

- Delegatecall storage collision (multiple `forge inspect` passes)
- stETH rounding (share-based vault inherently handles rebasing; documented)
- Soulbound bypass (no transfer function exists)
- Standard access control (compile-time constant addresses eliminate re-pointing)

### Architecture Attack Surface Map (from ARCHITECTURE.md)

| Rank | Surface | Payable Finding Risk | Key Entry Points |
|------|---------|---------------------|-----------------|
| 1 | Cross-module state (split-tx) | LOW-MEDIUM | advanceGame dispatch order |
| 2 | VRF commitment window (delta gaps) | LOW | rawFulfillRandomWords + v3.9/v6.0 additions |
| 3 | Governance manipulation | LOW (WAR-01/02 pre-disclosed) | DegenerusAdmin, unwrapTo |
| 4 | Delegatecall storage collision | LOW | forge inspect all 10 modules |
| 5 | stETH integration | LOW | DegenerusVault, StakedDegenerusStonk |
| 6 | Soulbound bypass | LOW | StakedDegenerusStonk, DegenerusStonk |

**Most dangerous unknown:** A cross-module state inconsistency during the split daily jackpot execution path, OR a variable introduced post-v3.8 (v3.9 far-future ticket routing, v6.0 DegenerusCharity `resolveLevel` hook, degenerette freeze fix routing) that was delta-audited but not verified against the original 55-variable, 87-path commitment window proof.

### Critical Pitfalls (from PITFALLS.md)

Top 5 pitfalls ranked by likelihood of producing a payable finding despite 25 prior audits:

1. **Monoculture analytical bias** (Rank 1): All 25 milestones used the same analytical framework, same reasoning patterns, same accumulated priors. The single most effective countermeasure: each simulated warden receives ONLY contract source, C4A README, and KNOWN-ISSUES.md — no prior SAFE verdicts, no accumulated audit context. Independent agreement increases confidence; divergence is the value.

2. **Cross-module state transition seams** (Rank 2): Module-by-module correctness proofs are insufficient. The BAF cache-overwrite bug (v4.4) is proof this class exists here. The semantic meaning of shared storage variables must be verified at every delegatecall boundary within a single transaction, not just at the module level.

3. **Rounding error accumulation in multi-step operations** (Rank 3): BPS splits across 5+ pools per purchase, chained with stETH shares-to-balance rounding, chained with coinflip multipliers. "All rounding favors solvency" is proven per-operation; the compound chain under adversarial amounts has not been fuzz-tested.

4. **Game-over boundary state machine violations** (Rank 4): Degenerette bets, pending lootbox RNG, and deity pass refunds in the game-over transition block. The 120-day inactivity trigger may have different propagation characteristics than the endgame trigger and has not been verified to be identical.

5. **VRF fulfillment timing assumptions** (Rank 5): The `phaseTransitionActive` exemption to `rngLocked` is an intentional hole. All prior proofs used a forward-tracing methodology. Backward tracing from each RNG consumer is analytically distinct and may surface paths the forward methodology skipped.

---

## Implications for Roadmap

### Phase 1: Warden Isolation and Specialization Design
**Rationale:** Warden design is the first dependency — every downstream phase depends on wardens being correctly scoped and isolated. Contaminated wardens produce false confidence. This phase defines specializations, entry points, context constraints, and output formats before any audit work begins.
**Delivers:** Five distinct warden specializations with defined entry points, strict context isolation, and mandatory output format (either coded Foundry PoC or written SAFE proof with methodology trace).
**Addresses:** Pitfall 1 (monoculture bias), C4A behavioral model
**Constraints to enforce in all wardens:**
- Input: contract source files + contest README + KNOWN-ISSUES.md only
- No prior audit findings, SAFE verdicts, or accumulated context
- Every H/M finding requires a coded, runnable Foundry PoC
- Severity declared before submission; downgrade penalty rule embedded in behavior
- Gas findings not submitted (out of scope)
- KNOWN-ISSUES.md checked before any submission

**Recommended warden specializations:**

| Warden | Primary Focus | Entry Point | Methodology |
|--------|--------------|-------------|-------------|
| W1: Money Tracer | ETH conservation, BPS rounding chains, stETH accounting | ETH outflows → trace backward to inputs | End-to-end fuzz with adversarial ETH amounts |
| W2: Module Seam Analyst | Cross-module state during advanceGame, split jackpot path | advanceGame dispatch sequence → shared storage write map | Manual state machine mapping + external-call-window CEI verification |
| W3: RNG Backward Tracer | VRF commitment window covering delta additions (v3.9+, v6.0) | Each RNG consumer → backward to commitment point | Variable-by-variable commitment window re-proof, independent of prior verdicts |
| W4: Bit Pack Auditor | BoonPacked, prizePoolsPacked, ticketQueuePacked (bit 22) | Storage declarations → mask/shift arithmetic | Manual field-by-field mask and shift verification |
| W5: Documentation Gap Hunter | KNOWN-ISSUES.md precision gaps, ERC-20 deviation composability | Each known issue entry → "what's the adjacent attack?" | Adversarial documentation reading, construct attacks adjacent to each documented entry |

### Phase 2: Parallel High-Probability Audits (W1, W2, W4)
**Rationale:** Money tracing, module seam analysis, and bit packing have the three highest probabilities of new payable findings and independent entry points. Running these in parallel maximizes fresh-eyes value — wardens cannot cross-contaminate.
**Delivers:** PoC attempts or SAFE proofs for:
- Full BPS split chain from `purchaseFor` through all pool destinations (W1)
- Full `advanceGame` state machine with storage write map at each module boundary, split jackpot path explicitly (W2)
- Field-by-field mask/shift verification for `BoonPacked`, `prizePoolsPacked`, `ticketQueuePacked` (W4)
**Avoids:** Pitfalls 2 and 3 (cross-module seams, rounding accumulation)
**Key constraint for W2:** STORAGE-WRITE-MAP.md from v5.0 must not be given as validation context. If used at all, frame it as "challenge this document, not verify against it."

### Phase 3: VRF Delta Audit and Game-Over Boundary (W3)
**Rationale:** VRF commitment window is well-audited for the pre-v3.9 state. The delta additions (v3.9 far-future routing, v6.0 `resolveLevel` hook, degenerette freeze fix routing) were delta-audited but not verified against the original 55-variable, 87-path proof framework. Game-over boundary is separately high-value because the two triggers (endgame, 120-day inactivity) may have different propagation behavior.
**Delivers:** Commitment window re-proof covering all variables introduced post-v3.8; game-over transition boundary analysis for both trigger paths.
**Avoids:** Pitfall 5 (VRF timing)
**Key constraint for W3:** Must NOT be given the v3.8 commitment window SAFE verdicts. Derive independently, then compare.

### Phase 4: KNOWN-ISSUES.md Hardening (W5)
**Rationale:** Documentation precision gaps are the lowest-effort path to a payable warden finding. A finding technically distinct from but related to a known issue entry is payable regardless of how obvious the underlying vulnerability is. W5 finds these gaps before a real warden does.
**Delivers:** Specific amendment recommendations for each imprecise or gameable KNOWN-ISSUES.md entry (see amendment table below).
**Avoids:** Pitfall 7 (known issues documentation gaps)
**No research phase needed:** Pure documentation review. W5 works from KNOWN-ISSUES.md + contracts only.

### Phase 5: Synthesis and C4A Adjudication
**Rationale:** Warden outputs must be adjudicated against C4A severity rules and against each other for duplicate detection. Phase 5 produces the final signal: what would be payable in a real C4A contest.
**Delivers:** Per-finding C4A severity classification, PoC validity assessment, duplicate grouping, KNOWN-ISSUES.md amendment log.
**Uses:** STACK.md severity mapping table, duplicate rules (same root cause = same pie regardless of different PoC paths), partial credit rules (25/50/75% of shares for partial impact understanding).

### Phase Ordering Rationale

- **Phases 2 and 3 run in parallel.** W1, W2, W4 (Phase 2) and W3 (Phase 3) have independent entry points. Simultaneous execution maximizes fresh-eyes effect and prevents cross-contamination.
- **Phase 4 runs after Phases 2+3 complete.** W5 benefits from knowing what code-focused wardens found — KNOWN-ISSUES.md gaps that newly-found issues would fall through are the priority amendments.
- **Phase 5 is strictly last.** Requires all warden outputs.
- **No phase requires external research.** All research is complete. Contract source, contest README, and KNOWN-ISSUES.md are the only warden inputs.

### Research Flags

Phases needing methodology discipline (not research):
- **Phase 2 (W2 — Module Seam):** STORAGE-WRITE-MAP.md must be framed as adversarial challenge, not validation.
- **Phase 3 (W3 — VRF Delta):** v3.8 commitment window SAFE verdicts must not be given as input. Re-derive independently.

Phases with well-documented patterns:
- **Phase 1 (Warden Setup):** C4A rules are deterministic from STACK.md research.
- **Phase 4 (Documentation):** Pure review task, no code uncertainty.
- **Phase 5 (Adjudication):** C4A severity and duplicate rules are deterministic.

---

## KNOWN-ISSUES.md Amendments Needed

These specific entries are vulnerable to warden escalation via adjacent attack constructions:

| Entry | Current Wording | Gap | Required Amendment |
|-------|----------------|-----|-------------------|
| Rounding | "All rounding favors solvency. stETH transfers retain 1-2 wei per operation." | No cumulative bound quantified. Warden can demonstrate that 1-2 wei per operation * maximum operation count = material drift. | Add: "Worst-case cumulative rounding loss over maximum game duration is bounded at [X wei], derived from [max operation count] * [max per-operation loss]. This does not violate the solvency invariant." |
| Non-VRF affiliate entropy | "Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction." | Does not bound maximum extractable value. Warden can argue the timing attack has higher value than stated. | Add: "Maximum extractable value via affiliate timing: [Y ETH], bounded by affiliate commission BPS ([Z bps]) * maximum single purchase size. No core game funds accessible." |
| Gameover prevrandao fallback | "A block proposer can bias prevrandao (1-bit manipulation on binary outcomes)." | Does not address multi-bit bias via proposer controlling both prevrandao AND transaction ordering. | Add explicit statement that transaction ordering within the block cannot compound the prevrandao bias because [specific reason]. |
| BURNIE ERC-20 deviations | Documented as design decisions. | No composability warnings for external DeFi integrations. | Add per-deviation: "BURNIE is not designed for integration with lending protocols, DEX aggregators, or multisigs. The auto-claim behavior in `_transfer` causes recipient balance changes beyond the transfer amount, violating ERC-20 transfer atomicity assumptions assumed by these protocols." |
| Unchecked `.call{value:}` returns | "ETH conservation proven in v5.0 adversarial audit." | Does not explicitly characterize the fallback-of-fallback path: what happens when BOTH ETH and stETH sends fail. | Add: "When both ETH and stETH sends fail, [specific behavior: funds remain in contract / payout queued / event emitted]. Accounting is not decremented until success confirmed." |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| C4A Rules (STACK.md) | HIGH | Verified against official Code4rena documentation. Payout formula, severity definitions, PoC requirements all from primary sources. |
| Exploit Patterns (FEATURES.md) | MEDIUM-HIGH | Patterns from documented C4A/Sherlock findings and OWASP SC Top 10 2025-2026. Degenerus-specific surface mapping based on code review and prior audit history. |
| Architecture Attack Surfaces (ARCHITECTURE.md) | HIGH | Based on actual codebase review plus documented prior audit milestones. Residual risk assessments grounded in specific prior audit deliverables. |
| Pitfalls (PITFALLS.md) | HIGH | Patterns drawn from real exploit post-mortems (GMX $42M, Yearn $9M, Bunni $2.4M) and documented cognitive bias research. Degenerus-specific examples tied to actual prior bugs (v4.4 BAF cache-overwrite). |

**Overall confidence:** HIGH

### Gaps to Address During Execution

- **Cumulative rounding quantification:** "All rounding favors solvency" needs a computed worst-case bound. W1's primary deliverable should include this calculation as a required output, not just a finding assessment.
- **advanceGame gas profile at adversarial maximum state:** v3.5 profiled 18 paths with 2 AT_RISK. Post-v4.2 changes may have shifted these. W2 should gas-profile `advanceGame` at simultaneous maximum tickets + lootboxes + coinflips before declaring seam analysis complete.
- **120-day inactivity game-over path vs. endgame path:** Prior game-over audits focused on the endgame trigger. W3 should explicitly verify the inactivity trigger propagation is identical.
- **Direct module invocation as PoC target:** Each of the 10 delegatecall modules can be called directly at their deployed address, operating on their own empty storage. The effect has not been characterized as a PoC target. W2 should verify this is safe.

---

## Sources

### Primary (HIGH confidence)
- [Code4rena Awarding Documentation](https://docs.code4rena.com/awarding) — payout formula, share calculation, duplicate rules, partial credit, hunter bonus
- [Code4rena Submission Guidelines](https://docs.code4rena.com/competitions/submission-guidelines) — severity definitions, PoC requirements, QA/Gas rules, known issue exclusions
- [Code4rena Severity Standardization](https://medium.com/code4rena/severity-standardization-in-code4rena-1d18214de666) — High/Medium definitions, judge discretion
- [Chainlink VRF V2 Best Practices](https://docs.chain.link/vrf/v2/best-practices) — VRF security model
- [Lido stETH Integration Guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) — 1-2 wei rounding, shares-based accounting

### Secondary (MEDIUM confidence)
- [Fractional C4A Storage Collision (2022-07)](https://github.com/code-423n4/2022-07-fractional-findings/issues/418) — delegatecall storage pattern precedent
- [Chainlink VRF $300K Immunefi Vulnerability](https://blog.chain.link/smart-contract-research-case-study/) — VRF subscription owner manipulation
- [LooksRare fulfillRandomWords Revert (Sherlock 2023-10)](https://github.com/sherlock-audit/2023-10-looksrare-judging/issues/40) — VRF callback safety
- [Code4rena Renzo stETH Finding (2024-04)](https://github.com/code-423n4/2024-04-renzo-findings/issues/289) — rebasing token accounting
- [Competitive Audit Strategy Guide](https://medium.com/@JohnnyTime/complete-audit-competitions-guide-strategies-cantina-code4rena-sherlock-more-bf55bdfe8542) — warden time allocation
- [OWASP Smart Contract Top 10 2025](https://owasp.org/) — exploit pattern rankings and 2024 loss data
- [Halborn Delegatecall Vulnerabilities](https://www.halborn.com/blog/post/delegatecall-vulnerabilities-in-solidity) — storage collision methodology

### Supporting Context
- Real exploit post-mortems used to calibrate pitfall severity rankings: GMX $42M (cross-component state at boundaries), Yearn $9M (economic invariants not covered by code review), Balancer $70-128M (rounding error sequences), Bunni $2.4M (stateful sequence rounding), Cork Protocol $12M (LST accounting)
- [Pike Finance Storage Collision (CertiK)](https://www.certik.com/resources/blog/pike-finance-incident-analysis) — real-world delegatecall storage corruption consequence
- [PartyDAO Governance Finding (C4A 2023-10)](https://code4rena.com/reports/2023-10-party) — governance manipulation via NFT minting

---
*Research completed: 2026-03-28*
*Ready for roadmap: yes*
