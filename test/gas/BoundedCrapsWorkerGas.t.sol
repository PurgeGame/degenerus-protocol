// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsPins} from "../craps/CrapsPins.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

/// @dev Real CrapsBattle, JackpotBattle and engine bytecode during measurement;
/// Game and credit destinations use the established CrapsPins mocks.
contract BoundedCrapsWorkerGasTest is CrapsPins, BoundedGasProbe {
    CrapsViews private table;
    uint256 private constant WORD = 123456789;
    function setUp() public {
        _installPins();
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 100) * 1 days + 82_620);
        table = new CrapsViews();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }
    function _prepareDay(uint256 count) private returns (uint24 day) {
        day = GameTimeLib.currentDayIndex() + 1;
        for (uint256 i; i < count; ++i) {
            address player = address(uint160(0xCA0000 + i));
            game.registerWallet_g9539(player, true);
            game.setScore(player, table.SYBIL_SCORE_FLOOR());
            vm.prank(player); table.buyFutureCrapsDays(day, 1, false, uint32(0));
        }
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + uint256(day) - 1) * 1 days + 82_620);
        _setDailyWord(day, WORD);
        vm.prank(ContractAddresses.GAME); table.openBonusDay();
    }
    function _production() private {
        vm.etch(address(table), vm.getDeployedCode("CrapsBattle.sol:CrapsBattle"));
    }
    function _views() private {
        vm.etch(address(table), vm.getDeployedCode("CrapsViews.sol:CrapsViews"));
    }
    function _scheduled(string memory label, uint256 count, bool previous) private {
        uint24 day = _prepareDay(count);
        uint64 slot = uint64(uint256(day) * 8 + 1);
        vm.warp(vm.getBlockTimestamp() + 21 minutes);
        uint48 index = table.armWindow(slot);
        if (previous) {
            vm.warp(vm.getBlockTimestamp() + 6 hours);
            assertEq(table.armWindow(slot + 1), index);
        }
        _setWord(index, WORD + 1);
        game.setRngConsumerStage(6);
        _production();
        JackpotBattle api = JackpotBattle(address(table));
        if (previous) {
            vm.prank(ContractAddresses.GAME); api.runCrapsReadWork(index, 9_000_000);
            _views(); assertGt(table.dayStaked(day), 0); _production();
            ++slot;
        }
        _measureBounded(label, address(table), ContractAddresses.GAME, 0,
            abi.encodeCall(api.runCrapsReadWork, (index, uint256(9_000_000))), false);
        _views();
        assertEq(table.bonusCursorOf(slot), count + 2, "paid seats plus two protocol seats settled");
        assertTrue(table.rngCohortComplete(index), "finalization drained the cohort");
        assertGt(table.dayStaked(day), 0, "real day action was recorded");
        assertGt(coinflip.totalCredited(), 0);
    }
    function test_CrapsScheduledFirstDayAction() public { _scheduled("C_worker_first", 1, false); }
    function test_CrapsScheduledSixSeats() public { _scheduled("C_worker_six", 6, false); }
    function test_CrapsScheduledExistingDayAction() public { _scheduled("C_worker_existing", 1, true); }
    function test_CrapsDailyJackpotFinalization() public {
        uint24 day = _prepareDay(4);
        _startDailyBattle(table, day + 1, WORD, 50_000);
        JackpotBattle api = JackpotBattle(address(table));
        (uint64 slot,, bool started, bool complete) = api.jackpotProgress();
        assertTrue(started); assertFalse(complete);
        _production();
        _measureBounded("C_worker_daily", address(table), ContractAddresses.GAME, 0,
            abi.encodeCall(api.runDailyBattleWork, (uint256(9_000_000))), false);
        (,,, complete) = api.jackpotProgress();
        assertTrue(complete, "jackpot round finalized");
        _views(); assertEq(table.bonusCursorOf(slot), 6, "four paid and two protocol seats");
        assertGt(coinflip.totalCredited(), 0);
    }
}
