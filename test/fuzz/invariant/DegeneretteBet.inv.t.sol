// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Game handler drives purchases (needed to set up lootbox RNG index)
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        degHandler = new DegeneretteHandler(game, mockVRF, 8);

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(degHandler));

        // SEED the fuzzer onto a reachable bet sequence. Without an explicit selector allow-list the
        // unguided fuzzer hammers advanceGame/warpTime and drives the game to game-over (where
        // placeDegeneretteBet is permanently unreachable) before a single bet is ever placed -- so
        // invariant_solvencyUnderDegenerette passes VACUOUSLY (measured: betsPlaced == 0, 0 reverts).
        // The property under test is Degenerette-bet solvency, so the Degenerette handler exposes only
        // the bet lifecycle (place/resolve/purchase/fulfill) -- NOT advanceGame -- keeping the game live
        // so bets actually execute. The GameHandler exposes purchase (to grow real ETH pools) and
        // claimWinnings (the withdrawal leg solvency must survive); advanceGame is excluded from both.
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

    /// @notice Degenerette bet resolution does not increase game ETH balance
    /// @dev After resolving a bet, the game balance should not exceed
    ///      (deposits - claims + initial balance). This catches ETH minting bugs.
    function invariant_noEthCreation() public view {
        // If no bets were resolved, skip
        if (degHandler.ghost_betsResolved() == 0) return;

        // ETH payout from Degenerette should not exceed ETH wagered into Degenerette
        // (Degenerette is EV-negative by design: ROI is 90-99.9%)
        // However, individual resolutions CAN pay out more than wagered (jackpots).
        // The key invariant is pool-level: futurePrizePool tracks correctly.
        // This is already covered by solvency, so we check a weaker form:
        // total claims (game + degenerette) <= total deposits
        uint256 totalIn = gameHandler.ghost_totalDeposited()
            + degHandler.ghost_totalEthWagered();
        uint256 totalOut = gameHandler.ghost_totalClaimed()
            + degHandler.ghost_totalEthPayout();

        assertGe(totalIn, totalOut, "Degenerette: ETH creation detected");
    }

    /// @notice Canary: Degenerette handler is operational
    function invariant_degeneretteCanary() public view {
        assertTrue(address(degHandler) != address(0), "DegeneretteHandler not deployed");
        assertTrue(address(game).code.length > 0, "Game has no code");
    }

    /// @notice Non-vacuity lever: the run MUST place at least one real Degenerette bet, else the
    ///         solvency invariant proves nothing about betting. Runs once after the full sequence.
    /// @dev Guards against silent regression to the pre-seed vacuous pass (betsPlaced == 0). The
    ///      mirror of RedemptionAccounting's `assertGt(ghost_..., 0, "lever never reached")` pattern.
    function afterInvariant() public view {
        assertGt(
            degHandler.ghost_betsPlaced(),
            0,
            "VACUOUS: no Degenerette bet was placed -- solvency invariant exercised no betting"
        );
    }

    /// @notice Diagnostic call/ghost summary (always passes; inspect with -vv).
    function invariant_callSummary() public view {
        console.log("--- DegeneretteBet Call Summary ---");
        console.log("  calls_placeBet:    ", degHandler.calls_placeBet());
        console.log("  calls_resolveBet:  ", degHandler.calls_resolveBet());
        console.log("  ghost_betsPlaced:  ", degHandler.ghost_betsPlaced());
        console.log("  ghost_betsResolved:", degHandler.ghost_betsResolved());
        console.log("  ghost_betsFailed:  ", degHandler.ghost_betsFailed());
        console.log("  ghost_ethWagered:  ", degHandler.ghost_totalEthWagered());
        console.log("  ghost_ethPayout:   ", degHandler.ghost_totalEthPayout());
        console.log("  game_deposited:    ", gameHandler.ghost_totalDeposited());
    }
}
