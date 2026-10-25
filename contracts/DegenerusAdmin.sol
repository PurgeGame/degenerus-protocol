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

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

import {BoundedCall} from "./libraries/BoundedCall.sol";
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
 *   3. Native subscription donations with 25% request credit
 *
 * DEPLOYMENT:
 *   - Deploy with no constructor parameters (VRF config from ContractAddresses)
 *   - VRF subscription created and Game consumer configured atomically on deployment
 *   - No post-deployment setup needed
 *
 * OWNERSHIP MODEL:
 *   - Owner caller is the pinned executor, approved by >50.1% of live DGVE supply
 *   - DGVE holders escrow approval, optionally through revocable voting delegates
 *
 * VRF SUBSCRIPTION LIFECYCLE:
 *   1. Created atomically during constructor call
 *   2. Consumer (Game contract) added automatically during construction
 *   3. Native funding via donateVrf
 *   4. Governed VRF swap via propose/vote/execute
 *   5. Shutdown after GAME-over with native ETH refund
 *
 * GOVERNANCE:
 *   - Admin path: DGVE-approved executor proposes after 44h VRF stall
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

    /// @notice Cancel a VRF subscription and refund remaining native ETH.
    /// @param subId Subscription ID to cancel.
    /// @param to Address to receive the native ETH refund.
    function cancelSubscription(uint256 subId, address to) external;

    /// @notice Create a new VRF subscription.
    /// @return subId The newly created subscription ID.
    function createSubscription() external returns (uint256 subId);

    /// @notice Add native ETH to the subscription.
    function fundSubscriptionWithNative(uint256 subId) external payable;

    /// @notice Get subscription details.
    /// @param subId Subscription ID to query.
    /// @return balance Legacy billing word (unused).
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
    /// @notice Retry an unanswered VRF request once, after the original request's 20-hour timeout.
    function retryRng() external;

    /// @notice Timestamp of the last successfully processed VRF fulfillment.
    function lastVrfProcessed() external view returns (uint48);

    /// @notice Whether the game is in jackpot resolution phase.
    function jackpotPhase() external view returns (bool);

    /// @notice Whether the game has ended.
    function gameOver() external view returns (bool);

    /// @notice Update the VRF coordinator, subscription, key hash and callback gas limit atomically.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New VRF key hash.
    /// @param newCallbackGasLimit Callback gas limit for VRF requests.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash,
        uint32 newCallbackGasLimit
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

    /// @notice Exchange caller-supplied ETH 1:1 for game-held stETH, sending the stETH to recipient.
    /// @param recipient Address to receive stETH.
    /// @param amount Amount of ETH to swap.
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable;

}

/// @dev Game interface for minting mid-day RNG credit to native ETH donors.
interface IGameMiddayCredit {
    /// @notice Mint mid-day RNG credit earned by a native ETH donation.
    /// @dev The donation is a paying action: Game registers the donor and returns its ID.
    ///      Reverts (Game `E`) for a new donor past paid admission.
    /// @param to Donor to credit.
    /// @param amount Request credit in wei.
    /// @return id The donor's wallet ID (never 0).
    function creditMiddayRng(address to, uint256 amount) external returns (uint32 id);
}

/// @dev Vault interface for ownership check.
interface IDegenerusVaultOwner {
    /// @notice Checks the pinned DGVE governance executor, as implemented by DegenerusVault.
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev sDGNRS interface for governance voting weight and voting supply.
interface IsDGNRSVotes {
    /// @notice The total sDGNRS supply, as implemented by sDGNRS.
    function totalSupply() external view returns (uint256);
    /// @notice An address's sDGNRS balance, as implemented by sDGNRS.
    function balanceOf(address account) external view returns (uint256);
    /// @notice The circulating sDGNRS eligible to vote, as implemented by sDGNRS.
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
    enum ProposalState { Active, Executed, Killed }

