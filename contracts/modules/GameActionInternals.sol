// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameComponentCall} from "./GameComponentCall.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IGameActionModule, IGameClaimAll, IGameClaimAmount} from "../interfaces/IGameActionModule.sol";

/// @dev Each hook is called only by its matching facade entry. Forwarding the original
///      calldata preserves that entry's selector, value and any gas-budget trailer.
abstract contract GameActionInternals is GameComponentCall {
    function _gameDrainAffiliateBases(uint256 ids, uint256 uplines) internal virtual returns (uint256, uint256, uint256) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data), (uint256, uint256, uint256));
    }

    function _gameRegisterWallet_g9539(address owner, bool allocate) internal virtual returns (uint32 id) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data), (uint32));
    }

    function _gameRegisterWalletIdentity(address owner) internal virtual returns (uint32 id) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data), (uint32));
    }

    function _gameRecordAfkingSecondary(uint32 id, uint16 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameFloorAfkingStreakBase(uint32 id, uint16 floor) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gamePayRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) internal virtual returns (uint256 paid, address payee) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data), (uint256, address));
    }

    function _gameSetOperatorApproval(uint32 id, address operator, bool approved) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameSetLootboxRngThreshold(uint256 newThreshold) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameSetMiddayMaxBasefee(uint256 newGwei) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameClaimWinnings(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameClaimWinnings(uint32 id, uint256 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameClaimWinningsStethFirst() internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameDepositAfkingFunding(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameAdminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameAdminStakeEthForStEth(uint256 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }

    function _gameReverseFlip(uint256 expectedCost) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, msg.data);
    }
}
