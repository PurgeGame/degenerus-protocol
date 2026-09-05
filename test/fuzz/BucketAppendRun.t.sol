// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract BucketRunHarness is DegenerusGameStorage {
    function append(uint32 owner, uint256 n) external returns (uint256 f, uint256 d) {
        uint256 slot;
        assembly ("memory-safe") {
            mstore(0, 11)
            mstore(32, lvlTraitEntry.slot)
            slot := keccak256(0, 64)
        }
        return _bucketAppendRun(slot, 7, owner, n);
    }

    function length() external view returns (uint256) {
        return lvlTraitEntry[11][7].length;
    }

    function word(uint256 i) external view returns (uint256 value) {
        uint256[] storage bucket = lvlTraitEntry[11][7];
        assembly ("memory-safe") {
            mstore(0, bucket.slot)
            value := sload(add(keccak256(0, 32), i))
        }
    }
}

/// @notice Compare packed runs and write-budget charges with a logical sequence of owners.
/// @dev Includes zero owners, maximum uint32 owners, empty runs and every tail alignment.
contract BucketAppendRunTest is Test {
    function _check(uint32 a, uint32 b, uint32 c, uint256 n, uint256 m, uint256 k) internal {
        BucketRunHarness h = new BucketRunHarness();
        uint256[3] memory sizes = [n, m, k];
        uint32[3] memory owners = [a, b, c];
        uint256 len;
        for (uint256 i; i < 3; ++i) {
            (uint256 fresh, uint256 dirty) = h.append(owners[i], sizes[i]);
            uint256 tail = len % 8;
            uint256 tailTake = tail == 0 ? 0 : (sizes[i] < 8 - tail ? sizes[i] : 8 - tail);
            assertEq(fresh, (len == 0 ? 1 : 0) + (sizes[i] - tailTake + 7) / 8, "fresh units");
            assertEq(dirty, (len == 0 ? 0 : 1) + (tail == 0 ? 0 : 1), "dirty units");
            len += sizes[i];
            assertEq(h.length(), len);
        }
        for (uint256 w; w <= len / 8; ++w) {
            uint256 expected;
            for (uint256 j; j < 8; ++j) {
                uint256 pos = w * 8 + j;
                if (pos < len) {
                    uint32 owner = pos < n ? a : (pos < n + m ? b : c);
                    expected |= uint256(owner) << (32 * j);
                }
            }
            assertEq(h.word(w), expected, "packed ownership / unused lanes");
        }
    }

    function testFuzz_AppendMatchesLogicalEntries(uint32 a, uint32 b, uint32 c, uint8 n, uint8 m, uint8 k) public {
        _check(a, b, c, n, m, k);
    }

    function test_AllTailBoundaries() public {
        for (uint256 n; n < 8; ++n) {
            for (uint256 m; m <= 17; ++m) {
                _check(0, type(uint32).max, 0xabcdef01, n, m, 9);
            }
        }
    }
}
