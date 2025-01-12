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

    uint24 public index;

    uint32 private offset;
    uint32 public MAPtokens;
    uint32 public totalMinted;
    uint32 public startingPrizePool;
    uint32 public PrizePool;
    uint32 private dailyCoinBurn;
    uint32 public revealTime;
    uint32 public gameEndTime;
    uint32 public dailyJackpotTime;
    uint32 public constant cost = 100;

    address private constant purgedCoinContract = 0x3b7e01469d545B187ef526f04A506B7D6F001a74;
    address public constant usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    

    uint32[256] public traitRemaining;
    uint32[80] public dailyPurgeCount;
    uint24[256] public totalCoinBurn;

    mapping(address => bool) trustedAddresses;
    mapping(uint32 => uint24) tokenTraits;
    mapping(uint8 => uint24[]) traitPurgeTicket;
    mapping(uint24 => address) indexAddress;
    mapping(address => uint24) addressIndex;
    mapping(string => uint24) referralCode;
    mapping(uint24 => uint32) claimableWinnings;
    mapping(uint24 => uint24) playerLuckbox;

    string public baseTokenURI = "ipfs://QmdxAQbPoqom3EuNoBZGSonjvv5afWDyo8YFaNoscNLcTV/";
   
    constructor() ERC721("Purge Game Beta Test", "PURGEGAMEBETA") {}

    modifier onlyTrusted() {
        if (msg.sender != owner()) {
            require(trustedAddresses[msg.sender], "Caller is not a trusted address");
            _;
        }
    }
    
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
    function createReferralCode(string calldata _referralCode) external {
        bytes memory referralCodeBytes = bytes(_referralCode);
        uint256 referralCodeLength = referralCodeBytes.length;

        require(
            referralCodeLength != 0 && referralCodeLength <= 40,
            "Invalid referral code length"
        );
        require(referralCode[_referralCode] == 0, "Referral code is taken");
        initAddress(msg.sender);
        referralCode[_referralCode] = addressIndex[msg.sender];
    }

    function returnReferralCodeOwner(string calldata _referralCode) external view returns(uint24)
    {
        return(referralCode[_referralCode]);
    }

// Mint function.
/*     function mintTrophy() external onlyTrusted
    {
        require(ownerOf(0)!=address(this) , "Trophy already minted");
        _mint(address(this),0);
    }  */

    function mint(uint32 _number, string calldata referrer) external 
    {
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 10000000, "Max tokens reached");
        RequireThousandMax(_number);
        usdcRecieve(_number);
        _mintToken(_number);
        payReferrer(_number, referrer);
        addToPrizePool(_number);
    }

// Mint with $PURGED.
    function coinMint(uint32 _number) external
    {
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 10000000, "Max tokens reached");
        RequireThousandMax(_number);
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 1000);
        _mintToken(_number);
    }
    
    function _mintToken(uint32 _number) private
    {
        uint32 tokenId = totalMinted;
        for (uint32 i = 0; i < _number; i++) {
            tokenId++;
            _mint(msg.sender, tokenId);
            uint24 traits = setTraits(tokenId);
            emit TokenMinted(tokenId, traits, msg.sender);
        }
        totalMinted += _number;
    }

// Creates a payout ticket for a token without actally minting that token to save gas.
    function mintAndPurge(uint32 _number, string calldata referrer) external  
    {
        usdcRecieve(_number);
        codeMintAndPurge(_number);
        payReferrer(_number, referrer);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _number * cost * 1000);
    }

    function coinMintAndPurge(uint32 _number) external 
    {
        RequireCoinFunds(_number);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * 900);
        codeMintAndPurge(_number);
    }

    function codeMintAndPurge(uint32 _number) private
    {
        require (publicSaleStatus == true, 'Mint inactive');
        RequireThousandMax(_number);
        initAddress(msg.sender);
        uint32 mapTokenNumber = 10000000 + MAPtokens;
        for(uint32 i= 0; i < _number; i++)
        {
            uint24 traits = setTraits(mapTokenNumber + i); 
            purgeWrite(traits,addressIndex[msg.sender]);
            emit MintAndPurge(mapTokenNumber + i, traits, msg.sender);
        }
        addToPrizePool(_number);
        MAPtokens += _number;   
    }

    function miniPurge() external 
    {
        require(publicSaleStatus == true, 'Public sale inactive');
        initAddress(msg.sender);
        uint256 totalCost = cost * 250000;
        RequireCorrectFunds(totalCost);
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), totalCost);
        PrizePool += cost / 4;
        uint16 randomHash = uint16(uint(keccak256(abi.encodePacked(PrizePool,block.number))));
        uint8 trait = uint8(getTrait(randomHash)) + (uint8(randomHash >> 5 ) % 4) * 64;
        traitPurgeTicket[trait].push(addressIndex[msg.sender]);
        emit MiniPurge(trait, msg.sender);
    }

    function usdcRecieve(uint32 _number) private
    {
        uint256 totalCost = _number * cost * 1000000;
        RequireCorrectFunds(totalCost);
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), totalCost);
    }

