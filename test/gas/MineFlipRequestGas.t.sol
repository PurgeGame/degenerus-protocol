// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {GNRUS} from "../../contracts/GNRUS.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {Test} from "forge-std/Test.sol";
import {RequestCostCoordinator, RequestStethEnvelope} from "../helpers/RequestCostCoordinator.sol";
import {VRFRandomWordsRequest, IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MockStETH} from "../../contracts/mocks/MockStETH.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";

contract RequestCloseProbe is DegenerusGameRngUtils {
    function closeOnly() external { _closeRedemptionBatch(); }
}

contract RequestGameSeeder is DegenerusGame {
    function seed(bool daily, bool transition, bool certify) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = daily ? today - 1 : today;
        _afkingResetDay = today;
        purchaseStartDay = daily && !transition ? today - 2 : today;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        rngRequestTime = uint48(block.timestamp - 1 hours);
        rngLockedFlag = false;
        rngWordCurrent = 1234;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(!certify);
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        subsFullyProcessed = true;
        _recordDailyRng(today, 1234);
        level = 13;
        lastPurchaseDay = transition;
        if (transition) {
            jackpotFlags = JACKPOT_TURBO;
            snapLevel = 14;
            snapPendingShift = 1;
            _setTicketRedemptionOpen(true);
        }
        _setPrizePools(1000 ether, 1000 ether);
        levelPrizePool[13] = 100 ether;
        vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
        vrfSubscriptionId = 1;
    }
    function pendingMidday(uint8 shape, uint32 id) external {
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, shape == 3 ? 100 : 0);
        if (shape == 3) middayRngCredit[id] = 100 ether;
        if (shape == 1) {
            earlyTicketLevel = level + 2;
            _queueEntries(id, level + 1, 4, false);
        }
        if (shape == 2) _queueEntries(id, level + 2, 4, false);
        if (shape == 4) {
            lastPurchaseDay = true;
            jackpotFlags = JACKPOT_TURBO;
            earlyTicketLevel = level + 2; // activation already occurred; exercise the final-swap guard
        }
    }
    function claimableBacking(uint256 amount) external {
        _creditClaimable(SDGNRS_WALLET_ID, amount);
        claimablePool += uint128(amount);
    }
    function requestOnly(bool daily) external {
        bytes memory data = daily ? abi.encodeWithSignature("requestDailyRng(uint24)", _afkingResetDay)
            : abi.encodeWithSignature("requestMinerRng()");
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
    function committed() external view returns (uint48 read, uint48 write, uint256 request, uint24 day) {
        return (_rngReadBuffer(), _rngWriteBuffer(), vrfRequestId, rngRequestDay);
    }
    function ticketState() external view returns (bool complete, bool writeSlot, uint24 early, uint256 latch) {
        return (ticketsFullyProcessed, ticketWriteSlot, earlyTicketLevel, _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK));
    }
    function credit(uint32 id) external view returns (uint256) { return middayRngCredit[id]; }
    // Requests only latch these write counts; member records are not visited until fulfillment.
    function seedWriteCounts(bool daily) external {
        _lrWrite(LR_BOX_COUNT_SHIFT, LR_COUNT_MASK, 1);
        _lrWrite(LR_BET_COUNT_SHIFT, LR_COUNT_MASK, 1);
        if (daily) foilWriteCount = 1;
    }
    function frozenCounts() external view returns (uint256 boxes, uint256 bets, uint256 foils) {
        return (boxReadCount, degeneretteReadCount, foilReadCount);
    }
    function closeOnly() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(abi.encodeWithSignature("closeOnly()"));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

contract RequestFlipSeeder is CoinflipStakeSetter {
    function seedBacking(uint24 latest, uint8 mode) external {
        uint32 id = degenerusGame.walletIdOf(ContractAddresses.SDGNRS);
        PlayerCoinflipState storage s = playerState[id];
        s.claimableStored = mode == 0 ? 1_000_000 : mode == 1 ? 0 : 1_000;
        s.lastClaim = latest;
        s.autoRebuyStartDay = 21;
        s.autoRebuyEnabled = true;
        s.autoRebuyStop = 0;
        s.autoRebuyCarry = 1_000_001;
        flipsClaimableDay = latest;
    }

}

