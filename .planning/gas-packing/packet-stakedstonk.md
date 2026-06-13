# Packet — StakedDegenerusStonk (RT-PACKING-12 + RT-PACKING-13)

The solvency-spine stage. Human-gated (user chose to proceed). One coordinated re-layout, one harness
recalibration, full SOLVENCY-01 / redemption-reentrancy regression on top of the standard gates.

## Why this is behavior- AND reentrancy-identical (the core safety argument)
Implemented with **compiler-auto-packed named private fields**, NOT a manual packed `uint256` word.
- `uint128 _totalSupply; uint96 _pendingRedemptionEthValue; uint24 _pendingResolveDay;` → the compiler
  lays these adjacently in one slot (128+96+24 = 248 ≤ 256) and emits a masked SLOAD/SSTORE for each access.
- Every read/write re-SLOADs the shared slot fresh at its statement — the optimizer treats external calls
  as storage barriers and will not hoist a read across one. This is **identical** to the unpacked version
  (where each var was its own slot, each access independent). The packing changes only *where* the bits
  live, not the read-fresh/write-fresh order.
- The skeptic's flagged risk — "caching the packed word across an external call reintroduces the patched
  in-flight-backing reentrancy" — is eliminated by construction: there is no manual cached word to go stale.
  No statement reads the slot into a local, makes an external call, then writes the local back.

## Width safety (verified against live source)
- `_mint` is `private`, called only at L367-368 inside the constructor; `INITIAL_SUPPLY = 1e30`. totalSupply
  starts at INITIAL_SUPPLY and only decreases via burns → ≤ 1e30 « uint128 max (3.4e38). uint128 safe.
- `pendingRedemptionEthValue` is real-ETH-bounded; uint96 holds 7.9e28 wei ≈ 7.9e10 ETH (658× total ETH supply). Safe.
- `pendingResolveDay` already uint24.

## ABI preservation (mandatory — cross-contract readers)
Narrowing changes the auto-getter return types, so make the three fields **private** and add explicit public
views returning the ORIGINAL types:
- `function totalSupply() external view returns (uint256)` (ERC20 standard — many cross-contract readers).
- `function pendingRedemptionEthValue() external view returns (uint256)`.
- `function pendingResolveDay() external view returns (uint24)` (AdvanceModule reads this at L1285/1347/1382).

## Casts (write sites only)
Reads auto-widen (uint96/uint128 → uint256) — no cast. Writes assigning a wider-typed local back to a narrow
field need an explicit narrowing cast with a safety comment (values proven bounded above), e.g.
`_totalSupply = uint128(uint256(_totalSupply) - amount);` and `_pendingRedemptionEthValue = uint96(uint256(_pendingRedemptionEthValue) + maxIncrement);`.

## Scalar site map (rename to private fields)
- totalSupply: reads L481/616/824/912/921; writes L510/550/626/948 (`-= amount`, all `unchecked` & bounded) + constructor L1046 `+= amount`.
- pendingRedemptionEthValue: read L621/834-835/929; RMW L691 (resolve), L770 (yearSweep), L971 (submit `+= maxIncrement`).
- pendingResolveDay: read L902; write L904 (submit first-burn), L702 (resolve clear).

## RT-PACKING-13 — poolBalances uint256[5] → uint128[5]
Change the array element type only. Solidity auto-packs `uint128[5]` into 3 slots in index order:
slot+0 = Whale(0)|Affiliate(1), slot+1 = Lootbox(2)|Reward(3), slot+2 = PresaleBox(4). This co-locates the
dominant warm pair (whale-pass / deity purchase debit Whale then Affiliate in one tx → 2nd access warm,
~2,000 saved). `poolBalances[i]` access, `poolBalances[idx] = available - amount` (transferFromPool clamp),
`delete poolBalances` (L552) all translate mechanically — compiler masks lanes. Width: pool balances bounded
by 1e30 supply « uint128. Sites L370-374 (init), L475/499/505/530/536/538 (access), L552 (delete).

## Layout (PRE → POST)
PRE: totalSupply@0, balanceOf@1, poolBalances@2-6, pendingRedemptions@7, redemptionPeriods@8,
pendingRedemptionEthValue@9, pendingByDay@10, pendingResolveDay@11.
POST (decl order: packed-scalars, balanceOf, poolBalances[uint128[5]], pendingRedemptions, redemptionPeriods, pendingByDay):
slot0 = _totalSupply|_pendingRedemptionEthValue|_pendingResolveDay, balanceOf@1, poolBalances@2-4,
pendingRedemptions@5, redemptionPeriods@6, pendingByDay@7. **Confirm via POST inspect before recalibration.**

## Harness recalibration (from POST inspect — 3 files)
`test/fuzz/RedemptionEdgeCases.t.sol`, `test/fuzz/handlers/RedemptionHandler.sol`, `test/fuzz/StakedStonkRedemption.t.sol`:
- SLOT_PENDING_REDEMPTIONS 7 → (POST), SLOT_REDEMPTION_PERIODS 8 → (POST), SLOT_PENDING_BY_DAY 10 → (POST).
- SLOT_PENDING_REDEMPTION_ETH_VALUE 9 → slot 0 lane [128:224]: writes become masked-lane vm.store.
- SLOT_PENDING_RESOLVE_DAY 11 → slot 0 lane [224:248]: writes become masked-lane vm.store.
- (also `PresaleBoxDrain.t.sol` SLOT_PRESALE_BOX_DGNRS_POOL_START=31 — verify if it indexes sDGNRS poolBalances; recalibrate if so.)

## Validation (extra rigor)
forge 845/0/110 by name + the redemption/solvency suites specifically green (RedemptionEdgeCases, StakedStonkRedemption,
RedemptionHandler invariants, V62RedemptionReentrancy, RedemptionStethFallback, the SOLVENCY-01 / CP-08 / INV-10/13
checks). npm test name-set diff. Independent reviewer on this diff. git-status-verify.
