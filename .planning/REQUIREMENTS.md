# Requirements: Degenerus Protocol — v48.0 sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle

**Defined:** 2026-05-25
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Audit baseline → subject:** v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. Subject = the single batched contract diff reconciling the seven work items below.
**Scope source:** seven plan docs — `PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` (F-47-01) · `PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` (F-47-02) · `PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` · `PLAN-V48-AFKING-POOL-RECOVERY.md` · `PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md` · `PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md` · `PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md`. All 7 designs LOCKED; open items are SPEC-time attestations/calibrations only.
**Delivery shape:** ONE batched USER-APPROVED `contracts/*.sol` diff → TST → TERMINAL delta-audit + 3-skill adversarial sweep + closure flip (the v44–v47 pattern).

> **Cross-cutting rule (applies to every requirement):** every cited `file:line` + the salvage-swap economics MUST be re-attested against the **v47.0-closure HEAD** before any patch (no "by construction" survives un-checked; `DegenerusGame` mint/jackpot inline-duplication precedent). Security floor over gas. RNG/VRF-freeze invariant untouched. Pre-launch redeploy-fresh (storage-layout break fine).

## v48.0 Requirements

### Presale-Box DGNRS Drain Fix — F-47-01 (`PLAN-V48-PRESALE-BOX-DRAIN-FIX.md`)

- [ ] **PFIX-01**: `_presaleBoxDgnrsReward` divisor changed `1_000 → 400` (base `poolStart/100 → poolStart/40`) in `DegenerusGameLootboxModule.sol`, with the inline `base` derivation comment updated to match. ISOLATED — touches no other item's surface.
- [x] **PFIX-02**: Over a realistic 50-ETH presale (random 50/40/10 outcomes across many boxes), the closing-box sweep transfers only variance dust (≤ a small bound, NOT ~60% of the pool) and the pool ends ~empty — the ~40% realized DGNRS branch rate × the 2.5×-larger curve drains the full pool in expectation.
- [x] **PFIX-03**: Tier shape preserved (tier-1 buyer still gets 3× the DGNRS-per-ETH of tier-5; only absolute scale moves); `transferFromPool` clamp holds so a run of early DGNRS hits empties the pool before close → closing sweep ≈ 0, no revert / no over-draw.

### Redemption ETH-Empty stETH Fallback — F-47-02 (`PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md`)

- [ ] **RFALL-01**: The 175% redemption reservation segregates from **pure-ETH OR pure-stETH** (no mix); if ETH cannot cover, fall back to pure-stETH; if **neither** pure leg covers, **revert** (fail-closed). `StakedDegenerusStonk.sol` `_submitGamblingClaimFrom` `maxIncrement` pull + `DegenerusGame.sol` `pullRedemptionReserve` coverage branch.
- [ ] **RFALL-02**: Donation-robust — coverage is checked against the **same asset basis the base is inflated by**, so a stETH-inflated `totalMoney` is coverable by the pure-stETH leg; no claimable-ETH-only chokepoint is reintroduced (stETH donation / `selfdestruct` force-feed cannot brick submit).
- [ ] **RFALL-03**: Claim-time payout asset selection matches the reserved asset (stETH-reserved → stETH-paid via the existing stETH-transfer paths); extends the v47 game-over deterministic ETH→stETH fallback (REDEEM-04) to the mid-game ETH-depletion case.
- [x] **RFALL-04**: `pendingRedemptionEthValue` accounting shape (single tracked value vs split ETH/stETH reservation) decided at SPEC and applied consistently across submit/claim/gameOver.
- [x] **RFALL-05**: v47 REDEEM-08 invariants still hold under the fallback — two same-period claimants, BURNIE-can't-block-ETH, value conservation, and `balance ≥ pending`.

### Keeper Rename + VAULT Affiliate Code (`PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md`)

