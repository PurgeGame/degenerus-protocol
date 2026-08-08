// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @title PurchaseDripHarness -- drives the live purchase-phase daily drip
/// @notice Extends the production DegenerusGameJackpotModule so `payDailyJackpot`
///         (guard-free by design; the Game parent controls access in production)
///         executes the real purchase-phase drip split in THIS contract's storage.
///         The harness only adds state seeders and read-only views; it overrides
///         NO production logic.
/// @dev Test-only. NO contracts/*.sol is mutated; this harness lives entirely under test/.
contract PurchaseDripHarness is DegenerusGameJackpotModule {
    /// @dev Push `count` distinct, non-zero holder addresses into lvlTraitEntry[lvl][traitId]
    ///      so bucket winner selection (which allows duplicates via `% effectiveLen`) never
    ///      resolves to address(0).
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        address[] storage holders = lvlTraitEntry[lvl][traitId];
        for (uint256 i; i < count; ++i) {
            holders.push(address(base + uint160(i + 1)));
        }
    }

    function exposed_setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function exposed_getPrizePools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function yieldAccumulatorView() external view returns (uint256) {
        return yieldAccumulator;
    }

    function claimablePoolView() external view returns (uint256) {
        return uint256(claimablePool);
    }
}

/// @title PurchaseDripSplitTest -- pins the purchase-phase daily drip's 75/23/2 split
/// @notice The purchase-phase daily takes a 1% slice of futurePrizePool and partitions it
///         75% ticket leg / 23% ETH leg / 2% insurance skim, with BOTH the ticket leg and
///         the skim sized off the WHOLE slice (so the ETH leg keeps the two flooring
///         remainders) and the skim credited to yieldAccumulator. These tests are the
///         drift defense for that arithmetic:
///         - exact observable deltas: nextPrizePool += 75% of slice, yieldAccumulator
///           += 2% of slice, futurePrizePool -= (ticket leg + skim + ETH actually paid)
///         - conservation with real winners: the future-pool debit equals ticket leg +
///           skim + the claimable ETH credited, and the paid ETH never exceeds the
///           23%-plus-remainders leg
///         - a fuzz over pool sizes covering the zero-slice and dust boundaries
///         - source-text pins on the two bps constants and the accumulator credit
contract PurchaseDripSplitTest is Test {
    /// @dev Mirror of the production constants (DegenerusGameJackpotModule).
    uint16 internal constant PURCHASE_REWARD_JACKPOT_TICKET_BPS = 7500;
    uint16 internal constant PURCHASE_INSURANCE_BPS = 200;

    /// @dev A level whose +1 price tier is a clean 0.04 ETH, matching the
    ///      JackpotSingleCallCorrectness fixture choice.
    uint24 internal constant LVL = 110;

    PurchaseDripHarness internal h;

    function setUp() public {
        h = new PurchaseDripHarness();
    }

    function _word() internal pure returns (uint256) {
        return uint256(keccak256("purchase-drip-split-fixed-word"));
    }

    /// @dev Expected partition of a future-pool balance's 1% slice, computed exactly as
    ///      the contract does: both legs floored off the whole slice, ETH leg = remainder.
    function _expectedSplit(uint256 futureBal)
        internal
        pure
        returns (uint256 slice, uint256 ticketLeg, uint256 insurance, uint256 ethLeg)
    {
        slice = futureBal / 100;
        if (slice != 0) {
            ticketLeg = (slice * PURCHASE_REWARD_JACKPOT_TICKET_BPS) / 10_000;
            insurance = (slice * PURCHASE_INSURANCE_BPS) / 10_000;
            ethLeg = slice - ticketLeg - insurance;
        }
    }

    // =========================================================================
    // Exact partition with empty trait boards: no ETH winner exists, so the
    // 23% leg goes unpaid and stays in futurePrizePool -- the observable deltas
    // isolate the ticket leg and the insurance skim exactly.
    // =========================================================================

    /// @notice 75% of the slice moves future -> next, 2% moves future -> yieldAccumulator,
    ///         and nothing else leaves the future pool when no bucket has holders.
    ///         A non-round balance exercises both flooring remainders landing in the ETH leg.
    function test_dripSplit_emptyBoards_exactPartition() public {
        uint128 future0 = 1_234_567_890_123_456_789_012; // ~1234.57 ether, deliberately non-round
        h.exposed_setPrizePools(0, future0);

        h.payDailyJackpot(false, LVL, _word());

        (uint256 slice, uint256 ticketLeg, uint256 insurance, ) = _expectedSplit(future0);
        (uint128 nextAfter, uint128 futureAfter) = h.exposed_getPrizePools();

        assertEq(nextAfter, ticketLeg, "next gains exactly 75% of the slice");
        assertEq(h.yieldAccumulatorView(), insurance, "yieldAccumulator gains exactly 2% of the slice");
        assertEq(
            uint256(futureAfter),
            uint256(future0) - ticketLeg - insurance,
            "future debited by exactly ticket leg + skim (unpaid ETH leg stays)"
        );
        assertEq(h.claimablePoolView(), 0, "no claimable credited with empty boards");
        // The skim is 2% of the WHOLE slice, not 2% of the 25% ETH leg (4x smaller).
        assertEq(insurance, (slice * 200) / 10_000, "skim sized off the whole drip");
    }

    /// @notice Partition deltas hold exactly for arbitrary pool sizes, including the
    ///         zero-slice (futureBal < 100) and dust (slice too small to floor a leg)
    ///         boundaries, and the two legs never exceed the slice.
    function testFuzz_dripSplit_partition(uint128 future0) public {
        future0 = uint128(bound(future0, 0, 1e30));
        h.exposed_setPrizePools(0, future0);

        h.payDailyJackpot(false, LVL, _word());

        (, uint256 ticketLeg, uint256 insurance, ) = _expectedSplit(future0);
        (uint128 nextAfter, uint128 futureAfter) = h.exposed_getPrizePools();

        assertEq(nextAfter, ticketLeg, "next delta == floored 75% leg");
        assertEq(h.yieldAccumulatorView(), insurance, "yield delta == floored 2% skim");
        assertEq(
            uint256(futureAfter),
            uint256(future0) - ticketLeg - insurance,
            "future debit == ticket leg + skim exactly (no ETH paid)"
        );
        assertLe(ticketLeg + insurance, uint256(future0) / 100, "legs partition within the slice");
    }

    // =========================================================================
    // Conservation with real winners: seed the day's four winning-trait buckets
    // so the ETH leg actually pays, and prove the single packed-slot RMW debits
    // future by exactly ticket leg + skim + paid ETH.
    // =========================================================================

    /// @notice With populated boards the future-pool debit is exactly the ticket leg +
    ///         the skim + the claimable ETH credited, the paid ETH stays within the
    ///         23%-plus-remainders leg, and the skim/ticket deltas are unchanged by payouts.
    function test_dripSplit_seededWinners_conservation() public {
        // On a fresh harness the hero pool is empty, so the day's main traits are exactly
        // getRandomTraits(word) -- the same reproduction JackpotSingleCallCorrectness uses.
        uint8[4] memory traitIds = JackpotBucketLib.getRandomTraits(_word());
        for (uint8 b; b < 4; ++b) {
            // 25 distinct holders per bucket (max purchase-phase bucket count is 20) on
            // disjoint address ranges.
            h.seedBucket(LVL, traitIds[b], 25, uint160(uint256(b + 1) * 1_000_000_000));
        }

        uint128 future0 = 1000 ether;
        h.exposed_setPrizePools(0, future0);

        h.payDailyJackpot(false, LVL, _word());

        (, uint256 ticketLeg, uint256 insurance, uint256 ethLeg) = _expectedSplit(future0);
        (uint128 nextAfter, uint128 futureAfter) = h.exposed_getPrizePools();
        uint256 paidEth = h.claimablePoolView();

        assertGt(paidEth, 0, "fixture must be non-vacuous: the ETH leg paid winners");
        assertLe(paidEth, ethLeg, "paid ETH never exceeds the 23%-plus-remainders leg");
        assertEq(nextAfter, ticketLeg, "payouts do not perturb the 75% ticket leg");
        assertEq(h.yieldAccumulatorView(), insurance, "payouts do not perturb the 2% skim");
        assertEq(
            uint256(future0) - uint256(futureAfter),
            ticketLeg + insurance + paidEth,
            "future debit == ticket leg + skim + paid ETH exactly"
        );
    }

    // =========================================================================
    // Source-text pins: the split constants and the accumulator credit must stay
    // in the module verbatim, defending the 75/23/2 shape against refactors that
    // would slip past behavior tests rebuilt around a changed split.
    // =========================================================================

    function test_sourcePins_dripSplitConstants() public view {
        string memory src = vm.readFile("contracts/modules/DegenerusGameJackpotModule.sol");
        assertEq(
            _countOccurrences(src, "PURCHASE_REWARD_JACKPOT_TICKET_BPS = 7500"),
            1,
            "ticket leg constant is 7500 bps"
        );
        assertEq(
            _countOccurrences(src, "PURCHASE_INSURANCE_BPS = 200"),
            1,
            "insurance skim constant is 200 bps"
        );
        assertEq(
            _countOccurrences(src, "yieldAccumulator += insuranceCut"),
            1,
            "skim credits yieldAccumulator"
        );
    }

    function _countOccurrences(string memory haystack, string memory needle)
        internal
        pure
        returns (uint256 count)
    {
        bytes memory h_ = bytes(haystack);
        bytes memory n_ = bytes(needle);
        if (n_.length == 0 || h_.length < n_.length) return 0;
        for (uint256 i; i <= h_.length - n_.length; ++i) {
            bool matched = true;
            for (uint256 j; j < n_.length; ++j) {
                if (h_[i + j] != n_[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) ++count;
        }
    }
}
