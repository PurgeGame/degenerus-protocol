# Known Issues — Degenerus Protocol

Findings from internal AI-assisted audit (7 phases, 4 adversarial sessions, Foundry invariant fuzzing).
Updated for current codebase state as of 2026-03-08.

## Open Findings

### H-01: Whale Bundle Available at Any Level (Spec/Code Mismatch)

**Severity:** High (specification conformance)
**Contract:** `DegenerusGameWhaleModule.sol` — `_purchaseWhaleBundle()`
**Status:** Open — awaiting design decision

NatSpec documents whale bundles as restricted to levels 0-3, x49/x99, or boon holders. No level guard exists in code. Any player can purchase at any level for 4 ETH. Economic impact is bounded (18 ETH face value for 4 ETH deposit). This is an intentional design simplification — the NatSpec needs updating to match code, or a level guard needs adding.

### M-02: Admin Key Loss + VRF Failure = 365-Day Wait

**Severity:** Medium (availability)
**Contract:** `DegenerusGame` / `DegenerusAdmin`
**Status:** Acknowledged — design limitation

If the admin key is lost AND Chainlink VRF fails simultaneously, the only recovery is the 365-day inactivity timeout. No fund-loss risk — winnings remain claimable throughout. Mitigation: admin key backup, multisig consideration.

### L-01: No Isolated VRF Callback Gas Regression Test

**Severity:** Low
**Contract:** `DegenerusGame` / `AdvanceModule`
**Status:** Open

No test explicitly measures `rawFulfillRandomWords` gas in isolation. Worst-case estimate is ~45,000 gas (85% headroom under 300,000 limit).

### L-03: Whale Bundle NatSpec States 50/50, Code Implements 30/70

**Severity:** Low (documentation)
**Contract:** `DegenerusGameWhaleModule`
**Status:** Open

NatSpec documents 50/50 nextPrizePool/futurePrizePool split. Code implements 30/70 (30% next, 70% future at level 0; 5/95 at level 1+). Code logic appears intentional.

### L-04: Lootbox Minimum Has No Upper Bound

**Severity:** Low
**Contract:** `DegenerusAdmin`
**Status:** Open

`setLootBoxMinimum()` has no upper bound. Admin could theoretically prevent all lootbox opens. Mitigated by admin trust model.

### L-06: `_threeDayRngGap` Duplicated in Two Contracts

**Severity:** Low (maintenance)
**Contract:** `DegenerusGame` + `AdvanceModule`
**Status:** Open

Identical logic in both contracts. Maintenance risk if one is updated without the other.

## Fixed Findings

### FX-01: Deity Affiliate Bonus Calculation Error (was High)

Fixed in commit `e2bbf50`. Deity pass affiliate bonus divided by 1e18 before applying BPS, zeroing the bonus.

### FX-02: Deity Pass Double Refund (was Medium)

Fixed. All three tracking variables now zeroed before payout, closing the double-refund path.

### FX-03: Day-Index Function Mismatch in Boon Checks (was Medium)

Fixed. Both whale and lazy pass boon validity now use `_simulatedDayIndex()`.

### FX-04: deityBoonSlots() staticcall Issue (was Medium)

No longer applicable — function implementation changed; no staticcall in current code.

### FX-05: Stale dailyIdx in handleGameOverDrain (was Low)

Fixed in commits `ca87702` and `5c9ca21`. Current `day` parameter now passed correctly.

### FX-06: Nudges Accepted During VRF Fallback Wait (was Low)

Fixed. `reverseFlip()` properly checks `rngLockedFlag` and reverts.

### FX-07: Reentrancy in DGNRS/Vault Burn (was Medium)

Fixed in commit `ca87702`. CEI pattern corrected.

### FX-08: Final Sweep Did Not Forfeit Unclaimed Winnings (was Medium)

Fixed in commit `737b18c`. Sweep now forfeits unclaimed winnings and sweeps all funds.

### FX-09: GameOver RNG Gate for Level >= 1 Inactivity (was Medium)

Fixed in commit `5c9ca21`. RNG gate now correctly blocks game-over finalization until VRF fulfills.

## Adversarial Session Results (All Clean)

| Session | Attack Vector | Result |
|---------|--------------|--------|
| ADVR-01 | ETH Extraction | No Medium+ findings |
| ADVR-02 | Brick advanceGame | No Medium+ findings |
| ADVR-03 | claimWinnings Overflow | No Medium+ findings |
| ADVR-04 | Delegatecall Reentrancy | No Medium+ findings |

## Invariant Fuzzing

Foundry invariant harnesses in `test/fuzz/` cover:
- ETH solvency (balance + steth >= claimablePool)
- BurnieCoin supply invariants
- VRF lifecycle state machine
- Vault share math precision
- Ticket queue ordering
- Whale/Sybil attack resistance
- Degenerette bet resolution
- Multi-level price escalation
- Game FSM transitions
- Cross-contract composition

All invariants hold under extended fuzzing campaigns.
