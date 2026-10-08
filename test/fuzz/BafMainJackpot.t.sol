// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {BafBracketFixture} from "../helpers/BafStageHost.sol";
import {BafBoardSeed} from "../helpers/BafBoardSeed.sol";
import {IDegenerusJackpots} from "../../contracts/interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @notice The existing BAF stage and main draw share the same winning traits, with no new work state.
contract BafMainJackpotTest is BafBracketFixture {
    uint24 private constant LVL = 20;
    uint256 private constant WORD = uint256(keccak256("baf-main-board")) | 1;
    bytes32 private constant CANDIDATES = keccak256("BafCandidates(uint24,uint24,uint16,uint24,uint8,uint32[])");
    uint256 private constant ONE = GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL
        + GasBounds.DAILY_PHASE_TAIL + 150_000;

    struct RoundEvent { uint24 sourceLevel; uint8 trait; uint32[] candidates; }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 40 days);
        _hostAt(LVL, WORD, false);
        host.seedPools(40 ether, 200 ether, 0, LVL - 1, 35 ether);
        host.seedFrozen(true, 0, 2 ether);
        _seedBracket(LVL);
        _armDepositDraw();
        vm.deal(address(game), address(game).balance + 2_000 ether);
    }

    function test_BafAndMainUseTheSameThreeTraits() public { _sharedBoard(WORD, false, false); }
    function test_SharedBoardIncludesHeroOverride() public { _sharedBoard(WORD, true, false); }
    function test_SharedBoardHonorsGoldenTicketHeroBan() public { _sharedBoard(WORD, true, true); }
    function test_SurvivingGoldSixIsExcludedFromBothBafLevels() public { _sharedBoard(843, false, false); }

    function test_ArmingPreparesEmptyBuffersInsteadOfSamplingOldLevels() public {
        // With no new entries, either physical buffer can still hold an older level.
        host.seedBufferLevel(LVL - 2);
        host.seedBufferLevel(LVL - 1);
        host.seedOneEntry(LVL - 2, 7, address(0xBAF701));
        host.seedOneEntry(LVL - 1, 7, address(0xBAF702));
        assertEq(game.sampleTraitEntries(false, 7, WORD).length, 1);
        assertEq(game.sampleTraitEntries(true, 7, WORD).length, 1);

        host.daily(9_500_000);

        assertEq(host.workView().kind, 7, "BAF armed");
        assertEq(host.bufferLevel(false), LVL);
        assertEq(host.bufferLevel(true), LVL + 1);
        assertEq(game.sampleTraitEntries(false, 7, WORD).length, 0, "old current tickets cleared");
        assertEq(game.sampleTraitEntries(true, 7, WORD).length, 0, "old next tickets cleared");
    }

    function _sharedBoard(uint256 word, bool hero, bool banned) private {
        host.seedSession(LVL, word, false);
        uint256 context = BafBoardSeed.context(LVL, word, 48);
        uint8 heroQuadrant = uint8(context >> 120) == 0 ? 1 : 0;
        uint8 baseTrait = uint8(context >> (uint256(heroQuadrant) * 8));
        uint8 heroSymbol = (baseTrait + 1) & 7;
        if (hero) host.seedHero(heroQuadrant, heroSymbol, banned);
        host.daily(9_500_000);
        assertEq(host.workView().kind, 7, "existing BAF stage is armed");
        uint8[24] memory drawnTraits;
        uint256 seen;
        for (uint256 calls; host.workView().kind == 7; ++calls) {
            assertLt(calls, 32, "BAF completes");
            vm.recordLogs();
            host.daily(ONE);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics.length == 0 || logs[j].topics[0] != CANDIDATES) continue;
                RoundEvent memory d;
                (d.sourceLevel, d.trait, d.candidates) = abi.decode(logs[j].data, (uint24, uint8, uint32[]));
                assertEq(uint256(logs[j].topics[3]), seen, "each near round appears once in order");
                assertEq(d.sourceLevel, LVL + seen / 12);
                assertEq(d.candidates.length, 4, "losing spots are retained");
                drawnTraits[seen++] = d.trait;
            }
        }
        assertEq(seen, 24, "48 current and 48 next-level spots");
        (bool present,) = host.frozenMainBoard();
        assertFalse(present, "BAF keeps its original position before main");
        for (uint256 calls; !present; ++calls) {
            assertLt(calls, 64, "main completes");
            host.daily(9_000_000);
            (present,) = host.frozenMainBoard();
        }
        (, uint32 board) = host.frozenMainBoard();
        if (hero) assertEq(uint8(board >> (uint256(heroQuadrant) * 8)) & 7, banned ? baseTrait & 7 : heroSymbol);
        if (word == 843) assertEq(uint8(board >> 24), 253, "fixture retains Gold Six");
        // Hero changes symbols only, so the reference board's gold/solo choice remains valid.
        uint256 actual = (context & ~uint256(type(uint32).max)) | board;
        for (uint256 r; r < 24; ++r) assertEq(drawnTraits[r], BafBoardSeed.trait(r, 48, actual), "same main non-solo trait");
    }

    function testFuzz_ThreeTraitsAtEveryScaleAndSolo(uint8 rawSolo, uint8 rawScale) public view {
        uint8 solo = rawSolo % 4;
        uint256 rounds = 48 << (rawScale % 6);
        uint8[3] memory traits;
        for (uint8 q; q < 3; ++q) traits[q] = (q < solo ? q : q + 1) * 64;
        uint256[4][2] memory counts;
        for (uint256 pair; pair < rounds / 4; ++pair) {
            (, IDegenerusJackpots.BafRound[2] memory draws) = jackpots.bafPairWinners(LVL, WORD, pair, rounds, traits);
            for (uint256 j; j < 2; ++j) {
                uint8 q = draws[j].trait >> 6;
                assertTrue(q != solo, "solo excluded at both levels");
                assertEq(draws[j].candidates.length, 4);
                counts[(2 * pair + j) / (rounds / 4)][q] += 4;
            }
        }
        for (uint256 band; band < 2; ++band) {
            for (uint256 q; q < 4; ++q) assertEq(counts[band][q], q == solo ? 0 : rounds / 3);
        }
    }

    function test_CandidateEventsRetainAllZeroScoreSpots() public {
        host.seedSession(LVL, WORD, true);
        _armBaf(LVL, 100 ether, 0);
        vm.store(address(jackpots), keccak256(abi.encode(uint256(LVL), uint256(2))), bytes32(uint256(1)));
        vm.recordLogs();
        host.daily(ONE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 seen;
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0 || logs[j].topics[0] != CANDIDATES) continue;
            RoundEvent memory d;
                (d.sourceLevel, d.trait, d.candidates) = abi.decode(logs[j].data, (uint24, uint8, uint32[]));
            assertEq(uint256(logs[j].topics[3]), seen++);
            assertEq(d.candidates.length, 4);
            for (uint256 k; k < 4; ++k) assertGt(d.candidates[k], 0);
        }
        assertGt(seen, 0);
        assertEq(_creditedIn(logs), 0, "zero scores receive no prizes");
    }

    function test_EmptyAndSingleEntryBucketsAreNotRerouted() public {
        host.clearTrait(LVL, 0);
        host.clearTrait(LVL, 64);
        address lone = address(0xBAF123);
        host.seedOneEntry(LVL, 64, lone);
        (uint32[4] memory winners, IDegenerusJackpots.BafRound[2] memory draws) = jackpots.bafPairWinners(LVL, WORD, 0, 48, [uint8(0), 64, 128]);
        assertEq(draws[0].candidates.length, 0);
        assertEq(draws[1].candidates.length, 1);
        assertEq(draws[1].candidates[0], game.walletIdOf(lone));
        for (uint256 i; i < 4; ++i) assertEq(winners[i], 0, "empty or zero-score entries do not win");
    }

    function test_TiedDuplicateAndLosingCandidatesRemainInTheSlate() public {
        uint32 a = host.seedWallet(address(0xBAF111));
        uint32 b = host.seedWallet(address(0xBAF112));
        uint32 c = host.seedWallet(address(0xBAF113));
        vm.startPrank(ContractAddresses.COINFLIP);
        jackpots.recordBafFlip(a, LVL, 123);
        jackpots.recordBafFlip(b, LVL, 123);
        vm.stopPrank();
        uint32[] memory ids = new uint32[](4);
        ids[0] = a; ids[1] = b; ids[2] = a; ids[3] = c;
        vm.mockCall(address(game), abi.encodeWithSelector(game.sampleTraitEntries.selector), abi.encode(ids));
        (uint32[4] memory winners, IDegenerusJackpots.BafRound[2] memory draws) = jackpots.bafPairWinners(LVL, WORD, 0, 48, [uint8(0), 64, 128]);
        assertEq(winners[0], a, "ties retain the first candidate");
        assertEq(winners[1], b, "runner-up is a distinct wallet");
        assertEq(abi.encode(draws[0].candidates), abi.encode(ids), "duplicate and losing spots remain");
    }
}
