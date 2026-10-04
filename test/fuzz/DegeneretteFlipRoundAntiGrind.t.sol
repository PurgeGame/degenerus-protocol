// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @title DegeneretteFlipRoundAntiGrind — the 100-FLIP collapse is fixed at VRF fulfillment,
///        not at settle time, however many bets a sweep call happens to flush together.
///
/// @notice Bets queued at an index resolve only through the permissionless FIFO sweep
///         (`openBoxes`/`mineFlip`), which drains the queue in order and groups however many
///         bets fit one call's walk-unit budget into a single `acc.flipMint` flush. That
///         grouping is the one real grind this design has to defend against:
///
///           If the 100-FLIP collapse ran on the SUMMED `acc.flipMint` at the flush, a caller
///           could pick a budget that groups bets against the ALREADY-COMMITTED VRF word so the
///           remainder rounds up most often — a free, repeatable edge worth up to ~100 FLIP per
///           bet, available to anyone, on bets they do not even own.
///
///         The defence is that the collapse runs PER BET on a `betId`-keyed word
///         (`EntropyLib.hash4(rngWord, player, betId, FLIP_ROUND_TAG)`), so the outcome of every bet is
///         determined the moment the VRF word lands and how many bets one call's budget happens
///         to flush together is a pure no-op on value.
///
/// @notice This file proves that BEHAVIOURALLY, not structurally: the same queued bets, against
///         the same injected word, must mint the IDENTICAL total FLIP whether one full-budget
///         sweep drains the whole queue in a single flush or a sequence of minimal-budget sweeps
///         drains it across many smaller flushes. (The sweep is strictly FIFO and permissionless
///         over the whole queue, not a caller-chosen id list, so call-budget size is the only
///         remaining degree of freedom over flush grouping — an exhaustive arbitrary-subset
///         partition search is no longer constructible and would in any case be redundant with
///         this comparison, since per-bet independence here already implies invariance to any
///         grouping.) The structural companion (the absence of any `FlipRoundLib` reference at
///         the flush) lives in `test/stat/FlipHundredsInvariant.test.js` [04a]; this file is the
///         one that fails if the "simplify it later — just round once at the flush" refactor is
///         ever made.
///
/// @dev Scaffold (setUp, slot constants, bet placement, RNG injection) is a faithful copy of
///      `DegeneretteResolveRepeg.t.sol`, which in turn copies `DegeneretteFreezeResolution.t.sol`.
///      CROSS-CITE: .planning/PLAN-FLIP-ROUND-HUNDREDS.md §4.
contract DegeneretteFlipRoundAntiGrind is DeployProtocol {
    // =========================================================================
    // Storage slot constants (confirmed via `forge inspect ... storage`)
    // =========================================================================

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;
    /// @dev lootboxRngPacked; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    /// @dev prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    /// @dev Degenerette bet currencies (DegeneretteModule).
    uint8 private constant CURRENCY_FLIP = 1;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    /// @dev Enough bets that a partition search would have real freedom, few enough that
    ///      the one-per-tx leg stays cheap.
    uint256 private constant BET_COUNT = 6;

    /// @dev Per-spin stake well above `MIN_BET_FLIP` (100 FLIP), so a winning bet's payout
    ///      clears `FLIP_ROUND_THRESHOLD` and the collapse actually engages. A stake at the
    ///      minimum would sit under the threshold and only be floored, making the test vacuous.
    uint128 private constant FLIP_PER_SPIN = 5_000 ether;
    uint8 private constant SPINS = 3;

    address private player;
    address private keeper;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("flip_round_grind_player");
        vm.deal(player, 1000 ether);
        keeper = makeAddr("flip_round_grind_keeper");

        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet reverts with E() when lootboxRngIndex == 0; seed it to 1.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );

        _seedFuturePrizePool(1_000_000 ether);
    }

    // =========================================================================
    // The anti-grind property
    // =========================================================================

    /// @notice One full-budget sweep and a sequence of minimal-budget sweeps over the same
    ///         queued bets must mint the same total FLIP. Any collapse applied to a per-call
    ///         flush aggregate instead of the per-bet word would break this, because the
    ///         remainder being rounded would differ between a one-call flush and a many-call one.
    function testSweepCallGroupingCannotMoveTheFlipTotal() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("flip-round-anti-grind"));

        _placeWinningFlipBets(index, word);
        _injectLootboxRngWord(index, word);
        _advanceActiveIndexPast(index);

        // Leg A — the whole queue drained by one full-budget sweep call.
        uint256 snap = vm.snapshotState();
        uint256 batchTotal = _sweepAndMeasure(type(uint256).max);
        vm.revertToState(snap);

        // Leg B — the same queue drained by a sequence of minimal-budget sweep calls. If the
        // collapse keyed on the per-call flush instead of the bet, this leg would round however
        // many separate remainders the call grouping happens to produce instead of one summed
        // remainder, and the totals would diverge.
        snap = vm.snapshotState();
        uint256 incrementalTotal;
        uint256 nonZeroMints;
        uint256 calls;
        while (!game.boxIndexComplete(index)) {
            // Each call gets the smallest gas allowance that resolves any bet (the walk-unit
            // budget became a gas allowance in 60d31f775), so each flush groups exactly one bet.
            uint256 minted = _sweepAndMeasure(0);
            if (minted != 0) {
                ++nonZeroMints;
                // Every surviving payout here clears the threshold, so any per-call flush,
                // whether it grouped one bet or several, must land on a whole 100-FLIP multiple.
                assertEq(
                    minted % FlipRoundLib.FLIP_ROUND_UNIT,
                    0,
                    "a sweep-call FLIP mint is not a whole 100-FLIP multiple"
                );
            }
            incrementalTotal += minted;
            ++calls;
            require(calls < 20, "sweep stalled");
        }
        vm.revertToState(snap);

        // Non-vacuity: the survival flip must have left something to round, and the
        // minimal-budget leg must actually have taken more than one call, or "call grouping
        // cannot move the total" is trivially true.
        assertGt(batchTotal, 0, "no FLIP was minted - the fixture pays nothing");
        assertGt(calls, 1, "the minimal-budget sweep never actually split across calls");
        assertGe(nonZeroMints, 1, "no sweep call paid - there is nothing to compare");

        assertEq(
            batchTotal,
            incrementalTotal,
            "settling across many minimal-budget sweeps paid a different total than one full sweep: the collapse is keyed on the CALL GROUPING, not the bet"
        );
        assertEq(
            batchTotal % FlipRoundLib.FLIP_ROUND_UNIT,
            0,
            "the summed mint is not a whole 100-FLIP multiple"
        );
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Place `BET_COUNT` FLIP bets that all self-match on spin 0 (so they win and have a
    ///      payout to round), funded up front.
    function _placeWinningFlipBets(uint48 index, uint256 word) internal {
        _fundFlip(
            player,
            uint256(FLIP_PER_SPIN) * SPINS * BET_COUNT + 1 ether
        );
        uint32 ticket = _winningTicketFor(index, word);

        for (uint256 i; i < BET_COUNT; i++) {
            _placeBet(CURRENCY_FLIP, FLIP_PER_SPIN, SPINS, ticket);
        }
    }

    /// @dev Move the active lootbox RNG index (low 48 bits of lootboxRngPacked) to `idx + 1`, the
    ///      state the human-box sweep needs before it will reach `idx`'s bet queue.
    function _advanceActiveIndexPast(uint48 idx) internal {
        RecyclingState.seedWriteBuffer(address(game), idx ^ 1);
    }

    /// @dev Sweep index 1 with `budget` from the keeper and return the FLIP minted to `player`.
    ///      Resolution is permissionless and only ever credits the bet owner, so the keeper
    ///      needs no approval.
    ///      Bets resolve only as the engine's Degenerette read consumer (mineFlip). `budget` is
    ///      max for one unbounded call, or 0 for the smallest allowance that resolves any bet.
    function _sweepAndMeasure(uint256 budget) internal returns (uint256 minted) {
        uint256 before = coin.balanceOf(player);
        uint256 allowance = budget == type(uint256).max ? 0 : _minimalAllowance();
        vm.prank(keeper);
        if (allowance == 0) game.mineFlip();
        else game.mineFlip{gas: allowance}();
        minted = coin.balanceOf(player) - before;
    }

    /// @dev The smallest mineFlip allowance that resolves a bet, by bisection over snapshots: the
    ///      engine admits a bet only while the remaining allowance covers its declared bound.
    function _minimalAllowance() internal returns (uint256) {
        bytes32 resolvedSig = keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");
        uint256 lo = 300_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            vm.prank(keeper);
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            bool resolved;
            if (ok) {
                Vm.Log[] memory logs = vm.getRecordedLogs();
                for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == resolvedSig) resolved = true;
            }
            vm.revertToStateAndDelete(snap);
            if (resolved) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    /// @dev Place a Degenerette bet for `player` and return its id within the index queue.
    function _placeBet(
        uint8 currency,
        uint128 perTicket,
        uint8 spins,
        uint32 ticket
    ) internal returns (uint64 betId) {
        vm.recordLogs();
        vm.prank(player);
        game.placeDegeneretteBet(address(0), currency, perTicket, spins, uint8(ticket & 7));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)")) {
                return uint64(uint256(logs[i].topics[3]));
            }
        }
        revert("bet not placed");
    }

    /// @dev The spin-0 winning custom ticket for (index, word): the spin-0 result ticket itself
    ///      (8/8 self-match guarantees a win on spin 0 -> the resolution actually pays).
    function _winningTicketFor(uint48 index, uint256 word)
        internal
        pure
        returns (uint32)
    {
        return _resultTicketForSpin(index, word, 0);
    }

    /// @dev Reproduce the on-chain per-spin result ticket (`_resolveBet` derivation).
    ///      Byte-faithful copy of `DegeneretteResolveRepeg.t.sol` so the fixtures stay in lockstep.
    function _resultTicketForSpin(
        uint48 index,
        uint256 word,
        uint8 spinIdx
    ) internal pure returns (uint32) {
        uint256 resultSeed = spinIdx == 0
            ? uint256(
                keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT))
            )
            : uint256(
                keccak256(
                    abi.encodePacked(
                        word,
                        uint32(index),
                        spinIdx,
                        QUICK_PLAY_SALT
                    )
                )
            );
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        RecyclingState.seedWord(address(game), index, bytes32(rngWord));
        // The day itself is sealed (dailyIdx = today, tickets drained), as after a mid-day request:
        // the delivered cohort's read consumers are the engine's only work.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        uint256 newPacked = (currentPacked &
            ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32(newPacked)
        );
    }

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame (keeps supply consistent).
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }
}