contract RequestCharitySeeder is GNRUS {
    function seed(uint24 lvl) external {
        currentLevel = lvl;
        for (uint8 i; i < 20; ++i) slotApproveWeight[lvl][i] = i + 1;
    }
}

contract RequestMaintenanceSeeder is CrapsBattle {
    function seedHead(uint24 day, uint8 period, uint32 entrants) external {
        _keeperSlot = uint64(uint256(day) * _BONUS_SLOTS_PER_DAY + period);
        _boostBudget[day] = 1;
        _battles[bytes32(uint256(_keeperSlot))] = entrants;
    }
    function binding(uint64 slot) external view returns (uint48) { return _slotIndexOf(slot); }
    function seedPaidJackpot(uint24 day) external {
        _bonus = uint256(day) + 1;
        _boostBudget[day] = 1;
        uint256 key = uint256(day) * _BONUS_SLOTS_PER_DAY + _BONUS_PERIODS_PER_DAY;
        _battles[bytes32(key)] = 3 | ((_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT);
        _dayTickets[uint256(day) * _BONUS_SLOTS_PER_DAY] = 1 | (uint256(1) << (_DT_HIGH_SHIFT * _BONUS_PERIODS_PER_DAY));
    }
    function frozenPaidCount() external view returns (uint256) { return _jackpotRounds[_activeJackpotSlot].paidCount; }
}

contract MineFlipRequestGasTest is DeployProtocol {
    uint24 internal constant DAY = 1000;
    RequestGameSeeder internal host;
    RequestCostCoordinator internal coordinator;
    RequestMaintenanceSeeder internal table;
    address internal constant BURNER = address(0xA11CE);
    uint32 internal burnerId;
    uint256 internal burned;
    uint64 internal slot;

    enum Scenario { Midday, TicketSwap, TicketActivation, Credit, FinalDay,
        Daily, Transition, RedeemEth, RedeemSteth, RedeemMixed, RedeemStored, RedeemCarry,
        DailyRedeem, Arm, ArmRedeem, CertifyDaily, CertifyDailyRedeem, DailyPaid, DailyPaidRedeem }
    bool private dailyCase;
    bool private transitionCase;
    bool private redemptionCase;
    bool private armCase;
    bool private certifyCase;
    bool private paidField;
    uint8 private shape;
    uint8 private funding = 2;
    uint8 private backingMode = 2;

    function _daily() internal view returns (bool) { return dailyCase; }
    function _transition() internal view returns (bool) { return transitionCase; }
    function _redemption() internal view returns (bool) { return redemptionCase; }
    function _funding() internal view returns (uint8) { return funding; }
    function _arm() internal view returns (bool) { return armCase; }
    function _certify() internal view returns (bool) { return certifyCase; }
    function _shape() internal view returns (uint8) { return shape; }

    function setUp() public { _deployProtocol(); }

    /// @dev With --isolate this outer call commits setup before the measured transaction:
    /// both access warmth AND original SSTORE values reset, including token funding.
    function configure(Scenario scenario) external {
        require(msg.sender == address(this));
        paidField = scenario == Scenario.DailyPaid || scenario == Scenario.DailyPaidRedeem;
        dailyCase = scenario == Scenario.Daily || scenario == Scenario.Transition || scenario == Scenario.DailyRedeem
            || scenario == Scenario.CertifyDaily || scenario == Scenario.CertifyDailyRedeem || paidField;
        transitionCase = dailyCase && scenario != Scenario.Daily;
        redemptionCase = (scenario >= Scenario.RedeemEth && scenario <= Scenario.DailyRedeem)
            || scenario == Scenario.ArmRedeem || scenario == Scenario.CertifyDailyRedeem || scenario == Scenario.DailyPaidRedeem;
        armCase = scenario == Scenario.Arm || scenario == Scenario.ArmRedeem;
        certifyCase = scenario == Scenario.CertifyDaily || scenario == Scenario.CertifyDailyRedeem;
        if (scenario >= Scenario.TicketSwap && scenario <= Scenario.FinalDay) shape = uint8(scenario);
        if (scenario == Scenario.RedeemEth) funding = 0;
        if (scenario == Scenario.RedeemSteth) funding = 1;
        if (scenario == Scenario.RedeemStored) backingMode = 0;
        if (scenario == Scenario.RedeemCarry) backingMode = 1;
        vm.warp((uint256(DAY - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1 hours);
        vm.fee(1 gwei);
        mockFeed.setPrice(0.004 ether);
        vm.etch(address(game), type(RequestGameSeeder).runtimeCode);
        host = RequestGameSeeder(payable(address(game)));
        host.seed(_daily(), _transition(), _certify());
        burnerId = _giveWalletId(BURNER);
        if (!_daily() && !_arm()) host.pendingMidday(_shape(), burnerId);
        // Cover populated foil swaps and the costlier first toggle of an empty foil slot.
        if (_daily() || _shape() == 3) host.seedWriteCounts(_daily() && !paidField);

        vm.etch(address(crapsBattle), type(RequestMaintenanceSeeder).runtimeCode);
        table = RequestMaintenanceSeeder(address(crapsBattle));
        table.seedHead(DAY, _arm() ? 1 : 6, _arm() ? 1 : 0);
        if (paidField) table.seedPaidJackpot(DAY - 1);
        slot = uint64(uint256(DAY) * 8 + 1);

        // Replace only the test coordinator, using its own storage layout at the wired address.
        RequestCostCoordinator source = new RequestCostCoordinator(125_000);
        vm.etch(address(mockVRF), address(source).code);
        coordinator = RequestCostCoordinator(address(mockVRF));
        // Admin creates a dedicated subscription and adds only GAME, including on rotation.
        coordinator.seed(address(game), 1);

        if (_transition()) {
            bytes memory original = address(gnrus).code;
            vm.etch(address(gnrus), type(RequestCharitySeeder).runtimeCode);
            RequestCharitySeeder(payable(address(gnrus))).seed(13);
            vm.etch(address(gnrus), original);
            // All 20 vote reads and all 17 mutable slots flushed to fresh recipients.
            for (uint8 i; i < 20; ++i) {
                gnrus.setCharity(i, address(uint160(0xC000 + i)));
                if (i >= 3) gnrus.setCharity(i, address(uint160(0xE000 + i)));
            }
            // A funded affiliate winner with a fresh sDGNRS balance.
            // _levelScore is slot 3, with leader score/id in the upper 128 bits.
            vm.store(address(affiliate), keccak256(abi.encode(uint24(14), uint256(3))),
                bytes32((uint256(burnerId) << 224) | (uint256(1) << 128) | 1));
            (uint32 top,) = affiliate.affiliateTop(14);
            assertEq(top, burnerId, "native affiliate fixture");
        }
        if (_redemption()) {
            host.claimableBacking(10_000 ether);
            vm.deal(address(game), _funding() == 0 ? 10_000 ether : _funding() == 1 ? 0 : 1 wei);
            mockStETH.mint(address(game), 10_000 ether);
            vm.deal(address(sdgnrs), 0);
            burned = sdgnrs.totalSupply() / 100;
            vm.prank(address(game));
            sdgnrs.transferFromPool(sDGNRS.Pool.Reward, BURNER, burned);
            vm.prank(BURNER); sdgnrs.burn(burned);
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(RequestFlipSeeder).runtimeCode);
            RequestFlipSeeder(address(coinflip)).seedBacking(DAY, backingMode);
            vm.etch(address(coinflip), original);
            MockStETH implementation = new MockStETH();
            RequestStethEnvelope proxy = new RequestStethEnvelope(address(implementation));
            vm.etch(address(mockStETH), address(proxy).code);
        }
    }

    function _assertRequested() internal view {
        assertEq(coordinator.requests(address(game)), 1, "one VRF request");
        (uint48 read, uint48 write, uint256 request, uint24 day) = host.committed();
        assertTrue(read != write, "cohorts remain distinct");
        assertTrue(coordinator.commitments(request) != bytes32(0), "real-shaped commitment written");
        assertEq(day, _daily() ? DAY : 0, "request identity");
        assertFalse(game.rngComplete(), "new cohort frozen");
        assertEq(game.rngLocked(), _daily(), "daily-only lock");
        if (_daily() || _shape() == 3) {
            (uint256 boxes, uint256 bets, uint256 foils) = host.frozenCounts();
            assertEq(boxes, 1, "box count frozen");
            assertEq(bets, 1, "bet count frozen");
            assertEq(foils, _daily() && !paidField ? 1 : 0, "foils remain daily-only");
        }
        if (paidField) assertEq(table.frozenPaidCount(), 4, "paid seats and day tickets frozen");
        if (_daily() && !_transition()) assertEq(game.level(), 13, "ordinary daily does not transition");
        if (!_daily()) {
            (bool complete, bool writeSlot, uint24 early, uint256 latch) = host.ticketState();
            if (_shape() == 1) { assertFalse(complete); assertTrue(writeSlot); assertEq(latch, 1); }
            if (_shape() == 2) { assertFalse(complete); assertEq(early, 15); assertEq(latch, 2); }
            if (_shape() == 4) { assertTrue(complete); assertFalse(writeSlot); assertEq(latch, 0); }
        }
        if (_transition()) {
            assertEq(game.level(), 14, "level transitioned");
            assertEq(gnrus.currentLevel(), 14, "charity resolved");
            assertEq(gnrus.pendingEditSet(), 0, "all charity edits flushed");
            assertGt(gnrus.balanceOf(address(0xC013)), 0, "charity winner paid");
            assertGt(sdgnrs.balanceOf(BURNER), 0, "affiliate winner paid");
        }
        if (_redemption()) _assertClosed();
    }
    function _assertClosed() private view {
            (uint32 open, uint32 settling,, uint256 escrow) = sdgnrs.redemptionBatchState();
            assertEq(open, 2);
            assertEq(settling, 1);
            assertEq(escrow, 0);
            (uint128 tokens, uint96 payout,, uint96 flipEscrow,,) = sdgnrs.redemptionBatches(1);
            assertEq(tokens, burned);
            assertGt(flipEscrow, 0, "coinflip backing withdrawn");
            assertEq(address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)), payout, "whole reserve funded");
            assertEq(game.claimableWinningsOf(address(sdgnrs)), 10_000 ether - payout, "claimable debited");
            uint256 state = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint32(2), uint256(2)))));
            assertEq(uint24(state >> 128), DAY, "backing remains caught up");
    }
    /// @dev All setup is in the preceding transaction. Use --isolate for committed SSTORE
    /// values and cold accounts/slots. gasTotalUsed is gross execution, before refunds.
    function _measureRequest(Scenario scenario) private {
        this.configure(scenario);
        uint256 used = this.measureRequestAtBasefee();
        emit log_named_uint("cold_request_operation", used);
        uint256 bound = _daily() ? Bounds.RNG_DAILY_REQUEST : Bounds.RNG_MIDDAY_REQUEST;
        if (_redemption()) bound += Bounds.RNG_REDEMPTION_CLOSE;
        assertLe(used, bound, "complete cold request fits its operation bound");
        if (_shape() == 3) assertLt(host.credit(burnerId), 100 ether, "nonzero donor charge executes");
        _assertRequested();
    }

    /// @dev Keep the priced block and the request in the same isolated outer transaction.
    function measureRequestAtBasefee() external returns (uint256) {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.prank(_shape() == 3 ? BURNER : address(this));
        host.requestOnly{gas: 6_000_000}(_daily());
        return vm.lastCallGas().gasTotalUsed;
    }
    function test_ColdMidday() public { _measureRequest(Scenario.Midday); }
    function test_ColdMiddayTicketSwap() public { _measureRequest(Scenario.TicketSwap); }
    function test_ColdMiddayTicketActivation() public { _measureRequest(Scenario.TicketActivation); }
    function test_ColdMiddayCredit() public { _measureRequest(Scenario.Credit); }
    function test_ColdMiddayFinalDay() public { _measureRequest(Scenario.FinalDay); }
    function test_ColdDaily() public { _measureRequest(Scenario.Daily); }
    function test_ColdDailyTransition() public { _measureRequest(Scenario.Transition); }
    function test_ColdDailyPaidField() public { _measureRequest(Scenario.DailyPaid); }
    function test_ColdDailyPaidFieldRedemption() public { _measureRequest(Scenario.DailyPaidRedeem); }
    function test_ColdRedemptionEth() public { _measureRequest(Scenario.RedeemEth); }
    function test_ColdRedemptionSteth() public { _measureRequest(Scenario.RedeemSteth); }
    function test_ColdRedemptionMixed() public { _measureRequest(Scenario.RedeemMixed); }
    function test_ColdRedemptionStoredOnly() public { _measureRequest(Scenario.RedeemStored); }
    function test_ColdRedemptionCarryOnly() public { _measureRequest(Scenario.RedeemCarry); }
    function test_ColdDailyRedemption() public { _measureRequest(Scenario.DailyRedeem); }
    function test_ColdRedemptionCloseAlone() public {
        this.configure(Scenario.RedeemMixed);
        vm.etch(ContractAddresses.GAME_RNG_MODULE, type(RequestCloseProbe).runtimeCode);
        host.closeOnly();
        uint256 used = _isolatedExecutionGas(abi.encodeWithSignature("closeOnly()"));
        emit log_named_uint("cold_redemption_close", used);
        assertLe(used, Bounds.RNG_REDEMPTION_CLOSE);
        _assertClosed();
    }
    function test_ArmAndRequestInOneMillion() public {
        this.configure(Scenario.Arm);
        game.mineFlip{gas: 1_000_000}(0);
        emit log_named_uint("cold_arm_and_request", _isolatedExecutionGas(abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        assertEq(table.binding(slot), 1, "armed once");
        _assertRequested();
    }
    function test_ExplicitBaselineAlsoArmsAndRequests() public {
        this.configure(Scenario.Arm);
        game.mineFlip{gas: 1_000_000}(10_000);
        _assertRequested();
    }
    function test_LowGasKeepsArmWithoutAttemptingRequest() public {
        this.configure(Scenario.Arm);
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), uint64(0));
        game.mineFlip{gas: 500_000}(0);
        assertEq(table.binding(slot), 1);
        assertEq(coordinator.requests(address(game)), 0);
        assertTrue(game.rngComplete(), "old read remains certified");
    }
    function test_MultiplierDefersContinuationButNeverFirstRequest() public {
        this.configure(Scenario.Arm);
        game.mineFlip{gas: 1_000_000}(20_000);
        assertEq(table.binding(slot), 1);
        assertEq(coordinator.requests(address(game)), 0, "caller doubled continuation reserve");
        game.mineFlip{gas: 1_000_000}(type(uint32).max);
        _assertRequested();
    }
    function test_ExtremeMultiplierStillArmsFirst() public {
        this.configure(Scenario.Arm);
        game.mineFlip{gas: 1_000_000}(type(uint32).max);
        assertEq(table.binding(slot), 1, "first progress ignores calibration");
        assertEq(coordinator.requests(address(game)), 0);
    }
    function test_HeavyCloseWaitsAfterArmWithoutRequestAttempt() public {
        this.configure(Scenario.ArmRedeem);
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), uint64(0));
        game.mineFlip{gas: 1_000_000}(0);
        assertEq(table.binding(slot), 1);
        assertEq(coordinator.requests(address(game)), 0);
        (uint32 open, uint32 settling,, uint256 escrow) = sdgnrs.redemptionBatchState();
        assertEq(open, 1);
        assertEq(settling, 0);
        assertEq(escrow, burned, "unadmitted close cannot mutate escrow");
    }
    function test_HeavyCloseCanResumeWithMaximumMultiplier() public {
        this.configure(Scenario.ArmRedeem);
        game.mineFlip{gas: 1_000_000}(0);
        game.mineFlip{gas: 1_000_000}(type(uint32).max);
        _assertRequested();
    }
    function test_FundedHeavyContinuationFits() public {
        this.configure(Scenario.ArmRedeem);
        game.mineFlip{gas: 1_300_000}(0);
        emit log_named_uint("cold_arm_redemption_request", _isolatedExecutionGas(abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        _assertRequested();
    }
    function test_DailyBudgetPreservesCertificationAtLowGas() public {
        this.configure(Scenario.CertifyDailyRedeem);
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestDailyRng(uint24)", DAY), uint64(0));
        game.mineFlip{gas: 1_000_000}(0);
        assertTrue(game.rngComplete());
        assertEq(coordinator.requests(address(game)), 0);
        assertEq(game.level(), 13, "no partial daily transition");
        assertGt(gnrus.pendingEditSet(), 0, "charity edits untouched");
    }
    function test_FundedDailyContinuationFits() public {
        this.configure(Scenario.CertifyDailyRedeem);
        game.mineFlip{gas: 2_500_000}(0);
        emit log_named_uint("cold_certify_daily_redemption_request", _isolatedExecutionGas(abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        _assertRequested();
    }

    function test_DailyWithoutRedemptionAlsoUsesItsOwnBudget() public {
        this.configure(Scenario.CertifyDaily);
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestDailyRng(uint24)", DAY), uint64(0));
        game.mineFlip{gas: 1_000_000}(0);
        assertTrue(game.rngComplete());
        assertEq(coordinator.requests(address(game)), 0);
        assertEq(game.level(), 13);
    }

    function testFuzz_DailyAndGapKeepSdgnrsCurrent(uint8 daysSeed, uint256 word) public {
        uint24 gap = uint24(bound(daysSeed, 1, 29));
        // The seed window and transition into perpetual auto-rebuy use the real daily path.
        vm.startPrank(address(game));
        for (uint24 d = 1; d <= 21; ++d) {
            coinflip.processCoinflipPayouts(0, uint256(keccak256(abi.encode(word, d))), d);
            _assertBackingCursor(d);
        }
        coinflip.processCoinflipGap(word, 22, 22 + gap);
        _assertBackingCursor(21 + gap);
        vm.stopPrank();
        // Both close-time methods see start == latest and cannot walk another history.
        vm.startPrank(address(sdgnrs));
        uint256 backing = coinflip.redeemableFlipBacking();
        coinflip.withdrawRedeemedFlip(backing / 2);
        _assertBackingCursor(21 + gap);
        vm.stopPrank();
    }

    function _assertBackingCursor(uint24 expected) private view {
        uint256 state = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint32(2), uint256(2)))));
        assertEq(uint24(state >> 128), expected, "sDGNRS auto-settles each resolved day");
        assertEq(uint24(uint256(vm.load(address(coinflip), bytes32(uint256(4))))), expected);
    }

    /// @dev --isolate includes intrinsic gas in non-static outer calls, unlike the nested
    /// request probe. Remove it for comparable execution-only numbers; admission is unchanged.
    function _isolatedExecutionGas(bytes memory data) private view returns (uint256) {
        uint256 used = vm.lastCallGas().gasTotalUsed;
        uint256 intrinsic = 21_000;
        for (uint256 i; i < data.length; ++i) intrinsic += data[i] == 0 ? 4 : 16;
        return used - intrinsic;
    }
}

contract CoordinatorRequestCostTest is Test {
    RequestCostCoordinator private coordinator;
    function setUp() public {
        coordinator = new RequestCostCoordinator(0);
        coordinator.seed(address(this), 1);
    }
    function test_ColdSourceDerivedCoordinatorCost() public {
        uint256 used = this.measureCoordinator();
        emit log_named_uint("source_derived_coordinator_request", used);
        assertLt(used, 125_000, "padded model dominates request overhead");
    }
    function measureCoordinator() external returns (uint256) {
        require(msg.sender == address(this));
        coordinator.requestRandomWords(VRFRandomWordsRequest(bytes32(uint256(1234)), 1, 4, 300_000, 1, hex""));
        return vm.lastCallGas().gasTotalUsed;
    }
}
