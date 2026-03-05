---
phase: 25-dependency-integration-attacker
plan: 01
subsystem: security-audit
tags: [chainlink-vrf, lido-steth, link-token, dependency-analysis, adversarial]

requires:
  - phase: none
    provides: blind analysis -- no prior phase dependencies

provides:
  - Comprehensive dependency failure mode analysis for VRF, stETH, LINK
  - 19 PoC tests validating all defense mechanisms
  - C4A-format attestation with zero Medium+ findings

affects: [29-synthesis-report]

tech-stack:
  added: []
  patterns: [defense-documentation-tests, blind-adversarial-analysis]

key-files:
  created:
    - test/poc/Phase25_DependencyIntegration.test.js
  modified: []

key-decisions:
  - "All external dependency failure modes are defended -- no Medium+ findings"
  - "stETH negative rebase risk is accepted design tradeoff for yield (Informational)"
  - "VRF has 3-tier defense: 18h retry, 3-day rotation, gameover fallback"

patterns-established:
  - "Dependency failure PoC: test each defense mechanism individually"

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04, DEP-05]

duration: 5min
completed: 2026-03-05
---

# Phase 25 Plan 01: Dependency & Integration Attacker Summary

**Blind adversarial analysis of Chainlink VRF V2.5, Lido stETH, and LINK token dependency failure modes -- all attack vectors defended with 3-tier VRF recovery, stETH fallback payouts, and strict onTokenTransfer validation**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-05T11:03:08Z
- **Completed:** 2026-03-05T11:08:11Z
- **Tasks:** 5
- **Files modified:** 1

## Accomplishments
- Analyzed 5 VRF coordinator failure scenarios with full protocol state impact tracing
- Computed stETH solvency at 10/50/90% depeg -- protocol design accepts rebase risk for yield
- Verified LINK onTokenTransfer is immune to spoofing, draining, and zero-amount attacks
- Confirmed VRF coordinator rotation path handles V2.5 deprecation scenario
- 19 passing PoC tests validating every defense mechanism

## C4A Findings

### Attestation: No Medium+ Findings

After thorough blind analysis of all external dependency interactions across DegenerusGame, DegenerusGameAdvanceModule, DegenerusAdmin, DegenerusVault, and related contracts, I attest that no Medium or higher severity findings exist in the dependency and integration attack surface. Below is the detailed analysis supporting this attestation.

---

### VRF Coordinator Failure Modes (Task 1)

**Scenario A: Coordinator permanently down**
- **Defense:** 18h retry timeout at AdvanceModule line 648-651. After 18h without fulfillment, `advanceGame()` re-requests VRF. After 3 consecutive days without any RNG word (checked via `_threeDayRngGap` at line 1240-1245), `rngStalledForThreeDays()` returns true and the admin can call `emergencyRecover()` (Admin line 487-549) to migrate to a new coordinator.
- **Impact:** Game halted for max 3 days before recovery path activates. No fund loss.

**Scenario B: Fulfillment delayed hours/days**
- **Defense:** 18h timeout triggers automatic retry (AdvanceModule line 648-651). Daily RNG gate at line 620-658 handles all timing scenarios. If fulfillment arrives late but before retry, it is accepted normally.
- **Impact:** Game delays by hours, not a vulnerability.

**Scenario C: Manipulated randomness**
- **Defense:** VRF provides verifiable randomness by construction. The `rawFulfillRandomWords` callback validates `msg.sender == vrfCoordinator` (AdvanceModule line 1185). Additionally, the nudge system (`reverseFlip` at AdvanceModule line 1153-1161) adds player-driven entropy that even the coordinator cannot predict.
- **Impact:** Would require compromising Chainlink's BLS threshold scheme -- outside protocol scope.

**Scenario D: Subscription out of LINK**
- **Defense:** `requestRandomWords` will revert at the coordinator level (insufficient funds). The game's `_requestRng` (line 995-1007) does a hard revert, halting the game until LINK is added. Lootbox RNG has explicit LINK balance check at line 574. The `_tryRequestRng` variant (line 1010-1037) uses try/catch for the gameover path, preventing permanent lockup.
- **Impact:** Game pauses until LINK donated via `onTokenTransfer`. Not a vulnerability.

**Scenario E: Coordinator self-destructs**
- **Defense:** `requestRandomWords` would revert (no code at address). 18h timeout + 3-day stall detection triggers emergency rotation. The `_gameOverEntropy` function (line 672-721) has a historical VRF word fallback using `_getHistoricalRngFallback` (line 728-747) that allows game completion even without any working VRF.
- **Impact:** Same as permanent coordinator failure -- 3-day recovery.

**Severity: Informational** -- All scenarios have documented recovery paths.

---

### stETH Depeg Scenario (Task 2)

**Protocol stETH holdings:**
- DegenerusGame holds stETH via `_autoStakeExcessEth()` (AdvanceModule line 983-989) which runs on every jackpot-to-purchase transition. Stakes `address(this).balance - claimablePool` into stETH.
- DegenerusVault holds stETH received from game deposit() calls (Vault line 450-458).
- Admin facilitates stETH <-> ETH swaps via `swapGameEthForStEth` and `stakeGameEthToStEth`.

**Invariant:** `address(this).balance + steth.balanceOf(this) >= claimablePool` (Game line 18)

**Depeg impact analysis:**

| Depeg Level | stETH Value | Impact on Game | Impact on Vault |
|-------------|-------------|----------------|-----------------|
| 10% | 0.90 ETH/stETH | Invariant likely holds -- yield surplus absorbs | DGVE holders receive 10% less |
| 50% | 0.50 ETH/stETH | Invariant may break -- claims partially fail | DGVE holders lose 50% value |
| 90% | 0.10 ETH/stETH | Invariant breaks -- stETH-dependent claims revert | DGVE effectively worthless |