// Generates token traits and adds the trait info to storage if minting an actual token.
    function setTraits(uint32 _tokenId) private returns(uint24)
    {
        if (_tokenId < 29500)
        {
            tokenTraits[_tokenId] = rarity(_tokenId);
            for(uint8 c = 0; c < 4; c++)
            {
                traitRemaining[uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c << 6))] +=1;
            }
            return(tokenTraits[_tokenId]); 
        }
        return rarity(_tokenId);
    }

    function rarity(uint32 _tokenId) private view returns(uint24)
    {
        uint64 randomHash = uint64(uint(keccak256(abi.encodePacked(_tokenId,block.number))));
        uint24 result = getTrait(uint16(randomHash));
        result += getTrait(uint16(randomHash >> 11)) << 6;
        result += getTrait(uint16(randomHash >> 22)) << 12;
        result += getTrait(uint16(randomHash >> 33)) << 18;
        return result;
    }

    function getTrait(uint16 _input) private pure returns (uint24) {
        _input &= 0x7ff; // Use bitwise AND to limit _input to 11 bits

        if (_input < 840) {
            return _input / 35;
        } else if (_input < 1352) {
            return 24 + (_input - 840) / 32;
        } else if (_input < 1832) {
            return 40 + (_input - 1352) / 30;
        } else {
            return 56 + (_input - 1832) / 27;
        }
    }

    function luckyCoinBurn(uint24 amount, uint32 _tokenId) external {
        require(
            amount > 0 && amount <= PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender),
            "Invalid amount"
        );
        initAddress(msg.sender);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, amount);
        uint24 traits = tokenTraits[realTraitsFromTokenId(_tokenId)];
        unchecked {
            totalCoinBurn[uint8(traits & 0x3f)] += amount;
            totalCoinBurn[uint8((traits >> 6) & 0x3f)] += amount;
            totalCoinBurn[uint8((traits >> 12) & 0x3f)] += amount;
            totalCoinBurn[uint8((traits >> 18) & 0x3f)] += amount;
            dailyCoinBurn += amount;
            playerLuckbox[addressIndex[msg.sender]] += amount;
        }

        emit CoinBurned(msg.sender, _tokenId, amount);
    }


// Burns tokens and creates payout tickets for each trait purged, then prints $PURGED.
    function purge(uint32[] calldata _tokenIds) external  
    { 
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        initAddress(msg.sender);
        uint32 _tokenId;
        purging = true;
        for(uint32 i = 0; i < _tokenIds.length; i++) 
        {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(tokenTraits[_tokenId], addressIndex[msg.sender]);
            purgeTraits(_tokenId);     
        }      
        purging = false;  
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost * 100);
    }

    function purgeWrite(uint24 traits, uint24 sender) private {
        uint8[4] memory traitIndices;
        traitIndices[0] = uint8(traits & 0x3f);
        traitIndices[1] = uint8((traits >> 6) & 0x3f);
        traitIndices[2] = uint8((traits >> 12) & 0x3f);
        traitIndices[3] = uint8((traits >> 18) & 0x3f);
        if (!REVEAL){
            dailyPurgeCount[traitIndices[0] % 8] += 1;
            dailyPurgeCount[traitIndices[1] / 8 + 8] += 1;
            dailyPurgeCount[traitIndices[2] + 16] += 1;
        }
        for (uint8 c = 0; c < 4; c++) {
            traitPurgeTicket[traitIndices[c] + 64 * c].push(sender);
        }
    }
