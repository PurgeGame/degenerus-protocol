// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenesisGasBase, DegenesisGasHost, DegenesisSettleGas, DegenesisCharitySeeder} from "./DegenesisGas.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {RequestCostCoordinator} from "../helpers/RequestCostCoordinator.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MineFlipAdmission} from "../fuzz/helpers/MineFlipAdmission.sol";

// =========================================================================
// Settlement: the largest chunk and the largest orders
// =========================================================================

/// @dev A full 128-order chunk of pass orders to fresh wallets closing the seventh cohort with the
///      burn: every order takes the costliest non-sDGNRS branch (a fresh CrapsBattle pass credit).
///      A 128-order chunk of capped pass orders cannot exist: the cohort's volume factor
///      K / (K + V) spreads at most about K's worth of FLIP over the cohort, so only a few orders
///      of one cohort can each exceed the twelve-high cap (DegenesisSettlePassCapGas holds four).
contract DegenesisSettlePassChunkGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Pass; }
    function _orders() internal pure override returns (uint256) { return 128; }
    function _cohort() internal pure override returns (uint256) { return 7; }
}

/// @dev One order at the per-order bound (2^38 - 1 units) on each branch it can take.
contract DegenesisSettleMaxUnitsPassCapGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.PassCap; }
    function _orders() internal pure override returns (uint256) { return 1; }
    function _units() internal pure override returns (uint256) { return (uint256(1) << 38) - 1; }
}

contract DegenesisSettleMaxUnitsCreditGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Credit; }
    function _orders() internal pure override returns (uint256) { return 1; }
    function _cohort() internal pure override returns (uint256) { return 7; }
    function _units() internal pure override returns (uint256) { return (uint256(1) << 38) - 1; }
}

contract DegenesisSettleMaxUnitsDgnrsGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.Dgnrs; }
    function _orders() internal pure override returns (uint256) { return 1; }
    function _units() internal pure override returns (uint256) { return (uint256(1) << 38) - 1; }
}

/// @dev Eight minimum orders (0.01 ETH, 100 units) on the sDGNRS branch with zero inventory:
///      every award falls back to the WWXRP consolation.
contract DegenesisSettleMinUnitsEmptyGas is DegenesisSettleGas {
    function _kind() internal pure override returns (Kind) { return Kind.DgnrsEmpty; }
    function _orders() internal pure override returns (uint256) { return 8; }
    function _units() internal pure override returns (uint256) { return 100; }
}

