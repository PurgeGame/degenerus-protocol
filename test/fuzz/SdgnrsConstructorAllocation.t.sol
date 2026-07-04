// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title SdgnrsConstructorAllocation -- pins the deploy-time supply split
/// @notice The sDGNRS constructor allocates INITIAL_SUPPLY (1e30) across the creator (minted to
///         the DGNRS wrapper) and five reward pools by fixed BPS. Nothing asserted these exact
///         proportions, so every arithmetic mutation of the allocation math survived the v75
///         mutation campaign (sDGNRS:385-397, see audit/mutation/FINDINGS-v75.md). This pins each
///         slice against the frozen split so any change to the allocation arithmetic is caught.
/// @dev Reads a freshly deployed sDGNRS before any reward distribution moves the pools; the
///      DeployProtocol harness deploys sDGNRS with the constructor split intact.
contract SdgnrsConstructorAllocation is DeployProtocol {
    uint256 internal constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18; // 1e30
    uint16 internal constant BPS = 10_000;

    function setUp() public {
        _deployProtocol();
    }

    function test_constructorSupplySplit() public view {
        // Frozen BPS: creator 2000 / whale 1000 / affiliate 3000 / lootbox 2000 / reward 1000
        // / presaleBox 1000 == 10000 (dust-free).
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Whale),      INITIAL_SUPPLY * 1000 / BPS, "whale pool");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Affiliate),  INITIAL_SUPPLY * 3000 / BPS, "affiliate pool");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Lootbox),    INITIAL_SUPPLY * 2000 / BPS, "lootbox pool");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward),     INITIAL_SUPPLY * 1000 / BPS, "reward pool");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox), INITIAL_SUPPLY * 1000 / BPS, "presaleBox pool");

        // Creator allocation minted to the DGNRS wrapper (line 385/402).
        assertEq(sdgnrs.balanceOf(ContractAddresses.DGNRS), INITIAL_SUPPLY * 2000 / BPS, "creator to DGNRS");

        // The contract holds exactly the five pools' sum (poolTotal, line 403).
        uint256 poolTotal = INITIAL_SUPPLY * (1000 + 3000 + 2000 + 1000 + 1000) / BPS;
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), poolTotal, "sDGNRS holds poolTotal");

        // Total supply == full INITIAL_SUPPLY (creator + pools; dust-free at these BPS).
        assertEq(sdgnrs.totalSupply(), INITIAL_SUPPLY, "totalSupply == INITIAL_SUPPLY");
    }
}
