// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDecimatorModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

// ReviewFixes0924 — regression tests for the 2026-09-24 review fixes.
//
//   T1  a VRF stall that recovers past the purchase deadline does not fire liveness before the
//       next advance's backfill credits the skipped days (unit + integration).
//   T2  terminal routing is irreversible: sDGNRS redemption waits (EndingPending) while liveness
//       reads true before game over; sealed Decimator battles remain settleable through the ending
//       and receive a full claim window after their last completion; the foil drain's terminal
//       flag keys on the ending latch, not the liveness predicate.
//   T3  a vault DGVE burn whose afking shortfall exceeds the game's ETH is paid ETH + stETH.
//   T4  the terminal jackpot pays exact shares: one wei in the pot moves a winner by wei, not a
//       whole ticket unit.
// Error selectors are spelled as literals so this file also compiles against the
//      pre-fix sources (red/green proof).

bytes4 constant ENDING_PENDING = bytes4(keccak256("EndingPending()"));

// =====================================================================================
// T1 — stall recovered past the deadline
// =====================================================================================

contract RecoveredStallLivenessHarness is DegenerusGameStorage {
    function seed(uint24 lvl, uint24 age, uint24 sealedAge, uint48 lastVrf) external {
        level = lvl;
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - age;
        dailyIdx = day - sealedAge;
        rngRequestTime = 0;
        lastVrfProcessedTimestamp = lastVrf;
    }

    function liveness() external view returns (bool) {
        return _livenessTriggered();
    }
}

contract RecoveredStallLivenessUnitTest is Test {
    RecoveredStallLivenessHarness private h;

    function setUp() public {
        vm.warp(1000 days + 12 hours);
        h = new RecoveredStallLivenessHarness();
    }

    /// @notice Past the deadline, behind by a gap, nothing in flight — but the late word was
    ///         applied today (or yesterday): a recovered stall, not an unattended gap.
    function test_recoveredStallWordTodayIsNotTriggered() public {
        h.seed(5, 33, 3, uint48(block.timestamp));
        assertFalse(h.liveness(), "a stall whose late word landed today waits for its backfill credit");
        h.seed(5, 33, 3, uint48(block.timestamp - 1 days));
        assertFalse(h.liveness(), "a late word applied yesterday also waits");
    }

    /// @notice A gap behind dailyIdx waits for its credit whenever the last word was applied: the
    ///         deadline fires only on a caught-up day.
    function test_gapWaitsWhateverTheLastWord() public {
        h.seed(5, 33, 3, uint48(block.timestamp - 2 days));
        assertFalse(h.liveness(), "a gap is a stall of that length and waits for its credit");
        h.seed(5, 33, 1, uint48(block.timestamp - 2 days));
        assertTrue(h.liveness(), "control: caught up past the deadline fires");
    }
}

/// @dev Level-1 purchase phase `age` days in, sealed yesterday, target unmet; plus read-backs.
contract ReviewDeadlineSeeder is DegenerusGame {
    function seed(uint24 age) external {
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }

    function clock() external view returns (uint24 psd, uint24 idx) {
        return (purchaseStartDay, dailyIdx);
    }

    function recordedWord(uint24 day) external view returns (uint256) {
        return _recordedDailyWord(day);
    }
}

