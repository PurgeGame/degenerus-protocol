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
/// Kinds: 0 lootbox, 1 craps, 2 daily, 3 daily refill, 4 level entry above the funding
/// threshold, 5 donation, 6 level entry below it, 7 swap reissue onto a fresh subscription,
/// 8 swap reissue onto a subscription already holding the forwarded refund.
contract VrfNativePairedGasTest is MineFlipRequestGasTest {
    uint256 private constant LIVE_REQ_COUNT = uint256(100) << 192;

    function _subscription(uint256 nativeBalance) private {
        // Source-model balances[1]: a live subscription keeps its nonzero request count.
        vm.store(address(coordinator), keccak256(abi.encode(uint256(1), uint256(2))),
            bytes32(LIVE_REQ_COUNT | (nativeBalance << 96)));
    }

    function configurePair(uint8 kind) external {
        require(msg.sender == address(this));
        if (kind != 5) {
            bool daily = kind == 2 || kind == 3 || kind >= 7;
            this.configure(daily ? Scenario.Daily : Scenario.Midday);
            vm.etch(address(host), vm.getDeployedCode("VrfNativePairedGas.t.sol:NativePairSeeder"));
            if (kind == 1) NativePairSeeder(payable(address(host))).pendingCraps();
            // The normal daily holds ETH, so it reads the subscription and finds it above low-water.
            if (kind >= 2 && kind != 5) {
                host.claimableBacking(1 ether);
                vm.deal(address(host), 3000 ether);
            }
            if (kind == 3 || kind == 4) _subscription(0.01 ether);
            // Deficit 0.01 ETH, under a tenth of the 0.2976 ETH refill band.
            if (kind == 6) _subscription(0.48352 ether);
            if (kind >= 7) {
                host.requestOnly(true);
                coordinator.seedSubscription(2, address(game), kind == 7 ? 0 : 1 ether);
                vm.deal(ContractAddresses.ADMIN, 1 ether);
            }
        }
        vm.deal(address(this), 100 ether);
    }
    function exportPair(uint8 kind) external {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        if (kind < 4) _nativeFixture(string.concat("pair-", vm.toString(kind)), address(this), address(host),
            abi.encodeCall(host.requestOnly, (kind >= 2)));
        if (kind == 4 || kind == 6) _nativeFixture(string.concat("pair-", vm.toString(kind)), address(this), address(host),
            abi.encodeCall(NativePairSeeder.distribution, ()));
        if (kind == 5) _nativeFixture("pair-5", address(this), address(admin), 1 ether, abi.encodeCall(admin.donateVrf, ()));
        if (kind >= 7) _nativeFixture(string.concat("pair-", vm.toString(kind)), ContractAddresses.ADMIN, address(host),
            abi.encodeCall(host.updateVrfCoordinatorAndSub, (address(coordinator), 2, bytes32(uint256(1234)), 150_000)));
    }
    /// @dev The funding kinds reach the target; the others leave the subscription as seeded.
    function checkPair(uint8 kind) external {
        require(msg.sender == address(this));
        uint256 snapshot = vm.snapshotState();
        uint256 sub = kind >= 7 ? 2 : 1;
        (, uint96 before,,,) = coordinator.getSubscription(sub);
        vm.fee(1 gwei);
        if (kind == 2 || kind == 3) host.requestOnly(true);
        if (kind == 4 || kind == 6) NativePairSeeder(payable(address(host))).distribution();
        if (kind >= 7) {
            (,, uint256 original,) = host.committed();
            vm.prank(ContractAddresses.ADMIN);
            host.updateVrfCoordinatorAndSub(address(coordinator), 2, bytes32(uint256(1234)), 150_000);
            (,, uint256 reissued,) = host.committed();
            assertTrue(reissued != original && coordinator.commitments(reissued) != bytes32(0), "swap reissued the daily request");
        }
        (, uint96 balance,,,) = coordinator.getSubscription(sub);
        if (kind == 3 || kind == 4 || kind == 7) assertEq(balance, 0.49352 ether, "funded to target");
        else assertEq(balance, before, "no funding call");
        assertTrue(vm.revertToStateAndDelete(snapshot));
    }
    function testPairLootbox() public { this.configurePair(0); this.exportPair(0); }
    function testPairCraps() public { this.configurePair(1); this.exportPair(1); }
    function testPairDaily() public { this.configurePair(2); this.checkPair(2); this.exportPair(2); }
    function testPairDailyRefill() public { this.configurePair(3); this.checkPair(3); this.exportPair(3); }
    function testPairDistribution() public { this.configurePair(4); this.checkPair(4); this.exportPair(4); }
    function testPairDonation() public { this.configurePair(5); this.exportPair(5); }
    function testPairDistributionBelowThreshold() public { this.configurePair(6); this.checkPair(6); this.exportPair(6); }
    function testPairSwapReissueFresh() public { this.configurePair(7); this.checkPair(7); this.exportPair(7); }
    function testPairSwapReissueFunded() public { this.configurePair(8); this.checkPair(8); this.exportPair(8); }
}
