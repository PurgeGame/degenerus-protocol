// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721PURGE.sol";
import "./Ownable.sol";

/// @custom:security-contact purgegamenft@gmail.com
interface PurgedCoinInterface 
{
    function mintFromPurge(address yourAddress, uint256 _amount) external;
    function burnToMint(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract PurgeGameBetaTest is ERC721, Ownable
{
    
    bool private paidJackpot;
    bool public coinMintStatus;
    bool public publicSaleStatus;
    bool public whitelistSaleStatus;
    bool public REVEAL;
    bool public gameOver;
    bool private purging;
    

    uint16 private offset;
    uint16 private bombNumber = 64501;
    uint16 public MAPtokens;
    uint16 public totalMinted;
    
    uint24 public index;
    uint24 private nuke;

    uint32 public revealTime;
    uint32 public gameEndTime;

    address private purgedCoinContract = 0x3b7e01469d545B187ef526f04A506B7D6F001a74;
    
    uint16[256] public traitRemaining;

    mapping(uint16 => uint24) tokenTraits;
    mapping(uint8 => uint24[]) traitPurgeAddress;
    mapping(uint24 => address) indexAddress;
    mapping(address => uint24) addressIndex;
    mapping(string => uint24) referralCode;
    mapping(uint24 => uint256) public claimableEth;
    mapping(uint24 => uint256) public claimablePurged;


    string public baseTokenURI = "ipfs://QmdxAQbPoqom3EuNoBZGSonjvv5afWDyo8YFaNoscNLcTV/";
    uint256 public cost = .0001 ether; 
    uint256 public PrizePool = 0 ether;

    constructor() ERC721("Purge Game Beta Test", "PURGEGAMEBETA") {}
    

// Links user addresses to a uint24 to save gas when recording game data and will be referenced in future seasons.
    function initAddress(address sender) public
    {
        require(gameOver == 0);
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
        require(bytes(_referralCode).length <= 40, "Too long");
        require(referralCode[_referralCode] == 0, "Referral code is taken");
        noContract();
        initAddress(msg.sender);
        referralCode[_referralCode] = addressIndex[msg.sender];
    }

    function returnReferralCodeOwner(string calldata _referralCode) external view returns(uint24)
    {
        return(referralCode[_referralCode]);
    }

// Mint function.
    function mint(uint16 _number, string calldata referrer) external payable 
     {
        RequireCorrectFunds(_number);
        if (whitelistSaleStatus == true && publicSaleStatus == false) require (addressIndex[msg.sender] <= 3000 && addressIndex[msg.sender] > 0, "You are not whitelisted");
        else require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 29421, "Max tokens reached");
        RequireHundredMax(_number);
        noContract();
        _mintToken(_number);
        if (referralCode[referrer] != 0) payReferrer(_number, referrer);
        addToPrizePool(_number);
    }

// Mint with $PURGED.
    function coinMint(uint16 _number) external
    {
        require(coinMintStatus == true, "Coin mints not currently available");
        require(totalMinted + _number < 29421, "Max tokens reached");
        RequireHundredMax(_number);
        noContract();
        RequireCoinFunds(_number);
        if (claimablePurged[addressIndex[msg.sender]] > _number * cost * 1000)
        {
             claimablePurged[addressIndex[msg.sender]] -= _number * cost * 1000;
        }
        else
        {
            PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 1000 - claimablePurged[addressIndex[msg.sender]]);
            claimablePurged[addressIndex[msg.sender]] = 0;
        }
        _mintToken(_number);
        addToPrizePool(_number);
    }
    
    function _mintToken(uint16 _number) private
    {
        uint16 tokenId = totalMinted;
        for (uint16 i = 0; i < _number; i++) 
        {
            tokenId++;
            _mint(msg.sender, tokenId);
            setTraits(tokenId);
            emit TokenMinted(tokenId, tokenTraits[tokenId], msg.sender);
        }
        _balances[msg.sender] += _number;
        totalMinted += _number;
    }

// Creates a payout ticket for a token without actally minting that token to save gas.
    function mintAndPurge(uint16 _number, string calldata referrer) external payable 
    {
        RequireCorrectFunds(_number);
        codeMintAndPurge(_number);
        if (referralCode[referrer] != 0) payReferrer(_number, referrer);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _number * cost * 100);
    }

    function coinMintAndPurge(uint16 _number) external 
    {
        RequireCoinFunds(_number);
        if (claimablePurged[addressIndex[msg.sender]] > _number * cost * 900)
        {
             claimablePurged[addressIndex[msg.sender]] -= _number * cost * 900;
        }
        else
        {
            PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 900 - claimablePurged[addressIndex[msg.sender]]);
            claimablePurged[addressIndex[msg.sender]] = 0;
        }
        codeMintAndPurge(_number);
    }

    function codeMintAndPurge(uint16 _number) private
    {
        require (whitelistSaleStatus == true || publicSaleStatus == true || coinMintStatus == true, 'Mint inactive');
        RequireHundredMax(_number);
        noContract();
        require(MAPtokens + _number < 34421, "34420 max Mint and Purges");
        initAddress(msg.sender);
        uint16 mapTokenNumber = 30001 + MAPtokens;
        for(uint16 i= 0; i < _number; i++)
        {
            uint24 traits = setTraits(mapTokenNumber + i); 
            purgeWrite(traits,addressIndex[msg.sender]);
            emit MintAndPurge(mapTokenNumber + i, traits, msg.sender);
        }
        addToPrizePool(_number);
        MAPtokens += _number;   
    }

