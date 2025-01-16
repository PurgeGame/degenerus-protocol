// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @custom:security-contact purgegamenft@gmail.com

interface PurgedCoinInterface 
{
    function mintFromPurge(address yourAddress, uint256 _amount) external;
    function burnToMint(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}


contract PurgeGameBetaTest is ERC721, Ownable 
{
    using Strings for uint256;

    
    bool private paidJackpot;
    bool public publicSaleStatus;
    bool public REVEAL;
    bool public gameOver;
    bool private purging;

    uint8 private dailyJackpotCounter;
    uint8 public constant cost = 100;

    uint24 public index;

    uint32 private offset;
    uint32 private MAPtokens;
    uint32 public totalMinted;

    uint32 public revealTime;
    uint32 public gameEndTime;
    uint32 public dailyJackpotTime;
    

    address private constant purgedCoinContract = 0x3b7e01469d545B187ef526f04A506B7D6F001a74;
    address public constant usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    
   
    uint256 public constant million = 1000000;
    uint256 public startingPrizePool;
    uint256 public PrizePool;
    uint256 private dailyCoinBurn;

    uint32[256] public traitRemaining;
    uint32[80] public dailyPurgeCount;
    uint256[256] public totalCoinBurn;

    mapping(address => bool) private trustedAddresses;
    mapping(uint32 => uint24) public tokenTraits;
    mapping(uint8 => uint24[]) private traitPurgeTicket;
    mapping(uint24 => address) private indexAddress;
    mapping(address => uint24) private addressIndex;
    mapping(string => uint24) private referralCode;
    mapping(uint24 => uint256) public claimableWinnings;
    mapping(uint24 => uint256) public playerLuckbox;

    string public baseTokenURI = "ipfs://QmdxAQbPoqom3EuNoBZGSonjvv5afWDyo8YFaNoscNLcTV/";
   
    constructor() ERC721("Purge Game Beta Test", "PURGEGAMEBETA") Ownable(msg.sender){}


    modifier onlyTrusted() {
        if (msg.sender != owner()) {
            require(trustedAddresses[msg.sender], "Caller is not a trusted address");
        }
        _;
    }
    
// Links user addresses to a uint24 to save gas when recording game data and will be referenced in future seasons.
    function initAddress(address sender) public{
        if (addressIndex[sender] == 0){
            index +=1;
            addressIndex[sender] = index;
            indexAddress[index] = sender;
        }
    }

    function returnAddressIndex(address _address) external view returns(uint24){
        return(addressIndex[_address]);
    }

    function returnIndexAddress(uint24 _index) external view returns(address){
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

    function returnReferralCodeOwner(string calldata _referralCode) external view returns(uint24){
        return(referralCode[_referralCode]);
    }

// Mint function.
    function mintTrophy() external onlyTrusted {
        require(_ownerOf(4206942069) == address(0), "Trophy already minted");
        _mint(address(this), 4206942069);
    }

    function mint(uint32 _number, string calldata referrer) external {
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 10000000, "Max tokens reached");
        RequireThousandMax(_number);
        usdcRecieve(_number * cost * million);
        _mintToken(_number);
        payReferrer(_number, referrer);
    }

// Mint with $PURGED.
    function coinMint(uint32 _number) external{
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < 10000000, "Max tokens reached");
        RequireThousandMax(_number);
        require(PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= _number * cost * million, "Not enough $PURGED");
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * million);
        _mintToken(_number);
    }
    
    function _mintToken(uint32 _number) private{
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
    function mintAndPurge(uint32 _number, string calldata referrer) external {
        usdcRecieve(_number * cost * million);
        codeMintAndPurge(_number);
        payReferrer(_number, referrer);
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _number * cost * million);
    }

    function coinMintAndPurge(uint32 _number) external {
        require (PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= _number * cost * million, "Not enough $PURGED");
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, _number * cost * million * 9 / 10);
        codeMintAndPurge(_number);
    }

    function codeMintAndPurge(uint32 _number) private{
        require (publicSaleStatus == true, 'Mint inactive');
        RequireThousandMax(_number);
        initAddress(msg.sender);
        uint32 mapTokenNumber = 10000000 + MAPtokens;
        for(uint32 i= 0; i < _number; i++){
            uint24 traits = setTraits(mapTokenNumber + i); 
            purgeWrite(traits,addressIndex[msg.sender]);
            emit MintAndPurge(mapTokenNumber + i, traits, msg.sender);
        }
        MAPtokens += _number;   
    }

    function miniPurge() external {
        usdcRecieve(cost * million / 4);
        codeMiniPurge();
    }

    function coinMiniPurge() external{
        require(PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= cost * million / 4, "Not enough $PURGED");
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, cost * million / 4);
        codeMiniPurge();
    }

    function codeMiniPurge() private{
        require(publicSaleStatus == true, 'Public sale inactive');
        initAddress(msg.sender);
        uint16 randomHash = uint16(uint(keccak256(abi.encodePacked(PrizePool,block.number))));
        uint8 trait = getTrait(randomHash) + ((uint8(randomHash >> 5) & 0x03) * 64);
        traitPurgeTicket[trait].push(addressIndex[msg.sender]);
        emit MiniPurge(trait, msg.sender);
    }

    function usdcRecieve(uint256 amount) private{
        RequireCorrectFunds(amount);
        PrizePool += amount;
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), amount);
    }

