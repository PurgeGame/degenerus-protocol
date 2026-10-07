// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionCloseTools} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Real burns, VRF requests and keeper lifecycle; no storage writes or mocked
/// claim paths. Live claims settle only through mineFlip's Redemption stage, in the
/// cohort's FIFO order.
contract RedemptionConsumerOrderingTest is RedemptionCloseTools {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    uint32 private burnDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _complete();
        mockStETH.mint(address(sdgnrs), 160_000 ether);
        address[3] memory owners = [ALICE, BOB, CAROL];
        for (uint256 i; i < owners.length; ++i) {
            dgnrs.unwrapTo(owners[i], 2_000_000_000e12);
            _giveWalletId(owners[i]);
            vm.prank(owners[i]);
            sdgnrs.burn(1_000_000_000e12);
        }
        burnDay = _openBatch();
        // A real paid ticket guarantees a read-side step after word publication.
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _request() private {
        for (uint256 i; i < 200 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "real request established");
    }

    function _complete() private {
        for (uint256 i; i < 500 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete(), "all committed work completes");
    }

    function _publish() private {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 7419);
        assertEq(_batchRoll(burnDay), 0, "roll waits for the redemption stage");
    }

    function _ready() private {
        _publish();
        // Hold the cohort's worker while earlier work drains: the call that reaches the
        // redemption stage stops there, whatever its remaining allowance would admit.
        vm.mockCall(address(sdgnrs), abi.encodeWithSignature("runRedemptionWork(uint256,uint256)"),
            abi.encode(false, false, uint256(0)));
        for (uint256 i; i < 100 && game.rngConsumerStage() != 1; ++i) {
            try game.mineFlip{gas: 10_000_000}() {} catch {
                assertEq(game.rngConsumerStage(), 1, "only the held worker may stop progress");
            }
        }
        vm.clearMockedCalls();
        assertEq(game.rngConsumerStage(), 1, "redemption is next after daily work");
        vm.prank(address(game)); sdgnrs.runRedemptionWork(7419, 200_000);
    }

    /// @dev One mineFlip at the smallest allowance (25k steps) that settles a beneficiary, probed on
    ///      snapshots and then applied. Every queued claim here is the same size, so that call's
    ///      spare allowance cannot admit a second one; callers assert which claim it settled.
    function _mineOneClaim() private {
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        for (uint256 g = 800_000; g <= 9_000_000; g += 25_000) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip()"));
            bool settled = ok && sdgnrs.pendingRedemptionEthValue() != reserved;
            assertTrue(vm.revertToState(snap));
            if (settled) {
                game.mineFlip{gas: g}();
                return;
            }
        }
        revert("harness: no allowance settles a beneficiary");
    }

    function _owed(address owner) private view returns (uint128 base) {
        (base,) = sdgnrs.pendingRedemptions(game.walletIdOf(owner), burnDay);
    }

    function _claimsHash() private view returns (bytes32) {
        (uint128 a, uint16 ascore) = sdgnrs.pendingRedemptions(game.walletIdOf(ALICE), burnDay);
        (uint128 b, uint16 bscore) = sdgnrs.pendingRedemptions(game.walletIdOf(BOB), burnDay);
        (uint128 c, uint16 cscore) = sdgnrs.pendingRedemptions(game.walletIdOf(CAROL), burnDay);
        return keccak256(abi.encode(a, ascore, b, bscore, c, cscore,
            sdgnrs.pendingRedemptionEthValue(), game.claimableWinningsOf(ALICE),
            game.claimableWinningsOf(BOB), game.claimableWinningsOf(CAROL)));
    }

    function test_PinnedWordCannotBypassUnfinishedDailyWork() public {
        _publish();
        assertTrue(game.rngLocked(), "publication precedes daily unlock");
        assertEq(game.rngConsumerStage(), 0);
        bytes32 beforeClaims = _claimsHash();
        assertTrue(game.nextMinerAction() != 8, "the engine finishes daily work before MinerAction.Redemption");
        // A live game has no self-claim door: the resolved claim waits for the engine.
        vm.expectRevert(_batchRoll(burnDay) == 0 ? sDGNRS.NotResolved.selector : sDGNRS.NotGameOver.selector);
        vm.prank(ALICE);
        sdgnrs.claimRedemption(0, burnDay);
        vm.expectRevert(sDGNRS.RedemptionStageBlocked.selector);
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(7419, 9_000_000);
        assertEq(_claimsHash(), beforeClaims, "all rejected paths preserve entitlements");
        _complete();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_KeeperSettlesFifoHeadsAndResumesAtNextBeneficiary() public {
        _ready();
        assertEq(game.nextMinerAction(), 8, "the cohort is the engine's next work (MinerAction.Redemption)");
        uint128 bob = _owed(BOB);
        uint128 carol = _owed(CAROL);
        assertGt(_owed(ALICE), 0); assertGt(bob, 0); assertGt(carol, 0);

        // Burned ALICE, BOB, CAROL: one admitted claim per call, taken in that order.
        _mineOneClaim();
        assertEq(_owed(ALICE), 0, "the first call settles the FIFO head");
        assertEq(_owed(BOB), bob, "later beneficiaries are untouched");
        assertEq(_owed(CAROL), carol, "later beneficiaries are untouched");
        assertTrue(sdgnrs.redemptionSettlementPending());
        // A consumed head cannot be taken again through any door in a live game.
        vm.expectRevert(_batchRoll(burnDay) == 0 ? sDGNRS.NotResolved.selector : sDGNRS.NotGameOver.selector);
        vm.prank(ALICE);
        sdgnrs.claimRedemption(0, burnDay);

        _mineOneClaim();
        assertEq(_owed(BOB), 0, "the next call resumes at the next beneficiary");
        assertEq(_owed(CAROL), carol, "the tail waits its turn");

        _complete();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "keeper resumes at next beneficiary");
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_LastBeneficiaryKeepsCohortGateThenNextBurnCanEnter() public {
        _ready();
        _mineOneClaim();
        _mineOneClaim();
        assertEq(_owed(ALICE), 0); assertEq(_owed(BOB), 0);
        uint128 carol = _owed(CAROL);
        assertGt(carol, 0, "the last beneficiary is still owed");
        assertTrue(sdgnrs.redemptionSettlementPending(), "the unfinished cohort stays live");
        assertEq(game.rngConsumerStage(), 1, "the cohort keeps its stage until its last claim settles");
        assertFalse(game.rngComplete());
        assertEq(game.nextMinerAction(), 8, "no request can cut in ahead of MinerAction.Redemption");
        vm.prank(address(game));
        bool done = sdgnrs.runRedemptionWork(7419, 11_000).done;
        assertFalse(done);
        assertEq(_owed(CAROL), carol, "tiny budget cannot settle the last claim");
        assertTrue(sdgnrs.redemptionSettlementPending(), "tiny budget cannot erase the cohort");
        _complete();
        assertEq(_owed(CAROL), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        vm.prank(ALICE);
        sdgnrs.burn(1e12);
        assertEq(_openBatch(), burnDay + 1, "next open batch accepts burns");
    }
}
