// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GoldSixFoilGasHarness} from "./GoldSixGas.t.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract BoundedFoilHost is GoldSixFoilGasHarness {
    function state() external view returns (uint32 count, uint32 cursor) { return (foilReadCount, foilCursor); }
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
