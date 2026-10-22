// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CoinflipRingPrototype} from "../../scripts/audit/fixtures/CoinflipRingPrototype.sol";
import {CoinflipReuseReference} from "../../scripts/audit/fixtures/CoinflipReuseReference.sol";

contract CoinflipReusePrototypeTest is Test {
    CoinflipRingPrototype internal r;
    CoinflipReuseReference internal oracle;
    uint32 internal constant ID = 42;

    function setUp() public {
        r = new CoinflipRingPrototype();
        oracle = new CoinflipReuseReference();
    }

    function _credit(uint24 day, uint256 amount) private {
        assertEq(r.credit(ID, day, amount, false), oracle.credit(ID, day, amount, false));
        assertEq(r.stake(ID, day), oracle.stakes(ID, day));
    }

    function test_zeroDoesNotAllocateOrRetag() public {
        r.credit(ID, 7, 0, false);
        assertEq(r.ring(ID, 1), 0);
        _credit(7, 1);
        uint256 word = r.ring(ID, 1);
        r.credit(ID, 112, 0, false);
        assertEq(r.ring(ID, 1), word);
        assertEq(r.overflow(ID, 16), 0);
    }

    function test_spillSurvivesRecoveryAndSamePageMerge() public {
        _credit(7, 23);
        _credit(112, 41);
        r.setFrontier(112);
        r.claimThrough(ID, 112);
        _credit(113, 53);
        assertEq(uint24(r.ring(ID, 1) >> 224), 2);
        assertEq(r.stake(ID, 112), 41);
        assertEq(r.stake(ID, 113), 53);
    }

    function test_staleHintWrapCannotDuplicateOrSelectAnotherPage() public {
        _credit(7, 17);
        _credit(112, 23);
        // Same ring index AND same seven-bit fingerprint after 15 * 128 pages.
        uint24 later = uint24((16 + 15 * 128) * 7);
        _credit(later, 31);
        assertEq(r.stake(ID, 112), 23);
        assertEq(r.stake(ID, later), 31);
        r.setFrontier(later);
        _credit(later + 1, 43);
        assertEq(r.stake(ID, later), 31);
        assertEq(uint24(r.ring(ID, 1) >> 224), 2);
    }

    function test_allSevenExpiryAlignmentsAndTomorrow() public {
        for (uint24 alignment; alignment < 7; ++alignment) {
            CoinflipRingPrototype x = new CoinflipRingPrototype();
            uint24 oldDay = 7 + alignment;
            x.credit(ID, oldDay, 7, false);
            x.setFrontier(oldDay + 89);
            x.credit(ID, oldDay + 105, 11, false);
            assertEq(x.stake(ID, oldDay), 7, "old day still live");
            assertEq(x.stake(ID, oldDay + 105), 11);
            x.setFrontier(oldDay + 90);
            x.credit(ID, oldDay + 106, 13, false);
            assertEq(x.stake(ID, oldDay + 105), 11, "spill wins over now-dead ring");
        }
    }

    function test_maxAmountSaturatesAndManualReverts() public {
        _credit(type(uint24).max, type(uint256).max);
        _credit(type(uint24).max, type(uint256).max);
        vm.expectRevert(CoinflipRingPrototype.StakeAboveDailyCap.selector);
        r.credit(ID, type(uint24).max, 1, true);
        assertEq(r.stake(ID, type(uint24).max), type(uint32).max);
    }

    function testFuzz_historyMatchesAbsoluteLedger(uint256 seed) public {
        uint24 frontier;
        uint24 cursor;
        for (uint24 day = 1; day <= 420; ++day) {
            seed = uint256(keccak256(abi.encode(seed, day)));
            // Includes normal resolution, stalls, and a permanent freeze with continued credits.
            if (day < 260 && seed % 5 != 0) {
                frontier = day;
                r.setFrontier(frontier);
            }
            _credit(day + 1, seed & 0xffff);
            if (seed % 13 == 0) {
                uint24 start = frontier > 90 ? frontier - 90 : 0;
                if (cursor > start) start = cursor;
                for (uint24 d = start + 1; d <= frontier; ++d) {
                    assertEq(r.stake(ID, d), oracle.stakes(ID, d), "live ledger");
                }
                cursor = frontier;
                r.claimThrough(ID, cursor);
            }
        }
    }

    function test_referenceSeedsCarryExpiryAndRepeatedClaim() public {
        oracle.configure(1, 0, 0, 0, false, 0);
        oracle.resolve(1, 100);
        (uint256 paid, uint256 baf,) = oracle.settle(1, 0);
        assertEq(paid, 400_000);
        assertEq(baf, 400_000);
        (paid,,) = oracle.settle(1, 0);
        assertEq(paid, 0);
        oracle.configure(ID, 1, 0, 1000, true, 0);
        oracle.resolve(92, 100);
        (paid,,) = oracle.settle(ID, 0);
        (, uint256 carry,,, ) = oracle.positions(ID);
        assertEq(paid, 0);
        assertEq(carry, 0, "expired carry cannot ride a known result");
    }
}
