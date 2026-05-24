# Phase 316: SPEC — Crank + Subscription + Legacy-Removal Design Lock — Research

**Researched:** 2026-05-23
**Domain:** Solidity smart-contract call-graph verification (read-only audit pass; no codebase external-dependency research applies)
**Confidence:** HIGH — every claim below is grep/forge-verified against the live contract HEAD at baseline `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`. Zero `[ASSUMED]` claims; no external packages installed by this phase (Standard Stack / Package Legitimacy / Environment Availability sections are N/A and omitted per the "code-only changes" skip conditions).

---

## Summary

This is the SPEC research substrate for Phase 316, the design-lock phase of the combined v46.0 ADD+REMOVE milestone. The phase deliverable (`316-SPEC.md`, written in a later wave/phase) must satisfy success criterion #5: **zero unverified "by construction" call-graph claims**. The two load-bearing input PLANs claim they were grep-verified at write time (2026-05-23); this research **re-verified every cited `file:line` against live source** and reports each as ✓ MATCH / ✗ DRIFT / ✗ MISSING.

**Headline result:** the REMOVE-half footprint (`PLAN-V47` §5.1–§5.9) is **substantially accurate** — all 13 DegenerusGame function declarations, the storage struct/mapping, the BurnieCoinflip surgery interiors, and the Vault/sStonk/interface decls match the doc to the line in the vast majority of cases. A small number of **minor line drifts** (≤ +4 lines) exist in two of the larger functions (`_addClaimableEth` auto-rebuy block, `_distributePayout` solvency check). The three load-bearing reconciliation claims all **HOLD**: (1) `_hasAnyLazyPass` has exactly two readers, both in afKing-mode machinery → KEEP+EXPOSE (PROTO-01/RM-04) is correct; (2) the keeper (`StreakKeeperV2`) depends on `hasAnyLazyPass` and **nothing** RM-* deletes → the deletion is dependency-safe; (3) the `_processAutoRebuy`/`_calcAutoRebuy` removal does drop a real VRF-`entropy` consumer on the claimable path (SAFE-04 freeze-obligation retirement).

**Two findings the planner MUST surface that the input docs under-stated:**
1. **RM-06 storage shift is bigger than "re-derive a few constants."** `autoRebuyState` is **slot 19** (forge-confirmed). Every state variable at slot 20+ shifts **−1** on deletion. The actual blast radius is **~28 test-side `SLOT_*` constants across ~15 test files**, NOT contract source (the contracts contain **zero numeric slot literals**). Worse: several of those test constants are **already +1 stale** vs the current layout and at least one slot-sensitive test (`LootboxBoonCoexistence.t.sol`) is **already failing at baseline** — so the RM-06 re-derivation is a known-dirty surface, not a clean shift.
2. **The keeper is in a MIXED transitional state, NOT the clean post-rename state `PLAN-CRANK` §9 describes.** §9 claims the `pullForKeeper → burnForKeeper` rename + `mintForKeeper` removal were "done this session (compile-verified)." Live source shows **19× `pullForKeeper`, 5× `mintForKeeper`, only 2× `creditFlip`**, and the OLD caller-supplied `sweep(startIdx, count)` loop — **no `sweepCursor`, no `reinvestPct`, no `windowPaid`**. The §9 "remaining IMPL work" is genuinely unbuilt; the SPEC must lock against the keeper's *intended* end-state, not its current source.

**Primary recommendation:** Structure the SPEC into 4 plans (ADD-design, REMOVE-footprint+reconciliation, open-item-resolution, call-graph-attestation) and treat this RESEARCH.md's verification table as the attestation appendix the SPEC's criterion #5 references. Lock OPEN-B/lootbox-denomination/whale-expiry from the source facts gathered here; flag the box-cursor VRF-rotation-index coupling (OPEN-D) as the one design landmine.

---

## Project Constraints (from CLAUDE.md / MEMORY / config)

No `./CLAUDE.md` exists in the audit repo root. The governing constraints come from the user's global `~/.claude/CLAUDE.md` + the project MEMORY feedback files + `.planning/config.json`:

