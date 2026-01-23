// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
 *      - wrap(): Deposit wXRP, receive WWXRP 1:1 (increases backing)
 *      - unwrap(): Burn WWXRP, receive wXRP 1:1 IF sufficient reserves exist
 *      - donate(): Anyone can donate wXRP to increase reserves (charitable souls)
 *
 * @dev SECURITY:
 *      - Simple ERC20 with no complex logic
 *      - Uses Solidity 0.8+ overflow protection
 *      - wXRP reserves tracked separately from supply for transparency
 *      - CEI pattern: burns before transfers
 */

import {ContractAddresses} from "./ContractAddresses.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract WrappedWrappedXRP {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Standard ERC20 events plus wrap/unwrap/donate tracking             |
      +======================================================================+*/

    /// @notice Standard ERC20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Standard ERC20 approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when someone wraps wXRP into WWXRP
    /// @param user The user who wrapped
    /// @param amount Amount of wXRP wrapped (and WWXRP minted)
    event Wrapped(address indexed user, uint256 amount);

    /// @notice Emitted when someone unwraps WWXRP back to wXRP
    /// @param user The user who unwrapped
    /// @param amount Amount of WWXRP burned (and wXRP returned)
    event Unwrapped(address indexed user, uint256 amount);

    /// @notice Emitted when someone donates wXRP to increase backing
    /// @param donor The generous donor
    /// @param amount Amount of wXRP donated
    event Donated(address indexed donor, uint256 amount);

    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts                            |
      +======================================================================+*/

    /// @notice Zero address not allowed
    error ZeroAddress();

    /// @notice Amount must be greater than zero
    error ZeroAmount();

    /// @notice Insufficient balance
    error InsufficientBalance();

    /// @notice Insufficient allowance
    error InsufficientAllowance();

    /// @notice Insufficient wXRP reserves to fulfill unwrap request
    error InsufficientReserves();

    /// @notice wXRP transfer failed
    error TransferFailed();

    /// @notice Caller is not authorized to mint
    error OnlyMinter();

    /*+======================================================================+
      |                         ERC20 STATE                                  |
      +======================================================================+
      |  Standard ERC20 metadata and balances                               |
      +======================================================================+*/

    /// @notice Token name - makes it VERY clear this is a joke
    string public constant name = "Wrapped Wrapped WWXRP (PARODY)";

    /// @notice Token symbol
    string public constant symbol = "WWXRP";

    /// @notice Decimals (matching wXRP standard)
    uint8 public constant decimals = 18;

    /// @notice Total circulating supply of WWXRP
    uint256 public totalSupply;

    /// @notice Balance mapping: user => WWXRP balance
    mapping(address => uint256) public balanceOf;

    /// @notice Allowance mapping: owner => spender => amount
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

    /// @notice Addresses authorized to mint WWXRP (game/coin contracts).
    /// @dev Compile-time constants, cannot be changed post-deploy.
    address internal constant MINTER_GAME = ContractAddresses.GAME;
    address internal constant MINTER_COIN = ContractAddresses.COIN;

    /*+======================================================================+
      |                         wXRP RESERVES                                |
      +======================================================================+
      |  Tracks the actual wXRP backing held by this contract               |
      +======================================================================+*/

    /// @notice Actual wXRP reserves held by this contract
    /// @dev This may be LESS than totalSupply (undercollateralized joke token!)
    ///      Or MORE than totalSupply if generous souls donate
    uint256 public wXRPReserves;

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

    /// @notice Transfer amount tokens from caller to recipient
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return True on success
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer amount tokens from sender to recipient using allowance
    /// @param from The source address
    /// @param to The destination address
    /// @param amount The amount to transfer
    /// @return True on success
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

    /// @dev Internal transfer helper
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    /// @dev Internal mint helper
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal burn helper
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
      |  Core functionality for exchanging between wXRP and WWXRP           |
      +======================================================================+*/

    /// @notice Wrap wXRP into WWXRP at 1:1 ratio
    /// @dev Transfers wXRP from caller, mints WWXRP to caller
    ///      Increases the backing ratio (good for everyone!)
    /// @param amount Amount of wXRP to wrap (18 decimals)
    function wrap(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // Transfer wXRP from user to this contract
        if (!wXRP.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        // Increase reserves and mint WWXRP 1:1
        wXRPReserves += amount;
        _mint(msg.sender, amount);

        emit Wrapped(msg.sender, amount);
    }

    /// @notice Unwrap WWXRP back to wXRP at 1:1 ratio (if reserves allow!)
    /// @dev Burns WWXRP from caller, transfers wXRP to caller
    ///      REVERTS if insufficient wXRP reserves - first come, first served!
    /// @param amount Amount of WWXRP to unwrap (18 decimals)
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
    ///      Or for game contracts to add prize pool reserves
    /// @param amount Amount of wXRP to donate (18 decimals)
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
      |                       LOOTBOX MINT FUNCTION                          |
      +======================================================================+
      |  Allows authorized minter to create unbacked WWXRP for prizes       |
      +======================================================================+*/

    /// @notice Mint WWXRP to a recipient (lootbox/loss payouts).
    /// @dev ONLY callable by authorized minters (game/coin contracts).
    ///      WARNING: This mints WITHOUT backing, making the token more unbacked!
    ///      That's the whole joke - enjoy your "Wrapped Wrapped WWXRP"!
    /// @param to Recipient of the minted WWXRP
    /// @param amount Amount to mint (18 decimals)
    function mintPrize(address to, uint256 amount) external {
        if (msg.sender != MINTER_GAME && msg.sender != MINTER_COIN) {
            revert OnlyMinter();
        }
        if (amount == 0) revert ZeroAmount();

        // Mint without backing - increases the backing deficit (perfect!)
        _mint(to, amount);

        emit Transfer(address(0), to, amount);
    }
}
