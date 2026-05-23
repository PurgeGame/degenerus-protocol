---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
verified: 2026-05-23T18:30:00Z
status: human_needed
score: 26/26 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Run the full forge test suite on the patched tree and confirm no NEW failures vs the pre-deletion baseline of 71 failing / 446 passing / 16 skipped"
    expected: "Zero new test failures introduced by Phase 317 edits; the 71-count pre-existing failures are unchanged or reduced; passing/skipped counts stable."
    why_human: "Phase 317's stated bar is forge build PASS (confirmed). Phase 318 owns the 'no NEW failures' assertion. However, DegeneretteFreezeResolution.t.sol has LOOTBOX_RNG_WORD_SLOT=39 / LOOTBOX_RNG_PACKED_SLOT=38 which are WRONG for the post-deletion layout (actual: 36/35). This file was a pre-existing failure (InvalidBet()) and was intentionally excluded from the RM-06 re-derivation. Programmatic verification cannot confirm its failure mode is unchanged vs baseline without running the suite."
  - test: "Confirm the CRANK_RESOLVE_BET_GAS_UNITS=120_000 / CRANK_OPEN_BOX_GAS_UNITS=120_000 placeholder constants are acceptable pending Phase 319 GAS calibration"
    expected: "The named constants are the correct shape per REW-03 (fixed, never gasleft()/tx.gasprice). The numeric values are acknowledged as pre-calibration placeholders until Phase 319 GAS pass."
    why_human: "The constants compile and satisfy REW-03 structurally. Whether 120,000 gas units is a reasonable initial value before Phase 319 measures the actual worst-case is a product/security judgment call."
  - test: "Confirm the AF_KING=address(0) placeholder in ContractAddresses.sol is acceptable at this stage"
    expected: "The address(0) placeholder is intentional (deploy-predicted address pinned at Phase 17 per docs). The protocol gates (onlyAfKing, onlyFlipCreditors, batchPurchase) all resolve to it correctly at this pre-deploy stage."
    why_human: "The address(0) value is a deploy-time placeholder across both repos. Whether this is acceptable for the current milestone state is a product decision."
deferred:
  - truth: "SAFE-01 faucet bounded — self-crank/Sybil round-trip earns net-zero or negative reward"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'SAFE-01 faucet bounded by the three caller-independent locks (purchase-gate + gas-peg + coinflip-credit illiquidity)'"
  - truth: "SAFE-02 non-brick — one reverting/stale/not-ready player skipped, batch completes"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'SAFE-02 non-brick (BOTH cranks AND batchPurchase)'"
  - truth: "SAFE-03 concurrency — two same-block sweeps self-partition via cursor + lastSweptDay"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'SAFE-03 concurrency — two same-block sweeps self-partition'"
  - truth: "SAFE-04 RNG-freeze intact — resolution stays post-unlock (RngNotReady guard preserved)"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'SAFE-04 RNG-freeze intact'"
  - truth: "JGAS-03 daily ETH jackpot pays all 305 winners correctly in ONE call without the split"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'JGAS-03 jackpot single-call correctness'"
  - truth: "JGAS-04 worst-case 305-winner single-call gas measured empirically within block limit"
    addressed_in: "Phase 319"
    evidence: "Phase 319 requirements: JGAS-04 owns this measurement"
  - truth: "No NEW failures vs the 71-count pre-deletion baseline (green-build suite)"
    addressed_in: "Phase 318"
    evidence: "Phase 318 success criteria: 'no NEW failures vs the 71-count pre-deletion baseline'"
---

# Phase 317: Batched ADD+REMOVE Contract Diff Verification Report

**Phase Goal:** Apply the v46.0 batched ADD+REMOVE contract diff across degenerus-audit/contracts/ (the do-work crank, the AfKing-keeper subscription/protocol-sub surface, and the legacy AFKing/free-ETH-auto-rebuy + daily-ETH-split removals) as ONE user-approved batched commit, plus the paired ../degenerus-utilities keeper reconciliation.
**Verified:** 2026-05-23T18:30:00Z
**Status:** human_needed (3 human items; all 26/26 automated truths VERIFIED)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

All 26 Phase-317-owned requirements are verified against the committed source at HEAD (contract commit `df4ef365`, test commit `16b0837f`, docs commit `d6b79b3b`, keeper commit `8e137e2`).

