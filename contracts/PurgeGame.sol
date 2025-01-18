// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @custom:security-contact purgegamenft@gmail.com

interface PurgedCoinInterface 
{
    function mintFromPurge(address yourAddress, uint256 _amount) external;
    function burnToMint(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getReferralCodeOwner(string calldata _referralCode) external view returns(address);
    function getPlayerLuckbox(address _index) external view returns(uint256);
    function addToPlayerLuckbox(address player, uint256 amount) external;
    function getTopLuckbox(address[] memory players) external view returns (address);
}

contract PurgeGameBetaTest is ERC721 
{
    using Strings for uint256;

    bool private paidJackpot;
    bool public publicSaleStatus;
    bool public REVEAL;
    bool public gameOver;
    bool private purging;

    uint8 private dailyJackpotCounter;
    uint8 public constant cost = 100;

    uint32 private offset;
    uint32 private MAPtokens;
    uint32 public totalMinted;
    uint32 public revealTime;
    uint32 public gameEndTime;
    uint32 public dailyJackpotTime;
    uint32 constant private maxTokens = 10000000;

    address private constant purgedCoinContract = 0x3b7e01469d545B187ef526f04A506B7D6F001a74;
    address public constant usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    address private _owner;
    
    uint256 public constant million = 1000000;
    uint256 public startingPrizePool;
    uint256 public PrizePool;
    uint256 private dailyCoinBurn;

    uint32[256] public traitRemaining;
    uint32[80] public dailyPurgeCount;
    uint256[256] public totalCoinBurn;

    mapping(address => bool) private trustedAddresses;
    mapping(uint32 => uint24) public tokenTraits;
    mapping(uint8 => address[]) private traitPurgeTicket;
    mapping(address => uint256) public claimableWinnings;

    string public baseTokenURI = "ipfs://QmdxAQbPoqom3EuNoBZGSonjvv5afWDyo8YFaNoscNLcTV/";
   
    constructor() ERC721("Purge Game Beta Test", "PURGEGAMEBETA") {
        _owner = msg.sender;
        trustedAddresses[_owner] = true;
    }

    modifier onlyTrusted() {
        require(trustedAddresses[msg.sender], "Caller is not a trusted address");
        _;
    }
    
// Mint function.
    function mint(uint32 _number, bool coin, string calldata referralCode) external {
        require(publicSaleStatus == true, 'Public sale inactive');
        require(totalMinted + _number < maxTokens, "Max tokens reached");
        requireThousandMax(_number);
        uint256 totalCost = _number * cost * million;
        if (coin) {
            coinReceive(totalCost);
        } else {
            usdcReceive(totalCost);
            payReferrer(_number, referralCode);
        }
        uint32 tokenId = totalMinted;
        for (uint32 i = 0; i < _number; i++) {
            tokenId++;
            _mint(msg.sender, tokenId);
            uint24 traits = rarity(tokenId);
            tokenTraits[tokenId] = traits;
            for (uint8 q = 0; q < 4; q++) {
                uint8 trait = uint8((traits >> (q * 6)) & 0x3f) + (q << 6);
                traitRemaining[trait] += 1;
            }
            emit TokenMinted(tokenId, traits, msg.sender);
        }
        totalMinted += _number;
    }

// Creates a payout ticket for a token without actally minting that token to save gas.
    function mintAndPurge(uint32 _number, bool coin, string calldata referralCode) external {
        require (publicSaleStatus == true, 'Mint inactive');
        requireThousandMax(_number);
        uint256 totalCost =  _number * cost * million;
        if (coin) {
            coinReceive(totalCost * 9 / 10);
        } else {
            usdcReceive(totalCost);
            payReferrer(_number, referralCode);
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, totalCost / 10);
        }
        uint32 mapTokenNumber = maxTokens + MAPtokens;
        for(uint32 i = 0; i < _number; i++){
            uint32 tokenId = mapTokenNumber + i;
            uint24 traits = rarity(tokenId); 
            purgeWrite(traits,msg.sender);
            emit MintAndPurge(tokenId, traits, msg.sender);
        }
        MAPtokens += _number;   
    }

