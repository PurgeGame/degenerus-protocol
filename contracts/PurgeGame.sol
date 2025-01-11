// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @custom:security-contact purgegamenft@gmail.com
interface PurgedCoinInterface 
{
    function mintFromPurge(address yourAddress, uint256 _amount) external;
    function burnToMint(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

abstract contract PurgeGameBetaTest is ERC721, Ownable 
{
    using Strings for uint256;

    
    bool private paidJackpot;
    bool public publicSaleStatus;
    bool public REVEAL;
    bool public gameOver;
    bool private purging;
    uint8 private dailyJackpotCounter;

    uint16 private offset;
    uint16 public MAPtokens;
    uint16 public totalMinted;
    
    uint24 public index;
    
    uint32 private dailyCoinBurn;
    uint32 public revealTime;
    uint32 public gameEndTime;
    uint32 public dailyJackpotTime;

    address private purgedCoinContract = 0x3b7e01469d545B187ef526f04A506B7D6F001a74;
    address public usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    
    uint16[256] public traitRemaining;
    uint16[80] public dailyPurgeCount;
    uint24[256] public totalCoinBurn;

    mapping(uint16 => uint24) tokenTraits;
    mapping(uint8 => uint24[]) traitPurgeTicket;
    mapping(uint24 => address) indexAddress;
    mapping(address => uint24) addressIndex;
    mapping(string => uint24) referralCode;
    mapping(uint24 => uint32) claimableWinnings;
    mapping(uint24 => uint24) playerLuckbox;

    string public baseTokenURI = "ipfs://QmdxAQbPoqom3EuNoBZGSonjvv5afWDyo8YFaNoscNLcTV/";
   
    uint256 public cost = 100; 
    uint256 public PrizePool = 0;
    uint256 public startingPrizePool = 0;

    constructor() ERC721("Purge Game Beta Test", "PURGEGAMEBETA") {}
    

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
        require(bytes(_referralCode).length <= 40, "Too long");
        require(referralCode[_referralCode] == 0, "Referral code is taken");
        initAddress(msg.sender);
        referralCode[_referralCode] = addressIndex[msg.sender];
    }

    function returnReferralCodeOwner(string calldata _referralCode) external view returns(uint24)
    {
        return(referralCode[_referralCode]);
    }

// Mint function.

        function mint(uint16 _number, string calldata referrer) external 
        {
            require(publicSaleStatus == true, 'Public sale inactive');
            require(totalMinted + _number < 32000, "Max tokens reached");
            RequireHundredMax(_number);
            usdcRecieve(_number);
            _mintToken(_number);
            payReferrer(_number, referrer);
            addToPrizePool(_number);
        }

// Mint with $PURGED.
    function coinMint(uint16 _number) external
    {
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 32000, "Max tokens reached");
        RequireHundredMax(_number);
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost);
        _mintToken(_number);
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
        totalMinted += _number;
    }

// Creates a payout ticket for a token without actally minting that token to save gas.
    function mintAndPurge(uint16 _number, string calldata referrer) external  
    {
        usdcRecieve(_number);
        codeMintAndPurge(_number);
        payReferrer(_number, referrer);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _number * cost);
    }

    function coinMintAndPurge(uint16 _number) external 
    {
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 9 / 10);
        codeMintAndPurge(_number);
    }

    function codeMintAndPurge(uint16 _number) private
    {
        require (publicSaleStatus == true, 'Mint inactive');
        RequireHundredMax(_number);
        require(MAPtokens + _number < 32000, "32000 max Mint and Purges");
        initAddress(msg.sender);
        uint16 mapTokenNumber = 32001 + MAPtokens;
        for(uint16 i= 0; i < _number; i++)
        {
            uint24 traits = setTraits(mapTokenNumber + i); 
            purgeWrite(traits,addressIndex[msg.sender]);
            emit MintAndPurge(mapTokenNumber + i, traits, msg.sender);
        }
        addToPrizePool(_number);
        MAPtokens += _number;   
    }

    function usdcRecieve(uint16 _number) private
    {
        uint256 totalCost = _number * cost * 1000000;
        RequireCorrectFunds(totalCost);
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), totalCost);
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

    function luckyCoinBurn(uint24 amount, uint16 _tokenId) external 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender), "Not enough $PURGED");
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, amount);
        uint24 traits = tokenTraits[_tokenId];
        totalCoinBurn[uint8(traits & 0x3f)] += amount;
        totalCoinBurn[uint8((traits >> 6) & 0x3f)] += amount;
        totalCoinBurn[uint8((traits >> 12) & 0x3f)] += amount;
        totalCoinBurn[uint8((traits >> 18) & 0x3f)] += amount;
        dailyCoinBurn += amount;
        playerLuckbox[addressIndex[msg.sender]] += amount;
        emit CoinBurned(msg.sender, _tokenId, amount);
    }


