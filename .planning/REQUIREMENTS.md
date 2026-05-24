# Requirements: Degenerus Protocol — v47.0 Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle

**Defined:** 2026-05-24
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Audit baseline → subject:** v46.0 closure HEAD `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687` → v47.0 closure HEAD. Subject = the single batched contract diff reconciling the seven work items.
**Scope source:** `.planning/PLAN-V47-MILESTONE-SCOPE.md` (manifest) + the 7 plan docs. All economic numbers + design decisions (D1–D5) LOCKED; no open decisions.

> **Posture:** pre-launch redeploy-fresh (storage-layout breaks fine, no migration); security floor over gas. **ONE batched USER-APPROVED `contracts/*.sol` diff** for the whole milestone — `.sol` may be edited autonomously but is NEVER committed without explicit hand-review of the diff. Tests + planning AGENT-committable. `ContractAddresses.sol` freely modifiable.

---

## v47.0 Requirements

### PRESALE — Rake-Free Presale + Coin Boxes (`PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md`)

- [ ] **PRESALE-01**: Remove the 20% presale vault skim — presale lootbox ETH routes 100% to prize pools (collapse the special presale split 50/30/20 → normal 90/10; `MintModule:1036-1075`).
- [ ] **PRESALE-02**: Remove the +62% presale BURNIE bonus block (`LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6200`; `LootboxModule:288, 957-975`). Net: all lootboxes are 0% to dev → game is rake-free.
- [ ] **PRESALE-03**: Accrue `presaleBoxCredit[player] += 0.25·purchaseEth` on all non-Degenerette ETH buys during presale (`!presaleOver`) — the exact 4 former `_awardEarlybirdDgnrs` sites: mint (`MintModule:1210`), whale bundle / lazy / deity (`WhaleModule:263/476/587`). BURNIE-funded buys + Degenerette ETH bets excluded.
- [ ] **PRESALE-04**: Coin-presale box — credit-gated, paid in fresh ETH (or claimable per CPAY-02), consumes credit 1:1; global cumulative cap 50 ETH; `MIN_BOX` 0.01 ETH checked on the REQUESTED amount (pre-clamp, lock-prevention); `boxAmount > availableCredit` → revert.
- [ ] **PRESALE-05**: Box contents — single random roll: 50% BURNIE (mean 400% of box ETH on-branch / 200% all-boxes avg, via `E[largeBurnieBps]=40000`), 40% DGNRS (%-of-pool tiers, 5×10-ETH cumulative-volume tiers at rates `[3.0,2.5,2.0,1.5,1.0]`, pool drains at 50 ETH), 10% → 1 WWXRP.
- [ ] **PRESALE-06**: Box ETH routing 80/20 — on purchase `claimablePool += boxEth`, `claimableWinnings[VAULT] += 80%`, `claimableWinnings[SDGNRS] += 20%` (remainder handled; pattern = `_queueWhalePassClaimCore`).
- [ ] **PRESALE-07**: Unified entrypoint `buyPresaleBox` / `buyLootboxAndPresaleBox` — optional same-call credit-earning mint + box buy; box queues at its own index; combined lootbox+box share one index/RNG word; bundle-open resolves both via domain-separated draws; robust to either-alone (lone lootbox / lone box / both).
- [ ] **PRESALE-08**: Presale box is BOON-LESS — its own 50/40/10 resolution, NOT a `_resolveLootboxCommon` caller, draws NO boons/passes (a credit-funded box can never mint a whale pass).
- [ ] **PRESALE-09**: Presale close — the box crossing 50 ETH is clamped to land cumulative box-ETH at exactly 50 (excess refunded), gets a normal roll, sweeps ALL remaining `Pool.PresaleBox` DGNRS to that buyer on top of the roll, latches `presaleOver = true` (slot 0), stops credit accrual. Verify the clamped final tier + sweep zeroes the pool.
- [ ] **PRESALE-10**: `Pool.PresaleBox` REPLACES `Pool.Earlybird` (rename the enum slot `StakedDegenerusStonk.sol:215` + `IStakedDegenerusStonk.sol:15`; takes the 10%-of-INITIAL_SUPPLY allocation, no bps change). REMOVE the entire earlybird emission subsystem: `_awardEarlybirdDgnrs` (`Storage:966-1013`) + 4 sites, `_finalizeEarlybird` (`AdvanceModule:1744`) + its `EARLYBIRD_END_LEVEL` trigger, `earlybirdDgnrsPoolStart`/`earlybirdEthIn`/`EARLYBIRD_TARGET_ETH`/`EARLYBIRD_END_LEVEL` (grep-verify no other consumer first).
- [ ] **PRESALE-11**: New storage — `presaleOver` bool (slot 0 padding), `presaleBoxEthSold` counter (own slot, cap 50 ETH), `presaleBoxCredit` mapping, presale-box index→RNG-word mapping + per-player queued box ETH (mirror `lootboxEth`/`lootboxRngWordByIndex`). Grep-verify and delete dead `presaleStatePacked` + level-3 clear + 200-ETH-mint auto-end if no consumers remain.
- [ ] **PRESALE-12**: Box RNG freeze-safe — payout entropy reuses the committed index/day RNG word with a domain-separated salt (`keccak256(rngWord,"PRESALE_BOX")`); entropy unknown at buy-commit, frozen across the request→unlock window (re-verify at secure-phase).
- [ ] **PRESALE-13**: Undrained-pool backstop — none needed: if box volume never reaches 50 ETH, the undrained `Pool.PresaleBox` burns at game-over (`StakedDegenerusStonk.sol:518`); credit accrual runs harmlessly (boxes globally capped at 50 ETH).

