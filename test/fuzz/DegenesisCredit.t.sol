// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PlayerQuestView} from "../../contracts/interfaces/IDegenerusQuests.sol";

/// @title DegenesisCredit -- where Degenesis credit is earned, and where it is not
/// @notice Spec checks 2, 14 and 18 on the Degenesis timeline, every purchase through the real
///         facade. Credit is 25% of the actual charged price of a qualifying ETH, claimable or
///         prepaid purchase while block.timestamp < DEGENESIS_END_TS; FLIP-paid tickets, AFKing
///         signup and daily deliveries, the Vault and sDGNRS earn none. A Degenesis buy pays no affiliate
///         commission and earns no quest, streak or activity credit.
///         Claimable balances are seeded with vm.store (ledger, claimablePool and ETH in tandem)
///         because no real payout lands one on demand; the FLIP-redemption window and the Vault
///         operator case also write one storage word each, noted where they do.
contract DegenesisCredit is DegenesisFixture {
    bytes32 internal constant AFF_CODE = bytes32(uint256(keccak256("degenesis-credit-aff")));
    address internal constant AFF_OWNER = address(0xA11F00);
    address internal constant REFERRED = address(0xB0B0B0);

    address internal alice;

    function _affiliateBootstrap() internal pure override returns (
        address[] memory owners, bytes32[] memory codes, uint8[] memory kicks, address[] memory players, bytes32[] memory refs
    ) {
        owners = new address[](1);
        codes = new bytes32[](1);
        kicks = new uint8[](1);
        players = new address[](1);
        refs = new bytes32[](1);
        owners[0] = AFF_OWNER;
        codes[0] = AFF_CODE;
        kicks[0] = 0;
        players[0] = REFERRED;
        refs[0] = AFF_CODE;
    }

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 0);
        _drain();
    }

    function _credit(address p) internal view returns (uint256) {
        return game.degenesisCreditOf(p);
    }

    function _idOf(address p) internal view returns (uint32) {
        return game.walletIdOf(p);
    }

    // ------------------------------------------------------------------ Mint purchase body

    /// @notice Tickets plus a lootbox paid with fresh ETH earn a quarter of the whole cost.
    function test_MintPurchase_FreshEth_CreditsQuarterOfTotalCost() public {
        uint256 cost = 10 * game.mintPrice() + 0.05 ether;
        vm.deal(alice, cost);
        vm.prank(alice);
        game.purchase{value: cost}(0, 4000, BoxOrderLib.boCustom(0.05 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(alice.balance, 0, "fixture: exact fresh payment");
        assertEq(_credit(alice), cost / 4, "credit = cost / 4");
    }

    /// @notice A claimable-funded purchase earns on its claimable spend.
    function test_MintPurchase_Claimable_CreditsQuarter() public {
        _seedClaimable(_idOf(alice), 1 ether);
        uint256 cost = 20 * game.mintPrice();
        uint256 before = _claimableOf(_idOf(alice));
        vm.prank(alice);
        game.purchase(0, 8000, 0, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(before - _claimableOf(_idOf(alice)), cost, "fixture: claimable paid");
        assertEq(_credit(alice), cost / 4, "claimable spend earns credit");
    }

    /// @notice A prepaid (AFKing-funded) purchase earns on its prepaid spend.
    function test_MintPurchase_PrepaidAfking_CreditsQuarter() public {
        vm.deal(alice, 1 ether);
        uint32 aliceId = _idOf(alice);
        vm.prank(alice);
        game.depositAfkingFunding{value: 1 ether}(aliceId);
        assertEq(_credit(alice), 0, "a deposit is not a purchase");
        uint256 cost = 10 * game.mintPrice();
        vm.prank(alice);
        game.purchase(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(1 ether - _afkingOf(_idOf(alice)), cost, "fixture: prepaid paid");
        assertEq(_credit(alice), cost / 4, "prepaid spend earns credit");
    }

    /// @notice Fresh ETH, then claimable, then prepaid in one purchase: all three legs earn.
    function test_MintPurchase_MixedLegs_CreditsWholeCost() public {
        uint32 id = _idOf(alice);
        _seedClaimable(id, 0.03 ether);
        vm.deal(alice, 0.05 ether);
        vm.prank(alice);
        game.depositAfkingFunding{value: 0.05 ether}(id);
        uint256 cost = 10 * game.mintPrice(); // 0.1 ETH: 0.02 fresh + 0.03 claimable + 0.05 prepaid
        vm.deal(alice, 0.02 ether);
        vm.prank(alice);
        game.purchase{value: 0.02 ether}(0, 4000, 0, bytes32(0), MintPaymentKind.Combined, false);
        assertEq(_afkingOf(id), 0, "fixture: prepaid leg used");
        assertEq(_claimableOf(id), 1, "fixture: claimable leg used to its sentinel");
        assertEq(_credit(alice), cost / 4, "every leg earns");
    }

    /// @notice FLIP-paid tickets earn nothing; in the same buyer's mixed spending only the ETH
    ///         part earns. The FLIP redemption window opens only past the 50 ETH target, so the
    ///         next pool is written past it (one storage word).
    function test_FlipPaidTickets_EarnNone_OnlyEthPartEarns() public {
        _setNextPool(60 ether);
        vm.prank(address(game));
        coin.mintForGame(alice, 10_000_000 ether);
        vm.prank(alice);
        game.redeemFlip(0, 4000);
        assertEq(_credit(alice), 0, "FLIP-paid tickets earn no credit");
        uint256 cost = 4 * game.mintPrice();
        vm.deal(alice, cost);
        vm.prank(alice);
        game.purchase{value: cost}(0, 1600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_credit(alice), cost / 4, "only the ETH part earns");
    }

    // ------------------------------------------------------------------ passes

    /// @dev Charged price of a pass buy: msg.value less the overpay credited to the payer's AFKing.
    function _charged(uint32 id, uint256 value, uint256 afkingBefore) internal view returns (uint256) {
        return value - (_afkingOf(id) - afkingBefore);
    }

    function test_WhalePass_CreditsFullCharge() public {
        uint32 id = _idOf(alice);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        game.purchaseWhalePass{value: 10 ether}(0, 2, bytes32(0));
        uint256 charged = _charged(id, 10 ether, 0);
        assertEq(charged, 4.8 ether, "fixture: two whale passes at 2.4 ETH");
        assertEq(_credit(alice), charged / 4, "whale pass: full charged price");
    }

    function test_LazyPass_CreditsFullCharge() public {
        uint32 id = _idOf(alice);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        uint256 charged = _charged(id, 1 ether, 0);
        assertGt(charged, 0, "fixture: lazy pass charged");
        assertEq(_credit(alice), charged / 4, "lazy pass: full charged price");
    }

    /// @notice A deity pass earns on its full charged price, nothing off for what it bundles,
    ///         and the bundled tickets earn nothing further.
    function test_DeityPass_CreditsFullChargedPrice() public {
        uint32 id = _idOf(alice);
        vm.deal(alice, 400 ether);
        vm.prank(alice);
        game.purchaseDeityPass{value: 400 ether}(0, 31, bytes32(0));
        uint256 charged = _charged(id, 400 ether, 0);
        uint256 recorded = uint96(uint256(vm.load(address(game),
            keccak256(abi.encode(uint256(id), GameSlots.DEITY_PASS_PRICE_PAID)))));
        assertEq(recorded, charged, "fixture: the recorded deity price is the charge");
        assertEq(_credit(alice), charged / 4, "deity pass: full charged price, no bundle discount");
    }

    // ------------------------------------------------------------------ foil

    function test_FoilPack_CreditsFoilCost() public {
        uint32 id = _idOf(alice);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.purchase{value: 1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        uint256 charged = _charged(id, 1 ether, 0);
        assertGt(charged, 0, "fixture: foil pack charged");
        assertEq(_credit(alice), charged / 4, "foil pack: credit on its cost");
    }

    function test_FoilPackWithTickets_CreditsBothLegs() public {
        uint32 id = _idOf(alice);
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        game.purchase{value: 2 ether}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        uint256 charged = _charged(id, 2 ether, 0);
        assertApproxEqAbs(_credit(alice), charged / 4, 1, "tickets + foil: credit on the whole charge");
    }

    // ------------------------------------------------------------------ AFKing

    /// @notice Signup buys nothing, and the daily deliveries that follow earn no credit.
    function test_AfkingSignupAndDailyDeliveriesEarnNone() public {
        address sub = _player("subscriber", 1 ether);
        uint32 id = _idOf(sub);
        uint256 seat = _grantSeat(sub);
        vm.prank(sub);
        game.subscribe{value: 1 ether}(0, false, 1, seat);
        assertEq(_afkingOf(id), 1 ether, "signup buys nothing");
        assertEq(game.degenesisCreditOf(sub), 0, "signup earns none");

        _driveDay(2);
        _driveDay(3);
        assertLt(_afkingOf(id), 1 ether, "fixture: daily deliveries spent");
        assertEq(game.degenesisCreditOf(sub), 0, "daily deliveries earn none");
    }

    // ------------------------------------------------------------------ protocol bodies

    /// @notice Vault purchases and sDGNRS's AFKing deliveries earn no credit.
    function test_VaultAndSdgnrs_EarnNone() public {
        vm.deal(ContractAddresses.CREATOR, 1 ether);
        vm.prank(ContractAddresses.CREATOR);
        vault.gamePurchase{value: 0.2 ether}(8000, 0, bytes32(0), MintPaymentKind.DirectEth, 0);
        assertEq(_creditOfId(VAULT_ID), 0, "the Vault earns no credit");

        // sDGNRS's daily deliveries run on Degenesis-split AFKing funding.
        _earnCredit(alice, 1 ether);
        _driveDay(2);
        _buyDegenesis(alice, 1 ether);
        _driveDay(3);
        uint256 afk = _afkingOf(SDGNRS_ID);
        assertGt(afk, 0, "fixture: sDGNRS funded by the split");
        _driveDay(4);
        assertLt(_afkingOf(SDGNRS_ID), afk, "fixture: sDGNRS delivered from its AFKing funding");
        assertEq(_creditOfId(SDGNRS_ID), 0, "sDGNRS earns no credit");
    }

    // ------------------------------------------------------------------ window

    /// @notice Credit accrues through the last second before DEGENESIS_END_TS and not from it.
    function test_CreditClosesAtDegenesisEndTs() public {
        _driveThrough(8);
        uint256 price = game.mintPrice();
        vm.warp(GameTimeLib.DEGENESIS_END_TS - 1);
        vm.deal(alice, price * 8);
        _buyTickets(alice, 4);
        assertEq(_credit(alice), price, "open until the last second");
        vm.warp(GameTimeLib.DEGENESIS_END_TS);
        _buyTickets(alice, 4);
        assertEq(_credit(alice), price, "closed from DEGENESIS_END_TS");
    }

    // ------------------------------------------------------------------ Degenesis buy itself

    /// @notice A Degenesis buy consumes credit 1:1, needs credit, and earns none itself.
    function test_DegenesisBuy_ConsumesCreditOneToOne() public {
        _earnCredit(alice, 0.5 ether);
        uint256 credit = _credit(alice);
        _driveDay(2);
        _buyDegenesis(alice, 0.2 ether);
        assertEq(_credit(alice), credit - 0.2 ether, "consumed 1:1, nothing earned back");
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDegenesisBox{value: 1 ether}(0, credit - 0.2 ether + UNIT);
    }

    /// @notice The Vault cannot buy a Degenesis box directly, even holding credit (written into
    ///         storage here, since the Vault never earns any, to isolate the Vault block).
    function test_VaultCannotBuyDegenesis_Direct() public {
        _driveDay(2);
        _seedCredit(VAULT_ID, 10 ether);
        vm.deal(ContractAddresses.VAULT, 1 ether);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.1 ether}(0, 0.1 ether);
    }

    /// @notice An operator approved for wallet 1 cannot buy for the Vault, while the same kind of
    ///         approval for a player works.
    function test_VaultOperatorCannotBuyDegenesis() public {
        _driveDay(2);
        _seedCredit(VAULT_ID, 10 ether);
        address op = _player("operator", 2 ether);
        vm.prank(ContractAddresses.CREATOR);
        vault.gameSetOperatorApproval(op, true);
        vm.prank(op);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.1 ether}(VAULT_ID, 0.1 ether);

        // Positive control: an operator for a player buys within the player's credit.
        _earnCredit(alice, 0.1 ether);
        vm.prank(alice);
        game.setOperatorApproval(0, op, true);
        uint32 aliceId = _idOf(alice);
        vm.prank(op);
        game.buyDegenesisBox{value: 0.1 ether}(aliceId, 0.1 ether);
        assertEq(_cohortCount(1), 1, "the player's order joined cohort 1");
    }

    /// @notice A Degenesis buy by a referred player pays no affiliate commission and moves no
    ///         quest progress, mint streak, activity score or coinflip stake. Positive control:
    ///         the same player's ticket buy does move the affiliate score.
    function test_DegenesisBuy_NoAffiliateQuestStreakActivity() public {
        _driveDay(2);
        vm.deal(REFERRED, 10 ether);
        uint32 rid = _idOf(REFERRED);
        if (rid == 0) rid = _giveWalletId(REFERRED);
        uint32 affId = _idOf(AFF_OWNER);
        uint256 scoreBefore = affiliate.affiliateScore(1, affId);
        vm.prank(REFERRED);
        game.purchase{value: 4 ether}(0, 400 * 400, 0, AFF_CODE, MintPaymentKind.DirectEth, false);
        assertGt(affiliate.affiliateScore(1, affId), scoreBefore, "control: a ticket buy pays the affiliate");

        uint256 score = affiliate.affiliateScore(1, affId);
        bytes memory quest = abi.encode(quests.getPlayerQuestView(rid));
        uint256 packed = game.mintPackedFor(REFERRED);
        (uint256 activity,) = game.playerActivityScore(REFERRED);
        uint256 flipStake = coinflip.coinflipAmount(REFERRED);
        uint256 affStake = coinflip.coinflipAmount(AFF_OWNER);

        vm.prank(REFERRED);
        game.buyDegenesisBox{value: 0.5 ether}(0, 0.5 ether);
        assertEq(_cohortCount(1), 1, "fixture: the order landed");

        assertEq(affiliate.affiliateScore(1, affId), score, "no affiliate score");
        assertEq(abi.encode(quests.getPlayerQuestView(rid)), quest, "no quest progress");
        assertEq(game.mintPackedFor(REFERRED), packed, "no streak or mint statistics");
        (uint256 activityAfter,) = game.playerActivityScore(REFERRED);
        assertEq(activityAfter, activity, "no activity credit");
        assertEq(coinflip.coinflipAmount(REFERRED), flipStake, "no FLIP kickback");
        assertEq(coinflip.coinflipAmount(AFF_OWNER), affStake, "no affiliate FLIP");
    }
}
