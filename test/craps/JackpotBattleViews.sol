// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

interface IJackpotBattleViews {
    function payProgressive(
        CrapsBattleStorage.Window calldata w,
        uint256 peak,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord
    ) external;
}

/// @dev Test-only progressive award entry, guarded by the table's self-call.
abstract contract JackpotBattleViews is JackpotBattle {
    function payProgressive(
        Window calldata w,
        uint256 peak,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord
    ) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _jackpotPayProgressive(w, peak, score, winnerId, winnerWord);
    }
}
