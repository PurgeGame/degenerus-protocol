---
phase: 324-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 01
milestone: v47.0
audit_baseline: 16e9668a6de35cc0c809d81ce960aee137950687
audit_baseline_signal: MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687
audit_subject_frozen_ref: fabe9e94
deliverable: 324-01-DELTA-AUDIT.md
regression_baseline: 598/38/16 (v46 565/45/16)
disposition: ALL-SURFACES-NON-WIDENING
---

# v47.0 SC1 Delta Audit — Per-Surface NON-WIDENING Attestation

**Audit subject (FROZEN):** `fabe9e94` — the single batched v47.0 IMPL diff `fb29ed51` + the
Degenerette `resolveBets` post-game-over insolvency guard `if (_livenessTriggered()) revert E();`
(`DegenerusGameDegeneretteModule.sol:421`). The working-tree `contracts/` is byte-identical to
`fabe9e94`: `git diff fabe9e94 HEAD -- contracts/` is **EMPTY** (zero contract mutation in this
terminal phase; the audit is read-only via `git show`/`git diff`/`grep`).

**Audit baseline:** v46.0 closure HEAD `16e9668a6de35cc0c809d81ce960aee137950687`
(signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`).

**Delta surface:** `git diff 16e9668a fabe9e94 --name-only -- contracts/` → **18 files** (17 mainnet
+ 1 `contracts/test/` helper). Every surface is attested **NON-WIDENING** below with a concrete
grep/diff anchor re-verified against the frozen subject.

---

## §1. The 18-file changed surface (grouped by the 7 work items)

| # | File | Work item(s) |
|---|------|--------------|
| 1 | `AfKing.sol` | 7 (cancel-tombstone) |
| 2 | `BurnieCoin.sol` | 5 (SDGNRS burn authority) |
| 3 | `BurnieCoinflip.sol` | 5 (SDGNRS flip-creditor authority) |
| 4 | `DegenerusGame.sol` | 1 (presaleOver latch, 80/20 box ledger), 2 (BURNIE-lootbox kill), 3, 4 (payable sweep), 5 (resolveRedemptionLootbox payable) |
| 5 | `DegenerusVault.sol` | 2 (BURNIE-lootbox wrapper kill) |
| 6 | `StakedDegenerusStonk.sol` | 1 (Pool.PresaleBox rename), 5 (ETH segregation + flip-credit-at-submit + reserve-apparatus deletion) |
| 7 | `interfaces/IDegenerusGame.sol` | 1/2/4/5 (entry-signature deltas) |
| 8 | `interfaces/IDegenerusGameModules.sol` | 2/3/5 (module-signature deltas: resolveRedemptionLootbox, lootbox params) |
| 9 | `interfaces/IStakedDegenerusStonk.sol` | 1 (Pool.PresaleBox), 5 (redemption interface) |
| 10 | `modules/DegenerusGameAdvanceModule.sol` | 1 (earlybird subsystem removal) |
| 11 | `modules/DegenerusGameDegeneretteModule.sol` | 3 (write-batching), 6 (per-currency caps) + the fabe9e94 liveness guard |
| 12 | `modules/DegenerusGameGameOverModule.sol` | 5 (drop `+ pendingRedemptionEthValue` double-count) |
| 13 | `modules/DegenerusGameLootboxModule.sol` | 1 (62% bonus removal, presale-box resolution), 2 (BURNIE-lootbox kill + `_resolveLootboxCommon` param collapse), 5 (resolveRedemptionLootbox) |
| 14 | `modules/DegenerusGameMintModule.sol` | 1 (90/10 split, credit accrual, earlybird removal), 2 (BURNIE-lootbox kill) |
| 15 | `modules/DegenerusGamePayoutUtils.sol` | 1/4 (claimable ledger helpers) |
| 16 | `modules/DegenerusGameWhaleModule.sol` | 4 (3 purchases claimable-pay), 1 (credit accrual sites) |
| 17 | `storage/DegenerusGameStorage.sol` | 1 (presale storage: presaleOver, presaleBoxCredit, presaleBoxEthSold, box index→word) |
| 18 | `contracts/test/SettleClaimableShortfallTester.sol` | **NON-MAINNET** test helper (CPAY shortfall harness) — not a mainnet surface |

---

## §2. Per-Surface NON-WIDENING Disposition Table

Mirrors v46 §3.A. Columns: Surface | Requirements | Re-grepped anchors (frozen subject) | Disposition.

| Surface | Requirements | Re-grepped anchors @ `fabe9e94` | Disposition |
|---|---|---|---|
| **1. Rake-removal + presale-box** | PRESALE-01..13 | 90/10 split via `LOOTBOX_SPLIT_NEXT_BPS`/`futureBps`/`10_000` (`MintModule:1030-1045`, no 50/30/20 special split, no 20% skim); `LOOTBOX_PRESALE_BURNIE_BONUS_BPS` grep **0** (62% bonus removed, PRESALE-02); `presaleOver` latch **15** refs (slot-0 latch present); `presaleBoxCredit` **14** refs (PRESALE-03/11); `PresaleBox` enum/refs **43** (Pool.Earlybird→PresaleBox rename, PRESALE-10); presale box resolution is boon-less own-path (`LootboxModule:574` "Boon-less, own resolution NOT a `_resolveLootboxCommon` caller", PRESALE-08); `keccak256(rngWord,"PRESALE_BOX")` domain salt present (PRESALE-12) | **NON-WIDENING** |
| **2. Lootbox-boon unification** | LOOT-01..06 | BURNIE-lootbox kill-set grep **0** in mainnet (`openBurnieLootBox`/`purchaseBurnieLootbox`/`_purchaseBurnieLootboxFor`/`gamePurchaseBurnieLootbox`/`BurnieLootOpen`/`lootBoxBurnieAmount` all 0); sole `openBurnieLootBox` survivor = `contracts/test/LootboxBernoulliTester.sol` doc comment (**non-mainnet**); `allowBoons`/`allowPasses` params grep **0** (LOOT-05 dead-param removal); `_resolveLootboxCommon` has exactly **3 callers** (`:558`, `:770`, `:803` — the unified ETH paths, LOOT-03); terminal-paradox closed (no BURNIE→box path survives) | **NON-WIDENING** |
| **3. Degenerette gas (same-results) + liveness guard** | DGAS-01..05 | DGAS-05 proven byte-identical to per-spin baseline (323-04 event-replay); batch is bookkeeping-only after outcomes determined (RNG/freeze untouched); per-betId lootbox sum + per-spin DGNRS; the **fabe9e94 liveness guard** `if (_livenessTriggered()) revert E();` confirmed at `DegeneretteModule:421` (proven to close the §1 insolvency by 323-09 `testResolveBetsRevertsPostGameOver_InsolvencyReproClosed`) | **NON-WIDENING** |
| **4. Per-currency spin caps** | DSPIN-01..02 | `MAX_SPINS_ETH=25` / `MAX_SPINS_BURNIE=15` / `MAX_SPINS_WWXRP=5` at `DegeneretteModule:226-228`; cap selector `:497-500`; worst-case 25-spin ETH 485,089 gas + 45-spin mixed 619,349 gas, both ≪ 30M (323-04) | **NON-WIDENING** |
| **5. Universal claimable-pay** | CPAY-01..03 | 3 WhaleModule purchases + the `DegenerusGame.sol` external-payable entry sweep apply the `shortfall = cost − msg.value` + strict-1-wei-sentinel pattern; `claimablePool == Σ claimableWinnings` proven balanced (323-09 `SolvencyObligations` canonical-set, 5 solvency invariants GREEN at 256 runs) | **NON-WIDENING** |
| **6. sDGNRS redemption** | REDEEM-01..08 | ETH hard-segregation `pullRedemptionReserve` **8** refs (checked debit, fail-closed, REDEEM-01); `redeemBurnieShare` **7** refs (flip-credit-at-submit, net BURNIE mint 0, REDEEM-05); `pendingRedemptionBurnie` grep **0** + `_payBurnie` grep **0** + `RedemptionPeriod.flipDay` grep **0** (reserve apparatus deleted, REDEEM-06 — note: the 15 residual `flipDay` substring hits are all `coinflipDay`/`CoinflipDayResult`, BurnieCoinflip's own mechanism, NOT the redemption field); `resolveRedemptionLootbox` Game entry `external payable` with `if (msg.value != amount) revert E();` (`DegenerusGame.sol:1835`) and the unchecked `claimableWinnings[SDGNRS] -= amount` debit **removed** (REDEEM-03, Defect A fixed); gameOver `+ pendingRedemptionEthValue` double-count dropped (REDEEM-04); REDEEM-08 repro proven (323-03) | **NON-WIDENING** |
| **7. AfKing cancel-tombstone** | TOMB-01..05 | `setDailyQuantity(0)` is in-place: `s.dailyQuantity = 0; emit SubscriptionUpdated(...); return;` (`AfKing.sol:463-467`) with **no `_removeFromSet`** call; all 3 `_removeFromSet` sites (`:617`, `:658`, `:755`) are **in-sweep-loop** (auto-pause / funding-kill / tombstone-reclaim), all no-cursor-advance; `SubscriptionExpired` reason `2 = CancelReclaim` added; H-CANCEL-SWAP-MISS structurally resolved (TOMB-01/02/03; empirically proven 323-05 `testCancelBehindCursorDoesNotStrandPendingTail`) | **NON-WIDENING** |

### Conditional-delete note (PRESALE-11)
`presaleStatePacked` survives (6 mainnet refs: `Storage:893/910/915` declare/get/set + `MintModule:1007/1014` read/write). PRESALE-11 specified "delete dead `presaleStatePacked` … **if no consumers remain**." A consumer DOES remain — the `lootboxPresaleActive` toggle (the presale-lootbox-pricing flag, distinct from the new `presaleOver` box latch) is still read/written via `presaleStatePacked` in `MintModule`. The conditional-delete trigger was therefore not met; retaining the slot is correct, not a widening. **NON-WIDENING.**

---

## §3. Composition Attestation Matrix (mirrors v46 §3.B)

| Composition | Attestation | Disposition |
|---|---|---|
| **ADD × REMOVE** | The earlybird emission subsystem (`_awardEarlybirdDgnrs` + 4 sites, `_finalizeEarlybird`, `EARLYBIRD_*` consts) is grep-**0** in mainnet; its 4 award sites (mint + whale/lazy/deity) are cleanly swapped 1:1 for the `presaleBoxCredit += 0.25·eth` accrual (PRESALE-03/D5); `Pool.Earlybird` enum slot grep-**0**, renamed to `Pool.PresaleBox` taking the identical 10%-of-INITIAL_SUPPLY allocation. No orphaned emitter, no double-credit. | **NON-WIDENING** |
| **claimable-balance** | `claimablePool == Σ claimableWinnings` holds across the three editors (PRESALE-06 80/20 box ledger move, CPAY shortfall debits, REDEEM SDGNRS-gated checked pull). Proven by the 323-09 `SolvencyObligations` canonical obligation set — all 5 solvency invariants (`EthSolvency`/`MultiLevel`/`WhaleSybil`/`VaultShareMath`/`DegeneretteBet`) GREEN at 256 runs / 32768 calls. | **NON-WIDENING** |
| **BURNIE-net-0** | `redeemBurnieShare` burns `min(base, balanceOf(SDGNRS))` held BURNIE then consumes the remainder from sDGNRS stake → `creditFlip(redeemer, base)`: net new BURNIE = 0 (REDEEM-05). The BURNIE-lootbox conversion path is removed entirely (no BURNIE→box mint). BURNIE→tickets KEPT (LOOT-02, ENF-01-guarded). | **NON-WIDENING** |
| **RNG-freeze-intact** | The presale box reuses the committed index/day RNG word with a domain salt `keccak256(rngWord,"PRESALE_BOX")` (PRESALE-12); the Degenerette write-batching touches only bookkeeping after outcomes are determined (DGAS-05 — RNG seed derivation, `rngWord` fetch, freeze invariant byte-unchanged). No new VRF consumer mutates in-window. | **NON-WIDENING** |

---

## §4. Regression-Baseline Attestation (mirrors v46 §5)

### §4a. Suite baseline — 598 / 38 / 16 NON-WIDENING vs v46 565 / 45 / 16

The final v47 foundry baseline (323-09 full `forge test`, combined run) is **598 pass / 38 fail /
16 skip** (652 total). Every one of the 38 failures is classified — **zero unexplained v47-delta:**

- **32 PRE-EXISTING v46** — byte-identical at the v46 closure HEAD `16e9668a` (worktree, isolated runs, identical gas). The "0x11 ticket-queue + pending-pool cluster" (`TicketRouting` 12 / `QueueDoubleBuffer`+`MidDaySwap` 9 / `TicketEdgeCases` 2 / `PrizePoolFreeze` 2 / `RngIndexDrainBinding` / `VRFCore` / `TicketLifecycle` / `GameOverPathIsolation` / `CoverageGap222` / `LootboxBoonCoexistence` 2) is a harness-time `block.timestamp` underflow (`_livenessTriggered()`→`GameTimeLib.currentDayIndexAt(1)` underflow in standalone setUps that never `vm.warp`) + an unmodeled 1% `_swapAndFreeze` pre-seed — **NOT a v47 slot-shift** (these files have no hardcoded slot constants and are byte-identical v46↔HEAD). Deferred (not fixed) per the do-not-touch-v46 / non-widening rule.
- **5 combined-run fuzz/cache noise** — `VRFPathInvariants` (3) / `VRFPathCoverage` / `RngLockDeterminism` PASS in isolation; the combined run re-populates the fuzz-failure replay cache mid-run (documented 323-01 tooling artifact). Not real residuals.
- **1 v47-behavioral PRESALE delta** — `VRFLifecycle::test_vrfLifecycle_levelAdvancement` (see §4b). Owned by this phase's economic re-verify.

The 5 solvency invariants that 323-01/323-04 had listed as new-vs-v46 were proven STALE-HARNESS (not rake economics) and re-greened by 323-09's principled obligation-formula correction — now GREEN and off the residual list. **ZERO v47 contract regressions.**

### §4b. REG-01-equivalent — NON-WIDENING attribution

`git diff 16e9668a..fabe9e94 -- contracts/ test/`: every hunk is attributable to a known
v47-scope change — the batched IMPL diff `fb29ed51`, the `fabe9e94` Degenerette liveness guard,
and the AGENT-committed test repairs (fixture `AF_KING` constructor args, `SolvencyObligations`
helper, the 323-03/04/05 repro + same-results + tombstone tests). `git diff fabe9e94 HEAD -- contracts/`
is empty. No unattributable contract hunk. **NON-WIDENING.**

---

## §5. Handoff dispositions (the two STATE.md "324 handoff" items)

### VRFLifecycle recalibration — v47-PRESALE test-calibration delta (NOT a defect)
`VRFLifecycle::test_vrfLifecycle_levelAdvancement` flipped PASS→FAIL deterministically at `fabe9e94`
("Game should advance past level 0"; gas 131M→76M). Root cause: the test's purchase-volume magic
numbers were calibrated for the **v46** prize-pool split; v47's rake-removal + presale-box
40%→`nextPrizePool` split changed per-purchase accumulation, so the same purchase loop no longer
bootstraps to the 50-ETH level-0 advance. The test even comments the "40% to nextPrizePool" presale
split. This is the **v47 SPEC behaving as intended**, NOT a contract defect.
- **Skeptic-filter:** (1) structural-protection — the level-advance gate is unchanged contract logic; the test's *input volume* is stale, not the contract. (2) 3-condition EV — (a) no harm manifests on-chain (real players supply real ETH; only the synthetic test's hardcoded volume is short), (b) magnitude n/a (test-only), (c) severity does not survive (it is a test fixture, not a contract path). **Does NOT elevate.**
- **Recommended disposition (v47-internal test note, NOT a finding):** recalibrate the test's purchase-volume to the v47 rake-free/presale split so it again reaches the 50-ETH bootstrap. Test-only; no contract change.

### OBS-1 — pre-existing Decimator under-reservation (out of v47 scope)
`_creditDecJackpotClaimCore` decrements `claimablePool -= lootboxPortion` (full, `DecimatorModule:394`),
then `_awardDecimatorLootbox` re-credits a sub-2.25-ETH `remainder` via `_creditClaimable` (`:592`)
**without** re-adding to `claimablePool` — leaving `claimablePool` short by `remainder` relative to
`Σ claimableWinnings` (an **under**-reservation → the dust may be un-payable; the OPPOSITE direction
from an unbacked over-credit / insolvency).
- **Classification:** PRE-EXISTING — byte-identical at the v46 baseline; outside the v47 audit-subject
  surface set (v47 touched Degenerette/presale/redemption/lootbox-boon/tombstone, not the regular
  Decimator claim accounting). Runs **pre-game-over only** (the game-over branch returns at `:336`).
- **Skeptic-filter:** (1) structural-protection — pre-GO only; the post-GO drain/guard class is unaffected (323 bug-class sweep found 0 siblings). (2) 3-condition EV — (a) no positive-EV attack (it strands the winner's own dust, harming only the claimant), (b) magnitude immaterial (sub-2.25-ETH remainder, and only the lootbox-half remainder fragment), (c) severity does not survive (un-payable dust, not a drain). **Does NOT elevate.**
- **Disposition:** carry forward descriptively for optional separate review of the regular-Decimator
  claim accounting. NOT a v47 finding; no contract change recommended.

---

## §6. SC1 Verdict

**ALL 7 v47.0 work-item surfaces attest NON-WIDENING** with concrete grep/diff evidence against the
frozen subject `fabe9e94`. The BURNIE-lootbox + earlybird kill-sets are grep-ZERO in mainnet code (the
sole `contracts/test/` doc-comment survivor noted as non-mainnet). The presaleOver latch, Pool.PresaleBox
rename, `_resolveLootboxCommon` 3-caller param-collapse, per-currency caps, redemption ETH segregation +
BURNIE-net-0 + reserve-apparatus deletion, and the AfKing in-place tombstone are each anchor-confirmed.
The composition matrix (ADD×REMOVE / claimable-balance / BURNIE-net-0 / RNG-freeze-intact) holds. The
598/38/16 regression baseline is NON-WIDENING vs v46 565/45/16 (32 pre-existing-v46 + 5 combined-run
noise + 1 v47-PRESALE test-calibration delta; 0 contract regressions). The VRFLifecycle recalibration
and OBS-1 handoff items pass the economic skeptic-filter and neither elevates to a finding.
`git diff fabe9e94 HEAD -- contracts/` is empty (zero contract mutation).

*SC1 delta-audit authored 2026-05-25. Read-only; subject frozen at `fabe9e94`.*
