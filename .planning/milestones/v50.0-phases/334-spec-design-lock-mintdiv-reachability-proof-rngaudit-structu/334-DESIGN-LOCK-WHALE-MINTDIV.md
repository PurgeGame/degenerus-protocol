# Phase 334 — Design-Lock: Whale-Pass O(1) Claim + MintModule Index Alignment (SC1, whale/MintDiv slice)

**Authored:** 2026-05-27
**Requirements:** BATCH-01 (settle shared signatures), WHALE-01/02 (governed at IMPL 335), MINTDIV-02 (the `:716`→`:502` one-liner ships at IMPL 335).
**Status:** SETTLED. These are the final shared signatures the IMPL phase (335) re-authors against, with zero "by construction" assumptions. Every `file:line` is grep-attested in `334-GREP-ATTESTATION.md` vs the frozen baseline `b0511ca2`.

> This is the SC1 whale/MintModule slice. The AfKing `validThroughLevel` + refresh-or-evict slice (AFSUB) and the WHALE-04 freeze proof live in their own SPEC artifacts. The IMPL-335 producer-before-consumer edit-order map is recorded in 334-RESEARCH.md ("IMPL-335 Edit-Order Map", D-18).

---

## 1. The headline: WHALE is a CONVERGENCE refactor onto EXISTING deployed machinery (D-20)

The whale-pass O(1) claim machinery CONTEXT.md framed as new **already exists and is deployed** at `b0511ca2`. WHALE-01's entire job is to **route the box-open whale-pass boon onto the SAME existing machinery** — not to build a parallel system.

Existing, present-at-baseline:

- **`claimWhalePass(address player) external`** — `DegenerusGameWhaleModule.sol:1018`. Already permissionless-with-beneficiary-arg (D-01); liveness-gated (`:1019` `if (_livenessTriggered()) revert E();`); reads the count (`:1020` `uint256 halfPasses = whalePassClaims[player]`); zeroes-before-award (`:1024`); claim-time anchored `uint24 startLevel = level + 1` (`:1030`, D-03); applies stats at claim `_applyWhalePassStats(player, startLevel)` (`:1032`, D-04); queues `_queueTicketRange(player, startLevel, 100, uint32(halfPasses), false)` (`:1034`).
- **`whalePassClaims[beneficiary]`** — the existing uint COUNT (D-02 storage). Written today by the jackpot/payout path: `DegenerusGamePayoutUtils.sol:52` (`whalePassClaims[winner] += fullHalfPasses`, inside `_queueWhalePassClaimCore:45`) and `DegenerusGameJackpotModule.sol:1410` (`whalePassClaims[winner] += whalePassCount`).
- **`_queueTicketRange`** — `DegenerusGameStorage.sol:647` (the contiguous far-future queue "optimized for whale-pass claims"), gates at `:655` (liveness) and `:661` (far-future + `rngLock`).
- **`_applyWhalePassStats`** — `DegenerusGameStorage.sol:1111` (def), delta-based / no double-dip.

**Pending-claim storage = the EXISTING `whalePassClaims[beneficiary]` counter.** D-02's `pendingWhalePasses` name is a **RELABEL of this existing map**, NOT a new structure. The box-open record MUST mirror the existing `+=` writer (`PayoutUtils:52`), not author a parallel counter (the "Pitfall 1" anti-pattern). A second counter is explicitly rejected.

---

## 2. The box-open change — replace the inline 100-loop with a single O(1) record

**Today (the WHALE-01 target):** the box-open boon dispatch (`DegenerusGameLootboxModule.sol:1635`) calls `_activateWhalePass(player)` (`:1240`), which runs:

- `_applyWhalePassStats(player, ticketStartLevel)` at `:1247` (immediate stats at open), then
- a 100-iteration `for (uint24 i = 0; i < 100; )` loop (`:1250-1260`) that `_queueTickets` 40/lvl for the ≤10 bonus band, 2/lvl otherwise — the ~5.4M-gas monster the whole refactor exists to kill.

**Settled box-open shape:** replace the entire `_activateWhalePass` loop **and** its `_applyWhalePassStats:1247` call with a single O(1) increment mirroring `PayoutUtils:52`:

```
whalePassClaims[beneficiary] += grant;   // O(1); the grant is half-pass units (see §3)
```

