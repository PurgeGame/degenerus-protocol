// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract ColdSubscriberSeeder is DegenerusGame, WalletSeed {
    /// @dev The all-skip gas fixture also places the two permanent protocol
    /// subscribers on their already-bought guard for the measured next day.
    function prepareProtocolSkips() external {
        uint24 nextDay = _simulatedDayIndex() + 1;
        _subOf[_seedWallet(ContractAddresses.VAULT)].lastAutoBoughtDay = nextDay;
        _subOf[_seedWallet(ContractAddresses.SDGNRS)].lastAutoBoughtDay = nextDay;
    }
    /// @dev Run the engine's live human-box worker without consuming independent stamped AFKING boxes.
    function finishIndexedRead() external {
        require(!rngLockedFlag, "setup daily still locked");
        for (uint256 i; i < 100 && !humanReadComplete; ++i) {
            (bool ok, bytes memory ret) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
                abi.encodeWithSelector(IGameAfkingModule.runHumanBoxWork.selector, gasleft())
            );
            if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        }
        require(humanReadComplete, "indexed read did not complete");
    }

    /// @dev Run the engine's box stages (AFKing, then human boxes) through their live workers while
    ///      either is the due read consumer, without the engine's later stages (a mid-day request
    ///      would reshape the measured fixture).
    function runDueBoxStages() external {
        for (uint256 i; i < 100; ++i) {
            uint8 stage = _rngConsumerStage();
            bytes4 selector;
            if (stage == 2) selector = IGameAfkingModule.runAfkingWork.selector;
            else if (stage == 3) selector = IGameAfkingModule.runHumanBoxWork.selector;
            else return;
            (bool ok, bytes memory ret) =
                ContractAddresses.GAME_AFKING_MODULE.delegatecall(abi.encodeWithSelector(selector, gasleft()));
            if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
            if (!abi.decode(ret, (MineFlipGas.Result)).progressed) return;
        }
    }

    function useMatureLevel() external {
        level = 110;
        levelPrizePool[110] = 1000 ether;
    }

    function seedSplitBalances(address[] calldata players) external {
        for (uint256 i; i < players.length; ++i) {
            _creditClaimable(_seedWallet(players[i]), 0.001 ether + 1);
        }
        _creditClaimable(_seedWallet(ContractAddresses.SDGNRS), 1 ether);
        claimablePool += uint128(players.length * (0.001 ether + 1) + 1 ether);
    }
}

