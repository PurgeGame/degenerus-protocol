// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

abstract contract GameJackpotEvents {
    event JackpotEthWin(uint32 indexed walletId, uint24 indexed level, uint16 indexed traitId,
        uint256 amount, uint256 entryIndex);
    event JackpotTicketWin(uint32 indexed walletId, uint24 indexed entryLevel, uint16 indexed traitId,
        uint32 entryCount, uint24 sourceLevel, uint256 entryIndex, bool roundedUp);
}
