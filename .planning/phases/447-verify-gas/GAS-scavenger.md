# GAS Scavenger Report — Phase 447 (v71 Foil Pack surface)

Surface: 18 files changed since v70 freeze `ffbd7796` (`git diff --stat ffbd7796 HEAD`).
Scope: **only CHANGED/NEW lines** in this diff. No v70-frozen code outside the diff is touched.
Method: READ-ONLY. These are RECOMMENDATIONS for the SKEPTIC pass — not edits.

Risk legend:
- **inert** = behavior-inert (no logic/rounding/RNG-byte/EV change), non-layout.
- **LAYOUT** = touches storage-slot order — HIGH-RISK, NOT recommended (state-corruption class).
- **RNG/EV** = touches RNG-byte-derivation or EV tables — HIGH-RISK, NOT recommended.

---

## TOP PICKS (high-saving, low-risk, behavior-inert) — apply these first

| # | file:line | candidate | est saving | conf | risk |
|---|---|---|---|---|---|
| 1 | FoilPackModule.sol:156-163,229 | Cache `level` once in `buyFoilPack` — read 3× (`_activeTicketLevel()` @156, `level+1` @163, `level+1` @229) | ~200 gas/foil-buy (2 warm SLOAD) | H | inert |
| 2 | FoilPackModule.sol:157,297 | Cache `rngLockedFlag` once — read @157 and @297 | ~100 gas/foil-buy | H | inert |
| 3 | FoilPackModule.sol:177,297 | Cache `dailyIdx` once — read @177 (`dailyIdx+1`) and @297 (`dailyIdx<day`) | ~100 gas/foil-buy | H | inert |
| 4 | MintModule.sol:654,712 | `queue.length != 0` re-reads length slot already in local `total` (set @635) — use `total != 0` | ~100 gas per finished-batch advance (HOT) | H | inert |
| 5 | DegenerusGame.sol:632 | `_purchaseWithFoil` reads `level` twice in `jackpotPhaseFlag ? level : level+1` — cache to local | ~100 gas/foil-buy | H | inert |

All five are warm-SLOAD eliminations on the foil buy / advance hot paths, fully behavior-inert, non-layout. Combined ~600 gas on the foil-buy path + ~100 gas on every finished-batch advance.

---

