// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

contract TicketStageGasSeeder is PhaseEndSeeder {
    function expandBuckets(uint8[4] calldata mainTraits, uint8[4] calldata bonusTraits) external {
        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(level, mainTraits[q]);
            _seedBucketDistinct(level, mainTraits[q], 20_000, uint160(0x5000000000 + uint256(q) * 0x100000));
            _seedBucketClear(level, bonusTraits[q]);
            _seedBucketDistinct(level, bonusTraits[q], 20_000, uint160(0x6000000000 + uint256(q) * 0x100000));
        }
    }
}

/// @dev Measures each complete advance from a cold transaction. Large disjoint buckets
///      exercise fresh recipient writes; assertions prevent repeat winners reducing the result.
abstract contract TicketStageGasFixture is BoundaryGasFixture {
    function carryover() internal pure virtual returns (bool);

    function setUp() public {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainTraits = JackpotBucketLib.getRandomTraits(word);
        uint8[4] memory bonusTraits = JackpotBucketLib.getRandomTraits(
            EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS")))
        );
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TicketStageGasSeeder).runtimeCode);
        TicketStageGasSeeder seeder = TicketStageGasSeeder(payable(address(game)));
        seeder.seedPhaseEnd(LVL, word, mainTraits, bonusTraits, uint160(0x1000000000));
        seeder.expandBuckets(mainTraits, bonusTraits);
        _restore(original);
        if (carryover()) game.advanceGame();
    }

    function test_ColdTicketStageWithDistinctRecipients() public {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address[96] memory recipients;
        uint256 tickets;
        uint256 nearWins;
        uint256 farWins;
        uint256 seatWins;
        uint8 stage;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 sig = logs[i].topics[0];
            if (sig == TICKET_WIN_SIG) {
                address player = address(uint160(uint256(logs[i].topics[1])));
                for (uint256 j; j < tickets; ++j) assertTrue(recipients[j] != player, "ticket recipients must be distinct");
                recipients[tickets++] = player;
            } else if (sig == FLIP_WIN_SIG) ++nearWins;
            else if (sig == FAR_WIN_SIG) ++farWins;
            else if (sig == CRAPS_WIN_SIG) ++seatWins;
            else if (sig == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        assertEq(tickets, 96);
        // The jackpot-day coin draw on level + 1: 25 craps seats and 25 equal coin shares, no
        // far-future leg.
        assertEq(nearWins, carryover() ? 0 : 25);
        assertEq(seatWins, carryover() ? 0 : 25);
        assertEq(farWins, 0);
        assertEq(stage, carryover() ? STAGE_JACKPOT_CARRYOVER_TICKETS : STAGE_JACKPOT_PHASE_ENDED);
        emit log_named_uint(carryover() ? "CARRYOVER_96_COLD_INCLUDING_INTRINSIC" : "DAILY_96_TICKETS_25_SEATS_25_FLIP_COLD_INCLUDING_INTRINSIC", used);
        assertLt(used, EIP7825_TX_GAS_CAP);
    }
}

contract DailyTicketStageGas is TicketStageGasFixture {
    function carryover() internal pure override returns (bool) { return false; }
}

contract CarryoverTicketStageGas is TicketStageGasFixture {
    function carryover() internal pure override returns (bool) { return true; }
}
