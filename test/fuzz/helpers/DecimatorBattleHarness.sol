// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameDecimatorModule} from "../../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {WalletSeed} from "../../helpers/WalletSeed.sol";

contract DecimatorBattleHarness is DegenerusGameDecimatorModule, WalletSeed {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly { value := sload(slot) }
    }

    function open(uint24 lvl) external {
        level = lvl - 1;
        _setDecWindowOpen(true);
        decBattleRounds[lvl].openedDay = _simulatedDayIndex();
    }

    function seal(uint24 lvl, uint128 pool, uint256 word) external returns (uint256 returned) {
        _setDecWindowOpen(false);
        if (decBattleRounds[lvl].phase == 0) {
            require(decBattleQueue == 0 && word > RNG_WORD_WAITING, "session not ready");
            rngWordCurrent = word;
            _setRngSessionPublished(true);
            _setRngRequestActive(false);
            ticketsFullyProcessed = true;
            humanReadComplete = true;
            dailyIdx = _simulatedDayIndex();
        }
        returned = this.runDecimatorJackpot(pool, lvl, word);
        claimablePool += pool - uint128(returned);
        // This harness exercises original-only settlement. Generated integration uses the
        // separate locked Game-context jackpot harness and its real delegate dispatcher.
        if (returned == 0) {
            decJackpotPlans[lvl].mode = 0;
        }
    }

    function roundOf(uint24 lvl) external view returns (DecBattleRound memory) {
        return decBattleRounds[lvl];
    }

    /// @dev A retained node as the Lens reports it: its score and the full ordering key.
    struct Node {
        uint256 score;
        uint256 key;
    }

    struct Entry {
        address owner;
        uint256 stack;
        uint32 chips;
    }

    function nodeOf(uint24 lvl, uint8 i) external view returns (Node memory n) {
        uint256 stored = decBattleHeap[i];
        uint64 id = uint64(stored);
        n.score = stored >> 64;
        n.key = (uint256(keccak256(abi.encode(keccak256("decimator.battle.tie.v1"), _currentRngWord(), lvl, id)))
            & ~uint256(type(uint64).max)) | id;
    }

    function activeWord() external view returns (uint256) { return _lootboxWord(_rngReadBuffer()); }

    /// @dev The stack in wei of virtual chips, as the Lens reports it.
    function entryOf(uint24 lvl, uint64 id) external view returns (Entry memory e) {
        uint256 entry = decBattleEntries[(uint256(lvl) << 64) | id];
        e.owner = address(uint160(entry));
        e.stack = (entry >> 190);
        e.chips = uint32((entry >> 160) & 0x3FFFFFFF);
    }

    function passesOf(address p) external view returns (uint256) {
        return _halfPassesOf(p);
    }

    function balanceOf(address p) external view returns (uint256) {
        return _claimableOf(_walletIdOf(p));
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

    function referenceOf() external view returns (uint64, uint40, uint256) {
        return (decPreviousStack, decPreviousCount, _decAutomaticCap());
    }

    function forceCursor(uint24 lvl, uint64 cursor) external { decBattleRounds[lvl].cursor = cursor; }

    function forceCount(uint24 lvl, uint40 count) external {
        decBattleRounds[lvl].count = count;
    }
}
