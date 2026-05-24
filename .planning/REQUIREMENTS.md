# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-23
**Milestone:** v46.0 Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal
**Posture:** Single batched USER-APPROVED contract diff at IMPL per `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_no_contract_commits` + `feedback_manual_review_before_push`; AGENT-COMMITTED test/planning/docs. Pre-launch redeploy-fresh per `feedback_frozen_contracts_no_future_proofing` (storage-layout break fine, no migration).
**Audit baseline → subject:** v45.0 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` → v46.0 closure HEAD. Subject = the batched ADD+REMOVE diff (`DegenerusGame` + modules + `BurnieCoin`/`BurnieCoinflip` + `DegenerusVault` + `StakedDegenerusStonk` + `ContractAddresses` + in-tree `AfKing` keeper; paired `degenerus-utilities` rework).
**Load-bearing input:** `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` (ADD half, §1–§14) + `.planning/PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` (REMOVE half, grep-verified footprint) + memories `project_free_burnie_crank_button` + `project_v47_remove_afking_eth_autorebuy`.
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

---

## v46.0 Goal (precise statement)

Ship the permissionless do-work crank and the AfKing auto-rebuy subscription (`StreakKeeperV2` moved in-tree as `AfKing`, wired via PROTO-01..05), and in the SAME batched diff remove the legacy in-game AFKing mode + free ETH auto-rebuy it succeeds — one source-tree change, one test pass, one adversarial audit, one `MILESTONE_V46_AT_HEAD_<sha>` closure. The removal is a prerequisite for the subscription's reinvest mode (old free auto-rebuy intercepts winnings before claimable; the subscription reads from claimable).

**Non-negotiable closure verdict at v46.0 TERMINAL (target):** `CRANK_DO_WORK SHIPPED; AFKING_SUBSCRIPTION SHIPPED; LEGACY_AFKING_MODE + FREE_ETH_AUTOREBUY REMOVED; BURNIE_FLIP_AUTOREBUY KEPT@75BPS; FAUCET_BOUNDED; SWEEP NON-BRICK + CONCURRENT-SAFE; FUNDING_WATERFALL + TWO-TIER_SKIP-KILL CORRECT; RNG_FREEZE_INTACT (+ obligations RETIRED by removal); JACKPOT_ETH_SPLIT REMOVED (single-call fits @305-ceiling); WWXRP_ZERO_REWARD; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`.

---

## v46.0 Requirements

### PROTO — Protocol-side contract additions (degenerus-audit, one batched diff)

- [x] **PROTO-01**: `DegenerusGame.hasAnyLazyPass(address) external view` exposed (the kept private `_hasAnyLazyPass` at `:1610`; returns "any of Deity/Whale/Lazy"). Reconciles with RM-04 — kept, not deleted.
- [x] **PROTO-02**: `BurnieCoin.burnForKeeper(address user, uint256 amount) returns (uint256 burned)` — ALL-OR-NOTHING burn of the subscription charge (source `balanceOf` + pending coinflip; if `< amount` burn nothing & return 0); `onlyAfKing` (gated on the pinned keeper address).
- [x] **PROTO-03**: AfKing keeper authorized in `BurnieCoinflip.onlyFlipCreditors` so its `creditFlip` bounty works (coinflip credit = deferred mint).
- [x] **PROTO-04**: `DegenerusGame.batchPurchase(players[], amounts[], modes[])` keeper-gated entry — per-player in-context purchase wrapped in try/catch + slice-refund (non-brick); one value transfer for the batch; batch-level `rngLocked`/game-over pre-checked once.
- [x] **PROTO-05**: `AF_KING` keeper address pinned as a frozen constant in `BurnieCoin` / `BurnieCoinflip` / `ContractAddresses.sol`; `burnForKeeper` / `creditFlip` / `batchPurchase` gate on exactly it.

### CRANK — In-game do-work crank (Deliverable A)

- [x] **CRANK-01**: Permissionless mass do-work entry(s) taking grouped `(player, ids)` work lists (off-chain-discovered, no on-chain enumeration); per-item isolated via `onlySelf` self-call + try/catch (skip stale/reverting items, reward only successes); batch-accumulated reward → one `creditFlip`/tx.
- [x] **CRANK-02**: Degenerette mass resolve via do-work (placement stays gated; resolve relaxed) with a collision short-circuit (`list[0]` already resolved → `BatchAlreadyTaken` revert); per-item try/catch wraps items 1..N.
- [x] **CRANK-03**: Lootbox open via do-work (already permissionless; route the reward). Boxes resolved via the parameterless cursor model (collision-free) per OPEN-D.
- [x] **CRANK-04**: WWXRP work is resolvable but earns **zero** reward (`currency == 3`).

### REW — Reward model

- [x] **REW-01**: Reward = `gasUnits(workType) · 0.5 gwei → BURNIE` via `_ethToBurnieValue` at the current level price.
- [x] **REW-02**: Paid as coinflip stake credit (deferred mint), batch-accumulated → one `creditFlip` per cranker per tx (never per-item).
- [x] **REW-03**: Marginal per-item gas peg (no base-amortization margin in batches); fixed `gasUnits` constants, never `gasleft()`/`tx.gasprice`.
- [x] **REW-04**: No caller restriction — reward credited to whoever calls, including a player resolving their own item.

### SUB — AfKing auto-rebuy subscription

- [x] **SUB-01**: Pass-OR-pay gate; pass = any of Deity/Whale/Lazy via `hasAnyLazyPass`; checked at the monthly renewal branch only (not per sweep). No pass → `burnForKeeper` charges the BURNIE cost (or skip-with-emit if uncoverable).
- [x] **SUB-02**: Authorization = the subscription itself; `subscribe(player, …)` self-consent (`player == msg.sender`/0) or operator-approved (`isOperatorApproved`), checked **once at subscribe** (third-party path only) — never at sweep.
- [x] **SUB-03**: Cursor sweep — `sweep(maxCount)` + daily `sweepCursor`; concurrent same-block callers self-partition via the advancing cursor; stall-escalating bounty drives daily completeness; per-entry `lastSweptDay` idempotency.
- [x] **SUB-04**: Quantity model = flat `dailyQuantity` (uint8, **minimum 1**) + optional `reinvestPct` (uint8); effective daily buy = `max(dailyQuantity, floor(claimable × reinvestPct / price))` — reinvest only triggers when its amount exceeds the flat schedule. Both pack into one flags byte + `reinvestPct` (no new slot).
- [x] **SUB-05**: Funding waterfall = claimable-first → pool top-up (Combined) → `InsufficientPool` skip (the existing `drainGameCreditFirst=true` model). "Claimable-only" needs no new flag — an empty `_poolOf` degrades to claimable-or-skip.
- [x] **SUB-06**: Two-tier skip-kill — a NORMAL sub is cancelled on a funding skip (`claimable+pool < cost`) via in-sweep swap-pop removal (pool dust stays withdrawable); **`Vault` + `sDGNRS` are EXEMPT** (transient skip, persist), keyed on un-spoofable pinned address identity (NOT a settable flag); renewal-lapse still cancels both.
- [x] **SUB-07**: Lapsed/cancelled lifecycle — tombstone-on-cancel (no move), in-sweep swap-pop reclaim, `_subOf` delete-unless-unexpired-paid-window (`windowPaid` bit), transient-skip retry, withdrawable stranded `_poolOf` ETH.
- [x] **SUB-08**: Bounty = coinflip credit (gas-pegged, REW); charge = `burnForKeeper` (burn, all-or-nothing).
- [x] **SUB-09**: Protocol-owned subs created at the contracts' own init — **sDGNRS** self-subscribes (claimable-only, lootbox mode, flat 1 + 2% reinvest) AND enables BURNIE flip auto-rebuy `takeProfit=0` (full recycle); **Vault** self-subscribes (claimable-only, flat 1, no reinvest, no BURNIE rebuy). Both free-renew via their Whale pass (level-expiring caveat — confirm post-expiry renewal funding at SPEC). **DESIGN LOCKED at Phase 316 (Plan 316-03 `## Protocol-Owned Subs (SUB-09)`):** init configs locked (sStonk `setAfKingMode`→self-subscribe replacement; Vault self-subscribe); post-expiry renewal funding USER-RATIFIED = `permanent-deity` — the permanent Deity bit is ALREADY set on SDGNRS/VAULT in the live `DegenerusGame` constructor (`:222`/`:223`), so `hasAnyLazyPass` is permanently true (zero per-renewal cost, no BURNIE stream) and Phase 317 needs only to preserve that grant byte-unmodified. IMPL wiring (PROTO/RM-05 self-subscribe) lands at Phase 317.

