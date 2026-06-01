# 348-INVARIANT-CARRY — The Discharged REVERT-FREE-CHAIN + EV-Cap Invariants, Carried as Locked v55 SPEC Invariants (AS AMENDED by D-348-04)

**Phase:** 348 — SPEC (paper-only; **zero `contracts/*.sol` edits**) · **Plan:** 348-03 · **Authored:** 2026-05-30
**Subject HEAD:** `f353a50b` — `contracts/` **byte-identical** to the v54 de-custody HEAD `20ca1f79`
(`git diff --numstat 20ca1f79 HEAD -- contracts/` EMPTY; docs-only since). Live grep IS a valid attestation.
**Anchor source:** the re-pinned live lines in `348-GREP-ATTESTATION.md` (348-01). This doc cites the ACTUAL re-grepped
lines.
**Source of truth carried (AS AMENDED):** `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §5 (the 4 LOCKED obligations) + §7
(the 3 SPEC follow-ups) + §3 (the slice-builder discharge = obligation-1 substrate) + §4 (EV-cap-at-open). **The
REVERT-FREE-CHAIN invariant is DISCHARGED** — v54 is already revert-free on the funded afking path; v55's job is
**migration fidelity** (obligation 1), not re-proving.

> **Amended 2026-05-30 (D-348-07):** score + baseLevel moved from live-read → stamped-frozen in the afking Sub stamp
> (now `(index, amount, day, scorePlus1, baseLevelPlus1)`); supersedes D-348-05 for those fields; residual live-read =
> the EV-cap monotonic clamp only. The stamp grows by 40 bits (`scorePlus1` uint16 + `baseLevelPlus1` uint24) into
> slot 2's ~90 spare bits — still **2-slot-feasible** (cites the human precedent widths at `LB:530`). The
> `evMultiplierBps` fed to `_applyEvMultiplierWithCap` now derives from the FROZEN `scorePlus1` (obligation 2/EVCAP-01),
> while the cap RMW itself stays live (benign monotonic clamp).

**Purpose:** 349 IMPL inherits the corrected (no-try/catch) invariant set + a verified obligation-1 so it can build the
process-pass + the box-stamp without re-opening the proof. This doc:
1. carries obligations 1–3 as the v55 locked invariant set;
2. records the **D-348-04 correction** (DROP the try/catch valve → no-valve form) as an explicit rewrite of
   REQUIREMENTS.md `REVERT-02` + proof §5 obligation 4 (parallel to how 343's D-01 corrected `AUTOBUY-02`);
3. reconciles the two §10 knock-ons (the rule-(2) pre-emptive skip; the eviction-cap re-evaluation);
4. discharges the 3 §7 follow-ups (cost-units; stamp field widths; the double-draw guard);
5. records the **light `/contract-auditor` obligation-1 pass** (D-348-06) as a per-invariant disposition + verdict.

---

## 1. The v55 locked invariant set — obligations 1–3 (AS AMENDED; obligation 4 DROPPED by D-348-04)

### Obligation 1 (LOAD-BEARING — now the SOLE no-brick guarantor): preserve `_resolveBuy`'s validation invariants VERBATIM

When AfKing's `_resolveBuy` (`AfKing.sol:727-795`) folds into the Game process-pass, the slice-builder validation
invariants must be preserved **verbatim**. This is a *migration-fidelity* obligation, not new design — it is exactly
what makes the funded buy revert-free by construction (proof §3). The specific invariants (re-pinned live lines):

| Invariant | Live line(s) | What it guarantees |
|-----------|--------------|--------------------|
| `effectiveQty = max(dailyQuantity, reinvestQty) ≥ 1` | `:756` / `:758-759`; `dailyQuantity==0` reverts at subscribe `:332` | quantity ≥ 1 → never hits the Game's `totalCost==0` / dust / `< TICKET_MIN_BUYIN_WEI` reverts |
| `cost = mp * effectiveQty` | `:761` | the exact cost the Game recomputes (see §4-i cost-unit reconciliation) |
| `LOOTBOX_MIN` transient skip (lootbox mode only) | `:772-774` (`if (cost < LOOTBOX_MIN) { lootboxSkip = true; return; }`); `LOOTBOX_MIN` decl `:269` | a sub-floor lootbox amount sets `lootboxSkip` and the sub STAYS in the set to retry — never hits `MintModule:1057` `< LOOTBOX_MIN` |
| 1-wei claimable sentinel | `:790` (`if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;`) | leaves `claimable > cost` and `basis > shortfall` → never hits the Game's Claimable `claimable <= amount` (`Game:976`) nor the shortfall settle `basis <= shortfall` (`Storage:843`) |
| `ev = cost − claimableUse` | `:791` (`ethValue = cost - claimableUse;`) | `ev ≤ cost` and the DirectEth/Combined fund-checks hold by construction (`ev==cost` for DirectEth; `ev + claimableUse == cost` for Combined) |
| enum-typed payKind ∈ {0,1,2} | `:792-794` (`MintPaymentKind` enum decl `AfKing.sol:9`) | never hits the unknown-payKind `else revert` (`Game:1006`) nor the enum-cast Panic 0x21 (`batchPurchase:1922`) |

The comment at `AfKing.sol:781-782` ("Never spend the entire claimable balance — leave >= 1 wei (the GAME's Claimable
branch needs claimable strictly > cost, and the claimable shortfall settle needs basis > shortfall)") is direct
evidence the slice builder was authored against the Game-side revert set. **Consequence of D-348-04 (below): obligation
1 is now the SOLE day-can't-brick guarantor under required-path** — which is exactly why the light `/contract-auditor`
pass (§5) sits here.

### Obligation 2: EV-cap at open via `_applyEvMultiplierWithCap`, keyed `[player][level+1]`, exactly once, buy-time write BYPASSED

The afking open-pass routes the box through **`_applyEvMultiplierWithCap(player, level+1, amount, mult)`**
(`LB:459-495`) — the same shape `resolveLootboxDirect` / `resolveRedemptionLootbox` use — which does the cap READ
(`:473`) and WRITE (`:488`) **atomically at open**, keyed on the **same** `lootboxEvBenefitUsedByLevel[player][level+1]`
map MintModule uses at buy (`MintModule:1298/1303` and `:1321/1327`, both keyed `[buyer][cachedLevel + 1]`).

- **Equivalent to the v54 per-(sub,level) accumulator:** same map + same `level+1` key + exactly-once RMW per open = one
  shared per-level 10-ETH budget (`LOOTBOX_EV_BENEFIT_CAP = 10 ether`, `Storage:1326`) across afking and any residual
  human boxes. This discharges the proof's §8 "prove the EV-cap accumulator is equivalent" item.
- **Hard-clamped ≤ 10 ETH, NO revert:** the write is `used + min(amount, CAP − used)` and short-circuits to a no-write
  100%-EV `return amount;` once the cap is hit (`LB:478-481`). The scale `(adjustedPortion · evMultiplierBps)/10_000`
  is bounded (`evMultiplierBps ≤ 13_500`, divisor constant). So the EV-cap increment cannot contribute a revert (it is
  NOT a class-B solvency site).
- **Buy-time write BYPASSED (no double-draw):** with boons OFF and the process-pass *stamping*
  `(index, amount, day, scorePlus1, baseLevelPlus1)` (not routing through `_callTicketPurchase`'s lootbox tally), the
  buy-time EV write at `MintModule:1303/1327` must NOT also fire for afking boxes — the open does the single RMW (its
  `evMultiplierBps` derived from the frozen `scorePlus1`). (See §4-iii, the double-draw guard.)

> **Live-read coupling (reframed under D-348-07):** score + baseLevel are now FROZEN — stamped `scorePlus1` /
> `baseLevelPlus1` at process and read from the stamp at open (`348-FREEZE-PROOF.md` FREEZE-01a). The **only** residual
> live-read is the EV-cap RMW itself (`lootboxEvBenefitUsedByLevel[player][level+1]`), a shared per-(player,level)
> cumulative accumulator that cannot be per-box-stamped — a **benign monotonic down-clamp** (hard ≤10 ETH, no
> profitable timing; FREEZE-01b), NOT the former score/baseLevel/EV-cap window. The `evMultiplierBps` fed into the cap
> helper now derives from the frozen `scorePlus1`; the equivalence + no-revert + no-double-draw stated here are the
> *correctness* obligations on top of that.

### Obligation 3: stamp `(index, amount, day, scorePlus1, baseLevelPlus1)`; seed the open with the STAMPED buy-day

Stamp `(index = pre-RNG LR_INDEX, amount = spend, day = boundary-pinned process day, scorePlus1 = activityScore+1,
baseLevelPlus1 = baseLevel+1)` into the Sub record at process (D-348-07 — score+baseLevel frozen at process, the analog
of the human deposit-time freeze of `lootboxPurchasePacked`, `LB:529-530`), and seed the open from the **stamped** day
— mirroring today's frozen `lootboxDay[index][player]` (`LB:514`), NEVER open-time `_simulatedDayIndex()` (`LB:513` and
the template sites `:766/:799/:836/:868`). The seed itself is UNCHANGED — it consumes only `(rngWord, player, day,
amount)` (`LB:534`); score+baseLevel enter AFTER the seed (scale/floor) and are read from the stamp, NOT live. Full
proof in `348-FREEZE-PROOF.md` (FREEZE-02 index-binding + FREEZE-03 stamped-day determinism + FREEZE-01a stamped
score/baseLevel). Carried here as the third locked obligation because it is the third member of the invariant set the
349 process-pass must satisfy.

### Obligation 4: ~~thin per-sub try/catch skip valve~~ → **DROPPED (D-348-04)** — see §2.

---

## 2. Correction to REVERT-02 + proof §5 obligation 4 — DROP the try/catch valve (D-348-04)

> **This is a REWRITE of a carried invariant** — the direct parallel to how Phase 343's **D-01 corrected
> `AUTOBUY-02`** (→ `b.funder`). It is recorded here prominently so 349 builds against the corrected form, not the
> stale one.

### What currently says "try/catch valve" (the two lines this correction rewrites)

- **`REQUIREMENTS.md` REVERT-02** (349-owned) currently reads: *"A thin per-sub **try/catch** skip valve isolates the
  process AND open legs, absorbing the two residual revert classes (solvency-violation [safe under SOLVENCY-01],
  liveness-timeout [game-dead]) so no single sub can brick a batch / the day."*
- **`PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §5 obligation 4** currently reads: *"Per-sub skip safety-valve (try/catch-
  isolated …) on BOTH the process and open legs …"*