### LOOT — Lootbox-Boon Unification + BURNIE-Box Removal (`PLAN-LOOTBOX-BOON-UNIFICATION.md`)

- [ ] **LOOT-01**: Remove the BURNIE lootbox surface entirely — `openBurnieLootBox` (`LootboxModule:561`; `Game:664/682`), `purchaseBurnieLootbox` (`Game:559`; `MintModule:864` + `_purchaseBurnieLootboxFor:1425`), the `lootBoxBurnieAmount` branch of `purchaseCoin`/`_purchaseCoinFor` (`MintModule:894-895`), the `BurnieLootOpen` event, the vault wrapper `gamePurchaseBurnieLootbox` (`DegenerusVault:554-557`) + interface decl. Closes the terminal-paradox (unguardable BURNIE→future-ticket) hole.
- [ ] **LOOT-02**: Keep BURNIE→tickets — `purchaseCoin`'s `ticketQuantity` branch (ENF-01-guarded) + vault `gamePurchaseTicketsBurnie` stay; `purchaseCoin` becomes tickets-only (drop/zero `lootBoxBurnieAmount`; update `Game:537`, `DegenerusVault:51` interface).
- [ ] **LOOT-03**: Unify the 3 remaining ETH callers — `resolveLootboxDirect` + `resolveRedemptionLootbox` flip `allowBoons` false→true (`openLootBox` already true); all three roll full boons + passes.
- [ ] **LOOT-04**: Fix the 10% boon-budget haircut — the `mainAmount = amount − _lootboxBoonBudget(amount)` carve (`:949`) now actually spends the budget on the two formerly-`allowBoons=false` paths (no silent drop).
- [ ] **LOOT-05**: Remove the now-dead `allowBoons` / `allowPasses` / `presale` params + their conditionals from `_resolveLootboxCommon` (`:973-975, :982, :1268-1282, :1344-1352`); update the 3 remaining call sites + param docs (`:897-910`); drop any BURNIE-conversion helper left with no caller.
- [ ] **LOOT-06** (D1): `resolveLootboxDirect` (shared Degenerette `DegeneretteModule:772` + Decimator `DecimatorModule:601` win paths) gains boons/passes — uniform, intended; player-claim, off the advanceGame chain, boon gas on the claimer's tx.

### DGAS — Degenerette Resolution Gas (same-results) (`PLAN-DEGENERETTE-RESOLUTION-GAS.md`)

