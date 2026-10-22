// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "./GameSlots.sol";

/// @dev Fund an ordinary claimable balance and its backing for test setup.
library ClaimableSeed {
    function fund(Vm vm, address game, address payer, uint32 id, uint256 amount) internal {
        vm.deal(payer, payer.balance - amount);
        vm.deal(game, game.balance + amount);
        bytes32 balance = keccak256(abi.encode(uint256(id), GameSlots.BALANCES_PACKED));
        vm.store(game, balance, bytes32(uint256(vm.load(game, balance)) + amount));
        bytes32 pool = bytes32(GameSlots.CLAIMABLE_POOL);
        vm.store(game, pool, bytes32(uint256(vm.load(game, pool)) + (amount << (GameSlots.CLAIMABLE_POOL_OFFSET * 8))));
    }
}
