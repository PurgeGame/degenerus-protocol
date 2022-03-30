// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//import "hardhat/console.sol";

/// @custom:security-contact purgegamenft@gmail.com
interface PurgedCoinInterface 
{
    function mintFromPurge(address yourAddress, uint256 _amount) external;
    function burnToMint(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract PurgeGameAlphaTest is ERC721, Ownable
{
    
    bool paidJackpot;
    bool public coinMintStatus;
    bool public publicSaleStatus;
    bool public REVEAL;
    bool public gameOver;

    uint16 offset;
    uint16 bombNumber = 65001;
    uint24 nuke = 999999;
    uint16 index;
    uint16 MAPtokens;
    uint16 public totalMinted;
    
    uint32 revealTime;

    address private purgedCoinContract = 0xfBFD4411914A2c6caBEd2Ba18A7DBe8DD9A26496;
    
    uint16[256] public traitRemaining;

    mapping(uint16 => uint24) tokenTraits;
    mapping(uint8 => uint24[]) traitPurgeAddress;
    mapping(uint24 => address) indexAddress;
    mapping(address => uint24) addressIndex;
    mapping(string => uint24) public referralCode;


    string public baseTokenURI = "https://ipfs.io/ipfs/QmbHSRcYNUC6xvAE9qjjxpSnZiebC6sidhKvGBhxM2A6Lt/";
    uint256 public cost = .0001 ether; 
    uint256 public PrizePool = 0 ether;

    constructor() ERC721("Purge Game Alpha Test #2", "PURGEGAMEa2") {}
    

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
    
// Allows users to create a referral code string that will pay them $PURGED when their referrals mint tokens.
    function createReferralCode(string calldata _referralCode) external 
    {
        require(bytes(_referralCode).length != 0, "Input your desired code");
        require(referralCode[_referralCode] == 0, "Referral code is taken");
        initAddress(msg.sender);
        referralCode[_referralCode] = addressIndex[msg.sender];
    }

    function returnReferralCode(string calldata _referralCode) external view returns(uint24)
    {
        return(referralCode[_referralCode]);
    }

// Mint function.
    function mint(uint16 _number, string calldata referrer) external payable 
     {
        RequireCorrectFunds(_number);
        RequireSale(_number);
        RequireHundredMax(_number);
        _mintToken(_number);
        if (referralCode[referrer] != 0 && indexAddress[referralCode[referrer]] != msg.sender) {payReferrer(_number, referrer);}
        addToPrizePool(_number);
    }

// Mint with $PURGED.
    function coinMint(uint16 _number) external
    {
        require(coinMintStatus == true, "Coin mints not yet available");
        //RequireSale(_number);
        require(REVEAL == false);
        RequireHundredMax(_number);
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 1000);
        _mintToken(_number);
        addToPrizePool(_number);
    }
    
    function _mintToken(uint16 _number) private
    {
        for (uint16 i = 1; i <= _number; i++) 
        {
            uint16 tokenId = uint16(_currentIndex + i);
            setTraits(tokenId);
            emit TokenMinted(tokenId, tokenTraits[tokenId], msg.sender);
        }
        _safeMint(msg.sender,_number);
    }

// Creates a payout ticket for a token without actally minting that token to save gas.
    function mintAndPurge(uint16 _number, string calldata referrer) external payable 
    {
        RequireCorrectFunds(_number);
        codeMintAndPurge(_number);
        if (referralCode[referrer] != 0 && indexAddress[referralCode[referrer]] != msg.sender) {payReferrer(_number, referrer);}
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _number * cost * 100);
    }

    function coinMintAndPurge(uint16 _number) external 
    {
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 900);
        codeMintAndPurge(_number);
    }

    function codeMintAndPurge(uint16 _number) private
    {
        RequireSale(_number);
        require(MAPtokens + _number < 24421, "24420 max Mint and Purges");
        initAddress(msg.sender);
        addToPrizePool(_number);
        uint16 mapTokenNumber = 40001;
        mapTokenNumber += MAPtokens;
        for(uint16 i= 0; i < _number; i++)
        {
            setTraits(mapTokenNumber); 
            purgeWrite(mapTokenNumber, addressIndex[msg.sender]);
            emit MintAndPurge(mapTokenNumber, tokenTraits[mapTokenNumber], msg.sender);
            mapTokenNumber++;
        }
        MAPtokens += _number;   
    }

