// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IDegenerusJackpots
/// @notice Interface for the jackpot distribution contract.
/// @dev Handles BAF (Biggest and First) and Decimator jackpot calculations and payouts.
interface IDegenerusJackpots {
    /// @notice Run the BAF (Biggest and First) jackpot distribution for a level.
    /// @dev Uses VRF randomness for winner selection. Access restricted to game contract.
    /// @param poolWei Total ETH pool to distribute.
    /// @param lvl The level being settled.
    /// @param rngWord VRF random word for winner selection.
    /// @return winners Array of winning addresses.
    /// @return amounts Array of corresponding payout amounts.
    /// @return winnerMask Bitpacked winner eligibility mask.
    /// @return returnAmountWei Amount of pool returned (undistributed).
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    )
        external
        returns (address[] memory winners, uint256[] memory amounts, uint256 winnerMask, uint256 returnAmountWei);

    /// @notice Run the Decimator jackpot distribution for a level.
    /// @dev Uses VRF randomness and bucket weighting for winner selection. Access restricted to game contract.
    /// @param poolWei Total ETH pool to distribute.
    /// @param lvl The level being settled.
    /// @param rngWord VRF random word for winner selection.
    /// @return returnAmountWei Amount of pool returned (undistributed).
    function runDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);

    /// @notice Record a BAF (coinflip) deposit for jackpot eligibility tracking.
    /// @param player The player making the deposit.
    /// @param lvl The current game level.
    /// @param amount The amount deposited (for leaderboard ranking).
    function recordBafFlip(address player, uint24 lvl, uint256 amount) external;

    /// @notice Record a decimator burn for jackpot eligibility tracking.
    /// @param player The player burning tokens.
    /// @param lvl The current game level.
    /// @param bucket Preferred bucket (2-12) for entry placement.
    /// @param baseAmount Base amount before multiplier.
    /// @param multBps Multiplier in basis points (10000 = 1x).
    /// @return bucketUsed The actual bucket used for entry (may differ from requested).
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint8 bucket,
        uint256 baseAmount,
        uint256 multBps
    ) external returns (uint8 bucketUsed);
}
