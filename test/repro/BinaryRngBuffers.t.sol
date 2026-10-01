// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";

/// @dev Observe the real request boundary, including a reentrant request attempt.
contract CompletionCheckingCoordinator {
    DegenerusGame private immutable game;
    constructor(DegenerusGame game_) { game = game_; }
    function getSubscription(uint256) external pure returns (uint96, uint96, uint64, address, address[] memory) {
        return (1000 ether, 0, 0, address(0), new address[](0));
    }
    function requestRandomWords(VRFRandomWordsRequest calldata) external returns (uint256) {
        require(!game.rngComplete(), "completion remained true during request");
        try game.requestLootboxRng() { revert("nested fresh request was accepted"); }
        catch (bytes memory reason) {
            require(bytes4(reason) == bytes4(keccak256("RngNotReady()")), "nested request reached another gate");
        }
        return 90001;
    }
}

contract BinaryRngBuffersTest is DeployProtocol {
    address buyer = address(0xB011);
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(buyer, 1000 ether); vm.deal(address(game), 5000 ether);
        mockVRF.fundSubscription(1, 1000 ether);
        uint24 today = game.currentDayView();
        for (uint256 i; i < 1024; ++i) {
            if (uint24(uint256(game.extsload(bytes32(0))) >> 24) == today && !game.rngLocked()) break;
            game.mineFlip();
            if (game.rngLocked() && !game.isRngFulfilled()) mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB0B5);
        }
        _finishReadConsumers();
        assertTrue(game.rngComplete(), "real initial day and read queues completed");
        vm.prank(address(admin)); game.creditMiddayRng(buyer, 100 ether);
        vm.fee(0);
    }
    function _buy() private {
        vm.prank(buyer);
        game.purchase{value: 1 ether}(buyer, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(buyer);
        game.placeDegeneretteBet{value: 0.005 ether}(buyer, 0, uint128(0.005 ether), 1, uint8(9));
    }
    function _request() private returns(uint256 id) {
        uint256 old = mockVRF.lastRequestId(); vm.prank(buyer); game.requestLootboxRng();
        id = mockVRF.lastRequestId(); assertGt(id, old, "fresh production request");
    }
    function _assertNextRequestBlocked(uint256 id) private {
        bytes32 state = game.extsload(bytes32(0));
        uint256 credit = game.middayRngCredits(buyer);
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        assertEq(game.extsload(bytes32(0)), state, "blocked request changed session state");
        assertEq(game.middayRngCredits(buyer), credit, "blocked request charged donor");
        assertEq(mockVRF.lastRequestId(), id, "blocked request reached coordinator");
    }
    function test_CompletionGateRejectsPendingDeliveredAndUnsettledSessions() public {
        _buy();
        uint256 id = _request();
        _assertNextRequestBlocked(id);
        mockVRF.fulfillRandomWords(id, 42);
        _assertNextRequestBlocked(id);
        game.advanceGame(); // Publication leaves the actual box/bet consumers outstanding.
        assertFalse(game.rngComplete());
        _assertNextRequestBlocked(id);
        for (uint256 i; i < 1024 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete());
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 128 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "next daily request holds the lock");
        _assertNextRequestBlocked(mockVRF.lastRequestId());
    }
    function test_MiddaySealInvalidatesCompletionBeforeCoordinatorCall() public {
        _buy();
        CompletionCheckingCoordinator observer = new CompletionCheckingCoordinator(game);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(observer), 1, bytes32(uint256(1)));
        vm.prank(buyer); game.requestLootboxRng();
        assertFalse(game.rngComplete());
        assertEq(uint256(game.extsload(bytes32(uint256(4)))), 90001);
    }
    function test_CoordinatorFailureRollsBackSealAndCredit() public {
        _buy();
        bytes32 state = game.extsload(bytes32(0));
        bytes32 cursor = game.extsload(bytes32(uint256(33)));
        uint256 credit = game.middayRngCredits(buyer);
        uint256 id = mockVRF.lastRequestId();
        vm.mockCallRevert(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector), "coordinator unavailable");
        vm.prank(buyer); vm.expectRevert(bytes("coordinator unavailable")); game.requestLootboxRng();
        assertEq(game.extsload(bytes32(0)), state, "failed request changed buffer or completion");
        assertEq(game.extsload(bytes32(uint256(33))), cursor, "failed request changed pending commitments");
        assertEq(game.middayRngCredits(buyer), credit);
        assertEq(mockVRF.lastRequestId(), id);
    }
    function test_EightSessionsReuseTwoBuffersWithoutLeakingOrdersOrBets() public {
        for (uint256 cycle; cycle < 8; ++cycle) {
            uint48 write = RecyclingState.writeBuffer(address(game));
            assertEq(uint256(game.extsload(keccak256(abi.encode(write, uint256(57))))), 0, "write boxes header reset");
            assertEq(uint256(game.extsload(keccak256(abi.encode(write, uint256(21))))), 0, "write bets header reset");
            _buy();
            uint256 id = _request();
            assertEq(RecyclingState.readBuffer(address(game)), write);
            assertEq(RecyclingState.writeBuffer(address(game)), write ^ 1);
            assertEq(uint48(uint256(game.extsload(bytes32(uint256(33))))), 0, "no increasing epoch counter");
            assertFalse(game.rngComplete()); assertEq(RecyclingState.currentWord(address(game)), 0);
            mockVRF.fulfillRandomWords(id, cycle + 42);
            assertFalse(game.rngComplete(), "delivery cannot skip settlement");
            // All producers now bind the other buffer, even while the read word exists.
            if (cycle == 0) {
                _buy();
                assertEq(uint256(game.extsload(keccak256(abi.encode(write ^ 1, uint256(21))))), 1);
            }
            vm.prank(buyer); vm.expectRevert(); game.requestLootboxRng();
            assertEq(mockVRF.lastRequestId(), id);
            for (uint256 i; i < 1024 && !game.rngComplete(); ++i) game.mineFlip();
            assertTrue(game.rngComplete(), "bounded production keeper completed all consumers");
            assertTrue(game.boxIndexComplete(write));
            assertEq(RecyclingState.currentWord(address(game)), cycle + 42, "completed payload stays nonzero");
            if (cycle == 0) {
                // Resolve the write-side commitments next; they were never part of the old read.
                uint256 next = _request(); mockVRF.fulfillRandomWords(next, 0xCAFE);
                for (uint256 i; i < 1024 && !game.rngComplete(); ++i) game.mineFlip();
                assertTrue(game.rngComplete());
            }
        }
    }
}