// Burns tokens and creates payout tickets for each trait purged, then prints $PURGED.
    function purge(uint16[] calldata _tokenIds) external  
    { 
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        initAddress(msg.sender);
        uint16 _tokenId;
        purging = true;
        for(uint16 i = 0; i < _tokenIds.length; i++) 
        {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(tokenTraits[_tokenId], addressIndex[msg.sender]);
            purgeTraits(_tokenId);     
        }      
        purging = false;  

        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost / 10);
    }

    function purgeWrite(uint24 traits, uint24 sender) private {
        uint8[4] memory traitIndices;
        traitIndices[0] = uint8(traits & 0x3f);
        traitIndices[1] = uint8((traits >> 6) & 0x3f);
        traitIndices[2] = uint8((traits >> 12) & 0x3f);
        traitIndices[3] = uint8((traits >> 18) & 0x3f);

        dailyPurgeCount[traitIndices[0] % 8] += 1;
        dailyPurgeCount[traitIndices[1] / 8 + 8] += 1;
        dailyPurgeCount[traitIndices[2] + 16] += 1;

        for (uint8 c = 0; c < 4; c++) {
            traitPurgeTicket[traitIndices[c] + 64 * c].push(sender);
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
            if (gameOver == false)
            {
                gameOver = true;
                gameEndTime = uint32(block.timestamp);
                payout(trait);  
            }
        }
    }

