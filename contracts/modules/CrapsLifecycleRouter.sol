// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsLifecycleViews} from "./CrapsLifecycleViews.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";

/// @dev Lifecycle entries preserve the table's storage root, caller and return payload.
abstract contract CrapsLifecycleRouter is CrapsLifecycleViews {
    function createBattle(
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) external returns (uint64 slot) {
        _delegateLifecycle();
    }

    function closeBattle(uint64 slot) external returns (uint48 index) {
        _delegateLifecycle();
    }

    function donate(bool custom, uint256 index, uint24 granules) external returns (uint256 amount) {
        _delegateLifecycle();
    }

    function setBattleCreator(address account, bool allowed) external {
        _delegateLifecycle();
    }

    function payBattlePot(uint64 slot, bytes32 key, uint256 winnerId, uint256 pot, uint256 boost, uint256 word)
        public
    {
        _delegateLifecycle();
    }

    function runCrapsReadWork(uint48 index, uint256 allowance) external returns (MineFlipGas.Result memory result) {
        _delegateLifecycle();
    }

    function admitCustom(uint64 slot) external {
        _delegateLifecycle();
    }

    function registerRngSlot_g709(uint48 index, uint64 slot, bytes32 key) external {
        _delegateLifecycle();
    }

    function lockJackpotBattle(uint24 requestDay, uint256 pool, uint24 level) external returns (bool locked) {
        _delegateLifecycle();
    }

    function prepareJackpotBattle(uint24 level, uint256 word)
        external returns (uint256 drawWord, uint256 cursor, uint256 remaining)
    {
        _delegateLifecycle();
    }

    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool last) external {
        _delegateLifecycle();
    }

    function settleHighRollerReserve(uint64 slot) external {
        _delegateLifecycle();
    }

    function convertNormalToHigh(uint32 id, uint32 highCount) external {
        _delegateLifecycle();
    }

    function upgradeReservedDay(uint32 id, uint24 day) external {
        _delegateLifecycle();
    }

    function finalizeBattle_g3665(Window calldata w, uint256 board, uint256 word) external {
        _delegateLifecycle();
    }

    function runCrapsMaintenance_g10712(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        _delegateLifecycle();
    }

    function runDailyBattleWork(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        _delegateLifecycle();
    }

    function _delegateLifecycle() internal virtual {
        address target = ContractAddresses.CRAPS_LIFECYCLE_MODULE;
        assembly ("memory-safe") {
            let data := mload(0x40)
            calldatacopy(data, 0, calldatasize())
            let ok := delegatecall(gas(), target, data, calldatasize(), 0, 0)
            returndatacopy(data, 0, returndatasize())
            if iszero(ok) { revert(data, returndatasize()) }
            return(data, returndatasize())
        }
    }
}