/// @title DegenesisSettleBoundsFuzz -- the settlement stage never reverts on its frozen inputs
/// @notice A cohort built at the input bounds: 1 to 300 orders (across the 128-order chunk and the
///         three-lane slot boundaries), each order's units drawn from the 0.01 ETH minimum, one
///         unit above it, a random amount and the 2^38 - 1 per-order bound, seconds from 0, the
///         six-hour cap and random, payees from a small registered set (repeats inside one flush
///         batch), any of the seven cohorts, any bound word, and the inventory full, drained or
///         one wei. The production worker runs under the engine's first-progress context at an
///         allowance drawn from zero to 30M: every call must return, progress and advance the
///         cursor, and the cohort must close with every order resolved exactly once.
contract DegenesisSettleBoundsFuzz is DegenesisGasBase {
    uint256 internal constant MAX_UNITS = (uint256(1) << 38) - 1;
    bytes32 internal constant RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");

    uint32[] internal payees;

    function setUp() public {
        _deployProtocol();
        _etchHost();
        for (uint256 i; i < 6; ++i) {
            uint32 id = host.hostWallet(address(uint160(0xB0D5000 + i)));
            if (i >= 3) {
                uint32 main = host.hostWallet(address(uint160(0xB0D6000 + i)));
                host.hostOwner(id, main);
            }
            payees.push(id);
        }
    }

    /// @dev The sDGNRS Degenesis pool balance (vm.store), keeping sDGNRS's own token balance equal
    ///      to the pool sum (DegenesisHarness._setDegPool). Zero and one-wei inventory only.
    function _setDegPool(uint256 x) internal {
        uint256 old = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis);
        bytes32 balSlot = keccak256(abi.encode(address(sdgnrs), uint256(1)));
        uint256 bal = uint256(vm.load(address(sdgnrs), balSlot));
        vm.store(address(sdgnrs), balSlot, bytes32(bal + x - old));
        uint256 w = uint256(vm.load(address(sdgnrs), bytes32(uint256(4))));
        vm.store(address(sdgnrs), bytes32(uint256(4)), bytes32((w >> 128 << 128) | x));
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), x, "setDegPool: slot mismatch");
    }

    /// forge-config: default.fuzz.runs = 48
    /// forge-config: deep.fuzz.runs = 512
    function testFuzz_SettleNeverRevertsAtBounds(uint256 seed) public {
        uint256 n = 1 + seed % 300;
        uint256 c = 1 + (seed >> 16) % 7;
        uint256 word = uint256(keccak256(abi.encode(seed, "word"))) | 1;
        uint256 volume;
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 shape = r % 4;
            uint256 units = shape == 0 ? 100 : shape == 1 ? 101 : shape == 2 ? 100 + (r >> 8) % 10_000_000 : MAX_UNITS;
            uint256 s = (r >> 64) % 3;
            uint256 secs = s == 0 ? 0 : s == 1 ? 6 hours : (r >> 96) % (6 hours + 1);
            host.hostOrder(c, i, payees[(r >> 128) % payees.length], units, secs);
            volume += units;
        }
        host.hostCohort(c, volume, n, true);
        host.hostClosed(uint8(c - 1));
        uint256 target = (c <= 3 ? uint256(20_000_000_000) : uint256(10_000_000_000)) * 1e12 * 5 / 2;
        uint256 cap = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) * 2 / 3;
        uint256 q = cap < target ? cap : target;
        host.hostActive(q, uint24(GameTimeLib.DEGENESIS_START_DAY + c), 0);
        host.hostWord(word);
        uint256 inventory = (seed >> 32) % 3;
        if (inventory == 1) _setDegPool(0);
        else if (inventory == 2) _setDegPool(1);

        vm.recordLogs();
        uint256 calls;
        uint256 cursor;
        bool closed;
        while (!closed) {
            uint256 allowance = uint256(keccak256(abi.encode(seed, "gas", calls))) % 30_000_001;
            uint256 budget = MineFlipGas.budget(allowance, 10_000, true);
            (bool progressed, bool done,) = host.hostRun{gas: allowance + 2_000_000}(budget);
            assertTrue(progressed, "every first-progress call progresses");
            (uint8 closedCount, uint256 active,,) = host.hostState(c);
            uint256 next = uint32(active >> 184);
            closed = done;
            if (closed) assertEq(closedCount, c, "the cohort closed");
            else assertGt(next, cursor, "the cursor advanced");
            cursor = next;
            ++calls;
            assertLe(calls, n + 1, "settlement terminates");
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 resolvedCount;
        uint256 closes;
        bool[] memory seen = new bool[](n);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == RESOLVED) {
                (, uint32 index,,,,,,) =
                    abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
                assertFalse(seen[index], "an order resolves once");
                seen[index] = true;
                ++resolvedCount;
            } else if (logs[i].topics[0] == CLOSED) {
                ++closes;
            }
        }
        assertEq(resolvedCount, n, "every order resolved");
        assertEq(closes, 1, "one close");
    }
}

// =========================================================================
// The daily request's Degenesis step: bounds fuzz
// =========================================================================

