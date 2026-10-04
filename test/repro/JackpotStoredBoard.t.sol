// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract StoredBoardHarness is DegenerusGameJackpotModule {
    function seed(uint8 counter, bool turbo) external {
        level = 4;
        dailyIdx = 100;
        rngLockedFlag = true;
        jackpotPhaseFlag = true;
        jackpotCounter = counter;
        jackpotFlags = turbo ? JACKPOT_TURBO : 0;
        _setPrizePools(0, 100 ether);
        dailyHeroWagers[100][1] = uint256(1000) << (5 * 32);
        // Both parity lanes exist; the preceding day's board must never be selected.
        dailyFoilDraw[0] = _packFoilDraw(0xC0804000, 3, 100, 123);
    }

    function replaceHeroAfterSeal() external {
        // Test-only fault injection: a reroll would change quadrant 1 from 101 to 103.
        dailyHeroWagers[100][1] = uint256(1000) << (7 * 32);
    }

    function draw() external view returns (bool, uint32, uint24) { return _foilDrawFor(101); }
    function work() external view returns (JackpotWork memory) { return jackpotWork; }

    function completedTickets() external {
        level = 4;
        dailyJackpotCoinTicketsPending = true;
        dailyTicketBudgetsPacked = uint256(40) << 8;
        jackpotWork.kind = 6;
        jackpotWork.lvl = 4;
        jackpotWork.quadrant = 4;
        jackpotWork.budget = 40;
    }

    function completion() external view returns (uint8, bool, uint256) {
        return (jackpotCounter, dailyJackpotCoinTicketsPending, dailyTicketBudgetsPacked);
    }
}

contract JackpotStoredBoardTest is Test {
    uint256 private constant WORD = 2;
    StoredBoardHarness private h;

    function setUp() public {
        h = new StoredBoardHarness();
        // A refused ticket checkpoint returns three zero words. Keeping the setup
        // checkpoint exposes the exact board and source level latched by production.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, hex"60006000526000602052600060405260606000f3");
    }

    function testFuzz_TicketLegUsesSealedBoardAcrossStallsAndDayShapes(
        bool earlyBird, uint8 counterSeed, bool turbo, uint16 stalledDays
    ) public {
        h.seed(earlyBird || turbo ? 0 : counterSeed % 3, turbo);
        MineFlipGas.Result memory ethLeg = h.runDailyJackpot(true, 4, WORD, 5_000_000);
        assertTrue(ethLeg.done, "the ETH leg records the board before retirement");
        assertEq(h.work().kind, 0, "ETH work retired");
        (bool present, uint32 sealedBoard, uint24 sourceLevel) = h.draw();
        assertTrue(present);
        assertEq(sourceLevel, 4);
        assertEq(uint8(sealedBoard >> 8), 101, "recorded board contains the sealed hero");

        h.replaceHeroAfterSeal();
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 101 + stalledDays) * 1 days);
        MineFlipGas.Result memory r = earlyBird
            ? h.runEarlyBirdTickets(WORD, 1_000_000)
            : h.runDailyJackpotTickets(WORD, 1_000_000);
        assertTrue(r.progressed);
        assertFalse(r.done);
        assertEq(h.work().traits, sealedBoard, "both legs retain the recorded board without rerolling");
        assertEq(h.work().lvl, earlyBird ? 5 : 4, "award source level is independent of draw source level");

        r = earlyBird ? h.runEarlyBirdTickets(WORD, 1_000_000) : h.runDailyJackpotTickets(WORD, 1_000_000);
        assertFalse(r.progressed, "a refused continuation preserves its checkpoint");
        assertEq(h.work().traits, sealedBoard);
    }

    function test_CompletedTicketAwardsFinalizeWithoutCallingTicketWorker() public {
        h.completedTickets();
        // Any delegatecall would revert. Finalization must still respect its gas bound.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, hex"60006000fd");
        MineFlipGas.Result memory r = h.runDailyJackpotTickets(WORD, 315_000);
        assertFalse(r.progressed);
        assertFalse(r.done);
        assertEq(h.work().quadrant, 4);

        r = h.runDailyJackpotTickets(WORD, 1_000_000);
        assertTrue(r.progressed);
        assertTrue(r.done);
        assertEq(h.work().kind, 0);
        (uint8 counter, bool pending, uint256 budgets) = h.completion();
        assertEq(counter, 1);
        assertFalse(pending);
        assertEq(budgets, 0);
        r = h.runDailyJackpotTickets(WORD, 1_000_000);
        assertTrue(r.done);
        assertFalse(r.progressed);
        (counter,,) = h.completion();
        assertEq(counter, 1, "finalization cannot count the same day twice");
    }
}
