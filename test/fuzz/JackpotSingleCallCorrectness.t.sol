// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title JackpotSingleCallHarness -- drives the live single-call daily-ETH jackpot surface
/// @notice Extends the production DegenerusGameJackpotModule so the inherited (external)
///         `runTerminalJackpotWork` executes the live `_processDailyEth -> _processBucket ->
///         _addClaimableEth` path in THIS contract's storage. The harness only adds a
///         `lvlTraitEntry` seeder + read-only accounting views; it overrides NO production
///         logic. `runTerminalJackpotWork` pays the fixed DAILY_ETH_MAX_WINNERS=305 terminal
///         geometry (bucket counts 152/104/48/1), in ONE call -- exactly the JGAS-03 surface.
/// @dev Test-only. NO contracts/*.sol is mutated; this harness lives entirely under test/.
contract JackpotSingleCallHarness is DegenerusGameJackpotModule, BucketSeed {
    /// @dev Push `count` distinct, non-zero holder addresses into lvlTraitEntry[lvl][traitId].
    ///      Distinct addresses make per-winner claimable accounting unambiguous; the seeded
    ///      pool is larger than any bucket's winner count so winner selection (which allows
    ///      duplicates via `% effectiveLen`) never resolves to address(0).
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        _seedBucketDistinct(lvl, traitId, count, base);
    }

    // -- read-only accounting views (the credit sinks _processDailyEth writes) --

    function claimableOf(address who) external view returns (uint256) {
        return _claimableOf(_walletIdOf(who));
    }

    function whalePassOf(address who) external view returns (uint256) {
        return _halfPassesOf(who);
    }

    function claimablePoolView() external view returns (uint256) {
        return uint256(claimablePool);
    }

    function futurePoolView() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    function bucketLen(uint24 lvl, uint8 traitId) external view returns (uint256) {
        return _bucketLength(lvl, traitId);
    }
}

