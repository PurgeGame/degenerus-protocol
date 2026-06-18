// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title DelegateOnlyGuards -- payable delegatecall-only module entrypoints reject direct calls
/// @notice The Game delegatecalls these module entrypoints, so under the nested dispatch
///         `address(this) == GAME`. A DIRECT call on the deployed module address would run
///         against the module's empty local state and trap the caller's `msg.value`, so each
///         guards `address(this) == GAME` and reverts a direct call. Regression for the
///         `buyPresaleBox` / `purchaseLazyPass` / `purchaseDeityPass` guards (the same class as
///         the v67 DELEGATE-FIND-01 fix for the Boon / resolveLootboxDirect entrypoints).
contract DelegateOnlyGuards is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.deal(address(this), 10 ether);
    }

    function test_buyPresaleBox_directCallReverts() public {
        vm.expectRevert();
        mintModule.buyPresaleBox{value: 1 ether}(address(this), 1 ether);
    }

    function test_purchaseLazyPass_directCallReverts() public {
        vm.expectRevert();
        whaleModule.purchaseLazyPass{value: 1 ether}(address(this));
    }

    function test_purchaseDeityPass_directCallReverts() public {
        vm.expectRevert();
        whaleModule.purchaseDeityPass{value: 1 ether}(address(this), 0);
    }
}
