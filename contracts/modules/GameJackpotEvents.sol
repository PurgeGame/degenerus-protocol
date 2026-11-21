// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

abstract contract GameJackpotEvents {
    /// @dev `entryIndex` is the winning entry's position in its trait bucket; `type(uint256).max`
    ///      marks a virtual deity entry. BAF awards carry trait 420 and entry index 0.
    event JackpotEthWin(uint32 indexed walletId, uint24 indexed level, uint16 indexed traitId,
        uint256 amount, uint256 entryIndex);
    event JackpotTicketWin(uint32 indexed walletId, uint24 indexed entryLevel, uint16 indexed traitId,
        uint32 entryCount, uint24 sourceLevel, uint256 entryIndex, bool roundedUp);
}