// Generates token traits and adds the trait info to storage if minting an actual token.
    function setTraits(uint32 _tokenId) private returns(uint24){
        if (_tokenId < 10000000){
            tokenTraits[_tokenId] = rarity(_tokenId);
            for(uint8 c = 0; c < 4; c++){
                traitRemaining[uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c << 6))] += 1;
            }
            return(tokenTraits[_tokenId]); 
        }
        return rarity(_tokenId);
    }

    function rarity(uint32 _tokenId) private view returns(uint24){
        uint64 randomHash = uint64(uint256(keccak256(abi.encodePacked(_tokenId,block.number))));
        uint24 result = getTrait(uint16(randomHash));
        result += getTrait(uint16(randomHash >> 11)) << 6;
        result += getTrait(uint16(randomHash >> 22)) << 12;
        result += getTrait(uint16(randomHash >> 33)) << 18;
        return result;
    }

    function getTrait(uint16 _input) private pure returns (uint8) {
        _input &= 0x7ff; 
        if (_input < 840) {
            return uint8(_input / 35);
        } else if (_input < 1352) {
            return uint8(24 + (_input - 840) / 32);
        } else if (_input < 1832) {
            return uint8(40 + (_input - 1352) / 30);
        } else {
            return uint8(56 + (_input - 1832) / 27);
        }
    }

    function luckyCoinBurn(uint256 amount, uint32 _tokenId) external {
        require(
            amount > 0 && amount <= PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender),
            "Invalid amount"
        );
        initAddress(msg.sender);
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, amount);
        if (_tokenId < 1000000000) {
            uint24 traits = tokenTraits[realTraitsFromTokenId(_tokenId)];
            totalCoinBurn[uint8(traits & 0x3f)] += amount/2;
            totalCoinBurn[uint8((traits >> 6) & 0x3f)] += amount/2;
            totalCoinBurn[uint8((traits >> 12) & 0x3f)] += amount/2;
            totalCoinBurn[uint8((traits >> 18) & 0x3f)] += amount/2;
        }else{
            _tokenId -= 1000000000;
            require(_tokenId >= 0 && _tokenId <= 255, "trait ID must be between 0 and 255");
            totalCoinBurn[_tokenId] += amount;
        }
        dailyCoinBurn += amount;
        playerLuckbox[addressIndex[msg.sender]] += amount;
        emit CoinBurned(msg.sender, _tokenId, amount);
    }


// Burns tokens and creates payout tickets for each trait purged, then prints $PURGED.
    function purge(uint32[] calldata _tokenIds) external{ 
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        initAddress(msg.sender);
        uint32 _tokenId;
        purging = true;
        for(uint32 i = 0; i < _tokenIds.length; i++) {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(tokenTraits[_tokenId], addressIndex[msg.sender]);
            purgeTraits(_tokenId);     
        }      
        purging = false;  
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost * million / 10);
    }

    function purgeWrite(uint24 traits, uint24 sender) private {
        uint8[4] memory traitIndices;
        traitIndices[0] = uint8(traits & 0x3f);
        traitIndices[1] = uint8((traits >> 6) & 0x3f);
        traitIndices[2] = uint8((traits >> 12) & 0x3f);
        traitIndices[3] = uint8((traits >> 18) & 0x3f);
        if (REVEAL){
            dailyPurgeCount[traitIndices[0] & 0x07] += 1;
            dailyPurgeCount[traitIndices[1] / 8 + 8] += 1;
            dailyPurgeCount[traitIndices[2] + 16] += 1;
        }
        for (uint8 c = 0; c < 4; c++) {
            traitPurgeTicket[traitIndices[c] + 64 * c].push(sender);
        }
    }
// Records the removal of a token's traits from the game.
    function purgeTraits(uint32 _tokenId) private{
        for(uint8 c = 0; c < 4; c++){
            removeTraitRemaining(uint8((tokenTraits[_tokenId] >> (c * 6) & 0x3f) + (c << 6)));
        }
    }

