---
phase: 14-foundry-infrastructure-and-compiler-alignment
plan: 02
status: complete
started: "2026-03-05"
completed: "2026-03-05"
---

# Summary: Address Prediction Script (14-02)

## What was done

1. **Created patchForFoundry.js**: Predicts all 22 protocol + 5 mock contract addresses for Foundry's test EVM deployer, patches ContractAddresses.sol, and supports a clean restore cycle.

2. **Discovered Foundry 1.5.x addressing change**: The research notes indicated `DEFAULT_TEST_CONTRACT = 0x5615...` but empirical testing showed the actual test contract address is `0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496` = `CREATE(DEFAULT_SENDER, 1)`. Foundry 1.5.x deploys test contracts directly, not through a double-nested chain.

3. **Created NonceCheck.t.sol**: Validates nonce starts at 1 (EIP-161), deployer matches expected address, and nonce increments correctly on deploy.

## Key deviation

The plan specified `FOUNDRY_TEST_CONTRACT = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f` from forge-std's StdConstants. Empirical testing proved the actual address is `0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496`. This was exactly the kind of issue the nonce validation task was designed to catch.

## Results

- Patch: 0 `address(0)` entries (all 27 addresses patched)
- Restore: 27 `address(0)` entries (all addresses back to zero)
- NonceCheck: 3/3 tests pass (nonce=1, deployer=0x7FA9..., increment works)

## Key files

- `scripts/lib/patchForFoundry.js` -- Address prediction and patching
- `test/fuzz/helpers/NonceCheck.t.sol` -- Nonce empirical validation

## Commits

- `0c3580b` feat(14-02): address prediction script and nonce validation

## Self-Check: PASSED

- [x] patchForFoundry.js predicts correct Foundry deployer nonces and patches ContractAddresses.sol
- [x] Predicted addresses match CREATE address math for the actual test contract deployer
- [x] Patch-restore cycle is non-destructive
- [x] Nonce starting value empirically confirmed
