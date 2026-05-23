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

**Non-negotiable closure verdict at v46.0 TERMINAL (target):** `CRANK_DO_WORK SHIPPED; AFKING_SUBSCRIPTION SHIPPED; LEGACY_AFKING_MODE + FREE_ETH_AUTOREBUY REMOVED; BURNIE_FLIP_AUTOREBUY KEPT@75BPS; FAUCET_BOUNDED; SWEEP NON-BRICK + CONCURRENT-SAFE; FUNDING_WATERFALL + TWO-TIER_SKIP-KILL CORRECT; RNG_FREEZE_INTACT (+ obligations RETIRED by removal); WWXRP_ZERO_REWARD; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`.

---

## v46.0 Requirements

### PROTO — Protocol-side contract additions (degenerus-audit, one batched diff)

- [ ] **PROTO-01**: `DegenerusGame.hasAnyLazyPass(address) external view` exposed (the kept private `_hasAnyLazyPass` at `:1610`; returns "any of Deity/Whale/Lazy"). Reconciles with RM-04 — kept, not deleted.
- [ ] **PROTO-02**: `BurnieCoin.burnForKeeper(address user, uint256 amount) returns (uint256 burned)` — ALL-OR-NOTHING burn of the subscription charge (source `balanceOf` + pending coinflip; if `< amount` burn nothing & return 0); `onlyAfKing` (gated on the pinned keeper address).
- [ ] **PROTO-03**: AfKing keeper authorized in `BurnieCoinflip.onlyFlipCreditors` so its `creditFlip` bounty works (coinflip credit = deferred mint).
- [ ] **PROTO-04**: `DegenerusGame.batchPurchase(players[], amounts[], modes[])` keeper-gated entry — per-player in-context purchase wrapped in try/catch + slice-refund (non-brick); one value transfer for the batch; batch-level `rngLocked`/game-over pre-checked once.
- [ ] **PROTO-05**: `AF_KING` keeper address pinned as a frozen constant in `BurnieCoin` / `BurnieCoinflip` / `ContractAddresses.sol`; `burnForKeeper` / `creditFlip` / `batchPurchase` gate on exactly it.

### CRANK — In-game do-work crank (Deliverable A)

- [ ] **CRANK-01**: Permissionless mass do-work entry(s) taking grouped `(player, ids)` work lists (off-chain-discovered, no on-chain enumeration); per-item isolated via `onlySelf` self-call + try/catch (skip stale/reverting items, reward only successes); batch-accumulated reward → one `creditFlip`/tx.
- [ ] **CRANK-02**: Degenerette mass resolve via do-work (placement stays gated; resolve relaxed) with a collision short-circuit (`list[0]` already resolved → `BatchAlreadyTaken` revert); per-item try/catch wraps items 1..N.
- [ ] **CRANK-03**: Lootbox open via do-work (already permissionless; route the reward). Boxes resolved via the parameterless cursor model (collision-free) per OPEN-D.
- [ ] **CRANK-04**: WWXRP work is resolvable but earns **zero** reward (`currency == 3`).

### REW — Reward model

- [ ] **REW-01**: Reward = `gasUnits(workType) · 0.5 gwei → BURNIE` via `_ethToBurnieValue` at the current level price.
- [ ] **REW-02**: Paid as coinflip stake credit (deferred mint), batch-accumulated → one `creditFlip` per cranker per tx (never per-item).
- [ ] **REW-03**: Marginal per-item gas peg (no base-amortization margin in batches); fixed `gasUnits` constants, never `gasleft()`/`tx.gasprice`.
- [ ] **REW-04**: No caller restriction — reward credited to whoever calls, including a player resolving their own item.

### SUB — AfKing auto-rebuy subscription

