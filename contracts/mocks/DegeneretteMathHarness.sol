// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameDegeneretteModule} from "../modules/DegenerusGameDegeneretteModule.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";

/// @dev Exposes the production pure math for exhaustive and differential tests.
contract DegeneretteMathHarness is DegenerusGameDegeneretteModule {
    function score(uint32 p, uint32 r) external pure returns (uint8, uint8) {
        return _score(p, r);
    }

    function payout(uint8 s, uint8 w, uint8 currency, uint128 stake, uint16 activity) external pure returns (uint256) {
        SpinResult memory spin;
        spin.score = s;
        spin.resultWilds = w;
        return _degenerettePayout(spin, currency, stake, activity);
    }

    function base(uint8 s) external pure returns (uint256) {
        return _basePayoutCentiX(s);
    }

    function ethAdd(uint8 s) external pure returns (uint256) {
        return _ethAddCentiX(s);
    }

    function roi(uint16 activity) external pure returns (uint256) {
        return _roiBpsFromScore(activity, false);
    }

    function wwxrpRoi(uint16 activity) external pure returns (uint256) {
        return _roiBpsFromScore(activity, true);
    }

    function ticket(uint256 seed, uint8 symbol) external pure returns (uint32) {
        return _playerTicket(seed, symbol);
    }

    function traits(uint256 seed) external pure returns (uint32) {
        return DegenerusTraitUtils.packedTraitsDegenerette(seed);
    }

    function ordinaryTraits(uint256 seed) external pure returns (uint32) {
        return DegenerusTraitUtils.packedTraitsDegeneretteOrdinary(seed);
    }

    function hero(uint256 seed, uint8 symbol) external pure returns (uint8) {
        return _spinSymbol(seed, symbol);
    }

    function rig(uint32 p, uint32 r, uint8 heroQuadrant, uint256 seed) external pure returns (uint32) {
        return _rigWwxrpResult(p, r, heroQuadrant, seed);
    }

    function spin(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        external pure returns (uint32, uint32, uint8, uint8)
    {
        SpinResult memory s = _rollSpin(seed, houseSeed, symbol, currency);
        return (s.playerTraits, s.resultTraits, s.score, s.resultWilds);
    }
}
