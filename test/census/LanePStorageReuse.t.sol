// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {StorageCensus} from "./StorageCensus.sol";

/// @dev Synthetic boundary jumps are outside recorded transactions; all measured writes use production entrypoints.
contract LanePStorageReuseCensus is StorageCensus {
    address private constant ALICE = address(0xA11CE);
    uint32 private id;
    function setUp() public { _deployProtocol(); id = _giveWalletId(ALICE); _censusRegisterProtocol(); }
    function _must(string memory label, bool protocolPaid, address from, address to, bytes memory data) private {
        (bool ok,) = _ctx(label, protocolPaid, from, to, 0, data);
        assertTrue(ok, label);
    }
    function testCensusPeripheralGenerations() public {
        bytes32 code = bytes32("CENSUS");
        vm.prank(ALICE); affiliate.createAffiliateCode(code, 0);
        vm.store(address(gnrus), bytes32(uint256(4)), bytes32(uint256(uint160(address(0xCAFE)))));
        vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.balanceOf.selector, ALICE), abi.encode(uint256(100e12)));
        _censusBegin("lane-p-generations");
        uint256 startTime = vm.getBlockTimestamp();
        uint24 startDay = game.currentWallDayView();
        for (uint24 generation; generation < 6; ++generation) {
            assertEq(game.currentWallDayView(), startDay + generation, "fresh census wall day");
            uint24 level_ = 99 + generation * 100;
            uint256 word = uint256(vm.load(address(game), bytes32(0)));
            vm.store(address(game), bytes32(0), bytes32((word & ~(uint256(type(uint24).max) << 96)) | (uint256(level_) << 96)));
            _must("credit-prize", true, address(game), address(wwxrp), abi.encodeCall(wwxrp.creditPrize, (id, 100)));
            _must("incinerator-entry", false, ALICE, address(wwxrp), abi.encodeCall(wwxrp.enter, (0, 100)));
            _must("credit-withdraw", true, address(game), address(wwxrp), abi.encodeCall(wwxrp.creditPrize, (id, 25)));
            _must("withdraw-prize", false, ALICE, address(wwxrp), abi.encodeCall(wwxrp.withdraw, (0, 0)));
            _must("affiliate-score", false, address(game), address(affiliate), abi.encodeCall(affiliate.payAffiliate, (1_000, code, 456, uint24(1 + generation * 4), true, 0)));
            vm.store(address(gnrus), bytes32(uint256(2)), bytes32(uint256(1 + generation)));
            _must("charity-vote", false, ALICE, address(gnrus), abi.encodeCall(gnrus.vote, (0)));
            for (uint32 n; n < 4; ++n) _must("baf-score", false, address(coinflip), address(jackpots), abi.encodeCall(jackpots.recordBafFlip, (id + n, uint24(10 + generation * 40), uint256(100 - n))));
            vm.prank(address(game)); coin.mintForGame(ALICE, 1000);
            uint24 day = game.currentDayView_g542950() + 1;
            _must("arm-draw", true, address(game), address(coinflip), abi.encodeCall(coinflip.armBafDraw, (day)));
            for (uint32 n; n < 4; ++n) _must("draw-deposit", false, ALICE, address(coinflip), abi.encodeCall(coinflip.depositCoinflip, (0, 100)));
            vm.warp(startTime + (uint256(generation) + 1) * 1 days);
        }
        _censusEnd();
    }
}
