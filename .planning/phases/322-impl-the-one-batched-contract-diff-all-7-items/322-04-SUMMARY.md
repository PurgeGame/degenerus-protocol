# 322-04 SUMMARY — REDEEM (sDGNRS ETH segregation + BURNIE flip-credit-at-submit)

**Plan:** `322-04-PLAN.md` (Phase 322 IMPL, executor #4 of 7). **Requirements:** REDEEM-01..07 (+ REDEEM-08 invariant).
**Status:** FULLY APPLIED. Contract edits only — NOT committed (single batched diff, user reviews at wave 8).
**Date:** 2026-05-25.
**Files touched (6, all in scope):** `DegenerusGame.sol`, `interfaces/IDegenerusGame.sol`, `modules/DegenerusGameGameOverModule.sol`, `StakedDegenerusStonk.sol`, `BurnieCoinflip.sol`, `BurnieCoin.sol`.

---

## Final signatures

### `resolveRedemptionLootbox` (DegenerusGame.sol, the Game-side R1 target)
```solidity
function resolveRedemptionLootbox(
    address player, uint256 amount, uint256 rngWord, uint16 activityScore
) external payable
```
- Now `external payable`. Gate `msg.sender == SDGNRS` kept. Added `if (msg.value != amount) revert E();`.
- **DELETED the entire unchecked claimable-debit block** (was `uint256 claimable = claimableWinnings[SDGNRS]; unchecked { claimableWinnings[SDGNRS] = claimable - amount; } claimablePool -= uint128(amount);`). Defect A fixed.
- Credits `futurePrizePool` from the arriving `msg.value` (freeze-aware: `prizePoolFrozen ? _setPendingPools(pNext, pFuture+amount) : _setPrizePools(next, future+amount)`). The ETH now physically arrives instead of being a claimable reassignment.
- 5-ETH chunk delegatecall loop UNCHANGED. Boon-always-roll comes from 322-03's R2 inside `_resolveLootboxCommon` — NO call-site flag added (C2 honored).

### `pullRedemptionReserve` (DegenerusGame.sol, NEW — REDEEM-01 / R3)
```solidity
function pullRedemptionReserve(uint256 amount) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert E();
    if (amount == 0) return;
    claimableWinnings[ContractAddresses.SDGNRS] -= amount;   // CHECKED (no unchecked)
    claimablePool -= uint128(amount);                         // CHECKED
    (bool ok, ) = payable(ContractAddresses.SDGNRS).call{value: amount}("");
    if (!ok) revert E();                                      // CEI: state before transfer
}
```
- SDGNRS-gated, CHECKED claimable debit + claimablePool decrement + real ETH transfer to sDGNRS.
- **This is the ONLY remaining `claimableWinnings[SDGNRS]` debit and it is CHECKED.** Solidity 0.8 reverts fail-closed if claimable < amount. Declared in `IDegenerusGame.sol` (the sDGNRS caller uses its own local `IDegenerusGamePlayer` interface, also extended).

## Submit-side MAX-175% pull + fail-closed (StakedDegenerusStonk `_submitGamblingClaimFrom`)
- After the base `ethValueOwed` (gwei-snapped), segregate the MAX (175%) out of claimable into sDGNRS balance:
```solidity
uint256 prevBaseWei = uint256(pool.ethBase) * 1e9;
pool.ethBase += uint64(ethValueOwed / 1e9);
uint256 newBaseWei = uint256(pool.ethBase) * 1e9;
uint256 maxIncrement = (newBaseWei * MAX_ROLL) / 100 - (prevBaseWei * MAX_ROLL) / 100; // MAX_ROLL=175
if (maxIncrement != 0) game.pullRedemptionReserve(maxIncrement);
pendingRedemptionEthValue += maxIncrement;
```
- **Fail-closed (LOCKED):** if `pullRedemptionReserve` can't fully segregate (claimable[SDGNRS] short — e.g. AfKing SUB-09 drained it, C5 — or the game can't physically send the ETH), the CHECKED debit / `call` reverts → the whole burn reverts. The redeemer retries once claimable/liquidity recovers (accepted liveness coupling).
- **Telescoping increment (key correctness fix):** `maxIncrement` is the delta of `floor(cumulativeBaseWei × 175 / 100)` before/after this claim. Summed over the day it equals EXACTLY `(pool.ethBase × 1e9 × 175)/100` — the value resolve subtracts. **Zero rounding drift, zero underflow risk** at resolve (a naive per-claim `floor(base_i × 175/100)` would under-accumulate vs the aggregate floor and could underflow `pendingRedemptionEthValue` at resolve).
- `pool.ethBase` still tracks the BASE (100%) in gwei (claim-side uses base × roll / 100, unchanged).

