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

> The 18 EDGE-NN entries below are the v44.0 threat-enumeration locus. Each entry has six labeled sub-fields: a narrative **Scenario**, a **Positive assertion** (correct-behavior outcome), a **Negative assertion** (specific revert OR byte-identity attestation that no exploit is reachable), the **Tests INV-NN** linkage, the **Depends on SPEC-NN** linkage, and the suggested **Foundry function name** for Phase 306 to mechanize. EDGE-07 — the V-184 attack reproduction per `.planning/RNGLOCK-FIXREC.md` §103 (lines 5410-5520) — is the headline negative test for v44.0 closure; HANDOFF-111..117 close STRUCTURALLY by absence of the overwrite primitive (per §2.0 Priority Statement, clause 1). The §1↔§3 cross-link table at the end of this section maps every INV-NN to its EDGE-NN exercisers so Plan 05 can grep-verify completeness.

### EDGE-01: Pre-advance-gap burn on day D

**Scenario:** Wall-clock has just flipped to day `D` (i.e., `game.currentDayView() == D`) and day-`D`'s `advanceGame()` call has not yet fired. Player A calls `burn(amount)` during this gap window. Day-`D-1`'s redemption pool `pendingByDay[D-1]` exists and is populated by burns from the prior wall-clock day; day-`D`'s pool `pendingByDay[D]` is the fresh slot the new burn must land in. Under post-refactor per-day keying (SPEC-01), the burn writes `pendingByDay[currentDay].ethBase += ethValueOwed` where `currentDay = game.currentDayView() == D`, while the still-unresolved `pendingByDay[D-1]` retains its full prior-day base value. The cumulative scalar `pendingRedemptionEthValue` reflects the sum of both pools simultaneously.

**Positive assertion:** the new burn writes its `ethValueOwed` and `burnieOwed` proportional values into `pendingByDay[D]` (the post-refactor lazy-init also fires here: `pendingByDay[D].supplySnapshot` initializes to `totalSupply` AT THE BURN MOMENT and `pendingByDay[D].burned` increments by `amount`); the cumulative `pendingRedemptionEthValue` equals the sum of `pendingByDay[D-1].ethBase` (pre-existing) + the new ETH base contribution from this burn into `pendingByDay[D].ethBase`; the per-claim slot `pendingRedemptions[A][D]` carries the player-side mirror of this base.

**Negative assertion:** `pendingByDay[D-1].ethBase`, `pendingByDay[D-1].burnieBase`, `pendingByDay[D-1].supplySnapshot`, and `pendingByDay[D-1].burned` are each byte-identical before and after the day-`D` burn (captured snapshot pre-burn, re-read post-burn, asserted equal slot-for-slot). The day-`D` burn cannot write to or mutate the day-`D-1` pool; the storage key separation makes this physically unreachable.

**Tests INV-NN:** Tests INV-08 (pre-advance-gap burn safety — burns during the gap land in the current-day pool, never the prior-day pool). Also tests INV-04 (per-day base correctness — the new `pendingByDay[D].ethBase` equals the sum of `pendingRedemptions[A][D].ethValueOwed` from this single-burn case) and INV-05 (cumulative correctness — `pendingRedemptionEthValue` aggregates both pools).

**Depends on SPEC-NN:** Depends on SPEC-01 (per-day-keyed `pendingByDay[uint32]` pool) + SPEC-03 (dayToResolve = `currentDayView() - 1` — the advance never reads or writes `pendingByDay[currentDay]`).

**Foundry function name:** `testFuzz_EDGE_01_PreAdvanceGapBurnLandsInCurrentDayPool`

### EDGE-02: Two pending days simultaneously

**Scenario:** Day `D-1` has unresolved burns (`pendingByDay[D-1].ethBase != 0`) — i.e., the prior wall-clock day's burns are awaiting their day-`D` advance call to resolve. Concurrently, the wall-clock has already flipped to day `D`, and one or more day-`D` burns have already landed in `pendingByDay[D]`. The AdvanceModule now fires day-`D`'s `advanceGame()` call, which invokes `resolveRedemptionPeriod(roll, flipDay, dayToResolve)` with `dayToResolve = currentDayView() - 1 = D-1` (per SPEC-03). The resolver must process `pendingByDay[D-1]` only — it must not read from or write to `pendingByDay[D]`.

**Positive assertion:** after the day-`D` advance fires, `redemptionPeriods[D-1].roll == R_D` (the rolled value derived from day-`D`'s VRF word), `redemptionPeriods[D-1].flipDay` is set to the corresponding coinflip day, the `RedemptionResolved` event emits for period `D-1`, and `pendingByDay[D-1]` is deleted (`pendingByDay[D-1].ethBase == 0 && pendingByDay[D-1].burnieBase == 0 && pendingByDay[D-1].supplySnapshot == 0 && pendingByDay[D-1].burned == 0` per SPEC-04 (c) delete-at-resolve).

**Negative assertion:** `pendingByDay[D].ethBase`, `pendingByDay[D].burnieBase`, `pendingByDay[D].supplySnapshot`, and `pendingByDay[D].burned` are byte-identical before and after the day-`D` advance call (captured snapshot pre-advance, re-read post-advance, asserted equal slot-for-slot); `redemptionPeriods[D].roll == 0` after the advance (the day-`D` period slot has NOT been written — only `redemptionPeriods[D-1]` was written). The advance fundamentally cannot touch the current day's pool because `dayToResolve = D-1` is the explicit arg passed by the AdvanceModule.

**Tests INV-NN:** Tests INV-08 (pre-advance-gap burn safety — confirms the burn into day `D` is preserved unmodified by the day-`D` advance) and INV-09 (skipped-advance recovery — confirms one-day-at-a-time resolution; the next advance for day `D+1` will resolve `pendingByDay[D]` and so on).

**Depends on SPEC-NN:** Depends on SPEC-03 (explicit `dayToResolve` arg; `currentDayView() - 1` derivation) + SPEC-04 (c) (delete-at-resolve produces the day-`D-1` cleared-state post-advance).

**Foundry function name:** `testFuzz_EDGE_02_TwoPendingDaysSimultaneous`

### EDGE-03: Single player burns multiple days, never claims

**Scenario:** Player A burns on day `D`, then again on day `D+1`, then again on day `D+2` — without ever calling `claimRedemption` between burns. Under post-refactor composite-key `pendingRedemptions[player][day]` (SPEC-02), each burn writes to an independent storage slot: `pendingRedemptions[A][D]`, `pendingRedemptions[A][D+1]`, `pendingRedemptions[A][D+2]`. The pre-refactor `UnresolvedClaim` revert (at `:796-797` per source) is REMOVED under SPEC-02, so a multi-day pending pile-up is legitimate. After the day-`D+1`, day-`D+2`, day-`D+3` advances have all fired (resolving days `D`, `D+1`, `D+2` respectively), player A can call `claimRedemption(D)`, `claimRedemption(D+1)`, `claimRedemption(D+2)` in any order.

**Positive assertion:** each of `pendingRedemptions[A][D]`, `pendingRedemptions[A][D+1]`, `pendingRedemptions[A][D+2]` is independently populated with its own `ethValueOwed`, `burnieOwed`, and `activityScore` derived from the contract state at its respective burn moment; each of `redemptionPeriods[D].roll`, `redemptionPeriods[D+1].roll`, `redemptionPeriods[D+2].roll` is independently written by its respective advance; claiming `D+2` first (out-of-order) succeeds and deletes `pendingRedemptions[A][D+2]` per SPEC-04 (d) without touching `pendingRedemptions[A][D]` or `pendingRedemptions[A][D+1]`. The claims for `D` and `D+1` then remain claimable in any order.

**Negative assertion:** claiming day `D+2` does not mutate the claim slots for days `D` or `D+1` — captured `pendingRedemptions[A][D].ethValueOwed`, `.burnieOwed`, `.activityScore` byte-identical before and after the day-`D+2` claim. No `UnresolvedClaim` revert fires at any of the burns (the revert is structurally removed under SPEC-02); no cross-day storage aliasing.

**Tests INV-NN:** Tests INV-04 (per-day base correctness — each day's base correctly accumulates only its own day's burns) and INV-07 (no self-roll manipulation via timing — the day-`D+2` claim does not retroactively mutate the locked-at-burn-time `pendingRedemptions[A][D].ethValueOwed`).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key `pendingRedemptions[player][day]`; `UnresolvedClaim` revert removed).

**Foundry function name:** `testFuzz_EDGE_03_SinglePlayerMultiDayClaimsIndependent`

### EDGE-04: Multiple players burn same day, different times relative to advance

**Scenario:** Day `D`. Player A burns at time `T1` (pre-advance, i.e., before day-`D+1`'s `advanceGame` fires). Player B burns at time `T2` (post-advance — but here "post-advance" specifically means after day-`D`'s `advanceGame` call has fired and resolved day `D-1`, AND before wall-clock crosses into day `D+1`). Both burns target the same wall-clock day `D` and therefore both write into `pendingByDay[D]` per SPEC-01. The lazy-init snapshot (SPEC-05) fires on whichever of `T1` or `T2` is the first burn of day `D`. Eventually, day-`D+1`'s `advanceGame` fires and `resolveRedemptionPeriod(roll, flipDay, dayToResolve = D)` is invoked.

**Positive assertion:** at day-`D+1` advance time, `pendingByDay[D].ethBase == pendingRedemptions[A][D].ethValueOwed + pendingRedemptions[B][D].ethValueOwed` (the per-day base equals the sum of player contributions). After the resolve, both `pendingRedemptions[A][D]` and `pendingRedemptions[B][D]` reference the SAME `redemptionPeriods[D].roll == R_{D+1}` — when each player claims, their `totalRolledEth = (claim.ethValueOwed * R_{D+1}) / 100` is computed using the same roll. The sum of `totalRolledEth` paid to A and B equals `(pendingByDay[D].ethBase * R_{D+1}) / 100` modulo per-claimant floor-division dust bounded by 1 wei per claimant.

**Negative assertion:** A's `pendingRedemptions[A][D].ethValueOwed` value is byte-identical before and after B's burn (captured pre-B-burn, re-read post-B-burn, asserted equal); B's `pendingRedemptions[B][D].ethValueOwed` value is byte-identical before and after the resolve (captured pre-resolve, re-read post-resolve). The two players' per-claim slots are independent storage keys and cannot overwrite each other.

