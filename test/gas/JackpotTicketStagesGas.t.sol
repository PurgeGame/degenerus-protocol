// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

contract TicketStageGasSeeder is PhaseEndSeeder {
    function expandBuckets(uint8[4] calldata mainTraits) external {
        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(level, mainTraits[q]);
            _seedBucketDistinct(level, mainTraits[q], 20_000, uint160(0x5000000000 + uint256(q) * 0x100000));
        }
    }
}

/// @dev Measures the phase-end coin+tickets stage from a cold transaction with a much deeper
///      ticket-board bucket (20,000 holders/quadrant) than Lvl100PhaseEndAdvanceGas's 130 — the
///      cursor/queue depth stress. Large disjoint buckets exercise fresh recipient writes;
///      assertions prevent repeat winners reducing the result. The stage runs no battle work of
///      its own (the far-future queues `seedPhaseEnd` seeds go unread here — the fill stage owns
///      them, from its own earlier tx).
contract DailyTicketStageGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainTraits = JackpotBucketLib.getRandomTraits(word);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TicketStageGasSeeder).runtimeCode);
        TicketStageGasSeeder seeder = TicketStageGasSeeder(payable(address(game)));
        seeder.seedPhaseEnd(LVL, word, mainTraits, uint160(0x1000000000));
        seeder.expandBuckets(mainTraits);
        _restore(original);
    }

    function test_ColdTicketStageWithDistinctRecipients() public {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address[96] memory recipients;
        address[64] memory battleWallets;
        uint256 tickets;
        uint256 battleRuns;
        uint256 battleDistinct;
        uint8 stage;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 sig = logs[i].topics[0];
            if (sig == TICKET_WIN_SIG) {
                address player = address(uint160(uint256(logs[i].topics[1])));
                for (uint256 j; j < tickets; ++j) assertTrue(recipients[j] != player, "ticket recipients must be distinct");
                recipients[tickets++] = player;
            } else if (sig == BATTLE_RUN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[2])));
                bool fresh = true;
                for (uint256 j; j < battleRuns; ++j) {
                    if (battleWallets[j] == w) {
                        fresh = false;
                        break;
                    }
                }
                if (fresh) ++battleDistinct;
                if (battleRuns < battleWallets.length) battleWallets[battleRuns] = w;
                ++battleRuns;
            } else if (sig == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        assertEq(tickets, 96, "the ticket leg paid the full 96-winner cap");
        assertEq(battleRuns, 0, "the coin+tickets stage runs no battle work: the fill stage owns it");
        assertEq(battleDistinct, 0);
        assertEq(stage, STAGE_JACKPOT_PHASE_ENDED);
        emit log_named_uint("DAILY_96_TICKETS_DEEP_BUCKET_COLD_INCLUDING_INTRINSIC", used);
        assertLt(used, EIP7825_TX_GAS_CAP);
    }
}
