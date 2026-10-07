// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DecimatorJackpotTerms} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract DecimatorJackpotEngineProbe {
    function settleSlipBounded(uint256 chips, uint256 chip, uint256 board, uint256 scatter, bytes32,
        uint256 bankroll, uint256, uint256 boost, uint256 bounds) external pure returns (Craps.SlipResult memory r)
    {
        uint256 named;
        for (uint256 i; i < 30; i += 3) named += (chips >> i) & 7;
        require(chip == 60 && scatter == 10 - named && bankroll == 3000e18 && bounds == (511 << 16 | 48));
        require(boost == (0x050c070c0a0c0e0c120c140c190c1e0c >> (named << 4)) & 0xffff);
        r.peakBankroll = bankroll + board % (1_000_000e18);
    }
}

contract DecimatorJackpotPreferenceProbe {
    mapping(uint32 => uint32) public preferredBoardOf;
    function set(address owner, uint32 chips) external {
        preferredBoardOf[DecimatorJackpotHarness(ContractAddresses.GAME).registerWallet(owner, true)] = chips;
    }
}

contract DecimatorJackpotHarness is DegenerusGameDecimatorModule, WalletSeed {
    function seedProtocolWallets() external { _seedProtocolWallets(); }
    function keyOf(uint32 id) external view returns (address) { return _walletKey(id); }

    function prepare(uint24 lvl, uint40 n, uint96 pot, uint128 ethBudget, uint256 word, bool entries) external {
        level = lvl;
        dailyIdx = _simulatedDayIndex();
        jackpotPhaseFlag = true;
        jackpotFlags = JACKPOT_TURBO;
        rngLockedFlag = true;
        rngWordCurrent = word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        _setTicketBufferLevel(lvl);
        _setCurrentPrizePool(ethBudget);
        jackpotWork.kind = 2;
        jackpotWork.lvl = lvl;
        jackpotWork.finalDay = true;
        jackpotWork.budget = ethBudget;
        jackpotWork.traits = uint32(0xc0804000);
        for (uint8 q; q < 4; ++q) deityBySymbol[q * 8] = _seedWallet(address(uint160(0xa100 + q)));
        DecBattleRound storage r = decBattleRounds[lvl];
        r.count = n;
        r.totalCreditedStack = uint64(n) * 2000;
        r.openedDay = dailyIdx;
        if (entries) {
            for (uint64 i = 1; i <= n; ++i) {
                _storeDecEntry(lvl, uint64(i),
            (uint256(2000) << 62) | _seedWallet(address(uint160(0x1000 + i))));
            }
        }
        uint256 returned = this.runDecimatorJackpot(pot, lvl, word);
        claimablePool += pot - uint96(returned);
    }

    function daily(uint24 lvl, uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory r) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeCall(DegenerusGameJackpotModule.runDailyJackpot, (true, lvl, word, allowance))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        r = abi.decode(data, (MineFlipGas.Result));
    }

    function unlock() external { rngLockedFlag = false; }
    function rngLocked() external view returns (bool) { return rngLockedFlag; }
    function setDeity(uint8 q, address owner) external { deityBySymbol[q * 8] = owner == address(0) ? 0 : _seedWallet(owner); }
    function originalOnly(uint24 lvl) external { decJackpotPlans[lvl].mode = 0; }
    function seedPlan(uint24 lvl, DecJackpotPlan calldata p) external { decJackpotPlans[lvl] = p; }
    function plan(uint24 lvl) external view returns (DecJackpotPlan memory) { return decJackpotPlans[lvl]; }
    function round(uint24 lvl) external view returns (DecBattleRound memory) { return decBattleRounds[lvl]; }
    function node(uint256 index) external view returns (uint256) { return decBattleHeap[index]; }
    function ownerSlot(uint256 index) external view returns (address) { return _walletKey(decGeneratedOwners[index]); }
    function registerWallet(address owner, bool) external returns (uint32) { return _seedWallet(owner); }
    function walletIdOf(address owner) external view returns (uint32) { return _walletIdOf(owner); }
    function balance(address owner) external view returns (uint256) { return _claimableOf(_walletIdOf(owner)); }
    function passes(address owner) external view returns (uint256) { return _halfPassesOf(owner); }
    function pools() external view returns (uint256, uint256, uint256) {
        return (_getCurrentPrizePool(), _getFuturePrizePool(), claimablePool);
    }
    function queue() external view returns (uint256) { return decBattleQueue; }
    function paid() external view returns (uint256) { return jackpotWork.paid; }
    function extsload(bytes32 slot) external view returns (bytes32 value) { assembly { value := sload(slot) } }
}

