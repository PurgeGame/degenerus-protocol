// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

contract SeizureGasSeeder is DegenerusGameStorage {
    function fund(uint32 id, uint128 claimable) external {
        balancesPacked[id] += claimable;
        claimablePool += claimable;
    }
    function seedLevel(uint32 id, uint24 level_, uint32 entries) external { _queueEntries(id, level_, entries, false); }
    /// @dev Record yesterday's word, seal today and complete its subscriber pass, so new runs open
    ///      as on an ordinary day.
    function prime() external {
        uint24 day = _wallDay();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        dailyComplete = true;
        lastDailyRequestWallDay = _wallDay();
        lastDailyCompletedAt = uint48(block.timestamp);
        purchaseStartDay = day;
        _afkingEndpointDay = day;
    }
    function completedDeadline() external {
        dailyIdx = purchaseStartDay + 30;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        lastPurchaseDay = false;
        jackpotPhaseFlag = false;
        _setPrizePools(0, uint128(_getFuturePrizePool()));
    }
    function setBalances(uint32 id, uint128 claimable, uint128 afking) external {
        uint256 old = balancesPacked[id];
        claimablePool = claimablePool - uint128(old) - uint128(old >> 128) + claimable + afking;
        balancesPacked[id] = (uint256(afking) << 128) | claimable;
    }
    function enterDue(uint24 due) external {
        level = due;
        _setLoansDuePending(true);
        loanSeizeCursor = 0;
    }
    function seize() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @notice Cold cost of one loan seizure, the stage's per-loan admission estimate. Every account
///         is built and the level armed in setUp, so the measured call reads each slot cold.
abstract contract LoanSeizureGasBase is DeployProtocol, NativeGasExport {
    address internal borrower;
    uint32 internal root;
    uint256 internal family;
    bytes internal gameRuntime;
    address internal seeder;
    DegenerusGameLens internal lens;

    function _setUpCase(uint256 smurfs, bool subscribed, bool deity, bool holdsSdgnrs) internal {
        _setUpCase(smurfs, subscribed, deity, holdsSdgnrs, false);
    }

    function _setUpBase() internal {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        borrower = makeAddr("gas-borrower");
        vm.deal(borrower, 1_000 ether);
        vm.deal(address(game), 10_000 ether);
        root = _giveWalletId(borrower);
        _grantSmurfBase(borrower, 8);
        gameRuntime = address(game).code;
        seeder = address(new SeizureGasSeeder());
        lens = new DegenerusGameLens();
        _etch(); SeizureGasSeeder(address(game)).fund(2, 500 ether); _unetch();
        _etch(); SeizureGasSeeder(address(game)).seedLevel(root, 8, 400); _unetch();
        _etch(); SeizureGasSeeder(address(game)).prime(); _unetch();
    }

    /// @dev `terminal` leaves level 1 unentered: game over settles the loan instead.
    function _setUpCase(uint256 smurfs, bool subscribed, bool deity, bool holdsSdgnrs, bool terminal) internal {
        _setUpBase();
        if (subscribed) _sub(root);
        uint32 lastChild;
        for (uint256 i; i < smurfs; ++i) {
            uint256 price = game.mintPrice();
            vm.prank(borrower);
            lastChild = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
            if (subscribed) _sub(lastChild);
        }
        if (deity) {
            vm.prank(borrower);
            // Symbol 31 is the last the seizure's registry scan reaches: its worst case.
            game.purchaseDeityPass{value: 200 ether}(smurfs == 0 ? root : lastChild, 31, bytes32(0));
        }
        if (holdsSdgnrs) {
            vm.prank(address(game));
            sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, borrower, 1e15);
        }
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        vm.prank(borrower);
        game.borrow(root, 1, type(uint256).max, q.principal);
        family = lens.loanOf(address(game), root).family;
        // One wei short of the repayment price (a one-level term costs its full term both at the
        // due level and at a game over before it): the auto-repay check reads everything, then defaults.
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), root);
        uint256 owed = info.principal * (10_000 + (info.dueLevel - info.startLevel) * 500) / 10_000;
        _setBalances(root, owed / 2, owed - owed / 2);
        if (!terminal) { _etch(); SeizureGasSeeder(address(game)).enterDue(1); _unetch(); }
    }

    function _setBalances(uint32 id, uint256 claimable, uint256 afking) internal {
        _etch(); SeizureGasSeeder(address(game)).setBalances(id, uint128(claimable), uint128(afking)); _unetch();
    }

    function _etch() internal { vm.etch(address(game), seeder.code); }
    function _unetch() internal { vm.etch(address(game), gameRuntime); _syncCoinflipFixtureDay(game.currentDayView_g542950()); }

    function _sub(uint32 id) internal {
        uint256 seat = _grantSeat(borrower);
        vm.prank(borrower);
        game.subscribe{value: 2 ether}(id, false, 1, seat);
    }

    function _measure(string memory label) internal returns (uint256 used) {
        used = _measureAs(label, address(sdgnrs));
    }

    function _measureAs(string memory label, address expectedPayee) internal returns (uint256 used) {
        _etch();
        uint256 snapshot = vm.snapshotState();
        uint256 before = gasleft();
        SeizureGasSeeder(address(game)).seize();
        used = before - gasleft();
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(label, address(this), address(game), abi.encodeCall(SeizureGasSeeder.seize, ()));
            SeizureGasSeeder(address(game)).seize();
        }
        _unetch();
        emit log_named_uint(label, used);
        (, address payee, ) = game.resolveAccount_g7029(root, address(0));
        assertEq(payee, expectedPayee, expectedPayee == borrower ? "auto-repaid" : "seized");
        uint256 bound = MineFlipGasBounds.LOAN_SEIZE_BASE + family * MineFlipGasBounds.LOAN_SEIZE_SUB
            + MineFlipGasBounds.LOAN_SEIZE_DEITY + MineFlipGasBounds.LOAN_SEIZE_TAIL;
        emit log_named_uint("admission_bound", bound);
        assertLe(used, bound, "the admission estimate covers the cold seizure");
    }
}

