// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";

/// @notice Minimal interface for sDGNRS balance/supply snapshots
interface ISDGNRSSnapshot {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal interface for DegenerusGame charity-facing functions
interface IDegenerusGameCharity {
    function claimWinnings(address player) external;
    function claimableWinningsOf(address player) external view returns (uint256);
}

/**
 * @title DegenerusCharity (GNRUS)
 * @notice Soulbound GNRUS token with proportional burn-for-ETH/stETH redemption
 *         and per-level sDGNRS-weighted governance controlling GNRUS distribution.
 * @dev GNRUS is minted entirely to this contract at deploy. Each level, the winning
 *      governance proposal's recipient receives 2% of the remaining unallocated GNRUS.
 *      GNRUS holders can burn tokens to redeem a proportional share of both ETH and stETH
 *      held by this contract. Funding arrives via claimYield() pulling from the game's
 *      claimable winnings, or via direct ETH/stETH deposits.
 *
 * ARCHITECTURE:
 * - 1T GNRUS minted to address(this) at deploy (unallocated pool)
 * - Each level, governance distributes 2% of remaining unallocated GNRUS to winning recipient
 * - GNRUS holders burn tokens to claim proportional ETH + stETH
 * - claimYield() pulls accumulated game winnings into this contract
 * - Soulbound: transfer, transferFrom, approve all revert
 */
contract DegenerusCharity {
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

    /// @notice Thrown when resolveLevel is called with no eligible winner
    error NoProposalsToResolve();

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

    /// @notice Thrown when resolveLevel is called twice for the same level
    error LevelAlreadyResolved();

    /// @notice Thrown when voting or proposing for a non-current level
    error LevelNotActive();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted on mint, burn, and governance distribution (indexer compat)
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of GNRUS transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when GNRUS is burned for proportional ETH + stETH
    /// @param burner Address that burned tokens
    /// @param gnrusAmount Amount of GNRUS burned
    /// @param ethOut ETH received
    /// @param stethOut stETH received
    event Burn(address indexed burner, uint256 gnrusAmount, uint256 ethOut, uint256 stethOut);

    /// @notice Emitted when yield is claimed from the game contract
    /// @param ethAmount ETH gained from claim
    /// @param stethAmount stETH gained from claim
    event YieldClaimed(uint256 ethAmount, uint256 stethAmount);

    /// @notice Emitted when a new proposal is created for the current level
    /// @param level Governance level
    /// @param proposalId Global proposal ID
    /// @param proposer Address that created the proposal
    /// @param recipient Charity wallet that will receive GNRUS if this proposal wins
    event ProposalCreated(uint24 indexed level, uint256 indexed proposalId, address indexed proposer, address recipient);

    /// @notice Emitted when a vote is cast on a proposal
    /// @param level Governance level
    /// @param proposalId Global proposal ID
    /// @param voter Address that voted
    /// @param approve True for approve, false for reject
    /// @param weight Vote weight (sDGNRS balance at time of vote)
    event Voted(uint24 indexed level, uint256 indexed proposalId, address indexed voter, bool approve, uint256 weight);

    /// @notice Emitted when a level resolves with a winning proposal
    /// @param level Governance level
    /// @param winningProposalId Winning proposal's global ID
    /// @param recipient Address receiving the GNRUS distribution
    /// @param gnrusDistributed Amount of GNRUS distributed
    event LevelResolved(uint24 indexed level, uint256 indexed winningProposalId, address recipient, uint256 gnrusDistributed);

    /// @notice Emitted when a level resolves with no eligible winner
    /// @param level Governance level that was skipped
    event LevelSkipped(uint24 indexed level);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Degenerus Charity";

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
        address recipient;       // charity wallet receiving GNRUS if this wins
        address proposer;        // who created the proposal
        uint256 approveWeight;   // cumulative approve vote weight
        uint256 rejectWeight;    // cumulative reject vote weight
    }

    /// @notice Current governance level (incremented by resolveLevel)
    uint24 public currentLevel;

