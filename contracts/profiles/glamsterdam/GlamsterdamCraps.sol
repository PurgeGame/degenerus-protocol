// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {ICrapsEngine, IFlipCoin, IVaultOwnership, IGameCraps, IHighRollerReserve, ICoinflipStake, IReadCohortLifecycle} from "../../CrapsInterfaces.sol";

import {CrapsBattleCore} from "../../modules/CrapsBattleCore.sol";
import {JackpotBattle} from "../../JackpotBattle.sol";
import {CrapsEngine} from "../../CrapsEngine.sol";
import {Craps} from "../../Craps.sol";

/// @notice Combined table, lifecycle and dice-engine shell.
contract GlamsterdamCraps is JackpotBattle, CrapsBattleCore, CrapsEngine {
    function _crapsSettleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll, uint256 goal, uint48 bound, uint256 field, uint256 word) internal pure virtual override returns (Craps.SlipResult memory) {
        return settleBattle(betId, header, chipFlip, bankroll, goal, bound, field, word);
    }
    function _crapsCustomDefinition(uint32 played, uint8 bankMult, uint16 goalMult, uint24 stakeUnits,
        uint40 closeTime, bool multiEntry, uint16 highRollerMult) internal view override returns (uint256)
    {
        return _customDefinition(played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult);
    }
}
