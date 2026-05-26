// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";

/// @title DegeneretteHeroScoreTest — Proves the v48 Degenerette hero 2-point
///        rescale (HERO-04 scoring SHAPE / packing / thresholds + HERO-06 DGAS
///        write-batch equivalence + dailyHeroWagers no-leak) against the applied
///        Phase-326 diff (FROZEN subject).
///
/// @notice These proofs assert SCORING SHAPE / DISPATCH / BEHAVIOR and the
///         AGGREGATION the write-batch touched — they do NOT depend on the final
///         per-N payout table VALUES, so they pass GREEN even while the Phase-326
///         intentional placeholders (QUICK_PLAY_PAYOUTS packed = old M-indexed,
///         _S8 = 0, WWXRP = old) are still in the contract. The byte-reproduce of
///         the final VALUES is the separate stat-gate (DegenerettePerNEvExactness),
///         whose RED-with-diff is the expected no-contract-phase outcome.
///
/// @dev Reaches the FROZEN `_score` (private) through the public resolve path and
///      reads the contract's score off the `FullTicketResult.matches` field (which
///      now carries S = A + 2*H ∈ {0..9}). The result ticket is derived on-chain
///      via DegenerusTraitUtils.packedTraitsDegenerette(rngWord, index, spinIdx);
///      a chosen player ticket is constructed to land an exact (A, H, S) against it.
contract DegeneretteHeroScoreTest is DeployProtocol {
    // --- Storage slots (mirror DegeneretteFreezeResolution.t.sol) ---
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_BURNIE = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_BURNIE = 100 ether;
    uint256 private constant MIN_BET_WWXRP = 1 ether;

    /// @dev DGNRS award bps tiers (DegeneretteModule:205-207): S=7/8/9.
    uint256 private constant DEGEN_DGNRS_7_BPS = 400;
    uint256 private constant DEGEN_DGNRS_8_BPS = 800;
    uint256 private constant DEGEN_DGNRS_9_BPS = 1500;

    /// @dev FullTicketResult topic0 (matches carries S now).
    bytes32 private constant FULL_TICKET_RESULT_SIG =
        0xed1cde932a37b486ad1cc829c4ce89bf3bff943b68625e57cad59bc1bc18d8de;
    bytes32 private constant PAYOUT_CAPPED_SIG =
        0xf8a9468f6767206f82ef0f809e2c4fb396a1495ad99e9f116652fe99a91f20c5;
    bytes32 private constant FULL_TICKET_RESOLVED_SIG =
        0xb740e09ba01c583a945713a2656978f631723409d1db2dce5df96a8b3ce27e15;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("hero_score_player");
        vm.deal(player, 10_000 ether);
        vm.deal(address(game), 5_000 ether);

        // Seed lootboxRngIndex to 1 (placement requires index >= 1 and word == 0).
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
    }

    // =========================================================================
    // Task 2 (a): S = A + 2*H scoring formula; hero-alone => S=2 win;
    //             hero quadrant's COLOR is an ordinary axis (contributes 1).
    // =========================================================================

    /// @notice Drive single-spin resolves with engineered (A, H) and assert the
    ///         contract's score (read from FullTicketResult.matches) equals
    ///         S = A + 2*H, capped at 9, with hero-alone (A=0,H=1) => S=2 (a win).
    function test_HERO_ScoreFormula() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint48 index = 1;
        uint256 word = uint256(keccak256("hero_score_formula_word"));
        uint8 heroQuadrant = 1;
        uint32 resultTicket = _resultTicketForSpin(index, word, 0);

        // (i) hero-symbol-alone: match ONLY the hero quadrant's symbol => A=0, H=1 => S=2.
        {
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 0, /*H*/ 1);
            uint8 s = _resolveOneAndReadScore(index, word, t, heroQuadrant);
            assertEq(s, 2, "hero-alone (A=0,H=1) must score S=2 (guaranteed win)");
        }
        // (ii) A=3, H=1 => S=5.
        {
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, 3, 1);
            uint8 s = _resolveOneAndReadScore(index, word, t, heroQuadrant);
            assertEq(s, 5, "A=3 + hero => S=5");
        }
        // (iii) A=5, H=0 => S=5 (no hero symbol match).
        {
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, 5, 0);
            uint8 s = _resolveOneAndReadScore(index, word, t, heroQuadrant);
            assertEq(s, 5, "A=5 + no hero => S=5");
        }
        // (iv) hero quadrant COLOR-only match (not symbol): contributes 1 (ordinary),
        //      not 2. Construct A=1 via the hero quadrant's color, H=0 => S=1 (no win).
        {
            uint32 t = _ticketMatchingHeroColorOnly(resultTicket, heroQuadrant);
            uint8 s = _resolveOneAndReadScore(index, word, t, heroQuadrant);
            assertEq(s, 1, "hero quadrant COLOR-only match contributes 1 (ordinary axis), not 2");
        }
    }

    // =========================================================================
    // Task 2 (b): S=9 == old M=8 jackpot relabel (pays the FINAL S9 constant).
    // =========================================================================

    /// @notice The all-axes-match event (7 ordinary + hero symbol) scores S=9 and
    ///         pays the FINAL QUICK_PLAY_PAYOUT_N{N}_S9 constant (the M=8 relabel —
    ///         already correct, not a placeholder). Asserted per N via a self-match
    ///         ticket (resultTicket itself) → S=9.
    function test_HERO_S9EqualsOldM8Jackpot() public {
        uint48 index = 1;

        // FINAL S9 constants (DegeneretteModule:269-273) — relabel of old M=8.
        uint256[5] memory S9 = [
            uint256(10_756_411),
            12_583_037,
            14_792_939,
            17_512_324,
            20_916_435
        ];

        // Use BURNIE currency: no ETH/WWXRP bonus uplift (baseBonus stays 0 for
        // CURRENCY_BURNIE), no ETH pool cap, no DGNRS award — so the spin payout is
        // cleanly betAmount * basePayout * roiBps / 1e6, and basePayout for S=9 is
        // the FINAL S9 constant for the ticket's N. This isolates the relabel value.
        uint128 perTicket = 1_000_000; // small BURNIE-unit bet; >= MIN_BET handled via funding
        // BURNIE min bet is 100 ether; use that scale to satisfy _validateMinBet.
        perTicket = 100 ether;

        for (uint8 N = 0; N < 5; ++N) {
            uint256 word = uint256(keccak256(abi.encodePacked("s9_jackpot", N)));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            // Exact self-match → all 8 axes match → S=9 (hero symbol among them).
            uint32 playerTicket = resultTicket;
            uint8 actualN = _countGoldQuadrants(resultTicket);
            uint8 heroQuadrant = 0;

            (uint8 s, uint256 payout, uint256 roiBps) =
                _resolveBurnieAndReadScore(index, word, playerTicket, heroQuadrant, perTicket);
            assertEq(s, 9, "self-match must score the S=9 jackpot");

            // payout = perTicket * basePayout * roiBps / 1e6  →  basePayout =
            // payout * 1e6 / (perTicket * roiBps). Exact integer (no cap/bonus on BURNIE).
            uint256 basePayout = (payout * 1_000_000) / (uint256(perTicket) * roiBps);
            assertEq(
                basePayout,
                S9[actualN],
                "S=9 pays the FINAL S9 jackpot constant (M=8 relabel) for the ticket's N"
            );
        }
    }

    // =========================================================================
    // Task 2 (c): S8/S9 separate-uint256 + S0..7 packed dispatch decodable.
    // =========================================================================

    /// @notice Prove the dispatch SHAPE end-to-end: S=9 reads the separate S9
    ///         constant (nonzero, the relabel), S=8 reads the separate S8 constant
    ///         (a placeholder 0 in this phase — proving the SEPARATE-slot dispatch,
    ///         not the value), and S=0..7 decode from the packed slot. The dispatch
    ///         is FINAL even while the packed/_S8 values are placeholders.
    function test_HERO_S8S9PackingDecodable() public {
        _seedFuturePrizePool(100_000_000 ether);
        uint48 index = 1;

        // S=9: separate slot, FINAL nonzero relabel → payout > 0.
        {
            uint256 word = uint256(keccak256("packing_s9"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            (uint8 s, uint256 payout) = _resolveOneAndReadScoreAndPayout(
                index,
                word,
                resultTicket,
                0
            );
            assertEq(s, 9, "self-match -> S=9");
            assertGt(payout, 0, "S=9 dispatches to the separate, nonzero S9 constant");
        }

        // S=8: separate slot. In this phase the S8 constant is the placeholder 0,
        // so a true S=8 spin pays 0 — proving the dispatch routes S=8 to the
        // SEPARATE slot (NOT the packed S0..7 path, which would be nonzero). This
        // is the placeholder showing through the FINAL dispatch shape.
        {
            uint8 heroQuadrant = 2;
            uint256 word = uint256(keccak256("packing_s8"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            // S=8 = A=6 + hero-symbol(2): 6 ordinary matches + hero symbol.
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 6, /*H*/ 1);
            (uint8 s, uint256 payout) = _resolveOneAndReadScoreAndPayout(
                index,
                word,
                t,
                heroQuadrant
            );
            assertEq(s, 8, "engineered A=6 + hero => S=8");
            assertEq(
                payout,
                0,
                "S=8 routes to the SEPARATE S8 slot (placeholder 0 in this phase) - dispatch shape is final"
            );
        }

        // S=0..7: packed slot decode. S=3 (A=3,H=0) reads the packed slot — nonzero
        // (the packed placeholder holds old M-indexed values, all > 0 for S>=2).
        {
            uint8 heroQuadrant = 3;
            uint256 word = uint256(keccak256("packing_s3"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 3, /*H*/ 0);
            (uint8 s, uint256 payout) = _resolveOneAndReadScoreAndPayout(
                index,
                word,
                t,
                heroQuadrant
            );
            assertEq(s, 3, "A=3 + no hero => S=3");
            assertGt(payout, 0, "S=3 decodes from the packed S0..7 slot (nonzero)");
        }
    }

    // =========================================================================
    // Task 2 (d): DGNRS award gate fires only S>=7 with the re-mapped BPS tiers.
    // =========================================================================

    /// @notice Drive ETH spins at S=6 / 7 / 8 / 9 and assert the sDGNRS award fires
    ///         only for S>=7, with BPS S=7→4% / S=8→8% / S=9→15% (re-mapped, D-03).
    function test_HERO_DgnrsThresholdsRemapped() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint48 index = 1;
        uint8 heroQuadrant = 0;
        uint128 perTicket = 1 ether; // DGNRS cappedBet caps at 1 ether

        // S=6 (A=4 + hero(2)): below the S>=7 gate → NO award.
        {
            uint256 word = uint256(keccak256("dgnrs_s6"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 4, /*H*/ 1);
            (uint8 s, uint256 gain, ) = _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 6, "engineered A=4 + hero => S=6");
            assertEq(gain, 0, "S=6 is below the S>=7 DGNRS gate - no award");
        }
        // S=7 (A=5 + hero(2)): award at 4% (DEGEN_DGNRS_7_BPS).
        {
            uint256 word = uint256(keccak256("dgnrs_s7"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 5, /*H*/ 1);
            (uint8 s, uint256 gain, uint256 poolBefore) =
                _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 7, "engineered A=5 + hero => S=7");
            assertGt(gain, 0, "S=7 fires the DGNRS award");
            assertEq(gain, (poolBefore * DEGEN_DGNRS_7_BPS) / 10_000, "S=7 award == 4% of Reward pool");
        }
        // S=8 (A=6 + hero(2)): award at 8% (DEGEN_DGNRS_8_BPS).
        {
            uint256 word = uint256(keccak256("dgnrs_s8"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketMatching(resultTicket, heroQuadrant, /*A*/ 6, /*H*/ 1);
            (uint8 s, uint256 gain, uint256 poolBefore) =
                _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 8, "engineered A=6 + hero => S=8");
            assertEq(gain, (poolBefore * DEGEN_DGNRS_8_BPS) / 10_000, "S=8 award == 8% of Reward pool");
        }
        // S=9 (self-match): award at 15% (DEGEN_DGNRS_9_BPS).
        {
            uint256 word = uint256(keccak256("dgnrs_s9"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            (uint8 s, uint256 gain, uint256 poolBefore) =
                _resolveEthAndDgnrs(index, word, resultTicket, heroQuadrant, perTicket);
            assertEq(s, 9, "self-match => S=9");
            assertEq(gain, (poolBefore * DEGEN_DGNRS_9_BPS) / 10_000, "S=9 award == 15% of Reward pool");
        }
    }

    // =========================================================================
    // Task 2 internal helpers
    // =========================================================================

    /// @dev Resolve a single-spin ETH bet and return the contract's score S (read
    ///      off FullTicketResult.matches). Uses a large pool so no cap binds.
    function _resolveOneAndReadScore(
        uint48 index,
        uint256 word,
        uint32 customTicket,
        uint8 heroQuadrant
    ) internal returns (uint8 s) {
        (s, ) = _resolveOneAndReadScoreAndPayout(index, word, customTicket, heroQuadrant);
    }

    function _resolveOneAndReadScoreAndPayout(
        uint48 index,
        uint256 word,
        uint32 customTicket,
        uint8 heroQuadrant
    ) internal returns (uint8 s, uint256 payout) {
        uint128 perTicket = 0.01 ether;
        uint64 betId = _placeEthBet(perTicket, 1, customTicket, heroQuadrant);
        _injectLootboxRngWord(index, word);

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, payout) = _firstSpinScoreAndPayout();

        // Reset for the next sub-case: clear the injected word so a fresh bet
        // placement passes the `word == 0` precondition.
        _injectLootboxRngWord(index, 0);
    }

    /// @dev Resolve a BURNIE single-spin bet and return (score, payout, roiBps).
    ///      BURNIE has no ETH/WWXRP bonus uplift, no pool cap, no DGNRS award, so
    ///      payout = perTicket * basePayout * roiBps / 1e6 exactly — isolating the
    ///      basePayout (used to anchor the S=9 jackpot relabel constant). roiBps is
    ///      decoded from the bet's stored activityScore via the ROI curve mirror.
    function _resolveBurnieAndReadScore(
        uint48 index,
        uint256 word,
        uint32 customTicket,
        uint8 heroQuadrant,
        uint128 perTicket
    ) internal returns (uint8 s, uint256 payout, uint256 roiBps) {
        _fundBurnie(player, uint256(perTicket) + 1 ether);
        vm.prank(player);
        game.placeDegeneretteBet(
            address(0),
            CURRENCY_BURNIE,
            perTicket,
            1,
            customTicket,
            heroQuadrant
        );
        uint64 betId = _betNonce(player);
        roiBps = _roiBpsOfBet(player, betId);
        _injectLootboxRngWord(index, word);

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, payout) = _firstSpinScoreAndPayout();
        _injectLootboxRngWord(index, 0);
    }

    /// @dev Resolve an ETH bet and measure the DGNRS award via the Reward-pool
    ///      (Pool.Reward) DELTA, NOT the player's total sDGNRS balance. The
    ///      _awardDegeneretteDgnrs transfer comes from Pool.Reward; the lootbox path
    ///      may ALSO award DGNRS from a different pool (Pool.Dgnrs) on the capped
    ///      jackpot share, so the Reward-pool delta isolates the gate-S>=7 award.
    function _resolveEthAndDgnrs(
        uint48 index,
        uint256 word,
        uint32 customTicket,
        uint8 heroQuadrant,
        uint128 perTicket
    ) internal returns (uint8 s, uint256 award, uint256 poolBefore) {
        uint64 betId = _placeEthBet(perTicket, 1, customTicket, heroQuadrant);
        _injectLootboxRngWord(index, word);

        poolBefore = sdgnrs.poolBalance(StakedDegenerusStonk.Pool.Reward);

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, ) = _firstSpinScoreAndPayout();
        uint256 poolAfter = sdgnrs.poolBalance(StakedDegenerusStonk.Pool.Reward);
        award = poolBefore - poolAfter;

        _injectLootboxRngWord(index, 0);
    }

    /// @dev Single-element uint64 array (resolveDegeneretteBets takes uint64[]).
    function _one(uint64 betId) internal pure returns (uint64[] memory a) {
        a = new uint64[](1);
        a[0] = betId;
    }

    /// @dev Mint BURNIE to `who` via the GAME-gated mintForGame.
    function _fundBurnie(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    // --- ROI curve mirror (DegeneretteModule._roiBpsFromScore L1071-1100) -------

    uint256 private constant ACTIVITY_SCORE_MID_BPS = 7_500;
    uint256 private constant ACTIVITY_SCORE_HIGH_BPS = 25_500;
    uint256 private constant ACTIVITY_SCORE_MAX_BPS = 30_500;
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_MID_BPS = 9_500;
    uint256 private constant ROI_HIGH_BPS = 9_950;
    uint256 private constant ROI_MAX_BPS = 9_990;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;

    /// @dev Read the activityScore the contract stored in the packed bet (bits
    ///      [220..235]) and mirror _roiBpsFromScore to recover the exact roiBps used.
    function _roiBpsOfBet(address who, uint64 betId) internal view returns (uint256 roiBps) {
        bytes32 inner = keccak256(abi.encode(who, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 slot = keccak256(abi.encode(uint256(betId), inner));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 score = (packed >> FT_ACTIVITY_SHIFT) & 0xFFFF;
        roiBps = _roiBpsFromScore(score);
    }

    function _roiBpsFromScore(uint256 score) internal pure returns (uint256 roiBps) {
        if (score > ACTIVITY_SCORE_MAX_BPS) score = ACTIVITY_SCORE_MAX_BPS;
        if (score <= ACTIVITY_SCORE_MID_BPS) {
            uint256 xDen = ACTIVITY_SCORE_MID_BPS;
            uint256 term1 = (1000 * score) / xDen;
            uint256 term2 = (500 * score * score) / (xDen * xDen);
            roiBps = ROI_MIN_BPS + term1 - term2;
        } else if (score <= ACTIVITY_SCORE_HIGH_BPS) {
            uint256 delta = score - ACTIVITY_SCORE_MID_BPS;
            uint256 span = ACTIVITY_SCORE_HIGH_BPS - ACTIVITY_SCORE_MID_BPS;
            uint256 roiDelta = ROI_HIGH_BPS - ROI_MID_BPS;
            roiBps = ROI_MID_BPS + (delta * roiDelta) / span;
        } else {
            uint256 delta = score - ACTIVITY_SCORE_HIGH_BPS;
            uint256 span = ACTIVITY_SCORE_MAX_BPS - ACTIVITY_SCORE_HIGH_BPS;
            uint256 roiDelta = ROI_MAX_BPS - ROI_HIGH_BPS;
            roiBps = ROI_HIGH_BPS + (delta * roiDelta) / span;
        }
    }

    /// @dev Place a single-bet ETH degenerette bet, return its betId (nonce).
    function _placeEthBet(
        uint128 perTicket,
        uint8 spins,
        uint32 customTicket,
        uint8 heroQuadrant
    ) internal returns (uint64 betId) {
        uint256 ethValue = uint256(perTicket) * spins;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(
            address(0),
            CURRENCY_ETH,
            perTicket,
            spins,
            customTicket,
            heroQuadrant
        );
        betId = _betNonce(player);
    }

    /// @dev Helper to call resolveDegeneretteBets with a single betId.
    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev Read the first spin's (score, payout) from the recorded FullTicketResult.
    function _firstSpinScoreAndPayout() internal returns (uint8 s, uint256 payout) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) {
                (uint8 spinIdx, , uint8 matches, uint256 p) =
                    abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                if (spinIdx == 0) return (matches, p);
            }
        }
        revert("no FullTicketResult for spin 0");
    }

    // ---- ticket construction -------------------------------------------------

    /// @dev Build a player ticket that matches `resultTicket` on exactly `A` ordinary
    ///      axes and (if H==1) the hero quadrant's SYMBOL, choosing axes so the hero
    ///      quadrant's color is NOT among the A matches unless needed. Ordinary axes
    ///      pool: 4 colors + 3 non-hero symbols = 7. Starts fully mismatched, then
    ///      copies matching axes from the result.
    function _ticketMatching(
        uint32 resultTicket,
        uint8 heroQuadrant,
        uint8 A,
        uint8 H
    ) internal pure returns (uint32 t) {
        require(A <= 7, "A<=7");
        // Start from a guaranteed-mismatch base: flip every trait nibble vs result.
        uint8[4] memory colors;
        uint8[4] memory symbols;
        for (uint8 q; q < 4; ++q) {
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            // Mismatch defaults (avoid gold color 7 unless we copy it).
            colors[q] = rColor == 0 ? 1 : 0;
            symbols[q] = rSymbol == 0 ? 1 : 0;
        }

        // Hero symbol (the 2-point axis).
        if (H == 1) {
            uint8 rHeroSym = uint8(resultTicket >> (heroQuadrant * 8)) & 7;
            symbols[heroQuadrant] = rHeroSym;
        }

        // Ordinary axes to match (A of them): 4 colors + 3 non-hero symbols.
        // Order: colors q=0..3, then non-hero symbols. Skip the hero symbol axis.
        uint8 placed;
        // colors first
        for (uint8 q; q < 4 && placed < A; ++q) {
            colors[q] = (uint8(resultTicket >> (q * 8)) >> 3) & 7;
            ++placed;
        }
        // then non-hero symbols
        for (uint8 q; q < 4 && placed < A; ++q) {
            if (q == heroQuadrant) continue;
            symbols[q] = uint8(resultTicket >> (q * 8)) & 7;
            ++placed;
        }
        require(placed == A, "could not place A ordinary matches");

        t = _assemble(colors, symbols);
    }

    /// @dev Build a player ticket that matches ONLY the hero quadrant's COLOR (an
    ///      ordinary axis) and nothing else → A=1, H=0 → S=1.
    function _ticketMatchingHeroColorOnly(
        uint32 resultTicket,
        uint8 heroQuadrant
    ) internal pure returns (uint32 t) {
        uint8[4] memory colors;
        uint8[4] memory symbols;
        for (uint8 q; q < 4; ++q) {
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            colors[q] = rColor == 0 ? 1 : 0;
            symbols[q] = rSymbol == 0 ? 1 : 0;
        }
        // Match only the hero quadrant's color.
        colors[heroQuadrant] = (uint8(resultTicket >> (heroQuadrant * 8)) >> 3) & 7;
        t = _assemble(colors, symbols);
    }

    /// @dev Assemble a packed ticket from per-quadrant color/symbol nibbles, keeping
    ///      the quadrant index bits [7..6] = q (mirrors makePlayerTicketWithN).
    function _assemble(
        uint8[4] memory colors,
        uint8[4] memory symbols
    ) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint8 byteVal = (q << 6) | ((colors[q] & 7) << 3) | (symbols[q] & 7);
            t |= uint32(byteVal) << (q * 8);
        }
    }

    /// @dev Force a ticket to have exactly N gold quadrants (color=7) — used only
    ///      where N is otherwise read back from the result (kept for API symmetry).
    function _withN(uint32 ticket, uint8 N) internal pure returns (uint32 t) {
        t = ticket;
        for (uint8 q; q < 4; ++q) {
            uint8 byteVal = uint8(t >> (q * 8));
            uint8 color = q < N ? 7 : 0;
            byteVal = (byteVal & 0xC7) | (color << 3);
            t = (t & ~(uint32(0xFF) << (q * 8))) | (uint32(byteVal) << (q * 8));
        }
    }

    function _countGoldQuadrants(uint32 ticket) internal pure returns (uint8 count) {
        for (uint8 q; q < 4; ++q) {
            uint8 color = uint8((ticket >> (q * 8 + 3)) & 7);
            if (color == 7) ++count;
        }
    }

    // =========================================================================
    // Shared harness helpers (mirror DegeneretteFreezeResolution.t.sol)
    // =========================================================================

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

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _readClaimablePool() internal view returns (uint256) {
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return uint256(uint128(s1 >> 128));
    }
}
