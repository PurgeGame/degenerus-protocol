// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteV73SolvencyFuzz — stateless property fuzz over single-symbol bets.
///
/// @notice Sweeps random heroes and words through manual FLIP bets and automatic WWXRP spins,
///         asserting the protocol-pillar invariants hold for EVERY reachable input — the coverage the
///         analytical EV proof and the single-config 3000-spin parity test sampled only narrowly:
///           SOLVENCY  — score S in {1..9}; the honest base payout never exceeds the shared S=9 payout with four house wilds
///                       (the table's max entry → no dispatch reads an inflated/OOB value); the pay
///                       floor holds (S<3 → payout 0).
///           RNG       — the WWXRP rig only LIFTS (rigged S in [honestS, honestS+1]), never changes the
///                       house wild count and can NEVER fabricate the S=9 jackpot.
///           LIVENESS  — every resolve succeeds (no revert/brick) for any ticket/hero/seed.
///
/// @dev Run: forge test --match-path test/fuzz/DegeneretteV73SolvencyFuzz.t.sol
contract DegeneretteV73SolvencyFuzz is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;

    bytes1 private constant QUICK_PLAY_SALT = 0x51;
    uint8 private constant CURRENCY_FLIP = 1;


    // ROI curve mirror (DegeneretteModule._roiBpsFromScore).
    uint256 private constant ACTIVITY_SCORE_MAX_POINTS = 305;
    uint256 private constant ACTIVITY_SEG_B_KNEE_POINTS = 500;
    uint256 private constant ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000;
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_VA_BPS = 9_891;
    uint256 private constant ROI_VB_BPS = 9_970;
    uint256 private constant ROI_MAX_BPS = 9_990;

    address private player;
    DegeneretteMathHarness private math;

    function setUp() public {
        _deployProtocol();
        math = new DegeneretteMathHarness();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("v73_fuzz_player");
        vm.deal(player, 1_000_000 ether);
        vm.deal(address(game), 1_000_000 ether);
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
        // Big future pool so no ETH-side cap interacts (FLIP/WWXRP don't touch it anyway).
        _seedFuturePrizePool(10_000_000 ether);
    }

    /// forge-config: default.fuzz.runs = 400
    function testFuzz_v73_manualFlipSolvency(uint8 symbol, uint256 word) public {
        word = bound(word, 2, type(uint256).max);
        symbol %= 24;
        uint128 perTicket = 100;
        vm.prank(address(game));
        coin.mintForGame(player, uint256(perTicket) + 1);
        vm.prank(player);
        game.placeDegeneretteBet(0, CURRENCY_FLIP, perTicket, 1, symbol);
        uint64 betId = DQ.lastBetId(vm, address(game), 1);
        uint256 bet = game.degeneretteBetInfo(1, betId);
        uint256 roiBps = _roiBps(DQ.activity(bet));
        _injectLootboxRngWord(1, word);
        // Bets resolve only as the engine's Degenerette read consumer (mineFlip).
        vm.recordLogs();
        vm.prank(player);
        game.mineFlip(0);
        (uint8 score, uint8 wilds) = _firstSpin();
        assertLe(wilds, 4, "at most four house wilds");
        uint256 payout = math.payout(score, wilds, CURRENCY_FLIP, DQ.stake(bet), DQ.activity(bet));
        assertGe(score, 1, "the hero color always scores");
        assertLe(score, 9, "score must be in {1..9}");
        uint256 base = (payout * 1_000_000) / (uint256(perTicket) * roiBps);
        assertLe(base, 46_000_000, "honest base exceeds S=9 with four house wilds");
        if (score < 3) assertEq(payout, 0, "pay floor: S<3 must pay 0");
    }

    /// @notice WWXRP keeps its rig through the production automatic-spin resolver.
    /// forge-config: default.fuzz.runs = 400
    function testFuzz_v73_automaticWwxrpRig(uint8 symbol, uint256 word) public {
        symbol %= 24;
        bytes memory facade = address(game).code;
        vm.etch(address(game), ContractAddresses.GAME_DEGENERETTE_MODULE.code);
        vm.recordLogs();
        (bool ok, bytes memory result) = address(game).call(abi.encodeCall(
            IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox,
            (uint32(1), 1 ether, uint16(305), word, symbol)
        ));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.etch(address(game), facade);
        assertTrue(ok, "automatic WWXRP resolution must remain live");
        bytes32 spinTopic = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != spinTopic) continue;
            (, uint256 packed, uint256 payout,) = abi.decode(logs[i].data, (uint64,uint256,uint256,uint256));
            uint8 score = uint8(packed >> 64);
            uint32 ticket = uint32(packed);
            uint256 drawSeed = Ref.drawWord(word, true);
            uint32 honestReel = Ref.traits(uint256(keccak256(abi.encode(drawSeed, uint256(0x446567656e526573756c74)))));
            (uint8 honestScore, uint8 honestWilds) = Ref.score(ticket, honestReel);
            (, uint8 wilds) = Ref.score(ticket, uint32(packed >> 32));
            assertLe(score, 9, "score outside valid range");
            assertGe(score, honestScore, "rig lowered honest score");
            assertLe(score, honestScore + 1, "rig lifted score by more than one");
            assertEq(wilds, honestWilds, "rig changed the house wild count");
            if (score == 9) assertEq(honestScore, 9, "rig manufactured the jackpot");
            if (score < 3) assertEq(payout, 0, "automatic payout below score floor");
            assertEq(abi.decode(result, (uint256)), payout, "returned payout differs from event");
            found = true;
        }
        assertTrue(found, "automatic WWXRP resolver emitted no spin");
    }

    // ---- helpers ----

    function _roiBps(uint256 score) internal pure returns (uint256 roiBps) {
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

    function _firstSpin() internal returns (uint8 score, uint8 wilds) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == DQ.RESOLVED_SIG) {
                (,, bytes memory spins) = abi.decode(logs[i].data, (uint256, uint32, bytes));
                (, score, wilds) = DQ.spinAt(spins, 0);
                return (score, wilds);
            }
        }
        revert("no DegeneretteResolved");
    }

    function _resultTicketForSpin(uint48 index, uint256 word, uint8 spinIdx) internal pure returns (uint32) {
        uint256 resultSeed = spinIdx == 0
            ? uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)))
            : uint256(keccak256(abi.encodePacked(word, uint32(index), spinIdx, QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
        // The day itself is sealed (dailyIdx = today, tickets drained), as after a mid-day request:
        // the delivered cohort's read consumers are the engine's only work.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }
}
