// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";

/// @title AfKingSeatToken — integration tests for the AFKing seat ERC721
///        (sub <=> seat): the pass-acquisition eligibility latch (whale
///        module -> mintPacked_ bit 154, read back through mintPackedFor),
///        the two-step claim flow, the subscribe coin gate, the seat lock
///        (an active sub's last-seat transfer reverts SeatInUse until manual
///        unsub or eviction), and the subscriberCount/subInfo views. Real
///        protocol deploy — the token sits at the predicted AFKING_SUB_TOKEN
///        address; SDGNRS holds serial 1 from construction and the vault
///        holds a 999-seat claim-rights allowance, never tokens.
contract AfKingSeatToken is DeployProtocol {
    error RngLocked();
    error NotVaultOwner();

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Grant seat + fund + subscribe (self, lootbox mode, qty 1).
    ///      Returns the seat's serial (0 if `who` already held one).
    function _seatAndSubscribe(address who) internal returns (uint256 tokenId) {
        tokenId = _grantSeat(who);
        _fundPool(who, 1 ether);
        vm.prank(who);
        game.subscribe(address(0), false, false, 1, address(0));
    }

    /// @dev Enter the RNG freeze window: fresh day + advance requests VRF.
    function _enterRngLock() internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "advance should open a VRF request");
    }

    /// @dev Complete a full day: advance -> VRF fulfill -> drain to unlock.
    function _completeDay(uint256 vrfWord) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function _isActive(address who) internal view returns (bool active) {
        (active, , , ) = game.subInfo(who);
    }

    function _isEligible(address who) internal view returns (bool) {
        return (game.mintPackedFor(who) >> 154) & 1 == 1;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Deploy seeding & the coin gate
    // ──────────────────────────────────────────────────────────────────────

    function testConstructionSeatsAndVaultAllowance() public view {
        assertEq(afkingSubToken.totalSupply(), 2, "the two protocol seats at deploy");
        assertEq(afkingSubToken.ownerOf(1), address(sdgnrs), "serial 1 -> SDGNRS");
        assertEq(afkingSubToken.ownerOf(2), address(vault), "serial 2 -> VAULT");
        assertEq(afkingSubToken.balanceOf(address(sdgnrs)), 1, "sdgnrs seat");
        assertEq(afkingSubToken.balanceOf(address(vault)), 1, "vault seat");
        assertEq(afkingSubToken.vaultGranted(), 0, "no claim-rights grants at deploy");
    }

    function testProtocolSelfSubsActiveViaIdentityCarve() public view {
        // Both self-subscribed at construction, BEFORE the token existed in
        // the deploy order — the subscribe gate's identity carve covers them;
        // the token's constructor then seats both for real (serials 1 and 2).
        assertTrue(_isActive(address(vault)), "vault self-sub active");
        assertTrue(_isActive(address(sdgnrs)), "sdgnrs self-sub active");
        assertEq(game.subscriberCount(), 2, "exactly the two protocol subs");
    }

    function testSubscribeWithoutSeatRevertsNoCoin() public {
        address player = makeAddr("seatless");
        _fundPool(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(GameAfkingModule.NoCoin.selector);
        game.subscribe(address(0), false, false, 1, address(0));
    }

    function testSubscribeWithSeatSucceeds() public {
        address player = makeAddr("seated");
        _seatAndSubscribe(player);

        (bool active, uint8 qty, uint24 startDay, uint24 coveredDay) = game
            .subInfo(player);
        assertTrue(active, "sub active");
        assertEq(qty, 1, "daily quantity stored");
        assertGt(startDay, 0, "activation day stamped");
        assertGe(coveredDay, startDay, "funded-through >= activation day");
        assertEq(game.subscriberCount(), 3, "ring grew by one");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Pass-acquisition eligibility latch -> claim (organic whale-module drive)
    // ──────────────────────────────────────────────────────────────────────

    function testLazyPassLatchesEligibilityAndSeatClaims() public {
        address buyer = makeAddr("lazy-buyer");
        assertFalse(_isEligible(buyer), "fresh address unlatched");

        vm.deal(buyer, 0.24 ether);
        vm.prank(buyer);
        game.purchaseLazyPass{value: 0.24 ether}(buyer, bytes32(0));
        assertTrue(_isEligible(buyer), "pass purchase latches bit 154");
        assertEq(afkingSubToken.balanceOf(buyer), 0, "latch-only: nothing minted yet");

        vm.prank(buyer);
        uint256 id = afkingSubToken.claimSeat(12, 0xff8800, 0x123abc);
        assertEq(afkingSubToken.ownerOf(id), buyer, "claim mints the seat");
        (uint8 s, uint24 bg, uint24 tr) = afkingSubToken.seatTraits(id);
        assertEq(s, 12, "buyer-chosen symbol");
        assertEq(bg, 0xff8800, "buyer-chosen background RGB");
        assertEq(tr, 0x123abc, "buyer-chosen trim RGB");
        assertEq(afkingSubToken.freeClaims(), 1, "free-tranche accounting");

        // The full credential path: latched -> claimed -> subscribed.
        _fundPool(buyer, 1 ether);
        vm.prank(buyer);
        game.subscribe(address(0), false, false, 1, address(0));
        assertTrue(_isActive(buyer), "seat is the sole afking credential");
    }

    function testWhalePassLatchesEligibilityOncePerLifetime() public {
        address buyer = makeAddr("whale-buyer");
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        game.purchaseWhalePass{value: 2.4 ether}(buyer, 1, bytes32(0));
        assertTrue(_isEligible(buyer), "whale purchase latches too");

        vm.prank(buyer);
        afkingSubToken.claimSeat(0, 0, 0);

        // A second pass acquisition (deity — a different trigger site)
        // re-runs the already-set latch but can never re-open the free
        // claim: one per address, lifetime, across all four triggers.
        vm.deal(buyer, 24 ether);
        vm.prank(buyer);
        game.purchaseDeityPass{value: 24 ether}(buyer, 5);
        vm.prank(buyer);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        afkingSubToken.claimSeat(1, 1, 1);
        assertEq(afkingSubToken.balanceOf(buyer), 1, "still exactly one seat");
    }

    function testUnlatchedClaimReverts() public {
        address nobody = makeAddr("no-pass");
        vm.prank(nobody);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        afkingSubToken.claimSeat(0, 0, 0);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Vault grant surface
    // ──────────────────────────────────────────────────────────────────────

    function testVaultGrantLockedUntilFreeTrancheFills() public {
        // Token-side: only the vault may grant, and grants stay locked while
        // the free tranche is open (0 of 1,000 claimed here).
        vm.prank(address(vault));
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        afkingSubToken.vaultGrant(makeAddr("grantee"), 1);
    }

    function testVaultAfkingGrantIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingGrant(makeAddr("grantee"), 1);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Seat lock: last-seat transfers blocked while subscribed
    // ──────────────────────────────────────────────────────────────────────

    function testLastSeatTransferBlockedWhileSubbed() public {
        address player = makeAddr("seller");
        address buyer = makeAddr("buyer");
        uint256 id = _seatAndSubscribe(player);
        assertTrue(_isActive(player), "precondition: active");

        vm.prank(player);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        afkingSubToken.transferFrom(player, buyer, id);
        assertTrue(_isActive(player), "sub untouched by the blocked transfer");
        assertEq(afkingSubToken.balanceOf(player), 1, "seat stays put");
    }

    function testCancelThenSellReleasesSeat() public {
        address player = makeAddr("seller2");
        address buyer = makeAddr("buyer2");
        uint256 id = _seatAndSubscribe(player);

        // Manual unsub: the cancel tombstone reads inactive immediately, so the
        // seat is sellable in the very next tx (before any reclaim).
        vm.prank(player);
        game.subscribe(address(0), false, false, 0, address(0));
        assertFalse(_isActive(player), "cancel tombstone reads inactive");

        vm.prank(player);
        afkingSubToken.transferFrom(player, buyer, id);
        assertEq(afkingSubToken.ownerOf(id), buyer, "seat sold after manual unsub");

        // The inert ring slot lingers until the next process pass reclaims it.
        assertEq(game.subscriberCount(), 3, "tombstone still in ring");
        _completeDay(uint256(keccak256("reclaim-day")));
        assertEq(game.subscriberCount(), 2, "tombstone reclaimed by the drain");
    }

    function testPartialTransferAllowedWhileSubbed() public {
        address player = makeAddr("twoseats");
        address donor = makeAddr("seat-donor");
        address buyer = makeAddr("buyer3");
        _seatAndSubscribe(player);

        // Second seat arrives on the market: an unsubscribed holder sells theirs.
        uint256 donorId = _grantSeat(donor);
        vm.prank(donor);
        afkingSubToken.transferFrom(donor, player, donorId);
        assertEq(afkingSubToken.balanceOf(player), 2);

        vm.prank(player);
        afkingSubToken.transferFrom(player, buyer, donorId);
        assertTrue(_isActive(player), "sub survives while >= 1 seat held");
    }

    function testReSubscribeAfterSeatRoundTrip() public {
        address player = makeAddr("returner");
        address parkAddr = makeAddr("park");
        uint256 id = _seatAndSubscribe(player);

        vm.prank(player);
        game.subscribe(address(0), false, false, 0, address(0)); // manual unsub first
        vm.prank(player);
        afkingSubToken.transferFrom(player, parkAddr, id); // now the seat can leave

        vm.prank(parkAddr);
        afkingSubToken.transferFrom(parkAddr, player, id); // seat comes back
        _fundPool(player, 1 ether);
        vm.prank(player);
        game.subscribe(address(0), false, false, 1, address(0));
        assertTrue(_isActive(player), "re-subscribe works with the seat back");
    }

    // ──────────────────────────────────────────────────────────────────────
    // RNG freeze window
    // ──────────────────────────────────────────────────────────────────────

    function testSeatFullyFrozenDuringRngLock() public {
        address player = makeAddr("locked-seller");
        address buyer = makeAddr("locked-buyer");
        uint256 id = _seatAndSubscribe(player);

        _enterRngLock();
        // The seat lock binds (still subscribed)...
        vm.prank(player);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        afkingSubToken.transferFrom(player, buyer, id);
        // ...and the escape hatch (manual cancel) is itself lock-gated, so the
        // subscriber set — and the seat — stay frozen across [request -> unlock].
        vm.prank(player);
        vm.expectRevert(RngLocked.selector);
        game.subscribe(address(0), false, false, 0, address(0));
        assertTrue(_isActive(player), "sub untouched across the freeze window");
    }

    function testNonSubHolderTransfersFreelyDuringRngLock() public {
        address holder = makeAddr("plain-holder");
        address buyer = makeAddr("plain-buyer");
        uint256 id = _grantSeat(holder); // holds a seat, never subscribed

        _enterRngLock();
        vm.prank(holder);
        afkingSubToken.transferFrom(holder, buyer, id); // subInfo.active false — never blocked
        assertEq(afkingSubToken.balanceOf(buyer), 1, "plain transfer unblocked");
    }

    // ──────────────────────────────────────────────────────────────────────
    // On-chain art against the real Icons32Data
    // ──────────────────────────────────────────────────────────────────────

    function testTokenURIRendersAgainstRealIcons() public {
        address buyer = makeAddr("art-buyer");
        _markSeatEligible(buyer);
        vm.prank(buyer);
        uint256 id = afkingSubToken.claimSeat(7, 0x1e1e2e, 0xffd700);

        string memory uri = afkingSubToken.tokenURI(id);
        bytes memory b = bytes(uri);
        assertGt(b.length, 100, "non-trivial data URI");
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i; i < prefix.length; i++) {
            assertEq(b[i], prefix[i], "base64 json data URI prefix");
        }
    }
}