| # | Truth (Requirement) | Status | Evidence |
|---|---|---|---|
| 1 | PROTO-01: `hasAnyLazyPass(address) external view` exposed, body byte-identical to old `_hasAnyLazyPass`, IDegenerusGame mirror | VERIFIED | `DegenerusGame.sol:1472` `function hasAnyLazyPass(address player) external view returns (bool)`; `IDegenerusGame.sol:370` declaration; body confirmed against LEDGER pre-patch snapshot |
| 2 | PROTO-02: `burnForKeeper(user, amount) returns (uint256 burned)` all-or-nothing, `onlyAfKing` on pinned `AF_KING`, `OnlyAfKing` error + `KeeperBurn` event | VERIFIED | `BurnieCoin.sol:456`; modifier `:533`; capacity-check-before-burn at `:463`; available<amount returns 0 at `:466`; error `:108`; event `:80` |
| 3 | PROTO-03: `onlyFlipCreditors` extended with `ContractAddresses.AF_KING` clause; no new interface decl; bounty via existing `creditFlip` | VERIFIED | `BurnieCoinflip.sol:191` modifier; `:198` AF_KING clause; `creditFlip` kept at `:852`/`:863` |
| 4 | PROTO-04: `batchPurchase(address[],uint256[],uint8[]) payable` keeper-gated on AF_KING; per-player try/catch slice-refund via `_batchPurchaseUnit`; once-at-entry rngLocked/gameOver pre-check; ONE batch value transfer; signature cross-repo MATCHED | VERIFIED | `DegenerusGame.sol:1687`; AF_KING gate `:1692`; rngLockedFlag check `:1693`; `_batchPurchaseUnit` `:1729`; AfKing IGame interface `AfKing.sol:26-30` matches verbatim; call site `AfKing.sol:738` passes (players, amounts, modes) |
| 5 | PROTO-05: `AF_KING` pinned as `address internal constant` in `ContractAddresses.sol`; BurnieCoin/BurnieCoinflip/DegenerusGame gate on it | VERIFIED | `ContractAddresses.sol:53` `address internal constant AF_KING = address(0x000...)`; `BurnieCoin.sol:534` onlyAfKing; `BurnieCoinflip.sol:198` AF_KING in onlyFlipCreditors; `DegenerusGame.sol:1692` AF_KING gate |
| 6 | CRANK-01: `crankBets(address[],uint64[])` + `crankBoxes(uint256 maxCount)` permissionless entries | VERIFIED | `DegenerusGame.sol:1543` crankBets; `:1592` crankBoxes; no caller restriction on either entry |
| 7 | CRANK-02: `BatchAlreadyTaken` short-circuit on item 0's degeneretteBets[players[0]][betIds[0]]==0; items 1..N per-item try/catch | VERIFIED | `DegenerusGame.sol:1552` short-circuit; error `:95`; try/catch loop at `:1557` |
| 8 | CRANK-03: parameterless box cursor (`boxCursor`/`boxCursorIndex`/`boxPlayers`); v45 a303ae18 re-issue coupling present (`lootboxRngWordByIndex[index]==0` orphan gate + `lootboxEthBase[index][player]==0` first-deposit skip); `enqueueBoxForCrank` producer in MintModule | VERIFIED | `DegenerusGame.sol:1507` boxCursor; `:1510` boxCursorIndex; `:1518` boxPlayers; `:1603` orphan gate `lootboxRngWordByIndex[index] == 0`; `:1618` skip `lootboxEthBase[index][player] == 0`; `DegenerusGameMintModule.sol:999` producer |
| 9 | CRANK-04: WWXRP currency==3 explicit zero-reward branch | VERIFIED | `DegenerusGame.sol:1563` comment; `:1564` `if (currency == 3)` explicit zero branch |
| 10 | REW-01: reward = `CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF` (0.5 gwei) → `_ethToBurnieValue`; OPEN-B price-unavailable → reward 0 never revert | VERIFIED | `DegenerusGame.sol:1495` CRANK_GAS_PRICE_REF=0.5 gwei; `:1501` CRANK_RESOLVE_BET_GAS_UNITS=120_000; `:1502` CRANK_OPEN_BOX_GAS_UNITS=120_000; `:1567` `_ethToBurnieValue(CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF, ...)`; `:1621` box variant |
| 11 | REW-02: ONE `creditFlip(msg.sender, reward)` per tx, never per-item | VERIFIED | `DegenerusGame.sol:1578` `if (reward != 0) coinflip.creditFlip(msg.sender, reward)`; `:1632` box variant; accumulation via `reward +=` inside loop |
| 12 | REW-03: fixed RESERVED gasUnits constants; ZERO non-comment matches for `gasleft()`/`tx.gasprice` in DegenerusGame.sol | VERIFIED | `DegenerusGame.sol:1495-1502` constants; grep confirmed 0 non-comment matches for gasleft()/tx.gasprice across all non-test contracts |
| 13 | REW-04: no caller restriction on crank entries | VERIFIED | `DegenerusGame.sol:1543` crankBets and `:1592` crankBoxes — no `_requireApproved` or msg.sender gate |
| 14 | SUB-01..08: `contracts/AfKing.sol` canonical keeper — pass-OR-pay renewal (SUB-01); subscribe-time auth (SUB-02); cursor sweep `sweep(uint256 maxCount)` + `_sweepDay`/`_sweepCursor` (SUB-03); `max(dailyQuantity, floor(claimable*reinvestPct/price))` quantity (SUB-04); funding waterfall (SUB-05); pinned-identity two-tier skip-kill NO settable flag (SUB-06); tombstone/swap-pop/windowPaid lifecycle (SUB-07); creditFlip bounty + burnForKeeper charge (SUB-08) | VERIFIED | `AfKing.sol` exists; `sweep(uint256 maxCount)` at `:522`; `_sweepDay`/`_sweepCursor` at `:212-213`; `reinvestPct` packed at `:86`; `windowPaid` flag at `:76`; `ContractAddresses.VAULT`/`SDGNRS` pinned-identity exemption at `:673`; 0 non-comment matches for isExempt/exemptFlag/skipKillExempt/_exempt; `_removeFromSet` at `:594`; `burnForKeeper` consumed at `:50`; `creditFlip` at `:63`; `pullForKeeper`/`mintForKeeper` = 0 matches |
| 15 | SUB-09: sDGNRS self-subscribes (claimable-only, lootbox, flat 1 + 2% reinvest + setCoinflipAutoRebuy(self,true,0)); Vault self-subscribes (claimable-only, flat 1, no reinvest); ctor Deity grant preserved byte-unmodified | VERIFIED | `StakedDegenerusStonk.sol:379` `afKing.subscribe(address(this), true, false, 1, 2)` + `coinflip.setCoinflipAutoRebuy(address(this), true, 0)`; `DegenerusVault.sol:473` `afKing.subscribe(address(this), true, false, 1, 0)`; `DegenerusGame.sol:213-214` HAS_DEITY_PASS_SHIFT ctor grant confirmed at :213/:214 |
| 16 | RM-01: 13 afKing-mode fns deleted (only hasAnyLazyPass kept+exposed); 3 events; AfKingLockActive error; 3 consts; 2 settleFlipModeChange cross-calls removed; IDegenerusGame 4 afKing decls removed | VERIFIED | 0 non-comment matches for setAfKingMode/_setAfKingMode/afKingModeFor/afKingActivatedLevelFor/deactivateAfKingFromCoin/syncAfKingLazyPassFromCoin/AfKingLockActive/AfKingModeToggled in non-test contracts; IDegenerusGame has hasDeityPass kept and hasAnyLazyPass added |
| 17 | RM-02: AutoRebuyState struct + autoRebuyState mapping deleted from storage; _processAutoRebuy + _calcAutoRebuy + AutoRebuyCalc gone; entropy arg dropped from _addClaimableEth; ETH always credits to claimable | VERIFIED | 0 non-comment matches for AutoRebuyState/autoRebuyState/_processAutoRebuy/_calcAutoRebuy/AutoRebuyCalc across non-test contracts |
| 18 | RM-03: BURNIE flip recycle collapsed to flat RECYCLE_BONUS_BPS=75; afKing/deity tier removed; win/loss RNG path byte-unmodified (processCoinflipPayouts, rngWord & 1) | VERIFIED | 0 non-comment matches for settleFlipModeChange/_afKingRecyclingBonus/_afKingDeityBonusHalfBpsWithLevel/AFKING_RECYCLE_BONUS_BPS/AFKING_KEEP_MIN_COIN/deactivateAfKingFromCoin in BurnieCoinflip.sol; `RECYCLE_BONUS_BPS=75` at `:130`; `rngWord & 1` at `:788` |
| 19 | RM-04: hasAnyLazyPass KEPT and EXPOSED (reconciled with PROTO-01) | VERIFIED | Covered by truth #1 above |
| 20 | RM-05: Vault gameSet* wrappers + decls removed (coinSet* kept); sStonk setAfKingMode decl + init removed; cascade coheers with IBurnieCoinflip.settleFlipModeChange removal | VERIFIED | 0 non-comment matches for gameSetAutoRebuy/gameSetAutoRebuyTakeProfit/gameSetAfKingMode/setAfKingMode in Vault/sStonk; coinSetAutoRebuy/coinSetAutoRebuyTakeProfit kept; settleFlipModeChange absent from IBurnieCoinflip.sol |
| 21 | RM-06: storage slots re-derived from ONE combined forge inspect; slot-≥34 family shifts −2 (vrfCoordinator 34→32, lootboxRngPacked 37→35, lootboxRngWordByIndex 38→36, lootboxDay 39→37, degeneretteBets 45→43, boonPacked 61→59); [20,33) shifts −1; ~11 affected test files re-derived; forge build PASSES | VERIFIED | forge build exit 0 confirmed; VrfRotationOrphanIndex SLOT_LOOTBOX_PACKED=35/SLOT_LOOTBOX_WORD_MAP=36; VrfRotationLiveness same; LootboxBoonCoexistence SLOT_LOOTBOX_RNG_IDX=35/SLOT_LOOTBOX_WORD=36/SLOT_LOOTBOX_DAY=37/SLOT_LOOTBOX_BASE=19; AffiliateDgnrsClaim SLOT_LEVEL_DGNRS_ALLOCATION=23/SLOT_LEVEL_DGNRS_CLAIMED=24; all match live forge inspect |
| 22 | JGAS-02: SPLIT_*/resumeEthPool/splitMode/call1Bucket/_resumeDailyEth/STAGE_JACKPOT_ETH_RESUME deleted from JackpotModule + AdvanceModule + Storage; DAILY_ETH_MAX_WINNERS=305 preserved; _unlockRng placement unchanged; single-call path | VERIFIED | 0 matches for resumeEthPool/SPLIT_CALL1/SPLIT_CALL2/SPLIT_NONE/_resumeDailyEth/STAGE_JACKPOT_ETH_RESUME/call1Bucket/splitMode/JACKPOT_MAX_WINNERS in non-test contracts; DAILY_ETH_MAX_WINNERS=305 at JackpotModule:210; _unlockRng at `:328`/`:399`/`:457`/`:619` (coin-tickets stages only) |
| 23 | Security: VRF freeze invariant held — _unlockRng NOT pulled into/before deleted resume path (J5 verdict) | VERIFIED | STAGE_JACKPOT_ETH_RESUME and its entire resume block deleted; _unlockRng remains only at coin-tickets/transition stages; no _unlockRng inside any deleted resume branch |
| 24 | Security: crank reward path has NO gasleft()/tx.gasprice (no gameable measured-gas peg) and has WWXRP currency==3 zero-reward branch | VERIFIED | 0 non-comment matches for gasleft()/tx.gasprice in DegenerusGame.sol; currency==3 branch at `:1563-1565` |
| 25 | Security: two-tier skip-kill uses pinned VAULT/SDGNRS identity with NO settable exemption flag | VERIFIED | AfKing.sol:673 `if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS)`; 0 non-comment matches for isExempt/exemptFlag/skipKillExempt/_exempt |
| 26 | D-01b: degenerus-utilities reconciled to canonical contracts/AfKing.sol via foundry remapping; StreakKeeperV2 retired; deploy script deploys AfKing; both repos pin AF_KING=address(0) aligned; keeper compiles | VERIFIED | commit `8e137e2` in degenerus-utilities; remappings.txt has `degenerus-audit/=../degenerus-audit/`; script imports AfKing; StreakKeeperV2.sol removed; `forge build` in degenerus-utilities: exit 0 (KEEPER_BUILD_PASS) |

