// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";

interface IStakedDegenerusStonk {
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
    function balanceOf(address account) external view returns (uint256);
    function wrapperTransferTo(address to, uint256 amount) external;
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Game interface for VRF liveness check (unwrap guard) and game-over check (burn guard).
interface IDegenerusGame {
    function lastVrfProcessed() external view returns (uint48);
    function gameOver() external view returns (bool);
}

/**
 * @title DegenerusStonk (DGNRS)
 * @notice Transferable ERC20 — the liquid face of the DGNRS token
 * @dev Holders burn DGNRS to claim proportional ETH + stETH + BURNIE backing.
 *      Creator can unwrap DGNRS back to soulbound sDGNRS for specific recipients.
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
    /// @notice Emitted when creator unwraps DGNRS back to soulbound sDGNRS
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
    //                          CONSTANTS
    // =====================================================================

    IStakedDegenerusStonk private constant stonk = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
    IERC20Minimal private constant burnie = IERC20Minimal(ContractAddresses.COIN);
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    constructor() {
        uint256 deposited = stonk.balanceOf(address(this));
        if (deposited == 0) revert Insufficient();
        totalSupply = deposited;
        balanceOf[ContractAddresses.CREATOR] = deposited;
        emit Transfer(address(0), ContractAddresses.CREATOR, deposited);
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
    /// @custom:reverts Insufficient if from balance < amount
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (amount > allowed) revert Insufficient();
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
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
    //                          UNWRAP (Creator Only)
    // =====================================================================

    /// @notice Burn DGNRS and send the underlying sDGNRS to a recipient as soulbound.
    /// @dev Blocked during VRF stall (>5h) to prevent creator vote-stacking via DGNRS→sDGNRS conversion.
    function unwrapTo(address recipient, uint256 amount) external {
        if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();
        if (recipient == address(0)) revert ZeroAddress();
        // Block unwrap during VRF stall (prevents creator vote-stacking)
        if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 5 hours)
            revert Unauthorized();
        _burn(msg.sender, amount);
        stonk.wrapperTransferTo(recipient, amount);
        emit UnwrapTo(recipient, amount);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn DGNRS to claim proportional ETH + stETH + BURNIE from sDGNRS backing
    /// @dev ETH sent last (checks-effects-interactions). Only available post-gameOver;
    ///      during active game, players must use burnWrapped() via sDGNRS gambling path.
    /// @custom:reverts GameNotOver If called during active game (Seam-1 fix).
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        _burn(msg.sender, amount);
        if (!IDegenerusGame(ContractAddresses.GAME).gameOver()) revert GameNotOver();

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
