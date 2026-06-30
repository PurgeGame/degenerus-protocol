// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DegeneretteV73MutationKills — pillar-targeted mutation-kill regression for the v73
///        Variant-2 rescore surface (`_score`, `_rigWwxrpResult`, `_getBasePayoutBps`).
///
/// @notice Each test PASSES on the clean (byte-frozen) v73 subject and FAILS when the named mutation
///         is re-applied in place — the "do the tests actually catch a bug" bar the rest of the spine
///         meets (see test/mutation/MutationKills.t.sol). Reaches the FROZEN private functions through
///         the public resolve path and reads the score/payout off the DegeneretteResult event. Grouped
///         by the three audited pillars (Solvency · RNG integrity · Liveness/no-brick).
///
/// @dev Run: forge test --match-path test/mutation/DegeneretteV73MutationKills.t.sol
///      Validation: each mutation below was transiently re-applied to confirm the test goes red, then
///      `git checkout -- contracts/` restored the frozen subject (TEST-ONLY; no persistent .sol edit).
contract DegeneretteV73MutationKills is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34;
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 39;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    bytes32 private constant FULL_TICKET_RESULT_SIG =
        0xed1cde932a37b486ad1cc829c4ce89bf3bff943b68625e57cad59bc1bc18d8de;

    // ROI curve mirror (DegeneretteModule._roiBpsFromScore) — to recover the exact base payout.
    uint256 private constant ACTIVITY_SCORE_MAX_POINTS = 305;
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_VA_BPS = 9_891;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;
    uint256 private constant DEGENERETTE_BETS_SLOT = 38;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("v73_mutkill_player");
        vm.deal(player, 10_000 ether);
        vm.deal(address(game), 5_000 ether);
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }

    // =====================================================================================
    // PILLAR 1 — SOLVENCY / scoring correctness
    // =====================================================================================

    /// @notice KILLS `_score` color-gate removal (the Variant-2 essence). A player matching every
    ///         COLOR but no SYMBOL scores S=0 (colors are gated behind symbols) → pays nothing. A
    ///         mutant that counts color independently (the old S=A+2H) scores S=4 → pays > 0.
    function test_kill_score_colorGate_loneColorsScoreZero() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint256 word = uint256(keccak256("colorgate"));
        uint32 reel = _resultTicketForSpin(1, word, 0);
        // all 4 colors match, no symbols → Variant-2 S=0.
        uint32 t = _ticketV2(reel, /*sym*/ 0x0, /*col*/ 0xF);
        (uint8 s, uint256 payout) = _resolveEthScorePayout(word, t, 0);
        assertEq(s, 0, "Variant-2: 4 colors + 0 symbols must score 0 (color gated behind symbol)");
        assertEq(payout, 0, "S=0 pays nothing (a color-independent mutant would score 4 and pay)");
    }

    /// @notice KILLS `_score` hero `+2`→`+1`. The hero symbol alone scores S=2 (a paying floor win).
    ///         A `+1` mutant scores S=1 → pays 0.
    function test_kill_score_heroPlusTwo_heroAlonePays() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint8 hero = 1;
        uint256 word = uint256(keccak256("heroplus2"));
        uint32 reel = _resultTicketForSpin(1, word, 0);
        uint32 t = _ticketV2(reel, /*sym*/ uint8(1) << hero, /*col*/ 0);
        (uint8 s, uint256 payout) = _resolveEthScorePayout(word, t, hero);
        assertEq(s, 2, "hero symbol alone scores S=2 (hero +2); a +1 mutant would score 1");
        assertGt(payout, 0, "S=2 pays (a hero +1 mutant -> S=1 -> 0)");
    }

    /// @notice KILLS an ordinary-symbol `+1`→`+2` mutant. A single NON-hero symbol scores S=1 (below
    ///         the S>=2 floor) → pays 0. A mutant scoring ordinary symbols +2 → S=2 → pays.
    function test_kill_score_ordinaryPlusOne_loneOrdinaryPaysZero() public {
        _seedFuturePrizePool(1_000_000 ether);
        uint8 hero = 0;
        uint256 word = uint256(keccak256("ordinaryplus1"));
        uint32 reel = _resultTicketForSpin(1, word, 0);
        // match ONE non-hero symbol (quad 1), nothing else.
        uint32 t = _ticketV2(reel, /*sym*/ 0x2, /*col*/ 0);
        (uint8 s, uint256 payout) = _resolveEthScorePayout(word, t, hero);
        assertEq(s, 1, "a lone non-hero symbol scores S=1 (below floor)");
        assertEq(payout, 0, "S=1 pays 0 (an ordinary +2 mutant -> S=2 -> pays)");
    }

    /// @notice KILLS the `_getBasePayoutBps` heroIsGold selector (ignore / gold<->common swap). For a
    ///         fixed N=2 ticket scoring S=5 on FLIP (no bonus/cap), the base payout is the HEROGOLD
    ///         table when the hero quadrant is gold and the HEROCOMMON table when it is common — two
    ///         DISTINCT calibrated values. A mutant that ignores heroIsGold pays one table for both.
    function test_kill_dispatch_heroIsGold_selectsCorrectTable() public {
        // Generator constants (slot 5, S=5) decoded from QUICK_PLAY_PAYOUTS_N2_*_PACKED:
        //   N2 hero-gold[5]   = 0x150a = 5386 ;  N2 hero-common[5] = 0x146f = 5231.
        uint256 N2_HEROGOLD_S5 = 5386;
        uint256 N2_HEROCOMMON_S5 = 5231;

        // hero-gold: colors [gold,gold,common,common], hero=0 (gold) -> N=2, heroIsGold=true.
        uint8[4] memory cGold = [uint8(7), 7, 0, 0];
        uint256 baseGold = _flipBaseForColorsSymbols(cGold, /*hero*/ 0, /*symMask*/ 0xF, "hg", 5);
        assertEq(baseGold, N2_HEROGOLD_S5, "N=2 hero-gold S=5 must read the HEROGOLD table");

        // hero-common: colors [common,gold,gold,common], hero=0 (common) -> N=2, heroIsGold=false.
        uint8[4] memory cCommon = [uint8(0), 7, 7, 0];
        uint256 baseCommon = _flipBaseForColorsSymbols(cCommon, /*hero*/ 0, /*symMask*/ 0xF, "hc", 5);
        assertEq(baseCommon, N2_HEROCOMMON_S5, "N=2 hero-common S=5 must read the HEROCOMMON table");

        assertTrue(baseGold != baseCommon, "non-vacuity: the two sub-case tables differ at S=5");
    }

    // =====================================================================================
    // PILLAR 2 — RNG INTEGRITY (the rig cannot manufacture the jackpot / cannot be biased)
    // =====================================================================================

    /// @notice KILLS the `_rigWwxrpResult` `m >= 7` cap. A WWXRP reel matching 7 of 8 axes (all 4
    ///         symbols + 3 colors; one color missing on a symbol-matched quad) scores S=8 and is
    ///         LEFT ALONE by the cap. Without the cap the rig would fire (when the gate fires) and
    ///         force the one eligible unmatched color → S=9: a MANUFACTURED jackpot. The chosen seed
    ///         has a firing gate, so the clean subject stays S=8 while a cap-removal mutant reaches 9.
    function test_kill_rig_m7cap_neverManufacturesS9() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 100 ether);
        uint8 hero = 2;
        // symMask=0xF (all symbols), colMask=0xE (3 colors; quad 0 color missing) -> M=7, honest S=8.
        (uint256 word, ) = _findWwxrpGateFires(hero, 0xF, 0xE);
        uint32 reel = _resultTicketForSpin(1, word, 0);
        uint32 t = _ticketV2(reel, 0xF, 0xE);
        (uint8 honestS, uint8 honestM) = _scoreAndM(t, reel, hero);
        assertEq(honestM, 7, "construction: honest M must be 7 (one axis missing)");
        assertEq(honestS, 8, "construction: honest S must be 8");
        uint8 riggedS = _resolveWwxrpScore(word, t, hero);
        assertEq(riggedS, 8, "the m>=7 cap leaves S=8 (a cap-removal mutant would fire -> S=9)");
        assertTrue(riggedS != 9, "the rig must NEVER manufacture the S=9 jackpot");
    }

    /// @notice KILLS the rig gate DIRECTION (`rigSeed % 5 >= 3`). Over many eligible (M<=6) WWXRP
    ///         spins the lift rate sits at ~60% (3/5). A flipped gate (`< 3`) drops it to ~40%, below
    ///         the 45% floor asserted here.
    function test_kill_rig_gateDirection_liftRateIsSixtyPct() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 400 ether);
        uint8 hero = 2;
        uint32 customTraits = _ticketWithHeroSym(hero, 4); // all-common, N=0
        uint256 eligible;
        uint256 lifted;
        for (uint256 i; i < 300; ++i) {
            uint256 word = uint256(keccak256(abi.encodePacked("gatedir", i)));
            uint8 riggedS = _resolveWwxrpScore(word, customTraits, hero);
            uint32 reel = _resultTicketForSpin(1, word, 0);
            (uint8 honestS, uint8 honestM) = _scoreAndM(customTraits, reel, hero);
            if (honestM <= 6) {
                ++eligible;
                if (riggedS > honestS) ++lifted;
            }
        }
        assertGt(eligible, 150, "non-vacuity: most reels are rig-eligible");
        // 60% gate; a flipped (<3) gate -> ~40% -> below this floor.
        assertGe(lifted * 100, eligible * 45, "lift rate >= 45% (kills the flipped-gate ~40% mutant)");
        assertLe(lifted * 100, eligible * 75, "lift rate <= 75%");
    }

    // =====================================================================================
    // PILLAR 3 — LIVENESS / NO-BRICK
    // =====================================================================================

    /// @notice KILLS the `_rigWwxrpResult` `u == 0` empty-pool guard. A WWXRP reel where all three
    ///         NON-hero quads are full doubles (sym+col matched) and the hero quad misses both axes
    ///         has M=6 (rig-eligible) but an EMPTY score-bearing pool (the only misses are the
    ///         excluded hero symbol and a no-op hero color). With the guard the spin resolves as a
    ///         no-op; WITHOUT the guard the `% u` is `% 0` → a div-by-zero panic that reverts (bricks)
    ///         the resolve. This test asserts the resolve succeeds.
    function test_kill_rig_emptyPoolGuard_noDivByZeroBrick() public {
        _seedFuturePrizePool(1_000_000 ether);
        _fundWwxrp(player, 100 ether);
        uint8 hero = 3;
        uint8 nonHeroMask = 0xF ^ (uint8(1) << hero); // quads 0,1,2 (full doubles); hero quad 3 misses.
        (uint256 word, ) = _findWwxrpGateFires(hero, nonHeroMask, nonHeroMask);
        uint32 reel = _resultTicketForSpin(1, word, 0);
        uint32 t = _ticketV2(reel, nonHeroMask, nonHeroMask);
        (uint8 honestS, uint8 honestM) = _scoreAndM(t, reel, hero);
        assertEq(honestM, 6, "construction: M=6 (rig-eligible)");
        assertEq(honestS, 6, "construction: 3 ordinary full doubles -> S=6");
        // The resolve must NOT revert (a missing u==0 guard -> % 0 -> panic -> revert).
        uint8 riggedS = _resolveWwxrpScore(word, t, hero);
        assertEq(riggedS, honestS, "empty-pool spin is a no-op (and does not div-by-zero brick)");
    }

    // =====================================================================================
    // Helpers
    // =====================================================================================

    /// @dev Search for a WWXRP word whose frozen rig seed FIRES the 60% gate for a _ticketV2(symMask,
    ///      colMask) construction. The eligibility / M are fixed by the masks (independent of the
    ///      seed); only the gate (rigSeed % 5 < 3) varies. Mirrors the on-chain rig seed derivation.
    function _findWwxrpGateFires(uint8 hero, uint8 symMask, uint8 colMask)
        internal
        view
        returns (uint256 word, uint32 t)
    {
        for (uint256 k; k < 4000; ++k) {
            uint256 cand = uint256(keccak256(abi.encodePacked("v73mut_gate", k, hero, symMask, colMask)));
            uint256 resultSeed = uint256(keccak256(abi.encodePacked(cand, uint32(1), QUICK_PLAY_SALT)));
            uint256 rigSeed = _hash2(resultSeed, 0x52494721); // WWXRP_RIG_SALT = "RIG!"
            if (rigSeed % 5 < 3) {
                uint32 reel = DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
                return (cand, _ticketV2(reel, symMask, colMask));
            }
        }
        revert("no firing-gate word found");
    }

    /// @dev Mirror EntropyLib.hash2 (scratch-slot keccak of two words).
    function _hash2(uint256 a, uint256 b) internal pure returns (uint256 h) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            h := keccak256(0x00, 0x40)
        }
    }

    /// @dev Resolve a FLIP spin for a player ticket built from explicit colors + a symbol match mask,
    ///      and return the decoded base payout (centi-x). FLIP has no bonus/cap/DGNRS so
    ///      payout = perTicket * base * roiBps / 1e6 exactly. `tag`/`wantS` pick a seed whose reel
    ///      does NOT gold-match the chosen gold colors, so S is the pure symbol score == wantS.
    function _flipBaseForColorsSymbols(
        uint8[4] memory colors,
        uint8 hero,
        uint8 symMask,
        string memory tag,
        uint8 wantS
    ) internal returns (uint256 base) {
        uint128 perTicket = 100 ether; // >= MIN_BET_FLIP
        _fundFlip(player, uint256(perTicket) + 1 ether);
        // Find a seed where (a) S == wantS and (b) no chosen gold color coincidentally matches the reel.
        uint256 word;
        uint32 t;
        for (uint256 k; k < 6000; ++k) {
            uint256 cand = uint256(keccak256(abi.encodePacked("v73mut_flipbase", tag, k)));
            uint32 reel = _resultTicketForSpin(1, cand, 0);
            t = _ticketColorsSymbols(reel, colors, symMask);
            (uint8 s, ) = _scoreAndM(t, reel, hero);
            if (s == wantS) {
                word = cand;
                break;
            }
        }
        require(word != 0, "no seed for wantS");
        uint64 betId = _placeBet(CURRENCY_FLIP, perTicket, t, hero);
        uint256 roiBps = _roiBpsOfBet(betId);
        _injectLootboxRngWord(1, word);
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (uint8 sOut, uint256 payout) = _firstSpinScoreAndPayout();
        _injectLootboxRngWord(1, 0);
        assertEq(sOut, wantS, "resolved score must match the engineered S");
        base = (payout * 1_000_000) / (uint256(perTicket) * roiBps);
    }

    /// @dev Build a player ticket with explicit per-quadrant colors and a symbol-match mask vs `reel`.
    ///      Color bits are the caller's choice (set N / heroIsGold); symbol matches `reel` where the
    ///      mask bit is set, else a guaranteed mismatch.
    function _ticketColorsSymbols(uint32 reel, uint8[4] memory colors, uint8 symMask)
        internal
        pure
        returns (uint32 t)
    {
        for (uint8 q; q < 4; ++q) {
            uint8 rq = uint8(reel >> (q * 8));
            uint8 rSym = rq & 7;
            bool symM = ((symMask >> q) & 1) == 1;
            uint8 sym = symM ? rSym : (rSym == 0 ? 1 : 0);
            uint8 byteVal = (q << 6) | ((colors[q] & 7) << 3) | (sym & 7);
            t |= uint32(byteVal) << (q * 8);
        }
    }

    /// @dev Variant-2 ticket from per-quadrant symbol/color match masks vs `reel` (mirrors the
    ///      DegeneretteHeroScore harness; mismatch colors land on a common value, never gold).
    function _ticketV2(uint32 reel, uint8 symMask, uint8 colMask) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint8 rq = uint8(reel >> (q * 8));
            uint8 rColor = (rq >> 3) & 7;
            uint8 rSym = rq & 7;
            bool symM = ((symMask >> q) & 1) == 1;
            bool colM = ((colMask >> q) & 1) == 1;
            uint8 sym = symM ? rSym : (rSym == 0 ? 1 : 0);
            uint8 col = colM ? rColor : (rColor == 0 ? 1 : 0);
            uint8 byteVal = (q << 6) | ((col & 7) << 3) | (sym & 7);
            t |= uint32(byteVal) << (q * 8);
        }
    }

    /// @dev A ticket whose only set field is the hero quadrant's symbol (all colors common -> N=0).
    function _ticketWithHeroSym(uint8 hero, uint8 heroSym) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint8 sym = q == hero ? (heroSym & 7) : 0;
            t |= uint32((q << 6) | sym) << (q * 8);
        }
    }

    /// @dev Variant-2 score + all-8-axis match count (M) for an honest reel.
    function _scoreAndM(uint32 pt, uint32 rt, uint8 hero) internal pure returns (uint8 s, uint8 m) {
        for (uint8 q; q < 4; ++q) {
            uint8 pq = uint8(pt >> (q * 8));
            uint8 rq = uint8(rt >> (q * 8));
            bool colorMatch = ((pq >> 3) & 7) == ((rq >> 3) & 7);
            bool symMatch = (pq & 7) == (rq & 7);
            if (colorMatch) ++m;
            if (symMatch) ++m;
            if (symMatch) {
                s += (q == hero) ? 2 : 1;
                if (colorMatch) ++s;
            }
        }
    }

    function _resolveEthScorePayout(uint256 word, uint32 t, uint8 hero)
        internal
        returns (uint8 s, uint256 payout)
    {
        uint128 perTicket = 0.01 ether;
        uint64 betId = _placeBetEth(perTicket, t, hero);
        _injectLootboxRngWord(1, word);
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, payout) = _firstSpinScoreAndPayout();
        _injectLootboxRngWord(1, 0);
    }

    function _resolveWwxrpScore(uint256 word, uint32 t, uint8 hero) internal returns (uint8 s) {
        vm.prank(player);
        game.placeDegeneretteBet(address(0), CURRENCY_WWXRP, 1 ether, 1, t, hero);
        uint64 betId = _betNonce(player);
        _injectLootboxRngWord(1, word);
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId));
        (s, ) = _firstSpinScoreAndPayout();
        _injectLootboxRngWord(1, 0);
    }

    function _placeBetEth(uint128 perTicket, uint32 t, uint8 hero) internal returns (uint64) {
        vm.prank(player);
        game.placeDegeneretteBet{value: uint256(perTicket)}(address(0), CURRENCY_ETH, perTicket, 1, t, hero);
        return _betNonce(player);
    }

    function _placeBet(uint8 currency, uint128 perTicket, uint32 t, uint8 hero) internal returns (uint64) {
        vm.prank(player);
        game.placeDegeneretteBet(address(0), currency, perTicket, 1, t, hero);
        return _betNonce(player);
    }

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _fundWwxrp(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
    }

    function _roiBpsOfBet(uint64 betId) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(player, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 slot = keccak256(abi.encode(uint256(betId), inner));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 score = (packed >> FT_ACTIVITY_SHIFT) & 0xFFFF;
        // mirror the seg-A leg of _roiBpsFromScore (engineered scores stay under the knee).
        if (score >= ACTIVITY_SCORE_MAX_POINTS) return ROI_VA_BPS;
        return ROI_MIN_BPS + (score * (ROI_VA_BPS - ROI_MIN_BPS)) / ACTIVITY_SCORE_MAX_POINTS;
    }

    function _one(uint64 betId) internal pure returns (uint64[] memory a) {
        a = new uint64[](1);
        a[0] = betId;
    }

    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    function _firstSpinScoreAndPayout() internal returns (uint8 s, uint256 payout) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) {
                (uint8 spinIdx, , uint8 matches, uint256 p) =
                    abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                if (spinIdx == 0) return (matches, p);
            }
        }
        revert("no DegeneretteResult for spin 0");
    }

    function _resultTicketForSpin(uint48 index, uint256 word, uint8 spinIdx) internal pure returns (uint32) {
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
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }
}
