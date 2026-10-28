// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {ForkDeployProtocol} from "./ForkDeployProtocol.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Caller gas must not expire a funded ordinary subscriber against pinned real Lido.
/// @dev Requires isolated calls for cold external/storage accesses. The fork's normal
/// proof-independent VRF delivery is used only for setup and the recovery completion.
contract SubscriberAdmissionRecoveryForkTest is ForkDeployProtocol {
    address private constant PLAYER = address(0x51B5C);
    address private constant PROBE_KEEPER = address(0xCA11);
    address private constant RECOVERY_KEEPER = address(0xCA12);
    uint256 private constant CAP = 16_700_000;
    DegenerusGameLens private lens;
    uint32 private playerId;
    uint256 private sharesBefore;

    function setUp() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "Lido gas boundary requires isolated calls");
        _forkAndDeploy();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(200);
        lens = new DegenerusGameLens();
        uint256 seat = _grantSeat(PLAYER);
        _realSteth(PLAYER, 2 ether);
        vm.startPrank(PLAYER);
        lido.approve(address(game), 1 ether);
        game.subscribe(0, false, 1, seat);
        vm.stopPrank();
        playerId = game.walletIdOf_g3120(PLAYER);
        sharesBefore = lido.sharesOf(PLAYER);
        assertGt(sharesBefore, 0, "fixture owns real shares");
        assertEq(lido.allowance(PLAYER, address(game)), 1 ether, "fixture has finite real allowance");
        assertEq(uint256(vm.load(address(game), GameSlotKeys.balances(playerId))) >> 128, 0);
        assertTrue(lens.subInfoFullById(address(game), playerId).active);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function keeperCall(uint32 factor, uint256 callGas) external returns (bool ok, bytes memory reason) {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.txGasPrice(3 gwei);
        vm.prank(PROBE_KEEPER, PROBE_KEEPER);
        return address(game).call{gas: callGas}(abi.encodeCall(game.mineRun, (factor)));
    }

    function test_realLidoMaxRefusalIsAtomicAndDifferentKeeperRecovers() public {
        bool refused;
        for (uint256 i; i < 16; ++i) {
            uint256 supply = coin.totalSupply();
            uint256 reward = coinflip.previewFlipBacking(PROBE_KEEPER);
            vm.startStateDiffRecording();
            (bool ok, bytes memory reason) = this.keeperCall(type(uint32).max, CAP);
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            if (ok) continue;
            assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
            _assertRolledBack(accesses);
            assertEq(coin.totalSupply(), supply, "refusal minted reward");
            assertEq(coinflip.previewFlipBacking(PROBE_KEEPER), reward, "refusal paid keeper");
            assertEq(lido.sharesOf(PLAYER), sharesBefore, "refusal spent real shares");
            assertTrue(lens.subInfoFullById(address(game), playerId).active);
            refused = true;
            break;
        }
        assertTrue(refused, "fixture never reached maximum-calibration refusal");
        _recover();
    }

    /// @dev A cold 2,500-bps scan in 2,000-gas increments, then broader 5,000/10,000-bps
    /// scans in 5,000-gas increments. A finite grid is evidence, not a universal gas proof.
    function test_realLidoFundedSubscriberSurvivesCallerGasBoundary() public {
        uint256 initial = vm.snapshotState();
        _recover(); // Establish a successful real-token baseline from this exact state.
        assertTrue(vm.revertToState(initial));
        uint256 refusals;
        uint256 funded;
        for (uint256 factorIndex; factorIndex < 3; ++factorIndex) {
            uint32 factor = factorIndex == 0 ? 2_500 : factorIndex == 1 ? 5_000 : 10_000;
            uint256 stride = factorIndex == 0 ? 2_000 : 5_000;
            uint256 limit = factorIndex == 0 ? 900_000 : 2_000_000;
            for (uint256 gasLimit = 250_000; gasLimit <= limit; gasLimit += stride) {
                assertTrue(vm.revertToState(initial));
                emit log_named_uint("probe factor", factor);
                emit log_named_uint("probe call gas", gasLimit);
                (bool refused, bool bought) = this.probePoint(factor, gasLimit);
                if (refused) ++refusals;
                if (bought) ++funded;
            }
        }
        assertGt(refusals, 0, "boundary scan must observe refusal");
        assertGt(funded, 0, "boundary scan must observe real funding");
        emit log_named_uint("refusing grid points", refusals);
        emit log_named_uint("funding grid points", funded);
        assertTrue(vm.revertToState(initial));
        _recover();
    }

    /// @dev Free the state-diff arrays between grid points; retaining them in the outer
    /// test frame would turn the gas sweep into a quadratic EVM memory-expansion test.
    function probePoint(uint32 factor, uint256 callGas) external returns (bool refused, bool bought) {
        require(msg.sender == address(this));
        for (uint256 i; i < 8; ++i) {
            vm.startStateDiffRecording();
            (bool ok,) = this.keeperCall(factor, callGas);
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            if (!ok) { _assertRolledBack(accesses); refused = true; }
            assertTrue(lens.subInfoFullById(address(game), playerId).active,
                "caller gas expired a real-Lido funded subscriber");
            if (lido.sharesOf(PLAYER) < sharesBefore) return (refused, true);
            if (!ok) return (true, false);
        }
        revert("probe never reached refusal or subscriber funding");
    }

    function _recover() private {
        keeper = RECOVERY_KEEPER;
        _crank(200);
        assertLt(lido.sharesOf(PLAYER), sharesBefore, "different keeper did not perform real funding");
        assertTrue(lens.subInfoFullById(address(game), playerId).active, "funded subscriber lost membership");
        (bool complete,,) = game.dailySessionState();
        assertTrue(complete, "different keeper did not complete the daily work");
    }

    function _assertRolledBack(Vm.AccountAccess[] memory accesses) private view {
        uint256 count;
        for (uint256 i; i < accesses.length; ++i) count += accesses[i].storageAccesses.length;
        Vm.StorageAccess[] memory first = new Vm.StorageAccess[](count);
        uint256 seen;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                bool known;
                for (uint256 k; k < seen; ++k) {
                    if (first[k].account == a.account && first[k].slot == a.slot) { known = true; break; }
                }
                if (known) continue;
                first[seen++] = a;
                assertEq(vm.load(a.account, a.slot), a.previousValue, "refused call persisted storage");
            }
        }
    }
}
