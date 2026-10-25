// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {YieldHarness} from "./YieldSurplusSolvency.t.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockStETH} from "../../contracts/mocks/MockStETH.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract NativeFundingHarness is YieldHarness {
    function wire(address coordinator, uint32 callbackGas) external {
        vrfCoordinator = IVRFCoordinator(coordinator);
        vrfSubscriptionId = 1;
        vrfCallbackGasLimit = callbackGas;
    }
    function seedSdgnrs(uint128 ordinary, uint128 afking) external {
        balancesPacked[SDGNRS_WALLET_ID] = uint256(ordinary) + 1 + (uint256(afking) << 128);
        claimablePool = ordinary + afking;
    }
    function funds() external view returns (uint256 ordinary, uint256 afking, uint256 pool) {
        return (_claimableOf(SDGNRS_WALLET_ID), _afkingOf(SDGNRS_WALLET_ID), claimablePool);
    }
    function target() external view returns (uint256 t) { (, t) = _vrfNativeLevels(); }
    function lowWater() external view returns (uint256 l) { (l,) = _vrfNativeLevels(); }
    function minimum() external view returns (uint256) { return _vrfMinFulfillBalance(); }
    function surplus() external view returns (bool, uint256) {
        MineFlipGas.Meter memory unmetered;
        return _vrfYieldSurplus(unmetered, GasBounds.VRF_LEVEL_FUND_TAIL);
    }
    function readBalance() external view returns (bool, uint256) {
        MineFlipGas.Meter memory unmetered;
        return _vrfNativeBalance(unmetered, VRF_READ_RESERVE);
    }
    function refill() external {
        MineFlipGas.Meter memory unmetered;
        _refillVrfNative(unmetered, GasBounds.VRF_DAILY_REFILL_TAIL);
    }
    function freshDailyTransport() external returns (uint256 id) {
        MineFlipGas.Meter memory unmetered;
        _refillVrfNative(unmetered, GasBounds.VRF_DAILY_REFILL_TAIL);
        (bool ok, uint256 request) = _boundedVrfRequest(6, MineFlipGas.fromCall(4));
        require(ok, "request");
        return request;
    }
    function topUp() external {
        MineFlipGas.Meter memory unmetered;
        (bool ok, uint256 balance) = _vrfNativeBalance(unmetered, GasBounds.VRF_LEVEL_FUND_TAIL);
        (bool read, uint256 yield) = _vrfYieldSurplus(unmetered, GasBounds.VRF_LEVEL_FUND_TAIL);
        (, uint256 t) = _vrfNativeLevels();
        if (ok && read && balance < t) _topUpVrfNative(unmetered, GasBounds.VRF_LEVEL_FUND_TAIL, t - balance, yield);
    }
}

contract NativeFundingCoordinator {
    uint256 public nativeBalance;
    uint256 public sent;
    uint256 public requests;
    uint8 public readMode;
    uint8 public fundMode;
    bool public wideIds;
    function setWideIds(bool on) external { wideIds = on; }
    function configure(uint256 balance, uint8 read, uint8 fund) external {
        nativeBalance = balance; readMode = read; fundMode = fund;
    }
    function getSubscription(uint256) external view returns (uint96, uint96, uint64, address, address[] memory) {
        uint256 mode = readMode;
        if (mode == 1) revert("broken read");
        if (mode == 3) assembly ("memory-safe") { mstore(0, 0) return(0, 32) }
        if (mode == 4) assembly ("memory-safe") { mstore(0, 0) mstore(32, shl(96, 1)) return(0, 64) }
        return (type(uint96).max, uint96(nativeBalance), 0, address(this), new address[](0));
    }
    function fundSubscriptionWithNative(uint256) external payable {
        if (fundMode == 1) revert("broken fund");
        nativeBalance += msg.value; sent += msg.value;
    }
    function requestRandomWords(VRFRandomWordsRequest calldata req) external returns (uint256) {
        require(keccak256(req.extraArgs) == keccak256(abi.encodeWithSelector(bytes4(keccak256("VRF ExtraArgsV1")), true)), "native flag");
        return wideIds ? ++requests << 64 : ++requests;
    }
    function charge(uint256 cost) external { nativeBalance -= cost; }
}