contract RecoveredStallIntegrationTest is DeployProtocol {
    bytes private realCode;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 20 ether);
        realCode = address(game).code;
    }

    function _clock() private returns (uint24 psd, uint24 idx) {
        vm.etch(address(game), type(ReviewDeadlineSeeder).runtimeCode);
        (psd, idx) = ReviewDeadlineSeeder(payable(address(game))).clock();
        vm.etch(address(game), realCode);
    }

    function _recordedWord(uint24 day) private returns (uint256 word) {
        vm.etch(address(game), type(ReviewDeadlineSeeder).runtimeCode);
        word = ReviewDeadlineSeeder(payable(address(game))).recordedWord(day);
        vm.etch(address(game), realCode);
    }

    function _answer() private {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (!done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, "review-word"))));
    }

    /// @notice The request for the day before the deadline day stalls; its word lands three days
    ///         later with the target unmet. The advance that finishes the stalled day must leave
    ///         liveness off, and the next advance credits the skipped days and carries on.
    function test_stallRecoveredPastDeadlineDoesNotEndTheLevel() public {
        vm.etch(address(game), type(ReviewDeadlineSeeder).runtimeCode);
        ReviewDeadlineSeeder(payable(address(game))).seed(29); // today = the day before the deadline day
        vm.etch(address(game), realCode);

        uint24 d = game.currentDayView();
        for (uint256 i; i < 40 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "day D requested; VRF stalls");
        (uint24 psd0,) = _clock();

        // vm.getBlockTimestamp, not block.timestamp: via-IR caches the latter across warps.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        uint24 w = game.currentDayView();
        assertEq(w, d + 3, "harness: three days later");
        assertGt(w, psd0 + 30, "harness: past the purchase deadline");
        assertFalse(game.livenessTriggered(), "a request in flight waits (both before and after the fix)");

        // The late word lands; the advance finishes the stalled day on it (RNGREUSE clamp).
        _answer();
        for (uint256 i; i < 200 && game.rngLocked(); ++i) {
            game.mineFlip();
            _answer();
        }
        assertFalse(game.rngLocked(), "the stalled day finished");
        assertTrue(_recordedWord(d) != 0, "on its own late word");
        assertEq(game.rngWordForDay(d), 0, "the public view expires words older than yesterday");
        (, uint24 idx1) = _clock();
        assertEq(idx1, d, "harness: only the stalled day sealed; the gap is not yet credited");
        assertFalse(game.gameOver(), "not over");

        // THE FIX: nothing in flight, behind by a gap, past the deadline — but the word was
        // applied today, so this is a recovered stall awaiting its backfill credit.
        assertFalse(game.livenessTriggered(), "recovered stall: liveness must not fire before the backfill");

        // The next advance requests today's word, backfills the gap and credits it.
        _finishReadConsumers();
        for (uint256 i; i < 200; ++i) {
            assertFalse(game.gameOver(), "the level must not end");
            _answer();
            game.mineFlip();
            _answer();
            if (!game.rngLocked() && game.rngWordForDay(w) != 0) break;
        }
        assertFalse(game.gameOver(), "the game continues");
        assertTrue(game.rngWordForDay(w) != 0, "today sealed");
        (uint24 psd2, uint24 idx2) = _clock();
        assertEq(psd2, psd0 + (w - d - 1), "the skipped days were credited to the deadline");
        assertEq(idx2, w, "caught up");
        assertFalse(game.livenessTriggered(), "and liveness stays off");
    }
}

// =====================================================================================
// T2 — terminal routing waits for game over
// =====================================================================================

contract ReviewClaimSeeder is DegenerusGame {
    /// @dev Past the purchase deadline, caught up, target unmet: liveness reads true, !gameOver.
    function seedLiveness() external {
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - 31;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        rngRequestTime = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }

    /// @dev A ranked decimator round at `lvl` whose lone winner is `player`, at the head of the
    ///      queue, so mineFlip's leg pays it directly.
    function seedDecRound(uint24 lvl, address player, uint96 poolWei) external {
        decBattleRounds[lvl].poolWei = poolWei;
        decBattleRounds[lvl].phase = 2;
        decBattleRounds[lvl].count = 1;
        decBattleRounds[lvl].winners = 1;
        decBattleRounds[lvl].champion = 1;
        decBattlePlayers[player] = (uint256(lvl) << 64) | 1;
        decBattleEntries[(uint256(lvl) << 64) | 1] = (uint256(1) << 190) | uint256(uint160(player));
        decBattleHeap[0] = 1;
        decBattleQueue = uint256(lvl) | uint256(lvl) << 24;
        // Back the credit a settle would write (claimablePool is the ledger total).
        claimablePool += uint128(poolWei);
    }

    function seedLosingKeeperRun(uint24 lvl) external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day; purchaseStartDay = day;
        rngLockedFlag = false; ticketsFullyProcessed = true; subsFullyProcessed = true;
        _afkingResetDay = day;
        DecBattleRound storage round = decBattleRounds[lvl];
        // Eight losing runs: enough work for one knee credit (15 units) at the measured prices.
        round.phase = 1; round.winners = 0; round.champion = 0; round.capacity = 1; round.count = 8;
        for (uint160 i = 2; i <= 8; ++i) decBattleEntries[(uint256(lvl) << 64) | i] = i;
        uint256 word;
        while (!_allTails(word, lvl, 8)) ++word;
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        _setRngComplete(false);
        humanReadComplete = true;
    }

    function _allTails(uint256 word, uint24 lvl, uint64 n) private pure returns (bool) {
        for (uint64 id = 1; id <= n; ++id) {
            if (uint256(keccak256(abi.encode(keccak256("decimator.battle.final-coin.v1"), word, lvl, id))) & 1 != 0) {
                return false;
            }
        }
        return true;
    }

    function setGameOver() external {
        gameOver = true;
        _goWrite(GO_TIME_SHIFT, GO_TIME_MASK, block.timestamp - 31 days);
    }

    function swept() external view returns (bool) { return _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0; }

    /// @dev Mirrors GameAfkingModule._decimatorSettle's delegatecall, isolated from mineFlip's
    ///      other legs so the leg's own liveness/game-over gate is exercised directly.
    function settleDecOne(uint256 budgetUnits)
        external
        returns (uint256 settled, uint256 unitsUsed, bool moved)
    {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.settleDecimatorWinners.selector,
                    budgetUnits
                )
            );
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(data, 32), mload(data))
            }
        }
        (settled, unitsUsed, moved) = abi.decode(data, (uint256, uint256, bool));
    }
}

