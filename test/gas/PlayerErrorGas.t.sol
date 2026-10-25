// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";

/// @notice Successful hot paths used for paired native error-guard calibration.
contract PlayerErrorGasTest is DeployProtocol, NativeGasExport {
    address private constant PLAYER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    function setUp() public {
        _deployProtocol();
        _giveWalletId(PLAYER);
        _giveWalletId(RECIPIENT);
        vm.prank(address(game));
        coin.mintForGame_g152734(PLAYER, 1_000_000);
        vm.deal(PLAYER, 100 ether);
    }

    function testNativeTransferFresh() public {
        this.exportNativeFixture("flip-transfer-fresh", PLAYER, address(coin), abi.encodeCall(coin.transfer, (RECIPIENT, 1_000)));
    }

    function testNativeTransferExisting() public {
        vm.prank(address(game)); coin.mintForGame_g152734(RECIPIENT, 100);
        this.exportNativeFixture("flip-transfer-existing", PLAYER, address(coin), abi.encodeCall(coin.transfer, (RECIPIENT, 1_000)));
    }

    function testNativeTransferFiniteAllowance() public {
        vm.prank(PLAYER); coin.approve(address(this), 2_000);
        this.exportNativeFixture("flip-transferFrom-finite", address(this), address(coin), abi.encodeCall(coin.transferFrom, (PLAYER, RECIPIENT, 1_000)));
    }

    function testNativeDepositFresh() public {
        this.exportNativeFixture("playCoinflip-fresh", PLAYER, address(coinflip), abi.encodeCall(coinflip.playCoinflip, (0, 1_000)));
    }

    function testNativeDepositExisting() public {
        vm.prank(PLAYER); coinflip.playCoinflip(0, 1_000);
        this.exportNativeFixture("playCoinflip-existing", PLAYER, address(coinflip), abi.encodeCall(coinflip.playCoinflip, (0, 1_000)));
    }
}