### The corrected form (NO valve)

> **REVERT-02 (corrected): NO valve.**
> - **Healthy path: revert-free-by-construction (obligation 1).** A funded, well-formed sub cannot revert (the
>   slice-builder invariants of §1 structurally prevent every Game-side input revert). There is **nothing to catch** —
>   a try/catch on the healthy path is dead code.
> - **Class B (solvency-violation): FAIL LOUD.** The residual reverts are the `claimablePool -= uint128(...)`
>   subtractions (`Game:1010`, `Game:1912`, `Storage:847`). Each subtrahend ≤ a per-account balance ≤ the `uint128`
>   `claimablePool` by **SOLVENCY-01** (proven at Phase 343: every free-ETH reservation site reserves `claimablePool`
>   inclusive of the afking total). A revert here means SOLVENCY-01 is **already violated** — a catastrophic state.
>   **Catching it would MASK a catastrophic solvency bug.** It MUST propagate (fail loud), never be swallowed.
> - **Class C (liveness-timeout): TERMINAL — routing-unblocked.** The liveness reverts (`_livenessTriggered → revert
>   E()` at `MintModule:1050`; `_queueTickets:579`) fire only when the game is ≥120-day-inactivity / VRF-death terminal
>   — heading to game-over, afking buys/opens moot. Instead of a valve, the SPEC requires the 349 IMPL to **verify the
>   afking STAGE cannot block the game-over routing** (game-over is a separate `advanceGame` path — the STAGE must not
>   sit on the path that reaches it). Class C is absorbed by the game ending, not by catching per-sub.

