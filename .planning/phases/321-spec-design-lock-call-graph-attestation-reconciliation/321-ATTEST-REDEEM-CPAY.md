# 321 — Call-Graph Attestation: sDGNRS-Redemption + Universal-Claimable-Pay

**Mode:** READ-ONLY. No `contracts/` edits. Sources read from `contracts/` only (stale copies ignored).
**Date:** 2026-05-24
**Plans reconciled:**
- `.planning/PLAN-SDGNRS-REDEMPTION-ACCOUNTING.md` (plan-1, "REDEEM")
- `.planning/PLAN-UNIVERSAL-CLAIMABLE-PAY.md` (plan-2, "CPAY")

Notation per anchor: `ANCHOR (claimed) → ACTUAL → MATCH | SHIFTED(±N) | ABSENT`.
SHIFTED means the cited symbol/code exists but at a different line (lines drift since the plans were written); the substance is unchanged unless flagged.

---

## A. ATTESTATION TABLE

### A.1 — REDEEM plan anchors

| # | Anchor (claimed) | Symbol | Actual | Verdict |
|---|---|---|---|---|
| R1 | `StakedDegenerusStonk.sol:379` ctor `afKing.subscribe(this,true,false,1,2)` | sDGNRS SUB-09 self-subscription | `:380` `afKing.subscribe(address(this), true, false, 1, 2, address(0));` | **SHIFTED(+1)** — signature has the v46 OPEN-E `address(0)` 6th arg (fundingSource). See §C. |
| R2 | `StakedDegenerusStonk.sol` `_submitGamblingClaimFrom` | private fn | `:824-910` (decl `:824`) | MATCH (full body §B.1) |
| R3 | `ethValueOwed` base compute | inside R2 | `:855-860` (`totalMoney = ethBal+stethBal+claimableEth - pendingRedemptionEthValue`; `ethValueOwed = totalMoney*amount/supplyBefore`) | MATCH |
| R4 | BURNIE base compute | inside R2 | `:862-866` (`totalBurnie = burnieBal+claimableBurnie - pendingRedemptionBurnie`; `burnieOwed = totalBurnie*amount/supplyBefore`) | MATCH |
| R5 | day keying | inside R2 | `:829` `currentPeriod = game.currentDayView()`; `:894-895` composite key `pendingRedemptions[beneficiary][currentPeriod]` | MATCH |
| R6 | `resolveRedemptionPeriod` ETH `pendingRedemptionEthValue = … - ethBase + rolledEth` :659 | ETH release | `:660` | **SHIFTED(+1)** |
| R7 | `resolveRedemptionPeriod` BURNIE `pendingRedemptionBurnie -= burnieBase` :665 | BURNIE release | `:666` | **SHIFTED(+1)** |
| R8 | `burnieToCredit` :662 | rolled BURNIE (emit-only) | `:663` `burnieToCredit = (burnieBase*roll)/100` — used only in `emit RedemptionResolved` (`:674`); confirms the §2-DefectB "computed but not added to the reserve release" claim | **SHIFTED(+1)** — defect confirmed |
| R9 | `claimRedemption` BURNIE-before-ETH ordering :746 vs :753 | ordering | `_payBurnie` at `:748` (guard `:747`), `_payEth` at `:754` — BURNIE still before ETH | **SHIFTED(+1/+1)**; ordering defect confirmed |
| R10 | partial-claim BURNIE branch | inside claimRedemption | `:730-736` (`flipResolved` → full delete; else `claim.ethValueOwed = 0`, keep BURNIE); day+1/flipDay lookup `:719-725` | MATCH |
| R11 | `game.claimWinnings(address(0))` pull :917 (in `_payEth`) | ETH-claim pull | `:919` `game.claimWinnings(address(0));` (guarded `:918` `amount > ethBal && claimableEth != 0`) | **SHIFTED(+2)** |
| R12 | `_payEth` :917 area | private fn | `:913-935` | **SHIFTED**; full body §B.4 |
| R13 | `_payBurnie` :937-948 | private fn | `:938-949` | **SHIFTED(+1)**; full body §B.5 |
| R14 | `claimCoinflipsForRedemption` | sDGNRS-gated coinflip pull | iface decl `StakedDegenerusStonk.sol:49`; impl `BurnieCoinflip.sol:333-339` (gate `msg.sender != SDGNRS`) | MATCH |
| R15 | `previewBurn` reserve terms | view | `:769-799` (`- pendingRedemptionEthValue` `:776`/`:781`; `- pendingRedemptionBurnie` `:796`) | MATCH (body §B.6) |
| R16 | `burnieReserve` reserve term | view | `:804-808` (`burnieBal + claimableBurnie - pendingRedemptionBurnie`) | MATCH |
| R17 | `RedemptionPeriod` struct `.flipDay` | struct | `:231-234` (`uint16 roll; uint32 flipDay;`) | MATCH |
| R18 | `PendingRedemption` struct | struct | `:225-229` (`uint96 ethValueOwed; uint96 burnieOwed; uint16 activityScore;`) | MATCH |
| R19 | `pendingRedemptionBurnie` global :795/:864/:806 | storage + reads | decl `:266` (`internal`); reads `:796` (previewBurn), `:865` (submit), `:807` (burnieReserve); release `:666` | **SHIFTED**; claimed `795→796`, `864→865`, `806→807` (all +1) |
| R20 | `pendingRedemptionEthValue` global | storage + reads | decl `:265` (`public`); used `:594`, `:660`, `:728`, `:776`, `:780-781`, `:859`, `:889` | MATCH (cross-ref) |
| R21 | `DegenerusGame.sol:1797-1806` `resolveRedemptionLootbox` unchecked claimable debit + `claimablePool -= uint128(amount)` | joint plan-1/plan-5 edit target | `:1788-1838` fn; debit block `:1802-1806`; `unchecked` `:1803-1805`; `claimablePool -= uint128(amount)` `:1806` | **SHIFTED(≈0)** — debit lands exactly in claimed `:1797-1806` range. Full sig+body §D. |
| R22 | `claimableWinnings` / `claimablePool` declarations | storage | `DegenerusGameStorage.sol:401` `mapping(address => uint256) internal claimableWinnings;`; `:354` `uint128 internal claimablePool;` (NOT in DegenerusGame.sol — base storage contract) | MATCH (relocated to storage base) |
| R23 | `ContractAddresses.SDGNRS` usage | constant | `ContractAddresses.sol:47` `address internal constant SDGNRS = …`; used in resolveRedemptionLootbox gate `:1794` + debit `:1802/:1804` | MATCH |
| R24 | `GameOverModule.sol:91-92` `reserved = claimablePool + pendingRedemptionEthValue` (pre-refund) | gameOver double-count | `:91-92` exact | **MATCH** |
| R25 | `GameOverModule.sol:154-155` postRefundReserved | gameOver double-count (2nd site) | `:154-155` exact | **MATCH** |
| R26 | `BurnieCoinflip.sol:191-201` `onlyFlipCreditors` | creditor gate | `:191-201` exact | **MATCH** (body §E) |
| R27 | `BurnieCoinflip.sol:374-377` `_claimCoinflipsAmount` clamp `min(amount,stored)` | clamp | `:374-377` (`toClaim=amount; if(toClaim>stored) toClaim=stored;`) | **MATCH** |
| R28 | `consumeCoinflipsForBurn` | onlyBurnieCoin no-mint claim | `:356-361` (`onlyBurnieCoin`; `_claimCoinflipsAmount(player,amount,false)`) | MATCH |
| R29 | `creditFlip` | onlyFlipCreditors deferred mint | `:849-855` (`onlyFlipCreditors`; `_addDailyFlip(player,amount,0,false,false)`) | MATCH |
| R30 | `previewClaimCoinflips` | view | `:882-886` (`_viewClaimableCoin + claimableStored`) | MATCH |
| R31 | `BurnieCoin.sol` `mintForGame` | gated mint | `:439-443` (gate `COINFLIP \|\| GAME`) | MATCH |
| R32 | `BurnieCoin.sol` burn fns + gates | burn surface | `_burn` `:401` (internal, VAULT-allowance branch); `burnForCoinflip` `:430` (`COINFLIP`); `burnForKeeper` `:456` (`onlyAfKing`); `burnCoin` `:586` (`onlyGame`); `decimatorBurn` `:607`; `terminalDecimatorBurn` `:682`. **No SDGNRS-gated burn exists yet** → new fn required (plan §6). | MATCH (surface) + see §F blocker note |
| R33 | `DegenerusGameJackpotModule.sol:720` 23% yield-surplus credit to `claimableWinnings[SDGNRS]` | sDGNRS backing source | `:720` `uint256 d1 = _addClaimableEth(ContractAddresses.SDGNRS, quarterShare);` (via helper, NOT a bare `claimableWinnings[SDGNRS]=`; `quarterShare = yieldPool*2300/10_000` `:716`) | **MATCH** (line exact; mechanism = `_addClaimableEth` helper) |

