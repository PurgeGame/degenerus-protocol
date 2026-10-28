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

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IVaultCoin} from "./interfaces/IVaultCoin.sol";
import {ICoinflip} from "./interfaces/ICoinflip.sol";
import {CrapsBattle} from "./CrapsBattle.sol";
import {WWXRP} from "./WWXRP.sol";
import {AFKingSubscriptionToken} from "./AFKingSubscriptionToken.sol";
import {DGNRS} from "./DGNRS.sol";
import {VaultPlayerActions} from "./libraries/VaultPlayerActions.sol";
import {BoundedCall} from "./libraries/BoundedCall.sol";

/// @dev Minimal token calls used by foreign-token recovery.
interface IERC20Sweep {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Plain NFT transfers avoid introducing a recipient callback into recovery.
interface IERC721Sweep {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/*
+========================================================================================================+
|                                        DegenerusVault                                                  |
|                     Multi-Asset Vault with Independent Share Classes                                   |
+========================================================================================================+
|                                                                                                        |
|  ARCHITECTURE OVERVIEW                                                                                 |
|  ---------------------                                                                                 |
|  DegenerusVault holds three assets (ETH, stETH, FLIP) across two independent share classes:            |
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
|  |   |  FLIP         |----►|  flipShare      |  DGVF - Claims FLIP only                              | |
|  |   +-----------------+     +-----------------+                                                     | |
|  |                                                                                                   | |
|  |   DGVE and DGVF have independent supply and proportional claim rights.                            | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              FUNDING FLOW                                                         | |
|  |                                                                                                   | |
|  |   ETH    ----► receive() donations + game claimable-winnings credits claimed by the vault         | |
|  |   stETH  ----► direct ERC20 transfers from game flows                                             | |
|  |   FLIP ----► FLIP credits the vault's mint allowance internally (virtual, no transfer)            | |
|  |                                                                                                   | |
|  |   Split: ETH+stETH accrue to DGVE. FLIP mint allowance is claimable by DGVF.                      | |
|  +---------------------------------------------------------------------------------------------------+ |
|                                                                                                        |
|  +---------------------------------------------------------------------------------------------------+ |
|  |                              CLAIM FLOW (Burn Shares)                                             | |
|  |                                                                                                   | |
|  |   User ----► burnCoin(amount) ----► Burns flipShare ----► Mints FLIP to user                      | |
|  |   User ----► burnEth(amount) -----► Burns ethShare -----► Sends ETH + stETH to user               | |
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
/// @notice Minimal ERC20 for vault share classes (DGVF, DGVE)
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
    /// @notice Token name (e.g., "Degenerus Vault Flip")
    string public name;
    /// @notice Token symbol (e.g., "DGVF")
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
    /// @param ensName_ ENS reverse name for this share class (e.g., "dgvf.degenerus.eth")
    constructor(string memory name_, string memory symbol_, string memory ensName_) {
        name = name_;
        symbol = symbol_;
        totalSupply = INITIAL_SUPPLY;
        balanceOf[ContractAddresses.CREATOR] = INITIAL_SUPPLY;
        emit Transfer(address(0), ContractAddresses.CREATOR, INITIAL_SUPPLY);

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok,) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", ensName_)
            );
            ok;
        }
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
    /// @notice Caller is not the pinned DGVE governance executor
    error NotVaultOwner();
    /// @notice The target/selector is outside the fixed player-action surface.
    error UnsupportedPlayerAction();
    /// @notice Insufficient balance, allowance, or reserve for operation
    error Insufficient();
    /// @notice ETH or token transfer failed
    error TransferFailed();

    /// @notice Token backs vault accounting and can never be swept out.
    error ProtectedToken();

    /// @notice Sweep recipient is the zero address.
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    /// @notice Emitted when ETH is donated to the vault via receive()
    /// @param from Depositor address
    /// @param ethAmount ETH deposited (via msg.value)
    /// @param stEthAmount Always 0 (stETH arrives via direct ERC20 transfers, which do not announce)
    /// @param coinAmount Always 0 (FLIP arrives as mint allowance credited inside FLIP)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stEthAmount, uint256 coinAmount);

    /// @notice Emitted when a foreign ERC20 is swept out of the vault
    /// @param token Token swept
    /// @param to Recipient
    /// @param amount Amount sent
    event TokenSwept(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when a foreign ERC721 is swept out of the vault
    /// @param token NFT contract swept from
    /// @param to Recipient
    /// @param tokenId Token serial sent
    event NftSwept(address indexed token, address indexed to, uint256 tokenId);
    /// @notice Emitted when user burns DGVF or DGVE shares to claim assets
    /// @param from User who burned shares
    /// @param sharesBurned Amount of shares burned
    /// @param ethOut ETH sent to user
    /// @param stEthOut stETH sent to user
    /// @param flipOut FLIP minted to user
    event Claim(address indexed from, uint256 sharesBurned, uint256 ethOut, uint256 stEthOut, uint256 flipOut);

    /// @notice Emitted once per craps comp the vault owner grants
    /// @param operator Vault owner who granted it
    /// @param toId Wallet ID of the account comped
    /// @param kind What was comped, as the table's `vaultComp` kind
    /// @param charged whole FLIP the comp lane paid for it
    event CrapsCompGranted(address indexed operator, uint32 indexed toId, uint8 kind, uint256 charged);

    /// @notice Comp budget was donated to a joinable custom battle or daily window.
    /// @param operator Vault owner or comp delegate who funded the pool.
    /// @param custom True for a custom battle, false for today's daily window.
    /// @param index Custom battle number or daily window period.
    /// @param charged whole FLIP charged to the comp lane and added to the pool.
    event CrapsCompDonated(address indexed operator, bool indexed custom, uint256 indexed index, uint256 charged);

    /// @notice The vault owner set what `who` may still comp, in whole FLIP
    /// @param operator The vault owner that set the allowance.
    /// @param who The address the allowance is set for.
    /// @param amount The new remaining comp allowance, in whole FLIP.
    event CrapsCompAllowanceSet(address indexed operator, address indexed who, uint256 amount);

    /// @notice An owner exercised a protocol player action as the Vault.
    event PlayerAction(address indexed operator, address indexed target, bytes4 indexed selector, uint256 value);

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
    /// @notice Share token for FLIP claims (symbol: DGVF)
    DegenerusVaultShare private immutable flipShare;
    /// @notice Share token for ETH+stETH claims (symbol: DGVE)
    DegenerusVaultShare private immutable ethShare;

    // ---------------------------------------------------------------------
    // WIRING (Constants)
    // ---------------------------------------------------------------------
    /// @dev Game contract for player actions
    IDegenerusGame internal constant gamePlayer = IDegenerusGame(ContractAddresses.GAME);
    /// @dev Coinflip contract for coinflip actions
    ICoinflip internal constant coinflipPlayer = ICoinflip(ContractAddresses.COINFLIP);
    /// @dev FLIP token contract for minting and transfers
    IVaultCoin internal constant flipToken = IVaultCoin(ContractAddresses.COIN);
    /// @dev WWXRP token contract for vault minting
    WWXRP internal constant wwxrpToken = WWXRP(payable(ContractAddresses.WWXRP));
    /// @dev AFKing seat token: capped vault mints and the vault-held seats
    AFKingSubscriptionToken internal constant afkingSubToken =
        AFKingSubscriptionToken(ContractAddresses.AFKING_SUB_TOKEN);
    /// @dev stETH (Lido) token contract
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    /// @dev DGNRS wrapper: the vault holds the DGNRS allocation and unwraps from it
    DGNRS internal constant dgnrsToken = DGNRS(payable(ContractAddresses.DGNRS));

    // ---------------------------------------------------------------------
    // LIQUIDATION-BUYER FALLBACK CONFIG (owner-settable; packed into one slot)
    // ---------------------------------------------------------------------
    /// @dev True when the vault buys liquidated accounts that sDGNRS cannot fund. Owner-gated.
    bool private _liquidationBuyEnabled;
    /// @dev ETH (wei) reserve the vault keeps untouched when acting as liquidation buyer-of-last-resort.
    ///      The game buys for the vault only while its game-side ETH (claimable + prepaid afking) >
    ///      totalBudget + this floor.
    uint96 private _liquidationVaultFloorWei;

    /// @notice whole FLIP of craps comps an address other than the vault owner may still assign
    ///         through `crapsComp` or `crapsCompDonate`. Set by the owner and charged at the
    ///         table's prices, from the same FLIP comp lane. The owner's own calls never touch it.
    mapping(address => uint256) public crapsCompAllowanceOf;

    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    /// @dev Restricts owner functions to the pinned DGVE approval executor.
    modifier onlyVaultOwner() {
        if (msg.sender != ContractAddresses.OWNER_GOVERNANCE) revert NotVaultOwner();
        _;
    }

    /// @notice Whether account is the protocol's owner executor.
    /// @dev The executor checks escrowed approval; pooled token balances confer no authority.
    /// @param account Address to check
    /// @return True if account qualifies as vault owner
    function isVaultOwner(address account) external pure returns (bool) {
        return account == ContractAddresses.OWNER_GOVERNANCE;
    }

    /// @notice Actual DGVE collateral contract, created by this Vault's constructor.
    function dgve() external view returns (address) {
        return address(ethShare);
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------

    /// @notice Deploy the vault and create all share class tokens
    /// @dev Deploys DGVF and DGVE tokens. Creator receives initial 1T supply of each.
    constructor() {
        flipShare = new DegenerusVaultShare("Degenerus Vault Flip", "DGVF", "dgvf.degenerus.eth");
        ethShare = new DegenerusVaultShare("Degenerus Vault Eth", "DGVE", "dgve.degenerus.eth");

        // Protocol-owned self-subscription: claimable-first daily lootbox buy of flat
        // quantity 1 (id 0 = the vault itself). The afking module exempts the pinned VAULT
        // wallet from the seat burn and the completed-day signup gate, so this subscribe
        // lands before the seat token is deployed and names no seat; the token's constructor
        // then mints the vault its construction seat.
        gamePlayer.subscribe(0, false, 1, 0);

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok,) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "vault.degenerus.eth")
            );
            ok;
        }
    }

    // ---------------------------------------------------------------------
    // DEPOSITS
    // ---------------------------------------------------------------------

    /// @notice Receive ETH donations from any sender
    receive() external payable {
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    // ---------------------------------------------------------------------
    // GAMEPLAY (Vault Owner)
    // ---------------------------------------------------------------------

    /// @notice Perform a protocol player action using the Vault's identity and balances.
    /// @dev Only fixed protocol target/selector pairs are allowed. This is a CALL, never a
    ///      delegatecall. Calldata and return/revert data pass through unchanged. Self-account
    ///      shorthand ID 0 resolves to the Vault where supported; funding deposits name ID 1.
    ///      Explicit IDs must satisfy the destination's account rules.
    ///      All game locks, prices, eligibility and protocol-account exclusions still apply.
    ///      Ordinary gameplay has this single entry point. Vault-specific budgets, mints,
    ///      delegation and share redemption keep their dedicated functions.
    /// @param target Protocol contract named in VaultPlayerActions.
    /// @param data ABI-encoded player function call, including its selector.
    /// @param ethValue Additional ETH from Vault reserves to send, on top of msg.value.
    /// @return result The destination's ABI-encoded return data.
    function playerAction(address target, bytes calldata data, uint256 ethValue)
        external payable onlyVaultOwner returns (bytes memory result)
    {
        if (data.length < 4 || !VaultPlayerActions.isAllowed(target, bytes4(data[:4]))) {
            revert UnsupportedPlayerAction();
        }
        uint256 value = _combinedValue(ethValue);
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        emit PlayerAction(msg.sender, target, bytes4(data[:4]), value);
    }

    /// @notice Spend the restricted Degenesis budget on tickets and lootboxes, or whale passes,
    ///         for an allocated recipient at their normal price
    /// @dev The game moves at most `maxCost` of the budget into the purchase and returns the
    ///      rest in the same call; the budget has no other way out.
    /// @param recipientId Allocated recipient account; 0 selects the Vault.
    /// @param whalePass True for whale passes, false for tickets and lootboxes
    /// @param quantity Whale passes, or ticket purchase units (400 = one whole ticket)
    /// @param boxOrder Packed box order (ignored with whale passes)
    /// @param maxCost Budget made available to the purchase
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor
    function spendDegenesis(uint32 recipientId, bool whalePass, uint256 quantity, uint256 boxOrder, uint256 maxCost)
        external
        onlyVaultOwner
    {
        gamePlayer.spendDegenesis(recipientId, whalePass, quantity, boxOrder, maxCost);
    }

    /// @notice Enable/disable the liquidation-buyer fallback and set the protected ETH reserve floor.
    /// @dev When enabled, the game routes an account liquidation to the vault as buyer when sDGNRS
    ///      cannot fund it, spending the vault's game-side ETH — claimable first, then prepaid afking
    ///      (staged via playerAction calling Game.depositAfkingFunding) — down to `floorWei`. The vault
    ///      owns the purchased account family and receives its later proceeds. This commits
    ///      DGVE backing at the same quote sDGNRS pays, so it is
    ///      vault-owner gated.
    /// @param enabled Whether the vault acts as liquidation buyer-of-last-resort.
    /// @param floorWei ETH (wei) reserve kept untouched; the vault buys only while its claimable + afking
    ///        exceeds totalBudget + floorWei.
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor.
    /// @custom:reverts Insufficient If floorWei exceeds the uint96 reserve-floor width.
    function setLiquidationBuyFallback(bool enabled, uint256 floorWei) external onlyVaultOwner {
        if (floorWei > type(uint96).max) revert Insufficient();
        _liquidationBuyEnabled = enabled;
        _liquidationVaultFloorWei = uint96(floorWei);
    }

    /// @notice The liquidation-buyer fallback config the game reads when sDGNRS cannot fund a liquidation.
    /// @return enabled Whether the vault buys liquidated accounts as last resort.
    /// @return floorWei ETH (wei) reserve the vault keeps untouched as buyer.
    function liquidationBuyConfig() external view returns (bool enabled, uint256 floorWei) {
        return (_liquidationBuyEnabled, _liquidationVaultFloorWei);
    }

    /// @notice Comp craps to whoever the vault likes — a seat, a day, future days, an upgrade or
    ///         banked passes — out of the FLIP comp lane the table feeds from every finished
    ///         battle. Priced by the table at exactly what the paid door burns; no vault asset
    ///         moves, and nothing here can set a price.
    /// @dev ALL OR NOTHING: any item the table refuses — a shut window, an occupied day, a bad
    ///      lane, a lane that cannot cover it — takes the whole batch down with it.
    /// @param codes One comp each, packed as the table's `vaultComp` reads it:
    ///              bits 0..31 the recipient's wallet ID; bits 32..159 zero; bits 160..167 the
    ///              kind (0 window · 1 day · 2 future days · 3 upgrade · 4 passes · 5 a window on
    ///              days ahead); bit 168 high; bits 176..199 the period, first day or ticket day;
    ///              bits 200..207 the count, or the upgrade's period mask; bits 208..215 the
    ///              period for kind 5.
    /// @custom:reverts NotVaultOwner If caller is neither the DGVE governance executor nor an allowance holder
    /// @custom:reverts Insufficient If the batch is empty, or exceeds the caller's allowance
    /// @custom:reverts ZeroAddress If any code names wallet ID 0
    function crapsComp(uint256[] calldata codes) external {
        (bool owner, uint256 allowance) = _crapsCompBudget();
        uint256 n = codes.length;
        if (n == 0) revert Insufficient();
        uint256 total;
        for (uint256 i; i < n; ++i) {
            uint256 code = codes[i];
            uint32 toId = uint32(code);
            if (toId == 0) revert ZeroAddress();
            uint256 charged = CrapsBattle(ContractAddresses.CRAPS).vaultComp(code);
            total += charged;
            emit CrapsCompGranted(msg.sender, toId, uint8(code >> 160), charged);
        }
        _spendCrapsCompBudget(owner, allowance, total);
    }

    /// @notice Donate comp budget to a battle pool while it is still taking entries.
    /// @dev Uses the same shared FLIP comp lane and delegate allowance as `crapsComp`.
    ///      A refused donation or insufficient allowance reverts the entire operation.
    /// @param custom True for a custom battle, false for one of today's daily windows.
    /// @param index The custom battle's number, or the daily window's period (0..5).
    /// @param granules Donation in 100-FLIP units: 10 adds 1,000 FLIP to the pool.
    /// @return charged whole FLIP charged to the comp lane and added to the pool.
    function crapsCompDonate(bool custom, uint256 index, uint24 granules) external returns (uint256 charged) {
        (bool owner, uint256 allowance) = _crapsCompBudget();
        charged = CrapsBattle(ContractAddresses.CRAPS).donate(custom, index, granules);
        _spendCrapsCompBudget(owner, allowance, charged);
        emit CrapsCompDonated(msg.sender, custom, index, charged);
    }

    function _crapsCompBudget() private view returns (bool owner, uint256 allowance) {
        owner = msg.sender == ContractAddresses.OWNER_GOVERNANCE;
        allowance = owner ? 0 : crapsCompAllowanceOf[msg.sender];
        if (!owner && allowance == 0) revert NotVaultOwner();
    }

    /// @dev Shared by grants and donations: owner calls use only the table's comp lane;
    ///      delegates also debit their individual limit by the table's actual charge.
    function _spendCrapsCompBudget(bool owner, uint256 allowance, uint256 total) private {
        if (!owner) {
            if (total > allowance) revert Insufficient();
            unchecked {
                crapsCompAllowanceOf[msg.sender] = allowance - total;
            }
        }
    }

    /// @notice Let `who` grant craps comps or donate to battle pools up to `amount` whole FLIP,
    ///         charged to the shared comp lane. Replaces any earlier figure; zero revokes.
    /// @param who The delegate.
    /// @param amount What they may still comp, in whole FLIP.
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor
    /// @custom:reverts ZeroAddress If `who` is the zero address
    function setCrapsCompAllowance(address who, uint256 amount) external onlyVaultOwner {
        if (who == address(0)) revert ZeroAddress();
        crapsCompAllowanceOf[who] = amount;
        emit CrapsCompAllowanceSet(msg.sender, who, amount);
    }

    /// @notice Mint any amount of WWXRP for free to a recipient
    /// @param to Recipient address
    /// @param amount Amount of WWXRP to mint
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor
    function wwxrpMint(address to, uint256 amount) external onlyVaultOwner {
        if (amount == 0) return;
        wwxrpToken.vaultMintTo(to, amount);
    }

    /// @notice Mint AFKing seats straight to a recipient. Seats carry deterministic default
    ///         art the recipient can restyle, so no claim step stands between the sale and the
    ///         seat.
    /// @dev The token refuses mints until all 1,000 free-tranche seats are gone, then allows
    ///      them while live seats + `amount` + the game's subscriber-set length stay within
    ///      2,000. Every subscription start burns a seat and every subscription the game
    ///      removes from its set frees one unit, so churn reopens room to sell.
    /// @param to Seat recipient
    /// @param amount Seats to mint
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor
    /// @custom:reverts FreeTrancheOpen (token) While fewer than 1,000 free seats are out
    /// @custom:reverts SeatCapReached (token) When the mint would pass the 2,000 cap
    /// @custom:reverts ZeroAddress (token) When `to` is the zero address
    function afkingSeatMint(address to, uint256 amount) external onlyVaultOwner {
        if (amount == 0) return;
        afkingSubToken.vaultMintSeats(to, amount);
    }

    /// @notice Unwrap vault-held DGNRS into soulbound sDGNRS for `recipient`.
    /// @dev Subject to the wrapper's lifetime unwrap cap (40B DGNRS), whole-token minimum and the
    ///      RNG-lock block; those checks revert on the wrapper side.
    /// @param recipient Receives the soulbound sDGNRS
    /// @param amount Amount of DGNRS to unwrap (12 decimals)
    /// @custom:reverts NotVaultOwner If caller is not the DGVE governance executor
    function dgnrsUnwrapTo(address recipient, uint256 amount) external onlyVaultOwner {
        dgnrsToken.unwrapTo(recipient, amount);
    }

    /// @notice Sweep a foreign ERC20 out of the vault.
    /// @dev Access: vault owner. Rescues foreign tokens sent here, which otherwise have no exit.
    ///      stETH is permanently excluded: it sits here as a real balance backing DGVE, so
    ///      sweeping it would move value out from under holders. FLIP needs no exclusion —
    ///      FLIP redirects VAULT-destined transfers and mints into vaultMintAllowance, so this
    ///      contract never holds a FLIP balance to sweep. Nor does sDGNRS, which is soulbound
    ///      and has no transfer function to call.
    /// @param token Foreign ERC20 to sweep.
    /// @param to Recipient.
    /// @param amount Amount to send; zero sweeps the full balance.
    /// @custom:reverts NotVaultOwner If caller is not the vault owner.
    /// @custom:reverts ZeroAddress If `to` is the zero address.
    /// @custom:reverts ProtectedToken If `token` backs vault accounting.
    /// @custom:reverts Insufficient If the vault holds less than `amount`, or holds nothing.
    /// @custom:reverts TransferFailed If the token transfer returns false.
    function sweepToken(address token, address to, uint256 amount) external onlyVaultOwner {
        if (to == address(0)) revert ZeroAddress();
        if (token == ContractAddresses.STETH_TOKEN) revert ProtectedToken();

        uint256 bal = IERC20Sweep(token).balanceOf(address(this));
        uint256 send = amount == 0 ? bal : amount;
        if (send == 0 || send > bal) revert Insufficient();
        if (!IERC20Sweep(token).transfer(to, send)) revert TransferFailed();
        emit TokenSwept(token, to, send);
    }

    /// @notice Sweep a foreign ERC721 out of the vault.
    /// @dev Access: vault owner. Rescues NFTs sent here by outside parties, which otherwise
    ///      have no exit, and moves the Vault's AFKing seats.
    ///      No exclusion list, because nothing here needs one: the vault reads no NFT
    ///      ownership or balance for accounting; its own subscription needs no seat; and
    ///      deity passes are soulbound, so they revert on their own.
    ///      Plain transferFrom, not safeTransferFrom: the caller picks `to`, and the receiver
    ///      hook would only add a failure mode on contract recipients.
    /// @param token NFT contract to sweep from.
    /// @param to Recipient.
    /// @param tokenId Token serial to send.
    /// @custom:reverts NotVaultOwner If caller is not the vault owner.
    /// @custom:reverts ZeroAddress If `to` is the zero address.
    function sweepNft(address token, address to, uint256 tokenId) external onlyVaultOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC721Sweep(token).transferFrom(address(this), to, tokenId);
        emit NftSwept(token, to, tokenId);
    }

    // ---------------------------------------------------------------------
    // CLAIMS (Burn Shares to Redeem Assets)
    // ---------------------------------------------------------------------

    /// @notice Burn DGVF shares to redeem proportional FLIP
    /// @dev Formula: flipOut = (DGVF reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      Claims outstanding coinflip winnings into the vault's mint allowance, then mints
    ///      the whole redemption from that allowance.
    /// @param amount Amount of DGVF shares to burn
    /// @return flipOut Amount of FLIP sent to caller
    /// @custom:reverts Insufficient If amount is 0 or reserve is insufficient
    function burnCoin(uint256 amount) external returns (uint256 flipOut) {
        DegenerusVaultShare share = flipShare;
        if (amount == 0) revert Insufficient();

        // No balanceOf leg: FLIP._transfer and _mint both redirect VAULT-destined FLIP into
        // vaultMintAllowance and return before crediting balanceOf, so this contract's FLIP
        // reserve is the allowance plus what is still claimable from coinflip.
        uint256 coinBal = flipToken.vaultMintAllowance();
        uint256 claimable = coinflipPlayer.previewClaimCoinflips(address(this));
        coinBal += claimable;

        // vaultBurn returns the pre-burn supply, so no separate totalSupply() round-trip is
        // needed; it touches only share-token storage, never the coin/coinflip state read above.
        uint256 supplyBefore = share.vaultBurn(msg.sender, amount);
        flipOut = (coinBal * amount) / supplyBefore;
        if (supplyBefore == amount) {
            share.vaultMint(msg.sender, REFILL_SUPPLY);
        }

        emit Claim(msg.sender, amount, 0, 0, flipOut);
        if (flipOut != 0) {
            if (claimable != 0) {
                // Claiming credits vaultMintAllowance, not balanceOf: the payout runs through
                // FLIP._mint, which intercepts VAULT-destined mints into the allowance. That
                // allowance is exactly what vaultMintTo below spends, so the claim funds the
                // whole redemption rather than a separate transferable leg.
                coinflipPlayer.claimCoinflips(0, flipOut);
            }

            // Any over-mint attempt reverts inside vaultMintTo against the live allowance.
            flipToken.vaultMintTo(msg.sender, flipOut);
        }
    }

    /// @notice Burn DGVE shares to redeem proportional ETH and stETH
    /// @dev ETH is preferred over stETH (uses ETH first, then stETH for remainder).
    ///      Formula: claimValue = (DGVE reserve * sharesBurned) / totalSupply.
    ///      If burning entire supply, caller receives 1T new shares (refill mechanism).
    ///      May auto-claim game winnings, then withdraw prepaid afking funding, if needed to
    ///      fulfill the redemption.
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
        uint256 reserve = combined + claimable + gamePlayer.afkingFundingOf(address(this));
        uint256 claimValue = (reserve * amount) / supplyBefore;

        // Short of the vault's own balance: claim winnings first, then withdraw the rest from
        // the prepaid afking funding. After game over the claim also pays the afking balance,
        // so the withdrawal is capped at what is left.
        if (claimValue > combined) {
            if (claimable != 0) {
                gamePlayer.claimClaimable(0);
                ethBal = address(this).balance;
                stBal = _stethBalance();
            }
            if (claimValue > ethBal + stBal) {
                uint256 shortfall = claimValue - ethBal - stBal;
                uint256 afking = gamePlayer.afkingFundingOf(address(this));
                gamePlayer.withdrawAfkingFunding(0, shortfall < afking ? shortfall : afking);
                ethBal = address(this).balance;
                stBal = _stethBalance(); // the withdrawal falls back to stETH when the game's ETH is short
            }
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

    /// @notice Calculate DGVF shares required to receive a target FLIP amount
    /// @dev Uses ceiling division to ensure user burns enough shares
    /// @param flipOut Target FLIP amount to receive
    /// @return burnAmount DGVF shares required to burn
    /// @custom:reverts Insufficient If flipOut is 0 or exceeds available reserve
    function previewBurnForCoinOut(uint256 flipOut) external view returns (uint256 burnAmount) {
        uint256 reserve = _coinReservesView();
        if (flipOut == 0 || flipOut > reserve) revert Insufficient();
        uint256 supply = flipShare.totalSupply();
        burnAmount = (flipOut * supply + reserve - 1) / reserve;
    }

    /// @notice Calculate DGVE shares required to receive a target ETH-equivalent value
    /// @dev Value = DGVE's share of the combined ETH+stETH pool. Uses ceiling division.
    /// @param targetValue Target combined ETH+stETH value to receive
    /// @return burnAmount DGVE shares required to burn
    /// @return ethOut Estimated ETH output (based on current balances)
    /// @return stEthOut Estimated stETH output (based on current balances)
    /// @custom:reverts Insufficient If targetValue is 0 or exceeds available reserve
    function previewBurnForEthOut(uint256 targetValue)
        external
        view
        returns (uint256 burnAmount, uint256 ethOut, uint256 stEthOut)
    {
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

    /// @notice Preview FLIP output for burning a given amount of DGVF shares
    /// @param amount DGVF shares to burn
    /// @return flipOut FLIP that would be received
    /// @custom:reverts Insufficient If amount is 0 or exceeds total supply
    function previewCoin(uint256 amount) external view returns (uint256 flipOut) {
        uint256 supply = flipShare.totalSupply();
        if (amount == 0 || amount > supply) revert Insufficient();
        uint256 coinBal = _coinReservesView();
        flipOut = (coinBal * amount) / supply;
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

    /// @dev Current ETH and stETH balances and their sum.
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

    /// @dev View helper for FLIP reserves.
    /// @return mainReserve DGVF claimable reserve (vault mint allowance + claimable coinflip winnings)
    function _coinReservesView() private view returns (uint256 mainReserve) {
        mainReserve = flipToken.vaultMintAllowance();
        uint256 claimable = coinflipPlayer.previewClaimCoinflips(address(this));
        unchecked {
            mainReserve += claimable;
        }
    }

    /// @dev View helper for ETH+stETH reserves (stETH rebase yield accrues to DGVE only)
    /// @return mainReserve DGVE claimable reserve (combined balance + claimable winnings +
    ///         prepaid afking funding)
    /// @return ethBal Current ETH balance
    function _ethReservesView() private view returns (uint256 mainReserve, uint256 ethBal) {
        uint256 combined;
        (ethBal,, combined) = _syncEthReserves();
        unchecked {
            mainReserve = combined + _netClaimableWinnings() + gamePlayer.afkingFundingOf(address(this));
        }
    }

    /// @dev Get this contract's stETH balance
    /// @return Current stETH balance of the vault
    function _stethBalance() private view returns (uint256) {
        return BoundedCall.stethBalanceOrZero(ContractAddresses.STETH_TOKEN, address(this));
    }

    /// @dev Send ETH to recipient using low-level call (supports contracts with custom receive logic)
    /// @param to Recipient address
    /// @param amount Amount of ETH to send
    function _payEth(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @dev Transfer stETH to recipient
    /// @param to Recipient address
    /// @param amount Amount of stETH to transfer
    function _paySteth(address to, uint256 amount) private {
        if (!steth.transfer(to, amount)) revert TransferFailed();
    }
}
