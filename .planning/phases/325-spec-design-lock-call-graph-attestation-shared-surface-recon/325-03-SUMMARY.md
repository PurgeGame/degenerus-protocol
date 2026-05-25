---
phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
plan: 03
subsystem: audit
tags: [spec-design-lock, shared-signature-reconciliation, v48, attestation-rollup, edit-order-map]

# Dependency graph
requires:
  - phase: 325-01
    provides: items 1-6 call-graph attestation (3 ATTEST docs, 0 IMPL blockers) + KEEP-04/05 + POOL-05 resolutions
  - phase: 325-02
    provides: SWAP item-7 attestation (no-arb floor HOLDS +4.5pp @d6, STOP NOT triggered; jitter pin; swap-pop enumeration)
provides:
  - "325-SPEC.md — the reconciled v48.0 design-lock blueprint (the v47 321-SPEC.md analog)"
  - "Section 0: attestation verdict roll-up (0 blockers, carried corrections C1-C8, SWAP no-arb verdict, discretion-item resolutions)"
  - "Section 1: Shared Signatures R1-R6 — one settled signature + apply-order per multi-item construct so items 2/3/4/7 cannot land as conflicting diffs"
  - "Section 2: open-item resolutions (RFALL-04 D-06, KEEP-04, KEEP-05, POOL-06 D-04, BTOMB packing, HERO-04 shape D-01/02/03, S=8/S=9 packing)"
  - "Section 3: per-item IMPL blueprint + file/edit-order map (the load-bearing input to Phase 326)"
