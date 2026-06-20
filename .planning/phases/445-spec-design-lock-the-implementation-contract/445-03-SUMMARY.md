---
phase: 445-spec-design-lock-the-implementation-contract
plan: 03
subsystem: v71.0 Foil Pack — entrypoints + match + payout + placement
tags: [spec, design-lock, foilpack, entrypoints, match-lottery, payout, eip-170]
requires:
  - 445-RESEARCH.md (§B/§E/§F/§G — adversarially verified V2/V3 PASS)
  - 445-CONTEXT.md (D-04 placement, D-05 calibration policy)
  - 445-SPEC-A-economics.md (PMF + foilBoostBps coefficients)
  - 445-SPEC-D-storage.md (foilRecord + foilMatchClaimed layout)
provides:
  - 445-SPEC-E-entrypoints.md (locked entrypoint signatures, match algorithm, payout lanes, calibration, placement)
affects:
  - 445-04 (consolidation of all SPEC sections into the build-ready contract)
  - 446 (IMPL — writes buyFoilPack/claimFoilMatch + GAME_FOILPACK_MODULE from this section)
tech-stack:
  added: []
  patterns:
    - thin facade stub (buyPresaleBox pattern, DegenerusGame.sol:614-629)
    - century level-stamp idiom (per-raw-level cap via foilRecord stamp)
    - sparse keccak claimed marker (CEI, foilMatchClaimed)
    - cloned ETH cap+spill (ETH_WIN_CAP_BPS=1000, DegenerusGameDegeneretteModule.sol:877-915)
key-files:
  created:
    - .planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-E-entrypoints.md
  modified: []
decisions:
  - "D-04 traced: placement is the engineering EIP-170 call — new GAME_FOILPACK_MODULE (~8-11 KB body, ~13.5-16.5 KB headroom), NOT MintModule (near-full, SEC-03-excluded); storage appended in DegenerusGameStorage only"
  - "D-05 traced: payout table LOCKED; calibration CONFIRMED at 1.9376 faces/pack/30d (3.1% low, not materially off) — reported, no recalibration flag, never silently retuned"
metrics:
  duration: "~10 min"
  completed: 2026-06-19
  tasks: 3
  files: 1
  commits: 3
---

# Phase 445 Plan 03: Entrypoints + Match + Payout + Calibration + Placement Summary

Locked the v71.0 Foil Pack implementation surface — the `buyFoilPack()` / `claimFoilMatch(day, ticketIndex, drawKind)` signatures and ordered module bodies, the LIVE-vs-HERO-FREE winning-set re-derivation with the steer-proof 4-of-4 gate, the isolated 40/40/20 payout schedule, the closed-form ≈2-faces/pack/30d calibration confirm, and the new `GAME_FOILPACK_MODULE` placement under EIP-170 — so an IMPL-446 author writes both entrypoints, the match predicate, the payout, and stands up the module with zero further decision. Paper-only; no `.sol` touched.

## What Was Built

`445-SPEC-E-entrypoints.md` (411 lines, three sections E.1/E.2 + E.3 + E.5/E.7/F) transcribing the V2/V3-verified corrected numbers from RESEARCH.md verbatim:

