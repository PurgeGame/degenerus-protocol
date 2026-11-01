// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract HalfPassSaturationHarness is WalletSeed {
    function seed(address owner) external returns (uint32) { return _seedWallet(owner); }
    function add(uint32 id, uint256 n) external { _addHalfPasses(id, n); }
    function halfPasses(address owner) external view returns (uint256) { return _halfPassesOf(owner); }
    function walletKey(uint32 id) external view returns (address) { return _walletKey(id); }
    function element(uint32 id) external view returns (uint256) { return _walletElement(id); }
}

/// @title HalfPassSaturation
/// @notice Half passes are credited on payout paths inside the mining chain. The count is the
///         wallet element's top field: it saturates at that field's maximum instead of reverting,
///         and never carries into the account key or owner bits below it.
contract HalfPassSaturationTest is Test {
    HalfPassSaturationHarness private h;
    address private owner = address(0xA11CE);
    uint32 private id;

    function setUp() public {
        h = new HalfPassSaturationHarness();
        id = h.seed(owner);
    }

    function test_countSaturatesAndKeepsTheLowerBits() public {
        uint256 lowBefore = h.element(id) & ((uint256(1) << 192) - 1);
        h.add(id, type(uint64).max - 3);
        h.add(id, 10);
        assertEq(h.halfPasses(owner), type(uint64).max, "the count stops at its field maximum");
        h.add(id, type(uint256).max);
        assertEq(h.halfPasses(owner), type(uint64).max, "a full-width credit saturates");
        assertEq(h.element(id) & ((uint256(1) << 192) - 1), lowBefore, "account key and owner bits untouched");
        assertEq(h.walletKey(id), owner, "the wallet still names its owner");
    }

    function test_belowTheMaximumAddsExactly() public {
        h.add(id, 7);
        h.add(id, 5);
        assertEq(h.halfPasses(owner), 12, "exact below the maximum");
    }
}
