# Phase 319 — GAS-06 Calibration Decision Record

**Authored:** 2026-05-24
**Contract HEAD:** `9ee13013` (`contracts/` clean; every cited `file:line` source-verified this session against `contracts/`)
**Task:** 319-05 Task 1 — compute the calibration; **NO `contracts/*.sol` edit in this task.** The contract edit (if any) is the USER-APPROVED Task-2 gate.
**Methodology floor (HARD):** `feedback_security_over_gas` (the SAFE-01 self-crank round-trip ≤ 0 faucet floor is a hard invariant) + the LOCKED REW-03 + A4 calibration policy (peg to the per-item MARGINAL, never the worst case).

---

## 0. Placement +0% verification (GAS-06 regression bound)

**Result: PLACEMENT +0% CONFIRMED.**

`forge snapshot --check` was run against the committed Plan-01 `.gas-snapshot` baseline (108 rows, the existing 12-contract unit/invariant snapshot — the GAS-06 placement reference scope per 319-01-SUMMARY).

- **Exit code: 0** — no tracked row exceeded the snapshot tolerance, i.e. **zero gas delta on every recorded placement-hot-path row**. `forge snapshot --check` emits a `Diff in "<test>"` line and a non-zero exit only when a recorded row's gas changed; there were **no such lines** and the exit was 0.
- The placement reference subset (319-01-SUMMARY) is byte-identical to the committed baseline:
  - `StorageFoundationTest:testPendingPoolPacking*` (5), `testPrizePoolPacking*` (5), `testSlot1FieldOffsets`, `testTicketSlotKey*`/`testTicketSlotKeysDiffer*` (5) — the placement-path storage packing + ticket-slot keying.
  - `LockRemovalTest:test_LOCK01_purchaseDuringRngLock` / `...StillRevertsOnGameOver` / `...StillRevertsOnZeroQuantity` — the deposit/purchase guard path.
