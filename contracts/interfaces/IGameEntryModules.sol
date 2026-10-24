// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "./IDegenerusGame.sol";

interface IGamePurchaseModule {
    function purchase(uint32 buyerId, uint256 entryQuantityScaled, uint256 boxOrder, bytes32 affiliateCode, MintPaymentKind payKind) external payable;
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind) external payable returns (uint32);
    function redeemFlip(uint32 id, uint256 entryQuantityScaled) external;
    function withdrawAfkingFunding(uint32 id, uint256 amount) external;
    function borrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) external;
    function repay(uint32 id) external payable;
    function sweepAccounts(uint32[] calldata ids) external returns (uint256, uint256);
}

interface IGameMinerModule {
    function mineFlip(uint32 gasMultiplierBps) external;
    function minerAction() external returns (uint8);
}

interface IGameBingoModule {
    function claimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) external;
    function claimAffiliateDgnrs(uint32 id) external;
}

interface IGameBetModule {
    function placeDegeneretteBet(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol) external payable;
}

interface IGameBoonActionsModule {
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16);
    function consumeDecimatorBoon(uint32 id) external returns (uint16);
    function issueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) external;
}
