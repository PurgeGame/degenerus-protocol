// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract RangeAwardSeeder is DegenerusGame, WalletSeed {
    function prepare(address player, uint256 passes, bool topup) external {
        _seedHalfPasses(player, passes);
        if (topup) _queueEntryRange(_walletIdOf(player), 1, 100, 4);
    }
}

contract RangeAwardGasTest is DeployProtocol {
    address private constant BUYER = address(0xABC125);

    function setUp() public {
        _deployProtocol();
        vm.deal(BUYER, 100 ether);
        _prepare(4, false);
    }

    function _prepare(uint256 passes, bool topup) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RangeAwardSeeder).runtimeCode);
        RangeAwardSeeder(payable(address(game))).prepare(BUYER, passes, topup);
        vm.etch(address(game), code);
    }

    function _claim(uint256 passes, bool topup, string memory name) private {
        if (passes != 4 || topup) _prepare(passes, topup);
        uint32 id = game.walletIdOf(BUYER);
        game.claimWhalePass(id);
        emit log_named_uint(name, vm.snapshotGasLastCall("range-award", name));
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint32 expected = uint32((passes / 4) * 4) + (topup ? 4 : 0);
            uint256 rem = passes % 4;
            if (rem >= 2 && (lvl - 1) % 2 == 0) expected += 4;
            if (rem == 1 && (lvl - 1) % 4 == 0) expected += 4;
            if (rem == 3 && lvl >= 2 && (lvl - 2) % 4 == 0) expected += 4;
            assertEq(game.entriesOwedView(lvl, BUYER), expected, "award distribution");
        }
    }

    function test_WhaleClaim100() public { _claim(4, false, "claim-100"); }
    function test_WhaleClaimTopup100() public { _claim(4, true, "claim-topup-100"); }
    function test_OneHalfPass25() public { _claim(1, false, "claim-stride4-25"); }
    function test_TwoHalfPasses50() public { _claim(2, false, "claim-stride2-50"); }
    function test_ThreeHalfPasses75() public { _claim(3, false, "claim-mixed-75"); }
    function test_SevenHalfPasses175() public { _claim(7, false, "claim-mixed-175"); }

    function test_DeityBuy100() public {
        vm.prank(BUYER);
        game.purchaseDeityPass{value: 24 ether}(0, 4, bytes32(0));
        emit log_named_uint("deity-buy-100", vm.snapshotGasLastCall("range-award", "deity-buy-100"));
        for (uint24 lvl = 1; lvl <= 100; ++lvl) assertEq(game.entriesOwedView(lvl, BUYER), 4);
    }

    function test_LazyBuy10() public {
        vm.prank(BUYER);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        emit log_named_uint("lazy-buy-10", vm.snapshotGasLastCall("range-award", "lazy-buy-10"));
        for (uint24 lvl = 2; lvl <= 10; ++lvl) assertEq(game.entriesOwedView(lvl, BUYER), 4);
    }
}
