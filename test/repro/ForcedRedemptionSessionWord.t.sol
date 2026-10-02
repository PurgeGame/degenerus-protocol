// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @dev Real burns and requests: a recovered session gives manual claims and the
/// mandatory keeper drain identical entropy, then permits buffer reuse.
contract ForcedRedemptionSessionWordTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    uint256 private constant WORD = 7419;

    function _request() private {
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "real daily request");
    }

    function _complete() private {
        for (uint256 i; i < 500 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete(), "bounded compulsory work finishes");
    }

    function _run(bool stalled, bool batch, bool terminal) private {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _complete();
        mockStETH.mint(address(sdgnrs), 2000 ether);
        address[3] memory owners = [ALICE, BOB, CAROL];
        uint24 burnDay;
        for (uint256 i; i < owners.length; ++i) {
            dgnrs.unwrapTo(owners[i], 2_000_000_000 ether);
            vm.prank(owners[i]);
            sdgnrs.burn(1_000_000_000 ether);
            burnDay = sdgnrs.pendingResolveDay();
            (uint96 base, uint16 score,) = sdgnrs.pendingRedemptions(owners[i], burnDay);
            uint256 rolled = uint256(base) * (((WORD >> 8) % 151) + 25) / 100;
            uint256 box = rolled - rolled / 2;
            assertGe(box, 0.01 ether, "paid lootbox leg");
            assertLe(box, 5 ether, "one chunk");
            if (!terminal || i == 0) {
                vm.expectCall(address(game), abi.encodeWithSelector(
                    game.resolveRedemptionLootbox.selector, owners[i], box,
                    uint256(keccak256(abi.encode(WORD, uint256(uint160(owners[i]))))), score - 1
                ));
            }
        }
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        if (stalled) vm.warp(vm.getBlockTimestamp() + 2 days);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD);
        for (uint256 i; i < 100 && (sdgnrs.redemptionPeriods(burnDay) == 0 || game.rngLocked()); ++i) game.mineFlip();
        assertGt(sdgnrs.redemptionPeriods(burnDay), 0, "cohort resolved");
        assertTrue(sdgnrs.redemptionSettlementPending(), "read cohort remains outstanding");
        assertFalse(game.rngComplete(), "reuse blocked before remaining claims settle");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        if (terminal) {
            sdgnrs.claimRedemption(ALICE, burnDay); // Consume one; the other paid claims survive terminal cutover.
            vm.warp(vm.getBlockTimestamp() + 1001 days);
            assertTrue(game.livenessTriggered(), "ending disables live settlement");
            // A terminal claim requires the irreversible ending latch; let the real
            // dead-VRF timeout and bounded ending workers establish it.
            for (uint256 i; i < 1000 && !game.gameOver(); ++i) {
                game.mineFlip();
                if (game.rngLocked() && !game.isRngFulfilled()) vm.warp(vm.getBlockTimestamp() + 13 hours);
            }
            assertTrue(game.gameOver(), "irreversible ending");
            uint256 reserved = sdgnrs.pendingRedemptionEthValue();
            for (uint256 i = 1; i < owners.length; ++i) {
                uint256 beforeSteth = mockStETH.balanceOf(owners[i]);
                vm.prank(owners[i]);
                sdgnrs.claimRedemption(owners[i], burnDay);
                assertGt(mockStETH.balanceOf(owners[i]), beforeSteth, "late terminal withdrawal paid");
                (uint96 base,,) = sdgnrs.pendingRedemptions(owners[i], burnDay);
                assertEq(base, 0, "late entitlement consumed once");
            }
            assertGt(reserved, 0);
            assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "no forfeiture or stranded reserve");
            return;
        } else if (batch) {
            address[] memory players = new address[](1);
            players[0] = ALICE;
            sdgnrs.claimRedemptionMany(players, burnDay);
        } else {
            sdgnrs.claimRedemption(ALICE, burnDay);
        }
        _complete();
        assertFalse(sdgnrs.redemptionSettlementPending(), "no retained obligation");
        for (uint256 i; i < owners.length; ++i) {
            (uint96 base,,) = sdgnrs.pendingRedemptions(owners[i], burnDay);
            assertEq(base, 0, "all paid claims consumed");
        }
    }

    function test_NormalSessionManualClaimMatchesKeeper() public { _run(false, false, false); }
    function test_StalledSessionManualClaimMatchesKeeper() public { _run(true, false, false); }
    function test_StalledSessionBatchClaimMatchesKeeper() public { _run(true, true, false); }
    function test_TerminalClaimsSurviveFormerExpiry() public { _run(false, false, true); }
}
