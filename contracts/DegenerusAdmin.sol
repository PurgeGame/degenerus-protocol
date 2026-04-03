// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";

/**
 * @title DegenerusAdmin
 * @author Burnie Degenerus
 * @notice Central administration contract for the Degenerus GAME ecosystem.
 *
 * @dev ARCHITECTURE OVERVIEW
 * -----------------------------------------------------------------------------
 * This contract serves as the single point of authority for:
 *   1. VRF subscription ownership and management
 *   2. sDGNRS-holder governance for emergency VRF coordinator swaps
 *   3. LINK token donation handling with reward multipliers
 *   4. LINK/ETH price feed management for reward valuation
 *
 * DEPLOYMENT:
 *   - Deploy with no constructor parameters (VRF config from ContractAddresses)
 *   - VRF subscription created and Game consumer configured atomically on deployment
 *   - No post-deployment setup needed
 *
 * OWNERSHIP MODEL:
 *   - Owner is anyone holding >50.1% of DGVE supply (vault governance token)
 *   - No single-address owner; ownership is transferable via DGVE market
 *
 * VRF SUBSCRIPTION LIFECYCLE:
 *   1. Created atomically during constructor call
 *   2. Consumer (Game contract) added automatically during construction
 *   3. LINK funding via onTokenTransfer (ERC-677)
 *   4. Governed VRF swap via propose/vote/execute (M-02 mitigation)
 *   5. Shutdown after GAME-over with LINK refund
 *
 * GOVERNANCE (M-02 Mitigation):
 *   - Admin path: DGVE holder proposes after 20h VRF stall
 *   - Community path: 0.5%+ sDGNRS holder proposes after 7d VRF stall
 *   - Approval voting with decaying threshold (50% → 5% over 7 days)
 *   - Changeable votes, approval voting across proposals
 *   - Auto-invalidation on VRF recovery (stall re-check in every vote)
 */

// =============================================================================
// EXTERNAL INTERFACES
// =============================================================================

/// @dev Minimal VRF coordinator surface for subscription management.
interface IVRFCoordinatorV2_5Owner {
    /// @notice Add a consumer contract to the VRF subscription.
    /// @param subId Subscription ID.
    /// @param consumer Address of the consumer contract to add.
    function addConsumer(uint256 subId, address consumer) external;

    /// @notice Cancel a VRF subscription and refund remaining LINK.
    /// @param subId Subscription ID to cancel.
    /// @param to Address to receive the LINK refund.
    function cancelSubscription(uint256 subId, address to) external;

    /// @notice Create a new VRF subscription.
    /// @return subId The newly created subscription ID.
    function createSubscription() external returns (uint256 subId);

    /// @notice Get subscription details.
    /// @param subId Subscription ID to query.
    /// @return balance LINK token balance.
    /// @return nativeBalance Native token balance.
    /// @return reqCount Total fulfilled request count.
    /// @return owner Subscription owner address.
    /// @return consumers List of consumer contract addresses.
    function getSubscription(
        uint256 subId
    )
        external
        view
        returns (
            uint96 balance,
            uint96 nativeBalance,
            uint64 reqCount,
            address owner,
            address[] memory consumers
        );
}

/// @dev Game contract admin interface (VRF + liquidity).
interface IDegenerusGameAdmin {
    /// @notice Timestamp of the last successfully processed VRF fulfillment.
    function lastVrfProcessed() external view returns (uint48);

    /// @notice Whether the game is in jackpot resolution phase.
    function jackpotPhase() external view returns (bool);

    /// @notice Whether the game has ended.
    function gameOver() external view returns (bool);

    /// @notice Update the VRF coordinator, subscription, and key hash atomically.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New VRF key hash.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;

    /// @notice Wire initial VRF configuration during deployment.
    /// @param coordinator_ VRF coordinator address.
    /// @param subId Subscription ID.
    /// @param keyHash_ VRF key hash.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;

    /// @notice Swap game-held ETH for stETH via external DEX, sending stETH to recipient.
    /// @param recipient Address to receive stETH.
    /// @param amount Amount of ETH to swap.
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable;

    /// @notice Get current purchase parameters.
    /// @return lvl Current game level.
    /// @return qty Tickets purchased this level.
    /// @return cap Ticket cap for this level.
    /// @return jackpotWei Jackpot pool in wei.
    /// @return priceWei Current ticket price in wei.
    function purchaseInfo()
        external
        view
        returns (
            uint256 lvl,
            uint256 qty,
            uint256 cap,
            uint256 jackpotWei,
            uint256 priceWei
        );
}

/// @dev LINK token interface (ERC-677 with transferAndCall).
interface ILinkTokenLike {
    /// @notice Get LINK balance for an account.
    /// @param account Address to query.
    /// @return LINK balance in base units.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer LINK tokens to a recipient.
    /// @param to Recipient address.
    /// @param value Amount of LINK to transfer.
    /// @return success True if transfer succeeded.
    function transfer(
        address to,
        uint256 value
    ) external returns (bool success);