### Consequence: the proof burden CONCENTRATES on obligation 1

Removing the valve means there is no catch-all backstop — so the entire no-brick guarantee rests on obligation 1
(slice-builder fidelity). This is the single sharpest IMPL-discipline point of the redesign, and it is precisely where
the rigor belongs: the light `/contract-auditor` obligation-1 pass (§5) verifies the §1 invariants are stated correctly
for the fold.

### Two §10 knock-ons reconciled

**(a) §10 process-pass rule (2) "mint slice fails → SKIP" becomes a PRE-EMPTIVE skip.** Under the dropped-valve model,
rule (2) is no longer a reactive try/catch of a failed mint — it is a **pre-emptive** skip: the slice builder
*declines to build an unbuildable slice* before any Game call. The only pre-emptive skip in `_resolveBuy` today is the
`LOOTBOX_MIN` transient skip (`:772-774`), which sets `lootboxSkip=true` and returns without calling the Game — the sub
STAYS and retries. **Proof that rule (2) is effectively unreachable in a healthy game:** under obligation 1 every funded
slice the builder *does* build is revert-free by construction (§1), so there is no "mint slice fails" event for a funded
well-formed sub — the only non-build is the `LOOTBOX_MIN` floor (a transient retry, not an eviction) and the unfunded
case (rule (1), below). Hence rule (2) reduces to "decline to build a sub-floor lootbox slice this cycle," which is the
existing `lootboxSkip` behavior, NOT a revert-catch. (351 TST-02 confirms empirically that a funded process never
reverts on well-formed slices.)

