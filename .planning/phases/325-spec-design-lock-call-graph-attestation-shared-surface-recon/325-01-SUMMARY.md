---
phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
plan: 01
subsystem: audit
tags: [attestation, call-graph, grep-verify, solidity, v48, spec-design-lock]

# Dependency graph
requires:
  - phase: 324-terminal-delta-audit-3-skill-adversarial-sweep-closure
    provides: v47.0 closure HEAD da5c9d50 (the frozen attestation baseline) + the 2 deferred findings F-47-01/F-47-02
provides:
  - "325-ATTEST-PFIX-RFALL.md — per-anchor grep tables for item 1 (PFIX) + item 2 (RFALL)"
  - "325-ATTEST-KEEP-POOL.md — per-anchor grep tables for item 3 (KEEP) + item 4 (POOL), incl. KEEP-04/KEEP-05/POOL-05 resolutions"
  - "325-ATTEST-BTOMB-HERO.md — per-anchor grep tables for item 5 (BTOMB) + item 6 (HERO), incl. BTOMB feasibility + HERO-06 no-leak"
  - "0 IMPL blockers across items 1-6; every cited file:line resolved at baseline da5c9d50"
affects: [325-03 (Plan 03 shared-surface reconciliation), 326-IMPL (the batched contract diff)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-anchor grep-verdict table (MATCH/SHIFTED(±N)/ABSENT) mirroring 321-ATTEST-TOMB.md"
    - "Baseline-anchored attestation: live tree == da5c9d50 (zero contract drift), grep live = grep baseline"

key-files:
  created:
    - .planning/phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-ATTEST-PFIX-RFALL.md
    - .planning/phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-ATTEST-KEEP-POOL.md
    - .planning/phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-ATTEST-BTOMB-HERO.md
  modified: []

key-decisions:
  - "KEEP-04 = YES: a registered owner==VAULT affiliate code exists (bytes32(\"DGNRS\")=AFFILIATE_CODE_DGNRS, seeded DegenerusAffiliate.sol:247-254); no register-one setup step needed"
  - "KEEP-05 = EXISTING: autoOpen is a rename of the live permissionless crankBoxes/_crankOpenBox (DegenerusGame.sol:1636/:1705), not a new capability"
  - "POOL-05 = VERBATIM MATCH: withdraw(uint256) (AfKing.sol:318) + poolOf(address) returns (uint256) (AfKing.sol:503) match the planned interface adds exactly; AfKing.sol needs no other change for item 4"
  - "KEEP-03 wiring-site correction: the affiliate code 0 is hard-coded at DegenerusGame.sol:1778 (_batchPurchaseUnit → _purchaseFor(..., bytes32(0), ...)), NOT in AfKing.sol — AfKing.batchPurchase carries no affiliate argument"
  - "BTOMB path clarification: reuse the clean GAME-gated vaultEscrow (BurnieCoin.sol:557-567) for the one-shot flood, not the :370 reclassification site (which pairs += vaultAllowance with -= totalSupply)"
  - "HERO-06 no-leak CONFIRMED: dailyHeroWagers/_rollHeroSymbol read the wagered hero-symbol pool, not per-bet matches/S scores — the 0-8→0-9 range widening cannot leak into the daily-hero jackpot"

patterns-established:
  - "ATTEST verdict table: # | Anchor (claimed) | ACTUAL | Verdict, grouped per item, with a per-doc Roll-up stating the IMPL-blocker count"
  - "Discretion grep-facts (KEEP-04/05/POOL-05) resolved with explicit yes/no | existing/new | verbatim-match verdicts, not prose hedges"

requirements-completed: [BATCH-01]

# Metrics
duration: 10min
completed: 2026-05-25
---

# Phase 325 Plan 01: PFIX/RFALL/KEEP/POOL/BTOMB/HERO Call-Graph Attestation Summary

**Grep-attested all 38 cited file:line anchors across the six v48.0 plan docs (items 1-6) against the v47.0-closure baseline da5c9d50 into three 325-ATTEST docs — 0 IMPL blockers, and resolved KEEP-04/KEEP-05/POOL-05 + a KEEP-03 wiring-site correction.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-25T17:35Z (phase execution start)
- **Completed:** 2026-05-25T17:44Z
- **Tasks:** 3
- **Files modified:** 3 created (paper-only, zero contracts/*.sol)

## Accomplishments
- **PFIX (item 1):** 7 anchors, all MATCH — the F-47-01 1-line fix target verified (`/(1_000 * 1 ether)` divisor @ `DegenerusGameLootboxModule.sol:720` + the `poolStart/100` derivation comment @ :716-719); the closing-box `transferFromPool` sweep (:686) and its clamp-to-live-balance (StakedDegenerusStonk.sol:481-483) confirmed.
- **RFALL (item 2):** 6 anchors, all MATCH — the F-47-02 gap **confirmed present**: `pullRedemptionReserve` (`DegenerusGame.sol:1888-1899`) is a CHECKED `claimableWinnings[SDGNRS]`-only debit with NO stETH/ETH fallback; the 4-term submit base (:847), the 175% maxIncrement pull (:880-887), and the two existing stETH-transfer claim paths (:622/:932) all verified.
- **KEEP (item 3):** 6 anchors, all MATCH + a wiring-site correction; KEEP-04/KEEP-05 resolved.
- **POOL (item 4):** 15 anchors, all MATCH; POOL-05 resolved verbatim.
- **BTOMB (item 5):** 7 anchors, 6 MATCH + path clarification; feasibility (1e36 « uint128 max) confirmed.
- **HERO (item 6):** 19 anchors, 17 MATCH + 2 immaterial SHIFTED; HERO-06 no-leak confirmed.

## Task Commits

Each task was committed atomically:

1. **Task 1: Attest PFIX + RFALL → 325-ATTEST-PFIX-RFALL.md** - `5d26ffb3` (docs)
2. **Task 2: Attest KEEP + POOL + resolve KEEP-04/05/POOL-05 → 325-ATTEST-KEEP-POOL.md** - `93b67281` (docs)
3. **Task 3: Attest BTOMB + HERO → 325-ATTEST-BTOMB-HERO.md** - `9f4a6097` (docs)

## Files Created/Modified
- `.planning/phases/325-.../325-ATTEST-PFIX-RFALL.md` - PFIX (LootboxModule) + RFALL (sStonk + DegenerusGame pullRedemptionReserve) anchor tables; F-47-01 fix target + F-47-02 gap attested.
- `.planning/phases/325-.../325-ATTEST-KEEP-POOL.md` - KEEP (rename targets + affiliate wiring) + POOL (AfKing withdraw/poolOf + sStonk/VAULT recovery surface) tables; KEEP-04/KEEP-05/POOL-05 resolved.
- `.planning/phases/325-.../325-ATTEST-BTOMB-HERO.md` - BTOMB (BurnieCoin vaultAllowance + GameOverModule hook) + HERO (DegeneretteModule scoring/payout/award/WWXRP + dailyHeroWagers no-leak) tables.

## Aggregate verdict roll-up (for Plan 03)

| Doc | Items | Anchors | MATCH | SHIFTED | ABSENT | Blockers |
|-----|-------|---------|-------|---------|--------|----------|
| 325-ATTEST-PFIX-RFALL | 1, 2 | 13 | 13 | 0 | 0 | 0 |
| 325-ATTEST-KEEP-POOL | 3, 4 | 21 | 21 | 0 | 0 | 0 |
| 325-ATTEST-BTOMB-HERO | 5, 6 | 26 | 24 | 2 | 0 | 0 |
| **Total** | **1-6** | **60** | **58** | **2** | **0** | **0** |

(The 2 SHIFTED are both immaterial HERO anchors: `HERO_BOOST_N4_PACKED` @ :343 within the :339-343 5-table block; `HERO_SCALE` declaration @ :345 vs the :331 NatSpec comment the plan cited.)

**Discretion-item resolutions for Plan 03:**
- **KEEP-04 = YES** — registered `owner==VAULT` code exists (`bytes32("DGNRS")`); no setup step. Caveat: codes are cross-named (`"DGNRS"`→VAULT, `"VAULT"`→SDGNRS); recommend wiring `bytes32("DGNRS")` at `DegenerusGame.sol:1778`.
- **KEEP-05 = EXISTING** — `autoOpen` renames `crankBoxes`/`_crankOpenBox`.
- **POOL-05 = VERBATIM MATCH** — `withdraw(uint256)` + `poolOf(address) returns (uint256)` match `AfKing.sol`; AfKing unchanged for item 4.

## Decisions Made
See `key-decisions` frontmatter. The substantive grep-derived resolutions (not user decisions, per the CONTEXT Claude's-Discretion list) are KEEP-04 (YES), KEEP-05 (EXISTING), POOL-05 (VERBATIM MATCH), the KEEP-03 wiring-site correction (DegenerusGame.sol:1778), the BTOMB path clarification (reuse `vaultEscrow`), and the HERO-06 no-leak confirmation.

## Deviations from Plan

None - plan executed exactly as written. (This is a paper-only attestation plan; the only adjustments are within-attestation findings — the KEEP-03 wiring-site correction and the BTOMB path clarification — which are the intended OUTPUT of grep-attestation, not deviations from the plan's instructions.)

## Issues Encountered
- **Anchor cross-naming nuance (KEEP-04):** the two affiliate constants are cross-named (`AFFILIATE_CODE_DGNRS`=`"DGNRS"` is owned by VAULT; `AFFILIATE_CODE_VAULT`=`"VAULT"` is owned by SDGNRS). Resolved by recording the exact owner mapping and recommending the VAULT-owned literal (`bytes32("DGNRS")`) for the KEEP-03 wiring, flagged for Plan 03 to disambiguate.
- **AfKing affiliate-code site (KEEP-03):** `AfKing.batchPurchase` carries no affiliate argument at all; the `bytes32(0)` is in the game's `_batchPurchaseUnit` self-call wrapper (`DegenerusGame.sol:1778`). Recorded as a wiring-site correction so Plan 03/IMPL targets the right line.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Plan 02 (SWAP item 7 attestation)** and **Plan 03 (shared-surface reconciliation + 325-SPEC.md)** can proceed: items 1-6 anchors are grep-verified with 0 blockers.
- Plan 03 shared-surface coordination points surfaced: `DegenerusGame.sol` is co-edited by item 2 (`pullRedemptionReserve` ETH-vs-stETH branch), item 3 (renamed crank entrypoints + the `:1778` affiliate wiring), and item 7 (SWAP); `StakedDegenerusStonk.sol` by item 2 (`_submitGamblingClaimFrom`) + item 4 (`receive()` relax + `burnAtGameOver` pool-recover); `DegenerusVault.sol` by item 3 (affiliate pass-through) + item 4 (`recoverAfKingPool()`); the GameOverModule `burnAtGameOver` (:142) hook is shared by item 4 (POOL recover) + item 5 (BTOMB flood) — edit-order is a Plan 03 concern.
- ZERO contracts/*.sol mutation maintained (`git diff --name-only da5c9d50 HEAD -- contracts/` empty).

## Self-Check: PASSED

- Created files verified present: 325-ATTEST-PFIX-RFALL.md, 325-ATTEST-KEEP-POOL.md, 325-ATTEST-BTOMB-HERO.md, 325-01-SUMMARY.md.
- Task commits verified in git log: 5d26ffb3, 93b67281, 9f4a6097.
- Zero contracts/*.sol mutation confirmed (`git diff --name-only da5c9d50 HEAD -- contracts/` empty).

---
*Phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon*
*Completed: 2026-05-25*
