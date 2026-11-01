// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {SeatFixture} from "./SeatConsumption.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title AfKingSeatToken — integration tests for the AFKing seat ERC721 on a real deploy:
///        the pass-purchase seat latch (whale module -> mintPacked_ SEAT_CLAIMED, read back
///        through mintPackedFor; per account, the seat minted to the account's payee), immediate
///        buyer minting, the subscribe seat burn, the vault mint and restyle surface, the
///        cancel removal, and the RNG freeze window. The token sits at the
///        predicted AFKING_SUB_TOKEN address; the protocol subscriptions hold no seat.
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
        for (uint256 i; i < 64 && !game.rngLocked(); ++i) game.mineRun(0);
        assertTrue(game.rngLocked(), "engine should open a VRF request");
        assertGt(mockVRF.lastRequestId(), beforeRequest, "fresh request opened");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Deploy seeding & the seat burn
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Deployment mints no seat; both protocol wallets keep the SEAT_CLAIMED latch and
    ///         their deity pass NFTs.
    function testDeploymentHoldsNoSeat() public view {
        assertEq(afkingSubToken.totalSupply(), 0, "no seat at deploy");
        assertEq(afkingSubToken.balanceOf(address(sdgnrs)), 0, "sdgnrs holds no seat");
        assertEq(afkingSubToken.balanceOf(address(vault)), 0, "vault holds no seat");
        assertEq(afkingSubToken.nextSerial(), 1, "the first player seat is serial 1");
        assertEq(afkingSubToken.freeClaims(), 0, "free tranche untouched at deploy");
        assertTrue(_isEligible(address(sdgnrs)) && _isEligible(address(vault)), "protocol seat bits latched");
        assertEq(deityPass.ownerOf(0), address(vault), "vault keeps its deity pass");
        assertEq(deityPass.ownerOf(6), address(sdgnrs), "sdgnrs keeps its deity pass");
    }

    function testProtocolSelfSubsActiveViaIdentityCarve() public view {
        // Both self-subscribed at construction, BEFORE the token existed in the
        // deploy order: the exemption covers them, burns nothing and needs no seat.
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
        game.subscribe{value: SUB_FUND}(0, false, 1, 0);
        assertEq(game.subscriberSetLength(), 2, "nothing entered the set");
    }

    function testSubscribeWithSeatSucceeds() public {
        address player = makeAddr("seated");
        uint256 seat = _giveSeat(player);
        _subscribe(player, 0, seat);

        uint32 id = game.walletIdOf_g3120(player);
        (uint256 lane,) = _laneOf(id);
        assertTrue(_active(player), "sub active");
        assertEq(_qty(id), 1, "daily quantity stored");
        assertEq(uint24((lane >> 46) & ((uint256(1) << 22) - 1)), game.currentDayView_g542950(), "checkpointed today");
        uint256 meta = uint256(vm.load(address(game), keccak256(abi.encode(uint256(id >> 2), GameSlots.SUB_META))))
            >> ((id & 3) * 64);
        assertEq(uint24((meta >> 14) & ((uint256(1) << 22) - 1)), game.currentDayView_g542950(), "run starts today");
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
        // seat: the vault holds none and burns no tranche slot.
        assertEq(
            afkingSubToken.balanceOf(ContractAddresses.VAULT),
            0,
            "vault holds no seat; a conferred pass mints none"
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
            0,
            "default affiliate receives no seat"
        );
        assertEq(
            afkingSubToken.freeClaims(),
            1,
            "only the purchased-pass recipient uses the free tranche"
        );
    }

    /// @notice The latch is per account. An operator's pass for another account mints the seat to
    ///         that account's payee and latches SEAT_CLAIMED on its word; the operator's own first
    ///         pass still mints the operator a free seat.
    function testOperatorPassSeatGoesToThePayeeWithAPerAccountLatch() public {
        address operator = makeAddr("pass-operator");
        address holder = makeAddr("pass-holder");
        vm.deal(operator, 10 ether);
        vm.deal(holder, 10 ether);
        // Both register through a plain ticket purchase (no pass, no seat).
        vm.prank(operator);
        game.purchaseOrderFor{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(holder);
        game.purchaseOrderFor{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint32 holderId = game.walletIdOf_g3120(holder);
        vm.prank(holder);
        game.setOperatorApproval(holderId, operator, true);

        vm.prank(operator);
        game.purchaseLazyPass{value: 0.24 ether}(holderId, bytes32(0));
        assertEq(afkingSubToken.balanceOf(holder), 1, "the account's seat mints to its payee");
        assertEq(afkingSubToken.balanceOf(operator), 0, "nothing to the operator");
        assertEq((game.mintPackedOfId_g5372(holderId) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1, 1, "the account's latch");
        assertFalse(_isEligible(operator), "the operator's own latch untouched");
        assertEq(afkingSubToken.freeClaims(), 1);

        vm.prank(operator);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        assertEq(afkingSubToken.balanceOf(operator), 1, "the operator's own pass mints its free seat");
        assertTrue(_isEligible(operator), "the operator latched now");
        assertEq(afkingSubToken.freeClaims(), 2);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Vault mint surface
    // ──────────────────────────────────────────────────────────────────────

    function testVaultMintLockedUntilFreeTrancheFills() public {
        // Token-side: only the vault may mint, and that stays locked while the free tranche
        // is open (0 of 5,000 minted here), so paid seats can never crowd out free ones.
        vm.prank(address(vault));
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        afkingSubToken.vaultMintSeats(makeAddr("grantee"), 1);
        // Through the vault the token's error bubbles.
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (makeAddr("grantee"), 1)), 0);
    }

    function testVaultSeatMintIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatMint(makeAddr("grantee"), 1);
    }

    function testVaultSeatTransferIsOwnerGated() public {
        uint256 seat = _giveSeat(address(vault));
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.sweepNft(ContractAddresses.AFKING_SUB_TOKEN, makeAddr("nope"), seat);
        assertEq(afkingSubToken.ownerOf(seat), address(vault));
    }

    function testVaultSeatRestyleIsOwnerGated() public {
        uint256 seat = _giveSeat(address(vault));
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.playerAction(
            ContractAddresses.AFKING_SUB_TOKEN,
            abi.encodeWithSignature("setSeatTraits(uint256,uint8,uint24,uint24)", seat, 1, 1, 1),
            0
        );
    }

    /// @dev The vault restyles a seat it holds; it has no authority over a seat sDGNRS holds.
    function testVaultRestylesOnlyItsOwnSeat() public {
        uint256 own = _giveSeat(address(vault));
        uint256 other = _giveSeat(address(sdgnrs));
        address owner_ = ContractAddresses.CREATOR;
        vm.prank(owner_);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.AFKING_SUB_TOKEN,
            abi.encodeWithSignature("setSeatTraits(uint256,uint8,uint24,uint24)", own, 9, 0xabcdef, 0x123456),
            0
        )), 0), (bytes));
        (uint8 s2, uint24 bg2, uint24 tr2) = afkingSubToken.seatTraits(own);
        assertEq(s2, 9, "vault seat restyled");
        assertEq(bg2, 0xabcdef);
        assertEq(tr2, 0x123456);

        vm.prank(owner_);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.AFKING_SUB_TOKEN,
            abi.encodeWithSignature("setSeatTraits(uint256,uint8,uint24,uint24)", other, 4, 0x0f0f0f, 0xf0f0f0),
            0
        )), 0);
        assertEq(afkingSubToken.ownerOf(other), address(sdgnrs), "the sdgnrs-held seat is untouched");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cancel removal; re-subscribe
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A cancel burns nothing and removes the member from the set at once.
    function testCancelRemovesAtOnce() public {
        address player = makeAddr("canceller");
        uint256 seat = _giveSeat(player);
        _subscribe(player, 0, seat);
        uint256 live = afkingSubToken.totalSupply();

        vm.prank(player);
        game.subscribe(0, false, 0, 0);
        assertFalse(_active(player), "cancel reads inactive");
        assertEq(afkingSubToken.totalSupply(), live, "a cancel burns nothing");
        assertEq(game.subscriberSetLength(), 2, "no tombstone stays in the set");
        assertEq(_pos(game.walletIdOf_g3120(player)), 0, "and no record");
    }

    /// @notice A re-subscribe after a cancel is a new run: it needs another seat (the first
    ///         was burned) and burns it.
    function testReSubscribeAfterCancelBurnsAnotherSeat() public {
        address player = makeAddr("returner");
        uint256 first = _giveSeat(player);
        _subscribe(player, 0, first);
        vm.prank(player);
        game.subscribe(0, false, 0, 0);

        // The burned seat is gone for good.
        vm.deal(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        game.subscribe{value: SUB_FUND}(0, false, 1, first);

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
        game.subscribe(0, false, 0, 0);
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
