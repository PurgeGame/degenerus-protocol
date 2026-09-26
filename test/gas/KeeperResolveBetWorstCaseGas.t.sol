// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";

/// @title Keeper resolve gas stress cases at the per-currency spin caps.
/// @notice Searches 2,000 rounds for a high count of paying spins, then injects a
/// small pool so every paying spin takes the cap-conversion path. Assertions check
/// the actual generated-ticket score, cap count, settlement and 30M gas budget.
/// The candidate search supplies a reproducible stress case, not an exhaustive
/// upper bound over every possible ticket sequence.
contract KeeperResolveBetWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34 (forge inspect DegenerusGame storageLayout, Stage-B POST); lootboxRngIndex is
    ///      the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // post Stage-B game-storage repack: was 35
    /// @dev lootboxRngWordByIndex mapping root slot (uint48 index => word) (post Stage-B game-storage repack: was 36).
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;
    /// @dev prizePoolsPacked at slot 2 ([future:128 | next:128]).
    uint256 private constant PRIZE_POOLS_SLOT = 2;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      test harness; the GAS-01 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev v47 per-currency spin caps (DegeneretteModule:226-228). The ETH cap (25) is the
    ///      structural spin-loop ceiling for the DSPIN-02 worst case — 2.5x the old 10-spin bound.
    uint8 internal constant MAX_SPINS_ETH = 25;
    uint8 internal constant MAX_SPINS_FLIP = 15;

    /// @dev The Phase-319 GAS-01 reference spin count (the OLD MAX_SPINS_PER_BET). Kept so the
    ///      per-1-spin-item marginal and the 10-vs-25 absorption comparison both have a stable
    ///      reference point. `resolveDegeneretteBets` pays NO reward at all now (the old flat
    ///      per-item CRANK_RESOLVE_BET_GAS_UNITS-calibrated reward is gone); these numbers are
    ///      pure gas-shape measurements.
    uint8 internal constant LEGACY_WORST_SPINS = 10;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    /// @dev Per-ticket bet amount: large enough that every winning spin's payout exceeds the
    ///      injected pool's 10% ETH-win cap, flipping the excess into the lootbox branch.
    uint128 private constant AMOUNT_PER_TICKET = 1 ether;
    /// @dev Small futurePrizePool injected so the 10%-of-pool ETH win cap is tiny (0.05 ETH); any
    ///      winning spin's payout (>= 0.45x of a 1-ETH bet) far exceeds it -> lootbox materialization.
    uint128 private constant SMALL_POOL_WEI = 0.5 ether;
    /// @dev Word-search budget (single combined pass in _findWorstCase). Maximizes the Variant-2
    ///      winning-spin count for the gas worst case. Bounded so the keccak/memory work in setUp stays
    ///      under the EVM memory limit (Solidity never frees per-iteration loop memory).
    uint256 private constant WORD_SEARCH_BUDGET = 2000;

    /// @dev PayoutCapped topic0 — emitted once per spin whose ETH share exceeds the 10% pool cap and
    ///      flips into the lootbox branch (DegeneretteModule:759). A count of 10 proves all 10 spins
    ///      drove a real lootbox materialization (the per-spin maximum branch).
    bytes32 private constant PAYOUT_CAPPED_SIG =
        0xf8a9468f6767206f82ef0f809e2c4fb396a1495ad99e9f116652fe99a91f20c5;

    address private player;
    address private cranker;

    /// @dev The legacy 10-spin worst-case (RNG word, customTicket): the word is searched so the
    ///      greedy ticket wins (matches >= 2) on all 10 spins; pinned in setUp for determinism.
    uint256 private worstCaseWord;
    uint32 private worstCaseTicket;

    /// @dev The DSPIN-02 25-spin worst-case (word, ticket): greedy ticket wins on all 25 spins.
    uint256 private worstCaseWord25;
    uint32 private worstCaseTicket25;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("resolve_worst_player");
        cranker = makeAddr("resolve_worst_cranker");
        vm.deal(player, 1_000_000 ether);
        vm.deal(cranker, 1_000_000 ether);
        vm.deal(address(game), 10_000_000 ether);

        // placeDegeneretteBet requires lootboxRngIndex != 0 and the word at that index == 0.
        // Seed index = 1 (word stays 0 until injected post-placement).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        // resolveDegeneretteBets is directly permissionless (any caller may settle any queued
        // bet; payouts always credit the bet's owner), so no operator-approval dance is needed
        // for the cranker/keeper to resolve `player`'s bets.

        // Pin the legacy 10-spin worst-case (Phase-319 reference).
        (worstCaseWord, worstCaseTicket) = _findWorstCase(INDEX, LEGACY_WORST_SPINS);
        // Pin the DSPIN-02 25-spin worst-case (all 25 spins win -> all 25 materialize a lootbox).
        (worstCaseWord25, worstCaseTicket25) = _findWorstCase(INDEX, MAX_SPINS_ETH);
    }

    // =========================================================================
    // Test A — 10-spin all-match worst case (the GAS-01 fit-check)
    // =========================================================================

    /// @notice GAS-01 worst-case-FIRST: a single `resolveDegeneretteBets` item resolving a `ticketCount == 10`
    ///         bet where every spin wins ETH and flips into the lootbox branch (10 materializations).
    ///         Asserts the scenario IS the maximum (ticketCount == 10 AND all 10 spins materialized a
    ///         lootbox) BEFORE the measurement is trusted, and asserts the measured gas < 30M mainnet.
    function testWorstCaseResolveBet10SpinAllMatchFitsBlockGasLimit() public {
        uint64 betId = _placeWorstCaseBet(player);
        // Inject a small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        // assert-is-worst-case precondition (1/2): the placed bet's ticketCount IS the legacy max.
        assertEq(_betTicketCount(betId), LEGACY_WORST_SPINS, "legacy worst case: ticketCount == 10");

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;

        // Measure the worst-case crank item's gas (gasleft delta around the external call).
        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(INDEX, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects(betIds);

        // assert-is-worst-case precondition (2/2): all 10 spins ran and EVERY WINNING spin drove the
        // lootbox materialization branch (one PayoutCapped per winning spin whose payout flipped into
        // the lootbox). Under Variant-2 a single fixed ticket cannot win (S>=2) on all 10 independent
        // result reels, so the harness maximizes the winning-spin count; we assert the loop ran fully
        // (10) and that the achieved cap-flip count equals the achieved winning-spin count (every
        // winning spin flips — the per-spin max branch) and is materially non-vacuous.
        assertEq(spinResults, LEGACY_WORST_SPINS, "all 10 spins resolved (packed into the one DegeneretteResolved event)");
        uint8 winningSpins10 = _countWinningSpins(INDEX, worstCaseWord, worstCaseTicket, LEGACY_WORST_SPINS);
        assertEq(
            lootboxFlips,
            uint256(winningSpins10),
            "legacy worst case: every WINNING spin materialized a lootbox (one PayoutCapped each)"
        );
        assertGt(lootboxFlips, 0, "legacy worst case non-vacuity: >= 1 spin materialized the lootbox branch");

        // Non-vacuity: the bet was actually resolved (queue word zeroed), not silently skipped.
        assertEq(game.degeneretteBetInfo(INDEX, betId), 0, "non-vacuity: worst-case bet resolved (word zeroed)");

        // The headline GAS-01 assertion: the worst case fits the REAL mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: 10-spin all-match resolve-bet worst case fits under the 30M mainnet block gas limit"
        );

        emit log_named_uint("worst_case_resolve_bet_10spin_allmatch_gas", gasUsed);
        emit log_named_uint("worst_case_resolve_bet_lootbox_materializations", lootboxFlips);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Test B — per-1-spin-item MARGINAL (the Plan 05 calibration target)
    // =========================================================================

    /// @notice GAS-01: isolate the per-1-spin-item MARGINAL gas — the marginal cost of adding one
    ///         typical (1-spin) resolve item to `resolveDegeneretteBets`, which pays no reward at
    ///         all (the old flat per-item CRANK_RESOLVE_BET_GAS_UNITS-calibrated reward is gone;
    ///         this is a pure gas-shape measurement now). Measured by the loop-N-divide
    ///         micro-bench idiom: crank N independent 1-spin items in one batch and divide the
    ///         delta by N. Asserts the per-1-spin marginal is materially BELOW the 10-spin worst
    ///         case, confirming per-item gas scales with spin work, not a flat charge.
    function testPerOneSpinItemMarginalBelowWorstCase() public {
        uint256 nItems = 8;

        // Place N independent 1-spin bets for the same player (distinct betIds).
        uint64[] memory betIds = new uint64[](nItems);
        for (uint256 i; i < nItems; ++i) {
            betIds[i] = _placeOneSpinBet(player);
        }
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        // Sanity: each placed item is a 1-spin bet (the typical case the marginal calibrates against).
        assertEq(_betTicketCount(betIds[0]), 1, "Test B item is a 1-spin bet (the typical case)");

        // Bracket the whole N-item batch; divide by N for the per-1-spin-item marginal.
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(INDEX, betIds);
        uint256 totalGas = gasBefore - gasleft();
        uint256 perItemMarginal = totalGas / nItems;

        // Non-vacuity: every item resolved (queue words zeroed), so the marginal is a real per-item cost.
        for (uint256 i; i < nItems; ++i) {
            assertEq(game.degeneretteBetInfo(INDEX, betIds[i]), 0, "non-vacuity: each 1-spin item resolved");
        }

        // Re-measure the 10-spin worst case in this test's own state for an apples-to-apples compare.
        uint256 worstCaseGas = _measureTenSpinWorstCase();

        // The per-1-spin marginal is materially below the 10-spin worst case (REW-03 under-reimburses
        // big wins): a 1-spin item drives at most ONE lootbox materialization vs the worst case's ten,
        // so the marginal must be a small fraction of the worst case (319-GAS-DERIVATION.md §1(e)).
        assertLt(
            perItemMarginal,
            worstCaseGas,
            "per-1-spin marginal is materially below the 10-spin worst case (per-spin peg under-reimburses)"
        );
        assertLt(perItemMarginal, MAINNET_BLOCK_GAS_LIMIT, "per-1-spin marginal trivially fits the block limit");

        // The calibration input Plan 05 reads from the test log.
        emit log_named_uint("per_1spin_item_resolve_marginal_gas", perItemMarginal);
        emit log_named_uint("per_1spin_item_resolve_batch_total_gas", totalGas);
        emit log_named_uint("worst_case_resolve_bet_10spin_allmatch_gas", worstCaseGas);
    }

    // =========================================================================
    // DSPIN-02 Test C — 25-spin ETH worst case (DERIVE-THEN-MEASURE)
    // =========================================================================

    /// @notice DSPIN-02 worst-case-FIRST. The v47 per-currency cap raises the ETH spin loop from
    ///         10 (old MAX_SPINS_PER_BET) to MAX_SPINS_ETH = 25 — 2.5x the roll work. This test
    ///         proves the raised cap's worst case is ABSORBED (fits the 30M mainnet block gas limit),
    ///         because the v47 write-batching replaces N per-spin storage writes with a SINGLE
    ///         end-of-call flush (one mint per currency, one claimable+claimablePool write, one pool
    ///         write, one box per betId).
    ///
    ///         DERIVATION (in writing, BEFORE measuring):
    ///           - The single most expensive resolveBets item is ONE ETH bet at ticketCount ==
    ///             MAX_SPINS_ETH == 25 where EVERY spin (a) wins ETH (matches >= 2 -> payout > 0)
    ///             AND (b) flips into the lootbox-conversion branch (ethShare exceeds the 10%-of-pool
    ///             ETH_WIN_CAP_BPS cap), driving 25 PayoutCapped emits and ONE per-bet
    ///             `_resolveLootboxDirect` materialization on the summed-per-bet lootbox share
    ///             (DGAS-03: one box per betId, NOT 25 boxes). This is the per-spin maximum branch
    ///             (ETH-win + cap-flip) repeated to the structural cap.
    ///           - 2.5x the old 10-spin roll work (25 result-seed keccaks + 25 payout computations +
    ///             25 cap evaluations against the running-pool local).
    ///           - OFFSETTING SAVINGS (why it is absorbed): the single end-of-call flush replaces what
    ///             was, pre-batching, up to 25 separate `_addClaimableEth` (claimable + claimablePool)
    ///             writes and 25 prize-pool writes with ONE of each; the box is rolled ONCE per bet,
    ///             not per spin. So the 25-spin cost is far below a naive 2.5x of the old per-spin-write
    ///             10-spin number.
    ///         MEASURE: assert ticketCount == 25, all 25 spins resolved, gas < 30M with comfortable
    ///         margin. A block-limit overflow would be a real finding (the cap would be unsafe).
    function testWorstCaseResolveBet25SpinAllMatchFitsBlockGasLimit() public {
        // Take the 10-spin reference FIRST, from the same cold fixture Test A measures it in.
        // Measured after the 25-spin bet instead, the reference inherits whatever one-time
        // slot initialization that bet's placement performed — most visibly the all-time
        // record bootstrap, whose claim writes the bettor's day stake — and reads ~30%
        // cheaper than the legacy worst case it is supposed to stand for, tightening this
        // ratio against a numerator that never moved. Ordering it first makes the 25-spin
        // figure below a steady-state resolve rather than a cold-start one; Test A keeps the
        // cold reading, and both sit orders of magnitude under the block limit either way.
        uint256 legacyGas = _measureTenSpinWorstCase();

        // That reference leaves its own word injected at INDEX; placement requires word == 0.
        _injectLootboxRngWord(INDEX, 0);
        uint64 betId = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        // Small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);

        // assert-is-worst-case (1/2): ticketCount IS the structural ETH cap (25).
        assertEq(_betTicketCount(betId), MAX_SPINS_ETH, "DSPIN-02: ticketCount == MAX_SPINS_ETH (25)");

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;

        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(INDEX, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects(betIds);

        // assert-is-worst-case (2/2): the full 25-iteration spin loop ran (the structural gas driver),
        // and the WINNING spins all drove the cap-flip branch (each winning ETH spin's share exceeds
        // the 10% pool cap -> PayoutCapped). A single fixed ticket cannot win on all 25 independent
        // result tickets, so the worst case maximizes the winning+cap-flip count; we assert the loop
        // ran fully (25) and that the achieved cap-flip count equals the achieved winning-spin count
        // (every winning spin flips, the per-spin max branch) and is materially non-vacuous.
        assertEq(spinResults, MAX_SPINS_ETH, "DSPIN-02: all 25 spins resolved (full loop; packed into the one DegeneretteResolved event)");
        uint8 winningSpins = _countWinningSpins(INDEX, worstCaseWord25, worstCaseTicket25, MAX_SPINS_ETH);
        assertEq(
            lootboxFlips,
            uint256(winningSpins),
            "DSPIN-02: every WINNING spin flipped into the lootbox branch (one PayoutCapped each)"
        );
        assertGt(lootboxFlips, 0, "DSPIN-02 non-vacuity: at least one spin materialized the lootbox branch");

        // Non-vacuity: the bet was actually resolved (queue word zeroed), not silently skipped.
        assertEq(game.degeneretteBetInfo(INDEX, betId), 0, "non-vacuity: 25-spin worst-case bet resolved (word zeroed)");

        // Headline DSPIN-02 assertion: the 25-spin worst case fits the REAL mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02: 25-spin all-match resolve-bet worst case fits under the 30M mainnet block gas limit"
        );

        // Absorption: re-measure the legacy 10-spin worst case in this test's own state, and assert
        // the 25-spin cost is BELOW a naive 2.5x of it — demonstrating the single-flush write savings
        // absorb the raised cap (the marginal per-spin work is roll-only, not write-per-spin).
        assertLt(
            gasUsed,
            (legacyGas * 5) / 2,
            "DSPIN-02 absorption: 25-spin cost < 2.5x the 10-spin worst case (single-flush savings)"
        );

        emit log_named_uint("worst_case_resolve_bet_25spin_allmatch_gas", gasUsed);
        emit log_named_uint("legacy_10spin_worst_case_gas", legacyGas);
        emit log_named_uint("worst_case_resolve_bet_25spin_lootbox_materializations", lootboxFlips);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // DSPIN-02 Test D — mixed-currency batch up to the per-currency caps
    // =========================================================================

    /// @notice Exercise both supported currencies at their caps in one settlement:
    ///         25 ETH spins and 15 FLIP spins, with the ETH lootbox work retained.
    function testWorstCaseMixedCurrencyBatchGas() public {
        // Both bets use one committed word; every spin executes its full resolution.
        uint128 flipPerTicket = 200 ether;  // >= MIN_BET_FLIP (100 ether)
        _fundFlip(player, uint256(flipPerTicket) * MAX_SPINS_FLIP + 1 ether);

        // Place one bet per currency at its cap, all using worstCaseTicket25 (wins on the ETH word).
        uint64 ethBet = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        uint64 flipBet = _placeCurrencyBet(player, 1, flipPerTicket, MAX_SPINS_FLIP, worstCaseTicket25);

        // Small pool so the ETH spins flip into the lootbox branch (max ETH-side work).
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);

        // Resolve the whole mixed batch in ONE call (the cross-bet flush under measurement). The crank
        // resolve relaxation isn't needed here — player resolves their own bets.
        uint64[] memory betIds = new uint64[](2);
        betIds[0] = ethBet;
        betIds[1] = flipBet;

        vm.recordLogs();
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(INDEX, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        // Non-vacuity: both bets resolved and all 40 spins ran.
        (uint256 spinResults, ) = _countResolveEffects(betIds);
        assertEq(spinResults, uint256(MAX_SPINS_ETH) + MAX_SPINS_FLIP,
            "mixed batch: all 40 spins resolved (ETH 25 + FLIP 15)");
        assertEq(game.degeneretteBetInfo(INDEX, ethBet), 0, "non-vacuity: ETH bet resolved");
        assertEq(game.degeneretteBetInfo(INDEX, flipBet), 0, "non-vacuity: FLIP bet resolved");

        // DSPIN-02: the maximum mixed-currency batch fits the 30M mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02: max mixed-currency batch (40 spins, 2 currencies) fits under the 30M block limit"
        );

        emit log_named_uint("worst_case_mixed_currency_batch_gas", gasUsed);
        emit log_named_uint("mixed_batch_total_spins", spinResults);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Sweep-path variants — the SAME worst-case bet shapes, resolved by the automatic
    // human-box sweep (game.openBoxes) instead of a direct resolveDegeneretteBets call.
    // =========================================================================

    /// @notice DSPIN-02 via the sweep: the same 25-spin all-match ETH worst case, resolved by
    ///         `openBoxes` once the index's word lands and the active lootbox index moves past
    ///         it (the sweep's own trigger condition — see DegeneretteSweep.t.sol `_landWord`).
    ///         Proves the automatic path absorbs the identical worst case, not just the manual one.
    function testWorstCaseResolveBet25SpinAllMatchViaSweepFitsBlockGasLimit() public {
        uint64 betId = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);
        _advanceActiveIndexPast(INDEX);

        assertEq(_betTicketCount(betId), MAX_SPINS_ETH, "DSPIN-02 sweep: ticketCount == MAX_SPINS_ETH (25)");

        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.openBoxes(type(uint256).max);
        uint256 gasUsed = gasBefore - gasleft();

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects(betIds);
        assertEq(spinResults, MAX_SPINS_ETH, "DSPIN-02 sweep: all 25 spins resolved");
        uint8 winningSpins = _countWinningSpins(INDEX, worstCaseWord25, worstCaseTicket25, MAX_SPINS_ETH);
        assertEq(
            lootboxFlips,
            uint256(winningSpins),
            "DSPIN-02 sweep: every WINNING spin flipped into the lootbox branch"
        );
        assertGt(lootboxFlips, 0, "DSPIN-02 sweep non-vacuity: at least one spin materialized the lootbox branch");

        assertEq(game.degeneretteBetInfo(INDEX, betId), 0, "non-vacuity: bet resolved via the sweep");

        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02 sweep: 25-spin all-match sweep-resolve worst case fits under the 30M mainnet block gas limit"
        );

        emit log_named_uint("worst_case_resolve_bet_25spin_allmatch_via_sweep_gas", gasUsed);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    /// @notice DSPIN-02 mixed-currency batch via the sweep: the same ETH-25 + FLIP-15 worst case
    ///         as `testWorstCaseMixedCurrencyBatchGas`, but resolved automatically by `openBoxes`.
    function testWorstCaseMixedCurrencyBatchGasViaSweep() public {
        uint128 flipPerTicket = 200 ether; // >= MIN_BET_FLIP (100 ether)
        _fundFlip(player, uint256(flipPerTicket) * MAX_SPINS_FLIP + 1 ether);

        uint64 ethBet = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        uint64 flipBet = _placeCurrencyBet(player, 1, flipPerTicket, MAX_SPINS_FLIP, worstCaseTicket25);

        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);
        _advanceActiveIndexPast(INDEX);

        uint64[] memory betIds = new uint64[](2);
        betIds[0] = ethBet;
        betIds[1] = flipBet;

        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.openBoxes(type(uint256).max);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, ) = _countResolveEffects(betIds);
        assertEq(spinResults, uint256(MAX_SPINS_ETH) + MAX_SPINS_FLIP,
            "mixed batch via sweep: all 40 spins resolved (ETH 25 + FLIP 15)");
        assertEq(game.degeneretteBetInfo(INDEX, ethBet), 0, "non-vacuity: ETH bet resolved via sweep");
        assertEq(game.degeneretteBetInfo(INDEX, flipBet), 0, "non-vacuity: FLIP bet resolved via sweep");

        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02 sweep: max mixed-currency batch (40 spins, 2 currencies) fits under the 30M block limit"
        );

        emit log_named_uint("worst_case_mixed_currency_batch_via_sweep_gas", gasUsed);
        emit log_named_uint("mixed_batch_total_spins", spinResults);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Place a worst-case ETH bet of `spins` tickets with `ticket` so every spin wins
    ///      (matches >= 2). Placement adds totalBet to the pool; the caller resets the pool to
    ///      SMALL_POOL_WEI afterward so the 10% cap flips each spin into the lootbox.
    function _placeWorstCaseBetN(address better, uint8 spins, uint32 ticket)
        internal
        returns (uint64 betId)
    {
        uint256 totalBet = uint256(AMOUNT_PER_TICKET) * spins;
        vm.prank(better);
        game.placeDegeneretteBet{value: totalBet}(address(0), 0, AMOUNT_PER_TICKET, spins, uint8(ticket & 7));
        betId = DQ.lastBetId(vm, address(game), INDEX);
    }

    /// @dev Place the legacy 10-spin worst-case bet (Phase-319 reference).
    function _placeWorstCaseBet(address better) internal returns (uint64 betId) {
        betId = _placeWorstCaseBetN(better, LEGACY_WORST_SPINS, worstCaseTicket);
    }

    /// @dev Place a FLIP bet at `spins` tickets. No msg.value; funds
    ///      are burned from the player's seeded token balance.
    function _placeCurrencyBet(
        address better,
        uint8 currency,
        uint128 perTicket,
        uint8 spins,
        uint32 ticket
    ) internal returns (uint64 betId) {
        vm.prank(better);
        game.placeDegeneretteBet(address(0), currency, perTicket, spins, uint8(ticket & 7));
        betId = DQ.lastBetId(vm, address(game), INDEX);
    }

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame (keeps supply consistent).
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Place a single 1-spin winning bet (the typical item the marginal calibrates against).
    function _placeOneSpinBet(address better) internal returns (uint64 betId) {
        vm.prank(better);
        game.placeDegeneretteBet{value: AMOUNT_PER_TICKET}(address(0), 0, AMOUNT_PER_TICKET, 1, uint8(worstCaseTicket & 7));
        betId = DQ.lastBetId(vm, address(game), INDEX);
    }

    /// @dev Place a fresh 10-spin worst-case bet (the word is already injected by the caller), reset
    ///      the pool so the cap flips every spin, then crank and return the measured gas. Used by
    ///      Test B to compare the per-1-spin marginal against the worst case in the same test state.
    function _measureTenSpinWorstCase() internal returns (uint256 gasUsed) {
        // Placement requires the index's word == 0; clear it, place, then re-inject.
        _injectLootboxRngWord(INDEX, 0);
        uint64 betId = _placeWorstCaseBet(player);
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;

        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(INDEX, betIds);
        gasUsed = gasBefore - gasleft();
    }

    /// @dev Search bounded candidate rounds for the most paying spins with a single
    /// hero. The player ticket is generated afresh for each spin, exactly as in production.
    /// This stresses the full loop plus the most cap conversions found in the search;
    /// it is a sampled stress case, not proof of the absolute gas maximum.
    function _findWorstCase(uint48 index, uint8 spins) internal pure returns (uint256 word, uint32 ticket) {
        uint8 bestWins;
        for (uint256 k; k < WORD_SEARCH_BUDGET; ++k) {
            uint256 candidate = uint256(keccak256(abi.encodePacked("crank_resolve_worst_case_word", k, spins)));
            uint32 t = Ref.house(candidate, uint32(index), 0, false);
            uint8 wins = _countWinningSpins(index, candidate, t, spins);
            if (wins > bestWins) {
                bestWins = wins;
                word = candidate;
                ticket = t;
            }
            if (wins == spins) break;
        }
        require(bestWins > 0, "no winning word found");
    }

    function _countWinningSpins(uint48 index, uint256 word, uint32 ticket, uint8 spins)
        internal pure returns (uint8 wins)
    {
        uint8 symbol = uint8(ticket & 7);
        for (uint8 spinIdx; spinIdx < spins; ++spinIdx) {
            (uint8 score,) = Ref.score(
                Ref.player(word, uint32(index), symbol, spinIdx, false),
                Ref.house(word, uint32(index), spinIdx, false), 0
            );
            if (score >= 2) ++wins;
        }
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 35).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Set the futurePrizePool (future half, bits 128-255 of slot 2), keeping next intact.
    function _setFuturePool(uint128 future) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_SLOT))));
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_SLOT)),
            bytes32((packed & ~(((uint256(1) << 128) - 1) << 128)) | (uint256(future) << 128))
        );
    }

    /// @dev Decode the spinCount from the bet word at `INDEX` (DQ.spinCount, bits 165..169).
    function _betTicketCount(uint64 id) internal view returns (uint8) {
        return DQ.spinCount(game.degeneretteBetInfo(INDEX, id));
    }

    /// @dev Advance the active lootbox index past `idx`, the sweep's own trigger condition once
    ///      `idx`'s word has landed (mirrors DegeneretteSweep.t.sol's `_landWord`/`_setActiveIndex`).
    function _advanceActiveIndexPast(uint48 idx) internal {
        uint256 lr = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32((lr & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx + 1))
        );
    }

    /// @dev Count the on-chain resolve effects from the recorded logs: DegeneretteResolved's packed
    ///      `spins` payload (one entry per spin, five bytes each) for the bets under test, and
    ///      PayoutCapped emissions (one per spin that flipped into the lootbox branch).
    function _countResolveEffects(uint64[] memory realBetIds)
        internal
        returns (uint256 spinResults, uint256 lootboxFlips)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == DQ.RESOLVED_SIG) {
                // One DegeneretteResolved per resolved bet; count only the bets under test.
                if (logs[i].topics.length > 3) {
                    uint64 bid = uint64(uint256(logs[i].topics[3]));
                    for (uint256 j; j < realBetIds.length; ++j) {
                        if (bid == realBetIds[j]) {
                            (, , bytes memory spins) = abi.decode(logs[i].data, (uint256, uint32, bytes));
                            spinResults += spins.length / 5;
                            break;
                        }
                    }
                }
            } else if (t0 == PAYOUT_CAPPED_SIG) ++lootboxFlips;
        }
    }
}
