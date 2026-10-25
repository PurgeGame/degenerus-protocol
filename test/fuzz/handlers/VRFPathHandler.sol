// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusAdmin} from "../../../contracts/DegenerusAdmin.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";

/// @title VRFPathHandler -- Invariant handler for VRF path lifecycle testing
/// @notice Wraps purchase/mineFlip/VRF/coordinatorSwap/warp operations while
///         tracking ghost variables for TEST-01 (lootbox index lifecycle),
///         TEST-02 (stall-to-recovery state machine), and TEST-03 (sequential logical-day commitment).
contract VRFPathHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    DegenerusAdmin public admin;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    // --- Ghost variables: TEST-01 (lootbox buffer lifecycle) ---
    // Two physical buffers (6d0e64b09): the "index" is the write-buffer selector (0/1). It flips
    // exactly once per committed request and never elsewhere; ghost_expectedIndex mirrors it.
    uint48 public ghost_expectedIndex;
    uint256 public ghost_freshRequests;
    uint48 internal recoveryFrom;
    uint256 public ghost_indexSkipViolations;
    uint256 public ghost_doubleIncrementCount;
    uint256 public ghost_orphanedIndices;

    // --- Ghost variables: TEST-02 (stall-to-recovery state machine) ---
    uint256 public ghost_stallCount;
    uint256 public ghost_recoveryCount;
    uint256 public ghost_stateViolations;
    bool public ghost_swapPending;
    bool public ghost_livenessLatched;

    // --- Ghost variables: TEST-03 (sequential logical-day commitment) ---
    uint256 public ghost_maxResetDelay;
    uint256 public ghost_logicalDayViolations;
    uint48 public ghost_dayBeforeSwap;

    // --- Non-vacuity: successes ---
    uint256 public ghost_purchases;
    uint256 public ghost_advances;
    uint256 public ghost_fulfillments;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;
    uint256 public calls_coordinatorSwap;
    uint256 public calls_requestMidday;
    uint256 public calls_warpTime;

    /// @dev Read lootboxRngIndex directly from storage slot 34 (low 48 bits of lootboxRngPacked)
    ///      (post V62 lootbox repack: was 35).
    function _lootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @notice Current lootboxRngIndex read from game storage, for invariant assertions
    ///         against ghost_expectedIndex.
    function actualLootboxRngIndex() external view returns (uint48) {
        return _lootboxRngIndex();
    }

    /// @dev Read dailyIdx from storage slot 0 (uint24 at byte offset 3 = bits 24-47).
    function _dailyIdx() internal view returns (uint48) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint48(uint24(raw >> 24));
    }

    /// @dev Read _lootboxWord(index) from storage (mapping at slot 34, post V62 repack: was 36).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev The game's own liveness trigger. Once true at an mineFlip entry, that advance routes
    ///      into the terminal flow, which by design does not backfill gap days.
    function _livenessMirror() internal view returns (bool) {
        return game.livenessTriggered();
    }

    /// @dev A request is in flight with no word yet (active bit, rngWordCurrent == WAITING).
    function _unansweredRequest() internal view returns (bool) {
        return uint256(vm.load(address(game), bytes32(0))) & (uint256(1) << 254) != 0
            && RecyclingState.currentWord(address(game)) == 0;
    }

    function _coinflipSettled(uint24 day) internal view returns (bool) {
        (bool ok, bytes memory data) = ContractAddresses.COINFLIP.staticcall(
            abi.encodeWithSignature("getCoinflipDayResult(uint24)", day)
        );
        if (!ok) return false;
        (uint16 rewardPercent, bool win) = abi.decode(data, (uint16, bool));
        return rewardPercent != 0 || win;
    }

    /// @dev Account one observed call for the buffer lifecycle: at most one committed request
    ///      per call, the selector flips iff a request was committed, and a fresh request never
    ///      seals while the previous request is still unanswered.
    function _noteRequests(uint48 indexBefore, uint256 reqBefore, bool unansweredBefore) internal {
        uint256 reqs = vrf.lastRequestId() - reqBefore;
        uint48 indexAfter = _lootboxRngIndex();
        if (reqs > 1) ghost_doubleIncrementCount++;
        bool flipped = indexAfter != indexBefore;
        if (flipped) {
            ghost_freshRequests++;
            ghost_expectedIndex ^= 1;
            if (reqs == 0) ghost_indexSkipViolations++;
            if (unansweredBefore) ghost_orphanedIndices++;
        }
    }

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        MockVRFCoordinator vrf_,
        DegenerusAdmin admin_,
        uint256 numActors
    ) {
        game = game_;
        vrf = vrf_;
        admin = admin_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xF0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
        ghost_expectedIndex = _lootboxRngIndex();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Handler Actions (7 fuzzer-callable functions)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Purchase tickets while tracking VRF path state
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 4000);
        lootboxAmt = bound(lootboxAmt, 0, 2 ether);

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 ticketCost = (priceWei * qty) / 400;
        uint256 totalCost = ticketCost + lootboxAmt;

        if (totalCost == 0 || totalCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: totalCost}(
            0,
            qty,
            BoxOrderLib.boCustomFloor(lootboxAmt),
            bytes32(0),
            MintPaymentKind.DirectEth, false
        ) {
            ghost_purchases++;
        } catch {
            return;
        }
    }

    /// @notice Advance game while tracking index lifecycle and recovery state
    function mineFlip() external {
        calls_advanceGame++;

        if (game.gameOver()) return;

        uint48 indexBefore = _lootboxRngIndex();
        uint256 reqBefore = vrf.lastRequestId();
        bool unansweredBefore = _unansweredRequest();
        // Capture dailyIdx BEFORE mineFlip updates it — the gap start reference.
        uint48 dailyIdxBefore = _dailyIdx();
        // Latch liveness at entry: an advance that runs while the trigger holds routes into the
        // terminal flow (gap backfill not owed from then on).
        if (_livenessMirror()) ghost_livenessLatched = true;

        try game.mineFlip(0) {} catch {
            return;
        }
        ghost_advances++;

        // TEST-01: one committed request per call at most, flips only on a request.
        _noteRequests(indexBefore, reqBefore, unansweredBefore);

        // Normal index increments only for one fresh request; no missed reset creates a round.
        uint48 dailyIdxAfter = _dailyIdx();
        if (dailyIdxAfter < dailyIdxBefore || dailyIdxAfter > dailyIdxBefore + 1) ++ghost_logicalDayViolations;
        uint24 mirrored = uint24(uint256(vm.load(ContractAddresses.COINFLIP, bytes32(uint256(4)))) >> 176);
        if (mirrored != dailyIdxAfter) ++ghost_logicalDayViolations;
        if (ghost_swapPending && ghost_livenessLatched) {
            ghost_swapPending = false;
            recoveryFrom = 0;
        }
        if (ghost_swapPending && !game.gameOver() && _coinflipSettled(uint24(ghost_dayBeforeSwap))) {
            uint256 elapsedResets = game.currentWallDayView() > ghost_dayBeforeSwap
                ? game.currentWallDayView() - ghost_dayBeforeSwap : 0;
            if (elapsedResets > ghost_maxResetDelay) ghost_maxResetDelay = elapsedResets;
            ghost_swapPending = false;
            ++ghost_recoveryCount;
        }
        // Clear swap flag if game ended (no recovery possible)
        if (ghost_swapPending && game.gameOver()) {
            ghost_swapPending = false;
            recoveryFrom = 0;
        }
    }

    /// @notice Fulfill pending VRF request with fuzzed random word
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        uint48 indexBefore = _lootboxRngIndex();

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {
            return;
        }
        ghost_fulfillments++;

        uint48 indexAfter = _lootboxRngIndex();

        // TEST-01: fulfillment words the pending index (daily: staged in rngWordCurrent;
        // mid-day: written to lootboxRngWordByIndex directly) but never allocates —
        // only a fresh request advances lootboxRngIndex.
        if (indexAfter != indexBefore) {
            ghost_indexSkipViolations++;
        }
    }

    /// @notice Request mid-day lootbox RNG through mineFlip, its only door, while tracking the
    ///         index lifecycle. Mines only when the request is the engine's next action, so the
    ///         call is the request alone.
    function requestMidday() external {
        calls_requestMidday++;

        if (game.gameOver() || game.rngLocked()) return;
        if (game.nextMinerAction() != 17) return;

        uint48 indexBefore = _lootboxRngIndex();
        uint256 reqBefore = vrf.lastRequestId();
        bool unansweredBefore = _unansweredRequest();

        try game.mineFlip(0) {} catch {
            return;
        }

        // TEST-01: same accounting as mineFlip.
        _noteRequests(indexBefore, reqBefore, unansweredBefore);
    }

    /// @notice Perform coordinator swap and track stall-to-recovery state
    function coordinatorSwap() external {
        calls_coordinatorSwap++;

        if (game.gameOver()) return;

        ghost_dayBeforeSwap = game.currentDayView_g542950();
        bool lockedBefore = game.rngLocked();
        uint48 indexBefore = _lootboxRngIndex();

        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));

        vm.prank(address(admin));
        try game.updateVrfCoordinatorAndSub(
            address(newVRF),
            newSubId,
            bytes32(uint256(1)), 300_000
        ) {} catch {
            return;
        }

        vrf = newVRF;
        ghost_stallCount++;
        ghost_swapPending = true;

        // TEST-02: the swap re-points config and re-issues any in-flight request but
        // never flips the lock in either direction — a daily request in flight keeps
        // rngLocked=true until the re-issued word lands (freeze discipline: unlocking
        // early would open a player-action window inside the commitment span), and an
        // idle or mid-day-only state keeps rngLocked=false.
        if (game.rngLocked() != lockedBefore) {
            ghost_stateViolations++;
        }

        // TEST-01: a swap re-issues any in-flight request as a retry; retries never
        // advance lootboxRngIndex.
        if (_lootboxRngIndex() != indexBefore) {
            ghost_indexSkipViolations++;
        }
    }

    /// @notice Warp time by bounded delta
    function warpTime(uint256 delta) external {
        calls_warpTime++;
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
    }

    /// @notice Warp past VRF timeout (12h + 1h buffer)
    function warpPastTimeout() external {
        vm.warp(block.timestamp + 13 hours);
    }
}