contract DecimatorLegEndingIdleTest is DeployProtocol {
    bytes private realCode;
    address private winner = makeAddr("dec-winner");
    uint24 private constant DLVL = 1;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 50 ether);
        realCode = address(game).code;
        vm.etch(address(game), type(ReviewClaimSeeder).runtimeCode);
        ReviewClaimSeeder(payable(address(game))).seedLiveness();
        ReviewClaimSeeder(payable(address(game))).seedDecRound(DLVL, winner, 1 ether);
        vm.etch(address(game), realCode);
        assertTrue(game.livenessTriggered(), "harness: liveness reads true");
        assertFalse(game.gameOver(), "harness: not over");
    }

    function _over() private {
        vm.etch(address(game), type(ReviewClaimSeeder).runtimeCode);
        ReviewClaimSeeder(payable(address(game))).setGameOver();
        vm.etch(address(game), realCode);
    }

    function test_LosingRunStillPaysOneKeeperBounty() public {
        vm.etch(address(game), type(ReviewClaimSeeder).runtimeCode);
        ReviewClaimSeeder(payable(address(game))).seedLosingKeeperRun(DLVL);
        vm.etch(address(game), realCode);
        assertFalse(game.advanceDue());
        address keeper = makeAddr("battle-keeper");
        uint256 before = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.mineFlip();
        assertGt(coinflip.coinflipAmount(keeper), before, "tails run still earns work bounty");
        assertEq(game.claimableWinningsOf(winner), 0, "tails has no ETH credit");
    }

    function test_legCreditsDuringLiveness() public {
        uint256 before = game.claimableWinningsOf(winner);
        (uint256 settled, , bool moved) = game.settleDecimatorWinners(1000);
        assertEq(settled, 1); assertTrue(moved);
        assertEq(game.claimableWinningsOf(winner), before + 1 ether);
    }

    function test_legIdlesAfterGameOver() public {
        _over();
        uint256 before = game.claimableWinningsOf(winner);
        (uint256 settled, uint256 units, bool moved) = game.settleDecimatorWinners(1500);
        assertEq(settled, 0); assertEq(units, 0); assertFalse(moved);
        assertEq(game.claimableWinningsOf(winner), before, "no credit after game over");
    }

    function test_SweepDoesNotWaitForPendingBattle() public {
        _over();
        game.mineFlip(); // Terminal deadline passed; the queued battle does not hold the sweep.
        vm.etch(address(game), type(ReviewClaimSeeder).runtimeCode);
        assertTrue(ReviewClaimSeeder(payable(address(game))).swept(), "sweep ran with a battle queued");
        vm.etch(address(game), realCode);
        assertEq(game.claimableWinningsOf(winner), 0, "the unsettled battle credits nothing");
    }

}

