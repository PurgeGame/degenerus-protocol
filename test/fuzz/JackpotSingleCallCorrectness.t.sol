// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title JackpotSingleCallHarness -- drives the live single-call daily-ETH jackpot surface
/// @notice Extends the production DegenerusGameJackpotModule so the inherited (external)
///         `runTerminalJackpot` executes the live `_processDailyEth -> _processBucket ->
///         _addClaimableEth` path in THIS contract's storage. The harness only adds a
///         `traitBurnTicket` seeder + read-only accounting views; it overrides NO production
///         logic. `runTerminalJackpot` already feeds `_processDailyEth` the full
///         DAILY_ETH_MAX_WINNERS=305 ceiling at the DAILY_JACKPOT_SCALE_MAX_BPS=63_600 max
///         scale (bucket counts 159/95/50/1), in ONE call -- exactly the JGAS-03 surface.
/// @dev Test-only. NO contracts/*.sol is mutated; this harness lives entirely under test/.
contract JackpotSingleCallHarness is DegenerusGameJackpotModule {
    /// @dev Push `count` distinct, non-zero holder addresses into traitBurnTicket[lvl][traitId].
    ///      Distinct addresses make per-winner claimable accounting unambiguous; the seeded
    ///      pool is larger than any bucket's winner count so winner selection (which allows
    ///      duplicates via `% effectiveLen`) never resolves to address(0).
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        address[] storage holders = traitBurnTicket[lvl][traitId];
        for (uint256 i; i < count; ++i) {
            holders.push(address(base + uint160(i + 1)));
        }
    }

    // -- read-only accounting views (the credit sinks _processDailyEth writes) --

    function claimableOf(address who) external view returns (uint256) {
        return claimableWinnings[who];
    }

    function whalePassOf(address who) external view returns (uint256) {
        return whalePassClaims[who];
    }

    function claimablePoolView() external view returns (uint256) {
        return uint256(claimablePool);
    }

    function futurePoolView() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    function bucketLen(uint24 lvl, uint8 traitId) external view returns (uint256) {
        return traitBurnTicket[lvl][traitId].length;
    }
}

