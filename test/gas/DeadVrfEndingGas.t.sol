// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/DeadVrfEnding.t.sol";

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
            lvlEntryOwner[lvl].push(EntryOwner(owner, 0));
            foilBuyers[day].push((lvlEntryOwner[lvl].length << 192) | (uint256(lvl) << 160) | uint160(owner));
        }
        foilDrainDay = day;
        foilLastResolveDay = day;
        // Reachable continuation after the registry (all zero owed) has been tallied.
        deadTallyPos = uint32(lvlEntryOwner[lvl].length);
        deadTallyStage = 1;
        deadTallyFoilDay = day;
    }

    function seedEmptyDays(uint24 first, uint24 last) external {
        foilDrainDay = first;
        foilLastResolveDay = last;
        deadTallyStage = 1;
        deadTallyFoilDay = first;
    }

    function seedFinalBatch(uint24 lvl) external returns (uint256 expectedUncreated) {
        snapShift = 1;
        // Populate every trait, then leave exactly 2,744 registry entries. The same cold
        // transaction must tally those, read all 256 trait lengths, and fix the payout.
        for (uint256 t; t < 256; ++t) {
            _seedBucket(lvl, uint8(t), address(0xC4EA7ED), 1);
        }
        while (lvlEntryOwner[lvl].length < 2744) {
            _seedQueued(_tqReadKey(lvl), lvl, address(uint160(0xDEAD0000 + lvlEntryOwner[lvl].length)), uint80(4) << 8);
        }
        for (uint256 i; i < lvlEntryOwner[lvl].length; ++i) {
            uint80 owed = uint80(_entryRecord(lvl, uint32(i + 1)) >> 160);
            if (owed != 0 && owed & SNAP_DONE_BIT == 0) owed = _snapOwedPacked(owed, 1);
            expectedUncreated += uint256(uint32(owed >> 8)) * QTY_SCALE + uint8(owed);
        }
        for (uint256 i; i < 30; ++i) {
            address owner = address(uint160(0xD3170000 + i));
            deityPassOwners.push(owner);
            deityPassPricePaid[owner] = 20 ether;
        }
    }

    function progress() external view returns (uint256 pos, uint256 day, uint256 idx, uint256 stage) {
        return (deadTallyPos, deadTallyFoilDay, deadTallyFoilIdx, deadTallyStage);
    }
}

/// @dev Setup runs before the measured transaction, so all production storage starts cold.
///      Measure the real Game -> Advance -> GameOver path, including call overhead and a
///      conservative 21,064 intrinsic gas allowance. Assert work as well as the 15M ceiling.
abstract contract DeadVrfEndingGasFixture is DeployProtocol {
    uint256 internal constant INTRINSIC = 21_064;
    uint256 internal constant TX_CAP = 16_777_216;
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
        if (mode == 2) s.seedEmptyDays(FOIL_DAY, FOIL_DAY + 3000);
        if (mode == 3) expectedUncreated = s.seedFinalBatch(10);
        vm.etch(address(game), code);
    }

    function test_ColdDeadVrfBatchFits15M() public {
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.advanceGame{gas: TX_CAP - INTRINSIC}();
        uint256 used = beforeGas - gasleft() + INTRINSIC;
        emit log_named_uint("DEAD_VRF_COLD_INCLUDING_INTRINSIC", used);
        assertLt(used, 15_000_000, "dead-VRF batch exceeds audit target");

        uint8 mode = shape();
        assertEq(game.gameOver(), mode == 3, "only the finishing batch may pay out");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool advanced;
        bool fixedPayout;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (uint8 advanceStage,) = abi.decode(logs[i].data, (uint8, uint24));
                assertEq(advanceStage, mode == 3 ? 0 : 5);
                advanced = true;
            }
            if (logs[i].topics[0] == keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)")) {
                (uint256 pot, uint256 created, uint256 uncreated, uint256 traits) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                assertEq(pot, 4400 ether, "30 full deity refunds before fixing the pot");
                assertEq(created, 256);
                assertEq(uncreated, expectedUncreated);
                assertEq(traits, 256);
                fixedPayout = true;
            }
        }
        assertTrue(advanced, "real advance path executed");
        assertEq(fixedPayout, mode == 3);

        // Inspect after measurement, never warming the measured transaction's state.
        vm.etch(address(game), type(DeadVrfGasSeeder).runtimeCode);
        (uint256 pos, uint256 day, uint256 idx, uint256 stage) = DeadVrfGasSeeder(payable(address(game))).progress();
        if (mode == 0) {
            assertEq(pos, 3000, "full registry budget consumed");
            assertEq(stage, 0);
        } else if (mode == 1) {
            assertEq(idx, 3000, "full foil budget consumed");
            assertEq(day, FOIL_DAY);
            assertEq(stage, 1);
        } else if (mode == 2) {
            assertEq(day, FOIL_DAY + 3000, "empty days also consume the budget");
            assertEq(stage, 1);
        } else {
            assertEq(pos, 2744);
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
        game.advanceGame();
        assertTrue(game.gameOver());
        expectedClaim = ((4400 ether * 25_600) / (25_600 + uncreated) / 256) * 256;
    }

    function test_ColdClaimAcross256TraitsFits15M() public {
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
        game.claimDeadVrf{gas: 16_777_216 - intrinsic}(OWNER, refs);
        uint256 used = beforeGas - gasleft() + intrinsic;
        emit log_named_uint("DEAD_VRF_COLD_256_TRAIT_CLAIM_INCLUDING_INTRINSIC", used);
        assertLt(used, 15_000_000);
        assertEq(game.claimableWinningsOf(OWNER), expectedClaim);
        assertGt(expectedClaim, 0, "the measured call must pay the owner");
        vm.expectRevert();
        game.claimDeadVrf(OWNER, refs);
    }
}