- **E.1/E.2 (Task 1):** `buyFoilPack() external payable` thin facade stub (buyPresaleBox pattern) + the ordered `_buyFoilPack` body — liveness gate, one-per-raw-level cap (stamp written after price settles), `10 * PriceLookupLib.priceForLevel(lvl)` price (FOIL-02), the afking-rejection guard (the `remaining > avail ⇒ revert E()` residual; FOIL-03), the `FOIL_TO_FUTURE_BPS = 2500` 75/25 pool fork (FOIL-04), boost freeze from `_playerActivityScore`, the 4-signature roll with a deterministic frozen seed, **the corrected `_queueTicketsScaled(buyer, _activeTicketLevel(), 400, false)`** (400-scale, not 4), and no buy-time reward mint. Plus the `claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind)` signature and ordered body using the unified `foilMatchClaimed` marker set before payout (CEI), with the full 6-bit positional count (color-only excluded; MATCH-03).
- **E.3 (Task 2):** the `getRandomTraits` uniform 6-bit substrate (boost cancels → per-quadrant 1/64); the HERO-FREE (no `_applyHeroResult`) vs LIVE (`_applyHeroResult` single-quadrant override) split, byte-faithful to `_rollWinningTraits`; the **critical `dailyHeroWagers[day-1]` IMPL anchor** (`:1290-1291`); and the tier gate — 2/3-of-4 off `liveCount` (bounded hero edge kept), 4-of-4 ONLY on `heroFreeCount == 4` (steer-proof; SEC-01 basis).
- **E.5/E.7/F (Task 3):** the isolated tier→faces table (5 / 65 faces + `whalePassClaims += 1` + bonus spin) with the no-Degenerette-routing statement (MATCH-04/07); the disjoint `FOIL_MAG_TAG`/`FOIL_CCY_TAG` entropy lanes (MATCH-08); the 40/40/20 FLIP/ETH/WWXRP split with `coin.mintForGame` / `wwxrp.mintPrize` mints and the ETH `ETH_WIN_CAP_BPS = 1000` clamp + lootbox spill **cloned from the corrected anchor `DegenerusGameDegeneretteModule.sol:877-915`** (SEC-02 basis); the closed-form calibration confirm (`E[faces/pack/30d] = 1.9376`, 87.9%/12.1% split, M≈2.4854 crossover, 4-of-4 ≈1-in-69,906) with the D-05 "not materially off / no recalibration" verdict (MATCH-10); and the new `GAME_FOILPACK_MODULE` placement (~13.5–16.5 KB headroom) with the re-measure-at-IMPL caveat (SEC-03, D-04).

## Requirements Locked

FOIL-02, FOIL-03, FOIL-04, MATCH-03, MATCH-04, MATCH-06, MATCH-07, MATCH-08, MATCH-09, MATCH-10, SEC-03 — plus the SEC-01 (steer-proof 4-of-4) and SEC-02 (ETH ≤ 10%-pool) design basis (attested downstream at 448).

## Key Decisions Traced

- **D-04 (module placement):** the engineering EIP-170 call — a NEW `GAME_FOILPACK_MODULE` (estimated 8–11 KB body, ~13.5–16.5 KB headroom), explicitly NOT `MintModule` (~1,116 B free, SEC-03-excluded); storage appended in `DegenerusGameStorage` only; two thin facade stubs (facade retains ~3.3–3.7 KB); one new `ContractAddresses.sol` constant. Re-measure-at-IMPL caveat stated (HARD-REQ §6.7).
- **D-05 (calibration policy):** the payout table is LOCKED. Confirmed and reported `E[faces/pack/30d] = 1.9376` (3.1% low vs the ~2 target) → not materially off → no recalibration flag. The closed-form (per-quadrant match collapses to constant `q = 1/64`) makes a Monte-Carlo optional confirmation, not a gating recompute. If 447's empirical run lands materially off ≈2, flag to USER — never silently retune.

## Deviations from Plan

None — plan executed exactly as written. Every corrected anchor (the 400-scale queue, `dailyHeroWagers[day-1]`, the ETH-cap clone at `:877-915`, the unified `foilMatchClaimed`) was transcribed verbatim from the V2/V3-verified RESEARCH.md. Load-bearing contract anchors were spot-checked against source before transcription (`buyPresaleBox:614-629`, `getRandomTraits:281-286`, hero `dailyIdx`-lag `:1288-1292`, `ETH_WIN_CAP_BPS=1000` at `:221`, `maxEth:889`, `whalePassClaims:1122`, `GAME_*_MODULE:13-35`) — all matched.

## Authentication Gates

None.

## Known Stubs

None — the SPEC describes a finalized design contract; no placeholder/TODO content.

## Threat Flags

None — the section pins the design basis for the existing trust boundaries already enumerated in the plan's `<threat_model>` (T-445-E1..E4); no new security surface beyond the locked design was introduced.

## Verification

- All three task automated verification gates: PASS.
- Plan-level `<verification>` string-presence: all six load-bearing strings present (`_queueTicketsScaled(...400, false)`, `heroFreeCount == 4`, `dailyHeroWagers[day-1]`, `ETH_WIN_CAP_BPS = 1000`, `1.9376`, `GAME_FOILPACK_MODULE`) plus the `877-915` clone anchor.
- `git diff --quiet -- contracts/` clean after every commit — no `.sol` modified.

## Self-Check: PASSED

- File exists: `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-E-entrypoints.md` — FOUND.
- Commits exist: `14e5de68` (Task 1), `be6d0b62` (Task 2), `5a9368bc` (Task 3) — all FOUND in `git log`.
- `contracts/` clean — VERIFIED.
