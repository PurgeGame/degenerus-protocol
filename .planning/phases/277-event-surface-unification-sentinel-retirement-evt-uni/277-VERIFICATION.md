---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
verified: 2026-05-14T12:00:00Z
status: passed
score: 14/14 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 277: Event Surface Unification + Sentinel Retirement Verification Report

**Phase Goal:** Delete `LootboxTicketRoll` entirely; add `bool roundedUp` to `LootBoxOpened`, `BurnieLootOpen`, and `JackpotTicketWin`; fix the `LootBoxOpened` index/day mislabel; retire the `index != type(uint48).max` sentinel in `_resolveLootboxCommon`; auto-resolve callers stay silent. Context overrides: no `preRollTickets`, fields stay `uint256` wide, auto-resolve stays silent. Gap-closure commit `f7a6fccd` adds `payColdBustConsolation` param (CR-01 fix), removes `bonusBurnie` from event and returns, deletes `LootBoxWwxrpReward`, collapses `allowWhalePass`/`allowLazyPass` into `allowPasses`.

**Verified:** 2026-05-14
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Zero `LootboxTicketRoll` declarations and emit sites in `contracts/` | VERIFIED | `grep -rn "LootboxTicketRoll" contracts/` returns empty; confirmed in both `DegenerusGameLootboxModule.sol` and `IDegenerusGameModules.sol` |
| 2  | `LootBoxOpened` emits real `lootboxIndex` (uint48 indexed) distinct from `day` (uint32 non-indexed), plus `bool roundedUp`; `amount`/`burnie` fields stay `uint256` wide; no `preRollTickets`; no `bonusBurnie` | VERIFIED | Lines 68-77 of LootboxModule: `event LootBoxOpened(address indexed player, uint48 indexed lootboxIndex, uint32 day, uint256 amount, uint24 futureLevel, uint32 futureTickets, uint256 burnie, bool roundedUp)` — no `bonusBurnie`, no `preRollTickets`, no narrowing |
| 3  | `BurnieLootOpen` gains only `bool roundedUp`; `JackpotTicketWin` gains non-indexed `bool roundedUp`; no `preRollTickets` on any event | VERIFIED | Lines 88-96: `BurnieLootOpen` ends in `bool roundedUp`; lines 90-98: `JackpotTicketWin` ends in non-indexed `bool roundedUp`; grep confirms zero `preRollTickets` in contracts |
| 4  | `_resolveLootboxCommon` has no `index != type(uint48).max` branch; unified `_queueTickets` path | VERIFIED | `grep -c "index != type(uint48).max" ...LootboxModule.sol` = 0; `grep -c "type(uint48).max" ...LootboxModule.sol` = 0; line 1057: unconditional `_queueTickets(player, targetLevel, whole, false)` |
| 5  | Auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass `index=0` and `emitLootboxEvent=false` | VERIFIED | Lines 682-698: `resolveLootboxDirect` passes `0` (3rd arg), `false` (emitLootboxEvent, 10th), `false` (payColdBustConsolation, 11th). Lines 718-733: `resolveRedemptionLootbox` same pattern |
| 6  | CR-01 fixed: manual callers pay the cold-bust consolation; auto-resolve stays silent | VERIFIED | `_resolveLootboxCommon` signature (line 971) has `bool payColdBustConsolation`. `openLootBox` (line 594) passes `true`. `openBurnieLootBox` (line 649) passes `true`. Auto-resolve callers (lines 692, 729) pass `false`. Gate at line 1058: `if (payColdBustConsolation && whole == 0)` |
| 7  | `bonusBurnie` removed from `LootBoxOpened` event AND `_resolveLootboxCommon` return tuple (now 3 returns) | VERIFIED | Event def lines 68-77 has no `bonusBurnie` field. Return tuple (lines 977-981): `(uint32 futureTickets, uint256 burnieAmount, bool roundedUp)` — 3 elements. Local `bonusBurnie` computation at line 1070 retained; folded into `burnieAmount` before return |
| 8  | `LootBoxWwxrpReward` event deleted; `wwxrp.mintPrize` payout retained | VERIFIED | `grep -n "LootBoxWwxrpReward" contracts/` returns empty. `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` at line 1064 retained |
| 9  | `allowWhalePass`/`allowLazyPass` collapsed into single `allowPasses` param | VERIFIED | `_resolveLootboxCommon` signature (line 969): `bool allowPasses`. `_rollLootboxBoons` signature (line 1111): `bool allowPasses`. Zero occurrences of `allowWhalePass` or `allowLazyPass` in contracts |
| 10 | `JackpotTicketWin` has exactly 3 indexed params; `roundedUp` is non-indexed; all 3 emit sites supply the 7th arg | VERIFIED | Lines 91-97: `winner`, `ticketLevel`, `traitId` are indexed; `roundedUp` is not. `grep -c "emit JackpotTicketWin"` = 3; lines 709-717 (false), 1013-1021 (false), 2254-2261 (captured roundedUp local) |
| 11 | `_jackpotTicketRoll` Bernoulli predicate captures `roundedUp`; math unchanged | VERIFIED | Lines 2241-2246: `bool roundedUp = false;` before predicate; `roundedUp = true;` inside `if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac))` |
| 12 | Storage layout byte-identical; no new state, modifiers, or public entry points | VERIFIED | REVIEW.md confirms behavior-equivalent refactor; `_lootboxBoonBudget` and `_accumulateLootboxRolls` are `private` helpers; no new storage slots, no new public/external functions |
| 13 | Contract compiles clean | VERIFIED | Commit `f7a6fccd` commit message: "Compiles clean; 112/112 affected tests pass" |
| 14 | All test requirements (TST-EVT-UNI-01..06) covered and passing | VERIFIED | `npx hardhat test` on all 6 Phase 277 test files: **112 passing, 0 failing** |

