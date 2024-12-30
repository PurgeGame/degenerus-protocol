
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Purged is ERC20, Ownable
{
    constructor() ERC20("Purged Coin", "PURGED") {}

    address[2] PurgeGameContract;
    uint256 public bank = 1000000 ether;
    uint32 starttime = 1648337132;
    
    modifier onlyPurgeGameContract()
    {
        require(PurgeGameContract[0] == msg.sender || PurgeGameContract[1] == msg.sender, "Only Purge Game contract can call this function");
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
            uint256 amount = _amount[c] * 1 ether;
            require(amount <= bank);
            _mint(to[c], amount);
            bank -= amount;
        }

    }

    function addToBank() external onlyOwner
    {
        bank += (block.timestamp - starttime) * 1000 ether / 24192;
        starttime = uint32(block.timestamp);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

}