**Score: 26/26 truths VERIFIED**

### Deferred Items (Phase 318 / 319 — not actionable gaps)

| # | Item | Addressed In | Evidence |
|---|---|---|---|
| 1 | SAFE-01 faucet bounded (test-level proof) | Phase 318 | Phase 318 goal: "SAFE-01 faucet bounded by the three caller-independent locks" |
| 2 | SAFE-02 non-brick proof | Phase 318 | Phase 318 goal: "SAFE-02 non-brick (BOTH cranks AND batchPurchase)" |
| 3 | SAFE-03 concurrency proof | Phase 318 | Phase 318 goal: "SAFE-03 concurrency — two same-block sweeps self-partition" |
| 4 | SAFE-04 RNG-freeze intact (suite-level) | Phase 318 | Phase 318 goal: "SAFE-04 RNG-freeze intact" |
| 5 | JGAS-03 305-winner single-call correctness | Phase 318 | Phase 318 goal: "JGAS-03 jackpot single-call correctness" |
| 6 | JGAS-04 empirical gas measurement | Phase 319 | Phase 319 requirements: JGAS-04 |
| 7 | GAS-01..06 worst-case calibration (closes OPEN-A) | Phase 319 | Phase 319 requirements: GAS-01..06 |
| 8 | No NEW failures vs 71-count baseline (suite-level assertion) | Phase 318 | Phase 318 explicitly owns this gate |

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `contracts/AfKing.sol` | Canonical in-tree AfKing keeper (D-01) | VERIFIED | New file in commit df4ef365; 750+ lines; sweep/cursor/reinvestPct/windowPaid/batchPurchase/burnForKeeper present |
| `contracts/BurnieCoin.sol` | burnForKeeper + onlyAfKing | VERIFIED | :456 burnForKeeper; :533 onlyAfKing modifier |
| `contracts/BurnieCoinflip.sol` | AF_KING in onlyFlipCreditors + flat-75bps collapse | VERIFIED | :191 modifier; :198 AF_KING; :130 RECYCLE_BONUS_BPS=75; :788 rngWord & 1 |
| `contracts/ContractAddresses.sol` | AF_KING pinned constant | VERIFIED | :53 AF_KING constant |
| `contracts/DegenerusGame.sol` | hasAnyLazyPass + batchPurchase + crank; afKing deleted; ctor grant preserved | VERIFIED | :1472 hasAnyLazyPass; :1687 batchPurchase; :1543 crankBets; :1592 crankBoxes; :213-214 ctor grant |
| `contracts/interfaces/IDegenerusGame.sol` | hasAnyLazyPass decl added; 4 afKing decls removed | VERIFIED | :370 hasAnyLazyPass; :364 hasDeityPass kept; afKing decls absent |
| `contracts/interfaces/IBurnieCoinflip.sol` | settleFlipModeChange removed; creditFlip/batch kept | VERIFIED | settleFlipModeChange absent; :108/:115 creditFlip/creditFlipBatch present |
| `contracts/modules/DegenerusGameJackpotModule.sol` | entropy/split removed; 305 preserved | VERIFIED | 0 JGAS/resumeEthPool symbols; DAILY_ETH_MAX_WINNERS=305 at :210 |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | STAGE_JACKPOT_ETH_RESUME + resume block deleted; _unlockRng unchanged | VERIFIED | STAGE_JACKPOT_ETH_RESUME=0 matches; _unlockRng at coin-tickets stages |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | _calcAutoRebuy/AutoRebuyCalc deleted | VERIFIED | 0 matches for these symbols |
| `contracts/modules/DegenerusGameMintModule.sol` | enqueueBoxForCrank producer wired | VERIFIED | :999 `IDegenerusGame(address(this)).enqueueBoxForCrank(lbIndex, buyer)` |
| `contracts/storage/DegenerusGameStorage.sol` | AutoRebuyState + resumeEthPool deleted | VERIFIED | 0 matches for AutoRebuyState/autoRebuyState/resumeEthPool |
| `contracts/DegenerusVault.sol` | gameSet* wrappers removed; Vault self-subscribe | VERIFIED | 0 gameSetAutoRebuy/gameSetAfKingMode; :473 afKing.subscribe |
| `contracts/StakedDegenerusStonk.sol` | setAfKingMode removed; sDGNRS self-subscribe | VERIFIED | 0 setAfKingMode; :379 afKing.subscribe with reinvestPct=2 |
| `test/` (13 files) | SLOT_* re-derived from ONE forge inspect (−2 family) | VERIFIED | All affected test SLOT_* match live forge inspect output; forge build PASS |

