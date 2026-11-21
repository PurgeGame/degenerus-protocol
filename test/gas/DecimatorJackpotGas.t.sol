// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {ProfileModules} from "../helpers/ProfileModules.sol";

import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {DecimatorJackpotHarness} from "../fuzz/DecimatorJackpotIntegration.t.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {GameMiner} from "../../contracts/modules/GameMiner.sol";
import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {DegenerusGameEndgameModule} from "../../contracts/modules/DegenerusGameEndgameModule.sol";
import {DegenerusGameDailyModule} from "../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DecimatorJackpotTerms} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {GlamsterdamMeterReplay} from "../helpers/GlamsterdamMeterReplay.sol";

contract DecimatorGasCoinflip {
    mapping(uint32 => uint256) public credited;
    function creditFlip_g317(uint32 owner, uint256 amount) external { credited[owner] += amount; }
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
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }

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

    function work(DecimatorGasHost host, uint256 allowance)
        external returns (uint256 used, MineFlipGas.Result memory result)
    {
        uint256 start = gasleft();
        result = host.runDecimatorWork(allowance);
        used = start - gasleft();
    }
}

contract DecimatorGasHost is DecimatorJackpotHarness, BucketSeed, GameMiner {
    function primeMiner(bool activePass) external {
        uint24 day = _wallDay();
        dailyIdx = day;
        dailyComplete = false;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay();
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
        _mineFlip(0);
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
            uint256 key = (uint256(keccak256(abi.encode(uint256(50), word, uint256(id))))
                & ~uint256(type(uint64).max)) | id;
            uint256 at = i;
            while (at != 0 && keys[at - 1] > key) { keys[at] = keys[at - 1]; --at; }
            keys[at] = key;
        }
        for (uint256 i; i < 200; ++i) decBattleHeap[i] = (uint256(2000 * 3000e18) << 64) | uint64(keys[i]);
    }
}

