# Phase 317 — Confirmed Pre-Patch File:Line Ledger + Baseline Snapshot

**Built:** 2026-05-23 (Plan 317-01, Task 1)
**Purpose:** The single source of truth every downstream contract-edit plan (317-02/03/04/05/06/07) reads FIRST. Per `feedback_verify_call_graph_against_source`, every `file:line` cited by `316-SPEC.md` is re-grep-verified against the ACTUAL current source HEAD before any edit relies on a stale anchor. ZERO source mutation — read + grep + forge-inspect + write this markdown only.
**Verification HEAD:** current working tree (`git diff --name-only -- contracts/` empty at ledger-build time — the milestone has not mutated source yet; `316-SPEC` was grep-verified at `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`).
**Verdict legend:** MATCH = SPEC/RESEARCH anchor equals live line. DRIFT = symbol present but cited line offset by a cosmetic doc-vs-`if` gap (live line locked here). MISSING = SPEC said "verify whether present" and the symbol is absent (resolves an open). ADD-ABSENT = symbol is a downstream ADD target correctly NOT present at HEAD.

---

## RM + PROTO + Crank Ledger

### RM-01 — AFKing mode surface (`contracts/DegenerusGame.sol`)

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `setAutoRebuy` | 1495 | 1495 | MATCH | DELETE (also RM-02) |
| `setAutoRebuyTakeProfit` | 1504 | 1504 | MATCH | DELETE (also RM-02) |
| `_setAutoRebuy` | 1512 | 1512 | MATCH | DELETE (also RM-02) |
| `_setAutoRebuyTakeProfit` | 1524 | 1524 | MATCH | DELETE (also RM-02) |
| `autoRebuyTakeProfitFor` | 1543 | 1543 | MATCH | DELETE (also RM-02) |
| `setAfKingMode` | 1559 | 1559 | MATCH | DELETE |
| `_setAfKingMode` | 1569 | 1569 | MATCH | DELETE (holds `:1580` reader) |
| `_hasAnyLazyPass` | 1610 | 1610 | MATCH | **KEEP+EXPOSE (RM-04 / PROTO-01)** — body byte-confirmed below |
| `afKingModeFor` | 1624 | 1624 | MATCH | DELETE |
| `afKingActivatedLevelFor` | 1631 | 1631 | MATCH | DELETE |
| `deactivateAfKingFromCoin` | 1641 | 1641 | MATCH | DELETE |
| `syncAfKingLazyPassFromCoin` | 1654 | 1654 | MATCH | DELETE (holds `:1660` reader) |
| `_deactivateAfKing` | 1670 | 1670 | MATCH | DELETE |
| event `AutoRebuyToggled` | 1476 | 1476 | MATCH | DELETE |
| event `AutoRebuyTakeProfitSet` | 1479 | 1479 | MATCH | DELETE |
| event `AfKingModeToggled` | 1482 | 1482 | MATCH | DELETE |
| error `AfKingLockActive` | 92 | 92 | MATCH | DELETE (used at `:1676` inside `_deactivateAfKing`) |
| const `AFKING_KEEP_MIN_ETH` | 151 | 151 | MATCH | DELETE (used `:1535`/`:1584`/`:1585`) |
| const `AFKING_KEEP_MIN_COIN` | 154 | 154 | MATCH | DELETE (used `:1588`/`:1589`) |
| const `AFKING_LOCK_LEVELS` | 157 | 157 | MATCH | DELETE (used `:1675`) |
| cross-call `coinflip.settleFlipModeChange(player)` | 1603 | 1603 | MATCH | REMOVE (inside `_setAfKingMode`) |
| cross-call `coinflip.settleFlipModeChange(player)` | 1678 | 1678 | MATCH | REMOVE (inside `_deactivateAfKing`) |
| reader `_hasAnyLazyPass(player)` | 1580 | 1580 | MATCH | dies with `_setAfKingMode` deletion (body survives via RM-04) |
| reader `_hasAnyLazyPass(player)` | 1660 | 1660 | MATCH | dies with `syncAfKingLazyPassFromCoin` deletion (body survives via RM-04) |

**`_hasAnyLazyPass :1610` body — byte-confirmed PRESENT and unmodified (RM-04 KEEP target):**
```solidity
    function _hasAnyLazyPass(address player) private view returns (bool) {
        uint256 packed = mintPacked_[player];
        if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;

        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        return frozenUntilLevel > level;
    }
```
PROTO-01 rename target: `private view` → `external view`, `_hasAnyLazyPass` → `hasAnyLazyPass`, NO body change. The two readers (`:1580`/`:1660`) sit inside RM-01-deleted functions; the body survives ONLY because the keeper needs it externally (`hasAnyLazyPass(player)` at keeper `:671`/`:974`) — KEEP+EXPOSE is **required, not optional**.