- **Box-open writes NO `mintPacked_`** — stats move entirely to claim-time (D-04). The box-open record is a pure O(1) counter increment; it touches no freeze/levelCount slot.
- Multi-roll (rolling `BOON_WHALE_PASS` again before claiming) is just another increment — the counter accumulates; the existing claim materializes the accumulated total.
- Claim-time anchoring (D-03) and stats-at-claim (D-04) are realized **entirely by the existing `claimWhalePass`** — `startLevel = level + 1` at claim, `_applyWhalePassStats` at `WhaleModule:1032`, `_queueTicketRange` over the claim-time 100-level window.

**`_applyWhalePassStats` call-site reconciliation (drift-corrected vs CONTEXT.md, see 334-GREP-ATTESTATION.md §2/§4):** the function has exactly THREE call sites repo-wide.

| Call site | Path | Disposition at IMPL 335 |
|-----------|------|--------------------------|
| `LootboxModule:1247` | box-open `_activateWhalePass` | **DELETED** — stats move to claim-time (D-04). |
| `WhaleModule:1032` | inside `claimWhalePass` (the claim itself) | **UNTOUCHED** — it IS the deferred-claim apply the box-open path now defers to. |
| `DecimatorModule:588` | Decimator win | **UNTOUCHED** — stays immediate-apply. |

