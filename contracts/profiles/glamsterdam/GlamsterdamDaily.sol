// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameAdvanceModule} from "../../modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameJackpotModule} from "../../modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameJackpotDrawModule} from "../../modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameRngModule} from "../../modules/DegenerusGameRngModule.sol";
import {MineFlipGas} from "../../libraries/MineFlipGas.sol";

/// @notice Daily processing, jackpot draws and RNG in the Game storage context.
contract GlamsterdamDaily is DegenerusGameAdvanceModule, DegenerusGameJackpotModule, DegenerusGameJackpotDrawModule, DegenerusGameRngModule {
    function _rngPrepareRequestBoundary(uint24 day) internal override {
        prepareRequestBoundary(day);
    }

    function _dailyRunJackpot(bool inJackpot, uint24 lvl, uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runDailyJackpot(inJackpot, lvl, word, allowance);
    }

    function _dailyRunTickets(uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runDailyJackpotTickets(word, allowance);
    }

    function _dailyRunEarlyBird(uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runEarlyBirdTickets(word, allowance);
    }

    function _dailyRunPurchaseTickets(uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runPurchaseDailyTickets(word, allowance);
    }

    function _dailyRunBaf(uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runBafAwards(word, allowance);
    }

    function _dailyPayFlip(uint24 lvl, uint256 word, uint24 minLevel, uint24 maxLevel) internal override {
        payDailyFlipJackpot(lvl, word, minLevel, maxLevel);
    }

    function _dailyRunBattle(uint24 lvl, uint256 word, uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return runPurchaseJackpotBattle(lvl, word, allowance);
    }

    function _drawPayGoldenTicket(uint32 winner, uint24 lvl, uint8 route, uint8 golds, bool grand) internal override {
        payGoldenTicket(winner, lvl, route, golds, grand);
    }

    function _drawAwardDailyFlip(uint24 minLevel, uint24 maxLevel, uint32 traits, uint256 budget, uint256 word) internal override {
        awardDailyFlipJackpot(minLevel, maxLevel, traits, budget, word);
    }

    function _drawRunBaf(uint256 word, uint256 allowance, uint8[3] memory traits) internal override returns (MineFlipGas.Result memory) {
        return runBafAwards(word, allowance, traits);
    }

    function _dailyDistributeYield(MineFlipGas.Meter memory meter) internal override {
        _distributeYieldSurplus(meter);
    }

    function _dailyEmitLevelOneTraits(uint256 word) internal override {
        _emitLevelOneWinningTraits(word);
    }
}
