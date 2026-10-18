// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";

/// @dev Exposes the production box-queue append/read and order decode unchanged.
contract CompactQueueHarness is DegenerusGameStorage {
    function setWriteState(uint32 count, uint48 buffer) external {
        lootboxRngPacked = uint256(count) << LR_BOX_COUNT_SHIFT;
        rngFlagsAndNudges = uint16(buffer & 1) << 12;
    }

    function seedWord(uint48 buffer, uint256 wordIndex, uint256 word) external {
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            sstore(add(keccak256(0x00, 0x20), wordIndex), word)
        }
    }

    function rawWord(uint48 buffer, uint256 wordIndex) external view returns (uint256 word) {
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            word := sload(add(keccak256(0x00, 0x20), wordIndex))
        }
    }

    function append(uint256 entry) external returns (uint48 buffer, uint32 position) {
        return _appendBoxEntry(entry, 0);
    }

    function entryAt(uint48 buffer, uint256 position) external view returns (uint256) {
        return _boxEntryAt(buffer, position);
    }

    function writeCount() external view returns (uint256) {
        return uint32(lootboxRngPacked >> LR_BOX_COUNT_SHIFT);
    }

    function decode(uint256 boxOrder, uint24 lvl) external pure returns (uint256 fields, uint256 cost) {
        return _decodeBoxOrder(boxOrder, lvl);
    }
}

/// @dev Exposes the production 12-bit score code unchanged.
contract ScoreCodeHarness is DegenerusGameLootboxModule {
    function code(uint256 score) external pure returns (uint256) {
        return _scoreCode(score);
    }

    function decodeScore(uint256 c) external pure returns (uint256) {
        return _scoreFromCode(c);
    }
}

