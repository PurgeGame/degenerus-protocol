# Project Research Summary

**Project:** Degenerus Protocol -- Full Contract Audit + Payout Specification (v3.0)
**Domain:** Comprehensive value-transfer security audit of a complex GameFi protocol, targeting C4A competitive audit readiness
**Researched:** 2026-03-17
**Confidence:** HIGH

## Executive Summary

Degenerus v3.0 is not a greenfield audit -- it is the fourth major audit pass on a 25,357-line Solidity codebase with 87 prior audit plans and 90 requirements already satisfied. The research confirms that the defining challenge of this milestone is not finding new tooling or establishing patterns from scratch, but executing a systematic value-transfer sweep across 17+ distribution systems without falling into the confirmation bias trap that comes from deep familiarity with the code. The recommended approach is: audit every payout path as if reading a stranger's code, derive every formula in the payout specification from current Solidity line references (not from prior docs), and treat zero findings as a red flag rather than a success signal.

The highest-stakes target is the GAMEOVER terminal distribution path, which converges all remaining protocol funds into a single execution sequence involving deity refunds, a new terminal decimator allocation (490 lines of uncommitted code across 7 files), a terminal jackpot, and a 50/50 vault/sDGNRS sweep. A single accounting error in `handleGameOverDrain` cannot be retried. The terminal decimator code is the one area in this milestone with zero prior audit coverage -- it is new, it modifies the most critical code path, and it must be audited from scratch. The research also establishes that the payout specification HTML document is the milestone's primary C4A-facing deliverable and must be written last, only after all audit phases have produced verified ground truth to draw from.

The toolchain is already in place: Slither 0.11.5, Hardhat, Foundry, and OpenZeppelin 5.4.0 are installed and configured. No new npm or pip dependencies are needed. Mermaid CLI is used via `npx -y` for diagram rendering, and the payout specification is a hand-authored single-file HTML document with inline SVGs. The key risks that could cause the audit to produce false confidence are: (1) self-audit bias anchoring to prior audit verdicts instead of re-verifying current code, (2) a missed `claimablePool` update creating a solvency invariant violation, and (3) the payout specification being written from the v1.1 economics primer rather than from current contract code.

## Key Findings

### Recommended Stack

The existing toolchain satisfies all v3.0 needs without additions. Slither 0.11.5 (already installed) provides the static analysis layer via targeted detector suites for reentrancy, arbitrary-send, unchecked-transfer, and controlled-delegatecall classes, plus structural printers (call-graph, function-summary, vars-and-auth, data-dependency) for manual audit cross-referencing. Mermaid CLI (via npx) is the diagram authoring tool for the payout specification -- text-based, diffable, renders to SVG for inline embedding. Graphviz `dot` is needed only for rendering Slither's call-graph DOT output and can be replaced by an online viewer.

**Core technologies:**
- **Slither 0.11.5:** Value-transfer static analysis -- 90+ detectors covering all relevant classes; already installed; run against full contract set (not just DegenerusAdmin as in v2.1)
- **Mermaid CLI (npx -y):** Payout spec diagram authoring -- text-based source in version control, renders to SVG for inline embedding; no package.json dependency needed
- **Hand-authored HTML + inline CSS:** Payout specification document -- single-file self-contained deliverable; precise layout control; zero runtime dependencies; print-friendly for PDF export
- **Graphviz dot (optional):** Render Slither call-graph DOT output to SVG for cross-referencing; can be replaced by online viewer if not installed

**What NOT to add:** Mythril (duplicates Slither coverage at 10-100x slower speed), Echidna (Foundry invariant tests already cover fuzz/invariant needs), Certora (formal verification deferred to v3.1+ per PROJECT.md).

### Expected Features

The audit has five categories of work. GAMEOVER path audit and payout/claim path audits are the core deliverables. Recent changes verification, invariant verification, and documentation correctness are supporting but mandatory. The payout specification HTML document is the terminal deliverable that depends on all others.

**Must have (table stakes):**
- GAMEOVER path audit (handleGameOverDrain, handleFinalSweep, death clock escalation, RNG fallback) -- highest fund concentration, single execution, no retry
- Terminal decimator audit (490 lines of new uncommitted code, zero prior coverage) -- directly modifies GAMEOVER critical path
- All 17+ payout/claim path audits -- independent value-transfer paths, each individually verifiable by C4A wardens
- claimablePool solvency invariant re-verification (16+ mutation sites, new terminal decimator sites added)
- Payout specification HTML document (primary C4A deliverable; all 17+ systems with exact code references, diagrams, invariant annotations)
- NatSpec and inline comment correctness sweep (bulk QA findings in C4A if missed)

