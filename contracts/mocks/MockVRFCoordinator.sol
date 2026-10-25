// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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
    uint32 public lastCallbackGasLimit;
    bool public lastNativePayment;

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
            // fundSubscription records a synthetic native balance without funding ETH.
            // Distinguish that fixture limitation from an empty/OOG call failure.
            require(address(this).balance >= bal, "mock refund unfunded");
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
        return (0, s.balance, 0, s.owner, s.consumers);
    }

    // --- IVRFCoordinator ---

    bool public requireFunds;
    function requireFundedRequests(bool on) external { requireFunds = on; }

    function requestRandomWords(
        VRFRandomWordsRequest calldata req
    ) external returns (uint256 requestId) {
        if (requireFunds) require(subs[req.subId].balance != 0, "not funded before request");
        require(keccak256(req.extraArgs) == keccak256(hex"92fd13380000000000000000000000000000000000000000000000000000000000000001"), "native payment required");
        lastCallbackGasLimit = req.callbackGasLimit;
        lastNativePayment = true;
        requestId = _nextRequestId++;
        pendingRequests[requestId] = PendingRequest({
            subId: req.subId,
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

    /// @dev Reset the fulfilled flag for a request so it can be reused in multi-day
    ///      test sequences where the game may reuse the same VRF request slot.
    function resetFulfilled(uint256 requestId) external {
        pendingRequests[requestId].fulfilled = false;
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

    function fundSubscriptionWithNative(uint256 subId) external payable {
        require(subs[subId].owner != address(0), "invalid subscription");
        require(msg.value <= type(uint96).max, "oversized funding");
        subs[subId].balance += uint96(msg.value);
    }

    /// @dev Simulate the native bill in lifecycle tests without needing an oracle proof.
    function chargeNative(uint256 subId, uint96 amount) external {
        subs[subId].balance -= amount;
    }

    receive() external payable {}
}
