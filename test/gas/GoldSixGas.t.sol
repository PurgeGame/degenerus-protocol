// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract GoldSixGasHarness is DegenerusGameTicketModule {
    function seedGoldSix() external {
        _setTicketBufferLevel(1);
        _bucketAppendRun(_traitBufferBase(1), 253, 0, 1, 1);
    }
    function seed(uint256 players, uint32 entriesScaled) external {
        level = 1;
        for (uint256 i; i < players; ++i) _queueEntriesScaled(address(uint160(0x1000 + i)), 1, entriesScaled, false);
        ticketWriteSlot = !ticketWriteSlot;
        rngWordCurrent = 0xabcdef123456;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
    }
}

contract GoldSixFoilGasHarness is DegenerusGameFoilPackModule {
    function seed() external {
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        _setTicketBufferLevel(1);
        uint256 priorOwner = uint256(_registerEntryOwner(address(0xBEEF), 1) >> OWNER_IDX_SHIFT) - 1;
        _bucketAppendRun(_traitBufferBase(1), 253, priorOwner, 1, 1);
        for (uint256 i; i < 8; ++i) {
            address who = address(uint160(0x1000 + i));
            uint256 owner = uint256(_registerEntryOwner(who, 1) >> OWNER_IDX_SHIFT);
            foilRecord[1][who] = (uint256(20_000) << _FOIL_MULT_SHIFT) | (uint256(1) << _FOIL_LEVEL_SHIFT);
            foilQueue[_foilWriteKey()].push((owner << 192) | (uint256(1) << 160) | uint160(who));
        }
        // The daily request swaps both cohorts; foil keys follow foilWriteSlot (017ac4cdf).
        ticketWriteSlot = !ticketWriteSlot;
        foilWriteSlot = !foilWriteSlot;
        rngWordCurrent = 0xabcdef123456;
        _setRngSessionPublished(true);
    }
}

contract GoldSixGasTest is Test {
    function testFoilDrainGasAfterGoldSixTaken() public {
        vm.etch(ContractAddresses.GAME, type(GoldSixFoilGasHarness).runtimeCode);
        GoldSixFoilGasHarness h = GoldSixFoilGasHarness(ContractAddresses.GAME);
        h.seed();
        vm.cool(address(h));
        uint256 beforeGas = gasleft();
        MineFlipGas.Result memory r = h.runFoilWork{gas: 9_000_000}(9_000_000);
        uint256 used = beforeGas - gasleft();
        assertTrue(r.progressed && r.done, "bounded transaction completes eight packs");
        assertLt(used, 9_000_000);
        emit log_named_uint("eight foil packs drain gas", used);
    }

    function measure(uint256 players, uint32 entriesScaled, bool goldSixTaken) private {
        GoldSixGasHarness h = new GoldSixGasHarness();
        h.seed(players, entriesScaled);
        if (goldSixTaken) h.seedGoldSix();
        vm.cool(address(h));
        uint256 beforeGas = gasleft();
        MineFlipGas.Result memory r = h.runTicketWork{gas: 9_000_000}(2, 9_000_000);
        uint256 used = beforeGas - gasleft();
        assertTrue(r.progressed && r.done, "bounded transaction completes this fixed cohort");
        assertLt(used, 9_000_000);
        emit log_named_uint("fixed cohort drain gas", used);
    }
    function testSoloDrainGas() public { measure(1, 12_800, false); }
    function testSoloDrainGasAfterGoldSixTaken() public { measure(1, 12_800, true); }
    function testRoundDrainGas() public { measure(8, 4_000, false); }
}
