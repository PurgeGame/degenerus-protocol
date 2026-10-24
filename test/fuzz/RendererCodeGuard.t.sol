// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Has code, but deliberately returns no ABI string.
contract MalformedP8Renderer {
    fallback() external {}
}

contract RendererCodeGuardTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.prank(ContractAddresses.GAME);
        deityPass.mint(address(this), 1);
        _grantSeat(address(this));
    }

    function testAllCollectionsRejectNoCodeAndRecoverFromMalformedRenderer() public {
        address[3] memory targets = [address(deityPass), address(afkingSubToken), address(recordBounty)];
        uint256[3] memory ids = [uint256(1), _seatOf(address(this)), uint256(0)];
        address malformed = address(new MalformedP8Renderer());
        for (uint256 i; i < targets.length; ++i) {
            bytes memory query = abi.encodeWithSignature("tokenURI(uint256)", ids[i]);
            (bool baselineOk, bytes memory baseline) = targets[i].staticcall(query);
            assertTrue(baselineOk, "built-in metadata works");
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            (bool ok, bytes memory reason) = targets[i].call(abi.encodeWithSignature("setRenderer(address)", address(0xBEEF)));
            assertFalse(ok, "no-code renderer refused");
            assertEq(reason, abi.encodeWithSignature("InvalidRenderer()"));
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            (ok,) = targets[i].call(abi.encodeWithSignature("setRenderer(address)", malformed));
            assertTrue(ok, "code-bearing renderer accepted");
            (ok,) = targets[i].staticcall(query);
            assertFalse(ok, "malformed ABI remains owner-recoverable");
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            (ok,) = targets[i].call(abi.encodeWithSignature("setRenderer(address)", address(0)));
            assertTrue(ok, "owner can disable renderer");
            (ok, reason) = targets[i].staticcall(query);
            assertTrue(ok);
            assertEq(reason, baseline, "built-in metadata restored exactly");
        }
    }
}
