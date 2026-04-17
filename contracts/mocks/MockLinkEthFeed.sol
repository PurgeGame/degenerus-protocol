// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Mock Chainlink AggregatorV3 price feed for LINK/ETH
contract MockLinkEthFeed {
    int256 public price;
    uint8 public constant decimals = 18;
    uint80 private _roundId = 1;
    uint256 private _updatedAt;

    constructor(int256 _price) {
        price = _price;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, price, _updatedAt, _updatedAt, _roundId);
    }

    /// @dev Test helper: update the price and refresh timestamp
    function setPrice(int256 newPrice) external {
        price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
    }

    /// @dev Test helper: set a stale timestamp
    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }
}