**Should have (competitive differentiators):**
- Per-system flow diagrams in payout spec -- makes every distribution visually traceable, eliminates "undocumented protocol" findings
- Edge case matrix documentation -- GAMEOVER at level 0, levels 1-9, x00, single player; preempts "what if?" warden submissions
- Token flow matrix -- single-table reference for which tokens touch which systems; quick coverage-completeness check for wardens
- War-game scenario documentation (whale manipulation, coordinated timing, terminal decimator cartel) -- preempts economic design challenge findings

**Defer to v3.1+:**
- Foundry fuzz invariant tests for governance paths
- Formal verification via Halmos (explicitly deferred in PROJECT.md)
- Monte Carlo simulation of game outcomes
- Gas optimization beyond correctness

### Architecture Approach

The audit scope maps 72 verified value-transfer call sites across 17 contract files, with 10 ETH exit points, 11 stETH transfer points, and token transfer points across BURNIE/sDGNRS/DGNRS/WWXRP/DGVE. The core game dispatcher (DegenerusGame.sol) uses delegatecall to 11 modules that share storage via identical inheritance from DegenerusGameStorage. The critical architectural risk is that `handleGameOverDrain` executes in the game's storage context and calls multiple modules that each independently modify `claimablePool` -- there is no atomic lock on the solvency invariant across the sequence of external calls within a single GAMEOVER execution.

**Six audit areas in strict dependency order:**
1. **GAMEOVER Path (Area 1):** handleGameOverDrain + handleFinalSweep + death clock + terminal decimator integration -- no dependencies, this is the audit root
2. **Payout/Claim Paths (Area 2):** 22 named distribution entry points across 7+ modules -- depends on Area 1 for terminal context
3. **Recent Changes Verification (Area 3):** Terminal decimator (7 files, 490 new lines) + post-v2.1 hardening (CEI fix, death clock pause removal) -- depends on Areas 1-2 for baseline
4. **Invariant Verification (Area 4):** Solvency, claimablePool accounting, sDGNRS supply, BURNIE mint authority, pool BPS conservation -- requires Areas 1-3 to map all mutation sites first
5. **Documentation Correctness (Area 5):** NatSpec, inline comments, storage layout, parameter reference -- requires Areas 1-4 to establish ground truth
6. **Edge Cases and Griefing Analysis (Area 6):** All boundary conditions -- speculative without full system knowledge from prior areas

**Key patterns to enforce in audit verification:**
- Credit-Then-Pool: every `claimableWinnings[x] += amount` must pair with `claimablePool += amount`
- Claim-Then-Send (CEI): sentinel set and pool decremented before any external call
- Budget-Capped Distribution: deity refund loop uses `budget = totalFunds - claimablePool`; decrements before crediting
- Delegatecall Self-Call: `IDegenerusGame(address(this)).runX(...)` guards require `msg.sender == address(this)`

### Critical Pitfalls

1. **Self-audit bias (CP-01)** -- Fourth audit pass on the same codebase creates "known correct" anchoring. Derive every payout path description independently from Solidity before consulting any prior audit doc. Apply the "zero findings = red flag" rule. Use inversion technique: write "how could a warden claim this loses funds?" before examining code.

2. **claimablePool invariant violation at GAMEOVER boundary (CP-02)** -- handleGameOverDrain makes sequential state-modifying calls to multiple modules; a missed update or unexpected return value permanently desynchronizes `claimablePool` from actual balances. Trace claimablePool through every single line. Verify `decRefund <= decPool` mathematically. Write a Foundry invariant test asserting `balance + stETH >= claimablePool` after every GAMEOVER scenario.

3. **Payout spec derived from prior docs, not current code (CP-03)** -- The v1.1 economics primer was written before the terminal decimator was added to the GAMEOVER flow. A spec copied from the primer describes "10% to Decimator" when the code now routes to the *terminal* decimator with refund recycling. Every formula and BPS value in the spec must cite a specific file:line in current code.

4. **Rounding accumulation in multi-step distributions (CP-04)** -- Eight distinct multi-step distribution mechanisms. The Balancer exploit ($70-128M) demonstrated that sub-wei rounding compounds. Verify the remainder pattern is applied independently in each of the 8 mechanisms. Pay special attention to BAF scatter (50 rounds, 2 tiers = 100 division operations).

