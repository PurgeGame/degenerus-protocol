// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";

/// @dev Minimal slices of the live protocol surfaces this faucet reads.
interface IGameLevel {
    function level() external view returns (uint24);
}

interface IAffiliateScore {
    /// @return score Direct affiliate base earnings for `player` at `lvl`, in FLIP base units (18 decimals).
    function affiliateScore(uint24 lvl, address player) external view returns (uint256 score);
}

interface IVaultOwnership {
    /// @return True if `account` holds >50.1% of DGVE supply (the live "vault owner" role).
    function isVaultOwner(address account) external view returns (bool);
}

/// @title DegenerusGasFaucet
/// @notice A standalone donation-funded faucet that hands out a tiny, fixed amount of ETH
///         ("gas dust") to affiliates who have earned rewards in the current level but hold
///         zero ETH — just enough to afford a single redemption / Uniswap transaction.
/// @dev Authority is the live protocol vault-owner role (the >50.1% DGVE holder, read from the
///      VAULT), plus any addresses that owner approves as distributors. The vault owner alone
///      tunes parameters, manages approvals, and recovers donated ETH.
///
///      Qualification (all must hold, evaluated at call time):
///        1. !hasReceived[recipient]                                 (never funded before — one use per address)
///        2. recipient.balance == 0                                  (holds no ETH)
///        3. affiliateScore(currentLevel, recipient) >= minAffiliateScore   (>= 1,000 FLIP, this level)
///
///      Dispense amount = gasPerTx * gasPriceWei, i.e. the gas cost of one redemption / swap
///      transaction priced at the configured gas price (default 0.25 gwei). All three knobs are
///      vault-owner tunable so the faucet tracks real network conditions.
///
///      Each top-up is sent with only ~2300 gas (the value-transfer stipend level): an externally-
///      owned account receives it, but a recipient contract cannot run any logic on receipt. Combined
///      with checks-effects-interactions in `distribute`, this makes the faucet reentrancy-safe with
///      no guard. (Owner withdrawals forward full gas, so the treasury sink may be a contract / safe.)
contract DegenerusGasFaucet {
    // -------------------------------------------------------------------------
    // Wiring (compile-time constants patched by the deploy pipeline)
    // -------------------------------------------------------------------------
    address public constant GAME = ContractAddresses.GAME;
    address public constant AFFILIATE = ContractAddresses.AFFILIATE;
    address public constant VAULT = ContractAddresses.VAULT;

    // -------------------------------------------------------------------------
    // Parameters (vault-owner tunable)
    // -------------------------------------------------------------------------
    /// @notice Minimum affiliate score (this level) a recipient must hold to qualify. 1,000 FLIP.
    uint256 public minAffiliateScore = 1_000e18;
    /// @notice Gas units one redemption / Uniswap tx is budgeted for.
    uint256 public gasPerTx = 350_000;
    /// @notice Gas price used to size the top-up. 0.25 gwei = 250,000,000 wei.
    uint256 public gasPriceWei = 250_000_000;

    /// @notice Addresses the vault owner has approved to trigger distributions.
    mapping(address => bool) public approvedDistributor;

    /// @notice One-use-per-address cap: true once an address has been funded by this faucet.
    ///         A funded address never qualifies again, on any level.
    mapping(address => bool) public hasReceived;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event Donated(address indexed from, uint256 amount);
    event Funded(address indexed recipient, uint24 indexed level, uint256 amount);
    event SendFailed(address indexed recipient, uint256 amount);
    event ApprovedDistributorSet(address indexed distributor, bool approved);
    event ParamsUpdated(uint256 minAffiliateScore, uint256 gasPerTx, uint256 gasPriceWei);
    event Withdrawn(address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error NotAuthorized();
    error NotVaultOwner();
    error ZeroAddress();
    error TransferFailed();
    error NothingToDispense();

    // -------------------------------------------------------------------------
    // Access control
    // -------------------------------------------------------------------------
    /// @dev Restricts to the live vault owner (majority DGVE holder).
    modifier onlyVaultOwner() {
        if (!IVaultOwnership(VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        _;
    }

    /// @dev Restricts to the vault owner or any distributor the vault owner approved.
    modifier onlyDistributor() {
        if (!approvedDistributor[msg.sender] && !IVaultOwnership(VAULT).isVaultOwner(msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------
    /// @notice The exact ETH amount handed to each qualifying recipient.
    function dispenseAmount() public view returns (uint256) {
        return gasPerTx * gasPriceWei;
    }

    /// @notice True if `recipient` currently qualifies for a top-up: never funded before,
    ///         holds zero ETH, and has enough affiliate score this level.
    function qualifies(address recipient) public view returns (bool) {
        if (hasReceived[recipient]) return false;
        if (recipient.balance != 0) return false;
        uint24 lvl = IGameLevel(GAME).level();
        return IAffiliateScore(AFFILIATE).affiliateScore(lvl, recipient) >= minAffiliateScore;
    }

    // -------------------------------------------------------------------------
    // Donations
    // -------------------------------------------------------------------------
    /// @notice Accept ETH donations from anyone.
    receive() external payable {
        emit Donated(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // Distribution
    // -------------------------------------------------------------------------
    /// @notice Mass-dispense gas dust to every qualifying recipient in `recipients`.
    /// @dev Non-qualifying recipients (already funded once, hold ETH, or below the affiliate-score
    ///      threshold this level) are silently skipped. The one-use cap (`hasReceived`) makes
    ///      duplicate list entries and self-forwarding harmless — a funded address can never be
    ///      funded twice. The loop stops early once the faucet can no longer cover a full top-up.
    ///
    ///      Reentrancy-safe by construction, no guard needed: the allowance is consumed BEFORE the
    ///      transfer (checks-effects-interactions), and the transfer is a gas-capped low-level call
    ///      (~2300 gas) — enough for an externally-owned account to receive, too little for a
    ///      recipient contract to run any logic, callback, or reentrant call on receipt. A recipient
    ///      that rejects the gas-capped transfer (only a contract can) lands in SendFailed with its
    ///      one allowance already spent, and does not abort the batch.
    /// @param recipients Candidate addresses to evaluate and (if qualifying) fund.
    /// @return funded Number of recipients that received a top-up.
    function distribute(address[] calldata recipients)
        external
        onlyDistributor
        returns (uint256 funded)
    {
        uint256 amount = gasPerTx * gasPriceWei;
        if (amount == 0) revert NothingToDispense();
        uint24 lvl = IGameLevel(GAME).level();

        for (uint256 i = 0; i < recipients.length; ++i) {
            if (address(this).balance < amount) break; // faucet dry — nothing more to give
            address r = recipients[i];
            if (hasReceived[r]) continue; // one use per address
            if (r.balance != 0) continue; // already holds ETH
            if (IAffiliateScore(AFFILIATE).affiliateScore(lvl, r) < minAffiliateScore) continue;

            // Effects before interaction: spend the one-use allowance up front so it can never be
            // re-entered — even though the gas cap below already makes a callback impossible.
            hasReceived[r] = true;

            // Forward only ~2300 gas (the value-transfer stipend level): an EOA receives fine, but a
            // recipient contract gets too little to run any logic, callback, or reentrant call.
            (bool ok, ) = r.call{value: amount, gas: 2300}("");
            if (ok) {
                emit Funded(r, lvl, amount);
                unchecked {
                    ++funded;
                }
            } else {
                emit SendFailed(r, amount); // contract rejected the gas-capped transfer; allowance forfeit
            }
        }
    }

    // -------------------------------------------------------------------------
    // Admin (vault owner only)
    // -------------------------------------------------------------------------
    /// @notice Approve or revoke an address as a distributor.
    function setApprovedDistributor(address distributor, bool approved) external onlyVaultOwner {
        if (distributor == address(0)) revert ZeroAddress();
        approvedDistributor[distributor] = approved;
        emit ApprovedDistributorSet(distributor, approved);
    }

    /// @notice Update qualification threshold and top-up sizing.
    function setParams(
        uint256 _minAffiliateScore,
        uint256 _gasPerTx,
        uint256 _gasPriceWei
    ) external onlyVaultOwner {
        minAffiliateScore = _minAffiliateScore;
        gasPerTx = _gasPerTx;
        gasPriceWei = _gasPriceWei;
        emit ParamsUpdated(_minAffiliateScore, _gasPerTx, _gasPriceWei);
    }

    /// @notice Recover donated ETH to `to`. Pass `address(this).balance` to sweep everything;
    ///         forwards full gas so the sink may be a contract / multisig.
    function withdraw(address to, uint256 amount) external onlyVaultOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(to, amount);
    }
}