contract DecimatorJackpotNativeViews {
    function redemptionSettlementPending_g153837() external pure returns (bool) { return false; }
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract DecimatorJackpotGasTest is GlamsterdamMeterReplay {
    uint256 private constant PLAN_FRAME_GAS = 20_000;

    DecimatorGasHost private h;
    DecimatorGeneratedWorkMeter private workMeter;
    mapping(uint64 => bool) private seen;
    bytes32 private constant WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");

    function setUp() public {
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1024);
        ProfileModules.installGame(vm);
        ProfileModules.installCraps(vm);
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 2 days);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, type(DecimatorGasHost).runtimeCode);
        // The selected profile helper installs all miner and worker dependencies.
        vm.etch(ContractAddresses.CRAPS, type(CrapsBattle).runtimeCode);
        vm.etch(ContractAddresses.COINFLIP, type(DecimatorGasCoinflip).runtimeCode);
        vm.etch(ContractAddresses.SDGNRS, type(DecimatorJackpotNativeViews).runtimeCode);
        vm.etch(ContractAddresses.STETH_TOKEN, type(DecimatorJackpotNativeViews).runtimeCode);
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(false));
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
        uint256 allowance = GasBounds.DECIMATOR_PLAN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + PLAN_FRAME_GAS;
        uint256 snap = vm.snapshotState();
        vm.cool(address(h));
        (uint256 used, MineFlipGas.Result memory r) = workMeter.run(h, terms, allowance);
        // Every write is a first change of a nonzero slot: the plan (mode 1), the round, the
        // packed current/claimable pools and the jackpot record, so no slot is created.
        (Priced memory g,) = _reprice(snap, address(workMeter), abi.encodeCall(workMeter.run, (h, terms, allowance)), used);
        assertTrue(r.progressed);
        assertFalse(r.done);
        assertEq(h.plan(5).cursor, 0);
        assertEq(h.plan(5).generatedEntries, 8000);
        assertEq(h.round(5).poolWei, 280 ether);
        assertLt(used, GasBounds.DECIMATOR_PLAN_GAS_MAX);
        emit log_named_uint("cold plan initialization and worker frame", used);
        _logPriced("cold plan initialization and worker frame", g, GasBounds.DECIMATOR_PLAN_GAS_MAX);
        uint256 resume = GasBounds.DECIMATOR_PLAN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000;
        emit log_named_uint("Jackpot resume admission", resume);
        assertEq(g.state, 0, "plan initialization creates no slot");
        assertLt(_glam(g), GasBounds.DECIMATOR_PLAN_GAS_MAX,
            "Glamsterdam plan initialization and worker frame fit DECIMATOR_PLAN_GAS_MAX");
        assertLt(_glam(g), resume,
            "Glamsterdam worker call fits the Jackpot resume admission DECIMATOR_PLAN + WORK_TAIL + 40k");
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
        // A cooled account is no longer touched; re-touch the host so the snapshot keeps its state.
        vm.deal(address(h), address(h).balance);
        uint256 beforeUsed = vm.snapshotState();
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
        _checkSoloGlamsterdam(refusedFrame, beforeUsed, high, used);
    }

    /// @dev Glamsterdam, no reservoir: the solo group (one winner, its passes and a fresh
    ///      golden-ticket arm) with the daily completion, against the composed admission at its
    ///      canRun site. The refused call's cold Osaka frame is subtracted: its own repricing can
    ///      only raise it, so the difference is an upper bound.
    function _checkSoloGlamsterdam(uint256 refusedFrame, uint256 beforeUsed, uint256 high, uint256 used) private {
        GlamsterdamReprice.Result memory g = _glamsterdamDaily(beforeUsed, high, used);
        uint256 unit = g.glamsterdamExec + g.stateGas - refusedFrame;
        uint256 bound = GasBounds.JACKPOT_ETH_WINNER_GAS_MAX + GasBounds.JACKPOT_ETH_FIRST_GROUP_GAS;
        emit log_named_uint("osaka solo unit", used - refusedFrame);
        emit log_named_uint("glamsterdam exec solo call", g.glamsterdamExec);
        emit log_named_uint("glamsterdam state solo call", g.stateGas);
        emit log_named_uint("glamsterdam new slots", g.newSlots);
        emit log_named_uint("glamsterdam total solo unit", unit);
        emit log_named_uint("glamsterdam bound (WINNER + FIRST_GROUP)", bound);
        emit log_named_uint("glamsterdam admission (WINNER + FIRST_GROUP + TAIL)", bound + GasBounds.JACKPOT_TAIL_GAS);
        assertLe(unit, bound + GasBounds.JACKPOT_TAIL_GAS,
            "Glamsterdam solo first group with completion fits WINNER + FIRST_GROUP + TAIL");
    }

    /// @dev Replays `workMeter.daily` from `pre` with state-diff recording and reprices the cold
    ///      figure from the replay's accesses; the post-call state is restored afterwards. The
    ///      recorded replay can run warmer than the cold call, so only its accesses are used.
    function _glamsterdamDaily(uint256 pre, uint256 allowance, uint256 osaka)
        private returns (GlamsterdamReprice.Result memory)
    {
        uint256 post = vm.snapshotState();
        assertTrue(vm.revertToState(pre));
        _coolSolo();
        vm.startStateDiffRecording();
        (uint256 replay, MineFlipGas.Result memory result) = workMeter.daily(h, 6, allowance);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        emit log_named_uint("recorded replay gas", replay);
        assertTrue(result.done, "the recorded replay completes the solo");
        bytes32 replayState = _touchedState(acc);
        assertTrue(vm.revertToState(post));
        assertEq(_touchedState(acc), replayState, "replay and cold call leave the same touched storage");
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm) || acc[i].account == address(this)) continue;
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                if (sa[j].isWrite && sa[j].previousValue == bytes32(0) && sa[j].newValue != bytes32(0)) {
                    emit log_named_bytes32("new slot", sa[j].slot);
                }
            }
            acc[n++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, n) }
        return GlamsterdamReprice.reprice(osaka, acc, address(workMeter));
    }

    function _touchedState(VmSafe.AccountAccess[] memory acc) private view returns (bytes32 digest) {
        for (uint256 i; i < acc.length; ++i) {
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                digest = keccak256(abi.encode(digest, sa[j].account, sa[j].slot, vm.load(sa[j].account, sa[j].slot)));
            }
        }
    }

    function _coolSolo() private {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_DECIMATOR_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
    }

    /// @dev Admits a skipped stratum and its tail with the worker frame, far below a generated item.
    uint256 private constant SKIP_ONLY_ALLOWANCE =
        GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 55_000;

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
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("extsload_g2807007(bytes32)"), hex"12345678");
        bytes memory payload = abi.encodeCall(workMeter.run, (h, terms, SKIP_ONLY_ALLOWANCE));
        vm.recordLogs();
        uint256 skipSnap = vm.snapshotState();
        (uint256 used, MineFlipGas.Result memory r) = workMeter.run(h, terms, SKIP_ONLY_ALLOWANCE);
        assertEq(vm.getRecordedLogs().length, 0, "natural strata do not emit generated receipts");
        assertTrue(r.progressed);
        assertFalse(r.done);
        assertEq(h.plan(5).cursor, 1, "natural stratum skipped below generated admission");
        assertEq(h.ownerSlot(1), address(0), "natural stratum does not store a generated owner");
        uint256 refusedSnap = vm.snapshotState();
        vm.cool(address(h));
        uint256 refusedFrame;
        (refusedFrame, r) = workMeter.run(h, terms, SKIP_ONLY_ALLOWANCE);
        // Both cold figures precede the first recording. The refusal changes nothing, so both
        // replays leave the skip's post-state.
        (Priced memory refused,) = _reprice(refusedSnap, address(workMeter), payload, refusedFrame);
        // The skip's cursor write is the plan slot's first change in the call.
        (Priced memory skip,) = _reprice(skipSnap, address(workMeter), payload, used);
        assertFalse(r.progressed);
        assertEq(h.plan(5).cursor, 1, "survivor waits atomically");
        assertLt(used, GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS);
        assertLt(used - refusedFrame, GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX);
        emit log_named_uint("cold skipped natural stratum and worker frame", used);
        emit log_named_uint("incremental skipped stratum gas", used - refusedFrame);
        _logPriced("skipped natural stratum and worker frame", skip,
            GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS);
        _logPriced("refused generated survivor frame", refused, 0);
        emit log_named_uint("Glamsterdam incremental skipped stratum", _glam(skip) - _glam(refused));
        assertLt(_glam(skip), GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS,
            "Glamsterdam skip and worker frame fit DECIMATOR_SAMPLE_SKIP + WORK_TAIL");
        assertLt(_glam(skip) - _glam(refused), GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX,
            "Glamsterdam incremental skipped stratum fits DECIMATOR_SAMPLE_SKIP_GAS_MAX");
    }

    /// @dev The original-run phase skips a generated stratum at the round's first stratum: its
    ///      cursor checkpoint creates the round's second slot (cursor, champion and next, zero
    ///      while no round is queued behind), the fresh-slot maximum behind this skip admission.
    function test_FirstSkippedStratumCreatesCursorSlot() public {
        uint256 word = 2;
        while (Sample.at(word, 5, 16000, 0) <= 8000 || Sample.at(word, 5, 16000, 1) > 8000) ++word;
        h.prepare(5, 8000, 140 ether, 1000 ether, word, false);
        h.seedRecipients(250);
        for (uint8 q; q < 4; ++q) h.setDeity(q, address(uint160(0xa100 + q)));
        h.primeMiner(false);
        DecimatorJackpotTerms memory terms;
        terms.word = word;
        terms.shares = [uint256(133.3 ether), 133.3 ether, 133.4 ether, 600 ether];
        terms.targets = [uint16(256), 128, 32, 1];
        terms.solo = 3;
        h.runDecimatorJackpotAwards(terms,
            GasBounds.DECIMATOR_PLAN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + PLAN_FRAME_GAS);
        assertEq(h.plan(5).generatedEntries, 8000);
        h.unlock();
        assertEq(h.round(5).cursor, 0);
        // The next stratum is an original run, so this allowance admits the skip alone.
        uint256 allowance = GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000;
        uint256 refusedSnap = vm.snapshotState();
        vm.cool(address(h));
        (uint256 refusedFrame, MineFlipGas.Result memory r) = workMeter.work(h, 50_000);
        assertFalse(r.progressed);
        uint256 skipSnap = vm.snapshotState();
        vm.cool(address(h));
        uint256 used;
        (used, r) = workMeter.work(h, allowance);
        assertTrue(r.progressed);
        assertEq(r.rewardBasis, 1, "the skip alone is admitted");
        assertEq(h.round(5).cursor, 1, "the generated stratum is skipped");
        // Both cold figures precede the first recording; the later snapshot replays first.
        (Priced memory skip,) = _reprice(skipSnap, address(workMeter), abi.encodeCall(workMeter.work, (h, allowance)), used);
        (Priced memory refused,) = _reprice(refusedSnap, address(workMeter),
            abi.encodeCall(workMeter.work, (h, uint256(50_000))), refusedFrame);
        uint256 admitted = GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS;
        emit log_named_uint("cold first skipped stratum and worker frame", used);
        emit log_named_uint("incremental skip and cursor checkpoint", used - refusedFrame);
        _logPriced("first skipped stratum and worker frame", skip, admitted);
        _logPriced("refused skip frame", refused, 0);
        emit log_named_uint("Glamsterdam incremental skip and cursor checkpoint", _glam(skip) - _glam(refused));
        assertEq(skip.state, 97_920, "the cursor checkpoint creates the round's second slot");
        assertLt(used - refusedFrame, admitted, "skip and cursor checkpoint fit SAMPLE_SKIP + WORK_TAIL");
        assertLt(_glam(skip) - _glam(refused), admitted,
            "Glamsterdam skip and fresh cursor checkpoint fit DECIMATOR_SAMPLE_SKIP + WORK_TAIL");
    }

    function test_ScaleItemCeilingsKeepGeneratedAdmission() public {
        _scaleItemCeilings(Pass(false, false));
    }

    /// @dev The same items repriced under Glamsterdam, every call recorded. Recording cannot change
    ///      a unit here: the item is the field's last stratum and the refusal is far below its bound.
    ///      The filling item creates its heap slot and its owner's ordinal slot, the fresh-slot
    ///      maximum of one generated item.
    function test_ScaleItemCeilingsGlamsterdam() public {
        _scaleItemCeilings(Pass(true, false));
    }

    function _scaleItemCeilings(Pass memory pass) private {
        uint40[4] memory ns = [uint40(1000),10_000,100_000,1_000_000];
        uint256[4] memory words = [uint256(25),2,6,29];
        (uint256 engine, uint256 engineSeed) = _engineCeiling();
        uint256[4] memory glamFrame;
        uint256[4] memory glamRefused;
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
            h.runDecimatorJackpotAwards(terms,
                GasBounds.DECIMATOR_PLAN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + PLAN_FRAME_GAS);
            assertEq(h.plan(5).generatedEntries, n);
            h.lastEntry();
            h.seedTiedOwnerHeap(word);
            vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorGeneratedFlatEngine).runtimeCode);
            _coolGenerated();
            (Priced memory refused, MineFlipGas.Result memory wait) = _work(terms, 70_000, pass);
            assertFalse(wait.progressed);
            _coolGenerated();
            uint256 snap = vm.snapshotState();
            (Priced memory frame, MineFlipGas.Result memory run) = _work(terms,
                GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000, pass);
            assertTrue(run.done);
            assertEq(h.plan(5).cursor, 1000);
            assertEq(h.round(5).winners, 200);
            assertTrue(h.ownerSlot(id - n) != address(0));
            assertTrue(vm.revertToStateAndDelete(snap));
            h.seedFillingHeap();
            _coolGenerated();
            (Priced memory filling,) = _work(terms,
                GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000, pass);
            assertEq(h.round(5).winners, 200);
            assertEq(uint64(h.node(0)), id);
            if (pass.glam) assertEq(filling.state, 2 * 97_920, "filling item creates its heap and owner slots");
            if (pass.glam) {
                _logPriced("scale generated item, replaced root", frame, 0);
                _logPriced("scale generated item, filling", filling, 0);
                _logPriced("scale refused generated frame", refused, 0);
            }
            (glamFrame[k], glamRefused[k]) = (_glam(frame) > _glam(filling) ? _glam(frame) : _glam(filling), _glam(refused));
            if (filling.osaka > frame.osaka) frame = filling;
            // The identical refused frame measures sampling/dispatch before admission.
            // Its subtraction leaves the indivisible generated item and its completion;
            // adding the whole cold 511-roll engine call remains conservative (flat call retained).
            uint256 item = frame.osaka - refused.osaka + engine;
            assertLt(item, GasBounds.DECIMATOR_GENERATED_GAS_MAX);
            assertLt(frame.osaka + engine, GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS);
            emit log_named_uint("scale item original count", n);
            emit log_named_uint("scale largest generated item ceiling", item);
            emit log_named_uint("scale cold item including worker frame ceiling", frame.osaka + engine);
        }
        if (!pass.glam) return;
        // The real engine again; it touches no slot, so recording leaves its cold figure unchanged.
        assertTrue(vm.revertToState(clean));
        (Priced memory engineG,) = _reprice(vm.snapshotState(), address(0xDEC17),
            abi.encodeCall(DecimatorGeneratedEngineMeter.run, (keccak256(abi.encode("ceiling", engineSeed)))), engine);
        _logPriced("511-roll engine ceiling", engineG, 0);
        for (uint256 k; k < ns.length; ++k) {
            uint256 item = glamFrame[k] - glamRefused[k] + _glam(engineG);
            emit log_named_uint("scale item original count", ns[k]);
            emit log_named_uint("Glamsterdam largest generated item ceiling", item);
            emit log_named_uint("Glamsterdam cold item including worker frame ceiling", glamFrame[k] + _glam(engineG));
            assertLt(item, GasBounds.DECIMATOR_GENERATED_GAS_MAX,
                "Glamsterdam generated item fits DECIMATOR_GENERATED_GAS_MAX");
            assertLt(glamFrame[k] + _glam(engineG),
                GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS,
                "Glamsterdam generated item and worker frame fit DECIMATOR_GENERATED + WORK_TAIL");
        }
    }

    /// @dev One generated-work call: unrecorded and cold, or recorded and repriced in a Glamsterdam pass.
    function _work(DecimatorJackpotTerms memory terms, uint256 allowance, Pass memory pass)
        private returns (Priced memory p, MineFlipGas.Result memory result)
    {
        if (!pass.glam) {
            (p.osaka, result) = workMeter.run(h, terms, allowance);
            return (p, result);
        }
        bytes memory ret;
        (p, ret) = _recorded(address(workMeter), abi.encodeCall(workMeter.run, (h, terms, allowance)), pass, 0);
        (, result) = abi.decode(ret, (uint256, MineFlipGas.Result));
    }

    function _coolGenerated() private {
        vm.cool(address(h)); vm.cool(ContractAddresses.CRAPS); vm.cool(ContractAddresses.CRAPS_ENGINE);
    }

    function _engineCeiling() private returns (uint256 engine, uint256 seed) {
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
                if (used > engine) (engine, seed) = (used, i);
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
                    uint256 index = uint256(keccak256(abi.encode(uint256(47), uint256(777), uint256(id)))) % 250;
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