/// @title DegenesisPrepareBoundsFuzz -- the request's split and pricing never revert, and fit
/// @notice Any subset of the seven cohorts nonempty (zero-volume days included), any split flags,
///         volumes from one unit to 2^46, any number already closed, an active cohort or none,
///         the inventory full or drained, and any request day: prepareDegenesis returns, and its
///         cold cost fits DEGENESIS_REQUEST_GAS on Osaka and on the no-reservoir Glamsterdam total.
contract DegenesisPrepareBoundsFuzz is DegenesisGasBase {
    function setUp() public {
        _deployProtocol();
        _etchHost();
    }

    /// forge-config: default.fuzz.runs = 32
    /// forge-config: deep.fuzz.runs = 256
    function testFuzz_PrepareNeverRevertsAndFits(uint256 seed) public {
        uint8 closed = uint8(seed % 7);
        uint256 reserved;
        for (uint256 c = closed + 1; c <= 7; ++c) {
            uint256 r = uint256(keccak256(abi.encode(seed, c)));
            if (r & 3 == 0) continue; // a zero-volume day
            uint256 units = r >> 8 & 1 == 0 ? 1 + (r >> 16) % 1_000_000 : 1 + (r >> 16) % (uint256(1) << 46);
            bool split = (r >> 200) & 7 == 0;
            host.hostCohort(c, units, 1 + (r >> 120) % 1000, split);
            if (!split) reserved += units * 0.0001 ether;
        }
        host.hostReserve(reserved);
        host.hostClosed(closed);
        if ((seed >> 64) & 3 == 0) host.hostActive(1 ether, uint24(GameTimeLib.DEGENESIS_START_DAY + closed + 1), 0);
        if ((seed >> 66) & 3 == 0) {
            vm.prank(address(game));
            sdgnrs.transferFromPool(sDGNRS.Pool.Degenesis, address(0xBEEF), type(uint256).max);
        }
        uint24 day = uint24(GameTimeLib.DEGENESIS_START_DAY + (seed >> 80) % 40);
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostPrepare, (day)));
        emit log_named_uint("prepare worst (osaka vs no-reservoir)", _worst(m));
        assertLe(_worst(m), GasBounds.DEGENESIS_REQUEST_GAS, "request addition covers the Degenesis step");
        (uint8 before,,,) = host.hostState(1);
        host.hostPrepare(day);
        (uint8 after_, uint256 active,,) = host.hostState(1);
        assertGe(after_, before, "closes only move forward");
        assertLe(after_, 7, "at most seven closed");
        if (after_ == 7) assertEq(active, 0, "nothing active after the seventh close");
    }
}

/// @title DegenesisPrepareSweepGas -- every nonempty-cohort pattern at the request, cold
/// @notice All 128 subsets of nonempty cohorts with nothing closed and nothing split (zero-volume
///         days close, nonempty days split, the first nonempty sealed day is priced; the empty set
///         closes all seven and burns). Every pattern is measured cold on Osaka and repriced
///         for the no-reservoir Glamsterdam total: an Osaka ranking need not preserve the
///         state-gas ranking. Every figure must fit DEGENESIS_REQUEST_GAS.
contract DegenesisPrepareSweepGas is DegenesisGasBase {
    function setUp() public {
        _deployProtocol();
        _etchHost();
        host.hostPools(0, false, 0);
        host.hostBudget(0, 0);
    }

    function _seedPattern(uint256 mask) internal {
        uint256 reserved;
        for (uint256 c = 1; c <= 7; ++c) {
            if ((mask >> (c - 1)) & 1 == 0) continue;
            host.hostCohort(c, 1_000_000 + c, 100, false);
            reserved += (1_000_000 + c) * 0.0001 ether;
        }
        host.hostReserve(reserved);
    }

    /// @dev Match measureCall's nested host frame without recording any accesses. Once a
    ///      replay has been recorded, this Forge version can retain warmth across snapshots.
    function measurePrepareOsaka() external returns (uint256 used) {
        require(msg.sender == address(this), "fixture self-call");
        _cool();
        host.hostPrepare{gas: 5_000_000}(60);
        used = vm.lastCallGas().gasTotalUsed;
    }

    function test_EveryCohortPatternFits() public {
        // Capture every uninstrumented cold call before the first recorded replay. Use those
        // costs with each replay's schedule delta, rather than its potentially warmed gas.
        uint256[128] memory osakaOf;
        for (uint256 mask; mask < 128; ++mask) {
            uint256 snap = vm.snapshotState();
            _seedPattern(mask);
            osakaOf[mask] = this.measurePrepareOsaka();
            vm.revertToStateAndDelete(snap);
        }
        uint256 peakOsaka;
        uint256 peakOsakaMask;
        uint256 peak;
        uint256 peakMask;
        Measured memory peakMeasurement;
        for (uint256 mask; mask < 128; ++mask) {
            uint256 snap = vm.snapshotState();
            _seedPattern(mask);
            Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostPrepare, (60)));
            vm.revertToStateAndDelete(snap);
            int256 scheduleDelta = int256(m.exec) - int256(m.osaka);
            m.osaka = osakaOf[mask];
            m.exec = uint256(int256(m.osaka) + scheduleDelta);
            if (m.osaka > peakOsaka) (peakOsaka, peakOsakaMask) = (m.osaka, mask);
            uint256 worst = _worst(m);
            if (worst > peak) {
                (peak, peakMask) = (worst, mask);
                peakMeasurement = m;
            }
        }
        emit log_named_uint("peak Osaka over all 128 patterns", peakOsaka);
        emit log_named_uint("peak Osaka pattern (bit c-1 = cohort c nonempty)", peakOsakaMask);
        emit log_named_uint("peak repriced over all 128 patterns", peak);
        emit log_named_uint("its pattern", peakMask);
        _log("worst request pattern", peakMeasurement);
        assertLe(peak, GasBounds.DEGENESIS_REQUEST_GAS, "every pattern fits the request addition");
        assertLe((peak * 120 + 99) / 100, GasBounds.DEGENESIS_REQUEST_GAS, "request addition retains 20% margin");
    }
}

