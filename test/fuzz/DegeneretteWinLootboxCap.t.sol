// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";

/// @dev Test overlay: exercises real module bytecode in the Game's storage and forwards
///      ordinary Game calls to its original runtime. No storage-layout slot constants.
contract WinLootboxCapProbe is DegenerusGameStorage, WalletSeed {
    address private constant ORIGINAL = address(0xCA9001);

    function seedAllowance(address player, uint24 key, uint256 used) external {
        _setLootboxEvUsedFor(_seedWallet(player), key, used);
    }

    function allowanceUsed(address player, uint24 key) external view returns (uint256) {
        return _lootboxEvUsedFor(_walletIdOf(player), key);
    }

    function allowanceWord(address player) external view returns (uint256) {
        return lootboxEvCapPacked[_walletIdOf(player)];
    }

    function seedLevel(uint24 lvl) external {
        level = lvl;
    }

    function seedFuturePool() external {
        _setPrizePools(0, uint128(1_000_000 ether));
    }

    function walletId(address who) external returns (uint32) {
        return _seedWallet(who);
    }

    function seedBetScore(uint48 index, uint256 pos, uint16 score) external {
        uint256 slot = _betSlot(index & 1, pos);
        uint256 word;
        assembly ("memory-safe") { word := sload(slot) }
        word = (word & ~(uint256(type(uint16).max) << 172)) | (uint256(score) << 172);
        assembly ("memory-safe") { sstore(slot, word) }
    }

    function dispatch(address module, bytes calldata payload) external payable {
        (bool ok, bytes memory data) = module.delegatecall(payload);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    fallback() external payable {
        address original = ORIGINAL;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), original, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

contract DegeneretteWinLootboxCap is DeployProtocol {
    bytes4 private constant NORMAL = bytes4(keccak256("resolveLootboxDirect(address,uint32,uint256,uint256,uint16)"));
    bytes4 private constant WIN = bytes4(keccak256("resolveDegeneretteLootboxDirect(address,uint32,uint256,uint256,uint16)"));
    bytes32 private constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    uint16 private constant MAX_SCORE = 30_000;
    uint8 private constant SYMBOL = 9;
    uint48 private constant INDEX = 1;
    address private player;
    uint32 private playerId;
    WinLootboxCapProbe private probe;
    uint256 private directWord;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(0xCA9001), address(game).code);
        WinLootboxCapProbe overlay = new WinLootboxCapProbe();
        vm.etch(address(game), address(overlay).code);
        probe = WinLootboxCapProbe(payable(address(game)));
        player = makeAddr("winCapPlayer");
        playerId = probe.walletId(player);
        // Ticket rolls emit LootBoxOpened even for a cold bust. Spin rolls use BoxSpin.
        for (uint256 word = 1; ; ++word) {
            uint256 seed = uint256(keccak256(abi.encode(word, uint256(playerId))));
            if (uint16(seed >> 40) % 20 < 8) { directWord = word; break; }
        }
        vm.deal(player, 10_000 ether);
        vm.deal(address(this), 10 ether);
        probe.seedFuturePool();
        RecyclingState.seedWriteBuffer(address(game), INDEX);
        vm.prank(address(game));
        coin.mintForGame(player, 1_000_000 ether);
    }

    function _resolve(bytes4 selector, uint256 amount, uint16 score) private returns (uint256 scaled, uint24 target) {
        vm.recordLogs();
        probe.dispatch(address(lootboxModule), abi.encodeWithSelector(selector, player, playerId, amount, directWord, score));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == OPENED) {
                (scaled, target,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                ++count;
            }
        }
        assertEq(count, amount == 0 ? 0 : 1, "one resolution per awarded box");
    }

    function test_LargeWinUses50EthCeilingAndExhaustsNormalAllowance() public {
        (uint256 scaled,) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertEq(scaled, 82.5 ether);
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
        (scaled,) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertEq(scaled, 60 ether, "exhausted means neutral, not another 40 ETH");
    }

    function test_PartiallyUsedAllowanceIsDeductedFrom50Eth() public {
        probe.seedAllowance(player, 1, 9 ether);
        (uint256 scaled,) = _resolve(WIN, 45 ether, MAX_SCORE);
        assertEq(scaled, 63.45 ether);
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
    }

    function test_ExactCeilingAndOneWeiOfRemainingAllowance() public {
        (uint256 scaled,) = _resolve(WIN, 50 ether, MAX_SCORE);
        assertEq(scaled, 72.5 ether);
        probe.seedAllowance(player, 1, 10 ether - 1);
        (scaled,) = _resolve(WIN, 50 ether, MAX_SCORE);
        assertEq(scaled, 50 ether + (uint256(40 ether + 1) * 4500) / 10000);
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
    }

    function test_SmallWinsConsumeAllowanceBeforeOneExceptionalDraw() public {
        probe.seedAllowance(player, 1, 5 ether);
        (uint256 scaled,) = _resolve(WIN, 2 ether, MAX_SCORE);
        assertEq(scaled, 2.9 ether);
        assertEq(probe.allowanceUsed(player, 1), 7 ether);
        (scaled,) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertEq(scaled, 79.35 ether);
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
        (scaled,) = _resolve(NORMAL, 2 ether, MAX_SCORE);
        assertEq(scaled, 2 ether, "ordinary box shares exhausted allowance");
    }

    function test_NormalRecirculationKeeps10EthCap() public {
        probe.seedAllowance(player, 1, 9 ether);
        (uint256 scaled,) = _resolve(NORMAL, 45 ether, MAX_SCORE);
        assertEq(scaled, 45.45 ether);
        (scaled,) = _resolve(WIN, 45 ether, MAX_SCORE);
        assertEq(scaled, 45 ether, "normal resolution consumed the remaining allowance");
    }

    function test_NeutralPenaltyAndZeroAmountDoNotConsumeAllowance() public {
        probe.seedAllowance(player, 1, 9 ether);
        uint256 beforeWord = probe.allowanceWord(player);
        (uint256 scaled,) = _resolve(WIN, 45 ether, 60);
        assertEq(scaled, 45 ether);
        (scaled,) = _resolve(WIN, 45 ether, 0);
        assertEq(scaled, 40.5 ether);
        _resolve(WIN, 0, MAX_SCORE);
        assertEq(probe.allowanceWord(player), beforeWord);
    }

    function test_FreshLevelPreservesOtherAllowanceWindow() public {
        probe.seedAllowance(player, 1, 10 ether);
        probe.seedLevel(1);
        (uint256 scaled,) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertEq(scaled, 82.5 ether);
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
        assertEq(probe.allowanceUsed(player, 2), 10 ether);
    }

    function test_AllowanceDoesNotChangeCommittedTargetLevel() public {
        uint256 snapshot = vm.snapshotState();
        (, uint24 eligibleTarget) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertTrue(vm.revertToState(snapshot));
        probe.seedAllowance(player, 1, 10 ether);
        (, uint24 exhaustedTarget) = _resolve(WIN, 60 ether, MAX_SCORE);
        assertEq(eligibleTarget, exhaustedTarget);
    }

    function test_DirectModuleCallRejectsValueEvenForZeroAmount() public {
        vm.expectRevert(bytes4(keccak256("OnlyDelegatecall()")));
        (bool ok,) = address(lootboxModule).call{value: 1 ether}(
            abi.encodeWithSelector(WIN, player, playerId, uint256(0), uint256(1), MAX_SCORE)
        );
        assertTrue(ok); // expectRevert makes the observed low-level call succeed
    }

    /// @dev A word where spin 0 scores 6 or more and the win boxes of bets 1 and 2 roll a ticket
    ///      outcome (a spin roll emits BoxSpin instead of LootBoxOpened).
    function _winningWord() private view returns (uint256 word) {
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encode("win-cap", k)));
            (uint8 score,) = Ref.score(
                Ref.player(word, uint32(INDEX), SYMBOL, 0, false),
                Ref.house(word, uint32(INDEX), 0, false));
            if (score < 6) continue;
            bool tickets = true;
            for (uint256 betId = 1; betId <= 2; ++betId) {
                uint256 boxWord = uint256(keccak256(abi.encode(word, betId)));
                uint256 seed = uint256(keccak256(abi.encode(boxWord, uint256(playerId))));
                if (uint16(seed >> 40) % 20 >= 8) tickets = false;
            }
            if (tickets) return word;
        }
    }

    function _place(uint8 spins, uint16 score) private {
        vm.prank(player);
        game.placeDegeneretteBet{value: uint256(spins) * 10 ether}(0, 0, 10 ether, spins, SYMBOL);
        uint64 id = DQ.lastBetId(vm, address(game), INDEX);
        probe.seedBetScore(INDEX, id - 1, score);
    }

    /// @dev Deliver the winning word for the sealed cohort at INDEX on a sealed day (dailyIdx =
    ///      today, tickets drained), as a fulfilled mid-day request leaves it: the cohort's read
    ///      consumers are then the engine's only work.
    function _land() private {
        RecyclingState.seedWord(address(game), INDEX, bytes32(_winningWord()));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Bets resolve only as the engine's Degenerette read consumer (mineFlip).
    function _sweepAmounts() private returns (uint256[] memory amounts) {
        _land();
        vm.recordLogs();
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == OPENED) ++count;
        amounts = new uint256[](count);
        count = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == OPENED) {
                (amounts[count],,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                ++count;
            }
        }
    }

    function test_PurchasedBetRoutesToExceptionalCapAndQueuedFollowupIsNeutral() public {
        _place(1, MAX_SCORE);
        _place(1, MAX_SCORE);
        uint256[] memory amounts = _sweepAmounts();
        assertEq(amounts.length, 2);
        assertGt(amounts[1], 50 ether, "fixture produces a large win box");
        assertEq(amounts[0], amounts[1] + 22.5 ether, "only first queued win gets bonus");
        assertEq(probe.allowanceUsed(player, 1), 10 ether);
    }

    function test_AllowanceIsReadAtSettlementAfterPlacement() public {
        _place(1, MAX_SCORE);
        uint256 snapshot = vm.snapshotState();
        uint256[] memory eligible = _sweepAmounts();
        assertTrue(vm.revertToState(snapshot));
        probe.seedAllowance(player, 1, 10 ether);
        uint256[] memory exhausted = _sweepAmounts();
        assertEq(eligible[0], exhausted[0] + 22.5 ether);
    }

    function test_MultiSpinBetKeepsOneBoxAndOneCeiling() public {
        _place(25, MAX_SCORE);
        uint256 snapshot = vm.snapshotState();
        uint256[] memory eligible = _sweepAmounts();
        assertEq(eligible.length, 1);
        assertTrue(vm.revertToState(snapshot));
        probe.seedAllowance(player, 1, 10 ether);
        uint256[] memory exhausted = _sweepAmounts();
        assertEq(exhausted.length, 1);
        assertEq(eligible[0], exhausted[0] + 22.5 ether);
    }

    function testFuzz_WinCapMatchesReference(uint256 used, uint256 amount, uint16 score) public {
        used = bound(used, 0, 10 ether);
        amount = bound(amount, 1 gwei, 100 ether);
        score = uint16(bound(score, 0, 30_000));
        probe.seedAllowance(player, 1, used);
        probe.seedAllowance(player, 2, 3 ether);
        uint256 multiplier;
        if (score <= 60) multiplier = 9000 + uint256(score) * 1000 / 60;
        else if (score <= 400) multiplier = 10000 + uint256(score - 60) * 3950 / 340;
        else if (score <= 500) multiplier = 13950 + uint256(score - 400) * 440 / 100;
        else multiplier = 14390 + uint256(score - 500) * 110 / 29500;
        uint256 expectedUsed = used;
        uint256 expected = amount * multiplier / 10000;
        if (multiplier > 10000) {
            uint256 adjusted = used == 10 ether ? 0 : (amount < 50 ether - used ? amount : 50 ether - used);
            expected = adjusted * multiplier / 10000 + amount - adjusted;
            expectedUsed = used + adjusted > 10 ether ? 10 ether : used + adjusted;
        }
        (uint256 scaled,) = _resolve(WIN, amount, score);
        assertEq(scaled, expected);
        assertEq(probe.allowanceUsed(player, 1), expectedUsed);
        assertEq(probe.allowanceUsed(player, 2), 3 ether, "other packed window preserved");
    }

    function _gasSweep(string memory name, uint8 spins, uint16 score, uint256 used) private {
        _gasSweepWithStake(name, spins, score, used, 10 ether);
    }

    function _gasSweepWithStake(string memory name, uint8 spins, uint16 score, uint256 used, uint128 stake) private {
        vm.prank(player);
        game.placeDegeneretteBet{value: uint256(spins) * stake}(0, 0, stake, spins, SYMBOL);
        probe.seedBetScore(INDEX, 0, score);
        probe.seedAllowance(player, 1, used);
        _land();
        vm.cool(address(game));
        vm.cool(address(lootboxModule));
        vm.cool(address(degeneretteModule));
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip();
        emit log_named_uint(name, beforeGas - gasleft());
        assertEq(_resolvedCount(vm.getRecordedLogs()), 1, "the measured call resolved the bet");
    }

    function testGas_Win1Spin() public { _gasSweep("cap_win_1spin", 1, MAX_SCORE, 0); }
    function testGas_Win25Spins() public { _gasSweep("cap_win_25spins", 25, MAX_SCORE, 0); }
    function testGas_Exhausted() public { _gasSweep("cap_exhausted", 1, MAX_SCORE, 10 ether); }
    function testGas_Neutral() public { _gasSweep("cap_neutral", 1, 60, 0); }
    function testGas_Penalty() public { _gasSweep("cap_penalty", 1, 0, 0); }
    function testGas_SmallWin() public { _gasSweepWithStake("cap_small_win", 1, MAX_SCORE, 0, 0.005 ether); }

    function testGas_WarmBatch() public {
        for (uint256 i; i < 11; ++i) _place(1, MAX_SCORE);
        _land();
        vm.cool(address(game));
        vm.cool(address(lootboxModule));
        vm.cool(address(degeneretteModule));
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip();
        uint256 used = beforeGas - gasleft();
        assertEq(_resolvedCount(vm.getRecordedLogs()), 11);
        emit log_named_uint("cap_batch_11", used);
    }

    function testGas_Placement() public {
        vm.prank(player);
        uint256 beforeGas = gasleft();
        game.placeDegeneretteBet{value: 10 ether}(0, 0, 10 ether, 1, SYMBOL);
        emit log_named_uint("cap_placement", beforeGas - gasleft());
    }

    function testGas_NormalRecirculation() public {
        vm.cool(address(game));
        vm.cool(address(lootboxModule));
        uint256 beforeGas = gasleft();
        probe.dispatch(address(lootboxModule), abi.encodeWithSelector(NORMAL, player, playerId, 60 ether, uint256(12345), MAX_SCORE));
        emit log_named_uint("cap_normal_recirc", beforeGas - gasleft());
    }

    function _resolvedCount(Vm.Log[] memory logs) private pure returns (uint256 n) {
        bytes32 resolved = keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == resolved) ++n;
    }
}
