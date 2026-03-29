// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Minimal mock for sDGNRS used by GNRUS unit tests.
///      Exposes settable totalSupply and per-address balances.
contract MockSDGNRSCharity {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function setTotalSupply(uint256 _supply) external {
        totalSupply = _supply;
    }

    function setBalance(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }

    uint256 private _votingSupply;

    function setVotingSupply(uint256 supply) external {
        _votingSupply = supply;
    }

    function votingSupply() external view returns (uint256) {
        // If explicitly set, use that; otherwise return totalSupply as fallback
        return _votingSupply != 0 ? _votingSupply : totalSupply;
    }
}