### RM — Legacy AFKing-mode + free ETH-auto-rebuy removal (the v47 half, folded in)

- [x] **RM-01**: AFKing mode removed entirely — `setAfKingMode`/`_setAfKingMode`/`_deactivateAfKing`/`afKingModeFor`/`afKingActivatedLevelFor`/`deactivateAfKingFromCoin`/`syncAfKingLazyPassFromCoin`, the `afKingMode`/`afKingActivatedLevel` fields, `AFKING_*` constants, `AfKingModeToggled` event, `AfKingLockActive` error all gone. Grep-clean for `afKing`/`AFKING_` (excl. `contracts/test`+`mocks`).
- [x] **RM-02**: Free ETH auto-rebuy removed entirely — `setAutoRebuy`/`setAutoRebuyTakeProfit` + privates + `autoRebuyTakeProfitFor` + the `AutoRebuyState` struct/mapping + jackpot `_processAutoRebuy`/`_calcAutoRebuy`. ETH jackpot winnings always credit to claimable; the jackpot credit path no longer consumes a VRF word (entropy param dropped).
- [x] **RM-03**: BURNIE flip auto-rebuy KEPT, collapsed to flat 75bps — `_afKingRecyclingBonus`/`_afKingDeityBonusHalfBpsWithLevel` + deity constants (`AFKING_RECYCLE_BONUS_BPS`/`AFKING_DEITY_*`/`DEITY_RECYCLE_CAP`/`AFKING_KEEP_MIN_COIN`) removed; enable/disable/take-profit/carry/claim still work end-to-end; deity tier dropped.
- [x] **RM-04**: `_hasAnyLazyPass` KEPT and exposed (PROTO-01) — overrides the standalone-removal dead-code instinct; it is the keeper's pass gate.
- [x] **RM-05**: Cross-contract cascade pruned — `DegenerusVault.gameSetAutoRebuy`/`gameSetAutoRebuyTakeProfit`/`gameSetAfKingMode` removed (BURNIE `coinSet*` kept); `StakedDegenerusStonk` init `setAfKingMode` replaced by the keeper self-subscribe (SUB-09); `IDegenerusGame`/`IBurnieCoinflip` decls + `settleFlipModeChange` removed.
- [x] **RM-06**: Storage-layout slot constants re-derived after the `AutoRebuyState` deletion; full suite compiles + green; `KNOWN_ISSUES` and the BURNIE win/loss RNG path (`processCoinflipPayouts`, `rngWord & 1`) unmodified.