// Generates token traits and adds the trait info to storage if minting an actual token.
    function setTraits(uint16 _tokenId) private
    {
        tokenTraits[_tokenId] = rarity(_tokenId);
        if (_tokenId < 39500)
        {
            for(uint8 c = 0; c < 4; c++)
            {
                traitRemaining[uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c * 64))] +=1;
            }   
        }
    }

    function rarity(uint16 _tokenId) private view returns(uint24)
    {
        uint64 randomHash = uint64(uint(keccak256(abi.encodePacked(_tokenId,PrizePool))));
        uint24 result = getTrait(uint16(randomHash));
        result += getTrait(uint16(randomHash >> 11)) << 6;
        result += getTrait(uint16(randomHash >> 22)) << 12;
        result += getTrait(uint16(randomHash >> 33)) << 18;
        return result;
    }

    function getTrait(uint16 _input) private pure returns(uint24) 
    {
        _input = _input & 0x7ff;
        if(_input < 840) return _input / 35;
        if(_input < 1352) return 24 + (_input - 840) / 32;
        if(_input < 1832) return 40 + (_input - 1352) / 30;
        return 56 + (_input - 1832) / 27;
    } 

// Burns tokens and creates payout tickets for each trait purged, then prints $PURGED.
    function purge(uint16[] calldata _tokenIds) external  
    {
        
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        initAddress(msg.sender);
        uint16 _tokenId;
        for(uint16 i = 0; i < _tokenIds.length; i++) 
        {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            require(_tokenId <= totalMinted, "You cannot purge bombs");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(_tokenId, addressIndex[msg.sender]);
            purgeTraits(_tokenId);     
        }        
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost * 100);
    }

// Records the purger's ID for each trait purged. This record will be used to deliver payouts when the game is over.
    function purgeWrite(uint16 _tokenId, uint24 sender) private
    {
        for(uint8 c = 0; c < 4; c++)
        {
            traitPurgeAddress[uint8(tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c * 64)].push(sender);
        }
    }

// Records the removal of a token's traits from the game.
    function purgeTraits(uint16 _tokenId) private
    {
        for(uint8 c = 0; c < 4; c++)
        {
            removeTraitRemaining(uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c * 64)));
        }
    }

// Records the removal of a trait and checks to see if this transaction exterminates that trait. 
// If so, this ends the game and pays out the winnings to everyone who has purged a token with that trait.
    function removeTraitRemaining(uint8 trait) private 
    {
        traitRemaining[trait] -=1;
        
        if (traitRemaining[trait] == 0)
        {
            if (gameOver == false)
            {
                gameOver = true;
                if (nuke != 999999) {payout(trait,indexAddress[nuke]);}
                else {payout(trait, msg.sender);}   
                
            }
        }

    }

// Pays the exterminator 10% of the prize pool minus the MAP Jackpot.
// Then pays each player who purged a token with the winning trait an equal amount for each token purged.
    function payout(uint8 trait, address winner) private
    {
        require(PrizePool > 0);
        uint16 totalPurges = uint16(traitPurgeAddress[trait].length - 1);
        uint256 paidMAPJackpot = MAPtokens * cost / 20;

        payable(winner).transfer((PrizePool - paidMAPJackpot) / 10);

        uint256 normalPayout = (PrizePool - ((PrizePool - paidMAPJackpot) / 10)) / totalPurges;
        
         for (uint16 i = 0; i < totalPurges; i++)
         { 
             payable(indexAddress[traitPurgeAddress[trait][i]]).transfer(normalPayout);
         }
         PrizePool = 0;
    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyOwner
    {
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        address payable winnerAddress = payable(indexAddress[getRandomPurge()]);
        PrizePool -= MAPtokens * cost / 20;
        paidJackpot = true;
        winnerAddress.transfer(MAPtokens * cost / 20); 
    }

// Picks a random address from all addresses which have purged, weighted by number of purges.
    function getRandomPurge() private view returns(uint24)
    {
        uint24 random = uint24(uint(keccak256(abi.encodePacked(PrizePool,totalSupply()))));
        uint16 randomHashTwo = uint16(random >> 8);
        randomHashTwo = randomHashTwo % uint16(traitPurgeAddress[uint8(random)].length);
        return(traitPurgeAddress[uint8(random)][randomHashTwo]);
    }

// Airdrops a bomb token to a random address which has purged a token at some point
    function bombAirdrop() external onlyOwner
    {
        /*
        if (bombNumber == 50001) {require(block.timestamp > revealTime + 1209600);}
        else {require(block.timestamp > revealTime + 86400);}
        */
        _safeMint(indexAddress[getRandomPurge()],1);
        bombNumber +=1;
        revealTime = uint32(block.timestamp);
    }

// Using the bomb allows the holder to purge any one remaining token
// Prizes for the purge go to the owner of the bombed token
    function nukeToken(uint16 bombTokenId, uint16 targetTokenId) external
    {
        
        require(bombTokenId > totalMinted);
        require(targetTokenId <= totalMinted);
        require(ownerOf(bombTokenId) == msg.sender);
        _burn(bombTokenId);
        initAddress(ownerOf(targetTokenId));
        nuke = addressIndex[ownerOf(targetTokenId)];
        _burn(targetTokenId);
        targetTokenId = realTraitsFromTokenId(targetTokenId);
        purgeWrite(targetTokenId, nuke);
        purgeTraits(targetTokenId);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[nuke], cost * 100);
        nuke = 999999;
    }