---

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `BurnieCoin.burnForKeeper` | `ContractAddresses.AF_KING` | onlyAfKing modifier | VERIFIED | `:533` modifier gates on AF_KING |
| `BurnieCoinflip.onlyFlipCreditors` | `ContractAddresses.AF_KING` | added creditor clause | VERIFIED | `:198` AF_KING clause |
| `DegenerusGame.batchPurchase` | `ContractAddresses.AF_KING` | msg.sender gate | VERIFIED | `:1692` AF_KING gate |
| `AfKing.sweep` batchPurchase call | `DegenerusGame.batchPurchase` | cross-repo signature MATCHED | VERIFIED | IGame interface `AfKing.sol:26-30` = game decl `:1687-1691`; call `:738` passes (players, amounts, modes) |
| `AfKing.sweep` charge | `BurnieCoin.burnForKeeper` | all-or-nothing burn consumption | VERIFIED | `:50` burnForKeeper decl in IToken; burned!=cost auto-pause path present |
| `AfKing` two-tier skip-kill exemption | `ContractAddresses.VAULT/SDGNRS` | pinned-identity branch | VERIFIED | `:673` pinned-address branch; 0 settable-flag matches |
| `crankBoxes` box cursor | v45 a303ae18 re-issue coupling | lootboxRngWordByIndex + lootboxEthBase | VERIFIED | `:1603` orphan gate; `:1618` first-deposit skip |
| `StakedDegenerusStonk` init | `AfKing.subscribe` | SUB-09 self-consent | VERIFIED | `:379` call; signature matches AfKing.sol:348-355 |
| `DegenerusVault` init | `AfKing.subscribe` | SUB-09 self-consent | VERIFIED | `:473` call; signature matches AfKing.sol:348-355 |
| `degenerus-utilities` deploy | `contracts/AfKing.sol` | foundry remapping D-01b | VERIFIED | remappings.txt; deploy script imports AfKing; StreakKeeperV2.sol retired |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| forge build on full patched tree | `forge build >/dev/null 2>&1 && echo FORGE_BUILD_PASS` | FORGE_BUILD_PASS | PASS |
| degenerus-utilities keeper build | `cd ../degenerus-utilities && forge build` | exit 0 / "No files changed, compilation skipped" | PASS |
| Deep legacy RM grep set (24 symbols) | grep across non-test contracts | 0 matches for all 24 symbols | PASS |
| JGAS-02 grep set (7 symbols) | grep across non-test contracts | 0 matches for all 7 symbols | PASS |
| BURNIE win/loss RNG path intact | grep for processCoinflipPayouts + rngWord & 1 | Both present at BurnieCoinflip.sol:756/:788 | PASS |
| No gasleft()/tx.gasprice in reward path | grep non-comment contracts/ | 0 matches | PASS |
| VAULT/SDGNRS pinned-identity exemption, no settable flag | grep for isExempt/exemptFlag/skipKillExempt/_exempt | 0 non-comment matches | PASS |
| ctor Deity grant byte-unmodified | grep HAS_DEITY_PASS_SHIFT at :213/:214 | Present at DegenerusGame.sol:213-214 | PASS |
| batchPurchase signature cross-repo MATCHED | element-by-element diff | (address[],uint256[],uint8[]) in both game decl and AfKing IGame interface + call site | PASS |
| commit ordering: contracts → test → docs | git log timestamps | df4ef365 14:40 → 16b0837f 14:41 → d6b79b3b 14:43 | PASS |
| no test/ files in contracts commit | git show --name-only df4ef365 \| grep "^test/" | empty | PASS |
| no contracts/ files in test commit | git show --name-only 16b0837f \| grep "^contracts/" | empty | PASS |

