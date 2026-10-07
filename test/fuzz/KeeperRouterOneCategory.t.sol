// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

// CURRENT ENGINE (60d31f775 / 72fc06f6c): the two-category router below is retired. `mineFlip()`
//      (DegenerusGameMinerModule) selects one action at a time from storage, composes as many as its
//      allowance admits, and credits the caller ONCE per call, after the loop, on measured gas above
//      an unpaid first MIN_REWARDED_GAS. The no-stacking proof is unchanged in form: count the
//      keeper's creditFlip per call (exactly one on a paid call, zero on NoWork). The source attest
//      now targets the engine module. The history below is kept for the requirement IDs.
/// @title KeeperRouterOneCategory -- TST-02 (Phase 351, v55.0 game-resident): one-rewarded-category-per-tx
///        (no bounty-stacking) on `mineFlip()` + the router->game->creditFlip double-pay disposition.
///
/// @notice The v55 router (`game.mineFlip()`, GameAfkingModule.sol:985) is a STRUCTURAL one-category
///         early-return: `if (advanceDue) {advance leg} else {open leg}` (GameAfkingModule.sol:993 vs :1000).
///         There are exactly TWO router categories — advance (the buy folded into mineFlip's required-path
///         STAGE, so it rides the advance bounty) and the box open (afking boxes first, then human boxes with
///         the leftover budget — one combined open bounty). The else-if XOR is the mitigation
///         for bounty-stacking; the single CEI-last `creditFlip(msg.sender, total)`
///         (GameAfkingModule.sol:1014-1016) is the mitigation for a composed reentrant double-pay. Security
///         is the HARD FLOOR.
///
///   D-02 (no-stacking proven by COUNTING `creditFlip`, NOT exact amounts): each `mineFlip()` tx fires
///   EXACTLY ONE `coinflip.creditFlip` across both category branches (advance / open), ZERO on the
///   `bountyEarned==0` skip (the sweep-pending gameover advance, or an ineligible keeper's advance, runs
///   the category but credits nothing, still no revert), and ZERO + `revert NoWork()` when there is no
///   work — BOTH O(1) predicates empty, OR a post-gameover idle crank with no final sweep pending. The count is taken via the
///   recipient-isolated `_countFor(logs, keeper)` oracle (topics[1] == keeper) so a
///   box-owner's / player's winnings credit can never inflate or mask the router bounty count. Asserting
///   COUNT (==1 / ==0) across both branches IS the proof the else early-return can never credit two
///   categories in one tx.
///
///   D-01 (reentrancy is STRUCTURAL, NO attacker harness): `mineFlip` pays only minted FLIP CREDIT, makes
///   NO ETH push, and every external call in every leg targets either a self-call
///   (`IGameRouter(address(this))`), the pinned `coinflip` immutable, or a pinned
///   `ContractAddresses.GAME_LOOTBOX_MODULE` delegatecall (the afking + human box-open legs — both
///   pull-only: no callee on those paths hands control to player code). There is no untrusted call to
///   re-enter through, so a synthetic reentrant attacker has no hook. The disposition is satisfied by a
///   comment-stripped source grep-attestation: (a) the single `creditFlip(msg.sender, total)`
///   occurrence (==1, CEI-last), and (b) ZERO low-level ETH-push primitives in the mineFlip legs (the
///   module pushes no ETH at all — funding withdraw moved to DegenerusGame). NO attacker/reentrant mock
///   exists in this file (User verbatim: "reentrancy is not an issue, nothing here pays eth and this only
///   interacts with trusted contracts.").
///
///   D-03 (box stages): box opens run only inside `mineFlip()`, as ordered read-consumer stages — AFKING
///   boxes first, then HUMAN boxes — and the call pays the keeper once, on its measured gas
///   (testMintFlipOpensHumanBoxAndPaysBounty).
///
/// @dev The five call-site deltas applied (D-351-01):
///   Δ3 doWork->mineFlip: `afKing.doWork()` -> `game.mineFlip()` (all sites).
///   Δ4 autoBuy: the per-sub buy folded into `mineFlip()`'s STAGE — driven via a new-day mineFlip()
///      + the `_settleGame` VRF drain; the standalone `autoBuy(count)` has NO successor.
///   Δ5 views: `afKing.subscriberCount()`/`autoBuyProgress()` -> read `_subscribers.length`/`_subCursor` via
///      vm.load (RE-DERIVED slots).
///   Two runtime traps cleared: AFKING_SRC repointed from the deleted standalone-contract path to
///   "contracts/modules/GameAfkingModule.sol" (the deleted file THROWS at runtime under vm.readFile) +
///   every grepped token re-derived for the relocated mineFlip body.
///   Pinned slots RE-DERIVED via `forge inspect storage DegenerusGame`. Zero contracts/*.sol mutation.
contract KeeperRouterOneCategory is DeployProtocol {
    // -------------------------------------------------------------------------
    // creditFlip-count oracle (recipient-isolated)
    // -------------------------------------------------------------------------

    /// @dev keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)") — emitted once per
    ///      creditFlip. The indexed `player` is topics[1] (recipient isolation).
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `solc --storage-layout` on the working tree after
    // the V62 lootbox repack — the folded lootboxEth word + removed lootboxEthBase/Flip/Purchase/
    // Distress shifted later slots down. The prior _subOf=62 / _subscribers=64 / lootbox 36/37/22
    // pins are now stale; corrected to the authoritative values below.)
    // -------------------------------------------------------------------------

    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9; Sub: u8 qty, u8 flags, u16 score, u24 amount)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // _subscribers address[] (length here)
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit)
    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;

    /// @dev lootboxRngPacked at slot 34; index = low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    /// @dev ticketQueue mapping root (uint24 => address[]) + entriesOwedPacked
    ///      (uint24 => address => uint40) — for forcing advanceDue via a read-slot backlog.
    uint256 private constant TICKET_QUEUE_SLOT = GameSlots.TICKET_QUEUE;
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13;
    uint24 private constant TICKET_SLOT_BIT = 1 << 23; // mirrors DegenerusGameStorage.TICKET_SLOT_BIT

    uint256 private constant FIXED_WORD = uint256(keccak256("keeper_router_one_category_word"));
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit human box

    // -------------------------------------------------------------------------
    // Source path for the comment-stripped grep attestation (REPOINTED: the standalone AfKing.sol is
    // deleted -> vm.readFile would THROW at runtime; the rewarded router now lives in GameAfkingModule).
    // -------------------------------------------------------------------------

    string private constant AFKING_SRC = "contracts/modules/GameAfkingModule.sol";
    /// @dev The single permissionless engine (60d31f775): one dispatcher, one credit site.
    string private constant MINER_SRC = "contracts/modules/DegenerusGameMinerModule.sol";

    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");
    /// @dev Distinct human-box owners in the rewarded open test: enough opens that the call
    ///      measures past the unpaid first MIN_REWARDED_GAS (72fc06f6c).
    uint256 private constant PAID_BOX_OWNERS = 24;

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

    /// @dev Settle the game to a clean state: drive mineFlip + deliver the mock VRF word until
    ///      `advanceDue()` is false and we are not locked. (PATTERNS §"Settle-to-clean-state VRF drain".)
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

    /// @dev A shut craps window is pending work for the next request, so a quiet table has to be
    ///      sealed and settled too: quiet the keeper's arm walk, then let ordinary requests land the
    ///      words that settle what it shut, until no window waits on the write buffer.
    function _quietCrapsTableAndRng(uint256 vrfWord) internal {
        _quietCrapsTable();
        for (uint256 i; i < 4; ++i) {
            uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
            if (packed & (uint256(1) << (250 + RecyclingState.writeBuffer(address(game)))) == 0) break;
            // A shut window waives the mid-day value gates, so the engine requests its word.
            game.mineFlip();
            uint256 reqId = mockVRF.lastRequestId();
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) mockVRF.fulfillRandomWords(reqId, vrfWord + i);
            _lastFulfilledReqId = reqId;
            _settleGame(vrfWord + i);
            _quietCrapsTable();
        }
    }

    // =========================================================================
    // Task 1 — D-02 one-category creditFlip COUNT across both branches + skip + NoWork
    // =========================================================================

    /// @notice ADVANCE branch: a new day's processing is ONE engine call composing many actions
    ///         (publish, tickets, the day's word, the daily phase, the read consumers), and it credits
    ///         the keeper EXACTLY ONCE. The one-category router is gone (60d31f775): the engine selects
    ///         one action at a time from storage and pays once per call, CEI-last, on the call's measured
    ///         gas above an unpaid first MIN_REWARDED_GAS (72fc06f6c). Composing actions therefore cannot
    ///         stack bounties.
    function testAdvanceBranchCreditsExactlyOnce() public {
        // Settle the deploy-day advance so we start from a clean, not-due, not-locked state.
        _settleGame(0xADADADAD0001);
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");

        // Drive `advanceDue()` true: roll the wall clock forward so the simulated day index moves ahead.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: advance is due");
        // The miner is paid at min(basefee, cap); Foundry's default basefee is 0.
        vm.fee(1 gwei);

        // The day's request is its own call: a request commits the next cohort and ends the call.
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory requestLogs = vm.getRecordedLogs();
        assertTrue(game.rngLocked(), "pre: the day's request took the daily lock");
        (, , uint256 requestReward) = _minerWork(requestLogs);
        assertEq(_countFor(requestLogs, keeper), requestReward == 0 ? 0 : 1, "request call: at most one credit");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xADADADAD0002);
        uint24 newDay = game.currentDayView();
        assertEq(game.rngWordForDay(newDay), 0, "pre: the new day's word is not yet applied");

        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (, uint256 measured, uint256 reward) = _minerWork(logs);
        emit log_named_uint("advance call measured gas", measured);
        emit log_named_uint("advance call bounty", reward);
        // Non-vacuity: the call really processed the day (publish, tickets, then the day's word
        // applied under the lock) and measured paid work.
        assertGt(game.rngWordForDay(newDay), 0, "non-vacuity: the advance call applied the new day's word");
        assertGt(measured, 1_000_000, "non-vacuity: the advance call measured past the unpaid first million");
        assertGt(reward, 0, "non-vacuity: the advance call earned a bounty");
        // The composed actions credited exactly once.
        assertEq(_countFor(logs, keeper), 1, "ADVANCE branch: exactly one mineFlip creditFlip to the keeper");
    }

    /// @notice GAMEOVER idle crank reverts: post-gameover the advance predicate stays true (dailyIdx
    ///         freezes) but the only remaining advance work is the one-time 30-day final sweep. With no
    ///         sweep pending (GO_TIME==0 here == the real within-30-day / already-swept states) mineFlip
    ///         reverts NoWork() rather than running the gameover advance leg as a free unrewarded no-op.
    ///         Zero creditFlip either way.
    function testGameoverIdleCrankRevertsNoWork() public {
        _settleGame(0x5C1F0001);
        assertFalse(game.advanceDue(), "pre: settled");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        // Latch gameOver; GO_TIME stays 0, so _finalSweepPending() is false — no sweep due.
        _latchGameOver();
        assertTrue(game.gameOver(), "pre: gameOver latched");

        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.recordLogs();
        vm.prank(keeper);
        vm.expectRevert(bytes4(keccak256("NoWork()"))); // no sweep pending, no free idle crank
        game.mineFlip();

        // ZERO creditFlips — the idle crank reverted before any bounty could pay.
        assertEq(_countCoinflipStakeUpdated(), 0, "GAMEOVER idle: zero creditFlip emissions on the NoWork revert");
    }

    /// @notice NoWork: BOTH O(1) predicates empty -> `mineFlip()` reverts `NoWork()` and credits
    ///         nothing. Advance not due + no afking boxes pending.
    function testNoWorkRevertsAndCreditsNothing() public {
        // Settle the deploy-day advance so advance is NOT due and we are not locked.
        _settleGame(uint256(keccak256("nowork-settle")));
        assertFalse(game.advanceDue(), "pre: settled (advance not due)");
        assertFalse(game.rngLocked(), "pre: settled (not locked)");
        // Mine any remaining read-cohort housekeeping (empty human-box frontiers included) so the
        // keeper's probe below meets a genuinely stationary engine.
        _mineAll(64);
        // No afking subscriber stamped a box (no STAGE buy was driven), so the open leg has nothing.

        // The crank has a craps arm now, and a shut window makes the next request real work, so a
        // NoWork probe has to quiet and settle the table too or it is asserting an idleness it
        // never set up.
        _quietCrapsTableAndRng(uint256(keccak256("nowork-craps")));
        assertFalse(game.advanceDue(), "pre: still not due after the table settled");
        vm.recordLogs();
        vm.prank(keeper);
        vm.expectRevert(); // GameAfkingModule.NoWork()
        game.mineFlip();

        // Nothing credited (the revert rolls back, but assert the count is zero regardless).
        assertEq(_countCoinflipStakeUpdated(), 0, "NoWork: zero creditFlip emissions on the empty-work revert");
    }

    // =========================================================================
    // Task 2 — D-01 structural reentrancy attest + D-03 the rewarded human box stage
    // =========================================================================

    /// @notice Pin the single engine dispatcher, its single CEI-last keeper-credit site, its trusted
    ///         worker targets, and the absence of ETH-push hooks. The v55 router functions in
    ///         GameAfkingModule (`_runWork`/`_runAdvance`/`_runRngConsumers`/`_creditWorkBounty`) are gone:
    ///         60d31f775 moved dispatch into DegenerusGameMinerModule.mineFlip, which reselects one action
    ///         from storage per iteration and credits once after the loop.
    function testMintFlipReentrancyStructurallySafeSourceAttest() public view {
        string memory miner = _stripComments(vm.readFile(MINER_SRC));
        string memory afking = _stripComments(vm.readFile(AFKING_SRC));
        string memory dispatch = _extractFunctionBody(miner, "function mineFlip() external {");
        assertGt(bytes(dispatch).length, 0, "D-01: shared dispatcher extracted");
        assertEq(_countOccurrences(dispatch, "for (uint256 transitions; transitions < 32; ++transitions) {"), 1, "one bounded dispatch loop");
        assertEq(_countOccurrences(dispatch, "MinerAction action = transitions == 0 ? first : _nextMinerAction(msg.sender);"), 1, "every dispatch reselects from storage");
        assertEq(_countOccurrences(dispatch, "coinflip.creditFlip(minerId, reward);"), 1, "single credit in the dispatcher");
        assertEq(_countOccurrences(miner, "creditFlip("), 1, "sole keeper-credit site in the engine");
        assertEq(_countOccurrences(afking, "creditFlip(minerId,"), 0, "the retired router credit site stays gone");
        assertEq(_countOccurrences(dispatch, "if (numerator >= (denominator - 1) / 1e18 + 1) {"), 1, "zero credit is skipped");
        // CEI-last: the credit follows the loop's exit check and the gas measurement.
        uint256 credit = _indexOf(dispatch, "coinflip.creditFlip(minerId, reward);");
        uint256 measured = _indexOf(dispatch, "uint256 used = rewardStart - gasleft() - unpaidAttemptGas;");
        uint256 loopExit = _indexOf(dispatch, "if (!moved) revert MineFlipGas.InsufficientExecutionGas();");
        assertGt(measured, loopExit, "gas is measured after every worker returned");
        assertGt(credit, measured, "the credit is the last external effect");
        // Every worker target is a pinned protocol address.
        assertGt(_countOccurrences(dispatch, "target = ContractAddresses."), 0, "worker targets present");
        assertEq(_countOccurrences(dispatch, "target = ContractAddresses."), _countOccurrences(dispatch, "target = "), "every worker target is a pinned protocol address");
        assertEq(_countOccurrences(dispatch, "target.call{gas: forwarded}(callData);"), 1, "one external worker call site");
        assertEq(_countOccurrences(dispatch, "target.delegatecall{gas: forwarded}(callData);"), 1, "one module delegatecall site");

        assertEq(_countOccurrences(miner, ".call{value:"), 0, "engine cannot push ETH");
        assertEq(_countOccurrences(miner, ".transfer("), 0, "engine cannot transfer ETH");
        assertEq(_countOccurrences(miner, ".send("), 0, "engine cannot send ETH");
        assertEq(_countOccurrences(afking, ".call{value:"), 0, "module cannot push ETH");
        assertEq(_countOccurrences(afking, ".transfer("), 0, "module cannot transfer ETH");
        assertEq(_countOccurrences(afking, ".send("), 0, "module cannot send ETH");
    }

    /// @notice REWARDED via mineFlip: once a delivered cohort's human boxes are the engine's next work
    ///         (the read-consumer HumanBoxes stage, 60d31f775), `mineFlip()` opens them and credits the
    ///         keeper EXACTLY ONCE, on the call's measured gas above the unpaid first MIN_REWARDED_GAS
    ///         (72fc06f6c). Enough distinct boxes are queued that the open measures past that million.
    function testMintFlipOpensHumanBoxAndPaysBounty() public {
        address[] memory owners = new address[](PAID_BOX_OWNERS);

        // Settle so the engine is idle and not locked.
        _settleGame(0x000F_1111);
        uint48 index = _activeLootboxIndex();
        for (uint256 i; i < PAID_BOX_OWNERS; ++i) {
            owners[i] = makeAddr(string.concat("mf_human_box_owner_", _u(i)));
            vm.deal(owners[i], 100_000 ether);
            _buyBox(owners[i], LOOTBOX_WEI);
        }
        // Finalize the boxes' index + land its word.
        _advanceLootboxRngIndexByOne();
        _injectLootboxRngWord(index, FIXED_WORD);
        for (uint256 i; i < PAID_BOX_OWNERS; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "pre: human box queued + un-opened");
        }
        assertTrue(game.boxesPending(), "pre: a human box is pending");
        assertEq(
            game.nextMinerAction(),
            uint8(DegenerusGameStorage.MinerAction.HumanBoxes),
            "pre: the delivered cohort's human boxes are the engine's next work"
        );
        assertFalse(game.rngLocked(), "pre: not locked (the human open leg runs)");
        vm.fee(1 gwei);

        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Every human box opened via mineFlip (first-deposit signal zeroed).
        for (uint256 i; i < PAID_BOX_OWNERS; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "non-vacuity: mineFlip's open leg opened the human box");
        }
        (, uint256 measured, uint256 reward) = _minerWork(logs);
        emit log_named_uint("human open call measured gas", measured);
        emit log_named_uint("human open call bounty", reward);
        assertGt(reward, 0, "the measured open work earned a bounty");
        // ...and the keeper earned EXACTLY ONE bounty (a box-owner winnings credit cannot inflate the
        // keeper-isolated count — only mineFlip credits the keeper).
        assertEq(_countFor(logs, keeper), 1, "REWARDED: mineFlip pays the keeper exactly once for opening a human box");
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

    /// @dev Recipient-isolated creditFlip count over already-captured logs: isolates the router
    ///      bounty (to the keeper) from a box-owner's winnings credit.
    function _countFor(Vm.Log[] memory logs, address who) internal view returns (uint256 count) {
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                logs[i].topics[1] == bytes32(uint256(game.walletIdOf(who)))
            ) count++;
        }
    }

    /// @dev The MinerWork(caller, firstAction, executionGas, flipReward) of a single mineFlip.
    function _minerWork(Vm.Log[] memory logs) internal view returns (uint8 first, uint256 measured, uint256 reward) {
        uint256 seen;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (first, measured, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "one MinerWork per mineFlip");
    }

    /// @dev Byte index of the first occurrence of `needle` (reverts if absent).
    function _indexOf(string memory haystack, string memory needle) private pure returns (uint256) {
        bytes memory hb = bytes(haystack);
        bytes memory n = bytes(needle);
        for (uint256 i; n.length != 0 && i + n.length <= hb.length; ++i) {
            bool matched = true;
            for (uint256 j; j < n.length; ++j) {
                if (hb[i + j] != n[j]) { matched = false; break; }
            }
            if (matched) return i;
        }
        revert(string.concat("needle not found: ", needle));
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
    ///      settle so mineFlip's subscription stage stamps the funded set + the day word lands.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Subscribe `who` as a self-funded LOOTBOX-mode sub (the afking box stamp path).
    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
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

    // ---- Sub field reads (_subOf slot 52 + verified offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    // ---- gameover latch ----

    /// @dev Latch the terminal gameOver public bool (byte 21 of SLOT 0) as a finished ending: the final
    ///      jackpot is paid (gameOverStatePacked slot 19, bit 48) and the gameover-time field stays 0, so
    ///      no 30-day sweep is due. Until the payout lands the engine still owes Terminal work
    ///      (60d31f775 selector), so an unpaid latch would not be idle.
    function _latchGameOver() internal {
        bytes32 slot = bytes32(uint256(0));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << (21 * 8));
        vm.store(address(game), slot, bytes32(packed));
        uint256 goState = uint256(vm.load(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED)));
        vm.store(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED), bytes32(goState | (uint256(1) << 48)));
        require(game.gameOver(), "_latchGameOver: gameOver did not flip (slot 0 byte 21)");
    }

    // ---- human box helpers ----

    /// @dev Buy a real human lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> the inlined boxPlayers push.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, BoxOrderLib.boCustomFloor(lootboxAmount), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 34).
    function _activeLootboxIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 35).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
    }

    /// @dev Fixture guard: a delivered word is present, so the box queued on the read buffer is
    ///      the cohort the human-box stage reads.
    function _advanceLootboxRngIndexByOne() internal {
        assertGt(RecyclingState.currentWord(address(game)), 1, "fixture delivered word");
    }

    /// @dev Nominal wei of `who`'s queue entries in `index`'s buffer that the human-box cursor has not
    ///      yet settled (zero once every one of them is opened). Entry positions are bounded by the
    ///      buffer's count (write count while accumulating, read count once sealed).
    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256 total) {
        uint256 n = RecyclingState.boxCount(address(game), index);
        uint256 cursor = (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8)) & type(uint48).max;
        bool sealed_ = index == RecyclingState.readBuffer(address(game));
        uint32 id = game.walletIdOf(who);
        for (uint256 i = sealed_ ? cursor : 0; i < n; ++i) {
            uint256 word = RecyclingState.boxEntry(address(game), index, i);
            if (BoxOrderLib.boId(word) != id) continue;
            total += BoxOrderLib.boNominal(word, PriceLookupLib.priceForLevel(BoxOrderLib.boLevel(word)));
        }
    }

    // ---- read-slot ticket seeding (force advanceDue via a non-empty current-level read slot) ----

    /// @dev Read the GAME's live ticketWriteSlot bool (SLOT 0 byte 25).
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((slot0 >> (25 * 8)) & 0x1) != 0;
    }

    /// @dev The current read key for a level — byte-faithful to DegenerusGameStorage._tqReadKey.
    function _readKey(uint24 lvl) internal view returns (uint24) {
        return !_ticketWriteSlot() ? (lvl | TICKET_SLOT_BIT) : lvl;
    }

    /// @dev Seed `whole` current-level tickets for `who` at the read key (packed: owed=whole*4 << 8 | rem)
    ///      and append `who` to ticketQueue[_ticketQueueStorageKey(readKey)], so advanceDue() sees a non-empty read slot.
    function _seedReadSlotTickets(uint24 readKey, address who, uint32 whole) internal {
        TicketQueueStorage.seed(address(game), readKey, readKey & ~TICKET_SLOT_BIT, who, uint80(whole) * 4 << 8);
    }

    /// @dev Set the ticketsFullyProcessed bool (SLOT 0 byte 24, golden layout), preserving the rest of slot 0.
    function _setTicketsFullyProcessed(bool v) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFF) << (24 * 8);
        slot0 &= ~mask;
        if (v) slot0 |= (uint256(1) << (24 * 8));
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
