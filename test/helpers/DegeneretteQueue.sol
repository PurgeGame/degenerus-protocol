// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";

/// @title DegeneretteQueue -- test-side readers for queued Degenerette bets.
/// @notice A bet is one word in the Game's degeneretteQueue[index] (mapping root slot 21); its
///         id is the queue position + 1, so the queue length is the newest bet's id. The word
///         packs owner [0..159] | symbol [160..164] | spins [165..169] | currency [170] |
///         record flag [171] | activity [172..187] | stake units [188..251] (ETH gwei, FLIP
///         whole). DegeneretteResolved carries five bytes per spin: player traits (big-endian)
///         then score | gold << 4.
library DegeneretteQueue {
    uint256 internal constant QUEUE_SLOT = 21;
    bytes32 internal constant PLACED_SIG = keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)");
    bytes32 internal constant RESOLVED_SIG =
        keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");

    /// @dev The newest bet id at `index` (the queue length).
    function lastBetId(Vm vm, address game, uint48 index) internal view returns (uint64) {
        return uint64(uint256(vm.load(game, keccak256(abi.encode(uint256(index), QUEUE_SLOT)))));
    }

    function owner(uint256 bet) internal pure returns (address) {
        return address(uint160(bet));
    }

    function spinCount(uint256 bet) internal pure returns (uint8) {
        return uint8((bet >> 165) & 0x1F);
    }

    function currency(uint256 bet) internal pure returns (uint8) {
        return uint8((bet >> 170) & 1);
    }

    function activity(uint256 bet) internal pure returns (uint16) {
        return uint16(bet >> 172);
    }

    /// @dev Per-spin stake in wei.
    function stake(uint256 bet) internal pure returns (uint128) {
        uint256 unit = currency(bet) == 0 ? 1 gwei : 1 ether;
        return uint128(((bet >> 188) & type(uint64).max) * unit);
    }

    /// @dev Spin `i` of a DegeneretteResolved `spins` payload.
    function spinAt(bytes memory spins, uint256 i)
        internal
        pure
        returns (uint32 playerTraits, uint8 score, uint8 gold)
    {
        uint256 o = i * 5;
        playerTraits = (uint32(uint8(spins[o])) << 24) | (uint32(uint8(spins[o + 1])) << 16)
            | (uint32(uint8(spins[o + 2])) << 8) | uint32(uint8(spins[o + 3]));
        uint8 tail = uint8(spins[o + 4]);
        score = tail & 0x0F;
        gold = tail >> 4;
    }
}
