// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @dev Constructs an Affiliate from code that holds no nonce of the test contract, so the
///      bootstrap instance can be built before the Game exists without shifting any address.
contract BootstrapAffiliateFactory {
    function deploy(
        address[] memory owners,
        bytes32[] memory codes,
        uint8[] memory kickbacks,
        address[] memory players,
        bytes32[] memory referralCodes
    ) external returns (address) {
        return address(new DegenerusAffiliate(owners, codes, kickbacks, players, referralCodes));
    }
}

/// @notice Shared fixture: the protocol with an Affiliate that carries deploy-time bootstrap codes
///         and referrals. The bootstrap instance is constructed while the Game address holds no
///         code (any constructor-time Game call would revert), then its constructor-written slots
///         are copied onto the Affiliate at its pinned address. The two instances run identical
///         runtime code (no immutables), so the copy is the bootstrap deployment.
abstract contract AffiliateIdFixture is DeployProtocol {
    // DegenerusAffiliate roots (scripts/layout/golden/DegenerusAffiliate.json).
    uint256 internal constant CODE_ROOT = 0;
    uint256 internal constant EARNED_ROOT = 1;
    uint256 internal constant REFERRAL_ROOT = 2;
    uint256 internal constant LEVEL_SCORE_ROOT = 3;
    uint256 internal constant BOOT_OWNER_ROOT = 4;
    /// @dev `Sub.affiliateBase` (uint32) starts at byte 19 of the `_subOf[id]` word.
    uint256 internal constant SUB_AFF_BASE_SHIFT = 19 * 8;

    address internal constant FACTORY = address(0xB0075EED);
    bytes32 internal constant ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    bytes32 internal constant LOCKED = bytes32(uint256(1));
    bytes32 internal constant VAULT_CODE = bytes32("VAULT");
    bytes32 internal constant DGNRS_CODE = bytes32("DGNRS");

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant REFERRAL_UPDATED = keccak256("ReferralUpdated(address,bytes32,uint32,bool)");
    bytes32 internal constant EARNINGS_RECORDED = keccak256("AffiliateEarningsRecorded(uint32,uint256)");
    bytes32 internal constant TOP_UPDATED = keccak256("AffiliateTopUpdated(uint24,uint32,uint96)");
    bytes32 internal constant AFFILIATE_EVENT = keccak256("Affiliate(uint256,bytes32,address)");
    bytes32 internal constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant QUEST_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 internal constant OLD_OWNER_REGISTERED = keccak256("AffiliateOwnerRegistered(bytes32,address)");
    bytes32 internal constant OLD_REFERRAL_UPDATED = keccak256("ReferralUpdated(address,bytes32,address,bool)");
    bytes32 internal constant OLD_EARNINGS_RECORDED = keccak256("AffiliateEarningsRecorded(address,uint256)");
    bytes32 internal constant OLD_TOP_UPDATED = keccak256("AffiliateTopUpdated(uint24,address,uint96)");

    // Bootstrap codes: one per registration door, a self-referral owner and a protocol owner.
    address internal constant OWN_A = address(0xB00A);
    address internal constant OWN_B = address(0xB00B);
    address internal constant OWN_C = address(0xB00C);
    address internal constant OWN_D = address(0xB00D);
    address internal constant OWN_S = address(0xB005);
    address internal constant OWN_G = ContractAddresses.GNRUS;
    bytes32 internal constant CODE_A = bytes32("BOOT_A");
    bytes32 internal constant CODE_B = bytes32("BOOT_B");
    bytes32 internal constant CODE_C = bytes32("BOOT_C");
    bytes32 internal constant CODE_D = bytes32("BOOT_D");
    bytes32 internal constant CODE_S = bytes32("BOOT_S");
    bytes32 internal constant CODE_G = bytes32("BOOT_G");
    uint8 internal constant KICK_A = 10;
    uint8 internal constant KICK_B = 0;
    uint8 internal constant KICK_C = 25;
    uint8 internal constant KICK_D = 5;
    uint8 internal constant KICK_S = 15;
    uint8 internal constant KICK_G = 0;

    // Bootstrap referrals.
    address internal constant P_A = address(0xBA0A);
    address internal constant P_B = address(0xBA0B);
    address internal constant P_C = address(0xBA0C);
    address internal constant P_D = address(0xBA0D);
    address internal constant P_G = address(0xBA06);
    address internal constant P_V = address(0xBA01);
    address internal constant P_DG = address(0xBA02);

    address internal bootAffiliate;
    uint256 private _dummies;

    struct CodeInfo {
        uint32 ownerId;
        uint8 kickback;
        uint32 upline1;
        uint32 upline2;
        uint8 flags;
    }

    function setUp() public virtual {
        require(ContractAddresses.GAME.code.length == 0, "fixture expects no Game yet");
        vm.etch(FACTORY, type(BootstrapAffiliateFactory).runtimeCode);
        (
            address[] memory owners,
            bytes32[] memory codes,
            uint8[] memory kicks,
            address[] memory players,
            bytes32[] memory refs
        ) = _bootArrays();
        bootAffiliate = BootstrapAffiliateFactory(FACTORY).deploy(owners, codes, kicks, players, refs);
        _deployProtocol();
        bytes32[] memory slots = _bootSlots();
        for (uint256 i; i < slots.length; ++i) {
            vm.store(address(affiliate), slots[i], vm.load(bootAffiliate, slots[i]));
        }
    }

    // ---------------------------------------------------------------------
    // Bootstrap configuration
    // ---------------------------------------------------------------------

    function _bootCodes() internal pure returns (bytes32[6] memory c, address[6] memory o, uint8[6] memory k) {
        c = [CODE_A, CODE_B, CODE_C, CODE_D, CODE_S, CODE_G];
        o = [OWN_A, OWN_B, OWN_C, OWN_D, OWN_S, OWN_G];
        k = [KICK_A, KICK_B, KICK_C, KICK_D, KICK_S, KICK_G];
    }

    function _bootPlayers() internal pure returns (address[7] memory p, bytes32[7] memory c) {
        p = [P_A, P_B, P_C, P_D, P_G, P_V, P_DG];
        c = [CODE_A, CODE_B, CODE_C, CODE_D, CODE_G, VAULT_CODE, DGNRS_CODE];
    }

    function _bootArrays()
        internal
        pure
        returns (
            address[] memory owners,
            bytes32[] memory codes,
            uint8[] memory kicks,
            address[] memory players,
            bytes32[] memory refs
        )
    {
        (bytes32[6] memory c, address[6] memory o, uint8[6] memory k) = _bootCodes();
        owners = new address[](6);
        codes = new bytes32[](6);
        kicks = new uint8[](6);
        for (uint256 i; i < 6; ++i) {
            owners[i] = o[i];
            codes[i] = c[i];
            kicks[i] = k[i];
        }
        (address[7] memory p, bytes32[7] memory r) = _bootPlayers();
        players = new address[](7);
        refs = new bytes32[](7);
        for (uint256 i; i < 7; ++i) {
            players[i] = p[i];
            refs[i] = r[i];
        }
    }

    /// @dev Every slot the bootstrap constructor writes: the two protocol code infos and their
    ///      referral words, each bootstrap code's info and side-map owner, and each bootstrap
    ///      player's referral word.
    function _bootSlots() internal pure returns (bytes32[] memory s) {
        (bytes32[6] memory c,,) = _bootCodes();
        (address[7] memory p,) = _bootPlayers();
        s = new bytes32[](4 + 12 + 7);
        s[0] = _codeSlot(VAULT_CODE);
        s[1] = _codeSlot(DGNRS_CODE);
        s[2] = _refSlot(ContractAddresses.VAULT);
        s[3] = _refSlot(ContractAddresses.SDGNRS);
        for (uint256 i; i < 6; ++i) {
            s[4 + 2 * i] = _codeSlot(c[i]);
            s[5 + 2 * i] = _bootOwnerSlot(c[i]);
        }
        for (uint256 i; i < 7; ++i) s[16 + i] = _refSlot(p[i]);
    }

    // ---------------------------------------------------------------------
    // Storage readers
    // ---------------------------------------------------------------------

    function _codeSlot(bytes32 code) internal pure returns (bytes32) {
        return keccak256(abi.encode(code, CODE_ROOT));
    }

    function _bootOwnerSlot(bytes32 code) internal pure returns (bytes32) {
        return keccak256(abi.encode(code, BOOT_OWNER_ROOT));
    }

    function _refSlot(address player) internal pure returns (bytes32) {
        return keccak256(abi.encode(player, REFERRAL_ROOT));
    }

    function _earnSlot(uint24 lvl, uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(lvl), EARNED_ROOT))));
    }

    function _codeWord(bytes32 code) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), _codeSlot(code)));
    }

    function _info(bytes32 code) internal view returns (CodeInfo memory c) {
        uint256 w = _codeWord(code);
        c.ownerId = uint32(w);
        c.kickback = uint8(w >> 32);
        c.upline1 = uint32(w >> 40);
        c.upline2 = uint32(w >> 72);
        c.flags = uint8(w >> 104);
    }

    function _bootOwner(bytes32 code) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(affiliate), _bootOwnerSlot(code)))));
    }

    function _refWord(address player) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), _refSlot(player)));
    }

    function _earnWord(uint24 lvl, uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), _earnSlot(lvl, id)));
    }

    function _levelWord(uint24 lvl) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(uint256(lvl), LEVEL_SCORE_ROOT))));
    }

    function _id(address a) internal view returns (uint32) {
        return game.walletIdOf(a);
    }

    function _keyOf(uint32 id) internal view returns (address) {
        return address(uint160(uint256(game.extsload(GameSlotKeys.walletElement(id)))));
    }

    function _nextId() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
    }

    function _dflt(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    // ---------------------------------------------------------------------
    // Roll steering
    // ---------------------------------------------------------------------

    function _entropy(uint32 buyerId, bytes32 code) internal view returns (uint256) {
        // vm.getBlockTimestamp: via-IR may fold repeated block.timestamp reads within one call.
        uint24 day = GameTimeLib.currentDayIndexAt(vm.getBlockTimestamp());
        return uint256(keccak256(abi.encodePacked(ROLL_TAG, day, buyerId, code)));
    }

    /// @dev 0 = owner (roll < 15), 1 = upline1 (15..18), 2 = upline2 (19).
    function _class(uint32 buyerId, bytes32 code) internal view returns (uint8) {
        uint256 r = _entropy(buyerId, code) % 20;
        return r < 15 ? 0 : (r < 19 ? 1 : 2);
    }

    function _senderFor(bytes32 code, uint8 cls, uint32 from) internal view returns (uint32 id) {
        for (id = from; _class(id, code) != cls; ++id) {}
    }

    /// @dev Registers throwaway wallets until the next allocated ID rolls `cls` for `code`.
    function _bumpIdsUntil(bytes32 code, uint8 cls) internal returns (uint32 next) {
        next = _nextId();
        while (_class(next, code) != cls) {
            _giveWalletId(address(uint160(0xD0000000 + ++_dummies)));
            next = _nextId();
        }
    }

    // ---------------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------------

    function _price() internal view returns (uint256 p) {
        (,,,, p) = game.purchaseInfo();
    }

    /// @dev One whole ticket bought with fresh ETH through the Game.
    function _buy(address buyer, bytes32 code) internal returns (uint32 id) {
        uint256 p = _price();
        vm.deal(buyer, buyer.balance + p);
        vm.prank(buyer);
        game.purchase{value: p}(0, 400, 0, code, MintPaymentKind.DirectEth, false);
        id = _id(buyer);
    }

    function _payCombined(bytes32 code, address sender, uint32 senderId, uint24 lvl, uint256 freshFlip)
        internal
        returns (uint32 winnerId, uint256 credit, uint256 kickback)
    {
        vm.prank(address(game));
        (winnerId, credit, kickback) =
            affiliate.payAffiliateCombined(code, sender, senderId, lvl, freshFlip, 0, 0, 0, 0);
    }

    function _pay(uint256 amount, bytes32 code, address sender, uint32 senderId, uint24 lvl)
        internal
        returns (uint256 kickback)
    {
        vm.prank(address(game));
        kickback = affiliate.payAffiliate(amount, code, sender, senderId, lvl, true, 0);
    }

    function _refer(address player, bytes32 code) internal {
        vm.prank(player);
        affiliate.referPlayer(code);
    }

    function _create(address owner, bytes32 code, uint8 kickback) internal {
        vm.prank(owner);
        affiliate.createAffiliateCode(code, kickback);
    }

    /// @dev Writes a sub's accrued affiliate base, which `drainAffiliateBase` reads and zeroes.
    function _seedBase(uint32 id, uint32 base) internal {
        bytes32 slot = keccak256(abi.encode(uint256(id), GameSlots.SUB_OF));
        uint256 w = uint256(vm.load(address(game), slot));
        w = (w & ~(uint256(type(uint32).max) << SUB_AFF_BASE_SHIFT)) | (uint256(base) << SUB_AFF_BASE_SHIFT);
        vm.store(address(game), slot, bytes32(w));
    }

    function _claim(address sub) internal {
        address[] memory subs = new address[](1);
        subs[0] = sub;
        affiliate.claim(subs);
    }

    // ---------------------------------------------------------------------
    // Call and log inspection
    // ---------------------------------------------------------------------

    function _match(Vm.AccountAccess memory a, address from, address to, bytes4 sel) internal pure returns (bool) {
        if (a.reverted) return false;
        if (a.kind != VmSafe.AccountAccessKind.Call && a.kind != VmSafe.AccountAccessKind.StaticCall) return false;
        if (a.account != to) return false;
        if (from != address(0) && a.accessor != from) return false;
        return a.data.length >= 4 && bytes4(a.data) == sel;
    }

    function _args(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(data.length - 4);
        for (uint256 i; i < out.length; ++i) out[i] = data[i + 4];
    }

    /// @dev Argument bytes of every matching call, in execution order.
    function _calls(Vm.AccountAccess[] memory acc, address from, address to, bytes4 sel)
        internal
        pure
        returns (bytes[] memory found)
    {
        uint256 n;
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) ++n;
        found = new bytes[](n);
        n = 0;
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) found[n++] = _args(acc[i].data);
    }

    function _firstIndex(Vm.AccountAccess[] memory acc, address from, address to, bytes4 sel)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) return i;
        return type(uint256).max;
    }

    function _extsloads(Vm.AccountAccess[] memory acc) internal view returns (uint256) {
        return _calls(acc, address(affiliate), address(game), game.extsload.selector).length;
    }

    function _registrations(Vm.AccountAccess[] memory acc) internal view returns (uint256) {
        return _calls(acc, address(affiliate), address(game), game.registerWallet.selector).length;
    }

    /// @dev The Game's paired purchase credit: (buyer leg ID, buyer amount, winner ID, winner amount).
    function _pair(Vm.AccountAccess[] memory acc)
        internal
        view
        returns (uint32 id1, uint256 a1, uint32 id2, uint256 a2)
    {
        bytes[] memory p = _calls(acc, address(game), address(coinflip), coinflip.creditFlipPair.selector);
        assertEq(p.length, 1, "one paired credit");
        (id1, a1, id2, a2) = abi.decode(p[0], (uint32, uint256, uint32, uint256));
    }

    function _countLogs(Vm.Log[] memory logs, address emitter, bytes32 t0) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length != 0 && logs[i].topics[0] == t0) ++n;
        }
    }

    function _countRegistered(Vm.Log[] memory logs, address owner) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics.length != 3 || l.topics[0] != WALLET_REGISTERED) continue;
            if (l.topics[2] == bytes32(uint256(uint160(owner)))) ++n;
        }
    }

    /// @dev Sum of the stake actually accepted for wallet `id`.
    function _staked(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 sum) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(coinflip) || l.topics.length < 2 || l.topics[0] != STAKE_UPDATED) continue;
            if (l.topics[1] == bytes32(uint256(id))) {
                (uint256 amount,) = abi.decode(l.data, (uint256, uint256));
                sum += amount;
            }
        }
    }

    function _stakeEvents(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter == address(coinflip) && l.topics.length >= 2 && l.topics[0] == STAKE_UPDATED
                && l.topics[1] == bytes32(uint256(id))) ++n;
        }
    }

    /// @dev The owner's running level total from its last AffiliateEarningsRecorded.
    function _earnedTotal(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(affiliate) || l.topics.length != 2 || l.topics[0] != EARNINGS_RECORDED) continue;
            if (l.topics[1] == bytes32(uint256(id))) total = abi.decode(l.data, (uint256)) >> 24;
        }
    }

    function _questRewards(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 sum) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(quests) || l.topics.length != 4 || l.topics[0] != QUEST_COMPLETED) continue;
            if (l.topics[1] == bytes32(uint256(id))) {
                (,, uint256 reward) = abi.decode(l.data, (uint8, uint32, uint256));
                sum += reward;
            }
        }
    }

    function _assertReferralUpdated(
        Vm.Log[] memory logs,
        address emitter,
        address player,
        bytes32 code,
        uint32 referrerId,
        bool locked
    ) internal pure {
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != emitter || l.topics.length != 4 || l.topics[0] != REFERRAL_UPDATED) continue;
            if (l.topics[1] != bytes32(uint256(uint160(player)))) continue;
            ++found;
            assertEq(l.topics[2], code, "ReferralUpdated.code");
            assertEq(uint256(l.topics[3]), uint256(referrerId), "ReferralUpdated.referrerId");
            assertEq(abi.decode(l.data, (bool)), locked, "ReferralUpdated.locked");
        }
        assertEq(found, 1, "one ReferralUpdated for the player");
    }

    function _assertInfo(bytes32 code, uint32 ownerId, uint8 kickback, uint32 u1, uint32 u2, uint8 flags)
        internal
        view
    {
        CodeInfo memory c = _info(code);
        assertEq(c.ownerId, ownerId, "ownerId");
        assertEq(c.kickback, kickback, "kickback");
        assertEq(c.upline1, u1, "upline1");
        assertEq(c.upline2, u2, "upline2");
        assertEq(c.flags, flags, "flags");
    }

    /// @dev A bootstrap code after its first runtime use: canonical owner ID, no flags, no side map.
    function _assertMaterialized(bytes32 code, address owner, uint8 kickback) internal view {
        uint32 id = _id(owner);
        assertGt(id, 0, "owner registered");
        _assertInfo(code, id, kickback, 0, 0, 0);
        assertEq(_bootOwner(code), address(0), "side map cleared");
        (address o, uint32 oid, uint8 k) = affiliate.affiliateCode(code);
        assertEq(o, owner);
        assertEq(oid, id);
        assertEq(k, kickback);
    }

    // ---------------------------------------------------------------------
    // ID truth (plan section 0): every nonzero ID Affiliate stores is the canonical ID of its key
    // ---------------------------------------------------------------------

    function _assertWordTruth(address p) internal view {
        uint256 w = _refWord(p);
        if (w < (uint256(1) << 160) || w >= (uint256(1) << 192)) return;
        uint32 id = uint32(w >> 160);
        assertGt(id, 0, "default word carries an ID");
        assertEq(_id(address(uint160(w))), id, "default word ID is the owner's canonical ID");
    }

    function _assertCodeTruth(bytes32 code, address bootOwner) internal view {
        CodeInfo memory c = _info(code);
        if (c.ownerId != 0) {
            address key = _keyOf(c.ownerId);
            assertEq(_id(key), c.ownerId, "code ownerId is canonical");
            if (bootOwner != address(0)) assertEq(key, bootOwner, "bootstrap code owner");
            assertEq(c.flags & 1, 0, "registered code is not pending");
        }
        if (c.flags & 2 != 0) {
            assertEq(c.upline1, affiliate.getReferrerId(_keyOf(c.ownerId)), "code upline1 cache");
        }
        if (c.flags & 4 != 0) {
            assertEq(c.upline2, affiliate.getReferrerId(_keyOf(c.upline1)), "code upline2 cache");
        }
    }

    function _assertCacheTruth(uint24 lvl, uint32 id) internal view {
        uint256 w = _earnWord(lvl, id);
        if ((w >> 192) & 1 != 0) {
            assertEq(uint32(w >> 128), affiliate.getReferrerId(_keyOf(id)), "earnings upline1 cache");
        }
        if ((w >> 193) & 1 != 0) {
            assertTrue((w >> 192) & 1 != 0, "upline2 cached only behind upline1");
            assertEq(uint32(w >> 160), affiliate.getReferrerId(_keyOf(uint32(w >> 128))), "earnings upline2 cache");
        }
    }

    function _assertLeaderTruth(uint24 lvl) internal view {
        uint32 lid = uint32(_levelWord(lvl) >> 224);
        if (lid == 0) return;
        assertLt(lid, _nextId(), "leader is allocated");
        assertEq(_id(_keyOf(lid)), lid, "leader ID is canonical");
    }

    function _assertIdTruth(address[] memory players, bytes32[] memory codes, uint24 maxLevel) internal view {
        for (uint256 i; i < players.length; ++i) _assertWordTruth(players[i]);
        _assertWordTruth(ContractAddresses.VAULT);
        _assertWordTruth(ContractAddresses.SDGNRS);
        (address[7] memory bp,) = _bootPlayers();
        for (uint256 i; i < 7; ++i) _assertWordTruth(bp[i]);
        (bytes32[6] memory bc, address[6] memory bo,) = _bootCodes();
        for (uint256 i; i < 6; ++i) _assertCodeTruth(bc[i], bo[i]);
        _assertCodeTruth(VAULT_CODE, address(0));
        _assertCodeTruth(DGNRS_CODE, address(0));
        for (uint256 i; i < codes.length; ++i) {
            if (uint256(codes[i]) >= (uint256(1) << 192)) _assertCodeTruth(codes[i], address(0));
        }
        uint32 n = _nextId();
        for (uint24 lvl = 1; lvl <= maxLevel; ++lvl) {
            _assertLeaderTruth(lvl);
            for (uint32 id = 1; id < n; ++id) _assertCacheTruth(lvl, id);
        }
    }
}

