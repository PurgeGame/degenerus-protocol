// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CrapsTagHarness is CrapsBattle {
    function tag(uint256 amount, uint256 flags) external pure returns (uint256) {
        return _tag(amount, flags);
    }
}

contract WholeTokenBoundaries is DeployProtocol {
    CrapsTagHarness private tags;

    function setUp() public {
        _deployProtocol();
        tags = new CrapsTagHarness();
    }

    function test_TokenDecimalConventions() public view {
        assertEq(coin.decimals(), 0);
        assertEq(wwxrp.decimals(), 0);
        assertEq(sdgnrs.decimals(), 12);
        assertEq(dgnrs.decimals(), 12);
        assertEq(gnrus.decimals(), 18);
    }

    function test_FlipTicketChargeRoundsUpAndExactPricesStayExact() public {
        // Meet the initial 50 ETH prize target so the real FLIP redemption door opens.
        // Preserve the future-pool half of the shared word.
        bytes32 poolSlot = bytes32(uint256(2));
        uint256 pools = uint256(vm.load(address(game), poolSlot));
        vm.store(address(game), poolSlot, bytes32((pools & ~uint256(type(uint128).max)) | 60 ether));
        for (uint256 quantity = 100; quantity <= 103; ++quantity) {
            address player = address(uint160(0xFA00 + quantity));
            uint256 charge = (quantity * 250 + 99) / 100;
            vm.prank(address(game));
            coin.mintForGame(player, charge - 1);
            vm.expectRevert(FLIP.Insufficient.selector);
            vm.prank(player);
            game.redeemFlip(0, quantity);
            assertEq(coin.balanceOf(player), charge - 1, "failed purchase burned funds");
            vm.prank(address(game));
            coin.mintForGame(player, 1);
            vm.prank(player);
            game.redeemFlip(0, quantity);
            assertEq(coin.balanceOf(player), 0, "purchase did not charge the ceiling");
            assertEq(game.entriesOwedView(1, player), quantity / 100);
        }
    }

    function test_CrapsTagPreservesLowAmountBitsAndRealBurns() public {
        uint256[6] memory amounts = [uint256(1), 255, 256, 257, 25_000, 500_000];
        address player = makeAddr("integer-craps");
        for (uint256 i; i < amounts.length; ++i) {
            uint256 amount = amounts[i];
            for (uint256 flags; flags < 32; ++flags) {
                uint256 packed = tags.tag(amount, flags);
                assertEq(packed >> 8, amount);
                assertEq(packed & 0xff, flags);
            }
            vm.prank(address(game));
            coin.mintForGame(player, amount);
            uint256 encoded = tags.tag(amount, 0);
            uint32 id = _giveWalletId(player);
            vm.prank(ContractAddresses.CRAPS);
            coin.burnCoinForCraps(player, id, encoded);
            assertEq(coin.balanceOf(player), 0, "decoded burn spends the exact principal");
        }
    }

    function test_CrapsTagRejectsOverflowAndUnknownFlags() public {
        uint256 packed = tags.tag(type(uint248).max, 31);
        assertEq(packed >> 8, type(uint248).max);
        assertEq(packed & 0xff, 31);
        vm.expectRevert();
        tags.tag(uint256(type(uint248).max) + 1, 0);
        vm.expectRevert();
        tags.tag(1, 32);
        vm.expectRevert();
        tags.tag(1, 256);
        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert(FLIP.InvalidCrapsFlags.selector);
        coin.burnCoinForCraps(address(this), 0, (1 << 8) | 32);
    }

    function testFuzz_CrapsTagRoundTrip(uint248 amount, uint8 flags) public view {
        flags &= 31;
        uint256 packed = tags.tag(amount, flags);
        assertEq(packed >> 8, amount);
        assertEq(packed & 0xff, flags);
    }

    function test_WwxrpHugeSecondBurnSaturatesAnAlreadyNonzeroBucket() public {
        address player = makeAddr("maximum-wwxrp");
        vm.prank(address(game));
        wwxrp.mintPrize(player, 25);
        vm.prank(player);
        wwxrp.enter(0, 25);
        // The first burn leaves a nonzero raw score but zero total token supply.
        vm.prank(address(game));
        wwxrp.mintPrize(player, type(uint256).max);
        vm.prank(player);
        wwxrp.enter(0, type(uint256).max);
        uint24 day = game.currentDayView();
        uint8 bucket = wwxrp.bucketOf(day, game.walletIdOf(player));
        (uint256 raw, uint256 total, uint32 count) = wwxrp.bucketInfo(day, bucket);
        assertEq(raw, type(uint96).max);
        assertEq(total, type(uint96).max);
        assertEq(count, 2);
        assertEq(wwxrp.balanceOf(player), 0);
        vm.prank(address(game));
        wwxrp.mintPrize(player, 25);
        vm.prank(player);
        wwxrp.enter(0, 25);
        (, uint256 endpoint) = wwxrp.entryAt(day, bucket, 2);
        assertEq(endpoint, type(uint96).max, "post-cap interval has zero width");
    }
}
