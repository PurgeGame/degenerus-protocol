// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {IDegenerusGameRngModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev The RNG module's mid-day request worker (the one mineFlip's RequestMidday stage
///      dispatches), called alone in the Game's context to observe its own gates.
contract MiddayRequestWorker is DegenerusGame {
    function requestMidday() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameRngModule.requestMinerRng.selector));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

/// @dev Observe the real request boundary, including a reentrant mineFlip attempt.
contract CompletionCheckingCoordinator {
    DegenerusGame private immutable game;
    constructor(DegenerusGame game_) { game = game_; }
    function getSubscription(uint256) external pure returns (uint96, uint96, uint64, address, address[] memory) {
        return (1000 ether, 0, 0, address(0), new address[](0));
    }
    function requestRandomWords(VRFRandomWordsRequest calldata) external returns (uint256) {
        require(!game.rngComplete(), "completion remained true during request");
        try game.mineFlip() { revert("nested fresh request was accepted"); }
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
        // The state engine requests mid-day words on its own once the day seals (a closed Craps
        // window rides a mid-day request when the subscription covers it, 6d0e64b09): answer and
        // drain them so the fixture starts from an idle, completed read session.
        for (uint256 i; i < 64; ++i) {
            uint8 action = game.nextMinerAction();
            if (action == 0) break;
            if (action == 2) {
                uint256 id = mockVRF.lastRequestId();
                (,, bool done) = mockVRF.pendingRequests(id);
                if (done) break;
                mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("setup-midday", id))));
            } else {
                game.mineFlip();
            }
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
    /// @dev Drain the delivered read session through the keeper. A 2M allowance can never admit
    ///      a fresh request (RNG_REQUEST plus tail), so the keeper stops at completion and the
    ///      test, not the engine's own mid-day request for pending write-side value, decides
    ///      when the next session is sealed.
    function _drainSession() private {
        for (uint256 i; i < 1024 && !game.rngComplete(); ++i) game.mineFlip{gas: 2_000_000}();
    }
    /// @dev The buyer's mineFlip, with the read session complete, issues the mid-day request.
    function _request() private returns(uint256 id) {
        uint256 old = mockVRF.lastRequestId(); vm.prank(buyer); game.mineFlip();
        id = mockVRF.lastRequestId(); assertGt(id, old, "fresh production request");
    }
    /// @dev No fresh request is reachable: the engine selects none for the credited buyer, and the
    ///      mid-day request worker itself refuses at its completion gate without touching state.
    function _assertNextRequestBlocked(uint256 id) private {
        vm.prank(buyer);
        uint8 action = game.minerAction();
        assertTrue(action != 17 && action != 18, "the engine selects no fresh request");
        bytes32 state = game.extsload(bytes32(0));
        uint256 credit = game.middayRngCredits(buyer);
        bytes memory production = address(game).code;
        vm.etch(address(game), address(new MiddayRequestWorker()).code);
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        MiddayRequestWorker(payable(address(game))).requestMidday();
        vm.etch(address(game), production);
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
        // Publication leaves the actual box/bet consumers outstanding. The keeper continues into
        // the consumers within the same call when the allowance covers them (60d31f775), so the
        // publication-only step is a 400k call: it can never admit a human-box entry.
        game.mineFlip{gas: 400_000}();
        assertFalse(game.rngComplete());
        _assertNextRequestBlocked(id);
        _drainSession();
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
        vm.prank(buyer); game.mineFlip();
        assertFalse(game.rngComplete());
        assertEq(uint256(game.extsload(bytes32(uint256(4)))), 90001);
    }
    function test_CoordinatorFailureRollsBackSealAndCredit() public {
        _buy();
        bytes32 state = game.extsload(bytes32(0));
        bytes32 cursor = game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED));
        uint256 credit = game.middayRngCredits(buyer);
        uint256 id = mockVRF.lastRequestId();
        vm.mockCallRevert(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector), "coordinator unavailable");
        vm.prank(buyer); vm.expectRevert(bytes("coordinator unavailable")); game.mineFlip();
        assertEq(game.extsload(bytes32(0)), state, "failed request changed buffer or completion");
        assertEq(game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED)), cursor, "failed request changed pending commitments");
        assertEq(game.middayRngCredits(buyer), credit);
        assertEq(mockVRF.lastRequestId(), id);
    }
    function test_EightSessionsReuseTwoBuffersWithoutLeakingOrdersOrBets() public {
        for (uint256 cycle; cycle < 8; ++cycle) {
            uint48 write = RecyclingState.writeBuffer(address(game));
            assertEq(uint256(game.extsload(keccak256(abi.encode(write, GameSlots.BOX_PLAYERS)))), 0, "write boxes header reset");
            assertEq(uint256(game.extsload(keccak256(abi.encode(write, GameSlots.DEGENERETTE_QUEUE)))), 0, "write bets header reset");
            _buy();
            // The low 48 bits of lootboxRngPacked are unused; a request must leave them
            // untouched, so no request-epoch counter exists anywhere in the word.
            uint48 lowBits = uint48(uint256(game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED))));
            uint256 id = _request();
            assertEq(RecyclingState.readBuffer(address(game)), write);
            assertEq(RecyclingState.writeBuffer(address(game)), write ^ 1);
            assertEq(uint48(uint256(game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED)))), lowBits, "no increasing epoch counter");
            assertFalse(game.rngComplete()); assertEq(RecyclingState.currentWord(address(game)), 0);
            mockVRF.fulfillRandomWords(id, cycle + 42);
            assertFalse(game.rngComplete(), "delivery cannot skip settlement");
            // All producers now bind the other buffer, even while the read word exists.
            if (cycle == 0) {
                _buy();
                assertEq(uint256(game.extsload(keccak256(abi.encode(write ^ 1, GameSlots.DEGENERETTE_QUEUE)))), 1);
            }
            _assertNextRequestBlocked(id);
            _drainSession();
            assertTrue(game.rngComplete(), "bounded production keeper completed all consumers");
            assertTrue(game.boxIndexComplete(write));
            assertEq(RecyclingState.currentWord(address(game)), cycle + 42, "completed payload stays nonzero");
            if (cycle == 0) {
                // Resolve the write-side commitments next; they were never part of the old read.
                uint256 next = _request(); mockVRF.fulfillRandomWords(next, 0xCAFE);
                _drainSession();
                assertTrue(game.rngComplete());
            }
        }
    }
}
