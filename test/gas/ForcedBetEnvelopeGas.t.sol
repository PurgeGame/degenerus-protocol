// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeAtomicReadFixture} from "./NativeAtomicWork.t.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Forced winning-bet/recirculation execution on complete prestates;
/// the variants change only the outcome controls.
contract ForcedBetEnvelopeGasTest is DeployProtocol {
    address private constant PLAYER = address(0xBE7CA1);

    function setUp() public {
        _deployProtocol();
        _giveWalletId(PLAYER);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 1_000_000 ether);
        vm.deal(PLAYER, 10_000 ether);
        vm.prank(address(game));
        coin.mintForGame_g152734(PLAYER, 1_000_000);
        vm.etch(address(game), type(NativeAtomicReadFixture).runtimeCode);
        NativeAtomicReadFixture(payable(address(game))).fundFuture();
    }

    function test_CompleteWinningBetCalibrationPrestates() public {
        for (uint256 shape; shape < 6; ++shape) {
            uint256 snapshot = vm.snapshotState();
            this.check(shape);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function check(uint256 shape) external {
        require(msg.sender == address(this), "fixture self-call");
        NativeAtomicReadFixture host = NativeAtomicReadFixture(payable(address(game)));
        uint8 currency = shape < 4 ? 0 : 1;
        uint8 spins = shape % 2 == 0 ? 1 : currency == 0 ? 25 : 15;
        uint128 stake = currency == 1 ? 100 : shape < 2 ? 1 ether : 100 ether;
        vm.prank(PLAYER);
        game.betDegenerette{value: currency == 0 ? uint256(stake) * spins : 0}(0, currency, stake, spins, 9);
        host.publishRead();
        host.setCommittedWord(0xBEEF1234); // Word 1 is the unpublished sentinel.
        MineFlipGas.Result memory result = host.workBet(14_000_000);
        assertTrue(result.done, "the full immutable bet executes");
        assertEq(result.rewardBasis, 1, "one completed bet");
        assertEq(host.betCursor(), 1, "the atomic cursor commits");
    }
}