/// @notice Affiliate state, routing, credits, views and events keyed by wallet ID, and the Game's
///         caller side (Mint pair credit, Whale deity chain).
contract AffiliateWalletIdsTest is AffiliateIdFixture {
    // =====================================================================
    // 1. Code info is one slot
    // =====================================================================

    function test_CodeInfoIsOneSlotWithFieldOffsets() public {
        address up = makeAddr("infoUpline");
        address owner = makeAddr("infoOwner");
        bytes32 code = bytes32("INFO_CODE");
        _buy(up, bytes32(0));
        assertEq(_refWord(up), 1, "upline locked to VAULT");
        _refer(owner, _dflt(up));
        _create(owner, code, 7);
        uint256 w = _codeWord(code);
        assertEq(uint32(w), _id(owner), "ownerId [0:32)");
        assertEq(uint8(w >> 32), 7, "kickback [32:40)");
        assertEq(uint32(w >> 40), _id(up), "upline1 [40:72)");
        assertEq(uint32(w >> 72), 1, "upline2 [72:104)");
        assertEq(uint8(w >> 104), 6, "flags [104:112)");
        assertEq(w >> 112, 0, "nothing above bit 112");
        assertEq(
            uint256(vm.load(address(affiliate), bytes32(uint256(_codeSlot(code)) + 1))), 0, "the struct spans one slot"
        );
    }

    /// @dev Roots 0-4 as the golden layout lists them, each read raw and checked against its view.
    function test_StorageRootsMatchTheViews() public {
        address o = makeAddr("rootOwner");
        address b = makeAddr("rootBuyer");
        bytes32 code = bytes32("ROOT_CODE");
        _create(o, code, 0);
        _refer(b, code);
        uint32 oid = _id(o);
        _payCombined(bytes32(0), b, _senderFor(code, 0, 60_000_000), 4, 4000);
        assertEq(uint32(_codeWord(code)), oid, "root 0: _affiliateCode");
        assertEq(_earnWord(4, oid) & type(uint128).max, affiliate.affiliateScore(4, oid), "root 1: affiliateCoinEarned");
        assertEq(affiliate.affiliateScore(4, oid), 800);
        assertEq(_refWord(b), uint256(code), "root 2: playerReferralCode");
        uint256 lw = _levelWord(4);
        (uint32 lid, uint96 lscore) = affiliate.affiliateTop(4);
        assertEq(lw & type(uint128).max, affiliate.totalAffiliateScore(4), "root 3: total [0:128)");
        assertEq(uint96(lw >> 128), lscore, "root 3: leader score [128:224)");
        assertEq(uint32(lw >> 224), lid, "root 3: leader ID [224:256)");
        assertEq(lid, oid);
        (address pendingOwner,,) = affiliate.affiliateCode(CODE_A);
        assertEq(_bootOwner(CODE_A), pendingOwner, "root 4: _bootstrapOwner");
        (uint32 none, uint96 noScore) = affiliate.affiliateTop(5);
        assertEq(none, 0, "an empty level has no leader");
        assertEq(noScore, 0);
    }

    // =====================================================================
    // 3. Default-code referral word
    // =====================================================================

    function test_DefaultCodeWordCarriesOwnerIdViaReferPlayer() public {
        address owner = makeAddr("dfltOwner");
        address player = makeAddr("dfltPlayer");
        assertEq(_id(owner), 0);
        vm.recordLogs();
        _refer(player, _dflt(owner));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32 id = _id(owner);
        assertGt(id, 0, "owner registered");
        assertEq(_countRegistered(logs, owner), 1, "one WalletRegistered for the owner");
        assertEq(_countLogs(logs, address(game), WALLET_REGISTERED), 1, "nobody else registers");
        assertEq(_refWord(player), uint256(uint160(owner)) | (uint256(id) << 160), "word = owner | id << 160");
        assertEq(affiliate.getReferrerId(player), id);
        assertEq(affiliate.getReferrer(player), owner);
        _assertReferralUpdated(logs, address(affiliate), player, _dflt(owner), id, false);
    }

    function test_DefaultCodeWordCarriesOwnerIdOnPurchase() public {
        address owner = makeAddr("dfltOwner2");
        address buyer = makeAddr("dfltBuyer2");
        vm.recordLogs();
        _buy(buyer, _dflt(owner));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32 id = _id(owner);
        assertGt(id, 0);
        assertEq(_countRegistered(logs, owner), 1, "one WalletRegistered for the owner");
        assertEq(_refWord(buyer), uint256(uint160(owner)) | (uint256(id) << 160));
        assertEq(affiliate.getReferrerId(buyer), id);
        assertEq(affiliate.getReferrer(buyer), owner);
        _assertReferralUpdated(logs, address(affiliate), buyer, _dflt(owner), id, false);
    }

    // =====================================================================
    // 4. Custom-code range
    // =====================================================================

    function test_CustomCodeRangeStartsAtTwoPow192() public {
        address who = makeAddr("rangeOwner");
        bytes32[4] memory bad =
            [bytes32(uint256(1) << 160), bytes32((uint256(1) << 192) - 1), bytes32(0), bytes32(uint256(1))];
        for (uint256 i; i < 4; ++i) {
            vm.expectRevert(DegenerusAffiliate.Zero.selector);
            vm.prank(who);
            affiliate.createAffiliateCode(bad[i], 0);
        }
        assertEq(_id(who), 0, "a refused creation registers nobody");
        _create(who, bytes32(uint256(1) << 192), 3);
        _create(who, bytes32("ALICE"), 4);
        uint32 id = _id(who);
        assertGt(id, 0);
        // An unreferred owner's first hop is not yet permanent, so nothing is cached.
        _assertInfo(bytes32(uint256(1) << 192), id, 3, 0, 0, 0);
        assertEq(_info(bytes32("ALICE")).ownerId, id);
    }

    function testFuzz_CodesBelowCustomRangeRevert(uint256 raw) public {
        bytes32 code = bytes32(bound(raw, 0, (uint256(1) << 192) - 1));
        vm.expectRevert(DegenerusAffiliate.Zero.selector);
        vm.prank(makeAddr("rangeFuzz"));
        affiliate.createAffiliateCode(code, 0);
    }

    // =====================================================================
    // 5. Forged default words and the sentinel code
    // =====================================================================

    function test_ForgedDefaultWordLocksBuyerToVault() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");
        _giveWalletId(victim);
        uint32 aid = _giveWalletId(attacker);
        bytes32 forged = bytes32(uint256(uint160(victim)) | (uint256(aid) << 160));
        address buyer = makeAddr("forgedBuyer");
        vm.recordLogs();
        vm.startStateDiffRecording();
        _buy(buyer, forged);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_refWord(buyer), 1, "buyer locked");
        assertEq(affiliate.getReferrerId(buyer), 1);
        _assertReferralUpdated(logs, address(affiliate), buyer, LOCKED, 1, true);
        assertEq(_stakeEvents(logs, aid), 0, "nothing credited to the forged ID");
        assertEq(_registrations(acc), 0, "no registration");
        (,, uint32 w,) = _pair(acc);
        assertTrue(w == 1 || w == 2, "the share goes to VAULT or SDGNRS");

        address other = makeAddr("forgedRefer");
        vm.expectRevert(DegenerusAffiliate.Insufficient.selector);
        _refer(other, forged);
        assertEq(_refWord(other), 0);
    }

    function test_SentinelCodeOneIsInvalidAndRegistersNobody() public {
        address buyer = makeAddr("sentinelBuyer");
        vm.startStateDiffRecording();
        _buy(buyer, LOCKED);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_refWord(buyer), 1, "locked");
        assertEq(_id(address(1)), 0, "address(1) is not registered");
        assertEq(_registrations(acc), 0);
        address other = makeAddr("sentinelRefer");
        vm.expectRevert(DegenerusAffiliate.Insufficient.selector);
        _refer(other, LOCKED);
        assertEq(_id(address(1)), 0);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_ForgedDefaultWordNeverRoutesToItsId(uint160 low, uint32 hi, uint32 senderId) public {
        vm.assume(hi != 0);
        bytes32 forged = bytes32(uint256(low) | (uint256(hi) << 160));
        address buyer = makeAddr("forgedFuzz");
        uint32 before = _id(address(low));
        vm.startStateDiffRecording();
        (uint32 w,,) = _payCombined(forged, buyer, senderId, 1, 4000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_refWord(buyer), 1, "locked");
        assertTrue(w == 1 || w == 2, "protocol winner");
        assertEq(_id(address(low)), before, "no registration of the forged owner");
        assertEq(_registrations(acc), 0);
    }

    // =====================================================================
    // 6. Default codes never read code info
    // =====================================================================

    function test_DefaultCodeRoutesReadNoCodeInfo() public {
        address u1 = makeAddr("dU1");
        address owner = makeAddr("dOwner");
        address buyer = makeAddr("dBuyer");
        address fresh = makeAddr("dFresh");
        _buy(u1, bytes32(0));
        _refer(owner, _dflt(u1));
        _refer(buyer, _dflt(owner));
        bytes32 route = _dflt(owner);
        bytes32 stored = bytes32(_refWord(buyer));
        uint32[3] memory winners = [_id(owner), _id(u1), uint32(1)];
        vm.record();
        vm.startStateDiffRecording();
        for (uint8 cls; cls < 3; ++cls) {
            uint32 sid = _senderFor(route, cls, 1_000_000);
            (uint32 w,,) = _payCombined(bytes32(0), buyer, sid, 2 + cls, 4000);
            assertEq(w, winners[cls], "winner by class");
        }
        _payCombined(route, fresh, 2_000_000, 1, 4000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (bytes32[] memory reads,) = vm.accesses(address(affiliate));
        bytes32[4] memory forbidden =
            [_codeSlot(route), _codeSlot(stored), _codeSlot(_dflt(u1)), _codeSlot(bytes32(_refWord(owner)))];
        for (uint256 i; i < reads.length; ++i) {
            for (uint256 j; j < 4; ++j) assertTrue(reads[i] != forbidden[j], "default code read code info");
        }
        assertEq(_extsloads(acc), 0, "default-code chain decodes nothing");
        assertEq(_refWord(fresh), uint256(route) | (uint256(_id(owner)) << 160));
    }

    // =====================================================================
    // 7. Self-referral
    // =====================================================================

    function test_SelfReferralOwnDefaultCodeLocks() public {
        address p = makeAddr("selfDefault");
        _buy(p, _dflt(p));
        assertEq(_refWord(p), 1, "own default code locks");
        address q = makeAddr("selfDefaultRefer");
        vm.expectRevert(DegenerusAffiliate.Insufficient.selector);
        _refer(q, _dflt(q));
        assertEq(_id(q), 0, "a refused referral registers nobody");
    }

    function test_SelfReferralOwnCustomCodeOnPurchaseLocks() public {
        address o = makeAddr("selfCustom");
        bytes32 code = bytes32("SELF_CUSTOM");
        _create(o, code, 20);
        uint32 oid = _id(o);
        vm.recordLogs();
        _buy(o, code);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_refWord(o), 1, "own custom code with senderId locks");
        _assertReferralUpdated(logs, address(affiliate), o, LOCKED, 1, true);
        assertEq(affiliate.affiliateScore(1, oid), 0, "no earnings to the self code");
    }

    function test_SelfReferralOwnCustomCodeWithoutSenderIdLocks() public {
        address o = makeAddr("selfLink");
        bytes32 code = bytes32("SELF_LINK");
        _create(o, code, 5);
        // Whale's link-only touch passes senderId 0; the self check decodes the owner's address.
        _pay(0, code, o, 0, 1);
        assertEq(_refWord(o), 1, "locked");
        assertEq(affiliate.getReferrerId(o), 1);
    }

    function test_SelfReferralReferPlayerOwnCustomCodeReverts() public {
        address o = makeAddr("selfRefer");
        bytes32 code = bytes32("SELF_REFER");
        _create(o, code, 5);
        vm.expectRevert(DegenerusAffiliate.Insufficient.selector);
        _refer(o, code);
        assertEq(_refWord(o), 0);
    }

    function test_SelfReferralThroughDeityLinkTouchLocks() public {
        address o = makeAddr("selfDeity");
        bytes32 code = bytes32("SELF_DEITY");
        _create(o, code, 0);
        vm.deal(o, 200 ether);
        vm.prank(o);
        game.purchaseDeityPass{value: 100 ether}(0, 1, code);
        assertEq(_refWord(o), 1, "locked");
        (uint32 a, uint32 u1, uint32 u2) = affiliate.referrerIds(o);
        assertEq(a, 1);
        assertEq(u1, 2);
        assertEq(u2, 1);
    }

    function test_BootstrapOwnerOwnPendingCodeLocksWithoutRegistering() public {
        vm.startStateDiffRecording();
        _pay(4000, CODE_S, OWN_S, 0, 1);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_refWord(OWN_S), 1, "locked");
        assertEq(_id(OWN_S), 0, "not registered by the refused attempt");
        assertEq(_registrations(acc), 0);
        _assertInfo(CODE_S, 0, KICK_S, 0, 0, 1);
        assertEq(_bootOwner(CODE_S), OWN_S, "still pending");
    }

    function test_BootstrapOwnerOwnPendingCodeOnPurchaseLocks() public {
        vm.startStateDiffRecording();
        _buy(OWN_S, CODE_S);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_refWord(OWN_S), 1, "locked");
        assertEq(_registrations(acc), 0, "the Affiliate registers nobody");
        _assertInfo(CODE_S, 0, KICK_S, 0, 0, 1);
        assertEq(_bootOwner(CODE_S), OWN_S, "still pending");
    }

    // =====================================================================
    // 8. Bootstrap
    // =====================================================================

    function test_BootstrapConstructorStateAndViews() public view {
        _assertInfo(VAULT_CODE, 1, 0, 2, 1, 6);
        _assertInfo(DGNRS_CODE, 2, 0, 1, 2, 6);
        (bytes32[6] memory c, address[6] memory o, uint8[6] memory k) = _bootCodes();
        for (uint256 i; i < 6; ++i) {
            _assertInfo(c[i], 0, k[i], 0, 0, 1);
            assertEq(_bootOwner(c[i]), o[i], "side-map owner");
            (address owner, uint32 oid, uint8 kick) = affiliate.affiliateCode(c[i]);
            assertEq(owner, o[i]);
            assertEq(oid, 0);
            assertEq(kick, k[i]);
        }
        address[5] memory pending = [P_A, P_B, P_C, P_D, P_G];
        address[5] memory owners = [OWN_A, OWN_B, OWN_C, OWN_D, OWN_G];
        bytes32[5] memory codes = [CODE_A, CODE_B, CODE_C, CODE_D, CODE_G];
        for (uint256 i; i < 5; ++i) {
            assertEq(affiliate.getReferrerId(pending[i]), 0, "pending referrer reads 0");
            assertEq(affiliate.getReferrer(pending[i]), owners[i], "address view reads the side map");
            (uint32 a, uint32 u1, uint32 u2) = affiliate.referrerIds(pending[i]);
            assertEq(a, 0);
            assertEq(u1, 0);
            assertEq(u2, 0);
            assertEq(_refWord(pending[i]), uint256(codes[i]));
            assertEq(_id(pending[i]), 0);
        }
        for (uint256 i; i < 5; ++i) if (o[i] != OWN_G) assertEq(_id(o[i]), 0, "no bootstrap owner registered");
        assertEq(affiliate.getReferrerId(P_V), 1);
        (uint32 va, uint32 v1, uint32 v2) = affiliate.referrerIds(P_V);
        assertEq(va, 1);
        assertEq(v1, 2);
        assertEq(v2, 1);
        (uint32 da, uint32 d1, uint32 d2) = affiliate.referrerIds(P_DG);
        assertEq(da, 2);
        assertEq(d1, 1);
        assertEq(d2, 2);
    }

    function test_BootstrapConstructionTouchesNoProtocolContract() public {
        (
            address[] memory owners,
            bytes32[] memory codes,
            uint8[] memory kicks,
            address[] memory players,
            bytes32[] memory refs
        ) = _bootArrays();
        vm.recordLogs();
        vm.startStateDiffRecording();
        DegenerusAffiliate fresh = new DegenerusAffiliate(owners, codes, kicks, players, refs);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertConstructorWrites(acc, address(fresh));
        _assertReferralUpdated(logs, address(fresh), P_A, CODE_A, 0, false);
        _assertReferralUpdated(logs, address(fresh), P_C, CODE_C, 0, false);
        _assertReferralUpdated(logs, address(fresh), P_G, CODE_G, 0, false);
        _assertReferralUpdated(logs, address(fresh), P_V, VAULT_CODE, 1, false);
        _assertReferralUpdated(logs, address(fresh), P_DG, DGNRS_CODE, 2, false);
        _assertReferralUpdated(logs, address(fresh), ContractAddresses.VAULT, DGNRS_CODE, 2, false);
        _assertReferralUpdated(logs, address(fresh), ContractAddresses.SDGNRS, VAULT_CODE, 1, false);
        assertEq(_countLogs(logs, address(fresh), OLD_OWNER_REGISTERED), 0, "AffiliateOwnerRegistered is gone");
        assertEq(_countLogs(logs, address(fresh), AFFILIATE_EVENT), 2 + 2 + 6 + 7, "creation and referral events");
    }

    /// @dev The constructor calls no protocol contract and writes exactly the bootstrap slots,
    ///      which the fixture copied onto the pinned Affiliate.
    function _assertConstructorWrites(Vm.AccountAccess[] memory acc, address fresh) internal view {
        bytes32[] memory expected = _bootSlots();
        bool[] memory hit = new bool[](expected.length);
        for (uint256 i; i < acc.length; ++i) {
            address a = acc[i].account;
            assertTrue(
                a != address(game) && a != address(coinflip) && a != address(quests), "constructor called the protocol"
            );
            Vm.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                if (!sa[j].isWrite || sa[j].account != fresh) continue;
                bool known;
                for (uint256 e; e < expected.length; ++e) {
                    if (expected[e] == sa[j].slot) {
                        known = true;
                        hit[e] = true;
                    }
                }
                assertTrue(known, "constructor wrote an unexpected slot");
            }
        }
        for (uint256 e; e < expected.length; ++e) {
            assertTrue(hit[e], "expected bootstrap slot written");
            assertEq(vm.load(fresh, expected[e]), vm.load(address(affiliate), expected[e]), "fixture copy");
        }
    }

    function test_BootstrapDoorFirstPurchaseRegistersOwnerOnce() public {
        _bumpIdsUntil(CODE_A, 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 pid = _buy(P_A, bytes32(0));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countRegistered(logs, OWN_A), 1, "owner registered once");
        assertEq(_registrations(acc), 1);
        _assertMaterialized(CODE_A, OWN_A, KICK_A);
        uint32 oid = _id(OWN_A);
        assertEq(affiliate.getReferrerId(P_A), oid);
        (uint32 id1,, uint32 w, uint256 credit) = _pair(acc);
        assertEq(id1, pid);
        assertEq(w, oid, "the owner wins by ID");
        uint256 total = _earnedTotal(logs, oid);
        assertGt(total, 0);
        assertEq(credit, total - (total * KICK_A) / 100 + _questRewards(logs, oid), "share + quest reward");
        assertEq(_staked(logs, oid), credit, "lands on the owner's ID lane");

        vm.startStateDiffRecording();
        _buy(P_A, bytes32(0));
        acc = vm.stopAndReturnStateDiff();
        assertEq(_registrations(acc), 0, "a second touch registers nobody");
        (,, w,) = _pair(acc);
        assertEq(w, oid);
    }

    function test_BootstrapDoorReferPlayerRegistersOwnerOnce() public {
        address q = makeAddr("doorB");
        vm.recordLogs();
        _refer(q, CODE_B);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countRegistered(logs, OWN_B), 1);
        _assertMaterialized(CODE_B, OWN_B, KICK_B);
        uint32 oid = _id(OWN_B);
        _assertReferralUpdated(logs, address(affiliate), q, CODE_B, oid, false);
        assertEq(affiliate.getReferrerId(P_B), oid, "the bootstrap referral resolves too");

        _bumpIdsUntil(CODE_B, 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 qid = _buy(q, bytes32(0));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        logs = vm.getRecordedLogs();
        assertEq(_registrations(acc), 0, "a later touch registers nobody");
        (uint32 id1,, uint32 w, uint256 credit) = _pair(acc);
        assertEq(id1, qid);
        assertEq(w, oid);
        assertGt(credit, 0);
        assertEq(_staked(logs, oid), credit, "credited by ID");
    }

    function test_BootstrapDoorSuppliedCodeRegistersOwnerOnce() public {
        address q = makeAddr("doorB2");
        _bumpIdsUntil(CODE_B, 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 qid = _buy(q, CODE_B);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countRegistered(logs, OWN_B), 1);
        assertEq(_registrations(acc), 1);
        _assertMaterialized(CODE_B, OWN_B, KICK_B);
        uint32 oid = _id(OWN_B);
        (uint32 id1,, uint32 w, uint256 credit) = _pair(acc);
        assertEq(id1, qid);
        assertEq(w, oid);
        assertEq(_staked(logs, oid), credit);

        vm.startStateDiffRecording();
        _payCombined(bytes32(0), P_B, 3_000_000, 1, 4000);
        acc = vm.stopAndReturnStateDiff();
        assertEq(_registrations(acc), 0, "the bootstrap player's stored code registers nobody");
    }

    function test_BootstrapDoorUplineTraversalRegistersOwnerOnce() public {
        address x = makeAddr("doorC");
        bytes32 route = _dflt(P_C);
        _bumpIdsUntil(route, 1);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 xid = _buy(x, route);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32 pcid = _id(P_C);
        assertGt(pcid, 0, "default-code owner registered");
        assertEq(_countRegistered(logs, OWN_C), 1, "upline owner registered once");
        _assertMaterialized(CODE_C, OWN_C, KICK_C);
        uint32 cid = _id(OWN_C);
        (uint32 id1,, uint32 w, uint256 credit) = _pair(acc);
        assertEq(id1, xid);
        assertEq(w, cid, "the upline roll pays the materialized owner by ID");
        assertGt(credit, 0);
        assertEq(_staked(logs, cid), credit);
        uint256 ew = _earnWord(1, pcid);
        assertEq(uint32(ew >> 128), cid, "upline1 cached by ID");
        assertEq((ew >> 192) & 1, 1);

        vm.startStateDiffRecording();
        _buy(x, bytes32(0));
        acc = vm.stopAndReturnStateDiff();
        assertEq(_registrations(acc), 0, "a second touch registers nobody");
        assertEq(_extsloads(acc), 0, "cache hit");
        (,, w,) = _pair(acc);
        assertEq(w, cid);
    }

    function test_BootstrapDoorClaimRegistersOwnerOnce() public {
        uint32 sid = _giveWalletId(P_D);
        _seedBase(sid, 1000);
        vm.recordLogs();
        vm.startStateDiffRecording();
        _claim(P_D);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countRegistered(logs, OWN_D), 1);
        _assertMaterialized(CODE_D, OWN_D, KICK_D);
        uint32 did = _id(OWN_D);
        bytes[] memory credits = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(credits.length, 3);
        _assertCredit(credits[0], did, 750);
        _assertCredit(credits[1], 1, 200);
        _assertCredit(credits[2], 2, 50);
        assertEq(_staked(logs, did), 750, "owner credited by ID");

        _seedBase(sid, 1000);
        vm.startStateDiffRecording();
        _claim(P_D);
        acc = vm.stopAndReturnStateDiff();
        assertEq(_registrations(acc), 0, "a second touch registers nobody");
    }

    function test_BootstrapProtocolOwnerMaterializesToItsReservedId() public {
        address q = makeAddr("doorG");
        vm.recordLogs();
        _refer(q, CODE_G);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, address(game), WALLET_REGISTERED), 0, "GNRUS keeps its reserved ID");
        _assertInfo(CODE_G, 3, KICK_G, 0, 0, 0);
        assertEq(_bootOwner(CODE_G), address(0));
        assertEq(affiliate.getReferrerId(P_G), 3);
        assertEq(affiliate.getReferrerId(q), 3);
    }

    function _assertCredit(bytes memory args, uint32 id, uint256 amount) internal pure {
        (uint32 cid, uint256 amt) = abi.decode(args, (uint32, uint256));
        assertEq(cid, id, "credit ID");
        assertEq(amt, amount, "credit amount");
    }

    // =====================================================================
    // 9. Protocol code caches equal dynamic resolution
    // =====================================================================

    function test_ProtocolCodeCachesEqualDynamicResolution() public {
        address bv = makeAddr("protoV");
        address bd = makeAddr("protoD");
        _refer(bv, VAULT_CODE);
        _refer(bd, DGNRS_CODE);
        address[6] memory buyers = [bv, bd, P_V, P_DG, ContractAddresses.SDGNRS, ContractAddresses.VAULT];
        bytes32[6] memory routes = [VAULT_CODE, DGNRS_CODE, VAULT_CODE, DGNRS_CODE, VAULT_CODE, DGNRS_CODE];
        uint32[3][6] memory expected;
        for (uint256 i; i < 6; ++i) {
            // Address resolution (the pre-ID semantics), mapped to IDs.
            address owner = affiliate.getReferrer(buyers[i]);
            address up1 = affiliate.getReferrer(owner);
            expected[i] = [_id(owner), _id(up1), _id(affiliate.getReferrer(up1))];
            bool isVault = routes[i] == VAULT_CODE;
            assertEq(expected[i][0], isVault ? 1 : 2);
            assertEq(expected[i][1], isVault ? 2 : 1);
            assertEq(expected[i][2], isVault ? 1 : 2);
        }
        vm.startStateDiffRecording();
        for (uint256 i; i < 6; ++i) {
            for (uint8 cls; cls < 3; ++cls) {
                uint32 sid = _senderFor(routes[i], cls, uint32(5_000_000 + i * 1000));
                (uint32 w,,) = _payCombined(bytes32(0), buyers[i], sid, 1, 4000);
                assertEq(w, expected[i][cls], "winner equals the address resolution");
            }
        }
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_extsloads(acc), 0, "protocol caches decode nothing");
        assertEq(_registrations(acc), 0, "protocol caches register nothing");
    }

    function test_SdgnrsWhalePassAffiliateIsTraversalFree() public {
        bool[3] memory seen;
        vm.expectCall(address(game), abi.encodeWithSelector(game.extsload.selector), 0);
        vm.expectCall(address(game), abi.encodeWithSelector(game.registerWallet.selector), 0);
        vm.startStateDiffRecording();
        for (uint256 d; d < 400 && !(seen[0] && seen[1] && seen[2]); ++d) {
            seen[_class(2, VAULT_CODE)] = true;
            vm.prank(address(game));
            affiliate.payAffiliate(8000, bytes32(0), ContractAddresses.SDGNRS, 2, 1, true, 0);
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertTrue(seen[0] && seen[1] && seen[2], "every roll class exercised");
        assertEq(_extsloads(acc), 0, "no extsload");
        assertEq(_registrations(acc), 0, "no registerWallet");
        bytes[] memory credits = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertGt(credits.length, 0);
        for (uint256 i; i < credits.length; ++i) {
            (uint32 id,) = abi.decode(credits[i], (uint32, uint256));
            assertEq(id, 1, "owner and upline2 are VAULT; upline1 is the sender and is skipped");
        }
    }

    // =====================================================================
    // 10. Upline caches by ID
    // =====================================================================

    /// @dev buyer -> C_OWNER (owner, no code cache) -> C_U1 (u1) -> C_U2 (u2, locked).
    function _customChain() internal returns (address owner, address u1, address u2, address buyer) {
        u2 = makeAddr("cU2");
        u1 = makeAddr("cU1");
        owner = makeAddr("cOwner");
        buyer = makeAddr("cBuyer");
        _buy(u2, bytes32(0));
        _create(u2, bytes32("C_U2"), 0);
        _refer(u1, bytes32("C_U2"));
        _create(u1, bytes32("C_U1"), 0);
        _create(owner, bytes32("C_OWNER"), 0);
        _refer(owner, bytes32("C_U1"));
        _refer(buyer, bytes32("C_OWNER"));
        assertEq(_info(bytes32("C_OWNER")).flags, 0, "owner code carries no cache");
    }

    function test_UplineCacheFillsOnFirstWinThenSkipsExtsload() public {
        (address owner, address u1, address u2, address buyer) = _customChain();
        bytes32 code = bytes32("C_OWNER");
        uint32 oid = _id(owner);
        uint24 lvl = 3;

        uint32 s1 = _senderFor(code, 1, 7_000_000);
        vm.startStateDiffRecording();
        (uint32 w,,) = _payCombined(bytes32(0), buyer, s1, lvl, 4000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(w, _id(u1));
        assertEq(_extsloads(acc), 1, "first upline1 win decodes the owner once");
        uint256 ew = _earnWord(lvl, oid);
        assertEq(uint32(ew >> 128), _id(u1));
        assertEq((ew >> 192) & 3, 1, "upline1 valid");

        vm.startStateDiffRecording();
        (w,,) = _payCombined(bytes32(0), buyer, _senderFor(code, 1, s1 + 1), lvl, 4000);
        acc = vm.stopAndReturnStateDiff();
        assertEq(w, _id(u1));
        assertEq(_extsloads(acc), 0, "cache hit");

        uint32 s3 = _senderFor(code, 2, 7_000_000);
        vm.startStateDiffRecording();
        (w,,) = _payCombined(bytes32(0), buyer, s3, lvl, 4000);
        acc = vm.stopAndReturnStateDiff();
        assertEq(w, _id(u2));
        assertEq(_extsloads(acc), 1, "hop one from the cache, one decode for hop two");
        ew = _earnWord(lvl, oid);
        assertEq(uint32(ew >> 160), _id(u2));
        assertEq((ew >> 192) & 3, 3, "both valid");

        vm.startStateDiffRecording();
        (w,,) = _payCombined(bytes32(0), buyer, _senderFor(code, 2, s3 + 1), lvl, 4000);
        acc = vm.stopAndReturnStateDiff();
        assertEq(w, _id(u2));
        assertEq(_extsloads(acc), 0, "cache hit");
    }

    function test_CustomCodeOwnerMissDecodesOncePerHop() public {
        (, , address u2, address buyer) = _customChain();
        uint32 s = _senderFor(bytes32("C_OWNER"), 2, 8_000_000);
        vm.startStateDiffRecording();
        (uint32 w,,) = _payCombined(bytes32(0), buyer, s, 4, 4000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(w, _id(u2));
        assertEq(_extsloads(acc), 2, "one decode per custom-code hop");
    }

    function test_DefaultCodeOwnerMissMakesNoExtsload() public {
        address u2 = makeAddr("dcU2");
        address u1 = makeAddr("dcU1");
        address owner = makeAddr("dcOwner");
        address buyer = makeAddr("dcBuyer");
        _buy(u2, bytes32(0));
        _refer(u1, _dflt(u2));
        _refer(owner, _dflt(u1));
        _refer(buyer, _dflt(owner));
        bytes32 route = _dflt(owner);
        vm.startStateDiffRecording();
        (uint32 w1,,) = _payCombined(bytes32(0), buyer, _senderFor(route, 1, 9_000_000), 2, 4000);
        (uint32 w2,,) = _payCombined(bytes32(0), buyer, _senderFor(route, 2, 9_000_000), 3, 4000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(w1, _id(u1));
        assertEq(w2, _id(u2));
        assertEq(_extsloads(acc), 0, "default-code hops carry their keys");
    }

    // =====================================================================
    // 11. Credits by ID
    // =====================================================================

    function test_NoReferrerPaysProtocolIdsWithoutQuestHop() public {
        address b = makeAddr("noRef");
        for (uint256 parity; parity < 2; ++parity) {
            uint32 sid = 10_000_000;
            while (_entropy(sid, VAULT_CODE) % 2 != parity) ++sid;
            vm.startStateDiffRecording();
            uint256 kb = _pay(4000, bytes32(0), b, sid, 1);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            assertEq(kb, 0);
            bytes[] memory credits = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
            assertEq(credits.length, 1);
            _assertCredit(credits[0], parity == 0 ? 1 : 2, 1000);
            assertEq(_calls(acc, address(affiliate), address(quests), quests.handleAffiliate.selector).length, 0);
        }
    }

    function test_WinnerCreditedByIdAfterQuestHop() public {
        address o = makeAddr("qhOwner");
        address up = makeAddr("qhUp");
        address b = makeAddr("qhBuyer");
        _buy(up, bytes32(0));
        _create(o, bytes32("QHOP"), 10);
        _refer(o, _dflt(up));
        _refer(b, bytes32("QHOP"));
        uint32[2] memory winners = [_id(o), _id(up)];
        for (uint8 cls; cls < 2; ++cls) {
            uint32 w = winners[cls];
            uint32 sid = _senderFor(bytes32("QHOP"), cls, 12_000_000);
            vm.recordLogs();
            vm.startStateDiffRecording();
            uint256 kb = _pay(4000, bytes32(0), b, sid, 1);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(kb, 100, "10% kickback of 1000");
            uint256 hop = _firstIndex(acc, address(affiliate), address(quests), quests.handleAffiliate.selector);
            uint256 credit = _firstIndex(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
            assertLt(hop, credit, "quest hop precedes the credit");
            bytes[] memory h = _calls(acc, address(affiliate), address(quests), quests.handleAffiliate.selector);
            assertEq(h.length, 1);
            (uint32 hid, uint256 hamt) = abi.decode(h[0], (uint32, uint256));
            assertEq(hid, w, "quest hop by winner ID");
            assertEq(hamt, 900, "share after kickback");
            bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
            assertEq(c.length, 1);
            uint256 expected = 900 + _questRewards(logs, w);
            _assertCredit(c[0], w, expected);
            assertEq(_staked(logs, w), expected, "winner's ID lane");
        }
        // The quest hop's reward joins the winner's credit.
        uint32 sid0 = _senderFor(bytes32("QHOP"), 0, 13_000_000);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(quests.handleAffiliate.selector, winners[0], uint256(900)),
            abi.encode(uint256(77), uint8(3), uint32(0), true)
        );
        vm.expectCall(address(coinflip), abi.encodeCall(coinflip.creditFlip, (winners[0], uint256(977))));
        _pay(4000, bytes32(0), b, sid0, 1);
    }

    function test_MutualReferralUplineIsSenderPaysNothing() public {
        address s = makeAddr("mutS");
        address o = makeAddr("mutO");
        bytes32 code = bytes32("MUTUAL");
        _create(o, code, 0);
        uint32 sid = _giveWalletId(s);
        _refer(s, code);
        _refer(o, _dflt(s));
        uint32 oid = _id(o);
        for (uint256 i; i < 400 && _class(sid, code) != 1; ++i) vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(_class(sid, code), 1, "a day whose roll lands on upline1");
        vm.startStateDiffRecording();
        _pay(4000, bytes32(0), s, sid, 1);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_calls(acc, address(affiliate), address(quests), quests.handleAffiliate.selector).length, 0);
        assertEq(_calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector).length, 0);
        assertEq(affiliate.affiliateScore(1, oid), 1000, "earnings still booked");
        (uint32 w, uint256 c,) = _payCombined(bytes32(0), s, sid, 1, 4000);
        assertEq(w, sid, "the winner is the sender");
        assertEq(c, 0, "nothing owed");
        assertEq(affiliate.affiliateScore(1, oid), 2000);
    }

    function test_PurchasePairsBuyerKickbackWithOwnerCredit() public {
        address o = makeAddr("pairOwner");
        bytes32 code = bytes32("PAIR_CODE");
        _create(o, code, 20);
        uint32 oid = _id(o);
        address b = makeAddr("pairBuyer");
        _bumpIdsUntil(code, 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 bid = _buy(b, code);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _calls(acc, address(game), address(affiliate), affiliate.payAffiliateCombined.selector).length, 1
        );
        (uint32 id1, uint256 a1, uint32 id2, uint256 a2) = _pair(acc);
        uint256 total = _earnedTotal(logs, oid);
        uint256 kick = (total * 20) / 100;
        assertGt(total, 0);
        assertEq(id1, bid, "buyer leg by buyer ID");
        assertGe(a1, kick, "buyer leg carries the kickback");
        assertEq(id2, oid, "winner leg by winner ID");
        assertEq(a2, total - kick + _questRewards(logs, oid));
        assertEq(_staked(logs, oid), a2, "winner ledger");
        assertEq(_staked(logs, bid), a1, "buyer ledger");
    }

    function test_PurchasePairPaysUplineWinnerById() public {
        address up = makeAddr("pairUp");
        address o = makeAddr("pairOwner2");
        bytes32 code = bytes32("PAIR_UP");
        _buy(up, bytes32(0));
        _refer(o, _dflt(up));
        _create(o, code, 0);
        uint32 uid = _id(up);
        address b = makeAddr("pairBuyer2");
        _bumpIdsUntil(code, 1);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint32 bid = _buy(b, code);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint32 id1,, uint32 id2, uint256 a2) = _pair(acc);
        assertEq(id1, bid);
        assertEq(id2, uid, "upline1 wins by ID");
        assertEq(a2, _earnedTotal(logs, _id(o)) + _questRewards(logs, uid));
        assertEq(_staked(logs, uid), a2);
        assertEq(_extsloads(acc), 0, "the code's creation cached its uplines");
    }

    // =====================================================================
    // 12. claim(subs)
    // =====================================================================

    function test_ClaimNoReferrerSplitsToProtocolIds() public {
        address s1 = makeAddr("clNone");
        address s2 = makeAddr("clLocked");
        _seedBase(_giveWalletId(s1), 60);
        _buy(s2, bytes32(0));
        _seedBase(_id(s2), 41);
        address[] memory subs = new address[](2);
        subs[0] = s1;
        subs[1] = s2;
        vm.startStateDiffRecording();
        affiliate.claim(subs);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(c.length, 2);
        _assertCredit(c[0], 1, 51);
        _assertCredit(c[1], 2, 50);
    }

    /// @dev sub -> CL_A (a) -> u1 (default) -> u2 (default, locked).
    function _claimChain() internal returns (address a, address u1, address u2) {
        u2 = makeAddr("clU2");
        u1 = makeAddr("clU1");
        a = makeAddr("clA");
        _buy(u2, bytes32(0));
        _refer(u1, _dflt(u2));
        _refer(a, _dflt(u1));
        _create(a, bytes32("CL_A"), 0);
    }

    function test_ClaimReferredSplitsByIds() public {
        (address a, address u1, address u2) = _claimChain();
        address s = makeAddr("clSub");
        _refer(s, bytes32("CL_A"));
        _seedBase(_giveWalletId(s), 1000);
        vm.startStateDiffRecording();
        _claim(s);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(c.length, 3);
        _assertCredit(c[0], _id(a), 750);
        _assertCredit(c[1], _id(u1), 200);
        _assertCredit(c[2], _id(u2), 50);
        assertEq(affiliate.affiliateScore(game.level() + 1, _id(a)), 1000, "leaderboard by ID");
    }

    function test_ClaimMutualReferralSkipsTheSubUpline() public {
        address a = makeAddr("muA");
        address s = makeAddr("muSub");
        _create(a, bytes32("MU_A"), 0);
        _refer(s, bytes32("MU_A"));
        _refer(a, _dflt(s));
        uint32 sid = _giveWalletId(s);
        _seedBase(sid, 1000);
        vm.startStateDiffRecording();
        _claim(s);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(c.length, 2, "upline1 (the sub) forfeits its cut");
        _assertCredit(c[0], _id(a), 950);
        _assertCredit(c[1], _id(a), 50);
        for (uint256 i; i < c.length; ++i) {
            (uint32 id,) = abi.decode(c[i], (uint32, uint256));
            assertTrue(id != sid, "never paid back to the sub");
        }
    }

    function test_ClaimVaultAsSubAndUpline() public {
        _seedBase(1, 1000);
        vm.startStateDiffRecording();
        _claim(ContractAddresses.VAULT);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(c.length, 2, "VAULT is upline1 of its own affiliate and forfeits");
        _assertCredit(c[0], 2, 950);
        _assertCredit(c[1], 2, 50);
    }

    function test_ClaimMixedBatchReverts() public {
        _claimChain();
        address s1 = makeAddr("mixA");
        address s2 = makeAddr("mixB");
        _refer(s1, bytes32("CL_A"));
        _seedBase(_giveWalletId(s1), 100);
        _seedBase(_giveWalletId(s2), 100);
        address[] memory subs = new address[](2);
        subs[0] = s1;
        subs[1] = s2;
        vm.expectRevert(DegenerusAffiliate.Insufficient.selector);
        affiliate.claim(subs);
    }

    function test_ClaimDuplicateSubDrainsOnce() public {
        (address a, address u1, address u2) = _claimChain();
        address s = makeAddr("dupSub");
        _refer(s, bytes32("CL_A"));
        _seedBase(_giveWalletId(s), 1000);
        address[] memory subs = new address[](2);
        subs[0] = s;
        subs[1] = s;
        vm.startStateDiffRecording();
        affiliate.claim(subs);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory c = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(c.length, 3);
        _assertCredit(c[0], _id(a), 750);
        _assertCredit(c[1], _id(u1), 200);
        _assertCredit(c[2], _id(u2), 50);
    }

    // =====================================================================
    // 13. Referrer views
    // =====================================================================

    function test_ReferrerViewsById() public {
        address x = makeAddr("vwNone");
        assertEq(affiliate.getReferrerId(x), 1, "unreferred reads VAULT");
        _assertIds(x, 1, 2, 1);
        assertEq(affiliate.getReferrer(x), ContractAddresses.VAULT);
        address locked = makeAddr("vwLocked");
        _buy(locked, bytes32(0));
        _assertIds(locked, 1, 2, 1);

        address o = makeAddr("vwOwner");
        address y = makeAddr("vwDefault");
        _refer(y, _dflt(o));
        _assertIds(y, _id(o), 1, 2);

        address o2 = makeAddr("vwOwner2");
        address z = makeAddr("vwCustom");
        _refer(o2, _dflt(o));
        _create(o2, bytes32("VW_CUSTOM"), 3);
        _refer(z, bytes32("VW_CUSTOM"));
        _assertIds(z, _id(o2), _id(o), 1);
        assertEq(affiliate.getReferrer(z), o2);

        // A pending bootstrap owner one hop up zeroes it and every later hop.
        address w = makeAddr("vwPendingUp");
        _refer(w, _dflt(P_A));
        _assertIds(w, _id(P_A), 0, 0);
        assertEq(affiliate.getReferrerId(w), _id(P_A));
        assertEq(_bootOwner(CODE_A), OWN_A, "views never materialize");
    }

    function _assertIds(address p, uint32 a, uint32 u1, uint32 u2) internal view {
        (uint32 ra, uint32 r1, uint32 r2) = affiliate.referrerIds(p);
        assertEq(ra, a, "affiliate");
        assertEq(r1, u1, "upline1");
        assertEq(r2, u2, "upline2");
        assertEq(affiliate.getReferrerId(p), a);
    }

    // =====================================================================
    // 14. Scores, totals, leader, bonus points and winners against an address reference
    // =====================================================================

    mapping(uint24 => mapping(address => uint256)) private _expScore;
    mapping(uint24 => uint256) private _expTotal;
    mapping(uint24 => address) private _expLeader;
    mapping(uint24 => uint256) private _expLeaderScore;

    function _refScale(uint256 amt, bool fresh, uint24 lvl, uint16 score) internal pure returns (uint256 s) {
        if (amt == 0) return 0;
        uint256 bps = fresh ? (lvl <= 3 ? 2500 : 2000) : 500;
        s = (amt * bps) / 10_000;
        if (s == 0 || score < 100) return s;
        if (score >= 255) return (s * 2500) / 10_000;
        uint256 reduction = (7500 * (uint256(score) - 100)) / 155;
        return (s * (10_000 - reduction)) / 10_000;
    }

    function _book(uint24 lvl, address owner, uint256 amt) internal {
        if (amt == 0) return;
        _expScore[lvl][owner] += amt;
        _expTotal[lvl] += amt;
        if (_expScore[lvl][owner] > _expLeaderScore[lvl]) {
            _expLeader[lvl] = owner;
            _expLeaderScore[lvl] = _expScore[lvl][owner];
        }
    }

    function _refBonus(uint24 curr, address owner) internal view returns (uint256) {
        if (curr == 0) return 0;
        uint256 cap = (25 ether * uint256(2000) * 1000) / 10_000;
        uint256 sum;
        for (uint24 off = 1; off <= 5; ++off) {
            if (curr <= off) break;
            uint24 lvl = curr - off;
            sum += _expScore[lvl][owner] * PriceLookupLib.priceForLevel(lvl);
            if (sum >= cap) break;
        }
        uint256 vol = (sum * 10_000) / (uint256(2000) * 1000);
        if (vol == 0) return 0;
        uint256 pts = vol <= 5 ether ? (vol * 4) / 1 ether : 20 + ((vol - 5 ether) * 3) / 2 ether;
        return pts > 50 ? 50 : pts;
    }

    /// @dev The winner the address-keyed resolution picks for this roll.
    function _refWinner(bytes32 route, address owner, uint32 sid) internal view returns (address) {
        uint256 r = _entropy(sid, route) % 20;
        if (r < 15) return owner;
        address up1 = affiliate.getReferrer(owner);
        return r < 19 ? up1 : affiliate.getReferrer(up1);
    }

    function test_ScoresTotalsLeaderAndWinnersMatchAddressReference() public {
        address up = makeAddr("vUp");
        address o1 = makeAddr("vO1");
        address o2 = makeAddr("vO2");
        address o3 = makeAddr("vO3");
        _giveWalletId(up);
        _pay(0, bytes32(0), up, 0, 1); // locked without booking any earnings
        _refer(o1, _dflt(up));
        _create(o1, bytes32("V_O1"), 12);
        _giveWalletId(o2);
        _create(o3, bytes32("V_O3"), 0);
        _refer(o3, bytes32("V_O1"));
        address[3] memory owners = [o1, o2, o3];
        bytes32[3] memory codes = [bytes32("V_O1"), _dflt(o2), bytes32("V_O3")];
        for (uint256 step; step < 36; ++step) {
            uint256 k = step % 3;
            uint24 lvl = uint24(1 + ((step * 7) % 6));
            uint256 fresh = 300_000 + step * 13_331;
            uint256 recycled = (step % 4) * 77_777;
            uint256 lbFresh = (step % 5) * 90_001;
            uint16 score = uint16((step * 37) % 300);
            uint32 sid = uint32(20_000_000 + step);
            address expWinner = _refWinner(codes[k], owners[k], sid);
            vm.prank(address(game));
            (uint32 w,,) = affiliate.payAffiliateCombined(
                codes[k], address(uint160(0xE0000 + step)), sid, lvl, fresh, recycled, lbFresh, 0, score
            );
            assertEq(w, _id(expWinner), "winner");
            _book(
                lvl,
                owners[k],
                _refScale(fresh, true, lvl, 0) + _refScale(recycled, false, lvl, 0) + _refScale(lbFresh, true, lvl, score)
            );
        }
        for (uint24 lvl = 1; lvl <= 7; ++lvl) {
            assertEq(affiliate.totalAffiliateScore(lvl), _expTotal[lvl], "total");
            (uint32 lid, uint96 lscore) = affiliate.affiliateTop(lvl);
            assertEq(lid, _expLeader[lvl] == address(0) ? 0 : _id(_expLeader[lvl]), "leader");
            assertEq(uint256(lscore), _expLeaderScore[lvl], "leader score");
            for (uint256 k; k < 3; ++k) {
                assertEq(affiliate.affiliateScore(lvl, _id(owners[k])), _expScore[lvl][owners[k]], "score");
            }
        }
        for (uint24 curr; curr <= 9; ++curr) {
            for (uint256 k; k < 3; ++k) {
                assertEq(affiliate.affiliateBonusPointsBest(curr, _id(owners[k])), _refBonus(curr, owners[k]), "bonus");
            }
            assertEq(affiliate.affiliateBonusPointsBest(curr, 0), 0, "ID 0 reads zero");
        }
        assertGt(_refBonus(7, o1), 0, "history reaches the bonus curve");
    }

    // =====================================================================
    // 15. Events
    // =====================================================================

    function test_ChangedEventsCarryIdsAndOldSignaturesAreGone() public {
        address o = makeAddr("evOwner");
        address p = makeAddr("evPlayer");
        address l = makeAddr("evLocked");
        bytes32 code = bytes32("EV_CODE");
        vm.recordLogs();
        _create(o, code, 0);
        uint32 oid = _id(o);
        _refer(p, code);
        _pay(0, bytes32(0), l, 0, 1);
        _pay(4000, bytes32(0), p, _senderFor(code, 0, 30_000_000), 2);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertReferralUpdated(logs, address(affiliate), p, code, oid, false);
        _assertReferralUpdated(logs, address(affiliate), l, LOCKED, 1, true);
        uint256 earned;
        uint256 tops;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory g = logs[i];
            if (g.emitter != address(affiliate)) continue;
            bytes32 t0 = g.topics[0];
            assertTrue(
                t0 != OLD_OWNER_REGISTERED && t0 != OLD_REFERRAL_UPDATED && t0 != OLD_EARNINGS_RECORDED
                    && t0 != OLD_TOP_UPDATED,
                "address-keyed event signature"
            );
            if (t0 == EARNINGS_RECORDED) {
                ++earned;
                assertEq(uint256(g.topics[1]), uint256(oid));
                assertEq(abi.decode(g.data, (uint256)), uint256(2) | (uint256(1000) << 24), "level | total << 24");
            }
            if (t0 == TOP_UPDATED) {
                ++tops;
                assertEq(uint256(g.topics[1]), 2);
                assertEq(uint256(g.topics[2]), uint256(oid));
                assertEq(abi.decode(g.data, (uint96)), 1000);
            }
        }
        assertEq(earned, 1);
        assertEq(tops, 1);
    }

    // =====================================================================
    // 16. affiliateCode view
    // =====================================================================

    function test_AffiliateCodeViewShapes() public {
        address reg = makeAddr("acReg");
        uint32 rid = _giveWalletId(reg);
        _assertCodeView(_dflt(reg), reg, rid, 0);
        address unreg = makeAddr("acUnreg");
        _assertCodeView(_dflt(unreg), unreg, 0, 0);
        address o = makeAddr("acOwner");
        _create(o, bytes32("AC_CUSTOM"), 9);
        uint32 oid = _id(o);
        _assertCodeView(bytes32("AC_CUSTOM"), o, oid, 9);
        assertEq(_keyOf(oid), o);
        _assertCodeView(CODE_A, OWN_A, 0, KICK_A);
        _assertCodeView(bytes32("AC_UNKNOWN"), address(0), 0, 0);
        _refer(makeAddr("acMaterialize"), CODE_A);
        _assertCodeView(CODE_A, OWN_A, _id(OWN_A), KICK_A);
    }

    function _assertCodeView(bytes32 code, address owner, uint32 id, uint8 kickback) internal view {
        (address o, uint32 oid, uint8 k) = affiliate.affiliateCode(code);
        assertEq(o, owner, "owner");
        assertEq(oid, id, "ownerId");
        assertEq(k, kickback, "kickback");
    }

    // =====================================================================
    // 17. ID truth across a random history
    // =====================================================================

    /// forge-config: default.fuzz.runs = 32
    function testFuzz_StoredIdsAreCanonical(uint256 seed) public {
        address[] memory actors = new address[](8);
        for (uint256 i; i < 8; ++i) actors[i] = address(uint160(0xA00000 + i));
        bytes32[] memory pool = new bytes32[](32);
        uint256 n = _seedPool(pool, actors);
        for (uint256 step; step < 18; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            n = _fuzzStep(r, actors, pool, n);
        }
        bytes32[] memory codes = new bytes32[](n);
        for (uint256 i; i < n; ++i) codes[i] = pool[i];
        _assertIdTruth(actors, codes, 5);
    }

    function _seedPool(bytes32[] memory pool, address[] memory actors) internal pure returns (uint256 n) {
        pool[n++] = bytes32(0);
        pool[n++] = VAULT_CODE;
        pool[n++] = DGNRS_CODE;
        (bytes32[6] memory bc,,) = _bootCodes();
        for (uint256 i; i < 6; ++i) pool[n++] = bc[i];
        pool[n++] = _dflt(P_C);
        pool[n++] = _dflt(P_A);
        for (uint256 i; i < actors.length; ++i) pool[n++] = _dflt(actors[i]);
    }

    function _fuzzStep(uint256 r, address[] memory actors, bytes32[] memory pool, uint256 n)
        internal
        returns (uint256)
    {
        address actor = actors[r % actors.length];
        uint256 op = (r >> 8) % 6;
        bytes32 code = pool[(r >> 16) % n];
        uint24 lvl = uint24(1 + ((r >> 32) % 5));
        uint256 amount = 1000 + ((r >> 40) % 100_000);
        if (op == 0) {
            vm.prank(actor);
            try affiliate.referPlayer(code) {} catch {}
        } else if (op == 1) {
            bytes32 fresh = keccak256(abi.encode("FZ", r)) | bytes32(uint256(1) << 255);
            vm.prank(actor);
            try affiliate.createAffiliateCode(fresh, uint8((r >> 64) % 26)) {
                if (n < pool.length) pool[n++] = fresh;
            } catch {}
        } else if (op == 2) {
            uint32 id = _giveWalletId(actor);
            _payCombined(code, actor, id, lvl, amount);
        } else if (op == 3) {
            uint32 id = _giveWalletId(actor);
            vm.prank(address(game));
            affiliate.payAffiliate(amount, code, actor, id, lvl, (r >> 72) & 1 == 0, uint16((r >> 80) % 300));
        } else if (op == 4) {
            _seedBase(_giveWalletId(actor), uint32(amount));
            _claim(actor);
        } else {
            _buy(actor, code);
        }
        return n;
    }

    // =====================================================================
    // Game caller side: deity chain via referrerIds
    // =====================================================================

    function _deityRecipients(Vm.AccountAccess[] memory acc) internal view returns (address[] memory out) {
        bytes[] memory t = _calls(acc, address(game), address(sdgnrs), sdgnrs.transferFromPool.selector);
        uint256 n;
        for (uint256 i; i < t.length; ++i) {
            (IsDGNRS.Pool pool,,) = abi.decode(t[i], (IsDGNRS.Pool, address, uint256));
            if (pool == IsDGNRS.Pool.Affiliate) ++n;
        }
        out = new address[](n);
        n = 0;
        for (uint256 i; i < t.length; ++i) {
            (IsDGNRS.Pool pool, address to,) = abi.decode(t[i], (IsDGNRS.Pool, address, uint256));
            if (pool == IsDGNRS.Pool.Affiliate) out[n++] = to;
        }
    }

    function test_DeityChainPaysReferrerIdPayees() public {
        address u2 = makeAddr("dyU2");
        address u1 = makeAddr("dyU1");
        address a = makeAddr("dyA");
        address buyer = makeAddr("dyBuyer");
        _buy(u2, bytes32(0));
        _refer(u1, _dflt(u2));
        _refer(a, _dflt(u1));
        _create(a, bytes32("DY_A"), 0);
        vm.deal(buyer, 200 ether);
        vm.startStateDiffRecording();
        vm.prank(buyer);
        game.purchaseDeityPass{value: 100 ether}(0, 3, bytes32("DY_A"));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_calls(acc, address(game), address(affiliate), affiliate.referrerIds.selector).length, 1);
        assertEq(_calls(acc, address(game), address(affiliate), affiliate.getReferrer.selector).length, 0);
        _assertIds(buyer, _id(a), _id(u1), _id(u2));
        address[] memory to = _deityRecipients(acc);
        assertEq(to.length, 3, "affiliate and both uplines paid");
        assertEq(to[0], a);
        assertEq(to[1], u1);
        assertEq(to[2], u2);
        assertEq(uint24(game.mintPackedFor(a) >> 120), 100, "the conferred whale pass lands on the affiliate's key");
    }

    function test_DeityChainSkipsZeroUplineHops() public {
        uint32 pbid = _giveWalletId(P_B);
        address buyer = makeAddr("dyPendingUp");
        vm.deal(buyer, 200 ether);
        vm.startStateDiffRecording();
        vm.prank(buyer);
        game.purchaseDeityPass{value: 100 ether}(0, 4, _dflt(P_B));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _assertIds(buyer, pbid, 0, 0);
        address[] memory to = _deityRecipients(acc);
        assertEq(to.length, 1, "zero upline hops are skipped");
        assertEq(to[0], P_B);
        assertEq(_bootOwner(CODE_B), OWN_B, "the pending upline stays pending");
    }

    function test_DeityPendingDirectAffiliateReverts() public {
        vm.deal(P_A, 200 ether);
        vm.expectRevert(bytes4(keccak256("E()")));
        vm.prank(P_A);
        game.purchaseDeityPass{value: 100 ether}(0, 5, bytes32(0));
    }

    function test_DeityLinkTouchMaterializesPendingAffiliate() public {
        vm.deal(P_A, 200 ether);
        vm.startStateDiffRecording();
        vm.prank(P_A);
        game.purchaseDeityPass{value: 100 ether}(0, 5, CODE_A);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _assertMaterialized(CODE_A, OWN_A, KICK_A);
        _assertIds(P_A, _id(OWN_A), 1, 2);
        address[] memory to = _deityRecipients(acc);
        assertGt(to.length, 0);
        assertEq(to[0], OWN_A, "the materialized owner is paid");
    }
}