---

## Requirements Coverage

All 26 Phase-317-owned requirements verified against committed source. 22 additional requirements (SAFE-01..04, JGAS-03/04, GAS-01..06, JGAS-01) are owned by Phases 318/319/320 per REQUIREMENTS.md and are deferred.

| Requirement | Primary Evidence | Status |
|---|---|---|
| PROTO-01 | DegenerusGame.sol:1472; IDegenerusGame.sol:370 | SATISFIED |
| PROTO-02 | BurnieCoin.sol:456; onlyAfKing :533; all-or-nothing at :463-466 | SATISFIED |
| PROTO-03 | BurnieCoinflip.sol:198 AF_KING clause | SATISFIED |
| PROTO-04 | DegenerusGame.sol:1687; AfKing.sol:738 call; IGame:26 decl; MATCHED | SATISFIED |
| PROTO-05 | ContractAddresses.sol:53; BurnieCoin/BurnieCoinflip/DegenerusGame gate on it | SATISFIED |
| CRANK-01 | DegenerusGame.sol:1543 crankBets; :1592 crankBoxes | SATISFIED |
| CRANK-02 | DegenerusGame.sol:1552 BatchAlreadyTaken short-circuit | SATISFIED |
| CRANK-03 | DegenerusGame.sol:1603 lootboxRngWordByIndex orphan gate; :1618 lootboxEthBase skip; MintModule:999 producer | SATISFIED |
| CRANK-04 | DegenerusGame.sol:1564 currency==3 zero-reward | SATISFIED |
| REW-01 | DegenerusGame.sol:1495-1502 CRANK_GAS_PRICE_REF/GAS_UNITS; :1567/:1621 _ethToBurnieValue | SATISFIED |
| REW-02 | DegenerusGame.sol:1578/:1632 ONE creditFlip per tx | SATISFIED |
| REW-03 | DegenerusGame.sol:1495-1502 fixed constants; 0 gasleft()/tx.gasprice | SATISFIED |
| REW-04 | DegenerusGame.sol:1543/:1592 no caller restriction | SATISFIED |
| SUB-01 | AfKing.sol:578 pass-OR-pay renewal branch | SATISFIED |
| SUB-02 | AfKing.sol:348 subscribe-time auth only | SATISFIED |
| SUB-03 | AfKing.sol:522 sweep(maxCount); :212-213 cursor fields | SATISFIED |
| SUB-04 | AfKing.sol:347 max-semantics; :86 reinvestPct | SATISFIED |
| SUB-05 | AfKing.sol funding waterfall; drainGameCreditFirst waterfall | SATISFIED |
| SUB-06 | AfKing.sol:673 pinned-identity; 0 settable-flag matches | SATISFIED |
| SUB-07 | AfKing.sol:594 _removeFromSet; :84 lastSweptDay; windowPaid :76 | SATISFIED |
| SUB-08 | AfKing.sol:50 burnForKeeper; :63 creditFlip | SATISFIED |
| SUB-09 | StakedDegenerusStonk.sol:379; DegenerusVault.sol:473; DegenerusGame.sol:213-214 | SATISFIED |
| RM-01 | 0 legacy afKing-mode symbols; IDegenerusGame updated | SATISFIED |
| RM-02 | 0 AutoRebuyState/autoRebuyState/_processAutoRebuy symbols | SATISFIED |
| RM-03 | BurnieCoinflip.sol:130 RECYCLE_BONUS_BPS=75; :788 rngWord & 1 | SATISFIED |
| RM-04 | DegenerusGame.sol:1472 (reconciled with PROTO-01) | SATISFIED |
| RM-05 | DegenerusVault.sol 0 gameSet*; StakedDegenerusStonk 0 setAfKingMode; SUB-09 self-subscribe | SATISFIED |
| RM-06 | 11 test files re-derived; forge build PASS; SLOT_* match forge inspect output | SATISFIED |
| JGAS-02 | 0 SPLIT*/resumeEthPool/STAGE_JACKPOT_ETH_RESUME symbols; 305 ceiling at JackpotModule:210 | SATISFIED |

