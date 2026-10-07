// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";

/// @notice Daily-spine degrade (DAILY-2): the opening-day protocol Decimator entry skips the
///         window when the settled consume lands below the entry minimum, instead of handing the
///         battle an amount it refuses (which would revert `applyDailyWord` for every caller).
/// @dev The seeded state is unreachable (the preview and the consume sum the same components);
///      it is produced by mocking the two coinflip legs so the preview clears the floor and the
///      consume does not. Run: forge test --match-path test/repro/DegradeAutoDecimatorBurn.t.sol -vv
contract DegradeAutoDecimatorBurnTest is DeployProtocol {
    address private constant HOUSE = ContractAddresses.SDGNRS;
    bytes32 private constant BURN_EVENT = keccak256("DecimatorBurn(uint32,uint256,uint64)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 21 days);
    }

    function _mockLegs(uint256 previewed, uint256 consumed) private {
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(Coinflip.previewFlipBacking.selector, HOUSE),
            abi.encode(previewed)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(Coinflip.consumeFlipBacking.selector, HOUSE, previewed),
            abi.encode(consumed)
        );
    }

    function _autoBurn() private returns (uint256 amount) {
        uint24 lvl = game.level() + 1;
        vm.prank(address(game));
        amount = coin.autoDecimatorBurn(lvl, 8000);
    }

    function _burnEvents(Vm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BURN_EVENT) ++n;
        }
    }

    /// @dev Preview clears the floor, the consume lands below it: the window is skipped, nothing
    ///      is minted, no entry is recorded and the call returns like an empty bankroll.
    function test_DustConsumeSkipsTheWindow() public {
        _mockLegs(5_000, 1999);
        uint256 supply = coin.totalSupply();
        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector), 0);
        vm.recordLogs();

        uint256 amount = _autoBurn();

        assertEq(amount, 0, "a dust consume reports a skipped window");
        assertEq(coin.totalSupply(), supply, "nothing minted");
        assertEq(coin.balanceOf(HOUSE), 0, "sDGNRS holds no wallet FLIP");
        assertEq(_burnEvents(vm.getRecordedLogs()), 0, "no entry recorded");
    }

    /// @dev Reachable shape: a consume at or above the floor still records the entry.
    function test_FloorConsumeStillRecords() public {
        _mockLegs(5_000, 2_000);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(DegenerusQuests.handleDecimator.selector),
            abi.encode(uint256(0), uint8(0), uint32(0), false)
        );
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector),
            abi.encode(uint64(1))
        );
        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector), 1);
        vm.recordLogs();

        uint256 amount = _autoBurn();

        assertEq(amount, 2_000, "the consumed backing is the entry");
        assertEq(_burnEvents(vm.getRecordedLogs()), 1, "one entry recorded");
    }
}
