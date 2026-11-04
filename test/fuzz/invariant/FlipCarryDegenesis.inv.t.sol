// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {FlipCarryAccountingInvariant} from "./FlipCarryAccounting.inv.t.sol";

/// @title FlipCarryDegenesis -- the FlipCarryAccounting oracle after a real Degenesis week
/// @notice Starts from the production timeline (deploy on day index 1, a real Degenesis week with
///         the turbo launch) instead of the post-Degenesis header fixture, so every coinflip day
///         resolves in order from day 2 and the Vault holds a real Degenesis budget. Adds
///         `vaultBuysForGnrus`: the Vault spending that budget on GNRUS tickets, the one GNRUS
///         purchase made WITHOUT a donor code, whose FLIP must route ordinarily (GNRUS keeps its
///         bonus, VAULT/sDGNRS take the no-referrer commission, no donor is paid).
contract FlipCarryDegenesisInvariant is FlipCarryAccountingInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _fixture() internal override {
        _deployProtocol();
        _degenesisWeek(true);
    }

    function _selectors() internal view virtual override returns (bytes4[] memory s) {
        bytes4[] memory base = super._selectors();
        s = new bytes4[](base.length + 1);
        for (uint256 k; k < base.length; ++k) s[k] = base[k];
        s[base.length] = h.vaultBuysForGnrus.selector;
    }

    function _prefix() internal pure virtual override returns (string memory) {
        return "FCD_";
    }

    /// @dev The zero-code Vault purchase for GNRUS is required here.
    function _required(uint256 k) internal pure virtual override returns (bool) {
        return k == 32 || super._required(k);
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
