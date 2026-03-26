// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";

/// @notice Minimal interface for sDGNRS balance/supply snapshots
interface ISDGNRSSnapshot {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal interface for DegenerusGame donation-facing functions
interface IDegenerusGameDonations {
    function claimWinnings(address player) external;
    function claimableWinningsOf(address player) external view returns (uint256);
    function gameOver() external view returns (bool);
}

/// @notice Minimal interface for DegenerusVault owner check
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/**
 * @title DegenerusDonations (GNRUS)
 * @notice Soulbound GNRUS token with proportional burn-for-ETH/stETH redemption
 *         and per-level sDGNRS-weighted governance controlling GNRUS distribution.
 * @dev GNRUS is minted entirely to this contract at deploy. Each level, the winning
 *      governance proposal's recipient receives 2% of the remaining unallocated GNRUS.
 *      GNRUS holders can burn tokens to redeem a proportional share of both ETH and stETH
 *      held by this contract. Funding arrives via game distributions (Phase 124 wiring).
 *
 * ARCHITECTURE:
 * - 1T GNRUS minted to address(this) at deploy (unallocated pool)
 * - Each level, governance distributes 2% of remaining unallocated GNRUS to winning recipient
 * - GNRUS holders burn tokens to claim proportional ETH + stETH
 * - At GAMEOVER: all unallocated GNRUS burned, game pushes final ETH/stETH
 * - Soulbound: transfer, transferFrom, approve all revert
 */
contract GNRUS {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();

    /// @notice Thrown when transfer, transferFrom, or approve is called (soulbound)
    error TransferDisabled();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when ETH or stETH transfer fails
    error TransferFailed();

    /// @notice Thrown when burn amount is 0 or below minimum
    error InsufficientBurn();

    /// @notice Thrown when creator exceeds 5 proposals per level
    error ProposalLimitReached();

    /// @notice Thrown when proposer is below 0.5% sDGNRS threshold
    error InsufficientStake();

    /// @notice Thrown when proposer has already submitted this level
    error AlreadyProposed();

    /// @notice Thrown when voter has already voted on this proposal
    error AlreadyVoted();

    /// @notice Thrown when proposal index is out of range
    error InvalidProposal();

    /// @notice Thrown when pickCharity is called twice for the same level
    error LevelAlreadyResolved();

    /// @notice Thrown when voting or proposing for a non-current level
    error LevelNotActive();

    /// @notice Thrown when recipient is a contract (GNRUS would be stuck)
    error RecipientIsContract();

    /// @notice Thrown when game is not in gameover state
    error GameNotOver();

    /// @notice Thrown when burnAtGameOver has already been called
    error AlreadyFinalized();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted on mint, burn, and governance distribution (indexer compat)
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when GNRUS is burned for proportional ETH + stETH
    event Burn(address indexed burner, uint256 gnrusAmount, uint256 ethOut, uint256 stethOut);

    /// @notice Emitted when a new proposal is created for the current level
    event ProposalCreated(uint24 indexed level, uint48 indexed proposalId, address indexed proposer, address recipient);

    /// @notice Emitted when a vote is cast on a proposal
    event Voted(uint24 indexed level, uint48 indexed proposalId, address indexed voter, bool approve, uint256 weight);

    /// @notice Emitted when a level resolves with a winning proposal
    event LevelResolved(uint24 indexed level, uint48 indexed winningProposalId, address recipient, uint256 gnrusDistributed);

    /// @notice Emitted when a level resolves with no eligible winner
    event LevelSkipped(uint24 indexed level);

    /// @notice Emitted when gameover finalization burns unallocated GNRUS and claims winnings
    event GameOverFinalized(uint256 gnrusBurned, uint256 ethClaimed, uint256 stethClaimed);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "GNRUS Donations";

    /// @notice Token symbol
    string public constant symbol = "GNRUS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of GNRUS tokens
    uint256 public totalSupply;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

    // =====================================================================
    //                      GOVERNANCE STRUCTS & STATE
    // =====================================================================

    /// @notice A governance proposal for GNRUS distribution
    struct Proposal {
        address recipient;       // 20 bytes ┐
        uint48  approveWeight;   //  6 bytes ├─ slot 0 (32 bytes exact)
        uint48  rejectWeight;    //  6 bytes ┘
        address proposer;        // 20 bytes ── slot 1 (12 bytes free)
    }
    // Weights stored as whole tokens (/ 1e18). uint48 max ~2.8e14, sDGNRS supply ~1e12 = 281× headroom.

    /// @notice Current governance level (incremented by pickCharity)
    uint24 public currentLevel;

    /// @notice Total proposals ever created (global counter)
    uint48 public proposalCount;

    /// @notice Whether burnAtGameOver has been called
    bool public finalized;

    // ^ currentLevel (3) + proposalCount (6) + finalized (1) = 10 bytes, one slot

    /// @notice Proposal storage by global ID
    mapping(uint48 => Proposal) public proposals;

    /// @notice First proposalId for a given level
    mapping(uint24 => uint48) public levelProposalStart;

    /// @notice Number of proposals for a given level
    mapping(uint24 => uint8) public levelProposalCount;

    /// @notice Whether pickCharity has been called for a given level
    mapping(uint24 => bool) public levelResolved;

    /// @notice Whether an address has already proposed for a given level
    mapping(uint24 => mapping(address => bool)) public hasProposed;

    /// @notice Creator proposal count per level (max 5)
    mapping(uint24 => uint8) public creatorProposalCount;

    /// @notice Whether a voter has already voted on a specific proposal in a given level
    mapping(uint24 => mapping(address => mapping(uint48 => bool))) public hasVoted;

    /// @notice sDGNRS total supply snapshot at level start (set on first proposal)
    mapping(uint24 => uint128) public levelSdgnrsSnapshot;

    /// @notice Vault owner address snapshot at level start (set on first proposal)
    mapping(uint24 => address) public levelVaultOwner;

    // =====================================================================
    //                            CONSTANTS
    // =====================================================================

    /// @notice Initial GNRUS supply: 1 trillion tokens
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @notice Minimum burn amount: 1 GNRUS
    uint256 private constant MIN_BURN = 1e18;

    /// @notice Distribution per level: 2% of remaining unallocated GNRUS
    uint16 private constant DISTRIBUTION_BPS = 200;

    /// @notice BPS denominator
    uint16 private constant BPS_DENOM = 10_000;

    /// @notice Minimum sDGNRS stake to propose: 0.5% of snapshot supply
    uint16 private constant PROPOSE_THRESHOLD_BPS = 50;

    /// @notice VAULT standing vote weight: 5% of snapshot supply
    uint16 private constant VAULT_VOTE_BPS = 500;

    /// @notice Maximum proposals creator can submit per level
    uint8 private constant MAX_CREATOR_PROPOSALS = 5;

    // =====================================================================
    //                       IMMUTABLE REFERENCES
    // =====================================================================

    /// @dev stETH token for proportional redemption on burn
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @dev sDGNRS token for governance vote weight snapshots
    ISDGNRSSnapshot private constant sdgnrs = ISDGNRSSnapshot(ContractAddresses.SDGNRS);

    /// @dev Game contract for gameOver checks
    IDegenerusGameDonations private constant game = IDegenerusGameDonations(ContractAddresses.GAME);

    /// @dev Vault contract for owner (>50.1% DGVE) checks
    IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);