// Records the removal of a token's traits from the game.
    function purgeTraits(uint32 _tokenId) private
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
                endGame();
                payout(trait);  
            }
        }
    }

    function endGame() private
    {
        gameOver = true;
        gameEndTime = uint32(block.timestamp);
    }

// Pays the exterminator 25% of the prize pool.
// Then pays each player who purged a token with the winning trait an equal amount for each token purged.
    function payout(uint8 trait) private
    {
        uint32 totalPurges = uint32(traitPurgeTicket[trait].length - 1);
        if (totalPurges == 0) totalPurges = 1;
        uint32 grandPrize = PrizePool / 4;
        uint32 normalPayout = (PrizePool - grandPrize) / totalPurges;
        PrizePool = 0;
        addClaimableUSDC(addressIndex[msg.sender], grandPrize);
        for (uint32 i = 0; i < totalPurges; i++)
        { 
            addClaimableUSDC(traitPurgeTicket[trait][i], normalPayout);
        } 

    }

    function addClaimableUSDC(uint24 player, uint32 amount) internal
    {
        claimableWinnings[player] += amount * 1000000;
        emit CoinPaid(indexAddress[player], amount, false);
    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyTrusted
    {
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(owner(), PrizePool * 250);
        startingPrizePool = PrizePool * 9 / 10;
        PrizePool -= PrizePool / 10;
        paidJackpot = true;
        uint8 randomTrait = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) %256);
        addClaimableUSDC(randTraitTicket(randomTrait, 1)[0], startingPrizePool / 9);
    }

    function payDailyJackpot() external onlyTrusted {
        require(dailyJackpotTime != 0);
        require(block.timestamp >= dailyJackpotTime + 23 hours);
        require(gameOver == false);
        coinJackpot();
        uint32 jackpot = startingPrizePool / 100;
        PrizePool -= startingPrizePool / 25;
        uint8[4] memory winningTraits = getWinningTraits();
        // Update claimable winnings for each winner
        for (uint8 i = 0; i < 4; i++) {
            if (i == 0){
                for (uint8 j = 0; j < 5; j++){
                    addClaimableUSDC(randTraitTicket(winningTraits[i],5)[j], jackpot/5);                  
                }
            } else if (i == 1){
                for (uint8 j = 0; j < 3; j++){
                    addClaimableUSDC(randTraitTicket(winningTraits[i],3)[j], jackpot/3);
                }
            } else if (i == 2){
                for (uint8 j = 0; j < 2; j++){
                    addClaimableUSDC(randTraitTicket(winningTraits[i],2)[j], jackpot/2);
                }
            } else if (i == 3){
                addClaimableUSDC(randTraitTicket(winningTraits[i],1)[0], jackpot);
            }
        }
        dailyJackpotCounter += 1;
        if (dailyJackpotCounter == 25) {
            endGame();
        }
        else {dailyJackpotTime = uint32(block.timestamp);}
        for (uint8 i = 0; i < dailyPurgeCount.length; i++) {dailyPurgeCount[i] = 0;}
    }

    function coinJackpot() internal
    {
        uint32 dailyCoinJackpot = dailyCoinBurn * 3 / 20;
        dailyCoinBurn = 0;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,"1")));
        uint8[12] memory traitIndices;
        uint8[4] memory winningTrait;
        uint24 max;

        for (uint8 i = 0; i < 12; i++) 
        {
            traitIndices[i] = uint8(randomNum >> i * 6 & 0x3f);
        }
        for (uint8 i = 0; i < 4; i++) 
        {
            max = 0;
            for (uint8 j = 0; j < 3; j++) 
            {
                uint8 trait = i * 3 + j;
                if (totalCoinBurn[traitIndices[trait]] >= max) 
                {
                    max = totalCoinBurn[traitIndices[trait]];
                    winningTrait[i] = traitIndices[trait] + 64 * i;
                }
            }
        }
        for (uint8 i = 0; i < 4; i++) 
        {
            address winner = indexAddress[randTraitTicket(winningTrait[i],1)[0]];
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(winner, dailyCoinJackpot);
            emit CoinPaid(winner, dailyCoinJackpot, true);
        }
    }

    function getWinningTraits() private view returns (uint8[4] memory) 
    {
        uint8[4] memory winningTraits;
        uint8 start;
        uint8 end;

        // Generate a single random number
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,"2")));

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

            uint32 maxCount = dailyPurgeCount[start];
            uint8 winner = start;
            for (uint8 i = start + 1; i < end; i++) {
                if (dailyPurgeCount[i] > maxCount) {
                    maxCount = dailyPurgeCount[i];
                    winner = i;
                } else if (dailyPurgeCount[i] == maxCount) {
                    if (randomNum >> i & 0x1 == 1) {
                        winner = i;
                    }
                }
            }
            if (quadrant == 1) {
                winningTraits[0] = uint8((randomNum >> 8) & 0x7) * 8 + winner;
            } else if (quadrant == 2) {
                winningTraits[1] = winner * 8 + uint8((randomNum >> 16) & 0x7) + 64;
            } else if (quadrant == 3) {
                winningTraits[2] = uint8((randomNum >> 24) & 0x3F) + 192;
            }
        }
        winningTraits[3] = uint8((randomNum >> 32) & 0x3F);
        return winningTraits;
    }
