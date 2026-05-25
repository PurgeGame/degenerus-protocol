# Roadmap: v48.0 — sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle

**Milestone:** v48.0 — 🚧 **IN PROGRESS** (started 2026-05-25)
**Defined:** 2026-05-25
**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Audit baseline → subject:** v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. Subject = the single batched USER-APPROVED contract diff reconciling the seven work items (scope source: the 7 plan docs — `PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` · `PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` · `PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` · `PLAN-V48-AFKING-POOL-RECOVERY.md` · `PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md` · `PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md` · `PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md`).
**Scope source:** `.planning/REQUIREMENTS.md` (40 v48.0 REQ-IDs across 8 categories) + the 7 plan docs. All 7 designs LOCKED; **open items are SPEC-time attestations/calibrations only — no research.**

> **Cross-cutting rule (every requirement):** every cited `file:line` + the salvage-swap economics MUST be re-attested against the **v47.0-closure HEAD** before any patch (no "by construction" survives un-checked; the `DegenerusGame` mint/jackpot inline-duplication precedent). Security floor over gas. RNG/VRF-freeze invariant untouched. Pre-launch redeploy-fresh (storage-layout break fine, no migration).

> **Posture:** **ONE batched USER-APPROVED `contracts/*.sol` diff** for the whole milestone — the shared surfaces `DegenerusGame.sol` (items 2/3/7), `StakedDegenerusStonk.sol` (items 2/4), and `DegenerusVault.sol` (items 3/4/7) are each touched by multiple items, so they CANNOT be independent diffs; the milestone has a single contract IMPL phase with a HARD STOP at the contract-commit boundary (the diff is applied + locally compiled/tested but never committed without explicit user hand-review). Items 1 (`LootboxModule`), 5 (`BurnieCoin`/`GameOverModule`), 6 (`DegeneretteModule`) are comparatively isolated; the keeper rename (item 3) is a wide mechanical diff that crosses the in-game crank entrypoints. Tests + planning + docs AGENT-committable. `ContractAddresses.sol` freely modifiable.

> **Phase numbering** continues from the previous milestone — v47.0 ended at Phase 324, so **v48.0 starts at Phase 325.** Not reset to 1.

> **Milestone shape** matches the established v44/v45/v46/v47 audit-milestone pattern: **SPEC design-lock → single batched IMPL contract diff → TST proof → TERMINAL delta-audit + closure flip.**

---

## Phases

- [ ] **Phase 325: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation** - Settle the final shared signatures across `DegenerusGame`/`StakedDegenerusStonk`/`DegenerusVault`, grep-attest every cited file:line vs the v47.0-closure HEAD, and resolve every SPEC-time open item (RFALL-04 accounting shape, KEEP-04/05 VAULT-code + autoOpen scope, POOL-06 re-stranding, BTOMB packing, HERO-04 shape+packing, SWAP-03 jitter source, SWAP-08 acquisition-floor re-confirm) before any patch.
- [ ] **Phase 326: IMPL — The ONE Batched Contract Diff (all 7 items)** - Apply all seven work items' contract edits as a single reconciled diff; HARD STOP at the contract-commit boundary (applied + locally compiled/tested, never committed without explicit user hand-review).
- [ ] **Phase 327: TST — Repro/Same-Results + No-Arb + EV + Regression Proofs** - Prove the presale-drain dust bound (PFIX-02/03), the redemption-fallback regression (RFALL-05), the sDGNRS `receive()` accounting-safety (POOL-04), the BURNIE tombstone non-circulating signal (BTOMB-03), the byte-identical Degenerette recalibration (HERO-04/06), and the salvage-swap no-arb at the jitter band CEILING + solvency (SWAP-08/09).
- [ ] **Phase 328: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure** - NON-WIDENING delta-audit vs the v47.0 baseline, run the 3-skill genuine-PARALLEL adversarial sweep, author `audit/FINDINGS-v48.0.md`, and flip the closure signal `MILESTONE_V48_AT_HEAD_<sha>`.

---

## Phase Details