(CONTEXT.md labelled `WhaleModule:1032` a "bundle purchase" immediate-apply caller; that is inaccurate — `:1032` is the claim caller, and the bundle path `_purchaseWhaleBundle:194` does not call `_applyWhalePassStats`. The substance of D-04 holds: only the LootboxModule box-open caller's stats application moves; Decimator stays immediate.)

---

## 3. Q1 — the grant-shape reconciliation: LOCKED to convergence (D-21)

**This is a SETTLED DECISION, not an open task.** Per D-21 (USER, 2026-05-27): routing the box-open whale pass onto the existing `claimWhalePass`/`whalePassClaims` machinery, the box-open whale pass **CONVERGES to the existing flat per-level grant shape**.

- The early-game **≤level-10 `WHALE_PASS_BONUS_TICKETS_PER_LEVEL = 40` bonus band is DROPPED** (`LootboxModule:207`/`:209`). The per-level rate aligns to the existing claim's flat `N tickets/level × 100`.
- **A single counter** — no grant-shape parameter, no second counter, no claim variant. The box-open increments `whalePassClaims` exactly as the jackpot path does; the existing `claimWhalePass` materializes it unchanged.
- This is a **deliberate economic REDUCTION** of the box-open whale-pass reward (the box-open pass previously carried the 40/lvl ≤10 early bonus band; converging to the flat shape removes it). Per D-06/D-21 the **value delta is routed to the Phase-338 SWEEP economic-analyst** to sign off — it is flagged, not silently absorbed. The economic-analyst charge: confirm the reward reduction is acceptable and that no chosen claim level becomes advantageous/abusable under the claim-timing degree of freedom (D-06).

This is the final settled grant shape. (The alternative — preserving the 2/lvl + 40/lvl≤10 shape via a shape param or a second counter — was considered and rejected as the larger, doubled surface.)

---

## 4. claimWhalePass signature + the HARD CONSTRAINT (D-01)

**The claim signature is the EXISTING deployed `claimWhalePass(address player) external`** at `WhaleModule:1018`. WHALE-01 does NOT introduce a new claim function — it reuses this one verbatim.

- **Access model (D-01):** permissionless with beneficiary arg; the caller pays gas. Self-claim is the norm; a third party MAY gift-claim; a future keeper could be wired to claim-for-bounty.
- **HARD CONSTRAINT (D-01):** the claim must **NEVER be auto-triggered by box-open or autoOpen.** Box-open only records the O(1) increment; nothing forces a claim. If the claim were auto-triggered, the keeper would again involuntarily eat the materialization gas — re-creating the exact misallocation this refactor exists to kill. The decoupling-from-open is what makes the permissionless model coherent and freeze-safe.

---

## 5. gameOver-forfeit rule (D-23)

Unclaimed `whalePassClaims` at `gameOver` are **FORFEIT** — there are no future levels to materialize, so the pending count cannot be redeemed. This is consistent with the existing claim machinery's `_livenessTriggered` revert at `claimWhalePass:1019` ("claim whenever is fine" — but not after the game ends). No auto-claim-at-gameOver path is added.

---

## 6. WHALE-03 — autoOpen carve-out retirement (D-07, follows from D-02/D-04)

Uniform O(1) box opens follow directly from D-02 (box-open is a counter increment) and D-04 (no per-open materialization). Therefore the 331 whale-pass-weighted `autoOpen` budget — `OPEN_NORMAL_GAS_UNIT = 90_000` (`DegenerusGame.sol:1561`), the `autoOpen` weighting (`:1687`), the `weighted += used / OPEN_NORMAL_GAS_UNIT` math (`:1728`) — is **retired**, and `OPEN_BATCH` returns to **flat per-box sizing** (re-confirmed under the worst-case uniform open). This is **IMPL-335 work**; SPEC only confirms it follows from D-02/D-04.

---

## 7. MintModule within-player index alignment (D-15, MINTDIV-02 ships at IMPL 335)

MINTDIV-01 is **PROVEN REACHABLE** (D-22; the full verdict + the −17/+1 arithmetic trace + the two live callers `AdvanceModule:561`/`:1496` + the concrete `owed > maxT` scenario live in 334-RESEARCH.md "MINTDIV-01 Reachability Verdict"). Therefore the D-15 fix ships.

**Settled alignment shape:** at `DegenerusGameMintModule.sol:716`, change

```
processed += writesUsed >> 1;     // SUSPECT — diverges from take whenever take < owed
```

to match the reference-correct contiguous advance at `processFutureTicketBatch:502`:

```
processed += take;                // CORRECT — advance by tickets emitted
```

- This makes `processTicketBatch` advance its within-player `startIndex` exactly like `processFutureTicketBatch`, so a player's owed tickets generate contiguous per-ticket LCG trait indices across a `WRITES_BUDGET_SAFE` (`:93`, `= 550`) budget-slice split — no gapped/overlapped traits.
- **The two near-duplicate loops STAY separate.** Full dedup is **explicitly rejected** (D-15): it is a larger blast radius on the trait-critical path with no gas win and a security-floor-gated change. The standing maintenance risk is unchanged. **No defensive change is made anywhere else** — the fix is exactly this one line.

---

## 8. Claude's-Discretion items left to IMPL 335

Per CONTEXT.md "Claude's Discretion", constrained by the decisions above:

1. **The exact home of the `claimWhalePass` entrypoint** — a `DegenerusGame` external fn delegating to `WhaleModule`, vs exposing the existing module-direct `WhaleModule:1018` fn. (The function already exists at `WhaleModule:1018`; the discretion is only the facade routing.)
2. **The precise pending-counter storage slot** — `whalePassClaims` already exists in inherited state; the box-open writer reuses it. The discretion is confirming the declaration location for the box-open writer (recorded in the IMPL-335 edit-order map as a producer-first step).

No new level-horizon view / `Sub` field is in this slice (that is the AFSUB slice).

---

## 9. Settled-signature summary (the IMPL-335 contract surface for this slice)

| Surface | Settled signature / shape | Anchor |
|---------|----------------------------|--------|
| Pending-claim storage | the EXISTING `whalePassClaims[beneficiary]` uint counter (relabel, no new map) | `WhaleModule:1020`; writers `PayoutUtils:52`, `JackpotModule:1410` |
| Box-open record | replace `_activateWhalePass:1240` loop + `_applyWhalePassStats:1247` with `whalePassClaims[beneficiary] += grant` (flat-shape, O(1), no `mintPacked_` write) | `LootboxModule:1240-1260`; mirror `PayoutUtils:52` |
| Grant shape (Q1, D-21) | flat per-level (converge to existing claim); ≤10 40/lvl bonus band DROPPED; single counter; value delta → 338 economic-analyst | constants `LootboxModule:207`/`:209` removed at IMPL |
| Claim signature | the EXISTING `claimWhalePass(address player) external` (permissionless, beneficiary arg); NEVER auto-triggered (D-01) | `WhaleModule:1018` |
| Claim-time semantics | `startLevel = level + 1`; `_applyWhalePassStats` at claim; `_queueTicketRange(...,100,...)` — all existing, unchanged | `WhaleModule:1030/1032/1034` |
| gameOver | unclaimed `whalePassClaims` FORFEIT (no auto-claim) | consistent with `claimWhalePass:1019` |
| WHALE-03 | retire autoOpen gas-weight → flat `OPEN_BATCH` (IMPL 335; follows from D-02/D-04) | `DegenerusGame:1561/1687/1728` |
| MintModule alignment | `:716` `processed += writesUsed >> 1` → `processed += take`; loops stay separate | `MintModule:716` → match `:502` |

*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu — Task 2 (SC1, whale/MintDiv slice).*
