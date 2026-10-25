// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Runs at the coordinator's address. The returned figure is the callback's share of a
///      coordinator fulfillment: the CALL (cold Game account) plus everything Game executes.
contract VrfBillingProbe {
    function fulfill(address game, uint256 id, uint256 word) external returns (uint256 used) {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        bytes memory data = abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", id, words);
        uint256 before = gasleft();
        (bool ok, ) = game.call(data);
        used = before - gasleft();
        require(ok, "callback reverted");
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true: every top-level call is a fresh transaction, so Game's
///      account and storage are cold. Uses only public reads, so the same file runs unchanged
///      against any storage layout for paired comparisons.
contract VrfCallbackGasTest is DeployProtocol {
    function setUp() public { _deployProtocol(); vm.warp(vm.getBlockTimestamp() + 1 days); }

    function _words(uint256 word) private pure returns (uint256[] memory words) {
        words = new uint256[](1);
        words[0] = word;
    }

    /// @dev Mine until a new request is issued; returns the issuing transaction's gas.
    function _mineRequest() private returns (uint256 id, uint256 used) {
        uint256 prior = mockVRF.lastRequestId();
        for (uint256 i; i < 200; ++i) {
            game.mineFlip(0);
            used = vm.snapshotGasLastCall("vrf-mine");
            id = mockVRF.lastRequestId();
            if (id != prior) return (id, used);
        }
        revert("no request");
    }

    function _billed(uint256 id, uint256 word) private returns (uint256 used) {
        bytes memory original = address(mockVRF).code;
        vm.etch(address(mockVRF), type(VrfBillingProbe).runtimeCode);
        used = VrfBillingProbe(address(mockVRF)).fulfill(address(game), id, word);
        vm.etch(address(mockVRF), original);
    }

    function _direct(uint256 id, uint256 word) private returns (uint256 used) {
        vm.prank(address(mockVRF));
        game.rawFulfillRandomWords(id, _words(word));
        used = vm.snapshotGasLastCall("vrf-callback");
    }

    function _finishDay() private {
        for (uint256 i; i < 400 && (game.rngLocked() || game.minerAction() != 0); ++i) {
            if (game.minerAction() == 2) {
                uint256 id = mockVRF.lastRequestId();
                mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("settle", id))));
            } else {
                game.mineFlip(0);
            }
        }
    }

    function _dailyRequest(uint256 nudges) private returns (uint256 id) {
        if (nudges != 0) RecyclingState.seedNudges(address(game), nudges);
        uint256 used;
        (id, used) = _mineRequest();
        assertTrue(game.rngLocked(), "daily request");
        emit log_named_uint("daily request tx gas", used);
    }

    function _middayRequest() private returns (uint256 id) {
        _finishDay();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _dailyRequest(0);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xDEAD0002);
        mockVRF.fundSubscription(1, 100e18);
        _finishDay();
        address buyer = makeAddr("vrfGasBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 used;
        (id, used) = _mineRequest();
        assertFalse(game.rngLocked(), "mid-day request");
        emit log_named_uint("midday request tx gas", used);
    }

    function test_DailyCallbackColdTransaction() public {
        uint256 id = _dailyRequest(7);
        uint256 used = _direct(id, 1_000_000);
        assertTrue(game.isRngFulfilled(), "daily word accepted");
        emit log_named_uint("daily callback cold tx gas", used);
    }

    function test_DailyCallbackBilled() public {
        uint256 id = _dailyRequest(7);
        uint256 used = _billed(id, 1_000_000);
        assertTrue(game.isRngFulfilled(), "daily word accepted");
        emit log_named_uint("daily callback billed gas", used);
    }

    function test_MiddayCallbackColdTransaction() public {
        uint256 id = _middayRequest();
        uint256 used = _direct(id, 1_000_000);
        assertEq(RecyclingState.currentWord(address(game)), 1_000_000);
        emit log_named_uint("midday callback cold tx gas", used);
    }

    function test_MiddayCallbackBilled() public {
        uint256 id = _middayRequest();
        uint256 used = _billed(id, 1_000_000);
        assertEq(RecyclingState.currentWord(address(game)), 1_000_000);
        emit log_named_uint("midday callback billed gas", used);
    }

    function test_StaleCallbackBilled() public {
        uint256 id = _dailyRequest(0);
        vm.warp(vm.getBlockTimestamp() + 21 hours);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        uint256 used = _billed(id, 1_000_000);
        assertEq(RecyclingState.currentWord(address(game)), 0, "superseded request ignored");
        emit log_named_uint("superseded callback billed gas", used);
    }

    function test_DailyRetryTransaction() public {
        _dailyRequest(0);
        vm.warp(vm.getBlockTimestamp() + 21 hours);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        emit log_named_uint("daily retry tx gas", vm.snapshotGasLastCall("vrf-retry"));
        uint256 id = mockVRF.lastRequestId();
        emit log_named_uint("retried daily callback billed gas", _billed(id, 1_000_000));
    }

    function test_MiddayRetryTransaction() public {
        _middayRequest();
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        emit log_named_uint("midday retry tx gas", vm.snapshotGasLastCall("vrf-retry"));
    }

    /// @dev The mining transaction that applies the nudged daily word (either event shape).
    function test_DailyApplyTransaction() public {
        uint256 id = _dailyRequest(7);
        mockVRF.fulfillRandomWords(id, 1_000_000);
        bytes32 current = keccak256("DailyRngApplied(uint24,uint256,uint256)");
        bytes32 legacy = keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)");
        for (uint256 i; i < 200 && game.rngLocked(); ++i) {
            vm.recordLogs();
            game.mineFlip(0);
            uint256 used = vm.snapshotGasLastCall("vrf-apply");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter == address(game) && (logs[j].topics[0] == current || logs[j].topics[0] == legacy)) {
                    emit log_named_uint("daily apply tx gas", used);
                    return;
                }
            }
        }
        revert("no daily apply");
    }

    function _swap() private returns (MockVRFCoordinator next) {
        next = new MockVRFCoordinator();
        uint256 sub = next.createSubscription();
        next.addConsumer(sub, address(game));
        vm.prank(ContractAddresses.ADMIN);
        game.updateVrfCoordinatorAndSub(address(next), sub, bytes32(uint256(1)), 300_000);
    }

    function test_DailyReissueTransaction() public {
        _dailyRequest(0);
        _swap();
        emit log_named_uint("daily reissue tx gas", vm.snapshotGasLastCall("vrf-reissue"));
    }

    function test_MiddayReissueTransaction() public {
        _middayRequest();
        _swap();
        emit log_named_uint("midday reissue tx gas", vm.snapshotGasLastCall("vrf-reissue"));
    }
}
