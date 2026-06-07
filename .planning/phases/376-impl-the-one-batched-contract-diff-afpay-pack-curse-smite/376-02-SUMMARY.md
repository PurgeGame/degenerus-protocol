---
phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite
plan: 02
subsystem: payments
tags: [solidity, bitpacking, activity-score, curse, smite, deity, delegatecall]

# Dependency graph
requires:
  - phase: 375
    provides: SPEC-V61-DESIGN-LOCK (D-03 cap=20, D-04 protocol-skip, D-05 staleness basis, curse/smite design)
provides:
  - Cashout/smite curse counter in mintPacked_ bits [215-222] (uint8, MASK_8, CURSE_COUNT_SHIFT=215)
  - Activity-score curse penalty APPLY in _playerActivityScore (curse*100 bps, floored at 0)
  - Curse infra in MintStreakUtils: CURSE_COUNT_CAP=20, _applyCurseStack (saturating +2), _clearCurse, curseCountOf view
  - SET via maybeCurse (GameAfkingModule), delegatecalled from claimWinnings; CURE in _purchaseForWith
  - decurse (100 BURNIE) + deity-gated smite (200 BURNIE) in GameAfkingModule + Game dispatch stubs + Decursed/Smited events
  - _recordLootboxMintDay relocated WhaleModule -> MintStreakUtils base; manual lootbox leg now stamps DAY_SHIFT
affects: [376-03, 377-gas, 378-tst-sec]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single saturating uint8 curse field shared by two sources (cashout SET +2, deity smite +2) with one APPLY site and one cap (D-03=20); the cap doubles as the uint8-wrap guard."
    - "Curse SET as a delegatecall (USER-approved deviation, overrides PLACE-01 inline): claimWinnings delegatecalls IGameAfkingModule.maybeCurse(player); the impl + decurse/smite live in GameAfkingModule (EIP-170 headroom)."

key-files:
  created: []
  modified:
    - contracts/libraries/BitPackingLib.sol
    - contracts/modules/DegenerusGameMintStreakUtils.sol
    - contracts/modules/GameAfkingModule.sol
    - contracts/DegenerusGame.sol
    - contracts/interfaces/IDegenerusGameModules.sol

key-decisions:
  - "CURSE_COUNT_CAP = 20 (D-03): 10 ghost-cashouts at +2 (or 10 smite stacks); the cap is also the mandatory uint8-wrap guard. Smite ceiling = 5 stacks (10 pts), below the 20 cap."
  - "Protocol-addr skip (D-04): smite + maybeCurse skip VAULT/SDGNRS/GNRUS via constant compares (no SLOAD) to protect the sDGNRS redemption-snapshot score read."
  - "Staleness basis = _currentMintDay() (D-05): maybeCurse uses `lastEthDay + 5 > _currentMintDay()`, sharing the ticket cure-stamp day basis."
  - "Self-smite allowed (Verification Item 2): harmless-by-design — curse only LOWERS the score, burns the caller's own BURNIE, feeds no bounty/keeper path."

patterns-established:
  - "Zero-new-SLOAD APPLY: the curse penalty rides the existing mintPacked_ load at MintStreakUtils:248; penalty = curse*100 bps subtracted from bonusBps, floored at 0, just before scoreBps = bonusBps."

requirements-completed: [CURSE-01, CURSE-02, CURSE-03, CURSE-04, CURSE-05, CURSE-06, CURSE-07, SMITE-01]

# Metrics
duration: ~session (prior)
completed: 2026-06-06
---

# Phase 376-02: Cashout-curse + deity-smite on a shared saturating activity-score penalty

**A uint8 curse counter packed into `mintPacked_` bits [215-222], penalizing activity score by `curse*100` bps; set +2 on a stale ghost-cashout (`maybeCurse` from `claimWinnings`), curable by a real buy or paid `decurse` (100 BURNIE), and stackable by deity `smite` (200 BURNIE) — all sharing one cap (20), one APPLY, and one cure.**

