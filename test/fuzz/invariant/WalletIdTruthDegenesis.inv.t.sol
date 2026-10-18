// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {WalletIdTruthHandler} from "../handlers/WalletIdTruthHandler.sol";
import {WalletIdTruthInvariant} from "./WalletIdTruth.inv.t.sol";

/// @title WalletIdTruthDegenesisWeek -- the wallet-ID truth after a real Degenesis week (turbo launch)
/// @notice Every log from Game construction on, the whole sale included, reaches the handler's registry
///         ghost: the opening keeps the suite's recording. The registry starts with the sale's buyers.
contract WalletIdTruthDegenesisWeek is WalletIdTruthInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _dgwKeepLogs() internal pure override returns (bool) {
        return true;
    }

    /// @dev Own counter keys, so the coverage and non-vacuity floors count this suite's runs, not the parent's.
    function _counterKey(string memory k) internal pure override returns (string memory) {
        return string.concat("DGT_", k);
    }

    function setUp() public override {
        // Every WalletRegistered from Game construction on reaches the handler's ghost list.
        vm.recordLogs();
        _deployProtocol();
        _degenesisWeek(true);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        for (uint256 i; i < N_SEEDED; ++i) {
            address a = address(uint160(0x1D7A0000 + i));
            seeded.push(a);
            vm.deal(a, 10_000 ether);
            _dgnrsFromVault(a, 1_000_000e12);
            vm.startPrank(address(game));
            coin.mintForGame(a, 5_000_000);
            wwxrp.mintPrize(a, 200_000);
            vm.stopPrank();
            mockLINK.mint(a, 50 ether);
            if (i < 4) {
                vm.prank(a);
                game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
                _grantSmurfBase(a, 8);
            }
        }
        _driveDay(1);
        handler = new WalletIdTruthHandler(game, mockVRF, mockLINK, seeded);
        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
