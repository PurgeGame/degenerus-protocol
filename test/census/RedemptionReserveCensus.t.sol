// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;


import {GameSlots} from "../helpers/GameSlots.sol";

import {StorageCensus} from "./StorageCensus.sol";
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionReserveHarness} from "../repro/RedemptionReserve.t.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

contract RedemptionReserveCensus is StorageCensus, RedemptionFixture {
    function setUp() public override {
        RedemptionFixture.setUp();
        GameFunding.credit(2, 1_000 ether);
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), 1_000 ether);
        _censusRegisterProtocol();
    }
    function _must(string memory label, address from, address to, bytes memory data) private {
        (bool ok,) = _ctx(label, true, from, to, 0, data);
        assertTrue(ok, label);
    }
    function _close(string memory label) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionReserveHarness).runtimeCode);
        _must(label, address(this), address(game), abi.encodeCall(RedemptionReserveHarness.close, ()));
        vm.etch(address(game), code);
    }
    function testCensusProtectedReserveGenerations() public {
        _censusBegin("lane-p-reserve-generations");
        vm.mockCall(address(game), abi.encodeWithSelector(game.rngConsumerStage_g379.selector), abi.encode(uint8(1)));
        for (uint32 batch = 1; batch <= 6; ++batch) {
            uint256 amount = sdgnrs.totalSupply() / 1000;
            _must("reserve-burn", alice, address(sdgnrs), abi.encodeCall(sdgnrs.burn, (amount)));
            _close("reserve-close");
            assertGt(game.redemptionReserve(), 0);
            uint256 beforeCredit = game.claimableWinningsOf(alice);
            _must("reserve-settle", address(game), address(sdgnrs),
                abi.encodeCall(sdgnrs.runRedemptionWork, (_wordForRoll(100), 9_000_000)));
            assertGt(game.claimableWinningsOf(alice), beforeCredit, "each measured claim is paid");
            _close("reserve-release");
            assertEq(game.redemptionReserve(), 0);
            assertEq(uint256(vm.load(address(game), bytes32(GameSlots.REDEMPTION_RESERVE_STORED))), 1);
        }
        _censusEnd();
    }
}
