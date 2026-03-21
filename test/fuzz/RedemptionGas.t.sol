// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";

/// @title RedemptionGasTest -- Gas benchmarks for all sDGNRS redemption functions
/// @notice Exercises burn, burnWrapped, resolveRedemptionPeriod, claimRedemption,
///         hasPendingRedemptions, and previewBurn in isolation for clean gas measurement.
/// @dev Inherits DeployProtocol for full 28-contract deployment. Gas snapshot baseline
///      captured via `forge snapshot --match-path "test/fuzz/RedemptionGas.t.sol"`.
contract RedemptionGasTest is DeployProtocol {
    address internal player;
    uint256 internal constant PLAYER_SDGNRS = 1_000_000e18;

    function setUp() public {
        _deployProtocol();

        // Create a test player distinct from any protocol address
        player = makeAddr("gasPlayer");

        // Give the player sDGNRS tokens via game's transferFromPool
        // (game contract is the authorized caller)
        vm.prank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, player, PLAYER_SDGNRS);

        // Fund the Game with ETH and credit sDGNRS via claimableWinnings
        // (during active game, all sDGNRS ETH backing is in claimableWinnings on the Game)
        vm.deal(address(game), 100 ether);
        // claimableWinnings mapping is at slot 9; compute slot for sDGNRS's entry
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(9)));
        vm.store(address(game), claimableSlot, bytes32(uint256(100 ether)));
        // claimablePool is at slot 10
        vm.store(address(game), bytes32(uint256(10)), bytes32(uint256(100 ether)));
    }

    // =====================================================================
    //                     GAMBLING BURN PATH (during game)
    // =====================================================================

    /// @notice Gas benchmark: burn() during active game (gambling path)
    function test_gas_burn_gambling() external {
        // Game is active (not gameOver), rngLocked is false
        // Player burns sDGNRS -> enters gambling claim queue
        vm.prank(player);
        sdgnrs.burn(PLAYER_SDGNRS / 10); // burn 10% of holdings
    }

    /// @notice Gas benchmark: burnWrapped() during active game (gambling path)
    function test_gas_burnWrapped_gambling() external {
        // Give player DGNRS tokens (the wrapper token)
        // Creator holds all DGNRS; transfer some to player
        vm.prank(ContractAddresses.CREATOR);
        dgnrs.transfer(player, PLAYER_SDGNRS / 10);

        // Player calls burnWrapped on sDGNRS which routes through DGNRS.burnForSdgnrs
        vm.prank(player);
        sdgnrs.burnWrapped(PLAYER_SDGNRS / 10);
    }

    // =====================================================================
    //                     RESOLVE REDEMPTION PERIOD
    // =====================================================================

    /// @notice Gas benchmark: resolveRedemptionPeriod() called by game contract
    function test_gas_resolveRedemptionPeriod() external {
        // First, create a pending redemption via burn
        vm.prank(player);
        sdgnrs.burn(PLAYER_SDGNRS / 10);

        // Now resolve the period as the game contract
        uint48 currentDay = game.currentDayView();
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(100, currentDay);
    }

    // =====================================================================
    //                     CLAIM REDEMPTION (full lifecycle)
    // =====================================================================

    /// @notice Gas benchmark: claimRedemption() after full resolve lifecycle
    function test_gas_claimRedemption() external {
        // Step 1: Player burns sDGNRS (creates gambling claim)
        vm.prank(player);
        sdgnrs.burn(PLAYER_SDGNRS / 10);

        // Step 2: Game resolves the period
        uint48 currentDay = game.currentDayView();
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(100, currentDay);

        // Step 3: Mock the coinflip day result so claimRedemption doesn't revert
        // getCoinflipDayResult(currentDay) must return (rewardPercent != 0, flipWon)
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(coinflip.getCoinflipDayResult.selector, currentDay),
            abi.encode(uint16(100), true)
        );

        // Step 4: Mock claimCoinflipsForRedemption to avoid revert on BURNIE payout
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(coinflip.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );

        // Step 5: Player claims
        vm.prank(player);
        sdgnrs.claimRedemption();
    }

    // =====================================================================
    //                     HAS PENDING REDEMPTIONS
    // =====================================================================

    /// @notice Gas benchmark: hasPendingRedemptions() when redemptions exist
    function test_gas_hasPendingRedemptions_true() external {
        // Create a pending redemption
        vm.prank(player);
        sdgnrs.burn(PLAYER_SDGNRS / 10);

        // Now check -- should be true
        bool pending = sdgnrs.hasPendingRedemptions();
        assertTrue(pending, "Expected pending redemptions");
    }

    /// @notice Gas benchmark: hasPendingRedemptions() when no redemptions exist
    function test_gas_hasPendingRedemptions_false() external view {
        // No burns submitted -- should be false
        bool pending = sdgnrs.hasPendingRedemptions();
        assertFalse(pending, "Expected no pending redemptions");
    }

    // =====================================================================
    //                     PREVIEW BURN
    // =====================================================================

    /// @notice Gas benchmark: previewBurn() view function
    function test_gas_previewBurn() external view {
        (uint256 ethOut, uint256 stethOut, uint256 burnieOut) = sdgnrs.previewBurn(PLAYER_SDGNRS / 10);
        // Sanity: ETH backing exists so ethOut should be nonzero
        assertTrue(ethOut > 0 || stethOut > 0 || burnieOut > 0, "Expected non-zero preview");
    }
}
