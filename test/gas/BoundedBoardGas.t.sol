// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

contract BoundedBoardHost is DegenerusGameJackpotModule {
    function seed(bool populated, bool recycled) external {
        dailyIdx = 100;
        if (populated) {
            for (uint8 q; q < 3; ++q) {
                for (uint8 s; s < 8; ++s) {
                    lootboxRngPacked = _recordHeroWager(q, s, 1 + uint256(q) * 8 + s, lootboxRngPacked);
                }
            }
        }
        _sealBenchmarkHero();
        if (recycled) dailyFoilDraw[1] = _packFoilDraw(0x01020304, 1, 99, 123);
    }
    function _sealBenchmarkHero() private { _sealHeroWagers(101); }
    function drawn() external view returns (bool present, uint32 traits) {
        (present, traits,) = _foilDrawFor(101);
    }
}

contract BoundedBoardGasTest is BoundedGasProbe {
    function _run(string memory label, bool populated, bool recycled) private {
        BoundedBoardHost host = new BoundedBoardHost();
        host.seed(populated, recycled);
        _measureBounded(label, address(host), ContractAddresses.GAME, 0,
            abi.encodeCall(host.emitDailyWinningTraits, (uint256(0xCAFE))), false);
        (bool present,) = host.drawn();
        assertTrue(present, "production board persisted for day101");
    }
    function test_G3_Hero_EmptyFirstBoard() public { _run("G3_hero_empty_board", false, false); }
    function test_G3_Hero_AllWeightsFirstBoard() public { _run("G3_hero_full_board", true, false); }
    function test_G3_Hero_AllWeightsRecycledBoard() public { _run("G3_hero_recycled_board", true, true); }
}
