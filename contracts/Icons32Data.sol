// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {ContractAddresses} from "./ContractAddresses.sol";

/// @dev Governance executor check, as implemented by DegenerusVault.
interface IVaultOwnerCheck {
    function isVaultOwner(address account) external view returns (bool);
}

/*
+=======================================================================================================+
|                                         Icons32Data                                                   |
|                           On-Chain SVG Icon Path Storage for Degenerus                                |
+=======================================================================================================+
|                                                                                                       |
|  ARCHITECTURE OVERVIEW                                                                                |
|  ---------------------                                                                                |
|  Icons32Data is an on-chain storage contract for SVG icon fragments. It holds 33 icon                 |
|  paths representing the symbols used in Degenerus tokens and trophies.                                |
|  Data is mutable until finalize() is called, after which it becomes immutable.                        |
|                                                                                                       |
|  +--------------------------------------------------------------------------------------------------+ |
|  |                              ICON INDEX LAYOUT                                                   | |
|  |                                                                                                  | |
|  |   _paths[0-7]   -► Quadrant 0 (Crypto):   Bitcoin, Ethereum, Litecoin, etc.                      | |
|  |   _paths[8-15]  -► Quadrant 1 (Zodiac):   Aries, Taurus, Gemini, etc.                            | |
|  |   _paths[16-23] -► Quadrant 2 (Cards):    Horseshoe, King, Cashsack, Club, Diamond, Heart        | |
|  |                                      Spade, Ace                                                  | |
|  |   _paths[24-31] -► Quadrant 3 (Dice):     1-8                                                    | |
|  |   _paths[32]    -► Affiliate Badge:       Special icon for affiliate trophies                    | |
|  |                                                                                                  | |
|  |   _symQ1[0-7]   -► Crypto symbol names:   "Bitcoin", "Ethereum", etc.                            | |
|  |   _symQ2[0-7]   -► Zodiac symbol names:   "Aries", "Taurus", etc.                                | |
|  |   _symQ3[0-7]   -► Cards symbol names:    "Horseshoe", "King", "Cashsack", "Club",              | |
|  |                                      "Diamond", "Heart", "Spade", "Ace"                          | |
|  |   (Q4 Dice names are generated dynamically: "1", "2", etc.)                                      | |
|  +--------------------------------------------------------------------------------------------------+ |
|                                                                                                       |
|  DESIGN RATIONALE                                                                                     |
|  ----------------                                                                                     |
|  1. On-chain storage ensures token metadata remains available even if IPFS/centralized                |
|     servers become unavailable.                                                                       |
|  2. Batch initialization via setter functions allows data population within gas limits.               |
|  3. finalize() locks all data permanently, making it immutable after initialization.                  |
|  4. View functions allow efficient reading by renderers without state changes.                        |
|  5. SVG paths are stored as raw strings (not base64) to allow renderer flexibility.                   |
|                                                                                                       |
+=======================================================================================================+
|  SECURITY CONSIDERATIONS                                                                              |
|  -----------------------                                                                              |
|                                                                                                       |
|  1. FINALIZATION                                                                                      |
|     • Data can be modified by the vault owner until finalize() is called                              |
|     • After finalization, no data can be changed                                                      |
|     • finalize() can only be called once                                                              |
|                                                                                                       |
|  2. ACCESS CONTROL                                                                                    |
|     • Creator initializes each entry once; later writes require governance                             |
|     • View functions are publicly accessible                                                          |
|                                                                                                       |
|  3. BOUNDS CHECKING                                                                                   |
|     • setPaths() reverts if batch would exceed array bounds                                           |
|     • data(i) will revert if i >= 33 (array bounds)                                                   |
|     • symbol(q, idx) returns "" for quadrant >= 3 (idx never read); for quadrant 0-2 it reverts       |
|       on idx >= 8 (array bounds)                                                                      |
|                                                                                                       |
|  4. NO EXTERNAL CALLS                                                                                 |
|     • Reads are pure data storage; setters make one view call to the Vault to authorize               |
|     • Reads cannot be manipulated by external state changes                                           |
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
|  1. The vault owner provides valid SVG fragments before finalization                                  |
|  2. Fragment data does not contain malicious SVG (script injection, etc.)                             |
|  3. Symbol names are appropriate and accurate                                                         |
|                                                                                                       |
+=======================================================================================================+
*/

