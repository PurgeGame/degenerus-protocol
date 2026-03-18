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
 *   - Approval voting with decaying threshold (60% → 5% over 7 days)
 *   - Changeable votes, approval voting across proposals
 *   - Auto-invalidation on VRF recovery (stall re-check in every vote)
 *   - Death clock pauses while any proposal is active
 */

// =============================================================================
// EXTERNAL INTERFACES
// =============================================================================

/// @dev Minimal VRF coordinator surface for subscription management.
interface IVRFCoordinatorV2_5Owner {
    function addConsumer(uint256 subId, address consumer) external;
    function cancelSubscription(uint256 subId, address to) external;
    function createSubscription() external returns (uint256 subId);
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

/// @dev Game contract admin interface (VRF + liquidity + liveness).
interface IDegenerusGameAdmin {
    function lastVrfProcessed() external view returns (uint48);
    function jackpotPhase() external view returns (bool);
    function gameOver() external view returns (bool);
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable;
    function adminStakeEthForStEth(uint256 amount) external;
    function setLootboxRngThreshold(uint256 newThreshold) external;
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
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address to,
        uint256 value
    ) external returns (bool success);
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool success);
}

/// @dev Coin contract interface for LINK donation flip credits.
interface IDegenerusCoinLinkReward {
    function creditLinkReward(address player, uint256 amount) external;
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

/// @dev sDGNRS interface for governance voting weight and circulating supply.
interface IsDGNRS {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
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

    struct Proposal {
        address proposer;
        address coordinator;
        bytes32 keyHash;
        uint48 createdAt;
        uint256 approveWeight;
        uint256 rejectWeight;
        uint256 circulatingSnapshot;
        ProposalPath path;
        ProposalState state;
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
    event LinkEthFeedUpdated(address indexed feed);

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
    IDegenerusCoinLinkReward internal constant coinLinkReward =
        IDegenerusCoinLinkReward(ContractAddresses.COIN);
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

    /// @notice Vote weight recorded at time of vote.
    mapping(uint256 => mapping(address => uint256)) public voteWeight;

    /// @notice Tracks each address's current active proposal ID (0 = none).
    mapping(address => uint256) public activeProposalId;

    /// @dev Proposal ID up to which all proposals are guaranteed non-Active.
    ///      _voidAllActive starts scanning from this index instead of 1.
    uint256 private voidedUpTo;

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

    /// @notice Configure the LINK/ETH price feed for LINK donation valuation.
    /// @param feed New price feed address (zero to disable).
    function setLinkEthPriceFeed(address feed) external onlyOwner {
        address current = linkEthPriceFeed;
        if (_feedHealthy(current)) revert FeedHealthy();
        if (
            feed != address(0) &&
            IAggregatorV3(feed).decimals() != LINK_ETH_FEED_DECIMALS
        ) {
            revert InvalidFeedDecimals();
        }
        linkEthPriceFeed = feed;
        emit LinkEthFeedUpdated(feed);
    }

    // =========================================================================
    // LIQUIDITY MANAGEMENT
    // =========================================================================

    function swapGameEthForStEth() external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value);
    }

    function stakeGameEthToStEth(uint256 amount) external onlyOwner {
        gameAdmin.adminStakeEthForStEth(amount);
    }

    function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {
        gameAdmin.setLootboxRngThreshold(newThreshold);
    }

    // =========================================================================
    // VRF COORDINATOR SWAP GOVERNANCE (M-02 Mitigation)
    // =========================================================================

