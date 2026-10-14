// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

contract SeizureGasSeeder is DegenerusGameStorage {
    function fund(uint32 id, uint128 claimable) external {
        balancesPacked[id] += claimable;
        claimablePool += claimable;
    }
    function seedLevel(uint32 id, uint24 level_, uint32 entries) external { _queueEntries(id, level_, entries, false); }
    /// @dev Record yesterday's word and seal today, so subscriptions open as on an ordinary day.
    function prime() external {
        uint24 day = _simulatedDayIndex();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        purchaseStartDay = day;
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
abstract contract LoanSeizureGasBase is DeployProtocol {
    address internal borrower;
    uint32 internal root;
    uint256 internal family;
    bytes internal gameRuntime;
    address internal seeder;
    DegenerusGameLens internal lens;

    function _setUpCase(uint256 smurfs, bool subscribed, bool deity, bool holdsSdgnrs) internal {
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
            sdgnrs.transferFromPool(sDGNRS.Pool.Reward, borrower, 1e15);
        }
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1);
        vm.prank(borrower);
        game.borrow(root, 1, q.principal);
        family = lens.loanOf(address(game), root).family;
        _etch(); SeizureGasSeeder(address(game)).enterDue(1); _unetch();
    }

    function _etch() internal { vm.etch(address(game), seeder.code); }
    function _unetch() internal { vm.etch(address(game), gameRuntime); }

    function _sub(uint32 id) internal {
        uint256 seat = _grantSeat(borrower);
        vm.prank(borrower);
        game.subscribe{value: 2 ether}(id, false, false, 1, 0, seat);
    }

    function _measure(string memory label) internal returns (uint256 used) {
        _etch();
        uint256 before = gasleft();
        SeizureGasSeeder(address(game)).seize();
        used = before - gasleft();
        _unetch();
        emit log_named_uint(label, used);
        (, address payee, ) = game.resolveAccount(root, address(0));
        assertEq(payee, address(sdgnrs), "seized");
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

/// @notice Player-paid entry points, for the record.
contract LoanEntryGas is LoanSeizureGasBase {
    function setUp() public { _setUpCase(0, false, false, false); }

    function test_Gas_BorrowAndRepay() public {
        address other = makeAddr("gas-other");
        uint32 id = _giveWalletId(other);
        _etch(); SeizureGasSeeder(address(game)).seedLevel(id, 8, 400); _unetch();
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, 5);
        vm.prank(other);
        game.borrow(id, 5, q.principal);
        emit log_named_uint("borrow_gas", vm.lastCallGas().gasTotalUsed);
        uint256 owed = lens.loanOf(address(game), id).owed;
        vm.deal(other, owed);
        vm.prank(other);
        game.repay{value: owed}(id);
        emit log_named_uint("repay_gas", vm.lastCallGas().gasTotalUsed);
    }
}