### A.2 — CPAY plan anchors

| # | Anchor (claimed) | Symbol | Actual | Verdict |
|---|---|---|---|---|
| C1 | `WhaleModule:262` `purchaseWhaleBundle` `if (msg.value != totalPrice) revert E()` | edit target | `:262` exact; fn decl `:187` | **MATCH** (block §G.1) |
| C2 | `WhaleModule:474` `purchaseLazyPass` exact `msg.value` | edit target | `:474` exact; fn decl `:380` | **MATCH** (block §G.2) |
| C3 | `WhaleModule:581` `purchaseDeityPass` exact `msg.value` | edit target | `:581` exact; fn decl `:538` | **MATCH** (block §G.3) |
| C4 | `MintModule:930-949` canonical shortfall pattern | reference pattern | core block `:929-951`; the `:930-949` span is the lootbox-shortfall branch (msg.value first → claimable shortfall → STRICT sentinel `:945` → `claimablePool -= shortfall` `:949`) | **MATCH** (pattern §H.1) |
| C5 | `DegeneretteModule:526-530` ETH-bet claimable pull | reference pattern | `_collectBetFunds` `:516`; pull block `:525-530` (`fromClaimable` `:526`; STRICT `<=` `:527`; debit `:529`; `claimablePool -= ` `:530`) | **MATCH** (note: actual = `DegenerusGameDegeneretteModule.sol`) |
| C6 | `DegenerusGame:917` strict-sentinel reference | sentinel pattern | `:917` `uint256 available = claimable - 1; // Preserve 1 wei sentinel` (Combined-payment branch of `recordMint`/claimable accounting `:910-931`) | **MATCH** |
| C7 | DegenerusGame `external payable` :347 | `recordMint(...) external payable returns (uint256 newClaimableBalance)` | decl `:341`, payable `:347` | **MATCH** |
| C8 | :498 | `purchase(...) external payable` | decl `:492`, payable `:498` | **MATCH** |
| C9 | :593 | `purchaseWhaleBundle(...) external payable` | decl `:590`, payable `:593` | **MATCH** |
| C10 | :615 | `purchaseLazyPass(address buyer) external payable` | `:615` | **MATCH** |
| C11 | :635 | `purchaseDeityPass(address buyer, uint8 symbolId) external payable` | `:635` | **MATCH** |
| C12 | :712 | `placeDegeneretteBet(...) external payable` | decl `:705`, payable `:712` | **MATCH** |
| C13 | :1691 | `batchPurchase(...) external payable` | decl `:1687`, payable `:1691` | **MATCH** |
| C14 | :1732 | `_batchPurchaseUnit(...) external payable` | decl `:1729`, payable `:1732` | **MATCH** (note: `external payable` despite `_`-prefix name; self-call entry) |
| C15 | :1875 | `adminSwapEthForStEth(...) external payable` | decl `:1872`, payable `:1875` | **MATCH** |

