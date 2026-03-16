import { ethers } from "ethers";
import {
  predictAddresses,
  computeDeployDayBoundary,
} from "./predictAddresses.js";
import {
  patchContractAddresses,
  restoreContractAddresses,
} from "./patchContractAddresses.js";

// The actual address of `address(this)` inside a forge test's setUp().
// In Foundry 1.5.x, test contracts are deployed at CREATE(DEFAULT_SENDER, 1)
// = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496.
// Note: forge-std's DEFAULT_TEST_CONTRACT (0x5615...) uses a double-nested
// derivation that does NOT match current Foundry behavior.
const FOUNDRY_TEST_CONTRACT =
  "0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496";

// 5 mocks deployed before protocol contracts:
// MockVRFCoordinator, MockStETH, MockLinkToken, MockWXRP, MockLinkEthFeed
const MOCK_COUNT = 5;

// Foundry test contracts start with nonce 1 (EIP-161: contracts start at 1).
// Mocks use nonces 1..5, protocol starts at nonce 6.
const PROTOCOL_START_NONCE = MOCK_COUNT + 1; // = 6

// Fixed deploy timestamp for reproducibility (1 day = 86400 seconds).
// DeployProtocol.sol must vm.warp() to this same value before deploying.
const DEPLOY_TIMESTAMP = 86400;

/**
 * Patch ContractAddresses.sol with predicted addresses for Foundry's
 * DEFAULT_TEST_CONTRACT deployer.
 *
 * @returns {{ predicted, external, dayBoundary, deployTimestamp, FOUNDRY_TEST_CONTRACT, PROTOCOL_START_NONCE }}
 */
export function patchForFoundry() {
  // Compute mock addresses at nonces 1-5
  const mockAddrs = {};
  const mockNames = [
    "MockVRFCoordinator",
    "MockStETH",
    "MockLinkToken",
    "MockWXRP",
    "MockLinkEthFeed",
  ];
  for (let i = 0; i < MOCK_COUNT; i++) {
    const addr = ethers.getCreateAddress({
      from: FOUNDRY_TEST_CONTRACT,
      nonce: i + 1,
    });
    mockAddrs[mockNames[i]] = addr;
  }

  // Predict protocol addresses starting at PROTOCOL_START_NONCE
  const predicted = predictAddresses(
    FOUNDRY_TEST_CONTRACT,
    PROTOCOL_START_NONCE
  );

  // Build external addresses object
  const external = {
    STETH_TOKEN: mockAddrs.MockStETH,
    LINK_TOKEN: mockAddrs.MockLinkToken,
    VRF_COORDINATOR: mockAddrs.MockVRFCoordinator,
    WXRP: mockAddrs.MockWXRP,
    CREATOR: FOUNDRY_TEST_CONTRACT,
  };

  // Compute day boundary from fixed timestamp
  const dayBoundary = computeDeployDayBoundary(DEPLOY_TIMESTAMP);

  // VRF key hash (matches Hardhat test fixture)
  const vrfKeyHash =
    "0xabababababababababababababababababababababababababababababababab";

  // Patch the file
  patchContractAddresses(predicted, external, dayBoundary, vrfKeyHash);

  return {
    predicted,
    external,
    mockAddrs,
    dayBoundary,
    deployTimestamp: DEPLOY_TIMESTAMP,
    FOUNDRY_TEST_CONTRACT,
    PROTOCOL_START_NONCE,
  };
}

export { restoreContractAddresses };

// CLI entry point
const scriptPath = process.argv[1];
if (scriptPath && scriptPath.endsWith("patchForFoundry.js")) {
  const result = patchForFoundry();
  console.log("Foundry ContractAddresses patched:");
  console.log(`  Deployer:       ${result.FOUNDRY_TEST_CONTRACT}`);
  console.log(`  Protocol nonce: ${result.PROTOCOL_START_NONCE}`);
  console.log(`  Day boundary:   ${result.dayBoundary}`);
  console.log(`  Timestamp:      ${result.deployTimestamp}`);
  console.log(
    `  First contract: ${result.predicted.get("ICONS_32")} (ICONS_32)`
  );
  console.log(
    `  Last contract:  ${result.predicted.get("ADMIN")} (ADMIN)`
  );
  console.log(`  Mock VRF:       ${result.mockAddrs.MockVRFCoordinator}`);
  console.log(`  Mock stETH:     ${result.mockAddrs.MockStETH}`);
  console.log(`  Mock LINK:      ${result.mockAddrs.MockLinkToken}`);
  console.log(`  Mock WXRP:      ${result.mockAddrs.MockWXRP}`);
  console.log(`  Mock Feed:      ${result.mockAddrs.MockLinkEthFeed}`);
}
