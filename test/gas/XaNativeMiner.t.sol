// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Three sealed 100-box orders ensure work exceeds the unpaid million-gas floor.
///      Removed before execution/export: the benchmark runs only production bytecode.
contract XaNativeMinerSeed is DegenerusGame {
    function seed(address player, address miner) external {
        _registerWallet(player, type(uint256).max);
        _registerWallet(miner, type(uint256).max);
        level = 99;
        dailyIdx = _wallDay();
        dailyComplete = false;
        rngRequestDay = dailyIdx;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        purchaseStartDay = dailyIdx;
        _afkingResetDay = dailyIdx;
        subsFullyProcessed = true;
        _clearRngRequest();
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 12345;
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        _pendingBoxCount = 0;
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 0);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        (uint256 word,) = _decodeBoxOrder(BoxOrderLib.boSmalls(100), 100);
        word |= uint256(_walletIdOf(player))
            | BoxOrderLib.scoreCode(ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) << LB_SCORE_SHIFT;
        word |= word << LB_ENTRY_BITS | word << (2 * LB_ENTRY_BITS);
        uint256[] storage queue = boxQueue[_rngReadBuffer()];
        assembly ("memory-safe") {
            mstore(0, queue.slot)
            sstore(keccak256(0, 32), word)
        }
        boxReadCount = 3;
        boxCursor = 0;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(10_000 ether, 10_000 ether);
    }
}

contract XaNativeMinerTest is DeployProtocol, NativeGasExport {
    address private constant MINER = address(0xB0A200);

    function test_NativePositiveMinerReward() public {
        _deployProtocol(false);
        vm.warp(21_000 days + 82_621);
        vm.deal(address(game), 50_000 ether);
        bytes memory production = address(game).code;
        vm.etch(address(game), type(XaNativeMinerSeed).runtimeCode);
        XaNativeMinerSeed(payable(address(game))).seed(address(0xB0A100), MINER);
        vm.etch(address(game), production);
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
        this.measureAndExport();
    }

    /// @dev Isolation resets basefee at an external transaction boundary; set it inside
    /// this adapter before the nested production call, as a real native transaction does.
    function measureAndExport() external {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei);
        uint256 snapshot = vm.snapshotState();
        vm.prank(MINER);
        game.mineFlip(0);
        assertGt(coinflip.coinflipAmount(MINER), 0, "fixture must earn a positive miner stake");
        assertTrue(vm.revertToState(snapshot));
        _nativeFixture("human_miner_reward_300", MINER, address(game), abi.encodeCall(game.mineFlip, (0)));
    }
}
