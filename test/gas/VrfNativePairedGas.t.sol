// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {MineFlipRequestGasTest, RequestGameSeeder} from "./MineFlipRequestGas.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract NativePairSeeder is RequestGameSeeder {
    function pendingCraps() external { lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer()); }
    function distribution() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSignature("distributeYieldSurplus(uint256)", uint256(1)));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

/// @dev The same committed fixtures run at f8b8b4af9 and on the native branch.
/// Each export is replayed with read-only state overrides on the native Glamsterdam node.
contract VrfNativePairedGasTest is MineFlipRequestGasTest {
    function configurePair(uint8 kind) external {
        require(msg.sender == address(this));
        if (kind < 5) {
        this.configure(kind == 2 || kind == 3 ? Scenario.Daily : Scenario.Midday);
        vm.etch(address(host), vm.getDeployedCode("VrfNativePairedGas.t.sol:NativePairSeeder"));
        if (kind == 1) NativePairSeeder(payable(address(host))).pendingCraps();
        if (kind == 3 || kind == 4) {
            // Source-model subscription balances[1], zero native or LINK balance.
            vm.store(address(coordinator), keccak256(abi.encode(uint256(1), uint256(2))), bytes32(0));
            host.claimableBacking(1 ether);
            vm.deal(address(host), 3000 ether);
        }
        }
        vm.deal(address(this), 100 ether);

    }
    function exportPair(uint8 kind) external {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        if (kind < 4) _nativeFixture(string.concat("pair-", vm.toString(kind)), address(this), address(host),
            abi.encodeCall(host.requestOnly, (kind >= 2)));
        if (kind == 4) _nativeFixture("pair-4", address(this), address(host), abi.encodeCall(NativePairSeeder.distribution, ()));
        if (kind == 5) _nativeFixture("pair-5", address(this), address(admin), 1 ether, abi.encodeCall(admin.donateVrf, ()));
    }
    function testPairLootbox() public { this.configurePair(0); this.exportPair(0); }
    function testPairCraps() public { this.configurePair(1); this.exportPair(1); }
    function testPairDaily() public { this.configurePair(2); this.exportPair(2); }
    function testPairDailyRefill() public { this.configurePair(3); this.exportPair(3); }
    function testPairDistribution() public { this.configurePair(4); this.exportPair(4); }
    function testPairDonation() public { this.configurePair(5); this.exportPair(5); }
}
