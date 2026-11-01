// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {AffiliateIdFixture} from "./AffiliateWalletIds.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Custom-code shape rule and ID-text referral resolution.
///         A custom code is 1-32 characters of A-Z/0-9, at least one letter, left-aligned with only
///         zero bytes after the last character. A referral input resolves, in order: a raw word up to
///         2^160 as an address, `2^160 | id` as an account ID, all-digit text as that ID, then a
///         custom-code lookup.
contract AffiliateCodeRulesTest is AffiliateIdFixture {
    uint256 internal constant ID_TAG = uint256(1) << 160;
    uint256 internal constant ID_WORD_TAG = uint256(1) << 32;
    uint256 internal constant ID_LOCKED = 1;

    address internal referrer;
    address internal buyer;
    uint32 internal referrerId;
    uint32 internal buyerId;

    function setUp() public override {
        super.setUp();
        referrer = makeAddr("codeRulesReferrer");
        buyer = makeAddr("codeRulesBuyer");
        referrerId = _giveWalletId(referrer);
        buyerId = _giveWalletId(buyer);
    }

    // ---------------------------------------------------------------------
    // Reference rule and helpers
    // ---------------------------------------------------------------------

    /// @dev Independent statement of the rule: the code is its non-zero prefix, followed by zeros.
    function _rule(bytes32 code) internal pure returns (bool) {
        bytes memory b = abi.encodePacked(code);
        uint256 n;
        while (n < 32 && b[n] != 0) ++n;
        if (n == 0) return false;
        for (uint256 i = n; i < 32; ++i) {
            if (b[i] != 0) return false;
        }
        bool letter;
        for (uint256 i; i < n; ++i) {
            uint8 c = uint8(b[i]);
            if (c >= 0x41 && c <= 0x5A) letter = true;
            else if (c < 0x30 || c > 0x39) return false;
        }
        return letter;
    }

    function _tryCreate(address who, bytes32 code) internal returns (bool ok, bytes4 sel) {
        vm.prank(who);
        bytes memory ret;
        (ok, ret) = address(affiliate).call(abi.encodeCall(affiliate.createAffiliateCode, (code, 0)));
        sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
    }

    function _assertAccepted(bytes32 code) internal {
        address who = makeAddr(string.concat("ok", vm.toString(code)));
        (bool ok,) = _tryCreate(who, code);
        assertTrue(ok, "well-formed code refused");
        assertEq(affiliate.getReferrerId(who), 1, "creation sets no referral");
        (address owner, uint32 ownerId,) = affiliate.affiliateCode(code);
        assertEq(owner, who);
        assertEq(ownerId, _id(who));
    }

    function _assertRefused(bytes32 code) internal {
        address who = makeAddr(string.concat("bad", vm.toString(code)));
        (bool ok, bytes4 sel) = _tryCreate(who, code);
        assertFalse(ok, "malformed code accepted");
        assertEq(sel, DegenerusAffiliate.InvalidCode.selector);
        assertEq(_id(who), 0, "a refused creation registers nobody");
    }

    /// @dev Decimal text of `n` behind `pad` zero characters, left-aligned.
    function _text(uint256 n, uint256 pad) internal pure returns (bytes32) {
        bytes memory zeros = new bytes(pad);
        for (uint256 i; i < pad; ++i) zeros[i] = "0";
        return bytes32(bytes.concat(zeros, bytes(vm.toString(n))));
    }

    function _tag(uint256 id) internal pure returns (bytes32) {
        return bytes32(ID_TAG | id);
    }

    function _bytes1Code(bytes1 first, bytes memory rest) internal pure returns (bytes32) {
        return bytes32(bytes.concat(first, rest));
    }

    // ---------------------------------------------------------------------
    // 1. Charset and shape
    // ---------------------------------------------------------------------

    function test_EmptyAndZeroLeadingCodesRefused() public {
        _assertRefused(bytes32(0));
        _assertRefused(bytes32(uint256(0x41)));
        _assertRefused(bytes32(bytes.concat(bytes1(0x00), "ABC")));
        _assertRefused(bytes32(uint256(1) << 192));
        _assertRefused(bytes32(uint256(ID_TAG | 5)));
    }

    function test_LengthBoundaries() public {
        _assertAccepted(bytes32("A"));
        _assertAccepted(bytes32("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"));
        _assertAccepted(bytes32("0000000000000000000000000000000A"));
        _assertAccepted(bytes32("A0000000000000000000000000000000"));
    }

    function test_LetterDigitMixesAccepted() public {
        _assertAccepted(bytes32("A1"));
        _assertAccepted(bytes32("1A"));
        _assertAccepted(bytes32("9Z9"));
        _assertAccepted(bytes32("0A0"));
        _assertAccepted(bytes32("ZZ"));
    }

    function test_DigitOnlyCodesRefused() public {
        _assertRefused(bytes32("0"));
        _assertRefused(bytes32("123"));
        _assertRefused(bytes32("4294967295"));
        _assertRefused(bytes32("00000000000000000000000000000001"));
        _assertRefused(bytes32("99999999999999999999999999999999"));
    }

    function test_LowercaseRefused() public {
        _assertRefused(bytes32("a"));
        _assertRefused(bytes32("alice"));
        _assertRefused(bytes32("Alice"));
        _assertRefused(bytes32("ALICe"));
        _assertRefused(bytes32("z9"));
    }

    function test_SymbolsAndNeighbouringBytesRefused() public {
        bytes1[10] memory bad = [
            bytes1("-"), bytes1("_"), bytes1(" "), bytes1("@"),
            bytes1(0x2F), bytes1(0x3A), bytes1(0x40), bytes1(0x5B), bytes1(0x60), bytes1(0x7B)
        ];
        for (uint256 i; i < bad.length; ++i) {
            _assertRefused(_bytes1Code(bad[i], "AB"));
            _assertRefused(_bytes1Code("A", bytes.concat(bad[i], "B")));
            _assertRefused(_bytes1Code("A", bytes.concat("B", bad[i])));
        }
        _assertRefused(bytes32(bytes.concat(bytes1(0x80), "AB")));
        _assertRefused(bytes32(bytes.concat("AB", bytes1(0xFF))));
    }

    function test_BoundaryBytesAccepted() public {
        // 0x30 '0', 0x39 '9', 0x41 'A', 0x5A 'Z' are the inclusive edges of the alphabet.
        _assertAccepted(_bytes1Code("0", "9AZ"));
        _assertAccepted(_bytes1Code("9", "0ZA"));
        _assertAccepted(_bytes1Code("Z", "A09"));
    }

    function test_InteriorZeroRefused() public {
        _assertRefused(bytes32(bytes.concat("AB", bytes1(0x00), "C")));
        _assertRefused(bytes32(bytes.concat("A", bytes1(0x00), "1")));
        _assertRefused(bytes32(bytes.concat("ABC", bytes1(0x00), bytes1(0x00), "D")));
    }

    function test_BuiltInCodesRegisteredAtBootstrap() public view {
        (address owner, uint32 ownerId, uint8 kickback) = affiliate.affiliateCode(bytes32("VAULT"));
        assertEq(owner, ContractAddresses.VAULT);
        assertEq(ownerId, 1);
        assertEq(kickback, 0);
        (owner, ownerId, kickback) = affiliate.affiliateCode(bytes32("DGNRS"));
        assertEq(owner, ContractAddresses.SDGNRS);
        assertEq(ownerId, 2);
        assertEq(kickback, 0);
        (owner, ownerId, kickback) = affiliate.affiliateCode(bytes32("GNRUS"));
        assertEq(owner, ContractAddresses.GNRUS);
        assertEq(ownerId, _id(ContractAddresses.GNRUS));
        assertEq(kickback, 10);
        assertTrue(_rule(bytes32("VAULT")) && _rule(bytes32("DGNRS")) && _rule(bytes32("GNRUS")));
    }

    function test_BuiltInCodesCannotBeReclaimed() public {
        bytes32[3] memory built = [bytes32("VAULT"), bytes32("DGNRS"), bytes32("GNRUS")];
        for (uint256 i; i < 3; ++i) {
            (bool ok, bytes4 sel) = _tryCreate(makeAddr("squatter"), built[i]);
            assertFalse(ok);
            assertEq(sel, DegenerusAffiliate.CodeTaken.selector);
        }
    }

    function test_CustomCodeShapeAcceptsAndRefusesExactlyTheRule() public {
        // Every first byte, and every pair drawn from the alphabet edges and their neighbours.
        bytes memory edges = hex"002D2F30393A40415A5B5F60617A7B2080FF";
        for (uint256 a; a < 256; ++a) {
            _checkAgainstRule(bytes32(uint256(a) << 248), a);
        }
        for (uint256 i; i < edges.length; ++i) {
            for (uint256 j; j < edges.length; ++j) {
                bytes32 two = bytes32((uint256(uint8(edges[i])) << 248) | (uint256(uint8(edges[j])) << 240));
                _checkAgainstRule(two, 256 + i * 64 + j);
            }
        }
    }

    function _checkAgainstRule(bytes32 code, uint256 salt) internal {
        address who = address(uint160(uint256(keccak256(abi.encode("shape", salt)))));
        bool taken = _rule(code) && _taken(code);
        (bool ok, bytes4 sel) = _tryCreate(who, code);
        assertEq(ok, _rule(code) && !taken, "accepts exactly the rule");
        if (!ok) assertEq(sel, taken ? DegenerusAffiliate.CodeTaken.selector : DegenerusAffiliate.InvalidCode.selector);
    }

    /// @dev `mode` selects how the candidate is built so both sides of the rule are exercised:
    ///      0 raw word, 1 prefix of alphabet-edge bytes, 2 well-formed text with one corrupted byte.
    function testFuzz_ShapeMatchesReference(bytes32 raw, uint8 len, uint8 mode, uint8 at, uint8 bad) public {
        bytes32 code;
        uint256 m = mode % 3;
        if (m == 0) {
            code = raw;
        } else {
            uint256 n = uint256(len) % 33;
            bytes memory b = new bytes(32);
            bytes memory edges = hex"2F3A40415A5B30396061787A7B2D5F20";
            for (uint256 i; i < n; ++i) {
                uint8 r = uint8(raw[i]);
                b[i] = m == 1 ? edges[r % edges.length] : bytes1(r % 2 == 0 ? 0x30 + (r >> 1) % 10 : 0x41 + (r >> 1) % 26);
            }
            if (m == 2 && n != 0) b[at % n] = bytes1(bad);
            code = bytes32(b);
        }
        address who = address(uint160(uint256(keccak256(abi.encode("fuzz", raw, len, mode, at, bad)))));
        bool taken = code != bytes32(0) && _taken(code);
        (bool ok, bytes4 sel) = _tryCreate(who, code);
        if (!_rule(code)) {
            assertFalse(ok);
            assertEq(sel, DegenerusAffiliate.InvalidCode.selector);
        } else if (taken) {
            assertFalse(ok);
            assertEq(sel, DegenerusAffiliate.CodeTaken.selector);
        } else {
            assertTrue(ok);
        }
    }

    function _taken(bytes32 code) internal view returns (bool) {
        (, uint32 ownerId,) = affiliate.affiliateCode(code);
        return ownerId != 0;
    }

    // ---------------------------------------------------------------------
    // 2. Digit text as an account ID
    // ---------------------------------------------------------------------

    /// @dev Referral word a first purchase with `code` leaves on `who`: 1 = no referrer, else
    ///      `2^32 | id`.
    function _purchaseWord(address who, bytes32 code) internal returns (uint256) {
        _buy(who, code);
        return _refWord(who);
    }

    function _viaRefer(address who, bytes32 code) internal returns (bool ok, bytes4 sel) {
        vm.prank(who);
        bytes memory ret;
        (ok, ret) = address(affiliate).call(abi.encodeCall(affiliate.referPlayer, (code)));
        sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
    }

    function _expectedWord(uint256 id, uint32 senderId) internal view returns (uint256) {
        if (id == 0 || id == senderId || id >= _nextId()) return ID_LOCKED;
        return ID_WORD_TAG | id;
    }

    /// @dev Both entries resolve `code` as the same account: the purchase path stores the tagged ID
    ///      word (or locks), the explicit path stores it (or refuses with UnknownCode).
    function _assertSameAsTag(uint256 id, bytes32 text) internal {
        uint256 want = _expectedWord(id, buyerId);
        uint256 snap = vm.snapshotState();
        uint256 viaTag = _purchaseWord(buyer, _tag(id));
        assertTrue(vm.revertToState(snap));
        uint256 viaText = _purchaseWord(buyer, text);
        assertEq(viaTag, want, "tag branch outcome");
        assertEq(viaText, viaTag, "digit text resolves like the tag");
        assertTrue(vm.revertToState(snap));

        (bool okTag, bytes4 selTag) = _viaRefer(buyer, _tag(id));
        assertTrue(vm.revertToState(snap));
        (bool okText, bytes4 selText) = _viaRefer(buyer, text);
        assertEq(okText, okTag, "explicit referral agrees");
        assertEq(selText, selTag, "explicit referral failure agrees");
        assertEq(okText, want != ID_LOCKED);
        if (!okText) assertEq(selText, DegenerusAffiliate.UnknownCode.selector);
        else assertEq(_refWord(buyer), want);
        assertTrue(vm.revertToState(snap));
        bool allocated = id != 0 && id < _nextId();

        (address ownerTag, uint32 idTag, uint8 kbTag) = affiliate.affiliateCode(_tag(id));
        (address ownerText, uint32 idText, uint8 kbText) = affiliate.affiliateCode(text);
        assertEq(ownerText, ownerTag);
        assertEq(idText, idTag);
        assertEq(kbText, kbTag);
        assertEq(kbText, 0);
        assertEq(idText, allocated ? uint32(id) : 0, "view mirrors allocation");
    }

    function test_ZeroTextHasNoReferrer() public {
        _assertSameAsTag(0, bytes32("0"));
        _assertSameAsTag(0, bytes32("00000"));
    }

    function test_OneTextIsTheVault() public {
        uint256 snap = vm.snapshotState();
        assertEq(_purchaseWord(buyer, bytes32("1")), ID_WORD_TAG | 1);
        assertTrue(vm.revertToState(snap));
        _assertSameAsTag(1, bytes32("1"));
        _assertSameAsTag(2, bytes32("2"));
    }

    function test_LeadingZerosResolveToTheSameId() public {
        _assertSameAsTag(1, bytes32("0001"));
        _assertSameAsTag(referrerId, _text(referrerId, 3));
        _assertSameAsTag(referrerId, _text(referrerId, 20));
        uint256 snap = vm.snapshotState();
        uint256 plain = _purchaseWord(buyer, _text(referrerId, 0));
        assertTrue(vm.revertToState(snap));
        assertEq(_purchaseWord(buyer, _text(referrerId, 9)), plain);
        assertEq(plain, ID_WORD_TAG | referrerId);
    }

    function test_AllocatedIdResolvesAndUnallocatedDoesNot() public {
        uint256 next = _nextId();
        _assertSameAsTag(next - 1, _text(next - 1, 0));
        _assertSameAsTag(next, _text(next, 0));
        _assertSameAsTag(next + 1, _text(next + 1, 0));
        _assertSameAsTag(next + 1000, _text(next + 1000, 2));
    }

    function test_OwnIdTextHasNoReferrer() public {
        _assertSameAsTag(buyerId, _text(buyerId, 0));
        _assertSameAsTag(buyerId, _text(buyerId, 4));
        (bool ok, bytes4 sel) = _viaRefer(buyer, _text(buyerId, 0));
        assertFalse(ok);
        assertEq(sel, DegenerusAffiliate.UnknownCode.selector);
    }

    function test_TextAboveUint32HasNoReferrerAndNeverReverts() public {
        bytes32[5] memory big = [
            bytes32("4294967296"),
            bytes32("4294967297"),
            bytes32("99999999999999999999"),
            bytes32("99999999999999999999999999999999"),
            bytes32("00000000004294967296")
        ];
        for (uint256 i; i < big.length; ++i) {
            uint256 snap = vm.snapshotState();
            assertEq(_purchaseWord(buyer, big[i]), ID_LOCKED, "purchase locks, no revert");
            assertTrue(vm.revertToState(snap));
            (bool ok, bytes4 sel) = _viaRefer(buyer, big[i]);
            assertFalse(ok);
            assertEq(sel, DegenerusAffiliate.UnknownCode.selector);
            (address owner, uint32 ownerId, uint8 kickback) = affiliate.affiliateCode(big[i]);
            assertEq(owner, address(0));
            assertEq(ownerId, 0);
            assertEq(kickback, 0);
        }
    }

    function test_MaxUint32TextResolvesOnlyWhenAllocated() public {
        bytes32 text = bytes32("4294967295");
        assertEq(_purchaseWord(buyer, text), ID_LOCKED, "unallocated");
        (, uint32 ownerId,) = affiliate.affiliateCode(text);
        assertEq(ownerId, 0);
        // Widen the registry so the last uint32 ID is allocated. Both buyers hold IDs already.
        address other = makeAddr("codeRulesOther");
        _giveWalletId(other);
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(uint256(1) << 32));
        (, ownerId,) = affiliate.affiliateCode(text);
        assertEq(ownerId, type(uint32).max, "view resolves");
        (, ownerId,) = affiliate.affiliateCode(_tag(type(uint32).max));
        assertEq(ownerId, type(uint32).max, "tag view resolves");
        (bool ok,) = _viaRefer(other, text);
        assertTrue(ok);
        assertEq(_refWord(other), ID_WORD_TAG | type(uint32).max);
        (, ownerId,) = affiliate.affiliateCode(bytes32("4294967296"));
        assertEq(ownerId, 0, "one past the top still resolves nothing");
    }

    function test_UnallocatedAndSelfOutcomesMatchTagBranch() public {
        uint256[4] memory ids = [uint256(0), 3, uint256(buyerId), uint256(_nextId()) + 7];
        for (uint256 i; i < ids.length; ++i) {
            _assertSameAsTag(ids[i], _text(ids[i], 0));
        }
    }

    function testFuzz_DigitTextMatchesTagBranch(uint32 raw, uint8 pad) public {
        uint256 span = uint256(_nextId()) + 4;
        uint256 id = uint256(raw) % span;
        _assertSameAsTag(id, _text(id, pad % 6));
    }

    function testFuzz_NonDigitTextNeverBecomesAnId(uint32 id, uint8 at, uint8 bad) public {
        // A digit string with one non-digit byte is a custom-code lookup, not an ID.
        bytes memory b = bytes(vm.toString(uint256(id) + 1));
        uint256 pos = uint256(at) % b.length;
        uint8 c = uint8(bad);
        vm.assume(c < 0x30 || c > 0x39);
        vm.assume(c != 0);
        b[pos] = bytes1(c);
        bytes32 code = bytes32(b);
        assertEq(_purchaseWord(buyer, code), ID_LOCKED);
    }

    // ---------------------------------------------------------------------
    // 3. Address, tag and digit routes agree
    // ---------------------------------------------------------------------

    struct Observed {
        uint256 word;
        uint32 referrerOf;
        address referrerAddress;
        uint256 score;
        uint256 total;
        uint256 flipReferrer;
        uint256 flipVault;
        uint256 flipSdgnrs;
        uint256 flipBuyer;
    }

    function _observe(bytes32 code) internal returns (Observed memory o) {
        uint24 lvl = game.currentLvl() + 1;
        _buy(buyer, code);
        o.word = _refWord(buyer);
        o.referrerOf = affiliate.getReferrerId(buyer);
        o.referrerAddress = affiliate.getReferrer(buyer);
        o.score = affiliate.affiliateScore(lvl, referrerId);
        o.total = affiliate.totalAffiliateScore(lvl);
        o.flipReferrer = coinflip.coinflipAmountById(referrerId);
        o.flipVault = coinflip.coinflipAmountById(1);
        o.flipSdgnrs = coinflip.coinflipAmountById(2);
        o.flipBuyer = coinflip.coinflipAmountById(buyerId);
    }

    function _assertSame(Observed memory a, Observed memory b, string memory what) internal pure {
        assertEq(a.word, b.word, string.concat(what, ": referral word"));
        assertEq(a.referrerOf, b.referrerOf, string.concat(what, ": referrer id"));
        assertEq(a.referrerAddress, b.referrerAddress, string.concat(what, ": referrer"));
        assertEq(a.score, b.score, string.concat(what, ": affiliate score"));
        assertEq(a.total, b.total, string.concat(what, ": level total"));
        assertEq(a.flipReferrer, b.flipReferrer, string.concat(what, ": referrer FLIP"));
        assertEq(a.flipVault, b.flipVault, string.concat(what, ": vault FLIP"));
        assertEq(a.flipSdgnrs, b.flipSdgnrs, string.concat(what, ": sDGNRS FLIP"));
        assertEq(a.flipBuyer, b.flipBuyer, string.concat(what, ": buyer FLIP"));
    }

    function test_AddressTagAndTextRoutesReachTheSameReferrerAndRewards() public {
        uint256 snap = vm.snapshotState();
        Observed memory viaAddress = _observe(_dflt(referrer));
        assertTrue(vm.revertToState(snap));
        Observed memory viaTag = _observe(_tag(referrerId));
        assertTrue(vm.revertToState(snap));
        Observed memory viaText = _observe(_text(referrerId, 0));
        assertTrue(vm.revertToState(snap));
        Observed memory viaPadded = _observe(_text(referrerId, 5));
        assertEq(viaAddress.word, ID_WORD_TAG | referrerId, "address route stores the tagged ID");
        assertEq(viaAddress.referrerAddress, referrer);
        assertEq(viaAddress.referrerOf, referrerId);
        _assertSame(viaAddress, viaTag, "address vs tag");
        _assertSame(viaAddress, viaText, "address vs digit text");
        _assertSame(viaAddress, viaPadded, "address vs padded digit text");
    }

    function test_ExplicitReferralRoutesStoreTheSameWord() public {
        bytes32[4] memory routes = [_dflt(referrer), _tag(referrerId), _text(referrerId, 0), _text(referrerId, 7)];
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < routes.length; ++i) {
            (bool ok,) = _viaRefer(buyer, routes[i]);
            assertTrue(ok);
            assertEq(_refWord(buyer), ID_WORD_TAG | referrerId);
            assertEq(affiliate.getReferrer(buyer), referrer);
            assertTrue(vm.revertToState(snap));
        }
    }

    function test_ViewsAgreeAcrossRoutes() public view {
        (address ownerA, uint32 idA, uint8 kbA) = affiliate.affiliateCode(_dflt(referrer));
        (address ownerT, uint32 idT, uint8 kbT) = affiliate.affiliateCode(_tag(referrerId));
        (address ownerD, uint32 idD, uint8 kbD) = affiliate.affiliateCode(_text(referrerId, 0));
        assertEq(ownerA, referrer);
        assertEq(ownerT, ownerA);
        assertEq(ownerD, ownerA);
        assertEq(idA, referrerId);
        assertEq(idT, idA);
        assertEq(idD, idA);
        assertEq(kbA + kbT + kbD, 0);
    }

    function testFuzz_RoutesAgreeForAnyAllocatedReferrer(uint8 pad, uint8 which) public {
        address r = makeAddr(string.concat("fuzzReferrer", vm.toString(which)));
        uint32 rid = _giveWalletId(r);
        uint256 snap = vm.snapshotState();
        (bool ok,) = _viaRefer(buyer, _dflt(r));
        assertTrue(ok);
        uint256 viaAddress = _refWord(buyer);
        assertTrue(vm.revertToState(snap));
        (ok,) = _viaRefer(buyer, _text(rid, pad % 8));
        assertTrue(ok);
        assertEq(_refWord(buyer), viaAddress);
        assertTrue(vm.revertToState(snap));
        (ok,) = _viaRefer(buyer, _tag(rid));
        assertTrue(ok);
        assertEq(_refWord(buyer), viaAddress);
        assertEq(viaAddress, ID_WORD_TAG | rid);
    }

    // ---------------------------------------------------------------------
    // 4. A small raw integer is an address, never an ID
    // ---------------------------------------------------------------------

    function test_SmallRawWordStaysOnTheAddressPath() public {
        // ID 5 exists as an account; the word 5 names the address 0x...05.
        while (_nextId() <= 5) _giveWalletId(address(uint160(0xE0000000 + _nextId())));
        address holderOfFive = _keyOf(5);
        assertTrue(holderOfFive != address(0));
        address named = address(uint160(5));
        assertEq(_id(named), 0);
        (address owner, uint32 ownerId,) = affiliate.affiliateCode(bytes32(uint256(5)));
        assertEq(owner, named, "view reads the word as an address");
        assertEq(ownerId, 0);
        uint256 scoreBefore = affiliate.affiliateScore(game.currentLvl() + 1, 5);
        _buy(buyer, bytes32(uint256(5)));
        uint32 namedId = _id(named);
        assertGt(namedId, 0, "the named address was registered");
        assertTrue(namedId != 5);
        assertEq(_refWord(buyer), ID_WORD_TAG | namedId, "referral is the address's ID");
        assertEq(affiliate.affiliateScore(game.currentLvl() + 1, 5), scoreBefore, "ID 5 earned nothing");
    }

    function testFuzz_SmallRawWordIsNeverReadAsId(uint16 small) public {
        uint256 w = uint256(bound(small, 2, type(uint16).max));
        while (_nextId() <= w && w < 64) _giveWalletId(address(uint160(0xE0000000 + _nextId())));
        address named = address(uint160(w));
        uint32 before = _id(named);
        uint256 nextBefore = _nextId();
        (bool ok,) = _viaRefer(buyer, bytes32(w));
        uint32 namedId = _id(named);
        if (ok) {
            assertEq(_refWord(buyer), ID_WORD_TAG | namedId);
            assertTrue(namedId != 0);
            if (before == 0 && w < nextBefore) assertTrue(namedId != uint32(w), "an allocated ID is not reached by its number");
        } else {
            assertEq(_refWord(buyer), 0);
        }
    }

    function test_SentinelWordsAreNotAddressesOrIds() public {
        // Words 0 and 1 are sentinels, not addresses and not IDs.
        (bool ok0, bytes4 s0) = _viaRefer(buyer, bytes32(0));
        assertFalse(ok0);
        assertEq(s0, DegenerusAffiliate.UnknownCode.selector);
        (bool ok1, bytes4 s1) = _viaRefer(buyer, bytes32(uint256(1)));
        assertFalse(ok1);
        assertEq(s1, DegenerusAffiliate.UnknownCode.selector);
        assertEq(_id(address(uint160(1))), 0);
    }
}