// Requirements for different mint types
    function RequireSale(uint16 _number) view private
    {
        require(publicSaleStatus == true, "Not yet");
        require(REVEAL == false);
        require(_number > 0, "You are trying to mint 0");
    }

    function RequireHundredMax(uint16 _number) view private
    {
        require(_number <= 500, "Maximum of 500 mints allowed per transaction");
        require(_currentIndex + _number < 39421, "Max 39420 tokens");
    }

    function RequireCorrectFunds(uint16 _number) view private
    {
        require(msg.value == _number * cost, "Incorrect funds supplied");
    }

    function RequireCoinFunds(uint16 _number) view private
    {
        require (PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= _number * cost * 1000, "Not enough $PURGED");
    }

// Minting adds half of the mint cost to the prize pool.
// This ether is locked into the contract and can only be released by winning the game.
    function addToPrizePool(uint16 _number) private
    {
        PrizePool += cost * _number / 2;
    }

// Pays $PURGED to referrers when their referrals mint tokens.
    function payReferrer(uint16 _number, string calldata referrer) private
    {
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[referralCode[referrer]], _number * cost * 50);
        emit Referred(referrer, indexAddress[referralCode[referrer]], _number, msg.sender);
    }

// Anti-hack funtion. The traits generated by minting will not correspond to the token minted.
    function setOffset(uint16 _offset) external onlyOwner
    {
        require(offset == 0);
        offset = _offset;
    }
    
    function realTraitsFromTokenId(uint16 _tokenId) private view returns(uint16)
    {
        if (offset != 0)
        {
            if (_tokenId < 40001)
            {
                if (_tokenId + offset < totalMinted) return(_tokenId + offset);
                else return(_tokenId + offset - totalMinted);
            }
        }
        return(_tokenId);
    }

    event MintAndPurge(uint16 tokenId, uint24 tokenTraits, address from);
    event TokenMinted(uint16 tokenId, uint24 tokenTraits, address from);
    event Referred(string referralCode, address referrer, uint16 number, address from);

// Owner game-running functions.
    function setCost(uint _newCost) external onlyOwner 
    {
        cost = _newCost;
    }

    function setCoinMintStatus(bool _status) external onlyOwner
    {
        coinMintStatus = _status;
        if (_status == false) totalMinted = uint16(_currentIndex-1);
    }

    function setPublicSaleStatus(bool _status) external onlyOwner 
    {
        publicSaleStatus = _status;
        if (_status == false ) totalMinted = uint16(_currentIndex-1);
    }

    function reveal(bool _REVEAL, string calldata updatedURI) external onlyOwner 
    {
        require(REVEAL == false);
        require (paidJackpot == true);
        require(address(this).balance >= PrizePool);
        REVEAL = _REVEAL;
        baseTokenURI = updatedURI;
        revealTime = uint32(block.timestamp);
    }

    function setTokenUri(string calldata updatedURI) external onlyOwner
    {
       baseTokenURI = updatedURI; 
    }

    function setPurgedCoinAddress(address _purgedCoinContract) external onlyOwner
    {
        purgedCoinContract = _purgedCoinContract;
    }

// The only way for funds to leave the contract other than payout and payMapJackpot. 
// This is only able to withdraw funds in excess of the prizepool.
    function withdrawMyFunds(address payable _to) external onlyOwner 
    {
        require(address(this).balance > PrizePool, "No funds to withdraw");
        _to.transfer(address(this).balance - PrizePool);    
    }

 // totalSupply includes purged tokens before reveal.  

    // function totalSupply() external view returns(uint256)
    // {
    //     if(REVEAL == false)return(_currentIndex-1 + MAPtokens);
    //     return _currentIndex-_burnCounter-1;
    // }


    receive () external payable  { }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
            return string(abi.encodePacked(baseTokenURI, uint2str(tokenId)));
    }

/*
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        //override(ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
*/
    function uint2str(uint _i) private pure returns (string memory _uintAsString) 
    {
        if (_i == 0) 
        {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) 
        {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) 
        {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721) 
    {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}