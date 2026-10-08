// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecimatorJackpotHarness} from "../fuzz/DecimatorJackpotIntegration.t.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DecimatorJackpotTerms} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

contract DecimatorGasCoinflip {
    mapping(uint32 => uint256) public credited;
    function creditFlip(uint32 owner, uint256 amount) external { credited[owner] += amount; }
}

contract DecimatorGeneratedEngineMeter {
    function run(bytes32 seed) external view returns (uint256 used, uint256 rolls) {
        uint256 start = gasleft();
        Craps.SlipResult memory r = CrapsEngine(ContractAddresses.CRAPS_ENGINE).settleSlipBounded(
            3 | 3 << 9 | 1 << 24, 60, uint256(keccak256(abi.encode("board", seed))), 3,
            seed, 1e45, 0xD1CE, 0x050c, (511 << 16) | 48);
        return (start - gasleft(), r.totalRolls);
    }
}

contract DecimatorGeneratedFlatEngine {
    function settleSlipBounded(uint256, uint256, uint256, uint256, bytes32,
        uint256 bankroll, uint256, uint256, uint256) external pure returns (Craps.SlipResult memory r)
    { r.peakBankroll = bankroll; }
}

/// @dev Measure inside an external frame so isolation's transaction refunds do not skew subtraction.
contract DecimatorGeneratedWorkMeter {
    function daily(DecimatorGasHost host, uint256 word, uint256 allowance)
        external returns (uint256 used, MineFlipGas.Result memory result)
    {
        uint256 start = gasleft();
        result = host.daily(5, word, allowance);
        used = start - gasleft();
    }

    function run(DecimatorGasHost host, DecimatorJackpotTerms calldata terms, uint256 allowance)
        external returns (uint256 used, MineFlipGas.Result memory result)
    {
        uint256 start = gasleft();
        (result,) = host.runDecimatorJackpotAwards(terms, allowance);
        used = start - gasleft();
    }
}

contract DecimatorGasHost is DecimatorJackpotHarness, BucketSeed {
    function primeMiner(bool activePass) external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day - 1;
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        _recordDailyRng(day, rngWordCurrent);
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _seedWallet(msg.sender);
        if (activePass) mintPacked_[_walletIdOf(msg.sender)] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }
    function idOf(address who) external view returns (uint32) { return _walletIdOf(who); }
    function seedRecipients(uint256 n) external {
        for (uint8 q; q < 4; ++q) {
            deityBySymbol[q * 8] = 0;
            for (uint256 i; i < n; ++i) _seedBucket(5, q * 64, address(uint160(0xb000 + q * n + i)), 1);
        }
    }
    function mine() external returns (uint256 actualBasefee) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_MINER_MODULE.delegatecall(
            abi.encodeCall(DegenerusGameMinerModule.mineFlip, (uint32(0))));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return block.basefee;
    }
    function readySoloWithGoldBuckets() external {
        jackpotWork.traits = 0xf8b87838;
        for (uint8 q; q < 4; ++q) {
            deityBySymbol[q * 8] = 0;
            _seedBucket(5, q * 64 + 56, address(uint160(0xc000 + q)), 1);
            _seedBucket(5, q * 64 + 56, address(uint160(0xd000 + q)), 1);
        }
        decJackpotPlans[5].cursor = Sample.count(uint256(decBattleRounds[5].count) + decJackpotPlans[5].generatedEntries);
    }
    function gold() external view returns (uint256) { return goldenTicket; }
    /// @dev Scale setup bypasses a million burns: count/aggregate are set by prepare, and
    ///      only sampled natural records are materialized. All settlement code is production.
    function seedSampledOriginals(uint256 word, uint40 generated) external {
        uint256 n = decBattleRounds[5].count;
        uint256 total = n + generated;
        for (uint256 i; i < Sample.count(total); ++i) {
            uint64 id = Sample.at(word, 5, total, i);
            if (id <= n) {
                _storeDecEntry(5, uint64(id),
            (uint256(2000) << 62) | _seedWallet(address(uint160(0x1000 + id))));
            }
        }
    }
    function lastEntry() external { decJackpotPlans[5].cursor = 999; }

    function seedFillingHeap() external {
        decBattleRounds[5].winners = 199;
        for (uint256 i; i < 199; ++i) {
            decBattleHeap[i] = ((uint256(2000 * 3000e18) + i + 1) << 64) | (i + 1);
        }
        delete decBattleHeap[199];
    }

    function seedTiedOwnerHeap(uint256 word) external {
        seedTiedHeap(word);
        decBattleRounds[5].winners = 200;
    }

    function seedTiedHeap(uint256 word) private {
        uint256[200] memory keys;
        for (uint256 i; i < 200; ++i) {
            uint64 id = uint64(i + 1);
            uint256 key = (uint256(keccak256(abi.encode(keccak256("decimator.battle.tie.v1"), word, uint24(5), id)))
                & ~uint256(type(uint64).max)) | id;
            uint256 at = i;
            while (at != 0 && keys[at - 1] > key) { keys[at] = keys[at - 1]; --at; }
            keys[at] = key;
        }
        for (uint256 i; i < 200; ++i) decBattleHeap[i] = (uint256(2000 * 3000e18) << 64) | uint64(keys[i]);
    }
}

