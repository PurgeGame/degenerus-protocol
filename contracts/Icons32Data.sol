// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";

/*
+=======================================================================================================+
|                                         Icons32Data                                                   |
|                           On-Chain SVG Icon Path Storage for Degenerus                                |
+=======================================================================================================+
|                                                                                                       |
|  ARCHITECTURE OVERVIEW                                                                                |
|  ---------------------                                                                                |
|  Icons32Data is an on-chain storage contract for SVG path data. It holds 33 icon                     |
|  paths representing the symbols used in Degenerus tokens and trophies.                                |
|  Data is mutable until finalize() is called, after which it becomes immutable.                        |
|                                                                                                       |
|  +--------------------------------------------------------------------------------------------------+ |
|  |                              ICON INDEX LAYOUT                                                   | |
|  |                                                                                                  | |
|  |   _paths[0-7]   -► Quadrant 0 (Crypto):   Bitcoin, Ethereum, Litecoin, etc.                     | |
|  |   _paths[8-15]  -► Quadrant 1 (Zodiac):   Aries, Taurus, Gemini, etc.                           | |
|  |   _paths[16-23] -► Quadrant 2 (Cards):    Horseshoe, King, Cashsack, Club, Diamond, Heart       | |
|  |                                      Spade, Ace                                                 | |
|  |   _paths[24-31] -► Quadrant 3 (Dice):     1-8                                                   | |
|  |   _paths[32]    -► Affiliate Badge:       Special icon for affiliate trophies                   | |
|  |                                                                                                  | |
|  |   _diamond      -► Flame icon:            Center glyph for all token renders                    | |
|  |                                                                                                  | |
|  |   _symQ1[0-7]   -► Crypto symbol names:   "Bitcoin", "Ethereum", etc.                           | |
|  |   _symQ2[0-7]   -► Zodiac symbol names:   "Aries", "Taurus", etc.                               | |
|  |   _symQ3[0-7]   -► Cards symbol names:    "Club", "Diamond", "Heart", "Spade",                  | |
|  |                                      "Horseshoe", "Cashsack", "King", "Ace"                    | |
|  |   (Q4 Dice names are generated dynamically: "1", "2", etc.)                                     | |
|  +--------------------------------------------------------------------------------------------------+ |
|                                                                                                       |
|  DESIGN RATIONALE                                                                                     |
|  ----------------                                                                                     |
|  1. On-chain storage ensures token metadata remains available even if IPFS/centralized              |
|     servers become unavailable.                                                                       |
|  2. Batch initialization via setter functions allows data population within gas limits.              |
|  3. finalize() locks all data permanently, making it immutable after initialization.                 |
|  4. View functions allow efficient reading by renderers without state changes.                       |
|  5. SVG paths are stored as raw strings (not base64) to allow renderer flexibility.                  |
|                                                                                                       |
+=======================================================================================================+
|  SECURITY CONSIDERATIONS                                                                              |
|  -----------------------                                                                              |
|                                                                                                       |
|  1. FINALIZATION                                                                                      |
|     • Data can be modified by CREATOR until finalize() is called                                      |
|     • After finalization, no data can be changed                                                      |
|     • finalize() can only be called once                                                              |
|                                                                                                       |
|  2. ACCESS CONTROL                                                                                    |
|     • Only ContractAddresses.CREATOR can call setter functions                                        |
|     • View functions are publicly accessible                                                          |
|                                                                                                       |
|  3. BOUNDS CHECKING                                                                                   |
|     • setPaths() reverts if batch would exceed array bounds                                           |
|     • data(i) will revert if i >= 33 (array bounds)                                                   |
|     • symbol(q, idx) returns "" for quadrant 3 or invalid quadrant; reverts for invalid idx          |
|                                                                                                       |
|  4. NO EXTERNAL CALLS                                                                                 |
|     • Pure data storage, no dependencies on other contracts (except ContractAddresses)                |
|     • Cannot be manipulated by external state changes                                                 |
|                                                                                                       |
|  5. GAS OPTIMIZATION                                                                                  |
|     • Batch size limited to 10 paths per call to stay under gas limits                                |
|     • View functions are free for off-chain calls                                                     |
|     • String data stored once, read many times                                                        |
|                                                                                                       |
+=======================================================================================================+
|  TRUST ASSUMPTIONS                                                                                    |
|  -----------------                                                                                    |
|                                                                                                       |
|  1. CREATOR provides valid SVG path data before finalization                                          |
|  2. Path data does not contain malicious SVG (script injection, etc.)                                 |
|  3. Symbol names are appropriate and accurate                                                         |
|                                                                                                       |
+=======================================================================================================+
*/

