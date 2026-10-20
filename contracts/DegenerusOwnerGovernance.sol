// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusVault, DegenerusVaultShare} from "./DegenerusVault.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {IOwnerVault} from "./interfaces/IOwnerActions.sol";
import {OwnerActions} from "./libraries/OwnerActions.sol";

/// @notice DGVE-weighted owner approval with revocable voting-only delegation.
/// @dev Non-upgradeable. Custody belongs to each depositor, never to a voting delegate or majority.
/// All accounting is committed before external calls. The fixed DGVE token has no callbacks;
/// executed actions may call back, but cannot replay an action or withdraw an already cleared position.
contract DegenerusOwnerGovernance {
    uint256 public constant PROPOSAL_LIFETIME = 7 days;
    DegenerusVaultShare public immutable dgve;
    uint32 public proposalCount;
    uint256 public totalEscrowed;

    struct Position {
        uint128 amount;
        uint32 proposalId;
        uint40 assignedBlock;
        uint40 depositBlock;
        address votingDelegate;
    }
    struct Proposal {
        address proposer;
        uint96 value;
        address target;
        uint40 expiresAt;
        uint40 recentBlock;
        bool executed;
        uint128 lockedWeight;
        uint128 recentWeight;
        bytes32 dataHash;
    }
    mapping(address => Position) public positions;
    mapping(uint256 => Proposal) private _proposals;

    error InvalidCollateral();
    error InvalidAmount();
    error PositionExists();
    error NoPosition();
    error NotVotingController();
    error OwnerOnly();
    error InvalidDelegate();
    error AlreadyAssigned();
    error InactiveProposal();
    error ActionNotAllowed();
    error NoMajority();
    error IncorrectValue();
    error DataHashMismatch();
    error InvalidOwnerOrder();
    error TransferFailed();

    event Deposited(address indexed owner, uint256 amount, address indexed votingDelegate);
    event DelegateChanged(address indexed owner, address indexed previousDelegate, address indexed votingDelegate);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address indexed owner,
        address target, uint256 value, bytes data, bytes32 actionHash, uint256 expiresAt);
    event Supported(uint256 indexed proposalId, address indexed owner, address indexed actor, uint256 amount, uint256 assignedBlock);
    event VoteCleared(uint256 indexed proposalId, address indexed owner, address indexed actor, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);
    event Executed(uint256 indexed proposalId, address indexed caller);
    event DirectAction(address indexed caller, bytes4 selector, uint256 value);

    constructor() {
        address token = IOwnerVault(ContractAddresses.VAULT).dgve();
        if (token.code.length == 0) revert InvalidCollateral();
        dgve = DegenerusVaultShare(token);
    }

    function deposit(uint256 amount, address votingDelegate) external {
        if (votingDelegate == msg.sender) revert InvalidDelegate();
        _deposit(msg.sender, amount, votingDelegate);
    }

    function propose(address owner, address target, uint256 value, bytes calldata data, uint256 amount)
        external returns (uint256 proposalId)
    {
        if (value > type(uint96).max) revert IncorrectValue();
        _validateAction(target, data);
        _prepare(owner, amount);
        proposalId = ++proposalCount;
        Proposal storage p = _proposals[proposalId];
        p.proposer = msg.sender;
        p.target = target;
        p.value = uint96(value);
        p.dataHash = keccak256(data);
        p.expiresAt = uint40(block.timestamp + PROPOSAL_LIFETIME);
        bytes32 actionHash = keccak256(abi.encode(block.chainid, address(this), proposalId, target, value, data, p.expiresAt));
        _assign(owner, proposalId);
        emit ProposalCreated(proposalId, msg.sender, owner, target, value, data, actionHash, p.expiresAt);
    }

    function support(address owner, uint256 proposalId, uint256 amount) external {
        _requireActive(proposalId);
        _prepare(owner, amount);
        _assign(owner, proposalId);
    }

    function setVotingDelegate(address votingDelegate) external {
        Position storage pos = positions[msg.sender];
        if (pos.amount == 0) revert NoPosition();
        address previous = pos.votingDelegate;
        if (votingDelegate == msg.sender || votingDelegate == previous) revert InvalidDelegate();
        _clear(msg.sender);
        pos.votingDelegate = votingDelegate;
        emit DelegateChanged(msg.sender, previous, votingDelegate);
    }

    function clearVote(address owner) external {
        _authorize(owner);
        _clear(owner);
    }

    function withdraw() external {
        uint256 amount = positions[msg.sender].amount;
        if (amount == 0) revert NoPosition();
        _clear(msg.sender);
        positions[msg.sender].amount = 0;
        totalEscrowed -= amount;
        if (!dgve.transfer(msg.sender, amount)) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function execute(uint256 proposalId, bytes calldata data) external payable returns (bytes memory result) {
        _requireActive(proposalId);
        Proposal storage p = _proposals[proposalId];
        if (!_hasMajority(_settledWeight(p))) revert NoMajority();
        if (msg.value != p.value) revert IncorrectValue();
        if (keccak256(data) != p.dataHash) revert DataHashMismatch();
        // Target and calldata were validated at creation and cannot be changed.
        if (p.target.code.length == 0) revert ActionNotAllowed();
        p.executed = true;
        bool ok;
        (ok, result) = p.target.call{value: msg.value}(data);
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        emit Executed(proposalId, msg.sender);
    }

    /// @notice Play as the Vault using a majority controlled by this caller, without a proposal.
    /// @dev Only Vault playerAction/spendDegenesis are reachable. Owners must be strictly
    /// sorted; current-block deposits never count, including withdraw/redeposit.
    function directAction(bytes calldata data, address[] calldata owners)
        external payable returns (bytes memory result)
    {
        if (data.length < 4 || (bytes4(data) != DegenerusVault.playerAction.selector
            && bytes4(data) != DegenerusVault.spendDegenesis.selector)) revert ActionNotAllowed();
        uint256 weight;
        address previous;
        for (uint256 i; i < owners.length; ++i) {
            address owner = owners[i];
            if (owner <= previous) revert InvalidOwnerOrder();
            previous = owner;
            _authorize(owner);
            Position storage pos = positions[owner];
            if (pos.depositBlock < block.number) weight += pos.amount;
        }
        if (!_hasMajority(weight)) revert NoMajority();
        bool ok;
        (ok, result) = ContractAddresses.VAULT.call{value: msg.value}(data);
        if (!ok) { assembly ("memory-safe") { revert(add(result, 32), mload(result)) } }
        emit DirectAction(msg.sender, bytes4(data), msg.value);
    }

    function proposal(uint256 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    /// @notice Approval assigned before this block, without enumerating voters or an activation transaction.
    function settledWeight(uint256 proposalId) external view returns (uint256) {
        return _settledWeight(_proposals[proposalId]);
    }

    /// @notice Whether settled approval suffices; target-side conditions may still revert.
    function canExecute(uint256 proposalId) external view returns (bool) {
        Proposal storage p = _proposals[proposalId];
        return p.expiresAt != 0 && !p.executed && block.timestamp < p.expiresAt && _hasMajority(_settledWeight(p));
    }

    function isAllowed(address target, bytes4 selector) external pure returns (bool) {
        return OwnerActions.isAllowed(target, selector);
    }

    function _hasMajority(uint256 weight) private view returns (bool) {
        // floor(supply * 501 / 1000), split before multiplying to avoid overflow at any uint256 supply.
        uint256 supply = dgve.totalSupply();
        uint256 threshold = (supply / 1000) * 501 + ((supply % 1000) * 501) / 1000;
        return weight > threshold;
    }

    function _settledWeight(Proposal storage p) private view returns (uint256) {
        return p.recentBlock == block.number ? p.lockedWeight - p.recentWeight : p.lockedWeight;
    }

    function _validateAction(address target, bytes memory data) private view {
        if (data.length < 4 || target.code.length == 0 || !OwnerActions.isAllowed(target, bytes4(data))) {
            revert ActionNotAllowed();
        }
    }

    function _requireActive(uint256 proposalId) private view {
        Proposal storage p = _proposals[proposalId];
        if (p.expiresAt == 0 || p.executed || block.timestamp >= p.expiresAt) revert InactiveProposal();
    }

    function _authorize(address owner) private view {
        Position storage pos = positions[owner];
        if (pos.amount == 0) revert NoPosition();
        if (msg.sender != owner && msg.sender != pos.votingDelegate) revert NotVotingController();
    }

    function _prepare(address owner, uint256 amount) private {
        if (amount != 0) {
            if (msg.sender != owner) revert OwnerOnly();
            _deposit(owner, amount, address(0));
        }
        _authorize(owner);
        if (positions[owner].proposalId != 0) revert AlreadyAssigned();
    }

    function _deposit(address owner, uint256 amount, address votingDelegate) private {
        if (amount == 0) revert InvalidAmount();
        if (positions[owner].amount != 0) revert PositionExists();
        // DGVE supply is bounded by 1e30. An amount above a real balance makes
        // transferFrom revert, rolling back this cast and all custody accounting.
        positions[owner] = Position(uint128(amount), 0, 0, uint40(block.number), votingDelegate);
        totalEscrowed += amount;
        if (!dgve.transferFrom(owner, address(this), amount)) revert TransferFailed();
        emit Deposited(owner, amount, votingDelegate);
    }

    function _assign(address owner, uint256 proposalId) private {
        Position storage pos = positions[owner];
        pos.proposalId = uint32(proposalId);
        pos.assignedBlock = uint40(block.number);
        Proposal storage p = _proposals[proposalId];
        if (p.recentBlock != block.number) {
            p.recentBlock = uint40(block.number);
            p.recentWeight = 0;
        }
        p.lockedWeight += pos.amount;
        p.recentWeight += pos.amount;
        emit Supported(proposalId, owner, msg.sender, pos.amount, block.number);
    }

    function _clear(address owner) private {
        Position storage pos = positions[owner];
        uint256 proposalId = pos.proposalId;
        if (proposalId == 0) return;
        Proposal storage p = _proposals[proposalId];
        p.lockedWeight -= pos.amount;
        if (pos.assignedBlock == p.recentBlock) p.recentWeight -= pos.amount;
        pos.proposalId = 0;
        pos.assignedBlock = 0;
        emit VoteCleared(proposalId, owner, msg.sender, pos.amount);
    }
}
