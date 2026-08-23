// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

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
