# Phase 411: RNGNET — Re-Derive the VRF-Consumer Net From HEAD

**Completed:** 2026-06-16
**Status:** PASSED — RNGNET-01 + RNGNET-02 + RNGNET-03 satisfied.
**Deliverable:** `.planning/v66-RNGNET-CONSUMER-NET.md` (supersedes the stale `RNGLOCK-CATALOG.md`).
**Method:** Claude workflow net (4 cluster agents re-deriving FROM HEAD) + cross-model council (gemini-flash + codex), both read-only; tree `0dd445a6` verified intact after each fan-out.

## Headline

The trusted catalog enumerated **13** VRF consumers. The re-derived current-HEAD net is **72** (council-verified). That gap IS the structural reason a defect could survive 10+ "clean" passes — the audit net was drawn once against a far smaller, pre-rename surface and never re-derived.

## RNGNET-01 — re-derived from HEAD
Mechanical enumeration of every `rngWordByDay` / `rngWordForDay` / `rngWordCurrent` / `lootboxRngWordByIndex` read + every `EntropyLib`/keccak derivation over a VRF word, independent of the catalog. 67 consumers from 4 Claude clusters; **codex added 5 more** (decimator jackpot normal+terminal, daily+level quest rolls, deity-boon viewer) that the Claude clusters' file assignment missed → **72 total**. Gemini-flash independently found 0 missing beyond these.

## RNGNET-02 — diff vs the catalog
- **28 missing** from the catalog's 13-list (entire BAF winner-select surface, the whole afking subsystem, salvage `_farFutureSeed`, the sDGNRS-side redemption seed mix + submit gate, Degenerette FLIP survival flip + box-spins, advance producer/keep-roll/backfill sites) + the 5 codex-found.
- **20 misclassified** (stale call sites, removed `flipDay` struct, dead `BurnieCoinflip`/`StakedDegenerusStonk` names, writer-only rows).
- **All 5 panel-flagged suspected-missing seeds CONFIRMED present + uncatalogued.**

## RNGNET-03 — stale-anchor reconciliation (9)
The catalog + v30 state-machine + v30 freeze-proof are a pre-rename historical SUBSET, not current truth. Key: the §12 "headline #1 cross-day re-roll exploit" is fully REMEDIATED (day-keyed redemption model; `redemptionPeriodIndex`/`pendingRedemptionEthBase` removed; `_pendingResolveDay` sentinel + `BurnsBlockedBeforeDailyRng`); the v30 third clear-site C-02 (`updateVrfCoordinatorAndSub rngLockedFlag=false`) is REMOVED — rotation now KEEPS the lock + re-issues, leaving `_unlockRng` as the SOLE clear; `currentDayView()` cross-calls replaced by local `GameTimeLib`; every line anchor off by tens-to-hundreds.

## Candidate finding (carried to 412/413 adversarial-verify)
- **`_deityBoonForSlot` MUTABLE-INPUT — TRIPLE-CONFIRMED (Claude + gemini + codex):** boon seed = `keccak(rngWord, deity, day, slot)` where the deity picks recipient + slot AFTER the day's word is publicly readable (`Lootbox:1138/1149/2319`). Severity pending 412/413 verify + USER adjudication (deity boon is a granted power — the question is whether the OUTCOME is grindable beyond intent).

## Open-freeze consumers → Phase 412 / 413 (the hunt queue, ~35)
Dominated by: BAF/jackpot winner-selects over player-mutable `traitBurnTicket`/`ticketQueue`; the decimator subbucket derivations; the daily/level quest rolls; the salvage prior-day-word seed; the `_awardDegeneretteDgnrs` drainable-reward-pool read; the gameover prevrandao fallback. Plus **2 council DIVERGENCES** as priority adjudications: `dailyHeroWagers` freshness window (gemini open / codex protected-by-day-offset) and the sDGNRS day+1 redemption seam (gemini open / codex pinned-by-submit-gate).

## Artifacts
- `.planning/v66-RNGNET-CONSUMER-NET.md` — the net (72), the diff, the council layer, the 9 stale anchors, the open-freeze routing.
- Workflow `wf_59121131-0b4`; council legs codex `b5147ohcl` + gemini-flash `bkqeq9aze`.
