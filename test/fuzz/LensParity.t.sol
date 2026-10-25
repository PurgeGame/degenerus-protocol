// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameFacade} from "../../contracts/modules/GameFacade.sol";

import "forge-std/Test.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameMintStreakUtils} from "../../contracts/modules/DegenerusGameMintStreakUtils.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title LensParity — DegenerusGameLens slot-math + decode parity proof
/// @notice The lens reads the game's storage through `extsload` with hand-derived
///         slot keys and packed-field decodes. This harness inherits the SAME
///         layout contract the game and every module inherit
///         (DegenerusGameMintStreakUtils → DegenerusGameStorage — the byte-identical
///         layout the delegatecall system already relies on), writes records through
///         the COMPILER's own layout/packing, and asserts the lens reads back exactly
///         what was written. Any drift between the lens's slot arithmetic / bit
///         shifts and the real layout fails here.
contract LensStorageHarness is DegenerusGameMintStreakUtils, WalletSeed {
    /// @dev Same body as DegenerusGame.extsload — the lens's read path.
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Same body as GameFacade.playerActivityScore — the authoritative
    ///      aggregate the lens breakdown must reconcile against.
    function playerActivityScore(address player) external view returns (uint256) {
        return _playerActivityScore(_walletIdOf(player), _effectiveQuestStreak(_walletIdOf(player)));
    }

    function playerActivityScoreById(uint32 id) external view returns (uint256) {
        return _playerActivityScore(id, _effectiveQuestStreak(id));
    }

    function nativeEffectiveStreak(address player) external view returns (uint32) {
        return _effectiveQuestStreak(_walletIdOf(player));
    }

    function nativeActiveTicketLevel() external view returns (uint24) {
        return _activeTicketLevel();
    }

    function queue(address player, uint24 lvl) external { _queueEntries(_seedWallet(player), lvl, 7, false); }

    // -- setters: write through the compiler's layout ------------------------

    /// @dev Write a member lane through the compiler's layout, in the box or ticket section,
    ///      with run-start day `runStart`.
    function setSub(
        address p,
        uint8 dailyQuantity,
        bool tickets,
        uint16 scoreCode,
        uint24 checkpointDay,
        uint16 checkpointStreak,
        bool removal,
        uint24 runStart
    ) external {
        uint32 id = _seedWallet(p);
        uint256 count = _subscribers.length;
        uint256 position = tickets ? SUBSCRIBER_CAP - (count - _subBoxCount) : _subBoxCount++;
        uint256 lane = uint256(id) | ((uint256(dailyQuantity) - 1) << SUB_QTY_SHIFT)
            | (tickets ? SUB_TICKETS_BIT : 0) | (uint256(scoreCode) << SUB_SCORE_SHIFT)
            | (removal ? SUB_REMOVAL_BIT : 0);
        _setSubLaneAt(position, _withSubCheckpoint(lane, checkpointDay, checkpointStreak));
        _setSubscriberCount(count + 1);
        _setSubMetaLane(id, (position + 1) | (uint256(runStart) << 11));
    }

    function setEndpoint(uint24 day) external { _afkingEndpointDay = day; }

    /// @dev Register the protocol wallets at their constant IDs and set the pause flags.
    function setProtocolFlags(uint8 flags) external {
        _seedProtocolWallets();
        _afkingProtocolFlags = flags;
    }

    function livenessTriggered() external view returns (bool) { return _livenessTriggered(); }

    function setMintPacked(address p, uint256 w) external {
        _registerWallet(p, type(uint256).max);
        mintPacked_[_walletIdOf(p)] = w;
    }

    /// @dev Register `p` and return its canonical wallet ID.
    function seedId(address p) external returns (uint32) {
        return _seedWallet(p);
    }

    function setSlot0(
        uint24 dailyIdx_,
        uint24 level_,
        bool jackpotPhase,
        bool phaseTransition,
        bool rngLocked,
        uint8 jackpotCounter_,
        uint8 compressedJackpot
    ) external {
        dailyIdx = dailyIdx_;
        level = level_;
        jackpotPhaseFlag = jackpotPhase;
        phaseTransitionActive = phaseTransition;
        rngLockedFlag = rngLocked;
        jackpotCounter = jackpotCounter_;
        jackpotFlags = compressedJackpot;
    }

    function setRngWordByDay(uint24 day, uint256 w) external {
        _recordDailyRng(day, w);
    }

    function setLevelDgnrs(uint24 lvl, uint128 allocation, uint128 claimed) external {
        level = lvl;
        levelDgnrsPacked = uint256(allocation) | (uint256(claimed) << 128) | (uint256(1) << 255);
    }

    function setDecEntry(uint24 lvl, uint64 id, address owner, uint64 stackFlip, uint32 chips) external {
        decEntriesLevel = lvl;
        if (id > decBattleRounds[lvl].count) decBattleRounds[lvl].count = uint40(id);
        decBattlePlayers[_seedWallet(owner)] = (uint256(lvl) << 64) | id;
        _storeDecEntry(lvl, uint64(id),
            (uint256(stackFlip) << 62) | (uint256(chips) << 32) | uint256(_walletIdOf(owner)));
    }

    function setDecRound(uint24 lvl, DecBattleRound calldata round) external {
        decBattleRounds[lvl] = round;
    }

    function setDecNode(uint8 index, uint256 node) external {
        decBattleHeap[index] = node;
    }

    function setDecGeneratedOwner(uint64 ordinal, address owner) external {
        decGeneratedOwners[ordinal] = _seedWallet(owner);
    }

    function setDecQueue(uint24 head, uint24 tail) external {
        decBattleQueue = uint256(head) | uint256(tail) << 24;
    }

    function setDecActiveWord(uint256 word, bool published) external {
        rngWordCurrent = word;
        _setRngSessionPublished(published);
    }

    function setFoilRecord(uint24 lvl, address p, uint256 w) external {
        foilRecord[lvl & 3][_seedWallet(p)] = w == 0 ? 0 : w | (uint256(lvl) << _FOIL_LEVEL_SHIFT);
    }
}

