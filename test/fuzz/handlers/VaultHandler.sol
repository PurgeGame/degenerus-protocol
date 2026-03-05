// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title VaultHandler -- Handler for vault deposit/withdraw operations in invariant tests
/// @notice Wraps burnCoin/burnEth with bounded inputs, tracks share math consistency.
/// @dev Targets the NEVER-FUZZED vault share math: shares never exceed assets, no rounding exploit.
///      In Foundry tests, the test contract (0x7FA9...) is CREATOR and holds initial vault shares.
///      The handler prank-calls as the test contract (creator) for burn operations.
contract VaultHandler is Test {
    DegenerusGame public game;
    DegenerusVault public vault;
    BurnieCoin public coin;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    uint256 public ghost_ethBurned;      // Total DGVE shares burned
    uint256 public ghost_ethReceived;    // Total ETH+stETH received from burns
    uint256 public ghost_coinBurned;     // Total DGVB shares burned
    uint256 public ghost_coinReceived;   // Total BURNIE received from burns
    uint256 public ghost_depositsTriggered;
    uint256 public ghost_burnEthSuccess;
    uint256 public ghost_burnCoinSuccess;

    // --- Call counters ---
    uint256 public calls_burnEth;
    uint256 public calls_burnCoin;
    uint256 public calls_purchase;

    // --- Creator is the test contract that holds initial shares ---
    address public creator;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        DegenerusVault vault_,
        BurnieCoin coin_,
        MockVRFCoordinator vrf_,
        address creator_,
        uint256 numActors
    ) {
        game = game_;
        vault = vault_;
        coin = coin_;
        vrf = vrf_;
        creator = creator_;

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xE0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Burn DGVE shares for ETH (acts as creator)
    /// @param amount Raw amount of DGVE shares to burn (bounded to small fraction)
    function burnEth(uint256 amount) external {
        calls_burnEth++;

        // Preview how much ETH we'd get (reverts if 0 shares or 0 reserve)
        amount = bound(amount, 1, 1e18); // Burn a tiny fraction of 1T supply

        vm.prank(creator);
        try vault.burnEth(creator, amount) returns (uint256 ethOut, uint256 stEthOut) {
            ghost_burnEthSuccess++;
            ghost_ethBurned += amount;
            ghost_ethReceived += ethOut + stEthOut;
        } catch {}
    }

    /// @notice Burn DGVB shares for BURNIE (acts as creator)
    /// @param amount Raw amount of DGVB shares to burn (bounded to small fraction)
    function burnCoin(uint256 amount) external {
        calls_burnCoin++;

        amount = bound(amount, 1, 1e18);

        vm.prank(creator);
        try vault.burnCoin(creator, amount) returns (uint256 coinOut) {
            ghost_burnCoinSuccess++;
            ghost_coinBurned += amount;
            ghost_coinReceived += coinOut;
        } catch {}
    }

    /// @notice Purchase tickets to drive ETH into the protocol
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw ticket quantity
    function purchase(uint256 actorSeed, uint256 qty) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 4000);

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: cost}(
            currentActor,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_depositsTriggered++;
        } catch {}
    }

    /// @notice Advance game to trigger jackpots that deposit to vault
    /// @param actorSeed Seed for actor selection
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}
    }

    /// @notice Fulfill VRF
    function fulfillVrf(uint256 randomWord) external {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @notice Warp time
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 7 days);
        vm.warp(block.timestamp + delta);
    }
}
