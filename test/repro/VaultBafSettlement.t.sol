// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev The turbo-chained advance rig of BafDrawArming, with the vault credited every day and
///      probes for its coinflip position and bracket scores. Shared by the gas suite.
abstract contract VaultBafRig is DeployProtocol {
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant REF = address(0x5EF0);
    address internal constant POKER = address(0x90CE);
    address internal buyer = address(0xB4A1);

    /// @dev Daily protocol-style flip credit to the vault (whole FLIP), staked tomorrow.
    uint256 internal constant VAULT_CREDIT = 5_000;

    bytes32 internal constant BAF_RECORDED = keccak256("BafFlipRecorded(uint32,uint24,uint256,uint256)");
    bytes32 internal constant DAY_RESOLVED = keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)");
    bytes32 internal constant DRAW_ARMED = keccak256("BafDrawArmed(uint24)");

    uint256 internal simTime;
    /// @dev 0 = natural words, 1 = every fulfilled word wins the flip, 2 = every word loses it.
    uint8 internal forceBit;
    /// @dev Purchase days held under target at `holdLevel` (pushes the latch past the one-day
    ///      turbo window); `_holdFor` may schedule other levels.
    uint256 internal holdDays;
    uint24 internal holdLevel;
    uint256 internal heldDays;
    uint24 internal heldLevel;
    /// @dev Mirror each staged day's final vault lane onto the claimer.
    bool internal mirrorDaily;

    function setUp() public virtual {
        _deployProtocol();
        simTime = block.timestamp + 1 days + 1;
        vm.warp(simTime);
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 500_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
        deal(address(coin), buyer, 5_000_000 ether, true);
        _giveWalletId(REF);
    }

    // ---------------------------------------------------------------------
    // Driver (shape of BafDrawArming / TurboBafTicketFloor)
    // ---------------------------------------------------------------------

    /// @dev Whole days until the latch whose purchaseInfo level is `lvlBefore` fires, then rewinds
    ///      to the close of the day before the latch day. Each day is staged identically on the
    ///      replay, so the latch reproduces.
    function _driveToEve(uint24 lvlBefore) internal {
        _settleToday();
        for (uint256 i = 0; i < 600; i++) {
            require(!game.gameOver(), "harness: gameOver before the latch");
            uint256 snap = vm.snapshotState();
            _stageDay();
            _runFullDay();
            (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == lvlBefore) {
                vm.revertToState(snap);
                return;
            }
            vm.deleteStateSnapshot(snap);
        }
        revert("harness: never reached the latch");
    }

    /// @dev One day's player and protocol actions, before the day boundary.
    function _stageDay() internal {
        vm.prank(address(game));
        coinflip.creditFlip(1, VAULT_CREDIT);
        if (!game.jackpotPhase()) {
            (uint24 lvl, , , , ) = game.purchaseInfo();
            if (lvl != heldLevel) (heldLevel, heldDays) = (lvl, 0);
            if (heldDays < _holdFor(lvl)) {
                // Hold the pool under target so the day seals without latching.
                ++heldDays;
                uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
                vm.store(address(game), bytes32(uint256(2)), bytes32(packed & ~((uint256(1) << 128) - 1)));
            } else {
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
            }
        }
        // Tomorrow's lane is final once today's actions are in (purchases credit the vault too).
        if (mirrorDaily) _mirrorLane(game.currentDayView() + 1);
    }

    function _holdFor(uint24 lvl) internal view virtual returns (uint256) {
        return lvl == holdLevel ? holdDays : 0;
    }

    function _assertLatched(uint24 lvlBefore, uint24 latchDay) internal view {
        (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
        require(lastPurchaseDay_ && lvl == lvlBefore, "harness: the replayed day must latch");
        (uint24 armed, , ) = coinflip.bafDrawInfo();
        require(armed == latchDay + 1, "harness: the latch arms the next day");
    }

    function _settleToday() internal {
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
        }
    }

    function _runFullDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        _settleToday();
    }

    function _mine() internal returns (bool) {
        if (game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.RequestMidday)) return false;
        uint256[6] memory ladder = [uint256(1_500_000), 2_500_000, 3_500_000, 5_000_000, 9_000_000, 16_777_216];
        for (uint256 r; r < ladder.length; ++r) {
            (bool ok, bytes memory err) = address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
            if (bytes4(err) != MineFlipGas.InsufficientExecutionGas.selector) return false;
        }
        return false;
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId)));
        if (forceBit == 1) word |= 1;
        else if (forceBit == 2) word &= ~uint256(1);
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _buyTickets() internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(buyer);
        game.purchase{value: (priceWei * 4000) / 400}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(address(game), bytes32(uint256(2)), bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext));
    }

    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), GameSlots.LEVEL_PRIZE_POOL))));
        return v < 50 ether ? 50 ether : v;
    }

    // ---------------------------------------------------------------------
    // Mirrors and probes (Coinflip: stake lanes slot 0, playerState slot 2;
    // Jackpots: bafPlayer slot 0, bafLevel slot 2)
    // ---------------------------------------------------------------------

    function _stakeSlot(uint24 key, address p) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(p)), keccak256(abi.encode(uint256(key), uint256(0)))));
    }

    function _stateSlot(address p) internal view returns (bytes32) {
        return keccak256(abi.encode(game.walletIdOf(p), uint256(2)));
    }

    function _scoreSlot(address p, uint24 lvl) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(p)), keccak256(abi.encode(uint256(lvl), uint256(0)))));
    }

    /// @dev The claimer takes the vault's whole coinflip position: state words and every stake
    ///      lane through `throughDay` (the claimer holds none of its own).
    function _mirrorVault(uint24 throughDay) internal {
        bytes32 v = _stateSlot(VAULT);
        bytes32 r = _stateSlot(REF);
        uint256 stateA = uint256(vm.load(address(coinflip), v));
        vm.store(address(coinflip), r, bytes32(stateA));
        vm.store(address(coinflip), bytes32(uint256(r) + 1), vm.load(address(coinflip), bytes32(uint256(v) + 1)));
        for (uint24 k; k <= throughDay >> 3; ++k) {
            vm.store(address(coinflip), _stakeSlot(k, REF), vm.load(address(coinflip), _stakeSlot(k, VAULT)));
            for (uint24 d = k << 3; d < (k << 3) + 8; ++d) _addSeed(d);
        }
        assertEq(_lastClaim(REF), _lastClaim(VAULT), "mirror: claim cursor");
    }

    /// @dev One day's lane, masked so the claimer's other days are untouched.
    function _mirrorLane(uint24 day) internal {
        uint256 shift = uint256(day & 7) << 5;
        uint256 mask = uint256(type(uint32).max) << shift;
        bytes32 rs = _stakeSlot(day >> 3, REF);
        uint256 v = uint256(vm.load(address(coinflip), _stakeSlot(day >> 3, VAULT)));
        uint256 r = uint256(vm.load(address(coinflip), rs));
        vm.store(address(coinflip), rs, bytes32((r & ~mask) | (v & mask)));
        _addSeed(day);
    }

    /// @dev The vault's seed stake for `day` in whole FLIP. Coinflip adds it on read for a seed
    ///      recipient (window start: slot 4, byte 25), so a mirrored claimer stores it in its lane.
    function _seedUnits(uint24 day) internal view returns (uint256) {
        uint256 start = (uint256(vm.load(address(coinflip), bytes32(uint256(4)))) >> 200) & 0xFFFFFF;
        return start != 0 && day >= start && day < start + 20 ? 200_000 : 0;
    }

    function _addSeed(uint24 day) internal {
        uint256 seed = _seedUnits(day);
        if (seed == 0) return;
        bytes32 rs = _stakeSlot(day >> 3, REF);
        uint256 shift = uint256(day & 7) << 5;
        uint256 r = uint256(vm.load(address(coinflip), rs));
        uint256 lane = ((r >> shift) & type(uint32).max) + seed;
        vm.store(address(coinflip), rs, bytes32((r & ~(uint256(type(uint32).max) << shift)) | (lane << shift)));
    }

    function _mirrorScore(uint24 lvl) internal {
        vm.store(address(jackpots), _scoreSlot(REF, lvl), vm.load(address(jackpots), _scoreSlot(VAULT, lvl)));
    }

    function _stake(address p, uint24 day) internal view returns (uint256) {
        uint256 w = uint256(vm.load(address(coinflip), _stakeSlot(day >> 3, p)));
        uint256 units = uint256(uint32(w >> ((uint256(day) & 7) << 5)));
        if (p == VAULT) units += _seedUnits(day);
        return units;
    }

    function _lastClaim(address p) internal view returns (uint24) {
        return uint24(uint256(vm.load(address(coinflip), _stateSlot(p))) >> 128);
    }

    /// @dev The bracket score as the draw reads it: zero once the stored epoch is stale.
    function _score(address p, uint24 lvl) internal view returns (uint256) {
        uint256 w = uint256(vm.load(address(jackpots), _scoreSlot(p, lvl)));
        if (uint64(w >> 192) != _bafEpoch(lvl)) return 0;
        return uint192(w);
    }

    function _bafWord(uint24 lvl) internal view returns (uint256) {
        return uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(lvl), uint256(2)))));
    }

    function _bafEpoch(uint24 lvl) internal view returns (uint64) {
        return uint64(_bafWord(lvl));
    }

    function _bafSkipped(uint24 lvl) internal view returns (bool) {
        return uint8(_bafWord(lvl) >> 72) != 0;
    }

    function _level() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 96);
    }

    function _jackpotFlags() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 184);
    }

    function _countRecorded(Vm.Log[] memory logs, address player, uint24 lvl) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (_isRecorded(logs[i], player, lvl)) ++n;
        }
    }

    function _recordedAmount(Vm.Log[] memory logs, address player, uint24 lvl) internal view returns (uint256 amount) {
        for (uint256 i; i < logs.length; ++i) {
            if (_isRecorded(logs[i], player, lvl)) {
                (uint256 a, ) = abi.decode(logs[i].data, (uint256, uint256));
                amount += a;
            }
        }
    }

    function _isRecorded(Vm.Log memory l, address player, uint24 lvl) internal view returns (bool) {
        return l.emitter == address(jackpots) && l.topics.length == 3 && l.topics[0] == BAF_RECORDED
            && l.topics[1] == bytes32(uint256(game.walletIdOf(player))) && l.topics[2] == bytes32(uint256(lvl));
    }

    function _logIndex(Vm.Log[] memory logs, address emitter, bytes32 sig, bytes32 topic1)
        internal pure returns (uint256)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 1 && logs[i].topics[0] == sig
                && logs[i].topics[1] == topic1) return i;
        }
        revert("harness: expected log missing");
    }
}

