// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract TerminalBurnCounter {
    uint256 public burns;
    function burnAtGameOver() external { ++burns; }
    function tombstoneAtGameOver() external { ++burns; }
}

contract TerminalPayoutHarness is DegenerusGameGameOverModule, BucketSeed {
    function seed(uint24 lvl, uint256 word, address affiliateWinner) external returns (uint24 day) {
        day = _simulatedDayIndex();
        level = lvl;
        jackpotPhaseFlag = true;
        dailyIdx = day - 31;
        rngRequestDay = day;
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        _setRngTerminal();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        rngWordCurrent = word;
        terminalAffiliate = affiliateWinner;
        _recordDailyRng(day, word);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) this.seedBucket(lvl, traits[q], uint160(0x10000 + uint256(q) * 0x10000));
    }
    function seedBucket(uint24 lvl, uint8 trait, uint160 base) external { _seedBucketDistinct(lvl, trait, 512, base); }
    function runTerminalJackpotWork(uint256, uint24, uint256, uint256)
        external returns (MineFlipGas.Result memory, uint256)
    {
        require(msg.sender == address(this));
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result, uint256));
    }
    function terminalState() external view returns (bool ended, uint256 paid, uint256 time, uint256 budget, uint256 liabilities) {
        return (gameOver, _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK),
            _goRead(GO_TIME_SHIFT, GO_TIME_MASK), jackpotWork.budget, claimablePool);
    }
    function claimed(address who) external view returns (uint256) { return _claimableOf(who); }
}

contract TerminalPayoutCheckpointsTest is Test {
    function test_SetupRunsOncePotIsPinnedAndTimerWaitsForFinalQuadrant() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 100 days);
        vm.etch(ContractAddresses.GAME, type(TerminalPayoutHarness).runtimeCode);
        TerminalPayoutHarness h = TerminalPayoutHarness(ContractAddresses.GAME);
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, address(new DegenerusGameJackpotModule()).code);
        vm.etch(ContractAddresses.GNRUS, type(TerminalBurnCounter).runtimeCode);
        vm.etch(ContractAddresses.SDGNRS, type(TerminalBurnCounter).runtimeCode);
        vm.etch(ContractAddresses.COIN, type(TerminalBurnCounter).runtimeCode);
        vm.mockCall(ContractAddresses.STETH_TOKEN, abi.encodeWithSignature("balanceOf(address)", address(h)), abi.encode(uint256(0)));
        address affiliateWinner = address(0xAFF);
        uint24 day = h.seed(110, 0xAC4DE45EDBEEF, affiliateWinner);
        vm.deal(address(h), 1000 ether);
        vm.cool(address(h));
        (,, bool unlocked,) = h.runGameOverAdvance{gas: 10_000_000}(day, 110, 6_700_000);
        assertFalse(unlocked);
        (bool ended, uint256 paid, uint256 time, uint256 budget,) = h.terminalState();
        assertTrue(ended);
        assertEq(paid, 0);
        assertEq(time, 0);
        assertEq(budget, 980 ether, "affiliate allocation precedes fixed ticket pot");
        assertEq(h.claimed(affiliateWinner), 20 ether);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.deal(address(h), 1077 ether);
        uint256 calls;
        while (paid == 0 && calls++ < 8) {
            vm.cool(address(h));
            (,, unlocked,) = h.runGameOverAdvance{gas: 10_000_000}(day + 2, 110, 6_700_000);
            (, paid, time,,) = h.terminalState();
        }
        assertEq(paid, 1);
        assertTrue(unlocked);
        assertEq(time, vm.getBlockTimestamp());
        assertEq(h.claimed(affiliateWinner), 20 ether, "affiliate is paid only once");
        (,,,, uint256 liabilities) = h.terminalState();
        assertLe(liabilities, 1000 ether, "post-setup forced ETH cannot resize the draw");
        assertGt(liabilities, 999 ether);
        assertEq(TerminalBurnCounter(ContractAddresses.GNRUS).burns(), 1);
        assertEq(TerminalBurnCounter(ContractAddresses.SDGNRS).burns(), 1);
        assertEq(TerminalBurnCounter(ContractAddresses.COIN).burns(), 1);
    }
}
