// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";

/// @dev Mock VRF Coordinator implementing both IVRFCoordinator (requestRandomWords)
///      and IVRFCoordinatorV2_5Owner (createSubscription, addConsumer, etc.)
contract MockVRFCoordinator {
    uint256 private _nextSubId = 1;
    uint256 private _nextRequestId = 1;

    struct Subscription {
        address owner;
        uint96 balance;
        address[] consumers;
    }

    struct PendingRequest {
        uint256 subId;
        address consumer;
        bool fulfilled;
    }

    mapping(uint256 => Subscription) public subs;
    mapping(uint256 => PendingRequest) public pendingRequests;

    // --- IVRFCoordinatorV2_5Owner ---

    function createSubscription() external returns (uint256 subId) {
        subId = _nextSubId++;
        subs[subId].owner = msg.sender;
    }

    function addConsumer(uint256 subId, address consumer) external {
        subs[subId].consumers.push(consumer);
    }

    function cancelSubscription(uint256 subId, address to) external {
        uint96 bal = subs[subId].balance;
        delete subs[subId];
        if (bal > 0) {
            (bool ok, ) = to.call{value: bal}("");
            require(ok);
        }
    }

    function getSubscription(
        uint256 subId
    )
        external
        view
        returns (
            uint96 balance,
            uint96 nativeBalance,
            uint64 reqCount,
            address owner,
            address[] memory consumers
        )
    {
        Subscription storage s = subs[subId];
        return (s.balance, 0, 0, s.owner, s.consumers);
    }

    // --- IVRFCoordinator ---

    function requestRandomWords(
        VRFRandomWordsRequest calldata
    ) external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        pendingRequests[requestId] = PendingRequest({
            subId: 0,
            consumer: msg.sender,
            fulfilled: false
        });
    }

    // --- Test helpers ---

    function fulfillRandomWords(uint256 requestId, uint256 randomWord) external {
        PendingRequest storage req = pendingRequests[requestId];
        require(!req.fulfilled, "already fulfilled");
        req.fulfilled = true;

        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;

        (bool ok, ) = req.consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                words
            )
        );
        require(ok, "VRF callback failed");
    }

    function fulfillRandomWordsRaw(
        uint256 requestId,
        address consumer,
        uint256 randomWord
    ) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        (bool ok, ) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                words
            )
        );
        require(ok, "VRF callback failed");
    }

    function fundSubscription(uint256 subId, uint96 amount) external {
        subs[subId].balance += amount;
    }

    function lastRequestId() external view returns (uint256) {
        return _nextRequestId - 1;
    }

    /// @dev ERC-677 callback: accept LINK funding for a subscription.
    ///      The real Chainlink VRF coordinator implements this to receive LINK.
    /// @param amount Amount of LINK received.
    /// @param data ABI-encoded subscription ID.
    function onTokenTransfer(address, uint256 amount, bytes calldata data) external {
        if (data.length == 32) {
            uint256 subId = abi.decode(data, (uint256));
            subs[subId].balance += uint96(amount);
        }
    }

    receive() external payable {}
}