// Picks a random address from all addresses which have purged, weighted by number of purges.
    function randTraitTicket(uint8 trait, uint8 amount) private returns (uint24[5] memory) {
        uint24[5] memory selectedTickets;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,"3"))); 
        for (uint8 i = 0; i < amount; i++) {
            uint32 rand = uint32(randomNum << i * 32);
            uint32 randomIndex = uint32(rand % traitPurgeTicket[trait].length);
            selectedTickets[i] = traitPurgeTicket[trait][randomIndex];
            emit RandomTicket(trait, randomIndex, indexAddress[selectedTickets[i]]);
        }
        return selectedTickets;
    }

// Requirements for different mint types

    function RequireThousandMax(uint32 _number) pure private
    {
        require(_number <= 1000, "Maximum of 1000 mints allowed per tx");
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

    function RequireCoinFunds(uint32 _number) view private
    {
        require (PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= _number * cost * 1000, "Not enough $PURGED");
    }

// Minting adds half of the mint cost to the prize pool.
// This ether is locked into the contract and can only be released by winning the game.
    function addToPrizePool(uint32 _number) private
    {
        PrizePool += cost * _number;
    }

// Pays $PURGED to referrers when their referrals mint tokens.
    function payReferrer(uint32 _number, string calldata referrer) private
    {
        uint24 code;
        if (referralCode[referrer] != 0) 
        {
            code = referralCode[referrer];
        }
        else {
            code = addressIndex[owner()];
        }
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[code], _number * cost * 50);
        emit Referred(referrer, indexAddress[referralCode[referrer]], _number, msg.sender);
    }

// Anti-hack funtion. The traits generated by minting will not correspond to the token minted.
    function setOffset(uint32 _offset) external onlyTrusted
    {
        require(offset == 0);
        offset = _offset;
    }
    
    function realTraitsFromTokenId(uint32 _tokenId) private view returns(uint32)
    {
        if (offset != 0)
        {
            if (_tokenId < 10000000)
            {
                if (_tokenId + offset <= totalMinted) return(_tokenId + offset);
                else return(_tokenId + offset - totalMinted);
            }
        }
        return(_tokenId);
    }

    event MintAndPurge(uint32 tokenId, uint24 tokenTraits, address from);
    event MiniPurge(uint8 trait, address player);
    event TokenMinted(uint32 tokenId, uint24 tokenTraits, address from);
    event Referred(string referralCode, address referrer, uint32 number, address from);
    event RandomTicket(uint8 trait, uint32 random, address player);
    event CoinPaid(address from, uint32 amount, bool coin);
    event CoinBurned(address from, uint32 tokenId, uint24 amount);

// Owner game-running functions.

    function setPublicSaleStatus(bool _status) external onlyTrusted 
    {
        onlyBeforeReveal();
        publicSaleStatus = _status;
    }


    function reveal(bool _REVEAL, string calldata updatedURI) external onlyTrusted 
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

    function setTokenUri(string calldata updatedURI) external onlyTrusted
    {
       baseTokenURI = updatedURI; 
    }

    function addTrustedAddress(address _address) external onlyOwner {
        trustedAddresses[_address] = true;
    }

    function removeTrustedAddress(address _address) external onlyTrusted {
        trustedAddresses[_address] = false;
    }

    receive() external payable {}

    function withdrawEth() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

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
        uint32 winnings = claimableWinnings[player];
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