    function miniPurge(bool coin) external {
        require(publicSaleStatus == true, 'Public sale inactive');
        if (coin) {
            coinReceive(cost * million / 4);
        } else {
            usdcReceive(cost * million / 4);
        }
        uint16 randomHash = uint16(uint(keccak256(abi.encodePacked(PrizePool,block.number))));
        uint8 trait = getTrait(randomHash) + ((uint8(randomHash >> 5) & 0x03) << 6);
        traitPurgeTicket[trait].push(msg.sender);
        emit MiniPurge(trait, msg.sender);
    }

    function usdcReceive(uint256 amount) private{
        require(IERC20(usdcTokenAddress).balanceOf(msg.sender) >= amount, "Insufficient USDC balance");
        require(IERC20(usdcTokenAddress).allowance(msg.sender, address(this)) >= amount, "USDC allowance too low");
        PrizePool += amount;
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), amount);
    }

    function coinReceive(uint256 amount) private{
        require(PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender) >= amount, "Not enough $PURGED");
        PurgedCoinInterface(purgedCoinContract).burnToMint(msg.sender, amount);
    }

// Generates token traits and adds the trait info to storage
    function setTraits(uint32 _tokenId) private returns(uint24){
        tokenTraits[_tokenId] = rarity(_tokenId);
        for(uint8 q = 0; q < 4; q++){
            traitRemaining[uint8((tokenTraits[_tokenId] >> (q * 6) & 0x3f) + (q << 6))] += 1;
        }
        return(tokenTraits[_tokenId]); 
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
            amount > 5 * million && amount <= PurgedCoinInterface(purgedCoinContract).balanceOf(msg.sender),
            "Invalid amount"
        );
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
        PurgedCoinInterface(purgedCoinContract).addToPlayerLuckbox(msg.sender, amount);
        emit CoinBurned(msg.sender, _tokenId, amount);
    }

// Burns tokens and creates payout tickets for each trait purged, then prints $PURGED.
    function purge(uint32[] calldata _tokenIds) external{ 
        require(gameOver == false, "Game Over");
        require(REVEAL, "No purging before reveal");
        uint32 _tokenId;
        purging = true;
        for(uint32 i = 0; i < _tokenIds.length; i++) {
            _tokenId = _tokenIds[i];
            require(ownerOf(_tokenId) == msg.sender, "You do not own that token");
            _burn(_tokenId);
            _tokenId = realTraitsFromTokenId(_tokenId);
            purgeWrite(tokenTraits[_tokenId], msg.sender);     
        }      
        purging = false;  
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(msg.sender, _tokenIds.length * cost * million / 10);
    }

    function purgeWrite(uint24 traits, address sender) private {
        uint8[4] memory traitIndices;
        traitIndices[0] = uint8(traits & 0x3f);
        traitIndices[1] = uint8((traits >> 6) & 0x3f);
        traitIndices[2] = uint8((traits >> 12) & 0x3f);
        traitIndices[3] = uint8((traits >> 18) & 0x3f);
        if (REVEAL){
            dailyPurgeCount[traitIndices[0] & 0x07] += 1;
            dailyPurgeCount[traitIndices[1] / 8 + 8] += 1;
            dailyPurgeCount[traitIndices[2] + 16] += 1;
            for (uint8 q = 0; q < 4; q++) {
                removeTraitRemaining(traitIndices[q] + (q << 6)); 
            }
        }
        for (uint8 q = 0; q < 4; q++) {
            traitPurgeTicket[traitIndices[q] + (q << 6)].push(sender);
        }
    }
