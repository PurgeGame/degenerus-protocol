// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame, MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IVaultCoin} from "./interfaces/IVaultCoin.sol";

enum PurchaseKind {
    Player,
    Ticket
}

struct PurchaseParams {
    uint256 quantity;
    PurchaseKind kind;
    MintPaymentKind payKind;
    bool payInCoin;
    bytes32 affiliateCode;
}

interface IDegenerusGamePlayerActions {
    function advanceGame(uint32 cap) external;
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    function openLootBox(address player, uint48 lootboxIndex) external;
    function burnTokens(address player, uint256[] calldata tokenIds) external;
    function claimWinnings(address player) external;
    function claimWinningsStethFirst() external;
    function claimWhalePass(address player) external;
    function setAutoRebuy(address player, bool enabled) external;
    function setAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external;
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external;
    function setOperatorApproval(address operator, bool approved) external;
    function claimableWinningsOf(address player) external view returns (uint256);
}

interface IDegenerusGamepiecesPlayerActions {
    function purchase(PurchaseParams calldata params) external payable;
}

interface IDegenerusCoinPlayerActions {
    function depositCoinflip(address player, uint256 amount) external;
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function claimCoinflipsKeepMultiple(address player, uint256 multiples) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function decimatorBurn(address player, uint256 amount) external;
    function setCoinflipAutoRebuy(address player, bool enabled, uint256 keepMultiple) external;
    function setCoinflipAutoRebuyKeepMultiple(address player, uint256 keepMultiple) external;
}

interface IDegenerusJackpotsPlayerActions {
    function claimDecimatorJackpot(uint24 lvl) external;
}

/*
+========================================================================================================+
|                                        DegenerusVault                                                  |
|                     Multi-Asset Vault with Independent Share Classes                                   |
+========================================================================================================+
|                                                                                                        |
|  ARCHITECTURE OVERVIEW                                                                                 |
|  ---------------------                                                                                 |
|  DegenerusVault holds three asset types with three independent share classes for claims:              |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              ASSET & SHARE MAPPING                                                | |
|  |                                                                                                   | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |   |  ASSETS HELD    |     |  SHARE CLASSES  |                                                     | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |   |  ETH            |----►|  ethShare       |  DGVE - Claims ETH + stETH proportionally           | |
|  |   |  stETH          |----►|  (combined)     |                                                     | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |   |  BURNIE         |----►|  coinShare      |  DGVB - Claims BURNIE only (80% of deposits)        | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |                                                                                                   | |
|  |   DGVA (allShare) claims 20% of combined ETH+stETH deposits and 20% of                            | |
|  |   BURNIE virtual deposits. ETH and stETH are interchangeable for DGVE/DGVA.                       | |
|  |   stETH rebase yield accrues to DGVE only (DGVA does not earn yield).                             | |
|  |   Each share class has independent supply and proportional claim rights.                          | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              DEPOSIT FLOW (Game-Only)                                             | |
|  |                                                                                                   | |
|  |   DegenerusGame ----► deposit() ----► Pulls ETH/stETH, escrows BURNIE mint allowance              | |
|  |                                                                                                   | |
|  |   Split: 20% of ETH+stETH and virtual deposits accrue to DGVA; 80% to existing classes.           | |
|  |   stETH rebase yield accrues to DGVE only.                                                        | |
|  |                                                                                                   | |
|  |   Note: BURNIE uses a "virtual" deposit via vaultEscrow() - no token transfer,                    | |
|  |         just increases the vault's mint allowance on the coin contract.                           | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              CLAIM FLOW (Burn Shares)                                             | |
|  |                                                                                                   | |
|  |   User ----► burnCoin(amount) ----► Burns coinShare ----► Mints BURNIE to user                    | |
|  |   User ----► burnEth(amount) -----► Burns ethShare -----► Sends ETH + stETH to user               | |
|  |   User ----► burnAll(amount) -----► Burns allShare -----► Sends ETH + stETH + BURNIE              | |
|  |                                                                                                   | |
|  |   Formula: claimAmount = (reserveBalance * sharesBurned) / totalShareSupply                       | |
|  |                                                                                                   | |
|  |   REFILL MECHANISM: If user burns ALL shares, 1T new shares are minted to them.                   | |
|  |   This prevents division-by-zero and keeps the share token alive.                                 | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  KEY INVARIANTS                                                                                        |
|  --------------                                                                                        |
|  • Share supply can never reach zero (refill mechanism)                                                |
|  • Only GAME can call deposit; ETH donations are open                                                  |
|  • Only this vault can mint/burn share tokens                                                          |
|  • ETH and stETH are combined for DGVE/DGVA claims (ETH preferred, then stETH)                         |
|  • DGVE claims exclude DGVA's reserved share of the combined pool                                      |
|  • All wiring is constant after construction                                                           |
|                                                                                                        |
+========================================================================================================+*/

