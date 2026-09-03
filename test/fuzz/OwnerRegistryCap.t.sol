// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";

/// @dev Exposes the three queue sinks over the production storage so the per-level owner
///      registry can be filled to its 32-bit lane ceiling by a raw length write.
contract RegistryCapHarness is DegenerusGameMintModule {
    function fill(uint24 lvl, uint256 len) external {
        address[] storage owners = lvlEntryOwner[lvl];
        assembly ("memory-safe") {
            sstore(owners.slot, len)
        }
    }
    function ownerCount(uint24 lvl) external view returns (uint256) { return lvlEntryOwner[lvl].length; }
    function queueLen(uint24 lvl) external view returns (uint256) { return ticketQueue[_tqWriteKey(lvl)].length; }
    function owedOf(uint24 lvl, address p) external view returns (uint80) { return entriesOwedPacked[_tqWriteKey(lvl)][p]; }
    function entries(address p, uint24 lvl, uint32 n, bool crank) external { _queueEntries(p, lvl, n, crank); }
    function scaled(address p, uint24 lvl, uint32 n, bool crank) external { _queueEntriesScaled(p, lvl, n, crank); }
    function range(address p, uint24 lvl, uint24 num, uint32 n, bool crank) external { _queueEntryRange(p, lvl, num, n, crank); }
}

/// @title OwnerRegistryCap — a full per-level owner registry never reaches the drain.
/// @notice Positions are stored plus one in 32-bit lanes, so a level holds at most 2^32 - 1
///         owners. At the ceiling a paid sink reverts (the buyer keeps their payment) and an
///         advance-chain sink drops the award for that level and continues; no owed word is
///         ever written without a position, so the drain's position decode cannot underflow.
contract OwnerRegistryCap is Test {
    RegistryCapHarness internal h;
    uint256 internal constant FULL = uint256(type(uint32).max) - 1;
    uint24 internal constant LVL = 3;

    function setUp() public {
        h = new RegistryCapHarness();
        h.fill(LVL, FULL);
    }

    function test_LastPositionStillRegisters() public {
        h.fill(LVL, FULL - 1);
        h.entries(address(0xA1), LVL, 4, false);
        assertEq(h.ownerCount(LVL), FULL, "the last lane position is taken");
        assertEq(uint256(h.owedOf(LVL, address(0xA1)) >> 48), FULL, "position + 1 fills the lane exactly");
    }

    function test_PaidSinksRevertAtTheCeiling() public {
        vm.expectRevert(bytes4(keccak256("E()")));
        h.entries(address(0xA1), LVL, 4, false);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.scaled(address(0xA1), LVL, 400, false);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.range(address(0xA1), LVL, 1, 4, false);
        assertEq(h.ownerCount(LVL), FULL, "nothing registered");
        assertEq(h.queueLen(LVL), 0, "nothing queued");
    }

    function test_CrankSinksDropTheLevelAndContinue() public {
        h.entries(address(0xA1), LVL, 4, true);
        h.scaled(address(0xA1), LVL, 400, true);
        assertEq(h.ownerCount(LVL), FULL, "award dropped: no position taken");
        assertEq(h.queueLen(LVL), 0, "award dropped: nothing queued");
        assertEq(h.owedOf(LVL, address(0xA1)), 0, "award dropped: no owed word");
        // A range spanning the full level skips it and still queues the others.
        h.range(address(0xA1), LVL - 1, 3, 4, true);
        assertEq(h.queueLen(LVL - 1), 1);
        assertEq(h.queueLen(LVL), 0);
        assertEq(h.queueLen(LVL + 1), 1);
        assertEq(h.ownerCount(LVL - 1), 1);
        assertEq(h.ownerCount(LVL + 1), 1);
    }

    function test_ExistingOwnerStillAccumulatesAtTheCeiling() public {
        h.fill(LVL, FULL - 1);
        h.entries(address(0xA1), LVL, 4, false);
        h.entries(address(0xA1), LVL, 4, false); // registry now full, but the word already has a position
        assertEq(uint256(uint32(h.owedOf(LVL, address(0xA1)) >> 8)), 8, "a registered owner keeps queuing");
    }
}
