---
phase: 08-eth-accounting-invariant-and-cei-verification
plan: "03"
subsystem: audit
tags: [solidity, vault, rounding, BurnieCoin, supply-invariant, security]

# Dependency graph
requires: []
provides:
  - ACCT-06 verdict: DegenerusVault share redemption rounding
  - ACCT-07 verdict: BurnieCoin supply invariant and mint path enumeration
affects: ["phase-13-report"]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/08-eth-accounting-invariant-and-cei-verification/08-03-SUMMARY.md
  modified: []

key-decisions:
  - "ACCT-06: PASS — vault redemption formula floors toward zero (favors protocol), partial-burn extraction yields no surplus, 1T refill is atomic"
  - "ACCT-07: PASS — BurnieCoin supply invariant totalSupply + vaultAllowance == supplyIncUncirculated holds; all mint paths enumerated and authorized; packed struct ensures atomic update"

patterns-established:
  - "Vault rounding convention: (reserve * amount) / supply always floors — claimer receives less than exact proportional share, protocol retains dust"
  - "BurnieCoin supply accounting: _mint to VAULT routes to vaultAllowance (not totalSupply); _burn from VAULT routes from vaultAllowance — invariant maintained by construction"

requirements-completed:
  - ACCT-06
  - ACCT-07

# Metrics
duration: 20min
completed: 2026-03-04
---

# Phase 08-03: Vault Rounding and BurnieCoin Supply Invariant Summary

**ACCT-06 and ACCT-07 both PASS — vault redemption rounds down (protocol-safe), partial-burn yields no surplus, BurnieCoin supply invariant is maintained by construction via packed struct with special VAULT routing in _mint/_burn.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-03-04T00:50:00Z
- **Completed:** 2026-03-04T01:10:00Z
- **Tasks:** 3 completed
- **Files modified:** 1

## Accomplishments

- Verified vault `(reserve * sharesBurned) / totalSupply` rounding direction: floors (safe)
- Confirmed partial-burn extraction scenario yields no surplus (algebraic proof)
- Confirmed 1T refill is atomic with the last burn — no race condition window
- Enumerated all BurnieCoin mint paths: 6 paths, all authorized
- Verified `_supply` packed struct: `_mint(to=VAULT)` routes to `vaultAllowance`; `vaultMintTo` routes from `vaultAllowance` to `totalSupply` — invariant preserved by construction
- Produced ACCT-06 and ACCT-07 verdicts: both PASS

## ACCT-06 Verdict

**ACCT-06**: PASS — `(reserve * sharesBurned) / totalSupply` floors toward zero (Solidity integer division); claimers receive less than exact proportional share; partial-burn sequence yields same or fewer tokens than single full burn; 1T refill is atomic with last burn step. [DegenerusVault.sol:779, 857]

## ACCT-07 Verdict

**ACCT-07**: PASS — `totalSupply + vaultAllowance == supplyIncUncirculated` holds at all times; all 6 mint paths have authorization guards; `_supply` packed struct ensures single-slot atomic write; no free-mint path exists. [BurnieCoin.sol:468-481, 657-686]

## Vault Rounding Direction

**Formula** (lines 779 and 857 of DegenerusVault.sol):
```
coinOut = (coinBal * amount) / supplyBefore    // DGVB redemption
claimValue = (reserve * amount) / supplyBefore  // DGVE redemption
```

Solidity integer division truncates toward zero. For positive operands (all guaranteed by function guards), this means **floor division**:
- `claimValue < (reserve * amount) / supplyBefore` whenever `reserve * amount` is not divisible by `supplyBefore`
- The rounding remainder stays in the reserve — the protocol retains fractional dust
- **Rounding direction: SAFE** — claimer receives less than exact share

**Deposit formula** (line 450 `deposit()`, no share issuance formula in DegenerusVault.sol):
- `deposit()` accepts ETH/stETH but does not issue shares directly — shares are issued during construction (1T initial supply) and via the refill mechanism
- The vault does not implement a deposit-proportional share issuance; existing shares represent proportional ownership of accumulated deposits
- No inflation attack possible from deposit rounding

## Partial-Burn Extraction Scenario

Consider: `B` = reserve, `N` = totalSupply (assuming no other activity).

**Single full burn**: `claimValue = floor(B * N / N) = B` (exact, no rounding loss)

**Two partial burns** (burn N/2 each time):
- Round 1: `c1 = floor(B * (N/2) / N) = floor(B/2)`. Rounding loss: `ε1 = B/2 - floor(B/2)` (0 if B even, 0 or 1 wei)
- After round 1: reserve = `B - c1 = B - floor(B/2) = ceil(B/2)`, supply = `N/2`
- Round 2: `c2 = floor(ceil(B/2) * (N/2) / (N/2)) = ceil(B/2)` (exact)
- Total: `c1 + c2 = floor(B/2) + ceil(B/2) = B` — same as full burn

**Result**: Two-step partial burn yields the **same** total as a single full burn (due to ceiling property of the remaining reserve after round 1). No surplus extraction.

For more than two steps, each subsequent burn gets the exact remaining reserve (since `sharesBurned == totalSupply` at the last step). Total is always `≤ B`. No extraction.

## 1T Refill Mechanism