- [ ] **DGAS-01**: Accumulate ETH/BURNIE/WWXRP payouts CROSS-BET across the whole `resolveBets` call and flush ONCE — one `mintForGame`/`mintPrize` per currency, one `claimableWinnings[player]` + one `claimablePool` write (additive → byte-identical).
- [ ] **DGAS-02**: ETH cap/solvency stays per-spin but evaluates against a running-pool local (read pool once, decrement in memory per spin); one claimable+pool write + one pool write at end — byte-identical to per-spin today.
- [ ] **DGAS-03**: Lootbox-share summed PER `betId` → one `resolveLootboxDirect` per bet; NEVER summed across betIds (resolution-batch-invariant). Per-spin RESULT seed for match determination stays per-spin; drop the per-spin `lootboxWord` salting.
- [ ] **DGAS-04**: DGNRS award (`_awardDegeneretteDgnrs`, ETH 6+ matches) stays per-spin — reads `poolBalance` fresh per call (summing off a stale balance would change payouts).
- [ ] **DGAS-05**: RNG seed derivation, `rngWord` fetch, and the freeze invariant are UNTOUCHED (batch only bookkeeping after outcomes are determined). Worst-case gas (one bet all-spins-paying per currency + mixed-currency multi-bet, up to the 25-spin ETH cap from DSPIN-01) derived-then-measured; report measured delta.

### CPAY — Universal Claimable-Pay (`PLAN-UNIVERSAL-CLAIMABLE-PAY.md`)

- [ ] **CPAY-01**: `purchaseWhaleBundle` / `purchaseLazyPass` / `purchaseDeityPass` (`WhaleModule:262/474/581`) accept `msg.value` + `claimableWinnings` shortfall — replace `if (msg.value != price) revert` with the established pattern (overpay reverts; `shortfall = cost − msg.value`; require `claimableWinnings[buyer] > shortfall` STRICT 1-wei-sentinel; debit claimable + `claimablePool`).
- [ ] **CPAY-02**: Presale box accepts claimable-pay (pure ledger move: player claimable → 80% VAULT + 20% SDGNRS, `claimablePool` net 0) — implemented jointly with PRESALE-06.
- [ ] **CPAY-03**: Sweep ALL `external payable` entries in `DegenerusGame.sol` (`:347, :498, :593, :615, :635, :712, :1691, :1732, :1875`) to apply claimable-pay uniformly; confirm no path legitimately requires fresh-ETH-only; `claimablePool == Σ claimableWinnings` stays balanced.

### REDEEM — sDGNRS Redemption Accounting (`PLAN-SDGNRS-REDEMPTION-ACCOUNTING.md`)

