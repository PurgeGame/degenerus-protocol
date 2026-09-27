// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Full production award path, including Coinflip, the Game's sDGNRS leg and the trophy.
///      A controlled qualifying receipt isolates this cost from the random dice simulation.
contract JackpotBattleAwardsGasTest is DeployProtocol {
    address private constant WINNER = address(0xBEEF);

    function setUp() public {
        _deployProtocol();
        crapsBattle.seedProgressive(500_000_000 ether);
        vm.etch(ContractAddresses.CRAPS, type(CrapsBattle).runtimeCode);
        // An old, unclaimed record reaches the largest accrued record-pool share.
        vm.warp(block.timestamp + 200 days);
    }

    function test_RealRiuRecordCreditAndTrophy() public {
        vm.prank(ContractAddresses.GAME);
        uint256 beforeGas = gasleft();
        CrapsBattle(ContractAddresses.CRAPS).rewardJackpotBattle(keccak256("draw"), WINNER, 360_000, 1_200_000);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("REAL_BATTLE_RIU_AND_RECORD_AWARD_GAS", used);
        assertEq(CrapsBattle(ContractAddresses.CRAPS).progressivePool(), 450_000_000 ether);
        assertEq(coinflip.biggestDiceRunEver(), 1_200_000);
        assertEq(coinflip.recordPool(), 2500 ether);
        assertEq(recordBounty.ownerOf(4), WINNER);
        assertGt(coinflip.coinflipAmount(WINNER), 7500 ether);
        assertGt(sdgnrs.balanceOf(WINNER), 0);
        uint256 passes = uint256(vm.load(ContractAddresses.CRAPS, keccak256(abi.encode(WINNER, uint256(15)))));
        assertGt(uint64(passes), 0);
        assertLt(used, 400_000, "battle award path exceeded its gas allowance");
    }
}
