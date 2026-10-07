// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {SeatFixture} from "./SeatConsumption.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title AfKingSeatToken — integration tests for the AFKing seat ERC721 on a real deploy:
///        the pass-purchase seat latch (whale module -> mintPacked_ SEAT_CLAIMED, read back
///        through mintPackedFor; per account, a smurf's seat minted to its owner), immediate
///        buyer minting, the subscribe seat burn, the vault mint and restyle surface, the
///        cancel tombstone and its reclaim, and the RNG freeze window. The token sits at the
///        predicted AFKING_SUB_TOKEN address; SDGNRS holds serial 1 and the vault serial 2.
contract AfKingSeatToken is SeatFixture {
    function setUp() public {
        _setUpSeats();
    }

    function _isEligible(address who) internal view returns (bool) {
        return (game.mintPackedFor(who) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1 == 1;
    }

    /// @dev Enter the RNG freeze window: fresh day + advance requests VRF.
    function _enterRngLock() internal {
        _finishReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 beforeRequest = mockVRF.lastRequestId();
        // Subscription preparation and maintenance can consume an earlier
        // call. Stop only when the engine has actually issued the request.
        for (uint256 i; i < 64 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "engine should open a VRF request");
        assertGt(mockVRF.lastRequestId(), beforeRequest, "fresh request opened");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Deploy seeding & the seat burn
    // ──────────────────────────────────────────────────────────────────────

    function testConstructionSeats() public view {
        assertEq(afkingSubToken.totalSupply(), 2, "the two protocol seats at deploy");
        assertEq(afkingSubToken.ownerOf(1), address(sdgnrs), "serial 1 -> SDGNRS");
        assertEq(afkingSubToken.ownerOf(2), address(vault), "serial 2 -> VAULT");
        assertEq(afkingSubToken.balanceOf(address(sdgnrs)), 1, "sdgnrs seat");
        assertEq(afkingSubToken.balanceOf(address(vault)), 1, "vault seat");
        assertEq(afkingSubToken.nextSerial(), 3, "no seat minted past the construction pair");
        assertEq(afkingSubToken.freeClaims(), 0, "free tranche untouched at deploy");
        assertTrue(_isEligible(address(sdgnrs)) && _isEligible(address(vault)), "construction seats latched");
    }

    function testProtocolSelfSubsActiveViaIdentityCarve() public view {
        // Both self-subscribed at construction, BEFORE the token existed in the
        // deploy order — the exemption covers them and burns nothing; the token's
        // constructor then seats both for real (serials 1 and 2).
        assertTrue(_active(address(vault)), "vault self-sub active");
        assertTrue(_active(address(sdgnrs)), "sdgnrs self-sub active");
        assertEq(game.subscriberSetLength(), 2, "exactly the two protocol subs");
    }

    /// @notice A new run must name a seat its payee holds: naming none (serial 0) reverts.
    function testSubscribeWithoutSeatRevertsInvalidToken() public {
        address player = makeAddr("seatless");
        vm.deal(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        game.subscribe{value: SUB_FUND}(0, false, false, 1, 0, 0);
        assertEq(game.subscriberSetLength(), 2, "nothing entered the set");
    }

    function testSubscribeWithSeatSucceeds() public {
        address player = makeAddr("seated");
        uint256 seat = _giveSeat(player);
        _subscribe(player, 0, seat);

        uint32 id = game.walletIdOf(player);
        uint256 w = _subWord(id);
        assertTrue(_active(player), "sub active");
        assertEq(uint8(w), 1, "daily quantity stored");
        uint24 startDay = uint24(w >> 128);
        uint24 coveredDay = uint24(w >> 104);
        assertGt(startDay, 0, "activation day stamped");
        assertGe(coveredDay, startDay, "funded-through >= activation day");
        assertEq(game.subscriberSetLength(), 3, "set grew by one");
        assertEq(afkingSubToken.balanceOf(player), 0, "the seat was burned");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Pass-purchase seat latch -> immediate mint (organic whale-module drive)
    // ──────────────────────────────────────────────────────────────────────

    function testLazyPassMintsSeatAndArtIsRestylable() public {
        address buyer = makeAddr("lazy-buyer");
        assertFalse(_isEligible(buyer), "fresh address unlatched");

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        assertTrue(_isEligible(buyer), "pass purchase latches SEAT_CLAIMED");
        // The seat ARRIVES with the pass -- no separate claim step.
        assertEq(afkingSubToken.balanceOf(buyer), 1, "pass purchase mints the seat");
        assertEq(afkingSubToken.freeClaims(), 1, "free-tranche accounting");

        // No burn has happened yet, so the freshest serial is the buyer's.
        uint256 id = uint256(afkingSubToken.nextSerial()) - 1;
        assertEq(afkingSubToken.ownerOf(id), buyer, "buyer owns the minted seat");

        // Default art is deterministic in (recipient, serial) -- no entropy is read.
        uint256 seed = uint256(keccak256(abi.encode(buyer, uint32(id))));
        (uint8 s, uint24 bg, uint24 tr) = afkingSubToken.seatTraits(id);
        assertEq(s, uint8(seed & 31), "default symbol is seeded, not chosen");
        assertEq(bg, uint24((seed >> 8) & 0xFFFFFF), "default background is seeded");
        assertEq(tr, uint24((seed >> 32) & 0xFFFFFF), "default trim is seeded");

        // ...and the holder restyles it whenever they like (art is mutable by design).
        vm.prank(buyer);
        afkingSubToken.setSeatTraits(id, 12, 0xff8800, 0x123abc);
        (s, bg, tr) = afkingSubToken.seatTraits(id);
        assertEq(s, 12, "restyled symbol");
        assertEq(bg, 0xff8800, "restyled background RGB");
        assertEq(tr, 0x123abc, "restyled trim RGB");

        // A restyle REPLACES the lane rather than ORing into it: a later low-value
        // restyle must not leave high bits of the previous colors behind.
        vm.prank(buyer);
        afkingSubToken.setSeatTraits(id, 0, 0, 0);
        (s, bg, tr) = afkingSubToken.seatTraits(id);
        assertEq(s, 0, "restyle clears symbol");
        assertEq(bg, 0, "restyle clears background, no OR residue");
        assertEq(tr, 0, "restyle clears trim, no OR residue");

        // Only the owner may restyle.
        vm.prank(makeAddr("not-the-owner"));
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        afkingSubToken.setSeatTraits(id, 1, 1, 1);

        // The full credential path: pass -> seat -> subscribed, burning that seat.
        _subscribe(buyer, 0, id);
        assertTrue(_active(buyer), "the pass seat started the run");
        assertEq(afkingSubToken.balanceOf(buyer), 0, "and was burned by it");
    }

    function testWhalePassLatchesEligibilityOncePerLifetime() public {
        address buyer = makeAddr("whale-buyer");
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        assertTrue(_isEligible(buyer), "whale purchase latches too");
        assertEq(afkingSubToken.balanceOf(buyer), 1, "whale purchase mints the seat");

        // A second pass purchase (deity — a different trigger site) re-runs the
        // already-set latch but can never mint a second free seat: one per account,
        // lifetime, across every trigger. The repeat path pays only the bit test.
        vm.deal(buyer, 24 ether);
        vm.prank(buyer);
        game.purchaseDeityPass{value: 24 ether}(0, 5, bytes32(0));
        assertEq(afkingSubToken.balanceOf(buyer), 1, "still exactly one seat");
        // The deity purchase also confers a pass on the buyer's AFFILIATE, which defaults
        // to the VAULT when unreferred. A conferred pass is not a purchase, so it mints no
        // seat: the vault keeps only its construction seat and burns no tranche slot.
        assertEq(
            afkingSubToken.balanceOf(ContractAddresses.VAULT),
            1,
            "vault holds only its construction seat; a conferred pass mints none"
        );
        assertEq(afkingSubToken.freeClaims(), 1, "only the buyer consumed a tranche slot");
    }

    function testDeityPassBuyerGetsSeatButConferredAffiliateDoesNot() public {
        address buyer = makeAddr("fresh-deity-buyer");
        vm.deal(buyer, 24 ether);

        vm.prank(buyer);
        game.purchaseDeityPass{value: 24 ether}(0, 7, bytes32(0));

        assertEq(afkingSubToken.balanceOf(buyer), 1, "deity buyer receives a seat");
        assertEq(
            afkingSubToken.balanceOf(ContractAddresses.VAULT),
            1,
            "default affiliate keeps only its construction seat"
        );
        assertEq(
            afkingSubToken.freeClaims(),
            1,
            "only the purchased-pass recipient uses the free tranche"
        );
    }

    /// @notice M13: the latch is per account. A smurf's pass mints its seat to the owner (the
    ///         payee) and latches SEAT_CLAIMED on the smurf's word; the owner's own first pass
    ///         still mints the owner a second free seat.
    function testSmurfPassSeatGoesToTheOwnerWithAPerAccountLatch() public {
        address owner = makeAddr("smurf-pass-owner");
        vm.deal(owner, 10 ether);
        // The owner registers through a plain ticket purchase (no pass, no seat).
        vm.prank(owner);
        game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(afkingSubToken.balanceOf(owner), 0);
        (uint32 smurfId, address smurfKey) = _createSmurf(owner);

        vm.prank(owner);
        game.purchaseLazyPass{value: 0.24 ether}(smurfId, bytes32(0));
        assertEq(afkingSubToken.balanceOf(owner), 1, "the smurf's seat mints to the owner");
        assertEq(afkingSubToken.balanceOf(smurfKey), 0, "never to the smurf key");
        assertTrue(_isEligible(smurfKey), "latch on the smurf's word");
        assertFalse(_isEligible(owner), "owner's own latch untouched");
        assertEq(afkingSubToken.freeClaims(), 1);

        vm.prank(owner);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        assertEq(afkingSubToken.balanceOf(owner), 2, "owner's own pass mints a second free seat");
        assertTrue(_isEligible(owner), "owner latched now");
        assertEq(afkingSubToken.freeClaims(), 2);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Vault mint surface
    // ──────────────────────────────────────────────────────────────────────

    function testVaultMintLockedUntilFreeTrancheFills() public {
        // Token-side: only the vault may mint, and that stays locked while the free tranche
        // is open (0 of 1,000 minted here), so paid seats can never crowd out free ones.
        vm.prank(address(vault));
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        afkingSubToken.vaultMintSeats(makeAddr("grantee"), 1);
        // Through the vault the token's error bubbles.
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        vault.afkingSeatMint(makeAddr("grantee"), 1);
    }

    function testVaultSeatMintIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatMint(makeAddr("grantee"), 1);
    }

    function testVaultSeatTransferIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatTransfer(2, makeAddr("nope"));
        assertEq(afkingSubToken.ownerOf(2), address(vault));
    }

    function testVaultSeatRestyleIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatRestyle(2, 1, 1, 1);
    }

    /// @dev The vault restyles its own construction seat (serial 2) AND the SDGNRS
    ///      construction seat (serial 1), which the token authorizes it to steward
    ///      because SDGNRS has no admin surface of its own.
    function testVaultRestylesOwnAndSdgnrsConstructionSeats() public {
        address owner_ = ContractAddresses.CREATOR;
        vm.prank(owner_);
        vault.afkingSeatRestyle(2, 9, 0xabcdef, 0x123456);
        (uint8 s2, uint24 bg2, uint24 tr2) = afkingSubToken.seatTraits(2);
        assertEq(s2, 9, "vault seat restyled");
        assertEq(bg2, 0xabcdef);
        assertEq(tr2, 0x123456);

        vm.prank(owner_);
        vault.afkingSeatRestyle(1, 4, 0x0f0f0f, 0xf0f0f0);
        (uint8 s1, uint24 bg1, uint24 tr1) = afkingSubToken.seatTraits(1);
        assertEq(s1, 4, "sdgnrs seat restyled by its vault steward");
        assertEq(bg1, 0x0f0f0f);
        assertEq(tr1, 0xf0f0f0);
        assertEq(afkingSubToken.ownerOf(1), address(sdgnrs), "ownership unchanged by a restyle");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cancel tombstone and reclaim; re-subscribe
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A cancel burns nothing and leaves a tombstone in the set; the next process pass
    ///         reclaims it.
    function testCancelTombstoneThenPassReclaims() public {
        address player = makeAddr("canceller");
        uint256 seat = _giveSeat(player);
        _subscribe(player, 0, seat);
        uint256 live = afkingSubToken.totalSupply();

        vm.prank(player);
        game.subscribe(0, false, false, 0, 0, 0);
        assertFalse(_active(player), "cancel tombstone reads inactive");
        assertEq(afkingSubToken.totalSupply(), live, "a cancel burns nothing");

        // The inert set slot lingers until the next process pass reclaims it.
        assertEq(game.subscriberSetLength(), 3, "tombstone still in the set");
        _driveUntilOut(game.walletIdOf(player));
        assertEq(game.subscriberSetLength(), 2, "tombstone reclaimed by the pass");
    }

    /// @notice A re-subscribe after a cancel is a new run: it needs another seat (the first
    ///         was burned) and burns it.
    function testReSubscribeAfterCancelBurnsAnotherSeat() public {
        address player = makeAddr("returner");
        uint256 first = _giveSeat(player);
        _subscribe(player, 0, first);
        vm.prank(player);
        game.subscribe(0, false, false, 0, 0, 0);

        // The burned seat is gone for good.
        vm.deal(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        game.subscribe{value: SUB_FUND}(0, false, false, 1, 0, first);

        // A seat bought on the market starts the new run.
        address seller = makeAddr("seat-seller");
        uint256 second = _giveSeat(seller);
        vm.prank(seller);
        afkingSubToken.transferFrom(seller, player, second);
        _subscribe(player, 0, second);
        assertTrue(_active(player), "re-subscribe works with another seat");
        assertEq(afkingSubToken.balanceOf(player), 0, "and burned it");
    }

    // ──────────────────────────────────────────────────────────────────────
    // RNG freeze window
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Inside the freeze window the subscriber set is frozen (a cancel reverts
    ///         RngLocked) while seats move freely: the token never reads the Game.
    function testSetFrozenButSeatsMoveDuringRngLock() public {
        address player = makeAddr("locked-seller");
        address buyer = makeAddr("locked-buyer");
        uint256 seat = _giveSeat(player);
        uint256 spare = _giveSeat(player);
        _subscribe(player, 0, seat);

        _enterRngLock();
        vm.prank(player);
        vm.expectRevert(RngLocked.selector);
        game.subscribe(0, false, false, 0, 0, 0);
        assertTrue(_active(player), "sub untouched across the freeze window");

        vm.prank(player);
        afkingSubToken.transferFrom(player, buyer, spare);
        assertEq(afkingSubToken.ownerOf(spare), buyer, "an active subscriber's last seat moves");
    }

    function testNonSubHolderTransfersFreelyDuringRngLock() public {
        address holder = makeAddr("plain-holder");
        address buyer = makeAddr("plain-buyer");
        uint256 id = _giveSeat(holder); // holds a seat, never subscribed

        _enterRngLock();
        vm.prank(holder);
        afkingSubToken.transferFrom(holder, buyer, id);
        assertEq(afkingSubToken.balanceOf(buyer), 1, "plain transfer unblocked");
    }

    // ──────────────────────────────────────────────────────────────────────
    // On-chain art against the real Icons32Data
    // ──────────────────────────────────────────────────────────────────────

    function testTokenURIRendersAgainstRealIcons() public {
        address buyer = makeAddr("art-buyer");
        uint256 id = _giveSeat(buyer);
        vm.prank(buyer);
        afkingSubToken.setSeatTraits(id, 7, 0x1e1e2e, 0xffd700);

        string memory uri = afkingSubToken.tokenURI(id);
        bytes memory b = bytes(uri);
        assertGt(b.length, 100, "non-trivial data URI");
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i; i < prefix.length; i++) {
            assertEq(b[i], prefix[i], "base64 json data URI prefix");
        }
    }
}
