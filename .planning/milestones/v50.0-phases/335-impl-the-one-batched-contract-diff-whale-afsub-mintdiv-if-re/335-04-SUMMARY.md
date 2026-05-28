---
phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
plan: 04
type: execute
wave: 2
completed: 2026-05-28
status: applied (uncommitted — held for BATCH-02 hand-review)
files_modified:
  - contracts/AfKing.sol
  - contracts/BurnieCoin.sol
requirements: [AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05]
---

## Outcome

The AFSUB cluster is applied to disk: `AfKing.sol` is re-shaped from a BURNIE-prepay-window subscription model to a pass-gated model that consumes the new `lazyPassHorizon` view (Plan 335-01's producer). `burnForKeeper` is deleted from BOTH `AfKing.sol` (iface decl + 2 call sites) AND `BurnieCoin.sol` (impl + event + modifier + bound error). The `Sub` struct slot offset 5 is repurposed in place from `uint32 paidThroughDay` → `uint32 validThroughLevel` (zero packing churn). The `_autoBuy` per-iter check is a cheap stored-field compare; the crossing branch re-reads `lazyPassHorizon` EXACTLY ONCE and refresh-or-evicts via the existing tombstone-then-reclaim pattern. OPEN-E + SUB-07 + v49 swap-pop invariants preserved by construction.

## Post-edit `Sub` struct layout

```solidity
struct Sub {
    uint8   dailyQuantity;     // offset 0
    uint32  lastAutoBoughtDay; // offset 1
    uint32  validThroughLevel; // offset 5  ← repurposed from paidThroughDay (D-11)
    uint8   reinvestPct;       // offset 9
    uint8   flags;             // offset 10 (bit 0 freed; bit 1 = drain, bit 2 = tickets)
    address fundingSource;     // offset 11 (UNTOUCHED — OPEN-E preservation)
}
```

Width kept `uint32` (Claude's Discretion per the plan — zero packing churn vs the existing layout). The `lazyPassHorizon` view returns `uint24`; the assignment is `uint32(IGame(GAME).lazyPassHorizon(...))` (lossless widen). Offsets 0/1/9/10/11 are byte-identical to the baseline.

## Post-edit IGame iface (AfKing.sol:23-44)

ADDED:
- `function level() external view returns (uint24);` — needed by the `_autoBuy` hoisted SLOAD.
- `function lazyPassHorizon(address player) external view returns (uint24);` — the AFSUB-02 producer (D-11).

REMOVED:
- `function hasAnyLazyPass(address player) external view returns (bool);` — the v50.0 pass-gating uses `lazyPassHorizon` as the single producer; AfKing no longer calls `hasAnyLazyPass`. NOTE: the `hasAnyLazyPass` view on `DegenerusGame.sol` itself is UNTOUCHED (per Plan 335-01 — other callers may still reference it).

The `IBurnie` iface block (was lines 45-58 pre-edit) is **deleted entirely** — its only member was `burnForKeeper`, now gone. Cleanup per the plan's "if no other IBurnie members exist" condition.

## Post-edit `subscribe` body (AfKing.sol:355-405)

The pre-edit body (lines 374-444) had a 71-line shape with the SUB-01 pass-OR-pay block as the load-bearing interaction-last step. The post-edit body is 50 lines:

PRESERVED (UNTOUCHED, line ranges shift but content byte-identical):
- `if (dailyQuantity == 0) revert InvalidDailyQuantity();`
- `if (reinvestPct > 100) revert InvalidReinvestPct();`
- The **SUB-02 self-consent gate**: `address subscriber = player == address(0) ? msg.sender : player; if (subscriber != msg.sender) { if (!IGame(...).isOperatorApproved(subscriber, msg.sender)) revert NotApproved(); }`
- The **OPENE-04 fundingSource consent gate**: `if (fundingSource != address(0) && fundingSource != subscriber && !IGame(...).isOperatorApproved(fundingSource, subscriber)) revert NotApproved();`
- The msg.value pool credit (`_poolOf[subscriber] += msg.value; emit Deposited;`).
- The `dailyQuantity`, `flags` (bits 1+2), `reinvestPct`, `fundingSource` writes.
- The `_addToSet(subscriber)` set insertion.
- The `SubscriptionUpdated` event emit.

DELETED:
- The `Sub storage s = _subOf[subscriber]; uint32 today = _currentDay();` preamble's `today` (still computed elsewhere as needed).
- The anchor math `uint32 anchor = s.paidThroughDay > today ? s.paidThroughDay : today;`.
- The write `s.paidThroughDay = anchor + WINDOW_DAYS;`.
- The entire SUB-01 pass-OR-pay block (the `if (hasAnyLazyPass) { s.flags &= ~FLAG_WINDOW_PAID; } else { ... burnForKeeper ... }` — 14 lines deleted).

ADDED:
- ONE line: `s.validThroughLevel = uint32(IGame(ContractAddresses.GAME).lazyPassHorizon(subscriber));` (positioned AFTER both consent gates; before the `_addToSet` + event emit). NO BURNIE charge.

## Post-edit `_autoBuy` per-iter + crossing

PRESERVED:
- The `:570-583` daily cursor reset (`_autoBuyDay == today` check + `_autoBuyCursor` snapshot).
- The chunk buffers preamble (`players`, `amounts`, `modes`, `batchLen`, `didWork`).
- The `:619-624` AlreadyAutoBoughtToday skip.
- The `_resolveBuy` call + the `lootboxSkip` early-out.
- The OPENE-02 `src = sub.fundingSource == address(0) ? player : sub.fundingSource` resolution.
- The InsufficientPool funding-skip two-tier kill (with the `flags &= ~FLAG_WINDOW_PAID` line REMOVED — bit 0 is freed).
- The CEI debit + slice accumulation + `lastAutoBoughtDay` day-stamp + final cursor write + final batched purchase + bounty payout.

HOISTED:
- `uint24 currentLevel = IGame(ContractAddresses.GAME).level();` — ONCE per autoBuy call, BEFORE the loop. GASOPT-05 preserved: per-iter validity is a pure stored-field compare with no external SLOAD on the non-crossing path.

REWRITTEN — the (0) cancel-tombstone reclaim:
- `preservePaidWindow` branch DROPPED (under AFSUB-01 there's no BURNIE prepay window to preserve). Every cancel = full delete.
- New shape: `delete _subOf[player]; _removeFromSet(player); emit SubscriptionExpired(player, 2); didWork = true; ++processed; continue;`
- `continue` WITHOUT cursor advance — Pitfall P6 / v49 swap-pop invariant preserved.

REWRITTEN — the (2) per-iter validity + crossing (replaces pre-edit day-31 auto-extract branch):
```solidity
if (currentLevel > sub.validThroughLevel) {
    uint24 h = IGame(ContractAddresses.GAME).lazyPassHorizon(player);
    if (currentLevel <= h) {
        // REFRESH
        sub.validThroughLevel = uint32(h);
        emit SubscriptionExtendedFree(player, today);
        didWork = true;
    } else {
        // EVICT — tombstone-then-reclaim (Pitfall P6)
        sub.dailyQuantity = 0;
        _removeFromSet(player);
        emit SubscriptionExpired(player, 1);
        didWork = true;
        unchecked { ++processed; }
        continue;
    }
}
```

`lazyPassHorizon(player)` is read EXACTLY ONCE at the crossing. The non-crossing path consumes ZERO external SLOADs.

DELETED:
- The day-31 PAID branch (the 25-line `burnForKeeper` call + shortfall handling + `BurnieAutoExtracted` event emit).
- The day-31 FREE pass-extend branch's `hasAnyLazyPass(player)` read + `s.paidThroughDay = today + WINDOW_DAYS` + `s.flags &= ~FLAG_WINDOW_PAID` writes. (The REFRESH branch in the rewrite replaces this functionally.)
- The `flags &= ~FLAG_WINDOW_PAID` line in the InsufficientPool funding-skip kill (bit 0 freed; no flag to clear).

## Post-edit `BurnieCoin.sol`

Four deletions:
- Event `KeeperBurn(address indexed user, uint256 amountBurned);` (was `:82-85` with 3-line NatSpec).
- Error `OnlyAfKing();` (was `:109-110` with NatSpec).
- Function `burnForKeeper(address user, uint256 amount) external onlyAfKing returns (uint256 burned) { ... }` (was `:472-488`, 17 lines including NatSpec).
- Modifier `onlyAfKing() { if (msg.sender != ContractAddresses.AF_KING) revert OnlyAfKing(); _; }` (was `:549-552` with NatSpec).
- The modifier-hierarchy NatSpec table row `onlyAfKing | AF_KING only` (was `:529`).

PRESERVED:
- `modifier onlyGame()` (at post-edit `:497`).
- `modifier onlyVault()` (at post-edit `:504`).
- All errors except `OnlyAfKing` (`OnlyGame`, `OnlyVault`, `Insufficient`, `AmountLTMin`, `ZeroAddress`, etc.).
- All events except `KeeperBurn`.

System-wide `grep burnForKeeper contracts/` returns 0 hits in code (2 remaining hits at `AfKing.sol:100` + `:508` are intentional historical NatSpec references explaining the v50.0 transition).

## Deviations / non-strict-scope cleanups

1. **`IBurnie` iface block deleted entirely** (not just the `burnForKeeper` member). Rationale: that was the ONLY member; an empty iface block was the alternative. The plan's "if no other IBurnie members" condition matched.

2. **`BurnieAutoExtracted` event decl deleted** (AfKing.sol pre-edit `:174`). Its only emitter was the day-31 PAID branch I removed. Plan Task 3 acceptance criterion `grep BurnieAutoExtracted = 0` required this.

3. **`BurnieChargeFailed` error decl deleted** (AfKing.sol pre-edit `:134-137`). Its only revert site was the deleted subscribe-time burnForKeeper shortfall path.

4. **`SUB_COST_ETH_TARGET` immutable + `_subCostEthTarget` constructor param + `InvalidSubCostTarget` error LEFT INTACT.** This is a deliberate scope decision: the plan didn't enumerate these for deletion, and removing the constructor param has deployment-script ripple. Surfaced for USER 335-07 hand-review consideration:
   - The immutable is now unreferenced by any code path (post-AFSUB-01 there is no BURNIE prepay window to compute a cost against).
   - The constructor still requires it (`revert InvalidSubCostTarget()` if `_subCostEthTarget == 0`).
   - **Recommendation:** delete in a follow-up cleanup commit (or fold into 335-07 if the USER wants the tighter shape pre-launch). Until then, it's a documented dead immutable — visible storage gas at deploy, no runtime cost.

5. **NatSpec rewritten** for the file-header IGame block, the contract-level AfKing block, the `Sub` struct, the `subscribe` and `setDailyQuantity` docstrings, the `_autoBuy` per-player ladder docstring, the `SubscriptionExpired` reason-code list, and the `SubscriptionExtendedFree` event. All updates reflect the post-AFSUB shape.

## SUB-09 deploy-time self-subscribes — expected behavior change

The `VAULT` and `SDGNRS` deploy-time self-subscribes (constructor / fixture-time) will be encoded with `validThroughLevel = lazyPassHorizon(VAULT)` and `lazyPassHorizon(SDGNRS)` respectively. Since neither holds a pass (no deity bit, no `frozenUntilLevel`), the horizon reads will return `0`. On their first `_autoBuy` crossing iteration, `currentLevel > 0` will be true, the keeper will re-read `lazyPassHorizon` (still `0`), and the EVICT branch will fire (tombstone + swap-pop). This is the **expected** post-AFSUB behavior:
- VAULT and SDGNRS are no longer permanently subscribed under v50.0.
- The OPEN-E `fundingSource` field on their `Sub` records is preserved through the eviction (the field is in the `Sub` struct being deleted, so it goes away — but the `fundingSource` was either `address(0)` (self) or another OPEN-E-approved address; no `fundingSource` state in OTHER subs is touched).
- The two-tier funding-skip InsufficientPool branch (which exempts VAULT + SDGNRS by pinned identity) is now MOOT for these two specific subs (they no longer get to the funding-skip step — they're evicted earlier in the same iteration). The branch is still in place for any OTHER sub the protocol may add later, but for these two specific deploy-time entries the eviction is structural.

**Plan 335-05 fixture re-attestation required:** the test fixture must EITHER (a) update the deploy-time entries to subscribe with a still-valid pass + assert refresh-not-evict semantics, OR (b) accept that the first autoBuy after deploy evicts both and assert the tombstone-then-reclaim shape fires cleanly.

## Plan-level acceptance gates (10/10 pass)

| # | Gate | Result |
|---|------|--------|
| 1 | System-wide `burnForKeeper` code paths = 0 | ✓ 0 (2 NatSpec historical refs intentional) |
| 2 | System-wide `paidThroughDay` code paths = 0 | ✓ 0 (2 NatSpec historical refs intentional) |
| 3 | `lazyPassHorizon(` calls in AfKing.sol = 2-3 | ✓ 2 calls (subscribe + crossing); +1 iface decl + 4 NatSpec refs |
| 4 | OPEN-E preserved | ✓ `fundingSource` = 20 lines (struct + decls + gates + uses); SUB-02 gate intact |
| 5 | Tombstone preserved | ✓ `sub.dailyQuantity = 0` = 2 (cancel reclaim + EVICT); `_removeFromSet(player)` = 3 (cancel + EVICT + InsufficientPool) |
| 6 | `validThroughLevel` ≥ 5 | ✓ 11 references (struct decl + subscribe write + per-iter compare + crossing refresh + NatSpec) |
| 7 | NO `refreshPass` entrypoint | ✓ 0 |
| 8 | No new external Burnie call | ✓ `IBurnie` iface entirely deleted |
| 9 | BurnieCoin sibling modifiers preserved | ✓ `onlyGame:497`, `onlyVault:504` |
| 10 | IGame iface `lazyPassHorizon` decl | ✓ `:38` |

## Invariants re-attested

- **v45 VRF-freeze invariant** — N/A directly to this plan; `lazyPassHorizon` is a pure read. No frozen-slot write introduced.
- **OPEN-E 4 structural protections** — preserved by construction: `fundingSource` field UNTOUCHED, SUB-02 (`:368`) UNTOUCHED, OPENE-04 (`:376-385`) UNTOUCHED, the new horizon encode positioned AFTER both consent gates. Plan 335-05 Test 2 owns empirical re-attest.
- **SUB-07 cancel-tombstone + v49 swap-pop** — pass-eviction routes through `dailyQuantity=0 + _removeFromSet + continue-without-cursor-advance` (identical shape as the existing cancel-reclaim at `:563-575`); Pitfall P6 enforced; H-CANCEL-SWAP-MISS class structurally cannot reproduce. Plan 335-05 Test 3 owns empirical re-attest.
- **GASOPT-05 per-iter no-external-read** — preserved by the hoisted `currentLevel` SLOAD + the stored-field compare per-iter; only 1 `lazyPassHorizon(player)` call in `_autoBuy`, scoped to the crossing branch.
- **D-IMPL-01 gameOver-forfeit** — N/A (whale-side).
- **`_applyWhalePassStats` 3-caller invariant** — N/A (whale-side).

## STRIDE re-attested

T-335-16 through T-335-24 all hold (see plan body). Notable:
- **T-335-16 OPEN-E 4 protections regression** — mitigated: the horizon encode is AFTER both consent gates (gates fire first; a still-pending revert preempts the storage write).
- **T-335-17 H-CANCEL-SWAP-MISS class** — mitigated: EVICT routes through tombstone-then-reclaim; never a direct mid-sweep removal.
- **T-335-18 membership ⟺ packed != 0** — preserved: both cancel-reclaim AND new pass-eviction use the same dailyQuantity=0 → tombstone shape.
- **T-335-19 GASOPT-05 regression** — mitigated: `lazyPassHorizon(player)` appears 1× in `_autoBuy` (crossing branch only); per-iter is pure stored-field compare.
- **T-335-20 refreshPass slip-in** — mitigated: zero `function refreshPass` matches.

## Within-cluster ordering recorded

D-09 Claude's Discretion: applied AfKing-first (IBurnie iface deletion, the 2 call sites at subscribe + day-31 branch removed in subscribe+_autoBuy rewrites), then BurnieCoin (impl + event + modifier + error). Atomic-diff property — either order safe; AfKing-first is the reviewer-clarity narrative.

## key-files.created / modified

| Path | Action | Diff |
|------|--------|------|
| `contracts/AfKing.sol` | modified | +88/-180 (273 lines touched); IGame iface members added, IBurnie iface deleted, Sub struct repurposed, subscribe + _autoBuy rewritten, NatSpec aligned |
| `contracts/BurnieCoin.sol` | modified | -45 (4 deletions: impl + event + modifier + error + 1 NatSpec table row) |

## Addendum — USER mid-execution refactor: constant `IGame` / `ICoinflip` handles

User raised a code-review observation that `AfKing.sol` was unique in NOT following the pattern at `contracts/storage/DegenerusGameStorage.sol:136-147`, which declares its protocol-handle interfaces as `T internal constant handle = T(ContractAddresses.HANDLE_ADDR);`. The inline `IGame(ContractAddresses.GAME).foo()` call-site shape was an inconsistency, not a load-bearing design choice — and a prior misclaim in this session that "contract types can't be `constant`" was incorrect. Solidity allows constant contract-typed declarations when the initializer is itself a compile-time constant expression (`IGame(<address constant>)` qualifies).

Refactor applied to `contracts/AfKing.sol`:

(a) Inserted two constant typed handles at the very top of the contract body (lines 128-129):
```solidity
IGame internal constant GAME = IGame(ContractAddresses.GAME);
ICoinflip internal constant COINFLIP = ICoinflip(ContractAddresses.COINFLIP);
```

(b) Replaced all 14 inline `IGame(ContractAddresses.GAME)` casts with `GAME` (the 16 grep hits collapsed to: 14 active call sites + 1 in the const decl + 1 in the file-header NatSpec describing the pattern).

(c) Replaced the single inline `ICoinflip(ContractAddresses.COINFLIP)` cast with `COINFLIP`.

(d) Rewrote the IGame-iface NatSpec block and the contract-level NatSpec block to describe the constant-handle pattern (rather than the prior "every call site is inline" prose).

### Acceptance for the refactor

- `grep -c "IGame(ContractAddresses\.GAME)" contracts/AfKing.sol` returns 2 (the const decl + 1 NatSpec self-reference describing the pattern). No active inline call sites remain.
- `grep -c "ICoinflip(ContractAddresses\.COINFLIP)" contracts/AfKing.sol` returns 2 (same shape).
- `grep -cE "\\bGAME\\.[a-z]" contracts/AfKing.sol` returns 15 (14 call sites + 1 NatSpec self-doc).
- `grep -cE "\\bCOINFLIP\\.[a-z]" contracts/AfKing.sol` returns 1.
- All 10 plan-level gates still pass (the refactor is purely textual; no semantic surface touched).

### Gas / deployment impact

- **Runtime gas:** zero change. The constant-handle compiles to the same `PUSH20 <literal>` + `STATICCALL`/`CALL` as the inline cast. The Solidity optimizer treats both identically.
- **Deployment cost:** zero immutable slots added (constants are inlined at compile time into the deployed bytecode, NOT stored as immutables).
- **Codesize:** minor net reduction at every call site (`GAME` is shorter than `IGame(ContractAddresses.GAME)`).

### Final file-level diff stat

`contracts/AfKing.sol`: **+148/-167** (revised from the 88/180 above). The increase in inserts vs the pre-refactor count is the two new constant decls + the NatSpec rewrites; the increase in deletions is the 15 inline casts being collapsed to short tokens.

## Self-Check: PASSED (10/10 gates) + USER refactor applied

Status: applied to working tree, uncommitted. Wave 2 complete. Wave 3 next: 335-05 (test full-alignment migration — 7 files).
