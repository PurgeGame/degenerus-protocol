// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameDegeneretteModule} from "../modules/DegenerusGameDegeneretteModule.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";

/// @dev Exposes the production pure math for exhaustive and differential tests.
contract DegeneretteMathHarness is DegenerusGameDegeneretteModule {
    function score(uint32 p, uint32 r, uint8 hero) external pure returns (uint8, uint8) {
        return _score(p, r, hero);
    }

    /// @dev Calls _score with arbitrary bits above each argument's type width, as assembly-built
    ///      or unmasked sub-word values may carry.
    function scoreDirty(uint256 pWord, uint256 rWord, uint256 heroWord) external pure returns (uint8, uint8) {
        uint32 p;
        uint32 r;
        uint8 hero;
        assembly ("memory-safe") {
            p := pWord
            r := rWord
            hero := heroWord
        }
        return _score(p, r, hero);
    }

    function payout(uint8 s, uint8 g, uint8 currency, uint128 stake, uint16 activity) external pure returns (uint256) {
        SpinResult memory spin;
        spin.score = s;
        spin.goldMatches = g;
        return _degenerettePayout(spin, currency, stake, activity);
    }

    function base(uint8 s) external pure returns (uint256) {
        return _basePayoutCentiX(s);
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

    function hero(uint256 seed, uint8 symbol) external pure returns (uint8) {
        return _spinSymbol(seed, symbol);
    }

    function rig(uint32 p, uint32 r, uint8 heroQuadrant, uint256 seed) external pure returns (uint32) {
        return _rigWwxrpResult(p, r, heroQuadrant, seed);
    }

    function spin(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        external pure returns (uint32, uint32, uint8, uint8, uint8)
    {
        SpinResult memory s = _rollSpin(seed, houseSeed, symbol, currency);
        return (s.playerTraits, s.resultTraits, s.heroQuadrant, s.score, s.goldMatches);
    }
}
