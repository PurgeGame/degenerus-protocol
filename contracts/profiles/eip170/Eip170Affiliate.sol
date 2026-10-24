// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusAffiliate} from "../../DegenerusAffiliate.sol";

contract Eip170Affiliate is DegenerusAffiliate {
    constructor(address[] memory owners, bytes32[] memory codes, uint8[] memory kicks, address[] memory players, bytes32[] memory refs) DegenerusAffiliate(owners,codes,kicks,players,refs) {}
}
