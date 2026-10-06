// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract DeadVrfGasSeeder is DeadVrfSeeder {
    function seedRegistry(uint24 lvl, uint256 count) external {
        snapShift = 1; // Every nonzero owed record takes the unsnapped adjustment branch.
        for (uint256 i; i < count; ++i) {
            _seedQueued(_tqReadKey(lvl), lvl, address(uint160(0xDEAD0000 + i)), uint80(4) << 8);
        }
    }

    function seedFoilBatch(uint24 lvl, uint24 day, uint256 count) external {
        for (uint256 i; i < count; ++i) {
            address owner = address(uint160(0xF0110000 + i));
            uint256 id = uint256(_seedWallet(owner));
        foilQueue[day & 1].push((id << 192) | (uint256(lvl) << 160) | uint160(owner));
        }
        foilGenerationDay = day;
        foilFirstDrawDay = day;
        // Reachable continuation after the registry (all zero owed) has been tallied.
        deadTallyPos = uint32((wallets.length - 1));
        deadTallyStage = 1;
        deadTallyFoilDay = (day & 1) + 1;
    }

    function seedEmptyDays(uint24 first, uint24 last) external {
        foilGenerationDay = first;
        foilFirstDrawDay = last;
        deadTallyStage = 1;
        deadTallyFoilDay = 1;
    }

    function seedFinalBatch(uint24 lvl) external returns (uint256 expectedUncreated) {
        snapShift = 1;
        // The finishing batch has 2,542 queued records across all three domains,
        // two foil-queue boundary steps and 256 trait reads: exactly 2,800 units.
        for (uint256 t; t < 256; ++t) {
            _seedBucket(lvl, uint8(t), address(0xC4EA7ED), 1);
        }
        uint24[3] memory keys = [_tqReadKey(lvl), _tqWriteKey(lvl), _tqFarFutureKey(lvl)];
        uint256 otherCount = _ticketQueueLength(keys[1]) + _ticketQueueLength(keys[2]);
        while (_ticketQueueLength(keys[0]) + otherCount < 2542) {
            _seedQueued(keys[0], lvl, address(uint160(0xDEAD0000 + _ticketQueueLength(keys[0]))), uint80(4) << 8);
        }
        for (uint256 k; k < keys.length; ++k) {
            for (uint256 i; i < _ticketQueueLength(keys[k]); ++i) {
                uint80 owed = _entryPacked(keys[k], _tqPositionAt(ticketQueue[_ticketQueueStorageKey(keys[k])], i));
                if (owed != 0 && owed & SNAP_DONE_BIT == 0) owed = _snapOwedPacked(owed, 1);
                expectedUncreated += uint256(uint32(owed >> 8)) * QTY_SCALE + uint8(owed);
            }
        }
        for (uint256 i; i < 30; ++i) {
            address owner = address(uint160(0xD3170000 + i));
            _seedDeity(owner);
            deityPassPricePaid[_seedWallet(owner)] = 20 ether;
        }
    }

    function progress() external view returns (uint256 pos, uint256 day, uint256 idx, uint256 stage) {
        return (deadTallyPos, deadTallyFoilDay, deadTallyFoilIdx, deadTallyStage);
    }
}