contract LoanSeizureGasLone is LoanSeizureGasBase {
    function setUp() public { _setUpCase(0, false, false, false); }
    function test_Gas_SeizeLoneAccount() public { _measure("seize_lone_cold"); }
}

contract LoanSeizureGasMainSdgnrs is LoanSeizureGasBase {
    function setUp() public { _setUpCase(0, true, false, true); }
    function test_Gas_SeizeMainWithRunAndSdgnrs() public { _measure("seize_main_run_sdgnrs_cold"); }
}

contract LoanSeizureGasFamily is LoanSeizureGasBase {
    function setUp() public { _setUpCase(5, true, false, true); }
    function test_Gas_SeizeMainWithFiveSubscribedSmurfs() public { _measure("seize_main_5_smurfs_6_runs_cold"); }
}

contract LoanSeizureGasWorst is LoanSeizureGasBase {
    function setUp() public { _setUpCase(5, true, true, true); }
    function test_Gas_SeizeWorstFamilyWithDeitySmurf() public { _measure("seize_worst_family_deity_cold"); }
}

/// @notice A borrower whose balances cover the full-term amount repays at the due level instead.
contract LoanAutoRepayGas is LoanSeizureGasBase {
    function setUp() public {
        _setUpCase(5, true, true, true);
        _setBalances(root, 1, 100 ether);
    }
    function test_Gas_AutoRepayWorstFamily() public { _measureAs("auto_repay_worst_family_cold", borrower); }
}

