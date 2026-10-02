// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Real burns, VRF requests and keeper lifecycle; no storage writes or mocked
/// claim paths. Manual calls must follow the same ordered cohort as the keeper.
contract RedemptionConsumerOrderingTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    uint24 private burnDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _complete();
        mockStETH.mint(address(sdgnrs), 2000 ether);
        address[3] memory owners = [ALICE, BOB, CAROL];
        for (uint256 i; i < owners.length; ++i) {
            dgnrs.unwrapTo(owners[i], 2_000_000_000 ether);
            vm.prank(owners[i]);
            sdgnrs.burn(1_000_000_000 ether);
        }
        burnDay = sdgnrs.pendingResolveDay();
        // A real paid ticket guarantees a read-side step after word publication.
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        game.purchase{value: 0.01 ether}(ALICE, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
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
        for (uint256 i; i < 100 && sdgnrs.redemptionPeriods(burnDay) == 0; ++i) game.mineFlip();
        assertGt(sdgnrs.redemptionPeriods(burnDay), 0, "resolved roll and pinned word");
    }

    function _ready() private {
        _publish();
        for (uint256 i; i < 100 && game.rngConsumerStage() != 1; ++i) game.mineFlip();
        assertEq(game.rngConsumerStage(), 1, "redemption is next after daily work");
    }

    function _claimsHash() private view returns (bytes32) {
        (uint96 a, uint16 ascore, uint96 aflip) = sdgnrs.pendingRedemptions(ALICE, burnDay);
        (uint96 b, uint16 bscore, uint96 bflip) = sdgnrs.pendingRedemptions(BOB, burnDay);
        (uint96 c, uint16 cscore, uint96 cflip) = sdgnrs.pendingRedemptions(CAROL, burnDay);
        return keccak256(abi.encode(a, ascore, aflip, b, bscore, bflip, c, cscore, cflip,
            sdgnrs.pendingRedemptionEthValue(), game.claimableWinningsOf(ALICE),
            game.claimableWinningsOf(BOB), game.claimableWinningsOf(CAROL)));
    }

    function test_PinnedWordCannotBypassUnfinishedDailyWork() public {
        _publish();
        assertTrue(game.rngLocked(), "publication precedes daily unlock");
        assertEq(game.rngConsumerStage(), 0);
        bytes32 beforeClaims = _claimsHash();
        vm.expectRevert(sDGNRS.RedemptionStageBlocked.selector);
        sdgnrs.claimRedemption(ALICE, burnDay);
        address[] memory prefix = new address[](1);
        prefix[0] = ALICE;
        vm.expectRevert(sDGNRS.RedemptionStageBlocked.selector);
        sdgnrs.claimRedemptionMany(prefix, burnDay);
        vm.expectRevert(sDGNRS.RedemptionStageBlocked.selector);
        vm.prank(address(game));
        sdgnrs.processRedemptionSettlement(1920);
        assertEq(_claimsHash(), beforeClaims, "all rejected paths preserve entitlements");
        _complete();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_OutOfOrderSingleAndBatchRevertAtomicallyThenKeeperContinues() public {
        _ready();
        bytes32 beforeClaims = _claimsHash();
        vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
        sdgnrs.claimRedemption(BOB, burnDay);
        address[] memory prefix = new address[](2);
        prefix[0] = ALICE;
        prefix[1] = CAROL;
        vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
        sdgnrs.claimRedemptionMany(prefix, burnDay);
        assertEq(_claimsHash(), beforeClaims, "invalid second entry rolls back first payout and cursor");
        prefix[1] = BOB;
        sdgnrs.claimRedemptionMany(prefix, burnDay);
        (uint96 first,,) = sdgnrs.pendingRedemptions(ALICE, burnDay);
        (uint96 second,,) = sdgnrs.pendingRedemptions(BOB, burnDay);
        (uint96 third,,) = sdgnrs.pendingRedemptions(CAROL, burnDay);
        assertEq(first, 0); assertEq(second, 0); assertGt(third, 0);
        vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
        sdgnrs.claimRedemption(ALICE, burnDay);
        _complete();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "keeper resumes at next beneficiary");
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_LastManualClaimRetainsCleanupGateThenNextBurnCanEnter() public {
        _ready();
        sdgnrs.claimRedemption(ALICE, burnDay);
        sdgnrs.claimRedemption(BOB, burnDay);
        sdgnrs.claimRedemption(CAROL, burnDay);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertTrue(sdgnrs.redemptionSettlementPending(), "queue cleanup keeps the cohort live");
        assertEq(game.rngConsumerStage(), 1, "last nested resolver and cleanup keep their stage");
        assertFalse(game.rngComplete());
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        vm.prank(address(game));
        (bool done, uint256 charged, uint256 bounty) = sdgnrs.processRedemptionSettlement(11);
        assertFalse(done); assertEq(charged, 0); assertEq(bounty, 0);
        assertTrue(sdgnrs.redemptionSettlementPending(), "tiny budget cannot erase cleanup work");
        _complete();
        assertFalse(sdgnrs.redemptionSettlementPending());
        vm.prank(ALICE);
        sdgnrs.burn(1 ether);
        assertEq(sdgnrs.pendingResolveDay(), game.currentDayView(), "fresh queue day can be established");
    }
}