/// @title DegenesisCompactArithmeticTest -- symbolic proofs for the compact order encodings
/// @notice Real code (called through harnesses that inherit it unchanged):
///         - box queue: `_appendBoxEntry` / `_boxEntryAt` (85-bit lanes, three per word);
///         - purchase input: `_decodeBoxOrder` (0.001-ETH units, quantity, per-box cap, cost);
///         - score code: `_scoreCode` / `_scoreFromCode` (12-bit piecewise code, bounds,
///           monotonicity, error).
///         Mirrors (the code is inline in a function body, so no harness can reach it; these prove
///         the arithmetic as written in the module, not the bytecode):
///         - the Degenesis order lane and day header written inline in `buyDegenesisBox`.
///         Not proved (each attempt timed out at the 120 s assertion budget on 256-bit multiply or
///         divide, so none is kept here): the Degenesis FLIP scale, schedule and volume factor
///         (private `_degenesisOutcome`, mirror only), the 0.0001-ETH grid, the quarter split, the
///         decode's cost product and `_loanOwedAt` (real code, even at a fixed principal). The
///         stateful suite checks the contract's FLIP per order against the spec reference, and
///         TerminalLoanConservation checks the settled price against an independent formula.
/// @custom:halmos --storage-layout generic
contract DegenesisCompactArithmeticTest is Test {
    CompactQueueHarness internal h;
    ScoreCodeHarness internal s;

    uint256 internal constant ENTRY_MASK = (uint256(1) << 85) - 1;
    uint256 internal constant UNITS_MAX = 2_000_000;

    function setUp() public {
        h = new CompactQueueHarness();
        s = new ScoreCodeHarness();
    }

    // =====================================================================
    // Box queue: three 85-bit lanes per word (real code)
    // =====================================================================

    /// @notice A fresh word (any stale content) takes three appends: each lane reads back exactly,
    ///         the word is exactly the three lanes, bit 255 stays zero, and the count advances.
    function check_boxQueue_threeLanesRoundTrip(uint32 group, uint48 buffer, uint256 stale, uint256 e0, uint256 e1, uint256 e2)
        public
    {
        vm.assume(group < (uint32(1) << 30));
        e0 &= ENTRY_MASK;
        e1 &= ENTRY_MASK;
        e2 &= ENTRY_MASK;
        buffer &= 1;
        uint32 base = group * 3;
        h.setWriteState(base, buffer);
        h.seedWord(buffer, group, stale);
        (uint48 b0, uint32 p0) = h.append(e0);
        (, uint32 p1) = h.append(e1);
        (, uint32 p2) = h.append(e2);
        assertEq(b0, buffer);
        assertEq(p0, base);
        assertEq(p1, base + 1);
        assertEq(p2, base + 2);
        assertEq(h.entryAt(buffer, base), e0);
        assertEq(h.entryAt(buffer, base + 1), e1);
        assertEq(h.entryAt(buffer, base + 2), e2);
        uint256 raw = h.rawWord(buffer, group);
        assertEq(raw, e0 | (e1 << 85) | (e2 << 170));
        assertEq(raw >> 255, 0);
        assertEq(h.writeCount(), uint256(base) + 3);
    }

    /// @notice A mid-word append ORs into its own lane only: the earlier lanes of the word and
    ///         the neighbouring words are unchanged.
    function check_boxQueue_laneIsolation(uint32 group, uint256 lane0, uint256 e, uint256 prevWord, uint256 nextWord)
        public
    {
        vm.assume(group > 0 && group < (uint32(1) << 30));
        lane0 &= ENTRY_MASK;
        e &= ENTRY_MASK;
        h.setWriteState(group * 3 + 1, 0);
        h.seedWord(0, group - 1, prevWord);
        h.seedWord(0, group, lane0);
        h.seedWord(0, group + 1, nextWord);
        h.append(e);
        assertEq(h.entryAt(0, group * 3), lane0);
        assertEq(h.entryAt(0, group * 3 + 1), e);
        assertEq(h.rawWord(0, group), lane0 | (e << 85));
        assertEq(h.rawWord(0, group - 1), prevWord);
        assertEq(h.rawWord(0, group + 1), nextWord);
    }

    /// @notice Every lane of any word reads back as its own 85 bits.
    function check_boxQueue_readerExtractsLane(uint32 group, uint256 word, uint8 lane) public {
        vm.assume(lane < 3 && group < (uint32(1) << 30));
        h.seedWord(1, group, word);
        assertEq(h.entryAt(1, uint256(group) * 3 + lane), (word >> (uint256(lane) * 85)) & ENTRY_MASK);
    }

    // =====================================================================
    // Purchase input decode: units, quantity, cost (real code)
    // =====================================================================

    /// @notice Any bit at or above 30 rejects the order: it lands in the units field, which a
    ///         preset requires to be zero and a custom caps at 2,000,000.
    function check_decode_rejectsHighBits(uint256 low, uint256 high, uint24 lvl) public view {
        low &= (uint256(1) << 30) - 1;
        vm.assume(high != 0 && high < (uint256(1) << 226));
        try h.decode(low | (high << 30), lvl) returns (uint256, uint256) {
            assert(false);
        } catch {}
    }

    /// @notice A custom order is accepted exactly for 1..100 boxes of 10..2,000,000 units, and its
    ///         fields hold exactly the units and quantity in their lanes and nothing else.
    function check_decode_custom(uint8 qty, uint32 units, uint24 lvl) public view {
        uint256 q = qty & 0x7F;
        uint256 u = units & 0x1FFFFF;
        bool ok = q >= 1 && q <= 100 && u >= 10 && u <= UNITS_MAX;
        try h.decode(q | (uint256(3) << 7) | (u << 9), lvl) returns (uint256 fields, uint256) {
            assert(ok);
            assert(fields == (u << 32) | (q << 77));
        } catch {
            assert(!ok);
        }
    }

    /// @notice A preset (small, medium, large) is accepted exactly for 1..100 boxes with a zero
    ///         units field, and stores 1..6,000 units (at most 25 x the 0.24 ETH top price) and its
    ///         quantity in their lanes and nothing else.
    function check_decode_preset(uint8 qty, uint8 kind, uint24 lvl) public view {
        vm.assume(kind < 3);
        uint256 q = qty & 0x7F;
        try h.decode(q | (uint256(kind) << 7), lvl) returns (uint256 fields, uint256) {
            assert(q >= 1 && q <= 100);
            uint256 u = (fields >> 32) & 0x1FFFFF;
            assert(u >= 10 && u <= 6000);
            assert(fields == (u << 32) | (q << 77));
        } catch {
            assert(q == 0 || q > 100);
        }
    }

    // =====================================================================
    // 12-bit score code (real code)
    // =====================================================================

    function check_scoreCode_fitsTwelveBits(uint256 score) public view {
        assertLe(s.code(score), 4039);
    }

    function check_scoreCode_monotone(uint256 a, uint256 b) public view {
        vm.assume(a <= b);
        assertLe(s.code(a), s.code(b));
    }

    /// @notice Decoding never overstates the clamped score, understates it by at most 13 points,
    ///         is exact through 2,042 and at the 30,000 cap.
    function check_scoreCode_decodeError(uint256 score) public view {
        uint256 clamped = score > 30_000 ? 30_000 : score;
        uint256 back = s.decodeScore(s.code(score));
        assertLe(back, clamped);
        assertLe(clamped - back, 13);
        if (clamped <= 2042 || clamped == 30_000) assertEq(back, clamped);
    }

    function check_scoreCode_decodeMonotone(uint256 a, uint256 b) public view {
        vm.assume(a <= b && b <= 4039);
        assertLe(s.decodeScore(a), s.decodeScore(b));
        assertEq(s.code(s.decodeScore(b)), b);
    }

    // =====================================================================
    // Degenesis order lane and day header (mirror of buyDegenesisBox)
    // =====================================================================

    uint256 internal constant DEG_AMOUNT_MASK = (uint256(1) << 38) - 1;
    uint256 internal constant DEG_LANE_MASK = (uint256(1) << 85) - 1;

    function _degLane(uint32 id, uint256 units, uint256 secs) internal pure returns (uint256) {
        return uint256(id) | (units << 32) | (secs << 70);
    }

    /// @notice Three orders written as the buy writes them (lane 0 overwrites the word, lanes 1-2
    ///         OR in) read back field for field as settlement reads them; bit 255 stays zero.
    function check_degenesisLanes_roundTripAndIsolation(uint32[3] memory ids, uint64[3] memory units, uint16[3] memory secs)
        public
        pure
    {
        uint256 word;
        uint256[3] memory u;
        uint256[3] memory sec;
        for (uint256 p; p < 3; ++p) {
            u[p] = uint256(units[p]) & DEG_AMOUNT_MASK;
            sec[p] = secs[p] > 6 hours ? 6 hours : secs[p];
            uint256 l = _degLane(ids[p], u[p], sec[p]);
            word = p == 0 ? l : word | (l << (p * 85));
        }
        assert(word >> 255 == 0);
        for (uint256 p; p < 3; ++p) {
            uint256 l = (word >> (p * 85)) & DEG_LANE_MASK;
            assert(uint32(l) == ids[p]);
            assert(((l >> 32) & DEG_AMOUNT_MASK) == u[p]);
            assert((l >> 70) == sec[p]);
        }
    }

    /// @notice The header add (volume + units, count + 1) never carries between fields while the
    ///         day's volume stays below 2^48 units (about 28 billion ETH).
    function check_degenesisHeader_noCarry(uint48 volume, uint32 count, uint256 units) public pure {
        units &= DEG_AMOUNT_MASK;
        vm.assume(uint256(volume) + units < (uint256(1) << 48) && count < type(uint32).max);
        uint256 hdr = uint256(volume) | (uint256(count) << 48);
        uint256 next = hdr + units + (uint256(1) << 48);
        assert(uint48(next) == uint256(volume) + units);
        assert(uint32(next >> 48) == uint256(count) + 1);
        assert(next >> 80 == 0);
    }
}
