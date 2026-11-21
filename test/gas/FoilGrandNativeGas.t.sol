// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameFoilCore} from "../../contracts/modules/DegenerusGameFoilCore.sol";

/// @dev Force the rare grand branch after foil generation. Every payout, pass and
/// FLIP credit is the real production implementation; only the RNG outcome is seeded.
contract FoilGrandNativeHost is DegenerusGame, DegenerusGameFoilCore, WalletSeed {
    function prepareGrand(address player) external {
        level = 19;
        dailyIdx = _wallDay();
        purchaseStartDay = dailyIdx;
        _seedWallet(player);
        _setPrizePools(50 ether, 400 ether);
        _setCurrentPrizePool(30 ether);
        yieldAccumulator = 20 ether;
    }
    function forceGrand(address player, uint8 golds, uint8 allGold) external {
        _pushFoilGrand(_walletIdOf(player), 20, golds, allGold);
    }
    function credit(address player) external view returns (uint256) {
        return _claimableOf(_walletIdOf(player));
    }
}

contract FoilGrandNativeGasTest is DeployProtocol, BoundedGasProbe, MinerloopGasProbe {
    FoilGrandNativeHost private host;
    address private constant PLAYER = address(0xF017CA1);
    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(FoilGrandNativeHost).runtimeCode);
        host = FoilGrandNativeHost(payable(address(game)));
        host.prepareGrand(PLAYER);
        vm.deal(address(game), 1_000 ether);
    }
    function test_GrandFourGoldLinesWithFreshPayoutLanes() public {
        uint256 before = host.credit(PLAYER);
        _measureBounded("foil-grand-four-gold-lines", address(host), address(this), 0,
            abi.encodeCall(host.forceGrand, (PLAYER, uint8(16), uint8(4))), false);
        assertEq(host.credit(PLAYER) - before, 100 ether, "real grand pays a quarter of the future pool");
    }
    /// @dev Glamsterdam: the forced grand push, one part of a pack admitted at canRun(FOIL_PACK, 100_000).
    function _glamsterdamGrand(string memory label, uint8 golds, uint8 allGold) private {
        uint256 before = host.credit(PLAYER);
        (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
            abi.encodeCall(host.forceGrand, (PLAYER, golds, allGold)), 10_000_000);
        vm.stopMappingRecording();
        assertEq(host.credit(PLAYER) - before, 100 ether, "real grand pays a quarter of the future pool");
        _report(label, r, Bounds.FOIL_PACK);
        emit log_named_uint("new_slots", r.newSlots);
        assertLe(r.glamsterdamExec + r.stateGas, Bounds.FOIL_PACK, "FOIL_PACK");
    }
    function test_GlamsterdamGrandFourGoldLines() public { _glamsterdamGrand("foil_grand_four_gold_lines", 16, 4); }
    function test_GlamsterdamGrandTwoGoldLines() public { _glamsterdamGrand("foil_grand_two_gold_lines", 8, 2); }

    function test_GrandTwoGoldLinesWithFreshPayoutLanes() public {
        uint256 before = host.credit(PLAYER);
        _measureBounded("foil-grand-two-gold-lines", address(host), address(this), 0,
            abi.encodeCall(host.forceGrand, (PLAYER, uint8(8), uint8(2))), false);
        assertEq(host.credit(PLAYER) - before, 100 ether, "real grand pays a quarter of the future pool");
    }
}
