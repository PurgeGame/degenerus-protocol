// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title YieldHarness -- Exposes distributeYieldSurplus over settable pool state.
/// @dev distributeYieldSurplus is external and unguarded (parent normally controls
///      access via delegatecall), so the test calls it directly on the harness.
contract YieldHarness is DegenerusGameJackpotModule {
    // --- Live pool setters ---
    function setCurrentPrizePool(uint256 v) external {
        _setCurrentPrizePool(v);
    }

    function setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function setPendingPools(uint128 next, uint128 future) external {
        _setPendingPools(next, future);
    }

    function setClaimablePool(uint128 v) external {
        claimablePool = v;
    }

    function setYieldAccumulator(uint256 v) external {
        yieldAccumulator = v;
    }

    function setFrozen(bool v) external {
        prizePoolFrozen = v;
    }

    function callUnfreezePool() external {
        _unfreezePool();
    }

    // --- Views ---
    function getClaimablePool() external view returns (uint256) {
        return claimablePool;
    }

    function getYieldAccumulator() external view returns (uint256) {
        return yieldAccumulator;
    }

    function getClaimable(address a) external view returns (uint256) {
        return claimableWinnings[a];
    }

    /// @dev Mirrors the live-pool liability terms in distributeYieldSurplus.
    function liveObligations() external view returns (uint256) {
        return
            _getCurrentPrizePool() +
            _getNextPrizePool() +
            claimablePool +
            _getFuturePrizePool() +
            yieldAccumulator;
    }
}

/// @title YieldSurplusSolvencyTest -- Regression for the pending-pool obligations gap.
/// @dev distributeYieldSurplus runs on the level-transition day while frozen, where
///      freeze-window revenue sits in balance but is parked in prizePoolPendingPacked
///      (outside the live pools). The obligations sum must include that pending buffer,
///      otherwise pending-backed ETH is misread as yield surplus and over-distributed,
///      leaving the protocol under-collateralized once _unfreezePool folds pending into
///      the live pools.
contract YieldSurplusSolvencyTest is Test {
    YieldHarness harness;

    // Live obligation components (sum = O).
    uint256 constant C = 100 ether; // currentPrizePool
    uint256 constant N = 50 ether; // next
    uint256 constant F = 80 ether; // future
    uint256 constant CP = 10 ether; // claimablePool
    uint256 constant YA = 5 ether; // yieldAccumulator

    // Pending buffer components (sum = P).
    uint128 constant PN = 7 ether;
    uint128 constant PF = 13 ether;

    uint256 constant O = C + N + F + CP + YA; // 245 ether
    uint256 constant P = uint256(PN) + uint256(PF); // 20 ether

    uint256 constant RNG = uint256(keccak256("yield-surplus-rng"));

    function setUp() public {
        // Put MockStETH bytecode at the STETH_TOKEN constant so steth.balanceOf
        // resolves; with no shares minted it returns 0, isolating totalBal to ETH.
        deployCodeTo("MockStETH.sol:MockStETH", ContractAddresses.STETH_TOKEN);

        harness = new YieldHarness();
        harness.setCurrentPrizePool(C);
        harness.setPrizePools(uint128(N), uint128(F));
        harness.setClaimablePool(uint128(CP));
        harness.setYieldAccumulator(YA);
        harness.setPendingPools(PN, PF);
        harness.setFrozen(true);
    }

    /// @dev REGRESSION: balance that exists only because of pending-pool deposits
    ///      (true surplus == 0) must NOT be distributed as yield.
    ///      Pre-fix, obligations omitted pending so yieldPool == P and 92% was skimmed.
    function testPendingBackedBalanceIsNotDistributed() public {
        // totalBal == O + P  =>  true surplus is exactly zero.
        vm.deal(address(harness), O + P);

        harness.distributeYieldSurplus(RNG);

        assertEq(harness.getClaimablePool(), CP, "claimablePool must not grow");
        assertEq(harness.getYieldAccumulator(), YA, "yieldAccumulator must not grow");
        assertEq(harness.getClaimable(ContractAddresses.VAULT), 0, "vault must not be credited");
        assertEq(harness.getClaimable(ContractAddresses.SDGNRS), 0, "sDGNRS must not be credited");
        assertEq(harness.getClaimable(ContractAddresses.GNRUS), 0, "charity must not be credited");
    }

    /// @dev Genuine stETH surplus on top of obligations+pending is still distributed,
    ///      and the yield base excludes pending (23% of Y, not 23% of Y+P).
    function testGenuineYieldStillDistributedExcludingPending() public {
        uint256 Y = 100 ether; // real surplus above O + P
        vm.deal(address(harness), O + P + Y);

        harness.distributeYieldSurplus(RNG);

        uint256 quarter = (Y * 2300) / 10_000; // 23 ether
        assertEq(harness.getClaimable(ContractAddresses.VAULT), quarter, "vault gets 23% of Y only");
        assertEq(harness.getClaimable(ContractAddresses.SDGNRS), quarter, "sDGNRS gets 23% of Y only");
        assertEq(harness.getClaimable(ContractAddresses.GNRUS), quarter, "charity gets 23% of Y only");
        assertEq(harness.getYieldAccumulator(), YA + quarter, "accumulator grows by 23% of Y");
        assertEq(harness.getClaimablePool(), CP + 3 * quarter, "claimablePool grows by 69% of Y");
    }

    /// @dev END-TO-END INVARIANT: balance >= obligations survives the full
    ///      freeze -> skim -> unfreeze cycle. With true surplus == 0, pre-fix the skim
    ///      would credit ~0.69*P of claimable, then unfreeze folds P into live pools,
    ///      pushing obligations above balance (insolvent). Post-fix the skim is a no-op.
    function testSolvencyHoldsAcrossFreezeUnfreezeCycle() public {
        vm.deal(address(harness), O + P); // solvent, zero true surplus

        harness.distributeYieldSurplus(RNG);
        harness.callUnfreezePool(); // pending folds into live pools

        assertEq(harness.liveObligations(), O + P, "pending folded into live obligations");
        assertGe(
            address(harness).balance,
            harness.liveObligations(),
            "contract must remain solvent after unfreeze"
        );
    }
}
