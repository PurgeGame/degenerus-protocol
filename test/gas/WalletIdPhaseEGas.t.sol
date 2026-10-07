// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract WalletIdPhaseEGasSeeder is DegenerusGameStorage, WalletSeed {
    function seedLevel(uint24 lvl) external {
        level = lvl;
        purchaseStartDay = _simulatedDayIndex();
        dailyIdx = purchaseStartDay;
        rngRequestTime = uint48(block.timestamp);
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = false;
        phaseTransitionActive = false;
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
        prizePoolPendingPacked = uint256(1 ether) | (uint256(1 ether) << 128);
    }

    /// @dev Register `player` and give it durable purchase history (betting and quest gates).
    function seedHistory(address player, uint256 mintData) external returns (uint32 id) {
        id = _seedWallet(player);
        mintPacked_[_walletIdOf(player)] |= mintData;
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every measured call is its own transaction against
///      committed prior state. Phase E wallet-ID paths that the customer gas suites do not
///      cover. Historical pre-E measurements are preserved in the planning gas artifacts.
contract WalletIdPhaseEGasTest is DeployProtocol {
    address private constant REG = address(0xA11CE);
    address private constant FRESH = address(0xF2E5);
    address private constant U2 = address(0xB002);
    address private constant U1 = address(0xB001);
    address private constant OWNER = address(0xB000);
    bytes32 private constant CUSTOM = bytes32("PHASE_E_CODE");
    bytes32 private constant ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    uint32 private constant BOARD = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    uint32 private constant BOARD2 = 2 | (uint32(3) << 6) | (uint32(2) << 15);
    /// @dev Durable purchase history at level 24: last level, level count and day set.
    uint256 private constant HISTORY = uint256(24) | (uint256(3) << 24) | (uint256(20) << 72);

    bytes private gameCode;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.warp(block.timestamp + 20 days);
        TicketQueueStorage.retireCompleted(address(game), 24);
        _seeder().seedLevel(24);
        _restoreGame();
        vm.deal(address(game), 1_000 ether);
        uint24 day = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
        address[5] memory funded = [REG, U2, U1, OWNER, FRESH];
        for (uint256 i; i < funded.length; ++i) vm.deal(funded[i], 1_000 ether);
        _ticket(REG, 0);
        // Referral chain U2 <- U1 <- OWNER, each registered by a purchase; OWNER also owns CUSTOM.
        _ticket(U2, 0);
        _ticket(U1, _default(U2));
        _ticket(OWNER, _default(U1));
        vm.prank(OWNER);
        affiliate.createAffiliateCode(CUSTOM, 0);
    }

    // ---------------------------------------------------------------------
    // Fixture plumbing
    // ---------------------------------------------------------------------

    function _seeder() private returns (WalletIdPhaseEGasSeeder) {
        if (gameCode.length == 0) gameCode = address(game).code;
        vm.etch(address(game), type(WalletIdPhaseEGasSeeder).runtimeCode);
        return WalletIdPhaseEGasSeeder(address(game));
    }

    function _restoreGame() private { vm.etch(address(game), gameCode); }

    function _history(address player) private returns (uint32 id) {
        id = _seeder().seedHistory(player, HISTORY);
        _restoreGame();
    }

    function _price() private view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }

    function _ticket(address buyer, bytes32 code) private {
        uint256 price = _price();
        vm.prank(buyer);
        game.purchase{value: price}(0, 400, 0, code, MintPaymentKind.DirectEth, false);
    }

    function _default(address owner) private pure returns (bytes32) { return bytes32(uint256(uint160(owner))); }

    function _report(string memory scenario) private {
        uint256 used = vm.snapshotGasLastCall("wallet-id-phase-e", scenario);
        emit log_named_uint(scenario, used);
    }

    function _key(address player) private view returns (uint32) {
        return game.walletIdOf(player);
    }

    function _credit(address player, uint256 amount) private {
        uint32 id = _key(player);
        vm.prank(address(game));
        coinflip.creditFlip(id, amount);
    }

    function _creditPasses(address player, uint32 normal) private {
        uint32 id = _key(player);
        vm.prank(address(game));
        crapsBattle.creditPasses(id, normal, 0);
    }

    function _deliverPasses(address player, uint32 normal) private {
        uint32 id = _key(player);
        vm.prank(address(game));
        crapsBattle.deliverPasses(id, normal, 0);
    }

    function _wallet(uint256 i) private pure returns (address) { return address(uint160(0xC0FFEE0000 + i)); }

    // ---------------------------------------------------------------------
    // FLIP credits by wallet ID (GAME creditor)
    // ---------------------------------------------------------------------

    function test_Gas_CreditFresh() public {
        _history(_wallet(1));
        _credit(_wallet(1), 1000);
        _report("credit_fresh_lane");
    }

    function test_Gas_CreditRepeat() public {
        _history(_wallet(1));
        _credit(_wallet(1), 1000);
        _credit(_wallet(1), 1000);
        _report("credit_repeat_lane");
    }

    function test_Gas_CreditBatchTenFresh() public {
        uint32[] memory keys = new uint32[](10);
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            _history(_wallet(i + 1));
            keys[i] = _key(_wallet(i + 1));
            amounts[i] = 1000;
        }
        vm.prank(address(game));
        coinflip.creditFlipBatch(keys, amounts);
        _report("credit_batch_10_fresh");
    }

    function test_Gas_CreditPairFresh() public {
        _history(_wallet(1));
        _history(_wallet(2));
        uint32 a = _key(_wallet(1));
        uint32 b = _key(_wallet(2));
        vm.prank(address(game));
        coinflip.creditFlipPair(a, 1000, b, 1000);
        _report("credit_pair_fresh");
    }

    // ---------------------------------------------------------------------
    // Coinflip player actions
    // ---------------------------------------------------------------------

    function _flip(address player) private {
        vm.prank(address(game));
        coin.mintForGame(player, 1_000_000);
    }

    function test_Gas_CoinflipDepositNewWallet() public {
        _flip(FRESH);
        vm.prank(FRESH);
        coinflip.depositCoinflip(0, 1000);
        _report("coinflip_deposit_new_wallet");
    }

    function test_Gas_CoinflipDepositRegisteredUncached() public {
        _flip(REG);
        vm.prank(REG);
        coinflip.depositCoinflip(0, 1000);
        _report("coinflip_deposit_registered_uncached");
    }

    function test_Gas_CoinflipDepositRepeat() public {
        _flip(REG);
        vm.prank(REG);
        coinflip.depositCoinflip(0, 1000);
        vm.prank(REG);
        coinflip.depositCoinflip(0, 1000);
        _report("coinflip_deposit_repeat");
    }

    function test_Gas_CoinflipClaimUncached() public {
        vm.prank(REG);
        coinflip.claimCoinflips(0, 1);
        _report("coinflip_claim_uncached");
    }

    function test_Gas_CoinflipClaimRepeat() public {
        vm.prank(REG);
        coinflip.claimCoinflips(0, 1);
        vm.prank(REG);
        coinflip.claimCoinflips(0, 1);
        _report("coinflip_claim_repeat");
    }

    // ---------------------------------------------------------------------
    // Affiliate legs of a referred ticket purchase
    // ---------------------------------------------------------------------

    /// @dev A registered, referred buyer whose winner roll on `code` lands in `branch`
    ///      (0 owner, 1 first upline, 2 second upline). The roll is keyed by the buyer's wallet ID,
    ///      so the buyer is registered with spare wallets until its ID qualifies.
    function _referredBuyer(bytes32 code, uint256 branch, uint256 salt) private returns (address buyer) {
        uint24 day = GameTimeLib.currentDayIndex();
        for (uint256 i; ; ++i) {
            buyer = address(uint160(uint256(keccak256(abi.encode("buyer", code, branch, salt, i)))));
            uint32 next = uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
            uint256 roll = uint256(keccak256(abi.encodePacked(ROLL_TAG, day, next, code))) % 20;
            if ((branch == 0 && roll < 15) || (branch == 1 && roll >= 15 && roll < 19) || (branch == 2 && roll == 19)) {
                break;
            }
            _giveWalletId(buyer);
        }
        vm.prank(buyer);
        affiliate.referPlayer(code);
        require(_giveWalletId(buyer) != 0, "buyer id");
        vm.deal(buyer, 10 ether);
    }

    function _affiliate(string memory label, bytes32 code, uint256 branch, bool repeat) private {
        address buyer = _referredBuyer(code, branch, 0);
        if (repeat) _ticket(buyer, 0);
        _ticket(buyer, 0);
        _report(label);
    }

    function test_Gas_AffDefaultOwner() public { _affiliate("aff_default_owner_first", _default(OWNER), 0, false); }
    function test_Gas_AffDefaultUpline1() public { _affiliate("aff_default_upline1_first", _default(OWNER), 1, false); }
    function test_Gas_AffDefaultUpline2() public { _affiliate("aff_default_upline2_first", _default(OWNER), 2, false); }
    function test_Gas_AffDefaultUpline1Repeat() public { _affiliate("aff_default_upline1_repeat", _default(OWNER), 1, true); }
    function test_Gas_AffCustomOwner() public { _affiliate("aff_custom_owner_first", CUSTOM, 0, false); }
    function test_Gas_AffCustomUpline1() public { _affiliate("aff_custom_upline1_first", CUSTOM, 1, false); }
    function test_Gas_AffCustomUpline2() public { _affiliate("aff_custom_upline2_first", CUSTOM, 2, false); }
    function test_Gas_AffCustomUpline1Repeat() public { _affiliate("aff_custom_upline1_repeat", CUSTOM, 1, true); }

    /// @dev A default code whose owner never played: the first use registers the owner.
    function test_Gas_AffDefaultFirstUseUnregisteredOwner() public {
        address buyer = address(0xD00D);
        vm.deal(buyer, 10 ether);
        _ticket(buyer, _default(address(0xFEED)));
        _report("aff_default_first_use_new_owner");
    }

    // ---------------------------------------------------------------------
    // Craps doors and pass ledger
    // ---------------------------------------------------------------------

    function _openDay() private {
        RecyclingState.seedDailyWord(address(game), uint24(game.currentDayView()), 40 << 8);
        vm.prank(address(game));
        crapsBattle.openBonusDay();
    }

    function test_Gas_CrapsWindowFirstNewWallet() public {
        _openDay();
        _flip(FRESH);
        vm.prank(FRESH);
        crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        _report("craps_window_first_new_wallet");
    }

    function test_Gas_CrapsWindowFirstRegistered() public {
        _openDay();
        _flip(REG);
        vm.prank(REG);
        crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        _report("craps_window_first_registered");
    }

    function test_Gas_CrapsWindowUnchangedBoard() public {
        _openDay();
        _flip(REG);
        vm.prank(REG);
        crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        vm.prank(REG);
        crapsBattle.enterBonusBattle(0, 2, BOARD, 1);
        _report("craps_window_unchanged_board");
    }

    function test_Gas_CrapsWindowChangedBoard() public {
        _openDay();
        _flip(REG);
        vm.prank(REG);
        crapsBattle.enterBonusBattle(0, 1, BOARD, 1);
        vm.prank(REG);
        crapsBattle.enterBonusBattle(0, 2, BOARD2, 1);
        _report("craps_window_changed_board");
    }

    function test_Gas_PassCreditFresh() public {
        _creditPasses(REG, 2);
        _report("pass_credit_fresh");
    }

    function test_Gas_PassCreditRepeat() public {
        _creditPasses(REG, 2);
        _creditPasses(REG, 2);
        _report("pass_credit_repeat");
    }

    function test_Gas_PassDeliver() public {
        _deliverPasses(REG, 1);
        _report("pass_deliver");
    }

    function test_Gas_PassSpend() public {
        _creditPasses(REG, 5);
        uint24 day = uint24(game.currentDayView()) + 1;
        vm.prank(REG);
        crapsBattle.applyCrapsPasses(0, day, 1, false, BOARD);
        _report("pass_spend");
    }

    // ---------------------------------------------------------------------
    // Parimutuel bets: fresh and shared array words
    // ---------------------------------------------------------------------

    function _open(uint24 round) private {
        vm.mockCall(address(game), abi.encodeWithSignature("growthState(uint24)", uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(1)));
    }

    function _bettor(uint256 i) private returns (address p) {
        p = _wallet(100 + i);
        _history(p);
        _flip(p);
    }

    function _bet(address p, bool over) private {
        vm.prank(p);
        parimutuel.placeBet(0, over);
    }

    function test_Gas_PariFirstBettorFreshWords() public {
        _open(24);
        address p = _bettor(0);
        _bet(p, true);
        _report("pari_bet_first_fresh_words");
    }

    function test_Gas_PariSecondBettorSharedWord() public {
        _open(24);
        address a = _bettor(0);
        address b = _bettor(1);
        _bet(a, true);
        _bet(b, true);
        _report("pari_bet_second_shared_word");
    }

    function test_Gas_PariNinthBettorFreshLaneWord() public {
        _open(24);
        address[] memory ps = new address[](9);
        for (uint256 i; i < 9; ++i) ps[i] = _bettor(i);
        for (uint256 i; i < 8; ++i) _bet(ps[i], true);
        _bet(ps[8], true);
        _report("pari_bet_ninth_fresh_lane_word");
    }

    function test_Gas_PariRepeatBettorNextRound() public {
        address p = _bettor(0);
        _open(24);
        _bet(p, true);
        _open(25);
        _bet(p, false);
        _report("pari_bet_repeat_next_round");
    }

    // ---------------------------------------------------------------------
    // WWXRP entries
    // ---------------------------------------------------------------------

    function _wwxrp(address p) private {
        vm.prank(address(game));
        wwxrp.mintPrize(p, 10_000);
    }

    function test_Gas_WwxrpDailyFirstNewWallet() public {
        _wwxrp(FRESH);
        vm.prank(FRESH);
        wwxrp.enter(0, 100);
        _report("wwxrp_daily_first_new_wallet");
    }

    function test_Gas_WwxrpDailyRepeat() public {
        _wwxrp(REG);
        vm.prank(REG);
        wwxrp.enter(0, 100);
        vm.prank(REG);
        wwxrp.enter(0, 100);
        _report("wwxrp_daily_repeat");
    }

    function _level99() private {
        TicketQueueStorage.retireCompleted(address(game), 99);
        _seeder().seedLevel(99);
        _restoreGame();
    }

    function test_Gas_WwxrpIncineratorFirst() public {
        _level99();
        _wwxrp(REG);
        vm.prank(REG);
        wwxrp.enter(0, 100);
        _report("wwxrp_incinerator_first");
    }

    function test_Gas_WwxrpIncineratorRepeat() public {
        _level99();
        _wwxrp(REG);
        vm.prank(REG);
        wwxrp.enter(0, 100);
        vm.prank(REG);
        wwxrp.enter(0, 100);
        _report("wwxrp_incinerator_repeat");
    }
}
