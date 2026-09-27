// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {CrapsPreferenceLib} from "./CrapsPreferenceLib.sol";

interface ICrapsPreferenceReader {
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory);
}

/// @dev Game-side preparation of the at-most-50-entry daily draw. One calldata word per
///      distinct played wallet: address [0:159], compact board [160:179], units [180:185].
///      The battle receives this frozen field and makes no storage callbacks.
library JackpotBattleFieldLib {
    uint256 internal constant BOARD_SHIFT = 160;
    uint256 internal constant UNITS_SHIFT = 180;
    uint256 internal constant BANKROLL_UNIT = 300 ether;

    function prepare(address[] memory entrants, uint256 amount) internal view returns (uint256[] memory field) {
        uint256 units = entrants.length;
        uint256 affordable = ((amount * 2) / 3) / BANKROLL_UNIT;
        if (units > affordable) units = affordable;
        field = new uint256[](units);
        if (units == 0) return field;

        bytes32[] memory slots = new bytes32[](units);
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
                field[j] += uint256(1) << UNITS_SHIFT;
            }
        }
        assembly ("memory-safe") {
            mstore(field, n)
            mstore(slots, n)
        }

        // Exactly one read per distinct PLAYED wallet, in one external call. Pass balances,
        // the initialized sentinel and reserved bits must never enter the battle payload.
        bytes32[] memory saved = ICrapsPreferenceReader(ContractAddresses.CRAPS).extsload(slots);
        for (uint256 j; j < n; ++j) {
            field[j] |= ((uint256(saved[j]) & CrapsPreferenceLib.MASK) >> CrapsPreferenceLib.SHIFT) << BOARD_SHIFT;
        }
    }
}
