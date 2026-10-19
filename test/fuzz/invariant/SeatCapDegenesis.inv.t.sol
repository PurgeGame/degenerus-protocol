// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {SeatCapHandler, SeatCapInvariant} from "./SeatCap.inv.t.sol";

/// @title SeatCapDegenesis -- the AFKing seat bound after a real Degenesis week (turbo launch)
contract SeatCapDegenesis is SeatCapInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev Own counter keys, so the coverage and non-vacuity floors count this suite's runs, not the parent's.
    function _counterKey(string memory k) internal pure override returns (string memory) {
        return string.concat("DGT_", k);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        handler = new SeatCapHandler(game, afkingSubToken, vault, mockVRF, address(sdgnrs));
        vaultOp = handler.vaultOp();
        // This contract is CREATOR, the vault owner.
        vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, vaultOp, true),
            0
        );
        // Wallets 0..4 start registered, each holding its pass's free seat; wallets 0 and 1
        // own a smurf. Wallets 5..9 start unregistered.
        for (uint256 i; i < 5; ++i) handler.passPurchase(i);
        for (uint256 i; i < 5; ++i) _grantSmurfBase(handler.wallets(i), 8);
        handler.createSmurf(0);
        handler.createSmurf(1);
        require(handler.smurfIds(1) != 0, "fixture: two smurfs");
        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
        _finishSubscriptionWindow();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
