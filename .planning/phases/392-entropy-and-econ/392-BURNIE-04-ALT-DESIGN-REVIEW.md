# Does the user's BURNIE-redemption design make sense?

## 1. Headline verdict — NEEDS CHANGE (the core idea is right; two pieces are wrong as stated)

The *direction* is sound and arguably better than the escrow-and-remint spec: keep redeemers' carry shares riding sDGNRS's actual coinflip rather than cloning/reminting a credit. But as literally specified the design has two design-blocking defects: (a) a `uint64 burnieBase` lane in raw wei **cannot hold the value** — it overflows ~10,842× at genesis; and (b) accumulating shares *without removing them from the live carry at submit* **breaks conservation on every winning day** (double-promise of exactly `burnieBase`, plus same-day multi-redeemer over-fraction). Both are fixable without abandoning the aggregate-lane + resolve-against-actual-carry premise — but the fix forces (1) a different width/encoding and (2) a submit-time carry decrement. With those two changes folded in, the design becomes sound-with-caveats; the ordering/freeze axis is already satisfied by the existing advance order.

## 2. Why it's attractive vs. escrow-and-remint

- **Faithfulness.** The redeemer's share rides sDGNRS's *real* flip on the same draw `resolveRedemptionPeriod` resolves on. No cloned/reminted credit that could diverge from the bankroll's actual fate.
- **No new mint surface on the loss path.** On a loss the carry zeroes for sDGNRS (`BurnieCoinflip.sol:515`) and the redeemer gets 0 — symmetric, conservative, nothing minted.
- **ETH-leg consistency.** It reuses the exact rail the ETH side already runs: a per-day aggregate (`DayPending`) reconciled by one GAME-only `resolveRedemptionPeriod` that stamps one shared outcome for the day, with per-claimer fan-out deferred to `_claimRedemptionFor`. The BURNIE leg becomes purely additive over a proven structure rather than a parallel escrow subsystem.

## 3. Concrete blockers / caveats, each with the fix

### 3a. WIDTH — `uint64 burnieBase` lane: definitive NO (with arithmetic)

- BURNIE has 18 decimals (`BurnieCoin.sol:278`), so 1 BURNIE = 1e18 raw wei → `uint64.max` (1.844e19) = only **~18.45 whole BURNIE** in raw wei.
- `SEED_FLIP_DAILY = 200_000 ether` (`BurnieCoinflip.sol:142`) → day-1 seed staked to sDGNRS = 2.0e23 wei = **~10,842× `uint64.max`**. `burnieOwed` is computed in raw wei (`StakedDegenerusStonk.sol:1031`) and passed in raw wei to `redeemBurnieShare` (`:1071-1073`). A single redeemer's proportional slice of the genesis backing already overflows; the `+=` either reverts (checked) or silently wraps (matching the sibling unchecked `pool.ethBase`/`burned` adds) and corrupts the aggregate.
- Even **whole-token** encoding (1e18 divisor, matching the sibling `supplySnapshot`/`burned` lanes) is not *provably* safe in `uint64`: BURNIE supply is uint128-bounded with **no economic MAX_SUPPLY** (`BurnieCoin.sol:341`, `mintForGame` uncapped at `:444`) → whole-token ceiling = uint128.max/1e18 ≈ **3.40e20 BURNIE**, which exceeds `uint64.max` whole tokens (1.84e19) by ~18.4×.
- The provably-safe widths (`uint128` raw-wei, or `uint96` whole-token) **do not fit** the 64 free bits left in `DayPending` (three `uint64` = 192/256, confirmed `StakedDegenerusStonk.sol:283-287`).

**Fix (pick one):**
- **Best (honors maximal-packing, stays single-slot, provably safe):** re-pack `DayPending` — `ethBase`/`supplySnapshot`/`burned` all carry huge documented headroom (`ethBase` ~11,500× under, `supplySnapshot` ~1.84e7× under, per the in-struct doc) — narrow them (e.g. `uint48` each) to open a `uint96` whole-token `burnieBase` lane in the same slot.
- **Minimal-change:** `uint64` whole-token lane **with a fail-closed `BurnieBaseOverflow` revert** on the narrowing cast and a documented bound. Accept and document the sub-1-BURNIE dust truncation that whole-token encoding introduces vs. today's exact raw-wei at-submit settlement.
- **Decoupled:** a separate `mapping(uint24 => uint128)` outside `DayPending` (one extra cold SSTORE on first-burn-of-day). Re-run `forge inspect storageLayout` and recalibrate slot-hardcoded harnesses.

Raw-wei `uint64` is rejected outright.

### 3b. CONSERVATION — "NOT removed from the carry at submit" breaks the win path (HIGH)

This is the defining break and a direct consequence of the user's explicit "aggregate, NOT escrow removed from the carry."