## contracts/modules/DegenerusGameFoilPackModule.sol (NEW ~811 lines)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| 156-163, 229 | **Redundant `level` SLOAD ×3.** `_activeTicketLevel()` @156 reads `level`; `lvl = level + 1` @163 (cold branch); `affLevel = level + 1` @229. Three reads of the same slot. | ~200 gas/buy | H | inert | Hoist `uint24 lvl_ = level;` near top. Use `lvl_` in the reroute (`level+1`→`lvl_+1` @163) and `affLevel = lvl_ + 1` @229. `_activeTicketLevel()` still does its own read (it also reads `jackpotPhaseFlag`); optionally inline it as `jackpotPhaseFlag ? lvl_ : lvl_+1` to drop that one too (see next row). |
| 156-157 | **Redundant `jackpotPhaseFlag` SLOAD ×2.** Read inside `_activeTicketLevel()` @156, then again @157 (`if (jackpotPhaseFlag && rngLockedFlag)`). | ~100 gas/buy | H | inert | Cache `bool jp = jackpotPhaseFlag;` once; inline `_activeTicketLevel()` as `jp ? lvl_ : lvl_+1` and reuse `jp` in the @157 guard. (Pairs with the `level` cache above; do them together.) |
| 157, 297 | **Redundant `rngLockedFlag` SLOAD ×2.** Read @157 (`jackpotPhaseFlag && rngLockedFlag`) and @297 (`!rngLockedFlag && dailyIdx < day`). | ~100 gas/buy | H | inert | `bool rngLocked = rngLockedFlag;` once; reuse at both sites. |
| 177, 297 | **Redundant `dailyIdx` SLOAD ×2.** Read @177 (`day > dailyIdx + 1`) and @297 (`dailyIdx < day`). | ~100 gas/buy | H | inert | `uint24 di = dailyIdx;` once after `day` is set; reuse at both sites. |
| 176 vs `_livenessTriggered`@146 | `_simulatedDayIndex()` (→ `GameTimeLib.currentDayIndex()`, pure timestamp math) is computed @176 AND again inside `_livenessTriggered()` @146. Cross-function; not a storage read but a duplicated keccak-free arithmetic call. | ~30-60 gas/buy | L | inert | Low value — would require threading `day` into a `_livenessTriggeredAt(day)` overload. Note only; the saving is small and the refactor widens surface. SKIP unless cheap. |
| 185 | `FOIL_PACK_TICKETS * priceWei` — `FOIL_PACK_TICKETS` is `constant` (10); compiler folds the constant operand. No runtime cost. | 0 | H | inert | none (already optimal). |
| 443-444 | `if (ticketIndex >= 4) return false; if (drawKind >= 2) return false;` — `ticketIndex` is `uint256` param but the four callers (claimFoilMatchMany) pass a `uint8`. Bound checks are cheap and load-bearing (alias guard). | 0 | — | inert | none — keep (correctness gate, not redundant). |
| 470-472, 491-500 | Claim score loop: `sel`, `winSet` cached to stack already; the 4-iter quadrant loop reads only stack/memory. No per-iter SLOAD. | 0 | H | inert | none — already tight. |
| 481 vs 590 | `rngWordByDay[resolveDay]` @481 (line derivation) vs `rngWordByDay[uint24(day)]` @590 (payout entropy). **Different keys** (`day >= resolveDay`, equal only when `day==resolveDay`). NOT redundant in general. | — | — | inert | none — do NOT merge; keys differ by design. |
| 526-555 | `_deriveFoilLines`: `foilCuts(multBps)` built **once** @540 then shared across the 4-line loop. Already hoisted correctly (matches the doc intent). | 0 | H | inert | none — already optimal. |
| 605-635 | `_payFoilTier` currency fork: each arm recomputes `faces * priceForLevel(L)` / `faces * FLIP_FACE_AMOUNT` only in its taken branch (no double-compute across branches). `priceForLevel(L)` @609 is a single call on the ETH arm. | 0 | M | inert | none. |
| 692-739 | `_processFoilDrain`: `foilDrainDay`, `foilLastResolveDay`, `foilCursor` each loaded once to locals (`dd`,`last`,`cursor`) @693-695 and written back once. `counts`/`touchedTraits` scratch shared across buyers (re-zeroed per buyer). Tight. | 0 | H | inert | none — already optimal loop structure. |
| 715, 722 | `(FOIL_PACK_ENTRIES * 2) + 3` written twice as the same expression (guard @715, charge @722). Both operands are `constant`, so it folds to `35` at compile — no runtime cost, but it's a duplicated magic expression. | 0 runtime | H | inert | OPTIONAL readability: a `uint32 private constant FOIL_DRAIN_UNIT_COST = (FOIL_PACK_ENTRIES * 2) + 3;` single source (must keep guard==charge — that equality is a documented brick-safety invariant). No gas delta. |
| 758 | `_resolveFoilBuyer` calls `_foilMultFor(buyer, lvl)` → fresh SLOAD of `foilRecord[lvl][buyer]`. This is the per-buyer drain inner loop. The full record was not read earlier in the drain, so this single SLOAD is necessary (reads whole slot, extracts multBps). | 0 | H | inert | none — one SLOAD, unavoidable; do not flag. |
| 777-805 | `_resolveFoilBuyer` batch-writer: `levelSlot` computed once, per-trait length SLOAD/SSTORE is the minimal pattern (mirrors the mint module batch writer). `counts[traitId]` re-zeroed inline. | 0 | H | inert | none — already optimal assembly. |

