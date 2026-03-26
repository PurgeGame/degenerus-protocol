// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Minimal mock for DegenerusGame used by DegenerusCharity unit tests.
///      Supports claimWinnings (sends ETH), claimableWinningsOf, and gameOver.
contract MockGameCharity {
    bool public gameOver;
    mapping(address => uint256) public claimable;

    function setGameOver(bool _over) external {
        gameOver = _over;
    }

    function setClaimable(address player, uint256 amount) external {
        claimable[player] = amount;
    }

    function claimableWinningsOf(address player) external view returns (uint256) {
        return claimable[player];
    }

    function claimWinnings(address player) external {
        uint256 amt = claimable[player];
        if (amt == 0) return;
        claimable[player] = 0;
        (bool ok,) = player.call{value: amt}("");
        require(ok, "ETH transfer failed");
    }

    receive() external payable {}
}
