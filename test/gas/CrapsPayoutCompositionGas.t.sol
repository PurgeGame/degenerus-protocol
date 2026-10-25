// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

interface CrapsPayoutCoinflip {
    function creditFlip_g317(uint32 id, uint256 amount) external;
    function armDiceRunRecord(uint32 id, uint256 score) external returns (uint256);
}
interface CrapsPayoutFlip { function creditCrapsComps_g37225(uint256 amount) external; }
interface CrapsPayoutGame { function setCrapsRngPending_g1406(uint48 index, bool pending) external; }

/// @dev Reproduce finalization's actual external-call order in one cold frame.
/// All callees retain their production code; only the calling table is a seam.
contract CrapsPayoutSequence {
    function pay(uint32 hot, uint32 main, uint32 lane) external {
        CrapsPayoutFlip(ContractAddresses.COIN).creditCrapsComps_g37225(123_456);
        CrapsPayoutCoinflip cf = CrapsPayoutCoinflip(ContractAddresses.COINFLIP);
        cf.creditFlip_g317(hot, 79_400);
        cf.creditFlip_g317(main, 863_400);
        cf.creditFlip_g317(lane, 1_184_200);
        cf.creditFlip_g317(main, 2_916_800);
        cf.armDiceRunRecord(main, 5_555_555_555);
        CrapsPayoutGame(ContractAddresses.GAME).setCrapsRngPending_g1406(0, false);
    }
}

contract CrapsPayoutCompositionGasTest is DeployProtocol, NativeGasExport {
    function setUp() public { _deployProtocol(); }

    function test_NativeFinalSeatPayoutComposition() public {
        vm.warp(vm.getBlockTimestamp() + 4 days);
        uint32 hot = _giveWalletId(address(0x710001));
        uint32 main = _giveWalletId(address(0x710002));
        uint32 lane = _giveWalletId(address(0x710003));
        vm.prank(address(game)); coinflip.fundRecordPool(1_000_000);
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending_g1406(0, true);
        vm.etch(ContractAddresses.CRAPS, type(CrapsPayoutSequence).runtimeCode);
        CrapsPayoutSequence host = CrapsPayoutSequence(ContractAddresses.CRAPS);
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(game)); vm.cool(address(coinflip)); vm.cool(address(coin));
        host.pay(hot, main, lane);
        emit log_named_uint("cold final-seat shared payout sequence", vm.lastCallGas().gasTotalUsed);
        assertEq(coinflip.biggestDiceRunEver(), 5_555_555_555, "fresh record branch");
        assertGt(sdgnrs.balanceOf(address(0x710002)), 0, "real record DGNRS payout");
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture("craps-final-seat-real-payout-sequence", address(this), address(host),
                abi.encodeCall(host.pay, (hot, main, lane)));
        }
        vm.deleteStateSnapshot(snapshot);
    }
}
