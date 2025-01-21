
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Purged is ERC20 {
    
    uint8 public percentOfDollar = 100;
    address private _owner;
    address private constant usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    
    uint256 public presaleAmount = 0;
    uint256 constant private million = 1000000;
    uint256 public bank = million * million;
    uint256 public totalPresaleSold = 0;
    uint256 public dailyCoinBurn;

    uint256[256] private totalCoinBurn;
    
    mapping(address => bool) private contractAddresses;
    mapping(address => uint256) public presalePurchases;
    mapping(string => address) private referralCode;
    mapping(address => uint256) public playerLuckbox;

    constructor() ERC20("Purged Coin", "PURGED") {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }
    
    modifier onlyPurgeGameContract() {
        require(contractAddresses[msg.sender], "Caller is not a Purge Game contract");
        _;
    }

    function resetDailyCoinBurn() external onlyPurgeGameContract{
        dailyCoinBurn = 0;
    }

    function resetSeasonCoinBurn() external onlyPurgeGameContract{
        for (uint8 i = 0; i < 256; i++) {
            totalCoinBurn[i] = 0;
        }
    }

    function getSeasonCoinBurn(uint8[] calldata traits) external view returns (uint256[] memory) {
        uint256[] memory burnCounts = new uint256[](traits.length);
        for (uint8 i = 0; i < traits.length; i++) {
            burnCounts[i] = totalCoinBurn[traits[i]];
        }
        return burnCounts;
    }

    function getPlayerLuckbox(address player) external view returns(uint256){
        return(playerLuckbox[player]);
    }

    function addToPlayerLuckbox(address player, uint256 amount) external onlyPurgeGameContract{
        playerLuckbox[player] += amount;
    }

    function payTopLuckbox(address[] memory winners, uint256 dailyCoinJackpot) external onlyPurgeGameContract{
        address topLuckbox = getTopLuckbox(winners);
        if (topLuckbox != address(0)) {
            _mint(topLuckbox, dailyCoinJackpot);
        } else {
            emit LuckboxFail(winners);
        }
    }

    function getTopLuckbox(address[] memory players) public view returns (address) {
        uint256 highestLuckboxValue = 0;
        address topLuckbox;
        for (uint8 i = 0; i < players.length; i++) {
            address player = players[i];
            uint256 luckboxValue = playerLuckbox[player];
            if (luckboxValue > highestLuckboxValue) {
                highestLuckboxValue = luckboxValue;
                topLuckbox = player;
            }
        }
        if(playerLuckbox[topLuckbox] == 0){
            topLuckbox = address(0);
        }
        return topLuckbox;
    }
    
// Allows users to create a referral code string that will pay them $PURGED when their referrals mint tokens.
    function createReferralCode(string calldata _referralCode) external {
        bytes memory referralCodeBytes = bytes(_referralCode);
        uint256 referralCodeLength = referralCodeBytes.length;
        require(
            referralCodeLength != 0 && referralCodeLength <= 40,
            "Invalid referral code length"
        );
        require(referralCode[_referralCode] == address(0), "Referral code is taken");
        referralCode[_referralCode] = msg.sender;
    }

    function getReferralCodeOwner(string calldata _referralCode) external view returns(address){
        return(referralCode[_referralCode]);
    }

    function payReferrer(uint256 amount, string calldata _referralCode, address sender) external onlyPurgeGameContract{
        address shill;
        shill = referralCode[_referralCode];
        if (shill == address(0)) {
            bank += amount;
        } else{
            _mint(shill, amount);
            emit Referred(_referralCode, shill, amount, sender);
        }
    }

    function addContractAddress(address _purgeGameContract) external onlyOwner{
       contractAddresses[_purgeGameContract] = true;
    }

    function removeContractAddress(address _purgeGameContract) external onlyOwner{
       contractAddresses[_purgeGameContract] = false;
    }

    function mintInGame(address yourAddress, uint256 _amount) external onlyPurgeGameContract{
        if (yourAddress == _owner){
            bank += _amount;
        } else{
            _mint(yourAddress, _amount);
        }
    }

    function burnInGame(address yourAddress, uint256 _amount) external onlyPurgeGameContract{
        _burn(yourAddress,_amount);
    }

    function luckyCoinBurn(uint256 amount, uint8 trait) external {
        require(amount > 5 * million && amount <= balanceOf(msg.sender), "Invalid amount");
        require(trait >= 0 && trait <= 255, "trait ID must be between 0 and 255");
        _burn(msg.sender, amount);
        totalCoinBurn[trait] += amount;
        dailyCoinBurn += amount;
        playerLuckbox[msg.sender] += amount;
        emit CoinBurned(msg.sender, trait, amount);
    }

    function airdrop(address[] calldata to, uint256[] calldata _amount) external onlyOwner {
        require (to.length == _amount.length);
        for (uint16 c = 0; c < to.length;c++){
            uint256 amount = _amount[c];
            require(amount <= bank);
            bank -= amount;
            _mint(to[c], amount);
        }
    }

    function presale(uint256 amount) external {
        require(amount > 5, "Amount must be greater than 5 coins");
        amount *= million;
        uint256 totalCost = amount * percentOfDollar / 100;
        require(totalPresaleSold + amount <= presaleAmount, "Exceeds maximum presale amount");
        require(amount <= bank, "Not enough coins in the bank");
        require(presalePurchases[msg.sender] + amount <= 1000 * million, "1k max");
        IERC20 usdc = IERC20(usdcTokenAddress);
        require(usdc.transferFrom(msg.sender, address(this), totalCost), "USDC transfer failed");
        totalPresaleSold += amount;
        presalePurchases[msg.sender] += amount;
        bank -= amount;
        _mint(msg.sender, amount);
    }

    function setPresale(uint256 _amount, uint8 _percentOfDollar) external onlyOwner {
        percentOfDollar = _percentOfDollar;
        presaleAmount = _amount * million;
    }

    function withdrawUSDC() external onlyOwner {
        IERC20 usdc = IERC20(usdcTokenAddress);
        require(usdc.transfer(_owner, usdc.balanceOf(address(this))), "USDC transfer failed");
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
    event CoinBurned(address from, uint32 tokenId, uint256 amount);
    event Referred(string referralCode, address shill, uint256 amount, address from);
    event LuckboxFail(address[] players);
    
}