## Resolve (StakedDegenerusStonk `resolveRedemptionPeriod`) — REDEEM-02
- ETH-only release from MAX→rolled (accounting only, no transfer back):
```solidity
uint256 segregatedMax = (ethBase * MAX_ROLL) / 100;   // ethBase = pool.ethBase * 1e9
uint256 rolledEth     = (ethBase * roll) / 100;
pendingRedemptionEthValue = pendingRedemptionEthValue - segregatedMax + rolledEth;
```
- `segregatedMax` equals the day's accumulated `Σ maxIncrement` exactly (telescoping) → no underflow.
- Signature `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)` KEPT (ABI-stable for the 3 AdvanceModule call sites, which are out of my file scope); `flipDay` is now an accepted-but-unused param (silenced via `flipDay;`). The `RedemptionPeriod.flipDay` STRUCT FIELD is deleted; the day+1 coinflip lookup is gone.

## Claim (StakedDegenerusStonk `claimRedemption`) — REDEEM-03, ETH-only
- NoClaim guard is now `claim.ethValueOwed == 0` (ETH-only). No partial-claim branch — always full `delete pendingRedemptions[player][day]`.
- Pays `ethDirect` FIRST from the segregated balance (`_payEth`, the `game.claimWinnings(address(0))` pull REMOVED from this path).
- Forwards the lootbox share as REAL `msg.value`: `game.resolveRedemptionLootbox{value: lootboxEth}(player, lootboxEth, entropy, actScore)`.
- gameOver→100%-direct / else 50/50 split UNCHANGED. State (pendingRedemptionEthValue release + slot delete) updated BEFORE external calls (CEI; a reentrant claim hits NoClaim).

## BURNIE settle-at-submit (`redeemBurnieShare`) — REDEEM-05, net BURNIE == 0 proof
**BurnieCoinflip.redeemBurnieShare(address redeemer, uint256 base)** (SDGNRS-gated):
```
held = burnie.balanceOf(SDGNRS)
burnFromHeld = min(base, held)            → burnie.burnForRedemption(SDGNRS, burnFromHeld)   [destroys real held BURNIE]
remainder    = base - burnFromHeld        → _claimCoinflipsAmount(SDGNRS, remainder, false)  [consumes stake, NO mint]
                                            (defense-in-depth: revert if consumed < remainder)
_addDailyFlip(redeemer, base, ...)        [deferred mint of `base` to redeemer]
```
**Net-zero proof:** `creditFlip`'s deferred mint of `base` (= burnFromHeld + remainder) is offset by (a) burning `burnFromHeld` of real held BURNIE and (b) consuming `remainder` from sDGNRS's coinflip stake (removing a future mint of exactly `remainder`). So minted = base, destroyed/cancelled = burnFromHeld + remainder = base ⇒ **net new BURNIE == 0**.
**Airtight:** sDGNRS computes `base = (held + previewClaimCoinflips(SDGNRS)) * amount / supply`, so `base ≤ held + stake` ⇒ `remainder ≤ stake` ⇒ the consume always covers `remainder`. Reads are stable within the submit tx (no BURNIE mint to SDGNRS between the submit read and `redeemBurnieShare`). No roll on BURNIE (it gambles via the normal coinflip).

Submit wires it: `if (burnieOwed != 0) coinflip.redeemBurnieShare(beneficiary, burnieOwed);` where `burnieOwed = (balanceOf(SDGNRS) + previewClaimCoinflips(SDGNRS)) * amount / supplyBefore`.