**Tests INV-NN:** Tests INV-04 (per-day base correctness — the per-day base correctly aggregates A + B), INV-05 (cumulative correctness — `pendingRedemptionEthValue` tracks the sum), and INV-06 (no cross-player roll manipulation — A's roll is identical to B's roll for day `D`, and neither can manipulate the other's claim).

**Depends on SPEC-NN:** Depends on SPEC-01 (per-day-keyed pool) + SPEC-02 (composite-key player-day claim).

**Foundry function name:** `testFuzz_EDGE_04_MultiplePlayersSameDay`

### EDGE-05: Player claims before advance fires

**Scenario:** Player A burns on day `D`, writing `pendingRedemptions[A][D].ethValueOwed = X` and `redemptionPeriods[D].roll == 0` (unwritten — day-`D+1`'s advance has not yet fired). Before day-`D+1`'s advance fires (i.e., the wall-clock either has not yet flipped to day `D+1` or has but the advance hasn't been called), player A attempts to call `claimRedemption(D)`. The `claimRedemption` function reads `redemptionPeriods[D]` (per SPEC-02), checks `period.roll == 0`, and reverts with `NotResolved` (error at `:114` per `contracts/StakedDegenerusStonk.sol`).

**Positive assertion:** the call to `claimRedemption(D)` reverts with `NotResolved`. The revert fires from the existing `:624` guard (`if (period.roll == 0) revert NotResolved();`) which is preserved verbatim under SPEC-02. After the failed call, the player can wait for the advance and then successfully claim.

**Negative assertion:** no state mutation occurs on the failed claim attempt — `pendingRedemptions[A][D].ethValueOwed`, `.burnieOwed`, `.activityScore` byte-identical before and after the failed call; `pendingRedemptionEthValue` byte-identical; no event emitted. The revert is total (no partial state). No mutation of `redemptionPeriods[D]` either — the slot stays at its zero-initialized state.

**Tests INV-NN:** Tests INV-07 (no self-roll manipulation via timing — the failed claim doesn't alter the locked `ethValueOwed`).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key claim with `NotResolved` revert preserved at `:624`).

**Foundry function name:** `testFuzz_EDGE_05_ClaimBeforeResolveReverts`

### EDGE-06: Skipped advance, long stall

**Scenario:** Player A burns on day `D`, writing `pendingRedemptions[A][D]` and `pendingByDay[D]` normally. Day-`D+1`'s `advanceGame` does NOT fire on time — perhaps stalled for 12 hours or longer due to a VRF callback delay, retryLootboxRng invocation, or simple advance-caller absence. Eventually (could be hours, could be a full day later — but always within the protocol's stall-recovery posture), day-`D+1`'s advance does fire, calling `resolveRedemptionPeriod(roll, flipDay, dayToResolve = D)` per SPEC-03. The VRF word feeding `roll` could be either the originally-pending day-`D+1` VRF word (if the stall was VRF-callback delay) OR the retryLootboxRng failsafe word (per `D-42N-RETRY-RNG-DOMAIN-SEP-01` carry — the failsafe path is structurally separate from but produces a valid `roll` value).

**Positive assertion:** after the eventual advance fires, `redemptionPeriods[D].roll != 0` and equals whichever VRF-derived value the advance produced; player A's subsequent `claimRedemption(D)` reads that `roll` and pays `totalRolledEth = (claim.ethValueOwed * roll) / 100` as normal. No stuck claim path; the claim succeeds regardless of how long the stall lasted; the day-`D` pool is fully resolved.

**Negative assertion:** there is no time-based degradation of the claim — `pendingRedemptions[A][D].ethValueOwed` is byte-identical to its post-burn value at the moment of the eventual advance (captured snapshot at burn, re-read at advance, asserted equal). No mutation by the passage of wall-clock time; no mutation by intervening burn/claim/admin actions by other players (per INV-07). Backward-trace per `feedback_rng_backward_trace.md`: the eventual `roll` value is a deterministic function ONLY of the VRF word that fed the eventual advance's `currentWord` derivation (chainlink callback OR retryLootboxRng) AND the per-position bit-slice ops in AdvanceModule — no SLOAD of player-controllable state inside the rng-derivation window aliases into `roll`.

**Tests INV-NN:** Tests INV-09 (skipped-advance recovery — oldest-first ordering; the eventual advance resolves day `D` as the next-oldest unresolved). Also tests INV-07 (no self-roll manipulation via timing — the claim value is locked at burn time independent of stall duration).

**Depends on SPEC-NN:** Depends on SPEC-03 (`dayToResolve = currentDayView() - 1` derivation; oldest-first by construction since AdvanceModule's day-by-day catch-up loop iterates from oldest forward).

**Foundry function name:** `testFuzz_EDGE_06_SkippedAdvanceLongStallEventualResolution`

### EDGE-07: V-184 attack reproduction — same-day post-resolve re-burn → next-advance overwrite (THE HEADLINE NEGATIVE TEST for v44.0 closure)

**Scenario:** This is the verbatim reproduction of the V-184 attack mechanic enumerated in `.planning/RNGLOCK-FIXREC.md` §103.A trace steps 1-5 (lines 5443-5470) and §103.B actor game-theory walk steps 1-7 (lines 5482-5510). Attack sequence: (1) Day `D`, player A burns `amount_A` sDGNRS via `burn(amount_A)` — writing `pendingRedemptions[A][D]` and incrementing `pendingByDay[D].ethBase`. (2) Day-`D+1`'s advance fires, calling `resolveRedemptionPeriod(roll_{D+1}, flipDay, dayToResolve = D)` and writing `redemptionPeriods[D].roll = R_{D+1}` (the roll derived from day-`D+1`'s VRF word; see RNGLOCK-FIXREC §103.A step 2 for the pre-refactor mechanism). Per SPEC-04 (c), `delete pendingByDay[D]` fires inside the resolver after the write. (3) Attacker B (or attacker A) — still on wall-clock day `D` (post-advance, pre-day-boundary, per RNGLOCK-FIXREC §103.B cross-day-boundary subtlety at line 5517) — observes `redemptionPeriods[D].roll = R_{D+1}` via the public auto-getter; if `R_{D+1} < 100` (unfavorable), attacker B calls `burn(1)` to re-burn 1 wei sDGNRS. Under post-refactor SPEC-01 + SPEC-03 + SPEC-04 (c), the re-burn must NOT overwrite `redemptionPeriods[D].roll` at any future advance. The post-refactor behavior is determined by where the 1-wei re-burn lands: (i) if the re-burn happens with `game.currentDayView() == D` (still day `D` wall-clock), it lands in `pendingByDay[D]` — but `pendingByDay[D]` was just deleted at step 2's resolve (SPEC-04 (c)), so the slot is fresh — the re-burn re-creates `pendingByDay[D]` as a NEW entry with `supplySnapshot` lazy-initialized to current `totalSupply` and `burned = 1` and `ethBase = 1-wei-proportional-eth`; (ii) if the wall-clock has crossed to day `D+1`, the re-burn lands in `pendingByDay[D+1]`. Either way, the re-burn writes to `pendingByDay[D]` or `pendingByDay[D+1]` — NEVER directly to `redemptionPeriods[D]`. (4) Day-`D+2`'s advance fires, calling `resolveRedemptionPeriod(roll_{D+2}, flipDay, dayToResolve = D+1)` per SPEC-03 (dayToResolve = `currentDayView() - 1`). The advance writes `redemptionPeriods[D+1].roll = R_{D+2}` — a DISTINCT mapping slot from `redemptionPeriods[D]`. (5) On a further next advance (day `D+3`), `resolveRedemptionPeriod(roll, flipDay, dayToResolve = D+2)` writes `redemptionPeriods[D+2].roll`, and if the re-burn from step 3 landed in `pendingByDay[D]` (case (i) above), the advance that resolves that pool will write `redemptionPeriods[D]` — but wait: this is the V-184 question. Post-refactor: the advance for `pendingByDay[D]` writes to `redemptionPeriods[dayToResolve = D]` — but at that point, `currentDayView() - 1 = D` only if `currentDayView() == D+1`. Since case (i) requires the wall-clock to still be at day `D` for the re-burn AND the next advance (D+2's advance) computes `dayToResolve = currentDayView() - 1 = D+1`, the re-created `pendingByDay[D]` slot is NOT resolved at day-`D+2`'s advance — it's only resolved at the advance whose call passes `dayToResolve = D`. That advance is day-`D+1`'s advance, which already fired at step 2 and is one-shot per day. There is therefore NO future advance call that writes to `redemptionPeriods[D]` (because no future advance will pass `dayToResolve = D` — the AdvanceModule's catch-up loop iterates oldest-first from the oldest unresolved day, and `D` was already resolved at step 2). The re-created `pendingByDay[D]` becomes inert structurally: its value cannot trigger an `redemptionPeriods[D]` overwrite because no resolver receives `dayToResolve = D` again. Per RNGLOCK-FIXREC §103 V-184 mechanic verbatim: the attacker's same-day post-resolve re-burn → next-advance overwrite primitive is closed STRUCTURALLY by the storage shape (every day's resolve writes a distinct mapping slot, and `dayToResolve` is bounded oldest-first by the AdvanceModule per SPEC-03). HANDOFF-111..117 are closed by this entry alone (the 7 catalog rows V-184/V-186/V-188/V-190/V-191/V-192/V-193 collapse into the same structural mechanism per FIXREC §0.6).

**Positive assertion:** at every step of the attack sequence above, the resolver respects `dayToResolve` as the explicit arg passed by the AdvanceModule (SPEC-03); the writes target distinct mapping slots `redemptionPeriods[D]`, `redemptionPeriods[D+1]`, `redemptionPeriods[D+2]`; player A's `claimRedemption(D)` reads `redemptionPeriods[D].roll = R_{D+1}` (its first-write value from step 2) and pays `totalRolledEth = (claim.ethValueOwed * R_{D+1}) / 100` exactly as originally resolved.

**Negative assertion (THE LOAD-BEARING V-184 CLOSURE):** `redemptionPeriods[D].roll` is byte-identical to its first-write value `R_{D+1}` after every subsequent state transition in the attack sequence. Specifically, captured snapshot `R_{D+1} = redemptionPeriods[D].roll` immediately after step 2 (post-day-`D+1`-advance); after step 3 (re-burn) the snapshot is unchanged; after step 4 (day-`D+2` advance) the snapshot is unchanged; after step 5 (day-`D+3` advance and any subsequent advances) the snapshot is unchanged; assertEq enforced at every checkpoint. INV-01 (write-once roll immutability) holds across the entire attack sequence. NO re-roll is achievable by ANY single-wei or multi-wei re-burn sequence on day `D` post-resolve, regardless of wall-clock timing relative to the day boundary. This is the structural closure of the V-184 catastrophe-class vector per RNGLOCK-FIXREC §103 + HANDOFF-111..117.

**Tests INV-NN:** Tests INV-01 (write-once roll immutability — `redemptionPeriods[D].roll` written exactly once at step 2 and immutable thereafter), INV-06 (no cross-player roll manipulation — attacker B's re-burn cannot mutate player A's effective roll), and INV-07 (no self-roll manipulation via timing — even attacker A re-burning their own claim cannot retroactively mutate the day-`D` roll).

**Depends on SPEC-NN:** Depends on SPEC-01 (per-day-keyed `pendingByDay[uint32]` and per-day-keyed `redemptionPeriods[uint32]` — distinct slots per day, no shared index), SPEC-03 (explicit `dayToResolve` arg + `dayToResolve = currentDayView() - 1` + oldest-first AdvanceModule iteration), and SPEC-04 (c) (delete-at-resolve makes `pendingByDay[D]` re-creation by post-resolve burns a fresh-pool event rather than a stale-pool re-arming).

**Cross-reference:** This EDGE-NN is the spec for TST-04 (the standalone V-184 reproduction in Phase 306, per `.planning/REQUIREMENTS.md` line 63 `TST-04`) and TST-05 (the Phase 301 `test/fuzz/RngLockDeterminism.t.sol` `vm.skip(HANDOFF-111..117)` 7-block → strict-assertion flip, per `.planning/REQUIREMENTS.md` line 64 + Phase 301 SCAFFOLD + `D-301-VMSKIP-MECHANISM-01` Option C). The 7 catalog rows closed by this single test: HANDOFF-111 (V-184), HANDOFF-112 (V-186), HANDOFF-113 (V-188), HANDOFF-114 (V-190), HANDOFF-115 (V-191), HANDOFF-116 (V-192), HANDOFF-117 (V-193) — per FIXREC §0.6 subsumption map.

**Foundry function name:** `testFuzz_EDGE_07_V184AttackReproductionStructuralClosure`

### EDGE-08: Burn → gameOver → claim

**Scenario:** Two timing variants probed. **Variant 1 (gameOver fires BEFORE day-`D+1` advance):** Player A burns on day `D` writing `pendingRedemptions[A][D]` and `pendingByDay[D]` normally. Before day-`D+1`'s `advanceGame` fires, `game.gameOver()` latches to true (terminal condition). Per SPEC-04 (a) lock — gracefully-resolve — `pendingByDay[D]` SURVIVES the `gameOver` latching; the eventual day-`D+1` advance call still fires `resolveRedemptionPeriod(roll, flipDay, dayToResolve = D)` and writes `redemptionPeriods[D].roll` normally (the advance loop does not short-circuit redemption resolution on `gameOver`, per the SPEC-04 (a) rationale — minimum-surface-area approach via existing logic at `contracts/StakedDegenerusStonk.sol:638-643`). Player A then calls `claimRedemption(D)`: the `isGameOver = game.gameOver()` check at `:635` selects the `isGameOver` branch at `:638-643` which yields `ethDirect = totalRolledEth` (100% direct, no lootbox routing). **Variant 2 (gameOver fires AFTER resolve but BEFORE claim):** Player A burns day `D`; day-`D+1` advance fires and resolves normally with `redemptionPeriods[D].roll = R_{D+1}`. Then `gameOver` latches. Player A then claims: same `:635` check yields the same 100%-direct outcome as Variant 1 — no special branch needed in `resolveRedemptionPeriod`.

**Positive assertion:** in both variants, player A's claim succeeds (no revert); the payout amount is `totalRolledEth = (claim.ethValueOwed * R_{D+1}) / 100`; in the `isGameOver` branch, the full `totalRolledEth` is paid as direct ETH (`ethDirect = totalRolledEth`, `lootboxEth = 0` per `:638-643`); the `delete pendingRedemptions[A][D]` (SPEC-04 (d)) fires on the full-claim path and the slot is cleared.

**Negative assertion:** no partial state — either the claim succeeds in full or it reverts in full; no double-payment (only one `_payEth` call per claim, gated by the delete-at-claim refund); no stuck funds (`pendingRedemptionEthValue` decrements by exactly `totalRolledEth` per `:657`); no lootbox routing under `isGameOver` (lootboxEth == 0 explicitly).

**Tests INV-NN:** Tests INV-12 (gameOver mid-pending safety — pre-`gameOver` pending resolves and claims correctly under both variants).

**Depends on SPEC-NN:** Depends on SPEC-04 (a) (gracefully-resolve mid-pending gameOver lock).

**Foundry function name:** `testFuzz_EDGE_08_BurnGameOverClaimBothVariants`

### EDGE-09: Concurrent claims from N players same day

**Scenario:** N players (e.g., N ∈ {2, 5, 10, 100} — fuzz range) all burn on day `D`, each contributing `ethValueOwed_i` to `pendingByDay[D].ethBase`. Day-`D+1`'s advance fires and writes `redemptionPeriods[D].roll = R_{D+1}`. All N players then call `claimRedemption(D)` (in arbitrary order — interleaved or sequential — fuzz the ordering). Each claim computes `totalRolledEth_i = (claim_i.ethValueOwed * R_{D+1}) / 100` per `:632` (floor division — per-claimant up to 1 wei dust). Each claim decrements `pendingRedemptionEthValue` by exactly its `totalRolledEth_i` per `:657`.

**Positive assertion:** the sum of all per-claimant `totalRolledEth_i` equals `(pendingByDay[D].ethBase * R_{D+1}) / 100` ± (N-1) wei dust (the per-claimant floor-division can leave up to 1 wei rounding loss per claimant relative to the aggregate — total aggregate dust bounded by N-1 wei since one claimant's full per-claimant value lands exactly). After all N claims, `pendingRedemptionEthValue` decremented by `sum(totalRolledEth_i)`. Each player receives their `ethDirect_i` and `burniePayout_i` per existing `:632-684` semantics.

**Negative assertion:** total payouts in aggregate do NOT exceed `(pendingByDay[D].ethBase * R_{D+1}) / 100` (no over-payment); the post-claim sum of `pendingRedemptionEthValue` decrements is bounded above by the pre-resolve `pendingByDay[D].ethBase * R_{D+1} / 100` value; no double-claim possible — second call to `claimRedemption(D)` by the same player reverts `NoClaim` (error at `:111` per `contracts/StakedDegenerusStonk.sol`) because `delete pendingRedemptions[player][D]` fired at first claim per SPEC-04 (d) and the subsequent read sees `claim.ethValueOwed == 0 && claim.burnieOwed == 0`.

**Tests INV-NN:** Tests INV-02 (ETH conservation with dust bound) and INV-05 (cumulative correctness — `pendingRedemptionEthValue` decrement equals the aggregate `totalRolledEth` paid).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key claim) + SPEC-04 (d) (delete-at-full-claim prevents double-claim).

**Foundry function name:** `testFuzz_EDGE_09_NPlayersConcurrentClaimsSumWithDust`

### EDGE-10: Re-entrancy attempt on _payEth

**Scenario:** Malicious recipient contract `MaliciousReceiver` calls `claimRedemption(D)` after burning on day `D` and after day-`D+1`'s advance fires. During the `_payEth` call at `:683` (which is the LAST step of `claimRedemption` per the CEI ordering at `:618-684`), the contract uses raw `.call{value: ethDirect}("")` to transfer ETH. `MaliciousReceiver`'s `receive()` or `fallback()` function attempts to re-enter `claimRedemption(D)` recursively to drain a second payout from the same day's claim slot.

**Positive assertion:** the re-entrant call inside `MaliciousReceiver.receive()` reverts with `NoClaim` (error at `:111` per `contracts/StakedDegenerusStonk.sol`). The reason: per SPEC-04 (d), `delete pendingRedemptions[msg.sender][day]` fires INSIDE `claimRedemption(day)` AFTER `_payBurnie` but BEFORE `_payEth` is invoked at `:683` (the actual CEI ordering: `delete` at the post-`flipResolved` true branch around `:660-661`, then `_payBurnie` at `:677`, then emit at `:680`, then `_payEth` at `:683` — the delete fires before the external ETH `.call`, so by the time re-entry happens the storage slot is cleared). The re-entrant call reads `pendingRedemptions[player][D].ethValueOwed == 0 && .burnieOwed == 0`, and the `NoClaim` revert at the entry guard (current `:621` analog `if (claim.periodIndex == 0) revert NoClaim();` re-keyed under SPEC-02 to a zero-equivalent guard) fires.

**Negative assertion:** no double-payout — `pendingRedemptionEthValue` decrements by exactly `totalRolledEth` (one decrement at `:657`, not two); aggregate ETH transferred to `MaliciousReceiver` equals `ethDirect` (one transfer), not `2 * ethDirect`; the re-entrant call's revert propagates UP and reverts the outer call ONLY IF the outer `_payEth` `.call` checks success (which it does — `:828-829` and `:834-835` revert `TransferFailed` on `!success`). If `MaliciousReceiver` swallows the revert and returns successfully (so outer `.call` reports success), the outer claim succeeds with exactly one payout — no double-claim because the storage is cleared.

**Tests INV-NN:** Tests INV-02 (ETH conservation under re-entrant claim) and INV-07 (no self-roll manipulation via timing — re-entry cannot retroactively re-arm a deleted claim).

**Depends on SPEC-NN:** Depends on SPEC-04 (d) (delete-at-claim happens before the external ETH `.call`, structurally precluding re-entrant double-claim).

**Foundry function name:** `testFuzz_EDGE_10_ReentrancyOnPayEthBlocked`

### EDGE-11: Burn during rngLocked window

**Scenario:** During the VRF callback window — specifically when `game.rngLocked() == true` (the AdvanceModule has fired a VRF request and is awaiting Chainlink callback) — a player calls `burn(amount)`. The existing guard at `contracts/StakedDegenerusStonk.sol:492` (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`) fires immediately. Under SPEC-01 + SPEC-03, this guard is PRESERVED — the per-day refactor does not change this gate. The guard's purpose is exactly to close the rng-commitment window per `feedback_rng_commitment_window.md` (the player must not be able to alter VRF-input-feeding state between VRF request and fulfillment).

**Positive assertion:** the call to `burn(amount)` reverts with `BurnsBlockedDuringRng` (error at `:100` per `contracts/StakedDegenerusStonk.sol`). The revert fires at `:492` before any state mutation. After the revert, the player can wait for `rngLocked` to clear (post-callback) and then burn successfully.

**Negative assertion:** no state mutation — `pendingByDay[currentDay].ethBase`, `.burnieBase`, `.supplySnapshot`, `.burned` byte-identical before and after the failed call; `pendingRedemptions[player][currentDay].ethValueOwed`, `.burnieOwed`, `.activityScore` byte-identical; `pendingRedemptionEthValue`, `pendingRedemptionBurnie` byte-identical; `balanceOf[player]` byte-identical. The revert is total. Backward-trace per `feedback_rng_commitment_window.md`: no SLOAD inside the rng-window of any slot that this burn would have mutated — the guard structurally precludes the SLOAD-during-window vector.

**Tests INV-NN:** Tests INV-06 (no cross-player roll manipulation during the RNG-input commitment window — burns during `rngLocked` cannot mutate the inputs that derive the roll).

**Depends on SPEC-NN:** Depends on SPEC-01 (the per-day refactor preserves the existing `:492` guard verbatim; no change to the rngLocked check).

**Foundry function name:** `testFuzz_EDGE_11_BurnDuringRngLockedReverts`

### EDGE-12: Burn during livenessTriggered window

**Scenario:** During the liveness-triggered-but-not-yet-gameOver window — specifically when `game.livenessTriggered() == true && game.gameOver() == false` — a player calls `burn(amount)`. The existing guard at `contracts/StakedDegenerusStonk.sol:491` (`if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();`) fires immediately. Note: under `game.gameOver() == true`, the prior branch at `:487-490` handles deterministic burn and returns before reaching the liveness check, so this EDGE is specifically the liveness-on-gameOver-off window.

**Positive assertion:** the call to `burn(amount)` reverts with `BurnsBlockedDuringLiveness` (error at `:105` per `contracts/StakedDegenerusStonk.sol`). The revert fires at `:491` before any state mutation.

**Negative assertion:** no state mutation — `pendingByDay[currentDay].ethBase`, `.burnieBase`, `.supplySnapshot`, `.burned` byte-identical before and after the failed call; player's claim slot byte-identical; cumulative scalars byte-identical; `balanceOf[player]` byte-identical. The revert is total. Burns during the pre-gameOver-latch liveness window cannot land any value into `pendingByDay` slots — this preserves INV-08's "no pending writes during the structurally-uncertain liveness window" property.

**Tests INV-NN:** Tests INV-08 (pre-advance-gap burn safety — no pending writes in the pre-gameOver-latch liveness window).

**Depends on SPEC-NN:** Depends on SPEC-01 (the per-day refactor preserves the existing `:491` guard verbatim; no change to the livenessTriggered check).

**Foundry function name:** `testFuzz_EDGE_12_BurnDuringLivenessReverts`

### EDGE-13: Zero-rounded ethValueOwed from tiny burn

**Scenario:** Player calls `burn(1)` — i.e., 1 wei sDGNRS — at a moment when `totalSupply` is very large relative to `totalMoney`. Per `_submitGamblingClaimFrom`'s computation `ethValueOwed = (totalMoney * amount) / supplyBefore`, the floor-division rounds to 0 (e.g., `totalMoney = 100 ether`, `amount = 1`, `supplyBefore = 1e30` → `ethValueOwed = (100e18 * 1) / 1e30 = 0`). Per SPEC-04 (b) lock — burn proceeds — the existing `amount == 0` revert at `:754` PRESERVED is the only zero-guard; a zero-rounded `ethValueOwed` from a non-zero `amount` does NOT revert. The burn proceeds with `ethValueOwed = 0` written to `pendingRedemptions[player][D].ethValueOwed` (no change from 0-init) and `pendingByDay[D].ethBase += 0` (no change). The same applies to `burnieOwed` if it rounds to 0 independently.

**Positive assertion:** the call to `burn(1)` succeeds (no revert); `pendingRedemptions[player][D].ethValueOwed` is incremented by 0 (effectively unchanged); `pendingByDay[D].ethBase` is incremented by 0 (effectively unchanged); `balanceOf[player]` decremented by 1; `totalSupply` decremented by 1; lazy-init snapshot fires if this is the first burn of day `D`. A subsequent `claimRedemption(D)` after the eventual day-`D+1` advance pays 0 ETH (`totalRolledEth = 0 * R_{D+1} / 100 = 0`), the `_payEth` early-returns at `:818` (`if (amount == 0) return;`), and `delete pendingRedemptions[player][D]` fires per SPEC-04 (d).

**Negative assertion:** no overflow — `pendingRedemptions[player][D].ethValueOwed` does NOT underflow or overflow on the `+= 0` operation; `pendingByDay[D].ethBase` does NOT corrupt; cumulative `pendingRedemptionEthValue` does NOT change as a result of this burn (`+= 0`); no revert from zero-claim mishandling at any downstream step; the 50% supply cap check at `:763` still uses the snapshot correctly even when `burned == 1` and `supplySnapshot / 2 >> 1`.

**Tests INV-NN:** Tests INV-04 (per-day base correctness — zero contributes zero, sums consistently).

**Depends on SPEC-NN:** Depends on SPEC-04 (b) (zero-rounded `ethValueOwed` burn proceeds; existing `amount == 0` revert at `:754` is the only zero-guard).

**Foundry function name:** `testFuzz_EDGE_13_ZeroRoundedEthValueOwedBurnProceeds`

### EDGE-14: 50% supply cap edge

**Scenario:** Three sub-scenarios. **Sub-scenario 1 (exact cap):** First burn of day `D` is `amount = totalSupply / 2` exactly. Per SPEC-05 lazy-init, `pendingByDay[D].supplySnapshot = totalSupply` at burn-entry time. The cap check at `:763` (`pendingByDay[currentDay].burned + amount > pendingByDay[currentDay].supplySnapshot / 2`) evaluates as `0 + (snapshot/2) > snapshot / 2` which is FALSE — burn succeeds. **Sub-scenario 2 (one wei over cap):** First burn of day `D` is `amount = (totalSupply / 2) + 1`. The cap check evaluates as `0 + (snapshot/2 + 1) > snapshot/2` which is TRUE — revert `Insufficient` (error at `:91` per `contracts/StakedDegenerusStonk.sol`). **Sub-scenario 3 (subsequent same-day burn against snapshot):** First burn of day `D` is `amount_1 = totalSupply / 4` (succeeds, lazy-init snapshot to `totalSupply`, `pendingByDay[D].burned = totalSupply / 4`). Subsequent same-day burn (after `totalSupply` has decreased by `amount_1`) attempts `amount_2 = totalSupply' / 4` where `totalSupply' = totalSupply - amount_1`. The cap check uses the LAZY-INIT snapshot (NOT current `totalSupply`): `burned + amount_2 > snapshot / 2` i.e. `(amount_1) + amount_2 > totalSupply / 2`. Per SPEC-05 lock — the snapshot is immutable for the rest of day `D` — even though current `totalSupply` has decreased, the cap check uses the locked snapshot value. The second burn succeeds if and only if `amount_1 + amount_2 <= totalSupply / 2`.

**Positive assertion:** sub-scenario 1 succeeds with no revert; sub-scenario 2 reverts `Insufficient`; sub-scenario 3 second burn succeeds when `amount_1 + amount_2 <= snapshot / 2` (using the LAZY-INIT snapshot, not the current decreasing `totalSupply`). The cap value is frozen at the first-burn snapshot for the duration of day `D`.

**Negative assertion:** the cap does NOT tighten as same-day burns proceed — i.e., the snapshot does not refresh to the new lower `totalSupply` on the second burn; specifically, captured `pendingByDay[D].supplySnapshot` value after burn 1 is byte-identical to the value after burn 2 (assertEq enforced). No silent overflow on the `pendingByDay[D].burned += amount` accumulator (the slot is `uint128` per SPEC-01; `INITIAL_SUPPLY ≈ 1e30 < uint128.max ≈ 3.4e38` so no overflow).

**Tests INV-NN:** Tests INV-10 (per-day supply cap — total burned in day `D` never exceeds `pendingByDay[D].supplySnapshot / 2`; snapshot immutable for the rest of day `D`).

**Depends on SPEC-NN:** Depends on SPEC-05 (lazy-init snapshot on first burn of day; immutable for the rest of day).

**Foundry function name:** `testFuzz_EDGE_14_SupplyCapExactOneWeiOverAndLazyInit`

### EDGE-15: 160 ETH EV cap edge

**Scenario:** Player accumulates `pendingRedemptions[player][D].ethValueOwed` toward 160 ETH (the `MAX_DAILY_REDEMPTION_EV` constant at `contracts/StakedDegenerusStonk.sol` analog of `:254`) via multiple same-day burns. **Sub-scenario 1 (exact cap):** sequence of burns whose computed `ethValueOwed` values sum to exactly 160 ETH on day `D` — the final burn that brings the running total to exactly 160 ETH succeeds, with `claim.ethValueOwed + ethValueOwed == 160 ether` (the cap check at `:801` is `claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV` — strictly greater-than, so exact equality succeeds). **Sub-scenario 2 (one wei over):** next burn whose `ethValueOwed >= 1` (i.e., would bring the total to 160 ether + 1 wei or more) — the cap check evaluates as `160e18 + ethValueOwed > 160e18` which is TRUE for any `ethValueOwed >= 1` wei — revert `ExceedsDailyRedemptionCap` (error at `:117` per `contracts/StakedDegenerusStonk.sol`).

**Positive assertion:** sub-scenario 1 succeeds; sub-scenario 2 reverts `ExceedsDailyRedemptionCap`. The cap is enforced per `(player, day)` composite key — `pendingRedemptions[player][D].ethValueOwed <= MAX_DAILY_REDEMPTION_EV` holds at every reachable state.

**Negative assertion:** no silent overflow on the cap-check arithmetic (`claim.ethValueOwed + ethValueOwed` is a `uint96 + uint256` mixed-type operation — actually the lhs is implicitly widened to `uint256` for the comparison; no overflow at 160 ether magnitude); the cap check at `:801` MUST fire BEFORE the `claim.ethValueOwed += uint96(ethValueOwed)` assignment at `:803` — verify ordering at IMPL-time per `feedback_verify_call_graph_against_source.md`.

**Tests INV-NN:** Tests INV-11 (per-`(player, day)` EV cap — 160 ETH max).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key `pendingRedemptions[player][day]` makes the per-`(player, day)` cap structurally per-day) + INV-11.

**Foundry function name:** `testFuzz_EDGE_15_EvCapExactOneWeiOver`

### EDGE-16: Cross-day cap reset

**Scenario:** Player burns enough on day `D` to accumulate exactly `pendingRedemptions[player][D].ethValueOwed == 160 ether`. Wall-clock then crosses to day `D+1`. Player then burns again on day `D+1` (after the eventual day-`D+1` advance has fired or before — the cap check is independent of the resolution state). The day-`D+1` burn writes to a DIFFERENT composite-key slot `pendingRedemptions[player][D+1]`, which starts at 0 per SPEC-02 (a fresh storage slot). The cap check at `:801` analog reads `pendingRedemptions[player][D+1].ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV` — `0 + ethValueOwed > 160e18` — and succeeds for any `ethValueOwed <= 160 ether`. The player can again accumulate up to 160 ETH on day `D+1`.

**Positive assertion:** both day-`D` and day-`D+1` burns are allowed up to 160 ETH each; `pendingRedemptions[player][D].ethValueOwed` and `pendingRedemptions[player][D+1].ethValueOwed` are independent storage slots; the per-`(player, day)` cap resets at the day boundary structurally (composite-key keying is what makes the reset happen — no explicit reset-block needed).

**Negative assertion:** day-`D` accumulated value does NOT affect the day-`D+1` cap check — captured `pendingRedemptions[player][D].ethValueOwed` byte-identical before and after the day-`D+1` burn (the day-`D+1` burn cannot mutate the day-`D` slot). No cross-day aliasing in the cap check (the cap check reads `pendingRedemptions[player][currentDay]` which under composite keying is the current-day slot, not a global accumulator).

**Tests INV-NN:** Tests INV-11 (per-`(player, day)` EV cap — cap resets per new day).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key makes the reset structural — no explicit reset block needed; the cap check naturally reads the current-day composite slot which starts at 0).

**Foundry function name:** `testFuzz_EDGE_16_CrossDayCapResetStructural`

### EDGE-17: Burn after resolve same wall-clock day

**Scenario:** Late-day timing scenario distinct from the V-184 attack (EDGE-07). Wall-clock day `D` is in progress. The day-`D`'s `advanceGame` fires at wall-clock 22:58 (i.e., before the day boundary at ~midnight UTC). Under SPEC-03 `dayToResolve = currentDayView() - 1`, so at the 22:58 firing time `currentDayView() == D` and `dayToResolve == D - 1` — the advance writes `redemptionPeriods[D-1].roll = R_D` per SPEC-03 (resolving the PRIOR day's pool, using a roll derived from day-`D`'s VRF word). Per SPEC-04 (c), `delete pendingByDay[D-1]` fires after the write. The player then burns at 23:30 on the same wall-clock day `D` — `game.currentDayView()` still returns `D` — so the burn lands in `pendingByDay[D]` (a key UNTOUCHED by the 22:58 advance, which targeted `pendingByDay[D-1]`); the 23:30 burn writes a fresh `pendingByDay[D]` entry with lazy-init `supplySnapshot = totalSupply` AT 23:30 and `burned = amount`. Eventually wall-clock crosses to `D+1`; day-`D+1`'s `advanceGame` fires (call it day-`D+2`-keyed in REQUIREMENTS.md EDGE-17 wording — the next advance after the 23:30 burn), `currentDayView() == D+1`, `dayToResolve = D`, and `resolveRedemptionPeriod(roll, flipDay, D)` writes `redemptionPeriods[D].roll = R_{D+1}` for the first time. This is the LEGITIMATE late-day-burn flow — distinct from the V-184 ATTACK in EDGE-07 because the 23:30 burn does NOT attempt to re-burn into an already-resolved slot (the 22:58 advance resolved day `D-1`, not day `D`). Under post-refactor per-day keying, BOTH outcomes are safe (no overwrite of any earlier-written rolls): the 23:30 burn → next-day advance resolves `redemptionPeriods[D]` for the first time (no overwrite); the V-184 attack as described in EDGE-07 also produces no overwrite (because the storage-key separation precludes it). The distinguishing assertion in EDGE-17 is that legitimate late-day burns land in the correct (fresh) day-pool and resolve at the correct next advance.

**Positive assertion:** the 23:30 burn writes to `pendingByDay[D]` (fresh slot with lazy-init `supplySnapshot` capturing 23:30 totalSupply and `burned = amount`); the burn does NOT mutate `pendingByDay[D-1]` (which was just resolved at 22:58); the burn does NOT mutate `redemptionPeriods[D-1]` (already written with `R_D`). After wall-clock crosses to `D+1` and day-`D+1`'s advance fires, `dayToResolve = (D+1) - 1 = D`, and the advance writes `redemptionPeriods[D].roll = R_{D+1}` — this is the FIRST-and-ONLY write to `redemptionPeriods[D]`; per SPEC-04 (c) `delete pendingByDay[D]` fires after the write.

**Negative assertion:** `redemptionPeriods[D-1].roll` is byte-identical to its first-write value (`R_D` from the 22:58 advance) after the 23:30 burn AND after the day-`D+1` advance (which writes `redemptionPeriods[D]`, NOT `redemptionPeriods[D-1]`). NO overwrite of `redemptionPeriods[D-1]` is possible from any later burn or advance — the post-refactor storage shape precludes it. This EDGE-NN explicitly distinguishes the legitimate-late-day-burn from the V-184 ATTACK by demonstrating that under BOTH cases (legitimate AND attack-attempt) the post-refactor storage shape produces the same correct outcome: write-once-per-day-slot, no overwrites.

**Tests INV-NN:** Tests INV-01 (write-once roll immutability — `redemptionPeriods[D-1]` and `redemptionPeriods[D]` each written exactly once), INV-04 (per-day base correctness — `pendingByDay[D].ethBase` correctly accumulates the late-day burn), and INV-08 (pre-advance-gap burn safety — the 23:30 burn lands in the correct current-day pool).

**Depends on SPEC-NN:** Depends on SPEC-01 (per-day-keyed `pendingByDay` + per-day-keyed `redemptionPeriods`) + SPEC-03 (`dayToResolve = currentDayView() - 1` derivation) + SPEC-04 (c) (delete-at-resolve).

**Foundry function name:** `testFuzz_EDGE_17_LateDayBurnPostResolveLegitimate`

### EDGE-18: BURNIE pool insufficient at claim

**Scenario:** Player A burns on day `D`, writing `pendingRedemptions[A][D].burnieOwed > 0` (i.e., the player is owed some BURNIE on resolve). Day-`D+1`'s advance fires and resolves with `R_{D+1}`. Day-`D+1`'s coinflip resolves with `flipResolved == true && flipWon == true && rewardPercent != 0` — so `burniePayout = (claim.burnieOwed * R_{D+1} * (100 + rewardPercent)) / 10000` is non-zero. Player A calls `claimRedemption(D)`. By the time the claim fires, the contract's BURNIE balance `coin.balanceOf(address(this))` is less than `burniePayout` — perhaps because other claims drained the pool, or because the coinflip pool hasn't pushed enough to sStonk yet. The `_payBurnie` helper at `contracts/StakedDegenerusStonk.sol:842-852` handles the shortfall via the existing fallback: transfer the available `payBal = burnieBal` amount; for the `remaining = amount - payBal`, call `coinflip.claimCoinflipsForRedemption(address(this), remaining)` to push the shortfall from the coinflip pool to sStonk; then `coin.transfer(player, remaining)` for the rest.

**Positive assertion:** the call to `claimRedemption(D)` succeeds (no revert); `_payBurnie` pays the player exactly `burniePayout` in total via the two-step fallback (`payBal` from sStonk balance, `remaining` from coinflip-pool-redemption); the player receives the full `burniePayout` amount as BURNIE token transfers; the ETH payout via `_payEth` succeeds as normal.

**Negative assertion:** no revert from BURNIE-pool insufficiency; no stuck claim; the `claimCoinflipsForRedemption` fallback path at `:850` executes correctly under the SPEC-02 + SPEC-04 (d) lock — the existing `_payBurnie` is preserved verbatim per the SPEC-02 "_payEth and _payBurnie flows downstream of the claim are UNCHANGED" lock; the only conceivable revert from `_payBurnie` is `TransferFailed` (error at `:97`) if the `coin.transfer` calls themselves fail at the ERC20 level — but under normal conditions both transfers succeed and the player is paid in full.

**Tests INV-NN:** Tests INV-03 (BURNIE conservation — the `_payBurnie` fallback correctly conserves BURNIE across the sStonk balance + coinflip-pool-claim transitions; no BURNIE leakage; no double-payment).

**Depends on SPEC-NN:** Depends on SPEC-02 (composite-key claim preserves the existing `_payBurnie` flow unchanged; no behavioral change to BURNIE shortfall handling).

**Foundry function name:** `testFuzz_EDGE_18_BurniePoolInsufficientFallback`

### §1↔§3 cross-link coverage table

Every INV-01..12 has at least one EDGE-NN exerciser. Plan 05 grep-verifies the row count and the per-INV-NN coverage. Each row reads "INV-NN ← EDGE-NN [+ EDGE-NN ...]" listing the §3 EDGE-NN entries that test the §1 INV-NN.

- INV-01 ← EDGE-07 + EDGE-17
- INV-02 ← EDGE-09 + EDGE-10
- INV-03 ← EDGE-18
- INV-04 ← EDGE-03 + EDGE-04 + EDGE-13 + EDGE-17
- INV-05 ← EDGE-01 + EDGE-04 + EDGE-09
- INV-06 ← EDGE-04 + EDGE-07 + EDGE-11
- INV-07 ← EDGE-03 + EDGE-05 + EDGE-06 + EDGE-07 + EDGE-10
- INV-08 ← EDGE-01 + EDGE-02 + EDGE-12 + EDGE-17
- INV-09 ← EDGE-02 + EDGE-06
- INV-10 ← EDGE-14
- INV-11 ← EDGE-15 + EDGE-16
- INV-12 ← EDGE-08

## §4 — Design-Intent Backward-Trace + Actor Game-Theory Walk

> Per `feedback_design_intent_before_deletion.md`, every deletion must trace ORIGINAL DESIGN INTENT + ACTOR GAME-THEORY across all (timing × state) combinations BEFORE the deletion is locked. §4 is the audit-trail proof that each of the 7 v44.0 deletions enumerated in §2.7 has been reasoned through — not just removed because the post-refactor code path doesn't need it. Each subsection captures four labeled fields: **ORIGINAL DESIGN INTENT** at the v43.0 baseline `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`, **ACTOR GAME-THEORY WALK** across (timing × state) combinations the original artifact was guarding or enabling, **POST-REFACTOR REPLACEMENT** naming the SPEC-NN lock that subsumes the deletion, and **DELETION SAFETY ATTESTATION** proving no game-theoretic scenario re-introduces the deleted behavior. §4 is the EXCEPTION zone for `feedback_no_history_in_comments.md` — pre-refactor narration appears ONLY here, under explicit `ORIGINAL DESIGN INTENT` labels; §1/§2/§3/§5 prose describes the POST-REFACTOR state only.

### Deletion 1: `redemptionPeriodIndex` storage slot (`StakedDegenerusStonk.sol:230` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** Declared at `:230` as `uint32 internal redemptionPeriodIndex`. The slot identifies the "current redemption period" — used by `_submitGamblingClaimFrom` as both (a) the period key into `redemptionPeriods[period]` for already-resolved rolls and (b) the storage key embedded in the player's `pendingRedemptions[player].periodIndex` field (verbatim from RNGLOCK-FIXREC §103.A line 5414). The original author advanced this slot at burn time ONLY on day-boundary transition (the `:757-762` reset block) and read it in `resolveRedemptionPeriod` as the resolve target (`:588` `uint32 period = redemptionPeriodIndex;`). Per RNGLOCK-FIXREC §103.A line 5414, the slot is mutated by a single writer — `_submitGamblingClaimFrom` at `:760`. The embedded assumption: one roll resolves all burns in a period, and the index self-advances via the day-boundary check.

**ACTOR GAME-THEORY WALK:** The walk reproduces RNGLOCK-FIXREC §103 V-184 verbatim across the (timing × state) combinations the single-pool indirection slot was enabling.

- **Setup — Day D, honest burner Player A (timing: pre-day-D-advance; state: `pendingRedemptionEthBase == 0`, `redemptionPeriods[D].roll == 0`):** Player A burns 100 sDGNRS. `currentPeriod = D`; `redemptionPeriodIndex` was 0 or some earlier day; `:758` triggers reset → `redemptionPeriodIndex = D`. `pendingRedemptionEthBase += ethValueOwed_A`. `claim_A.periodIndex = D`, `claim_A.ethValueOwed = ethValueOwed_A` (RNGLOCK-FIXREC §103.A lines 5445-5449).
- **Day-D advance — advance-stack caller (timing: rngGate fires; state: `hasPendingRedemptions() == true`):** `resolveRedemptionPeriod(roll_D, D+1)` runs. `period = redemptionPeriodIndex = D` (`:588`); `redemptionPeriods[D] = {roll: roll_D, flipDay: D+1}` (`:604`); `pendingRedemptionEthBase = 0` (`:594`). **Critical: `redemptionPeriodIndex` NOT mutated — REMAINS at `D`** (RNGLOCK-FIXREC §103.A line 5455). No "this period was already resolved" marker is set.
- **Decision point — informed attacker Player B (timing: same-day post-resolve, pre-day-boundary; state: `redemptionPeriods[D].roll != 0`, `pendingRedemptionEthBase == 0`):** Attacker reads `redemptionPeriods[D].roll` via the public mapping auto-getter at `:222`. If `roll_D >= 100` (favorable): CLAIM IMMEDIATELY via `claimRedemption()` — lock in the favorable roll. If `roll_D < 100` (unfavorable): proceed to re-arm. Informed-re-roll filter activates: only 50% of cases trigger re-roll (RNGLOCK-FIXREC §103.B line 5472).
- **Re-arm — same-day post-resolve re-burn Player B (timing: still wall-clock day D; state: `redemptionPeriodIndex == currentPeriod == D` because advance did NOT update the slot):** Player B burns 1 wei. `currentPeriod = D`; `redemptionPeriodIndex (D) == currentPeriod (D)` → `:758` conditional FALSE → NO reset → `redemptionPeriodSupplySnapshot` stays frozen + `redemptionPeriodBurned` keeps accumulating + `redemptionPeriodIndex` stays at `D`. `pendingRedemptionEthBase += 1-wei-proportional` (NOW NON-ZERO again). `claim_B.periodIndex = D` (attached to already-resolved period; RNGLOCK-FIXREC §103.A lines 5457-5461).
- **Re-roll fire — day-D+1 advance-stack caller (timing: next-day rngGate; state: `pendingRedemptionEthBase != 0` again, `redemptionPeriodIndex == D` stale):** `rngGate` runs because `rngWordByDay[D+1] == 0`. Branch at `:1225` `if (sdgnrs.hasPendingRedemptions())` → TRUE (re-burn set `pendingRedemptionEthBase != 0`). `resolveRedemptionPeriod(roll_{D+1}, D+2)` invoked. Inside resolver: `period = redemptionPeriodIndex = D` (STALE — still pointing at day D); `pendingRedemptionEthBase != 0` (from re-arm), so early-return at `:589` is BYPASSED; `redemptionPeriods[D] = {roll: roll_{D+1}, flipDay: D+2}` — **OVERWRITES** the original `roll_D` with the fresh `roll_{D+1}`.
- **Claim — Player A and the attacker (timing: post day-D+1 advance; state: `redemptionPeriods[D].roll == roll_{D+1}` — a different value than what was emitted in the day-D `RedemptionResolved` event):** When Player A calls `claimRedemption()`, they read `redemptionPeriods[D].roll = roll_{D+1}` and their `ethValueOwed` is multiplied by the FRESH `roll_{D+1}` — even though Player A burned BEFORE the day-D resolution. Attacker likewise claims at the fresh roll.
- **EV asymmetry:** Per RNGLOCK-FIXREC §103.B line 5473, `0.5 × E[roll | roll ≥ 100] + 0.5 × E[roll | re-roll] = 0.5 × 137.5 + 0.5 × 100 = 118.75` vs baseline `100` = **~18.75% positive EV per round** (rounded to ~19% in headline). Re-arm cost is 1 wei sDGNRS (dust); attack is statistically free; iteration ceiling bounded only by the 50% supply cap and the 175% max roll (RNGLOCK-FIXREC §103.B line 5474).
- **Collateral damage — Player C (timing: burned on day D; state: `claim_C.periodIndex = D`, hadn't yet called `claimRedemption()`):** Player C is forced into the re-rolled outcome WITHOUT consent. Player C's `roll_D` becomes `roll_{D+1}` after the re-resolve — data-corruption-class behavior independent of EV-asymmetry (RNGLOCK-FIXREC §103.A line 5478).
- **Same-day rngWordByDay short-circuit (timing: any same-day; state: `rngWordByDay[D] != 0`):** AdvanceModule:1187 `if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);` prevents `rngGate` from re-running on day D's RNG slot — but the cross-day re-resolution is on day D+1's rngGate, which executes normally. The rngWordByDay short-circuit does NOT defend against V-184 (RNGLOCK-FIXREC §103.A line 5476).
- **Supply cap binding (timing: across many re-rolls; state: cumulative `redemptionPeriodBurned`):** `:763` cap binds on VOLUME, not on COUNT of re-rolls. 1-wei re-burns accumulate negligibly — cap does NOT prevent the attack (RNGLOCK-FIXREC §103.B line 5511).

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (DayPending struct shape — per-day pool keyed by `uint32` day)** + **SPEC-03 (`dayToResolve` arg on `resolveRedemptionPeriod`)** + **SPEC-04 (c) (`delete pendingByDay[dayToResolve]` at resolve)**. The single-pool indirection slot is REPLACED by `mapping(uint32 => DayPending) internal pendingByDay` keyed directly by the day. There is no "current period" indirection slot to go stale; every day's pool lives in its own mapping entry. `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)` takes the day explicitly per SPEC-03 with `dayToResolve = currentDayView() - 1` passed at every AdvanceModule call site (`:1230`/`:1293`/`:1323`). SPEC-04 (c) `delete pendingByDay[dayToResolve]` after `redemptionPeriods[D]` written + `RedemptionResolved` emitted closes the re-arm window — any subsequent same-day burn writes to `pendingByDay[currentDayView()] == pendingByDay[D]`, which is now empty, but the next-day advance passes `dayToResolve = currentDayView() - 1 == D` again only ONCE (AdvanceModule's catch-up loop iterates strictly forward by day; oldest-first; no rollback path).

**DELETION SAFETY ATTESTATION:** **INV-01 (write-once roll immutability)** + **INV-06 (no cross-player roll manipulation)** + **INV-07 (no self-roll manipulation via timing)** + **EDGE-07 (V-184 attack reproduction — NEGATIVE assertion: `redemptionPeriods[D].roll` byte-identical to first-write value `R_{D+1}` enforced via `assertEq` at every attack-sequence checkpoint)** jointly attest that no actor under any (timing × state) combination can re-arm an already-resolved period. Per §2.0 Priority Statement clause 1, V-184 closure is STRUCTURAL — the post-refactor storage shape forecloses the overwrite primitive itself (every day's resolve writes a distinct `redemptionPeriods[D]` slot bounded by the per-day key); there is no "stale index" indirection to corrupt. The closure does not depend on a runtime check (no `BurnsBlockedAfterResolution` revert is added); it derives from the storage-shape change alone. Phase 305 IMPL is the consumer that materializes this deletion in the diff; Phase 306 TST-04 / TST-05 / EDGE-07 are the negative tests that prove it.

### Deletion 2: `redemptionPeriodSupplySnapshot` storage slot (`StakedDegenerusStonk.sol:229` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** Declared at `:229` as `uint256 internal redemptionPeriodSupplySnapshot`. Snapshots `totalSupply` on the first burn of each day so the 50% supply cap evaluated at `:763` (`redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2`) tests against a FROZEN baseline rather than against the LIVE `totalSupply` (which decreases as burns proceed and would auto-tighten the cap across same-day burns). Lazy-initialized inside the `:757-762` reset block when `redemptionPeriodIndex != currentPeriod` (first burn of a new wall-clock day); immutable for the rest of the day by construction. The embedded assumption: a single per-period denominator is the right shape for capping cumulative same-day burn volume against a stable supply reference.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the snapshot was guarding or enabling.

- **Honest first-of-day burner (timing: first burn of day D; state: `redemptionPeriodIndex != currentPeriod`):** Trips the `:758` conditional → `redemptionPeriodSupplySnapshot = totalSupply`. The denominator is fixed for the rest of day D. Subsequent same-day burners check `redemptionPeriodBurned + amount > snapshot / 2` against the frozen denominator.
- **Late-day honest burner (timing: same-day, mid-period; state: snapshot frozen, `redemptionPeriodBurned > 0`):** Cap binds against day-D's `totalSupply` as captured at first burn. If the snapshot were LIVE (re-read on each burn), early burners would shrink `totalSupply` and proportionally shrink the cap denominator — disadvantaging late legitimate burners against an arbitrarily-tightened denominator. The lazy-init snapshot preserves a uniform burn allowance across all same-day participants.
- **Hypothetical front-running attacker (timing: same-day, pre-first-burn-of-day; state: attacker observes mempool first-burn-of-day call):** Could the attacker inflate the snapshot by manipulating `totalSupply` before the first burn? `totalSupply` is mutated only by mint (constructor + supply-init paths) and burn (`_submitGamblingClaimFrom :784`); there is no public mint path post-launch. So the snapshot value is determined by the first-burner's timing alone. The `:758-762` reset is unconditional on first-burn-of-day, so the snapshot is taken at the moment the day boundary is crossed regardless of which actor causes it. No actor can inflate or deflate the snapshot beyond what `totalSupply` reads at that single first-burn moment.
- **V-184 attacker interaction (timing: same-day post-resolve re-burn; state: `redemptionPeriodIndex == currentPeriod` so `:758` conditional FALSE; snapshot unchanged):** Under the V-184 exploit, the snapshot stays frozen at day D's first-burn value even through same-day post-resolve re-burns. The cap continues to bind against day-D's `totalSupply` baseline. The supply-snapshot was a defense against runaway intra-period volume (RNGLOCK-FIXREC §103.B line 5511 — "cap bounds intra-period magnitude but does not prevent repeated 1-wei re-burns"); it did NOT prevent the re-roll EV asymmetry because the attack operates on 1-wei dust burns that accumulate negligibly against the cap.
- **Cross-day legitimate burner (timing: first burn of day D+1; state: `redemptionPeriodIndex (D) != currentPeriod (D+1)`):** `:758` fires → `redemptionPeriodSupplySnapshot = totalSupply` re-snapshots against day-D+1's post-burns baseline. The cap restarts at day-D+1's `snapshot / 2`.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (DayPending struct shape — `pendingByDay[D].supplySnapshot` field, `uint128` slot 3 first half)** + **SPEC-05 (supply-snapshot lazy-init timing — first burn of day D when `pendingByDay[D].supplySnapshot == 0 && pendingByDay[D].burned == 0`, immutable rest of day)**. Identical semantics; new home. The slot-zero predicate replaces the index-change predicate one-for-one: each day's `pendingByDay[D]` entry starts at default-zero per Solidity mapping semantics, so the lazy-init test is the slot reading zero rather than a separate index slot changing.

**DELETION SAFETY ATTESTATION:** **INV-10 (per-day supply cap)** + **EDGE-14 (50% supply cap edge — burn exactly cap succeeds, one wei over reverts `Insufficient`; lazy-init snapshot immutable rest of day verified by burning across multiple same-day participants and asserting `pendingByDay[D].supplySnapshot` byte-identical at each burn site)** attest that the cap-denominator behavior is byte-equivalent under per-day keying. The supply-snapshot's role as "frozen denominator for the day's burn allowance" is preserved verbatim — only its physical slot location changes (from a single per-contract `uint256` to a per-day `uint128` field inside `DayPending`). The non-future-extensibility posture per `feedback_frozen_contracts_no_future_proofing.md` is honored: no migration-friendly fallback to read both the old slot and the new field; the slot is gone, redeploy-fresh.

### Deletion 3: `redemptionPeriodBurned` storage slot (`StakedDegenerusStonk.sol:231` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** Declared at `:231` as `uint256 internal redemptionPeriodBurned`. Tracks cumulative sDGNRS burned within the current day's redemption period. Read at `:763` (`redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2`) as the LHS of the 50% supply cap inequality; incremented on each burn at `:764` (`redemptionPeriodBurned += amount`); reset to 0 inside the `:757-762` block on first burn of a new day. The embedded assumption: a single per-period accumulator paired with the per-period snapshot denominator (Deletion 2) is the right shape for enforcing the cap.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the cumulative-burn counter was guarding or enabling.

- **Honest same-day burn sequence (timing: multiple burns within day D; state: `redemptionPeriodBurned` strictly increasing):** Each burn accumulates `redemptionPeriodBurned += amount`. When cumulative exceeds `redemptionPeriodSupplySnapshot / 2`, the next burn reverts `Insufficient`. The cap binds on TOTAL volume burned same-day, not on count of burns nor on per-actor share.
- **Cap-bypass attempt — mid-day reset (timing: same-day after partial burn; state: `redemptionPeriodBurned > 0`):** No actor can reset `redemptionPeriodBurned` mid-day. The `:758` conditional only fires when `redemptionPeriodIndex != currentDayView()`, which requires a wall-clock day boundary to be crossed. There is no burn-path branch that zeroes the counter intra-day.
- **Cap-bypass attempt — many small burns (timing: many same-day burns; state: each burn negligible amount):** Cap is amount-aggregate, not count-aggregate. Burning 1000 × 100 sDGNRS is identical to one 100,000-sDGNRS burn for cap purposes. No game-theoretic bypass.
- **V-184 attacker interaction (timing: same-day post-resolve 1-wei re-burns; state: `redemptionPeriodBurned + 1 wei`):** Attacker's 1-wei re-burns increment `redemptionPeriodBurned` by negligible amounts. The cap binds on VOLUME, not on COUNT, so the cap does NOT prevent the V-184 attack (RNGLOCK-FIXREC §103.B line 5511 — "cap bounds intra-period magnitude but does not prevent repeated 1-wei re-burns"). The counter was an orthogonal defense (against runaway volume), not against the re-roll mechanic.
- **Cross-day reset — first burn of day D+1 (timing: day-boundary tick; state: `redemptionPeriodIndex (D) != currentPeriod (D+1)`):** `:761` fires → `redemptionPeriodBurned = 0`. Day-D+1 burns restart cap counting from 0 against day-D+1's snapshot. Legitimate cross-day burners are not penalized by day-D's accumulation.
- **Skipped-advance edge (timing: many days pass with no burns; state: `redemptionPeriodIndex` lags many days behind `currentDayView()`):** First burn of the catch-up day fires the reset block; both snapshot and burned-counter re-initialize to day-of-burn baseline. The slot does NOT preserve cross-day accumulation across skipped periods.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (DayPending struct shape — `pendingByDay[D].burned` field, `uint128` slot 3 second half)**. Each day's burned counter lives in its own per-day mapping entry. No cross-day reset block needed; new-day entries default to `burned = 0` via Solidity's default-zero mapping semantics. The counter's role is preserved verbatim — only the physical slot location changes (from a single per-contract `uint256` to a per-day `uint128` field).

**DELETION SAFETY ATTESTATION:** **INV-10 (per-day supply cap)** + **EDGE-14 (50% supply cap edge — burn exactly cap succeeds, +1-wei reverts `Insufficient`)** + **EDGE-16 (cross-day cap reset — burn 160 ETH on day D + burn 160 ETH on day D+1 both succeed independently)** jointly attest that the cap-counter behavior is byte-equivalent under per-day keying AND that the cross-day reset is now STRUCTURAL (Solidity default-zero) rather than block-conditional (the `:761` reset). The structural-reset property is strictly safer than the block-conditional one — there is no `:758` conditional whose mis-evaluation could fail to reset the counter; each day's mapping entry is independent by construction.

### Deletion 4: `pendingRedemptionEthBase` storage slot (`StakedDegenerusStonk.sol:226` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** Declared at `:226` as `uint256 internal pendingRedemptionEthBase`. Holds the segregated ETH base for the CURRENT unresolved period — the "what's at stake on the next roll" register. Cleared on resolve at `:594` (`pendingRedemptionEthBase = 0` after the `(ethBase * roll) / 100` is computed and folded into `pendingRedemptionEthValue` at `:593`); incremented on burn at `:790` (`pendingRedemptionEthBase += ethValueOwed`). `resolveRedemptionPeriod` reads it at `:592` and multiplies by `roll / 100` to compute the rolled outcome; the early-return short-circuit at `:589` (`if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;`) uses it as the "nothing pending, skip resolve" signal. The embedded assumption: a single per-contract pool of "next-roll ETH" is the right shape for the resolver's input.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the single-pool ETH base was guarding or enabling.

- **Honest same-day burn (timing: any time before day-D advance; state: `pendingRedemptionEthBase >= 0`):** Each burn increments this slot; multiple same-day burners contribute additively; the cumulative value is the day-D ETH pool the resolver will roll on.
- **Day-D advance resolution (timing: rngGate fires; state: `pendingRedemptionEthBase != 0` if any same-day burns occurred):** Resolver reads the slot, multiplies by roll, writes rolled value into `pendingRedemptionEthValue` (`:593`), clears the slot (`:594`). The slot's role as the "consumed-at-resolve register" is preserved verbatim under the v43.0 design.
- **V-184 attacker — same-day post-resolve re-burn (timing: wall-clock day D, after `resolveRedemptionPeriod` has cleared the slot; state: `pendingRedemptionEthBase == 0`, `redemptionPeriods[D].roll != 0`):** Attacker burns 1 wei → `pendingRedemptionEthBase += 1-wei-proportional-eth` (now NON-ZERO again, RNGLOCK-FIXREC §103.B step 4 line 5494). The slot's single-pool nature is what enables the V-184 cross-day re-roll: there is NO day-keyed separation between the just-resolved period and the new pending burns. The slot's "current unresolved period" framing assumes period boundaries are tracked by `redemptionPeriodIndex` (Deletion 1) — when that index goes stale post-resolve, the ETH base re-arms inside the stale period's accounting.
- **Day-D+1 advance — re-roll fire (timing: next-day rngGate; state: `pendingRedemptionEthBase != 0` from re-arm, `redemptionPeriodIndex == D` stale):** `resolveRedemptionPeriod` re-runs with `period = redemptionPeriodIndex = D`. Early-return at `:589` bypassed because the base is non-zero. Resolver writes `redemptionPeriods[D] = {roll: roll_{D+1}}` — overwriting the original `roll_D` (RNGLOCK-FIXREC §103.B step 5 line 5500-5506). The single-pool ETH base is the carrier of the re-arm primitive.
- **Honest cross-day burner (timing: first burn of day D+1; state: `pendingRedemptionEthBase` accumulating with day-D+1 contributions):** Day-D+1 burner increments the slot AFTER the `:757-762` reset block fires (which resets snapshot + counter + index, but NOT the ETH base — the base is reset only by resolve at `:594`). The day-D+1 resolve at day-D+2 advance consumes the day-D+1 contributions. Works correctly because at day-D+2 advance time the slot represents day-D+1's pool only (no V-184 attack scenario contributing to the day-D+1 pool).
- **`hasPendingRedemptions()` reader (timing: any pre-advance; state: `pendingRedemptionEthBase` either zero or non-zero):** Public view at `:578` reads `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0`. The AdvanceModule call site at `:1225` (`if (sdgnrs.hasPendingRedemptions())`) uses this to gate the resolve. Under V-184 post-resolve re-arm, the reader returns TRUE because the base is non-zero — gating the day-D+1 resolve invocation.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (`pendingByDay[D].ethBase` field — `uint256` slot 0 of the `DayPending` struct)**. Each day's ETH base lives in its own mapping entry. The cross-day pool conflation that V-184 exploited is STRUCTURALLY impossible: same-day post-resolve re-burns under SPEC-04 (c) `delete pendingByDay[D]` at resolve write to a freshly-zero `pendingByDay[currentDayView()]` entry, and the next-day advance passes `dayToResolve = currentDayView() - 1` to `resolveRedemptionPeriod`, which reads `pendingByDay[dayToResolve]` — not a stale single-pool slot.

**DELETION SAFETY ATTESTATION:** **INV-04 (per-day base correctness — unresolved-day pre-condition)** + **INV-08 (pre-advance-gap burn safety — burns during the post-resolve / pre-day-boundary gap land in `pendingByDay[currentDayView()]`, not in the just-resolved day's pool)** + **EDGE-01 (pre-advance-gap burn on day D lands in `pendingByDay[D]`, NOT `pendingByDay[D-1]`)** + **EDGE-02 (two pending days simultaneously — day-D advance resolves D-1 only; `pendingByDay[D]` byte-identical pre/post advance)** + **EDGE-07 (V-184 attack reproduction — `pendingByDay[D].ethBase` cannot be re-armed once `delete pendingByDay[D]` fires at resolve; any subsequent same-wall-clock-day burn writes to `pendingByDay[currentDayView()]` which is a different mapping entry)** jointly attest that per-day ETH pools never leak into each other and that the V-184 re-arm primitive is foreclosed by the storage shape itself.

### Deletion 5: `pendingRedemptionBurnieBase` storage slot (`StakedDegenerusStonk.sol:227` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** Declared at `:227` as `uint256 internal pendingRedemptionBurnieBase`. BURNIE analog of `pendingRedemptionEthBase` (Deletion 4) — segregated BURNIE base for the current unresolved period. Cleared on resolve at `:601` (`pendingRedemptionBurnieBase = 0` after computing `burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100` at `:597` and releasing the cumulative reserve at `:600` `pendingRedemptionBurnie -= pendingRedemptionBurnieBase`); incremented on burn at `:792` (`pendingRedemptionBurnieBase += burnieOwed`). `resolveRedemptionPeriod` reads it at `:597` and multiplies by `roll / 100`; the resulting `burnieToCredit` is emitted in `RedemptionResolved` (`:609`) and paid out on claim via `_payBurnie` if the coinflip resolves favorably. The embedded assumption: BURNIE and ETH share the SAME `roll` (the percentage applied at resolve is identical for both bases), so the slot's lifecycle mirrors `pendingRedemptionEthBase` one-for-one.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the BURNIE base was guarding or enabling, with explicit attention to the BURNIE-side of the V-184 attack.

- **Honest BURNIE-claimer (timing: same-day burn → day-D advance → claim with favorable coinflip; state: `pendingRedemptionBurnieBase` accumulates → consumed at resolve → `burnieOwed` paid via `_payBurnie`):** Each burn segregates BURNIE proportionally (`:779-792`); resolve consumes (`:597-601`); claim pays out on coinflip win (`:649-654`). The slot's role is preserved verbatim under v43.0 design.
- **V-184 attacker — BURNIE side of the exploit (timing: same-day post-resolve 1-wei re-burn; state: `pendingRedemptionBurnieBase == 0` post-resolve, then re-armed to non-zero):** Same mechanic as Deletion 4 — same-day post-resolve re-burn re-arms this slot at `:792`. Next-day advance includes the stale re-arming in its resolve computation. The `R_{D+1}` overwrite at `redemptionPeriods[D]` scales BOTH the ETH side and the BURNIE side because the resolver uses the SAME `roll` for both bases. So the V-184 EV asymmetry applies to BURNIE payouts as well — not just to ETH.
- **Coinflip-decoupled actor (timing: any time post-resolve; state: BURNIE roll-adjusted value committed but coinflip-day result not yet known):** BURNIE payout depends on the SEPARATE coinflip outcome at `flipDay` (per `:651-654` `coinflip.previewClaimCoinflips()` read + `redemptionPeriods[period].flipDay` lookup). The V-184 ETH-side exploit and the coinflip outcome are statistically independent — the attacker controls the re-roll but not the coinflip. Net BURNIE EV = (V-184 re-roll EV) × (coinflip win probability) = ~19% × 50% = ~9.5% per round on the BURNIE side. The combined ETH + BURNIE EV is the headline ~19% (ETH dominates by economic magnitude per `feedback_skeptic_pass_before_catastrophe.md` 3-condition EV lens, but the BURNIE side is not zero).
- **BURNIE-pool insufficient at claim (timing: claim; state: `coin.balanceOf(address(this)) < burnieOwed`):** `_payBurnie` fallback chain at `:842-852` reads coinflip pool via `coinflip.claimCoinflipsForRedemption()` to top up. The V-184 attack does not interact with this fallback — the BURNIE pool magnitude is unchanged by the re-roll; only the `roll`-multiplied `burnieToCredit` per claim is affected.
- **`pendingRedemptionBurnie` cumulative reserve (timing: across all unresolved periods; state: `pendingRedemptionBurnie = sum of all unresolved BURNIE bases`):** `:600` releases the reservation at resolve. Under V-184, the same-day post-resolve re-burn at `:791` `pendingRedemptionBurnie += burnieOwed` adds 1-wei-proportional to the reserve; the next-day advance's `:600` releases that 1-wei-proportional. Net reserve accounting is correct each iteration; the V-184 corruption is to the `roll` magnitude, not to the reserve total.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (`pendingByDay[D].burnieBase` field — `uint256` slot 1 of the `DayPending` struct)**. Each day's BURNIE base lives in its own mapping entry. Same structural foreclosure of the V-184 re-arm as Deletion 4: SPEC-04 (c) `delete pendingByDay[D]` at resolve zeroes the entry; same-wall-clock-day re-burns write to a separate mapping entry (`pendingByDay[currentDayView()]`), and the next-day advance reads `pendingByDay[dayToResolve = currentDayView() - 1]` — not a stale single-pool slot.

**DELETION SAFETY ATTESTATION:** **INV-03 (BURNIE conservation — resolve-time release; for every (D, P) the BURNIE-claimable amount equals `burnieOwed` committed at burn time multiplied by `roll / 100` from day-D's first-write `redemptionPeriods[D].roll`)** + **INV-04 (per-day base correctness)** + **EDGE-04 (multiple players burn same day, different times relative to advance — both burns land in `pendingByDay[D]`, same `R_{D+1}` applied to both)** + **EDGE-18 (BURNIE pool insufficient at claim — `_payBurnie` fallback chain via `coinflip.claimCoinflipsForRedemption` preserved)** jointly attest that BURNIE pool semantics are byte-equivalent under per-day keying. The BURNIE-side of V-184 is closed by the SAME structural lock as the ETH side (SPEC-01 + SPEC-03 + SPEC-04 (c)) — no separate BURNIE-specific defense is required.

### Deletion 6: `UnresolvedClaim` revert (`StakedDegenerusStonk.sol:796-797` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** The revert block at `:796-797` reads `if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) revert UnresolvedClaim();` (error declared at `:108`). Under pre-refactor single-key `mapping(address => PendingRedemption) public pendingRedemptions` at `:221`, a player could only have ONE pending claim at a time — the player's slot held `{ethValueOwed, burnieOwed, periodIndex, activityScore}` for whatever period they last burned in. The revert prevented a player who had an UNRESOLVED claim from day D from submitting a NEW claim on day D+1, because the new claim would OVERWRITE the old one in the single-key mapping (clobbering `ethValueOwed_D` with `ethValueOwed_{D+1}` for an entirely different period's roll). This was both a UX guardrail (forcing the player to wait for day-D's advance + claim before submitting day-D+1's burn) AND a safety guardrail (preventing accidental loss of pending value via mapping-entry overwrite). The same-period accumulation case is permitted: the condition `claim.periodIndex != currentPeriod` allows a player to ADD to an existing same-period claim (`claim.periodIndex == currentPeriod`) — only cross-period accumulation reverts.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the revert was guarding.

- **Honest cross-day accumulator (timing: day-D+1 burn; state: `claim.periodIndex == D` (day-D burn unresolved, advance hasn't fired yet), `currentPeriod == D+1`):** Hits the revert (`D != 0 && D != D+1`). Friction but no economic harm — the player must wait for day-D's advance + claim before burning on day D+1.
- **Honest same-period accumulator (timing: second burn same day; state: `claim.periodIndex == currentPeriod == D`):** Bypasses revert (condition `D != currentPeriod` is FALSE). The accumulating burn adds to the existing claim slot via `claim.ethValueOwed += uint96(ethValueOwed)` at `:803`. This is the SAFE same-period stacking path the revert deliberately permits.
- **First-ever burner (timing: first burn ever; state: `claim.periodIndex == 0`):** Bypasses revert (condition `claim.periodIndex != 0` is FALSE — the `!= 0` first-clause exists specifically to permit the fresh-claim case). Then proceeds to set `claim.periodIndex = currentPeriod` somewhere on the burn path.
- **Deliberate-stall attacker — hypothetical mid-period overwrite (timing: pre-resolve same-day; state: attacker tries to inflate `ethValueOwed` after observing pending favorable conditions):** This is the attack the revert structurally permits but limits. Under same-period stacking, an attacker CAN add more burn pre-resolve same-day — but this is symmetric: more burn means more `pendingRedemptionEthBase` exposed to the SAME unknown future `roll_D`. There is no informed advantage — the attacker doesn't yet know `roll_D` at burn time. The revert's role is NOT to defend against this (same-period stacking is intentional); the revert defends against cross-period clobbering specifically.
- **Cross-day stall + claim-skip attacker (timing: day-D+1 burn attempt without claiming day-D; state: `claim_D.ethValueOwed > 0`, `claim_D.periodIndex == D`):** The revert blocks this. Without the revert, the day-D+1 burn would overwrite `claim.periodIndex = D+1` and the player would LOSE their day-D `ethValueOwed` (since the single mapping entry now points at day D+1's `redemptionPeriods[D+1].roll`, not day D's). This was a structural UX-and-correctness guardrail at v43.0.
- **`periodIndex == 0` sentinel ambiguity (timing: first-ever burn; state: `claim.periodIndex == 0`):** The `claim.periodIndex != 0` first-clause prevents the revert from firing on the genuine first burn. There is a soft assumption that `currentPeriod` is never 0 in normal operation — this holds because `currentDayView()` returns wall-clock days since launch, and day 0 is launch day with no preceding pending state. No attack surface from the sentinel.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-02 (composite-key `pendingRedemptions[player][day]` mapping + `UnresolvedClaim` revert removal + `claimRedemption(uint32 day)` signature + inner `PendingRedemption` struct loses the `uint32 periodIndex` field at `:212` since the outer mapping key now carries the day)**. Under composite keying, day-D and day-D+1 claims are in SEPARATE mapping entries — there is no overwrite collision to guard against. A player can burn on day D, then burn on day D+1 (without claiming day-D first), and both claims coexist in `pendingRedemptions[player][D]` and `pendingRedemptions[player][D+1]` independently. The revert becomes STRUCTURALLY UNREACHABLE under the new shape; SPEC-02 removes the dead code. The same-period stacking case (the revert's permitted path) is preserved: a second same-day burn still adds to `pendingRedemptions[player][currentDay].ethValueOwed` via the same `+=` accumulator pattern, only now keyed by `[player][currentDay]` instead of `[player]` alone.

**DELETION SAFETY ATTESTATION:** **INV-07 (no self-roll manipulation via timing — for any (P, D) the locked `ethValueOwed` and effective `roll` are byte-identical from burn through claim regardless of intervening burns on other days)** + **EDGE-03 (single player burns multiple days, never claims — each `pendingRedemptions[P][D]` slot independently resolvable; assertion: balances at `D=1`, `D=2`, ..., `D=N` retained byte-identical until each is claimed)** + **EDGE-16 (cross-day cap reset — burn 160 ETH on day D + burn 160 ETH on day D+1 both succeed; both `pendingRedemptions[P][D]` and `pendingRedemptions[P][D+1]` slots populated independently)** jointly attest that cross-day claim accumulation under composite keying does NOT enable any front-run-resolve attack the revert was guarding against. The structural argument: each day's `pendingRedemptions[player][D]` is sealed at burn time (`ethValueOwed` written once per burn, accumulating only within the same-day key) and cannot be retroactively modified once day-D's advance fires (because subsequent burns are routed to `pendingRedemptions[player][D']` for `D' != D`). The revert's UX-guardrail role (forcing claim-before-cross-day-burn) is also rendered obsolete: under composite keying, claiming day-D and burning on day D+1 are independent operations with no ordering constraint, which is a STRICTLY BETTER UX than the v43.0 forced-ordering.

### Deletion 7: `redemptionPeriodIndex` reset block (`StakedDegenerusStonk.sol:757-762` at v43.0 baseline)

**ORIGINAL DESIGN INTENT (v43.0 baseline):** The literal deleted block, with line-by-line breakdown verified against source HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2`:

```solidity
// :757
uint32 currentPeriod = game.currentDayView();
// :758
if (redemptionPeriodIndex != currentPeriod) {
// :759
    redemptionPeriodSupplySnapshot = totalSupply;
// :760
    redemptionPeriodIndex = currentPeriod;
// :761
    redemptionPeriodBurned = 0;
// :762
}
```

Plan 05 grep-verifies this canonical line range against source HEAD. The block lazy-initializes per-day cap state (`redemptionPeriodSupplySnapshot` + `redemptionPeriodBurned`) when the first burn of a new wall-clock day arrives, and advances `redemptionPeriodIndex` to the new day. Per RNGLOCK-FIXREC §103.A line 5414, `:760` is the ONLY writer of `redemptionPeriodIndex` (single-writer attestation). The embedded assumption: a per-period "current day" index + per-period cap state, lazy-initialized on day-boundary transition detected via the `redemptionPeriodIndex != currentPeriod` predicate, is the right shape for per-day cap accounting.

**ACTOR GAME-THEORY WALK:** The walk enumerates the (timing × state) combinations the reset block was guarding or enabling, with explicit attention to V-184 because this block is the STRUCTURAL ENABLER of that attack.

- **Honest first-of-day burner (timing: first burn of day D; state: `redemptionPeriodIndex` lags at D-1 or earlier):** Trips the reset (`:758` conditional TRUE). Snapshot + counter + index initialized to day-D baseline.
- **Honest subsequent same-day burner (timing: second+ burn of day D; state: `redemptionPeriodIndex == currentPeriod == D`):** Skips the reset (`:758` conditional FALSE). Accumulates against the existing snapshot. Cap binds correctly against day-D's first-burn baseline.
- **V-184 attacker — STRUCTURAL ENABLER (timing: same-day post-resolve re-burn; state: `redemptionPeriodIndex == currentPeriod == D` because resolver does NOT advance the index, RNGLOCK-FIXREC §103.A line 5455):** Because `resolveRedemptionPeriod` does NOT advance `redemptionPeriodIndex` (it only WRITES `redemptionPeriods[period]`), the index LAGS the resolved-period boundary by exactly one day. The same-day post-resolve 1-wei re-burn SKIPS the reset block (the `:758` conditional `redemptionPeriodIndex != currentPeriod` evaluates to `D != D == false`), re-arming `pendingRedemptionEthBase` (Deletion 4) and `pendingRedemptionBurnieBase` (Deletion 5) WITHOUT updating any "this period was already resolved" marker. The next-day advance then operates on the stale index. **This is the structural primitive that enables the V-184 attack: the reset block's predicate cannot distinguish "first burn of fresh day D" from "post-resolve re-burn on same wall-clock day D" — both look identical from the predicate's vantage point because `redemptionPeriodIndex == currentPeriod` in both cases.**
- **RNGLOCK-FIXREC §103.C tactic-(c) v43-baseline proposed fix (timing: hypothetical v43-staying fix; state: `redemptionPeriodIndex = period + 1` advanced inside resolver):** Per RNGLOCK-FIXREC §103.C line 5567, one proposed fix was to advance `redemptionPeriodIndex` inside `resolveRedemptionPeriod` (`redemptionPeriodIndex = period + 1;` after the resolve writes `redemptionPeriods[period]`). RNGLOCK-FIXREC §103.C lines 5577-5578 itself shows why this tactic alone is INSUFFICIENT: same-day post-resolve burn with `redemptionPeriodIndex = D+1` and `currentPeriod = D` re-trips the `:758` reset (`D+1 != D` is TRUE), which RE-SETS `redemptionPeriodIndex = D`, RE-EMERGING the exploit. The tactic-(c) clean variant requires combining the structural advance with EITHER removing the `:758` reset conditional OR adding a `redemptionPeriods[currentPeriod].roll != 0` revert (which collapses to tactic-(a)). **Per-day keying is a STRICTLY STRONGER structural answer**: there is no single `redemptionPeriodIndex` slot to advance because there is no single-pool indirection in the first place. The day is a direct mapping key, not an indirect slot reference. The §103.C tactic-(c) failure mode (reset regression) is structurally impossible under SPEC-01.
- **Skipped-advance edge (timing: many wall-clock days pass with no burns; state: `redemptionPeriodIndex` lags many days behind `currentDayView()`):** First burn of the catch-up day fires the reset block; snapshot + counter + index all jump forward to the catch-up day. The block's `!=` predicate handles arbitrary-gap day jumps the same way it handles single-day jumps. No game-theoretic issue.

**POST-REFACTOR REPLACEMENT:** Subsumed by **SPEC-01 (per-day keying — `mapping(uint32 => DayPending) internal pendingByDay` eliminates the need for a current-period index slot in the first place; each day is its own mapping key)** + **SPEC-05 (lazy-init of `pendingByDay[D].supplySnapshot` when the slot reads zero — `if (pendingByDay[currentDay].supplySnapshot == 0 && pendingByDay[currentDay].burned == 0)` predicate replaces the `redemptionPeriodIndex != currentPeriod` predicate one-for-one)**. The block's two roles split cleanly: (a) the snapshot/counter lazy-init role moves to SPEC-05's slot-zero predicate inside the per-day `DayPending` entry; (b) the index-advance role is ELIMINATED because there is no index slot to advance. The cross-day reset of `burned` to 0 is now structural (Solidity default-zero of a fresh `DayPending` entry) rather than block-conditional.

**DELETION SAFETY ATTESTATION:** **INV-01 (write-once roll immutability — for every `(D, P)` the locked `redemptionPeriods[D].roll` is byte-identical from first-write through claim regardless of any subsequent burns on the same wall-clock day)** + **INV-10 (per-day supply cap with snapshot timing per SPEC-05 — first-write predicate `supplySnapshot == 0 && burned == 0` plus immutable rest of day)** + **EDGE-07 (V-184 attack reproduction — NEGATIVE outcome: assertion `redemptionPeriods[D].roll` byte-identical to first-write value at every attack-sequence checkpoint, including after a same-day post-resolve 1-wei re-burn and after the subsequent day-D+1 advance)** + **EDGE-14 (50% supply cap edge — exact-cap succeeds, +1-wei reverts `Insufficient`)** + **EDGE-16 (cross-day cap reset — burn 160 ETH on day D + burn 160 ETH on day D+1 both succeed; cap counter restarts at 0 on the day-D+1 entry)** jointly attest that the lazy-init + cross-day reset semantics are byte-equivalent under per-day keying AND that the V-184 mechanic the reset block was structurally enabling is now structurally IMPOSSIBLE. The structural argument: post-refactor, there is no single `redemptionPeriodIndex` slot that can go stale; there is no `:758` predicate whose `==` evaluation can fail to detect "this day was already resolved"; the day key flows directly from `currentDayView()` into the per-day mapping, and SPEC-04 (c) `delete pendingByDay[dayToResolve]` at resolve ensures the just-resolved day's entry is zeroed before any subsequent burn could write to it (a subsequent same-wall-clock-day burn writes to `pendingByDay[currentDayView()]` which is a separate entry; a different-wall-clock-day burn writes to a different separate entry).

### §4 closing attestation

Seven deletions traced. Each carries ORIGINAL DESIGN INTENT at the v43.0 baseline + ACTOR GAME-THEORY WALK across (timing × state) combinations + POST-REFACTOR REPLACEMENT naming the SPEC-NN lock that subsumes it + DELETION SAFETY ATTESTATION proving no game-theoretic scenario re-introduces the deleted behavior. Per `feedback_design_intent_before_deletion.md`, every deletion was reasoned through BEFORE the lock — Phase 305 IMPL materializes the 7 deletions in the actual contract diff with the design walk above as its load-bearing input.

**V-184 structural elimination is the joint product of three SPEC-NN locks; no single lock suffices alone:**

1. **SPEC-01 (per-day keying via `mapping(uint32 => DayPending) internal pendingByDay`)** removes the single-pool indirection that the V-184 re-arm primitive abused. With SPEC-01 alone but WITHOUT SPEC-03, a resolver reading from a contract-state "current period" indirection slot could still go stale.
2. **SPEC-03 (`dayToResolve` arg on `resolveRedemptionPeriod` + `hasPendingRedemptions(uint32 day)` taking day arg)** makes the resolve target an explicit per-call selector flowing in from the AdvanceModule caller. With SPEC-03 alone but WITHOUT SPEC-01, a per-day pool that still shared a single ETH base slot would re-introduce the cross-day conflation.
3. **SPEC-04 (c) (`delete pendingByDay[dayToResolve]` at resolve)** closes the same-wall-clock-day re-arm window by zeroing the just-resolved day's entry. With SPEC-04 (c) alone but WITHOUT SPEC-01, there is no per-day entry to delete.

The three locks JOINTLY foreclose the overwrite primitive; absence of any one re-opens the surface. Per §2.0 Priority Statement clause 1, the V-184 catastrophe class (the only CATASTROPHE-tier finding in the entire v43.0 catalog per RNGLOCK-FIXREC §0 headline) is closed STRUCTURALLY at v44.0 — not by a runtime revert (no `BurnsBlockedAfterResolution` is added), but by the storage shape itself making the overwrite unreachable. **EDGE-07 in §3 (V-184 attack reproduction with byte-identical-roll negative assertion) and Deletions 1 + 4 + 5 + 7 in §4 (the four deletion walks that explicitly trace the V-184 mechanic) are the canonical closure artifacts; Phase 305 IMPL ships the diff; Phase 306 TST-04 (V-184 standalone reproduction) + TST-05 (`vm.skip(HANDOFF-111..117)` strict-assertion flip) + EDGE-07 fuzz test prove it; Phase 308 §3.D records the RESOLVED-AT-V44 disposition.**


## §5 — Source-Verified Citation Manifest

_To be filled by Plan 05 — see PLAN.md_
