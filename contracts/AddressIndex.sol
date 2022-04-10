// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

contract AddressIndex
{
    uint16 index;
    mapping(uint24 => address) indexAddress;
    mapping(address => uint24) addressIndex;

    // Links user addresses to a uint24 to save gas when recording game data and will be referenced in future seasons.
    function initAddress(address sender) public
    {
        if (addressIndex[sender] == 0)
        {
            index +=1;
            addressIndex[sender] = index;
            indexAddress[index] = sender;
        }
    }

    function returnAddressIndex(address _address) external view returns(uint24)
    {
        return(addressIndex[_address]);
    }

    function returnIndexAddress(uint24 _index) external view returns(address)
    {
        return(indexAddress[_index]);
    }
}