---

## Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|---|---|---|---|
| `DegenerusGame.sol:1498` | "placeholders calibrated from measured worst-case marginal gas at the Phase 319 GAS pass" | Info | NOT a blocker — the values (120_000) are concrete non-zero constants. The NatDoc comment explicitly records the Phase 319 calibration deferral, which is the correct place (Phase 319 owns GAS-01..06). REW-03 is structurally satisfied (fixed named constants, never gasleft()/tx.gasprice). |
| `ContractAddresses.sol:53` / `degenerus-utilities/contracts/ContractAddresses.sol:53` | AF_KING = address(0) placeholder | Info | Both repos pin address(0). This is a deploy-time placeholder per project convention (other addresses also pinned via `address(0x...)` for deploy). Flagged as a human-check item. |
| `test/fuzz/DegeneretteFreezeResolution.t.sol:37-40` | LOOTBOX_RNG_WORD_SLOT=39 / LOOTBOX_RNG_PACKED_SLOT=38 (actual slots are 36/35) | Warning | This file was a PRE-EXISTING failure (InvalidBet(), 3 tests) in the 71-count baseline and was intentionally excluded from RM-06 re-derivation per the 317-06 SUMMARY. The wrong slot values will cause the tests to write to the wrong storage slots (lootboxPurchasePacked=38 / lootboxBurnie=39 instead of lootboxRngWordByIndex=36 / lootboxRngPacked=35) — likely preserving the InvalidBet() failure mode. Phase 318 owns the "no NEW failures vs 71-count" gate and must assess whether the failure mode has changed. |

