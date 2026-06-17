# Council Sweep 390 — SOLVENCY-SPINE: claimablePool / ETH-stETH / sDGNRS-backing slice (SOLV-01..07)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top).
Be concrete and reachable: a finding needs a real ordered call sequence (multi-tx where the ordering
matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the post-v62 **solvency accounting** rework on the ETH/stETH spine: the redemption
claim-path split (a new game-side `creditRedemptionDirect` leg), the dust-lootbox forfeit-to-self
credit, the CEI / yield-surplus reorder, and the JackpotModule `_addClaimableEth` inline + manual
delta-fold. We believe the rework is **value-preserving and backing-conserving** — every credit pairs an
equal `claimablePool` move, the segregated redemption reserve releases exactly what re-enters the game,
and no payout leg leaks in-flight stETH to a reentrant distributor. Your job is to find where that belief
breaks.

**Threat priority (USER-locked for this slice):** DOMINANT = RNG/freeze; HIGH = gas-DoS only in the
`advanceGame` chain (16,777,216 gas = brick); **SPINE = solvency — and this is the SOLVENCY slice, so
the spine identities below ARE the dominant target here**; LOW/confirmatory = access-control / reentrancy
/ MEV. **One exception to the "reentrancy is low" rule: SOLV-06 is the V62-03 CEI / yield-surplus
reentrancy class — the council caught exactly this class in v62 (a yield-surplus read counting in-flight
stETH as unreserved backing) where a Claude-only pass missed it. Treat SOLV-06 as a serious, primary
target, not low.** Keeper-bounty exploitability, where it touches this slice, must be reasoned against
REAL prevailing gas (5–50+ gwei) and flip-credit illiquidity, not the 0.5-gwei reference peg.

## The two master invariants this slice rests on (restated from source)

**GAME identity** (`DegenerusGame.sol` header ~18-19; `DegenerusGameStorage.sol:357-366`):

> `address(this).balance + steth.balanceOf(this) >= claimablePool`
> `claimablePool == Σ (claimable + afking halves of balancesPacked[*])`

Both the per-player claimable winnings AND the prepaid afking funding ride inside the single
`claimablePool` uint128 reserve (no separate aggregate). Every mutation of a player's packed balance
pairs an equal `claimablePool` move at the call site. The prize pools (current/next/future),
`yieldAccumulator`, and the pending freeze-window pools are SEPARATE obligations layered on top in the
yield-surplus view, NOT inside `claimablePool`.

**sDGNRS backing identity** (`StakedDegenerusStonk.sol`): backing per token =
`(ETH bal + stETH bal + claimableWinnings[SDGNRS] − pendingRedemptionEthValue) / totalSupply`.
`pendingRedemptionEthValue` is the **physically-segregated reserve** for unresolved/unclaimed
gambling-burn redemptions — excluded from regular-burn backing so it is never double-spent.

## Trust-boundary framing (so you do not waste passes)

`DegenerusGame.sol` + `contracts/modules/*.sol` all inherit the SAME `DegenerusGameStorage` base, so
`claimablePool` and the packed balances are one shared layout across the modules (cross-module slot
aliasing is not structurally possible). `StakedDegenerusStonk` and `DegenerusVault` are standalone
(regular CALL, own storage); the cross-contract value flow between sDGNRS and the GAME goes through the
`creditRedemptionDirect` / `resolveRedemptionLootbox` / `pullRedemptionReserve` interface legs only. The
residual risk is therefore **accounting correctness across those legs** (conservation, double-credit,
strand, phantom backing, CEI ordering on the payout), NOT layout aliasing.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- The redemption **dust-drop forfeit policy itself** — when a rolled lootbox half lands below
  `MIN_REDEMPTION_LOOTBOX_ETH` (0.01 ETH) it is dropped and forfeited to `claimableWinnings[SDGNRS]`.
  This is an intended anti-dust-farm mechanism. Your job is to verify the forfeit credit is BACKED by
  value actually leaving sDGNRS — NOT to flag that the forfeit happens.
- Lootbox / redemption **claim/open TIMING** as a player edge (the open is permissionless and
  economically-incentivized, seed frozen at request). Do not flag day/level/wait-to-open steering as a
  player advantage. (A concrete strand/double-credit accounting break across the gameOver latch IS in
  scope — that is SOLV-05, an accounting question, not a timing-edge question.)
- **BURNIE is off the ETH/stETH solvency spine.** The keeper-bounty `creditFlip` issuance is a
  BURNIE-only emission. Do NOT model it as an ETH-spine break here; it is routed to the ACCESS / 393
  sweep. The ONE thing in scope for this slice is whether the BURNIE keeper-bounty ISSUANCE IS BOUNDED
  (FC-390-06) — an unbounded mint that downstream dilutes ETH backing — not the BURNIE emission economics.
- Degenerette RTP > 100% and the deliberately-near-worthless WWXRP token (economics, audited elsewhere).
- The documented reward rebalances (EV-multiplier lift, recycle-bonus relaxation, EV-neutral
  redistributions) — economics, audited in the 392 slice; here we care only about ETH/stETH/claimablePool
  conservation, not whether an EV change is intended.
- Operator-approval as the trust boundary; afking inclusive eviction; `claimBingo` no level guard.

## The thesis to BREAK (mapped to SOLV-01..07)

We believe ALL of the following hold. Find a concrete counterexample to any one:

1. **(SOLV-01) Every changed credit/debit pairs an equal `claimablePool` move.** The
   `_debitClaimableAndAfking` per-half guards and the JackpotModule manual `claimableDelta` fold each
   capture every `_creditClaimable`; no credit escapes the pool accounting and no debit double-subtracts.
2. **(SOLV-02) The sDGNRS backing identity holds under the rework** — `ETH + stETH +
   claimableWinnings[SDGNRS] − pendingRedemptionEthValue >= outstanding redemption obligations` at every
   reachable state, including mid-resolution.
3. **(SOLV-03) Redemption submit↔claim conserves exactly.** `ethDirect + lootboxEth + forfeitEth ==
   totalRolledEth` in EVERY branch, and `_pendingRedemptionEthValue -= totalRolledEth` releases exactly
   that — no double-count or leak across the submit/claim boundary; the MAX(175%) over-reservation
   remainder stays in sDGNRS as free backing.
4. **(SOLV-04) The dust-forfeit self-credit is always backed by value actually leaving sDGNRS**
   (msg.value ETH + the stETH-remainder pull), never a phantom claimable bump beyond the pending release.
5. **(SOLV-05) The redemption CLAIM path's liveness-window ordering cannot strand or double-credit**
   across the `handleGameOverDrain` `totalFunds` snapshot and the `livenessTriggered()→gameOver()` latch.
6. **(SOLV-06) The CEI / yield-surplus reentrancy is closed on the ETH/stETH payout legs** — the
   stETH-before-ETH ordering (the V62-03 class) holds on EVERY spine payout, so a reentrant
   `distributeYieldSurplus` cannot observe in-flight stETH as unreserved backing and over-distribute.
7. **(SOLV-07) The JackpotModule delta-fold credits/deletes no pool twice** across the `_addClaimableEth`
   inline rework — every `_creditClaimable` on each path is captured exactly once in the single
   `claimablePool +=` fold, and whale-pass value routes to `futurePrizePool`, not `claimablePool`.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

- `StakedDegenerusStonk.sol`: `claimRedemption` @771; `claimRedemptionMany` @787 (both read
  `isGameOver = game.gameOver()` ONCE then call `_claimRedemptionFor`); `_claimRedemptionFor` @821;
  dust-forfeit branch @845-848 (`lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH` = 0.01 ETH @337) + @897-900
  (`creditRedemptionDirect{value: ethForForfeit}(address(this), forfeitEth)` @900; `ethForForfeit =
  min(bal, forfeitEth)` @899); the direct leg `creditRedemptionDirect{value: ethForDirect}(player,
  ethDirect)` @890; the segregation release `_pendingRedemptionEthValue -= totalRolledEth` @854; the
  submit-side MAX(175%) reservation `_pendingRedemptionEthValue += maxIncrement` @1066;
  `BurnsBlockedBeforeDailyRng` @991 via `GameTimeLib.currentDayIndex()` @983; `_pendingRedemptionEthValue`
  uint96 @223; the GAME pre-approve for both legs @431-432.
- `DegenerusGameGameOverModule.sol`: `handleGameOverDrain` @73; `totalFunds` snapshot @78;
  `reserved = uint256(claimablePool)` @85; `gameOver = true` latch @135; final sweep `claimablePool = 0`
  @206.
- `DegenerusGameLootboxModule.sol`: `creditRedemptionDirect` body @1004-1015 (auth `msg.sender == SDGNRS`;
  `msg.value <= amount`; pulls `amount − msg.value` as stETH via `transferFrom`; then `_creditClaimable` +
  `claimablePool += amount`); `resolveRedemptionLootbox` @926-957 (credits `futurePrizePool`, NO
  `claimableWinnings[SDGNRS]` debit).
- `DegenerusGame.sol`: `claimWinnings` strict CEI @1209-1255 (`_debitClaimableAndAfking` @1247;
  `claimablePool -= payout` @1248 BEFORE the external call); `_payoutWithStethFallback` @1888-1909 (the
  `53cd25cf` CEI reorder: stETH leg out FIRST, untrusted ETH `.call` LAST); `pullRedemptionReserve`
  @1572-1600 (`_debitClaimable(SDGNRS)` + `claimablePool -= amount` @1583; pure-stETH fallback no game
  move); `creditRedemptionDirect` stub @1552.
- `DegenerusGameJackpotModule.sol`: `distributeYieldSurplus` @682 (obligations sum @686-690 includes
  `claimablePool`; the cached-then-fold write @713); `_processSoloBucketWinner` @1247
  (`whalePassCost → futurePrizePool`, ETH portion → `claimableDelta`); daily-jackpot fold
  `claimablePool += liabilityDelta` @1119; `_addClaimableEth` REMOVED (was an inline `_creditClaimable`).
- `DegenerusGameDecimatorModule.sol`: `claimDecimatorJackpot` permissionless @283-322; batch @339-380.
- `DegenerusVault.sol`: `burnEth` claim-trigger @751-770; `deposit()` removed; `gameDegeneretteBet`
  overpay guard relocated game-side @577-589 (vs `_collectBetFunds:596`).

## Concrete break-targets (the prime targets — charge these HARD)

### 1. (prime — SOLV-05 / FC-390-01, MED) Redemption CLAIM path has NO explicit liveness-window gate

`claimRedemption` / `claimRedemptionMany` (`StakedDegenerusStonk.sol:771/787`) read
`isGameOver = game.gameOver()` ONCE, then `_claimRedemptionFor` routes the **live-game path** (credits
`player`'s game claimable + funds the lootbox) when `!isGameOver`. The SUBMIT side is gated
(`BurnsBlockedDuringLiveness` / `RedemptionSweptDuringLiveness`), but the CLAIM side is gated only by that
single `gameOver()` snapshot.

Meanwhile `handleGameOverDrain` (`DegenerusGameGameOverModule.sol`) takes `totalFunds` snapshot @78,
reserves `reserved = claimablePool` @85, latches `gameOver = true` @135, and finally sweeps
`claimablePool = 0` @206.

**Find ANY multi-tx ordering across the `livenessTriggered()→gameOver()` latch and the drain's snapshot
where a redemption settled via the live path either:**
- **(a) strands value** — released from `pendingRedemptionEthValue` (or its segregation reduced) but the
  corresponding credit is not reflected in `claimablePool` / `reserved` / the swept distributable before
  the drain finalizes; or
- **(b) double-credits** — credited via the live path AND swept/refunded by the drain.

Spell out the exact block/tx interleavings to try, e.g.:
- a live claim landing in the SAME block as, or right after, the drain's `totalFunds` snapshot @78 but
  before the `claimablePool = 0` sweep @206;
- a claim that races the `gameOver` latch @135 — read `!isGameOver` at the snapshot @771, then the latch
  flips, then the credit leg (`creditRedemptionDirect`) lands `claimablePool += amount` after `reserved`
  was already taken;
- a `claimRedemptionMany` batch that caches `isGameOver` once and straddles the latch mid-batch.

The credit legs push real ETH/stETH back into the game and bump `claimablePool`, so the drain's
`reserved = claimablePool` SHOULD protect it — but verify the interaction of a live-path credit landing
during/after the `totalFunds` snapshot. **Prove strand/double-credit-free with the exact ordering reason,
OR surface a finding with the interleaving.**

### 2. (prime — SOLV-04 / FC-390-02, MED) Dust-forfeit self-credit backing

The forfeit leg `creditRedemptionDirect{value: ethForForfeit}(address(this), forfeitEth)`
(`StakedDegenerusStonk.sol:900`) credits sDGNRS's OWN game claimable (`claimableWinnings[SDGNRS]` +
`claimablePool += forfeitEth`). In the **stETH-leg submit case NO claimable was debited at submit** (the
stETH stayed in sDGNRS custody; only the ETH-leg submit debited `claimableWinnings[SDGNRS]`).

The forfeit leg computes `bal = address(this).balance; ethForForfeit = min(bal, forfeitEth)` @899, sends
that as `msg.value`, and the GAME-side `creditRedemptionDirect` (`DegenerusGameLootboxModule.sol:1004-1015`)
pulls the remainder `amount − msg.value` as stETH via `transferFrom`, then does `claimablePool += amount`
(crediting the FULL `forfeitEth`).

**Ask whether `forfeitEth`'s funding can EVER exceed the value actually leaving sDGNRS** — find a path
where:
- `ethForForfeit = min(bal, forfeitEth)` under-sends ETH (address(this).balance < forfeitEth), AND
- the GAME-side `creditRedemptionDirect` cannot pull the full stETH remainder (`amount − msg.value` via
  `transferFrom` reverts or sDGNRS lacks the stETH balance / approval),

so either the leg reverts (denial / stuck redemption) or — worse — `claimablePool += amount` credits
MORE than sDGNRS actually released = a phantom claimable bump breaking the GAME identity AND the sDGNRS
backing identity simultaneously.

Tie it to the MAX(175%) reservation (`_pendingRedemptionEthValue += maxIncrement` @1066) claim that
ETH+stETH always covers the rolled value: **break that guarantee** with a concrete
partial-balance / many-claim sequence that drains `address(this).balance` below `forfeitEth` AND leaves
insufficient stETH balance/approval for the remainder pull. Also confirm the forfeit credit reconciles
exactly with the `_pendingRedemptionEthValue -= totalRolledEth` release @854 (`ethDirect + lootboxEth +
forfeitEth == totalRolledEth`) so the forfeit is never credited beyond what the segregation released.

### 3. (prime — SOLV-06, MED) V62-03-class CEI / yield-surplus reentrancy

`_payoutWithStethFallback` (`DegenerusGame.sol:1888`) carries the `53cd25cf` reorder — stETH leg out
FIRST, untrusted ETH `.call` LAST — so a reentrant `distributeYieldSurplus`
(`DegenerusGameJackpotModule.sol:682`, whose obligations sum @686-690 reads `claimablePool` + the
pending pools) cannot observe in-flight stETH as unreserved backing and over-distribute.

**Charge this as if the V62-03 vector still exists somewhere on the changed surface.** Find ANY payout
leg on the spine where EITHER:
- the CEI ordering is NOT applied (a state debit — `claimablePool -=`, `_debitClaimable`,
  `_pendingRedemptionEthValue -=` — happens AFTER the external ETH `.call` / stETH transfer, not before);
  OR
- the stETH-before-ETH ordering is violated, so an in-flight ETH `.call` re-enters
  `distributeYieldSurplus` and the obligations read @686-690 understates the true reserved backing while
  ETH/stETH is mid-flight → over-distribution.

Enumerate the spine payout legs explicitly: `claimWinnings` @1209-1255 (debit @1248 before the call);
the redemption credit legs (`creditRedemptionDirect` @1004-1015 — value-IN-before-credit, but check the
reentrancy of the `transferFrom` pull); `pullRedemptionReserve` @1572-1600 (debit @1583); the JackpotModule
fold @713/@1119; and ANY other ETH `.call` / stETH transfer on the spine. For each: state whether the
debit precedes the external call and whether a reentrant `distributeYieldSurplus` can read stale/inflated
backing, and whether the stETH-first ordering holds. Prove the CEI is closed on each, OR surface the leg
where it is not.

## The remaining leads (numbered break-targets at map severity)

4. **(FC-390-03, MED — cross-ref 393) Permissionless decimator/redemption claim + post-gameOver/freeze
   edge.** `claimDecimatorJackpot` is now permissionless (`DegenerusGameDecimatorModule.sol:283-322`); a
   third party can trigger a victim's claim during a live game. The batch (@339-380) caches `over` /
   `frozen` ONCE. Find any path where `gameOver` / `prizePoolFrozen` flips mid-batch and splits a batch
   across the boundary inconsistently, OR where a permissionless trigger resolves a claim into claimable
   that is then forfeited/swept (e.g. resolved right as `gameOver` latches). Confirm the cached
   `over`/`frozen` is consistent for the whole batch or surface the split.

5. **(FC-390-04, LOW) `burnEth` claim-trigger simplification.** The claim-trigger condition was
   simplified from `claimValue > combined && claimable != 0` to `claimValue > combined`
   (`DegenerusVault.sol:751-770`), with a proof comment that the second conjunct is implied. Verify the
   edge `amount == supplyBefore` (last DGVE burn → REFILL_SUPPLY mint) cannot let `claimValue` slightly
   exceed `combined` with `claimable == 0` (sentinel-only) → a wasted `claimWinnings(vault)` for a 0-net
   amount. Low impact (a wasted call at worst) but confirm the simplification holds.

6. **(FC-390-05, INFO — verified) `gameDegeneretteBet` overpay guard relocated game-side.** The vault no
   longer caps `value` at `amountPerTicket * ticketCount` (`DegenerusVault.sol:577-589`); confirm the
   game-side guard `_collectBetFunds:596 if (ethPaid > totalBet) revert` (with `totalBet = amountPerTicket
   * ticketCount`) is present and matches the removed vault formula exactly — else vault overpay could
   over-fund a bet. Recorded for completeness.

7. **(FC-390-06, LOW/INFO — cross-ref 393/ACCESS-02) Keeper-bounty `creditFlip` issuance bound.** Both
   batch claims (`StakedDegenerusStonk.sol:803-814`, `DegenerusGameDecimatorModule.sol:357-380`) pay the
   caller a BURNIE flip-credit per settled box. BURNIE is off the direct ETH/stETH spine, but it is
   redeemable against sDGNRS/vault backing downstream. **Confirm the issuance is bounded** (one box per
   wallet/day for redemption; one decimator entry per real burn) so a keeper cannot mint unbounded BURNIE
   claim-value that later dilutes ETH backing. The issuance bound is the only in-scope question here, not
   the BURNIE economics.

8. **(FC-390-07, INFO) Vault `deposit()` removal completeness.** The game-only `deposit(coinAmount,
   stEthAmount)` + `coinTracked` + `_pullSteth` were removed (`DegenerusVault.sol:680-760`). Confirm NO
   remaining game-side code attempts `vault.deposit(...)` (a dead/reverting call), and that BURNIE
   mint-allowance accounting (now read live via `vaultMintAllowance()` rather than the dropped
   `coinTracked`) cannot over-mint — `burnCoin`'s `remaining` over-mint is claimed to revert inside
   `vaultMintTo` against the live allowance.

## Inherited cross-refs to fold into this slice (the solvency-conservation half)

- **(FC-389-02 / FC-389-08, INFO/LOW) Narrowing-cast solvency-conservation half.** The uint96
  `_pendingRedemptionEthValue` and uint128 `poolBalances` narrowing casts in `StakedDegenerusStonk.sol`
  do NOT revert on overflow — they silently truncate; safety rests on the economic bound (real-ETH <
  2^96; pool conservation < 2^128). **Ask whether ANY redemption path inflates segregated ETH or a pool
  beyond width** so a silent truncation UNDERSTATES segregated ETH → solvency-accounting drift (e.g. a
  double-credit or accounting drift that accumulates `_pendingRedemptionEthValue` unboundedly, or a
  partial-release path that leaves a residual that re-accumulates). The packing-correctness half is
  audited in 389; here confirm no SOLVENCY path can drive the value past width.

- **(FC-392-08, MED — cross-ref 392) Redemption ETH-spin reaches a live ETH-pool RMW + recirc INSIDE the
  claim path.** The redemption claim path reaches the box ETH-spin (`allowEthSpin=true`) whose
  `_distributePayout` does a live ETH-pool read-modify-write + a recirc box draw INSIDE the redemption
  claim (`DegeneretteModule.sol ~1400`, `_resolveRedemptionChunk`). **Trace whether the ETH-spin pool
  writes + the dust-forfeit + the `pendingRedemptionEthValue` release reconcile EXACTLY** (no double-move
  between the spin pool and the segregated reserve), and whether the recirc box's
  `_applyEvMultiplierWithCap` cap RMW can be raced across redemption chunks. This is the V62-03 / council
  CEI surface reaching the redemption path — charge the ETH-pool RMW + recirc-during-claim ordering.

- **(FC-393-02, INFO — cross-ref 393) Forfeit-to-self timing.** A keeper choosing WHICH redemptions to
  settle could bias when forfeits land vs full lootboxes resolve. The per-claim split is deterministic
  from the fixed roll + the player's owed value. **Confirm no per-victim value extraction — only benign
  timing of backing accrual** (the keeper cannot steer the split to extract value from a specific victim).

- **(FC-393-03, LOW — cross-ref 393) Partial-balance redemption-leg solvency.** Each leg sends
  `min(address(this).balance, legAmount)` ETH and pulls the rest as stETH; the MAX(175%) reservation is
  claimed to guarantee ETH+stETH ≥ rolled. **Under an adversarial sequence of MANY partial-balance live
  claims in ONE block**, confirm the segregation accounting (`_pendingRedemptionEthValue` release == total
  leg movement) never strands ETH or under-pulls stETH — e.g. claim #1 drains most of address(this).balance
  via its ETH leg, then claim #2's leg sends almost no ETH and must pull nearly all of `legAmount` as
  stETH; verify the stETH balance/approval covers EVERY leg in the sequence and the cumulative release
  equals the cumulative leg movement with no residual stranded.

## Output (per item)

For each break-target AND each thesis point (SOLV-01..07), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (multi-tx where the ordering matters) ·
  STATE VAR + `file:line` at `a8b702a7` · SEVERITY (per the threat priority above; note SOLV-06 is the
  serious V62-03 class) · WHY the master-invariant protections (the `reserved = claimablePool` drain
  guard, the MAX(175%) over-reservation, the CEI reorder, the value-in-before-credit ordering) do NOT
  stop it.
- **VERIFIED SOUND:** the property and the specific reason it holds (cite the bound, the mask, the
  reservation, the CEI ordering, or the call-site invariant) so the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7`. The council
finds; the adjudicator (Claude) reconciles at 390-02.
