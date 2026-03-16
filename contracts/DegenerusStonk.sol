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

    error Unauthorized();
    error Insufficient();
    error ZeroAddress();
    error TransferFailed();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event BurnThrough(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);
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

    receive() external payable {}

    // =====================================================================
    //                          ERC20 FUNCTIONS
    // =====================================================================

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // =====================================================================
    //                          UNWRAP (Creator Only)
    // =====================================================================

    /// @notice Burn DGNRS and send the underlying sDGNRS to a recipient as soulbound
    function unwrapTo(address recipient, uint256 amount) external {
        if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();
        if (recipient == address(0)) revert ZeroAddress();
        _burn(msg.sender, amount);
        stonk.wrapperTransferTo(recipient, amount);
        emit UnwrapTo(recipient, amount);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn DGNRS to claim proportional ETH + stETH + BURNIE from sDGNRS backing
    /// @dev ETH sent last (checks-effects-interactions)
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        _burn(msg.sender, amount);

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

    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        return stonk.previewBurn(amount);
    }

    // =====================================================================
    //                          INTERNAL
    // =====================================================================

    function _transfer(address from, address to, uint256 amount) private returns (bool) {
        if (to == address(0)) revert ZeroAddress();
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
}
