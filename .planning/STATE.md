---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: completed
last_updated: "2026-03-17T00:12:53.594Z"
last_activity: 2026-03-17 — Completed 21-03 (invariants and privilege escalation)
progress:
  total_phases: 5
  completed_phases: 3
  total_plans: 9
  completed_plans: 9
---

# State

## Current Position

Phase: 21 (Novel Attack Surface)
Plan: 04 of 4 -- COMPLETE
Status: Phase 21 complete. All 4 plans executed: economic/amplifier attacks, composition/griefing/edge cases, invariants/privilege, timing/race conditions.
Last activity: 2026-03-17 — Completed 21-03 (invariants and privilege escalation)

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-16)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Pre-C4A audit preparation

## Decisions

- DELTA-L-01 (Low): DGNRS transfer-to-self token lock acknowledged as standard ERC20 behavior
- DELTA-I-01 (Info): stale poolBalances after burnRemainingPools not exploitable due to gameOver guard
- DELTA-I-02 (Info): stray ETH locked in DGNRS is harmless, no sweep function needed
- DELTA-I-03 (Info): previewBurn/burn ETH split discrepancy is by design
- DELTA-I-04 (Info): stale comment at DegenerusGameStorage.sol:1086 (says "reward pool", code uses Lootbox)
- 26 pre-existing test failures in affiliate/RNG/economic suites documented as out-of-scope
- Prior v1.0-v1.2 SOUND assessment still holds after sDGNRS/DGNRS split
- No Phase 19 findings warrant KNOWN-ISSUES.md modification (deferred to Phase 20)
- 20-01: Fixed 3 additional COINFLIP line references plan marked as correct (off-by-one in reference file)
- 20-02: sDGNRS section placed before DGNRS in function audits (underlying before wrapper); all 14 verdicts CORRECT per Phase 19 verification
- 20-03: BURNIE burn path documented as untestable without fixture modification; DGNRS self-transfer validates DELTA-L-01; depositSteth(0) confirmed as no-op
- 21-01: All 9 economic/amplifier attack vectors SAFE or OUT_OF_SCOPE; proportional burn-redeem formula is the fundamental defense
- 21-03: Backing solvency invariant uses Insufficient() revert as backstop -- worst case is reverted burn, never overpayment; game contract is trust anchor for privilege model
- [Phase 21]: 21-04: stETH rebase timing SAFE (<$2 extractable for 10% holder); all 5 game-over race conditions SAFE/INFORMATIONAL
- 21-02: claimWinnings stETH fallback path confirmed safe (game _payoutWithStethFallback deposits stETH to sDGNRS via depositSteth); stETH rounding revert at line 415 only for near-100% burns; forced ETH donation via selfdestruct is net loss for attacker
- [Phase 21]: Backing solvency invariant uses Insufficient() revert as backstop; game contract is trust anchor for privilege model

## Accumulated Context

- v1.0-v1.2 audit docs cover all subsystems pre-sDGNRS split
- sDGNRS/DGNRS split is the largest code delta since v1.1 audit
- All audit docs synced to new architecture in v1.3
- Contracts compile clean, 201 Hardhat tests pass, Foundry fuzz tests compile
- One pre-existing test failure in EconomicAdversarial (unrelated to split)
- 19-01: sDGNRS+DGNRS core audit PASS (DELTA-01, DELTA-02, DELTA-03). 1 Low + 3 Info findings. Focused tests 73/73 green.
- 19-02: Consumer callsites audit PASS (DELTA-04 through DELTA-08). 30/30 callsites verified. 1 Info finding.
- Phase 19 consolidated: SOUND. 0 Critical/High/Medium, 1 Low, 4 Informational. All 8 DELTA requirements PASS.
- Full test suite: 1065 passing, 26 pre-existing failures (affiliate/RNG/economic -- unrelated to scope). No regression.
- 20-01: DegenerusStonk.sol now has 16 @notice NatDoc tags (full coverage). Stale earlybird comment fixed. 10 parameter reference line numbers corrected. DELTA-L-01 in KNOWN-ISSUES. sDGNRS in external audit scope.
- 20-02: state-changing-function-audits.md now has complete sDGNRS section (14 entries). FINAL-FINDINGS-REPORT.md updated with v2.0 delta findings (1L+4I), DELTA-01-08 coverage matrix, sDGNRS in scope, 62 plans/68 requirements.
- 20-03: 7 new edge case tests added (self-transfer, zero-address, zero-amount, stETH burn). Focused tests: 80 passing. Full suite: 1074 passing, 24 pre-existing failures, 0 new regressions. Fuzz tests compile clean. CORR-03+CORR-04 satisfied. Phase 20 complete.
- 21-01: NOVEL-01 (5 economic vectors) + NOVEL-12 (4 amplifier scenarios) analyzed. Flash loan blocked by onlyGame. Selfdestruct ETH = donation. MEV sandwich on burns = order-independent. Flash loan DGNRS = self-defeating (burn destroys repayment). Accumulation = intended arbitrage. 479-line report with 60+ file:line citations.
- 21-02: NOVEL-02 (5 call chains) + NOVEL-03 (6 griefing vectors) + NOVEL-04 (15 edge cases) analyzed. All call chains SAFE with CEI. claimWinnings stETH fallback path discovered and verified. 2 griefing vectors BLOCKED, 3 NEGLIGIBLE, 1 KNOWN. stETH rounding revert only for near-100% burns. 474-line report.
- 21-03: NOVEL-05 (4 invariants) + NOVEL-09 (privilege escalation) analyzed. Supply conservation proven across 6 paths. Cross-contract supply invariant proven across 6 paths. Backing solvency proven with Insufficient() revert backstop. Pool balance consistency proven pre-gameOver. Complete privilege map: GAME, DGNRS, CREATOR, public. 4 escalation vectors (delegatecall, proxy, CREATE2, tx.origin) all NO ESCALATION. 602-line report.
- 21-04: NOVEL-10 (stETH rebasing) + NOVEL-11 (game-over races) analyzed. Rebase extractable value <$2/burn at 10% holder. previewBurn discrepancy = by design (DELTA-I-03). Branch flipping = composition not value. 4-state game-over machine documented. 5 race conditions analyzed: concurrent burns proven order-independent (algebraic proof). Pending RNG window = INFORMATIONAL. 539-line report.
