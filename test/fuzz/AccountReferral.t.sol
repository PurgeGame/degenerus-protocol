// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {AccountFixture} from "./AccountFixture.t.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {QaSlots} from "../helpers/QaSlots.sol";

/// @title AccountReferral -- an account's default code credits its ID and pays its payee
/// @notice A third party buying on an account's default code books the affiliate score and the
///         Coinflip credit on that account's ID and allocates no wallet. Value reaches the current
///         payee: the wallet for an ordinary account; after a seizure the lender, whose FLIP is
///         collected through the sweep (the seller cannot claim).
contract AccountReferralTest is AccountFixture {
    bytes32 internal constant ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes4 internal constant CREDIT_PAIR = bytes4(keccak256("creditFlipPair_g578(uint32,uint256,uint32,uint256)"));

    address internal owner;
    uint32 internal ownerId;
    address internal third = makeAddr("account-ref-third");
    address internal stranger = makeAddr("account-ref-stranger");
    uint256 private _dummies;

    function setUp() public {
        _setUpAccountFixture();
        (owner, ownerId) = _wallet("account-ref-owner");
    }

    // ── fixtures ─────────────────────────────────────────────────────────────

    function _refWord(uint32 player) internal view returns (uint256) {
        return uint256(vm.load(address(affiliate), keccak256(abi.encode(player, QaSlots.REFERRAL))));
    }

    function _nextId() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
    }

    function _buy(address buyer, bytes32 code) internal {
        (,,,, uint256 p) = game.purchaseInfo_g1027();
        vm.deal(buyer, buyer.balance + p);
        vm.prank(buyer);
        game.purchaseOrderFor{value: p}(0, 400, 0, code, MintPaymentKind.DirectEth, false);
    }

    function _entropy(uint32 buyerId, bytes32 code) internal view returns (uint256) {
        uint24 d = GameTimeLib.currentDayIndexAt(vm.getBlockTimestamp());
        uint256 c = uint256(code);
        if (c >> 32 == (uint256(1) << 128)) code = bytes32((uint256(1) << 32) | uint32(c));
        return uint256(keccak256(abi.encodePacked(ROLL_TAG, d, buyerId, code)));
    }

    /// @dev 0 = the code's owner (roll < 15), 1 = upline1 (15..18), 2 = upline2 (19).
    function _class(uint32 buyerId, bytes32 code) internal view returns (uint8) {
        uint256 r = _entropy(buyerId, code) % 20;
        return r < 15 ? 0 : (r < 19 ? 1 : 2);
    }

    /// @dev Registers throwaway wallets until the next allocated ID rolls `cls` for `code`.
    function _bumpIdsUntil(bytes32 code, uint8 cls) internal {
        while (_class(_nextId(), code) != cls) {
            _giveWalletId(address(uint160(0xD0000000 + ++_dummies)));
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

    /// @dev A third party buys on account `id`'s default code (owner leg); the score and the
    ///      Coinflip credit book on `id`. Returns the credited stake.
    function _thirdPartyBuy(uint32 id) private returns (uint256 credit) {
        bytes32 code = affiliate.defaultCodeById(id);
        _bumpIdsUntil(code, 0);
        uint32 tId = _giveWalletId(third);
        assertEq(_class(tId, code), 0, "fixture: owner leg");

        uint32 next = _nextId();
        uint256 stakeBefore = coinflip.coinflipAmountById(id);
        vm.expectCall(address(game), abi.encodeWithSelector(game.registerWallet_g9539.selector), 0);
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
        assertEq(_refWord(tId), (uint256(1) << 32) | id, "the stored word names the account");
        assertEq(affiliate.getReferrerIdById(tId), id);
        assertGt(affiliate.affiliateScore(game.currentLvl() + 1, id) + affiliate.affiliateScore(game.currentLvl(), id), 0,
            "the earnings book on the account's ID");
        bool found;
        uint32 winner;
        (found,,, winner, credit) = _pairCall(acc);
        assertTrue(found, "the purchase credited Coinflip");
        assertEq(winner, id, "the affiliate share credits the account's ID");
        assertGt(credit, 0);
        assertEq(coinflip.coinflipAmountById(id) - stakeBefore, credit, "the stake sits on the account's ID");
    }

    /// @dev Resolve the next logical coinflip round as a win.
    function _winNextFlip() private {
        uint24 d = coinflip.requestedDailyIdx();
        uint256 word = uint256(keccak256(abi.encodePacked("account_referral_flip", d + 1))) | 1;
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, d + 1);
    }

    // ── tests ────────────────────────────────────────────────────────────────

    function test_aThirdPartyOnAnAccountsDefaultCodeCreditsTheAccountAndPaysItsWallet() public {
        _thirdPartyBuy(ownerId);
        assertEq(affiliate.getReferrerById(_fixtureId(third)), owner);
        _winNextFlip();
        uint256 before = coin.balanceOf(owner);
        vm.prank(owner);
        uint256 got = coinflip.claimCoinflips(ownerId, type(uint256).max);
        assertGt(got, 0, "the account won its flip");
        assertEq(coin.balanceOf(owner) - before, got, "the claim minted to the wallet");
    }

    function test_AcquiredAccountsDefaultCode_Vault() public { _acquiredCode(VAULT_ID); }

    function test_AcquiredAccountsDefaultCode_Sdgnrs() public { _acquiredCode(SDGNRS_ID); }

    /// @dev After the seizure the account's default code still refers by ID; its affiliate FLIP
    ///      collects to the lender, and the seller cannot claim it.
    function _acquiredCode(uint32 lender) private {
        _acquire(owner, ownerId, lender);
        address lenderAddr = _lenderAddress(lender);
        _thirdPartyBuy(ownerId);
        assertEq(affiliate.getReferrerById(_fixtureId(third)), lenderAddr, "the referrer resolves to the lender");
        _winNextFlip();

        vm.prank(owner);
        vm.expectRevert();
        coinflip.claimCoinflips(ownerId, type(uint256).max);

        uint32[] memory ids = new uint32[](1);
        ids[0] = ownerId;
        uint256 mark = _lenderFlipMark(lender);
        _expectLenderFlip(lender);
        vm.prank(lender == VAULT_ID ? lenderAddr : stranger);
        (, uint256 flipOut) = game.sweepAccounts(ids);
        assertGt(flipOut, 0, "the affiliate stake won and collected");
        _assertLenderFlip(lender, mark, flipOut);
        assertEq(coin.balanceOf(owner), 0, "nothing to the seller");
    }
}