// Pays the exterminator 10% of the prize pool minus the MAP Jackpot.
// Then pays each player who purged a token with the winning trait an equal amount for each token purged.
    function payout(uint8 trait) private
    {
        uint16 totalPurges = uint16(traitPurgeTicket[trait].length - 1);
        if (totalPurges == 0) totalPurges = 1;
        uint32 grandPrize = uint32(PrizePool) / 4;
        uint32 normalPayout = (uint32(PrizePool) - grandPrize) / totalPurges;
        PrizePool = 0;
        claimableWinnings[addressIndex[msg.sender]] += grandPrize;
        for (uint16 i = 0; i < totalPurges; i++)
        { 
            claimableWinnings[traitPurgeTicket[trait][i]] += normalPayout;
        } 

    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyOwner
    {
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(owner(), PrizePool / 4);
        startingPrizePool = PrizePool * 9 / 10;
        PrizePool -= PrizePool / 10;
        paidJackpot = true;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) %256;
        claimableWinnings[randTraitTicket(getWinningTrait(randomNum))] += uint32(startingPrizePool / 9);
    }

    function payDailyJackpot() external onlyOwner {
        require(dailyJackpotTime != 0);
        require(block.timestamp >= dailyJackpotTime + 23 hours);
        require(gameOver == false);
        coinJackpot();
        uint256 jackpot = startingPrizePool / 100;
        PrizePool -= startingPrizePool / 25;
        uint8[3] memory winningTraits = getWinningTraits();
        // Update claimable winnings for each winner
        for (uint8 i = 0; i < 4; i++) {
            claimableWinnings[randTraitTicket(winningTraits[i])] += uint32(jackpot);
        }
        dailyJackpotCounter += 1;
        if (dailyJackpotCounter == 25) {
            gameOver = true;
            gameEndTime = uint32(block.timestamp);
            PrizePool = 0;
        }
        else {dailyJackpotTime = uint32(block.timestamp);}
        for (uint8 i = 0; i < dailyPurgeCount.length; i++) {dailyPurgeCount[i] = 0;}
    }

    function coinJackpot() internal
    {
        uint32 dailyCoinJackpot = dailyCoinBurn * 3 / 20;
        dailyCoinBurn = 0;
        uint24 randomNum = uint24(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)) )% 256);
        uint8[12] memory traitIndices;
        uint8[4] memory winningTrait;
        uint24 max;

        for (uint8 i = 0; i < 12; i++) 
        {
            traitIndices[i] = uint8(randomNum >> i * 6 & 0x3f);
        }
        for (uint8 i = 1; i < 5; i++) 
        {
            max = 0;
            for (uint8 j = 1; j < 4; j++) 
            {
                uint8 trait = i * j -1;
                if (totalCoinBurn[traitIndices[trait]] > max) 
                {
                    max = totalCoinBurn[traitIndices[trait]];
                    winningTrait[i] = traitIndices[trait] * i;
                }
            }
        }
        for (uint8 i = 0; i < 4; i++) 
        {
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[randTraitTicket(winningTrait[i])], dailyCoinJackpot);
        }
    }

    function getWinningTraits() private view returns (uint8[3] memory) 
    {
        uint8[4] memory winningTraits;
        uint8 start;
        uint8 end;

        // Generate a single random number
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));

        for (uint8 quadrant = 1; quadrant <= 3; quadrant++) {
            if (quadrant == 1) {
                start = 0;
                end = 8;
            } else if (quadrant == 2) {
                start = 8;
                end = 16;
            } else if (quadrant == 3) {
                start = 16;
                end = 80;
            }

            uint16 maxCount = dailyPurgeCount[start];
            uint8 winner = start;
            for (uint8 i = start + 1; i < end; i++) {
                if (dailyPurgeCount[i] > maxCount) {
                    maxCount = dailyPurgeCount[i];
                    winner = i;
                } else if (dailyPurgeCount[i] == maxCount) {
                    if ((randomNum >> (i * 2)) & 0x1) {
                        winner = i;
                    }
                }
            }

            if (quadrant == 1) {
                uint8 randomSegment = uint8((randomNum >> 8) & 0x7);
                winningTraits[0] = randomSegment * 8 + winner;
            } else if (quadrant == 2) {
                uint8 randomSegment = uint8((randomNum >> 16) & 0x7);
                winningTraits[1] = winner * 8 + randomSegment + 64;
            } else if (quadrant == 3) {
                uint8 randomSegment = uint8((randomNum >> 24) & 0x3F);
                winningTraits[2] = randomSegment + 192;
            }
        }
        winningTraits[3] = uint8((randomNum >> 32) & 0x3F);
        return winningTraits;
    }
// Picks a random address from all addresses which have purged, weighted by number of purges.
    function randTraitTicket(uint8 trait) private returns (uint24) {
        uint16 random = uint16(uint256(keccak256(abi.encodePacked(dailyPurgeCount[uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 256]))) % traitPurgeTicket[trait].length); 
        emit RandomPurge(trait, random, indexAddress[traitPurgeTicket[trait][random]]);
        return traitPurgeTicket[trait][random];
    }

