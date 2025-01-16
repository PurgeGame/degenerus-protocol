
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Purged is ERC20, Ownable
{
    constructor() ERC20("Purged Coin", "PURGED") Ownable(msg.sender){}

    address[10] PurgeGameContract;
    uint8 public percentOfDollar = 100;
    uint256 public presaleAmount = 0;
    uint256 constant private million = 1000000;
    uint256 public bank = million * million;
    uint256 public totalPresaleSold = 0;
    address public usdcTokenAddress = 0xe4C7fBB0a626ed208021ccabA6Be1566905E2dFc;
    mapping(address => uint256) public presalePurchases;

    
    modifier onlyPurgeGameContract() {
        bool isAuthorized = false;
        for (uint8 i = 0; i < 10; i++) {
            if (PurgeGameContract[i] == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Only Purge Game contract can call this function");
        _;
    }

    function setPurgeGameAddress(address _purgeGameContract, uint8 season) external onlyOwner{
       PurgeGameContract[season] = _purgeGameContract;
    }

    function mintFromPurge(address yourAddress, uint256 _amount) external onlyPurgeGameContract{
        if (yourAddress == owner()){
            bank += _amount;
        } else{
            _mint(yourAddress, _amount);
        }
    }

    function burnToMint(address yourAddress, uint256 _amount) external onlyPurgeGameContract{
        _burn(yourAddress,_amount);
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
        amount *= million;
        require(amount > 0, "Amount must be greater than zero");
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
        require(usdc.transfer(owner(), usdc.balanceOf(address(this))), "USDC transfer failed");
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
