// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {NestedSettlementFixture} from "./AdvanceNestedSettlementGas.t.sol";

contract FullAwardPoolSeeder is DegenerusGame {
    function setPreviousPool(uint24 level, uint256 amount) external {
        levelPrizePool[level] = amount;
    }
}

/// @notice Split-stage stress through the mineFlip router: fresh VRF, 365 days of failed vault
///         settlement and a pending redemption in the word-apply transaction; the jackpot battle at
///         its 500-award cap in its own transactions; the golden grand and 49 ETH awards in the daily
///         transaction; then the 120-ticket leg. Each transaction is measured alone and held to its
///         limit. Run with FOUNDRY_ISOLATE=true.
contract AdvanceNestedFullCompositionGas is NestedSettlementFixture {
    /// @dev 40,000 ETH at 0.04 ETH is 5,000,000 FLIP of Added: the 500-award cap.
    uint256 internal constant PREV_POOL_AWARD_CAP = 40_000 ether;

    function _sufficient() internal pure override returns (bool) {
        return false;
    }

    function _comps() internal pure override returns (bool) {
        return true;
    }

    function _extras() internal pure override returns (bool) {
        return true;
    }

    function _router() internal pure override returns (bool) {
        return true;
    }

    /// @dev Records the award-cap pool before the real request freezes the battle's Added.
    function _beforeRequest() internal override {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(FullAwardPoolSeeder).runtimeCode);
        FullAwardPoolSeeder(payable(address(game))).setPreviousPool(LVL, PREV_POOL_AWARD_CAP);
        vm.etch(address(game), realCode);
    }

    function test_EachStageWithAwardCapBattleFitsItsLimit() public {
        _checkNestedSettlement();
        (uint64 slot,,,) = IJackpotBattle(address(crapsBattle)).jackpotProgress();
        (CrapsBattleStorage.JackpotRound memory round,,) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.drawnUnits, 500, "the battle drew its full award cap");
    }
}
