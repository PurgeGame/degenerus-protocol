// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsPins} from "../craps/CrapsPins.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Inject only two deterministic rare outcomes. The witness tests settlement
/// ordering and pool accounting, not the probability of these engine outcomes.
contract UnpushedSidegameOutcomeEngine {
    function settleBattle(uint256, uint256 header, uint256, uint256 bankroll,
        uint256, uint48, uint256, uint256) external pure returns (Craps.SlipResult memory r)
    {
        address player = address(uint160(header));
        if (player == address(0xA11CE) || player == address(0xB0B)) {
            r.peakBankroll = bankroll * 120;
            r.unitsPlayed = (uint256(1) << 104) | ((r.peakBankroll / 1 ether) << 60);
            r.stop = Craps.SlipStop.Goal;
        }
        r.totalRolls = 1;
    }
}

/// @notice Residual payout-timing witness: the read stage's normal-cohort settlement and the
/// Game's jackpot stage consume the same live progressive; the read-cohort gate fixes the order.
/// The Game/VRF stages use the existing pinned fixture; fields, admission, arming,
/// and settlement use their production entrypoints. No award helper is called.
contract UnpushedSidegameRngSafety is CrapsPins {
    CrapsViews private table;
    JackpotBattle private api;
    uint48 private buffer;

    function setUp() public {
        _installPins();
        table = new CrapsViews();
        api = JackpotBattle(address(table));
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        uint256 dayStart = vm.getBlockTimestamp() + 1 days - elapsed;
        vm.warp(dayStart);
        uint24 day = table.currentDayIndex();
        _setIndex(0);
        _setDailyWord(day, 123456);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();

        vm.prank(address(0xA11CE));
        table.enterBonusBattle(0, 0, 1);
        vm.prank(address(0xB0B));
        table.enterBonusBattle(5, 0, 1);

        vm.warp(dayStart + 1 days);
        // The oldest closed scheduled field joins the next normal word before
        // its daily request; the daily jackpot is committed by that same request.
        (bool armed,) = _crank(table);
        assertTrue(armed);
        buffer = 0;
        assertEq(table.slotIndexOf(uint64(uint256(day) * 8 + 1)), buffer + 1);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        api.lockJackpotBattle(day + 1, 100 ether, 2);
        _setWord(buffer, 0xC0FFEE);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(7, 0xC0FFEE);
        api.appendJackpotBattle(new uint256[](0), 0, true);
        vm.stopPrank();

        table.seedProgressive(1_000_000 ether);
        vm.etch(ContractAddresses.CRAPS_ENGINE, address(new UnpushedSidegameOutcomeEngine()).code);
    }

    function _settleScheduled() private returns (uint256 award) {
        uint256 before = table.progressivePool();
        MineFlipGas.Result memory step = _readWork(table, buffer);
        assertTrue(step.progressed && step.rewardBasis != 0);
        return before - table.progressivePool();
    }

    function _settleJackpot() private {
        vm.prank(ContractAddresses.GAME);
        assertTrue(table.runDailyBattleWork(gasleft()).done);
    }

    /// @notice The witness no longer has two orders. Read-bound Craps cohorts are a gated read
    ///         consumer (stage 6), reachable only once the daily lock lifts, while the jackpot
    ///         battle advances inside the locked daily phase (6d0e64b09 / 60d31f775). So the
    ///         read stage's settlement of the scheduled field can never run ahead of the jackpot
    ///         stage of the request that sealed it: the progressive is consumed jackpot-first, always.
    function test_ReadStageSettlementWaitsForTheJackpotStageWithFrozenOutcomes() public {
        MineFlipGas.Result memory step = _readWork(table, buffer);
        assertFalse(step.progressed || step.rewardBasis != 0, "the scheduled cohort waits while the daily jackpot stage holds the lock");
        uint256 before = table.progressivePool();
        _settleJackpot();
        assertEq(before - table.progressivePool(), 100_000 ether, "the jackpot stage consumes the progressive first");
        // The daily phase ends with the jackpot stage; the lock lifts and the gated read
        // consumers, the scheduled Craps cohort among them, run on the same frozen outcomes.
        game.setRngLocked(false);
        uint256 aliceLast = _settleScheduled();
        assertEq(aliceLast, 90_000 ether);
    }
}
