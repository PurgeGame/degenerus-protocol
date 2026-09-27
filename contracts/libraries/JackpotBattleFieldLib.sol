// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {CrapsPreferenceLib} from "./CrapsPreferenceLib.sol";

interface ICrapsPreferenceReader {
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory);
}

/// @dev Game-side preparation of one chunk of the daily draw, at most `MAX_CHUNK` entries. One
///      calldata word per awarded entry: address [0:159], compact board [160:179], one unit [180].
///      The battle receives this frozen field and makes no storage callbacks.
library JackpotBattleFieldLib {
    /// @dev Most entries one draw call collects and one append accepts; Game and battle share it.
    uint256 internal constant MAX_CHUNK = 150;
    uint256 internal constant BOARD_SHIFT = 160;
    uint256 internal constant UNITS_SHIFT = 180;

    function prepare(address[] memory entrants) internal view returns (uint256[] memory field) {
        uint256 units = entrants.length;
        field = new uint256[](units);
        if (units == 0) return field;

        bytes32[] memory slots = new bytes32[](units);
        uint256[] memory position = new uint256[](units);
        uint256 n;
        uint256 seen;
        unchecked {
            for (uint256 i; i < units; ++i) {
                address player = entrants[i];
                // A fresh low-byte bit proves uniqueness; collisions require the exact scan.
                uint256 bit = uint256(1) << uint8(uint160(player));
                uint256 j = n;
                if (seen & bit != 0) {
                    j = 0;
                    while (j < n && address(uint160(field[j])) != player) ++j;
                }
                if (j == n) {
                    field[n] = uint160(player);
                    slots[n] = keccak256(abi.encode(player, CrapsPreferenceLib.PASS_SLOT));
                    ++n;
                    seen |= bit;
                }
                position[i] = j;
            }
        }
        assembly ("memory-safe") {
            mstore(slots, n)
        }

        // Exactly one read per distinct PLAYED wallet, in one external call. Pass balances,
        // the initialized sentinel and reserved bits must never enter the battle payload.
        bytes32[] memory saved = ICrapsPreferenceReader(ContractAddresses.CRAPS).extsload(slots);
        for (uint256 i; i < units; ++i) {
            field[i] = uint160(entrants[i]) | (uint256(1) << UNITS_SHIFT)
                | (((uint256(saved[position[i]]) & CrapsPreferenceLib.MASK) >> CrapsPreferenceLib.SHIFT) << BOARD_SHIFT);
        }
    }
}
