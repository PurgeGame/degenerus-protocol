// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Test-only gated buffer takeover. Production applies the foil-backlog gate inline in the
///      ticket worker before `_prepareTicketLevelAfterFoil`; harnesses that drive storage
///      directly use this combined form.
abstract contract TicketLevelPrep is DegenerusGameStorage {
    /// @dev Constant work; pending paid obligations defer generation without clearing them.
    function _prepareTicketLevel(uint24 lvl) internal returns (bool) {
        uint24 old = _ticketBufferLevel(lvl);
        if (old != 0 && old != lvl && !gameOver && _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0
            && _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) == 0 && _foilDrainPending()) return false;
        return _prepareTicketLevelAfterFoil(lvl);
    }
}