/// @dev Setup completes before the measured transaction, including every funding/storage write.
abstract contract ColdSubscriberFixture is DeployProtocol {
    uint256 internal constant INTRINSIC = 21_192;
    uint256 internal constant REALISTIC_ALLOWANCE = 10_000_000;
    uint256 internal constant CHUNK_GAS_TARGET = 10_000_000;
    bytes32 internal constant ADVANCE_EVENT = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant DELIVERED_EVENT = keccak256("AfkingDelivered(uint32,uint256)");
    bytes32 internal constant EXPIRED_EVENT = keccak256("SubscriptionExpired(uint32,uint8)");
    bytes32 internal constant SKIPPED_EVENT = keccak256("PlayerSkipped(uint32,uint8)");

    function _mode() internal pure virtual returns (uint8);

    function _split() internal pure virtual returns (bool) {
        return false;
    }

    function _complete() internal pure virtual returns (bool) {
        return false;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 1_000_000 ether);
        vm.deal(address(this), 100_000 ether);
        _settle();
        _finishReadConsumers();

        uint8 mode = _mode();
        // At mature levels subscriptions create stamped daily boxes, separate from
        // read-cohort indexed covers; their pending-box skip can span a daily request.
        if (mode == 3) {
            bytes memory original = address(game).code;
            vm.etch(address(game), type(ColdSubscriberSeeder).runtimeCode);
            ColdSubscriberSeeder(payable(address(game))).useMatureLevel();
            vm.etch(address(game), original);
        }
        uint256 n = mode == 0 ? 320 : mode == 1 ? 125 : mode == 2 ? 260 : 1300;
        // The per-level sDGNRS whale purchase takes 700 of the 2,500-unit budget on this day.
        if (_complete()) n = mode == 1 ? 85 : 180;
        address[] memory players = new address[](n);
        for (uint256 i; i < n; ++i) {
            address player = address(uint160(0xA5700000 + i));
            players[i] = player;
            _giveWalletId(player);
            uint256 seat;
            if (i < 1000) {
                seat = _grantSeat(player);
            } else {
                _markSeatEligible(player);
                vm.prank(ContractAddresses.VAULT);
                afkingSubToken.vaultMintSeats(player, 1);
                seat = _seatOf(player);
            }
            address source = _split() ? address(uint160(0xA5800000 + i)) : player;
            uint32 playerId = game.walletIdOf(player);
            uint32 sourceId = _split() ? _giveWalletId(source) : playerId;
            game.depositAfkingFunding{value: 50 ether}(sourceId);
            if (_split()) {
                vm.prank(source);
                game.setAfkingFundingApproval(sourceId, playerId, true);
            }
            vm.prank(player);
            game.subscribe(0, _split(), mode == 1, 1, _split() ? sourceId : 0, seat);
        }
        if (mode != 3) {
            bytes memory live = address(game).code;
            vm.etch(address(game), type(ColdSubscriberSeeder).runtimeCode);
            ColdSubscriberSeeder(payable(address(game))).runDueBoxStages();
            vm.etch(address(game), live);
        } else {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            _settle();
        }
        if (mode == 0) {
            for (uint256 i; i < n; ++i) {
                uint256 amount = game.afkingFundingOf(players[i]);
                vm.prank(players[i]);
                game.withdrawAfkingFunding(0, amount);
            }
        }
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdSubscriberSeeder).runtimeCode);
        ColdSubscriberSeeder(payable(address(game))).useMatureLevel();
        if (mode == 3) {
            ColdSubscriberSeeder(payable(address(game))).finishIndexedRead();
            ColdSubscriberSeeder(payable(address(game))).prepareProtocolSkips();
        }
        if (_split()) ColdSubscriberSeeder(payable(address(game))).seedSplitBalances(players);
        vm.etch(address(game), original);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _settle() private {
        for (uint256 i; i < 240; ++i) {
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256("cold-subscriber-setup")) | 1);
            }
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip(0);
        }
        revert("setup did not settle");
    }

    /// @dev The engine keeps admitting chunks while the supplied gas covers the next declared
    ///      bound, so a call's total mirrors its own allowance and is not bounded here. Asserted:
    ///      (1) every call at a realistic 10M allowance succeeds and progresses, and those calls
    ///      complete the subscriber work and the continuation; (2) driven again from the same
    ///      state with each call at the exact minimum allowance that admits its next chunk, every
    ///      call succeeds, so each admitted chunk fits its declared admission (bound plus tail:
    ///      a chunk over it would fail the meter's WorkGasBound check or run out of gas), each
    ///      admission requirement and each measured chunk is <= 10M, and the same work completes.
    function _check(bytes32 workEvent, uint256 minimum, uint256 maximum) internal {
        uint256 snap = vm.snapshotState();
        (uint256 work, uint8 stage, uint256 calls,) = _drive(workEvent, false);
        emit log_named_uint("realistic_10m_calls", calls);
        emit log_named_uint("completed_items", work);
        assertEq(stage, _complete() ? 1 : 11, "full subscriber work and expected continuation must run");
        assertGe(work, minimum, "fixture did not exercise the full subscriber set");
        assertLe(work, maximum, "subscriber work exceeded its item count");
        vm.revertToState(snap);

        uint256 maxChunk;
        (work, stage, calls, maxChunk) = _drive(workEvent, true);
        emit log_named_uint("admitted_chunks", calls);
        emit log_named_uint("max_chunk_gas_including_intrinsic", maxChunk);
        assertEq(stage, _complete() ? 1 : 11, "chunked subscriber work reaches the same continuation");
        assertGe(work, minimum, "chunked drive did not complete the subscriber set");
        assertLe(work, maximum, "chunked subscriber work exceeded its item count");
    }

    /// @dev Calls mineFlip until the expected continuation's Advance marker is emitted. Every
    ///      call must succeed and change Game storage. `tight` runs each call at its exact
    ///      minimum admission allowance and bounds the admission and the measured chunk at 10M.
    function _drive(bytes32 workEvent, bool tight)
        private returns (uint256 work, uint8 stage, uint256 calls, uint256 maxChunk)
    {
        uint8 target = _complete() ? 1 : 11;
        stage = 255;
        for (; calls < 2000 && stage != target; ++calls) {
            uint256 allowance = tight ? _minimumAllowance() : REALISTIC_ALLOWANCE;
            if (tight) assertLe(allowance, CHUNK_GAS_TARGET, "next chunk admitted under a realistic 10M allowance");
            vm.recordLogs();
            vm.startStateDiffRecording();
            uint256 before = gasleft();
            game.mineFlip{gas: allowance}(0);
            uint256 used = before - gasleft() + INTRINSIC;
            assertTrue(_storageChanged(vm.stopAndReturnStateDiff()), "a successful call makes engine progress");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
                if (logs[i].topics[0] == workEvent) ++work;
                if (logs[i].topics[0] == ADVANCE_EVENT) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
            if (tight) {
                assertLe(used, CHUNK_GAS_TARGET, "one admitted chunk stays <= 10M");
                if (used > maxChunk) maxChunk = used;
            }
        }
    }

    /// @dev Exact (5k-granular) smallest allowance that admits the next chunk, probed on a
    ///      snapshot. Every smaller allowance must be refused with InsufficientExecutionGas.
    function _minimumAllowance() private returns (uint256 hi) {
        uint256 lo = 200_000;
        hi = REALISTIC_ALLOWANCE;
        uint256 snap = vm.snapshotState();
        (bool ok,) = address(game).call{gas: hi}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        vm.revertToState(snap);
        assertTrue(ok, "next chunk admitted under a realistic 10M allowance");
        while (hi - lo > 5_000) {
            uint256 mid = (lo + hi) / 2;
            bytes memory err;
            (ok, err) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            vm.revertToState(snap);
            if (ok) {
                hi = mid;
            } else {
                assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "a short allowance is refused, nothing else");
                lo = mid;
            }
        }
    }

    /// @dev True when a non-reverted frame changed a Game storage word (module work runs by
    ///      delegatecall, so the written storage account is the Game).
    function _storageChanged(Vm.AccountAccess[] memory accesses) private view returns (bool) {
        for (uint256 a; a < accesses.length; ++a) {
            if (accesses[a].reverted) continue;
            for (uint256 k; k < accesses[a].storageAccesses.length; ++k) {
                Vm.StorageAccess memory w = accesses[a].storageAccesses[k];
                if (w.account == address(game) && w.isWrite && !w.reverted && w.previousValue != w.newValue) return true;
            }
        }
        return false;
    }
}

contract AdvanceColdSplitLootboxSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 2;
    }

    function _split() internal pure override returns (bool) {
        return true;
    }

    function _complete() internal pure override returns (bool) {
        return true;
    }

    function test_ColdSplitLootboxesAndRngRequest() public {
        _check(DELIVERED_EVENT, 181, 181);
    }
}

