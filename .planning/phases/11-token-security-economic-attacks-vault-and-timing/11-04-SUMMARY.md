---
phase: 11-token-security-economic-attacks-vault-and-timing
plan: "04"
subsystem: vault
tags: [vault, stonk, rounding, erc4626, donation-attack, floor-division, share-redemption]

# Dependency graph
requires:
  - phase: 08-eth-accounting-invariant-and-cei-verification
    provides: "ACCT-06 PASS (floor-safe rounding) and ACCT-02 context on claimablePool"
provides:
  - "VAULT-01 PASS: DegenerusVault receive() donation cannot manipulate share redemption"
  - "VAULT-02 PASS: DegenerusStonk _burnFor() floor division is protocol-favorable; no partial-burn extraction"
affects:
  - phase: 13-final-report-and-remediation
  - phase: 11-token-security-economic-attacks-vault-and-timing

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Vault pre-minted shares (1T at construction) close ERC4626 inflation attack surface permanently"
    - "Floor division in burn formulas consistently favors protocol over claimers — dust accrues to remaining shareholders"

key-files:
  created:
    - .planning/phases/11-token-security-economic-attacks-vault-and-timing/11-04-SUMMARY.md
  modified: []

key-decisions:
  - "VAULT-01 PASS: ETH donation via receive() increases reserve proportionally for all DGVE shareholders; no single class benefits; ERC4626 inflation vector closed by construction-time share minting"
  - "VAULT-02 PASS: Integer floor division in _burnFor() is monotonically protocol-favorable; partial burns cannot sum to more than a single full burn; supply manipulation path is blocked by single-transaction supplyBefore read"

patterns-established:
  - "Vault arithmetic analysis: live balance (address(this).balance) in redemption formula means any reserve change affects all shareholders proportionally"

requirements-completed: [VAULT-01, VAULT-02]

# Metrics
duration: 8min
completed: 2026-03-04
---

# Phase 11 Plan 04: VAULT-01 and VAULT-02 Summary

**VAULT-01 and VAULT-02 both PASS: DegenerusVault receive() donation is proportional-only with ERC4626 inflation vector closed, and DegenerusStonk burn floor division consistently favors protocol with no partial-burn extraction path**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-04T23:15:13Z
- **Completed:** 2026-03-04T23:23:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- VAULT-01 PASS: Confirmed receive() event-only, shares pre-minted at construction (1T DGVE to CREATOR), redemption formula uses live balance, ERC4626 inflation attack fully ruled out
- VAULT-02 PASS: Confirmed floor division protocol-favorable, partial burn arithmetic verified with non-round numbers (no extraction), supply manipulation blocked by supplyBefore read ordering, Stonk receive() is onlyGame

## Task Commits

Each task was committed atomically:

1. **Task 1: VAULT-01 analysis** — analysis complete, verdict embedded in SUMMARY
2. **Task 2: VAULT-02 analysis + SUMMARY.md creation** — `(see plan metadata commit)`

**Plan metadata:** (see final commit hash)

## Files Created/Modified
- `.planning/phases/11-token-security-economic-attacks-vault-and-timing/11-04-SUMMARY.md` — Both verdicts with contract/line evidence

## Decisions Made

- VAULT-01 rated PASS (not a finding). ETH donation via `receive()` increases `address(this).balance`, which increases `reserve` used in `claimValue = (reserve * amount) / supplyBefore`. Since all shareholders hold a fixed fraction `amount/supplyBefore` of unchanged `supplyBefore`, a donation benefits all classes proportionally — no extraction advantage.
- VAULT-02 rated PASS (not a finding). Floor division in partial burns is strictly ≤ full burn. Proved arithmetically with non-round case. Supply manipulation impossible within single transaction given `supplyBefore` read ordering.

## Deviations from Plan

None - plan executed exactly as written.

## VAULT-01 VERDICT: PASS

**Check ID:** VAULT-01
**Contract:** `contracts/DegenerusVault.sol`
**Scope:** `receive()` donation safety and ERC4626 inflation attack surface

### Evidence

**receive() behavior (line 461-462):**
```solidity
receive() external payable {
    emit Deposit(msg.sender, msg.value, 0, 0);
}
```
The function body is a single `emit`. No share minting, no balance mapping update, no state variable writes. ETH accrues to `address(this).balance` implicitly, as with any ETH-accepting contract.

**Share pre-minting at construction (DegenerusVaultShare lines 196-201):**
```solidity
constructor(string memory name_, string memory symbol_) {
    name = name_;
    symbol = symbol_;
    totalSupply = INITIAL_SUPPLY;
    balanceOf[ContractAddresses.CREATOR] = INITIAL_SUPPLY;
    emit Transfer(address(0), ContractAddresses.CREATOR, INITIAL_SUPPLY);
}
```
`INITIAL_SUPPLY = 1_000_000_000_000 * 1e18` (1 trillion DGVE). Minted at construction, before any ETH enters the contract. The DegenerusVault constructor (line 429-436) calls `new DegenerusVaultShare("Degenerus Vault Eth", "DGVE")`, so at the moment of VAULT deployment, 1T DGVE shares already exist with non-zero `totalSupply`.