**NOTE (CPAY §5):** the C9/C10/C11 entries are the *DegenerusGame.sol* facades that forward to the WhaleModule via delegatecall. The actual `if (msg.value != totalPrice) revert E()` checks the plan edits live in **`DegenerusGameWhaleModule.sol`** (C1/C2/C3). Both layers are `payable`; the edit lands in the module.

---

## B. sDGNRS REDEMPTION — current code (edit targets)

### B.1 — `_submitGamblingClaimFrom` (full body, `:824-910`)
```solidity
function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
    uint256 bal = balanceOf[burnFrom];
    if (amount == 0 || amount > bal) revert Insufficient();
    if (amount < MIN_BURN_AMOUNT) revert BurnTooSmall();

    uint32 currentPeriod = game.currentDayView();

    uint32 stamp = pendingResolveDay;
    if (stamp != 0 && stamp != currentPeriod) revert PriorDayUnresolved();
    if (stamp == 0) pendingResolveDay = currentPeriod;

    DayPending storage pool = pendingByDay[currentPeriod];

    if (pool.supplySnapshot == 0 && pool.burned == 0) {
        pool.supplySnapshot = uint64(totalSupply / 1e18);
    }
    uint256 amountWhole = (amount + 1e18 - 1) / 1e18;
    if (uint256(pool.burned) + amountWhole > uint256(pool.supplySnapshot) / 2) revert Insufficient();
    pool.burned += uint64(amountWhole);

    uint256 supplyBefore = totalSupply;

    // Compute proportional ETH value (subtract already-segregated)
    uint256 ethBal = address(this).balance;
    uint256 stethBal = steth.balanceOf(address(this));
    uint256 claimableEth = _claimableWinnings();
    uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
    uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

    // Compute proportional BURNIE (subtract already-reserved)
    uint256 burnieBal = coin.balanceOf(address(this));
    uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
    uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
    uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;

    unchecked {
        ethValueOwed = (ethValueOwed / 1e9) * 1e9;
        burnieOwed = (burnieOwed / 1e9) * 1e9;
    }

    // Burn sDGNRS
    unchecked {
        balanceOf[burnFrom] = bal - amount;
        totalSupply -= amount;
    }
    emit Transfer(burnFrom, address(0), amount);

    pendingRedemptionEthValue += ethValueOwed;
    pool.ethBase += uint64(ethValueOwed / 1e9);
    pendingRedemptionBurnie += burnieOwed;
    pool.burnieBase += uint64(burnieOwed / 1e9);

    PendingRedemption storage claim = pendingRedemptions[beneficiary][currentPeriod];

    if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

    claim.ethValueOwed += uint96(ethValueOwed);
    claim.burnieOwed += uint96(burnieOwed);

    if (claim.activityScore == 0) {
        claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
    }

    emit RedemptionSubmitted(beneficiary, amount, ethValueOwed, burnieOwed, currentPeriod);
}
```
- **ethValueOwed base:** `:860` `(totalMoney * amount) / supplyBefore`, where `totalMoney` (`:859`) = `ethBal + stethBal + claimableEth - pendingRedemptionEthValue`.
- **BURNIE base:** `:866` `(totalBurnie * amount) / supplyBefore`, where `totalBurnie` (`:865`) = `burnieBal + claimableBurnie - pendingRedemptionBurnie`.
- **day keying:** `:829` `game.currentDayView()` → composite `pendingRedemptions[beneficiary][currentPeriod]` (`:895`).
- Plan-1 §3.1 will pull the MAX (175%) into balance here; plan-1 §4.1 replaces the BURNIE base/reserve with `creditFlip` + burn/consume.

