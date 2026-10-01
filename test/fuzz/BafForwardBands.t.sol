// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Distinct scored candidates expose which band the real BAF allocator used.
contract BafBandOracle {
    uint24 private immutable baseLevel;
    constructor(uint24 lvl) { baseLevel = lvl; }

    function candidate(uint256 band, uint256 rank) public pure returns (address) {
        return address(uint160(0xBAF000 + band * 16 + rank));
    }

    function sampleTraitEntries(bool next, uint256) external pure returns (uint8, address[] memory entries) {
        entries = new address[](4);
        entries[0] = candidate(next ? 1 : 0, 1);
        entries[1] = candidate(next ? 1 : 0, 2);
        return (0, entries);
    }

    function sampleFarFutureTickets(uint256, uint24 from, uint24 to) external view returns (address[] memory entries) {
        uint256 band;
        if (from == baseLevel + 2 && to == baseLevel + 5) band = 2;
        else {
            require(from == baseLevel + 6 && to == baseLevel + 99, "unexpected/history band");
            band = 3;
        }
        entries = new address[](8);
        entries[0] = entries[4] = candidate(band, 1);
        entries[1] = entries[5] = candidate(band, 2);
    }
}

contract BafForwardBandsTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }

    function test_CenturyPaysTwelveRoundsInEachForwardBand() public { _check(100); }
    function test_OrdinaryBracketKeepsTwelveRoundsInEachForwardBand() public { _check(110); }

    function _check(uint24 lvl) private {
        BafBandOracle oracle = new BafBandOracle(lvl);
        for (uint256 band; band < 4; ++band) {
            vm.startPrank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(oracle.candidate(band, 1), lvl, 100 ether);
            jackpots.recordBafFlip(oracle.candidate(band, 2), lvl, 50 ether);
            vm.stopPrank();
        }
        vm.etch(address(game), address(oracle).code);
        vm.prank(address(game));
        (address[] memory winners, uint256[] memory amounts, uint256 back) = jackpots.runBafJackpot(48_000, lvl, 123);
        uint256[4] memory first;
        uint256[4] memory second;
        uint256 paid;
        for (uint256 i; i < winners.length; ++i) {
            paid += amounts[i];
            if (amounts[i] != 500 && amounts[i] != 300) continue;
            uint256 band = (uint160(winners[i]) - 0xBAF000) / 16;
            assertLt(band, 4, "scatter never pays historical candidates");
            if (amounts[i] == 500) {
                assertEq(winners[i], oracle.candidate(band, 1), "highest score gets first share");
                ++first[band];
            } else {
                assertEq(winners[i], oracle.candidate(band, 2), "second score gets second share");
                ++second[band];
            }
        }
        for (uint256 band; band < 4; ++band) {
            assertEq(first[band], 12, "twelve first prizes in each forward band");
            assertEq(second[band], 12, "twelve second prizes in each forward band");
        }
        assertEq(paid + back, 48_000, "payouts plus refund conserve BAF pool");
    }
}