### SAFE — Safety / non-brick / faucet

- [x] **SAFE-01**: Faucet bounded by the three caller-independent locks (purchase-gate + gas-peg + coinflip-credit illiquidity); self-crank/Sybil round-trip ≤ 0; WWXRP 0 reward.
- [x] **SAFE-02**: Non-brick (BOTH cranks AND `batchPurchase`) — per-item `onlySelf` self-call + try/catch (skip + refund-if-applicable, reward only successes); caller-bounded iteration; cancel un-brickable; no double-buy reentrancy (in-context sub-call rolls back on revert). **PROVEN 318-03** (CrankNonBrick.t.sol 12/12 + AfKingSubscription.t.sol 7/7).
- [x] **SAFE-03**: Concurrency — same-block sweeps process correctly (cursor self-partition + `lastSweptDay`); no double-buy. **PROVEN 318-04** (AfKingConcurrency.t.sol 10/10 incl. a 1000-run exactly-once same-block-split fuzz + AfKingFundingWaterfall.t.sol 9/9; same-block self-partition sum==N/max-per==1, tombstone no-miss + no dead-slot buildup, SUB-05 waterfall + SUB-06 two-tier pinned-identity skip-kill, grep-clean no settable exemption flag).
- [x] **SAFE-04**: RNG-freeze intact — resolution stays post-unlock (`RngNotReady` guard), placement guard untouched; the ETH-auto-rebuy removal **retires** freeze obligations (one fewer VRF consumer + three fewer player-mutable in-window inputs) rather than weakening any.

