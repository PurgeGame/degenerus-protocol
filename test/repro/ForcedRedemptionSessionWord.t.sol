// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @dev Real burns and requests: a recovered session gives manual claims and the
/// mandatory keeper drain identical entropy, then permits buffer reuse.
/// The keeper settles live claims inside the same call that finishes the daily work, as far as
/// its allowance admits, so a manual claim takes whichever claim heads the queue when the
/// redemption stage opens; the cohort is sized so heads outlast that call's spare allowance.
contract ForcedRedemptionSessionWordTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    uint256 private constant WORD = 7419;
    uint256 private constant OWNERS = 30;

    function _request() private {
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "real daily request");
    }

    function _complete() private {
        uint256 requestBefore = mockVRF.lastRequestId();
        for (uint256 i; i < 500 && !game.rngComplete() && mockVRF.lastRequestId() == requestBefore; ++i) {
            game.mineFlip();
        }
        // After a stall the call that completes the session also issues the overdue daily request;
        // that request proves completion, since a fresh request waits for every read consumer.
        assertTrue(game.rngComplete() || mockVRF.lastRequestId() > requestBefore, "bounded compulsory work finishes");
    }

    function _owner(uint256 i) private pure returns (address) {
        if (i == 0) return ALICE;
        if (i == 1) return BOB;
        if (i == 2) return CAROL;
        return address(uint160(0xF0B000 + i));
    }

    /// @dev Advance with bounded allowances until the redemption consumer stage opens with part of
    ///      at least two claims still unsettled. The engine admits chunks while the allowance covers the next
    ///      declared bound, so a step that crosses into stage 1 with gas to spare settles heads in
    ///      the same call; such a step is replayed with a smaller allowance (the largest that
    ///      leaves two claims pending).
    function _unsettled(uint24 day) private view returns (uint256 n) {
        for (uint256 i; i < OWNERS; ++i) {
            (uint96 base,,) = sdgnrs.pendingRedemptions(_owner(i), day);
            if (base != 0) ++n;
        }
    }

    function _toRedemptionStage(uint24 day) private {
        for (uint256 i; i < 200 && game.rngConsumerStage() != 1; ++i) {
            uint256 snap = vm.snapshotState();
            bool stepped;
            for (uint256 g = 9_000_000; g >= 400_000 && !stepped; g -= 100_000) {
                try game.mineFlip{gas: g}() {
                    // Stop with a manual head and at least one keeper claim still unsettled.
                    if (_unsettled(day) >= 2) stepped = true;
                    else assertTrue(vm.revertToState(snap));
                } catch {
                    assertTrue(vm.revertToState(snap));
                }
            }
            assertTrue(stepped, "harness: a bounded allowance stops at the redemption stage");
        }
        assertEq(game.rngConsumerStage(), 1, "redemption stage reached after daily work");
    }

    function _run(bool stalled, bool batch, bool terminal) private {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _complete();
        mockStETH.mint(address(sdgnrs), 2000 ether);
        uint256[] memory boxes = new uint256[](OWNERS);
        uint16[] memory scores = new uint16[](OWNERS);
        uint24 burnDay;
        for (uint256 i; i < OWNERS; ++i) {
            address owner = _owner(i);
            dgnrs.unwrapTo(owner, 1_000_000_000 ether);
            vm.prank(owner);
            sdgnrs.burn(500_000_000 ether);
            burnDay = sdgnrs.pendingResolveDay();
            (uint96 base, uint16 score,) = sdgnrs.pendingRedemptions(owner, burnDay);
            uint256 rolled = uint256(base) * (((WORD >> 8) % 151) + 25) / 100;
            uint256 box = rolled - rolled / 2;
            assertGe(box, 0.01 ether, "paid lootbox leg");
            assertLe(box, 5 ether, "one chunk");
            boxes[i] = box;
            scores[i] = score;
        }
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        if (stalled) vm.warp(vm.getBlockTimestamp() + 2 days);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD);
        _toRedemptionStage(burnDay);
        assertGt(sdgnrs.redemptionPeriods(burnDay), 0, "cohort resolved");
        assertFalse(game.rngLocked(), "daily work released the lock");
        assertTrue(sdgnrs.redemptionSettlementPending(), "read cohort remains outstanding");
        assertFalse(game.rngComplete(), "reuse blocked before remaining claims settle");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();

        // FIFO: the first unsettled owner heads the queue; at least one more stays for the keeper.
        uint256 head = OWNERS;
        for (uint256 i; i < OWNERS && head == OWNERS; ++i) {
            (uint96 base,,) = sdgnrs.pendingRedemptions(_owner(i), burnDay);
            if (base != 0) head = i;
        }
        assertLt(head + 1, OWNERS, "harness: a manual head and a keeper claim remain");
        // Declared after the bounded probe, so replayed probe steps cannot satisfy them: each
        // remaining paid claim, manual or keeper, resolves its box from the pinned session word.
        for (uint256 i = head; i < OWNERS; ++i) {
            if (!terminal || i == head) {
                vm.expectCall(address(game), abi.encodeWithSelector(
                    game.resolveRedemptionLootbox.selector, _owner(i), boxes[i],
                    uint256(keccak256(abi.encode(WORD, uint256(uint160(_owner(i)))))), scores[i] - 1
                ));
            }
        }
        address manual = _owner(head);

        if (terminal) {
            sdgnrs.claimRedemption(manual, burnDay); // Consume one; the other paid claims survive terminal cutover.
            vm.warp(vm.getBlockTimestamp() + 1001 days);
            assertTrue(game.livenessTriggered(), "ending disables live settlement");
            // A terminal claim requires the irreversible ending latch; let the real
            // dead-VRF timeout and bounded ending workers establish it.
            for (uint256 i; i < 1000 && !game.gameOver(); ++i) {
                // While the unanswered terminal request waits out its dead-VRF timeout the engine
                // reports RngNotReady (nothing to do yet), not progress.
                try game.mineFlip() {} catch (bytes memory err) {
                    assertEq(bytes4(err), bytes4(keccak256("RngNotReady()")), "only waiting on the terminal word");
                }
                if (game.rngLocked() && !game.isRngFulfilled()) vm.warp(vm.getBlockTimestamp() + 13 hours);
            }
            assertTrue(game.gameOver(), "irreversible ending");
            uint256 reserved = sdgnrs.pendingRedemptionEthValue();
            for (uint256 i = head + 1; i < OWNERS; ++i) {
                address owner = _owner(i);
                uint256 beforeSteth = mockStETH.balanceOf(owner);
                vm.prank(owner);
                sdgnrs.claimRedemption(owner, burnDay);
                assertGt(mockStETH.balanceOf(owner), beforeSteth, "late terminal withdrawal paid");
                (uint96 base,,) = sdgnrs.pendingRedemptions(owner, burnDay);
                assertEq(base, 0, "late entitlement consumed once");
            }
            assertGt(reserved, 0);
            assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "no forfeiture or stranded reserve");
            return;
        } else if (batch) {
            address[] memory players = new address[](1);
            players[0] = manual;
            sdgnrs.claimRedemptionMany(players, burnDay);
        } else {
            sdgnrs.claimRedemption(manual, burnDay);
        }
        _complete();
        assertFalse(sdgnrs.redemptionSettlementPending(), "no retained obligation");
        for (uint256 i; i < OWNERS; ++i) {
            (uint96 base,,) = sdgnrs.pendingRedemptions(_owner(i), burnDay);
            assertEq(base, 0, "all paid claims consumed");
        }
    }

    function test_NormalSessionManualClaimMatchesKeeper() public { _run(false, false, false); }
    function test_StalledSessionManualClaimMatchesKeeper() public { _run(true, false, false); }
    function test_StalledSessionBatchClaimMatchesKeeper() public { _run(true, true, false); }
    function test_TerminalClaimsSurviveFormerExpiry() public { _run(false, false, true); }
}