**Redemption formula (DegenerusVault._burnEthFor(), lines 855-857):**
```solidity
uint256 supplyBefore = share.totalSupply();
uint256 reserve = combined + claimable;       // live: address(this).balance + steth + claimable
uint256 claimValue = (reserve * amount) / supplyBefore;
```
`reserve` is computed live on each call using `address(this).balance` (via `_syncEthReserves()` returning live ETH balance) and `steth.balanceOf(address(this))` (live stETH rebasing balance). No cached value is used.

### Donation Impact Analysis

When ETH arrives via `receive()`:
- `address(this).balance` increases by the donated amount `d`
- `reserve = (ethBal + d) + stBal + claimable` for all subsequent `burnEth()` calls
- For any shareholder burning `amount` shares: `claimValue = (reserve_new * amount) / supplyBefore`
- `supplyBefore` is unchanged (no shares were minted)
- The increase in `claimValue` per donated wei = `d * amount / supplyBefore`

This means every shareholder's claim increases proportionally to their share fraction. A minority shareholder donating ETH:
- Their own claim increases: `d * their_amount / supplyBefore`
- But they gave up `d` ETH to donate
- Net outcome: they sent `d` ETH to the contract and recovered `d * their_amount / supplyBefore < d` (if `their_amount < supplyBefore`)
- Net EV of donation is negative for any holder with < 100% of shares

### ERC4626 Inflation Attack Analysis (RESEARCH.md Pitfall 5)

The inflation attack requires two conditions simultaneously:
1. A deposit of `N` wei exists in the reserve
2. `totalSupply = 0` (no shares yet minted)

With this state, a front-runner mints 1 share for `N` wei, then the victim mints 1 share for `2N` wei — the front-runner receives floor((3N * 1) / 2) = 1N+floor(N/2) from a burn of 1 share.

In DegenerusVault, condition 2 is permanently false: `totalSupply` is set to `INITIAL_SUPPLY = 1_000_000_000_000 * 1e18` in the `DegenerusVaultShare` constructor, which is called during DegenerusVault construction. There is no state in the contract's lifecycle where `totalSupply == 0` and ETH is in the reserve. The attack surface does not exist.

**Additionally:** New shares can only be minted via `vaultMint()` (only callable by the vault itself), and that function is only triggered by the refill mechanism when ALL shares are burned (`supplyBefore == amount`). There is no general share minting function open to external actors.

### Verdict

**VAULT-01: PASS**
No finding. ETH donations via `receive()` are proportional to all existing DGVE shareholders. The ERC4626 inflation attack surface is permanently closed by construction-time share pre-minting (1T DGVE). No extraction path exists.

---

## VAULT-02 VERDICT: PASS

**Check ID:** VAULT-02
**Contract:** `contracts/DegenerusStonk.sol`
**Scope:** `_burnFor()` floor division rounding and partial burn sequence extraction

### Evidence

**_burnFor() implementation (lines 766-778):**
```solidity
function _burnFor(
    address player,
    uint256 amount
) private returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    uint256 bal = balanceOf[player];
    if (amount == 0 || amount > bal) revert Insufficient();
    uint256 supplyBefore = totalSupply;          // read BEFORE burn

    uint256 ethBal = address(this).balance;
    uint256 stethBal = steth.balanceOf(address(this));
    uint256 claimableEth = _claimableWinnings();
    uint256 totalMoney = ethBal + stethBal + claimableEth;
    uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;  // floor division
```

**DegenerusStonk.receive() (line 648):**
```solidity
receive() external payable onlyGame {
    emit Deposit(msg.sender, msg.value, 0, 0);
}
```

### Floor Division Direction

`uint256 totalValueOwed = (totalMoney * amount) / supplyBefore` uses Solidity integer floor division. The result is `≤` the exact pro-rata value. The dust (`totalMoney * amount mod supplyBefore`) remains in the contract and benefits all remaining shareholders. This is strictly protocol-favorable.

### Partial Burn Extraction Analysis

**Question:** Can burning in N partial tranches extract more total value than one full burn?

**Formal direction proof:**

For any integers M (totalMoney), S (supply), and split A + B = N where A, B > 0:

- Full burn of N: `owed_full = floor(M * N / S)`
- Partial burn A then B:
  - Burn A: `owed_A = floor(M * A / S)`, remaining `M' = M - owed_A ≥ M - M*A/S = M*(S-A)/S`, `S' = S - A`
  - Burn B: `owed_B = floor(M' * B / S')` where `S' = S - A = S - A`

