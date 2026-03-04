// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title VRF Random Words Request
/// @notice Request structure for Chainlink VRF V2.5 Plus
/// @dev Matches VRFV2PlusClient.RandomWordsRequest for Chainlink VRF V2.5 Plus coordinator
struct VRFRandomWordsRequest {
    /// @notice The gas lane key hash value for the VRF job
    bytes32 keyHash;
    /// @notice The VRF subscription ID
    uint256 subId;
    /// @notice Number of block confirmations before fulfillment
    uint16 requestConfirmations;
    /// @notice Gas limit for the fulfillRandomWords callback
    uint32 callbackGasLimit;
    /// @notice Number of random words to request
    uint32 numWords;
    /// @notice Extra arguments for the request (e.g., native payment flag)
    bytes extraArgs;
}

/// @title IVRFCoordinator
/// @notice Interface for Chainlink VRF V2.5 Plus Coordinator
/// @dev Used to request verifiable random numbers from Chainlink oracles
interface IVRFCoordinator {
    /// @notice Requests random words from the VRF coordinator
    /// @param request The VRF request parameters
    /// @return requestId The unique ID for this randomness request
    function requestRandomWords(
        VRFRandomWordsRequest calldata request
    ) external returns (uint256);

    /// @notice Retrieves subscription details
    /// @param subId The subscription ID to query
    /// @return balance The LINK token balance of the subscription
    /// @return nativeBalance The native token balance of the subscription
    /// @return reqCount The number of requests made by this subscription
    /// @return owner The owner address of the subscription
    /// @return consumers The list of consumer contract addresses
    function getSubscription(
        uint256 subId
    )
        external
        view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers);
}