### B.2 — `resolveRedemptionPeriod` (`:648-681`)
```solidity
function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external {
    if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

    DayPending storage pool = pendingByDay[dayToResolve];
    uint256 ethBase = uint256(pool.ethBase) * 1e9;
    uint256 burnieBase = uint256(pool.burnieBase) * 1e9;
    if (ethBase == 0 && burnieBase == 0) return;

    uint256 rolledEth = (ethBase * roll) / 100;
    pendingRedemptionEthValue = pendingRedemptionEthValue - ethBase + rolledEth;   // :660  (claimed :659)

    uint256 burnieToCredit = (burnieBase * roll) / 100;                            // :663  (claimed :662)

    pendingRedemptionBurnie -= burnieBase;                                         // :666  (claimed :665)

    redemptionPeriods[dayToResolve] = RedemptionPeriod({
        roll: roll,
        flipDay: flipDay
    });

    emit RedemptionResolved(dayToResolve, roll, burnieToCredit, flipDay);          // :674  burnieToCredit emit-only

    delete pendingByDay[dayToResolve];

    if (pendingResolveDay == dayToResolve) pendingResolveDay = 0;
}
```
- **Defect-B asymmetry confirmed:** `burnieToCredit` (`:663`) is computed but only emitted (`:674`); the reserve release (`:666`) subtracts bare `burnieBase` — no `+ burnieToCredit` — so resolved-but-unclaimed BURNIE re-enters `totalBurnie`. ETH side keeps rolled value (`:660`).