/// @notice Game over's loan checkpoint through the full engine stack, cold: the decision ran in
///         setUp (the purchase deadline, VRF alive), so the measured call settles the worst six-account deity
///         family and scans every later due level in one transaction.
abstract contract LoanTerminalGasBase is LoanSeizureGasBase {
    uint256 private constant GO_LOAN_STEP_SHIFT = 64;

    function _decideTerminal() internal {
        vm.warp(block.timestamp + 31 days);
        _etch(); SeizureGasSeeder(address(game)).completedDeadline(); _unetch();
        assertTrue(game.livenessTriggered(), "thirty completed rounds with VRF alive");
        game.mineRun(0);
        assertEq(_loanStep(), 1, "the decision owes settlement");
    }

    function _loanStep() internal view returns (uint256) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(GameSlots.GAME_OVER_STATE_PACKED))))
            >> GO_LOAN_STEP_SHIFT);
    }

    function _measureTerminal(string memory label) internal returns (uint256 used) {
        uint256 snapshot = vm.snapshotState();
        uint256 before = gasleft();
        game.mineRun(0);
        used = before - gasleft();
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(label, address(this), address(game), abi.encodeCall(game.mineRun, (0)));
            game.mineRun(0);
        }
        emit log_named_uint(label, used);
        assertEq(_loanStep(), 0, "one call finishes the book");
        assertLt(used, 10_000_000, "the checkpoint stays under the 10M chunk rule");
    }
}

contract LoanTerminalGasWorst is LoanTerminalGasBase {
    function setUp() public {
        _setUpCase(5, true, true, true, true);
        _decideTerminal();
    }

    function test_Gas_TerminalWorstFamilyAndFullScan() public {
        uint256 used = _measureTerminal("terminal_worst_family_and_99_level_scan_cold");
        (, address payee, ) = game.resolveAccount_g7029(root, address(0));
        assertEq(payee, address(sdgnrs), "seized");
        uint256 bound = MineFlipGasBounds.LOAN_SEIZE_BASE + family * MineFlipGasBounds.LOAN_SEIZE_SUB
            + MineFlipGasBounds.LOAN_SEIZE_DEITY + 99 * MineFlipGasBounds.LOAN_TERMINAL_LEVEL
            + MineFlipGasBounds.LOAN_SEIZE_TAIL;
        emit log_named_uint("admission_bound_plus_scan", bound);
        assertLe(used, bound + MineFlipGasBounds.ENGINE_BOUNDARY + MineFlipGasBounds.ENGINE_RETURN,
            "the admission estimates cover the cold checkpoint");
    }
}

/// @notice The scan alone: 99 cold empty levels, against the per-level admission estimate.
contract LoanTerminalGasEmptyScan is LoanTerminalGasBase {
    function setUp() public {
        _setUpBase();
        _decideTerminal();
    }

    function test_Gas_TerminalEmptyScan() public {
        uint256 used = _measureTerminal("terminal_99_level_empty_scan_cold");
        assertLe(used, 99 * MineFlipGasBounds.LOAN_TERMINAL_LEVEL + MineFlipGasBounds.LOAN_SEIZE_TAIL
            + MineFlipGasBounds.ENGINE_BOUNDARY + MineFlipGasBounds.ENGINE_RETURN,
            "the per-level estimate covers a cold empty level");
    }
}

/// @notice Player-paid entry points, for the record.
contract LoanEntryGas is LoanSeizureGasBase {
    function setUp() public { _setUpCase(0, false, false, false); }

    function test_Gas_BorrowAndRepay() public {
        address other = makeAddr("gas-other");
        uint32 id = _giveWalletId(other);
        _etch(); SeizureGasSeeder(address(game)).seedLevel(id, 8, 400); _unetch();
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, 5, type(uint256).max);
        vm.prank(other);
        game.borrow(id, 5, type(uint256).max, q.principal);
        emit log_named_uint("borrow_gas", vm.lastCallGas().gasTotalUsed);
        uint256 owed = lens.loanOf(address(game), id).owed;
        vm.deal(other, owed);
        vm.prank(other);
        game.clearDebtNow{value: owed}(id);
        emit log_named_uint("repay_gas", vm.lastCallGas().gasTotalUsed);
    }
}
