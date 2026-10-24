// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GoldSixFoilGasHarness} from "./GoldSixGas.t.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract BoundedFoilHost is GoldSixFoilGasHarness {
    function state() external view returns (uint32 count, uint32 cursor) { return (foilReadCount, foilCursor); }
    function single(uint256 word) external { foilReadCount = 1; rngWordCurrent = word; }
    function generatedLines() external view returns (uint32[4] memory lines) {
        uint256 record = foilRecord[1][_walletIdOf(address(0x1000))];
        for (uint256 i; i < 4; ++i) lines[i] = uint32(record >> (_FOIL_LINES_SHIFT + i * 32));
    }
}
contract BoundedFoilGasTest is BoundedGasProbe {
    BoundedFoilHost private host;
    function setUp() public {
        vm.etch(ContractAddresses.GAME, type(BoundedFoilHost).runtimeCode);
        host = BoundedFoilHost(ContractAddresses.GAME);
        host.seed();
    }
    function _run(string memory label) private {
        _measureBounded(label, address(host), address(this), 0,
            abi.encodeCall(host.runFoilWork, (uint256(14_000_000))), false);
        (uint32 count, uint32 cursor) = host.state();
        assertEq(count, 0, "all eight paid packs resolved");
        assertEq(cursor, 0, "completed cursor reset");
    }
    function test_SinglePackSixteenDistinctFreshTraits() public {
        uint256 chosen;
        uint256 snapshot = vm.snapshotState();
        for (uint256 word = 2; word < 1_000 && chosen == 0; ++word) {
            host.single(word);
            host.runFoilWork(15_000_000);
            uint32[4] memory lines = host.generatedLines();
            assertTrue(vm.revertToState(snapshot));
            uint256 seen;
            uint256 distinct;
            for (uint256 i; i < 4; ++i) for (uint256 q; q < 4; ++q) {
                uint256 bit = uint256(1) << uint8(lines[i] >> (8 * q));
                if (seen & bit == 0) { seen |= bit; ++distinct; }
            }
            if (distinct == 16) {
                assertEq(seen & (uint256(1) << 253), 0, "all selected buckets are fresh; occupied gold-six is replaced");
                chosen = word;
            }
        }
        assertTrue(vm.revertToStateAndDelete(snapshot));
        assertGt(chosen, 0, "fixture reaches sixteen distinct fresh trait buckets");
        host.single(chosen);
        _run("foil-single-sixteen-distinct");
        emit log_named_uint("sixteen-distinct foil word", chosen);
    }

    function test_G3_G7_G10_WholeEightPackDrain() public { _run("G3_G7_G10_foil_drain8"); }
    function test_G3_G7_G10_ResumedPackDrain() public {
        MineFlipGas.Result memory first = host.runFoilWork(Bounds.FOIL_PACK + 100_000 + MineFlipGas.CHECK_RESERVE + 50_000);
        (, uint32 cursor) = host.state();
        assertTrue(first.progressed && !first.done, "fixture stops during paid cohort");
        assertGt(cursor, 0);
        assertLt(cursor, 8);
        emit log_named_uint("resume_cursor", cursor);
        _run("G3_G7_G10_foil_resume");
    }
}
