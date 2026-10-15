// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {RedemptionCloseTools} from "./helpers/RedemptionCloseTools.sol";

contract WriteTrimSeeder is DegenerusGameStorage {
    function seed(uint32 id, uint32 entries) external {
        uint24 day = _simulatedDayIndex();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        purchaseStartDay = day;
        if (entries != 0) _queueEntries(id, _activeTicketLevel() + 6, entries, false);
    }

    function seedClaimable(uint32 id, uint128 claimable) external {
        claimablePool += claimable;
        balancesPacked[id] += claimable;
    }

    /// @dev Enter `due` and run the production seizure worker, as the transition request and the
    ///      mining engine would.
    function seizeDue(uint24 due) external {
        level = due;
        if (_loansDueCount[due] == 0) return;
        _setLoansDuePending(true);
        loanSeizeCursor = 0;
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @notice A loan seizure stops the seized account's AFKing run and, for a main, every smurf's,
///         by walking the main's stored smurf list. The daily stage no longer polls acquisition.
contract AfkingFamilyLiquidationTest is RedemptionCloseTools {
    address private seller;
    uint32 private root;
    bytes private gameRuntime;
    address private seeder;
    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        seller = makeAddr("family-seller");
        root = _giveWalletId(seller);
        _grantSmurfBase(seller, 16);
        vm.deal(seller, 1_000 ether);
        vm.deal(address(game), 10_000 ether);
        gameRuntime = address(game).code;
        seeder = address(new WriteTrimSeeder());
        lens = new DegenerusGameLens();
        _seed(root, 400);
        vm.etch(address(game), seeder.code);
        WriteTrimSeeder(address(game)).seedClaimable(2, 100 ether);
        vm.etch(address(game), gameRuntime);
    }

    function _seed(uint32 id, uint32 entries) private {
        vm.etch(address(game), seeder.code);
        WriteTrimSeeder(address(game)).seed(id, entries);
        vm.etch(address(game), gameRuntime);
    }

    function _child() private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(seller);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _sub(uint32 id, bool tickets) private {
        uint256 seat = _grantSeat(seller);
        vm.prank(seller);
        game.subscribe{value: 2 ether}(id, false, tickets, 1, 0, seat);
    }

    function _quantity(uint32 id) private view returns (uint8) {
        return lens.subInfoFullById(address(game), id).dailyQuantity;
    }

    /// @dev Borrow against `id` and default at the next level.
    function _sale(uint32 id) private {
        uint24 due = game.level() + 1;
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due, type(uint256).max);
        assertTrue(q.eligible, "borrow eligible");
        vm.prank(seller);
        game.borrow(id, due, type(uint256).max, q.principal);
        // A borrower whose own balances cover the full-term amount auto-repays at the due level,
        // so withdraw the account's prepaid funding to default.
        uint256 prepaid = uint256(vm.load(address(game), GameSlotKeys.balances(id))) >> 128;
        if (prepaid != 0) {
            vm.prank(seller);
            game.withdrawAfkingFunding(id, prepaid);
        }
        vm.etch(address(game), seeder.code);
        WriteTrimSeeder(address(game)).seizeDue(due);
        vm.etch(address(game), gameRuntime);
    }

    function test_SmurfListRecordsEveryCreationAcrossWords() public {
        uint32[] memory made = new uint32[](11);
        for (uint256 i; i < made.length; ++i) made[i] = _child();
        uint32[] memory listed = lens.smurfsOf(address(game), root);
        assertEq(listed.length, made.length, "list length is the lifetime smurf count");
        for (uint256 i; i < made.length; ++i) assertEq(listed[i], made[i], "creation order");
        assertEq(lens.smurfsOf(address(game), made[0]).length, 0, "a smurf owns no list");
    }

    function test_MainSaleCancelsOwnAndEverySmurfSubscription() public {
        _sub(root, false);
        // A borrowing main has at most five smurfs, so the walk fits one list word.
        uint32[] memory kids = new uint32[](5);
        for (uint256 i; i < kids.length; ++i) kids[i] = _child();
        // Active box and ticket runs, one tombstone, one never subscribed.
        _sub(kids[0], false);
        _sub(kids[1], true);
        _sub(kids[3], false);
        _sub(kids[2], false);
        vm.prank(seller);
        game.subscribe(kids[2], false, false, 0, 0, 0);
        uint256 members = game.subscriberSetLength();

        _sale(root);

        assertEq(_quantity(root), 0, "main's own run cancelled");
        for (uint256 i; i < kids.length; ++i) assertEq(_quantity(kids[i]), 0, "every smurf run cancelled");
        assertEq(game.subscriberSetLength(), members, "tombstones stay for the stage to reclaim");
        // Acquired family members cannot restart.
        vm.prank(seller);
        vm.expectRevert(bytes4(keccak256("NotApproved()")));
        game.subscribe(kids[0], false, false, 1, 0, 0);
    }

    function test_ChildSaleCancelsOnlyThatChild() public {
        _sub(root, false);
        uint32 a = _child();
        uint32 b = _child();
        _sub(a, false);
        _sub(b, true);
        _seed(a, 400);

        _sale(a);

        assertEq(_quantity(a), 0, "sold child's run cancelled");
        assertEq(_quantity(b), 1, "sibling untouched");
        assertEq(_quantity(root), 1, "owner untouched");

        // A later main sale walks past the already-cancelled child.
        _seed(root, 400);
        _sale(root);
        assertEq(_quantity(b), 0);
        assertEq(_quantity(root), 0);
    }

    function test_ExternallyFundedOutsiderSurvivesSaleUntilStage() public {
        address outsider = makeAddr("family-outsider");
        uint32 outsiderId = _giveWalletId(outsider);
        vm.prank(seller);
        game.setAfkingFundingApproval(0, outsiderId, true);
        vm.prank(seller);
        game.depositAfkingFunding{value: 5 ether}(root);
        uint256 seat = _grantSeat(outsider);
        vm.prank(outsider);
        game.subscribe(0, false, false, 1, root, seat);

        _sale(root);

        // The sale cannot find an outsider funded by the sold account; the stage's funder check
        // cancels it before any further debit of the buyer-owned balance.
        assertEq(_quantity(outsiderId), 1, "outsider run left for the stage");
        assertFalse(game.afkingFundingApproved(root, outsiderId), "consent dead after sale");
    }
}