**Rule (1) is UNAFFECTED.** Normal eviction of an **unfunded** sub (insufficient `afkingFunding` to cover even the
minimum) remains a legitimate, pre-buy decision — it is not a revert-catch and does not depend on the valve. The
process-pass still evicts (or skip-exempts) unfunded subs as before.

**(b) §10's "optional per-cycle eviction cap" — RE-EVALUATED.** This cap existed to bound a *revert-driven mass
eviction* (a wave of subs all failing and being evicted in one cycle). **D-348-04 removes that rationale entirely** —
there is no revert-driven eviction anymore (the only evictions are the deliberate rule-(1) unfunded case; failures are
pre-empted, not caught-then-evicted). **Recommendation: DROP the optional per-cycle eviction cap.** It guarded against a
failure mode (mass eviction triggered by reverts) that no longer exists under the no-valve model. Dropping it also
removes a per-cycle bookkeeping field and a tunable with no remaining purpose. (If 349 later finds a *gas*-driven reason
to bound evictions per cycle — distinct from the retired revert-driven rationale — that is a GAS-phase (350) decision,
not a freeze/revert one; flagged here so the cap's removal is a deliberate recorded choice, not an oversight.)

---

## 3. The 3 §7 SPEC follow-ups — DISCHARGED

### (i) Cost-unit reconciliation: AfKing `mp · effectiveQty` ≡ Game `priceForLevel · ticketQuantity / (4 · TICKET_SCALE)`

The folded process-pass must compute `cost` **identically** to the Game so the preserved slice-builder math (§1) lines
up with the Game's recompute. The two formulas reconcile **exactly** — with one load-bearing constant subtlety:

- **AfKing side:** `cost = mp * effectiveQty` (`AfKing.sol:761`); ticket `amount = effectiveQty * TICKET_SCALE` where
  **AfKing's `TICKET_SCALE = 400`** (`AfKing.sol:238`). So AfKing's entry-unit `ticketQuantity = effectiveQty * 400`.
- **Game side:** `ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)` (`MintModule:1062`) where **Storage's
  `TICKET_SCALE = 100`** (`DegenerusGameStorage.sol:166`), so the Game divisor `4 * TICKET_SCALE = 400`.
- **Substitute** `priceWei = mp`, `ticketQuantity = effectiveQty * 400`:
  `ticketCost = mp * (effectiveQty * 400) / 400 = mp * effectiveQty` = **AfKing's `cost`.** ✅ Equivalence holds.

> **⚠ Load-bearing for the 349 fold (a deliberate dual-constant):** AfKing's `TICKET_SCALE = 400` is numerically equal
> to the Game's `4 * TICKET_SCALE` (= 4 × 100). They are **different named constants with different values** (400 vs
> 100) that happen to compose to the same 400 divisor/multiplier. When the process-pass folds into the Game module, the
> IMPL MUST NOT naively reuse one `TICKET_SCALE` symbol for both roles — it must preserve `amount = effectiveQty * 400`
> (entry-units) AND the Game's `/ (4 * 100)` divisor so `cost` stays `mp * effectiveQty`. This is exactly the kind of
> constant-collision a verbatim-preservation fold can silently break; flagged so 349 carries the right numeric in each
> role. (No revert risk either way — this is a correctness/equivalence check, as §7 states.)

### (ii) Stamp field widths hold `amount` (full wei) + `index` + `day` + `scorePlus1` + `baseLevelPlus1`

