---
phase: 322-impl-the-one-batched-contract-diff-all-7-items
plan: 05
type: execute
status: applied
requirements: [DGAS-01, DGAS-02, DGAS-03, DGAS-04, DSPIN-01]
files_modified:
  - contracts/modules/DegenerusGameDegeneretteModule.sol
committed: false
---

# 322-05 SUMMARY — DegeneretteModule: DGAS write-batching + DSPIN per-currency caps (R5)

**Scope:** ONE file — `contracts/modules/DegenerusGameDegeneretteModule.sol`. GAS-ONLY for DGAS
with a HARD "byte-identical payout results" constraint; DSPIN raises the per-bet spin loop bound.
NOT committed (joins the single batched diff for the wave-8 USER review gate).

Existence of this file = **322-05 fully applied.**

---

## DSPIN-01 — per-currency spin caps (ETH 25 / BURNIE 15 / WWXRP 5)

- Retired `MAX_SPINS_PER_BET = 10` (was `:226`). Replaced with three named constants:
  `MAX_SPINS_ETH = 25`, `MAX_SPINS_BURNIE = 15`, `MAX_SPINS_WWXRP = 5` (`:226-228`).
- `_placeDegeneretteBetCore` validation (was `:445-446`) now selects the cap by currency:
  ```solidity
  uint8 maxSpins = currency == CURRENCY_ETH
      ? MAX_SPINS_ETH
      : currency == CURRENCY_BURNIE
          ? MAX_SPINS_BURNIE
          : MAX_SPINS_WWXRP;   // WWXRP (CURRENCY_WWXRP=3) is the default arm (C6)
  if (ticketCount == 0 || ticketCount > maxSpins) revert InvalidBet();
  ```
- Currency is still authoritatively gated by `_validateMinBet` (`:503`, called at `:454`), which
  runs AFTER the cap check — exactly as today. An unsupported currency (e.g. 2) reverts
  `UnsupportedCurrency` at `_validateMinBet` regardless of `ticketCount` (the cap arm only uses the
  WWXRP default for the branch, never gates the currency). Ordering preserved.
- `grep -rn MAX_SPINS_PER_BET contracts/` → NONE. Both doc comments updated (packing comment ~`:296`
  and `@param ticketCount` ~`:364`) to describe the per-currency caps. `ticketCount` is `uint8`
  (field `[34..41]`) → 25 fits, **no packing change**. Min-bet logic unchanged.

## DGAS-01..04 — cross-bet write-batching (same-results)

### New signatures (return-tuple / accumulator)
The public `resolveBets(address,uint64[]) external` signature is **UNCHANGED** (void) — the interface
decl (`IDegenerusGameModules.sol:390`) and the `DegenerusGame.sol` delegatecall wrapper (`:782`) are
untouched. The cross-bet flush is internal. The private helpers were re-shaped to thread a memory
accumulator (instead of large return tuples):

```solidity
struct ResolveAcc {
    uint256 ethClaimable;   // summed ETH claimable across all bets
    uint256 burnieMint;     // summed BURNIE mint across all bets
    uint256 wwxrpMint;      // summed WWXRP mint across all bets
    bool    poolFrozen;     // prizePoolFrozen snapshot (stable across the call)
    bool    poolLoaded;     // running pool locals initialized?
    uint256 runningFuture;  // unfrozen: running futurePrizePool
    uint128 pendingNext;    // frozen: running pending next pool
    uint128 pendingFuture;  // frozen: running pending future pool
}

function resolveBets(address player, uint64[] calldata betIds) external;          // void (unchanged)
function _resolveBet(address player, uint64 betId, ResolveAcc memory acc) private;
function _resolveFullTicketBet(address player, uint64 betId, uint256 packed, ResolveAcc memory acc) private;
function _distributePayout(address player, uint8 currency, uint128 betAmount, uint256 payout, ResolveAcc memory acc)
    private returns (uint256 lootboxShare);   // returns this spin's ETH lootbox-share
```

A Solidity `memory` struct is reference-passed between internal calls, so per-spin mutations to
`acc` (ETH claimable sum, BURNIE/WWXRP sums, running-pool decrement) persist back to `resolveBets`.

### Single-flush structure (one write per currency)
`resolveBets` constructs `acc`, snapshots `acc.poolFrozen = prizePoolFrozen` ONCE, loops the bets
(each accumulating into `acc`), then flushes ONCE:
```solidity
if (acc.burnieMint   != 0) coin.mintForGame(player, acc.burnieMint);   // one BURNIE mint
if (acc.wwxrpMint    != 0) wwxrp.mintPrize(player, acc.wwxrpMint);     // one WWXRP mint
if (acc.ethClaimable != 0) _addClaimableEth(player, acc.ethClaimable); // one claimable + claimablePool write
if (acc.poolLoaded) {                                                  // one prize-pool write
    if (acc.poolFrozen) _setPendingPools(acc.pendingNext, acc.pendingFuture);
    else                _setFuturePrizePool(acc.runningFuture);
}
```
`_distributePayout` no longer writes storage — it accumulates `ethShare → acc.ethClaimable`,
`payout → acc.burnieMint / acc.wwxrpMint`, mutates the running-pool local, and RETURNS the spin's
ETH lootbox-share. (BURNIE/WWXRP return 0 — no lootbox path.)

