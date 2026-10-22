// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "./GameSlots.sol";

library GamePoolSlots {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function read(address host, uint24 lvl) internal view returns (uint256) {
        uint256 word = uint256(VM.load(host, bytes32(GameSlots.LEVEL_PRIZE_POOL + uint256(lvl & 3))));
        return word >> 128 == uint256(lvl) + 1 ? uint128(word) : 0;
    }

    function write(address host, uint24 lvl, uint256 amount) internal {
        VM.store(host, bytes32(GameSlots.LEVEL_PRIZE_POOL + uint256(lvl & 3)),
            bytes32(((uint256(lvl) + 1) << 128) | uint128(amount)));
    }
}