**Storage-layout note (NOT a recommendation):** the new foil append in `DegenerusGameStorage.sol` already packs `foilCursor (uint32) + foilDrainDay (uint24) + foilLastResolveDay (uint24)` = 80 bits into ONE slot (declared consecutively @2462-2464). No packing win remains, and reordering existing slots is HIGH-RISK / NOT recommended. The `foilRecord` value packs resolveDay/multBps/activityScore into one uint256 (good). `dailyFoilDraw` packs mainSet/bonusSet/level into one uint256 (good). No layout action.

---

## contracts/modules/DegenerusGameMintModule.sol (heavy refactor)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| 654, 712 | **`queue.length != 0` re-reads the array-length slot already cached in `total`** (`total = queue.length` @635). Queue is not pushed/popped between @635 and these checks. | ~100 gas per finished-level advance (HOT: processTicketBatch) | H | inert | Replace both `queue.length != 0` with `total != 0`. |
| 753 | `(FOIL_PACK_ENTRIES * 2) + 3` magic literal duplicates FoilPackModule:715/722. Constant-folds — no runtime cost. | 0 runtime | H | inert | OPTIONAL: share one `constant` (see foil-module row above). |
| (removal) | The ~220-line `_recordMintData` body removed from this module (relocated to MintStreakUtils) is a net bytecode/gas reduction already. | — | — | inert | none — already a win. |

No new redundant SLOADs, no dead params, no unreachable branches introduced by the refactor. New import `IDegenerusGameFoilPackModule` is used (@757) — not dead.

---

## contracts/DegenerusGame.sol (+141)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| 632 | `_purchaseWithFoil` reads `level` twice in `jackpotPhaseFlag ? level : level + 1`. | ~100 gas/foil-buy | H | inert | `uint24 lvl_ = level;` then `jackpotPhaseFlag ? lvl_ : lvl_ + 1`. |
| 666, 720-748, 444-447 | New delegatecall facades (`purchaseWith`, `claimFoilMatch`/`Many`, `floorAfkingStreakBase`) forward raw `msg.data` — cheapest form. | — | — | inert | none — already optimal. |

---

## contracts/modules/DegenerusGameMintStreakUtils.sol (NEW +218)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| 47-80 | `_bountyEligible`: `mintPacked_[who]` loaded **once** into `mintData` @51, all subfields (lastEthDay, deity, frozenUntilLevel) read from it. `level` read once @71 only on the pass-holder branch. `dailyIdx` read once @48. Tiered short-circuit (cheapest first). | 0 | H | inert | none — already optimal. |
| 282-372 | `_playerActivityScoreAt`: `mintPacked_[player]` loaded **once** into `packed` @290; deity/levelCount/streak/frozenUntil/bundleType/curse/affiliate-cache all unpacked from the single word. `currLevel` is a param (caller hoists the `level` read). Curse penalty rides the already-loaded word (zero new SLOAD, as documented @363). | 0 | H | inert | none — exemplary single-SLOAD design. |
| 470-665 | `_recordMintData`: single `prevData` load @476, single conditional `mintPacked_[player] = data` write per branch (guarded `if (data != prevData)`). `affiliateBonusPointsBest` external call only on the new-level ≥4-units branch (piggybacks the SSTORE). | 0 | H | inert | none — already optimal. |
| 145-148 | `_farFutureFractionBps`: pure two-line curve, no SLOAD. | 0 | — | inert | none. |
| 167-207 | `_quoteFarFutureSwap`: `levels`/`quantities` are `calldata` (not `memory`) — already optimal. Loop reads only calldata + `priceForLevel`. | 0 | H | inert | none — `calldata` already used. |

No packing/dead-code/redundant-SLOAD candidates. This file is the cleanest of the new surface.

---

