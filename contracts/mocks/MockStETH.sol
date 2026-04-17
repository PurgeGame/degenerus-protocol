// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Mock Lido stETH with shares-based rebase model.
///      balanceOf grows passively when rebase() is called (no holder enumeration).
///      Mirrors real Lido: balance = shares[acc] * totalPooledEther / totalShares.
contract MockStETH {
    string public constant name = "Mock stETH";
    string public constant symbol = "stETH";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public sharesOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalPooledEther;
    uint256 public totalShares;

    /// @dev Daily yield in basis points (10 = 0.10% ≈ 3.65% APY).
    uint256 public rebaseYieldBps = 10;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address account) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (sharesOf[account] * totalPooledEther) / totalShares;
    }

    function totalSupply() external view returns (uint256) {
        return totalPooledEther;
    }

    function submit(address) external payable returns (uint256) {
        uint256 shares = _ethToShares(msg.value);
        sharesOf[msg.sender] += shares;
        totalShares += shares;
        totalPooledEther += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
        return shares;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 shares = _ethToShares(amount);
        sharesOf[msg.sender] -= shares;
        sharesOf[to] += shares;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        uint256 shares = _ethToShares(amount);
        sharesOf[from] -= shares;
        sharesOf[to] += shares;
        emit Transfer(from, to, amount);
        return true;
    }

    /// @dev Simulate daily Lido rebase — increases totalPooledEther by yield %.
    ///      All holders' balanceOf() increases proportionally.
    function rebase() external {
        if (totalPooledEther == 0) return;
        totalPooledEther += (totalPooledEther * rebaseYieldBps) / 10_000;
    }

    /// @dev Test helper: adjust daily yield rate.
    function setRebaseYieldBps(uint256 bps) external {
        rebaseYieldBps = bps;
    }

    /// @dev Test helper: mint stETH directly (calculates shares at current rate).
    function mint(address to, uint256 amount) external {
        uint256 shares = _ethToShares(amount);
        sharesOf[to] += shares;
        totalShares += shares;
        totalPooledEther += amount;
        emit Transfer(address(0), to, amount);
    }

    receive() external payable {
        uint256 shares = _ethToShares(msg.value);
        sharesOf[msg.sender] += shares;
        totalShares += shares;
        totalPooledEther += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    /// @dev Convert ETH amount to shares at current exchange rate (1:1 if first deposit).
    function _ethToShares(uint256 ethAmount) private view returns (uint256) {
        if (totalShares == 0 || totalPooledEther == 0) return ethAmount;
        return (ethAmount * totalShares) / totalPooledEther;
    }
}
