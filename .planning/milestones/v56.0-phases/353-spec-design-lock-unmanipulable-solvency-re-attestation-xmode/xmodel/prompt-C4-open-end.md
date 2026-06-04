# XMODEL Design Review — Concern C4: Open-End Unmanipulability (post-refactor)

You are an adversarial smart-contract RNG/EV auditor reviewing a **design** (pre-launch, frozen contracts). Your single job: after the v56 refactor moves affiliate/quest to a **deferred settle**, confirm the afking **box-open path is still unmanipulable** — no double-open, no EV double-draw, no level/seed timing edge — OR find a vector.

## The mechanism (the open path — already lean, a re-verification target)

The afking box-open path (`_openAfkingBox` `GameAfkingModule.sol:888-910` → `resolveAfkingBox` `DegenerusGameLootboxModule.sol:877-...`, driven by `mintBurnie` `:985` / `_autoOpen` `:938-966` / `OPEN_BATCH` `:191`) already shares `_resolveLootboxCommon` with the human `openLootBox` path. v56 does NOT touch the open's freeze/parity guarantees — the per-buy accrue and the settle are the only things that change. The accumulator fields (`affiliateBase`/`lastSettledDay`/`questProgress`) co-reside in the SAME warm `Sub` slot as the open's markers (`lastOpenedDay`/`lastAutoBoughtDay`), but on DISJOINT fields written by DIFFERENT paths.

## The asserted invariants (try to break each)

1. **Live-level parity:** `resolveAfkingBox` rolls `currentLevel = level + 1` LIVE (`DegenerusGameLootboxModule.sol:894`), exactly like the human `resolveLootboxDirect` — parity with the human box.
2. **Frozen stamp-day seed + word:** the box word is the caller-passed `rngWordByDay[lastAutoBoughtDay]` (the FROZEN stamp-day word, `:905`) and the seed `day` is the FROZEN stamp day (`:904`/`:889`), NOT the live day — the freeze prevents seed-grinding by open-timing.
3. **No double-open:** `lastOpenedDay` advances BEFORE the resolve (`_openAfkingBox:892`, effects-first); `_afkingBoxReady` gates on `lastOpenedDay < lastAutoBoughtDay` (`:918-922`); `lastOpenedDay` is monotone → a re-walked open is a no-op.
4. **EV-cap exactly-once:** the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, ...)` RMW (`:902`), keyed `lootboxEvBenefitUsedByLevel[player][currentLevel]` (`currentLevel = level + 1`) on the SAME map the human path uses; the afking buy-time EV write is bypassed → the open is the single draw, no double-draw.
5. **No shared-state hazard:** the in-slot accumulator fields are **disjoint** from the open's markers within the shared `Sub` slot (different fields, different write paths) → no collision. The human + afking routes share only the intended per-`(player,level)` EV-cap budget.

## Your task

After the v56 accrual/settle refactor, find any way to manipulate the afking open. Consider in particular whether the refactor's NEW writes (the in-slot accumulator on the buy/settle path) could perturb the open's invariants:
- Could a settle (which writes `affiliateBase`/`lastSettledDay`/`questProgress` in the same `Sub` slot) corrupt or race the open's `lastOpenedDay`/`lastAutoBoughtDay` markers? (Same slot, different fields — is a read-modify-write of the packed slot on one path able to clobber the other path's fields?)
- Can a player **double-open** one stamped box (re-walk the open, or interleave buy/settle/open to get `lastOpenedDay` to advance twice for one stamp)?
- Can a player grind the box SEED or LEVEL by timing the open relative to the settle, given the seed is frozen at the stamp day but the level resolves live?
- Can a human open and an afking open at the same level **double-draw** the shared per-`(player,level)` EV-cap, now that the buy-time EV write is bypassed in favor of the at-open RMW?
- Does deferring quest/affiliate to the settle change WHEN the box is openable (the `_afkingBoxReady` gate), opening a timing edge?

## Required structured answer

End your response with EXACTLY this block:

```
VERDICT: [EXPLOITABLE | NOT-EXPLOITABLE | NEEDS-DESIGN-CHANGE]
RATIONALE: <one paragraph>
OPEN-VECTOR: <the concrete double-open / EV double-draw / seed-or-level timing edge / slot-clobber, OR "none — the open's frozen-seed + live-level + monotone-marker + exactly-once-EV-cap invariants survive the refactor; the accumulator fields are disjoint from the open markers">
```