### Phase 325: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation
**Goal**: Every shared contract surface has a single settled signature, every cited `file:line` is grep-verified against the v47.0-closure HEAD, and every SPEC-time open item is resolved on paper — so the IMPL phase applies a fully reconciled diff with zero "by construction" assumptions, and the load-bearing salvage-swap economics (no-arb margin) are confirmed before any code is written.
**Depends on**: Nothing (first v48.0 phase; consumes the v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` as the frozen audit baseline)
**Requirements**: BATCH-01, RFALL-04, KEEP-04, KEEP-05, POOL-06
**Success Criteria** (what must be TRUE):
  1. The final shared signatures are settled in writing for every multi-item file — `DegenerusGame.sol` (item 2 `pullRedemptionReserve` coverage branch + item 3 renamed crank entrypoints + item 7 `sellFarFutureTickets` + inline `claimableWinnings[SDGNRS]` debit), `StakedDegenerusStonk.sol` (item 2 `_submitGamblingClaimFrom` `maxIncrement` pull + item 4 `receive()` relaxation + `burnAtGameOver` pool-recovery + the `IAfKing` `withdraw`/`poolOf` interface adds), and `DegenerusVault.sol` (item 3 `affiliateCode` pass-through + item 4 `recoverAfKingPool()` + item 7 `gameSellFarFutureTickets onlyVaultOwner`) — so none of items 2/3/4/7 can land as an independent diff that breaks another.
  2. Every cited `file:line` across all 7 plan docs is grep-verified against the v47.0-closure HEAD and any drift is corrected in the SPEC (no "by construction" / "single fn reaches all paths" claim survives un-checked; the `DegenerusGame` mint/jackpot inline-duplication precedent re-checked; `POOL-05` confirms the `IAfKing`/`IAfKingSubscribe` `withdraw(uint256)` + `poolOf(address)` interface adds match `AfKing.sol`'s signatures verbatim and that `AfKing.sol` itself stays UNCHANGED).
  3. The load-bearing salvage-swap no-arb floor is RE-CONFIRMED at the v47.0-closure HEAD (SWAP-08 attestation): the cheapest far-future-entry acquisition cost (~21%, lootbox tier-1) is re-derived from current source, the jitter band CEILING max full payout (`110% × fractionBps(6) = 16.5% of face` @d6) is confirmed below it (margin ~4.5pp), BURNIE is confirmed unable to mint a far-future entry (`purchaseCoin` has no level arg; v47 removed the BURNIE-lootbox→future path), and the SWAP-03 jitter source is pinned to an already-SETTLED past VRF word (freeze-safe per `v45-vrf-freeze-invariant`) — so the swap is provably -EV at the band a grinder/waiter captures, not just at the mean.
  4. Every SPEC-time open item is resolved and recorded: RFALL-04 (`pendingRedemptionEthValue` single-value vs split ETH/stETH reservation shape, applied consistently across submit/claim/gameOver); KEEP-04 (VAULT confirmed to hold a registered affiliate code with `owner == VAULT` distinct from its address-derived default, or a setup step to register one); KEEP-05 (whether `autoOpen` is an existing keeper capability or new, scoped accordingly); POOL-06 (post-gameOver `depositFor(SDGNRS)` re-stranding — second sweep in `handleFinalSweep` vs accept-as-minor); the BTOMB `vaultAllowance` checked-add/cap + one-shot packing; the HERO-04 payout SHAPE over `S∈{0..9}` + the S=8/S=9 (>32-bit) packing scheme.
  5. The salvage-swap `ticketQueue` swap-pop is proven on paper NOT to reproduce the `H-CANCEL-SWAP-MISS` operation class (SWAP-06 design lock): every `ticketQueue` / `_tqFarFutureKey` consumer is enumerated, the O(1) caller-verified swap-pop (`q[idx]==player`, `queueIndices` used only when a line zeroes a level) is shown to MAINTAIN `membership ⟺ packed != 0` so the far-future jackpot samplers need no change and gain no hot-path read, and the LOCKED OPEN-E operator-trust disposition is confirmed to cover this first value-destructive operator-gated action.
**Plans**: 3 plans (2 waves)
- [x] 325-01-PLAN.md — Call-graph attestation for items 1/2/3/4/5/6 -> three 325-ATTEST-*.md grep tables (PFIX-RFALL, KEEP-POOL, BTOMB-HERO) + resolve KEEP-04/KEEP-05/POOL-05 (Wave 1)
- [ ] 325-02-PLAN.md — Load-bearing SWAP attestation: SWAP-08 no-arb re-derivation at the band ceiling (STOP-if-violated) + SWAP-03 jitter-source pin + SWAP-06 swap-pop enumeration -> 325-ATTEST-SWAP.md (Wave 1)
- [ ] 325-03-PLAN.md — 325-SPEC.md: shared-signature reconciliation across DegenerusGame/StakedDegenerusStonk/DegenerusVault + open-item resolutions (RFALL-04, KEEP-04/05, POOL-06, BTOMB/HERO packing+shape) + per-item IMPL blueprint + edit-order map (Wave 2)
**UI hint**: no

### Phase 326: IMPL — The ONE Batched Contract Diff (all 7 items)
**Goal**: All seven work items land as a single reconciled `contracts/*.sol` diff — the presale-box DGNRS drain is fixed (divisor 1_000→400), the redemption ETH-empty stETH fallback is segregated fail-closed + donation-robust, the keeper functions are renamed (autoBuy/autoOpen/autoResolve) and pass VAULT's registered affiliate code, the AfKing prepaid pools are recoverable, the gameover BURNIE tombstone floods the virtual VAULT allowance one-shot, the Degenerette hero becomes a 2-point scoring element with the standalone multiplier removed, and the sDGNRS far-future salvage swap ships -EV-by-design — applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
**Depends on**: Phase 325 (the SPEC must settle the shared-surface signatures + resolve every open item first)
**Requirements**: PFIX-01, RFALL-01, RFALL-02, RFALL-03, KEEP-01, KEEP-02, KEEP-03, POOL-01, POOL-02, POOL-03, POOL-05, BTOMB-01, BTOMB-02, HERO-01, HERO-02, HERO-03, HERO-05, SWAP-01, SWAP-02, SWAP-03, SWAP-04, SWAP-05, SWAP-06, SWAP-07, BATCH-02
**Success Criteria** (what must be TRUE):
  1. F-47-01 is fixed (PFIX-01) — `_presaleBoxDgnrsReward`'s divisor moves `1_000 → 400` (base `poolStart/100 → poolStart/40`) in `DegenerusGameLootboxModule.sol` with the inline `base` derivation comment updated, the tier shape preserved (tier-1 still 3× tier-5 DGNRS-per-ETH; only absolute scale moves), and the `transferFromPool` clamp held — an ISOLATED edit touching no other item's surface.
  2. F-47-02 is fixed (RFALL-01/02/03) — the 175% redemption reservation segregates from pure-ETH OR pure-stETH (no mix), falls back to pure-stETH when ETH can't cover, and REVERTS fail-closed if neither pure leg covers (`StakedDegenerusStonk.sol` `_submitGamblingClaimFrom` `maxIncrement` pull + `DegenerusGame.sol` `pullRedemptionReserve` coverage branch); coverage is checked against the SAME asset basis the base is inflated by (donation-robust — a stETH donation / `selfdestruct` force-feed cannot brick submit); claim-time payout asset selection matches the reserved asset (stETH-reserved → stETH-paid), extending the v47 game-over ETH→stETH fallback (REDEEM-04) to the mid-game ETH-depletion case.
  3. The keeper surface is renamed + affiliate-wired (KEEP-01/02/03) — `AfKing.sol`'s `sweep` + the in-game mass-resolve/open crank entrypoints become `autoBuy` / `autoOpen` / `autoResolve` ("crank"/"do-work"/"sweep" purged from code AND comments), the v46 `creditFlip` minted-flip-credit bounty is KEPT (gas-pegged `BOUNTY_ETH_TARGET`, no funding-pool overlay), and AfKing passes VAULT's registered (immutable) affiliate code into `game.purchase(...)` on every tx (was `0`) so unreferred AfKing-joiners are permanently captured by VAULT (foreclosure intended) while players holding a real human affiliate keep it.
  4. The AfKing prepaid pools are recoverable (POOL-01/02/03/05) — VAULT gets a permissionless `recoverAfKingPool()` → `afKing.withdraw(afKing.poolOf(address(this)))` (recovered ETH to VAULT reserves via its open `receive()`, no gameOver gate); sDGNRS `receive()` is relaxed to accept `AF_KING` in addition to `GAME`; sDGNRS auto-recovers its pool inside `burnAtGameOver()` placed BEFORE the `balanceOf(this)==0` early-return (no standalone sDGNRS withdraw); `AfKing.sol` itself stays UNCHANGED with the `IAfKing`/`IAfKingSubscribe` `withdraw(uint256)`/`poolOf(address)` interface adds matching its signatures verbatim.
  5. The gameover BURNIE tombstone + the Degenerette hero rescale land (BTOMB-01/02, HERO-01/02/03/05) — `gameOver()` one-shot bumps BURNIE's virtual VAULT mint allowance (`_supply.vaultAllowance`) by 1e36 wei via the existing GAME-gated escrow/allowance path with a checked add/cap (no `uint128` overflow, strictly one-shot); Degenerette scoring becomes `S = A + 2·H` (max 9, pay floor `S ≥ 2`) with `_countMatches` → `_score(...) ∈ {0..9}`, the standalone EV-neutral hero multiplier removed (`_applyHeroMultiplier` / `HERO_BOOST_*` / `HERO_PENALTY` / `HERO_SCALE` + the `M<2`/`M=8` carve-out deleted; `heroQuadrant >= 4` revert + `FT_HERO_SHIFT` decode kept), per-N tables recalibrated to `basePayoutEV = 100 centi-x` across 10 buckets (RTP unchanged), and the jackpot preserved exactly (`S=9 ≡ old M=8` relabel; `_awardDegeneretteDgnrs` thresholds re-mapped).
  6. The sDGNRS far-future salvage swap ships (SWAP-01/02/03/04/05/06/07) — the new `sellFarFutureTickets(...)` game entrypoint (`_resolvePlayer` operator-honor, `rngLocked`-gated, mass-sell → ONE aggregated current-level ticket mint + ONE cash credit) values each line by `d = L - currentLevel` (require `6 ≤ d ≤ 100`) at `priceForLevel(targetLevel)` with the two-line `fractionBps(d)` curve (15%@d6→5%@d100) and the daily per-player jitter (fraction ×∈[70%,110%], cash share ∈[20%,60%]) seeded from the SETTLED past VRF word; ticket floor first (always ≥1 whole current-level ticket, revert if `totalBudget < oneTicketWei`); funded fail-closed from `claimableWinnings[SDGNRS]` down to a ≥1 ETH floor (NO `pendingRedemptionEthValue` term, NO daily cap, debited INLINE); the fully-liquidated seller removed from `ticketQueue` via the O(1) caller-verified swap-pop maintaining `membership ⟺ packed != 0`; and the VAULT `gameSellFarFutureTickets onlyVaultOwner` wrapper added (drone reaches via existing operator-approval; satellite `DroneManager` v47-interface re-sync folded in).
  7. The diff is reconciled per the SPEC's settled shared signatures and is HELD at the contract-commit boundary (BATCH-02) — applied to `contracts/` and locally compiling/tested (`ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`).
**Plans**: TBD (single contract IMPL phase; plans serialize on the shared `.sol` files — items 2/3/7 on `DegenerusGame`, 2/4 on `StakedDegenerusStonk`, 3/4/7 on `DegenerusVault` — with items 1/5/6 comparatively isolated; the final wave is the single autonomous:false USER-APPROVAL gate for the ONE batched diff)
**UI hint**: no

### Phase 327: TST — Repro/Same-Results + No-Arb + EV + Regression Proofs
**Goal**: The IMPL diff is proven correct empirically — the presale-box drain now mops up only variance dust (not ~60% of the pool), the redemption fallback preserves the v47 REDEEM-08 invariants under stETH coverage, the sDGNRS `receive()` relaxation is accounting-safe, the BURNIE tombstone signals only in uncirculated supply, the Degenerette recalibration is byte-identical from `derive_5_tables.py`, and the load-bearing salvage-swap no-arb holds at the jitter band CEILING with solvency preserved — restoring a clean v48.0 regression baseline.
**Depends on**: Phase 326 (tests run against the applied contract diff)
**Requirements**: PFIX-02, PFIX-03, RFALL-05, POOL-04, BTOMB-03, HERO-04, HERO-06, SWAP-08, SWAP-09
**Success Criteria** (what must be TRUE):
  1. The presale-drain dust bound is proven (PFIX-02/03) — over a realistic 50-ETH presale (random 50/40/10 outcomes across many boxes) the closing-box sweep transfers only variance dust (≤ a small bound, NOT ~60% of the pool) and the pool ends ~empty; the tier shape is preserved (tier-1 still 3× tier-5 DGNRS-per-ETH); and a run of early DGNRS hits empties the pool before close via the `transferFromPool` clamp → closing sweep ≈ 0, no revert / no over-draw.
  2. The redemption-fallback regression holds (RFALL-05) + the sDGNRS `receive()` relaxation is accounting-safe (POOL-04) — the v47 REDEEM-08 invariants still hold under the stETH fallback (two same-period claimants, BURNIE-can't-block-ETH, value conservation, `balance ≥ pending`); and reserves are read by `address(this).balance` (not a running counter incremented in `receive()`), so an `AF_KING`-sourced credit is not mis-attributed / double-counted / bypassed.
  3. The BURNIE tombstone signal is proven non-circulating (BTOMB-03) — the 1e36-wei flood does NOT touch `totalSupply()`, lands only in `vaultMintAllowance()` / `supplyIncUncirculated()` / `balanceOf(VAULT)`, and the DGVB pro-rata BURNIE-claim math does not overflow when claiming a share of a 1e36 allowance.
  4. The Degenerette recalibration is byte-identical (HERO-04 byte-reproduce gate + HERO-06) — every per-N payout constant across the 10 buckets `S=0..9` is reproduced byte-identical from `derive_5_tables.py` (Phase-267-style PASS_ALL gate, NOT hand-typed), the chosen payout SHAPE + WWXRP-bonus/sDGNRS/"high tier" thresholds re-map onto the 10-point scale, the S=8/S=9 (>32-bit) packing is verified, the recalibration stays write-batch byte-identical to v47's `resolveBets` (DGAS), and the `dailyHeroWagers`/`_rollHeroSymbol` daily-hero-symbol jackpot is verified unaffected (no `matches`-range leakage).
  5. The load-bearing salvage-swap no-arb + solvency hold (SWAP-08/09) — the no-arb inequality is PROVEN at the jitter band CEILING (max full payout `110% × fractionBps(6) = 16.5% of face` @d6 < cheapest far-entry acquisition ~21%, margin ~4.5pp; base `fractionBps` keeps ≥~10% margin below the far ticket's present EV so a 110%-day pawn doesn't overpay sDGNRS); BURNIE-can't-mint-a-far-entry is confirmed; and solvency is safe (`claimablePool ≤ ETH + stETH` never violated — ticket leg adds pool slack, cash leg is a claimant-to-claimant relabel; array length bounded ≤32).
**Plans**: TBD
**UI hint**: no

### Phase 328: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure
**Goal**: The v48.0 audit subject (the single batched diff) is delta-audited NON-WIDENING against the v47.0 baseline, swept by the 3-skill genuine-PARALLEL adversarial pass for new findings, consolidated into `audit/FINDINGS-v48.0.md`, and the milestone is closed with the `MILESTONE_V48_AT_HEAD_<sha>` signal and the atomic ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flip — re-attesting all 40 requirements.
**Depends on**: Phase 327 (the audit subject must be implemented + test-proven before the terminal delta-audit + sweep)
**Requirements**: BATCH-03
**Success Criteria** (what must be TRUE):
  1. The delta audit is NON-WIDENING — every `contracts`/`test` diff vs the v47.0-closure baseline `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` is attributable to a v48-scope item across all 7 surfaces (presale-drain fix, redemption stETH-fallback, keeper rename + VAULT-code, AfKing pool recovery, gameover BURNIE tombstone, Degenerette hero rescale, sDGNRS far-future salvage swap), with each surface attested non-widening relative to the baseline and the two v47-deferred findings (F-47-01, F-47-02) recorded RESOLVED-AT-V48.
  2. The 3-skill genuine-PARALLEL adversarial sweep runs (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per the carried decision) charged against the 7 surfaces + composition — the salvage-swap no-arb at the band ceiling / grinder-waiter timing / swap-pop H-CANCEL-SWAP-MISS regression / redemption-desk structural protection, the redemption stETH-fallback donation-robustness, the presale-drain dust bound, the keeper foreclosure + minted-credit faucet, the AfKing pool-recovery accounting, the BURNIE-tombstone overflow, and the Degenerette byte-identical RTP — with every elevation passed through the skeptic filter (structural-protection + 3-condition EV lens) before being recorded.
  3. `audit/FINDINGS-v48.0.md` is authored at the v48.0 closure HEAD (mirrors the v44/v46/v47 9-section pattern, chmod 444) folding in the F-47-01 + F-47-02 resolution dispositions and any newly-surfaced findings (adjudicated or deferred per user direction).
  4. The `MILESTONE_V48_AT_HEAD_<sha>` closure signal is emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied with all 40 requirements re-attested at closure.
**Plans**: TBD
**UI hint**: no

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 325. SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation | 1/3 | In Progress|  |
| 326. IMPL — The ONE Batched Contract Diff (all 7 items) | 0/TBD | Not started | - |
| 327. TST — Repro/Same-Results + No-Arb + EV + Regression Proofs | 0/TBD | Not started | - |
| 328. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 0/TBD | Not started | - |

---

## Coverage

**40/40 v48.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 325 SPEC | BATCH-01, RFALL-04, KEEP-04, KEEP-05, POOL-06 | 5 |
| 326 IMPL | PFIX-01, RFALL-01/02/03, KEEP-01/02/03, POOL-01/02/03/05, BTOMB-01/02, HERO-01/02/03/05, SWAP-01/02/03/04/05/06/07, BATCH-02 | 25 |
| 327 TST | PFIX-02/03, RFALL-05, POOL-04, BTOMB-03, HERO-04/06, SWAP-08/09 | 9 |
| 328 TERMINAL | BATCH-03 | 1 |
| **Total** | | **40** |

**Per-category split (verification):**

| Category | Total | SPEC | IMPL | TST | TERMINAL |
|----------|-------|------|------|-----|----------|
| PFIX | 3 | — | 1 (01) | 2 (02–03) | — |
| RFALL | 5 | 1 (04) | 3 (01–03) | 1 (05) | — |
| KEEP | 5 | 2 (04–05) | 3 (01–03) | — | — |
| POOL | 6 | 1 (06) | 4 (01,02,03,05) | 1 (04) | — |
| BTOMB | 3 | — | 2 (01–02) | 1 (03) | — |
| HERO | 6 | — | 4 (01,02,03,05) | 2 (04,06) | — |
| SWAP | 9 | — | 7 (01–07) | 2 (08–09) | — |
| BATCH | 3 | 1 (01) | 1 (02) | — | 1 (03) |
| **Total** | **40** | **5** | **25** | **9** | **1** |

**Center-of-gravity rationale (where a requirement spans design+impl+test):**
- **RFALL-04** (accounting-shape decision) → SPEC; the implementation lands under RFALL-01/02/03 (IMPL).
- **KEEP-04** (VAULT registered-code prerequisite) + **KEEP-05** (autoOpen-capability scoping) → SPEC; the rename/affiliate-wiring code lands under KEEP-01/02/03 (IMPL).
- **POOL-06** (post-gameOver re-stranding decision) → SPEC; the recovery code lands under POOL-01/02/03/05 (IMPL); the `receive()` accounting-safety proof is POOL-04 (TST).
- **HERO-04** owns the byte-reproduce gate (empirical `derive_5_tables.py` PASS_ALL) → TST; the SPEC-time shape+packing choice is folded into BATCH-01's open-item resolution; the table values land under HERO-03 (IMPL).
- **SWAP-08** owns the no-arb proof at the band ceiling → TST; the floor RE-CONFIRMATION attestation is folded into BATCH-01 (SPEC) and the swap economics land under SWAP-02/03 (IMPL).
- **BATCH-01** (the single SPEC design-lock) absorbs the remaining SPEC-time open-item resolutions (BTOMB packing, HERO-04 shape+packing, SWAP-03 jitter source + SWAP-08 acquisition-floor re-confirm) without duplicating the requirements those decisions feed.

✓ All 40 v48.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

---
*Roadmap created: 2026-05-25*
