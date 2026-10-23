// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StorageCensusLongRunTest} from "../census/StorageCensusLongRun.t.sol";
import {SolvencyObligations} from "../fuzz/helpers/SolvencyObligations.sol";
import {console} from "forge-std/console.sol";

/// @dev Run the same workload with each runtime set. Random recipients and quantities may
/// change, but every transaction must conserve ETH and every checkpoint must retain backing
/// and valid tagged queue boundaries. No ledger or entire storage contract is whitelisted.
contract RngInvariantReplayTest is StorageCensusLongRunTest {
    address[] private holders;
    uint256 private invariantChecks;

    function setUp() public override {
        super.setUp();
        string memory file = vm.envOr("OPT_RUNTIME_OVERRIDES", string(""));
        if (bytes(file).length != 0) {
            string memory variants = vm.readFile(file);
            uint256 count = vm.parseJsonUint(variants, ".count");
            for (uint256 i; i < count; ++i) {
                string memory prefix = string.concat(".contracts[", vm.toString(i), "]");
                vm.etch(vm.parseJsonAddress(variants, string.concat(prefix, ".target")),
                    vm.parseJsonBytes(variants, string.concat(prefix, ".runtime")));
            }
        }
        for (uint256 i; i < cast.length; ++i) _holder(cast[i]);
        _holder(address(this)); _holder(CENSUS_KEEPER);
        _holder(address(game)); _holder(address(coin)); _holder(address(coinflip));
        _holder(address(sdgnrs)); _holder(address(dgnrs)); _holder(address(crapsBattle));
        _holder(address(wwxrp)); _holder(address(gnrus)); _holder(address(vault));
        _holder(address(affiliate)); _holder(address(quests)); _holder(address(jackpots));
        _holder(address(afkingSubToken)); _holder(address(deityPass));
        _holder(address(parimutuel)); _holder(address(recordBounty));
        _holder(address(ownerGovernance)); _holder(address(admin));
        _holder(address(mockStETH)); _holder(address(mockVRF)); _holder(address(mockLINK));
        _holder(address(0xC4A1)); _holder(address(0xC4A2));
        vm.fee(0);
    }

    function _holder(address who) private {
        for (uint256 i; i < holders.length; ++i) if (holders[i] == who) return;
        holders.push(who);
    }

    function _eth() private view returns (uint256 total) {
        for (uint256 i; i < holders.length; ++i) total += holders[i].balance;
    }

    function _ctx(string memory label, bool protocolPaid, address from, address to, uint256 value, bytes memory data)
        internal override returns (bool ok, bytes memory ret)
    {
        _holder(from); _holder(to);
        uint256 beforeEth = _eth();
        (ok, ret) = super._ctx(label, protocolPaid, from, to, value, data);
        // The raw queue oracle allocates memory for cheatcode reads. Isolate each
        // checkpoint so thousands of checks do not grow the long-run parent frame.
        this.checkRngInvariants(beforeEth, label);
        ++invariantChecks;
    }

    function checkRngInvariants(uint256 beforeEth, string calldata label) external view {
        require(msg.sender == address(this));
        assertEq(_eth(), beforeEth, string.concat("ETH conservation: ", label));
        assertGe(SolvencyObligations.backing(game), SolvencyObligations.obligations(game),
            string.concat("ETH backing and queue boundaries: ", label));
    }

    function _censusEnd() internal override {
        super._censusEnd();
        console.log("RNGINVARIANTS|ETH-conservation|solvency|queue-boundaries|PASS", invariantChecks);
    }
}
