// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title WrappedWrappedXRP (WWXRP)
 * @author Burnie Degenerus
 * @notice An ERC20 token representing "Wrapped Wrapped WWXRP" - a joke prize that MIGHT be backed by actual wXRP.
 *
 * @dev WARNING: THIS IS A JOKE TOKEN!
 *      - There is NO GUARANTEE that enough wXRP exists to back all WWXRP tokens
 *      - The contract MAY be undercollateralized at any time
 *      - Unwrapping is FIRST-COME-FIRST-SERVED based on available reserves
 *      - If you get actual wXRP out, consider yourself lucky!
 *
 * @dev FEATURES:
 *      - Standard ERC20 functionality (transfer, approve, etc.)
 *      - mintPrize(): Authorized minters can award unbacked WWXRP prizes
 *      - vaultMintTo(): Vault can mint from a fixed uncirculating reserve
 *      - wrap is disabled; unwrap/donate remain available
 *
 * @dev SECURITY:
 *      - Simple ERC20 with no complex logic
 *      - Uses Solidity 0.8+ overflow protection
 *      - wXRP reserves tracked separately from supply for transparency
 *      - CEI pattern: burns before transfers
 */

import {ContractAddresses} from "./ContractAddresses.sol";

/// @notice Minimal ERC20 interface for wXRP token interactions.
interface IERC20 {
    /// @notice Transfer tokens to a recipient.
    function transfer(address to, uint256 amount) external returns (bool);
    /// @notice Transfer tokens from sender to recipient using caller's allowance.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    /// @notice Get token balance for an address.
    function balanceOf(address account) external view returns (uint256);
}