The refill occurs at `DegenerusVault.sol:782-784` (DGVB) and `874-876` (DGVE):
```solidity
share.vaultBurn(player, amount);
if (supplyBefore == amount) {
    share.vaultMint(player, REFILL_SUPPLY);  // REFILL_SUPPLY = 1T * 1e18
}
```

**Atomicity**: burn and refill happen in the same transaction, same call frame. No window between the burn and the refill where `totalSupply == 0` is visible to another caller.

**Refill share inflation**: The refill mints 1T shares to the last burner. The reserve at that point is whatever dust remains after the floor-rounded redemption. Any subsequent depositor would receive proportional shares. The 1T receiver has a claim on `(reserve * newBurn) / newSupply` for future redemptions — no disproportionate advantage over the initial 1T supply distribution.

## DegenerusVault `receive()` (Out-of-Scope for ACCT-06)

Line 461-463: `receive() external payable { emit Deposit(msg.sender, msg.value, 0, 0); }` — Direct ETH donations emit an event but do NOT update any reserve tracking. Since `_syncEthReserves()` in `_burnEthFor` reads `address(this).balance` directly (line 846), a direct ETH donation DOES increase the vault's ETH reserve, benefiting existing DGVE shareholders proportionally. This is a VAULT-01 concern (Phase 11 scope), not ACCT-06.

## BurnieCoin Supply Invariant

**Documented invariant** (BurnieCoin.sol:262):
```
totalSupply + vaultAllowance = supplyIncUncirculated
```
Implemented as `supplyIncUncirculated()` at line 321-322:
```solidity
return uint256(_supply.totalSupply) + uint256(_supply.vaultAllowance);
```

**Packed struct** (`_supply`, lines 194-202): `uint128 totalSupply + uint128 vaultAllowance` fits in one 32-byte slot. Any update writes both fields atomically in one SSTORE.

## BurnieCoin Mint Paths (All Enumerated)

| # | Function | Authorization | Effect on `_supply` | Notes |
|---|----------|---------------|---------------------|-------|
| 1 | `mintForCoinflip(to, amount)` (line 526) | `coinflipContract` only | `totalSupply += amount` (or `vaultAllowance += amount` if to==VAULT) | Called by BurnieCoinflip on coinflip wins |
| 2 | `mintForGame(to, amount)` (line 535) | `ContractAddresses.GAME` only | `totalSupply += amount` | Called by DegenerusGame for Degenerette wins etc. |
| 3 | `creditCoin(player, amount)` (line 545) | `onlyFlipCreditors` (GAME or AFFILIATE) | `totalSupply += amount` | Direct BURNIE credit |
| 4 | `vaultEscrow(amount)` (line 657) | GAME or VAULT only | `vaultAllowance += amount` (no `totalSupply` change) | Virtual deposit — increases uncirculated allowance only |
| 5 | `vaultMintTo(to, amount)` (line 674) | `onlyVault` | `vaultAllowance -= amount`, `totalSupply += amount` | Converts vault allowance to circulating supply — net effect on `supplyIncUncirculated` is zero |
| 6 | `_mint(to=VAULT, amount)` (line 471-476) | Internal — called only by above paths | `vaultAllowance += amount` | Routes to allowance when recipient is VAULT |

**Invariant preservation per path**:
- Paths 1-3: `totalSupply += X`, `vaultAllowance` unchanged → `supplyIncUncirculated += X` ✓
- Path 4: `vaultAllowance += X`, `totalSupply` unchanged → `supplyIncUncirculated += X` ✓
- Path 5: `vaultAllowance -= X`, `totalSupply += X` → `supplyIncUncirculated` unchanged ✓ (conversion, not mint)
- Path 6 (to=VAULT): `vaultAllowance += X` → same as path 4 ✓

**Burn paths** (symmetric):
- `_burn(from, amount)` for normal addresses: `totalSupply -= amount` → `supplyIncUncirculated -= amount` ✓
- `_burn(from=VAULT, amount)`: `vaultAllowance -= amount` → `supplyIncUncirculated -= amount` ✓

No free-mint path exists. All paths require either `GAME`, `AFFILIATE`, `coinflipContract`, or `VAULT` authorization.

## Task Commits

1. **Task 1: Verify DegenerusVault share redemption rounding** — audit analysis (no code changes)
2. **Task 2: Verify BurnieCoin supply invariant and mint paths** — audit analysis (no code changes)
3. **Task 3: Write 08-03-SUMMARY.md** — committed as `docs(08-03): ACCT-06 ACCT-07 verdicts — both PASS`

## Files Created/Modified

- `.planning/phases/08-eth-accounting-invariant-and-cei-verification/08-03-SUMMARY.md` — This file

## Decisions Made

- ACCT-06: PASS — floor rounding confirmed safe; no partial-burn extraction; refill atomic
- ACCT-07: PASS — invariant maintained by construction via packed struct and VAULT-routing in _mint/_burn

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

ACCT-06 and ACCT-07 are complete. No vault rounding exploits or BurnieCoin supply manipulation paths found. Phase 11 (VAULT-01) should investigate the `receive()` donation behavior for DGVE share dilution concerns.

---
*Phase: 08-eth-accounting-invariant-and-cei-verification*
*Completed: 2026-03-04*