    /// @notice Total proposals ever created (global counter)
    uint256 public proposalCount;

    /// @notice Proposal storage by global ID
    mapping(uint256 => Proposal) public proposals;

    /// @notice First proposalId for a given level
    mapping(uint24 => uint256) public levelProposalStart;

    /// @notice Number of proposals for a given level
    mapping(uint24 => uint256) public levelProposalCount;

    /// @notice Whether resolveLevel has been called for a given level
    mapping(uint24 => bool) public levelResolved;

    /// @notice Whether an address has already proposed for a given level
    mapping(uint24 => mapping(address => bool)) public hasProposed;

    /// @notice Creator proposal count per level (max 5)
    mapping(uint24 => uint256) public creatorProposalCount;

    /// @notice Whether a voter has already voted on a specific proposal in a given level
    mapping(uint24 => mapping(address => mapping(uint256 => bool))) public hasVoted;

    /// @notice sDGNRS total supply snapshot at level start (set on first proposal)
    mapping(uint24 => uint256) public levelSdgnrsSnapshot;

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

    /// @dev Game contract for claimYield pull
    IDegenerusGameCharity private constant game = IDegenerusGameCharity(ContractAddresses.GAME);

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

        // Proportional share of BOTH assets
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));

        uint256 ethOut = (ethBal * amount) / supply;
        uint256 stethOut = (stethBal * amount) / supply;

        // Burn tokens (reverts on underflow via Solidity 0.8)
        balanceOf[burner] -= amount;
        unchecked { totalSupply = supply - amount; }

        emit Transfer(burner, address(0), amount);
        emit Burn(burner, amount, ethOut, stethOut);

        // Transfer ETH
        if (ethOut != 0) {
            (bool ok,) = burner.call{value: ethOut}("");
            if (!ok) revert TransferFailed();
        }
        // Transfer stETH
        if (stethOut != 0) {
            if (!steth.transfer(burner, stethOut)) revert TransferFailed();
        }
    }

    // =====================================================================
    //                           YIELD PULL
    // =====================================================================

    /// @notice Pull accumulated ETH/stETH winnings from the game contract
    /// @dev Permissionless -- anyone can trigger the yield claim. Emits YieldClaimed
    ///      only if new assets were received.
    function claimYield() external {
        uint256 ethBefore = address(this).balance;
        uint256 stethBefore = steth.balanceOf(address(this));

        game.claimWinnings(address(this));

        uint256 ethGained = address(this).balance - ethBefore;
        uint256 stethGained = steth.balanceOf(address(this)) - stethBefore;

        if (ethGained != 0 || stethGained != 0) {
            emit YieldClaimed(ethGained, stethGained);
        }
    }

    // =====================================================================
    //                      GOVERNANCE -- PROPOSE
    // =====================================================================

    /// @notice Create a proposal for the current governance level
    /// @dev Creator (CREATOR address) can submit up to 5 proposals per level.
    ///      Other proposers need >= 0.5% of sDGNRS snapshot supply and can propose once per level.
    ///      The first proposal of a level snapshots the sDGNRS total supply.
    /// @param recipient Charity wallet address that will receive GNRUS if this proposal wins
    /// @return proposalId The global ID of the created proposal
    function propose(address recipient) external returns (uint256 proposalId) {
        if (recipient == address(0)) revert ZeroAddress();
        uint24 level = currentLevel;

        // Snapshot sDGNRS supply on first proposal of this level
        if (levelProposalCount[level] == 0) {
            levelSdgnrsSnapshot[level] = sdgnrs.totalSupply();
        }

        address proposer = msg.sender;
        uint256 snapshot = levelSdgnrsSnapshot[level];

        if (proposer == ContractAddresses.CREATOR) {
            if (creatorProposalCount[level] >= MAX_CREATOR_PROPOSALS) revert ProposalLimitReached();
            creatorProposalCount[level]++;
        } else {
            // 0.5% threshold check
            if (sdgnrs.balanceOf(proposer) * BPS_DENOM < snapshot * PROPOSE_THRESHOLD_BPS) revert InsufficientStake();
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
    /// @dev Vote weight equals the voter's current sDGNRS balance. Voters can vote on
    ///      every proposal independently but only once per proposal per level.
    /// @param proposalId The global proposal ID to vote on
    /// @param approveVote True to approve, false to reject
    function vote(uint256 proposalId, bool approveVote) external {
        uint24 level = currentLevel;
        uint256 start = levelProposalStart[level];
        uint256 count = levelProposalCount[level];
        if (count == 0 || proposalId < start || proposalId >= start + count) revert InvalidProposal();

        address voter = msg.sender;
        if (hasVoted[level][voter][proposalId]) revert AlreadyVoted();
        hasVoted[level][voter][proposalId] = true;

        uint256 weight = sdgnrs.balanceOf(voter);
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

    /// @notice Resolve the current governance level, distributing 2% of unallocated GNRUS
    ///         to the winning proposal's recipient
    /// @dev In Phase 123, anyone can call. Phase 124 wires game-only access via onlyGame.
    ///      VAULT gets a standing 5% approve vote on every proposal. Winner is the proposal
    ///      with the highest positive net weight (approve - reject). Ties broken by first-submitted.
    ///      If no proposals exist or all are net-negative, the level is skipped.
    /// @param level The level to resolve (must equal currentLevel)
    function resolveLevel(uint24 level) external {
        // Per D-12: in Phase 123, anyone can call. Phase 124 wires game-only access.
        if (level != currentLevel) revert LevelNotActive();
        if (levelResolved[level]) revert LevelAlreadyResolved();
        levelResolved[level] = true;

        // Advance to next level
        currentLevel = level + 1;

        uint256 count = levelProposalCount[level];

        // If no proposals, skip
        if (count == 0) {
            emit LevelSkipped(level);
            return;
        }

        uint256 start = levelProposalStart[level];

        // Add VAULT standing vote: 5% of snapshot on every proposal as approve
        {
            uint256 snapshot = levelSdgnrsSnapshot[level];
            uint256 vaultWeight = (snapshot * VAULT_VOTE_BPS) / BPS_DENOM;
            if (vaultWeight != 0) {
                for (uint256 i = 0; i < count;) {
                    proposals[start + i].approveWeight += vaultWeight;
                    unchecked { ++i; }
                }
            }
        }

        // Find winner: highest net weight (approve - reject), must be positive
        uint256 bestId = type(uint256).max;
        int256 bestNet = 0; // must be > 0 to win

        for (uint256 i = 0; i < count;) {
            Proposal storage p = proposals[start + i];
            int256 net = int256(p.approveWeight) - int256(p.rejectWeight);
            if (net > bestNet) {
                bestNet = net;
                bestId = start + i;
            }
            // Per D-10: ties use first-submitted as tiebreaker (lower proposalId wins).
            // bestId already holds the lower index, so no change needed on tie.
            unchecked { ++i; }
        }

        // All proposals net-negative or zero => skip
        if (bestId == type(uint256).max) {
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
    /// @param proposalId The global proposal ID
    /// @return recipient Charity wallet address
    /// @return proposer Who created the proposal
    /// @return approveWeight Cumulative approve vote weight
    /// @return rejectWeight Cumulative reject vote weight
    function getProposal(uint256 proposalId) external view returns (
        address recipient, address proposer, uint256 approveWeight, uint256 rejectWeight
    ) {
        Proposal storage p = proposals[proposalId];
        return (p.recipient, p.proposer, p.approveWeight, p.rejectWeight);
    }

    /// @notice Get the proposal range for a given level
    /// @param level The governance level to query
    /// @return start First proposalId for this level
    /// @return count Number of proposals for this level
    function getLevelProposals(uint24 level) external view returns (uint256 start, uint256 count) {
        return (levelProposalStart[level], levelProposalCount[level]);
    }

    // =====================================================================
    //                           PRIVATE
    // =====================================================================

    /// @dev Mint GNRUS tokens to an address (mirror sDGNRS pattern)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }
}
