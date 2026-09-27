// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Isolated jackpot battle fixtures retain the real reader's SLOAD and call cost.
contract CrapsPreferenceStore {
    event DrawAwardRequested(bytes32 key, address winner, uint256 peakFlip, uint256 score);

    function rewardJackpotBattle(bytes32 key, address winner, uint256 peakFlip, uint256 score) external {
        emit DrawAwardRequested(key, winner, peakFlip, score);
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        assembly ("memory-safe") {
            let out := mload(0x40)
            mstore(out, 32)
            mstore(add(out, 32), slots.length)
            let size := shl(5, slots.length)
            for { let i := 0 } lt(i, size) { i := add(i, 32) } {
                mstore(add(add(out, 64), i), sload(calldataload(add(slots.offset, i))))
            }
            return(out, add(64, size))
        }
    }
}
