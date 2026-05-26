# 322-06 SUMMARY — CPAY (universal claimable-pay) + WhaleModule earlybird→presaleBoxCredit swap (wave 6)

**Plan:** `322-06-PLAN.md` (wave 6, executor #6 of 7). **Status:** FULLY APPLIED.
**Discipline:** NO git operation performed. Contracts left dirty for the single batched-diff review (wave 8).
**Built on:** the tree after executors #1–5 (322-01..05). Anchors re-grepped at edit time; WhaleModule sites :263/:476/:587 confirmed exact; DegenerusGame `external payable` lines drifted after 322-02/04 (re-enumerated below).
**Requirements:** CPAY-01, CPAY-03 (plus PRESALE-03 remainder — the 3 WhaleModule credit sites).

---

## Files touched (2)

1. `contracts/modules/DegenerusGameWhaleModule.sol` — the 3 whale purchases get claimable-pay (CPAY-01) + the 3 `_awardEarlybirdDgnrs` sites swapped to `presaleBoxCredit` accrual (PRESALE-03); 1 stale "earlybird" code comment updated to describe what IS.
2. `contracts/modules/DegenerusGameLootboxModule.sol` — ONE-LINE cross-plan reconciliation: dropped a stale 4th arg on a `_boonFromRoll` call site left over from executor #3's (322-03) signature reduction (see Deviations). NOT a CPAY edit.

`contracts/DegenerusGame.sol` was SWEPT (CPAY-03) but required NO edit — every `external payable` entry is already covered or legitimately out of scope (full table below).

---

## Task 1 — CPAY-01 (claimable-pay on the 3 whale purchases) + PRESALE-03 (earlybird→presaleBoxCredit)

### The canonical shortfall pattern applied (ATTEST §H, R3)
Each of `_purchaseWhaleBundle` / `_purchaseLazyPass` / `_purchaseDeityPass` replaced `if (msg.value != totalPrice) revert E();` with:
```solidity
if (msg.value > totalPrice) revert E();              // no overpay
uint256 shortfall = totalPrice - msg.value;
if (shortfall != 0) {
    uint256 claimable = claimableWinnings[buyer];
    if (claimable <= shortfall) revert E();          // STRICT — preserves the 1-wei sentinel
    unchecked { claimableWinnings[buyer] = claimable - shortfall; }
    claimablePool -= uint128(shortfall);             // checked; debited by EXACTLY shortfall
}
```
- `buyer` is the address each fn already resolves (the facade `_resolvePlayer`s before the delegatecall; WhaleModule receives the resolved `buyer`). The debit hits the resolved buyer's ledger — correct.
- **R3 invariant:** `claimableWinnings[buyer]` and `claimablePool` are both debited by exactly `shortfall` → `claimablePool == Σ claimableWinnings` stays balanced. Pure ledger move; no double-credit; no real ETH moves on the claimable-funded portion. The whale purchase routes the committed value into pools/passes downstream exactly as before — only the SOURCE of the value (fresh ETH vs claimable shortfall) changed.
- `purchaseDeityPass`: `deityPassPaidTotal[buyer] += totalPrice;` (the post-check accumulator) is PRESERVED unchanged.

### PRESALE-03 — the 3 earlybird credit sites swapped (R6)
Mirrors exactly the MintModule:1187 pattern executor #2 landed:
- `_purchaseWhaleBundle` (was `_awardEarlybirdDgnrs(buyer, totalPrice)`) → `if (!presaleOver) { presaleBoxCredit[buyer] += totalPrice / 4; }`
- `_purchaseLazyPass`  (was `_awardEarlybirdDgnrs(buyer, benefitValue)`) → `if (!presaleOver) { presaleBoxCredit[buyer] += benefitValue / 4; }` (preserves the original earlybird semantics: accrued on `benefitValue`, the undiscounted value, NOT `totalPrice`)
- `_purchaseDeityPass` (was `_awardEarlybirdDgnrs(buyer, totalPrice)`) → `if (!presaleOver) { presaleBoxCredit[buyer] += totalPrice / 4; }`
- Accrual is on the TOTAL committed price (msg.value + claimable shortfall) for bundle/deity, and on `benefitValue` for lazy — matching the former `_awardEarlybirdDgnrs(buyer, <amount>)` argument exactly.

### `_awardEarlybirdDgnrs` fully removed — CONFIRMED
`grep -rn _awardEarlybirdDgnrs contracts/` → **EMPTY** (exit 1, zero matches). Body was deleted by 322-02; these were the last 3 call sites. Earlybird DGNRS-emission subsystem is now fully gone.

**Residual "earlybird" matches are unrelated and CORRECTLY KEPT:**
- `JackpotModule:348/364/365/391/639` — `isEarlyBirdDay` / `_runEarlyBirdLootboxJackpot`: the EarlyBird LOOTBOX JACKPOT mechanism (a distinct day-0 jackpot subsystem), NOT the deleted DGNRS-credit emission. Out of scope.
- `WhaleModule:450` — a code comment on `benefitValue`; updated from "used for earlybird/lootbox/pool splits" → "used for presale-box credit/lootbox/pool splits" (comment now describes what IS).

---

## Task 2 — CPAY-03 sweep: every `external payable` entry in DegenerusGame.sol

Re-enumerated at edit time (`grep -n "external payable"`): **13 entries** (the ATTEST §A.2 pre-patch list of 9 + 2 box facades from 322-02 + payable `resolveRedemptionLootbox` from 322-04, and `receive()`). Per-entry disposition:

| # | Line | Entry | Disposition | Reason |
|---|------|-------|-------------|--------|
| 1 | :347 | `recordMint(...)` | **already-claimable** + onlySelf | `msg.sender != address(this)` revert; the claimable/Combined pattern lives in `_processMintPayment` (ATTEST §H.3). |
| 2 | :498 | `purchase(...)` | **already-claimable** | Facade → `_purchaseFor` → MintModule `_processMintPayment` (canonical claimable pattern, H.1/H.3). |
| 3 | :561 | `buyPresaleBox(...)` | **already-claimable** | 322-02 CPAY-02: standalone box accepts msg.value + claimable shortfall (STRICT sentinel; pool balanced). |
| 4 | :592 | `buyLootboxAndPresaleBox(...)` | **already-claimable** | 322-02: mint leg via `_purchaseFor` (claimable); box leg claimable-funded. |
| 5 | :661 | `purchaseWhaleBundle(...)` | **covered-by Task 1** | Facade → WhaleModule `purchaseWhaleBundle`, where Task 1 added the canonical pattern. |
| 6 | :683 | `purchaseLazyPass(...)` | **covered-by Task 1** | Facade → WhaleModule `purchaseLazyPass` (Task 1). |
| 7 | :703 | `purchaseDeityPass(...)` | **covered-by Task 1** | Facade → WhaleModule `purchaseDeityPass` (Task 1). |
| 8 | :756 | `placeDegeneretteBet(...)` | **already-claimable** | Facade → DegeneretteModule `_collectBetFunds` (ETH-bet claimable pull, ATTEST §H.2/C5). |
| 9 | :1735 | `batchPurchase(...)` | **already-claimable** (keeper-gated) | `onlyAfKing`; forwards per-player slices to `_batchPurchaseUnit` → `_purchaseFor` (claimable). Keeper batch, not a direct player entry. |
| 10 | :1776 | `_batchPurchaseUnit(...)` | **EXCLUDED** | `onlySelf` (`msg.sender != address(this)` revert). Internal self-call wrapper — per ROADMAP, not a user entry. |
| 11 | :1840 | `resolveRedemptionLootbox(...)` | **out-of-scope** | SDGNRS-gated; `msg.value != amount` exact. The ETH was already segregated out of `claimableWinnings[SDGNRS]` at submit (322-04 REDEEM); this is a real-ETH-IN pool credit, NOT a player purchase. Claimable-pay would double-debit. |
| 12 | :1936 | `adminSwapEthForStEth(...)` | **out-of-scope (fresh-ETH-only, documented)** | ADMIN-gated value-neutral ETH↔stETH swap; `msg.value != amount` MUST hold for the value-neutral invariant. Not a purchase; requires real ETH to exchange for stETH (claimable is a ledger entry, not transferable swap ETH). |
| 13 | :2738 | `receive()` | **out-of-scope (donation)** | Bare ETH receiver routing `msg.value` straight to the future prize pool. Pure donation, no buyer/purchase semantics — claimable-pay is inapplicable. |

**Sweep verdict:** every player-facing PURCHASE entry accepts msg.value + claimable shortfall (entries 1–9 via the canonical pattern). No entry silently rejects claimable-pay without a documented reason. `_batchPurchaseUnit` excluded (onlySelf). The 3 non-purchase payable entries (resolveRedemptionLootbox / adminSwapEthForStEth / receive) are dispositioned with rationale. **No edit to DegenerusGame.sol was required.**

**R3 balance across the swept set:** every new claimable debit (Task 1's 3 whale sites) decrements `claimablePool` by exactly the same `shortfall` it removes from `claimableWinnings[buyer]`. No swept entry debits claimable without an equal pool decrement, and no swept entry moves real ETH on the claimable-funded portion. `claimablePool == Σ claimableWinnings` holds.

---

## forge build result

**`contracts/` builds CLEAN — 0 errors.**
- The 3 dangling `_awardEarlybirdDgnrs` Undeclared-identifier errors (WhaleModule :263/:476/:587) are RESOLVED.
- JackpotModule shows only the 2 pre-existing `Warning (2519)` shadow-declaration warnings (untouched noise, NOT errors, exactly as the plan's BUILD EXPECTATION notes).
- A 4th error surfaced that was NOT one of my 3 owned dangling refs: `Error (6160)` at `DegenerusGameLootboxModule.sol:1894` — a stale 4-arg call to `_boonFromRoll` (now 3-param). See Deviation 1.

**Remaining `forge build` errors are ALL in `test/` (55 total), owned by Phase 323 (TST):**
- `test/fuzz/RedemptionEdgeCases.t.sol` ×54 — `Error (7364)` tuple-arity mismatches: the tests still destructure `RedemptionPeriod`/`PendingRedemption` with the OLD field counts (322-04 REDEEM dropped `RedemptionPeriod.flipDay` and changed `pendingRedemptions`).
- `test/fuzz/RngLockDeterminism.t.sol` ×1 — `Error (9582)` `gamePurchaseBurnieLootbox` not found on DegenerusVault (322-03 removed the BURNIE-lootbox surface).
These are downstream test-side breakages from the v47 struct/surface changes (deferred to 323 per 322-CONTEXT). They do NOT affect mainnet contract compilation.

---

## Deviations

1. **One-line LootboxModule fix outside my nominal file set (cross-plan reconciliation).** Executor #3 (322-03 LOOT / boon-unification) reduced `_boonFromRoll` from 4 params `(roll, decimatorAllowed, deityEligible, allowPasses)` → 3 `(roll, decimatorAllowed, deityEligible)` and updated the `:1218` call site, but MISSED the `:1894` call site in `_deityBoonForSlot` (still passing the now-removed 4th arg `true`). This left an `Error (6160)` blocking a clean `contracts/` build. The fix is unambiguous and the ONLY one consistent with the new 3-param signature: drop the stale `, true` (the removed `allowPasses` was always-true in the unified resolver). I applied it to honor the plan's HARD "build MUST be CLEAN (0 errors)" gate; it is a 322-03 missed-call-site, flagged here for the wave-8 reviewer. No CPAY/earlybird semantics involved.
2. **No edit to DegenerusGame.sol.** The CPAY-03 sweep found every payable entry already covered or legitimately out of scope (table above). The plan anticipated edits "for ANY player-facing purchase entry that does NOT yet accept claimable" — none existed. Sweep complete; zero edits.

---

**Existence of this file = 322-06 fully applied.** No git commit performed.