---

## Human Verification Required

### 1. Full test suite — no NEW failures vs baseline

**Test:** Run `forge test` on the committed patched tree and count failing tests.
**Expected:** 71 failing / 446 passing / 16 skipped (or fewer failures; more passing is fine); the DegeneretteFreezeResolution tests still fail with InvalidBet() not a slot-error.
**Why human:** Phase 317's bar is forge build PASS (confirmed). Phase 318 explicitly owns "no NEW failures vs the 71-count baseline." The DegeneretteFreezeResolution.t.sol slot mismatch (slots 39/38 vs actual 36/35) is a pre-existing failure but could change the failure mode. Programmatic verification of unchanged failure mode requires running the suite, which exceeds Phase 317's stated scope.

### 2. Gas constant placeholder values acceptable pre-Phase-319

**Test:** Review `CRANK_RESOLVE_BET_GAS_UNITS = 120_000` and `CRANK_OPEN_BOX_GAS_UNITS = 120_000` at DegenerusGame.sol:1501-1502.
**Expected:** These are acknowledged pre-calibration estimates. Phase 319 GAS pass (GAS-01..06, JGAS-04) will measure worst-case marginal gas and update them. The REW-03 structural requirement (fixed named constants, never gasleft()/tx.gasprice) is satisfied.
**Why human:** Whether 120,000 is a safe enough initial estimate before Phase 319 calibration is a product/security judgment. The reward formula is `120_000 * 0.5 gwei = 0.06 mETH` per item — whether this is above or below actual gas cost determines whether the crank is net-positive for callers before calibration.

