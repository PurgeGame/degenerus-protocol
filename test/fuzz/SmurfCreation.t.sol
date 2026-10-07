// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title SmurfCreation -- Game.createSmurf against the real protocol
/// @notice Proves the creation contract of plan F / decision G7 and hazard H-F2:
///         - only a caller holding a wallet ID creates a smurf;
///         - the owner's referral resolves and locks first (a default-code owner registers
///           before the smurf ID is taken), then the smurf copies it verbatim, so its referrer is
///           the owner's referrer and never the owner;
///         - the smurf's table element is `ownerId << 160`, its mint word carries the smurf flag
///           (bit 147), and `SmurfCreated(ownerId, smurfId)` records creation;
///         - the one whole ticket, its mint history and its quest progress belong to the smurf, while
///           every payment leg (fresh ETH, claimable, AFKing, overpay credit) is the owner's;
///         - invalid payment, liveness and paid-admission checks revert atomically,
///           leaving no table push or referral write.
contract SmurfCreation is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant SMURF_CREATED = keccak256("SmurfCreated(uint32,uint32)");
    bytes32 private constant ENTRIES_BOUGHT = keccak256("EntriesBought(uint32,uint256,uint256)");

    /// @dev DegenerusAffiliate.playerReferralCode root (scripts/layout/golden/DegenerusAffiliate.json).
    uint256 private constant AFF_REFERRAL_ROOT = 2;
    bytes32 private constant REF_LOCKED = bytes32(uint256(1));
    uint32 private constant VAULT_ID = 1;

    uint256 private constant PAID_ADMISSION_WALLETS = 3_000_000_000;

    /// @dev Mint-word bits the creation write owns and no ticket purchase touches: whale-pass type,
    ///      seat latch, smurf flag (144..147), deity bit (172), curse count (203..207).
    uint256 private constant CREATION_MASK = (uint256(0xF) << 144) | (uint256(1) << 172)
        | (uint256(0x1F) << 203);
    /// @dev Mint-history fields a one-ticket purchase writes (level/count/streak/day/units lanes).
    uint256 private constant HISTORY_MASK = ((uint256(1) << 144) - 1) | (uint256(0xFFFFFF) << 148)
        | (uint256(0xFFFF) << 208);

    error E();
    error Insolvent();

    address private owner;
    address private referrer;
    address private control;
    address private stranger;
    uint256 private price;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 1_000 ether);
        owner = makeAddr("smurf_owner");
        referrer = makeAddr("smurf_referrer");
        control = makeAddr("smurf_control");
        stranger = makeAddr("smurf_stranger");
        vm.deal(owner, 100 ether);
        vm.deal(control, 100 ether);
        vm.deal(stranger, 100 ether);
        price = game.mintPrice();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------



    function _walletsLength() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _element(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.walletElement(id)));
    }

    function _refWord(address who) private view returns (bytes32) {
        return vm.load(address(affiliate), keccak256(abi.encode(_fixtureId(who), AFF_REFERRAL_ROOT)));
    }
    function _refWord(uint32 who) private view returns (bytes32) {
        return vm.load(address(affiliate), keccak256(abi.encode(_fixtureId(who), AFF_REFERRAL_ROOT)));
    }

    function _mintWord(address who) private view returns (uint256) {
        return _fixtureMint(who);
    }
    function _mintWord(uint32 who) private view returns (uint256) {
        return _fixtureMint(who);
    }

    /// @dev One whole ticket bought by `who` for itself (registers it and resolves its referral).
    function _buyTicket(address who, bytes32 code) private {
        vm.prank(who);
        game.purchase{value: price}(0, 400, 0, code, MintPaymentKind.DirectEth, false);
    }

    /// @dev `code` created by `referrer` (registers the referrer).
    function _referrerCode(bytes32 code) private returns (uint32 refId) {
        vm.prank(referrer);
        affiliate.createAffiliateCode(code, 0);
        refId = game.walletIdOf(referrer);
        assertTrue(refId != 0, "fixture: code creation registers its owner");
    }

    /// @dev Credit `id`'s claimable to `amount` (wei, incl. sentinel) with claimablePool in tandem.
    function _seedClaimable(uint32 id, uint256 amount) private {
        bytes32 slot = GameSlotKeys.balances(id);
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 old = uint128(w);
        vm.store(address(game), slot, bytes32(((w >> 128) << 128) | amount));
        bytes32 poolSlot = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 p = uint256(vm.load(address(game), poolSlot));
        uint256 pool = (p >> 128) + amount - old;
        vm.store(address(game), poolSlot, bytes32((pool << 128) | uint128(p)));
    }

    function _fundAfking(uint32 id, uint256 amount) private {
        vm.deal(address(this), address(this).balance + amount);
        game.depositAfkingFunding{value: amount}(id);
    }

    function _createSmurf(address o, bytes32 code, MintPaymentKind kind, uint256 value)
        private
        returns (uint32 smurfId, uint32 key)
    {
        uint32 expected = uint32(_walletsLength());
        vm.prank(o);
        smurfId = game.createSmurf{value: value}(code, kind);
        key = smurfId;
        assertTrue(smurfId >= expected, "smurf ID is taken from the table end");
    }

    /// @dev The game's WalletRegistered/SmurfCreated logs, in order.
    function _identityLogs(Vm.Log[] memory logs)
        private
        view
        returns (uint32[] memory regIds, address[] memory regKeys, uint256[] memory regAt, uint256 smurfAt,
                 uint32 smurfOwnerId, uint32 smurfIdLogged, uint256 smurfCount)
    {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) ++n;
        }
        regIds = new uint32[](n);
        regKeys = new address[](n);
        regAt = new uint256[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == WALLET_REGISTERED) {
                regIds[n] = uint32(uint256(logs[i].topics[1]));
                regKeys[n] = address(uint160(uint256(logs[i].topics[2])));
                regAt[n] = i;
                ++n;
            } else if (logs[i].topics[0] == SMURF_CREATED) {
                smurfAt = i;
                smurfOwnerId = uint32(uint256(logs[i].topics[1]));
                smurfIdLogged = uint32(uint256(logs[i].topics[2]));
                ++smurfCount;
            }
        }
    }

    // ---------------------------------------------------------------------
    // Registration, table element, mint word, events
    // ---------------------------------------------------------------------

    /// @notice A caller without a wallet ID cannot create a smurf, and nothing is pushed.
    function test_CallerWithoutId_RevertsE() public {
        uint256 len = _walletsLength();
        vm.prank(stranger);
        vm.expectRevert(E.selector);
        game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        assertEq(_walletsLength(), len, "no table push");
        assertEq(_refWord(stranger), bytes32(0), "no referral write");
    }

    /// @notice The smurf takes the next table position, stores its owner ID and smurf flag,
    ///         and emits SmurfCreated.
    function test_RegistersSmurf_ElementMintWordAndEvents() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        uint256 ownerWordBefore = _mintWord(owner);
        uint32 expectedId = uint32(_walletsLength());
        uint32 expectedKey = expectedId;

        vm.recordLogs();
        vm.prank(owner);
        uint32 smurfId = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        smurfId;

        assertEq(smurfId, expectedId, "smurfId = wallets.length before the push");
        assertEq(_walletsLength(), uint256(expectedId) + 1, "one table push");
        assertEq(_element(smurfId), uint256(ownerId) << 160, "element = ownerId << 160");

        uint256 word = _mintWord(expectedKey);
        assertEq(word & CREATION_MASK, (uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT),
            "mint word carries the smurf flag outside the purchase's history lanes");
        assertEq(_mintWord(owner), ownerWordBefore, "owner's mint word untouched");
        assertEq((_mintWord(owner) >> BitPackingLib.SMURF_FLAG_SHIFT) & 1, 0, "owner carries no smurf flag");

        (uint32[] memory regIds, address[] memory regKeys, uint256[] memory regAt, uint256 smurfAt,
         uint32 loggedOwner, uint32 loggedSmurf, uint256 smurfCount) = _identityLogs(logs);
        assertEq(regIds.length, 0, "smurfs emit only SmurfCreated");
        assertEq(smurfCount, 1, "one SmurfCreated");
        assertEq(loggedOwner, ownerId);
        assertEq(loggedSmurf, smurfId);


        (address key, address payee, bool authorized) = game.resolveAccount(smurfId, owner);
        assertEq(key, address(0));
        assertEq(payee, owner);
        assertTrue(authorized);
    }

    /// @notice The creation ticket is one whole ticket queued for the smurf: its owed entries and mint
    ///         history match an ordinary one-ticket buyer's, the quest handler sees the smurf's ID
    ///         and never the owner's, and the owner's history and queue stay unchanged.
    function test_OneWholeTicket_HistoryAndQuestFollowTheSmurf() public {
        _buyTicket(owner, bytes32(0));
        _buyTicket(control, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        uint256 ownerWordBefore = _mintWord(owner);
        uint256 ownerOwedBefore = _fixtureEntries(1, owner);
        uint32 expectedId = uint32(_walletsLength());
        uint32 expectedKey = expectedId;

        vm.expectCall(address(quests), abi.encodeWithSelector(quests.handlePurchase.selector, expectedId), 1);
        vm.expectCall(address(quests), abi.encodeWithSelector(quests.handlePurchase.selector, ownerId), 0);
        vm.expectEmit(true, false, false, true, address(game));
        emit EntriesBought(expectedId, 400, price);
        (uint32 smurfId, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        assertEq(smurfId, expectedId);

        uint32 owed = _fixtureEntries(1, key);
        assertGt(owed, 0, "the smurf owes entries");
        assertEq(owed, _fixtureEntries(1, control), "one whole ticket, as an ordinary buyer's");
        assertEq(_mintWord(key) & HISTORY_MASK, _mintWord(control) & HISTORY_MASK,
            "smurf mint history = an ordinary one-ticket buyer's");
        assertGt(_mintWord(key) & HISTORY_MASK, 0, "history recorded on the smurf");
        assertEq(_mintWord(owner), ownerWordBefore, "owner's mint history untouched");
        assertEq(_fixtureEntries(1, owner), ownerOwedBefore, "owner's queue untouched");
    }

    event EntriesBought(uint32 indexed buyer, uint256 entryQuantityScaled, uint256 weiIn);
    event AfkingFunded(uint32 indexed walletId, uint256 amount);
    event AfkingSpent(uint32 indexed walletId, uint256 amount);

    // ---------------------------------------------------------------------
    // Payment kinds: every leg is the owner's
    // ---------------------------------------------------------------------

    /// @notice DirectEth with the exact price: the owner's ETH pays, no ledger moves.
    function test_DirectEth_FreshEthFromOwner() public {
        _buyTicket(owner, bytes32(0));
        uint256 ethBefore = owner.balance;
        uint256 claimBefore = _fixtureClaimable(owner);
        uint256 afkBefore = _fixtureAfking(owner);
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        assertEq(owner.balance, ethBefore - price, "owner's fresh ETH paid");
        assertEq(_fixtureClaimable(owner), claimBefore);
        assertEq(_fixtureAfking(owner), afkBefore);
        assertEq(_fixtureClaimable(key), 0, "smurf ledger empty");
        assertEq(_fixtureAfking(key), 0, "smurf AFKing empty");
    }

    /// @notice DirectEth with no ETH: the owner's AFKing covers the ticket (the smurf has none).
    function test_DirectEth_NoValue_DebitsOwnerAfking() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        _fundAfking(ownerId, 1 ether);
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingSpent(ownerId, price);
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, 0);
        assertEq(_fixtureAfking(owner), 1 ether - price, "owner's AFKing debited");
        assertEq(_fixtureAfking(key), 0);
    }

    /// @notice Claimable: the owner's claimable pays; ETH sent with it credits the owner's AFKing.
    function test_Claimable_DebitsOwnerClaimable_ValueToOwnerAfking() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        _seedClaimable(ownerId, 1 ether);
        uint256 afkBefore = _fixtureAfking(owner);
        uint256 ethBefore = owner.balance;
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.Claimable, 0.3 ether);
        assertEq(_fixtureClaimable(owner), 1 ether - price, "owner's claimable debited");
        assertEq(_fixtureAfking(owner), afkBefore + 0.3 ether, "the ETH sent credits the owner's AFKing");
        assertEq(owner.balance, ethBefore - 0.3 ether);
        assertEq(_fixtureClaimable(key), 0);
        assertEq(_fixtureAfking(key), 0);
    }

    /// @notice Combined: the owner's ETH first, the owner's claimable for the rest.
    function test_Combined_OwnerEthThenOwnerClaimable() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        _seedClaimable(ownerId, 1 ether);
        uint256 half = price / 2;
        uint256 ethBefore = owner.balance;
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.Combined, half);
        assertEq(owner.balance, ethBefore - half, "owner's ETH leg");
        assertEq(_fixtureClaimable(owner), 1 ether - (price - half), "owner's claimable leg");
        assertEq(_fixtureClaimable(key), 0);
        assertEq(_fixtureAfking(key), 0);
    }

    /// @notice Fresh ETH above the price credits the owner's AFKing balance, never the smurf's.
    function test_Overpay_CreditsOwnerAfking() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        uint256 afkBefore = _fixtureAfking(owner);
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingFunded(ownerId, 0.5 ether);
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price + 0.5 ether);
        assertEq(_fixtureAfking(owner), afkBefore + 0.5 ether, "overpay to the owner's AFKing");
        assertEq(_fixtureAfking(key), 0, "nothing to the smurf");
    }

    /// @notice An unfunded creation reverts and rolls back the whole creation.
    function test_Unfunded_RevertsInsolvent_RollsBack() public {
        _buyTicket(owner, bytes32(0));
        uint256 len = _walletsLength();
        uint32 key = uint32(len);
        vm.prank(owner);
        vm.expectRevert(Insolvent.selector);
        game.createSmurf(bytes32(0), MintPaymentKind.DirectEth);
        assertEq(_walletsLength(), len, "no table push");
        assertEq(_mintWord(key), 0, "no mint word");
        assertEq(_refWord(key), bytes32(0), "no referral copy");
    }

    /// @notice `Internal` is not a player payment kind: E, and the creation rolls back entirely,
    ///         including the owner's referral lock and a default-code owner's registration.
    function test_InternalKind_RevertsE_NoTablePushNoReferralWrite() public {
        _giveWalletId(owner);
        address codeOwner = makeAddr("smurf_unregistered_code_owner");
        bytes32 code = bytes32(uint256(uint160(codeOwner)));
        uint256 len = _walletsLength();
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.createSmurf{value: price}(code, MintPaymentKind.Internal);
        assertEq(_walletsLength(), len, "no table push");
        assertEq(game.walletIdOf(codeOwner), 0, "the code owner's registration rolled back");
        assertEq(_refWord(owner), bytes32(0), "the owner's referral stays unset");
        assertEq(_refWord(uint32(len + 1)), bytes32(0), "no smurf referral");
    }

    // ---------------------------------------------------------------------
    // Referral
    // ---------------------------------------------------------------------

    /// @notice An owner with a referrer gives the smurf that referrer (never the owner), whatever
    ///         code the creation passes; the smurf's buy routes affiliate score to it.
    function test_Referral_OwnerWithReferrer_SmurfCopies() public {
        uint32 refId = _referrerCode(bytes32("SMURF_REF_ONE"));
        _buyTicket(owner, bytes32("SMURF_REF_ONE"));
        uint32 ownerId = game.walletIdOf(owner);
        address other = makeAddr("smurf_other_referrer");
        vm.prank(other);
        affiliate.createAffiliateCode(bytes32("SMURF_REF_TWO"), 0);
        uint256 scoreBefore = affiliate.affiliateScore(1, refId);

        (, uint32 key) = _createSmurf(owner, bytes32("SMURF_REF_TWO"), MintPaymentKind.DirectEth, price);

        assertEq(affiliate.getReferrerIdById(_fixtureId(owner)), refId, "owner's referral unchanged");
        assertEq(affiliate.getReferrerIdById(_fixtureId(key)), refId, "smurf's referrer = owner's referrer");
        assertTrue(affiliate.getReferrerIdById(_fixtureId(key)) != ownerId, "never the owner");
        (uint32 a0, uint32 u10, uint32 u20) = affiliate.referrerIdsById(_fixtureId(owner));
        (uint32 a1, uint32 u11, uint32 u21) = affiliate.referrerIdsById(_fixtureId(key));
        assertEq(a1, a0);
        assertEq(u11, u10);
        assertEq(u21, u20);
        assertEq(_refWord(key), _refWord(owner), "the word is copied verbatim");
        assertGt(affiliate.affiliateScore(1, refId), scoreBefore, "the smurf's ticket routes to the copied referrer");
    }

    /// @notice Unset owner with a valid code: the owner's referral is set from it, the smurf copies.
    function test_Referral_UnsetOwner_ValidCode_SetsOwnerThenCopies() public {
        uint32 refId = _referrerCode(bytes32("SMURF_REF_ONE"));
        _giveWalletId(owner);
        assertEq(_refWord(owner), bytes32(0), "fixture: owner unreferred");
        (, uint32 key) = _createSmurf(owner, bytes32("SMURF_REF_ONE"), MintPaymentKind.DirectEth, price);
        assertEq(affiliate.getReferrerIdById(_fixtureId(owner)), refId, "owner referred by the code");
        assertEq(affiliate.getReferrerIdById(_fixtureId(key)), refId, "smurf copies");
        assertEq(_refWord(key), _refWord(owner));
        assertEq(_refWord(owner), bytes32("SMURF_REF_ONE"));
    }

    /// @notice Unset owner with a blank code: both lock to no referrer.
    function test_Referral_UnsetOwner_BlankCode_LocksBoth() public {
        _giveWalletId(owner);
        (, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        assertEq(_refWord(owner), REF_LOCKED, "owner locked");
        assertEq(_refWord(key), REF_LOCKED, "smurf locked");
        assertEq(affiliate.getReferrerIdById(_fixtureId(owner)), VAULT_ID, "no referrer reads as the VAULT");
        assertEq(affiliate.getReferrerIdById(_fixtureId(key)), VAULT_ID);
    }

    /// @notice Unset owner passing its own default code: a self-referral locks the owner, so the
    ///         smurf is locked too and can never name its owner.
    function test_Referral_UnsetOwner_OwnDefaultCode_LocksBothNeverOwner() public {
        uint32 ownerId = _giveWalletId(owner);
        (, uint32 key) = _createSmurf(owner, bytes32(uint256(uint160(owner))), MintPaymentKind.DirectEth, price);
        assertEq(_refWord(owner), REF_LOCKED);
        assertEq(_refWord(key), REF_LOCKED);
        assertTrue(affiliate.getReferrerIdById(_fixtureId(key)) != ownerId, "never the owner");
    }

    /// @notice H-F2: an unregistered default code registers its owner BEFORE the smurf ID is taken:
    ///         smurfId = wallets.length after that registration, the key derives from it, and the
    ///         logs run code owner, smurf, SmurfCreated.
    function test_Referral_UnregisteredDefaultCode_RegistersCodeOwnerFirst() public {
        uint32 ownerId = _giveWalletId(owner);
        address codeOwner = makeAddr("smurf_default_code_owner");
        assertEq(game.walletIdOf(codeOwner), 0, "fixture: code owner unregistered");
        uint32 len = uint32(_walletsLength());

        vm.recordLogs();
        vm.prank(owner);
        uint32 smurfId = game.createSmurf{value: price}(bytes32(uint256(uint160(codeOwner))), MintPaymentKind.DirectEth);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(game.walletIdOf(codeOwner), len, "code owner takes the first new ID");
        assertEq(smurfId, len + 1, "smurf ID taken after the code owner's");
        uint32 key = smurfId;
        assertEq(_element(smurfId), uint256(ownerId) << 160, "key derives from the later ID");
        assertEq(affiliate.getReferrerIdById(_fixtureId(owner)), len, "owner referred by the code owner");
        assertEq(affiliate.getReferrerIdById(_fixtureId(key)), len, "smurf copies");

        (uint32[] memory regIds, address[] memory regKeys, uint256[] memory regAt, uint256 smurfAt,
         uint32 loggedOwner, uint32 loggedSmurf, uint256 smurfCount) = _identityLogs(logs);
        assertEq(regIds.length, 1, "only the ordinary referrer registers");
        assertEq(regIds[0], len);
        assertEq(regKeys[0], codeOwner);
        assertEq(smurfCount, 1);
        assertEq(loggedOwner, ownerId);
        assertEq(loggedSmurf, smurfId);
        assertGt(smurfAt, regAt[0], "referrer registered before SmurfCreated");
    }

    // ---------------------------------------------------------------------
    // Guards
    // ---------------------------------------------------------------------




    /// @notice Once liveness has triggered, creation reverts and rolls back.
    function test_LivenessTriggered_Reverts() public {
        _buyTicket(owner, bytes32(0));
        vm.warp(block.timestamp + 32 days);
        assertTrue(game.livenessTriggered(), "fixture: deadman fired");
        uint256 len = _walletsLength();
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        assertEq(_walletsLength(), len, "no table push");
    }

    /// @notice Paid admission: past 3B registered wallets a creation whose ticket costs under
    ///         0.04 ETH reverts E; at exactly 3B it still admits. (The admitted branch past 3B needs
    ///         a ticket price of at least 0.04 ETH, i.e. level 10 or later; not driven here.)
    function test_PaidAdmission_Past3B_CheapTicketRevertsE() public {
        _buyTicket(owner, bytes32(0));
        assertLt(price, 0.04 ether, "fixture: early-level ticket");
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAID_ADMISSION_WALLETS + 1));
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        assertEq(_walletsLength(), PAID_ADMISSION_WALLETS + 1, "no table push");
    }

    function test_PaidAdmission_At3B_Admits() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAID_ADMISSION_WALLETS));
        (uint32 smurfId, uint32 key) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        assertEq(smurfId, uint32(PAID_ADMISSION_WALLETS));
        assertEq(_element(smurfId), uint256(ownerId) << 160);
        assertEq(_walletsLength(), PAID_ADMISSION_WALLETS + 1);
    }

    /// @notice Two smurfs of one owner are distinct accounts with distinct keys, both owned.
    function test_TwoSmurfs_DistinctKeysSameOwner() public {
        _buyTicket(owner, bytes32(0));
        uint32 ownerId = game.walletIdOf(owner);
        (uint32 a, uint32 ka) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        (uint32 b, uint32 kb) = _createSmurf(owner, bytes32(0), MintPaymentKind.DirectEth, price);
        assertEq(b, a + 1);
        assertTrue(ka != kb);
        assertEq(_element(a) >> 160 & type(uint32).max, ownerId);
        assertEq(_element(b) >> 160 & type(uint32).max, ownerId);
        (, address pa, bool oka) = game.resolveAccount(a, owner);
        (, address pb, bool okb) = game.resolveAccount(b, owner);
        assertTrue(oka && okb);
        assertEq(pa, owner);
        assertEq(pb, owner);
    }
}