// =========================================================================
// The daily request with every cohort unsplit (a stall across the whole sale)
// =========================================================================

/// @title DegenesisStallRequestGas -- the first request after a stall across the whole sale
/// @notice No request ran during the sale: all seven cohorts are sealed and unsplit when the first
///         post-sale request lands. That request splits all seven, prices cohort 1 and latches the
///         early turbo with the level increment, with the heavy request legs loaded as
///         DegenesisDayNineRequestGas loads them (all 20 charity votes, a funded affiliate winner,
///         the 125k-floor coordinator). Measured cold through the production RNG module against
///         RNG_DAILY_REQUEST + DEGENESIS_REQUEST_GAS.
abstract contract DegenesisStallRequestGas is DegenesisGasBase {
    address internal constant WINNER = address(0xA11CE);
    RequestCostCoordinator internal coordinator;

    /// @dev Days after the main launch day the request lands on.
    function _late() internal pure virtual returns (uint256);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + (8 + _late()) * 1 days);
        _quietCrapsTable();
        uint32 winnerId = _giveWalletId(WINNER);
        _etchHost();
        host.hostRequestSeed(1000 ether);
        uint256 reserved;
        for (uint256 c = 1; c <= 7; ++c) {
            host.hostCohort(c, 1_000_000 + c, 100, false);
            reserved += (1_000_000 + c) * 0.0001 ether;
        }
        host.hostReserve(reserved);
        host.hostClosed(0);
        host.hostBudget(0, 0);
        RequestCostCoordinator source = new RequestCostCoordinator(125_000);
        vm.etch(address(mockVRF), address(source).code);
        coordinator = RequestCostCoordinator(address(mockVRF));
        coordinator.seed(address(game), 1);
        bytes memory original = address(gnrus).code;
        vm.etch(address(gnrus), type(DegenesisCharitySeeder).runtimeCode);
        DegenesisCharitySeeder(payable(address(gnrus))).seed(0);
        vm.etch(address(gnrus), original);
        for (uint8 i; i < 20; ++i) {
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            gnrus.setCharity(i, address(uint160(0xC000 + i)));
            if (i >= 3) {
                vm.prank(ContractAddresses.OWNER_GOVERNANCE);
                gnrus.setCharity(i, address(uint160(0xE000 + i)));
            }
        }
        vm.store(address(affiliate), bytes32(PeripheralSlots.AFF_LEVEL_SCORE + uint256(uint24(1))), bytes32((uint256(1) << 232) | (uint256(winnerId) << 163) | (uint256(1) << 128) | 1));
    }

    function test_StallRequestSplitsAllSeven() public {
        vm.fee(1 gwei);
        Measured memory m = _measure(abi.encodeCall(DegenesisGasHost.hostRequestOnly, ()));
        _log("first request after a stall across the sale: 7 splits, price, turbo", m);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        host.hostRequestOnly();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint24 lvl, bool lastDay,) = host.hostRequestState();
        (uint8 closed, uint256 active,,) = host.hostState(1);
        uint256 splitFlags;
        for (uint256 c = 1; c <= 7; ++c) {
            (,,, uint256 header) = host.hostState(c);
            if (header & (uint256(1) << 80) != 0) ++splitFlags;
        }
        vm.revertToStateAndDelete(snap);
        uint256 splits;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == keccak256("DegenesisCohortSplit(uint8,uint256)")) {
                ++splits;
            }
        }
        assertEq(splits, 7, "seven cohorts split in the request");
        assertEq(splitFlags, 7, "seven split flags set");
        assertEq(closed, 0, "nothing closed: cohort 1 is priced");
        assertTrue(active != 0, "cohort 1 priced");
        assertTrue(lastDay && lvl == 1, "turbo latched and the level incremented");
        uint256 bound = GasBounds.RNG_DAILY_REQUEST + GasBounds.DEGENESIS_REQUEST_GAS;
        emit log_named_uint("admission RNG_DAILY_REQUEST + DEGENESIS_REQUEST_GAS", bound);
        assertLe(_worst(m), bound, "request admission");
        assertLt(bound, 10_000_000, "request checkpoint under 10M");
    }
}