### B.3 — `claimRedemption` (`:690-755`)
```solidity
function claimRedemption(uint32 day) external {
    address player = msg.sender;
    PendingRedemption storage claim = pendingRedemptions[player][day];
    if (claim.ethValueOwed == 0 && claim.burnieOwed == 0) revert NoClaim();

    RedemptionPeriod storage period = redemptionPeriods[day];
    if (period.roll == 0) revert NotResolved();

    uint16 roll = period.roll;
    uint16 claimActivityScore = claim.activityScore;

    uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

    bool isGameOver = game.gameOver();
    uint256 ethDirect;
    uint256 lootboxEth;
    if (isGameOver) {
        ethDirect = totalRolledEth;
    } else {
        ethDirect = totalRolledEth / 2;
        lootboxEth = totalRolledEth - ethDirect;
    }

    uint256 burniePayout;
    bool flipResolved;
    {
        (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);
        flipResolved = (rewardPercent != 0 || flipWon);
        if (flipResolved && flipWon) {
            burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;
        }
    }

    pendingRedemptionEthValue -= totalRolledEth;

    if (flipResolved) {
        delete pendingRedemptions[player][day];
    } else {
        claim.ethValueOwed = 0;          // partial-claim BURNIE branch: keep BURNIE
    }

    if (lootboxEth != 0) {
        uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
        uint256 rngWord = game.rngWordForDay(day);
        uint256 entropy = uint256(keccak256(abi.encode(rngWord, player)));
        game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore);
    }

    if (burniePayout != 0) {
        _payBurnie(player, burniePayout);     // :748  BURNIE BEFORE ETH
    }

    emit RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth);

    _payEth(player, ethDirect);               // :754  ETH AFTER BURNIE
}
```
- **Ordering defect confirmed:** `_payBurnie` (`:748`) runs before `_payEth` (`:754`) → a BURNIE revert unwinds the ETH leg (plan-1 §2 Defect B / §4 deletes the whole BURNIE-on-claim path).
- **`resolveRedemptionLootbox` call site:** `:743` — currently a plain (non-`payable`) external call passing `lootboxEth` (no `{value:}`). Plan-1 §3.3 makes it forward `lootboxEth` as `msg.value`.

### B.4 — `_payEth` (`:913-935`)
```solidity
function _payEth(address player, uint256 amount) private {
    if (amount == 0) return;
    uint256 ethBal = address(this).balance;
    uint256 claimableEth = _claimableWinnings();

    if (amount > ethBal && claimableEth != 0) {
        game.claimWinnings(address(0));        // :919  (claimed :917) — drains all SDGNRS claimable to 1-wei sentinel
        ethBal = address(this).balance;
    }

    if (amount <= ethBal) {
        (bool success, ) = player.call{value: amount}("");
        if (!success) revert TransferFailed();
    } else {
        uint256 ethOut = ethBal;
        uint256 stethOut = amount - ethOut;
        if (ethOut > 0) {
            (bool success, ) = player.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }
        if (!steth.transfer(player, stethOut)) revert TransferFailed();
    }
}
```
- Plan-1 §3.3 drops the `game.claimWinnings(address(0))` pull for the redemption path (ETH now pre-segregated in sDGNRS balance at submit).

### B.5 — `_payBurnie` (`:938-949`) — plan-1 deletes this
```solidity
function _payBurnie(address player, uint256 amount) private {
    uint256 burnieBal = coin.balanceOf(address(this));
    uint256 payBal = amount <= burnieBal ? amount : burnieBal;
    uint256 remaining = amount - payBal;
    if (payBal != 0) {
        if (!coin.transfer(player, payBal)) revert TransferFailed();
    }
    if (remaining != 0) {
        coinflip.claimCoinflipsForRedemption(address(this), remaining);   // :946  capped at sDGNRS stake → can revert on shortfall
        if (!coin.transfer(player, remaining)) revert TransferFailed();
    }
}
```

### B.6 — `previewBurn` (`:769-799`) + `burnieReserve` (`:804-808`)
```solidity
function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    uint256 supply = totalSupply;
    if (amount == 0 || amount > supply) return (0, 0, 0);

    uint256 ethBal = address(this).balance;
    uint256 stethBal = steth.balanceOf(address(this));
    uint256 claimableEth = _claimableWinnings();
    uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;   // :776
    uint256 totalValueOwed = (totalMoney * amount) / supply;

    uint256 ethAvailable = ethBal + claimableEth;
    if (ethAvailable > pendingRedemptionEthValue) {                                       // :780
        ethAvailable -= pendingRedemptionEthValue;                                        // :781
    } else {
        ethAvailable = 0;
    }
    if (totalValueOwed <= ethAvailable) {
        ethOut = totalValueOwed;
    } else {
        ethOut = ethAvailable;
        stethOut = totalValueOwed - ethOut;
    }

    if (!game.gameOver()) {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;      // :796
        burnieOut = (totalBurnie * amount) / supply;
    }
}

function burnieReserve() external view returns (uint256) {
    uint256 burnieBal = coin.balanceOf(address(this));
    uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
    return burnieBal + claimableBurnie - pendingRedemptionBurnie;                          // :807
}
```

### B.7 — Structs + globals (`:225-267`)
```solidity
struct PendingRedemption {
    uint96  ethValueOwed;
    uint96  burnieOwed;
    uint16  activityScore;
} // :225-229

struct RedemptionPeriod {
    uint16  roll;
    uint32  flipDay;          // :233  — plan-1 §4.3 deletes flipDay
} // :231-234

mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions;   // :262
mapping(uint32 => RedemptionPeriod) public redemptionPeriods;                          // :263
uint256 public pendingRedemptionEthValue;                                              // :265
uint256 internal pendingRedemptionBurnie;                                              // :266  — plan-1 §4.3 deletes
mapping(uint32 => DayPending) internal pendingByDay;                                    // :267
```

