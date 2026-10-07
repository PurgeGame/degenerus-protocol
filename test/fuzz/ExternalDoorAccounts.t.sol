// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title ExternalDoorAccounts -- FLIP decimatorBurn, Parimutuel placeBet, WWXRP enter and Jackpots
///        claimBafConsolation acting for an account by wallet ID
/// @notice O owns smurf S; P is an operator O approved for S; X is a stranger. The authorized doors
///         (decimatorBurn, placeBet, enter) revert `NotApproved` for X and Game `E` for an unallocated
///         ID; state follows the account (S's ID and key), wallet-token burns come from O (the payee).
///         The permissionless consolation claim takes any caller and pays the score owner's payee.
///         Self paths make no Game `resolveAccount` call; an ID-addressed action makes exactly one,
///         and a smurf action never registers a wallet. S's key never holds FLIP, WWXRP or ETH.
contract ExternalDoorAccountsTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant DECIMATOR_BURN = keccak256("DecimatorBurn(uint32,uint256,uint64)");
    bytes32 internal constant BET_PLACED = keccak256("BetPlaced(uint32,uint24,bool,uint256)");
    bytes32 internal constant DRAW_ENTERED =
        keccak256("DrawEntered(uint24,uint32,uint8,uint32,uint256,uint256,uint256)");
    bytes32 internal constant INCIN_ENTERED =
        keccak256("IncineratorEntered(uint24,uint32,uint32,uint256,uint256,uint256)");
    bytes4 internal constant GROWTH_STATE = bytes4(keccak256("growthState(uint24)"));

    uint256 internal constant BURN = 2_000;
    uint256 internal constant STAKE = 1_000;
    /// @dev DecBattleRound.openedDay sits after poolWei (96) + count (40) + totalCreditedStack (64).
    uint256 internal constant OPENED_DAY_SHIFT = 200;
    uint256 internal constant WWXRP_LANE_SHIFT = 232;

    event BafConsolationClaimed(uint32 indexed player, uint24 indexed lvl, uint256 score, uint256 wwxrpAmount);

    address internal owner;
    uint32 internal ownerId;
    uint32 internal smurfId;
    address internal stranger;
    address internal operator;

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("xda_owner");
        ownerId = _giveWalletId(owner);
        (smurfId,) = _createSmurf(owner);
        stranger = makeAddr("xda_stranger");
        operator = makeAddr("xda_operator");
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
    }

    // =====================================================================
    //                              helpers
    // =====================================================================



    function _createSmurf(address o) internal returns (uint32 sid, uint32 skey) {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(o, price);
        vm.prank(o);
        sid = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        skey = sid;
        (address key, address payee, bool authorized) = game.resolveAccount(sid, o);
        require(key == address(0) && payee == o && authorized, "fixture: smurf key, payee, owner authority");
        vm.deal(o, 0);
    }

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
        coin.mintForGame(p, amount);
    }

    function _fundWwxrp(address p, uint256 amount) internal {
        vm.prank(GAME);
        wwxrp.mintPrize(p, amount);
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _lane(uint24 day, uint32 id) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(day >> 3), uint256(0)))));
        return uint32(uint256(vm.load(address(coinflip), slot)) >> ((uint256(day) & 7) * 32));
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
        lvl = game.level() + 1;
        bytes32 flagsSlot = bytes32(GameSlots.DECIMATOR_FLAGS);
        uint256 flags = uint256(vm.load(address(game), flagsSlot));
        vm.store(address(game), flagsSlot, bytes32(flags | (uint256(1) << (GameSlots.DECIMATOR_FLAGS_OFFSET * 8))));
        bytes32 roundSlot = keccak256(abi.encode(uint256(lvl), GameSlots.DEC_BATTLE_ROUNDS));
        uint256 round = uint256(vm.load(address(game), roundSlot));
        vm.store(address(game), roundSlot, bytes32(round | (uint256(game.currentDayView()) << OPENED_DAY_SHIFT)));
        require(game.decWindow(), "fixture: decimator window flag");
    }

    /// @dev The wallet's Decimator entry at `lvl`: the entry word's owner ID (bits 0..31).
    function _entryOwner(uint32 id, uint24 lvl) internal view returns (uint32) {
        uint256 latest = uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.DEC_BATTLE_PLAYERS)));
        if (uint24(latest >> 64) != lvl) return 0;
        uint256 p = uint64(latest) - 1;
        bytes32 entrySlot = keccak256(abi.encode((uint256(lvl) << 64) | (p >> 1), GameSlots.DEC_BATTLE_ENTRIES));
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
        uint256 lane = tier | (uint256(game.currentDayView()) << 3);
        vm.store(address(game), s, bytes32((v & ~(uint256(0xFFFFFF) << WWXRP_LANE_SHIFT)) | (lane << WWXRP_LANE_SHIFT)));
    }

    function _wwxrpTier(uint32 id) internal view returns (uint256) {
        return (uint256(vm.load(address(game), _boonSlot1(id))) >> WWXRP_LANE_SHIFT) & 3;
    }

    // =====================================================================
    //                       9. FLIP decimatorBurn
    // =====================================================================

    /// @notice O's burn for S burns O's FLIP; the quest, boon, activity score, Game entry and event
    ///         are S's; no wallet registers.
    function test_DecimatorBurn_OwnerForSmurf_OwnerPays_StateOnSmurf() public {
        _fundFlip(owner, 10_000);
        uint24 lvl = _openWindow();

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, owner)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (smurfId, BURN)), 1);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.playerActivityScoreCachedById, (smurfId)), 1);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.consumeDecimatorBoon, (smurfId)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector, smurfId, lvl), 1);
        vm.recordLogs();
        vm.prank(owner);
        coin.decimatorBurn(smurfId, BURN, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coin.balanceOf(owner), 10_000 - BURN, "the payee's FLIP burned");
        assertEq(_countFor(logs, address(coin), DECIMATOR_BURN, 1, bytes32(uint256(smurfId))), 1, "DecimatorBurn names S's key");
        assertEq(_registrations(logs), 0, "no registration");
        assertEq(_entryOwner(smurfId, lvl), smurfId, "the Game entry is S's");
        assertEq(_entryOwner(ownerId, lvl), 0, "no entry for O");
    }

    /// @notice When O's wallet is short, O's settled coinflip winnings cover the rest; S's never do.
    function test_DecimatorBurn_ShortWallet_UsesOwnerCoinflipNotSmurfs() public {
        uint24 d = _today();
        vm.startPrank(GAME);
        coinflip.creditFlip(ownerId, 5_000);
        coinflip.creditFlip(smurfId, 5_000);
        vm.stopPrank();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        uint256 ownerPending = coinflip.previewClaimCoinflipsById(_fixtureId(owner));
        uint256 smurfPending = coinflip.previewClaimCoinflipsById(_fixtureId(smurfId));
        assertGt(ownerPending, BURN);
        assertGt(smurfPending, 0);
        _fundFlip(owner, 500);
        _openWindow();

        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.consumeCoinflipsForBurn.selector, owner), 1);
        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.consumeCoinflipsForBurn.selector, smurfId), 0);
        vm.prank(owner);
        coin.decimatorBurn(smurfId, BURN, 0);

        assertEq(coin.balanceOf(owner), 0, "O's wallet spent first");
        assertEq(coinflip.previewClaimCoinflipsById(_fixtureId(owner)), ownerPending - (BURN - 500), "O's winnings covered the rest");
        assertEq(coinflip.previewClaimCoinflipsById(_fixtureId(smurfId)), smurfPending, "S's winnings untouched");
    }

    /// @notice X reverts NotApproved and an unallocated ID reverts E (both before any burn); P's burn
    ///         for S burns O's FLIP; a self burn makes no resolveAccount call and registers as before.
    function test_DecimatorBurn_StrangerNotApproved_UnallocatedE_Operator_Self() public {
        _fundFlip(stranger, 10_000);
        _fundFlip(owner, 10_000);
        uint24 lvl = _openWindow();
        vm.expectRevert(FLIP.NotApproved.selector);
        vm.prank(stranger);
        coin.decimatorBurn(smurfId, BURN, 0);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        coin.decimatorBurn(uint32(_walletCount()), BURN, 0);
        assertEq(coin.balanceOf(stranger), 10_000);

        vm.prank(operator);
        coin.decimatorBurn(smurfId, BURN, 0);
        assertEq(coin.balanceOf(owner), 10_000 - BURN, "P's burn for S spent O's FLIP");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_entryOwner(smurfId, lvl), smurfId);

        address p = makeAddr("xda_self_burner");
        _fundFlip(p, 10_000);
        uint32 expected = uint32(_walletCount());
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.resolveAccount.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (expected, BURN)), 1);
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);
        assertEq(game.walletIdOf(p), expected);
        assertEq(_entryOwner(expected, lvl), expected);
    }

    // =====================================================================
    //                        10. Parimutuel placeBet
    // =====================================================================

    /// @notice O's bet for S burns O's STAKE and records the bet on S (eligible by its creation
    ///         ticket, real gate); O can bet its own account the same round; a second bet for S
    ///         reverts AlreadyBet; X reverts NotApproved. Settlement credits S's lane.
    function test_PlaceBet_OwnerForSmurf_RecordedOnSmurf_SettlementCreditsSmurf() public {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(owner, price);
        vm.prank(owner);
        game.purchase{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        _openMarket(1);
        _fundFlip(owner, 10_000);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, owner)), 1);
        // The bet and P's refused repeat below: the gate read precedes the AlreadyBet check.
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.marketBetGates, (smurfId, uint24(1))), 2);
        vm.recordLogs();
        vm.prank(owner);
        parimutuel.placeBet(smurfId, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coin.balanceOf(owner), 10_000 - STAKE, "O's STAKE burned");
        assertEq(_countFor(logs, address(parimutuel), BET_PLACED, 1, bytes32(uint256(smurfId))), 1, "BetPlaced(S)");
        assertEq(_side(smurfId, 1), 1, "S holds the OVER bet");
        assertEq(_side(owner, 1), 0, "O has no bet yet");

        vm.prank(owner);
        parimutuel.placeBet(0, false);
        assertEq(_side(owner, 1), 2, "O bets its own account the same round");
        assertEq(coin.balanceOf(owner), 10_000 - 2 * STAKE);

        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        vm.prank(operator);
        parimutuel.placeBet(smurfId, true);
        _fundFlip(stranger, 10_000);
        vm.expectRevert(DegenerusParimutuel.NotApproved.selector);
        vm.prank(stranger);
        parimutuel.placeBet(smurfId, true);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        parimutuel.placeBet(uint32(_walletCount()), true);

        uint24 target = _today() + 1;
        uint256 smurfLane = _lane(target, smurfId);
        uint256 ownerLane = _lane(target, ownerId);
        vm.startPrank(GAME);
        parimutuel.recordGrowth(1, true);
        parimutuel.settleGrowth(16);
        vm.stopPrank();
        assertGt(_lane(target, smurfId), smurfLane, "the OVER win credits S's stake lane");
        assertEq(_lane(target, ownerId), ownerLane, "O's losing UNDER bet pays nothing");
    }

    /// @notice P's bet for S burns O's FLIP and O's second bet for S reverts AlreadyBet; O's self
    ///         bet makes no resolveAccount call.
    function test_PlaceBet_OperatorForSmurf_BurnsOwner_SelfNoResolve() public {
        _openMarket(1);
        _fundFlip(owner, 10_000);
        vm.prank(operator);
        parimutuel.placeBet(smurfId, false);
        assertEq(coin.balanceOf(owner), 10_000 - STAKE, "P's bet for S spent O's FLIP");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_side(smurfId, 1), 2);
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        vm.prank(owner);
        parimutuel.placeBet(smurfId, true);

        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(owner, price);
        vm.prank(owner);
        game.purchase{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.resolveAccount.selector), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.marketBetGates, (ownerId, uint24(1))), 1);
        vm.prank(owner);
        parimutuel.placeBet(0, true);
        assertEq(_side(owner, 1), 1, "self bet recorded on O");
        assertEq(coin.balanceOf(owner), 10_000 - 2 * STAKE);
    }

    // =====================================================================
    //                            11. WWXRP enter
    // =====================================================================

    /// @notice O's entry for S burns O's WWXRP; the entry, bucket, score and boon are S's; the event
    ///         names S's key; no wallet registers.
    function test_Enter_OwnerForSmurf_EntryAndBoonOnSmurf() public {
        _fundWwxrp(owner, 1_000);
        _seedWwxrpLane(smurfId, 1);
        uint256 wallets = _walletCount();
        uint24 day = _today();

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, owner)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.playerActivityScoreCachedById, (smurfId)), 1);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (smurfId)), 1);
        vm.recordLogs();
        vm.prank(owner);
        wwxrp.enter(smurfId, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(wwxrp.balanceOf(owner), 900, "O's WWXRP burned");
        uint8 bucket = wwxrp.bucketOf(day, smurfId);
        (uint32 eid, uint256 cum) = wwxrp.entryAt(day, bucket, 0);
        assertEq(eid, smurfId, "the entry is S's");
        assertGt(cum, 0);
        assertEq(_wwxrpTier(smurfId), 0, "S's WWXRP boon spent");
        assertEq(_walletCount(), wallets, "no new ID");
        assertEq(_registrations(logs), 0);
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != DRAW_ENTERED) continue;
            assertEq(uint32(uint256(logs[i].topics[2])), smurfId, "DrawEntered names S's key");
            (uint8 evBucket,,,,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256));
            assertEq(evBucket, bucket);
            seen = true;
        }
        assertTrue(seen);
    }

    /// @notice At level x99 O's entry for S also enters the century incinerator as S.
    function test_Enter_X99Incinerator_CarriesSmurf() public {
        _fundWwxrp(owner, 1_000);
        vm.mockCall(address(game), abi.encodeWithSignature("level()"), abi.encode(uint24(199)));
        vm.recordLogs();
        vm.prank(owner);
        wwxrp.enter(smurfId, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint32 e,) = wwxrp.incineratorEntryAt(200, 0);
        assertEq(e, smurfId, "the incinerator entry carries S");
        assertEq(_countFor(logs, address(wwxrp), INCIN_ENTERED, 2, bytes32(uint256(smurfId))), 1, "IncineratorEntered names S's key");
        assertEq(wwxrp.balanceOf(owner), 900);
    }

    /// @notice X reverts NotApproved, an unallocated ID reverts E; P's entry for S burns O's WWXRP;
    ///         a self entry makes no resolveAccount call.
    function test_Enter_StrangerNotApproved_UnallocatedE_Operator_SelfNoResolve() public {
        _fundWwxrp(stranger, 1_000);
        _fundWwxrp(owner, 1_000);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        vm.prank(stranger);
        wwxrp.enter(smurfId, 100);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        wwxrp.enter(uint32(_walletCount()), 100);
        assertEq(wwxrp.balanceOf(stranger), 1_000);

        vm.prank(operator);
        wwxrp.enter(smurfId, 100);
        assertEq(wwxrp.balanceOf(owner), 900, "P's entry for S burned O's WWXRP");
        assertEq(wwxrp.balanceOf(operator), 0);

        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.resolveAccount.selector), 0);
        vm.prank(stranger);
        wwxrp.enter(0, 100);
        assertEq(wwxrp.balanceOf(stranger), 900);
        uint32 sid = game.walletIdOf(stranger);
        assertTrue(sid != 0, "a self entrant registers");
        uint8 bucket = wwxrp.bucketOf(_today(), sid);
        (,, uint32 count) = wwxrp.bucketInfo(_today(), bucket);
        (uint32 eid,) = wwxrp.entryAt(_today(), bucket, count - 1);
        assertEq(eid, sid);
    }

    // =====================================================================
    //                   12. Jackpots claimBafConsolation
    // =====================================================================

    /// @notice Anyone may claim S's consolation: the WWXRP mints to O, the event names S's key and
    ///         S's score is consumed.
    function test_ClaimBafConsolation_AnyoneForSmurf_PaysOwner() public {
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(smurfId, 10, 5_000);
        vm.prank(GAME);
        jackpots.markBafSkipped(10);
        assertEq(jackpots.bafConsolationOfId(smurfId, 10), 5);
        uint256 ownerBefore = wwxrp.claimable(smurfId);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, stranger)), 0);
        vm.expectEmit(true, true, false, true, address(jackpots));
        emit BafConsolationClaimed(smurfId, 10, 5_000, 5);
        vm.prank(stranger);
        jackpots.claimBafConsolation(smurfId, 10);

        assertEq(wwxrp.claimable(smurfId) - ownerBefore, 5, "minted to S's payee");
        assertEq(wwxrp.balanceOf(stranger), 0, "nothing to the caller");
        assertEq(jackpots.bafConsolationOfId(smurfId, 10), 0, "S's score consumed");
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        vm.prank(owner);
        jackpots.claimBafConsolation(smurfId, 10);
    }

    /// @notice `id == 0` is the caller (Game `walletIdOf`, no resolveAccount); a caller with no ID
    ///         holds nothing; an unallocated ID reverts E once the bracket is skipped.
    function test_ClaimBafConsolation_ZeroIsCaller_NoIdNothing_UnallocatedE() public {
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(ownerId, 10, 3_000);
        vm.prank(GAME);
        jackpots.markBafSkipped(10);
        uint256 before = wwxrp.claimable(ownerId);
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

        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.resolveAccount.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.walletIdOf, (owner)), 1);
        vm.prank(owner);
        jackpots.claimBafConsolation(0, 10);
        assertEq(wwxrp.claimable(ownerId) - before, 3, "self claim paid the caller");
    }
}
