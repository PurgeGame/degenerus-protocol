---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 03
status: complete
requirements: [HERO-01, HERO-02, HERO-03, HERO-05]
files_modified:
  - contracts/modules/DegenerusGameDegeneretteModule.sol
committed: false
tst_handoff: true
---

# 326-03 HERO — Degenerette hero = 2-point scoring element (S = A + 2*H)

## Scoring (Task 1)
`_countMatches(playerTicket, resultTicket)` → **`_score(playerTicket, resultTicket, heroQuadrant) ∈ {0..9}`**:
- 4 color axes (all quadrants) + 3 non-hero symbol axes = ordinary count A ∈ {0..7}.
- hero quadrant's SYMBOL match scores **2** (`s += (q == heroQuadrant) ? 2 : 1`); its color stays ordinary.
- S = A + 2H, max 9; hero-alone ⇒ S=2 (a win, floor S≥2 encoded by the packed table's 0-valued S=0/S=1 slots).
- Resolve path (`_resolveFullTicketBet`): `matches` → `s` flows to `_getBasePayoutBps(N,s)`, `_fullTicketPayout`, the `FullTicketResult` event, and the award gate. `FT_HERO_SHIFT` decode + `heroQuadrant >= 4` revert KEPT. N selector (`_countGoldQuadrants`) + activity curve (`_roiBpsFromScore`) byte-unchanged.

## Net-deletion + layout (Task 2)
- **DELETED** the standalone multiplier apparatus: `_applyHeroMultiplier`, `HERO_BOOST_N0..N4_PACKED`, `HERO_PENALTY`, `HERO_SCALE`, their comment block, and the `matches >= 2 && matches < 8` carve-out in `_fullTicketPayout`. grep-confirmed zero survivors. `_fullTicketPayout` lost its now-unused `resultTicket`/`heroQuadrant` params and dispatches purely on `s`.
- **Packing (settled SPEC layout):** `QUICK_PLAY_PAYOUTS_N{N}_PACKED` keeps S=0..7 (8×32-bit, dispatch `(packed>>(s*32))&0xFFFFFFFF`); **separate** `QUICK_PLAY_PAYOUT_N{N}_S8` + `_S9` per-N constants, dispatched `if (s>=9) ...S9; if (s==8) ...S8;` ahead of the packed path. `_M8` → `_S9` (S=9 ≡ old M=8, value unchanged — the jackpot relabel).
- **Thresholds re-mapped (D-03 shift-by-one):** DGNRS award gate `matches >= 6` → `s >= 7`; `DEGEN_DGNRS_6/7/8_BPS` → `DEGEN_DGNRS_7/8/9_BPS` (S=7→4% / S=8→8% / S=9→15%, rarity preserved). WWXRP `_wwxrpBonusBucket` floor M≥5 → **S≥6** (buckets 6/7/8/9), `_wwxrpFactor` dispatch offset `(bucket-5)` → `(bucket-6)`.

## ⚠ TST HANDOFF (Phase 327 — `derive_5_tables.py` PASS_ALL byte-reproduce)
The byte-exact S∈{0..9} table VALUES are **placeholders**, NOT final:
- `QUICK_PLAY_PAYOUTS_N{N}_PACKED` (S=0..7) — still hold the **old M-indexed values** (clearly-commented placeholders).
- `QUICK_PLAY_PAYOUT_N{N}_S8` = **0** (placeholder).
- `WWXRP_FACTORS_N{N}_PACKED` — old values, placeholders (bucket re-map S=6..9 pending re-derivation).
- FINAL (not placeholder): `QUICK_PLAY_PAYOUT_N{N}_S9` (= old M=8 jackpot, identical odds — a relabel).
- **Expected at 326-08:** Degenerette payout-table tests may fail until the Phase-327 byte-reproduce → classify as **KNOWN-TST-DEFERRED**, NOT a v48 regression. (S=8 paying 0 in the interim is the placeholder showing through.)

## ⚠ SHAPE DECISION for hand-review / TST
WWXRP bucket floor set to **S≥6** (shift-by-one from old M≥5), preserving the 4-bucket factor packing. The SPEC D-03 headline reads "at S≥7" but explicitly invokes "shift-by-one, consistent with S=9≡M=8"; DGNRS (M≥6) → S≥7 and WWXRP (M≥5) → S≥6 are both shift-by-one from their own floors. Flagged for TST confirmation.

## Untouched (verified)
`dailyHeroWagers` / `_rollHeroSymbol` (HERO-06 no-leak, C6); `_countGoldQuadrants`; `_roiBpsFromScore`; the `resolveBets` write-batch / `acc` flush shape (DGAS — only inside-loop score/payout/event/award edges changed). Event field name `matches` retained (indexer track out-of-scope); NatSpec range updated 0-8 → 0-9.

## Verification
- `forge build` (whole tree, Wave 1) = 0 errors.
- grep: `_score` present; `_countMatches`/`_applyHeroMultiplier`/`HERO_BOOST`/`HERO_PENALTY`/`HERO_SCALE`/`_M8`/`matchCount`/`matches >= 6` all gone; `heroQuadrant >= 4` + `FT_HERO_SHIFT` kept.

## Not committed
Batched-diff discipline.
