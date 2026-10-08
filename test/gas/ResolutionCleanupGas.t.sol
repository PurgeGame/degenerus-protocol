// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Run with --isolate. Measures complete production mineFlip transactions.
/// Only clock, published RNG, and window arming are fixture-controlled.
contract ResolutionCleanupGasTest is DeployProtocol {
    uint256 private constant WORD = 0xD1CEB00C;
    bytes private fixtureTableCode;

    function setUp() public {
        _deployProtocol();
        fixtureTableCode = address(crapsBattle).code;
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 3; ++i) {
            address player = address(uint160(0xCA1101 + i));
            vm.prank(address(coin)); game.registerWallet(player, true);
            vm.prank(address(game)); coin.mintForGame(player, 100_000_000);
        }
    }

    function _cycle(uint24 day, uint256 seats, string memory label) private {
        CrapsBattle table = CrapsBattle(address(crapsBattle));
        for (uint256 i; i < seats; ++i) {
            vm.prank(address(uint160(0xCA1101 + i)));
            table.buyFutureCrapsDays(0, day, 1, false, 0);
        }
        uint256 start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + day - 1) * 1 days + 82_620;
        vm.warp(start);
        RecyclingState.seedDailyWord(address(game), day, WORD);
        vm.prank(address(game)); table.openBonusDay();
        uint256[5] memory closes = [uint256(21 minutes), 6 hours + 4 minutes, 12 hours + 4 minutes,
            18 hours + 4 minutes, 1 days - 19 minutes];
        uint48 buffer;
        uint256 armGas;
        vm.etch(address(table), fixtureTableCode);
        for (uint256 i; i < 5; ++i) {
            vm.warp(start + closes[i]);
            buffer = crapsBattle.armWindow(uint64(uint256(day) * 8 + i + 1));
            armGas += vm.lastCallGas().gasTotalUsed;
        }
        vm.etch(address(table), type(CrapsBattle).runtimeCode);
        RecyclingState.seedWord(address(game), buffer, bytes32(WORD));
        uint256 state = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32((state & ~(uint256(0xffffff) << 24))
            | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192)));
        uint256 resolveGas;
        // The miner preserves one-field finalization per transaction.
        for (uint256 i; i < 5; ++i) {
            game.mineFlip(0);
            resolveGas += vm.lastCallGas().gasTotalUsed;
        }
        assertTrue(game.rngComplete(), "five fields must drain in five transactions");
        emit log_named_uint(string.concat(label, "-arm-execution-gas"), armGas);
        emit log_named_uint(string.concat(label, "-mineFlip-execution-gas"), resolveGas);
    }

    function test_CrapsFiveFieldsOneSeat() public {
        _cycle(game.currentDayView() + 1, 1, "one-seat");
    }

    function test_CrapsFiveFieldsThreeSeats() public {
        _cycle(game.currentDayView() + 1, 3, "three-seats");
    }
}