## Accomplishments
- **CURSE-01** — `BitPackingLib.CURSE_COUNT_SHIFT = 215` (`:89`) + `MASK_8` (`:45`); layout doc updated to `[215-222]` (`:22`). Empirically clobber-free (all `mintPacked_` writers are field-isolated RMW).
- **CURSE-02** — APPLY in `_playerActivityScore` (`MintStreakUtils:322`), riding the existing packed SLOAD (`:248`, zero new SLOAD): `penalty = curse*100` bps, `bonusBps = bonusBps > penalty ? bonusBps - penalty : 0`. Propagates to every consumer + the public view + frozen snapshots.
- **CURSE-07** — `CURSE_COUNT_CAP = 20` (`:348`), `_applyCurseStack` (saturating +2, `:351`), `_clearCurse` (`:366`), `curseCountOf` external view (`:378`) — all in MintStreakUtils.
- **CURSE-03** — SET = `maybeCurse(player)` (`GameAfkingModule:1668`), delegatecalled from `claimWinnings` after a successful `_claimWinningsInternal`. Cheapest-first bails: infra (VAULT/SDGNRS/GNRUS) → gameOver → non-stale (`lastEthDay + 5 > _currentMintDay()`) → deity → whale/lazy pass → active afker → already at cap; else `+2` saturating. NOT on `claimWinningsStethFirst`.
- **CURSE-04** — CURE `_clearCurse(buyer)` when `totalCost >= priceWei` in `_purchaseForWith`, folded into the existing `mintPacked_` RMW (no write-after-write clobber).
- **CURSE-05** — `_recordLootboxMintDay` relocated `WhaleModule` → `MintStreakUtils` base; the plain standalone lootbox leg in `_purchaseForWith` now stamps `DAY_SHIFT`.
- **CURSE-06 / SMITE-01** — `decurse(target)` (100 BURNIE; `:1696`) + `smite(deityId, smitee)` (200 BURNIE; `:1710`, gate `ownerOf(deityId) == msg.sender`, bails active-afker / >=10 pts / protocol; self-smite allowed) impls in GameAfkingModule; thin Game dispatch stubs; events `Decursed`/`Smited`; selectors in `IGameAfkingModule`.

## Files Created/Modified
- `contracts/libraries/BitPackingLib.sol` — `CURSE_COUNT_SHIFT`, `MASK_8`, layout doc.
- `contracts/modules/DegenerusGameMintStreakUtils.sol` — APPLY, cap, `_applyCurseStack`, `_clearCurse`, `curseCountOf`, relocated `_recordLootboxMintDay`.
- `contracts/modules/GameAfkingModule.sol` — `maybeCurse`, `decurse`, `smite`, events.
- `contracts/DegenerusGame.sol` — `claimWinnings` → `maybeCurse` delegatecall; CURE in `_purchaseForWith`; lootbox-leg stamp; `decurse`/`smite` dispatch stubs.
- `contracts/interfaces/IDegenerusGameModules.sol` — `maybeCurse`/`decurse`/`smite` selectors.

## Decisions Made
See key-decisions frontmatter (D-03 cap, D-04 protocol-skip, D-05 staleness basis, self-smite verdict — all from the 375 SPEC lock).

## Deviations from Plan
- **Curse SET as a delegatecall** (USER-approved, overrides PLACE-01 "inline"): `claimWinnings` delegatecalls `IGameAfkingModule.maybeCurse(player)`; impl lives in GameAfkingModule (chosen for EIP-170 headroom; the base `_maybeCurse` was removed).

## Issues Encountered
None (build-cleanliness + EIP-170 handled in 376-03).

## Next Phase Readiness
- Contracts compile; diff HELD at the contract-commit boundary (see 376-03). SEC-01 (378) proves the RNG-freeze floor (the curse path is score-only, no rngWord read).

---
*Phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite (plan 02)*
*Completed: 2026-06-06*