    // =====================================================================
    //                            MODIFIERS
    // =====================================================================

    /// @notice Restricts access to the game contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    // =====================================================================
    //                           CONSTRUCTOR
    // =====================================================================

    /// @notice Deploys GNRUS with 1T supply minted to the contract itself (unallocated pool)
    constructor() {
        _mint(address(this), INITIAL_SUPPLY);
    }

    // =====================================================================
    //                      SOULBOUND ENFORCEMENT
    // =====================================================================

    /// @notice Disabled -- GNRUS is soulbound
    function transfer(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    /// @notice Disabled -- GNRUS is soulbound
    function transferFrom(address, address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    /// @notice Disabled -- GNRUS is soulbound
    function approve(address, uint256) external pure returns (bool) { revert TransferDisabled(); }

    // =====================================================================
    //                       BURN-FOR-REDEMPTION
    // =====================================================================

    /// @notice Burn GNRUS to receive proportional ETH and stETH
    /// @dev Burns `amount` GNRUS from msg.sender and transfers proportional shares of
    ///      both ETH and stETH held by this contract. Last-holder sweep: if the caller's
    ///      entire balance equals `amount` or all non-contract GNRUS equals `amount`,
    ///      sweeps the full caller balance to avoid dust.
    ///      CEI: state updates and events before external transfers. stETH before ETH (ETH last).
    /// @param amount Amount of GNRUS to burn (minimum 1 GNRUS)
    function burn(uint256 amount) external {
        if (amount < MIN_BURN) revert InsufficientBurn();

        uint256 supply = totalSupply;
        address burner = msg.sender;
        uint256 burnerBal = balanceOf[burner];

        // Last-holder sweep: if burning all remaining non-contract balance,
        // use the full balance even if slightly above `amount`
        if (burnerBal == amount || (supply - balanceOf[address(this)]) == amount) {
            amount = burnerBal; // sweep
        }

        // Calculate owed from total backing (on-hand + claimable)
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimable = game.claimableWinningsOf(address(this));
        if (claimable > 1) { unchecked { claimable -= 1; } } else { claimable = 0; }

        uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;

        // Pay from on-hand first (ETH-preferred), pull remainder from game
        uint256 onHand = ethBal + stethBal;
        if (owed > onHand) {
            game.claimWinnings(address(this));
            ethBal = address(this).balance;
            stethBal = steth.balanceOf(address(this));
        }

        uint256 ethOut = owed <= ethBal ? owed : ethBal;
        uint256 stethOut = owed - ethOut;

        // CEI: burn tokens before external transfers
        balanceOf[burner] -= amount; // reverts on underflow via Solidity 0.8
        unchecked { totalSupply = supply - amount; }

        emit Transfer(burner, address(0), amount);
        emit Burn(burner, amount, ethOut, stethOut);

        // stETH transfer first (ERC20), ETH transfer last (raw call — CEI)
        if (stethOut != 0) {
            if (!steth.transfer(burner, stethOut)) revert TransferFailed();
        }
        if (ethOut != 0) {
            (bool ok,) = burner.call{value: ethOut}("");
            if (!ok) revert TransferFailed();
        }
    }

    // =====================================================================
    //                        GAMEOVER HANDLING
    // =====================================================================

    /// @notice Finalize at gameover: burn all remaining unallocated GNRUS
    /// @dev Only callable by the game contract. Can only be called once.
    ///      The game contract pushes final ETH/stETH to VAULT, DGNRS, and GNRUS
    ///      during gameover processing. This function handles the GNRUS-side cleanup
    ///      of burning unallocated tokens.
    function burnAtGameOver() external onlyGame {
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        uint256 unallocated = balanceOf[address(this)];
        if (unallocated != 0) {
            balanceOf[address(this)] = 0;
            unchecked { totalSupply -= unallocated; }
            emit Transfer(address(this), address(0), unallocated);
        }

        emit GameOverFinalized(unallocated, 0, 0);
    }

    // =====================================================================
    //                      GOVERNANCE -- PROPOSE
    // =====================================================================

    /// @notice Create a proposal for the current governance level
    /// @dev Any sDGNRS holder with >= 0.5% of snapshot supply can propose once per level.
    ///      The vault owner (>50.1% DGVE) can submit up to 5 proposals per level.
    ///      The first proposal of a level snapshots the sDGNRS total supply.
    /// @param recipient Donation wallet address that will receive GNRUS if this proposal wins
    /// @return proposalId The global ID of the created proposal
    function propose(address recipient) external returns (uint48 proposalId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (recipient.code.length != 0) revert RecipientIsContract();
        uint24 level = currentLevel;

        // Snapshot sDGNRS supply on first proposal of this level
        if (levelProposalCount[level] == 0) {
            levelSdgnrsSnapshot[level] = uint128(sdgnrs.totalSupply());
        }

        address proposer = msg.sender;
        uint128 snapshot = levelSdgnrsSnapshot[level];

        if (vault.isVaultOwner(proposer)) {
            // Snapshot vault owner on first vault-owner action
            if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = proposer;
            if (creatorProposalCount[level] >= MAX_CREATOR_PROPOSALS) revert ProposalLimitReached();
            creatorProposalCount[level]++;
        } else {
            // Community: 0.5% sDGNRS threshold, once per level
            if (sdgnrs.balanceOf(proposer) * BPS_DENOM < uint256(snapshot) * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();
            if (hasProposed[level][proposer]) revert AlreadyProposed();
            hasProposed[level][proposer] = true;
        }

        proposalId = proposalCount++;
        if (levelProposalCount[level] == 0) {
            levelProposalStart[level] = proposalId;
        }
        levelProposalCount[level]++;

        proposals[proposalId] = Proposal({
            recipient: recipient,
            proposer: proposer,
            approveWeight: 0,
            rejectWeight: 0
        });

        emit ProposalCreated(level, proposalId, proposer, recipient);
    }

    // =====================================================================
    //                        GOVERNANCE -- VOTE
    // =====================================================================

    /// @notice Cast an approve or reject vote on a proposal for the current level
    /// @dev Vote weight equals the voter's sDGNRS balance, except the vault owner
    ///      (>50.1% DGVE) whose weight is fixed at 5% of the sDGNRS snapshot.
    ///      Voters can vote on every proposal independently but only once per proposal per level.
    /// @param proposalId The global proposal ID to vote on
    /// @param approveVote True to approve, false to reject
    function vote(uint48 proposalId, bool approveVote) external {
        uint24 level = currentLevel;
        uint48 start = levelProposalStart[level];
        uint8 count = levelProposalCount[level];
        if (count == 0 || proposalId < start || proposalId >= start + count) revert InvalidProposal();

        address voter = msg.sender;
        if (hasVoted[level][voter][proposalId]) revert AlreadyVoted();
        hasVoted[level][voter][proposalId] = true;

        uint48 weight = uint48(sdgnrs.balanceOf(voter) / 1e18);
        // Vault owner bonus: 5% of snapshot per proposal. Snapshot locks on first vault-owner action.
        if (voter == levelVaultOwner[level] || (levelVaultOwner[level] == address(0) && vault.isVaultOwner(voter))) {
            if (levelVaultOwner[level] == address(0)) levelVaultOwner[level] = voter;
            weight += uint48((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / (BPS_DENOM * 1e18));
        }
        if (weight == 0) revert InsufficientStake();

        if (approveVote) {
            proposals[proposalId].approveWeight += weight;
        } else {
            proposals[proposalId].rejectWeight += weight;
        }

        emit Voted(level, proposalId, voter, approveVote, weight);
    }

    // =====================================================================
    //                    GOVERNANCE -- RESOLVE LEVEL
    // =====================================================================

    /// @notice Pick the winning charity for the current level, distributing 2% of unallocated
    ///         GNRUS to the winning proposal's recipient. Called by the game on level transition.
    /// @dev Winner is the proposal with the highest positive net weight (approve - reject).
    ///      Ties broken by first-submitted. If no proposals exist or all are net-negative,
    ///      the level is skipped.
    /// @param level The level to resolve (must equal currentLevel)
    function pickCharity(uint24 level) external onlyGame {
        if (level != currentLevel) revert LevelNotActive();
        if (levelResolved[level]) revert LevelAlreadyResolved();
        levelResolved[level] = true;

        // Advance to next level
        currentLevel = level + 1;

        uint8 count = levelProposalCount[level];

        // If no proposals, skip
        if (count == 0) {
            emit LevelSkipped(level);
            return;
        }

        uint48 start = levelProposalStart[level];

        // Find winner: highest net weight (approve - reject), must be positive
        uint48 bestId = type(uint48).max;
        int256 bestNet = 0; // must be > 0 to win

        for (uint8 i = 0; i < count;) {
            Proposal storage p = proposals[start + i];
            int256 net = int256(uint256(p.approveWeight)) - int256(uint256(p.rejectWeight));
            if (net > bestNet) {
                bestNet = net;
                bestId = start + uint48(i);
            }
            unchecked { ++i; }
        }

        // All proposals net-negative or zero => skip
        if (bestId == type(uint48).max) {
            emit LevelSkipped(level);
            return;
        }

        // Distribute 2% of remaining unallocated GNRUS
        uint256 unallocated = balanceOf[address(this)];
        uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;

        if (distribution == 0) {
            emit LevelSkipped(level);
            return;
        }

        address recipient = proposals[bestId].recipient;

        // Transfer from contract's unallocated pool to recipient
        unchecked {
            balanceOf[address(this)] = unallocated - distribution;
            balanceOf[recipient] += distribution;
        }
        emit Transfer(address(this), recipient, distribution);
        emit LevelResolved(level, bestId, recipient, distribution);
    }

    // =====================================================================
    //                         RECEIVE FUNCTION
    // =====================================================================

    /// @notice Accept ETH from game claimWinnings and direct deposits
    receive() external payable {}

    // =====================================================================
    //                          VIEW HELPERS
    // =====================================================================

    /// @notice Get proposal details by global ID
    function getProposal(uint48 proposalId) external view returns (
        address recipient, address proposer, uint48 approveWeight, uint48 rejectWeight
    ) {
        Proposal storage p = proposals[proposalId];
        return (p.recipient, p.proposer, p.approveWeight, p.rejectWeight);
    }

    /// @notice Get the proposal range for a given level
    function getLevelProposals(uint24 level) external view returns (uint48 start, uint8 count) {
        return (levelProposalStart[level], levelProposalCount[level]);
    }

    // =====================================================================
    //                           PRIVATE
    // =====================================================================

    /// @dev Mint GNRUS tokens to an address
    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }
}