affects: [326-impl (the single batched contract diff), 327-tst, 328-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared-signature reconciliation R-rows (one settled signature + apply-order per shared construct) mirroring v47 321-SPEC R1..R7"
    - "Section-0 carried-corrections (C1..Cn) folding Wave-1 attestation drift into override-the-plan-prose notes"
    - "Open-item resolution subsections recording decision + source (D-NN / grep verdict) + IMPL instruction"

key-files:
  created:
    - .planning/phases/325-spec-design-lock-call-graph-attestation-shared-surface-recon/325-SPEC.md
  modified: []

key-decisions:
  - "R1-R5 settle one signature per shared construct with explicit apply-order: DegenerusGame.sol R1(pullRedemptionReserve coverage)->R2(crank rename+affiliate bytes32 DGNRS)->R3(sellFarFutureTickets+inline claimableWinnings[SDGNRS] debit); sStonk R4(receive AF_KING relax + burnAtGameOver pool-recover + _submitGamblingClaimFrom segregation + interface adds); DegenerusVault R5(recoverAfKingPool + gameSellFarFutureTickets wrapper + interface entry)"
  - "RFALL-04 = D-06 single pendingRedemptionEthValue (pure-ETH OR pure-stETH, no separate stETH slot; donation-robust; fail-closed revert-if-neither)"
  - "KEEP-04 = wire bytes32(\"DGNRS\") (AFFILIATE_CODE_DGNRS, owner==VAULT) at DegenerusGame.sol:1778; cross-naming disambiguated (NOT bytes32(\"VAULT\") which is owner SDGNRS)"
  - "KEEP-05 = autoOpen is a RENAME of crankBoxes/_crankOpenBox (existing capability)"
  - "POOL-06 = D-04 accept-as-minor, NO second sweep in handleFinalSweep; donor-only post-gameOver residual documented; VAULT unaffected (anytime recoverAfKingPool)"
  - "BTOMB = reuse vaultEscrow (BurnieCoin.sol:557-567) with explicit checked-add/cap (its += is unchecked), one-shot from gameover-drain; 1e36 « uint128 max"
  - "HERO-04 = D-01 continuity (S=3..9 track M=2..8) + D-02 S=2 ~40-60% partial refund + D-03 thresholds S>=7; SHAPE locked here, byte-exact constants handed to derive_5_tables.py PASS_ALL gate at Phase 327; S=8/S=9 held as separate per-N uint256"
  - "0-8->0-9 FullTicketResult.matches widening FLAGGED as frontend/indexer out-of-scope (flag, not fix)"

patterns-established:
  - "v48 SPEC mirrors v47 321-SPEC: section 0 attestation+corrections / section 1 R-reconciliation / section 2 open-item resolutions / section 3 blueprint+edit-order map + SC checklist"

requirements-completed: [BATCH-01, RFALL-04, KEEP-04, KEEP-05, POOL-06]

# Metrics
duration: ~5min
completed: 2026-05-25
---

# Phase 325 Plan 03: 325-SPEC.md Shared-Surface Reconciliation Summary

**Authored `325-SPEC.md` — the reconciled v48.0 design-lock blueprint — folding the four Wave-1 ATTEST docs into a section-0 verdict roll-up (0 IMPL blockers, corrections C1-C8, SWAP no-arb HOLDS +4.5pp @d6), settling R1-R6 shared signatures with explicit apply-order so items 2/3/4/7 cannot land as conflicting diffs, resolving every SPEC-time open item (RFALL-04/KEEP-04/KEEP-05/POOL-06/BTOMB/HERO-04/S8-S9), and producing the per-item IMPL blueprint + file/edit-order map for Phase 326 — zero `contracts/*.sol` mutation.**

## Performance
- **Duration:** ~5 min (after the ~load of 4 ATTEST + 2 SUMMARY + 7 plan docs)
- **Started:** 2026-05-25T17:58Z
- **Completed:** 2026-05-25
- **Tasks:** 2
- **Files modified:** 1 created (paper-only, zero `contracts/*.sol`)

## 325-SPEC.md sections

- **Section 0 — Attestation verdict (BATCH-01, Wave-1 roll-up):** 0 IMPL blockers across all 7 items (60 anchors + SWAP economics: 58 MATCH / 2 immaterial SHIFTED / 0 ABSENT). Eight carried corrections (C1 PFIX exact :720 divisor; C2 KEEP-03 wiring-site = `DegenerusGame.sol:1778`; C3 RFALL gap confirmed present; C4 BTOMB reuse `vaultEscrow`; C5 HERO immaterial SHIFTED :343/:345; C6 HERO-06 no-leak; C7 SWAP `_runEarlyBirdLootboxJackpot` @ JackpotModule:639; C8 SWAP §12 recompute). SWAP no-arb verdict folded (HOLDS +4.5pp @d6, STOP NOT triggered). KEEP-04 (YES, `bytes32("DGNRS")`), KEEP-05 (EXISTING rename), POOL-05 (verbatim match) resolutions.
- **Section 1 — Shared Signatures (R1-R6):** one settled signature + apply-order each. R1 `pullRedemptionReserve` coverage branch (D-06). R2 crank-entrypoint rename (`sweep`→`autoBuy`, `crankBets`→`autoResolve`, `crankBoxes`→`autoOpen`, helpers) + `bytes32(0)`→`bytes32("DGNRS")` at :1778. R3 `sellFarFutureTickets` + inline `claimableWinnings[SDGNRS]` debit + `_removeFarFutureTickets` swap-pop. R4 sStonk joint (`receive()` AF_KING relax + `burnAtGameOver` pool-recover + `_submitGamblingClaimFrom` segregation + interface adds). R5 DegenerusVault joint (`recoverAfKingPool()` + `gameSellFarFutureTickets` wrapper + interface entry). R6 cross-repo `DroneManager` flag + OPEN-E disposition confirmed for the first value-destructive operator action.
- **Section 2 — Open-item resolutions:** RFALL-04 (D-06 single value, donation-robust), KEEP-04 (`bytes32("DGNRS")` disambiguated), KEEP-05 (autoOpen rename), POOL-06 (D-04 accept-as-minor + documented donor-only residual), BTOMB packing (checked-add/cap, one-shot via `vaultEscrow`), HERO-04 shape (D-01/02/03 + byte-reproduce-gate TST handoff), S=8/S=9 packing (separate per-N `uint256`).
- **Section 3 — Per-item IMPL blueprint + edit-order map:** Files-in-the-diff list with the storage->interface->helpers->callers->entrypoints->wrappers order + the intra-file apply-order (DegenerusGame R1->R2->R3; sStonk interface->receive->submit->burnAtGameOver; Vault interfaces->wrappers) + the GameOverModule item-4/item-5 coordination note. One blueprint paragraph per item (1-7) referencing the R-rows. The 0-8->0-9 widening flagged frontend/indexer out-of-scope. SC1-SC5 checklist mapped 1:1 to ROADMAP Phase 325 + the SOURCE-TREE-not-mutated line.

## Settled shared signatures (recap)

| R | Construct | Co-editing items | Settled outcome |
|---|-----------|------------------|-----------------|
| R1 | `DegenerusGame.pullRedemptionReserve(uint256)` | 2 | ETH-vs-stETH coverage branch on the v47 SDGNRS-gated form; single `pendingRedemptionEthValue` (D-06) |
| R2 | `DegenerusGame` crank entrypoints + affiliate code | 3 | `sweep`→`autoBuy`/`crankBets`→`autoResolve`/`crankBoxes`→`autoOpen`; `bytes32(0)`→`bytes32("DGNRS")` @:1778 |
| R3 | `DegenerusGame.sellFarFutureTickets(address,uint32[],uint256[],uint256[])` | 7 | new entrypoint + inline `claimableWinnings[SDGNRS]` debit (≥1 ETH floor, no `pendingRedemptionEthValue` term, no daily cap) + `_removeFarFutureTickets` swap-pop |
| R4 | `StakedDegenerusStonk` (receive/burnAtGameOver/_submitGamblingClaimFrom/interface) | 2 + 4 | AF_KING `receive()` relax + pool-recover before `balanceOf(this)==0` early-return + maxIncrement segregation + `withdraw`/`poolOf` adds |
| R5 | `DegenerusVault` (recoverAfKingPool/gameSellFarFutureTickets/interface) | 3 + 4 + 7 | permissionless `recoverAfKingPool()` + `gameSellFarFutureTickets onlyVaultOwner` wrapper + `IDegenerusGamePlayerActions` entry + `withdraw`/`poolOf` adds |
| R6 | cross-repo `DroneManager` + OPEN-E | 7 | +1 typed `onlyChainOwner` pass-through (folds into v47 re-sync); OPEN-E confirmed to cover the value-destructive operator action |

## SC1..SC5 coverage (ROADMAP Phase 325)

- **SC1 (shared signatures settled):** R1-R5 each settle one signature + apply-order; none of items 2/3/4/7 can land as a conflicting independent diff. ✅
- **SC2 (every anchor grep-attested; no un-grepped "by construction"):** §0 — 60 anchors + SWAP attested vs `da5c9d50`, 0 blockers, C1-C8 captured; mint/jackpot inline-duplication precedent re-checked (C2); POOL-05 verbatim + AfKing unchanged for item 4. ✅
- **SC3 (no-arb floor re-confirmed at band ceiling):** §0 SWAP verdict — 16.5% @d6 < ~21% acquisition, +4.5pp; BURNIE-can't-mint-far; SWAP-03 pinned `rngWordByDay[currentDay-1]`. ✅
- **SC4 (every open item resolved):** §2 — RFALL-04/KEEP-04/KEEP-05/POOL-06/BTOMB/HERO-04/S8-S9 all resolved with decision+source+IMPL instruction. ✅
- **SC5 (swap-pop not H-CANCEL-SWAP-MISS + OPEN-E covers value-destructive action):** §0 + R3/R6 + §2 — 11 consumers enumerated, `membership ⟺ packed != 0` maintained, samplers gain no hot-path read, OPEN-E disposition confirmed. ✅

## Decisions Made
See `key-decisions` frontmatter. The user-locked decisions honored verbatim are D-01/02/03 (HERO shape), D-04 (POOL accept-as-minor), D-05 (SWAP no-arb floor re-derived, not widened), D-06 (single `pendingRedemptionEthValue`). The grep-derived discretion resolutions folded from Wave 1 are KEEP-04 (`bytes32("DGNRS")`), KEEP-05 (autoOpen rename), POOL-05 (verbatim), BTOMB (`vaultEscrow` + checked-add/cap), HERO-06 (no-leak), the S=8/S=9 separate-`uint256` packing, and the C1-C8 corrections.

## Deviations from Plan

None - plan executed exactly as written. The plan's two tasks (sections 0+1, then append 2+3) were both authored and committed atomically. The carried corrections C1-C8 are the intended OUTPUT of folding the Wave-1 attestation drift into the SPEC (not deviations) — including the two non-blocking citation corrections the Wave-1 docs surfaced for Plan 03 to fold in (C2 KEEP-03 wiring-site `DegenerusGame.sol:1778`; C7 `_runEarlyBirdLootboxJackpot` at `JackpotModule:639`).

## Issues Encountered
- **Affiliate-code cross-naming (KEEP-04):** the two custom codes are cross-named (`AFFILIATE_CODE_DGNRS`=`"DGNRS"`→owner VAULT; `AFFILIATE_CODE_VAULT`=`"VAULT"`→owner SDGNRS). Resolved in §2 by pinning the VAULT-owned literal `bytes32("DGNRS")` and explicitly warning against wiring `bytes32("VAULT")`.
- **SWAP §12 worked example on the wrong basis:** the plan-doc §12 uses a `/4`-per-ticket basis. Recorded as C8 (recompute on the true `oneTicketWei = priceForLevel(currentLevel)` whole-ticket basis) — a documentation recompute, not a contract issue; the §A no-arb arithmetic already uses the correct basis.

## User Setup Required
None - paper-only SPEC reconciliation, no external service configuration.

## Next Phase Readiness
- **Phase 326 (IMPL) ready to consume:** the single batched contract diff applies R1-R5 in the §3 edit-order map with zero "by construction" assumptions and zero shared-signature conflicts. HELD at the contract-commit boundary for explicit user hand-review (single batched diff, never committed without approval).
- **Phase 327 (TST) handoff captured:** the HERO byte-exact 10-bucket per-N constants (incl. S=8/S=9) are emitted by `derive_5_tables.py` under the Phase-267-style PASS_ALL byte-reproduce gate — never hand-typed at IMPL.
- ZERO `contracts/*.sol` mutation maintained (`git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` empty).

## Self-Check: PASSED

- Created files verified present: 325-SPEC.md, 325-03-SUMMARY.md.
- Task commits verified in git log: b6cc7825 (sections 0+1), 09d27524 (sections 2+3).
- Zero `contracts/*.sol` mutation confirmed (`git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` empty; working-tree `contracts/*.sol` empty).
- Task 1 + Task 2 automated verification gates: both PASS.

---
*Phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon*
*Completed: 2026-05-25*
