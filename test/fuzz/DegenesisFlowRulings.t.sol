// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegenesisLaunchTurboBoundary -- the launch turbo decided by the next pool alone
/// @notice Deploys on day index 1 and drives the empty Degenesis week once in setUp. Each run then
///         sets the next pool at the end of day 8 and drives the main launch: the index-9 request
///         latches the turbo (level 1, then level 1's jackpot phase entered and ended within day
///         9) exactly when the next pool is strictly above the 50 ETH level-1 target; otherwise
///         level 0 continues on its normal daily path with no latch.
contract DegenesisLaunchTurboBoundary is DegenesisFixture {
    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_DEGENESIS_DAY = 21;
    uint8 internal constant JACKPOT_TURBO = 1;

    function setUp() public override {
        super.setUp();
        _drain();
        _driveThrough(8);
        require(_level() == 0 && _dailyIdx() == 8, "fixture: day 8 sealed at level 0");
    }

    /// forge-config: default.fuzz.runs = 96
    function testFuzz_LaunchTurboIffNextPoolAboveTarget(uint256 raw) public {
        // A third of the runs sit on the boundary itself: 50 ETH - 1, 50 ETH, 50 ETH + 1.
        uint256 next = raw % 3 == 0 ? 50 ether - 1 + (raw >> 8) % 3 : bound(raw >> 8, 1 ether, 120 ether);
        _launchAt(next);
    }

    function test_LaunchBoundaryEdges() public {
        uint256[5] memory edges = [uint256(0), 50 ether - 1, 50 ether, 50 ether + 1, 400 ether];
        for (uint256 i; i < edges.length; ++i) {
            uint256 snap = vm.snapshotState();
            _launchAt(edges[i]);
            vm.revertToStateAndDelete(snap);
        }
    }

    function _launchAt(uint256 next) internal {
        assertEq(game.prizePoolTargetView(), 50 ether, "level-1 target");
        _setNextPool(next);
        bool above = next > 50 ether;

        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        vm.recordLogs();
        _drain(false, 400);
        assertTrue(game.rngLocked(), "the launch request is out");
        if (above) {
            assertEq(_level(), 1, "above the target: level 1 at the launch request");
            assertTrue(_lastPurchaseDay(), "latched at the launch request");
            assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "turbo latched");
        } else {
            assertEq(_level(), 0, "at or below the target: level 0 continues");
            assertFalse(_lastPurchaseDay(), "no latch");
            assertEq(_jackpotFlags() & JACKPOT_TURBO, 0, "no turbo");
        }
        _drain();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_dailyIdx(), GameTimeLib.MAIN_LAUNCH_DAY, "day 9 sealed");
        assertEq(_stageCount(logs, STAGE_DEGENESIS_DAY), 0, "day 9 is not a Degenesis day");
        assertFalse(_jackpotPhase(), "no jackpot phase carried past day 9");
        if (above) {
            assertEq(_level(), 1, "level 1 after day 9");
            assertEq(_stageCount(logs, STAGE_ENTERED_JACKPOT), 1, "level 1's jackpot entered on day 9");
            assertEq(_stageCount(logs, STAGE_JACKPOT_PHASE_ENDED), 1, "and ended on day 9");
            assertEq(_stageCount(logs, STAGE_PURCHASE_DAILY), 0, "no level-0 daily path");
        } else {
            assertEq(_level(), 0, "level 0 after day 9");
            assertEq(_stageCount(logs, STAGE_ENTERED_JACKPOT), 0, "no jackpot phase");
            assertEq(_stageCount(logs, STAGE_PURCHASE_DAILY), 1, "the normal level-0 daily path ran");
        }

        // The day after the launch is ordinary play at the launch's level.
        uint24 lvl = _level();
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY + 1, 1 hours);
        _drain();
        assertEq(_dailyIdx(), GameTimeLib.MAIN_LAUNCH_DAY + 1, "day 10 sealed");
        assertFalse(_jackpotPhase(), "no jackpot phase on day 10");
        assertEq(_level(), lvl, "no second level move on day 10");
    }

    function _stageCount(Vm.Log[] memory logs, uint8 stage) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 1 && logs[i].topics[0] == ADVANCE_SIG) {
                (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
                if (s == stage) ++n;
            }
        }
    }
}

