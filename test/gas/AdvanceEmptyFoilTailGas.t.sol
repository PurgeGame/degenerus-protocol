// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PurchaseDailyFixture, PurchaseDailySeeder} from "./PurchaseDailyWorstCase.t.sol";

contract EmptyFoilTailSeeder is DegenerusGame {
    function seedTail(uint24 emptyDays, uint256 payoutWord) external {
        uint24 wallDay = _simulatedDayIndex();
        uint24 first = wallDay - emptyDays;
        dailyIdx = first - 1;
        purchaseStartDay = wallDay;
        rngRequestTime = uint48(block.timestamp);
        ticketsFullyProcessed = false;
        foilDrainDay = first;
        foilLastResolveDay = wallDay;
        // A future/unsealed bucket terminates the empty walk without resolving a buyer.
        foilBuyers[wallDay].push(uint256(uint160(address(0xF011))) | (uint256(level + 1) << 160));
        for (uint24 d = first; d < wallDay; ++d) {
            rngWordByDay[d] = uint256(keccak256(abi.encode(d))) | 1;
        }
        rngWordByDay[first] = payoutWord;
        rngWordByDay[wallDay] = 0;
    }
}

abstract contract EmptyFoilTailFixture is PurchaseDailyFixture {
    function _days() internal pure virtual returns (uint24);

    function setUp() public {
        PurchaseDailySeeder.Shape memory shape =
            _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_LATCH, PREV_POOL_OPEN25);
        _seed(shape);
        vm.warp((999 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(EmptyFoilTailSeeder).runtimeCode);
        EmptyFoilTailSeeder(payable(address(game))).seedTail(_days(), shape.word);
        vm.etch(address(game), original);
    }

    function test_EmptyFoilWalkAndCompleteCachedDailyShareOneTransaction() public {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethAwards;
        uint256 tickets;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_WIN_SIG) ++ethAwards;
            if (topic == TICKET_WIN_SIG) ++tickets;
            if (topic == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("empty_foil_days", _days());
        emit log_named_uint("empty_walk_plus_daily_including_intrinsic", used);
        assertEq(stage, STAGE_PURCHASE_DAILY, "empty cleanup must fall through to the full daily");
        assertEq(ethAwards, PURCHASE_ETH_WINNERS, "all ETH draws must execute");
        assertEq(tickets, 0, "the ticket leg waits for its own stage");
        assertEq(
            uint24(uint256(vm.load(address(game), bytes32(uint256(62)))) >> 32),
            1000,
            "entire empty foil tail must advance"
        );
        assertLt(used, EIP7825_TX_GAS_CAP, "composed empty scan and payout exceed cap");

        // The priced ticket leg pays from the next advance on the same recorded word.
        vm.recordLogs();
        before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        used = before - gasleft() + 21_064;
        logs = vm.getRecordedLogs();
        tickets = 0;
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TICKET_WIN_SIG) ++tickets;
            if (logs[i].topics[0] == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("ticket_stage_including_intrinsic", used);
        assertEq(stage, 15, "the purchase ticket stage must follow");
        assertEq(tickets, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket awards must execute in the ticket stage");
        assertLt(used, EIP7825_TX_GAS_CAP, "ticket stage exceeds cap");
    }
}

/// @dev The widest backlog the 30-day VRF deadman lets a live game carry: one more unsealed day and
///      the game ends instead of walking.
contract AdvanceEmptyFoilGapTail is EmptyFoilTailFixture {
    function _days() internal pure override returns (uint24) {
        return 29;
    }
}
