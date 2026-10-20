// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

/// @dev Independent fixture encoder supporting arbitrary-order writes within seven levels.
library AffiliateStorage {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant CAP = (uint256(1) << 35) - 1;

    function slot(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), uint256(1)));
    }

    function set(address target, uint32 id, uint24 level, uint256 amount) internal {
        require(level != 0, "fixture level zero");
        uint256 old = uint256(VM.load(target, slot(id)));
        uint24 latest = uint24(old >> 165);
        uint24 next = level > latest ? level : latest;
        require(next - level < 7, "fixture outside retained history");
        uint256 word = (old & ~((uint256(1) << 189) - 1)) | (uint256(next) << 165);
        for (uint256 age; age < 7 && age < next; ++age) {
            uint256 wanted = uint256(next) - age;
            uint256 value;
            if (wanted == level) value = amount > CAP ? CAP : amount;
            else if (wanted <= latest && latest - wanted < 7) {
                uint256 priorAge = uint256(latest) - wanted;
                value = priorAge < 2 ? (old >> (priorAge * 35)) & CAP
                    : (old >> (70 + (priorAge - 2) * 19)) & ((uint256(1) << 19) - 1);
            }
            if (age < 2) word |= value << (age * 35);
            else word |= (value > 500_000 ? 500_000 : value) << (70 + (age - 2) * 19);
        }
        VM.store(target, slot(id), bytes32(word));
    }
}
