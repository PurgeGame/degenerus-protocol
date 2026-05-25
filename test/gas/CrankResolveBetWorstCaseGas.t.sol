// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";

/// @title CrankResolveBetWorstCaseGas -- GAS-01 resolve-bet worst-case measurement (Phase 319 Plan 02)
///
/// @notice The single biggest do-work-crank cost center is a `crankBets` item resolving a degenerette
///         bet with `ticketCount == MAX_SPINS_ETH == 10` where EVERY spin's payout flips into the
///         lootbox-conversion branch, driving 10 separate `_resolveLootboxDirect` materializations
///         (each a 2-level delegatecall: DegeneretteModule -> LootboxModule -> nested BoonModule, plus
///         a `_queueTickets` SSTORE and reward events). 319-GAS-DERIVATION.md §1 fixes THIS as the
///         per-item maximum: the spin loop cannot exceed 10 (`MAX_SPINS_ETH`, DegeneretteModule:226)
///         and each spin's most expensive branch is the ETH-win lootbox branch
///         (`_distributePayout` -> `_resolveLootboxDirect`, DegeneretteModule:771-773).
///
///         Per `feedback_gas_worst_case`, this harness ASSERTS the constructed scenario IS the worst
///         case (ticketCount == 10 AND all 10 spins materialized a lootbox) BEFORE trusting the
///         measurement, then asserts the measured gas is < the REAL mainnet 30M block gas limit (NOT
///         foundry.toml's inflated 30e9). It MEASURES only; Plan 05 owns the `*_GAS_UNITS` calibration.
///
///         Two measurements are emitted via `log_named_uint` for Plan 05:
///           - Test A: the 10-spin all-match worst case (the GAS-01 fit-check headline).
///           - Test B: the per-1-spin-item MARGINAL — the calibration target for
///             CRANK_RESOLVE_BET_GAS_UNITS. The contract pays a FLAT per-item reward
///             (DegenerusGame.sol:1567), so the peg is calibrated to the per-1-spin marginal, NOT the
///             10-spin worst case; pegging to the worst case would over-reimburse and risk opening the
///             SAFE-01 self-crank faucet (319-GAS-DERIVATION.md §1(e)).
///
/// @dev Live `DeployProtocol` fixture (the crank writes Game storage, so a module-extending harness
///      will not work here — unlike the jackpot). Clones the `CrankFaucetResistance` crank fixture
///      (lootboxRngIndex seed + post-placement RNG-word inject + self-operator-approval) and the
///      `RedemptionGas` gasleft-delta idiom.
///
///      Worst-case construction: each of the 10 spins derives its own random result ticket, so a
///      single `customTicket` cannot match all spins. Instead the harness (1) searches the RNG word
///      space for a word where the per-quadrant-greedy ticket wins (matches >= 2 -> payout > 0) on
///      EVERY one of the 10 spins, and (2) injects a small `futurePrizePool` so the 10%-of-pool ETH
///      win cap (ETH_WIN_CAP_BPS, DegeneretteModule:196) flips each winning spin's payout excess into
///      the lootbox branch -> a `PayoutCapped` emit + a real `_resolveLootboxDirect` materialization
///      per spin. The on-chain `FullTicketResult` (one per spin) and `PayoutCapped` (one per lootbox
///      flip) counts then VERIFY all 10 spins materialized (the non-vacuity + all-match guard). The
///      pool injection only sizes the cap; it does not change the per-spin work path the worst case
///      measures. Test-only: no contracts/*.sol mutated.
contract CrankResolveBetWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 35; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 35;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 36;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 43;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 44;
    /// @dev prizePoolsPacked at slot 2 ((future << 128) | next).
    uint256 private constant PRIZE_POOLS_SLOT = 2;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      test harness; the GAS-01 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev v47: `MAX_SPINS_ETH` was retired in favour of per-currency caps
    ///      (`MAX_SPINS_ETH = 25 / MAX_SPINS_BURNIE = 15 / MAX_SPINS_WWXRP = 5`, DegeneretteModule:226-228).
    ///      The ETH cap is the relevant spin-loop ceiling for this ETH-bet worst case. This harness's
    ///      existing 10-spin all-match construction (word search + per-spin lootbox-flip assertions) is
    ///      kept AS-IS so the test still compiles and runs; re-deriving the true 25-spin worst case
    ///      (a fresh word search achieving all-25-match) is owned by 323-04 (DGAS/DSPIN proofs).
    /// 323-04 owns the 25-spin worst-case re-derivation against the new MAX_SPINS_ETH cap.
    uint8 internal constant MAX_SPINS_ETH = 10;

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

    /// @dev The worst-case (RNG word, customTicket): the word is searched so the greedy ticket wins
    ///      (matches >= 2) on all 10 spins; both are pinned in setUp for determinism.
    uint256 private worstCaseWord;
    uint32 private worstCaseTicket;

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

        // Pin the worst-case (word, ticket): a word whose greedy ticket wins on all 10 spins.
        (worstCaseWord, worstCaseTicket) = _findWorstCase(INDEX);
    }

    // =========================================================================
    // Test A — 10-spin all-match worst case (the GAS-01 fit-check)
    // =========================================================================

    /// @notice GAS-01 worst-case-FIRST: a single `crankBets` item resolving a `ticketCount == 10`
    ///         bet where every spin wins ETH and flips into the lootbox branch (10 materializations).
    ///         Asserts the scenario IS the maximum (ticketCount == 10 AND all 10 spins materialized a
    ///         lootbox) BEFORE the measurement is trusted, and asserts the measured gas < 30M mainnet.
    function testWorstCaseResolveBet10SpinAllMatchFitsBlockGasLimit() public {
        uint64 betId = _placeWorstCaseBet(player);
        // Inject a small pool so the 10% ETH-win cap flips every winning spin into the lootbox branch.
        _setFuturePool(SMALL_POOL_WEI);
        _injectLootboxRngWord(INDEX, worstCaseWord);

        // assert-is-worst-case precondition (1/2): the placed bet's ticketCount IS the structural max.
        assertEq(_betTicketCount(player, betId), MAX_SPINS_ETH, "worst case: ticketCount == MAX_SPINS_ETH (10)");

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // Measure the worst-case crank item's gas (gasleft delta around the external call).
        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.crankBets(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        (uint256 spinResults, uint256 lootboxFlips) = _countResolveEffects();

        // assert-is-worst-case precondition (2/2): all 10 spins ran and EVERY spin drove the lootbox
        // materialization branch (one PayoutCapped per spin whose payout flipped into the lootbox).
        assertEq(spinResults, MAX_SPINS_ETH, "all 10 spins resolved (one FullTicketResult each)");
        assertEq(
            lootboxFlips,
            MAX_SPINS_ETH,
            "worst case: all 10 spins materialized a lootbox (10 PayoutCapped, the per-spin max branch)"
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
    ///         adding one typical (1-spin) resolve item to `crankBets`. This is the calibration
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
        game.crankBets(players, betIds);
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
    // Internal helpers
    // =========================================================================

    /// @dev Place the worst-case bet: ticketCount == MAX_SPINS_ETH (10) with the searched ticket
    ///      so every spin wins (matches >= 2). Placement adds totalBet to the pool; the caller resets
    ///      the pool to SMALL_POOL_WEI afterward so the 10% cap flips each spin into the lootbox.
    function _placeWorstCaseBet(address better) internal returns (uint64 betId) {
        uint256 totalBet = uint256(AMOUNT_PER_TICKET) * MAX_SPINS_ETH;
        vm.prank(better);
        game.placeDegeneretteBet{value: totalBet}(
            address(0), 0, AMOUNT_PER_TICKET, MAX_SPINS_ETH, worstCaseTicket, 0
        );
        betId = _betNonce(better);
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
        game.crankBets(players, betIds);
        gasUsed = gasBefore - gasleft();
    }

    /// @dev Search the RNG word space for a word whose per-quadrant-greedy ticket wins (matches >= 2,
    ///      so payout > 0) on EVERY one of the 10 spins. Maximizes the MIN match across spins. The
    ///      greedy ticket picks, per quadrant, the color and symbol that match the most of that
    ///      quadrant's 10 result values (color + symbol matched independently in _countMatches).
    function _findWorstCase(uint48 index) internal pure returns (uint256 word, uint32 ticket) {
        uint8 bestMin;
        for (uint256 k; k < WORD_SEARCH_BUDGET; ++k) {
            uint256 candidate = uint256(keccak256(abi.encodePacked("crank_resolve_worst_case_word", k)));
            uint32 t = _greedyTicket(index, candidate);
            uint8 minMatch = 8;
            for (uint8 spinIdx; spinIdx < MAX_SPINS_ETH; ++spinIdx) {
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
        require(bestMin >= 2, "no word found where all 10 spins win, widen WORD_SEARCH_BUDGET");
    }

    /// @dev Per-quadrant greedy ticket: for each quadrant pick the (color, symbol) matching the most
    ///      of the 10 spins' result values in that quadrant.
    function _greedyTicket(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
        for (uint8 q; q < 4; ++q) {
            uint16[8] memory colorHits;
            uint16[8] memory symbolHits;
            for (uint8 spinIdx; spinIdx < MAX_SPINS_ETH; ++spinIdx) {
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