## contracts/DegenerusTraitUtils.sol (+118)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| foilCuts (boost ladder) | `foilCuts(multBps)` builds the /15360 ladder; callers (`_deriveFoilLines`, `packedTraitsFoil`) already hoist it once and share across lanes. The `traitFromWordFoil` wrapper rebuilds per call but is doc-flagged "callers resolving many entries should hoist foilCuts" — and the hot paths DO hoist. | 0 | H | RNG/EV | none — the math is RNG-byte-load-bearing; do NOT alter. Already hoisted on hot paths. |
| foilTrait | 7-branch running-sum walk identical to `weightedColorBucket`. `cut` is `memory uint256[7]` param — reused, not re-derived. | 0 | H | RNG/EV | none — behavior-frozen; do NOT touch. |
| packedTraitsFoil | Builds `cut` once, 4 lanes. Optimal. Note: appears UNUSED by the live modules (the drain/claim use the local `_deriveFoilLines` which calls `foilTrait` directly, not `packedTraitsFoil`). | dead-code candidate | M | inert (removal) | **POSSIBLE DEAD CODE**: `packedTraitsFoil` and `traitFromWordFoil` may have no on-chain caller (verify with a repo-wide grep over `contracts/`). If only referenced by tests, they are internal-library dead code that still costs bytecode in any contract that imports the lib. SKEPTIC: confirm no `contracts/**` caller before recommending removal — library internal fns are inlined only if called, so unused ones add no runtime gas but do add source/audit surface. LOW priority. |

**HIGH-RISK boundary:** every byte of `foilCuts`/`foilTrait` feeds RNG-derived trait bytes that must equal the drain's filed entries and the claim's re-derivation (the load-bearing mint==claim invariant). Do NOT micro-optimize the arithmetic — any rounding shift corrupts the match. Flagged, not recommended.

---

## contracts/storage/DegenerusGameStorage.sol (+180)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| foilCursor/foilDrainDay/foilLastResolveDay | uint32+uint24+uint24 = 80 bits — **already share one slot** (declared consecutively). | 0 | H | LAYOUT | none — already packed; do NOT reorder. |
| foilRecord value | resolveDay(24)+multBps(16)+activityScore(16) packed in one uint256 via shifts. | 0 | H | LAYOUT | none — optimal. |
| dailyFoilDraw value | mainSet(32)+bonusSet(32)+level(24) packed in one uint256. | 0 | H | LAYOUT | none — optimal. |
| _foilRecordFor / _foilMultFor / _foilBoughtThisLevel / _foilDrawFor / _foilDrainPending | Each is a single-SLOAD view helper. `_foilBoughtThisLevel` and `_foilMultFor` both read `foilRecord[lvl][player]` — but they are called on disjoint paths (cap-check vs drain), never back-to-back, so no shared-read win. | 0 | H | inert | none. |
| FOIL_* constants | All `internal constant` / `private constant` — no storage slots. | 0 | H | inert | none — correct. |

No new mutable state needs packing. No layout action recommended.

---

## contracts/libraries/ActivityCurveLib.sol (+37)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| foilBoostBps + FOIL_*_BPS | All new values are `internal constant`; the piecewise-linear interp is pure stack math with early-exit guards (score==0, >=cap). No SLOAD, no loop. | 0 | H | RNG/EV-adjacent | none — the constants are EV-calibrated (frozen multiplier); do NOT alter values. Structure already optimal. |

---

## contracts/modules/DegenerusGameJackpotModule.sol (+77)

| file:line | candidate | est saving | conf | risk | exact suggested change |
|---|---|---|---|---|---|
| 1379-1392 | `_rollHeroSymbol` now takes `excludeIdx`; inner loop computes `idx = (q<<3)\|s` BEFORE the amount read and gates the SLOAD-free packed-shift on `idx == excludeIdx`. The `dailyHeroWagers[day][q]` SLOAD is hoisted to the outer `q` loop (once per quadrant) — already optimal. | 0 | H | inert | none — the refactor kept the per-quadrant single SLOAD. |
| 1585-1590, 1845-1858 | `dailyFoilDraw[questDay] = _packFoilDraw(...)` — one SSTORE per daily seal (cold→warm new slot). Necessary new write (foil==jackpot persistence). The packed-set values (`mainTraitsPacked`/`bonusTraitsPacked`) are locals already computed for the emit — reused, not recomputed. | 0 (required write) | H | inert | none — minimal (one SSTORE/day, reuses existing locals). |
| 1778-1804 | `_rollWinningTraits` bonus path now calls `_rollHeroSymbol` TWICE (main-hero off unsalted @1789, bonus-hero off salted @1796) to force a distinct hero. This is **new required work** (the distinct-hero feature), not redundant — each call reads different entropy. NOT a gas candidate (behavior change, not inert). | — | — | RNG/EV | none — load-bearing; do NOT collapse. |

