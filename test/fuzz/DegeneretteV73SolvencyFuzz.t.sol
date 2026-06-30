// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DegeneretteV73SolvencyFuzz — stateless property fuzz over the v73 Variant-2 surface.
///
/// @notice Sweeps random (customTicket, heroQuadrant, rngWord, currency) and resolves one live spin,
///         asserting the protocol-pillar invariants hold for EVERY reachable input — the coverage the
///         analytical EV proof and the single-config 3000-spin parity test sampled only narrowly:
///           SOLVENCY  — score S in {0..9}; the honest base payout never exceeds the per-N S=9 pin
///                       (the table's max entry → no dispatch reads an inflated/OOB value); the pay
///                       floor holds (S<2 → payout 0).
///           RNG       — the WWXRP rig only LIFTS (rigged S in [honestS, honestS+2]) and can NEVER
///                       fabricate the S=9 jackpot (rigged S==9 ⇒ the honest reel already had M==8).
///           LIVENESS  — every resolve succeeds (no revert/brick) for any ticket/hero/seed.
///
/// @dev Run: forge test --match-path test/fuzz/DegeneretteV73SolvencyFuzz.t.sol
contract DegeneretteV73SolvencyFuzz is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34;
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 39;
    uint256 private constant DEGENERETTE_BETS_SLOT = 38;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;

    bytes1 private constant QUICK_PLAY_SALT = 0x51;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    bytes32 private constant FULL_TICKET_RESULT_SIG =
        0xed1cde932a37b486ad1cc829c4ce89bf3bff943b68625e57cad59bc1bc18d8de;

    // ROI curve mirror (DegeneretteModule._roiBpsFromScore).
    uint256 private constant ACTIVITY_SCORE_MAX_POINTS = 305;
    uint256 private constant ACTIVITY_SEG_B_KNEE_POINTS = 500;
    uint256 private constant ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000;
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_VA_BPS = 9_891;
    uint256 private constant ROI_VB_BPS = 9_970;
    uint256 private constant ROI_MAX_BPS = 9_990;

    // S=9 jackpot pins (the max table entry per N).
    uint256[5] private S9_PIN = [
        uint256(10_756_411), 12_583_037, 14_792_939, 17_512_324, 20_916_435
    ];

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("v73_fuzz_player");
        vm.deal(player, 1_000_000 ether);
        vm.deal(address(game), 1_000_000 ether);
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
        // Big future pool so no ETH-side cap interacts (FLIP/WWXRP don't touch it anyway).
        _seedFuturePrizePool(10_000_000 ether);
    }

    /// forge-config: default.fuzz.runs = 400
    function testFuzz_v73_solvency_and_rig(uint32 ticketSeed, uint8 heroRaw, uint256 word, bool useWwxrp)
        public
    {
        word = bound(word, 1, type(uint256).max); // rngWord must be nonzero
        uint8 hero = heroRaw % 4;
        uint32 ticket = ticketSeed; // any 32-bit value is a structurally valid ticket
        uint8 currency = useWwxrp ? CURRENCY_WWXRP : CURRENCY_FLIP;
        uint128 perTicket = useWwxrp ? uint128(1 ether) : uint128(100 ether);

        // Fund + place (self-funded per run for robustness).
        if (useWwxrp) {
            vm.prank(address(game));
            wwxrp.mintPrize(player, uint256(perTicket) + 1 ether);
        } else {
            vm.prank(address(game));
            coin.mintForGame(player, uint256(perTicket) + 1 ether);
        }
        vm.prank(player);
        game.placeDegeneretteBet(address(0), currency, perTicket, 1, ticket, hero);
        uint64 betId = _betNonce(player);
        uint256 roiBps = _roiBpsOfBet(betId);

        _injectLootboxRngWord(1, word);
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), _one(betId)); // LIVENESS: must not revert
        (uint8 s, uint256 payout) = _firstSpinScoreAndPayout();
        _injectLootboxRngWord(1, 0);

        // SOLVENCY: score in range.
        assertLe(s, 9, "score must be in {0..9}");

        uint8 n = _goldCount(ticket);

        if (!useWwxrp) {
            // FLIP honest lane: payout = perTicket * base * roiBps / 1e6 exactly (no bonus/cap/DGNRS).
            // SOLVENCY: the decoded base never exceeds the per-N S=9 pin (the table's max entry).
            uint256 base = (payout * 1_000_000) / (uint256(perTicket) * roiBps);
            assertLe(base, S9_PIN[n], "honest base payout exceeds the per-N S=9 pin (inflated/OOB table read)");
            // Pay floor S>=2.
            if (s < 2) assertEq(payout, 0, "pay floor: S<2 must pay 0");
        } else {
            // WWXRP: compare against the honest (pre-rig) reel.
            uint32 honestReel = _resultTicketForSpin(1, word, 0);
            (uint8 honestS, uint8 honestM) = _scoreAndM(ticket, honestReel, hero);
            // RNG: the rig only lifts (0..+2), never below honest.
            assertGe(s, honestS, "rig lowered the score below honest");
            assertLe(s, honestS + 2, "rig lifted the score by more than +2");
            // RNG: the rig can NEVER fabricate the S=9 jackpot.
            if (s == 9) {
                assertEq(honestM, 8, "rig manufactured S=9 (honest reel was not a full 8-axis match)");
            }
        }
    }

    // ---- helpers ----

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

    function _goldCount(uint32 ticket) internal pure returns (uint8 n) {
        for (uint8 q; q < 4; ++q) {
            if (((ticket >> (q * 8 + 3)) & 7) == 7) ++n;
        }
    }

    function _roiBpsOfBet(uint64 betId) internal view returns (uint256 roiBps) {
        bytes32 inner = keccak256(abi.encode(player, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 slot = keccak256(abi.encode(uint256(betId), inner));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 score = (packed >> FT_ACTIVITY_SHIFT) & 0xFFFF;
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return ROI_MAX_BPS;
        if (score <= ACTIVITY_SCORE_MAX_POINTS) {
            return ROI_MIN_BPS + (score * (ROI_VA_BPS - ROI_MIN_BPS)) / ACTIVITY_SCORE_MAX_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return ROI_VA_BPS + ((score - ACTIVITY_SCORE_MAX_POINTS) * (ROI_VB_BPS - ROI_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - ACTIVITY_SCORE_MAX_POINTS);
        }
        return ROI_VB_BPS + ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (ROI_MAX_BPS - ROI_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
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
