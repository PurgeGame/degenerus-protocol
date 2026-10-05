// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

interface IJackpotBattleViews {
    function payProgressive(
        CrapsBattleStorage.Window calldata w,
        uint256 peak,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord,
        address winner
    ) external;
}

/// @title The cold module with the progressive award exposed
/// @dev Test-only. Production reaches `_payProgressive` from finalization alone; the suite drives
///      it directly through the table's self-call, so install this runtime over
///      `ContractAddresses.JACKPOT_BATTLE` with `vm.etch` before calling `payProgressiveAt`.
contract JackpotBattleViews is JackpotBattle {
    function payProgressive(
        Window calldata w,
        uint256 peak,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord,
        address winner
    ) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _payProgressive(w, peak, score, winnerId, winnerWord, winner);
    }
}
