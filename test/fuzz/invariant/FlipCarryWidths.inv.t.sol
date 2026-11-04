// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {FlipCarryDegenesisInvariant} from "./FlipCarryDegenesis.inv.t.sol";

/// @title FlipCarryWidths -- the FlipCarryAccounting oracle with positions pushed to the widths
/// @notice Same handler, invariants and model on the real Degenesis timeline (every coinflip day
///         after day 1 holds a stored result), plus `injectWidth`, which writes a tracked player's
///         auto-rebuy carry or claimableStored to within 1e30 of uint128 max (the model adopts the
///         value and books it as an injection). From there the campaign's wins, carry rides,
///         claims, carry claims, burns and transfers exercise the saturating clamps: the uint128
///         carry clamp after a win, claimableStored saturation, and FLIP's mint stopping at the
///         uint128 supply ceiling. Every step must still match the model exactly, and the paths
///         the model says cannot fail (claims, settles, affordable burns and transfers) must never
///         revert.
contract FlipCarryWidthsInvariant is FlipCarryDegenesisInvariant {
    function setUp() public override {
        super.setUp();
        h.enableWidthMode();
    }

    function _selectors() internal view override returns (bytes4[] memory s) {
        bytes4[] memory base = super._selectors();
        s = new bytes4[](base.length + 1);
        for (uint256 k; k < base.length; ++k) s[k] = base[k];
        s[base.length] = h.injectWidth.selector;
    }

    function _prefix() internal pure override returns (string memory) {
        return "FCW_";
    }

    /// @dev The width injection is required here as well; the clips it leads to are reported.
    function _required(uint256 k) internal pure override returns (bool) {
        return k == 29 || super._required(k);
    }
}
