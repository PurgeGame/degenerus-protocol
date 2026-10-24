// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CoinflipCore, IFLIP, IWWXRP, IDegenerusRecordBounty} from "./modules/CoinflipCore.sol";
import {DegenerusQuests} from "./DegenerusQuests.sol";
import {DegenerusAffiliate} from "./DegenerusAffiliate.sol";

/// @notice Combined Coinflip, Quests and Affiliate shell.
contract Coinflip is DegenerusQuests, DegenerusAffiliate, CoinflipCore {
    constructor(address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
        address[] memory players, bytes32[] memory refs) DegenerusAffiliate(owners, codes, kicks, players, refs) {}

    function _coinflipQuest(uint32 id, uint256 amount) internal override
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        return _handleFlip(id, amount);
    }

    // These bridges are statically bound and absent from the public ABI. Each
    // caller supplies the original credited wallet, independent of msg.sender.
    function _questGameDay() internal view override returns (uint24) { return requestedDailyIdx; }

    function _questCreditFlip(uint32 id, uint256 amount) internal override {
        _creditFlip(id, amount);
    }

    function _affiliateQuestReward(uint32 id, uint256 amount) internal override returns (uint256 reward) {
        (reward,,,) = _handleAffiliate(id, amount);
    }

    function _affiliateCreditFlip(uint32 id, uint256 amount) internal override {
        _creditFlip(id, amount);
    }

    function _affiliateCreditFlipPair(uint32 a, uint256 amountA, uint32 b, uint256 amountB) internal override {
        _creditFlip(a, amountA);
        _creditFlip(b, amountB);
    }
}
