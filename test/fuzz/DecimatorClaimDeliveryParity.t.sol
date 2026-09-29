// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DecimatorClaimDeliveryParity
/// @notice Pins the value and side-effect parity between the eager single Decimator claim and
///         mineFlip's decimator-leg walk, which defers only its whole Whale Pass units.
contract DecimatorClaimDeliveryParity is DeployProtocol {
    uint256 internal constant SLOT_HEADER = 0;
    uint256 internal constant SLOT_POOLS = 1;
    uint256 internal constant SLOT_DEC_ENTRY = 40;
    uint256 internal constant SLOT_DEC_SUB = 41;
    uint256 internal constant SLOT_DEC_CLAIM_ROUNDS = 42;
    uint256 internal constant SLOT_DEC_OFFSET_PACKED = 43;
    uint256 internal constant SLOT_DEC_CURSOR = 76;
    uint256 internal constant SLOT_PENDING_POOLS_PACKED = 11;

    uint256 internal constant DEC_BASE_UNIT = 1e15;

    uint256 internal constant POOL_FUTURE_SHIFT = 128;
    uint256 internal constant POOL_HALF_MASK = (uint256(1) << 128) - 1;
    uint256 internal constant HALF_PASS_PRICE = 2.25 ether;
    bytes32 internal constant LOOTBOX_OPENED_TOPIC =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes4 internal constant RNG_LOCKED_SELECTOR = bytes4(keccak256("RngLocked()"));

    uint24 internal constant LVL = 50;
    uint8 internal constant DENOM = 2;
    uint8 internal constant WINNING_SUB = 0;
    uint32 internal constant ROUND_WORD = 0xdec1a700;

    address internal winner;
    address internal keeper;

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private _lastFulfilledReqId;

    struct ClaimResult {
        uint256 playerClaimable;
        uint256 claimablePool;
        uint256 futurePool;
        uint256 pendingFuturePool;
        uint256 pendingPasses;
        uint256 mintPacked;
        uint256 seatBalance;
        uint256 flipBalance;
        uint256 flipCredit;
        uint256 dgnrsBalance;
        uint256 wwxrpBalance;
        uint32[100] entries;
    }

    function setUp() public {
        _deployProtocol();
        winner = makeAddr("decimator-delivery-winner");
        keeper = makeAddr("decimator-delivery-keeper");
        // mineFlip's decimator leg only runs once the advance leg is not due and the box legs
        // find nothing pending — drain both so the batch path below reaches the leg cleanly.
        _settleGame(uint256(keccak256("dec-delivery-settle")));
        game.openBoxes(1_000);
        _quietCrapsTable();
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _key(uint24 lvl, uint8 denom, uint8 sub, uint32 position) internal pure returns (uint256) {
        return (uint256(lvl) << 48) | (uint256(denom) << 40) | (uint256(sub) << 32) | uint256(position);
    }

    function _setClaimRound(uint256 amountWei) internal {
        bytes32 slot = keccak256(abi.encode(uint256(LVL), SLOT_DEC_CLAIM_ROUNDS));
        uint256 packed = amountWei | (amountWei << 96) | (uint256(ROUND_WORD) << 224);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev One winning list entry, its subbucket aggregate, the winning-subbucket offset, and the
    ///      settle cursor pointed straight at it, so mineFlip's walk reaches this round directly
    ///      rather than starting its natural walk at level 5.
    function _setWinningBet(uint256 burnWei) internal {
        uint64 weightMilli = uint64(burnWei / DEC_BASE_UNIT);
        bytes32 slot = keccak256(abi.encode(_key(LVL, DENOM, WINNING_SUB, 0), SLOT_DEC_ENTRY));
        uint256 packed = uint256(uint160(winner)) | (uint256(weightMilli) << 160) | (uint256(weightMilli) << 224);
        vm.store(address(game), slot, bytes32(packed));

        uint256 arrBase = uint256(keccak256(abi.encode(uint256(LVL), SLOT_DEC_SUB)));
        bytes32 aggSlot = bytes32(arrBase + uint256(DENOM) * 13 + WINNING_SUB);
        vm.store(address(game), aggSlot, bytes32(burnWei | (uint256(1) << 192)));

        bytes32 offsetSlot = keccak256(abi.encode(uint256(LVL), SLOT_DEC_OFFSET_PACKED));
        vm.store(address(game), offsetSlot, bytes32(uint256(WINNING_SUB)));

        uint256 cursorWord = uint256(LVL) | (uint256(DENOM) << 24);
        vm.store(address(game), bytes32(SLOT_DEC_CURSOR), bytes32(cursorWord));
    }

    function _setClaimablePool(uint128 value) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_POOLS)));
        packed = (packed & type(uint128).max) | (uint256(value) << 128);
        vm.store(address(game), bytes32(SLOT_POOLS), bytes32(packed));
    }

    function _setRngLocked(bool locked) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        uint256 bit = uint256(1) << (19 * 8);
        packed = locked ? packed | bit : packed & ~bit;
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(packed));
    }

    function _setPoolFrozen(bool frozen) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        uint256 bit = uint256(1) << (26 * 8);
        packed = frozen ? packed | bit : packed & ~bit;
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(packed));
    }

    function _pendingFuturePool() internal view returns (uint256) {
        return
            (uint256(vm.load(address(game), bytes32(SLOT_PENDING_POOLS_PACKED))) >> POOL_FUTURE_SHIFT) & POOL_HALF_MASK;
    }

    function _capture() internal view returns (ClaimResult memory result) {
        result.playerClaimable = game.claimableWinningsOf(winner);
        result.claimablePool = game.claimablePoolView();
        result.futurePool = game.futurePrizePoolView();
        result.pendingFuturePool = _pendingFuturePool();
        result.pendingPasses = game.whalePassClaimAmount(winner);
        result.mintPacked = game.mintPackedFor(winner);
        result.seatBalance = afkingSubToken.balanceOf(winner);
        result.flipBalance = coin.balanceOf(winner);
        result.flipCredit = coinflip.coinflipAmount(winner);
        result.dgnrsBalance = dgnrs.balanceOf(winner);
        result.wwxrpBalance = wwxrp.balanceOf(winner);
        for (uint24 i; i < 100; ++i) {
            result.entries[i] = game.entriesOwedView(i + 1, winner);
        }
    }

    function _claimSingle() internal {
        vm.prank(keeper);
        game.claimDecimatorJackpot(LVL, DENOM, 0);
    }

    /// @dev mineFlip's decimator leg, with the box/advance/craps legs already quiet, settles the
    ///      one entry the cursor points at and defers its whole half-pass units.
    function _claimBatch() internal {
        vm.prank(keeper);
        game.mineFlip();
    }

    function _assertEquivalentMaterialization(ClaimResult memory eager, ClaimResult memory deferred) internal pure {
        assertEq(deferred.playerClaimable, eager.playerClaimable, "player ETH credit parity");
        assertEq(deferred.claimablePool, eager.claimablePool, "claimablePool parity");
        assertEq(deferred.futurePool, eager.futurePool, "future pool parity");
        assertEq(deferred.pendingFuturePool, eager.pendingFuturePool, "pending future parity");
        assertEq(deferred.pendingPasses, 0, "deferred pass accumulator consumed");
        assertEq(deferred.mintPacked, eager.mintPacked, "packed pass stats parity");
        assertEq(deferred.seatBalance, eager.seatBalance, "seat parity");
        assertEq(deferred.flipBalance, eager.flipBalance, "FLIP balance parity");
        assertEq(deferred.flipCredit, eager.flipCredit, "FLIP credit parity");
        assertEq(deferred.dgnrsBalance, eager.dgnrsBalance, "DGNRS balance parity");
        assertEq(deferred.wwxrpBalance, eager.wwxrpBalance, "WWXRP balance parity");
        for (uint256 i; i < 100; ++i) {
            assertEq(deferred.entries[i], eager.entries[i], "100-level entry schedule parity");
        }
    }

    function _lootboxOpenedDigest(Vm.Log[] memory logs) internal pure returns (bytes32 digest, uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == LOOTBOX_OPENED_TOPIC) {
                digest = keccak256(abi.encode(logs[i].emitter, logs[i].topics, logs[i].data));
                ++count;
            }
        }
    }

    function _assertRewardBalancesEqual(ClaimResult memory a, ClaimResult memory b) internal pure {
        assertEq(a.playerClaimable, b.playerClaimable, "player ETH credit parity");
        assertEq(a.claimablePool, b.claimablePool, "claimablePool parity");
        assertEq(a.futurePool, b.futurePool, "future pool parity");
        assertEq(a.pendingFuturePool, b.pendingFuturePool, "pending future parity");
        assertEq(a.flipBalance, b.flipBalance, "FLIP balance parity");
        assertEq(a.flipCredit, b.flipCredit, "FLIP credit parity");
        assertEq(a.dgnrsBalance, b.dgnrsBalance, "DGNRS balance parity");
        assertEq(a.wwxrpBalance, b.wwxrpBalance, "WWXRP balance parity");
    }

    function test_SingleMaterializesWhileBatchDefersThenMaterializesEquivalentPass() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        uint256 initialClaimablePool = game.claimablePoolView();
        uint256 initialFuturePool = game.futurePrizePoolView();
        uint256 snap = vm.snapshotState();

        _claimSingle();
        ClaimResult memory eager = _capture();
        assertEq(eager.pendingPasses, 0, "single claim is eager");
        assertEq(eager.seatBalance, 0, "won pass mints no AFKing seat");
        assertEq(eager.playerClaimable, award / 2, "single credits ETH half");
        assertEq(initialClaimablePool - eager.claimablePool, lootboxPortion, "single debits box half");
        assertEq(eager.futurePool - initialFuturePool, lootboxPortion, "single backs future pool");

        assertTrue(vm.revertToState(snap), "restore identical pre-claim state");
        _claimBatch();
        ClaimResult memory pending = _capture();
        assertEq(pending.pendingPasses, halfPasses, "batch defers exact half-pass count");
        assertEq(pending.mintPacked, 0, "batch does not apply pass stats yet");
        assertEq(pending.seatBalance, 0, "batch mints no seat");
        for (uint256 i; i < 100; ++i) {
            assertEq(pending.entries[i], 0, "batch does not queue pass entries yet");
        }
        assertEq(pending.playerClaimable, eager.playerClaimable, "ETH credit already identical");
        assertEq(pending.claimablePool, eager.claimablePool, "claimablePool already identical");
        assertEq(pending.futurePool, eager.futurePool, "future pool already identical");

        uint256 claimableBeforeMaterialize = pending.claimablePool;
        uint256 futureBeforeMaterialize = pending.futurePool;
        game.claimWhalePass(winner);
        ClaimResult memory materialized = _capture();
        _assertEquivalentMaterialization(eager, materialized);
        assertEq(materialized.claimablePool, claimableBeforeMaterialize, "materialization adds no ETH liability");
        assertEq(materialized.futurePool, futureBeforeMaterialize, "materialization moves no pool ETH");
    }

    function test_DustRemainderStaysInFuturePoolAndNeverBecomesEth() public {
        uint256 halfPasses = 3;
        uint256 dust = 0.009 ether;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE + dust;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        uint256 futureBefore = game.futurePrizePoolView();
        uint256 snap = vm.snapshotState();

        vm.recordLogs();
        _claimSingle();
        Vm.Log[] memory singleLogs = vm.getRecordedLogs();
        ClaimResult memory eager = _capture();

        assertTrue(vm.revertToState(snap), "restore identical pre-claim state");
        vm.recordLogs();
        _claimBatch();
        Vm.Log[] memory batchLogs = vm.getRecordedLogs();
        ClaimResult memory deferred = _capture();

        (, uint256 singleBoxes) = _lootboxOpenedDigest(singleLogs);
        (, uint256 batchBoxes) = _lootboxOpenedDigest(batchLogs);
        assertEq(singleBoxes, 0, "dust must not open a lootbox in single claim");
        assertEq(batchBoxes, 0, "dust must not open a lootbox in batch claim");
        assertEq(eager.playerClaimable, award / 2, "single credits only ETH half");
        assertEq(deferred.playerClaimable, award / 2, "batch credits only ETH half");
        assertEq(
            eager.futurePool - futureBefore, lootboxPortion, "single leaves full box half including dust in future pool"
        );
        assertEq(
            deferred.futurePool - futureBefore,
            lootboxPortion,
            "batch leaves full box half including dust in future pool"
        );
        assertEq(eager.pendingPasses, 0, "single materializes whole units");
        assertEq(deferred.pendingPasses, halfPasses, "batch defers only whole units");
        _assertRewardBalancesEqual(eager, deferred);
    }

    function test_ResolvableRemainderHasIdenticalLootboxOutcomeNeverEth() public {
        uint256 halfPasses = 3;
        uint256 remainder = 0.5 ether;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE + remainder;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _claimSingle();
        Vm.Log[] memory singleLogs = vm.getRecordedLogs();
        ClaimResult memory eager = _capture();

        assertTrue(vm.revertToState(snap), "restore identical pre-claim state");
        vm.recordLogs();
        _claimBatch();
        Vm.Log[] memory batchLogs = vm.getRecordedLogs();
        ClaimResult memory deferred = _capture();

        (bytes32 singleDigest, uint256 singleBoxes) = _lootboxOpenedDigest(singleLogs);
        (bytes32 batchDigest, uint256 batchBoxes) = _lootboxOpenedDigest(batchLogs);
        assertEq(singleBoxes, 1, "single resolves exactly one remainder box");
        assertEq(batchBoxes, 1, "batch resolves exactly one remainder box");
        assertEq(batchDigest, singleDigest, "remainder lootbox event must be byte-identical");
        assertEq(eager.playerClaimable, award / 2, "single remainder is not ETH");
        assertEq(deferred.playerClaimable, award / 2, "batch remainder is not ETH");
        assertEq(
            deferred.pendingPasses,
            eager.pendingPasses + halfPasses,
            "only outer whole half-passes differ in delivery timing"
        );
        _assertRewardBalancesEqual(eager, deferred);
    }

    function test_FrozenPoolAccountingMatchesForEagerAndDeferredDelivery() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);
        _setPoolFrozen(true);

        uint256 liveFutureBefore = game.futurePrizePoolView();
        uint256 pendingFutureBefore = _pendingFuturePool();
        uint256 snap = vm.snapshotState();

        _claimSingle();
        ClaimResult memory eager = _capture();
        assertEq(eager.futurePool, liveFutureBefore, "single leaves frozen live future unchanged");
        assertEq(eager.pendingFuturePool - pendingFutureBefore, lootboxPortion, "single credits frozen pending future");

        assertTrue(vm.revertToState(snap), "restore identical pre-claim state");
        _claimBatch();
        ClaimResult memory deferred = _capture();
        assertEq(deferred.futurePool, liveFutureBefore, "batch leaves frozen live future unchanged");
        assertEq(
            deferred.pendingFuturePool - pendingFutureBefore, lootboxPortion, "batch credits frozen pending future"
        );
        assertEq(deferred.pendingPasses, halfPasses, "batch still defers whole units");
        _assertRewardBalancesEqual(eager, deferred);
    }

    /// @notice Under RNG lock, both delivery paths are blocked: the eager claim reverts
    ///         attempting immediate materialization, and mineFlip's decimator leg — gated on
    ///         rngLockedFlag exactly as it is on gameOver and liveness — finds no work at all,
    ///         so it defers nothing either. Once unlocked the walk settles and defers normally,
    ///         and materialization is itself guarded by the same lock independent of how the
    ///         pending units were recorded.
    function test_RngLockBlocksTheClaimAndTheWalkThenGuardsMaterializationAtomically() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);
        _setRngLocked(true);

        ClaimResult memory beforeClaim = _capture();
        vm.expectRevert(RNG_LOCKED_SELECTOR);
        _claimSingle();
        ClaimResult memory afterEagerRevert = _capture();
        _assertRewardBalancesEqual(beforeClaim, afterEagerRevert);
        assertEq(afterEagerRevert.pendingPasses, 0, "failed eager claim creates no pending pass");
        assertEq(afterEagerRevert.mintPacked, 0, "failed eager stats roll back");
        assertEq(afterEagerRevert.seatBalance, 0, "failed eager seat rolls back");

        vm.prank(keeper);
        vm.expectRevert();
        game.mineFlip();
        ClaimResult memory afterWalkRevert = _capture();
        _assertRewardBalancesEqual(beforeClaim, afterWalkRevert);
        assertEq(afterWalkRevert.pendingPasses, 0, "the locked leg records no pending pass either");

        _setRngLocked(false);
        _claimBatch();
        ClaimResult memory pending = _capture();
        assertEq(pending.pendingPasses, halfPasses, "the unlocked walk records exact pending units");
        assertEq(pending.mintPacked, 0, "the walk performs no eager pass writes");
        assertEq(pending.seatBalance, 0, "the walk performs no eager seat mint");

        _setRngLocked(true);
        vm.expectRevert(RNG_LOCKED_SELECTOR);
        game.claimWhalePass(winner);
        ClaimResult memory afterMaterializeRevert = _capture();
        assertEq(afterMaterializeRevert.pendingPasses, halfPasses, "failed materialization preserves pending units");
        assertEq(afterMaterializeRevert.mintPacked, 0, "failed materialization stats roll back");
        assertEq(afterMaterializeRevert.seatBalance, 0, "failed materialization seat rolls back");
        _assertRewardBalancesEqual(pending, afterMaterializeRevert);

        _setRngLocked(false);
        game.claimWhalePass(winner);
        ClaimResult memory materialized = _capture();
        assertEq(materialized.pendingPasses, 0, "unlocked claim consumes pending units");
        assertEq(materialized.seatBalance, 0, "won pass mints no seat on materialization");
        assertTrue(materialized.mintPacked != 0, "unlocked claim applies pass stats");
    }

    function test_SmallClaimsKeepIdenticalDirectLootboxResolution() public {
        uint256 lootboxPortion = 0.5 ether;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _claimSingle();
        Vm.Log[] memory singleLogs = vm.getRecordedLogs();
        ClaimResult memory single = _capture();

        assertTrue(vm.revertToState(snap), "restore identical pre-claim state");
        vm.recordLogs();
        _claimBatch();
        Vm.Log[] memory batchLogs = vm.getRecordedLogs();
        ClaimResult memory batch = _capture();

        (bytes32 singleDigest, uint256 singleBoxes) = _lootboxOpenedDigest(singleLogs);
        (bytes32 batchDigest, uint256 batchBoxes) = _lootboxOpenedDigest(batchLogs);
        assertEq(singleBoxes, 1, "single opens one small box");
        assertEq(batchBoxes, 1, "batch opens one small box");
        assertEq(batchDigest, singleDigest, "small-claim lootbox event parity");
        assertEq(single.pendingPasses, batch.pendingPasses, "small claim creates no outer pass delta");
        _assertRewardBalancesEqual(single, batch);
    }
}