    /// @dev Packed into 3 storage slots (down from 7).
    ///      Weights and snapshot stored as whole tokens (raw / 1e12). Max 1T = fits uint40 (1.1T max).
    ///      createdAt as uint40 = max year ~36,847.
    ///      Slot 1: proposer(4) + createdAt(5) + votingSnapshot(5) + path(1) + state(1)
    ///              + callbackGasLimit(4) = 20 bytes
    ///      Slot 2: coordinator(20) + approveWeight(5) + rejectWeight(5) = 30 bytes
    ///      Slot 3: keyHash(32) = 32 bytes
    struct Proposal {
        uint32 proposer;              // slot 1: who proposed
        uint40 createdAt;              // slot 1: block.timestamp at creation
        uint40 votingSnapshot;         // slot 1: voting sDGNRS at proposal time (whole tokens)
        ProposalPath path;             // slot 1: Admin or Community
        ProposalState state;           // slot 1: Active, Executed, or Killed (expiry computed live from createdAt)
        uint32 callbackGasLimit;       // slot 1: proposed VRF callback gas limit
        address coordinator;           // slot 2: proposed VRF coordinator
        uint40 approveWeight;          // slot 2: cumulative sDGNRS approve weight (whole tokens)
        uint40 rejectWeight;           // slot 2: cumulative sDGNRS reject weight (whole tokens)
        bytes32 keyHash;               // slot 3: proposed VRF key hash
    }

    // =========================================================================
    // CUSTOM ERRORS
    // =========================================================================

    /// @notice Thrown when the caller is not the DGVE governance executor.
    error NotOwner();
    /// @notice Thrown when the caller is not the address a function is restricted to
    ///         (the game contract or vault owner, depending on the call).
    error NotAuthorized();
    /// @notice Thrown when a proposed coordinator, key hash or callback gas limit is zero.
    error ZeroAddress();
    error InvalidRecipient();
    /// @notice Thrown when a coordinator-swap proposal is filed before its
    ///         path's minimum stall duration has elapsed.
    error NotStalled();
    /// @notice Thrown when a coordinator swap is proposed before a VRF subscription is wired.
    error NotWired();
    /// @notice Thrown when a native ETH donation arrives with no VRF subscription wired.
    error NoSubscription();
    /// @notice Thrown when a swap, donation, or native ETH forward amount is zero, or the forward
    ///         itself fails.
    error InvalidAmount();
    /// @notice Thrown when a recovery call names the live coordinator/subscription pair
    ///         instead of a retired one.
    error SubscriptionActive();
    /// @notice Thrown when a native ETH transfer returns false.
    error TransferFailed();
    /// @notice Thrown when a call that requires the game still running is made after game over.
    error GameOver();
    /// @notice Thrown when a vote or execution targets a proposal that is not active.
    error ProposalNotActive();
    /// @notice Thrown when a vote or execution targets a proposal past its lifetime.
    error ProposalExpired();
    /// @notice Thrown when a community-path proposer's voting sDGNRS stake is below the
    ///         required minimum.
    error InsufficientStake();
    /// @notice Thrown when the proposer (or, on the admin path, the vault) already has an
    ///         active proposal.
    error AlreadyHasActiveProposal();

    // =========================================================================
    // EVENTS
    // =========================================================================

    /// @notice Emitted when the wired VRF coordinator and subscription are set or swapped.
    /// @param coordinator The coordinator now in effect.
    /// @param subId The subscription now in effect.
    event CoordinatorUpdated(
        address indexed coordinator,
        uint256 indexed subId
    );
    /// @notice Emitted when the game contract is registered as a consumer on the VRF subscription.
    /// @param consumer The registered consumer address.
    event ConsumerAdded(address indexed consumer);
    /// @notice Emitted when a new VRF subscription is created.
    /// @param subId The created subscription ID.
    event SubscriptionCreated(uint256 indexed subId);
    /// @notice Emitted when a VRF subscription is cancelled.
    /// @param subId The cancelled subscription ID.
    /// @param to Address the coordinator refunds any remaining subscription balance to.
    event SubscriptionCancelled(uint256 indexed subId, address indexed to);