/// @dev Setup runs before the measured transaction, so all production storage starts cold.
///      Measure the real Game -> Advance -> GameOver path, including call overhead and a
///      conservative 21,064 intrinsic gas allowance. The dead tally is checkpointed per record
///      under declared gas bounds (MineFlipGasBounds TERMINAL_*; 60d31f775), not a fixed
///      2,800-unit batch, so the engine spends whatever allowance it is given. Owner rule: no
///      bound on a whole transaction; a realistic 10M allowance must succeed and progress, and the
///      ending must complete through such calls with the exact fixed payout.
abstract contract DeadVrfEndingGasFixture is DeployProtocol {
    uint256 internal constant INTRINSIC = 21_064;
    uint256 internal constant REALISTIC = 10_000_000;
    uint24 internal constant LVL = 5000;
    uint24 internal constant FOIL_DAY = 100;
    uint256 internal expectedUncreated;

    function shape() internal pure virtual returns (uint8);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 4000 days);
        vm.deal(address(game), 5000 ether);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(DeadVrfGasSeeder).runtimeCode);
        DeadVrfGasSeeder s = DeadVrfGasSeeder(payable(address(game)));
        uint8 mode = shape();
        s.seedDeadStall(mode == 3 ? 9 : LVL);
        if (mode == 0) s.seedRegistry(LVL + 1, 3001);
        if (mode == 1) s.seedFoilBatch(LVL + 1, FOIL_DAY, 3001);
        if (mode == 2) s.seedEmptyDays(FOIL_DAY, FOIL_DAY + 2800);
        if (mode == 3) expectedUncreated = s.seedFinalBatch(10);
        vm.etch(address(game), code);
    }

    function _progress() private returns (uint256 pos, uint256 day, uint256 idx, uint256 stage) {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(DeadVrfGasSeeder).runtimeCode);
        (pos, day, idx, stage) = DeadVrfGasSeeder(payable(address(game))).progress();
        vm.etch(address(game), code);
    }

    function test_ColdDeadVrfBatchFits11_5M() public {
        uint8 mode = shape();
        // Only the empty-days shape completes in the first call; the others need several.
        bool oneCall = mode == 2;
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: REALISTIC - INTRINSIC}();
        uint256 used = beforeGas - gasleft() + INTRINSIC;
        emit log_named_uint("DEAD_VRF_COLD_INCLUDING_INTRINSIC", used);
        assertEq(game.gameOver(), oneCall, "empty queues and finishing batches may pay out");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool advanced;
        bool fixedPayout;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (uint8 advanceStage,) = abi.decode(logs[i].data, (uint8, uint24));
                // Tally checkpoints report STAGE_TICKETS_WORKING (5); a call that finishes the
                // tally moves on to the drain (STAGE_GAMEOVER, 0) within the same allowance.
                if (oneCall) assertEq(advanceStage, 0);
                else assertTrue(advanceStage == 5 || advanceStage == 0, "terminal stage");
                advanced = true;
            }
            if (logs[i].topics[0] == keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)")) {
                fixedPayout = true;
            }
        }
        assertTrue(advanced, "real advance path executed");
        assertEq(fixedPayout, oneCall);

        // Inspect after measurement, never warming the measured transaction's state.
        (uint256 pos, uint256 day, uint256 idx, uint256 stage) = _progress();
        if (mode == 0) {
            assertGt(pos, 0, "full registry budget consumed");
            assertLt(pos, 3001, "the realistic call checkpoints inside the registry");
            assertEq(stage, 0);
        } else if (mode == 1) {
            // Foil records tally cheaply under their per-record bound, so one realistic call may
            // finish the 3,001-record queue and move on; it must at least have entered it.
            assertTrue(idx > 0 || day > (FOIL_DAY & 1) + 1, "full foil budget consumed");
            assertGe(stage, 1);
        } else if (mode == 2) {
            assertEq(day, 3, "only two physical foil queues are scanned");
            assertEq(stage, 3);
        }

        // Continue at the realistic allowance: every call succeeds and progresses until the
        // deterministic ending pays out.
        uint256 maxUsed = used;
        uint256 calls = 1;
        vm.recordLogs();
        while (!game.gameOver() && calls < 64) {
            (uint256 p0, uint256 d0, uint256 i0, uint256 s0) = _progress();
            beforeGas = gasleft();
            game.mineFlip{gas: REALISTIC - INTRINSIC}();
            used = beforeGas - gasleft() + INTRINSIC;
            if (used > maxUsed) maxUsed = used;
            ++calls;
            (uint256 p1, uint256 d1, uint256 i1, uint256 s1) = _progress();
            assertTrue(game.gameOver() || p1 != p0 || d1 != d0 || i1 != i0 || s1 != s0,
                "each realistic call makes progress");
        }
        emit log_named_uint("DEAD_VRF_REALISTIC_CALLS", calls);
        emit log_named_uint("DEAD_VRF_MAX_CALL_INCLUDING_INTRINSIC", maxUsed);
        assertTrue(game.gameOver(), "the deterministic ending completes at a realistic allowance");
        if (!oneCall) {
            logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)")) continue;
                fixedPayout = true;
                if (mode != 3) continue;
                (uint256 pot, uint256 created, uint256 uncreated, uint256 traits) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                assertEq(pot, 4400 ether, "30 full deity refunds before fixing the pot");
                assertEq(created, 256);
                assertEq(uncreated, expectedUncreated);
                assertEq(traits, 256);
            }
            assertTrue(fixedPayout, "the ending fixed its deterministic payout");
        }
        if (mode == 3) {
            (pos,,, stage) = _progress();
            assertEq(pos, 0, "completed queue-stage cursor cleared");
            assertEq(stage, 3);
        }
    }
}

contract DeadVrfRegistryGas is DeadVrfEndingGasFixture {
    function shape() internal pure override returns (uint8) {
        return 0;
    }
}

contract DeadVrfFoilGas is DeadVrfEndingGasFixture {
    function shape() internal pure override returns (uint8) {
        return 1;
    }
}

contract DeadVrfEmptyDaysGas is DeadVrfEndingGasFixture {
    function shape() internal pure override returns (uint8) {
        return 2;
    }
}

contract DeadVrfFinalBatchGas is DeadVrfEndingGasFixture {
    function shape() internal pure override returns (uint8) {
        return 3;
    }
}

/// @dev One owner claims one created ticket from each of the 256 nonempty traits, forcing
///      256 distinct cold claimed-bitmap writes. References can also be submitted in smaller batches.
contract DeadVrfClaimGas is DeployProtocol {
    address private constant OWNER = address(0xC4EA7ED);
    uint256 private expectedClaim;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 4000 days);
        vm.deal(address(game), 5000 ether);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(DeadVrfGasSeeder).runtimeCode);
        DeadVrfGasSeeder s = DeadVrfGasSeeder(payable(address(game)));
        s.seedDeadStall(9);
        uint256 uncreated = s.seedFinalBatch(10);
        vm.etch(address(game), code);
        game.mineFlip();
        assertTrue(game.gameOver());
        expectedClaim = ((4400 ether * 25_600) / (25_600 + uncreated) / 256) * 256;
    }

    function test_ColdClaimAcross256TraitsFits11_5M() public {
        uint256[] memory refs = new uint256[](256);
        for (uint256 i; i < refs.length; ++i) {
            refs[i] = i << 64;
        }
        bytes memory payload = abi.encodeCall(game.claimDeadVrf, (OWNER, refs));
        uint256 intrinsic = 21_000;
        for (uint256 i; i < payload.length; ++i) {
            intrinsic += payload[i] == 0 ? 4 : 16;
        }

        uint256 beforeGas = gasleft();
        game.claimDeadVrf{gas: 11_500_000 - intrinsic}(OWNER, refs);
        uint256 used = beforeGas - gasleft() + intrinsic;
        emit log_named_uint("DEAD_VRF_COLD_256_TRAIT_CLAIM_INCLUDING_INTRINSIC", used);
        assertLt(used, 11_500_000);
        assertEq(game.claimableWinningsOf(OWNER), expectedClaim);
        assertGt(expectedClaim, 0, "the measured call must pay the owner");
        vm.expectRevert();
        game.claimDeadVrf(OWNER, refs);
    }
}
