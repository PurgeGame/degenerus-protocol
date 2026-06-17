# BURNIE-04 — sDGNRS Redemption: Carry-Inclusive, Flip-Contingent BURNIE Value (Fix-Design Spec)

> **Status:** DESIGN ONLY — for a LATER USER-gated, USER-approved contract change. The subject is byte-frozen at `a8b702a7` (`contracts/` tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620`, per `test/REGRESSION-BASELINE-v63.md`). Nothing here is applied now. All file:line references are against `git show a8b702a7:contracts/<path>`.
>
> **HEADLINE VERDICT:** The originally-routed design (absolute BURNIE escrow snapshotted at submit, contingency read from the redeemed day `D`'s coinflip result) is **NOT SOUND** — it failed all five adversarial lenses with convergent HIGH findings. This spec restates the intended design, then specifies a **REVISED, sound design**: a *resolve-time-proportional* carry claim resolved against the *live, freshly-settled* carry on the flip the carry actually rides (**day `D+1`**), with the carry slice **moved out of `autoRebuyCarry` at submit** so it cannot be zeroed, double-promised, or stranded. Several economic-policy choices remain genuinely open and require a USER decision (Section 8) before implementation.

---

## 1. Problem recap + USER ruling (real gap → fix)

**USER-stated intended design (confirmed 2026-06-15):** The redemption value for the BURNIE part of an sDGNRS redemption = the amount **OWNED** (held wallet balance + claimable) **PLUS** the amount in the flip **CARRY** (`autoRebuyCarry`). The redeemer's share is **FLIP-CONTINGENT**: if the next coinflip loses, that share pays nothing; if it wins, the redeemer gets their share and it is **DEDUCTED from the carry** (or from the balance if there is one).

**The gap, concretely:**
1. Every sDGNRS BURNIE-base read funnels through `coinflip.previewClaimCoinflips(SDGNRS)`, which is `_viewClaimableCoin + claimableStored` only (`BurnieCoinflip.sol:971-975`). It **provably omits `autoRebuyCarry`**. Once sDGNRS arms perpetual 0-take-profit auto-rebuy (`BurnieCoinflip.sol:879-892`), winnings **never** route to `claimableStored` — they roll into the carry (`BurnieCoinflip.sol:497-506`, `573`). So in steady state the redemption BURNIE base is structurally **near-zero**, and the carry — the bulk of sDGNRS's BURNIE house value — is unredeemable.
2. There is **no sDGNRS-reachable liquidation path** into the carry. The carry mutators `claimCoinflipCarry` (`:754-779`) and the auto-rebuy toggles (`:691`, `:729`) are not reachable from sDGNRS; sDGNRS only calls `creditFlip`, `previewClaimCoinflips`, and `redeemBurnieShare` (`IBurnieCoinflipPlayer`, `StakedDegenerusStonk.sol:64-74`).

**USER ruling:** This is a real gap (under-implementation of the intended design), routed for a fix. The fix must (a) widen the redemption BURNIE base to include the carry, and (b) give the redeemer's claimed carry slice a flip-contingent payout that resolves on the same daily coinflip cadence the ETH leg already uses.

---

## 2. Intended design (restated precisely)

For `player = SDGNRS` (`address(this)`), the redemption BURNIE value at submit is:

```
burnieValue = owned + carry
  owned = coin.balanceOf(SDGNRS) + claimableBurnie(SDGNRS)   // already in the base today
  carry = playerState[SDGNRS].autoRebuyCarry                  // NEW term
```

A redeemer burning `amount` of `supplyBefore` total receives a proportional slice. The slice splits by source:
- **Owned portion** — backed by held balance + claimable. Always realizable, non-contingent. Settled exactly as today (`redeemBurnieShare`, net-zero burn+consume+credit).
- **Carry portion** — drawn from the carry. **Flip-contingent**: it rides the same coinflip the carry rides next; on a **win** the redeemer is paid (deducted carry-first, then balance); on a **loss** it pays nothing (the carry it rode evaporated for sDGNRS too — symmetric).

**Liquidation path (the intended new value-exit):** the carry-portion is the only mechanism by which BURNIE leaves sDGNRS's flip position other than the existing owned-portion burn+consume — gated entirely behind the redemption flow (`burn`/`burnWrapped` → submit; `advanceGame` rngGate → resolve; `claimRedemption` → payout). No new public surface and no new role beyond two views and one extended internal leg.

**Solvency invariant (must hold):** The carry stays **BURNIE-denominated, off the ETH spine**. BURNIE has no ETH/stETH linkage; the `distributeYieldSurplus` obligations sum (`DegenerusGameJackpotModule.sol:688-700`) and `handleGameOverDrain` (`DegenerusGameGameOverModule.sol:150-153`, reserves only `claimablePool`) must **NOT** gain any carry term. If the escrowed carry ever gained an ETH-settlement path it would have to enter the obligations sum or be over-distributed. This design keeps it pure BURNIE — that axis is sound.

---

## 3. Current behavior at `a8b702a7` (the gap, with file:line)

| # | Behavior | Location |
|---|----------|----------|
| 1 | Redemption BURNIE base = `held + previewClaimCoinflips(SDGNRS)`; **no carry term**. | `StakedDegenerusStonk.sol:1029-1031` (submit), `941-946` (`previewBurn`), `953-957` (`burnieReserve`) |
| 2 | `previewClaimCoinflips` = `_viewClaimableCoin + claimableStored`; **omits `autoRebuyCarry`**. | `BurnieCoinflip.sol:971-975` |
| 3 | The whole BURNIE share is settled **atomically at submit**, net-zero, with **nothing recorded per claim**. | `StakedDegenerusStonk.sol:1066-1073` → `BurnieCoinflip.sol:940-964` |
| 4 | `PendingRedemption` is **ETH-only** (`uint96 ethValueOwed + uint16 activityScore` = 112/256 bits, 144 free). | `StakedDegenerusStonk.sol:259-262` |
| 5 | `_claimRedemptionFor` is **ETH-only** and early-returns on `claim.ethValueOwed == 0`. | `StakedDegenerusStonk.sol:821-833` |
| 6 | `previewBurn` / `burnieReserve` have **no reserve subtraction** ("BURNIE settled at submit, never reserved"). | `StakedDegenerusStonk.sol:937-947`, `949-958` |
| 7 | sDGNRS carry mutators are unreachable from sDGNRS (no liquidation path into carry). | `BurnieCoinflip.sol:754-779` (`claimCoinflipCarry`), `691`, `729` (toggles) — all `rngLocked`-gated and not on the sDGNRS call list (`StakedDegenerusStonk.sol:64-74`) |
| 8 | On a losing day, `_claimCoinflipsInternal` zeroes the **entire** carry. | `BurnieCoinflip.sol:513-516` (`carry = 0`) |
| 9 | The carry **rolls forward** to become the next day's stake under auto-rebuy. | `BurnieCoinflip.sol:470-473` (`stake += carry`) |
| 10 | sDGNRS's in-advance settlement walk is bounded by `windowDays` in the non-deep branch — it does **not** guarantee `lastClaim == flipsClaimableDay` after a multi-day stall. | `BurnieCoinflip.sol:453-458` (`remaining = windowDays`), `851` (`flipsClaimableDay = epoch` regardless), `877-887` (sDGNRS settle) |

---

## 4. The proposed change (REVISED — sound design)

The originally-routed mechanism (absolute escrow snapshotted at submit, contingency on day `D`'s result) is replaced by a **resolve-time-proportional** mechanism. The two design moves below are mandatory; they are the synthesis of every adversarial HIGH.

### 4.0 Why the revision (the two structural reasons the snapshot model fails)

- **The contingency coin must be day `D+1`, not day `D`.** At submit on day `D`, the carry slot is already settled *through* day `D`: submit is gated on `game.rngWordForDay(D) != 0` (`StakedDegenerusStonk.sol:991`, `BurnsBlockedBeforeDailyRng`), and that same advance ran `processCoinflipPayouts(...,D)` which settled sDGNRS into carry (`BurnieCoinflip.sol:877-887`). So **day `D`'s result is already baked into the snapshotted carry.** The carry then *rolls forward* to become day `D+1`'s stake (`stake += carry`, `BurnieCoinflip.sol:472`) and rides day `D+1`'s coin — a `D+1` loss zeroes it (`:515`), a `D+1` win compounds it. Gating the escrow on `_dayResult(D)` (the originally-routed choice) **double-applies `D`, is blind to the resolving flip `D+1`, and — worst — `D`'s result is fully known and public at submit, making the "loss pays nothing" branch unreachable by any chain-watching redeemer (the escrow would have zero real contingency and be grindable). The contingency must ride `D+1`, whose word is unknown at submit (same property the ETH lootbox leg relies on: `rngWordForDay(day+1)`, `StakedDegenerusStonk.sol:894-901`).**

- **The carry slice must be removed from the shared `autoRebuyCarry` slot at submit.** An absolute figure snapshotted against the *live* carry is wrong because the carry is a single shared bankroll that any intervening losing day zeroes entirely (`BurnieCoinflip.sol:515`) and that recycle-compounds on wins (`:505`, `_recyclingBonus :1138-1142`). If the carry is zeroed between submit and claim, a "win" payout against the stale snapshot either bricks the entire claim (`revert Insufficient()`, `BurnieCoinflip.sol:959`, taking the ETH leg with it) or over-pays from held/claimable backing belonging to remaining holders. **Moving the carry slice out of the shared slot at submit makes the escrow self-funding, immune to intervening losses, and free of same-day double-counting.**

### 4.1 Move A — backing widening (a NEW sDGNRS-only view; do NOT touch `previewClaimCoinflips`)

`previewClaimCoinflips` is shared by `DegenerusVault.sol:704,901` and `BurnieCoin.balanceOfWithClaimable:243`, and both VAULT (it can arm rebuy via `coinSetAutoRebuy`, `DegenerusVault.sol:645`) and sDGNRS can carry. Widening the shared funnel would **leak normally-hidden carry into unrelated claim/spend semantics.** Add a separate view instead.

```solidity
// BurnieCoinflip.sol — NEW external view, SDGNRS-only consumer (place beside previewClaimCoinflips:971-975)
// SETTLE-CORRECT base read: returns owned + carry with the terms provably DISJOINT.
// NOTE: this is a non-view (mutating) settle-then-read for the SUBMIT consumer (see §6 R1); a
// best-effort pure preview variant may exist separately for UI but MUST NOT feed the submit base.
function redeemableBurnieSettled(address player) external returns (uint256 owned, uint256 carry) {
    if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();
    // Force lastClaim all the way to flipsClaimableDay so _viewClaimableCoin == 0 and no
    // resolved-unsettled win day is counted in BOTH owned and carry (the disjointness fix).
    _settleToCurrent(player);                       // NEW primitive (see §4.4)
    owned = playerState[player].claimableStored;    // _viewClaimableCoin now provably 0
    carry = playerState[player].autoRebuyCarry;
}
```

The three sDGNRS sites change their BURNIE-base source from `previewClaimCoinflips` to this settled read (submit) or to a documented best-effort view (the two read-only previews):
- `_submitGamblingClaimFrom` — `StakedDegenerusStonk.sol:1029-1031` → use `redeemableBurnieSettled(address(this))`; `owned`/`carry` returned directly.
- `previewBurn` — `StakedDegenerusStonk.sol:941-946` → best-effort `owned + carry` view (document the lag).
- `burnieReserve` — `StakedDegenerusStonk.sol:953-957` → best-effort `owned + carry` view, **minus the outstanding escrow reserve** (see 4.5).

> **Why a settle-then-read (not a pure view) at submit:** `_viewClaimableCoin` (`BurnieCoinflip.sol:1014-1062`) sums resolved-but-unsettled WIN days, and `_claimCoinflipsInternal` later rolls those exact days into `autoRebuyCarry`. The two terms are **only disjoint if `lastClaim == flipsClaimableDay`.** The in-advance settle is bounded by `windowDays` (`:454-458`) and `flipsClaimableDay` advances regardless (`:851`), so after a multi-day stall / gap-backfill (`AdvanceModule.sol:1244-1261`, gap path `:1822-1844`) the terms can **double-count** a win day. Forcing a deep settle to current at the base read removes the double-count by construction.

### 4.2 Move B — contingency via resolve-time-proportional escrow

At submit, compute the slice proportions against the disjoint base and the live carry:

```
ownedPortion = (owned * amount) / supplyBefore       // settle now, exactly as today
carryPortion = (carry  * amount) / supplyBefore       // escrow, flip-contingent
```

- **Owned portion:** settle immediately via the existing `redeemBurnieShare(beneficiary, ownedPortion)` (net-zero, `BurnieCoinflip.sol:940-964`). Unchanged semantics. Because the base read settled sDGNRS to current, `ownedPortion <= held + claimableStored` holds and the existing burn→consume waterfall covers it (no brick).
- **Carry portion:** **decrement `playerState[SDGNRS].autoRebuyCarry` by `carryPortion` now** (new internal leg, §4.4) and record `carryPortion` as a per-(beneficiary, day) BURNIE escrow. **Mint nothing now.** This removes the slice from the shared carry slot so a later loss/win/recycle cannot move it, and so two same-day redeemers each remove their own slice from the live carry (`carry` is re-read fresh per submit and decremented per submit — no two redeemers contend for the same wei).

`carryPortion` is held in the existing `PendingRedemption` slot (144 free bits) and aggregated in a new scalar `_pendingBurnieEscrow`.

### 4.3 Flip-resolution hook (resolve the escrow on day `D+1`'s coinflip)

The escrow resolves on the **same redemption resolve rail** the ETH leg uses, gated on day `D+1`'s coinflip outcome.

- `AdvanceModule.rngGate` already calls `sdgnrs.resolveRedemptionPeriod(roll, D)` for the stamped day after `processCoinflipPayouts(...,D+1)` has run on that advance (`DegenerusGameAdvanceModule.sol:1245`, `1256-1261`; gap variants `1306-1323`, `1338-1358`). The redemption for day `D` resolves on day `D+1`'s draw — the same coupling the lootbox leg already relies on.
- Add a tiny sDGNRS-callable view to read the coinflip outcome of the resolving day:

```solidity
// BurnieCoinflip.sol — NEW view beside _dayResult (:1092-1096)
function coinflipDayWon(uint24 day) external view returns (bool resolved, bool win) {
    (uint16 rewardPercent, bool w) = _dayResult(day);   // 0 = unresolved, 1 = loss, 50..156 = win
    return (rewardPercent != 0, w);
}
```

- The escrow's contingency reads `coinflipDayWon(D + 1)` (the flip the carry rode). `D+1`'s word is unknown at submit on `D` (`rngWordForDay(D+1) == 0` at submit), so the outcome cannot be selected after the fact.

**Where payout/zeroing happens** — in `_claimRedemptionFor` (`StakedDegenerusStonk.sol:821-906`), with the existence check **decoupled from the ETH key**:

```solidity
// CHANGED guard so a zero-ETH (gwei-floored) claim with a nonzero escrow is not stranded:
if (claim.ethValueOwed == 0 && claim.burnieEscrow == 0) return false;
...
// BURNIE-contingency leg (runs even on a zero-ETH claim):
if (claim.burnieEscrow != 0) {
    uint128 escrow = claim.burnieEscrow;
    (bool resolved, bool won) = coinflip.coinflipDayWon(day + 1);
    // resolved is guaranteed true post-resolve in a live game; gameOver handled separately (§8 Q4)
    uint256 burniePaid = 0;
    if (won) {
        // Pay the escrowed slice to the redeemer. Escrow is self-funded (removed from carry at
        // submit), so this is a pure deferred mint — NO carry/held/claimable read, NO brick path.
        coinflip.payRedeemedBurnie(player, escrow);   // NEW: deferred-mint the held escrow
        burniePaid = escrow;
    } // else: loss → pay nothing (the slice burns; symmetric with carry evaporating on a loss)
    claim.burnieEscrow = 0;
    _pendingBurnieEscrow -= escrow;
    // emit burniePaid in RedemptionClaimed
}
```

> **Note on `payRedeemedBurnie` vs. the original `redeemBurnieShare` step-3 extension:** Because the carry slice was *removed from `autoRebuyCarry` at submit*, the win-path is a **pure deferred mint** of an amount already conserved against sDGNRS's backing at submit — there is no claim-time carry read, no `_claimCoinflipsInternal` re-settle, no `revert Insufficient()` brick risk, and no `rngLocked`-window carry mutation. This is strictly safer than the originally-routed "extend `redeemBurnieShare` with a step-3 carry consume at claim time," which read the *live* carry at the permissionless, ungated claim — re-opening the exact dodge-a-known-loss window the `claimCoinflipCarry` `rngLocked` guard (`BurnieCoinflip.sol:759`) exists to close.

### 4.4 New internal primitives in BurnieCoinflip

- `_settleToCurrent(address player)` — deep-settle `player` so `lastClaim == flipsClaimableDay`. Either a new unbounded-to-current walk, or reuse `_claimCoinflipsInternal` with a cap that provably reaches `flipsClaimableDay` (note: `deepAutoRebuy=true` is **insufficient** — its cap is `AUTO_REBUY_OFF_CLAIM_DAYS_MAX`, not unbounded). Bound the worst case (post-stall this can walk up to `COIN_CLAIM_DAYS = 365`; quantify per §5).
- `consumeRedeemedCarry(address /*SDGNRS*/, uint256 amount)` — SDGNRS-only; after `_settleToCurrent(SDGNRS)`, decrement `playerState[SDGNRS].autoRebuyCarry -= amount` (mirror `claimCoinflipCarry:772-774`), **no mint**. Called at submit. Reverts if `amount > carry` (fail-closed; cannot happen because `carryPortion <= carry` by construction from the same settled read).
- `payRedeemedBurnie(address redeemer, uint256 amount)` — SDGNRS-only; `_addDailyFlip(redeemer, amount, 0, false, false)` (deferred mint as a flip credit, like the existing owned-path). The mint is the realization of the carry already removed at submit, so net BURNIE across submit+resolve is conserved.

### 4.5 Reserve subtraction (single-counting discipline)

Add aggregate `_pendingBurnieEscrow`. Subtract it from the BURNIE base in the read paths so subsequent burns see carry net of outstanding promises — the BURNIE analogue of `_pendingRedemptionEthValue` subtraction on the ETH side (`StakedDegenerusStonk.sol:1027`). **Use a saturating (floored-at-0) subtraction** so a transiently-low carry read cannot underflow-revert and freeze other holders' previews.

- At submit, because `carryPortion` is *removed from `autoRebuyCarry` immediately*, the next submit's `carry` read is already net of it — the reserve is belt-and-suspenders for the read-only previews and for the window between decrement and the next settle. Subtract `_pendingBurnieEscrow` (saturating) in `previewBurn`/`burnieReserve`.
- Increment `_pendingBurnieEscrow += carryPortion` at submit; decrement `_pendingBurnieEscrow -= escrow` at resolve (win **or** loss). Invariant: `Σ over (player,day) burnieEscrow == _pendingBurnieEscrow`.

### 4.6 Touchpoint table (exact)

| File / function | Change |
|---|---|
| `BurnieCoinflip.sol` (beside `previewClaimCoinflips:971-975`) | Add `redeemableBurnieSettled(address) returns (owned, carry)` (SDGNRS-only, settle-then-read). Do **NOT** modify `previewClaimCoinflips`. |
| `BurnieCoinflip.sol` (beside `_dayResult:1092-1096`) | Add `coinflipDayWon(uint24 day) returns (bool resolved, bool win)`. |
| `BurnieCoinflip.sol` (new internals) | Add `_settleToCurrent`, `consumeRedeemedCarry` (SDGNRS-only carry decrement, no mint), `payRedeemedBurnie` (SDGNRS-only deferred mint). `redeemBurnieShare:940-964` stays as-is for the owned portion. |
| `StakedDegenerusStonk.sol:259-262` (`PendingRedemption`) | Add `uint128 burnieEscrow` (96+16+128 = 240/256, still 1 slot — 144 free bits confirmed). Update the "nothing BURNIE-related is recorded" comment. |
| `StakedDegenerusStonk.sol` (new scalar) | Add `_pendingBurnieEscrow` in a **NEW dedicated slot** (slot 0 is full — see §5). |
| `StakedDegenerusStonk.sol:1029-1073` (submit) | Source base via `redeemableBurnieSettled`; settle `ownedPortion` via `redeemBurnieShare`; call `consumeRedeemedCarry(SDGNRS, carryPortion)`; record `claim.burnieEscrow += carryPortion`, `_pendingBurnieEscrow += carryPortion`. |
| `StakedDegenerusStonk.sol:821-906` (`_claimRedemptionFor`) | Decouple existence guard (`ethValueOwed==0 && burnieEscrow==0`); add the contingency leg reading `coinflipDayWon(day+1)`; win → `payRedeemedBurnie`; loss → nothing; both → zero escrow + decrement reserve. |
| `StakedDegenerusStonk.sol:937-947` (`previewBurn`) & `949-958` (`burnieReserve`) | Source `owned+carry`; subtract `_pendingBurnieEscrow` (saturating). Update "no reserve" comments. |
| `StakedDegenerusStonk.sol:185-187,190-191` (events) | `RedemptionSubmitted`: split `burnieSettled` → `burnieSettled` (owned) + `burnieEscrowed` (carry). `RedemptionClaimed`: add `burniePaid`. |
| `StakedDegenerusStonk.sol:64-74` (local `IBurnieCoinflipPlayer`) | Declare `redeemableBurnieSettled`, `coinflipDayWon`, `consumeRedeemedCarry`, `payRedeemedBurnie`. |
| `contracts/interfaces/IBurnieCoinflip.sol` (beside `previewClaimCoinflips:138-143`) | Declare the new externals for other consumers. |
| `StakedDegenerusStonk.sol` (gameOver path) | Resolve all outstanding escrow at the gameOver latch (see §8 Q4). |

---

## 5. New state + EIP-170 / gas note

**Storage (verified via `forge inspect StakedDegenerusStonk storageLayout`):**
- Slot 0 = `_totalSupply` (uint128, off 0, 16 B) + `_pendingRedemptionEthValue` (uint96, off 16, 12 B) + `_pendingResolveDay` (uint24, off 28, 3 B) = **31 of 32 bytes used (1 free byte).** The originally-routed claim that a `uint96 _pendingBurnieEscrow` "could pack beside them in slot 0" is **FALSE.** `_pendingBurnieEscrow` **must occupy a new dedicated slot** (any width up to uint256 since it is alone; `uint128` is the natural mint-supply-bounded choice). **Explicitly forbid reordering/widening slot-0 fields to make room** — per the storage-packing lesson, a slot-0 shift silently breaks the ~30 slot-hardcoded `vm.store`/`vm.load` harnesses at runtime (compile stays green). The `pendingRedemptions` mapping value is its own slot region; adding `uint128 burnieEscrow` to the struct stays within the existing single 256-bit slot (112 → 240 bits) and does **not** shift any scalar slot.
- `PlayerCoinflipState.autoRebuyCarry` (`BurnieCoinflip.sol:154`) already exists — no new BurnieCoinflip storage.
- Net new storage: **one struct field (free, in-slot) + one new scalar slot.** Re-run `forge inspect ... storageLayout` post-edit and re-derive every slot-hardcoded harness against the green baseline before any test interpretation.

**EIP-170 (verified at the frozen subject):** BurnieCoinflip ≈ 15.0 KB deployed (~9.5 KB headroom); StakedDegenerusStonk ≈ 12.6 KB deployed (~11.9 KB headroom). The two new views + three internals on BurnieCoinflip and the base-read swaps + escrow leg + struct field + scalar on StakedDegenerusStonk are trivial against those margins. The perpetually-tight `DegenerusGame` (~19.4 KB) is **NOT on this path**. Using `redeemableBurnieSettled` instead of widening `previewClaimCoinflips` means `DegenerusVault` and `BurnieCoin` do not grow at all. **EIP-170 is a genuine non-issue.**

**Gas / batch-sizing:** The carry-portion work splits across submit (carry decrement) and resolve (deferred mint). The resolve work — `coinflipDayWon` view (1 SLOAD) + `payRedeemedBurnie` (`_addDailyFlip`: packed stake write + `_updateTopDayBettor` leaderboard + 2 emits, `BurnieCoinflip.sol:613-619`) — runs **per winning redeemer inside the unbounded `claimRedemptionMany` loop** (`StakedDegenerusStonk.sol:787-813`). This path is **NOT** in the `advanceGame` chain (the 16.7M hard ceiling), so it cannot brick the game — it only caps keeper batch size `N`. Quantify the worst-case per-winning-box marginal gas (leaderboard write taken, cold escrow-slot release) and document a safe `N` per the v56 dual-bound rule (target <10M/tx, provably never >16.7M). The `_settleToCurrent` walk at submit can reach `COIN_CLAIM_DAYS = 365` after a stalled advance (`BurnieCoinflip.sol:136`, `423`, `460`) — fold that worst case into the submit-path gas derivation. **Reject the "escrow the full owned+carry share" variant on gas grounds** — keeping the owned portion atomic-at-submit minimizes per-box claim gas.

---

## 6. Adversarial review — each raised risk and how the revised design handles it

| Lens / Risk | Severity (as raised) | Disposition in this design |
|---|---|---|
| **L1-R1 — `redeemableBurnie` double-counts a resolved-unsettled win day when sDGNRS's settle lags `flipsClaimableDay`** (`_viewClaimableCoin` ∩ carry not disjoint; bounded `windowDays` walk + multi-day stalls; `BurnieCoinflip.sol:454-458,851,877-887,1014-1062`) | HIGH | **HANDLED.** Base is read via `redeemableBurnieSettled`, which `_settleToCurrent` first so `_viewClaimableCoin == 0` and `owned`/`carry` are provably disjoint. The base is `claimableStored + autoRebuyCarry` only; the lagging unsettled-win term is eliminated, not summed. (§4.1) |
| **L1-R2 — raw-carry `carryBase` lets N same-day redeemers each escrow a slice of the *same* full carry; not net of `_pendingBurnieEscrow`; `supplyBefore` shrinks per burn so proportions don't telescope** | HIGH | **HANDLED.** Each submit *removes* its `carryPortion` from `autoRebuyCarry` immediately (`consumeRedeemedCarry`) and re-reads `carry` fresh on the next submit, so two redeemers never escrow the same wei. The aggregate reserve is belt-and-suspenders. Invariant `Σ burnieEscrow == _pendingBurnieEscrow <= autoRebuyCarry`. (§4.2, §4.5) |
| **L1-R3 / L3-R1 / L4-R3 — absolute snapshot vs. a carry that an intervening loss zeroes: win-branch over-draws → brick (`Insufficient()` `:959`, takes ETH leg) or over-pay from other holders' backing; recycle growth drift** | HIGH | **HANDLED.** No absolute snapshot against the live carry. The slice is *removed from carry at submit* and held as a self-funded escrow; the win-path is a pure deferred mint with no live-carry read. An intervening loss cannot touch an amount already removed; recycle growth accrues to remaining holders, not the redeemer (consistent with the snapshot-freezes-the-slice intent). (§4.2, §4.3) |
| **L2-R1 — zero-ETH claim permanently strands the escrow** (`_claimRedemptionFor` early-returns on `ethValueOwed == 0`, `:833`; post-day-20 carry-dominant regime gwei-floors ETH to 0) | HIGH | **HANDLED.** Existence guard decoupled: `if (claim.ethValueOwed == 0 && claim.burnieEscrow == 0) return false;`. The contingency leg runs on zero-ETH claims; reserve is released. (§4.3) |
| **L2-R2 / L3-R2 / L4-R1 — contingency coin is the WRONG flip: snapshot already absorbed day `D`; carry rides `D+1`; `D`'s result is public at submit (grindable, zero real contingency)** | HIGH | **HANDLED.** Contingency reads `coinflipDayWon(D+1)` — the flip the carry actually rides, unknown at submit (`rngWordForDay(D+1)==0`). Resolution is on the same advance that settles `D+1` and runs `resolveRedemptionPeriod(D)` (`AdvanceModule.sol:1245-1261`). (§4.0, §4.3) |
| **L4-R2 — extended `redeemBurnieShare` reads/decrements live carry at the permissionless, `rngLocked`-ungated `claimRedemption`** | HIGH | **HANDLED.** Eliminated. The carry is consumed only at submit (already `rngLocked`-gated via `burn`/`burnWrapped`, `StakedDegenerusStonk.sol:628,646`). The claim-time win-path is a pure deferred mint (`payRedeemedBurnie`) with no live-carry access. (§4.3 note) |
| **L1-R4 / L2-R4 / L3-R3 / L4-R5 — gameOver-stranded escrow: pays tombstoned/zero backing or permanently freezes `_pendingBurnieEscrow`** (`GameOverModule.sol:135,143`; `previewBurn` gated `!gameOver` `:942`) | MEDIUM | **OPEN — requires USER decision (Q4).** Recommended resolution: at the gameOver latch, resolve all outstanding escrow as **loss** (zero `burnieEscrow`, release `_pendingBurnieEscrow`), symmetric with BURNIE tombstoning and with the loss-pays-nothing branch; and treat `coinflipDayWon(D+1)` `resolved==false` post-gameOver as loss. Guard the contingency leg on `!isGameOver`. (§8 Q4) |
| **L4-R4 — same-day multi-redeemer claim-order race draining one shared carry at claim** | MEDIUM | **HANDLED** by the submit-time carry removal (each redeemer's slice is segregated at its own submit; no claim-order contention). (§4.2) |
| **L5-R1 — slot-0 packing claim for `_pendingBurnieEscrow` is FALSE; risk of an implementer reordering slot 0 and breaking slot-hardcoded harnesses** | LOW | **HANDLED** in spec: new dedicated slot mandated; slot-0 reorder explicitly forbidden; re-`forge inspect` required. (§5) |
| **L5-R2 — per-winning-box settle work relocated into the `claimRedemptionMany` per-N loop raises per-tx gas, shrinks safe N** | LOW | **HANDLED.** Quantify worst-case and document safe N (v56 dual-bound); keep owned-portion atomic-at-submit; reject the full-share-escrow variant. Off the 16.7M advanceGame chain → not game-bricking. (§5) |
| **L5-R3 — `_settleToCurrent` walk up to `COIN_CLAIM_DAYS=365` on a stalled-advance gap** | LOW | **HANDLED.** Bounded (365 hard cap); folded into the submit worst-case gas derivation. Off the advanceGame chain. (§4.4, §5) |
| **L3 ETH-spine axis — no BURNIE term in `distributeYieldSurplus` obligations / `handleGameOverDrain`** | (raised sound) | **PRESERVED.** Carry stays pure BURNIE; no term added to `JackpotModule.sol:688-700` or `GameOverModule.sol:150-153`. (§2) |

---

## 7. Test plan for the eventual fix

Reproduce against the green baseline `test/REGRESSION-BASELINE-v63.md` (any new failing test **name** is a regression; raw red count is not). Build the suite to prove each lens.

**Conservation / over-credit (L1):**
- `test_RedeemableBurnieDisjoint_AfterMultiDayStall`: advance `> COIN_CLAIM_DAYS` with RNG stalls so `flipsClaimableDay - lastClaim > windowDays`, then assert `redeemableBurnieSettled` returns `owned + carry` with `_viewClaimableCoin(SDGNRS) == 0` (settled to current) and that no win day is counted twice.
- `test_MultiRedeemerSameDay_SumWithinCarry`: two redeemers on the same day `D` on a winning `D+1` sequence; assert `Σ paid <= owned + carry` and `Σ burnieEscrow == _pendingBurnieEscrow <= autoRebuyCarry` at every step.
- Invariant (fuzz): `Σ over (player,day) burnieEscrow == _pendingBurnieEscrow` and `_pendingBurnieEscrow <= autoRebuyCarry(SDGNRS)` between submit and resolve, across arbitrary win/loss day sequences.

**Double-claim / strand (L2):**
- `test_ZeroEthClaim_PaysEscrow`: state where `ethValueOwed` gwei-floors to 0 but `carryPortion > 0`; assert the claim is reachable, escrow resolves, reserve released.
- `test_ContingencyRidesDayPlus1`: submit on `D` (a known win); make `D+1` a loss; assert `burniePaid == 0` and reserve released — and that no held/claimable backing of other holders is touched (no over-pay, no brick of the ETH leg).
- `test_DayPlus1Win_PaysExactEscrow`: `D+1` win → `burniePaid == carryPortion` snapshot, deferred-minted to redeemer; sDGNRS net BURNIE conserved across submit+resolve.

**Solvency / freeze (L3):**
- `test_NoEthObligationTerm`: assert `distributeYieldSurplus` obligations and `handleGameOverDrain` reserved amount are byte-identical with and without outstanding escrow (no ETH-spine leak).
- `test_LossZeroesCarry_NoUnderflow`: submit, then a losing interim day zeroes live carry; assert `previewBurn`/`burnieReserve` (saturating subtraction) do not revert and other holders' previews remain readable.
- `test_NoGrind_DayPlus1WordUnknownAtSubmit`: assert `rngWordForDay(D+1) == 0` at submit time (the contingency word is not yet drawn).

**Timing / race / reentrancy (L4):**
- `test_NoClaimTimeCarryRead`: assert the win-path performs no `autoRebuyCarry` read/mutation at claim (only at submit); carry consumed only inside the `rngLocked`-gated submit window.
- `test_SameDayNoClaimOrderRace`: two same-day winners; assert claim order does not change either payout and neither bricks.

**GameOver (L4-R5 / Q4 — pending decision):**
- `test_PendingEscrow_ZeroedAtGameOver`: pre-gameOver escrow, latch gameOver; assert `_pendingBurnieEscrow == 0` immediately after `handleGameOverDrain`, `burniePaid == 0`, ETH leg (self-claim) returns cleanly, no revert.

**Gas / EIP-170 (L5):**
- `test_StorageLayout_NewScalarOwnSlot`: `forge inspect` asserts `_pendingBurnieEscrow` is on a fresh slot and slot-0 fields are unmoved.
- `test_ClaimManyWorstCaseGas`: worst-case per-winning-box gas (leaderboard write, cold release, 365-day submit settle in a sibling test) → document safe `N` (<10M target, never >16.7M).
- Deployed-size assertions for BurnieCoinflip and StakedDegenerusStonk remain well under 24,576.

---

## 8. OPEN QUESTIONS FOR USER

1. **Owned-vs-carry split granularity.** This design settles the **owned** portion atomically at submit (non-contingent, as today) and makes **only the carry** portion flip-contingent. The USER phrasing — *"if it wins, the redeemer gets their share and it is DEDUCTED from the carry (or from the balance if there is one)"* — could instead mean the **entire** share (owned + carry) is contingent and drawn carry-first. If so, escrow the full `burnieOwed` and remove the atomic settle at submit, paying the full slice only on a `D+1` win. **Default in this spec: owned atomic, carry contingent (lower gas, owned is always-realizable). Confirm.**

2. **Contingency coin = day `D+1`.** This spec binds the carry slice to **day `D+1`'s** coinflip (the flip the carry actually rides; unknown at submit). The originally-routed "ride the redeemed day `D`'s result" is rejected as grindable and double-applying. **Confirm `D+1` is the intended "next coinflip."** (If a *fresh independent* flip is intended instead, the resolution rail and the unknown-at-submit proof change — flag if so.)

3. **Reserve subtraction scope.** `_pendingBurnieEscrow` is subtracted (saturating) from the BURNIE base in `previewBurn`/`burnieReserve`, mirroring `pendingRedemptionEthValue` on the ETH side, to prevent re-promising carry. **Confirm there is no intended over-collateralization where multiple redeemers SHOULD share contingent claims on the same carry** (this spec assumes single-counting, like the ETH side).

4. **GameOver stranding (must be decided — not left open in the eventual implementation).** An escrow submitted pre-gameOver but unresolved when `handleGameOverDrain` latches (`GameOverModule.sol:135`) and tombstones BURNIE (`:143`) is unpayable in worthless BURNIE, and `coinflipDayWon(D+1)` may never resolve. Options: **(a)** resolve all outstanding escrow as **loss** at the gameOver latch (zero `burnieEscrow`, release `_pendingBurnieEscrow`) — symmetric with carry evaporating and with the loss branch; **(b)** extend `BurnsBlockedDuringLiveness` to also block new submits once any escrow is outstanding (it already blocks new submits in the liveness window, so this only force-resolves already-recorded escrow); **(c)** resolve-as-win at the latch (pays worthless tombstoned BURNIE — not recommended). **Spec recommendation: (a), with the contingency leg guarded on `!isGameOver`. Confirm.**

5. **Recycle-bonus interaction.** sDGNRS carry compounds +0.75%/win (`BurnieCoinflip.sol:505`, `_recyclingBonus :1138-1142`). Because the slice is removed from carry at submit, post-submit recycle growth accrues to **remaining holders, not the pending redeemer** (the redeemer gets exactly the slice removed at submit, paid on the `D+1` outcome). **Confirm the redeemer is NOT entitled to recycle growth between submit and resolve.**