**SUB-09 ctor Deity grant — byte-confirmed PRESENT (PRESERVE targets, do NOT perturb):**
```solidity
// DegenerusGame.sol constructor (opens :216)
:222   mintPacked_[ContractAddresses.SDGNRS] = BitPackingLib.setPacked(mintPacked_[ContractAddresses.SDGNRS], BitPackingLib.HAS_DEITY_PASS_SHIFT, 1, 1);
:223   mintPacked_[ContractAddresses.VAULT]  = BitPackingLib.setPacked(mintPacked_[ContractAddresses.VAULT],  BitPackingLib.HAS_DEITY_PASS_SHIFT, 1, 1);
```
| Anchor | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| ctor SDGNRS Deity grant | 222 | 222 | MATCH | **PRESERVE byte-unmodified** (SUB-09 permanent-deity free-renew; nearby RM edits must NOT perturb) |
| ctor VAULT Deity grant | 223 | 223 | MATCH | **PRESERVE byte-unmodified** |
The permanent Deity bit makes `hasAnyLazyPass(VAULT/SDGNRS)` return true forever → keeper renewal branch takes the free pass-extend path at zero cost. Do NOT add a redundant Deity-bit setter (SUB-09 needs NO new write).

### RM-02 — free ETH auto-rebuy (`storage/DegenerusGameStorage.sol` + `modules/DegenerusGameJackpotModule.sol` + `modules/DegenerusGamePayoutUtils.sol`)

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `struct AutoRebuyState` | 910 | 910 | MATCH | DELETE (forge slot 19 — see JGAS-02 / slot-shift) |
| `mapping autoRebuyState` | 926 | 926 | MATCH | DELETE |
| `_addClaimableEth` 3-arg decl | 788 | 788 | MATCH | reduce to direct `_creditClaimable`, drop `entropy` param |
| auto-rebuy block (cold SLOAD `:801`) | 800–808 | 798–806 (comment 798–799, `if(!gameOver)` 800, SLOAD 801, close 806) | **DRIFT (+2 confirmed)** | DELETE block; `PLAN-V47` claimed 798–806, live `if`-block opens 800 / SLOAD 801 — locked range 800–808 holds (encloses comment→close) |
| `_processAutoRebuy` | 822 | 822 | MATCH | DELETE |
| `_calcAutoRebuy` (PayoutUtils) | 51 | 51 | MATCH | DELETE |
| `_calcAutoRebuy` afKing selector | 83 | 83 (`state.afKingMode ? bonusBpsAfKing : bonusBps`) | MATCH | dies with `_calcAutoRebuy` |
| `_calcAutoRebuy` entropy roll | ~70 | 68 (`keccak256(abi.encode(entropy, beneficiary, weiAmount))`) | DRIFT (−2 interior) | dies with `_calcAutoRebuy` |
| `JackpotEthWin` event decl | 69 | 69 | MATCH | signature change (drop `rebuyLevel`/`rebuyTickets`) — benign ABI break |
| `JackpotEthWin.rebuyLevel` | 75 | 75 | MATCH | drop field |
| `JackpotEthWin.rebuyTickets` | 76 | 76 | MATCH | drop field |

**The 8 `_addClaimableEth` consume sites (drop `entropy` arg at each) — ALL MATCH:**
| SPEC site | Live site | Verdict |
|-----------|-----------|---------|
| 755 | 755 | MATCH (internal 3-call helper) |
| 760 | 760 | MATCH |
| 765 | 765 | MATCH |
| 1430 | 1430 (`_addClaimableEth(w, perWinner, entropyState)`) | MATCH |
| 1530 | 1530 (`_addClaimableEth(w, perWinner, entropy)`) | MATCH |
| 1571 | 1571 | MATCH |
| 1583 | 1583 | MATCH |
| 2132 | 2132 | MATCH |
| 2165 | 2165 | MATCH |

**Pitfall 4 (do NOT conflate):** `DegenerusGameDegeneretteModule._addClaimableEth(beneficiary, weiAmount)` **2-arg overload** at `:1117` (live) — DISTINCT function, UNTOUCHED by RM-02.

**Zero-orphan grep results (RM-05 / RM-06 mandate — `grep -rn … contracts/` excl `contracts/test`):**

