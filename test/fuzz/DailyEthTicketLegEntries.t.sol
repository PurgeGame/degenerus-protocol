// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

/// @title DailyEthTicketLegEntries -- the purchase-phase daily jackpot's ticket leg delivers its figure
/// @notice The daily ETH phase carves one percent of the future pool into a day slice; 75% of the
///         slice is the ticket leg, and `_distributePoolBackedTickets` converts HALF of that leg
///         into entries at the level's price, four per whole ticket, spread over at most 120
///         winners with equal entry counts. Mutation v78 found no foundry assertion of that count
///         (a `budget / bps` mutant collapsed the leg to zero entries and survived); this pins the
///         delivered total against the arithmetic, winner by winner.
contract DailyEthTicketLegEntries is Test {
    GoldenTicketHarness internal h;

    uint24 internal constant LVL = 5;
    uint128 internal constant FUT_POOL = 4000 ether;
    uint16 internal constant MAX_WINNERS = 120; // PURCHASE_PHASE_TICKET_MAX_WINNERS
    uint256 internal constant TICKET_LEG_BPS = 7500; // PURCHASE_REWARD_JACKPOT_TICKET_BPS
    uint256 internal constant CONVERSION_BPS = 5000; // the pool-backed leg's 50% conversion

    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed entryLevel,
        uint16 indexed traitId,
        uint32 entryCount,
        uint24 sourceLevel,
        uint256 entryIndex,
        bool roundedUp
    );

    function setUp() public {
        h = new GoldenTicketHarness();
        vm.etch(ContractAddresses.COINFLIP, address(new CoinflipRecorder()).code);
        vm.etch(ContractAddresses.WWXRP, address(new WwxrpRecorder()).code);
        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);
        h.setLevel(LVL);
        h.setJackpotCounter(1); // an ordinary purchase day: no early-bird, not final
        h.setDailyIdx(10);
        h.setCurrentPool(1000 ether);
        h.setPools(200 ether, FUT_POOL);
    }

    /// @dev A mixed-colour board (no golden quadrant) with its four trait buckets seeded deep
    ///      enough that every winner slot finds a distinct holder.
    function _board() internal returns (uint256 word) {
        uint8[4] memory colors = [1, 2, 3, 4];
        uint8[4] memory syms = [1, 2, 3, 4];
        for (uint256 i; i < 4; ++i) {
            word |= (uint256(colors[i]) << 3 | uint256(syms[i])) << (i * 6);
        }
        word |= uint256(0xB0A7D) << 24;
        for (uint8 i; i < 4; ++i) {
            uint8 trait = uint8(uint256(i) * 64 + ((word >> (uint256(i) * 6)) & 0x3F));
            h.seedBucket(LVL, trait, 80, uint160(0x2000) + uint160(i) * 1000);
        }
    }

    function test_ticketLegDeliversItsEntries() public {
        uint256 word = _board();
        vm.recordLogs();
        h.payDailyJackpot(false, LVL, word);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The arithmetic the leg is meant to deliver.
        uint256 slice = uint256(FUT_POOL) / 100;
        uint256 leg = (slice * TICKET_LEG_BPS) / 10_000;
        uint256 basis = (leg * CONVERSION_BPS) / 10_000;
        uint256 entries = (basis << 2) / PriceLookupLib.priceForLevel(LVL);
        uint256 tickets = entries / 4;
        assertGe(tickets, MAX_WINNERS, "fixture: enough tickets to fill every winner slot");
        uint256 each = (tickets / MAX_WINNERS) * 4;

        bytes32 sig = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
        uint256 winners;
        uint256 delivered;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != sig || logs[i].emitter != address(h)) continue;
            (uint32 count, uint24 sourceLevel,,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
            assertEq(uint256(logs[i].topics[2]), LVL, "entries are queued at the purchase level");
            assertEq(sourceLevel, LVL, "and sourced from it");
            assertEq(count, each, "every winner takes the same whole-ticket share");
            winners++;
            delivered += count;
        }
        assertEq(winners, MAX_WINNERS, "the leg fills every winner slot");
        assertEq(delivered, each * MAX_WINNERS, "the delivered total is the winners' shares");
        assertLe(delivered, entries, "never more than the leg converts");
        assertGt(delivered, entries - 4 * MAX_WINNERS, "and within one sub-ticket per winner of it");
    }
}