- **Double-promise.** `autoRebuyCarry` is a single shared bankroll. On a winning day it pays out (with growth) to whoever still holds sDGNRS. If the redeemer's slice was never debited at submit, "distribute the recorded `burnieBase`" pays day-D redeemers **on top of** a carry remaining holders still redeem in full. With the intended owned+carry base widening, net promised on a winning day = `burnieBase` (to redeemers) + `C_win` (still fully claimable by holders) > actual carry `C_win`. Over-mint = exactly `burnieBase`, on every winning day with ≥1 redeemer.
- **Same-day multi-redeemer over-fraction.** Carry = C, supply = S. A burns `a`: records `C·a/S`, carry not decremented. B then burns `b`: records `C·b/(S−a)`. Since `a/S + b/(S−a) > (a+b)/S`, the summed recorded fractions exceed the redeemers' true collective ownership `(a+b)/S`. The aggregate over-counts the carry even ignoring remaining holders.
- **"distribute recorded burnieBase" vs "recompute share of grown carry" — does the policy change conservation? Yes.** "Distribute recorded `burnieBase`" pays a *pre-flip* figure while the carry at resolve is the *post-flip* `C_win` — internally inconsistent with "rides the actual flip" and double-promising. "Recompute a proportional share of the resolved carry" is the only conservable shape, but it requires (i) deducting the distributed amount from the live carry at resolve and (ii) telescoped per-redeemer fractions — which a single aggregate scalar cannot reconstruct (it stores summed pre-flip wei only).

**Fix:** reintroduce the **submit-time carry decrement** even while keeping the aggregate lane (hybrid): at submit, accumulate `burnieBase` *and* decrement `playerState[SDGNRS].autoRebuyCarry` by the same slice (the escrow design's `consumeRedeemedCarry`). Then remaining holders read the carry **net of the promise**, B re-reads the carry fresh after A's slice is removed (kills the over-fraction), and the win path becomes a **pure deferred mint of an already-segregated amount** — no fragile live-carry deduction at resolve/claim. This is the only structure that makes win-branch conservation airtight against a fused, already-rolling carry scalar.

### 3c. ORDERING / read-the-outcome — already satisfied; one read-source caveat (sound-with-caveats)

- The advance order is **already correct** and needs **no unsafe reorder**: in the normal `rngGate`, `processCoinflipPayouts(currentWord, day=D+1)` settles sDGNRS's carry through D+1 (`AdvanceModule.sol:1245`; win compounds `BurnieCoinflip.sol:497-506`, loss zeroes `:515`, carry rolls into D+1 stake `:472`) **before** `resolveRedemptionPeriod(roll, D)` (`AdvanceModule.sol:1256-1261`). So resolve observes the freshly-settled D+1 carry — the flip the carry-for-D actually rides.
- **Caveat (must-fix): do NOT read the resolve-site `currentWord & 1`.** That equals D+1's flip *only when no stall intervened*. Under a multi-day VRF stall, the carry-for-D is settled inside `_backfillGapDays` against `keccak256(currentWord, D+1)` (`AdvanceModule.sol:1838-1843` → `BurnieCoinflip.sol:877`), a **different draw** than the resolve advance's `currentWord`. Keying off `currentWord` would pay/zero redeemers off the wrong flip. Also note `resolveRedemptionPeriod` today receives only the **post-shifted `roll`** (`((currentWord>>8)%151)+25`), not the raw word — it cannot even recover `currentWord & 1`. So an explicit additive read/param is required regardless.

  **Fix:** key the contingency to the **absolute D+1 day-result lane** — add a `coinflipDayWon(uint24)` view over `_dayResult` (populated unconditionally inside `processCoinflipPayouts` via `_storeDayResult`, including on backfill, `BurnieCoinflip.sol:824`), resolved at claim time exactly like the proven ETH lootbox `rngWordForDay(day+1)` pattern (`StakedDegenerusStonk.sol:894`). Never the resolve advance's word or roll.

### 3d. DISTRIBUTE POLICY — interpretation (a) is the only feasible one (sound, ratify it)

- **(b) is structurally infeasible** against a per-day aggregate scalar: the grown carry is a single fused value (`BurnieCoinflip.sol:154`) with no per-redeemer growth factor; the per-redeemer rows are ETH-only (`PendingRedemption{ethValueOwed, activityScore}`, `:259-262`) with no BURNIE field to fan growth into; and by claim time the D+1 carry has already rolled to the D+2 stake (`:472`). So the design **can only implement (a)**: on a win the redeemer gets their recorded submit-time principal slice; on a loss, 0.
- This means **all D+1 upside** (the 50–156% `rewardPercent` multiplier + 0.75% recycling bonus, `:497-506`) accrues to **remaining holders**, not the exiting redeemer. That is fair (they chose to exit at submit) and gas-cheap — but it is a genuine policy decision the user should **explicitly ratify**, not have fall out of the structure.

### 3e. GAMEOVER / freeze / reentrancy

- **GameOver (HIGH, must add):** both gameOver-entropy branches guard `processCoinflipPayouts` on `lvl != 0` (`AdvanceModule.sol:1309, 1344`) yet call `resolveRedemptionPeriod` **unconditionally**, and run **no** `_backfillGapDays`. So at lvl==0 / a gameOver stall, the D+1 result is never stored → a `coinflipDayWon`-keyed lane is unresolvable and strands `_pendingBurnieEscrow`; and BURNIE is tombstoned at the drain (`GameOverModule.sol:143`), so any post-latch "won" distribution mints worthless tokens. **Fix:** define unresolved-at-gameOver as a **LOSS** — force-zero every outstanding `burnieBase` lane (and the aggregate escrow) at the latch, and guard the BURNIE-distribute leg on `!isGameOver`.
- **Freeze:** safe **iff** win/loss is consumed in-advance (resolve runs in the freeze-exempt `advanceGame`) and claim reads **no** carry / no coinflip outcome. The deferred-mint-at-resolve shape (3b/3c) gives exactly this; a live-carry read at the permissionless, rngLocked-ungated `claimRedemption` would re-open the dodge-a-known-loss window the `claimCoinflipCarry` rngLocked guard exists to close.
- **Reentrancy (LOW):** sDGNRS has no global guard, but existing `_claimRedemptionFor` is CEI-safe. Zero the per-(player,day) BURNIE lane + decrement the escrow **before** any external call, and place the internal mint (`_addDailyFlip`, no untrusted callout) before the ETH `_payEth` push.

## 4. Revised touchpoint sketch (if you adopt the fixes)

1. **`DayPending` lane.** Add the BURNIE aggregate in **whole tokens**, not raw wei. Preferred: re-pack to `uint48 ethBase / uint48 supplySnapshot / uint48 burned / uint96 burnieBase` (single slot, provably safe); minimal: `uint64` whole-token + `BurnieBaseOverflow` fail-closed cast. Re-run `forge inspect StakedDegenerusStonk storageLayout` and recalibrate slot-hardcoded harnesses by name.
2. **Submit (`_submitGamblingClaimFrom`).** Keep computing the redeemer's carry-share slice, accumulate it into `burnieBase` (whole-token), **and** decrement `playerState[SDGNRS].autoRebuyCarry` by the same slice (`consumeRedeemedCarry`) so the live carry is net-of-promise. (This is the one place the user's "NOT removed at submit" framing must be reversed.)
3. **Advance ordering.** No reorder. After `processCoinflipPayouts(currentWord, D+1)` (already first), read the **absolute D+1** win/loss via `coinflipDayWon(D+1)` and resolve the day's BURNIE: **loss → zero the lane + release escrow; win → record a per-day resolved BURNIE-per-unit** (mirroring how `redemptionPeriods[day]` stores the ETH roll) for deferred claim-time mint.
4. **Claim (`_claimRedemptionFor`).** Mint each redeemer's slice via an SDGNRS-only `payRedeemedBurnie`/`_addDailyFlip` with **no** `autoRebuyCarry` read and **no** coinflip-outcome read. Zero the per-(player,day) BURNIE lane + decrement the day aggregate **before** any external call; keep the mint before `_payEth`.
5. **Conservation discipline.** Add a per-advance fuzz invariant: `Σ(recorded burnieBase across pending days) ≤ autoRebuyCarry(SDGNRS) + held + claimable` at every advance step. Add gameOver regressions: gameOver-at-level-0 with an outstanding redemption must not revert and must zero the lane.