// -----------------------------------------------------------------------------
// VAULT SHARE TOKEN
// -----------------------------------------------------------------------------

/// @title DegenerusVaultShare
/// @notice Minimal ERC20 for vault share classes (DGVB, DGVE, DGVA)
/// @dev Only the parent vault can mint/burn. Standard ERC20 transfer/approve for users.
contract DegenerusVaultShare {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    /// @dev Caller is not the authorized vault contract
    error Unauthorized();
    /// @dev Address parameter is zero when non-zero required
    error ZeroAddress();
    /// @dev Insufficient balance or allowance for operation
    error Insufficient();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @dev Standard ERC20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @dev Standard ERC20 Approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // ---------------------------------------------------------------------
    // ERC20 STATE
    // ---------------------------------------------------------------------
    /// @notice Token name (e.g., "Degenerus Vault Burnie")
    string public name;
    /// @notice Token symbol (e.g., "DGVB")
    string public symbol;
    /// @notice Token decimals (always 18)
    uint8 public constant decimals = 18;
    /// @notice Initial share supply (1 trillion tokens)
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @notice Total supply of shares
    uint256 public totalSupply;
    /// @notice Balance of shares per address
    mapping(address => uint256) public balanceOf;
    /// @notice Allowance mapping for transferFrom
    mapping(address => mapping(address => uint256)) public allowance;

    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    /// @dev Restricts function to the parent vault contract
    modifier onlyVault() {
        if (msg.sender != ContractAddresses.VAULT) revert Unauthorized();
        _;
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    /// @notice Deploy a new share token with initial supply
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        totalSupply = INITIAL_SUPPLY;
        balanceOf[ContractAddresses.CREATOR] = INITIAL_SUPPLY;
        emit Transfer(address(0), ContractAddresses.CREATOR, INITIAL_SUPPLY);
    }

    // ---------------------------------------------------------------------
    // ERC20 STANDARD FUNCTIONS
    // ---------------------------------------------------------------------
    /// @notice Approve spender to transfer tokens on behalf of caller
    /// @param spender Address to approve
    /// @param amount Amount to approve (type(uint256).max for unlimited)
    /// @return success Always true
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens to recipient
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success Always true (reverts on failure)
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens from one address to another (requires allowance)
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    /// @return success Always true (reverts on failure)
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert Insufficient();
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------
    // VAULT-CONTROLLED MINT/BURN
    // ---------------------------------------------------------------------
    /// @notice Mint new shares to recipient (vault only)
    /// @dev Used for refill mechanism when all shares are burned
    /// @param to Recipient address
    /// @param amount Amount to mint
    function vaultMint(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount; // Safe: totalSupply checked, so this can't overflow
        }
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn shares from holder (vault only)
    /// @dev Used when users claim underlying assets
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function vaultBurn(address from, uint256 amount) external onlyVault {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount; // Safe: amount <= bal verified above
            totalSupply -= amount; // Safe: sum(balances) == totalSupply invariant
        }
        emit Transfer(from, address(0), amount);
    }

    // ---------------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------------
    /// @dev Internal transfer logic with balance checks
    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        if (from == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount; // Safe: amount <= bal verified above
            balanceOf[to] += amount; // Safe: total supply is constant, can't overflow
        }
        emit Transfer(from, to, amount);
    }
}

// -----------------------------------------------------------------------------
// MAIN VAULT CONTRACT
// -----------------------------------------------------------------------------

