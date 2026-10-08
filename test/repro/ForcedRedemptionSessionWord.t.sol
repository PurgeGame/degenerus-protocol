// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionCloseTools} from "../fuzz/helpers/RedemptionCloseTools.sol";

/// @dev Real burns and requests: every claim the mandatory keeper drain settles, in a normal or a
/// recovered (stalled) session, resolves its box from the cohort's pinned session word, and the
/// drained cohort then permits buffer reuse. The keeper settles live claims inside the same call
/// that finishes the daily work, as far as its allowance admits; the cohort is sized so claims
/// outlast that call's spare allowance and are settled by later engine calls.
contract ForcedRedemptionSessionWordTest is RedemptionCloseTools {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    uint256 private constant WORD = 7419;
    uint256 private constant OWNERS = 30;

    function _request() private {
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) game.mineFlip(0);
        assertTrue(game.rngLocked(), "real daily request");
    }

    function _complete() private {
        uint256 requestBefore = mockVRF.lastRequestId();
        for (uint256 i; i < 500 && !game.rngComplete() && mockVRF.lastRequestId() == requestBefore; ++i) {
            game.mineFlip(0);
        }
        // After a stall the call that completes the session also issues the overdue daily request;
        // that request proves completion, since a fresh request waits for every read consumer.
        assertTrue(game.rngComplete() || mockVRF.lastRequestId() > requestBefore, "bounded compulsory work finishes");
    }

    /// @dev One mineFlip at the smallest allowance (25k steps) that settles a claim, probed on
    ///      snapshots and then applied. Every queued claim is the same size, so that call's spare
    ///      allowance cannot admit a second one.
    function _mineOneClaim() private {
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        for (uint256 g = 800_000; g <= 9_000_000; g += 25_000) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            bool settled = ok && sdgnrs.pendingRedemptionEthValue() != reserved;
            assertTrue(vm.revertToState(snap));
            if (settled) {
                game.mineFlip{gas: g}(0);
                return;
            }
        }
        revert("harness: no allowance settles a claim");
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
    function _unsettled(uint32 day) private view returns (uint256 n) {
        for (uint256 i; i < OWNERS; ++i) {
            (uint128 base,) = sdgnrs.pendingRedemptions(game.walletIdOf(_owner(i)), day);
            if (base != 0) ++n;
        }
    }

    function _toRedemptionStage(uint32 day) private {
        for (uint256 i; i < 200 && game.rngConsumerStage() != 1; ++i) {
            uint256 snap = vm.snapshotState();
            bool stepped;
            for (uint256 g = 9_000_000; g >= 400_000 && !stepped; g -= 100_000) {
                try game.mineFlip{gas: g}(0) {
                    // Stop with at least two claims still unsettled for later engine calls.
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

    function _run(bool stalled, bool terminal) private {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _complete();
        mockStETH.mint(address(sdgnrs), 2000 ether);
        uint256[] memory boxes = new uint256[](OWNERS);
        uint16[] memory scores = new uint16[](OWNERS);
        uint32 burnDay;
        for (uint256 i; i < OWNERS; ++i) {
            address owner = _owner(i);
            dgnrs.unwrapTo(owner, 1_000_000_000e12);
            _giveWalletId(owner);
            vm.prank(owner);
            sdgnrs.burn(500_000_000e12);
            burnDay = _openBatch();
            (, uint16 score) = sdgnrs.pendingRedemptions(game.walletIdOf(owner), burnDay);
            scores[i] = score;
        }
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        for (uint256 i; i < OWNERS; ++i) {
            uint256 rolled = _batchBase(_owner(i), burnDay) * (((WORD >> 8) % 155) + 21) / 100;
            boxes[i] = rolled - rolled / 2;
            assertGe(boxes[i], 0.01 ether);
        }
        if (stalled) vm.warp(vm.getBlockTimestamp() + 2 days);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD);
        _toRedemptionStage(burnDay);
        // The first admitted worker call resolves the batch.
        vm.prank(address(game)); sdgnrs.runRedemptionWork(WORD, 200_000);
        assertGt(_batchRoll(burnDay), 0, "cohort resolved");
        assertFalse(game.rngLocked(), "daily work released the lock");
        assertTrue(sdgnrs.redemptionSettlementPending(), "read cohort remains outstanding");
        assertFalse(game.rngComplete(), "reuse blocked before remaining claims settle");
        assertEq(game.nextMinerAction(), 8, "no request can cut in ahead of MinerAction.Redemption");

        // FIFO: the first unsettled owner heads the queue; at least one more follows it.
        uint256 head = OWNERS;
        for (uint256 i; i < OWNERS && head == OWNERS; ++i) {
            (uint128 base,) = sdgnrs.pendingRedemptions(game.walletIdOf(_owner(i)), burnDay);
            if (base != 0) head = i;
        }
        assertLt(head + 1, OWNERS, "harness: a head and a later claim remain");
        // Declared after the bounded probe, so replayed probe steps cannot satisfy them: each
        // remaining paid claim the keeper settles resolves its box from the pinned session word.
        for (uint256 i = head; i < OWNERS; ++i) {
            if (!terminal || i == head) {
                vm.expectCall(address(game), abi.encodeWithSelector(
                    game.resolveRedemptionLootbox.selector, game.walletIdOf(_owner(i)), boxes[i],
                    uint256(keccak256(abi.encode(WORD, uint256(game.walletIdOf(_owner(i)))))), scores[i] - 1, burnDay
                ));
            }
        }
        if (terminal) {
            // The engine settles the head live; the other paid claims survive terminal cutover.
            _mineOneClaim();
            (uint128 settled,) = sdgnrs.pendingRedemptions(game.walletIdOf(_owner(head)), burnDay);
            assertEq(settled, 0, "the head settled live");
            (uint128 waiting,) = sdgnrs.pendingRedemptions(game.walletIdOf(_owner(head + 1)), burnDay);
            assertGt(waiting, 0, "later claims wait for the ending");
            vm.warp(vm.getBlockTimestamp() + 1001 days);
            assertTrue(game.livenessTriggered(), "ending disables live settlement");
            // A terminal claim requires the irreversible ending latch; let the real
            // dead-VRF timeout and bounded ending workers establish it.
            for (uint256 i; i < 1000 && !game.gameOver(); ++i) {
                // While the unanswered terminal request waits out its dead-VRF timeout the engine
                // reports RngNotReady (nothing to do yet), not progress.
                try game.mineFlip(0) {} catch (bytes memory err) {
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
                sdgnrs.claimRedemption(0, burnDay);
                assertGt(mockStETH.balanceOf(owner), beforeSteth, "late terminal withdrawal paid");
                (uint128 base,) = sdgnrs.pendingRedemptions(game.walletIdOf(owner), burnDay);
                assertEq(base, 0, "late entitlement consumed once");
            }
            assertGt(reserved, 0);
            assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "no forfeiture or stranded reserve");
            return;
        }
        _complete();
        assertFalse(sdgnrs.redemptionSettlementPending(), "no retained obligation");
        for (uint256 i; i < OWNERS; ++i) {
            (uint128 base,) = sdgnrs.pendingRedemptions(game.walletIdOf(_owner(i)), burnDay);
            assertEq(base, 0, "all paid claims consumed");
        }
    }

    function test_NormalSessionKeeperClaimsUsePinnedWord() public { _run(false, false); }
    function test_StalledSessionKeeperClaimsUsePinnedWord() public { _run(true, false); }
    function test_TerminalClaimsSurviveFormerExpiry() public { _run(false, true); }
}
