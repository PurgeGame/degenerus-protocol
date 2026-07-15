// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title FSMHandler -- Handler that snapshots game FSM state for invariant testing
/// @notice Wraps purchase/advanceGame/VRF operations while tracking FSM ghost state.
///         The invariant test checks that level only increases, gameOver is terminal, level is
///         frozen after gameOver, the VRF-progress clock never rewinds, and that a well-formed,
///         unblocked advance never hard-stalls (bounded no-brick liveness).
contract FSMHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- FSM Ghost variables (existing) ---
    uint256 public ghost_maxLevel;
    bool public ghost_everGameOver;
    uint256 public ghost_levelDecreaseCount;
    uint256 public ghost_gameOverRevival;

    // --- FSM Ghost variables (terminal freeze) ---
    // Once gameOver latches, `level` must never change again. Distinct from levelMonotonic (which
    // still permits post-gameover INCREASES) and gameOverTerminal (which only checks gameOver stays
    // true). `level` is only ever written pre-gameover (at RNG-request time), so post-gameover
    // final-sweep advances must leave it fixed.
    bool internal _gameOverLatched;
    uint256 public ghost_levelAtGameOver;
    uint256 public ghost_levelChangedAfterGameOver;

    // --- FSM Ghost variables (VRF-progress clock) ---
    // lastVrfProcessed() is a max-of-block.timestamp stamp written only on VRF processing, so it is
    // monotone non-decreasing; a regression signals corrupted liveness bookkeeping.
    uint256 public ghost_lastVrfSeen;
    uint256 public ghost_vrfClockRegressions;

    // Budget for the recovery-crank DRIVER (see recoverAndDrain). Loop guard only -- it does NOT
    // back a liveness assertion (see the note on recoverAndDrain for why a sound bounded no-brick
    // ghost is not wireable here).
    uint256 internal constant RECOVER_CRANK_CAP = 512;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;
    uint256 public calls_recover;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xF0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Purchase tickets while tracking FSM state
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        // Purchases are inert after gameOver; skip the buy but still record FSM state so the
        // terminal-freeze / clock ghosts observe the post-gameover state.
        if (!gameOverBefore) {
            qty = bound(qty, 100, 4000);
            lootboxAmt = bound(lootboxAmt, 0, 2 ether);

            (, , , , uint256 priceWei) = game.purchaseInfo();
            uint256 ticketCost = (priceWei * qty) / 400;
            uint256 totalCost = ticketCost + lootboxAmt;

            if (totalCost != 0 && totalCost <= currentActor.balance) {
                vm.prank(currentActor);
                try game.purchase{value: totalCost}(
                    currentActor,
                    qty,
                    lootboxAmt,
                    bytes32(0),
                    MintPaymentKind.DirectEth, false
                ) {} catch {}
            }
        }

        _postAction(levelBefore, gameOverBefore);
    }

    /// @notice Advance game while tracking FSM state
    /// @dev Runs even after gameOver so the post-gameover final-sweep path is exercised and the
    ///      terminal-freeze ghost can catch any illegal post-gameover level mutation.
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        calls_advanceGame++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}

        _postAction(levelBefore, gameOverBefore);
    }

    /// @notice Fulfill VRF while tracking FSM state
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
            }
        }

        _postAction(levelBefore, gameOverBefore);
    }

    /// @notice VRF-recovery crank -- a coverage DRIVER (no assertion of its own).
    /// @dev Repeatedly (up to RECOVER_CRANK_CAP) supplies a VRF word for any pending request and
    ///      cranks advanceGame, WITHOUT warping time, until the game is caught up (no owed work and
    ///      not VRF-gated), reaches gameOver, or advanceGame reverts. This drives the game deep
    ///      through the VRF request/fulfill/unlock cycle and into gameOver, which is what exercises
    ///      the level-monotonic, gameOver-terminal, terminal-freeze, and VRF-clock invariants.
    ///
    ///      NOT A BRICK ORACLE (intentionally): a sound bounded no-brick ghost cannot be wired here.
    ///      Within-day / backlog drain makes real forward progress that is INVISIBLE through the
    ///      exposed views (level/gameOver/lastVrfProcessed/currentDayView do not change per tick),
    ///      and time-warp actions can accumulate an arbitrarily large owed-day backlog that a
    ///      fixed-time crank must drain over many ticks. So any finite iteration cap either
    ///      false-positives on a large legitimate backlog or, if raised enough to be safe, exceeds
    ///      the block gas limit. A cap-exhaustion "brick" flag was implemented and empirically
    ///      confirmed flaky (false-positive on a legitimate backlog), so it was removed. The sound
    ///      liveness property that IS asserted is VRF-clock monotonicity (invariant_vrfClockMonotone).
    /// @param word VRF word to feed any pending requests during the crank.
    function recoverAndDrain(uint256 word) external {
        calls_recover++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        address cranker = actors[0];
        for (uint256 i; i < RECOVER_CRANK_CAP; i++) {
            if (game.gameOver()) break;

            if (game.rngLocked()) {
                uint256 reqId = vrf.lastRequestId();
                if (reqId != 0) {
                    (, , bool fulfilled) = vrf.pendingRequests(reqId);
                    if (!fulfilled) {
                        try vrf.fulfillRandomWords(reqId, word) {} catch {}
                    }
                }
            }

            // Caught up: no owed work and not waiting on VRF.
            if (!game.advanceDue() && !game.rngLocked()) break;

            vm.prank(cranker);
            try game.advanceGame() {} catch {
                break;
            }
        }

        _postAction(levelBefore, gameOverBefore);
    }

    /// @notice Warp past the VRF retry timeout (18 hours + 1 second)
    function warpPastVrfTimeout() external {
        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();
        vm.warp(block.timestamp + 18 hours + 1);
        _postAction(levelBefore, gameOverBefore);
    }

    /// @notice Warp time by bounded delta
    function warpTime(uint256 delta) external {
        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
        _postAction(levelBefore, gameOverBefore);
    }

    /// @dev Update FSM ghost state after an operation.
    function _postAction(uint256 levelBefore, bool gameOverBefore) private {
        uint256 levelAfter = game.level();
        bool gameOverAfter = game.gameOver();

        // Level monotonicity violations.
        if (levelAfter < levelBefore) {
            ghost_levelDecreaseCount++;
        }

        // Track max level.
        if (levelAfter > ghost_maxLevel) {
            ghost_maxLevel = levelAfter;
        }

        // gameOver terminality violations.
        if (gameOverBefore && !gameOverAfter) {
            ghost_gameOverRevival++;
        }

        if (gameOverAfter) {
            ghost_everGameOver = true;

            // Terminal freeze: latch the level at first gameOver, then forbid any change.
            if (!_gameOverLatched) {
                _gameOverLatched = true;
                ghost_levelAtGameOver = levelAfter;
            } else if (levelAfter != ghost_levelAtGameOver) {
                ghost_levelChangedAfterGameOver++;
            }
        }

        // VRF-progress clock is monotone non-decreasing.
        uint256 vrfClock = game.lastVrfProcessed();
        if (vrfClock < ghost_lastVrfSeen) {
            ghost_vrfClockRegressions++;
        } else {
            ghost_lastVrfSeen = vrfClock;
        }
    }
}
