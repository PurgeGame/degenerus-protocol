
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Purged is ERC20, Ownable
{
    constructor() ERC20("Purged Coin", "PURGED") {}

    address[10] PurgeGameContract;
    uint256 public bank = 400000000;
    
    modifier onlyPurgeGameContract() 
    {
        bool isAuthorized = false;
        for (uint8 i = 0; i < 10; i++) 
        {
            if (PurgeGameContract[i] == msg.sender) 
            {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Only Purge Game contract can call this function");
        _;
    }
    function setPurgeGameAddress(address _purgeGameContract, uint8 season) external onlyOwner
    {
       PurgeGameContract[season] = _purgeGameContract;
    }

    function mintFromPurge(address yourAddress, uint256 _amount) external onlyPurgeGameContract
    {
        _mint(yourAddress, _amount);
    }

    function burnToMint(address yourAddress, uint256 _amount) external onlyPurgeGameContract
    {
        _burn(yourAddress,_amount);
    }

    function airdrop(address[] calldata to, uint256[] calldata _amount) external onlyOwner 
    {
        require (to.length == _amount.length);
        for (uint16 c = 0; c < to.length;c++)
        {
            uint256 amount = _amount[c] * 1000;
            require(amount <= bank);
            bank -= amount;
            _mint(to[c], amount);
        }
    }

    // Removed _beforeTokenTransfer function override as it is not needed
    // Override the decimals function to set the number of decimals
    function decimals() public view virtual override returns (uint8) {
        return 3;
    }
}