/// @title DegenesisPostSaleHooks -- after the period, the rest of the game never touches sale state
/// @notice The ruling: once the seventh cohort closes, every outside Degenesis hook is a constant compare
///         or a warm slot-0 read. Measured with storage-access recording on the Game over whole
///         ordinary days (ticket, lootbox, foil and whale-pass buys, the daily request, its
///         fulfilment, the day's processing, box opening): no read or write of any Degenesis-only
///         slot (the Vault budget, the credit map, the active cohort, the bound word, the cohort
///         headers, the orders). The same recorder sees those slots during the sale, so it is
///         sensitive.
contract DegenesisPostSaleHooks is DegenesisFixture {
    address internal alice;
    address internal bob;
    uint256[] internal orderKeys;

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 1_000 ether);
        bob = _player("bob", 1_000 ether);
        _drain();
    }

    /// @dev Degenesis-only slots of the Game's storage for the given wallet range.
    function _isDegenesisSlot(bytes32 s, uint256 walletCount) internal view returns (bool) {
        uint256 v = uint256(s);
        if (v == GameSlots.DEGENESIS_ACTIVE || v == GameSlots.DEGENESIS_WORD) {
            return true;
        }
        for (uint256 c = 1; c <= 8; ++c) {
            if (s == keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))) return true;
        }
        for (uint256 i; i < orderKeys.length; ++i) {
            if (s == keccak256(abi.encode(orderKeys[i], GameSlots.DEGENESIS_ORDERS))) return true;
        }
        for (uint256 id = 1; id <= walletCount; ++id) {
            if (s == keccak256(abi.encode(id, GameSlots.DEGENESIS_CREDIT))) return true;
        }
        return false;
    }

    function _countDegenesisAccesses() internal returns (uint256 reads, uint256 writes) {
        (bytes32[] memory r, bytes32[] memory w) = vm.accesses(address(game));
        uint256 n = uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
        for (uint256 i; i < r.length; ++i) if (_isDegenesisSlot(r[i], n)) ++reads;
        for (uint256 i; i < w.length; ++i) if (_isDegenesisSlot(w[i], n)) ++writes;
    }

    /// @dev One ordinary day: ticket + lootbox and preset-box buys, then the whole day driven.
    function _ordinaryDay(uint256 d) internal {
        _warpDay(d, 30 minutes);
        uint256 price = game.mintPrice();
        vm.prank(alice);
        game.purchase{value: price * 4 + 0.05 ether}(
            0, 4 * 400, BoxOrderLib.boCustom(0.05 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        vm.prank(bob);
        game.purchase{value: price * 2}(0, 0, BoxOrderLib.boSmalls(2), bytes32(0), MintPaymentKind.DirectEth, false);
        _warpDay(d, 1 hours);
        _drain();
        _warpDay(d, 13 hours);
        _drain();
    }

    function test_AfterSale_OutsideHooksTouchNoDegenesisState() public {
        // The sale: one order on every Degenesis day, with credit earned by real buys.
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 d = GameTimeLib.DEGENESIS_START_DAY + c - 1;
            _warpDay(d, 2 hours);
            _drain(); // accept this cohort before placing its orders
            _earnCredit(alice, 0.05 ether);
            _buyDegenesis(alice, 0.05 ether);
            orderKeys.push(c << 32);
            if (c == 4) {
                // Control: the same recorder sees the sale's state on a sale day.
                vm.record();
                _earnCredit(bob, 0.02 ether);
                _buyDegenesis(bob, 0.02 ether);
                orderKeys.push(c << 32);
                _warpDay(d, 3 hours);
                _drain();
                (uint256 r0, uint256 w0) = _countDegenesisAccesses();
                vm.stopRecord();
                assertGt(r0, 0, "control: the sale reads Degenesis state");
                assertGt(w0, 0, "control: the sale writes Degenesis state");
            }
            _warpDay(d, 13 hours);
            _drain();
        }
        for (uint256 d = GameTimeLib.MAIN_LAUNCH_DAY; _degenesisClosed() < 7; ++d) {
            require(d < GameTimeLib.MAIN_LAUNCH_DAY + 4, "fixture: sale did not close");
            _driveDay(d);
        }
        assertEq(_degenesisClosed(), 7, "fixture: seventh cohort closed");
        uint256 startDay = game.currentDayView() + 1;
        assertGe(block.timestamp, GameTimeLib.DEGENESIS_END_TS, "fixture: credit window closed");

        uint256 purchases;
        for (uint256 d = startDay; d < startDay + 3; ++d) {
            // The budget shares slot 13 with the daily completion timestamp.
            uint128 budget = uint128(_slot(GameSlots.DEGENESIS_VAULT_BUDGET));
            vm.record();
            _ordinaryDay(d);
            // A foil pack and a whale pass also run the credit hook.
            if (d == startDay) {
                vm.prank(alice);
                game.purchase{value: 0.1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
                vm.prank(bob);
                game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
                purchases += 2;
            }
            (uint256 reads, uint256 writes) = _countDegenesisAccesses();
            vm.stopRecord();
            assertEq(uint128(_slot(GameSlots.DEGENESIS_VAULT_BUDGET)), budget, "Degenesis budget unchanged");
            purchases += 2;
            assertEq(reads, 0, "after the sale: a Degenesis-only slot was read");
            assertEq(writes, 0, "after the sale: a Degenesis-only slot was written");
            assertEq(_dailyIdx(), d, "the ordinary day sealed");
        }
        assertEq(purchases, 8, "non-vacuity: purchases ran");
        assertEq(_creditOfId(game.walletIdOf_g3120(alice)), 0, "no credit accrued after the window");
    }
}

/// @title DegenesisOneTypePerBuy -- one box type per lootbox purchase, through the real Game
/// @notice The purchase input carries one kind and one count; it cannot express two kinds. Through
///         `game.purchase`: each kind alone buys, an input with a bit at or above 30, a preset
///         carrying custom units, a zero or 101 count, or a custom outside 0.01..2,000 ETH reverts
///         with nothing charged and nothing credited; the 2,000 ETH custom maximum buys.
contract DegenesisOneTypePerBuy is DegenesisFixture {
    address internal alice;

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 10_000 ether);
    }

    function _buyBox(uint256 boxOrder, uint256 value) internal returns (bool ok) {
        vm.prank(alice);
        (ok,) = address(game).call{value: value}(
            abi.encodeWithSignature(
                "purchase(uint32,uint256,uint256,bytes32,uint8,bool)",
                uint32(0), uint256(0), boxOrder, bytes32(0), uint8(MintPaymentKind.DirectEth), false
            )
        );
    }

    function test_OneKindPerPurchase_RealGame() public {
        uint256 price = game.mintPrice();
        uint256[4] memory good = [BoxOrderLib.boSmalls(3), BoxOrderLib.boMeds(2), BoxOrderLib.boLarges(1), BoxOrderLib.boCustom(0.37 ether)];
        uint256[4] memory cost = [3 * price, 2 * 5 * price, 25 * price, 0.37 ether];
        uint32 id = game.walletIdOf_g3120(alice);
        for (uint256 i; i < 4; ++i) {
            uint256 credit0 = _creditOfId(id);
            uint256 pool0 = _claimablePool();
            uint256 bal0 = alice.balance;
            assertTrue(_buyBox(good[i], cost[i]), "a single-kind order buys");
            assertEq(bal0 - alice.balance, cost[i], "charged exactly the one kind's cost");
            assertEq(_creditOfId(id) - credit0, cost[i] / 4, "credit on the whole cost");
            assertEq(_claimablePool(), pool0, "no overpay");
        }
        assertTrue(_buyBox(BoxOrderLib.boCustom(2_000 ether), 2_000 ether), "the 2,000 ETH maximum buys");

        uint256[8] memory bad = [
            BoxOrderLib.boInput(0, 1, 0) | (uint256(1) << 30), // second field above the input
            BoxOrderLib.boSmalls(1) | (BoxOrderLib.boMeds(1) << 30), // a second kind packed above
            BoxOrderLib.boInput(1, 1, 50), // a preset carrying units
            BoxOrderLib.boInput(3, 0, 50), // custom with zero count
            BoxOrderLib.boInput(0, 101, 0), // 101 boxes
            BoxOrderLib.boInput(3, 1, 9), // below 0.01 ETH
            BoxOrderLib.boInput(3, 1, 2_000_001), // above 2,000 ETH
            BoxOrderLib.boInput(3, 1, 10) | (uint256(1) << 255)
        ];
        for (uint256 i; i < bad.length; ++i) {
            uint256 credit0 = _creditOfId(id);
            uint256 pool0 = _claimablePool();
            uint256 bal0 = alice.balance;
            assertFalse(_buyBox(bad[i], 2_001 ether), "a malformed order reverts");
            assertEq(alice.balance, bal0, "nothing charged");
            assertEq(_creditOfId(id), credit0, "nothing credited");
            assertEq(_claimablePool(), pool0, "nothing held");
        }
    }
}
