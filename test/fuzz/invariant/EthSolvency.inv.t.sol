// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title EthSolvencyInvariant -- Proves ETH solvency holds across randomized call sequences
/// @notice The primary invariant: the game contract always holds enough ETH to cover all pool
///         obligations. Ghost variables track ETH flows for reconciliation.
contract EthSolvencyInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    WhaleHandler public whaleHandler;
    uint256 private startingCustody;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Create handlers
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        whaleHandler = new WhaleHandler(game, 5);
        startingCustody = _protocolCustody();

        // Register as target contracts for the fuzzer
        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(whaleHandler));
    }

    /// @notice ETH solvency: game balance >= sum of all pool obligations
    /// @dev This is THE critical invariant for any ETH-holding protocol.
    ///      If this fails, the protocol is insolvent -- players cannot claim their winnings.
    function invariant_ethSolvency() public view {
        uint256 gameBalance = address(game).balance + mockStETH.balanceOf(address(game));
        // Canonical obligation set (freeze-window pending buffer included; dead post-game-over
        // live pools excluded) -- see SolvencyObligations. Still a real `balance < obligations` test.
        uint256 obligations = SolvencyObligations.obligations(game);

        assertGe(
            gameBalance,
            obligations,
            "ETH solvency violated: balance < obligations"
        );
    }

    /// @notice Ghost accounting: total deposited across all handlers >= total claimed
    /// @dev Catches cases where more ETH exits the protocol than enters.
    function invariant_ghostAccountingDepositsGeClaims() public view {
        uint256 totalDeposited = gameHandler.ghost_totalDeposited()
            + whaleHandler.ghost_whalePassDeposited()
            + whaleHandler.ghost_lazyPassDeposited()
            + whaleHandler.ghost_deityPassDeposited();

        assertGe(
            totalDeposited,
            gameHandler.ghost_totalClaimed(),
            "Ghost accounting: more ETH claimed than deposited"
        );
    }

    /// @notice Canary: game contract is properly deployed
    function invariant_canary() public view {
        assertTrue(address(game) != address(0), "Game not deployed");
        assertTrue(address(game).code.length > 0, "Game has no code");
    }

    /// @notice Every deposited wei remains in protocol custody or has been paid to an actor.
    /// @dev These handlers introduce no donations, rebases, or externally funded stETH. Purchases
    ///      can move backing between the Game, Vault, sDGNRS and GNRUS, and auto-staking replaces
    ///      ETH with mock stETH 1:1. Track all four sinks rather than only the Game. The claim
    ///      handler records native ETH payouts; its actors' stETH holdings cover the other leg.
    function invariant_balanceReconciliation() public view {
        (uint256 accounted, uint256 expected) = _reconciliation();
        assertEq(accounted, expected, "Custody plus paid assets must equal starting custody plus deposits");
    }

    function _protocolCustody() private view returns (uint256 total) {
        address[4] memory sinks = [address(game), address(vault), address(sdgnrs), address(gnrus)];
        for (uint256 i; i < sinks.length; ++i) {
            total += sinks[i].balance + mockStETH.balanceOf(sinks[i]);
        }
    }

    function _reconciliation() private view returns (uint256 accounted, uint256 expected) {
        accounted = _protocolCustody() + gameHandler.ghost_totalClaimed();
        for (uint256 i; i < 10; ++i) {
            accounted += mockStETH.balanceOf(gameHandler.actors(i));
        }
        expected = startingCustody + gameHandler.ghost_totalDeposited()
            + whaleHandler.ghost_whalePassDeposited()
            + whaleHandler.ghost_lazyPassDeposited()
            + whaleHandler.ghost_deityPassDeposited();
    }

    /// @notice A balance leak must fail reconciliation even while every pool remains solvent.
    function test_reconciliationDetectsMissingWei() public {
        gameHandler.purchase(0, 400, 0);
        assertGt(gameHandler.ghost_totalDeposited(), 0, "fixture: a real purchase must land");
        invariant_balanceReconciliation();
        uint256 before = address(game).balance;
        vm.deal(address(game), before - 1);
        (uint256 accounted, uint256 expected) = _reconciliation();
        assertEq(accounted + 1, expected, "the oracle must see the missing wei");
        vm.deal(address(game), before);
        invariant_balanceReconciliation();
    }

    /// @notice Exercise real purchases and settlement before checking conservation.
    function test_reconciliationAcrossPurchasesAndSettlement() public {
        gameHandler.purchase(0, 400, 0.1 ether);
        whaleHandler.purchaseWhalePass(0, 1);
        whaleHandler.purchaseLazyPass(1);
        whaleHandler.purchaseDeityPass(2, 0);
        assertGt(gameHandler.ghost_totalDeposited(), 0, "fixture: ticket/box purchase");
        assertGt(whaleHandler.ghost_whalePassDeposited(), 0, "fixture: whale purchase");
        assertGt(whaleHandler.ghost_lazyPassDeposited(), 0, "fixture: lazy purchase");
        assertGt(whaleHandler.ghost_deityPassDeposited(), 0, "fixture: deity purchase");
        invariant_balanceReconciliation();
        for (uint256 day; day < 3; ++day) {
            vm.warp(block.timestamp + 1 days);
            for (uint256 step; step < 20; ++step) {
                gameHandler.advanceGame(0);
                vrfHandler.fulfillVrf(uint256(keccak256(abi.encode(day, step))));
                invariant_balanceReconciliation();
            }
        }
        assertGt(vrfHandler.ghost_vrfFulfillments(), 0, "fixture: VRF must settle");
        gameHandler.claimWinnings(0);
        invariant_balanceReconciliation();
    }
}