    /// @notice Propose an emergency VRF coordinator swap.
    /// @dev Two paths:
    ///      - Admin path: DGVE >50.1% holder, requires 20h+ VRF stall
    ///      - Community path: 0.5%+ circulating sDGNRS, requires 7d+ VRF stall
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
            uint256 circ = circulatingSupply();
            if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)
                revert InsufficientStake();
            path = ProposalPath.Community;
        }

        proposalId = ++proposalCount;
        Proposal storage p = proposals[proposalId];
        p.proposer = msg.sender;
        p.coordinator = newCoordinator;
        p.keyHash = newKeyHash;
        p.createdAt = uint48(block.timestamp);
        p.circulatingSnapshot = circulatingSupply();
        p.path = path;
        // p.state = ProposalState.Active (default 0)

        activeProposalId[msg.sender] = proposalId;

        emit ProposalCreated(proposalId, msg.sender, newCoordinator, newKeyHash, path);
    }

    /// @notice Vote on an active VRF swap proposal.
    /// @dev Votes are changeable. After recording, checks execute/kill conditions.
    ///      Reverts if VRF has recovered (stall < 20h) — this IS the auto-cancellation.
    /// @param proposalId ID of the proposal to vote on.
    /// @param approve True to approve, false to reject.
    function vote(uint256 proposalId, bool approve) external {
        // Stall re-check: if VRF recovered, all governance is invalid
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD)
            revert NotStalled();

        Proposal storage p = proposals[proposalId];
        if (p.state != ProposalState.Active || p.createdAt == 0)
            revert ProposalNotActive();

        // Check expiry
        if (block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME) {
            p.state = ProposalState.Expired;
            revert ProposalExpired();
        }

        // Get voter weight from live sDGNRS balance
        // Safe: VRF dead = supply frozen (no advances, unwrapTo blocked)
        uint256 weight = sDGNRS.balanceOf(msg.sender);
        if (weight == 0) revert InsufficientStake();

        // Handle vote change: subtract old weight before adding new
        Vote currentVote = votes[proposalId][msg.sender];
        if (currentVote != Vote.None) {
            uint256 oldWeight = voteWeight[proposalId][msg.sender];
            if (currentVote == Vote.Approve) {
                p.approveWeight -= oldWeight;
            } else {
                p.rejectWeight -= oldWeight;
            }
        }

        // Record new vote
        Vote newVote = approve ? Vote.Approve : Vote.Reject;
        votes[proposalId][msg.sender] = newVote;
        voteWeight[proposalId][msg.sender] = weight;

        if (approve) {
            p.approveWeight += weight;
        } else {
            p.rejectWeight += weight;
        }

        emit VoteCast(proposalId, msg.sender, approve, weight);

        // Check execute/kill conditions against decaying threshold
        uint16 t = threshold(proposalId);

        // Execute: approve% >= threshold AND approve > reject
        if (
            p.approveWeight * BPS >= uint256(t) * p.circulatingSnapshot &&
            p.approveWeight > p.rejectWeight
        ) {
            _executeSwap(proposalId);
            return;
        }

        // Kill: reject > approve AND reject% >= threshold
        if (
            p.rejectWeight > p.approveWeight &&
            p.rejectWeight * BPS >= uint256(t) * p.circulatingSnapshot
        ) {
            p.state = ProposalState.Killed;
            emit ProposalKilled(proposalId);
        }
    }

    /// @notice Circulating sDGNRS supply (excludes undistributed pools and DGNRS wrapper).
    function circulatingSupply() public view returns (uint256) {
        return sDGNRS.totalSupply()
            - sDGNRS.balanceOf(ContractAddresses.SDGNRS)
            - sDGNRS.balanceOf(ContractAddresses.DGNRS);
    }

    /// @notice Current approval threshold for a proposal (basis points, decays daily).
    /// @dev Returns 0 if proposal has expired (168h+).
    /// @param proposalId ID of the proposal.
    /// @return Threshold in basis points (e.g. 6000 = 60%).
    function threshold(uint256 proposalId) public view returns (uint16) {
        uint256 elapsed = block.timestamp - uint256(proposals[proposalId].createdAt);
        if (elapsed >= 168 hours) return 0;
        if (elapsed >= 144 hours) return 500;   // 5%
        if (elapsed >= 120 hours) return 1000;  // 10%
        if (elapsed >= 96 hours)  return 2000;  // 20%
        if (elapsed >= 72 hours)  return 3000;  // 30%
        if (elapsed >= 48 hours)  return 4000;  // 40%
        if (elapsed >= 24 hours)  return 5000;  // 50%
        return 6000; // 60%
    }

    /// @notice Check if a proposal can be executed (view-only, no side effects).
    /// @param proposalId ID of the proposal.
    /// @return True if all execution conditions are met.
    function canExecute(uint256 proposalId) external view returns (bool) {
        Proposal storage p = proposals[proposalId];
        if (p.state != ProposalState.Active || p.createdAt == 0) return false;
        if (block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME) return false;

        // Stall check
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD) return false;

        uint16 t = threshold(proposalId);
        return p.approveWeight * BPS >= uint256(t) * p.circulatingSnapshot
            && p.approveWeight > p.rejectWeight;
    }

    // =========================================================================
    // GOVERNANCE INTERNAL
    // =========================================================================

    /// @dev Execute VRF coordinator swap and void all other active proposals.
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

        coinLinkReward.creditLinkReward(from, credit);
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