| Symbol | Surviving callers at HEAD | Verdict / IMPL action |
|--------|---------------------------|------------------------|
| `_budgetToTicketUnits` (JackpotModule `:861`) | **3 LIVE callers** at `:400`, `:435`, `:889` (daily-ticket budget computation, NOT the auto-rebuy path) | **NOT orphaned → KEEP.** ⚠ The SPEC's "verify-orphaned … confirm no surviving caller" check resolves to NOT-ORPHANED here — `_budgetToTicketUnits` must be PRESERVED. Do NOT delete it; only the auto-rebuy block + `_processAutoRebuy` go. |
| `struct AutoRebuyCalc` (PayoutUtils `:19`) | sole consumer = JackpotModule `:831` (inside `_calcAutoRebuy`, which RM-02 deletes) + PayoutUtils `:59` return type of `_calcAutoRebuy` | **WILL be orphaned post-cut → DELETE** after `_calcAutoRebuy` removal (re-grep at edit time to confirm zero survivors). |

### RM-03 — BURNIE flip recycle collapse to flat 75bps (`contracts/BurnieCoinflip.sol`)

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `settleFlipModeChange` | 217 | 217 | MATCH | DELETE (+ its IBurnieCoinflip `:85` decl) |
| const `RECYCLE_BONUS_BPS` (=75) | 129 | 129 (`= 75`) | MATCH | **KEEP byte-identical** (flat post-collapse rate) |
| const `AFKING_RECYCLE_BONUS_BPS` (=100) | 130 | 130 (`= 100`) | MATCH | **DELETE** (the deleted afKing tier — value distinction confirmed: 100 ≠ kept 75) |
| `_recyclingBonus` | 1051 | 1051 (`bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR)` at `:1055`) | MATCH | **KEEP byte-identical** |
| `processCoinflipPayouts` (BURNIE win/loss RNG path) | 805 | 805 | MATCH | **KEEP byte-identical (RM-06 hard floor)** |
| `(rngWord & 1) == 1` win | 837 | 837 | MATCH | **KEEP byte-identical** |
| afKing rebet-bonus branch | 294–308 | (afKing/deity branch; `_recyclingBonus` at `:1051`, afKing recycle helper `:1067` reads `AFKING_RECYCLE_BONUS_BPS`) | MATCH | collapse to `_recyclingBonus` |

**Value-distinction note (locked, do NOT misdelete):** `RECYCLE_BONUS_BPS = 75 :129` is KEPT; `AFKING_RECYCLE_BONUS_BPS = 100 :130` is the DELETED tier. `PLAN-V47 §1.5`'s shorthand "75bps" refers to the *kept* constant. A wrong-value deletion (deleting 75 instead of 100) is a defect.

### RM-05 — cross-contract cascade (interfaces + Vault + sStonk)

| File | Symbol | SPEC line | Live line | Verdict | Action |
|------|--------|-----------|-----------|---------|--------|
| `interfaces/IDegenerusGame.sol` | `afKingModeFor` | 274 | 274 | MATCH | REMOVE |
| `interfaces/IDegenerusGame.sol` | `afKingActivatedLevelFor` | 279 | 279 | MATCH | REMOVE |
| `interfaces/IDegenerusGame.sol` | `deactivateAfKingFromCoin` | 283 | 283 | MATCH | REMOVE |
| `interfaces/IDegenerusGame.sol` | `syncAfKingLazyPassFromCoin` | 288 | 288 | MATCH | REMOVE |
| `interfaces/IDegenerusGame.sol` | `hasDeityPass` | 376 | 376 | MATCH | **KEEP** (read by coinflip, not in scope) |
| `interfaces/IDegenerusGame.sol` | `setAutoRebuy`/`setAutoRebuyTakeProfit`/`setAfKingMode` | "verify present" | ABSENT | **MISSING (resolves open)** | NOT here — they live in DegenerusVault local iface (`:47/:49/:51`). PLAN-V47 §5.6 open RESOLVED. |
| `interfaces/IDegenerusGame.sol` | `hasAnyLazyPass` (PROTO-01 ADD) | — | ABSENT | **ADD-ABSENT** | ADD mirroring `hasDeityPass :376` view-decl style |
| `interfaces/IBurnieCoinflip.sol` | `settleFlipModeChange` | 85 | 85 | MATCH | REMOVE |
| `interfaces/IBurnieCoinflip.sol` | `creditFlip` | 115 | 115 | MATCH | **KEEP** (PROTO-03 needs no new decl) |
| `interfaces/IBurnieCoinflip.sol` | `creditFlipBatch` | 122 | 122 | MATCH | **KEEP** |
| `DegenerusVault.sol` | local decl `setAutoRebuy` | 47 | 47 | MATCH | REMOVE |
| `DegenerusVault.sol` | local decl `setAutoRebuyTakeProfit` | 49 | 49 | MATCH | REMOVE |
| `DegenerusVault.sol` | local decl `setAfKingMode` | 51 | 51 | MATCH | REMOVE |
| `DegenerusVault.sol` | wrapper `gameSetAutoRebuy` | 627 | 627 | MATCH | REMOVE |
| `DegenerusVault.sol` | wrapper `gameSetAutoRebuyTakeProfit` | 634 | 634 | MATCH | REMOVE |
| `DegenerusVault.sol` | wrapper `gameSetAfKingMode` | 643 | 643 | MATCH | REMOVE |
| `DegenerusVault.sol` | `coinSetAutoRebuy` | 685 | 685 | MATCH | **KEEP** (BURNIE-side wrapper) |
| `DegenerusVault.sol` | `coinSetAutoRebuyTakeProfit` | 692 | 692 | MATCH | **KEEP** |
| `DegenerusVault.sol` | `gameClaimWhalePass` (init-call shape model) | 581 | 581 | MATCH | KEEP (SUB-09 self-subscribe init-call model) |
| `StakedDegenerusStonk.sol` | local decl `setAfKingMode` | 13 | 13 | MATCH | REMOVE |
| `StakedDegenerusStonk.sol` | init `game.claimWhalePass(address(0))` | 360 | 360 | MATCH | KEEP entry; precedes the `:361` removal |
| `StakedDegenerusStonk.sol` | init `game.setAfKingMode(...)` | 361 | 361 | MATCH | REMOVE — REPLACED by SUB-09 self-subscribe |
| `StakedDegenerusStonk.sol` | re-claim `game.claimWhalePass(address(0))` | 404 | 404 | MATCH | **KEEP** (not in removal scope) |

