// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

interface IGameClaimAll { function claimWinnings(uint32 id) external; }
interface IGameClaimAmount { function claimWinnings(uint32 id, uint256 amount) external; }

interface IGameActionModule {
    function raiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) external;
    function drainAffiliateBases(uint256 ids, uint256 uplines) external returns (uint256, uint256, uint256);
    function registerWallet_g9539(address owner, bool allocate) external returns (uint32 id);
    function registerWalletIdentity(address owner) external returns (uint32 id);
    function recordAfkingSecondary_g3316(uint32 id, uint16 amount) external;
    function floorAfkingStreakBase(uint32 id, uint16 floor) external;
    function payRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) external returns (uint256 paid, address payee);
    function setOperatorApproval(uint32 id, address operator, bool approved) external;
    function setLootboxRngThreshold(uint256 newThreshold) external;
    function setMiddayMaxBasefee(uint256 newGwei) external;
    function claimWinnings(uint32 id) external;
    function claimWinnings(uint32 id, uint256 amount) external;
    function claimWinningsStethFirst() external;
    function depositAfkingFunding(uint32 id) external payable;
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable;
    function adminStakeEthForStEth(uint256 amount) external;
    function reverseFlip(uint256 expectedCost) external;
}
