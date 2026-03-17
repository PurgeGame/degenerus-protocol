# Known Issues and Design Notes

Pre-disclosure for C4A wardens. If you find something listed here, it's already known.

---

## Known Finding

### M-02: Admin + VRF Failure (Medium, Acknowledged)

**Contract:** `DegenerusGame` / `DegenerusAdmin`

If Chainlink VRF stalls for 3+ consecutive days, the admin (>50.1% DGVE holder) can call `emergencyRecover` to set a new VRF coordinator. A hostile admin could point this at an attacker-controlled coordinator that returns chosen random words — controlling jackpots, lootboxes, and all RNG-dependent outcomes.

**Preconditions (both required):**
1. Chainlink VRF genuinely down for 3+ consecutive days (no precedent on mainnet)
2. Admin key compromised OR admin absent (365-day timeout is the only recovery)

**Why it's accepted:**
- Admin is neutered during normal VRF operation — zero influence on outcomes
- `EmergencyRecovered` events make coordinator swaps publicly detectable
- The alternative (no recovery path) means the game dies permanently if Chainlink goes down
- LINK subscription top-up is permissionless — subscription exhaustion is not a contributing factor

**GAMEOVER fallback (dead VRF, no admin):** `_getHistoricalRngFallback` uses early VRF words + `block.prevrandao`. 1-bit validator influence in a disaster-recovery-only context.

---

## Intentional Design (Not Bugs)

**BURNIE has multiple mint pathways.** `mintForCoinflip()`, `mintForGame()`, and the vault's 2M virtual reserve. All authorized via `onlyTrustedContracts`. No free-mint path.

**Degenerette is +EV at high activity.** 305% activity score yields ~99.9% ROI. Intentional — bounded by bet limits, 10% pool cap on ETH payouts, and lootbox delivery (future tickets, not liquid value).

**Activity score gap compounds.** 80% lootbox EV (minimum) to 135% (maximum). Intentional incentive for consistent participation.

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Deity pass pricing favors early buyers.** Cost is `24 + T(n)` ETH where `T(n) = n(n+1)/2`. GAMEOVER refund (20 ETH/pass, levels 0-9 only, FIFO) partially mitigates but doesn't eliminate early-mover advantage.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

**`previewBurn` and `burn` may differ slightly.** When `claimableEth > 0`, the ETH/stETH split can shift between preview and execution. By design — claimable ETH remains as reserves for future burners.

---

## External Dependencies

**Chainlink VRF V2.5** — sole randomness source. Soft dependency: game stalls but no funds lost if VRF goes down. 3-day emergency fallback (M-02) and 365-day inactivity timeout provide independent recovery paths.

**Lido stETH** — prize pool growth depends on ~2.5% APR yield. If yield goes to zero, positive-sum margin disappears.