    /// @notice Emitted when a retired subscription's native ETH is routed onward. A failed forward
    ///         reverts the call, so the event never reports zero.
    /// @param subId The retired subscription the native ETH was recovered from.
    /// @param to Where the recovered native ETH was routed: the live subscription while the game
    ///        runs, the vault after game over.
    /// @param amount native ETH amount routed.
    event SubscriptionRecovered(
        uint256 indexed subId,
        address indexed to,
        uint256 amount
    );
    /// @notice Emitted when the VRF subscription is cancelled and its native ETH swept at game over.
    /// @param subId The subscription cancelled.
    /// @param to The vault address the swept native ETH is sent to.
    /// @param sweptAmount native ETH balance forwarded (0 if there was nothing to sweep or the
    ///        forward failed).
    event SubscriptionShutdown(
        uint256 indexed subId,
        address indexed to,
        uint256 sweptAmount
    );

    // Governance events
    /// @notice Emitted when a VRF coordinator-swap proposal is filed.
    /// @param proposalId The new proposal's ID.
    /// @param proposer The ordinary wallet ID that filed the proposal.
    /// @param coordinator The proposed VRF coordinator.
    /// @param keyHash The proposed VRF key hash.
    /// @param callbackGasLimit The proposed VRF callback gas limit.
    /// @param path The proposal's path (Admin or Community).
    event ProposalCreated(
        uint256 indexed proposalId,
        uint32 indexed proposer,
        address coordinator,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        ProposalPath path
    );
    /// @notice Emitted when a vote is cast on a coordinator-swap proposal.
    /// @param proposalId The proposal voted on.
    /// @param voter The ordinary wallet ID casting the vote.
    /// @param approve True to approve, false to reject.
    /// @param weight The voter's sDGNRS weight (wei) applied to the vote.
    event VoteCast(
        uint256 indexed proposalId,
        uint32 indexed voter,
        bool approve,
        uint256 weight
    );
    /// @notice Emitted when a coordinator-swap proposal passes and executes.
    /// @param proposalId The executed proposal's ID.
    /// @param coordinator The new VRF coordinator now wired.
    /// @param newSubId The new VRF subscription created for it.
    event ProposalExecuted(
        uint256 indexed proposalId,
        address coordinator,
        uint256 newSubId
    );
    /// @notice Emitted when a coordinator-swap proposal is killed — voted down, or found moot
    ///         because VRF recovered before it could execute.
    /// @param proposalId The killed proposal's ID.
    event ProposalKilled(uint256 indexed proposalId);

    // =========================================================================
    // PRECOMPUTED ADDRESSES
    // =========================================================================

    IVRFCoordinatorV2_5Owner internal constant vrfCoordinator =
        IVRFCoordinatorV2_5Owner(ContractAddresses.VRF_COORDINATOR);
    IDegenerusGameAdmin internal constant gameAdmin =
        IDegenerusGameAdmin(ContractAddresses.GAME);
    IsDGNRSVotes internal constant sDGNRS =
        IsDGNRSVotes(ContractAddresses.SDGNRS);

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

    /// @dev One vote direction + weight lane (6 bytes).
    struct VoterRecord {
        Vote v;     // vote direction
        uint40 w;   // weight at time of vote (whole tokens)
    }

    /// @dev Five voter lanes per word per proposal, indexed by ordinary wallet ID / 5.
    mapping(uint256 => mapping(uint32 => uint256)) private voterRecords;

    /// @notice Vote direction per voter per proposal.
    function votes(uint256 proposalId, address voter) external view returns (Vote) {
        return _voterRecord(voterRecords[proposalId], _governanceId(voter)).v;
    }

