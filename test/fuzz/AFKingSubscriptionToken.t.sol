// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";

/// @dev Stand-in for the game's surface, etched at the compile-time GAME
///      address. The seat lock reads subInfo's `active` plus the
///      SEAT_ENCUMBERED bit (155) out of mintPackedFor; the free-claim path
///      reads the SEAT_CLAIMED eligibility bit (154); reclaimSeat settles a
///      forfeit through clearSeatEncumbrance.
contract MockSeatGame {
    mapping(address => bool) public activeOf;
    mapping(address => bool) public eligibleOf;
    mapping(address => bool) public encumberedOf;

    function setActive(address who, bool a) external {
        activeOf[who] = a;
    }

    function setEligible(address who, bool e) external {
        eligibleOf[who] = e;
    }

    function setEncumbered(address who, bool e) external {
        encumberedOf[who] = e;
    }

    function clearSeatEncumbrance(address holder) external {
        encumberedOf[holder] = false;
    }

    function subInfo(
        address player
    ) external view returns (bool, uint8, uint24, uint24) {
        return (activeOf[player], 0, 0, 0);
    }

    function mintPackedFor(address player) external view returns (uint256) {
        uint256 word = eligibleOf[player] ? (uint256(1) << 154) : 0;
        if (encumberedOf[player]) word |= uint256(1) << 155;
        return word;
    }
}

/// @dev Stand-in vault: settable DGVE-majority answer for the admin surface.
contract MockSeatVault {
    mapping(address => bool) public ownerOf_;

    function setOwner(address who, bool v) external {
        ownerOf_[who] = v;
    }

    function isVaultOwner(address account) external view returns (bool) {
        return ownerOf_[account];
    }
}

/// @dev Stand-in Icons32: fixed path + name so tokenURI renders standalone.
contract MockIcons32 {
    function data(uint256) external pure returns (string memory) {
        return "<path d='M0 0h512v512H0z'/>";
    }

    function symbol(uint256, uint8) external pure returns (string memory) {
        return "MockSymbol";
    }
}

/// @dev External renderer double for the override/fallback tests.
contract MockSeatRenderer {
    string public out;
    bool public shouldRevert;

    function set(string calldata o, bool r) external {
        out = o;
        shouldRevert = r;
    }

    function render(
        uint256,
        uint8,
        uint24,
        uint24,
        string calldata,
        string calldata,
        bool,
        bool,
        string calldata,
        string calldata
    ) external view returns (string memory) {
        if (shouldRevert) revert("renderer down");
        return out;
    }
}

/// @dev ERC721 receiver doubles for the safe-transfer tests.
contract GoodReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract BadReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

contract NonReceiver {}