/// @title Icons32Data
/// @notice On-chain storage for Degenerus SVG icon paths and symbol names
/// @dev Data is mutable until finalize() is called by CREATOR, after which it becomes immutable
contract Icons32Data {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------

    /// @notice Thrown when caller is not ContractAddresses.CREATOR
    error OnlyCreator();

    /// @notice Thrown when attempting to modify data after finalize() has been called
    error AlreadyFinalized();

    /// @notice Thrown when batch size exceeds maximum of 10
    error MaxBatch();

    /// @notice Thrown when startIndex + paths.length would exceed array bounds (33)
    error IndexOutOfBounds();

    /// @notice Thrown when quadrant parameter is not 1, 2, or 3
    error InvalidQuadrant();

    // ---------------------------------------------------------------------
    // STORAGE
    // ---------------------------------------------------------------------

    /// @notice SVG path data for 33 icons (32 quadrant symbols + 1 affiliate badge)
    /// @dev Each path is the "d" attribute content for an SVG <path> element
    string[33] private _paths;

    /// @notice Human-readable symbol names for Quadrant 0 (Crypto)
    /// @dev Examples: "Bitcoin", "Ethereum", "Dogecoin", "Solana"
    string[8] private _symQ1;

    /// @notice Human-readable symbol names for Quadrant 1 (Zodiac)
    /// @dev Examples: "Aries", "Taurus", "Gemini", "Cancer"
    string[8] private _symQ2;

    /// @notice Human-readable symbol names for Quadrant 2 (Cards)
    /// @dev Examples: "Horseshoe", "King", "Cashsack", "Club", "Diamond", "Heart", "Spade", "Ace"
    string[8] private _symQ3;

    /// @notice Flag indicating whether data has been locked permanently
    /// @dev Once true, no setter functions can be called
    bool private _finalized;

    // Note: Quadrant 3 (Dice) names are generated dynamically as "1" through "8"

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------

    /// @notice Deploy contract for batch initialization by CREATOR
    /// @dev Data must be populated via setter functions before finalization
    constructor() {}

    // ---------------------------------------------------------------------
    // INITIALIZATION FUNCTIONS (ONLY BEFORE FINALIZATION)
    // ---------------------------------------------------------------------

    /// @notice Set a batch of icon paths
    /// @dev Only callable by CREATOR before finalization. Max 10 paths per call to stay under gas limits.
    /// @param startIndex Starting index in _paths array (0-32)
    /// @param paths Array of SVG path strings to set (max 10)
    /// @custom:reverts OnlyCreator When caller is not ContractAddresses.CREATOR
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    /// @custom:reverts MaxBatch When paths.length > 10
    /// @custom:reverts IndexOutOfBounds When startIndex + paths.length > 33
    function setPaths(uint256 startIndex, string[] calldata paths) external {
        if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();
        if (_finalized) revert AlreadyFinalized();
        if (paths.length > 10) revert MaxBatch();
        if (startIndex + paths.length > 33) revert IndexOutOfBounds();

        for (uint256 i = 0; i < paths.length; ++i) {
            _paths[startIndex + i] = paths[i];
        }
    }

    /// @notice Set symbol names for a quadrant
    /// @dev Only callable by CREATOR before finalization. Quadrant 0 (Dice) names are generated dynamically.
    /// @param quadrant Quadrant number (1=Crypto, 2=Zodiac, 3=Cards)
    /// @param symbols Array of 8 symbol names for the quadrant
    /// @custom:reverts OnlyCreator When caller is not ContractAddresses.CREATOR
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    /// @custom:reverts InvalidQuadrant When quadrant is not 1, 2, or 3
    function setSymbols(uint256 quadrant, string[8] memory symbols) external {
        if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();
        if (_finalized) revert AlreadyFinalized();

        if (quadrant == 1) {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ1[i] = symbols[i];
            }
        } else if (quadrant == 2) {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ2[i] = symbols[i];
            }
        } else if (quadrant == 3) {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ3[i] = symbols[i];
            }
        } else {
            revert InvalidQuadrant();
        }
    }

    /// @notice Finalize the contract, locking all data permanently
    /// @dev Only callable by CREATOR once. After this, no setter functions can be called.
    /// @custom:reverts OnlyCreator When caller is not ContractAddresses.CREATOR
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    function finalize() external {
        if (msg.sender != ContractAddresses.CREATOR) revert OnlyCreator();
        if (_finalized) revert AlreadyFinalized();
        _finalized = true;
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS
    // ---------------------------------------------------------------------

    /// @notice Get the SVG path data for an icon by index
    /// @dev Reverts with array out-of-bounds if index >= 33
    /// @param i Icon index: 0-31 for quadrant symbols, 32 for affiliate badge
    ///          Layout: i = (quadrant * 8) + symbolIndex
    /// @return The SVG path "d" attribute string for the icon
    function data(uint256 i) external view returns (string memory) {
        return _paths[i];
    }

    /// @notice Get the human-readable name for a symbol
    /// @dev Quadrant 3 (Dice) returns empty string; renderer generates "1..8" dynamically.
    ///      Will revert with array out-of-bounds if idx >= 8 for quadrants 0-2.
    /// @param quadrant Quadrant index: 0=Crypto, 1=Zodiac, 2=Cards, 3=Dice
    /// @param idx Symbol index within the quadrant (0-7)
    /// @return The symbol name, or empty string if quadrant >= 3
    function symbol(uint256 quadrant, uint8 idx) external view returns (string memory) {
        if (quadrant == 0) return _symQ1[idx];
        if (quadrant == 1) return _symQ2[idx];
        if (quadrant == 2) return _symQ3[idx];
        // Quadrant 3 (Dice) names are generated by the renderer as "1..8"
        return "";
    }
}