interface IReviewCoinflipMock {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

contract RedemptionEndingPendingTest is DeployProtocol {
    address private playerA = makeAddr("redeemer");
    uint24 private burnDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(playerA, 1 ether);
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerA, 1_000_000 ether);
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IReviewCoinflipMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IReviewCoinflipMock.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );

        // Game ETH + sDGNRS claimable back the reservation (RedemptionStethFallback (a) shape).
        vm.deal(address(game), 100 ether);
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 word = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((word & (type(uint256).max << 128)) | uint256(100 ether)));
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        vm.store(address(game), bytes32(uint256(1)), bytes32((s1 & type(uint128).max) | (uint256(100 ether) << 128)));

        _primeCurrentDayRng();
        burnDay = game.currentDayView();
        vm.prank(playerA);
        sdgnrs.burn(1_000_000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _primeCurrentDayRng();
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(100, burnDay);
    }

    function _mockEnding(bool over) private {
        vm.mockCall(address(game), abi.encodeWithSelector(game.livenessTriggered.selector), abi.encode(true));
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(over));
    }

    function test_claimWaitsWhileLivenessReadsTrueThenSettlesTerminal() public {
        (uint96 owed,,) = sdgnrs.pendingRedemptions(playerA, burnDay);
        assertGt(owed, 0, "harness: a claim is pending");

        _mockEnding(false);
        vm.prank(playerA);
        vm.expectRevert(ENDING_PENDING);
        sdgnrs.claimRedemption(playerA, burnDay);
        (uint96 still,,) = sdgnrs.pendingRedemptions(playerA, burnDay);
        assertEq(still, owed, "nothing settled while pending");

        _mockEnding(true);
        uint256 eth0 = playerA.balance;
        uint256 st0 = mockStETH.balanceOf(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, burnDay);
        uint256 got = (playerA.balance - eth0) + (mockStETH.balanceOf(playerA) - st0);
        assertApproxEqAbs(got, owed, 2, "terminal after game over: the whole rolled value paid direct");
        (uint96 cleared,,) = sdgnrs.pendingRedemptions(playerA, burnDay);
        assertEq(cleared, 0, "claim consumed");
    }
}

/// @dev Foil module etched at GAME: the drain runs in this storage.
contract ReviewFoilHarness is DegenerusGameFoilPackModule {
    function setFoilPack(uint24 day, uint24 lvl, address buyer, uint16 multBps) external {
        foilRecord[lvl & 3][buyer] = uint256(day) | (uint256(multBps) << _FOIL_MULT_SHIFT)
            | (uint256(lvl) << _FOIL_LEVEL_SHIFT);
        uint256 ownerIdx = uint256(_registerEntryOwner(buyer, lvl) >> OWNER_IDX_SHIFT) - 1;
        foilQueue[_foilReadKey()].push(((ownerIdx + 1) << 192) | (uint256(lvl) << 160) | uint256(uint160(buyer)));
    }

    function setWordAndWindow(uint24 day, uint256 word) external {
        _recordDailyRng(day, word);
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        foilGenerationDay = day;
        foilFirstDrawDay = day;
        foilCursor = 0;
    }

    /// @dev Identical slot writes in every case, so only the values differ between measurements.
    ///      liveTrigger: past the purchase deadline, caught up, target unmet.
    function setCase(bool liveTrigger, bool latchLvl) external {
        uint24 day = _simulatedDayIndex();
        level = 5;
        purchaseStartDay = day - (liveTrigger ? 31 : 5);
        dailyIdx = day - 1;
        rngRequestTime = 0;
        levelPrizePool[5] = 10 ether;
        _setPrizePools(9 ether, 0);
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, latchLvl ? 2 : 0);
    }

    function liveness() external view returns (bool) {
        return _livenessTriggered();
    }

    function drainGas() external returns (uint256 used) {
        uint256 g0 = gasleft();
        (bool done,) = this.processFoilDrain(1000);
        used = g0 - gasleft();
        require(done, "harness: the drain finished in one call");
    }
}