- [ ] **REDEEM-01**: ETH submit segregation — at `_submitGamblingClaimFrom`, pull the MAX possible payout (175% of base) from `claimableWinnings[SDGNRS]` into sDGNRS's balance via a new `SDGNRS`-gated `pullRedemptionReserve(uint256)` (checked debit of claimable + `claimablePool` + real ETH transfer); `pendingRedemptionEthValue` tracks the segregated 175%. Revert the burn if the full 175% can't segregate (fail-closed).
- [ ] **REDEEM-02**: ETH resolve — at `resolveRedemptionPeriod`, lower `pendingRedemptionEthValue` from MAX to the rolled amount (accounting only); the excess ETH already in sDGNRS balance becomes free backing (no transfer back to claimable).
- [ ] **REDEEM-03**: ETH claim + lootbox — `claimRedemption` pays `ethDirect` first from segregated balance (drop the `game.claimWinnings` pull for this path); `resolveRedemptionLootbox` becomes `payable` (sDGNRS forwards `lootboxEth` as `msg.value`; game credits `futurePrizePool` from the arriving ETH) and REMOVES the unchecked `claimableWinnings[SDGNRS] -= amount` debit entirely (Defect A fixed).
- [ ] **REDEEM-04**: GameOver — drop `+ pendingRedemptionEthValue` from `reserved` (`GameOverModule:91-92, 154-155`) — double-count once ETH is pre-pulled into sDGNRS; deterministic ETH→stETH fallback unchanged; re-check the `BurnsBlockedDuringLiveness` window rationale.
- [ ] **REDEEM-05**: BURNIE flip-credit at submit — settle the whole BURNIE leg at submit via one atomic `redeemBurnieShare(redeemer, base)` on `BurnieCoinflip` (burn `min(base, balanceOf(SDGNRS))` held BURNIE → consume remainder from sDGNRS stake → `creditFlip(redeemer, base)`); no reserve, no roll, no claim-time BURNIE; net new BURNIE = 0 (conserved).
- [ ] **REDEEM-06**: Delete the BURNIE reserve apparatus — `pendingRedemptionBurnie` + `- pendingRedemptionBurnie` terms (`:795/:864/:806`), the resolve-time release (`:662-665`), `_payBurnie` (`:937-948`), `RedemptionPeriod.flipDay`, the day+1 coinflip lookup + partial-claim BURNIE branch; `claimRedemption` becomes ETH-only.
- [ ] **REDEEM-07**: BURNIE authority — add `ContractAddresses.SDGNRS` to `onlyFlipCreditors` (`BurnieCoinflip:191-201`); allow sDGNRS to consume its own stake; new `SDGNRS`-gated burn on `BurnieCoin.sol` for sDGNRS's own held BURNIE.
- [ ] **REDEEM-08**: Invariants — NO `unchecked` claimable subtraction anywhere in the redemption path; `address(this).balance ≥ pendingRedemptionEthValue` at all times; BURNIE net mint across a redemption == 0. Repro tests (write FIRST, fail pre-fix): two-claimant ETH underflow; BURNIE-can't-block-ETH; conservation across submit/resolve/claim/gameOver.

### DSPIN — Degenerette Per-Currency Spin Caps (`PLAN-DEGENERETTE-SPINS-PER-CURRENCY.md`)

- [ ] **DSPIN-01**: Replace the single global `MAX_SPINS_PER_BET = 10` with per-currency caps ETH 25 / BURNIE 15 / WWXRP 5 in `_placeDegeneretteBetCore` (`:445`); retire `MAX_SPINS_PER_BET`; update the two doc comments (`:296, :364`). Min bet per-spin unchanged; `ticketCount` 8-bit packing unchanged.
- [ ] **DSPIN-02**: Worst-case `resolveBets` (max 25-spin ETH bets in one call, 2.5× the old per-bet roll work) gas regression derived-then-measured and shown absorbed by the DGAS write-batching.

### TOMB — AfKing Cancel-Tombstone (ISOLATED; fixes v46.0 H-CANCEL-SWAP-MISS) (`PLAN-V47-AFKING-CANCEL-TOMBSTONE.md`)

- [ ] **TOMB-01**: `setDailyQuantity(0)` becomes a true in-place tombstone (`AfKing.sol:455-468`) — do NOT call `_removeFromSet` (relocate no one); set `s.dailyQuantity = 0` in place; defer the `_subOf` delete-vs-preserve decision to the in-sweep reclaim; preserve the existing `SubscriptionUpdated(…,0,…)` event shape. Stranded `_poolOf` ETH stays withdrawable. Re-activation via `setDailyQuantity(q>0)` with no set churn / no double-add.
- [ ] **TOMB-02**: Add the in-sweep tombstone-reclaim branch to the sweep loop (`~:609-745`) — at loop-top on `sub.dailyQuantity == 0`, apply the deferred `_subOf` delete-vs-preserve (paid-unexpired-window → keep; else delete), `_removeFromSet(player)`, emit the appropriate event, and do NOT advance the cursor (process the swap-pop occupant at this same index this sweep; mirror the `:644` no-`++i` pattern). Order the tombstone check vs the `lastSweptDay >= today` skip so a dead tombstone is always reclaimed, never left as a permanent dead slot.
- [ ] **TOMB-03**: Invariant — external cancel never relocates an entry → the only swap-pops are in-loop (auto-pause, funding-kill, tombstone-reclaim), all no-cursor-advance → no subscriber is ever skipped for the day because of someone else's cancel → mint streaks are not collaterally broken (H-CANCEL-SWAP-MISS fixed; SUB-07 restored).
- [ ] **TOMB-04** (test): `test/fuzz/AfKingConcurrency.t.sol` — add `testCancelBehindCursorDoesNotStrandPendingTail`, `testCancelTombstoneReclaimedByNextSweep`, `testCancelPreservesPaidWindowThroughDeferredReclaim`, `testReactivateTombstonedSubNoDoubleAdd`; re-confirm the existing 318-04 guarantees (exactly-once same-block, `lastSweptDay` backstop, no double-buy, no dead-slot buildup, two-tier skip-kill identity).
- [ ] **TOMB-05** (stale test fix): update `test/gas/CrankLeversAndPacking.t.sol::testGas04PackingAndNoNewHotPathStorageSourcePresence` to the post-OPENE-01 `Sub` shape (drop the two standalone-bool field checks, add `address fundingSource`, fix the byte-sum 13→31 + field list) — restores a clean 44-fail v47.0 regression baseline (currently the 45th fail).

