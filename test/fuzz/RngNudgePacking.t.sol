// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract NudgePackingHarness is DegenerusGameStorage {
    function count(uint16 value) external { require(value <= RNG_NUDGE_CAP); _setNudgeCount(value); }
    function flags(bool window, bool complete) external {
        _setTicketRedemptionOpen(window); _setRngComplete(complete);
    }
    function read() external view returns (uint256, bool, bool) {
        return (_nudgeCount(), _ticketRedemptionOpen(), _rngComplete());
    }
}
contract RngNudgePackingTest is Test {
    NudgePackingHarness h;
    function setUp() public { h = new NudgePackingHarness(); }
    function testFuzz_NudgesAndFlagUpdatesPreserveEveryNeighbor(uint256 state, uint16 count, bool window, bool complete) public {
        count = uint16(bound(count, 0, 255));
        vm.store(address(h), bytes32(0), bytes32(state));
        h.count(count);
        uint256 nudgeMask = uint256(0xFF) << 240;
        assertEq(uint256(vm.load(address(h), bytes32(0))) & ~nudgeMask, state & ~nudgeMask);
        h.flags(window, complete);
        (uint256 result, bool gotWindow, bool gotComplete) = h.read();
        assertEq(result, count);
        assertEq(gotWindow, window); assertEq(gotComplete, complete);
        uint256 changed = nudgeMask | ((uint256(1) << 9) | (uint256(1) << 8)) << 240;
        assertEq(uint256(vm.load(address(h), bytes32(0))) & ~changed, state & ~changed);
    }
    function test_Exact255IsRepresentableWithBothFlagsSet() public {
        h.flags(true, true); h.count(255);
        (uint256 count, bool window, bool complete) = h.read();
        assertEq(count, 255); assertTrue(window && complete);
        h.count(0);
        (count, window, complete) = h.read();
        assertEq(count, 0); assertTrue(window && complete);
    }
}
contract RngNudgeCapTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }
    function test_255thNudgeAcceptedAnd256thRejectedBeforeBurn() public {
        RecyclingState.seedNudges(address(game), 254);
        vm.mockCall(ContractAddresses.COIN, abi.encodeWithSignature("burnCoin(address,uint256)"), abi.encode());
        (uint256 queued, uint256 cost) = game.rngNudgeQuote();
        assertEq(queued, 254); assertGt(cost, 0);
        game.reverseFlip(cost);
        (queued, cost) = game.rngNudgeQuote();
        assertEq(queued, 255); assertEq(cost, 0);
        vm.mockCallRevert(ContractAddresses.COIN, abi.encodeWithSignature("burnCoin(address,uint256)"), "burn must not run at cap");
        vm.expectRevert(bytes4(keccak256("NudgeCapReached()")));
        game.reverseFlip(0);
        assertEq(RecyclingState.nudgeCount(address(game)), 255);
    }
}
