// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisDeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Identical benchmark source runs against the pre-migration and logical-day trees.
contract LogicalDaysGasTest is DegenesisDeployProtocol {
    address private player = address(0xA11CE);
    uint32 private playerId;

    function setUp() public {
        _deployProtocol(false);
        mockVRF.fundSubscription(1, 1_000 ether);
        playerId = _giveWalletId(player);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(player, 1_000_000);
    }

    function measure(address to, address caller, bytes calldata input) external returns (uint256 used) {
        require(msg.sender == address(this));
        bool trace = vm.envOr("LDAYS_SLOT_TRACE", false);
        if (trace) vm.startStateDiffRecording();
        vm.prank(caller);
        (bool ok, bytes memory result) = to.call(input);
        used = vm.lastCallGas().gasTotalUsed;
        if (trace) {
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            emit log_named_bytes("slot_accesses", abi.encode(to, input, accesses));
        }
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    /// @dev Both target calls share one outer transaction even under Foundry isolation.
    function measurePair(address to, address caller, bytes calldata input) external returns (uint256 first, uint256 second) {
        require(msg.sender == address(this));
        vm.prank(caller);
        (bool ok, bytes memory result) = to.call(input);
        first = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        vm.prank(caller);
        (ok, result) = to.call(input);
        second = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function test_DepositWithinTransactionColdWarm() public {
        (uint256 first, uint256 second) = this.measurePair(address(coinflip), player,
            abi.encodeCall(coinflip.depositCoinflip, (playerId, 1_000)));
        emit log_named_uint("deposit_tx_cold", first);
        emit log_named_uint("deposit_tx_warm", second);
    }

    function test_WwxrpEntryWithinTransactionColdWarm() public {
        vm.prank(ContractAddresses.GAME); wwxrp.mintPrize(player, 1_000);
        (uint256 first, uint256 second) = this.measurePair(address(wwxrp), player,
            abi.encodeCall(wwxrp.enter, (playerId, 100)));
        emit log_named_uint("wwxrp_entry_tx_cold", first);
        emit log_named_uint("wwxrp_entry_tx_warm", second);
    }

    function test_CreditBatchWithinTransactionColdWarm() public {
        uint32[] memory ids = new uint32[](16);
        uint256[] memory amounts = new uint256[](16);
        for (uint32 i; i < 16; ++i) { ids[i] = playerId + i; amounts[i] = 1_000; }
        (uint256 first, uint256 second) = this.measurePair(address(coinflip), ContractAddresses.GAME,
            abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts)));
        emit log_named_uint("credit_batch_tx_cold", first);
        emit log_named_uint("credit_batch_tx_warm", second);
    }

    function test_RebetWithinTransactionColdWarm() public {
        _settleBenchmarkDay(2, false);
        vm.prank(player); coinflip.depositCoinflip(playerId, 100_000);
        _settleBenchmarkDay(3, true);
        vm.prank(player); coinflip.claimCoinflips(playerId, 0);
        (uint256 first, uint256 second) = this.measurePair(address(coinflip), player,
            abi.encodeCall(coinflip.depositCoinflip, (playerId, 1_000)));
        emit log_named_uint("rebet_tx_cold", first);
        emit log_named_uint("rebet_tx_warm", second);
    }

    function test_CarryExitWithinTransactionColdWarm() public {
        _carryPosition();
        (uint256 first, uint256 second) = this.measurePair(address(coinflip), player,
            abi.encodeCall(coinflip.claimCoinflipCarry, (playerId, 1_000)));
        emit log_named_uint("carry_exit_tx_cold", first);
        emit log_named_uint("carry_exit_tx_warm", second);
    }

    function test_DepositColdWarm() public {
        bytes memory data = abi.encodeCall(coinflip.depositCoinflip, (playerId, 1_000));
        emit log_named_uint("deposit_cold", this.measure(address(coinflip), player, data));
        emit log_named_uint("deposit_warm", this.measure(address(coinflip), player, data));
    }

    function test_CreditBatchColdWarm() public {
        uint32[] memory ids = new uint32[](16);
        uint256[] memory amounts = new uint256[](16);
        for (uint32 i; i < 16; ++i) { ids[i] = playerId + i; amounts[i] = 1_000; }
        bytes memory data = abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts));
        emit log_named_uint("credit_batch_cold", this.measure(address(coinflip), ContractAddresses.GAME, data));
        emit log_named_uint("credit_batch_warm", this.measure(address(coinflip), ContractAddresses.GAME, data));
    }

    function test_FreshDailyRequest() public {
        vm.warp(block.timestamp + 1 days);
        uint256 used = this.measure(address(game), player, abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        assertTrue(game.rngLocked());
        emit log_named_uint("fresh_daily_request", used);
    }

    function test_DegenesisPurchase() public {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        vm.warp(block.timestamp + 1 hours);
        // Credit is an input to this purchase, independent of its funding transaction.
        vm.store(address(game), keccak256(abi.encode(playerId, uint256(14))), bytes32(uint256(1 ether)));
        vm.deal(player, 1 ether);
        emit log_named_uint("degenesis_purchase", this.measurePurchase());
    }

    function measurePurchase() external returns (uint256 used) {
        require(msg.sender == address(this));
        vm.prank(player);
        game.buyDegenesisBox{value: 0.1 ether}(playerId, 0.1 ether);
        used = vm.lastCallGas().gasTotalUsed;
    }

    function test_PostDegenesisDailyRequest() public {
        // Same production request with the sale already closed; no bonus timestamp write.
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        header = (header & ~(uint256(0xffffff) << 24)) | (uint256(9) << 24);
        header = (header & ~(uint256(0xff) << 216)) | (uint256(7) << 216);
        vm.store(address(game), bytes32(0), bytes32(header));
        uint256 cf = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((cf & ~(uint256(0xffffff) << 176)) | (uint256(9) << 176)));
        // Baseline daily eligibility still follows the calendar day.
        vm.warp((uint256(9) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        (bool logical,) = address(coinflip).staticcall(abi.encodeWithSignature("requestedDailyIdx()"));
        uint8 requestAction = logical ? 16 : 17;
        for (uint256 i; i < 100 && game.nextMinerAction() != requestAction; ++i) {
            game.mineFlip(type(uint32).max);
        }
        assertEq(game.nextMinerAction(), requestAction, "prepare the request without consuming it");
        emit log_named_uint("post_degenesis_request", this.measure(address(game), player,
            abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        assertTrue(game.rngLocked());
    }

    function test_CompletionCertificate() public {
        // An authenticated published and fully drained daily read, with the daily phase unlocked.
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        header = (header & ~(uint256(0xffffff) << 24)) | (uint256(2) << 24);
        header |= (uint256(1) << 192) | (uint256(1) << 232) | (uint256(1) << 255);
        header &= ~((uint256(1) << 248) | (uint256(1) << 254) | (uint256(0xff) << 152));
        vm.store(address(game), bytes32(0), bytes32(header));
        vm.store(address(game), bytes32(uint256(3)), bytes32(uint256(777)));
        uint256 session = uint256(vm.load(address(game), bytes32(uint256(5))));
        session = (session & ~uint256(0xffffffff)) | 2;
        session = (session & ~(uint256(0xffffff) << 216)) | (uint256(2) << 216);
        vm.store(address(game), bytes32(uint256(5)), bytes32(session));
        vm.warp(block.timestamp + 1 days);
        emit log_named_uint("completion_certificate", this.measure(address(game), player, abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        assertTrue(game.rngComplete());
    }

    function test_TerminalEntry() public {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        assertTrue(game.rngLocked());
        vm.warp(block.timestamp + 14 days);
        emit log_named_uint("terminal_entry", this.measure(address(game), player, abi.encodeWithSignature("mineFlip(uint32)", uint32(0))));
        assertTrue(game.livenessTriggered());
    }

    function _settleBenchmarkDay(uint24 day, bool win) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32((header & ~(uint256(0xffffff) << 24)) | (uint256(day) << 24)));
        uint256 cf = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((cf & ~(uint256(0xffffff) << 176)) | (uint256(day) << 176)));
        uint256 clocks = uint256(vm.load(address(game), bytes32(uint256(13))));
        vm.store(address(game), bytes32(uint256(13)), bytes32((clocks & ~(uint256(type(uint48).max) << 128)) | (block.timestamp << 128)));
        vm.prank(ContractAddresses.GAME);
        coinflip.processCoinflipPayouts(0, win ? 777 : 778, day);
    }

    function test_ClaimableRebetColdWarm() public {
        _settleBenchmarkDay(2, false);
        vm.prank(player); coinflip.depositCoinflip(playerId, 100_000);
        _settleBenchmarkDay(3, true);
        vm.prank(player); coinflip.claimCoinflips(playerId, 0);
        bytes memory data = abi.encodeCall(coinflip.depositCoinflip, (playerId, 1_000));
        emit log_named_uint("rebet_cold", this.measure(address(coinflip), player, data));
        emit log_named_uint("rebet_warm", this.measure(address(coinflip), player, data));
    }

    function _carryPosition() private {
        _settleBenchmarkDay(2, false);
        emit log_named_uint("autorebuy_enable", this.measure(address(coinflip), player,
            abi.encodeCall(coinflip.setCoinflipAutoRebuy, (playerId, true, 0))));
        vm.prank(player); coinflip.depositCoinflip(playerId, 100_000);
        _settleBenchmarkDay(3, true);
    }

    function test_CarryExitColdWarm() public {
        _carryPosition();
        bytes memory data = abi.encodeCall(coinflip.claimCoinflipCarry, (playerId, 1_000));
        emit log_named_uint("carry_exit_cold", this.measure(address(coinflip), player, data));
        emit log_named_uint("carry_exit_warm", this.measure(address(coinflip), player, data));
    }

    function test_AutoRebuyMutation() public {
        _carryPosition();
        emit log_named_uint("autorebuy_take_profit", this.measure(address(coinflip), player,
            abi.encodeCall(coinflip.setCoinflipAutoRebuyTakeProfit, (playerId, 200_000))));
        emit log_named_uint("autorebuy_disable", this.measure(address(coinflip), player,
            abi.encodeCall(coinflip.setCoinflipAutoRebuy, (playerId, false, 0))));
    }
}