contract DegenesisStallRequestDayNineGas is DegenesisStallRequestGas {
    function _late() internal pure override returns (uint256) { return 0; }
}

contract DegenesisStallRequestDayTwelveGas is DegenesisStallRequestGas {
    function _late() internal pure override returns (uint256) { return 3; }
}

// =========================================================================
// Terminal setup during the sale, through the production engine
// =========================================================================

/// @title DegenesisTerminalSetupEngineGas -- game over during the sale, the setup call cold
/// @notice Orders on all seven sale days through real purchases and no mineFlip at all, so every
///         cohort is unsplit when the deadman fires. The engine runs the ending until the next
///         call is the one whose terminal setup splits the cohorts and releases the Degenesis
///         funds; that call is measured cold (Osaka and no-reservoir Glamsterdam) against the
///         setup admission: TERMINAL_SETUP + DEGENESIS_TERMINAL_GAS + TERMINAL_TAIL with the phase
///         pre-check, the engine boundary and return.
contract DegenesisTerminalSetupEngineGas is DegenesisGasBase {
    bytes32 internal constant SPLIT = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant RELEASED = keccak256("DegenesisFundsReleased(uint256,uint256)");
    address internal miner;

    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 100_000 ether);
        miner = makeAddr("terminal-miner");
        _giveWalletId(miner);
        for (uint256 c = 1; c <= 7; ++c) {
            vm.warp((uint256(GameTimeLib.DEGENESIS_START_DAY + c - 1) - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME + 2 hours);
            for (uint256 k; k < 3; ++k) {
                address p = makeAddr(string(abi.encode("terminal-buyer", c, k)));
                vm.deal(p, 1_000 ether);
                vm.prank(p);
                game.purchase{value: 4.08 ether}(0, 0, BoxOrderLib.boCustoms(1, 4.08 ether), bytes32(0),
                    MintPaymentKind.DirectEth, false);
                uint256 amount = k == 0 ? 0.01 ether : k == 1 ? 0.0101 ether : 1 ether;
                vm.prank(p);
                game.buyDegenesisBox{value: amount}(0, amount);
            }
        }
        vm.warp(block.timestamp + 32 days);
        require(game.livenessTriggered(), "fixture: deadman");
    }

    function _cool() internal override {
        super._cool();
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(address(gnrus));
    }

    /// @dev Whether the next engine call emits the splits (trial in a snapshot).
    function _nextCallSplits() internal returns (bool splits, bool ok) {
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.prank(miner);
        (ok,) = address(game).call{gas: 30_000_000}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.revertToStateAndDelete(snap);
        // A reverted call has no effect; forge still records the logs it emitted.
        if (!ok) return (false, false);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == SPLIT) splits = true;
        }
    }

    function test_TerminalSetupDuringSaleFits() public {
        for (uint256 i; i < 40; ++i) {
            uint256 req = mockVRF.lastRequestId();
            if (req != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(req);
                if (!fulfilled) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("terminal", req))));
            }
            (bool splits, bool ok) = _nextCallSplits();
            if (splits) {
                Measured memory m = _measureCall(address(game), abi.encodeWithSignature("mineFlip(uint32)", uint32(0)), miner);
                _log("engine call with terminal setup during the sale (7 unsplit cohorts)", m);
                vm.recordLogs();
                vm.prank(miner);
                game.mineFlip(0);
                Vm.Log[] memory logs = vm.getRecordedLogs();
                uint256 n;
                uint256 released;
                for (uint256 j; j < logs.length; ++j) {
                    if (logs[j].topics.length == 0) continue;
                    if (logs[j].topics[0] == SPLIT) ++n;
                    if (logs[j].topics[0] == RELEASED) ++released;
                }
                assertEq(n, 7, "all seven cohorts split at terminal setup");
                assertEq(released, 1, "the Degenesis funds released");
                assertTrue(game.gameOver(), "the setup latched game over");
                uint256 bound = MineFlipAdmission.gross(GasBounds.TERMINAL_SETUP + GasBounds.DEGENESIS_TERMINAL_GAS
                    + GasBounds.TERMINAL_TAIL + 250_000);
                emit log_named_uint("setup checkpoint admission, grossed through the engine", bound);
                assertLe(_worst(m), bound, "terminal setup call within its admission");
                assertLt(GasBounds.TERMINAL_SETUP + GasBounds.DEGENESIS_TERMINAL_GAS + GasBounds.TERMINAL_TAIL,
                    10_000_000, "setup checkpoint under 10M");
                return;
            }
            vm.prank(miner);
            (bool mined,) = address(game).call{gas: 30_000_000}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            ok; mined;
        }
        fail("terminal setup never reached");
    }
}