### BATCH — Cross-Plan Reconciliation, Call-Graph Attestation & Terminal Audit

- [ ] **BATCH-01**: ONE batched contract diff reconciles all shared surfaces per manifest §2 — most critically `resolveRedemptionLootbox`'s FINAL signature settles LOOT-03 (boon flag) + REDEEM-03 (payable + no-claimable-debit) together; the `presale`-param removal (LOOT-05) lands with the presale-bonus removal (PRESALE-02); the `DegeneretteModule` edit lands DGAS + DSPIN once; `claimablePool == Σ claimableWinnings` checked jointly across PRESALE-06 / CPAY / REDEEM.
- [ ] **BATCH-02**: Call-graph attestation — every cited file:line grep-verified against the v47.0 plan-time HEAD before patching (no "by construction" claims; `feedback_verify_call_graph_against_source`); inline-duplicated logic re-checked (DegenerusGame jackpot/mint precedent).
- [ ] **BATCH-03** (terminal): delta audit vs the v46.0 baseline + 3-skill adversarial sweep (presale snipe / credit double-spend / box-RNG freeze / close-liveness; claimable-invariant; lootbox terminal-paradox closure; redemption two-claimant + BURNIE-can't-block-ETH + conservation; tombstone griefing) → findings + `MILESTONE_V47_AT_HEAD_<sha>` closure signal + atomic ROADMAP/STATE/MILESTONES/PROJECT flip.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Liquid-BURNIE crank rewards; the "free BURNIE" crank-reward button | Planned separately; boxes already permissionless (`project_free_burnie_crank_button`) |
| Off-chain indexer / webpage | Separate frontend track (PROJECT.md) |
| Degenerette payout-EV / placement changes | DSPIN changes spin caps only (fewer WWXRP shots / lower variance on the main roll, no whale-pass effect); DGAS is gas-only, same results |
| Raising `DAILY_ETH_MAX_WINNERS` or any jackpot winner-count / payout-EV change | Out of bundle scope |
| AfKing crank/subscription redesign beyond the cancel-tombstone | v46.0 shipped; TOMB-* is the only AfKing change (revert-to-SUB-07-spec) |
| BURNIE→tickets removal | KEPT (already ENF-01 terminal-safe); only BURNIE→lootbox is removed |

## Traceability

Empty — populated by the roadmapper during ROADMAP creation. Each requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| (to be filled by roadmap) | — | Pending |

**Coverage:**
- v47.0 requirements: 42 total (PRESALE 13 · LOOT 6 · DGAS 5 · CPAY 3 · REDEEM 8 · DSPIN 2 · TOMB 5 · BATCH 3 = 45 IDs; roadmapper validates 100% mapping)
- Mapped to phases: TBD
- Unmapped: TBD ⚠️

---
*Requirements defined: 2026-05-24*
*Last updated: 2026-05-24 after v47.0 milestone definition*
