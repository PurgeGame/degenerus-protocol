// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev A full production facade with controlled, committed native-worker inputs.
///      The measured calls delegate to the unmodified production AFKing module.
contract SubscriberNativeGasHost is DegenerusGame, WalletSeed {
    function prepare(bool whale) external {
        uint24 day = _wallDay();
        level = 4;
        dailyIdx = day - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        _afkingResetDay = day;
        _afkingEndpointDay = day - 1;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        _clearSubscriberSet();
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
            // 1,650 ETH: 1,640 after the top-up, whose quarter (410 ETH) buys exactly 20 groups.
            _creditClaimable(_seedWallet(ContractAddresses.SDGNRS), 1_650 ether);
            claimablePool += 1_650 ether;
        }
    }

    /// @dev A maximum-quantity lane checkpointed at `day`, optionally pending removal.
    function _configureLane(uint32 id, uint24 day, bool removal) private {
        uint256 position1 = _subPosition1(id);
        uint256 lane = _subLaneAt(position1 - 1);
        lane |= uint256(SUB_MAX_QUANTITY - 1) << SUB_QTY_SHIFT;
        lane = _withSubCheckpoint(lane, day, 0);
        if (removal) lane |= SUB_REMOVAL_BIT;
        _setSubLaneAt(position1 - 1, lane);
        _setSubMetaLane(id, position1 | (uint256(day) << 11));
    }

    /// @param mode 0=self funded ticket,1=claimable ticket,2=claimable then prepaid ticket,
    ///             3=unfunded expiry,4=seized removal,5=maximum box stamp.
    function add(address player, uint8 mode) external {
        uint32 id = _seedWallet(player);
        _seedSubscriber(id, mode != 5);
        _configureLane(id, _afkingResetDay - 1, mode == 4);
        if (mode == 0 || mode == 5) _creditAfkingValue(id, 100 ether);
        if (mode == 1) {
            _creditClaimable(id, 100 ether);
            claimablePool += 100 ether;
        }
        if (mode == 2) {
            _creditAfkingValue(id, 1 ether);
            _creditClaimable(id, 0.01 ether + 1);
            claimablePool += 0.01 ether + 1;
        }
    }

    function openFixture(address player, uint256 word) external {
        uint24 day = _wallDay();
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
        _clearSubscriberSet();
        _seedSubscriber(id, false);
        _subOpenCursor = 0;
        _pendingBoxCount = 1;
        _afkingResetDay = day; // the cohort's stamp day, as preparation leaves it
        _configureLane(id, day - 1, false);
        _afkingEndpointDay = day;
        _afkingCohortPriceMilli = uint16(_packEthToMilliEth(0.24 ether)); // the maximum unit price
        if (player == ContractAddresses.SDGNRS) _afkingProtocolFlags = AFK_SDGNRS_BOUGHT;
        // The maximum quantity at the maximum price and the maximum useful activity-score code.
        uint256 position1 = _subPosition1(id);
        _setSubLaneAt(position1 - 1, _subLaneAt(position1 - 1) | (uint256(305) << SUB_SCORE_SHIFT));
        // All following destinations are newly funded, cold far-future queues.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(q.slot, 0) }
        }
        _setPrizePools(1_000 ether, 10_000 ether);
    }

    // Fixture-only ownership transition; the loan tests exercise the real seizure itself.
    function acquireForTest(address player, bool child) external {
        uint32 id = _walletIdOf(player);
        if (child) {
            uint32 parent = _seedWallet(address(0xAC0123));
            wallets[id] = uint256(parent) << 160;
            id = parent;
        }
        wallets[id] |= uint256(SDGNRS_WALLET_ID) << 160;
    }
    /// @dev Fixture for a seizure: the ownership transition, then the cancel `runLoanSeizureWork` runs
    ///      right after it (a main seizure also stops its smurfs; `child` makes `player` the seized
    ///      main's only smurf).
    function liquidateForTest(address player, bool child) external {
        uint32 id = _walletIdOf(player);
        if (child) {
            uint32 parent = _seedWallet(address(0xAC0123));
            wallets[id] = uint256(parent) << 160;
            mintPacked_[parent] += uint256(1) << BitPackingLib.SMURF_COUNT_SHIFT;
            _smurfWords[parent][0] = id;
            id = parent;
        }
        wallets[id] |= uint256(SDGNRS_WALLET_ID) << 160;
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("cancelLiquidatedSubscriptions(uint32,bool)", id, child)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
    function publishForOpen() external {
        dailyIdx = _afkingResetDay;
        rngRequestDay = dailyIdx;
        rngWordCurrent = 0xAFAFAF;
        _setRngSessionPublished(true);
        _setRngComplete(false);
    }
    function nextPass() external {
        _afkingResetDay = _wallDay();
        _subCursor = 0;
        subsFullyProcessed = false;
    }

    function subWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runSubscriberWork_g6352(uint24,uint256)", _afkingResetDay, allowance));
    }
    function openWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runAfkingWork_g8553(uint256)", allowance));
    }
    function pendingBoxes() external view returns (uint256) { return _pendingBoxCount; }
    function memberCount() external view returns (uint256) { return _subscribers.length; }
    /// @dev (day bought, day whose box has been opened). The preparation cursor passing a member
    ///      is its purchase; a stamped box is pending exactly while the count is nonzero, the
    ///      member sits in the box section and the opener cursor has not passed it.
    function delivered(address player) external view returns (uint24, uint24) {
        uint256 position1 = _subPosition1(_walletIdOf(player));
        if (position1 == 0) return (0, 0);
        uint256 position = position1 - 1;
        uint256 cursor = _subCursor;
        bool visited = subsFullyProcessed
            || (position < _subBoxCount ? position < cursor : cursor >= SUBSCRIBER_TICKET_PHASE
                && cursor - SUBSCRIBER_TICKET_PHASE > SUBSCRIBER_CAP - position);
        if (!visited) return (0, 0);
        uint24 bought = _afkingResetDay;
        bool pending = _pendingBoxCount != 0 && position < _subBoxCount && position >= _subOpenCursor;
        return (bought, pending ? bought - 1 : bought);
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

contract SubscriberAfkingNativeGasTest is DeployProtocol, NativeGasExport {
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
    function exportSubscriber(string calldata label, bool opening) external {
        require(msg.sender == address(this), "export self-call");
        bytes memory input = opening ? abi.encodeCall(host.openWork, (uint256(12_000_000)))
            : abi.encodeCall(host.subWork, (uint256(12_000_000)));
        this.exportNativeFixture(label, address(this), address(host), input);
    }

    function _lastGas() private returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
    }
    function test_AcquiredSubscriptionsStopBeforeAnyFurtherFundingDebit() public {
        uint256 base = vm.snapshotState();
        for (uint8 mode; mode < 2; ++mode) {
            host.prepare(false);
            host.add(PLAYER, 0);
            // Own sale (0) and main sale with the smurf (1) stop at liquidation.
            host.liquidateForTest(PLAYER, mode == 1);
            uint256 fundingBefore = game.afkingFundingOf(PLAYER);
            uint256 claimableBefore = host.claimableOf(PLAYER);
            // The pass admits each member only with SUBSCRIBER_ITEM_GAS + SUBSCRIBER_TAIL_GAS left
            // (1.95M at the 1.7M item bound); after the empty box section a 2M budget no longer
            // reaches the ticket-section member, so the caller budget is 4M.
            MineFlipGas.Result memory result = host.subWork{gas: 4_000_000}(4_000_000);
            uint256 used = _lastGas();
            emit log_named_uint("acquired_subscriber_cleanup_gas", used);
            assertTrue(result.progressed, "the cleanup progresses");
            assertTrue(result.done, "the pass completes");
            assertEq(host.memberCount(), 0, "the acquired member is removed");
            assertEq(game.afkingFundingOf(PLAYER), fundingBefore, "no further funding debit");
            assertEq(host.claimableOf(PLAYER), claimableBefore, "no claimable debit");
            assertEq(host.pendingEntries(PLAYER, 5), 0, "no entries bought");
            assertLe(used, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS, "cleanup within the item bound");
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
        host.liquidateForTest(PLAYER, true);
        host.publishForOpen();
        assertEq(host.openWork(12_000_000).rewardBasis, 1, "acquisition cannot discard the paid box");
        assertEq(host.pendingBoxes(), 0);
        (, uint24 openedAfter) = host.delivered(PLAYER);
        assertEq(openedAfter, bought);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        host.nextPass();
        host.subWork(2_000_000);
        assertEq(host.memberCount(), 0, "acquired member removed on next preparation");
        assertEq(game.afkingFundingOf(PLAYER), fundingBefore);
    }

    function test_ColdHundredPaidPassWhaleFitsNativeBound() public {
        host.prepare(true);
        uint256[100] memory beforeEntries;
        for (uint24 i; i < 100; ++i) beforeEntries[i] = host.pendingEntries(ContractAddresses.SDGNRS, i + 5);
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        MineFlipGas.Result memory result = host.subWork{gas: 12_000_000}(12_000_000);
        uint256 used = _lastGas();
        emit log_named_uint("native_subscriber_100_paid_passes_including_intrinsic", used);
        assertTrue(result.progressed && result.done);
        assertLe(used, GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
            "whale action exceeds saved atomic envelope");
        assertLe(used, STEP_GAS_TARGET);
        // The top-up moves 10 ETH of claimable into sDGNRS AFKing before the purchase, which then
        // spends 400 ETH; plus the 1-wei registration sentinel.
        assertEq(game.afkingFundingOf(ContractAddresses.SDGNRS), 10 ether, "AFKing topped up to target");
        assertEq(host.claimableOf(ContractAddresses.SDGNRS), 1_240 ether + 1, "all100 paid passes bought");
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
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportSubscriber("subscriber_whale_100", false);
        }
    }
    function test_ColdSubscriberFundingAndRemovalBranchesFitSavedBound() public {
        uint256 base = vm.snapshotState();
        uint256 peak;
        for (uint8 mode; mode <= 5; ++mode) {
            host.prepare(false);
            host.add(PLAYER, mode);
            uint256 snapshot = vm.snapshotState();
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
                assertEq(bought, game.currentDayView() + 1, "preparation stamps the upcoming logical round");
                assertEq(opened, mode == 5 ? bought - 1 : bought);
            }
            if (used > peak) peak = used;
            if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
                assertTrue(vm.revertToState(snapshot));
                this.exportSubscriber(string.concat("subscriber_branch_", vm.toString(mode)), false);
            }
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
            uint256 snapshot = vm.snapshotState();
            _cool();
            MineFlipGas.Result memory result = host.openWork{gas: 12_000_000}(12_000_000);
            uint256 used = _lastGas();
            assertTrue(result.progressed && result.done);
            total += used;
            if (used > peak) peak = used;
            if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
                assertTrue(vm.revertToState(snapshot));
                this.exportSubscriber(string.concat("afking_saturated_", vm.toString(i)), true);
            }
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