### Tier-1 same-results argument (additive)
BURNIE/WWXRP mints and the ETH `claimableWinnings`/`claimablePool` credits are pure additions.
`mintForGame(player, Σpayout) ≡ Σ mintForGame(player, payout)`; `claimableWinnings[p] += Σx ≡` the
sequence of `+= x`. The `claimablePool += weiAmount` inside `_addClaimableEth` is likewise additive.
`_addClaimableEth(0)` is a no-op, so spins with zero ETH share contribute nothing to the sum — same
as today. The claimable write and the pool write touch **disjoint storage slots** with no
read-after-write dependency, so the flush order (`_addClaimableEth` then the pool write) is
immaterial vs the per-spin order (pool write then `_addClaimableEth`). Result: byte-identical
to-the-wei.

### Tier-2 same-results argument (ETH cap against a running-pool local)
The ETH cap / solvency stays evaluated PER SPIN, but against a running local in `acc`:
- The local is lazily loaded on the **first** ETH win (`!acc.poolLoaded`): `_getFuturePrizePool()`
  (unfrozen) or `_getPendingPools()` (frozen). That first read equals the live storage value the
  per-spin path would have read on its first ETH win (no other writer runs inside `resolveBets`).
- Each subsequent ETH win computes `maxEth = pool * ETH_WIN_CAP_BPS / 10_000` (unfrozen) or the
  solvency check `pendingFuture < ethShare` (frozen) **against the running local**, then decrements
  the local. Because today's per-spin path writes the decremented pool back every spin, the next
  spin's storage read equals exactly this running-local value. So every spin's cap/solvency sees the
  identical shrinking pool, the cap binds on the identical spin, `PayoutCapped` fires per-spin on the
  identical spin (kept inside `_distributePayout`), and the frozen solvency revert fires on the
  identical spin. The single pool write at the end equals the final per-spin write. WHEN the cap
  binds is unchanged. Byte-identical.

### DGAS-03 — lootbox summed PER betId (one box per bet)
`_resolveFullTicketBet` accumulates each spin's returned ETH lootbox-share into a per-bet local
`betLootboxShare`, then calls `_resolveLootboxDirect(player, betLootboxShare, rngWord, activityScore)`
ONCE at the end of the bet (one box per `betId`). Lootbox-share is **never** summed across betIds
(resolution-batch-invariant — two bet-txs sharing an `index` still resolve as two boxes). The box
rolls off the bet's `rngWord` (the per-spin `lootboxWord` salt `bytes1(0x4c)` 'L' at ~`:646-657` is
DROPPED). Uses the private `_resolveLootboxDirect` wrapper (`:848`, C9 / ATTEST §F-3), not the module
selector. `_resolveLootboxDirect` (LootboxModule) has zero pool/claimable writes (it can mint a
lootbox WWXRP consolation, independent of the Degenerette WWXRP payout), so resolving it per-bet
before the end-of-call ETH/pool flush introduces no stale read.

### DGAS-04 — DGNRS stays per-spin
`_awardDegeneretteDgnrs` (ETH 6+ matches) is left PER SPIN inside the loop — it reads `poolBalance`
fresh per call (`:~1200`); summing off a stale balance would change the payout. Not batched.

### RNG / freeze UNTOUCHED
- `rngWord = lootboxRngWordByIndex[index]` fetch (`:633`) untouched; place-time RngNotReady guard
  (`:501`) untouched.
- The per-spin RESULT seed (`keccak256(rngWord, index[, spinIdx], QUICK_PLAY_SALT)`, ~`:652-665`)
  KEPT byte-for-byte; `QUICK_PLAY_SALT` (0x51 'Q') unchanged; `spinIdx` still mixed for spin N.
- Only the redundant per-spin `lootboxWord` salt was dropped (the box now rolls once per bet).
- `prizePoolFrozen` snapshotted once and treated as stable — no freeze toggle runs inside
  `resolveBets`. No SLOAD was moved into or out of the rng-window.

## forge build result
`forge build` reports EXACTLY the 3 known pre-existing WhaleModule errors (322-06's), all
`Undeclared identifier _awardEarlybirdDgnrs` at `DegenerusGameWhaleModule.sol:263 / :476 / :587`.
**Zero new errors in DegeneretteModule** — the file is self-contained and compiles within its scope.
The `resolveBets` interface decl + the `DegenerusGame.sol` wrapper are unchanged (void public
signature), so no interface / delegatecall lock-step edit was needed.

## Worst case to measure at Phase 323
Max **25-spin ETH bets** packed into one `resolveBets` call (DSPIN-02 + DGAS-05): the 2.5× roll work
(25 vs old 10) against the single-flush write savings (one mint per currency, one
claimable+claimablePool write, one pool write, one box per bet). Plus a mixed-currency multi-bet
batch (ETH/BURNIE/WWXRP) to confirm the cross-bet flush totals match the per-spin baseline to the wei
(equivalence test) and that the cap binds on the identical spin.

## Deviations
- None from the plan's intent. Used a `memory` struct (`ResolveAcc`) threaded by reference rather
  than literal multi-value return tuples — equivalent accumulation, fewer copies; the plan left
  "exact local variable names / helper placement WITHIN the locked signatures" to implementer
  discretion (322-CONTEXT §decisions). The public `resolveBets` signature stays void as the SPEC
  requires; only the private helpers gained the `acc` parameter.
- `_distributePayout` lost its now-unused `rngWord`/`activityScore` params (the per-bet lootbox call
  moved up to `_resolveFullTicketBet`, which holds both). Private function, no external surface.
