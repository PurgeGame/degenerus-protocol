# Round 7 packet — DegenerusStonk.sol + StakedDegenerusStonk.sol

Source verified 2026-06-12 at round-6 HEAD 307d5312.

## STONK-02 (APPROVED) — yearSweep: drop the dominated gameOver() staticcall
- Site: `if (!game.gameOver()) revert SweepNotReady();` (L304). The sole gameOver latch
  (GameOverModule:138) writes GO_TIME atomically on the next line; GO_TIME has no other
  writer and _goWrite is a masked field write — so gameOverTimestamp() != 0 <=> gameOver.
  The L305-306 `goTime == 0` check dominates with the IDENTICAL SweepNotReady selector.
- Edit: delete L304 only.

## STONK-03 (APPROVED) — burn(): remove the unreachable BURNIE forward leg
- Site: `if (burnieOut != 0) { if (!burnie.transfer(...)) revert TransferFailed(); }`
  (L233-235). burn() reverts GameNotOver unless gameOver (L229, monotonic latch, no
  intervening call); StakedDegenerusStonk.burn's gameOver path returns (eth, steth, 0)
  unconditionally — burnieOut is structurally zero on the only reachable path.
- Edit: delete the branch + the `burnie` constant (L104) + the IERC20Minimal interface
  (L20-23; sole use — steth is typed IStETH from a separate import, verified). Return
  signature + BurnThrough event shape unchanged (burnieOut stays 0, ABI untouched).

## STONK-04 (APPROVED) — burnForSdgnrs delegates to _burn
- Site: burnForSdgnrs (L349-358) re-implements private _burn (L278-286) byte-for-byte
  (verified identical: bal read, `amount == 0 || amount > bal` Insufficient, unchecked
  decrements, Transfer emit). Only the auth check differs.
- Edit: body → `if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();
  _burn(player, amount);`

## STONK-01 (APPROVED) — burnWrapped: cache gameOver()
- Site: StakedDegenerusStonk.burnWrapped (L588-598): gameOver() read in the L589
  short-circuit and again at L591; the intervening burnForSdgnrs makes zero external
  calls (verified above) so the value cannot change.
- Edit: `bool isOver = game.gameOver();` hoisted to the top;
  L589 → `if (!isOver && game.livenessTriggered()) revert BurnsBlockedDuringLiveness();`;
  L591 → `if (isOver)`. Gate boolean identical; live path 2 staticcalls before/after,
  post-gameOver path drops to 1. View-call order swap is externally unobservable.

## STONK-08 (APPROVED) — single pendingRedemptions load per claim
- Sites: claimRedemption (L713-723), claimRedemptionMany (L731-742),
  _claimRedemptionFor (L747+). The (player,day) slot is read in the entry points
  (`.ethValueOwed == 0` guard) and re-derived + re-read inside the helper.
- Edit: helper loads `PendingRedemption memory claim = pendingRedemptions[player][day];`
  once at top, `if (claim.ethValueOwed == 0) return false;`, returns bool;
  claimRedemption → `if (!_claimRedemptionFor(...)) revert NoClaim();`;
  claimRedemptionMany drops its pre-check (skip-on-false == current skip semantics).
  CEI untouched (delete still precedes the external calls); pendingRedemptionEthValue
  lines unedited.
- Accepted deltas (all-revert overlaps only, on-chain harmless):
  (no-claim AND unresolved day) NoClaim → NotResolved;
  (no-claim AND post-gameOver third-party) NoClaim → Unauthorized.
  Verify test pins in test/fuzz/RedemptionEdgeCases.t.sol +
  test/repro/V62RedemptionReentrancy.t.sol don't construct the overlaps; repin if so.
- Bonus: the bool return makes the helper's silent-no-op path (spurious
  RedemptionClaimed on a zero claim — unreachable today) structurally impossible.

## Test impact
- STONK-08 overlap pins (check the two files above); otherwise none expected.
