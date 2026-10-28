// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameActionEntries} from "../../modules/GameActionEntries.sol";
import {GameBingoEntries} from "../../modules/GameBingoEntries.sol";
import {GameAllowanceEntries} from "../../modules/GameAllowanceEntries.sol";

contract Eip170Actions is GameActionEntries, GameBingoEntries, GameAllowanceEntries {

}