/// @title AFKingSubscriptionToken — standalone ERC721 unit tests (no protocol deploy; the
///        game / vault / icons are mocks etched at their compile-time
///        addresses). The 2,000-serial seat collection: construction seats,
///        free-tranche claims with free 24-bit RGB color picks, vault
///        claim-rights grants, the seat lock, and the on-chain art surface.
contract AFKingSubscriptionTokenTest is Test {
    AFKingSubscriptionToken internal coin;
    MockSeatGame internal game;
    MockSeatVault internal mvault;

    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;
    address internal constant ICONS = ContractAddresses.ICONS_32;

    uint24 internal constant DEFAULT_BG = 0xd9d9d9;
    uint24 internal constant DEFAULT_TRIM = 0x3f1a82;

    address internal alice;
    address internal bob;
    address internal admin;

    function setUp() public {
        vm.etch(GAME, address(new MockSeatGame()).code);
        game = MockSeatGame(GAME);
        vm.etch(VAULT, address(new MockSeatVault()).code);
        mvault = MockSeatVault(VAULT);
        vm.etch(ICONS, address(new MockIcons32()).code);
        coin = new AFKingSubscriptionToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        admin = makeAddr("admin");
        mvault.setOwner(admin, true);
        // In-test `new` deployments must not land on the compile-time
        // protocol addresses (CREATE(this, 5..31)) — the GAME/VAULT/ICONS
        // etches above sit inside that range and CREATE reverts on a
        // code-bearing address.
        vm.setNonce(address(this), 1000);
    }

    /// @dev Free-tranche claim for `who` (marks eligible first).
    function _claim(
        address who,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) internal returns (uint256 id) {
        game.setEligible(who, true);
        vm.prank(who);
        id = coin.claimSeat(symbolId, bgRgb, trimRgb);
    }

    /// @dev Exhaust the free tranche: 1,000 claims by distinct fresh addresses.
    function _exhaustFreeTranche() internal {
        uint256 remaining = 1000 - coin.freeClaims();
        for (uint256 i; i < remaining; i++) {
            _claim(
                makeAddr(string(abi.encodePacked("filler", i))),
                uint8(i % 32),
                uint24(uint256(keccak256(abi.encode("bg", i)))),
                uint24(uint256(keccak256(abi.encode("trim", i))))
            );
        }
        assertEq(coin.freeClaims(), 1000, "free tranche exhausted");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Metadata & construction
    // ──────────────────────────────────────────────────────────────────────

    function testMetadata() public view {
        assertEq(coin.name(), "AFKing Subscription Token");
        assertEq(coin.symbol(), "AFK");
        assertEq(coin.FREE_TRANCHE(), 1000);
        assertEq(coin.VAULT_TRANCHE(), 998);
        assertEq(coin.MAX_SERIAL(), 2000);
    }

    function testConstructionMintsProtocolSeats() public view {
        assertEq(coin.totalSupply(), 2, "the two protocol seats at deploy");
        assertEq(coin.ownerOf(1), SDGNRS, "serial 1 -> SDGNRS");
        assertEq(coin.ownerOf(2), VAULT, "serial 2 -> VAULT");
        assertEq(coin.balanceOf(SDGNRS), 1, "sdgnrs holds its seat");
        assertEq(coin.balanceOf(VAULT), 1, "vault holds its seat");
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(1);
        assertEq(s, 0, "default symbol");
        assertEq(bg, DEFAULT_BG, "default background");
        assertEq(tr, DEFAULT_TRIM, "default trim");
        (s, bg, tr) = coin.seatTraits(2);
        assertEq(s, 0, "default symbol");
        assertEq(bg, DEFAULT_BG, "default background");
        assertEq(tr, DEFAULT_TRIM, "default trim");
    }

    function testSupportsInterface() public view {
        assertTrue(coin.supportsInterface(0x80ac58cd), "IERC721");
        assertTrue(coin.supportsInterface(0x5b5e139f), "IERC721Metadata");
        assertTrue(coin.supportsInterface(0x01ffc9a7), "IERC165");
        assertFalse(coin.supportsInterface(0xffffffff), "junk id");
    }

    function testViewsRevertOnMissingToken() public {
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.ownerOf(3);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.getApproved(3);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.seatTraits(3);
        vm.expectRevert(AFKingSubscriptionToken.ZeroAddress.selector);
        coin.balanceOf(address(0));
    }

    // ──────────────────────────────────────────────────────────────────────
    // Free-tranche claims
    // ──────────────────────────────────────────────────────────────────────

    function testFreeClaimMintsWithChosenTraits() public {
        uint256 id = _claim(alice, 17, 0xff8800, 0x00ff88);
        assertEq(id, 3, "serials are sequential after the construction seats");
        assertEq(coin.ownerOf(id), alice);
        assertEq(coin.balanceOf(alice), 1);
        assertEq(coin.freeClaims(), 1);
        assertTrue(coin.seatClaimed(alice), "claimed half of the latch set");
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(id);
        assertEq(s, 17, "chosen symbol");
        assertEq(bg, 0xff8800, "chosen background RGB");
        assertEq(tr, 0x00ff88, "chosen trim RGB");
    }

    function testClaimWithoutEligibilityReverts() public {
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        coin.claimSeat(0, 0, 0);
    }

    function testDoubleFreeClaimReverts() public {
        _claim(alice, 1, 0x111111, 0x222222);
        // The game-side eligibility bit stays set for life; the token-side
        // seatClaimed latch blocks the second free claim.
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        coin.claimSeat(2, 0x333333, 0x444444);
    }

    function testClaimInvalidSymbolReverts() public {
        game.setEligible(alice, true);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.InvalidTrait.selector);
        coin.claimSeat(32, 0, 0);
    }

    function testFuzzTraitRoundtrip(
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) public {
        symbolId = uint8(bound(symbolId, 0, 31));
        uint256 id = _claim(alice, symbolId, bgRgb, trimRgb);
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(id);
        assertEq(s, symbolId);
        assertEq(bg, bgRgb);
        assertEq(tr, trimRgb);
    }

    /// @dev Traits pack 4 per storage word (64-bit lanes) — neighbors must
    ///      not bleed, including across the construction seats' lanes.
    function testTraitPackingNeighborsIsolated() public {
        uint256[] memory ids = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            ids[i] = _claim(
                makeAddr(string(abi.encodePacked("packed", i))),
                uint8((i * 7) % 32),
                uint24(uint256(keccak256(abi.encode("nbg", i)))),
                uint24(uint256(keccak256(abi.encode("ntr", i))))
            );
        }
        for (uint256 i; i < 10; i++) {
            (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(ids[i]);
            assertEq(s, uint8((i * 7) % 32), "symbol survives neighbors");
            assertEq(
                bg,
                uint24(uint256(keccak256(abi.encode("nbg", i)))),
                "bg survives neighbors"
            );
            assertEq(
                tr,
                uint24(uint256(keccak256(abi.encode("ntr", i)))),
                "trim survives neighbors"
            );
        }
        // The construction seats' lanes are untouched by the claims around them.
        (uint8 s0, uint24 bg0, uint24 tr0) = coin.seatTraits(1);
        assertEq(s0, 0);
        assertEq(bg0, DEFAULT_BG);
        assertEq(tr0, DEFAULT_TRIM);
        (s0, bg0, tr0) = coin.seatTraits(2);
        assertEq(s0, 0);
        assertEq(bg0, DEFAULT_BG);
        assertEq(tr0, DEFAULT_TRIM);
    }

    function testFreeTrancheExhaustionThenClaimReverts() public {
        _exhaustFreeTranche();
        assertEq(coin.totalSupply(), 1002, "2 construction + 1000 free");
        // Latched-eligible but the tranche is gone and no vault grant exists.
        game.setEligible(alice, true);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        coin.claimSeat(0, 0, 0);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Vault claim-rights grants
    // ──────────────────────────────────────────────────────────────────────

    function testVaultGrantOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.OnlyVault.selector);
        coin.vaultGrant(alice, 1);
    }

    function testVaultGrantLockedWhileFreeTrancheOpen() public {
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        coin.vaultGrant(alice, 1);
    }

    function testVaultGrantZeroAddressReverts() public {
        _exhaustFreeTranche();
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.ZeroAddress.selector);
        coin.vaultGrant(address(0), 1);
    }

    function testVaultGrantedClaimUsesOwnTraits() public {
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(bob, 2);
        assertEq(coin.vaultGrants(bob), 2);
        assertEq(coin.vaultGranted(), 2);

        vm.prank(bob);
        uint256 id = coin.claimSeat(31, 0xdeadbe, 0xc0ffee);
        assertEq(coin.ownerOf(id), bob);
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(id);
        assertEq(s, 31);
        assertEq(bg, 0xdeadbe);
        assertEq(tr, 0xc0ffee);
        assertEq(coin.vaultGrants(bob), 1, "one right consumed");

        vm.prank(bob);
        coin.claimSeat(0, 1, 2);
        assertEq(coin.vaultGrants(bob), 0);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        coin.claimSeat(0, 3, 4);
    }

    /// @dev An address that used its free claim can still consume vault
    ///      grants (multi-seat holders are a supported shape).
    function testFreeThenGrantedClaimStacks() public {
        uint256 freeId = _claim(alice, 3, 0x101010, 0x202020);
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(alice, 1);
        vm.prank(alice);
        uint256 grantedId = coin.claimSeat(4, 0x303030, 0x404040);
        assertEq(coin.balanceOf(alice), 2);
        assertTrue(freeId != grantedId);
    }

    function testVaultGrantCapAndFullSupply() public {
        _exhaustFreeTranche();
        vm.startPrank(VAULT);
        coin.vaultGrant(bob, 998);
        vm.expectRevert(AFKingSubscriptionToken.GrantExceedsTranche.selector);
        coin.vaultGrant(bob, 1);
        vm.stopPrank();

        for (uint256 i; i < 998; i++) {
            vm.prank(bob);
            coin.claimSeat(uint8(i % 32), uint24(i), uint24(i * 3));
        }
        assertEq(coin.totalSupply(), 2000, "2 + 1000 + 998 = every serial out");
        assertEq(coin.balanceOf(bob), 998);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.NotEligible.selector);
        coin.claimSeat(0, 0, 0);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Transfers & approvals
    // ──────────────────────────────────────────────────────────────────────

    function testTransferMovesSeat() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), bob);
        assertEq(coin.balanceOf(alice), 0);
        assertEq(coin.balanceOf(bob), 1);
    }

    function testTransferWrongFromReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.transferFrom(bob, alice, id);
    }

    function testTransferToZeroReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.ZeroAddress.selector);
        coin.transferFrom(alice, address(0), id);
    }

    function testTransferUnauthorizedReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        coin.transferFrom(alice, bob, id);
    }

    function testApproveThenTransferFrom() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.approve(bob, id);
        assertEq(coin.getApproved(id), bob);
        vm.prank(bob);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), bob);
        assertEq(coin.getApproved(id), address(0), "approval cleared on transfer");
    }

    function testApproveByNonOwnerReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        coin.approve(bob, id);
    }

    function testOperatorTransfersAndApproves() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.setApprovalForAll(bob, true);
        assertTrue(coin.isApprovedForAll(alice, bob));
        // An operator may also issue per-token approvals.
        vm.prank(bob);
        coin.approve(bob, id);
        vm.prank(bob);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), bob);
    }

    function testSafeTransferToEOA() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.safeTransferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), bob);
    }

    function testSafeTransferToGoodReceiver() public {
        uint256 id = _claim(alice, 1, 1, 1);
        address rcv = address(new GoodReceiver());
        vm.prank(alice);
        coin.safeTransferFrom(alice, rcv, id, "payload");
        assertEq(coin.ownerOf(id), rcv);
    }

    function testSafeTransferToBadReceiverReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        address rcv = address(new BadReceiver());
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.UnsafeRecipient.selector);
        coin.safeTransferFrom(alice, rcv, id);
    }

    function testSafeTransferToNonReceiverContractReverts() public {
        uint256 id = _claim(alice, 1, 1, 1);
        address rcv = address(new NonReceiver());
        vm.prank(alice);
        vm.expectRevert();
        coin.safeTransferFrom(alice, rcv, id);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Seat lock
    // ──────────────────────────────────────────────────────────────────────

    function testLastSeatTransferAllowedWithoutSub() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.balanceOf(alice), 0, "plain holder never blocked");
    }

    function testLastSeatTransferBlockedWhileActive() public {
        uint256 id = _claim(alice, 1, 1, 1);
        game.setActive(alice, true);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), alice, "seat stays put");
    }

    function testSeatLockBindsApprovedSpenderToo() public {
        uint256 id = _claim(alice, 1, 1, 1);
        game.setActive(alice, true);
        vm.prank(alice);
        coin.approve(bob, id);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.transferFrom(alice, bob, id);
    }

    function testSeatLockBindsSafeTransferToo() public {
        uint256 id = _claim(alice, 1, 1, 1);
        game.setActive(alice, true);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.safeTransferFrom(alice, bob, id);
    }

    function testPartialTransferAllowedWhileActive() public {
        uint256 first = _claim(alice, 1, 1, 1);
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(alice, 1);
        vm.prank(alice);
        coin.claimSeat(2, 2, 2);
        game.setActive(alice, true);

        vm.prank(alice);
        coin.transferFrom(alice, bob, first);
        assertEq(coin.balanceOf(alice), 1, "kept a seat -> not a crossing");
        assertEq(coin.ownerOf(first), bob);
    }

    function testSelfTransferAllowedWhileActive() public {
        uint256 id = _claim(alice, 1, 1, 1);
        game.setActive(alice, true);
        vm.prank(alice);
        coin.transferFrom(alice, alice, id);
        assertEq(coin.ownerOf(id), alice, "self-transfer nets to nonzero");
    }

    function testUnsubReleasesLastSeatTransfer() public {
        uint256 id = _claim(alice, 1, 1, 1);
        game.setActive(alice, true);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.transferFrom(alice, bob, id);

        game.setActive(alice, false);
        vm.prank(alice);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), bob, "released after unsub");
    }

    function testClaimNeverBlockedBySeatLock() public {
        // An active sub claiming another seat only RAISES its balance —
        // claims can never cross a holder to zero.
        game.setActive(alice, true);
        uint256 id = _claim(alice, 1, 1, 1);
        assertEq(coin.ownerOf(id), alice);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Eviction forfeit (reclaimSeat)
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The forfeit state: SEAT_ENCUMBERED set with no active sub.
    function _evict(address who) internal {
        game.setActive(who, false);
        game.setEncumbered(who, true);
    }

    function testEvictedLastSeatTransferBlocked() public {
        uint256 id = _claim(alice, 1, 1, 1);
        _evict(alice);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.ownerOf(id), alice, "forfeited seat is trapped");
    }

    function testEvictedExtraSeatStillTransfers() public {
        uint256 first = _claim(alice, 1, 1, 1);
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(alice, 1);
        vm.prank(alice);
        uint256 second = coin.claimSeat(2, 2, 2);
        _evict(alice);

        // Only the LAST seat is trapped — exactly one seat is forfeit.
        vm.prank(alice);
        coin.transferFrom(alice, bob, first);
        assertEq(coin.ownerOf(first), bob, "surplus seat leaves freely");
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        coin.transferFrom(alice, bob, second);
    }

    function testReclaimSeatSeizesToVaultAndSettles() public {
        uint256 id = _claim(alice, 1, 1, 1);
        _evict(alice);

        // Permissionless: any caller may collect the forfeit — to the VAULT only.
        vm.expectEmit(true, true, true, true, address(coin));
        emit AFKingSubscriptionToken.Transfer(alice, VAULT, id);
        vm.expectEmit(true, true, true, true, address(coin));
        emit AFKingSubscriptionToken.SeatReclaimed(alice, id);
        vm.prank(bob);
        coin.reclaimSeat(id);

        assertEq(coin.ownerOf(id), VAULT, "seat repossessed to the vault");
        assertEq(coin.balanceOf(alice), 0);
        assertEq(coin.balanceOf(VAULT), 2, "construction seat + repossession");
        assertFalse(game.encumberedOf(alice), "forfeit settled game-side");
        // The vault is a clean holder: the repossession reads Transferable again.
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Transferable"),
            "vault-held repossession -> normal metadata"
        );
    }

    function testReclaimSeatRevertsUnlessForfeitState() public {
        uint256 id = _claim(alice, 1, 1, 1);
        // Clean holder: nothing forfeit.
        vm.expectRevert(AFKingSubscriptionToken.NotEvicted.selector);
        coin.reclaimSeat(id);
        // Active sub (encumbered but not evicted): nothing forfeit.
        game.setActive(alice, true);
        game.setEncumbered(alice, true);
        vm.expectRevert(AFKingSubscriptionToken.NotEvicted.selector);
        coin.reclaimSeat(id);
        // Unminted serial.
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.reclaimSeat(1999);
    }

    function testReclaimSettlesRemainingSeatsAndStops() public {
        uint256 first = _claim(alice, 1, 1, 1);
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(alice, 1);
        vm.prank(alice);
        uint256 second = coin.claimSeat(2, 2, 2);
        _evict(alice);

        vm.prank(bob);
        coin.reclaimSeat(second);
        // The clear ends the forfeit: no second seizure, and the remaining
        // seat transfers freely again.
        vm.expectRevert(AFKingSubscriptionToken.NotEvicted.selector);
        coin.reclaimSeat(first);
        vm.prank(alice);
        coin.transferFrom(alice, bob, first);
        assertEq(coin.ownerOf(first), bob, "remaining seat freed by the settle");
    }

    /// @dev Evicted metadata: Status flips to the forfeit flag, the art is the
    ///      WWXRP mark (no badge rings), and an external renderer is bypassed.
    function testTokenURIEvictedArtAndStatus() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        string memory normalJson = _decodeJson(coin.tokenURI(id));

        _evict(alice);
        string memory evictedUri = coin.tokenURI(id);
        string memory evictedJson = _decodeJson(evictedUri);
        assertTrue(
            _contains(evictedJson, "Evicted - reclaimable"),
            "forfeit status flag"
        );
        assertTrue(
            keccak256(bytes(evictedJson)) != keccak256(bytes(normalJson)),
            "evicted art differs"
        );
        string memory svg = _decodeSvg(evictedJson);
        assertTrue(_contains(svg, "WWXRP"), "WWXRP wordmark in the art");
        assertFalse(_contains(svg, "<circle r="), "no badge rings");

        // Evicted seats always internal-render: an external renderer is ignored.
        MockSeatRenderer r = new MockSeatRenderer();
        vm.prank(admin);
        coin.setRenderer(address(r));
        r.set("<svg>external</svg>", false);
        assertEq(
            coin.tokenURI(id),
            evictedUri,
            "external renderer bypassed while evicted"
        );

        // Settling the forfeit restores the badge art.
        vm.prank(bob);
        coin.reclaimSeat(id);
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Transferable"),
            "reclaimed seat renders normally"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Admin render surface
    // ──────────────────────────────────────────────────────────────────────

    function testAdminSurfaceGated() public {
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        coin.setRenderer(address(1));
        vm.prank(admin);
        coin.setRenderer(address(1));
        assertEq(coin.renderer(), address(1), "DGVE majority sets the renderer");
    }

    // ──────────────────────────────────────────────────────────────────────
    // tokenURI
    // ──────────────────────────────────────────────────────────────────────

    function testTokenURIInternalRender() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        string memory uri = coin.tokenURI(id);
        assertTrue(
            _startsWith(uri, "data:application/json;base64,"),
            "base64 json data URI"
        );
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.tokenURI(1999);
    }

    /// @dev The buyer's RGB picks land in the SVG verbatim as #rrggbb.
    function testTokenURICarriesChosenRgb() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        string memory json = _decodeJson(coin.tokenURI(id));
        assertTrue(_contains(json, "#ff8800"), "bg hex in metadata");
        assertTrue(_contains(json, "#123abc"), "trim hex in metadata");
    }

    /// @dev LIVE lock state in metadata: Locked while the holder is an
    ///      active sub with only this seat, back to Transferable when the
    ///      sub ends or a second seat arrives.
    function testTokenURIShowsSeatLockState() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Transferable"),
            "unsubbed holder -> Transferable"
        );

        game.setActive(alice, true);
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Locked - seat in use"),
            "active sub + last seat -> Locked"
        );

        // A second seat releases this one (no crossing to zero possible).
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultGrant(alice, 1);
        vm.prank(alice);
        coin.claimSeat(2, 2, 2);
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Transferable"),
            "multi-seat holder -> Transferable"
        );

        game.setActive(alice, false);
        assertTrue(
            _contains(_decodeJson(coin.tokenURI(id)), "Transferable"),
            "unsub releases"
        );
    }

    function testTokenURIExternalRendererOverrideAndFallback() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        string memory internalUri = coin.tokenURI(id);

        MockSeatRenderer r = new MockSeatRenderer();
        vm.prank(admin);
        coin.setRenderer(address(r));

        r.set("<svg>external</svg>", false);
        string memory overridden = coin.tokenURI(id);
        assertTrue(
            keccak256(bytes(overridden)) != keccak256(bytes(internalUri)),
            "external render overrides"
        );

        // A reverting renderer falls back to the internal render.
        r.set("", true);
        assertEq(
            coin.tokenURI(id),
            internalUri,
            "reverting renderer -> internal fallback"
        );

        // An empty-returning renderer falls back as well.
        r.set("", false);
        assertEq(
            coin.tokenURI(id),
            internalUri,
            "empty renderer -> internal fallback"
        );
    }

    /// @dev Base64-decode the data URI's JSON payload.
    function _decodeJson(
        string memory uri
    ) private pure returns (string memory) {
        bytes memory b = bytes(uri);
        uint256 prefixLen = bytes("data:application/json;base64,").length;
        bytes memory payload = new bytes(b.length - prefixLen);
        for (uint256 i; i < payload.length; i++) {
            payload[i] = b[prefixLen + i];
        }
        return string(_b64decode(payload));
    }

    /// @dev Extract and base64-decode the SVG image payload out of the
    ///      decoded JSON body.
    function _decodeSvg(
        string memory json
    ) private pure returns (string memory) {
        bytes memory b = bytes(json);
        bytes memory marker = bytes("data:image/svg+xml;base64,");
        uint256 start = type(uint256).max;
        for (uint256 i; i + marker.length <= b.length; i++) {
            bool hit = true;
            for (uint256 j; j < marker.length; j++) {
                if (b[i + j] != marker[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                start = i + marker.length;
                break;
            }
        }
        require(start != type(uint256).max, "svg marker not found");
        uint256 end = start;
        while (end < b.length && b[end] != bytes1(0x22)) end++;
        bytes memory payload = new bytes(end - start);
        for (uint256 i; i < payload.length; i++) {
            payload[i] = b[start + i];
        }
        return string(_b64decode(payload));
    }

    function _b64decode(bytes memory input) private pure returns (bytes memory) {
        bytes memory table = new bytes(256);
        bytes memory alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (uint256 i; i < 64; i++) {
            table[uint8(alphabet[i])] = bytes1(uint8(i));
        }
        uint256 len = input.length;
        while (len > 0 && input[len - 1] == "=") len--;
        bytes memory out = new bytes((len * 3) / 4);
        uint256 o;
        uint256 buf;
        uint256 bits;
        for (uint256 i; i < len; i++) {
            buf = (buf << 6) | uint8(table[uint8(input[i])]);
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                out[o++] = bytes1(uint8(buf >> bits));
            }
        }
        return out;
    }

    function _contains(
        string memory haystack,
        string memory needle
    ) private pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function _startsWith(
        string memory s,
        string memory prefix
    ) private pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        if (sb.length < pb.length) return false;
        for (uint256 i; i < pb.length; i++) {
            if (sb[i] != pb[i]) return false;
        }
        return true;
    }
}
