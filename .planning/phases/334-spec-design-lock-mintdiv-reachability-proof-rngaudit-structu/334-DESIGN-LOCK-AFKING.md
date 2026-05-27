# Phase 334 — AfKing Pass-Gated Subscription Design-Lock (SC1, the AFSUB slice)

**Authored:** 2026-05-27
**Plan:** 334-03 (SPEC — Design-Lock)
**Requirement:** BATCH-01 (settles the AFSUB-01..05 signatures; implemented at IMPL 335)
**Audit baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`
**Anchor attestation note:** Working-tree HEAD is `a4e39d50` — docs commits sit on top of `b0511ca2`; `git diff b0511ca2 HEAD -- contracts/` is EMPTY, so every `file:line` below was grep-confirmed directly against the frozen contract baseline (re-verified 2026-05-27 during execution of this plan).

---

## 0. Purpose & Scope

This document settles, **in writing**, the AfKing pass-gated subscription signatures so the IMPL phase (335) re-authors them in the **one batched contract diff** with zero "by construction" assumptions. Even though the implementing requirements (AFSUB-01..05) land at 335, their signatures are settled now: the `validThroughLevel` field placement, the new level-horizon pass view, the refresh-or-evict crossing control flow, the `burnForKeeper` removal across both contracts, and the preservation criteria (OPEN-E 4-protection, SUB-07 cancel-tombstone, v49 swap-pop) the pass-gated model must satisfy.

**This is a paper-only SPEC artifact. Zero `contracts/*.sol` edits in Phase 334.** The contract changes these decisions govern land at IMPL 335 under the single-batched-diff HARD STOP.

**Decision provenance:** D-08..D-13 in `334-CONTEXT.md`; Architecture Patterns 2 & 3 + the "Don't Hand-Roll" / Anti-Pattern guidance in `334-RESEARCH.md`; the memory invariants `open-e-operator-approval-trust-boundary` + `afking-cancel-tombstone-streak-finding` + `feedback_security_over_gas` + `feedback_frozen_contracts_no_future_proofing`.

---

## 1. The pass-gating scope is the autoBuy sub window ONLY (D-08)

The subscription window gates **autoBuy** — the daily box-buying leg, cursor-driven via `_autoBuyCursor` (`AfKing.sol:214`). `autoOpen` is a **permissionless router leg**: boxes are openable by anyone (there is no "window" to gate) and it stays **UNCHANGED** by this design. The seed's open "autoBuy / autoOpen / both?" question resolves to **autoBuy only, by construction** — the level-window only ever fronts the `subscribe`-set state read inside the `_autoBuy` sweep.

> **Scope guard:** any IMPL-335 task that touches the autoOpen path under the banner of "pass-gating" is out of scope for AFSUB. autoOpen's only v50 change is the *separate* WHALE-03 carve-out retirement (flat `OPEN_BATCH`), which is a WHALE item, not an AFSUB item.

---

## 2. The `validThroughLevel` field placement (D-11/D-12/D-13 + Claude's Discretion)

### 2.1 The frozen `Sub` layout being repurposed

`AfKing.sol:86-93` — single storage slot, reached through `_subOf` at slot 1 (layout doc `:79-82`):

```solidity
struct Sub {
    uint8   dailyQuantity;     // offset 0
    uint32  lastAutoBoughtDay; // offset 1
    uint32  paidThroughDay;    // offset 5  <-- the field to repurpose (the 30-day rolling prepay window endpoint)
    uint8   reinvestPct;       // offset 9
    uint8   flags;             // offset 10  (bit 0 = windowPaid, bit 1 = drainGameCreditFirst, bit 2 = useTickets)
    address fundingSource;     // offset 11  (address(0) = self)
}
```

### 2.2 Settled placement — in-place reinterpretation of the `paidThroughDay` slot

**`validThroughLevel` repurposes the existing `Sub.paidThroughDay` slot (offset 5, `uint32` — `AfKing.sol:89`).** This is an **in-place reinterpretation**, not a layout break: the on-chain `level` is `uint24` (it drives `frozenUntilLevel` as a `uint24` at `DegenerusGame.sol:1524`), and a `uint24` level fits the `uint32` field with headroom (the `type(uint24).max` deity sentinel, §3.2, fits — `0xFFFFFF` < `0xFFFFFFFF`). The day-denominated `paidThroughDay` semantics retire (D-09); the level-denominated `validThroughLevel` semantics replace them at the same byte offset.

- **Recommended typing (Claude's Discretion, constrained by D-11/D-12):** keep the field `uint32` (zero packing churn) OR narrow it to `uint24` to mirror `level`'s width — both are acceptable; the IMPL planner picks. The settled semantic is the *meaning* (a level horizon), not the exact width.
- **Layout-break tolerance (D-13):** the protocol is pre-launch redeploy-fresh; **any storage-layout break is fine regardless** (no live state, no migration — D-13). The in-place reinterpretation is chosen for minimal diff, NOT because a break would be a problem. The seed's "in-flight BURNIE-paid window at cutover / refund / grandfather" question is therefore **moot** (D-13).
- **Freed flag bit:** the `FLAG_WINDOW_PAID` bit-0 semantics (`AfKing.sol:81` flags doc; set/cleared at `:433/:442/:634/:650`) retire with `burnForKeeper` (D-09, §5) — the bit is freed. No future-proofing reservation of it (`feedback_frozen_contracts_no_future_proofing`).

---

## 3. The new level-horizon pass view (D-11)

### 3.1 Why a boolean is insufficient

Today's free-extend uses the **boolean** `hasAnyLazyPass(address) returns (bool)` at `DegenerusGame.sol:1520` (also read at AfKing subscribe `:432` and the day-31 crossing `:631`):

```solidity
// DegenerusGame.sol:1520 — boolean today
function hasAnyLazyPass(address player) external view returns (bool) {
    uint256 packed = mintPacked_[player];
    if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;       // deity = permanent
    uint24 frozenUntilLevel = uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
    return frozenUntilLevel > level;                                              // lazy/whale = covered-through
}
```

The `validThroughLevel` model needs the **level number** the pass covers through, not a yes/no — so AfKing can store it at subscribe and compare against it per-iteration without re-reading.

### 3.2 The settled view signature

A new per-pass-type **level-horizon** view lives **alongside `hasAnyLazyPass` at `DegenerusGame.sol:1520`**, exposed via the `IGame` interface AfKing reads:

- **deity pass → `type(uint24).max`** — the **permanent sentinel** (D-11). Because `level` is `uint24`, `currentLevel <= type(uint24).max` is always true → a deity sub **never crosses** (the cheapest case; never triggers the crossing re-read). (Assumption A4 in RESEARCH: `level` reaching `type(uint24).max` is ~16.7M levels, unreachable — the sentinel is safe.)
- **lazy / whale pass → the covered-through level** — i.e. the `frozenUntilLevel` read from `mintPacked_` (the same `FROZEN_UNTIL_LEVEL_SHIFT`/`MASK_24` slice `hasAnyLazyPass` reads at `DegenerusGame.sol:1524-1527`).
- **no pass → a horizon `< currentLevel`** (e.g. `0`, or the bare `frozenUntilLevel` which is `<= currentLevel` when expired) — so the subscribe-time gate evaluates to "not covered."

**Recommended name/signature (Claude's-Discretion-constrained, final name left to IMPL):**

```solidity
// new in DegenerusGame.sol alongside hasAnyLazyPass:1520; exposed via IGame
function lazyPassHorizon(address player) external view returns (uint24) {
    uint256 packed = mintPacked_[player];
    if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return type(uint24).max;   // deity sentinel
    return uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);  // lazy/whale horizon
}
```

**Settled:** the view's **return semantics** (deity = `type(uint24).max`, lazy/whale = covered-through level) and that it lives alongside `hasAnyLazyPass` at `DegenerusGame:1520`, exposed via `IGame`. The exact final name/width is IMPL's to finalize. SPEC confirms each pass type maps to a **determinable horizon** readable both at subscribe AND at the crossing re-check.

> **`hasAnyLazyPass` is NOT deleted** — it remains a boolean view used elsewhere; the level-horizon view is *added* alongside it. AfKing's two former `hasAnyLazyPass` reads (`:432`, `:631`) migrate to the horizon view; whether the now-unused-by-AfKing boolean has other callers is an IMPL grep concern, not an AFSUB deletion.

---

## 4. The refresh-or-evict crossing control flow (D-12)

### 4.1 At subscribe — encode the horizon (replaces the pass-OR-pay gate)

`AfKing.subscribe` (`AfKing.sol:374`) today, after setting the sub fields, runs the SUB-01 **pass-OR-pay** gate at `:432`: active pass → free extend (clear `windowPaid`); else all-or-nothing `burnForKeeper` (set `windowPaid`).

**Pass-gated target:** `subscribe` sets

```
sub.validThroughLevel = IGame(GAME).lazyPassHorizon(subscriber);
```

— a single external read at subscribe (the only-rarely-hit cold path). No BURNIE charge, no `paidThroughDay`/`WINDOW_DAYS` anchor math (D-09 removes the `:414-416` extend-from-endpoint anchoring + the `:424` `paidThroughDay = anchor + WINDOW_DAYS` write + the entire `:430-443` pass-OR-pay block). The SUB-02 self-consent check (`:385-391`) and the OPENE-04 gate (`:393-403`) are PRESERVED (§6).

### 4.2 Per-iteration (non-crossing) — the cheap stored-field compare (GASOPT-05 preserved)

The frozen `_autoBuy` per-iter validity check is `if (sub.paidThroughDay <= today)` (`AfKing.sol:630`). It becomes the **level-denominated** mirror:

```
if (currentLevel <= sub.validThroughLevel) { ... still covered: proceed with the buy ... }
```

- This is a **pure stored-field compare** — **NO per-iteration external pass read** on the non-crossing path. It mirrors the retired `paidThroughDay <= today` day-compare at the SAME cheap cost (one SLOAD already in the sub struct, one comparison).
- This preserves the **GASOPT-05 win** (no per-iter external pass read). **The "per-iteration external pass read" is the explicit Anti-Pattern this design forbids** (RESEARCH "Anti-Patterns to Avoid"; T-334-08 in the threat register).

### 4.3 At the crossing — re-read ONCE, refresh-or-evict (NOT an unconditional kick)

The crossing condition is `currentLevel > sub.validThroughLevel` (the level-denominated analog of the frozen day-31 branch at `AfKing.sol:630-631`, where `hasAnyLazyPass(player)` "fires only here" per the source comment at `:629`). At the crossing:

1. **Re-read the level horizon EXACTLY ONCE:** `uint24 h = IGame(GAME).lazyPassHorizon(player);`
2. **If still covered (`currentLevel <= h`) → REFRESH:** `sub.validThroughLevel = h;` and the sub **continues** (the daily buy proceeds). This is the level-denominated analog of the frozen FREE active-pass extend at `:633` (`sub.paidThroughDay = today + WINDOW_DAYS`). A player who **upgraded** their pass after subscribing (lazy → deity, or extended freeze) is re-read here and **refreshed, never wrongly evicted** — which is exactly why D-10 needs **no proactive `refreshPass()`** (§5.3).
3. **Else (`currentLevel > h`, no/expired pass) → EVICT** via the existing in-place tombstone + swap-pop reclaim (§6.2). This replaces the frozen PAID `burnForKeeper` branch at `:641` (D-09, §5).

**This is NOT an unconditional kick.** The crossing is the **ONLY external pass read on the hot path** — the per-iter non-crossing path never reads a pass (§4.2). The control flow is symmetrical with the retired day-window's "free-extend-or-charge" shape, swapping the BURNIE charge for an eviction.

---

## 5. `burnForKeeper` full removal from BOTH contracts (D-09)

`burnForKeeper` is removed **ENTIRELY from BOTH `AfKing.sol` AND `BurnieCoin.sol`** — so the **batched IMPL diff (335) touches `BurnieCoin.sol`** (folded into the one USER-approved diff). No dead code, no future-proofing (`feedback_frozen_contracts_no_future_proofing`).

### 5.1 AfKing.sol removals

| Surface | Anchor | Action |
|---------|--------|--------|
| `burnForKeeper` interface declaration | `IBurnie` iface `AfKing.sol:57` | DELETE (no remaining caller after the two call sites go) |
| subscribe-time PAID burn call | `AfKing.sol:437` (inside the `:430-443` pass-OR-pay block) | DELETE — replaced by §4.1 `validThroughLevel` set |
| day-31 PAID burn call | `AfKing.sol:641` (inside the `:638-...` PAID branch) | DELETE — replaced by §4.3 eviction |
| `paidThroughDay` window accounting | the field `AfKing.sol:89` (repurposed §2) + the anchor math `:414-416`/`:424` | REPURPOSE to `validThroughLevel` / DELETE the day math |
| `WINDOW_DAYS` constant | `AfKing.sol:220` (`= 30`) | DELETE (the level horizon has no fixed window length) |
| `FLAG_WINDOW_PAID` semantics | flags bit 0 (`:81` doc; set/cleared `:433/:442/:634/:650`) | DELETE — the windowPaid concept retires; bit freed |
| `BurnieAutoExtracted` / the `SubscriptionExtendedFree`-PAID day-31 branch | the `:637-...` PAID branch + its events | DELETE — the crossing is now refresh-or-evict, no charge/extract |

### 5.2 BurnieCoin.sol removals (the now-dead implementation)

AfKing is `burnForKeeper`'s **only** caller, and `onlyAfKing` gates **only** `burnForKeeper`:

| Surface | Anchor | Action |
|---------|--------|--------|
| `burnForKeeper` implementation | `BurnieCoin.sol:472` (`external onlyAfKing returns (uint256 burned)` at `:475`) | DELETE |
| `KeeperBurn` event | `BurnieCoin.sol:85` | DELETE (only emitted by `burnForKeeper`) |
| `onlyAfKing` modifier | `BurnieCoin.sol:549` | DELETE — **confirmed `burnForKeeper` is its ONLY user** (grep 2026-05-27: `onlyAfKing` appears at `:462` doc, `:475` the gate on `burnForKeeper`, `:529` doc, `:549` def — the only *modifier application* is `:475`) |

> **D-09 confirmation (grep-attested 2026-05-27):** `grep -rn burnForKeeper contracts/` returns only `AfKing.sol` (iface `:57` + doc lines + call sites `:437`, `:641`) and `BurnieCoin.sol:472`. No third contract references it. Removing it orphans `onlyAfKing` with no other user (Assumption A3 confirmed). **The IMPL diff therefore touches `BurnieCoin.sol`.**

### 5.3 D-10 — lazy-only refresh; NO `refreshPass()` entrypoint

**No proactive `refreshPass()` entrypoint is authored** (smallest surface). The crossing re-check (§4.3) already catches a post-subscribe pass upgrade: an upgrader is **re-read and refreshed AT the crossing** and is never wrongly evicted. A convenience `refreshPass()` would have **no functional necessity** — skip it (D-10). The only external pass reads in the whole pass-gated model are: (1) once at `subscribe` (§4.1), and (2) once per crossing (§4.3). That is the entire pass-read surface.

---

## 6. Preservation Criteria (the acceptance bar for AFSUB-04 / AFSUB-05 at IMPL 335)

> These are the structural-preservation invariants the pass-gated model is **built to satisfy** (not bolted on). They are the IMPL-335 acceptance criteria for AFSUB-04/05, and are **empirically re-attested** by **TST-02 at Phase 336** and the **SWEEP-01 OPEN-E re-attest at Phase 338** (D-12; REQUIREMENTS AFSUB-04/05).

### 6.1 OPEN-E preservation — `fundingSource` STAYS; pass-gating does NOT moot OPEN-E (D-12, AFSUB-04)

Third-party box funding (the OPEN-E shared `fundingSource` in `Sub` `AfKing.sol:86-93`, offset 11) **STAYS**. Pass-gating gates **whose pass extends the autoBuy window** (the subscriber's), which is **independent of whose wallet funds the boxes** (`fundingSource`) — so **pass-gating does NOT moot OPEN-E**. Third-party box funding remains a live, valuable surface and is NOT collapsed by AFSUB.

The **4 OPEN-E structural protections** re-attest to hold under the pass-gated model (`open-e-operator-approval-trust-boundary`):

1. **Consent-gate-at-subscribe** — the OPENE-04 gate `AfKing.sol:393-403`: a non-zero, non-self `fundingSource` must have `isOperatorApproved(fundingSource, subscriber)` on the game (`:396-402`). **Checked HERE only** (the source comment at `:394-395`: "the renewal and per-draw paths never re-check"). Pass-gating does not change this — the level-window front-end never reads `fundingSource` consent; the consent gate stays exactly where it is, at subscribe.
2. **Default-self byte-identical** — `address(0)` `fundingSource` (= self) short-circuits the consent read (`:397-398`); the self-funded path is byte-identical whether or not a `fundingSource` is set. Pass-gating leaves the `fundingSource == address(0)` default unchanged.
3. **No-escalation** — the consent grant is funding-only; it confers no ability to escalate beyond funding the subscriber's own boxes. Pass-gating adds no new authority to `fundingSource`.
4. **Trust-the-sub temporal bound** — the operator-approval IS the trust boundary; the grantee is the same person or a fixed contract. **Do NOT model a "tricked into approving" actor** (`open-e-operator-approval-trust-boundary`); BURNIE-funding overload is **accepted-by-design**. (Under pass-gating the BURNIE charge is removed entirely (D-09), so the BURNIE-funding-overload surface SHRINKS — the funding now only pays for the boxes themselves, not a keeper sub charge.)

### 6.2 SUB-07 cancel-tombstone + v49 swap-pop membership invariant preservation (D-12, AFSUB-05)

The eviction path (§4.3) **reuses the existing eviction mechanism — no new tombstone infra**:

- **SUB-07 in-place cancel-tombstone** — `setDailyQuantity(0)` (`AfKing.sol:458`) writes the `dailyQuantity = 0` "paused" sentinel and **leaves the entry in the iterable set** — it moves nothing (doc `:449-457`: "it moves nothing, so it can never relocate an unprocessed entry behind the chunked autoBuy cursor"). The delete-vs-preserve decision is applied by the **in-autoBuy reclaim** when the sweep reaches the tombstone — `_autoBuy:605` (`if (sub.dailyQuantity == 0) { ... _removeFromSet(player); ... continue; }` at `:605-617`), which swap-pops it out of the set and **continues WITHOUT advancing the cursor** (the swap-pop occupant — a mover from ahead, hence still pending — is processed at this slot this autoBuy; source comment `:598-604`).
- **v49 swap-pop membership invariant — `membership ⟺ packed != 0`** holds: the in-place tombstone keeps the record readable (membership unchanged until the reclaim swap-pops it), and the reclaim's swap-pop preserves the set's membership-⟺-packed identity (the v49 invariant). Pass-eviction at the crossing routes through **exactly this** reclaim path — the eviction is the existing tombstone + `_autoBuy:605` swap-pop, not a new direct-removal.

### 6.3 The H-CANCEL-SWAP-MISS regression the eviction must NOT reproduce

Pass-eviction at the crossing must **NOT** relocate a pending tail **behind** the mid-sweep cursor — the **H-CANCEL-SWAP-MISS missed-day / mint-streak-reset class** (`afking-cancel-tombstone-streak-finding`: `setDailyQuantity(0)` swap-pop relocating a pending tail behind the sweep cursor → missed day → per-consecutive-level mint-streak RESET, up to −50% activity score). The reuse in §6.2 is precisely what avoids this: the in-place tombstone **moves nothing** at cancel time, and the in-autoBuy reclaim **does not advance the cursor** after a swap-pop (so the relocated occupant is processed this sweep, not skipped). Any IMPL-335 eviction that performs a direct `_removeFromSet` mid-sweep WITHOUT the tombstone-then-reclaim-at-cursor shape would re-open H-CANCEL-SWAP-MISS — **that is the regression bar AFSUB-05 forbids.**

---

## 7. Settled-signature summary (the AFSUB hand-off to IMPL 335)

| Item | Settled signature / decision | Anchor(s) | Decision |
|------|------------------------------|-----------|----------|
| Pass-gating scope | autoBuy sub window ONLY; autoOpen unchanged | `_autoBuyCursor:214` | D-08 |
| `validThroughLevel` placement | repurpose `Sub.paidThroughDay` slot (offset 5) in-place; width `uint24`-or-`uint32` (IMPL picks) | `AfKing.sol:86-93` (field `:89`) | D-11/D-12/D-13 |
| Level-horizon view | `lazyPassHorizon(address) returns (uint24)`: deity = `type(uint24).max`, lazy/whale = covered-through; alongside `hasAnyLazyPass`, via `IGame` | `DegenerusGame.sol:1520` | D-11 |
| Subscribe | `validThroughLevel = lazyPassHorizon(subscriber)`; remove pass-OR-pay block | `AfKing.sol:374`, `:430-443` | D-09/D-12 |
| Per-iter check | `currentLevel <= sub.validThroughLevel` (NO external read off-crossing) | `AfKing.sol:630` | D-12 (GASOPT-05) |
| Crossing | `currentLevel > validThroughLevel` → re-read horizon ONCE → refresh-or-evict (not a kick); ONLY hot-path pass read | `AfKing.sol:630-631`, `:633` | D-12 |
| `burnForKeeper` removal | DELETE from AfKing (iface `:57`, calls `:437`/`:641`, window accounting, `WINDOW_DAYS`, `FLAG_WINDOW_PAID`) AND BurnieCoin (`:472` impl, `KeeperBurn:85`, `onlyAfKing:549`) | both contracts | D-09 |
| Refresh | lazy-only; NO `refreshPass()` entrypoint | — | D-10 |
| Migration | none — pre-launch redeploy-fresh; layout break fine | — | D-13 |
| OPEN-E preservation | `fundingSource` stays; 4 protections re-attest; not mooted | `AfKing.sol:393-403` | AFSUB-04 |
| SUB-07 / swap-pop preservation | reuse `setDailyQuantity(0)` tombstone + `_autoBuy:605` reclaim; membership ⟺ packed != 0; no H-CANCEL-SWAP-MISS | `AfKing.sol:458`, `:605` | AFSUB-05 |

**Empirical re-attestation downstream:** TST-02 (Phase 336) proves the pass-gated sweep + eviction; SWEEP-01 (Phase 338) re-attests the OPEN-E 4-protection under the pass-gated model.