/// @notice The AFKing open pass reads Sub records but never writes them, and the stage's batched
///         claimablePool release equals the per-account debits exactly.
contract AfkingWriteTrimTest is DeployProtocol {
    uint256 private _lastFulfilledReqId;
    bytes private gameRuntime;
    address private seeder;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
        gameRuntime = address(game).code;
        seeder = address(new WriteTrimSeeder());
        _finishSubscriptionWindow();
    }

    function test_OpenPassSettlesEachStampOnceAndNeverWritesSubRecords() public {
        address[] memory boxes = _subs(9, "wt_box_", false, false);
        address[] memory tickets = _subs(3, "wt_tkt_", true, false);
        _toRequest(uint256(keccak256("wt_w1")) | 1);

        uint24 stampDay = _resetDay();
        assertGe(_pendingCount(), boxes.length, "every box sub stamped");
        bytes32[] memory before = new bytes32[](boxes.length + tickets.length);
        for (uint256 i; i < boxes.length; ++i) {
            before[i] = _subWord(boxes[i]);
            assertEq(uint24(uint256(before[i]) >> 56), stampDay, "stamped today");
        }
        for (uint256 i; i < tickets.length; ++i) before[boxes.length + i] = _subWord(tickets[i]);

        // Answer the request and run the engine to the AFKing read consumer.
        for (uint256 i; i < 200 && game.rngConsumerStage() != 2; ++i) {
            _fulfill(uint256(keccak256("wt_c1")) + i);
            _stepMinimal();
        }
        assertEq(game.rngConsumerStage(), 2, "AFKing consumer reached");

        // Settlement evidence independent of the counter and cursor: step the open walk in
        // minimal calls and record which accounts emitted a box-settlement record in each.
        uint256 calls;
        while (game.rngConsumerStage() == 2) {
            require(++calls < 200, "harness: open walk never finished");
            uint256 gasCap = _minimalGas();
            vm.recordLogs();
            game.mineFlip{gas: gasCap}(0);
            _tallySettlements(vm.getRecordedLogs());
        }
        assertGt(calls, 1, "open walk split across calls");
        for (uint256 i; i < boxes.length; ++i) {
            assertEq(_settledCalls[game.walletIdOf(boxes[i])], 1, "each paid box settled exactly once");
        }
        for (uint256 i; i < tickets.length; ++i) {
            assertEq(_settledCalls[game.walletIdOf(tickets[i])], 0, "ticket subs have no AFKing box");
        }

        _drainDay(uint256(keccak256("wt_c2")) | 1);
        assertEq(_pendingCount(), 0, "every stamp opened");
        for (uint256 i; i < boxes.length; ++i) assertEq(_subWord(boxes[i]), before[i], "box Sub untouched by open");
        for (uint256 i; i < tickets.length; ++i) {
            assertEq(_subWord(tickets[i]), before[boxes.length + i], "ticket Sub untouched by open");
        }
    }

    function test_StageReleasesClaimablePoolOncePerChunkExactly() public {
        address[] memory a = _subs(6, "wt_pa_", false, false);
        address[] memory b = _subs(4, "wt_pb_", true, false);
        address[] memory c = _subs(4, "wt_pc_", false, true); // drain claimable first
        for (uint256 i; i < c.length; ++i) _seedClaimable(game.walletIdOf(c[i]), 3 ether);

        _drainDay(uint256(keccak256("wt_pre")) | 1);
        vm.warp(block.timestamp + 1 days);
        // Run the new day's earlier work, stopping where subscriber preparation is next.
        for (uint256 i; i < 400 && game.nextMinerAction() != 15; ++i) _stepMinimal();
        assertEq(game.nextMinerAction(), 15, "preparation is next"); // PrepareSubscriptions
        uint256 poolBefore = game.claimablePoolView();
        int256 balancesBefore = _balanceSum(a, b, c);
        int256 minerBefore = _balance(game.walletIdOf(address(this)));

        uint256 calls;
        for (; calls < 400 && game.nextMinerAction() == 15; ++calls) _stepMinimal();
        assertGt(calls, 1, "preparation split across chunks");
        assertTrue(game.nextMinerAction() != 15, "preparation finished");

        int256 balanceDelta = _balanceSum(a, b, c) - balancesBefore
            + _balance(game.walletIdOf(address(this))) - minerBefore;
        assertLt(balanceDelta, 0, "subs paid");
        assertEq(int256(game.claimablePoolView()) - int256(poolBefore), balanceDelta, "pool moved with the accounts");
    }

    // ---- helpers ----

    function _subs(uint256 n, string memory prefix, bool tickets, bool drainFirst)
        private
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who);
            vm.deal(address(this), 20 ether);
            uint32 id = game.walletIdOf(who);
            if (id == 0) id = _giveWalletId(who);
            game.depositAfkingFunding{value: 20 ether}(id);
            vm.prank(who);
            game.subscribe(0, drainFirst, tickets, 1, 0, seat);
        }
    }

    function _seedClaimable(uint32 id, uint128 amount) private {
        vm.etch(address(game), seeder.code);
        WriteTrimSeeder(address(game)).seedClaimable(id, amount);
        vm.etch(address(game), gameRuntime);
    }

    function _balance(uint32 id) private view returns (int256) {
        if (id == 0) return 0;
        uint256 packed = uint256(vm.load(address(game), GameSlotKeys.balances(id)));
        return int256(uint256(uint128(packed)) + (packed >> 128));
    }

    function _balanceSum(address[] memory a, address[] memory b, address[] memory c) private view returns (int256 s) {
        for (uint256 i; i < a.length; ++i) s += _balance(game.walletIdOf(a[i]));
        for (uint256 i; i < b.length; ++i) s += _balance(game.walletIdOf(b[i]));
        for (uint256 i; i < c.length; ++i) s += _balance(game.walletIdOf(c[i]));
    }

    function _subWord(address who) private view returns (bytes32) {
        return vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)));
    }

    function _cursorWord() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.SUB_CURSOR)));
    }

    function _pendingCount() private view returns (uint256) {
        return uint16(_cursorWord() >> (GameSlots.PENDING_BOX_COUNT_OFFSET * 8));
    }

    function _resetDay() private view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_RESET_DAY))) >> (GameSlots.AFKING_RESET_DAY_OFFSET * 8));
    }

    mapping(uint32 => uint256) private _settledCalls;

    bytes32 private constant LOOTBOX_OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant BOX_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    bytes32 private constant CRAPS_PASSES = keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)");

    /// @dev Every box roll ends in exactly one of these records for its account. Count each
    ///      account once per call, so a box opened again in a later call shows up as 2.
    function _tallySettlements(Vm.Log[] memory logs) private {
        uint32[] memory seen = new uint32[](logs.length);
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 sig = logs[i].topics[0];
            if (sig != LOOTBOX_OPENED && sig != BOX_SPIN && sig != CRAPS_PASSES) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            bool dup;
            for (uint256 j; j < n; ++j) if (seen[j] == id) dup = true;
            if (dup) continue;
            seen[n++] = id;
            ++_settledCalls[id];
        }
    }

    /// @dev The smallest mineFlip allowance that succeeds now (bisection over snapshots).
    function _minimalGas() private returns (uint256) {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    function _stepMinimal() private {
        game.mineFlip{gas: _minimalGas()}(0);
    }

    function _fulfill(uint256 vrfWord) private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    /// @dev Settle the current day, then step the next day in minimal calls until its
    ///      preparation has stamped and the daily request is next or has just been made.
    function _toRequest(uint256 vrfWord) private {
        _drainDay(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() == 17) return; // RequestDaily
            uint256 req = mockVRF.lastRequestId();
            _stepMinimal();
            if (mockVRF.lastRequestId() != req && _resetDay() == _today()) return;
        }
        revert("harness: the daily request never became the next work");
    }

    function _today() private view returns (uint24) {
        return uint24(game.currentDayView());
    }

    function _drainDay(uint256 vrfWord) private {
        for (uint256 i; i < 800; ++i) {
            if (!game.advanceDue() && game.rngComplete()) return;
            _fulfill(vrfWord + i);
            _stepMinimal();
        }
        revert("harness: the day never settled");
    }
}
