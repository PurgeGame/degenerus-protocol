---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 04
status: complete
requirements: [RFALL-01, RFALL-02, RFALL-03]
files_modified:
  - contracts/DegenerusGame.sol
  - contracts/StakedDegenerusStonk.sol
committed: false
---

# 326-04 RFALL — mid-game ETH-depletion + stETH-donation redemption brick (F-47-02)

## DegenerusGame.pullRedemptionReserve (R1) — the substantive fix
Selector / SDGNRS-gate / `amount == 0` early-return KEPT. Added the pure-ETH-OR-pure-stETH
coverage branch (fail-closed, donation-robust):
- **ETH leg (as today):** `if (claimableWinnings[SDGNRS] >= amount && address(this).balance >= amount)` →
  CHECKED debit `claimableWinnings[SDGNRS] -= amount; claimablePool -= uint128(amount);` + CEI ETH `call` → return.
- **stETH leg (NEW):** else `if (steth.balanceOf(SDGNRS) >= amount) return;` — NO game-side move and NO ledger debit.
- **Neither → `revert E()`** (fail-closed).

## ⚠ ACCOUNTING INTERPRETATION (for hand-review scrutiny)
The SPEC R1 step 2 ("sDGNRS already holds stETH; the claim pays stETH; coverage checked against the
stETH basis; no new external-call selector") is implemented as: **the stETH leg is a no-op on the game**
— it neither moves stETH nor debits `claimableWinnings[SDGNRS]`/`claimablePool`. Rationale (forced by the
canonical donation case): a stETH donation inflates the submit base beyond `claimableWinnings[SDGNRS]`,
so a ledger debit would underflow; the inflation is backed by sDGNRS's OWN stETH already in safe custody,
so nothing needs moving. The reservation is recorded solely by the caller's `pendingRedemptionEthValue += maxIncrement`
(D-06 single tracker), and the claim pays from sDGNRS's balance via the existing `_payEth`/`burnAtGameOver`
stETH sites. Solvency stays at the pool level (REDEEM-08 `balance+stETH >= pending`), re-proven at TST (RFALL-05).
The ETH leg only moves the *at-risk* claim-on-game ETH (drainable by a concurrent claimable drain) into
sDGNRS's custody; the stETH leg's backing is already safe, hence no move. **Alternative interpretation
considered + rejected:** "game transfers stETH + debits ledger" — would NOT fix the donation case (ledger
underflows). Donation-robustness check is against `steth.balanceOf(SDGNRS)` — the same basis a donation inflates.

## StakedDegenerusStonk (R4 item-2) — comment-only (logic flows from the updated pullRedemptionReserve)
The coverage branch lives in `pullRedemptionReserve`; the sStonk call site
(`game.pullRedemptionReserve(maxIncrement)`) and `pendingRedemptionEthValue += maxIncrement` are UNCHANGED.
Edits: updated the stale `:870-873` comment (it claimed "reverts if the MAX cannot segregate" → now describes
the ETH-or-stETH fallback) and the `_payEth` NatSpec (the backing may now be sDGNRS's own stETH). The 4-term
submit base (:847) and the single `pendingRedemptionEthValue` (:263) are byte-unchanged (D-06). Claim-asset
match is satisfied at the pool level by the existing `_payEth` (ETH-first, stETH-fallback).

## Untouched (verified)
sStonk `receive()` / `burnAtGameOver` / `IAfKingSubscribe` interface NOT touched by this plan (those are 326-05) —
`git diff` hunks confined to the two comment regions. RFALL build = 0 errors.

## Not committed
Batched-diff discipline.
