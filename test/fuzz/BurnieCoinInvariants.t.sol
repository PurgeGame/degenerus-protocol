// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

/// @title BurnieCoin Supply Invariant Fuzz Tests
/// @notice Verifies core ERC20 supply invariants under random operations.
/// @dev Uses a minimal standalone token that mirrors BurnieCoin's supply accounting.
///      We can't deploy the real BurnieCoin because ContractAddresses are compile-time
///      constants (address(0) in source). These tests validate the MATH is sound.
contract MockBurnieSupply {
    struct Supply {
        uint128 totalSupply;
        uint128 vaultAllowance;
    }

    Supply public supply;
    mapping(address => uint256) public balanceOf;

    address public constant VAULT = address(0xBA017);

    error ZeroAddress();
    error Insufficient();
    error SupplyOverflow();

    constructor(uint128 initialVaultAllowance) {
        supply = Supply({totalSupply: 0, vaultAllowance: initialVaultAllowance});
    }

    function totalSupply() external view returns (uint256) {
        return supply.totalSupply;
    }

    function vaultAllowance() external view returns (uint256) {
        return supply.vaultAllowance;
    }

    function supplyIncUncirculated() external view returns (uint256) {
        return uint256(supply.totalSupply) + uint256(supply.vaultAllowance);
    }

    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        if (to == VAULT) {
            unchecked {
                supply.vaultAllowance += amount128;
            }
            return;
        }
        supply.totalSupply += amount128;
        balanceOf[to] += amount;
    }

    function burn(address from, uint256 amount) external {
        if (from == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        if (from == VAULT) {
            uint128 va = supply.vaultAllowance;
            if (amount128 > va) revert Insufficient();
            unchecked {
                supply.vaultAllowance = va - amount128;
            }
            return;
        }
        balanceOf[from] -= amount;
        supply.totalSupply -= amount128;
    }

    function transfer(address from, address to, uint256 amount) external {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        balanceOf[from] -= amount;

        if (to == VAULT) {
            uint128 amount128 = _toUint128(amount);
            unchecked {
                supply.totalSupply -= amount128;
                supply.vaultAllowance += amount128;
            }
            return;
        }
        balanceOf[to] += amount;
    }

    function vaultMintTo(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        uint128 va = supply.vaultAllowance;
        if (amount128 > va) revert Insufficient();
        unchecked {
            supply.vaultAllowance = va - amount128;
        }
        supply.totalSupply += amount128;
        balanceOf[to] += amount;
    }

    function _toUint128(uint256 x) internal pure returns (uint128) {
        if (x > type(uint128).max) revert SupplyOverflow();
        return uint128(x);
    }
}

contract BurnieCoinInvariantsTest is Test {
    MockBurnieSupply token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint128 constant INITIAL_VAULT = uint128(2_000_000 ether);

    function setUp() public {
        token = new MockBurnieSupply(INITIAL_VAULT);
    }

    /// @notice supplyIncUncirculated == totalSupply + vaultAllowance always holds
    function testFuzz_supplyInvariant_afterMint(address to, uint128 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount <= 100_000_000 ether);

        uint256 supplyBefore = token.supplyIncUncirculated();
        token.mint(to, amount);
        uint256 supplyAfter = token.supplyIncUncirculated();

        assertEq(
            token.supplyIncUncirculated(),
            uint256(token.totalSupply()) + token.vaultAllowance(),
            "supply invariant broken after mint"
        );

        if (to == token.VAULT()) {
            assertEq(supplyAfter, supplyBefore + amount, "vault mint should increase uncirculated");
        } else {
            assertEq(supplyAfter, supplyBefore + amount, "regular mint should increase uncirculated");
        }
    }

    /// @notice mint then burn same amount: supply returns to original
    function testFuzz_mintBurnRoundtrip(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 100_000_000 ether);

        uint256 supplyBefore = token.supplyIncUncirculated();
        token.mint(alice, amount);
        token.burn(alice, amount);

        assertEq(token.supplyIncUncirculated(), supplyBefore, "mint-burn roundtrip should be identity");
        assertEq(token.balanceOf(alice), 0, "balance should be zero after full burn");
        assertEq(token.totalSupply(), 0, "totalSupply should be zero after full burn");
    }

    /// @notice transfer to vault: totalSupply decreases, vaultAllowance increases, sum unchanged
    function testFuzz_transferToVault(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 100_000_000 ether);

        token.mint(alice, amount);
        uint256 supplyBefore = token.supplyIncUncirculated();
        uint256 tsBefore = token.totalSupply();
        uint256 vaBefore = token.vaultAllowance();

        token.transfer(alice, token.VAULT(), amount);

        assertEq(token.supplyIncUncirculated(), supplyBefore, "vault transfer should not change uncirculated");
        assertEq(token.totalSupply(), tsBefore - amount, "totalSupply should decrease");
        assertEq(token.vaultAllowance(), vaBefore + amount, "vaultAllowance should increase");
        assertEq(token.balanceOf(alice), 0, "sender balance should be zero");
    }

    /// @notice vaultMintTo: vaultAllowance decreases, totalSupply increases, sum unchanged
    function testFuzz_vaultMintTo(uint128 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_VAULT);

        uint256 supplyBefore = token.supplyIncUncirculated();
        token.vaultMintTo(alice, amount);

        assertEq(token.supplyIncUncirculated(), supplyBefore, "vaultMintTo should not change uncirculated");
        assertEq(token.totalSupply(), amount, "totalSupply should equal minted amount");
        assertEq(token.vaultAllowance(), INITIAL_VAULT - amount, "vaultAllowance should decrease");
    }

    /// @notice vaultMintTo reverts if amount exceeds vault allowance
    function testFuzz_vaultMintTo_revertOnExceed(uint128 extra) public {
        vm.assume(extra > 0 && extra <= type(uint128).max - INITIAL_VAULT);
        uint256 amount = uint256(INITIAL_VAULT) + uint256(extra);

        vm.expectRevert(MockBurnieSupply.Insufficient.selector);
        token.vaultMintTo(alice, amount);
    }

    /// @notice multiple operations preserve invariant
    function testFuzz_multiOp(uint128 mintAmt, uint128 transferAmt, uint128 burnAmt) public {
        vm.assume(mintAmt > 0 && mintAmt <= 100_000_000 ether);
        vm.assume(transferAmt <= mintAmt);
        vm.assume(burnAmt <= mintAmt - transferAmt);

        token.mint(alice, mintAmt);
        if (transferAmt > 0) {
            token.transfer(alice, bob, transferAmt);
        }
        if (burnAmt > 0) {
            token.burn(alice, burnAmt);
        }

        assertEq(
            token.supplyIncUncirculated(),
            uint256(token.totalSupply()) + token.vaultAllowance(),
            "supply invariant broken after multi-op"
        );
        assertEq(
            token.balanceOf(alice) + token.balanceOf(bob),
            token.totalSupply(),
            "sum of balances should equal totalSupply"
        );
    }
}
