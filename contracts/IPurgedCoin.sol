// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface PurgedCoinInterface {
    function mintInGame(address yourAddress, uint256 _amount) external;
    function burnInGame(address yourAddress, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function payTopLuckbox(address[] memory players, uint256 dailyCoinJackpot) external view returns (address);
    function dailyCoinBurn() external view returns(uint256);
    function getSeasonCoinBurn(uint8[] calldata traits) external view returns (uint256[] memory);
    function resetDailyCoinBurn() external;
    function resetSeasonCoinBurn() external;
    function payReferrer(uint256 amount, string calldata _referralCode, address sender) external;
}