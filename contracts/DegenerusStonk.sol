// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";

/// @notice Interface for sDGNRS contract methods used by DGNRS.
interface IStakedDegenerusStonk {
    /// @notice Burn sDGNRS to claim proportional backing assets.
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
    /// @notice Get token balance for an address.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Transfer sDGNRS from wrapper to recipient (wrapper only).
    function wrapperTransferTo(address to, uint256 amount) external;
    /// @notice Preview ETH, stETH, and BURNIE output for a given burn amount.
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}

/// @notice Minimal ERC20 interface for token transfers.
interface IERC20Minimal {
    /// @notice Transfer tokens to a recipient.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Game interface for RNG lock (unwrap guard), game-over check (burn guard), and level (vesting).
interface IDegenerusGame {
    function rngLocked() external view returns (bool);
    function gameOver() external view returns (bool);
    function gameOverTimestamp() external view returns (uint48);
    function level() external view returns (uint24);
}

/// @dev Vault interface for DGVE ownership check (unwrap auth).
interface IDegenerusVault {
    function isVaultOwner(address account) external view returns (bool);
}

/**
 * @title DegenerusStonk (DGNRS)
 * @notice Transferable ERC20 — the liquid face of the DGNRS token
 * @dev Holders burn DGNRS to claim proportional ETH + stETH + BURNIE backing.
 *      DGVE majority holder can unwrap DGNRS back to soulbound sDGNRS for specific recipients.
 */
contract DegenerusStonk {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();
    /// @notice Thrown when balance or allowance is insufficient
    error Insufficient();
    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();
    /// @notice Thrown when an ETH or token transfer fails
    error TransferFailed();
    /// @notice Thrown when burn() is called during active game (use burnWrapped() instead)
    error GameNotOver();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted on every token transfer (including mint and burn)
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when an allowance is set via approve
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    /// @notice Emitted when DGNRS is burned through to sDGNRS for ETH + stETH + BURNIE
    event BurnThrough(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);
    /// @notice Emitted when DGVE majority holder unwraps DGNRS back to soulbound sDGNRS
    event UnwrapTo(address indexed recipient, uint256 amount);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    string public constant name = "Degenerus Stonk";
    string public constant symbol = "DGNRS";
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // =====================================================================
    //                          VESTING STATE
    // =====================================================================

    uint256 private _vestingReleased;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    uint256 private constant CREATOR_INITIAL = 50_000_000_000 * 1e18;   // 50B at deploy
    uint256 private constant VEST_PER_LEVEL  = 5_000_000_000 * 1e18;    // 5B per level
    uint256 private constant CREATOR_TOTAL   = 200_000_000_000 * 1e18;  // 200B total

    IStakedDegenerusStonk private constant stonk = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
    IERC20Minimal private constant burnie = IERC20Minimal(ContractAddresses.COIN);
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    IDegenerusVault private constant vault = IDegenerusVault(ContractAddresses.VAULT);
    IDegenerusGame private constant game = IDegenerusGame(ContractAddresses.GAME);

    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    constructor() {
        uint256 deposited = stonk.balanceOf(address(this));
        if (deposited == 0) revert Insufficient();
        totalSupply = deposited;
        uint256 unvested = deposited - CREATOR_INITIAL;
        balanceOf[ContractAddresses.CREATOR] = CREATOR_INITIAL;
        balanceOf[address(this)] = unvested;
        _vestingReleased = CREATOR_INITIAL;
        emit Transfer(address(0), ContractAddresses.CREATOR, CREATOR_INITIAL);
        emit Transfer(address(0), address(this), unvested);
    }

    /// @notice Accepts ETH from sDGNRS during burn-through
    /// @custom:reverts Unauthorized if sender is not sDGNRS
    receive() external payable {
        if (msg.sender != address(stonk)) revert Unauthorized();
    }

    // =====================================================================
    //                          ERC20 FUNCTIONS
    // =====================================================================

    /// @notice Transfer DGNRS tokens to a recipient
    /// @param to Recipient address
    /// @param amount Amount of DGNRS to transfer (18 decimals)
    /// @return True on success
    /// @custom:reverts ZeroAddress if to is address(0)
    /// @custom:reverts Unauthorized if to is DGNRS contract address
    /// @custom:reverts Insufficient if sender balance < amount
    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Transfer DGNRS tokens from one address to another (requires prior allowance)
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount of DGNRS to transfer (18 decimals)
    /// @return True on success
    /// @custom:reverts Insufficient if amount exceeds allowance (unless max uint256 approval)
    /// @custom:reverts ZeroAddress if to is address(0)
    /// @custom:reverts Unauthorized if to is DGNRS contract address
    /// @custom:reverts Insufficient if from balance < amount
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (amount > allowed) revert Insufficient();
            uint256 newAllowance;
            unchecked {
                newAllowance = allowed - amount;
            }
            allowance[from][msg.sender] = newAllowance;
            emit Approval(from, msg.sender, newAllowance);
        }
        return _transfer(from, to, amount);
    }

    /// @notice Approve a spender to transfer DGNRS tokens on behalf of msg.sender
    /// @param spender Address authorized to spend
    /// @param amount Allowance amount (use type(uint256).max for unlimited)
    /// @return True on success
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // =====================================================================
    //                          UNWRAP (Vault Owner Only)
    // =====================================================================

    /// @notice Burn DGNRS and send the underlying sDGNRS to a recipient as soulbound.
    /// @dev Blocked while RNG is locked to prevent vote-stacking via DGNRS→sDGNRS conversion.
    /// @param recipient Address to receive the soulbound sDGNRS.
    /// @param amount Amount of DGNRS to burn and unwrap (18 decimals).
    function unwrapTo(address recipient, uint256 amount) external {
        if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();
        if (recipient == address(0)) revert ZeroAddress();
        if (game.rngLocked()) revert Unauthorized();
        _burn(msg.sender, amount);
        stonk.wrapperTransferTo(recipient, amount);
        emit UnwrapTo(recipient, amount);
    }

    // =====================================================================
    //                          VESTING (Vault Owner Only)
    // =====================================================================

    /// @notice Claim vested DGNRS based on current game level.
    /// @dev 50B at deploy to CREATOR, then 5B per level to vault owner. Fully vested at level 30.
    function claimVested() external {
        if (!vault.isVaultOwner(msg.sender)) revert Unauthorized();
        uint256 vested = CREATOR_INITIAL + game.level() * VEST_PER_LEVEL;
        if (vested > CREATOR_TOTAL) vested = CREATOR_TOTAL;
        if (vested <= _vestingReleased) revert Insufficient();
        uint256 claimable;
        unchecked { claimable = vested - _vestingReleased; }
        _vestingReleased = vested;
        balanceOf[address(this)] -= claimable;
        balanceOf[msg.sender] += claimable;
        emit Transfer(address(this), msg.sender, claimable);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn DGNRS to claim proportional ETH + stETH + BURNIE from sDGNRS backing
    /// @dev ETH sent last (checks-effects-interactions). Only available post-gameOver;
    ///      during active game, players must use burnWrapped() via sDGNRS gambling path.
    /// @param amount Amount of DGNRS to burn (18 decimals).
    /// @return ethOut ETH received from backing.
    /// @return stethOut stETH received from backing.
    /// @return burnieOut BURNIE received from backing.
    /// @custom:reverts GameNotOver If called during active game (Seam-1 fix).
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        _burn(msg.sender, amount);
        if (!game.gameOver()) revert GameNotOver();

        (ethOut, stethOut, burnieOut) = stonk.burn(amount);

        if (burnieOut != 0) {
            if (!burnie.transfer(msg.sender, burnieOut)) revert TransferFailed();
        }
        if (stethOut != 0) {
            if (!steth.transfer(msg.sender, stethOut)) revert TransferFailed();
        }
        if (ethOut != 0) {
            (bool success, ) = msg.sender.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }

        emit BurnThrough(msg.sender, amount, ethOut, stethOut, burnieOut);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning a given amount of DGNRS
    /// @dev Delegates to sDGNRS.previewBurn; does not modify state
    /// @param amount Amount of DGNRS to simulate burning (18 decimals)
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        return stonk.previewBurn(amount);
    }

    // =====================================================================
    //                          INTERNAL
    // =====================================================================

    function _transfer(address from, address to, uint256 amount) private returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert Unauthorized();
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function _burn(address from, uint256 amount) private {
        uint256 bal = balanceOf[from];
        if (amount == 0 || amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // =====================================================================
    //                    1-YEAR POST-GAMEOVER SWEEP
    // =====================================================================

    /// @notice Thrown when 1-year sweep is called too early or game not over
    error SweepNotReady();

    /// @notice Thrown when no remaining sDGNRS to sweep
    error NothingToSweep();

    /// @notice Emitted when 1-year sweep distributes remaining backing
    event YearSweep(uint256 ethToGnrus, uint256 stethToGnrus, uint256 ethToVault, uint256 stethToVault);

    /// @notice Sweep remaining DGNRS backing 50-50 to GNRUS and VAULT after 1 year post-gameover.
    /// @dev Permissionless. Burns all sDGNRS held by this contract and forwards the
    ///      ETH/stETH output. stETH sent first, then ETH (CEI).
    function yearSweep() external {
        if (!game.gameOver()) revert SweepNotReady();
        uint48 goTime = game.gameOverTimestamp();
        if (goTime == 0 || block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();

        uint256 remaining = stonk.balanceOf(address(this));
        if (remaining == 0) revert NothingToSweep();

        (uint256 ethOut, uint256 stethOut,) = stonk.burn(remaining);

        // 50-50 split
        uint256 stethToGnrus = stethOut / 2;
        uint256 stethToVault = stethOut - stethToGnrus;
        uint256 ethToGnrus = ethOut / 2;
        uint256 ethToVault = ethOut - ethToGnrus;

        // stETH first (lower reentrancy risk)
        if (stethToGnrus != 0) {
            if (!steth.transfer(ContractAddresses.GNRUS, stethToGnrus)) revert TransferFailed();
        }
        if (stethToVault != 0) {
            if (!steth.transfer(ContractAddresses.VAULT, stethToVault)) revert TransferFailed();
        }
        // ETH last
        if (ethToGnrus != 0) {
            (bool ok,) = payable(ContractAddresses.GNRUS).call{value: ethToGnrus}("");
            if (!ok) revert TransferFailed();
        }
        if (ethToVault != 0) {
            (bool ok,) = payable(ContractAddresses.VAULT).call{value: ethToVault}("");
            if (!ok) revert TransferFailed();
        }

        emit YearSweep(ethToGnrus, stethToGnrus, ethToVault, stethToVault);
    }

    // =====================================================================
    //                    sDGNRS BURN SUPPORT
    // =====================================================================

    /// @notice Burn DGNRS from a player on behalf of sDGNRS (for wrapped gambling burns)
    /// @dev Only callable by sDGNRS contract. Burns the wrapper token so sDGNRS can
    ///      burn the backing sDGNRS from this contract's balance.
    /// @param player Address whose DGNRS to burn
    /// @param amount Amount of DGNRS to burn
    function burnForSdgnrs(address player, uint256 amount) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();
        uint256 bal = balanceOf[player];
        if (amount == 0 || amount > bal) revert Insufficient();
        unchecked {
            balanceOf[player] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(player, address(0), amount);
    }
}
