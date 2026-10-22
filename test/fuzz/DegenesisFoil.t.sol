// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol, DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {FoilGenerationFreshRequest} from "./FoilResolveDayAlwaysTomorrow.t.sol";
import {FoilPackEV} from "../economics/FoilPackEV.t.sol";
import {FoilSnapPayout} from "../economics/FoilSnapPayout.t.sol";
import {FoilClaimBatch} from "../economics/FoilClaimBatch.t.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

// Existing foil suites, unchanged, re-run on the Degenesis timeline (deploy on day index 1, so
// their relative days fall in the Degenesis week). Check 20: foil code is unchanged and packs
// bought during Degenesis generate and pay their gold as before.

contract DegenesisFoilGenerationFreshRequest is FoilGenerationFreshRequest, DegenesisDeployProtocol {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisDeployProtocol) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

contract DegenesisFoilPackEV is FoilPackEV, DegenesisDeployProtocol {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisDeployProtocol) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

contract DegenesisFoilSnapPayout is FoilSnapPayout, DegenesisDeployProtocol {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisDeployProtocol) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev The day-1 deploy draws a different trajectory; this series surfaces a FLIP-lane match.
    function _wordSeries() internal pure override returns (uint256) {
        return 31;
    }
}

contract DegenesisFoilClaimBatch is FoilClaimBatch, DegenesisDeployProtocol {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisDeployProtocol) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

/// @title DegenesisFoilMatch -- no foil match before the first post-Degenesis draw (check 20)
/// @notice Degenesis days skip the daily draw, so they record no winning traits and no match claim
///         exists for them; the first draw, and with it the first claimable day, is day 9.
contract DegenesisFoilMatch is DegenesisFixture {
    bytes32 internal constant WINNING_TRAITS_SIG = keccak256("DailyWinningTraits(uint24,uint32)");

    function test_NoFoilMatchBeforeFirstPostDegenesisDraw() public {
        address alice = _player("alice", 10 ether);
        uint32 id = game.walletIdOf(alice);
        _drain();
        uint256 draws;
        for (uint256 d = 2; d <= 8; ++d) {
            _warpDay(d, 1 hours);
            if (d == 2) {
                // A pack bought on Degenesis day 1 (one per cycle) generates during the week.
                vm.prank(alice);
                game.purchase{value: 0.1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
            }
            vm.recordLogs();
            _drain();
            draws += _countSig(vm.getRecordedLogs(), WINNING_TRAITS_SIG);
            for (uint256 day = 2; day <= d; ++day) {
                for (uint256 t; t < 4; ++t) {
                    vm.expectRevert();
                    game.claimFoilMatch(id, day, t);
                }
            }
        }
        assertEq(draws, 0, "no daily draw on any Degenesis day");

        // Day 9 (next pool below the target): the normal level-0 daily draw records traits.
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        vm.recordLogs();
        _drain();
        assertEq(_countSig(vm.getRecordedLogs(), WINNING_TRAITS_SIG), 1, "the first draw is day 9's");
    }
}