---

## C. CRITICAL — current sDGNRS ctor `subscribe(...)` call shape (R1)

**`StakedDegenerusStonk.sol:380`:**
```solidity
afKing.subscribe(address(this), true, false, 1, 2, address(0));
```
- Claimed `:379` `afKing.subscribe(this,true,false,1,2)` → **SHIFTED(+1)** AND **signature widened by v46 OPEN-E**: a 6th arg `address(0)` (the `fundingSource` parameter added in OPEN-E commit `42140ceb`) is now present. The plan's 5-arg citation is stale.
- Args: `(address subscriber=this, bool flag1=true, bool flag2=false, uint8 quantity=1, uint8 reinvestPct=2, address fundingSource=address(0))`. `address(0)` = default self-funding (per OPEN-E "default-self byte-identical").
- **IMPL note for plan-1:** this call is NOT itself edited by plan-1, but plan-1 §2 cites it as one of the three claimable-spending mechanisms (SUB-09 self-sub daily lootbox debits `claimableWinnings[SDGNRS]`). The ETH-segregation fix (§3.1) must account for this concurrent drain. No drift risk to the fix; just update the citation to 6-arg.

---

## D. CRITICAL — current `resolveRedemptionLootbox` (joint plan-1/plan-2 + plan-5 edit) (R21)

**`DegenerusGame.sol:1788-1838` — FULL signature + body:**
```solidity
function resolveRedemptionLootbox(
    address player,
    uint256 amount,
    uint256 rngWord,
    uint16 activityScore
) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert E();
    if (amount == 0) return;

    // Debit from sDGNRS's claimable (ETH stays in Game's balance).
    // SAFETY: unchecked is safe because the only path that drains claimableWinnings[SDGNRS]
    // is _deterministicBurnFrom → game.claimWinnings(), which only fires at gameOver.
    // This function is only called during active game (lootboxEth = 0 when gameOver).
    // The two paths are mutually exclusive, so claimable >= amount always holds here.
    uint256 claimable = claimableWinnings[ContractAddresses.SDGNRS];
    unchecked {
        claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;       // :1804  UNCHECKED — Defect A
    }
    claimablePool -= uint128(amount);                                            // :1806  checked

    // Credit to future prize pool (respects freeze state)
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(pNext, pFuture + uint128(amount));
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next, future + uint128(amount));
    }

    // Resolve lootboxes in 5 ETH chunks via delegatecall to lootbox module
    uint256 remaining = amount;
    while (remaining != 0) {
        uint256 box = remaining > 5 ether ? 5 ether : remaining;
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule
                        .resolveRedemptionLootbox
                        .selector,
                    player,
                    box,
                    rngWord,
                    activityScore
                )
            );
        if (!ok) _revertDelegate(data);
        remaining -= box;
        rngWord = uint256(keccak256(abi.encode(rngWord)));
    }
}
```
**Joint-edit reconciliation (plans 1, 2/5):**
- **plan-1 §3.3 + §6:** make this `external payable`; remove the `:1802-1806` claimable-debit block entirely (the unchecked `claimableWinnings[SDGNRS] -= amount` + `claimablePool -= uint128(amount)`); credit `futurePrizePool` from the just-arrived `msg.value` instead of from reclassified claimable.
- **PLAN-LOOTBOX-BOON-UNIFICATION §** (sibling, cited by plan-1 §7): flips `allowBoons` false→true at the delegatecall arg / lootbox module path (claimed `:675` in that plan; not in scope of this attestation, but the delegatecall here at `:1817-1833` is where the boon flag is wired). MUST land in ONE diff.
- The `if (msg.sender != ContractAddresses.SDGNRS) revert E();` gate (`:1794`) and the 5-ETH chunk loop (`:1818-1837`) are unchanged by either plan.

---

