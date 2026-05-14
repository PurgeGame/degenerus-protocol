---
phase: 277
slug: event-surface-unification-sentinel-retirement-evt-uni
status: secured
threats_open: 0
threats_closed: 8
asvs_level: 1
created: 2026-05-14
---

# Phase 277 — Security Audit: Event Surface Unification + Sentinel Retirement

**Audited:** 2026-05-14
**ASVS Level:** L1
**block_on:** high
**Threats:** 8/8 CLOSED (5 contract wave + 3 test wave)
**Result:** SECURED
**Code state audited:** post gap-closure commit `f7a6fccd` (working tree HEAD `0a484177`)

---

## Audit Note — T-277-05 verified against CURRENT code, not the stale PLAN text

The 277-01-PLAN.md mitigation text for T-277-05 was demonstrably FALSE: it claimed
`emitLootboxEvent` was `true` for exactly the two manual callers, but `openBurnieLootBox`
(a manual caller) passes `emitLootboxEvent = false` because it emits its own
`BurnieLootOpen` event. The threat MATERIALIZED — code review BLOCKER CR-01 caught that
`openBurnieLootBox`'s ticket-path cold-bust silently stopped paying
`LOOTBOX_WWXRP_CONSOLATION`. This was FIXED in user-approved gap-closure commit
`f7a6fccd`, which introduced a dedicated `bool payColdBustConsolation` param. T-277-05 is
verified below against that real mitigation, NOT the PLAN's stale claim.

---

## Threat Verification — Contract Wave (277-01-PLAN.md)

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-277-01 | Tampering | accept | CLOSED | Breaking topic-hash / ABI change is intentional and pre-launch. Current `LootBoxOpened` def `contracts/modules/DegenerusGameLootboxModule.sol:68-77` keeps `amount` and `burnie` as `uint256` wei (no narrowing — D-277-EVT-WIDE-01 honored); `bonusBurnie` was removed entirely in `f7a6fccd` (event has 8 fields, no `bonusBurnie`, no `preRollTickets`). No truncation introduced. Accepted-risk entry recorded in the log below. |
| T-277-02 | Information Disclosure | mitigate | CLOSED | `_jackpotTicketRoll` `roundedUp` capture at `DegenerusGameJackpotModule.sol:2241-2247`: `bool roundedUp = false;` then `roundedUp = true;` set purely inside the existing Bernoulli predicate `if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac))`. No new state read/written, no new entropy bits — `entropy >> 200` slice unchanged. Mirrors the audited Lootbox pattern at `DegenerusGameLootboxModule.sol:1047-1052`. |
| T-277-03 | Denial of Service | mitigate | CLOSED | `_queueTickets` at `DegenerusGameStorage.sol:562-568` early-returns on `quantity == 0` (`if (quantity == 0) return;`). The sentinel-retired call site `DegenerusGameLootboxModule.sol:1057` is an unconditional `_queueTickets(player, targetLevel, whole, false)` inside the `if (futureTickets != 0)` block — no new revert path, no unbounded loop. Auto-resolve callers now pass `emitLootboxEvent = false` (`:692`, `:729`), REMOVING a `LootBoxOpened` LOG3 from the advanceGame chain — net gas reduction. |
| T-277-04 | Elevation of Privilege | accept | CLOSED | No new entry points: `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox` / `openLootBox` signatures unchanged; the two extracted helpers (`_lootboxBoonBudget`, `_accumulateLootboxRolls`) are `private`. `_resolveLootboxCommon` is `private`. No new state vars, no new modifiers — storage layout byte-identical to v39 baseline `6a7455d1` (event signatures do not affect storage layout). Accepted-risk entry recorded in the log below. |
| T-277-05 | Repudiation | mitigate | CLOSED | **Real mitigation = commit `f7a6fccd`, NOT the stale PLAN text.** `_resolveLootboxCommon` signature `DegenerusGameLootboxModule.sol:960-981` carries a dedicated `bool payColdBustConsolation` param (position 11). The cold-bust consolation gate at `:1058` is `if (payColdBustConsolation && whole == 0)` — decoupled from `emitLootboxEvent`. Manual callers pass `true`: `openLootBox` at `:595`, `openBurnieLootBox` at `:649`. Auto-resolve callers pass `false`: `resolveLootboxDirect` at `:693`, `resolveRedemptionLootbox` at `:729`. `openBurnieLootBox`'s cold-bust consolation is restored; auto-resolve stays silent (D-277-AR-SILENT-01). The asymmetry is now correct on the right axis. |

