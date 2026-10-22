// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusAdmin, ILinkTokenLike, IAggregatorV3, IVRFCoordinatorV2_5Owner}
    from "../../contracts/DegenerusAdmin.sol";

contract AdminHostileTarget {
    bytes4 private immutable selected;
    uint256 private immutable mode;

    constructor(bytes4 selected_, uint256 mode_) { selected = selected_; mode = mode_; }

    fallback() external {
        uint256 action = msg.sig == selected ? mode : 100;
        bytes4 errorSelector = MineFlipGas.WorkGasBound.selector;
        assembly ("memory-safe") {
            switch action
            case 0 { revert(0, 0) }
            case 1 { invalid() }
            case 2 { return(0, 31) }
            case 4 {
                mstore(0, errorSelector)
                revert(0, 4)
            }
            case 5 {
                mstore(0, 2)
                return(0, 32)
            }
            case 6 {
                mstore(0, shl(80, 1))
                return(0, 160)
            }
            case 7 {
                for {} gt(gas(), 1000) {} {}
                mstore(0, 1)
                return(0, 32)
            }
            default {
                let ptr := mload(64)
                mstore(ptr, 1)
                mstore(add(ptr, 32), 4000000000000000)
                mstore(add(ptr, 64), timestamp())
                mstore(add(ptr, 96), timestamp())
                mstore(add(ptr, 128), 1)
                if eq(action, 3) { return(ptr, 32768) }
                return(ptr, 160)
            }
        }
    }
}

contract AdminIsolationTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }

    function _etch(address target, bytes4 selector, uint256 mode) private {
        vm.etch(target, address(new AdminHostileTarget(selector, mode)).code);
    }

    function testFeedAllFailureModesReturnZeroAndOversizeUsesBoundedTuple() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 7; ++mode) {
            _etch(address(mockFeed), IAggregatorV3.latestRoundData.selector, mode);
            assertEq(admin.linkAmountToEth(1 ether), mode == 3 ? 0.004 ether : 0);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testFeedUnderfundingRevertsInsteadOfZero() public {
        (bool ok, bytes memory reason) = address(admin).staticcall{gas: 55_000}(
            abi.encodeWithSelector(admin.linkAmountToEth.selector, 1 ether)
        );
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
    }

    function testShutdownCoordinatorFailuresDoNotBlockRetirement() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 6; ++mode) {
            _etch(address(mockVRF), IVRFCoordinatorV2_5Owner.cancelSubscription.selector, mode);
            vm.prank(address(game));
            admin.shutdownVrf();
            assertEq(admin.subscriptionId(), 0);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testShutdownLinkBalanceFailuresDoNotBlockRetirement() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 6; ++mode) {
            _etch(address(mockLINK), ILinkTokenLike.balanceOf.selector, mode);
            vm.prank(address(game));
            admin.shutdownVrf();
            assertEq(admin.subscriptionId(), 0);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testShutdownLinkTransferFailuresDoNotBlockRetirement() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 6; ++mode) {
            _etch(address(mockLINK), ILinkTokenLike.transfer.selector, mode);
            vm.prank(address(game));
            admin.shutdownVrf();
            assertEq(admin.subscriptionId(), 0);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testShutdownUnderfundingAtEachBoundaryRollsBackRetirement() public {
        uint256 sub = admin.subscriptionId();
        uint256 snapshot = vm.snapshotState();
        uint256[3] memory gasLimits = [uint256(250_000), 350_000, 480_000];
        for (uint256 site; site < 3; ++site) {
            if (site != 0) _etch(address(mockVRF), IVRFCoordinatorV2_5Owner.cancelSubscription.selector, 7);
            if (site == 2) _etch(address(mockLINK), ILinkTokenLike.balanceOf.selector, 7);
            vm.prank(address(game));
            (bool ok, bytes memory reason) = address(admin).call{gas: gasLimits[site]}(
                abi.encodeWithSelector(admin.shutdownVrf.selector)
            );
            assertFalse(ok);
            assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
            assertEq(admin.subscriptionId(), sub);
            assertTrue(vm.revertToState(snapshot));
        }
    }
}
