---
phase: 14-foundry-infrastructure-and-compiler-alignment
plan: 03
status: complete
started: "2026-03-05"
completed: "2026-03-05"
---

# Summary: Full Protocol Deployment and Canary Test (14-03)

## What was done

1. **Created DeployProtocol.sol**: Abstract contract that deploys all 5 mocks + 22 protocol contracts in correct nonce order. Uses `vm.warp(86400)` to match patchForFoundry.js fixed timestamp. Handles BurnieCoinflip (4 constructor args from ContractAddresses) and DegenerusAffiliate (5 empty arrays).

2. **Created DeployCanary.t.sol**: Two tests -- `test_allAddressesMatch()` asserts all 27 deployed addresses match their ContractAddresses constants, `test_protocolWired()` confirms constructor side effects (VRF subscription created, all key contracts deployed).

3. **Created Makefile**: `invariant-test` target runs the full patch-build-test-restore cycle with restore-on-failure safety. Also provides `invariant-build` and `invariant-clean` targets.

## Results

- `make invariant-test`: 26 tests passed, 0 failed across 5 suites
- All 22 protocol + 5 external address assertions pass
- Constructor side effects confirmed: Admin has VRF subscription, all contracts deployed
- ContractAddresses.sol correctly restored after test run

## Key files

- `test/fuzz/helpers/DeployProtocol.sol` -- Abstract deployment base
- `test/fuzz/DeployCanary.t.sol` -- Address and wiring canary tests
- `Makefile` -- Automation targets

## Commits

- `e93a484` feat(14-03): full protocol deployment and canary test for Foundry

## Self-Check: PASSED

- [x] DeployProtocol.sol deploys all 5 mocks + 22 protocol contracts
- [x] Every deployed address matches its ContractAddresses constant
- [x] Constructor side effects execute correctly (VRF subscription, vault, stonk)
- [x] make invariant-test automates the full patch-build-test-restore cycle
- [x] ContractAddresses.sol restored to address(0) state after test
