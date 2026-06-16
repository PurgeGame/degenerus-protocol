// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IVaultCoin} from "./interfaces/IVaultCoin.sol";

/// @notice Interface for game player actions on DegenerusGame contract used by DegenerusVault.
interface IDegenerusGamePlayerActions {
    /// @notice Crank the unified keeper router (advance + box opens), paying any earned bounty.
    function mintBurnie() external;
    /// @notice Queue this caller's perpetual tickets for levels 1-100 (VAULT/SDGNRS only, once).
    function initPerpetualTickets() external;
    /// @notice Start or extend a daily afking subscription for `player` (self when 0/msg.sender).
    /// @dev v55.0 ARCH-03: the afking subscription surface is GAME-resident (AfKing dissolved).
    ///      The vault self-subscribes (player == address(this) == msg.sender) so the GAME's
    ///      SUB-02 self-consent path passes with no operator approval.
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct,
        address fundingSource
    ) external payable;
    /// @notice Purchase tickets and/or lootboxes.
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    /// @notice Claim accumulated ETH winnings for a player.
    function claimWinnings(address player) external;
    /// @notice Claim winnings preferring stETH over ETH.
    function claimWinningsStethFirst() external;
    /// @notice Claim whale pass for a player.
    function claimWhalePass(address player) external;
    /// @notice Purchase a deity pass with ETH.
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable;
    /// @notice Place full-ticket bets on degenerette.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable;
    /// @notice Resolve degenerette bets for a player.
    function resolveDegeneretteBets(address player, uint64[] calldata betIds) external;
    /// @notice Set operator approval for a player.
    function setOperatorApproval(address operator, bool approved) external;
    /// @notice View claimable ETH winnings for a player.
    function claimableWinningsOf(address player) external view returns (uint256);
    /// @notice Purchase tickets using BURNIE.
    function redeemBurnie(
        address buyer,
        uint256 ticketQuantity
    ) external;
    /// @notice Sell far-future ticket entries to sDGNRS for current-level tickets + cash.
    function sellFarFutureTickets(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external;
    /// @notice Withdraw the caller's prepaid afking ETH (sends to the caller).
    function withdrawAfkingFunding(uint256 amount) external;
    /// @notice The caller's prepaid afking ETH balance.
    function afkingFundingOf(address player) external view returns (uint256);
}

/// @notice Interface for coinflip player actions used by DegenerusVault.
interface ICoinflipPlayerActions {
    /// @notice Deposit BURNIE into daily coinflip system.
    function depositCoinflip(address player, uint256 amount) external;
    /// @notice Claim coinflip winnings (exact amount).
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    /// @notice Preview claimable coinflip winnings for a player.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    /// @notice Configure auto-rebuy mode for coinflips.
    function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;
    /// @notice Set auto-rebuy take-profit threshold for coinflips.
    function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external;
}

/// @notice Interface for BurnieCoin decimator burn used by DegenerusVault.
interface ICoinPlayerActions {
    /// @notice Burn BURNIE for decimator jackpot eligibility.
    function decimatorBurn(address player, uint256 amount) external;
}

/// @notice Interface for sDGNRS player actions used by DegenerusVault.
interface IStakedDegenerusStonkBurn {
    /// @notice Burn sDGNRS to claim proportional backing assets.
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
    /// @notice Claim a resolved gambling-burn redemption for `player` on day `day` (SPEC-02 composite key).
    function claimRedemption(address player, uint24 day) external;
}