/// @notice The only thing the drain's terminal flag changes is whether each pack's gold is read
///         for the grand push (`_packGold` + the grand check). A grand needs two all-gold tickets
///         (~1 in 7.1 billion packs), past any entropy search, so the flag is observed through
///         that per-pack work: eight packs drained non-terminal cost measurably more than the same
///         eight drained terminal, and the liveness-only state must cost exactly the same as the
///         plain live state (same flag, same reads).
contract FoilDrainTerminalFlagTest is Test {
    ReviewFoilHarness private h;
    uint24 private constant DAY = 900;
    uint24 private constant FLVL = 6;

    function setUp() public {
        vm.warp(1000 days + 12 hours);
        ReviewFoilHarness impl = new ReviewFoilHarness();
        vm.etch(ContractAddresses.GAME, address(impl).code);
        h = ReviewFoilHarness(payable(ContractAddresses.GAME));
        for (uint256 i; i < 8; ++i) h.setFoilPack(DAY, FLVL, address(uint160(0xF0A100 + i)), 60000);
        h.setWordAndWindow(DAY, uint256(keccak256("review-foil-word")) | 1);
    }

    function _measure(uint256 snap, bool liveTrigger, bool latch) private returns (uint256 g, bool live) {
        vm.revertToState(snap);
        h.setCase(liveTrigger, latch);
        live = h.liveness();
        g = h.drainGas();
    }

    function test_drainTerminalFlagKeysOnTheLatchNotLiveness() public {
        uint256 snap = vm.snapshotState();
        _measure(snap, false, false); // warm-up so every measured run sees the same access state
        (uint256 gLive, bool l0) = _measure(snap, false, false);
        (uint256 gTrig, bool l1) = _measure(snap, true, false);
        (uint256 gLatch, bool l2) = _measure(snap, true, true);
        emit log_named_uint("drain gas: live", gLive);
        emit log_named_uint("drain gas: liveness true, no latch", gTrig);
        emit log_named_uint("drain gas: ending latched", gLatch);

        assertFalse(l0, "harness: plain live state");
        assertTrue(l1, "harness: liveness reads true with no ending latch");
        assertTrue(l2, "harness: latched ending");

        assertEq(gTrig, gLive, "liveness alone must not make the drain terminal (grand check still runs)");
        assertGt(gLive, gLatch + 2000, "a latched ending makes the drain terminal (grand check skipped per pack)");
    }
}

// =====================================================================================
// T3 — vault burn with the game holding mostly stETH
// =====================================================================================

contract VaultBurnStethFallbackTest is DeployProtocol {
    address private owner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        owner = ContractAddresses.CREATOR;
        require(vault.isVaultOwner(owner), "fixture: CREATOR holds the DGVE majority");
    }

    receive() external payable {}

    function test_burnEthPaysInFullWhenTheGameHoldsMostlyStEth() public {
        vm.deal(address(vault), 100 ether);
        vm.prank(owner);
        vault.gameDepositAfkingFunding(90 ether);
        assertEq(address(vault).balance, 10 ether, "harness: the vault keeps 10 ETH");

        // The game's reserve is mostly stETH: 10 ETH on hand, 200 stETH.
        vm.deal(address(game), 10 ether);
        mockStETH.mint(address(game), 200 ether);

        uint256 burn = 1_000_000_000_000 * 1e18 / 2;
        (uint256 previewOut, uint256 previewSt) = vault.previewEth(burn);
        uint256 claim = previewOut + previewSt;
        assertGt(claim, 10 ether + 10 ether, "harness: the shortfall exceeds the game's ETH");

        uint256 eth0 = owner.balance;
        uint256 st0 = mockStETH.balanceOf(owner);
        vm.prank(owner);
        (uint256 ethOut, uint256 stOut) = vault.burnEth(burn);

        assertEq(ethOut + stOut, claim, "the burn pays the full claim");
        assertGt(stOut, 0, "part of it in stETH");
        assertEq(owner.balance - eth0, ethOut, "ETH leg paid");
        assertApproxEqAbs(mockStETH.balanceOf(owner) - st0, stOut, 2, "stETH leg paid");
    }
}

// =====================================================================================
// T4 — terminal jackpot pays exact shares
// =====================================================================================

contract ReviewTerminalHarness is DegenerusGameJackpotModule, BucketSeed {
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        _seedBucketDistinct(lvl, traitId, count, base);
    }

    function claimableOf(address who) external view returns (uint256) {
        return _claimableOf(who);
    }

    function whalePassOf(address who) external view returns (uint256) {
        return whalePassClaims[who];
    }
}

