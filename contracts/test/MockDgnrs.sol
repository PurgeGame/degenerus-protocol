// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

contract MockDgnrs is IDegenerusStonk {
    error Insufficient();

    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 ether;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 private totalSupply_;

    constructor() {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }

    function vaultEscrow(uint256) external {}

    function depositSteth(uint256) external {}

    function poolBalance(Pool) external pure returns (uint256) {
        return 0;
    }

    function transferFromPool(
        Pool,
        address,
        uint256
    ) external pure returns (uint256 transferred) {
        return transferred;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (msg.sender != ContractAddresses.COIN) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                if (allowed < amount) revert Insufficient();
                unchecked {
                    allowance[from][msg.sender] = allowed - amount;
                }
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return totalSupply_;
    }

    function ethReserve() external pure returns (uint256) {
        return 0;
    }

    function stethReserve() external pure returns (uint256) {
        return 0;
    }

    function burnieReserve() external pure returns (uint256) {
        return 0;
    }

    function vaultMintAllowance() external pure returns (uint256) {
        return 0;
    }

    function totalBacking() external pure returns (uint256) {
        return 0;
    }

    function previewBurn(uint256) external pure returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        ethOut = 0;
        stethOut = 0;
        burnieOut = 0;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (balances[from] < amount) revert Insufficient();
        unchecked {
            balances[from] = balances[from] - amount;
            balances[to] = balances[to] + amount;
        }
    }
}
