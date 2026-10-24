// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Uses the actual Game runtime and a fixed cold-storage callback fixture.
///      Constructor, coordinator bookkeeping and purchase setup are outside the measurement.
contract StackSpillCallbackGasTest is Test {
    address private constant TARGET = address(0x1000);
    address private constant COORDINATOR = address(0x2000);
    uint256 private constant REQUEST = 123;
    uint256 private constant WORD = 123456789;
    uint256 private constant FLAGS = (uint256(1) << 254) | (uint256(1) << 152);
    DegenerusGame private game;

    function setUp() public {
        vm.etch(TARGET, vm.getDeployedCode("DegenerusGame.sol:DegenerusGame"));
        game = DegenerusGame(payable(TARGET));
        vm.store(TARGET, bytes32(uint256(22)), bytes32(uint256(uint160(COORDINATOR))));
        vm.store(TARGET, bytes32(0), bytes32(FLAGS));
        vm.store(TARGET, bytes32(uint256(3)), bytes32(uint256(1)));
        vm.store(TARGET, bytes32(uint256(4)), bytes32(REQUEST));
    }

    function _fulfill(uint256 request) private returns (uint256) {
        uint256[] memory words = new uint256[](1);
        words[0] = WORD;
        vm.prank(COORDINATOR);
        game.rawFulfillRandomWords(request, words);
        Vm.Gas memory measured = vm.lastCallGas();
        uint256 intrinsic;
        if (vm.envOr("FOUNDRY_ISOLATE", false)) {
            bytes memory data = abi.encodeCall(game.rawFulfillRandomWords, (request, words));
            intrinsic = 21_000;
            for (uint256 i; i < data.length; ++i) intrinsic += data[i] == 0 ? 4 : 16;
        }
        return measured.gasTotalUsed - intrinsic;
    }

    function test_FulfillmentGasPin() public {
        // Cold callback execution only; calldata intrinsic gas is outside this frame.
        assertEq(_fulfill(REQUEST), 12_440, "callback execution gas changed");
        assertEq(uint256(vm.load(TARGET, bytes32(uint256(3)))), WORD);
        assertEq(uint256(vm.load(TARGET, bytes32(0))), FLAGS);
    }

    function test_StaleRequestGasPin() public {
        assertEq(_fulfill(REQUEST + 1), 7_325, "stale callback execution gas changed");
        assertEq(uint256(vm.load(TARGET, bytes32(uint256(3)))), 1);
        assertEq(uint256(vm.load(TARGET, bytes32(0))), FLAGS);
    }
}
