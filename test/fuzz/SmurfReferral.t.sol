// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title Smurf referrals
/// @notice `createSmurf` resolves the owner's referral exactly as a purchase would, then the
///         Affiliate's Game-only `copyReferral` copies the owner's resolved word to the smurf,
///         verbatim and permanent. A smurf's default code is a code like any other: its
///         affiliate credits land on the smurf's ID and value reaches the owner.
contract SmurfReferralTest is DeployProtocol {
    // DegenerusAffiliate roots (scripts/layout/golden/DegenerusAffiliate.json).
    uint256 internal constant CODE_ROOT = 0;
    uint256 internal constant REFERRAL_ROOT = 2;
    uint256 internal constant BOOT_OWNER_ROOT = 4;
    /// @dev `AffiliateCodeInfo.flags` sits at byte 13 of the packed code word; bit 0 = PENDING.
    uint256 internal constant CODE_FLAGS_SHIFT = 104;

    bytes32 internal constant ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    bytes32 internal constant LOCKED = bytes32(uint256(1));
    bytes32 internal constant REFERRAL_UPDATED = keccak256("ReferralUpdated(uint32,bytes32,uint32,bool)");
    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant SMURF_CREATED = keccak256("SmurfCreated(uint32,uint32)");
    bytes32 internal constant EARNINGS_RECORDED = keccak256("AffiliateEarningsRecorded(uint32,uint256)");
    bytes32 internal constant TOP_REWARD_SIG = keccak256("AffiliateDgnrsReward(address,uint24,uint256)");
    bytes4 internal constant CREDIT_PAIR = bytes4(keccak256("creditFlipPair(uint32,uint256,uint32,uint256)"));
    uint256 internal constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint256 internal constant POOL_HALF_MASK = (uint256(1) << 128) - 1;

    bytes32 internal constant CODE_R = bytes32("SMURF_REF_R");
    bytes32 internal constant CODE_OTHER = bytes32("SMURF_REF_OTHER");
    bytes32 internal constant CODE_BOOT = bytes32("SMURF_REF_BOOT");
    bytes32 internal constant CODE_SELF = bytes32("SMURF_REF_SELF");

    address internal owner = makeAddr("smurf-ref-owner");
    address internal referrer = makeAddr("smurf-ref-referrer");
    address internal other = makeAddr("smurf-ref-other");
    address internal third = makeAddr("smurf-ref-third");
    address internal stranger = makeAddr("smurf-ref-stranger");
    address internal bootOwner = address(0xB0075EED0001);
    address internal driveBuyer = makeAddr("smurf-ref-drive-buyer");
    uint256 private _dummies;
    uint256 private _buyerNonce;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ── fixtures ─────────────────────────────────────────────────────────────

    struct RefEvent {
        bool found;
        uint256 index;
        bytes32 code;
        uint32 referrerId;
        bool locked;
    }

    function _refWord(address player) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(_fixtureId(player), REFERRAL_ROOT))));
    }
    function _refWord(uint32 player) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(_fixtureId(player), REFERRAL_ROOT))));
    }

    function _dflt(address a) internal pure returns (bytes32) { return bytes32(uint256(uint160(a))); }
    function _dflt(uint32 id) internal view returns (bytes32) { return affiliate.defaultCodeById(id); }

    function _nextId() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
    }

    function _price() internal view returns (uint256 p) {
        (,,,, p) = game.purchaseInfo();
    }

    function _buy(address buyer, bytes32 code) internal {
        uint256 p = _price();
        vm.deal(buyer, buyer.balance + p);
        vm.prank(buyer);
        game.purchase{value: p}(0, 400, 0, code, MintPaymentKind.DirectEth, false);
    }

    function _createSmurf(address o, bytes32 code) internal returns (uint32 id, uint32 key, Vm.Log[] memory logs) {
        uint256 p = _price();
        vm.deal(o, o.balance + p);
        vm.recordLogs();
        vm.prank(o);
        id = game.createSmurf{value: p}(code, MintPaymentKind.DirectEth);
        logs = vm.getRecordedLogs();
        key = id;
    }

    /// @dev A constructor-created code whose owner had no wallet ID, written as the constructor
    ///      writes it: owner ID 0, the kickback, the PENDING flag, and the side-map owner.
    function _installBootstrap(bytes32 code, address o, uint8 kick) internal {
        vm.prank(o);
        affiliate.createAffiliateCode(code, kick);
        (address codeOwner, uint32 codeOwnerId, uint8 kickback) = affiliate.affiliateCode(code);
        assertEq(codeOwner, o);
        assertEq(codeOwnerId, game.walletIdOf(o));
        assertEq(kickback, kick);
    }

    function _refEvent(Vm.Log[] memory logs, address player) internal view returns (RefEvent memory e) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(affiliate) || logs[i].topics.length != 4) continue;
            if (logs[i].topics[0] != REFERRAL_UPDATED) continue;
            if (uint32(uint256(logs[i].topics[1])) != _fixtureId(player)) continue;
            assertFalse(e.found, "one ReferralUpdated per player");
            e.found = true;
            e.index = i;
            e.code = logs[i].topics[2];
            e.referrerId = uint32(uint256(logs[i].topics[3]));
            e.locked = abi.decode(logs[i].data, (bool));
        }
    }
    function _refEvent(Vm.Log[] memory logs, uint32 player) internal view returns (RefEvent memory e) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(affiliate) || logs[i].topics.length != 4) continue;
            if (logs[i].topics[0] != REFERRAL_UPDATED) continue;
            if (uint32(uint256(logs[i].topics[1])) != _fixtureId(player)) continue;
            assertFalse(e.found, "one ReferralUpdated per player");
            e.found = true;
            e.index = i;
            e.code = logs[i].topics[2];
            e.referrerId = uint32(uint256(logs[i].topics[3]));
            e.locked = abi.decode(logs[i].data, (bool));
        }
    }

    function _logIndex(Vm.Log[] memory logs, address emitter, bytes32 sig, uint256 topic1) internal pure returns (uint256) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != emitter || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint256(logs[i].topics[1]) == topic1) return i;
        }
        return type(uint256).max;
    }

    /// @dev The smurf's word, views and event are the owner's: the projection a purchase would
    ///      have emitted for the owner.
    function _assertCopied(Vm.Log[] memory logs, address o, uint32 s, bytes32 code, uint32 refId, bool locked)
        internal
        view
    {
        assertTrue(_refWord(o) != 0, "the owner's referral was resolved");
        assertEq(_refWord(s), _refWord(o), "the smurf's word is the owner's");
        RefEvent memory e = _refEvent(logs, s);
        assertTrue(e.found, "ReferralUpdated for the smurf");
        uint256 c = uint256(code);
        bytes32 expectedCode = code;
        if (c > 1 && c < (uint256(1) << 192)) expectedCode = bytes32((uint256(1) << 32) | refId);
        assertEq(e.code, expectedCode, "copy event carries resolved ID code");
        assertEq(e.referrerId, refId, "event referrer ID");
        assertEq(e.locked, locked, "event locked flag");
        assertEq(affiliate.getReferrerIdById(_fixtureId(s)), affiliate.getReferrerIdById(_fixtureId(o)), "getReferrerId");
        assertEq(affiliate.getReferrerIdById(_fixtureId(s)), affiliate.getReferrerIdById(_fixtureId(o)), "referrer owner ID");
        (uint32 a1, uint32 u1, uint32 v1) = affiliate.referrerIdsById(_fixtureId(s));
        (uint32 a2, uint32 u2, uint32 v2) = affiliate.referrerIdsById(_fixtureId(o));
        assertEq(a1, a2, "referrerIds affiliate");
        assertEq(u1, u2, "referrerIds upline1");
        assertEq(v1, v2, "referrerIds upline2");
    }

    function _entropy(uint32 buyerId, bytes32 code) internal view returns (uint256) {
        uint24 d = GameTimeLib.currentDayIndexAt(vm.getBlockTimestamp());
        uint256 c = uint256(code);
        if (c > 1 && c <= type(uint160).max) {
            uint32 id = game.walletIdOf(address(uint160(c)));
            if (id == 0) id = _nextId();
            code = bytes32((uint256(1) << 32) | id);
        } else if (c >> 32 == (uint256(1) << 128)) code = bytes32((uint256(1) << 32) | uint32(c));
        return uint256(keccak256(abi.encodePacked(ROLL_TAG, d, buyerId, code)));
    }

    /// @dev 0 = the code's owner (roll < 15), 1 = upline1 (15..18), 2 = upline2 (19).
    function _class(uint32 buyerId, bytes32 code) internal view returns (uint8) {
        uint256 r = _entropy(buyerId, code) % 20;
        return r < 15 ? 0 : (r < 19 ? 1 : 2);
    }

    /// @dev Registers throwaway wallets until the next allocated ID rolls `cls` for `code`.
    function _bumpIdsUntil(bytes32 code, uint8 cls) internal returns (uint32 next) {
        next = _nextId();
        while (_class(next, code) != cls) {
            _giveWalletId(address(uint160(0xD0000000 + ++_dummies)));
            next = _nextId();
        }
    }

    function _pairCall(Vm.AccountAccess[] memory a)
        internal
        view
        returns (bool found, uint32 id1, uint256 amount1, uint32 id2, uint256 amount2)
    {
        for (uint256 i; i < a.length; ++i) {
            if (a[i].account != address(coinflip) || a[i].kind != VmSafe.AccountAccessKind.Call) continue;
            bytes memory d = a[i].data;
            if (d.length != 132 || bytes4(d) != CREDIT_PAIR) continue;
            assembly ("memory-safe") {
                id1 := mload(add(d, 36))
                amount1 := mload(add(d, 68))
                id2 := mload(add(d, 100))
                amount2 := mload(add(d, 132))
            }
            found = true;
        }
    }

    // ── 11. copyReferral ─────────────────────────────────────────────────────

    function test_copyReferralFromADefaultCode() public {
        uint32 rId = _giveWalletId(referrer);
        _giveWalletId(owner);
        (, uint32 s, Vm.Log[] memory logs) = _createSmurf(owner, _dflt(referrer));
        assertEq(_refWord(owner), (uint256(1) << 32) | rId, "default word");
        _assertCopied(logs, owner, s, _dflt(referrer), rId, false);
        RefEvent memory own = _refEvent(logs, owner);
        assertTrue(own.found && own.code == _dflt(referrer) && own.referrerId == rId && !own.locked,
            "the projection is the owner's own");
        assertEq(affiliate.getReferrerById(_fixtureId(s)), referrer);
    }

    function test_copyReferralFromACustomCode() public {
        vm.prank(referrer);
        affiliate.createAffiliateCode(CODE_R, 10);
        uint32 rId = game.walletIdOf(referrer);
        _giveWalletId(owner);
        (, uint32 s, Vm.Log[] memory logs) = _createSmurf(owner, CODE_R);
        assertEq(_refWord(owner), uint256(CODE_R), "custom word");
        _assertCopied(logs, owner, s, CODE_R, rId, false);
        assertEq(affiliate.getReferrerById(_fixtureId(s)), referrer);
    }

    /// @dev A bootstrap code still pending its owner is materialized by the zero-amount
    ///      `payAffiliate` touch inside `createSmurf`, before the smurf is allocated.
    function test_copyReferralFromABootstrapCodeMaterializedByTheTouch() public {
        _installBootstrap(CODE_BOOT, bootOwner, 7);
        assertGt(game.walletIdOf(bootOwner), 0, "bootstrap owner registered");
        _giveWalletId(owner);
        (uint32 sId, uint32 s, Vm.Log[] memory logs) = _createSmurf(owner, CODE_BOOT);
        uint32 bootId = game.walletIdOf(bootOwner);
        assertGt(bootId, 0, "the touch registered the bootstrap owner");
        assertLt(bootId, sId, "before the smurf was allocated");
        (, uint32 codeOwnerId,) = affiliate.affiliateCode(CODE_BOOT);
        assertEq(codeOwnerId, bootId);
        _assertCopied(logs, owner, s, CODE_BOOT, bootId, false);
        assertEq(affiliate.getReferrerById(_fixtureId(s)), bootOwner);
    }

    function test_copyReferralFromALockedOwner() public {
        _giveWalletId(owner);
        (, uint32 s, Vm.Log[] memory logs) = _createSmurf(owner, bytes32(0));
        assertEq(_refWord(owner), 1, "a blank code locks the owner");
        _assertCopied(logs, owner, s, LOCKED, 1, true);
        assertEq(affiliate.getReferrerIdById(_fixtureId(s)), 1);
        (uint32 a, uint32 u1, uint32 u2) = affiliate.referrerIdsById(_fixtureId(s));
        assertEq(a, 1);
        assertEq(u1, 2);
        assertEq(u2, 1);
    }

    function test_copyReferralIsGameOnly() public {
        address key = makeAddr("smurf-ref-key");
        uint32 ownerId = game.walletIdOf(owner); uint32 keyId = _giveWalletId(key);
        vm.prank(stranger);
        vm.expectRevert(DegenerusAffiliate.OnlyAuthorized.selector);
        affiliate.copyReferral(ownerId, keyId);
        vm.prank(owner);
        vm.expectRevert(DegenerusAffiliate.OnlyAuthorized.selector);
        affiliate.copyReferral(ownerId, keyId);
        assertEq(_refWord(key), 0);
    }

    /// @dev The copy reads views only: even an owner word naming a still-pending bootstrap code
    ///      registers nobody, and no external call is made.
    function test_copyReferralRegistersNobodyAndCallsNothing() public {
        _installBootstrap(CODE_BOOT, bootOwner, 3);
        vm.store(address(affiliate), keccak256(abi.encode(game.walletIdOf(owner), REFERRAL_ROOT)), CODE_BOOT);
        address key = makeAddr("smurf-ref-direct-key");
        uint32 ownerId = game.walletIdOf(owner); uint32 keyId = _giveWalletId(key);

        vm.expectCall(address(game), abi.encodeWithSelector(game.registerWallet.selector), 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(address(game));
        affiliate.copyReferral(ownerId, keyId);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind == VmSafe.AccountAccessKind.Call || acc[i].kind == VmSafe.AccountAccessKind.StaticCall
                || acc[i].kind == VmSafe.AccountAccessKind.DelegateCall) {
                assertEq(acc[i].account, address(affiliate), "copyReferral made an external call");
            }
        }
        assertEq(_refWord(key), uint256(CODE_BOOT), "the word was copied verbatim");
        RefEvent memory e = _refEvent(logs, key);
        assertTrue(e.found);
        assertEq(e.code, CODE_BOOT);
        assertEq(e.referrerId, game.walletIdOf(bootOwner), "bootstrap owner ID");
        assertFalse(e.locked);
        assertEq(game.walletIdOf(bootOwner), e.referrerId, "copy preserved bootstrap registration");
    }

    // ── 12. Permanence and order ─────────────────────────────────────────────

    function test_aSmurfsReferralIsPermanent() public {
        uint32 rId = _giveWalletId(referrer);
        _giveWalletId(owner);
        (uint32 sId, uint32 s,) = _createSmurf(owner, _dflt(referrer));
        uint256 word = _refWord(s);

        vm.prank(other);
        affiliate.createAffiliateCode(CODE_OTHER, 5);
        uint256 p = _price();
        vm.deal(owner, owner.balance + p);
        vm.recordLogs();
        vm.prank(owner);
        game.purchase{value: p}(sId, 400, 0, CODE_OTHER, MintPaymentKind.DirectEth, false);
        assertFalse(_refEvent(vm.getRecordedLogs(), s).found, "no referral write for the smurf");
        assertEq(_refWord(s), word, "a purchase with another code keeps the copied referrer");
        assertEq(affiliate.getReferrerIdById(_fixtureId(s)), rId);
    }

    /// @dev H-F2: the owner's referral is resolved first, then the smurf is allocated, then the
    ///      word is copied, then the smurf's ticket settles its affiliate leg on the copied word.
    function test_createSmurfResolvesTheOwnerThenAllocatesThenCopiesThenBuys() public {
        uint32 rId = _giveWalletId(referrer);
        uint32 oId = _giveWalletId(owner);
        (uint32 sId, uint32 s, Vm.Log[] memory logs) = _createSmurf(owner, _dflt(referrer));
        uint256 iOwner = _refEvent(logs, owner).index;
        uint256 iReg = _logIndex(logs, address(game), WALLET_REGISTERED, sId);
        uint256 iCreated = _logIndex(logs, address(game), SMURF_CREATED, oId);
        uint256 iCopy = _refEvent(logs, s).index;
        uint256 iEarn = type(uint256).max;
        for (uint256 i = iCopy; i < logs.length; ++i) {
            if (logs[i].emitter == address(affiliate) && logs[i].topics.length == 2
                && logs[i].topics[0] == EARNINGS_RECORDED && uint256(logs[i].topics[1]) == rId) {
                iEarn = i;
                break;
            }
        }
        assertTrue(_refEvent(logs, owner).found, "the owner was resolved in this call");
        assertEq(iReg, type(uint256).max, "subaccounts emit no WalletRegistered");
        assertTrue(iCreated != type(uint256).max, "subaccount allocated");
        assertLt(iOwner, iCreated, "owner resolved before allocation");
        assertLt(iCreated, iCopy, "the copy follows the allocation");
        assertTrue(iEarn != type(uint256).max, "the smurf's ticket booked its affiliate on the copied word");
        assertEq(_refWord(s), _refWord(owner));
        assertTrue(_refWord(s) != 0);
    }

    // ── 13. No self-referral ─────────────────────────────────────────────────

    function test_aSmurfsDirectAffiliateIsNeverItsOwner() public {
        _giveWalletId(referrer);
        vm.prank(referrer);
        affiliate.createAffiliateCode(CODE_R, 0);
        _installBootstrap(CODE_BOOT, bootOwner, 0);
        for (uint256 form; form < 7; ++form) {
            address o = address(uint160(uint256(keccak256(abi.encode("smurf-ref-self", form)))));
            uint32 oId = _giveWalletId(o);
            bytes32 code;
            if (form == 0) code = _dflt(referrer);
            else if (form == 1) code = CODE_R;
            else if (form == 2) code = CODE_BOOT;
            else if (form == 3) code = bytes32(0);
            else if (form == 4) code = _dflt(o);
            else if (form == 5) {
                vm.prank(o);
                affiliate.createAffiliateCode(CODE_SELF, 0);
                code = CODE_SELF;
            } else {
                // Referred earlier by a purchase; the smurf call then names the owner itself.
                _buy(o, _dflt(referrer));
                code = _dflt(o);
            }
            (, uint32 s,) = _createSmurf(o, code);
            if (form == 4 || form == 5) assertEq(_refWord(o), 1, "a self-referral locks the owner");
            assertEq(_refWord(s), _refWord(o), "the smurf copies the owner's word");
            assertTrue(affiliate.getReferrerIdById(_fixtureId(s)) != oId, "the smurf's referrer is never its owner");
            assertTrue(affiliate.getReferrerById(_fixtureId(s)) != o, "the smurf's referrer address is never its owner");
            (uint32 a,,) = affiliate.referrerIdsById(_fixtureId(s));
            assertTrue(a != oId, "the smurf's direct affiliate is never its owner");
        }
    }

    // ── 14. A third party uses a smurf's default code ────────────────────────

    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function test_aThirdPartyOnASmurfsDefaultCodeCreditsTheSmurfAndPaysTheOwner() public {
        _giveWalletId(owner);
        (uint32 sId, uint32 s,) = _createSmurf(owner, bytes32(0));
        bytes32 code = _dflt(s);
        // The third party's ID rolls the code owner's leg.
        _bumpIdsUntil(code, 0);
        uint32 tId = _giveWalletId(third);
        assertEq(_class(tId, code), 0, "fixture: owner leg");

        uint32 next = _nextId();
        uint256 stakeBefore = coinflip.coinflipAmountById(_fixtureId(s));
        vm.expectCall(address(game), abi.encodeWithSelector(game.registerWallet.selector), 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        _buy(third, code);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_nextId(), next, "an ID referral allocates no wallet");
        for (uint256 i; i < logs.length; ++i) {
            assertFalse(logs[i].emitter == address(game) && logs[i].topics.length > 0
                && logs[i].topics[0] == WALLET_REGISTERED, "no wallet registered");
        }
        assertEq(_refWord(third), (uint256(1) << 32) | sId, "the stored word names the smurf");
        assertEq(affiliate.getReferrerIdById(_fixtureId(third)), sId);
        assertEq(affiliate.getReferrerById(_fixtureId(third)), owner);
        assertGt(affiliate.affiliateScore(1, sId), 0, "the earnings book on the smurf's ID");
        (bool found,,, uint32 winner, uint256 credit) = _pairCall(acc);
        assertTrue(found, "the purchase credited Coinflip");
        assertEq(winner, sId, "the affiliate share credits the smurf's ID");
        assertGt(credit, 0);
        assertEq(coinflip.coinflipAmountById(_fixtureId(s)) - stakeBefore, credit, "the stake sits on the smurf's ID");

        // A coinflip claim for the smurf mints to the owner.
        uint24 d = _today();
        _warpToDay(d + 1);
        uint256 word = uint256(keccak256(abi.encodePacked("smurf_referral_flip", d + 1))) | 1;
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, d + 1);
        uint256 before = coin.balanceOf(owner);
        vm.prank(owner);
        uint256 got = coinflip.claimCoinflips(sId, type(uint256).max);
        assertGt(got, 0, "the smurf won its flip");
        assertEq(coin.balanceOf(owner) - before, got, "the claim minted to the owner");
    }

    function _buyWithCode(bytes32 code) private {
        address who = address(uint160(0xA11C5000 + _buyerNonce++));
        vm.deal(who, 5 ether);
        vm.prank(who);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), code, MintPaymentKind.DirectEth, false);
    }

    /// @dev Drive the real game to level 1 and read the transition's top-affiliate award.
    function _driveToLevelOne() private returns (address top, uint256 paid) {
        vm.deal(driveBuyer, 50_000 ether);
        vm.deal(address(game), 100_000 ether);
        vm.recordLogs();
        uint256 simTime = block.timestamp;
        for (uint256 d; d < 500 && game.level() < 1; ++d) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            uint256 packed = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT)));
            if ((packed & POOL_HALF_MASK) < 500 ether) {
                vm.store(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT), bytes32((packed & ~POOL_HALF_MASK) | 500 ether));
            }
            (,,, bool locked, uint256 priceWei) = game.purchaseInfo();
            if (!locked && !game.gameOver()) {
                vm.prank(driveBuyer);
                try game.purchase{value: priceWei * 10}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
            }
            for (uint256 j; j < 80 && game.level() < 1; ++j) {
                uint256 reqId = mockVRF.lastRequestId();
                if (reqId != 0) {
                    (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                    if (!fulfilled) {
                        try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp, reqId)))) {} catch {}
                    }
                }
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (!ok) break;
            }
        }
        assertEq(game.level(), 1, "reached level 1");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 3) continue;
            if (logs[i].topics[0] == TOP_REWARD_SIG && uint256(logs[i].topics[2]) == 1) {
                top = address(uint160(uint256(logs[i].topics[1])));
                paid = abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function test_aSmurfTopsALevelAndTheOwnerTakesTheSdgnrs() public {
        _giveWalletId(owner);
        (uint32 sId, uint32 s,) = _createSmurf(owner, bytes32(0));
        for (uint256 i; i < 3; ++i) _buyWithCode(_dflt(s));
        (uint32 topId,) = affiliate.affiliateTop(1);
        assertEq(topId, sId, "fixture: the smurf leads level 1");

        uint256 ownerBefore = sdgnrs.balanceOf(owner);
        (address top, uint256 paid) = _driveToLevelOne();
        assertEq(top, owner, "the leader award names the smurf's owner");
        assertGt(paid, 0);
        assertGe(sdgnrs.balanceOf(owner) - ownerBefore, paid, "the owner holds the award");

        // The per-affiliate claim is permissionless and also pays the owner.
        uint256 mid = sdgnrs.balanceOf(owner);
        vm.prank(stranger);
        game.claimAffiliateDgnrs(sId);
        assertGt(sdgnrs.balanceOf(owner), mid, "the claim paid the owner");
        assertEq(sdgnrs.balanceOf(stranger), 0);
    }

    // ── 15. Mutual-referral cycle (accepted, notes §2.7) ─────────────────────

    /// @dev ACCEPTED BEHAVIOUR (F-craps-aff notes §2.7, orchestrator ruling): an owner O referred
    ///      by R, where R is referred by O, is the upline1 of its own smurfs, so the 20% upline leg
    ///      of a smurf's purchase can pay O. On O's own purchases that leg is never paid (the
    ///      winner equals the buyer).
    function test_mutualReferralCycleLetsTheOwnerWinItsSmurfsUplineLeg() public {
        uint32 oId = _giveWalletId(owner);
        // A referrer whose default code rolls upline1 for the owner's own ID today.
        address r;
        for (uint256 i; ; ++i) {
            r = address(uint160(uint256(keccak256(abi.encode("smurf-ref-cycle", i)))));
            _giveWalletId(r);
            if (_class(oId, _dflt(r)) == 1) break;
        }
        _buy(r, _dflt(owner));
        uint32 rId = game.walletIdOf(r);
        assertEq(affiliate.getReferrerIdById(_fixtureId(r)), oId, "fixture: R is referred by O");

        bytes32 codeR = _dflt(r);
        _bumpIdsUntil(codeR, 1);
        (uint32 sId, uint32 s,) = _createSmurf(owner, codeR);
        assertEq(_class(sId, codeR), 1, "fixture: the smurf rolls upline1");
        assertEq(affiliate.getReferrerIdById(_fixtureId(owner)), rId, "O is referred by R");
        (uint32 a, uint32 u1,) = affiliate.referrerIdsById(_fixtureId(s));
        assertEq(a, rId, "the smurf's direct affiliate is R");
        assertEq(u1, oId, "the smurf's upline1 is its owner");

        uint256 rScore = affiliate.affiliateScore(1, rId);
        uint256 p = _price();
        vm.deal(owner, owner.balance + 2 * p);
        vm.startStateDiffRecording();
        vm.prank(owner);
        game.purchase{value: p}(sId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (bool found, uint32 buyerId,, uint32 winner, uint256 credit) = _pairCall(acc);
        assertTrue(found);
        assertEq(buyerId, sId);
        assertEq(winner, oId, "accepted: the owner wins the upline leg of its smurf's purchase");
        assertGt(credit, 0);
        assertGt(affiliate.affiliateScore(1, rId), rScore, "R books the score");

        // The owner's own purchase on the same roll class pays the leg to nobody.
        vm.startStateDiffRecording();
        vm.prank(owner);
        game.purchase{value: p}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        acc = vm.stopAndReturnStateDiff();
        uint256 ownerCredit;
        (found,,, winner, credit) = _pairCall(acc);
        if (found && winner == oId) ownerCredit = credit;
        assertEq(ownerCredit, 0, "the upline leg of the owner's own purchase is not paid");
        assertTrue(s != 0);
    }
}
