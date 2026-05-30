# Phase 339 — claimBingo Tier-Precedence Acceptance Contract (SC3 / BATCH-01 / "Open before SPEC" item 7)

**Status:** LOCKED · **Gathered:** 2026-05-28 · **Audit subject HEAD:** `812abeee` (≡ current HEAD for `contracts/`)

This is the **binding IMPL acceptance contract** for the `claimBingo` three-tier reward selection (BINGO-03, Phase 340) — written so IMPL 340 implements the suppression + bit-marking exactly and avoids the **double-pay trap**. The economics are LOCKED (D-05); this document specifies only the **selection ordering, the bit-marking, the suppression, and the per-tier payout** as a directive acceptance table. It is the companion to `339-DESIGN-LOCK-BINGO.md` (signature / storage / constants). The suppression behavior codified here is exactly what **TST-02 (Phase 341)** will prove empirically.

Source: D-06 (the tier-precedence rule, LOCKED) + the "Validation sketch" tier-selection block at `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md:107-131` + the "Tier ordering matters" note (`:158`).

---

## 1. The masks (D-07)

For a claim of `symbol` (∈ [0,31]) on `level`:

```
quadrant = symbol >> 3                  // ∈ [0,3]
qMask    = 1 << quadrant                // 4-bit quadrant mask  (firstQuadrant[level], bingoClaimed[level][player])
sMask    = 1 << symbol                  // 32-bit symbol mask   (firstSymbol[level])
```

Storage keyed by `uint24` level (see `339-DESIGN-LOCK-BINGO.md` §2): `firstQuadrant` is a systemwide `uint8`, `firstSymbol` a systemwide `uint32`, `bingoClaimed` a per-player `uint8`.

---

## 2. The precedence rule (D-06) — ORDERED DECISION, LOCKED

After the per-player dedup check passes (the `(level, quadrant)` bit in `bingoClaimed[level][msg.sender]` is unset → set it; a set bit reverts), compute BOTH first-flags, then **check `isQuadrantFirst` BEFORE `isSymbolFirst`**:

```
isQuadrantFirst = (firstQuadrant[level] & qMask) == 0
isSymbolFirst   = (firstSymbol[level]   & sMask) == 0
```

**The ordering is mandatory.** `isQuadrantFirst` MUST be evaluated and branched on **before** any symbol-first logic. The decision is an `if (isQuadrantFirst) … else if (isSymbolFirst) … else …` cascade — quadrant-first dominates and consumes the symbol-first slot in the SAME claim.

---

## 3. Three-branch acceptance table (D-05 / D-06)

| # | Branch | Condition | Bits marked | sDGNRS (bps → %) | BURNIE | Event | Suppression |
|---|--------|-----------|-------------|------------------|--------|-------|-------------|
| 3 | **QUADRANT-FIRST** | `isQuadrantFirst` (true) | `firstQuadrant[level] \|= qMask` **AND** `firstSymbol[level] \|= sMask` (BOTH) | `FIRST_QUADRANT_DGNRS_BPS = 50` → **0.5%** (REPLACEMENT) | `FIRST_QUADRANT_BURNIE = 5_000e18` (REPLACEMENT) | `FirstQuadrantBingo(msg.sender, level, symbol)` | **SUPPRESSES** the symbol-first bonus (non-additive) — pays the quadrant replacement only, NOT regular + symbol + quadrant |
| 2 | **SYMBOL-FIRST** | `!isQuadrantFirst && isSymbolFirst` | `firstSymbol[level] \|= sMask` (symbol only) | `REGULAR_DGNRS_BPS + FIRST_SYMBOL_BONUS_DGNRS_BPS = 5 + 5 = 10` → **0.1%** (ADDITIVE) | `REGULAR_BURNIE + FIRST_SYMBOL_BONUS_BURNIE = 1_000 + 1_000 = 2_000e18` (ADDITIVE) | `FirstSymbolBingo(msg.sender, level, symbol)` | n/a (this IS the symbol-first bonus, added on regular) |
| 1 | **REGULAR** | `!isQuadrantFirst && !isSymbolFirst` (both already set) | none (no first-bit marking) | `REGULAR_DGNRS_BPS = 5` → **0.05%** (baseline) | `REGULAR_BURNIE = 1_000e18` (baseline) | (only the universal `BingoClaimed`) | n/a |

### Per-branch directive prose