## gameOver double-count drop — REDEEM-04 (both sites)
`DegenerusGameGameOverModule.sol` `handleGameOverDrain`: `reserved`/`postRefundReserved` now = `uint256(claimablePool)` only — the `+ pendingRedemptionEthValue()` term DROPPED at both `:91-92` and `:153-154`. The redemption ETH was segregated OUT of the game at submit (it left `address(this).balance`), so it is no longer part of `totalFunds` here — subtracting it would double-count. Removed the now-unused `import IStakedDegenerusStonk`. Deterministic ETH→stETH fallback UNCHANGED.

## C4 authority extensions (REDEEM-07 — BOTH gates touched)
- **`onlyFlipCreditors`** (BurnieCoinflip): added `ContractAddresses.SDGNRS` (was {GAME, QUESTS, AFFILIATE, ADMIN, AF_KING}).
- **`onlyBurnieCoin`** (the SEPARATE consume gate): extended to allow `SDGNRS` in addition to `COIN` (so sDGNRS can consume its own coinflip stake). `redeemBurnieShare` itself uses the internal `_claimCoinflipsAmount` for atomicity, but the gate widening literally satisfies C4's "touch both gates."
- **New SDGNRS-gated burn on BurnieCoin:** `burnForRedemption(address from, uint256 amount)` — gated `msg.sender == COINFLIP` (the orchestrator is `redeemBurnieShare` on Coinflip per the LOCKED §9 single-atomic-call design) AND `from == SDGNRS`; burns ONLY held balance (no coinflip shortfall consume). New error `OnlySdgnrs`.

## Deleted BURNIE reserve apparatus (REDEEM-06)
- `pendingRedemptionBurnie` storage + every read (`previewBurn`, `burnieReserve`, submit).
- `_payBurnie` (whole fn).
- `RedemptionPeriod.flipDay` (struct field) + the day+1 lookup + the partial-claim BURNIE branch in `claimRedemption`.
- `PendingRedemption.burnieOwed` (struct field, now dead — BURNIE settled at submit) and `DayPending.burnieBase` (struct field, no per-day BURNIE base) — packing comments updated.
- The resolve-time BURNIE release + `burnieToCredit`.
- Events trimmed: `RedemptionSubmitted` `burnieOwed→burnieSettled` (still reports the settled base), `RedemptionResolved` dropped `rolledBurnie`+`flipDay`, `RedemptionClaimed` dropped `flipResolved`+`burniePayout`. `claimRedemption` is now ETH-only.

## SUB-09 self-sub drain accounting (C5)
The sDGNRS ctor 6-arg `afKing.subscribe(address(this), true, false, 1, 2, address(0))` still drains `claimableWinnings[SDGNRS]` daily. The segregation fix accounts for it directly: at submit the MAX (175%) is pulled OUT of claimable into sDGNRS balance via the CHECKED `pullRedemptionReserve`. If the AfKing sub already drained claimable below the MAX, the pull reverts the burn (fail-closed) rather than leaving a virtual reserve a later drain could undercut. Once segregated, the owed ETH lives in sDGNRS balance where no AfKing/claimWinnings/2nd-claimant drain can reach it (Defect A closed).

## Invariants (REDEEM-08)
- **No `unchecked` claimable subtraction in the redemption path** — verified: the only claimable[SDGNRS] debit is `pullRedemptionReserve` (CHECKED); `resolveRedemptionLootbox` has no claimable debit at all; sDGNRS `unchecked` blocks touch only gwei-snap / token-burn arithmetic, never claimable.
- **`claimablePool == Σ claimableWinnings`** stays balanced — `pullRedemptionReserve` decrements both by the same `amount` and moves real ETH out; `resolveRedemptionLootbox` no longer touches claimable.
- **ETH conservation** — `pendingRedemptionEthValue` accumulates exactly what `pullRedemptionReserve` physically pulls in (telescoping = zero drift); resolve lowers it MAX→rolled with the over-pull staying as free backing; claim releases `totalRolledEth` and pays/forwards exactly that.

