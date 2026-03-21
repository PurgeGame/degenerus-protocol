# Known Issues

Pre-disclosure for audit wardens. If you find something listed here, it's already known.

---

## Intentional Design (Not Bugs)

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

---

## Design Mechanics

These are architectural decisions, not vulnerabilities.

**VRF swap governance.** Emergency VRF coordinator rotation requires a 20h+ stall and sDGNRS community approval with time-decaying threshold. Execution requires approve weight > reject weight and meeting the threshold -- reject voters holding more sDGNRS than approvers block the proposal. This is the intended trust model.

**Chainlink VRF V2.5 dependency.** Sole randomness source. Game stalls but no funds are lost if VRF goes down. Governance-based coordinator rotation and 120-day inactivity timeout provide independent recovery paths.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent — the solvency invariant does not depend on yield.

**_sendToVault uses hard reverts (GO-05-F01).** `_sendToVault` reverts on any ETH or stETH transfer failure. Vault and sDGNRS are immutable protocol-owned contracts with unconditional `receive()` functions. Lido stETH has never paused transfers. Recipients can't reject funds.

**Gambling burn mechanism.** During active game, sDGNRS/DGNRS burns enter a gambling path instead of deterministic redemption. The burn amount is submitted to a pending redemption queue. When the next advanceGame resolves via VRF, a roll (25-175%) is applied to determine the ETH payout multiplier. BURNIE payout is conditional on a separate coinflip result. This is intentional -- it creates an RNG-gated burn with variable outcomes. Post-gameOver, burns revert to deterministic proportional payouts.

**Split-claim design (CP-07 fix).** `claimRedemption()` pays ETH immediately once the period is resolved, regardless of coinflip state. BURNIE is paid only if the coinflip resolved and won. If the coinflip hasn't resolved yet, ETH is paid and the claim remains open for BURNIE. This prevents ETH from being stuck due to unresolved coinflips.

**50% supply cap per period.** Each gambling burn period is capped at 50% of current totalSupply. This prevents bank-run scenarios and ensures the RNG roll applies to at most half the supply in any period.

**RNG-locked burn rejection.** Burns revert with `BurnsBlockedDuringRng` during VRF resolution lock to prevent front-running the RNG outcome.