**Score:** 14/14 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `contracts/modules/DegenerusGameLootboxModule.sol` | Restructured events, sentinel retired, auto-resolve silent, CR-01 fix | VERIFIED | `LootBoxOpened`/`BurnieLootOpen` restructured; `LootboxTicketRoll` deleted; sentinel gone; `payColdBustConsolation` param added; `bonusBurnie` removed from event; `LootBoxWwxrpReward` deleted; `allowPasses` replaces dual params |
| `contracts/modules/DegenerusGameJackpotModule.sol` | `JackpotTicketWin` gains non-indexed `roundedUp`; `_jackpotTicketRoll` captures it | VERIFIED | Lines 90-98: event def; lines 2241-2261: capture and threading; 3 emit sites all supply 7th arg |
| `contracts/interfaces/IDegenerusGameModules.sol` | `LootboxTicketRoll` deleted from `IDegenerusGameLootboxModule` interface block | VERIFIED | `grep -rn "LootboxTicketRoll" contracts/interfaces/` returns empty |
| `test/unit/EventSurfaceUnification.test.js` | All six TST-EVT-UNI describe blocks | VERIFIED | 570 lines; 6 describe blocks labeled TST-EVT-UNI-01..06; 26 passing |
| `test/edge/LootboxAutoResolveRegression.test.js` | TST-REG-03/04 retargeted off retired sentinel | VERIFIED | Asserts `emitLootboxEvent=false` + `index=0` pattern; no `type(uint48).max` assertions |
| `test/unit/LootboxWholeTicket.test.js` | Drift-grep updated for post-retirement source | VERIFIED | No `LootboxTicketRoll` or sentinel patterns; TST-WT-04..07 updated |
| `test/unit/JackpotTicketRollSilentColdBust.test.js` | `JackpotTicketWin.roundedUp` assertion | VERIFIED | [03a] updated; 7-arg emit threading asserted |
| `test/unit/LootboxConsolation.test.js` | `openBurnieLootBox` correctly pays consolation; TST-WX-04 behavioral gate | VERIFIED | Header correctly distinguishes `openBurnieLootBox` (pays consolation) from auto-resolve (silent); TST-WX-04 `LootboxBernoulliTester.coldBustConsolationFires` behavioral mirror |
| `test/unit/LootboxAutoResolveSilentColdBust.test.js` | Retargeted off retired sentinel; unified single `_queueTickets` callsite | VERIFIED | `type(uint48).max` and `LootboxTicketRoll` assertions removed; unified path asserted |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_resolveLootboxCommon` ticket-award path | `_queueTickets` | unconditional call at line 1057 | VERIFIED | `_queueTickets(player, targetLevel, whole, false)` appears exactly once, outside any conditional branch on `index` |
| `openBurnieLootBox` → `_resolveLootboxCommon` | `payColdBustConsolation=true` | 11th arg at line 649 | VERIFIED | Args count: presale=false, allowPasses=false, emitLootboxEvent=false, payColdBustConsolation=true |
| `resolveLootboxDirect` → `_resolveLootboxCommon` | `index=0`, `emitLootboxEvent=false`, `payColdBustConsolation=false` | lines 684-696 | VERIFIED | 3rd arg=0, 10th arg=false, 11th arg=false |
| `resolveRedemptionLootbox` → `_resolveLootboxCommon` | `index=0`, `emitLootboxEvent=false`, `payColdBustConsolation=false` | lines 720-732 | VERIFIED | Same pattern as `resolveLootboxDirect` |
| `_jackpotTicketRoll` `roundedUp` capture | `JackpotTicketWin` emit | captured at `whole += 1` site; threaded to line 2261 | VERIFIED | `roundedUp = true;` at line 2246; `emit JackpotTicketWin(..., roundedUp)` at line 2254-2261 |
| `LootboxBernoulliTester.coldBustConsolationFires` | production `payColdBustConsolation && whole == 0` gate | TST-WX-04 drift-detect assertion | VERIFIED | Test asserts mirror string matches production gate; behavioral gate exercises all 4 callers |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase modifies event surface and control flow, not data rendering components. No new components render dynamic data from a store or API. The event-data flows (roundedUp, lootboxIndex, payColdBustConsolation) are verified by the key-link checks above.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `LootboxTicketRoll` absent from all contracts | `grep -rn "LootboxTicketRoll" contracts/` | empty output | PASS |
| `type(uint48).max` absent from LootboxModule | `grep -c "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` | 0 | PASS |
| `JackpotTicketWin` has exactly 3 emit sites | `grep -c "emit JackpotTicketWin" contracts/modules/DegenerusGameJackpotModule.sol` | 3 | PASS |
| All 6 Phase 277 test files pass | `npx hardhat test` on all 6 files | 112 passing, 0 failing | PASS |
| `LootBoxWwxrpReward` deleted from contracts | `grep -rn "LootBoxWwxrpReward" contracts/` | empty output | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description (authoritative, as overridden by CONTEXT.md) | Status | Evidence |
|-------------|------------|-----------------------------------------------------------|--------|----------|
| EVT-UNI-01 | 277-01 | Delete `LootboxTicketRoll` from interface + contract; zero emit sites | SATISFIED | Confirmed via grep; both files clean |
| EVT-UNI-02 | 277-01 | `LootBoxOpened` mislabel fixed (real `lootboxIndex` + separate `day`); `roundedUp` added; fields stay `uint256` wide; no `preRollTickets` (D-277-EVT-WIDE-01 + D-277-NO-PREROLL-01 override the REQUIREMENTS.md literal text) | SATISFIED | Event def at lines 68-77 confirmed |
| EVT-UNI-03 | 277-01 | `BurnieLootOpen` gains only `bool roundedUp`; no `preRollTickets` (D-277-NO-PREROLL-01 override) | SATISFIED | Event def at lines 88-96 confirmed |
| EVT-UNI-04 | 277-01 | `JackpotTicketWin` gains non-indexed `bool roundedUp`; `_jackpotTicketRoll` captures it; all 3 emits supply it | SATISFIED | Lines 90-98, 2241-2261 confirmed |
| EVT-UNI-05 | 277-01 | `index != type(uint48).max` sentinel retired; unified `_queueTickets` flow | SATISFIED | Zero sentinel occurrences; unconditional `_queueTickets` at line 1057 |
| EVT-UNI-06 | 277-01 | Auto-resolve stays silent on `LootBoxOpened` (D-277-AR-SILENT-01 resolves as option b) | SATISFIED | Both auto-resolve callers pass `emitLootboxEvent=false` |
| EVT-UNI-07 | 277-01 | Gas worst-case derived first; bytecode delta recorded in commit message | SATISFIED | Commit `02fb7085` body: theoretical derivation + measured `-527B` (LootboxModule) / `+23B` (JackpotModule) |
| EVT-UNI-08 | 277-01 | Breaking topic-hashes accepted per D-40N-EVT-BREAK-01; noted in commit | SATISFIED | Commit `02fb7085` body: "Breaking ABI change accepted per D-40N-EVT-BREAK-01" |
| TST-EVT-UNI-01 | 277-02 | Topic-hash changes asserted via compiled ABI; old `LootboxTicketRoll` topic has zero emit sites | SATISFIED | `EventSurfaceUnification.test.js` TST-EVT-UNI-01 describe block; 26 passing |
| TST-EVT-UNI-02 | 277-02 | `LootboxTicketRoll` absent from `DegenerusGameLootboxModule.sol` AND `IDegenerusGameModules.sol` | SATISFIED | [02a] and [02b] source-grep assertions |
| TST-EVT-UNI-03 | 277-02 | No `index != type(uint48).max`; auto-resolve callers pass `0` + `emitLootboxEvent=false` | SATISFIED | [03a]-[03d] assertions; positional arg parsing confirmed |
| TST-EVT-UNI-04 | 277-02 | Manual-path field-consistency: `whole = (futureTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)`; `lootboxIndex`/`day` emit wiring asserted; no `preRollTickets` | SATISFIED | [04a]-[04f] assertions; D-277-NO-PREROLL-01 honored |
| TST-EVT-UNI-05 | 277-02 | Auto-resolve emits no `LootBoxOpened`; consolation is `payColdBustConsolation`-gated (post-CR-01 fix) | SATISFIED | [05a]-[05d]; correctly tests `payColdBustConsolation && whole == 0` gate, not `emitLootboxEvent` |
| TST-EVT-UNI-06 | 277-02 | `JackpotTicketWin.roundedUp` non-indexed; mirrors `_jackpotTicketRoll` Bernoulli outcome | SATISFIED | [06a]-[06e] assertions; trait-matched paths pass `false` |