/// @title DegenerusVault
/// @notice Multi-asset vault with four independent share classes for claiming different assets
/// @dev See contract header for full architecture documentation
contract DegenerusVault {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    /// @dev Caller is not authorized (not ContractAddresses.GAME contract)
    error Unauthorized();
    /// @dev Caller does not control enough DGVE to manage vault gameplay.
    error NotVaultOwner();
    /// @dev Insufficient balance, allowance, or reserve for operation
    error Insufficient();
    /// @dev ETH or token transfer failed
    error TransferFailed();
    /// @dev Caller is not approved to act for the player.
    error NotApproved();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @notice Emitted when assets are deposited into the vault
    /// @param from Depositor address (typically ContractAddresses.GAME contract)
    /// @param ethAmount ETH deposited (via msg.value)
    /// @param stEthAmount stETH pulled from depositor
    /// @param coinAmount BURNIE mint allowance escrowed (virtual deposit)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stEthAmount, uint256 coinAmount);
    /// @notice Emitted when user burns shares to claim ETH/stETH/BURNIE
    /// @param from User who burned shares
    /// @param sharesBurned Amount of shares burned
    /// @param ethOut ETH sent to user
    /// @param stEthOut stETH sent to user
    /// @param coinOut BURNIE minted to user
    event Claim(address indexed from, uint256 sharesBurned, uint256 ethOut, uint256 stEthOut, uint256 coinOut);
    /// @notice Emitted when user burns DGVA shares to claim ETH/stETH/BURNIE
    /// @param from User who burned shares
    /// @param sharesBurned Amount of DGVA shares burned
    /// @param ethOut ETH sent to user
    /// @param stEthOut stETH sent to user
    /// @param coinOut BURNIE minted to user
    event ClaimAll(
        address indexed from,
        uint256 sharesBurned,
        uint256 ethOut,
        uint256 stEthOut,
        uint256 coinOut
    );
    /// @notice Emitted when DGNRS shares are minted as a reward
    /// @param to Recipient of the reward
    /// @param amount Amount of DGNRS shares minted
    event DgnrsReward(address indexed to, uint256 amount);

    // ---------------------------------------------------------------------
    // CONSTANTS
    // ---------------------------------------------------------------------
    /// @notice Vault metadata name
    string public constant name = "Degenerus Vault";
    /// @notice Vault metadata symbol
    string public constant symbol = "DGV";
    /// @notice Vault metadata decimals
    uint8 public constant decimals = 18;
    /// @dev Supply minted when all shares are burned (keeps token alive)
    uint256 private constant REFILL_SUPPLY = 1_000_000_000_000 * 1e18;
    /// @dev DGVA share of deposits: 20% (amount / 5)
    uint256 private constant DGVA_SPLIT_DIVISOR = 5;

    // ---------------------------------------------------------------------
    // SHARE CLASS TOKENS (Immutable)
    // ---------------------------------------------------------------------
    /// @notice Share token for BURNIE claims (symbol: DGVB)
    DegenerusVaultShare private immutable coinShare;
    /// @notice Share token for ETH+stETH claims (symbol: DGVE)
    DegenerusVaultShare private immutable ethShare;
    /// @notice Share token for 20% multi-asset claims (symbol: DGNRS)
    DegenerusVaultShare private immutable allShare;

    // ---------------------------------------------------------------------
    // WIRING (Constants)
    // ---------------------------------------------------------------------
    /// @dev Game contract for operator approvals
    IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);
    /// @dev Game contract for player actions
    IDegenerusGamePlayerActions internal constant gamePlayer =
        IDegenerusGamePlayerActions(ContractAddresses.GAME);
    /// @dev Gamepieces contract for player actions
    IDegenerusGamepiecesPlayerActions internal constant gamepiecesPlayer =
        IDegenerusGamepiecesPlayerActions(ContractAddresses.GAMEPIECES);
    /// @dev Coin contract for player actions
    IDegenerusCoinPlayerActions internal constant coinPlayer =
        IDegenerusCoinPlayerActions(ContractAddresses.COIN);
    /// @dev Jackpots contract for player claims
    IDegenerusJackpotsPlayerActions internal constant jackpotsPlayer =
        IDegenerusJackpotsPlayerActions(ContractAddresses.JACKPOTS);
    /// @dev BURNIE token address (implements IVaultCoin)
    IVaultCoin internal constant coinToken = IVaultCoin(ContractAddresses.COIN);
    /// @dev stETH token address (Lido)
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    // ---------------------------------------------------------------------
    // RESERVE TRACKING (DGVA SPLIT)
    // ---------------------------------------------------------------------
    /// @dev Combined ETH+stETH reserved for DGVA claims (20% of deposits)
    uint256 private dgvaEthReserve;
    /// @dev BURNIE reserved for DGVA claims (20% of virtual deposits)
    uint256 private dgvaCoinReserve;
    /// @dev Tracked total BURNIE allowance (for split accounting)
    uint256 private coinTracked;


    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    /// @dev Restricts function to the ContractAddresses.GAME contract
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    modifier onlyVaultOwner() {
        if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();
        _;
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }

    function _isVaultOwner(address account) private view returns (bool) {
        uint256 supply = ethShare.totalSupply();
        uint256 balance = ethShare.balanceOf(account);
        return balance * 10 > supply * 3;
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    /// @notice Deploy the vault with all required addresses.
    /// @dev Deploys the share tokens using precomputed addresses from ContractAddresses.
    constructor() {
        // Deploy share class tokens - creator receives initial 1T supply of each
        coinShare = new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB");
        ethShare = new DegenerusVaultShare("Degenerus Vault Eth", "DGVE");
        allShare = new DegenerusVaultShare("Degenerus Stonk", "DGNRS");

        uint256 coinAllowance = coinToken.vaultMintAllowance();
        coinTracked = coinAllowance;
        dgvaCoinReserve = coinAllowance / DGVA_SPLIT_DIVISOR;

    }

    // ---------------------------------------------------------------------
    // DEPOSITS (Game-Only)
    // ---------------------------------------------------------------------

    /// @notice Deposit ETH, stETH, and/or BURNIE mint allowance into the vault
    /// @dev Game contract only. BURNIE uses virtual deposit (escrows mint allowance, no transfer).
    ///      ETH is received via msg.value, stETH is pulled via transferFrom.
    ///      20% of ETH+stETH and virtual deposits accrue to DGVA; ETH/stETH interchangeable for DGVE/DGVA.
    /// @param coinAmount BURNIE mint allowance to escrow (virtual deposit)
    /// @param stEthAmount stETH to pull from caller
    function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame {
        if (coinAmount != 0) {
            _syncCoinReserves();
            coinToken.vaultEscrow(coinAmount);
            uint256 dgvaShare = coinAmount / DGVA_SPLIT_DIVISOR;
            dgvaCoinReserve += dgvaShare;
            coinTracked += coinAmount;
        }
        _pullSteth(msg.sender, stEthAmount);
        uint256 combinedIn = msg.value + stEthAmount;
        if (combinedIn != 0) {
            dgvaEthReserve += combinedIn / DGVA_SPLIT_DIVISOR;
        }
        emit Deposit(msg.sender, msg.value, stEthAmount, coinAmount);
    }

    /// @notice Receive ETH deposits (e.g., from game contract)
    /// @dev Anyone can send ETH; splits 20% to DGVA and 80% to DGVE (combined pool)
    receive() external payable {
        if (msg.value != 0) {
            dgvaEthReserve += msg.value / DGVA_SPLIT_DIVISOR;
        }
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    // ---------------------------------------------------------------------
    // DGNRS REWARD MINTING (Game-Only)
    // ---------------------------------------------------------------------

    /// @notice Mint DGNRS shares as a reward to a recipient
    /// @dev Game contract only. Allows rewarding players with vault shares.
    ///      DGNRS shares represent claims on 20% of vault's ETH+stETH and BURNIE reserves.
    /// @param to Recipient address
    /// @param amount Amount of DGNRS shares to mint (18 decimals)
    function mintDgnrsReward(address to, uint256 amount) external onlyGame {
        if (amount == 0) return;
        allShare.vaultMint(to, amount);
        emit DgnrsReward(to, amount);
    }

    // ---------------------------------------------------------------------
    // GAMEPLAY (Vault Owner)
    // ---------------------------------------------------------------------

    function gameAdvance(uint32 cap) external onlyVaultOwner {
        gamePlayer.advanceGame(cap);
    }

    function gamePurchase(
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) external payable onlyVaultOwner {
        uint256 totalValue = _combinedValue(ethValue);
        gamePlayer.purchase{value: totalValue}(
            address(this),
            gamepieceQuantity,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner {
        gamePlayer.openLootBox(address(this), lootboxIndex);
    }

    function gameBurnTokens(uint256[] calldata tokenIds) external onlyVaultOwner {
        gamePlayer.burnTokens(address(this), tokenIds);
    }

    function gameClaimWinnings() external onlyVaultOwner {
        gamePlayer.claimWinningsStethFirst();
    }

    function gameClaimWhalePass() external onlyVaultOwner {
        gamePlayer.claimWhalePass(address(this));
    }

    function gameSetAutoRebuy(bool enabled) external onlyVaultOwner {
        gamePlayer.setAutoRebuy(address(this), enabled);
    }

    function gameSetAutoRebuyKeepMultiple(uint256 keepMultiple) external onlyVaultOwner {
        gamePlayer.setAutoRebuyKeepMultiple(address(this), keepMultiple);
    }

    function gameSetAfKingMode(
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external onlyVaultOwner {
        gamePlayer.setAfKingMode(address(this), enabled, ethKeepMultiple, coinKeepMultiple);
    }

    function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner {
        gamePlayer.setOperatorApproval(operator, approved);
    }

    function gamepiecesPurchase(
        PurchaseParams calldata params,
        uint256 ethValue
    ) external payable onlyVaultOwner {
        uint256 totalValue = _combinedValue(ethValue);
        gamepiecesPlayer.purchase{value: totalValue}(params);
    }

    function coinDepositCoinflip(uint256 amount) external onlyVaultOwner {
        coinPlayer.depositCoinflip(address(this), amount);
    }

    function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {
        return coinPlayer.claimCoinflips(address(this), amount);
    }

    function coinClaimCoinflipsKeepMultiple(
        uint256 multiples
    ) external onlyVaultOwner returns (uint256 claimed) {
        return coinPlayer.claimCoinflipsKeepMultiple(address(this), multiples);
    }

    function coinDecimatorBurn(uint256 amount) external onlyVaultOwner {
        coinPlayer.decimatorBurn(address(this), amount);
    }

    function coinSetAutoRebuy(bool enabled, uint256 keepMultiple) external onlyVaultOwner {
        coinPlayer.setCoinflipAutoRebuy(address(this), enabled, keepMultiple);
    }

    function coinSetAutoRebuyKeepMultiple(uint256 keepMultiple) external onlyVaultOwner {
        coinPlayer.setCoinflipAutoRebuyKeepMultiple(address(this), keepMultiple);
    }

    function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner {
        jackpotsPlayer.claimDecimatorJackpot(lvl);
    }

    // ---------------------------------------------------------------------
    // CLAIMS (Burn Shares to Redeem Assets)
    // ---------------------------------------------------------------------

    /// @notice Burn DGVB (coinShare) tokens to redeem proportional BURNIE
    /// @dev Formula: coinOut = (DGVB reserve * sharesBurned) / totalSupply
    ///      If burning entire supply, caller receives new 1T shares (refill mechanism).
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount of DGVB shares to burn
    /// @return coinOut Amount of BURNIE minted to player
    function burnCoin(address player, uint256 amount) external returns (uint256 coinOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnCoinFor(player, amount);
    }

    function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut) {
        DegenerusVaultShare share = coinShare;
        uint256 bal = share.balanceOf(player);
        if (amount == 0 || amount > bal) revert Insufficient();

        _syncCoinReserves();
        uint256 supplyBefore = share.totalSupply();
        uint256 coinBal = coinTracked;
        if (coinBal < dgvaCoinReserve) revert Insufficient();
        coinBal -= dgvaCoinReserve;
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinPlayer.previewClaimCoinflips(address(this));
        if (vaultBal != 0 || claimable != 0) {
            coinBal += vaultBal + claimable;
        }
        coinOut = (coinBal * amount) / supplyBefore; // Floor division - dust remains

        // CEI: State changes before external calls
        share.vaultBurn(player, amount);
        if (supplyBefore == amount) {
            // Refill: burning entire supply grants new 1T shares to prevent division-by-zero
            share.vaultMint(player, REFILL_SUPPLY);
        }

        emit Claim(player, amount, 0, 0, coinOut);
        if (coinOut != 0) {
            uint256 remaining = coinOut;
            if (vaultBal != 0) {
                uint256 payBal = remaining <= vaultBal ? remaining : vaultBal;
                if (payBal != 0) {
                    remaining -= payBal;
                    if (!coinToken.transfer(player, payBal)) revert TransferFailed();
                }
            }

            if (remaining != 0 && claimable != 0) {
                uint256 claimed = coinPlayer.claimCoinflips(address(this), remaining);
                if (claimed != 0) {
                    remaining -= claimed;
                    if (!coinToken.transfer(player, claimed)) revert TransferFailed();
                }
            }

            if (remaining != 0) {
                coinTracked -= remaining;
                coinToken.vaultMintTo(player, remaining);
            }
        }
    }

    /// @notice Burn DGVE (ethShare) tokens to redeem proportional ETH and stETH
    /// @dev ETH is preferred over stETH (uses ETH first, then stETH for remainder).
    ///      Formula: claimValue = (combinedReserve) * sharesBurned / totalSupply
    ///      If burning entire supply, caller receives new 1T shares (refill mechanism).
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount of DGVE shares to burn
    /// @return ethOut Amount of ETH sent to player
    /// @return stEthOut Amount of stETH sent to player
    function burnEth(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stEthOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnEthFor(player, amount);
    }

    function _burnEthFor(
        address player,
        uint256 amount
    ) private returns (uint256 ethOut, uint256 stEthOut) {
        DegenerusVaultShare share = ethShare;
        uint256 bal = share.balanceOf(player);
        if (amount == 0 || amount > bal) revert Insufficient();

        (uint256 ethBal, uint256 stBal, uint256 combined) = _syncEthReserves();
        uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
        if (claimable <= 1) {
            claimable = 0;
        } else {
            unchecked {
                claimable -= 1;
            }
        }
        uint256 supplyBefore = share.totalSupply();
        uint256 dgvaReserve = dgvaEthReserve;
        uint256 reserve = combined + claimable - dgvaReserve;
        uint256 claimValue = (reserve * amount) / supplyBefore; // Floor division

        if (claimValue > ethBal + stBal && claimable != 0) {
            gamePlayer.claimWinnings(address(this));
            ethBal = address(this).balance;
            stBal = _stethBalance();
        }

        // ETH-first payout strategy (saves gas vs stETH transfer)
        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
            if (stEthOut > stBal) revert Insufficient();
        }

        // CEI: State changes before external calls (ETH send has callback risk)
        share.vaultBurn(player, amount);
        if (supplyBefore == amount) {
            share.vaultMint(player, REFILL_SUPPLY);
        }

        emit Claim(player, amount, ethOut, stEthOut, 0);

        // External calls last (ETH balance already reduced atomically with send)
        if (ethOut != 0) _payEth(player, ethOut);
        if (stEthOut != 0) _paySteth(player, stEthOut);
    }

    /// @notice Burn DGVA (allShare) tokens to redeem proportional ETH/stETH and BURNIE
    /// @dev ETH/stETH claims are limited to DGVA's combined reserve (20% of deposits).
    ///      Formula per asset: out = (reserve * sharesBurned) / totalSupply
    ///      If burning entire supply, caller receives new 1T shares (refill mechanism).
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount of DGVA shares to burn
    /// @return ethOut Amount of ETH sent to player
    /// @return stEthOut Amount of stETH sent to player
    /// @return coinOut Amount of BURNIE minted to player
    function burnAll(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stEthOut, uint256 coinOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnAllFor(player, amount);
    }

    function _burnAllFor(
        address player,
        uint256 amount
    ) private returns (uint256 ethOut, uint256 stEthOut, uint256 coinOut) {
        DegenerusVaultShare share = allShare;
        uint256 bal = share.balanceOf(player);
        if (amount == 0 || amount > bal) revert Insufficient();

        (uint256 ethBal, uint256 stBal, ) = _syncEthReserves();
        _syncCoinReserves();

        uint256 supplyBefore = share.totalSupply();
        uint256 ethReserve = dgvaEthReserve;
        uint256 coinReserve = dgvaCoinReserve;

        uint256 claimValue = (ethReserve * amount) / supplyBefore;
        coinOut = (coinReserve * amount) / supplyBefore;

        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
            if (stEthOut > stBal) revert Insufficient();
        }

        // CEI: State changes before external calls
        share.vaultBurn(player, amount);
        if (supplyBefore == amount) {
            share.vaultMint(player, REFILL_SUPPLY);
        }
        if (claimValue != 0) {
            dgvaEthReserve = ethReserve - claimValue;
        }
        if (coinOut != 0) {
            dgvaCoinReserve = coinReserve - coinOut;
            coinTracked -= coinOut;
        }

        emit ClaimAll(player, amount, ethOut, stEthOut, coinOut);

        if (ethOut != 0) _payEth(player, ethOut);
        if (stEthOut != 0) _paySteth(player, stEthOut);
        if (coinOut != 0) coinToken.vaultMintTo(player, coinOut);
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS - Reverse Calculations (Target Output → Required Burn)
    // ---------------------------------------------------------------------

    /// @notice Calculate shares to burn for a target BURNIE output
    /// @dev Uses ceiling division to ensure user burns enough shares
    /// @param coinOut Target BURNIE amount to receive
    /// @return burnAmount DGVB shares required to burn
    function previewBurnForCoinOut(uint256 coinOut) external view returns (uint256 burnAmount) {
        (uint256 reserve, ) = _coinReservesView();
        if (coinOut == 0 || coinOut > reserve) revert Insufficient();
        uint256 supply = coinShare.totalSupply();
        // Ceiling division: ceil(coinOut * supply / reserve)
        burnAmount = (coinOut * supply + reserve - 1) / reserve;
    }

    /// @notice Calculate shares to burn for a target ETH-equivalent value
    /// @dev Value = DGVE's share of the combined ETH+stETH pool. Uses ceiling division.
    /// @param targetValue Target combined ETH+stETH value to receive (DGVE share)
    /// @return burnAmount DGVE shares required to burn
    /// @return ethOut Estimated ETH output
    /// @return stEthOut Estimated stETH output
    function previewBurnForEthOut(
        uint256 targetValue
    ) external view returns (uint256 burnAmount, uint256 ethOut, uint256 stEthOut) {
        uint256 supply = ethShare.totalSupply();
        (uint256 reserve, , uint256 ethBal) = _ethReservesView();
        if (targetValue == 0 || targetValue > reserve) revert Insufficient();

        // Ceiling division: ceil(targetValue * supply / reserve)
        burnAmount = (targetValue * supply + reserve - 1) / reserve;

        // Simulate actual claim output with calculated burn amount
        uint256 claimValue = (reserve * burnAmount) / supply;
        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
        }
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS - Forward Calculations (Shares to Burn → Expected Output)
    // ---------------------------------------------------------------------

    /// @notice Preview BURNIE output for burning a given amount of shares
    /// @param amount DGVB shares to burn
    /// @return coinOut BURNIE that would be minted
    function previewCoin(uint256 amount) external view returns (uint256 coinOut) {
        uint256 supply = coinShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        (uint256 coinBal, ) = _coinReservesView();
        coinOut = (coinBal * amount) / supply; // Floor division
    }

    /// @notice Preview ETH/stETH output for burning a given amount of shares
    /// @param amount DGVE shares to burn
    /// @return ethOut ETH that would be sent
    /// @return stEthOut stETH that would be sent
    function previewEth(uint256 amount) external view returns (uint256 ethOut, uint256 stEthOut) {
        uint256 supply = ethShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        (uint256 reserve, , uint256 ethBal) = _ethReservesView();
        uint256 claimValue = (reserve * amount) / supply; // Floor division

        // ETH-first payout strategy
        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
        }
    }

    /// @notice Preview ETH/stETH/BURNIE output for burning a given amount of DGVA shares
    /// @param amount DGVA shares to burn
    /// @return ethOut ETH that would be sent
    /// @return stEthOut stETH that would be sent
    /// @return coinOut BURNIE that would be minted
    function previewAll(
        uint256 amount
    ) external view returns (uint256 ethOut, uint256 stEthOut, uint256 coinOut) {
        uint256 supply = allShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        (, uint256 ethReserve, uint256 ethBal) = _ethReservesView();
        (, uint256 coinBal) = _coinReservesView();
        uint256 claimValue = (ethReserve * amount) / supply;
        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
        }
        coinOut = (coinBal * amount) / supply;
    }

    // ---------------------------------------------------------------------
    // DGNRS INFO (Public Views)
    // ---------------------------------------------------------------------

    /// @notice Get the total supply of DGNRS shares
    /// @return Total supply of DGNRS (allShare) tokens
    function allShareSupply() external view returns (uint256) {
        return allShare.totalSupply();
    }

    /// @notice Get ETH+stETH reserve backing DGNRS claims
    /// @return ETH reserve for DGNRS (20% of deposits)
    function dgnrsEthReserve() external view returns (uint256) {
        return dgvaEthReserve;
    }

    /// @notice Get BURNIE reserve backing DGNRS claims
    /// @return BURNIE reserve for DGNRS (20% of virtual deposits)
    function dgnrsCoinReserve() external view returns (uint256) {
        return dgvaCoinReserve;
    }

    // ---------------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------------
    /// @dev Combine msg.value with an additional vault-funded amount.
    function _combinedValue(uint256 extraValue) private view returns (uint256 totalValue) {
        totalValue = msg.value + extraValue;
        if (totalValue > address(this).balance) revert Insufficient();
    }

    /// @dev Clamp DGVA's ETH+stETH reserve to actual balance; returns balances to avoid re-reading
    function _syncEthReserves() private returns (uint256 ethBal, uint256 stBal, uint256 combined) {
        ethBal = address(this).balance;
        stBal = _stethBalance();
        combined = ethBal + stBal;
        if (dgvaEthReserve > combined) {
            dgvaEthReserve = combined;
        }
    }

    /// @dev Sync BURNIE reserve split with the actual allowance
    function _syncCoinReserves() private {
        uint256 allowance = coinToken.vaultMintAllowance();
        uint256 tracked = coinTracked;
        if (allowance > tracked) {
            uint256 delta = allowance - tracked;
            uint256 dgvaShare = delta / DGVA_SPLIT_DIVISOR;
            dgvaCoinReserve += dgvaShare;
            coinTracked = allowance;
        } else if (allowance < tracked) {
            coinTracked = allowance;
            if (dgvaCoinReserve > allowance) {
                dgvaCoinReserve = allowance;
            }
        }
    }

    /// @dev View helper for BURNIE reserves with pending split delta applied
    function _coinReservesView() private view returns (uint256 mainReserve, uint256 dgvaReserve) {
        uint256 allowance = coinToken.vaultMintAllowance();
        uint256 tracked = coinTracked;
        dgvaReserve = dgvaCoinReserve;
        if (allowance > tracked) {
            uint256 delta = allowance - tracked;
            dgvaReserve += delta / DGVA_SPLIT_DIVISOR;
        }
        if (dgvaReserve > allowance) {
            dgvaReserve = allowance;
        }
        mainReserve = allowance - dgvaReserve;
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinPlayer.previewClaimCoinflips(address(this));
        if (vaultBal != 0 || claimable != 0) {
            mainReserve += vaultBal + claimable;
        }
    }

    /// @dev View helper for ETH+stETH reserves (stETH rebase yield goes to DGVE)
    function _ethReservesView() private view returns (uint256 mainReserve, uint256 dgvaReserve, uint256 ethBal) {
        ethBal = address(this).balance;
        uint256 stBal = _stethBalance();
        uint256 combined = ethBal + stBal;
        dgvaReserve = dgvaEthReserve;
        if (dgvaReserve > combined) {
            dgvaReserve = combined;
        }
        uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
        if (claimable > 1) {
            unchecked {
                claimable -= 1;
            }
        } else {
            claimable = 0;
        }
        mainReserve = combined - dgvaReserve + claimable;
    }

    /// @dev Get this contract's stETH balance
    function _stethBalance() private view returns (uint256) {
        return steth.balanceOf(address(this));
    }

    /// @dev Send ETH to recipient using low-level call
    /// @notice Uses .call{} to support contracts with custom receive logic
    function _payEth(address to, uint256 amount) private {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @dev Transfer stETH to recipient
    function _paySteth(address to, uint256 amount) private {
        if (!steth.transfer(to, amount)) revert TransferFailed();
    }

    /// @dev Pull stETH from sender (requires prior approval)
    function _pullSteth(address from, uint256 amount) private {
        if (amount == 0) return;
        if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();
    }
}
