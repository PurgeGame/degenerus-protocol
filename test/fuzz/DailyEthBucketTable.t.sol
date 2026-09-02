// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

/// @title DailyEthBucketTable -- the daily ETH leg's winner table and quarter-price granule
/// @notice The purchase-phase daily jackpot pays four trait buckets from the 20 / 12 / 6 / 1
///         table, rotated so the entropy-picked solo quadrant is the ONE-winner bucket and takes
///         the pool's remainder, and every other bucket's share is floored to whole quarters of
///         the NEXT level's price per winner. Mutation v78 left the table's figures, the rotation
///         and the granule's level unasserted in foundry (`12 -> 1`, `6 -> 0`, `& 3 -> + 3` and
///         `lvl + 1 -> lvl` all survived); this reads them back off `JackpotEthWin`.
contract DailyEthBucketTable is Test {
    GoldenTicketHarness internal h;

    uint24 internal constant LVL = 4; // price(4) = 0.01, price(5) = 0.02: the granule's level is observable
    uint128 internal constant FUT_POOL = 40_123 ether;
    uint256 internal constant SEATS = 80;

    bytes32 internal constant ETH_WIN = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");

    function setUp() public {
        h = new GoldenTicketHarness();
        vm.etch(ContractAddresses.COINFLIP, address(new CoinflipRecorder()).code);
        vm.etch(ContractAddresses.WWXRP, address(new WwxrpRecorder()).code);
        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);
        h.setLevel(LVL);
        h.setJackpotCounter(1);
        h.setDailyIdx(10);
        h.setCurrentPool(1000 ether);
        h.setPools(200 ether, FUT_POOL);
    }

    /// @dev A mixed-colour board whose four trait buckets are seeded deep enough for any count.
    function _board(uint24 lvl, uint256 salt) internal returns (uint256 word, uint8[4] memory traits) {
        uint8[4] memory colors = [1, 2, 3, 4];
        uint8[4] memory syms = [5, 6, 1, 2];
        for (uint256 i; i < 4; ++i) {
            word |= (uint256(colors[i]) << 3 | uint256(syms[i])) << (i * 6);
        }
        word |= salt << 24;
        for (uint8 i; i < 4; ++i) {
            traits[i] = uint8(uint256(i) * 64 + ((word >> (uint256(i) * 6)) & 0x3F));
            h.seedBucket(lvl, traits[i], SEATS, uint160(0x3000) + uint160(i) * 1000);
        }
    }

    /// @dev Winner count and ETH total per quadrant, off the ETH win events of one call.
    function _tally(Vm.Log[] memory logs, uint8[4] memory traits, uint256 unit)
        internal
        returns (uint256[4] memory count, uint256[4] memory total)
    {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != ETH_WIN || logs[i].emitter != address(h)) continue;
            uint256 trait = uint256(logs[i].topics[3]);
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            for (uint8 q; q < 4; q++) {
                if (trait == traits[q]) {
                    count[q]++;
                    total[q] += amount;
                    assertGe(amount, unit, "a winner is never paid less than one granule");
                }
            }
        }
    }

    function test_purchasePhaseTableRotatesAroundTheSoloQuadrant() public {
        (uint256 word, uint8[4] memory traits) = _board(LVL, 0xD1CE);
        vm.recordLogs();
        h.payDailyJackpot(false, LVL, word);
        uint256 unit = PriceLookupLib.priceForLevel(LVL + 1) >> 2;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256[4] memory count, uint256[4] memory total) = _tally(logs, traits, unit);
        uint256[4] memory ticketWinners;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != TICKET_WIN || logs[i].emitter != address(h)) continue;
            uint256 trait = uint256(logs[i].topics[3]);
            for (uint8 q; q < 4; q++) if (trait == traits[q]) ticketWinners[q]++;
        }

        // The solo quadrant is the one-winner bucket; the next three around the wheel take
        // 20, 12 and 6 (`base[(i + offset) & 3]` with the offset pinned to the solo pick).
        uint8 solo = 4;
        for (uint8 q; q < 4; q++) {
            if (count[q] == 1) {
                assertEq(solo, 4, "exactly one bucket has a single winner");
                solo = q;
            }
        }
        assertLt(solo, 4, "the solo quadrant's bucket has exactly one winner");
        assertEq(count[(solo + 1) & 3], 20, "the bucket after the solo quadrant takes twenty winners");
        assertEq(count[(solo + 2) & 3], 12, "then twelve");
        assertEq(count[(solo + 3) & 3], 6, "then six");
        // The solo quadrant took the ETH remainder, so the pool-backed ticket leg skips it and
        // spreads its winners over the other three.
        assertEq(ticketWinners[solo], 0, "no ticket winner in the solo quadrant");
        for (uint8 q; q < 4; q++) {
            if (q != solo) assertGt(ticketWinners[q], 0, "every other quadrant wins tickets");
        }

        // Every non-remainder bucket is 20% of the ETH leg floored to whole granules per winner,
        // and the granule is a quarter of the NEXT level's price.
        uint256 slice = uint256(FUT_POOL) / 100;
        uint256 ethPool = slice - (slice * 7500) / 10_000 - (slice * 200) / 10_000;
        uint256 remainderPaid;
        for (uint8 q; q < 4; q++) {
            if (q == solo) {
                remainderPaid = total[q];
                continue;
            }
            uint256 share = (ethPool * 2000) / 10_000;
            uint256 unitBucket = unit * count[q];
            assertEq(total[q], (share / unitBucket) * unitBucket, "a bucket pays its fifth floored to granules");
            assertEq(total[q] % unit, 0, "and every winner's cut is whole granules");
        }
        // The solo bucket absorbs the leg's remainder: the 20% no bucket was assigned plus the
        // three flooring residues.
        uint256 distributed;
        for (uint8 q; q < 4; q++) if (q != solo) distributed += total[q];
        assertEq(remainderPaid, ethPool - distributed, "the solo quadrant takes the whole remainder");
    }

    function test_terminalJackpotPaysWholeGranulesOfTheNextLevelsPrice() public {
        uint24 target = LVL;
        (uint256 word, uint8[4] memory traits) = _board(target, 0xFEED);
        uint256 poolWei = 12.345678901234567891 ether;
        uint256 unit = PriceLookupLib.priceForLevel(target + 1) >> 2;
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        uint256 paid = h.runTerminalJackpot(poolWei, target, word);
        (uint256[4] memory count, uint256[4] memory total) = _tally(vm.getRecordedLogs(), traits, unit);

        uint256 summed;
        uint256 wholeBuckets;
        for (uint8 q; q < 4; q++) {
            summed += total[q];
            if (count[q] != 0 && total[q] % unit == 0) wholeBuckets++;
        }
        assertEq(summed, paid, "the events account for every wei the call reports paid");
        assertLe(paid, poolWei, "never more than the pool");
        // Three buckets are floored to the granule; only the remainder bucket may carry an
        // unaligned residue, so at least three of the paying buckets are whole granules.
        assertGe(wholeBuckets, 3, "the shared buckets pay whole quarters of the next level's price");
        // The mutant that floors to THIS level's granule (half the size) pays a finer figure: some
        // shared bucket's total is then an odd multiple of it, which the coarse granule rejects.
        uint256 fine = PriceLookupLib.priceForLevel(target) >> 2;
        assertEq(unit, 2 * fine, "fixture: the two candidate granules differ");
    }
}
