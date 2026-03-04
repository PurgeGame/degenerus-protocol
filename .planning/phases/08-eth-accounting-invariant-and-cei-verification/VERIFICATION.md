---
phase: 08-eth-accounting-invariant-and-cei-verification
type: verification
completed: 2026-03-04
---

# Phase 08 Verification

## Phase Goal

> Confirm (or disprove) the ETH solvency invariant across all reachable game states. Audit every `_creditClaimable` call site, verify all BPS fee splits round correctly, formally trace `claimWinnings()` and stETH/LINK reentrancy paths, verify vault share rounding, BurnieCoin supply invariant, game-over zero-balance, admin stake guard, and `receive()` donation safety.
>
> Produce verdicts (PASS / finding with severity) for ACCT-01 through ACCT-10.

## Verdict: PHASE GOAL MET

All 10 ACCT requirements have verdicts. No CRITICAL or HIGH findings. One LOW finding (creditLinkReward missing implementation). Two INFO findings (LINK CEI deviation not exploitable; selfdestruct surplus is protocol benefit).

## Requirement Verdicts

| Req | Description | Plan | Verdict |
|-----|-------------|------|---------|
| ACCT-01 | ETH solvency invariant holds across all game states | 08-04 | PASS — 7/7 invariant checkpoints pass (EthInvariant.test.js) |
| ACCT-02 | All _creditClaimable call sites correctly paired with claimablePool updates | 08-01 | PASS — 11/11 sites classified CORRECT (Pattern A or B) |
| ACCT-03 | BPS fee splits round correctly; no silent ETH drop | 08-05 | PASS — all 4 sites use subtraction pattern; remainder explicit |
| ACCT-04 | claimWinnings() follows CEI; no reentrancy path | 08-02 | PASS — strict CEI: sentinel set before external call |
| ACCT-05 | LINK onTokenTransfer and stETH paths follow CEI | 08-02 | PASS+INFO+LOW — formal deviation not exploitable; creditLinkReward missing (LOW) |
| ACCT-06 | DegenerusVault share redemption rounds down (protocol-safe) | 08-03 | PASS — floor division confirmed; no partial-burn extraction |
| ACCT-07 | BurnieCoin supply invariant totalSupply + vaultAllowance == supplyIncUncirculated | 08-03 | PASS — packed struct + VAULT-routing maintains invariant by construction |
| ACCT-08 | Game-over terminal state holds solvency invariant | 08-04 | PASS — 912-day level-0 timeout triggers gameOver=true; invariant holds |
| ACCT-09 | adminStakeEthForStEth guard prevents staking below claimablePool | 08-05 | PASS — guard confirmed claimablePool-based; authorization correct |
| ACCT-10 | receive() donation safe; selfdestruct forced ETH assessed | 08-05 | PASS+INFO — futurePrizePool only; no transitions; selfdestruct surplus is protocol reserve |

## Findings Summary

| ID | Severity | Location | Description |
|----|----------|----------|-------------|
| ACCT-05-L1 | LOW | DegenerusAdmin.sol:636 / BurnieCoin.sol | `creditLinkReward` declared in IDegenerusCoinLinkReward interface but not implemented in BurnieCoin.sol. LINK still forwards to VRF subscription, but BURNIE bonus silently not credited. No ETH at risk. Broken incentive feature only. |
| ACCT-05-I1 | INFO | DegenerusAdmin.sol:613, 636 | Formal CEI deviation in onTokenTransfer: creditLinkReward (EFFECT) executes after transferAndCall (INTERACT). Not exploitable: mult computed before INTERACT; Chainlink VRF coordinator is trusted. |
| ACCT-10-I1 | INFO | DegenerusGame.sol:2856 | selfdestruct-forced ETH increases balance without updating futurePrizePool. Makes solvency invariant more satisfied. Surplus ETH distributed as yield surplus in future rounds. Not a vulnerability. |

## Evidence

- `test/unit/EthInvariant.test.js` — 7 passing (17s) — empirical ACCT-01 and ACCT-08 evidence
- `test/helpers/invariantUtils.js` — reusable assertSolvencyInvariant and assertClaimablePoolConsistency helpers
- 08-01-SUMMARY.md — 11-site _creditClaimable classification table
- 08-02-SUMMARY.md — CEI trace tables for claimWinnings and onTokenTransfer
- 08-03-SUMMARY.md — vault rounding algebraic proof; BurnieCoin mint path enumeration
- 08-05-SUMMARY.md — BPS site table; staking guard trace; receive() body confirmation

## Phase Completion Status

COMPLETE — All 10 ACCT requirements have verdicts. No blocking findings. Phase 13 (security report) can cite all verdicts from this phase.