- [ ] **SUB-01**: Pass-OR-pay gate; pass = any of Deity/Whale/Lazy via `hasAnyLazyPass`; checked at the monthly renewal branch only (not per sweep). No pass → `burnForKeeper` charges the BURNIE cost (or skip-with-emit if uncoverable).
- [ ] **SUB-02**: Authorization = the subscription itself; `subscribe(player, …)` self-consent (`player == msg.sender`/0) or operator-approved (`isOperatorApproved`), checked **once at subscribe** (third-party path only) — never at sweep.
- [ ] **SUB-03**: Cursor sweep — `sweep(maxCount)` + daily `sweepCursor`; concurrent same-block callers self-partition via the advancing cursor; stall-escalating bounty drives daily completeness; per-entry `lastSweptDay` idempotency.
- [ ] **SUB-04**: Quantity model = flat `dailyQuantity` (uint8, **minimum 1**) + optional `reinvestPct` (uint8); effective daily buy = `max(dailyQuantity, floor(claimable × reinvestPct / price))` — reinvest only triggers when its amount exceeds the flat schedule. Both pack into one flags byte + `reinvestPct` (no new slot).
- [ ] **SUB-05**: Funding waterfall = claimable-first → pool top-up (Combined) → `InsufficientPool` skip (the existing `drainGameCreditFirst=true` model). "Claimable-only" needs no new flag — an empty `_poolOf` degrades to claimable-or-skip.
- [ ] **SUB-06**: Two-tier skip-kill — a NORMAL sub is cancelled on a funding skip (`claimable+pool < cost`) via in-sweep swap-pop removal (pool dust stays withdrawable); **`Vault` + `sDGNRS` are EXEMPT** (transient skip, persist), keyed on un-spoofable pinned address identity (NOT a settable flag); renewal-lapse still cancels both.
- [ ] **SUB-07**: Lapsed/cancelled lifecycle — tombstone-on-cancel (no move), in-sweep swap-pop reclaim, `_subOf` delete-unless-unexpired-paid-window (`windowPaid` bit), transient-skip retry, withdrawable stranded `_poolOf` ETH.
- [ ] **SUB-08**: Bounty = coinflip credit (gas-pegged, REW); charge = `burnForKeeper` (burn, all-or-nothing).
- [ ] **SUB-09**: Protocol-owned subs created at the contracts' own init — **sDGNRS** self-subscribes (claimable-only, lootbox mode, flat 1 + 2% reinvest) AND enables BURNIE flip auto-rebuy `takeProfit=0` (full recycle); **Vault** self-subscribes (claimable-only, flat 1, no reinvest, no BURNIE rebuy). Both free-renew via their Whale pass (level-expiring caveat — confirm post-expiry renewal funding at SPEC).

### RM — Legacy AFKing-mode + free ETH-auto-rebuy removal (the v47 half, folded in)

- [ ] **RM-01**: AFKing mode removed entirely — `setAfKingMode`/`_setAfKingMode`/`_deactivateAfKing`/`afKingModeFor`/`afKingActivatedLevelFor`/`deactivateAfKingFromCoin`/`syncAfKingLazyPassFromCoin`, the `afKingMode`/`afKingActivatedLevel` fields, `AFKING_*` constants, `AfKingModeToggled` event, `AfKingLockActive` error all gone. Grep-clean for `afKing`/`AFKING_` (excl. `contracts/test`+`mocks`).
- [ ] **RM-02**: Free ETH auto-rebuy removed entirely — `setAutoRebuy`/`setAutoRebuyTakeProfit` + privates + `autoRebuyTakeProfitFor` + the `AutoRebuyState` struct/mapping + jackpot `_processAutoRebuy`/`_calcAutoRebuy`. ETH jackpot winnings always credit to claimable; the jackpot credit path no longer consumes a VRF word (entropy param dropped).
- [ ] **RM-03**: BURNIE flip auto-rebuy KEPT, collapsed to flat 75bps — `_afKingRecyclingBonus`/`_afKingDeityBonusHalfBpsWithLevel` + deity constants (`AFKING_RECYCLE_BONUS_BPS`/`AFKING_DEITY_*`/`DEITY_RECYCLE_CAP`/`AFKING_KEEP_MIN_COIN`) removed; enable/disable/take-profit/carry/claim still work end-to-end; deity tier dropped.
- [ ] **RM-04**: `_hasAnyLazyPass` KEPT and exposed (PROTO-01) — overrides the standalone-removal dead-code instinct; it is the keeper's pass gate.
- [ ] **RM-05**: Cross-contract cascade pruned — `DegenerusVault.gameSetAutoRebuy`/`gameSetAutoRebuyTakeProfit`/`gameSetAfKingMode` removed (BURNIE `coinSet*` kept); `StakedDegenerusStonk` init `setAfKingMode` replaced by the keeper self-subscribe (SUB-09); `IDegenerusGame`/`IBurnieCoinflip` decls + `settleFlipModeChange` removed.
- [ ] **RM-06**: Storage-layout slot constants re-derived after the `AutoRebuyState` deletion; full suite compiles + green; `KNOWN_ISSUES` and the BURNIE win/loss RNG path (`processCoinflipPayouts`, `rngWord & 1`) unmodified.

