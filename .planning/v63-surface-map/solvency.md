# v63 Surface Map — Dimension: Solvency Spine (claimablePool / ETH & stETH accounting)

BASELINE `77580320` → SUBJECT `a8b702a7`. READ-ONLY change-surface map. Leads below are for a later
adversarial sweep — NOT confirmed findings.

## Master invariant (restated from source)

`DegenerusGame` (header comment, line 18-19) and storage (DegenerusGameStorage.sol:357-366):

> `address(this).balance + steth.balanceOf(this) >= claimablePool`
> `claimablePool == Σ (claimable + afking halves of balancesPacked[*])`

Both the per-player claimable winnings AND the prepaid afking funding ride inside the single
`claimablePool` uint128 reserve (no separate aggregate). Every mutation of a player's packed
balance pairs an equal `claimablePool` move at the call site. The prize pools
(current/next/future), `yieldAccumulator`, and the pending freeze-window pools are SEPARATE
obligations layered on top in the yield-surplus view, not inside claimablePool.

`StakedDegenerusStonk` runs its OWN solvency identity for sDGNRS backing: backing per token =
`(ETH bal + stETH bal + claimableWinnings[SDGNRS] − pendingRedemptionEthValue) / totalSupply`.
`pendingRedemptionEthValue` is the physically-segregated reserve for unresolved/unclaimed
gambling-burn redemptions, excluded from regular-burn backing so it is never double-spent.

## Change inventory (every credit/debit touch this dimension)

### A. DegenerusGamePayoutUtils.sol (2 incidental rewrites, accounting-identical)
- **A1 `_creditBoxProceeds` (line 21):** `(boxEth * 20)/100` → `boxEth / 5`. Identical for all uint
  (both floor-divide by 5). claimablePool still bumped by full `boxEth`; VAULT gets `boxEth −
  sdgnrsShare`, SDGNRS gets `sdgnrsShare`. Invariant `claimablePool += Σ claimable` preserved.
- **A2 `_creditWhalePassRemainder` (line 39):** `amount − (fullHalfPasses*HALF)` → `amount %
  HALF_WHALE_PASS_PRICE`. Algebraically identical. Whale passes are a non-ETH claim
  (`whalePassClaims`); they do NOT touch claimablePool. No change.

### B. StakedDegenerusStonk.sol — redemption claim split + dust-forfeit + slot packing (the heart)
- **B1 New `creditRedemptionDirect` game-side leg + claim-split rewrite (`_claimRedemptionFor`,
  lines 821-903):** Live-game claim now routes BOTH halves to the GAME (was: direct half pushed
  ETH to the player via `_payEth`, lootbox half to the game). Direct half →
  `game.creditRedemptionDirect{value}(player, ethDirect)` (credits player's game claimable).
  Lootbox half → `game.resolveRedemptionLootbox` (unchanged). Post-gameOver: 100% direct PUSH
  (`_payEth`). change_class: intended-behavior.
- **B2 Dust-lootbox forfeit (lines 845-848, 893-901):** when the lootbox half lands below
  `MIN_REDEMPTION_LOOTBOX_ETH` (0.01 ETH; rolled value < ~0.02 ETH), the lootbox leg is DROPPED and
  its value `forfeitEth` is credited to sDGNRS's OWN game claimable
  (`game.creditRedemptionDirect{value}(address(this), forfeitEth)`). Reconciliation:
  `ethDirect + lootboxEth + forfeitEth == totalRolledEth` in EVERY branch (when lootbox dropped,
  forfeit takes exactly its value), and `_pendingRedemptionEthValue -= totalRolledEth` (line 854)
  releases exactly that. change_class: intended-behavior / invariant-relevant.
- **B3 Permissionless live claim + `claimRedemptionMany` batch + keeper bounty (lines 771-902):**
  `claimRedemption(address player, uint24 day)` — anyone may settle `player`'s claim live (all
  value to player; no ETH pushed at player — credits ride claimable). Post-gameOver gated to
  self-claim (`player != msg.sender → Unauthorized`). New batch skips empty slots; pays caller a
  BURNIE flip-credit per settled box (`creditFlip`, BURNIE-only — no ETH/stETH impact on the
  solvency spine). change_class: new-entrypoint.
