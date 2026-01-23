// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MintPaymentKind} from "./IDegenerusGame.sol";

/**
 * @title IBurnieLootbox
 * @notice Interface for BurnieLootbox contract - handles all lootbox purchasing and opening logic.
 */
interface IBurnieLootbox {
    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Purchase lootboxes with ETH.
    /// @param buyer The player making the purchase.
    /// @param gamepieceQuantity Number of gamepieces purchased (for reward calculations).
    /// @param ticketQuantity Number of tickets purchased (2 decimals, scaled by 100).
    /// @param lootBoxAmount Amount of lootbox (in wei).
    /// @param affiliateCode Affiliate referral code.
    /// @param payKind Payment type (ETH or stETH).
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    /// @notice Purchase lootboxes with BURNIE.
    /// @param buyer The player making the purchase.
    /// @param burnieAmount Amount of BURNIE to spend.
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;

    /// @notice Open an ETH lootbox.
    /// @param player The player opening the lootbox.
    /// @param index The lootbox index to open.
    function openLootBox(address player, uint48 index) external;

    /// @notice Open a BURNIE lootbox.
    /// @param player The player opening the lootbox.
    /// @param index The lootbox index to open.
    function openBurnieLootBox(address player, uint48 index) external;

    /// @notice Resolve lootbox directly with RNG (for decimator claims).
    /// @param player The player receiving the lootbox.
    /// @param amount The lootbox amount.
    /// @param rngWord The VRF random word.
    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) external;

    /*+======================================================================+
      |                       RNG PROCESSING                                 |
      +======================================================================+*/

    /// @notice Resolve lootbox RNG for a day (called by game contract).
    /// @param rngWord The VRF random word.
    /// @param day The day index.
    function resolveLootboxRng(uint256 rngWord, uint48 day) external;

    /*+======================================================================+
      |                       BOON CONSUMPTION                               |
      +======================================================================+*/

    /// @notice Check and consume coinflip boon (called by game contract).
    /// @param player The player to check.
    /// @return boonBps The bonus BPS (500/1000/2500 for 5%/10%/25%, 0 if none).
    function consumeCoinflipBoon(address player) external returns (uint16 boonBps);

    /// @notice Check and consume gamepiece boost (called by game contract).
    /// @param player The player to check.
    /// @return boostBps The boost BPS (500/1500/2500 for 5%/15%/25%, 0 if none).
    function consumeGamepieceBoost(address player) external returns (uint16 boostBps);

    /// @notice Check and consume ticket boost (called by game contract).
    /// @param player The player to check.
    /// @return boostBps The boost BPS (500/1500/2500 for 5%/15%/25%, 0 if none).
    function consumeTicketBoost(address player) external returns (uint16 boostBps);

    /// @notice Check and consume decimator boost (called by game contract).
    /// @param player The player to check.
    /// @return boostBps The boost BPS (1000/2500/5000 for 10%/25%/50%, 0 if none).
    function consumeDecimatorBoost(address player) external returns (uint16 boostBps);

    /// @notice Check and consume burn boon (called by game contract).
    /// @param player The player to check.
    /// @return bonusAmount The bonus BURNIE amount (100 ether if active, 0 if not).
    function consumeBurnBoon(address player) external returns (uint256 bonusAmount);

    /// @notice Check whale boon validity (called by game contract).
    /// @param player The player to check.
    /// @return hasWhaleBoon Whether player has an active whale boon.
    function hasWhaleBoon(address player) external view returns (bool hasWhaleBoon);

    /// @notice Consume whale boon (called by game contract after validation).
    /// @param player The player consuming the boon.
    function consumeWhaleBoon(address player) external;

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Get lootbox amount for a player on a specific day.
    /// @param player The player to check.
    /// @param day The day index.
    /// @return amount The lootbox amount (in wei).
    function lootboxAmountFor(address player, uint48 day) external view returns (uint256 amount);

    /// @notice Get BURNIE lootbox amount for a player on a specific day.
    /// @param player The player to check.
    /// @param day The day index.
    /// @return amount The BURNIE lootbox amount (in wei).
    function burnieLootboxAmountFor(address player, uint48 day) external view returns (uint256 amount);

    /// @notice Get current purchase day.
    /// @return day The current day index.
    function currentPurchaseDay() external view returns (uint48 day);

    /// @notice Get current lootbox index (for RNG resolution).
    /// @return index The current index.
    function currentLootboxIndex() external view returns (uint48 index);

    /// @notice Get RNG word for a lootbox index.
    /// @param index The lootbox index.
    /// @return rngWord The VRF random word (0 if not yet resolved).
    function lootboxRngWordForIndex(uint48 index) external view returns (uint256 rngWord);

    /// @notice Get total pending BURNIE lootbox amount.
    /// @return amount The total pending BURNIE (in wei).
    function lootboxRngPendingBurnieAmount() external view returns (uint256 amount);
}
