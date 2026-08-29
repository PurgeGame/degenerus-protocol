// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusRecordBounty} from "../../contracts/DegenerusRecordBounty.sol";
import {
    RECORD_KIND_SPIN,
    RECORD_KIND_BUY
} from "../../contracts/interfaces/ICoinflip.sol";

/// @dev Renderer stub returning full custom metadata for any trophy.
contract FullMetadataRenderer {
    function tokenURI(
        uint256 tokenId,
        address,
        uint256,
        uint256,
        uint256,
        string calldata,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return string(abi.encodePacked("ipfs://custom-metadata/", bytes1(uint8(48 + tokenId))));
    }
}

/// @dev Renderer stub that always reverts.
contract RevertingRenderer {
    fallback() external {
        revert("renderer down");
    }
}

/// @dev Renderer stub returning an empty string.
contract EmptyRenderer {
    function tokenURI(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        string calldata,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return "";
    }
}

/// @title RecordBountyTrophyTest — pins the soulbound record-bounty trophy.
///
/// @notice Four trophies (tokenId = RECORD_KIND_*) mint to CREATOR at deploy.
///         Coinflip's _armBigRecord moves a trophy on EVERY mark ratchet — the
///         claim bar gates only the pool share, never the trophy — through the
///         real armRecord surface, so these tests also pin the deploy wiring
///         (a mispredicted RECORD_BOUNTY address would leave the trophy parked
///         at CREATOR while the mark ratchets).
contract RecordBountyTrophyTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant CREATOR = ContractAddresses.CREATOR;

    address private player;
    address private rival;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("trophy_player");
        rival = makeAddr("trophy_rival");
        _warpToDay(2);
    }

    // ---------------------------------------------------------------------
    // Deploy state
    // ---------------------------------------------------------------------

    function testAllFiveMintToCreatorAtDeploy() public view {
        assertEq(recordBounty.balanceOf(CREATOR), 5, "creator holds all five");
        for (uint256 i; i < 5; ++i) {
            assertEq(recordBounty.ownerOf(i), CREATOR, "creator owns trophy");
            (address holder, uint128 mark, uint24 sinceDay, ) = recordBounty.recordInfo(i);
            assertEq(holder, CREATOR, "recordInfo holder");
            assertEq(mark, 0, "mark starts unset");
            assertEq(sinceDay, 1, "since-day stamps the deploy day");
        }
    }

    // ---------------------------------------------------------------------
    // Auth + soulbound surface
    // ---------------------------------------------------------------------

    function testRecordSetIsCoinflipOnly() public {
        vm.prank(player);
        vm.expectRevert(DegenerusRecordBounty.NotAuthorized.selector);
        recordBounty.recordSet(RECORD_KIND_SPIN, player, 1 ether);

        vm.prank(GAME);
        vm.expectRevert(DegenerusRecordBounty.NotAuthorized.selector);
        recordBounty.recordSet(RECORD_KIND_SPIN, player, 1 ether);
    }

    function testRecordSetRejectsBadKindAndZeroHolder() public {
        vm.startPrank(ContractAddresses.COINFLIP);
        vm.expectRevert(DegenerusRecordBounty.InvalidToken.selector);
        recordBounty.recordSet(5, player, 1 ether);
        vm.expectRevert(DegenerusRecordBounty.ZeroAddress.selector);
        recordBounty.recordSet(RECORD_KIND_SPIN, address(0), 1 ether);
        vm.stopPrank();
    }

    function testSoulboundSurface() public {
        vm.startPrank(CREATOR);
        vm.expectRevert(DegenerusRecordBounty.Soulbound.selector);
        recordBounty.approve(player, 0);
        vm.expectRevert(DegenerusRecordBounty.Soulbound.selector);
        recordBounty.setApprovalForAll(player, true);
        vm.expectRevert(DegenerusRecordBounty.Soulbound.selector);
        recordBounty.transferFrom(CREATOR, player, 0);
        vm.expectRevert(DegenerusRecordBounty.Soulbound.selector);
        recordBounty.safeTransferFrom(CREATOR, player, 0);
        vm.expectRevert(DegenerusRecordBounty.Soulbound.selector);
        recordBounty.safeTransferFrom(CREATOR, player, 0, "");
        vm.stopPrank();

        assertEq(recordBounty.getApproved(0), address(0), "no approvals exist");
        assertFalse(recordBounty.isApprovedForAll(CREATOR, player), "no operators exist");
    }

    // ---------------------------------------------------------------------
    // Trophy movement through the real record path
    // ---------------------------------------------------------------------

    /// @notice A first mark takes the trophy from CREATOR through armRecord —
    ///         the end-to-end wiring, not a direct recordSet.
    function testFirstMarkTakesTheTrophy() public {
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_SPIN, player, 1 ether);

        assertEq(recordBounty.ownerOf(RECORD_KIND_SPIN), player, "trophy moved to setter");
        assertEq(recordBounty.balanceOf(CREATOR), 4, "creator down to four");
        assertEq(recordBounty.balanceOf(player), 1, "player holds one");
        (, uint128 mark, uint24 sinceDay, uint256 daysHeld) =
            recordBounty.recordInfo(RECORD_KIND_SPIN);
        assertEq(mark, 1 ether, "mark mirrors the candidate");
        assertEq(sinceDay, 2, "since-day stamps the take day");
        assertEq(daysHeld, 0, "held zero whole days so far");
    }

    /// @notice A bare ratchet (bigger, but under the claim bar) still moves the
    ///         trophy, and a holder out-ratcheting themselves keeps their
    ///         days-held clock.
    function testBareRatchetMovesTrophyAndSelfRatchetKeepsClock() public {
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_SPIN, player, 1 ether);

        _warpToDay(5);
        // +5% — over the mark, under the +20% claim bar: ratchet only.
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_SPIN, player, 1.05 ether);
        (, uint128 mark, uint24 sinceDay, uint256 daysHeld) =
            recordBounty.recordInfo(RECORD_KIND_SPIN);
        assertEq(mark, 1.05 ether, "self-ratchet stamps the new mark");
        assertEq(sinceDay, 2, "self-ratchet keeps the holder clock");
        assertEq(daysHeld, 3, "three whole days held");

        // A rival's bare ratchet takes the trophy and restarts the clock.
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_SPIN, rival, 1.15 ether);
        assertEq(recordBounty.ownerOf(RECORD_KIND_SPIN), rival, "rival takes the trophy");
        assertEq(recordBounty.balanceOf(player), 0, "player parted with it");
        (, , uint24 rivalSince, uint256 rivalHeld) =
            recordBounty.recordInfo(RECORD_KIND_SPIN);
        assertEq(rivalSince, 5, "clock restarts on the new holder");
        assertEq(rivalHeld, 0, "new holder starts at zero");
    }

    /// @notice A losing candidate (at or under the mark) moves nothing.
    function testLosingCandidateMovesNothing() public {
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_BUY, player, 500);
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_BUY, rival, 500);

        assertEq(recordBounty.ownerOf(RECORD_KIND_BUY), player, "tie moves nothing");
        (, uint128 mark, , ) = recordBounty.recordInfo(RECORD_KIND_BUY);
        assertEq(mark, 500, "mark unchanged");
    }

    /// @notice Each kind's trophy moves independently.
    function testKindsMoveIndependently() public {
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_SPIN, player, 1 ether);
        vm.prank(GAME);
        coinflip.armRecord(RECORD_KIND_BUY, rival, 250);

        assertEq(recordBounty.ownerOf(RECORD_KIND_SPIN), player, "spin trophy");
        assertEq(recordBounty.ownerOf(RECORD_KIND_BUY), rival, "buy trophy");
        assertEq(recordBounty.ownerOf(0), CREATOR, "flip trophy parked");
        assertEq(recordBounty.ownerOf(2), CREATOR, "luckbox trophy parked");
    }

    function testTokenUriRendersForAllKinds() public view {
        for (uint256 i; i < 4; ++i) {
            assertGt(bytes(recordBounty.tokenURI(i)).length, 0, "tokenURI renders");
        }
    }

    // ---------------------------------------------------------------------
    // External renderer owns the whole metadata
    // ---------------------------------------------------------------------

    /// @notice A set renderer's non-empty return IS the tokenURI, verbatim —
    ///         any scheme, full metadata, no internal wrapping.
    function testExternalRendererOwnsFullMetadata() public {
        recordBounty.setRenderer(address(new FullMetadataRenderer()));
        assertEq(
            recordBounty.tokenURI(2),
            "ipfs://custom-metadata/2",
            "external return is the whole URI"
        );
    }

    /// @notice A reverting or empty external render falls back to the internal
    ///         base64-JSON metadata.
    function testRendererRevertOrEmptyFallsBackToInternal() public {
        recordBounty.setRenderer(address(new RevertingRenderer()));
        _assertInternalUri(recordBounty.tokenURI(0));

        recordBounty.setRenderer(address(new EmptyRenderer()));
        _assertInternalUri(recordBounty.tokenURI(0));

        recordBounty.setRenderer(address(0));
        _assertInternalUri(recordBounty.tokenURI(0));
    }

    function testSetRendererIsOwnerGated() public {
        vm.prank(player);
        vm.expectRevert(DegenerusRecordBounty.NotAuthorized.selector);
        recordBounty.setRenderer(address(0xBEEF));
    }

    /// @dev Asserts the internal metadata shape: a base64 JSON data URI.
    function _assertInternalUri(string memory uri) private pure {
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory b = bytes(uri);
        assertGt(b.length, prefix.length, "internal URI non-trivial");
        for (uint256 i; i < prefix.length; ++i) {
            assertEq(b[i], prefix[i], "internal URI prefix");
        }
    }

    /// @dev Wall clock to game-day `d` (just past the 22:57 UTC reset).
    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }
}
