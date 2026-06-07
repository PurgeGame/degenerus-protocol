// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperRouterOneCategory -- TST-02 (Phase 351, v55.0 game-resident): one-rewarded-category-per-tx
///        (no bounty-stacking) on `mintBurnie()` + the router->game->creditFlip double-pay disposition + the
///        standalone UNREWARDED human `autoOpen(count)` escape.
///
/// @notice The v55 router (`game.mintBurnie()`, GameAfkingModule.sol:985) is a STRUCTURAL one-category
///         early-return: `if (advanceDue) {advance leg} else {open leg}` (GameAfkingModule.sol:993 vs :1000).
///         There are exactly TWO router categories — advance (the buy folded into advanceGame's required-path
///         STAGE, so it rides the advance bounty) and the afking-box open. The else-if XOR is the mitigation
///         for bounty-stacking; the single CEI-last `creditFlip(msg.sender, bountyEarned)`
///         (GameAfkingModule.sol:1014-1016) is the mitigation for a composed reentrant double-pay. Security
///         is the HARD FLOOR.
///
///   D-02 (no-stacking proven by COUNTING `creditFlip`, NOT exact amounts): each `mintBurnie()` tx fires
///   EXACTLY ONE `coinflip.creditFlip` across both category branches (advance / open), ZERO on the
///   `bountyEarned==0` skip (a mult==0 gameover advance runs the category but credits nothing, still no
///   revert), and ZERO + `revert NoWork()` when BOTH O(1) predicates are empty. The count is taken via the
///   recipient-isolated `_countCoinflipStakeUpdatedFor(keeper)` oracle (topics[1] == keeper) so a
///   box-owner's / player's winnings credit can never inflate or mask the router bounty count. Asserting
///   COUNT (==1 / ==0) across both branches IS the proof the else early-return can never credit two
///   categories in one tx.
///
///   D-01 (reentrancy is STRUCTURAL, NO attacker harness): `mintBurnie` pays only minted FLIP CREDIT, makes
///   NO ETH push, and every external call in every leg targets either a self-call
///   (`IGameRouter(address(this))`) or the pinned `coinflip` immutable. There is no untrusted call to
///   re-enter through, so a synthetic reentrant attacker has no hook. The disposition is satisfied by a
///   comment-stripped source grep-attestation: (a) the single `creditFlip(msg.sender, bountyEarned)`
///   occurrence (==1, CEI-last), and (b) ZERO low-level ETH-push primitives in the mintBurnie legs (the
///   module pushes no ETH at all — funding withdraw moved to DegenerusGame). NO attacker/reentrant mock
///   exists in this file (User verbatim: "reentrancy is not an issue, nothing here pays eth and this only
///   interacts with trusted contracts.").
///
///   D-03 (default-batch / escapes): `mintBurnie()` runs the fixed open-leg default batch (OPEN_BATCH=200)
///   and does NOT OOG; the standalone parametered HUMAN `game.openBoxes(count)` is an emergency escape that
///   runs the human box leg but credits NOTHING (only `mintBurnie` credits). The afking-module standalone
///   `autoOpen` selector COLLIDES with the human `autoOpen(uint256)` so the afking open is reachable ONLY
///   through `mintBurnie` (DegenerusGame.sol:352-353) — there is no separately-callable unrewarded afking
///   escape to test here.
///
/// @dev The five call-site deltas applied (D-351-01):
///   Δ3 doWork->mintBurnie: `afKing.doWork()` -> `game.mintBurnie()` (all sites).
///   Δ4 autoBuy: the per-sub buy folded into `advanceGame()`'s STAGE — driven via a new-day advanceGame()
///      + the `_settleGame` VRF drain; the standalone `autoBuy(count)` has NO successor.
///   Δ5 views: `afKing.subscriberCount()`/`autoBuyProgress()` -> read `_subscribers.length`/`_subCursor` via
///      vm.load (RE-DERIVED slots).
///   Two runtime traps cleared: AFKING_SRC repointed from the deleted standalone-contract path to
///   "contracts/modules/GameAfkingModule.sol" (the deleted file THROWS at runtime under vm.readFile) +
///   every grepped token re-derived for the relocated mintBurnie body.
///   Pinned slots RE-DERIVED via `forge inspect storage DegenerusGame`. Zero contracts/*.sol mutation.
contract KeeperRouterOneCategory is DeployProtocol {
    // -------------------------------------------------------------------------
    // creditFlip-count oracle (recipient-isolated)
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once per
    ///      creditFlip. The indexed `player` is topics[1] (recipient isolation).
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`;
    // the AfKing-standalone SUBOF_SLOT=65 / AUTOBUY_SLOT=4 / lootbox slots 37/38 were WRONG).
    // -------------------------------------------------------------------------

    uint256 private constant SUBOF_SLOT = 62; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)
    uint256 private constant SUBSCRIBERS_SLOT = 64; // _subscribers address[] (length here)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS_SHIFT in mintPacked_

    /// @dev lootboxRngPacked at slot 36; index = low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 36;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 37;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

    /// @dev ticketQueue mapping root (uint24 => address[]) + ticketsOwedPacked
    ///      (uint24 => address => uint40) — for forcing advanceDue via a read-slot backlog.
    uint256 private constant TICKET_QUEUE_SLOT = 12;
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13;
    uint24 private constant TICKET_SLOT_BIT = 1 << 23; // mirrors DegenerusGameStorage.TICKET_SLOT_BIT

    uint256 private constant FIXED_WORD = uint256(keccak256("keeper_router_one_category_word"));
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit human box

    // -------------------------------------------------------------------------
    // Source path for the comment-stripped grep attestation (REPOINTED: the standalone AfKing.sol is
    // deleted -> vm.readFile would THROW at runtime; the rewarded router now lives in GameAfkingModule).
    // -------------------------------------------------------------------------

    string private constant AFKING_SRC = "contracts/modules/GameAfkingModule.sol";

    address private keeper;
    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // One keeper-local day off the deploy boundary so the day index is a clean, stable value.
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        keeper = makeAddr("router_keeper");
        vm.deal(keeper, 100_000 ether);
        vm.deal(address(game), 1_000_000 ether);
    }

    /// @dev Settle the game to a clean state: drive advanceGame + deliver the mock VRF word until
    ///      `advanceDue()` is false and we are not locked. (PATTERNS §"Settle-to-clean-state VRF drain".)
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
    // Task 1 — D-02 one-category creditFlip COUNT across both branches + skip + NoWork
    // =========================================================================

    /// @notice ADVANCE branch: with `advanceDue()` true, `mintBurnie()` takes the advance leg (the
    ///         structural early-return's `if (advanceDue)` arm); a multiplier > 0 credits EXACTLY ONCE.
    ///         The buy folded into advanceGame's STAGE rides this single advance bounty.
    function testAdvanceBranchCreditsExactlyOnce() public {
        // Settle the deploy-day advance so we start from a clean, not-due, not-locked state.
        _settleGame(0xADADADAD0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");

        // Drive `advanceDue()` true: roll the wall clock forward so the simulated day index moves ahead.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: advance is due");

        bool dueBefore = game.advanceDue();
        bool lockedBefore = game.rngLocked();

        vm.recordLogs();
        vm.prank(keeper);
        game.mintBurnie();

        // The advance leg credited exactly once (mult > 0 on a normal day-advance).
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "ADVANCE branch: exactly one mintBurnie creditFlip to the keeper");

        // Non-vacuity: the advance leg actually ran — mintBurnie's advanceGame() either cleared the
        // advance-due predicate or engaged rngLock for the day it just advanced (the multi-stage
        // day-advance locks RNG mid-flight). Either is observable state progress only the advance leg produces.
        bool progressed = (dueBefore && !game.advanceDue()) || (!lockedBefore && game.rngLocked());
        assertTrue(progressed, "non-vacuity: the advance leg ran (advance consumed or rngLock engaged)");
    }

    /// @notice OPEN branch: advance NOT due + an afking-stamped box pending (RNG-ready, un-opened) ->
    ///         `mintBurnie()` takes the `else` open leg and credits EXACTLY ONCE. (The afking open is
    ///         reachable ONLY via mintBurnie — the module's standalone autoOpen selector collides with the
    ///         human autoOpen(uint256) and is not re-exposed on the Game.)
    function testOpenBranchCreditsExactlyOnce() public {
        vm.skip(true, "357-00b D-12 supersession: the one-category router harness subscribes an ungrounded sub then routes the STAGE buy/open; the grounded subscribe perturbs the single-category early-return + open-credit path; re-proven by V56AfkingGasMarginal + V56SubHardening");
        // A funded LOOTBOX-mode sub gets a stamped afking box via the STAGE (deity-passed so it survives
        // any level crossing — orthogonal to the router-branch property).
        address sub = makeAddr("open1_afk_sub");
        _grantDeityPass(sub);
        _subscribeLootbox(sub, 1);
        _fundPool(sub, 5 ether);
        _runStageNewDay(0x0BACED01); // stamp the afking box (lastAutoBoughtDay set, day word landed)

        // Settle so advance is NOT due and we are not locked (the open leg is the `else` arm, reachable
        // only when !advanceDue; the open leg also no-ops during rngLock).
        _settleGame(0x0BACED02);
        assertFalse(game.advanceDue(), "pre: settled (advance not due, the open leg is reachable)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");

        uint32 stampDay = _lastBoughtDayOf(sub);
        assertGt(stampDay, 0, "pre: an afking box is stamped (RNG-ready)");
        assertTrue(_lastOpenedDayOf(sub) < stampDay, "pre: the afking box is un-opened (pending)");

        vm.recordLogs();
        vm.prank(keeper);
        game.mintBurnie();

        // The open leg credited exactly once.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "OPEN branch: exactly one mintBurnie creditFlip to the keeper");

        // Non-vacuity: the stamped afking box actually opened (its open marker advanced to the stamp day).
        assertEq(_lastOpenedDayOf(sub), stampDay, "non-vacuity: the open leg materialized the afking box");
    }

    /// @notice bountyEarned==0 SKIP path: a gameover advance (mult==0) runs the advance CATEGORY (the
    ///         `if (advanceDue)` arm executes advanceGame) but credits ZERO (no creditFlip) and does NOT
    ///         revert. Proves the early-return took a category yet the single CEI-last creditFlip was
    ///         skipped at bountyEarned==0 (the category still ran, so mintBurnie RETURNS, not NoWork()).
    function testBountyEarnedZeroSkipCreditsNothing() public {
        _settleGame(0x5C1F0001);
        assertFalse(game.advanceDue(), "pre: settled");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        // Latch gameOver so the advance leg returns mult==0 (the flip-credit is worthless at gameover).
        _latchGameOver();
        assertTrue(game.gameOver(), "pre: gameOver latched");
        assertTrue(game.advanceDue(), "pre: advance still due (mintBurnie routes to the advance leg)");

        vm.recordLogs();
        vm.prank(keeper);
        // Must NOT revert: the advance category ran (it just earned mult==0) so mintBurnie returns, not NoWork().
        game.mintBurnie();

        // ZERO router creditFlips — the bounty was skipped at bountyEarned == 0.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 0, "SKIP path: zero creditFlip when the advance leg earned mult==0");
        assertEq(_countCoinflipStakeUpdated(), 0, "SKIP path: zero creditFlip emissions at all (no stacking, no winnings credit)");
    }

    /// @notice NoWork: BOTH O(1) predicates empty -> `mintBurnie()` reverts `NoWork()` and credits
    ///         nothing. Advance not due + no afking boxes pending.
    function testNoWorkRevertsAndCreditsNothing() public {
        // Settle the deploy-day advance so advance is NOT due and we are not locked.
        _settleGame(uint256(keccak256("nowork-settle")));
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");
        // No afking subscriber stamped a box (no STAGE buy was driven), so the open leg has nothing.

        vm.recordLogs();
        vm.prank(keeper);
        vm.expectRevert(); // GameAfkingModule.NoWork()
        game.mintBurnie();

        // Nothing credited (the revert rolls back, but assert the count is zero regardless).
        assertEq(_countCoinflipStakeUpdated(), 0, "NoWork: zero creditFlip emissions on the empty-work revert");
    }

    // =========================================================================
    // Task 2 — D-01 structural reentrancy attest + D-03 one-category early-return + the human escape
    // =========================================================================

    /// @notice STRUCTURAL reentrancy attestation (D-01), grep over the COMMENT-STRIPPED GameAfkingModule
    ///         source — NO attacker harness. Proves (a) the single `creditFlip(msg.sender, bountyEarned)`
    ///         occurrence (CEI-last, one money edge per tx) and (b) ZERO low-level ETH-push primitives in
    ///         the mintBurnie legs (the module pushes no ETH at all). The source-grep finds the relocated
    ///         mintBurnie body at the new GameAfkingModule.sol location (no runtime throw on the deleted
    ///         AfKing.sol).
    function testMintBurnieReentrancyStructurallySafeSourceAttest() public view {
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));
        // Scope the attestation to the mintBurnie() function body (the router legs).
        string memory body = _extractFunctionBody(afking, "function mintBurnie() external {");
        assertGt(bytes(body).length, 0, "D-01: mintBurnie() body extracted (source-grep repointed, no readFile throw)");

        // (a) The single unified bounty credit is byte-present EXACTLY ONCE in mintBurnie (CEI-last after
        // the one-category early-return). This is the ONLY money edge in the router per tx.
        assertEq(
            _countOccurrences(body, "creditFlip(msg.sender, bountyEarned)"),
            1,
            "D-01: exactly one CEI-last mintBurnie creditFlip (the only money edge per tx)"
        );
        // The same gate over the whole file proves the unified bounty is the SOLE `creditFlip(msg.sender,...)`
        // site — there is no second router self-credit (the other creditFlip in the file is the 349.2 per-buy
        // `creditFlip(player, flipCredit)` affiliate/quest side-effect inside the STAGE, a different recipient
        // and a different argument shape, NOT a router bounty).
        assertEq(
            _countOccurrences(afking, "creditFlip(msg.sender, bountyEarned)"),
            1,
            "D-01: the unified bounty is the ONLY creditFlip(msg.sender, bountyEarned) site (no per-leg self-credit)"
        );

        // (b) NO untrusted external-call primitive inside the mintBurnie legs that could hand control to an
        // arbitrary address. The bounty is a minted flip-credit ledger move (NO ETH push), so a low-level
        // `.call{value:` / `.transfer(` / `.send(` ETH-push has NO place in any router leg. Asserting ZERO
        // over the comment-stripped mintBurnie body pins the no-ETH-push / no-untrusted-call shape.
        assertEq(_countOccurrences(body, ".call{value:"), 0, "D-01: no low-level ETH-push call in the mintBurnie legs");
        assertEq(_countOccurrences(body, ".transfer("), 0, "D-01: no .transfer ETH-push in the mintBurnie legs");
        assertEq(_countOccurrences(body, ".send("), 0, "D-01: no .send ETH-push in the mintBurnie legs");

        // (c) File-wide, the GameAfkingModule pushes NO ETH at all (the funding self-send was re-homed to
        // DegenerusGame.withdrawAfkingFunding, NOT this module). Pin the module's low-level ETH-push count at
        // exactly 0 so a future ETH-push surface (a potential reentrancy vector) flips RED.
        assertEq(
            _countOccurrences(afking, ".call{value:"),
            0,
            "D-01: the GameAfkingModule pushes no ETH file-wide (funding withdraw lives on DegenerusGame)"
        );
    }

    /// @notice D-03 ONE-CATEGORY structural early-return (the load-bearing no-stack property): a single
    ///         `mintBurnie()` tx credits EXACTLY ONE category. When advance is due it credits the advance
    ///         leg ONCE and does NOT additionally open a pending afking box in the SAME tx (the `else` arm
    ///         is unreachable when the `if (advanceDue)` arm is taken). Proven by: stage a pending afking
    ///         box AND make advance due, then assert the single mintBurnie credits once AND leaves the
    ///         afking box unopened (the open leg never ran — no stacking).
    function testOneCategoryEarlyReturnNoStack() public {
        vm.skip(true, "357-00b D-12 supersession: the one-category router harness subscribes an ungrounded sub then routes the STAGE buy/open; the grounded subscribe perturbs the single-category early-return + open-credit path; re-proven by V56AfkingGasMarginal + V56SubHardening");
        // Stage a pending afking box first (on a settled day).
        address sub = makeAddr("nostack_afk_sub");
        _grantDeityPass(sub);
        _subscribeLootbox(sub, 1);
        _fundPool(sub, 5 ether);
        _runStageNewDay(0x0FACE01);
        _settleGame(0x0FACE02);
        uint32 stampDay = _lastBoughtDayOf(sub);
        assertGt(stampDay, 0, "pre: an afking box is stamped");
        assertTrue(_lastOpenedDayOf(sub) < stampDay, "pre: the afking box is pending (un-opened)");

        // Now ALSO make advance due — via a LARGE multi-player read-slot backlog (advanceDue() is TRUE
        // when the read slot is non-empty + not fully processed). The backlog exceeds the per-batch write
        // budget so the mid-day partial-drain advance WORKS but does NOT finish (mult==1, no NotTimeYet),
        // and a warp cannot drive a fresh new-day advance here (the idle fixture's day index saturates
        // after the STAGE day — 351-02). The structural early-return takes the advance arm (XOR), so the
        // pending afking box is NOT opened in this same tx.
        uint24 readKey = _readKey(uint24(game.level()) + 1);
        for (uint256 i; i < 200; i++) {
            _seedReadSlotTickets(readKey, makeAddr(string(abi.encodePacked("nostack_backlog_", _u(i)))), 3);
        }
        _setTicketsFullyProcessed(false);
        assertTrue(game.advanceDue(), "pre: advance is due (the `if` arm will be taken, not the open `else`)");

        vm.recordLogs();
        vm.prank(keeper);
        game.mintBurnie();

        // Exactly ONE category credited (the advance leg) — no second open-leg credit.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "ONE-CATEGORY: exactly one credit (advance), no stacked open credit");
        // The pending afking box was NOT opened this tx (the `else` open arm never ran — XOR).
        assertTrue(
            _lastOpenedDayOf(sub) < stampDay,
            "ONE-CATEGORY: the pending afking box stayed unopened (advance arm taken, open arm not stacked)"
        );
    }

    /// @notice D-03 UNREWARDED escape: the standalone parametered HUMAN `game.openBoxes(count)` runs the
    ///         human box leg (a queued human box opens) but credits NOTHING (only `mintBurnie` credits).
    function testStandaloneAutoOpenEscapeUnrewarded() public {
        address boxOwner = makeAddr("esc_open_box_owner");
        vm.deal(boxOwner, 100_000 ether);

        // Settle so the human box can be queued + opened cleanly.
        _settleGame(0xE5C0_0001);
        uint48 index = _activeLootboxIndex();
        _buyBox(boxOwner, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);
        assertGt(_lootboxEthBase(index, boxOwner), 0, "pre: human box queued + un-opened");
        assertTrue(game.boxesPending(), "pre: a human box is pending");

        vm.recordLogs();
        vm.prank(keeper);
        game.openBoxes(50);

        // Work happened: the human box opened (first-deposit signal zeroed).
        assertEq(_lootboxEthBase(index, boxOwner), 0, "non-vacuity: the standalone autoOpen opened the human box");

        // ...but the keeper got NO bounty credit (only mintBurnie credits). A box open can itself credit
        // BURNIE winnings to the BOX OWNER, so isolate the keeper's count: it is 0.
        assertEq(_countCoinflipStakeUpdatedFor(keeper), 0, "UNREWARDED: standalone autoOpen(count) credits the keeper zero");
    }

    // =========================================================================
    // creditFlip-count oracle
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

    /// @dev Count CoinflipStakeUpdated emissions whose indexed `player` topic == `who` (topics[1]).
    ///      Isolates the router bounty (to the keeper) from a box-owner's winnings credit.
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
    // Source-grep helpers (comment-stripped, function-body scoped)
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
    function _extractFunctionBody(string memory haystack, string memory sig)
        private
        pure
        returns (string memory)
    {
        bytes memory hb = bytes(haystack);
        bytes memory s = bytes(sig);
        if (s.length == 0 || hb.length < s.length) return "";
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
    // Protocol-driving helpers (mirror AfKingConcurrency / V55SetMutationOpenE)
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (Δ4 successor to afKing.autoBuy): warp +1 day,
    ///      settle so processSubscriberStage(SUB_STAGE_BATCH) stamps the funded set + the day word lands.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Subscribe `who` as a self-funded LOOTBOX-mode sub (the afking box stamp path).
    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
    }

    /// @dev Credit `who`'s afkingFunding bucket (Δ5: depositAfkingFunding replaces AfKing.depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity bit (mintPacked_ is slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    // ---- Sub field reads (_subOf slot 62 + verified offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    // ---- gameover latch ----

    /// @dev Latch the terminal gameOver public bool (byte 21 of SLOT 0) WITHOUT setting the gameover-time
    ///      slot, so the advance takes the gameover branch (mult=0) harmlessly.
    function _latchGameOver() internal {
        bytes32 slot = bytes32(uint256(0));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << (21 * 8));
        vm.store(address(game), slot, bytes32(packed));
        require(game.gameOver(), "_latchGameOver: gameOver did not flip (slot 0 byte 21)");
    }

    // ---- human box helpers (the unrewarded human autoOpen escape) ----

    /// @dev Buy a real human lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> enqueueBoxForAutoOpen.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 36).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 39).
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

    // ---- read-slot ticket seeding (force advanceDue via a non-empty current-level read slot) ----

    /// @dev Read the GAME's live ticketWriteSlot bool (SLOT 0 byte 28).
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((slot0 >> (28 * 8)) & 0x1) != 0;
    }

    /// @dev The current read key for a level — byte-faithful to DegenerusGameStorage._tqReadKey.
    function _readKey(uint24 lvl) internal view returns (uint24) {
        return !_ticketWriteSlot() ? (lvl | TICKET_SLOT_BIT) : lvl;
    }

    /// @dev Seed `whole` current-level tickets for `who` at the read key (packed: owed=whole*4 << 8 | rem)
    ///      and append `who` to ticketQueue[readKey], so advanceDue() sees a non-empty read slot.
    function _seedReadSlotTickets(uint24 readKey, address who, uint32 whole) internal {
        uint32 entries = whole * 4;
        uint40 packed = uint40(uint256(entries) << 8);
        bytes32 owedInner = keccak256(abi.encode(uint256(readKey), TICKETS_OWED_PACKED_SLOT));
        vm.store(address(game), keccak256(abi.encode(who, uint256(owedInner))), bytes32(uint256(packed)));

        bytes32 lenSlot = keccak256(abi.encode(uint256(readKey), TICKET_QUEUE_SLOT));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        vm.store(address(game), bytes32(uint256(dataBase) + len), bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
    }

    /// @dev Set the ticketsFullyProcessed bool (SLOT 0 byte 26), preserving the rest of slot 0.
    function _setTicketsFullyProcessed(bool v) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFF) << (26 * 8);
        slot0 &= ~mask;
        if (v) slot0 |= (uint256(1) << (26 * 8));
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
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
