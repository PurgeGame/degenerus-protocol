// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";

/// @dev Stand-in for the game's surface, etched at the compile-time GAME address. The token
///      reads only the subscriber-set length, for the capped vault mint.
contract MockSeatGame {
    uint256 public setLen;

    function setSetLength(uint256 n) external {
        setLen = n;
    }

    function subscriberSetLength() external view returns (uint256) {
        return setLen;
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

/// @dev External renderer double for the override/fallback tests. In echo mode it returns its
///      seven arguments joined by '|', so a test can read back exactly what the token passed.
contract MockSeatRenderer {
    string public out;
    bool public shouldRevert;
    bool public echo;

    function set(string calldata o, bool r) external {
        out = o;
        shouldRevert = r;
    }

    function setEcho(bool e) external {
        echo = e;
    }

    function render(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string calldata symbolName,
        string calldata iconPath,
        bool isCrypto
    ) external view returns (string memory) {
        if (shouldRevert) revert("renderer down");
        if (echo) {
            return string.concat(
                Strings.toString(tokenId), "|",
                Strings.toString(symbolId), "|",
                Strings.toString(bgRgb), "|",
                Strings.toString(trimRgb), "|",
                symbolName, "|",
                iconPath, "|",
                isCrypto ? "crypto" : "plain"
            );
        }
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
///        game / vault / icons are mocks etched at their compile-time addresses). The seat
///        collection: construction seats, the free tranche, the capped vault mint, the
///        Game-only burn (`consumeSeat`), plain ERC721 transfers and the on-chain art surface.
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

    string internal constant DESCRIPTION =
        '"description":"AFKing seat. Starting an afking-mode subscription burns one seat."';

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event VaultSeatsMinted(address indexed to, uint256 amount);

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
        // The two exempt protocol subscriptions are in the set from construction.
        game.setSetLength(2);
        // In-test `new` deployments must not land on the compile-time
        // protocol addresses (CREATE(this, 5..31)) — the GAME/VAULT/ICONS
        // etches above sit inside that range and CREATE reverts on a
        // code-bearing address.
        vm.setNonce(address(this), 1000);
    }

    /// @dev Free-tranche seat for `who` via the GAME-gated push mint, then restyled to the
    ///      requested traits (seats mint with deterministic defaults; art is mutable).
    function _claim(
        address who,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) internal returns (uint256 id) {
        id = _mintSeat(who);
        vm.prank(who);
        coin.setSeatTraits(id, symbolId, bgRgb, trimRgb);
    }

    /// @dev Raw GAME-gated mint (default art), the production path.
    function _mintSeat(address who) internal returns (uint256 id) {
        vm.prank(ContractAddresses.GAME);
        coin.mintSeatFor(who);
        id = uint256(coin.nextSerial()) - 1;
    }

    /// @dev Exhaust the free tranche: pushed mints to distinct fresh addresses.
    function _exhaustFreeTranche() internal {
        uint256 remaining = 1000 - coin.freeClaims();
        for (uint256 i; i < remaining; i++) {
            _mintSeat(address(uint160(0xF111_0000 + i)));
        }
        assertEq(coin.freeClaims(), 1000, "free tranche exhausted");
    }

    /// @dev Write `freeClaims` (slot 5, bytes 24..25: renderer 0..19 | nextSerial 20..23 |
    ///      freeClaims 24..25 | liveSeats 26..27, from the compiled layout), leaving the rest.
    function _setFreeClaims(uint16 v) internal {
        uint256 w = uint256(vm.load(address(coin), bytes32(uint256(5))));
        w = (w & ~(uint256(0xFFFF) << 192)) | (uint256(v) << 192);
        vm.store(address(coin), bytes32(uint256(5)), bytes32(w));
        assertEq(coin.freeClaims(), v, "slot 5 freeClaims lane");
    }

    /// @dev The Game burning `id` from `holder`.
    function _burn(address holder, uint256 id) internal {
        vm.prank(GAME);
        coin.consumeSeat(holder, id);
    }

    /// @dev The deterministic default traits of serial `id` minted to `to`.
    function _seeded(address to, uint256 id) internal pure returns (uint8 s, uint24 bg, uint24 tr) {
        uint256 seed = uint256(keccak256(abi.encode(to, uint32(id))));
        s = uint8(seed & 31);
        bg = uint24((seed >> 8) & 0xFFFFFF);
        tr = uint24((seed >> 32) & 0xFFFFFF);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Metadata & construction
    // ──────────────────────────────────────────────────────────────────────

    function testMetadata() public view {
        assertEq(coin.name(), "AFKing Subscription Token");
        assertEq(coin.symbol(), "AFK");
        assertEq(coin.FREE_TRANCHE(), 1000);
        assertEq(coin.SEAT_CAP(), 2000);
    }

    function testConstructionMintsProtocolSeats() public view {
        assertEq(coin.totalSupply(), 2, "the two protocol seats at deploy");
        assertEq(coin.nextSerial(), 3, "serials 1 and 2 taken");
        assertEq(coin.freeClaims(), 0, "construction seats are not free-tranche seats");
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
    // Free-tranche mints
    // ──────────────────────────────────────────────────────────────────────

    function testPushMintUsesDefaultArtThenRestyles() public {
        uint256 id = _mintSeat(alice);
        assertEq(id, 3, "serials are sequential after the construction seats");
        assertEq(coin.ownerOf(id), alice);
        assertEq(coin.balanceOf(alice), 1);
        assertEq(coin.freeClaims(), 1);
        assertEq(coin.totalSupply(), 3, "live count includes the new seat");

        // Default art is deterministic in (recipient, serial) -- no entropy is read.
        (uint8 es, uint24 ebg, uint24 etr) = _seeded(alice, id);
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(id);
        assertEq(s, es, "seeded default symbol");
        assertEq(bg, ebg, "seeded default background");
        assertEq(tr, etr, "seeded default trim");

        vm.prank(alice);
        coin.setSeatTraits(id, 17, 0xff8800, 0x00ff88);
        (s, bg, tr) = coin.seatTraits(id);
        assertEq(s, 17, "restyled symbol");
        assertEq(bg, 0xff8800, "restyled background RGB");
        assertEq(tr, 0x00ff88, "restyled trim RGB");
    }

    function testMintSeatForOnlyGame() public {
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.OnlyGame.selector);
        coin.mintSeatFor(alice);
    }

    /// @notice A zero recipient is a silent no-op: no serial, no tranche slot, no revert.
    function testMintSeatForZeroAddressIsNoOp() public {
        vm.prank(GAME);
        coin.mintSeatFor(address(0));
        assertEq(coin.nextSerial(), 3, "no serial consumed");
        assertEq(coin.freeClaims(), 0, "no tranche slot consumed");
        assertEq(coin.totalSupply(), 2, "no seat minted");
    }

    function testRestyleOnlyOwner() public {
        uint256 id = _mintSeat(alice);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        coin.setSeatTraits(id, 1, 1, 1);
    }

    function testRestyleInvalidSymbolReverts() public {
        uint256 id = _mintSeat(alice);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.InvalidTrait.selector);
        coin.setSeatTraits(id, 32, 0, 0);
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
        // Past the tranche the pushed mint is a SILENT no-op -- it rides inside a pass
        // purchase and must never revert one. The acquirer simply gets no seat.
        vm.prank(ContractAddresses.GAME);
        coin.mintSeatFor(alice);
        assertEq(coin.balanceOf(alice), 0, "no seat past the tranche");
        assertEq(coin.totalSupply(), 1002, "and no serial consumed");
        assertEq(coin.nextSerial(), 1003, "next serial unmoved");
        assertEq(coin.freeClaims(), 1000, "tranche counter stops at 1,000");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Capped vault mint
    // ──────────────────────────────────────────────────────────────────────

    function testVaultGrantOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.OnlyVault.selector);
        coin.vaultMintSeats(alice, 1);
    }

    function testVaultGrantLockedWhileFreeTrancheOpen() public {
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        coin.vaultMintSeats(alice, 1);
    }

    /// @notice One free seat short of the tranche, a vault mint with ample capacity is refused;
    ///         the 1,000th free mint opens it.
    function testVaultMintRefusedAt999ThenOpensAtTheThousandth() public {
        for (uint256 i; i < 999; i++) _mintSeat(address(uint160(0xF111_0000 + i)));
        assertEq(coin.freeClaims(), 999);
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        coin.vaultMintSeats(alice, 1);

        _mintSeat(bob);
        assertEq(coin.freeClaims(), 1000);
        vm.prank(VAULT);
        coin.vaultMintSeats(alice, 1);
        assertEq(coin.balanceOf(alice), 1, "vault mint opens after the 1,000th free seat");
    }

    function testVaultGrantZeroAddressReverts() public {
        _exhaustFreeTranche();
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.ZeroAddress.selector);
        coin.vaultMintSeats(address(0), 1);
    }

    function testVaultGrantedClaimUsesOwnTraits() public {
        _exhaustFreeTranche();
        vm.expectEmit(true, false, false, true, address(coin));
        emit VaultSeatsMinted(bob, 2);
        vm.prank(VAULT);
        coin.vaultMintSeats(bob, 2);
        assertEq(coin.balanceOf(bob), 2, "seats land immediately, no claim step");
        assertEq(coin.freeClaims(), 1000, "a vault mint is not a free-tranche seat");

        // Default art, restylable by the recipient like any other seat.
        uint256 id = uint256(coin.nextSerial()) - 1;
        assertEq(coin.ownerOf(id), bob);
        (uint8 es, uint24 ebg, uint24 etr) = _seeded(bob, id);
        (uint8 s1, uint24 bg1, uint24 tr1) = coin.seatTraits(id);
        assertEq(s1, es);
        assertEq(bg1, ebg);
        assertEq(tr1, etr);
        vm.prank(bob);
        coin.setSeatTraits(id, 31, 0xdeadbe, 0xc0ffee);
        (uint8 s2, uint24 bg, uint24 tr) = coin.seatTraits(id);
        assertEq(s2, 31);
        assertEq(bg, 0xdeadbe);
        assertEq(tr, 0xc0ffee);
    }

    /// @dev An address that took a free seat can still receive vault-minted ones
    ///      (multi-seat holders are a supported shape).
    function testFreeThenVaultMintedStacks() public {
        uint256 freeId = _claim(alice, 3, 0x101010, 0x202020);
        _exhaustFreeTranche();
        vm.prank(VAULT);
        coin.vaultMintSeats(alice, 1);
        uint256 mintedId = uint256(coin.nextSerial()) - 1;
        assertEq(coin.balanceOf(alice), 2);
        assertTrue(freeId != mintedId);
    }

    /// @notice The cap: live seats + amount + the game's set length may reach 2,000 and not
    ///         pass it. Sum 1,999 -> minting 1 lands on 2,000; one more is refused.
    function testVaultGrantCapAndFullSupply() public {
        _exhaustFreeTranche();
        game.setSetLength(3);
        // L = 1002, S = 3: 995 more seats leave the sum at 2,000 - 1 = 1,999 after 994.
        vm.startPrank(VAULT);
        coin.vaultMintSeats(bob, 994);
        assertEq(coin.totalSupply() + game.subscriberSetLength(), 1999, "sum at 1,999");
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        coin.vaultMintSeats(bob, 2);
        coin.vaultMintSeats(bob, 1);
        assertEq(coin.totalSupply() + game.subscriberSetLength(), 2000, "sum lands on the cap");
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        coin.vaultMintSeats(bob, 1);
        vm.stopPrank();

        assertEq(coin.totalSupply(), 1997, "2 + 1000 + 995");
        assertEq(coin.balanceOf(bob), 995);
    }

    /// @notice One call reaching exactly 2,000 succeeds; one that would land on 2,001 reverts.
    ///         The tranche is closed by writing `freeClaims` (slot 5) so the live count varies.
    /// forge-config: default.fuzz.runs = 256
    function testFuzzVaultMintCapBoundary(uint256 setLen, uint256 n, uint256 extraLive) public {
        extraLive = bound(extraLive, 0, 40);
        for (uint256 i; i < extraLive; i++) _mintSeat(address(uint160(0xF222_0000 + i)));
        _setFreeClaims(1000);
        setLen = bound(setLen, 1850, 2000 - coin.totalSupply());
        game.setSetLength(setLen);
        uint256 room = 2000 - coin.totalSupply() - setLen;
        n = bound(n, 1, room + 3);
        vm.prank(VAULT);
        if (n > room) {
            vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
            coin.vaultMintSeats(bob, n);
            assertEq(coin.balanceOf(bob), 0, "nothing minted past the cap");
        } else {
            coin.vaultMintSeats(bob, n);
            assertEq(coin.balanceOf(bob), n);
            assertLe(coin.totalSupply() + setLen, 2000, "never past the cap");
        }
    }

    /// @notice The cap check is checked arithmetic: an absurd amount panics, mints nothing.
    function testVaultMintAbsurdAmountPanics() public {
        _exhaustFreeTranche();
        vm.prank(VAULT);
        vm.expectRevert(stdError.arithmeticError);
        coin.vaultMintSeats(bob, type(uint256).max);
    }

    /// @notice A set length alone at the cap blocks every vault mint, whatever the live count.
    function testVaultMintBlockedWhenSetFillsTheCap() public {
        _exhaustFreeTranche();
        game.setSetLength(2000 - coin.totalSupply());
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        coin.vaultMintSeats(bob, 1);
    }

    // ──────────────────────────────────────────────────────────────────────
    // consumeSeat (the Game-only burn)
    // ──────────────────────────────────────────────────────────────────────

    function testConsumeSeatOnlyGame() public {
        uint256 id = _mintSeat(alice);
        vm.prank(alice);
        vm.expectRevert(AFKingSubscriptionToken.OnlyGame.selector);
        coin.consumeSeat(alice, id);
        vm.prank(VAULT);
        vm.expectRevert(AFKingSubscriptionToken.OnlyGame.selector);
        coin.consumeSeat(alice, id);
        assertEq(coin.ownerOf(id), alice, "seat untouched");
    }

    function testConsumeSeatBurns() public {
        uint256 id = _mintSeat(alice);
        _mintSeat(alice);
        uint32 next = coin.nextSerial();
        uint16 free = coin.freeClaims();

        vm.expectEmit(true, true, true, true, address(coin));
        emit Transfer(alice, address(0), id);
        _burn(alice, id);

        assertEq(coin.balanceOf(alice), 1, "balance - 1");
        assertEq(coin.totalSupply(), 3, "live count - 1");
        assertEq(coin.nextSerial(), next, "nextSerial unchanged");
        assertEq(coin.freeClaims(), free, "freeClaims unchanged");
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.ownerOf(id);
    }

    /// @notice The holder must hold the serial: another holder's seat, a never-minted serial,
    ///         a burned serial and serial 0 all revert InvalidToken.
    function testConsumeSeatWrongHolderReverts() public {
        uint256 a = _mintSeat(alice);
        uint256 b = _mintSeat(bob);

        vm.startPrank(GAME);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.consumeSeat(alice, b);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.consumeSeat(alice, 999);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.consumeSeat(alice, 0);
        coin.consumeSeat(alice, a);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.consumeSeat(alice, a);
        vm.stopPrank();

        assertEq(coin.ownerOf(b), bob, "bob's seat untouched");
        assertEq(coin.totalSupply(), 3, "exactly one burn landed");
    }

    /// @notice After the burn every surface treats the serial as nonexistent.
    function testBurnedSeatIsDeadEverywhere() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        _burn(alice, id);

        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.ownerOf(id);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.getApproved(id);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.seatTraits(id);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.tokenURI(id);

        vm.startPrank(alice);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.transferFrom(alice, bob, id);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.safeTransferFrom(alice, bob, id);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.approve(bob, id);
        vm.expectRevert(AFKingSubscriptionToken.NotAuthorized.selector);
        coin.setSeatTraits(id, 1, 1, 1);
        vm.stopPrank();
    }

    /// @notice A per-token approval and an operator approval set before the burn move nothing.
    function testApprovalSetBeforeBurnIsUnusable() public {
        uint256 id = _mintSeat(alice);
        vm.startPrank(alice);
        coin.approve(bob, id);
        coin.setApprovalForAll(admin, true);
        vm.stopPrank();
        _burn(alice, id);

        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.transferFrom(alice, bob, id);
        vm.prank(admin);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.transferFrom(alice, admin, id);
        vm.prank(bob);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.approve(bob, id);
    }

    /// @notice Serials are never reused, and the next serial renders its own seeded art even
    ///         when it shares a trait word with a burned, fully restyled serial.
    function testNextMintAfterBurnGetsFreshSerialAndOwnArt() public {
        uint256 a = _mintSeat(alice); // 3 (word 0)
        uint256 b = _mintSeat(alice); // 4 (word 1, lane 0)
        assertEq(b >> 2, 1, "serial 4 opens trait word 1");
        vm.prank(alice);
        coin.setSeatTraits(b, 31, 0xFFFFFF, 0xFFFFFF);
        _burn(alice, b);
        _burn(alice, a);

        uint256 c = _mintSeat(bob);
        assertEq(c, 5, "fresh serial, no reuse of 3 or 4");
        assertEq(c >> 2, b >> 2, "shares the burned serial's trait word");
        (uint8 es, uint24 ebg, uint24 etr) = _seeded(bob, c);
        (uint8 s, uint24 bg, uint24 tr) = coin.seatTraits(c);
        assertEq(s, es, "own seeded symbol");
        assertEq(bg, ebg, "own seeded background");
        assertEq(tr, etr, "own seeded trim");
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        coin.ownerOf(b);
    }

    /// @notice The burn makes no external call (no Game or vault callback).
    function testConsumeSeatMakesNoExternalCall() public {
        uint256 id = _mintSeat(alice);
        vm.expectCall(GAME, "", 0);
        vm.expectCall(VAULT, "", 0);
        vm.expectCall(ICONS, "", 0);
        _burn(alice, id);
    }

    /// @notice totalSupply is minted minus burned across any interleaving.
    function testFuzzTotalSupplyIsLiveCount(uint8 mints, uint256 burnMask) public {
        mints = uint8(bound(mints, 1, 40));
        uint256 first = coin.nextSerial();
        for (uint256 i; i < mints; i++) _mintSeat(i % 2 == 0 ? alice : bob);
        uint256 burned;
        for (uint256 i; i < mints; i++) {
            if ((burnMask >> i) & 1 == 1) {
                _burn(i % 2 == 0 ? alice : bob, first + i);
                burned++;
            }
        }
        assertEq(coin.totalSupply(), 2 + uint256(mints) - burned, "live = minted - burned");
        assertEq(coin.totalSupply(), uint256(coin.nextSerial()) - 1 - burned, "live = serials - burned");
        assertEq(
            coin.balanceOf(alice) + coin.balanceOf(bob) + coin.balanceOf(SDGNRS) + coin.balanceOf(VAULT),
            coin.totalSupply(),
            "balances sum to the live count"
        );
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

    function testLastSeatTransferAllowedWithoutSub() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.transferFrom(alice, bob, id);
        assertEq(coin.balanceOf(alice), 0, "plain holder never blocked");
    }

    function testSelfTransferKeepsTheSeat() public {
        uint256 id = _claim(alice, 1, 1, 1);
        vm.prank(alice);
        coin.transferFrom(alice, alice, id);
        assertEq(coin.ownerOf(id), alice, "self-transfer nets to the same holder");
        assertEq(coin.balanceOf(alice), 1, "balance unchanged");
    }

    /// @notice Transfers are plain ERC721: none of the three forms calls the Game.
    function testTransfersReadNothingFromGame() public {
        uint256 a = _mintSeat(alice);
        uint256 b = _mintSeat(alice);
        uint256 c = _mintSeat(alice);
        vm.expectCall(GAME, "", 0);
        vm.startPrank(alice);
        coin.transferFrom(alice, bob, a);
        coin.safeTransferFrom(alice, bob, b);
        coin.safeTransferFrom(alice, bob, c, "data");
        vm.stopPrank();
        assertEq(coin.balanceOf(bob), 3);
        assertEq(coin.balanceOf(alice), 0, "the last seat leaves too");
    }

    /// @notice With the Game's code replaced by INVALID, every transfer form still succeeds.
    function testTransfersSurviveABrokenGame() public {
        uint256 a = _mintSeat(alice);
        uint256 b = _mintSeat(alice);
        uint256 snap = vm.snapshotState();
        vm.etch(GAME, hex"fe");
        vm.startPrank(alice);
        coin.transferFrom(alice, bob, a);
        coin.safeTransferFrom(alice, bob, b);
        vm.stopPrank();
        assertEq(coin.balanceOf(bob), 2, "transfers never touch the Game");
        vm.revertToState(snap);
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

    /// @notice The metadata carries the seat description and exactly the Symbol / Background /
    ///         Trim attributes; no lock state.
    function testTokenURINoStatusAttributeAndNewDescription() public {
        uint256 id = _claim(alice, 9, 0xff8800, 0x123abc);
        string memory json = _decodeJson(coin.tokenURI(id));
        assertTrue(_contains(json, DESCRIPTION), "seat description");
        assertTrue(
            _contains(
                json,
                '"attributes":[{"trait_type":"Symbol","value":"MockSymbol"},{"trait_type":"Background","value":"#ff8800"},{"trait_type":"Trim","value":"#123abc"}]'
            ),
            "exactly three attributes"
        );
        assertFalse(_contains(json, "Status"), "no Status attribute");
        assertFalse(_contains(json, "Locked"), "no lock state");
        assertFalse(_contains(json, "Transferable"), "no lock state");
        assertTrue(_startsWith(json, '{"name":"AFK Sub #3 - MockSymbol"'), "name");
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
        assertEq(_decodeSvg(_decodeJson(overridden)), "<svg>external</svg>", "external SVG embedded");

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

        // Unsetting the renderer restores the internal render.
        vm.prank(admin);
        coin.setRenderer(address(0));
        assertEq(coin.tokenURI(id), internalUri, "renderer unset -> internal");
    }

    /// @notice The renderer receives the seven-argument tuple (tokenId, symbolId, bgRgb,
    ///         trimRgb, symbolName, iconPath, isCrypto).
    function testExternalRendererReceivesSevenArguments() public {
        uint256 id = _claim(alice, 5, 0x0a0b0c, 0x0d0e0f);
        MockSeatRenderer r = new MockSeatRenderer();
        r.setEcho(true);
        vm.prank(admin);
        coin.setRenderer(address(r));
        string memory svg = _decodeSvg(_decodeJson(coin.tokenURI(id)));
        assertEq(
            svg,
            string.concat(
                Strings.toString(id),
                "|5|",
                Strings.toString(uint256(0x0a0b0c)),
                "|",
                Strings.toString(uint256(0x0d0e0f)),
                "|MockSymbol|<path d='M0 0h512v512H0z'/>|crypto"
            ),
            "seven arguments, symbol 5 is a crypto symbol"
        );

        vm.prank(alice);
        coin.setSeatTraits(id, 12, 0x0a0b0c, 0x0d0e0f);
        svg = _decodeSvg(_decodeJson(coin.tokenURI(id)));
        assertTrue(_contains(svg, "|12|"), "restyled symbol passed");
        assertTrue(_contains(svg, "|plain"), "symbol 12 is not a crypto symbol");
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
