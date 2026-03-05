# Project Research Summary

**Project:** Degenerus Protocol v5.0 -- Novel Zero-Day Attack Surface Audit
**Domain:** Smart contract security audit -- zero-day hunting on 22-contract delegatecall GameFi architecture
**Researched:** 2026-03-05
**Supersedes:** SUMMARY.md dated 2026-03-05 (v4.0 adversarial stress test)
**Confidence:** MEDIUM-HIGH

## Executive Summary

Degenerus Protocol is a 22-contract, 10-module delegatecall GameFi system that has survived four audit milestones (v1.0-v4.0) with zero Medium+ findings across 103 plans and 10 independent blind adversarial agents. The v5.0 milestone shifts from manual review to automated tooling and novel attack surface hunting -- specifically targeting composition bugs (cross-module shared storage corruption via 30 delegatecall sites), precision/rounding exploitation (222 division operations across 21 files), temporal edge cases (14 timestamp uses, 5 timeout boundaries), EVM-level weirdness (231 unchecked blocks, 15 assembly blocks, BitPackingLib gap bits 155-227), and cross-system economic composition. The existing tool stack (Foundry 1.5.1, Halmos 0.3.3, Slither 0.11.5) requires zero new installations -- only configuration changes (Foundry deep/ci profiles) and new test harnesses (4 composition-focused handlers, 5 Halmos property files, 4 invariant test files).

The recommended approach centers on three principles: (1) write NEW invariant harnesses targeting v5.0-specific attack surfaces rather than increasing run counts on existing v3.0 tests, (2) scope Halmos to isolated pure math functions only (BitPackingLib, PriceLookupLib, JackpotBucketLib) where it is proven effective and avoid full-contract symbolic execution that will timeout, and (3) cross-reference all three tools at the function level -- a function flagged by 2+ tools is highest priority regardless of individual tool severity. The six suggested phases follow a strict dependency order: tooling setup first (storage layouts are prerequisite), then composition and precision analysis in parallel (the two highest-value zero-day classes), then temporal/EVM and economic analysis, with Halmos verification and multi-tool synthesis last.

The dominant risk is "5th pass confirmation bias": four clean milestones create an overwhelming psychological anchor that the code is safe, causing analysts to reduce scrutiny on genuinely novel surfaces and default to re-checking known vulnerability classes. Industry data shows ~70% of major DeFi exploits come from audited contracts (median 47 days post-audit). The mitigation is structural: allocate investigation time by INVERSE of prior coverage, structure work by protocol-specific attack surfaces (not SWC/OWASP checklists), and require 50%+ of effort on surfaces with zero prior v1-v4 coverage. A secondary risk is Halmos timeout misinterpretation -- v3.0 saw 7/12 properties timeout, and TIMEOUT is NOT "verified." All bounds must be reported honestly.

## Key Findings

### Recommended Stack

No new tools needed. The existing infrastructure is at latest versions and sufficient for v5.0 scope. Total new dependencies: zero (one optional: slitherin pip package for 20+ additional Slither detectors).

**Configuration changes only:**
- **Foundry deep/ci profiles** (foundry.toml): 10K fuzz runs, 1K invariant runs, 256 depth -- keeps default profile fast while enabling deep hunting via `FOUNDRY_PROFILE=deep`
- **Halmos 0.3.3**: Scope to pure math verification -- PriceLookupLib, BitPackingLib, JackpotBucketLib, DeityPricing, LootboxEV. Use `--solver-timeout-assertion 300000` for nonlinear arithmetic
- **Slither 0.11.5**: Full triage with JSON output, category-focused runs (reentrancy, delegatecall, arithmetic), per-finding suppression (never bulk-exclude categories)
- **New Foundry handlers**: CompositionHandler, PrecisionHandler, TemporalHandler, LifecycleHandler -- these are the actual v5.0 deliverables, not run count increases on existing tests

### Expected Features

**Must have (table stakes for a credible zero-day hunt):**
- Cross-contract state composition graph -- foundation for composition bugs; without this the hunt is another line-by-line review
- Precision/rounding systematic sweep -- division-before-multiplication and zero-rounding are the #1 bug class surviving multiple audits per industry data
- Forced ETH (selfdestruct/coinbase) balance check -- simple to verify, catastrophic if missed
- Vault share inflation re-examination -- highest-value single vector; first-depositor/donation attacks are the most common post-audit vault bug
- Multi-step gameOver interleaving test -- protocol-specific high-value race condition
- Foundry fuzz campaigns at 10K+ runs with NEW composition-aware harnesses

