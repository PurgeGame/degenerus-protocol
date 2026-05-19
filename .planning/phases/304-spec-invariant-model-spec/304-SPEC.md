# Phase 304 — sStonk Per-Day Redemption Refactor: SPEC + Invariant Model

## §0 — Header

- **Milestone:** v44.0 sStonk Per-Day Redemption Refactor + Accounting Invariant Proof
- **Phase:** 304 — SPEC + Invariant Model (SPEC)
- **Baseline:** `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
- **Load-bearing inputs:**
  - `audit/FINDINGS-v43.0.md` §9d HANDOFF-111..117 (the 7 sStonk anchors closed by v44.0)
  - `.planning/RNGLOCK-FIXREC.md` §103 (V-184 mechanic — catastrophic cross-day re-roll)
  - `.planning/REQUIREMENTS.md` v44.0 block (canonical INV-01..12, SPEC-01..05, EDGE-01..18, IMPL-01..04)
- **Downstream consumer:** Phase 305 IMPL — single batched USER-APPROVED diff against `contracts/StakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` (+ optional `IDegenerusGamePlayer` minimum delta). Every locked decision in §1–§4 of this SPEC is a load-bearing input for that diff per `feedback_batch_contract_approval.md` and `feedback_never_preapprove_contracts.md`.
- **Posture:** pre-launch, frozen-at-deploy per `feedback_frozen_contracts_no_future_proofing.md`. Storage layout breaks are ACCEPTED; redeploy-fresh; no migration prose appears anywhere in this SPEC; no future-extensibility speculation appears anywhere in this SPEC.
- **Comment policy:** per `feedback_no_history_in_comments.md`, §1/§2/§3/§5 prose describes the POST-REFACTOR state — what IS — and never narrates "what changed" or "what it used to be." Pre-refactor narrative appears ONLY in §4 design-intent walk under explicit `ORIGINAL DESIGN INTENT` subheadings; nowhere else.

### §0 — Requirement Traceability

> At-a-glance map a Phase 306 TST author uses to locate the SPEC text for any requirement ID. Every requirement maps to a primary SPEC section. INV-NN are doc'd at §1; SPEC-NN are locked at §2; EDGE-NN are enumerated at §3.

| Requirement | Section | Status |
|-------------|---------|--------|
| INV-01 | §1 | Filled by Plan 01 |
| INV-02 | §1 | Filled by Plan 01 |
| INV-03 | §1 | Filled by Plan 01 |
| INV-04 | §1 | Filled by Plan 01 |
| INV-05 | §1 | Filled by Plan 01 |
| INV-06 | §1 | Filled by Plan 01 |
| INV-07 | §1 | Filled by Plan 01 |
| INV-08 | §1 | Filled by Plan 01 |
| INV-09 | §1 | Filled by Plan 01 |
| INV-10 | §1 | Filled by Plan 01 |
| INV-11 | §1 | Filled by Plan 01 |
| INV-12 | §1 | Filled by Plan 01 |
| SPEC-01 | §2 | Filled by Plan 02 |
| SPEC-02 | §2 | Filled by Plan 02 |
| SPEC-03 | §2 | Filled by Plan 02 |
| SPEC-04 | §2 | Filled by Plan 02 |
| SPEC-05 | §2 | Filled by Plan 02 |
| EDGE-01 | §3 | Filled by Plan 03 |
| EDGE-02 | §3 | Filled by Plan 03 |
| EDGE-03 | §3 | Filled by Plan 03 |
| EDGE-04 | §3 | Filled by Plan 03 |
| EDGE-05 | §3 | Filled by Plan 03 |
| EDGE-06 | §3 | Filled by Plan 03 |
| EDGE-07 | §3 | Filled by Plan 03 |
| EDGE-08 | §3 | Filled by Plan 03 |
| EDGE-09 | §3 | Filled by Plan 03 |
| EDGE-10 | §3 | Filled by Plan 03 |
| EDGE-11 | §3 | Filled by Plan 03 |
| EDGE-12 | §3 | Filled by Plan 03 |
| EDGE-13 | §3 | Filled by Plan 03 |
| EDGE-14 | §3 | Filled by Plan 03 |
| EDGE-15 | §3 | Filled by Plan 03 |
| EDGE-16 | §3 | Filled by Plan 03 |
| EDGE-17 | §3 | Filled by Plan 03 |
| EDGE-18 | §3 | Filled by Plan 03 |

## §1 — Invariant Model (INV-01..12)

> The 12 formal accounting properties the post-refactor `contracts/StakedDegenerusStonk.sol` must satisfy under every reachable state. Each INV-NN restates the canonical `REQUIREMENTS.md` lines 26-37 wording as a precise property + names the storage variables it constrains + enumerates the state transitions across which it must hold + maps to the Foundry test that proves it.
>
> **Action set referenced by every "State transitions" field below:**
> - `burn` — `burn(uint256)` / `burnWrapped(uint256)` → `_submitGamblingClaimFrom(beneficiary, amount, ethValueOwed, burnieOwed)`; the gambling-redemption entry path
> - `advanceGame` — `DegenerusGameAdvanceModule._advanceGame` → `StakedDegenerusStonk.resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)`; the per-day resolve writer
> - `claimRedemption(uint32 day)` — player-side payout entry; reads `pendingRedemptions[msg.sender][day]` + `redemptionPeriods[day]`, calls `_payEth` / `_payBurnie`, deletes the composite-keyed claim
> - `gameOver-latch` — the state transition where `DegenerusGame.gameOver` becomes true
> - `transfer` / `approve` — ERC20 surface; never touches redemption storage but listed for invariant-completeness
> - `admin-action` — owner-gated paths (pause, fee setters, etc.); never touches redemption-state per SPEC posture
>
> **Storage variable set referenced by every "Storage variables involved" field below** (post-refactor; SPEC-01..03 lock the final shape — forward-referenced and resolved when Plan 02 fills §2):
> - `pendingByDay[uint32 day]` — per-day `DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` (3 slots per active day)
> - `pendingRedemptions[address player][uint32 day]` — composite-keyed `PendingRedemption { uint96 ethValueOwed; uint96 burnieOwed; uint16 activityScore; }` (1 slot per (player, day) claim)
> - `redemptionPeriods[uint32 day]` — `RedemptionPeriod { uint16 roll; uint32 flipDay; }` (1 slot per resolved day)
> - `pendingRedemptionEthValue` (public uint256) — global cumulative ETH segregated across ALL days, resolved and unresolved
> - `pendingRedemptionBurnie` (internal uint256) — global cumulative BURNIE reserved across ALL days, resolved and unresolved
> - `MAX_DAILY_REDEMPTION_EV` (private constant uint256 = 160 ether) — the per-(player, day) EV cap from INV-11

### INV-01: Write-once roll immutability

**Formal property:** For every day `D` such that `redemptionPeriods[D].roll != 0`, the value of `redemptionPeriods[D].roll` (and the paired `redemptionPeriods[D].flipDay`) is byte-identical at every reachable state after the first write. Formally: let `T_first(D)` denote the block at which `resolveRedemptionPeriod(roll, flipDay, dayToResolve=D)` first writes `redemptionPeriods[D]`; then for all `t >= T_first(D)` and all action sequences executed in `[T_first(D), t]`, `redemptionPeriods[D].roll` and `redemptionPeriods[D].flipDay` at block `t` equal the values written at `T_first(D)`. This is the formal statement of the V-184 closure: no `(burn, advance, claim, gameOver, transfer, approve, admin-action)` interleaving can overwrite an already-resolved day.

**Storage variables involved:** `redemptionPeriods[D].roll`, `redemptionPeriods[D].flipDay`.

**State transitions across which the property must hold:** Every reachable transition once `redemptionPeriods[D].roll != 0` has been written — i.e. every subsequent `burn`, `advanceGame`, `claimRedemption`, `gameOver-latch`, `transfer`, `approve`, `admin-action`. The structural enforcement vector is the per-day key in `resolveRedemptionPeriod(uint32 dayToResolve)`: a second `advanceGame` for day `D+1` writes `redemptionPeriods[D+1]`, not `redemptionPeriods[D]`, so the single-pool overwrite mechanic that V-184 exploited is eliminated by construction.

**Test mapping:** `invariant_INV_01_RollWriteOnce()` in `test/invariant/RedemptionAccounting.t.sol` — storage-write hook on `redemptionPeriods[D]` records first-write value; invariant asserts byte-identity at every handler call. EDGE-07 (V-184 attack reproduction) at `test/fuzz/RedemptionEdgeCases.t.sol::testFuzz_VictimDayRollNotOverwritten` is the dedicated negative-path reproduction.

---

### INV-02: ETH conservation (dust-bounded)

**Formal property:** At every reachable state, the contract's ETH-equivalent assets equal the cumulative ETH segregated for pending claims plus the cumulative ETH paid out plus dust accumulated from integer-division floors. Formally:

```
address(this).balance
  + steth.balanceOf(address(this))
  + claimableWinnings(address(this))
