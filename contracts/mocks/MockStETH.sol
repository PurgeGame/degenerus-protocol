// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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

    /// @dev Annual yield in basis points (250 = 2.5% APR), a fixed test rate for
    ///      deterministic rebase simulation.
    ///      Each rebase() applies one day's share of this rate.
    uint256 public rebaseAprBps = 250;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TransferShares(address indexed from, address indexed to, uint256 shares);

    function balanceOf(address account) public view virtual returns (uint256) {
        if (totalShares == 0) return 0;
        return (sharesOf[account] * totalPooledEther) / totalShares;
    }

    function totalSupply() external view returns (uint256) {
        return totalPooledEther;
    }

    function submit(address) external payable returns (uint256) {
        _admitted(300_000);
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

    function getSharesByPooledEth(uint256 amount) public view virtual returns (uint256) {
        return _ethToShares(amount);
    }

    function getPooledEthByShares(uint256 shares) public view virtual returns (uint256) {
        if (totalShares == 0) return 0;
        return shares * totalPooledEther / totalShares;
    }

    function transferSharesFrom(address from, address to, uint256 shares) public virtual returns (uint256 amount) {
        if (msg.sig == this.transferSharesFrom.selector) _admitted(300_000);
        require(from != address(0) && to != address(0) && to != address(this));
        amount = getPooledEthByShares(shares);
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            allowance[from][msg.sender] = approved - amount;
            emit Approval(from, msg.sender, approved - amount);
        }
        sharesOf[from] -= shares;
        sharesOf[to] += shares;
        emit Transfer(from, to, amount);
        emit TransferShares(from, to, shares);
    }

    /// @dev Simulate daily Lido rebase — increases totalPooledEther by one day
    ///      of the annual rate. All holders' balanceOf() increases proportionally.
    function rebase() external {
        if (totalPooledEther == 0) return;
        totalPooledEther += (totalPooledEther * rebaseAprBps) / (10_000 * 365);
    }

    /// @dev Test helper: adjust annual yield rate in basis points.
    function setRebaseAprBps(uint256 bps) external {
        rebaseAprBps = bps;
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
    /// @dev Test oracle: calls that arrived with less gas than the protocol admits each guarded entry
    ///      point with (stake 300k, AFKing share pull 300k). A failure the protocol swallows is sound
    ///      only at or above that admission, so the count stays zero.
    uint256 public starvedCalls;
    bytes4 public firstStarvedSelector;

    function _admitted(uint256 minimum) internal {
        // Function dispatch precedes this read.
        if (gasleft() + 2_000 >= minimum) return;
        if (starvedCalls++ == 0) firstStarvedSelector = msg.sig;
    }

    function _ethToShares(uint256 ethAmount) private view returns (uint256) {
        if (totalShares == 0 || totalPooledEther == 0) return ethAmount;
        return (ethAmount * totalShares) / totalPooledEther;
    }
}