    /// @notice Vote weight recorded at time of vote (whole tokens).
    function voteWeight(uint256 proposalId, address voter) external view returns (uint40) {
        return _voterRecord(voterRecords[proposalId], _governanceId(voter)).w;
    }

    /// @dev Five 48-bit vote records per word. IDs always belong to msg.sender's ordinary wallet.
    function _voterRecord(mapping(uint32 => uint256) storage records, uint32 id)
        private view returns (VoterRecord memory record)
    {
        uint256 lane = records[id / 5] >> ((id % 5) * 48);
        record.v = Vote(uint8(lane));
        record.w = uint40(lane >> 8);
    }

    function _setVoterRecord(mapping(uint32 => uint256) storage records, uint32 id, Vote direction, uint40 weight) private {
        uint256 shift = (id % 5) * 48;
        uint256 lane = uint256(uint8(direction)) | (uint256(weight) << 8);
        records[id / 5] = (records[id / 5] & ~(uint256(type(uint48).max) << shift)) | (lane << shift);
    }

    function _governanceId(address wallet) private view returns (uint32) {
        return IDegenerusGame(ContractAddresses.GAME).walletIdentityOf(wallet);
    }

    /// @dev No account selector: voting weight and identity both belong to the caller.
    ///      Past free admission the caller must first register through a qualifying paid Game door.
    function _registerGovernanceCaller() private returns (uint32) {
        return IDegenerusGame(ContractAddresses.GAME).registerWalletIdentity(msg.sender);
    }

    /// @notice Tracks each address's current active proposal ID (0 = none).
    mapping(uint32 => uint256) private _activeProposalId;

    function activeProposalId(address proposer) external view returns (uint256) {
        return _activeProposalId[proposer == ContractAddresses.OWNER_GOVERNANCE ? 1 : _governanceId(proposer)];
    }

    /// @dev Epoch cutoff: proposals with id < validFromId were superseded by an executed swap and can
    ///      no longer vote or execute (they keep state == Active in storage). Advanced to
    ///      proposalCount + 1 on every execution, invalidating all prior competitors in O(1).
    uint256 private validFromId;

    // =========================================================================
    // GOVERNANCE CONSTANTS
    // =========================================================================

    /// @dev Minimum VRF stall before admin can propose. lastVrfProcessed only advances on the
    ///      once-per-day RNG, so block.timestamp - lastVrfProcessed sawtooths up to ~24h every
    ///      healthy cycle; the threshold must clear a full cycle or it trips daily. 44h = one
    ///      ~24h cycle + 20h genuine-stall grace, so it fires only ~20h after a daily RNG is
    ///      actually missed, never during normal operation.
    uint256 private constant ADMIN_STALL_THRESHOLD = 44 hours;

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

