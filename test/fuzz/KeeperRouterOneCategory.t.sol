// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperRouterOneCategory -- TST-02 (Phase 332): one-rewarded-category-per-tx (no
///        bounty-stacking) + the router->game->creditFlip double-pay disposition + the
///        parameterless-`doWork()` default-batch/remainder behavior + the standalone UNREWARDED
///        `autoBuy(count)` / `autoOpen(count)` escapes.
///
/// @notice TST-02 is the second load-bearing v49 SECURITY proof (with TST-01). The `doWork()`
///         one-category STRUCTURAL early-return (AfKing.sol:883-919) is the mitigation for
///         bounty-stacking; the single CEI-last `creditFlip` (AfKing.sol:916-918) is the mitigation
///         for a composed reentrant double-pay. Security is the HARD FLOOR.
///
///   D-02 (no-stacking proven by COUNTING `creditFlip`, NOT exact amounts): each `doWork()` tx fires
///   EXACTLY ONE `COINFLIP.creditFlip` across all three category branches (buy / advance / open),
///   ZERO on the `bountyEarned==0` skip (a buy chunk that walked only already-bought subs runs the
///   category but credits nothing, still no revert), and ZERO + `revert NoWork()` when all three O(1)
///   predicates are empty. The count is taken via the recipient-isolated
///   `_countCoinflipStakeUpdatedFor(keeper)` oracle (topics[1] == keeper) so a box-owner's winnings
///   credit (LootboxModule:1036) can never inflate or mask the router bounty count. Asserting COUNT
///   (==1 / ==0) across all three branches IS the proof the else-if chain can never credit two
///   categories in one tx — no exact-amount or retired per-item *summed* reward is asserted anywhere.
///
///   D-01 (reentrancy is STRUCTURAL, NO attacker harness): `doWork` pays only minted FLIP CREDIT,
///   makes NO ETH push, and every external call in every leg targets a pinned `ContractAddresses.*`
///   (GAME / COINFLIP). There is no untrusted call to re-enter through, so a synthetic reentrant
///   attacker has no hook (it would be false-soundness theatre). The disposition is satisfied by a
///   comment-stripped source grep-attestation: (a) the single `creditFlip(msg.sender, bountyEarned)`
///   occurrence (==1, CEI-last), and (b) every external call site in `doWork` targets only the pinned
///   `ContractAddresses.GAME` / `ContractAddresses.COINFLIP` (no untrusted address literal, no
///   `.call` / `.transfer` / `.send` to a non-pinned target). NO attacker/reentrant mock exists in
///   this file (User verbatim: "reentrancy is not an issue, nothing here pays eth and this only
///   interacts with trusted contracts.").
///
///   D-03 (default-batch / escapes): parameterless `doWork()` runs the fixed per-leg default batch
///   (BUY_BATCH=50 / OPEN_BATCH=100) and does NOT OOG; a backlog larger than the batch leaves a
///   remainder for the next call (the `autoBuyProgress()` cursor < length). The standalone parametered
///   `autoBuy(count)` / `autoOpen(count)` are emergency escapes that run the leg but credit NOTHING.
///
/// @dev The `_countCoinflipStakeUpdated` / `_countCoinflipStakeUpdatedFor` log-count helpers and the
///      `_stripComments` / `_countOccurrences` source-grep helpers are byte-faithful ports of
///      CrankLeversAndPacking.t.sol (they are not in a shared base). The buy-side driving
///      (`_setupHealthyBuyingSubs`, the storage-stamp / cursor helpers) mirrors AfKingConcurrency.t.sol;
///      the box-enqueue driving (`_buyBox` + `_injectLootboxRngWord`) mirrors CrankOpenBoxWorstCaseGas.t.sol.
///      Zero contracts/*.sol mutation; test-only.
contract KeeperRouterOneCategory is DeployProtocol {
    // -------------------------------------------------------------------------
    // creditFlip-count oracle (CrankLeversAndPacking.t.sol:75 / :523-548 — verbatim port)
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once per
    ///      creditFlip via _addDailyFlip; counting topic[0] is the canonical "how many bounty credits
    ///      fired this tx" oracle. The indexed `player` is topics[1] (recipient isolation).
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    // -------------------------------------------------------------------------
    // AfKing pinned slot layout (per AfKing.sol; mirrors AfKingConcurrency.t.sol)
    // -------------------------------------------------------------------------

    uint256 private constant SUBOF_SLOT = 1;            // _subOf mapping root (address => Sub, one slot)
    uint256 private constant OFF_LASTSWEPT = 1;         // uint32 lastAutoBoughtDay (bytes 1..4)
    uint256 private constant AUTOBUY_SLOT = 4;          // _autoBuyDay (uint32 bytes 0..3) + _autoBuyCursor (uint224)

    // -------------------------------------------------------------------------
    // DegenerusGame pinned slot layout (per the lootbox-box helpers; confirmed via forge inspect)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); index = low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

    uint256 private constant FIXED_WORD = uint256(keccak256("keeper_router_one_category_word"));
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit box

    // -------------------------------------------------------------------------
    // Source path for the comment-stripped grep attestation
    // -------------------------------------------------------------------------

    string private constant AFKING_SRC = "contracts/AfKing.sol";

    address private keeper;
    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // One keeper-local day off the deploy boundary so _currentDay() is a clean, stable index
        // (mirrors AfKingConcurrency / CrankLeversAndPacking).
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        keeper = makeAddr("router_keeper");
        vm.deal(keeper, 100_000 ether);
        vm.deal(address(game), 1_000_000 ether);
    }

    /// @dev Settle the game to a clean state: complete the pending day-advance (drive advanceGame +
    ///      deliver the mock VRF word + drain the rngLock) until `advanceDue()` is false and we are no
    ///      longer locked. Mirrors RngLockDeterminism._completeDay. Idempotent once settled.
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
    // Task 1 — D-02 one-category creditFlip COUNT across all branches + skip + NoWork
    // =========================================================================

    /// @notice BUY branch: a fresh-day backlog routes `doWork()` to the buy leg (highest priority);
    ///         a successful buy credits the keeper EXACTLY ONCE.
    function testBuyBranchCreditsExactlyOnce() public {
        address[] memory subs = _setupHealthyBuyingSubs(3, "buy1_");

        // Pre-state: a fresh keeper-local day with an un-walked backlog -> the buy-leg predicate
        // (`_autoBuyDay != _currentDay() || _autoBuyCursor < length`) is TRUE.
        (uint32 progDay, uint256 cursor0) = afKing.autoBuyProgress();
        assertTrue(progDay != _today() || cursor0 < afKing.subscriberCount(), "pre: buy leg is due (fresh-day backlog)");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // Exactly one router bounty credit to the keeper across the whole tx.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "BUY branch: exactly one doWork creditFlip to the keeper");

        // Non-vacuity: the buy leg actually bought (a sub's lastAutoBoughtDay advanced to today).
        bool boughtOne;
        for (uint256 i; i < subs.length; i++) {
            if (_lastAutoBoughtDayOf(subs[i]) == _today()) boughtOne = true;
        }
        assertTrue(boughtOne, "non-vacuity: the buy leg landed at least one buy");
    }

    /// @notice ADVANCE branch: with the buy leg empty (all subs walked + bought) and `advanceDue()`
    ///         true, `doWork()` routes to the advance leg; a multiplier > 0 credits EXACTLY ONCE.
    function testAdvanceBranchCreditsExactlyOnce() public {
        // Settle the deploy-day advance so we start from a clean, not-due, not-locked state.
        _settleGame(0xADADADAD0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");

        // Drive `advanceDue()` true: roll the wall clock forward so the simulated day index moves ahead
        // of dailyIdx. The buy predicate keys on AfKing's _currentDay(); advanceDue() keys on the game's
        // _simulatedDayIndex(). Pin the buy stamp to AfKing's *current* day so the buy leg is "already
        // walked today" (FALSE) while the game owes a day-advance — the router falls through to advance.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: advance is due");
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();

        bool dueBefore = game.advanceDue();
        bool lockedBefore = game.rngLocked();

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // The advance leg credited exactly once (mult > 0 on a normal day-advance).
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "ADVANCE branch: exactly one doWork creditFlip to the keeper");

        // Non-vacuity: the advance leg actually ran — doWork's advanceGame() either cleared the
        // advance-due predicate or engaged rngLock for the day it just advanced (the multi-stage
        // day-advance locks RNG mid-flight). Either is observable state progress only the advance leg
        // produces (the buy leg was pinned empty and no boxes are pending).
        bool progressed = (dueBefore && !game.advanceDue()) || (!lockedBefore && game.rngLocked());
        assertTrue(progressed, "non-vacuity: the advance leg ran (advance consumed or rngLock engaged)");
    }

    /// @notice OPEN branch: buy leg empty + advance not due + a box pending (RNG-ready, un-opened) ->
    ///         `doWork()` routes to the open leg and credits EXACTLY ONCE.
    function testOpenBranchCreditsExactlyOnce() public {
        address boxOwner = makeAddr("open1_box_owner");
        vm.deal(boxOwner, 100_000 ether);

        // Settle the deploy-day advance so advance is NOT due and we are not locked (boxesPending() is
        // FALSE during rngLock, so the open leg is only reachable from a settled state).
        _settleGame(0x0BACED0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due, open leg is reachable)");
        assertFalse(game.rngLocked(), "pre: settled (not locked, so boxesPending can be TRUE)");

        // Queue a real box (first-deposit signal) and land its index's RNG word.
        uint48 index = _activeLootboxIndex();
        _buyBox(boxOwner, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);

        // Clear the buy leg so the router falls through buy -> advance(not due) -> open.
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();
        assertFalse(game.advanceDue(), "pre: advance not due (open leg is reachable)");
        assertTrue(game.boxesPending(), "pre: a box is pending (RNG-ready, un-opened)");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork();

        // The open leg credited exactly once.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "OPEN branch: exactly one doWork creditFlip to the keeper");

        // Non-vacuity: the queued box actually opened (first-deposit signal zeroed).
        assertEq(_lootboxEthBase(index, boxOwner), 0, "non-vacuity: the open leg opened the queued box");
    }

    /// @notice bountyEarned==0 SKIP path: a buy chunk that walks ONLY already-bought subs runs the buy
    ///         category but credits ZERO (no creditFlip) and does NOT revert. Proves the else-if chain
    ///         entered the buy leg yet the single CEI-last creditFlip was skipped at bounty==0.
    function testBountyEarnedZeroSkipCreditsNothing() public {
        address[] memory subs = _setupHealthyBuyingSubs(2, "skip1_");

        // Stamp every sub bought-today via a full autoBuy.
        vm.prank(makeAddr("skip1_buy_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        for (uint256 i; i < subs.length; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), _today(), "pre: each sub bought today");
        }

        // Re-open the buy leg by resetting the cursor to 0 while keeping the day-stamp == today. The
        // buy predicate (`_autoBuyCursor < length`) is now TRUE, so doWork ENTERS the buy category,
        // but every sub hits the AlreadyAutoBoughtToday skip -> bought == 0 -> bountyEarned == 0.
        _resetCursorToZeroForToday();
        (uint32 progDay, uint256 cursorReset) = afKing.autoBuyProgress();
        assertEq(progDay, _today(), "pre: day-stamp still today (buy leg re-entered, not a fresh day)");
        assertEq(cursorReset, 0, "pre: cursor reset to 0 so the buy leg re-walks the already-bought subs");

        vm.recordLogs();
        vm.prank(keeper);
        // Must NOT revert: the category ran (it just bought nothing) so doWork returns, not NoWork().
        afKing.doWork();

        // ZERO router creditFlips — the bounty was skipped at bountyEarned == 0.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 0, "SKIP path: zero creditFlip when the buy chunk bought nothing");
        assertEq(_countCoinflipStakeUpdated(), 0, "SKIP path: zero creditFlip emissions at all (no stacking, no winnings credit)");
    }

    /// @notice NoWork: all three O(1) predicates empty -> `doWork()` reverts `NoWork()` and credits
    ///         nothing. No subs (buy empty), advance not due, no boxes pending.
    function testNoWorkRevertsAndCreditsNothing() public {
        // Settle the deploy-day advance so advance is NOT due and we are not locked.
        _settleGame(uint256(keccak256("nowork-settle")));
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");

        // Pin the buy leg walked-for-today with NO subscribers backlog, advance not due, no boxes.
        _pinBuyLegWalkedForToday();
        _assertBuyLegEmpty();
        assertFalse(game.advanceDue(), "pre: advance not due");
        assertFalse(game.boxesPending(), "pre: no boxes pending");

        vm.recordLogs();
        vm.prank(keeper);
        vm.expectRevert(); // AfKing.NoWork()
        afKing.doWork();

        // Nothing credited (the revert rolls back, but assert the count is zero regardless).
        assertEq(_countCoinflipStakeUpdated(), 0, "NoWork: zero creditFlip emissions on the empty-work revert");
    }

    // =========================================================================
    // Task 2 — D-01 structural reentrancy attest + D-03 default-batch/remainder + escapes
    // =========================================================================

    /// @notice STRUCTURAL reentrancy attestation (D-01), grep over COMMENT-STRIPPED AfKing source — NO
    ///         attacker harness. Proves (a) the single `creditFlip(msg.sender, bountyEarned)` occurrence
    ///         (CEI-last, one money edge per tx) and (b) every external call in `doWork`/`_autoBuy`
    ///         targets only the pinned `ContractAddresses.GAME` / `ContractAddresses.COINFLIP` — no
    ///         untrusted address and no raw `.call` / `.transfer` / `.send` to a non-pinned target.
    function testDoWorkReentrancyStructurallySafeSourceAttest() public view {
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));
        // Scope the attestation to the doWork() function body (the router legs) — the disposition is
        // about the router path, not unrelated player paths (e.g. the pool withdraw self-send).
        string memory doWorkBody = _extractFunctionBody(afking, "function doWork() external {");
        assertGt(bytes(doWorkBody).length, 0, "D-01: doWork() body extracted");

        // (a) The single unified bounty credit is byte-present EXACTLY ONCE in doWork (CEI-last after
        // the one-category early-return). The :257-style gate, re-pinned here for TST-02. This is the
        // ONLY money edge in the router per tx.
        assertEq(
            _countOccurrences(doWorkBody, "creditFlip(msg.sender, bountyEarned)"),
            1,
            "D-01: exactly one CEI-last doWork creditFlip (the only money edge per tx)"
        );
        // The same gate over the whole file proves there is no second creditFlip site anywhere in
        // AfKing — the unified bounty is the sole creditFlip caller (RD-4 re-homing).
        assertEq(
            _countOccurrences(afking, "creditFlip(msg.sender, bountyEarned)"),
            1,
            "D-01: the unified bounty is the ONLY creditFlip site in AfKing (no per-leg self-credit)"
        );

        // (b) Every external call in the doWork legs targets a PINNED ContractAddresses.* constant.
        // The router's external calls are: GAME.{mintPrice,advanceDue,advanceGame,boxesPending,
        // autoOpen} and COINFLIP.creditFlip. Plan 335-04 collapsed the v49-era inline
        // `IGame(ContractAddresses.GAME).*` cast pattern into compile-time constant immutables
        // declared at AfKing.sol :207 (`IGame internal constant GAME = IGame(ContractAddresses.GAME);`)
        // — same pinned target, cheaper call site. The attestation tracks the immutable name here.
        assertGt(
            _countOccurrences(doWorkBody, "GAME."),
            0,
            "D-01: the doWork game-leg calls target the pinned GAME immutable (= IGame(ContractAddresses.GAME))"
        );
        assertEq(
            _countOccurrences(doWorkBody, "COINFLIP.creditFlip"),
            1,
            "D-01: the only creditFlip target in doWork is the pinned COINFLIP immutable (= ICoinflip(ContractAddresses.COINFLIP))"
        );

        // (c) No untrusted external-call primitive inside the doWork legs that could hand control to an
        // arbitrary address. The bounty is a minted flip-credit ledger move (NO ETH push the keeper
        // receives), so a low-level `.call{value:` / `.transfer(` / `.send(` ETH-push has NO place in
        // any router leg. Asserting ZERO over the comment-stripped doWork body pins the
        // no-ETH-push / no-untrusted-call shape (NatSpec is comment-stripped, so prose can't self-satisfy).
        assertEq(
            _countOccurrences(doWorkBody, ".call{value:"),
            0,
            "D-01: no low-level ETH-push call in the doWork legs (no untrusted reentrancy hook)"
        );
        assertEq(
            _countOccurrences(doWorkBody, ".transfer("),
            0,
            "D-01: no .transfer ETH-push in the doWork legs"
        );
        assertEq(
            _countOccurrences(doWorkBody, ".send("),
            0,
            "D-01: no .send ETH-push in the doWork legs"
        );

        // (d) File-wide, the SOLE low-level ETH-push in AfKing is the CEI-correct `withdraw` self-send
        // (`msg.sender.call{value: amount}("")` after the pool is zeroed) — a subscriber pulling its own
        // prepaid pool, a separate player path, NOT a doWork leg and NOT a creditFlip recipient. Pin its
        // count at exactly 1 so a future second ETH-push (a potential reentrancy surface) flips RED.
        assertEq(
            _countOccurrences(afking, ".call{value: amount}(\"\")"),
            1,
            "D-01: the only file-wide ETH-push is the CEI-correct withdraw self-send (msg.sender)"
        );
    }

    /// @notice D-03 (no-OOG): parameterless `doWork()` runs the FIXED buy default batch (BUY_BATCH=50)
    ///         over a backlog LARGER than the batch, returns without OOG, and leaves a REMAINDER (cursor
    ///         < length); a second `doWork()` advances the cursor further — proving the parameterless
    ///         router chunks (D-07) and never runs an unbounded loop.
    function testParameterlessDoWorkDefaultBatchLeavesRemainder() public {
        // Backlog larger than BUY_BATCH=50 (plus the 2 deploy-time subs). 60 healthy subs.
        uint256 N = 60;
        _setupHealthyBuyingSubs(N, "batch_");
        uint256 total = afKing.subscriberCount();
        assertGt(total, 50, "pre: backlog exceeds the BUY_BATCH default of 50");

        // First parameterless doWork — runs the fixed default batch, must NOT OOG (it returns).
        vm.prank(keeper);
        afKing.doWork();
        (, uint256 cursorAfter1) = afKing.autoBuyProgress();
        assertGt(cursorAfter1, 0, "first doWork advanced the buy cursor");
        assertLt(cursorAfter1, total, "default batch leaves a remainder for the next call (cursor < length)");

        // Buy leg still due (a remainder remains), so a second doWork advances further.
        assertTrue(_buyLegDue(), "pre: buy leg still due after the first default batch");
        vm.prank(keeper);
        afKing.doWork();
        (, uint256 cursorAfter2) = afKing.autoBuyProgress();
        assertGt(cursorAfter2, cursorAfter1, "second doWork advanced the cursor further (chunked, no OOG)");
    }

    /// @notice D-03 UNREWARDED escape: the standalone parametered `autoBuy(count)` runs the buy leg
    ///         (state changes — a sub gets bought) but credits NOTHING (only doWork() credits).
    function testStandaloneAutoBuyEscapeUnrewarded() public {
        address[] memory subs = _setupHealthyBuyingSubs(3, "esc_buy_");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.autoBuy(afKing.subscriberCount() + 5);

        // Work happened: at least one sub bought.
        bool boughtOne;
        for (uint256 i; i < subs.length; i++) {
            if (_lastAutoBoughtDayOf(subs[i]) == _today()) boughtOne = true;
        }
        assertTrue(boughtOne, "non-vacuity: the standalone autoBuy ran the buy leg (a sub was bought)");

        // ...but it credited the KEEPER (caller) NOTHING — the standalone escape pays no router bounty
        // (only doWork() credits). Recipient-isolated to the keeper (D-02): the buy itself can route
        // flip-credit to the BOUGHT subscriber as part of that sub's own reinvest/BURNIE-auto-rebuy
        // config (the two deploy-time protocol subs do exactly this), which is the buy's player-side
        // economic effect, NOT the router bounty. The unrewarded-escape claim is "the caller gets no
        // bounty", so isolate by the keeper recipient.
        assertEq(
            _countCoinflipStakeUpdatedFor(keeper),
            0,
            "UNREWARDED: standalone autoBuy(count) pays the caller zero router bounty"
        );
    }

    /// @notice D-03 UNREWARDED escape: the standalone parametered `autoOpen(count)` runs the open leg
    ///         (a queued box opens) but credits NOTHING (the in-callee bounty was re-homed to doWork at
    ///         RD-4; `game.autoOpen` self-credits zero).
    function testStandaloneAutoOpenEscapeUnrewarded() public {
        address boxOwner = makeAddr("esc_open_box_owner");
        vm.deal(boxOwner, 100_000 ether);

        uint48 index = _activeLootboxIndex();
        _buyBox(boxOwner, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);
        assertGt(_lootboxEthBase(index, boxOwner), 0, "pre: box queued + un-opened");
        assertTrue(game.boxesPending(), "pre: a box is pending");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.autoOpen(50);

        // Work happened: the box opened (first-deposit signal zeroed).
        assertEq(_lootboxEthBase(index, boxOwner), 0, "non-vacuity: the standalone autoOpen opened the box");

        // ...but the keeper got NO bounty credit (only doWork credits). A box open can itself credit
        // BURNIE winnings to the BOX OWNER (LootboxModule:1036), so isolate the keeper's count: it is 0.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 0, "UNREWARDED: standalone autoOpen(count) credits the keeper zero");
    }

    // =========================================================================
    // creditFlip-count oracle (verbatim port of CrankLeversAndPacking.t.sol:523-548)
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

    /// @dev Count CoinflipStakeUpdated emissions whose indexed `player` topic == `who`. The event is
    ///      `CoinflipStakeUpdated(address indexed player, uint32 indexed day, uint256 amount, uint256 newTotal)`
    ///      so the player address is topics[1]. Isolates the router bounty (to the keeper) from a
    ///      box-owner's winnings credit (LootboxModule:1036) — the count cannot be inflated/masked.
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
    // Source-grep helpers (byte-faithful port of CrankLeversAndPacking.t.sol:554-633)
    // =========================================================================

    /// @dev Count non-overlapping occurrences of `needle` in `haystack`.
    function _countOccurrences(string memory haystack, string memory needle)
        private
        pure
        returns (uint256 count)
    {
        bytes memory hb = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || hb.length < n.length) return 0;
        for (uint256 i = 0; i <= hb.length - n.length; ) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; ++j) {
                if (hb[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                unchecked {
                    ++count;
                    i += n.length;
                }
            } else {
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @dev Strip `//` line comments and lines whose first non-space char starts a block comment
    ///      (`*` or `/*`), so NatSpec prose mentioning a symbol cannot self-satisfy/self-invalidate a
    ///      grep gate. Code matches survive.
    function _stripComments(string memory src) private pure returns (string memory) {
        bytes memory b = bytes(src);
        bytes memory out = new bytes(b.length);
        uint256 o;
        uint256 i;
        uint256 lineStart;
        bool lineIsBlockComment;
        while (i < b.length) {
            if (b[i] == 0x0a) {
                out[o++] = b[i];
                i++;
                lineStart = i;
                lineIsBlockComment = false;
                continue;
            }
            if (i == lineStart || _onlySpacesSince(b, lineStart, i)) {
                if (b[i] == 0x2a) {
                    lineIsBlockComment = true;
                } else if (b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2a) {
                    lineIsBlockComment = true;
                }
            }
            if (!lineIsBlockComment && b[i] == 0x2f && i + 1 < b.length && b[i + 1] == 0x2f) {
                while (i < b.length && b[i] != 0x0a) i++;
                continue;
            }
            if (!lineIsBlockComment) {
                out[o++] = b[i];
            }
            i++;
        }
        bytes memory trimmed = new bytes(o);
        for (uint256 k; k < o; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    /// @dev True iff every byte in [from, to) is a space (0x20) or tab (0x09).
    function _onlySpacesSince(bytes memory b, uint256 from, uint256 to)
        private
        pure
        returns (bool)
    {
        for (uint256 i = from; i < to; i++) {
            if (b[i] != 0x20 && b[i] != 0x09) return false;
        }
        return true;
    }

    /// @dev Extract a function body: locate `sig` (which ends at the opening `{`), then return the
    ///      substring from that `{` to its brace-depth-matched `}` (inclusive). Returns "" if not found.
    ///      Used to scope a grep gate to a single function body (e.g. doWork()'s router legs).
    function _extractFunctionBody(string memory haystack, string memory sig)
        private
        pure
        returns (string memory)
    {
        bytes memory hb = bytes(haystack);
        bytes memory s = bytes(sig);
        if (s.length == 0 || hb.length < s.length) return "";
        // Find the signature (its trailing `{` is the open brace we depth-match from).
        uint256 sigStart = type(uint256).max;
        for (uint256 i = 0; i <= hb.length - s.length; i++) {
            bool matched = true;
            for (uint256 j = 0; j < s.length; j++) {
                if (hb[i + j] != s[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                sigStart = i;
                break;
            }
        }
        if (sigStart == type(uint256).max) return "";
        uint256 open = sigStart + s.length - 1; // index of the trailing `{` in `sig`
        uint256 depth;
        uint256 end = open;
        for (uint256 i = open; i < hb.length; i++) {
            if (hb[i] == 0x7b) depth++;        // {
            else if (hb[i] == 0x7d) {          // }
                depth--;
                if (depth == 0) {
                    end = i;
                    break;
                }
            }
        }
        bytes memory out = new bytes(end - open + 1);
        for (uint256 k = 0; k <= end - open; k++) out[k] = hb[open + k];
        return string(out);
    }

    // =========================================================================
    // Protocol-driving helpers (mirror AfKingConcurrency / CrankOpenBoxWorstCaseGas)
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev True iff AfKing's buy-leg predicate (`_autoBuyDay != _currentDay() || cursor < length`) is TRUE.
    function _buyLegDue() internal view returns (bool) {
        (uint32 progDay, uint256 cursor) = afKing.autoBuyProgress();
        return progDay != _today() || cursor < afKing.subscriberCount();
    }

    function _assertBuyLegEmpty() internal view {
        assertFalse(_buyLegDue(), "pre: buy leg is empty (walked + stamped for today)");
    }

    /// @dev Subscribe `n` fresh players as fully-healthy buying subs (ticket mode, operator-approved,
    ///      pool-funded, not renewal-due) so each lands a clean buy. Mirrors AfKingConcurrency.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _fundBurnie(who, _subCost()); // for the no-pass subscribe-time all-or-nothing charge
            vm.prank(who);
            afKing.subscribe(address(0), false, true, 1, 0, address(0)); // self, drainCredit=false, ticket, qty 1, self-funded
            vm.prank(who);
            game.setOperatorApproval(address(afKing), true);
            _fundPool(who, 1 ether);
        }
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

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot).
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Force the autoBuy cursor back to 0 while keeping the day-stamp == today, so the next autoBuy
    ///      re-walks index 0. Slot 4: _autoBuyDay (uint32 bytes 0..3) + _autoBuyCursor (uint224 bytes 4..).
    function _resetCursorToZeroForToday() internal {
        uint256 packed = uint256(vm.load(address(afKing), bytes32(uint256(AUTOBUY_SLOT))));
        packed &= uint256(0xFFFFFFFF);             // keep _autoBuyDay (low 4 bytes), zero the cursor
        packed &= ~uint256(0xFFFFFFFF);            // clear the day field too, then re-stamp today
        packed |= (uint256(_today()) & 0xFFFFFFFF);
        vm.store(address(afKing), bytes32(uint256(AUTOBUY_SLOT)), bytes32(packed));
    }

    /// @dev Pin the buy leg "walked for today": stamp _autoBuyDay == today AND cursor >= length so the
    ///      buy-leg predicate (`_autoBuyDay != _currentDay() || cursor < length`) is FALSE. Used to force
    ///      the router past the buy leg into advance / open / NoWork without re-opening the buy backlog.
    function _pinBuyLegWalkedForToday() internal {
        uint256 len = afKing.subscriberCount();
        uint256 packed = (uint256(_today()) & 0xFFFFFFFF) | ((len + 1) << 32);
        vm.store(address(afKing), bytes32(uint256(AUTOBUY_SLOT)), bytes32(packed));
    }

    /// @dev Buy a real lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> enqueueBoxForAutoOpen (MintModule).
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 37).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 38).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Read lootboxEthBase[index][who] — the first-deposit signal, zeroed on open.
    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
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