The double `_rollHeroSymbol` in the bonus path is the cost of the distinct-hero feature, not waste. No inert reduction available here.

---

## Remaining diff files (light) — swept, nothing material

- **DegenerusGameAdvanceModule.sol (+27):** `ticketQueue[rk].length != 0 || _foilDrainPending()` short-circuit ordering already optimal (cheap length read first; `_foilDrainPending` is 1 SLOAD when no foil bought). The `> 0` vs `!= 0` on the length is a ~3-gas micro-tweak and the sites already used `> 0` pre-edit — skip (consistency, trivial).
- **DegenerusGameLootboxModule.sol (+9):** only adds literal `uint32(0)` trailing arg to box-spin delegatecall encodings — compile-time constant, zero runtime cost. Nothing.
- **GameAfkingModule.sol (+18):** `floorAfkingStreakBase` mirrors the v70-frozen `recordAfkingSecondary` double-guard (`_subscriberIndex==0` then `afkingStartDay==0`) — intentional established pattern, no new redundancy. Conditional `_setStreakBase` write only when below floor. Nothing.
- **DegenerusQuests.sol (+148):** `foilStreakBoost` / `handleFoilPack` each call `_loadActiveQuests()` once and reuse; `QUEST_TYPE_RESERVED`→`QUEST_TYPE_FOIL` repurpose keeps value 4 (no slot change); all new values are constants. Nothing.
- **DegenerusVault.sol (+9):** interface widened with trailing `bool foil`, call site passes literal `false` — compile-time constant, zero runtime. Nothing.
- **ContractAddresses.sol (+3), interfaces (IDegenerusGame/IDegenerusGameModules/IDegenerusQuests):** address constant + interface signature additions — no executable body, no gas surface.

---

## Summary

- **Total candidates:** 7 actionable + ~5 noted-only (folds/required-writes) + 2 HIGH-RISK boundaries flagged-not-recommended.
- **TOP PICKS (high-confidence, behavior-inert, non-layout):** 5 — all warm-SLOAD eliminations on the foil-buy / advance hot paths (FoilPackModule level/rngLockedFlag/dailyIdx/jackpotPhaseFlag caches collapse to the foil-buy entry; MintModule `total != 0`; Game.sol `level` cache). Combined ≈ 600 gas/foil-buy + ≈ 100 gas/finished-batch advance.
- **Single biggest opportunity:** the `buyFoilPack` SLOAD caching cluster (FoilPackModule.sol:156-163/177/229/297) — `level` ×3, `jackpotPhaseFlag` ×2, `rngLockedFlag` ×2, `dailyIdx` ×2 all collapse to one read each. ~500 gas on a player-facing hot path, fully behavior-inert, no layout/RNG touch. Do these together as one hoisting edit at the top of the function.
- **Layout / RNG / EV:** no reorders or arithmetic changes recommended. Foil storage is already optimally packed; foilCuts/foilTrait/ActivityCurveLib/Degenerette-rig math is RNG/EV-load-bearing and must stay byte-frozen.
- **Possible dead code (LOW, verify first):** `DegenerusTraitUtils.packedTraitsFoil` and `traitFromWordFoil` may lack any `contracts/**` caller (the live paths use the foil module's local `_deriveFoilLines`+`foilTrait`). No runtime gas cost (uncalled internal lib fns aren't inlined), only audit/source surface. SKEPTIC: grep-confirm before any removal.