**Coverage: 14/14 requirements satisfied.**

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `DegenerusGameLootboxModule.sol` | 992, 1020 | `_lootboxBoonBudget(amount)` called twice instead of cached | Info | WR-03 — deferred by user decision (277-REVIEW.md); `private pure` function, deterministic result, extra multiplication only. Per user decision: acceptable, no action required. |
| `DegenerusGameLootboxModule.sol` | 657 | `uint32(index)` truncation in `BurnieLootOpen` emit | Info | WR-04 — deferred by user decision (277-REVIEW.md); pre-existing, low-risk for current index ranges. No action required. |

No `TBD`, `FIXME`, or `XXX` markers found in the modified contract files.

---

### Gap-Closure Verification (CR-01 and Additional Trims)

The following changes from commit `f7a6fccd` were verified against the actual codebase, as instructed:

**CR-01 (RESOLVED):** `payColdBustConsolation` param added at position 11 of `_resolveLootboxCommon`. `openLootBox` passes `true` (line 594); `openBurnieLootBox` passes `true` (line 649); `resolveLootboxDirect` passes `false` (line 692); `resolveRedemptionLootbox` passes `false` (line 729). Gate in body at line 1058: `if (payColdBustConsolation && whole == 0)`. The BURNIE-lootbox cold-bust consolation is correctly restored.