### PROTO target sites (ADD surfaces — analog anchors confirmed; ADD symbols correctly absent)

| File | Anchor (analog / target) | SPEC line | Live line | Verdict |
|------|--------------------------|-----------|-----------|---------|
| `ContractAddresses.sol` | `COINFLIP` const | 35 | 35 | MATCH (analog block) |
| `ContractAddresses.sol` | `VAULT` const | 37 | 37 | MATCH |
| `ContractAddresses.sol` | `SDGNRS` const | 47 | 47 | MATCH |
| `ContractAddresses.sol` | `AF_KING` (PROTO-05 ADD) | — | ABSENT | **ADD-ABSENT** (pin alongside the block; aligns with deploy-predicted keeper addr — D-01b) |
| `BurnieCoin.sol` | `onlyVault` modifier (gate analog) | 485 | 485 | MATCH |
| `BurnieCoin.sol` | `_burn` primitive | 390 | 390 | MATCH |
| `BurnieCoin.sol` | `vaultMintTo` gated-fn idiom | 518 | 518 | MATCH |
| `BurnieCoin.sol` | `spendable = balanceOf[player]` read pattern | 230 | 230 | MATCH |
| `BurnieCoin.sol` | `burnForKeeper` (PROTO-02 ADD) | — | ABSENT | **ADD-ABSENT** (transitional note: keeper-side caller exists, BurnieCoin target NOT yet present) |
| `BurnieCoinflip.sol` | `onlyFlipCreditors` modifier (PROTO-03 extend) | 194 | 194 | MATCH |
| `BurnieCoinflip.sol` | `creditFlip` impl | 898 | 898 | MATCH |
| `DegenerusGame.sol` | `purchase` | 501 | 501 | MATCH (per-player batch unit for PROTO-04) |
| `DegenerusGame.sol` | `_purchaseFor` | 518 | 518 | MATCH |
| `DegenerusGame.sol` | `_resolvePlayer` | 458 | 458 | MATCH (crank resolve gate) |
| `DegenerusGame.sol` | `_requireApproved` | 452 | 452 | MATCH |
| `DegenerusGame.sol` | `rngLocked()` view | 2190 | 2190 | MATCH (batch-level rng-lock pre-check) |
| `DegenerusGame.sol` | `batchPurchase` (PROTO-04 ADD) | — | ABSENT | **ADD-ABSENT** |
| `DegenerusGame.sol` | `hasAnyLazyPass` (PROTO-01 ADD/rename) | — | ABSENT | **ADD-ABSENT** (rename of `_hasAnyLazyPass :1610`) |

### Crank reuse sites (CRANK-01..04 + REW-01..04 design anchors — all MATCH)