### SAFE — Safety / non-brick / faucet

- [ ] **SAFE-01**: Faucet bounded by the three caller-independent locks (purchase-gate + gas-peg + coinflip-credit illiquidity); self-crank/Sybil round-trip ≤ 0; WWXRP 0 reward.
- [ ] **SAFE-02**: Non-brick (BOTH cranks AND `batchPurchase`) — per-item `onlySelf` self-call + try/catch (skip + refund-if-applicable, reward only successes); caller-bounded iteration; cancel un-brickable; no double-buy reentrancy (in-context sub-call rolls back on revert).
- [ ] **SAFE-03**: Concurrency — same-block sweeps process correctly (cursor self-partition + `lastSweptDay`); no double-buy.
- [ ] **SAFE-04**: RNG-freeze intact — resolution stays post-unlock (`RngNotReady` guard), placement guard untouched; the ETH-auto-rebuy removal **retires** freeze obligations (one fewer VRF consumer + three fewer player-mutable in-window inputs) rather than weakening any.

### GAS — Gas efficiency (worst-case-first per `feedback_gas_worst_case`)

- [ ] **GAS-01**: Worst-case-first measurement per work-type before optimizing.
- [ ] **GAS-02**: One `creditFlip`/cranker/tx; one batch value transfer; `level`/`mintPrice` read once/batch.
- [ ] **GAS-03**: Calldata grouped by player; homogeneous per-work-type fns.
- [ ] **GAS-04**: Maximal storage packing; no new per-bet/box storage on the hot placement path.
- [ ] **GAS-05**: Scavenger + Skeptic pass; every removal/packing validated against the security floor.
- [ ] **GAS-06**: Regression bounds (placement hot-path +0%); measured worst-cases calibrate the 0.5 gwei peg.

---

## Deferred / Future (acknowledged, not in v46.0 roadmap)

- **OPEN-E — shared funding source for multi-wallet players** (`Sub.fundingSource` + operator-approval to draw a shared `_poolOf`). Optional enhancement; promote at SPEC only if wanted.
- **OPEN-D bet-cursor** — on-chain per-index bet queue + parameterless `resolveBetsWork()`. Bets stay caller-list (per-bet enqueue tax too steep on the hot path); revisit only if heavy cross-player bet-cranking is expected.

## Out of Scope

| Feature | Reason |
|---------|--------|
| System-chore cranks (advanceGame / jackpot) | Out of the do-work scope; separate concern |
| Degenerette payout-EV / placement changes | Not a v46 surface; placement stays gated |
| Bet/box ledger storage re-key | Hot-path cost; off-chain discovery used instead (OPEN-D deferred) |
| Liquid-BURNIE rewards | Reward must survive coinflip edge (illiquidity is a faucet lock) |
| Off-chain indexer / webpage | Separate frontend track |
| Deity-pass utilities outside the BURNIE recycle bonus | Trait/gold mechanics untouched by RM-03 |
| Deployed-state migration | None — pre-launch redeploy-fresh |

## Traceability

