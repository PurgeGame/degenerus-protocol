// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {AffiliateEarningsLib as E} from "../../contracts/libraries/AffiliateEarningsLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

contract AffiliateStorageReuseTest is Test {
    mapping(uint24 => uint256) private ledger;

    function add(uint256 word, uint24 level, uint256 amount) external pure returns (uint256, uint256, uint256) {
        return E.add(word, level, amount);
    }

    function testFuzz_allRolloverDistancesPreserveScoresBonusAndCache(uint256 seed, uint256 cacheSeed) public {
        uint256 cache = cacheSeed & ((uint256(1) << 66) - 1);
        uint256 word = cache << 189;
        uint24 level = 1;
        for (uint256 i; i < 48; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            level += uint24(seed % 12);
            uint256 amount = 1 + ((seed >> 16) & ((uint256(1) << 36) - 1));
            uint256 accepted = amount;
            if (accepted > E.LIVE_CAP - ledger[level]) accepted = E.LIVE_CAP - ledger[level];
            ledger[level] += accepted;
            uint256 total;
            uint256 actualAccepted;
            (word, total, actualAccepted) = E.add(word, level, amount);
            assertEq(total, ledger[level]);
            assertEq(actualAccepted, accepted);
            assertEq(word >> 189, cache, "cache survives rollover");
            assertEq(word >> 255, 0);
            for (uint24 age; age < 9; ++age) {
                if (age >= level) break;
                uint24 old = level - age;
                assertEq(E.score(word, old), age < 2 ? ledger[old] : 0, "exact-score lifetime");
            }
            // All current-level alignments reachable for an inactive account.
            for (uint24 current = level - 1; current <= level + 7; ++current) {
                uint256 rawProduct;
                uint256 compactProduct;
                for (uint24 offset = 1; offset <= 5 && offset < current; ++offset) {
                    uint24 old = current - offset;
                    rawProduct += ledger[old] * PriceLookupLib.priceForLevel(old);
                    compactProduct += E.bonusScore(word, old) * PriceLookupLib.priceForLevel(old);
                }
                assertEq(_points(compactProduct), _points(rawProduct), "activity bonus parity");
            }
        }
    }

    function test_zeroDoesNotInitializeOrAdvanceAndHugeInputSaturates() public pure {
        (uint256 word,, uint256 accepted) = E.add(0, 5, 0);
        assertEq(word, 0);
        assertEq(accepted, 0);
        (word,, accepted) = E.add(word, 5, type(uint256).max);
        assertEq(accepted, E.LIVE_CAP);
        uint256 before_ = word;
        (word,, accepted) = E.add(word, 6, 0);
        assertEq(word, before_);
        (word,, accepted) = E.add(word, 5, type(uint256).max);
        assertEq(word, before_);
        assertEq(accepted, 0);
    }

    function test_maximumTagAndBothValidUplineIdsFit() public pure {
        uint256 cache = (uint256(1) << 66) - 1;
        (uint256 word,,) = E.add(cache << 189, type(uint24).max, type(uint256).max);
        assertEq(uint24(word >> 165), type(uint24).max);
        assertEq(word >> 189, cache);
        assertEq(word >> 255, 0);
        assertEq(E.score(word, type(uint24).max), E.LIVE_CAP);
    }

    function testFuzz_oldAndZeroCreditsAreNoOps(uint256 cache, uint256 amount) public pure {
        cache &= (uint256(1) << 66) - 1;
        (uint256 word,,) = E.add(cache << 189, 8, 37);
        (word,,) = E.add(word, 9, 41);
        for (uint24 level; level < 9; ++level) {
            (uint256 updated, uint256 total, uint256 accepted) = E.add(word, level, amount);
            assertEq(updated, word, "invalid target cannot mutate score, tag or cache");
            assertEq(total, amount == 0 ? E.score(word, level) : 0);
            assertEq(accepted, 0);
        }
        (uint256 empty, uint256 score_, uint256 delta) = E.add(cache << 189, 0, type(uint256).max);
        assertEq(empty, cache << 189);
        assertEq(score_, 0);
        assertEq(delta, 0);
    }

    function test_clippedHistoryAloneSaturatesAtMinimumPrice() public pure {
        (uint256 word,,) = E.add(0, 1, E.LIVE_CAP);
        (word,,) = E.add(word, 3, 1);
        assertEq(E.bonusScore(word, 1), 500_000);
        assertEq(_points(E.bonusScore(word, 1) * PriceLookupLib.priceForLevel(1)), 50);
    }

    function _points(uint256 product) private pure returns (uint256) {
        uint256 volume = product * 10_000 / (2000 * 1000);
        uint256 points = volume <= 5 ether ? volume * 4 / 1 ether : 20 + (volume - 5 ether) * 3 / 2 ether;
        return points > 50 ? 50 : points;
    }
}
