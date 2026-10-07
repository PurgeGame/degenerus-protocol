// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MiddayFrozenPoolLatch} from "./MiddayFrozenPoolLatch.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Real request, fulfilment and unaided production keeper routing across midnight.
contract SerializedMidnightProgressTest is MiddayFrozenPoolLatch {
    address private constant MINER = address(0xC4A9);
    uint256 private constant SUBSCRIBERS_LOW_GAS = 2000;
    /// @dev lootboxRngPacked (scripts/layout/golden/DegenerusGame.json); low 48 bits = miner clock.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;

    /// @dev Latch the frozen pool mid-day, deliver its word, fill the subscriber ring and cross
    ///      midnight; returns the identity of the committed cohort the crossing must retain.
    function _prepareCrossing(uint256 subscribers)
        private returns (uint256 previousRequest, uint256 committedWord, uint48 committedRead)
    {
        vm.pauseGasMetering();
        _latchMiddayAfterTarget(false);
        assertFalse(game.rngComplete(), "the requested cycle is not complete before delivery");
        _fulfillPending();
        assertFalse(_ticketsFullyProcessed(), "nonvacuity: read tickets remain");
        assertFalse(game.boxIndexComplete(RecyclingState.readBuffer(address(game))), "nonvacuity: read box frontier remains");
        uint256 existing = game.subscriberCount();
        for (uint256 i; i + existing < subscribers; ++i) {
            address owner = address(uint160(0xF00000 + i));
            vm.deal(owner, 10 ether);
            _grantSeat(owner);
            // The free mint tranche has 1,000 seats. Fill the remaining live
            // subscriber set through the real 998-seat vault tranche.
            if (afkingSubToken.balanceOf(owner) == 0) {
                vm.prank(address(vault));
                afkingSubToken.vaultMintSeats(owner, 1);
            }
            vm.prank(owner);
            game.subscribe{value: 1 ether}(address(0), false, false, 1, address(0));
        }
        if (subscribers != 0) assertEq(game.subscriberCount(), subscribers, "nonvacuity: full subscriber ring");
        // Subscribing queues indexed cover boxes, also bound to the next write cohort.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        previousRequest = mockVRF.lastRequestId();
        // The single engine entry handles both funded and unrewarded safe checkpoints.
        // Funding changes transaction boundaries, never the committed cohort's identity.
        committedWord = RecyclingState.currentWord(address(game));
        committedRead = RecyclingState.readBuffer(address(game));
        vm.resumeGasMetering();
        // The miner bounty prices measured gas above each call's first 1M at min(basefee, cap)
        // (MinerModule); Foundry's default basefee is zero, which prices every call at zero.
        vm.fee(1 gwei);
    }

    function _assertContinuation(uint256 previousRequest, uint256 committedWord, uint48 committedRead) private view {
        if (mockVRF.lastRequestId() == previousRequest) {
            assertEq(RecyclingState.currentWord(address(game)), committedWord, "continuation retains old entropy");
            assertEq(RecyclingState.readBuffer(address(game)), committedRead, "continuation retains old read buffer");
        }
    }

    function _assertCrossed(uint256 previousRequest, bool ticketWork) private view {
        assertTrue(ticketWork, "the old ticket cohort generated traits before the next request");
        assertGt(mockVRF.lastRequestId(), previousRequest, "keeper alone drained read consumers and requested the next day");
        assertTrue(game.rngLocked(), "the fresh daily request reached its lock");
        assertFalse(game.rngComplete(), "a fresh request clears the completion marker");
        assertFalse(game.boxIndexComplete(RecyclingState.readBuffer(address(game))), "fresh read buffer needs its new word");
        assertEq(RecyclingState.boxCount(address(game), RecyclingState.writeBuffer(address(game))), 0, "old read buffer's box count restarts once at seal");
    }

    function _crossMidnight(uint256 subscribers) private {
        (uint256 previousRequest, uint256 committedWord, uint48 committedRead) = _prepareCrossing(subscribers);
        vm.recordLogs();
        for (uint256 i; i < 1024 && mockVRF.lastRequestId() == previousRequest; ++i) {
            vm.prank(MINER);
            game.mineFlip{gas: 12_000_000}();
            _assertContinuation(previousRequest, committedWord, committedRead);
        }
        (uint256 bounties, uint256 callsAboveUnpaidFloor, bool ticketWork) = _scanMidnightLogs(vm.getRecordedLogs());
        // Each call's first 1M gas is unpaid (MinerModule), so exactly the calls that measured
        // more than 1M are paid. The bare crossing is one ~0.65M call and pays nothing;
        // the full subscriber ring needs calls above the floor.
        assertEq(bounties, callsAboveUnpaidFloor, "mineFlip pays for completed keeper work above the unpaid 1M");
        if (subscribers != 0) assertGt(bounties, 0, "mineFlip pays for completed keeper work");
        _assertCrossed(previousRequest, ticketWork);
    }

    /// @dev Mirror of the MinerModule pay for one call: measured gas above the unpaid first
    ///      MIN_REWARDED_GAS at min(basefee, cap), 0.3x + 0.45x per 30 minutes on the miner clock
    ///      (saturating at 2h), x2 when the daily lock was held at call start. MINER holds no pass.
    function _expectedReward(uint256 used, uint256 price, uint256 due, bool locked) private view returns (uint256) {
        if (used <= MineFlipGas.MIN_REWARDED_GAS) return 0;
        uint256 ts = vm.getBlockTimestamp();
        uint256 steps = (ts > due ? ts - due : 0) / 30 minutes;
        if (steps > 4) steps = 4;
        uint256 cap = uint256(0.5 gwei) << steps;
        uint256 bps = (3_000 + 4_500 * steps) << (locked ? 1 : 0);
        uint256 rate = block.basefee < cap ? block.basefee : cap;
        uint256 reward = (used - MineFlipGas.MIN_REWARDED_GAS) * rate * 1000 ether * bps / (price * 10_000);
        if (reward == 0) return 0;
        // Coinflip stakes are whole FLIP: at least 1 FLIP, larger rewards floored.
        return reward < 1 ether ? 1 ether : (reward / 1 ether) * 1 ether;
    }

    /// @dev The miner clock: the later of the last accepted callback and the current day reset.
    function _rewardDueAt() private view returns (uint256 due) {
        due = uint48(uint256(vm.load(address(game), bytes32(0))) >> 48);
        uint256 ts = vm.getBlockTimestamp();
        uint256 reset = ts - (ts - 82_620) % 1 days;
        if (reset > due) due = reset;
    }

    /// @dev Smallest allowance on the ladder that admits the next chunk (probed on a snapshot).
    ///      Every smaller allowance must be refused with InsufficientExecutionGas, nothing else.
    function _minimumAllowance() private returns (uint256) {
        uint256[8] memory ladder =
            [uint256(1_000_000), 1_250_000, 1_500_000, 2_000_000, 2_500_000, 3_500_000, 5_000_000, 9_500_000];
        for (uint256 s; s < ladder.length; ++s) {
            uint256 snap = vm.snapshotState();
            vm.prank(MINER);
            try game.mineFlip{gas: ladder[s]}() {
                vm.revertToState(snap);
                return ladder[s];
            } catch (bytes memory err) {
                vm.revertToState(snap);
                assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "a short allowance is refused, nothing else");
            }
        }
        revert("no allowance up to 9.5M admits the next chunk");
    }

    /// @dev One call at `allowance`: returns its measured execution gas and paid reward, and
    ///      whether it changed any Game storage word (progress). Also checks the bounty event
    ///      carries exactly the reported reward and scans for ticket work.
    function _lowGasCall(uint256 allowance)
        private returns (uint256 used, uint256 reward, bool progressed, bool ticketWork)
    {
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(MINER);
        game.mineFlip{gas: allowance}();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        for (uint256 a; a < accesses.length && !progressed; ++a) {
            // Module work runs by delegatecall: the frame's account is the module, the written
            // storage account is the Game.
            if (accesses[a].reverted) continue;
            for (uint256 k; k < accesses[a].storageAccesses.length; ++k) {
                Vm.StorageAccess memory w = accesses[a].storageAccesses[k];
                if (w.account == address(game) && w.isWrite && !w.reverted && w.previousValue != w.newValue) {
                    progressed = true;
                    break;
                }
            }
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 works;
        uint256 bountyPaid;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == keccak256("Advance(uint8,uint24)")) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                assertTrue(stage != 18, "consumer cleanup cannot report a fresh daily word applied");
            } else if (topic == keccak256("TraitsGenerated(uint32,uint256,uint32)")) {
                ticketWork = true;
            } else if (topic == keccak256("MinerBounty(uint8,address,uint256)")) {
                (, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                bountyPaid += amount;
            } else if (topic == keccak256("MinerWork(address,uint8,uint256,uint256)")) {
                (, used, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++works;
            }
        }
        assertEq(works, 1, "one MinerWork report per successful call");
        assertEq(bountyPaid, reward, "the bounty event credits exactly the reported reward");
    }

    /// @dev The crossing at 1 gwei: one realistic 9.5M call first (it measures above 1M and
    ///      pays exactly the engine formula), then the rest one admitted chunk at a time, each
    ///      call at the smallest ladder allowance that admits its next chunk. A call that
    ///      measures <= 1M execution gas pays exactly 0 and still changes engine storage; a call
    ///      that measures more pays exactly the engine formula. Both kinds must occur. The full
    ///      subscriber ring supplies work above the unpaid 1M (the bare crossing is ~0.65M).
    function _crossMidnightLowGas(uint256 subscribers) private {
        (uint256 previousRequest, uint256 committedWord, uint48 committedRead) = _prepareCrossing(subscribers);
        uint256 unpaidCalls;
        uint256 paidCalls;
        bool ticketWork;
        for (uint256 i; i < 4096 && mockVRF.lastRequestId() == previousRequest; ++i) {
            uint256 allowance = i == 0 ? 9_500_000 : _minimumAllowance();
            uint256 price = game.mintPrice();
            uint256 due = _rewardDueAt();
            bool locked = game.rngLocked();
            (uint256 used, uint256 reward, bool progressed, bool tickets) = _lowGasCall(allowance);
            ticketWork = ticketWork || tickets;
            emit log_named_uint("midnight low-gas call execution gas", used);
            if (i == 0) assertGt(used, MineFlipGas.MIN_REWARDED_GAS, "nonvacuity: the realistic first call measures above 1M");
            if (used <= MineFlipGas.MIN_REWARDED_GAS) {
                assertEq(reward, 0, "a call's first 1M execution gas is unpaid");
                assertTrue(progressed, "an unpaid call still makes engine progress");
                ++unpaidCalls;
            } else {
                if (i != 0) emit log_named_uint("minimum-admission call above the unpaid 1M", used);
                uint256 expected = _expectedReward(used, price, due, locked);
                assertGt(expected, 0, "nonvacuity: gas above 1M at 1 gwei prices to a nonzero reward");
                assertEq(reward, expected, "a call above 1M pays exactly the engine formula");
                ++paidCalls;
            }
            _assertContinuation(previousRequest, committedWord, committedRead);
        }
        emit log_named_uint("unpaid calls (<= 1M)", unpaidCalls);
        emit log_named_uint("paid calls (> 1M)", paidCalls);
        assertGt(unpaidCalls, 0, "nonvacuity: the crossing ran calls within the unpaid 1M");
        assertGt(paidCalls, 0, "nonvacuity: the crossing ran a call above the unpaid 1M");
        _assertCrossed(previousRequest, ticketWork);
    }
    /// @dev Per-call reward checks over the crossing's logs; returns the bounty count, the number
    ///      of calls that measured more than the unpaid first 1M, and whether tickets generated.
    function _scanMidnightLogs(Vm.Log[] memory logs)
        private returns (uint256 bounties, uint256 callsAboveUnpaidFloor, bool ticketWork)
    {
        uint256 bountyPaid;
        uint256 workReward;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == keccak256("Advance(uint8,uint24)")) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                assertTrue(stage != 18, "consumer cleanup cannot report a fresh daily word applied");
            } else if (topic == keccak256("TraitsGenerated(uint32,uint256,uint32)")) {
                ticketWork = true;
            } else if (topic == keccak256("MinerBounty(uint8,address,uint256)")) {
                ++bounties;
                (, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                bountyPaid += amount;
            } else if (topic == keccak256("MinerWork(address,uint8,uint256,uint256)")) {
                (, uint256 used, uint256 reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                emit log_named_uint("midnight crank execution gas", used);
                workReward += reward;
                if (used > 1_000_000) ++callsAboveUnpaidFloor;
                // Each call's first 1M gas is unpaid; completed work above it is paid.
                if (used > 1_000_000) assertGt(reward, 0, "work above the first 1M gas is paid");
                else assertEq(reward, 0, "a call's first 1M gas is unpaid");
            }
        }
        assertEq(bountyPaid, workReward, "every reported miner reward is credited as a bounty");
    }

    function test_MidnightCommitsFinalTicketLatchBeforeWaitingForBoxes() public { _crossMidnight(0); }
    function test_LowGasMidnightDrainsWithoutPayingBounty() public { _crossMidnightLowGas(SUBSCRIBERS_LOW_GAS); }
    function test_AdminPreservesVaultOwnerForStalledRequestRetry() public {
        vm.pauseGasMetering();
        _latchMiddayAfterTarget(false);
        uint256 request = mockVRF.lastRequestId();
        uint48 committedRead = RecyclingState.readBuffer(address(game));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(vault.isVaultOwner(ContractAddresses.CREATOR), "fixture creator holds the vault majority");
        assertFalse(vault.isVaultOwner(address(game)), "Game is not the vault owner");
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        assertGt(mockVRF.lastRequestId(), request, "Admin forwards the owner's authorized retry");
        assertFalse(game.rngLocked(), "retry preserves the original midday request mode");
        assertEq(RecyclingState.readBuffer(address(game)), committedRead, "retry preserves the committed cohort");
        _fulfillPending();
        for (uint256 i; i < 1024 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "after the midday cohort drains the next daily request locks");
    }
    // 2 protocol + 1,000 free + 998 vault seats is the reachable supply ceiling.
    function test_MidnightDefersSubscriberStampingUntilReadCohortCompletes() public { _crossMidnight(2000); }
}
