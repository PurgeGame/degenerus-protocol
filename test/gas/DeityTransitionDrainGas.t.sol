// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";

contract DeityTransitionQueueSeeder is DegenerusGameStorage {
    function seedSurvivors(uint24 target) external {
        uint24 key = _tqFarFutureKey(target);
        for (uint160 i; i < 8; ++i) {
            address who = address(0xF0100000 + i);
            uint80 packed = _registerEntryOwner(who, target);
            uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
            entryOwnerPosition[key][who] = pos;
            _tqAppend(key, pos);
            _setEntryOwed(target, pos, packed | (uint80(1_000_000) << 8));
        }
    }
}

contract DeityTransitionDrainGasTest is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();
        bytes memory original = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(LVL, uint256(keccak256("deity-transition-full-drain")) | 1);
        vm.etch(address(game), type(DeityTransitionQueueSeeder).runtimeCode);
        DeityTransitionQueueSeeder(address(game)).seedSurvivors(LVL + 5);
        _restore(original);
    }
    function testColdThirtyTwoPerpetualGrantsPlusFullDrainChunkFitAndResume() public {
        uint256 beforeGas = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("cold 32-deity renewal plus full FF drain including intrinsic", used);
        assertLt(used, 16_777_216);
        _checkOwners();
        // A surviving FF cohort resumes; no owner gets a second perpetual ticket.
        game.advanceGame{gas: 16_777_216 - 21_064}();
        _checkOwners();
    }
    function _checkOwners() private {
        DegenerusGameLens lens = new DegenerusGameLens();
        for (uint256 i; i < 32; ++i) {
            address owner = lens.deityOwnerAt(address(game), i);
            uint24 key = (uint24(1) << 22) | (LVL + 100);
            assertEq(uint32(TQ.owed(address(game), key, owner) >> 8), 4);
        }
    }
}
