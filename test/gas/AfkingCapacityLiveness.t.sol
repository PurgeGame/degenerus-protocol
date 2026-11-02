// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract ReviewCapacitySeeder is WalletSeed {
    function seed(uint256 boxes) external {
        for (uint256 i; i < 10_000; ++i) {
            uint32 id = _seedWallet(address(uint160(0xB0000000 + i)));
            _seedSubscriber(id, i >= boxes);
            _setSubRunStart(id, dailyIdx);
            balancesPacked[id] += uint256(1 ether) << 128;
            claimablePool += 1 ether;
        }
    }
    function state() external view returns (uint256 members, uint256 pending, uint256 prep, uint256 opened) {
        return (_subscribers.length, _pendingBoxCount, _subCursor, _subOpenCursor);
    }
    function funding(address who) external view returns (uint256) { return _afkingOf(_walletIdOf(who)); }
}

contract AfkingCapacityLivenessTest is DeployProtocol {
    bytes private runtime;

    function setUp() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires cold calls");
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000_000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishSubscriptionWindow();
        runtime = address(game).code;
    }

    function _run(uint256 boxes) private {
        vm.etch(address(game), type(ReviewCapacitySeeder).runtimeCode);
        ReviewCapacitySeeder(address(game)).seed(boxes);
        vm.etch(address(game), runtime);
        vm.deal(address(game), address(game).balance + 10_000 ether);
        uint24 beforeDay = game.currentDayView_g542950();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 usedCalls;
        uint256 maximumGas;
        for (; usedCalls < 2_000; ++usedCalls) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("capacity-review", request))));
            }
            if (!game.advanceDue() && game.rngComplete()) break;
            uint256 beforeGas = gasleft();
            (bool ok, bytes memory reason) = address(game).call{gas: 15_000_000}(abi.encodeCall(game.mineRun, (0)));
            uint256 used = beforeGas - gasleft();
            if (used > maximumGas) maximumGas = used;
            assertTrue(ok, string.concat("bounded crank failed: ", vm.toString(reason)));
        }
        assertLt(usedCalls, 2_000, "full set failed to drain");
        assertGt(game.currentDayView_g542950(), beforeDay, "logical day advanced");
        assertTrue(game.rngComplete(), "all RNG consumers finished");
        assertFalse(game.gameOver(), "healthy full set must stay live");
        vm.etch(address(game), type(ReviewCapacitySeeder).runtimeCode);
        (uint256 members, uint256 pending,,) = ReviewCapacitySeeder(address(game)).state();
        assertEq(members, 10_002, "no funded member lost");
        assertEq(pending, 0, "all paid boxes opened");
        for (uint256 i; i < 10_000; ++i) {
            assertLt(ReviewCapacitySeeder(address(game)).funding(address(uint160(0xB0000000 + i))), 1 ether,
                "funded subscriber skipped");
        }
        vm.etch(address(game), runtime);
        emit log_named_uint("cold 15M-capped calls", usedCalls);
        emit log_named_uint("maximum call gas including harness overhead", maximumGas);
    }

    function test_FullBoxSetDrains() public { _run(10_000); }
    function test_FullTicketSetDrains() public { _run(0); }
    function test_FullMixedSetDrains() public { _run(5_000); }
}
