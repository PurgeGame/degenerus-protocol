// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BafViews} from "../helpers/BafViews.sol";

/// @dev Distinct scored candidates expose which band the real BAF allocator used.
contract BafBandOracle {
    uint24 private immutable baseLevel;
    constructor(uint24 lvl) { baseLevel = lvl; }

    function candidate(uint256 band, uint256 rank) public pure returns (uint32) {
        return uint32(0xBAF000 + band * 16 + rank);
    }

    function sampleTraitEntries(bool next, uint8, uint256) external pure returns (uint32[] memory entries) {
        entries = new uint32[](4);
        entries[0] = candidate(next ? 1 : 0, 1);
        entries[1] = candidate(next ? 1 : 0, 2);
        return entries;
    }

    function sampleFarFutureTickets(uint256, uint24 from, uint24 to) external view returns (uint32[] memory entries) {
        uint256 band;
        if (from == baseLevel + 2 && to == baseLevel + 5) band = 2;
        else {
            require(from == baseLevel + 6 && to == baseLevel + 99, "unexpected/history band");
            band = 3;
        }
        entries = new uint32[](8);
        entries[0] = entries[4] = candidate(band, 1);
        entries[1] = entries[5] = candidate(band, 2);
    }
}

/// @notice Each scatter round's band at 48 rounds: rounds 0-11 sample the level's trait buckets,
///         12-23 the next level's, 24-35 the far-future queues lvl+2..lvl+5 and 36-47
///         lvl+6..lvl+99, read through `DegenerusJackpots.bafPairWinners` (the pair view the award
///         stage pays from; `BafViews.round` takes one round's half). The higher score takes the
///         round's first place and the lower its second; no round reads a past level. The head
///         slots (`bafHeadWinner`) read the board, not the bands.
contract BafForwardBandsTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }

    function test_CenturyPaysTwelveRoundsInEachForwardBand() public { _check(100); }
    function test_OrdinaryBracketKeepsTwelveRoundsInEachForwardBand() public { _check(110); }

    function _check(uint24 lvl) private {
        BafBandOracle oracle = new BafBandOracle(lvl);
        for (uint256 band; band < 4; ++band) {
            vm.startPrank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(oracle.candidate(band, 1), lvl, (100 + band) * 1 ether);
            jackpots.recordBafFlip(oracle.candidate(band, 2), lvl, 50 ether);
            vm.stopPrank();
        }
        vm.etch(address(game), address(oracle).code);
        uint256[4] memory first;
        uint256[4] memory second;
        for (uint256 round; round < 48; ++round) {
            (uint32 best, uint32 next) = BafViews.round(address(jackpots), lvl, 123, round, 48);
            uint256 band = (uint256(best) - 0xBAF000) / 16;
            assertLt(band, 4, "scatter never pays historical candidates");
            assertEq(band, round / 12, "twelve-round bands in forward order");
            assertEq(best, oracle.candidate(band, 1), "highest score gets first place");
            assertEq(next, oracle.candidate(band, 2), "second score gets second place");
            ++first[band];
            ++second[band];
        }
        for (uint256 band; band < 4; ++band) {
            assertEq(first[band], 12, "twelve first prizes in each forward band");
            assertEq(second[band], 12, "twelve second prizes in each forward band");
        }
        // Head slots: the top bettor and the word-picked third or fourth place of the board.
        assertEq(jackpots.bafHeadWinner(lvl, 123, 0), oracle.candidate(3, 1), "slot 0 is the top bettor");
        uint32 pick = jackpots.bafHeadWinner(lvl, 123, 2);
        assertTrue(pick == oracle.candidate(1, 1) || pick == oracle.candidate(0, 1), "slot 2 is third or fourth place");
    }
}
