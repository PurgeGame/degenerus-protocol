// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ActivityAffiliateCacheFixture, ActivityAffiliateCacheHost} from "./helpers/ActivityAffiliateCacheFixture.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
import {activityScoreOf} from "../helpers/ActivityScoreOf.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract ActivityCacheQuestStub {
    function effectiveBaseStreakAndAfking(uint32) external pure returns (uint32, bool) { return (17, false); }
}

contract ActivityAffiliateCacheTest is ActivityAffiliateCacheFixture {
    uint256 private constant DURABLE_MASK = (uint256(1) << 48) - 1 | (uint256(type(uint32).max) << 72);
    function testFuzz_CachedScorePreservesScoreAndOtherFields(
        uint256 packed, uint32 streak, uint24 lvl, uint24 basis, address player, uint128 earnings
    ) public {
        packed = _stale(packed, lvl);
        uint32 id = uint32(packed >> 224);
        host.seed(player, packed, lvl);
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
            assertEq((afterPacked >> 185) & 0xffffff, lvl);
            assertEq((afterPacked >> 209) & 63, affiliate.affiliateBonusPointsBest(lvl, id));
        }
        assertEq(host.score(player, streak, basis), expected);
    }

    function testFuzz_CacheHitHasNoAffiliateCallOrStore(uint256 packed, uint24 lvl, uint32 streak) public {
        packed = _withId(_stale(packed, lvl) | 1, PLAYER_ID);
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
        host.seed(PLAYER, _withId(_stale(1, 6), PLAYER_ID), 6);
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
        assertEq((host.packedOf(PLAYER) >> 185) & 0xffffff, 7);
    }

    function test_RecordMintPiggybacksActualLevelCache() public {
        _seedEarnings(23, PLAYER_ID, 100);
        _seedEarnings(24, PLAYER_ID, 50_000);
        host.seed(PLAYER, _withId(0, PLAYER_ID), 24);
        host.record(PLAYER, 25, 400);
        uint256 packed = host.packedOf(PLAYER);
        assertEq((packed >> 185) & 0xffffff, 24, "actual game level, not target25");
        assertEq((packed >> 209) & 63, affiliate.affiliateBonusPointsBest(24, PLAYER_ID));
        assertTrue(affiliate.affiliateBonusPointsBest(25, PLAYER_ID) != ((packed >> 209) & 63));
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
        ActivityAffiliateCacheHost(ContractAddresses.GAME).seed(PLAYER, _withId(1, PLAYER_ID), 24);
        vm.etch(ContractAddresses.GAME, type(DegenerusGame).runtimeCode);
        vm.etch(ContractAddresses.GAME_MINER_MODULE, type(DegenerusGameMinerModule).runtimeCode);
        vm.etch(ContractAddresses.QUESTS, type(ActivityCacheQuestStub).runtimeCode);
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
        ActivityAffiliateCacheHost(ContractAddresses.GAME).seed(PLAYER, _withId(packed, PLAYER_ID), 24);
        vm.etch(ContractAddresses.GAME, type(DegenerusGame).runtimeCode);
        vm.etch(ContractAddresses.GAME_MINER_MODULE, type(DegenerusGameMinerModule).runtimeCode);
        vm.etch(ContractAddresses.QUESTS, type(DegenerusQuests).runtimeCode);
        game = DegenerusGame(payable(ContractAddresses.GAME));
        quests = DegenerusQuests(ContractAddresses.QUESTS);
    }

    function testFuzz_PermissionlessCacheCannotOpenGrowthGate(uint8 curse) public {
        uint256 packed = uint256(curse) << BitPackingLib.CURSE_COUNT_SHIFT;
        (DegenerusGame game, DegenerusQuests quests) = _productionGame(packed);
        (bool mayBet, bool rewarded,) = quests.marketBetGates(PLAYER, 24);
        assertFalse(mayBet); assertFalse(rewarded);
        (uint256 expected,) = game.playerActivityScore(PLAYER);
        vm.startStateDiffRecording();
        vm.prank(address(0xBAD));
        (uint256 cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, expected);
        (,uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(game));
        assertEq(stores, 0);
        assertEq(game.mintPackedFor(PLAYER), _withId(packed, PLAYER_ID));
        (mayBet, rewarded,) = quests.marketBetGates(PLAYER, 24);
        assertFalse(mayBet); assertFalse(rewarded);
    }

    function testFuzz_MutableOnlyWordsNeverPersistCache(uint8 curse) public {
        uint256 packed = uint256(curse) << BitPackingLib.CURSE_COUNT_SHIFT;
        host.seed(PLAYER, _withId(packed, PLAYER_ID), 24);
        uint256 expected = host.score(PLAYER, 17, 25);
        vm.startStateDiffRecording();
        assertEq(host.scoreCached(PLAYER, 17, 25), expected);
        (,uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        assertEq(stores, 0); assertEq(host.packedOf(PLAYER), _withId(packed, PLAYER_ID));
    }
    function test_HitsAndHistoryFreeWalletsSkipMinerDispatch() public {
        (DegenerusGame game,) = _productionGame(1 | (uint256(24) << 185));
        vm.etch(ContractAddresses.GAME_MINER_MODULE, hex"5f5ffd");
        (uint256 cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, activityScoreOf(address(game), PLAYER));
        (game,) = _productionGame(0);
        vm.etch(ContractAddresses.GAME_MINER_MODULE, hex"5f5ffd");
        (cached,) = game.playerActivityScoreCached(PLAYER);
        assertEq(cached, activityScoreOf(address(game), PLAYER));
        assertEq(game.mintPackedFor(PLAYER), _withId(0, PLAYER_ID));
    }

}
