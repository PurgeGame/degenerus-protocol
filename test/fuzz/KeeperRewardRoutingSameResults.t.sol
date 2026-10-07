// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title FFKeyHarness -- Exposes _tqFarFutureKey as a pure helper for the GASOPT-01 owed-slot math.
/// @dev Inherits DegenerusGameStorage solely to surface the far-future key derivation the seed helpers
///      key on. Zero behavioral coupling to the FROZEN subject.
contract FFKeyHarness is DegenerusGameStorage {
    function ffKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @notice Measured miner compensation and existing batched-view/accounting regressions.
/// @dev Reward observation is isolated to the miner recipient. Compensation depends on
/// reported execution gas and capped base fee, independently of the supplied gas limit.
contract KeeperRewardRoutingSameResults is DeployProtocol {
    // -------------------------------------------------------------------------
    // creditFlip-count / amount oracle — the recipient-isolated DIFFERENTIAL instrument
    // (PRESERVED VERBATIM: 351-04/05/08 port this topic-decode).
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)") — emitted once per
    ///      creditFlip. topics[1] is the indexed player (recipient isolation); the non-indexed
    ///      `amount` is the first 32 bytes of `data`.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    // -------------------------------------------------------------------------
    // DegenerusGame pinned slot layout (RE-DERIVED via `forge inspect storage DegenerusGame`;
    // the AfKing-standalone SUBOF_SLOT=65 / TICKET_QUEUE_SLOT=12 / TICKETS_OWED_PACKED_SLOT=13 were WRONG).
    // -------------------------------------------------------------------------

    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay (bytes 11..13 of the Sub slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // _subscribers address[] (length here)
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit)
    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;

    uint256 private constant CLAIMABLE_POOL_SLOT = GameSlots.CLAIMABLE_POOL; // uint128 packed at offset 16 of slot 1
    uint256 private constant BALANCES_PACKED_SLOT = GameSlots.BALANCES_PACKED; // mapping(address => uint256) balancesPacked [afking:high128 | claimable:low128]
    uint256 private constant TICKET_QUEUE_SLOT = GameSlots.TICKET_QUEUE; // mapping(uint24 => address[])
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13; // mapping(uint24 => mapping(address => uint40))

    FFKeyHarness private ffk;
    address private keeper;
    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;
    uint256 private _passFactor = 1;

    function setUp() public {
        _deployProtocol();
        vm.fee(1 gwei);
        // One keeper-local day off the deploy boundary so the day index is a clean, stable value
        // (mirrors AfKingConcurrency / V55SetMutationOpenE).
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        ffk = new FFKeyHarness();
        keeper = makeAddr("routing_keeper");
        vm.deal(keeper, 100_000 ether);
        vm.deal(address(game), 5_000_000 ether);
    }

    /// @dev Settle the game to a clean state: complete the pending day-advance (drive mineFlip +
    ///      deliver the mock VRF word + drain the rngLock) until advanceDue() is false and we are not
    ///      locked. PRESERVED VERBATIM — the donor VRF-drain helper (PATTERNS §"Settle-to-clean-state
    ///      VRF drain"); 351-04/05/08 port this.
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
        _finishReadConsumers();
    }

    // =========================================================================
    // Native mining reward routing.
    /// @notice Supplying more than 10M gas cannot earn a reward for less than 1M of work.
    function test_HighEntryTinyWorkIsUnpaid() public {
        // Settle the deploy-day advance, then roll the wall clock so a fresh day-advance is due.
        _settleGame(0x57A11A10E0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        address caller = makeAddr("standalone_advance_caller");

        vm.recordLogs();
        vm.prank(caller);
        game.mineFlip{gas: 15_000_000}();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 workEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game)
                && logs[i].topics[0] == keccak256("MinerWork(address,uint8,uint256,uint256)")) {
                (, uint256 used, uint256 paid) = abi.decode(logs[i].data, (uint8,uint256,uint256));
                assertGt(used, 0, "a real preparation or maintenance step performed work");
                assertLt(used, 1_000_000, "fixture must exercise sub-threshold work");
                assertEq(paid, 0, "high entry gas cannot reward a small final work item");
                ++workEvents;
            }
            if (logs[i].emitter == address(coinflip) && logs[i].topics.length > 1
                && logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG) {
                assertNotEq(logs[i].topics[1], bytes32(uint256(game.walletIdOf(caller))), "tiny work credited the miner");
            }
        }
        assertEq(workEvents, 1, "the request must report measured progress");
        assertFalse(game.gameOver(), "liveness work remains in the live game");

        // MinerWork is emitted only after actual progress; the first preparation or
        // maintenance checkpoint need not also reach the following VRF request.
    }

    /// @notice A delay never exempts a small checkpoint from the measured-gas cutoff.
    function testMineFlipPricesMeasuredWorkAtBothStallTimes() public {
        _settleGame(0xADADAD0002);
        assertFalse(game.advanceDue());
        assertFalse(game.rngLocked());
        uint256 snap = vm.snapshotState();
        _mintFlipAdvanceCreditAtStall(31 minutes);
        vm.revertToState(snap);
        _mintFlipAdvanceCreditAtStall(2 hours + 1 minutes);
    }

    /// @dev Observe one real preparation checkpoint after a delayed daily reset.
    function _mintFlipAdvanceCreditAtStall(uint256 stallElapsed) internal returns (uint256) {
        // Move to the START of the NEXT calendar-day window, then add the stall offset. The advance
        // module derives day = _simulatedDayIndexAt(ts) = (ts-82620)/1days + 1, and the stall window is
        // elapsed = (ts-82620) mod 1days (DEPLOY_DAY_BOUNDARY==0). Rolling _today() forward by 1 makes a
        // fresh day-advance due; the offset INTO that day window is exactly `stallElapsed`, so the stall
        // ladder resolves as intended.
        uint32 dayNow = _today();
        uint256 nextDayStart = (uint256(dayNow + 1) * 1 days) + 82_620; // start of the next day's window
        vm.warp(nextDayStart + stallElapsed);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due at the chosen stall");

        uint256 rewardPrice = game.mintPrice();
        uint256 elapsed = _rewardElapsed();
        bool lockedAtStart = game.rngLocked();
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();

        // Read the recorded logs ONCE (vm.getRecordedLogs drains them) and derive BOTH the count and the
        // credited amount in a single pass, so the amount is not lost to a prior drain.
        (uint256 count, uint256 amount) = _keeperCreditCountAndAmount(rewardPrice, elapsed, lockedAtStart);
        assertEq(count, amount == 0 ? 0 : 1, "only qualifying measured work credits the miner");
        return amount;
    }

    /// @dev Single-pass recorded-log read returning (count, summed amount) of the keeper's
    ///      CoinflipStakeUpdated emissions. Avoids the double-getRecordedLogs drain hazard.
    function _keeperCreditCountAndAmount(uint256 rewardPrice, uint256 elapsed, bool lockedAtStart)
        internal returns (uint256 count, uint256 amount)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 declaredReward;
        uint256 workEvents;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("MinerWork(address,uint8,uint256,uint256)")) {
                (, uint256 used, uint256 paid) = abi.decode(logs[i].data, (uint8,uint256,uint256));
                uint256 step = elapsed / 30 minutes;
                if (step > 4) step = 4;
                uint256 cap = uint256(0.5 gwei) << step;
                uint256 rate = block.basefee < cap ? block.basefee : cap;
                uint256 expected = used <= 1_000_000 ? 0
                    : (used - 1_000_000) * rate * 1000 ether * (3000 + step * 4500) * _passFactor * (lockedAtStart ? 2 : 1)
                        / (rewardPrice * 10_000);
                // Whole-FLIP normalization at the payment site: positive sub-FLIP pays 1 FLIP.
                if (expected != 0) expected = expected < 1 ether ? 1 : expected / 1 ether;
                assertEq(paid, expected, "reward prices qualifying measured gas at capped base fee");
                assertGt(used, 0);
                ++workEvents;
                declaredReward += paid;
            }
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                logs[i].topics[1] == bytes32(uint256(game.walletIdOf(keeper)))
            ) {
                count++;
                amount += abi.decode(logs[i].data, (uint256));
            }
        }
        assertEq(workEvents, 1, "the measured work oracle must observe real progress");
        assertEq(amount, declaredReward, "one reported reward equals the actual miner credit");
    }

    function _rewardElapsed() private view returns (uint256) {
        // One clock: the later of the latest VRF request stamp (rngRequestTime, slot 0 bits
        // 48..95; a retry keeps its origin) and the current day's reset.
        uint256 ts = vm.getBlockTimestamp();
        uint256 due = uint48(uint256(vm.load(address(game), bytes32(0))) >> 48);
        uint256 reset = ts - (ts - 82_620) % 1 days;
        if (reset > due) due = reset;
        return ts > due ? ts - due : 0;
    }

    /// @notice A published mid-day ticket cohort earns the same measured-work compensation.
    function testMidDayPartialDrainRewardedViaMintFlip() public {
        _seedMidDayCohort();
        uint256 amount = _mineSeededCohort();
        assertGt(amount, 0, "mid-day ticket work exceeds the measured-gas cutoff");
    }

    /// @notice An active pass doubles the bounty for the same measured work.
    function testActivePassDoublesMineFlipBounty() public {
        _seedMidDayCohort();
        uint256 snap = vm.snapshotState();
        uint256 plain = _mineSeededCohort();
        vm.revertToState(snap);
        _grantDeityPass(keeper);
        assertTrue(game.hasDeityPass(keeper), "pre: keeper holds a deity pass");
        _passFactor = 2;
        uint256 doubled = _mineSeededCohort();
        assertGt(plain, 0, "the plain miner is paid");
        assertApproxEqAbs(doubled, plain * 2, 1, "an active pass doubles the same work's bounty");
    }

    /// @notice Ticket work that starts under the daily RNG lock pays double.
    function testRngLockedWorkPaysDouble() public {
        _settleGame(0x10CC0001);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < DRAIN_MAX_ITERATIONS && !game.rngLocked(); i++) game.mineFlip();
        assertTrue(game.rngLocked(), "pre: the daily request holds the lock");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0x10CC0002);

        uint24 readKey = _readKey(uint24(game.level()) + 1);
        for (uint256 i; i < 200; i++) {
            _seedReadSlotTickets(readKey, makeAddr(string(abi.encodePacked("locked_player_", _u(i)))), 3);
        }
        _setTicketsFullyProcessed(false);

        assertTrue(game.rngLocked(), "pre: work starts under the lock");
        uint256 amount = _mineSeededCohort();
        assertGt(amount, 0, "locked ticket work exceeds the measured-gas cutoff");
    }

    /// @dev Model an authenticated, published mid-day cohort with enough ticket
    ///      work to cross the reward cutoff and reach a resumable checkpoint.
    function _seedMidDayCohort() internal {
        // Settle to a clean, not-due, not-locked baseline: `day == dailyIdx` (the mid-day precondition).
        _settleGame(0x1D0E0003);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");
        assertFalse(game.gameOver(), "pre: game live");

        // Compute the mid-day purchaseLevel + read key exactly as the contract does (purchase phase,
        // not lastPurchaseDay, not rngLocked => purchaseLevel = level + 1; read key honours ticketWriteSlot).
        uint24 purchaseLevel = uint24(game.level()) + 1;
        uint24 readKey = _readKey(purchaseLevel);

        uint256 M = 200;
        for (uint256 i; i < M; i++) {
            _seedReadSlotTickets(readKey, makeAddr(string(abi.encodePacked("midday_player_", _u(i)))), 3); // 3 whole tickets each (12 entries)
        }
        _setTicketsFullyProcessed(false);
        RecyclingState.seedWord(address(game), RecyclingState.readBuffer(address(game)), bytes32(uint256(0x1D0E0003)));

        assertTrue(game.advanceDue(), "pre: a mid-day partial-drain advance is due (read slot un-fully-processed)");
        assertFalse(game.rngLocked(), "pre: not locked (mid-day, no escalation)");
    }

    /// @dev One keeper mineFlip over seeded work, checked against the reward oracle.
    function _mineSeededCohort() internal returns (uint256 amount) {
        uint256 rewardPrice = game.mintPrice();
        uint256 elapsed = _rewardElapsed();
        bool lockedAtStart = game.rngLocked();
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip{gas: 9_500_000}();

        uint256 count;
        (count, amount) = _keeperCreditCountAndAmount(rewardPrice, elapsed, lockedAtStart);
        assertEq(count, 1, "seeded ticket work credits the miner exactly once");
    }

    /// @notice GAMEOVER idle crank reverts via mineFlip: post-gameover dailyIdx freezes so the advance
    ///         predicate stays true forever, but the only remaining advance work is the one-time 30-day
    ///         final sweep. With no sweep pending (GO_TIME==0 here, mirroring the real within-30-day /
    ///         already-swept states) mineFlip refuses the idle crank with NoWork() rather than running the
    ///         gameover advance leg as a free unrewarded no-op. Zero creditFlip either way.
    function testGameoverAdvanceUnrewarded() public {
        // Settle, then make a fresh day-advance due.
        _settleGame(0x90E00004);
        assertFalse(game.advanceDue(), "pre: settled");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        // Latch the terminal gameOver flag (the public bool). GO_TIME stays 0, so _finalSweepPending()
        // is false — the same result the real within-30-day / already-swept post-gameover states give.
        _latchGameOver();
        assertTrue(game.gameOver(), "pre: gameOver latched");

        vm.recordLogs();
        vm.prank(keeper);
        vm.expectRevert(); // GameAfkingModule.NoWork() — no sweep pending, no free idle crank
        game.mineFlip();

        // Nothing credited (the revert rolls back, but assert zero regardless of the count oracle).
        assertEq(
            _countCoinflipStakeUpdated(),
            0,
            "GAMEOVER: zero creditFlip emissions on the idle-crank NoWork revert"
        );
    }

    // =========================================================================
    // Task 2 — afkingSnapshot (the keeperSnapshot successor) + owedMap pointer-hoist same-results
    // =========================================================================

    /// @notice afkingSnapshot batched-read same-results: the batched read is VALUE-IDENTICAL to N
    ///         individual reads — `mintPriceWei == mintPrice()`, `rngLocked_ == rngLocked()`,
    ///         `claimables[i] == claimableWinningsOf(players[i])`, and
    ///         `afkingFundings[i] == afkingFundingOf(players[i])` element-by-element across N players with
    ///         varied claimable + afking-funding balances. (afkingSnapshot is the v55 rename of
    ///         keeperSnapshot — same batched-read role, with the added afkingFundings column.)
    function testAfkingSnapshotEqualsIndividualReads() public {
        // N players holding VARIED claimable + afking-funding balances (some zero, some non-zero, distinct).
        uint256 N = 6;
        address[] memory players = new address[](N);
        uint256[] memory seededClaim = new uint256[](N);
        uint256[] memory seededFund = new uint256[](N);
        for (uint256 i; i < N; i++) {
            players[i] = makeAddr(string(abi.encodePacked("snap_player_", _u(i))));
            _giveWalletId(players[i]);
            // Vary: alternate zero / non-zero, distinct magnitudes.
            seededClaim[i] = (i % 3 == 0) ? 0 : (uint256(i + 1) * 1.337 ether);
            if (seededClaim[i] > 0) _seedClaimable(players[i], seededClaim[i]);
            seededFund[i] = (i % 2 == 0) ? (uint256(i + 1) * 0.5 ether) : 0;
            if (seededFund[i] > 0) _fundAfking(players[i], seededFund[i]);
        }

        // Batched read.
        (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables, uint256[] memory afkingFundings) =
            game.afkingSnapshot(players);

        // Field 1: mintPriceWei == mintPrice().
        assertEq(mintPriceWei, game.mintPrice(), "afkingSnapshot.mintPriceWei == mintPrice()");
        // Field 2: rngLocked_ == rngLocked().
        assertEq(rngLocked_, game.rngLocked(), "afkingSnapshot.rngLocked_ == rngLocked()");
        // Field 3+4: claimables[i]/afkingFundings[i] == the individual accessors for every i.
        assertEq(claimables.length, N, "afkingSnapshot: claimables length == N");
        assertEq(afkingFundings.length, N, "afkingSnapshot: afkingFundings length == N");
        bool sawNonZeroClaim;
        bool sawNonZeroFund;
        for (uint256 i; i < N; i++) {
            assertEq(
                claimables[i],
                game.claimableWinningsOf(players[i]),
                "afkingSnapshot: claimables[i] == claimableWinningsOf(players[i])"
            );
            assertEq(
                afkingFundings[i],
                game.afkingFundingOf(players[i]),
                "afkingSnapshot: afkingFundings[i] == afkingFundingOf(players[i])"
            );
            // Non-vacuity: the batched values track the seeded balances (not a constant zero).
            assertEq(claimables[i], seededClaim[i], "afkingSnapshot non-vacuity: claimables[i] tracks the seeded balance");
            assertEq(afkingFundings[i], seededFund[i], "afkingSnapshot non-vacuity: afkingFundings[i] tracks the seeded funding");
            if (claimables[i] > 0) sawNonZeroClaim = true;
            if (afkingFundings[i] > 0) sawNonZeroFund = true;
        }
        assertTrue(sawNonZeroClaim, "afkingSnapshot non-vacuity: at least one player held a non-zero claimable");
        assertTrue(sawNonZeroFund, "afkingSnapshot non-vacuity: at least one player held a non-zero afking funding");
    }


    /// @notice GASOPT-01 (per-entry owed drain) same-results: a MULTI-PLAYER far-future ticket backlog
    ///         drains every player's owed to ZERO through the engine's ticket worker
    ///         (TicketModule `runTicketWork`, mineFlip's Tickets stage) on its far-future drain. A broken drain would skip / double-process a player, leaving
    ///         non-zero owed or mis-decrementing it; the
    ///         per-player owed RESULTS are byte-identical to the expected per-player accounting (full drain).
    function testGasopt01OwedMapHoistSameResults() public {
        // Multi-player backlog: seed M fresh players each with K whole far-future tickets at a level the
        // advance will process.
        uint24 L = 6; // a far-future level the constructor also pre-queues (sDGNRS + VAULT) — multi-player
        uint256 M = 5;
        uint32 K = 4; // 4 whole tickets => owed packed = (4*4 entries) << 8
        address[] memory players = new address[](M);
        for (uint256 i; i < M; i++) {
            players[i] = makeAddr(string(abi.encodePacked("owed_player_", _u(i))));
            _seedFarTickets(players[i], L, K);
            // Pre-condition: each seeded player has a NON-ZERO owed at the far-future key (non-vacuity).
            assertGt(_owedPackedOf(L, players[i]), 0, "pre: each seeded player has non-zero far-future owed");
        }
        uint256 queuedBefore = _ffQueueLen(L);
        assertGe(queuedBefore, M, "pre: the far-future queue holds at least the M seeded players");

        // Drive the protocol through the advance cycle past the FF-processing range for level L. The
        // engine's ticket worker (runTicketWork) drains the multi-player queue.
        _driveAdvanceThroughFarFutureProcessing(L);

        // SAME-RESULTS: every seeded player's owed drained to ZERO (the rk-loop-invariant pointer processed
        // each player exactly once — no skip, no double-count). This is the per-player owed accounting the
        // hoist produces, byte-identical to the expected full-drain result.
        for (uint256 i; i < M; i++) {
            assertEq(
                _owedPackedOf(L, players[i]),
                0,
                "GASOPT-01: each player's far-future owed drained to zero (owedMap hoist processed every player)"
            );
        }
        // And the far-future queue for level L drained to zero (all addresses removed after processing).
        assertEq(
            _ffQueueLen(L),
            0,
            "GASOPT-01: the multi-player far-future queue drained to zero (no stranded / double-processed player)"
        );
    }

    // =========================================================================
    // creditFlip-count / amount oracle (recipient-isolated — the DIFFERENTIAL instrument)
    // =========================================================================

    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 0 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG
            ) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose indexed `player` topic == `who`. The player is
    ///      topics[1] — isolates the router bounty (to the keeper) from a player/box-owner winnings credit.
    function _countCoinflipStakeUpdatedFor(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                logs[i].topics[1] == bytes32(uint256(game.walletIdOf(who)))
            ) count++;
        }
    }

    // =========================================================================
    // Protocol-driving helpers (mirror AfKingConcurrency / V55SetMutationOpenE)
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (Δ4 successor to afKing.autoBuy): warp +1 day,
    ///      settle so mineFlip's PrepareSubscriptions stage stamps the funded set + the day word lands.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D); // settle any in-flight day first
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Grant `who` the permanent deity bit (mintPacked_ is slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding replaces
    ///      AfKing.depositFor). The deposit credits both the player bucket AND claimablePool in-contract,
    ///      so SOLVENCY-01 stays balanced.
    function _fundAfking(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Read `who`'s lastAutoBoughtDay (_subOf slot 52, uint24 bytes 11..13 of the packed Sub slot).
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        return uint32(uint24(packed >> (OFF_LASTBOUGHT * 8)));
    }

    // ---- claimable seeding (with the tandem claimablePool credit so SOLVENCY-01 stays balanced) ----

    function _claimableSlot(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(who)), BALANCES_PACKED_SLOT));
    }

    /// @dev Seed claimableWinnings[who] = amt and bump claimablePool by the delta so the invariant
    ///      claimablePool >= sum(claimableWinnings[*]) is preserved. balancesPacked packs claimable in
    ///      the low 128 bits and afking in the high 128 — write only the low half so a claimable seed
    ///      never corrupts the afking funding half.
    function _seedClaimable(address who, uint256 amt) internal {
        require(amt <= type(uint128).max, "claimable seed exceeds uint128");
        uint256 prev = game.claimableWinningsOf(who);
        bytes32 bSlot = _claimableSlot(who);
        uint256 packedBal = uint256(vm.load(address(game), bSlot));
        uint256 afkingHalf = packedBal & ~((uint256(1) << 128) - 1);
        vm.store(address(game), bSlot, bytes32(afkingHalf | amt));
        uint256 packedSlot1 = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = packedSlot1 & ((uint256(1) << 128) - 1);
        uint256 pool = packedSlot1 >> 128;
        if (amt >= prev) {
            pool += (amt - prev);
        } else {
            uint256 dec = prev - amt;
            pool = pool >= dec ? pool - dec : 0;
        }
        uint256 newPacked = (pool << 128) | lower;
        vm.store(address(game), bytes32(CLAIMABLE_POOL_SLOT), bytes32(newPacked));
    }

    // ---- far-future ticket seeding (ticketQueue slot 12 / entriesOwedPacked slot 13) ----

    function _queueBaseSlot(uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT));
    }

    /// @dev Register `who` in ticketOwners (slot 67, permanent) the way every sink does at
    ///      queue time, returning the owner bits the owed word must carry (position + 1 << 48).
    /// @dev Seed `whole` far-future tickets for `who` at level L (packed: owed=whole*4 entries << 8 | rem).
    ///      Appends `who` to ticketQueue[_ticketQueueStorageKey(ffk(L))].
    function _seedFarTickets(address who, uint24 L, uint32 whole) internal {
        TicketQueueStorage.seed(address(game), ffk.ffKey(L), L, who, uint80(whole) * 4 << 8);
    }

    function _owedPackedOf(uint24 L, address who) internal view returns (uint40) {
        return uint40(uint256(TicketQueueStorage.owed(address(game), ffk.ffKey(L), who)));
    }

    function _ffQueueLen(uint24 L) internal view returns (uint256) {
        return TicketQueueStorage.length(address(game), ffk.ffKey(L));
    }

    // ---- mid-day read-slot seeding (current-level queue, the contract's own read key) ----

    uint24 private constant TICKET_SLOT_BIT = 1 << 23; // mirrors DegenerusGameStorage.TICKET_SLOT_BIT

    /// @dev Read the GAME's live ticketWriteSlot bool (SLOT 0 byte 25) so the read key matches what the
    ///      contract computes (`_tqReadKey`: !writeSlot ? lvl|BIT : lvl).
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((slot0 >> (25 * 8)) & 0x1) != 0;
    }

    /// @dev The current read key for a level — byte-faithful to DegenerusGameStorage._tqReadKey.
    function _readKey(uint24 lvl) internal view returns (uint24) {
        return !_ticketWriteSlot() ? (lvl | TICKET_SLOT_BIT) : lvl;
    }

    /// @dev Seed `whole` current-level tickets for `who` at the read key (packed: owed=whole*4 entries
    ///      << 8 | rem) and append `who` to ticketQueue[_ticketQueueStorageKey(readKey)]. Mirrors the far-future seed shape.
    function _seedReadSlotTickets(uint24 readKey, address who, uint32 whole) internal {
        TicketQueueStorage.seed(address(game), readKey, readKey & ~TICKET_SLOT_BIT, who, uint80(whole) * 4 << 8);
    }

    /// @dev Set the ticketsFullyProcessed bool (SLOT 0 byte 24 at c4d48008), preserving every other
    ///      field in slot 0. The pre-PACK byte 26 is now ticketWriteSlot — poking it left
    ///      ticketsFullyProcessed unchanged (advanceDue stayed false) AND flipped the read-slot.
    function _setTicketsFullyProcessed(bool v) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFF) << (24 * 8);
        slot0 &= ~mask;
        if (v) slot0 |= (uint256(1) << (24 * 8));
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // ---- gameover latch ----

    /// @dev Latch the terminal gameOver public bool WITHOUT setting the gameover-time slot, so the
    ///      final sweep is never due (GO_TIME==0) and mineFlip sees no remaining terminal work. `gameOver` is the bool at byte 21 of EVM SLOT 0 (the
    ///      timing/FSM/flags pack). Set only that byte, preserving every other field, and confirm the
    ///      public getter flips.
    function _latchGameOver() internal {
        bytes32 slot = bytes32(uint256(0)); // SLOT 0 — the timing/FSM/flag pack holding gameOver at byte 21
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << (21 * 8));
        vm.store(address(game), slot, bytes32(packed));
        // This is an already-paid terminal state, not a freshly latched ending
        // whose remaining final jackpot the engine must still process.
        bytes32 ending = bytes32(GameSlots.GAME_OVER_STATE_PACKED);
        vm.store(address(game), ending, bytes32(uint256(vm.load(address(game), ending)) | (uint256(1) << 48)));
        require(game.gameOver(), "_latchGameOver: gameOver did not flip (slot 0 byte 21)");
    }

    // ---- real ticket-backlog driving ----

    /// @dev Buy a large current-level ticket backlog via the public mint API (enqueues at the write slot).
    function _buyManyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost + 1 ether) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _fulfillVrfIfPending(uint256 word) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    /// @dev Drive the protocol through enough advance cycles that the far-future queue for level L is
    ///      processed (the constructor + seeded multi-player FF entries drain through the engine's
    ///      ticket worker, runTicketWork).
    function _driveAdvanceThroughFarFutureProcessing(uint24 L) internal {
        uint256 simTime = block.timestamp;
        address poolFiller = makeAddr("ff_pool_filler");
        vm.deal(poolFiller, 1_000_000 ether);
        for (uint256 d; d < 300; d++) {
            if (game.level() >= L) break;
            if (game.gameOver()) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _buyManyTickets(poolFiller, 4000);
            // Drive until the protocol stops accepting work (NotTimeYet), not a fixed
            // ration: mainnet keepers are unbounded, and the sDGNRS level-bonus box can
            // legitimately queue multi-batch ticket drains (its size scales with the
            // claimable a played-out game accumulates). A fixed per-day call budget
            // starves the drain and manufactures a fake liveness trip.
            for (uint256 j; j < 4000; j++) {
                _fulfillVrfIfPending(uint256(keccak256(abi.encode(simTime, j, "ffdrain"))));
                (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (!ok) break;
            }
        }
    }

    /// @dev Seed nextPrizePool to accelerate level transitions.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 PRIZE_POOLS_PACKED_SLOT = 2;
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT)));
        uint256 currentNext = currentPacked & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        uint256 newPacked = (currentPacked & ~((uint256(1) << 128) - 1)) | targetNext;
        vm.store(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT), bytes32(newPacked));
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
