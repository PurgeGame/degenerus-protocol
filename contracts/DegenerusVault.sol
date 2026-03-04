// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame, MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IVaultCoin} from "./interfaces/IVaultCoin.sol";

/// @notice Interface for game player actions on DegenerusGame contract
interface IDegenerusGamePlayerActions {
    function advanceGame() external;
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    function openLootBox(address player, uint48 lootboxIndex) external;
    function claimWinnings(address player) external;
    function claimWinningsStethFirst() external;
    function claimWhalePass(address player) external;
    function claimDecimatorJackpot(uint24 lvl) external;
    function setDecimatorAutoRebuy(address player, bool enabled) external;
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;
    function purchaseDeityPass(address buyer, bool useBoon) external payable;
    function placeFullTicketBets(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external payable;
    function resolveDegeneretteBets(address player, uint64[] calldata betIds) external;
    function setAutoRebuy(address player, bool enabled) external;
    function setAutoRebuyTakeProfit(address player, uint256 takeProfit) external;
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external;
    function setOperatorApproval(address operator, bool approved) external;
    function claimableWinningsOf(address player) external view returns (uint256);
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external;
}

/// @notice Interface for coin player actions (coinflip mechanics)
interface IDegenerusCoinPlayerActions {
    function depositCoinflip(address player, uint256 amount) external;
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function claimCoinflipsTakeProfit(address player, uint256 multiples) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function decimatorBurn(address player, uint256 amount) external;
    function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;
    function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;
}

/// @notice Interface for WWXRP vault-minting
interface IWWXRPMint {
    function vaultMintTo(address to, uint256 amount) external;
    function vaultMintAllowance() external view returns (uint256);
}

/*
+========================================================================================================+
|                                        DegenerusVault                                                  |
|                     Multi-Asset Vault with Independent Share Classes                                   |
+========================================================================================================+
|                                                                                                        |
|  ARCHITECTURE OVERVIEW                                                                                 |
|  ---------------------                                                                                 |
|  DegenerusVault holds two asset types with two independent share classes for claims:                 |
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
|  |   |  BURNIE         |----►|  coinShare      |  DGVB - Claims BURNIE only                          | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |                                                                                                   | |
|  |   DGVE and DGVB have independent supply and proportional claim rights.                            | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              DEPOSIT FLOW (Game-Only)                                             | |
|  |                                                                                                   | |
|  |   DegenerusGame ----► deposit() ----► Pulls ETH/stETH, escrows BURNIE mint allowance              | |
|  |                                                                                                   | |
|  |   Split: ETH+stETH deposits accrue to DGVE. BURNIE vault allowance is claimable by DGVB.          | |
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
|  |   (No DGNRS share class in the vault)                                                              | |
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
|  • ETH and stETH are combined for DGVE claims (ETH preferred, then stETH)                              |
|  • All wiring is constant after construction                                                           |
|                                                                                                        |
+========================================================================================================+*/

// -----------------------------------------------------------------------------
// VAULT SHARE TOKEN
// -----------------------------------------------------------------------------

/// @title DegenerusVaultShare
/// @notice Minimal ERC20 for vault share classes (DGVB, DGVE)
/// @dev Only the parent vault can mint/burn. Standard ERC20 transfer/approve for users.
contract DegenerusVaultShare {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    /// @notice Caller is not the authorized vault contract
    error Unauthorized();
    /// @notice Address parameter is zero when non-zero required
    error ZeroAddress();
    /// @notice Insufficient balance or allowance for operation
    error Insufficient();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when an allowance is set or updated
    /// @param owner Token owner granting allowance
    /// @param spender Address approved to spend tokens
    /// @param amount New allowance amount
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
    /// @notice Initial share supply minted to creator (1 trillion tokens)
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @notice Total supply of shares currently in circulation
    uint256 public totalSupply;
    /// @notice Balance of shares per address
    mapping(address => uint256) public balanceOf;
    /// @notice Spending allowance granted by owner to spender
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
    /// @notice Deploy a new share token with initial supply minted to creator
    /// @dev Initial supply is minted to ContractAddresses.CREATOR
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
    /// @custom:reverts ZeroAddress If to is address(0)
    /// @custom:reverts Insufficient If sender balance is less than amount
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens from one address to another using allowance
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    /// @return success Always true (reverts on failure)
    /// @custom:reverts ZeroAddress If from or to is address(0)
    /// @custom:reverts Insufficient If allowance or balance is insufficient
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert Insufficient();
            uint256 newAllowance = allowed - amount;
            allowance[from][msg.sender] = newAllowance;
            emit Approval(from, msg.sender, newAllowance);
        }
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------
    // VAULT-CONTROLLED MINT/BURN
    // ---------------------------------------------------------------------
    /// @notice Mint new shares to recipient
    /// @dev Only callable by the vault contract. Used for refill mechanism when all shares are burned.
    /// @param to Recipient address
    /// @param amount Amount to mint
    /// @custom:reverts Unauthorized If caller is not the vault
    /// @custom:reverts ZeroAddress If to is address(0)
    function vaultMint(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn shares from holder
    /// @dev Only callable by the vault contract. Used when users claim underlying assets.
    /// @param from Address to burn from
    /// @param amount Amount to burn
    /// @custom:reverts Unauthorized If caller is not the vault
    /// @custom:reverts Insufficient If from balance is less than amount
    function vaultBurn(address from, uint256 amount) external onlyVault {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // ---------------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------------
    /// @dev Internal transfer logic with balance and zero-address checks
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

// -----------------------------------------------------------------------------
// MAIN VAULT CONTRACT
// -----------------------------------------------------------------------------

/// @title DegenerusVault
/// @notice Multi-asset vault with two independent share classes for claiming different assets
/// @dev See contract header for full architecture documentation
contract DegenerusVault {
    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------
    /// @notice Caller is not the GAME contract
    error Unauthorized();
    /// @notice Caller does not hold >30% of DGVE supply
    error NotVaultOwner();
    /// @notice Insufficient balance, allowance, or reserve for operation
    error Insufficient();
    /// @notice ETH or token transfer failed
    error TransferFailed();
    /// @notice Caller is not the player and not an approved operator
    error NotApproved();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @notice Emitted when assets are deposited into the vault
    /// @param from Depositor address (typically the GAME contract)
    /// @param ethAmount ETH deposited (via msg.value)
    /// @param stEthAmount stETH pulled from depositor
    /// @param coinAmount BURNIE mint allowance escrowed (virtual deposit)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stEthAmount, uint256 coinAmount);
    /// @notice Emitted when user burns DGVB or DGVE shares to claim assets
    /// @param from User who burned shares
    /// @param sharesBurned Amount of shares burned
    /// @param ethOut ETH sent to user
    /// @param stEthOut stETH sent to user
    /// @param coinOut BURNIE minted to user
    event Claim(address indexed from, uint256 sharesBurned, uint256 ethOut, uint256 stEthOut, uint256 coinOut);

    // ---------------------------------------------------------------------
    // CONSTANTS
    // ---------------------------------------------------------------------
    /// @notice Vault metadata name
    string public constant name = "Degenerus Vault";
    /// @notice Vault metadata symbol
    string public constant symbol = "DGV";
    /// @notice Vault metadata decimals
    uint8 public constant decimals = 18;
    /// @dev Supply minted when all shares are burned (1 trillion, keeps token alive)
    uint256 private constant REFILL_SUPPLY = 1_000_000_000_000 * 1e18;

    // ---------------------------------------------------------------------
    // SHARE CLASS TOKENS (Immutable)
    // ---------------------------------------------------------------------
    /// @notice Share token for BURNIE claims (symbol: DGVB)
    DegenerusVaultShare private immutable coinShare;
    /// @notice Share token for ETH+stETH claims (symbol: DGVE)
    DegenerusVaultShare private immutable ethShare;

    // ---------------------------------------------------------------------
    // WIRING (Constants)
    // ---------------------------------------------------------------------
    /// @dev Game contract for operator approval checks
    IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);
    /// @dev Game contract for player actions
    IDegenerusGamePlayerActions internal constant gamePlayer =
        IDegenerusGamePlayerActions(ContractAddresses.GAME);
    /// @dev Coin contract for coinflip actions
    IDegenerusCoinPlayerActions internal constant coinPlayer =
        IDegenerusCoinPlayerActions(ContractAddresses.COIN);
    /// @dev Jackpots contract for decimator claims
    /// @dev BURNIE token contract for minting and transfers
    IVaultCoin internal constant coinToken = IVaultCoin(ContractAddresses.COIN);
    /// @dev WWXRP token contract for vault minting
    IWWXRPMint internal constant wwxrpToken = IWWXRPMint(ContractAddresses.WWXRP);
    /// @dev stETH (Lido) token contract
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // ---------------------------------------------------------------------
    // RESERVE TRACKING
    // ---------------------------------------------------------------------
    /// @dev Tracked total BURNIE mint allowance (for claim accounting)
    uint256 private coinTracked;


    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    /// @dev Restricts function to the GAME contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    /// @dev Restricts function to accounts holding >30% of DGVE supply
    modifier onlyVaultOwner() {
        if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();
        _;
    }

    /// @dev Reverts if caller is not the player and not an approved operator for the player
    /// @param player The player address to check approval for
    function _requireApproved(address player) private view {
        if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }

    /// @dev Check if account holds >30% of DGVE supply (balance * 10 > supply * 3)
    /// @param account Address to check
    /// @return True if account qualifies as vault owner
    function _isVaultOwner(address account) private view returns (bool) {
        uint256 supply = ethShare.totalSupply();
        uint256 balance = ethShare.balanceOf(account);
        return balance * 10 > supply * 3;
    }

    /// @notice Check if account holds >30% of DGVE supply
    /// @param account Address to check
    /// @return True if account qualifies as vault owner
    function isVaultOwner(address account) external view returns (bool) {
        return _isVaultOwner(account);
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    /// @notice Deploy the vault and create all share class tokens
    /// @dev Deploys DGVB and DGVE tokens. Creator receives initial 1T supply of each.
    constructor() {
        coinShare = new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB");
        ethShare = new DegenerusVaultShare("Degenerus Vault Eth", "DGVE");

        uint256 coinAllowance = coinToken.vaultMintAllowance();
        coinTracked = coinAllowance;

    }

    // ---------------------------------------------------------------------
    // DEPOSITS (Game-Only)
    // ---------------------------------------------------------------------

    /// @notice Deposit ETH, stETH, and/or BURNIE mint allowance into the vault
    /// @dev BURNIE uses virtual deposit (escrows mint allowance, no transfer).
    ///      ETH is received via msg.value, stETH is pulled via transferFrom.
    ///      ETH+stETH deposits accrue to DGVE.
    /// @param coinAmount BURNIE mint allowance to escrow (virtual deposit)
    /// @param stEthAmount stETH to pull from caller (requires prior approval)
    /// @custom:reverts Unauthorized If caller is not the GAME contract
    /// @custom:reverts TransferFailed If stETH transfer fails
    function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame {
        if (coinAmount != 0) {
            _syncCoinReserves();
            coinToken.vaultEscrow(coinAmount);
            coinTracked += coinAmount;
        }
        _pullSteth(msg.sender, stEthAmount);
        emit Deposit(msg.sender, msg.value, stEthAmount, coinAmount);
    }

    /// @notice Receive ETH donations from any sender
    receive() external payable {
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    // ---------------------------------------------------------------------
    // GAMEPLAY (Vault Owner)
    // ---------------------------------------------------------------------

    /// @notice Advance the game on behalf of the vault
    /// @dev Requires caller to hold >30% of DGVE supply
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameAdvance() external onlyVaultOwner {
        gamePlayer.advanceGame();
    }

    /// @notice Purchase tickets and lootboxes for the vault
    /// @dev Combines msg.value with vault ETH balance if ethValue > 0
    /// @param ticketQuantity Number of tickets to purchase
    /// @param lootBoxAmount Number of lootboxes to purchase
    /// @param affiliateCode Affiliate code for referral tracking
    /// @param payKind Payment method for minting
    /// @param ethValue Additional ETH from vault balance to use (on top of msg.value)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    /// @custom:reverts Insufficient If total value exceeds vault balance
    function gamePurchase(
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) external payable onlyVaultOwner {
        uint256 totalValue = _combinedValue(ethValue);
        gamePlayer.purchase{value: totalValue}(
            address(this),
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    /// @notice Purchase BURNIE tickets through the game contract
    /// @param ticketQuantity Number of tickets to purchase
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    /// @custom:reverts Insufficient If ticketQuantity is zero
    function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner {
        if (ticketQuantity == 0) revert Insufficient();
        gamePlayer.purchaseCoin(address(this), ticketQuantity, 0);
    }

    /// @notice Purchase a BURNIE lootbox for the vault
    /// @param burnieAmount Amount of BURNIE to burn
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    /// @custom:reverts Insufficient If burnieAmount is zero
    function gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner {
        if (burnieAmount == 0) revert Insufficient();
        gamePlayer.purchaseBurnieLootbox(address(this), burnieAmount);
    }

    /// @notice Open a lootbox owned by the vault
    /// @param lootboxIndex Index of the lootbox to open
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner {
        gamePlayer.openLootBox(address(this), lootboxIndex);
    }

    /// @notice Purchase a deity pass using an active boon for the vault
    /// @dev Uses vault ETH + claimable winnings; msg.value is retained in the vault.
    /// @param priceWei Expected price (15/25/50 ETH)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    /// @custom:reverts Insufficient If price is zero or vault cannot fund the purchase
    function gamePurchaseDeityPassFromBoon(uint256 priceWei) external payable onlyVaultOwner {
        if (priceWei == 0) revert Insufficient();
        if (address(this).balance < priceWei) {
            uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
            if (claimable > 1) {
                gamePlayer.claimWinnings(address(this));
            }
        }
        if (address(this).balance < priceWei) revert Insufficient();
        gamePlayer.purchaseDeityPass{value: priceWei}(address(this), true);
    }

    /// @notice Claim winnings for the vault (preferring stETH)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameClaimWinnings() external onlyVaultOwner {
        gamePlayer.claimWinningsStethFirst();
    }

    /// @notice Claim a whale pass for the vault
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameClaimWhalePass() external onlyVaultOwner {
        gamePlayer.claimWhalePass(address(this));
    }

    /// @notice Place a Degenerette bet using ETH (and/or claimable winnings)
    /// @dev Uses msg.value + ethValue from vault balance. If underfunded, claimable winnings are used.
    /// @param amountPerTicket Bet amount per ticket
    /// @param ticketCount Number of tickets (must satisfy game rules)
    /// @param customTicket Custom packed traits
    /// @param customSpecial Custom special (1=ETH,2=BURNIE,3=DGNRS)
    /// @param ethValue Additional ETH from vault balance to use (on top of msg.value)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    /// @custom:reverts Insufficient If msg.value + ethValue exceeds total bet or vault balance
    function gameDegeneretteBetEth(
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial,
        uint256 ethValue
    ) external payable onlyVaultOwner {
        uint256 totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        uint256 totalValue = _combinedValue(ethValue);
        if (totalValue > totalBet) revert Insufficient();
        gamePlayer.placeFullTicketBets{value: totalValue}(
            address(this),
            0,
            amountPerTicket,
            ticketCount,
            customTicket,
            customSpecial
        );
    }

    /// @notice Place a Degenerette bet using BURNIE
    /// @param amountPerTicket Bet amount per ticket
    /// @param ticketCount Number of tickets (must satisfy game rules)
    /// @param customTicket Custom packed traits
    /// @param customSpecial Custom special (1=ETH,2=BURNIE,3=DGNRS)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameDegeneretteBetBurnie(
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external onlyVaultOwner {
        gamePlayer.placeFullTicketBets(
            address(this),
            1,
            amountPerTicket,
            ticketCount,
            customTicket,
            customSpecial
        );
    }

    /// @notice Place a Degenerette bet using WWXRP
    /// @param amountPerTicket Bet amount per ticket
    /// @param ticketCount Number of tickets (must satisfy game rules)
    /// @param customTicket Custom packed traits
    /// @param customSpecial Custom special (1=ETH,2=BURNIE,3=DGNRS)
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameDegeneretteBetWwxrp(
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external onlyVaultOwner {
        gamePlayer.placeFullTicketBets(
            address(this),
            3,
            amountPerTicket,
            ticketCount,
            customTicket,
            customSpecial
        );
    }

    /// @notice Resolve Degenerette bets for the vault
    /// @param betIds Bet identifiers to resolve
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner {
        gamePlayer.resolveDegeneretteBets(address(this), betIds);
    }

    /// @notice Enable or disable auto-rebuy for the vault
    /// @param enabled Whether auto-rebuy should be enabled
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameSetAutoRebuy(bool enabled) external onlyVaultOwner {
        gamePlayer.setAutoRebuy(address(this), enabled);
    }

    /// @notice Set the auto-rebuy take profit for the vault
    /// @param takeProfit Amount to take profit before auto-rebuying
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {
        gamePlayer.setAutoRebuyTakeProfit(address(this), takeProfit);
    }

    /// @notice Enable or disable auto-rebuy for decimator claims
    /// @param enabled True to enable, false to disable
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner {
        gamePlayer.setDecimatorAutoRebuy(address(this), enabled);
    }

    /// @notice Configure AFK king mode settings for the vault
    /// @param enabled Whether AFK king mode should be enabled
    /// @param ethTakeProfit ETH take profit threshold
    /// @param coinTakeProfit Coin take profit threshold
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameSetAfKingMode(
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external onlyVaultOwner {
        gamePlayer.setAfKingMode(address(this), enabled, ethTakeProfit, coinTakeProfit);
    }

    /// @notice Approve or revoke an operator for the vault's game actions
    /// @param operator Address to approve or revoke
    /// @param approved Whether to approve or revoke
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner {
        gamePlayer.setOperatorApproval(operator, approved);
    }

    /// @notice Deposit coins into coinflip for the vault
    /// @param amount Amount of coins to deposit
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinDepositCoinflip(uint256 amount) external onlyVaultOwner {
        coinPlayer.depositCoinflip(address(this), amount);
    }

    /// @notice Claim coinflip winnings for the vault
    /// @param amount Maximum amount to claim
    /// @return claimed Actual amount claimed
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {
        return coinPlayer.claimCoinflips(address(this), amount);
    }

    /// @notice Claim coinflip winnings as take profit multiples
    /// @param multiples Number of take profit multiples to claim
    /// @return claimed Actual amount claimed
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinClaimCoinflipsTakeProfit(
        uint256 multiples
    ) external onlyVaultOwner returns (uint256 claimed) {
        return coinPlayer.claimCoinflipsTakeProfit(address(this), multiples);
    }

    /// @notice Burn coins in the decimator for the vault
    /// @param amount Amount of coins to burn
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinDecimatorBurn(uint256 amount) external onlyVaultOwner {
        coinPlayer.decimatorBurn(address(this), amount);
    }

    /// @notice Configure coinflip auto-rebuy for the vault
    /// @param enabled Whether auto-rebuy should be enabled
    /// @param takeProfit Amount to take profit
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner {
        coinPlayer.setCoinflipAutoRebuy(address(this), enabled, takeProfit);
    }

    /// @notice Set coinflip auto-rebuy take profit for the vault
    /// @param takeProfit Amount to take profit
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {
        coinPlayer.setCoinflipAutoRebuyTakeProfit(address(this), takeProfit);
    }

    /// @notice Mint WWXRP from the vault's uncirculating reserve to a recipient
    /// @param to Recipient address
    /// @param amount Amount of WWXRP to mint
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function wwxrpMint(address to, uint256 amount) external onlyVaultOwner {
        if (amount == 0) return;
        wwxrpToken.vaultMintTo(to, amount);
    }

    /// @notice Claim a decimator jackpot for the vault
    /// @param lvl Jackpot level to claim
    /// @custom:reverts NotVaultOwner If caller does not hold >30% of DGVE
    function jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner {
        gamePlayer.claimDecimatorJackpot(lvl);
    }

    // ---------------------------------------------------------------------
    // CLAIMS (Burn Shares to Redeem Assets)
    // ---------------------------------------------------------------------

    /// @notice Burn DGVB shares to redeem proportional BURNIE
    /// @dev Formula: coinOut = (DGVB reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      Pays from vault balance first, then claimable coinflips, then mints remainder.
    /// @param player Player address to burn for (address(0) uses msg.sender)
    /// @param amount Amount of DGVB shares to burn
    /// @return coinOut Amount of BURNIE sent to player
    /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
    /// @custom:reverts NotApproved If caller is not player and not approved operator
    /// @custom:reverts TransferFailed If BURNIE transfer fails
    function burnCoin(address player, uint256 amount) external returns (uint256 coinOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnCoinFor(player, amount);
    }

    /// @dev Internal implementation for burning DGVB shares
    /// @param player Player address receiving the BURNIE
    /// @param amount Amount of DGVB shares to burn
    /// @return coinOut Amount of BURNIE sent to player
    function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut) {
        DegenerusVaultShare share = coinShare;
        if (amount == 0) revert Insufficient();

        uint256 coinBal = _syncCoinReserves();
        uint256 supplyBefore = share.totalSupply();
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinPlayer.previewClaimCoinflips(address(this));
        if (vaultBal != 0 || claimable != 0) {
            coinBal += vaultBal + claimable;
        }
        coinOut = (coinBal * amount) / supplyBefore;

        share.vaultBurn(player, amount);
        if (supplyBefore == amount) {
            share.vaultMint(player, REFILL_SUPPLY);
        }

        emit Claim(player, amount, 0, 0, coinOut);
        if (coinOut != 0) {
            uint256 remaining = coinOut;
            if (vaultBal != 0) {
                uint256 payBal = remaining <= vaultBal ? remaining : vaultBal;
                remaining -= payBal;
                if (!coinToken.transfer(player, payBal)) revert TransferFailed();
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

    /// @notice Burn DGVE shares to redeem proportional ETH and stETH
    /// @dev ETH is preferred over stETH (uses ETH first, then stETH for remainder).
    ///      Formula: claimValue = (DGVE reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      May auto-claim game winnings if needed to fulfill the redemption.
    /// @param player Player address to burn for (address(0) uses msg.sender)
    /// @param amount Amount of DGVE shares to burn
    /// @return ethOut Amount of ETH sent to player
    /// @return stEthOut Amount of stETH sent to player
    /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
    /// @custom:reverts NotApproved If caller is not player and not approved operator
    /// @custom:reverts TransferFailed If ETH or stETH transfer fails
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

    /// @dev Internal implementation for burning DGVE shares
    /// @param player Player address receiving the ETH/stETH
    /// @param amount Amount of DGVE shares to burn
    /// @return ethOut Amount of ETH sent to player
    /// @return stEthOut Amount of stETH sent to player
    function _burnEthFor(
        address player,
        uint256 amount
    ) private returns (uint256 ethOut, uint256 stEthOut) {
        DegenerusVaultShare share = ethShare;
        if (amount == 0) revert Insufficient();

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
        uint256 reserve = combined + claimable;
        uint256 claimValue = (reserve * amount) / supplyBefore;

        if (claimValue > combined && claimable != 0) {
            gamePlayer.claimWinnings(address(this));
            ethBal = address(this).balance;
            stBal = _stethBalance();
        }

        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
            if (stEthOut > stBal) revert Insufficient();
        }

        share.vaultBurn(player, amount);
        if (supplyBefore == amount) {
            share.vaultMint(player, REFILL_SUPPLY);
        }

        emit Claim(player, amount, ethOut, stEthOut, 0);

        if (ethOut != 0) _payEth(player, ethOut);
        if (stEthOut != 0) _paySteth(player, stEthOut);
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS - Reverse Calculations (Target Output → Required Burn)
    // ---------------------------------------------------------------------

    /// @notice Calculate DGVB shares required to receive a target BURNIE amount
    /// @dev Uses ceiling division to ensure user burns enough shares
    /// @param coinOut Target BURNIE amount to receive
    /// @return burnAmount DGVB shares required to burn
    /// @custom:reverts Insufficient If coinOut is 0 or exceeds available reserve
    function previewBurnForCoinOut(uint256 coinOut) external view returns (uint256 burnAmount) {
        uint256 reserve = _coinReservesView();
        if (coinOut == 0 || coinOut > reserve) revert Insufficient();
        uint256 supply = coinShare.totalSupply();
        burnAmount = (coinOut * supply + reserve - 1) / reserve;
    }

    /// @notice Calculate DGVE shares required to receive a target ETH-equivalent value
    /// @dev Value = DGVE's share of the combined ETH+stETH pool. Uses ceiling division.
    /// @param targetValue Target combined ETH+stETH value to receive
    /// @return burnAmount DGVE shares required to burn
    /// @return ethOut Estimated ETH output (based on current balances)
    /// @return stEthOut Estimated stETH output (based on current balances)
    /// @custom:reverts Insufficient If targetValue is 0 or exceeds available reserve
    function previewBurnForEthOut(
        uint256 targetValue
    ) external view returns (uint256 burnAmount, uint256 ethOut, uint256 stEthOut) {
        uint256 supply = ethShare.totalSupply();
        (uint256 reserve, uint256 ethBal) = _ethReservesView();
        if (targetValue == 0 || targetValue > reserve) revert Insufficient();

        burnAmount = (targetValue * supply + reserve - 1) / reserve;

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

    /// @notice Preview BURNIE output for burning a given amount of DGVB shares
    /// @param amount DGVB shares to burn
    /// @return coinOut BURNIE that would be received
    /// @custom:reverts Insufficient If amount is 0 or exceeds total supply
    function previewCoin(uint256 amount) external view returns (uint256 coinOut) {
        uint256 supply = coinShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        uint256 coinBal = _coinReservesView();
        coinOut = (coinBal * amount) / supply;
    }

    /// @notice Preview ETH/stETH output for burning a given amount of DGVE shares
    /// @param amount DGVE shares to burn
    /// @return ethOut ETH that would be sent
    /// @return stEthOut stETH that would be sent
    /// @custom:reverts Insufficient If amount is 0 or exceeds total supply
    function previewEth(uint256 amount) external view returns (uint256 ethOut, uint256 stEthOut) {
        uint256 supply = ethShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        (uint256 reserve, uint256 ethBal) = _ethReservesView();
        uint256 claimValue = (reserve * amount) / supply;

        if (claimValue <= ethBal) {
            ethOut = claimValue;
        } else {
            ethOut = ethBal;
            stEthOut = claimValue - ethBal;
        }
    }

    // ---------------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------------
    /// @dev Combine msg.value with additional vault-funded ETH
    /// @param extraValue Additional ETH to use from vault balance
    /// @return totalValue Combined ETH value (msg.value + extraValue)
    function _combinedValue(uint256 extraValue) private view returns (uint256 totalValue) {
        if (extraValue == 0) {
            return msg.value;
        }
        totalValue = msg.value + extraValue;
        if (totalValue > address(this).balance) revert Insufficient();
    }

    /// @dev Sync ETH+stETH balances and return combined total.
    /// @return ethBal Current ETH balance
    /// @return stBal Current stETH balance
    /// @return combined Sum of ETH and stETH balances
    function _syncEthReserves() private view returns (uint256 ethBal, uint256 stBal, uint256 combined) {
        ethBal = address(this).balance;
        stBal = _stethBalance();
        unchecked {
            combined = ethBal + stBal;
        }
    }

    /// @dev Sync BURNIE mint allowance tracking.
    function _syncCoinReserves() private returns (uint256 synced) {
        synced = coinToken.vaultMintAllowance();
        coinTracked = synced;
    }

    /// @dev View helper for BURNIE reserves.
    /// @return mainReserve DGVB claimable reserve (allowance + vault balance + claimable)
    function _coinReservesView() private view returns (uint256 mainReserve) {
        uint256 allowance = coinToken.vaultMintAllowance();
        mainReserve = allowance;
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinPlayer.previewClaimCoinflips(address(this));
        if (vaultBal != 0 || claimable != 0) {
            unchecked {
                mainReserve += vaultBal + claimable;
            }
        }
    }

    /// @dev View helper for ETH+stETH reserves (stETH rebase yield accrues to DGVE only)
    /// @return mainReserve DGVE claimable reserve (combined balance + claimable winnings)
    /// @return ethBal Current ETH balance
    function _ethReservesView() private view returns (uint256 mainReserve, uint256 ethBal) {
        ethBal = address(this).balance;
        uint256 stBal = _stethBalance();
        uint256 combined;
        unchecked {
            combined = ethBal + stBal;
        }
        uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
        if (claimable > 1) {
            unchecked {
                claimable -= 1;
            }
        } else {
            claimable = 0;
        }
        unchecked {
            mainReserve = combined + claimable;
        }
    }

    /// @dev Get this contract's stETH balance
    /// @return Current stETH balance of the vault
    function _stethBalance() private view returns (uint256) {
        return steth.balanceOf(address(this));
    }

    /// @dev Send ETH to recipient using low-level call (supports contracts with custom receive logic)
    /// @param to Recipient address
    /// @param amount Amount of ETH to send
    function _payEth(address to, uint256 amount) private {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @dev Transfer stETH to recipient
    /// @param to Recipient address
    /// @param amount Amount of stETH to transfer
    function _paySteth(address to, uint256 amount) private {
        if (!steth.transfer(to, amount)) revert TransferFailed();
    }

    /// @dev Pull stETH from sender (requires prior approval)
    /// @param from Address to pull stETH from
    /// @param amount Amount of stETH to pull (0 is a no-op)
    function _pullSteth(address from, uint256 amount) private {
        if (amount == 0) return;
        if (!steth.transferFrom(from, address(this), amount)) revert TransferFailed();
    }
}
