# Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 277-Event Surface Unification + Sentinel Retirement (EVT-UNI)
**Areas discussed:** Consolation gate after sentinel retirement, LootBoxOpened field types, bonus field width, Auto-resolve LootBoxOpened emission, Auto-resolve lootboxIndex value

---

## Consolation Gate After Sentinel Retirement

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse emitLootboxEvent flag | _resolveLootboxCommon already takes bool emitLootboxEvent — true for manual, false for auto-resolve, 1:1 with the consolation asymmetry. Gate consolation on that flag; no new param. | ✓ |
| Add dedicated bool param | Add explicit bool allowConsolation/manualPath. Self-documenting, decoupled, but adds a param to an already-14-arg signature. | |
| Keep a narrow index check | Drop the sentinel's behavior-split for queuing but keep index != max only for the consolation branch. Contradicts EVT-UNI-05's "sentinel retired" language. | |

**User's choice:** Reuse emitLootboxEvent flag
**Notes:** Accepted that `emitLootboxEvent` now does double duty (gate `LootBoxOpened` emit + gate cold-bust consolation). Critical downstream constraint recorded in D-277-CONSOLATION-GATE-01 / D-277-AR-EMIT-01: auto-resolve `LootBoxOpened` emission (option a) must NOT be wired by flipping `emitLootboxEvent` to true, or it would also enable auto-resolve consolation and violate D-40N-SILENT-01.

---

## LootBoxOpened Field Types (burnie/bonus wei-truncation)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep burnie/bonus as uint256 | Adopt narrow types where safe, keep burnie + bonus as uint256 wei. No truncation, no semantic change, larger payload. | |
| Emit whole-token counts | Keep uint32 burnie / uint16 bonus but emit burnieAmount / 1 ether. Fits narrow types, aligns with Phase 279 whole-BURNIE floor; semantic change to the event. | ✓ |
| uint128 burnie / uint96 bonus | Narrow-but-wei-safe types. Keeps wei semantics, tighter than uint256, no truncation. | |

**User's choice:** Emit whole-token counts
**Notes:** Surfaced after tracing actual value scale — `burnieAmount` lands on 1e18+ wei (`burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice`, `PRICE_COIN_UNIT = 1000 ether`), so EVT-UNI-02's literal `uint32 burnie` would catastrophically truncate. Whole-token semantics resolve it and align with the Phase 279 whole-BURNIE floor. Applies to `LootBoxOpened` only; `BurnieLootOpen` stays wei per EVT-UNI-03 scope.

---

## bonus Field Width

| Option | Description | Selected |
|--------|-------------|----------|
| uint32 bonus (Recommended) | Widen bonus to uint32, matching the burnie field. Same magnitude class, no truncation. Overrides EVT-UNI-02's uint16. | ✓ |
| Keep uint16, planner verifies cap | Keep uint16; planner must prove bonus never exceeds 65,535 whole BURNIE. Likely fails the proof. | |
| uint64 bonus | Maximum headroom but inconsistent with burnie's uint32. | |

**User's choice:** uint32 bonus
**Notes:** Follow-up after the user asked "what is bonus and is uint16 enough?" — `bonus` is the `bonusBurnie` local (62% presale-multiplier bonus, a large fraction of `burnie`). Even as a whole-token count, uint16's 65,535 cap is far too small for whale lootboxes. uint32 matches the sibling `burnie` field's magnitude class. Planner still derives the theoretical worst-case bound to confirm uint32 headroom.

---

## Auto-Resolve LootBoxOpened Emission (EVT-UNI-06 / D-40N-AR-EMIT-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Lock option (a) now | Add LootBoxOpened emission to both resolveLootboxDirect + resolveRedemptionLootbox. Unified event model, field-consistent. Roadmap's default. Costs gas on the high-volume decimator-claim path. | ✓ |
| Lock option (b) now | Keep auto-resolve silent on LootBoxOpened; surface fields via a TicketsQueued extension. Cheaper on decimator-claim path, second event shape to maintain. | |
| Genuinely defer to plan-phase | Leave EVT-UNI-06 open; plan-phase picks after measuring gas delta. | |

**User's choice:** Lock option (a) now
**Notes:** Auto-resolve now emits `LootBoxOpened` field-consistent with manual paths. Gas cost on the decimator-claim path acknowledged and to be reported in the contract commit message. Wiring constraint: must be decoupled from the `emitLootboxEvent` consolation gate (see Consolation Gate area).

---

## Auto-Resolve lootboxIndex Value

| Option | Description | Selected |
|--------|-------------|----------|
| Pass 0 as a sentinel-free default | Auto-resolve passes lootboxIndex = 0. Distinguishable in practice; no behavior gating attached so collision is cosmetic. | ✓ |
| Derive a meaningful identifier | Pass something traceable (day, keccak-derived resolution id) for indexer correlation. More useful off-chain, needs planner to pick the derivation. | |
| Tie to EVT-UNI-06 outcome | Resolve jointly with the auto-resolve emit decision. | |

**User's choice:** Pass 0 as a sentinel-free default
**Notes:** `resolveLootboxDirect` / `resolveRedemptionLootbox` resolve ETH directly and have no per-player queued lootbox storage index. With the sentinel retired, `lootboxIndex` carries no behavior — `0` is a clean "no index" value; any collision with a manual `index == 0` is cosmetic.

---

## Claude's Discretion

- Final `LootBoxOpened` field order (EVT-UNI-02 "TBD by plan-phase").
- `BurnieLootOpen` field handling — EVT-UNI-03 adds only the 2 new fields; existing fields stay wei `uint256`. Resulting asymmetry vs. `LootBoxOpened` whole-token semantics is scoped by the requirements; planner flags to user if it believes the asymmetry is wrong.
- `JackpotTicketWin.roundedUp` capture — `_jackpotTicketRoll` currently has no `roundedUp` bool; planner introduces the capture and threads it; trait-matched emit sites pass `false`.
- NatSpec / inline comment updates per `feedback_no_history_in_comments.md`.
- Test filenames + placement per Phase 275/276 precedent.
- Gas-delta worst-case derivation per `feedback_gas_worst_case.md` — derive first, then benchmark; report bytecode + gas delta in the contract commit message.

## Deferred Ideas

- `_queueLootboxTickets` wrapper retirement + `xTICKET_SCALE` cleanup + ENT-05 BAF xorshift refactor + TST-CROSS-01 — Phase 278 JPT-CLEAN.
- Whole-BURNIE floor at lootbox spin + near/far-future coin jackpot — Phase 279 BUR.
- `BurnieLootOpen` whole-token semantics — considered, left wei this phase per EVT-UNI-03 scope.
- ROADMAP.md / REQUIREMENTS.md text correction for EVT-UNI-02 (`uint32 burnie` / `uint16 bonus`) + EVT-UNI-06 (lock to option a) — docs-only follow-up, flagged to user at context-close.
