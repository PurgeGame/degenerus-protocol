// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @dev Full production creditFlip call, including authorization and day calculation.
///      These are recorded-access estimates, not native Glamsterdam measurements.
contract StorageReuseCreditGasTest is DeployProtocol {
    uint32 private id;

    function setUp() public { _deployProtocol(); id = _giveWalletId(address(0x8888)); }

    function _clock(uint24 today, uint24 resolved) private {
        vm.warp((uint256(today - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        bytes32 slot = bytes32(uint256(4));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((w & ~uint256(type(uint24).max)) | resolved));
    }

    function _call() private returns (uint256 used) {
        vm.cool(address(coinflip));
        vm.prank(ContractAddresses.GAME);
        coinflip.creditFlip(id, 1000);
        // Gross gas avoids treating a capped Osaka refund as Glamsterdam execution.
        used = vm.lastCallGas().gasTotalUsed + uint64(vm.lastCallGas().gasRefunded);
    }

    function _measure(string memory name, uint256 expectedNew, uint256 expectedWrites) private {
        uint256 snap = vm.snapshotState();
        uint256 used = _call();
        vm.revertToState(snap);
        vm.startStateDiffRecording();
        _call();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(used, accesses, address(coinflip));
        emit log_named_string("case", name);
        emit log_named_uint("glamsterdam_exec_estimate", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state_gas", r.stateGas);
        emit log_named_uint("glamsterdam_total_estimate", r.glamsterdamExec + r.stateGas);
        assertEq(r.newSlots, expectedNew);
        assertEq(r.sstores, expectedWrites);
    }

    function test_creditFresh() public { _clock(105, 105); _measure("fresh", 1, 1); }
    function test_creditSamePage() public {
        _clock(105, 105);
        CoinflipStorage.set(address(coinflip), id, 105, 1000);
        _measure("same_page", 0, 1);
    }
    function test_creditReusesExpiredPage() public {
        _clock(105, 105);
        CoinflipStorage.set(address(coinflip), id, 6, 1000);
        _measure("expired_page", 0, 1);
    }
    function test_creditReusesConsumedPage() public {
        _clock(105, 90);
        CoinflipStorage.set(address(coinflip), id, 6, 1000);
        vm.store(address(coinflip), keccak256(abi.encode(uint256(id), uint256(2))), bytes32(uint256(6) << 128));
        _measure("consumed_page", 0, 1);
    }
    function test_creditSpillsLivePage() public {
        _clock(105, 90);
        CoinflipStorage.set(address(coinflip), id, 6, 1000);
        _measure("new_overflow", 1, 2);
    }
    function test_creditMergesExistingOverflowEvenAfterClaim() public {
        _clock(105, 90);
        CoinflipStorage.set(address(coinflip), id, 6, 1000);
        CoinflipStorage.set(address(coinflip), id, 105, 1000);
        vm.store(address(coinflip), keccak256(abi.encode(uint256(id), uint256(2))), bytes32(uint256(90) << 128));
        _measure("existing_overflow", 0, 1);
    }
    function test_staleHintPaysProbeButReusesDeadHome() public {
        _clock(13_440, 13_440);
        CoinflipStorage.set(address(coinflip), id, 6, 1000);
        bytes32 slot = CoinflipStorage.ringSlot(id, 0);
        vm.store(address(coinflip), slot, bytes32(uint256(vm.load(address(coinflip), slot)) | (uint256(0x80) << 248)));
        _measure("stale_hint", 0, 1);
    }
}