== pendingRedemptionEthValue
  + (cumulative ETH paid out via claimRedemption since deploy)
  + (cumulative non-gambling burns since deploy)
  + dust(D-set)
```

where `dust(D-set)` is the per-resolved-day floor-division remainder accumulated across all resolved days. Per `:592` analog `uint256 rolledEth = (pendingByDay[D].ethBase * roll) / 100`, each resolved day produces at most `99` wei of floor-division dust (the remainder of an integer division by `100` is in `[0, 99]`), so the per-period dust is bounded by `99` wei and the cumulative dust across `N` resolved days is bounded by `99 * N` wei. This bound is the load-bearing assertion: total ETH never leaves the contract uncounted, total ETH never appears from nothing, the only slippage is sub-wei rounding from the `(ethBase * roll) / 100` floor.

**Storage variables involved:** `pendingRedemptionEthValue`, `pendingByDay[D].ethBase` (for each unresolved D), `pendingRedemptions[P][D].ethValueOwed` (the cumulative-sum sources), the external `address(this).balance` + `steth.balanceOf(address(this))` + `claimableWinnings(address(this))` (the on-chain asset side).

**State transitions across which the property must hold:** Every reachable transition. Specifically:
- `burn` increments `pendingRedemptionEthValue` by `ethValueOwed` and credits `pendingByDay[D].ethBase` (asset side ETH unchanged, claim side grows by `ethValueOwed`).
- `advanceGame` → `resolveRedemptionPeriod(D)` rewrites `pendingRedemptionEthValue` from `+= -pendingByDay[D].ethBase + (pendingByDay[D].ethBase * roll) / 100` (per-period dust released as the floor-division residue).
- `claimRedemption(D)` decrements `pendingRedemptionEthValue` by the player's resolved ETH share AND decrements `address(this).balance` (or stETH equivalent) by the same amount (asset side and claim side decrement together).
- `gameOver-latch`, `transfer`, `approve`, `admin-action` do NOT touch any of the storage variables involved, so the property is trivially preserved.

**Test mapping:** `invariant_INV_02_EthConservation()` in `test/invariant/RedemptionAccounting.t.sol` — asserts the equation modulo dust after every handler action across `{burn, advance, claim, gameOver, transfer, approve, admin-action}` random sequences. Dust tolerance per resolved day is the implementation literal `99 wei` derived from the `% 100` floor-division residue.

---

### INV-03: BURNIE conservation (resolve-time release)

**Formal property:** At every reachable state:

```
coin.balanceOf(address(this))
  + coinflip.previewClaimCoinflips(address(this))
  - pendingRedemptionBurnie
== BURNIE available for new burns
```

i.e. the BURNIE reserved across all pending days equals the difference between the on-chain BURNIE balance (direct + coinflip-claimable) and the BURNIE freely usable for new burns. The key timing semantics: BURNIE reservation is RELEASED AT RESOLVE — `resolveRedemptionPeriod(D)` decrements `pendingRedemptionBurnie` by the unrolled `pendingByDay[D].burnieBase` and re-adds the rolled portion via the same `(base * roll) / 100` floor. Reservation is NOT released at claim (the on-chain payment via `_payBurnie` happens at claim, but the `pendingRedemptionBurnie` accumulator is already net-of-roll by then per existing `:600` semantics).

**Storage variables involved:** `pendingRedemptionBurnie`, `pendingByDay[D].burnieBase` (for each unresolved D), `pendingRedemptions[P][D].burnieOwed`, the external `coin.balanceOf(address(this))` + `coinflip.previewClaimCoinflips(address(this))`.

**State transitions across which the property must hold:** Every reachable transition. Specifically:
- `burn` increments `pendingRedemptionBurnie` by `burnieOwed` AND credits `pendingByDay[D].burnieBase`.
- `advanceGame` → `resolveRedemptionPeriod(D)` decrements `pendingRedemptionBurnie` by `pendingByDay[D].burnieBase` and the rolled portion `(pendingByDay[D].burnieBase * roll) / 100` is what's reflected by the per-(player, day) `pendingRedemptions[P][D].burnieOwed * roll / 100` at claim time. Note: existing v43 semantics at `:600` releases the full unrolled `pendingRedemptionBurnieBase` at resolve, so the post-refactor `pendingRedemptionBurnie` after resolve no longer carries day-D's reservation; the actual BURNIE payment happens later at claim from already-net BURNIE inventory.
- `claimRedemption(D)` calls `_payBurnie` which decrements on-chain BURNIE balance by the player's `pendingRedemptions[P][D].burnieOwed * roll / 100`; `pendingRedemptionBurnie` is NOT decremented at claim (already netted at resolve).
- `gameOver-latch`, `transfer`, `approve`, `admin-action` do NOT touch any of the storage variables involved.

**Test mapping:** `invariant_INV_03_BurnieConservation()` in `test/invariant/RedemptionAccounting.t.sol` — asserts the equation after every handler action; pairs with EDGE-18 (`test/fuzz/RedemptionEdgeCases.t.sol::testFuzz_BurnieFallbackOnDrainedCoinflip`) for the BURNIE-pool-insufficient path.

---

### INV-04: Per-day base correctness (unresolved-day pre-condition)

**Formal property:** For every day `D` such that `pendingByDay[D].ethBase != 0` AND `redemptionPeriods[D].roll == 0` (i.e. day `D` has been burned-into but not yet resolved):

```
pendingByDay[D].ethBase == sum over all players P of pendingRedemptions[P][D].ethValueOwed
```

Symmetric assertion for BURNIE: `pendingByDay[D].burnieBase == sum over all P of pendingRedemptions[P][D].burnieOwed`. This is the per-day local-correctness check: the pool-side aggregator equals the sum of all per-player credits on that day. Once `redemptionPeriods[D].roll != 0` (post-resolve), the invariant predicate's pre-condition is false, so this INV does not constrain resolved days; INV-05 carries the cumulative correctness across the resolved/unresolved boundary.

**Storage variables involved:** `pendingByDay[D].ethBase`, `pendingByDay[D].burnieBase`, `pendingRedemptions[*][D].ethValueOwed`, `pendingRedemptions[*][D].burnieOwed`, `redemptionPeriods[D].roll` (the predicate gate).

**State transitions across which the property must hold:** Every reachable transition where the pre-condition `redemptionPeriods[D].roll == 0 AND pendingByDay[D].ethBase != 0` is true. Specifically:
- `burn` on day `D` (when `currentDayView() == D`) increments both sides by the same `(ethValueOwed, burnieOwed)` tuple — sum on the right grows by exactly the same amount the aggregator on the left grows.
- `advanceGame` for day `D+1` triggers `resolveRedemptionPeriod(dayToResolve=D)`, which transitions `redemptionPeriods[D].roll` from `0` to non-zero; after that block the pre-condition is false and INV-04 no longer constrains day `D` (INV-05 takes over).
- `claimRedemption(D)` can only succeed when `redemptionPeriods[D].roll != 0` (existing `NotResolved` revert preserved per SPEC-02), so it never executes while INV-04's pre-condition holds; the property is therefore trivially preserved across `claimRedemption` calls that target days `!= D`.
- `gameOver-latch`, `transfer`, `approve`, `admin-action` do not modify the involved variables.

**Test mapping:** `invariant_INV_04_PerDayBaseCorrectness()` in `test/invariant/RedemptionAccounting.t.sol` — for every day `D` in the handler's emitted action history, if `redemptionPeriods[D].roll == 0` and `pendingByDay[D].ethBase != 0`, assert the sum equality. EDGE-04 (`testFuzz_MultiPlayerSameDay`) is the dedicated multi-player same-day positive coverage.

---

### INV-05: Per-day cumulative correctness (mixed resolved + unresolved)

**Formal property:** At every reachable state, the global cumulative scalar equals the sum of unresolved-day pool bases plus the sum over resolved-but-unclaimed days of the per-player rolled credits:

```
pendingRedemptionEthValue
==   (sum over unresolved D of pendingByDay[D].ethBase)
   + (sum over resolved-but-unclaimed D of
        sum over unclaimed players P of
          floor(pendingRedemptions[P][D].ethValueOwed * redemptionPeriods[D].roll / 100))