// Generates token traits and adds the trait info to storage if minting an actual token.
    function setTraits(uint16 _tokenId) private returns(uint24)
    {
        if (_tokenId < 29500)
        {
            tokenTraits[_tokenId] = rarity(_tokenId);
            for(uint8 c = 0; c < 4; c++)
            {
                traitRemaining[uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c << 6))] +=1;
            }
            return(0); 
        }
        return rarity(_tokenId);
    }

    function rarity(uint16 _tokenId) private view returns(uint24)
    {
        uint64 randomHash = uint64(uint(keccak256(abi.encodePacked(_tokenId,block.number))));
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
        noContract();
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        initAddress(msg.sender);
        uint16 _tokenId;
        purging = true;
        for(uint16 i = 0; i < _tokenIds.length; i++) 
        {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            require(_tokenId <= 64500, "You cannot purge bombs");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(tokenTraits[_tokenId], addressIndex[msg.sender]);
            purgeTraits(_tokenId);     
        }      
        purging = false;  
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost * 100);
        if (gameOver == true) gameEndTime = uint32(block.timestamp);
    }

// Records the purger's ID for each trait purged. This record will be used to deliver payouts when the game is over.
    function purgeWrite(uint24 traits, uint24 sender) private
    {
        for(uint8 c = 0; c < 4; c++)
        {
            traitPurgeAddress[uint8(traits >> (c * 6) & 0x3f) + (c << 6)].push(sender);
        }
    }

// Records the removal of a token's traits from the game.
    function purgeTraits(uint16 _tokenId) private
    {
        for(uint8 c = 0; c < 4; c++)
        {
            removeTraitRemaining(uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c << 6)));
        }
    }

// Records the removal of a trait and checks to see if this transaction exterminates that trait. 
// If so, this ends the game and pays out the winnings to everyone who has purged a token with that trait.
    function removeTraitRemaining(uint8 trait) private 
    {
        traitRemaining[trait] -=1;
        if (traitRemaining[trait] == 0)
        {   
            if (nuke != 9999999) require(false,"cannot nuke the last token of a trait");
            if (gameOver == false)
            {
                gameOver = true;
                payout(trait);  
                
            }
        }
    }

// Pays the exterminator 10% of the prize pool minus the MAP Jackpot.
// Then pays each player who purged a token with the winning trait an equal amount for each token purged.
    function payout(uint8 trait) private
    {
        uint16 totalPurges = uint16(traitPurgeAddress[trait].length - 1);
        if (totalPurges == 0) totalPurges = 1;
        uint256 paidMAPJackpot = MAPtokens * cost / 20;
        uint256 grandPrize = (PrizePool - paidMAPJackpot) / 10;
        uint256 normalPayout = (PrizePool - grandPrize) / totalPurges;
        claimableEth[addressIndex[msg.sender]] += grandPrize;
        for (uint16 i = 0; i < totalPurges; i++)
        { 
            claimableEth[traitPurgeAddress[trait][i]] += normalPayout;
        } 
    }

/*     function claimEth() public
    {
        require(claimableEth[addressIndex[msg.sender]] > 0);
        uint256 winnings = claimableEth[addressIndex[msg.sender]];
        claimableEth[addressIndex[msg.sender]] = 0;
        PrizePool -= winnings;
        payable(msg.sender).transfer(winnings);
    }

    function claimPurged() public
    {
        require(claimablePurged[addressIndex[msg.sender]] > 0);
        uint256 bonus = claimablePurged[addressIndex[msg.sender]];
        claimablePurged[addressIndex[msg.sender]] = 0;
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, bonus);
    } */

    function claim() external
    {
        require(claimableEth[addressIndex[msg.sender]] > 0 || claimablePurged[addressIndex[msg.sender]] > 0, "Nothing to claim");
        if(claimableEth[addressIndex[msg.sender]] > 0)
        {
            uint256 winnings = claimableEth[addressIndex[msg.sender]];
            claimableEth[addressIndex[msg.sender]] = 0;
            PrizePool -= winnings;
            payable(msg.sender).transfer(winnings);
        }
        if(claimablePurged[addressIndex[msg.sender]] > 0)
        {
            uint256 bonus = claimablePurged[addressIndex[msg.sender]];
            claimablePurged[addressIndex[msg.sender]] = 0;
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, bonus);
        }
    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyOwner
    {
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        require(whitelistSaleStatus == false);
        require(coinMintStatus == false);
        paidJackpot = true;
        claimableEth[getRandomPurge()] += (MAPtokens * cost / 20); 
    }

