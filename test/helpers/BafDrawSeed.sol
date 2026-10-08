// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

interface IBafDrawEntryReader {
    function bafDrawEntryAt(uint24 day, uint32 index) external view returns (uint32 id, uint96 cumulativeWeight);
}

/// @dev Test-only packed draw-book writer; production getters authenticate every seeded lane.
library BafDrawSeed {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function entry(address coinflip, uint24 day, uint32 index, uint32 id, uint96 cumulative) internal {
        require(id != 0 && cumulative != 0, "draw seed requires a nonempty interval");
        bytes32 slot = keccak256(abi.encode((uint256(day) << 32) | (index >> 1), uint256(8)));
        uint256 shift = (index & 1) * 128;
        uint256 previous = uint256(VM.load(coinflip, slot));
        uint256 packed = (uint256(id) << 96) | cumulative;
        VM.store(coinflip, slot, bytes32((previous & ~(uint256(type(uint128).max) << shift)) | (packed << shift)));
        (uint32 actualId, uint96 actualCumulative) = IBafDrawEntryReader(coinflip).bafDrawEntryAt(day, index);
        require(actualId == id && actualCumulative == cumulative, "draw seed layout drift");
    }
}