// =========================================================================
// The purchase battle lock's skip path on the first sale days
// =========================================================================

/// @title DegenesisBattleSkipRequestGas -- the request on a day before the first window day
/// @notice On Degenesis day 1 (day index 2) the purchase battle has no window yet:
///         lockJackpotBattle returns false and the request leaves the battle-pending bit clear,
///         so the daily phase never waits on a battle stage. The request is measured cold, then
///         the day seals with no battle stage.
contract DegenesisBattleSkipRequestGas is DegenesisGasBase {
    address internal miner;

    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 100_000 ether);
        miner = makeAddr("skip-miner");
        _giveWalletId(miner);
        vm.warp(block.timestamp + 1 days);
        require(game.currentDayView() == GameTimeLib.DEGENESIS_START_DAY, "fixture: Degenesis day 1");
        for (uint256 i; i < 50; ++i) {
            if (game.nextMinerAction() == MineFlipAdmission.REQUEST_DAILY) break;
            game.mineFlip{gas: 3_000_000}(0);
        }
        require(game.nextMinerAction() == MineFlipAdmission.REQUEST_DAILY, "fixture: request next");
    }

    function _battlePending() internal view returns (bool) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DAILY_TICKET_BUDGETS_PACKED))) & (uint256(1) << 72) != 0;
    }

    function test_SkipPathRequestAndSeal() public {
        Measured memory m = _measureCall(address(game), abi.encodeWithSignature("mineFlip(uint32)", uint32(0)), miner);
        _log("Degenesis day-1 request (battle lock skipped)", m);
        vm.prank(miner);
        game.mineFlip(MineFlipGas.DEFAULT_MULTIPLIER);
        assertTrue(game.rngLocked(), "the request went out");
        assertFalse(_battlePending(), "no battle pending on a pre-window day");
        uint256 bound = MineFlipAdmission.minGas(MineFlipAdmission.REQUEST_DAILY, true);
        emit log_named_uint("request admission, grossed through the engine", bound);
        assertLe(_worst(m), bound, "request within its admission");
        bool battleStage;
        bool degenesisDay;
        for (uint256 i; i < 60; ++i) {
            uint256 req = mockVRF.lastRequestId();
            (,, bool fulfilled) = mockVRF.pendingRequests(req);
            if (!fulfilled) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("skip", req))));
            vm.recordLogs();
            vm.prank(miner);
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            // A reverted call has no effect; forge still records the logs it emitted.
            if (!ok) break;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
                if (logs[j].topics[0] != keccak256("Advance(uint8,uint24)")) continue;
                (uint8 stage,) = abi.decode(logs[j].data, (uint8, uint24));
                if (stage == 17) battleStage = true;
                if (stage == 21) degenesisDay = true;
            }
        }
        assertFalse(game.rngLocked(), "the day sealed");
        assertFalse(battleStage, "no purchase battle stage");
        assertTrue(degenesisDay, "the Degenesis day branch closed the day");
    }
}

// =========================================================================
// Every changed admission is under 10M
// =========================================================================

