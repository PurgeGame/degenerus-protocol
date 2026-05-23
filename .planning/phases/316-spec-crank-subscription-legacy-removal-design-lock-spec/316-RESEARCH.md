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