5. **Auto-rebuy during GAMEOVER creates phantom tickets (CP-05)** -- `_addClaimableEth` has four separate implementations (EndgameModule, DecimatorModule, JackpotModule, DegeneretteModule). Each must independently check `gameOver = true` to suppress auto-rebuy. Any implementation that does not check `gameOver` is a finding.

## Implications for Roadmap

Based on the architecture dependency graph and risk ordering established across all four research files:

### Phase 26: GAMEOVER Path Audit

**Rationale:** All remaining protocol funds converge into this single code path. The terminal decimator is new uncommitted code that directly modifies it. A bug here is the highest-severity possible finding -- total fund loss, no retry. All other audit areas depend on understanding GAMEOVER context first.

**Delivers:** Verified GAMEOVER terminal distribution; confirmed terminal decimator integration; verified death clock escalation; confirmed _sendToVault accounting; verified deity refund FIFO and budget-cap logic.

**Addresses:** GAMEOVER path audit, terminal decimator audit, death clock verification, RNG fallback verification, deity refund ordering, _sendToVault stETH/ETH split correctness.

**Avoids:** CP-02 (invariant violation), CP-05 (auto-rebuy phantom tickets), MP-02 (lvl+1 targeting undocumented), MP-04 (stETH rounding at GAMEOVER).

**Research flag:** NONE -- GAMEOVER logic is fully specified in v1.1-endgame-and-activity.md, PLAN-TERMINAL-DECIMATOR.md, and direct code.

### Phase 27: Payout/Claim Path Audit

**Rationale:** Each of the 17+ distribution systems is an independent value-transfer path. Phase 26 establishes terminal context; Phase 27 covers normal gameplay paths. CEI verification for all claim functions must be re-verified from code (not cited from prior audit) because terminal decimator adds a new claim path with zero prior coverage.

**Delivers:** Per-system invariant verification for all 22 named distribution entry points; CEI confirmation for every claim path; auto-rebuy suppression verified in all four `_addClaimableEth` implementations; complete mutation site inventory for Phase 28.

**Addresses:** Daily jackpot, 5-day jackpot phase draws, BAF distribution, decimator payout, terminal decimator claims, coinflip, lootbox, affiliate, stETH yield, quest rewards, bounties, DGNRS burn, vault redemption, claimWinnings pull pattern.

