// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {LoanSeizureGasBase, SeizureGasSeeder} from "./LoanSeizureGas.t.sol";

/// @notice One loan settlement priced under both gas schedules against its admission bound
///         (`LOAN_SEIZE + LOAN_SEIZE_TAIL`). The Osaka figure is measured exactly as
///         `LoanSeizureGas.t.sol` does; the same call is then replayed with state-diff recording
///         and re-priced by `GlamsterdamReprice` (execution delta plus state gas per new slot).
///         Both lenders already hold a DeityPass balance, so a seizure creates no lender-side slot;
///         every write lands on a slot that exists, and the new-slot count is logged and checked.
abstract contract LoanSeizureGlamsterdamBase is LoanSeizureGasBase {
    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;
    // The measured Osaka call opens on a cold Game; Glamsterdam charges 3,000 for it.
    uint256 private constant COLD_TARGET_DELTA = 400;

    bool internal vaultLender;

    function _setUpGlam(bool vault_, bool subscribed, bool deity, bool holdsSdgnrs) internal {
        vaultLender = vault_;
        _setUpCase(subscribed, deity, holdsSdgnrs);
    }

    function _beforeBorrow() internal override {
        if (!vaultLender) return;
        _setBalances(SDGNRS_ID, 1 ether, 0);
        _etch(); SeizureGasSeeder(address(game)).fund(VAULT_ID, 100 ether); _unetch();
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.setLiquidationBuyFallback, (true, 1 ether)), 0);
    }

    function _lender() internal view returns (address) {
        return vaultLender ? address(vault) : address(sdgnrs);
    }

    /// @dev `payee` is the account's payee after the unit: the lender on a seizure, the borrower on a repayment.
    function _glam(string memory label, address payee, bool deity) internal returns (uint256 total) {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        uint256 passesBefore = deityPass.balanceOf(_lender());
        assertGt(passesBefore, 0, "the lender's DeityPass balance slot exists");

        _etch();
        uint256 snapshot = vm.snapshotState();
        uint256 before = gasleft();
        SeizureGasSeeder(address(game)).seize();
        uint256 used = before - gasleft();
        assertTrue(vm.revertToState(snapshot));

        vm.startStateDiffRecording();
        SeizureGasSeeder(address(game)).seize();
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _unetch();

        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(used, acc, address(game));
        total = r.glamsterdamExec + COLD_TARGET_DELTA + r.stateGas;
        _logNewSlots(acc);

        uint256 bound = MineFlipGasBounds.LOAN_SEIZE + MineFlipGasBounds.LOAN_SEIZE_TAIL;
        emit log_named_string("unit", label);
        emit log_named_uint("osaka_total", used);
        emit log_named_uint("glamsterdam_exec", r.glamsterdamExec + COLD_TARGET_DELTA);
        emit log_named_uint("glamsterdam_state", r.stateGas);
        emit log_named_uint("glamsterdam_total", total);
        emit log_named_uint("new_slots", r.newSlots);
        emit log_named_uint("first_changes", r.firstChanges);
        emit log_named_uint("cold_accounts", r.coldAccounts);
        emit log_named_uint("bound", bound);
        emit log_named_int("margin", int256(bound) - int256(total));
        (, address actual, ) = game.resolveAccount_g7029(root, address(0));
        assertEq(actual, payee, "the unit took the intended branch");
        assertEq(deityPass.balanceOf(_lender()), passesBefore + (deity && payee == _lender() ? 1 : 0),
            "the pass follows a seized account");

        assertEq(r.newSlots, 0, "no unit-created slot: a new one adds 97,920 state gas");
        assertLe(used, bound, "Osaka: the admission bound covers the cold unit");
        assertLe(total, bound, "Glamsterdam: the admission bound covers the cold unit");
    }

    function _logNewSlots(VmSafe.AccountAccess[] memory acc) private {
        for (uint256 i; i < acc.length; ++i) {
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                if (a.isWrite && !a.reverted && a.previousValue == bytes32(0) && a.newValue != bytes32(0)) {
                    emit log_named_address("new_slot_account", a.account);
                    emit log_named_bytes32("new_slot", a.slot);
                }
            }
        }
    }
}

/// @dev The heaviest seizure: run cancellation, cold symbol-31 deity transfer, native sDGNRS burn.
contract LoanSeizureGlamSdgnrsWorst is LoanSeizureGlamsterdamBase {
    function setUp() public { _setUpGlam(false, true, true, true); }
    function test_Gas_Glamsterdam_SdgnrsRunDeitySdgnrs() public { _glam("sdgnrs_run_deity_sdgnrs", address(sdgnrs), true); }
}

contract LoanSeizureGlamVaultWorst is LoanSeizureGlamsterdamBase {
    function setUp() public { _setUpGlam(true, true, true, true); }
    function test_Gas_Glamsterdam_VaultRunDeitySdgnrs() public { _glam("vault_run_deity_sdgnrs", address(vault), true); }
}

contract LoanSeizureGlamSdgnrsRunSdgnrs is LoanSeizureGlamsterdamBase {
    function setUp() public { _setUpGlam(false, true, false, true); }
    function test_Gas_Glamsterdam_SdgnrsRunSdgnrs() public { _glam("sdgnrs_run_sdgnrs", address(sdgnrs), false); }
}

contract LoanSeizureGlamVaultRunSdgnrs is LoanSeizureGlamsterdamBase {
    function setUp() public { _setUpGlam(true, true, false, true); }
    function test_Gas_Glamsterdam_VaultRunSdgnrs() public { _glam("vault_run_sdgnrs", address(vault), false); }
}

contract LoanSeizureGlamSdgnrsLone is LoanSeizureGlamsterdamBase {
    function setUp() public { _setUpGlam(false, false, false, false); }
    function test_Gas_Glamsterdam_SdgnrsLone() public { _glam("sdgnrs_lone", address(sdgnrs), false); }
}

/// @dev The other branch of the same admitted unit: the borrower's balances cover the full term.
contract LoanSeizureGlamSdgnrsAutoRepay is LoanSeizureGlamsterdamBase {
    function setUp() public {
        _setUpGlam(false, true, true, true);
        _setBalances(root, 1, 100 ether);
    }
    function test_Gas_Glamsterdam_SdgnrsAutoRepay() public { _glam("sdgnrs_auto_repay", borrower, true); }
}

contract LoanSeizureGlamVaultAutoRepay is LoanSeizureGlamsterdamBase {
    function setUp() public {
        _setUpGlam(true, true, true, true);
        _setBalances(root, 1, 100 ether);
    }
    function test_Gas_Glamsterdam_VaultAutoRepay() public { _glam("vault_auto_repay", borrower, true); }
}