Each requirement maps to exactly one phase (primary verification owner). The full add+remove design is *locked* at Phase 316 SPEC and *consumed* by every downstream phase; the table below records the single phase that owns each requirement's acceptance. Phase 320 (TERMINAL) re-attests all 38 at the closure verdict and owns no requirement primarily.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROTO-01 | Phase 316 | Pending |
| SUB-09 | Phase 316 | Pending |
| RM-04 | Phase 316 | Pending |
| PROTO-02 | Phase 317 | Pending |
| PROTO-03 | Phase 317 | Pending |
| PROTO-04 | Phase 317 | Pending |
| PROTO-05 | Phase 317 | Pending |
| CRANK-01 | Phase 317 | Pending |
| CRANK-02 | Phase 317 | Pending |
| CRANK-03 | Phase 317 | Pending |
| CRANK-04 | Phase 317 | Pending |
| REW-01 | Phase 317 | Pending |
| REW-02 | Phase 317 | Pending |
| REW-03 | Phase 317 | Pending |
| REW-04 | Phase 317 | Pending |
| SUB-01 | Phase 317 | Pending |
| SUB-02 | Phase 317 | Pending |
| SUB-03 | Phase 317 | Pending |
| SUB-04 | Phase 317 | Pending |
| SUB-05 | Phase 317 | Pending |
| SUB-06 | Phase 317 | Pending |
| SUB-07 | Phase 317 | Pending |
| SUB-08 | Phase 317 | Pending |
| RM-01 | Phase 317 | Pending |
| RM-02 | Phase 317 | Pending |
| RM-03 | Phase 317 | Pending |
| RM-05 | Phase 317 | Pending |
| RM-06 | Phase 317 | Pending |
| SAFE-01 | Phase 318 | Pending |
| SAFE-02 | Phase 318 | Pending |
| SAFE-03 | Phase 318 | Pending |
| SAFE-04 | Phase 318 | Pending |
| GAS-01 | Phase 319 | Pending |
| GAS-02 | Phase 319 | Pending |
| GAS-03 | Phase 319 | Pending |
| GAS-04 | Phase 319 | Pending |
| GAS-05 | Phase 319 | Pending |
| GAS-06 | Phase 319 | Pending |

**Coverage:**
- v46.0 requirements: 38 total (PROTO 5 · CRANK 4 · REW 4 · SUB 9 · RM 6 · SAFE 4 · GAS 6)
- Mapped to phases: **38 / 38** (Phase 316: 3 · Phase 317: 25 · Phase 318: 4 · Phase 319: 6 · Phase 320 TERMINAL: re-attests all 38, owns 0 primarily)
- Unmapped / orphaned: **0**
- No requirement maps to more than one phase (no duplicates).

**Per-phase requirement sets:**
- **Phase 316 SPEC** (3): PROTO-01, SUB-09, RM-04 — the cross-half reconciliation (KEEP+EXPOSE `_hasAnyLazyPass`) + protocol-owned sub init design + claimable-only/quantity-unit/skip-kill-identity/whale-expiry SPEC-open resolution. (All 38 requirements' designs are locked here; only these 3 have SPEC as primary owner.)
- **Phase 317 IMPL** (25): PROTO-02..05 + CRANK-01..04 + REW-01..04 + SUB-01..08 + RM-01/02/03/05/06 — the one batched USER-APPROVED contract diff + paired `AfKing` keeper rework.
- **Phase 318 TST** (4): SAFE-01..04 — faucet-resistance, non-brick, concurrency, RNG-freeze; also carries the testable acceptance of SUB-*/CRANK-*/REW-*/RM-* + the removal proofs.
- **Phase 319 GAS** (6): GAS-01..06 — worst-case-first pass + 0.5 gwei peg calibration.
- **Phase 320 TERMINAL** (0 primary): cross-cutting acceptance / closure verdict over all 38 + the add/remove delta-audit + freeze-obligation-retirement attestation.

---
*Requirements defined: 2026-05-23 — milestone v46.0 (combined crank/subscription ADD + legacy AFKing/ETH-auto-rebuy REMOVE). Traceability filled by roadmapper 2026-05-23 — 38/38 mapped, 0 orphaned, 0 duplicated.*