    /// @notice Creates the VRF subscription, wires the game as its consumer, and wires the
    ///         coordinator config into the game contract.
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

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "admin.degenerus.eth")
            );
            ok;
        }
    }

    /// @dev Only a cancellation performed by this contract may retain a live refund.
    /// Transient routing adds no persistent accounting or storage layout slot.
    address transient private refundSource;

    /// @notice Plain ETH goes to the Vault; live cancellation refunds fund the replacement.
    receive() external payable {
        if (msg.value == 0 || msg.sender == refundSource) return;
        (bool ok, ) = payable(ContractAddresses.VAULT).call{value: msg.value}("");
        if (!ok) revert TransferFailed();
    }

    // =========================================================================
    // LIQUIDITY MANAGEMENT
    // =========================================================================

    /// @notice Exchange supplied ETH 1:1 for game-held stETH, paid to the approved recipient.
    /// @dev Forwards msg.value; the game keeps the ETH and transfers the same nominal stETH.
    function swapGameEthForStEth(address recipient) external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        if (recipient == address(0) || recipient == ContractAddresses.OWNER_GOVERNANCE) revert InvalidRecipient();
        gameAdmin.adminSwapEthForStEth{value: msg.value}(recipient, msg.value);
    }

    // =========================================================================
    // VRF COORDINATOR SWAP GOVERNANCE
    // =========================================================================

    /// @notice Retry the game's unanswered VRF request without changing its committed inputs.
    /// @dev The game enforces the 20-hour timeout, one retry per request and terminal precedence.
    function retryGameRng() external onlyOwner {
        gameAdmin.retryRng();
    }

    /// @notice Propose an emergency VRF coordinator swap.
    /// @dev Two paths:
    ///      - Admin path: DGVE governance executor, requires 20h+ VRF stall
    ///      - Community path: 0.5%+ voting sDGNRS, requires 7d+ VRF stall
    /// @param newCoordinator Address of the proposed VRF coordinator.
    /// @param newKeyHash Key hash for the proposed coordinator.
    /// @param newCallbackGasLimit VRF callback gas limit after the swap. VRF checks the
    ///        subscription's native ETH against the cost at this cap, so keep it near the measured need.
    /// @return proposalId The ID of the created proposal.
    function propose(
        address newCoordinator,
        bytes32 newKeyHash,
        uint32 newCallbackGasLimit
    ) external returns (uint256 proposalId) {
        if (subscriptionId == 0) revert NotWired();
        if (gameAdmin.gameOver()) revert GameOver();
        if (newCoordinator == address(0) || newKeyHash == bytes32(0) || newCallbackGasLimit == 0)
            revert ZeroAddress();

        // 1-per-address active proposal limit. A slot pointing at a superseded proposal
        // (id < validFromId) no longer blocks: the proposer may file afresh.
        bool ownerPath = vault.isVaultOwner(msg.sender);
        uint32 proposerId = ownerPath ? 1 : _registerGovernanceCaller();
        uint256 existing = _activeProposalId[proposerId];
        if (existing >= validFromId && existing != 0) {
            Proposal storage ep = proposals[existing];
            if (_isActiveProposal(ep.state, ep.createdAt, PROPOSAL_LIFETIME)) {
                revert AlreadyHasActiveProposal();
            }
        }

        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        uint256 stall = block.timestamp - uint256(lastVrf);

        uint256 circ = sDGNRS.votingSupply();
        ProposalPath path;
        if (ownerPath) {
            if (stall < ADMIN_STALL_THRESHOLD) revert NotStalled();
            path = ProposalPath.Admin;
        } else {
            if (stall < COMMUNITY_STALL_THRESHOLD) revert NotStalled();
            if (circ == 0 || sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS)
                revert InsufficientStake();
            path = ProposalPath.Community;
        }

        proposalId = ++proposalCount;
        Proposal storage p = proposals[proposalId];
        p.proposer = proposerId;
        p.createdAt = uint40(block.timestamp);
        p.path = path;
        // p.state = ProposalState.Active (default 0)
        p.coordinator = newCoordinator;
        p.keyHash = newKeyHash;
        p.callbackGasLimit = newCallbackGasLimit;
        p.votingSnapshot = uint40(circ / 1e12);

        _activeProposalId[proposerId] = proposalId;

        emit ProposalCreated(proposalId, proposerId, newCoordinator, newKeyHash, newCallbackGasLimit, path);
    }

    /// @notice Vote on an active VRF swap proposal.
    /// @dev Votes are changeable. After recording, checks execute/kill conditions.
    ///      On VRF recovery after creation (a word fulfilled since createdAt), the proposal is
    ///      auto-killed rather than executed — this IS the auto-cancellation.
    ///      Zero-weight calls (no sDGNRS) skip vote recording and just check
    ///      execute/kill conditions — allows anyone to poke a proposal past threshold.
    /// @param proposalId ID of the proposal to vote on.
    /// @param approve True to approve, false to reject.
    function vote(uint256 proposalId, bool approve) external {
        Proposal storage p = proposals[proposalId];
        uint40 createdAt = p.createdAt;
        // A prior executed swap advances validFromId, invalidating every earlier proposal in O(1);
        // such superseded proposals keep state == Active but can no longer vote or execute.
        if (proposalId < validFromId) revert ProposalNotActive();
        _requireActiveProposal(p.state, createdAt, PROPOSAL_LIFETIME);

        // Invalidate (KILL) the proposal if VRF is healthy NOW, or if any VRF word was fulfilled
        // AFTER this proposal was created (lastVrf > createdAt). A proposal exists only to swap a
        // DEAD coordinator; a fulfillment past creation means a recovery occurred, so the proposal
        // must not linger and resume voting on a later re-stall at a further-decayed (age-keyed)
        // threshold. The recovery check is recovery-proof even if no one poked during the recovery
        // window, since it compares against the persistent lastVrfProcessed. Anyone can poke this.
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (
            block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD ||
            uint256(lastVrf) > uint256(createdAt)
        ) {
            p.state = ProposalState.Killed;
            emit ProposalKilled(proposalId);
            return;
        }

        // Record vote only if caller has sDGNRS; otherwise skip to threshold checks (poke)
        // Safe: VRF dead = supply frozen (no advances, unwrapTo blocked)
        (uint40 aw, uint40 rw) = (p.approveWeight, p.rejectWeight);
        uint40 weight = _voterWeight();
        if (weight != 0) {
            uint32 voterId = _registerGovernanceCaller();
            VoterRecord memory vr = _voterRecord(voterRecords[proposalId], voterId);
            (aw, rw) = _applyVote(approve, weight, vr.v, vr.w, aw, rw);
            (p.approveWeight, p.rejectWeight) = (aw, rw);
            _setVoterRecord(voterRecords[proposalId], voterId, approve ? Vote.Approve : Vote.Reject, weight);
            emit VoteCast(proposalId, voterId, approve, uint256(weight) * 1e12);
        }

        Resolution r = _resolveThreshold(
            aw, rw, p.votingSnapshot, _thresholdFrom(createdAt)
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
        return _thresholdFrom(proposals[proposalId].createdAt);
    }

    /// @dev Threshold decay ladder keyed on the proposal's creation time.
    function _thresholdFrom(uint40 createdAt) private view returns (uint16) {
        uint256 elapsed = block.timestamp - uint256(createdAt);
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
        uint40 createdAt = p.createdAt;
        if (proposalId < validFromId) return false;
        if (!_isActiveProposal(p.state, createdAt, PROPOSAL_LIFETIME)) return false;

        // Stall check + recovery-spanning invalidation (mirrors vote(): a fulfillment after
        // creation means a recovery occurred, so the proposal is dead).
        uint48 lastVrf = gameAdmin.lastVrfProcessed();
        if (
            block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD ||
            uint256(lastVrf) > uint256(createdAt)
        ) return false;

        return _resolveThreshold(
            p.approveWeight, p.rejectWeight, p.votingSnapshot, _thresholdFrom(createdAt)
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

    /// @dev Get voter's sDGNRS weight as whole tokens. Sub-token balances have no vote weight.
    function _voterWeight() private view returns (uint40) {
        return uint40(sDGNRS.balanceOf(msg.sender) / 1e12);
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
    // Intentional: lastVrfProcessed is NOT reset here — the old stall
    // timestamp carries over so governance can rapidly re-swap if the new
    // coordinator also fails, without waiting for a fresh stall window.
    function _executeSwap(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        p.state = ProposalState.Executed;

        // Invalidate all competing proposals by advancing the epoch cutoff past every existing ID,
        // before external calls (CEI). O(1) and independent of history size — no loop can gas-strand a
        // coordinator swap. Superseded proposals (id < validFromId) keep state == Active but can no
        // longer vote or execute; the freed proposer can re-propose against the current VRF state.
        validFromId = proposalCount + 1;

        address newCoordinator = p.coordinator;
        bytes32 newKeyHash = p.keyHash;

        uint256 oldSub = subscriptionId;
        address oldCoord = coordinator;

        // Cancellation may fail while an old request remains pending. Governance can recover
        // that retired subscription later. A successful native refund stays here for funding;
        // without one, Game refills the replacement before its reissue.
        if (oldSub != 0 && oldCoord.code.length != 0) {
            refundSource = oldCoord;
            bool cancelled = BoundedCall.callValueFixed(oldCoord, 0, 450_000,
                abi.encodeWithSelector(IVRFCoordinatorV2_5Owner.cancelSubscription.selector, oldSub, address(this)));
            refundSource = address(0);
            if (cancelled) emit SubscriptionCancelled(oldSub, address(this));
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

        // Fund before the Game can issue the replacement request. A failure rolls back the swap.
        uint256 bal = address(this).balance;
        if (bal != 0) IVRFCoordinatorV2_5Owner(newCoordinator).fundSubscriptionWithNative{value: bal}(newSubId);

        // 4. Push new config to Game
        gameAdmin.updateVrfCoordinatorAndSub(
            newCoordinator,
            newSubId,
            newKeyHash,
            p.callbackGasLimit
        );

        emit ProposalExecuted(proposalId, newCoordinator, newSubId);
    }

    // =========================================================================
    // VRF SHUTDOWN (Game-Over)
    // =========================================================================

    /// @notice Cancel the subscription at game over; the coordinator refunds the Vault.
    /// @dev Broken external coordinators are skipped, including gas-burning implementations.
    function shutdownVrf() external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        uint256 subId = subscriptionId;
        if (subId == 0) return;
        subscriptionId = 0;
        address target = ContractAddresses.VAULT;
        uint256 beforeBalance = target.balance;
        bool cancelled = BoundedCall.callValueFixed(coordinator, 0, 450_000,
            abi.encodeWithSelector(IVRFCoordinatorV2_5Owner.cancelSubscription.selector, subId, target));
        if (cancelled) emit SubscriptionCancelled(subId, target);
        emit SubscriptionShutdown(subId, target, target.balance - beforeBalance);
    }

    /// @notice Recover a retired subscription atomically; live funds replenish VRF, final funds go to the Vault.
    function retrySubCancel(address retiredCoordinator, uint256 subId) external {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        if (retiredCoordinator == coordinator && subId == subscriptionId) revert SubscriptionActive();
        bool ended = gameAdmin.gameOver();
        address target = ended ? ContractAddresses.VAULT : coordinator;
        uint256 beforeBalance = ended ? target.balance : address(this).balance;
        if (!ended) refundSource = retiredCoordinator;
        IVRFCoordinatorV2_5Owner(retiredCoordinator).cancelSubscription(subId, ended ? target : address(this));
        refundSource = address(0);
        uint256 recovered = (ended ? target.balance : address(this).balance) - beforeBalance;
        if (!ended && recovered != 0) {
            IVRFCoordinatorV2_5Owner(target).fundSubscriptionWithNative{value: recovered}(subscriptionId);
        }
        emit SubscriptionRecovered(subId, target, recovered);
    }

    /// @notice Fund VRF with native ETH and bank floor(msg.value / 4) wei of request credit.
    /// @dev Funding and donor registration are atomic. Plain ETH earns no credit.
    function donateVrf() external payable {
        if (msg.value == 0) revert InvalidAmount();
        uint256 subId = subscriptionId;
        if (subId == 0) revert NoSubscription();
        if (gameAdmin.gameOver()) revert GameOver();
        IVRFCoordinatorV2_5Owner(coordinator).fundSubscriptionWithNative{value: msg.value}(subId);
        IGameMiddayCredit(ContractAddresses.GAME).creditMiddayRng(msg.sender, msg.value / 4);
    }
}
