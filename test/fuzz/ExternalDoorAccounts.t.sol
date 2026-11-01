// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameFacade} from "../../contracts/modules/GameFacade.sol";

import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title ExternalDoorAccounts -- FLIP decimatorBurn, Parimutuel placeBet, WWXRP enter and Jackpots
///        claimBafConsolation acting for an account by wallet ID
/// @notice A is an ordinary account; P is an operator A approved on its ID; X is a stranger. The
///         authorized doors (decimatorBurn, placeBet, enter) revert `NotApproved` for X and Game `E`
///         for an unallocated ID; state follows the account's ID, wallet-token burns come from A's
///         wallet (the payee), never from P. The permissionless consolation claim takes any caller
///         and pays the score owner's payee. Self paths make no Game `resolveAccount` call; an
///         ID-addressed action makes exactly one and never registers a wallet.
contract ExternalDoorAccountsTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant DECIMATOR_BURN = keccak256("DecimatorBurn(uint32,uint256,uint64)");
    bytes32 internal constant BET_PLACED = keccak256("BetPlaced(uint32,uint24,bool,uint256)");
    bytes32 internal constant DRAW_ENTERED =
        keccak256("DrawEntered(uint24,uint32,uint8,uint32,uint256,uint256,uint256)");
    bytes32 internal constant INCIN_ENTERED =
        keccak256("IncineratorEntered(uint24,uint32,uint32,uint256,uint256,uint256)");
    bytes4 internal constant GROWTH_STATE = bytes4(keccak256("getGrowth(uint24)"));

    uint256 internal constant BURN = 2_000;
    uint256 internal constant STAKE = 1_000;
    /// @dev DecBattleRound.openedDay sits after poolWei (96) + count (40) + totalCreditedStack (64).
    uint256 internal constant OPENED_DAY_SHIFT = 200;
    uint256 internal constant WWXRP_LANE_SHIFT = 232;

    event BafConsolationClaimed(uint32 indexed player, uint24 indexed lvl, uint256 score, uint256 wwxrpAmount);

    address internal account;
    uint32 internal accountId;
    address internal stranger;
    address internal operator;
    uint32 internal operatorId;

    function setUp() public {
        _deployProtocol();
        account = makeAddr("xda_account");
        accountId = _giveWalletId(account);
        stranger = makeAddr("xda_stranger");
        operator = makeAddr("xda_operator");
        operatorId = _giveWalletId(operator);
        vm.prank(account);
        game.setOperatorApproval(accountId, operator, true);
    }

    // =====================================================================
    //                              helpers
    // =====================================================================



    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _resolveDay(uint24 d, bool win) internal {
        uint256 word = uint256(keccak256(abi.encodePacked("external_door_accounts", d)));
        word = win ? word | 1 : word & ~uint256(1);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, d);
    }

    function _fundFlip(address p, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame_g152734(p, amount);
    }

    function _fundWwxrp(address p, uint256 amount) internal {
        vm.prank(GAME);
        wwxrp.mintPrize(p, amount);
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _lane(uint24 day, uint32 id) internal view returns (uint256) {
        return CoinflipStorage.read(address(coinflip), id, day);
    }

    function _t(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _countFor(Vm.Log[] memory logs, address emitter, bytes32 topic, uint256 index, bytes32 value)
        internal pure returns (uint256 n)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != emitter || logs[i].topics.length <= index) continue;
            if (logs[i].topics[0] == topic && logs[i].topics[index] == value) ++n;
        }
    }

    function _registrations(Vm.Log[] memory logs) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) ++n;
        }
    }



    /// @dev Open the next level's Decimator window today: the window flag and the round's opened day.
    function _openWindow() internal returns (uint24 lvl) {
        lvl = game.currentLvl() + 1;
        bytes32 flagsSlot = bytes32(GameSlots.DECIMATOR_FLAGS);
        uint256 flags = uint256(vm.load(address(game), flagsSlot));
        vm.store(address(game), flagsSlot, bytes32(flags | (uint256(1) << (GameSlots.DECIMATOR_FLAGS_OFFSET * 8))));
        bytes32 roundSlot = keccak256(abi.encode(uint256(lvl), GameSlots.DEC_BATTLE_ROUNDS));
        uint256 round = uint256(vm.load(address(game), roundSlot));
        vm.store(address(game), roundSlot, bytes32(round | (uint256(game.currentDayView_g542950()) << OPENED_DAY_SHIFT)));
        require(game.decimatorActive(), "fixture: decimator window flag");
    }

    /// @dev The wallet's Decimator entry at `lvl`: the entry word's owner ID (bits 0..31).
    function _entryOwner(uint32 id, uint24 lvl) internal view returns (uint32) {
        uint256 latest = uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.DEC_BATTLE_PLAYERS)));
        if (uint24(latest >> 64) != lvl) return 0;
        uint256 p = uint64(latest) - 1;
        bytes32 entrySlot = keccak256(abi.encode(p >> 1, GameSlots.DEC_BATTLE_ENTRIES));
        return uint32(uint256(vm.load(address(game), entrySlot)) >> ((p & 1) * 128));
    }

    /// @dev Open the growth market on `round` (the key-0 route tuple placement and views read).
    function _openMarket(uint24 round) internal {
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0))
        );
    }

    function _side(address who, uint24 round) internal view returns (uint8 side) {
        (,,,, side,,,) = parimutuel.marketStateById(_fixtureId(who), round);
    }
    function _side(uint32 who, uint24 round) internal view returns (uint8 side) {
        (,,,, side,,,) = parimutuel.marketStateById(_fixtureId(who), round);
    }

    function _boonSlot1(uint32 id) internal pure returns (bytes32) {
        return bytes32(uint256(GameSlotKeys.byId(id, GameSlots.BOON_PACKED)) + 1);
    }

    /// @dev A live, non-deity WWXRP lane of `tier` stamped today for wallet `id`.
    function _seedWwxrpLane(uint32 id, uint256 tier) internal {
        bytes32 s = _boonSlot1(id);
        uint256 v = uint256(vm.load(address(game), s));
        uint256 lane = tier | (uint256(game.currentDayView_g542950()) << 3);
        vm.store(address(game), s, bytes32((v & ~(uint256(0xFFFFFF) << WWXRP_LANE_SHIFT)) | (lane << WWXRP_LANE_SHIFT)));
    }

    function _wwxrpTier(uint32 id) internal view returns (uint256) {
        return (uint256(vm.load(address(game), _boonSlot1(id))) >> WWXRP_LANE_SHIFT) & 3;
    }

    // =====================================================================
    //                       9. FLIP decimatorBurn
    // =====================================================================

    /// @notice P's burn for A burns A's FLIP; the quest, boon, activity score, Game entry and event
    ///         are A's; no wallet registers.
    function test_DecimatorBurn_OperatorForAccount_AccountPays_StateOnAccount() public {
        _fundFlip(account, 10_000);
        uint24 lvl = _openWindow();

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, operator)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (accountId, BURN)), 1);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.playerActivityScoreCachedById_g975, (accountId)), 1);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.consumeDecimatorBoon, (accountId)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.recordDecBurn_g1271.selector, accountId, lvl), 1);
        vm.recordLogs();
        vm.prank(operator);
        coin.decimatorBurn(accountId, BURN, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coin.balanceOf(account), 10_000 - BURN, "the payee's FLIP burned");
        assertEq(coin.balanceOf(operator), 0, "the operator paid nothing");
        assertEq(_countFor(logs, address(coin), DECIMATOR_BURN, 1, bytes32(uint256(accountId))), 1, "DecimatorBurn names A's ID");
        assertEq(_registrations(logs), 0, "no registration");
        assertEq(_entryOwner(accountId, lvl), accountId, "the Game entry is A's");
        assertEq(_entryOwner(operatorId, lvl), 0, "no entry for P");
    }

    /// @notice When A's wallet is short, A's settled coinflip winnings cover the rest; the
    ///         operator's never do.
    function test_DecimatorBurn_ShortWallet_UsesAccountCoinflipNotOperators() public {
        uint24 d = _today();
        vm.startPrank(GAME);
        coinflip.creditFlip_g317(accountId, 5_000);
        coinflip.creditFlip_g317(operatorId, 5_000);
        vm.stopPrank();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        uint256 accountPending = coinflip.previewClaimCoinflipsById(_fixtureId(account));
        uint256 operatorPending = coinflip.previewClaimCoinflipsById(_fixtureId(operator));
        assertGt(accountPending, BURN);
        assertGt(operatorPending, 0);
        _fundFlip(account, 500);
        _openWindow();

        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.consumeCoinflipsForBurn.selector, account), 1);
        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.consumeCoinflipsForBurn.selector, operator), 0);
        vm.prank(operator);
        coin.decimatorBurn(accountId, BURN, 0);

        assertEq(coin.balanceOf(account), 0, "A's wallet spent first");
        assertEq(coinflip.previewClaimCoinflipsById(_fixtureId(account)), accountPending - (BURN - 500), "A's winnings covered the rest");
        assertEq(coinflip.previewClaimCoinflipsById(_fixtureId(operator)), operatorPending, "P's winnings untouched");
    }

    /// @notice X reverts NotApproved and an unallocated ID reverts E (both before any burn); the
    ///         key's explicit-ID burn spends its own FLIP; a self burn makes no resolveAccount call
    ///         and registers as before.
    function test_DecimatorBurn_StrangerNotApproved_UnallocatedE_Operator_Self() public {
        _fundFlip(stranger, 10_000);
        _fundFlip(account, 10_000);
        uint24 lvl = _openWindow();
        vm.expectRevert(FLIP.NotApproved.selector);
        vm.prank(stranger);
        coin.decimatorBurn(accountId, BURN, 0);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        coin.decimatorBurn(uint32(_walletCount()), BURN, 0);
        assertEq(coin.balanceOf(stranger), 10_000);

        vm.prank(operator);
        coin.decimatorBurn(accountId, BURN, 0);
        assertEq(coin.balanceOf(account), 10_000 - BURN, "P's burn for A spent A's FLIP");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_entryOwner(accountId, lvl), accountId);

        vm.prank(account);
        coin.decimatorBurn(accountId, BURN, 0);
        assertEq(coin.balanceOf(account), 10_000 - 2 * BURN, "the key's explicit-ID burn spent its own FLIP");

        address p = makeAddr("xda_self_burner");
        _fundFlip(p, 10_000);
        uint32 expected = uint32(_walletCount());
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.resolveAccount_g7029.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.registerWallet_g9539, (p, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (expected, BURN)), 1);
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);
        assertEq(game.walletIdOf_g3120(p), expected);
        assertEq(_entryOwner(expected, lvl), expected);
    }

    // =====================================================================
    //                        10. Parimutuel placeBet
    // =====================================================================

    function _buyTicket(address who) internal {
        (,,,, uint256 price) = game.purchaseInfo_g1027();
        vm.deal(who, price);
        vm.prank(who);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @notice P's bet for A burns A's STAKE and records the bet on A (eligible by its ticket, real
    ///         gate); P can bet its own account the same round; a second bet for A reverts
    ///         AlreadyBet; X reverts NotApproved. Settlement credits A's lane.
    function test_PlaceBet_OperatorForAccount_RecordedOnAccount_SettlementCreditsAccount() public {
        _buyTicket(account);
        _buyTicket(operator);
        _openMarket(1);
        _fundFlip(account, 10_000);
        _fundFlip(operator, 10_000);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, operator)), 2);
        // The bet and P's refused repeat below: the gate read precedes the AlreadyBet check.
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.marketBetGates, (accountId, uint24(1))), 2);
        vm.recordLogs();
        vm.prank(operator);
        parimutuel.placeBet(accountId, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coin.balanceOf(account), 10_000 - STAKE, "A's STAKE burned");
        assertEq(coin.balanceOf(operator), 10_000, "P's FLIP untouched");
        assertEq(_countFor(logs, address(parimutuel), BET_PLACED, 1, bytes32(uint256(accountId))), 1, "BetPlaced(A)");
        assertEq(_side(accountId, 1), 1, "A holds the OVER bet");
        assertEq(_side(operator, 1), 0, "P has no bet yet");

        vm.prank(operator);
        parimutuel.placeBet(0, false);
        assertEq(_side(operator, 1), 2, "P bets its own account the same round");
        assertEq(coin.balanceOf(operator), 10_000 - STAKE);

        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        vm.prank(operator);
        parimutuel.placeBet(accountId, true);
        _fundFlip(stranger, 10_000);
        vm.expectRevert(DegenerusParimutuel.NotApproved.selector);
        vm.prank(stranger);
        parimutuel.placeBet(accountId, true);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        parimutuel.placeBet(uint32(_walletCount()), true);

        uint24 target = _today() + 1;
        uint256 accountLane = _lane(target, accountId);
        uint256 operatorLane = _lane(target, operatorId);
        vm.startPrank(GAME);
        parimutuel.recordGrowth(1, true);
        parimutuel.runGrowthWork(MineFlipGas.budget(8_500_000, 10_000, true));
        vm.stopPrank();
        assertGt(_lane(target, accountId), accountLane, "the OVER win credits A's stake lane");
        assertEq(_lane(target, operatorId), operatorLane, "P's losing UNDER bet pays nothing");
    }

    /// @notice P's bet for A burns A's FLIP and A's second bet through its own ID reverts
    ///         AlreadyBet; P's self bet makes no resolveAccount call.
    function test_PlaceBet_OperatorForAccount_BurnsAccount_SelfNoResolve() public {
        _buyTicket(account);
        _openMarket(1);
        _fundFlip(account, 10_000);
        vm.prank(operator);
        parimutuel.placeBet(accountId, false);
        assertEq(coin.balanceOf(account), 10_000 - STAKE, "P's bet for A spent A's FLIP");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_side(accountId, 1), 2);
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        vm.prank(account);
        parimutuel.placeBet(accountId, true);

        _buyTicket(operator);
        _fundFlip(operator, 10_000);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.resolveAccount_g7029.selector), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.marketBetGates, (operatorId, uint24(1))), 1);
        vm.prank(operator);
        parimutuel.placeBet(0, true);
        assertEq(_side(operator, 1), 1, "self bet recorded on P");
        assertEq(coin.balanceOf(operator), 10_000 - STAKE);
        assertEq(coin.balanceOf(account), 10_000 - STAKE, "A untouched by P's own bet");
    }

    // =====================================================================
    //                            11. WWXRP enter
    // =====================================================================

    /// @notice P's entry for A burns A's WWXRP; the entry, bucket, score and boon are A's; the
    ///         event names A's ID; no wallet registers.
    function test_Enter_OperatorForAccount_EntryAndBoonOnAccount() public {
        _fundWwxrp(account, 1_000);
        _seedWwxrpLane(accountId, 1);
        uint256 wallets = _walletCount();
        uint24 day = _today();

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, operator)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.playerActivityScoreCachedById_g975, (accountId)), 1);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.consumeCoinflipBoon_g2902, (accountId)), 1);
        vm.recordLogs();
        vm.prank(operator);
        wwxrp.enterDraw(accountId, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(wwxrp.balanceOf(account), 900, "A's WWXRP burned");
        uint8 bucket = wwxrp.bucketOf(day, accountId);
        (uint32 eid, uint256 cum) = wwxrp.entryAt(day, bucket, 0);
        assertEq(eid, accountId, "the entry is A's");
        assertGt(cum, 0);
        assertEq(_wwxrpTier(accountId), 0, "A's WWXRP boon spent");
        assertEq(_walletCount(), wallets, "no new ID");
        assertEq(_registrations(logs), 0);
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != DRAW_ENTERED) continue;
            assertEq(uint32(uint256(logs[i].topics[2])), accountId, "DrawEntered names A's ID");
            (uint8 evBucket,,,,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256));
            assertEq(evBucket, bucket);
            seen = true;
        }
        assertTrue(seen);
    }

    /// @notice At level x99 P's entry for A also enters the century incinerator as A.
    function test_Enter_X99Incinerator_CarriesAccount() public {
        _fundWwxrp(account, 1_000);
        vm.mockCall(address(game), abi.encodeWithSignature("currentLvl()"), abi.encode(uint24(199)));
        vm.recordLogs();
        vm.prank(operator);
        wwxrp.enterDraw(accountId, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint32 e,) = wwxrp.incineratorEntryAt(200, 0);
        assertEq(e, accountId, "the incinerator entry carries A");
        assertEq(_countFor(logs, address(wwxrp), INCIN_ENTERED, 2, bytes32(uint256(accountId))), 1, "IncineratorEntered names A's ID");
        assertEq(wwxrp.balanceOf(account), 900);
    }

    /// @notice X reverts NotApproved, an unallocated ID reverts E; P's entry for A burns A's WWXRP;
    ///         a self entry makes no resolveAccount call.
    function test_Enter_StrangerNotApproved_UnallocatedE_Operator_SelfNoResolve() public {
        _fundWwxrp(stranger, 1_000);
        _fundWwxrp(account, 1_000);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        vm.prank(stranger);
        wwxrp.enterDraw(accountId, 100);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        wwxrp.enterDraw(uint32(_walletCount()), 100);
        assertEq(wwxrp.balanceOf(stranger), 1_000);

        vm.prank(operator);
        wwxrp.enterDraw(accountId, 100);
        assertEq(wwxrp.balanceOf(account), 900, "P's entry for A burned A's WWXRP");
        assertEq(wwxrp.balanceOf(operator), 0);

        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.resolveAccount_g7029.selector), 0);
        vm.prank(stranger);
        wwxrp.enterDraw(0, 100);
        assertEq(wwxrp.balanceOf(stranger), 900);
        uint32 sid = game.walletIdOf_g3120(stranger);
        assertTrue(sid != 0, "a self entrant registers");
        uint8 bucket = wwxrp.bucketOf(_today(), sid);
        (,, uint32 count) = wwxrp.bucketInfo(_today(), bucket);
        (uint32 eid,) = wwxrp.entryAt(_today(), bucket, count - 1);
        assertEq(eid, sid);
    }

    // =====================================================================
    //                   12. Jackpots claimBafConsolation
    // =====================================================================

    /// @notice Anyone may claim A's consolation: the WWXRP mints to A's payee, the event names A's
    ///         ID and A's score is consumed.
    function test_ClaimBafConsolation_AnyoneForAccount_PaysAccount() public {
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(accountId, 10, 5_000);
        vm.prank(GAME);
        jackpots.markBafSkippedAt(10, uint24(uint256(vm.load(address(game), bytes32(0))) >> 24));
        assertEq(jackpots.bafConsolationOfId(accountId, 10), 5);
        uint256 before = wwxrp.claimable(accountId);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, stranger)), 0);
        vm.expectEmit(true, true, false, true, address(jackpots));
        emit BafConsolationClaimed(accountId, 10, 5_000, 5);
        vm.prank(stranger);
        jackpots.claimBafConsolation(accountId, 10);

        assertEq(wwxrp.claimable(accountId) - before, 5, "minted to A's payee");
        assertEq(wwxrp.balanceOf(stranger), 0, "nothing to the caller");
        assertEq(jackpots.bafConsolationOfId(accountId, 10), 0, "A's score consumed");
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(account);
        jackpots.claimBafConsolation(accountId, 10);
    }

    /// @notice `id == 0` is the caller (Game `walletIdOf`, no resolveAccount); a caller with no ID
    ///         holds nothing; an unallocated ID reverts E once the bracket is skipped.
    function test_ClaimBafConsolation_ZeroIsCaller_NoIdNothing_UnallocatedE() public {
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(accountId, 10, 3_000);
        vm.prank(GAME);
        jackpots.markBafSkippedAt(10, uint24(uint256(vm.load(address(game), bytes32(0))) >> 24));
        uint256 before = wwxrp.claimable(accountId);
        uint32 unallocated = uint32(_walletCount());

        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(stranger);
        jackpots.claimBafConsolation(0, 10);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(stranger);
        jackpots.claimBafConsolation(unallocated, 20);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(stranger);
        jackpots.claimBafConsolation(unallocated, 10);

        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.resolveAccount_g7029.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.walletIdOf_g3120, (account)), 1);
        vm.prank(account);
        jackpots.claimBafConsolation(0, 10);
        assertEq(wwxrp.claimable(accountId) - before, 3, "self claim paid the caller");
    }
}
