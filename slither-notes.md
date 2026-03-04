# Slither Analysis Notes

Run: `unset VIRTUAL_ENV && slither . --filter-paths "node_modules|mocks" --exclude naming-convention,solc-version,low-level-calls,assembly,too-many-digits,similar-names,dead-code`

Full JSON report: `slither-report.json`

## Summary: 1788 results

| Impact | Count | Notes |
|--------|-------|-------|
| High | 99 | 89 are uninitialized-state (delegatecall pattern FP) |
| Medium | 234 | Mostly uninitialized-local, divide-before-multiply, reentrancy-no-eth |
| Low | 209 | Informational-grade |
| Informational | 1186 | Style/naming |
| Optimization | 60 | constable-states, immutable-states |

## Known False Positives

### uninitialized-state (89 High)
All DegenerusGameStorage variables. These are inherited by delegatecall modules — storage is written via `delegatecall` from DegenerusGame, so Slither cannot trace the initialization path. This is inherent to the delegatecall module pattern.

### weak-prng (1 High)
`rngWord % (variance * 2 + 1)` in AdvanceModule. The `rngWord` comes from Chainlink VRF — this is a false positive.

### incorrect-exp (1 High)
`otherSlot = slot ^ 1` in DegenerusQuests. This is intentional XOR to toggle between slot 0 and 1, not exponentiation.

### arbitrary-send-eth (3 High)
Payout functions in DegenerusGame and DegenerusVault. These are game payout functions — sending ETH to players is the intended behavior. Access is restricted to valid claim paths.

### reentrancy-eth / reentrancy-balance (5 High)
Cross-function reentrancy via delegatecall modules and stETH interactions. The rngLockedFlag and phase transition flags provide reentrancy protection. External calls to Lido stETH and VRF are to trusted protocol addresses.

## Items Worth Auditor Review

- `divide-before-multiply` (53 Medium) — Potential precision loss in pricing/reward calculations
- `unused-return` (33 Medium) — Unchecked return values on external calls
- `incorrect-equality` (21 Medium) — Strict equality checks that may be fragile
- `reentrancy-no-eth` (49 Medium) — Read-only reentrancy paths to verify
