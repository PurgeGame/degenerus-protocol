// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BafStageHost, BafBracketFixture} from "../helpers/BafStageHost.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @title BafStagedSkip — a losing daily flip arms no BAF award stage.
/// @notice At an x0 consolidation whose word has bit 0 clear, the bracket is marked skipped
///         (and on x00 the incinerator resolves) inside the consolidation transaction; no
///         kind-7 record is armed and no BAF ETH is reserved; the bracket keeps its frozen scores
///         for the consolation (no `finalizeBaf`); the next daily-phase call is the jackpot daily
///         (stage 10), never the BAF award stage (19).
contract BafStagedSkipTest is BafBracketFixture {
    uint256 private constant LOSING_WORD = uint256(keccak256("baf-staged-skip")) & ~uint256(1);
    uint256 private constant ALLOWANCE = 9_500_000;
    uint8 private constant STAGE_ENTERED_JACKPOT = 7;
    uint8 private constant STAGE_JACKPOT_DAILY_STARTED = 10;
    bytes32 private constant SKIPPED_SIG = keccak256("BafSkipped(uint24,uint24)");
    bytes32 private constant SETTLED_SIG =
        keccak256("PoolsSettled(uint24,uint24,uint24,uint256,uint256,uint256,uint256,uint256,uint256)");
    address private constant SCORER = address(0x5C0BE);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 40 days);
    }

    function test_X0LosingFlipSkipsWithoutAStage() public {
        _checkSkip(20);
    }

    function test_X00LosingFlipResolvesTheIncineratorInTheConsolidation() public {
        _checkSkip(100);
    }

    function _checkSkip(uint24 lvl) private {
        _hostAt(lvl, LOSING_WORD, false);
        host.seedPools(40 ether, 200 ether, 0, lvl - 1, 35 ether);
        vm.deal(address(game), address(game).balance + 400 ether);
        vm.prank(ContractAddresses.COINFLIP);
        jackpots.recordBafFlip(SCORER, lvl, 5_000 ether);
        (uint64 epoch0,,,) = _bracketBoard(lvl);

        if (lvl % 100 == 0) {
            vm.expectCall(address(wwxrp), abi.encodeCall(WWXRP.resolveIncinerator, (lvl, LOSING_WORD)), 1);
        }
        vm.recordLogs();
        MineFlipGas.Result memory r = host.daily{gas: 30_000_000}(ALLOWANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(r.progressed && r.done, "consolidation completes");
        assertTrue(game.jackpotPhase(), "the jackpot phase opened");

        bool skipped;
        bool settled;
        uint8[] memory stages = _stages(logs, lvl);
        assertEq(stages.length, 1);
        assertEq(stages[0], STAGE_ENTERED_JACKPOT, "consolidation marker");
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].topics.length == 0) continue;
            bytes32 sig = logs[j].topics[0];
            if (logs[j].emitter == address(jackpots) && sig == SKIPPED_SIG) {
                assertEq(uint256(logs[j].topics[1]), lvl, "the bracket skipped");
                skipped = true;
            }
            if (logs[j].emitter == address(game) && sig == SETTLED_SIG) {
                (,,,,,,, uint256 claimableDelta) =
                    abi.decode(logs[j].data, (uint24, uint24, uint256, uint256, uint256, uint256, uint256, uint256));
                // x00 also seals the Decimator from the same settlement; x0 has no other claimable leg.
                if (lvl % 100 != 0) assertEq(claimableDelta, 0, "a skip reserves no BAF ETH");
                settled = true;
            }
            if (logs[j].emitter == address(game)) {
                assertTrue(sig != ETH_SIG && sig != TICKET_SIG && sig != WHALE_SIG, "no BAF award on a losing flip");
            }
        }
        assertTrue(skipped, "markBafSkipped ran in the consolidation transaction");
        assertTrue(settled, "pools settled in the same transaction");
        assertEq(jackpots.getLastBafResolvedDay(), game.currentDayView(), "the skip records the resolution day");

        BafStageHost.WorkView memory w = host.workView();
        assertEq(w.kind, 0, "no award record armed");
        assertEq(w.paid, 0);
        assertEq(w.traits, 0);

        // The skipped bracket keeps its scores (no finalizeBaf): the consolation stays claimable.
        (uint64 epoch1,, bool skippedFlag,) = _bracketBoard(lvl);
        assertEq(epoch1, epoch0, "no epoch bump on a skip");
        assertTrue(skippedFlag, "the bracket is marked skipped");
        assertEq(jackpots.bafConsolationOf(SCORER, lvl), 5 ether, "frozen score stays claimable as consolation");

        vm.recordLogs();
        r = host.daily{gas: 30_000_000}(ALLOWANCE);
        stages = _stages(vm.getRecordedLogs(), lvl);
        assertTrue(r.progressed, "the next call does daily work");
        assertGt(stages.length, 0);
        assertEq(stages[0], STAGE_JACKPOT_DAILY_STARTED, "the next call is the jackpot daily");
        for (uint256 k; k < stages.length; ++k) assertTrue(stages[k] != STAGE_BAF, "no BAF award stage");
    }

    function _stages(Vm.Log[] memory logs, uint24 lvl) private view returns (uint8[] memory stages) {
        uint256 count;
        stages = new uint8[](logs.length);
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
            if (logs[j].topics[0] != ADVANCE_SIG) continue;
            (uint8 stage, uint24 at) = abi.decode(logs[j].data, (uint8, uint24));
            assertEq(at, lvl);
            stages[count++] = stage;
        }
        assembly ("memory-safe") { mstore(stages, count) }
    }
}
