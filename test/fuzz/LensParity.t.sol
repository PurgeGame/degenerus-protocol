// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameMintStreakUtils} from "../../contracts/modules/DegenerusGameMintStreakUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @title LensParity — DegenerusGameLens slot-math + decode parity proof
/// @notice The lens reads the game's storage through `extsload` with hand-derived
///         slot keys and packed-field decodes. This harness inherits the SAME
///         layout contract the game and every module inherit
///         (DegenerusGameMintStreakUtils → DegenerusGameStorage — the byte-identical
///         layout the delegatecall system already relies on), writes records through
///         the COMPILER's own layout/packing, and asserts the lens reads back exactly
///         what was written. Any drift between the lens's slot arithmetic / bit
///         shifts and the real layout fails here.
contract LensStorageHarness is DegenerusGameMintStreakUtils {
    /// @dev Same body as DegenerusGame.extsload — the lens's read path.
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Same body as DegenerusGame.playerActivityScore — the authoritative
    ///      aggregate the lens breakdown must reconcile against.
    function playerActivityScore(address player) external view returns (uint256) {
        return _playerActivityScore(player, _effectiveQuestStreak(player));
    }

    function nativeEffectiveStreak(address player) external view returns (uint32) {
        return _effectiveQuestStreak(player);
    }

    function nativeActiveTicketLevel() external view returns (uint24) {
        return _activeTicketLevel();
    }

    // -- setters: write through the compiler's layout ------------------------

    function setSub(
        address p,
        uint8 dailyQuantity,
        uint8 flags,
        uint16 score,
        uint24 amount,
        uint24 lastAutoBoughtDay,
        uint24 lastOpenedDay,
        uint24 afkCoveredThroughDay,
        uint24 afkingStartDay,
        uint32 affiliateBase,
        uint24 pendingFlip,
        uint16 subStreakLatch
    ) external {
        Sub storage s = _subOf[p];
        s.dailyQuantity = dailyQuantity;
        s.flags = flags;
        s.score = score;
        s.amount = amount;
        s.lastAutoBoughtDay = lastAutoBoughtDay;
        s.lastOpenedDay = lastOpenedDay;
        s.afkCoveredThroughDay = afkCoveredThroughDay;
        s.afkingStartDay = afkingStartDay;
        s.affiliateBase = affiliateBase;
        s.pendingFlip = pendingFlip;
        s.subStreakLatch = subStreakLatch;
    }

    function setMintPacked(address p, uint256 w) external {
        mintPacked_[p] = w;
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
        compressedJackpotFlag = compressedJackpot;
    }

    function setRngWordByDay(uint24 day, uint256 w) external {
        rngWordByDay[day] = w;
    }

    function setLevelDgnrs(uint24 lvl, uint128 allocation, uint128 claimed) external {
        levelDgnrsPacked[lvl] = uint256(allocation) | (uint256(claimed) << 128);
    }

    function setDecBurn(
        uint24 lvl,
        address p,
        uint192 burn,
        uint8 bucket,
        uint8 subBucket,
        uint8 claimed
    ) external {
        DecBet storage e = decBurn[lvl][p];
        e.burn = burn;
        e.bucket = bucket;
        e.subBucket = subBucket;
        e.claimed = claimed;
    }

    function setDecBucketTotal(uint24 lvl, uint8 denom, uint8 subBucket, uint256 v) external {
        decBucketBurnTotal[lvl][denom][subBucket] = v;
    }

    function setTerminalDecBet(
        address p,
        uint80 totalBurn,
        uint88 weightedBurn,
        uint8 bucket,
        uint8 subBucket,
        uint48 burnLevel,
        bool boosted
    ) external {
        terminalDecBets[p] = TerminalDecBet({
            totalBurn: totalBurn,
            weightedBurn: weightedBurn,
            bucket: bucket,
            subBucket: subBucket,
            burnLevel: burnLevel,
            boosted: boosted
        });
    }

    /// @dev Same key derivation as the terminal decimator write sites
    ///      (keccak256(abi.encode(lvl, denom, subBucket))).
    function setTerminalBucketTotal(uint48 lvl, uint8 denom, uint8 subBucket, uint256 v) external {
        terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, denom, subBucket))] = v;
    }

    function setTerminalClaimRound(uint24 lvl, uint96 poolWei, uint128 totalBurn) external {
        lastTerminalDecClaimRound = TerminalDecClaimRound({lvl: lvl, poolWei: poolWei, totalBurn: totalBurn});
    }

    function setFoilRecord(uint24 lvl, address p, uint256 w) external {
        foilRecord[lvl][p] = w;
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

    function _mockQuests(address player, uint32 manualStreak, bool afking) internal {
        vm.mockCall(
            ContractAddresses.QUESTS,
            abi.encodeWithSelector(IDegenerusQuests.effectiveBaseStreakAndAfking.selector, player),
            abi.encode(manualStreak, afking)
        );
    }

    function _mockAffiliate(uint24 currLevel, address player, uint256 points) internal {
        vm.mockCall(
            ContractAddresses.AFFILIATE,
            abi.encodeWithSelector(IDegenerusAffiliate.affiliateBonusPointsBest.selector, currLevel, player),
            abi.encode(points)
        );
    }

    // =========================================================================
    // Sub record: slot + full 11-field decode + effective streak
    // =========================================================================

    function testFuzz_subInfoFull_decodesWrittenRecord(
        address p,
        uint8 dailyQuantity,
        uint8 flags,
        uint16 score,
        uint24 amount,
        uint24 lastAutoBoughtDay,
        uint24 lastOpenedDay,
        uint24 afkCoveredThroughDay,
        uint24 afkingStartDay,
        uint32 affiliateBase,
        uint24 pendingFlip,
        uint16 subStreakLatch
    ) public {
        harness.setSub(
            p,
            dailyQuantity,
            flags,
            score,
            amount,
            lastAutoBoughtDay,
            lastOpenedDay,
            afkCoveredThroughDay,
            afkingStartDay,
            affiliateBase,
            pendingFlip,
            subStreakLatch
        );
        _mockQuests(p, 7, false); // non-afking: effectiveStreak = manual streak

        DegenerusGameLens.SubFull memory s = lens.subInfoFull(game, p);
        assertEq(s.active, dailyQuantity != 0, "active");
        assertEq(s.dailyQuantity, dailyQuantity, "dailyQuantity");
        assertEq(s.flags, flags, "flags");
        assertEq(s.score, score, "score");
        assertEq(s.amountMilliEth, amount, "amount");
        assertEq(s.lastAutoBoughtDay, lastAutoBoughtDay, "lastAutoBoughtDay");
        assertEq(s.lastOpenedDay, lastOpenedDay, "lastOpenedDay");
        assertEq(s.afkCoveredThroughDay, afkCoveredThroughDay, "afkCoveredThroughDay");
        assertEq(s.afkingStartDay, afkingStartDay, "afkingStartDay");
        assertEq(s.affiliateBase, affiliateBase, "affiliateBase");
        assertEq(s.pendingFlip, pendingFlip, "pendingFlip");
        assertEq(s.subStreakLatch, subStreakLatch, "subStreakLatch");
        assertEq(s.effectiveStreak, 7, "manual streak passthrough");
        assertEq(s.effectiveStreak, harness.nativeEffectiveStreak(p), "native parity");
    }

    /// @notice The live-afking compute-on-read streak (decay branches included)
    ///         matches the game-side _effectiveQuestStreak exactly.
    function testFuzz_subInfoFull_effectiveStreak_afkingParity(
        uint24 afkingStartDay,
        uint24 afkCoveredThroughDay,
        uint24 dailyIdx_,
        uint16 subStreakLatch,
        uint32 manualStreak,
        uint48 warpTs,
        bool sealNextWord
    ) public {
        // A live run: start day set, covered >= start (the run's own invariant).
        afkingStartDay = uint24(bound(afkingStartDay, 1, 5000));
        afkCoveredThroughDay = uint24(bound(afkCoveredThroughDay, afkingStartDay, 6000));
        dailyIdx_ = uint24(bound(dailyIdx_, 0, 7000));
        warpTs = uint48(bound(warpTs, 2 days, 8000 days));
        vm.warp(warpTs);

        harness.setSub(PLAYER, 1, 0, 0, 0, 0, 0, afkCoveredThroughDay, afkingStartDay, 0, 0, subStreakLatch);
        harness.setSlot0(dailyIdx_, 3, false, false, false, 0, 0);
        if (sealNextWord) harness.setRngWordByDay(dailyIdx_ + 1, 0xABCD);
        _mockQuests(PLAYER, manualStreak, true);

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

        harness.setMintPacked(PLAYER, packed);
        harness.setSlot0(0, level_, jackpotPhase, false, false, 0, 0);
        _mockQuests(PLAYER, manualStreak, false);
        _mockAffiliate(level_, PLAYER, 41); // cache-miss branch answer

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
        comp = uint8(bound(comp, 0, 2));
        cnt = uint8(bound(cnt, 0, 5));
        harness.setSlot0(0, level_, jackpotPhase, phaseTransition, rngLocked, cnt, comp);
        assertEq(lens.activeTicketLevelOf(game), harness.nativeActiveTicketLevel(), "routed level parity");
    }

    // =========================================================================
    // Level DGNRS / decimator / terminal decimator / foil records
    // =========================================================================

    function testFuzz_levelDgnrsInfo(uint24 lvl, uint128 allocation, uint128 claimed) public {
        harness.setLevelDgnrs(lvl, allocation, claimed);
        (uint128 a, uint128 c) = lens.levelDgnrsInfo(game, lvl);
        assertEq(a, allocation, "allocation");
        assertEq(c, claimed, "claimed");
    }

    function testFuzz_decBurnOf(
        uint24 lvl,
        address p,
        uint192 burn,
        uint8 bucket,
        uint8 subBucket,
        bool claimed
    ) public {
        harness.setDecBurn(lvl, p, burn, bucket, subBucket, claimed ? 1 : 0);
        DegenerusGameLens.DecBurnEntry memory e = lens.decBurnOf(game, lvl, p);
        assertEq(e.burn, burn, "burn");
        assertEq(e.bucket, bucket, "bucket");
        assertEq(e.subBucket, subBucket, "subBucket");
        assertEq(e.claimed, claimed, "claimed");
    }

    function testFuzz_decBucketTotal(uint24 lvl, uint8 denom, uint8 subBucket, uint256 v) public {
        denom = uint8(bound(denom, 0, 12));
        subBucket = uint8(bound(subBucket, 0, 12));
        harness.setDecBucketTotal(lvl, denom, subBucket, v);
        assertEq(lens.decBucketTotal(game, lvl, denom, subBucket), v, "bucket total");
    }

    function testFuzz_terminalDecBetOf(
        address p,
        uint80 totalBurn,
        uint88 weightedBurn,
        uint8 bucket,
        uint8 subBucket,
        uint48 burnLevel,
        bool boosted
    ) public {
        harness.setTerminalDecBet(p, totalBurn, weightedBurn, bucket, subBucket, burnLevel, boosted);
        DegenerusGameLens.TerminalDecEntry memory e = lens.terminalDecBetOf(game, p);
        assertEq(e.totalBurn, totalBurn, "totalBurn");
        assertEq(e.weightedBurn, weightedBurn, "weightedBurn");
        assertEq(e.bucket, bucket, "bucket");
        assertEq(e.subBucket, subBucket, "subBucket");
        assertEq(e.burnLevel, burnLevel, "burnLevel");
        assertEq(e.boosted, boosted, "boosted");
    }

    function testFuzz_terminalDecBucketTotal(uint48 lvl, uint8 denom, uint8 subBucket, uint256 v) public {
        harness.setTerminalBucketTotal(lvl, denom, subBucket, v);
        assertEq(lens.terminalDecBucketTotal(game, lvl, denom, subBucket), v, "terminal bucket total");
    }

    function testFuzz_terminalDecClaimRound(uint24 lvl, uint96 poolWei, uint128 totalBurn) public {
        harness.setTerminalClaimRound(lvl, poolWei, totalBurn);
        (uint24 l, uint96 pw, uint128 tb) = lens.terminalDecClaimRound(game);
        assertEq(l, lvl, "lvl");
        assertEq(pw, poolWei, "poolWei");
        assertEq(tb, totalBurn, "totalBurn");
    }

    function testFuzz_foilRecordOf(uint24 lvl, address p, uint24 resolveDay, uint16 multBps, uint16 score, uint8 snap)
        public
    {
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