- **B4 `BurnsBlockedBeforeDailyRng` gate at submit (lines 1014-1023):** gambling burns now blocked
  until the current day's VRF word is recorded; day index computed locally via
  `GameTimeLib.currentDayIndex()` (replaces `game.currentDayView()`). RNG-window, not solvency, but
  it pins the pool stamp to a drawn day so resolution/segregation timing is deterministic.
- **B5 Slot-0 packing of `_totalSupply` (uint128) + `_pendingRedemptionEthValue` (uint96) +
  `_pendingResolveDay` (uint24) (lines 69-95, 209-217):** former `uint256 totalSupply` /
  `pendingRedemptionEthValue` / `pendingResolveDay` narrowed and co-located; ABI-preserving public
  getters added. Every write now applies a narrowing cast on a CHECKED arithmetic result
  (e.g. line 854/424 `uint96(_pendingRedemptionEthValue − totalRolledEth)`, line 1062
  `uint96(... + maxIncrement)`, supply burns `uint128(_totalSupply − amount)`). Bounds documented:
  `_pendingRedemptionEthValue` ≤ ~1.2e26 wei real-ETH-bound << uint96 7.9e28; `_totalSupply` ≤
  INITIAL_SUPPLY 1e30 << uint128. change_class: gas-or-packing-incidental (but the cast on
  release/segregation is invariant-relevant).
- **B6 `poolBalances` narrowed `uint256[5]` → `uint128[5]` (lines 90-95):** pool-distribution
  scalars (Whale/Affiliate/Lootbox/Reward/PresaleBox), not ETH; sDGNRS token amounts, BPS slices of
  INITIAL_SUPPLY << uint128. change_class: gas-or-packing-incidental.
- **B7 sETH pre-approve comment widened + lootbox `keccak` → `EntropyLib.hash2` (line 879):**
  entropy derivation migration (RNG-byte-shape, not solvency). Pre-approval now covers both claim
  legs.

### C. DegenerusGameLootboxModule.sol — new `creditRedemptionDirect` body (lines 1004-1015)
- **C1:** Delegatecall target of the Game stub. Auth `msg.sender == SDGNRS`; `msg.value <= amount`;
  pulls `amount − msg.value` as stETH via `transferFrom`; then `_creditClaimable(player, amount)` +
  `claimablePool += amount`. Order is value-in-before-credit (correct). Mirrors the existing
  `resolveRedemptionLootbox` funding mix. change_class: new-entrypoint / invariant-relevant.
- **C2 `resolveRedemptionLootbox` (lines 926-957):** UNCHANGED in accounting — credits
  futurePrizePool by `amount`, NO claimableWinnings[SDGNRS] debit (the value was pulled out at
  submit via pullRedemptionReserve). 5-ETH chunked resolution.

### D. DegenerusGame.sol stubs + pullRedemptionReserve
- **D1 New `creditRedemptionDirect(address,uint256) payable` stub (line 1552):** thin delegatecall
  to the lootbox module. change_class: new-entrypoint.