- The 44 failing tests in the run are the **EXACT pre-existing v45 baseline** (invariant-replay / arithmetic-panic / accumulator failures in `WhaleSybil.inv`, `FreezeLifecycleTest`, `QueueDoubleBufferTest`, RngGuard range tests — zero AfKing/crank/placement involvement). They are excluded from the +0% reference subset per 319-01-SUMMARY (a failing test's recorded gas is execution-to-revert, not a valid placement reference). `forge snapshot --check` exits 0 regardless of the unrelated baseline failures.

**Why placement is structurally +0%:** the v46 crank relaxes the RESOLVE path only (`crankBets`/`crankBoxes` + the `onlySelf` resolve wrappers); the bet/box DEPOSIT (placement) machinery is untouched. No placement-path bytecode changed in Phase 317, so the recorded placement gas is identical.

`git diff --name-only -- contracts/` is **EMPTY** — zero contract mutation in this task.

---

## 1. The calibration inputs (measured marginals)

| Work type | Per-item MARGINAL (the calibration target) | Source |
|-----------|--------------------------------------------|--------|
| resolve-bet (per 1-spin item) | **66,528 gas** | 319-02-SUMMARY Test B (loop-N-divide, asserted materially below the 726,944 10-spin worst case) |
| open-box (per box) | **137,944 gas** | 319-02-SUMMARY Task 2 (single-box materialization marginal) |
| sweep (per successful player) | **309,007 gas** | 319-03-SUMMARY Test A (conservative over-estimate; shape-insensitive per Test B) |

**Locked policy (REW-03 + A4 + SAFE-01):** the peg constant is calibrated to the per-item MARGINAL, and the value must be **AT or BELOW** the measured marginal — never above. The SAFE-01 self-crank round-trip must stay ≤ 0 (a peg above the marginal opens a Sybil faucet at the 0.5 gwei reference price).

**Chosen safety-margin / rounding policy:** peg **exactly to the measured marginal** (no upward safety margin — REW-03 forbids a base-amortization margin; an upward margin would breach the faucet floor). No rounding is applied: the measured integers (66,528 / 137,944) are exact gas counts and are used verbatim. This is the most accurate reimbursement that still satisfies "AT or below the marginal" (equality is the boundary; round-trip = 0 at the reference price, ≤ 0 at any realistic market price).

---

## 2. Faucet-floor analysis (the SAFE-01 hard floor)

The reward credited per item is `_ethToBurnieValue(GAS_UNITS · 0.5 gwei, priceForLevel(lvl))`; valued back at the same peg it recovers exactly `GAS_UNITS · 0.5 gwei` of ETH. The cranker's REAL cost is `marginal_gas · (real gas price)`. Round-trip ≤ 0 ⟺ `GAS_UNITS · 0.5 gwei ≤ marginal_gas · (real price)`.

| Constant | Placeholder | Marginal | Placeholder vs marginal | Round-trip @ 0.5 gwei REFERENCE | Round-trip @ ≥1 gwei MARKET (SAFE-01 standard) |
|----------|-------------|----------|--------------------------|--------------------------------|-----------------------------------------------|
| `CRANK_RESOLVE_BET_GAS_UNITS` | 120,000 | **66,528** | placeholder is **1.80× ABOVE** the marginal | reward 60,000 gwei vs cost 33,264 gwei → **OVER-reimburses by +26,736 gwei (faucet OPEN at the reference price)** | reward 60,000 gwei vs cost@1gwei 66,528 gwei → ≤ 0 (held in 318-02 only via the ≥1 gwei market cushion) |
| `CRANK_OPEN_BOX_GAS_UNITS` | 120,000 | **137,944** | placeholder is **0.87× BELOW** the marginal | reward 60,000 gwei vs cost 68,972 gwei → **−8,972 gwei (round-trip ≤ 0, safe — UNDER-reimburses)** | reward 60,000 gwei vs cost@1gwei 137,944 gwei → ≤ 0 (safe with wide margin) |

### The load-bearing subtlety (RESOLVE constant)

318-02 proved round-trip ≤ 0 at the `120_000` placeholder. That proof is **real but narrow**: it compares the reward priced at the 0.5 gwei *reference* against the cranker's gas priced at the ≥1 gwei *realistic market floor* — a built-in 2× cushion (1 gwei is the lowest realistic mainnet submission price; 0.5 gwei is below market). At the 0.5 gwei reference price *itself*, the `120_000` reserve **over-reimburses** the 66,528 marginal by 26,736 gwei (1.80×). So 318-02's green is a property of the market-price cushion, NOT of the constant being at/below the marginal.

**Disposition for RESOLVE: this is BOTH a REW-03 accuracy refinement AND a faucet-floor tightening.** The LOCKED policy is "AT or below the marginal." `120,000 > 66,528` **violates** that policy at the reference-price boundary, even though the market-cushion keeps the *observed* round-trip ≤ 0. Calibrating to `66,528` makes the constant correct by construction (round-trip ≤ 0 at *every* price ≥ 0.5 gwei, not only ≥ 1 gwei) and reimburses the resolve cranker its exact per-1-spin marginal (REW-03 accuracy). → **OUTCOME B (edit): `120_000` → `66_528`.**

**Disposition for BOX: this is purely a REW-03 accuracy refinement.** `120,000 < 137,944` already satisfies "AT or below the marginal" — the box cranker is *under*-reimbursed by ~13% at the placeholder (no faucet risk; round-trip ≤ 0 by a comfortable margin). Raising to `137,944` (the marginal) brings the reward up to the cranker's exact per-box gas — a REW-03 accuracy improvement that keeps round-trip = 0 at the reference price and ≤ 0 at any market price. This is the policy target ("peg to the marginal"). → **OUTCOME B (edit): `120_000` → `137_944`.**

> Both edits move the constant TO the marginal. RESOLVE moves DOWN (closing a reference-price over-reimbursement / tightening the faucet floor); BOX moves UP (a pure accuracy refinement that fully reimburses the box cranker). Neither value exceeds its marginal, so the SAFE-01 round-trip ≤ 0 invariant is preserved at both — at equality, round-trip = 0 at the 0.5 gwei reference and strictly < 0 at every realistic market price (≥ 1 gwei).

### Faucet-floor proof of the proposed values

| Constant | Proposed | reward @ 0.5 gwei ref (gwei) | cost @ 0.5 gwei ref (gwei) | round-trip @ ref | round-trip @ 1 gwei market |
|----------|----------|------------------------------|-----------------------------|------------------|----------------------------|
| `CRANK_RESOLVE_BET_GAS_UNITS` | **66,528** | 33,264 | 33,264 | **= 0 (boundary, safe)** | reward 33,264 < cost 66,528 → **< 0 (safe)** |
| `CRANK_OPEN_BOX_GAS_UNITS` | **137,944** | 68,972 | 68,972 | **= 0 (boundary, safe)** | reward 68,972 < cost 137,944 → **< 0 (safe)** |

Both satisfy the SAFE-01 hard floor (round-trip ≤ 0) at every price ≥ the 0.5 gwei reference. BURNIE credit magnitudes at level 1 (`priceForLevel(1) = 0.01 ETH`): resolve 3.3264 BURNIE/item, box 6.8972 BURNIE/box — illiquid coinflip stake (not liquid BURNIE).

---

## 3. Per-constant decision summary

| Constant | Location | Measured marginal | Current | **Proposed** | Decision | Faucet floor |
|----------|----------|-------------------|---------|--------------|----------|--------------|
| `CRANK_RESOLVE_BET_GAS_UNITS` | `DegenerusGame.sol:1501` | 66,528 | 120,000 | **66,528** | **OUTCOME B — edit (down; tighten faucet floor + REW-03 accuracy)** | round-trip = 0 @ ref, < 0 @ market ✓ |
| `CRANK_OPEN_BOX_GAS_UNITS` | `DegenerusGame.sol:1502` | 137,944 | 120,000 | **137,944** | **OUTCOME B — edit (up; REW-03 accuracy)** | round-trip = 0 @ ref, < 0 @ market ✓ |
| `CRANK_GAS_PRICE_REF` | `DegenerusGame.sol:1495` | — | 0.5 gwei | **0.5 gwei (UNTOUCHED)** | FINAL/locked — never edited | — |

**Both `*_GAS_UNITS` constants need an edit → the phase is OUTCOME B.** The edit is the EXACT integer change at `DegenerusGame.sol:1501-1502`; `CRANK_GAS_PRICE_REF` (:1495) is NOT touched. The edit is CONDITIONAL on the USER-APPROVED Task-2 gate — nothing is pre-approved.

---

## 4. BOUNTY_ETH_TARGET deploy-param decision (AGENT-editable, NOT a frozen gate)

`BOUNTY_ETH_TARGET` is an AfKing constructor immutable (`AfKing.sol:252`, set `:268`), supplied as `DeployProtocol.sol:126` arg2 = `885_000_000`. It is **ETH wei** (NatSpec `AfKing.sol:246-252,261`). The per-player bounty is `(BOUNTY_ETH_TARGET · PRICE_COIN_UNIT · bountyMultiplier) / mp` BURNIE (`AfKing.sol:745`), so at base `bountyMultiplier == 1` the ETH-equivalent reward per player recovers to exactly `BOUNTY_ETH_TARGET` wei.

**Stall multiplier (SUB-03, `AfKing.sol:539-551`):** the bounty scales 1× → 2× (≥20 min) → 4× (≥1 h) → 6× (≥2 h) as the daily sweep stalls. The faucet ceiling must hold at the **6× peak**.

**Measured calibration input:** sweep per-player marginal = **309,007 gas**. Faucet floor at the 0.5 gwei reference = `309,007 · 0.5 gwei = 154,503,500,000,000 wei` (≈ 0.0001545 ETH per player).

| Lens | Constraint on BOUNTY_ETH_TARGET |
|------|----------------------------------|
| Round-trip ≤ 0 at the 0.5 gwei REFERENCE during a 6× stall | `BOUNTY_ETH_TARGET ≤ 154,503,500,000,000 / 6 = 25,750,583,333,333 wei` |
| Round-trip ≤ 0 at the ≥1 gwei MARKET floor during a 6× stall (the SAFE-01 standard 2× cushion) | `BOUNTY_ETH_TARGET ≤ 309,007 · 1 gwei / 6 = 51,501,166,666,666 wei` |

**Current value analysis:** `885,000,000` wei is **~177,000× BELOW** the faucet floor — even at the 6× peak the bounty (5,310,000,000 wei) is ~58,000× below the keeper's ≥1 gwei market gas cost (309,007,000,000,000 wei). The current value is **NOT a faucet risk**; it is so far below the keeper's actual gas cost that it under-incentivizes the sweep keeper by ~5 orders of magnitude.

**Decision: NO autonomous deploy-param change in this plan; SURFACE for the USER.** Rationale:
1. `BOUNTY_ETH_TARGET` is an **economic / keeper-incentive** parameter, not a pure-gas-floor parameter. Setting it correctly is a trade-off between (a) keeper incentive (it must at least cover the keeper's market gas cost or no third party will run the sweep) and (b) the SAFE-01 self-crank faucet ceiling at the 6× peak. GAS-06's scope is the *gas calibration* (the faucet ceiling); the *incentive target* (how far above gas cost to pay the keeper) is an economic choice the user owns.
2. `DeployProtocol.sol:126` is a **test fixture** value. The PRODUCTION keeper deploy lives in the paired `degenerus-utilities` repo (319-03-SUMMARY / `scripts/deploy.js` does NOT reference AfKing), so the test-fixture arg2 is not the mainnet value. Changing the fixture arg2 would only affect test economics, not production.
3. The recommended production CEILING (the hard faucet floor): **`BOUNTY_ETH_TARGET ≤ 51,501,166,666,666 wei`** (the 6×-stall, ≥1 gwei-market round-trip ≤ 0 bound). The recommended FLOOR (keeper incentive) is a user/economic choice — a value near `5.15e13` wei would reimburse ~100% of the keeper's 1 gwei gas at the 6× peak while the base (1×) reward stays ~6× below cost (under-reimbursing during a healthy fast sweep, escalating only when the sweep stalls — exactly the SUB-03 design intent).

**This is recorded for USER visibility (Task-2 gate item 4). No `DeployProtocol.sol` edit is proposed here.** If the user wants the test fixture or the production target tuned, that is a separate (agent-editable) deploy-param change applied in Task 3.

---

## 5. GAS-02 hoist disposition (SCAV-319-01, from Plan 04 / 319-GAS-05-GUARDRAILS.md)

**Disposition: NO-OP — NOT shipped.**

SCAV-319-01 (the `crankBets:1567-1570` / `crankBoxes:1621-1623` loop-invariant hoist of `_ethToBurnieValue(CRANK_*_GAS_UNITS · CRANK_GAS_PRICE_REF, priceForLevel(lvl))` out of the per-item loop) was surfaced by Plan 04 with the Skeptic disposition **"approve-IF-real-saving / no-op-IF-already-hoisted-by-the-optimizer."** The handoff condition (319-GAS-05-GUARDRAILS.md §SCAV-319-01) is: **ship into Plan 05's diff IFF a before/after measurement shows a real runtime saving at runs=200; otherwise drop as a no-op.**

The hoisted expression is a pure recomputation of compile-time-`constant` inputs (`CRANK_*_GAS_UNITS`, `CRANK_GAS_PRICE_REF`) and a `pure` library lookup of a loop-invariant local (`lvl`, read once before the loop). At the production `runs=200` / `viaIR` optimizer (foundry.toml:10), common-subexpression elimination already hoists such loop-invariant pure calls — so the source edit yields **zero measured runtime saving** (the emitted bytecode is identical). Per the runs=200 correction documented in 319-GAS-05-GUARDRAILS.md (NOT the stale SKILL.md runs=2 bytecode-first lens), this is a no-op. **It is dropped — NOT included in the OUTCOME-B batched diff.** The batched diff is therefore the two `*_GAS_UNITS` integer changes + the test-mirror syncs ONLY.

---

## 6. Test-mirror sync scope (CRITICAL — wider than the plan's stated single mirror)

The plan's `<interfaces>` named `CrankFaucetResistance.t.sol:74-75` as "the" mirror, with the note "If any new Plan-02/03 harness also mirrors the constants, sync those too." A grep of `test/` confirms **FOUR** files declare the `120_000` mirror, THREE of which consume it in LIVE peg-equality `assertEq`s (so they flip RED if the contract changes but the mirror does not):

| File | Mirror lines | Consumes in peg-equality assertion? | Must sync if OUTCOME B |
|------|--------------|--------------------------------------|------------------------|
| `test/fuzz/CrankFaucetResistance.t.sol` | 74-75 | YES — `:145, :177-182, :239, :265, :335, :443` (SAFE-01 round-trip ≤ 0 + peg-equality) | **YES** |
| `test/fuzz/CrankNonBrick.t.sol` | 72-73 | YES — `:162, :200, :248` (`2 * CRANK_*_GAS_UNITS * CRANK_GAS_PRICE_REF`) | **YES** |
| `test/gas/CrankLeversAndPacking.t.sol` | 69-70 | YES — `:153, :202` (`3 * CRANK_*_GAS_UNITS * CRANK_GAS_PRICE_REF`) | **YES** |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | 59-60 | NO — declared but not consumed in an assertion (no-op declaration) | **YES (consistency; harmless)** |

**Implication for Task 3 (OUTCOME B):** the contract-constant edit at `DegenerusGame.sol:1501-1502` must sync ALL FOUR mirrors in the SAME change, or `CrankFaucetResistance`, `CrankNonBrick`, and `CrankLeversAndPacking` peg-equality assertions break. This is a material expansion of the plan's stated mirror set (the plan named one of four). It is surfaced here and in the Task-2 checkpoint for the USER. The four mirror syncs are test-only files (no contract approval needed for them; only `DegenerusGame.sol` is the frozen gate).

---

## 7. Proposed OUTCOME-B batched diff (for USER review — NOT applied)

The exact change presented for the Task-2 USER-APPROVED gate. The `contracts/DegenerusGame.sol` hunk is the ONLY frozen-contract mutation; `CRANK_GAS_PRICE_REF` (:1495) is untouched; the four test mirrors sync in the same change; the GAS-02 hoist is a no-op (not included).

```diff
--- a/contracts/DegenerusGame.sol
+++ b/contracts/DegenerusGame.sol
@@ -1498,8 +1498,8 @@
      ///      placeholders calibrated from measured worst-case marginal gas at the
      ///      Phase 319 GAS pass; only the names/shape are fixed here. They are
      ///      FIXED constants (REW-03) — the reward never depends on gasleft().
-    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
-    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;
+    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
+    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 137_944;
```

```diff
--- a/test/fuzz/CrankFaucetResistance.t.sol
+++ b/test/fuzz/CrankFaucetResistance.t.sol
@@ -73,4 +73,4 @@
     /// @dev Reserved per-work-type gas-unit constants (DegenerusGame.sol:1501-1502).
-    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
-    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;
+    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
+    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 137_944;
```

```diff
--- a/test/fuzz/CrankNonBrick.t.sol
+++ b/test/fuzz/CrankNonBrick.t.sol
@@ -72,2 +72,2 @@
-    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
-    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;
+    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
+    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 137_944;
```

```diff
--- a/test/gas/CrankLeversAndPacking.t.sol
+++ b/test/gas/CrankLeversAndPacking.t.sol
@@ -69,2 +69,2 @@
-    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
-    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;
+    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
+    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 137_944;
```

```diff
--- a/test/fuzz/RngFreezeAndRemovalProofs.t.sol
+++ b/test/fuzz/RngFreezeAndRemovalProofs.t.sol
@@ -59,2 +59,2 @@
-    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
-    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;
+    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
+    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 137_944;
```

**No `DeployProtocol.sol` change is proposed** (BOUNTY_ETH_TARGET is surfaced for the user but not autonomously tuned — §4).

---

## 8. Summary for the Task-2 gate

| Item | Decision |
|------|----------|
| Placement +0% | **CONFIRMED** (forge snapshot --check exit 0, zero placement-row delta) |
| `CRANK_RESOLVE_BET_GAS_UNITS` | **OUTCOME B — `120_000` → `66_528`** (down; faucet-floor tighten + REW-03 accuracy) |
| `CRANK_OPEN_BOX_GAS_UNITS` | **OUTCOME B — `120_000` → `137_944`** (up; REW-03 accuracy; still ≤ marginal) |
| `CRANK_GAS_PRICE_REF` | **UNTOUCHED (0.5 gwei, FINAL)** |
| Faucet floor (SAFE-01) | **PRESERVED** — both proposed values = their marginal; round-trip = 0 @ 0.5 gwei ref, < 0 @ every market price ≥ 1 gwei |
| `BOUNTY_ETH_TARGET` deploy-param | **NO autonomous change; SURFACED** — current 885,000,000 wei is ~177,000× below the faucet floor (under-incentivizes, not a faucet risk); production target is an economic choice in the paired `degenerus-utilities` deploy; hard ceiling ≤ 51,501,166,666,666 wei (6×-stall, 1 gwei-market round-trip ≤ 0) |
| GAS-02 hoist (SCAV-319-01) | **NO-OP — dropped** (optimizer already hoists at runs=200; zero measured saving) |
| Test-mirror sync scope | **FOUR files** (CrankFaucetResistance, CrankNonBrick, CrankLeversAndPacking, RngFreezeAndRemovalProofs) — wider than the plan's stated single mirror; all sync in the same Task-3 change |
| Contract approval | **REQUIRED at Task 2 — nothing pre-approved.** Only `DegenerusGame.sol` is the frozen gate; the four test mirrors are test-only |