// Requirements for different mint types

    function RequireHundredMax(uint16 _number) pure private
    {
        require(_number <= 100, "Maximum of 100 mints allowed per tx");
        require(_number > 0);
    }
    
    function onlyBeforeReveal() view private
    {
        require(REVEAL == false);
    }

    function RequireCorrectFunds(uint256 totalCost) view private
    {
        // Check user's USDC balance
        require(IERC20(usdcTokenAddress).balanceOf(msg.sender) >= totalCost, "Insufficient USDC balance");

        // Check allowance
        require(IERC20(usdcTokenAddress).allowance(msg.sender, address(this)) >= totalCost, "USDC allowance too low");

    }

    function RequireCoinFunds(uint16 _number) view private
    {
        require (PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= _number * cost, "Not enough $PURGED");
    }

// Minting adds half of the mint cost to the prize pool.
// This ether is locked into the contract and can only be released by winning the game.
    function addToPrizePool(uint16 _number) private
    {
        PrizePool += cost * _number;
    }

// Pays $PURGED to referrers when their referrals mint tokens.
    function payReferrer(uint16 _number, string calldata referrer) private
    {
        uint24 code;
        if (referralCode[referrer] != 0) 
        {
            code = referralCode[referrer];
        }
        else {
            code = addressIndex[owner()];
        }
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[code], _number * cost / 20);
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
            if (_tokenId < 32001)
            {
                if (_tokenId + offset <= totalMinted) return(_tokenId + offset);
                else return(_tokenId + offset - totalMinted);
            }
        }
        return(_tokenId);
    }


    event MintAndPurge(uint16 tokenId, uint24 tokenTraits, address from);
    event TokenMinted(uint16 tokenId, uint24 tokenTraits, address from);
    event Referred(string referralCode, address referrer, uint16 number, address from);
    event RandomPurge(uint8 trait, uint16 random, address player);
    event CoinBurned(address from, uint16 tokenId, uint256 amount);

// Owner game-running functions.
    function setCost(uint _newCost) external onlyOwner 
    {
        onlyBeforeReveal();
        cost = _newCost;
    }


    function setPublicSaleStatus(bool _status) external onlyOwner 
    {
        onlyBeforeReveal();
        publicSaleStatus = _status;
    }


    function reveal(bool _REVEAL, string calldata updatedURI) external onlyOwner 
    {
        onlyBeforeReveal();
        require(paidJackpot == true);
        require(offset != 0);
        require(publicSaleStatus == false);
        REVEAL = _REVEAL;
        baseTokenURI = updatedURI;
        revealTime = uint32(block.timestamp);
        dailyJackpotTime = revealTime;
    }

    function setTokenUri(string calldata updatedURI) external onlyOwner
    {
       baseTokenURI = updatedURI; 
    }

    function setPurgedCoinAddress(address _purgedCoinContract) external onlyOwner
    {
        purgedCoinContract = _purgedCoinContract;
    }

    //totalSupply includes purged tokens before reveal.  

     function totalSupply() external view returns(uint256)
    {
        if(REVEAL == false) return(totalMinted + MAPtokens);
        return totalMinted;
    }


    receive() external payable {require(false, "No ETH allowed");}

    // Winnings must be claimed by 6 months after the game ends.
    function withdrawAbandoned() external onlyOwner 
    {
        require(gameOver == true);
        require(block.timestamp > gameEndTime + 180 days);
        IERC20(usdcTokenAddress).transfer(owner(), IERC20(usdcTokenAddress).balanceOf(address(this)));
    }   

    function claimWinnings() external 
    {
        uint24 player = addressIndex[msg.sender];
        require (claimableWinnings[player] > 0, "No winnings to claim");
        uint256 winnings = claimableWinnings[player] * 1000000;
        claimableWinnings[player] = 0;
        require(IERC20(usdcTokenAddress).transfer(msg.sender, winnings), "USDC transfer failed");
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseTokenURI, tokenId.toString()));
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) 
    {
        if (to == address(0)) {
            require(purging == true, "Use purge function");
        }
        if (gameOver == true) {
            require(block.timestamp > gameEndTime + 24 hours, "Transfers disabled for 24h after game over");
        }
        return super._update(to, tokenId, auth);
    }

}