```

(symmetric assertion for `pendingRedemptionBurnie` — but see INV-03 timing-semantics note: BURNIE is netted at resolve, so the equivalent equation for `pendingRedemptionBurnie` does not include the resolved-but-unclaimed term and instead asserts `pendingRedemptionBurnie == sum over unresolved D of pendingByDay[D].burnieBase`). This INV-05 carries the cumulative correctness across the resolved/unresolved boundary that INV-04 cannot cover. The unresolved term shrinks to zero as days are resolved; the resolved-but-unclaimed term grows as resolution happens then shrinks as players claim.

**Storage variables involved:** `pendingRedemptionEthValue`, `pendingByDay[D].ethBase` (for unresolved D), `pendingRedemptions[P][D].ethValueOwed`, `redemptionPeriods[D].roll`.

**State transitions across which the property must hold:** Every reachable transition. Specifically:
- `burn` on day `D` increments `pendingRedemptionEthValue` by `ethValueOwed` AND `pendingByDay[D].ethBase` by the same amount (the unresolved-term sum side grows by the same amount as the LHS).
- `advanceGame` → `resolveRedemptionPeriod(D)` does the floor-division re-write: LHS is set to `LHS - pendingByDay[D].ethBase + (pendingByDay[D].ethBase * roll) / 100`; on the RHS, the unresolved term drops `pendingByDay[D].ethBase`; the resolved-but-unclaimed term gains `(pendingByDay[D].ethBase * roll) / 100` modulo per-player floor-division dust (bounded per INV-02). Net: equation re-balances modulo dust.
- `claimRedemption(D)` decrements `pendingRedemptionEthValue` by the player's `pendingRedemptions[P][D].ethValueOwed * roll / 100` AND removes the same amount from the resolved-but-unclaimed term (via `delete pendingRedemptions[P][D]`). Equation re-balances exactly.
- `gameOver-latch`, `transfer`, `approve`, `admin-action` do not modify involved variables.

**Test mapping:** `invariant_INV_05_CumulativeCorrectness()` in `test/invariant/RedemptionAccounting.t.sol` — recomputes both sides of the equation from action history after every handler call. EDGE-02 (`testFuzz_TwoPendingDaysSimultaneously`) is the dedicated coverage for the mixed unresolved-D + accumulating-D+1 scenario.

---

### INV-06: No cross-player roll manipulation

**Formal property:** For any player `P` and day `D` such that `P` has a claim `pendingRedemptions[P][D]`, `redemptionPeriods[D].roll` is a deterministic function of day-D+1's VRF word only — specifically the locked `roll` parameter passed by `DegenerusGameAdvanceModule._advanceGame` to `resolveRedemptionPeriod(roll, flipDay, dayToResolve=D)` derived from VRF word `R_{D+1}`. No action by any non-EXEMPT actor (other player's `burn`, other player's `claim`, `gameOver-latch`, `transfer`, `approve`, owner `admin-action`) occurring between `P`'s `burn(day=D)` and `P`'s `claimRedemption(D)` can alter `redemptionPeriods[D].roll`. Formally: for any action sequence `A` between `P`'s burn at time `T_burn(P,D)` and `P`'s claim at time `T_claim(P,D)`, the value of `redemptionPeriods[D].roll` at `T_claim(P,D)` equals `roll_locked(R_{D+1})` — independent of `A`.

**Storage variables involved:** `redemptionPeriods[D].roll` (the constrained value), `pendingRedemptions[P][D]` (the lifetime delimiter).

**State transitions across which the property must hold:** Every transition in the half-open window `[T_burn(P, D), T_claim(P, D))`. The only EXEMPT writer is `resolveRedemptionPeriod` called by `DegenerusGameAdvanceModule._advanceGame` exactly once for `dayToResolve=D` (the day-D+1 advance), with input `roll` derived from VRF word `R_{D+1}`. INV-01 covers the post-write immutability; INV-06 covers the pre-write phase — i.e. no non-EXEMPT actor can sneak a write to `redemptionPeriods[D].roll` between burn and claim.

**Test mapping:** `invariant_INV_06_NoCrossPlayerRollManipulation()` in `test/invariant/RedemptionAccounting.t.sol` — handler action emitter randomly schedules non-EXEMPT actions between burn and claim across multiple players; asserts the resolved-roll value matches the VRF word recorded at the day-D+1 advance. EDGE-04 (`testFuzz_MultiPlayerSameDayDifferentAdvanceOffsets`) provides multi-player coverage.

---

### INV-07: No self-roll manipulation via timing

**Formal property:** For any player `P` with `pendingRedemptions[P][D].ethValueOwed = X` set at time `T_set`, the value `X` is byte-identical at every later time until `P` calls `claimRedemption(D)`. Formally: for all `t` in `[T_set, T_claim(P, D))`, `pendingRedemptions[P][D].ethValueOwed` at `t` equals `X`. Symmetric for `burnieOwed` and `activityScore`. No action by `P` (self) and no action by any other actor can retroactively modify `P`'s locked per-(player, day) claim values between when they're written (at the burn that creates / accumulates into the claim) and when the player claims. The "via timing" qualifier is the load-bearing distinction: V-184's catastrophic mechanic was that re-bursting on a later day caused the SHARED resolve pool to mutate the claim's effective payout retroactively; per-day keying eliminates that vector by structurally separating per-(player, day) claims from the per-day pool.

**Storage variables involved:** `pendingRedemptions[P][D].ethValueOwed`, `pendingRedemptions[P][D].burnieOwed`, `pendingRedemptions[P][D].activityScore`.

**State transitions across which the property must hold:** Every transition in the half-open window `[T_set, T_claim(P, D))`. Specifically:
- `burn` BY `P` on a DIFFERENT day `D' != D` writes `pendingRedemptions[P][D'].ethValueOwed` — a DIFFERENT storage slot. `pendingRedemptions[P][D]` is untouched. (This is the V-184 closure.)
- `burn` BY `P` on the SAME day `D` (re-burning within the same day before any advance) is the only mutator — it accumulates additively into `pendingRedemptions[P][D].ethValueOwed += newEthValueOwed`. Per SPEC, this same-day accumulation is the intended behavior and not a violation: the `T_set` reference is the LAST same-day burn before day-D+1 advance, not the first. The invariant constrains the window from "the burn that finalizes the per-(player, day) entry" through claim.
- `burn` BY ANOTHER PLAYER `Q != P` on day `D` writes `pendingRedemptions[Q][D]` — DIFFERENT composite key, `pendingRedemptions[P][D]` untouched.
- `advanceGame` → `resolveRedemptionPeriod(D)` writes `redemptionPeriods[D]`, NOT `pendingRedemptions[P][D]`.
- `claimRedemption(D)` is the terminator — at `T_claim(P, D)` the contract deletes `pendingRedemptions[P][D]` (storage refund per SPEC-04 (d)), ending the invariant's enforcement window.
- `gameOver-latch`, `transfer`, `approve`, `admin-action` do not modify `pendingRedemptions[P][D]`.

**Test mapping:** `invariant_INV_07_NoSelfRollManipulation()` in `test/invariant/RedemptionAccounting.t.sol` — handler tracks per-(player, day) ethValueOwed snapshots; asserts byte-identity from finalization through claim. `test/fuzz/StakedStonkRedemption.t.sol::testFuzz_BurnLandsInCurrentDayPool` provides the per-function fuzz reproduction of the cross-day separation.

---

### INV-08: Pre-advance-gap burn safety

**Formal property:** For any burn occurring at time `T` where `game.currentDayView() == D` AND day-D's advance has not yet fired (i.e. `redemptionPeriods[D-1].roll == 0` is irrelevant — the gating predicate is "day-D's advance has not fired yet, even though the wall clock has flipped to day D"), the burn lands in `pendingByDay[D]`, NOT `pendingByDay[D-1]`. Specifically: `_submitGamblingClaimFrom` reads `D = game.currentDayView()` and writes `pendingByDay[D].ethBase += ethValueOwed`. Day-D's eventual advance (which resolves day `D-1`) calls `resolveRedemptionPeriod(dayToResolve=D-1)` and reads `pendingByDay[D-1]` only — it does NOT read or write `pendingByDay[D]`. The cumulative scalar `pendingRedemptionEthValue` correctly reflects BOTH pools simultaneously during the gap.

**Storage variables involved:** `pendingByDay[D].ethBase` (current-day pool, recipient of the gap burn), `pendingByDay[D-1].ethBase` (yesterday's pool, target of the pending advance), `pendingRedemptionEthValue` (cumulative, holds both at once), `game.currentDayView()` (the wall-clock day reader).

**State transitions across which the property must hold:** Every `burn` action occurring in the gap window — wall clock at day `D`, advance for day `D` not yet fired. The critical structural lock is the `dayToResolve` argument: `DegenerusGameAdvanceModule._advanceGame` must pass `dayToResolve = currentDayView() - 1` (or the locked equivalent per SPEC-03) so that the resolve targets yesterday's pool. The SPEC-03 lock makes the gap-burn vs same-day-pool collision physically impossible: the two pools have different keys.

**Test mapping:** `invariant_INV_08_PreAdvanceGapBurnSafety()` in `test/invariant/RedemptionAccounting.t.sol` — handler schedules gap-window burns; asserts (a) `pendingByDay[D-1]` untouched by the gap burn; (b) `pendingByDay[D]` correctly credited; (c) `pendingRedemptionEthValue == pendingByDay[D-1].ethBase + pendingByDay[D].ethBase` post-burn pre-advance. EDGE-01 (`testFuzz_PreAdvanceGapBurnLandsInCurrentDay`) is the dedicated fuzz reproduction.

---

### INV-09: Skipped-advance recovery (oldest-first ordering)

**Formal property:** If advances for days `D+1, D+2, ..., D+k` are skipped (operator stall, gas spike, infrastructure outage, etc.) and eventually fire in sequence, each advance call resolves the next-oldest unresolved day (oldest-first ordering). Formally: when `advanceGame` fires at wall day `W > D+k`, it resolves `dayToResolve = oldest_unresolved_day` — first the resolve targets day `D`, the next subsequent advance targets day `D+1`, etc. No pending day's pool is bypassed; no overwrite occurs; no two advances ever target the same `dayToResolve`. The eventual closure state has all of days `D..D+k-1` resolved with VRF words from advance days `D+1..D+k` respectively (one-day offset preserved).

**Storage variables involved:** `pendingByDay[D'].ethBase` (for each unresolved D' in the backlog), `pendingByDay[D'].burnieBase`, `pendingByDay[D'].supplySnapshot`, `pendingByDay[D'].burned`, `redemptionPeriods[D'].roll` (target of each resolve), `redemptionPeriods[D'].flipDay`.

