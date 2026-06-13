# Round 7 packet — DegenerusJackpots.sol

Source verified 2026-06-12 at round-6 HEAD 307d5312.

## JACKPOTS-06 + RT-CLAIMS-13 (APPROVED ×2, ONE edit) — dedupe slices D/D2
- Sites: runBafJackpot slice D (L313-352) and slice D2 (L353-392) — textually identical
  blocks (++salt → hash2 rehash → sampleFarFutureTickets → top-2 by _bafScore →
  3%/2% credit-or-refund) differing only in comments.
- Edit: wrap ONE block in `for (uint256 pass; pass < 2; )` with `unchecked { ++salt; }`
  as the FIRST statement of the body. Salt sequence provably unchanged: slice B leaves
  salt=1; loop produces 2 then 3 — same preimages, same hash2 digests, same winner
  selection and n/toReturn accumulation order. ENTROPY-ORDER-PRESERVING by construction.
- RT-CLAIMS-13 (helper-extraction form of the same dedup) is subsumed by the loop form
  (smaller diff, same effect).

## JACKPOTS-09 (APPROVED) — _updateBafTop Case 1 shift-then-place
- Site: Case 1 (existing player improves), L626-640: pre-write of board[existing].score
  (packed-slot RMW) + full memory-tmp SWAP per bubble step.
- Edit (mirrors Cases 2/3):
  delete the pre-write; `uint8 idx = existing; while (idx > 0 && score >
  board[idx - 1].score) { board[idx] = board[idx - 1]; unchecked { --idx; } }
  board[idx] = PlayerScore({player: player, score: score});`
- Truth-table verified by the skeptic: current swap-loop condition reduces to
  `score > board[idx-1].score` throughout (board[idx] holds the mover after the
  pre-write), strict > so equal scores never reorder — identical end state on no-move,
  mid-board climb, and tie-stop. Player appears at most once (Cases 2/3 only when
  not found). Leaderboard feeds slices A/B — ordering provably unchanged.

## JACKPOTS-11 (APPROVED, ⚠ USER-INTENT FLAG) — tighten onlyCoin to COINFLIP-only
- Site: onlyCoin modifier (L162-165) admits COIN and COINFLIP; sole user recordBafFlip;
  the only production caller is BurnieCoinflip.sol:571. BurnieCoin contains zero
  references to JACKPOTS/recordBafFlip (skeptic grep-verified — cannot even target the
  contract). Strictly NARROWS access control.
- Edit: `if (msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();` + fix the
  stale natspec (modifier doc + recordBafFlip @custom:access + the header line naming
  BurnieCoin as the forwarder).
- ⚠ SURFACED FOR EXPLICIT USER CONFIRMATION AT DIFF REVIEW (skeptic instruction): tests
  encode COIN-as-valid-caller as spec (DegenerusJackpots.test.js coin-caller acceptance;
  BafRebuyReconciliation.t.sol vm.prank(coin)) — those recalibrate to COINFLIP if the
  user confirms the dead allowance was not intentional.
- Test recalibrations: test/unit/DegenerusJackpots.test.js (recordBafFlip-as-coin
  helper/tests) + test/fuzz/BafRebuyReconciliation.t.sol (vm.prank(coin) sites) → COINFLIP.

## Test impact
- JACKPOTS-06/09: none — seed-pinned full-slate jackpot tests + leaderboard ordering
  tests are the regression net and must stay green unchanged.
- JACKPOTS-11: the two caller-impersonation recalibrations above.
