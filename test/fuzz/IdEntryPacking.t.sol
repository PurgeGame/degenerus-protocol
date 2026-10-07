// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract IdEntryPackingHarness is DegenerusGameStorage {
    function bet(uint48 buffer, uint256 p, uint256 word) external { _storeDegeneretteBet(buffer, p, word); }
    function bet(uint48 buffer, uint256 p) external view returns (uint256) { return _loadDegeneretteBet(buffer, p); }
    function entry(uint24 lvl, uint64 id, uint256 word) external { _storeDecEntry(lvl, id, word); }
    function entry(uint24 lvl, uint64 id) external view returns (uint256) { return _loadDecEntry(lvl, id); }
}

contract IdEntryPackingTest is Test {
    IdEntryPackingHarness private h;
    function setUp() public { h = new IdEntryPackingHarness(); }

    function testFuzz_PairsRoundTripAndUpdatesPreserveSibling(uint32 id, uint96 fields, uint64 p) public {
        p = uint64(bound(p, 0, type(uint32).max));
        uint256 bet = uint256(id) | (uint256(fields & ((uint96(1) << 92) - 1)) << 32);
        uint256 sibling = uint256(19) | (uint256(23) << 60);
        h.bet(0, p ^ 1, sibling);
        h.bet(1, p, sibling);
        h.bet(0, p, bet);
        assertEq(h.bet(0, p), bet);
        assertEq(h.bet(0, p ^ 1), sibling);
        assertEq(h.bet(1, p), sibling);
        h.bet(0, p, 0);
        assertEq(h.bet(0, p ^ 1), sibling);

        uint256 entry = uint256(id) | (uint256(fields) << 32);
        h.entry(7, (p ^ 1) + 1, sibling);
        h.entry(8, p + 1, sibling);
        h.entry(7, p + 1, entry);
        assertEq(h.entry(7, p + 1), entry);
        assertEq(h.entry(7, (p ^ 1) + 1), sibling);
        assertEq(h.entry(8, p + 1), sibling);
        assertEq(h.entry(7, 0), 0, "zero id cannot alias the first pair");
    }
}