**State transitions across which the property must hold:** The action sequence `(burn day=D), (skipped advance D+1), (skipped advance D+2), ..., (eventual advance W)`. The structural enforcement vector is `DegenerusGameAdvanceModule._advanceGame` computing `dayToResolve` from the oldest pending day (the locked SPEC-03 derivation — exact computation locked at Plan 02). Per-day keying makes oldest-first ordering trivially expressible: scan `pendingByDay[D']` for the smallest `D'` with `ethBase != 0 && redemptionPeriods[D'].roll == 0`; that's `dayToResolve`. (Alternative: precompute via the AdvanceModule's existing day-counter state — locked at SPEC-03.)

**Test mapping:** `invariant_INV_09_SkippedAdvanceRecovery()` in `test/invariant/RedemptionAccounting.t.sol` — handler emits sequences with random advance-skip distributions; asserts oldest-first resolve ordering and no overwrite of already-resolved days (the latter overlaps INV-01 enforcement). EDGE-06 (`testFuzz_SkippedAdvanceLongStall`) is the dedicated 12h+-stall fuzz reproduction.

---

### INV-10: Per-day supply cap

**Formal property:** For every day `D`, total burned in day `D` never exceeds half the snapshotted supply on first burn of that day. Formally:

```
pendingByDay[D].burned <= pendingByDay[D].supplySnapshot / 2
```

at every reachable state. The snapshot is lazy-initialized: `pendingByDay[D].supplySnapshot = totalSupply` on the first burn of day `D` (i.e. when the slot reads `0`); immutable for the rest of day `D` regardless of subsequent same-day burns and the corresponding `totalSupply` decreases. Per SPEC-05, the cap is enforced against the snapshot, not against the post-burn `totalSupply`, so a flurry of same-day burns can drive `totalSupply` below `supplySnapshot / 2` legitimately as long as the cumulative `pendingByDay[D].burned` itself stays within the snapshot-derived budget.

**Storage variables involved:** `pendingByDay[D].supplySnapshot`, `pendingByDay[D].burned`. Also reads `totalSupply` (ERC20 state) for the lazy-init.

**State transitions across which the property must hold:** Every `burn` action targeting day `D`. The structural enforcement vector is the existing `:763` check rewritten as `if (pendingByDay[D].burned + amount > pendingByDay[D].supplySnapshot / 2) revert Insufficient();`. After the snapshot is taken (`pendingByDay[D].supplySnapshot != 0`), it does NOT update on subsequent same-day burns — per SPEC-05 immutability lock. `advanceGame` for day `D+1` calls `resolveRedemptionPeriod(D)` which `delete`s `pendingByDay[D]` per SPEC-04 (c); after that the invariant pre-condition (`pendingByDay[D].supplySnapshot != 0`) is false and the property no longer constrains day `D` (it has been settled into `redemptionPeriods[D]`).