- **READ-ONLY phase.** Zero `contracts/` and zero `test/` mutations (success criterion #5, ROADMAP). This research made zero edits — only `forge inspect` (read-only) and `grep`.
- **Security/RNG-non-manipulability is the hard floor** (`feedback_security_over_gas`). Reject any gas optimization that weakens an invariant.
- **Only read contracts from `contracts/`** (`feedback_contract_locations`). All cited paths below are canonical; stale copies in `testing/`, `degenerus-contracts/`, `forge-out/`, `cache/` were ignored.
- **Slash commands use the HYPHEN form** (`feedback_slash_command_hyphen_form`): write `/gsd-plan-phase`, not `/gsd:plan-phase`.
- **No code edits without explicit approval** (`feedback_wait_for_approval`, `feedback_manual_review_before_push`); the milestone ships as ONE batched USER-APPROVED diff at IMPL (Phase 317) — this SPEC informs design only.
- **Comments describe what IS, never what changed** (`feedback_no_history_in_comments`) — relevant when the SPEC dictates comment edits at IMPL.
- **`commit_docs: true`, `nyquist_validation: false`** (config.json) → the Validation Architecture section is OMITTED below per its explicit skip condition. `.planning/` is gitignored — force-add planning docs.
- **Call-graph "by construction" claims MUST be grep-verified pre-patch** (`feedback_verify_call_graph_against_source`) — this is the entire mission of this phase.

---

## User Constraints (from REQUIREMENTS.md / ROADMAP — no CONTEXT.md exists)

No `*-CONTEXT.md` exists for Phase 316 (no `/gsd-discuss-phase` was run). The binding decisions are the locked items in `REQUIREMENTS.md` + `PLAN-CRANK §12.6` (RESOLVED, user 2026-05-23):

### Locked Decisions (treat as CONTEXT-equivalent; SPEC must honor verbatim)
- **PROTO-01/RM-04 = KEEP+EXPOSE `_hasAnyLazyPass`, delete the rest of afKing.** Overrides the dead-code-deletion instinct. (REQUIREMENTS RM-04; PLAN-V47 §1.5.1)
- **OPEN-F = COEXIST with max-semantics, NOT replace.** `effective = max(dailyQuantity≥1, floor(claimable × reinvestPct / price))`. Both pack into one flags byte + `reinvestPct uint8` (no new slot). flat=0 disallowed (min 1). (PLAN-CRANK §12.6)
- **Funding waterfall = the EXISTING `drainGameCreditFirst=true` model** (Claimable / Combined / DirectEth + InsufficientPool skip). Claimable-only = empty `_poolOf` (no new flag). (PLAN-CRANK §12.6)
- **Two-tier skip-kill BY IDENTITY.** NORMAL subs cancel on funding skip via in-sweep swap-pop; `VAULT` + `sDGNRS` EXEMPT, keyed on **un-spoofable pinned address constants** (NEVER a player-settable flag). (PLAN-CRANK §12.6, REQUIREMENTS SUB-06)
- **Protocol-owned subs at init (SUB-09):** sDGNRS = claimable-only, lootbox, `dailyQuantity=1` + `reinvestPct=2%` + `setCoinflipAutoRebuy(self,true,0)`; Vault = claimable-only, lootbox, `dailyQuantity=1`, no reinvest, no BURNIE rebuy. Both free-renew via Whale pass.
- **Reward = coinflip-credit (`creditFlip`), gas-pegged at 0.5 gwei via the `_ethToBurnieValue`/advanceGame idiom; charge = `burnForKeeper` (burn, all-or-nothing).** No caller restriction. WWXRP (`currency==3`) = zero reward.
- **Keeper moves in-tree as `AfKing`** (separate contract, audited in-tree). Rename `STREAK_KEEPER_V2`→`AF_KING`, `onlyStreakKeeper`→`onlyAfKing`.

### Claude's Discretion (SPEC author decides, grounded in this research)
- OPEN-B price-unavailable edge formula (source facts below: `_ethToBurnieValue` already guards; `priceForLevel` never returns 0).
- OPEN-C reentrancy disposition (CEI-proof vs explicit guard — facts below favor CEI).
- OPEN-D bet-cursor: **deferred** per REQUIREMENTS; boxes → cursor; bets → caller-list.

### Deferred / OUT OF SCOPE (ignore)
- OPEN-E shared funding source (promote at SPEC only if user wants — default OUT).
- OPEN-D bet-cursor on-chain queue (per-bet enqueue tax too steep).
- System-chore cranks, degenerette EV/placement changes, liquid-BURNIE rewards, off-chain indexer, deity utilities beyond BURNIE recycle, deployed-state migration.

---

## Phase Requirements

| ID | Description (REQUIREMENTS.md) | Research Support (this doc) |
|----|-------------------------------|------------------------------|
| **PROTO-01** | Expose `DegenerusGame.hasAnyLazyPass(address) external view` (kept private `_hasAnyLazyPass` at `:1610`); reconciles RM-04 | §"`_hasAnyLazyPass` Reader-Set Finding" — definitively 2 readers, both afKing-mode; KEEP+EXPOSE confirmed. Body reads Deity bit 184 + FROZEN_UNTIL_LEVEL 128 via `BitPackingLib` constants. |
| **SUB-09** | Protocol-owned subs at init — sDGNRS + Vault self-subscribe, claimable-only, lootbox, free-renew via Whale pass | §"Open-Item Resolution Facts" — sStonk init at `:360-366`; whale-pass renewal mechanics resolved; "1 price lootbox" denomination resolved (`TICKET_SCALE=400`). |
| **RM-04** | `_hasAnyLazyPass` KEEP + expose (PROTO-01) — overrides dead-code instinct | Same as PROTO-01. The keeper-dependency finding proves WHY it must be kept (keeper's sole pass gate). |

(All 38 requirements' designs are locked at this phase; only these 3 have SPEC as primary verification owner. The Call-Graph Verification Table below is the substrate the planner needs to lock RM-01..06 + the ADD design for downstream phases 317/318/319.)

---

## 1. Call-Graph Verification Table (HEADLINE DELIVERABLE)

All paths canonical (`/home/zak/Dev/PurgeGame/degenerus-audit/contracts/...` or `/home/zak/Dev/PurgeGame/degenerus-utilities/contracts/StreakKeeperV2.sol`). Verdicts: ✓ = doc line matches live source; ✗ DRIFT = present but at a different line; ✗ MISSING = not found.

### 1.1 `DegenerusGame.sol` (PLAN-V47 §5.1)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `setAutoRebuy` | 1495 | 1495 | ✓ |
| `setAutoRebuyTakeProfit` | 1504 | 1504 | ✓ |
| `_setAutoRebuy` | 1512 | 1512 | ✓ |
| `_setAutoRebuyTakeProfit` | 1524 | 1524 | ✓ |
| `autoRebuyTakeProfitFor` | 1543 | 1543 | ✓ |
| `setAfKingMode` | 1559 | 1559 | ✓ |
| `_setAfKingMode` | 1569 | 1569 | ✓ |
| `_hasAnyLazyPass` | 1610 | 1610 | ✓ |
| `afKingModeFor` | 1624 | 1624 | ✓ |
| `afKingActivatedLevelFor` | 1631 | 1631 | ✓ |
| `deactivateAfKingFromCoin` | 1641 | 1641 | ✓ |
| `syncAfKingLazyPassFromCoin` | 1654 | 1654 | ✓ |
| `_deactivateAfKing` | 1670 | 1670 | ✓ |
| event `AutoRebuyToggled` | 1476 | 1476 | ✓ |
| event `AutoRebuyTakeProfitSet` | 1479 | 1479 | ✓ |
| event `AfKingModeToggled` | 1482 | 1482 | ✓ |
| error `AfKingLockActive` | 92 | 92 (decl); used at 1676; doc-ref at 1558 | ✓ |
| const `AFKING_KEEP_MIN_ETH` | 151 | 151 (also used 1535/1584/1585) | ✓ |
| const `AFKING_KEEP_MIN_COIN` | 154 | 154 (also used 1588/1589) | ✓ |
| const `AFKING_LOCK_LEVELS` | 157 | 157 (also used 1675) | ✓ |
| `coinflip.settleFlipModeChange` cross-calls | 1603, 1678 | 1603, 1678 | ✓ |
| `_hasAnyLazyPass` reader at `_setAfKingMode` | 1580 | 1580 | ✓ |
| `_hasAnyLazyPass` reader at `syncAfKingLazyPassFromCoin` | 1660 | 1660 | ✓ |

### 1.2 `storage/DegenerusGameStorage.sol` (PLAN-V47 §5.2)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `struct AutoRebuyState` | 910–919 | 910 (struct opens; body 910–919) | ✓ |
| `mapping autoRebuyState` | 926 | 926 | ✓ |
| **forge storage slot of `autoRebuyState`** | (not in doc) | **slot 19** | NEW (see §4) |

### 1.3 `modules/DegenerusGameJackpotModule.sol` (PLAN-V47 §5.3)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `_addClaimableEth` | 788 | 788 | ✓ |
| auto-rebuy block inside `_addClaimableEth` | 798–806 | **800–808** | ✗ DRIFT (+2; cosmetic) |
| `_processAutoRebuy` | 822 | 822 | ✓ |
| `_budgetToTicketUnits` | 861 | 861 | ✓ |
| `entropy` param of `_addClaimableEth` (3-arg form) | (cited as cascade) | sig at 788–795 takes `(beneficiary, weiAmount, entropy)` | ✓ |
| `_addClaimableEth` callers passing entropy | (implied) | 1430 (`entropyState`), 1530 (`entropy`), 1571 + 1583 (`entropy`), 2132, 2165 | ✓ (5 jackpot call sites; see §"entropy cascade") |
| `JackpotEthWin` event carries `rebuyLevel/rebuyTickets` | (implied by removal) | event decl 69; emitted 1431-1438, 1531 | ✓ — **event signature changes on removal** |

### 1.4 `modules/DegenerusGamePayoutUtils.sol` (PLAN-V47 §5.4)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `_calcAutoRebuy` | 51 | 51 | ✓ |
| `struct AutoRebuyCalc` | (referenced) | 19 | ✓ |
| afKingMode bonus selector `state.afKingMode ? bonusBpsAfKing : bonusBps` | 83 | 83 | ✓ |
| entropy use in level-offset roll | 67–84 | `keccak256(abi.encode(entropy, beneficiary, weiAmount)) & 3` at ~70 | ✓ |
| `_budgetToTicketUnits` location | "JackpotModule:861" | 861 (JackpotModule, not PayoutUtils) | ✓ (doc correctly attributes to JackpotModule) |

### 1.5 `BurnieCoinflip.sol` (PLAN-V47 §5.5)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `settleFlipModeChange` | 217 | 217 | ✓ |
| rebet-bonus afKing branch | 288–310 | branch body 294–308 (`afKingModeFor` at 300, `hasDeityPass` 302, `_afKingDeityBonus` 304, `_afKingRecyclingBonus` 305) | ✓ |
| `_claimCoinflipsInternal` | 416 | 416 | ✓ |
| `syncAfKingLazyPassFromCoin` call in claim | 422 | 422 | ✓ |
| `afKingActive`/`hasDeityPass`/`deityBonusHalfBps` block | 434–443 | 434–443 | ✓ |
| recycle branch collapse target | 539–548 | 540–548 (`afKingActive ? _afKingRecyclingBonus : _recyclingBonus`) | ✓ |
| `_setCoinflipAutoRebuy` | (referenced) | 722 | ✓ |
| `_setCoinflipAutoRebuyTakeProfit` | (referenced) | 776 | ✓ |
| `deactivateAfKingFromCoin` calls | 754, 766, 793 | 754, 766, 793 | ✓ |
| `AFKING_KEEP_MIN_COIN` floor checks | 753, 792 | 753, 792 | ✓ |
| `_afKingRecyclingBonus` | 1062 | 1062 | ✓ |
| `_afKingDeityBonusHalfBpsWithLevel` | 1078 | 1078 | ✓ |
| const `AFKING_RECYCLE_BONUS_BPS` | 130 | 130 | ✓ |
| const `AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS` | 131 | 131 | ✓ |
| const `AFKING_DEITY_BONUS_MAX_HALF_BPS` | 132 | 132 | ✓ |
| const `DEITY_RECYCLE_CAP` | 133 | 133 | ✓ |
| const `AFKING_KEEP_MIN_COIN` | 140 | 140 | ✓ |
| **KEEP** const `RECYCLE_BONUS_BPS` (=75) | 129 | 129 | ✓ |
| **KEEP** `_recyclingBonus` | 1051 | 1051 (`amount * RECYCLE_BONUS_BPS / BPS_DENOMINATOR` at 1055) | ✓ |
| **KEEP** win/loss `rngWord & 1` | (must not modify) | `processCoinflipPayouts` 805; `(rngWord & 1)==1` at 837 | ✓ |

### 1.6 `interfaces/IDegenerusGame.sol` (PLAN-V47 §5.6)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `afKingModeFor` | 274 | 274 | ✓ |
| `afKingActivatedLevelFor` | 279 | 279 | ✓ |
| `deactivateAfKingFromCoin` | 283 | 283 | ✓ |
| `syncAfKingLazyPassFromCoin` | 288 | 288 | ✓ |
| `setAutoRebuy`/`setAutoRebuyTakeProfit`/`setAfKingMode` decls (doc said "verify whether present") | verify | **NOT declared in IDegenerusGame** | ✗ MISSING (resolves the doc's open verify — these are NOT in this interface; they ARE in Vault's local interface, see §1.8) |
| `hasDeityPass` (KEEP — read by coinflip) | (not flagged) | 376 | ✓ (KEEP — not in removal scope) |

### 1.7 `interfaces/IBurnieCoinflip.sol` (PLAN-V47 §5.7)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| `settleFlipModeChange` | 85 | 85 | ✓ |
| `creditFlip` (ADD-side PROTO-03 dependency — already present!) | (not in §5.7) | **115** (+ `creditFlipBatch` 122) | NEW — PROTO-03 interface decl ALREADY EXISTS |

### 1.8 `DegenerusVault.sol` (PLAN-V47 §5.8)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| local decl `setAutoRebuy` | 47 | 47 | ✓ |
| local decl `setAutoRebuyTakeProfit` | 49 | 49 | ✓ |
| local decl `setAfKingMode` | 51 | 51 | ✓ |
| wrapper `gameSetAutoRebuy` | 627→628 | decl 627, body call 628 | ✓ |
| wrapper `gameSetAutoRebuyTakeProfit` | 634→635 | decl 634, body 635 | ✓ |
| wrapper `gameSetAfKingMode` | 643→648 | decl 643, body 648 | ✓ |
| **KEEP** `coinSetAutoRebuy` | (KEEP) | 685 | ✓ |
| **KEEP** `coinSetAutoRebuyTakeProfit` | (KEEP) | 692 | ✓ |

### 1.9 `StakedDegenerusStonk.sol` (PLAN-V47 §5.9)

| Symbol | Doc claim | Live | Verdict |
|--------|-----------|------|---------|
| local decl `setAfKingMode` | 13 | 13 | ✓ |
| init call `game.setAfKingMode(address(0), true, 10 ether, 0)` | 361 | 361 (preceded by `game.claimWhalePass(address(0))` at 360) | ✓ |
| **NEW** second whale-pass entry `gameClaimWhalePass()` | (not in doc) | **404** (`game.claimWhalePass(address(0))`) | NEW — see §5 whale-renewal |

### 1.10 ADD-side anchors — `_ethToBurnieValue` + advanceGame bounty idiom (verification item #10)

| Symbol | Doc/PLAN claim | Live | Verdict |
|--------|-----------|------|---------|
| `_ethToBurnieValue` | "advanceGame uses it" | `DegenerusGameMintModule.sol:1412` (private pure; **`if (amountWei==0 \|\| priceWei==0) return 0`** then `(amountWei * PRICE_COIN_UNIT)/priceWei`) | ✓ — and **OPEN-B-safe by construction** |
| advanceGame per-chunk bounty idiom | ~194/480 | `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / PriceLookupLib.priceForLevel(lvl)` via `coinflip.creditFlip` at AdvanceModule **190-194, 228-230, 478-480, 886-888** | ✓ |
| escalating `bountyMultiplier` (2/4/6×) | ~244-256 | AdvanceModule 244 (`=1`), 252 (`=6`), 254 (`=4`), 256 (`=2`) | ✓ |
| `ADVANCE_BOUNTY_ETH` const | (idiom) | AdvanceModule:150 (`0.005 ether`) | ✓ |
| **NOTE** advanceGame idiom does NOT call `_ethToBurnieValue` | — | inlines the division with **NO `mp==0` guard** ("trust-the-protocol D13-01") | NEW — see OPEN-B disposition |

### 1.11 Resolve/placement gates the crank reuses (verification item #11)

| Symbol | Doc/PLAN claim | Live | Verdict |
|--------|-----------|------|---------|
| `resolveDegeneretteBets` | `DegenerusGame.sol:743` | 743 | ✓ |
| `_requireApproved` | (relaxed for resolve) | `DegenerusGame.sol:452`; `DegeneretteModule.sol:131` | ✓ |
| `_resolvePlayer` | (mirror for subscribe consent) | `DegenerusGame.sol:458`; `DegeneretteModule.sol:141` | ✓ |
| `resolveBets(player, betIds)` (owner self-resolve) | (bet caller-list base) | `DegeneretteModule.sol:389` | ✓ |
| bet `delete degeneretteBets[player][betId]` | `DegeneretteModule.sol:580` | 580 | ✓ |
| bet `RngNotReady` guard `if (rngWord == 0)` | (resolve guard) | `DegeneretteModule.sol:578`; error decl 49 | ✓ |
| placement twin `lootboxRngWordByIndex[index] != 0` → `RngNotReady` | (freeze invariant) | `DegeneretteModule.sol:452` | ✓ |
| box-zeroing `lootboxEth[index][player] = 0` | `LootboxModule.sol:~530` | 530 (open path); 531 also zeroes `lootboxEthBase` | ✓ |
| box `RngNotReady` resolve guard | (preserved) | `LootboxModule.sol:485, 567` (`if (rngWord==0) revert RngNotReady`); error 45 | ✓ |
| `openLootBox` (already permissionless, no caller gate) | (CRANK-03) | `LootboxModule.sol:477` | ✓ |
| `_distributePayout` frozen-pool solvency check | `DegeneretteModule.sol:742` | **`_distributePayout` decl 705; solvency `if (uint256(pFuture) < ethShare) revert E()` at ~738** | ✗ DRIFT (decl 705, check ~738; doc's 742 is inside the body, slightly off) |
| separate `_addClaimableEth(player, weiAmount)` (no-entropy overload) | (Degenerette path) | `DegeneretteModule.sol:1117` (2-arg; distinct from JackpotModule's 3-arg) | NEW — two overloads exist; only the JackpotModule 3-arg one carries the auto-rebuy/entropy path |
| `lootboxEthBase==0` first-deposit signal (OPEN-D box-cursor enqueue anchor) | (PLAN §12.6) | written `MintModule:1004-1008`; the `existingBase` read at 1004 is the first-deposit detector; zeroed `LootboxModule:531` | ✓ |

### 1.12 Keeper `StreakKeeperV2.sol` (verification item #12 — the SPEC-316 dependency check)

| Property | Doc/PLAN claim | Live | Verdict |
|----------|----------------|------|---------|
| References ANY RM-deleted symbol (`syncAfKingLazyPassFromCoin`/`afKingModeFor`/`setAfKingMode`/`autoRebuyState`/`settleFlipModeChange`/etc.) | "does NOT depend" | **ZERO matches** | ✓ — dependency-safe |
| Pass gate path | `IGame.hasAnyLazyPass` | `hasAnyLazyPass(player)` calls at 671 (subscribe gate), 974 (sweep renewal gate); doc-refs 15/310/322/585/613/627/823/971 | ✓ — sole pass gate = the PROTO-01 view |
| Funding waterfall | `:1068-1106` (Claimable/Combined/DirectEth + InsufficientPool skip) | **1076-1108** (`drainGameCreditFirst` 3-case + `_poolOf[player] < msgValue` skip at 1100) | ✓ (≈, +8 line drift) |
| CEI: pool debit before purchase, lastSweptDay after | (OPEN-C analog) | `_poolOf[player] -= msgValue` (1104) → `purchase{value}` (1110) → `sub.lastSweptDay = today` (1115) | ✓ — debit-before-call CEI holds |
| `subscribe` signature | (PLAN §12.6 says add reinvestPct) | `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` at 632 — **no reinvestPct yet** | ✗ DRIFT vs intended end-state |
| sweep model | PLAN §5 wants `sweep(maxCount)` + internal `sweepCursor` | live = `sweep(uint256 startIdx, uint256 count)` at 931 — **caller-supplied range, no internal cursor** | ✗ DRIFT vs intended end-state |
| `pullForKeeper`→`burnForKeeper` rename "done this session" | PLAN §9 | **19× `pullForKeeper`, 5× `burnForKeeper` (doc-comments), 5× `mintForKeeper` still present** | ✗ DRIFT — rename NOT actually applied to live source |
| `creditFlip` bounty wired | PLAN §9 "done" | only **2× `creditFlip`** (partial) | ✗ DRIFT — partial |
| `lastSweptDay` idempotency | (SUB-03 backstop) | field at 31; `if (sub.lastSweptDay >= today)` skip at 962 | ✓ (already exists) |
| `_removeFromSet` swap-pop | (SUB-07 reclaim) | 707, 1013 (auto-pause removal) | ✓ (already exists) |
| `reinvestPct` / `windowPaid` | PLAN wants both | **neither exists** | ✗ MISSING (unbuilt) |
| `TICKET_SCALE` (denomination) | PLAN "1 price lootbox" | `=400` at 387; `ticketQuantity = TICKET_SCALE * dailyQuantity`; lootbox mode `lootBoxAmt = cost` | ✓ |

**Keeper drift verdict:** the keeper's CURRENT source is a **transitional/mixed state** that does NOT match `PLAN-CRANK §9`'s claimed post-rework state. The dependency check (does it touch RM-deleted symbols?) is **clean** — that's the load-bearing answer. But the SPEC must explicitly note that the keeper's §9 "remaining IMPL work" (cursor, reinvestPct, windowPaid, batchPurchase switch, pull→burn rename, full creditFlip) is **genuinely unbuilt**, and lock the design against the intended end-state, citing this drift so the plan-checker does not treat §9 "done this session" as ground truth.

---

## 2. `_hasAnyLazyPass` Reader-Set Finding (PROTO-01 / RM-04 hinge)

**DEFINITIVE: the claim holds.** `grep -rn '_hasAnyLazyPass' contracts/` (excl test/mocks) returns exactly **three** lines:
- `DegenerusGame.sol:1610` — the declaration (`private view returns (bool)`).
- `DegenerusGame.sol:1580` — reader inside `_setAfKingMode` (`if (!_hasAnyLazyPass(player)) revert E();`).
- `DegenerusGame.sol:1660` — reader inside `syncAfKingLazyPassFromCoin` (`if (_hasAnyLazyPass(player)) return true;`).

Both readers are inside afKing-**mode** machinery slated for deletion → after RM-01 the private function is dead code **except for the keeper's external need**. Therefore **KEEP + EXPOSE as `hasAnyLazyPass` (PROTO-01) is correct**, and the keeper-dependency finding (§3) proves it is *required*, not optional.

**What `_hasAnyLazyPass` actually reads** (verified body, 1610–1619):
```solidity
uint256 packed = mintPacked_[player];
if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;   // Deity (bit 184)
uint24 frozenUntilLevel = uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
return frozenUntilLevel > level;                                          // Whale-bundle / Lazy (FROZEN_UNTIL_LEVEL, bits 128-151)
```
Verified constants (`contracts/libraries/BitPackingLib.sol`): `HAS_DEITY_PASS_SHIFT = 184` (:71), `FROZEN_UNTIL_LEVEL_SHIFT = 128` (:63), `MASK_24 = (1<<24)-1` (:35). The doc's bit-layout claim (Deity=184, FROZEN_UNTIL_LEVEL=128-151, Lazy=FROZEN_UNTIL_LEVEL) is **exactly correct**. The function returns "Deity OR (Whale/Lazy active i.e. frozenUntilLevel > level)" = "any of the three" — matching SUB-01's pass definition. 1 SLOAD common case (Deity hit), 2 SLOADs worst (mintPacked_ + level), zero external calls.

**SPEC lock:** PROTO-01 = rename-to-external only (`private` → `external view`, no body change). RM-04 = the deletion of 1580/1660's surrounding functions does not touch the body. No `[ASSUMED]` — fully source-grounded.

---

## 3. Keeper Dependency Finding (the explicit SPEC-316 check)

**ANSWER: `StreakKeeperV2` does NOT depend on any symbol RM-01..06 deletes.** A grep of the keeper for the entire RM-deletion symbol set (`syncAfKingLazyPassFromCoin`, `afKingModeFor`, `afKingActivatedLevelFor`, `setAfKingMode`, `deactivateAfKingFromCoin`, `setAutoRebuy`, `setAutoRebuyTakeProfit`, `autoRebuyState`, `AutoRebuyState`, `_processAutoRebuy`, `_calcAutoRebuy`, `settleFlipModeChange`, `_afKingRecyclingBonus`, `_afKingDeityBonus`, `gameSetAutoRebuy`, `gameSetAfKingMode`) returns **zero matches**.

The keeper's ONLY game-side coupling to the afKing namespace is **`IGame.hasAnyLazyPass(player)`** — which is the **kept-and-exposed** PROTO-01 view, not a deleted symbol. Confirmed call sites: line 671 (subscribe-time gate) and line 974 (monthly-renewal sweep gate, the optimistic "fire only inside renewal branch" D15-08 pattern). The keeper also depends on `purchase`, `claimableWinningsOf`, `creditFlip`/`pullForKeeper`/`mintForKeeper` (PROTO-side, not afKing). **The lazy-pass sync (`syncAfKingLazyPassFromCoin`) the doc worried about is NOT used by the keeper** — that sync is a coinflip↔game internal, deleted safely.

**Conclusion for the SPEC:** the v46 deletion is dependency-safe for the keeper *provided PROTO-01 ships in the same diff*. The keeper's gate survives v47/RM-* unchanged. This is the cleanest possible resolution of `PLAN-CRANK §9`'s "design the gate to survive v47" concern: the gate already reads only the surviving `hasAnyLazyPass`.

**Caveat the SPEC must record:** the keeper's CURRENT source still calls `IBurnie.pullForKeeper` / `mintForKeeper` (against the game-side `BurnieCoin`, which has NEITHER function yet — deferred-selector by design per PLAN §14). PROTO-02 must add `burnForKeeper` to `BurnieCoin`, and the keeper's IMPL rework (Phase 317, utilities side) must switch its calls to it. This is a PROTO-side interface obligation, not an afKing-deletion dependency.

---

## 4. Storage-Layout Slot-Shift Map (RM-06)

**Authoritative source:** `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout` (read-only; forge 1.6.0-nightly available at `~/.foundry/bin/forge`).

**`autoRebuyState` is at slot 19.** Deleting it shifts **every state variable at slot ≥ 20 down by exactly −1**. The relevant region (current → post-deletion):

| Var | Current slot | Post-deletion slot |
|-----|--------------|--------------------|
| `lootboxEth` | 15 | 15 (unchanged — before 19) |
| `presaleStatePacked` / `gameOverStatePacked` / `whalePassClaims` | 16 / 17 / 18 | unchanged |
| **`autoRebuyState`** | **19** | **(deleted)** |
| `lootboxEthBase` | 20 | 19 |
| `operatorApprovals` | 21 | 20 |
| `levelPrizePool` | 22 | 21 |
| `affiliateDgnrsClaimedBy` | 23 | 22 |
| `levelDgnrsAllocation` | 24 | 23 |
| `levelDgnrsClaimed` | 25 | 24 |
| `deityPass*` block | 26-30 | 25-29 |
| `earlybird*` / `resumeEthPool` | 31-33 | 30-32 |
| `vrfCoordinator` / `vrfKeyHash` / `vrfSubscriptionId` | 34 / 35 / 36 | 33 / 34 / 35 |
| `lootboxRngPacked` | 37 | 36 |
| `lootboxRngWordByIndex` | 38 | 37 |
| `lootboxDay` | 39 | 38 |
| `lootboxPurchasePacked` | 40 | 39 |
| `lootboxBurnie` | 41 | 40 |
| `deityBoonDay` | 42 | 41 |
| `degeneretteBets` | 45 | 44 |
| `lootboxEvBenefitUsedByLevel` | 47 | 46 |
| `boonPacked` | 61 | 60 |
| (all subsequent vars) | N | N−1 |

**The contract source contains ZERO numeric slot literals** — verified: no `sload(N)`, no `.slot := N`, no `SLOT_* = N` constants in `contracts/`. The only assembly `.slot` uses are struct-member names (`bp.slot0`/`bp.slot1`) and `traitBurnTicket.slot` (a mapping's own slot, used for keccak keying — re-resolves correctly after reorder since mappings hash their declared slot). **So no contract code breaks on the shift** — RM-06's "re-derive slot constants" is **entirely a test-side problem.**

**Test-side blast radius (~28 constants across ~15 files).** Files with hardcoded game-storage slot constants / `vm.load`/`vm.store`: `BafRebuyReconciliation`, `BafFarFutureTickets`, `RngIndexDrainBinding`(+handler), `DegeneretteFreezeResolution`, `AdvanceGameRewrite`, `AffiliateDgnrsClaim`, `QueueDoubleBuffer`, `VRFCore`, `StorageFoundation`, `LootboxBoonCoexistence`, `LootboxRngLifecycle`, `VrfRotationOrphanIndex`, `StakedStonkRedemption`, `RngLockRotationDeterminism`, `RedemptionEdgeCases`, `VrfRotationLiveness`, `JackpotCombinedPool`, `TicketLifecycle`, `RngLockDeterminism`, `VRFStallEdgeCases`, `RedemptionInvariants.inv`, `RedemptionHandler`. Constants that reference slot ≥ 20 (e.g. `SLOT_LOOTBOX_MAPPING=38`, `SLOT_LR_INDEX=37`, `SLOT_RNG_WORD...`, `SLOT_PENDING_BY_DAY=11`(unaffected, <19), `SLOT_PENDING_REDEMPTIONS=7`(unaffected)) must each be re-checked and decremented where slot ≥ 20.

**⚠ Compounding hazard — the test constants are ALREADY stale.** `LootboxBoonCoexistence.t.sol` declares `SLOT_LOOTBOX_BASE=21`, `SLOT_LOOTBOX_RNG_IDX=38`, `SLOT_LOOTBOX_WORD=39`, `SLOT_LOOTBOX_DAY=40` — but the LIVE layout (with `autoRebuyState` still present) puts `lootboxEthBase=20`, `lootboxRngPacked=37`, `lootboxRngWordByIndex=38`, `lootboxDay=39`. The test constants are **already +1 high** vs current, and `forge test --match-test test_lootboxBoonAppliedDespiteExistingCoinflipBoon` **FAILS at baseline** ("At least one lootbox should have rolled a non-coinflip boon"). This is one of the "unrelated pre-existing baseline failures" the project memory notes for the suite. **Implication for RM-06:** the deletion makes `lootboxEthBase` etc. move to slot 19/36/37/38 — i.e. the re-derivation cannot simply "decrement by 1" blindly, because some constants are off by +1 in the wrong direction already. **RM-06 must re-run `forge inspect ... storage-layout` against the post-deletion contract and rewrite each test SLOT_* constant from that authoritative output**, not patch-by-arithmetic. The TST phase (318) owns proving "no NEW failures vs baseline," and this stale-baseline interaction must be called out so a re-derivation does not get blamed for the pre-existing `LootboxBoonCoexistence` failure.

**SPEC lock for RM-06:** (a) contract source = zero slot work; (b) test SLOT_* constants = full re-derivation from `forge inspect` on the post-deletion contract, file-by-file; (c) baseline-failure ledger must be captured BEFORE the diff so the delta is attributable.

---

## 5. Open-Item Resolution Facts (source evidence to lock each SPEC-open)

### OPEN-B — price-unavailable edge (reward → 0, never revert)
- `_ethToBurnieValue(amountWei, priceWei)` (`MintModule:1412`) **already guards**: `if (amountWei == 0 || priceWei == 0) return 0;` then `(amountWei * PRICE_COIN_UNIT) / priceWei`. **Mirror this idiom for the crank reward → OPEN-B is solved by reusing the guarded helper.**
- `PriceLookupLib.priceForLevel(uint24)` (`:21`) is `pure` and **never returns 0** (every branch returns ≥ 0.01 ether). So if the crank pegs to `priceForLevel(level)` rather than the external `mintPrice()`, div-by-zero is structurally impossible.
- **Contrast:** the `advanceGame` bounty idiom (AdvanceModule:190-194) inlines `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / priceForLevel(lvl)` with NO zero-guard ("trust-the-protocol D13-01") — safe only because `priceForLevel` can't be 0. **SPEC decision:** prefer the guarded `_ethToBurnieValue` form (defends against a future `mintPrice()`-sourced price), OR explicitly peg to `priceForLevel` and document the non-zero invariant. Either way: reward → 0, never revert settlement. Relevant skill: none external; pure-arithmetic.

### OPEN-C — batchPurchase reentrancy (CEI vs guard)
- `DegenerusGame` has **no `nonReentrant` modifier / ReentrancyGuard** anywhere (the only "locked" matches are `RngLocked` / afKing-lock, unrelated). Protection is **CEI throughout**: e.g. `claimablePool -= uint128(payout)` at `DegenerusGame.sol:1408` is explicitly commented "CEI: update state before external call"; ETH sends via `.call{value}` at 2005/2022/2043.
- The keeper's existing per-player loop already does CEI: `_poolOf[player] -= msgValue` (debit) BEFORE `purchase{value}` (external), `lastSweptDay = today` AFTER.
- **Disposition lean (Claude's discretion):** CEI-proof is the existing protocol convention; `batchPurchase`'s per-player try/catch + slice-refund + a once-at-entry batch debit + post-loop day-stamp should satisfy "no double-buy via reentrant sweep/cancel" without a new guard — BUT the SPEC should require the IMPL to trace the full mint→lootbox→prize-pool→EV-cap→quest callback chain for any external call that re-enters before the day-stamp, and add a guard only if a re-entrant path is found. **Route to the `contract-auditor` skill at IMPL/TST** for the CEI-vs-guard proof (this is the highest-scrutiny ADD surface alongside `burnForKeeper`/`creditFlip` authority).

### "1 price lootbox" denomination
- Keeper `useTickets` (default `false` = lootbox mode). Lootbox mode: `lootBoxAmt = cost`, where `cost = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()`. Ticket mode: `ticketQuantity = TICKET_SCALE(=400) * dailyQuantity`, calibrated so `400 * qty * mintPrice / 400 == mintPrice * qty`.
- **Therefore `dailyQuantity` is denominated in price-units: 1 unit = 1 `mintPrice` worth = one 1-price lootbox.** The PLAN §12.6 "flat number of tickets worth = price-denominated quantity" is grounded. The `max(dailyQuantity, floor(claimable × reinvestPct / price))` comparison is unit-consistent (both sides in price-units). **OPEN resolved.**
- Lootbox-floor skip path exists: `if (!useTickets && cost < LOOTBOX_MIN) → PlayerSkipped(player, 4)` (keeper:449/289). The SPEC's "skip vs kill" must distinguish this transient lootbox-floor skip from a funding skip.

### Whale-pass-expiry renewal for protocol subs (sDGNRS / Vault)
- `claimWhalePass(player)` (`WhaleModule:1004`): if `whalePassClaims[player] == 0` → **early-return (no-op)**; else clears the queue and `_applyWhalePassStats(player, level+1)` + `_queueTicketRange(... 100 levels ...)`. `_applyWhalePassStats` advances `FROZEN_UNTIL_LEVEL` (WhaleModule 213-231, capped at `currentLevel + 7`, :428). **Reverts on `_livenessTriggered()`.**
- sStonk has TWO claim sites: init at `:360` (`game.claimWhalePass(address(0))` BEFORE the `setAfKingMode` at 361) AND a public re-claim `gameClaimWhalePass()` at `:404`. Vault has `gameClaimWhalePass()` at `:580` (owner-gated) → `claimWhalePass(address(this))` at 582.
- **The expiry problem is REAL and unresolved by source alone:** `claimWhalePass` only EXTENDS the freeze if `whalePassClaims[player] > 0` (queued half-passes). It does not self-renew indefinitely. **SPEC must lock where sDGNRS/Vault's `whalePassClaims` keep accruing post-initial-expiry** (e.g. they earn whale passes through gameplay, OR they fall back to `burnForKeeper` once the pass lapses, OR they hold a permanent Deity bit). If none accrues, the protocol subs lapse at whale-pass expiry — exactly the caveat PLAN §12.6 flagged. **This is a genuine open the SPEC must close with a user decision; do not present a default as fact.** Relevant skill: `economic-analyst` (does the protocol-sub funding model close?).

### Two-tier skip-kill identity (SUB-06)
- Pinned address constants live in `ContractAddresses.sol`: `VAULT` (:37), `SDGNRS` (:47) already exist. The exemption branch keys on these (un-spoofable). **No `AF_KING`/`STREAK_KEEPER` constant exists yet** — PROTO-05 must ADD it. The exemption is `keeper-side` logic comparing the swept player to `ContractAddresses.VAULT`/`SDGNRS`. **Source-confirmed: the identity anchors exist; the keeper constant must be added.**

---

## 6. Architecture Patterns

### Component Responsibility Map (ADD + REMOVE surfaces)
| Capability | Owner contract / module | Notes |
|------------|-------------------------|-------|
| Pass gate (`hasAnyLazyPass`) | `DegenerusGame.sol:1610` (expose) | PROTO-01; sole keeper coupling |
| Subscription state + sweep + funding waterfall | `StreakKeeperV2.sol`→`AfKing` (separate contract) | game-brick-immunity rationale; cursor/reinvestPct/windowPaid UNBUILT |
| Reward emission (`creditFlip`) | `BurnieCoinflip.sol` `onlyFlipCreditors` (194) | PROTO-03 adds keeper |
| Charge (`burnForKeeper`) | `BurnieCoin.sol` (does NOT exist yet) | PROTO-02 adds it |
| Keeper-gated batch purchase | `DegenerusGame.batchPurchase` (does NOT exist yet) | PROTO-04; in-context per-player try/catch |
| Pinned keeper address | `ContractAddresses.sol` (add `AF_KING`) | PROTO-05; `VAULT`/`SDGNRS` already pinned |
| ETH jackpot credit (post-removal: always claimable) | `JackpotModule._addClaimableEth:788` | RM-02; drop `_processAutoRebuy`/entropy |
| BURNIE flip recycle (KEEP @ flat 75bps) | `BurnieCoinflip._recyclingBonus:1051` | RM-03; drop afKing tier |
| Protocol-sub init | `StakedDegenerusStonk.sol:360-366` + `DegenerusVault` constructor | SUB-09; replace `setAfKingMode` with self-subscribe |

### entropy cascade (the SAFE-04 VRF-freeze-obligation retirement)
The VRF word originates as `rngWord`/`randWord` (VRF-derived) and is mixed via `EntropyLib.hash2` at JackpotModule 286/533/1187/1933, threaded as `entropy`/`entropyState` through the jackpot resolution loop (1280/1294/1328/1389/1401) into `_addClaimableEth(w, perWinner, entropy)` (1430/1530/1571/1583/2132/2165) → `_processAutoRebuy(beneficiary, weiAmount, entropy, state)` (822) → `_calcAutoRebuy(..., entropy, ...)` (PayoutUtils:51) where `keccak256(abi.encode(entropy, beneficiary, weiAmount)) & 3` picks the rebuy target level. Removing `_processAutoRebuy`/`_calcAutoRebuy` makes the `entropy` param **unconsumed on the claimable path** → it can be dropped from `_addClaimableEth`'s signature, and the `JackpotEthWin` event's `rebuyLevel`/`rebuyTickets` fields become dead (event signature change). **This is the concrete "one fewer VRF consumer + three fewer player-mutable in-window inputs (`autoRebuyEnabled`/`takeProfit`/`afKingMode`)" retirement SAFE-04 claims — source-confirmed.** Relevant skills at AUDIT: `zero-day-hunter` (does dropping entropy threading change any OTHER consumer? — note the 3-arg `_addClaimableEth` is JackpotModule-only; the DegeneretteModule 2-arg overload at 1117 is untouched).

### Anti-patterns to avoid (carried from project rules)
- **Do NOT frame the afKing/auto-rebuy backlog as live exploits** (`project_rnglock_audit_disposition`) — it's a removal for simplification, not a finding fix.
- **Do NOT pitch a box direct-resolve refactor** (`project_lootbox_delayed_finalization_intentional`) — the queue-then-materialize is intentional; the box cursor (OPEN-D) layers on top.
- **Do NOT re-key bet/box ledgers on the hot path** (REQUIREMENTS Out of Scope) — bets stay caller-list.

---

## 7. Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| ETH→BURNIE reward conversion | A new pegged-conversion fn | `_ethToBurnieValue` (`MintModule:1412`) idiom | Already zero-guarded (OPEN-B); matches advanceGame; auditor-familiar |
| Stall-escalating bounty | New multiplier scheme | advanceGame `bountyMultiplier` 2/4/6× (AdvanceModule:244-256) | Proven pattern; SPEC mirrors it for sweep |
| Per-item revert isolation | inline try patterns | `onlySelf` external sub-call + try/catch | The only Solidity way to isolate in-context per-item revert (PLAN §8) |
| Pass gate | New `hasAnyPass` view | expose existing `_hasAnyLazyPass` | Already = "any of 3"; 1-2 SLOADs (PROTO-01) |
| Sweep idempotency | New day-tracking | existing `lastSweptDay` (keeper:31) | Already built |
| Active-set reclaim | `compact()` pass | existing `_removeFromSet` swap-pop (keeper:707/1013) | Already built; no-`++i` invariant holds |
| Protocol-sub exemption flag | settable bool | pinned `ContractAddresses.VAULT`/`SDGNRS` identity | settable flag = trivial cancellation dodge (SUB-06) |

---

## 8. Common Pitfalls

### Pitfall 1: Treating PLAN-CRANK §9 "done this session" as ground truth
**What goes wrong:** the SPEC locks against a keeper state that doesn't exist. **Why:** §9 claims pull→burn rename + creditFlip wiring + mintForKeeper removal are compile-verified-done; live source shows 19× `pullForKeeper`, 5× `mintForKeeper`, 2× `creditFlip`, OLD `sweep(startIdx,count)`. **Avoid:** lock against the *intended end-state* (cursor + reinvestPct + windowPaid + burnForKeeper) and explicitly cite the §1.12 drift; the IMPL phase builds it.

### Pitfall 2: RM-06 "decrement slots by 1" naive patch
**What goes wrong:** test SLOT_* constants are already +1 stale vs current layout AND at least one slot-sensitive test fails at baseline. **Avoid:** re-derive every test SLOT_* from `forge inspect` on the POST-deletion contract; capture the pre-deletion baseline-failure ledger first.

### Pitfall 3: Box cursor re-coupling to the VRF-rotation orphan-index keyspace (OPEN-D)
**What goes wrong:** a `boxPlayers[index]` enqueue keyed on the lootbox `index` re-introduces the v45 CATASTROPHE surface (`project_vrf_rotation_midday_orphan_index`): emergency VRF rotation orphans in-flight mid-day indices. **Why:** the box cursor's enqueue/dequeue must follow the v45 `a303ae18` detect-preserve-re-issue path. **Avoid:** the SPEC must state the box cursor follows the orphan-index re-issue, and the AUDIT phase re-verifies the freeze invariant holds under rotation WITH the new cursor. This is the milestone's single biggest design landmine.

### Pitfall 4: Dropping the `entropy` param without checking all consumers
**What goes wrong:** silently breaking a non-rebuy entropy consumer. **Avoid:** the 3-arg `_addClaimableEth` is JackpotModule-only; the DegeneretteModule 2-arg overload (1117) is separate and untouched. Verify no OTHER reader of the threaded `entropyState` survives (grep at IMPL).

### Pitfall 5: Whale-pass expiry silently lapses protocol subs
**What goes wrong:** sDGNRS/Vault subs cancel at whale-pass expiry because `claimWhalePass` no-ops when `whalePassClaims==0`. **Avoid:** SPEC must lock the post-expiry renewal funding (user decision required — do NOT default).

---

## 9. Open Questions

1. **Whale-pass-expiry renewal funding for protocol subs.** What we know: `claimWhalePass` only extends freeze if `whalePassClaims>0`; both sStonk/Vault have re-claim entries. What's unclear: where their `whalePassClaims` accrue after initial expiry. Recommendation: **flag for user decision at SPEC** (BURNIE-to-burn fallback vs permanent Deity bit vs accept lapse). Cannot be resolved from source alone.
2. **OPEN-C final disposition (CEI vs guard).** What we know: game uses CEI throughout, no ReentrancyGuard. What's unclear: whether any path in mint→lootbox→prize-pool→EV-cap→quest re-enters before the day-stamp. Recommendation: SPEC requires the IMPL/AUDIT trace; lean CEI-proof; `contract-auditor` skill owns the proof.
3. **`JackpotEthWin` event consumer fan-out.** What we know: removal drops `rebuyLevel/rebuyTickets` fields. What's unclear: off-chain indexer dependence (out of scope, but the event signature change is a breaking ABI delta). Recommendation: note the ABI break in the SPEC's delta section; indexer is a separate frontend track.

---

## 10. Planning Recommendations

**Skip deep research is already done — this IS the research.** The SPEC-writing should decompose into **4 plans** (the phase is SPEC-type, zero contract/test mutation, `commit_docs:true`):

**Plan 316-01 — ADD-design lock.** Owns: do-work entry signatures + work-type encoding (caller-list bets w/ `BatchAlreadyTaken` short-circuit reusing the resolving-item-0 SLOAD; parameterless box cursor per OPEN-D); reward formula (mirror `_ethToBurnieValue`/advanceGame idiom, OPEN-B-safe) + reserved per-work-type gas-peg constants (numbers deferred to Phase 319/OPEN-A); `batchPurchase` shape + per-player `onlySelf`+try/catch+slice-refund + batch-level `rngLocked`/game-over precheck + OPEN-C disposition; cursor sweep (mirror advanceGame cursor + escalating bounty + tombstone-on-cancel + swap-pop + `windowPaid`); authorization (subscribe-time self-or-operator consent via `_resolvePlayer`/`_requireApproved` mirror, never at sweep) + pass-OR-pay via `hasAnyLazyPass`; the 5 PROTO signatures gating on pinned `AF_KING`. **Must cite the §1.10/§1.11/§1.12 anchors.** Covers SC #1, #2.

**Plan 316-02 — REMOVE footprint + reconciliation lock.** Owns: PROTO-01/RM-04 KEEP+EXPOSE statement (cite §2); the RM-01..06 deletion footprint as the verified §1.1–§1.9 table (afKing mode surface, `AutoRebuyState` slot-19 deletion, jackpot `_processAutoRebuy`/`_calcAutoRebuy` + entropy-param drop + `JackpotEthWin` signature change, BURNIE recycle→flat 75bps dropping deity tier, Vault `gameSet*` + sStonk `setAfKingMode`→self-subscribe + interface decls); the §4 storage slot-shift map + test-side re-derivation plan; the SAFE-04 VRF-freeze-obligation retirement (§6 entropy cascade). Covers SC #4.

**Plan 316-03 — open-item resolution.** Owns: OPEN-B (cite `_ethToBurnieValue` guard + `priceForLevel` non-zero); OPEN-C disposition; "1 price lootbox" denomination (cite `TICKET_SCALE=400`); whale-pass-expiry renewal (FLAG for user decision — §5); two-tier skip-kill identity (cite `ContractAddresses.VAULT`/`SDGNRS` + add `AF_KING`); the SUB-09 protocol-sub init configs (sStonk + Vault). Covers SC #2, #3.

**Plan 316-04 — call-graph attestation.** Owns SC #5: embed/reference this RESEARCH.md's §1 verification table as the attestation; record the keeper-dependency clean result (§3); record the drift items (the ≤+4-line drifts, the keeper transitional-state caveat, the IDegenerusGame "setAutoRebuy not in this interface" resolution) so the SPEC contains **zero unverified "by construction" claims**; note the box-cursor VRF-rotation-index coupling landmine (Pitfall 3).

**Landmines for the planner:**
- The box-cursor (OPEN-D) re-couples to the VRF-rotation orphan-index keyspace → must follow v45 `a303ae18` re-issue (Pitfall 3 / memory `project_vrf_rotation_midday_orphan_index`). Single biggest design risk.
- RM-06 storage shift is test-only but interacts with a pre-existing stale baseline (Pitfall 2).
- The keeper's `PLAN-CRANK §9` "done" claim is false vs live source (Pitfall 1); lock the intended end-state.
- Whale-pass-expiry renewal is a genuine open requiring user input — do NOT default (§5, Q1).
- Highest-scrutiny ADD surfaces (`burnForKeeper`/`creditFlip` authority, `batchPurchase` reentrancy) → route to `contract-auditor` + `economic-analyst` skills at AUDIT (Phase 320).

**Waving:** these 4 plans are independent design-doc sections (no code), so they can be authored in parallel or one wave. No Wave 0 (nyquist disabled). No checkpoint:human-verify needed for packages (none installed).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | (none) | — | All claims verified via grep / `forge inspect` against live HEAD; zero `[ASSUMED]`. The one user-decision-required item (whale-pass-expiry renewal funding, §5/Q1) is flagged as an OPEN, not asserted. |

---

## Sources

### Primary (HIGH — verified this session)
- `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout` (forge 1.6.0-nightly, read-only) — authoritative slot map; `autoRebuyState` = slot 19.
- `grep -rn` across `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol` + `/home/zak/Dev/PurgeGame/degenerus-utilities/contracts/StreakKeeperV2.sol` — every §1 file:line.
- `forge test --match-test test_lootboxBoonAppliedDespiteExistingCoinflipBoon` — confirmed pre-existing baseline failure (RM-06 hazard).

### Input docs (re-verified, not trusted blind)
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` (§1–§14 incl §12.6 resolutions).
- `.planning/PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` (§5 footprint).
- `.planning/REQUIREMENTS.md` (38 v46.0 reqs), `.planning/STATE.md`, `.planning/ROADMAP.md` (Phase 316 SC).

### Project rules consulted
- MEMORY: `feedback_verify_call_graph_against_source`, `feedback_security_over_gas`, `feedback_contract_locations`, `project_vrf_rotation_midday_orphan_index`, `project_v47_remove_afking_eth_autorebuy`, `project_free_burnie_crank_button`, `feedback_slash_command_hyphen_form`.

---

## Metadata

**Confidence breakdown:**
- Call-graph verification (§1): HIGH — direct grep against live HEAD, every line confirmed.
- `_hasAnyLazyPass` reader-set (§2): HIGH — exhaustive grep, 3 matches total.
- Keeper dependency (§3): HIGH — zero-match grep on the full RM-symbol set.
- Storage slot map (§4): HIGH — `forge inspect` authoritative; baseline-failure empirically confirmed.
- Open-item facts (§5): HIGH for OPEN-B/OPEN-C/denomination/skip-kill-identity (source-grounded); MEDIUM for whale-expiry (mechanics confirmed, but the renewal-funding decision is a genuine user-OPEN, not derivable from source).

**Research date:** 2026-05-23
**Valid until:** until the next `contracts/`/`test/` mutation lands (this milestone is the next mutation — so valid through Phase 317 IMPL; re-verify the slot map immediately after the batched diff per RM-06).

---

## JGAS — Jackpot ETH-Split Removal (added scope, 2026-05-23)

**Researched:** 2026-05-23 (addendum pass) · **Confidence:** HIGH — every line below grep/`forge inspect`-verified against live HEAD `MILESTONE_V45_AT_HEAD_62fb514b`. Zero `[ASSUMED]` factual claims; the one judgement call (single-call-fits-with-margin) is flagged as a structural estimate the SPEC must lock as "REMOVE pending JGAS-04 empirical confirmation."

This addendum supplies the grep-verified factual substrate for **JGAS-01** (Phase 316 SPEC decision-gate), which the main research pass did not cover. JGAS-01 must (a) trace the two-call split's design intent BEFORE locking deletion (`feedback_design_intent_before_deletion`), (b) derive the theoretical worst-case single-call gas FIRST (`feedback_gas_worst_case`), (c) lock REMOVE-if-fits-with-margin else RETAIN+document, and (d) enumerate + grep-verify the deletion footprint across both modules. The split removal is **enabled by RM-02** (drops the per-winner `autoRebuyState` SLOAD + `_processAutoRebuy` branch from the daily-ETH credit path) and ships in the SAME batched USER-APPROVED diff at Phase 317 (JGAS-02).

### J1. JGAS Deletion-Footprint Verification Table (HEADLINE)

All paths canonical (`/home/zak/Dev/PurgeGame/degenerus-audit/contracts/...`). Verdicts: ✓ = doc line matches live; ✗ DRIFT = present at different line; ✗ MISSING = not found.

#### J1.1 `modules/DegenerusGameJackpotModule.sol`

| # | Symbol | Doc/req claim | Live | Verdict |
|---|--------|---------------|------|---------|
| 1 | `SPLIT_NONE` constant (=0) | (req: SPLIT_*) | `uint8 private constant SPLIT_NONE = 0;` **:197** | ✓ |
| 1 | `SPLIT_CALL1` constant (=1) | (req: SPLIT_*) | `=1` **:199** | ✓ |
| 1 | `SPLIT_CALL2` constant (=2) | (req: SPLIT_*) | `=2` **:201** | ✓ |
| 2 | `resumeEthPool` storage decl | (req: slot) | `uint128 internal resumeEthPool;` `storage/DegenerusGameStorage.sol:994` (forge slot **33**) | ✓ |
| 2 | `resumeEthPool` resume-check (jackpot module) | req `:348` | `if (resumeEthPool != 0)` **:349** | ✗ DRIFT (+1; req says 348, body guard at 349, comment at 348) |
| 2 | `_resumeDailyEth` function | (req: present) | `function _resumeDailyEth(uint24 lvl, uint256 randWord) private` **:1186** (called from **:350**) | ✓ |
| 3 | `splitMode` param (in `_processDailyEth`) | (req: splitMode routing) | `uint8 splitMode,` **:1248**; local derived **:476/:480/:501** | ✓ |
| 3 | `call1Bucket` mask routing | (req: call1Bucket) | `bool[4] memory call1Bucket;` **:1270**; build **:1271-1278**; skip-routing **:1287-1288** | ✓ |
| 4 | `JACKPOT_MAX_WINNERS` split-threshold branch | req `:476-501` | branch `splitMode = (totalWinners <= JACKPOT_MAX_WINNERS) ? SPLIT_NONE : SPLIT_CALL1;` **:476-483**; `_processDailyEth(... splitMode ...)` call **:493-503** | ✓ (the req's `476-501` brackets the threshold-derivation block + the `_processDailyEth` call at 493-503; matches) |
| 4 | resume-check (jackpot module) | req `:348` | **:349** (see #2) | ✗ DRIFT (+1) |
| 5 | `DAILY_JACKPOT_SCALE_MAX_BPS` value | req `=63_600` | `uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;` **:248** | ✓ (value exact) |
| 5 | `DAILY_ETH_MAX_WINNERS` value | req `=305` | `uint16 private constant DAILY_ETH_MAX_WINNERS = 305;` **:227** | ✓ (value exact) |
| 5 | bucket sizes 159/95/50/1 | req 159/95/50/1, sum 305 | doc-comment **:226** `159 + 95 + 50 + 1 = 305`; **:246-247** `call 1 ... 159 + solo 1 = 160 winners, call 2 ... 95 + 50 = 145` | ✓ — **arithmetic confirmed: 159+95+50+1 = 305; call1 = 159+1 = 160; call2 = 95+50 = 145** |
| — | `JACKPOT_MAX_WINNERS` constant (=160) | (req: threshold) | `uint16 private constant JACKPOT_MAX_WINNERS = 160;` **:219** — used **ONLY** at the split-threshold (**:480**); the **:242** mention is a doc-comment cross-reference, not a use | ✓ — **becomes dead on removal** (sole functional use is the threshold) |

**Note (item 4 line-range nuance):** the req's `:476-501` cite is a *range* spanning the `splitMode` derivation block (`:476-483`) plus the `_processDailyEth(...)` call that consumes it (`:493-503`). Both are present and contiguous in the live source; the range is accurate. The interior resume-check the req pins at `:348` is at **:349** in live source (+1 drift — the doc comment is at 348, the `if` guard at 349). Cosmetic; flag in the SPEC attestation.

#### J1.2 `modules/DegenerusGameAdvanceModule.sol`

| # | Symbol | Doc/req claim | Live | Verdict |
|---|--------|---------------|------|---------|
| 6 | `STAGE_JACKPOT_ETH_RESUME` constant (=8) | req `=8`, `:68-70` | `uint8 private constant STAGE_JACKPOT_ETH_RESUME = 8;` **:70** (NatSpec **:68-69**) | ✓ (value=8 exact; decl at 70, doc-comment 68-69 — req's `:68-70` brackets the doc+decl) |
| 6 | resume-check + stage handler (advance module) | req `:452-455` | `if (resumeEthPool != 0) { payDailyJackpot(true, lvl, rngWord); stage = STAGE_JACKPOT_ETH_RESUME; break; }` **:453-456** | ✗ DRIFT (+1; req `452-455`, live `453-456` — comment at 452, block 453-456) |

**Both module footprints are present and accurately located** (≤ +1 line drift on the two interior resume-checks; all constants exact-match by value). The only DRIFTs are the two `+1` resume-check line offsets — purely the doc citing the leading comment line rather than the `if`. No MISSING symbols.

### J2. Advance-Stage-Machine Map (item 7)

**Full `STAGE_*` enumeration** (`DegenerusGameAdvanceModule.sol:60-73`), all `uint8 private constant`:

| Constant | Value | Set at line(s) | Role |
|----------|-------|----------------|------|
| `STAGE_GAMEOVER` | 0 | 545, 563, 630 (returns) | game-over / final-sweep completion |
| `STAGE_RNG_REQUESTED` | 1 | 300 | VRF requested, awaiting fulfillment |
| `STAGE_TRANSITION_WORKING` | 2 | 315, 327 | level-transition drain in progress |
| `STAGE_TRANSITION_DONE` | 3 | 336 | transition complete |
| `STAGE_FUTURE_TICKETS_WORKING` | 4 | 349, 416 | far-future ticket drain |
| `STAGE_TICKETS_WORKING` | 5 | 281, 361, 594, 613 | ticket-queue best-effort drain (caller retries) |
| `STAGE_PURCHASE_DAILY` | 6 | 403 | purchase-phase daily jackpot done |
| `STAGE_ENTERED_JACKPOT` | 7 | 446 | jackpot phase entered |
| **`STAGE_JACKPOT_ETH_RESUME`** | **8** | **455** | **call-2 of the two-call ETH split — JGAS DELETION TARGET** |
| `STAGE_JACKPOT_COIN_TICKETS` | 9 | 468 | coin+ticket distribution done |
| `STAGE_JACKPOT_PHASE_ENDED` | 10 | 464 | jackpot phase complete |
| `STAGE_JACKPOT_DAILY_STARTED` | 11 | 474 | fresh daily jackpot kicked off |

**Are stage numbers load-bearing? NO — verified three ways:**
1. **Not persisted.** `stage` is a **function-local `uint8`** (declared `:260` inside `advanceGame`); it is never written to a storage slot. `grep` for any storage-side `stage`/`goStage`/`stagePacked`/`gameStage` field returns nothing.
2. **Not compared by value.** The only `STAGE_* ==` comparison anywhere is `goStage == STAGE_TICKETS_WORKING` (**:188**) — and that compares against a *returned local* from `_handleGameOverPath`, not a stored or persisted stage. `STAGE_JACKPOT_ETH_RESUME` is **only ever assigned** (`:455`) and **emitted** — never read or compared. (`grep "== 8"` / `STAGE_JACKPOT_ETH_RESUME` confirms: decl `:70`, single assignment `:455`, zero comparisons.)
3. **Emit-only sink.** Every stage value flows into `emit Advance(stage, lvl)` (event decl `:52`; emitted `:187/:227/:477`). The `Advance` event is **not consumed on-chain** — the two `gameAdvance()` wrappers (`DegenerusVault.sol:500`, `StakedDegenerusStonk.sol:398`) just *call* advance; they do not read the stage. The event is purely an off-chain/observability payload.

**Consequence for JGAS-02:** removing `STAGE_JACKPOT_ETH_RESUME` requires deleting only the constant (`:70`) and its single assignment site (`:455`, inside the `resumeEthPool != 0` block being deleted). **Renumbering 9/10/11 → 8/9/10 is OPTIONAL and cosmetic** (purely tidies the emitted-event enum). The actual resume *mechanism* is driven by the `resumeEthPool != 0` storage read at `:453`, NOT by any stored stage number — so deleting that storage var + its check is what behaviorally removes the resume path. **No load-bearing renumber hazard.** SPEC recommendation: delete constant 8, leave 9/10/11 as-is OR renumber for tidiness (planner's call; either is behaviorally inert). Document the off-chain `Advance`-event ABI note (stage 8 will never be emitted post-removal) as a benign observability delta.

### J3. Combined Storage-Slot Re-Derivation (RM-06 + JGAS, item 8)

**Authoritative `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout` (read-only, forge 1.6.0-nightly):**

| Var | Width | Live slot | After RM-02 (`autoRebuyState`@19 del) | After RM-02 **+** JGAS (`resumeEthPool`@33 del) |
|-----|-------|-----------|----------------------------------------|--------------------------------------------------|
| `autoRebuyState` | mapping (full slot) | **19** | **(deleted)** | (deleted) |
| `lootboxEthBase` | mapping | 20 | 19 (−1) | 19 (−1) |
| `deityBySymbol` | mapping | 30 | 29 (−1) | 29 (−1) |
| `earlybirdDgnrsPoolStart` | uint256 | 31 | 30 (−1) | 30 (−1) |
| `earlybirdEthIn` | uint256 | 32 | 31 (−1) | 31 (−1) |
| **`resumeEthPool`** | uint128 (own slot) | **33** | 32 (−1) | **(deleted)** |
| `vrfCoordinator` | address | 34 | 33 (−1) | **32 (−2 vs live)** |
| `vrfKeyHash` | bytes32 | 35 | 34 (−1) | **33 (−2)** |
| `vrfSubscriptionId` | uint256 | 36 | 35 (−1) | **34 (−2)** |
| `lootboxRngPacked` | uint256 | 37 | 36 (−1) | **35 (−2)** |
| `lootboxRngWordByIndex` | mapping | 38 | 37 (−1) | **36 (−2)** |
| `lootboxDay` | mapping | 39 | 38 (−1) | **37 (−2)** |
| `lootboxPurchasePacked` | mapping | 40 | 39 (−1) | **38 (−2)** |
| `lootboxBurnie` | mapping | 41 | 40 (−1) | **39 (−2)** |
| `deityBoonDay` | mapping | 42 | 41 (−1) | **40 (−2)** |
| `boonPacked` | mapping | 61 | 60 (−1) | **59 (−2)** |
| (all vars at slot ≥ 34) | — | N | N−1 | **N−2** |

**Key facts:**
- **`resumeEthPool` occupies its OWN slot 33** (uint128 at offset 0; the next declared var `vrfCoordinator` starts fresh at slot 34, NOT packed into 33's free upper 16 bytes). So its deletion is a clean **−1 shift of every var at slot ≥ 34**, layered on top of RM-02's **−1 shift of every var at slot ≥ 20**.
- **Combined effect: every storage var at slot ≥ 34 shifts down by −2; vars in [20, 33) shift −1; vars < 19 unchanged.** The `vrf*` block + the entire `lootboxRng*` family (the slots the v45 VRF work depends on — §4 of the main pass and `project_vrf_rotation_midday_orphan_index` reference slot-38 `lootboxRngWordByIndex`) all move **−2**. `lootboxRngWordByIndex` 38 → **36**; `lootboxRngPacked` 37 → **35**.
- **Contracts hold ZERO numeric slot literals** — re-confirmed this pass: `grep -rnE '\.slot\s*:?=\s*[0-9]+|sload\([0-9]+\)|SLOT_[A-Z_]+\s*=\s*[0-9]+' contracts/ (excl test)` returns only `QUEST_SLOT_COUNT=2` and `TICKET_SLOT_BIT=1<<23` (neither is a storage-slot literal). So **no contract code breaks on either shift** — both RM-06 and JGAS slot work are **entirely test-side**.
- **Compounds with the §4 stale-baseline hazard.** The main pass found `LootboxBoonCoexistence.t.sol` already declares `SLOT_LOOTBOX_RNG_IDX=38 / SLOT_LOOTBOX_WORD=39` and is *already* +1 stale (and failing at baseline). Adding the JGAS −2 shift means `lootboxRngWordByIndex` lands at **36**, `lootboxRngPacked` at **35** — so the re-derivation **cannot be a blind decrement** (some constants are already off in the wrong direction). **Re-run `forge inspect ... storage-layout` against the POST-(RM-02+JGAS) contract and rewrite every test `SLOT_*` from that authoritative output**, file-by-file, AFTER capturing the pre-deletion baseline-failure ledger. This is the same instruction as RM-06 §4 — JGAS just deepens the shift from −1 to −2 for the slot-≥34 region. **RM-06 and JGAS must be re-derived together in one pass** (deleting both vars in the same batched diff, then one `forge inspect`).

### J4. Design-Intent + Worst-Case Finding (items 9, 10, 11 — the JGAS-01 decision-gate substrate)

#### J4.1 Why the two-call split exists (design intent — `feedback_design_intent_before_deletion`)

The split is a **pure gas-ceiling workaround**, NOT a correctness/fairness mechanism. Traced from source:

- **The ceiling that forced it:** the daily ETH jackpot at max scale (`DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` = 6.36×, pool ≥ 200 ETH) caps at `DAILY_ETH_MAX_WINNERS = 305` winners across 4 trait buckets (159/95/50/1). Each winner costs a per-winner credit (see J4.2). The split threshold is `JACKPOT_MAX_WINNERS = 160` (`:480`): if `totalWinners ≤ 160` → `SPLIT_NONE` (one call); else → `SPLIT_CALL1` (two calls). 305 > 160 → splits.
- **How the split partitions:** `call1Bucket` mask (`:1270-1278`) assigns **call 1 = largest bucket + solo bucket** (159 + 1 = 160 winners), **call 2 = the two mid buckets** (95 + 50 = 145 winners). Call 1 sets `resumeEthPool = uint128(ethPool)` (`:1347-1348`); call 2 reads it back, zeroes it (`:1251-1253`), and pays the skipped buckets.
- **What state `resumeEthPool` carries between calls:** *only the total ETH pool amount* (a single `uint128`). The winner set, trait IDs, shares, and entropy are **re-derived deterministically in call 2** (`_resumeDailyEth` `:1186-1214` re-rolls `_rollWinningTraits(randWord)`, `_pickSoloQuadrant`, `bucketCountsForPoolCap` from the SAME `randWord` — see J5). So `resumeEthPool` is the *only* cross-call storage carry; everything else is recomputed from the held VRF word.
- **How advanceGame pauses + resumes:** call 1 runs inside the fresh-daily-jackpot path (`payDailyJackpot(true,...)` at advance `:473`, stage → `STAGE_JACKPOT_DAILY_STARTED`). The NEXT `advanceGame` invocation sees `resumeEthPool != 0` (advance `:453`), runs call 2 (`payDailyJackpot` → jackpot `:349` → `_resumeDailyEth`), stage → `STAGE_JACKPOT_ETH_RESUME`. So **two separate `advanceGame` transactions** complete one daily ETH jackpot when winners > 160.
- **Actor game-theory:** `advanceGame` is permissionless, gas-rebated via the escalating `bountyMultiplier` (1/2/4/6× of `ADVANCE_BOUNTY_ETH = 0.005 ether`, advance `:244-256`) credited as a coinflip-stake bounty. Whoever calls each chunk earns the per-chunk bounty. The split means the daily-jackpot completion is **two bountied advance calls** instead of one — collapsing it to one call merges the two bounties into one.
- **Correctness/fairness property lost on single-call? NONE.** Because call 2 re-derives the SAME winner set from the SAME held `randWord`, single-call and two-call produce **identical payouts** (same winners, same per-winner amounts, same solo-bucket whale-pass treatment). The split is observationally equivalent to a single call modulo gas. **No EV, fairness, or determinism property is carried by the split — it is purely a gas-fits workaround.** This is the clean precondition `feedback_design_intent_before_deletion` requires before locking deletion: the mechanism carries no semantic load beyond gas.

#### J4.2 Theoretical worst-case single-call gas (item 10 — `feedback_gas_worst_case`)

**Per-winner cost structure (post-RM-02), derived from source, NOT measured (JGAS-04/Phase-319 measures):**

The single-call payout iterates 4 buckets (`_processDailyEth:1283`), and within each bucket calls `_randTraitTicket` (winner selection) then either `_payNormalBucket` (`:1517`, the 3 non-solo buckets, 304 winners) or `_handleSoloBucketWinner` (1 winner). Per **normal** winner (the dominant 304 of 305):

- `_addClaimableEth(w, perWinner, entropy)` post-RM-02 → falls straight through to `_creditClaimable` (`PayoutUtils:32`): **one SSTORE to `claimableWinnings[w]`** (cold, ~22.1k gas: 20k cold-zero-init SSTORE + 2.1k cold-account access for the new map slot) + one `PlayerCredited` event (~1.5k).
- One `JackpotEthWin` event emit per winner (`:1531`, 7 indexed/data fields, ~2-3k gas).
- The `_randTraitTicket` selection amortizes per bucket (one call per bucket, returns the winner array) — its dominant cost is reading the trait ticket pool; bounded by `MAX_BUCKET_WINNERS = 250` (no single bucket > 159 at worst case, so under the cap).
- `claimablePool += liabilityDelta` is **batched once per bucket** (`:1342-1343`), not per winner — a warm SSTORE (~5k) ×4 buckets.

**Order-of-magnitude estimate (structural, ±30%):** ~25-30k gas per cold-new winner credit (SSTORE + 2 events) × 305 ≈ **7.6M-9.2M gas** for the winner-credit loop, **plus** fixed overhead (4× `_randTraitTicket` ticket-pool reads, bucket-share math, `bucketCountsForPoolCap`, the solo-bucket whale-pass path, prize-pool accounting SSTOREs) ≈ **1-3M**. **Theoretical worst-case single-call ≈ 9-12M gas.** Against a ~30M block gas limit (Ethereum mainnet), that is a **~2.5-3.3× margin** — comfortably fits in one call with headroom. *Caveat:* `_randTraitTicket` cost scales with the trait ticket-pool population (the selection draws from `traitBurnTicket[lvl]`); if the pool is very large the read cost rises, but it is bounded and was already inside *each* of the two split calls today (call 1 alone already paid 160 winners + its own selection overhead under the block limit). **Today call 1 demonstrably pays 160 winners in one tx under the limit; single-call adds the 145 mid-bucket winners (call 2's load) onto the same tx — i.e. single-call ≈ call1 + call2 gas, which is the SAME total work spread across one tx instead of two.** The question is purely whether `call1_gas + call2_gas < block_limit`.

#### J4.3 What RM-02 frees (item 11 — the enabling headroom)

RM-02 removes, **per daily-ETH winner**, from `_addClaimableEth` (`:800-806`):
- one **cold SLOAD of `autoRebuyState[beneficiary]`** (`:801`, ~2.1k cold-account + 2.1k cold-slot ≈ 4.2k gas; the struct is one slot) — paid for **every** winner even when auto-rebuy is disabled (the SLOAD happens before the `state.autoRebuyEnabled` branch).
- the conditional `_processAutoRebuy` branch (`:802-804`) — a no-op for disabled winners, but the SLOAD + branch test is unconditional per winner.

**Freed per-winner ≈ 4.2k gas (the unconditional cold struct SLOAD) × 305 ≈ ~1.3M gas** off the worst-case single-call total. That is the localized daily-ETH-path headroom JGAS spends to fit 305 winners in one call. (Coin/lootbox/ticket caps are unaffected — those paths sit on `creditFlip`/other cost centers and the coin path keeps the v46 BURNIE-flip rebuy, so `DAILY_COIN_MAX_WINNERS=50`/`LOOTBOX_MAX_WINNERS=100`/`PURCHASE_PHASE_TICKET_MAX_WINNERS=120` are untouched — confirmed `:223/:230/:243`.)

#### J4.4 Recommended JGAS-01 decision-gate disposition

**LOCK = "REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented."**

Reasoning: the structural derivation (J4.2) shows single-call worst-case ≈ 9-12M gas vs ~30M limit (~2.5-3.3× margin), AND the strongest evidence is **observational equivalence to today's behavior**: the split already pays 160 winners (call 1) + 145 winners (call 2) in two txs that each fit under the block limit; single-call simply sums that same total work into one tx. Since RM-02 *lowers* per-winner cost, single-call total = (call1 + call2 work) − (305 × freed SLOAD) < the current two-call total work. The margin is real but the absolute total (9-12M) is an estimate, not a measurement — and the project rule `feedback_gas_worst_case` mandates measuring the derived worst case before relying on it. **The SPEC therefore locks REMOVE conditionally**: design the IMPL (JGAS-02) to delete the split, and gate the lock's *finality* on JGAS-04's empirical 305-winner single-call measurement at Phase 319 confirming < block limit with margin. **RETAIN-fallback documented:** if JGAS-04 measures the single-call over (or uncomfortably near) the block limit, the IMPL reverts to keeping the split — but this is judged unlikely given the structural margin + the observational-equivalence argument. The decision is *makeable at SPEC* (REMOVE) with an empirical confirmation gate, NOT blocked-until-measurement.

### J5. VRF / Security-Floor Assessment (item 12 — HEADLINE; gates whether JGAS is safe)

**`DegenerusGameAdvanceModule` is the VRF-rotation-sensitive module** (the Phase 312 `a303ae18` work lived here). A stage-machine edit here is exactly the change class that can perturb the freeze invariant — so this assessment is load-bearing per `feedback_security_over_gas` + the v45 VRF-freeze north-star.

**Does the daily-ETH stage consume/read a VRF word?** YES. The daily ETH jackpot is driven by `randWord` (the VRF-derived daily word from `rngGate`). Both call 1 (`payDailyJackpot(true, lvl, rngWord)`, advance `:473`) and call 2 (`payDailyJackpot(true, lvl, rngWord)` → `_resumeDailyEth(lvl, randWord)`, advance `:454` / jackpot `:350`) consume the **SAME `rngWord`** — call 2 re-derives winners by re-rolling `_rollWinningTraits(randWord)` from the identical held word (jackpot `:1188`).

**Is the rng lock HELD across the split? YES — and this is the critical finding.** Tracing `_unlockRng` placement in the jackpot-phase block (advance `:450-475`):
- The **ETH-resume branch** (`:453-456`): `if (resumeEthPool != 0) { payDailyJackpot(...); stage = STAGE_JACKPOT_ETH_RESUME; break; }` — **does NOT call `_unlockRng`**. The rng lock (`rngLockedFlag`) stays SET, `rngWordCurrent` stays non-zero, the pool stays frozen (`_unfreezePool` not called).
- `_unlockRng` is called only at the **coin-tickets stage** (`:467`), the **phase-ended path**, and the non-jackpot transition paths (`:331/:402/:629`).
- So today, across the *entire* two-call ETH split (call 1 → next advanceGame → call 2), **the VRF word is frozen and the same word is reused** — exactly the freeze invariant the north-star demands (every variable interacting with a VRF word frozen across `[rng request → unlock]` vs players).

**Does removing `STAGE_JACKPOT_ETH_RESUME` / the split touch the freeze invariant? NO — and it STRENGTHENS surface-minimality, consistent with SAFE-04's "retire obligations" framing:**
1. **Single-call collapses two same-word consumptions into one.** Today the word is consumed twice (call 1 + call 2) while held frozen. Single-call consumes it once. Fewer consumption points = strictly simpler freeze surface, never weaker. The word is still consumed *inside* the locked window (the daily jackpot still runs before `_unlockRng` at the coin-tickets stage).
2. **`_unlockRng` placement is UNCHANGED by JGAS.** JGAS deletes the `resumeEthPool != 0` early-return branch (`:453-456`). The unlock still happens at the coin-tickets stage (`:467`) — which is the NEXT advanceGame call after the (now single) daily ETH jackpot. The unlock timing relative to VRF consumption does not move. Removing the resume branch just means the daily-jackpot-then-coin-tickets sequence is one fewer advanceGame hop; the lock is still held continuously from request to the coin-tickets `_unlockRng`.
3. **No new player-mutable in-window input.** Single-call reads the same `traitBurnTicket[lvl]` pools and the same held `randWord` that the split already read. No additional SLOAD of player-controllable state is introduced (RM-02 *removes* the `autoRebuyState` read — the opposite direction). The `dailyHeroWagers[dailyIdx]` read (jackpot `:1592-1600`) is keyed on the frozen `dailyIdx` (written only at `_unlockRng`), unchanged by JGAS.
4. **No coupling between stage *number* and VRF unlock.** Resume is driven by the `resumeEthPool != 0` storage read, NOT by the emitted stage value (J2). The VRF unlock is sequenced by the *code path* (`_unlockRng` call site), not by any stored stage. So deleting stage-constant 8 cannot perturb VRF sequencing — there is no stored-stage→unlock dependency to break.

**Caller-bounded-iteration / bounty model under single-call (the gas-spike concern):** single-call raises ONE advanceGame stage's gas from ~call1-only (~5-7M) to ~call1+call2 (~9-12M). This is still **one permissionless `advanceGame` tx under the block limit** (J4.2 margin). The cursor/chunk-bounty model (escalating `bountyMultiplier`) is **not coupled to the ETH-jackpot chunking** — the bounty escalation is time-based (`elapsed` thresholds, advance `:255`), not winner-count-based. Merging the two ETH-jackpot chunks into one means one bounty payment instead of two for that work — an economic delta (slightly cheaper to fully advance), NOT a safety regression. The remaining caller-bounded-iteration guards (ticket-queue drain `STAGE_TICKETS_WORKING` retry, `MAX_BUCKET_WINNERS=250` per-bucket cap) are untouched. **Provided JGAS-04 confirms the single-call fits under the block limit (J4.4 gate), there is no advanceGame brick risk** — the iteration is still bounded by `DAILY_ETH_MAX_WINNERS=305` (preserved, not raised).

**SECURITY-FLOOR VERDICT: JGAS is freeze-invariant-SAFE.** It removes a VRF-word *re-consumption* point (two same-word reads → one), does not move `_unlockRng`, introduces no new in-window player-mutable input, and the stage-number deletion cannot perturb VRF sequencing (stage numbers are not load-bearing, J2). The only residual risk is the gas-fits question (J4.4), which is a liveness/brick concern gated on JGAS-04's empirical measurement — NOT a freeze-invariant or RNG-manipulability concern. This is the HEADLINE the SPEC needs: **the stage-machine edit does NOT touch the freeze invariant; JGAS is safe to lock REMOVE (pending the gas-fits empirical gate).** The AUDIT phase (320) must re-attest the freeze invariant holds under the post-removal single-call path AND under emergency VRF rotation (the `project_vrf_rotation_midday_orphan_index` surface) — single-call must not orphan a mid-jackpot index, but since it completes the daily ETH jackpot in one atomic call (no cross-tx `resumeEthPool` carry to orphan), it is **strictly less rotation-exposed** than the two-call split, which carries `resumeEthPool` across a tx boundary where a rotation could intervene. **JGAS removes a cross-tx VRF-state carry — a rotation-robustness improvement, consistent with the Phase 312 detect-preserve-re-issue work.**

### J6. Planning Recommendation

**JGAS-01 SPEC section structure (folds into the existing 4-plan decomposition; revise Plan 316-04 + add a JGAS sub-section to 316-02):**

1. **JGAS-01 decision-gate statement** (new SPEC sub-section, owned by the REMOVE-footprint plan **316-02** since it is a removal): lock **"REMOVE the two-call split pending JGAS-04 empirical confirmation; RETAIN-fallback documented"** (J4.4). State the design-intent trace (J4.1 — pure gas workaround, no correctness/fairness load), the theoretical worst-case derivation (J4.2 — ~9-12M vs ~30M, ~2.5-3.3× margin, observational-equivalence argument), and the RM-02 freed headroom (J4.3 — ~1.3M off the path). **Cite the J1 footprint table** as the deletion-surface attestation.
2. **JGAS deletion footprint** (into 316-02's removal-footprint table, alongside the RM-01..06 surface): the J1.1/J1.2 verified symbols — `SPLIT_NONE/CALL1/CALL2` (`:197/199/201`), `resumeEthPool` (storage `:994`, slot 33; reads/writes jackpot `:349/1201/1252/1253/1348`, advance `:453`), `_resumeDailyEth` (`:1186`), `splitMode` param (`:1248`) + `call1Bucket` mask (`:1270-1278/1287-1288`), the `JACKPOT_MAX_WINNERS` split-threshold (`:476-483/480`) + `JACKPOT_MAX_WINNERS` constant (`:219`, dead on removal), `STAGE_JACKPOT_ETH_RESUME` (`:70`) + its assignment (`:455`) + the advance resume-check (`:453-456`).
3. **Combined storage re-derivation** (MERGE into 316-02's RM-06 §4 slot-shift plan — do NOT treat as separate): RM-02+JGAS delete TWO storage vars (`autoRebuyState`@19, `resumeEthPool`@33); the slot-≥34 region shifts **−2** (J3). Lock: contract source = zero slot work; test `SLOT_*` = full `forge inspect` re-derivation against the post-(RM-02+JGAS) contract, file-by-file, after capturing the baseline-failure ledger; deepens the §4 stale-baseline hazard (`lootboxRngWordByIndex` → slot 36).
4. **VRF/security-floor attestation** (HEADLINE into 316-02 and re-stated in the call-graph attestation 316-04): J5 — the stage removal does NOT touch the freeze invariant; it removes a VRF-word re-consumption point + a cross-tx `resumeEthPool` carry (rotation-robustness improvement); `_unlockRng` unmoved; stage numbers not load-bearing. Flag the AUDIT-320 re-attestation charge (freeze holds under single-call + under VRF rotation).
5. **Revise Plan 316-04 (call-graph attestation / coverage) to the 42-requirement set + JGAS footprint attestation.** The main pass wrote 316-04 against the **38-req** milestone and the "3 SPEC-owned reqs (PROTO-01/SUB-09/RM-04)." REQUIREMENTS.md now carries **42 reqs** (JGAS-01..04 folded in 2026-05-23) with **4 SPEC-owned** (PROTO-01, SUB-09, RM-04, **JGAS-01**). Plan 316-04 must (a) update the coverage count 38→42, (b) add JGAS-01 to the SPEC-owned set, (c) embed this addendum's J1 table + J5 VRF verdict as the JGAS attestation, (d) record the two `+1` resume-check line drifts (jackpot `:348`→349, advance `:452-455`→453-456) so the SPEC contains zero unverified "by construction" claims. The main pass's §"Phase Requirements" table (3 rows) and its "All 38 requirements" prose must be updated to 4 rows / 42 reqs.

**Downstream owners (do NOT run now — note for the planner):** JGAS-03 (Phase 318 TST) proves 305-winner single-call correctness + the split grep-clean/behaviorally-gone; JGAS-04 (Phase 319 GAS) empirically measures the single-call worst-case via gas-audit/gas-scavenger/gas-skeptic + confirms J4.2's derivation + attributes the delta to the removed `autoRebuyState` SLOAD; Phase 320 TERMINAL delta-audits the split removal (no payout stranded by the dropped `resumeEthPool` carry, no double/under-credit, freeze holds under rotation).

**Scope-fence check (item from the brief):** the entire JGAS footprint (J1) is removable **without touching winner-count/EV**. `DAILY_ETH_MAX_WINNERS=305`, `DAILY_JACKPOT_SCALE_MAX_BPS=63_600`, and the 159/95/50/1 bucket derivation (`bucketCountsForPoolCap`/`capBucketCounts`) are **NOT in the deletion set** — only the `splitMode`/`resumeEthPool`/`STAGE_*` *mechanism* that chunks those same 305 winners across two calls. The split-threshold constant `JACKPOT_MAX_WINNERS=160` becomes dead and is deleted, but it is a *split-routing* threshold, NOT a winner-count cap (the cap is `DAILY_ETH_MAX_WINNERS=305`, preserved). **Confirmed: JGAS removes only the split mechanism at the same 305-winner ceiling — zero winner-count / bucket-scaling / payout-EV change.** No footprint item forces an EV touch.

### JGAS Confidence Breakdown

- J1 footprint verification: **HIGH** — direct grep against live HEAD, every constant value + line confirmed; only 2× +1 resume-check line drifts (cosmetic).
- J2 stage-machine load-bearing analysis: **HIGH** — `stage` is function-local (not stored), `STAGE_JACKPOT_ETH_RESUME` only assigned+emitted (zero comparisons), `Advance` event not consumed on-chain.
- J3 combined slot re-derivation: **HIGH** — `forge inspect` authoritative; `resumeEthPool`@33 own-slot confirmed; zero contract slot literals re-confirmed.
- J4 design-intent + worst-case: **HIGH** for design-intent + footprint (source-traced); **MEDIUM** for the absolute gas figure (structural derivation, ±30%, not measured — hence the JGAS-04 empirical gate in the J4.4 lock).
- J5 VRF/freeze assessment: **HIGH** — `_unlockRng` placement traced; rng-lock-held-across-split confirmed; stage-number non-load-bearing confirmed; cross-tx-carry-removal reasoning source-grounded.

## RESEARCH COMPLETE
