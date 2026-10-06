// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice The Game constructor reserves wallet IDs 1-3 for VAULT, sDGNRS and GNRUS, so a public
///         registration between deployment steps cannot shift them and initProtocolDeity succeeds.
contract ProtocolWalletIdsAtConstruction is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");

    function test_IdsAreOneTwoThreeAndEventsFireAtConstruction() public {
        vm.recordLogs();
        _deployProtocol(false); // no initProtocolDeity yet
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(game.walletIdOf(ContractAddresses.VAULT), 1, "vault");
        assertEq(game.walletIdOf(ContractAddresses.SDGNRS), 2, "sdgnrs");
        assertEq(game.walletIdOf(ContractAddresses.GNRUS), 3, "gnrus");

        address[3] memory want = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != WALLET_REGISTERED) continue;
            if (seen < 3) {
                assertEq(uint256(logs[i].topics[1]), seen + 1, "event id");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), want[seen], "event owner");
            }
            ++seen;
        }
        assertGe(seen, 3, "three WalletRegistered at construction");
        // The first three registrations in the deployment are the protocol wallets, in order.
        assertEq(address(uint160(uint256(_firstRegistered(logs, 0)))), want[0]);
    }

    function _firstRegistered(Vm.Log[] memory logs, uint256 nth) private view returns (bytes32 owner) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) {
                if (n++ == nth) return logs[i].topics[2];
            }
        }
    }

    function test_PublicRegistrationBeforeInitGetsIdFourAndInitSucceeds() public {
        _deployProtocol(false);
        address early = address(0xEA51);
        // The affiliate door registers a wallet before the one-time protocol init.
        uint32 earlyId = _giveWalletId(early);
        assertEq(earlyId, 4, "first public wallet is ID 4");
        // A level-0 buyer would take the next ID.
        assertEq(game.walletIdOf(ContractAddresses.VAULT), 1);
        assertEq(game.walletIdOf(ContractAddresses.SDGNRS), 2);
        assertEq(game.walletIdOf(ContractAddresses.GNRUS), 3);

        game.initProtocolDeity();

        assertEq(game.walletIdOf(ContractAddresses.VAULT), 1, "vault after init");
        assertEq(game.walletIdOf(ContractAddresses.SDGNRS), 2, "sdgnrs after init");
        assertEq(game.walletIdOf(ContractAddresses.GNRUS), 3, "gnrus after init");
        assertEq(game.walletIdOf(early), 4, "early wallet keeps its ID");
    }
}
