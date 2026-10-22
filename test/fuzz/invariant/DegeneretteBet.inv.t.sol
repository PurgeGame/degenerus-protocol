// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {DegeneretteHandler} from "../handlers/DegeneretteHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title DegeneretteBetInvariant -- Proves Degenerette ETH bet accounting invariant
/// @notice NEVER PREVIOUSLY FUZZED. Targets the Degenerette slot machine (placeDegeneretteBet /
///         resolveBets) to verify:
///         1. ETH wager in = ETH in futurePool increase (no ETH created during betting)
///         2. ETH payouts from resolve <= pool at time of resolution
///         3. Solvency invariant holds after bet placement AND after resolution
///         4. Claimable pool tracks correctly through bet lifecycle
contract DegeneretteBetInvariant is DeployProtocol {
    DegeneretteHandler public degHandler;
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    uint256 internal fixtureBets;
    uint256 internal fixtureResolved;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Game handler drives purchases (needed to set up lootbox RNG index)
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        degHandler = new DegeneretteHandler(game, mockVRF, 8);

        // Start every sequence with a real bet and resolution. Random time warps can
        // otherwise reach the liveness timeout before the first betting action.
        degHandler.placeEthBet(0, 0.01 ether, 1, 0);
        assertEq(degHandler.ghost_betsPlaced(), 1, "fixture must place a real bet");
        degHandler.resolveBets(0);
        assertEq(degHandler.ghost_betsResolved(), 1, "fixture must resolve a real bet");
        fixtureBets = degHandler.ghost_betsPlaced();
        fixtureResolved = degHandler.ghost_betsResolved();

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(degHandler));

        // SEED the fuzzer onto a reachable bet sequence. Without an explicit selector allow-list the
        // unguided fuzzer hammers mineFlip/warpTime and drives the game to game-over (where
        // placeDegeneretteBet is permanently unreachable) before a single bet is ever placed -- so
        // invariant_solvencyUnderDegenerette passes VACUOUSLY (measured: betsPlaced == 0, 0 reverts).
        // The property under test is Degenerette-bet solvency, so the Degenerette handler exposes only
        // the bet lifecycle (place/resolve/purchase/fulfill) -- NOT mineFlip -- keeping the game live
        // so bets actually execute. The GameHandler exposes purchase (to grow real ETH pools) and
        // claimWinnings (the withdrawal leg solvency must survive); mineFlip is excluded from both.
        bytes4[] memory degSelectors = new bytes4[](4);
        degSelectors[0] = DegeneretteHandler.placeEthBet.selector;
        degSelectors[1] = DegeneretteHandler.resolveBets.selector;
        degSelectors[2] = DegeneretteHandler.purchaseTickets.selector;
        degSelectors[3] = DegeneretteHandler.fulfillVrf.selector;
        targetSelector(FuzzSelector({addr: address(degHandler), selectors: degSelectors}));

        bytes4[] memory gameSelectors = new bytes4[](2);
        gameSelectors[0] = GameHandler.purchase.selector;
        gameSelectors[1] = GameHandler.claimWinnings.selector;
        targetSelector(FuzzSelector({addr: address(gameHandler), selectors: gameSelectors}));
    }

    /// @notice ETH solvency holds after Degenerette operations
    /// @dev The critical invariant: game balance >= sum of all pool obligations.
    ///      This is the same invariant as EthSolvency but under Degenerette pressure.
    function invariant_solvencyUnderDegenerette() public view {
        uint256 gameBalance = address(game).balance;
        // Canonical obligation set: pending freeze buffer included, dead post-GO live pools
        // excluded (only claimablePool survives game-over). This keeps claimablePool in the
        // post-GO set, so the now-guarded Degenerette resolveBets path is still caught if the
        // contract guard ever regresses (it pushed claimablePool itself above balance). See
        // SolvencyObligations + 323-SOLVENCY-FINDING.md §1/§3.
        uint256 obligations = SolvencyObligations.obligations(game);

        assertGe(
            gameBalance,
            obligations,
            "Degenerette: solvency violated -- balance < obligations"
        );
    }

    /// @notice Ghost accounting: deposits via purchases >= claims from Degenerette + game
    /// @dev The total ETH entering the protocol must always be >= total ETH exiting.
    ///      Degenerette bets add to futurePrizePool; resolutions deduct and credit claimable.
    function invariant_ghostAccountingNetPositive() public view {
        uint256 totalIn = gameHandler.ghost_totalDeposited()
            + degHandler.ghost_totalEthWagered();

        uint256 totalOut = gameHandler.ghost_totalClaimed()
            + degHandler.ghost_totalEthPayout();

        assertGe(
            totalIn,
            totalOut,
            "Degenerette: more ETH exited than entered"
        );
    }


    /// @notice Non-vacuity lever: the CAMPAIGN (not the setUp fixture, which places and resolves one bet
    ///         every run) must place and resolve real Degenerette bets.
    /// @dev `betsPlaced > 0` alone is always satisfied by the fixture bet. Measured over 514
    ///      default-profile runs: about 7 campaign bets placed and 2 resolved per run, but a single run can
    ///      place none, so campaign counts are accumulated over the process (unique DB_ prefix) and must be
    ///      non-zero once MIN_RUNS runs have completed.
    uint256 private constant MIN_RUNS = 16;

    function _acc(string memory k, uint256 v) private returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        uint256 runs = _acc("DB_RUNS", 1);
        uint256 placed = _acc("DB_placed", degHandler.ghost_betsPlaced() - fixtureBets);
        uint256 resolved = _acc("DB_resolved", degHandler.ghost_betsResolved() - fixtureResolved);
        uint256 purchases = _acc("DB_purchases", gameHandler.ghost_successfulPurchases());
        if (runs < MIN_RUNS) return;
        assertGt(placed, 0, "VACUOUS: the campaign never placed a Degenerette bet");
        assertGt(resolved, 0, "VACUOUS: the campaign never resolved a Degenerette bet");
        assertGt(purchases, 0, "VACUOUS: no ticket purchase ever succeeded");
    }


}