/// @title Icons32Data
/// @notice On-chain storage for Degenerus SVG icon paths and symbol names
/// @dev Data is mutable by the vault owner until finalize() is called, after which it becomes immutable
contract Icons32Data {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------

    /// @notice Thrown when caller lacks governance or initial icon setup authority
    error NotVaultOwner();

    /// @notice Thrown when attempting to modify data after finalize() has been called
    error AlreadyFinalized();

    /// @notice Thrown when batch size exceeds maximum of 10
    error MaxBatch();

    /// @notice Thrown when startIndex + paths.length would exceed array bounds (33)
    error IndexOutOfBounds();

    /// @notice Thrown when quadrant parameter is not 0, 1, or 2
    error InvalidQuadrant();

    // ---------------------------------------------------------------------
    // STORAGE
    // ---------------------------------------------------------------------

    /// @notice SVG fragments for 33 icons (32 quadrant symbols + 1 affiliate badge)
    /// @dev Each entry is a complete SVG fragment (groups, styles, transforms and shapes), not bare path data
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
    uint64 public initializedMask;
    uint64 public constant COMPLETE_MASK = (uint64(1) << 36) - 1;
    bool public bootstrapClosed;
    bool public immutable finalizeOnBootstrap;

    error InvalidInitialData();
    error AlreadyInitialized();
    event BootstrapClosed(bool finalized);

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------

    /// @notice Deploy contract for one-time batch initialization by the creator
    /// @dev Data must be populated via setter functions before finalization
    constructor(bool finalizeOnBootstrap_) {
        finalizeOnBootstrap = finalizeOnBootstrap_;
    }

    // ---------------------------------------------------------------------
    // INITIALIZATION FUNCTIONS (ONLY BEFORE FINALIZATION)
    // ---------------------------------------------------------------------

    /// @notice Set a batch of icon paths
    /// @dev Callable before finalization by the vault owner, and by the creator to initialize each entry
    ///      once until the bootstrap closes. Batch capped at 10 paths per call; path
    ///      strings are individually unbounded, so the caller still sizes the batch to fit gas.
    /// @param startIndex Starting index in _paths array (0-32)
    /// @param paths Array of SVG fragment strings to set (max 10)
    /// @custom:reverts NotVaultOwner When caller lacks governance or initial icon setup authority
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    /// @custom:reverts MaxBatch When paths.length > 10
    /// @custom:reverts IndexOutOfBounds When startIndex + paths.length > 33
    function setPaths(uint256 startIndex, string[] calldata paths) external {
        bool bootstrap = _authorizeWrite();
        if (paths.length > 10) revert MaxBatch();
        if (startIndex + paths.length > 33) revert IndexOutOfBounds();
        if (bootstrap && paths.length == 0) revert InvalidInitialData();

        for (uint256 i = 0; i < paths.length; ++i) {
            if (bootstrap) {
                uint64 bit = uint64(1) << (startIndex + i);
                if (initializedMask & bit != 0) revert AlreadyInitialized();
                if (bytes(paths[i]).length == 0) revert InvalidInitialData();
                initializedMask |= bit;
            }
            _paths[startIndex + i] = paths[i];
        }
        if (bootstrap) _finishBootstrap();
    }

    /// @notice Set symbol names for a quadrant
    /// @dev The creator initializes each quadrant once; governance may edit before finalization. Dice names are generated dynamically.
    /// @param quadrant Quadrant index (0=Crypto, 1=Zodiac, 2=Cards) — matches symbol() getter indexing
    /// @param symbols Array of 8 symbol names for the quadrant
    /// @custom:reverts NotVaultOwner When caller lacks governance or initial icon setup authority
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    /// @custom:reverts InvalidQuadrant When quadrant is not 0, 1, or 2
    function setSymbols(uint256 quadrant, string[8] calldata symbols) external {
        bool bootstrap = _authorizeWrite();
        if (quadrant > 2) revert InvalidQuadrant();
        if (bootstrap) {
            uint64 bit = uint64(1) << (33 + quadrant);
            if (initializedMask & bit != 0) revert AlreadyInitialized();
            for (uint256 i; i < 8; ++i) {
                if (bytes(symbols[i]).length == 0) revert InvalidInitialData();
            }
            initializedMask |= bit;
        }

        if (quadrant == 0) {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ1[i] = symbols[i];
            }
        } else if (quadrant == 1) {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ2[i] = symbols[i];
            }
        } else {
            for (uint256 i = 0; i < 8; ++i) {
                _symQ3[i] = symbols[i];
            }
        }
        if (bootstrap) _finishBootstrap();
    }

    /// @notice Finalize the contract, locking all data permanently
    /// @dev Only callable by the vault owner once. After this, no setter functions can be called.
    /// @custom:reverts NotVaultOwner When caller is not the DGVE governance executor
    /// @custom:reverts AlreadyFinalized When finalize() has already been called
    function finalize() external {
        if (!IVaultOwnerCheck(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        if (_finalized) revert AlreadyFinalized();
        _finalized = true;
        if (!bootstrapClosed) {
            bootstrapClosed = true;
            emit BootstrapClosed(true);
        }
    }

    function finalized() external view returns (bool) {
        return _finalized;
    }

    /// @dev Creator can populate each initial entry once. Governance takeover closes this route forever.
    function _authorizeWrite() private returns (bool bootstrap) {
        if (_finalized) revert AlreadyFinalized();
        if (!bootstrapClosed && msg.sender == ContractAddresses.CREATOR) return true;
        if (!IVaultOwnerCheck(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        if (!bootstrapClosed) {
            bootstrapClosed = true;
            emit BootstrapClosed(false);
        }
    }

    function _finishBootstrap() private {
        if (initializedMask == COMPLETE_MASK) {
            bootstrapClosed = true;
            _finalized = finalizeOnBootstrap;
            emit BootstrapClosed(_finalized);
        }
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS
    // ---------------------------------------------------------------------

    /// @notice Get the SVG fragment for an icon by index
    /// @dev Reverts with array out-of-bounds if index >= 33
    /// @param i Icon index: 0-31 for quadrant symbols, 32 for affiliate badge
    ///          Layout: i = (quadrant * 8) + symbolIndex
    /// @return The complete SVG fragment string for the icon
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
