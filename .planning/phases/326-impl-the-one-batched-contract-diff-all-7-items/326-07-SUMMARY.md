---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 07
status: complete
requirements: [SWAP-01, SWAP-02, SWAP-03, SWAP-04, SWAP-05, SWAP-06, SWAP-07]
files_modified:
  - contracts/modules/DegenerusGameMintModule.sol         # executing entrypoint + _removeFarFutureTickets + event
  - contracts/modules/DegenerusGameMintStreakUtils.sol    # shared _quoteFarFutureSwap + _farFutureFractionBps (+ PriceLookupLib import)
  - contracts/DegenerusGame.sol                           # thin wrapper + previewSellFarFutureTickets view
  - contracts/interfaces/IDegenerusGameModules.sol        # IDegenerusGameMintModule.sellFarFutureTickets selector
  - contracts/DegenerusVault.sol                          # gameSellFarFutureTickets onlyVaultOwner wrapper + interface entry
committed: false
---

# 326-07 SWAP — sDGNRS far-future salvage swap (sellFarFutureTickets)

## Behavior (per SPEC R3 + design doc, with the two USER steers below)
`sellFarFutureTickets(player, levels, quantities, queueIndices)`: resolves the seller via
`_resolvePlayer` (operator-honor), `rngLocked`/`gameOver`/liveness gated. Mass-sells WHOLE far
tickets (6 ≤ d = L − currentLevel ≤ 100) → ONE aggregated current-level mint + cash residual.
- **Valuation:** per line `faceWei = priceForLevel(L) * n` (1 whole ticket = priceForLevel(L), units
  per attestation #2: `owed` is entries, 4/ticket, so the debit/credit use `n*4`). Two-line
  `fractionBps(d)` 15%@d6→10%@d20→5%@d100 + daily per-player jitter from `rngWordByDay[currentDay-1]`
  (SETTLED prior-day word, freeze-safe). Jitter bands: fraction ×∈[70%,110%], ticket share ∈[40%,80%]
  (cash ∈[20%,60%]).
- **Ticket floor:** `oneTicketWei = priceForLevel(currentLevel)` (NOT /4); revert if `totalBudget < oneTicketWei`.
- **Funding:** fail-closed inline `claimableWinnings[SDGNRS] >= totalBudget + 1 ether` (≥1 ETH floor); NO `pendingRedemptionEthValue` term; NO daily cap.
- **Swap-pop:** `_removeFarFutureTickets` O(1) caller-verified (`q[idx]==player`) ONLY on full sell-out (packed==0); maintains `membership ⟺ packed != 0`; samplers + JackpotModule byte-unchanged.
- **No-arb (SWAP-08 noted, not re-proven):** ceiling = 110% × 15% = **16.5% of face @ d6** < ~21% cheapest acquisition → margin ~4.5pp holds. No band widened → no STOP.

## ⚠ TWO USER STEERS during execution (flag for hand-review)
1. **Ticket leg = NORMAL recycled mint** (USER: "it's fine if its easier to just make it a normal mint").
   The design §8 side-effect suppression (no FLIP/streak/boons/rebuy/mint-count) is RELAXED — the leg
   calls the MintModule's internal `_purchaseFor(player, qty, 0, bytes32(0), Claimable)`. Plumbing:
   move `totalBudget` SDGNRS→player claimable (relabel, claimablePool unchanged), normal-mint `ticketWei`
   worth, leftover (~cashWei) is the player's withdrawable residual. `qty = ticketWei*4*TICKET_SCALE/oneTicketWei`.
   Acceptable because the swap is -EV (not farmable). Recorded in [[v48-swap-ticket-leg-normal-mint]].
2. **Moved to a module for EIP-170 headroom** (USER: "Move SWAP logic into a module"). The game contract
   was at 23,535 B (1,041 B margin) with SWAP inline. Refactor: heavy mutating logic + `_removeFarFutureTickets`
   + the `FarFutureSwap` event → `DegenerusGameMintModule` (7.4 KB headroom; reuses internal `_purchaseFor`
   directly). DegenerusGame keeps only a thin `sellFarFutureTickets` wrapper (resolve + delegatecall MINT_MODULE).

## NEW quote view (USER-requested: "do we have a view for what a bundle would sell for?")
`previewSellFarFutureTickets(player, levels, quantities) view → (totalFaceWei, totalBudget, ticketWei, cashWei)`
on the game contract (a `view` can't delegatecall, so it must run in the game's storage context). Shares
the EXACT valuation with the executing path via `_quoteFarFutureSwap` in MintStreakUtils (both game + MintModule
inherit it) → the displayed offer can never drift from the paid offer. Net-new surface beyond the plan/SPEC.

## VAULT (R5 item-7)
`IDegenerusGamePlayerActions.sellFarFutureTickets(address,uint32[],uint256[],uint256[])` interface entry +
`gameSellFarFutureTickets(uint32[],uint256[],uint256[]) onlyVaultOwner` wrapper → `gamePlayer.sellFarFutureTickets(address(this), ...)`.
**R6 flags (out-of-diff):** DroneManager (degenerus-utilities) needs a +1 `onlyChainOwner sellFarFutureTickets`
pass-through in its pending v47 re-sync. OPEN-E operator-trust disposition CONFIRMED to cover this first
value-destructive operator action.

## Not committed
Batched-diff discipline. Build/size confirmation in 326-08.