contract DecimatorJackpotIntegrationTest is Test {
    DecimatorJackpotHarness private h;
    DegenerusGameLens private lens;
    uint24 private constant LVL = 5;
    uint256 private constant WORD = 777;
    bytes32 private constant GENERATED = keccak256("DecimatorGenerated(uint24,uint64,uint32,uint8,uint32,uint256,uint256)");
    bytes32 private constant RUN = keccak256("DecimatorRun(uint24,uint64,uint256)");

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.etch(ContractAddresses.GAME, type(DecimatorJackpotHarness).runtimeCode);
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, type(DegenerusGameJackpotModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_DECIMATOR_MODULE, type(DegenerusGameDecimatorModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, type(DegenerusGameWhaleModule).runtimeCode);
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorJackpotEngineProbe).runtimeCode);
        vm.etch(ContractAddresses.CRAPS, type(DecimatorJackpotPreferenceProbe).runtimeCode);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.AFFILIATE, abi.encodeWithSignature("affiliateTop(uint24)"), abi.encode(uint32(0), uint96(0)));
        h = DecimatorJackpotHarness(ContractAddresses.GAME);
        h.seedProtocolWallets();
        lens = new DegenerusGameLens();
    }

    function _daily(uint256 word, uint256 allowance) private {
        for (uint256 i; i < 2000; ++i) {
            MineFlipGas.Result memory r = h.daily(LVL, word, allowance);
            assertTrue(r.progressed, "daily work progresses");
            if (r.done) return;
        }
        fail("daily did not finish");
    }

    function _settle(uint256 allowance) private {
        h.unlock();
        for (uint256 i; h.queue() != 0 && i < 5000; ++i) {
            MineFlipGas.Result memory r = h.runDecimatorWork(allowance);
            assertTrue(r.progressed, "original work progresses");
        }
        assertEq(h.queue(), 0);
    }

    function test_NoCandidateRunsBeforeFinalFieldIsFixed() public {
        h.prepare(LVL, 40, 100 ether, 1000 ether, WORD, false);
        vm.recordLogs();
        assertFalse(h.daily(LVL, WORD, 100_000).progressed);
        assertFalse(h.runDecimatorWork(10_000_000).progressed);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(h.plan(LVL).mode, 1);
        assertEq(h.plan(LVL).cursor, 0);
        assertEq(h.round(LVL).cursor, 0);
        assertEq(h.round(LVL).winners, 0);
        _daily(WORD, 2_000_000);
        assertEq(h.plan(LVL).mode, 2);
        assertEq(h.plan(LVL).generatedEntries, 40);
        assertEq(h.plan(LVL).cursor, 40);
        assertEq(h.round(LVL).cursor, 0);
    }

    function test_PinnedThousandEthExampleFundsOnceBeforeAnyOriginal() public {
        h.prepare(LVL, 2000, 140 ether, 1000 ether, WORD, false);
        assertFalse(h.runDecimatorWork(10_000_000).progressed);
        vm.recordLogs();
        MineFlipGas.Result memory first = h.daily(LVL, WORD, 1_000_000);
        (uint256 budget,) = _planBudget(vm.getRecordedLogs());
        assertTrue(first.progressed);
        assertFalse(first.done);
        DegenerusGameStorage.DecJackpotPlan memory p = h.plan(LVL);
        assertEq(p.mode, 2);
        assertEq(budget, 650 ether);
        assertEq(p.soloAmount, 600 ether);
        assertEq(p.generatedEntries, 2000);
        assertEq(h.round(LVL).capacity, 200);
        assertEq(h.round(LVL).poolWei, 280 ether);
        (uint256 current,, uint256 reserved) = h.pools();
        assertEq(current, 860 ether);
        assertEq(reserved, 280 ether);
        assertEq(h.paid(), 140 ether);
        assertEq(abi.encode(lens.decJackpotPlanOf(address(h), LVL)), abi.encode(p));
        _daily(WORD, 5_000_000);
        assertEq(h.plan(LVL).cursor, 1000);
        assertEq(h.round(LVL).poolWei, 280 ether, "funding debited only once");
        assertEq(h.round(LVL).cursor, 0);
        (current,, reserved) = h.pools();
        assertEq(current, 0);
        assertEq(reserved, 731.5 ether);
        uint8 solo = uint8(3 - (uint256(keccak256(abi.encode(WORD, LVL))) & 3));
        assertEq(h.balance(address(uint160(0xa100 + solo))), 451.5 ether);
        assertEq(h.passes(address(uint160(0xa100 + solo))), 66);
        (, uint256 future,) = h.pools();
        assertEq(future, 408.5 ether);
        assertEq(140 ether + 451.5 ether + future, 1000 ether);
    }

    function test_UncappedFullMatchThroughUint40Maximum() public {
        uint40[11] memory ns = [uint40(100),101,400,401,1000,1001,4000,4001,8000,8001,type(uint40).max];
        uint256 clean = vm.snapshotState();
        for (uint256 i; i < ns.length; ++i) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            h.prepare(LVL, ns[i], 10 ether, 100 ether, WORD, false);
            h.daily(LVL, WORD, 1_000_000);
            DegenerusGameStorage.DecJackpotPlan memory p = h.plan(LVL);
            uint256 m = ns[i];
            uint256 f = (m * 10 ether + ns[i] - 1) / ns[i];
            assertEq(p.generatedEntries, m);
            assertEq(h.round(LVL).poolWei, 10 ether + f);
            assertEq(p.soloAmount, 60 ether);
            assertLe(p.cursor, Sample.count(uint256(ns[i]) + m));
            assertGt(f, 0);
        }
    }

    function test_ZeroEntriesAndSubWeiReferenceStillUseWholeEntryMath() public {
        uint256 clean = vm.snapshotState();
        h.prepare(LVL, 8000, 2000 ether, 1, WORD, false);
        MineFlipGas.Result memory result = h.daily(LVL, WORD, 500_000);
        assertTrue(result.done, "zero generated entries finish without scanning 1000 strata");
        DegenerusGameStorage.DecJackpotPlan memory p = h.plan(LVL);
        assertEq(p.generatedEntries, 0);
        assertEq(p.cursor, 0);
        assertEq(h.round(LVL).cursor, 0, "original settlement remains pending");
        assertEq((h.round(LVL).poolWei - 2000 ether), 0);
        assertEq(p.mode, 2);
        assertTrue(vm.revertToState(clean));
        h.prepare(LVL, 101, 7, 100, WORD, false);
        _daily(WORD, 3_000_000);
        p = h.plan(LVL);
        assertEq(p.generatedEntries, 101);
        assertEq((h.round(LVL).poolWei - 7), 7, "do not round a sub-wei entry price before multiplying");
        assertEq(h.round(LVL).poolWei, 14);
    }

    function testFuzz_PartialFundingAndFixedAllocation(uint40 count, uint96 pot, uint96 budget) public {
        uint40 n = uint40(bound(count, 1, type(uint40).max));
        pot = uint96(bound(pot, 1, 1_000_000 ether));
        budget = uint96(bound(budget, 1, 1_000_000 ether));
        h.prepare(LVL, n, pot, budget, WORD, false);
        vm.recordLogs();
        h.daily(LVL, WORD, 1_000_000);
        (uint256 conversionBudget, uint64 weights) = _planBudget(vm.getRecordedLogs());
        // The final-day non-solo shares are 13.33%, 13.33%, 13.34%; solo receives the rest.
        uint256 nonSolo = 2 * (uint256(budget) * 1333 / 10000) + uint256(budget) * 1334 / 10000;
        uint256 soloShare = budget - nonSolo;
        assertEq(conversionBudget, uint256(budget) - uint256(budget) * 35 / 100);
        uint8 solo = uint8(3 - (uint256(keccak256(abi.encode(WORD, LVL))) & 3));
        assertEq(uint16(weights >> (solo * 16)), 0);
        DegenerusGameStorage.DecJackpotPlan memory p = h.plan(LVL);
        uint256 m = nonSolo == 0 ? 0 : conversionBudget * n / pot;
        if (m > n) m = n;
        uint256 f = (m * pot + n - 1) / n;
        assertEq(p.generatedEntries, m);
        assertEq(h.round(LVL).poolWei, uint256(pot) + f);
        assertLe(f, conversionBudget);
        assertLe(f, pot);
        assertEq(p.soloAmount, uint256(budget) - f < soloShare ? uint256(budget) - f : soloShare);
        uint256 field = uint256(n) + m;
        uint256 places = (field + 9) / 10;
        if (places < 20) places = 20;
        if (places > field / 2) places = field / 2;
        assertEq(h.round(LVL).capacity, places > 200 ? 200 : places);
        assertEq(p.weights, weights);
        assertGe(p.soloAmount, uint256(budget) * 35 / 100);
        assertLe(p.soloAmount, soloShare);
        if (nonSolo != 0 && pot <= conversionBudget) assertEq(m, n, "all active cohorts fully match affordable pots");
    }

    function test_UncappedGeneratedFieldMatchesIndependentTop200() public {
        h.prepare(LVL, 4001, 60 ether + 7, 1000 ether, WORD, true);
        vm.recordLogs();
        _daily(WORD, 3_000_000);
        _settle(1_000_000);
        _assertField(4001, WORD, vm.getRecordedLogs());
        assertEq(h.plan(LVL).generatedEntries, 4001);
        assertEq(h.round(LVL).winners, 200);
    }

    function test_EmptyCohortsDoNotContributeOrDraw() public {
        h.prepare(LVL, 40, 10 ether, 100 ether, WORD, true);
        for (uint8 q; q < 4; ++q) h.setDeity(q, address(0));
        vm.recordLogs();
        _daily(WORD, 3_000_000);
        (uint256 budget,) = _planBudget(vm.getRecordedLogs());
        assertEq(budget, 25 ether, "unused solo excess cannot buy entries without a cohort");
        assertEq(h.plan(LVL).generatedEntries, 0);
        assertEq(h.round(LVL).poolWei, 10 ether);
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 100 ether);
        assertEq(reserved, 10 ether);
        _settle(1_000_000);
    }

    function test_ZeroReferenceKeepsNormalCashAndPassFallback() public {
        uint256 clean = vm.snapshotState();
        for (uint8 zeroPot; zeroPot < 2; ++zeroPot) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            h.prepare(LVL, zeroPot == 0 ? 0 : 40, zeroPot == 0 ? 10 ether : 0, 100 ether, WORD, true);
            _daily(WORD, 3_000_000);
            assertEq(h.plan(LVL).mode, 0);
            assertEq(h.round(LVL).poolWei, 0);
            uint256 paid;
            uint256 passes;
            for (uint160 q; q < 4; ++q) { paid += h.balance(address(0xa100 + q)); passes += h.passes(address(0xa100 + q)); }
            assertGt(paid, 0);
            assertGt(passes, 0);
            (uint256 current, uint256 future, uint256 reserved) = h.pools();
            assertEq(current, 0);
            assertEq(reserved, paid);
            assertEq(reserved + future, 100 ether);
            if (zeroPot != 0) _settle(1_000_000);
        }
    }

    function test_EmptySoloAndMixedCohortsFinishAndSweepUnpaidBudget() public {
        // This word rotates the final-day solo to quadrant 3.
        h.prepare(LVL, 40, 10 ether, 1000 ether, 6, true);
        h.setDeity(1, address(0));
        h.setDeity(3, address(0));
        vm.recordLogs();
        _daily(6, 2_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 budget, uint64 weights) = _planBudget(logs);
        assertEq(budget, 516.7 ether); // active non-solo 266.7 plus solo excess 250
        assertEq(uint16(weights), 256, "non-solo weight is its cash target without a pass increment");
        assertEq(uint16(weights >> 16), 0);
        assertEq(uint16(weights >> 32), 32);
        assertEq(uint16(weights >> 48), 0);
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == GENERATED) {
            (uint8 q,,,) = abi.decode(logs[i].data, (uint8,uint32,uint256,uint256));
            assertTrue(q == 0 || q == 2, "empty cohorts have no generated entries");
        }
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 990 ether);
        assertEq(reserved, 20 ether);
        _settle(1_000_000);
    }

    function test_SoloBelowPassThresholdKeepsNormalShareAndSweepsSurplus() public {
        h.prepare(LVL, 40, 5 ether, 20 ether, 6, false);
        _daily(6, 2_000_000);
        assertEq(h.plan(LVL).soloAmount, 12 ether);
        assertEq(h.balance(address(0xa103)), 12 ether);
        assertEq(h.passes(address(0xa103)), 0);
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 3 ether);
        assertEq(reserved, 22 ether); // original 5 + funding 5 + cash 12
    }

    function test_SoloAtPassThresholdRetainsOneWholePass() public {
        h.prepare(LVL, 40, 5 ether, 30 ether, 6, false);
        _daily(6, 2_000_000);
        assertEq(h.plan(LVL).soloAmount, 18 ether);
        assertEq(h.balance(address(0xa103)), 13.5 ether); // 18 - 4.5
        assertEq(h.passes(address(0xa103)), 2);
        (, uint256 future, uint256 reserved) = h.pools();
        assertEq(future, 11.5 ether); // pass funding 4.5 plus surplus 7
        assertEq(reserved + future, 35 ether);
    }

    function test_MatchMayReduceSoloBelowPassThreshold() public {
        h.prepare(LVL, 40, 19.5 ether, 30 ether, 6, false);
        _daily(6, 2_000_000);
        assertEq(h.plan(LVL).soloAmount, 10.5 ether);
        assertEq(h.plan(LVL).generatedEntries, 40);
        assertEq(h.balance(address(0xa103)), 10.5 ether);
        assertEq(h.passes(address(0xa103)), 0, "pass cost uses the reduced solo budget");
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 0);
        assertEq(reserved, 49.5 ether);
    }

    function test_NoNonSoloCohortCannotGenerateFromSoloExcess() public {
        h.prepare(LVL, 40, 140 ether, 1000 ether, 6, false);
        for (uint8 q; q < 3; ++q) h.setDeity(q, address(0));
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("preferredBoardOf(uint32)"), hex"12345678");
        _daily(6, 2_000_000);
        assertEq(h.plan(LVL).generatedEntries, 0);
        assertEq(h.plan(LVL).weights, 0);
        assertEq(h.plan(LVL).soloAmount, 600 ether);
        assertEq(h.balance(address(0xa103)), 451.5 ether);
        assertEq(h.passes(address(0xa103)), 66);
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, 548.5 ether);
        assertEq(reserved, 591.5 ether);
    }

    function testFuzz_SoloPassConservationAndExcludedAllocation(uint96 dayBudget, uint96 originalPool,
        uint40 population, uint8 emptyMask, uint256 word) public
    {
        word = bound(word, 2, type(uint256).max);
        uint256 budget = bound(dayBudget, 1, 1000 ether);
        uint96 pot = uint96(bound(originalPool, 1, 1000 ether));
        uint40 n = uint40(bound(population, 1, type(uint40).max));
        h.prepare(LVL, n, pot, uint128(budget), word, false);
        for (uint8 q; q < 4; ++q) if (emptyMask & (1 << q) != 0) h.setDeity(q, address(0));
        uint8 offset = uint8(uint256(keccak256(abi.encode(word, LVL))) & 3);
        uint8 solo = 3 - offset;
        uint256 soloShare = budget - 2 * (budget * 1333 / 10000) - budget * 1334 / 10000;
        uint256 activeNonSolo;
        for (uint8 q; q < 4; ++q) if (q != solo && emptyMask & (1 << q) == 0) {
            activeNonSolo += budget * (((q + offset) & 3) == 2 ? 1334 : 1333) / 10000;
        }
        vm.recordLogs();
        _daily(word, 2_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 available, uint64 weights) = _planBudget(logs);
        assertEq(available, activeNonSolo + soloShare - budget * 35 / 100);
        assertEq(uint16(weights >> (solo * 16)), 0, "solo has no generated weight");
        DegenerusGameStorage.DecJackpotPlan memory p = h.plan(LVL);
        assertEq(p.weights, weights);
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == GENERATED) {
            (uint8 q,,,) = abi.decode(logs[i].data, (uint8,uint32,uint256,uint256));
            assertTrue(q != solo, "solo cannot receive generated entries");
        }
        uint256 m = activeNonSolo == 0 ? 0 : available * n / pot;
        if (m > n) m = n;
        assertEq(p.generatedEntries, m);
        uint256 funding = h.round(LVL).poolWei - pot;
        assertEq(funding, (m * pot + n - 1) / n);
        uint256 soloAmount = activeNonSolo + soloShare - funding;
        if (soloAmount > soloShare) soloAmount = soloShare;
        assertEq(p.soloAmount, soloAmount);
        assertGe(soloAmount, budget * 35 / 100);
        assertLe(soloAmount, soloShare);
        assertEq(p.cursor, m == 0 ? 0 : Sample.count(uint256(n) + m));
        uint256 passCost;
        uint256 cash;
        uint256 unpaid = budget - funding;
        if (emptyMask & (1 << solo) == 0) {
            passCost = soloAmount / 18 ether * 4.5 ether;
            cash = soloAmount - passCost;
            unpaid -= soloAmount;
        }
        for (uint8 q; q < 4; ++q) {
            assertEq(h.balance(address(uint160(0xa100 + q))), q == solo ? cash : 0);
            assertEq(h.passes(address(uint160(0xa100 + q))), q == solo ? passCost / 2.25 ether : 0);
        }
        (uint256 current, uint256 future, uint256 reserved) = h.pools();
        assertEq(current, 0);
        assertEq(future, passCost + unpaid);
        assertEq(reserved, uint256(pot) + funding + cash);
        assertEq(funding + cash + passCost + unpaid, budget, "complete daily ETH conservation");
    }

    function test_RealPreferredBoardCannotChangeWhileGeneratedWorkIsPending() public {
        vm.etch(ContractAddresses.CRAPS, type(CrapsBattle).runtimeCode);
        CrapsBattle c = CrapsBattle(ContractAddresses.CRAPS);
        for (uint160 q; q < 4; ++q) {
            vm.prank(address(0xa100 + q));
            c.setPreferredBoard(0, 3);
        }
        h.prepare(LVL, 101, 60 ether, 1000 ether, WORD, true);
        h.daily(LVL, WORD, 1_000_000);
        vm.prank(address(0xa100));
        vm.expectRevert();
        c.setPreferredBoard(0, 2);
        assertEq(c.preferredBoardOf(h.walletIdOf(address(0xa100))), 3);
        _daily(WORD, 3_000_000);
        _settle(1_000_000);
        vm.prank(address(0xa100));
        c.setPreferredBoard(0, 2);
        assertEq(c.preferredBoardOf(h.walletIdOf(address(0xa100))), 2);
    }

    function test_OneOriginalGetsFinalCapacityOnlyAfterGeneratedPlan() public {
        h.prepare(LVL, 1, 1 ether, 100 ether, WORD, true);
        assertEq(h.round(LVL).capacity, 0);
        assertEq(h.plan(LVL).mode, 1);
        _daily(WORD, 2_000_000);
        assertEq(h.round(LVL).capacity, 1);
        assertEq(h.plan(LVL).generatedEntries, 1);
        _settle(2_000_000);
        assertLe(h.round(LVL).winners, 1);
    }

    function test_OneOriginalWithoutMatchSamplesOneButPaysNobody() public {
        uint256 word = 2;
        h.prepare(LVL, 1, 100 ether, 1, word, true);
        _daily(word, 2_000_000);
        _settle(2_000_000);
        assertEq(h.round(LVL).capacity, 0);
        assertEq(h.round(LVL).winners, 0);
        assertEq(h.balance(address(0x1001)), 0);
        (, uint256 future,) = h.pools();
        assertEq(future, 100 ether);
    }

    function testFuzz_LensPlanPacking(uint24 lvl, DegenerusGameStorage.DecJackpotPlan memory p) public {
        h.seedPlan(lvl, p);
        assertEq(abi.encode(lens.decJackpotPlanOf(address(h), lvl)), abi.encode(p));
    }

    function test_RealEnginePreferredBoardsAndCallerPartitionsKeepTranscript() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        for (uint160 q; q < 4; ++q) {
            uint32 chips = q == 0 ? 0 : q == 1 ? 1 : q == 2 ? 3 : 3 | 3 << 9 | 1 << 24;
            DecimatorJackpotPreferenceProbe(ContractAddresses.CRAPS).set(address(0xa100 + q), chips);
        }
        h.prepare(LVL, 101, 60 ether, 1000 ether, WORD, true);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _daily(WORD, 8_000_000);
        _settle(8_000_000);
        bytes32 whole = _digest(vm.getRecordedLogs());
        bytes memory state = abi.encode(h.round(LVL), h.plan(LVL));
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        vm.startPrank(address(0x1234));
        _daily(WORD, 2_000_000);
        _settle(1_000_000);
        vm.stopPrank();
        assertEq(_digest(vm.getRecordedLogs()), whole);
        assertEq(abi.encode(h.round(LVL), h.plan(LVL)), state);
    }

    function test_RepeatedRecipientKeepsSeparateRunKeysAndFrozenChips() public {
        uint256 word = 2;
        uint64 id = 102;
        while (!Sample.contains(word, LVL, 202, id)) ++word;
        address owner = address(0x1001);
        uint32 chips = 3 | 3 << 9 | 1 << 24;
        DecimatorJackpotPreferenceProbe(ContractAddresses.CRAPS).set(owner, chips);
        h.prepare(LVL, 101, 60 ether, 1000 ether, word, true);
        for (uint8 q; q < 4; ++q) h.setDeity(q, owner);
        address player = address(uint160(uint256(keccak256(abi.encode(keccak256("decimator.battle.generated.player.v1"), word, LVL, id)))));
        assertTrue(player != owner);
        vm.expectCall(ContractAddresses.CRAPS_ENGINE, abi.encodeWithSignature(
            "settleSlipBounded(uint256,uint256,uint256,uint256,bytes32,uint256,uint256,uint256,uint256)",
            uint256(chips), uint256(60), uint256(keccak256(abi.encode(keccak256("decimator.battle.board.v1"),word,LVL,id))),
            uint256(3), keccak256(abi.encode(keccak256("decimator.battle.dice.v1"),word,LVL)),
            uint256(3000e18), uint256(uint160(player)), uint256(0x050c), uint256(511 << 16 | 48)
        ), 1);
        vm.recordLogs();
        _daily(word, 3_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 receipts;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == GENERATED) {
            assertEq(h.keyOf(uint32(uint256(logs[i].topics[3]))), owner);
            (, uint32 usedChips,,) = abi.decode(logs[i].data,(uint8,uint32,uint256,uint256));
            assertEq(usedChips, chips);
            uint64 actualId = uint64(uint256(logs[i].topics[2]));
            assertGe(actualId, 102);
            assertLe(actualId, 202);
            assertTrue(Sample.contains(word, LVL, 202, actualId));
            ++receipts;
        }
        uint256 expected;
        for (uint64 i = 102; i <= 202; ++i) if (Sample.contains(word, LVL, 202, i)) ++expected;
        assertEq(receipts, expected);
        _settle(1_000_000);
    }

    function test_FailedPreferenceLookupRevertsItemWithoutRepeatingFunding() public {
        h.prepare(LVL, 100, 10 ether, 100 ether, WORD, false);
        h.daily(LVL, WORD, 1_000_000);
        uint16 beforeCursor = h.plan(LVL).cursor;
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("preferredBoardOf(uint32)"), hex"12345678");
        vm.expectRevert(bytes4(0x12345678));
        h.daily(LVL, WORD, 3_000_000);
        assertEq(h.plan(LVL).cursor, beforeCursor);
        assertEq(h.round(LVL).poolWei, 20 ether);
        assertEq(h.paid(), 10 ether);
    }

    function _planBudget(Vm.Log[] memory logs) private view returns (uint256 budget, uint64 weights) {
        bytes32 topic = keccak256("DecimatorJackpotPlan(uint24,uint256,uint96,uint64,uint40,uint128,uint96,uint128,uint32,uint40,uint64)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(h) || logs[i].topics[0] != topic) continue;
            (,,,,budget,,,,,weights) = abi.decode(logs[i].data,
                (uint256,uint96,uint64,uint40,uint128,uint96,uint128,uint32,uint40,uint64));
            return (budget, weights);
        }
        revert("missing plan");
    }

    function _digest(Vm.Log[] memory logs) private view returns (bytes32 digest) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].emitter == address(h)) {
            digest = keccak256(abi.encode(digest,logs[i].topics,logs[i].data));
        }
    }

    function test_AllTiedScoresAndLensMatchSharedIdentityOrder() public {
        Craps.SlipResult memory flat;
        flat.peakBankroll = 3000e18;
        vm.mockCall(ContractAddresses.CRAPS_ENGINE, abi.encodeWithSignature(
            "settleSlipBounded(uint256,uint256,uint256,uint256,bytes32,uint256,uint256,uint256,uint256)"
        ), abi.encode(flat));
        h.prepare(LVL, 401, 600 ether + 7, 2000 ether, WORD, true);
        vm.recordLogs();
        _daily(WORD, 3_000_000);
        h.unlock();
        for (uint256 i; h.round(LVL).phase == 1 && i < 1000; ++i) h.runDecimatorWork(700_000);
        assertEq(h.round(LVL).phase, 2, "inspect retained entries before completion");
        for (uint8 i; i < h.round(LVL).winners; ++i) {
            DegenerusGameLens.DecWinner memory node = lens.decWinnerAt(address(h), LVL, i);
            uint256 raw = h.node(i);
            assertEq(uint64(node.key), uint64(raw));
            assertEq(node.score, raw >> 64);
            uint64 id = uint64(raw);
            assertEq(node.owner, id > 401 ? h.ownerSlot(id - 401) : address(uint160(0x1000 + id)));
            assertEq(node.key, (uint256(keccak256(abi.encode(keccak256("decimator.battle.tie.v1"),
                WORD, LVL, uint64(raw)))) & ~uint256(type(uint64).max)) | uint64(raw));
        }
        _settle(1_000_000);
        _assertField(401, WORD, vm.getRecordedLogs());
    }

    function testFuzz_SharedHeapMatchesIndependentFieldAndConservesPool(uint8 population, uint256 word) public {
        uint40 n = uint40(bound(population, 1, 120));
        word = bound(word, 2, type(uint256).max);
        h.prepare(LVL, n, 60 ether + 7, 1000 ether, word, true);
        vm.recordLogs();
        _daily(word, 3_000_000);
        _settle(1_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertField(n, word, logs);
        (, uint256 future, uint256 reserved) = h.pools();
        uint256 balances;
        for (uint160 i = 1; i <= n; ++i) balances += h.balance(address(0x1000 + i));
        for (uint160 q; q < 4; ++q) balances += h.balance(address(0xa100 + q));
        assertEq(balances, reserved);
        assertEq(balances + future, 1060 ether + 7);
    }

    function _assertField(uint40 n, uint256 word, Vm.Log[] memory logs) private view {
        uint256 m = h.plan(LVL).generatedEntries;
        uint256 field = uint256(n) + m;
        uint256[] memory nodes = new uint256[](field);
        bool[] memory seen = new bool[](field + 1);
        uint256 eligible;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(h) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != GENERATED && logs[i].topics[0] != RUN) continue;
            uint64 id = uint64(uint256(logs[i].topics[2]));
            assertGt(id, 0); assertLe(id, field); assertFalse(seen[id], "one run per id"); seen[id] = true;
            uint256 score;
            if (logs[i].topics[0] == GENERATED) {
                (,,, score) = abi.decode(logs[i].data, (uint8,uint32,uint256,uint256));
                assertGt(id, n);
            } else {
                score = 2000 * abi.decode(logs[i].data, (uint256));
                assertLe(id, n);
            }
            nodes[eligible++] = (score << 64) | id;
        }
        assertEq(eligible, Sample.count(field), "exact survivor count across both phases");
        for (uint64 id = 1; id <= field; ++id) {
            assertEq(seen[id], Sample.contains(word, LVL, field, id));
        }
        for (uint256 i = 1; i < eligible; ++i) {
            uint256 node = nodes[i]; uint256 j = i;
            while (j != 0 && _better(word, node, nodes[j-1])) { nodes[j] = nodes[j-1]; --j; }
            nodes[j] = node;
        }
        uint256 expectedW = (field + 9) / 10;
        if (expectedW < 20) expectedW = 20;
        if (expectedW > field / 2) expectedW = field / 2;
        if (expectedW > 200) expectedW = 200;
        assertEq(h.round(LVL).winners, expectedW);
        for (uint256 i; i < expectedW; ++i) {
            uint256 node = h.node(i);
            bool found;
            for (uint256 j; j < expectedW; ++j) if (nodes[j] == node) { found = true; break; }
            assertTrue(found, "retains exactly the strongest eligible entries");
            for (uint256 j; j < i; ++j) assertTrue(h.node(j) != node, "unique winner");
        }
        if (expectedW != 0) assertEq(h.round(LVL).champion, uint64(nodes[0]));
        _assertPayments(logs);
    }

    function _assertPayments(Vm.Log[] memory logs) private view {
        uint256 w = h.round(LVL).winners;
        if (w == 0) return;
        uint256 pool = h.round(LVL).poolWei;
        uint256 base = (pool - pool / 20) / w;
        uint256 first = pool - base * (w - 1);
        uint256 unit = 2.25 ether;
        bool passMode = base >= unit && w > 1;
        uint256 passPositions = (w - 1) / 2;
        uint256 topup = passMode ? passPositions * (base % unit) / (w - 1 - passPositions) : 0;
        bytes32 claim = keccak256("DecimatorClaimed(uint32,uint24,uint64,uint256,uint256)");
        for (uint256 pos; pos < w; ++pos) {
            uint64 id = uint64(h.node(pos));
            address owner = address(uint160(0x1000 + id));
            if (id > h.round(LVL).count) {
                owner = address(0);
                for (uint256 i; i < logs.length; ++i) {
                    if (logs[i].emitter == address(h) && logs[i].topics[0] == GENERATED
                        && uint64(uint256(logs[i].topics[2])) == id) {
                        owner = h.keyOf(uint32(uint256(logs[i].topics[3])));
                        break;
                    }
                }
                assertTrue(owner != address(0), "winner owner comes from its original generated receipt");
                assertEq(h.ownerSlot(id - h.round(LVL).count), owner);
            }
            uint256 eth; uint256 passes;
            if (pos == 0) { passes = first / 2 / unit; eth = first - passes * unit; }
            else if (passMode && pos % 2 == 0) passes = base / unit;
            else eth = base + topup;
            bool found;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != address(h) || logs[i].topics[0] != claim
                    || uint64(uint256(logs[i].topics[3])) != id) continue;
                (uint256 paidEth, uint256 paidPasses) = abi.decode(logs[i].data, (uint256,uint256));
                assertFalse(found, "one receipt per winner");
                assertEq(h.keyOf(uint32(uint256(logs[i].topics[1]))), owner);
                assertEq(paidEth, eth); assertEq(paidPasses, passes); found = true;
            }
            assertTrue(found, "every retained entry paid");
        }
    }

    function _better(uint256 word, uint256 a, uint256 b) private pure returns (bool) {
        if (a >> 64 != b >> 64) return a >> 64 > b >> 64;
        bytes32 tag = keccak256("decimator.battle.tie.v1");
        uint256 ka = (uint256(keccak256(abi.encode(tag,word,LVL,uint64(a)))) & ~uint256(type(uint64).max)) | uint64(a);
        uint256 kb = (uint256(keccak256(abi.encode(tag,word,LVL,uint64(b)))) & ~uint256(type(uint64).max)) | uint64(b);
        return ka > kb;
    }


}