**Test mapping:** `invariant_INV_10_PerDaySupplyCap()` in `test/invariant/RedemptionAccounting.t.sol` — asserts the inequality after every handler `burn` action. EDGE-14 (`testFuzz_SupplyCapEdge`) covers the exact-cap-succeeds + one-wei-over-reverts boundary.

---

### INV-11: Per-(player, day) EV cap

**Formal property:** For every (player `P`, day `D`):

```
pendingRedemptions[P][D].ethValueOwed <= MAX_DAILY_REDEMPTION_EV  // 160 ether
```

at every reachable state. The constant `MAX_DAILY_REDEMPTION_EV = 160 ether` (private uint256 at contract `:254` baseline) is unchanged post-refactor. The cap RESETS per new day: when player `P` burns on day `D+1`, the cap is checked against `pendingRedemptions[P][D+1].ethValueOwed` (a separate composite-key slot from `pendingRedemptions[P][D]`), so a player can legitimately accumulate up to 160 ETH of pending claim PER DAY without violation.

**Storage variables involved:** `pendingRedemptions[P][D].ethValueOwed`, the constant `MAX_DAILY_REDEMPTION_EV`.

**State transitions across which the property must hold:** Every `burn` action by `P` targeting day `D`. The structural enforcement vector is the existing `:800` check rewritten against the composite-key claim: `if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();` where `claim = pendingRedemptions[beneficiary][currentDayView()]`. `claimRedemption(D)` decrements (via `delete pendingRedemptions[P][D]`) without violating the cap (zero <= 160 ether trivially). `advanceGame`, `gameOver-latch`, `transfer`, `approve`, `admin-action` do not modify `pendingRedemptions[P][D].ethValueOwed`.

**Test mapping:** `invariant_INV_11_PerPlayerPerDayEvCap()` in `test/invariant/RedemptionAccounting.t.sol` — asserts the inequality after every handler `burn` action. EDGE-15 (`testFuzz_EvCapEdge`) covers exact-160-succeeds + one-wei-over-reverts; EDGE-16 (`testFuzz_CrossDayCapReset`) covers the per-day reset.

---

### INV-12: gameOver mid-pending safety

