// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {QaSlots} from "../helpers/QaSlots.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @notice A run credits from the day after it starts, so a manual primary completed on the start
///         day credits like one off a run: +1 on the run's streak and the 100-FLIP slot-0 reward.
///         Subscribing alone credits nothing, later run days stay streak-neutral, the completion
///         mask dedups within a day, and the protocol seats never take the start-day credit.
contract AfkingSubscribeDayCreditTest is DeployProtocol {
    uint256 private constant STATE_ROOT = QaSlots.STATE;
    uint256 private constant ACTIVE_ROOT = QaSlots.ACTIVE;
    uint256 private constant OFF_LAST_ACTIVE = 3;
    uint256 private constant OFF_STREAK = 9;
    uint256 private constant OFF_MASK = 24;
    uint256 private constant OFF_AFKING_SINCE = 26;
    uint256 private constant SLOT0_REWARD = 100;

    bytes32 private constant E_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");

    uint256 private price;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _nonce;

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo_g1027();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
        assertEq(_questDay(), _fixtureGameDay(), "non-vacuity: today's quests are rolled");
    }

    // =====================================================================
    // Scenarios
    // =====================================================================

    function test_SubscribeAloneCreditsNothing() public {
        address p = makeAddr("subOnly");
        uint32 id = _fund(p);
        uint256 streak0 = _field(id, OFF_STREAK, 16);
        uint256 flip0 = coinflip.coinflipAmountById(id);

        vm.recordLogs();
        _subscribe(p);
        (uint256 n,,) = _completions(id, vm.getRecordedLogs());

        assertEq(n, 0, "no completion");
        assertEq(_field(id, OFF_MASK, 8), 0, "no slot marked");
        assertEq(_checkpointStreak(id), streak0, "the run snapshots the streak as it was");
        assertEq(_field(id, OFF_AFKING_SINCE, 24), _fixtureGameDay(), "the run's start day");
        assertEq(coinflip.coinflipAmountById(id), flip0, "subscribing pays no FLIP");
        assertEq(coin.balanceOf(p), 0, "subscribing mints no FLIP");
    }

    function test_SubscribeThenBuyCreditsTheStartDayOnce() public {
        address p = makeAddr("subFirst");
        address control = makeAddr("control");
        uint32 id = _fund(p);
        uint32 cid = _fund(control);
        _subscribe(p);
        uint256 checkpoint0 = _checkpointStreak(id);
        uint256 manual0 = _field(id, OFF_STREAK, 16);
        uint256 flip0 = coinflip.coinflipAmountById(id);
        uint256 cflip0 = coinflip.coinflipAmountById(cid);

        vm.recordLogs();
        _buy(p);
        (uint256 n, uint256 reward, uint8 slot) = _completions(id, vm.getRecordedLogs());
        _buy(control);

        assertEq(n, 1, "one completion");
        assertEq(slot, 0, "the primary");
        assertEq(reward, SLOT0_REWARD, "the slot-0 reward");
        assertEq(_checkpointStreak(id), checkpoint0 + 1, "+1 reaches the run");
        assertEq(_field(id, OFF_STREAK, 16), manual0, "the dormant manual streak stays put");
        assertEq(_field(id, OFF_LAST_ACTIVE, 24), _questDay(), "a funded mint day");
        assertEq(
            coinflip.coinflipAmountById(id) - flip0,
            coinflip.coinflipAmountById(cid) - cflip0,
            "paid exactly like a non-afking buyer"
        );

        vm.recordLogs();
        _buy(p);
        (n,,) = _completions(id, vm.getRecordedLogs());
        assertEq(n, 0, "the mask dedups a second buy");
        assertEq(_checkpointStreak(id), checkpoint0 + 1);
    }

    function test_BuyThenSubscribeCreditsNothingExtra() public {
        address p = makeAddr("buyFirst");
        uint32 id = _fund(p);
        _buy(p);
        uint256 streak1 = _field(id, OFF_STREAK, 16);
        assertEq(_field(id, OFF_MASK, 8) & 1, 1, "non-vacuity: the buy completed the primary");

        vm.recordLogs();
        _subscribe(p);
        _buy(p);
        (uint256 n,,) = _completions(id, vm.getRecordedLogs());

        assertEq(n, 0, "no completion");
        assertEq(_checkpointStreak(id), streak1, "the snapshot already includes the buy");
    }

    function test_ResubscribeSameDayCannotDoubleCredit() public {
        address p = makeAddr("resub");
        uint32 id = _fund(p);
        _subscribe(p);
        _buy(p);
        uint256 credited = _checkpointStreak(id);
        vm.prank(p);
        game.subscribe(0, false, 0, 0);
        assertEq(_field(id, OFF_AFKING_SINCE, 24), 0, "non-vacuity: the run ended");
        assertEq(_field(id, OFF_STREAK, 16), credited, "the handback carries the start-day credit");

        vm.recordLogs();
        _subscribe(p);
        _buy(p);
        (uint256 n,,) = _completions(id, vm.getRecordedLogs());

        assertEq(n, 0, "no second credit");
        assertEq(_checkpointStreak(id), credited, "the snapshot carries the single credit");
    }

    function test_LaterDayBuyStaysNeutral() public {
        address p = makeAddr("laterDay");
        address control = makeAddr("controlLater");
        uint32 id = _fund(p);
        uint32 cid = _fund(control);
        _subscribe(p);
        _deliverDay();
        assertEq(_questDay(), _fixtureGameDay(), "non-vacuity: the next day's quests are rolled");
        assertGt(_fixtureGameDay(), _field(id, OFF_AFKING_SINCE, 24), "non-vacuity: a later run day");
        uint256 checkpoint1 = _checkpointStreak(id);
        uint256 flip1 = coinflip.coinflipAmountById(id);
        uint256 cflip1 = coinflip.coinflipAmountById(cid);

        vm.recordLogs();
        _buy(p);
        (uint256 n, uint256 reward, uint8 slot) = _completions(id, vm.getRecordedLogs());
        _buy(control);

        assertEq(n, 1);
        assertEq(slot, 0);
        assertEq(reward, 0, "the run credits this day");
        assertEq(_checkpointStreak(id), checkpoint1, "streak-neutral");
        assertEq(
            coinflip.coinflipAmountById(id) - flip1 + SLOT0_REWARD,
            coinflip.coinflipAmountById(cid) - cflip1,
            "no slot-0 reward"
        );
    }

    function test_ProtocolSeatTakesNoStartDayCredit() public {
        uint32 id = 1; // the Vault
        uint24 day = _questDay();
        bytes32 slot = keccak256(abi.encode(uint256(id), STATE_ROOT));
        uint256 w = uint256(vm.load(address(quests), slot));
        w = (w & ~(uint256(0xffffff) << (OFF_AFKING_SINCE * 8))) | (uint256(day) << (OFF_AFKING_SINCE * 8));
        vm.store(address(quests), slot, bytes32(w));
        vm.expectCall(address(game), abi.encodeCall(game.recordAfkingSecondary_g3316, (id, 1)), 0);
        vm.recordLogs();
        vm.prank(ContractAddresses.COIN);
        (uint256 reward,,, bool completed,) =
            quests.handlePurchase_g23478(_fixtureGameDay(), id, price, 0, 0, price, price);
        (uint256 n, uint256 eventReward, uint8 slot0) = _completions(id, vm.getRecordedLogs());

        assertTrue(completed, "non-vacuity: the primary completes");
        assertEq(slot0, 0);
        assertGt(n, 0);
        assertEq(reward, 0, "no reward");
        assertEq(eventReward, 0, "no reward on any completion");
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _fund(address p) private returns (uint32 id) {
        id = game.walletIdOf_g3120(p);
        if (id == 0) id = _giveWalletId(p);
        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(id);
    }

    function _subscribe(address p) private {
        uint256 seat = _grantSeat(p);
        vm.prank(p);
        game.subscribe(0, false, 1, seat);
    }

    function _buy(address p) private {
        vm.deal(p, p.balance + price);
        vm.prank(p);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _completions(uint32 id, Vm.Log[] memory logs)
        private pure returns (uint256 n, uint256 reward, uint8 slot)
    {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length != 4 || l.topics[0] != E_COMPLETED) continue;
            if (uint256(l.topics[1]) != id) continue;
            (,, uint256 r) = abi.decode(l.data, (uint8, uint32, uint256));
            if (n == 0) slot = uint8(uint256(l.topics[3]));
            ++n;
            reward += r;
        }
    }

    function _field(uint32 id, uint256 offset, uint256 width) private view returns (uint256) {
        uint256 w = uint256(vm.load(address(quests), keccak256(abi.encode(uint256(id), STATE_ROOT))));
        return (w >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _questDay() private view returns (uint24) {
        return uint24(uint256(vm.load(address(quests), bytes32(ACTIVE_ROOT))));
    }

    function _checkpointStreak(uint32 id) private view returns (uint256) {
        (uint256 lane,) = GameSlotKeys.subLane(address(game), id);
        return (lane >> 69) & 0xffff;
    }

    /// @dev One funded day for the live set: the new-day pass, then open the pending boxes.
    function _deliverDay() private {
        uint256 w = uint256(keccak256(abi.encode("dayCredit", _nonce++))) | 1;
        _settle(w ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settle(w);
        _settle(uint256(keccak256(abi.encode("clean", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
        _finishSubscriptionWindow();
    }

    function _settle(uint256 vrfWord) private {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfill(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
            _fulfill(vrfWord);
        }
    }

    function _fulfill(uint256 vrfWord) private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }
}

/// @notice The protocol seats begin in the Vault / sDGNRS constructors and stay out of the
///         start-day credit: bootstrap completes no quest for them.
contract AfkingSubscribeDayCreditProtocolSeatsTest is DeployProtocol {
    bytes32 private constant E_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");

    function test_ProtocolSeatsUnchangedAtBootstrap() public {
        vm.recordLogs();
        _deployProtocol();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint32 id = 1; id <= 2; ++id) {
            (, uint256 position1) = GameSlotKeys.subLane(address(game), id);
            assertGt(position1, 0, "non-vacuity: the protocol seat is a member");
            uint256 w = uint256(vm.load(address(quests), keccak256(abi.encode(uint256(id), QaSlots.STATE))));
            assertGt((w >> (26 * 8)) & 0xffffff, 0, "the seat's run is marked");
            assertEq((w >> (9 * 8)) & 0xffff, 0, "no quest streak");
            for (uint256 i; i < logs.length; ++i) {
                Vm.Log memory l = logs[i];
                if (l.topics.length == 4 && l.topics[0] == E_COMPLETED) {
                    assertTrue(uint256(l.topics[1]) != id, "no completion for a protocol seat");
                }
            }
        }
    }
}