// Records the removal of a trait and checks to see if this transaction exterminates that trait. 
// If so, this ends the game and pays out the winnings to everyone who has purged a token with that trait.
    function removeTraitRemaining(uint8 trait) private {
        traitRemaining[trait] -= 1;
        if (traitRemaining[trait] == 0){   
            if (!gameOver){
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
        addClaimableUSDC(msg.sender, grandPrize);
        _mint(msg.sender, 4206942069);
        for (uint32 i = 0; i < totalPurges; i++){ 
            addClaimableUSDC(traitPurgeTicket[trait][i], normalPayout);
        } 
    }

    function addClaimableUSDC(address player, uint256 amount) private
    {
        claimableWinnings[player] += amount;
        emit CoinPaid(player, amount, false);
    }

// Pays the MAP Jackpot to a random Mint and Purger.
    function payMapJackpot() external onlyTrusted{
        require(paidJackpot == false);
        require(publicSaleStatus == false);
        startingPrizePool = PrizePool * 85 / 100;   
        paidJackpot = true;
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(_owner, PrizePool / 4);
        uint8[9] memory trait;
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));
        // First trait is completely random
        trait[0] = uint8(random & 0xFF);
        // Next four traits fall within specific quadrants
        for (uint8 q = 1; q < 8; q+=2) {
            trait[q] = uint8((random >> (q * 6)) & 0x3F) + ((q - 1) << 6);
            trait[q + 1] = trait [q];
        }
        // Define the number of winners for each trait
        uint8[9] memory numbers = [1, 1, 8, 1, 8, 1, 5, 1, 20];
        // Define the prize for each winner - (x *.1% of prize pool / number of winners)
        uint8[9] memory prizes = [100, 5, 5, 4, 6, 3, 7, 10, 10];
        // Distribute prizes to winners
        uint256 prize;
        address[] memory winners;
        for (uint8 i = 0; i < 9; i++) {
            winners = randTraitTicket(trait[i], numbers[i]);
            prize = PrizePool * prizes[i] / 1000 / numbers[i];
            for (uint8 p = 0; p < numbers[i]; p++) {
                addClaimableUSDC(winners[p], prize);
            }
        }
        // Mint coins for the consolation prize
        for (uint32 c = 0; c < traitPurgeTicket[trait[0]].length; c++) {
            PurgedCoinInterface(purgedCoinContract).mintFromPurge(traitPurgeTicket[trait[0]][c], 100 * million);
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
        address[] memory winners;
        uint8[4] memory numbers = [20, 10, 4, 1];
        for (uint8 q = 0; q < 4; q++) {
            winners = randTraitTicket(winningTraits[q], numbers[q]);
            for (uint8 i = 0; i < numbers[q]; i++) {
                addClaimableUSDC(winners[i], jackpot / numbers[q]);
            }
        }
        dailyJackpotCounter += 1;
        if (dailyJackpotCounter == 25) {
            endGame();
        }
        else {dailyJackpotTime = uint32(block.timestamp);}
        for (uint8 i = 0; i < 80; i++) {dailyPurgeCount[i] = 0;}
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
        for (uint8 q = 0; q < 4; q++) {
            max = 0;
            for (uint8 i = 0; i < 3; i++) {
                uint8 trait = q * 3 + i;
                if (totalCoinBurn[traitIndices[trait]] >= max) {
                    max = totalCoinBurn[traitIndices[trait]];
                    winningTrait[q] = traitIndices[trait] + 64 * q;
                }
            }
        }
        for (uint8 q = 0; q < 4; q++) {
            address luckbox = PurgedCoinInterface(purgedCoinContract).getTopLuckbox(randTraitTicket(winningTrait[q], 5));
            if (PurgedCoinInterface(purgedCoinContract).getPlayerLuckbox(msg.sender) != 0) {
                PurgedCoinInterface(purgedCoinContract).mintFromPurge(luckbox, dailyCoinJackpot);
                emit CoinPaid(luckbox, dailyCoinJackpot, true);
            }
        }
    }

    function getWinningTraits() private view returns (uint8[4] memory) {
        uint8[4] memory winningTraits;
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, "2")));
        uint8[3] memory start = [0, 8, 16];
        uint8[3] memory end = [8, 16, 80];
        for (uint8 q = 0; q < 3; q++) {
            uint32 maxCount = dailyPurgeCount[start[q]];
            uint8 winner = start[q];
            for (uint8 i = start[q] + 1; i < end[q]; i++) {
                if (dailyPurgeCount[i] > maxCount) {
                    maxCount = dailyPurgeCount[i];
                    winner = i;
                } else if (dailyPurgeCount[i] == maxCount) {
                    if ((randomNum >> i & 0x1) == 1) {
                        winner = i;
                    }
                }
            }
            if (q == 0) {
                winningTraits[0] = uint8((randomNum >> 8) & 0x7) * 8 + winner;
            } else if (q == 1) {
                winningTraits[1] = winner * 8 + uint8((randomNum >> 16) & 0x7) + 64;
            } else if (q == 2) {
                winningTraits[2] = uint8((randomNum >> 24) & 0x3F) + 192;
            }     
        }
        winningTraits[3] = uint8((randomNum >> 32) & 0x3F);
        return winningTraits;
    }

    function randTraitTicket(uint8 trait, uint8 amount) private returns (address[] memory) {
        address[] memory selectedTickets = new address[](amount);
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao,trait))); 
        for (uint8 i = 0; i < amount; i++) {
            uint32 rand = uint32(randomNum << i * 16);
            uint32 randomIndex = uint32(rand % traitPurgeTicket[trait].length);
            selectedTickets[i] = traitPurgeTicket[trait][randomIndex];
            emit RandomTicket(trait, randomIndex, selectedTickets[i]);
        }
        return selectedTickets;
    }

    function requireThousandMax(uint32 _number) pure private {
        require(_number > 0 && _number <= 1000, "Number of mints must be between 1 and 1000");
    }

