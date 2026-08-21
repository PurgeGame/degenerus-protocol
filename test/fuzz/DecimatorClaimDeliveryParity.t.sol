// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DecimatorClaimDeliveryParity
/// @notice Pins the value and side-effect parity between eager single Decimator claims and
///         batch claims that defer only their whole Whale Pass units.
contract DecimatorClaimDeliveryParity is DeployProtocol {
    uint256 internal constant SLOT_HEADER = 0;
    uint256 internal constant SLOT_POOLS = 1;
    uint256 internal constant SLOT_DEC_BURN = 40;
    uint256 internal constant SLOT_DEC_CLAIM_ROUNDS = 42;
    uint256 internal constant SLOT_DEC_OFFSET_PACKED = 43;
    uint256 internal constant SLOT_PENDING_POOLS_PACKED = 11;

    uint256 internal constant POOL_FUTURE_SHIFT = 104;
    uint256 internal constant POOL_HALF_MASK = (uint256(1) << 104) - 1;
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
    }

    function _setClaimRound(uint256 amountWei) internal {
        bytes32 slot = keccak256(abi.encode(uint256(LVL), SLOT_DEC_CLAIM_ROUNDS));
        uint256 packed = amountWei | (amountWei << 96) | (uint256(ROUND_WORD) << 224);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _setWinningBet(uint256 burnWei) internal {
        bytes32 inner = keccak256(abi.encode(uint256(LVL), SLOT_DEC_BURN));
        bytes32 slot = keccak256(abi.encode(winner, uint256(inner)));
        uint256 packed = burnWei | (uint256(DENOM) << 192) | (uint256(WINNING_SUB) << 200);
        vm.store(address(game), slot, bytes32(packed));

        bytes32 offsetSlot = keccak256(abi.encode(uint256(LVL), SLOT_DEC_OFFSET_PACKED));
        vm.store(address(game), offsetSlot, bytes32(uint256(WINNING_SUB)));
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
        game.claimDecimatorJackpot(winner, LVL);
    }

    function _claimBatch() internal {
        address[] memory players = new address[](1);
        players[0] = winner;
        vm.prank(keeper);
        game.claimDecimatorJackpotMany(players, LVL);
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

    function test_RngLockAllowsBatchDeferralButGuardsMaterializationAtomically() public {
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

        _claimBatch();
        ClaimResult memory pending = _capture();
        assertEq(pending.pendingPasses, halfPasses, "batch records exact pending units under lock");
        assertEq(pending.mintPacked, 0, "batch performs no eager pass writes");
        assertEq(pending.seatBalance, 0, "batch performs no eager seat mint");

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