## E. CRITICAL — `onlyFlipCreditors` gating (R26) — `BurnieCoinflip.sol:191-201`
```solidity
modifier onlyFlipCreditors() {
    address sender = msg.sender;
    if (
        sender != ContractAddresses.GAME &&
        sender != ContractAddresses.QUESTS &&
        sender != ContractAddresses.AFFILIATE &&
        sender != ContractAddresses.ADMIN &&
        sender != ContractAddresses.AF_KING
    ) revert OnlyFlipCreditors();
    _;
}
```
- **5 allowed callers:** GAME, QUESTS, AFFILIATE, ADMIN, AF_KING. **SDGNRS is NOT in the list** → plan-1 §6 must add `ContractAddresses.SDGNRS` here (so `creditFlip` works from the new `redeemBurnieShare`).
- Gates `creditFlip` (`:852`) and `creditFlipBatch` (`:863`).
- `consumeCoinflipsForBurn` (`:356-361`) is gated by a SEPARATE modifier `onlyBurnieCoin` (`:203-206`, COIN only) — plan-1 §6 must extend this OR add a thin SDGNRS-gated `redeemBurnieShare`.

---

## F. BurnieCoin burn surface (R32) — for the new SDGNRS-gated burn
Current burn/mint entrypoints + gates (`BurnieCoin.sol`):
- `_burn(from, amount)` `:401` — internal; special VAULT-allowance branch (`:404-412`), else `balanceOf[from] -= amount; totalSupply -= amount`.
- `burnForCoinflip` `:430` — gate `msg.sender != COINFLIP`.
- `mintForGame` `:439` — gate `COINFLIP || GAME` (`:440`).
- `burnForKeeper` `:456` — `onlyAfKing`; all-or-nothing balance-then-coinflip draw.
- `burnCoin` `:586` — `onlyGame`; `_consumeCoinflipShortfall` then `_burn`.
- `decimatorBurn` `:607`, `terminalDecimatorBurn` `:682` — decimator-window gated.