## Threat Verification — Test Wave (277-02-PLAN.md)

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-277T-01 | Tampering | mitigate | CLOSED | Five precedent test files retargeted off stale Wave-1 assertions (`test/edge/LootboxAutoResolveRegression.test.js`, `test/unit/LootboxWholeTicket.test.js`, `test/unit/JackpotTicketRollSilentColdBust.test.js`, plus user-approved fold-in of `test/unit/LootboxConsolation.test.js` and `test/unit/LootboxAutoResolveSilentColdBust.test.js`). 277-VERIFICATION.md confirms 112/112 affected tests pass post gap-closure. `LootboxConsolation.test.js` header now correctly distinguishes `openBurnieLootBox` (pays consolation) from auto-resolve (silent); `TST-WX-04` `LootboxBernoulliTester.coldBustConsolationFires` behaviorally pins all four callers' cold-bust outcomes — this is the test that would now catch a CR-01-class regression. |
| T-277T-02 | Repudiation | mitigate | CLOSED | `test/unit/EventSurfaceUnification.test.js` TST-EVT-UNI-01 computes topic hashes from the freshly compiled post-Wave-1 ABI via `hre.artifacts.readArtifact` + `ethers.Interface` and asserts the new `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` signatures; TST-EVT-UNI-02 asserts zero `emit LootboxTicketRoll` sites across `contracts/`. Verified independently: `grep -rn "LootboxTicketRoll" contracts/` returns empty; `grep -c "type(uint48).max"` on the Lootbox module returns 0. |
| T-277T-03 | Elevation of Privilege | accept | CLOSED | Test wave commit `6fbee850` staged exactly 7 paths — `test/unit/EventSurfaceUnification.test.js` (new) + 5 modified test files + `package.json`. No `contracts/` files staged in the test wave (the contract changes are isolated in `02fb7085` / `f7a6fccd`). Accepted-risk entry recorded in the log below. |

---

## Independent Verification Commands Run

```
grep -rn "LootboxTicketRoll" contracts/                                    -> empty (CLOSED: T-277T-02)
grep -c "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol -> 0
grep -c "index != type(uint48).max" .../DegenerusGameLootboxModule.sol      -> 0
grep -c "emit JackpotTicketWin" .../DegenerusGameJackpotModule.sol          -> 3
grep -rn "preRollTickets" contracts/                                       -> empty
grep -rn "LootBoxWwxrpReward" contracts/                                   -> empty (event deleted in f7a6fccd)
```

All 3 `emit JackpotTicketWin` sites supply the 7th `roundedUp` arg:
`DegenerusGameJackpotModule.sol:709-717` (literal `false`, trait-matched),
`:1013-1020` (literal `false`, near/far-future coin), `:2254-2262` (captured `roundedUp` local from `_jackpotTicketRoll`).

---

## Accepted Risks Log

| Threat ID | Risk | Justification | Sign-off |
|-----------|------|---------------|----------|
| T-277-01 | `LootBoxOpened` topic-0 hash + ABI change breaks any existing indexer subscription | Pre-launch; no live indexer. Intentional per D-40N-EVT-BREAK-01 / EVT-UNI-08. Fields kept `uint256` wide specifically to avoid truncating `burnie` wei values. Indexer rebuild expected at launch. | Recorded in commit `02fb7085` body; D-40N-EVT-BREAK-01 |
| T-277-04 | No new privilege surface introduced | Verified: no new external/public functions, no new state, no new modifiers; two new functions are `private`. Storage layout byte-identical to v39 baseline `6a7455d1`. | 277-VERIFICATION.md truth #12 |
| T-277T-03 | Test wave does not modify `contracts/` | Verified: test-wave commit `6fbee850` stages only `test/` + `package.json`. | 277-02-SUMMARY.md |
| (related) | `JackpotTicketWin` and `BurnieLootOpen` topic-0 hashes also change | Same pre-launch ABI-break acceptance as T-277-01; covered by D-40N-EVT-BREAK-01. IN-02 in 277-REVIEW.md. | 277-REVIEW.md IN-02 |

## Deferred Items (from 277-REVIEW.md — informational, do not block this phase)

| ID | Description | Disposition |
|----|-------------|-------------|
| WR-03 | `_lootboxBoonBudget(amount)` recomputed twice in `_resolveLootboxCommon` (`:992`, `:1020`) instead of cached — `private pure`, deterministic; extra multiplication only | DEFERRED by user decision; not a security threat |
| WR-04 | `BurnieLootOpen.index` is `uint32 indexed`; `openBurnieLootBox` emits `uint32(index)` truncating a `uint48` (`:657`) — pre-existing; aliasing only possible if lootbox indices exceed `type(uint32).max` | DEFERRED by user decision; not in the Phase 277 threat register |

---

## Unregistered Flags

None. Both 277-01-SUMMARY.md and 277-02-SUMMARY.md `## Threat Flags` sections report
"None." The gap-closure (`f7a6fccd`) event-surface trims (`bonusBurnie` removal,
`LootBoxWwxrpReward` deletion, `allowPasses` consolidation) are user-approved scope
additions documented in 277-REVIEW.md; they introduce no new attack surface — they
shrink the event surface and consolidate already-equal params. WWXRP payouts remain
observable via the ERC-20 `Transfer` event after `LootBoxWwxrpReward` deletion.

---

## Conclusion

All 8 declared threats are CLOSED against the current post-`f7a6fccd` code. The one
threat that materialized (T-277-05, BLOCKER CR-01) was caught by code review and fixed
with a real, verified mitigation — the dedicated `payColdBustConsolation` gate — not
the PLAN's false original claim. No mitigation was accepted on documentation or intent
alone; every `mitigate` threat resolves to a grep-confirmed code location, and every
`accept` threat has an entry in the accepted risks log above.

**Phase 277 is SECURED.**
