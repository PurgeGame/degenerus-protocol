# XMODEL Design Review — Concern C5: Long-Run Gas Optimization

You are an expert EVM gas optimizer reviewing a **design** (pre-launch, frozen contracts). Your job: suggest gas optimizations for the three v56 hot paths below, **WITHOUT weakening any unmanipulability / solvency / RNG-freeze invariant**. Any suggestion that trades a security invariant for a gas win must be flagged as such and is OUT OF BOUNDS.

## The three hot paths

### 1. The per-buy accrue (the everyday-gas target)
Each afking daily buy currently runs a cross-contract storm (quest `handlePurchase` + affiliate `payAffiliate` ×2 + per-buy `creditFlip`). v56 collapses this to **ONE warm SSTORE** into the re-packed `Sub` slot (the slot is already warm after the stamp read). The accumulator lives IN the existing single `Sub` slot via a re-pack + denomination change — **NO new cold slot**:
- `affiliateBase`: uint32, **whole BURNIE** (not 1e18 base units), with a **saturating clamp at 100,000,000 whole BURNIE**.
- `amount`: re-denominated to **0.001-ETH / milli-ETH units** (uint96 → ~uint32).
- `validThroughLevel`: uint32 → uint24. `lastAutoBoughtDay` / `lastOpenedDay`: uint32 → uint24.
- New accumulator fields: `lastSettledDay` (uint24), `questProgress` (uint8).
- `windowStartDay` is DROPPED — the window boundary is derived from a global ~10-day epoch (`currentDay - lastSettledDay >= 10`).

The irreducible per-buy reads that MUST stay hot: `_subscribers[cursor]→player` (`:551`), `_subOf[player]` (one warm slot, `:552`), `_goRead(swept)` (`:461`), `afkingFunding[player]` (`:464`); the W1/W2 solvency debit `afkingFunding[src] -= ethValue` (`:709`) + `claimablePool -= uint128(ethValue)` (`:710`) [byte-unchanged, on the solvency path — DO NOT touch]; the stamp `scorePlus1`+`amount` (`:793-794`); + the ONE accrue SSTORE.

### 2. The ~10-day settle leg
A `mintBurnie`-driven settle fires when the global ~10-day epoch elapses. It runs the deferred affiliate distribution (the winner-takes-all roll seeded by the FIXED window-boundary day) + the deferred quest credit + ONE batched leaderboard write (`_updateTopAffiliate` is a read-once-compare: 1 SLOAD + a conditional SSTORE only when the new total beats the top), then advances `lastSettledDay`.

### 3. The `OPEN_BATCH` open walk
The afking box-open path walks subscribers and opens ready boxes (`_autoOpen` `:938-966`, `OPEN_BATCH` `:191`). Per the reads/writes inventory it is already lean (no cold ledger; one marker write + the EV-cap RMW that IS the box + one cursor write + one bounty) — it is a RE-VERIFICATION target, NOT an optimization target. Suggest only optimizations that keep the frozen-seed + live-level + monotone-marker + exactly-once-EV-cap invariants intact.

## The invariants you must NOT weaken (any suggestion violating these is OUT OF BOUNDS)

- The ETH/`claimablePool` solvency debit (`:709-710`) stays byte-unchanged (SOLVENCY-01).
- The open uses the FROZEN stamp-day seed + word and the LIVE level (RNG-freeze).
- The affiliate roll seeds on the FIXED window-boundary day, buyer-never-wins (`:579`), intra-upline-chain-only (no settle-timing edge).
- The per-buy taper is immutable + monotone-down + applied per-buy (no clustering dodge).
- `lastSettledDay` / `lastOpenedDay` / `lastAutoBoughtDay` stay monotone idempotency markers (no double-settle, no double-open).
- The accumulator must remain in ONE warm slot (no new cold slot).

## Your task

Suggest concrete, named gas optimizations for the per-buy accrue, the settle leg, and the OPEN_BATCH walk. For each suggestion state: (a) the optimization, (b) the approximate gas saved, (c) which invariant it touches and why it does NOT weaken it. If you find NO safe optimization beyond the locked design, say so explicitly. If a tempting optimization WOULD weaken an invariant, list it under "REJECTED (weakens invariant)".

## Required structured answer

End your response with EXACTLY this block:

```
VERDICT: [OPTIMIZATIONS-FOUND | NO-SAFE-OPTIMIZATION | NEEDS-DESIGN-CHANGE]
RATIONALE: <one paragraph>
GAS-SUGGESTIONS: <numbered list, each with the gas estimate + the invariant note, OR "none beyond the locked design">
REJECTED-AS-INVARIANT-WEAKENING: <any tempting optimization that trades a security invariant for gas, OR "none">
```
