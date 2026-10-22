// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {PurchaseDailyLevelOneSaturated} from "./PurchaseDailyWorstCase.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

contract StorageReusePurchaseHost is DegenerusGame {
    function phaseOnly() external returns (bytes memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runDailyPhase(uint256)", uint256(9_000_000)));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return result;
    }
}

/// @dev Full level-one draw, including all 50 credits, before its daily seal.
contract StorageReuseNativePurchaseTest is PurchaseDailyLevelOneSaturated, NativeGasExport {
    function _purchaseFixtureDay() internal pure override returns (uint24) { return 21_000; }

    function test_nativeLevelOneFiftyShareDraw() public {
        uint24 day = game.currentDayView();
        uint256 word = game.rngWordForDay(day);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, day);
        vm.etch(address(game), type(StorageReusePurchaseHost).runtimeCode);
        _nativeFixture("level_one_draw_50", address(0x8888), address(game),
            abi.encodeCall(StorageReusePurchaseHost.phaseOnly, ()));
        vm.recordLogs();
        StorageReusePurchaseHost(payable(address(game))).phaseOnly();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awards;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FLIP_WIN_SIG) ++awards;
        }
        assertEq(awards, 50, "all trait shares execute in the measured phase");
        assertFalse(game.rngLocked(), "draw completes its daily seal");
    }
}
