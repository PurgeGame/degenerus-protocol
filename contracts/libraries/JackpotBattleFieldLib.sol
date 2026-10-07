// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {CrapsPreferenceLib} from "./CrapsPreferenceLib.sol";

interface ICrapsPreferenceReader {
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory);
}

/// @dev Game-side preparation of one chunk of the daily draw, at most `MAX_CHUNK` entries. One
///      calldata word per awarded entry: wallet ID [0:31], compact board [160:179], one unit [180].
///      The battle receives this frozen field and makes no storage callbacks.
library JackpotBattleFieldLib {
    /// @dev Most entries one draw call collects and one append accepts; Game and battle share it.
    uint256 internal constant MAX_CHUNK = 50;
    uint256 internal constant BOARD_SHIFT = 160;
    uint256 internal constant UNITS_SHIFT = 180;

    function prepare(uint32[] memory ids) internal view returns (uint256[] memory field) {
        uint256 units = ids.length;
        field = new uint256[](units);
        if (units == 0) return field;

        bytes32[] memory slots = new bytes32[](units);
        uint256[] memory position = new uint256[](units);
        uint256 n;
        uint256 seen;
        unchecked {
            for (uint256 i; i < units; ++i) {
                uint32 id = ids[i];
                // A fresh low-byte bit proves uniqueness; collisions require the exact scan.
                uint256 bit = uint256(1) << uint8(id);
                uint256 j = n;
                if (seen & bit != 0) {
                    j = 0;
                    while (j < n && uint32(field[j]) != id) ++j;
                }
                if (j == n) {
                    field[n] = id;
                    slots[n] = keccak256(abi.encode(id, CrapsPreferenceLib.PASS_SLOT));
                    ++n;
                    seen |= bit;
                }
                position[i] = j;
            }
        }
        assembly ("memory-safe") {
            mstore(slots, n)
        }

        // Exactly one read per distinct PLAYED wallet, in one external call. Pass balances and
        // the initialized sentinel must never enter the battle payload.
        bytes32[] memory saved = ICrapsPreferenceReader(ContractAddresses.CRAPS).extsload(slots);
        for (uint256 i; i < units; ++i) {
            field[i] = uint256(ids[i]) | (uint256(1) << UNITS_SHIFT)
                | (((uint256(saved[position[i]]) & CrapsPreferenceLib.MASK) >> CrapsPreferenceLib.SHIFT) << BOARD_SHIFT);
        }
    }
}
