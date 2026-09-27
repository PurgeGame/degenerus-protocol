// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The jackpot slot winner's progressive award against the real Coinflip and Game, driven
///      through the harness tap on the table so a controlled qualifying score isolates its cost
///      from the random dice simulation.
contract JackpotBattleAwardsGasTest is DeployProtocol {
    address private constant WINNER = address(0xBEEF);

    function setUp() public {
        _deployProtocol();
        crapsBattle.seedProgressive(500_000_000 ether);
    }

    function test_RealRiuCreditAndPasses() public {
        uint256 beforeGas = gasleft();
        crapsBattle.payProgressiveAt(keccak256("draw"), WINNER, 360_000, 1_200_000);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("REAL_BATTLE_RIU_AWARD_GAS", used);
        assertEq(crapsBattle.progressivePool(), 450_000_000 ether);
        assertGt(coinflip.coinflipAmount(WINNER), 0);
        uint256 passes = uint256(vm.load(ContractAddresses.CRAPS, keccak256(abi.encode(WINNER, uint256(15)))));
        assertGt(uint64(passes), 0);
        assertLt(used, 400_000, "battle award path exceeded its gas allowance");
    }
}
