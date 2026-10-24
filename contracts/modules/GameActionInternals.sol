// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameComponentCall} from "./GameComponentCall.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IGameActionModule, IGameClaimAll, IGameClaimAmount} from "../interfaces/IGameActionModule.sol";

abstract contract GameActionInternals is GameComponentCall {
    function _gameDrainAffiliateBases(uint256 ids, uint256 uplines) internal virtual returns (uint256, uint256, uint256) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.drainAffiliateBases.selector, ids, uplines)), (uint256, uint256, uint256));
    }

    function _gameRegisterWallet_g9539(address owner, bool allocate) internal virtual returns (uint32 id) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.registerWallet_g9539.selector, owner, allocate)), (uint32));
    }

    function _gameRegisterWalletIdentity(address owner) internal virtual returns (uint32 id) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.registerWalletIdentity.selector, owner)), (uint32));
    }

    function _gameRecordAfkingSecondary(uint32 id, uint16 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.recordAfkingSecondary.selector, id, amount));
    }

    function _gameFloorAfkingStreakBase(uint32 id, uint16 floor) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.floorAfkingStreakBase.selector, id, floor));
    }

    function _gamePayRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) internal virtual returns (uint256 paid, address payee) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.payRecordSdgnrs.selector, id, shareBps)), (uint256, address));
    }

    function _gameSetOperatorApproval(uint32 id, address operator, bool approved) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.setOperatorApproval.selector, id, operator, approved));
    }

    function _gameSetLootboxRngThreshold(uint256 newThreshold) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.setLootboxRngThreshold.selector, newThreshold));
    }

    function _gameSetMiddayMaxBasefee(uint256 newGwei) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.setMiddayMaxBasefee.selector, newGwei));
    }

    function _gameClaimWinnings(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameClaimAll.claimWinnings.selector, id));
    }

    function _gameClaimWinnings(uint32 id, uint256 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameClaimAmount.claimWinnings.selector, id, amount));
    }

    function _gameClaimWinningsStethFirst() internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.claimWinningsStethFirst.selector));
    }

    function _gameDepositAfkingFunding(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.depositAfkingFunding.selector, id));
    }

    function _gameAdminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.adminSwapEthForStEth.selector, recipient, amount));
    }

    function _gameAdminStakeEthForStEth(uint256 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.adminStakeEthForStEth.selector, amount));
    }

    function _gameReverseFlip(uint256 expectedCost) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ACTIONS_MODULE, abi.encodeWithSelector(IGameActionModule.reverseFlip.selector, expectedCost));
    }
}