contract DecimatorJackpotGasTest is Test {
    DecimatorGasHost private h;
    DecimatorGeneratedWorkMeter private workMeter;
    mapping(uint64 => bool) private seen;
    bytes32 private constant WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 2 days);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, type(DecimatorGasHost).runtimeCode);
        vm.etch(ContractAddresses.GAME_MINER_MODULE, type(DegenerusGameMinerModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, type(DegenerusGameAdvanceModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, type(DegenerusGameJackpotModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_DECIMATOR_MODULE, type(DegenerusGameDecimatorModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, type(DegenerusGameWhaleModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(DegenerusGameTicketModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, type(DegenerusGameFoilPackModule).runtimeCode);
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        vm.etch(ContractAddresses.CRAPS, type(CrapsBattle).runtimeCode);
        vm.etch(ContractAddresses.COINFLIP, type(DecimatorGasCoinflip).runtimeCode);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.STETH_TOKEN, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
        h = DecimatorGasHost(ContractAddresses.GAME);
        h.seedProtocolWallets();
        vm.etch(address(0xDEC18), type(DecimatorGeneratedWorkMeter).runtimeCode);
        workMeter = DecimatorGeneratedWorkMeter(address(0xDEC18));
    }

    function test_FullMatchEightThousandThroughRealMiner() public {
        _campaign(8000, false, 0);
    }

    function test_FullMatchThousandThroughRealMiner() public {
        _campaign(1000, false, 0);
    }

    function test_ScaleFullMatchTenThousand() public { _campaign(10_000, false, 0); }
    function test_ScaleFullMatchHundredThousand() public { _campaign(100_000, false, 0); }
    function test_ScaleFullMatchMillion() public { _campaign(1_000_000, false, 0); }

    function test_ColdPlanInitializationFitsAdmission() public {
        uint256 word = 2;
        while (Sample.at(word, 5, 16000, 0) <= 8000) ++word;
        h.prepare(5, 8000, 140 ether, 1000 ether, word, false);
        h.seedRecipients(250);
        for (uint8 q; q < 4; ++q) h.setDeity(q, address(uint160(0xa100 + q)));
        DecimatorJackpotTerms memory terms;
        terms.word = word;
        terms.shares = [uint256(133.3 ether), 133.3 ether, 133.4 ether, 600 ether];
        terms.targets = [uint16(256), 128, 32, 1];
        terms.solo = 3;
        vm.cool(address(h));
        (uint256 used, MineFlipGas.Result memory r) = workMeter.run(h, terms,
            GasBounds.DECIMATOR_PLAN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 20_000);
        assertTrue(r.progressed);
        assertFalse(r.done);
        assertEq(h.plan(5).cursor, 0);
        assertEq(h.plan(5).generatedEntries, 8000);
        assertEq(h.round(5).poolWei, 280 ether);
        assertLt(used, GasBounds.DECIMATOR_PLAN_GAS_MAX);
        emit log_named_uint("cold plan initialization and worker frame", used);
    }

    function test_ColdSoloPassAndGoldResumeFitExistingAdmission() public {
        h.prepare(5, 8000, 140 ether, 1000 ether, 6, false);
        h.daily(5, 6, 1_000_000);
        h.readySoloWithGoldBuckets();
        // Only the solo remains. Search the first admitted allowance from identical cold state.
        uint256 low = 350_000;
        uint256 high = 600_000;
        while (high - low > 1) {
            uint256 snap = vm.snapshotState();
            uint256 allowance = (low + high) / 2;
            _coolSolo();
            (, MineFlipGas.Result memory r) = workMeter.daily(h, 6, allowance);
            if (r.done) high = allowance;
            else {
                low = allowance;
                assertFalse(r.progressed);
                assertEq(h.gold(), 0);
                assertEq(h.paid(), 140 ether);
                for (uint160 q; q < 4; ++q) {
                    assertEq(h.passes(address(0xc000 + q)), 0);
                    assertEq(h.passes(address(0xd000 + q)), 0);
                }
            }
            assertTrue(vm.revertToStateAndDelete(snap));
        }
        _coolSolo();
        (uint256 refusedFrame, MineFlipGas.Result memory refused) = workMeter.daily(h, 6, low);
        assertFalse(refused.progressed);
        _coolSolo();
        vm.recordLogs();
        (uint256 used, MineFlipGas.Result memory result) = workMeter.daily(h, 6, high);
        assertTrue(result.done);
        uint256 passEvents;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("JackpotWhalePassWin(uint32,uint256,uint8)")) ++passEvents;
        }
        assertEq(passEvents, 1, "checkpoint awards the solo pass once");
        uint256 passes;
        uint256 cash;
        for (uint160 q; q < 4; ++q) {
            passes += h.passes(address(0xc000 + q)) + h.passes(address(0xd000 + q));
            cash += h.balance(address(0xc000 + q)) + h.balance(address(0xd000 + q));
        }
        assertEq(passes, 66);
        assertEq(cash, 451.5 ether);
        assertTrue((h.gold() >> 189) & 1 != 0);
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 408.5 ether); // passes 148.5 + unpaid surplus 260
        assertEq(reserved, 731.5 ether);
        // Subtract identical cold planning/admission that refuses the award. The difference
        // includes pass/cash/gold AND the subsequent accounting/completion tail.
        assertLt(used - refusedFrame, GasBounds.JACKPOT_ETH_WINNER_GAS_MAX + 160_000);
        emit log_named_uint("cold solo cash/pass/gold and daily completion frame", used);
        emit log_named_uint("solo award plus completion beyond refused frame", used - refusedFrame);
        emit log_named_uint("first admitted solo resume allowance", high);
    }

    function _coolSolo() private {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_DECIMATOR_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
    }

    function test_SkippedNaturalStratumFitsSmallAllowanceAndGeneratedWaits() public {
        uint256 word = 2;
        while (Sample.at(word, 5, 16000, 0) > 8000 || Sample.at(word, 5, 16000, 1) <= 8000) ++word;
        h.prepare(5, 8000, 140 ether, 1000 ether, word, false);
        h.seedRecipients(250);
        h.daily(5, word, 1_000_000);
        DecimatorGasHost.DecJackpotPlan memory p = h.plan(5);
        p.cursor = 0;
        h.seedPlan(5, p);
        DecimatorJackpotTerms memory terms;
        terms.word = word;
        vm.cool(address(h)); vm.cool(ContractAddresses.CRAPS);
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("preferredBoardOf(uint32)"), hex"12345678");
        vm.recordLogs();
        (uint256 used, MineFlipGas.Result memory r) = workMeter.run(h, terms, 150_000);
        assertEq(vm.getRecordedLogs().length, 0, "natural strata do not emit generated receipts");
        assertTrue(r.progressed);
        assertFalse(r.done);
        assertEq(h.plan(5).cursor, 1, "natural stratum skipped below generated admission");
        assertEq(h.ownerSlot(1), address(0), "natural stratum does not store a generated owner");
        vm.cool(address(h));
        uint256 refusedFrame;
        (refusedFrame, r) = workMeter.run(h, terms, 150_000);
        assertFalse(r.progressed);
        assertEq(h.plan(5).cursor, 1, "survivor waits atomically");
        assertLt(used, GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS);
        assertLt(used - refusedFrame, GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX);
        emit log_named_uint("cold skipped natural stratum and worker frame", used);
        emit log_named_uint("incremental skipped stratum gas", used - refusedFrame);
    }

    function test_ScaleItemCeilingsKeepGeneratedAdmission() public {
        uint40[4] memory ns = [uint40(1000),10_000,100_000,1_000_000];
        uint256[4] memory words = [uint256(765),228,346,347];
        uint256 engine = _engineCeiling();
        uint256 clean = vm.snapshotState();
        for (uint256 k; k < ns.length; ++k) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            uint256 word = words[k];
            uint40 n = ns[k];
            uint64 id = Sample.at(word, 5, uint256(n) * 2, 999);
            assertGt(id, n);
            assertGt(id - n, uint256(n) * 384 / 416, "last non-solo bucket exercises cumulative allocation");
            for (uint160 i; i < 1000; ++i) {
                vm.prank(address(0xb000 + i));
                CrapsBattle(ContractAddresses.CRAPS).setPreferredBoard(0, 3 << 27 | 3 << 9 | 1 << 24);
            }
            h.prepare(5, n, 140 ether, 1000 ether, word, false);
            h.seedRecipients(250);
            DecimatorJackpotTerms memory terms;
            terms.word = word;
            terms.shares = [uint256(133.3 ether),133.3 ether,133.4 ether,600 ether];
            terms.targets = [uint16(256),128,32,1];
            terms.solo = 3;
            h.runDecimatorJackpotAwards(terms, 180_000);
            assertEq(h.plan(5).generatedEntries, n);
            h.lastEntry();
            h.seedTiedOwnerHeap(word);
            vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorGeneratedFlatEngine).runtimeCode);
            _coolGenerated();
            (uint256 refused, MineFlipGas.Result memory wait) = workMeter.run(h, terms, 70_000);
            assertFalse(wait.progressed);
            _coolGenerated();
            uint256 snap = vm.snapshotState();
            (uint256 frame, MineFlipGas.Result memory run) = workMeter.run(h, terms,
                GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000);
            assertTrue(run.done);
            assertEq(h.plan(5).cursor, 1000);
            assertEq(h.round(5).winners, 200);
            assertTrue(h.ownerSlot(id - n) != address(0));
            assertTrue(vm.revertToStateAndDelete(snap));
            h.seedFillingHeap();
            _coolGenerated();
            (uint256 fillingFrame,) = workMeter.run(h, terms,
                GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000);
            assertEq(h.round(5).winners, 200);
            assertEq(uint64(h.node(0)), id);
            if (fillingFrame > frame) frame = fillingFrame;
            // The identical refused frame measures sampling/dispatch before admission.
            // Its subtraction leaves the indivisible generated item and its completion;
            // adding the whole cold 511-roll engine call remains conservative (flat call retained).
            uint256 item = frame - refused + engine;
            assertLt(item, GasBounds.DECIMATOR_GENERATED_GAS_MAX);
            assertLt(frame + engine, GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS);
            emit log_named_uint("scale item original count", n);
            emit log_named_uint("scale largest generated item ceiling", item);
            emit log_named_uint("scale cold item including worker frame ceiling", frame + engine);
        }
    }

    function _coolGenerated() private {
        vm.cool(address(h)); vm.cool(ContractAddresses.CRAPS); vm.cool(ContractAddresses.CRAPS_ENGINE);
    }

    function _engineCeiling() private returns (uint256 engine) {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        address meterAddress = address(0xDEC17);
        vm.etch(meterAddress, type(DecimatorGeneratedEngineMeter).runtimeCode);
        DecimatorGeneratedEngineMeter meter = DecimatorGeneratedEngineMeter(meterAddress);
        uint256 witnesses;
        for (uint256 i; i < 400 && witnesses < 4; ++i) {
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            (uint256 used, uint256 rolls) = meter.run(keccak256(abi.encode("ceiling", i)));
            if (rolls == 511) {
                ++witnesses;
                if (used > engine) engine = used;
            }
        }
        assertGt(witnesses, 0);
        emit log_named_uint("cold 511-roll engine ceiling", engine);
    }

    function test_FullMatchActivePassAndEscalatedRate() public {
        _campaign(8000, true, 2 hours);
    }

    function _campaign(uint40 originals, bool activePass, uint256 delay) private {
        uint32[8] memory boards = [uint32(0),1,2,3,3 | 1 << 9,3 << 27 | 2 << 9,3 | 3 << 9,3 | 3 << 9 | 1 << 24];
        for (uint160 i; i < 1000; ++i) {
            vm.prank(address(0xb000 + i));
            CrapsBattle(ContractAddresses.CRAPS).setPreferredBoard(0, boards[i % 8]);
        }
        h.prepare(5, originals, 140 ether, 1000 ether, 777, false);
        h.seedSampledOriginals(777, originals);
        h.seedRecipients(250);
        h.primeMiner(activePass);
        vm.warp(block.timestamp + delay);
        uint256 lockedGas;
        uint256 unlockedGas;
        uint256 lockedCalls;
        uint256 unlockedCalls;
        uint256 totalReward;
        uint256 maxCall;
        uint256 receivedEntries;
        uint256 naturalRuns;
        uint256 observedBasefee;
        for (uint256 i; h.queue() != 0 && i < 1000; ++i) {
            bool locked = h.rngLocked();
            vm.cool(address(h)); vm.cool(ContractAddresses.CRAPS); vm.cool(ContractAddresses.CRAPS_ENGINE);
            vm.recordLogs();
            vm.fee(1 gwei);
            uint256 beforeGas = gasleft();
            uint256 actualBasefee = h.mine{gas: 10_000_000}();
            observedBasefee = actualBasefee;
            uint256 used = beforeGas - gasleft();
            if (used > maxCall) maxCall = used;
            if (locked) { lockedGas += used; ++lockedCalls; }
            else { unlockedGas += used; ++unlockedCalls; }
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool metered;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] == keccak256("DecimatorGenerated(uint24,uint64,uint32,uint8,uint32,uint256,uint256)")
                    || logs[j].topics[0] == keccak256("DecimatorRun(uint24,uint64,uint256)")) {
                    uint64 id = uint64(uint256(logs[j].topics[2]));
                    assertFalse(seen[id], "no survivor runs twice");
                    seen[id] = true;
                    assertTrue(Sample.contains(777, 5, uint256(originals) * 2, id));
                    if (id <= originals) ++naturalRuns;
                }
                if (logs[j].topics[0] == keccak256("DecimatorGenerated(uint24,uint64,uint32,uint8,uint32,uint256,uint256)")) {
                    (uint8 q,,,) = abi.decode(logs[j].data, (uint8,uint32,uint256,uint256));
                    uint64 id = uint64(uint256(logs[j].topics[2]));
                    uint256 index = uint256(keccak256(abi.encode(keccak256("decimator.battle.generated.recipient.v1"), uint256(777), uint24(5), id, q, uint8(q * 64)))) % 250;
                    assertEq(h.keyOf(uint32(uint256(logs[j].topics[3]))), address(uint160(0xb000 + uint256(q) * 250 + index)));
                    ++receivedEntries;
                }
                if (logs[j].topics[0] != WORK) continue;
                (, uint256 executionGas, uint256 reward) = abi.decode(logs[j].data, (uint8,uint256,uint256));
                uint256 bps = delay == 0 ? 3000 : 21000;
                if (locked) bps *= 2;
                if (activePass) bps *= 2;
                // Foundry isolation uses zero basefee in these child transactions.
                // Also run without isolation to verify the nonzero vm.fee bounty.
                uint256 cap = delay == 0 ? 0.5 gwei : 8 gwei;
                uint256 rate = actualBasefee < cap ? actualBasefee : cap;
                uint256 expected = executionGas <= 1_000_000 ? 0
                    : (executionGas - 1_000_000) * rate * 1000 * bps / (0.02 ether * 10_000);
                if (rate != 0 && executionGas > 1_000_000 && expected == 0) expected = 1;
                assertEq(reward, expected, "production Miner reward policy");
                totalReward += reward;
                metered = true;
            }
            assertTrue(metered);
        }
        assertEq(h.queue(), 0);
        assertEq(h.plan(5).cursor, 1000);
        assertEq(h.plan(5).generatedEntries, originals);
        uint256 expectedEntries;
        for (uint256 i; i < 1000; ++i) {
            uint64 id = Sample.at(777, 5, uint256(originals) * 2, i);
            assertTrue(seen[id]);
            if (id > originals) ++expectedEntries;
        }
        assertEq(receivedEntries, expectedEntries);
        assertEq(naturalRuns + receivedEntries, 1000);
        assertEq(h.round(5).cursor, 1000);
        assertEq(h.round(5).winners, 200);
        assertEq(DecimatorGasCoinflip(ContractAddresses.COINFLIP).credited(h.idOf(address(this))), totalReward);
        emit log_named_uint("original and generated count each", originals);
        emit log_named_uint("sampled generated runs", receivedEntries);
        emit log_named_uint("sampled natural runs", naturalRuns);
        emit log_named_uint("total settlement gas", lockedGas + unlockedGas);
        emit log_named_uint("locked-at-start total gas", lockedGas);
        emit log_named_uint("locked-at-start calls (10M supplied)", lockedCalls);
        emit log_named_uint("unlocked-at-start total gas", unlockedGas);
        emit log_named_uint("unlocked-at-start calls (10M supplied)", unlockedCalls);
        emit log_named_uint("largest external call gas incl wrapper", maxCall);
        emit log_named_uint("whole FLIP bounty credited", totalReward);
        emit log_named_uint("actual transaction basefee wei", observedBasefee);
    }

}
