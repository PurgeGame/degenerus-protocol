// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ColdTerminalSeeder} from "./AdvanceColdTerminalGas.t.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract TerminalRequestSeeder is ColdTerminalSeeder {
    /// @dev A write-side cohort at the terminal level, so the request also makes the one terminal swap.
    function queueWriteCohort(address owner, uint32 entries) external {
        _queueEntries(_seedWallet(owner), level + 1, entries, false);
    }
}

/// @notice The normal ending's own terminal request, cold: the decision and the loan book run first,
///         then the measured call makes the terminal ticket/foil swap, arms the request day and time
///         and sends the request (DegenerusGameGameOverModule admits it at RNG_TERMINAL_REQUEST +
///         100,000, then RNG_TERMINAL_REQUEST). The whole mineRun call is measured.
contract TerminalRequestGasTest is DeployProtocol, MinerloopGasProbe {
    uint256 private constant WORD = uint256(keccak256("cold-terminal-full-payout")) | 1;
    uint256 private constant ADMISSION = Bounds.RNG_TERMINAL_REQUEST + 100_000;

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint24 lastSealedDay = game.currentWallDayView() - 1;
        _seedLogicalFixtureDay(lastSealedDay);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, WORD, lastSealedDay);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TerminalRequestSeeder).runtimeCode);
        TerminalRequestSeeder(payable(address(game))).seed(WORD, 0);
        TerminalRequestSeeder(payable(address(game))).queueWriteCohort(address(0xC0FFEE), 4);
        vm.etch(address(game), original);
        vm.deal(address(game), 5000 ether);
        uint256 before = mockVRF.lastRequestId();
        game.mineRun(0); // decision
        game.mineRun(0); // the (empty) loan book
        assertEq(mockVRF.lastRequestId(), before, "no request before the loan book is settled");
    }

    function _measure(string memory label) private {
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this),
            abi.encodeCall(game.mineRun, (uint32(0))), ADMISSION + Bounds.TERMINAL_TAIL + 1_000_000);
        _report(label, r, ADMISSION);
        header ^= uint256(vm.load(address(game), bytes32(0)));
        assertEq((header >> (8 * GameSlots.TICKET_WRITE_SLOT_OFFSET)) & 1, 1, "the terminal ticket swap ran");
        assertTrue(game.rngLocked(), "terminal request accepted");
        assertLe(r.osakaExec, Bounds.RNG_TERMINAL_REQUEST, "Osaka terminal request call fits RNG_TERMINAL_REQUEST");
        assertLe(r.glamsterdamExec + r.stateGas, Bounds.RNG_TERMINAL_REQUEST,
            "Glamsterdam terminal request call fits RNG_TERMINAL_REQUEST");
        assertLe(r.glamsterdamExec + r.stateGas, ADMISSION,
            "Glamsterdam terminal request call fits the RNG_TERMINAL_REQUEST + 100,000 admission");
    }

    /// @notice On the source-shaped Chainlink coordinator with its 125k execution padding.
    function test_ColdTerminalRequestPaddedCoordinator() public {
        RequestCostCoordinator source = new RequestCostCoordinator(125_000);
        vm.etch(address(mockVRF), address(source).code);
        RequestCostCoordinator coordinator = RequestCostCoordinator(address(mockVRF));
        coordinator.seed(address(game), 1);
        uint256 subId = uint256(vm.load(address(game), bytes32(GameSlots.VRF_SUBSCRIPTION_ID)));
        if (subId != 1) coordinator.seedSubscription(subId, address(game), 100 ether);
        _measure("terminal_request_padded_coordinator");
        assertEq(coordinator.requests(address(game)), 1, "one terminal request");
    }

    /// @notice On the mock coordinator, whose first request creates four slots.
    function test_ColdTerminalRequestMockCoordinator() public {
        uint256 before = mockVRF.lastRequestId();
        _measure("terminal_request_mock_coordinator");
        assertEq(mockVRF.lastRequestId(), before + 1, "one terminal request");
    }
}