## BurnsBlockedDuringLiveness re-check (per Task 1 ask)
KEPT unchanged. Rationale UPDATED: the original sweep-race (handleGameOverDrain sweeping virtual-reserved redemption ETH before claimRedemption) is now CLOSED by physical segregation — the ETH leaves the game at submit, so the gameOver drain can't reach it. The guard remains appropriate defense-in-depth: it prevents NEW gambling-burn submits in the liveness window from creating an unresolvable pending pool (resolveRedemptionPeriod only fires via advanceGame, which won't run post-liveness). No concern; no change.

## forge build error set (classified)
`forge build` → **3 errors total**, all known pre-existing 322-06-owned dangling refs:
- **(a) Known 3 WhaleModule:** `Error (7576) Undeclared identifier` `_awardEarlybirdDgnrs` at `DegenerusGameWhaleModule.sol:263`, `:476`, `:587` (R6 body deleted by 322-02; call sites land on 322-06).
- **(b) New expected for later executors:** NONE. Making `resolveRedemptionLootbox` payable changed its selector — updated in lock-step: the Game-side fn, the LootboxModule delegatecall path (unchanged signature — module side is non-payable per 322-03, no selector clash since they're distinct declarations), the sDGNRS local interface (`IDegenerusGamePlayer.resolveRedemptionLootbox ... external payable` + `pullRedemptionReserve`), and the sDGNRS call site (`{value: lootboxEth}`). No NEW dangling refs introduced.
- **(c) Unexpected:** NONE. Zero warnings/errors attributable to any of my 6 files.

Pre-existing non-error noise (not mine): 2 `Warning (2519)` shadow declarations in `DegenerusGameJackpotModule.sol:432/433` (untouched; also noted by 322-03).

## Deviations / notes
- **`resolveRedemptionPeriod` signature kept (flipDay unused param).** Deleting the param would force edits to AdvanceModule (3 call sites) + `IStakedDegenerusStonk.sol`, both OUTSIDE my file scope and shared with other executors. Kept ABI-stable; only the STRUCT field `flipDay` is deleted (in-scope). The plan's acceptance criterion is "RedemptionPeriod.flipDay ... deleted" — the struct field is gone; the param is a harmless accepted-but-unused arg.
- **`claimCoinflipsForRedemption` (BurnieCoinflip:345 + IBurnieCoinflip.sol decl) is now dead** (its only caller was the deleted `_payBurnie`). Left in place — it's a safe SDGNRS-gated fn, not part of the sDGNRS reserve apparatus the plan enumerates for deletion, and removing it would churn the Coinflip surface beyond REDEEM scope. Flag for optional downstream cleanup.
- **`IDegenerusCoinPlayer.transfer` (sDGNRS local iface) is now unused** (was only `_payBurnie`'s `coin.transfer`). Harmless unused decl; `coin.balanceOf` still used. Left in place.
- **TST follow-ups (Phase 323, deferred):** `test/fuzz/StakedStonkRedemption.t.sol`, `RedemptionGas.t.sol`, `RedemptionHandler.sol`, `RedemptionInvariants.inv.t.sol`, `RedemptionEdgeCases.t.sol`, etc. reference the old event/fn signatures — they are NOT compiled by `forge build` and are TST-phase concerns (REDEEM-08 repro is explicitly deferred to 323 per the CONTEXT).
- No git operation performed.

## Verification
- Task1/Task2/Task3 plan automated greps: all PASS.
- `pullRedemptionReserve` SDGNRS-gated + CHECKED + claimablePool decrement + real ETH transfer; declared in IDegenerusGame.sol.
- `resolveRedemptionLootbox` is `external payable`; unchecked claimable debit GONE; futurePrizePool credited from msg.value.
- Both gameOver sites drop `+ pendingRedemptionEthValue`.
- No `pendingRedemptionBurnie` / `_payBurnie` / `RedemptionPeriod.flipDay` token survives in `contracts/`; claimRedemption ETH-only.
- `redeemBurnieShare` exists (SDGNRS-gated, atomic burn→consume→creditFlip); SDGNRS in `onlyFlipCreditors` AND `onlyBurnieCoin`; new `burnForRedemption` on BurnieCoin.
- `forge build` error set = exactly the known 3 WhaleModule errors (322-06).
