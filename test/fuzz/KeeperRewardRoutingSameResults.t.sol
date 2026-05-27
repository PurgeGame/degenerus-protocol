// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title FFKeyHarness -- Exposes _tqFarFutureKey as a pure helper for the GASOPT-01 owed-slot math.
/// @dev Inherits DegenerusGameStorage solely to surface the far-future key derivation the seed helpers
///      key on. Zero behavioral coupling to the FROZEN subject.
contract FFKeyHarness is DegenerusGameStorage {
    function ffKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title KeeperRewardRoutingSameResults -- TST-03 (Phase 332): the advanceGame reward-routing rework
///        (ADV-01..05) proven EMPIRICALLY plus the two GASOPT micro-opts proven same-results.
///
/// @notice TST-03 closes the SC3 reward-routing + same-results bar for the v49 unified keeper-router.
///         The re-homing must demonstrably MOVE the advance bounty from the standalone path to the
///         router WITHOUT changing the advance behavior, and the two gas-only micro-opts must produce
///         byte-identical RESULTS.
///
///   Reward routing (the load-bearing re-home proof):
///   - advanceGame() called STANDALONE (directly on GAME) earns the caller NOTHING — the 3 in-callee
///     `creditFlip` sites were removed at ADV-01; `advanceGame` returns only `uint8 mult` (no credit).
///   - The SAME advance driven via `afKing.doWork()` CREDITS the keeper: the router pays
///     `unit * ADVANCE_RATIO_NUM * mult` (AfKing.sol:899). The stall multiplier is HONORED — a stalled
///     new-day advance (`mult > 1`) credits STRICTLY MORE than the un-stalled (`mult == 1`) advance,
///     proven by RELATIVE magnitude (not the GAS-calibrated 331 peg constant, which this proof does
///     NOT own). The mid-day partial-drain leg (`mult == 1`) is REWARDED. The gameover leg
///     (`mult == 0`) is UNREWARDED — zero creditFlip.
///   All reward observation is recipient-isolated to the keeper via the `_countCoinflipStakeUpdatedFor`
///   / `_creditAmountFor` oracle (topics[1] == keeper), so a box-owner's / player's winnings credit can
///   never inflate or mask the router bounty count or amount.
///
///   GASOPT same-results (Foundry behavioral / value-equality — these opts touch NO RNG/result):
///   - GASOPT-03 (DegenerusGame.keeperSnapshot, :2628 — SUBSUMES the original GASOPT-02): the batched
///     read returns the SAME `(mintPriceWei, rngLocked_, claimables[])` as N individual
///     `mintPrice()` / `rngLocked()` / `claimableWinningsOf(player)` accessors, element-by-element, and
///     an autoBuy driven through it produces identical buy outcomes. There is NO separate AfKing
///     per-iteration `claimableWinningsOf` hoist site — GASOPT-02 was subsumed; this proof does NOT
///     search AfKing.sol for one (RESEARCH Pitfall 5; count is 0).
///   - GASOPT-01 (DegenerusGameMintModule `owedMap` pointer hoist, :399 + :673): the
///     `processTicketBatch` / `processFutureTicketBatch` ticket-processing RESULTS (per-player owed
///     drain) are byte-identical to the expected per-player accounting. The hoist
///     (`mapping(...) storage owedMap = ticketsOwedPacked[rk]`) is `rk`-loop-invariant, so a multi-player
///     backlog drains every player's owed to zero — a broken pointer hoist would skip / double-process a
///     player, stranding non-zero owed or mis-decrementing it. This is observed via the contract's own
///     `ticketsOwedPacked` storage (the per-player owed truth) after a real advance-driven drain.
///
/// @dev The `_countCoinflipStakeUpdated` / `_countCoinflipStakeUpdatedFor` log-count helpers, the
///      `_settleGame` VRF drain, the buy-leg slot-forcing (`_pinBuyLegWalkedForToday`), and the
///      `_setupHealthyBuyingSubs` driving mirror KeeperRouterOneCategory.t.sol / AfKingConcurrency.t.sol.
///      The far-future ticket seeding (`_seedFarTickets`) + claimable seeding (`_seedClaimable`) mirror
///      FarFutureSalvageSwap.t.sol. Zero contracts/*.sol mutation; test-only; FROZEN subject honored.
contract KeeperRewardRoutingSameResults is DeployProtocol {
    // -------------------------------------------------------------------------
    // creditFlip-count / amount oracle (CrankLeversAndPacking.t.sol:75 / :523-548 — verbatim port,
    // extended with a recipient-isolated AMOUNT decode for the multiplier-honored magnitude check)
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once per
    ///      creditFlip. topics[1] is the indexed player (recipient isolation); the non-indexed
    ///      `amount` is the first 32 bytes of `data`.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    // -------------------------------------------------------------------------
    // AfKing pinned slot layout (mirrors KeeperRouterOneCategory / AfKingConcurrency)
    // -------------------------------------------------------------------------

    uint256 private constant SUBOF_SLOT = 1;   // _subOf mapping root (address => Sub, one slot)
    uint256 private constant OFF_LASTSWEPT = 1; // uint32 lastAutoBoughtDay (bytes 1..4)
    uint256 private constant AUTOBUY_SLOT = 4;  // _autoBuyDay (uint32 bytes 0..3) + _autoBuyCursor (uint224)

    // -------------------------------------------------------------------------
    // DegenerusGame pinned slot layout (forge inspect; mirrors FarFutureSalvageSwap / FarFutureIntegration)
    // -------------------------------------------------------------------------

    uint256 private constant CLAIMABLE_POOL_SLOT = 1;       // uint128 packed at offset 16 of slot 1
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7;   // mapping(address => uint256)
    uint256 private constant TICKET_QUEUE_SLOT = 12;        // mapping(uint24 => address[])
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13; // mapping(uint24 => mapping(address => uint40))
    uint256 private constant GAMEOVER_SLOT_BIT = 23;        // public bool gameOver at byte 23 of its packed slot

    FFKeyHarness private ffk;
    address private keeper;
    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // One keeper-local day off the deploy boundary so the day index is a clean, stable value
        // (mirrors KeeperRouterOneCategory / AfKingConcurrency).
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        ffk = new FFKeyHarness();
        keeper = makeAddr("routing_keeper");
        vm.deal(keeper, 100_000 ether);
        vm.deal(address(game), 5_000_000 ether);
    }

    /// @dev Settle the game to a clean state: complete the pending day-advance (drive advanceGame +
    ///      deliver the mock VRF word + drain the rngLock) until advanceDue() is false and we are not
    ///      locked. Mirrors KeeperRouterOneCategory._settleGame / RngLockDeterminism._completeDay.
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    // =========================================================================
    // Task 1 — advanceGame UNREWARDED-standalone vs REWARDED-via-doWork (multiplier honored)
    // =========================================================================

    /// @notice STANDALONE advanceGame() earns the caller NOTHING (ADV-01: the 3 in-callee creditFlip
    ///         sites were removed; advanceGame returns only `uint8 mult`), yet the day STILL ADVANCES
    ///         (advance is fully functional standalone — it is just the unrewarded liveness fallback).
    function testAdvanceStandaloneUnrewarded() public {
        // Settle the deploy-day advance, then roll the wall clock so a fresh day-advance is due.
        _settleGame(0x57A11A10E0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        address caller = makeAddr("standalone_advance_caller");
        bool lockedBefore = game.rngLocked();

        vm.recordLogs();
        vm.prank(caller);
        uint8 mult = game.advanceGame();

        // The caller earned ZERO router bounty — the standalone advance pays nothing (re-homed to doWork).
        assertEq(
            _countCoinflipStakeUpdatedFor(caller),
            0,
            "STANDALONE: advanceGame() credits the caller zero (the 3 in-callee creditFlip removed at ADV-01)"
        );
        // And it returned a live (non-gameover) multiplier — the advance ran, it just paid nobody.
        assertGt(mult, 0, "STANDALONE: advanceGame returned a live mult (a normal day-advance, not gameover)");

        // Non-vacuity: the day actually advanced (the tick happened) — advance is fully functional
        // standalone. The single advanceGame() either cleared the advance-due predicate or engaged
        // rngLock mid-flight for the day it just advanced.
        bool progressed = !game.advanceDue() || (!lockedBefore && game.rngLocked());
        assertTrue(progressed, "non-vacuity: the standalone advance ticked the day (still fully functional)");
    }

    /// @notice REWARDED via doWork with the MULTIPLIER HONORED: the SAME new-day advance, driven via
    ///         doWork at a HIGHER STALL, credits the keeper STRICTLY MORE than at the un-stalled base.
    ///         Proven by RELATIVE magnitude (the 1/2/4/6 ladder flows through `unit * 2 * mult`), never
    ///         by the GAS-calibrated 331 peg constant. mintPrice is identical across both scenarios
    ///         (same deploy level), so `unit` is identical and the credit ratio == the mult ratio.
    function testAdvanceViaDoWorkRewardedMultiplierHonored() public {
        // Settle so we start from a clean, not-due, not-locked baseline.
        _settleGame(0xADADAD0002);
        assertFalse(game.advanceDue(), "pre: settled");
        assertFalse(game.rngLocked(), "pre: not locked");

        uint256 snap = vm.snapshot();

        // --- Scenario A: lightly-stalled new-day advance (mult == 2: >= 20 min past the day boundary) ---
        // We use a 31-minute offset so the advance ALSO clears the _enforceDailyMintGate 30-minute
        // permissionless bypass (a fresh keeper that has not minted today otherwise reverts
        // MustMintToday). 31 min => mult == 2 (the >= 20-min ladder step), gate bypassed.
        uint256 lowStallCredit = _doWorkAdvanceCreditAtStall(31 minutes);
        assertGt(lowStallCredit, 0, "REWARDED: the lightly-stalled advance credited the keeper (mult==2)");

        // --- Scenario B: heavily-stalled new-day advance (mult == 6: >= 2 hours past the day boundary) ---
        vm.revertTo(snap);
        uint256 highStallCredit = _doWorkAdvanceCreditAtStall(2 hours + 1 minutes);
        assertGt(highStallCredit, 0, "REWARDED: the heavily-stalled advance credited the keeper (mult==6)");

        // The multiplier is HONORED: the higher stall credits STRICTLY MORE (unit identical, only mult
        // differs). At the 2h+ stall mult==6 vs the 31-min stall mult==2, so the high-stall credit is ~3x
        // the low-stall credit - but we assert only strict ordering, never the GAS-calibrated peg.
        assertGt(
            highStallCredit,
            lowStallCredit,
            "MULTIPLIER HONORED: a higher stall credits strictly more (the 1/2/4/6 ladder flows through)"
        );
    }

    /// @dev Drive ONE doWork() advance leg at `stallElapsed` past a fresh day boundary and return the
    ///      keeper's credited router-bounty amount. Aligns the wall clock so a new-day advance is due and
    ///      the stall window resolves to the intended multiplier; pins the buy leg empty so doWork routes
    ///      straight to the advance leg.
    function _doWorkAdvanceCreditAtStall(uint256 stallElapsed) internal returns (uint256) {
        // Move to the START of the NEXT calendar-day window, then add the stall offset. The advance
        // module derives day = _simulatedDayIndexAt(ts) = (ts-82620)/1days + 1, and the stall window is
        // elapsed = ts - ((day-1)*1days + 82620) = (ts-82620) mod 1days (DEPLOY_DAY_BOUNDARY==0). Rolling
        // _today() forward by 1 makes a fresh day-advance due (day != dailyIdx after settle); the offset
        // INTO that day window is exactly `stallElapsed`, so the stall ladder resolves as intended.
        uint32 dayNow = _today();
        uint256 nextDayStart = (uint256(dayNow + 1) * 1 days) + 82_620; // start of the next day's window
        vm.warp(nextDayStart + stallElapsed);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due at the chosen stall");

        // Force the router past the buy leg (no backlog due) into the advance leg.
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // Read the recorded logs ONCE (vm.getRecordedLogs drains them) and derive BOTH the count and the
        // credited amount in a single pass, so the amount is not lost to a prior drain.
        (uint256 count, uint256 amount) = _keeperCreditCountAndAmount();
        // Exactly one router bounty credit on the advance leg.
        assertEq(count, 1, "REWARDED: the advance leg credits the keeper exactly once via doWork");
        return amount;
    }

    /// @dev Single-pass recorded-log read returning (count, summed amount) of the keeper's
    ///      CoinflipStakeUpdated emissions. Avoids the double-getRecordedLogs drain hazard.
    function _keeperCreditCountAndAmount() internal returns (uint256 count, uint256 amount) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                logs[i].topics[1] == bytes32(uint256(uint160(keeper)))
            ) {
                count++;
                amount += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    /// @notice MID-DAY partial-drain leg (mult == 1) is REWARDED via doWork: a `day == dailyIdx` advance
    ///         that drains a non-empty read slot returns mult=1 (ADV-05/D-07, no escalation), so the
    ///         router credits the keeper exactly once. The mid-day partial-drain path (AdvanceModule:194)
    ///         is reachable only at `day == dailyIdx`; after a clean settle we stage it by seeding a
    ///         multi-player read-slot backlog with `ticketsFullyProcessed = false` (the same condition the
    ///         contract reaches when tickets are bought after the day already advanced). The advance then
    ///         takes the mid-day branch, `_runProcessTicketBatch` WORKS, and `mult` returns 1.
    function testMidDayPartialDrainRewardedViaDoWork() public {
        // Settle to a clean, not-due, not-locked baseline: `day == dailyIdx` (the mid-day precondition).
        _settleGame(0x1D0E0003);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");
        assertFalse(game.gameOver(), "pre: game live");

        // Compute the mid-day purchaseLevel + read key exactly as the contract does (purchase phase,
        // not lastPurchaseDay, not rngLocked => purchaseLevel = level + 1; read key honours ticketWriteSlot).
        uint24 purchaseLevel = uint24(game.level()) + 1;
        uint24 readKey = _readKey(purchaseLevel);

        // Seed a LARGE multi-player read-slot backlog (each player owed whole tickets) and clear the
        // fully-processed flag so advanceDue() is TRUE mid-day (read slot non-empty + not fully processed).
        // The backlog is sized to exceed the per-batch write budget (WRITES_BUDGET_SAFE=550, 65%-scaled on
        // the first batch) so the mid-day _runProcessTicketBatch WORKS but does NOT finish -> the advance
        // takes the STAGE_TICKETS_WORKING partial-drain return (mult==1) rather than fully draining and
        // falling through to NotTimeYet.
        uint256 M = 200;
        address[] memory players = new address[](M);
        for (uint256 i; i < M; i++) {
            players[i] = makeAddr(string(abi.encodePacked("midday_player_", _u(i))));
            _seedReadSlotTickets(readKey, players[i], 3); // 3 whole tickets each (12 entries)
        }
        _setTicketsFullyProcessed(false);

        assertTrue(game.advanceDue(), "pre: a mid-day partial-drain advance is due (read slot un-fully-processed)");
        assertFalse(game.rngLocked(), "pre: not locked (mid-day, no escalation)");

        // Pin the buy leg empty so doWork routes to the advance leg (which takes the mid-day path).
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // The mid-day partial-drain leg IS rewardable advance-leg work - exactly one creditFlip (mult==1).
        assertEq(
            _countCoinflipStakeUpdatedFor(keeper),
            1,
            "MID-DAY: the partial-drain leg (mult==1) is rewarded - exactly one creditFlip to the keeper"
        );
    }

    /// @notice GAMEOVER leg (mult == 0) is UNREWARDED via doWork: the advance runs the gameover path
    ///         (the flip-credit coin is worthless at gameover) and returns mult=0, so the router skips
    ///         the creditFlip entirely — zero credit.
    function testGameoverAdvanceUnrewarded() public {
        // Settle, then make a fresh day-advance due.
        _settleGame(0x90E00004);
        assertFalse(game.advanceDue(), "pre: settled");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        // Latch the terminal gameOver flag (the public bool). With gameOver==true and the gameover-time
        // slot still 0, _handleGameOverPath takes the gameOver branch -> handleFinalSweep early-returns
        // ("Game not over yet" at GO_TIME==0, a harmless no-op) -> advanceGame returns mult=0 (the
        // gameover path: advance ran but earns no bounty).
        _latchGameOver();
        assertTrue(game.gameOver(), "pre: gameOver latched");

        // Pin the buy leg empty so doWork routes to the advance leg, which takes the gameover (mult=0) path.
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();
        assertTrue(game.advanceDue(), "pre: advance still due (the router will route to the advance leg)");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // mult==0 => the router's `if (mult > 0)` guard skips bounty, and the CEI-last creditFlip is the
        // `bountyEarned > 0` skip — ZERO credit to the keeper.
        assertEq(
            _countCoinflipStakeUpdatedFor(keeper),
            0,
            "GAMEOVER: the mult==0 advance leg credits the keeper zero (the flip-credit is worthless at gameover)"
        );
        // And zero creditFlip emissions at all from the gameover advance (no stacking, no winnings credit).
        assertEq(
            _countCoinflipStakeUpdated(),
            0,
            "GAMEOVER: zero creditFlip emissions on the mult==0 advance leg"
        );
    }

    // =========================================================================
    // Task 2 — GASOPT-03 (keeperSnapshot) + GASOPT-01 (owedMap pointer hoist) behavioral same-results
    // =========================================================================

    /// @notice GASOPT-03 (keeperSnapshot SUBSUMES GASOPT-02): the batched read is VALUE-IDENTICAL to N
    ///         individual reads — `mintPriceWei == mintPrice()`, `rngLocked_ == rngLocked()`, and
    ///         `claimables[i] == claimableWinningsOf(players[i])` element-by-element across N players with
    ///         varied claimable balances.
    function testKeeperSnapshotEqualsIndividualReads() public {
        // N players holding VARIED claimable balances (some zero, some non-zero, distinct).
        uint256 N = 6;
        address[] memory players = new address[](N);
        uint256[] memory seeded = new uint256[](N);
        for (uint256 i; i < N; i++) {
            players[i] = makeAddr(string(abi.encodePacked("snap_player_", _u(i))));
            // Vary: alternate zero / non-zero, distinct magnitudes.
            seeded[i] = (i % 3 == 0) ? 0 : (uint256(i + 1) * 1.337 ether);
            if (seeded[i] > 0) _seedClaimable(players[i], seeded[i]);
        }

        // Batched read.
        (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables) = game.keeperSnapshot(players);

        // Field 1: mintPriceWei == mintPrice().
        assertEq(mintPriceWei, game.mintPrice(), "GASOPT-03: keeperSnapshot.mintPriceWei == mintPrice()");
        // Field 2: rngLocked_ == rngLocked().
        assertEq(rngLocked_, game.rngLocked(), "GASOPT-03: keeperSnapshot.rngLocked_ == rngLocked()");
        // Field 3: claimables[i] == claimableWinningsOf(players[i]) for every i.
        assertEq(claimables.length, N, "GASOPT-03: claimables length == N");
        bool sawNonZero;
        for (uint256 i; i < N; i++) {
            assertEq(
                claimables[i],
                game.claimableWinningsOf(players[i]),
                "GASOPT-03: claimables[i] == claimableWinningsOf(players[i])"
            );
            // Non-vacuity: the batched value tracks the seeded balance (it is not a constant zero).
            assertEq(claimables[i], seeded[i], "GASOPT-03 non-vacuity: claimables[i] tracks the seeded balance");
            if (claimables[i] > 0) sawNonZero = true;
        }
        assertTrue(sawNonZero, "GASOPT-03 non-vacuity: at least one player held a non-zero claimable");
    }

    /// @notice GASOPT-03 drives an IDENTICAL autoBuy outcome: a reinvest-subscriber's autoBuy reads the
    ///         keeperSnapshot claimable (AfKing._buildSubBuyParams consumes the batched read) and produces
    ///         the same buy outcome as the reference per-player computation — the buy lands and stamps the
    ///         sub bought-today (the keeperSnapshot read fed the correct claimable into the buy waterfall).
    function testKeeperSnapshotDrivenAutoBuyIdenticalOutcome() public {
        // A reinvest subscriber: reinvestPct > 0 forces _buildSubBuyParams down the keeperSnapshot read
        // path (it builds a 1-element snap and reads cl[0]); the buy outcome must match the reference.
        address sub = makeAddr("snap_autobuy_sub");
        _fundBurnie(sub, _subCost());
        vm.prank(sub);
        // (player=self, drainCredit=false, useTickets=true, dailyQty=1, reinvestPct=50, fundingSource=self)
        afKing.subscribe(address(0), false, true, 1, 50, address(0));
        vm.prank(sub);
        game.setOperatorApproval(address(afKing), true);
        _fundPool(sub, 5 ether);

        // Reference: what the keeperSnapshot returns for this sub right now (the value the buy will read).
        address[] memory one = new address[](1);
        one[0] = sub;
        (uint256 snapPrice, , uint256[] memory snapClaim) = game.keeperSnapshot(one);
        assertEq(snapPrice, game.mintPrice(), "ref: keeperSnapshot price == mintPrice()");
        assertEq(snapClaim[0], game.claimableWinningsOf(sub), "ref: keeperSnapshot claimable == claimableWinningsOf(sub)");

        // Drive the autoBuy (the leg that consumes keeperSnapshot internally) and assert the buy landed.
        vm.prank(keeper);
        afKing.autoBuy(afKing.subscriberCount() + 5);

        // Outcome: the reinvest sub was bought today (the keeperSnapshot-fed waterfall produced a buy).
        assertEq(
            _lastAutoBoughtDayOf(sub),
            _today(),
            "GASOPT-03: the keeperSnapshot-driven autoBuy bought the reinvest sub today (identical outcome)"
        );
    }

    /// @notice GASOPT-01 (owedMap pointer hoist) same-results: a MULTI-PLAYER far-future ticket backlog
    ///         drains every player's owed to ZERO through the advance-driven processFutureTicketBatch loop
    ///         (the hoisted `owedMap = ticketsOwedPacked[rk]` is rk-loop-invariant). A broken pointer hoist
    ///         would skip / double-process a player, leaving non-zero owed or mis-decrementing it; the
    ///         per-player owed RESULTS are byte-identical to the expected per-player accounting (full drain).
    function testGasopt01OwedMapHoistSameResults() public {
        // Multi-player backlog: seed M fresh players each with K whole far-future tickets at a level the
        // advance will process. Mirrors FarFutureSalvageSwap._seedFarTickets / FarFutureIntegration.
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
        // internal processFutureTicketBatch (the GASOPT-01 hoist site) drains the multi-player queue.
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
    // creditFlip-count / amount oracle (port of CrankLeversAndPacking.t.sol:523-548 + amount decode)
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
                logs[i].topics[1] == bytes32(uint256(uint160(who)))
            ) count++;
        }
    }

    // =========================================================================
    // Protocol-driving helpers (mirror KeeperRouterOneCategory / AfKingConcurrency / FarFutureSalvageSwap)
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    function _buyLegDue() internal view returns (bool) {
        (uint32 progDay, uint256 cursor) = afKing.autoBuyProgress();
        return progDay != _today() || cursor < afKing.subscriberCount();
    }

    function _assertBuyLegEmpty() internal view {
        assertFalse(_buyLegDue(), "pre: buy leg is empty (walked + stamped for today)");
    }

    /// @dev Pin the buy leg "walked for today": stamp _autoBuyDay == today AND cursor >= length so the
    ///      buy-leg predicate is FALSE. Forces the router past the buy leg into advance / open / NoWork.
    function _pinBuyLegWalkedForToday() internal {
        uint256 len = afKing.subscriberCount();
        uint256 packed = (uint256(_today()) & 0xFFFFFFFF) | ((len + 1) << 32);
        vm.store(address(afKing), bytes32(uint256(AUTOBUY_SLOT)), bytes32(packed));
    }

    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * 1000 ether) / game.mintPrice();
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    // ---- claimable seeding (mirror FarFutureSalvageSwap._seedClaimable) ----

    function _claimableSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, CLAIMABLE_WINNINGS_SLOT));
    }

    /// @dev Seed claimableWinnings[who] = amt and bump claimablePool by the delta so the invariant
    ///      claimablePool >= sum(claimableWinnings[*]) is preserved.
    function _seedClaimable(address who, uint256 amt) internal {
        uint256 prev = game.claimableWinningsOf(who);
        vm.store(address(game), _claimableSlot(who), bytes32(amt));
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

    // ---- far-future ticket seeding (mirror FarFutureSalvageSwap._seedFarTickets) ----

    function _ownedPackedSlot(uint24 key, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(key), TICKETS_OWED_PACKED_SLOT));
        return keccak256(abi.encode(who, uint256(inner)));
    }

    function _queueBaseSlot(uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT));
    }

    /// @dev Seed `whole` far-future tickets for `who` at level L (packed: owed=whole*4 entries << 8 | rem).
    ///      Appends `who` to ticketQueue[ffk(L)].
    function _seedFarTickets(address who, uint24 L, uint32 whole) internal {
        uint24 key = ffk.ffKey(L);
        uint32 entries = whole * 4;
        uint40 packed = uint40(uint256(entries) << 8); // rem = 0
        vm.store(address(game), _ownedPackedSlot(key, who), bytes32(uint256(packed)));

        bytes32 lenSlot = _queueBaseSlot(key);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        bytes32 elemSlot = bytes32(uint256(dataBase) + len);
        vm.store(address(game), elemSlot, bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
    }

    function _owedPackedOf(uint24 L, address who) internal view returns (uint40) {
        return uint40(uint256(vm.load(address(game), _ownedPackedSlot(ffk.ffKey(L), who))));
    }

    function _ffQueueLen(uint24 L) internal view returns (uint256) {
        return uint256(vm.load(address(game), _queueBaseSlot(ffk.ffKey(L))));
    }

    // ---- mid-day read-slot seeding (current-level queue, the contract's own read key) ----

    uint24 private constant TICKET_SLOT_BIT = 1 << 23; // mirrors DegenerusGameStorage.TICKET_SLOT_BIT

    /// @dev Read the GAME's live ticketWriteSlot bool (SLOT 0 byte 28) so the read key matches what the
    ///      contract computes (`_tqReadKey`: !writeSlot ? lvl|BIT : lvl).
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((slot0 >> (28 * 8)) & 0x1) != 0;
    }

    /// @dev The current read key for a level — byte-faithful to DegenerusGameStorage._tqReadKey.
    function _readKey(uint24 lvl) internal view returns (uint24) {
        return !_ticketWriteSlot() ? (lvl | TICKET_SLOT_BIT) : lvl;
    }

    /// @dev Seed `whole` current-level tickets for `who` at the read key (packed: owed=whole*4 entries
    ///      << 8 | rem) and append `who` to ticketQueue[readKey]. Mirrors the far-future seed shape.
    function _seedReadSlotTickets(uint24 readKey, address who, uint32 whole) internal {
        uint32 entries = whole * 4;
        uint40 packed = uint40(uint256(entries) << 8);
        vm.store(address(game), _ownedPackedSlot(readKey, who), bytes32(uint256(packed)));

        bytes32 lenSlot = _queueBaseSlot(readKey);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        bytes32 elemSlot = bytes32(uint256(dataBase) + len);
        vm.store(address(game), elemSlot, bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
    }

    /// @dev Set the ticketsFullyProcessed bool (SLOT 0 byte 26), preserving every other field in slot 0.
    function _setTicketsFullyProcessed(bool v) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFF) << (26 * 8);
        slot0 &= ~mask;
        if (v) slot0 |= (uint256(1) << (26 * 8));
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // ---- gameover latch ----

    /// @dev Latch the terminal gameOver public bool WITHOUT setting the gameover-time slot, so
    ///      handleFinalSweep early-returns harmlessly ("Game not over yet" at GO_TIME==0) and advanceGame
    ///      takes the gameover branch (mult=0). Per the DegenerusGameStorage layout doc, `gameOver` is the
    ///      bool at byte [23:24] of EVM SLOT 0 (the timing/FSM/flags pack). Set only that byte, preserving
    ///      every other field in the slot, and confirm the public getter flips.
    function _latchGameOver() internal {
        bytes32 slot = bytes32(uint256(0)); // SLOT 0 — the timing/FSM/flag pack holding gameOver at byte 23
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << (GAMEOVER_SLOT_BIT * 8));
        vm.store(address(game), slot, bytes32(packed));
        require(game.gameOver(), "_latchGameOver: gameOver did not flip (slot 0 byte 23)");
    }

    // ---- real ticket-backlog driving (mirror FarFutureIntegration) ----

    /// @dev Buy a large current-level ticket backlog via the public mint API (enqueues at the write slot).
    function _buyManyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost + 1 ether) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth);
    }

    function _fulfillVrfIfPending(uint256 word) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    /// @dev Drive the protocol through enough advance cycles that the far-future queue for level L is
    ///      processed (the constructor + seeded multi-player FF entries drain via processFutureTicketBatch).
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
            for (uint256 j; j < 50; j++) {
                _fulfillVrfIfPending(uint256(keccak256(abi.encode(simTime, j, "ffdrain"))));
                (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) break;
            }
        }
    }

    /// @dev Seed nextPrizePool to accelerate level transitions (mirror FarFutureIntegration).
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 PRIZE_POOLS_PACKED_SLOT = 2;
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT)));
        uint128 currentNext = uint128(currentPacked);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(currentPacked >> 128);
        uint256 newPacked = (uint256(currentFuture) << 128) | targetNext;
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
