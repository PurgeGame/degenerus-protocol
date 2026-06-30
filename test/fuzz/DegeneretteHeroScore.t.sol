// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title DegeneretteHeroScoreTest — Proves the v73 Degenerette Variant-2
///        (color-gated-by-symbol) rescore: the `_score` rule, the S=0..7 packed /
///        S=8 / S=9 dispatch, the DGNRS S>=7 thresholds, the DEC-01 R2 WWXRP rig
///        (+2 unlock, never a 9), plus HERO-06 DGAS write-batch equivalence +
///        dailyHeroWagers no-leak — against the FROZEN v73 subject.
///
/// @notice These proofs assert SCORING SHAPE / DISPATCH / BEHAVIOR and the
///         AGGREGATION the write-batch touched. The byte-reproduced final per-N
///         payout VALUES + the rigged-table EV calibration are verified separately by
///         the DegenerettePerNEvExactness / DegeneretteBonusEv stat gates; this suite
///         anchors the Variant-2 dispatch shape and the on-chain rig behaviour.
///
/// @dev Reaches the FROZEN Variant-2 `_score` / `_rigWwxrpResult` (private) through
///      the public resolve path and reads the contract's score off the
///      `FullTicketResult.matches` field (S ∈ {0..9}). The result ticket is derived
///      on-chain via DegenerusTraitUtils.packedTraitsDegenerette(resultSeed); a chosen
///      player ticket is constructed via `_ticketV2` (per-quadrant symbol/color match
///      masks) to land an exact Variant-2 S against it.
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

    /// @notice Drive single-spin resolves with engineered per-quadrant (symbol,
    ///         color) match states and assert the contract's Variant-2 score (read
    ///         from FullTicketResult.matches): per quadrant a symbol match scores +1
    ///         (hero +2) and that quadrant's color scores +1 ONLY IF its symbol also
    ///         matched (color gated behind symbol). Floor S>=2: a lone ordinary symbol
    ///         (S=1) and a lone color (S=0) both pay 0.
    function test_HERO_ScoreFormula() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint48 index = 1;
        uint256 word = uint256(keccak256("hero_score_formula_word"));
        uint8 heroQuadrant = 1;
        uint8 heroBit = uint8(1) << heroQuadrant; // 0x02
        uint8 q0 = 0x01; // ordinary quadrant 0
        uint32 resultTicket = _resultTicketForSpin(index, word, 0);

        // (A) hero symbol alone (no colors) => S=2 (the floor win: hero symbol +2).
        {
            uint32 t = _ticketV2(resultTicket, /*sym*/ heroBit, /*col*/ 0);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 2,
                "hero symbol alone => S=2 (floor win)");
        }
        // (B) hero quadrant full double (symbol + its color) => S=3.
        {
            uint32 t = _ticketV2(resultTicket, heroBit, heroBit);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 3,
                "hero symbol + hero color (gated, unlocks) => S=3");
        }
        // (C) one ordinary full double (q0 symbol + q0 color), hero misses => S=2.
        {
            uint32 t = _ticketV2(resultTicket, q0, q0);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 2,
                "one ordinary full double => S=2 (floor win)");
        }
        // (D) VARIANT-2 KEY: hero quadrant COLOR-only (symbol misses) contributes 0
        //     (color is gated behind the symbol — it never scores on its own). => S=0.
        {
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0, /*col*/ heroBit);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 0,
                "Variant-2: a lone color (symbol unmatched) scores 0 - gated behind symbol");
        }
        // (E) one ordinary symbol alone (no color) => S=1 (below the S>=2 floor).
        {
            uint32 t = _ticketV2(resultTicket, q0, 0);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 1,
                "a lone ordinary symbol => S=1 (no win, below floor)");
        }
        // (F) all four symbols match, no colors => hero(2) + 3 ordinary(1) = S=5.
        {
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 5,
                "all symbols, no colors => S=5 (hero 2 + 3 ordinary)");
        }
        // (G) everything matches (self-match shape) => S=9 (all 8 axes).
        {
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0x0F);
            assertEq(_resolveOneAndReadScore(index, word, t, heroQuadrant), 9,
                "all symbols + all colors => S=9 (the all-8-axes jackpot)");
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
            uint8 heroQuadrant = 2; // hero quad's bit = 0x04
            uint256 word = uint256(keccak256("packing_s8"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            // Variant-2 S=8: all 4 symbols + 3 colors (drop q0's color). Hero q2 full
            // (sym2+col1=3) + q1 full(2) + q3 full(2) + q0 symbol-only(1) = 8.
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0x0E);
            (uint8 s, uint256 payout) = _resolveOneAndReadScoreAndPayout(
                index,
                word,
                t,
                heroQuadrant
            );
            assertEq(s, 8, "Variant-2 all-symbols + 3-colors => S=8");
            assertGt(
                payout,
                0,
                "S=8 routes to the SEPARATE, now-final nonzero S8 slot - dispatch shape is final"
            );
        }

        // S=0..7: packed slot decode. Variant-2 S=3 (hero symbol + one ordinary
        // symbol, no colors) reads the packed slot — nonzero.
        {
            uint8 heroQuadrant = 3; // hero bit = 0x08
            uint256 word = uint256(keccak256("packing_s3"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            // sym = hero(0x08) | q0(0x01) = 0x09, no colors => S = 2 + 1 = 3.
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x09, /*col*/ 0);
            (uint8 s, uint256 payout) = _resolveOneAndReadScoreAndPayout(
                index,
                word,
                t,
                heroQuadrant
            );
            assertEq(s, 3, "Variant-2 hero symbol + 1 ordinary symbol => S=3");
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

        // Variant-2 S=6 (all symbols + hero color only): below the S>=7 gate → NO award.
        // hero q0 full(3) + 3 ordinary symbol-only(1 each) = 6.
        {
            uint256 word = uint256(keccak256("dgnrs_s6"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0x01);
            (uint8 s, uint256 gain, ) = _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 6, "Variant-2 all-symbols + hero-color => S=6");
            assertEq(gain, 0, "S=6 is below the S>=7 DGNRS gate - no award");
        }
        // Variant-2 S=7 (all symbols + hero color + one ordinary color): award at 4%.
        // hero q0 full(3) + q1 full(2) + 2 ordinary symbol-only(1 each) = 7.
        {
            uint256 word = uint256(keccak256("dgnrs_s7"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0x03);
            (uint8 s, uint256 gain, uint256 poolBefore) =
                _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 7, "Variant-2 all-symbols + 2-colors => S=7");
            assertGt(gain, 0, "S=7 fires the DGNRS award");
            assertEq(gain, (poolBefore * DEGEN_DGNRS_7_BPS) / 10_000, "S=7 award == 4% of Reward pool");
        }
        // Variant-2 S=8 (all symbols + 3 colors): award at 8% (DEGEN_DGNRS_8_BPS).
        // hero q0 full(3) + q1 full(2) + q2 full(2) + q3 symbol-only(1) = 8.
        {
            uint256 word = uint256(keccak256("dgnrs_s8"));
            uint32 resultTicket = _resultTicketForSpin(index, word, 0);
            uint32 t = _ticketV2(resultTicket, /*sym*/ 0x0F, /*col*/ 0x07);
            (uint8 s, uint256 gain, uint256 poolBefore) =
                _resolveEthAndDgnrs(index, word, t, heroQuadrant, perTicket);
            assertEq(s, 8, "Variant-2 all-symbols + 3-colors => S=8");
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
        // The chosen heroSymbol is decoded from customTraits >> (heroQuadrant*8) & 7.
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

    /// @notice DEC-01 R2 per-sample correctness. Drives many single-spin WWXRP bets
    ///         through the live resolve path and checks each rigged score against the
    ///         pre-rig (honest) reel: the rig lifts by exactly 0, +1, or +2 (the +2
    ///         color-unlock is ALLOWED under Variant-2), never below honest, never
    ///         fires when the honest reel is full / 1-off (M >= 7), and can NEVER lift
    ///         a reel to the S=9 jackpot (a rigged S=9 only ever coincides with an
    ///         honest S=9). Over the batch the lift rate among eligible (M <= 6) reels
    ///         sits at ~60% (the 3/5 gate). Validates `_rigWwxrpResult` end-to-end.
    function test_WWXRP_Rig_ControlledBehavior() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 400 ether);
        uint48 index = 1;
        uint8 heroQuadrant = 2;
        uint32 customTraits = _ticketWithHero(heroQuadrant, 4);

        uint256 eligible; // honest M <= 6 (rig may fire)
        uint256 lifted; // rigged score > honest (rig fired and a cell was forced)
        uint256 lifted2; // rigged score == honest + 2 (the color-unlock)
        uint256 samples = 300;

        for (uint256 i; i < samples; ++i) {
            uint256 word = uint256(keccak256(abi.encodePacked("wwxrp_rig", i)));
            vm.prank(player);
            game.placeDegeneretteBet(address(0), CURRENCY_WWXRP, 1 ether, 1, customTraits, heroQuadrant);
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
                _honestScoreAndM(customTraits, honestResult, heroQuadrant);

            // Per-sample correctness: lift is 0, +1, or +2 (+2 = color-unlock), never
            // negative.
            assertTrue(
                s >= honestS && s <= honestS + 2,
                "rig lifts the score by 0, +1, or +2 (never below honest)"
            );
            // The rig can NEVER fabricate the S=9 jackpot: a rigged S=9 only when the
            // HONEST reel was already S=9 (m>=7 cap leaves the jackpot tier untouched).
            if (s == 9) {
                assertEq(honestS, 9, "rig must NEVER lift a reel to S=9 (jackpot unreachable by the rig)");
            }
            if (honestM >= 7) {
                assertEq(s, honestS, "rig must NOT fire on a full / 1-off reel (M >= 7)");
            } else {
                ++eligible;
                if (s > honestS) ++lifted;
                if (s == honestS + 2) ++lifted2;
            }
        }

        // Non-vacuity + ~60% gate: among eligible reels the rig fires ~3/5 of the time.
        assertGt(eligible, 150, "non-vacuity: most reels are rig-eligible (M <= 6)");
        assertGt(lifted, 0, "non-vacuity: the rig actually lifts some reels");
        assertGt(lifted2, 0, "non-vacuity: the +2 color-unlock actually occurs (R2)");
        assertLt(lifted, eligible, "non-vacuity: the rig is NOT always-on (40% no-op)");
        assertGe(lifted * 100, eligible * 45, "lift rate >= 45% (3/5 gate, sample tolerance)");
        assertLe(lifted * 100, eligible * 75, "lift rate <= 75% (3/5 gate, sample tolerance)");
    }

    /// @notice DEC-01 R2 DISTRIBUTION parity — runs the REAL `_rigWwxrpResult` over
    ///         many seeds (live resolve path) for a fixed N=0 / hero-common ticket and
    ///         confirms the empirical rigged-score histogram matches the generator's
    ///         analytical `p_score_distribution_rigged(N=0)` (the distribution the
    ///         rigged WWXRP payout tables are solved against). Expected per-mille-of-1e6
    ///         probabilities are from derive_5_tables.py's R2 model (see the stat gate
    ///         DegenerettePerNEvExactness for the analytical cross-check). A wrong rig
    ///         (different pool / no +2 / wrong gate) would blow the per-bin tolerances.
    function test_WWXRP_Rig_DistributionParity() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 5_000 ether);
        uint48 index = 1;
        uint8 heroQuadrant = 2;
        // All-common colors (N=0) + hero-common => the conditional distribution is
        // exactly riggedPScore(N=0) (no hero-placement averaging needed at N=0).
        uint32 customTraits = _ticketWithHero(heroQuadrant, 4);

        uint256 K = 3000;
        uint256[10] memory counts;
        uint256 sumS;

        for (uint256 i; i < K; ++i) {
            uint256 word = uint256(keccak256(abi.encodePacked("wwxrp_rig_dist", i)));
            vm.prank(player);
            game.placeDegeneretteBet(address(0), CURRENCY_WWXRP, 1 ether, 1, customTraits, heroQuadrant);
            uint64 betId = _betNonce(player);
            _injectLootboxRngWord(index, word);
            vm.recordLogs();
            vm.prank(player);
            game.resolveDegeneretteBets(address(0), _one(betId));
            (uint8 s, ) = _firstSpinScoreAndPayout();
            _injectLootboxRngWord(index, 0);
            counts[s] += 1;
            sumS += s;
        }

        // Analytical riggedPScore(N=0), scaled to 1e6 (derive_5_tables.py R2 model):
        //   S0 234473  S1 391904  S2 219128  S3 102687  S4 39080  S>=5 12728
        uint32[6] memory expScaled = [
            uint32(234473), 391904, 219128, 102687, 39080, 12728
        ];
        uint256[6] memory obs;
        for (uint8 s; s < 5; ++s) obs[s] = counts[s];
        obs[5] = counts[5] + counts[6] + counts[7] + counts[8] + counts[9];

        // Per-bin frequency tolerance (~4σ at K=3000): bins 0..4 within 3.5% absolute,
        // the rare tail (S>=5) within 1.5% absolute.
        for (uint8 b; b < 6; ++b) {
            uint256 obsScaled = (obs[b] * 1_000_000) / K;
            uint256 diff = obsScaled > expScaled[b]
                ? obsScaled - expScaled[b]
                : expScaled[b] - obsScaled;
            uint256 tol = b < 5 ? 35_000 : 15_000;
            assertLt(
                diff,
                tol,
                "rig-parity: rigged-score bin frequency outside tolerance vs analytical R2 dist"
            );
        }

        // Mean parity: analytical E[S | N=0] = 1.36088 (scaled x1000 = 1361), ±0.09.
        uint256 meanScaled = (sumS * 1000) / K;
        uint256 meanDiff = meanScaled > 1361 ? meanScaled - 1361 : 1361 - meanScaled;
        assertLt(meanDiff, 90, "rig-parity: empirical mean score diverges from analytical E[S]");

        // The rig essentially never reaches S=9 here (honest 1/12.96M); over K=3000 it
        // must be exactly 0.
        assertEq(counts[9], 0, "rig-parity: no S=9 over the sample (rig cannot fabricate the jackpot)");
    }

    /// @dev Mirror Variant-2 `_score` AND count matched axes (M) for an honest
    ///      (pre-rig) reel. Variant-2: a symbol match scores +1 (hero +2); the
    ///      quadrant's color scores +1 ONLY IF its symbol also matched. M counts all
    ///      8 per-axis matches (color + symbol) regardless of gating — the rig's
    ///      m>=7 cap is on M, not S. S is naturally <= 9 (no clamp needed).
    function _honestScoreAndM(uint32 playerTicket, uint32 resultTicket, uint8 heroQuadrant)
        internal
        pure
        returns (uint8 s, uint8 m)
    {
        for (uint8 q; q < 4; ++q) {
            uint8 pq = uint8(playerTicket >> (q * 8));
            uint8 rq = uint8(resultTicket >> (q * 8));
            bool colorMatch = ((pq >> 3) & 7) == ((rq >> 3) & 7);
            bool symMatch = (pq & 7) == (rq & 7);
            if (colorMatch) ++m;
            if (symMatch) ++m;
            if (symMatch) {
                s += (q == heroQuadrant) ? 2 : 1;
                if (colorMatch) ++s; // Variant-2: color gated behind symbol
            }
        }
    }

    // ---- Task 3 helpers ------------------------------------------------------

    /// @dev Place a fixed set of ETH wagers with chosen hero symbols/quadrants.
    ///      heroSymbol = customTraits >> (heroQuadrant*8) & 7. We choose distinct
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
        // Mirror Variant-2 _score: symbol +1 (hero +2); color +1 only if symbol matched.
        for (uint8 q; q < 4; ++q) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            bool colorMatch = ((pQuad >> 3) & 7) == ((rQuad >> 3) & 7);
            if ((pQuad & 7) == (rQuad & 7)) {
                s += (q == heroQuadrant) ? 2 : 1;
                if (colorMatch) ++s;
            }
        }
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
        uint32 customTraits,
        uint8 heroQuadrant
    ) internal returns (uint8 s) {
        (s, ) = _resolveOneAndReadScoreAndPayout(index, word, customTraits, heroQuadrant);
    }

    function _resolveOneAndReadScoreAndPayout(
        uint48 index,
        uint256 word,
        uint32 customTraits,
        uint8 heroQuadrant
    ) internal returns (uint8 s, uint256 payout) {
        uint128 perTicket = 0.01 ether;
        uint64 betId = _placeEthBet(perTicket, 1, customTraits, heroQuadrant);
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
        uint32 customTraits,
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
            customTraits,
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
        uint32 customTraits,
        uint8 heroQuadrant,
        uint128 perTicket
    ) internal returns (uint8 s, uint256 award, uint256 poolBefore) {
        uint64 betId = _placeEthBet(perTicket, 1, customTraits, heroQuadrant);
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
        uint32 customTraits,
        uint8 heroQuadrant
    ) internal returns (uint64 betId) {
        uint256 ethValue = uint256(perTicket) * spins;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(
            address(0),
            CURRENCY_ETH,
            perTicket,
            spins,
            customTraits,
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

    /// @dev Variant-2 ticket constructor. `symMask`/`colMask` are 4-bit masks (bit q
    ///      = quadrant q). For each quadrant, the player's symbol matches the result iff
    ///      symMask bit q is set (else a guaranteed mismatch); likewise the color via
    ///      colMask. The resulting Variant-2 score is deterministic:
    ///        S = Σ_q [ symMatch(q) ? ((q==hero?2:1) + (colMatch(q)?1:0)) : 0 ].
    function _ticketV2(uint32 resultTicket, uint8 symMask, uint8 colMask)
        internal
        pure
        returns (uint32 t)
    {
        uint8[4] memory colors;
        uint8[4] memory symbols;
        for (uint8 q; q < 4; ++q) {
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            bool symM = ((symMask >> q) & 1) == 1;
            bool colM = ((colMask >> q) & 1) == 1;
            symbols[q] = symM ? rSymbol : (rSymbol == 0 ? 1 : 0);
            colors[q] = colM ? rColor : (rColor == 0 ? 1 : 0);
        }
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