### GAS — Gas efficiency (worst-case-first per `feedback_gas_worst_case`)

- [x] **GAS-01**: Worst-case-first measurement per work-type before optimizing.
- [ ] **GAS-02**: One `creditFlip`/cranker/tx; one batch value transfer; `level`/`mintPrice` read once/batch.
- [ ] **GAS-03**: Calldata grouped by player; homogeneous per-work-type fns.
- [ ] **GAS-04**: Maximal storage packing; no new per-bet/box storage on the hot placement path.
- [ ] **GAS-05**: Scavenger + Skeptic pass; every removal/packing validated against the security floor.
- [x] **GAS-06**: Regression bounds (placement hot-path +0%); measured worst-cases calibrate the 0.5 gwei peg.

### JGAS — Jackpot ETH-path gas re-profile + two-call split removal (folded in; *enabled by* RM-02's ETH-auto-rebuy removal)

The free ETH auto-rebuy was a per-winner conditional branch on the daily-ETH-jackpot credit path — `_addClaimableEth` (`DegenerusGameJackpotModule.sol:788-811`) did a cold `SLOAD` of `autoRebuyState[beneficiary]` + a possible `_processAutoRebuy` per winner. RM-02 deletes it, flattening + lowering per-winner ETH-credit gas. That freed headroom is localized to the **daily-ETH path** only (coin/lootbox/ticket caps sit on other cost centers and the coin path retains the BURNIE-flip auto-rebuy v46 keeps — so `DAILY_COIN_MAX_WINNERS`/`LOOTBOX_MAX_WINNERS`/`PURCHASE_PHASE_TICKET_MAX_WINNERS` are untouched). Use it purely to delete the two-call split at the **same 305-winner ceiling** — no winner-count / payout-EV change.

