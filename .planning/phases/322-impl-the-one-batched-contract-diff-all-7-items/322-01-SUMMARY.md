# 322-01 SUMMARY — PRESALE foundation (Pool rename + earlybird partial-delete + presale storage + `_creditBoxProceeds`)

**Plan:** `322-01-PLAN.md` (wave 1, executor #1 of 7). **Status:** FULLY APPLIED.
**Discipline:** No git operation performed. Contracts left dirty for the single batched-diff review (plan 322-08).
**Baseline:** clean tree (executor #1); anchors re-grepped at edit time — all matched HEAD `2a18d622` with only the benign line-drift noted in 321-ATTEST-PRESALE.

---

## Files touched (5)

1. `contracts/StakedDegenerusStonk.sol` — Pool enum + bps const + ctor pool-list rename.
2. `contracts/interfaces/IStakedDegenerusStonk.sol` — Pool enum rename (lockstep).
3. `contracts/modules/DegenerusGameAdvanceModule.sol` — `_finalizeEarlybird` + its trigger deleted.
4. `contracts/storage/DegenerusGameStorage.sol` — `EARLYBIRD_END_LEVEL` deleted; presale storage + `PRESALE_BOX_ETH_CAP` added; slot-0 header/inline comments updated.
5. `contracts/modules/DegenerusGamePayoutUtils.sol` — `_creditBoxProceeds` helper added; `ContractAddresses` import added.

---

## Task 1 — `Pool.Earlybird` → `Pool.PresaleBox` (ABI-safe rename)

- Concrete enum `StakedDegenerusStonk.sol`: `Earlybird` → `PresaleBox` at the SAME ordinal (4, last member). `uint8(Pool.PresaleBox) == 4 == old uint8(Pool.Earlybird)`.
- Interface enum `IStakedDegenerusStonk.sol`: renamed identically (ordinal 4).
- Constant `EARLYBIRD_POOL_BPS = 1000` → `PRESALE_BOX_POOL_BPS = 1000` (value UNCHANGED — 10% allocation preserved, PRESALE-10).
- Ctor local `earlybirdAmount` → `presaleBoxAmount` (4 occurrences: decl `:348`, totalAllocated sum, poolTotal sum, pool-list assign).
- Pool-list assignment: `poolBalances[uint8(Pool.PresaleBox)] = presaleBoxAmount;`.
- `burnAtGameOver` `delete poolBalances` — UNCHANGED (still zeroes the renamed ordinal at game-over; PRESALE-13 verified, no edit needed).
- No `Earlybird` token survives in either file.

## Task 2 — earlybird emission subsystem (partial delete + explicit deferral)

**Removed in THIS plan (322-01):**
- `_finalizeEarlybird()` (`AdvanceModule`) — full function + its NatSpec.
- Its sole caller / trigger: the `if (lvl == EARLYBIRD_END_LEVEL) { _finalizeEarlybird(); }` block + the 2-line comment above it (`AdvanceModule`, formerly `:1670-1674`) — deleted in the SAME edit so no dangling reference to the function remained.
- Constant `EARLYBIRD_END_LEVEL` (`Storage`, formerly `:175`) — its only reader was the trigger above; deleted now that the last reader is gone.

**Deferred (NOT touched here) — by deletion-ownership:**
- `_awardEarlybirdDgnrs(address,uint256)` BODY (`Storage`, now `:1004-1047`) — left in place & unused. Deleted by **322-02** after its MintModule call site is swapped.
- Its 4 call sites — UNTOUCHED: `MintModule:1210`, `WhaleModule:263/476/587`. Swapped to `if (!presaleOver) presaleBoxCredit[x] += eth/4` by **322-02** (MintModule) and **322-06** (the 3 WhaleModule sites).
- `EARLYBIRD_TARGET_ETH` (`Storage:178`), `earlybirdDgnrsPoolStart` (`Storage`), `earlybirdEthIn` (`Storage`) — STILL READ inside the deferred body → deferred to **322-02** (deleted with the body).
- (Two `_finalizeEarlybird` mentions remain ONLY as comment text inside the deferred body — they vanish with the body in 322-02.)

Grep-confirmed before each deletion: `EARLYBIRD_END_LEVEL` had zero non-trigger readers; the three deferred state symbols + `EARLYBIRD_TARGET_ETH` each still had a live reader in the body, so they were correctly left for 322-02.

## Task 3 — presale storage + `_creditBoxProceeds` helper

**`DegenerusGameStorage.sol`:**
- `bool internal presaleOver;` — added IMMEDIATELY after `prizePoolFrozen` (last slot-0 field). Lands in slot-0 padding at byte `[30:31]`. Latching monotonic terminal.
- `uint96 internal presaleBoxEthSold;` — own slot (cumulative box ETH; does not fit slot-0's 1 free byte). No partially-filled co-pack slot adopted (none adjacent in the lootbox/presale section; left in its own slot — acceptable, untouched after latch).
- `mapping(address => uint256) internal presaleBoxCredit;` — accrued spendable credit.
- `mapping(uint48 => uint256) internal presaleBoxRngWordByIndex;` — mirrors `lootboxRngWordByIndex` (key width **uint48**, grep-confirmed).
- `mapping(uint48 => mapping(address => uint256)) internal presaleBoxEth;` — mirrors `lootboxEth` shape exactly (index→player→eth).
- `uint256 internal constant PRESALE_BOX_ETH_CAP = 50 ether;` — added next to `LOOTBOX_PRESALE_ETH_CAP = 200 ether` (DISTINCT cap).
- Comments updated to describe what IS (no changelog).

**Slot-0 byte tally (FINAL):** 31/32 bytes used, **1 byte free** (byte `[31:32]`). Header table (`:64-66`) and inline comment (`:218`) both updated from "30 used / 2 padding" → "31 used / 1 padding". Matches SPEC C7.

**`DegenerusGamePayoutUtils.sol` — `_creditBoxProceeds`:**
```solidity
function _creditBoxProceeds(uint256 boxEth) internal {
    if (boxEth == 0) return;
    uint256 sdgnrsShare = (boxEth * 20) / 100;
    claimablePool += uint128(boxEth);
    _creditClaimable(ContractAddresses.VAULT, boxEth - sdgnrsShare);
    _creditClaimable(ContractAddresses.SDGNRS, sdgnrsShare);
}
```
- 80/20 split: VAULT gets `boxEth - sdgnrsShare` (80% + rounding remainder), SDGNRS gets `sdgnrsShare` (20%).
- **Invariant:** the two credits sum to exactly `boxEth`, matching `claimablePool += boxEth` → `claimablePool == Σ claimableWinnings` preserved (SPEC R3).
- Reuses `_creditClaimable` (emits `PlayerCredited` per beneficiary — matches the module's existing event convention, per ATTEST §7b recommendation).
- `uint128(boxEth)` cast safe: box ETH ≤ 50e18 ≪ uint128 max; mirrors the existing `uint128(remainder)` cast in `_queueWhalePassClaimCore`.

---

## Deviations from plan

- **Added `import {ContractAddresses}` to `DegenerusGamePayoutUtils.sol`.** PayoutUtils did not previously import it (it had no need). The base `DegenerusGameStorage` imports `ContractAddresses`, but Solidity does not make a `{named}` import visible transitively in derived files. Every other module that uses `ContractAddresses` imports it explicitly; added the matching import. (Caught via `forge build` — undeclared identifier; resolved.) Within plan discretion ("helper placement"); no design change.

## Anchor drift observed (all benign, none structural)

- `prizePoolFrozen` at `:329` (ATTEST cited `:332`) — same field, end of slot-0.
- `LOOTBOX_PRESALE_ETH_CAP` at `:849` (ATTEST cited `:852`).
- `_awardEarlybirdDgnrs` body now `:1004-1047`; its `Pool.Earlybird` refs at `:1017` / `:1043`.
- All other anchors at the ATTEST-cited lines.

## Expected cross-file dangling references (for downstream plans — NOT failures of this plan)

`forge build` reports ONE error class, by design:
- **`contracts/storage/DegenerusGameStorage.sol:1017` (and `:1043`): `Member "Earlybird" not found … in enum IStakedDegenerusStonk.Pool`.** These are the two `Pool.Earlybird` references inside the DEFERRED `_awardEarlybirdDgnrs` body. The enum was renamed in Task 1 (now `PresaleBox`); the body that still references the old name is deleted by **322-02**. This is the documented consequence of the rename-now / delete-body-later deletion ordering (PLAN Task 2 + SPEC R6). Resolved when 322-02 lands. No other build errors remain after the import fix.

The full build is verified at wave 8 after all 7 plans land.
