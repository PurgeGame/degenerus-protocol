---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 05
status: complete
requirements: [POOL-01, POOL-02, POOL-03, POOL-05]
files_modified:
  - contracts/StakedDegenerusStonk.sol
  - contracts/DegenerusVault.sol
committed: false
---

# 326-05 POOL — recoverable AfKing prepaid pools

## DegenerusVault.sol
- `IAfKingSubscribe` interface: added `function withdraw(uint256 amount) external;` + `function poolOf(address player) external view returns (uint256);` (verbatim to AfKing.sol:318/:503 — same param names + identical selectors; matches the file's existing `subscribe` decl style).
- New `function recoverAfKingPool() external` — **PERMISSIONLESS** (no `onlyVaultOwner`, no gameOver gate): `afKing.withdraw(afKing.poolOf(address(this)));`. AfKing.withdraw sends to the caller (this vault), so an external trigger can only force the vault to recover its OWN pool into its own `receive()` — no theft surface. Placed right after the open `receive()`.

## StakedDegenerusStonk.sol (apply-order: interface → receive → burnAtGameOver)
- `IAfKingSubscribe` interface: same verbatim `withdraw`/`poolOf` adds.
- `receive()`: relaxed from `onlyGame` to an inline GAME-or-AF_KING gate (`if (msg.sender != GAME && msg.sender != AF_KING) revert Unauthorized()`), so AfKing's withdraw send-back lands. **Accounting-safe (POOL-04):** no running-reserve counter SSTORE added — reserves are read live via `address(this).balance`, so an AF_KING credit is never mis-attributed.
- `burnAtGameOver()`: `afKing.withdraw(afKing.poolOf(address(this)));` folded in BEFORE the `if (bal == 0) return;` early-return, so a zero-pool-TOKEN sDGNRS still recovers its ETH pool. **withdraw(0) is a no-op** (`AfKing.withdraw` returns early on amount==0, `poolOf` never reverts), so the common empty-pool case cannot brick gameOver.

## Locked decisions honored
- `AfKing.sol` **byte-UNCHANGED** for item 4 (`git diff --quiet contracts/AfKing.sol` clean before KEEP touched it for the sweep→autoBuy rename in 326-06). POOL-05 verbatim.
- NO standalone sDGNRS `withdraw` (D-04). NO second sweep in `handleFinalSweep`.
- **POOL-06 documented known-minor (accept-as-minor, D-04):** a `depositFor(SDGNRS)` landing AFTER `burnAtGameOver` re-strands (sDGNRS has no later trigger by design) — adversarial/pointless self-donation harming only the donor; VAULT is unaffected (anytime `recoverAfKingPool()`). No protocol loss.

## Composition
`burnAtGameOver` pool-recover composes with the 326-04 RFALL `_payEth`/payout-asset selection (different region of the same function path — no conflict); the gameover-drain ordering is shared with BTOMB (326-02) but in a different contract.

## Verification
POOL (Waves 1-3) `forge build` = 0 errors. AfKing.sol byte-unchanged at POOL time. RFALL item-2 edits preserved.

## Not committed
Batched-diff discipline.