**Formal property:** If `game.gameOver` latches to `true` while `pendingByDay[D].ethBase != 0` for some day `D` (i.e. burns exist for day `D` but day-D+1's advance has not yet resolved them), the eventual `resolveRedemptionPeriod(D)` + `claimRedemption(D)` flow either (a) completes correctly — `claimRedemption(D)` reads the stored `redemptionPeriods[D].roll`, payouts proceed via `_payEth` / `_payBurnie` exactly as in the non-gameOver path — OR (b) reverts cleanly with no partial state, no stuck funds, no double-payment.

The binding decision between (a) and (b) is locked at SPEC-04 (a) "gameOver path interaction." Forward-reference to §2 Plan 02: §2 SPEC-04 (a) resolves whether the post-gameOver advance fires `resolveRedemptionPeriod` for pre-gameOver pending days. Two candidate semantics are on the table at SPEC time, and Plan 02 selects exactly one:

- **Semantic (a) — gracefully-resolve:** post-gameOver `advanceGame` continues to fire `resolveRedemptionPeriod` for pre-gameOver pending days; players can still claim. Cleanest for pre-gameOver burners. Adds gameOver-window complexity to `_advanceGame` if its gameOver guard is otherwise short-circuiting.
- **Semantic (b) — fail-closed:** post-gameOver `advanceGame` skips redemption resolution; `claimRedemption(D)` reverts with a clean error (e.g. `GameOverPreResolve`) for any day that never got resolved. Burners on pre-gameOver days who weren't yet resolved take a known loss.

Whichever semantic Plan 02 locks at SPEC-04 (a), the INV-12 binding is that it is EXACTLY ONE of (a) or (b) — never both, never partial. The Phase 306 test author mechanizes `invariant_INV_12_GameOverMidPending()` against the locked semantic with no ambiguity.

**Storage variables involved:** `pendingByDay[D].ethBase`, `pendingByDay[D].burnieBase`, `pendingRedemptions[P][D].ethValueOwed`, `pendingRedemptions[P][D].burnieOwed`, `redemptionPeriods[D].roll`, `pendingRedemptionEthValue`, `pendingRedemptionBurnie`, plus the external `game.gameOver()` predicate.

**State transitions across which the property must hold:** The action sequence `(burn day=D), (gameOver-latch at time T_GO where T_GO < T_advance(D+1)), (post-gameOver advanceGame or no advance), (claimRedemption(D) by P)`. Whether the advance fires post-gameOver depends on SPEC-04 (a). The claim must EITHER succeed cleanly (semantic a) OR revert cleanly (semantic b) — no third option (partial state, stuck funds, double-payment) is allowed by this invariant.

**Test mapping:** `invariant_INV_12_GameOverMidPending()` in `test/invariant/RedemptionAccounting.t.sol` — handler emits `gameOver` action at random points in the random sequence; asserts the SPEC-04 (a)-locked semantic holds. EDGE-08 (`testFuzz_BurnThenGameOverThenClaim`) is the dedicated positive + negative reproduction; the test branches on the SPEC-04 (a) lock and asserts the correct outcome per locked semantic.

## §2 — Locked Design Decisions (SPEC-01..05)

> The five locks below are the contract between Phase 304 SPEC and Phase 305 IMPL. The IMPL plan-phase writes the diff against these locks verbatim. Every lock is stated declaratively (what IS post-refactor) — pre-refactor narrative is reserved for §4 design-intent walk per `feedback_no_history_in_comments.md`. SPEC-04 contains the 4 lettered sub-locks (a–d) that `REQUIREMENTS.md` flagged "to lock at SPEC phase" — this plan IS where they lock; Phase 305 has no further authority to revisit them.

### §2.0 — Priority Statement (security-first; gas-efficient within)

1. **Hard floor (non-negotiable):** Complete RNG non-manipulability. Per-day per-player keyed redemption state — `pendingByDay[day]`, `pendingRedemptions[player][day]`, and `redemptionPeriods[day]` — is LOAD-BEARING. Three canonical security properties produced by this SPEC:
    - INV-01 — write-once roll immutability per day (no action sequence rewrites a resolved `redemptionPeriods[D].roll`).
    - INV-06 — no cross-player roll manipulation between burn and claim (the roll a player resolves at is a deterministic function of day-D+1's VRF word only).
    - INV-07 — no self-roll manipulation via timing (a player cannot retroactively mutate their own locked `pendingRedemptions[P][D].ethValueOwed` via later-day burns or any other action).

    No optimization, packing, slot-reuse, or shortcut may collapse the `(player, day)` key space or alias rolls across days. The V-184 catastrophe class enumerated in `.planning/RNGLOCK-FIXREC.md` §103 (cross-day re-roll via shared `redemptionPeriodIndex`) is closed STRUCTURALLY at v44.0 — not by gating, not by an ordering check, but by absence of the overwrite primitive: every day's resolve writes a distinct mapping slot, and the storage shape itself precludes the re-roll vector.

2. **Soft target (within the floor):** Within the keying floor, gas is minimized. The IMPL phase pursues four lever classes: (a) struct packing where the type system permits — SPEC-01 packs `supplySnapshot + burned` into one slot via `uint128 + uint128`, achieving 3 slots per active day instead of 4; (b) `delete` on resolution and on claim for storage refunds — SPEC-04 (c) for the day-keyed pool, SPEC-04 (d) for the player-day claim; (c) lazy-init on first write to avoid wasted SSTOREs that initialize to defaults — SPEC-05 snapshot timing initializes only when the slot reads zero on the first burn of the day; (d) skip the resolve writer entirely on no-pending days via the existing `hasPendingRedemptions(day)` gating query, now taking an explicit day arg (SPEC-03 secondary lock). The TST-06 gas regression target — `≤+5%` on the burn path, `≤+0%` on the claim path — is the SOFT target the IMPL phase chases; it is aspirational, not a hard contract, and may shift downward at Phase 306 if the bench reveals a tighter equilibrium.

3. **Conflict resolution:** Any gas optimization that weakens an INV-01..12 property, or that requires the §4 design-intent walk to re-accept a design Plan 04 explicitly rejects, is REJECTED — regardless of the magnitude of gas savings. Rejected optimizations are documented at Plan 04 §4 under "Considered + Rejected" subsections so Phase 305 IMPL can see the reasoning trail and not re-litigate them. The reverse direction is symmetric: if an INV property requires `+X%` gas to enforce correctly, the gas cost is ACCEPTED unconditionally and the TST-06 targets revise downward at Phase 306 — correctness sets the floor, gas targets follow. This ordering is load-bearing for the Phase 305 IMPL trade-off decisions per the user-stated priority that this is real-money crypto with adversarial actors assumed.

### SPEC-01: DayPending struct shape — per-day pool keyed by uint32 day

**Lock:** `struct DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` declared inside the `StakedDegenerusStonk` contract scope. `mapping(uint32 => DayPending) internal pendingByDay`. Exactly 3 storage slots per active day: slot 1 holds `ethBase` (uint256); slot 2 holds `burnieBase` (uint256); slot 3 packs `supplySnapshot` (uint128) and `burned` (uint128). The `uint128` headroom is comfortable: total sDGNRS supply is bounded by the 1e30-wei initial supply (`INITIAL_SUPPLY = 1_000_000_000_000 * 1e18 ≈ 1e30`), well below `uint128.max ≈ 3.4e38`.

**Rationale:** The single-pool indirection through `redemptionPeriodIndex` that V-184 (RNGLOCK-FIXREC §103) exploited no longer exists. Each day's pool is independently mapped by `uint32 day` so no day's pool can be overwritten by writes targeted at another day. The struct shape is chosen for slot economy under the SPEC-04 (c) delete-at-resolve refund pattern — 3 slots refunded per resolved day (one per slot written) is the upper bound the IMPL phase optimizes against.

**Impact on storage layout:** Subsumes 5 pre-refactor slots into one day-keyed mapping: `pendingRedemptionEthBase` (`StakedDegenerusStonk.sol:226`), `pendingRedemptionBurnieBase` (`:227`), `redemptionPeriodSupplySnapshot` (`:229`), `redemptionPeriodIndex` (`:230`), `redemptionPeriodBurned` (`:231`). The two cumulative scalars `pendingRedemptionEthValue` (`:224` public) and `pendingRedemptionBurnie` (`:225` internal) are UNCHANGED.

**Impact on call sites:** `_submitGamblingClaimFrom` writes `pendingByDay[currentDay].ethBase += ethValueOwed`, `pendingByDay[currentDay].burnieBase += burnieOwed`, `pendingByDay[currentDay].burned += amount` (in place of the pre-refactor `pendingRedemptionEthBase`/`pendingRedemptionBurnieBase`/`redemptionPeriodBurned` writes). `resolveRedemptionPeriod` reads `pendingByDay[dayToResolve].ethBase` + `.burnieBase` for the per-day rolled amounts. `claimRedemption(day)` does not touch `pendingByDay` (player-keyed reads only).

**Resolves §1 forward-reference:** Names the post-refactor storage shape referenced by every §1 INV's "Storage variables involved" field — specifically the `pendingByDay[uint32 day]` slot referenced by INV-04, INV-05, INV-08, INV-09, INV-10.

### SPEC-02: Composite-key pendingRedemptions + UnresolvedClaim revert removal

**Lock:** `mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions` — composite key per `(player, day)`. `claimRedemption(uint32 day) external` signature — the caller specifies which day's resolved claim to settle; no batch helper, no implicit-day variant; immediate-claim UX preserved. The pre-refactor `UnresolvedClaim` revert at `StakedDegenerusStonk.sol:796-797` is REMOVED — under composite keying a player may legitimately hold concurrent unresolved entries across multiple days, so the revert becomes both incorrect and meaningless. The `NotResolved` revert at `:624` (gated on `period.roll == 0`) is PRESERVED — a player must still wait for their target day's advance to fire before claiming.

**Rationale:** Composite keying is the structural separation that closes V-184 on the player side: a re-burn on day `D+1` writes `pendingRedemptions[player][D+1]`, a distinct storage slot from `pendingRedemptions[player][D]`, so no later action can retroactively rewrite a player's day-D claim values (INV-07). The `UnresolvedClaim` revert existed because the pre-refactor single-pool design required players to flush their prior claim before a new burn could land — that constraint dissolves under per-day keying.

**Impact on storage layout:** Re-keys an existing storage slot (`pendingRedemptions` at `:221`) from `address → PendingRedemption` to `address → uint32 → PendingRedemption`. The inner `PendingRedemption` struct shape is unchanged at the field level (`uint96 ethValueOwed`, `uint96 burnieOwed`, `uint16 activityScore`); the `uint32 periodIndex` field at the pre-refactor `:212` is REMOVED because the outer mapping key now carries the day reference. New per-claim slot: 1 (down from 1 — same slot count, but the `periodIndex` field is reclaimed).

**Impact on call sites:** `_submitGamblingClaimFrom` writes `pendingRedemptions[beneficiary][game.currentDayView()]` (composite); the pre-refactor `if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) revert UnresolvedClaim();` block at `:796-797` is DELETED. `claimRedemption(day)` reads `pendingRedemptions[msg.sender][day]` and `redemptionPeriods[day]`; existing `NotResolved` (`period.roll == 0`) revert preserved (`:624`). `_payEth` and `_payBurnie` flows downstream of the claim are UNCHANGED — they consume `(player, amount)` only.

**Resolves §1 forward-reference:** Sets the storage shape that §1 INV-04 (per-day base sum), INV-05 (cumulative correctness), INV-07 (self-roll immutability), and INV-11 (per-(player, day) EV cap) all reference verbatim.

### SPEC-03: dayToResolve arg on resolveRedemptionPeriod + hasPendingRedemptions(day)

**Lock:** `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external` — explicit `dayToResolve` arg supplied by the `DegenerusGameAdvanceModule` caller. Value passed at every call site: `dayToResolve = game.currentDayView() - 1` (the just-completed day whose pool is being resolved against day-D+1's VRF word). Equivalently: at the moment the advance fires for wall-day `D`'s VRF derivation, day `D-1`'s pool is what gets resolved — the one-day offset is preserved verbatim from the pre-refactor flow, expressed by an explicit arg instead of an implicit `redemptionPeriodIndex` read.

**Lock secondary:** `function hasPendingRedemptions(uint32 day) external view returns (bool)` — query takes an explicit day arg and returns `pendingByDay[day].ethBase != 0 || pendingByDay[day].burnieBase != 0`. All three AdvanceModule gating sites pass the IDENTICAL `dayToResolve` value to both `hasPendingRedemptions(dayToResolve)` (the gate) and `resolveRedemptionPeriod(roll, flipDay, dayToResolve)` (the writer). No call site computes `dayToResolve` differently; Plan 05 grep-verifies all three sites pass the same expression.

**Rationale:** The pre-refactor `resolveRedemptionPeriod(uint16 roll, uint32 flipDay)` read `period = redemptionPeriodIndex` implicitly at `:588`. Under per-day keying that single-pool index slot is deleted (SPEC-01) and the caller must name the target day explicitly. Making the arg explicit also enforces INV-08: the AdvanceModule chooses `currentDayView() - 1` so the resolver cannot accidentally write `redemptionPeriods[currentDay]` or read `pendingByDay[currentDay]` — the gap-window safety property is a direct consequence of the arg's value.

**Impact on storage layout:** No new slot; no slot removed at this lock (the `redemptionPeriodIndex` removal is owned by SPEC-01). The arg IS the per-call selector — the resolver reads no contract-state for day selection; the target day flows in from the caller.

**Impact on call sites:** Three call sites in `contracts/modules/DegenerusGameAdvanceModule.sol` update to pass the third arg: `:1230` (first sStonk resolve in `_advanceGame`'s primary path), `:1293` (second resolve in the secondary advance path), `:1323` (third resolve in the tertiary path). All three sites currently call `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` and must update to `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay, dayToResolve)` where `dayToResolve` is computed from the local-variable in scope at each site (Plan 05 grep-verifies the exact local-variable name at each site; the prompt-given baseline is `currentDayView() - 1` or the equivalent already-in-scope local). All three gating-site `hasPendingRedemptions()` calls at `:1225`, `:1288`, `:1318` update from the zero-arg form to `hasPendingRedemptions(dayToResolve)` with the same value.

**Resolves §1 forward-reference:** INV-08 (pre-advance-gap burn safety) — explicit `dayToResolve = currentDayView() - 1` is the structural lock that makes `pendingByDay[currentDay]` physically unreachable from the advance writer. INV-09 (skipped-advance recovery oldest-first ordering) — the locked derivation is the simple `currentDayView() - 1` form; under skipped advances the AdvanceModule's existing day-by-day catch-up loop already iterates from oldest unresolved forward, so each iteration's local `dayToResolve` walks the backlog oldest-first without an explicit scan.

### SPEC-04: gameOver + zero-rounded + delete-timing sub-locks (a–d)

**Lock:** SPEC-04 contains four lettered sub-locks (a–d) that `REQUIREMENTS.md` flagged "to lock at SPEC phase." Each sub-lock below names the post-refactor behavior declaratively and is non-negotiable input to Phase 305 IMPL: (a) `pendingByDay[D]` survives `gameOver` and the advance loop continues to resolve pre-gameOver pending days; (b) zero-rounded `ethValueOwed` burns proceed normally with a zero-payout claim; (c) `delete pendingByDay[D]` fires inside `resolveRedemptionPeriod` after `redemptionPeriods[D]` is written; (d) `delete pendingRedemptions[msg.sender][day]` fires inside `claimRedemption(day)` after full payout, with the partial-claim branch (unresolved coinflip) preserved verbatim from the pre-refactor flow.

**Rationale:** SPEC-04 (a) preserves the existing `:638-643` 50/50-vs-100% split logic which already provides the correct post-`gameOver` payout semantic without an explicit branch in `resolveRedemptionPeriod`; minimum-surface-area approach per `feedback_frozen_contracts_no_future_proofing.md` pre-launch posture. SPEC-04 (b)–(d) preserve existing v43 economic and refund semantics verbatim under the per-day composite-key shape. Each sub-lock's detailed rationale is given in the corresponding (a)/(b)/(c)/(d) entry below.

**Impact on storage layout:** SPEC-04 does not introduce or remove top-level storage slots. The (c) and (d) `delete` sites refund the slots introduced by SPEC-01 (3 slots per resolved day) and SPEC-02 (1 slot per claimed (player, day) pair) at the appropriate transition boundaries.

**Impact on call sites:** `resolveRedemptionPeriod` adds the `delete pendingByDay[dayToResolve]` site (SPEC-04 (c)). `claimRedemption(day)` adds the `delete pendingRedemptions[msg.sender][day]` site at the full-claim path (SPEC-04 (d)). `_submitGamblingClaimFrom` does not add a zero-rounded revert branch (SPEC-04 (b)) — the existing `amount == 0 || amount > bal` revert at `:754` is the only zero-guard. `resolveRedemptionPeriod` does not add a `gameOver` short-circuit (SPEC-04 (a)) — the advance loop continues normally.

**Resolves §1 forward-reference:** SPEC-04 (a) resolves INV-12 (selects Semantic (a) gracefully-resolve over Semantic (b) fail-closed); SPEC-04 (c) supports INV-10 (closes the cap-enforcement window at resolve); SPEC-04 (d) supports INV-07 (terminates the self-roll-immutability half-open window at the full-claim `delete`).



- **(a) gameOver mid-pending semantics — gracefully-resolve:** LOCK: `pendingByDay[D]` SURVIVES `game.gameOver` latching to true. If pre-gameOver pending exists at day `D` and `gameOver` latches before day-`D+1`'s advance fires, the eventual day-`D+1` advance still calls `resolveRedemptionPeriod(roll, flipDay, dayToResolve = D)` and writes `redemptionPeriods[D].roll` normally — the redemption roll is a sub-component of the advance VRF derivation, not a separate gate, so the advance loop does not short-circuit redemption resolution on `gameOver`. Players then call `claimRedemption(D)` and the existing `:638-643` 50/50-split branch degenerates correctly: the `isGameOver = game.gameOver()` check at `:635` selects the 100%-direct path (`ethDirect = totalRolledEth`, no lootbox routing), which is the desired post-`gameOver` payout semantic. If `gameOver` fires AFTER the resolve and BEFORE the claim, the same `:635` check yields the same 100%-direct outcome with no special branch needed in `resolveRedemptionPeriod`. **Rationale:** pre-launch frozen-at-deploy posture per `feedback_frozen_contracts_no_future_proofing.md` — no separate gameOver branch is added to `resolveRedemptionPeriod`; minimum-surface-area approach; the existing `:638-643` split logic already provides the correct post-`gameOver` semantic by construction. **Resolves §1 forward-reference:** INV-12 (gameOver mid-pending safety) — Plan 02 selects Semantic (a) "gracefully-resolve" of the two candidates §1 documented; the Phase 306 invariant_INV_12 test mechanizes the gracefully-resolve path with no ambiguity.

- **(b) zero-rounded ethValueOwed handling — burn proceeds, zero claim is no-op:** LOCK: the existing `amount == 0 || amount > bal` revert in `_submitGamblingClaimFrom` (`:754`) is PRESERVED — burns of zero sDGNRS revert as before. If `amount != 0` but the proportional `ethValueOwed = (totalMoney * amount) / supplyBefore` rounds to zero (e.g. 1 wei sDGNRS burned at very low `supply` ratio), the burn PROCEEDS with `ethValueOwed = 0` written to `pendingRedemptions[player][day].ethValueOwed` and `pendingByDay[day].ethBase`. A subsequent `claimRedemption(day)` on a zero-ethValueOwed claim pays 0 ETH (no `_payEth` work because `claim.ethValueOwed * roll / 100 == 0`) and the storage-refund still fires per SPEC-04 (d). **Rationale:** integer-division rounding is bounded; a zero-claim has no economic effect (no payout, no liability); does not affect INV-04/INV-05 sum equalities (zero contributes zero to both sides); matches existing economic behavior pre-refactor. Adding a "round-to-zero revert" branch would be a behavior change and is REJECTED at this lock. EDGE-13 (Plan 03) tests this case explicitly. **Resolves §1 forward-reference:** None directly; this sub-lock is referenced by EDGE-13 (zero-rounded burn) which Plan 03 enumerates.

- **(c) pendingByDay[D] storage-refund timing — delete at resolve:** LOCK: `delete pendingByDay[D]` fires INSIDE `resolveRedemptionPeriod`, AFTER `redemptionPeriods[D]` has been written and `RedemptionResolved` has emitted. The storage-refund (3 slots refunded per resolved day per SPEC-01) flows to the AdvanceModule caller (the EOA invoking `advanceGame`). The early-return short-circuit at the pre-refactor `:589` (`if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;`) becomes `if (pendingByDay[dayToResolve].ethBase == 0 && pendingByDay[dayToResolve].burnieBase == 0) return;` — the no-pending day short-circuit is preserved verbatim, just re-keyed. **Rationale:** the per-day pool ceases to need cross-day reference once `redemptionPeriods[D].roll` is written; resolving to the per-claim composite-keyed storage at one transition boundary minimizes long-lived day-keyed storage and concentrates the refund in the same transaction that consumes the slots' last useful read. **Resolves §1 forward-reference:** INV-10 (per-day supply cap) — the cap predicate `pendingByDay[D].supplySnapshot != 0` becomes false after the delete; INV-10's enforcement window closes at the resolve, consistent with the property's "until the period is settled" framing.

- **(d) pendingRedemptions[player][day] storage-refund at claim — delete after full payout:** LOCK: `delete pendingRedemptions[msg.sender][day]` fires INSIDE `claimRedemption(day)`, AFTER both `_payEth` and `_payBurnie` (or their lootbox-eth equivalent at `:667-673`) have executed and the `RedemptionClaimed` event has emitted. The pre-refactor partial-claim branch at `:659-665` is PRESERVED VERBATIM: when the coinflip is unresolved (`flipResolved == false`), the claim clears only `claim.ethValueOwed = 0` and retains `claim.burnieOwed` for a second claim attempt; the `delete` fires ONLY when `flipResolved == true` (full claim path at `:660-661`). The interaction with the coinflip-result oracle is preserved verbatim from `:649-654`: `(rewardPercent, flipWon) = coinflip.getCoinflipDayResult(period.flipDay)` and `flipResolved = (rewardPercent != 0 || flipWon)`. **Rationale:** the partial-claim path is the existing v43 contract semantic for unresolved-coinflip days; SPEC-04 (d) preserves it verbatim under composite keying (`pendingRedemptions[msg.sender][day]` replacing `pendingRedemptions[msg.sender]`). Storage-refund concentrates at the full-claim path because partial-claims still need the slot live for the second-claim BURNIE payout. **Resolves §1 forward-reference:** INV-07 (self-roll immutability) — the half-open window `[T_set, T_claim(P, D))` terminates at the `delete`, which fires only on the full-claim path; under partial-claim the window extends to the eventual full-claim, with the partial-clear (`claim.ethValueOwed = 0`) being a player-initiated mutation excluded from INV-07's "non-EXEMPT actor" predicate.

### SPEC-05: 50% supply cap snapshot timing — lazy-init on first burn of day

**Lock:** `pendingByDay[D].supplySnapshot` is lazy-initialized on the first burn of day `D` — at the moment when `pendingByDay[D].supplySnapshot == 0` AND `pendingByDay[D].burned == 0` (both packed half-slots zero). The initialization value is `totalSupply` AT THAT MOMENT (the post-burn `totalSupply` is captured AFTER the burn's `totalSupply -= amount` decrement only if the IMPL phase reorders for gas; per `:766` precedent the existing pre-refactor pattern captures `supplyBefore = totalSupply` BEFORE the decrement, and SPEC-05 preserves that pre-decrement semantic). Once initialized, `pendingByDay[D].supplySnapshot` is IMMUTABLE for the rest of day `D` — subsequent same-day burns enforce the cap against the snapshot, not against the current decreasing `totalSupply`. The cap check at the pre-refactor `:763` becomes `if (pendingByDay[currentDay].burned + amount > pendingByDay[currentDay].supplySnapshot / 2) revert Insufficient();`.

**Rationale:** prevents the cap from automatically tightening as a same-day series of burns reduces `totalSupply`. Without the snapshot lock, an early burner could legitimately burn near the cap, then subsequent same-day burners would see a smaller `totalSupply` and a tighter `totalSupply / 2` budget — creating an unintended cross-burner externality where the first-mover indirectly throttles same-day followers. The pre-refactor `:758-762` reset block already lazy-inits on a per-period basis (`if (redemptionPeriodIndex != currentPeriod) { redemptionPeriodSupplySnapshot = totalSupply; redemptionPeriodIndex = currentPeriod; redemptionPeriodBurned = 0; }`); SPEC-05 preserves that semantic verbatim under per-day keying, with the predicate changing from "period changed" to "slot reads zero" (which is the structurally-equivalent test under per-day mapping keys: the `redemptionPeriodIndex != currentPeriod` check is exactly the same as `pendingByDay[currentDay].supplySnapshot == 0 && pendingByDay[currentDay].burned == 0` on a fresh day key).

**Impact on storage layout:** Uses the `supplySnapshot` half-slot of `pendingByDay[D]` (SPEC-01). No new slot; replaces the pre-refactor `redemptionPeriodSupplySnapshot` global at `:229` with the per-day mapped half-slot.

**Impact on call sites:** `_submitGamblingClaimFrom` replaces the pre-refactor `:758-762` reset block with the lazy-init: `if (pendingByDay[currentDay].supplySnapshot == 0 && pendingByDay[currentDay].burned == 0) { pendingByDay[currentDay].supplySnapshot = uint128(totalSupply); }`. The cap check at `:763` re-keys to `pendingByDay[currentDay].supplySnapshot / 2`. The `pendingByDay[currentDay].burned += amount` accumulator at `:764` re-keys identically.

**Resolves §1 forward-reference:** INV-10 (per-day supply cap) — the snapshot lazy-init timing is the lock that makes INV-10's "snapshot taken on first burn of day D, immutable for the rest of day D" property hold by construction.

### §2.7 — Cross-cutting: the 7 deletions Plan 04 design-intent-traces

Plan 04 §4 walks the original design intent + actor game-theory for each of the 7 deletions enumerated below before locking them. This section is the deletion work-item list Plan 04 consumes.

1. `redemptionPeriodIndex` storage slot (`StakedDegenerusStonk.sol:230`) — subsumed by per-day mapping keys; obsolete under SPEC-01.
2. `redemptionPeriodSupplySnapshot` storage slot (`:229`) — subsumed by `pendingByDay[D].supplySnapshot` half-slot per SPEC-01 + SPEC-05.
3. `redemptionPeriodBurned` storage slot (`:231`) — subsumed by `pendingByDay[D].burned` half-slot per SPEC-01.
4. `pendingRedemptionEthBase` storage slot (`:226`) — subsumed by `pendingByDay[D].ethBase` per SPEC-01.
5. `pendingRedemptionBurnieBase` storage slot (`:227`) — subsumed by `pendingByDay[D].burnieBase` per SPEC-01.
6. `UnresolvedClaim` revert (`:796-797`) — removed by composite keying per SPEC-02; the revert was structurally required only under the pre-refactor single-pool design where concurrent unresolved player claims aliased into one slot.
7. `redemptionPeriodIndex` reset block (`:757-762` — the `if (redemptionPeriodIndex != currentPeriod) { ... }` body opens at `:757` per source-verified read; Plan 05 grep-verifies the canonical range against HEAD and either confirms `:757-762` or corrects) — deleted by composite keying + lazy-init snapshot per SPEC-01 + SPEC-02 + SPEC-05; the reset is replaced by the SPEC-05 lazy-init check.



## §3 — Edge Scenario Enumeration (EDGE-01..18)

_To be filled by Plan 03 — see PLAN.md_

## §4 — Design-Intent Backward-Trace + Actor Game-Theory Walk

_To be filled by Plan 04 — see PLAN.md_

## §5 — Source-Verified Citation Manifest

_To be filled by Plan 05 — see PLAN.md_
