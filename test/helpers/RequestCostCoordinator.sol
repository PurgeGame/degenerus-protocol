// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";

/// @dev Request-only cost model of Chainlink VRFCoordinatorV2_5 / SubscriptionAPI:
/// https://github.com/smartcontractkit/chainlink-evm/tree/b723176adfe8f2e9eff47730e21a1ac8f64b46d7/contracts/src/v0.8/vrf
/// Preserves the production storage shapes, validation reads, consumer nonce/pending write,
/// fresh commitment, hashes, dynamic extraArgs event and subscription-array return. It does
/// NOT run proof verification or the 300k callback: those belong to the later fulfillment.
/// A configurable execution floor additionally stresses compiler/version/chain overhead;
/// tests use 125k. An independent build of the pinned, unmodified Chainlink contract
/// (solc 0.8.19, optimizer 200, no IR, Paris) measured 41,419 cold request execution gas.
/// Proof verification and fulfillment costs are deliberately outside this request budget.
contract RequestCostCoordinator {
    struct Subscription { uint96 balance; uint96 nativeBalance; uint64 reqCount; }
    struct SubscriptionConfig { address owner; address requestedOwner; address[] consumers; }
    struct ConsumerConfig { bool active; uint64 nonce; uint64 pendingReqCount; }
    struct Config {
        uint16 minimumRequestConfirmations;
        uint32 maxGasLimit;
        bool reentrancyLock;
        uint32 stalenessSeconds;
        uint32 gasAfterPaymentCalculation;
        uint32 fulfillmentFlatFeeNativePPM;
        uint32 fulfillmentFlatFeeLinkDiscountPPM;
        uint8 nativePremiumPercentage;
        uint8 linkPremiumPercentage;
    }
    mapping(address => mapping(uint256 => ConsumerConfig)) private consumers;
    mapping(uint256 => SubscriptionConfig) private subscriptions;
    mapping(uint256 => Subscription) private balances;
    mapping(uint256 => bytes32) public commitments;
    Config private config;
    uint256 private immutable executionFloor;

    event RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed,
        uint256 indexed subId, uint16 minimumRequestConfirmations, uint32 callbackGasLimit,
        uint32 numWords, bytes extraArgs, address indexed sender);

    constructor(uint256 floor) { executionFloor = floor; }

    function seed(address consumer, uint256 count) external {
        config.minimumRequestConfirmations = 3;
        config.maxGasLimit = 2_500_000;
        subscriptions[1].owner = msg.sender;
        balances[1].balance = 100 ether;
        consumers[consumer][1].active = true;
        subscriptions[1].consumers.push(consumer);
        for (uint256 i = 1; i < count; ++i) subscriptions[1].consumers.push(address(uint160(0xD000 + i)));
    }

    function getSubscription(uint256 id) external view
        returns (uint96, uint96, uint64, address, address[] memory)
    {
        require(subscriptions[id].owner != address(0), "subscription");
        Subscription memory s = balances[id];
        return (s.balance, s.nativeBalance, s.reqCount, subscriptions[id].owner, subscriptions[id].consumers);
    }

    function requestRandomWords(VRFRandomWordsRequest calldata req) external returns (uint256 requestId) {
        uint256 start = gasleft();
        require(!config.reentrancyLock, "reentrant");
        require(subscriptions[req.subId].owner != address(0), "subscription");
        ConsumerConfig memory c = consumers[msg.sender][req.subId];
        require(c.active, "consumer");
        require(req.requestConfirmations >= config.minimumRequestConfirmations && req.requestConfirmations <= 200, "confirmations");
        require(req.callbackGasLimit <= config.maxGasLimit && req.numWords <= 500, "limits");
        ++c.nonce;
        ++c.pendingReqCount;
        uint256 preSeed = uint256(keccak256(abi.encode(req.keyHash, msg.sender, req.subId, c.nonce)));
        requestId = uint256(keccak256(abi.encode(req.keyHash, preSeed)));
        // The Game always uses the production empty-extraArgs default: LINK payment.
        require(req.extraArgs.length == 0, "fixture expects LINK default");
        bytes memory extraArgs = abi.encodeWithSelector(bytes4(keccak256("VRF ExtraArgsV1")), false);
        commitments[requestId] = keccak256(abi.encode(requestId, block.number, req.subId,
            req.callbackGasLimit, req.numWords, msg.sender, extraArgs));
        emit RandomWordsRequested(req.keyHash, requestId, preSeed, req.subId, req.requestConfirmations,
            req.callbackGasLimit, req.numWords, extraArgs, msg.sender);
        consumers[msg.sender][req.subId] = c;
        while (start - gasleft() < executionFloor) { }
    }

    function requests(address consumer) external view returns (uint64) { return consumers[consumer][1].nonce; }
}

/// @dev Keep MockStETH's storage/behavior but add a proxy frame and conservative execution
/// overhead for real stETH's pooled-ETH/share reads, conversion, stop check and TransferShares
/// event. The 40k transfer + 10k balanceOf surcharges are separate from coordinator padding.
contract RequestStethEnvelope {
    address private immutable implementation;
    constructor(address target) { implementation = target; }
    fallback() external payable {
        uint256 start = gasleft();
        uint256 extra = msg.sig == bytes4(keccak256("transfer(address,uint256)")) ? 40_000 : 10_000;
        while (start - gasleft() < extra) { }
        address target = implementation;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}
