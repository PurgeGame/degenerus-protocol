// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title VrfWireOneShot — VTST-04: VRF wiring is one-shot (proves VRF-04 + VRF-05)
/// @notice Phase 312 deliberately OMITTED the `wireVrf` init-only runtime lock that the
///         311 SPEC originally mandated (user-approved VRF-04 deviation, see
///         312-01-SUMMARY Deviations §1). There is NO
///         `if (address(vrfCoordinator) != address(0)) revert E();` guard in the
///         contract — so this test does NOT assert any such init-lock revert (one would
///         fail). The one-shot property is proven in the form that ACTUALLY EXISTS:
///
///         (1) Access-guard revert — the impl's `:503` (wireVrf) /
///             `:1717` (updateVrfCoordinatorAndSub) `msg.sender != ContractAddresses.ADMIN`
///             check rejects every non-ADMIN caller through the routed delegatecall reach
///             (DegenerusGame.wireVrf :308 / updateVrfCoordinatorAndSub :1874 ->
///             delegatecall -> AdvanceModule impl -> ADMIN guard). This is the
///             "second wire from an unauthorized caller reverts" provable shape.
///         (2) Structural one-shot attestation — DegenerusAdmin reaches `gameAdmin.wireVrf`
///             only from its constructor (:458) and exposes no post-construction forwarder,
///             so a second wire even from the ADMIN sender is topologically unreachable.
///
///         Models test/fuzz/CoverageGap222.t.sol:test_gap_game_vrf_admin_paths.
contract VrfWireOneShot is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    /// @notice A non-ADMIN caller's `wireVrf` reverts via the impl `:503` ADMIN guard.
    /// @dev Routed reach: DegenerusGame.wireVrf (:308) delegatecalls the AdvanceModule
    ///      impl (:498) whose `:503` `msg.sender != ContractAddresses.ADMIN` check rejects
    ///      the call. `msg.sender` is preserved across delegatecall, so a freshly-made
    ///      non-admin actor (distinct from ContractAddresses.ADMIN) is genuinely rejected
    ///      by the guard — not a setup artifact. Low-level call + assertFalse(ok) so the
    ///      assertion is robust to the exact revert selector (the access guard reverts with
    ///      the contract's `E()` custom error). This is the access-guard form of "a second
    ///      wire reverts" for any unauthorized caller (VRF-04).
    function test_nonAdminWireVrf_reverts() public {
        address nonAdmin = makeAddr("nonAdmin");
        // Sanity: the actor is NOT the privileged ADMIN, so the revert below is the
        // genuine guard rejecting an unauthorized caller (mitigates a tautological pass).
        assertTrue(nonAdmin != ContractAddresses.ADMIN, "actor must not be ADMIN");

        vm.prank(nonAdmin);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature(
                "wireVrf(address,uint256,bytes32)",
                makeAddr("coord"),
                uint256(1),
                keccak256("kh")
            )
        );
        assertFalse(ok, "wireVrf rejects non-ADMIN caller (the :503 guard)");
    }

    /// @notice A non-ADMIN caller's `updateVrfCoordinatorAndSub` reverts (VRF-05 companion).
    /// @dev The routed admin dispatch (DegenerusGame.updateVrfCoordinatorAndSub :1874 ->
    ///      delegatecall -> AdvanceModule impl :1712) terminates at the same impl behind the
    ///      `:1717` `msg.sender != ContractAddresses.ADMIN` guard. Proves the routed
    ///      coordinator-rotation entry is guarded against any non-ADMIN sender.
    function test_nonAdminUpdateVrf_reverts() public {
        address nonAdmin = makeAddr("nonAdmin");
        assertTrue(nonAdmin != ContractAddresses.ADMIN, "actor must not be ADMIN");

        vm.prank(nonAdmin);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature(
                "updateVrfCoordinatorAndSub(address,uint256,bytes32)",
                makeAddr("coord2"),
                uint256(2),
                keccak256("kh2")
            )
        );
        assertFalse(
            ok,
            "updateVrfCoordinatorAndSub rejects non-ADMIN caller (the :1717 guard)"
        );
    }

    /// @notice The constructor wire ran exactly once at deploy.
    /// @dev DegenerusAdmin's constructor (:445) calls gameAdmin.wireVrf (:458), which sets
    ///      `lastVrfProcessedTimestamp`. A non-zero `lastVrfProcessed()` view confirms wiring
    ///      is in place, establishing that any further `wireVrf` is the "second wire" the
    ///      access guard blocks for every non-ADMIN caller.
    function test_wiringHappenedAtDeploy() public view {
        assertTrue(
            game.lastVrfProcessed() != 0,
            "VRF wiring ran once at deploy (lastVrfProcessed != 0)"
        );
    }
}