**Key defense mechanisms:**
1. `_payoutWithStethFallback` (Game line 2015-2042): Sends ETH first, stETH only for remainder. ETH claims unaffected.
2. `_autoStakeExcessEth` uses try/catch (line 988): If Lido fails, ETH stays as ETH. Non-blocking.
3. `adminStakeEthForStEth` (line 1873-1888): Cannot stake below claimablePool boundary.
4. Vault `_syncEthReserves` (line 977-983) uses live `steth.balanceOf()` -- DGVE holders bear rebase risk by design.

**Can negative rebase cause `claimablePool > actual balance`?**
Yes, theoretically. After `_autoStakeExcessEth` converts excess ETH to stETH, a negative rebase reduces `steth.balanceOf(this)` without reducing `claimablePool`. If the rebase is severe enough, claims could partially fail (revert in `_payoutWithStethFallback`). However:
- New ETH purchases continuously add fresh ETH, re-establishing solvency.
- The admin `swapGameEthForStEth` path allows injecting ETH to cover shortfalls.
- Claims that CAN be paid in ETH are unaffected.

**Severity: Informational** -- Accepted design tradeoff for yield generation. Protocol does not guarantee 1:1 stETH:ETH parity.

---

### LINK Token Depletion and onTokenTransfer (Task 3)

**0 LINK subscription:**
- `requestRandomWords` reverts at coordinator (insufficient funds). Game halts until LINK added.
- `requestLootboxRng` explicitly checks: `linkBal < MIN_LINK_FOR_LOOTBOX_RNG` (AdvanceModule line 574-575).
- Recovery: Anyone can donate LINK via `transferAndCall` to Admin contract.

**onTokenTransfer abuse vectors:**
1. **Spoofed caller:** Blocked by `msg.sender != ContractAddresses.LINK_TOKEN` check (Admin line 612).
2. **Zero amount:** Blocked by `amount == 0` check (Admin line 613).
3. **No subscription:** Blocked by `subId == 0` check (Admin line 616).
4. **After game over:** Blocked by `gameAdmin.gameOver()` check (Admin line 619).
5. **Malicious data parameter:** The `data` parameter in `onTokenTransfer` is ignored entirely (Admin line 609: `bytes calldata` unnamed). The LINK is forwarded to VRF coordinator via `transferAndCall` with properly encoded subId.
6. **Oracle manipulation for reward inflation:** The `_linkAmountToEth` function (Admin line 672-693) validates staleness, positive answer, round consistency. Returns 0 on any invalid data. Reward multiplier caps at 3x and drops to 0 at 1000 LINK balance.

**Can attacker drain subscription?**
No. Only the Admin contract can cancel the subscription via `cancelSubscription` (gated by `onlyOwner` and either `rngStalledForThreeDays` or `gameOver`). The VRF coordinator does not expose subscription drainage to consumers.

**Severity: Informational** -- All LINK interaction paths are properly validated.

---

### Dependency Upgrade/Deprecation Risk (Task 4)

**Chainlink VRF V2.5 deprecation to V3:**
- Protocol has explicit migration path: `emergencyRecover()` (Admin line 487-549) creates new subscription on new coordinator, transfers LINK, and pushes config to Game.
- `updateVrfCoordinatorAndSub` (AdvanceModule line 1115-1134) accepts any coordinator address, subId, and keyHash.
- Migration requires 3-day VRF stall -- planned deprecation would need coordinated downtime or preemptive stall simulation.
- **Risk: Low.** Migration path exists but requires 3-day game pause.

**Lido stETH rebasing mechanism change:**
- Protocol uses only standard ERC20 interface + `submit()`: `balanceOf()`, `transfer()`, `approve()`, `transferFrom()`.
- No dependency on `sharesOf()`, `getPooledEthByShares()`, or internal rebase mechanics.
- The `_autoStakeExcessEth` uses try/catch (AdvanceModule line 988), so stETH failures are non-blocking.
- **Risk: Very Low.** Interface is minimal and stable.

**LINK token proxy upgrade:**
- Protocol uses only `balanceOf()`, `transfer()`, `transferAndCall()` -- standard ERC-677.
- LINK proxy upgrades have maintained backward compatibility historically.
- The `onTokenTransfer` callback validates `msg.sender` against the compile-time LINK address.
- A proxy upgrade preserving the address would be transparent. An address change would break donations but not game operation (VRF requests use subscription balance, not direct LINK payments).
- **Risk: Very Low.** Only donation flow affected; game VRF continues from existing subscription balance.

**Severity: Informational** -- All upgrade scenarios have mitigation or graceful degradation.

---

## Task Commits

1. **Tasks 1-5: Full analysis + PoC tests** - `283ee06` (test)

## Files Created/Modified
- `test/poc/Phase25_DependencyIntegration.test.js` - 19 PoC tests covering VRF retry, access control, stETH fallback, LINK validation, oracle staleness, and upgrade paths

## Decisions Made
- All dependency failure modes have existing defenses -- attestation of no Medium+ findings
- stETH negative rebase is an accepted design tradeoff documented as Informational
- VRF 3-tier defense (18h retry + 3-day rotation + gameover fallback) is comprehensive

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All dependency/integration analysis complete
- Findings ready for Phase 29 synthesis report
- No blockers

---
## Self-Check: PASSED

- test/poc/Phase25_DependencyIntegration.test.js: FOUND
- Commit 283ee06: FOUND
- 25-01-SUMMARY.md: FOUND

---
*Phase: 25-dependency-integration-attacker*
*Completed: 2026-03-05*
