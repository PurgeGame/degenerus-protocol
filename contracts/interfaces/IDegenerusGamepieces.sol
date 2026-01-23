// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IDegenerusGamepieces
/// @notice Interface for the ERC721 gamepiece NFT contract.
/// @dev Core NFT contract for the game's playable tokens with on-chain metadata generation.
interface IDegenerusGamepieces {
    /// @notice Get the total number of gamepieces purchased.
    /// @return Total purchase count across all players.
    function purchaseCount() external view returns (uint32);

    /// @notice Get purchase counts split by phase.
    /// @return prePurchase Count during pre-purchase phase.
    /// @return purchasePhase Count during main purchase phase.
    function purchaseCounts() external view returns (uint32 prePurchase, uint32 purchasePhase);

    /// @notice Process pending gamepiece mints for players (airdrop phase).
    /// @dev Uses VRF randomness to generate traits. Gas-bounded batch processing.
    /// @param playersToProcess Maximum number of players to process in this call.
    /// @param multiplier Airdrop multiplier (e.g., 10x for 10 gamepieces per purchase).
    /// @param rngWord VRF random word for trait generation.
    /// @return finished True if all pending mints are complete, false if more calls needed.
    function processPendingMints(
        uint32 playersToProcess,
        uint32 multiplier,
        uint256 rngWord
    ) external returns (bool finished);

    /// @notice Begin retiring tokens for the next level.
    /// @dev Base token ID advances during processDormant batches.
    function advanceBase() external;

    /// @notice Burn gamepieces on behalf of a player (decimator flow).
    /// @dev Access restricted to game contract only.
    /// @param owner The owner of the tokens to burn.
    /// @param tokenIds Array of token IDs to burn.
    function burnFromGame(address owner, uint256[] calldata tokenIds) external;

    /// @notice Get the current base token ID for this level.
    /// @return The base token ID (increments each level).
    function currentBaseTokenId() external view returns (uint256);

    /// @notice Get the number of pending gamepieces owed to a player.
    /// @param player The player to query.
    /// @return Number of gamepieces pending mint.
    function tokensOwed(address player) external view returns (uint32);

    /// @notice Process dormant tokens (burn events + base advancement).
    /// @dev Gas-bounded batch processing of retired tokens. Game-only.
    /// @param maxCount Maximum number of tokens to process.
    /// @return worked True if any work was done, false if nothing to process.
    function processDormant(uint32 maxCount) external returns (bool worked);

    /// @notice Queue reward gamepiece mints for a player (processed during advanceGame).
    /// @param player Address to receive the gamepieces.
    /// @param quantity Number of gamepieces to mint.
    function queueRewardMints(address player, uint32 quantity) external;

    /// @notice Queue reward mints for multiple players in a single call (gas optimization).
    /// @param buyers Array of player addresses.
    /// @param quantities Array of quantities (must match buyers length).
    function queueRewardMintsBatch(address[] calldata buyers, uint32[] calldata quantities) external;
}