contract VrfNativeFundingTest is Test {
    NativeFundingHarness h;
    NativeFundingCoordinator c;
    MockStETH st;
    event VrfFunded(uint24 level, uint256 fromYield, uint256 fromSdgnrs);

    function setUp() public {
        deployCodeTo("MockStETH.sol:MockStETH", ContractAddresses.STETH_TOKEN);
        st = MockStETH(payable(ContractAddresses.STETH_TOKEN));
        vm.setNonce(address(this), 10); // Avoid the fixture-pinned stETH CREATE address.
        h = new NativeFundingHarness(); c = new NativeFundingCoordinator();
        h.wire(address(c), 150_000);
        h.setCurrentPrizePool(3 ether); h.setPrizePools(2 ether, 1 ether);
        h.setPendingPools(1 ether, 1 ether); h.setFrozen(true); h.setYieldAccumulator(1 ether);
        h.seedSdgnrs(2 ether, 3 ether);
        vm.deal(address(h), 14 ether);
    }
    function _solvent() private view {
        assertGe(address(h).balance + st.balanceOf(address(h)), h.liveObligations() + 2 ether);
    }
    function _unchanged(uint256 ordinary, uint256 afking, uint256 pool) private view {
        (uint256 a, uint256 b, uint256 p) = h.funds();
        assertEq(a, ordinary); assertEq(b, afking); assertEq(p, pool);
        _solvent();
    }
    function testNumbersAndCallbackAdjustment() public {
        assertEq(h.minimum(), 0.0868 ether);
        assertEq(h.lowWater(), 0.19592 ether);
        assertEq(h.target(), 0.49352 ether);
        h.wire(address(c), 100_000);
        assertEq(h.lowWater(), 0.19592 ether); assertEq(h.target(), 0.49352 ether);
        // 150k extra callback gas: two lane minimums (0.0744) plus 60 requests (0.01116) at
        // 1 gwei stress, and 800 interval requests (0.1488) more for the target.
        h.wire(address(c), 300_000);
        assertEq(h.minimum(), 0.124 ether);
        assertEq(h.lowWater(), 0.28148 ether);
        assertEq(h.target(), 0.72788 ether);
        assertGt(h.lowWater(), h.minimum() * 2);
    }
    function testNativeSecondWordAndMalformedReads() public {
        c.configure(0.42 ether, 0, 0);
        (bool ok, uint256 bal) = h.readBalance();
        assertTrue(ok); assertEq(bal, 0.42 ether);
        for (uint8 mode = 1; mode <= 4; ++mode) {
            if (mode == 2) continue;
            c.configure(0, mode, 0); (ok,) = h.readBalance(); assertFalse(ok);
        }
    }
    /// @dev A dead coordinator without code answers nothing: the refill skips with no send.
    function testNoCodeCoordinatorSkipsRefill() public {
        h.wire(address(0xdead), 150_000);
        (bool ok,) = h.readBalance(); assertFalse(ok);
        h.refill();
        assertEq(address(0xdead).balance, 0); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testYieldFundsBeforeEitherSdgnrsBalance() public {
        vm.deal(address(h), 15 ether);
        vm.expectEmit(false, false, false, true, address(h)); emit VrfFunded(0, h.target(), 0);
        h.topUp();
        assertEq(c.sent(), h.target()); _unchanged(2 ether + 1, 3 ether, 5 ether);
        h.topUp(); assertEq(c.sent(), h.target()); _solvent();
    }
    function testPartialYieldThenClaimableThenAfking() public {
        h.seedSdgnrs(0.1 ether, 1 ether);
        vm.deal(address(h), 10.3 ether); // 9 pools + 1.1 claimable + 0.2 yield.
        uint256 target = h.target();
        h.refill();
        assertEq(c.sent(), target);
        _unchanged(1, 1 ether - (target - 0.3 ether), 1.1 ether - (target - 0.2 ether));
        assertEq(h.getYieldAccumulator(), 1 ether);
    }
    function testReportedBalanceReducesSend() public {
        c.configure(0.1 ether, 0, 0);
        h.topUp(); assertEq(c.sent(), h.target() - 0.1 ether); _solvent();
    }
    function testDistributionSplitsOnlyRemainingYield() public {
        vm.deal(address(h), 16 ether);
        uint256 share = (2 ether - h.target()) * 2300 / 10000;
        h.distributeYieldSurplus(0);
        assertEq(h.getClaimable(1), share); assertEq(h.getClaimable(3), share);
        _unchanged(2 ether + 1 + share, 3 ether, 5 ether + 3 * share);
        assertEq(h.getYieldAccumulator(), 1 ether + share);
    }
    function testStethOnlySendsZeroAndRequests() public {
        vm.deal(address(h), 0); st.mint(address(h), 15 ether);
        h.topUp(); h.refill(); assertEq(h.freshDailyTransport(), 1);
        assertEq(c.sent(), 0); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testEthLiquidityCapsPartialPull() public {
        vm.deal(address(h), 0.05 ether); st.mint(address(h), 14 ether);
        h.refill(); assertEq(c.sent(), 0.05 ether); assertEq(address(h).balance, 0);
        _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testSoftClaimReservationCanFundWhileTotalAssetsStaySolvent() public {
        vm.deal(address(h), 0.05 ether); st.mint(address(h), 13.95 ether);
        h.refill(); assertEq(c.sent(), 0.05 ether);
        _unchanged(1.95 ether + 1, 3 ether, 4.95 ether);
    }
    function testAboveLowWaterOnlyChecksSubscription() public {
        c.configure(h.lowWater(), 0, 0);
        vm.mockCallRevert(address(st), abi.encodeWithSelector(st.balanceOf.selector), "must not read");
        h.refill(); assertEq(c.sent(), 0);
        vm.clearMockedCalls(); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testBrokenReadSkipsFundingButStillRequests() public {
        uint256 requests;
        for (uint8 mode = 1; mode <= 4; ++mode) {
            if (mode == 2) continue;
            c.configure(0, mode, 0);
            assertEq(h.freshDailyTransport(), ++requests);
            assertEq(c.sent(), 0); _unchanged(2 ether + 1, 3 ether, 5 ether);
        }
    }
    /// @dev The Game keeps the low 64 bits of the ID: a zero there is refused like ID 0.
    function testRequestIdWithZeroLowWordIsRefused() public {
        c.setWideIds(true);
        vm.expectRevert(bytes("request"));
        h.freshDailyTransport();
    }
    function testBrokenFundingSkipsDebitButStillRequests() public {
        c.configure(0, 0, 1);
        assertEq(h.freshDailyTransport(), 1);
        assertEq(c.sent(), 0); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testLevelEntryBelowThresholdSendsNothingAndSplitsFullSurplus() public {
        uint256 band = h.target() - h.lowWater();
        c.configure(h.target() - band / 10 + 1, 0, 0);
        vm.deal(address(h), 16 ether);
        h.distributeYieldSurplus(0);
        assertEq(c.sent(), 0);
        uint256 share = 2 ether * 2300 / 10000;
        assertEq(h.getClaimable(1), share);
        _unchanged(2 ether + 1 + share, 3 ether, 5 ether + 3 * share);
    }
    function testLevelEntryAtThresholdFundsToTarget() public {
        uint256 band = h.target() - h.lowWater();
        c.configure(h.target() - band / 10, 0, 0);
        vm.deal(address(h), 16 ether);
        h.distributeYieldSurplus(0);
        assertEq(c.sent(), band / 10); assertEq(c.nativeBalance(), h.target());
        uint256 share = (2 ether - band / 10) * 2300 / 10000;
        assertEq(h.getClaimable(1), share);
        _unchanged(2 ether + 1 + share, 3 ether, 5 ether + 3 * share);
    }
    function test_FailedTopUpLeavesFullSurplusForSplit() public {
        vm.deal(address(h), 15 ether); c.configure(0, 0, 1);
        h.distributeYieldSurplus(0);
        assertEq(c.sent(), 0); assertEq(h.getClaimable(1), 0.23 ether);
        _unchanged(2.23 ether + 1, 3 ether, 5.69 ether);
    }
    function testBrokenStethReadNeverUsesSdgnrsBeforeUnknownYield() public {
        vm.mockCallRevert(address(st), abi.encodeWithSelector(st.balanceOf.selector), "broken");
        h.refill(); assertEq(c.sent(), 0);
        vm.clearMockedCalls(); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    /// @dev A stETH without code or with a short answer skips the funding and distribution.
    function testDeadStethSkipsFundingWithoutLedgerChange() public {
        bytes memory code = address(st).code;
        vm.etch(address(st), "");
        (bool ok,) = h.surplus(); assertFalse(ok);
        h.refill(); assertEq(c.sent(), 0);
        vm.etch(address(st), code); _unchanged(2 ether + 1, 3 ether, 5 ether);
        vm.mockCall(address(st), abi.encodeWithSelector(st.balanceOf.selector), hex"1234");
        (ok,) = h.surplus(); assertFalse(ok);
        h.refill(); assertEq(c.sent(), 0);
        vm.clearMockedCalls(); _unchanged(2 ether + 1, 3 ether, 5 ether);
    }
    function testScheduledWorstCaseIntervalNeverRefills() public {
        c.configure(h.target(), 0, 0);
        uint256 cost = 0.000372 ether;
        for (uint256 day; day < 33; ++day) {
            h.refill(); assertEq(c.sent(), 0);
            for (uint256 request; request < 12; ++request) c.charge(cost);
        }
        for (uint256 request; request < 4; ++request) c.charge(cost);
        h.refill(); assertEq(c.sent(), 0); assertGt(c.nativeBalance(), h.lowWater());
        _solvent();
    }
    function testFuzzFundingPreservesSolvency(uint96 yield, uint96 ordinary, uint96 afking, uint96 liquid) public {
        uint256 y = bound(yield, 0, 3 ether);
        uint128 o = uint128(bound(ordinary, 0, 3 ether));
        uint128 a = uint128(bound(afking, 0, 3 ether));
        h.seedSdgnrs(o, a);
        uint256 assets = 9 ether + uint256(o) + a + y;
        uint256 eth = bound(liquid, 0, assets);
        vm.deal(address(h), eth); st.mint(address(h), assets - eth);
        h.refill(); _solvent();
        assertLe(c.sent(), eth); assertLe(c.sent(), h.target());
        (uint256 afterOrdinary, uint256 afterAfking, uint256 pool) = h.funds();
        assertEq(pool, afterOrdinary - 1 + afterAfking);
        if (c.sent() <= y) { assertEq(afterOrdinary, uint256(o) + 1); assertEq(afterAfking, a); }
    }
}