/// @title VaultBafSettlement — the x0 seal settles the vault's coinflip position into its bracket.
///
/// @notice The x0 last-purchase seal arms tomorrow's BAF draw after today's coinflip result
///         is applied, and in the same step settles the vault's resolved flips through the
///         existing `depositCoinflip(1, 0)` entry. Drives the real advance path (the
///         turbo-chained rig of BafDrawArming) and pins:
///         - Reference equality: a player holding the vault's exact position who claims at
///           the last moment that still scores the bracket (the close of the day before the
///           BAF day, before the next request promotes the level) holds the same bracket
///           score as the vault when the bracket draws, turbo or not, auto-rebuy on or off.
///         - The BAF day's own winning flip scores the NEXT bracket, for the vault (settled at
///           the next x0 seal) exactly as for the reference player.
///         - The settlement follows the day's applied result: a win on the day before the BAF
///           day is in the vault's score, recorded after that day's resolution and the arming.
///         - A skipped BAF (losing flip) still finds the vault settled: its frozen bracket score
///           is claimable as the WWXRP consolation.
contract VaultBafSettlement is VaultBafRig {
    // ---------------------------------------------------------------------
    // Reference equality and next-bracket routing
    // ---------------------------------------------------------------------

    /// @dev Turbo latch, auto-rebuy off, across two brackets: equal bracket-10 scores at the
    ///      draw, and the BAF day's win scoring bracket 20 for both.
    function testVaultMatchesLastMomentClaimerAcrossTwoBrackets() public {
        vm.pauseGasMetering();
        _driveToEve(9);
        uint24 latchDay = game.currentDayView() + 1;
        uint24 bafDay = latchDay + 1;

        _stageDay();
        _mirrorVault(latchDay);
        _mirrorScore(10);
        uint24 vaultCursorBefore = _lastClaim(VAULT);
        assertLt(vaultCursorBefore, latchDay, "harness: the vault holds unsettled days into the latch");

        _runFullDay();
        _assertLatched(9, latchDay);
        assertEq(_jackpotFlags(), 1, "harness: the latch collapses the level under turbo");
        assertEq(_lastClaim(VAULT), latchDay, "the x0 seal settles the vault through the latch day");

        // The last moment a claim still scores bracket 10: the latch day's close.
        vm.prank(REF);
        coinflip.claimCoinflips(0, 0);
        uint256 vaultScore = _score(VAULT, 10);
        assertGt(vaultScore, 0, "harness: the vault must hold bracket-10 credit");
        assertEq(vaultScore, _score(REF, 10), "vault and last-moment claimer hold the same bracket-10 score");

        // Stake the BAF day identically, then resolve it on a winning flip.
        _stageDay();
        _mirrorLane(bafDay);
        assertGt(_stake(VAULT, bafDay), 0, "harness: the vault stakes the BAF day");
        forceBit = 1;
        vm.recordLogs();
        _runFullDay();
        forceBit = 0;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_bafEpoch(10), 1, "harness: the bracket-10 BAF must resolve");
        assertEq(_countRecorded(logs, VAULT, 10) + _countRecorded(logs, REF, 10), 0,
            "no credit reaches bracket 10 between the latch-day close and its draw");

        // The BAF day's win routes to bracket 20: at once for a claim on the BAF day...
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(bafDay);
        assertTrue(win, "harness: the BAF day's flip won");
        uint256 stakeB = _stake(REF, bafDay);
        uint256 payoutB = stakeB + (stakeB * reward) / 100;
        vm.recordLogs();
        vm.prank(REF);
        coinflip.claimCoinflips(0, 0);
        logs = vm.getRecordedLogs();
        assertEq(_recordedAmount(logs, REF, 20), payoutB, "the BAF day's win scores bracket 20");
        assertEq(_countRecorded(logs, REF, 10), 0, "and never bracket 10");
        assertEq(_lastClaim(VAULT), latchDay, "the vault holds the BAF day for its next settlement");

        // ...and for the vault at the next x0 seal. Each later day's lane is mirrored once it is
        // final (staged on the eve of that day), ahead of any intermediate vault settlement.
        mirrorDaily = true;
        _driveToEve(19);
        uint24 latch2 = game.currentDayView() + 1;
        _stageDay();
        _runFullDay();
        _assertLatched(19, latch2);
        assertEq(_lastClaim(VAULT), latch2, "the next x0 seal settles the vault through its latch day");
        vm.prank(REF);
        coinflip.claimCoinflips(0, 0);
        uint256 vault20 = _score(VAULT, 20);
        assertGe(vault20, payoutB, "the vault's bracket-20 score carries the BAF day's win");
        assertEq(vault20, _score(REF, 20), "vault and claimer agree on bracket 20");
    }

    /// @dev Latch three purchase days past the level's start (no turbo), vault and claimer on
    ///      auto-rebuy with a take-profit: equal scores at the draw.
    function testVaultMatchesLastMomentClaimerWithoutTurboOnAutoRebuy() public {
        vm.pauseGasMetering();
        _settleToday();
        vm.prank(VAULT);
        coinflip.setCoinflipAutoRebuy(0, true, 7_000 ether);
        holdLevel = 9;
        holdDays = 3;
        _driveToEve(9);
        uint24 latchDay = game.currentDayView() + 1;

        _stageDay();
        _mirrorVault(latchDay);
        _mirrorScore(10);
        (bool rebuy,,,) = coinflip.coinflipAutoRebuyInfo(REF);
        assertTrue(rebuy, "harness: the claimer mirrors the vault's auto-rebuy");

        _runFullDay();
        _assertLatched(9, latchDay);
        assertEq(_jackpotFlags(), 0, "harness: the latch must land past the turbo window");
        assertEq(_lastClaim(VAULT), latchDay, "the x0 seal settles the vault through the latch day");

        vm.prank(REF);
        coinflip.claimCoinflips(0, 0);
        uint256 vaultScore = _score(VAULT, 10);
        assertGt(vaultScore, 0, "harness: the vault must hold bracket-10 credit");
        assertEq(vaultScore, _score(REF, 10), "vault and last-moment claimer hold the same bracket-10 score");
        (,, uint256 vaultCarry,) = coinflip.coinflipAutoRebuyInfo(VAULT);
        (,, uint256 refCarry,) = coinflip.coinflipAutoRebuyInfo(REF);
        assertEq(vaultCarry, refCarry, "both positions roll the same carry into the BAF day");

        _stageDay();
        vm.recordLogs();
        _runFullDay();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countRecorded(logs, VAULT, 10) + _countRecorded(logs, REF, 10), 0,
            "no credit reaches bracket 10 between the latch-day close and its draw");
        assertTrue(_bafEpoch(10) == 1 || _bafSkipped(10), "harness: the bracket-10 BAF must draw or skip");
    }

    // ---------------------------------------------------------------------
    // Settlement follows the latch day's applied result
    // ---------------------------------------------------------------------

    function testLatchDayWinCountsAfterItsResolution() public {
        vm.pauseGasMetering();
        _driveToEve(9);
        uint24 latchDay = game.currentDayView() + 1;

        // Settle everything before the latch day, so the latch day's stake is the vault's only
        // unsettled flip; then stake it.
        vm.prank(POKER);
        coinflip.depositCoinflip(1, 0);
        _stageDay();
        uint256 stake = _stake(VAULT, latchDay);
        assertGt(stake, 0, "harness: the vault stakes the latch day");
        uint256 before = _score(VAULT, 10);

        forceBit = 1;
        vm.recordLogs();
        _runFullDay();
        forceBit = 0;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertLatched(9, latchDay);

        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(latchDay);
        assertTrue(win, "harness: the latch day's flip won");
        uint256 payout = stake + (stake * reward) / 100;
        assertEq(_score(VAULT, 10) - before, payout, "the latch day's win is in the vault's bracket score");

        uint256 resolvedAt = _logIndex(logs, address(coinflip), DAY_RESOLVED, bytes32(uint256(latchDay)));
        uint256 armedAt = _logIndex(logs, address(coinflip), DRAW_ARMED, bytes32(uint256(latchDay + 1)));
        uint256 recordedAt = _logIndex(logs, address(jackpots), BAF_RECORDED, bytes32(uint256(1)));
        assertLt(resolvedAt, armedAt, "the draw arms after the latch day's result is applied");
        assertLt(armedAt, recordedAt, "the vault settles at the arming, after the applied result");
        assertEq(_countRecorded(logs, VAULT, 10), 1, "one settlement on the latch day");
    }

    // ---------------------------------------------------------------------
    // A skipped BAF still settles the vault
    // ---------------------------------------------------------------------

    function testSkippedBafFindsTheVaultSettled() public {
        vm.pauseGasMetering();
        _driveToEve(9);
        uint24 latchDay = game.currentDayView() + 1;
        _stageDay();
        assertLt(_lastClaim(VAULT), latchDay, "harness: the vault holds unsettled days into the latch");
        _runFullDay();
        _assertLatched(9, latchDay);
        assertEq(_lastClaim(VAULT), latchDay, "the x0 seal settles the vault before the BAF day's flip");
        uint256 frozen = _score(VAULT, 10);
        assertGt(frozen, 0, "harness: the vault must hold bracket-10 credit");

        _stageDay();
        forceBit = 2;
        _runFullDay();
        forceBit = 0;
        assertTrue(_bafSkipped(10), "harness: the losing BAF day skips the bracket");
        assertEq(_bafEpoch(10), 0, "a skipped bracket keeps its epoch");
        assertEq(_score(VAULT, 10), frozen, "the settled score is frozen by the skip");
        assertEq(jackpots.bafConsolationOf(VAULT, 10), frozen / 1000, "the vault's settled score is its consolation");

        uint256 wwxrpBefore = wwxrp.claimable(game.walletIdOf(VAULT));
        jackpots.claimBafConsolation(1, 10);
        assertEq(wwxrp.claimable(game.walletIdOf(VAULT)) - wwxrpBefore, frozen / 1000, "the consolation pays the vault");
    }
}