/// @title DegenesisAdmissionCeilings -- the changed checkpoints' admissions stay under 10M
/// @notice Each new or changed MineFlipGasBounds constant, and each checkpoint admission it joins
///         (its operation plus the tails the caller reserves beside it), is under the 10M
///         per-checkpoint ceiling. The 100-box human entry is the one documented exception and is
///         held under the 16.7M ceiling instead.
contract DegenesisAdmissionCeilings is DegenesisGasBase {
    uint256 internal constant CEILING = 10_000_000;

    function test_ChangedAdmissionsUnderTenMillion() public pure {
        uint256[10] memory constants_ = [
            GasBounds.DEGENESIS_WWXRP_GAS, GasBounds.DEGENESIS_FLIP_CREDIT_GAS, GasBounds.DEGENESIS_FLIP_PASS_GAS,
            GasBounds.DEGENESIS_DGNRS_GAS, GasBounds.DEGENESIS_FLUSH_PER_CREDIT, GasBounds.DEGENESIS_TAIL_GAS,
            GasBounds.DEGENESIS_DAY_CLOSE, GasBounds.DEGENESIS_REQUEST_GAS, GasBounds.DEGENESIS_TERMINAL_GAS,
            GasBounds.DEGENESIS_WORD_COPY_GAS
        ];
        for (uint256 i; i < constants_.length; ++i) assertLt(constants_[i], CEILING, "Degenesis constant");
        // Checkpoint admissions as the engine composes them.
        assertLt(MineFlipAdmission.degenesisSettleFirstUnit() + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN,
            CEILING, "settlement first order with its flush, close and burn");
        assertLt(GasBounds.RNG_DAILY_REQUEST + GasBounds.DEGENESIS_REQUEST_GAS + GasBounds.RNG_REDEMPTION_CLOSE
            + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN, CEILING, "daily request with the Degenesis step");
        assertLt(GasBounds.DAILY_APPLY + GasBounds.DEGENESIS_WORD_COPY_GAS + GasBounds.ENGINE_BOUNDARY
            + GasBounds.ENGINE_RETURN, CEILING, "daily apply with the word copy");
        assertLt(GasBounds.DAILY_GAP + GasBounds.DAILY_APPLY + GasBounds.DEGENESIS_WORD_COPY_GAS
            + GasBounds.TERMINAL_TAIL + 250_000, CEILING, "terminal word application with the word copy");
        assertLt(GasBounds.TERMINAL_SETUP + GasBounds.DEGENESIS_TERMINAL_GAS + GasBounds.TERMINAL_TAIL + 250_000,
            CEILING, "terminal setup with the Degenesis split");
        assertLt(GasBounds.DEGENESIS_DAY_CLOSE + GasBounds.DAILY_PHASE_TAIL + 250_000, CEILING, "Degenesis day close");
        assertLt(GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS, CEILING, "sDGNRS whale buy and top-up");
        assertLt(MineFlipAdmission.terminalLoanFirstUnit(), CEILING, "game over's loan checkpoint");
        assertLt(GasBounds.LOAN_SEIZE_BASE + 6 * GasBounds.LOAN_SEIZE_SUB + GasBounds.LOAN_SEIZE_DEITY
            + GasBounds.LOAN_SEIZE_TAIL, CEILING, "level loan checkpoint");
        assertLt(GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL, CEILING, "battle draw incl. zero-award seal");
        // The documented exception: the rare 100-box human entry, under the 16.7M ceiling.
        assertLt(GasBounds.HUMAN_ENTRY_GAS + 100 * GasBounds.HUMAN_BOX_GAS + GasBounds.HUMAN_TAIL_GAS, 16_700_000,
            "100-box human entry under the hard ceiling");
    }
}

// =========================================================================
// Error classification below the minimum: the sDGNRS whale stage
// =========================================================================

