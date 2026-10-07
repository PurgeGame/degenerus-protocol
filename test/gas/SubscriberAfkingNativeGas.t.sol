// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev A full production facade with controlled, committed native-worker inputs.
///      The measured calls delegate to the unmodified production AFKing module.
contract SubscriberNativeGasHost is DegenerusGame, WalletSeed {
    function prepare(bool whale) external {
        uint24 day = _simulatedDayIndex();
        level = 4;
        dailyIdx = day - 1;
        _afkingResetDay = day;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        delete _subscribers;
        subsFullyProcessed = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        _sdgnrsBonusLevel = whale ? 0 : level;
        // This fixture skips the first four levels; retire their bootstrap far-future headers
        // before the real purchase binds levels 101..104, and both slot sides of their near
        // queues, whose level-parity physical roots the current level's queues recycle (a
        // still-occupied root refuses a new level with E()).
        for (uint24 oldLevel = 1; oldLevel <= 4; ++oldLevel) {
            uint24[3] memory keys = [_tqFarFutureKey(oldLevel), oldLevel, oldLevel | TICKET_SLOT_BIT];
            for (uint256 k; k < 3; ++k) {
                uint256[] storage q = ticketQueue[_ticketQueueStorageKey(keys[k])];
                assembly ("memory-safe") { sstore(q.slot, 0) }
            }
        }
        // The genesis holders' near cohorts of the skipped levels retire with those queues: a
        // parity lane still holding level-1/2 balances refuses a level-5/6 write with E().
        delete ticketPending[_walletIdOf(ContractAddresses.SDGNRS)];
        delete ticketPending[_walletIdOf(ContractAddresses.VAULT)];
        if (whale) {
            _creditClaimable(_seedWallet(ContractAddresses.SDGNRS), 2_000 ether);
            claimablePool += 2_000 ether;
        }
    }

    /// @param mode 0=self funded ticket,1=claimable ticket,2=external mixed funding,
    ///             3=unfunded expiry,4=cancelled tombstone,5=maximum box stamp.
    function add(address player, uint8 mode) external {
        uint32 id = _seedWallet(player);
        _subscribers.push(id);
        Sub storage sub = _subOf[id];
        sub.setPosition = uint32(_subscribers.length);
        uint24 yesterday = _afkingResetDay - 1;
        sub.dailyQuantity = mode == 4 ? 0 : 255;
        sub.flags = mode == 5 ? 0 : 4;
        sub.lastAutoBoughtDay = yesterday;
        sub.lastOpenedDay = yesterday;
        sub.afkingStartDay = yesterday;
        sub.afkCoveredThroughDay = yesterday;
        if (mode == 0 || mode == 5) _creditAfkingValue(_seedWallet(player), 100 ether);
        if (mode == 1) {
            sub.flags |= 2;
            _creditClaimable(_seedWallet(player), 100 ether);
            claimablePool += 100 ether;
        }
        if (mode == 2) {
            address funder = address(uint160(player) + 0x100000);
            sub.flags |= 1;
            _fundingSourceOf[id] = _seedWallet(funder);
            _creditAfkingValue(_seedWallet(funder), 1 ether);
            _creditClaimable(_seedWallet(player), 100 ether);
            claimablePool += 100 ether;
        }
    }

    function openFixture(address player, uint256 word) external {
        uint24 day = _simulatedDayIndex();
        level = 299;
        dailyIdx = day;
        rngRequestDay = day;
        rngWordCurrent = word < 2 ? 99 : word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        subsFullyProcessed = true;
        uint32 id = _seedWallet(player);
        delete _subscribers;
        _subscribers.push(id);
        _subOpenCursor = 0;
        _pendingBoxCount = 1;
        Sub storage sub = _subOf[id];
        sub.setPosition = 1;
        sub.lastAutoBoughtDay = day;
        sub.lastOpenedDay = day - 1;
        sub.amount = 61_200; //255 tickets at the maximum0.24ETH price.
        sub.score = 305; //Maximum useful activity-score multiplier.
        // All following destinations are newly funded, cold far-future queues.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(q.slot, 0) }
        }
        _setPrizePools(1_000 ether, 10_000 ether);
    }

    // Fixture-only ownership transition; liquidation tests exercise the authorized sale itself.
    function acquireForTest(address player, bool child) external {
        uint32 id = _walletIdOf(player);
        if (child) {
            uint32 parent = _seedWallet(address(0xAC0123));
            wallets[id] = uint256(parent) << 160;
            id = parent;
        }
        wallets[id] |= uint256(SDGNRS_WALLET_ID) << 160;
    }
    function nextPass() external {
        _afkingResetDay = _simulatedDayIndex();
        _subCursor = 0;
        subsFullyProcessed = false;
    }

    function subWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", _afkingResetDay, allowance));
    }
    function openWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runAfkingWork(uint256)", allowance));
    }
    function pendingBoxes() external view returns (uint256) { return _pendingBoxCount; }
    function memberCount() external view returns (uint256) { return _subscribers.length; }
    function delivered(address player) external view returns (uint24, uint24) {
        return (_subOf[_walletIdOf(player)].lastAutoBoughtDay, _subOf[_walletIdOf(player)].lastOpenedDay);
    }
    function claimableOf(address player) external view returns (uint256) { return _claimableOf(_walletIdOf(player)); }
    function pendingEntries(address player, uint24 lvl) external view returns (uint256) {
        return _entriesOwedTotal(lvl, _walletIdOf(player));
    }
    function _work(bytes memory data) private returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (MineFlipGas.Result));
    }
}

