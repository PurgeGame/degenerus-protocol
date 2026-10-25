// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CoinflipCore} from "../../contracts/modules/CoinflipCore.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {AutoDecimatorAdvanceHarness, AutoDecimatorGameHarness} from "../fuzz/SdgnrsAutoDecimator.t.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract PinDecimatorGameHarness is AutoDecimatorGameHarness {
    function setRoundTotal(uint24 lvl, uint64 total) external {
        decBattleRounds[lvl].totalCreditedStack = total;
    }

    function roundTotal(uint24 lvl) external view returns (uint64) {
        return decBattleRounds[lvl].totalCreditedStack;
    }
}

/// @notice Pins on the opening-day decimator entry (C7, F3) and the sDGNRS pool decrement (F10), run through
///         the real `applyDailyWord_g1652` on the harnessed Game.
contract ChainPinDecimatorHarness is DeployProtocol {
    address private constant HOUSE = ContractAddresses.SDGNRS;
    uint32 private constant HOUSE_ID = 2;
    bytes32 private constant BURN_EVENT = keccak256("DecimatorBurn(uint32,uint256,uint64)");
    PinDecimatorGameHarness private harness;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(PinDecimatorGameHarness).runtimeCode);
        vm.etch(address(advanceModule), type(AutoDecimatorAdvanceHarness).runtimeCode);
        harness = PinDecimatorGameHarness(payable(address(game)));
        // Bank one genesis win and arm sDGNRS's perpetual auto-rebuy, then start without a seed reserve.
        for (uint24 day = 1; day <= 20; ++day) {
            _warp(day);
            vm.prank(address(game));
            coinflip.processCoinflipPayouts(0, day == 1 ? 3 : 2, day);
        }
        uint256 banked = coinflip.previewFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(banked);
        assertEq(coinflip.previewFlipBacking(HOUSE), 0);
    }

    function _warp(uint24 day) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _fund(uint256 amount) private {
        vm.prank(address(game));
        coinflip.creditFlip_g317(HOUSE_ID, amount);
    }

    function _prepare(uint24 day, uint24 lvl, uint256 word, bool opening) private {
        _warp(day);
        harness.prepareOpening(day, lvl, word, opening);
    }

    function _burnedBy(Vm.Log[] memory logs) private view returns (uint256 amount) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coin) && logs[i].topics[0] == BURN_EVENT) {
                assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf_g3120(HOUSE));
                (uint256 spent,) = abi.decode(logs[i].data, (uint256, uint64));
                amount += spent;
            }
        }
    }

    // ---- C7 ----

    /// @dev The opening-day entry at the maximal inputs: a 2x activity multiplier, the 50% decimator boon on
    ///      a 50k base and a 5,000 quest reward. `room0` is what is left under the round's 64-bit aggregate.
    function _c7(uint256 room0, bool bigReference) private {
        _fund(2_000_000);
        if (bigReference) harness.setDecReference(4_000_000, 1, 4);
        _prepare(21, 4, 3, true);
        uint64 start = uint64(uint256(type(uint64).max) - room0);
        harness.setRoundTotal(5, start);
        uint32 id = game.walletIdOf_g3120(HOUSE);
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(IDegenerusGame.playerActivityScoreCachedById_g975.selector, id),
            abi.encode(uint256(1_000_000))
        );
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(IDegenerusGame.consumeDecimatorBoon.selector, id),
            abi.encode(uint16(5000))
        );
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(quests.handleDecimator.selector),
            abi.encode(uint256(5000), uint8(0), uint32(0), true)
        );
        vm.recordLogs();
        harness.applyOpeningWord(21);
        uint256 spent = _burnedBy(vm.getRecordedLogs());
        uint256 credited = uint256(harness.roundTotal(5)) - uint256(start);
        assertLe(credited, room0, "C7: the automatic entry stays inside the round aggregate");
        uint256 room = room0 / 2;
        uint256 fit = room > 30_000 ? room - 30_000 : 0;
        uint256 cap = bigReference ? fit : (fit < 8000 ? fit : 8000);
        if (cap >= 2000) {
            assertGt(credited, 0, "C7: an entry that fits is recorded");
            assertEq(spent, cap, "C7: the cap is what is spent");
        } else {
            assertEq(credited, 0, "C7: no room, no entry");
            assertEq(spent, 0);
        }
        assertGt(game.rngWordForDay(21), 0, "C7: applyDailyWord_g1652 completed");
    }

    /// forge-config: default.fuzz.runs = 48
    function testFuzz_C7_automaticCapKeepsEntryInsideAggregate(uint256 room0, bool bigReference) public {
        _c7(bound(room0, 0, 400_000), bigReference);
    }

    /// @dev Large reference, 200k of room: the cap is 70k and the credit lands exactly at 2x(cap + margin).
    function test_C7_roomWhereTheMarginIsTight() public {
        _c7(200_000, true);
    }

    function test_C7_roomJustBelowTheMinimumEntry() public {
        _c7(2 * (30_000 + 1999) + 1, true);
    }

    function test_C7_fullRound() public {
        _c7(0, true);
    }

    // ---- F3 ----

    /// @dev A word applied after the wall day moved on skips the opening-day burn (and the craps opener)
    ///      without reverting; the control applies the same word on the day itself.
    function test_F3_lateWordSkipsOpeningBurn() public {
        _fund(400_000);
        _prepare(21, 4, 3, true);
        uint256 snap = vm.snapshotState();
        harness.applyOpeningWord(21);
        (uint256 onTime,) = harness.entry(5);
        assertGt(onTime, 0, "control: the on-time word records the entry");
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0, "control: and opens the craps seat");

        assertTrue(vm.revertToState(snap));
        _warp(22);
        vm.recordLogs();
        harness.applyOpeningWord(21);
        assertEq(_burnedBy(vm.getRecordedLogs()), 0, "F3: no burn after midnight");
        (uint256 late,) = harness.entry(5);
        assertEq(late, 0, "F3: no entry after midnight");
        assertGt(game.rngWordForDay(21), 0, "F3: the word was still applied");
        assertGt(coinflip.previewFlipBacking(HOUSE), 8000, "F3: the day's backing is untouched");
        assertEq(crapsBattle.daySeatNumberOf(21, HOUSE), 0, "F3: no craps seat for the stale day");
    }

    // ---- F10 (sDGNRS side) ----

    /// @dev `transferFromPool` returns exactly what it took out of the pool and out of the contract balance.
    /// forge-config: default.fuzz.runs = 64
    function testFuzz_F10_transferFromPoolReturnsTheExactDecrement(uint8 poolSeed, uint256 keep, uint256 ask) public {
        sDGNRS.Pool pool = sDGNRS.Pool(bound(poolSeed, 0, 4));
        uint256 cur = sdgnrs.poolBalance(pool);
        keep = bound(keep, 0, cur);
        if (cur != keep) {
            vm.prank(address(game));
            sdgnrs.transferFromPool(pool, address(0xdead), cur - keep);
        }
        assertEq(sdgnrs.poolBalance(pool), keep);
        ask = bound(ask, 0, 2 * keep + 10);
        address to = address(0xBEEF);
        uint256 poolBefore = sdgnrs.poolBalance(pool);
        uint256 selfBefore = sdgnrs.balanceOf(address(sdgnrs));
        uint256 toBefore = sdgnrs.balanceOf(to);
        vm.prank(address(game));
        uint256 got = sdgnrs.transferFromPool(pool, to, ask);
        assertEq(got, ask < poolBefore ? ask : poolBefore, "returns the clamped amount");
        assertEq(poolBefore - sdgnrs.poolBalance(pool), got, "F10: the pool fell by the returned amount");
        assertEq(selfBefore - sdgnrs.balanceOf(address(sdgnrs)), got, "and so did the contract balance");
        assertEq(sdgnrs.balanceOf(to) - toBefore, got, "and the recipient gained it");
    }
}

