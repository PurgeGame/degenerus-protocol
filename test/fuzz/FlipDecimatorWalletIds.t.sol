// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title FlipDecimatorWalletIds -- FLIP's Decimator and craps burns by wallet ID on the real protocol
/// @notice A Decimator burn pays, so FLIP registers the burner through the Game hook first (an
///         existing wallet, sDGNRS included, gets its ID back with no write and no event); the
///         quest, the boon and the Game entry all see that one ID; the activity score is read after
///         the quest, so a burn that completes a quest is weighted by the post-quest score. A craps
///         burn spends the craps boon lane of the ID the table passes and reports the action by it;
///         a comp burn touches neither.
contract FlipDecimatorWalletIdsTest is DeployProtocol {
    address private constant CRAPS = ContractAddresses.CRAPS;
    address private constant SDGNRS = ContractAddresses.SDGNRS;
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    uint256 private constant BURN = 2_000;
    /// @dev DecBattleRound.openedDay sits after poolWei (96) + count (40) + totalCreditedStack (64).
    uint256 private constant OPENED_DAY_SHIFT = 200;

    function setUp() public {
        _deployProtocol();
    }

    // =====================================================================
    //                              helpers
    // =====================================================================

    function _fundFlip(address p, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(p, amount);
    }

    function _gameId(address p) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), GameSlotKeys.walletId(p))));
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
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
        require(game.decWindow(), "harness: decimator window flag");
    }

    function _registrations(Vm.Log[] memory logs) internal view returns (uint256 n, uint32 lastId, address lastOwner) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != WALLET_REGISTERED) continue;
            ++n;
            lastId = uint32(uint256(logs[i].topics[1]));
            lastOwner = address(uint160(uint256(logs[i].topics[2])));
        }
    }

    /// @dev The wallet's Decimator entry at `lvl`: the entry word's owner ID (bits 0..31).
    function _entryOwner(uint32 id, uint24 lvl) internal view returns (uint32) {
        uint256 latest = uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.DEC_BATTLE_PLAYERS)));
        if (uint24(latest >> 64) != lvl) return 0;
        bytes32 entrySlot = keccak256(abi.encode((uint256(lvl) << 64) | uint64(latest), GameSlots.DEC_BATTLE_ENTRIES));
        return uint32(uint256(vm.load(address(game), entrySlot)));
    }

    /// @dev Stamp a live, non-deity craps lane (slot1 bits 0..23) of `tier` for wallet `id` today.
    function _seedCrapsLane(uint32 id, uint256 tier) internal {
        bytes32 s = bytes32(uint256(GameSlotKeys.byId(id, GameSlots.BOON_PACKED)) + 1);
        uint256 v = uint256(vm.load(address(game), s));
        uint256 lane = tier | (uint256(game.currentDayView()) << 3);
        vm.store(address(game), s, bytes32((v & ~uint256(0xFFFFFF)) | lane));
    }

    function _crapsTier(uint32 id) internal view returns (uint256) {
        (, uint256 slot1) = game.boonPacked(id);
        return slot1 & 3;
    }

    /// @dev Roll today's quests with slot 1 forced to the Decimator quest; returns today.
    function _rollDecimatorQuest() internal returns (uint24 today) {
        today = game.currentDayView();
        vm.prank(address(game));
        quests.rollDailyQuest(today, 1, false, false, true);
        QuestInfo[2] memory active = quests.getActiveQuests();
        assertEq(active[1].day, today, "fixture: today's quests rolled");
        assertEq(active[1].questType, 5, "fixture: slot 1 is the Decimator quest");
    }

    /// @dev The quest reward a `BURN`-sized Decimator burn completes for `id`, and `p`'s activity
    ///      score right after that quest call (state rolled back).
    function _previewQuestBurn(uint32 id, address p) internal returns (uint256 reward, uint256 postScore) {
        uint256 snap = vm.snapshotState();
        vm.prank(address(coin));
        bool completed;
        (reward,,, completed) = quests.handleDecimator(id, BURN);
        (postScore,) = game.playerActivityScore(p);
        assertTrue(vm.revertToState(snap));
        assertTrue(completed, "fixture: the burn completes the Decimator quest");
    }

    // ---- afking-run drive (as test/fuzz/QuestBoonAfkingStreakLoss.t.sol) ----

    uint256 private _t;
    uint256 private _lastFulfilledReqId;
    uint256 private _deliverNonce;

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_giveWalletId(who));
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, false, q, 0, seat);
    }

    /// @dev Deliver one funded day to the live sub set and open the pending box.
    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _settleGame(w ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(w);
        _settleGame(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    // =====================================================================
    //                           Decimator burns
    // =====================================================================

    /// @notice A burner with no ID registers exactly once, before the quest: the quest, the boon
    ///         and the Game entry all carry that ID.
    function test_UnregisteredBurner_RegistersOnce_BeforeQuestBoonAndEntry() public {
        address p = makeAddr("dec_new_burner");
        _fundFlip(p, 10_000);
        uint24 lvl = _openWindow();
        uint32 expectedId = uint32(_walletCount());
        assertEq(_gameId(p), 0);

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (expectedId, BURN)), 1);
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeDecimatorBoon, (expectedId)), 1);
        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector, expectedId, lvl), 1);
        vm.recordLogs();
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);

        (uint256 n, uint32 rid, address owner) = _registrations(vm.getRecordedLogs());
        assertEq(n, 1, "exactly one WalletRegistered");
        assertEq(rid, expectedId);
        assertEq(owner, p);
        assertEq(_entryOwner(expectedId, lvl), expectedId, "the Game entry is keyed by the same ID");
        assertEq(coin.balanceOf(p), 10_000 - BURN);
    }

    /// @notice For an existing wallet the hook is a read: it returns the ID with no Game write and
    ///         no event, and the burn's quest runs under that ID.
    function test_RegisteredBurner_RegistrationIsWriteFree() public {
        address p = makeAddr("dec_existing_burner");
        uint32 id = _giveWalletId(p);
        _fundFlip(p, 10_000);
        uint24 lvl = _openWindow();

        vm.recordLogs();
        vm.record();
        vm.prank(address(coin));
        uint32 got = game.registerWallet(p, true);
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(got, id);
        assertEq(writes.length, 0, "no Game write for an existing wallet");
        (uint256 n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0);

        uint256 walletsBefore = _walletCount();
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (id, BURN)), 1);
        vm.recordLogs();
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);
        (n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0, "no event on the burn either");
        assertEq(_walletCount(), walletsBefore);
        assertEq(_gameId(p), id);
        assertEq(_entryOwner(id, lvl), id);
    }

    /// @notice Off an afking run a same-day completion leaves the reward streak at its start-of-day
    ///         snapshot, so the multiplier is the burner's score either way; the quest reward joins the
    ///         burn's base and is itself credited to the burner's ID.
    function test_QuestCompletingBurn_OffRun_RewardJoinsBaseCreditedById() public {
        address p = makeAddr("dec_quester");
        uint32 id = _giveWalletId(p);
        _fundFlip(p, 10_000);
        // The deploy day's quests are already rolled; take the next day's fresh roll.
        vm.warp(block.timestamp + 1 days);
        uint24 lvl = _openWindow();
        _rollDecimatorQuest();
        uint256 price = game.mintPrice();
        vm.prank(address(game));
        (,,, bool primaryDone,) = quests.handlePurchase(id, 1 ether, 0, 0, price, price);
        assertTrue(primaryDone, "fixture: the primary quest completes first (unlocks slot 1)");

        (uint256 reward, uint256 postScore) = _previewQuestBurn(id, p);
        vm.expectCall(
            address(game),
            abi.encodeCall(
                DegenerusGame.recordDecBurn,
                (id, lvl, BURN + reward, ActivityCurveLib.decBattleMultBps(postScore), uint32(0))
            ),
            1
        );
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);
        assertEq(coinflip.coinflipAmount(p), reward, "quest reward credited by ID");
    }

    /// @notice A burn that completes the Decimator quest during a live afking run is weighted by the
    ///         post-quest activity score: the in-run secondary raises the run's streak base at once,
    ///         and recordDecBurn receives the multiplier of the score read after handleDecimator,
    ///         which differs from the pre-quest one.
    function test_QuestCompletingBurn_AfkingRun_UsesPostQuestActivityScore() public {
        address p = makeAddr("dec_afking_quester");
        uint32 id = _giveWalletId(p);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(0xD3C1);
        (, bool afking) = quests.effectiveBaseStreakAndAfking(id);
        assertTrue(afking, "fixture: mid afking run");

        // A fresh quest day whose slot 1 is the Decimator quest (an afker's slot 1 is never locked).
        _t += 1 days;
        vm.warp(_t);
        uint24 lvl = _openWindow();
        uint24 today = _rollDecimatorQuest();
        _fundFlip(p, 10_000);

        (uint256 preScore,) = game.playerActivityScore(p);
        (uint256 reward, uint256 postScore) = _previewQuestBurn(id, p);
        if (ActivityCurveLib.decBattleMultBps(postScore) == ActivityCurveLib.decBattleMultBps(preScore)) {
            // The score counts streak / 2: flip the run streak's parity (an activity-boon +1, routed
            // into the run's base) so the secondary's +1 moves the score.
            vm.prank(address(game));
            quests.awardQuestStreakBonus(id, 1, today);
            (preScore,) = game.playerActivityScore(p);
            (reward, postScore) = _previewQuestBurn(id, p);
        }
        assertGt(postScore, preScore, "fixture: the in-run completion raises the score");
        uint256 postMult = ActivityCurveLib.decBattleMultBps(postScore);
        assertTrue(postMult != ActivityCurveLib.decBattleMultBps(preScore), "fixture: the multiplier moves");

        vm.expectCall(
            address(game),
            abi.encodeCall(DegenerusGame.recordDecBurn, (id, lvl, BURN + reward, postMult, uint32(0))),
            1
        );
        vm.prank(p);
        coin.decimatorBurn(0, BURN, 0);
    }

    /// @notice Past PAID_ADMISSION_WALLETS a new burner reverts (the burn rolls back); an existing
    ///         wallet still burns.
    function test_PastPaidAdmission_NewBurnerReverts_ExistingBurns() public {
        address e = makeAddr("dec_adm_existing");
        address n = makeAddr("dec_adm_new");
        uint32 eid = _giveWalletId(e);
        _fundFlip(e, 10_000);
        _fundFlip(n, 10_000);
        uint24 lvl = _openWindow();
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(uint256(3_000_000_001)));

        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(n);
        coin.decimatorBurn(0, BURN, 0);
        assertEq(coin.balanceOf(n), 10_000);
        assertEq(_gameId(n), 0);

        vm.prank(e);
        coin.decimatorBurn(0, BURN, 0);
        assertEq(_entryOwner(eid, lvl), eid);
    }

    /// @notice The advance-path `autoDecimatorBurn` gets sDGNRS's constant ID 2 back from the hook
    ///         (no write, no event) and runs the quest, boon and entry under it.
    function test_AutoDecimatorBurn_GetsSdgnrsIdWithoutWrite() public {
        vm.recordLogs();
        vm.record();
        vm.prank(address(coin));
        uint32 sid = game.registerWallet(SDGNRS, true);
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(sid, 2);
        assertEq(writes.length, 0, "the hook writes nothing for sDGNRS");
        (uint256 n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0);

        // Settled sDGNRS backing: claimableStored (slot A low 128 bits).
        bytes32 stateSlot = keccak256(abi.encode(uint32(2), uint256(2)));
        uint256 packed = uint256(vm.load(address(coinflip), stateSlot));
        vm.store(address(coinflip), stateSlot, bytes32((packed & ~uint256(type(uint128).max)) | 50_000));
        uint24 lvl = _openWindow();
        uint256 walletsBefore = _walletCount();

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.registerWallet, (SDGNRS, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleDecimator, (uint32(2), 8_000)), 1);
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeDecimatorBoon, (uint32(2))), 1);
        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.recordDecBurn.selector, uint32(2), lvl), 1);
        vm.recordLogs();
        vm.prank(address(game));
        uint256 spent = coin.autoDecimatorBurn(lvl, 8_000);
        assertEq(spent, 8_000);
        (n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0);
        assertEq(_walletCount(), walletsBefore);
        assertEq(_entryOwner(2, lvl), 2, "entry keyed by sDGNRS's ID");
    }

    // =====================================================================
    //                             craps burns
    // =====================================================================

    /// @notice A paid craps burn spends the craps lane of the passed ID (another ID's lane is
    ///         untouched) and reports the action to Quests by that ID; the spent lane pays nothing
    ///         on the next burn.
    function test_CrapsBurn_ConsumesIdLane_RecordsActionById() public {
        address p = makeAddr("craps_player");
        address q = makeAddr("craps_bystander");
        uint32 pid = _giveWalletId(p);
        uint32 qid = _giveWalletId(q);
        _fundFlip(p, 10_000);
        _seedCrapsLane(pid, 1);
        _seedCrapsLane(qid, 2);
        uint256 grossAndFlags = (uint256(500) << 8) | 0x1;

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (pid)), 2);
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (qid)), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.recordCrapsAction, (pid, uint8(1))), 2);
        vm.prank(CRAPS);
        uint8 mask = coin.burnCoinForCraps(p, pid, grossAndFlags);
        assertEq(mask, 1, "tier-1 craps boon -> one-hot mask 1");
        assertEq(coin.balanceOf(p), 9_500, "the full gross burns");
        assertEq(_crapsTier(pid), 0, "the passed ID's lane is spent");
        assertEq(_crapsTier(qid), 2, "another ID's lane is untouched");

        vm.prank(CRAPS);
        assertEq(coin.burnCoinForCraps(p, pid, grossAndFlags), 0, "a spent lane pays nothing");
        assertEq(coin.balanceOf(p), 9_000);
    }

    /// @notice A comp burn (vault-funded) consumes no boon and records no quest action.
    function test_CrapsCompBurn_TouchesNeitherBoonNorQuests() public {
        address p = makeAddr("craps_comp_player");
        uint32 pid = _giveWalletId(p);
        _fundFlip(p, 10_000);
        _seedCrapsLane(pid, 1);
        vm.prank(CRAPS);
        coin.creditCrapsComps(1_000);
        uint256 lane = coin.crapsCompAllowance();

        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.consumeCoinflipBoon.selector), 0);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.recordCrapsAction.selector), 0);
        vm.prank(CRAPS);
        uint8 mask = coin.burnCoinForCraps(p, pid, (uint256(500) << 8) | 0x10 | 0x1);
        assertEq(mask, 0);
        assertEq(coin.crapsCompAllowance(), lane - 500, "the comp lane pays");
        assertEq(coin.balanceOf(p), 10_000, "no wallet FLIP burned");
        assertEq(_crapsTier(pid), 1, "boon lane untouched");
    }
}
