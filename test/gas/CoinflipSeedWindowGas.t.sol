// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipSeedWindowGas — cost of the VAULT / sDGNRS seed program
/// @notice Every measured call is the first protocol call of its test, so it starts on a cold
///         EIP-2929 access list with setUp's writes committed. Figures are logged; the ceilings
///         pin the seed window's single-word arm and the walk reading the seed instead of a lane.
///         The outer self-call keeps the measured protocol call nested under --isolate, so
///         lastCallGas reports execution gas without adding transaction intrinsic gas.
contract CoinflipSeedWindowGas is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;

    uint256 internal constant ARM_GAS_CEIL = 15_000;
    uint256 internal constant VAULT_WALK_GAS_CEIL = 180_000;
    uint256 internal constant SEEDED_DAY_RESOLVE_GAS_CEIL = 43_000;

    function setUp() public {
        _deployProtocol();
        // Days 1..20 carry the deploy window; resolve 1..19 so day 20 is left to measure and the
        // vault's cursor still sits at 0.
        for (uint24 d = 1; d < 20; ++d) {
            _resolve(d, d % 3 != 0);
        }
    }

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _resolve(uint24 d, bool win) internal {
        _warpToDay(d);
        uint256 word = uint256(keccak256(abi.encodePacked("seed_window_gas", d)));
        word = win ? word | 1 : word & ~uint256(1);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, d);
    }

    function measureSeedCall(address caller, bytes calldata data) external returns (uint256 used) {
        require(msg.sender == address(this));
        vm.prank(caller);
        (bool ok, bytes memory result) = address(coinflip).call(data);
        used = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    /// @dev The x00 arm, cold, at a day past the deploy window.
    function test_ArmCenturySeedCold() public {
        _warpToDay(60);
        uint256 used = this.measureSeedCall(GAME, abi.encodeCall(coinflip.armCenturySeed, (100)));
        emit log_named_uint("armCenturySeed_cold_gas", used);
        assertLt(used, ARM_GAS_CEIL, "arming a window is one packed-slot write");
    }

    /// @dev The vault's first claim: the walk crosses the 19 resolved deploy-window days.
    function test_VaultClaimAcrossSeededWindowCold() public {
        uint256 used = this.measureSeedCall(VAULT,
            abi.encodeCall(coinflip.claimCoinflips, (0, type(uint256).max)));
        emit log_named_uint("vault_claim_19_seeded_days_cold_gas", used);
        assertLt(used, VAULT_WALK_GAS_CEIL, "seeded days add no lane clear to the vault walk");
    }

    /// @dev A seeded day's resolution, which walks sDGNRS across that day.
    function test_SeededDayResolutionCold() public {
        _warpToDay(20);
        uint256 used = this.measureSeedCall(GAME, abi.encodeCall(coinflip.processCoinflipPayouts,
            (0, uint256(keccak256("seed_window_gas_day20")) | 1, 20)));
        emit log_named_uint("seeded_day_resolution_cold_gas", used);
        assertLt(used, SEEDED_DAY_RESOLVE_GAS_CEIL, "sDGNRS's seeded day costs no lane clear");
    }

    /// @dev Deploying Coinflip, constructor included.
    function test_DeployGas() public {
        uint256 g0 = gasleft();
        new Coinflip();
        uint256 used = g0 - gasleft();
        emit log_named_uint("coinflip_deploy_gas", used);
    }
}