**`bonusBurnie` removed from `LootBoxOpened`:** Event field is absent (lines 68-77). Local computation at line 1070 retained, folded into `burnieAmount`. Return tuple is 3 elements (lines 977-981).

**`LootBoxWwxrpReward` deleted:** Zero occurrences in `contracts/`. `wwxrp.mintPrize` call at line 1064 retained. ERC-20 `Transfer` event is the observable signal.

**`allowPasses` consolidation:** `_resolveLootboxCommon` signature at line 969: `bool allowPasses`. Zero occurrences of `allowWhalePass` or `allowLazyPass` in contracts. `_rollLootboxBoons` at line 1111 uses `bool allowPasses`. `_boonPoolStats` and `_boonFromRoll` likewise use single `allowPasses`.

**WR-01 (RESOLVED):** `LootboxConsolation.test.js` header explicitly documents `openBurnieLootBox` as a manual caller that pays consolation (distinct from auto-resolve). TST-WX-04 `LootboxBernoulliTester.coldBustConsolationFires` behavioral mirror tests all four callers.

**WR-02 (ADDRESSED):** `LootboxBernoulliTester.coldBustConsolationFires` mirror exercises the production gate with each caller's actual flag values, exercising the `openBurnieLootBox` cold-bust case CR-01 dropped. End-to-end VRF fixture remains RE-DEFERRED (LBX-02, D-40N-LBX02-OUT-01).

**WR-03 / WR-04 (DEFERRED):** Both remain in code per user decision. Documented in 277-REVIEW.md.

---

### Human Verification Required

None. All must-haves are verifiable via source inspection, grep, and the test suite. The phase produces no UI components, no real-time behavior, and no external service integrations.

---

### Deferred Items

None. All gaps identified in the code review (277-REVIEW.md) were either resolved (CR-01, WR-01, WR-02) or explicitly deferred by user decision (WR-03, WR-04). Deferred items are informational only and do not block this phase.

---

## Summary

Phase 277 fully achieves its goal. The event surface unification is complete:

- `LootboxTicketRoll` is gone from both the contract and the interface, with zero emission sites.
- `LootBoxOpened` has a correct `uint48 indexed lootboxIndex` field, a separate `uint32 day` field, and `bool roundedUp`; fields stay `uint256` wide; no `bonusBurnie` (gap-closure removed it); no `preRollTickets`.
- `BurnieLootOpen` and `JackpotTicketWin` each carry a non-indexed `bool roundedUp`.
- The `index != type(uint48).max` sentinel is gone; the ticket-award path is a single unconditional `_queueTickets` call.
- Auto-resolve callers pass `index=0` and `emitLootboxEvent=false` and stay silent.
- The CR-01 regression is correctly fixed: `openBurnieLootBox` pays the cold-bust WWXRP consolation via the dedicated `payColdBustConsolation=true` flag; auto-resolve passes `false`.
- `LootBoxWwxrpReward` is deleted; `allowWhalePass`/`allowLazyPass` collapsed to `allowPasses`.
- 112/112 tests pass across all six Phase 277 test files.
- All 14 requirements (EVT-UNI-01..08 + TST-EVT-UNI-01..06) are satisfied.

---

_Verified: 2026-05-14_
_Verifier: Claude (gsd-verifier)_
