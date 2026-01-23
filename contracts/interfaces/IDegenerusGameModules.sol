// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoinModule} from "./DegenerusGameModuleInterfaces.sol";
import {MintPaymentKind} from "./IDegenerusGame.sol";

interface IDegenerusGameAdvanceModule {
    function advanceGame(uint32 cap) external;

    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;

    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;

    function reverseFlip(address player) external;

    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external;
}

interface IDegenerusGameEndgameModule {
    function finalizeEndgame(uint24 lvl, uint256 rngWord) external;
    function payExterminatorOnJackpot(uint24 lvl, uint256 rngWord) external;
    function rewardTopAffiliate(uint24 lvl) external;
    function claimWhalePass(address player) external;
}

interface IDegenerusGameGameOverModule {
    function handleGameOverDrain(uint48 day) external;
    function handleFinalSweep() external;
}

interface IDegenerusGameJackpotModule {
    function payDailyJackpot(
        bool isDaily,
        uint24 lvl,
        uint256 randWord
    ) external;

    function payTicketJackpot(
        uint24 lvl,
        uint256 randWord
    ) external;

    function payExterminationJackpot(
        uint24 lvl,
        uint8 traitId,
        uint256 randWord,
        uint256 ethPool
    ) external returns (uint256 paidEth);

    function payPurchaseRewardLootbox(
        uint24 lvl,
        uint8 traitId,
        uint256 randWord,
        uint256 lootboxBudget
    ) external returns (address[] memory winners, uint256[] memory ethAmounts);

    function payLevelJackpotLootbox(
        uint24 lvl,
        uint256 rngWord,
        uint256 effectiveWei
    ) external;

    function payLevelJackpotEth(
        uint24 lvl,
        uint256 rngWord
    ) external;

    function calcPrizePoolForLevelJackpot(
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 effectiveWei);

    function processTicketBatchLegacy(uint32 writesBudget) external returns (bool finished);

    function processTicketBatch(uint32 writesBudget, uint24 lvl) external returns (bool finished);

    function payEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) external;

    function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external;
}

interface IDegenerusGameDecimatorModule {
    function creditDecJackpotClaimBatch(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 rngWord
    ) external;

    function burnTokens(
        address player,
        uint256[] calldata tokenIds
    ) external;
}

interface IDegenerusGameWhaleModule {
    function purchaseWhaleBundle(address buyer, uint256 quantity) external payable;

    function purchaseWhaleBundle10(address buyer, uint256 quantity) external payable;

    function purchaseDeityPass(address buyer, uint256 quantity) external payable;

    function redeemWhaleBundle10Pass(address buyer, uint256 quantity) external;
}

interface IDegenerusGameMintModule {
    function recordMintData(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) external payable returns (uint256 coinReward);

    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    function openLootBox(address player, uint48 lootboxIndex) external;

    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) external;

    function processFutureTicketBatch(
        uint32 playersToProcess,
        uint24 lvl
    ) external returns (bool worked, bool finished);

    function calculateAirdropMultiplier(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount,
        uint24 lvl
    ) external pure returns (uint32);

    function purchaseTargetCountFromRaw(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount
    ) external view returns (uint32);

    function rebuildTraitCounts(
        uint32 tokenBudget,
        uint32 target,
        uint256 baseTokenId
    ) external returns (bool finished);
}

interface IDegenerusGameLootboxModule {
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;
    function rollLootboxRng(address player) external;
}

interface IDegenerusGameLootboxOpenModule {
    function openLootBox(address player, uint48 lootboxIndex) external;
    function openBurnieLootBox(address player, uint48 lootboxIndex) external;

    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) external;
}