- **D2 `pullRedemptionReserve` (lines 1572-1600):** UNCHANGED logic — pure-ETH leg
  (`_debitClaimable(SDGNRS, amount)` + `claimablePool -= amount` + `call{value:amount}` to sDGNRS),
  pure-stETH fallback leg (no game move/debit; sDGNRS's own stETH backs it), else revert.
- **D3 `claimWinnings` strict CEI (lines 1230-1255):** UNCHANGED — debit `claimablePool` before the
  untrusted payout. `_payoutWithStethFallback` (lines 1888-1909) carries the CEI reorder
  (`53cd25cf`): stETH leg moved out FIRST, untrusted ETH `.call` LAST, so a reentrant
  `distributeYieldSurplus` cannot read in-flight stETH as unreserved backing.

### E. DegenerusGameDecimatorModule.sol — permissionless claim + batch + bounty
- **E1 `claimDecimatorJackpot(address player, uint24 lvl)` now PERMISSIONLESS (lines 283-322):**
  was caller-self (`claimDecimatorJackpot(uint24)` → `_consumeDecClaim(msg.sender)`). Anyone may
  resolve `player`'s claim; all value credits to `player` (winner). Resolution-into-claimable only;
  no ETH leaves. change_class: new-entrypoint.
- **E2 New `claimDecimatorJackpotMany` + keeper bounty (lines 339-380):** batch, skip non-winners,
  BURNIE flip-credit per settled box (BURNIE-only — no ETH/stETH spine impact).
- **E3 Decimator claim accounting (UNCHANGED model, `_creditDecJackpotClaimCore` line 449-464):**
  the full decimator `poolWei` is moved into `claimablePool` at RESOLUTION (AdvanceModule line
  958-964: `runDecimatorJackpot` returns 0 when winners exist → `spend = decPoolWei` →
  `claimablePool += decPoolWei`). At CLAIM the ETH half stays in claimable; the lootbox half is
  `claimablePool -= lootboxPortion` and moved to futurePrizePool. Balanced.
- **E4 Terminal-decimator offset keyed at `lvl+1` (lines 1014-1108):** the DEC-ALIAS fix carried in
  — terminal offset stored/read at `decBucketOffsetPacked[lvl+1]` so it never aliases a live regular
  round's `[lvl]`. Claim accounting unchanged.
- **E5 `DecClaimRound` field narrowing (line 273):** `poolWei` uint96 / `totalBurn` uint128 /
  `rngWord` uint32. poolWei is real-ETH-bound. Packing-incidental.
- **E6 Whale-pass remainder in `_awardDecimatorLootbox` (lines 650-674):** restructured (mod
  arithmetic + threshold fall-through); accounting unchanged — sub-half-pass remainder stays in
  futurePrizePool, never double-backed.

### F. DegenerusGameJackpotModule.sol — `_addClaimableEth` inlined, manual delta fold
- **F1 `_addClaimableEth` REMOVED (was lines 487-502):** it only did `_creditClaimable` + returned
  the amount — NO auto-rebuy or other side-effect. All call sites now call `_creditClaimable`
  directly and accumulate `claimableDelta`/`liabilityDelta` manually, then ONE
  `claimablePool += delta` at the end of each path (daily jackpot line 1118-1120; yield surplus line
  713; reward jackpots fold via AdvanceModule). change_class: gas-or-packing-incidental but
  invariant-relevant (the manual fold must capture EVERY credit).
- **F2 Whale-pass solo split (`_processSoloBucketWinner` lines 1247-1282):** `claimableDelta` = ETH
  portion ONLY; `whalePassCost` → futurePrizePool (NOT claimablePool); `whalePassClaims[winner]`
  records the pass. Preserves invariant — whale-pass value is a pool obligation, not a claimable
  liability.
- **F3 `distributeYieldSurplus` (lines 682-716):** obligations sum =
  current+next+claimablePool+future+yieldAcc+pendingNext+pendingFuture; the CEI reorder in
  `_payoutWithStethFallback` protects this read from in-flight-stETH over-distribution.

### G. DegenerusVault.sol — `deposit()` removed, claim helpers simplified
- **G1 Game-only `deposit(coinAmount, stEthAmount)` + `coinTracked` + `_pullSteth` + `onlyGame`
  REMOVED (lines 463-489 of baseline):** the vault now receives ETH via `receive()` donations +
  game claimable credits, stETH via direct ERC20 transfers, BURNIE via mint-allowance. No path now
  pulls stETH INTO the vault from the game. change_class: intended-behavior. NOTE: any prior caller
  that relied on `game → vault.deposit(...)` is gone — verify no live caller remained.
- **G2 `vaultBurn` returns `supplyBefore` (DegenerusVaultShare lines 303-318):** saves a
  `totalSupply()` round-trip in `burnCoin` (line 699-714). The pre-burn supply is read in the SAME
  call that mutates only share-token storage; the coin/coinflip reserve reads above it are
  unaffected. Accounting-equivalent.
- **G3 `burnEth` claimable-net refactor (`_netClaimableWinnings`, lines 751-770, 885-916):** the
  1-wei-sentinel net of `claimableWinningsOf(vault)` extracted to a helper; `burnEth` claim-trigger
  condition simplified from `claimValue > combined && claimable != 0` to `claimValue > combined`
  (with a proof comment that the second conjunct is implied). Reserve = `combined + claimable`,
  claimValue = `reserve * amount / supplyBefore`. Verify the simplification holds for the edge
  `amount == supplyBefore` (last burn).
- **G4 `gameDegeneretteBet` overpay check moved game-side (lines 577-589):** the
  `value > amountPerTicket*ticketCount` revert was removed from the vault; the comment asserts the
  module's `_collectBetFunds` rejects `ethPaid > totalBet` with the identical formula. Verify that
  game-side guard exists and matches (else vault overpay could over-fund a bet).
- **G5 `jackpotsClaimDecimator` / `vaultMintAllowance` interface entry / `advanceGame` interface
  entry REMOVED:** dead-surface trim following E1's permissionless decimator. No solvency effect.

## Reconciliation conclusions (where the identity holds)

1. **Redemption submit↔claim conservation.** At submit, `pullRedemptionReserve` reserves MAX (175%)
   into `pendingRedemptionEthValue` — ETH-leg debits `claimableWinnings[SDGNRS]` + `claimablePool`
   and pushes ETH to sDGNRS; stETH-leg leaves stETH in sDGNRS custody with NO game-side debit. At
   claim, `_pendingRedemptionEthValue -= totalRolledEth` and exactly `totalRolledEth`
   (= ethDirect + lootboxEth + forfeitEth) re-enters the game via the credit legs (msg.value ETH +
   stETH-remainder pull). The MAX−rolled over-pull stays in sDGNRS as free backing. No double-count
   across the submit/claim boundary.
2. **Decimator pool.** Full pool → claimablePool at resolution; ETH half stays, lootbox half
   migrates to futurePrizePool at claim. Permissionless/batch claims change WHO triggers, not the
   accounting. Balanced.
3. **Jackpot delta fold.** `_addClaimableEth` removal is a pure rename/inline; the manual
   `claimableDelta` accumulation captures every `_creditClaimable` on each path and folds it into one
   `claimablePool +=`. Whale-pass value is correctly routed to futurePrizePool, not claimablePool.
4. **Yield-surplus / CEI.** The stETH-before-ETH reorder in `_payoutWithStethFallback` closes the
   in-flight-stETH over-distribution vector; obligations include claimablePool + pending pools fresh.
5. **Packing.** Every narrowed write applies the cast to a CHECKED arithmetic result with documented
   real-ETH/supply bounds; reads are independent masked SLOADs (no stale cached word).

## Candidate focus areas for the adversarial sweep

- **CF-1 (MED) — `claimRedemption` live-claim has no explicit liveness-window gate; gameOver read is
  a single snapshot.** `claimRedemption`/`claimRedemptionMany` read `isGameOver = game.gameOver()`
  ONCE, then `_claimRedemptionFor` routes the live-game path (credits claimable + funds lootbox)
  when `!isGameOver`. Between `livenessTriggered()` firing and `gameOver()` latching, a resolved
  redemption can settle via the live path; meanwhile `handleGameOverDrain` reserves `claimablePool`
  and sweeps distributable funds. The submit side is gated (`BurnsBlockedDuringLiveness`,
  `RedemptionSweptDuringLiveness`) but the CLAIM side is not. Plausible because: (a) the credit
  legs push real ETH/stETH back into the game and bump claimablePool, so the drain's
  `reserved = claimablePool` should protect it — but the interaction of a live-path credit landing
  during/after the drain's `totalFunds` snapshot (taken at line 78, before any claim in the same
  block could run) is worth a concrete multi-tx ordering check. Location:
  `StakedDegenerusStonk.sol:771-801`, `DegenerusGameGameOverModule.sol:73-182`.