| File | Anchor | SPEC line | Live line | Verdict |
|------|--------|-----------|-----------|---------|
| `DegenerusGame.sol` | `resolveDegeneretteBets` | 743 | 743 | MATCH (crank caller-list entry) |
| `modules/DegenerusGameDegeneretteModule.sol` | `resolveBets` | 389 | 389 | MATCH (caller-list loop model) |
| `modules/DegenerusGameDegeneretteModule.sol` | `_resolvePlayer` (module mirror) | 141 | 141 | MATCH |
| `modules/DegenerusGameDegeneretteModule.sol` | `degeneretteBets` delete-site (`delete`) | 580 | 580 | MATCH (`delete degeneretteBets[player][betId]`) — CRANK-02 resolved-state probe |
| `modules/DegenerusGameLootboxModule.sol` | `openLootBox` | 477 (SPEC narration ~530) | 477 (decl); zeroing `lootboxEth :530` / `lootboxEthBase :531` | MATCH |
| `modules/DegenerusGameLootboxModule.sol` | `RngNotReady` guard | 485 | 485 (`if (rngWord == 0) revert RngNotReady()`) | MATCH |
| `modules/DegenerusGameMintModule.sol` | `_ethToBurnieValue` (guarded zero-return) | 1412 | 1412 | MATCH (body byte-confirmed: `if (amountWei == 0 \|\| priceWei == 0) return 0;`) |
| `modules/DegenerusGameMintModule.sol` | `lootboxEthBase` first-deposit enqueue signal | 1004–1008 | 1004 (read) / 1008 (write) | MATCH (OPEN-D box-cursor enqueue signal) |
| `modules/DegenerusGameAdvanceModule.sol` | `advanceGame` | 158 | 158 | MATCH (stage `do{}while(false)` machine) |
| `modules/DegenerusGameAdvanceModule.sol` | `creditFlip` bounty idiom | 478–482 | 478 (call) / 480 (`(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / …`) | MATCH (REW-01 reward-path model; also at `:192`/`:228`) |
| `modules/DegenerusGameAdvanceModule.sol` | `ADVANCE_BOUNTY_ETH = 0.005 ether` | 150 | 150 | MATCH |
| `libraries/BitPackingLib.sol` | `HAS_DEITY_PASS_SHIFT = 184` | 71 | 71 | MATCH |
| `libraries/BitPackingLib.sol` | `FROZEN_UNTIL_LEVEL_SHIFT = 128` | 63 | 63 | MATCH |
| `libraries/BitPackingLib.sol` | `MASK_24` | — | 35 | MATCH |
| `libraries/PriceLookupLib.sol` | `priceForLevel` (pure non-zero) | 21 | 21 | MATCH |

