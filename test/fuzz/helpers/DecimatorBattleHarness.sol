// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameDecimatorModule} from "../../../contracts/modules/DegenerusGameDecimatorModule.sol";

contract DecimatorBattleHarness is DegenerusGameDecimatorModule {
    function open(uint24 lvl) external {
        level = lvl - 1;
        decWindowOpen = true;
        decBattleRounds[lvl].openedDay = _simulatedDayIndex();
    }

    function seal(uint24 lvl, uint128 pool, uint256 word) external returns (uint256 returned) {
        decWindowOpen = false;
        returned = this.runDecimatorJackpot(pool, lvl, word);
        claimablePool += pool - uint128(returned);
    }

    function roundOf(uint24 lvl) external view returns (DecBattleRound memory) {
        return decBattleRounds[lvl];
    }

    /// @dev A retained node as the Lens reports it: exact score words and the full ordering key.
    struct Node {
        uint256 high;
        uint256 low;
        uint256 key;
    }

    struct Entry {
        address owner;
        uint256 stack;
        uint32 chips;
    }

    function nodeOf(uint24 lvl, uint8 i) external view returns (Node memory n) {
        DecBattleNode storage stored = decBattleHeap[i];
        uint64 id = uint64(stored.head);
        n.high = stored.head >> 64;
        n.low = stored.low;
        n.key = (uint256(keccak256(abi.encode(keccak256("decimator.battle.tie.v1"), decBattleRounds[lvl].rngWord, lvl, id)))
            & ~uint256(type(uint64).max)) | id;
    }

    function entryOf(uint24 lvl, uint64 id) external view returns (Entry memory e) {
        e.owner = decBattleOwners[(uint256(lvl) << 64) | id];
        uint256 packed = decBattleEntries[lvl][e.owner];
        e.stack = packed >> 96;
        e.chips = uint32(packed >> 64);
    }

    function passesOf(address p) external view returns (uint256) {
        return whalePassClaims[p];
    }

    function balanceOf(address p) external view returns (uint256) {
        return _claimableOf(p);
    }

    function reserved() external view returns (uint256) {
        return claimablePool;
    }

    function queue() external view returns (uint256) {
        return decBattleQueue;
    }

    function future() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    function pendingFuture() external view returns (uint256) {
        (, uint128 f) = _getPendingPools();
        return f;
    }

    function freeze(bool value) external {
        prizePoolFrozen = value;
        rngLockedFlag = value;
    }

    function terminal() external {
        gameOver = true;
    }

    function forceCount(uint24 lvl, uint64 count) external {
        decBattleRounds[lvl].count = count;
    }
}