/// @dev Game-frame caller for the Quests -> Game re-entry: the BoonModule calls `awardQuestStreakBonus` from the
///      Game's own frame, and Quests calls back into the Game.
contract PinReentryGameHarness is DegenerusGame {
    function awardViaQuests(uint32 id, uint16 amount, uint24 day) external {
        quests.awardQuestStreakBonus(id, amount, day);
    }

    function setStreak(uint32 id, uint256 streak) external {
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        _setSubLaneAt(position1 - 1, _withSubCheckpoint(lane, _subDay(lane), streak));
    }

    function streakOf(uint32 id) external view returns (uint256) {
        (uint256 lane,) = _subLaneOf(id);
        return _subCheckpointStreak(lane);
    }

    function markRemoval(uint32 id) external {
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        _setSubLaneAt(position1 - 1, lane | SUB_REMOVAL_BIT);
    }
}

/// @notice F-A6 and F-B7 on the AFKing worker path.
contract ChainPinAfking is DeployProtocol {
    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;
    address private constant ALICE = address(0xA11CE);

    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000_000 ether);
        lens = new DegenerusGameLens();
        vm.deal(address(this), 100 ether);
    }

    function _nextDay() private {
        vm.warp(block.timestamp + 1 days);
        _finishSubscriptionWindow();
        _finishReadConsumers();
    }

    function _info(uint32 id) private view returns (DegenerusGameLens.SubFull memory) {
        return lens.subInfoFullById(address(game), id);
    }

    function _flip(uint32 id) private view returns (uint256) {
        return coinflip.coinflipAmountById(id);
    }

    function _flags() private view returns (uint8) {
        uint256 word = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)));
        return uint8(word >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET));
    }

    function _setBalances(uint32 id, uint256 prepaid, uint256 claimable) private {
        vm.store(address(game), GameSlotKeys.balances(id), bytes32((prepaid << 128) | claimable));
    }

    // ---- F-A6 ----

    bytes32 private constant CLAIMED_SIG = keccak256("AfkingFlipClaimed(uint32,uint256)");

    function _claimedFor(Vm.Log[] memory logs, uint32 id) private view returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == CLAIMED_SIG
                && uint32(uint256(logs[i].topics[1])) == id) {
                total += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    /// @dev Both protocol seats bought for two days, then cannot pay on the same pass: each is paused and settled
    ///      through `Affiliate.claim` -> `drainAffiliateBases` -> `CoinflipCore.creditFlip_g317`, and the pass completes.
    function test_FA6_bothProtocolSeatsUnfundedOnTheSameDay() public {
        game.depositAfkingFunding{value: 10 ether}(VAULT_ID);
        game.depositAfkingFunding{value: 10 ether}(SDGNRS_ID);
        emit log_string("funded");
        _nextDay();
        _nextDay();
        emit log_string("two funded days done");
        assertEq(_flags() & 24, 0, "both seats are funded and running");
        uint256 vaultOwed = _info(VAULT_ID).owedFlip;
        uint256 sdgnrsOwed = _info(SDGNRS_ID).owedFlip;
        emit log_named_uint("vault owed", vaultOwed);
        emit log_named_uint("sdgnrs owed", sdgnrsOwed);
        assertGe(vaultOwed, 200, "the Vault earned two days");
        assertGe(sdgnrsOwed, 200, "sDGNRS earned two days");

        _setBalances(VAULT_ID, 0, 1);
        _setBalances(SDGNRS_ID, 0, 1);
        vm.recordLogs();
        _nextDay();
        emit log_string("unfunded pass done");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_flags() & 24, 24, "both seats paused on the unfunded pass");
        assertTrue(_info(VAULT_ID).paused && _info(SDGNRS_ID).paused);
        assertTrue(_info(VAULT_ID).member && _info(SDGNRS_ID).member, "paused seats stay members");
        assertEq(_info(VAULT_ID).owedFlip, 0, "the Vault settled through its last bought day");
        assertEq(_info(SDGNRS_ID).owedFlip, 0, "sDGNRS settled through its last bought day");
        assertEq(_claimedFor(logs, VAULT_ID), vaultOwed, "the Vault was paid its own reward");
        assertEq(_claimedFor(logs, SDGNRS_ID), sdgnrsOwed, "sDGNRS was paid its own reward");

        _nextDay();
        assertEq(_flags() & 24, 24, "a second unfunded day changes nothing and completes");
    }

    // ---- F-B7 ----

    function _subscribe(address who) private returns (uint32 id) {
        uint256 seat = _grantSeat(who);
        vm.deal(who, 1 ether);
        vm.prank(who);
        game.subscribe{value: 1 ether}(0, false, 1, seat);
        id = game.walletIdOf_g3120(who);
    }

    /// forge-config: default.fuzz.runs = 24
    function testFuzz_FB7_questsReentrySaturatesAndNeverReverts(uint256 start, uint256 amount) public {
        start = bound(start, 0, 0xffff);
        amount = bound(amount, 1, 0xffff);
        uint32 id = _subscribe(ALICE);
        _nextDay();
        vm.etch(address(game), type(PinReentryGameHarness).runtimeCode);
        PinReentryGameHarness h = PinReentryGameHarness(payable(address(game)));
        h.setStreak(id, start);
        h.awardViaQuests(id, uint16(amount), game.currentDayView_g542950());
        uint256 sum = start + amount;
        assertEq(h.streakOf(id), sum > 0xffff ? 0xffff : sum, "F-B7: the streak adds and saturates, no revert");
    }

    function test_FB7_streakAtTheCeiling() public {
        uint32 id = _subscribe(ALICE);
        _nextDay();
        vm.etch(address(game), type(PinReentryGameHarness).runtimeCode);
        PinReentryGameHarness h = PinReentryGameHarness(payable(address(game)));
        h.setStreak(id, 0xffff);
        h.awardViaQuests(id, 0xffff, game.currentDayView_g542950());
        assertEq(h.streakOf(id), 0xffff);
        vm.prank(address(quests));
        game.recordAfkingSecondary_g3316(id, 0xffff);
        assertEq(h.streakOf(id), 0xffff);
    }

    function test_FB7_runPendingRemovalIsANoOp() public {
        uint32 id = _subscribe(ALICE);
        _nextDay();
        vm.etch(address(game), type(PinReentryGameHarness).runtimeCode);
        PinReentryGameHarness h = PinReentryGameHarness(payable(address(game)));
        h.setStreak(id, 7);
        h.markRemoval(id);
        h.awardViaQuests(id, 50, game.currentDayView_g542950());
        assertEq(h.streakOf(id), 7, "a run pending removal ignores the award");
    }
}
