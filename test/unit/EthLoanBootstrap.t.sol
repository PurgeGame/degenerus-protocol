// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMintStreakUtils} from "../../contracts/modules/DegenerusGameMintStreakUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @notice Checks the finite whale-pass bootstrap model against production queue/quote helpers.
/// @dev Excludes bundled rewards, subsequent purchases, and later outcomes. Seeding the
/// quoted award is not an end-to-end purchase or eligibility test.
contract EthLoanBootstrapTest is Test, DegenerusGameMintStreakUtils {
    function _awardAndQuote(uint24 start, uint256 quantity, bool jackpot)
        private returns (uint256 principal, uint256 cost)
    {
        level = start - 1;
        jackpotPhaseFlag = jackpot;
        uint256 award = quantity + quantity / 5;
        uint24 bonus = start < 10 ? 10 - start : 0;
        if (bonus != 0) _queueEntryRange(7, start, bonus, uint32(20 * award));
        _queueHalfPassAward(7, start + bonus, 100 - bonus, 2 * award);
        (, principal) = _quoteLoan(7, start);
        uint256 unit = start <= 4 ? 2.4 ether : 4 ether;
        cost = unit * (100 * quantity - 35) / 100;

        uint256 model;
        uint256 active = jackpot ? start - 1 : start;
        for (uint24 target = start + 2; target < start + 100; ++target) {
            uint256 tickets = target < 10 ? 5 * award
                : award / 2 + (award % 2 != 0 && (target - start - bonus) % 2 == 0 ? 1 : 0);
            uint256 d = target - active;
            uint256 bps = d <= 20 ? 1000 - (d - 2) * 500 / 18 : 500 - (d - 20) * 300 / 80;
            model += PriceLookupLib.priceForLevel(target) * tickets * bps / 10_000;
        }
        assertEq(principal, model, "finite model agrees with production queued collateral quote");
    }

    function test_maximumBootstrapWitness() public {
        (uint256 principal, uint256 cost) = _awardAndQuote(1, 1, false);
        assertEq(principal, 0.205175 ether);
        assertEq(cost, 1.56 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_bootstrapModelMatchesProduction(uint8 startSeed, uint16 quantitySeed, bool jackpot) public {
        uint24 start = 1 + uint24(startSeed % 109);
        uint256 quantity = 1 + uint256(quantitySeed % 1000);
        (uint256 principal, uint256 cost) = _awardAndQuote(start, quantity, jackpot);
        assertLe(principal * 62400, cost * 8207, "principal/cost <= 8207/62400");
    }
}