The stamp is `(index, amount, day, scorePlus1, baseLevelPlus1)` (D-348-07 — score+baseLevel stamped-frozen):
- `amount` — **full wei** spend. A box `amount` is bounded by the per-box economics but must be stored at full `uint256`
  fidelity to feed the seed (`LB:534` consumes `amount` as a 32-byte `abi.encode` field) and the payout math — so
  `amount` takes a full slot (or is packed into a wide-enough field; today `lootboxEth` packs `amount` in the low 232
  bits with `purchaseLevel` in the top 24, `LB:505-509`, a workable precedent if a packed layout is chosen).
- `index` — the lootbox RNG index, `uint48` (today's `openLootBox` takes `uint48 index`, `LB:503`; `_finalizeLootboxRng`
  uses `uint48`, `:1230`). Fits comfortably alongside other small fields.
- `day` — the simulated day index, `uint32` (today's `lootboxDay` and `_simulatedDayIndex()` are `uint32`, `LB:513-514`).
- `scorePlus1` — the frozen activity score+1, `uint16` (D-348-07). Cites the human precedent: the human deposit-freeze
  unpacks `(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1)` from `lootboxPurchasePacked[index][player]` at
  `LB:529-530` — the afking stamp reuses the `scorePlus1` width (uint16) but does **NOT** carry `adj` (the open passes
  the full stamped `amount` to `_applyEvMultiplierWithCap` and derives the cap-adjusted portion live).
- `baseLevelPlus1` — the frozen baseLevel+1, `uint24` (D-348-07; same width as the human `baseLevelPlus1` at `LB:530`).

**Disposition:** the five fields fit a **2-slot Sub-record extension** (the §8 Sub-record-width item) — one full slot
for `amount` (or `amount` packed with `purchaseLevel`-style headroom) + one slot holding `index` (`uint48`) + `day`
(`uint32`) + `scorePlus1` (`uint16`) + `baseLevelPlus1` (`uint24`) + the existing `lastAutoBoughtDay` / `lastOpenedIndex`
markers. The added 40 bits (`scorePlus1` 16 + `baseLevelPlus1` 24) drop into slot 2's ~90 spare bits alongside the
existing ~160 bits of small fields — **the same single SSTORE, no third slot**. The exact packing is a 349 layout
decision (pre-launch redeploy-fresh → storage break is fine, no migration); the SPEC confirms the widths are
**sufficient and still 2-slot-feasible** with the two D-348-07 fields added, which is all §7 asks.

### (iii) Double-draw guard: the process-pass never routes through `_callTicketPurchase`'s lootbox EV tally

This is the obligation-2 double-draw guard. The buy-time EV write lives inside the ticket-purchase queue logic
(`MintModule:1261` "Queue tickets (moved from `_callTicketPurchase`)", with the `lootboxEvBenefitUsedByLevel` writes at
`:1303` and `:1327`). The process-pass **stamps** `(index, amount, day, scorePlus1, baseLevelPlus1)` and **does not**
route through `_callTicketPurchase` (`MintModule:1496`) nor reach the `:1303/:1327` buy-time tally — the single EV RMW
happens at OPEN via `_applyEvMultiplierWithCap` (obligation 2). **Disposition:** confirmed against source — the
process-pass's job is a stamp + `afkingFunding` debit + success-marker, none of which touch `MintModule:1303/1327`; the
open does the one live
RMW. 349 must preserve this separation (stamp at process, single RMW at open); 351 TST-04 (two-path) covers it
empirically.

---

## 4. Residual revert classes (carried, accepted — for completeness)

- **Class B — solvency-backed subs.** `Game:1010` / `Game:1912` / `Storage:847` (`claimablePool -= uint128(...)`):
  each subtrahend ≤ `claimablePool` by SOLVENCY-01 (Phase 343); reverts only if SOLVENCY-01 is already violated.
  **Accepted; FAIL LOUD (D-348-04) — never caught.** Documented dependency on SOLVENCY-01.
- **Class C — liveness-timeout.** `MintModule:1050` / `_queueTickets:579`: fires only in the ≥120-day terminal state.
  **Accepted; terminal — the SPEC requires verifying the STAGE cannot block game-over routing (D-348-04), no valve.**

`mintForGame` (`BurnieCoin:444`) and `transferFromPool` (`Stonk:478`) are **NOT reached on the buy path** (proof §2/§7);
the buy pays BURNIE only as `creditFlip` flip-credit and routes ETH only to prize pools / claimable.

---

## 5. Light /contract-auditor pass — obligation-1 (D-348-06)

**Scope (D-348-06):** obligation-1 ONLY — verify the slice-builder invariants are **stated correctly for the fold**
(`ev = cost − claimableUse` + enum payKind; the 1-wei claimable sentinel; the `LOOTBOX_MIN` transient skip;
`quantity ≥ 1`). This is a contract-correctness check on the no-brick guarantor, **distinct** from the freeze tradeoff
(self-attested known issue). **All other adversarial probing is deferred to the 352 TERMINAL in-milestone 3-skill sweep
on the real folded code** — this is NOT a paper re-audit of v54.

**Method note (transparency):** the executing agent did not have the Task/Skill tool to spawn the `/contract-auditor`
subagent, so this pass was performed **inline with an adversarial auditor's mindset** — reading the slice-builder source
directly (`AfKing.sol:727-795`, the named-revert comment `:781-782`, the `LOOTBOX_MIN` skip `:772-774` + decl `:269`,
`cost = mp * effectiveQty` `:761`, the 1-wei sentinel `:790`, `ev = cost − claimableUse` `:791`, the `payKind` enum
`:792-794` + decl `:9`) and the Game-side revert primitives it must avoid, against the re-pinned anchors. The 352
in-milestone sweep runs the real `/contract-auditor` on the folded code.

### Per-invariant disposition

| # | Obligation-1 invariant | Live line(s) | Stated correctly for the fold? | Auditor note |
|---|------------------------|--------------|-------------------------------|--------------|
| 1 | `quantity ≥ 1` (`effectiveQty = max(dailyQuantity, reinvestQty)`, `dailyQuantity==0` reverts at subscribe) | `:756`/`:758-759`; `:332` | **YES** | `effectiveQty` starts at `sub.dailyQuantity` (≥1, enforced at subscribe `:332`) and only increases via the reinvest bump — it can never drop below 1. Stated correctly: the fold must keep the subscribe-time `dailyQuantity ≥ 1` gate AND the `max(...)` shape. Guards the Game's `totalCost==0`/dust/`TICKET_MIN_BUYIN_WEI` reverts. |
| 2 | `LOOTBOX_MIN` transient skip (lootbox mode) | `:772-774`; decl `:269` | **YES** | `if (cost < LOOTBOX_MIN) { lootboxSkip = true; return (...); }` — sets the skip flag and returns WITHOUT a Game call; the sub stays in the set (transient, retries). Correctly a **pre-emptive** skip (matches the D-348-04 §2a reconciliation — not a revert-catch). The fold must carry `LOOTBOX_MIN` (decl `:269`) into the Game-resident process-pass and preserve the early-return-without-call shape. Guards `MintModule:1057`. |
| 3 | 1-wei claimable sentinel | `:790` | **YES** | `if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;` — leaves `claimable` strictly `> claimableUse` (and `> cost` on the Claimable/Combined branches), so `basis > shortfall` for the settle. Stated correctly; the comment `:781-782` names the exact two reverts it avoids (`Game:976` Claimable `claimable <= amount`; `Storage:843` `basis <= shortfall`). The fold must preserve the `>= claimable → claimable - 1` clamp verbatim. |
| 4 | `ev = cost − claimableUse` | `:791` | **YES** | `ethValue = cost - claimableUse;` with `claimableUse ≤ cost` (the drainFirst branch caps at `cost` `:788`; the reinvest branch caps `reinvestSpend > cost → cost` `:786`; the sentinel `:790` only lowers `claimableUse`). So `0 ≤ ev ≤ cost`. Stated correctly: DirectEth ⟹ `claimableUse==0` ⟹ `ev==cost`; Combined ⟹ `ev + claimableUse == cost`; Claimable ⟹ `ev==0`. Guards `Game:968/985/1003`. The fold must keep the `cost − claimableUse` derivation AND the `claimableUse` caps that keep it in `[0, cost]`. |
| 5 | enum-typed payKind ∈ {0,1,2} | `:792-794`; enum decl `:9` | **YES** | `payKind = ev==0 ? Claimable : (claimableUse==0 ? DirectEth : Combined)` — a `MintPaymentKind` enum (decl `AfKing.sol:9`), so `uint8(payKind) ∈ {0,1,2}` by construction. Stated correctly; guards the unknown-payKind `else revert` (`Game:1006`) and the enum-cast Panic 0x21 (`batchPurchase:1922`). The fold must keep payKind **enum-typed end-to-end** (not a raw `uint8` that could be constructed out of range). |

### Adversarial cross-checks the auditor ran (no findings)

- **Could `claimableUse > cost` slip through and make `ev` underflow (`cost − claimableUse`)?** No. drainFirst caps at
  `cost` (`:788`); reinvest caps `reinvestSpend` at `cost` (`:786`) and `claimableUse = reinvestSpend` (`:787-789`); the
  sentinel (`:790`) only lowers it. `claimableUse ≤ cost` always ⟹ no underflow at `:791`.
- **Could the reinvest bump make `effectiveQty` so large that `cost = mp * effectiveQty` overflows?** `effectiveQty`
  from reinvest is `(claimable * reinvestPct) / 100 / mp` (`:758`), so `mp * effectiveQty ≤ claimable * reinvestPct /
  100 ≤ claimable` — bounded by a real balance, far below `2^256`. No overflow.
- **Does the `LOOTBOX_MIN` early return leave the other return values well-formed?** Yes — it returns the zero-valued
  tuple with `lootboxSkip = true` (`:773-774`); the caller branches on `lootboxSkip` and does not consume `payKind`/
  `ev`/`amount` for a skipped sub. Stated correctly for the fold (the process-pass must branch on `lootboxSkip` before
  using the payment fields).
- **Is there a payKind the ternary cannot produce?** The ternary covers all three enum values exhaustively
  (`Claimable` when `ev==0`; `DirectEth` when `ev≠0 ∧ claimableUse==0`; `Combined` otherwise). No fourth state.

### Verdict

**PASS — all five obligation-1 invariants are stated correctly for the fold; zero mis-statements; zero findings.**
The slice-builder discharge (proof §3) is sound and the invariants are precisely the ones the fold must preserve
verbatim. Obligation 1 is a credible SOLE no-brick guarantor under the no-try/catch (D-348-04) required-path, **provided
the 349 fold preserves all five invariants verbatim** (including the dual-`TICKET_SCALE` cost-unit subtlety of §3-i and
the enum-typed payKind end-to-end). No obligation-1 invariant is mis-stated → no design-gating blocker on the
obligation-1 axis. (Residual freeze obligation — the FREEZE-02 `subsFullyProcessed` no-interleave guard — is owned by
`348-FREEZE-PROOF.md`, not this pass.)

---

## 6. Hand-off to 349 (what is now locked)

- **Invariant set:** obligations 1–3 (§1) are the v55 locked invariant set; obligation 4 is DROPPED (§2).
- **REVERT-02 corrected:** no valve — revert-free-by-construction (obl 1) + fail-loud-on-solvency (class B) +
  terminal-routing-unblocked (class C). 349 IMPL owns REVERT-01 (preserve the §1 invariants verbatim) + REVERT-02 (the
  corrected no-valve placement + the game-over-routing verification).
- **EVCAP-01 (349-owned):** `_applyEvMultiplierWithCap(player, level+1, amount, mult)` at open, exactly once, ≤10 ETH
  no-revert, buy-time write bypassed. The `mult` (`evMultiplierBps`) now derives from the **FROZEN** `scorePlus1`
  (stamped at process, D-348-07) — NOT a live score recompute; the cap RMW itself stays live (benign monotonic clamp).
- **§10 knock-ons:** rule (2) is a pre-emptive skip (effectively unreachable for funded subs); the optional per-cycle
  eviction cap is recommended DROPPED (lost its revert-driven rationale); rule (1) unfunded eviction unaffected.
- **§7 follow-ups discharged:** cost-units equivalent (mind the dual `TICKET_SCALE` = 400 vs 4×100); stamp widths now 5
  fields (`index, amount, day, scorePlus1, baseLevelPlus1`, D-348-07) — still 2-slot-feasible (40 bits into slot 2's
  spare); double-draw guarded (stamp at process, single RMW at open).
- **Obligation-1 light auditor pass:** PASS (5/5 invariants stated correctly; §5).

---

*Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is empty (only the pre-existing unrelated
`scope.txt` change is in the working tree, untouched by this plan). Paper-only SPEC carry; the only CLI used was
`git diff` + `grep`/read (read-only source inspection). Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-03.*
