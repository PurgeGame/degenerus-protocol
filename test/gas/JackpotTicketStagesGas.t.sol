// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";

contract TicketStageGasSeeder is PhaseEndSeeder {
    function expandBuckets(uint8[4] calldata mainTraits) external {
        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(level, mainTraits[q]);
            _seedBucketDistinct(level, mainTraits[q], 20_000, uint160(0x5000000000 + uint256(q) * 0x100000));
        }
    }
}

/// @dev The phase-end coin+tickets stage with a much deeper ticket-board bucket (20,000
///      holders/quadrant) than Lvl100PhaseEndAdvanceGas's 130 — the cursor/queue depth stress.
///      Large disjoint buckets exercise fresh recipient writes; assertions prevent repeat winners
///      reducing the result. The stage runs no battle work of its own (the far-future queues
///      `seedPhaseEnd` seeds go unread here). The leg is read from the ordered log stream, each
///      call at a realistic allowance; its largest call is logged (no whole-call ceiling).
contract DailyTicketStageGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainTraits = JackpotBucketLib.getRandomTraits(word);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TicketStageGasSeeder).runtimeCode);
        TicketStageGasSeeder seeder = TicketStageGasSeeder(payable(address(game)));
        // Every queue through level 100 has drained: free the recycled roots seedPhaseEnd fills.
        TQ.retireCompleted(address(game), LVL);
        seeder.seedPhaseEnd(LVL, word, mainTraits, uint160(0x1000000000));
        seeder.expandBuckets(mainTraits);
        _openSession();
        _restore(original);
    }

    function test_ColdTicketStageWithDistinctRecipients() public {
        (uint8 stage, uint256 from, uint256 to, uint256 used) = _nextStageRun(200);
        if (stage == STAGE_JACKPOT_COIN_TICKETS && game.rngLocked()) {
            uint256 g;
            (stage,, to, g) = _nextStageRun(200);
            if (g > used) used = g;
        }
        address[] memory recipients = new address[](TICKET_LEG_WINNERS);
        uint256 tickets;
        uint256 battleEntries;
        for (uint256 i = from; i <= to; ++i) {
            Vm.Log storage l = streamLogs[i];
            if (l.topics.length == 0) continue;
            bytes32 sig = l.topics[0];
            if (sig == TICKET_WIN_SIG) {
                tickets = _pushDistinctRecipient(recipients, tickets, address(uint160(uint256(l.topics[1]))));
            } else if (sig == TICKET_BATCH_SIG) {
                // Direct next-level materialization names registry owner IDs (95d88f68b).
                (, uint8 count,, uint256[4] memory owners,) = abi.decode(l.data, (uint16, uint8, uint32, uint256[4], uint256[4]));
                for (uint256 j; j < count; ++j) {
                    tickets = _pushDistinctRecipient(recipients, tickets, _ownerAt(uint32(owners[j >> 3] >> (32 * (j & 7)))));
                }
            } else if (sig == BATTLE_ENTRY_SIG) {
                ++battleEntries;
            }
        }
        assertEq(tickets, TICKET_LEG_WINNERS, "the ticket leg paid the full 192-winner cap");
        assertEq(battleEntries, 0, "the coin+tickets stage runs no battle work");
        assertEq(stage, STAGE_JACKPOT_PHASE_ENDED);
        emit log_named_uint("DAILY_192_TICKETS_DEEP_BUCKET_LARGEST_CALL_INCLUDING_INTRINSIC", used);
    }

    function _pushDistinctRecipient(address[] memory recipients, uint256 n, address player) private pure returns (uint256) {
        for (uint256 j; j < n; ++j) assertTrue(recipients[j] != player, "ticket recipients must be distinct");
        recipients[n] = player;
        return n + 1;
    }
}
