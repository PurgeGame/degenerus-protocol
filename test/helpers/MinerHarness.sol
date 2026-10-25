// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameMiner, IMinerCrapsWork} from "../../contracts/modules/GameMiner.sol";

contract MinerHarness is GameMiner {
    function minerAction() external view returns (uint8) { return _minerAction(); }
    function playerActivityScoreCachedById_g975(uint32 id) external returns (uint256) { return _minerActivityById(id); }
    function playerActivityScoreCached(address player) external returns (uint256 score, uint32 id) { return _minerActivity(player); }
    function mineFlip(uint32 gasMultiplierBps) external { _mineFlip(gasMultiplierBps); }
}
