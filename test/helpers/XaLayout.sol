// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";

/// @dev Layout probe for scripts/layout/check_peripheral_layouts.py: the compiler reports a
///      namespaced struct's member slots only when it is declared as a state variable.
contract XaAffiliateLayout {
    DegenerusAffiliate.DegenerusAffiliateStorage internal probe;
}