/// @title SdgnrsWhaleUnderfundedRevert -- an underfunded whale stage reverts E(), not a gas refusal
/// @notice Once the preparation day is pinned, the next mineFlip of a new level's day runs the
///         sDGNRS AFKing top-up and the 1,000-pass whale buy as its first unit. Below that unit's minimum admission, some
///         cold calls revert E(): the buy's nested recordCoverBox delegatecall runs out of gas
///         with 1/64 left in the parent, and WhaleModule._recordLootboxEntry turns the empty
///         revert data into E() (the AFKing module's own delegate helper turns it into
///         EmptyRevert, which the engine reports as InsufficientExecutionGas). The reverted call
///         changes nothing, and the minimum admission progresses, so liveness holds; the note is
///         the misclassified error. Fixture as SdgnrsWhaleBuyStageGas (day-9 deploy): level 4,
///         sDGNRS funded for the 1,000-pass cap, AFKing below its target.
contract SdgnrsWhaleUnderfundedRevert is DeployProtocol {
    address internal constant MINER = address(0xFEED01);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        _giveWalletId(MINER);
        _setLevelFour();
        _retireSkippedLevels();
        _fundSdgnrs(16_000 ether);
        vm.warp(block.timestamp + 1 days);
        require(game.nextMinerAction() == MineFlipAdmission.PREPARE_SUBS, "fixture: subscription stage next");
        // A cheap first call only pins the preparation day; the whale buy is then the next call's
        // first unit.
        vm.prank(MINER);
        game.mineFlip{gas: 300_000}(0);
        require(game.nextMinerAction() == MineFlipAdmission.PREPARE_SUBS, "fixture: whale stage next");
        require(uint24(uint256(vm.load(address(game), bytes32(GameSlots.SUB_CURSOR))) >> (17 * 8)) == 0,
            "fixture: whale attempt unspent");
    }

    /// @dev Level 4 with its whale attempt unspent (SdgnrsWhaleBuyStageGas._setLevel).
    function _setLevelFour() internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(0)));
        s0 = (s0 & ~(uint256(0xFFFFFF) << 96)) | (uint256(4) << 96);
        vm.store(address(game), bytes32(0), bytes32(s0));
    }

    /// @dev SdgnrsWhaleBuyStageGas._retireSkippedLevels.
    function _retireSkippedLevels() internal {
        for (uint24 lvl = 1; lvl <= 4; ++lvl) {
            uint24 nearRoot = ((lvl - 1) & 1) + 1;
            _clearRoot(nearRoot);
            _clearRoot(nearRoot | 0x800000);
            _clearRoot(lvl | 0x400000);
        }
        _clearPending(ContractAddresses.SDGNRS);
        _clearPending(ContractAddresses.VAULT);
    }

    function _clearRoot(uint24 root) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(root), GameSlots.TICKET_QUEUE)), bytes32(0));
    }

    function _clearPending(address holder) internal {
        uint32 id = game.walletIdOf(holder);
        if (id != 0) vm.store(address(game), keccak256(abi.encode(uint256(id), GameSlots.TICKET_PENDING)), bytes32(0));
    }

    /// @dev sDGNRS claimable `amount` with AFKing 0, claimablePool moved with it: the top-up
    ///      writes and the 1,000-pass cap is bought.
    function _fundSdgnrs(uint256 amount) internal {
        bytes32 cw = keccak256(abi.encode(uint256(game.walletIdOf(ContractAddresses.SDGNRS)), GameSlots.BALANCES_PACKED));
        uint256 prev = uint256(vm.load(address(game), cw));
        vm.store(address(game), cw, bytes32(amount));
        bytes32 cp = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 p1 = uint256(vm.load(address(game), cp));
        uint256 pool = (p1 >> 128) + amount - uint128(prev) - (prev >> 128);
        vm.store(address(game), cp, bytes32((p1 & type(uint128).max) | (pool << 128)));
    }

    function _coolEngine() internal {
        vm.cool(address(game));
        vm.cool(address(sdgnrs));
        vm.cool(address(coinflip));
        vm.cool(address(coin));
        vm.cool(address(affiliate));
        vm.cool(address(quests));
        vm.cool(address(crapsBattle));
        vm.cool(address(wwxrp));
        vm.cool(ContractAddresses.GAME_DEGENESIS_MODULE);
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.AFKING_SUB_TOKEN);
        vm.cool(ContractAddresses.DEITY_PASS);
    }

    function test_UnderfundedWhaleStageRevertsE_MinimumProgresses() public {
        uint256 minimum = MineFlipAdmission.minGas(MineFlipAdmission.PREPARE_SUBS, false);
        uint256 eAt;
        uint256 eCount;
        for (uint256 g = 300_000; g < minimum; g += 10_000) {
            uint256 snap = vm.snapshotState();
            _coolEngine();
            vm.prank(MINER);
            (bool ok, bytes memory ret) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            vm.revertToStateAndDelete(snap);
            if (ok) continue;
            if (keccak256(ret) == keccak256(abi.encodeWithSignature("E()"))) {
                if (eAt == 0) eAt = g;
                ++eCount;
                continue;
            }
            bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
            assertTrue(ret.length == 0 || sel == bytes4(keccak256("InsufficientExecutionGas()"))
                || sel == bytes4(keccak256("EmptyRevert()")), "below the minimum: a gas refusal or the E() case");
        }
        emit log_named_uint("lowest gas surfacing E()", eAt);
        emit log_named_uint("gas levels surfacing E() (10k steps)", eCount);
        assertGt(eAt, 0, "an underfunded whale stage surfaces the out-of-gas as E()");
        _coolEngine();
        vm.prank(MINER);
        (bool okMin,) = address(game).call{gas: minimum}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        assertTrue(okMin, "the minimum admission progresses");
        assertEq(uint24(uint256(vm.load(address(game), bytes32(GameSlots.SUB_CURSOR))) >> (17 * 8)), 4,
            "the whale attempt ran at the minimum");
    }
}