**No SDGNRS-gated burn exists.** Plan-1 §6 ("`BurnieCoin.sol` — new `SDGNRS`-gated burn for sDGNRS's own held BURNIE") is a genuinely NEW function — not an edit of an existing one. Not a blocker (it's an additive new fn the plan already specifies), but flagged so IMPL doesn't expect a stub to modify.

---

## G. CPAY — current whale-module payment blocks (C1/C2/C3)

### G.1 — `purchaseWhaleBundle` (`DegenerusGameWhaleModule.sol`, decl `:187`)
Price compute `:240-260`, then:
```solidity
if (msg.value != totalPrice) revert E();       // :262
_awardEarlybirdDgnrs(buyer, totalPrice);       // :263
```
Price path: `hasValidBoon` → `discountedPrice + STANDARD*(quantity-1)`; else `unitPrice*quantity` (`EARLY` if `passLevel<=4` else `STANDARD`); x99 floor `quantity>=2`.

### G.2 — `purchaseLazyPass` (decl `:380`)
Price compute `:438-468`, slot1 clear `:469-473`, then:
```solidity
if (msg.value != totalPrice) revert E();       // :474
```
Price path: `currentLevel<=2` → `benefitValue=0.24 ether` (boon-discounted or full); else `baseCost` (boon-discounted or full).

### G.3 — `purchaseDeityPass` (decl `:538`)
Price compute `:555-579` (boon-tier discount 10/25/50%), then:
```solidity
if (msg.value != totalPrice) revert E();       // :581
uint24 passLevel = level + 1;                  // :583
deityPassPaidTotal[buyer] += totalPrice;       // :586
_awardEarlybirdDgnrs(buyer, totalPrice);       // :587
```

**CPAY edit for all 3:** replace `if (msg.value != totalPrice) revert E();` with the §H.1 canonical pattern — `msg.value > totalPrice` reverts (no overpay); `msg.value < totalPrice` → `shortfall = totalPrice - msg.value`; STRICT `claimableWinnings[buyer] > shortfall`; debit `claimableWinnings[buyer]` and `claimablePool` by `shortfall`.

---

## H. CPAY — canonical shortfall pattern (C4/C5/C6)

### H.1 — `DegenerusGameMintModule.sol:929-951` (lootbox-shortfall branch; the C4 reference)
```solidity
if (lootBoxAmount != 0) {
    // Lootbox payment uses msg.value first; optional claimable shortfall.
    if (remainingEth >= lootBoxAmount) {
        lootboxFreshEth = lootBoxAmount;
        unchecked { remainingEth -= lootBoxAmount; }
    } else {
        if (payKind == MintPaymentKind.DirectEth) revert E();
        lootboxFreshEth = remainingEth;
        uint256 shortfall = lootBoxAmount - remainingEth;
        remainingEth = 0;

        uint256 claimable = initialClaimable;
        // Preserve 1 wei sentinel (same as mint payments).
        if (claimable <= shortfall) revert E();              // STRICT <=
        unchecked { claimableWinnings[buyer] = claimable - shortfall; }
        claimablePool -= uint128(shortfall);                  // checked
        lootboxClaimableUsed = shortfall;
    }
}
```

### H.2 — `DegenerusGameDegeneretteModule.sol:522-531` (`_collectBetFunds`, the C5 reference)
```solidity
if (currency == CURRENCY_ETH) {
    if (ethPaid > totalBet) revert InvalidBet();              // no overpay
    if (ethPaid < totalBet) {
        uint256 fromClaimable = totalBet - ethPaid;           // :526
        if (claimableWinnings[player] <= fromClaimable)        // STRICT <=  :527
            revert InvalidBet();
        claimableWinnings[player] -= fromClaimable;            // :529
        claimablePool -= uint128(fromClaimable);               // :530
    }
    ...
}
```

### H.3 — `DegenerusGame.sol:910-931` strict-sentinel (the C6 reference — Combined-payment branch)
```solidity
} else if (payKind == MintPaymentKind.Combined) {
    if (msg.value > amount) revert E();                       // no overpay
    uint256 remaining = amount - msg.value;
    if (remaining != 0) {
        uint256 claimable = claimableWinnings[player];
        if (claimable > 1) {
            uint256 available = claimable - 1; // Preserve 1 wei sentinel  :917
            claimableUsed = remaining < available ? remaining : available;
            if (claimableUsed != 0) {
                unchecked { newClaimableBalance = claimable - claimableUsed; }
                claimableWinnings[player] = newClaimableBalance;
                remaining -= claimableUsed;
            }
        }
    }
    if (remaining != 0) revert E();                           // must fully cover
    prizeContribution = msg.value + claimableUsed;
}
```
**Canonical rule (synthesized):** (1) `msg.value > cost` reverts; (2) `shortfall = cost − msg.value`; (3) STRICT guard preserving the 1-wei sentinel (`claimable <= shortfall` reverts, or `claimable - 1` headroom); (4) `claimableWinnings[buyer] -= shortfall`; (5) `claimablePool -= uint128(shortfall)`. All three styles agree; H.1/H.2 use the `<=`-revert form, H.3 the `claimable - 1` clamp form.

---

## I. BLOCKERS / MATERIAL DRIFT

**No ABSENT anchors. No material-drift blockers.** Every cited symbol exists and is substantively unchanged. Findings to carry into IMPL:

1. **(R1 / §C) — sDGNRS ctor `subscribe` is now 6-arg.** Plan-1 cites the stale 5-arg `subscribe(this,true,false,1,2)`; current source is `subscribe(address(this), true, false, 1, 2, address(0))` (v46 OPEN-E `fundingSource`). Not an edit target, but update the citation; the ETH-segregation fix must still account for the SUB-09 self-sub draining `claimableWinnings[SDGNRS]`. **Advisory, not a blocker.**
2. **(R32 / §F) — no SDGNRS-gated burn exists on BurnieCoin.** Plan-1 §6 specifies a NEW such function — confirmed additive (not modifying a stub). **Advisory.**
3. **(R26 / §E) — SDGNRS absent from `onlyFlipCreditors` and the separate `onlyBurnieCoin` gate.** Plan-1 §6 must add SDGNRS to `onlyFlipCreditors` (for `creditFlip`) AND extend `consumeCoinflipsForBurn`'s gate (or add `redeemBurnieShare`). Both gates verified; the widening is the plan's stated intent. **Advisory.**
4. **(R33) — the 23% SDGNRS yield credit is via `_addClaimableEth(SDGNRS, quarterShare)` (`:720`), not a bare `claimableWinnings[SDGNRS]=`.** Line exact; mechanism is a helper. No impact. **Informational.**
5. **Line-number drift in sDGNRS:** the §B redemption functions are uniformly **+1 to +2 lines** below the plan-1 citations (the plan was written before a 1-line ctor-comment/sub-arg shift). The DegenerusGame, GameOverModule, BurnieCoinflip, WhaleModule, JackpotModule, and MintModule anchors are **exact**. No semantic drift anywhere.
6. **Joint-edit integrity (R21 / §D):** `resolveRedemptionLootbox` is the shared edit for plan-1 (payable + drop debit), plan-2/5 (claimable invariant), and PLAN-LOOTBOX-BOON-UNIFICATION (`allowBoons` flip at the `:1817-1833` delegatecall). All three converge on one function — confirm a single batched diff at IMPL.

**Source-frozen attestation valid as of contract HEAD 2026-05-24.**
