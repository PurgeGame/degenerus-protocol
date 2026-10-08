// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Run with --isolate. Identical fixture works against the pre-packing source snapshot.
/// Every measured call uses production contracts; only RNG delivery and window opening are seeded.
contract IdPackingLifecycleGasTest is DeployProtocol {
    address constant A = address(0xCA1101);
    address constant B = address(0xCA1102);
    address constant C = address(0xCA1103);
    uint256 constant WORD = 0xD1CEB00C;
    bytes private fixtureTableCode;
    event Sample(string name, uint256 gross, int256 refund, uint256 charged, uint256 writes);

    function setUp() public {
        _deployProtocol();
        fixtureTableCode = address(crapsBattle).code;
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 3; ++i) {
            address player = address(uint160(A) + uint160(i));
            vm.prank(address(coin)); game.registerWallet(player, true);
            vm.prank(address(game)); coin.mintForGame(player, 100_000_000);
        }
    }

    function _sample(string memory name, address target) private returns (uint256 charged) {
        Vm.Gas memory g = vm.lastCallGas();
        (, bytes32[] memory writes) = vm.accesses(target);
        // Foundry reports the refund counter separately. Apply the transaction refund cap.
        uint256 refund = g.gasRefunded > 0 ? uint256(uint64(g.gasRefunded)) : 0;
        if (refund > g.gasTotalUsed / 5) refund = g.gasTotalUsed / 5;
        charged = g.gasTotalUsed - refund;
        emit Sample(name, g.gasTotalUsed, g.gasRefunded, charged, writes.length);
        emit log_named_uint(name, charged);
    }

    function _degCycle(uint256 n, string memory prefix) private returns (uint256 total) {
        RecyclingState.seedWriteBuffer(address(game), 1);
        for (uint256 i; i < n; ++i) {
            vm.record(); vm.prank(A);
            game.placeDegeneretteBet(0, 1, 100, 1, 9);
            total += _sample(string.concat(prefix, "-place-", vm.toString(i + 1)), address(game));
        }
        RecyclingState.seedWord(address(game), 1, bytes32(WORD));
        uint256 state = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32((state & ~(uint256(0xffffff) << 24))
            | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192)));
        vm.record();
        game.mineFlip(0);
        total += _sample(string.concat(prefix, "-resolve"), address(game));
        assertTrue(game.boxIndexComplete(1));
        emit log_named_uint(string.concat(prefix, "-lifecycle"), total);
    }

    function test_DegeneretteOneFreshAndReused() public {
        _degCycle(1, "deg-one-fresh"); _degCycle(1, "deg-one-reused");
    }
    function test_DegeneretteThreeFreshAndReused() public {
        _degCycle(3, "deg-three-fresh"); _degCycle(3, "deg-three-reused");
    }
    function test_DegeneretteThirtyTwoFreshAndReused() public {
        _degCycle(32, "deg-32-fresh"); _degCycle(32, "deg-32-reused");
    }

    function test_DecimatorBurnsAndTopup() public {
        uint24 lvl = game.level() + 1;
        bytes32 flags = bytes32(GameSlots.DECIMATOR_FLAGS);
        vm.store(address(game), flags, bytes32(uint256(vm.load(address(game), flags))
            | (uint256(1) << (GameSlots.DECIMATOR_FLAGS_OFFSET * 8))));
        bytes32 round = keccak256(abi.encode(uint256(lvl), GameSlots.DEC_BATTLE_ROUNDS));
        vm.store(address(game), round, bytes32(uint256(vm.load(address(game), round))
            | (uint256(game.currentDayView()) << 200)));
        for (uint256 i; i < 3; ++i) {
            vm.record(); vm.prank(address(uint160(A) + uint160(i)));
            coin.decimatorBurn(0, 2000, 0);
            _sample(string.concat("dec-burn-", vm.toString(i + 1)), address(game));
        }
        vm.record(); vm.prank(A); coin.decimatorBurn(0, 2000, 0);
        _sample("dec-topup", address(game));
    }

    function _crapsCycle(uint24 day, uint256 n, string memory prefix) private returns (uint256 total) {
        CrapsBattle table = CrapsBattle(address(crapsBattle));
        for (uint256 i; i < n; ++i) {
            vm.record(); vm.prank(address(uint160(A) + uint160(i)));
            table.buyFutureCrapsDays(0, day, 1, false, 0);
            total += _sample(string.concat(prefix, "-place-", vm.toString(i + 1)), address(table));
        }
        vm.record(); vm.prank(A);
        table.amendSlip(0, (uint256(day) << 67) | 1, 1);
        total += _sample(string.concat(prefix, "-amend"), address(table));
        uint256 start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + day - 1) * 1 days + 82_620;
        vm.warp(start);
        RecyclingState.seedDailyWord(address(game), day, WORD);
        vm.prank(address(game)); table.openBonusDay();
        uint256[5] memory closes = [uint256(21 minutes), 6 hours + 4 minutes, 12 hours + 4 minutes,
            18 hours + 4 minutes, 1 days - 19 minutes];
        uint48 buffer;
        vm.etch(address(table), fixtureTableCode);
        for (uint256 i; i < 5; ++i) {
            vm.warp(start + closes[i]);
            buffer = crapsBattle.armWindow(uint64(uint256(day) * 8 + i + 1));
        }
        vm.etch(address(table), type(CrapsBattle).runtimeCode);
        RecyclingState.seedWord(address(game), buffer, bytes32(WORD));
        for (uint256 i; i < 5; ++i) {
            vm.record(); vm.prank(address(table));
            table.resolveRngSlot(uint64(uint256(day) * 8 + i + 1), 20_000_000);
            total += _sample(string.concat(prefix, "-resolve-window-", vm.toString(i + 1)), address(table));
        }
        emit log_named_uint(string.concat(prefix, "-lifecycle"), total);
    }

    function test_CrapsOneFreshAndReused() public {
        uint24 day = GameTimeLib.currentDayIndex() + 1;
        _crapsCycle(day, 1, "craps-one-fresh");
        vm.warp(block.timestamp + 63 days);
        _crapsCycle(day + 64, 1, "craps-one-reused");
    }
    function test_CrapsThreeFreshAndReused() public {
        uint24 day = GameTimeLib.currentDayIndex() + 1;
        _crapsCycle(day, 3, "craps-three-fresh");
        vm.warp(block.timestamp + 63 days);
        _crapsCycle(day + 64, 3, "craps-three-reused");
    }
}
