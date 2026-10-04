// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @title MinerRewardMinimum — whole-FLIP mining rewards with a 1 FLIP floor on positive pay
/// @notice `mineFlip` prices its bounty on measured gas above the unpaid first
///         MIN_REWARDED_GAS; the figure that reaches Coinflip is then normalized to the
///         whole-FLIP stake lanes: 0 stays 0, anything positive below 1 FLIP pays 1 FLIP,
///         anything larger floors to whole FLIP. MinerBounty and MinerWork report the
///         normalized award, which equals the stake Coinflip credits below the daily cap.
/// @dev One real daily advance is prepared in setUp and replayed from a snapshot at
///      different base fees. The call's measured gas does not depend on the fee, so the
///      raw reward is a known multiple of the fee and the fee selects the raw band.
contract MinerRewardMinimum is DeployProtocol {
    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant BASEFEE_CAP = 0.5 gwei;

    address internal keeper;
    uint256 internal snapshot;
    uint256 internal rawPerWei;
    uint256 internal measuredAtOne;
    bool internal sawUnpaidPrep;

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("minimum_keeper");
        vm.deal(keeper, 100 ether);
        uint256 dayStart = ((block.timestamp - 82_620) / 1 days + 1) * 1 days + 82_620;
        vm.warp(dayStart + 1 minutes);
        vm.fee(1 gwei);
        // The day's preparation and request. Any call whose measured gas stays inside the
        // unpaid first million pays exactly zero, nonzero base fee or not.
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            uint256 pre = coinflip.coinflipAmount(keeper);
            vm.recordLogs();
            vm.prank(keeper);
            game.mineFlip();
            (uint256 used, uint256 reward, uint256 bounty, uint256 bountyCount) = _work(vm.getRecordedLogs());
            if (used <= MineFlipGas.MIN_REWARDED_GAS) {
                sawUnpaidPrep = true;
                assertEq(reward, 0, "inside the unpaid first million: zero reward");
                assertEq(bountyCount, 0, "no MinerBounty inside the unpaid first million");
                assertEq(coinflip.coinflipAmount(keeper), pre, "no credit inside the unpaid first million");
            } else {
                assertEq(reward, bounty, "paid prep call: both events report the same award");
                assertEq(coinflip.coinflipAmount(keeper) - pre, reward, "paid prep call credits the award");
            }
        }
        assertTrue(game.rngLocked(), "the request took the daily lock");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256("minimum_word")));

        // Calibrate on a throwaway snapshot: at a 1 wei base fee the raw reward is one fee-unit
        // of pay. The run is reverted and the figures written afterwards, so the replay snapshot
        // below carries them.
        snapshot = vm.snapshotState();
        (uint256 measured,,,) = _advance(1);
        vm.revertToState(snapshot);
        measuredAtOne = measured;
        assertGt(measured, MineFlipGas.MIN_REWARDED_GAS, "non-vacuity: the advance measures past the unpaid million");
        rawPerWei = _rawPay(measured, 1);
        snapshot = vm.snapshotState();
        assertGt(rawPerWei, 0, "non-vacuity: a 1 wei fee prices a positive raw reward");
        assertLt(rawPerWei, 1 ether, "fixture: the 1 wei raw reward is below 1 FLIP");
    }

    /// @dev Replay the prepared advance at `fee` and return (measured gas, MinerWork reward,
    ///      MinerBounty amount, stake credited).
    function _advance(uint256 fee) internal returns (uint256 measured, uint256 reward, uint256 bounty, uint256 credited) {
        vm.revertToState(snapshot);
        vm.fee(fee);
        uint256 pre = coinflip.coinflipAmount(keeper);
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        uint256 count;
        (measured, reward, bounty, count) = _work(vm.getRecordedLogs());
        if (count == 0) assertEq(reward, 0, "a call without MinerBounty reports zero reward");
        else assertEq(reward, bounty, "MinerWork and MinerBounty report the same normalized award");
        credited = coinflip.coinflipAmount(keeper) - pre;
        assertEq(credited, reward, "below the daily cap the credited stake is the reported award");
    }

    function _work(Vm.Log[] memory logs) internal returns (uint256 used, uint256 reward, uint256 bounty, uint256 bountyCount) {
        uint256 works;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == MINER_WORK_SIG) {
                (, used, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++works;
            } else if (logs[i].topics[0] == MINER_BOUNTY_SIG) {
                (, bounty) = abi.decode(logs[i].data, (uint8, uint256));
                ++bountyCount;
            }
        }
        assertEq(works, 1, "one MinerWork per mineFlip");
        assertLe(bountyCount, 1, "at most one MinerBounty per mineFlip");
    }

    /// @dev The raw (pre-normalization) pay: locked at call start (x2) on a fresh callback clock (0.3x).
    function _rawPay(uint256 measured, uint256 fee) internal view returns (uint256) {
        uint256 rate = fee < BASEFEE_CAP ? fee : BASEFEE_CAP;
        return (measured - MineFlipGas.MIN_REWARDED_GAS) * rate * PRICE_COIN_UNIT * 6_000 / (game.mintPrice() * 10_000);
    }

    function _normalized(uint256 raw) internal pure returns (uint256) {
        if (raw == 0) return 0;
        if (raw < 1 ether) return 1 ether;
        return (raw / 1 ether) * 1 ether;
    }

    function test_UnderTheUnpaidMillionPaysZeroAtNonzeroBaseFee() public view {
        assertTrue(sawUnpaidPrep, "non-vacuity: a real mineFlip measured inside the unpaid first million");
    }

    function test_ZeroBaseFeePaysZero() public {
        (uint256 measured, uint256 reward,, uint256 credited) = _advance(0);
        assertGt(measured, MineFlipGas.MIN_REWARDED_GAS, "the work is paid-eligible");
        assertEq(reward, 0, "a zero raw reward stays zero");
        assertEq(credited, 0);
    }

    function test_OneWeiRawRewardPaysOneFlip() public {
        (uint256 measured, uint256 reward,,) = _advance(1);
        assertEq(measured, measuredAtOne, "the fee does not change the measured gas");
        assertEq(reward, 1 ether, "a positive sub-FLIP raw reward pays 1 FLIP");
    }

    function test_JustBelowOneFlipPaysOneFlip() public {
        uint256 fee = (1 ether - 1) / rawPerWei;
        uint256 raw = _rawPay(measuredAtOne, fee);
        assertLt(raw, 1 ether, "fixture: raw is just below 1 FLIP");
        assertGe(raw + rawPerWei, 1 ether, "fixture: one more fee-unit would reach 1 FLIP");
        (, uint256 reward,,) = _advance(fee);
        assertEq(reward, 1 ether);
    }

    function test_OneFlipAndDustPaysOneFlip() public {
        uint256 fee = 1 ether / rawPerWei + 1;
        uint256 raw = _rawPay(measuredAtOne, fee);
        assertGe(raw, 1 ether, "fixture: raw reached 1 FLIP");
        assertLt(raw, 2 ether, "fixture: raw holds sub-FLIP dust");
        (, uint256 reward,,) = _advance(fee);
        assertEq(reward, 1 ether, "dust above 1 FLIP floors away");
        assertEq(reward, _normalized(raw));
        // Exactly 1 FLIP raw is reachable only when the per-wei pay divides 1 FLIP.
        if (1 ether % rawPerWei == 0) {
            (, uint256 exact,,) = _advance(1 ether / rawPerWei);
            assertEq(exact, 1 ether, "exactly 1 FLIP raw pays 1 FLIP");
        }
    }

    function test_TwoFlipPaysTwoFlip() public {
        uint256 fee = 2 ether / rawPerWei + (2 ether % rawPerWei == 0 ? 0 : 1);
        uint256 raw = _rawPay(measuredAtOne, fee);
        assertGe(raw, 2 ether);
        assertLt(raw, 3 ether);
        assertLe(fee, BASEFEE_CAP, "fixture: the fee stays under the reward cap");
        (, uint256 reward,,) = _advance(fee);
        assertEq(reward, 2 ether, "whole FLIP floors, no minimum involved");
    }

    function testFuzz_RewardIsTheNormalizedRawPay(uint64 fee) public {
        fee = uint64(bound(fee, 0, BASEFEE_CAP));
        uint256 raw = _rawPay(measuredAtOne, fee);
        (uint256 measured, uint256 reward,,) = _advance(fee);
        assertEq(measured, measuredAtOne);
        assertEq(reward, _normalized(raw), "reward == normalize(raw)");
        // The rounding subsidy per paid call is bounded by one FLIP.
        assertLe(reward, raw + 1 ether);
    }
}
