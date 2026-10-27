// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "./BucketSeed.sol";
import {BafBoardSeed} from "./BafBoardSeed.sol";

/// @dev Controlled, committed resolver state, not a replay of the first 99 levels.
///      Production bytecode is restored before the real request and measured advance.
contract CenturyConsolidationSeeder is DegenerusGame, BucketSeed {
    /// @dev The century state for the 48-round schedule (pools below 500 ETH).
    function seed(uint256 word, uint128 nextPool, uint128 futurePool) external {
        seedRounds(word, nextPool, futurePool, 48);
    }

    /// @dev The century state with the minted-level buckets of a `rounds`-round schedule seeded. Above
    ///      48 rounds the far-future queues are four times as deep, so the doubled samples still
    ///      draw distinct wallets.
    function seedRounds(uint256 word, uint128 nextPool, uint128 futurePool, uint256 rounds) public {
        uint24 day = _wallDay();
        level = 99;
        // Real maximum supply, with prior transition coverage committed.
        for (uint256 i = _deityCount(); i < 32; ++i) {
            _seedDeity(address(uint160(0xDE170000 + i)));
        }
        purchaseStartDay = day - 8; // accelerated skim trough; preserve the fixture's minimum-rate shape
        dailyIdx = day - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _setDecWindowOpen(true);
        currentPrizePool = 0;
        _setPrizePools(nextPool, futurePool);
        _setLevelPrizePool(98, (uint256(nextPool) * 8) / 10);
        _setLevelPrizePool(99, (uint256(nextPool) * 9) / 10);
        // Seed + 23 ETH surplus share + the 1% insurance skim of nextPool reaches the x00
        // dump, whose 40% must move the 17 ETH (+ a quarter of the skim) the pinned
        // BAF pools were tuned for.
        yieldAccumulator = 18.25 ether + uint256(nextPool) / 400;

        // The synthetic jump skips the bootstrap cohorts at levels 2..100.
        // Retire only their physical queue headers before binding the century's
        // separately seeded population; production never discards a live queue.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage oldQueue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(oldQueue.slot, 0) }
        }

        // Perpetual tickets populate every BAF candidate level in a live game. The far-future
        // scatter bands sample lvl+2..lvl+5 (102..105, revisited by every round pair of its band)
        // and lvl+6..lvl+99 (106..199). Holders are wholly synthetic (not the SDGNRS/VAULT
        // deities, which would repeat identically across all 98 levels) and keyed by (level,
        // slot index), so every lane holds a different wallet. Band 2's levels get a deep pool
        // (2048) and band 3's 128; both exceed the sampler's 8-lane window, and both are
        // multiples of eight, so a BAF winner's first ticket roll onto a level starts a fresh
        // queue word.
        uint256 depth = farDepth(rounds);
        for (uint24 target = 102; target <= 105; ++target) {
            for (uint256 i; i < 2048 * depth; ++i) {
                address p = address(uint160(0xFA000000 + (uint256(target) - 102) * 2048 * depth + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }
        for (uint24 target = 106; target <= 199; ++target) {
            for (uint256 i; i < 128 * depth; ++i) {
                address p = address(uint160(0xFB000000 + (uint256(target) - 106) * 128 * depth + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }

        // The minted-level scatter rounds (rounds / 4 at level 100, then rounds / 4 at level 101;
        // 12 and 12 for 48 rounds) each read four
        // entries of one packed word of the (level, trait) bucket that hash2(base, round) selects,
        // base = hash2(word, BAF tag). Each selected bucket holds 2048 distinct wallets; a bucket
        // selected by two rounds keeps the first round's wallets (for the fixture's words such
        // rounds read different packed words, so no wallet is a candidate twice).
        uint256 board = BafBoardSeed.context(100, word, rounds);
        for (uint256 round; round < rounds / 2; ++round) {
            uint24 target = round < rounds / 4 ? 100 : 101;
            uint8 trait = uint8(uint32(board) >> ((round % 4) * 8));
            if (_seedBucketLen(target, trait) < 2048) {
                _seedBucketDistinct(target, trait, 2048, uint160(0xC3700000 + round * 4096));
            }
        }
        // Sealing is constant work regardless of the entrant population.
        decBattleRounds[100].count = 1_000_000;
    }

    /// @dev Far-future queue depth multiplier of a `rounds`-round schedule.
    function farDepth(uint256 rounds) public pure returns (uint256) {
        return rounds > 48 ? 4 : 1;
    }
}