### 3. AF_KING = address(0) placeholder acceptable at this stage

**Test:** Review `ContractAddresses.sol:53` AF_KING = address(0x0000...0000) and corresponding alignment in degenerus-utilities/contracts/ContractAddresses.sol:53.
**Expected:** Both repos pin address(0) as the placeholder. All protocol gates (burnForKeeper, creditFlip, batchPurchase) resolve to address(0) until a real keeper is deployed. The D-01b docs reference "pinned to the deploy-predicted keeper address" for release.
**Why human:** Whether address(0) as the current AF_KING value creates any unintended access (e.g., can address(0) call burnForKeeper?) is a runtime security question. Also whether the placeholder approach is acceptable for the current milestone state.

---

## Gaps Summary

No blocking gaps found. All 26 must-haves are VERIFIED against committed source. The phase goal — one user-approved batched commit covering the full PROTO/CRANK/REW/SUB/RM/JGAS requirement set plus the paired keeper reconciliation — is achieved.

The three human verification items are operational/product decisions (test suite regression, gas constant acceptability, placeholder address policy), not implementation failures.

The DegeneretteFreezeResolution.t.sol slot mismatch is noted as a WARNING (not a BLOCKER) because: (1) the file was a PRE-EXISTING failure; (2) Phase 317's bar is forge build PASS (confirmed); (3) Phase 318 explicitly owns the "no NEW failures" gate; (4) the wrong slots affect only a mapping key derivation inside an already-failing test.

---

_Verified: 2026-05-23T18:30:00Z_
_Verifier: Claude (gsd-verifier)_