// Picks a random address from all addresses which have purged, weighted by number of purges.
    function getRandomPurge() private view returns(uint24)
    {
        uint24 random = uint24(uint(keccak256(abi.encodePacked(PrizePool,block.timestamp >> 5))));
        uint16 randomHashTwo = uint16(random >> 8);
        randomHashTwo = randomHashTwo % uint16(traitPurgeAddress[uint8(random)].length);
        return(traitPurgeAddress[uint8(random)][randomHashTwo]);
    }

// Airdrops a bomb token to a random address which has purged a token at some point
    function bombAirdrop() external onlyOwner
    {
        require(REVEAL);
        require(gameOver == false);
        /*  THIS WILL BE IN THE REAL CONTRACT
        if (bombNumber == 64501) {require(block.timestamp > revealTime + 1209600);}
        else {require(block.timestamp > revealTime + 86400);}
        */
        address recipient = indexAddress[getRandomPurge()];
        _mint(recipient,bombNumber);
        _balances[recipient] += 1;
        bombNumber +=1;
        revealTime = uint32(block.timestamp);
    }

// Using the bomb allows the holder to purge any one remaining token
// Prizes for the purge go to the owner of the bombed token
    function nukeToken(uint16 bombTokenId, uint16 targetTokenId) external
    {
        require(bombTokenId > 64500, 'that is not a bomb');
        require(targetTokenId < 64500,'cannot bomb bombs');
        require(ownerOf(bombTokenId) == msg.sender, 'you do not own that bomb');
        purging = true;
        _burn(bombTokenId);
        initAddress(ownerOf(targetTokenId));
        nuke = addressIndex[ownerOf(targetTokenId)];
        _burn(targetTokenId);
        purging = false;
        emit TokenBombed(targetTokenId);
        targetTokenId = realTraitsFromTokenId(targetTokenId);
        purgeWrite(tokenTraits[targetTokenId], nuke);
        purgeTraits(targetTokenId);
        nuke = 9999999;
    }

// Requirements for different mint types

    function RequireHundredMax(uint16 _number) pure private
    {
        require(_number <= 400, "Maximum of 400 mints allowed per tx");
        require(_number > 0);
    }
    
    function onlyBeforeReveal() view private
    {
        require(REVEAL == false);
    }

    function noContract() view private
    {
        require(tx.origin == msg.sender, 'no hax plz');
    }

    function RequireCorrectFunds(uint16 _number) view private
    {
        require(msg.value == _number * cost, "Incorrect funds supplied");
    }

    function RequireCoinFunds(uint16 _number) view private
    {
        if (claimablePurged[addressIndex[msg.sender]] < _number)
        {
            require (PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) + claimablePurged[indexAddress[msg.sender]] >= _number * cost * 1000, "Not enough $PURGED");
        }
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
        claimablePurged[referralCode[referrer]] += _number * cost * 50;
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
            if (_tokenId < 30001)
            {
                if (_tokenId + offset <= totalMinted) return(_tokenId + offset);
                else return(_tokenId + offset - totalMinted);
            }
        }
        return(_tokenId);
    }

    event TokenBombed(uint16 tokenId);
    event MintAndPurge(uint16 tokenId, uint24 tokenTraits, address from);
    event TokenMinted(uint16 tokenId, uint24 tokenTraits, address from);
    event Referred(string referralCode, address referrer, uint16 number, address from);

// Owner game-running functions.
    function setCost(uint _newCost) external onlyOwner 
    {
        onlyBeforeReveal();
        cost = _newCost;
    }

    function setCoinMintStatus(bool _status) external onlyOwner
    {
        onlyBeforeReveal();
        coinMintStatus = _status;
    }

    function setPublicSaleStatus(bool _status) external onlyOwner 
    {
        onlyBeforeReveal();
        publicSaleStatus = _status;
    }

    function setWhitelistSaleStatus(bool _status) external onlyOwner
    {
        onlyBeforeReveal();
        whitelistSaleStatus = _status;
    }

    function reveal(bool _REVEAL, string calldata updatedURI) external onlyOwner 
    {
        onlyBeforeReveal();
        require(paidJackpot == true);
        require(offset != 0);
        require(address(this).balance >= PrizePool);
        require(publicSaleStatus == false);
        require(whitelistSaleStatus == false);
        require(coinMintStatus == false);
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

    //totalSupply includes purged tokens before reveal.  

     function totalSupply() external view returns(uint256)
    {
        if(REVEAL == false) return(totalMinted + MAPtokens);
        return totalMinted;
    }


    receive () external payable  { }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
            return string(abi.encodePacked(baseTokenURI, uint2str(tokenId)));
    }


    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721)
    {
        if (to == address(0)) require(purging == true, 'Use purge function');
        if (gameOver == true) require(block.timestamp > gameEndTime + 86400, 'Transfers disabled for 24h after game over');
        super._beforeTokenTransfer(from, to, tokenId);
    }

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