- **Branch 3 — QUADRANT-FIRST (`isQuadrantFirst`):** mark **BOTH** `firstQuadrant[level] |= qMask` AND `firstSymbol[level] |= sMask`. Pay the **REPLACEMENT** reward: `dgnrsBps = FIRST_QUADRANT_DGNRS_BPS` (50 bps = 0.5% of `Pool.Reward`) and `burnieReward = FIRST_QUADRANT_BURNIE` (5 000e18). **SUPPRESS** the symbol-first bonus — the quadrant-first reward does NOT stack on the regular or symbol-first amounts; it replaces them. Emit `FirstQuadrantBingo`.
- **Branch 2 — SYMBOL-FIRST (`!isQuadrantFirst && isSymbolFirst`):** mark `firstSymbol[level] |= sMask` only. Pay the **ADDITIVE** reward: `dgnrsBps = REGULAR_DGNRS_BPS + FIRST_SYMBOL_BONUS_DGNRS_BPS` (5 + 5 = 10 bps = 0.1%) and `burnieReward = REGULAR_BURNIE + FIRST_SYMBOL_BONUS_BURNIE` (1 000 + 1 000 = 2 000e18). Emit `FirstSymbolBingo`.
- **Branch 1 — REGULAR (`!isQuadrantFirst && !isSymbolFirst`):** no first-bit marking. Pay the **baseline**: `dgnrsBps = REGULAR_DGNRS_BPS` (5 bps = 0.05%) and `burnieReward = REGULAR_BURNIE` (1 000e18). No tier event.

### Universal: every branch emits BingoClaimed

Regardless of tier, every successful claim then performs the sDGNRS draw (`transferFromPool(Pool.Reward, …)`, clamped-return as `dgnrsPaid`, graceful no-op if the pool is empty) + the BURNIE flip credit (`coinflip.creditFlip`) and finally emits:

```
BingoClaimed(msg.sender, level, symbol, burnieReward, dgnrsPaid)
```

This is the universal record carrying the actually-paid amounts for every claim. (Reward-path mechanics are detailed in `339-DESIGN-LOCK-BINGO.md` §6.)

---

## 4. The KEY INVARIANT (the reason the ordering matters) — LOCKED

> **A quadrant-first claim that marks the `firstSymbol[level]` bit GUARANTEES that no later claim of that same symbol can re-collect the symbol-first bonus.**

This is the **suppression-is-also-a-bit-set** rule. The double-pay trap it forecloses: if a quadrant-first claim suppressed the symbol-first bonus *without* also setting `firstSymbol[level] |= sMask`, the symbol-first slot would still read as "open," and a subsequent claimant of that symbol would collect the symbol-first bonus — paying out the symbol-first prize twice in economic effect (once folded into the quadrant-first replacement's chronology, once to the later claimant). Marking the symbol bit on the quadrant-first branch closes that window.

The ordering (`isQuadrantFirst` checked first, marking BOTH bits) is sound because a quadrant-first claim is **necessarily also the chronological first claim for its symbol**: the quadrant for `(level, quadrant)` had no prior claimant, so the specific `(level, symbol)` within it had no prior claimant either — the quadrant-first claimant legitimately *is* the symbol-first, and consuming the symbol slot (without paying the additive bonus separately) is correct, not a forfeiture of someone else's prize.

**This is precisely the behavior TST-02 (Phase 341) codifies:** a quadrant-first claim correctly (a) pays the replacement reward, (b) suppresses the symbol-first bonus for that claim, and (c) marks the symbol-first bit so that a later non-quadrant-first claim of the same symbol receives only the **regular** reward (Branch 1), not the symbol-first bonus.

---

## 5. Binding scope

- This document is the **binding IMPL acceptance contract for BINGO-03** at Phase 340. IMPL 340 MUST implement the cascade exactly: per-player dedup → compute both first-flags → `if (isQuadrantFirst)` (mark BOTH bits, replacement, suppress, `FirstQuadrantBingo`) `else if (isSymbolFirst)` (mark symbol bit, additive, `FirstSymbolBingo`) `else` (baseline) → universal sDGNRS draw + BURNIE credit + `BingoClaimed`.
- The suppression + both-bits-marking behavior is the surface **TST-02 (Phase 341)** proves empirically (per-tier × per-quadrant happy path + the tier-precedence suppression case).
- Any IMPL that pays the symbol-first bonus on a quadrant-first claim, or that fails to set `firstSymbol[level] |= sMask` on a quadrant-first claim, VIOLATES this acceptance contract (the double-pay trap).

---

*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc · Plan 02 · Task 2*
*Companion: 339-DESIGN-LOCK-BINGO.md (signature / storage / constants / reward paths)*