**Avoids:** CP-01 (self-audit bias -- treat each path as a stranger's code), CP-04 (rounding accumulation -- verify remainder pattern in each mechanism), MP-03 (claimableWinnings/claimablePool pairing), MP-06 (false positive reentrancy).

**Research flag:** NONE -- all 17+ systems are fully specified in v1.1 economics docs. Use direct code analysis per CP-01 mitigation.

### Phase 28: Recent Changes + Invariant Verification

**Rationale:** Recent changes are the highest probability location for new bugs. The terminal decimator (490 lines across 7 files) has zero prior audit coverage. Invariant verification requires Phases 26-27 to have mapped all mutation sites first -- exhaustive verification is impossible before that mapping is complete.

**Delivers:** Terminal decimator code review (all 490 new lines); VRF governance regression check; solvency invariant verified at all mutation sites; sDGNRS supply conservation confirmed; BURNIE mint authority confirmed; pool BPS sums verified.

**Addresses:** Recent changes verification (CEI fix, death clock pause removal, activeProposalCount removal, deity soulbound enforcement), invariant re-verification across all mutation sites including new terminal decimator paths.

**Avoids:** CP-03 (stale docs -- diff all modified files against v1.1 primer), CP-02 (GAMEOVER invariant boundary -- verified after full path understanding from Phases 26-27).

**Research flag:** NONE -- terminal decimator is specified in PLAN-TERMINAL-DECIMATOR.md; invariant patterns are established from v1.0 ACCT series.

### Phase 29: Documentation Correctness + Edge Cases

**Rationale:** Comments and NatSpec cannot be verified for accuracy until the code's ground truth is established in Phases 26-28. Edge cases are combinatorial -- reasoning about boundary conditions requires deep understanding of all distribution systems and invariant properties.

**Delivers:** NatSpec corrected for all new/changed functions; storage layout comments verified; parameter reference updated with terminal decimator constants; edge case matrix for GAMEOVER scenarios (level 0, levels 1-9, x00, single player, zero terminal decimator participants); gas griefing bounds verified for deity refund loop.

**Addresses:** Comment correctness, NatSpec accuracy, storage documentation; edge case analysis (GAMEOVER level 0 edge, single-player, gas griefing, timing attacks, terminal decimator with zero participants). War-game scenario documentation (whale manipulation, coordinated timing, terminal decimator cartel).

**Avoids:** CP-01 (self-audit bias in edge case reasoning), mP-05 (NatSpec inaccuracies), mP-04 (finalSwept flag with post-sweep deposits).

**Research flag:** NONE -- NatSpec patterns are standard; edge case scenarios are derived directly from the GAMEOVER architecture research.

### Phase 30: Payout Specification Document

**Rationale:** The payout specification is a synthesis of all prior phases and must be written last. Writing it speculatively would encode unverified assumptions. This is the terminal deliverable for C4A readiness. Per ARCHITECTURE.md, this document consumes verified descriptions from Phases 26-29 -- it cannot be accurate before those phases complete.

**Delivers:** audit/PAYOUT-SPECIFICATION.html -- self-contained HTML document covering all 17+ distribution systems with per-system Mermaid flow diagrams, exact file:line code references, invariant annotations, failure mode documentation (zero-pool, no-recipients, revert, expiry), and edge case coverage. Version-stamped with git commit hash.

**Addresses:** Complete payout specification, per-system flow diagrams, exact code references, invariant annotations per system, edge case documentation per system, token flow matrix, sentinel wei pattern documentation, decimator claim expiry documentation, lvl+1 targeting rationale, whale pass conversion documentation, deity FIFO ordering.

**Avoids:** CP-03 (spec derived from code not docs -- every formula cites file:line), MP-01 (missing failure modes -- every system documents failure scenarios), MP-07 (sentinel wei pattern documented), mP-01 (deity FIFO ordering documented), mP-02 (whale pass conversion documented).

**Research flag:** YES -- before authoring, create a coverage matrix mapping each of the 22+ distribution entry points to a spec section, its diagram type, and its failure modes. Without this matrix, systems can be accidentally omitted or claim windows mischaracterized.

### Phase Ordering Rationale

- GAMEOVER before payout paths: terminal distribution is the root context; payout paths during GAMEOVER behave differently than during normal gameplay (auto-rebuy suppressed, pools zeroed).
- Payout paths before invariant verification: solvency invariant verification requires exhaustive mutation site enumeration, which Phase 27 produces.
- Invariants before documentation: comments are descriptions of truth; establish truth first, then verify descriptions match.
- Documentation before payout specification: the spec must describe verified behavior; Phase 29 corrects any stale NatSpec so Phase 30 has accurate descriptions to synthesize.
- Payout specification last: synthesis document; writing it before verification completes requires rework.

### Research Flags

Phases needing deeper research or prep during planning:
- **Phase 30 (Payout Specification):** Pre-authoring coverage matrix needed -- map each of the 22+ distribution entry points to a spec section, diagram type, and failure mode list. Without this, accidental omissions are likely given the scope.

Phases with standard patterns (skip research-phase):
- **Phase 26 (GAMEOVER):** Fully specified in v1.1-endgame-and-activity.md and PLAN-TERMINAL-DECIMATOR.md. Direct code analysis is the complete methodology.
- **Phase 27 (Payout Paths):** All 17+ systems specified in v1.1 economics docs. No novel patterns.
- **Phase 28 (Invariants):** ACCT-01 through ACCT-10 establish the baseline. Terminal decimator adds mutation sites; same verification methodology applies.
- **Phase 29 (Comments/Edge Cases):** NatSpec patterns are standard; edge cases flow directly from GAMEOVER architecture analysis.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified installed locally; versions confirmed against PyPI and npm; "no Mythril" recommendation verified against detector coverage overlap |
| Features | HIGH | Based on direct code inspection of all 23 contracts, 87 prior plans, established C4A methodology; feature list is exhaustive not aspirational |
| Architecture | HIGH | All 23 contract source files, 12 module files, and 42 audit documents directly inspected; terminal decimator changes reviewed via git diff; 10 ETH exit points and 11 stETH transfer points enumerated precisely |
| Pitfalls | MEDIUM-HIGH | Code-specific pitfalls (CP-02 through CP-05) are HIGH -- derived from direct code analysis. Self-audit bias framework (CP-01) is MEDIUM -- corroborated by ACM cognitive bias research and blockchain audit industry practices |

**Overall confidence:** HIGH

### Gaps to Address

- **Terminal decimator code not yet committed:** The 490-line terminal decimator changes exist as uncommitted modifications. Phases 26 and 28 must be executed against the final committed code. If the implementation diverges from PLAN-TERMINAL-DECIMATOR.md, phase plans need adjustment.
- **HTML payout spec build pipeline not prototyped:** The Mermaid-to-SVG-to-inline-HTML pipeline is straightforward in principle but has not been executed for this project. Phase 30 should begin with a single-system proof-of-concept (e.g., claimWinnings pipeline) before authoring all 17+ systems.
- **C4A severity boundary for rounding findings:** Whether a C4A warden would file rounding findings as Medium or QA depends on their interpretation of impact. The payout spec's explicit rounding documentation is the primary mitigation; its effectiveness will only be confirmed during the actual C4A.
- **Slither compatibility with Solidity 0.8.34 + via_ir:** Not explicitly confirmed in documentation, but tested working in the existing npm script. Flag as a verification item at the start of Phase 26 static analysis runs.

## Sources

### Primary (HIGH confidence)

Direct code analysis:
- `contracts/modules/DegenerusGameGameOverModule.sol` -- terminal distribution logic (handleGameOverDrain, handleFinalSweep, _sendToVault)
- `contracts/DegenerusGame.sol` -- claim pipeline (_claimWinningsInternal, _payoutWithStethFallback, _payoutWithEthFallback, all delegatecall routing)
- `contracts/modules/DegenerusGameDecimatorModule.sol` -- decimator and terminal decimator claim/resolution
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout, claimablePool, claimableWinnings
- All 23 contract source files and 12 module files in `contracts/`
- All 42 audit documents in `audit/`
- Uncommitted terminal decimator changes (7 files, 490 lines) via git diff
- `.planning/PLAN-TERMINAL-DECIMATOR.md` -- terminal decimator specification
- `.planning/PROJECT.md` -- v3.0 milestone definition
- `audit/FINAL-FINDINGS-REPORT.md` -- 87 plans, 90 requirements, severity distribution
- `audit/KNOWN-ISSUES.md` -- known issues and design tradeoffs
- `audit/v1.1-ECONOMICS-PRIMER.md` -- all 13 economic subsystem references
- `audit/v1.1-endgame-and-activity.md` -- death clock and terminal distribution
- `audit/v1.1-transition-jackpots.md` -- BAF and decimator mechanics
- `audit/v2.1-governance-verdicts.md` -- 26 governance verdicts
- Slither 0.11.5 verified installed locally (`slither --version` = 0.11.5)
- [Slither GitHub Repository](https://github.com/crytic/slither) -- 90+ detectors, 18 printers
- [Mermaid.js CLI GitHub](https://github.com/mermaid-js/mermaid-cli) -- mmdc CLI
- [PyPI slither-analyzer 0.11.5](https://pypi.org/project/slither-analyzer/) -- released 2026-01-16

### Secondary (MEDIUM confidence)

- [Cyfrin: 10 Steps to Smart Contract Audit](https://www.cyfrin.io/blog/10-steps-to-systematically-approach-a-smart-contract-audit) -- audit methodology
- [Dacian.me: Precision Loss Errors](https://dacian.me/precision-loss-errors) -- rounding error amplification
- [Coinmonks: Audited, Tested, and Still Broken](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Balancer rounding exploit ($70-128M), audit gap analysis
- [OpenZeppelin audit readiness guide](https://learn.openzeppelin.com/security-audits/readiness-guide) -- pre-audit documentation requirements
- [ACM: Cognitive Biases in Software Development](https://cacm.acm.org/research/cognitive-biases-in-software-development/) -- confirmation bias in code review
- [Code4rena severity standardization](https://medium.com/code4rena/severity-standardization-in-code4rena-1d18214de666) -- C4A severity criteria

### Tertiary (LOW confidence)

- [Hacken: Smart Contract Audit Process](https://hacken.io/discover/smart-contract-audit-process/) -- fund flow analysis preparation
- [BlockApex: Smart Contract Audit Services](https://blockapex.io/smart-contract-audit-services/) -- siloed team review methodology
- [Arxiv: Towards Debiasing Code Review](https://arxiv.org/html/2407.01407v1) -- debiasing techniques for self-review

---
*Research completed: 2026-03-17*
*Ready for roadmap: yes*