contract TerminalExactSharesTest is Test {
    ReviewTerminalHarness private h;
    uint24 private constant TLVL = 110;
    uint64 private constant FINAL_DAY_SHARES_PACKED =
        (uint64(6000)) | (uint64(1333) << 16) | (uint64(1333) << 32) | (uint64(1334) << 48);
    uint256 private constant HOLDERS = 305;

    function setUp() public {
        h = new ReviewTerminalHarness();
    }

    function _word() private pure returns (uint256 word) {
        word = uint256(keccak256("jgas03-single-call-fixed-word"));
        while (true) {
            uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
            bool gold;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) gold = true;
            if (!gold) return word;
            ++word;
        }
    }

    function _geometry(uint256 word)
        private
        pure
        returns (uint8[4] memory traitIds, uint16[4] memory bc, uint16[4] memory shareBps, uint8 soloIdx)
    {
        traitIds = JackpotBucketLib.getRandomTraits(word);
        uint256 entropy = EntropyLib.hash2(word, TLVL);
        uint8 soloQuadrant = uint8((3 - (entropy & 3)) & 3);
        uint256 eff = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3);
        bc = JackpotBucketLib.terminalWinnerCounts(eff);
        shareBps = JackpotBucketLib.shareBpsByBucket(FINAL_DAY_SHARES_PACKED, uint8(eff & 3));
        soloIdx = JackpotBucketLib.soloBucketIndex(eff);
    }

    function _credits() private view returns (uint256[] memory c) {
        c = new uint256[](4 * HOLDERS);
        for (uint256 b; b < 4; ++b) {
            uint160 base = uint160((b + 1) * 1_000_000_000);
            for (uint256 i; i < HOLDERS; ++i) {
                address who = address(base + uint160(i + 1));
                // Value-weighted: a solo winner's whale-pass leg counts at the half-pass price.
                c[b * HOLDERS + i] = h.claimableOf(who) + h.whalePassOf(who) * 2.25 ether;
            }
        }
    }

    function test_oneWeiMovesEachWinnerByWeiNotAUnit() public {
        uint256 word = _word();
        (uint8[4] memory traitIds, uint16[4] memory bc, uint16[4] memory shareBps, uint8 soloIdx) = _geometry(word);
        for (uint8 b; b < 4; ++b) h.seedBucket(TLVL, traitIds[b], HOLDERS, uint160(uint256(b + 1) * 1_000_000_000));

        // A pot sitting exactly on the OLD rounding edge of one non-solo bucket: at `pot` that
        // bucket's share is k whole ticket units per winner, at pot - 1 it was k - 1.
        uint8 edge = soloIdx == 0 ? 1 : 0;
        uint256 unitBucket = (PriceLookupLib.priceForLevel(TLVL + 1) >> 2) * bc[edge];
        uint256 k = (1000 ether * uint256(shareBps[edge]) / 10_000) / unitBucket;
        uint256 pot = (k * unitBucket * 10_000 + shareBps[edge] - 1) / shareBps[edge];

        uint256 snap = vm.snapshotState();
        vm.prank(ContractAddresses.GAME);
        uint256 paidLo = h.runTerminalJackpot(pot - 1, TLVL, word);
        uint256[] memory lo = _credits();

        vm.revertToState(snap);
        vm.prank(ContractAddresses.GAME);
        uint256 paidHi = h.runTerminalJackpot(pot, TLVL, word);
        uint256[] memory hi = _credits();

        uint256 paidMove = paidHi > paidLo ? paidHi - paidLo : paidLo - paidHi;
        emit log_named_uint("paid move (wei)", paidMove);
        assertLe(paidMove, HOLDERS, "one more wei in moves the total paid by at most a wei per winner");
        uint256 maxMove;
        for (uint256 i; i < lo.length; ++i) {
            uint256 d = hi[i] > lo[i] ? hi[i] - lo[i] : lo[i] - hi[i];
            if (d > maxMove) maxMove = d;
        }
        emit log_named_uint("max per-holder move (wei)", maxMove);
        assertLe(maxMove, 8, "one wei in the pot moves a winner by wei, not a ticket unit");
    }
}