/// @notice Interface for WWXRP vault-minting used by DegenerusVault.
interface IWWXRPMint {
    /// @notice Mint WWXRP to a recipient from vault's uncirculating reserve.
    function vaultMintTo(address to, uint256 amount) external;
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
|  |                              FUNDING FLOW                                                         | |
|  |                                                                                                   | |
|  |   ETH    ----► receive() donations + game claimable-winnings credits claimed by the vault         | |
|  |   stETH  ----► direct ERC20 transfers from game flows                                             | |
|  |   BURNIE ----► BurnieCoin credits the vault's mint allowance internally (virtual, no transfer)    | |
|  |                                                                                                   | |
|  |   Split: ETH+stETH accrue to DGVE. BURNIE mint allowance is claimable by DGVB.                    | |
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
|  • ETH donations are open (receive)                                                                    |
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
    /// @custom:reverts ZeroAddress If to is address(0)
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
    function vaultMint(address to, uint256 amount) external onlyVault {
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
    /// @return supplyBefore Total supply before this burn (saves the caller a totalSupply() round-trip)
    /// @custom:reverts Unauthorized If caller is not the vault
    /// @custom:reverts Insufficient If from balance is less than amount
    function vaultBurn(address from, uint256 amount) external onlyVault returns (uint256 supplyBefore) {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        supplyBefore = totalSupply;
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply = supplyBefore - amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // ---------------------------------------------------------------------
    // INTERNAL HELPERS
    // ---------------------------------------------------------------------
    /// @dev Internal transfer logic with balance and destination zero-address check (to only)
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
    /// @notice Caller does not hold >50.1% of DGVE supply
    error NotVaultOwner();
    /// @notice Insufficient balance, allowance, or reserve for operation
    error Insufficient();
    /// @notice ETH or token transfer failed
    error TransferFailed();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @notice Emitted when ETH is donated to the vault via receive()
    /// @param from Depositor address
    /// @param ethAmount ETH deposited (via msg.value)
    /// @param stEthAmount Always 0 (stETH arrives via direct ERC20 transfers, which do not announce)
    /// @param coinAmount Always 0 (BURNIE arrives as mint allowance credited inside BurnieCoin)
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
    /// @dev Game contract for player actions
    IDegenerusGamePlayerActions internal constant gamePlayer =
        IDegenerusGamePlayerActions(ContractAddresses.GAME);
    /// @dev Coinflip contract for coinflip actions
    ICoinflipPlayerActions internal constant coinflipPlayer =
        ICoinflipPlayerActions(ContractAddresses.COINFLIP);
    /// @dev Coin contract for decimator actions
    ICoinPlayerActions internal constant coinPlayer =
        ICoinPlayerActions(ContractAddresses.COIN);
    /// @dev BURNIE token contract for minting and transfers
    IVaultCoin internal constant coinToken = IVaultCoin(ContractAddresses.COIN);
    /// @dev WWXRP token contract for vault minting
    IWWXRPMint internal constant wwxrpToken = IWWXRPMint(ContractAddresses.WWXRP);
    /// @dev stETH (Lido) token contract
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    /// @dev sDGNRS contract for burning vault-held sDGNRS
    IStakedDegenerusStonkBurn internal constant sdgnrsToken =
        IStakedDegenerusStonkBurn(ContractAddresses.SDGNRS);

    // ---------------------------------------------------------------------
    // SALVAGE-BUYER FALLBACK CONFIG (owner-settable; packed into one slot)
    // ---------------------------------------------------------------------
    /// @dev True when the vault buys far-future salvage tickets that sDGNRS cannot fund. Owner-gated.
    bool private _salvageBuyEnabled;
    /// @dev ETH (wei) reserve the vault keeps untouched when acting as salvage buyer-of-last-resort.
    ///      The game buys for the vault only while its game-side ETH (claimable + prepaid afking) >=
    ///      totalBudget + this floor.
    uint96 private _salvageVaultFloorWei;

    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    /// @dev Restricts function to accounts holding >50.1% of DGVE supply
    modifier onlyVaultOwner() {
        if (!_isVaultOwner(msg.sender)) revert NotVaultOwner();
        _;
    }

    /// @dev Check if account holds >50.1% of DGVE supply (balance * 1000 > supply * 501)
    /// @param account Address to check
    /// @return True if account qualifies as vault owner
    function _isVaultOwner(address account) private view returns (bool) {
        uint256 supply = ethShare.totalSupply();
        uint256 balance = ethShare.balanceOf(account);
        return balance * 1000 > supply * 501;
    }

    /// @notice Check if account holds >50.1% of DGVE supply
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

        // SUB-09 protocol-owned self-subscription: claimable-only daily lootbox
        // buy of flat quantity 1, no reinvest, no BURNIE rebuy. Self-consent —
        // the vault IS the player (player == msg.sender). The vault holds the
        // permanent deity pass (granted in the DegenerusGame constructor), so the
        // afking's pass-OR-pay gate takes the free 30-day extend at zero cost.
        // v55.0 ARCH-03: the afking surface is GAME-resident (AfKing dissolved);
        // self-subscribe directly against the GAME (subscriber == msg.sender ⇒
        // the GAME's SUB-02 self-consent path, no operator approval needed).
        gamePlayer.subscribe(address(this), true, false, 1, 0, address(0));

        // Queue this vault's perpetual tickets (levels 1-100). Moved out of the GAME
        // constructor so GAME's deploy stays under the per-tx gas cap.
        gamePlayer.initPerpetualTickets();
    }

    // ---------------------------------------------------------------------
    // DEPOSITS
    // ---------------------------------------------------------------------

    /// @notice Receive ETH donations from any sender
    receive() external payable {
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    /// @notice Recover the vault's prepaid afking ETH back into vault reserves.
    /// @dev Permissionless (no owner gate): game.withdrawAfkingFunding sends to the CALLER (this
    ///      vault), so the recovered ETH only ever lands in the vault's own receive() — an external
    ///      trigger cannot redirect it. A zero balance is a no-op (withdrawAfkingFunding(0) returns).
    ///      Available anytime pre-sweep; reverts after the 30-day final sweep (the afking reservation
    ///      is forfeited with claimablePool, claimable-equivalent — GAMEOVER-02).
    function recoverAfkingFunding() external {
        gamePlayer.withdrawAfkingFunding(gamePlayer.afkingFundingOf(address(this)));
    }

    // ---------------------------------------------------------------------
    // GAMEPLAY (Vault Owner)
    // ---------------------------------------------------------------------

    /// @notice Crank the game keeper router on behalf of the vault (advance + box opens)
    /// @dev Requires caller to hold >50.1% of DGVE supply. Routes through mintBurnie so the
    ///      vault earns the keeper bounty for the work; reverts NoWork() when nothing is due.
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function gameAdvance() external onlyVaultOwner {
        gamePlayer.mintBurnie();
    }

    /// @notice Purchase tickets and lootboxes for the vault
    /// @dev Combines msg.value with vault ETH balance if ethValue > 0
    /// @param ticketQuantity Number of tickets to purchase
    /// @param lootBoxAmount Number of lootboxes to purchase
    /// @param affiliateCode Affiliate code for referral tracking
    /// @param payKind Payment method for minting
    /// @param ethValue Additional ETH from vault balance to use (on top of msg.value)
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
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
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    /// @custom:reverts Insufficient If ticketQuantity is zero
    function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner {
        if (ticketQuantity == 0) revert Insufficient();
        gamePlayer.redeemBurnie(address(this), ticketQuantity);
    }

    /// @notice Purchase a deity pass using an active boon for the vault
    /// @dev Uses vault ETH + claimable winnings; forwards priceWei to the deity pass contract.
    /// @param priceWei Expected deity pass price (24 + T(n) ETH where T(n) = n*(n+1)/2)
    /// @param symbolId The deity symbol to mint (0-based index into deity pass types)
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    /// @custom:reverts Insufficient If price is zero or vault cannot fund the purchase
    function gamePurchaseDeityPassFromBoon(uint256 priceWei, uint8 symbolId) external payable onlyVaultOwner {
        if (priceWei == 0) revert Insufficient();
        if (address(this).balance < priceWei) {
            uint256 claimable = gamePlayer.claimableWinningsOf(address(this));
            if (claimable > 1) {
                gamePlayer.claimWinnings(address(this));
            }
        }
        if (address(this).balance < priceWei) revert Insufficient();
        gamePlayer.purchaseDeityPass{value: priceWei}(address(this), symbolId);
    }

    /// @notice Claim winnings for the vault (preferring stETH)
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function gameClaimWinnings() external onlyVaultOwner {
        gamePlayer.claimWinningsStethFirst();
    }

    /// @notice Claim a whale pass for the vault
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function gameClaimWhalePass() external onlyVaultOwner {
        gamePlayer.claimWhalePass(address(this));
    }

    /// @notice Place a Degenerette bet using ETH (and/or claimable winnings)
    /// @dev Uses msg.value + ethValue from vault balance. If underfunded, claimable winnings are used.
    /// @param amountPerTicket Bet amount per ticket
    /// @param ticketCount Number of tickets (must satisfy game rules)
    /// @param customTicket Custom packed traits
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero
    /// @param ethValue Additional ETH from vault balance to use (on top of msg.value)
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    /// @custom:reverts Insufficient If msg.value + ethValue exceeds vault balance
    function gameDegeneretteBet(
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant,
        uint256 ethValue
    ) external payable onlyVaultOwner {
        uint256 value;
        if (currency == 0) {
            // Overpay (value > amountPerTicket * ticketCount) reverts game-side: the module's
            // _collectBetFunds rejects ethPaid > totalBet with the identical formula.
            value = _combinedValue(ethValue);
        }
        gamePlayer.placeDegeneretteBet{value: value}(
            address(this),
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        );
    }

    /// @notice Resolve Degenerette bets for the vault
    /// @param betIds Bet identifiers to resolve
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner {
        gamePlayer.resolveDegeneretteBets(address(this), betIds);
    }

    /// @notice Salvage the vault's far-future tickets to sDGNRS (current tickets + cash) — vault owner.
    /// @dev The >50.1% DGVE holder can trim VAULT's far inventory. VAULT self-calls (no operator).
    function gameSellFarFutureTickets(
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external onlyVaultOwner {
        gamePlayer.sellFarFutureTickets(address(this), levels, quantities, queueIndices);
    }

    /// @notice Enable/disable the salvage-buyer fallback and set the protected ETH reserve floor.
    /// @dev When enabled, the game routes a far-future salvage swap to the vault as buyer when sDGNRS
    ///      cannot fund it, spending the vault's game-side ETH — claimable first, then prepaid afking
    ///      (staged from reserves via the game's depositAfkingFunding) — down to `floorWei`, plus
    ///      vault-owned BURNIE, and parking the bought far-future tickets in the vault. This commits
    ///      DGVE/DGVB backing as buyer-of-last-resort at the same -EV quote sDGNRS pays, so it is
    ///      vault-owner gated.
    /// @param enabled Whether the vault acts as salvage buyer-of-last-resort.
    /// @param floorWei ETH (wei) reserve kept untouched; the vault buys only while its claimable + afking
    ///        covers totalBudget + floorWei.
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE.
    /// @custom:reverts Insufficient If floorWei exceeds the uint96 reserve-floor width.
    function setSalvageBuyFallback(bool enabled, uint256 floorWei) external onlyVaultOwner {
        if (floorWei > type(uint96).max) revert Insufficient();
        _salvageBuyEnabled = enabled;
        _salvageVaultFloorWei = uint96(floorWei);
    }

    /// @notice The salvage-buyer fallback config the game reads when sDGNRS cannot fund a salvage swap.
    /// @return enabled Whether the vault buys far-future salvage tickets as last resort.
    /// @return floorWei ETH (wei) reserve the vault keeps untouched as buyer.
    function salvageBuyConfig() external view returns (bool enabled, uint256 floorWei) {
        return (_salvageBuyEnabled, _salvageVaultFloorWei);
    }

    /// @notice Approve or revoke an operator for the vault's game actions
    /// @param operator Address to approve or revoke
    /// @param approved Whether to approve or revoke
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner {
        gamePlayer.setOperatorApproval(operator, approved);
    }

    /// @notice Deposit coins into coinflip for the vault
    /// @param amount Amount of coins to deposit
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function coinDepositCoinflip(uint256 amount) external onlyVaultOwner {
        coinflipPlayer.depositCoinflip(address(this), amount);
    }

    /// @notice Claim coinflip winnings for the vault
    /// @param amount Maximum amount to claim
    /// @return claimed Actual amount claimed
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed) {
        return coinflipPlayer.claimCoinflips(address(this), amount);
    }

    /// @notice Burn coins in the decimator for the vault
    /// @param amount Amount of coins to burn
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function coinDecimatorBurn(uint256 amount) external onlyVaultOwner {
        coinPlayer.decimatorBurn(address(this), amount);
    }

    /// @notice Configure coinflip auto-rebuy for the vault
    /// @param enabled Whether auto-rebuy should be enabled
    /// @param takeProfit Amount to take profit
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner {
        coinflipPlayer.setCoinflipAutoRebuy(address(this), enabled, takeProfit);
    }

    /// @notice Set coinflip auto-rebuy take profit for the vault
    /// @param takeProfit Amount to take profit
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner {
        coinflipPlayer.setCoinflipAutoRebuyTakeProfit(address(this), takeProfit);
    }

    /// @notice Mint WWXRP from the vault's uncirculating reserve to a recipient
    /// @param to Recipient address
    /// @param amount Amount of WWXRP to mint
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function wwxrpMint(address to, uint256 amount) external onlyVaultOwner {
        if (amount == 0) return;
        wwxrpToken.vaultMintTo(to, amount);
    }

    /// @notice Burn vault-held sDGNRS to claim proportional backing assets
    /// @dev ETH/stETH received flows into vault reserves, increasing DGVE value.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received
    /// @return stethOut stETH received
    /// @return burnieOut BURNIE received
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function sdgnrsBurn(uint256 amount) external onlyVaultOwner returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        return sdgnrsToken.burn(amount);
    }

    /// @notice Claim a resolved sDGNRS gambling-burn redemption for day `day` on behalf of the vault.
    /// @dev Caller must pass the wall-clock day for which the vault holds an unresolved+resolved
    ///      gambling-burn entry (SPEC-02 composite key). Reverts if no such entry exists or the
    ///      day has not been resolved.
    /// @param day Wall-clock day whose redemption to claim.
    /// @custom:reverts NotVaultOwner If caller does not hold >50.1% of DGVE
    function sdgnrsClaimRedemption(uint24 day) external onlyVaultOwner {
        sdgnrsToken.claimRedemption(address(this), day);
    }

    // ---------------------------------------------------------------------
    // CLAIMS (Burn Shares to Redeem Assets)
    // ---------------------------------------------------------------------

    /// @notice Burn DGVB shares to redeem proportional BURNIE
    /// @dev Formula: coinOut = (DGVB reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      Pays from vault balance first, then claimable coinflips, then mints remainder.
    /// @param amount Amount of DGVB shares to burn
    /// @return coinOut Amount of BURNIE sent to caller
    /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
    /// @custom:reverts TransferFailed If BURNIE transfer fails
    function burnCoin(uint256 amount) external returns (uint256 coinOut) {
        DegenerusVaultShare share = coinShare;
        if (amount == 0) revert Insufficient();

        uint256 coinBal = coinToken.vaultMintAllowance();
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinflipPlayer.previewClaimCoinflips(address(this));
        coinBal += vaultBal + claimable;

        // vaultBurn returns the pre-burn supply, so no separate totalSupply() round-trip is
        // needed; it touches only share-token storage, never the coin/coinflip state read above.
        uint256 supplyBefore = share.vaultBurn(msg.sender, amount);
        coinOut = (coinBal * amount) / supplyBefore;
        if (supplyBefore == amount) {
            share.vaultMint(msg.sender, REFILL_SUPPLY);
        }

        emit Claim(msg.sender, amount, 0, 0, coinOut);
        if (coinOut != 0) {
            uint256 remaining = coinOut;
            if (vaultBal != 0) {
                uint256 payBal = remaining <= vaultBal ? remaining : vaultBal;
                remaining -= payBal;
                if (!coinToken.transfer(msg.sender, payBal)) revert TransferFailed();
            }

            if (remaining != 0 && claimable != 0) {
                uint256 claimed = coinflipPlayer.claimCoinflips(address(this), remaining);
                if (claimed != 0) {
                    remaining -= claimed;
                    if (!coinToken.transfer(msg.sender, claimed)) revert TransferFailed();
                }
            }

            if (remaining != 0) {
                // Any over-mint attempt reverts inside vaultMintTo against the live allowance.
                coinToken.vaultMintTo(msg.sender, remaining);
            }
        }
    }

    /// @notice Burn DGVE shares to redeem proportional ETH and stETH
    /// @dev ETH is preferred over stETH (uses ETH first, then stETH for remainder).
    ///      Formula: claimValue = (DGVE reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      May auto-claim game winnings if needed to fulfill the redemption.
    /// @param amount Amount of DGVE shares to burn
    /// @return ethOut Amount of ETH sent to caller
    /// @return stEthOut Amount of stETH sent to caller
    /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
    /// @custom:reverts TransferFailed If ETH or stETH transfer fails
    function burnEth(uint256 amount) external returns (uint256 ethOut, uint256 stEthOut) {
        DegenerusVaultShare share = ethShare;
        if (amount == 0) revert Insufficient();

        (uint256 ethBal, uint256 stBal, uint256 combined) = _syncEthReserves();
        uint256 claimable = _netClaimableWinnings();
        uint256 supplyBefore = share.totalSupply();
        uint256 reserve = combined + claimable;
        uint256 claimValue = (reserve * amount) / supplyBefore;

        // claimValue > combined arithmetically implies claimable != 0 for any amount that the
        // vaultBurn below accepts (claimValue <= reserve = combined + claimable when
        // amount <= supplyBefore), so no extra conjunct is needed here.
        if (claimValue > combined) {
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

        share.vaultBurn(msg.sender, amount);
        if (supplyBefore == amount) {
            share.vaultMint(msg.sender, REFILL_SUPPLY);
        }

        emit Claim(msg.sender, amount, ethOut, stEthOut, 0);

        if (stEthOut != 0) _paySteth(msg.sender, stEthOut);
        if (ethOut != 0) _payEth(msg.sender, ethOut);
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

    /// @dev Net claimable game winnings (the 1-wei sentinel the game retains is not claimable).
    /// @return claimable Claimable winnings minus the sentinel wei; 0 when nothing is claimable
    function _netClaimableWinnings() private view returns (uint256 claimable) {
        claimable = gamePlayer.claimableWinningsOf(address(this));
        claimable = claimable <= 1 ? 0 : claimable - 1;
    }

    /// @dev View helper for BURNIE reserves.
    /// @return mainReserve DGVB claimable reserve (allowance + vault balance + claimable)
    function _coinReservesView() private view returns (uint256 mainReserve) {
        uint256 allowance = coinToken.vaultMintAllowance();
        mainReserve = allowance;
        uint256 vaultBal = coinToken.balanceOf(address(this));
        uint256 claimable = coinflipPlayer.previewClaimCoinflips(address(this));
        unchecked {
            mainReserve += vaultBal + claimable;
        }
    }

    /// @dev View helper for ETH+stETH reserves (stETH rebase yield accrues to DGVE only)
    /// @return mainReserve DGVE claimable reserve (combined balance + claimable winnings)
    /// @return ethBal Current ETH balance
    function _ethReservesView() private view returns (uint256 mainReserve, uint256 ethBal) {
        uint256 combined;
        (ethBal, , combined) = _syncEthReserves();
        unchecked {
            mainReserve = combined + _netClaimableWinnings();
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
}