**Recorded SPEC DRIFT/MISSING items — re-confirmed against live source:**
1. **DRIFT (+2, cosmetic) CONFIRMED:** JackpotModule auto-rebuy block — `PLAN-V47` claimed 798–806; live `if (!gameOver)` opens at `:800`, cold SLOAD `autoRebuyState[beneficiary]` at `:801`, block closes `:806`. SPEC's locked 800–808 range holds.
2. **DRIFT (interior offset, cosmetic) CONFIRMED:** DegeneretteModule `_distributePayout` decl `:705`; the revert-on-insufficient-solvency `if (uint256(pFuture) < ethShare) revert E();` is at `:742` (SPEC's "~738" points to the comment-block narration ending at `:738`; live `if` guard `:742`). PLAN-CRANK §8's "742" actually matches the live `if`.
3. **MISSING (resolves open) CONFIRMED:** `setAutoRebuy`/`setAutoRebuyTakeProfit`/`setAfKingMode` are NOT in `IDegenerusGame.sol`; they are in `DegenerusVault.sol`'s local interface (`:47`/`:49`/`:51`, which RM-05 removes).

**Zero-orphan grep summary (CRITICAL downstream input):**
- `_budgetToTicketUnits` → **NOT orphaned (3 live callers `:400`/`:435`/`:889`) → KEEP** (SPEC's orphan-check resolves to NOT-ORPHANED; preserve it).
- `AutoRebuyCalc` → orphaned only AFTER `_calcAutoRebuy` deletion (sole consumer JackpotModule `:831` + the `_calcAutoRebuy` return type) → DELETE post-cut, re-grep to confirm.

**No `contracts/` file modified by this task** (`git diff --stat -- contracts/` empty).

---

## JGAS-02 Footprint Ledger

**Built:** 2026-05-23 (Plan 317-01, Task 2). The JGAS daily-ETH two-call-split deletion footprint re-grep-verified across `modules/DegenerusGameJackpotModule.sol` + `modules/DegenerusGameAdvanceModule.sol` + `storage/DegenerusGameStorage.sol`. ZERO source mutation.

### Deletion set — `modules/DegenerusGameJackpotModule.sol`

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `SPLIT_NONE = 0` | 197 | 197 | MATCH | DELETE split-mode tag |
| `SPLIT_CALL1 = 1` | 199 | 199 | MATCH | DELETE |
| `SPLIT_CALL2 = 2` | 201 | 201 | MATCH | DELETE |
| `JACKPOT_MAX_WINNERS = 160` | 219 | 219 | MATCH | **DELETE — DEAD on removal.** Sole functional use = split-threshold at `:480` (`splitMode = (totalWinners <= JACKPOT_MAX_WINNERS) ? SPLIT_NONE : SPLIT_CALL1`). **It is a split-routing threshold, NOT a winner-count cap.** |
| `resumeEthPool` jackpot resume-check `if` | 348 (comment) | **349** (`if (resumeEthPool != 0)`) | **DRIFT (+1 cosmetic)** | DELETE — requirement cites the leading comment line `:348`; live `if` guard `:349` |
| `resumeEthPool` read (inside `_resumeDailyEth`) | 1201 | 1201 (`uint256(resumeEthPool)`) | MATCH | DELETE |
| `resumeEthPool` read+zero (call 2) | 1252–1253 | 1252 (`ethPool = uint256(resumeEthPool)`) / 1253 (`resumeEthPool = 0`) | MATCH | DELETE |
| `resumeEthPool` write (call 1) | 1348 (gated 1347) | 1348 (`resumeEthPool = uint128(ethPool)`); gate `if (splitMode == SPLIT_CALL1)` at 1347 | MATCH | DELETE |
| `_resumeDailyEth` decl | 1186 | 1186 (called at `:350`) | MATCH | DELETE |
| `splitMode` param (in `_processDailyEth`) | 1248 | 1248 | MATCH | DELETE param |
| `splitMode` routing | 1251 / 476 / 480 / 501 | 1251 (`if (splitMode == SPLIT_CALL2)`) / 476 (`uint8 splitMode;`) / 480 (threshold) / 501 (call arg) | MATCH | DELETE routing; collapse to single-call. Additional routing reads at `:1271`/`:1287`/`:1288`/`:1347` |
| `call1Bucket` mask decl | 1270 | 1270 (`bool[4] memory call1Bucket;`) | MATCH | DELETE |
| `call1Bucket` build | 1272/1274/1276 | 1272 / 1274 / 1276 | MATCH | DELETE |
| `call1Bucket` skip-routing | 1287–1288 | 1287 (`SPLIT_CALL1 && !call1Bucket[traitIdx]`) / 1288 (`SPLIT_CALL2 && call1Bucket[traitIdx]`) | MATCH | DELETE |
| split-threshold branch | 476–483 | 476–482 (`splitMode` derivation) | MATCH | collapse to unconditional single-call |
| `_processDailyEth(... splitMode ...)` call | 493–503 | `splitMode` arg passed at `:501` | MATCH | collapse to single-call |

### Deletion set — `modules/DegenerusGameAdvanceModule.sol`

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `STAGE_JACKPOT_ETH_RESUME = 8` | 70 | 70 (`uint8 private constant … = 8`) | MATCH (value=8 exact) | DELETE constant |
| stage assignment `stage = STAGE_JACKPOT_ETH_RESUME;` | 455 | 455 | MATCH | DELETE |
| whole resume-check block | 452–455 (comment-anchored) | **block 453–457**: comment `:452`, `if (resumeEthPool != 0)` `:453`, `payDailyJackpot(true, lvl, rngWord)` `:454`, `stage = …` `:455`, `break;` `:456`, close `}` `:457` | **DRIFT (+1 cosmetic)** | DELETE the entire `:453-457` block — requirement cites comment `:452`; live `if`-block opens `:453` |

### Deletion set — `storage/DegenerusGameStorage.sol`

| Symbol | SPEC line | Live line | Verdict | Action |
|--------|-----------|-----------|---------|--------|
| `uint128 internal resumeEthPool;` | 994 | 994 | MATCH | DELETE (forge slot 33, own slot — the −2 slot-shift consequence is owned by the RM-06 slot-shift work; footprint item only here) |

### PRESERVE set — explicitly NOT in the deletion set

| Symbol | Live line | Verdict | Note |
|--------|-----------|---------|------|
| `DAILY_ETH_MAX_WINNERS = 305` | 227 | MATCH — **PRESERVE** | the winner-count ceiling stays; mechanism-only removal at the SAME 305 ceiling |
| `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` | 248 | MATCH — **PRESERVE** | the 6.36× max-scale stays |
| 159 / 95 / 50 / 1 bucket derivation | (sum=305) | **PRESERVE** | zero winner-count / bucket-scaling / payout-EV change |

### Two cosmetic `+1` resume-check DRIFTs — re-confirmed
- **Jackpot** (`DegenerusGameJackpotModule.sol`): requirement cites `:348` (comment "Resume check: call 2 of two-call daily ETH split."); live `if (resumeEthPool != 0)` guard at `:349`. Cosmetic doc-vs-`if` offset; no symbol drift, no MISSING.
- **Advance** (`DegenerusGameAdvanceModule.sol`): requirement cites `:452-455`; live block is `:453-456` (close brace `:457`), comment at `:452`. Cosmetic offset; no symbol drift, no MISSING.

### Stage numbers NOT load-bearing (re-confirmed)
`stage` is a function-local `uint8` inside `advanceGame` (never stored). `STAGE_JACKPOT_ETH_RESUME` is only ASSIGNED (`:455`) and EMITTED via the `Advance` event — ZERO `==` comparisons anywhere. Resume is driven by the `resumeEthPool != 0` STORAGE read (`:453`/`:349`), NOT by any stored stage value. Renumbering 9/10/11 → 8/9/10 is OPTIONAL/cosmetic; deleting constant 8 + its single assignment + the resume-check block is sufficient and behaviorally complete.

### `_unlockRng`-not-in-resume-branch — J5 freeze trace re-confirmed
`_unlockRng` call sites in `DegenerusGameAdvanceModule.sol` are `:331`, `:402`, `:467` (coin-tickets stage), `:629`, and the decl `:1772`. **NONE fall inside the resume-check block `:453-457`.** The ETH-resume branch holds `rngLockedFlag` SET across the entire split (call 1 → next advanceGame → call 2); the same `randWord` is re-consumed in call 2 (`_resumeDailyEth` re-rolls the winning traits from the identical held word). Single-call collapses two same-word consumptions into ONE; `_unlockRng` placement is UNCHANGED (still `:467`). **VERDICT (re-confirmed): JGAS is freeze-invariant-SAFE** — removes a VRF-word re-consumption point + a cross-tx `resumeEthPool` carry → a VRF-rotation-robustness IMPROVEMENT (no cross-tx state to orphan; strictly less rotation-exposed than the two-call split). Only residual is the gas-fits liveness question (JGAS-04, Phase 319) — NOT a freeze/manipulability concern. AUDIT-320 re-attests under emergency rotation.

---

## Live Keeper Transitional-State Table

**Built:** 2026-05-23 (Plan 317-01, Task 2). Re-grep-verified against `../degenerus-utilities/contracts/StreakKeeperV2.sol` live source (the keeper to be reworked into the canonical in-tree `contracts/AfKing.sol`). Per Pitfall 1 — downstream edits author the INTENDED end-state, NOT this mixed live source.

### Occurrence-count snapshot (live)

| Symbol | Live count | Interpretation |
|--------|-----------:|----------------|
| `pullForKeeper` | 19 | still PRESENT — pre-rework; PROTO-02 switches these to `burnForKeeper` |
| `mintForKeeper` | 5 | still PRESENT — pre-rework |
| `burnForKeeper` | 5 | PRESENT keeper-SIDE (keeper already calls it) — but the BurnieCoin TARGET is ADD-ABSENT (verified Task 1: no `burnForKeeper` in `contracts/BurnieCoin.sol`). The keeper is partially ahead of the BurnieCoin target — the exact transitional mix. |
| `creditFlip` | 2 | partial — full `creditFlip` rework genuinely unbuilt |
| `sweepCursor` | **0** | genuinely UNBUILT — the parameterless daily-reset cursor is a Phase-317 ADD |
| `reinvestPct` | **0** | genuinely UNBUILT — the reinvest% field (packed into `Sub` free bytes) is a Phase-317 ADD |
| `windowPaid` | **0** | genuinely UNBUILT — the 1-bit flag is a Phase-317 ADD |

### Live signatures (pre-rework — to be reworked, NOT trusted as end-state)

| Symbol | Live line | Live signature | Rework target |
|--------|-----------|----------------|---------------|
| `subscribe` | 632 | `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` external payable | ADD `reinvestPct` (SUB-04 quantity model — `effective = max(dailyQuantity, floor(claimable × reinvestPct / price))`) |
| `sweep` | 931 | `sweep(uint256 startIdx, uint256 count)` external returns (uint256 bountyEarned) | REPLACE with parameterless `sweep(uint256 maxCount)` + internal `sweepCursor` daily-reset (SUB-03) |

### Game-side coupling (the only coupling — re-confirmed CLEAN)
- `IGame(ContractAddresses.GAME).hasAnyLazyPass(msg.sender)` at keeper `:671` (subscribe gate) and `hasAnyLazyPass(player)` at `:974` (renewal-sweep gate) — both MATCH SPEC. This is the kept-and-exposed PROTO-01 view, NOT a deleted symbol.
- **Keeper RM-symbol cross-check = 0 matches** across the full RM-deletion set (`syncAfKingLazyPassFromCoin`/`afKingModeFor`/`afKingActivatedLevelFor`/`setAfKingMode`/`deactivateAfKingFromCoin`/`setAutoRebuy`/`autoRebuyState`/`AutoRebuyState`/`_processAutoRebuy`/`_calcAutoRebuy`/`settleFlipModeChange`).
- **Keeper JGAS-symbol cross-check = 0 matches** (`SPLIT_*`/`resumeEthPool`/`STAGE_JACKPOT_ETH_RESUME`/`_resumeDailyEth`/`call1Bucket`/`splitMode`).
- **CONCLUSION:** The RM-* + JGAS-02 deletions are dependency-safe w.r.t. the keeper **IFF PROTO-01 (`hasAnyLazyPass` rename) ships in the SAME batched Phase-317 diff.** The keeper's only game-side coupling survives the deletion unchanged.

---

## D-01b Single-Source / Deploy Reconciliation

**Built:** 2026-05-23 (Plan 317-01, Task 2). D-01b is a HOW-item: how `../degenerus-utilities` consumes/deploys the canonical `contracts/AfKing.sol` (the in-tree, audited source per D-01) rather than maintaining a divergent `StreakKeeperV2`, plus the `AF_KING` pinned-address alignment.

### Current cross-repo state (live)
- **Game-side `contracts/ContractAddresses.sol`:** has NO `AF_KING` / `KEEPER` constant yet (verified — PROTO-05 ADD-ABSENT). Pinning form to mirror: the two-line `address internal constant <NAME> = address(0x…);` block (e.g. `COINFLIP :35`, `VAULT :37`, `SDGNRS :47`), header-commented as "Compile-time constants populated by the deploy script."
- **Utilities `../degenerus-utilities/contracts/ContractAddresses.sol`:** `address internal constant STREAK_KEEPER_V2 = address(0); // TODO: pin on release/sepolia in Phase 17 — per D13-04` (line 35). The keeper's own pinned slot is still a zero placeholder.
- **Utilities deploy/wiring assets present:** `script/DeployStreakKeeperV2.s.sol` (the deploy script that produces the keeper address), `script/PatchAddressesForFork.sh` (patches `ContractAddresses.sol` with deploy-predicted addresses), `test/StreakKeeperV2.fork.t.sol` + `test/StreakKeeperV2.unit.t.sol` (the fork/unit harness).
- **No `AfKing.sol` exists in utilities yet** (only unrelated doc-prose hits in utilities `.planning/`); the keeper file is still named `StreakKeeperV2.sol`.

### Reconciliation path (recorded for downstream IMPL)
1. **Single source of truth = `degenerus-audit/contracts/AfKing.sol`** (D-01). The utilities repo must NOT keep a divergent `StreakKeeperV2.sol` copy of the reworked logic.
2. **Consumption mechanism (utilities side):** the utilities `script/DeployStreakKeeperV2.s.sol` (→ to be renamed/repointed for AfKing) deploys the canonical AfKing source. Practical options the IMPL chooses between: (a) import/symlink the canonical `degenerus-audit/contracts/AfKing.sol` into the utilities build via a remapping, or (b) keep the deploy script in utilities but point it at the canonical source path. Either way the LOGIC lives once in `degenerus-audit/contracts/AfKing.sol`.
3. **`AF_KING` pinned-address alignment (PROTO-05 + SUB-06):** the address PROTO-05 pins into game-side `ContractAddresses.sol` MUST equal the address the utilities deploy predicts/produces for the keeper. The existing utilities `PatchAddressesForFork.sh` + `STREAK_KEEPER_V2` placeholder is the alignment mechanism — the deploy pipeline predicts the keeper address and patches BOTH repos' `ContractAddresses.sol` to the same literal. The keeper gates (PROTO-02 `onlyAfKing`, PROTO-03 `onlyFlipCreditors` extension, PROTO-04 `batchPurchase` gate) all key on the game-side pinned `AF_KING` constant — un-spoofable only if it equals the deploy-predicted keeper address.
4. **Keeper-diff approval discipline (D-02):** the utilities AfKing rework diff is ALSO presented for explicit USER review before commit (same review moment as the protocol diff) — the commit-guard hook does NOT watch the other repo, so this gate is enforced manually by the executor pausing for approval at the Phase-317 contract-boundary wave.

**No `contracts/` file modified by Task 2** (`git diff --stat -- contracts/` empty).