// Records the removal of a trait and checks to see if this transaction exterminates that trait. 
// If so, this ends the game and pays out the winnings to everyone who has purged a token with that trait.
    function removeTraitRemaining(uint8 trait) private {
        traitRemaining[trait] -=1;
        if (traitRemaining[trait] == 0){   
            if (gameOver == false){
                endGame();
                payout(trait);  
            }
        }
    }

    function endGame() private{
        gameOver = true;
        gameEndTime = uint32(block.timestamp);
        coinJackpot();
    }

// Pays the exterminator 20% of the prize pool.
// Then pays each player who purged a token with the winning trait an equal amount for each token purged.
    function payout(uint8 trait) private{
        uint32 totalPurges = uint32(traitPurgeTicket[trait].length - 1);
        if (totalPurges == 0) totalPurges = 1;
        uint256 grandPrize = PrizePool / 5;
        uint256 normalPayout = (PrizePool - grandPrize) / totalPurges;
        PrizePool = 0;
        startingPrizePool = 0;
        addClaimableUSDC(addressIndex[msg.sender], grandPrize);
        for (uint32 i = 0; i < totalPurges; i++){ 
            addClaimableUSDC(traitPurgeTicket[trait][i], normalPayout);
        } 
    }

    function addClaimableUSDC(uint24 player, uint256 amount) private
    {
        claimableWinnings[player] += amount;
        emit CoinPaid(indexAddress[player], amount, false);
    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyTrusted{
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        startingPrizePool = PrizePool * 85 / 100;   
        paidJackpot = true;
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(owner(), PrizePool / 4);
        uint8[9] memory trait;
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));

        // First trait is completely random
        trait[0] = uint8(random & 0xFF);

        // Next four traits fall within specific quadrants
        for (uint8 c = 1; c < 8; c+=2) {
            trait[c] = uint8((random >> (c * 6)) & 0x3F) + (c - 1) * 64;
            trait[c + 1] = trait [c];
        }
        // Define the number of winners for each trait
        uint8[9] memory numbers = [1, 1, 8, 1, 8, 1, 5, 1, 20];
        // Define the prize for each winner - (x *.1% of prize pool / number of winners)
        uint8[9] memory prizes = [100, 5, 5, 4, 6, 3, 7, 10, 10];

        // Distribute prizes to winners
        for (uint8 i = 0; i < 9; i++) {
            uint24[] memory winners = randTraitTicket(trait[i], numbers[i]);
            for (uint8 j = 0; j < numbers[i]; j++) {
                uint256 prize = PrizePool * prizes[i] / 1000 / numbers[i];
                addClaimableUSDC(winners[j], prize);
            }
        }

        // Mint coins for the consolation prize
        for (uint32 c = 0; c < traitPurgeTicket[trait[0]].length; c++) {
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[traitPurgeTicket[trait[0]][c]], 100 * million);
        }
        PrizePool = PrizePool * 85 / 100;
    }

    function payDailyJackpot() external onlyTrusted {
        require(dailyJackpotTime != 0);
        require(block.timestamp >= dailyJackpotTime + 23 hours);
        require(gameOver == false);
        coinJackpot();
        uint256 jackpot = startingPrizePool / 100;
        PrizePool -= startingPrizePool / 25;
        uint8[4] memory winningTraits = getWinningTraits();
        uint24[] memory winners;
        uint8[4] memory numbers = [20, 10, 4, 1];
        for (uint8 i = 0; i < 4; i++) {
            winners = randTraitTicket(winningTraits[i], numbers[i]);
            for (uint8 j = 0; j < numbers[i]; j++) {
                addClaimableUSDC(winners[j], jackpot / numbers[i]);
            }
        }
        dailyJackpotCounter += 1;
        if (dailyJackpotCounter == 25) {
            endGame();
        }
        else {dailyJackpotTime = uint32(block.timestamp);}
        for (uint8 i = 0; i < dailyPurgeCount.length; i++) {dailyPurgeCount[i] = 0;}
    }

    function coinJackpot() private{
        if (dailyCoinBurn < 1600000000){
            dailyCoinBurn = 1600000000;
        }
        uint256 dailyCoinJackpot = dailyCoinBurn * 3 / 20;
        dailyCoinBurn = 0;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,"1")));
        uint8[12] memory traitIndices;
        uint8[4] memory winningTrait;
        uint256 max;
        for (uint8 i = 0; i < 12; i++) {
            traitIndices[i] = uint8(randomNum >> i * 6 & 0x3f);
        }
        for (uint8 i = 0; i < 4; i++) {
            max = 0;
            for (uint8 j = 0; j < 3; j++) {
                uint8 trait = i * 3 + j;
                if (totalCoinBurn[traitIndices[trait]] >= max) {
                    max = totalCoinBurn[traitIndices[trait]];
                    winningTrait[i] = traitIndices[trait] + 64 * i;
                }
            }
        }
        for (uint8 i = 0; i < 4; i++) {
            uint24 luckbox = getTopLuckbox(randTraitTicket(winningTrait[i], 5));
            if (playerLuckbox[luckbox] != 0){
                PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[luckbox], dailyCoinJackpot);
                emit CoinPaid(indexAddress[luckbox], dailyCoinJackpot, true);
            }
        }
        
    }

    function getTopLuckbox(uint24[] memory players) private view returns (uint24) {
        uint256 highestLuckboxValue = 0;
        uint24 topLuckbox = 0;
        for (uint8 i = 0; i < players.length; i++) {
            uint24 player = players[i];
            uint256 luckboxValue = playerLuckbox[player];
            if (luckboxValue > highestLuckboxValue) {
                highestLuckboxValue = luckboxValue;
                topLuckbox = player;
            }
        }
        return topLuckbox;
    }

    function getWinningTraits() private view returns (uint8[4] memory) {
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
                    if ((randomNum >> i & 0x1) == 1) {
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

    function randTraitTicket(uint8 trait, uint8 amount) private returns (uint24[] memory) {
        uint24[] memory selectedTickets;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,trait))); 
        for (uint8 i = 0; i < amount; i++) {
            uint32 rand = uint32(randomNum << i * 16);
            uint32 randomIndex = uint32(rand % traitPurgeTicket[trait].length);
            selectedTickets[i] = traitPurgeTicket[trait][randomIndex];
            emit RandomTicket(trait, randomIndex, indexAddress[selectedTickets[i]]);
        }
        return selectedTickets;
    }

