// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipRequestGasTest, RequestCloseProbe} from "./MineFlipRequestGas.t.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @dev Uses the established complete native request fixtures and production
///      delegate dispatcher, with an independently cross-checked warm replay.
contract BoundedRequestGasTest is MineFlipRequestGasTest, BoundedGasProbe {
    // Dispatcher and caller frame headroom above the measured operation.
    uint256 private constant FRAME_GAS = 1_000_000;
    // MinerAction.RequestMidday.
    uint8 private constant ACTION_REQUEST_MIDDAY = 17;
    // The coordinator read inside selection admits EXTERNAL_READ_GAS (50k) plus its EIP-150
    // share (793), the 10k call overhead and VRF_READ_RESERVE (200k) above the meter floor.
    uint256 private constant SELECTION_READ_ADMISSION = 50_000 + 793 + 10_000 + 200_000;

    function _configureBounded(Scenario scenario) private {
        this.configure(scenario);
        // Retain the realistic coordinator storage and checks. A gas-burning
        // floor absorbs cold surcharges and cannot measure a warm/cold delta.
        RequestCostCoordinator source = new RequestCostCoordinator(0);
        vm.etch(address(coordinator), address(source).code);
    }
    function test_BoundedDaily() public {
        _configureBounded(Scenario.Daily);
        _measureBounded("request_daily", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }
    function test_BoundedDailyTransition() public {
        _configureBounded(Scenario.Transition);
        _measureBounded("request_transition", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }
    function test_BoundedMidday() public {
        _configureBounded(Scenario.Midday);
        _measureBounded("request_midday", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (false)), false);
    }
    function test_BoundedDailyRedemption() public {
        _configureBounded(Scenario.DailyRedeem);
        _measureBounded("request_redemption", address(host), address(this), 0,
            abi.encodeCall(host.requestOnly, (true)), false);
    }

    /// @dev Cold frame gas of one call, priced at 1 gwei inside its isolated transaction.
    function feeMeasured(address target, address sender, bytes calldata data, uint256 cap)
        external returns (uint256 used, bytes memory result)
    {
        require(msg.sender == address(this), "measurement self-call");
        vm.fee(1 gwei);
        vm.prank(sender);
        bool ok;
        (ok, result) = target.call{gas: cap}(data);
        VmSafe.Gas memory g = vm.lastCallGas();
        used = uint256(g.gasLimit) - uint256(g.gasRemaining);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    /// @dev Cold Osaka frame, then a recorded replay from the same pre-state, repriced. Leaves the
    ///      cold call's post-state in place.
    function _glamsterdam(string memory label, address target, address sender, bytes memory data,
        uint256 cap, uint256 bound) private returns (GlamsterdamReprice.Result memory r, bytes memory result)
    {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        uint256 snap = vm.snapshotState();
        uint256 used;
        (used, result) = this.feeMeasured(target, sender, data, cap);
        uint256 coldPost = vm.snapshotState();
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        (, bytes memory replay) = this.feeMeasured(target, sender, data, cap);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        assertEq(keccak256(replay), keccak256(result), "recorded replay returns the same result");
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        r = GlamsterdamReprice.reprice(used, acc, target);
        assertTrue(vm.revertToState(coldPost));
        vm.deleteStateSnapshot(coldPost);
        vm.deleteStateSnapshot(snap);
        emit log_named_string("unit", label);
        emit log_named_uint("osaka", r.osakaExec);
        emit log_named_uint("glamsterdam_exec", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state", r.stateGas);
        emit log_named_uint("glamsterdam_total", r.glamsterdamExec + r.stateGas);
        emit log_named_uint("new_slots", r.newSlots);
        emit log_named_uint("bound", bound);
    }

    /// @dev The mid-day request worker the miner admits at RNG_MIDDAY_REQUEST, on the padded
    ///      coordinator, at both prices.
    function _midday(Scenario scenario, string memory label) private {
        this.configure(scenario);
        (GlamsterdamReprice.Result memory r,) = _glamsterdam(label, address(host),
            _shape() == 3 ? BURNER : address(this), abi.encodeCall(host.requestOnly, (false)),
            Bounds.RNG_MIDDAY_REQUEST + FRAME_GAS, Bounds.RNG_MIDDAY_REQUEST);
        assertLe(r.osakaExec, Bounds.RNG_MIDDAY_REQUEST, "Osaka mid-day request fits RNG_MIDDAY_REQUEST");
        assertLe(r.glamsterdamExec + r.stateGas, Bounds.RNG_MIDDAY_REQUEST,
            "Glamsterdam mid-day request fits RNG_MIDDAY_REQUEST");
        _assertRequested();
    }
    function test_GlamsterdamMidday() public { _midday(Scenario.Midday, "midday"); }
    function test_GlamsterdamMiddayTicketSwap() public { _midday(Scenario.TicketSwap, "midday_ticket_swap"); }
    function test_GlamsterdamMiddayTicketActivation() public {
        _midday(Scenario.TicketActivation, "midday_ticket_activation");
    }
    function test_GlamsterdamMiddayCredit() public { _midday(Scenario.Credit, "midday_credit"); }
    function test_GlamsterdamMiddayFinalDay() public { _midday(Scenario.FinalDay, "midday_final_day"); }

    /// @dev The nonempty redemption close alone, every backing and funding shape.
    function _close(Scenario scenario, string memory label) private {
        this.configure(scenario);
        vm.etch(ContractAddresses.GAME_RNG_MODULE, type(RequestCloseProbe).runtimeCode);
        (GlamsterdamReprice.Result memory r,) = _glamsterdam(label, address(host), address(this),
            abi.encodeCall(host.closeOnly, ()), Bounds.RNG_REDEMPTION_CLOSE + FRAME_GAS, Bounds.RNG_REDEMPTION_CLOSE);
        assertLe(r.osakaExec, Bounds.RNG_REDEMPTION_CLOSE, "Osaka close fits RNG_REDEMPTION_CLOSE");
        assertLe(r.glamsterdamExec + r.stateGas, Bounds.RNG_REDEMPTION_CLOSE,
            "Glamsterdam close fits RNG_REDEMPTION_CLOSE");
        (uint32 open, uint32 settling,, uint256 escrow) = sdgnrs.redemptionBatchState();
        assertEq(open, 2, "close opened the next batch");
        assertEq(settling, 1, "close froze the burned batch");
        assertEq(escrow, 0, "close consumed the escrow");
    }
    function test_GlamsterdamCloseEth() public { _close(Scenario.RedeemEth, "close_eth"); }
    function test_GlamsterdamCloseSteth() public { _close(Scenario.RedeemSteth, "close_steth"); }
    function test_GlamsterdamCloseMixed() public { _close(Scenario.RedeemMixed, "close_mixed"); }
    function test_GlamsterdamCloseStoredOnly() public { _close(Scenario.RedeemStored, "close_stored"); }
    function test_GlamsterdamCloseCarryOnly() public { _close(Scenario.RedeemCarry, "close_carry"); }

    /// @notice The deepest miner selection: every gate, the Craps maintenance read, a below-threshold
    ///         queue paid by the caller's donated credit and the coordinator's native-balance read,
    ///         through the production facade and miner module.
    function test_GlamsterdamSelectionWithCreditAndCoordinatorRead() public {
        _configureBounded(Scenario.Credit);
        (GlamsterdamReprice.Result memory r, bytes memory result) = _glamsterdam("selection_credit_read",
            address(game), BURNER, abi.encodeCall(game.minerAction, ()), 2_000_000, Bounds.ENGINE_SELECTION);
        assertEq(abi.decode(result, (uint8)), ACTION_REQUEST_MIDDAY, "selection reached the mid-day request");
        uint256 total = r.glamsterdamExec + r.stateGas;
        assertEq(r.sstores, 0, "selection writes nothing");
        assertLe(r.osakaExec, Bounds.ENGINE_SELECTION, "Osaka selection fits ENGINE_SELECTION");
        assertLe(total, Bounds.ENGINE_SELECTION, "Glamsterdam selection fits ENGINE_SELECTION");
        // The selection admission (ENGINE_SELECTION + ENGINE_RETURN) must still hold the read's own
        // admission after everything selection spends, so the read never refuses a committed prefix.
        emit log_named_uint("selection_plus_read_admission", total + SELECTION_READ_ADMISSION);
        assertLe(total + SELECTION_READ_ADMISSION, Bounds.ENGINE_SELECTION + Bounds.ENGINE_RETURN,
            "selection admission covers the selection and the coordinator read's admission");
    }
}
