# 333-01 — SWEEP-02 Delta Audit (v49.0 TERMINAL)

**Plan:** 333-01 (SWEEP-02, Wave-1). READ-ONLY analysis — ZERO `contracts/*.sol` edits, ZERO commits.
**Requirement owned:** SWEEP-02 (+ the D-06 structural-spine re-attestations the FINDINGS §3/§5 folds).
**Audit baseline:** v48.0 closure HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029`
(signal `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029`).
**Frozen subject HEAD:** `4c9f9d9b` = the Phase-330 batched router/advance-redesign diff `63bc16ca`
+ the Phase-331 GAS-split / re-peg diff `4c9f9d9b`.
**Frozen-subject guard:** `git diff 4c9f9d9b HEAD -- contracts/` is **EMPTY** (verified this session —
EMPTY-CONFIRMED; 331/332 since `4c9f9d9b` are doc + test only). Every `file:line` anchor below was
**re-grep-verified against the frozen blob** via `git show 4c9f9d9b:contracts/...` (NOT from memory, NOT
from the working tree).

> **THE BINDING HEADLINE.** Every contract surface changed vs the v48.0 baseline `0cc5d10f` is enumerated
> and attested **NON-WIDENING** with a concrete grep/diff anchor @ `4c9f9d9b`; every `contracts/` + `test/`
> delta hunk maps to exactly ONE v49 work item (no orphan hunks); the 4 structural invariants + the
> **OPEN-E** 4-protection + the VRF/RNG-freeze are re-attested intact; the 666/42/17 regression baseline is
> NON-WIDENING by NAME; the v48 SWAP cash-share advisory is carried-forward-unmodified.

---

## 1. The delta surface (`git diff 0cc5d10f 4c9f9d9b -- contracts/`)

**5 files changed, +376 / −226 [VERIFIED this session]:**

| File | Lines changed | v49 work item(s) (owning surface) |
|------|---------------|-----------------------------------|
| `contracts/AfKing.sol` | 318 | ROUTER-01..10 + GASOPT-04/05 + the 331 re-peg (GAS-02..05) |
| `contracts/DegenerusGame.sol` | 196 | ADV-02 wrapper + GASOPT-03 discovery views + autoOpen RD-3/RD-5 + `degeneretteResolve` (GAS-06) + RD-2 batchPurchase-guard drop |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 52 | ADV-01/02/05/03 (advance bounty-removal + `(mult)` return-shape + free-fallback callers intact) |
| `contracts/modules/DegenerusGameMintModule.sol` | 30 | GASOPT-01 (`owedMap` storage-pointer hoist) |
| `contracts/interfaces/IDegenerusGameModules.sol` | 6 | the `advanceGame() returns (uint8 mult)` interface update |

Two mainnet contract commits in the range (`git log 0cc5d10f..4c9f9d9b -- 'contracts/*.sol'`):
`63bc16ca` (330 redesign, BATCH-02 USER-approved) + `4c9f9d9b` (331-05 GAS split).

---

## 2. Per-Surface NON-WIDENING Disposition Table

> Mirrors the v48 FINDINGS §3.A columns: **Surface (file) | Requirements | Re-grepped anchors @ `4c9f9d9b` |
> Disposition**. Every anchor below was re-grep-verified against the frozen blob this session.

| Surface | Requirements | Re-grepped anchors @ `4c9f9d9b` | Disposition |
| --- | --- | --- | --- |
| **AfKing.sol** — parameterless router + unified bounty + re-peg + micro-opts | ROUTER-01·02·03·04·05·06·08·09·10 · GASOPT-04·05 · GAS-02·03·04·05 | **PARAMETERLESS `doWork()`** (`function doWork() external` `:883`, NO `maxCount` arg) routing one-category `else-if` **autoBuy → advance → autoOpen → `NoWork()`** (`:890`/`:896`/`:902`/`revert NoWork()` `:910`) with the **SINGLE unified `creditFlip` CEI-LAST** after the early-return (`creditFlip(msg.sender, bountyEarned)` `:917`; `NoWork()` decl `:148`). `_autoBuy` is **internal** (`function _autoBuy(uint256 maxCount) internal` `:561`); the RD-2 **rngLock guard `:568` is DROPPED** (autoBuy fires `TRUE even during rngLock` — `doWork` (1) leg comment `:889`). Standalone **UNREWARDED** escapes present: `autoBuy(uint256 count)` `:923` + `autoOpen(uint256 count)` `:929` (parametered, never credit — only `doWork` credits). The 331 **re-peg constants** present: `BOUNTY_ETH_TARGET` immutable `:261`, `BUY_BATCH = 50` `:850`, `OPEN_BATCH = 100` `:856`, `ADVANCE_RATIO_NUM = 2` `:860`, `BUY_RATIO_NUM/DEN = 3/2` `:864-865`, `OPEN_KNEE = 5` `:869`; the per-leg bounty math `unit*BUY_RATIO_NUM/DEN` `:893`, `unit*ADVANCE_RATIO_NUM*mult` `:899`, `unit*k/OPEN_KNEE` (pro-rate below knee) `:905-906`. **KILL-SET (grep-ZERO):** the `AutoBought` EVENT — `event AutoBought`/`emit AutoBought` = **0** (GASOPT-04; the no-double-buy oracle migrated to the `lastAutoBoughtDay` storage stamp `:88`/`:744`, stamped CEI after accounting). The per-iter `isOperatorApproved(player, AfKing)` `:676` — **DROPPED** (GASOPT-05; only the GASOPT-05 strike comment remains at `:667-670`); the subscribe-time `isOperatorApproved(fundingSource, subscriber)` gate **KEPT** (`:388` self + `:399` fundingSource). The **autoBuy STALL LADDER DELETED** (GAS-03/D-07): `bountyMultiplier`/`stallMultiplier`/`STALL_` = **0**; the old absolute-day bounty epoch is gone (the 2 remaining `82620` hits `:965-969` are the keeper-local once/day idempotency epoch `_currentDay()`, NOT an escalating stall ladder). | **NON-WIDENING** |
| **DegenerusGame.sol** — wrapper decode + discovery views + autoOpen RD-3/RD-5 + degeneretteResolve + batchPurchase guard | ADV-02 · GASOPT-03 · ROUTER-04·09 · GAS-06 · ROUTER-08 | **`advanceGame` wrapper** (`:278`) now **DECODES** the delegatecall return `data` (`mult = abi.decode(data, (uint8))` `:288`) instead of discarding it on success (ADV-02; the `(uint8)` shape — see §5 note on the collapsed `rewardable` bool). **O(1) discovery views, no unbounded scan:** `advanceDue()` `:1637`, `boxesPending()` `:1655` (**rngLock-aware** — `if (rngLockedFlag) return false;` `:1656`, RD-3), `keeperSnapshot(address[])` `:2628` (batches the per-player `claimableWinningsOf` STATICCALLs, GASOPT-03; returns `mintPriceWei`/`rngLocked_`/`claimables[]`). **autoOpen RD-5** (`:1687`): **try/catch DROPPED**, replaced by a pre-loop **entry-gate** `if (rngLockedFlag || _livenessTriggered()) return 0;` `:1692`; `_autoOpenBox` is **internal** (`:1762`). **`degeneretteResolve`** (renamed from `autoResolve`, `:1595`): flat `RESOLVE_FLAT_BURNIE = 1e18` `:1544`; **≥3-NON-WWXRP gate** + `NoWork()`-at-zero — `if (totalResolved == 0) revert NoWork();` `:1629`, `if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE)` `:1630` (1-2 resolved → committed UNPAID, never strand the tail, GAS-06). **batchPurchase** (`:1790`): the game-side **rngLock pre-check `:1737` DROPPED** (RD-2) while the `gameOver` revert is **KEPT** (`if (gameOver) revert E()` `:1796`); AF_KING-gated `:1795`; per-player try/catch isolation INTACT (`this._batchPurchaseUnit{value: slice}` `:1806`, `catch {}` — a reverting player is skipped, never bricks the batch). | **NON-WIDENING** |
| **modules/DegenerusGameAdvanceModule.sol** — advance bounty-removal + return-shape + free-fallback intact | ADV-01 · ADV-02 · ADV-05 · ADV-03 | **KILL-SET (grep-ZERO keeper credits):** the 3 in-callee advance keeper `creditFlip(caller, …)` sites (`:189`/`:225`/`:468`) are **REMOVED** — `creditFlip` count in the whole module = **1**, and that sole survivor at `:860` credits **`ContractAddresses.SDGNRS`** (the gameover-RNG SDGNRS credit, U6 — payee is SDGNRS, NOT the keeper, so it is not a `doWork` bounty). **`advanceGame() returns (uint8 mult)`** (`:154`): `mult = 1` default at entry `:156`; **gameover path `mult = 0`** (`:185`, "coin is worthless at gameover → return mult=0 so doWork pays nothing"); **mid-day partial-drain `mult = 1`** (no escalation, ADV-05/D-07 — `:217-218`); **new-day stall ladder** writes `mult` straight from the KEPT GAME-day epoch (`6` after 2h `:236`, `4` after 1h `:238`, `2` `:240`). The ticket-drain / day-advance logic is otherwise **untouched** (only the bounty was removed; standalone `advanceGame()` stays a functional UNREWARDED liveness fallback, ADV-03). **Free-fallback callers INTACT (D-04a):** the 30-min universal permissionless bypass `if (elapsed >= 30 minutes) return;` `:996`; the ~120-day death-clock `DEPLOY_IDLE_TIMEOUT_DAYS` `:109`. The Vault/sStonk `gameAdvance()` SECONDARY callers are **NOT in the v49 delta surface** (`git diff --name-only 0cc5d10f 4c9f9d9b` lists NEITHER `DegenerusVault.sol` NOR `StakedDegenerusStonk.sol` → re-homing the bounty removed NO structural caller). | **NON-WIDENING** |
| **modules/DegenerusGameMintModule.sol** — GASOPT-01 owedMap hoist | GASOPT-01 | The `mapping(address => uint40) storage owedMap = ticketsOwedPacked[rk]` pointer hoist landed in **BOTH** loops: the resolve/future loop (`:399`) and `processTicketBatch` (`:673`), threaded through the helpers (`owedMap` param `:735`/`:765`). `rk` is loop-invariant within each scope (computed once from the active level key) → the hoist is a behavior-identical SLOAD-count reduction (gas-only, same reads/writes: `owedMap[player]` reads/writes at `:432`/`:442`/`:454`/`:464`/`:499`/`:743`/`:750`/`:756`/`:771`/`:824` are byte-equivalent to the prior `ticketsOwedPacked[rk][player]` form). | **NON-WIDENING** |
| **interfaces/IDegenerusGameModules.sol** — advanceGame tuple signature | ADV-02 | The 6-line diff changes `function advanceGame() external;` → `function advanceGame() external returns (uint8 mult);` (+ NatSpec documenting `mult` = stall ladder 1/2/4/6 new-day / 1 mid-day / 0 gameover). The interface return shape **matches the AdvanceModule contract signature verbatim** (`:154` `returns (uint8 mult)`) and the wrapper decode (`abi.decode(data, (uint8))` `DegenerusGame:288`). No other interface row changed. | **NON-WIDENING** |

**All 36 v49.0 REQ-IDs cross-referenced.** The 5-surface table above carries every IMPL/GAS-resident req:
ROUTER-01..10 + ADV-01·02·03·05 + GAS-02·03·04·05·06 + GASOPT-01·03·04·05 (ROUTER-07/ADV-04/GAS-03/BATCH-01
are the SPEC-resident design-locks re-attested in §3; GAS-01 is the GAS derivation; TST-01..05 are the
332 proofs cited in §3/§5; SWEEP-01 is 333-02; SWEEP-03 is 333-03; BATCH-02 is the `63bc16ca` diff itself;
BATCH-03 is the 333-04 closure flip).

---

## 3. Composition Attestation Matrix

> Mirrors the v48 FINDINGS §3.B AND extends with the three D-06 v49-specific re-attestations
> (the 4 invariants / the OPEN-E 4-protection / VRF-freeze).

### 3.1 — Every delta hunk maps to exactly ONE v49 work item (NO orphan hunks)

- **`AfKing.sol` (318 lines):** every hunk lands in exactly one of {the parameterless `doWork` router + the
  one-category early-return (ROUTER-01/02/03); `_autoBuy` internal-refactor + RD-2 guard-drop (ROUTER-05/08);
  the single unified `creditFlip` (ROUTER-10/R4); the re-peg constants + leg math (GAS-02/03/04/05); the
  `AutoBought`-event drop + `lastAutoBoughtDay`-oracle migration (GASOPT-04); the `:676` per-iter
  `isOperatorApproved` drop (GASOPT-05); the stall-ladder deletion (GAS-03/D-07)}. The `keeperSnapshot`
  read-collapse consumer side is GASOPT-03.
- **`DegenerusGame.sol` (196 lines):** every hunk lands in exactly one of {the `advanceGame` wrapper decode
  (ADV-02); the rngLock-aware `advanceDue`/`boxesPending` views + `keeperSnapshot` (ROUTER-04/GASOPT-03); the
  autoOpen entry-gate + try/catch-drop + `_autoOpenBox`-internal (ROUTER-09/RD-3/RD-5); the `degeneretteResolve`
  rename + flat ≥3 re-peg (GAS-06); the `batchPurchase` rngLock-pre-check drop / gameOver-keep (ROUTER-08/RD-2)}.
- **`modules/DegenerusGameAdvanceModule.sol` (52 lines):** every hunk = the 3 creditFlip-removals (ADV-01) +
  the `(uint8 mult)` return-shape with the gameover-0 / mid-day-1 / stall-ladder legs (ADV-02/ADV-05). The
  free-fallback callers (`:109`/`:996`) are read-only confirms, not hunks.
- **`modules/DegenerusGameMintModule.sol` (30 lines):** every hunk = the `owedMap` storage-pointer hoist
  (GASOPT-01), both loops.
- **`interfaces/IDegenerusGameModules.sol` (6 lines):** the single `advanceGame` return-tuple signature
  (ADV-02).

**Conclusion: ZERO orphan hunks** across the +376/−226 contract delta — every hunk is attributable to exactly
one v49 work item. This is the SWEEP-02 NON-WIDENING core: the v49 surface widens NOTHING beyond the four
work-item families (router / advance-rework / re-peg / micro-opts).

### 3.2 — The 4 Structural Invariants (329-SPEC §2) re-attested intact @ `4c9f9d9b`

| # | Invariant (329-SPEC §2 text) | Re-attestation @ `4c9f9d9b` | Empirical proof |
|---|------------------------------|------------------------------|-----------------|
| **(a)** | **ONE-CATEGORY STRUCTURAL EARLY-RETURN** — `doWork()` routes `autoBuy → advance → autoOpen` and returns after the FIRST category that has work; advance/open/buy bounties can never stack in one tx. | The `doWork` body (`AfKing:883-919`) is an `if / else if / else if / else` ladder: leg (1) autoBuy `:890`, leg (2) advance `:896` (`else if`), leg (3) autoOpen `:902` (`else if`), leg (4) `revert NoWork()` `:910` (`else`). Exactly one leg can execute. The single `creditFlip` `:917` fires once, CEI-LAST, after the ladder. **Bounty-stacking structurally impossible.** | TST-02 (`KeeperRouterOneCategory.t.sol`, 332-02: creditFlip COUNT==1 across buy/advance/open) |
| **(b)** | **FROZEN ADVANCE-CONSUME (ADV-04)** — the router advance-consume reads only FROZEN VRF-window state even when fired same-tx as autoOpen/autoBuy; the player-controllable `totalFlipReversals` nudge stays frozen request→consume; no new in-window SLOAD. | RD-1 ordering IS the invariant: autoBuy runs PRE-ENTROPY at day-open (leg 1, `TRUE even during rngLock` `:889`) BEFORE the advance leg requests the day's word (leg 2); autoOpen (leg 3) is rngLock-BLOCKED (`boxesPending()` returns false during rngLock `DegenerusGame:1656`; the autoOpen entry-gate `:1692` also returns 0 during the freeze) so it never runs during the protected window. The advance leg consumes via the design-1 RETURN (the wrapper decode `:288`); it adds NO new mutable in-window SLOAD (AdvanceModule diff is bounty-removal + return-shape only — the consume logic is untouched). | ADV-04 (SPEC, Complete) + TST-01 (`RngLockDeterminism.t.sol`, 332-01: router same-tx perturbation — byte-identical consumed VRF output) |
| **(c)** | **GUARANTEED FREE-FALLBACK CALLER (D-04a)** — standalone `advanceGame()` is unrewarded but the EXISTING bypass tiers remain; re-homing the bounty removed NO structural caller. | Standalone `advanceGame()` stays functional + UNREWARDED (ADV-03; the AdvanceModule logic is untouched apart from the keeper-credit removal). SECONDARY/TERTIARY callers INTACT: the 30-min universal permissionless bypass `AdvanceModule:996` (`elapsed >= 30 minutes`), the ~120-day death-clock `:109` (`DEPLOY_IDLE_TIMEOUT_DAYS`); `DegenerusVault.gameAdvance()` + `StakedDegenerusStonk.gameAdvance()` are **NOT in the v49 delta surface** (the diff lists neither file → both untouched). | D-04a (SPEC) |
| **(d)** | **SINGLE DAY-START EPOCH: SATISFIED-BY-DELETION (GAS-03)** — dropping the autoBuy stall multiplier deletes AfKing's autoBuy stall ladder + its absolute-day epoch, leaving the AdvanceModule GAME-day epoch as the SOLE stall epoch. | The AfKing autoBuy stall ladder is **DELETED** (grep-ZERO `bountyMultiplier`/`stallMultiplier`/`STALL_`); the only escalating stall epoch is the AdvanceModule GAME-day ladder (`AdvanceModule:236/238/240` 6/4/2). The 2 remaining `82620` hits (`AfKing:965-969` `_currentDay()`) are the keeper-local once/day idempotency epoch (feeds `lastAutoBoughtDay`), NOT an escalating bounty stall ladder. There are no two epochs to collapse (D-03 dissolved by D-07). | GAS-03 (SPEC, Complete; autoBuy stall ladder deleted) |

### 3.3 — OPEN-E 4-Protection BLOCKING Re-Attestation (GASOPT-05) — HARD CONDITION

> **GASOPT-05 dropped the per-iteration `isOperatorApproved(player, AfKing)` check (`:676`) and kept the
> subscribe-time `isOperatorApproved(fundingSource, subscriber)` gate (`:401`/`:399`).** Per
> [[open-e-operator-approval-trust-boundary]] + the ROADMAP coverage note + REQUIREMENTS GASOPT-05, the
> delta-audit MUST re-attest the 4 OPEN-E structural protections HOLD WITHOUT `:676` as a **HARD BLOCKING
> CONDITION before closure**. If ANY protection fails, the GASOPT-05 removal is REVERTED before the milestone
> ships — this is a 333-04-closure-gate-routed blocker, NOT a 333-01 fix.

**Anchor confirmation @ `4c9f9d9b`:** the per-iter `:676` call is **DROPPED** (the autoBuy loop carries only the
GASOPT-05 strike comment at `AfKing:667-670` documenting the removal — no `isOperatorApproved` call inside the
buy loop); the subscribe-time gate is **KEPT** (`isOperatorApproved(subscriber, msg.sender)` self at `:388` +
`isOperatorApproved(fundingSource, subscriber)` at `:399`, inside `subscribe`).

| # | OPEN-E protection | Re-attestation @ `4c9f9d9b` | Outcome |
|---|-------------------|------------------------------|---------|
| **(1)** | **consent-gate-at-subscribe** | The SUB is the consent unit. Operator approval is checked ONCE, at `subscribe` time (`:399` `isOperatorApproved(fundingSource, subscriber)` — the funding source must have pre-approved the subscriber). A player who never approved cannot be subscribed by a third party. The per-iter `:676` re-check is redundant: consent was already gated at the subscription boundary. | **HOLD** |
| **(2)** | **default-self byte-identical** | The default funding source is the subscriber themself (`fundingSource = subscriber` when none is supplied → `isOperatorApproved(self, self)` is trivially true / the self-funding path needs no external approval). Dropping `:676` does not alter the default-self path: a self-funded sub still buys for itself, byte-identically, with no operator check needed. | **HOLD** |
| **(3)** | **no-escalation** | Dropping the per-iter check grants NO new authority: the keeper (`msg.sender` of `doWork`/`autoBuy`) was never the consent principal — the consent principal is `fundingSource`, fixed at subscribe. The autoBuy loop spends only `_poolOf[src]` (the funding source's prepaid pool, CEI-debited `:728`), routed into the player's own mint via `batchPurchase`'s per-slice forward. No path lets a keeper redirect funds or escalate beyond what the subscribe-time approval already authorized. | **HOLD** |
| **(4)** | **trust-the-sub temporal bound** | Revocation remains available and bounded: `setDailyQuantity(0)` tombstones the sub (the funding-skip / removal path `:715-721` pops it from the active set). Consent is bounded by the subscriber's own ability to revoke at any time; the keeper cannot extend it. The per-iter `:676` check added no temporal protection the subscribe-time gate + the revoke-via-`setDailyQuantity(0)` does not already provide. | **HOLD** |

**OPEN-E re-attestation outcome: ALL 4 PROTECTIONS HOLD** without the per-iter `:676` check. The GASOPT-05
removal is **NON-WIDENING** — it removes a redundant per-iteration re-check while the consent trust boundary
(subscribe-time gate + sub-as-consent-unit + revoke-to-tombstone) is fully preserved. **The HARD BLOCKING
CONDITION is SATISFIED → no GASOPT-05 revert is required; closure is NOT blocked on this axis.**

### 3.4 — VRF / RNG-Freeze INTACT under the router composition (the v45 north-star)

The unified same-tx router path introduces **NO in-window SLOAD** into the advance-consume
([[v45-vrf-freeze-invariant]]; ADV-04). Structural basis: (i) autoBuy (leg 1) runs PRE-ENTROPY at day-open
before advance requests the word — buying is freeze-safe by construction (RD-2: box queues at the current
`LR_INDEX`, the word lands at `LR_INDEX-1`, `LR_INDEX` advances only inside `advanceGame`); (ii) the advance
leg (leg 2) consumes via the return-tuple decode (`DegenerusGame:288`) — the AdvanceModule consume logic is
byte-untouched by the v49 diff (only the keeper `creditFlip`s were removed and the `(mult)` return added), so
no fresh mutable VRF-window read was introduced; (iii) autoOpen (leg 3) is rngLock-BLOCKED — `boxesPending()`
returns false during rngLock (`DegenerusGame:1656`) AND the autoOpen entry-gate returns 0 during the freeze
(`:1692` `rngLockedFlag || _livenessTriggered()`), so the open path NEVER executes inside the protected
window. The player-controllable `totalFlipReversals` nudge stays frozen request→consume. **Composition verdict:
RNG-freeze NON-WIDENING under the router composition.**

---

## 4. Reentrancy disposition (ROUTER-07) — re-attestation, NOT a hunt

Per the USER-locked 332 stance + the 329-SPEC ROUTER-07 disposition: **NO `nonReentrant` guard on `doWork`**,
re-grounded on the unified single `creditFlip`. Under RD-4 there is exactly ONE `creditFlip` in `doWork`
(`:917`), CEI-LAST, after the one-category early-return, fed by legs that return raw counts/`mult` and never
self-credit. Every external call targets a pinned `ContractAddresses.*` (GAME / COINFLIP); the bounty is
minted FLIP CREDIT through the `claimableWinnings` pull ledger, never an ETH push the keeper-contract
receives; the keeper is never a payee of an untrusted send. **0 untrusted-push legs → 0 ROUTER-07 blocker.**
Recorded **SAFE_BY_DESIGN / structural attestation** (the active-attacker reentrancy harness is 333-02's
SWEEP-01 scope; the D-01b TST-02 double-pay regression `KeeperRouterOneCategory.t.sol` is the empirical
backstop).

---

## 5. Note on the ADV-02 `(mult, rewardable)` → `(uint8 mult)` collapse (USER deviation, NON-WIDENING)

The 329-SPEC R1 text specified `advanceGame` returning `(uint8 mult, bool rewardable)`. The frozen
implementation @ `4c9f9d9b` returns only `(uint8 mult)` — the `rewardable` bool was COLLAPSED into the
`mult == 0` sentinel (the USER deviation recorded at IMPL: `mult > 0` ⇒ rewardable, `mult == 0` ⇒ the
gameover path pays nothing). The `doWork` consumer reads `mult > 0` as the rewardable predicate
(`if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult` `:899`); the gameover path returns `mult = 0`
(`AdvanceModule:185`) so the router pays no bounty. This collapse is **NON-WIDENING**: the rewardable
information is fully preserved in the `mult` channel (no bounty is paid when it should not be), the interface
matches the contract signature verbatim (both `returns (uint8 mult)`), and no payout path widened. The
collapse SHRINKS the surface (one fewer return value to decode/wire) — consistent with
[[feedback_frozen_contracts_no_future_proofing]].

---

## 6. Regression-Baseline Attestation — 666/42/17 NON-WIDENING BY NAME

> Mirrors the v48 FINDINGS §5 LEAN Regression Appendix. The AUTHORITATIVE source is
> `test/REGRESSION-BASELINE-v49.md` (the 332-06 ledger). This section CITES the ledger; it does NOT re-run
> `forge` or re-derive the numbers (D-09).

### 6.1 — The baseline (cite `test/REGRESSION-BASELINE-v49.md`)

The whole-tree `forge test` run at the v49 TST HEAD (`7d59ec16`) = **666 passed / 42 failed / 17 skipped**
(708 run). Per the ledger §1 arithmetic: the Phase-330 keeper-router diff `63bc16ca` + the Phase-331 GAS-2
re-peg `4c9f9d9b` flipped a set of **17 premise-retired reward-rehoming tests** from green-at-v48 to
red-at-v49; 332-05 (TST-04 part A) **DELETED all 17** (their v49 invariants re-authored fresh at 332-02/03/04,
zero coverage lost) and `git mv`-**renamed the 5 surviving `Crank*` files to `Keeper*`**. `59 − 17 = 42`;
the passing count stayed flat at **666** across the deletion (the deletions removed only RED tests).

### 6.2 — The BINDING gate: failing-NAME-set EQUALITY, NOT a count (the Pitfall-3 guard)

**NON-WIDENING = a strict failing-NAME-set equality**, NOT a count match: at the v49 TST HEAD the live
`forge test` failing set **== the 42 v48.0 §2-union reds BY NAME** (`test/REGRESSION-BASELINE-v48.md §2`,
carried forward verbatim — Bucket A 8 VRF/RNG + Bucket B 34 stale-harness/v48-behavioral + Bucket C 0
HERO-foundry = 42). The ledger §6 verified BOTH directions empirically this run:
`live failing set − v48 union = ∅` (no new red outside baseline) AND `v48 union − live failing set = ∅` (no
dropped baseline red) → `live == v48 union BY NAME` is TRUE. **Net-zero new regression.** Do NOT quote
"42 failures, up from 40" — the gate is name-set equality, not an arithmetic count delta (FC1 / T-332-06-COUNT).

### 6.3 — The 17 deletions + 5 renames are ATTRIBUTED via the ledger, NOT counted as regression

- **17 premise-retired deletions** (ledger §3, commit `8041451d`, 4 files / 736 deletions): each enumerated
  BY NAME with per-test re-homing + the v46 provenance commit (`3afbf676` / `795e679d` / `dfba3ac1` /
  `47b9d031` / `b9bc5206`). Classified reward-shape (RD-4 + GAS-2 per-item-summed premise retired) or
  oracle-migration (RD-2 guard-drop / RD-5 entry-gate / GASOPT-04 `AutoBought`→`lastAutoBoughtDay`). The
  retired premises re-home into the fresh v49 proofs (flat-per-tx one-credit / self-keeper round-trip ≤0 /
  `NoWork()`-on-no-work / RD-2 autoBuy-during-rngLock-safe / RD-5 no-marooned-boxes / per-item poison
  isolation) — **zero coverage lost.**
- **5 `Crank*`→`Keeper*` renames** (ledger §4, commit `52452fe1`, R094-R098 similarity): pure file-path +
  identifier churn. Foundry test contracts do not import each other → the renames are behavior-neutral,
  PROVEN by the byte-identical post-rename failing NAME set (666/42 both pre- and post-rename). The single
  deliberate `Crank` code residual (`testCrankBoxOpenStaysPostUnlock`, GREEN, in the NOT-renamed
  `RngFreezeAndRemovalProofs.t.sol`) is left unchanged per the explicit plan directive.

The file-path churn is attributed via the ledger, **NOT counted as new regression** (FC2 / T-332-06-ATTR).

### 6.4 — SWEEP-02 NON-WIDENING claim (the binding attribution)

Every `git diff 0cc5d10f 4c9f9d9b -- contracts/ test/` hunk is attributable to a known v49-scope commit:
- the batched IMPL/redesign diff **`63bc16ca`** (the 5-file router/advance contract surface — §1/§2);
- the GAS-split diff **`4c9f9d9b`** (the 331-05 re-peg constants in `AfKing.sol` + `DegenerusGame.sol`);
- the AGENT-committed 331 GAS + 332 TST test work (`acac8285`/`921599c2`/`480fa54f`/`648783e2`/`46f30546`/
  `322fd972` GAS harnesses; `a8b93040`/`41a49223`/`c7c57376`/`e2fff795`/`6f8bd35a`/`75284aac` 332 proofs;
  `8041451d` the 17 deletions; `52452fe1` the 5 renames; `11d1b1f5` the regression ledger itself).

`git diff 4c9f9d9b HEAD -- contracts/` is **EMPTY** (zero contract mutation since the frozen subject;
EMPTY-CONFIRMED this session). **SWEEP-02 NON-WIDENING CONFIRMED.**

---

## 7. Carried-Forward v48 SWAP Cash-Share Advisory (SC2, UNMODIFIED)

> Per CONTEXT D-05 + the plan Task 2: the v48 informational ADVISORY is **carried-forward-UNMODIFIED**
> verbatim. It is NOT a finding, does NOT amend the verdict, and does NOT stop closure.

**Verbatim from `audit/FINDINGS-v48.0.md` frontmatter `new_findings_disposition` (line 14):**

> "0 NEW_FINDINGS — both v47-deferred MEDIUM findings (F-47-01 presale closing-box DGNRS over-distribution
> + F-47-02 redemption submit ETH-empty stETH-fallback gap) RESOLVED-AT-V48; one informational ADVISORY
> (SWAP cash-share ceiling 60% code vs <=40% design memo — no-arb holds, doc-drift for USER reconciliation,
> NOT a finding)."

**Verbatim from `audit/FINDINGS-v48.0.md` §9d:**

> "Informational ADVISORY (NOT a finding) — SWAP withdrawable-cash ceiling 60% (code) vs <=40% (design memo).
> Recorded for USER reconciliation at the 328-04 closure gate: reconcile the design memo / verdict text to the
> implemented `<=60%` cash ceiling, OR confirm 60% was the intended IMPL calibration. No-arb HOLDS at the 60%
> ceiling (max withdrawable cash 9.9% of face); no positive-EV path; no solvency impact. `0 NEW_FINDINGS`
> unaffected."

**This advisory is carried-forward-unmodified into v49.0** (REQUIREMENTS Out-of-Scope: "SWAP cash-share ≤40%
tighten — the v48 advisory; USER accepted ≤60% as canonical. Revisit only if explicitly requested.").

**SWAP-path surface confirmed OUTSIDE the v49 blast radius:** NONE of the 5 v49 delta files touched the SWAP
path. Verified this session @ `4c9f9d9b`: the `sellFarFutureTickets` ENTRYPOINT body + the `ticketShareBps`
cash-share constant have **ZERO function-body hunks** in `git diff 0cc5d10f 4c9f9d9b -- contracts/` (the
`sellFarFutureTickets` symbol exists in `DegenerusGame.sol`/`MintModule.sol`/the interface — it SHIPPED in
v48 — but was not modified; the only "farFuture" diff hunks in `MintModule.sol` are the `inFarFuture` /
`_tqFarFutureKey` ticket-routing `rk`-key computation inside the GASOPT-01 `owedMap`-hoist region, NOT the
SWAP cash leg). Neither `DegenerusVault.sol` nor `StakedDegenerusStonk.sol` (the SWAP wrapper / `_payEth`
surfaces) appears in the v49 delta surface. The v48 SWAP advisory's surface is therefore untouched by v49 —
the carried-forward advisory remains accurate verbatim.

---

## 8. Read-only attestation + summary

- `git diff 4c9f9d9b HEAD -- contracts/` is **EMPTY** throughout (EMPTY-CONFIRMED) — ZERO `contracts/*.sol`
  was opened or mutated by this plan; all source was read via `git show 4c9f9d9b:contracts/...`.
- **5 surfaces all attested NON-WIDENING** with re-grep-verified anchors @ `4c9f9d9b`; every delta hunk maps
  to exactly one v49 work item (zero orphan hunks).
- **Kill-sets grep-ZERO in mainnet code:** 3 advance in-callee keeper `creditFlip` sites removed
  (`:189`/`:225`/`:468`; only the SDGNRS U6 credit at `:860` survives); autoBuy stall ladder deleted;
  `AutoBought` event dropped; per-iter `isOperatorApproved` `:676` dropped (subscribe-time `:401`/`:399` kept).
- **4 structural invariants intact** (a/b/c/d) cross-ref'd to TST-02 / ADV-04+TST-01 / D-04a / GAS-03.
- **OPEN-E 4-protection re-attestation: ALL 4 HOLD** (HARD BLOCKING CONDITION SATISFIED — no revert needed).
- **VRF/RNG-freeze INTACT** under the router composition (no in-window SLOAD introduced).
- **Regression 666/42/17 NON-WIDENING BY NAME** (ledger-cited; 17 deletions + 5 renames attributed, not
  counted as regression).
- **v48 SWAP cash-share advisory carried-forward-unmodified**; SWAP path confirmed outside the v49 blast
  radius.

*SWEEP-02 satisfied. 333-01 DELTA-AUDIT authored 2026-05-27. Subject frozen at `4c9f9d9b`
(`git diff 4c9f9d9b HEAD -- contracts/` empty throughout).*