/// @title JackpotSingleCallCorrectness -- JGAS-03 single-call 305-winner proofs
/// @notice After the JGAS-02 two-call-split removal, the daily ETH jackpot pays all 305
///         winners (buckets 159/95/50/1 at max scale) correctly in ONE call:
///         - every bucket paid, exact per-winner amounts, none missed, none double-paid
///         - conservation: total ETH credited (claimable + whale-pass) == the distributed pool
///         - the single call fits under the mainnet block gas limit (worst-case-FIRST)
///         - the split path is behaviorally gone (no resume stage entered) + grep-clean
///
/// @dev Drives the live `runTerminalJackpot` entry (msg.sender==GAME guard satisfied via prank)
///      which routes straight into the single-call `_processDailyEth` at the 305 ceiling.
///      Source-level attestations use vm.readFile over ./contracts (foundry.toml grants read).
contract JackpotSingleCallCorrectness is Test {
    JackpotSingleCallHarness internal h;

    /// @dev Mirror of the production constants (DegenerusGameJackpotModule).
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    uint32 internal constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;
    /// @dev FINAL_DAY_SHARES_PACKED = [6000, 1333, 1333, 1334] bps (runTerminalJackpot path).
    uint64 internal constant FINAL_DAY_SHARES_PACKED =
        (uint64(6000)) |
            (uint64(1333) << 16) |
            (uint64(1333) << 32) |
            (uint64(1334) << 48);

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for
    ///      the test harness; the JGAS-03 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    // -------------------------------------------------------------------------
    // JGAS-04 delta-attribution constants (Phase 319 Plan 02)
    // -------------------------------------------------------------------------

    /// @dev The 316-SPEC §J4.2 theoretical worst-case single-call band (structural estimate, +/-30%):
    ///      the 305-winner credit loop ~7.6-9.2M + fixed overhead ~1-3M = ~9-12M gas. This is a
    ///      derived structural bound, NOT a measurement (which is precisely why the JGAS-01 REMOVE
    ///      lock's finality was gated on this JGAS-04 empirical confirmation).
    uint256 internal constant SPEC_THEORY_WORST_CASE_LO_GAS = 9_000_000;
    uint256 internal constant SPEC_THEORY_WORST_CASE_HI_GAS = 12_000_000;

    /// @dev RM-02 freed, per daily-ETH winner, the unconditional cold `autoRebuyState[beneficiary]`
    ///      SLOAD + the conditional `_processAutoRebuy` branch from `_addClaimableEth`. EIP-2929
    ///      cold-access: 1 cold storage slot (~2100) + 1 cold account (~2100) ~= 4.2k gas per winner.
    ///      The post-RM-02 2-arg `_addClaimableEth(beneficiary, weiAmount)` (JackpotModule:738) falls
    ///      straight to `_creditClaimable` with NO `autoRebuyState` read (source-confirmed: grep of
    ///      `autoRebuyState` over the jackpot module returns ZERO matches).
    uint256 internal constant RM02_FREED_PER_WINNER_GAS = 4_200;

    /// @dev A2 (RESEARCH Assumptions Log) + WR-02 re-frame: the numeric `theory - freed` band is
    ///      explicitly NOT a proof of the exact 1.3M freed delta. EIP-2929 cold-access constants are
    ///      fixed, but the surrounding warm/cold loop state shifts the precise number AND the theory
    ///      band is itself +/-30%, so any tolerance wide enough to absorb that uncertainty is too wide
    ///      to pin the 1.3M delta numerically (a ~3M tolerance around a ~7.7M lower edge admits roughly
    ///      [4.7M, 10.7M] — almost any plausible measurement passes; the numeric check is near-vacuous
    ///      and is retained ONLY as a coarse sanity sieve). The LOAD-BEARING proof that RM-02 freed the
    ///      per-winner `autoRebuyState` SLOAD is the STRUCTURAL `_countOccurrences(jp, "autoRebuyState")
    ///      == 0` source attestation below — the freed surface is provably, byte-for-byte absent from
    ///      the jackpot path. The numeric assertion is downgraded to a one-sided "measured gas sits at
    ///      or below the (theory - freed) upper edge" sanity bound (the freeing could only LOWER the
    ///      total), framed as "consistent-with", never "empirically confirmed the exact 1.3M delta".
    uint256 internal constant ATTRIBUTION_TOLERANCE_GAS = 3_000_000;

    /// @dev JackpotEthWin topic0 (for vm.recordLogs filtering).
    bytes32 internal constant JACKPOT_ETH_WIN_TOPIC =
        keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");

    /// @dev A target level whose +1 price tier is a clean 0.04 ETH (unit = 0.01 ETH).
    uint24 internal constant TARGET_LVL = 110;
    /// @dev Pool well above the 200-ETH max-scale floor (JACKPOT_SCALE_SECOND_WEI), so the
    ///      scaleBps pins to DAILY_JACKPOT_SCALE_MAX_BPS and the buckets hit 159/95/50/1.
    uint256 internal constant POOL_WEI = 1000 ether;

    function setUp() public {
        h = new JackpotSingleCallHarness();
    }

    // =========================================================================
    // Task 1 — 305-winner single-call correctness + conservation
    // =========================================================================

    /// @notice JGAS-03: at max scale the daily-ETH jackpot pays exactly DAILY_ETH_MAX_WINNERS=305
    ///         winners across the 4 buckets (159 + 95 + 50 + 1) in ONE call -- every bucket paid,
    ///         each winner credited its exact per-winner bucket amount, none missed, none double
    ///         credited within its bucket, and total ETH credited == the distributed pool.
    function testSingleCallPaysAll305WithConservation() public {
        (uint8[4] memory traitIds, uint256 effectiveEntropy) = _deriveTraits(_word());

        // Confirm the bucket geometry IS the 305 ceiling (159/95/50/1) BEFORE driving the call.
        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            POOL_WEI,
            effectiveEntropy,
            DAILY_ETH_MAX_WINNERS,
            DAILY_JACKPOT_SCALE_MAX_BPS
        );
        assertEq(JackpotBucketLib.sumBucketCounts(bc), 305, "max-scale total == 305");
        _assertCountMultiset(bc, [uint16(159), 95, 50, 1]);

        // Seed each of the 4 winning-trait buckets with distinct holders (one disjoint address
        // range per trait), more than any bucket's winner count so no winner resolves to zero.
        _seedAllBuckets(traitIds);

        // Drive the live single-call jackpot (msg.sender==GAME via prank).
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());

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
        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            POOL_WEI, effectiveEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );

        uint8 soloIdx = JackpotBucketLib.soloBucketIndex(effectiveEntropy);
        uint256 unit = PriceLookupLib.priceForLevel(TARGET_LVL + 1) >> 2;
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED, uint8(effectiveEntropy & 3)
        );
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            POOL_WEI, shareBps, bc, soloIdx, unit
        );

        _seedAllBuckets(traitIds);
        vm.prank(ContractAddresses.GAME);
        h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());

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
    ///         reached for any pool >= JACKPOT_SCALE_SECOND_WEI = 200 ETH at max scale.)
    function testFuzz_SingleCall305AtMaxScale(uint96 extraWei) public {
        uint256 pool = 200 ether + bound(uint256(extraWei), 0, 5000 ether);
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            pool, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );
        assertEq(JackpotBucketLib.sumBucketCounts(bc), 305, "any >=200-ETH pool hits the 305 ceiling");

        _seedAllBuckets(traitIds);
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        uint256 paidWei = h.runTerminalJackpot(pool, TARGET_LVL, _word());

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
    ///         path is the 305-winner max-scale single call (all 4 buckets, 159/95/50/1) -- no
    ///         daily-ETH path produces more winners (DAILY_ETH_MAX_WINNERS = 305 is the hard
    ///         cap, and MAX_BUCKET_WINNERS=250 never clips a 159 bucket). We measure THAT call's
    ///         gas (gasleft delta) and assert it is < the mainnet 30M block gas limit, i.e. it
    ///         fits with margin. Full peg calibration + the margin attribution to the removed
    ///         per-winner autoRebuyState SLOAD is Phase 319 / JGAS-04; this plan's bar is "fits".
    function testWorstCaseSingleCallFitsBlockGasLimit() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        // Establish this IS the worst case: 305 winners, the maximum the daily-ETH path emits.
        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            POOL_WEI, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );
        assertEq(JackpotBucketLib.sumBucketCounts(bc), 305, "worst case: 305 winners (the hard cap)");

        _seedAllBuckets(traitIds);

        // Measure the single call's gas consumption (gasleft delta around the external call).
        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());
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
    ///         DAILY_ETH_MAX_WINNERS = 305 and MAX_BUCKET_WINNERS = 250 which never clips a 159 bucket)
    ///         and records the 30M - measured margin for the SUMMARY.
    function testJgas04WorstCaseFirstReframeWithMargin() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        // Worst-case-FIRST (assert the scenario IS the max BEFORE measuring):
        //  (a) the bucket geometry reaches exactly the DAILY_ETH_MAX_WINNERS = 305 hard cap;
        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            POOL_WEI, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );
        assertEq(
            JackpotBucketLib.sumBucketCounts(bc),
            DAILY_ETH_MAX_WINNERS,
            "JGAS-04 worst case: 305 winners == DAILY_ETH_MAX_WINNERS (the daily-ETH hard cap)"
        );
        //  (b) no single bucket count can exceed MAX_BUCKET_WINNERS = 250, so the 159/95/50/1
        //      geometry is never clipped — 305-across-4-buckets is the true maximum work shape.
        for (uint8 b; b < 4; ++b) {
            assertLe(bc[b], 250, "JGAS-04 worst case: no bucket exceeds MAX_BUCKET_WINNERS = 250 (never clips 159)");
        }

        _seedAllBuckets(traitIds);

        // Measure the worst-case single call.
        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());
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

    /// @notice JGAS-04 delta attribution (structural, RESEARCH option (a) — no dead-code re-introduction):
    ///         the enabling headroom that lets all 305 winners fit one call is RM-02 removing, per
    ///         winner, the unconditional cold `autoRebuyState[beneficiary]` SLOAD + `_processAutoRebuy`
    ///         branch from `_addClaimableEth`. The post-RM-02 2-arg `_addClaimableEth` (JackpotModule:738)
    ///         falls straight to `_creditClaimable` (source-confirmed: zero `autoRebuyState` reads on
    ///         the jackpot path).
    ///
    ///         WR-02 RE-FRAME: this test does NOT empirically confirm the exact ~1.3M freed delta. The
    ///         LOAD-BEARING proof is the STRUCTURAL `_countOccurrences(jp, "autoRebuyState") == 0`
    ///         attestation — the freed surface is provably absent from the jackpot module source. The
    ///         numeric `theory - freed` figure is a coarse sanity sieve only: it computes the freed
    ///         estimate from the EIP-2929 cold-access constants (~4.2k/winner x 305 ~= 1.28M) and
    ///         asserts the MEASURED single-call gas sits at/below the 316-SPEC §J4.2 theory (9-12M)
    ///         MINUS that freed delta — a one-sided upper-bound that is "consistent with" the freeing
    ///         having lowered the total, NOT a proof of the 1.3M magnitude (Assumption A2; the band's
    ///         tolerance is too wide to pin the delta numerically — see ATTRIBUTION_TOLERANCE_GAS). It
    ///         does NOT re-introduce the removed SLOAD (option (b) comparison harness is rejected).
    function testJgas04FreedAutoRebuyStateSloadDeltaAttribution() public {
        (uint8[4] memory traitIds, ) = _deriveTraits(_word());
        _seedAllBuckets(traitIds);

        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(paidWei, 0, "JGAS-04 attribution: the measured call actually paid out");

        // The freed band: RM-02 removed ~4.2k cold-access gas per winner x 305 winners ~= 1.28M off
        // the worst-case single-call total. (1 cold storage slot ~2100 + 1 cold account ~2100.)
        uint256 freed = RM02_FREED_PER_WINNER_GAS * DAILY_ETH_MAX_WINNERS;
        assertGt(freed, 1_000_000, "JGAS-04: the freed autoRebuyState-SLOAD band is ~1.3M (4.2k x 305)");
        assertLt(freed, 1_600_000, "JGAS-04: the freed band stays in the ~1.3M neighborhood");

        // WR-02 one-sided sanity sieve (NOT a proof of the 1.3M magnitude): the 316-SPEC structural
        // worst case (9-12M) less the freed ~1.3M => ~7.7-10.7M. The ONLY defensible numeric direction
        // is the upper bound — the freeing could only LOWER the total, so the measured single-call gas
        // must sit at/below the (theory - freed) upper edge. The prior lower-edge "within tolerance"
        // assertion was near-vacuous (a 3M tolerance around the ~7.7M lower edge admits ~[4.7M,10.7M])
        // and is REMOVED: it claimed to confirm the 1.3M delta but admitted almost any measurement.
        // The load-bearing proof is the STRUCTURAL autoRebuyState==0 attestation below.
        uint256 theoryMinusFreedHi = SPEC_THEORY_WORST_CASE_HI_GAS - freed; // ~10.72M

        // measured must not exceed the (theory - freed) upper edge (the freeing did lower the total).
        assertLt(
            gasUsed,
            theoryMinusFreedHi,
            "JGAS-04: measured single-call gas is below the (theory - freed) upper edge (consistent-with, not a proof of the exact 1.3M delta - A2/WR-02)"
        );

        // Source attestation (THE LOAD-BEARING PROOF): the removed surface is genuinely gone (no
        // dead-code re-introduction). The 2-arg _addClaimableEth performs ZERO autoRebuyState reads on
        // the jackpot daily-ETH path — this structural absence, not the numeric band, proves JGAS-04.
        string memory jp = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameJackpotModule.sol")
        );
        assertEq(
            _countOccurrences(jp, "autoRebuyState"),
            0,
            "JGAS-04: the per-winner autoRebuyState SLOAD is structurally absent from the jackpot path"
        );

        emit log_named_uint("jgas04_measured_single_call_gas", gasUsed);
        emit log_named_uint("jgas04_freed_autoRebuyState_sload_band", freed);
        emit log_named_uint("jgas04_theory_minus_freed_hi", theoryMinusFreedHi);
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
        uint256 unit = PriceLookupLib.priceForLevel(TARGET_LVL + 1) >> 2;
        uint16[4] memory bc = JackpotBucketLib.bucketCountsForPoolCap(
            POOL_WEI, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED, uint8(effEntropy & 3)
        );
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            POOL_WEI, shareBps, bc, soloIdx, unit
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
        uint256 paidWei = h.runTerminalJackpot(POOL_WEI, TARGET_LVL, _word());

        // Full resolution in one call: everything except the in-bucket rounding dust is paid.
        // (No resumeEthPool carry could exist -- the symbol is grep-clean, proven below.)
        assertEq(
            paidWei + expectedDust,
            POOL_WEI,
            "single call fully resolves: paidWei + in-bucket rounding dust == pool (no resume carry)"
        );
    }

    /// @notice JGAS-03 split grep-clean: the two-call-split symbol set returns ZERO non-comment
    ///         matches across the daily-ETH production surface (JackpotModule + AdvanceModule).
    ///         The split MECHANISM is structurally absent, not merely unreached.
    /// @dev Reads each source via vm.readFile (foundry.toml grants read on ./contracts), strips
    ///      comments so NatSpec prose cannot self-invalidate the gate, and asserts 0 residual
    ///      matches per symbol. Mirrors the established VrfWireOneShot / RngFreezeAndRemovalProofs
    ///      source-attestation pattern.
    function testSplitSymbolsGrepClean() public view {
        string[7] memory splitKillSet = [
            "resumeEthPool",
            "SPLIT_CALL1",
            "SPLIT_CALL2",
            "SPLIT_NONE",
            "_resumeDailyEth",
            "STAGE_JACKPOT_ETH_RESUME",
            "call1Bucket"
        ];
        // splitMode is asserted separately so its substring does not accidentally match a longer
        // identifier; it must also be zero.
        string[2] memory sources = [
            "contracts/modules/DegenerusGameJackpotModule.sol",
            "contracts/modules/DegenerusGameAdvanceModule.sol"
        ];

        for (uint256 s; s < sources.length; ++s) {
            string memory code = _stripComments(vm.readFile(sources[s]));
            for (uint256 k; k < splitKillSet.length; ++k) {
                assertEq(
                    _countOccurrences(code, splitKillSet[k]),
                    0,
                    string.concat("split symbol still present in ", sources[s], ": ", splitKillSet[k])
                );
            }
            assertEq(
                _countOccurrences(code, "splitMode"),
                0,
                string.concat("splitMode still present in ", sources[s])
            );
        }
    }

    /// @notice JGAS-03 single-call structural attestation: the AdvanceModule retains NO resume
    ///         stage. The three live STAGE_JACKPOT_* constants are the renumbered 8/9/10 set
    ///         (COIN_TICKETS / PHASE_ENDED / DAILY_STARTED); STAGE_JACKPOT_ETH_RESUME is absent.
    function testNoResumeStageConstantInAdvanceModule() public view {
        string memory adv = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameAdvanceModule.sol")
        );
        assertEq(
            _countOccurrences(adv, "STAGE_JACKPOT_ETH_RESUME"),
            0,
            "no resume stage constant survives in the AdvanceModule"
        );
        // The single-call daily-ETH entry (payDailyJackpot) is still dispatched exactly once.
        assertGt(
            _countOccurrences(adv, "payDailyJackpot("),
            0,
            "the single-call daily-ETH entry is still dispatched"
        );
    }

    /// @notice JGAS-03 preserved ceiling: the 305-winner ceiling + the max scale + the
    ///         159/95/50/1 bucket geometry survive byte-faithfully in the JackpotModule (the split
    ///         removal changed routing only, not amounts/winner-counts).
    function testPreservedCeilingAndScaleConstants() public view {
        string memory src = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameJackpotModule.sol")
        );
        assertEq(
            _countOccurrences(src, "DAILY_ETH_MAX_WINNERS = 305"),
            1,
            "the 305 winner ceiling is preserved"
        );
        assertEq(
            _countOccurrences(src, "DAILY_JACKPOT_SCALE_MAX_BPS = 63_600"),
            1,
            "the 6.36x max scale is preserved"
        );
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev A fixed VRF word whose getRandomTraits() yields 4 distinct, non-gold trait IDs and a
    ///      gold-free quadrant set (so _pickSoloQuadrant takes the entropy-rotation branch and no
    ///      deity virtual entries appear -- deityBySymbol is empty in the harness anyway).
    function _word() internal pure returns (uint256) {
        return uint256(keccak256("jgas03-single-call-fixed-word"));
    }

    /// @dev Reproduces runTerminalJackpot's trait + effective-entropy derivation (the harness has
    ///      an empty dailyHeroWagers, so _applyHeroOverride is a no-op and the traits are exactly
    ///      getRandomTraits(word)).
    function _deriveTraits(uint256 word)
        internal
        pure
        returns (uint8[4] memory traitIds, uint256 effectiveEntropy)
    {
        traitIds = JackpotBucketLib.getRandomTraits(word);
        uint256 entropy = EntropyLib.hash2(word, TARGET_LVL + 1);
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
            require(found, "bucket counts are not the 159/95/50/1 multiset");
        }
    }

    // -------------------------------------------------------------------------
    // Source-level grep helpers (vm.readFile over ./contracts)
    // -------------------------------------------------------------------------

    /// @dev Count non-overlapping occurrences of `needle` in `haystack`.
    function _countOccurrences(string memory haystack, string memory needle)
        private
        pure
        returns (uint256 count)
    {
        bytes memory hb = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || hb.length < n.length) return 0;
        for (uint256 i = 0; i <= hb.length - n.length; ) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; ++j) {
                if (hb[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                unchecked {
                    ++count;
                    i += n.length;
                }
            } else {
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @dev Strip `//` line comments and lines whose first non-space char starts a block comment
    ///      (`*` or `/*`), so NatSpec prose mentioning a kill-set symbol does not self-invalidate
    ///      the grep gate. Code matches survive. (Mirrors RngFreezeAndRemovalProofs._stripComments.)
    function _stripComments(string memory src) private pure returns (string memory) {
        bytes memory b = bytes(src);
        bytes memory out = new bytes(b.length);
        uint256 o;
        uint256 i;
        uint256 lineStart;
        bool lineIsBlockComment;
        while (i < b.length) {
            if (b[i] == 0x0a) {
                out[o++] = b[i];
                i++;
                lineStart = i;
                lineIsBlockComment = false;
                continue;
            }
            if (i == lineStart || _onlySpacesSince(b, lineStart, i)) {
                if (b[i] == 0x2a) {
                    lineIsBlockComment = true;
                } else if (b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2a) {
                    lineIsBlockComment = true;
                }
            }
            if (!lineIsBlockComment && b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2f) {
                while (i < b.length && b[i] != 0x0a) i++;
                continue;
            }
            if (!lineIsBlockComment) {
                out[o++] = b[i];
            }
            i++;
        }
        bytes memory trimmed = new bytes(o);
        for (uint256 k; k < o; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    /// @dev True iff every byte in [from, to) is a space (0x20) or tab (0x09).
    function _onlySpacesSince(bytes memory b, uint256 from, uint256 to)
        private
        pure
        returns (bool)
    {
        for (uint256 i = from; i < to; i++) {
            if (b[i] != 0x20 && b[i] != 0x09) return false;
        }
        return true;
    }
}
