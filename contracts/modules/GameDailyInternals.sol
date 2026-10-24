// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameComponentCall} from "./GameComponentCall.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusGameAdvanceModule, IDegenerusGameJackpotModule, IDegenerusGameJackpotDrawModule} from "../interfaces/IDegenerusGameModules.sol";

/// @dev Compile-time daily component boundaries; shells inline only colocated components.
abstract contract GameDailyInternals is GameComponentCall {
    error RngNotReady();
    event Advance(uint8 stage, uint24 lvl);

    function _rngPrepareRequestBoundary(uint24 day) internal virtual {
        _componentDelegate(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSelector(IDegenerusGameAdvanceModule.prepareRequestBoundary.selector, day));
    }

    function _dailyRunJackpot(bool inJackpot, uint24 lvl, uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.runDailyJackpot.selector, inJackpot, lvl, word, allowance)), (MineFlipGas.Result));
    }

    function _dailyRunTickets(uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.runDailyJackpotTickets.selector, word, allowance)), (MineFlipGas.Result));
    }

    function _dailyRunEarlyBird(uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.runEarlyBirdTickets.selector, word, allowance)), (MineFlipGas.Result));
    }

    function _dailyRunPurchaseTickets(uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.runPurchaseDailyTickets.selector, word, allowance)), (MineFlipGas.Result));
    }

    function _dailyRunBaf(uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.runBafAwards.selector, word, allowance)), (MineFlipGas.Result));
    }

    function _dailyPayFlip(uint24 lvl, uint256 word, uint24 minLevel, uint24 maxLevel) internal virtual {
        _componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotModule.payDailyFlipJackpot.selector, lvl, word, minLevel, maxLevel));
    }

    function _dailyRunBattle(uint24 lvl, uint256 word, uint256 allowance) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotDrawModule.runPurchaseJackpotBattle.selector, lvl, word, allowance)), (MineFlipGas.Result));
    }

    function _drawPayGoldenTicket(uint32 winner, uint24 lvl, uint8 route, uint8 golds, bool grand) internal virtual {
        _componentDelegate(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotDrawModule.payGoldenTicket.selector, winner, lvl, route, golds, grand));
    }

    function _drawAwardDailyFlip(uint24 minLevel, uint24 maxLevel, uint32 traits, uint256 budget, uint256 word) internal virtual {
        _componentDelegate(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotDrawModule.awardDailyFlipJackpot.selector, minLevel, maxLevel, traits, budget, word));
    }

    function _drawRunBaf(uint256 word, uint256 allowance, uint8[3] memory traits) internal virtual returns (MineFlipGas.Result memory) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, abi.encodeWithSelector(IDegenerusGameJackpotDrawModule.runBafAwards.selector, word, allowance, traits)), (MineFlipGas.Result));
    }

    function _dailyDistributeYield(MineFlipGas.Meter memory meter) internal virtual {
        _componentDelegate(ContractAddresses.GAME_JACKPOT_MODULE,
            abi.encodeWithSelector(IDegenerusGameJackpotModule.distributeYieldSurplus.selector,
                uint256(0), MineFlipGas.child(meter, 0)));
    }

    function _dailyEmitLevelOneTraits(uint256 word) internal virtual {
        IDegenerusGame(address(this)).emitDailyWinningTraits(word);
    }
}
