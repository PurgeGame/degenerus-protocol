// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoinModule} from "./DegenerusGameModuleInterfaces.sol";

interface IDegenerusCoin is IDegenerusCoinModule {
    function creditCoin(address player, uint256 amount) external;

    function burnCoin(address target, uint256 amount) external;

    function notifyQuestMint(address player, uint32 quantity, bool paidWithEth) external;

    function notifyQuestBurn(address player, uint32 quantity) external;

    function notifyQuestLootBox(address player, uint256 amountWei) external;

    function setDeployTime(uint48 timestamp) external;

    function turboFlipPendingBurnieAmount() external view returns (uint256);
}