- **CF-2 (MED) — Dust-forfeit credits sDGNRS's OWN game claimable via `creditRedemptionDirect`.**
  The forfeit leg (`creditRedemptionDirect{value}(address(this), forfeitEth)`) re-injects value into
  `claimableWinnings[SDGNRS]` + `claimablePool`. In the stETH-leg submit case NO claimable was
  debited at submit, so confirm the forfeit credit doesn't OVER-credit sDGNRS's claimable relative
  to what the segregation released — i.e. that `forfeitEth` funding is always backed by value
  actually leaving sDGNRS (msg.value + stETH-pull) and not a phantom claimable bump. The leg's
  `bal = address(this).balance; ethForForfeit = min(bal, forfeitEth)` then the GAME pulls the stETH
  remainder; verify the stETH transferFrom can always cover the remainder (the MAX reservation is
  claimed to guarantee ETH+stETH ≥ rolled). Location: `StakedDegenerusStonk.sol:893-901`,
  `DegenerusGameLootboxModule.sol:1004-1015`.

- **CF-3 (MED) — Permissionless decimator/redemption claim + the post-gameOver/freeze edge.**
  `claimDecimatorJackpot` is now permissionless and reverts on `prizePoolFrozen`, but a third party
  can trigger a victim's claim during a live game; verify no path lets a permissionless trigger
  resolve a claim into claimable that is then forfeited (e.g. resolved right as gameOver latches).
  The decimator path checks `prizePoolFrozen` and branches on `gameOver`; the redemption path checks
  `gameOver` once. Worth a check that `gameOver`/`prizePoolFrozen` can't flip mid-batch in a way
  that splits a batch across the boundary inconsistently (the batch caches `over`/`frozen` once).
  Location: `DegenerusGameDecimatorModule.sol:283-380`.

