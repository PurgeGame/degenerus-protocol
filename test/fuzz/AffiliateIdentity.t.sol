// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {AffiliateIdentityLib} from "../../contracts/libraries/AffiliateIdentityLib.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

contract AffiliateIdentitySeeder is DegenerusGameStorage {
    function length(uint256 n) external { assembly ("memory-safe") { sstore(wallets.slot, add(n, 1)) } }
    function presale(bool value) external { presaleOver = !value; }
    function rawOwner(uint32 id) external view returns (address) { return AffiliateIdentityLib.ownerOf(id); }
}

contract AffiliateIdentityTest is DeployProtocol {
    uint256 constant CAP = 3_000_000_000;
    bytes32 constant A = bytes32("ID_A");
    bytes32 constant B = bytes32("ID_B");
    bytes32 constant C = bytes32("ID_C");
    address a = address(0xA11);
    address b = address(0xB11);
    address c = address(0xC11);
    DegenerusGameLens lens;

    function setUp() public {
        _deployProtocol(); lens = new DegenerusGameLens();
        vm.prank(a); affiliate.createAffiliateCode(A, 12);
        vm.prank(b); affiliate.createAffiliateCode(B, 0);
        vm.prank(c); affiliate.createAffiliateCode(C, 25);
    }

    function _seed(bytes memory data) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(AffiliateIdentitySeeder).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), code);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }
    function _length(uint256 n) private { _seed(abi.encodeCall(AffiliateIdentitySeeder.length, (n))); }
    function _id(address owner) private view returns (uint32) { return lens.walletIdOf(address(game), owner); }
    function _buyer(bytes32 code, uint256 branch, uint256 start) private view returns (address buyer) {
        for (uint256 i = start; ; ++i) {
            buyer = address(uint160(0x100000 + i));
            uint256 roll = uint256(keccak256(abi.encodePacked(keccak256("affiliate-payout-roll-v1"), GameTimeLib.currentDayIndex(), buyer, code))) % 20;
            if ((branch == 0 && roll < 15) || (branch == 1 && roll >= 15 && roll < 19) || (branch == 2 && roll == 19)) return buyer;
        }
    }
    function _pay(bytes32 code, uint256 branch, uint256 nonce) private returns (address winner) {
        address buyer = _buyer(code, branch, nonce);
        vm.prank(address(game));
        (winner,,) = affiliate.payAffiliateCombined(code, buyer, 5, 10000, 0, 0, 0, 0);
    }
    function _earningsSlot(uint24 lvl, address owner) private pure returns (bytes32) {
        return keccak256(abi.encode(owner, keccak256(abi.encode(lvl, uint256(1)))));
    }
    function _earningsWord(uint24 lvl, address owner) private view returns (uint256) {
        return uint256(vm.load(address(affiliate), _earningsSlot(lvl, owner)));
    }
    function _codeWord(bytes32 code) private view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(code, uint256(0)))));
    }

    function test_DefaultCodeFirstUseRegistersOnlyIdentityAndAliasesShareIt() public {
        address fresh = address(0xD11);
        bytes32 aliasCode = bytes32("DEFAULT_ALIAS");
        bytes32 defaultCode = bytes32(uint256(uint160(fresh)));
        assertEq(_id(fresh), 0);
        vm.recordLogs();
        vm.prank(b); affiliate.referPlayer(defaultCode);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 entry = keccak256("EntriesQueued(uint32,uint24,uint32)");
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != entry, "identity emitted a ticket entry");
        uint32 id = _id(fresh);
        assertGt(id, 0);
        assertEq(affiliate.affiliateWalletId(defaultCode), id);
        assertEq(game.entriesOwedView(1, fresh), 0);
        vm.prank(fresh); affiliate.createAffiliateCode(aliasCode, 12);
        vm.prank(c); affiliate.referPlayer(aliasCode);
        assertEq(affiliate.affiliateWalletId(aliasCode), id);
        (address owner, uint8 kickback) = affiliate.affiliateCode(aliasCode);
        assertEq(owner, fresh); assertEq(kickback, 12);
        (, kickback) = affiliate.affiliateCode(defaultCode);
        assertEq(kickback, 0);
        assertEq(_codeWord(defaultCode), 0, "default identity created a code slot");
    }

    function test_IdentityAndTicketsReuseRegistryInBothOrders() public {
        uint32 original = _id(a);
        assertGt(original, 0, "custom creation did not register owner");
        vm.deal(a, 1 ether);
        vm.prank(a); game.purchase{value: 0.01 ether}(a, 400, 0, B, MintPaymentKind.DirectEth, false);
        assertEq(_id(a), original);
        address fresh = address(0xD11);
        bytes32 freshCode = bytes32("TICKET_FIRST");
        vm.deal(fresh, 1 ether);
        vm.prank(fresh); game.purchase{value: 0.01 ether}(fresh, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint32 ticketId = _id(fresh);
        vm.prank(fresh); affiliate.createAffiliateCode(freshCode, 7);
        assertEq(_id(fresh), ticketId);
        assertEq(affiliate.affiliateWalletId(freshCode), ticketId);
    }

    function test_CapAllowsLastIdExistingAliasesAndAtomicFailure() public {
        address lastOwner = address(0xD11);
        address rejected = address(0xE11);
        bytes32 lastCode = bytes32("LAST_ID");
        bytes32 rejectedCode = bytes32("REJECTED_ID");
        _length(CAP - 1);
        vm.prank(lastOwner); affiliate.createAffiliateCode(lastCode, 9);
        assertEq(_id(lastOwner), CAP);
        vm.prank(lastOwner); affiliate.createAffiliateCode(bytes32("LAST_ALIAS"), 25);
        vm.prank(a); affiliate.createAffiliateCode(bytes32("EXISTING_ALIAS"), 0);
        vm.prank(c); affiliate.referPlayer(bytes32(uint256(uint160(lastOwner))));
        assertEq(_id(lastOwner), CAP);
        vm.expectRevert(bytes4(keccak256("E()")));
        vm.prank(rejected); affiliate.createAffiliateCode(rejectedCode, 0);
        assertEq(_id(rejected), 0);
        (address owner,) = affiliate.affiliateCode(rejectedCode);
        assertEq(owner, address(0), "failed creation reserved a code");
        vm.expectRevert(bytes4(keccak256("E()")));
        vm.prank(b); affiliate.referPlayer(bytes32(uint256(uint160(rejected))));
        assertEq(affiliate.getReferrer(b), ContractAddresses.VAULT);
        vm.prank(b); affiliate.referPlayer(lastCode);
        assertEq(affiliate.getReferrer(b), lastOwner);
    }

    function test_OptionalUnregisteredUplineStillPaysAtCapacity() public {
        // A valid default-address referral can exist before its owner receives an ID.
        address unregistered = address(0xF11);
        vm.store(address(affiliate), keccak256(abi.encode(a, uint256(2))), bytes32(uint256(uint160(unregistered))));
        _length(CAP);
        assertEq(_pay(A, 1, 0), unregistered);
        assertGt(_id(a), 0);
        assertEq(_id(unregistered), 0);
        assertEq((_earningsWord(5, a) >> 192) & 1, 0, "missing ID marked a cache valid");
    }

    function test_LateReferralAndSecondHopAreNotFrozenByEarlierPayouts() public {
        assertEq(_pay(A, 1, 0), ContractAddresses.VAULT);
        assertEq((_earningsWord(5, a) >> 192) & 3, 0);
        vm.prank(a); affiliate.referPlayer(B);
        assertEq(_pay(A, 1, 100), b);
        assertEq(_pay(A, 2, 200), ContractAddresses.VAULT);
        assertEq((_earningsWord(5, a) >> 192) & 3, 1, "unset second hop cached a fallback");
        vm.prank(b); affiliate.referPlayer(C);
        assertEq(_pay(A, 2, 300), c);
        assertEq((_earningsWord(5, a) >> 192) & 3, 3);
        assertEq(_pay(A, 1, 400), b);
        assertEq(_pay(A, 2, 500), c);
        (address owner, uint8 kickback) = affiliate.affiliateCode(A);
        assertEq(owner, a); assertEq(kickback, 12);
    }

    function test_PresaleVaultReferralIsPermanentAndCacheable() public {
        _seed(abi.encodeCall(AffiliateIdentitySeeder.presale, (true)));
        vm.prank(a); affiliate.referPlayer(bytes32("VAULT"));
        assertEq(_pay(A, 1, 0), ContractAddresses.VAULT);
        assertEq((_earningsWord(5, a) >> 192) & 1, 1);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        vm.prank(a); affiliate.referPlayer(B);
        vm.prank(address(game));
        affiliate.payAffiliateCombined(B, a, 5, 10000, 0, 0, 0, 0);
        assertEq(affiliate.getReferrer(a), ContractAddresses.VAULT);
        vm.prank(address(game)); affiliate.payAffiliate(10000, C, a, 5, true, 0);
        assertEq(affiliate.getReferrer(a), ContractAddresses.VAULT);
        assertEq(_pay(A, 1, 100), ContractAddresses.VAULT);
    }

    function test_PresaleLockedDefaultCannotBeReplaced() public {
        _seed(abi.encodeCall(AffiliateIdentitySeeder.presale, (true)));
        vm.prank(address(game)); affiliate.payAffiliate(10000, bytes32(0), a, 5, true, 0);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        vm.prank(a); affiliate.referPlayer(B);
        vm.prank(address(game)); affiliate.payAffiliate(10000, B, a, 5, true, 0);
        vm.prank(address(game)); affiliate.payAffiliateCombined(C, a, 5, 10000, 0, 0, 0, 0);
        assertEq(affiliate.getReferrer(a), ContractAddresses.VAULT);
    }

    function test_MissingUplineIdFallsBackWithoutAllocatingEvenBelowCap() public {
        address unregistered = address(0xF11);
        vm.store(address(affiliate), keccak256(abi.encode(a, uint256(2))), bytes32(uint256(uint160(unregistered))));
        assertEq(_pay(A, 1, 0), unregistered);
        assertEq(_id(unregistered), 0);
        assertEq((_earningsWord(5, a) >> 192) & 1, 0);
        // Once independently registered, the next hit can fill the same earnings word.
        vm.prank(unregistered); affiliate.createAffiliateCode(bytes32("LATER_ID"), 0);
        assertEq(_pay(A, 1, 100), unregistered);
        assertEq(uint32(_earningsWord(5, a) >> 128), _id(unregistered));
    }

    function test_DefaultCacheSharesEarningsWriteAndRefillsAcrossLevels() public {
        vm.prank(a); affiliate.referPlayer(B);
        vm.prank(b); affiliate.referPlayer(C);
        bytes32 code = bytes32(uint256(uint160(a)));
        assertEq(_pay(code, 2, 0), c);
        uint256 first = _earningsWord(5, a);
        assertEq(uint128(first), 2000);
        assertEq(uint32(first >> 128), _id(b));
        assertEq(uint32(first >> 160), _id(c));
        assertEq(first >> 192, 3);
        assertEq(_codeWord(code), 0, "default route wrote a code word");
        assertEq(_pay(code, 0, 100), a);
        assertEq(_earningsWord(5, a) >> 128, first >> 128, "direct hit erased cache");
        assertEq(affiliate.affiliateScore(5, a), 4000);
        assertEq(affiliate.totalAffiliateScore(5), 4000);
        // Bonus points must ignore the high cache bits.
        uint256 bonus = affiliate.affiliateBonusPointsBest(6, a);
        vm.store(address(affiliate), _earningsSlot(5, a), bytes32(uint256(4000)));
        assertEq(affiliate.affiliateBonusPointsBest(6, a), bonus);
        vm.store(address(affiliate), _earningsSlot(5, a), bytes32(_earningsWord(5, a) | (first & ~uint256(type(uint128).max))));
        address buyer = _buyer(code, 2, 200);
        vm.prank(address(game));
        (address winner,,) = affiliate.payAffiliateCombined(code, buyer, 6, 10000, 0, 0, 0, 0);
        assertEq(winner, c);
        assertEq(_earningsWord(6, a) >> 128, first >> 128);
        assertEq(affiliate.affiliateScore(6, a), 2000);
        assertEq(_codeWord(code), 0);
    }

    function test_CustomCreationCapturesPermanentLinksWithoutLaterCodeWrites() public {
        vm.prank(a); affiliate.referPlayer(B);
        vm.prank(b); affiliate.referPlayer(C);
        bytes32 code = bytes32("CACHED_AT_CREATION");
        vm.prank(a); affiliate.createAffiliateCode(code, 15);
        uint256 beforeWord = _codeWord(code);
        assertEq(uint32(beforeWord >> 168), _id(b));
        assertEq(uint32(beforeWord >> 200), _id(c));
        assertEq((beforeWord >> 232) & 7, 7);
        assertEq(_pay(code, 2, 0), c);
        assertEq(_codeWord(code), beforeWord);
        assertEq(affiliate.affiliateScore(5, a), 2000);
    }

    function test_EarningsWidthBoundaryRevertsWithoutCorruptingCache() public {
        vm.prank(a); affiliate.referPlayer(B);
        assertEq(_pay(A, 1, 0), b);
        uint256 cache = _earningsWord(5, a) & ~uint256(type(uint128).max);
        vm.store(address(affiliate), _earningsSlot(5, a), bytes32(cache | (uint256(type(uint128).max) - 2000)));
        assertEq(_pay(A, 0, 100), a);
        assertEq(affiliate.affiliateScore(5, a), type(uint128).max);
        uint256 beforeWord = _earningsWord(5, a);
        address buyer = _buyer(A, 1, 200);
        vm.expectRevert(bytes4(keccak256("EarningsOverflow()")));
        vm.prank(address(game)); affiliate.payAffiliateCombined(A, buyer, 5, 10000, 0, 0, 0, 0);
        assertEq(_earningsWord(5, a), beforeWord);
    }

    function test_RawIdentityRootsAndZeroUnallocatedBounds() public {
        AffiliateIdentitySeeder seeder = new AffiliateIdentitySeeder();
        assertEq(seeder.rawOwner(0), address(0));
        assertEq(seeder.rawOwner(uint32(CAP)), address(0));
        assertEq(seeder.rawOwner(type(uint32).max), address(0));
        vm.prank(b); affiliate.referPlayer(A);
        assertEq(seeder.rawOwner(_id(a)), a);
        assertEq(seeder.rawOwner(_id(c) + 1), address(0));
    }

    function test_UnauthorizedAllocationCannotConsumeAnId() public {
        address fresh = address(0xD11);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.registerWallet(fresh, false);
        assertEq(_id(fresh), 0);
    }

    function test_CustomCreationRegistersWithoutTicketsAndPreservesAliasConfiguration() public {
        address fresh = address(0xD11);
        vm.recordLogs();
        vm.prank(fresh); affiliate.createAffiliateCode(bytes32("NEW_CUSTOM"), 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 entry = keccak256("EntriesQueued(uint32,uint24,uint32)");
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != entry);
        uint32 id = _id(fresh);
        assertGt(id, 0);
        assertEq(game.entriesOwedView(1, fresh), 0);
        vm.prank(fresh); affiliate.createAffiliateCode(bytes32("NEW_ALIAS"), 25);
        assertEq(_id(fresh), id);
        (address owner, uint8 kickback) = affiliate.affiliateCode(bytes32("NEW_CUSTOM"));
        assertEq(owner, fresh); assertEq(kickback, 4);
        (owner, kickback) = affiliate.affiliateCode(bytes32("NEW_ALIAS"));
        assertEq(owner, fresh); assertEq(kickback, 25);
        assertEq((_codeWord(bytes32("NEW_CUSTOM")) >> 232) & 1, 1);
    }
}
