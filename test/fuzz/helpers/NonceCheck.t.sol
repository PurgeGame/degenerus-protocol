// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

/// @dev Trivial contract for nonce increment testing
contract Dummy {}

/// @title NonceCheck - Empirical validation of Foundry deployer nonce
/// @notice Confirms the starting nonce and deployer identity for address prediction
contract NonceCheck is Test {
    uint256 startNonce;

    function setUp() public {
        startNonce = vm.getNonce(address(this));
    }

    function test_startingNonce() public view {
        // EIP-161: contract accounts start with nonce 1
        assertEq(startNonce, 1, "Starting nonce should be 1 (EIP-161)");
    }

    function test_deployerIsTestContract() public view {
        // In Foundry 1.5.x, test contracts are at CREATE(DEFAULT_SENDER, 1)
        // = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
        assertEq(
            address(this),
            0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496,
            "Test contract should be CREATE(DEFAULT_SENDER, 1)"
        );
    }

    function test_nonceIncrements() public {
        uint256 nonceBefore = vm.getNonce(address(this));
        new Dummy();
        uint256 nonceAfter = vm.getNonce(address(this));
        assertEq(nonceAfter, nonceBefore + 1, "Nonce should increment by 1 after deploy");
    }
}
