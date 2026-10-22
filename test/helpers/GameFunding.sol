// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots, GameSlotKeys} from "./GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title GameFunding
/// @notice Seeds backed Game ledger state for tests, replacing the retired payable credit door.
library GameFunding {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Credit `amount` of claimable winnings to wallet `id`: ledger, claimablePool and the
    ///      Game's ETH move together.
    function credit(uint32 id, uint256 amount) internal {
        address game = ContractAddresses.GAME;
        bytes32 key = GameSlotKeys.balances(id);
        vm.store(game, key, bytes32(uint256(vm.load(game, key)) + amount));
        addPool(amount);
        vm.deal(game, game.balance + amount);
    }

    /// @dev Set wallet `id`'s claimable to exactly `amount` (afking half untouched), moving
    ///      claimablePool and the Game's ETH by the difference.
    function setClaimable(uint32 id, uint256 amount) internal {
        address game = ContractAddresses.GAME;
        bytes32 key = GameSlotKeys.balances(id);
        uint256 word = uint256(vm.load(game, key));
        uint256 old = uint128(word);
        vm.store(game, key, bytes32((word & ~uint256(type(uint128).max)) | amount));
        if (amount >= old) {
            addPool(amount - old);
            vm.deal(game, game.balance + (amount - old));
        } else {
            uint256 down = old - amount;
            uint256 s1 = uint256(vm.load(game, bytes32(GameSlots.CLAIMABLE_POOL)));
            vm.store(game, bytes32(GameSlots.CLAIMABLE_POOL),
                bytes32((s1 & type(uint128).max) | (((s1 >> 128) - down) << 128)));
            vm.deal(game, game.balance > down ? game.balance - down : 0);
        }
    }

    /// @dev Raise claimablePool (the high half of its slot) without touching a wallet or ETH.
    function addPool(uint256 amount) internal {
        address game = ContractAddresses.GAME;
        uint256 s1 = uint256(vm.load(game, bytes32(GameSlots.CLAIMABLE_POOL)));
        uint256 pool = (s1 >> 128) + amount;
        vm.store(game, bytes32(GameSlots.CLAIMABLE_POOL), bytes32((s1 & type(uint128).max) | (pool << 128)));
    }

    /// @dev Set the Game's redemption reserve to exactly `amount`, moving claimablePool and the
    ///      Game's ETH by the difference.
    function setReserve(uint256 amount) internal {
        address game = ContractAddresses.GAME;
        uint256 old = uint256(vm.load(game, bytes32(GameSlots.REDEMPTION_RESERVE_STORED))) - 1;
        vm.store(game, bytes32(GameSlots.REDEMPTION_RESERVE_STORED), bytes32(amount + 1));
        if (amount >= old) {
            addPool(amount - old);
            vm.deal(game, game.balance + (amount - old));
        } else {
            uint256 down = old - amount;
            uint256 s1 = uint256(vm.load(game, bytes32(GameSlots.CLAIMABLE_POOL)));
            vm.store(game, bytes32(GameSlots.CLAIMABLE_POOL),
                bytes32((s1 & type(uint128).max) | (((s1 >> 128) - down) << 128)));
            vm.deal(game, game.balance > down ? game.balance - down : 0);
        }
    }

    /// @dev Add `amount` to the Game's redemption reserve and claimablePool, backed by ETH.
    function reserve(uint256 amount) internal {
        address game = ContractAddresses.GAME;
        uint256 stored = uint256(vm.load(game, bytes32(GameSlots.REDEMPTION_RESERVE_STORED)));
        vm.store(game, bytes32(GameSlots.REDEMPTION_RESERVE_STORED), bytes32(stored + amount));
        addPool(amount);
        vm.deal(game, game.balance + amount);
    }
}