/// @title JackpotSingleCallCorrectness -- JGAS-03 single-call 305-winner proofs
/// @notice After the JGAS-02 two-call-split removal, the daily ETH jackpot pays all 305
///         winners (buckets 152/104/48/1 at max scale) correctly in ONE call:
///         - every bucket paid, exact per-winner amounts, none missed, none double-paid
///         - conservation: total ETH credited (claimable + whale-pass) == the distributed pool
///         - the single call fits under the mainnet block gas limit (worst-case-FIRST)
///         - the split path is behaviorally gone (no resume stage entered) + grep-clean
///
/// @dev Drives the live `runTerminalJackpotWork` entry (msg.sender==GAME guard satisfied via prank)
///      which routes straight into the single-call `_processDailyEth` at the 305 ceiling.
contract JackpotSingleCallCorrectness is Test {
    JackpotSingleCallHarness internal h;

    /// @dev Mirror of the production constants (DegenerusGameJackpotModule).
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    /// @dev FINAL_DAY_SHARES_PACKED = [6000, 1333, 1333, 1334] bps (runTerminalJackpotWork path).
    uint64 internal constant FINAL_DAY_SHARES_PACKED =
        (uint64(6000)) |
            (uint64(1333) << 16) |
            (uint64(1333) << 32) |
            (uint64(1334) << 48);

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for
    ///      the test harness; the JGAS-03 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev JackpotEthWin topic0 (for vm.recordLogs filtering).
    bytes32 internal constant JACKPOT_ETH_WIN_TOPIC =
        keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    /// @dev A target level whose +1 price tier is a clean 0.04 ETH (unit = 0.01 ETH).
    uint24 internal constant TARGET_LVL = 110;
    /// @dev Terminal pool; the terminal buckets are the fixed 152/104/48/1.
    uint256 internal constant POOL_WEI = 1000 ether;

    function setUp() public {
        h = new JackpotSingleCallHarness();
    }

    // =========================================================================
    // Task 1 — 305-winner single-call correctness + conservation
    // =========================================================================

    /// @notice JGAS-03: at max scale the daily-ETH jackpot pays exactly DAILY_ETH_MAX_WINNERS=305
    ///         winners across the 4 buckets (152 + 104 + 48 + 1) in ONE call -- every bucket paid,
    ///         each winner credited its exact per-winner bucket amount, none missed, none double
    ///         credited within its bucket, and total ETH credited == the distributed pool.
    function testSingleCallPaysAll305WithConservation() public {
        (uint8[4] memory traitIds, uint256 effectiveEntropy) = _deriveTraits(_word());

        // Confirm the bucket geometry IS the 305 ceiling (152/104/48/1) BEFORE driving the call.
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effectiveEntropy);
        assertEq(_total(bc), 305, "terminal total == 305");
        _assertCountMultiset(bc, [uint16(152), 104, 48, 1]);

        // Seed each of the 4 winning-trait buckets with distinct holders (one disjoint address
        // range per trait), more than any bucket's winner count so no winner resolves to zero.
        _seedAllBuckets(traitIds);

        // Drive the live single-call jackpot (msg.sender==GAME via prank).
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        (, uint256 paidWei) = h.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());

        // --- Correctness: exactly 305 JackpotEthWin emissions, one per paid winner slot. ---
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethWins;
        uint256 emittedSum;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == JACKPOT_ETH_WIN_TOPIC) {
                ++ethWins;
                (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
                emittedSum += amount;
            }
        }
        assertEq(ethWins, 305, "exactly 305 JackpotEthWin emissions (none missed, none extra)");

        // --- Conservation: total ETH that LEFT the distributable pool == paidWei. ---
        // The credit sinks are claimableWinnings (per-winner) + whalePassClaims (solo 75/25
        // split routes 25% to futurePrizePool). Sum every seeded holder's claimable delta plus
        // the solo whale-pass spend, and assert it equals the returned paidWei.
        uint256 totalClaimable = _sumSeededClaimable(traitIds);
        uint256 futureFromWhalePass = h.futurePoolView(); // started at 0; only whale-pass adds here
        assertEq(
            totalClaimable + futureFromWhalePass,
            paidWei,
            "conservation: claimable credits + whale-pass spend == paidWei (no leak, no overpay)"
        );

        // claimablePool liability tracks the per-winner claimable exactly.
        assertEq(h.claimablePoolView(), totalClaimable, "claimablePool == sum of per-winner claimable");

        // The pool is never overpaid: paidWei <= POOL_WEI (unit-rounding dust returns to caller).
        assertLe(paidWei, POOL_WEI, "paidWei never exceeds the input pool (no overpay)");
        // And it is a meaningful payout (not a vacuous 0).
        assertGt(paidWei, 0, "the single call actually distributed ETH");
    }

    /// @notice JGAS-03 (exact per-winner amounts, no double-pay within a bucket): for the three
    ///         normal (non-solo) buckets, every distinct seeded holder's claimable balance is a
    ///         whole multiple of that bucket's per-winner amount (share/count). A holder credited
    ///         twice (duplicate winner draw) shows 2x -- which is correct single-draw accounting,
    ///         NOT a double-pay; the invariant that breaks under a double-pay bug is that the
    ///         summed credits stay == the bucket share. We assert each bucket's summed claimable
    ///         equals its computed unit-rounded share (exact, none missed/over).
    function testPerBucketExactShareNoDoublePay() public {
        (uint8[4] memory traitIds, uint256 effectiveEntropy) = _deriveTraits(_word());
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effectiveEntropy);

        uint8 soloIdx = JackpotBucketLib.soloBucketIndex(effectiveEntropy);
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED, uint8(effectiveEntropy & 3)
        );
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            POOL_WEI, shareBps, bc, soloIdx
        );

        _seedAllBuckets(traitIds);
        vm.prank(ContractAddresses.GAME);
        h.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());

        // For each NON-solo bucket, the sum of its holders' claimable == its computed share,
        // and per-winner == share/count (exact, integer division floor; remainder dust stranded
        // only on the solo/remainder bucket). This proves exact amounts + no double/over-pay.
        for (uint8 b; b < 4; ++b) {
            if (b == soloIdx) continue; // solo handled separately (75/25 split)
            uint16 count = bc[b];
            if (count == 0) continue;
            uint256 perWinner = shares[b] / count;
            uint256 bucketSum = _sumBucketClaimable(traitIds[b], b, count);
            assertEq(
                bucketSum,
                perWinner * count,
                "non-solo bucket: summed claimable == perWinner * count (exact, no over/under-pay)"
            );
            assertGt(perWinner, 0, "non-solo per-winner amount is non-zero");
        }
    }

    /// @notice JGAS-03 fuzz: across a range of pools that still reach the 305 ceiling, the single
    ///         call always pays exactly 305 winners and never overpays the pool. (The 305 cap is
    ///         the fixed terminal geometry for any non-empty pool.)
    function testFuzz_SingleCall305AtMaxScale(uint96 extraWei) public {
        uint256 pool = 200 ether + bound(uint256(extraWei), 0, 5000 ether);
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effEntropy);
        assertEq(_total(bc), 305, "the terminal geometry is the 305 ceiling");

        _seedAllBuckets(traitIds);
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        (, uint256 paidWei) = h.runTerminalJackpotWork(pool, TARGET_LVL, _word(), gasleft());

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethWins;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == JACKPOT_ETH_WIN_TOPIC) ++ethWins;
        }
        assertEq(ethWins, 305, "fuzz: 305 winners paid in one call at max scale");
        assertLe(paidWei, pool, "fuzz: never overpays the pool");
    }

    // =========================================================================
    // Task 2 — single call fits the block gas limit (worst-case-first) + split gone
    // =========================================================================

    /// @notice JGAS-03 worst-case-FIRST gas fit: the theoretical worst case for the daily-ETH
    ///         path is the 305-winner max-scale single call (all 4 buckets, 152/104/48/1) -- no
    ///         daily-ETH path produces more winners (DAILY_ETH_MAX_WINNERS = 305 is the hard
    ///         cap, and MAX_BUCKET_WINNERS=248 never clips a 152 bucket). We measure THAT call's
    ///         gas (gasleft delta) and assert it is < the mainnet 30M block gas limit, i.e. it
    ///         fits with margin. Full peg calibration + the margin attribution to the removed
    ///         per-winner autoRebuyState SLOAD is Phase 319 / JGAS-04; this plan's bar is "fits".
    function testWorstCaseSingleCallFitsBlockGasLimit() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        // Establish this IS the worst case: 305 winners, the maximum the daily-ETH path emits.
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effEntropy);
        assertEq(_total(bc), 305, "worst case: 305 winners (the hard cap)");

        _seedAllBuckets(traitIds);

        // Measure the single call's gas consumption (gasleft delta around the external call).
        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        (, uint256 paidWei) = h.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasUsed = gasBefore - gasleft();

        assertGt(paidWei, 0, "the measured worst-case call actually paid out");
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "worst-case 305-winner single call fits under the 30M mainnet block gas limit"
        );
        // Record the measured number for the SUMMARY narration.
        emit log_named_uint("worst_case_305_winner_single_call_gas", gasUsed);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Phase 319 / JGAS-04 — worst-case-FIRST re-frame + freed-SLOAD delta attribution
    // =========================================================================

    /// @notice JGAS-04 worst-case-FIRST re-frame: assert the 305-winner max-scale single call IS the
    ///         daily-ETH worst case BEFORE measuring, then assert measured < 30M with margin and emit
    ///         the margin. 318-06 already proved 305 is structurally the max; JGAS-04 makes the
    ///         worst-case-first framing an explicit standalone assertion (the two hard caps:
    ///         DAILY_ETH_MAX_WINNERS = 305 and MAX_BUCKET_WINNERS = 248 which never clips a 152 bucket)
    ///         and records the 30M - measured margin for the SUMMARY.
    function testJgas04WorstCaseFirstReframeWithMargin() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        // Worst-case-FIRST (assert the scenario IS the max BEFORE measuring):
        //  (a) the bucket geometry reaches exactly the DAILY_ETH_MAX_WINNERS = 305 hard cap;
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effEntropy);
        assertEq(
            _total(bc),
            DAILY_ETH_MAX_WINNERS,
            "JGAS-04 worst case: 305 winners == DAILY_ETH_MAX_WINNERS (the daily-ETH hard cap)"
        );
        //  (b) no single bucket count can exceed MAX_BUCKET_WINNERS = 248, so the 152/104/48/1
        //      geometry is never clipped — 305-across-4-buckets is the true maximum work shape.
        for (uint8 b; b < 4; ++b) {
            assertLe(bc[b], 248, "JGAS-04 worst case: no bucket exceeds MAX_BUCKET_WINNERS = 248 (never clips 152)");
        }

        _seedAllBuckets(traitIds);

        // Measure the worst-case single call.
        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        (, uint256 paidWei) = h.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasUsed = gasBefore - gasleft();

        assertGt(paidWei, 0, "JGAS-04: the measured worst-case call actually paid out");
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "JGAS-04: the 305-winner worst case fits under the 30M mainnet block gas limit with margin"
        );

        // Emit the margin (30M - measured) for the SUMMARY.
        uint256 margin = MAINNET_BLOCK_GAS_LIMIT - gasUsed;
        assertGt(margin, 0, "JGAS-04: positive margin under the block limit");
        emit log_named_uint("jgas04_worst_case_305_winner_gas", gasUsed);
        emit log_named_uint("jgas04_margin_under_30M", margin);
    }


    /// @notice JGAS-03 split behaviorally gone: the daily-ETH jackpot at the 305 ceiling completes
    ///         in ONE call -- the full pool resolves with no second-call carry. We re-run the same
    ///         max-scale call and assert it fully resolves (paidWei + the unit-rounding dust ==
    ///         POOL_WEI) with no pending remainder that a resume stage would have to drain. There
    ///         is no STAGE_JACKPOT_ETH_RESUME to enter and no resumeEthPool to read/write -- the
    ///         single return value IS the whole distribution.
    function testNoResumeStageSingleCallFullyResolves() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());
        uint8 soloIdx = JackpotBucketLib.soloBucketIndex(effEntropy);
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effEntropy);
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED, uint8(effEntropy & 3)
        );
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            POOL_WEI, shareBps, bc, soloIdx
        );
        // The remainder (solo) bucket gets pool - distributed; the only ETH NOT paid is the
        // per-non-solo-bucket unit-rounding floor dust. There is no cross-call carry.
        uint256 expectedDust;
        for (uint8 b; b < 4; ++b) {
            if (b == soloIdx) continue;
            uint16 count = bc[b];
            if (count == 0) continue;
            uint256 perWinner = shares[b] / count;
            expectedDust += shares[b] - perWinner * count; // floor remainder within the bucket
        }

        _seedAllBuckets(traitIds);
        vm.prank(ContractAddresses.GAME);
        (, uint256 paidWei) = h.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());

        // Full resolution in one call: everything except the in-bucket rounding dust is paid.
        assertEq(
            paidWei + expectedDust,
            POOL_WEI,
            "single call fully resolves: paidWei + in-bucket rounding dust == pool (no resume carry)"
        );
    }


    /// @notice JGAS-03 preserved ceiling: every rotation of the terminal geometry is a
    ///         permutation of 152/104/48/1 = 305.
    function testPreservedTerminalCeiling() public pure {
        for (uint256 r; r < 4; ++r) {
            uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(r);
            assertEq(_total(bc), DAILY_ETH_MAX_WINNERS, "terminal geometry pays the 305 ceiling");
            _assertCountMultiset(bc, [uint16(152), 104, 48, 1]);
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev A fixed VRF word whose getRandomTraits() yields 4 distinct, non-gold trait IDs and a
    ///      gold-free quadrant set (so _pickSoloQuadrant takes the entropy-rotation branch and no
    ///      deity virtual entries appear -- deityBySymbol is empty in the harness anyway).
    function _word() internal pure returns (uint256) {
        uint256 word = uint256(keccak256("jgas03-single-call-fixed-word"));
        while (true) {
            uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
            bool gold;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) gold = true;
            if (!gold) return word;
            ++word;
        }
    }

    /// @dev Reproduces runTerminalJackpotWork's trait + effective-entropy derivation (the harness has
    ///      an empty dailyHeroWagers, so _applyHeroOverride is a no-op and the traits are exactly
    ///      getRandomTraits(word)).
    function _deriveTraits(uint256 word)
        internal
        pure
        returns (uint8[4] memory traitIds, uint256 effectiveEntropy)
    {
        traitIds = JackpotBucketLib.getRandomTraits(word);
        uint256 entropy = EntropyLib.hash2(word, TARGET_LVL);
        uint8 soloQuadrant = _pickSoloQuadrantLocal(traitIds, entropy);
        effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3);
    }

    /// @dev Local mirror of _pickSoloQuadrant (gold-free path: no trait color == 7 in the chosen
    ///      word, so this returns the entropy-rotation quadrant).
    function _pickSoloQuadrantLocal(uint8[4] memory traits, uint256 entropy)
        internal
        pure
        returns (uint8)
    {
        for (uint8 i; i < 4; ++i) {
            // Assert the chosen word is gold-free so the rotation branch is taken deterministically.
            require(((traits[i] >> 3) & 7) != 7, "test word must be gold-free");
        }
        return uint8((3 - (entropy & 3)) & 3);
    }

    /// @dev Seed each of the 4 winning-trait buckets with a disjoint address range, sized larger
    ///      than the max bucket count so winner selection never resolves to address(0).
    function _seedAllBuckets(uint8[4] memory traitIds) internal {
        for (uint8 b; b < 4; ++b) {
            // 305 distinct holders per bucket on disjoint ranges (1e9 spacing) -> no cross-bucket
            // address collision, so each bucket's claimable is attributable to that bucket alone.
            h.seedBucket(TARGET_LVL, traitIds[b], 305, uint160(uint256(b + 1) * 1_000_000_000));
        }
    }

    /// @dev Sum claimable across every distinct seeded holder of every bucket.
    function _sumSeededClaimable(uint8[4] memory) internal view returns (uint256 total) {
        for (uint8 b; b < 4; ++b) {
            uint160 base = uint160(uint256(b + 1) * 1_000_000_000);
            for (uint256 i; i < 305; ++i) {
                total += h.claimableOf(address(base + uint160(i + 1)));
            }
        }
    }

    /// @dev Sum claimable across the distinct seeded holders of one bucket.
    function _sumBucketClaimable(uint8, uint8 b, uint16) internal view returns (uint256 total) {
        uint160 base = uint160(uint256(b + 1) * 1_000_000_000);
        for (uint256 i; i < 305; ++i) {
            total += h.claimableOf(address(base + uint160(i + 1)));
        }
    }

    /// @dev Assert the bucket-count array is a permutation of the expected multiset.
    function _total(uint16[4] memory counts) internal pure returns (uint256) {
        return uint256(counts[0]) + counts[1] + counts[2] + counts[3];
    }

    function _assertCountMultiset(uint16[4] memory got, uint16[4] memory expected) internal pure {
        bool[4] memory used;
        for (uint8 i; i < 4; ++i) {
            bool found;
            for (uint8 j; j < 4; ++j) {
                if (!used[j] && got[i] == expected[j]) {
                    used[j] = true;
                    found = true;
                    break;
                }
            }
            require(found, "bucket counts are not the 152/104/48/1 multiset");
        }
    }


}
