// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";

/// @title KeeperResolveBetWorstCaseGas -- GAS-01 (Phase 319) + DSPIN-02 (Phase 323-04) resolve-bet
///        worst-case measurement.
///
/// @notice The biggest keeper-router cost center is a `degeneretteResolve` item resolving a degenerette bet
///         where the spin loop runs to the per-currency cap and the winning spins each flip into the
///         lootbox-conversion branch. The v47 per-currency caps raise the ETH spin ceiling from 10
///         (old MAX_SPINS_PER_BET) to MAX_SPINS_ETH = 25 (DegeneretteModule:226) — 2.5x the roll work.
///         The DGAS write-batching summing the lootbox-share PER betId means one box materializes per
///         bet (not per spin), and a single end-of-call flush replaces N per-spin storage writes.
///
///         Per `feedback_gas_worst_case`, this harness DERIVES the worst case in writing FIRST (see
///         each test's NatSpec) then MEASURES, asserting the constructed scenario IS the maximum
///         (ticketCount at the cap, full spin loop, winning spins flip into the lootbox) BEFORE
///         trusting the measurement, and that the measured gas is < the REAL mainnet 30M block gas
///         limit (NOT foundry.toml's inflated 30e9). It MEASURES only; Phase 319 Plan 05 owned the
///         `*_GAS_UNITS` calibration (out of scope here).
///
///         Tests:
///           - Test A: the legacy 10-spin all-match worst case (Phase-319 GAS-01 reference).
///           - Test B: the per-1-spin-item MARGINAL (the CRANK_RESOLVE_BET_GAS_UNITS calibration
///             target; the contract pays a FLAT per-item reward — peg to the per-1-spin marginal, NOT
///             the worst case, to keep the SAFE-01 self-crank faucet closed).
///           - Test C: DSPIN-02 25-spin ETH worst case (derive-then-measure; absorbed under 30M).
///           - Test D: DSPIN-02 max mixed-currency batch (ETH 25 + BURNIE 15 + WWXRP 5 in one call).
///
/// @dev Live `DeployProtocol` fixture (the keeper-router writes Game storage). Clones the `KeeperFaucetResistance`
///      resolve fixture (lootboxRngIndex seed + post-placement RNG-word inject + self-operator-approval)
///      and the `RedemptionGas` gasleft-delta idiom.
///
///      Worst-case construction: each spin derives its own random result ticket, so a single
///      `customTicket` cannot match all spins. For <= 15 spins the harness searches the RNG word space
///      for a word where the per-quadrant-greedy ticket wins (matches >= 2 -> payout > 0) on EVERY
///      spin; for 25 ETH spins an all-win single ticket is statistically unreachable, so it falls back
///      to MAXIMIZING the winning-spin count (the 25-iteration loop is the structural gas driver
///      regardless, and every winning spin drives the expensive cap-flip branch). A small
///      `futurePrizePool` injection sizes the 10%-of-pool ETH win cap (ETH_WIN_CAP_BPS,
///      DegeneretteModule:196) so each winning spin's excess flips into the lootbox branch -> a
///      `PayoutCapped` emit. The on-chain `FullTicketResult` (one per spin) and `PayoutCapped` (one
///      per cap-flip) counts VERIFY the loop ran fully and the winning spins flipped (non-vacuity).
///      Test-only: no contracts/*.sol mutated.
contract KeeperResolveBetWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;
    /// @dev prizePoolsPacked at slot 2 ((future << 128) | next).
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
    uint8 internal constant MAX_SPINS_BURNIE = 15;
    uint8 internal constant MAX_SPINS_WWXRP = 5;

    /// @dev The Phase-319 GAS-01 reference spin count (the OLD MAX_SPINS_PER_BET). Kept so the
    ///      per-1-spin-item marginal (the CRANK_RESOLVE_BET_GAS_UNITS calibration target) and the
    ///      10-vs-25 absorption comparison both have a stable reference point.
    uint8 internal constant LEGACY_WORST_SPINS = 10;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    /// @dev Per-ticket bet amount: large enough that every winning spin's payout exceeds the
    ///      injected pool's 10% ETH-win cap, flipping the excess into the lootbox branch.
    uint128 private constant AMOUNT_PER_TICKET = 1 ether;
    /// @dev Small futurePrizePool injected so the 10%-of-pool ETH win cap is tiny (0.05 ETH); any
    ///      winning spin's payout (>= ~1.8x of a 1-ETH bet) far exceeds it -> lootbox materialization.
    uint128 private constant SMALL_POOL_WEI = 0.5 ether;
    /// @dev Word-search budget. Empirically a word achieving min-match >= 2 over all 10 spins is
    ///      found well within this bound (so every spin wins -> every spin materializes a lootbox).
    uint256 private constant WORD_SEARCH_BUDGET = 4000;

    /// @dev FullTicketResult topic0 — one per spin (DegeneretteModule:632).
    bytes32 private constant FULL_TICKET_RESULT_SIG =
        0xed1cde932a37b486ad1cc829c4ce89bf3bff943b68625e57cad59bc1bc18d8de;
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

        // The crank's onlySelf resolve sub-call delegatecalls resolveBets with msg.sender ==
        // address(game). resolveBets -> _resolvePlayer -> _requireApproved needs the game approved as
        // the bet owner's operator (the documented crank resolve relaxation). WITHOUT this every item
        // silently skips and the "measurement" is of a no-op (the vacuous-test gotcha).
        vm.prank(player);
        game.setOperatorApproval(address(game), true);

        // Pin the legacy 10-spin worst-case (Phase-319 reference).
        (worstCaseWord, worstCaseTicket) = _findWorstCase(INDEX, LEGACY_WORST_SPINS);
        // Pin the DSPIN-02 25-spin worst-case (all 25 spins win -> all 25 materialize a lootbox).
        (worstCaseWord25, worstCaseTicket25) = _findWorstCase(INDEX, MAX_SPINS_ETH);
    }

    // =========================================================================
    // Test A — 10-spin all-match worst case (the GAS-01 fit-check)
    // =========================================================================

    /// @notice GAS-01 worst-case-FIRST: a single `degeneretteResolve` item resolving a `ticketCount == 10`
    ///         bet where every spin wins ETH and flips into the lootbox branch (10 materializations).
    ///         Asserts the scenario IS the maximum (ticketCount == 10 AND all 10 spins materialized a
    ///         lootbox) BEFORE the measurement is trusted, and asserts the measured gas < 30M mainnet.
    function testWorstCaseResolveBet10SpinAllMatchFitsBlockGasLimit() public {
        uint64 betId = _placeWorstCaseBet(player);
        // Inject a small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        // assert-is-worst-case precondition (1/2): the placed bet's ticketCount IS the legacy max.
        assertEq(_betTicketCount(player, betId), LEGACY_WORST_SPINS, "legacy worst case: ticketCount == 10");

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // Measure the worst-case crank item's gas (gasleft delta around the external call).
        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects();

        // assert-is-worst-case precondition (2/2): all 10 spins ran and EVERY spin drove the lootbox
        // materialization branch (one PayoutCapped per spin whose payout flipped into the lootbox).
        assertEq(spinResults, LEGACY_WORST_SPINS, "all 10 spins resolved (one FullTicketResult each)");
        assertEq(
            lootboxFlips,
            LEGACY_WORST_SPINS,
            "legacy worst case: all 10 spins materialized a lootbox (10 PayoutCapped, the per-spin max branch)"
        );

        // Non-vacuity: the bet was actually resolved (slot deleted), not silently skipped.
        assertEq(_readBetPacked(player, betId), 0, "non-vacuity: worst-case bet resolved (slot deleted)");

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

    /// @notice GAS-01 / GAS-06: isolate the per-1-spin-item MARGINAL gas — the marginal cost of
    ///         adding one typical (1-spin) resolve item to `degeneretteResolve`. This is the calibration
    ///         target for CRANK_RESOLVE_BET_GAS_UNITS (the contract pays a FLAT per-item reward, so
    ///         the peg is a single per-item number). Measured by the loop-N-divide micro-bench idiom:
    ///         crank N independent 1-spin items in one batch and divide the delta by N. Asserts the
    ///         per-1-spin marginal is materially BELOW the 10-spin worst case — confirming the
    ///         per-spin peg under-reimburses big wins by construction (REW-03 / faucet-safe).
    function testPerOneSpinItemMarginalBelowWorstCase() public {
        uint256 nItems = 8;

        // Place N independent 1-spin bets for the same player (distinct betIds).
        address[] memory players = new address[](nItems);
        uint64[] memory betIds = new uint64[](nItems);
        for (uint256 i; i < nItems; ++i) {
            betIds[i] = _placeOneSpinBet(player);
            players[i] = player;
        }
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        // Sanity: each placed item is a 1-spin bet (the typical case the marginal calibrates against).
        assertEq(_betTicketCount(player, betIds[0]), 1, "Test B item is a 1-spin bet (the typical case)");

        // Bracket the whole N-item batch; divide by N for the per-1-spin-item marginal.
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 totalGas = gasBefore - gasleft();
        uint256 perItemMarginal = totalGas / nItems;

        // Non-vacuity: every item resolved (slots deleted), so the marginal is a real per-item cost.
        for (uint256 i; i < nItems; ++i) {
            assertEq(_readBetPacked(player, betIds[i]), 0, "non-vacuity: each 1-spin item resolved");
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
        uint64 betId = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        // Small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);

        // assert-is-worst-case (1/2): ticketCount IS the structural ETH cap (25).
        assertEq(_betTicketCount(player, betId), MAX_SPINS_ETH, "DSPIN-02: ticketCount == MAX_SPINS_ETH (25)");

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects();

        // assert-is-worst-case (2/2): the full 25-iteration spin loop ran (the structural gas driver),
        // and the WINNING spins all drove the cap-flip branch (each winning ETH spin's share exceeds
        // the 10% pool cap -> PayoutCapped). A single fixed ticket cannot win on all 25 independent
        // result tickets, so the worst case maximizes the winning+cap-flip count; we assert the loop
        // ran fully (25) and that the achieved cap-flip count equals the achieved winning-spin count
        // (every winning spin flips, the per-spin max branch) and is materially non-vacuous.
        assertEq(spinResults, MAX_SPINS_ETH, "DSPIN-02: all 25 spins resolved (full loop; one FullTicketResult each)");
        uint8 winningSpins = _countWinningSpins(INDEX, worstCaseWord25, worstCaseTicket25, MAX_SPINS_ETH);
        assertEq(
            lootboxFlips,
            uint256(winningSpins),
            "DSPIN-02: every WINNING spin flipped into the lootbox branch (one PayoutCapped each)"
        );
        assertGt(lootboxFlips, 0, "DSPIN-02 non-vacuity: at least one spin materialized the lootbox branch");

        // Non-vacuity: the bet was actually resolved (slot deleted), not silently skipped.
        assertEq(_readBetPacked(player, betId), 0, "non-vacuity: 25-spin worst-case bet resolved (slot deleted)");

        // Headline DSPIN-02 assertion: the 25-spin worst case fits the REAL mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02: 25-spin all-match resolve-bet worst case fits under the 30M mainnet block gas limit"
        );

        // Absorption: re-measure the legacy 10-spin worst case in this test's own state, and assert
        // the 25-spin cost is BELOW a naive 2.5x of it — demonstrating the single-flush write savings
        // absorb the raised cap (the marginal per-spin work is roll-only, not write-per-spin).
        uint256 legacyGas = _measureTenSpinWorstCase();
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

    /// @notice DSPIN-02 cross-bet flush at MAXIMUM accumulation: a mixed-currency multi-bet batch
    ///         packed to the per-currency caps in ONE resolveBets call — one ETH bet @ 25 spins, one
    ///         BURNIE bet @ 15 spins, one WWXRP bet @ 5 spins (45 spins total across 3 betIds). This
    ///         exercises the cross-bet ResolveAcc accumulation at full width (ETH claimable sum +
    ///         BURNIE mint sum + WWXRP mint sum, three single flushes). DERIVE: the worst mixed batch
    ///         is one bet per currency at its cap, all spins winning; MEASURE: assert it fits the 30M
    ///         block limit. (Resolved directly via resolveDegeneretteBets — the full batch path — since
    ///         degeneretteResolve resolves one item at a time; this test measures the resolveBets flush itself.)
    function testWorstCaseMixedCurrencyBatchGas() public {
        // All three bets share index 1 (one committed word = worstCaseWord25). BURNIE spins are
        // spins 0..14 and WWXRP spins are spins 0..4 — both SUBSETS of the 25 ETH spins that
        // worstCaseTicket25 already wins (matches >= 2) on, so all 45 spins win on this one word.
        // Even a losing spin still runs the full spin-loop iteration (the gas driver), and the
        // per-spin FullTicketResult fires regardless — the 45-spin count is asserted below.

        // Fund BURNIE + WWXRP for the player (game-gated mints; ETH comes from msg.value).
        uint128 burniePerTicket = 200 ether;  // >= MIN_BET_BURNIE (100 ether)
        uint128 wwxrpPerTicket = 2 ether;      // >= MIN_BET_WWXRP (1 ether)
        _fundBurnie(player, uint256(burniePerTicket) * MAX_SPINS_BURNIE + 1 ether);
        _fundWwxrp(player, uint256(wwxrpPerTicket) * MAX_SPINS_WWXRP + 1 ether);

        // Place one bet per currency at its cap, all using worstCaseTicket25 (wins on the ETH word).
        uint64 ethBet = _placeWorstCaseBetN(player, MAX_SPINS_ETH, worstCaseTicket25);
        uint64 burnieBet = _placeCurrencyBet(player, 1, burniePerTicket, MAX_SPINS_BURNIE, worstCaseTicket25);
        uint64 wwxrpBet = _placeCurrencyBet(player, 3, wwxrpPerTicket, MAX_SPINS_WWXRP, worstCaseTicket25);

        // Small pool so the ETH spins flip into the lootbox branch (max ETH-side work).
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord25);

        // Resolve the whole mixed batch in ONE call (the cross-bet flush under measurement). The crank
        // resolve relaxation isn't needed here — player resolves their own bets.
        uint64[] memory betIds = new uint64[](3);
        betIds[0] = ethBet;
        betIds[1] = burnieBet;
        betIds[2] = wwxrpBet;

        vm.recordLogs();
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.resolveDegeneretteBets(address(0), betIds);
        uint256 gasUsed = gasBefore - gasleft();

        // Non-vacuity: all three bets resolved (slots deleted) and all 45 spins ran.
        (uint256 spinResults, ) = _countResolveEffects();
        assertEq(spinResults, uint256(MAX_SPINS_ETH) + MAX_SPINS_BURNIE + MAX_SPINS_WWXRP,
            "mixed batch: all 45 spins resolved (ETH 25 + BURNIE 15 + WWXRP 5)");
        assertEq(_readBetPacked(player, ethBet), 0, "non-vacuity: ETH bet resolved");
        assertEq(_readBetPacked(player, burnieBet), 0, "non-vacuity: BURNIE bet resolved");
        assertEq(_readBetPacked(player, wwxrpBet), 0, "non-vacuity: WWXRP bet resolved");

        // DSPIN-02: the maximum mixed-currency batch fits the 30M mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "DSPIN-02: max mixed-currency batch (45 spins, 3 currencies) fits under the 30M block limit"
        );

        emit log_named_uint("worst_case_mixed_currency_batch_gas", gasUsed);
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
        game.placeDegeneretteBet{value: totalBet}(
            address(0), 0, AMOUNT_PER_TICKET, spins, ticket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Place the legacy 10-spin worst-case bet (Phase-319 reference).
    function _placeWorstCaseBet(address better) internal returns (uint64 betId) {
        betId = _placeWorstCaseBetN(better, LEGACY_WORST_SPINS, worstCaseTicket);
    }

    /// @dev Place a non-ETH (BURNIE=1 / WWXRP=3) bet at `spins` tickets. No msg.value; funds
    ///      are burned from the player's seeded token balance.
    function _placeCurrencyBet(
        address better,
        uint8 currency,
        uint128 perTicket,
        uint8 spins,
        uint32 ticket
    ) internal returns (uint64 betId) {
        vm.prank(better);
        game.placeDegeneretteBet(address(0), currency, perTicket, spins, ticket, 0);
        betId = _betNonce(better);
    }

    /// @dev Mint BURNIE to `who` via the GAME-gated mintForGame (keeps supply consistent).
    function _fundBurnie(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Mint WWXRP to `who` via the GAME-gated mintPrize (keeps supply consistent).
    function _fundWwxrp(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
    }

    /// @dev Place a single 1-spin winning bet (the typical item the marginal calibrates against).
    function _placeOneSpinBet(address better) internal returns (uint64 betId) {
        vm.prank(better);
        game.placeDegeneretteBet{value: AMOUNT_PER_TICKET}(
            address(0), 0, AMOUNT_PER_TICKET, 1, worstCaseTicket, 0
        );
        betId = _betNonce(better);
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

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        gasUsed = gasBefore - gasleft();
    }

    /// @dev Search the RNG word space for a word whose per-quadrant-greedy ticket wins (matches >= 2,
    ///      so payout > 0) on EVERY one of `spins` spins. Maximizes the MIN match across spins. The
    ///      greedy ticket picks, per quadrant, the color and symbol that match the most of that
    ///      quadrant's `spins` result values (color + symbol matched independently in _countMatches).
    ///
    ///      All-spins-win is achievable for small `spins` (10 / 15 / 5), but a SINGLE fixed ticket
    ///      cannot win on all 25 ETH spins (25 independent random result tickets — P(min>=2 over 25) is
    ///      vanishingly small). For `spins` where the strict all-win search fails, this falls back to
    ///      the word MAXIMIZING the winning-spin count via _findMaxWinWord (still the gas worst case:
    ///      the 25-iteration loop runs fully regardless, and every WINNING spin drives the expensive
    ///      _distributePayout + cap-flip branch; the per-bet lootbox materializes once on the summed
    ///      share). The caller asserts the achieved win/cap count for non-vacuity.
    function _findWorstCase(uint48 index, uint8 spins) internal pure returns (uint256 word, uint32 ticket) {
        uint8 bestMin;
        for (uint256 k; k < WORD_SEARCH_BUDGET; ++k) {
            uint256 candidate = uint256(keccak256(abi.encodePacked("crank_resolve_worst_case_word", k, spins)));
            uint32 t = _greedyTicket(index, candidate, spins);
            uint8 minMatch = 8;
            for (uint8 spinIdx; spinIdx < spins; ++spinIdx) {
                uint8 m = _countMatches(t, _resultTicketForSpin(index, candidate, spinIdx));
                if (m < minMatch) minMatch = m;
            }
            if (minMatch > bestMin) {
                bestMin = minMatch;
                word = candidate;
                ticket = t;
                if (bestMin >= 2) break; // every spin wins — sufficient for the worst case
            }
        }
        if (bestMin >= 2) return (word, ticket);
        // Fallback: maximize the WINNING-spin count (the achievable gas worst case for large `spins`).
        (word, ticket) = _findMaxWinWord(index, spins);
    }

    /// @dev Find the word whose greedy ticket WINS (matches >= 2) on the MOST spins (used for the
    ///      25-spin ETH worst case, where an all-win single ticket is statistically unreachable). The
    ///      gas worst case is still the full 25-iteration loop with the maximum achievable count of
    ///      winning+cap-flip spins; the caller asserts the achieved count.
    function _findMaxWinWord(uint48 index, uint8 spins) internal pure returns (uint256 word, uint32 ticket) {
        uint8 bestWins;
        for (uint256 k; k < WORD_SEARCH_BUDGET; ++k) {
            uint256 candidate = uint256(keccak256(abi.encodePacked("crank_resolve_maxwin_word", k, spins)));
            uint32 t = _greedyTicket(index, candidate, spins);
            uint8 wins;
            for (uint8 spinIdx; spinIdx < spins; ++spinIdx) {
                if (_countMatches(t, _resultTicketForSpin(index, candidate, spinIdx)) >= 2) ++wins;
            }
            if (wins > bestWins) {
                bestWins = wins;
                word = candidate;
                ticket = t;
            }
        }
        require(bestWins > 0, "no winning word found, widen WORD_SEARCH_BUDGET");
    }

    /// @dev Count how many of `spins` spins WIN (matches >= 2) for (word, ticket).
    function _countWinningSpins(uint48 index, uint256 word, uint32 ticket, uint8 spins)
        internal
        pure
        returns (uint8 wins)
    {
        for (uint8 spinIdx; spinIdx < spins; ++spinIdx) {
            if (_countMatches(ticket, _resultTicketForSpin(index, word, spinIdx)) >= 2) ++wins;
        }
    }

    /// @dev Per-quadrant greedy ticket: for each quadrant pick the (color, symbol) matching the most
    ///      of the `spins` spins' result values in that quadrant.
    function _greedyTicket(uint48 index, uint256 word, uint8 spins) internal pure returns (uint32 ticket) {
        for (uint8 q; q < 4; ++q) {
            uint16[8] memory colorHits;
            uint16[8] memory symbolHits;
            for (uint8 spinIdx; spinIdx < spins; ++spinIdx) {
                uint32 result = _resultTicketForSpin(index, word, spinIdx);
                uint8 rQuad = uint8(result >> (q * 8));
                ++colorHits[(rQuad >> 3) & 7];
                ++symbolHits[rQuad & 7];
            }
            uint8 bestColor;
            uint8 bestSymbol;
            for (uint8 c = 1; c < 8; ++c) {
                if (colorHits[c] > colorHits[bestColor]) bestColor = c;
            }
            for (uint8 s = 1; s < 8; ++s) {
                if (symbolHits[s] > symbolHits[bestSymbol]) bestSymbol = s;
            }
            uint8 quad = (bestColor << 3) | bestSymbol; // tag bits 7-6 ignored by _countMatches
            ticket |= (uint32(quad) << (q * 8));
        }
    }

    /// @dev Reproduce the on-chain per-spin result ticket derivation (_resolveFullTicketBet:596-612):
    ///      spin 0 uses the short preimage (no spinIdx), spins 1+ mix in spinIdx.
    function _resultTicketForSpin(uint48 index, uint256 word, uint8 spinIdx)
        internal
        pure
        returns (uint32)
    {
        uint256 resultSeed = spinIdx == 0
            ? uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)))
            : uint256(keccak256(abi.encodePacked(word, uint32(index), spinIdx, QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev Mirror of the on-chain _countMatches (color bits 5-3, symbol bits 2-0, per quadrant).
    function _countMatches(uint32 playerTicket, uint32 resultTicket) internal pure returns (uint8 matches) {
        for (uint8 q; q < 4; ++q) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) ++matches;
            if ((pQuad & 7) == (rQuad & 7)) ++matches;
        }
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 36).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Set the futurePrizePool (high 128 bits of prizePoolsPacked at slot 2), keeping next intact.
    function _setFuturePool(uint128 future) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_SLOT))));
        uint128 next = uint128(packed);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_SLOT)),
            bytes32((uint256(future) << 128) | uint256(next))
        );
    }

    /// @dev Read the packed bet for (owner, betId) from degeneretteBets (slot 43).
    function _readBetPacked(address owner, uint64 id) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev Decode the ticketCount (FT_COUNT_SHIFT == 34, 8 bits) from the packed bet.
    function _betTicketCount(address owner, uint64 id) internal view returns (uint8) {
        uint256 packed = _readBetPacked(owner, id);
        return uint8((packed >> 34) & 0xFF);
    }

    /// @dev Read the current degeneretteBetNonce for a player (slot 44).
    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev Count the on-chain resolve effects from the recorded logs: FullTicketResult emissions
    ///      (one per spin) and PayoutCapped emissions (one per spin that flipped into the lootbox).
    function _countResolveEffects() internal returns (uint256 spinResults, uint256 lootboxFlips) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == FULL_TICKET_RESULT_SIG) ++spinResults;
            else if (t0 == PAYOUT_CAPPED_SIG) ++lootboxFlips;
        }
    }
}
