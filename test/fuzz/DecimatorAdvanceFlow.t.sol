// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";

/// @dev Seed purchase history only. The production engine must set turbo, promote the level,
///      lock/request/apply RNG, consolidate/seal, generate entries, unlock and pay originals.
contract DecimatorPurchaseSeeder is BucketSeed {
    function seed(bool fast) external {
        uint24 day = _simulatedDayIndex();
        // The seeded buckets represent minted tickets through purchase level 5.
        // Retire their already-consumed genesis queues before the circular keys are reused.
        TQ.retireCompleted(address(this), 5);
        level = 4;
        dailyIdx = day - 1;
        purchaseStartDay = day - (fast ? 1 : 3);
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        humanReadComplete = true;
        _afkingResetDay = day;
        _setRngComplete(true);
        _setPrizePools(500 ether, 100 ether);
        levelPrizePool[3] = 350 ether;
        levelPrizePool[4] = 400 ether;
        _setDecWindowOpen(true);
        decBattleRounds[5].openedDay = day;
        for (uint256 trait; trait < 256; ++trait) _seedBucket(5, uint8(trait), address(0xA100), 1);
    }
}

contract DecimatorAdvanceFlowTest is DeployProtocol {
    DegenerusGameLens private lens;
    uint256 private constant WORD = 777;
    uint24 private constant DAY = 20;
    bytes32 private constant GENERATED = keccak256("DecimatorGenerated(uint24,uint64,uint32,uint8,uint32,uint256,uint256)");
    bytes32 private constant RUN = keccak256("DecimatorRun(uint24,uint64,uint256)");
    bytes32 private constant SEALED = keccak256("DecimatorResolved(uint24,uint256,uint256,uint64)");

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000e18);
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY + DAY - 1) * 1 days + 82_621);
        lens = new DegenerusGameLens();
    }

    function test_PublicMinerDrivesFastClosingJackpotAndOriginals() public { _flow(true); }
    function test_PublicMinerDrivesSlowClosingJackpotAndOriginals() public { _flow(false); }

    function _flow(bool fast) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(DecimatorPurchaseSeeder).runtimeCode);
        DecimatorPurchaseSeeder(address(game)).seed(fast);
        vm.etch(address(game), code);
        vm.deal(address(game), 600 ether);
        vm.prank(address(0xA100));
        crapsBattle.setPreferredBoard(0, 3);
        for (uint160 i = 1; i <= 40; ++i) {
            address player = address(0xD000 + i);
            vm.prank(address(game)); coin.mintForGame(player, 2000);
            vm.prank(player); coin.decimatorBurn(0, 2000, 0);
        }
        assertFalse(game.rngLocked());
        assertEq(lens.decBattleRoundOf(address(game), 5).phase, 0);
        uint256 generatedReceipts;
        uint256 seals;
        uint256 requests;
        uint24 closingDay;
        bool originalsRan;
        // Slow closure needs its purchase day, then its one closing jackpot day.
        for (uint256 day; day < 2; ++day) {
            uint256 beforeRequest = mockVRF.lastRequestId();
            for (uint256 calls; mockVRF.lastRequestId() == beforeRequest; ++calls) {
                assertLt(calls, 1000, "public request stalled");
                game.mineFlip{gas: 10_000_000}(0);
            }
            ++requests;
            assertTrue(game.rngLocked());
            mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD + day);
            for (uint256 calls; calls < 1000; ++calls) {
                vm.recordLogs();
                game.mineFlip{gas: 10_000_000}(0);
                Vm.Log[] memory logs = vm.getRecordedLogs();
                for (uint256 i; i < logs.length; ++i) {
                    if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
                    if (logs[i].topics[0] == SEALED) {
                        ++seals;
                        closingDay = uint24(DAY + day);
                        (uint256 word,,) = abi.decode(logs[i].data, (uint256,uint256,uint64));
                        assertEq(word, WORD + day);
                    }
                    if (logs[i].topics[0] == GENERATED) ++generatedReceipts;
                    if (logs[i].topics[0] == RUN) {
                        originalsRan = true;
                        assertEq(lens.decJackpotPlanOf(address(game), 5).cursor,
                            Sample.count(uint256(lens.decBattleRoundOf(address(game), 5).count) +
                                lens.decJackpotPlanOf(address(game), 5).generatedEntries), "all generated strata finish before originals");
                    }
                }
                DegenerusGameStorage.DecJackpotPlan memory p = lens.decJackpotPlanOf(address(game), 5);
                DegenerusGameStorage.DecBattleRound memory r = lens.decBattleRoundOf(address(game), 5);
                if (p.mode == 2 && p.cursor < Sample.count(uint256(r.count) + p.generatedEntries)) {
                    assertTrue(game.rngLocked());
                    assertEq(r.cursor, 0);
                }
                if (r.phase == 3) break;
                if (!game.rngLocked() && r.phase == 0) break;
                assertLt(calls, 999, "closing daily or original settlement stalled");
            }
            if (lens.decBattleRoundOf(address(game), 5).phase == 3) break;
            vm.warp(block.timestamp + 1 days);
        }
        DegenerusGameStorage.DecJackpotPlan memory plan = lens.decJackpotPlanOf(address(game), 5);
        DegenerusGameStorage.DecBattleRound memory round = lens.decBattleRoundOf(address(game), 5);
        assertEq(requests, fast ? 1 : 2);
        assertEq(seals, 1);
        assertEq(round.phase, 3);
        assertGt(plan.generatedEntries, 0);
        uint256 expectedReceipts;
        uint256 sealedWord = fast ? WORD : WORD + 1;
        uint256 field = uint256(round.count) + plan.generatedEntries;
        uint16 survivors = Sample.count(field);
        for (uint256 i; i < survivors; ++i) {
            if (Sample.at(sealedWord, 5, field, i) > round.count) ++expectedReceipts;
        }
        assertEq(generatedReceipts, expectedReceipts);
        assertEq(plan.cursor, survivors);
        assertEq(round.cursor, survivors);
        assertTrue(originalsRan);
        assertFalse(game.rngLocked());
        assertEq(game.rngWordForDay(closingDay), fast ? WORD : WORD + 1);
        assertEq(game.level(), 5);
        assertLe(round.winners, (uint256(round.count) + plan.generatedEntries) / 2);
    }
}
