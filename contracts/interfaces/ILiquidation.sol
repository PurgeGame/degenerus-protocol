// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

struct LiquidationQuote {
    uint32 accountId;
    uint32 buyerId;
    bool eligible;
    uint256 faceValue;
    uint256 quoteBudget;
    uint256 ticketValue;
    uint256 price;
}

interface ILiquidationDeity {
    function balanceOf(address owner) external view returns (uint256);
}
