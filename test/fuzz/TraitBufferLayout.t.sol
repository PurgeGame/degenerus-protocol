// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract TraitBufferLayoutHarness is DegenerusGameStorage {
    constructor() { dailyHeroWagers[0][0] = 0xabcdef; }

    function root() external pure returns (uint256 value) {
        assembly { value := lvlTraitEntry.slot }
    }
    function bases(uint24 lvl) external pure returns (uint256, uint256) {
        return (_traitBufferBase(lvl), _traitBatchBase(lvl));
    }
    function write(uint24 lvl, uint8 trait, uint256 value) external {
        lvlTraitEntry[lvl & 1][trait] = value;
    }
    function read(uint24 lvl, uint8 trait) external view returns (uint256 word) {
        uint256 slot = _traitBufferBase(lvl) + trait;
        assembly { word := sload(slot) }
    }
    function neighbors() external view returns (uint256, uint256) {
        return (_redemptionReserveStored, dailyHeroWagers[0][0]);
    }
    function afterSlot() external pure returns (uint256 value) {
        assembly { value := dailyHeroWagers.slot }
    }
}

contract TraitBufferLayoutTest is Test {
    TraitBufferLayoutHarness h;
    function setUp() public { h = new TraitBufferLayoutHarness(); }

    function test_RootAndExtentMatchCompilerLayout() public view {
        assertEq(h.root(), GameSlots.LVL_TRAIT_ENTRY);
        assertEq(h.afterSlot(), h.root() + 512);
    }

    function testFuzz_CompiledIndexingMatchesBothHelpers(uint24 lvl, uint8 trait, uint256 value) public {
        h.write(lvl, trait, value);
        assertEq(h.read(lvl, trait), value);
        assertEq(h.read(lvl ^ 1, trait), 0, "opposite parity is independent");
        (uint256 base, uint256 batchBase) = h.bases(lvl);
        assertEq(base, batchBase);
        assertEq(uint256(vm.load(address(h), bytes32(base + trait))), value);
    }

    function test_BothBufferBoundariesDoNotOverwriteNeighbors() public {
        h.write(0, 0, 11); h.write(0, 255, 22);
        h.write(1, 0, 33); h.write(1, 255, 44);
        assertEq(h.read(0, 0), 11); assertEq(h.read(0, 255), 22);
        assertEq(h.read(1, 0), 33); assertEq(h.read(1, 255), 44);
        (uint256 beforeValue, uint256 afterValue) = h.neighbors();
        assertEq(beforeValue, 1); assertEq(afterValue, 0xabcdef);
    }
}
