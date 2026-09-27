// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins, MockCoinflip} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CrapsJackpotBattleAwardsTest is CrapsPins {
    CrapsViews private c;
    address private winner = address(0xBEEF);
    bytes32 private constant KEY = keccak256("jackpot battle-award");

    function setUp() public {
        _installPins();
        vm.cloneAccount(address(new MockCoinflip()), address(coinflip));
        c = new CrapsViews();
        c.seedProgressive(100_000_000 ether);
    }

    function test_OnlyGameCanSubmitAnAward() public {
        vm.expectRevert(CrapsBattle.OnlyGame.selector);
        c.rewardJackpotBattle(KEY, winner, 360_000, 1_200_000);
    }

    function test_ThresholdsAndPassSplitConserveThePool() public {
        uint256[7] memory scores = [uint256(0), 249_999, 250_000, 999_999, 1_000_000, 1_199_999, 1_200_000];
        for (uint256 i; i < scores.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            uint256 score = scores[i];
            uint256 gross = score >= 1_200_000 ? 10_000_000 ether : score >= 250_000 ? 5_000_000 ether : 0;
            uint256 recordBefore = coinflip.recordPool();
            vm.prank(ContractAddresses.GAME);
            c.rewardJackpotBattle(KEY, winner, score * 300 / 10_000, score);
            assertEq(c.progressivePool(), 100_000_000 ether - gross);
            assertEq(coinflip.diceRunArms(), score >= 1_000_000 ? 1 : 0);
            assertEq(coinflip.biggestDiceRunEver(), score >= 1_000_000 ? score : 0);
            (uint256 normal, uint256 high) = c.passCreditsOf(winner);
            uint256 passValue = normal * c.NORMAL_PASS_VALUE() + high * c.HIGH_PASS_VALUE();
            assertEq(passValue + coinflip.staked(winner), gross + recordBefore - coinflip.recordPool());
            assertEq(c.routineGoalDayOf(winner), 0, "jackpot battle cannot activate the event's repeat-win doubling");
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function test_RecordStillClaimsWhenRiuPoolIsEmptyAndOnlyImproves() public {
        c.seedProgressive(0);
        vm.startPrank(ContractAddresses.GAME);
        c.rewardJackpotBattle(KEY, winner, 30_000, 1_000_000);
        uint256 claimed = coinflip.staked(winner);
        assertGt(claimed, 0);
        c.rewardJackpotBattle(KEY, winner, 30_000, 1_000_000);
        assertEq(coinflip.staked(winner), claimed, "equal record claimed twice");
        c.rewardJackpotBattle(KEY, winner, 30_001, 1_000_001);
        assertGt(coinflip.staked(winner), claimed);
        vm.stopPrank();
    }

    function test_RiuPassAwardPreservesPreferredBoardAndSentinel() public {
        vm.prank(winner);
        c.setPreferredBoard(3 | (3 << 12) | (1 << 15));
        vm.prank(ContractAddresses.GAME);
        c.rewardJackpotBattle(KEY, winner, 7500, 250_000);
        assertEq(c.preferredBoardOf(winner), 3 | (3 << 12) | (1 << 15));
        uint256 word = uint256(c.extsload(keccak256(abi.encode(winner, uint256(15)))));
        assertNotEq(word & (uint256(1) << 84), 0);
    }

    function test_GasQualifiedBattleAwards() public {
        vm.prank(ContractAddresses.GAME);
        uint256 beforeGas = gasleft();
        c.rewardJackpotBattle(KEY, winner, 360_000, 1_200_000);
        emit log_named_uint("BATTLE_RIU_AND_RECORD_AWARD_GAS_MOCK_COINFLIP", beforeGas - gasleft());
    }
}
