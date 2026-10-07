// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "./GameSlots.sol";

/// @title DegeneretteQueue -- test-side readers for queued Degenerette bets.
/// @notice A bet is a 128-bit lane at keccak256(degeneretteQueue[index & 1].slot) + position / 2; its id is
///         the position + 1, so the buffer's bet count is the newest bet's id. The write buffer's
///         count lives in lootboxRngPacked bits 152..183, the sealed read buffer's in
///         degeneretteReadCount. The word packs owner wallet ID [0..31] | symbol [32..36] |
///         spins [37..41] | currency [42] |
///         record flag [43] | activity [44..59] | stake units [60..123] (ETH gwei, FLIP
///         whole). DegeneretteResolved carries five bytes per spin: player traits (big-endian)
///         then score | house wilds << 4.
library DegeneretteQueue {
    uint256 internal constant QUEUE_SLOT = GameSlots.DEGENERETTE_QUEUE;
    bytes32 internal constant PLACED_SIG = keccak256("DegeneretteBetPlaced(uint32,uint32,uint64,uint256)");
    bytes32 internal constant RESOLVED_SIG =
        keccak256("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)");

    /// @dev The newest bet id at `index` (the buffer's bet count).
    function lastBetId(Vm vm, address game, uint48 index) internal view returns (uint64) {
        uint256 writeBuffer = (uint256(vm.load(game, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES))) >> 252) & 1;
        if ((index & 1) == writeBuffer) {
            return uint64((uint256(vm.load(game, bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 152) & 0xFFFFFFFF);
        }
        return uint64(
            (uint256(vm.load(game, bytes32(GameSlots.DEGENERETTE_READ_COUNT)))
                >> (GameSlots.DEGENERETTE_READ_COUNT_OFFSET * 8)) & 0xFFFFFFFF
        );
    }

    /// @dev Bet word with id `betId` at `index`.
    function betAt(Vm vm, address game, uint48 index, uint64 betId) internal view returns (uint256) {
        bytes32 data = keccak256(abi.encode(uint256(keccak256(abi.encode(uint256(index & 1), QUEUE_SLOT)))));
        if (betId == 0) return 0;
        uint256 p = uint256(betId) - 1;
        uint128 lane = uint128(uint256(vm.load(game, bytes32(uint256(data) + (p >> 1)))) >> ((p & 1) * 128));
        return lane;
    }

    function owner(uint256 bet) internal pure returns (address) {
        return address(uint160(uint32(bet)));
    }

    function spinCount(uint256 bet) internal pure returns (uint8) {
        return uint8((bet >> 37) & 0x1F);
    }

    function currency(uint256 bet) internal pure returns (uint8) {
        return uint8((bet >> 42) & 1);
    }

    function activity(uint256 bet) internal pure returns (uint16) {
        return uint16(bet >> 44);
    }

    /// @dev Per-spin stake in wei.
    function stake(uint256 bet) internal pure returns (uint128) {
        uint256 unit = currency(bet) == 0 ? 1 gwei : 1;
        return uint128(((bet >> 60) & type(uint64).max) * unit);
    }

    /// @dev Spin `i` of a DegeneretteResolved `spins` payload.
    function spinAt(bytes memory spins, uint256 i)
        internal
        pure
        returns (uint32 playerTraits, uint8 score, uint8 wilds)
    {
        uint256 o = i * 5;
        playerTraits = (uint32(uint8(spins[o])) << 24) | (uint32(uint8(spins[o + 1])) << 16)
            | (uint32(uint8(spins[o + 2])) << 8) | uint32(uint8(spins[o + 3]));
        uint8 tail = uint8(spins[o + 4]);
        score = tail & 0x0F;
        wilds = tail >> 4;
    }
}