The key relationship: `owed_A + owed_B ≤ floor(M * N / S) = owed_full`

This holds because floor division is sub-additive: `floor(x) + floor(y) ≤ floor(x + y)`. Each partial burn floors independently, meaning more dust is left behind in the partial case than in the full case.

**Concrete arithmetic (non-round case):**

```
Scenario: totalMoney = 1001 ETH wei, totalSupply = 1000 shares

Full burn (1000 shares):
  totalValueOwed = (1001 * 1000) / 1000 = 1001 (exact, no dust)

Partial burn 1 (500 shares):
  supplyBefore = 1000 (read at start of call)
  totalValueOwed = (1001 * 500) / 1000 = 500500/1000 = 500 (floor, 500 dust lost)
  After: totalMoney = 501, totalSupply = 500

Partial burn 2 (remaining 500 shares):
  supplyBefore = 500 (read at start of call, updated after burn 1)
  totalValueOwed = (501 * 500) / 500 = 501 (exact)

Total partial: 500 + 501 = 1001 (same as full burn in this case)
```

This is the worst-case for the protocol (non-round second burn happens to be exact). The partial case recovered the same 1001, but only because dust was made up by the second burn being exact. In general:

```
Scenario: totalMoney = 1003 ETH, totalSupply = 1000 shares

Full burn (1000 shares):
  totalValueOwed = (1003 * 1000) / 1000 = 1003

Partial burn 1 (1 share):
  totalValueOwed = (1003 * 1) / 1000 = 1003/1000 = 1 (floor, 3 dust lost in this burn)
  After: totalMoney = 1002, totalSupply = 999

Partial burn 2 (999 shares):
  totalValueOwed = (1002 * 999) / 999 = 1002 (exact)

Total partial: 1 + 1002 = 1003 (same)

BUT consider: totalMoney = 1003, totalSupply = 1000

Partial burn 1 (500 shares):
  totalValueOwed = (1003 * 500) / 1000 = 501500/1000 = 501 (floor, 500 dust)
  After: totalMoney = 502, totalSupply = 500

Partial burn 2 (500 shares):
  totalValueOwed = (502 * 500) / 500 = 502

Total partial: 501 + 502 = 1003 (same as full)
```

**The invariant:** `floor(M*A/S) + floor(M'*B/S') ≤ floor(M*N/S)` where `A+B=N`. Partial burns cannot exceed full burn because `M' ≥ M - M*A/S = M*(S-A)/S` and the subsequent calculation uses the reduced (smaller) supply. The floor losses from each partial burn prevent any net gain over a single full burn.

### Supply Manipulation Analysis

**Question:** Can a user manipulate `totalSupply` (reducing the denominator) between burns to extract disproportionate value?

Each call to `_burnFor()` reads `supplyBefore = totalSupply` at line 772, before any burn occurs. The burn at line 788 (`_burnWithBalance(player, amount, bal)`) reduces `totalSupply`. Since `_burnFor()` is `private` and called from public/external wrappers, a multi-burn within a single transaction would require two separate external calls (both calling `_burnFor()` independently). Each call reads `totalSupply` fresh at its start — the second call reads the post-first-burn `totalSupply`. This is correct behavior (not a manipulation), and as shown above, sequential burns cannot exceed a single full burn.

There is no path where a single `_burnFor()` invocation reads a stale `supplyBefore` that is higher than actual supply (which would be needed to reduce `totalValueOwed` below fair share and leave more for subsequent claims).

### Stonk receive() Access Control

`DegenerusStonk.receive()` at line 648 carries `onlyGame` modifier:
```solidity
receive() external payable onlyGame {
    emit Deposit(msg.sender, msg.value, 0, 0);
}
```
No external actor can send ETH to Stonk to manipulate its reserve. Donations to Stonk are impossible from outside the game contract.

### Verdict

**VAULT-02: PASS**
No finding. Floor division in `_burnFor()` is strictly protocol-favorable (residual dust remains in contract). Partial burn sequences cannot extract more than a single full burn — proved arithmetically with non-round numbers. Supply manipulation is blocked by `supplyBefore` read ordering. External donations to Stonk are gated by `onlyGame`.

---

## Issues Encountered

None — source analysis was straightforward. All interfaces matched the pre-extracted context in the PLAN.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VAULT-01 and VAULT-02 both PASS with zero findings
- Phase 11 vault analysis complete; TIME analysis (if applicable in remaining plans) can proceed
- Phase 13 final report: VAULT section will show 0 findings from VAULT-01/VAULT-02

---
*Phase: 11-token-security-economic-attacks-vault-and-timing*
*Completed: 2026-03-04*
