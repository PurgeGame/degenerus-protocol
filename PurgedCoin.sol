
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Purged is ERC20, ERC20Burnable, Ownable
{
    constructor() ERC20("Purged Coin", "PURGED") {}

    address[2] PurgeGameContract;
    
    modifier onlyPurgeGameContract()
    {
        require(PurgeGameContract[0] == msg.sender || PurgeGameContract[1] == msg.sender, "Only Purge Game contract can call this function");
         _;
    }

    function setPurgeGameAddress(uint8 season, address _purgeGameContract) public onlyOwner
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

    function airdrop(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

}

