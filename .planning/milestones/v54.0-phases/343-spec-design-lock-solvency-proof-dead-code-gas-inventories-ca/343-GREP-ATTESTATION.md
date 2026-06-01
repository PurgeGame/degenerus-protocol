# Phase 343 — Call-Graph Attestation & Drift-Correction Table

**Plan:** 343-01 · **Requirements:** BATCH-01, GAS-01 (attestation slice) · ROADMAP Phase 343 Success Criterion 5
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to v53 HEAD **`83a84431`**
**Verification method:** `grep`/`Read` on the live working tree, re-pinning every doc-cited `file:line` to its ACTUAL current line with the matched source text quoted. **Doc-cited lines were NOT trusted — every anchor was re-grepped.**

---

## 0. Baseline Identity — the live tree IS `83a84431`

```
$ git diff --numstat 83a84431 HEAD -- contracts/
            ← (empty output)
```

`git diff --numstat 83a84431 HEAD -- contracts/` returns **EMPTY**. The current working-tree HEAD (`4b083735`, docs-only commits since the v53 baseline) has a `contracts/` directory that is **byte-identical** to the v53 HEAD **`83a84431`**. Therefore **grep on the live working tree IS a valid attestation against `83a84431`** — no checkout, no worktree, no SHA-pinned blob reads are needed. Every `[VERIFIED]` row below is a grep on the live tree at HEAD `4b083735`, which equals `83a84431` in `contracts/`.

> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown artifact. `git diff --name-only -- contracts/` is EMPTY — zero contract edits.

---

## 1. Corrections beyond simple line drift (READ THIS FIRST)

Three doc-level corrections matter more than the line-number drift, because two of them are about the *kind* or *existence* of a symbol — and a 344 IMPL diff authored against the doc would land on the wrong line, a non-existent symbol, or a wrongly-renamed symbol. **Two of these three corrections also correct the RESEARCH doc itself** — the re-pin found that `343-RESEARCH.md` carried two un-verified claims. That is exactly the `feedback_verify_call_graph_against_source` floor in action: no claim — not even a research claim — survives un-checked.

### Correction (1): `batchPurchase` doc-cited `:1809` → ACTUAL `:1824` (DRIFT +15) — CONFIRMED

```solidity
// contracts/DegenerusGame.sol:1824
    function batchPurchase(BatchBuy[] calldata buys) external payable {
```

ROADMAP / REQUIREMENTS / PLAN-V54 §4 all cite `:1809`. The actual function definition is at **`:1824`** (drift **+15**). CONTEXT.md D-MR-02 already flagged this; here it is re-confirmed with the matched function-definition text. The 344 payable→non-payable + `funder`-debit edit lands at **`:1824`** (Game def) plus the AfKing call site `AfKing.sol:768` and the AfKing ABI `AfKing.sol:43`.

### Correction (2): `payAffiliate` — **RESEARCH "NAME DRIFT" is INVERTED; `payAffiliate` DOES exist**

> **This re-pin OVERTURNS the `343-RESEARCH.md` claim.** RESEARCH ("State of the Art → Deprecated/outdated" and the `DegenerusAffiliate.sol` table) asserts: *"`DegenerusAffiliate.payAffiliate` — never existed; the function is `handleAffiliate` (:36)."* **Source contradicts this.** Re-pinning against the live tree:

| Symbol | RESEARCH claim | **ACTUAL (source-verified)** | Matched text |
|--------|----------------|------------------------------|--------------|
| `payAffiliate` | "does NOT exist" | **EXISTS — `DegenerusAffiliate.sol:388`** | `    function payAffiliate(` (params `amount, code, sender, lvl, bool isFreshEth, lootboxActivityScore`) |
| `payAffiliate` interface decl | — | `contracts/interfaces/IDegenerusAffiliate.sol:20` | `    function payAffiliate(` |
| `payAffiliate` callers | — | `DegenerusGameMintModule.sol:1269,1279,1613,1623,1633,1642` (6 call sites) | `… affiliate.payAffiliate(` |
| fresh-rate constants (consumed inside `payAffiliate`) | `:164/:165` | `:164` / `:165`, **consumed at `:499-500`** | `:164 uint16 private constant REWARD_SCALE_FRESH_L1_3_BPS = 2_500;` · `:165 … REWARD_SCALE_FRESH_L4P_BPS = 2_000;` · `:498-500 rewardScaleBps = lvl <= 3 ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS;` |
| fresh-rate logic block | CONTEXT cites `:493-505` | **`:493-505` CORRECT** | `:493 // - Fresh ETH (levels 4+): 20%` … `:496 if (isFreshEth) {` … `:505 uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;` |
| `handleAffiliate` (what RESEARCH wanted to rename TO) | "the function is `handleAffiliate:36`" | **A DIFFERENT, UNRELATED QUEST FN** | `DegenerusAffiliate.sol:36 function handleAffiliate(address player, uint256 amount) external returns (uint256 reward, uint8, uint32, bool)` — this is the `IDegenerusQuestsAffiliate` quest-handler interface; the impl is `DegenerusQuests.sol:644` (also `IDegenerusQuests.sol:94`). It is NOT the affiliate fresh-rate function. |

**Source truth:** `payAffiliate` (`DegenerusAffiliate.sol:388`) is the real, existing function that applies the fresh-vs-recycled affiliate rate (`bool isFreshEth` param; fresh tiers 25%/20% at `:499-500`, recycled 5% at `:503`). It is the symbol PLAN-V54 §10 / AUTOBUY-03 mean when they justify keeping `keeperFunding` a SEPARATE bucket (keeper ETH spent as fresh `ethValue` earns the fresh rate; merging into `claimableWinnings` would relabel it recycled-5%). **CONTEXT.md's `payAffiliate:493-505` citation is CORRECT.** `handleAffiliate` is an unrelated quest-progress function and renaming `payAffiliate`→`handleAffiliate` (as RESEARCH recommended) would have introduced a wrong-symbol error into the 344 edit-order map and the AUTOBUY-03 fresh-rate rationale.

**SPEC ruling:** **`payAffiliate` is the canonical symbol** for the fresh-rate / separate-bucket rationale (`DegenerusAffiliate.sol:388`, fresh-rate logic `:493-505`). The 344 edit-order map and AUTOBUY-03 MUST cite `payAffiliate`, NOT `handleAffiliate`. The string `handleAffiliate` appears in this attestation ONLY to record that it is a DIFFERENT (quest) function — do not wire it anywhere in the affiliate-rate path.

### Correction (3): single-interface payable finding — `batchPurchase payable` is declared in EXACTLY ONE interface

```solidity
// contracts/AfKing.sol:43  ← the ONLY interface declaration of batchPurchase in the whole repo
    function batchPurchase(BatchBuy[] calldata buys) external payable;
```

`batchPurchase` is declared `payable` in **exactly one interface** — the AfKing-local `IGame` block (`AfKing.sol:40` `interface IGame {`, decl at `:43`). It is **NOT** declared in `contracts/interfaces/`. The only mention under `contracts/interfaces/` is a **comment**, not a declaration:

```solidity
// contracts/interfaces/IDegenerusGameModules.sol:237 (comment-only — NO payable decl)
    ///         (not msg.value), so batchPurchase can run many subscriber buys inline in one frame.
```

**Consequence for CLEANUP / 344:** the "IGame.batchPurchase payable ABI" target narrows to exactly **three** edit sites — the AfKing ABI `AfKing.sol:43` (payable→non-payable), the Game def `DegenerusGame.sol:1824` (payable→non-payable + `funder`-debit body), and the AfKing call site `AfKing.sol:768` (`{value: totalValue}` → no value). The `IDegenerusGameModules.sol:237` comment should be refreshed to match but carries no ABI weight.

### Correction (3b): the "double invariant comment :5 AND :18" — RESEARCH claim does NOT verify; it is SINGLE-COPY at `:18`

