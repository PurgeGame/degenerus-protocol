// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {FlipSupplyProbe} from "../handlers/FlipSupplyProbe.sol";

/// @title CoinSupplyInvariant -- Proves FLIP supply conservation (FUZZ-02 / COIN-01)
/// @notice The old `invariant_supplyConsistency` compared totalSupply()+vaultMintAllowance() to
///         supplyIncUncirculated(). Both sides read the SAME two Supply-struct fields
///         (supplyIncUncirculated() is DEFINED as totalSupply + vaultAllowance in FLIP.sol), so the
///         assertion was `x == x` -- structurally unfailable and testing nothing.
///
///         The real conservation property is now proven by FlipSupplyProbe, the sole fuzz target.
///         On every action it reconstructs FLIP's two supply scalars INDEPENDENTLY from the emitted
///         event stream (zero-address Transfers -> totalSupply moves; VaultEscrowRecorded /
///         VaultAllowanceSpent -> vaultAllowance moves) and cross-checks them against FLIP's storage
///         getters. This catches any escaped mint/burn: a `_supply` field mutated without the
///         matching event (or with a mismatched amount) breaks the identity. There is no supply
///         floor: FLIP deploys at zero and the initial emission arrives later as Coinflip seed
///         stakes, all captured by the probe's per-action accounting.
contract CoinSupplyInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    WhaleHandler public whaleHandler;
    FlipSupplyProbe public probe;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Underlying drivers -- NOT targeted directly; the probe forwards to them so that every
        // fuzzer step ends inside the probe's per-action supply reconciliation.
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        whaleHandler = new WhaleHandler(game, 5);

        probe = new FlipSupplyProbe(coin, gameHandler, vrfHandler, whaleHandler);

        targetContract(address(probe));
    }

    /// @notice REAL conservation: FLIP's stored circulating supply equals its initial supply plus
    ///         every event-recorded mint minus every event-recorded burn.
    /// @dev Underflow-free form of `totalSupply == initialTotal + ghostMinted - ghostBurned`.
    ///      Independent of holder enumeration: it reconstructs the scalar from the mint/burn event
    ///      stream, not from a sum of balances. Falsifiable -- an escaped mint (totalSupply bumped
    ///      with no Transfer(from==0)) or an escaped burn makes the two sides diverge.
    function invariant_flipCirculatingConserved() public view {
        assertEq(
            coin.totalSupply() + probe.ghostBurned(),
            probe.initialTotal() + probe.ghostMinted(),
            "FLIP: circulating supply diverged from mint/burn event stream"
        );
    }

    /// @notice REAL conservation: FLIP's stored virtual vault allowance equals its initial value
    ///         plus every escrow credit minus every allowance spend.
    /// @dev Underflow-free form of `vaultAllowance == initialVault + ghostEscrowed - ghostSpent`.
    ///      Catches the vault-side leg specifically: transfer->VAULT, vaultEscrow, vaultMintTo, and
    ///      the gameover tombstone flood all move vaultAllowance, each via its own event.
    function invariant_flipVaultAllowanceConserved() public view {
        assertEq(
            coin.vaultMintAllowance() + probe.ghostSpent(),
            probe.initialVault() + probe.ghostEscrowed(),
            "FLIP: vault allowance diverged from escrow/spend event stream"
        );
    }

    /// @notice Per-action falsification counters: no single action's storage supply delta ever
    ///         disagreed with its event-derived delta.
    /// @dev The finest-grained teeth -- an inconsistent mutation is caught in the action that causes
    ///      it, even if a later action would coincidentally rebalance the running totals.
    function invariant_flipSupplyNoMismatch() public view {
        assertEq(
            probe.ghostTotalSupplyMismatch(),
            0,
            "FLIP: a totalSupply mutation did not match its emitted event"
        );
        assertEq(
            probe.ghostVaultAllowanceMismatch(),
            0,
            "FLIP: a vaultAllowance mutation did not match its emitted event"
        );
    }

    /// @notice Struct-consistency sanity: supplyIncUncirculated() is the sum of the two supply
    ///         fields. Cheap, and (unlike before) NOT the suite's only supply check.
    function invariant_supplyConsistency() public view {
        assertEq(
            coin.totalSupply() + coin.vaultMintAllowance(),
            coin.supplyIncUncirculated(),
            "FLIP: totalSupply + vaultAllowance != supplyIncUncirculated"
        );
    }

    /// @notice Canary: coin contract is deployed and functional.
    function invariant_coinCanary() public view {
        assertTrue(address(coin) != address(0), "Coin not deployed");
        assertTrue(address(coin).code.length > 0, "Coin has no code");
    }
}
