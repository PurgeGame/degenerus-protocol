// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {VaultBafRig} from "./VaultBafSettlement.t.sol";

/// @dev The vault's coinflip claim backlog, written through Coinflip's lane helpers, so the
///      x0 seal's vault settlement walks a full 365-day window.
contract SweepVaultSeeder is CoinflipStakeSetter {
    function seedVaultHistory(uint24 latest, uint24 gap, bool rebuy) external {
        PlayerCoinflipState storage s = playerState[degenerusGame.walletIdOf(ContractAddresses.VAULT)];
        uint24 last = latest - gap;
        s.claimableStored = 0;
        s.lastClaim = last;
        s.autoRebuyStartDay = rebuy ? last : 0;
        s.autoRebuyEnabled = rebuy;
        s.autoRebuyStop = rebuy ? 7 ether : 0;
        s.autoRebuyCarry = 0;
        uint24 lossDay = last + gap / 2;
        for (uint24 d = last + 1; d <= latest; ++d) {
            _setFlipStake(d, 1, 5_000 ether);
            _storeDayResult(d, 150, d != lossDay);
        }
        flipsClaimableDay = latest;
    }
}

/// @dev Production Game plus native seams to stop the daily cycle at a chosen first action.
contract SweepHost is DegenerusGame {
    function publishOnly() external {
        _native(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng()"));
    }

    function ticketsOnly() external returns (bool done) {
        uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
        MineFlipGas.Result memory result = abi.decode(_native(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork(uint24,uint256)", anchor, uint256(9_000_000))),
            (MineFlipGas.Result));
        done = result.done;
        if (done) {
            ticketsFullyProcessed = true;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }

    function applyOnly() external {
        _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord()"));
    }

    function _native(address target, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        return reason;
    }
}

/// @title MineFlipGasSweep — mineFlip never reverts once its first action fits.
/// @notice USER requirement: with enough gas for the first action, mineFlip never reverts on
///         gas. The state is the x0 latch day of a real game (purchase level 10: the seal arms
///         the BAF draw and settles the vault's coinflips, a BAF_VAULT_SETTLE tail):
///         - from Publish: Publish, then the Tickets worker, DailyApply, the sealing DailyPhase
///           and the consumer stages, each admitted on estimates after the first action;
///         - from DailyPhase: the jackpot child runs the latch day's groups as the first
///           action, then the seal runs in the AdvanceModule's tail.
///         Each sweep calls mineFlip at every gas from one snapshot: coarse 100k steps to
///         16.7M, a 2k-step band over the first 1.2M above the first success (where later
///         workers are admitted with zero or tiny allowances), and 10k steps below 16.7M.
abstract contract MineFlipGasSweepBase is VaultBafRig {
    uint256 internal constant CAP = 16_700_000;
    uint24 internal latchDay;

    struct Stats {
        uint256 firstOk;
        uint256 oks;
        uint256 fails;
        uint256 firstSeal;
        uint256 seals;
        uint256 otherErrors;
    }

    function _slow() internal pure virtual returns (bool);

    function _holdFor(uint24 lvl) internal view override returns (uint256) {
        if (!_slow()) return super._holdFor(lvl);
        return lvl == 0 ? 240 : (lvl < 9 ? 14 : 0);
    }

    function setUp() public override {
        super.setUp();
        vm.pauseGasMetering();
        _settleToday();
        if (_slow()) {
            _runFullDay();
            vm.prank(POKER);
            coinflip.depositCoinflip(1, 0);
            vm.prank(VAULT);
            coinflip.setCoinflipAutoRebuy(0, true, 7 ether);
        }
        _driveToEve(9);
        latchDay = game.currentDayView() + 1;
        _stageDay();
        simTime += 1 days + 1;
        vm.warp(simTime);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 calls; mockVRF.lastRequestId() == before; ++calls) {
            require(calls < 64, "harness: the latch-day request stalled");
            game.mineFlip{gas: 12_000_000}(0);
        }
        _fulfillPending();
        vm.etch(address(game), type(SweepHost).runtimeCode);
        vm.resumeGasMetering();
    }

    function _latched() internal view returns (bool) {
        (, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
        return lastPurchaseDay_;
    }

    function _action() internal view returns (uint8) {
        return game.nextMinerAction();
    }

    function _toDailyPhase() internal {
        SweepHost host = SweepHost(payable(address(game)));
        host.publishOnly();
        for (uint256 reads; !host.ticketsOnly(); ++reads) require(reads < 32, "harness: tickets stalled");
        host.applyOnly();
        if (_slow()) {
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(SweepVaultSeeder).runtimeCode);
            SweepVaultSeeder(address(coinflip)).seedVaultHistory(latchDay, 365, true);
            vm.etch(address(coinflip), original);
        }
        assertEq(_action(), uint8(DegenerusGameStorage.MinerAction.DailyPhase));
        assertFalse(_latched());
    }

    /// @dev Every call in a test shares one transaction's access list; re-cool the protocol so
    ///      each swept call pays what a fresh keeper transaction pays.
    function _coolAll() internal {
        address[22] memory accounts = [
            ContractAddresses.GAME, ContractAddresses.COIN, ContractAddresses.COINFLIP, ContractAddresses.VAULT,
            ContractAddresses.AFFILIATE, ContractAddresses.JACKPOTS, ContractAddresses.QUESTS, ContractAddresses.SDGNRS,
            ContractAddresses.DGNRS, ContractAddresses.ADMIN, ContractAddresses.WWXRP, ContractAddresses.STETH_TOKEN,
            ContractAddresses.LINK_TOKEN, ContractAddresses.GNRUS, ContractAddresses.PARIMUTUEL, ContractAddresses.CRAPS,
            ContractAddresses.CRAPS_ENGINE, ContractAddresses.JACKPOT_BATTLE, ContractAddresses.DEITY_PASS,
            ContractAddresses.AFKING_SUB_TOKEN, ContractAddresses.VRF_COORDINATOR, address(mockVRF)
        ];
        for (uint256 i; i < accounts.length; ++i) vm.cool(accounts[i]);
        address[16] memory modules = [
            ContractAddresses.GAME_MINT_MODULE, ContractAddresses.GAME_ADVANCE_MODULE, ContractAddresses.GAME_WHALE_MODULE,
            ContractAddresses.GAME_JACKPOT_MODULE, ContractAddresses.GAME_DECIMATOR_MODULE, ContractAddresses.GAME_GAMEOVER_MODULE,
            ContractAddresses.GAME_LOOTBOX_MODULE, ContractAddresses.GAME_BOON_MODULE, ContractAddresses.GAME_DEGENERETTE_MODULE,
            ContractAddresses.GAME_BINGO_MODULE, ContractAddresses.GAME_AFKING_MODULE, ContractAddresses.GAME_FOILPACK_MODULE,
            ContractAddresses.GAME_TICKET_MODULE, ContractAddresses.GAME_MINER_MODULE, ContractAddresses.GAME_RNG_MODULE,
            ContractAddresses.GAME_JACKPOT_DRAW_MODULE
        ];
        for (uint256 i; i < modules.length; ++i) vm.cool(modules[i]);
    }

    function _mineAt(uint256 g) internal returns (bool ok, bytes memory err) {
        _coolAll();
        (ok, err) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
    }

    /// @dev From DailyPhase, advance with the smallest successful calls to the earliest state
    ///      from which one 16.7M call seals the latch day, so that call's first-mode jackpot
    ///      child runs every remaining unit of the sealing leg before the seal.
    function _toEarliestSealingCall() internal {
        for (uint256 i; ; ++i) {
            require(i < 64, "harness: never reached a sealing call");
            uint256 snap = vm.snapshotState();
            _mineAt(CAP);
            bool seals = _latched();
            vm.revertToStateAndDelete(snap);
            if (seals) return;
            bool moved;
            for (uint256 g = 1_000_000; g <= CAP && !moved; g += 500_000) (moved,) = _mineAt(g);
            require(moved, "harness: no call advanced the day");
            require(!_latched(), "harness: a small call sealed");
        }
    }

    function _sweep(uint256 lo, uint256 hi, uint256 step) internal returns (Stats memory st) {
        for (uint256 g = lo; ; g += step) {
            if (g > hi) g = hi;
            uint256 snap = vm.snapshotState();
            (bool ok, bytes memory err) = _mineAt(g);
            if (ok) {
                if (st.firstOk == 0) st.firstOk = g;
                ++st.oks;
                if (_latched()) {
                    if (st.firstSeal == 0) st.firstSeal = g;
                    ++st.seals;
                }
            } else {
                ++st.fails;
                bytes4 sel = bytes4(err);
                assertTrue(err.length == 0 || sel != MineFlipGas.WorkGasBound.selector, "never WorkGasBound");
                if (err.length != 0 && sel != MineFlipGas.InsufficientExecutionGas.selector
                    && sel != MineFlipGas.EmptyRevert.selector) {
                    ++st.otherErrors;
                    emit log_named_bytes("non-gas revert below the first action", err);
                    emit log_named_uint("at gas", g);
                }
                if (st.firstOk != 0) {
                    emit log_named_uint("mineFlip reverted at gas", g);
                    emit log_named_uint("after first success at", st.firstOk);
                    emit log_named_bytes("revert data", err);
                    fail();
                }
            }
            vm.revertToStateAndDelete(snap);
            if (g == hi) break;
        }
    }

    function _fullSweep(string memory label) internal returns (Stats memory coarse) {
        coarse = _sweep(100_000, CAP, 100_000);
        assertGt(coarse.firstOk, 0, "some gas completes the first action");
        uint256 lo = coarse.firstOk > 100_000 ? coarse.firstOk - 100_000 : 1;
        Stats memory band = _sweep(lo, coarse.firstOk + 1_200_000, 2_000);
        Stats memory top = _sweep(CAP - 500_000, CAP, 10_000);
        assertEq(top.fails, 0, "near the cap every call succeeds");
        emit log_string(label);
        emit log_named_uint("coarse first success", coarse.firstOk);
        emit log_named_uint("2k-step first success", band.firstOk);
        emit log_named_uint("coarse first seal", coarse.firstSeal);
        emit log_named_uint("calls swept", coarse.oks + coarse.fails + band.oks + band.fails + top.oks + top.fails);
        emit log_named_uint("non-gas reverts below the first action", coarse.otherErrors + band.otherErrors);
        assertGt(band.oks, 500, "the band is swept above the first success");
    }

    /// @dev Calls of `g` gas until the latch day seals, from the current state (0 if a call
    ///      reverts or 64 calls do not seal).
    function _callsToSeal(uint256 g) internal returns (uint256 calls) {
        uint256 snap = vm.snapshotState();
        while (!_latched()) {
            (bool ok,) = _mineAt(g);
            if (!ok || ++calls == 64) {
                calls = 0;
                break;
            }
        }
        vm.revertToStateAndDelete(snap);
    }

    function test_SweepFromPublish() public {
        assertEq(_action(), uint8(DegenerusGameStorage.MinerAction.Publish));
        _fullSweep("first action Publish");
        uint256 snap = vm.snapshotState();
        (bool ok,) = _mineAt(CAP);
        assertTrue(ok);
        uint8 after_ = _action();
        emit log_named_uint("next action after one 16.7M call", after_);
        assertGt(after_, uint8(DegenerusGameStorage.MinerAction.Tickets),
            "non-vacuous: the 16.7M call chains Publish into later estimate-admitted actions");
        vm.revertToStateAndDelete(snap);
    }

    function test_SweepFromDailyPhase() public {
        _toDailyPhase();
        _fullSweep("first action DailyPhase (jackpot leg)");
    }

    function test_SweepFromSealingDailyPhase() public {
        _toDailyPhase();
        _toEarliestSealingCall();
        assertEq(_action(), uint8(DegenerusGameStorage.MinerAction.DailyPhase));
        assertEq(_callsToSeal(CAP), 1, "16.7M seals the latch day in one call");
        Stats memory st = _fullSweep("first action DailyPhase (x0 sealing leg)");
        assertGt(st.seals, 0);
        // More than one call at the threshold gas means the 16.7M call ran several jackpot
        // units in its first-mode child before the seal.
        emit log_named_uint("calls to seal at the first-success gas", _callsToSeal(st.firstOk));
        emit log_named_uint("calls to seal at 4M", _callsToSeal(4_000_000));
    }
}

contract MineFlipGasSweepTurbo is MineFlipGasSweepBase {
    function _slow() internal pure override returns (bool) { return false; }
}

/// @dev Slow game with the vault on auto-rebuy and a 365-day claim backlog on the DailyPhase
///      sweep: the seal's vault settlement is at its declared worst case.
contract MineFlipGasSweepSlowRebuy is MineFlipGasSweepBase {
    function _slow() internal pure override returns (bool) { return true; }
}