- **CF-4 (LOW) — `burnEth` claim-trigger simplification (`claimValue > combined`).** The dropped
  `&& claimable != 0` conjunct is defended by a proof comment (claimValue > combined implies
  claimable != 0 for any amount vaultBurn accepts). Verify the edge `amount == supplyBefore` (last
  DGVE burn → REFILL_SUPPLY mint) doesn't let `claimValue` slightly exceed `combined` with
  `claimable == 0` (sentinel-only), which would call `claimWinnings(vault)` for a 0-net amount.
  Low impact (a wasted call at worst) but a clean reconciliation check. Location:
  `DegenerusVault.sol:751-770`.

- **CF-5 (INFO — VERIFIED equivalent) — `gameDegeneretteBet` overpay guard relocated to the game
  side.** The vault no longer caps `value` at `amountPerTicket*ticketCount`; the game-side guard
  CONFIRMED present: `_collectBetFunds` line 596 `if (ethPaid > totalBet) revert InvalidBet()`, with
  `totalBet = amountPerTicket * ticketCount` (line 535) — identical to the removed vault formula. No
  value-leak; recorded for completeness only. Location: `DegenerusVault.sol:577-589`,
  `DegenerusGameDegeneretteModule.sol:587-618`.

- **CF-6 (LOW/INFO) — Keeper-bounty `creditFlip` issuance (redemption + decimator batches).** Both
  batch claims mint a BURNIE flip-credit `(settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
  mintPrice` to the caller. BURNIE is off the ETH/stETH solvency spine, so no direct invariant
  break, but BURNIE is redeemable against sDGNRS/vault backing downstream; confirm the issuance is
  bounded (one box per wallet/day for redemption; one decimator entry per real burn) so a keeper
  cannot mint unbounded BURNIE claim-value that later dilutes ETH backing. Location:
  `StakedDegenerusStonk.sol:803-814`, `DegenerusGameDecimatorModule.sol:357-380`.

- **CF-7 (INFO) — Vault `deposit()` removal completeness.** The game-only `deposit` path and
  `coinTracked` reserve tracking were removed. Confirm no remaining game-side code attempts
  `vault.deposit(...)` (would be a dead/reverting call) and that BURNIE mint-allowance accounting
  (now read live via `vaultMintAllowance()` rather than the dropped `coinTracked`) cannot
  over-mint — `burnCoin`'s `remaining` over-mint is claimed to revert inside `vaultMintTo` against
  the live allowance. Location: `DegenerusVault.sol:680-760`.
