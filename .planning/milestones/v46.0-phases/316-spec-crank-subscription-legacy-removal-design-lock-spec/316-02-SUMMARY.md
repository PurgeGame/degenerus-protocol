---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
plan: 02
subsystem: spec-design-lock
tags: [remove-footprint, storage-slot-shift, vrf-freeze-retirement, rm-04, keep-expose, reconciliation]
requires:
  - "316-01 ADD-half sections present in 316-SPEC.md (ADD Design — Do-Work Crank / Subscription / PROTO Additions)"
  - "316-RESEARCH.md §1.1–§1.9 verified deletion-footprint table; §2 reader-set; §3 keeper-dependency; §4 + §J3 slot map; §6 entropy cascade"
provides:
  - "316-SPEC.md ## REMOVE Footprint — PROTO-01/RM-04 KEEP+EXPOSE reconciliation + RM-01..06 deletion footprint (verified lines)"
  - "316-SPEC.md ## Storage Slot-Shift Plan — COMPOUNDED RM-02+JGAS −2 shift + one-combined-forge-inspect mandate + stale-baseline hazard"
  - "316-SPEC.md ## VRF-Freeze Obligation Retirement — SAFE-04 entropy-param drop + JackpotEthWin ABI break + AUDIT routing"
affects:
  - "Phase 317 IMPL (RM-01/02/03/05/06 + JGAS-02 deletion) — deletes exactly this enumerated footprint"
  - "Phase 318 TST (slot re-derivation 'no NEW failures vs baseline')"
  - "Plan 316-05 (JGAS footprint owner — this plan carries only the slot-compounding note)"
tech-stack:
  added: []
  patterns:
    - "grep-verified file:line footprint (SC#5) — every anchor re-checked against HEAD before authoring"
    - "forge inspect storage-layout as authoritative slot source; never patch-by-arithmetic"
key-files:
  created:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-02-SUMMARY.md"
  modified:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md"
decisions:
  - "RM-04 = KEEP+EXPOSE _hasAnyLazyPass (rename private→external, NO body change); delete rest of afKing — dependency-safe IFF PROTO-01 ships same diff (keeper's sole coupling is hasAnyLazyPass at keeper :671/:974)"
  - "Storage slot-shift locked as COMPOUNDED −2: autoRebuyState@19 (−1 for ≥20) + resumeEthPool@33 own-slot (additional −1 for ≥34) → vrf*/lootboxRng* family at −2; one combined forge inspect on POST-(RM-02+JGAS) contract, never blind −1"
  - "Recorded AFKING_RECYCLE_BONUS_BPS=100 (deleted afKing tier) vs kept RECYCLE_BONUS_BPS=75 — precise values to prevent a wrong-value deletion at IMPL"
  - "JackpotModule auto-rebuy block locked at 800-808 (RESEARCH live line; +2 drift from PLAN-V47's 798-806 recorded inline)"
  - "JGAS deletion footprint left to Plan 316-05; this plan carries only the resumeEthPool slot-compounding note"
metrics:
  duration: "~12 min"
  completed: "2026-05-23"
  tasks: 2
  commits: 2
  files_changed: 1
---

# Phase 316 Plan 02: REMOVE Footprint + Reconciliation + Storage Slot-Shift + VRF-Freeze Retirement Summary

REMOVE-half design lock for v46.0 — appends three sections to `316-SPEC.md` locking the PROTO-01/RM-04 KEEP+EXPOSE reconciliation, the grep-verified RM-01..06 deletion footprint, the COMPOUNDED RM-02+JGAS −2 storage-slot re-derivation mandate, and the SAFE-04 VRF-freeze-obligation retirement — leaving the JGAS deletion footprint to Plan 316-05.

## What Was Built

Two `## ` sections appended in Task 1 (`## REMOVE Footprint`) and two in Task 2 (`## Storage Slot-Shift Plan`, `## VRF-Freeze Obligation Retirement`) to `316-SPEC.md`. The three 316-01 ADD-half sections (`## ADD Design — Do-Work Crank`, `## ADD Design — Subscription Sweep & Authorization`, `## PROTO Additions`) were left untouched (verified: headers still at lines 18/65/104; new sections at 120/195/245).