// Requirements for different mint types

    function RequireThousandMax(uint32 _number) pure private {
        require(_number > 0 && _number <= 1000, "Number of mints must be between 1 and 1000");
    }

    function RequireCorrectFunds(uint256 totalCost) view private{
        require(IERC20(usdcTokenAddress).balanceOf(msg.sender) >= totalCost, "Insufficient USDC balance");
        require(IERC20(usdcTokenAddress).allowance(msg.sender, address(this)) >= totalCost, "USDC allowance too low");
    }

// Pays $PURGED to referrers when their referrals mint tokens.
    function payReferrer(uint32 _number, string calldata referrer) private{
        uint24 code;
        if (referralCode[referrer] != 0) {
            code = referralCode[referrer];
        }
        else {
            code = addressIndex[owner()];
        }
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(indexAddress[code], _number * cost * million / 20);
        emit Referred(referrer, indexAddress[referralCode[referrer]], _number, msg.sender);
    }

// Anti-hack funtion. The traits generated by minting will not correspond to the token minted.
    function setOffset(uint32 _offset) external onlyTrusted{
        require(offset == 0);
        offset = _offset;
    }
    
    function realTraitsFromTokenId(uint32 _tokenId) private view returns(uint32){
        if (offset != 0){
            if (_tokenId < 10000000){
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
    event CoinPaid(address from, uint256 amount, bool coin);
    event CoinBurned(address from, uint32 tokenId, uint256 amount);

// Owner game-running functions.

    function setPublicSaleStatus(bool _status) external onlyTrusted {
        require(REVEAL == false);
        publicSaleStatus = _status;
    }


    function reveal(string calldata updatedURI) external onlyTrusted {
        require(REVEAL == false);
        require(paidJackpot == true);
        require(offset != 0);
        require(publicSaleStatus == false);
        REVEAL = true;
        baseTokenURI = updatedURI;
        revealTime = uint32(block.timestamp);
        dailyJackpotTime = revealTime;
    }

    function setTokenUri(string calldata updatedURI) external onlyTrusted{
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
    function withdrawAbandoned() external onlyOwner {
        require(gameOver == true);
        require(block.timestamp > gameEndTime + 180 days);
        IERC20(usdcTokenAddress).transfer(owner(), IERC20(usdcTokenAddress).balanceOf(address(this)));
    }   

    function claimWinnings() external {
        uint24 player = addressIndex[msg.sender];
        require (claimableWinnings[player] > 0, "No winnings to claim");
        uint256 winnings = claimableWinnings[player];
        claimableWinnings[player] = 0;
        require(IERC20(usdcTokenAddress).transfer(msg.sender, winnings), "USDC transfer failed");
    }

 /*    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseTokenURI, tokenId.toString()));
    } */

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        if (gameOver == true) {
            require(block.timestamp > gameEndTime + 24 hours, "Transfers disabled for 24h after game over");
        }else if (to == address(0)) {
            require(purging == true, "Use purge function");
        }
        return super._update(to, tokenId, auth);
    }
}