contract SubscriberAfkingNativeGasTest is DeployProtocol {
    // Benchmark guideline only; runtime admission uses the caller's remaining gas.
    uint256 private constant STEP_GAS_TARGET = 10_000_000;
    SubscriberNativeGasHost private host;
    address private constant PLAYER = address(0xA11CE123);
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.etch(address(game), type(SubscriberNativeGasHost).runtimeCode);
        host = SubscriberNativeGasHost(payable(address(game)));
        vm.deal(address(game), 50_000 ether);
    }
    function _cool() private {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(address(sdgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle));
        vm.cool(address(quests)); vm.cool(address(affiliate)); vm.cool(address(dgnrs));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE); vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE); vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }
    function _lastGas() private returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
    }
    function test_AcquiredSubscriptionsStopBeforeAnyFurtherFundingDebit() public {
        uint256 base = vm.snapshotState();
        for (uint8 mode; mode < 3; ++mode) {
            host.prepare(false);
            host.add(PLAYER, mode == 2 ? 2 : 0);
            address funder = mode == 2 ? address(uint160(PLAYER) + 0x100000) : PLAYER;
            host.acquireForTest(funder, mode == 1);
            uint256 fundingBefore = game.afkingFundingOf(funder);
            uint256 claimableBefore = host.claimableOf(PLAYER);
            MineFlipGas.Result memory result = host.subWork{gas: 2_000_000}(2_000_000);
            uint256 used = _lastGas();
            emit log_named_uint("acquired_subscriber_cleanup_gas", used);
            assertTrue(result.progressed && result.done);
            assertEq(host.memberCount(), 0);
            assertEq(game.afkingFundingOf(funder), fundingBefore);
            assertEq(host.claimableOf(PLAYER), claimableBefore);
            assertEq(host.pendingEntries(PLAYER, 5), 0);
            assertLe(used, (mode == 2 ? 2 : 1) * GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS);
            assertTrue(vm.revertToState(base));
        }
    }

    function test_AcquisitionDoesNotOrphanPreviouslyPaidBox() public {
        host.prepare(false);
        host.add(PLAYER, 5);
        host.subWork(2_000_000);
        (uint24 bought, uint24 opened) = host.delivered(PLAYER);
        assertGt(bought, opened);
        assertEq(host.pendingBoxes(), 1);
        uint256 fundingBefore = game.afkingFundingOf(PLAYER);
        host.acquireForTest(PLAYER, true);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        host.nextPass();
        host.subWork(2_000_000);
        assertEq(host.memberCount(), 1);
        assertEq(host.pendingBoxes(), 1);
        (uint24 boughtAfter, uint24 openedAfter) = host.delivered(PLAYER);
        assertEq(boughtAfter, bought);
        assertEq(openedAfter, opened);
        assertEq(game.afkingFundingOf(PLAYER), fundingBefore);
    }

    function test_ColdHundredPaidPassWhaleFitsNativeBound() public {
        host.prepare(true);
        uint256[100] memory beforeEntries;
        for (uint24 i; i < 100; ++i) beforeEntries[i] = host.pendingEntries(ContractAddresses.SDGNRS, i + 5);
        vm.recordLogs();
        MineFlipGas.Result memory result = host.subWork{gas: 12_000_000}(12_000_000);
        uint256 used = _lastGas();
        emit log_named_uint("native_subscriber_100_paid_passes_including_intrinsic", used);
        assertTrue(result.progressed && result.done);
        assertLe(used, GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
            "whale action exceeds saved atomic envelope");
        assertLe(used, STEP_GAS_TARGET);
        assertEq(host.claimableOf(ContractAddresses.SDGNRS), 1_600 ether, "all100 paid passes bought");
        uint256 purchaseLogs;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].emitter == address(game)
                && logs[i].topics[0] == keccak256("WhalePassPurchased(uint32,uint256,uint256)")) {
                (uint256 quantity, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(quantity, 100);
                assertEq(paid, 400 ether);
                ++purchaseLogs;
            }
        }
        assertEq(purchaseLogs, 1, "one aggregate100-pass purchase");
        for (uint24 i; i < 100; ++i) {
            assertGt(host.pendingEntries(ContractAddresses.SDGNRS, i + 5), beforeEntries[i],
                "purchase must deliver every level in the100-level span");
        }
    }
    function test_ColdSubscriberFundingAndRemovalBranchesFitSavedBound() public {
        uint256 base = vm.snapshotState();
        uint256 peak;
        for (uint8 mode; mode <= 5; ++mode) {
            host.prepare(false);
            host.add(PLAYER, mode);
            MineFlipGas.Result memory result = host.subWork{gas: 12_000_000}(12_000_000);
            uint256 used = _lastGas();
            emit log_named_uint("subscriber_branch_mode", mode);
            emit log_named_uint("native_single_subscriber_including_intrinsic", used);
            assertTrue(result.progressed && result.done);
            assertEq(result.rewardBasis, 1, "exactly one subscriber processed");
            assertLe(used, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
                "cold full item exceeds saved atomic envelope");
            assertLe(used, STEP_GAS_TARGET);
            if (mode == 3 || mode == 4) assertEq(host.memberCount(), 0, "expired member removed");
            else {
                (uint24 bought, uint24 opened) = host.delivered(PLAYER);
                assertEq(bought, game.currentDayView());
                assertEq(opened, mode == 5 ? bought - 1 : bought);
            }
            if (used > peak) peak = used;
            vm.revertToState(base);
        }
        emit log_named_uint("native_subscriber_branch_peak", peak);
    }
    /// @dev The saturated AFKing grant over many committed words, every run from the same cold
    ///      fixture: the peak includes a winning ETH spin whose share recirculates into a nested box.
    function test_ColdSaturatedAfkingGrantSweep() public {
        uint256 base = vm.snapshotState();
        uint256 peak;
        uint256 total;
        for (uint256 i; i < 256; ++i) {
            address player = i & 1 == 0 ? PLAYER : ContractAddresses.SDGNRS;
            host.openFixture(player, uint256(keccak256(abi.encode("afking grant", i))));
            _cool();
            MineFlipGas.Result memory result = host.openWork{gas: 12_000_000}(12_000_000);
            uint256 used = _lastGas();
            assertTrue(result.progressed && result.done);
            total += used;
            if (used > peak) peak = used;
            assertTrue(vm.revertToState(base));
        }
        emit log_named_uint("saturated AFKing grant worker incl. intrinsic, mean", total / 256);
        emit log_named_uint("saturated AFKing grant worker incl. intrinsic, peak", peak);
        emit log_named_uint("declared AFKING_OPEN_GAS + AFKING_TAIL_GAS", GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS);
        assertLe(peak, GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS, "cold AFKing grant exceeds its envelope");
        assertLe(GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS + MineFlipGas.CHECK_RESERVE, STEP_GAS_TARGET);
    }

    function testFuzz_ColdSaturatedAfkingGrantFitsSavedBound(uint256 word, bool protocolPlayer) public {
        address player = protocolPlayer ? ContractAddresses.SDGNRS : PLAYER;
        host.openFixture(player, word);
        MineFlipGas.Result memory result = host.openWork{gas: 12_000_000}(12_000_000);
        uint256 used = _lastGas();
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, 1);
        assertEq(host.pendingBoxes(), 0);
        assertLe(used, GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS,
            "cold full AFKing grant exceeds saved atomic envelope");
        assertLe(used, STEP_GAS_TARGET);
        (uint24 bought, uint24 opened) = host.delivered(player);
        assertEq(opened, bought);
    }
}
