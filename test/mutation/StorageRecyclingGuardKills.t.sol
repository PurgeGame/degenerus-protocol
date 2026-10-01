// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;
import {StorageRecyclingSymbolicTest} from "../halmos/StorageRecycling.t.sol";
contract StorageRecyclingGuardKillsTest is StorageRecyclingSymbolicTest {
    function test_StaleRunHeaderTail() public {
        check_stale_run_initializes_header_tail(type(uint256).max, 23, 5);
        check_stale_run_initializes_header_tail(type(uint256).max, 0, 8);
    }
    function test_StaleLanesHeaderTail() public {
        check_stale_lanes_initialize_header_tail(type(uint256).max, 0x8877665544332211, 2);
        check_stale_lanes_initialize_header_tail(type(uint256).max, type(uint256).max, 8);
    }
    function test_PartialAppendAndExactCompletion() public {
        check_append_preserves_tail_and_completes_word(3, 1, 77, 23);
        check_append_preserves_tail_and_completes_word(3, 7, type(uint224).max, 0x12345678);
        check_append_preserves_tail_and_completes_word(3, type(uint32).max - 1, type(uint224).max, 0);
    }
    function test_HeaderCountTailRoundtrip() public { check_header_count_tail_roundtrip(3, 7, type(uint224).max); }
    function test_BitmapResetAndParity() public { check_bitmap_reset_preserves_other_parity(type(uint256).max, 9, 3); }
    function test_SameLevelBitmap() public { check_same_level_preserves_bitmap(22, 33, 3); }
    function test_FutureLevelEquality() public { check_full_level_equality(3, 7); }
    function test_BitmapReadGate() public { check_unset_bitmap_hides_header(3, 9); }
    function test_StampNeighbors() public { check_stamp_half_and_neighbors_are_isolated(type(uint256).max, 3); }
    function test_PriceOriginalSlots() public {
        check_live_tail_word_price(0, type(uint224).max, 23);
        check_live_tail_word_price(type(uint256).max, type(uint224).max, 23);
        check_stale_run_prices_original_slots(type(uint256).max, 23, 5);
        check_stale_run_prices_original_slots(0, 23, 8);
        check_stale_lanes_prices_original_slots(type(uint256).max, 23, 8);
        check_stale_lanes_prices_original_slots(0, 23, 8);
    }
    function test_BinaryTags() public {
        check_binary_tag_validation(0); check_binary_tag_validation(1);
        check_binary_tag_validation(2); check_binary_tag_validation(type(uint48).max);
    }
}
