// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title DegeneretteHeroScoreTest — Proves the v48 Degenerette hero 2-point
///        rescale (HERO-04 scoring SHAPE / packing / thresholds + HERO-06 DGAS
///        write-batch equivalence + dailyHeroWagers no-leak) against the applied
///        Phase-326 diff (FROZEN subject).
///
/// @notice These proofs assert SCORING SHAPE / DISPATCH / BEHAVIOR and the
///         AGGREGATION the write-batch touched. The byte-reproduced final per-N
///         payout VALUES are verified separately by the DegenerettePerNEvExactness
///         stat gate (PASS_ALL byte-reproduce + neutral-or-just-under baseline EV);
///         this suite anchors the dispatch shape (S=0..7 packed, S=8/S=9 separate
///         uint256s) and the scoring/aggregation behavior.
///
/// @dev Reaches the FROZEN `_score` (private) through the public resolve path and
///      reads the contract's score off the `FullTicketResult.matches` field (which
///      now carries S = A + 2*H ∈ {0..9}). The result ticket is derived on-chain
///      via DegenerusTraitUtils.packedTraitsDegenerette(rngWord, index, spinIdx);
///      a chosen player ticket is constructed to land an exact (A, H, S) against it.
contract DegeneretteHeroScoreTest is DeployProtocol {
    // --- Storage slots (mirror DegeneretteFreezeResolution.t.sol) ---
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;   // post Stage-B game-storage repack: was 36
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34; // post Stage-B game-storage repack: was 35
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 39; // post Stage-B game-storage repack: was 41
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_FLIP = 100 ether;
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

        // Use FLIP currency: no ETH/WWXRP bonus uplift (baseBonus stays 0 for
        // CURRENCY_FLIP), no ETH pool cap, no DGNRS award — so the spin payout is
        // cleanly betAmount * basePayout * roiBps / 1e6, and basePayout for S=9 is
        // the FINAL S9 constant for the ticket's N. This isolates the relabel value.
        uint128 perTicket = 1_000_000; // small FLIP-unit bet; >= MIN_BET handled via funding
        // FLIP min bet is 100 ether; use that scale to satisfy _validateMinBet.
        perTicket = 100 ether;

        for (uint8 N = 0; N < 5; ++N) {
            uint256 word = uint256(keccak256(abi.encodePacked("s9_jackpot", N)));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            // Exact self-match → all 8 axes match → S=9 (hero symbol among them).
            uint32 playerTicket = resultTicket;
            uint8 actualN = _countGoldQuadrants(resultTicket);
            uint8 heroQuadrant = 0;

            (uint8 s, uint256 payout, uint256 roiBps) =
                _resolveFlipAndReadScore(index, word, playerTicket, heroQuadrant, perTicket);
            assertEq(s, 9, "self-match must score the S=9 jackpot");

            // payout = perTicket * basePayout * roiBps / 1e6  →  basePayout =
            // payout * 1e6 / (perTicket * roiBps). Exact integer (no cap/bonus on FLIP).
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

        // S=8: separate slot holding the FINAL nonzero S8 constant → a true S=8
        // spin pays > 0 via the SEPARATE-slot dispatch (NOT the packed S0..7 path).
        // Proves the >32-bit S8 slot is decoded end-to-end.
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
            assertGt(
                payout,
                0,
                "S=8 routes to the SEPARATE, now-final nonzero S8 slot - dispatch shape is final"
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
    // Task 3 (a): HERO-06 DGAS write-batch byte-identical to per-bet resolve.
    // =========================================================================

    /// @notice Resolve a set of N bets in ONE resolveBets call, then resolve the
    ///         SAME N bets one-at-a-time (fresh state via snapshot, identical VRF
    ///         words + tickets), and assert the cumulative claimable, claimablePool,
    ///         FLIP/WWXRP mint deltas, and the per-bet FullTicketResult events are
    ///         byte-identical between the batched and per-bet paths. The cross-bet
    ///         `acc` flush must be same-results (the HERO-06 DGAS constraint — the
    ///         rescale changed payout SHAPE only, never the aggregation).
    function test_HERO06_WriteBatchByteIdentical_DGAS() public {
        // Large unfrozen pool so the ETH cap never binds (cap-path is DGAS-05's job;
        // HERO-06 asserts the rescaled payout SHAPE keeps the batch == per-bet).
        _seedFuturePrizePool(10_000_000 ether);

        uint48 index = 1;
        uint256 word = uint256(keccak256("hero06_dgas_word"));
        uint32 ticket = _resultTicketForSpin(index, word, 0); // 8/8 self-match on spin 0

        // Mixed-currency batch: ETH(4 spins) + FLIP(3) + WWXRP(2), same ticket.
        uint128 ethPerTicket = 0.01 ether;
        uint128 flipPerTicket = 200 ether;
        uint128 wwxrpPerTicket = 2 ether;
        _fundFlip(player, uint256(flipPerTicket) * 3 + 1 ether);
        _fundWwxrp(player, uint256(wwxrpPerTicket) * 2 + 1 ether);

        uint64 ethBet = _placeBet(CURRENCY_ETH, ethPerTicket, 4, ticket, 0);
        uint64 flipBet = _placeBet(CURRENCY_FLIP, flipPerTicket, 3, ticket, 1);
        uint64 wwxrpBet = _placeBet(CURRENCY_WWXRP, wwxrpPerTicket, 2, ticket, 2);
        _injectLootboxRngWord(index, word);

        uint256 snap = vm.snapshotState();

        // --- Run A: ONE resolveBets call (the cross-bet batch) ---
        uint256 preClaimableA = game.claimableWinningsOf(player);
        uint256 preClaimablePoolA = _readClaimablePool();
        uint256 preFlipA = coin.balanceOf(player);
        uint256 preWwxrpA = wwxrp.balanceOf(player);

        uint64[] memory all = new uint64[](3);
        all[0] = ethBet;
        all[1] = flipBet;
        all[2] = wwxrpBet;
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), all);
        bytes32 eventsDigestA = _fullTicketResultDigest();

        uint256 claimableDeltaA = game.claimableWinningsOf(player) - preClaimableA;
        uint256 claimablePoolDeltaA = _readClaimablePool() - preClaimablePoolA;
        uint256 flipDeltaA = coin.balanceOf(player) - preFlipA;
        uint256 wwxrpDeltaA = wwxrp.balanceOf(player) - preWwxrpA;

        // --- Run B: revert, resolve the SAME bets one-at-a-time ---
        vm.revertToState(snap);
        uint256 preClaimableB = game.claimableWinningsOf(player);
        uint256 preClaimablePoolB = _readClaimablePool();
        uint256 preFlipB = coin.balanceOf(player);
        uint256 preWwxrpB = wwxrp.balanceOf(player);

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(ethBet));
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(flipBet));
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(wwxrpBet));
        bytes32 eventsDigestB = _fullTicketResultDigest();

        uint256 claimableDeltaB = game.claimableWinningsOf(player) - preClaimableB;
        uint256 claimablePoolDeltaB = _readClaimablePool() - preClaimablePoolB;
        uint256 flipDeltaB = coin.balanceOf(player) - preFlipB;
        uint256 wwxrpDeltaB = wwxrp.balanceOf(player) - preWwxrpB;

        // Byte-identical assertions (HERO-06 DGAS same-results).
        assertEq(claimableDeltaA, claimableDeltaB, "DGAS: batched ETH claimable == per-bet");
        assertEq(claimablePoolDeltaA, claimablePoolDeltaB, "DGAS: batched claimablePool == per-bet");
        assertEq(flipDeltaA, flipDeltaB, "DGAS: batched FLIP mint == per-bet");
        assertEq(wwxrpDeltaA, wwxrpDeltaB, "DGAS: batched WWXRP mint == per-bet");
        assertEq(eventsDigestA, eventsDigestB, "DGAS: per-spin FullTicketResult stream byte-identical");

        // Non-vacuity: the rescaled payouts actually exercised each currency.
        assertGt(claimableDeltaA, 0, "non-vacuity: ETH payout exercised");
        assertGt(flipDeltaA, 0, "non-vacuity: FLIP payout exercised");
        assertGt(wwxrpDeltaA, 0, "non-vacuity: WWXRP payout exercised");
    }

    // =========================================================================
    // Task 3 (b): HERO-06 dailyHeroWagers / hero-jackpot no-leak.
    // =========================================================================

    /// @notice Prove the daily-hero-symbol jackpot reads ONLY the player's WAGERED
    ///         hero symbol, never the per-bet resolution score. Two runs with
    ///         IDENTICAL wagers but DIFFERENT resolution scores S must produce the
    ///         IDENTICAL dailyHeroWagers ledger (all 32 slots via getDailyHeroWager)
    ///         and the IDENTICAL hero winner (getDailyHeroWinner). The 0-8 -> 0-9
    ///         matches-range change cannot leak into the wager ledger / hero roll.
    function test_HERO06_DailyHeroJackpotUnaffected_NoLeak() public {
        _seedFuturePrizePool(10_000_000 ether);
        uint48 index = 1;
        uint32 day = GameTimeLib.currentDayIndex();

        // Two RNG words producing DIFFERENT resolution scores for the SAME tickets.
        // The wagers (chosen hero symbols) are identical across both runs.
        uint256 wordLow = uint256(keccak256("noleak_low_score"));
        uint256 wordHigh = uint256(keccak256("noleak_high_score"));

        // Build a small wager set: 3 ETH bets with chosen hero symbols/quadrants.
        // The chosen heroSymbol is decoded from customTicket >> (heroQuadrant*8) & 7.
        uint128 perTicket = 0.01 ether;

        uint256 snap = vm.snapshotState();

        // --- Run LOW: place wagers, resolve under wordLow ---
        _placeNoLeakWagers(perTicket);
        uint256[32] memory ledgerLow = _readHeroLedger(day);
        // Resolve every placed bet (nonce 1..3) under wordLow.
        _injectLootboxRngWord(index, wordLow);
        _resolveAllNoLeak();
        (uint8 wqLow, uint8 wsLow, uint256 waLow) = game.getDailyHeroWinner(uint24(day));
        uint256[32] memory ledgerLowPost = _readHeroLedger(day);

        // --- Run HIGH: revert, place the SAME wagers, resolve under wordHigh ---
        vm.revertToState(snap);
        _placeNoLeakWagers(perTicket);
        uint256[32] memory ledgerHigh = _readHeroLedger(day);
        _injectLootboxRngWord(index, wordHigh);
        _resolveAllNoLeak();
        (uint8 wqHigh, uint8 wsHigh, uint256 waHigh) = game.getDailyHeroWinner(uint24(day));
        uint256[32] memory ledgerHighPost = _readHeroLedger(day);

        // (1) The wager ledger is identical across the two runs (wagers identical).
        for (uint256 i; i < 32; ++i) {
            assertEq(ledgerLow[i], ledgerHigh[i], "no-leak: pre-resolve wager ledger identical across runs");
            // (2) Resolution does NOT mutate the wager ledger at all (it is wager-only,
            //     written at placement; resolution reads scores, never wagers).
            assertEq(ledgerLow[i], ledgerLowPost[i], "no-leak: resolution does not touch the wager ledger (low run)");
            assertEq(ledgerHigh[i], ledgerHighPost[i], "no-leak: resolution does not touch the wager ledger (high run)");
            // (3) Post-resolve ledgers identical across runs (different scores, same wagers).
            assertEq(ledgerLowPost[i], ledgerHighPost[i], "no-leak: post-resolve ledger identical despite different scores");
        }

        // (4) The hero winner (jackpot roll input) is identical across the two runs.
        assertEq(wqLow, wqHigh, "no-leak: hero winner quadrant identical (depends only on wagers)");
        assertEq(wsLow, wsHigh, "no-leak: hero winner symbol identical (depends only on wagers)");
        assertEq(waLow, waHigh, "no-leak: hero winner amount identical (depends only on wagers)");

        // Non-vacuity: the differential is meaningful only if the two runs DID score
        // differently. Assert the resolution scores diverged between the runs.
        uint8 sLow = _scoreOfTicketUnder(index, wordLow);
        uint8 sHigh = _scoreOfTicketUnder(index, wordHigh);
        assertTrue(sLow != sHigh, "non-vacuity: the two runs must produce different resolution scores");
        // And the wager ledger is non-empty (the hero winner is a real wager).
        assertGt(waLow, 0, "non-vacuity: the hero wager ledger is non-empty");
    }

    // =========================================================================
    // WWXRP RIG — controlled on-chain behavior of the rigged WWXRP reel path.
    // =========================================================================

    /// @notice Drives many single-spin WWXRP bets through the live resolve path and
    ///         checks the rigged score against the pre-rig (honest) reel for EVERY
    ///         sample: the rigged score lifts by exactly 0 or 1 (never +2 — the hero
    ///         symbol is never the lifted cell), is never below honest, and never
    ///         fires when the honest reel is full / 1-off (M >= 7). Over the batch the
    ///         lift rate among eligible (M <= 6) reels sits at ~60% (the 3/5 gate).
    ///         This validates the `_rigWwxrpResult` bit-manipulation end-to-end (the
    ///         analytical stat gate validates the calibration; this validates the code).
    function test_WWXRP_Rig_ControlledBehavior() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 400 ether);
        uint48 index = 1;
        uint8 heroQuadrant = 2;
        uint32 customTicket = _ticketWithHero(heroQuadrant, 4);

        uint256 eligible; // honest M <= 6 (rig may fire)
        uint256 lifted; // rigged score == honest + 1
        uint256 samples = 200;

        for (uint256 i; i < samples; ++i) {
            uint256 word = uint256(keccak256(abi.encodePacked("wwxrp_rig", i)));
            vm.prank(player);
            game.placeDegeneretteBet(address(0), CURRENCY_WWXRP, 1 ether, 1, customTicket, heroQuadrant);
            uint64 betId = _betNonce(player);
            _injectLootboxRngWord(index, word);
            vm.recordLogs();
            vm.prank(player);
            game.resolveDegeneretteBets(address(0), _one(betId));
            (uint8 s, ) = _firstSpinScoreAndPayout();
            _injectLootboxRngWord(index, 0);

            // Honest (pre-rig) reel + score/M for this spin.
            uint32 honestResult = _resultTicketForSpin(index, word, 0);
            (uint8 honestS, uint8 honestM) =
                _honestScoreAndM(customTicket, honestResult, heroQuadrant);

            // Per-sample correctness: the rigged score lifts by exactly 0 or 1 — never
            // +2 (the hero symbol is excluded), never below honest.
            assertTrue(
                s == honestS || s == honestS + 1,
                "rig lifts the score by exactly 0 or 1 (never +2, never negative)"
            );
            if (honestM >= 7) {
                assertEq(s, honestS, "rig must NOT fire on a full / 1-off reel (M >= 7)");
            } else {
                ++eligible;
                if (s == honestS + 1) ++lifted;
            }
        }

        // Non-vacuity + ~60% gate: among eligible reels the rig fires ~3/5 of the time.
        assertGt(eligible, 100, "non-vacuity: most reels are rig-eligible (M <= 6)");
        assertGt(lifted, 0, "non-vacuity: the rig actually lifts some reels");
        assertLt(lifted, eligible, "non-vacuity: the rig is NOT always-on (40% no-op)");
        assertGe(lifted * 100, eligible * 45, "lift rate >= 45% (3/5 gate, sample tolerance)");
        assertLe(lifted * 100, eligible * 75, "lift rate <= 75% (3/5 gate, sample tolerance)");
    }

    /// @dev Mirror `_score` AND count matched axes (M) for an honest (pre-rig) reel.
    function _honestScoreAndM(uint32 playerTicket, uint32 resultTicket, uint8 heroQuadrant)
        internal
        pure
        returns (uint8 s, uint8 m)
    {
        for (uint8 q; q < 4; ++q) {
            uint8 pq = uint8(playerTicket >> (q * 8));
            uint8 rq = uint8(resultTicket >> (q * 8));
            if (((pq >> 3) & 7) == ((rq >> 3) & 7)) {
                ++s;
                ++m;
            } // color axis
            if ((pq & 7) == (rq & 7)) {
                s += (q == heroQuadrant) ? 2 : 1;
                ++m;
            } // symbol axis
        }
        if (s > 9) s = 9;
    }

    // ---- Task 3 helpers ------------------------------------------------------

    /// @dev Place a fixed set of ETH wagers with chosen hero symbols/quadrants.
    ///      heroSymbol = customTicket >> (heroQuadrant*8) & 7. We choose distinct
    ///      (quadrant, symbol) wagers so the ledger has a clear leader.
    function _placeNoLeakWagers(uint128 perTicket) internal {
        // Wager 1: heroQuadrant 0, symbol 5, multiple spins -> larger wager.
        _placeEthBet(perTicket, 5, _ticketWithHero(0, 5), 0);
        // Wager 2: heroQuadrant 1, symbol 2.
        _placeEthBet(perTicket, 2, _ticketWithHero(1, 2), 1);
        // Wager 3: heroQuadrant 0, symbol 5 again (reinforces the leader).
        _placeEthBet(perTicket, 3, _ticketWithHero(0, 5), 0);
    }

    /// @dev Resolve nonces 1..3 individually (the 3 wagers placed above).
    function _resolveAllNoLeak() internal {
        for (uint64 n = 1; n <= 3; ++n) {
            vm.prank(player);
            game.resolveDegeneretteBets(address(0), _one(n));
        }
    }

    /// @dev Read all 32 dailyHeroWagers slots for `day` via the public getter.
    function _readHeroLedger(uint32 day) internal view returns (uint256[32] memory ledger) {
        for (uint8 q; q < 4; ++q) {
            for (uint8 s; s < 8; ++s) {
                ledger[(q << 3) | s] = game.getDailyHeroWager(uint24(day), q, s);
            }
        }
    }

    /// @dev Build a ticket with a given hero symbol at the hero quadrant. The hero
    ///      symbol is the only field the wager-ledger write reads; other traits are
    ///      set to 0 (irrelevant to the wager path).
    function _ticketWithHero(uint8 heroQuadrant, uint8 heroSymbol) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint8 sym = q == heroQuadrant ? (heroSymbol & 7) : 0;
            uint8 byteVal = (q << 6) | (0 << 3) | sym;
            t |= uint32(byteVal) << (q * 8);
        }
    }

    /// @dev Compute the resolution score the spin-0 ticket would get under `word`
    ///      (the wager-1 ticket: hero quadrant 0, symbol 5). Used for non-vacuity:
    ///      the two runs must produce different scores for the differential to bite.
    function _scoreOfTicketUnder(uint48 index, uint256 word) internal pure returns (uint8 s) {
        uint32 playerTicket = _ticketWithHero(0, 5);
        uint32 resultTicket = _resultTicketForSpin(index, word, 0);
        uint8 heroQuadrant = 0;
        // Mirror _score: S = A + 2*H.
        for (uint8 q; q < 4; ++q) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) ++s; // color
            if ((pQuad & 7) == (rQuad & 7)) {
                s += (q == heroQuadrant) ? 2 : 1;
            }
        }
        if (s > 9) s = 9;
    }

    /// @dev keccak digest of the ordered (spinIdx, playerTicket, matches, payout)
    ///      FullTicketResult stream — a byte-identity fingerprint for the per-spin
    ///      result events (DGAS same-results).
    function _fullTicketResultDigest() internal returns (bytes32 digest) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) {
                digest = keccak256(abi.encodePacked(digest, logs[i].data));
            }
        }
    }

    /// @dev Mint WWXRP to `who` via the GAME-gated mintPrize.
    function _fundWwxrp(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
    }

    /// @dev Place a Degenerette bet of the given currency, return its betId.
    function _placeBet(
        uint8 currency,
        uint128 perTicket,
        uint8 spins,
        uint32 ticket,
        uint8 heroQuadrant
    ) internal returns (uint64 betId) {
        uint256 ethValue = currency == CURRENCY_ETH ? uint256(perTicket) * spins : 0;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(
            address(0), currency, perTicket, spins, ticket, heroQuadrant
        );
        betId = _betNonce(player);
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

    /// @dev Resolve a FLIP single-spin bet and return (score, payout, roiBps).
    ///      FLIP has no ETH/WWXRP bonus uplift, no pool cap, no DGNRS award, so
    ///      payout = perTicket * basePayout * roiBps / 1e6 exactly — isolating the
    ///      basePayout (used to anchor the S=9 jackpot relabel constant). roiBps is
    ///      decoded from the bet's stored activityScore via the ROI curve mirror.
    function _resolveFlipAndReadScore(
        uint48 index,
        uint256 word,
        uint32 customTicket,
        uint8 heroQuadrant,
        uint128 perTicket
    ) internal returns (uint8 s, uint256 payout, uint256 roiBps) {
        _fundFlip(player, uint256(perTicket) + 1 ether);
        vm.prank(player);
        game.placeDegeneretteBet(
            address(0),
            CURRENCY_FLIP,
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

        poolBefore = sdgnrs.poolBalance(sDGNRS.Pool.Reward);

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, ) = _firstSpinScoreAndPayout();
        uint256 poolAfter = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        award = poolBefore - poolAfter;

        _injectLootboxRngWord(index, 0);
    }

    /// @dev Single-element uint64 array (resolveDegeneretteBets takes uint64[]).
    function _one(uint64 betId) internal pure returns (uint64[] memory a) {
        a = new uint64[](1);
        a[0] = betId;
    }

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame.
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    // --- ROI curve mirror (DegeneretteModule._roiBpsFromScore) ------------------

    uint256 private constant ACTIVITY_SCORE_MAX_POINTS = 305; // curve knee K
    uint256 private constant ACTIVITY_SEG_B_KNEE_POINTS = 500;
    uint256 private constant ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000;
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_VA_BPS = 9_891;
    uint256 private constant ROI_VB_BPS = 9_970;
    uint256 private constant ROI_MAX_BPS = 9_990;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;
    uint256 private constant DEGENERETTE_BETS_SLOT = 38; // post Stage-B game-storage repack: was 40

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
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return ROI_MAX_BPS;
        if (score <= ACTIVITY_SCORE_MAX_POINTS) {
            return ROI_MIN_BPS + (score * (ROI_VA_BPS - ROI_MIN_BPS)) / ACTIVITY_SCORE_MAX_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                ROI_VA_BPS +
                ((score - ACTIVITY_SCORE_MAX_POINTS) * (ROI_VB_BPS - ROI_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - ACTIVITY_SCORE_MAX_POINTS);
        }
        return
            ROI_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (ROI_MAX_BPS - ROI_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
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
