// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Request structure for Chainlink VRF V2.5 Plus.
/// @dev Matches VRFV2PlusClient.RandomWordsRequest for real Chainlink VRF V2.5 Plus coordinator.
struct VRFRandomWordsRequest {
    bytes32 keyHash;
    uint256 subId;
    uint16 requestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
    bytes extraArgs;
}

/// @notice Interface for Chainlink VRF Coordinator.
interface IVRFCoordinator {
    function requestRandomWords(
        VRFRandomWordsRequest calldata request
    ) external returns (uint256);

    function getSubscription(
        uint256 subId
    )
        external
        view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers);
}