### Task 1 — `## REMOVE Footprint` (commit `cd0479d1`)
- **RM-04 / PROTO-01 reconciliation locked verbatim:** KEEP+EXPOSE `_hasAnyLazyPass` (rename `private`→`external` as `hasAnyLazyPass`, NO body change), delete the rest of afKing. Cited the verified 3-match reader-set (decl `DegenerusGame.sol:1610`, readers `:1580` inside `_setAfKingMode` + `:1660` inside `syncAfKingLazyPassFromCoin`, both in deleted afKing-mode machinery). Stated dependency-safe IFF PROTO-01 ships the same diff, citing the keeper-dependency finding (keeper's sole game coupling = `hasAnyLazyPass` at keeper `:671`/`:974`; zero RM-symbol matches).
- **RM-01..06 footprint enumerated by file** using RESEARCH §1 re-verified lines: the 13 DegenerusGame fns (minus kept `_hasAnyLazyPass`), 3 events (`:1476`/`:1479`/`:1482`), `AfKingLockActive` error (`:92`), 3 consts (`:151`/`:154`/`:157`), 2 `settleFlipModeChange` cross-calls (`:1603`/`:1678`); `AutoRebuyState` struct/mapping (`:910`/`:926`, slot 19); jackpot `_processAutoRebuy` (`:822`) + `_calcAutoRebuy` (PayoutUtils `:51`); BURNIE recycle collapse (drop `_afKingRecyclingBonus` `:1062` / `_afKingDeityBonusHalfBpsWithLevel` `:1078` + 5 consts); RM-05 cross-contract cascade (IDegenerusGame `:274`/`:279`/`:283`/`:288`, IBurnieCoinflip `:85`, Vault `gameSet*` wrappers + local decls, sStonk `setAfKingMode` `:13`/`:361`→self-subscribe).
- Recorded the `:800-808` JackpotModule auto-rebuy block drift (+2 vs PLAN-V47's 798-806) and the `_distributePayout` solvency check (decl `:705`, revert at `:742`).
- Marked KEEP `RECYCLE_BONUS_BPS`=75 (`:129`) + `_recyclingBonus` (`:1051`) and the byte-unmodified BURNIE win/loss RNG path (`processCoinflipPayouts` `:805`, `(rngWord & 1)` `:837`) + `KNOWN_ISSUES`.
- Stated the Degenerette 2-arg `_addClaimableEth` overload (`:1117`) is separate and untouched (Pitfall 4).
- JGAS footprint left to 316-05 (one-line cross-reference + slot-compounding note only).

### Task 2 — `## Storage Slot-Shift Plan` + `## VRF-Freeze Obligation Retirement` (commit `4f150837`)
- **COMPOUNDED slot shift locked:** `autoRebuyState`=slot 19 (RM-02) AND `resumeEthPool`=own-slot 33 (JGAS-02) deleted in the same diff → vars in [20,33) shift −1, vars at slot ≥34 shift −2. Key combined shifts tabled (`lootboxEthBase` 20→19, `vrfCoordinator` 34→32, `lootboxRngPacked` 37→35, `lootboxRngWordByIndex` 38→36, `lootboxDay` 39→37, `degeneretteBets` 45→43, `boonPacked` 61→59). Explicitly flagged the `vrf*`/`lootboxRng*` family at −2 NOT −1.
- Stated contract source has ZERO numeric slot literals → entirely test-side (~28 `SLOT_*` constants across ~15 files, listed). Locked the ONE-combined-`forge inspect`-re-derivation mandate on the POST-(RM-02+JGAS) contract (never patch-by-arithmetic, never blind −1) + the `LootboxBoonCoexistence.t.sol` already-stale + baseline-failing hazard with capture-baseline-ledger-first instruction.
- **VRF-freeze retirement:** documented the entropy cascade (`rngWord`→`EntropyLib.hash2`→`entropy`/`entropyState`→3-arg `_addClaimableEth` `:788`→`_processAutoRebuy` `:822`→`_calcAutoRebuy` `:51`); locked dropping `entropy` from the 3-arg `_addClaimableEth`; noted the `JackpotEthWin` event signature change (`:69`, fields `:75`/`:76`) ABI break; framed as the SAFE-04 "one fewer VRF consumer + three fewer player-mutable in-window inputs (`autoRebuyEnabled`/`takeProfit`/`afKingMode`)" retirement. Locked the IMPL obligation to verify no other `entropyState` consumer survives (2-arg `:1117` untouched) and routed the consumer check to `zero-day-hunter` at AUDIT.

## Verification Performed (all grep-verified against HEAD `MILESTONE_V45_AT_HEAD_62fb514b...`)
- DegenerusGame.sol: all 13 fns, decl `:1610` + readers `:1580`/`:1660`, events `:1476`/`:1479`/`:1482`, error `:92`, consts `:151`/`:154`/`:157`, cross-calls `:1603`/`:1678` — all MATCH.
- storage `:910`/`:926`; forge: `autoRebuyState`=slot 19, `lootboxEthBase`=20, `resumeEthPool`=slot 33 (uint128 own-slot, `vrfCoordinator` fresh at 34), `lootboxRngWordByIndex`=38 — all confirmed.
- JackpotModule `_addClaimableEth` `:788` (3-arg), auto-rebuy SLOAD at `:801` (consistent with locked 800-808 block), `_processAutoRebuy` `:822`, `JackpotEthWin` `:69`/`:75`/`:76`; PayoutUtils `_calcAutoRebuy` `:51`, afKingMode selector `:83`.
- DegeneretteModule 2-arg overload `:1117` (untouched), `_distributePayout` `:705` / solvency `:742`.
- BurnieCoinflip KEEP `RECYCLE_BONUS_BPS`=75 (`:129`) + `_recyclingBonus` (`:1051`/`:1055`) + win/loss `(rngWord & 1)` (`:837`); DELETE `AFKING_RECYCLE_BONUS_BPS`=100 (`:130`), the 4 other afKing consts, surgery anchors all MATCH.
- IDegenerusGame `:274`/`:279`/`:283`/`:288` + KEEP `hasDeityPass` `:376`; IBurnieCoinflip `settleFlipModeChange` `:85`; Vault local decls + wrappers + KEEP `coinSet*`; sStonk `:13`/`:361`/`:404` — all MATCH.
- Zero numeric slot literals in contract source confirmed (`grep` returns only `QUEST_SLOT_COUNT=2` + `TICKET_SLOT_BIT=1<<23`).

## Deviations from Plan

None — plan executed exactly as written. One precision correction recorded inline in the SPEC (not a deviation): `AFKING_RECYCLE_BONUS_BPS=100` is the *deleted* afKing tier, while the *kept* flat-recycle constant is `RECYCLE_BONUS_BPS=75`; PLAN-V47's "75bps" shorthand referred to the kept constant. Recorded precisely to prevent a wrong-value deletion at IMPL.

## Known Stubs

None. This is a design-lock document; no code stubs introduced.

## Threat Flags

None. Zero new security-relevant surface introduced (read-only doc authoring; zero `contracts/`/`test/` mutations).

## Constraints Honored
- ZERO `contracts/*.sol` and ZERO test-file mutations (verified: 2-commit diff touches only `316-SPEC.md`).
- `.planning/` force-added (`git add -f`) on both commits; contract-dirty commit hook not triggered (zero contracts touched); no `--no-verify`.
- 316-01's ADD-half sections untouched (headers verified at lines 18/65/104).
- Every file:line re-grep-verified against contract HEAD before authoring (SC#5, `feedback_verify_call_graph_against_source`).
- No fenced solidity implementation bodies in the REMOVE-half sections (symbols/lines as prose/table only).

## Self-Check: PASSED
- FOUND: `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` (## REMOVE Footprint, ## Storage Slot-Shift Plan, ## VRF-Freeze Obligation Retirement all present)
- FOUND: commit `cd0479d1` (Task 1), `4f150837` (Task 2)
- Confirmed: 2-commit diff (`HEAD~2 HEAD`) touches only `316-SPEC.md`; zero `.sol`/test files.