contract LensParityTest is Test {
    LensStorageHarness internal harness;
    DegenerusGameLens internal lens;
    address internal game; // the harness, read through extsload like the real game

    address internal constant PLAYER = address(0xBEEF);

    function setUp() public {
        harness = new LensStorageHarness();
        lens = new DegenerusGameLens();
        game = address(harness);
        // The lens and the layout contract bind quests/affiliate to the
        // ContractAddresses constants; give them code so mocked staticcalls hit.
        vm.etch(ContractAddresses.QUESTS, hex"00");
        vm.etch(ContractAddresses.AFFILIATE, hex"00");
    }

    function _mockQuests(uint32 id, uint32 manualStreak, bool afking) internal {
        vm.mockCall(
            ContractAddresses.QUESTS,
            abi.encodeWithSelector(IDegenerusQuests.effectiveBaseStreakAndAfking_g1521.selector, id),
            abi.encode(manualStreak, afking)
        );
    }

    function _mockAffiliate(uint24 currLevel, uint32 id, uint256 points) internal {
        vm.mockCall(
            ContractAddresses.AFFILIATE,
            abi.encodeWithSelector(IDegenerusAffiliate.affiliateBonusPointsBest_g3878.selector, currLevel, id),
            abi.encode(points)
        );
    }

    // =========================================================================
    // Member lane: slot + full decode + derived rewards + effective streak
    // =========================================================================

    function testFuzz_subInfoFull_decodesWrittenLane(
        address p,
        uint8 dailyQuantity,
        bool tickets,
        uint16 scoreCode,
        uint24 checkpointDay,
        uint16 checkpointStreak,
        bool removal,
        uint24 runStart,
        uint24 endpoint
    ) public {
        vm.assume(p != address(0));
        dailyQuantity = uint8(bound(dailyQuantity, 1, 8));
        scoreCode = uint16(bound(scoreCode, 0, 961));
        checkpointDay = uint24(bound(checkpointDay, 0, 5000));
        endpoint = uint24(bound(endpoint, 0, 6000));
        runStart = uint24(bound(runStart, 0, 5000));
        harness.setSub(p, dailyQuantity, tickets, scoreCode, checkpointDay, checkpointStreak, removal, runStart);
        harness.setEndpoint(endpoint);
        uint32 id = harness.seedId(p);
        _mockQuests(id, 7, false); // non-afking: effectiveStreak = manual streak

        DegenerusGameLens.SubFull memory s = lens.subInfoFull(game, p);
        assertTrue(s.member, "member");
        assertEq(s.active, !removal, "active");
        assertEq(s.removalPending, removal, "removalPending");
        assertFalse(s.paused, "paused");
        assertEq(s.useTickets, tickets, "useTickets");
        assertEq(s.dailyQuantity, dailyQuantity, "dailyQuantity");
        assertEq(s.score, scoreCode <= 500 ? scoreCode : (scoreCode >= 961 ? 30_000 : 500 + ((uint256(scoreCode) - 500) << 6)), "score");
        assertEq(s.checkpointDay, checkpointDay, "checkpointDay");
        assertEq(s.checkpointStreak, checkpointStreak, "checkpointStreak");
        assertEq(s.runStartDay, runStart, "runStartDay");
        assertEq(s.endpoint, endpoint, "endpoint");
        uint256 elapsed = endpoint > checkpointDay ? endpoint - checkpointDay : 0;
        assertEq(s.owedFlip, elapsed * (tickets ? 100 + 100 * uint256(dailyQuantity) : 100), "owedFlip");
        assertEq(s.owedAffiliateBase, elapsed * 70 * dailyQuantity, "owedAffiliateBase");
        assertEq(s.effectiveStreak, 7, "manual streak passthrough");
        assertEq(s.effectiveStreak, harness.nativeEffectiveStreak(p), "native parity");
    }

    function test_subInfoFull_nonMember() public {
        harness.setEndpoint(9);
        _mockQuests(harness.seedId(PLAYER), 4, false);
        DegenerusGameLens.SubFull memory s = lens.subInfoFull(game, PLAYER);
        assertFalse(s.member);
        assertFalse(s.active);
        assertEq(s.dailyQuantity, 0);
        assertEq(s.owedFlip, 0);
        assertEq(s.endpoint, 9, "endpoint is global");
        assertEq(s.effectiveStreak, 4);
    }

    /// @notice A protocol seat's pause flags read as `paused`; its parked checkpoint day owes nothing.
    function test_subInfoFull_pausedProtocolSeat() public {
        harness.setProtocolFlags(8); // Vault unfunded pause
        address vaultKey = ContractAddresses.VAULT;
        harness.setSub(vaultKey, 1, false, 0, uint24((1 << 22) - 1), 5, false, 3);
        harness.setEndpoint(50);
        _mockQuests(1, 0, true);
        DegenerusGameLens.SubFull memory s = lens.subInfoFull(game, vaultKey);
        assertTrue(s.paused, "paused");
        assertEq(s.owedFlip, 0, "a parked checkpoint owes nothing");
        assertEq(s.owedAffiliateBase, 0);
        assertEq(s.effectiveStreak, harness.nativeEffectiveStreak(vaultKey), "parity");
    }

    /// @notice The live-afking streak (checkpoint streak plus elapsed days, a run pending
    ///         removal falling back to the manual streak) matches the game-side
    ///         _effectiveQuestStreak exactly.
    function testFuzz_subInfoFull_effectiveStreak_afkingParity(
        uint24 checkpointDay,
        uint24 endpoint,
        uint16 checkpointStreak,
        uint32 manualStreak,
        bool removal,
        bool afking
    ) public {
        checkpointDay = uint24(bound(checkpointDay, 0, 5000));
        endpoint = uint24(bound(endpoint, 0, 6000));

        harness.setSub(PLAYER, 1, false, 0, checkpointDay, checkpointStreak, removal, 0);
        harness.setEndpoint(endpoint);
        _mockQuests(harness.seedId(PLAYER), manualStreak, afking);

        assertEq(
            lens.subInfoFull(game, PLAYER).effectiveStreak,
            harness.nativeEffectiveStreak(PLAYER),
            "afking effective streak parity"
        );
    }

    // =========================================================================
    // Activity score breakdown: components reconcile to the aggregate
    // =========================================================================

    function testFuzz_activityBreakdown_reconcilesToAggregate(
        uint24 lastCompleted,
        uint24 streakVal,
        uint24 levelCount,
        uint24 frozenUntilLevel,
        uint8 passTypeSeed,
        bool deityPass,
        uint24 affCacheLevel,
        uint8 affCachePoints,
        uint8 curse,
        uint24 level_,
        uint32 manualStreak,
        bool jackpotPhase
    ) public {
        level_ = uint24(bound(level_, 1, 100_000));
        affCachePoints = uint8(bound(affCachePoints, 0, 63)); // 6-bit field
        curse &= 31; // five-bit field; do not overwrite the adjacent units lane
        uint8 passType = passTypeSeed % 3 == 0 ? 0 : (passTypeSeed % 3 == 1 ? 1 : 3);

        uint256 packed = (uint256(lastCompleted)) |
            (uint256(levelCount) << BitPackingLib.LEVEL_COUNT_SHIFT) |
            (uint256(streakVal) << BitPackingLib.LEVEL_STREAK_SHIFT) |
            (uint256(frozenUntilLevel) << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) |
            (uint256(passType) << BitPackingLib.WHALE_PASS_TYPE_SHIFT) |
            (deityPass ? (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT) : 0) |
            (uint256(affCacheLevel) << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) |
            (uint256(affCachePoints) << BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) |
            (uint256(curse) << BitPackingLib.CURSE_COUNT_SHIFT);

        uint32 id = harness.seedId(PLAYER);
        harness.setMintPacked(PLAYER, packed);
        harness.setSlot0(0, level_, jackpotPhase, false, false, 0, 0);
        _mockQuests(id, manualStreak, false);
        _mockAffiliate(level_, id, 41); // cache-miss branch answer

        DegenerusGameLens.ActivityBreakdown memory b = lens.activityScoreBreakdown(game, PLAYER);

        // The lens total IS the game aggregate.
        assertEq(b.total, harness.playerActivityScore(PLAYER), "total == aggregate");

        // The components re-sum to the aggregate under the same curse floor + cap.
        uint256 sum = b.mintStreakPoints + b.mintCountPoints + b.questStreakPoints + b.affiliatePoints
            + b.passBonusPoints;
        sum = sum > b.cursePoints ? sum - b.cursePoints : 0;
        if (sum > 65_534) sum = 65_534;
        assertEq(sum, b.total, "component sum reconciles");
    }

    function testFuzz_activeTicketLevel_parity(
        uint24 level_,
        bool jackpotPhase,
        bool phaseTransition,
        bool rngLocked,
        uint8 cnt,
        uint8 comp
    ) public {
        level_ = uint24(bound(level_, 0, 1_000_000));
        comp = uint8(bound(comp, 0, 3));
        cnt = uint8(bound(cnt, 0, 3));
        harness.setSlot0(0, level_, jackpotPhase, phaseTransition, rngLocked, cnt, comp);
        assertEq(lens.activeTicketLevelOf(game), harness.nativeActiveTicketLevel(), "routed level parity");
    }

    // =========================================================================
    // Level DGNRS / decimator / foil records
    // =========================================================================

    function test_RegistryOwedWritesPreserveLensSlots() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        harness.setLevelDgnrs(9, 123456, 789);
        for (uint160 i; i < 19; ++i) harness.queue(address(0xCE00 + i), 9);
        (uint128 allocation, uint128 claimed) = lens.levelDgnrsInfo(game, 9);
        assertEq(allocation, 123456); assertEq(claimed, 789);
        assertEq(lens.activeTicketLevelOf(game), harness.nativeActiveTicketLevel());
    }

    function testFuzz_levelDgnrsInfo(uint24 lvl, uint128 allocation, uint128 claimed) public {
        claimed &= uint128((uint256(1) << 127) - 1);
        harness.setLevelDgnrs(lvl, allocation, claimed);
        (uint128 a, uint128 c) = lens.levelDgnrsInfo(game, lvl);
        assertEq(a, allocation, "allocation");
        assertEq(c, claimed, "claimed");
    }

    function testFuzz_decBurnOf(uint24 lvl, uint64 id, address p, uint64 stackFlip, uint32 chips) public {
        id = uint64(bound(id, 1, type(uint40).max));
        vm.assume(p != address(0));
        chips = uint32(bound(chips, 0, 0x3FFFFFFF));
        harness.setDecEntry(lvl, id, p, stackFlip, chips);
        DegenerusGameLens.DecBurnEntry memory e = lens.decBurnOf(game, lvl, p);
        uint256 stack = uint256(stackFlip);
        assertEq(e.entryId, id); assertEq(e.owner, p); assertEq(e.stack, stack); assertEq(e.chips, chips);
        (address o, uint256 s, uint32 c) = lens.decEntryAt(game, lvl, id);
        assertEq(o, p); assertEq(s, stack); assertEq(c, chips);
        // Retired rounds cannot read the shared entry bank.
        harness.setDecEntry(lvl ^ 1, 1, p, 1, 0);
        assertEq(lens.decBurnOf(game, lvl, p).entryId, 0);
        (o,,) = lens.decEntryAt(game, lvl, id);
        assertEq(o, address(0));
    }

    function testFuzz_decRound(uint24 lvl, DegenerusGameLens.DecBattleRound memory r) public {
        harness.setDecRound(lvl, r);
        assertEq(abi.encode(lens.decBattleRoundOf(game, lvl)), abi.encode(r));
    }

    function testFuzz_decWinner(
        uint24 lvl, uint8 index, uint256 word, uint192 score, uint64 id,
        address owner, bool generated, uint40 ordinal
    ) public {
        vm.assume(lvl != 0);
        vm.assume(owner != address(0) && owner != address(1));
        word = bound(word, 2, type(uint256).max);
        index = uint8(bound(index, 0, 199));
        id = uint64(bound(id, 1, type(uint40).max));
        DegenerusGameLens.DecBattleRound memory r;
        r.count = uint40(id);
        ordinal = uint40(bound(ordinal, 1, id));
        if (generated) id += ordinal;
        address other = address(uint160(owner) ^ 1);
        harness.setDecEntry(lvl, id, generated ? other : owner, 2000, 0);
        harness.setDecGeneratedOwner(ordinal, generated ? owner : other);
        r.winners = index + 1;
        r.phase = 1;
        harness.setDecActiveWord(word, true);
        harness.setDecRound(lvl, r);
        harness.setDecNode(index, (uint256(score) << 64) | id);
        // The shared leaderboard answers only for the round at the head of the queue.
        harness.setDecQueue(lvl ^ 1, lvl ^ 1);
        vm.expectRevert(); lens.decWinnerAt(game, lvl, index);
        harness.setDecQueue(lvl, lvl);
        DegenerusGameLens.DecWinner memory w = lens.decWinnerAt(game, lvl, index);
        assertEq(w.score, score);
        assertEq(w.owner, owner, "winner resolves the correct original or generated owner source");
        uint256 tie = uint256(keccak256(abi.encode(uint256(50), word, uint256(id))));
        assertEq(w.key, (tie & ~uint256(type(uint64).max)) | id);
        vm.expectRevert(); lens.decWinnerAt(game, lvl, index + 1);
        harness.setDecActiveWord(word, false);
        vm.expectRevert(); lens.decWinnerAt(game, lvl, index);
        harness.setDecActiveWord(1, true);
        vm.expectRevert(); lens.decWinnerAt(game, lvl, index);
        harness.setDecActiveWord(word, true);
        r.phase = 3;
        harness.setDecRound(lvl, r);
        vm.expectRevert(); lens.decWinnerAt(game, lvl, index);
    }

    function testFuzz_decSettleCursorOf(uint24 head, uint24 tail) public {
        harness.setDecQueue(head, tail);
        (uint24 h, uint24 t) = lens.decSettleCursorOf(game);
        assertEq(h, head); assertEq(t, tail);
    }

    function testFuzz_foilRecordOf(uint24 lvl, address p, uint24 resolveDay, uint16 multBps, uint16 score, uint8 snap)
        public
    {
        vm.assume(p != address(0));
        uint256 w = uint256(resolveDay) | (uint256(multBps) << 24) | (uint256(score) << 40)
            | (uint256(snap) << 56);
        harness.setFoilRecord(lvl, p, w);
        DegenerusGameLens.FoilRecordEntry memory f = lens.foilRecordOf(game, lvl, p);
        assertEq(f.present, w != 0, "present");
        assertEq(f.resolveDay, resolveDay, "resolveDay");
        assertEq(f.multBps, multBps, "multBps");
        assertEq(f.activityScore, score, "activityScore");
    }
}