**Should have (differentiators):**
- Slither full triage with custom detectors for protocol-specific patterns
- Halmos symbolic verification of pricing math (proves no input violates invariants across entire input space)
- Timestamp boundary off-by-one analysis (>= vs > at exact timeout boundaries)
- Packed storage boundary value testing (BitPackingLib at 2^N-1 values)
- Multi-tool convergence analysis (function-level signal matrix across Slither/Halmos/Foundry)

**Defer (diminishing returns given v1-v4 clean results):**
- Full ABI encoding edge case analysis -- well-typed entry points reduce risk
- CREATE2/address prediction attacks -- one-time deploy pipeline
- Circular affiliate reward analysis -- low expected yield
- stETH rebasing during multi-step operations -- bounded by daily rebasing rate (~0.01%)
- Formal ETH taint tracking -- v2.0 manual ACCT analysis was comprehensive

### Architecture Approach

The zero-day audit is an analysis overlay on the existing protocol, not new contract code. It produces Foundry test harnesses, Slither triage artifacts, and Halmos verification properties targeting five attack surface categories mapped to specific contract interfaces and data flows. The critical architectural insight is that composition bugs can ONLY occur through the 10 delegatecall modules sharing DegenerusGameStorage -- regular inter-contract calls use message passing and do not share storage.

**Major analysis targets (by priority):**
1. **DegenerusGame (19KB, 30 delegatecall sites)** -- CRITICAL: composition bugs in sequences of storage mutations across modules
2. **DegenerusGameStorage (shared state)** -- CRITICAL: BitPackingLib gap bits 155-227, cross-module packed slot races
3. **JackpotModule (40 unchecked, 27 divisions)** -- HIGH: double-division in bucketShares(), rounding to zero in small pools
4. **MintModule (15 unchecked, 4 assembly SSTOREs)** -- HIGH: cost formula precision, dust-free minting
5. **LootboxModule (39 divisions)** -- HIGH: heaviest division surface, EV calculation precision
6. **GameTimeLib** -- MEDIUM: 22:57 UTC day boundary, underflow potential, proposer manipulation
7. **DegenerusVault** -- MEDIUM: donation attack re-examination, stETH rebasing interaction

### Critical Pitfalls

1. **"5th Pass Confirmation Bias"** -- Four clean milestones anchor toward confirming safety rather than discovering flaws. Mitigate by allocating time INVERSELY to prior coverage; require 50%+ effort on genuinely novel surfaces.

2. **Slither False Positive Fatigue (636 results)** -- Bulk-dismissal after hundreds of known false positives buries genuine findings. Mitigate with per-finding suppression (never category-level), reverse priority order (new detectors first), hard 2-hour triage time-box.

3. **Halmos Timeout Interpreted as "Verified Safe"** -- TIMEOUT is NOT verification. v3.0 had 7/12 properties timeout. Scope Halmos to isolated pure functions only; complement with Foundry fuzz for the same properties; report all bounds honestly.

4. **Foundry Run Count Theater** -- 10K runs on existing v3.0 harnesses tests the same constrained input space more times without covering v5.0 surfaces. Write NEW handlers for precision, temporal, and composition. Track coverage metrics before/after.

5. **Anchoring on Known Vulnerability Classes** -- Checking reentrancy, access control, overflow (thoroughly covered by v1-v4) instead of protocol-specific surfaces. Structure investigation by protocol-specific attack surfaces, not SWC/OWASP categories.

## Implications for Roadmap

Based on research, suggested 6-phase structure:

### Phase 1: Tooling Setup and Static Analysis
**Rationale:** Storage layout data is prerequisite for composition and temporal analysis. Selector collision check is fast and eliminates/confirms an entire attack class immediately. Slither triage produces the signal matrix guiding all subsequent phases.
**Delivers:** Foundry deep/ci profiles configured, `forge inspect` storage layouts for all 22 contracts, selector collision check, Slither full triage with JSON output, optional slitherin sweep
**Addresses:** Forced ETH balance check, function selector collision, Slither detector coverage
**Avoids:** Pitfall #7 (Slither version mismatch) -- document exact version; Pitfall #2 (false positive fatigue) -- per-finding suppression, reverse priority triage

### Phase 2: Composition Analysis
**Rationale:** Composition bugs are the highest-severity zero-day class (state corruption, fund loss). Must come before economic analysis because composition findings may reveal new attack surfaces. Scoped to 10 delegatecall modules only to prevent scope creep.
**Delivers:** Storage slot ownership matrix, CompositionHandler with ghost variable tracking, composition invariant tests, cross-module state assumption verification
**Addresses:** Delegatecall shared storage re-derivation, cross-module state corruption via ordering, multi-module transaction atomicity, view function state dependency, BitPackingLib storage overlap
**Avoids:** Pitfall #6 (scope creep) -- time-box to 30% of total effort, delegatecall modules only