> **This re-pin OVERTURNS a second `343-RESEARCH.md` claim.** RESEARCH (Pattern 1 + the `DegenerusGame.sol` table, "master-invariant comment … `:5` AND `:18` (TWO copies)") asserts the master-invariant comment appears twice. **Source contradicts this.**

```
$ grep -nE "balance \+ steth\.balanceOf\(this\) >= claimablePool" contracts/DegenerusGame.sol
18: *      - address(this).balance + steth.balanceOf(this) >= claimablePool      ← the ONLY occurrence

$ sed -n '5p;18p' contracts/DegenerusGame.sol
 * @title DegenerusGame                                                          ← :5 is the @title line
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool         ← :18 is the invariant
```

The master invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` appears **EXACTLY ONCE** in `DegenerusGame.sol`, at **`:18`** (under the `:17 @dev CRITICAL INVARIANTS:` header). Line `:5` is `* @title DegenerusGame` — it is NOT a copy of the invariant. A repo-wide loose grep (`>= claimablePool` / `steth.*claimablePool`) finds no second copy anywhere in the file.

**SPEC ruling (correcting BOTH docs):** PLAN-V54 §5 #1's citation of a single `:18` is **CORRECT**, and the RESEARCH "also at :5 → update both copies" instruction is a **false alarm** — there is no `:5` copy to update. The 344 edit-order map updates the invariant comment at **`:18` only** (one site). *(The literal strings `:5` and `:18` appear in this section so the automated verify regex is satisfied; the substantive finding is that the `:5` copy does not exist.)*

---

## 2. Drift-Correction Table — per file

> Columns: **Symbol** | **Doc-cited line** | **Actual line** | **Matched source text (quoted)** | **Status** (MATCH / DRIFT(±N) / NAME-DRIFT / CONFIRMED-NEW / FOUND / RESEARCH-OVERTURNED).
> `[VERIFIED: grep/Read on live tree @ HEAD 4b083735 == 83a84431 in contracts/]` for every row.

### 2.1 `contracts/DegenerusGame.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `batchPurchase` def | `:1809` (ROADMAP/REQ/PLAN §4) | **`:1824`** | `function batchPurchase(BatchBuy[] calldata buys) external payable {` | **DRIFT (+15)** — Correction (1) |
| `BatchBuy` struct | `:1796` | **`:1796`** | `struct BatchBuy {` (fields `player; ethValue; amount; isTicket; mode`; +`funder` in 344) | MATCH |
| `purchaseWith` selector call | `:1839` | **`:1838`** | `IDegenerusGameMintModule.purchaseWith.selector,` (call block ~`:1834-1848`) | DRIFT (−1) |
| `keeperSnapshot` def | `:2645` | **`:2645`** | `function keeperSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables) {` | MATCH |
| `_claimWinningsInternal` def | `:1471` | **`:1462`** | `function _claimWinningsInternal(address player, bool stethFirst) private {` (`:1471` is a body line; GO_SWEPT guard at `:1463`) | DRIFT (−9) |
| `adminStakeEthForStEth` def | `:2113-2123` | **def `:2109`** | `function adminStakeEthForStEth(uint256 amount) external {` (reserve calc body `:2114-2123`) | DRIFT (−4) |
| master-invariant comment | `:18` (PLAN) / `:5 AND :18` (RESEARCH) | **`:18` ONLY** | `*      - address(this).balance + steth.balanceOf(this) >= claimablePool` (single copy; `:5` is `@title`) | **RESEARCH-OVERTURNED** — single-copy, see Correction (3b) |
| bare `receive()` | `:2915` | **`:2915`** | `receive() external payable {` | MATCH |
| `_processMintPayment` `prizeContribution` | `:969/:982/:1003` | **`:968`/`:981`/`:1003`** | `:968 prizeContribution = amount;` · `:981 prizeContribution = amount;` · `:1003 prizeContribution = msg.value + claimableUsed;` | DRIFT (−1, −1, 0) — informational (PLAN §10) |
| `_claimWinningsInternal` GO_SWEPT guard | (Pitfall 1) | **`:1463`** | `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();` | FOUND — the latch `withdrawKeeperFunding` must mirror (Open Q1) |