/// @title LensSettlementParity — the lens's owed figures are what settlement actually pays
/// @notice Two real subscribers (a box member and a ticket member) run for several completed
///         days on the deployed protocol; `owedFlip` / `owedAffiliateBase` read before the claim
///         equal the AfkingFlipClaimed / AffiliateBaseDrained the claim then emits, and the lens
///         shows the settled checkpoint afterwards.
contract LensSettlementParity is DeployProtocol {
    bytes32 private constant AFKING_FLIP_CLAIMED = keccak256("AfkingFlipClaimed(uint32,uint256)");
    bytes32 private constant AFFILIATE_BASE_DRAINED = keccak256("AffiliateBaseDrained(uint32,uint256)");

    DegenerusGameLens private lens;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    function _subscribe(string memory name, bool tickets, uint8 quantity) private returns (address who, uint32 id) {
        who = makeAddr(name);
        uint256 seat = _grantSeat(who);
        id = game.walletIdOf_g3120(who);
        vm.deal(address(this), 5 ether);
        game.depositAfkingFunding{value: 5 ether}(id);
        vm.prank(who);
        game.subscribe(0, tickets, quantity, seat);
    }

    function _completeDay(uint256 vrfWord) private {
        _finishReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 50 && mockVRF.lastRequestId() == before; ++i) game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i; i < 50; ++i) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        _finishReadConsumers();
    }

    function test_owedFiguresEqualWhatTheClaimSettles() public {
        (address boxer, uint32 boxId) = _subscribe("lens_boxer", false, 3);
        (address ticketer, uint32 ticketId) = _subscribe("lens_ticketer", true, 2);

        DegenerusGameLens.SubFull memory fresh = lens.subInfoFull(address(game), boxer);
        assertEq(fresh.owedFlip, 0, "nothing is owed before a pass completes");
        assertEq(fresh.checkpointDay, fresh.endpoint, "checkpointed at signup");

        for (uint256 d = 1; d <= 3; ++d) _completeDay(uint256(keccak256(abi.encode("lens_settle_day", d))) | 1);

        DegenerusGameLens.SubFull memory box = lens.subInfoFull(address(game), boxer);
        DegenerusGameLens.SubFull memory tix = lens.subInfoFull(address(game), ticketer);
        assertEq(box.endpoint - box.checkpointDay, 3, "three completed days elapsed");
        assertEq(box.owedFlip, 300, "box: 100 per day");
        assertEq(box.owedAffiliateBase, 3 * 70 * 3, "box: 70 per unit per day");
        assertEq(tix.owedFlip, 3 * (100 + 200), "tickets: 100 + 100 per ticket per day");
        assertEq(tix.owedAffiliateBase, 3 * 70 * 2, "tickets: 70 per unit per day");
        assertEq(box.effectiveStreak, box.checkpointStreak + 3, "live streak includes the elapsed days");

        uint32[] memory subs = new uint32[](2);
        subs[0] = boxId;
        subs[1] = ticketId;
        vm.recordLogs();
        game.claimAfkingFlip(subs);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 paidBox;
        uint256 paidTix;
        uint256 baseBox;
        uint256 baseTix;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game)) continue;
            uint32 who = uint32(uint256(logs[i].topics[1]));
            if (logs[i].topics[0] == AFKING_FLIP_CLAIMED) {
                if (who == boxId) paidBox = abi.decode(logs[i].data, (uint256));
                else if (who == ticketId) paidTix = abi.decode(logs[i].data, (uint256));
            } else if (logs[i].topics[0] == AFFILIATE_BASE_DRAINED) {
                if (who == boxId) baseBox = abi.decode(logs[i].data, (uint256));
                else if (who == ticketId) baseTix = abi.decode(logs[i].data, (uint256));
            }
        }
        assertEq(paidBox, box.owedFlip, "box: claim paid the owed FLIP");
        assertEq(paidTix, tix.owedFlip, "tickets: claim paid the owed FLIP");
        assertEq(baseBox, box.owedAffiliateBase, "box: claim drained the owed base");
        assertEq(baseTix, tix.owedAffiliateBase, "tickets: claim drained the owed base");

        DegenerusGameLens.SubFull memory after_ = lens.subInfoFull(address(game), boxer);
        assertEq(after_.owedFlip, 0, "settled");
        assertEq(after_.owedAffiliateBase, 0, "settled");
        assertEq(after_.checkpointDay, after_.endpoint, "checkpoint moved to the endpoint");
        assertEq(after_.checkpointStreak, box.checkpointStreak + 3, "elapsed days folded into the checkpoint streak");
        assertEq(after_.effectiveStreak, box.effectiveStreak, "settling never moves the live streak");
    }
}