### Phase 3: Precision and Rounding Analysis (parallel with Phase 2)
**Rationale:** Independent of composition (no data dependencies). Precision/rounding is the #1 bug class surviving multiple audits per industry data. 222 division operations across 21 files is a large concrete surface.
**Delivers:** PrecisionHandler, precision boundary invariant tests, JackpotBucketLib bucketShares() deep fuzz, zero-rounding free action detection, wei lifecycle trace through purchase-to-claim
**Addresses:** Division-before-multiplication chains, zero-rounding free actions, dust accumulation, lootbox EV precision, coinflip range precision, deity pass T(n) precision
**Avoids:** Pitfall #10 (per-operation not chain analysis) -- cumulative rounding invariant across full transaction lifecycle

### Phase 4: Temporal and EVM-Level Analysis
**Rationale:** Depends on Phase 1 storage layouts. Moderate severity but protocol-specific targets -- 5 timeout boundaries, 231 unchecked blocks, 15 assembly blocks are concrete and bounded.
**Delivers:** TemporalHandler with vm.warp at boundary timestamps, StorageSlotVerifier for assembly SSTORE operations, BitPackingLib gap bit corruption test, ETH forcing test on 3 receive() contracts, timestamp boundary off-by-one analysis, timeout interaction tests
**Addresses:** Multi-step gameOver race, VRF callback timing, level transition boundaries, packed storage corruption, assembly safety
**Avoids:** Pitfall #11 (isolated timeout testing) -- test timeout INTERACTIONS; Pitfall #9 (source-only analysis) -- use forge inspect, bytecode verification

### Phase 5: Economic Composition Analysis
**Rationale:** Depends on Phase 3 precision results -- if minting can be nearly free via precision exploit, economic exploitation is amplified. Must follow precision analysis.
**Delivers:** Vault share inflation re-examination, Stonk sandwich analysis, circular affiliate reward test, cross-contract EV exploitation analysis, stETH rebasing edge case verification
**Addresses:** Vault donation attack, price curve manipulation, whale bundle + lootbox interaction, BurnieCoin supply manipulation, quest streak farming
**Avoids:** Pitfall #1 (confirmation bias) -- re-derive vault math independently rather than trusting v2.0 conclusions

### Phase 6: Halmos Verification and Multi-Tool Synthesis
**Rationale:** Halmos confirms specific properties discovered in Phases 2-5. Synthesis requires all tool runs complete for function-level signal matrix. This is the capstone phase.
**Delivers:** Halmos properties for BitPackingLib roundtrip, EntropyLib absorbing states, JackpotBucketLib share sum, PriceLookupLib monotonicity. Function-level multi-tool convergence matrix. Final findings report with coverage delta from v1-v4.
**Addresses:** "Auditors were wrong" re-examination, ETH solvency re-derivation, CEI re-verification, multi-tool convergence
**Avoids:** Pitfall #3 (timeout = verified) -- honest bounds reporting; Pitfall #15 (trivially true properties); Pitfall #12 (sequential tools) -- cross-reference all signals; Pitfall #14 (uncalibrated results) -- coverage delta from v1-v4

### Phase Ordering Rationale

- **Tooling first** because storage layout data is prerequisite for composition and temporal analysis, and Slither triage produces the signal matrix guiding manual work
- **Phases 2 and 3 parallel** because composition and precision are independent analysis streams targeting the two highest-value zero-day classes
- **Phase 4 after tooling** because it depends on storage layouts and is moderate severity
- **Phase 5 after precision** because precision results determine whether cheap-mint economic exploits are possible
- **Phase 6 last** because symbolic verification confirms properties from earlier phases, and synthesis requires all data

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Composition):** Requires building a storage slot ownership matrix from `forge inspect` output for all 10 modules -- no prior phase has this artifact. The 30 delegatecall sites need systematic mapping.
- **Phase 3 (Precision):** 222 division operations need classification by risk. The "wei lifecycle" trace is novel analysis with no established template.
- **Phase 6 (Halmos):** v3.0 saw 7/12 properties timeout. Phase planning must scope properties conservatively and include a triage step for timeouts.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Tooling Setup):** Foundry profiles, Slither runs, forge inspect are well-documented with stable APIs.
- **Phase 4 (Temporal/EVM):** Temporal boundary testing with vm.warp and storage verification with vm.load are established Foundry patterns.
- **Phase 5 (Economic):** Vault donation attacks and sandwich analysis have extensive C4A precedent to follow.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools at latest versions, zero installations needed, configuration-only changes with stable documented APIs |
| Features | MEDIUM | Attack surface categories well-defined but yield uncertain -- protocol may genuinely be clean after 4 milestones, or v5.0 may find what 10 agents missed |
| Architecture | HIGH | Protocol fully mapped from source: 30 delegatecall sites, 222 divisions, 231 unchecked blocks, 15 assembly blocks all counted with high confidence |
| Pitfalls | HIGH | Grounded in industry exploit data (70% of exploits from audited contracts), documented tool limitations (Halmos v3.0 timeouts), and cognitive bias research |