- [ ] **KEEP-01**: Full function rename — `AfKing.sol`'s `sweep` + the in-game mass-resolve/open crank entrypoints → **autoBuy / autoOpen / autoResolve**; purge "crank" / "do-work" / "sweep" from contract code AND comments. Wide mechanical diff spanning `AfKing.sol` + the in-game crank entrypoints in `DegenerusGame`/modules.
- [ ] **KEEP-02**: Bounty stays MINTED as flip credit — keep the existing v46 `creditFlip` keeper bounty (gas-pegged `BOUNTY_ETH_TARGET`, coinflip-credit illiquidity faucet-lock); the affiliate-revenue funding-pool overlay is DROPPED (no such pool).
- [ ] **KEEP-03**: AfKing passes VAULT's **registered (immutable) affiliate code** into `game.purchase(...)` on every tx it makes (was `0`); unreferred AfKing-joiners are permanently captured by VAULT (foreclosure INTENDED); players already holding a real human affiliate keep it (code ignored).
- [x] **KEEP-04**: SPEC prerequisite — confirm VAULT holds a **registered** affiliate code (`owner == VAULT`, distinct from its address-derived default); register one as a setup step if absent.
- [x] **KEEP-05**: Confirm whether `autoOpen` (open subscribers' lootboxes) is an existing keeper capability or a new one to add; scope accordingly.

### AfKing Pool Recovery (`PLAN-V48-AFKING-POOL-RECOVERY.md`)

- [ ] **POOL-01**: VAULT gets a **permissionless** `recoverAfKingPool()` → `afKing.withdraw(afKing.poolOf(address(this)))`; recovered ETH lands in VAULT reserves via its open `receive()`; no gameOver gate (only moves donated keeper-pool ETH back to where it belongs).
- [ ] **POOL-02**: sDGNRS `receive()` relaxed to accept `AF_KING` in addition to `GAME` (`if (msg.sender != GAME && msg.sender != AF_KING) revert Unauthorized();`) — without this the AfKing send-back reverts (`EthSendFailed`).
- [ ] **POOL-03**: sDGNRS auto-recovers its AfKing pool by folding `afKing.withdraw(afKing.poolOf(address(this)))` into `burnAtGameOver()` (`onlyGame`), placed **before** the `balanceOf(this)==0` early-return so a zero-pool-token sDGNRS still recovers; NO standalone sDGNRS withdraw function.
- [x] **POOL-04**: sDGNRS `receive()` relaxation proven accounting-safe — reserves are read by `address(this).balance` (not a running counter incremented in `receive()`), so an `AF_KING`-sourced credit isn't mis-attributed / double-counted / bypassed.
- [ ] **POOL-05**: `AfKing.sol` itself UNCHANGED; the `IAfKing`/`IAfKingSubscribe` interface additions (`withdraw(uint256)`, `poolOf(address) returns (uint256)`) match `AfKing.sol` signatures verbatim.
- [x] **POOL-06**: Post-gameOver re-stranding (a `depositFor(SDGNRS)` after `burnAtGameOver`) handling decided at SPEC — second sweep in `handleFinalSweep` (fires +30d) vs accept-as-minor; VAULT unaffected (anytime recovery).

### Gameover BURNIE Tombstone (`PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md`)

- [ ] **BTOMB-01**: At `gameOver()`, one-shot bump BURNIE's virtual VAULT mint allowance (`_supply.vaultAllowance`) by **1e36 wei (1 quintillion BURNIE)** via the existing GAME-gated escrow/allowance-increase path, called once from the gameover-drain. `BurnieCoin.sol` + `DegenerusGameGameOverModule`.
- [ ] **BTOMB-02**: Checked add / cap so `existing vaultAllowance + flood` can't overflow `uint128` (constant kept well below 1e38 wei, ~340× headroom); strictly one-shot (cannot be re-triggered to re-flood).
- [x] **BTOMB-03**: Does NOT touch circulating `totalSupply()`; signal lands only in `vaultMintAllowance()` / `supplyIncUncirculated()` / `balanceOf(VAULT)`; DGVB pro-rata BURNIE-claim math does not overflow when claiming a share of a 1e36 allowance.

### Degenerette Hero 2-Point Rescale (`PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md`)

- [ ] **HERO-01**: Scoring becomes `S = A + 2·H` (`A` = matches among the 7 ordinary axes = 4 colors + 3 non-hero symbols; `H = 1` iff hero-quadrant **symbol** matches; hero quadrant's color stays ordinary); max `S = 9`; pay floor `S ≥ 2` so hero-symbol-alone is a guaranteed win. `_countMatches` → `_score(playerTicket, resultTicket, heroQuadrant) ∈ {0..9}`.
- [ ] **HERO-02**: REMOVE the standalone EV-neutral hero multiplier — delete `_applyHeroMultiplier`, `HERO_BOOST_N0..N4_PACKED`, `HERO_PENALTY`, `HERO_SCALE`, and the `M<2`/`M=8` carve-out in `_fullTicketPayout`; hero quadrant stays mandatory (`heroQuadrant >= 4` revert) and `FT_HERO_SHIFT` decode is kept (still needed for scoring) — no new storage, no bet-layout change.
- [ ] **HERO-03**: Per-N payout tables recalibrated to `basePayoutEV = 100 centi-x` across **10 buckets S=0..9**; player RTP unchanged (90.00%–99.90% by activity score; ETH +5% bonus / WWXRP high-roi redistribution preserved); `_roiBpsFromScore` activity-score curve untouched.
- [x] **HERO-04**: Payout SHAPE over `S∈{0..9}` (frequent-small vs juicy-top) chosen at SPEC; WWXRP-bonus / sDGNRS / "high tier" thresholds re-mapped onto the 10-point scale; the S=8/S=9 packing scheme (both > 32-bit) settled; all constants reproduced **byte-identical** from `derive_5_tables.py` (Phase-267-style PASS_ALL gate, not hand-typed).
- [ ] **HERO-05**: Jackpot preserved exactly — `S=9` (all 7 ordinary + hero symbol) is the identical physical event as today's `M=8` (same odds, a relabel); `_awardDegeneretteDgnrs` thresholds (`DEGEN_DGNRS_6/7/8_BPS`) re-mapped to the new scale; `FullTicketResult.matches` doc/range widened `(0-8) → (0-9)`.
- [x] **HERO-06**: Recalibration stays write-batch **byte-identical** to v47's `resolveBets` write-batching (DGAS); the `dailyHeroWagers` / `_rollHeroSymbol` daily-hero-symbol jackpot is unaffected (reads wagers, not per-bet scores) — verify the `matches`-range change does not leak in.

### sDGNRS Far-Future Salvage Swap (`PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md`)

- [ ] **SWAP-01**: New `sellFarFutureTickets(address player, uint32[] levels, uint256[] quantities, uint256[] queueIndices)` game entrypoint; `player` resolved via `_resolvePlayer` (operator-approval honor, drone reaches it with no new forwarder); mass-sell across many far levels → ONE aggregated current-level ticket mint + ONE cash credit; `rngLocked`-gated.
- [ ] **SWAP-02**: Per-line valuation — `d = L - currentLevel`, require `6 ≤ d ≤ 100` (else revert that line); `faceWei` from `PriceLookupLib.priceForLevel(targetLevel)` (never current-level price, never user-supplied); two-line `fractionBps(d)` curve (15%@d6 → 10%@d20 → 5%@d100); units pinned (`owed` in entries, 4 entries = 1 ticket; `oneTicketWei = priceForLevel(currentLevel)`, NOT `/4`); per-level owned-balance check against a running decrement.
- [ ] **SWAP-03**: Daily per-player "pawn-shop" jitter — fraction multiplier ∈ `[70%, 110%]` of base + cash share ∈ `[20%, 60%]` (ticket share `[40%, 80%]`), seeded by `hash(player, lastDayRng)` where `lastDayRng` is an already-SETTLED past VRF word (freeze-safe per `v45-vrf-freeze-invariant`; exact source confirmed at SPEC); offer is player-computable (wait-able/grindable) → all safety bounds proven at the band CEILING, not the mean.
- [ ] **SWAP-04**: Split — ticket floor first (player always receives **≥ 1 whole current-level ticket**), cash is the residual capped per the jitter share; `require(totalBudget >= oneTicketWei)` else revert (too small to deliver one ticket).
- [ ] **SWAP-05**: Funding fail-closed from `claimableWinnings[SDGNRS]` leaving a **≥ 1 ETH floor** (`require(totalBudget <= claimableWinnings[SDGNRS] - 1 ether)`); NO `pendingRedemptionEthValue` term (claimable is already net of redemption backing — redemption desk protected STRUCTURALLY); NO daily cap; `claimableWinnings[SDGNRS]` debited **inline** (ledger lives on the game contract, no sDGNRS-side `fundFarFutureSwap` call).
- [ ] **SWAP-06**: A fully-liquidated seller is removed from `ticketQueue[_tqFarFutureKey(level)]` via an O(1) caller-verified swap-pop (`q[idx]==player`, `queueIndices` only used when a line zeroes a level), MAINTAINING `membership ⟺ packed != 0` so the far-future jackpot samplers need NO change and gain NO hot-path read; **proven NOT to reproduce the `H-CANCEL-SWAP-MISS` operation class** and every `ticketQueue` consumer enumerated safe under swap-pop.
- [ ] **SWAP-07**: VAULT self-call wrapper `gameSellFarFutureTickets onlyVaultOwner` added (`DegenerusVault.sol`); drone reaches the entrypoint via existing operator-approval (no `DegenerusDrone` change); satellite `DroneManager` (+1 typed `onlyChainOwner` pass-through) folded into its pending v47-interface re-sync (it still references v47-deleted `purchaseBurnieLootbox`/`openBurnieLootBox`); LOCKED OPEN-E operator-trust disposition confirmed to cover this first value-destructive operator-gated action.
- [x] **SWAP-08** *(load-bearing security attestation)*: No-arb proven at the jitter band **CEILING** — max full payout `110% × fractionBps(6) = 16.5% of face` @d6 < the cheapest far-entry acquisition (~21%, lootbox tier-1, **re-confirmed at the v47.0-closure HEAD**; margin ~4.5pp); BURNIE cannot mint a far-future entry (`purchaseCoin` has no level arg; mint always targets `cachedLevel`/`+1`; v47 removed the BURNIE-lootbox→future path); base `fractionBps` keeps ≥~10% margin below the far ticket's present EV so a 110%-day pawn doesn't overpay sDGNRS.
- [x] **SWAP-09**: Solvency-safe — `claimablePool ≤ ETH + stETH` never violated (ticket leg routes ETH into pools = gains slack; cash leg is a claimant-to-claimant relabel = neutral); array length bounded (≤ 32); a UI that labels the -EV trade (face value vs tickets + ETH received) ships with the feature (frontend track — flag, don't build here).

### Cross-Cutting — SPEC Reconciliation + TERMINAL Audit (BATCH)

- [x] **BATCH-01** *(SPEC)*: Single SPEC design-lock across all 7 items — every cited `file:line` re-attested vs the v47.0-closure HEAD (no "by construction" claims); shared-surface final signatures reconciled where multiple items touch the same file (`DegenerusGame.sol` items 2/3/7, `StakedDegenerusStonk.sol` items 2/4, `DegenerusVault.sol` items 3/4/7); all SPEC-time open items resolved (RFALL-04, KEEP-04/05, POOL-06, BTOMB packing, HERO-04 shape + packing, SWAP-03 jitter source + SWAP-08 acquisition floor).
- [ ] **BATCH-02** *(IMPL)*: The ONE batched USER-APPROVED `contracts/*.sol` diff (all 7 items) applied + locally compiled/tested, **HELD at the contract-commit boundary** — never committed without explicit user hand-review of the diff (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely-modifiable).
- [ ] **BATCH-03** *(TERMINAL)*: v47→v48 delta-audit (NON-WIDENING — every `contracts`/`test` diff attributable to a v48-scope item) + 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) charged against the 7 surfaces + composition, skeptic-filtered before any elevation; `audit/FINDINGS-v48.0.md` (9-section, chmod 444); closure flip emitting `MILESTONE_V48_AT_HEAD_<sha>`; re-attests every v48.0 requirement.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Off-chain indexer / webpage (incl. Degenerette `matches` 0-8→0-9 widening + salvage-swap -EV labeling UI) | Separate frontend track per PROJECT.md — flag, don't fix here. |
| Liquid-BURNIE keeper rewards / affiliate-revenue funding pool | DROPPED (user 2026-05-25) — bounty stays minted flip credit; no funding pool. |
| Jackpot winner-count / payout-EV / bucket-scaling changes | Not in scope; v48 changes no jackpot EV. |
| Degenerette payout-EV changes beyond the hero rescale | Hero rescale stays neutral-EV (RTP invariant); no other EV change. |
| `dailyHeroWagers` / `_rollHeroSymbol` daily-hero-symbol jackpot | Orthogonal feature (reads wagers, not per-bet scores) — verify no leakage only. |
| Salvage-swap value-side risk (sDGNRS overpaying if a far ticket's true EV < the discount) | Systemic-dilution symptom, bounded by the ≥1 ETH floor — not this feature's concern. |
| Formal archive of v47.0 phase directories (321–324) | Deferred to `/gsd-complete-milestone`; retained in `.planning/phases/` so F-47-01/F-47-02 finding write-ups stay referable. |

## Traceability

Which phases cover which requirements. Phase numbering continues from v47.0 (ended Phase 324) → v48.0 phases are 325–328. SPEC/IMPL/TST/TERMINAL shape.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BATCH-01 | Phase 325 (SPEC) | Complete |
| RFALL-04 | Phase 325 (SPEC) | Complete |
| KEEP-04 | Phase 325 (SPEC) | Complete |
| KEEP-05 | Phase 325 (SPEC) | Complete |
| POOL-06 | Phase 325 (SPEC) | Complete |
| PFIX-01 | Phase 326 (IMPL) | Pending |
| RFALL-01 | Phase 326 (IMPL) | Pending |
| RFALL-02 | Phase 326 (IMPL) | Pending |
| RFALL-03 | Phase 326 (IMPL) | Pending |
| KEEP-01 | Phase 326 (IMPL) | Pending |
| KEEP-02 | Phase 326 (IMPL) | Pending |
| KEEP-03 | Phase 326 (IMPL) | Pending |
| POOL-01 | Phase 326 (IMPL) | Pending |
| POOL-02 | Phase 326 (IMPL) | Pending |
| POOL-03 | Phase 326 (IMPL) | Pending |
| POOL-05 | Phase 326 (IMPL) | Pending |
| BTOMB-01 | Phase 326 (IMPL) | Pending |
| BTOMB-02 | Phase 326 (IMPL) | Pending |
| HERO-01 | Phase 326 (IMPL) | Pending |
| HERO-02 | Phase 326 (IMPL) | Pending |
| HERO-03 | Phase 326 (IMPL) | Pending |
| HERO-05 | Phase 326 (IMPL) | Pending |
| SWAP-01 | Phase 326 (IMPL) | Pending |
| SWAP-02 | Phase 326 (IMPL) | Pending |
| SWAP-03 | Phase 326 (IMPL) | Pending |
| SWAP-04 | Phase 326 (IMPL) | Pending |
| SWAP-05 | Phase 326 (IMPL) | Pending |
| SWAP-06 | Phase 326 (IMPL) | Pending |
| SWAP-07 | Phase 326 (IMPL) | Pending |
| BATCH-02 | Phase 326 (IMPL) | Pending |
| PFIX-02 | Phase 327 (TST) | Complete |
| PFIX-03 | Phase 327 (TST) | Complete |
| RFALL-05 | Phase 327 (TST) | Complete |
| POOL-04 | Phase 327 (TST) | Complete |
| BTOMB-03 | Phase 327 (TST) | Complete |
| HERO-04 | Phase 327 (TST) | Complete |
| HERO-06 | Phase 327 (TST) | Complete |
| SWAP-08 | Phase 327 (TST) | Complete |
| SWAP-09 | Phase 327 (TST) | Complete |
| BATCH-03 | Phase 328 (TERMINAL) | Pending |

**Coverage:**
- v48.0 requirements: **40 total** — PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3.
- Mapped to phases: **40/40 ✓** (Phase 325 SPEC: 5 · Phase 326 IMPL: 25 · Phase 327 TST: 9 · Phase 328 TERMINAL: 1).
- Unmapped: **0** — every requirement maps to exactly one phase; 0 orphaned, 0 duplicated.
- Center-of-gravity split: design-decision items → SPEC (RFALL-04, KEEP-04/05, POOL-06, BATCH-01); code-change items → IMPL; empirical-proof items → TST (incl. HERO-04 byte-reproduce gate + SWAP-08 no-arb proof); delta-audit/sweep/closure → TERMINAL.

---
*Requirements defined: 2026-05-25*
*Last updated: 2026-05-25 — Traceability table filled to 100% coverage at roadmap creation (Phases 325–328)*
