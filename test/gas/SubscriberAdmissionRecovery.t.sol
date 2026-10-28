// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Healthy-token admission refuses atomically and a different keeper can resume.
/// @dev Run with FOUNDRY_ISOLATE=true. The shares mock has no gas-burning/reverting behavior;
/// its gas envelope is not evidence about the gas consumed by mainnet Lido's proxy.
contract SubscriberAdmissionRecoveryTest is DeployProtocol {
    address private constant SUBSCRIBER = address(0x51B5C);
    address private constant FIRST_KEEPER = address(0xCA11);
    address private constant NEXT_KEEPER = address(0xCA12);
    uint256 private constant CALL_CAP = 16_700_000;
    DegenerusGameLens private lens;
    uint32 private subscriberId;
    uint256 private subscriberShares;

    function setUp() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "subscriber regression requires isolated calls");
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishSubscriptionWindow();
        _finishReadConsumers();
        lens = new DegenerusGameLens();
        uint256 seat = _grantSeat(SUBSCRIBER);
        vm.deal(SUBSCRIBER, 10 ether);
        vm.startPrank(SUBSCRIBER);
        mockStETH.submit{value: 2 ether}(address(0));
        mockStETH.approve(address(game), 1 ether);
        game.subscribe(0, false, 1, seat);
        vm.stopPrank();
        mockStETH.rebase();
        subscriberId = game.walletIdOf_g3120(SUBSCRIBER);
        subscriberShares = mockStETH.sharesOf(SUBSCRIBER);
        assertEq(uint256(vm.load(address(game), GameSlotKeys.balances(subscriberId))) >> 128, 0);
        assertTrue(lens.subInfoFullById(address(game), subscriberId).active);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev The external wrapper gives every measured protocol call a fresh isolated transaction.
    function keeperCall(address keeper, uint32 calibration, uint256 callGas)
        external returns (bool ok, bytes memory reason)
    {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.txGasPrice(3 gwei);
        vm.prank(keeper, keeper);
        return address(game).call{gas: callGas}(abi.encodeCall(game.mineRun, (calibration)));
    }

    function test_maxCalibrationRefusalIsAtomicAndDifferentKeeperRecovers() public {
        bool refused;
        for (uint256 i; i < 16; ++i) {
            bytes32 progress = vm.load(address(game), bytes32(GameSlots.SUB_CURSOR));
            uint256 supply = coin.totalSupply();
            uint256 keeperFlip = coinflip.previewFlipBacking(FIRST_KEEPER);
            vm.startStateDiffRecording();
            (bool ok, bytes memory reason) = this.keeperCall(FIRST_KEEPER, type(uint32).max, CALL_CAP);
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            if (ok) continue; // Earlier mandatory protocol-seat work may precede this member.
            assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
            _assertRolledBack(accesses);
            assertEq(vm.load(address(game), bytes32(GameSlots.SUB_CURSOR)), progress, "refusal changed cursor/day");
            assertEq(coin.totalSupply(), supply, "refusal minted reward");
            assertEq(coinflip.previewFlipBacking(FIRST_KEEPER), keeperFlip, "refusal credited keeper");
            assertEq(mockStETH.sharesOf(SUBSCRIBER), subscriberShares, "refusal spent subscriber shares");
            assertTrue(lens.subInfoFullById(address(game), subscriberId).active, "refusal expired member");
            refused = true;
            break;
        }
        assertTrue(refused, "fixture never reached required admission refusal");
        _recover();
    }

    /// @notice Caller gas/calibration must not turn healthy funded membership into expiry.
    /// forge-config: default.fuzz.runs = 128
    /// forge-config: deep.fuzz.runs = 512
    function testFuzz_healthyFundingDoesNotExpireAtCallerGasBoundary(uint32 calibrationSeed, uint256 gasSeed) public {
        uint32 calibration = uint32(bound(calibrationSeed, 2_500, 10_000));
        uint256 callGas = bound(gasSeed, 250_000, 2_000_000);
        bool boundaryReached;
        for (uint256 i; i < 8; ++i) {
            vm.startStateDiffRecording();
            (bool ok,) = this.keeperCall(FIRST_KEEPER, calibration, callGas);
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            if (!ok) _assertRolledBack(accesses);
            assertTrue(lens.subInfoFullById(address(game), subscriberId).active,
                "caller gas expired a healthy funded subscriber");
            if (!ok || mockStETH.sharesOf(SUBSCRIBER) != subscriberShares) {
                boundaryReached = true;
                break;
            }
        }
        assertTrue(boundaryReached, "probe never reached refusal or subscriber funding");
        _recover();
    }

    function _recover() private {
        uint24 startDay = game.currentDayView_g542950();
        for (uint256 i; i < 100; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool delivered) = mockVRF.pendingRequests(request);
                if (!delivered) mockVRF.fulfillRandomWords(request, 0xA11CE);
            }
            (bool complete,,) = game.dailySessionState();
            if (mockStETH.sharesOf(SUBSCRIBER) < subscriberShares && complete) {
                assertTrue(lens.subInfoFullById(address(game), subscriberId).active);
                assertGe(game.currentDayView_g542950(), startDay);
                return;
            }
            (bool ok, bytes memory reason) = this.keeperCall(NEXT_KEEPER, 0, CALL_CAP);
            assertTrue(ok, string.concat("normal recovery refused: ", vm.toString(reason)));
        }
        revert("unrelated keeper did not finish healthy subscriber work");
    }

    /// @dev Compare every touched slot with its first observed value, including nested calls.
    /// This also witnesses rollback outside the Game (token, reward and other modules).
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