**Overall confidence:** MEDIUM-HIGH -- tooling and architecture are well-understood, but the fundamental question "will v5.0 find anything new?" is inherently uncertain. The research provides a rigorous framework; whether findings exist is unknown.

### Gaps to Address

- **Halmos feasibility for complex properties:** v3.0 saw 7/12 properties timeout. Phase 6 must triage properties that timeout after 5 minutes to "fuzz-only" rather than consuming hours of solver time.
- **Composition handler design:** No template exists for ghost-variable-tracking handlers that snapshot storage across delegatecall boundaries. Phase 2 will need to design this pattern from scratch.
- **Coverage metrics baseline:** Need Foundry code coverage BEFORE v5.0 harness development to measure the delta. Without baseline, cannot prove v5.0 tested new code paths.
- **Slither viaIR compatibility:** Slither may struggle with viaIR compilation artifacts. Fallback: compile with viaIR disabled for Slither-only analysis if errors occur.
- **Same-auditor bias persists:** v5.0 uses the same model as v1-v4. Automated tools (Slither, Halmos, Foundry) partially mitigate this by providing independent oracles, but the interpretation of tool output is still subject to the same model's blind spots.

## Sources

### Primary (HIGH confidence)
- Contract source code analysis (all files in `contracts/` directory)
- Existing Foundry infrastructure (`test/fuzz/` -- 68 invariant tests, 9 harnesses)
- Existing Halmos infrastructure (10 symbolic properties verified in v3.0)
- DegenerusGameStorage.sol -- packed slots 0-2, gap at bits 155-227
- [Foundry Invariant Testing Docs](https://getfoundry.sh/forge/invariant-testing)
- [Foundry Config Reference](https://www.getfoundry.sh/config/reference/overview)
- [Halmos GitHub](https://github.com/a16z/halmos) -- v0.3.3 latest
- [Halmos Wiki: Warnings](https://github.com/a16z/halmos/wiki/warnings) -- nonlinear arithmetic limitations
- [Slither GitHub](https://github.com/crytic/slither) -- v0.11.5, 10.9% FP rate for reentrancy
- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation) -- 90+ detectors
- v4.0 Synthesis Report (29-01) -- 10/10 agents zero Medium+
- v2.0 ACCT-01 through ACCT-10 -- ETH solvency invariants

### Secondary (MEDIUM confidence)
- [OWASP Smart Contract Top 10 2026](https://owasp.org/www-project-smart-contract-top-10/) -- SC-01 through SC-10
- [Olympix: State of Web3 Security 2025](https://olympix.security/blog/the-state-of-web3-security-in-2025-why-most-exploits-come-from-audited-contracts) -- 70% exploits from audited contracts
- [Guardian Audits: Division Precision Loss](https://lab.guardianaudits.com/encyclopedia-of-common-solidity-bugs/division-precision-loss)
- [Dacian: Precision Loss Errors](https://dacian.me/precision-loss-errors) -- C4A finding patterns
- [Pessimistic.io slitherin](https://github.com/pessimistic-io/slitherin) -- 20+ additional detectors
- [Hacken: Top 10 Smart Contract Vulnerabilities 2025](https://hacken.io/discover/smart-contract-vulnerabilities/)
- [Medium/Coinmonks: Audited, Tested, and Still Broken](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- rounding exploit patterns

### Tertiary (LOW confidence)
- [Verichains: ABI Encoding Exploit](https://blog.verichains.io/p/soliditys-hidden-flexibility-how) -- needs validation against well-typed entry points
- [SmartState: State-Reverting Vulnerabilities](https://arxiv.org/html/2406.15988v1) -- academic methodology, applicability uncertain

---
*Research completed: 2026-03-05*
*Supersedes: SUMMARY.md dated 2026-03-05 (v4.0 adversarial stress test)*
*Ready for roadmap: yes*
