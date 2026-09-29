// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DecimatorWalkDelivery
/// @notice Pins what mineFlip's decimator walk delivers for one winning entry: the ETH half as
///         claimable, the lootbox half out of claimablePool and into the future pool (the pending
///         buffer while frozen), whole half-pass units deferred to `whalePassClaims`, and any
///         sub-half-pass remainder resolved as one box (or left as future-pool dust below
///         0.01 ETH). Deferred units materialize through claimWhalePass as the same 100-level
///         schedule a bought half-pass queues.
contract DecimatorWalkDelivery is DeployProtocol {
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
        // find nothing pending — drain both so the walk below reaches the leg cleanly.
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

    /// @dev mineFlip's decimator leg, with the box/advance/craps legs already quiet, settles the
    ///      one entry the cursor points at.
    function _walk() internal {
        vm.prank(keeper);
        game.mineFlip();
    }

    function _lootboxOpenedCount(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == LOOTBOX_OPENED_TOPIC) ++count;
        }
    }

    function _assertRewardBalancesEqual(ClaimResult memory a, ClaimResult memory b) internal pure {
        assertEq(a.playerClaimable, b.playerClaimable, "player ETH credit unchanged");
        assertEq(a.claimablePool, b.claimablePool, "claimablePool unchanged");
        assertEq(a.futurePool, b.futurePool, "future pool unchanged");
        assertEq(a.pendingFuturePool, b.pendingFuturePool, "pending future unchanged");
        assertEq(a.flipBalance, b.flipBalance, "FLIP balance unchanged");
        assertEq(a.flipCredit, b.flipCredit, "FLIP credit unchanged");
        assertEq(a.dgnrsBalance, b.dgnrsBalance, "DGNRS balance unchanged");
        assertEq(a.wwxrpBalance, b.wwxrpBalance, "WWXRP balance unchanged");
    }

    function _entryTotal(ClaimResult memory r) internal pure returns (uint256 total) {
        for (uint256 i; i < 100; ++i) total += r.entries[i];
    }

    function test_WalkDefersWholePassesThenMaterializesTheirSchedule() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        uint256 initialClaimablePool = game.claimablePoolView();
        uint256 initialFuturePool = game.futurePrizePoolView();

        _walk();
        ClaimResult memory pending = _capture();
        assertEq(pending.pendingPasses, halfPasses, "walk defers the exact half-pass count");
        assertEq(pending.mintPacked, 0, "walk does not apply pass stats");
        assertEq(pending.seatBalance, 0, "walk mints no seat");
        assertEq(_entryTotal(pending), 0, "walk queues no pass entries");
        assertEq(pending.playerClaimable, award / 2, "walk credits the ETH half");
        assertEq(initialClaimablePool - pending.claimablePool, lootboxPortion, "walk debits the box half");
        assertEq(pending.futurePool - initialFuturePool, lootboxPortion, "walk backs the future pool");

        game.claimWhalePass(winner);
        ClaimResult memory materialized = _capture();
        assertEq(materialized.pendingPasses, 0, "claimWhalePass consumes the deferred units");
        assertTrue(materialized.mintPacked != 0, "claimWhalePass applies pass stats");
        assertEq(materialized.seatBalance, 0, "a won pass mints no seat");
        // A half-pass is 100 entries over the 100 levels from level + 1.
        assertEq(_entryTotal(materialized), halfPasses * 100, "100 entries per half-pass");
        assertEq(materialized.claimablePool, pending.claimablePool, "materialization adds no ETH liability");
        assertEq(materialized.futurePool, pending.futurePool, "materialization moves no pool ETH");
        assertEq(materialized.playerClaimable, pending.playerClaimable, "materialization credits no ETH");
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
        vm.recordLogs();
        _walk();
        uint256 boxes = _lootboxOpenedCount(vm.getRecordedLogs());
        ClaimResult memory r = _capture();

        assertEq(boxes, 0, "dust must not open a lootbox");
        assertEq(r.playerClaimable, award / 2, "only the ETH half becomes claimable");
        assertEq(r.futurePool - futureBefore, lootboxPortion, "the full box half, dust included, stays in future");
        assertEq(r.pendingPasses, halfPasses, "only whole units defer");
    }

    function test_ResolvableRemainderOpensExactlyOneBoxNeverEth() public {
        uint256 halfPasses = 3;
        uint256 remainder = 0.5 ether;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE + remainder;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        vm.recordLogs();
        _walk();
        uint256 boxes = _lootboxOpenedCount(vm.getRecordedLogs());
        ClaimResult memory r = _capture();

        assertEq(boxes, 1, "the remainder resolves as exactly one box");
        assertEq(r.playerClaimable, award / 2, "the remainder is not ETH");
        assertEq(r.pendingPasses, halfPasses, "whole units defer");
    }

    function test_FrozenPoolRoutesTheBoxHalfToPendingFuture() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);
        _setPoolFrozen(true);

        uint256 liveFutureBefore = game.futurePrizePoolView();
        uint256 pendingFutureBefore = _pendingFuturePool();
        _walk();
        ClaimResult memory r = _capture();
        assertEq(r.futurePool, liveFutureBefore, "frozen live future unchanged");
        assertEq(r.pendingFuturePool - pendingFutureBefore, lootboxPortion, "pending future takes the box half");
        assertEq(r.pendingPasses, halfPasses, "whole units still defer");
        assertEq(r.playerClaimable, award / 2, "ETH half credited");
    }

    /// @notice Under the RNG lock the walk settles nothing and records no pending pass. Once
    ///         unlocked it settles and defers normally, and materialization is guarded by the same
    ///         lock on its own.
    function test_RngLockIdlesTheWalkThenGuardsMaterializationAtomically() public {
        uint256 halfPasses = 3;
        uint256 lootboxPortion = halfPasses * HALF_PASS_PRICE;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);
        _setRngLocked(true);

        ClaimResult memory beforeWalk = _capture();
        vm.prank(keeper);
        vm.expectRevert();
        game.mineFlip();
        ClaimResult memory afterLocked = _capture();
        _assertRewardBalancesEqual(beforeWalk, afterLocked);
        assertEq(afterLocked.pendingPasses, 0, "the locked leg records no pending pass");

        _setRngLocked(false);
        _walk();
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

    function test_SmallWinOpensOneBoxAndDefersNothing() public {
        uint256 lootboxPortion = 0.5 ether;
        uint256 award = lootboxPortion * 2;
        _setClaimRound(award);
        _setWinningBet(award);
        _setClaimablePool(100 ether);

        vm.recordLogs();
        _walk();
        uint256 boxes = _lootboxOpenedCount(vm.getRecordedLogs());
        ClaimResult memory r = _capture();
        assertEq(boxes, 1, "a small win opens one box");
        assertEq(r.pendingPasses, 0, "a small win defers no pass");
        assertEq(r.playerClaimable, award / 2, "ETH half credited");
    }
}