## 5. Decision points for the user

1. **Width/packing:** re-pack `DayPending` to a `uint96` whole-token lane (provably safe, single slot, best packing) **vs.** `uint64` whole-token with a fail-closed overflow revert (minimal change, accepts sub-1-BURNIE dust truncation) **vs.** a separate `uint128` mapping (decoupled, one extra cold SSTORE)?
2. **Conservation:** accept reinstating the **submit-time carry decrement** (the one reversal of your "NOT removed at submit" framing). Without it the win path is not conservable; with it the aggregate-lane approach is fully sound. Confirm.
3. **Distribute policy (ratify (a)):** redeemer gets the **submit-time principal slice** on a win, 0 on a loss, with **all** D+1 growth (50–156% multiplier + 0.75% recycle) going to remaining holders. Interpretation (b) is infeasible — confirm you accept (a).
4. **Read source:** confirm the contingency keys off the **absolute D+1 day-result** (`coinflipDayWon`/`rngWordForDay(day+1)` pattern), not the resolve-advance `currentWord` — required for stall-correctness.
5. **GameOver rule:** confirm **unresolved-at-gameOver = LOSS** (force-zero the lane at the latch, guard distribute on `!isGameOver`).

Frozen-source anchors: `StakedDegenerusStonk.sol:259-262, 283-287` (ETH-only per-redeemer row + 64-free-bit aggregate struct), `:731-758` (aggregate-only resolve), `:1031, 1071-1073` (raw-wei `burnieOwed`), `:894` (`rngWordForDay(day+1)` pattern); `BurnieCoinflip.sol:142` (200k seed), `:154` (fused carry), `:472/497-506/515` (carry roll/win/loss), `:822-825/1092-1096` (`_dayResult`); `BurnieCoin.sol:278` (18 decimals), `:341` (uint128-only supply guard), `:528-536` (tombstone); `AdvanceModule.sol:1245-1261` (processCoinflip-then-resolve order), `:1307-1359` (gameOver branches), `:1822-1844` (gap-backfill); `GameOverModule.sol:143` (tombstone-at-drain).