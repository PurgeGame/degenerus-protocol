// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {ActivityAffiliateCacheFixture, ActivityAffiliateCacheHost, ActivityAffiliateRealQA, ActivityAffiliateStubQA} from "./helpers/ActivityAffiliateCacheFixture.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
import {activityScoreOf} from "../helpers/ActivityScoreOf.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract ActivityCacheQuestStub {
    function effectiveBaseStreakAndAfking_g1521(uint32, uint24) external pure returns (uint32, bool) { return (17, false); }
}

contract ActivityAffiliateCacheTest is ActivityAffiliateCacheFixture {
    // Last level, level count and last-purchase day: the history the cache persists beside.
    uint256 private constant DURABLE_MASK = (uint256(1) << 48) - 1 | (uint256(type(uint24).max) << 72);
    function testFuzz_CachedScorePreservesScoreAndOtherFields(
        uint256 packed, uint32 streak, uint24 lvl, uint24 basis, address player, uint128 earnings
    ) public {
        packed = _stale(packed, lvl);
        uint32 id = host.seed(player, packed, lvl);
        if (lvl > 1) _seedEarnings(lvl - 1, id, earnings);
        uint256 expected = host.score(player, streak, basis);
        uint256 actual = host.scoreCached(player, streak, basis);
        assertEq(actual, expected);
        uint256 afterPacked = host.packedOf(player);
        assertEq(afterPacked & ~CACHE_MASK, packed & ~CACHE_MASK, "only cache fields change");
        if (player == address(0) || (packed & DURABLE_MASK) == 0) {
            assertEq(afterPacked, packed, "zero or history-free player never cached");
        }
        else {
            assertEq((afterPacked >> 173) & 0xffffff, lvl);
            assertEq((afterPacked >> 197) & 63, affiliate.affiliateBonusPointsBest_g3878(lvl, id));
        }
        assertEq(host.score(player, streak, basis), expected);
    }

    function test_UnitTrackingLevelAloneIsNotDurableHistory() public {
        uint256 packed = _stale(uint256(1) << 96, 7);
        host.seed(PLAYER, packed, 7);
        host.scoreCached(PLAYER, 0, 7);
        assertEq(host.packedOf(PLAYER), packed, "unit-tracking level alone never caches");
    }

    function testFuzz_CacheHitHasNoAffiliateCallOrStore(uint256 packed, uint24 lvl, uint32 streak) public {
        packed = _stale(packed, lvl) | 1;
        host.seed(PLAYER, packed, lvl);
        uint256 expected = host.scoreCached(PLAYER, streak, lvl);
        vm.startStateDiffRecording();
        uint256 actual = host.scoreCached(PLAYER, streak, lvl);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(actual, expected); assertEq(calls, 0); assertEq(stores, 0);
    }

    function test_LevelAdvanceRefreshesWindow() public {
        // At level6, level5 earnings count; advancing to7 drops level1 and admits6.
        _seedEarnings(1, PLAYER_ID, 1_000);
        _seedEarnings(5, PLAYER_ID, 100);
        host.seed(PLAYER, _stale(1, 6), 6);
        uint256 first = host.scoreCached(PLAYER, 0, 6);
        _seedEarnings(6, PLAYER_ID, 50_000);
        // Next/current-level earnings never change the cached prior-level window.
        assertEq(host.scoreCached(PLAYER, 0, 6), first);
        host.seed(PLAYER, host.packedOf(PLAYER), 7);
        uint256 expected = host.score(PLAYER, 0, 7);
        vm.startStateDiffRecording();
        uint256 actual = host.scoreCached(PLAYER, 0, 7);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(actual, expected); assertGt(actual, first); assertEq(calls, 1); assertEq(stores, 1);
        assertEq((host.packedOf(PLAYER) >> 173) & 0xffffff, 7);
    }

    function test_RecordMintPiggybacksActualLevelCache() public {
        _seedEarnings(23, PLAYER_ID, 100);
        _seedEarnings(24, PLAYER_ID, 50_000);
        host.seed(PLAYER, 0, 24);
        host.record(PLAYER, 25, 400);
        uint256 packed = host.packedOf(PLAYER);
        assertEq((packed >> 173) & 0xffffff, 24, "actual game level, not target25");
        assertEq((packed >> 197) & 63, affiliate.affiliateBonusPointsBest_g3878(24, PLAYER_ID));
        assertTrue(affiliate.affiliateBonusPointsBest_g3878(25, PLAYER_ID) != ((packed >> 197) & 63));
        uint256 expected = host.score(PLAYER, 10, 25);
        vm.startStateDiffRecording();
        uint256 actual = host.scoreCached(PLAYER, 10, 25);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(actual, expected); assertEq(calls, 0); assertEq(stores, 0);
    }

    function test_ZeroPlayerReturnsZeroWithoutCaching() public {
        host.seed(address(0), type(uint256).max, 24);
        vm.startStateDiffRecording();
        assertEq(host.scoreCached(address(0), type(uint32).max, 25), 0);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(calls, 0); assertEq(stores, 0); assertEq(host.packedOf(address(0)), type(uint256).max);
    }

    function test_ProductionFacadeDelegatesAndPreservesView() public {
        vm.etch(ContractAddresses.GAME, type(ActivityAffiliateCacheHost).runtimeCode);
        ActivityAffiliateCacheHost(ContractAddresses.GAME).seed(PLAYER, 1, 24);
        vm.etch(ContractAddresses.GAME, type(DegenerusGame).runtimeCode);
        vm.etch(ContractAddresses.QUESTS, type(ActivityAffiliateStubQA).runtimeCode);
        _seedEarnings(23, PLAYER_ID, 100);
        DegenerusGame game = DegenerusGame(payable(ContractAddresses.GAME));
        (uint256 expected,) = game.playerActivityScore(PLAYER);
        (uint256 cachedScore, uint32 cachedId) = game.playerActivityScoreCached(PLAYER);
        assertEq(cachedScore, expected);
        assertEq(cachedId, PLAYER_ID);
        (uint256 score,) = game.playerActivityScore(PLAYER);
        assertEq(score, expected);
        vm.startStateDiffRecording();
        (uint256 hitScore,) = game.playerActivityScoreCached(PLAYER);
        assertEq(hitScore, expected);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(game));
        assertEq(calls, 0); assertEq(stores, 0);
        (uint256 zeroScore, uint32 zeroId) = game.playerActivityScoreCached(address(0));
        assertEq(zeroScore, 0); assertEq(zeroId, 0);
    }

    function _productionGame(uint256 packed) private returns (DegenerusGame game, DegenerusQuests quests) {
        vm.etch(ContractAddresses.GAME, type(ActivityAffiliateCacheHost).runtimeCode);
        ActivityAffiliateCacheHost(ContractAddresses.GAME).seed(PLAYER, packed, 24);
        vm.etch(ContractAddresses.GAME, type(DegenerusGame).runtimeCode);
        vm.etch(ContractAddresses.QUESTS, type(ActivityAffiliateRealQA).runtimeCode);
        game = DegenerusGame(payable(ContractAddresses.GAME));
        quests = DegenerusQuests(ContractAddresses.QUESTS);
    }

    function testFuzz_PermissionlessCacheCannotOpenGrowthGate(uint8 curse) public {
        uint256 packed = (uint256(curse) & BitPackingLib.MASK_5) << BitPackingLib.CURSE_COUNT_SHIFT;
        (DegenerusGame game, DegenerusQuests quests) = _productionGame(packed);
        (bool mayBet, bool rewarded,) = quests.marketBetGates(game.walletIdOf_g3120(PLAYER), 24);
        assertFalse(mayBet); assertFalse(rewarded);
        (uint256 expected,) = game.playerActivityScore(PLAYER);
        vm.startStateDiffRecording();
        vm.prank(address(0xBAD));
        (uint256 cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, expected);
        (,uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(game));
        assertEq(stores, 0);
        assertEq(game.mintPackedFor(PLAYER), packed);
        (mayBet, rewarded,) = quests.marketBetGates(game.walletIdOf_g3120(PLAYER), 24);
        assertFalse(mayBet); assertFalse(rewarded);
    }

    function testFuzz_MutableOnlyWordsNeverPersistCache(uint8 curse) public {
        uint256 packed = (uint256(curse) & BitPackingLib.MASK_5) << BitPackingLib.CURSE_COUNT_SHIFT;
        host.seed(PLAYER, packed, 24);
        uint256 expected = host.score(PLAYER, 17, 25);
        vm.startStateDiffRecording();
        assertEq(host.scoreCached(PLAYER, 17, 25), expected);
        (,uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(stores, 0); assertEq(host.packedOf(PLAYER), packed);
    }
    function test_HitsAndHistoryFreeWalletsSkipMinerDispatch() public {
        (DegenerusGame game,) = _productionGame(1 | (uint256(24) << 173));
        if (ContractAddresses.GAME_MINER_MODULE != ContractAddresses.GAME) vm.etch(ContractAddresses.GAME_MINER_MODULE, hex"5f5ffd");
        (uint256 cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, activityScoreOf(address(game), PLAYER));
        (game,) = _productionGame(0);
        if (ContractAddresses.GAME_MINER_MODULE != ContractAddresses.GAME) vm.etch(ContractAddresses.GAME_MINER_MODULE, hex"5f5ffd");
        (cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, activityScoreOf(address(game), PLAYER));
        assertEq(game.mintPackedFor(PLAYER), 0);
    }

    function _passWord(uint8 passType, uint24 frozenUntil, uint24 lastLevel, uint24 count) private pure returns (uint256) {
        return (uint256(passType) << BitPackingLib.WHALE_PASS_TYPE_SHIFT)
            | (uint256(frozenUntil) << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT)
            | (uint256(count) << BitPackingLib.LEVEL_COUNT_SHIFT)
            | uint256(lastLevel);
    }

    function _passFields(uint256 packed) private pure returns (uint256 passType, uint256 frozenUntil) {
        passType = (packed >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3;
        frozenUntil = (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24;
    }

    /// @dev A whole ticket for the level after the pass's last level, recorded while the game level is still that
    ///      last level, keeps the pass fields and counts the level; the fields clear once the game level has passed it.
    function test_RecordMintKeepsPassUntilGameLevelPassesIt() public {
        uint24 last = 24;
        host.seed(PLAYER, _passWord(3, last, last, 5), last);
        uint256 scoreBefore = host.score(PLAYER, 0, last);

        host.record(PLAYER, last + 1, 400);
        uint256 packed = host.packedOf(PLAYER);
        (uint256 passType, uint256 frozenUntil) = _passFields(packed);
        assertEq(passType, 3, "whale pass type kept at its last level");
        assertEq(frozenUntil, last, "freeze kept at its last level");
        assertEq((packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24, 6, "level past the freeze counts");
        assertEq(packed & BitPackingLib.MASK_24, last + 1, "last level is the ticket level");
        assertGe(host.score(PLAYER, 0, last), scoreBefore, "pass bonus still scored at the game level");

        host.seed(PLAYER, packed, last + 1);
        host.record(PLAYER, last + 2, 400);
        packed = host.packedOf(PLAYER);
        (passType, frozenUntil) = _passFields(packed);
        assertEq(passType, 0, "pass type cleared once the game level passed the freeze");
        assertEq(frozenUntil, 0, "freeze cleared once the game level passed the freeze");
        assertEq((packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24, 7);
        assertEq(packed & BitPackingLib.MASK_24, last + 2);
    }
}