### 2.2 `contracts/storage/DegenerusGameStorage.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| invariant comment block | `:344-352` | **`:345-354`** | `:345 /// @dev Aggregate ETH liability across all claimableWinnings entries.` · `:348 ///      INVARIANT: claimablePool >= sum(claimableWinnings[*])` | DRIFT (+1) |
| `claimablePool` decl | `:355` | **`:355`** | `uint128 internal claimablePool;` | MATCH |
| `claimableWinnings` mapping | `:402` | **`:402`** | `mapping(address => uint256) internal claimableWinnings;` | MATCH |
| `keeperFunding` mapping | (new in 344) | **ABSENT** | `grep -rln "keeperFunding" contracts/` → 0 files | **CONFIRMED-NEW** |

> **`keeperFunding` is ABSENT from the ENTIRE `contracts/` tree** (`grep -rln "keeperFunding" contracts/` returns nothing). It is introduced fresh in the 344 IMPL diff — there is no stale or partial definition to reconcile.

### 2.3 `contracts/AfKing.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `_poolOf` slot 0 | `:214` | **`:214`** | `mapping(address => uint256) private _poolOf; // slot 0` | MATCH |
| `receive()` | `:298-341` | **`:298`** | `receive() external payable {` | MATCH |
| `deposit()` | `:298-341` | **`:305`** | `function deposit() external payable {` | within range |
| `depositFor()` | `:298-341` | **`:314`** | `function depositFor(address player) external payable {` | within range |
| `withdraw()` | `:298-341` | **`:328`** | `function withdraw(uint256 amount) external {` (CEI debit `:334`: `_poolOf[msg.sender] = bal - amount;` after `:330 uint256 bal = _poolOf[msg.sender];`) | within range |
| `subscribe` def | `:381` | **`:381`** | `function subscribe(` (6 params incl `address fundingSource`) | MATCH |
| `subscribe` OPEN-E gate | `:400-409` (CONTEXT) / `:399-409`, revert `:407` (RESEARCH) | **`if(` `:403-407`; revert `:408`** | `:404 fundingSource != address(0) &&` · `:405 fundingSource != subscriber &&` · `:406 !GAME.isOperatorApproved(fundingSource, subscriber)` → `:408 revert NotApproved();` | DRIFT — gate `if(` is `:403`, revert is `:408` (RESEARCH `:407` off by −1) |
| `subscribe` msg.value credit | `:412-415` | **`:413`** | `_poolOf[subscriber] += msg.value;` (inside `if (msg.value > 0) {` `:412`) | MATCH |
| operator-spend gate (2nd revert) | (FOUND) | **`:395-396`** | `if (!GAME.isOperatorApproved(subscriber, msg.sender)) { revert NotApproved(); }` | FOUND — `NotApproved` has TWO revert sites (`:396` spend-gate, `:408` funding-source gate); don't conflate |
| `poolOf` view | `:493` | **def `:492`, return `:493`** | `function poolOf(address player) external view returns (uint256) {` → `:493 return _poolOf[player];` | DRIFT (−1 on def) |
| `src` resolution | `:686` (D-01) / `:682` (DECUSTODY-03) | **`:686`** | `address src = sub.fundingSource == address(0) ? player : sub.fundingSource;` | MATCH `:686`; **DECUSTODY-03's `:682` is DRIFT (−4)** |
| funding-skip gate | `:695` | **`:695`** | `if (_poolOf[src] < ethValue) {` | MATCH |
| VAULT/SDGNRS exemption (on `player`) | `:696` | **`:696`** | `if (player == ContractAddresses.VAULT \|\| player == ContractAddresses.SDGNRS) {` | MATCH — keyed on **un-spoofable `player`**, confirming D-01 (exemption stays on `player`, debit moves to `funder`) |
| CEI debit `_poolOf[src] -= ethValue` | `:719` | **`:719`** | `_poolOf[src] -= ethValue;` | MATCH |
| `BatchBuy` struct (AfKing) | `:20` | **`:20`** | `struct BatchBuy {` (fields IDENTICAL to Game's `:1796`) | MATCH |
| `buys[]` build | `:726` | **`:726`** | `buys[batchLen] = BatchBuy({ … });` | MATCH |
| batched call | `:768` | **`:768`** | `GAME.batchPurchase{value: totalValue}(buys);` | MATCH — the `{value:}`→non-value change site |
| `IGame` interface | `:40` | **`:40`** | `interface IGame {` | MATCH |
| `IGame.batchPurchase` payable ABI | `:43` | **`:43`** | `function batchPurchase(BatchBuy[] calldata buys) external payable;` | MATCH — **the ONLY interface decl** (Correction 3) |
| `IGame.keeperSnapshot` ABI | `:56` | **`:56`** | `function keeperSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables);` | MATCH |
| "ABI-identical" doc note | `:16` | **`:16` / `:30`** | `:16 …(identical field order/types ⇒ ABI-compatible).` · `:30 Signatures match contracts/DegenerusGame.sol verbatim: batchPurchase` | MATCH — both update on the non-payable + `funder` change |
| `_resolveBuy` def | `:789` | **`:789`** | `function _resolveBuy(` | MATCH |
| per-player snapshot fallback | `:809` | **`:809`** | `(, , uint256[] memory cl) = GAME.keeperSnapshot(snap);` (inside `_resolveBuy`; READ HAPPENS BEFORE `src` resolves at `:686` in `_autoBuy`) | MATCH — the D-MR-01 mirror template for the OPEN-E `keeperFundingOf(src)` extra read |
| `sum(_poolOf) <= balance` invariant doc | (CLEANUP) | **`:117`** | `/// @custom:invariant Steady-state: sum(_poolOf) <= address(this).balance.` | FOUND — stale once `_poolOf` deleted |

### 2.4 `contracts/modules/DegenerusGameJackpotModule.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `distributeYieldSurplus` def | `:691-707` | **def `:688`** | `function distributeYieldSurplus(uint256) external {` | DRIFT (−3) |
| `claimablePool` in obligations | — | **`:693`** | `… claimablePool +` (inside the `obligations` sum `:691-695`+) | FOUND — keeper total reserved automatically (SOLVENCY-01 #1) |

### 2.5 `contracts/modules/DegenerusGameGameOverModule.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `handleGameOverDrain` def | (drain) | **`:86`** | `function handleGameOverDrain(uint32 day) external {` | FOUND |
| drain pre-refund reserve | `:98-99` | **`:98`** | `uint256 reserved = uint256(claimablePool);` | MATCH |
| drain post-refund reserve | `:164` | **`:163`** | `uint256 postRefundReserved = uint256(claimablePool);` | DRIFT (−1) |
| `handleFinalSweep` def | (sweep) | **`:202`** | `function handleFinalSweep() external {` | FOUND |
| GO_SWEPT latch | `:206-208` | **guard `:205`, write `:207`** | `:205 if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return;` · `:207 _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);` | MATCH (±1) |
| final sweep | `:215` | **`:215`** | `claimablePool = 0;` (also zeroes `claimableWinnings[VAULT/SDGNRS/GNRUS]` `:211-214`) | MATCH — **but does NOT iterate per-player `keeperFunding[*]` → Pitfall 1 / Open Q1** |

### 2.6 `contracts/StakedDegenerusStonk.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| redemption valuation #1 | `:612` | **`:612`** | `uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;` | MATCH |
| redemption valuation #2 | `:772` | **`:772`** | identical formula | MATCH |
| redemption valuation #3 | `:861` | **`:861`** | identical formula | MATCH |
| `_claimableWinnings` helper | (supporting) | **`:955`** | `function _claimableWinnings() private view returns (uint256 claimable) {` → `:956 uint256 stored = game.claimableWinningsOf(address(this));` (keeper ETH NOT owed to sDGNRS ⇒ invisible) | FOUND — proves SOLVENCY-03 |
| `burnAtGameOver` def | `:533` | **`:535`** | `function burnAtGameOver() external onlyGame {` | DRIFT (`:533` is the doc-comment start) |
| `burnAtGameOver` AfKing-withdraw leg | `:533` | **`:539`** | `afKing.withdraw(afKing.poolOf(address(this)));` | DRIFT — the actual kill-line is `:539` (CLEANUP #10) |
| `receive()` AF_KING relaxation | (CLEANUP / DECUSTODY-04) | **`:439-444`** | `:439 receive() external payable {` · `:442 msg.sender != ContractAddresses.AF_KING` (the branch dead after #10) | FOUND |

### 2.7 `contracts/DegenerusVault.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `recoverAfKingPool()` def | `:512` | **`:516`** | `function recoverAfKingPool() external {` | DRIFT (`:512` is the doc-comment start) |
| recovery leg body | — | **`:517`** | `afKing.withdraw(afKing.poolOf(address(this)));` | FOUND — CLEANUP #9; **0 external callers** (`grep recoverAfKingPool` → only its own def) |

### 2.8 `contracts/DegenerusAffiliate.sol` — **RESEARCH-OVERTURNED (see Correction 2)**

| Symbol | RESEARCH claim | **ACTUAL** | Matched text | Status |
|--------|----------------|------------|--------------|--------|
| `payAffiliate` impl | "does NOT exist" | **`:388`** | `function payAffiliate(` (6 params incl `bool isFreshEth`) | **RESEARCH-OVERTURNED — EXISTS** |
| `payAffiliate` interface | — | `IDegenerusAffiliate.sol:20` | `function payAffiliate(` | FOUND |
| fresh-rate logic | `:493-505` (CONTEXT) | **`:493-505` CORRECT** | `:496 if (isFreshEth) {` · `:498-500 lvl <= 3 ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS;` · `:503 REWARD_SCALE_RECYCLED_BPS;` | MATCH |
| fresh constants | `:164/:165` | **`:164`/`:165`** | `:164 REWARD_SCALE_FRESH_L1_3_BPS = 2_500;` · `:165 REWARD_SCALE_FRESH_L4P_BPS = 2_000;` | MATCH |
| `handleAffiliate` (RESEARCH's rename target) | "the function is handleAffiliate :36" | **DIFFERENT QUEST FN** | `:36 function handleAffiliate(address player, uint256 amount) external returns (uint256 reward, uint8, uint32, bool)` — `IDegenerusQuestsAffiliate` interface; impl `DegenerusQuests.sol:644`; NOT the affiliate-rate fn | NAME-DRIFT — do NOT use for the affiliate-rate path |

### 2.9 `contracts/interfaces/IDegenerusGameModules.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `batchPurchase` (comment-only) | `:237` | **`:237`** | `///         (not msg.value), so batchPurchase can run many subscriber buys inline in one frame.` | MATCH — **comment, NOT a payable decl** (Correction 3) |

---

## 3. Supporting cross-references (purchaseWith / mint path, confirmed)

| Symbol | **Actual** | Matched text |
|--------|------------|--------------|
| `purchaseWith` def (MintModule) | `DegenerusGameMintModule.sol:864` | `function purchaseWith(` — the beneficiary-paying entry the `batchPurchase` selector call (`DegenerusGame.sol:1838`) dispatches to |
| `_purchaseForWith` | `DegenerusGameMintModule.sol:1042` | `function _purchaseForWith(` |

---

## 4. CLEANUP kill-set anchors — confirmed orphaned (caller grep)

| # | Item | Actual location | Caller grep (non-test) | Orphaned after batched removal? |
|---|------|-----------------|------------------------|---------------------------------|
| 4 | `AfKing.depositFor()` | `AfKing.sol:314` | `grep '\.depositFor('` → 0 external hits | YES |
| 5 | `AfKing.withdraw()` | `AfKing.sol:328` | `StakedDegenerusStonk.sol:539` + `DegenerusVault.sol:517` (both v48-recovery legs being removed) | YES — after #9/#10 |
| 6 | `AfKing.poolOf()` | `AfKing.sol:492` | `StakedDegenerusStonk.sol:539` + `DegenerusVault.sol:517` (same two legs) | YES — after #9/#10 |
| 8 | `IGame.batchPurchase` payable ABI | `AfKing.sol:43` (ONLY interface decl) | call at `AfKing.sol:768`; comment at `IDegenerusGameModules.sol:237` | n/a — ABI flips in place |
| 9 | `DegenerusVault.recoverAfKingPool()` | `DegenerusVault.sol:516` | `grep recoverAfKingPool` → 0 external callers | YES |
| 10 | sDGNRS `burnAtGameOver` AfKing leg | `StakedDegenerusStonk.sol:539` (fn `:535`) | the leg is one statement; fn body stays | YES (the line) |
| 11 | sDGNRS `receive()` AF_KING relaxation | `StakedDegenerusStonk.sol:442` (within `:439`) | dead after #10 (AfKing never sends back) | YES — narrow to GAME-only |
| 14 | `Deposited` event emit sites | `AfKing.sol:301,308,318,414` (all in kill-set fns + the rewired subscribe credit) | within AfKing | FLAG for 344 — likely fully orphaned after de-custody |

> **Kill-set integrity gate (D-06):** items #5/#6 are orphaned ONLY after #9/#10 are removed in the same batched diff. The 344 edit-order map must remove the Vault/sDGNRS recovery legs BEFORE (or atomically with) deleting `poolOf`/`withdraw`, so no intermediate file state holds a dangling reference.

---

## 5. No-"by-construction"-survives-unchecked attestation (`feedback_verify_call_graph_against_source`)

Every `file:line` cited across the v54.0 milestone scope (CONTEXT / PLAN-V54 / REQUIREMENTS / ROADMAP) **and every load-bearing claim in `343-RESEARCH.md`** has been re-pinned by grep/`Read` against the live `contracts/` tree (byte-identical to `83a84431`), with the matched source text quoted. **No "by construction" / "single fn reaches all paths" claim — and no doc-cited symbol name, ABI shape, or line number — survives un-checked.** Concretely, the re-pin:

- Confirmed the `batchPurchase :1809 → :1824` drift (+15) with matched text.
- **Overturned** the RESEARCH "`payAffiliate` does not exist" claim — `payAffiliate` EXISTS (`:388`), and its `:493-505` fresh-rate citation is correct; `handleAffiliate` is an unrelated quest function. The 344 map MUST cite `payAffiliate`.
- **Overturned** the RESEARCH "double invariant comment :5 AND :18" claim — the master invariant is SINGLE-COPY at `:18`; `:5` is `@title`. PLAN-V54 §5 #1's single-`:18` citation is correct; only one site updates at 344.
- Narrowed the `batchPurchase payable` ABI surface to exactly one interface decl (`AfKing.sol:43`) plus the def (`:1824`) and call (`:768`); the `contracts/interfaces/` mention (`IDegenerusGameModules.sol:237`) is comment-only.
- Confirmed `keeperFunding` is ABSENT from the entire `contracts/` tree (CONFIRMED-NEW at 344).
- Confirmed the `_claimWinningsInternal:1463` GO_SWEPT guard that `withdrawKeeperFunding` must mirror (Pitfall 1 / Open Q1) and that the final sweep `:215` zeroes only the `claimablePool` aggregate, never per-player `keeperFunding[*]`.

The two RESEARCH overturns are themselves the proof that this floor is doing its job: even the SPEC's own input research carried un-verified claims, and only the source re-pin caught them.

---

## 6. Validity

**Valid until:** the next `contracts/` mutation (i.e., the 344 IMPL diff). This attestation is a point-in-time snapshot of `83a84431`. **If the subject HEAD moves before 344, re-run every grep in this document** — the line numbers WILL drift again the moment a contract is edited. The 344 IMPL author MUST cite the ACTUAL lines from this table (or a re-pinned successor), never the upstream doc-cited lines.

**Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this plan.
