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
