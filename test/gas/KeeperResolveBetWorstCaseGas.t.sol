// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

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
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;
    /// @dev prizePoolsPacked at slot 2 ([future:128 | next:128]).
    uint256 private constant PRIZE_POOLS_SLOT = 2;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev v47 per-currency spin caps (DegeneretteModule:226-228). The ETH cap (25) is the
    ///      structural spin-loop ceiling for the DSPIN-02 worst case — 2.5x the old 10-spin bound.
    uint8 internal constant MAX_SPINS_ETH = 25;
    uint8 internal constant MAX_SPINS_FLIP = 15;

    /// @dev The Phase-319 GAS-01 reference spin count (the OLD MAX_SPINS_PER_BET). Kept so the
    ///      per-1-spin-item marginal and the 10-vs-25 absorption comparison both have a stable
    ///      reference point. The sweep (`mineFlip`'s Degenerette stage) that resolves these bets
    ///      is the only door; these numbers are pure gas-shape measurements.
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
        RecyclingState.seedWriteBuffer(address(game), INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        // The sweep (mineFlip) is permissionless (any caller may settle any queued bet;
        // payouts always credit the bet's owner), so no operator-approval dance is needed for
        // the cranker/keeper to resolve `player`'s bets.

        // Pin the legacy 10-spin worst-case (Phase-319 reference).
        (worstCaseWord, worstCaseTicket) = _findWorstCase(INDEX, LEGACY_WORST_SPINS);
        // Pin the DSPIN-02 25-spin worst-case (all 25 spins win -> all 25 materialize a lootbox).
        (worstCaseWord25, worstCaseTicket25) = _findWorstCase(INDEX, MAX_SPINS_ETH);
    }

    // =========================================================================
    // Test A — 10-spin all-match worst case (the GAS-01 fit-check)
    // =========================================================================

    /// @notice GAS-01 worst-case-FIRST: a single sweep-resolved item with a `ticketCount == 10`
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
        _advanceActiveIndexPast(INDEX);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        uint256 bound = _ethStageBound(LEGACY_WORST_SPINS, game.degeneretteBetInfo(INDEX, betId));

        // Measure the worst-case bet's resolve as its own engine stage (the mineFlip that resolves
        // it, minus the same call with the bet queue emptied).
        (uint256 gasUsed, uint256 stageGas) = _crankResolve();

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

        // The headline GAS-01 assertion, per checkpoint: the worst case resolves inside the
        // admission the engine charges for it (the declared bound, itself far under 10M).
        assertLe(stageGas, bound, "GAS-01: 10-spin all-match resolve stays inside its declared admission");
        assertLe(bound, 10_000_000, "the declared admission is one realistic chunk");

        emit log_named_uint("worst_case_resolve_bet_10spin_allmatch_gas", stageGas);
        emit log_named_uint("worst_case_resolve_bet_10spin_mineflip_gas", gasUsed);
        emit log_named_uint("declared_10spin_admission", bound);
        emit log_named_uint("worst_case_resolve_bet_lootbox_materializations", lootboxFlips);
    }

    // =========================================================================
    // Test B — per-1-spin-item MARGINAL (the Plan 05 calibration target)
    // =========================================================================

    /// @notice GAS-01: isolate the per-1-spin-item MARGINAL gas — the marginal cost of adding one
    ///         typical (1-spin) resolve item to the sweep (`mineFlip`'s Degenerette stage); this
    ///         is a pure gas-shape measurement. Measured by the loop-N-divide
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
        _advanceActiveIndexPast(INDEX);

        uint256 declared = GasBounds.DEGENERETTE_TAIL_GAS + GasBounds.ENGINE_BOUNDARY;
        for (uint256 i; i < nItems; ++i) declared += _betBound(0, 1, game.degeneretteBetInfo(INDEX, betIds[i]));

        // Bracket the whole N-item stage; divide by N for the per-1-spin-item marginal.
        (, uint256 totalGas) = _crankResolve();
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
        assertLe(totalGas, declared, "the N-item stage stays inside the admissions its bets were charged");
        emit log_named_uint("declared_n_item_admission", declared);

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

        // _measureTenSpinWorstCase leaves the active index moved past whatever fresh index it
        // used; the sweep only ever reaches an index once, so this 25-spin bet places at the
        // NEW current index and derives its own worst-case word/ticket for it (the setUp-pinned
        // worstCaseWord25/worstCaseTicket25 are entropy-specific to index 1 and would not be a
        // genuine worst case at a different index).
        uint48 idx = _currentActiveIndex();
        (uint256 word25, uint32 ticket25) = _findWorstCase(idx, MAX_SPINS_ETH);
        uint64 betId = _placeWorstCaseBetN(player, MAX_SPINS_ETH, ticket25);
        // Small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(idx, word25);
        _advanceActiveIndexPast(idx);

        // assert-is-worst-case (1/2): ticketCount IS the structural ETH cap (25).
        assertEq(DQ.spinCount(game.degeneretteBetInfo(idx, betId)), MAX_SPINS_ETH, "DSPIN-02: ticketCount == MAX_SPINS_ETH (25)");

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        uint256 bound = _ethStageBound(MAX_SPINS_ETH, game.degeneretteBetInfo(idx, betId));

        (, uint256 gasUsed) = _crankResolve();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects(betIds);

        // assert-is-worst-case (2/2): the full 25-iteration spin loop ran (the structural gas driver),
        // and the WINNING spins all drove the cap-flip branch (each winning ETH spin's share exceeds
        // the 10% pool cap -> PayoutCapped). A single fixed ticket cannot win on all 25 independent
        // result tickets, so the worst case maximizes the winning+cap-flip count; we assert the loop
        // ran fully (25) and that the achieved cap-flip count equals the achieved winning-spin count
        // (every winning spin flips, the per-spin max branch) and is materially non-vacuous.
        assertEq(spinResults, MAX_SPINS_ETH, "DSPIN-02: all 25 spins resolved (full loop; packed into the one DegeneretteResolved event)");
        uint8 winningSpins = _countWinningSpins(idx, word25, ticket25, MAX_SPINS_ETH);
        assertEq(
            lootboxFlips,
            uint256(winningSpins),
            "DSPIN-02: every WINNING spin flipped into the lootbox branch (one PayoutCapped each)"
        );
        assertGt(lootboxFlips, 0, "DSPIN-02 non-vacuity: at least one spin materialized the lootbox branch");

        // Non-vacuity: the bet was actually resolved (queue word zeroed), not silently skipped.
        assertEq(game.degeneretteBetInfo(idx, betId), 0, "non-vacuity: 25-spin worst-case bet resolved (word zeroed)");

        // Headline DSPIN-02 assertion, per checkpoint: the 25-spin worst case resolves inside the
        // admission the engine charges for it (the declared bound, itself far under 10M).
        assertLe(gasUsed, bound, "DSPIN-02: 25-spin all-match resolve stays inside its declared admission");
        assertLe(bound, 10_000_000, "the declared admission is one realistic chunk");

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
        emit log_named_uint("declared_25spin_admission", bound);
    }

    // =========================================================================
    // Sweep-path variants — the SAME worst-case bet shapes, resolved at a fresh, untouched
    // index using the setUp-pinned word/ticket directly (Tests A-C above derive their own
    // per-index word/ticket instead, since some reuse the sweep more than once per test).
    // =========================================================================

    /// @notice DSPIN-02 via the sweep: the same 25-spin all-match ETH worst case, resolved by
    ///         `mineFlip` once the index's word lands and the active lootbox index moves past
    ///         it (the sweep's own trigger condition — see DegeneretteSweep.t.sol `_landWord`).
    ///         Proves the automatic path absorbs the identical worst case, not just the manual one.
    function testWorstCaseResolveBet25SpinAllMatchViaSweepFitsBlockGasLimit() public {
        uint64 betId = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);
        _advanceActiveIndexPast(INDEX);

        assertEq(_betTicketCount(betId), MAX_SPINS_ETH, "DSPIN-02 sweep: ticketCount == MAX_SPINS_ETH (25)");
        uint256 bound = _ethStageBound(MAX_SPINS_ETH, game.degeneretteBetInfo(INDEX, betId));

        (uint256 callGas, uint256 gasUsed) = _crankResolve();

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

        assertLe(gasUsed, bound, "DSPIN-02 sweep: 25-spin all-match resolve stays inside its declared admission");
        assertLe(bound, 10_000_000, "the declared admission is one realistic chunk");

        emit log_named_uint("worst_case_resolve_bet_25spin_allmatch_via_sweep_gas", gasUsed);
        emit log_named_uint("worst_case_resolve_bet_25spin_mineflip_gas", callGas);
        emit log_named_uint("declared_25spin_admission", bound);
    }

    /// @notice DSPIN-02 mixed-currency batch via the sweep: the same ETH-25 + FLIP-15 worst case
    ///         as `testWorstCaseMixedCurrencyBatchGas`, but resolved automatically by `mineFlip`.
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
        uint256 bound = _ethStageBound(MAX_SPINS_ETH, game.degeneretteBetInfo(INDEX, ethBet))
            + _betBound(1, MAX_SPINS_FLIP, game.degeneretteBetInfo(INDEX, flipBet));

        (uint256 callGas, uint256 gasUsed) = _crankResolve();

        (uint256 spinResults, ) = _countResolveEffects(betIds);
        assertEq(spinResults, uint256(MAX_SPINS_ETH) + MAX_SPINS_FLIP,
            "mixed batch via sweep: all 40 spins resolved (ETH 25 + FLIP 15)");
        assertEq(game.degeneretteBetInfo(INDEX, ethBet), 0, "non-vacuity: ETH bet resolved via sweep");
        assertEq(game.degeneretteBetInfo(INDEX, flipBet), 0, "non-vacuity: FLIP bet resolved via sweep");

        assertLe(gasUsed, bound, "DSPIN-02 sweep: max mixed-currency batch stays inside its declared admissions");
        assertLe(bound, 10_000_000, "the declared admissions fit one realistic chunk");

        emit log_named_uint("worst_case_mixed_currency_batch_via_sweep_gas", gasUsed);
        emit log_named_uint("worst_case_mixed_currency_batch_mineflip_gas", callGas);
        emit log_named_uint("mixed_batch_total_spins", spinResults);
        emit log_named_uint("declared_mixed_admission", bound);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev One same-symbol cohort makes every owner's high-score spins correlate.
    ///      Cold calls include sDGNRS awards, win boxes, the human sweep and bounty. Each call gets
    ///      a realistic 10M allowance and must succeed and progress; the cohort's actual cold work
    ///      exceeds one such allowance, so it splits across calls.
    function test_ColdMineFlipCorrelatedMaxSpinEthBetsStayUnderOrdinaryTier() public {
        (uint256 word, uint8 symbol) = _findHighAwardWord();
        // 48 owners: resolved cold, the cohort measures past one 10M allowance (20 measured 5.5M),
        // so the engine's checkpoints must split it across calls.
        uint64[48] memory ids;
        for (uint256 i; i < 48; ++i) {
            address owner = address(uint160(0xA77000 + i));
            vm.deal(owner, 100 ether);
            ids[i] = _placeWorstCaseBetN(owner, MAX_SPINS_ETH, symbol);
        }
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, word);
        _advanceActiveIndexPast(INDEX);
        uint256 done;
        uint256 calls;
        uint256 awards;
        bytes32 awardTopic = keccak256("PoolTransfer(uint8,address,uint256)");
        while (done < ids.length && calls < 20) {
            // A realistic allowance: the engine admits bets only while the remaining allowance
            // covers each one's declared bound, so a saturated cohort splits across calls.
            _cool();
            vm.recordLogs();
            vm.prank(cranker);
            game.mineFlip{gas: 10_000_000 - 21_000}();
            uint256 used = vm.snapshotGasLastCall("correlated-eth-bet-keeper");
            emit log_named_uint("correlated keeper gross call gas", used);
            Vm.Log[] memory rows = vm.getRecordedLogs();
            for (uint256 i; i < rows.length; ++i) {
                if (rows[i].emitter == address(sdgnrs) && rows[i].topics.length != 0 && rows[i].topics[0] == awardTopic) ++awards;
            }
            uint256 prior = done;
            done = 0;
            for (uint256 i; i < ids.length; ++i) if (game.degeneretteBetInfo(INDEX, ids[i]) == 0) ++done;
            assertGt(done, prior, "each realistic-allowance call makes progress");
            ++calls;
        }
        assertEq(done, ids.length);
        assertGt(awards, 0, "nonvacuity: high-score sDGNRS tail actually executed");
        assertGt(calls, 1, "saturated cohort is split into bounded calls");
    }

    function _findHighAwardWord() private pure returns (uint256 word, uint8 symbol) {
        for (uint256 k; k < WORD_SEARCH_BUDGET; ++k) {
            uint256 candidate = uint256(keccak256(abi.encode("correlated high-score gas", k)));
            for (uint8 hero; hero < 8; ++hero) {
                for (uint8 spin; spin < MAX_SPINS_ETH; ++spin) {
                    (uint8 score,) = Ref.score(Ref.player(candidate, uint32(INDEX), hero, spin, false),
                        Ref.house(candidate, uint32(INDEX), spin, false), 0);
                    if (score >= 7) return (candidate, hero);
                }
            }
        }
        revert("no high-score stress word found");
    }

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

    /// @dev Place a fresh 10-spin worst-case bet at the CURRENT active index and crank it via the
    ///      sweep, returning the measured gas. Used by Test B and Test C to compare against the
    ///      worst case in the same test state. Unlike the removed direct per-id door (which let a
    ///      test reuse one fixed index across many placement/resolve cycles by clearing its word
    ///      between them), the sweep only ever reaches an index once the active pointer has moved
    ///      past it, so each call here must place at a fresh index and derive its own worst-case
    ///      word/ticket for that index rather than reusing the ones setUp pinned for index 1.
    function _measureTenSpinWorstCase() internal returns (uint256 gasUsed) {
        uint48 idx = _currentActiveIndex();
        (uint256 word, uint32 ticket) = _findWorstCase(idx, LEGACY_WORST_SPINS);
        uint64 betId = _placeWorstCaseBetN(player, LEGACY_WORST_SPINS, ticket);
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(idx, word);
        _advanceActiveIndexPast(idx);

        (, gasUsed) = _crankResolve();
        assertEq(game.degeneretteBetInfo(idx, betId), 0, "the reference 10-spin bet resolved");
    }

    /// @dev The current active lootbox RNG index (low 48 bits of lootboxRngPacked).
    function _currentActiveIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
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
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
        // What the request's seal also does: the consumer cursors restart and the new write tag's
        // queues are emptied, so a later cohort's bets sit at positions the Degenerette cursor reads.
        uint256 s14 = uint256(vm.load(address(game), bytes32(uint256(14))));
        vm.store(address(game), bytes32(uint256(14)), bytes32(s14 & ~(uint256(type(uint48).max) << 160)));
        uint256 s56 = uint256(vm.load(address(game), bytes32(uint256(56))));
        vm.store(address(game), bytes32(uint256(56)), bytes32(s56 & ~(uint256(type(uint48).max) << 56)));
        vm.store(address(game), keccak256(abi.encode(uint256((index ^ 1) & 1), DQ.QUEUE_SLOT)), bytes32(0));
        vm.store(address(game), keccak256(abi.encode(uint256((index ^ 1) & 1), uint256(57))), bytes32(0));
        // The day itself is sealed, as after a mid-day request: the delivered cohort's read
        // consumers are the engine's only work, so a measured call ends when the cohort completes.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Measured calls pay cold access, as a fresh keeper transaction does.
    function _cool() internal {
        vm.cool(address(game));
        vm.cool(address(coin));
        vm.cool(address(coinflip));
        vm.cool(address(sdgnrs));
        vm.cool(address(wwxrp));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
    }

    /// @dev Resolve the delivered cohort with one cold mineFlip. Bets resolve only as the engine's
    ///      Degenerette read consumer; `stageGas` isolates that stage: the same call against the
    ///      same state with the read bet queue emptied is the baseline every other stage shares.
    ///      Logs are recorded for the measured call only.
    function _crankResolve() internal returns (uint256 gasUsed, uint256 stageGas) {
        uint48 read = RecyclingState.readBuffer(address(game));
        uint256 snap = vm.snapshotState();
        vm.store(address(game), keccak256(abi.encode(uint256(read & 1), DQ.QUEUE_SLOT)), bytes32(0));
        _cool();
        vm.prank(cranker);
        uint256 g = gasleft();
        game.mineFlip();
        uint256 baseline = g - gasleft();
        vm.revertToStateAndDelete(snap);
        _cool();
        vm.recordLogs();
        vm.prank(cranker);
        g = gasleft();
        game.mineFlip();
        gasUsed = g - gasleft();
        stageGas = gasUsed - baseline;
        emit log_named_uint("cold mineFlip gas", gasUsed);
        emit log_named_uint("Degenerette stage gas (mineFlip minus empty-queue baseline)", stageGas);
    }

    /// @dev The engine's admission for one ETH bet of `spins` (MineFlipGasBounds), plus the stage's
    ///      dispatch boundary and tail that its first admitted bet carries.
    function _ethStageBound(uint8 spins, uint256 betWord) internal pure returns (uint256) {
        return _betBound(0, spins, betWord) + GasBounds.DEGENERETTE_TAIL_GAS + GasBounds.ENGINE_BOUNDARY;
    }

    /// @dev One bet's declared admission: currency base + per-spin, plus the record-claim spin
    ///      when the bet armed one (record flag, bit 171 of the queued word).
    function _betBound(uint8 currency, uint8 spins, uint256 betWord) internal pure returns (uint256 b) {
        b = currency == 0
            ? GasBounds.DEGENERETTE_ETH_BASE_GAS + uint256(spins) * GasBounds.DEGENERETTE_ETH_SPIN_GAS
            : GasBounds.DEGENERETTE_FLIP_BASE_GAS + uint256(spins) * GasBounds.DEGENERETTE_FLIP_SPIN_GAS;
        if ((betWord >> 171) & 1 != 0) b += GasBounds.DEGENERETTE_RECORD_GAS;
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
        RecyclingState.seedWriteBuffer(address(game), idx ^ 1);
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