- [x] **JGAS-01**: Derive the THEORETICAL worst-case single-call daily-ETH-jackpot gas *after* RM-02 (worst case = max scale `DAILY_JACKPOT_SCALE_MAX_BPS=63_600` → `DAILY_ETH_MAX_WINNERS=305`, buckets 159/95/50/1, all 4 in one call) — worst-case-FIRST per `feedback_gas_worst_case`. Trace the split's design intent + actor game-theory before locking deletion per `feedback_design_intent_before_deletion`. **DECISION GATE:** 305-winner single call fits the block gas limit with margin → lock removal; else **RETAIN + document**. The 305 ceiling is PRESERVED (split removal only). Enumerate + grep-verify the deletion footprint spanning BOTH `DegenerusGameJackpotModule.sol` (`SPLIT_NONE/CALL1/CALL2`, `resumeEthPool` slot, `_resumeDailyEth`, `splitMode`/`call1Bucket` routing, the `JACKPOT_MAX_WINNERS` split-threshold branch `:476-501`, the `:348` resume-check) AND `DegenerusGameAdvanceModule.sol` (`STAGE_JACKPOT_ETH_RESUME=8` `:68-70` + the `:452-455` resume-check + its stage handler).
- [x] **JGAS-02**: *If JGAS-01 locks removal* — in the SAME batched USER-APPROVED diff, delete the daily-ETH two-call split across both modules: `SPLIT_*` constants + `splitMode` param + `call1Bucket` mask + `_resumeDailyEth` + the `resumeEthPool` storage slot + the split-threshold branch in the jackpot module, AND `STAGE_JACKPOT_ETH_RESUME` + its resume-check + stage handler in the advance module. Daily ETH jackpot completes in ONE advanceGame stage / one call at the 305 ceiling. Re-derive storage-layout slot constants after the `resumeEthPool` deletion (compounds with RM-02/RM-06's `AutoRebuyState` slot re-derivation). No winner-count / scaling / EV change.
- [x] **JGAS-03**: Prove the daily ETH jackpot pays out correctly at the 305-winner ceiling in ONE call without the split — every bucket (159/95/50/1) paid, exact per-winner amounts, none missed/double-paid, total credited = pool, gas under the block limit; the old split path (`resumeEthPool`, `SPLIT_CALL1/2`, `STAGE_JACKPOT_ETH_RESUME`) grep-clean + behaviorally gone (no resume stage entered). Suite recompiles green with the re-derived slots. **(318-06, JackpotSingleCallCorrectness.t.sol 8/8: 305 emissions, per-bucket exact share, conservation `sum(claimable)+whale-pass==paidWei≤pool`, worst-case 7.5M gas < 30M, single-call fully resolves + split grep-clean; commit `a3e6b27f`.)**
- [ ] **JGAS-04**: Empirically measure the worst-case single-call 305-winner daily-ETH-jackpot gas on the patched tree; confirm JGAS-01's theoretical derivation + the margin under the block gas limit; attribute the enabling delta to the removed per-winner `autoRebuyState` SLOAD + branch. Folds into the GAS-01 worst-case-first pass.

(The split-removal delta-audit — composes cleanly with the RM-02 removal, no payout stranded by the dropped `resumeEthPool` carry, no double/under-credit — is folded into Phase 320 TERMINAL's existing cross-cutting delta-audit charge, which owns no requirement primarily and re-attests everything at closure.)

### OPENE — Shared funding source (OPEN-E, promoted into v46.0 at Phase 319.1)

Promoted from Deferred 2026-05-24. One funding wallet covers BOTH the BURNIE subscription charge AND the ETH `_poolOf` auto-buy draw for a player's multiple subscriber addresses. Default `fundingSource == address(0)` = self (behavior-identical to pre-OPEN-E). Pre-launch redeploy-fresh — the `Sub` repack + slot re-derivation is free per `feedback_frozen_contracts_no_future_proofing`. Lands as its own single batched USER-APPROVED `contracts/AfKing.sol` diff at Phase 319.1 (a SECOND IMPL diff on top of the 317 batch).

- [ ] **OPENE-01**: `Sub` gains `address fundingSource` (default `address(0)` = self) set via a caller-scoped mutator (same NotSubscribed gating as the other `Sub` setters). Repack to free room — only 19 of 32 bytes remain vs a 20-byte address — by collapsing the two standalone bools (`drainGameCreditFirst`, `useTickets`) into the existing `flags` byte; storage-layout slot constants re-derived, suite recompiles green with no slot drift.
- [ ] **OPENE-02**: The sweep ETH auto-buy draw reads/debits `_poolOf[fundingSource]` (resolved to self when `fundingSource == 0`) instead of `_poolOf[player]`; per-draw gas unchanged (same single slot already SLOADed). The two-tier funding-skip-kill keeps the Vault/sDGNRS exemption keyed on the un-spoofable SUBSCRIBER identity, never the source.
- [ ] **OPENE-03**: Both `burnForKeeper` charge sites route to `fundingSource` instead of the subscriber — the `subscribe()` SUB-01 pass-or-pay gate (`AfKing.sol:396`) and the `sweep()` day-31 auto-extract (`AfKing.sol:587`). All-or-nothing semantics preserved; source-shortfall falls through the existing failure path (subscribe revert / day-31 auto-pause).
- [ ] **OPENE-04**: Authorization = game operator-approval, money-holder-grants-spender direction — source S calls `setOperatorApproval(M, true)`; keeper requires `isOperatorApproved(S, M)` to honor `fundingSource = S`, checked at subscribe + the day-31 renewal branch ONLY (never per-draw — bounds post-revoke drain to ≤1 renewal window; on revoke the draw reverts to self / auto-pauses). **Caveat documented:** for the BURNIE charge this same approval authorizes burning S's general wallet BURNIE + pending coinflip (sharper than the pre-funded ETH escrow the gate was originally chosen for); a dedicated `allowBurnieFunding[S][M]` opt-in flag is the explicit alternative if the overload is later judged unwanted.

---

## Deferred / Future (acknowledged, not in v46.0 roadmap)

- **OPEN-E — shared funding source for multi-wallet players** — PROMOTED into v46.0 on 2026-05-24; now in scope as OPENE-01..04 (Phase 319.1, full BURNIE + ETH pool). See the OPENE requirements section above.
- **OPEN-D bet-cursor** — on-chain per-index bet queue + parameterless `resolveBetsWork()`. Bets stay caller-list (per-bet enqueue tax too steep on the hot path); revisit only if heavy cross-player bet-cranking is expected.

## Out of Scope

| Feature | Reason |
|---------|--------|
| System-chore cranks (advanceGame / jackpot) | Out of the do-work scope; separate concern |
| Jackpot winner-count / bucket-scaling / payout-EV changes | JGAS removes only the gas-split *mechanism* at the SAME 305-winner ceiling; raising `DAILY_ETH_MAX_WINNERS` (an EV change) was explicitly declined |
| Degenerette payout-EV / placement changes | Not a v46 surface; placement stays gated |
| Bet/box ledger storage re-key | Hot-path cost; off-chain discovery used instead (OPEN-D deferred) |
| Liquid-BURNIE rewards | Reward must survive coinflip edge (illiquidity is a faucet lock) |
| Off-chain indexer / webpage | Separate frontend track |
| Deity-pass utilities outside the BURNIE recycle bonus | Trait/gold mechanics untouched by RM-03 |
| Deployed-state migration | None — pre-launch redeploy-fresh |

## Traceability

Each requirement maps to exactly one phase (primary verification owner). The full add+remove design is *locked* at Phase 316 SPEC and *consumed* by every downstream phase; the table below records the single phase that owns each requirement's acceptance. Phase 320 (TERMINAL) re-attests all 46 at the closure verdict and owns no requirement primarily.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROTO-01 | Phase 316 | Complete |
| SUB-09 | Phase 316 | Complete (316-03 — design locked; permanent-deity free-renew ratified) |
| RM-04 | Phase 316 | Complete |
| JGAS-01 | Phase 316 | Complete |
| PROTO-02 | Phase 317 | Complete |
| PROTO-03 | Phase 317 | Complete |
| PROTO-04 | Phase 317 | Complete |
| PROTO-05 | Phase 317 | Complete |
| CRANK-01 | Phase 317 | Complete |
| CRANK-02 | Phase 317 | Complete |
| CRANK-03 | Phase 317 | Complete |
| CRANK-04 | Phase 317 | Complete |
| REW-01 | Phase 317 | Complete |
| REW-02 | Phase 317 | Complete |
| REW-03 | Phase 317 | Complete |
| REW-04 | Phase 317 | Complete |
| SUB-01 | Phase 317 | Complete |
| SUB-02 | Phase 317 | Complete |
| SUB-03 | Phase 317 | Complete |
| SUB-04 | Phase 317 | Complete |
| SUB-05 | Phase 317 | Complete |
| SUB-06 | Phase 317 | Complete |
| SUB-07 | Phase 317 | Complete |
| SUB-08 | Phase 317 | Complete |
| RM-01 | Phase 317 | Complete |
| RM-02 | Phase 317 | Complete |
| RM-03 | Phase 317 | Complete |
| RM-05 | Phase 317 | Complete |
| RM-06 | Phase 317 | Complete |
| JGAS-02 | Phase 317 | Complete |
| SAFE-01 | Phase 318 | Complete |
| SAFE-02 | Phase 318 | Complete |
| SAFE-03 | Phase 318 | Complete |
| SAFE-04 | Phase 318 | SATISFIED — 318-01 the slot/recompile facet (suite green, no slot drift, RM-06 empirically confirmed); 318-05 the RNG-freeze post-unlock proof (RngFreezeAndRemovalProofs.t.sol 13/13: crank resolve stays behind RngNotReady pre-word, placement guard :452 untouched, word-set-timing fuzz) + freeze-obligation retirement (deterministic no-VRF-word credit) + the REMOVE proofs (grep-clean kill set, ETH→claimable, flat 75bps, win/loss RNG path + KNOWN-ISSUES byte-unmodified). Commit `b9bc5206` |
| JGAS-03 | Phase 318 | Complete (318-06) |
| GAS-01 | Phase 319 | Complete |
| GAS-02 | Phase 319 | Pending |
| GAS-03 | Phase 319 | Pending |
| GAS-04 | Phase 319 | Pending |
| GAS-05 | Phase 319 | Pending |
| GAS-06 | Phase 319 | Complete |
| JGAS-04 | Phase 319 | Pending |
| OPENE-01 | Phase 319.1 | Pending |
| OPENE-02 | Phase 319.1 | Pending |
| OPENE-03 | Phase 319.1 | Pending |
| OPENE-04 | Phase 319.1 | Pending |

**Coverage:**
- v46.0 requirements: 46 total (PROTO 5 · CRANK 4 · REW 4 · SUB 9 · RM 6 · SAFE 4 · GAS 6 · JGAS 4 · OPENE 4)
- Mapped to phases: **46 / 46** (Phase 316: 4 · Phase 317: 26 · Phase 318: 5 · Phase 319: 7 · Phase 319.1: 4 · Phase 320 TERMINAL: re-attests all 46, owns 0 primarily)
- Unmapped / orphaned: **0**
- No requirement maps to more than one phase (no duplicates).

**Per-phase requirement sets:**
- **Phase 316 SPEC** (4): PROTO-01, SUB-09, RM-04, JGAS-01 — the cross-half reconciliation (KEEP+EXPOSE `_hasAnyLazyPass`) + protocol-owned sub init design + the jackpot-split removal decision gate (worst-case-first gas derivation @305) + claimable-only/quantity-unit/skip-kill-identity/whale-expiry SPEC-open resolution. (All 42 requirements' designs are locked here; only these 4 have SPEC as primary owner.)
- **Phase 317 IMPL** (26): PROTO-02..05 + CRANK-01..04 + REW-01..04 + SUB-01..08 + RM-01/02/03/05/06 + JGAS-02 — the one batched USER-APPROVED contract diff + paired `AfKing` keeper rework + the daily-ETH two-call split removal (both modules).
- **Phase 318 TST** (5): SAFE-01..04 + JGAS-03 — faucet-resistance, non-brick, concurrency, RNG-freeze, 305-winner single-call jackpot correctness; also carries the testable acceptance of SUB-*/CRANK-*/REW-*/RM-* + the removal proofs.
- **Phase 319 GAS** (7): GAS-01..06 + JGAS-04 — worst-case-first pass + 0.5 gwei peg calibration + empirical 305-winner single-call jackpot measurement.
- **Phase 319.1 IMPL** (4): OPENE-01..04 — the shared funding-source promotion (`Sub.fundingSource` field + setter, ETH-pool draw routing, BURNIE-charge routing at both `burnForKeeper` sites, operator-approval authorization at subscribe + renewal). Its own single batched USER-APPROVED `contracts/AfKing.sol` diff.
- **Phase 320 TERMINAL** (0 primary): cross-cutting acceptance / closure verdict over all 46 + the add/remove + jackpot-split-removal + OPEN-E funding-source delta-audit + freeze-obligation-retirement attestation.

---
*Requirements defined: 2026-05-23 — milestone v46.0 (combined crank/subscription ADD + legacy AFKing/ETH-auto-rebuy REMOVE). Traceability filled by roadmapper 2026-05-23 — 38/38 mapped, 0 orphaned, 0 duplicated. JGAS-01..04 jackpot-split-removal sub-thread folded in 2026-05-23 — 42/42 mapped. OPEN-E (OPENE-01..04) promoted from Deferred into v46.0 scope 2026-05-24 at inserted Phase 319.1 — 46/46 mapped.*