contract WrappedWrappedXRP {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Standard ERC20 events plus unwrap/donate tracking                  |
      +======================================================================+*/

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from The sender address (address(0) for mints)
    /// @param to The recipient address (address(0) for burns)
    /// @param amount The amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when an allowance is set via approve
    /// @param owner The token owner granting the allowance
    /// @param spender The address authorized to spend
    /// @param amount The approved spending limit
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when someone unwraps WWXRP back to wXRP
    /// @param user The user who unwrapped
    /// @param amount Amount of WWXRP burned (and wXRP returned)
    event Unwrapped(address indexed user, uint256 amount);

    /// @notice Emitted when someone donates wXRP to increase backing
    /// @param donor The generous donor
    /// @param amount Amount of wXRP donated
    event Donated(address indexed donor, uint256 amount);

    /// @notice Emitted when the vault spends from its uncirculating allowance
    /// @param spender The contract spending from allowance (address(this))
    /// @param amount Amount spent from allowance
    event VaultAllowanceSpent(address indexed spender, uint256 amount);

    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts                            |
      +======================================================================+*/

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when amount parameter is zero
    error ZeroAmount();

    /// @notice Thrown when sender has insufficient token balance
    error InsufficientBalance();

    /// @notice Thrown when spender has insufficient allowance
    error InsufficientAllowance();

    /// @notice Thrown when wXRP reserves are insufficient to fulfill unwrap request
    error InsufficientReserves();

    /// @notice Thrown when wXRP transfer fails
    error TransferFailed();

    /// @notice Thrown when caller is not an authorized minter
    error OnlyMinter();

    /// @notice Thrown when caller is not the vault
    error OnlyVault();

    /// @notice Thrown when vault allowance is insufficient
    error InsufficientVaultAllowance();

    /*+======================================================================+
      |                         ERC20 STATE                                  |
      +======================================================================+
      |  Standard ERC20 metadata and balances                               |
      +======================================================================+*/

    /// @notice Token name - makes it VERY clear this is a joke
    string public constant name = "Wrapped Wrapped WWXRP (PARODY)";

    /// @notice Token symbol
    string public constant symbol = "WWXRP";

    /// @notice Number of decimals (matching wXRP standard)
    uint8 public constant decimals = 18;

    /// @notice Total circulating supply of WWXRP (excludes vault allowance)
    uint256 public totalSupply;

    /// @notice Initial uncirculating reserve (1B WWXRP, 18 decimals)
    uint256 public constant INITIAL_VAULT_ALLOWANCE = 1_000_000_000 ether;

    /// @notice Remaining uncirculating reserve the vault can mint from
    uint256 public vaultAllowance = INITIAL_VAULT_ALLOWANCE;

    /// @notice Mapping of address to WWXRP balance
    mapping(address => uint256) public balanceOf;

    /// @notice Mapping of owner to spender to approved amount
    mapping(address => mapping(address => uint256)) public allowance;

    /*+======================================================================+
      |                    WIRED CONTRACTS & CONSTANTS                       |
      +======================================================================+
      |  All external dependencies are compile-time constants sourced from  |
      |  ContractAddresses. No storage slots consumed for wiring.            |
      +======================================================================+*/

    /// @notice The wXRP token contract address (compile-time constant)
    /// @dev Set in ContractAddresses library before deployment
    IERC20 internal constant wXRP = IERC20(ContractAddresses.WXRP);

    /// @dev Game contract address authorized to mint WWXRP
    address internal constant MINTER_GAME = ContractAddresses.GAME;

    /// @dev Coin contract address authorized to mint WWXRP
    address internal constant MINTER_COIN = ContractAddresses.COIN;

    /// @dev Coinflip contract address authorized to mint WWXRP
    address internal constant MINTER_COINFLIP = ContractAddresses.COINFLIP;

    /// @dev Vault contract address authorized to mint from uncirculating reserve
    address internal constant MINTER_VAULT = ContractAddresses.VAULT;

    /*+======================================================================+
      |                         wXRP RESERVES                                |
      +======================================================================+
      |  Tracks the actual wXRP backing held by this contract               |
      +======================================================================+*/

    /// @notice Actual wXRP reserves held by this contract
    /// @dev This may be LESS than totalSupply (undercollateralized joke token!)
    ///      Or MORE than totalSupply if generous souls donate
    uint256 public wXRPReserves;

    /// @notice Total supply including uncirculating vault allowance
    /// @dev Used by dashboards to show circulation + reserve.
    function supplyIncUncirculated() external view returns (uint256) {
        return totalSupply + vaultAllowance;
    }

    /// @notice Vault mint allowance remaining (uncirculating reserve)
    function vaultMintAllowance() external view returns (uint256) {
        return vaultAllowance;
    }

    /*+======================================================================+
      |                       ERC20 FUNCTIONS                                |
      +======================================================================+
      |  Standard ERC20 implementation                                      |
      +======================================================================+*/

    /// @notice Approve spender to transfer up to amount on behalf of caller
    /// @param spender The address authorized to spend
    /// @param amount The maximum amount that can be spent
    /// @return True on success
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens from caller to recipient
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return True on success
    /// @custom:reverts ZeroAddress When from or to is address(0)
    /// @custom:reverts InsufficientBalance When caller has insufficient balance
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens from sender to recipient using caller's allowance
    /// @dev If allowance is type(uint256).max, it is treated as unlimited and not decremented
    /// @param from The source address
    /// @param to The destination address
    /// @param amount The amount to transfer
    /// @return True on success
    /// @custom:reverts InsufficientAllowance When caller has insufficient allowance
    /// @custom:reverts ZeroAddress When from or to is address(0)
    /// @custom:reverts InsufficientBalance When from has insufficient balance
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowed - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @dev Internal transfer helper - moves tokens between addresses
    /// @param from The source address
    /// @param to The destination address
    /// @param amount The amount to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    /// @dev Internal mint helper - creates new tokens
    /// @param to The recipient of newly minted tokens
    /// @param amount The amount to mint
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal burn helper - destroys tokens
    /// @param from The address to burn tokens from
    /// @param amount The amount to burn
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();

        balanceOf[from] -= amount;
        totalSupply -= amount;

        emit Transfer(from, address(0), amount);
    }

    /*+======================================================================+
      |                       WRAP / UNWRAP FUNCTIONS                        |
      +======================================================================+
      |  Wrap not implemented; unwrap/donate are enabled.                     |
      +======================================================================+*/

    /// @notice Unwrap WWXRP back to wXRP at 1:1 ratio (if reserves allow!)
    /// @dev Burns WWXRP from caller, transfers wXRP to caller.
    ///      Uses CEI pattern: burns before external transfer.
    /// @param amount Amount of WWXRP to unwrap (18 decimals)
    /// @custom:reverts ZeroAmount When amount is zero
    /// @custom:reverts InsufficientReserves When wXRP reserves are insufficient
    /// @custom:reverts InsufficientBalance When caller has insufficient WWXRP
    /// @custom:reverts TransferFailed When wXRP transfer fails
    function unwrap(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // Check if we actually have enough wXRP (probably not!)
        if (wXRPReserves < amount) revert InsufficientReserves();

        // CEI pattern: burn first, transfer after
        _burn(msg.sender, amount);
        wXRPReserves -= amount;

        // Transfer wXRP back to user
        if (!wXRP.transfer(msg.sender, amount)) {
            revert TransferFailed();
        }

        emit Unwrapped(msg.sender, amount);
    }

    /// @notice Donate wXRP to increase reserves without minting WWXRP
    /// @dev For generous souls who want to improve the backing ratio
    ///      or for game contracts to add prize pool reserves
    /// @param amount Amount of wXRP to donate (18 decimals)
    /// @custom:reverts ZeroAmount When amount is zero
    /// @custom:reverts TransferFailed When wXRP transferFrom fails
    function donate(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // Transfer wXRP from donor to this contract
        if (!wXRP.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        // Increase reserves without minting (improves backing ratio!)
        wXRPReserves += amount;

        emit Donated(msg.sender, amount);
    }

    /*+======================================================================+
      |                       PRIVILEGED MINT/BURN FUNCTIONS                 |
      +======================================================================+
      |  Allows authorized minters to create/destroy WWXRP                  |
      +======================================================================+*/

    /// @notice Mint WWXRP to a recipient (for lootbox/game prizes)
    /// @dev Only callable by authorized minters (game/coin/coinflip contracts).
    ///      Mints WITHOUT backing, making the token more undercollateralized.
    /// @param to Recipient of the minted WWXRP
    /// @param amount Amount to mint (18 decimals)
    /// @custom:reverts OnlyMinter When caller is not an authorized minter
    /// @custom:reverts ZeroAmount When amount is zero
    /// @custom:reverts ZeroAddress When to is address(0)
    function mintPrize(address to, uint256 amount) external {
        if (
            msg.sender != MINTER_GAME &&
            msg.sender != MINTER_COIN &&
            msg.sender != MINTER_COINFLIP
        ) {
            revert OnlyMinter();
        }
        if (amount == 0) revert ZeroAmount();

        // Mint without backing - increases the backing deficit (perfect!)
        _mint(to, amount);
    }

    /// @notice Mint WWXRP to a recipient from the vault's uncirculating reserve
    /// @dev Only callable by the vault contract. Reduces vault allowance and mints to recipient.
    /// @param to Recipient address
    /// @param amount Amount to mint (18 decimals)
    /// @custom:reverts OnlyVault When caller is not the vault
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts InsufficientVaultAllowance When amount exceeds remaining allowance
    function vaultMintTo(address to, uint256 amount) external {
        if (msg.sender != MINTER_VAULT) revert OnlyVault();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        uint256 allowanceVault = vaultAllowance;
        if (amount > allowanceVault) revert InsufficientVaultAllowance();
        unchecked {
            vaultAllowance = allowanceVault - amount;
        }
        _mint(to, amount);
        emit VaultAllowanceSpent(address(this), amount);
    }

    /// @notice Burn WWXRP for game bets
    /// @dev Only callable by the game contract. Silently returns if amount is zero.
    /// @param from Address to burn from
    /// @param amount Amount to burn (18 decimals)
    /// @custom:reverts OnlyMinter When caller is not the game contract
    /// @custom:reverts ZeroAddress When from is address(0)
    /// @custom:reverts InsufficientBalance When from has insufficient balance
    function burnForGame(address from, uint256 amount) external {
        if (msg.sender != MINTER_GAME) revert OnlyMinter();
        if (amount == 0) return;
        _burn(from, amount);
    }
}