/// @notice The Degenerette resolution's referrer leg credits `getReferrerId(player)`.
contract AffiliateDegeneretteReferrerTest is AffiliateIdFixture {
    uint48 private constant IDX = 1;
    uint8 private constant SYMBOL = 9;

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 1 days);
        RecyclingState.seedWriteBuffer(address(game), IDX);
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        pools = (pools & ((uint256(1) << 128) - 1)) | (uint256(1_000_000 ether) << 128);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(pools));
    }

    function _wordScoring(uint8 minScore) private pure returns (uint256 word) {
        for (uint256 k; k < 200_000; ++k) {
            word = uint256(keccak256(abi.encodePacked("aff_referrer_leg", k)));
            (uint8 s,) = Ref.score(Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false));
            if (s >= minScore) return word;
        }
        revert("no word");
    }

    function _landWord(uint256 word) private {
        RecyclingState.seedWord(address(game), IDX, bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Places one high-scoring ETH spin for `player`, resolves it, and returns the referrer
    ///      credit the resolution made right after its `getReferrerId` read.
    function _resolve(address player) private returns (uint32 id, uint256 amount, Vm.Log[] memory logs) {
        vm.deal(player, 1 ether);
        vm.prank(player);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, 0.01 ether, 1, SYMBOL);
        _landWord(_wordScoring(7));
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(makeAddr("degCrank"));
        game.mineFlip();
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        logs = vm.getRecordedLogs();
        assertEq(game.degeneretteBetInfo(IDX, 1), 0, "resolved");
        bytes[] memory reads = _calls(acc, address(game), address(affiliate), affiliate.getReferrerId.selector);
        assertEq(reads.length, 1, "one referrer read");
        assertEq(abi.decode(reads[0], (address)), player);
        assertEq(_calls(acc, address(game), address(affiliate), affiliate.getReferrer.selector).length, 0);
        uint256 at = _firstIndex(acc, address(game), address(affiliate), affiliate.getReferrerId.selector);
        for (uint256 i = at + 1; i < acc.length; ++i) {
            if (_match(acc[i], address(game), address(coinflip), coinflip.creditFlip.selector)) {
                (id, amount) = abi.decode(_args(acc[i].data), (uint32, uint256));
                return (id, amount, logs);
            }
        }
        revert("no referrer credit");
    }

    function test_UnreferredPlayerCreditsVault() public {
        (uint32 id, uint256 amount,) = _resolve(makeAddr("degNoRef"));
        assertEq(id, 1);
        assertGt(amount, 0);
    }

    function test_ReferredPlayerCreditsReferrerId() public {
        address o = makeAddr("degOwner");
        address p = makeAddr("degPlayer");
        _refer(p, _dflt(o));
        uint32 oid = _id(o);
        (uint32 id, uint256 amount, Vm.Log[] memory logs) = _resolve(p);
        assertEq(id, oid);
        assertGt(amount, 0);
        assertEq(_staked(logs, oid), amount, "lands on the referrer's ID lane");
    }

    function test_PendingBootstrapReferrerIsANoOpCredit() public {
        (uint32 id, uint256 amount, Vm.Log[] memory logs) = _resolve(P_A);
        assertEq(id, 0, "an unregistered bootstrap owner reads 0");
        assertGt(amount, 0);
        assertEq(_stakeEvents(logs, 0), 0, "ID 0 credits nothing");
        assertEq(_bootOwner(CODE_A), OWN_A, "the view registers nobody");
        assertEq(_id(OWN_A), 0);
    }
}
