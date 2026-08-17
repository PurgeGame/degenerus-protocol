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
///        (an encumbered holder's last-seat transfer reverts SeatInUse until
///        manual unsub; an eviction forfeits the seat to the vault via
///        reclaimSeat), and the subscriberCount/subInfo views. Real
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
        assertEq(afkingSubToken.vaultGranted(), 0, "no vault-tranche seats minted at deploy");
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

    function testLazyPassMintsSeatAndArtIsRestylable() public {
        address buyer = makeAddr("lazy-buyer");
        assertFalse(_isEligible(buyer), "fresh address unlatched");

        vm.deal(buyer, 0.24 ether);
        vm.prank(buyer);
        game.purchaseLazyPass{value: 0.24 ether}(buyer, bytes32(0));
        assertTrue(_isEligible(buyer), "pass purchase latches bit 154");
        // The seat ARRIVES with the pass -- no separate claim step.
        assertEq(afkingSubToken.balanceOf(buyer), 1, "pass acquisition mints the seat");
        assertEq(afkingSubToken.freeClaims(), 1, "free-tranche accounting");

        // Serials are monotonic with no burn path, so the freshest one is the buyer's.
        uint256 id = uint256(afkingSubToken.nextSerial()) - 1;
        assertEq(afkingSubToken.ownerOf(id), buyer, "buyer owns the minted seat");

        // Default art is deterministic in (recipient, serial) -- no entropy is read.
        uint256 seed = uint256(keccak256(abi.encode(buyer, uint16(id))));
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

        // The full credential path: pass -> seat -> subscribed.
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
        assertEq(afkingSubToken.balanceOf(buyer), 1, "whale purchase mints the seat");

        // A second pass acquisition (deity — a different trigger site) re-runs the
        // already-set latch but can never mint a second free seat: one per address,
        // lifetime, across all four triggers. The repeat path pays only the bit test.
        vm.deal(buyer, 24 ether);
        vm.prank(buyer);
        game.purchaseDeityPass{value: 24 ether}(buyer, 5, bytes32(0));
        assertEq(afkingSubToken.balanceOf(buyer), 1, "still exactly one seat");
        // The deity purchase also latches the buyer's AFFILIATE, which defaults to the
        // VAULT when unreferred — so the vault takes its own one-per-address seat here.
        // That is one seat for the vault's lifetime, not one per purchase: the latch is
        // idempotent per address, so only this first unreferred deity purchase mints it.
        assertEq(
            afkingSubToken.balanceOf(ContractAddresses.VAULT),
            2,
            "vault holds its construction seat plus its one default-affiliate seat"
        );
        assertEq(afkingSubToken.freeClaims(), 2, "buyer + vault, one tranche slot each");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Vault grant surface
    // ──────────────────────────────────────────────────────────────────────

    function testVaultMintLockedUntilFreeTrancheFills() public {
        // Token-side: only the vault may mint from its tranche, and that stays locked
        // while the free tranche is open (0 of 1,000 minted here), so paid seats can
        // never crowd out free ones.
        vm.prank(address(vault));
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        afkingSubToken.vaultMintSeats(makeAddr("grantee"), 1);
    }

    function testVaultSeatMintIsOwnerGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatMint(makeAddr("grantee"), 1);
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
    // Eviction forfeit: trapped seat, blocked re-subscribe, vault reclaim
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Drive `who` into the funding-kill: drain their afking funding and
    ///      complete days until the STAGE evicts (the no-orphan guard can
    ///      defer the kill a cycle while a stamped box awaits its open).
    function _evict(address who, string memory seedTag) internal {
        for (uint256 i; i < 5 && _isActive(who); i++) {
            uint256 rem = game.afkingFundingOf(who);
            if (rem > 0) {
                vm.prank(who);
                game.withdrawAfkingFunding(rem);
            }
            _completeDay(uint256(keccak256(abi.encode(seedTag, i))) | 1);
        }
        assertFalse(_isActive(who), "fixture: the funding-kill evicted the sub");
    }

    /// @notice End-to-end forfeit: an evicted sub's last seat is trapped
    ///         (SeatInUse), a fresh re-subscribe reverts SeatForfeited, anyone
    ///         collects the forfeit to the vault, the vault owner disposes of
    ///         the repossession, and the settled evictee re-enters with a
    ///         fresh seat.
    function testEvictionForfeitEndToEnd() public {
        address p = makeAddr("evictee");
        address flipper = makeAddr("repo-buyer");
        uint256 id = _seatAndSubscribe(p);

        _evict(p, "evict-e2e");

        // Trapped: the evicted holder cannot move the seat...
        vm.prank(p);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        afkingSubToken.transferFrom(p, flipper, id);
        // ...and cannot re-subscribe past the forfeit.
        _fundPool(p, 1 ether);
        vm.prank(p);
        vm.expectRevert(GameAfkingModule.SeatForfeited.selector);
        game.subscribe(address(0), false, false, 1, address(0));

        // Permissionless collection to the vault.
        afkingSubToken.reclaimSeat(id);
        assertEq(afkingSubToken.ownerOf(id), address(vault), "seat repossessed");
        assertEq(afkingSubToken.balanceOf(p), 0);

        // A second collection has nothing to take.
        vm.expectRevert(AFKingSubscriptionToken.NotEvicted.selector);
        afkingSubToken.reclaimSeat(id);

        // Vault-owner disposal (CREATOR holds the DGVE majority); the rando
        // arm proves the gate.
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NotVaultOwner.selector);
        vault.afkingSeatTransfer(id, flipper);
        vm.prank(ContractAddresses.CREATOR);
        vault.afkingSeatTransfer(id, flipper);
        assertEq(afkingSubToken.ownerOf(id), flipper, "vault re-sold the seat");

        // Settled: with a seat back in hand the evictee subscribes again.
        vm.prank(flipper);
        afkingSubToken.transferFrom(flipper, p, id);
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, address(0));
        assertTrue(_isActive(p), "forfeit settled -> re-subscribe works");
    }

    /// @notice The vault cannot dispose of its LAST seat: the construction
    ///         seat's permanent self-subscription keeps the seat lock binding
    ///         on the vault as `from`.
    function testVaultCannotDisposeConstructionSeat() public {
        // Serial 2 is the vault's only seat at deploy.
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        vault.afkingSeatTransfer(2, makeAddr("nope"));
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
        vm.prank(ContractAddresses.GAME);
        afkingSubToken.mintSeatFor(buyer);
        uint256 id = uint256(afkingSubToken.nextSerial()) - 1;
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