// Pays $PURGED to referrers when their referrals mint tokens.
    function payReferrer(uint32 _number, string calldata referralCode) private{
        address shill;
        shill = PurgedCoinInterface(purgedCoinContract).getReferralCodeOwner(referralCode);
        if (shill == address(0)) {
            shill = _owner;
        }
        PurgedCoinInterface(purgedCoinContract).mintFromPurge(shill, _number * cost * million / 20);
        emit Referred(referralCode, shill, _number, msg.sender);
    }

// Anti-hack funtion. The traits generated by minting will not correspond to the token minted.
    function setOffset(uint32 _offset) external onlyTrusted{
        require(offset == 0, "Offset already set");
        require(_offset > 0 && _offset < maxTokens, "Offset out of range");
        offset = _offset;
    }
    
    function realTraitsFromTokenId(uint32 _tokenId) private view returns(uint32){
        if (offset != 0){
            if (_tokenId < maxTokens){
                if (_tokenId + offset <= totalMinted) return(_tokenId + offset);
                else return(_tokenId + offset - totalMinted);
            }
        }
        return(_tokenId);
    }

    event MintAndPurge(uint32 tokenId, uint24 tokenTraits, address from);
    event MiniPurge(uint8 trait, address player);
    event TokenMinted(uint32 tokenId, uint24 tokenTraits, address from);
    event Referred(string referralCode, address shill, uint32 number, address from);
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

    function addTrustedAddress(address _address) external onlyTrusted {
        trustedAddresses[_address] = true;
    }

    function removeTrustedAddress(address _address) external onlyTrusted {
        require(_address != _owner, "Cannot remove owner");
        trustedAddresses[_address] = false;
    }

    receive() external payable {}

    function withdrawEth() external onlyTrusted {
        (bool success, ) = payable(_owner).call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    // Winnings must be claimed by 6 months after the game ends.
    function withdrawAbandoned() external onlyTrusted {
        require(gameOver == true);
        require(block.timestamp > gameEndTime + 180 days);
        IERC20(usdcTokenAddress).transfer(_owner, IERC20(usdcTokenAddress).balanceOf(address(this)));
    }   

    function claimWinnings() external {
        address player = msg.sender;
        uint256 winnings = claimableWinnings[player];
        require (winnings > 0, "No winnings to claim");  
        claimableWinnings[player] = 0;
        require(IERC20(usdcTokenAddress).transfer(player, winnings), "USDC transfer failed");
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