    /// @notice Transfer LINK and call onTokenTransfer on the recipient (ERC-677).
    /// @param to Recipient contract address.
    /// @param value Amount of LINK to transfer.
    /// @param data Additional data passed to the recipient's onTokenTransfer.
    /// @return success True if transfer and callback succeeded.
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool success);
}

/// @dev BurnieCoinflip interface for LINK donation flip credits.
interface IBurnieCoinflipLinkReward {
    /// @notice Credit FLIP stake to a player as a LINK donation reward.
    /// @param player Recipient address.
    /// @param amount Amount of BURNIE-denominated flip stake to credit (18 decimals).
    function creditFlip(address player, uint256 amount) external;
}

/// @dev Chainlink price feed interface (AggregatorV3).
interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function decimals() external view returns (uint8);
}

/// @dev Vault interface for ownership check.
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev sDGNRS interface for governance voting weight and voting supply.
interface IsDGNRS {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function votingSupply() external view returns (uint256);
}

/**
 * @title DegenerusAdmin
 * @notice Central admin contract: owns the VRF subscription, wires VRF config,
 *         and governs emergency VRF coordinator swaps via sDGNRS-holder voting.
 */
contract DegenerusAdmin {
    // =========================================================================
    // GOVERNANCE TYPES
    // =========================================================================

    enum Vote { None, Approve, Reject }
    enum ProposalPath { Admin, Community }
    enum ProposalState { Active, Executed, Killed, Expired }

    /// @dev Packed into 3 storage slots (down from 7).
    ///      Weights and snapshot stored as whole tokens (wei / 1e18). Max 1T = fits uint40 (1.1T max).
    ///      createdAt as uint40 = max year ~36,847.
    ///      Slot 1: proposer(20) + createdAt(5) + votingSnapshot(5) + path(1) + state(1) = 32 exact
    ///      Slot 2: coordinator(20) + approveWeight(5) + rejectWeight(5) = 30 bytes
    ///      Slot 3: keyHash(32) = 32 bytes
    struct Proposal {
        address proposer;              // slot 1: who proposed
        uint40 createdAt;              // slot 1: block.timestamp at creation
        uint40 votingSnapshot;         // slot 1: voting sDGNRS at proposal time (whole tokens)
        ProposalPath path;             // slot 1: Admin or Community
        ProposalState state;           // slot 1: Active, Executed, Killed, Expired
        address coordinator;           // slot 2: proposed VRF coordinator
        uint40 approveWeight;          // slot 2: cumulative sDGNRS approve weight (whole tokens)
        uint40 rejectWeight;           // slot 2: cumulative sDGNRS reject weight (whole tokens)
        bytes32 keyHash;               // slot 3: proposed VRF key hash
    }

    // =========================================================================
    // CUSTOM ERRORS
    // =========================================================================

    error NotOwner();
    error NotAuthorized();
    error ZeroAddress();
    error NotStalled();
    error NotWired();
    error NoSubscription();
    error InvalidAmount();
    error GameOver();
    error FeedHealthy();
    error InvalidFeedDecimals();
    error ProposalNotActive();
    error ProposalExpired();
    error InsufficientStake();
    error AlreadyHasActiveProposal();

    // =========================================================================
    // EVENTS
    // =========================================================================

    event CoordinatorUpdated(
        address indexed coordinator,
        uint256 indexed subId
    );
    event ConsumerAdded(address indexed consumer);
    event SubscriptionCreated(uint256 indexed subId);
    event SubscriptionCancelled(uint256 indexed subId, address indexed to);
    event SubscriptionShutdown(
        uint256 indexed subId,
        address indexed to,
        uint256 sweptAmount
    );
    event LinkCreditRecorded(address indexed player, uint256 amount);
    event LinkEthFeedUpdated(address indexed oldFeed, address indexed newFeed);

    // Governance events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address coordinator,
        bytes32 keyHash,
        ProposalPath path
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool approve,
        uint256 weight
    );
    event ProposalExecuted(
        uint256 indexed proposalId,
        address coordinator,
        uint256 newSubId
    );
    event ProposalKilled(uint256 indexed proposalId);

    // =========================================================================
    // PRECOMPUTED ADDRESSES
    // =========================================================================

    IVRFCoordinatorV2_5Owner internal constant vrfCoordinator =
        IVRFCoordinatorV2_5Owner(ContractAddresses.VRF_COORDINATOR);
    IDegenerusGameAdmin internal constant gameAdmin =
        IDegenerusGameAdmin(ContractAddresses.GAME);
    ILinkTokenLike internal constant linkToken =
        ILinkTokenLike(ContractAddresses.LINK_TOKEN);
    IBurnieCoinflipLinkReward internal constant coinflipReward =
        IBurnieCoinflipLinkReward(ContractAddresses.COINFLIP);
    IsDGNRS internal constant sDGNRS =
        IsDGNRS(ContractAddresses.SDGNRS);

    // =========================================================================
    // VRF STATE
    // =========================================================================

    /// @notice Current VRF coordinator address.
    address public coordinator;

    /// @notice Current VRF subscription ID.
    uint256 public subscriptionId;

    /// @notice VRF key hash for the current coordinator.
    bytes32 public vrfKeyHash;

    // =========================================================================
    // GOVERNANCE STATE
    // =========================================================================

    /// @notice Total proposals ever created (also serves as next ID - 1).
    uint256 public proposalCount;

    /// @notice Proposal data by ID (1-indexed).
    mapping(uint256 => Proposal) public proposals;

    /// @notice Vote direction per voter per proposal.
    mapping(uint256 => mapping(address => Vote)) public votes;

    /// @notice Vote weight recorded at time of vote (whole tokens).
    mapping(uint256 => mapping(address => uint40)) public voteWeight;

    /// @notice Tracks each address's current active proposal ID (0 = none).
    mapping(address => uint256) public activeProposalId;

    /// @dev Proposal ID up to which all proposals are guaranteed non-Active.
    ///      _voidAllActive starts scanning from this index instead of 1.
    uint256 private voidedUpTo;

    // =========================================================================
    // FEED GOVERNANCE STATE
    // =========================================================================

    /// @dev Packed into 2 storage slots (down from 6).
    ///      Weights and snapshot stored as whole tokens (wei / 1e18). Max 1T = fits uint40 (1.1T max).
    ///      Slot 1: proposer(20) + createdAt(5) + votingSnapshot(5) + path(1) + state(1) = 32 exact
    ///      Slot 2: feed(20) + approveWeight(5) + rejectWeight(5) = 30 bytes
    struct FeedProposal {
        address proposer;              // slot 1: who proposed
        uint40 createdAt;              // slot 1: block.timestamp at creation
        uint40 votingSnapshot;         // slot 1: voting sDGNRS at proposal time (whole tokens)
        ProposalPath path;             // slot 1: Admin or Community
        ProposalState state;           // slot 1: Active, Executed, Killed, Expired
        address feed;                  // slot 2: proposed feed address (zero = disable)
        uint40 approveWeight;          // slot 2: cumulative sDGNRS approve weight (whole tokens)
        uint40 rejectWeight;           // slot 2: cumulative sDGNRS reject weight (whole tokens)
    }

    /// @notice Total feed proposals ever created.
    uint256 public feedProposalCount;

    /// @notice Feed proposal data by ID (1-indexed).
    mapping(uint256 => FeedProposal) public feedProposals;

    /// @notice Vote direction per voter per feed proposal.
    mapping(uint256 => mapping(address => Vote)) public feedVotes;

    /// @notice Vote weight recorded at time of feed vote (whole tokens).
    mapping(uint256 => mapping(address => uint40)) public feedVoteWeight;

    /// @notice Tracks each address's current active feed proposal ID (0 = none).
    mapping(address => uint256) public activeFeedProposalId;

    /// @dev Feed proposal ID up to which all proposals are guaranteed non-Active.
    uint256 private feedVoidedUpTo;

    // Feed governance events
    event FeedProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address feed,
        ProposalPath path
    );
    event FeedVoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool approve,
        uint256 weight
    );
    event FeedProposalExecuted(uint256 indexed proposalId, address feed);
    event FeedProposalKilled(uint256 indexed proposalId);

    // =========================================================================
    // LINK REWARD STATE
    // =========================================================================

    /// @notice Chainlink LINK/ETH price feed address.
    address public linkEthPriceFeed;

    /// @dev BURNIE conversion constant: 1000 BURNIE = 1e21 base units.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Expected LINK/ETH feed decimals.
    uint8 private constant LINK_ETH_FEED_DECIMALS = 18;

    /// @dev Max staleness window before LINK/ETH feed is considered unhealthy.
    uint256 private constant LINK_ETH_MAX_STALE = 1 days;

    // =========================================================================
    // GOVERNANCE CONSTANTS
    // =========================================================================

    /// @dev Minimum VRF stall duration before admin can propose (20 hours).
    uint256 private constant ADMIN_STALL_THRESHOLD = 20 hours;

    /// @dev Minimum VRF stall duration before community can propose (7 days).
    uint256 private constant COMMUNITY_STALL_THRESHOLD = 7 days;

    /// @dev Minimum feed-unhealthy duration before admin can propose feed swap (2 days).
    uint256 private constant FEED_ADMIN_STALL_THRESHOLD = 2 days;

    /// @dev Minimum feed-unhealthy duration before community can propose feed swap (7 days).
    uint256 private constant FEED_COMMUNITY_STALL_THRESHOLD = 7 days;

    /// @dev Feed swap proposal lifetime before expiry (168 hours = 7 days).
    uint256 private constant FEED_PROPOSAL_LIFETIME = 168 hours;

    /// @dev Minimum sDGNRS stake to propose via community path (0.5% = 50 bps).
    uint256 private constant COMMUNITY_PROPOSE_BPS = 50;

    /// @dev Proposal lifetime before expiry (168 hours = 7 days).
    uint256 private constant PROPOSAL_LIFETIME = 168 hours;

    /// @dev Basis points denominator.
    uint256 private constant BPS = 10000;

    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    IDegenerusVaultOwner private constant vault =
        IDegenerusVaultOwner(ContractAddresses.VAULT);

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotOwner();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() {
        uint256 subId = vrfCoordinator.createSubscription();

        coordinator = ContractAddresses.VRF_COORDINATOR;
        subscriptionId = subId;
        vrfKeyHash = ContractAddresses.VRF_KEY_HASH;

        emit SubscriptionCreated(subId);
        emit CoordinatorUpdated(ContractAddresses.VRF_COORDINATOR, subId);

        vrfCoordinator.addConsumer(subId, ContractAddresses.GAME);
        emit ConsumerAdded(ContractAddresses.GAME);

        gameAdmin.wireVrf(
            ContractAddresses.VRF_COORDINATOR,
            subId,
            ContractAddresses.VRF_KEY_HASH
        );
    }

    // =========================================================================
    // PRICE FEED MANAGEMENT
    // =========================================================================

    // =========================================================================
    // PRICE FEED SWAP GOVERNANCE
    // =========================================================================

    /// @notice Propose a LINK/ETH price feed swap.
    /// @dev Two paths:
    ///      - Admin path: DGVE >50.1% holder, requires 2d+ feed unhealthy
    ///      - Community path: 0.5%+ voting sDGNRS, requires 7d+ feed unhealthy
    /// @param newFeed Address of the proposed price feed (zero to disable).
    /// @return proposalId The ID of the created proposal.
    function proposeFeedSwap(
        address newFeed
    ) external returns (uint256 proposalId) {
        if (gameAdmin.gameOver()) revert GameOver();

        // Feed must be unhealthy and stale long enough for the proposer's path
        uint256 stall = _feedStallDuration(linkEthPriceFeed);
        if (stall == 0) revert FeedHealthy();

        // Validate proposed feed (zero = disable, non-zero must have correct decimals)
        if (
            newFeed != address(0) &&
            IAggregatorV3(newFeed).decimals() != LINK_ETH_FEED_DECIMALS
        ) {
            revert InvalidFeedDecimals();
        }

        // 1-per-address active proposal limit
        uint256 existing = activeFeedProposalId[msg.sender];
        if (existing != 0) {
            FeedProposal storage ep = feedProposals[existing];
            if (ep.state == ProposalState.Active &&
                block.timestamp - uint256(ep.createdAt) < FEED_PROPOSAL_LIFETIME) {
                revert AlreadyHasActiveProposal();
            }
        }

        ProposalPath path;
        if (vault.isVaultOwner(msg.sender)) {
            if (stall < FEED_ADMIN_STALL_THRESHOLD) revert NotStalled();
            path = ProposalPath.Admin;
        } else {
            if (stall < FEED_COMMUNITY_STALL_THRESHOLD) revert NotStalled();
            uint256 circ = sDGNRS.votingSupply();
            if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)
                revert InsufficientStake();
            path = ProposalPath.Community;
        }

        proposalId = ++feedProposalCount;
        FeedProposal storage p = feedProposals[proposalId];
        p.proposer = msg.sender;
        p.createdAt = uint40(block.timestamp);
        p.path = path;
        // p.state = ProposalState.Active (default 0)
        p.feed = newFeed;
        // approveWeight and rejectWeight start at 0
        p.votingSnapshot = uint40(sDGNRS.votingSupply() / 1 ether);

        activeFeedProposalId[msg.sender] = proposalId;

        emit FeedProposalCreated(proposalId, msg.sender, newFeed, path);
    }

    /// @notice Vote on an active feed swap proposal.
    /// @dev Votes are changeable. After recording, checks execute/kill conditions.
    ///      Reverts if feed has recovered — auto-cancellation.
    /// @param proposalId ID of the feed proposal to vote on.
    /// @param approve True to approve, false to reject.
    /// @dev Zero-weight calls (no sDGNRS) skip vote recording and just check
    ///      execute/kill conditions. This allows anyone to "poke" a proposal
    ///      that has already crossed threshold due to time decay.
    function voteFeedSwap(uint256 proposalId, bool approve) external {
        // Feed recovery check: if feed is healthy again, governance is invalid
        if (_feedHealthy(linkEthPriceFeed)) revert FeedHealthy();

        FeedProposal storage p = feedProposals[proposalId];
        _requireActiveProposal(p.state, p.createdAt, FEED_PROPOSAL_LIFETIME);

        // Record vote only if caller has sDGNRS; otherwise skip to threshold checks (poke)
        uint40 weight = _voterWeight();
        if (weight != 0) {
            (p.approveWeight, p.rejectWeight) = _applyVote(
                approve, weight,
                feedVotes[proposalId][msg.sender],
                feedVoteWeight[proposalId][msg.sender],
                p.approveWeight, p.rejectWeight
            );
            feedVotes[proposalId][msg.sender] = approve ? Vote.Approve : Vote.Reject;
            feedVoteWeight[proposalId][msg.sender] = weight;
            emit FeedVoteCast(proposalId, msg.sender, approve, uint256(weight) * 1 ether);
        }

        Resolution r = _resolveThreshold(
            p.approveWeight, p.rejectWeight, p.votingSnapshot, feedThreshold(proposalId)
        );
        if (r == Resolution.Execute) {
            _executeFeedSwap(proposalId);
        } else if (r == Resolution.Kill) {
            p.state = ProposalState.Killed;
            emit FeedProposalKilled(proposalId);
        }
    }

    /// @notice Current approval threshold for a feed proposal (basis points, decays daily).
    /// @dev Defence-weighted schedule: 50% → 40% → 25% → 15% over 4 days.
    ///      Floor is 15% (1500 bps) — if community can't reach 15% with approve > reject,
    ///      the proposal expires. Defence matters more than restoring LINK rewards.
    /// @param proposalId ID of the feed proposal.
    /// @return Threshold in basis points (e.g. 5000 = 50%).
    function feedThreshold(uint256 proposalId) public view returns (uint16) {
        uint256 elapsed = block.timestamp - uint256(feedProposals[proposalId].createdAt);
        if (elapsed >= FEED_PROPOSAL_LIFETIME) return 0;
        if (elapsed >= 72 hours) return 1500;  // 15%
        if (elapsed >= 48 hours) return 2500;  // 25%
        if (elapsed >= 24 hours) return 4000;  // 40%
        return 5000; // 50%
    }

    /// @notice Check if a feed proposal can be executed (view-only).
    /// @param proposalId ID of the feed proposal.
    /// @return True if all execution conditions are met.
    function canExecuteFeedSwap(uint256 proposalId) external view returns (bool) {
        FeedProposal storage p = feedProposals[proposalId];
        if (!_isActiveProposal(p.state, p.createdAt, FEED_PROPOSAL_LIFETIME)) return false;
        if (_feedHealthy(linkEthPriceFeed)) return false;

        return _resolveThreshold(
            p.approveWeight, p.rejectWeight, p.votingSnapshot, feedThreshold(proposalId)
        ) == Resolution.Execute;
    }

    /// @dev Execute feed swap and void all other active feed proposals.
    function _executeFeedSwap(uint256 proposalId) internal {
        FeedProposal storage p = feedProposals[proposalId];
        p.state = ProposalState.Executed;

        // Void all other active feed proposals
        uint256 start = feedVoidedUpTo + 1;
        uint256 count = feedProposalCount;
        for (uint256 i = start; i <= count; i++) {
            if (i == proposalId) continue;
            if (feedProposals[i].state == ProposalState.Active) {
                feedProposals[i].state = ProposalState.Killed;
                emit FeedProposalKilled(i);
            }
        }
        feedVoidedUpTo = count;

        address oldFeed = linkEthPriceFeed;
        linkEthPriceFeed = p.feed;

        emit LinkEthFeedUpdated(oldFeed, p.feed);
        emit FeedProposalExecuted(proposalId, p.feed);
    }

    // =========================================================================
    // LIQUIDITY MANAGEMENT
    // =========================================================================

    /// @notice Swap game-held ETH for stETH via external DEX, sending stETH to caller.
    /// @dev Forwards msg.value as the ETH amount to swap.
    function swapGameEthForStEth() external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value);
    }

    // =========================================================================
    // VRF COORDINATOR SWAP GOVERNANCE (M-02 Mitigation)
    // =========================================================================

    /// @notice Propose an emergency VRF coordinator swap.
    /// @dev Two paths:
    ///      - Admin path: DGVE >50.1% holder, requires 20h+ VRF stall
    ///      - Community path: 0.5%+ voting sDGNRS, requires 7d+ VRF stall
    /// @param newCoordinator Address of the proposed VRF coordinator.
    /// @param newKeyHash Key hash for the proposed coordinator.
    /// @return proposalId The ID of the created proposal.
    function propose(
        address newCoordinator,
        bytes32 newKeyHash
    ) external returns (uint256 proposalId) {
        if (subscriptionId == 0) revert NotWired();
        if (gameAdmin.gameOver()) revert GameOver();
        if (newCoordinator == address(0) || newKeyHash == bytes32(0))
            revert ZeroAddress();

        // 1-per-address active proposal limit
        uint256 existing = activeProposalId[msg.sender];
        if (existing != 0) {
            Proposal storage ep = proposals[existing];
            if (ep.state == ProposalState.Active &&
                block.timestamp - uint256(ep.createdAt) < PROPOSAL_LIFETIME) {
                revert AlreadyHasActiveProposal();
            }
        }

        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        uint256 stall = block.timestamp - uint256(lastVrf);

        ProposalPath path;
        if (vault.isVaultOwner(msg.sender)) {
            if (stall < ADMIN_STALL_THRESHOLD) revert NotStalled();
            path = ProposalPath.Admin;
        } else {
            if (stall < COMMUNITY_STALL_THRESHOLD) revert NotStalled();
            uint256 circ = sDGNRS.votingSupply();
            if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)
                revert InsufficientStake();
            path = ProposalPath.Community;
        }

        proposalId = ++proposalCount;
        Proposal storage p = proposals[proposalId];
        p.proposer = msg.sender;
        p.createdAt = uint40(block.timestamp);
        p.path = path;
        // p.state = ProposalState.Active (default 0)
        p.coordinator = newCoordinator;
        p.keyHash = newKeyHash;
        p.votingSnapshot = uint40(sDGNRS.votingSupply() / 1 ether);

        activeProposalId[msg.sender] = proposalId;

        emit ProposalCreated(proposalId, msg.sender, newCoordinator, newKeyHash, path);
    }

    /// @notice Vote on an active VRF swap proposal.
    /// @dev Votes are changeable. After recording, checks execute/kill conditions.
    ///      Reverts if VRF has recovered (stall < 20h) — this IS the auto-cancellation.
    ///      Zero-weight calls (no sDGNRS) skip vote recording and just check
    ///      execute/kill conditions — allows anyone to poke a proposal past threshold.
    /// @param proposalId ID of the proposal to vote on.
    /// @param approve True to approve, false to reject.
    function vote(uint256 proposalId, bool approve) external {
        // Stall re-check: if VRF recovered, all governance is invalid
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD)
            revert NotStalled();

        Proposal storage p = proposals[proposalId];
        _requireActiveProposal(p.state, p.createdAt, PROPOSAL_LIFETIME);

        // Record vote only if caller has sDGNRS; otherwise skip to threshold checks (poke)
        // Safe: VRF dead = supply frozen (no advances, unwrapTo blocked)
        uint40 weight = _voterWeight();
        if (weight != 0) {
            (p.approveWeight, p.rejectWeight) = _applyVote(
                approve, weight,
                votes[proposalId][msg.sender],
                voteWeight[proposalId][msg.sender],
                p.approveWeight, p.rejectWeight
            );
            votes[proposalId][msg.sender] = approve ? Vote.Approve : Vote.Reject;
            voteWeight[proposalId][msg.sender] = weight;
            emit VoteCast(proposalId, msg.sender, approve, uint256(weight) * 1 ether);
        }

        Resolution r = _resolveThreshold(
            p.approveWeight, p.rejectWeight, p.votingSnapshot, threshold(proposalId)
        );
        if (r == Resolution.Execute) {
            _executeSwap(proposalId);
        } else if (r == Resolution.Kill) {
            p.state = ProposalState.Killed;
            emit ProposalKilled(proposalId);
        }
    }

    /// @notice Current approval threshold for a proposal (basis points, decays daily).
    /// @dev Returns 0 if proposal has expired (168h+).
    /// @param proposalId ID of the proposal.
    /// @return Threshold in basis points (e.g. 5000 = 50%).
    function threshold(uint256 proposalId) public view returns (uint16) {
        uint256 elapsed = block.timestamp - uint256(proposals[proposalId].createdAt);
        if (elapsed >= 168 hours) return 0;
        if (elapsed >= 144 hours) return 500;   // 5%
        if (elapsed >= 120 hours) return 1000;  // 10%
        if (elapsed >= 96 hours)  return 2000;  // 20%
        if (elapsed >= 72 hours)  return 3000;  // 30%
        if (elapsed >= 48 hours)  return 4000;  // 40%
        return 5000; // 50%
    }

    /// @notice Check if a proposal can be executed (view-only, no side effects).
    /// @param proposalId ID of the proposal.
    /// @return True if all execution conditions are met.
    function canExecute(uint256 proposalId) external view returns (bool) {
        Proposal storage p = proposals[proposalId];
        if (!_isActiveProposal(p.state, p.createdAt, PROPOSAL_LIFETIME)) return false;

        // Stall check
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD) return false;

        return _resolveThreshold(
            p.approveWeight, p.rejectWeight, p.votingSnapshot, threshold(proposalId)
        ) == Resolution.Execute;
    }

    // =========================================================================
    // SHARED GOVERNANCE HELPERS
    // =========================================================================

    enum Resolution { None, Execute, Kill }

    /// @dev Calculate new cumulative weights after a vote, handling vote changes.
    ///      Returns (newApprove, newReject) — caller applies to storage.
    function _applyVote(
        bool approve,
        uint40 weight,
        Vote currentVote,
        uint40 oldWeight,
        uint40 approveWeight,
        uint40 rejectWeight
    ) private pure returns (uint40, uint40) {
        // Undo previous vote if changing
        if (currentVote == Vote.Approve) {
            approveWeight -= oldWeight;
        } else if (currentVote == Vote.Reject) {
            rejectWeight -= oldWeight;
        }
        // Apply new vote
        if (approve) {
            approveWeight += weight;
        } else {
            rejectWeight += weight;
        }
        return (approveWeight, rejectWeight);
    }

    /// @dev Get voter's sDGNRS weight as whole tokens (0 if none, floor 1 if dust).
    function _voterWeight() private view returns (uint40) {
        uint256 raw = sDGNRS.balanceOf(msg.sender);
        if (raw == 0) return 0;
        uint40 w = uint40(raw / 1 ether);
        return w == 0 ? 1 : w;
    }

    /// @dev Validate a proposal is active and not expired.
    ///      Reverts ProposalNotActive or ProposalExpired.
    function _requireActiveProposal(
        ProposalState state,
        uint40 createdAt,
        uint256 lifetime
    ) private view {
        if (state != ProposalState.Active || createdAt == 0)
            revert ProposalNotActive();
        if (block.timestamp - uint256(createdAt) >= lifetime)
            revert ProposalExpired();
    }

    /// @dev Check if a proposal is active and not expired (view, no revert).
    function _isActiveProposal(
        ProposalState state,
        uint40 createdAt,
        uint256 lifetime
    ) private view returns (bool) {
        if (state != ProposalState.Active || createdAt == 0) return false;
        if (block.timestamp - uint256(createdAt) >= lifetime) return false;
        return true;
    }

    /// @dev Check whether approve or reject weight has crossed the threshold.
    ///      Returns Execute, Kill, or None. All values promoted to uint256.
    function _resolveThreshold(
        uint256 approveWeight,
        uint256 rejectWeight,
        uint256 snapshot,
        uint16 t
    ) private pure returns (Resolution) {
        if (
            approveWeight * BPS >= uint256(t) * snapshot &&
            approveWeight > rejectWeight
        ) return Resolution.Execute;
        if (
            rejectWeight > approveWeight &&
            rejectWeight * BPS >= uint256(t) * snapshot
        ) return Resolution.Kill;
        return Resolution.None;
    }

    // =========================================================================
    // GOVERNANCE INTERNAL
    // =========================================================================

    /// @dev Execute VRF coordinator swap and void all other active proposals.
    // Intentional: lastVrfProcessedTimestamp is NOT reset here — the old stall
    // timestamp carries over so governance can rapidly re-swap if the new
    // coordinator also fails, without waiting for a fresh stall window.
    function _executeSwap(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        p.state = ProposalState.Executed;

        // Void all other active proposals before external calls (CEI)
        _voidAllActive(proposalId);

        address newCoordinator = p.coordinator;
        bytes32 newKeyHash = p.keyHash;

        uint256 oldSub = subscriptionId;
        address oldCoord = coordinator;

        // 1. Cancel old subscription (try/catch for edge cases)
        if (oldSub != 0) {
            try
                IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(
                    oldSub,
                    address(this)
                )
            {
                emit SubscriptionCancelled(oldSub, address(this));
            } catch {}
        }

        // 2. Create new subscription on proposed coordinator
        coordinator = newCoordinator;
        uint256 newSubId = IVRFCoordinatorV2_5Owner(newCoordinator)
            .createSubscription();
        subscriptionId = newSubId;
        vrfKeyHash = newKeyHash;
        emit CoordinatorUpdated(newCoordinator, newSubId);
        emit SubscriptionCreated(newSubId);

        // 3. Add Game as consumer
        IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(
            newSubId,
            ContractAddresses.GAME
        );
        emit ConsumerAdded(ContractAddresses.GAME);

        // 4. Push new config to Game
        gameAdmin.updateVrfCoordinatorAndSub(
            newCoordinator,
            newSubId,
            newKeyHash
        );

        // 5. Transfer LINK to new subscription
        uint256 bal = linkToken.balanceOf(address(this));
        if (bal != 0) {
            try
                linkToken.transferAndCall(
                    newCoordinator,
                    bal,
                    abi.encode(newSubId)
                )
            returns (bool) {} catch {}
        }

        emit ProposalExecuted(proposalId, newCoordinator, newSubId);
    }

    /// @dev Mark all active proposals (except the executed one) as Killed.
    ///      Uses voidedUpTo watermark to skip already-voided prefix.
    function _voidAllActive(uint256 exceptId) internal {
        uint256 start = voidedUpTo + 1;
        uint256 count = proposalCount;
        for (uint256 i = start; i <= count; i++) {
            if (i == exceptId) continue;
            if (proposals[i].state == ProposalState.Active) {
                proposals[i].state = ProposalState.Killed;
                emit ProposalKilled(i);
            }
        }
        // All proposals up to count are now non-Active (except exceptId which is Executed).
        voidedUpTo = count;
    }

    // =========================================================================
    // VRF SHUTDOWN (Game-Over)
    // =========================================================================

    /// @notice Cancel VRF subscription and sweep LINK to vault after GAME-over.
    /// @dev Only callable by the GAME contract (during handleFinalSweep).
    function shutdownVrf() external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        uint256 subId = subscriptionId;
        if (subId == 0) return;

        subscriptionId = 0;
        address target = ContractAddresses.VAULT;

        try IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, target) {
            emit SubscriptionCancelled(subId, target);
        } catch {}

        uint256 bal = linkToken.balanceOf(address(this));
        if (bal != 0) {
            try linkToken.transfer(target, bal) returns (bool ok) {
                if (ok) {
                    emit SubscriptionShutdown(subId, target, bal);
                    return;
                }
            } catch {}
        }

        emit SubscriptionShutdown(subId, target, 0);
    }

    // =========================================================================
    // LINK DONATION HANDLING (ERC-677 Callback)
    // =========================================================================

    /// @notice ERC-677 callback: handles LINK donations to fund VRF subscription.
    /// @param from Address that sent the LINK.
    /// @param amount Amount of LINK received.
    /// @param --- Unused calldata (required by ERC-677 interface).
    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata
    ) external {
        if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();
        if (amount == 0) revert InvalidAmount();

        uint256 subId = subscriptionId;
        if (subId == 0) revert NoSubscription();
        if (gameAdmin.gameOver()) revert GameOver();

        address coord = coordinator;

        (uint96 bal, , , , ) = IVRFCoordinatorV2_5Owner(coord).getSubscription(
            subId
        );
        uint256 mult = _linkRewardMultiplier(uint256(bal));

        try
            linkToken.transferAndCall(coord, amount, abi.encode(subId))
        returns (bool ok) {
            if (!ok) revert InvalidAmount();
        } catch {
            revert InvalidAmount();
        }
        if (mult == 0) return;

        uint256 ethEquivalent;
        try this.linkAmountToEth(amount) returns (uint256 eth) {
            ethEquivalent = eth;
        } catch {
            return;
        }
        if (ethEquivalent == 0) return;

        (, , , , uint256 priceWei) = gameAdmin.purchaseInfo();
        if (priceWei == 0) return;
        uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;
        uint256 credit = (baseCredit * mult) / 1e18;
        if (credit == 0) return;

        coinflipReward.creditFlip(from, credit);
        emit LinkCreditRecorded(from, credit);
    }

    // =========================================================================
    // INTERNAL HELPERS — LINK VALUATION
    // =========================================================================

    /// @dev Convert LINK amount to ETH-equivalent using price feed.
    function linkAmountToEth(
        uint256 amount
    ) external view returns (uint256 ethAmount) {
        address feed = linkEthPriceFeed;
        if (feed == address(0) || amount == 0) return 0;

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IAggregatorV3(feed).latestRoundData();
        if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
            return 0;
        if (updatedAt > block.timestamp) return 0;
        unchecked {
            if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE) return 0;
        }

        ethAmount = (amount * uint256(answer)) / 1 ether;
    }

    /// @dev Calculate reward multiplier based on subscription LINK balance.
    function _linkRewardMultiplier(
        uint256 subBal
    ) private pure returns (uint256 mult) {
        if (subBal >= 1000 ether) return 0;
        if (subBal <= 200 ether) {
            uint256 delta = (subBal * 2e18) / 200 ether;
            unchecked {
                return 3e18 - delta;
            }
        }
        uint256 excess = subBal - 200 ether;
        uint256 delta2 = (excess * 1e18) / 800 ether;
        if (delta2 >= 1e18) return 0;
        unchecked {
            return 1e18 - delta2;
        }
    }

    /// @dev Returns how long the feed has been unhealthy (0 if healthy).
    ///      Uses the feed's own updatedAt as the last-healthy timestamp.
    ///      If feed is zero, reverted, or has bad data, returns max stall.
    function _feedStallDuration(address feed) private view returns (uint256) {
        if (feed == address(0)) return type(uint256).max;
        try IAggregatorV3(feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                return type(uint256).max;
            if (updatedAt > block.timestamp) return type(uint256).max;
            uint256 age = block.timestamp - updatedAt;
            if (age <= LINK_ETH_MAX_STALE) return 0; // healthy
            return age;
        } catch {
            return type(uint256).max;
        }
    }

    /// @dev Check if a price feed is healthy (fresh and valid).
    function _feedHealthy(address feed) private view returns (bool) {
        if (feed == address(0)) return false;
        try IAggregatorV3(feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                return false;
            if (updatedAt > block.timestamp) return false;
            unchecked {
                if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE)
                    return false;
            }
            try IAggregatorV3(feed).decimals() returns (uint8 dec) {
                if (dec != LINK_ETH_FEED_DECIMALS) return false;
            } catch {
                return false;
            }
            return true;
        } catch {
            return false;
        }
    }
}
