// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";

/// @title DegeneretteResolveRepeg -- sweep-budget invariance of queued-bet resolution.
/// @notice Bets are queued per RNG index (`degeneretteQueue[index & 1]`, id = queue position + 1) and
///         resolve ONLY through the permissionless in-order sweep (`game.mineFlip`, rewarded to the CALLER based on the walk-unit work actually done --
///         see KeeperFaucetResistance.t.sol and DegeneretteSweep.t.sol for that reward's own
///         faucet-safety and equivalence proofs), strictly in queue order. There is no per-id
///         door: the flat ~1-FLIP "loser" reward, the >=3-successful-resolutions gate,
///         `BatchAlreadyTaken`, and the zero-resolved `NoWork()` revert this file used to test all
///         belonged to the removed `game.degeneretteResolve(players, betIds)` keeper-crank helper
///         and have no replacement (confirmed absent from contracts/ by grep); the later
///         `resolveDegeneretteBets(index, betIds)` cherry-pick door that superseded it is also
///         gone, so a caller can no longer choose an arbitrary id list or its ordering -- only
///         how much budget one sweep call spends before the walk stops.
///
///         What remains meaningful here: the cross-bet payout accumulator
///         (`DegenerusGameDegeneretteModule.ResolveAcc`) sums ETH/FLIP per owner and flushes once
///         per owner-run, purely additively. This file proves that additivity end-to-end -- the
///         SAME set of queued bets must settle to byte-identical player balances whether one
///         full-budget sweep drains them all in a single call or several minimal-budget sweeps
///         drain them one at a time -- so a caller's choice of sweep-call budget can never move
///         value.
contract DegeneretteResolveRepeg is DeployProtocol {
    // =========================================================================
    // Storage slot constants (confirmed via `forge inspect ... storage`)
    // =========================================================================

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;
    /// @dev lootboxRngPacked; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    /// @dev prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    /// @dev claimablePool (uint128) lives in slot 1, byte 16 (high 128 bits).
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    /// @dev Mirrors DegenerusGameDegeneretteModule's private BET_SURVIVAL_TAG domain separator.
    uint256 private constant BET_SURVIVAL_TAG = 0x446567656e537572766976616c; // "DegenSurvival"

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("degen_resolve_player");
        vm.deal(player, 1000 ether);

        // Fund the game with ETH to back any pool / winning credit.
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet reverts with E() when lootboxRngIndex == 0; seed it to 1
        // (the word at index 1 starts at 0 = no pending RNG, the state bet placement needs).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }

    // =========================================================================
    // Sweep-budget invariance
    // =========================================================================

    /// @notice The player's total resolution deltas (ETH claimable / claimablePool / FLIP minted)
    ///         are byte-identical no matter how many mineFlip calls it takes to drain the same
    ///         queued bets: one unbounded call that drains all three, or three minimal-allowance
    ///         calls that each drain exactly one. Bets resolve only through
    ///         this permissionless FIFO sweep now (the manual per-id door that let a caller
    ///         choose an arbitrary id list, its ordering, or a third-party "automatic sweep vs
    ///         caller-driven call" distinction is gone -- every sweep call is the same entrypoint,
    ///         whoever sends it), so call-budget size is the only remaining degree of freedom
    ///         over how resolution gets split across transactions; this proves that freedom moves
    ///         nothing either (DegeneretteSweep.t.sol proves the single-bet and resume-across-
    ///         calls shapes of this same property; this file owns the full-sweep-vs-incremental
    ///         comparison).
    function testResolutionDeltasIndependentOfBatchPartitioning() public {
        _seedFuturePrizePool(1_000_000 ether);

        // Word chosen so the FLIP bet (betId 1) WINS its bet-keyed survival flip
        // (keccak(word, player, betId, BET_SURVIVAL_TAG) & 1 == 1) -- keeps the FLIP
        // non-vacuity assert live under every partitioning. The FLIP bet queues first: the
        // queue's declared per-bet admissions are then non-decreasing (FLIP below ETH), so a
        // minimal-allowance call that admits one bet can never also admit the next.
        uint48 index = 1;
        uint256 word = uint256(keccak256("repeg_partition_independence_v1"));
        while (uint256(keccak256(abi.encode(word, player, uint256(1), BET_SURVIVAL_TAG))) & 1 == 0) ++word;
        uint32 ticket = _winningTicketFor(index, word);

        _fundFlip(player, 1_000 ether);
        uint64 b1 = _placeBet(CURRENCY_FLIP, 200 ether, 2, ticket);
        uint64 b0 = _placeBet(CURRENCY_ETH, 0.01 ether, 2, ticket);
        uint64 b2 = _placeBet(CURRENCY_ETH, 0.01 ether, 2, ticket);

        _injectLootboxRngWord(index, word);

        uint256 preClaimable = game.claimableWinningsOf(player);
        uint256 preClaimablePool = _readClaimablePool();
        uint256 preFlip = coin.balanceOf(player);

        uint256 snap = vm.snapshotState();

        // --- A: all 3 bets drained by ONE unbounded mineFlip ---
        _advanceActiveIndexPast(index);
        _crank(type(uint256).max);

        uint256 claimableDeltaA = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDeltaA = _readClaimablePool() - preClaimablePool;
        uint256 flipDeltaA = coin.balanceOf(player) - preFlip;
        assertEq(game.degeneretteBetInfo(index, b0), 0, "Run A: bet 0 resolved");
        assertEq(game.degeneretteBetInfo(index, b1), 0, "Run A: bet 1 resolved");
        assertEq(game.degeneretteBetInfo(index, b2), 0, "Run A: bet 2 resolved");

        // --- B: revert, resolve the SAME 3 bets in THREE separate minimal-allowance calls ---
        // The walk-unit budget is now a gas allowance (60d31f775): each call gets the smallest
        // allowance that resolves any bet, so each drains exactly one bet in queue order.
        vm.revertToState(snap);
        _advanceActiveIndexPast(index);
        assertEq(_crankOneBet(), 1, "Run B call 1 resolves exactly one bet");
        assertEq(_crankOneBet(), 1, "Run B call 2 resolves exactly one bet");
        assertEq(_crankOneBet(), 1, "Run B call 3 resolves exactly one bet");

        uint256 claimableDeltaB = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDeltaB = _readClaimablePool() - preClaimablePool;
        uint256 flipDeltaB = coin.balanceOf(player) - preFlip;
        assertEq(game.degeneretteBetInfo(index, b0), 0, "Run B: bet 0 resolved");
        assertEq(game.degeneretteBetInfo(index, b1), 0, "Run B: bet 1 resolved");
        assertEq(game.degeneretteBetInfo(index, b2), 0, "Run B: bet 2 resolved");

        assertEq(claimableDeltaA, claimableDeltaB,
            "budget-invariant: ETH claimable delta identical, one full sweep vs three incremental sweeps");
        assertEq(claimablePoolDeltaA, claimablePoolDeltaB,
            "budget-invariant: claimablePool delta identical, one full sweep vs three incremental sweeps");
        assertEq(flipDeltaA, flipDeltaB,
            "budget-invariant: FLIP mint delta identical, one full sweep vs three incremental sweeps");

        // Non-vacuity: the resolutions actually paid SOMETHING (the equality is not 0 == 0).
        assertGt(claimableDeltaA, 0, "non-vacuity: the resolutions credited ETH claimable");
        assertGt(flipDeltaA, 0, "non-vacuity: the resolutions minted FLIP");
    }

    // =========================================================================
    // Bet placement / RNG helpers
    // =========================================================================

    /// @dev Place a Degenerette bet for `player` and return its betId (queue position + 1).
    function _placeBet(uint8 currency, uint128 perTicket, uint8 spins, uint32 ticket)
        internal
        returns (uint64 betId)
    {
        uint256 ethValue = currency == CURRENCY_ETH ? uint256(perTicket) * spins : 0;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(address(0), currency, perTicket, spins, uint8(ticket & 7));
        betId = DQ.lastBetId(vm, address(game), 1);
    }

    /// @dev The spin-0 winning custom ticket for (index, word): the spin-0 result ticket itself
    ///      (8/8 self-match guarantees a win on spin 0 -> the resolution actually pays).
    function _winningTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        return _resultTicketForSpin(index, word, 0);
    }

    /// @dev Reproduce the on-chain per-spin result ticket (_resolveBet derivation).
    function _resultTicketForSpin(uint48 index, uint256 word, uint8 spinIdx)
        internal
        pure
        returns (uint32)
    {
        uint256 resultSeed = spinIdx == 0
            ? uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)))
            : uint256(keccak256(abi.encodePacked(word, uint32(index), spinIdx, QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev Inject a lootbox RNG word for a given index (lootboxRngWordByIndex mapping).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
        // The day itself is sealed (dailyIdx = today, tickets drained), as after a mid-day request:
        // the delivered cohort's read consumers are the engine's only work.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Bets resolve only as the engine's Degenerette read consumer (mineFlip). Returns the bets this call resolved.
    function _crank(uint256 allowance) internal returns (uint256 resolved) {
        vm.recordLogs();
        vm.prank(makeAddr("degen_resolve_crank"));
        if (allowance == type(uint256).max) game.mineFlip();
        else game.mineFlip{gas: allowance}();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == DQ.RESOLVED_SIG) ++resolved;
    }

    /// @dev One mineFlip given the smallest allowance that still resolves a bet (bisection over
    ///      snapshots): the engine admits a bet only while the remaining allowance covers its
    ///      declared bound.
    function _crankOneBet() internal returns (uint256) {
        uint256 lo = 300_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.prank(makeAddr("degen_resolve_crank"));
            vm.recordLogs();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            uint256 n;
            if (ok) {
                Vm.Log[] memory logs = vm.getRecordedLogs();
                for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == DQ.RESOLVED_SIG) ++n;
            }
            vm.revertToStateAndDelete(snap);
            if (n != 0) hi = mid;
            else lo = mid;
        }
        return _crank(hi);
    }

    /// @dev Move the active lootbox RNG index (low 48 bits of lootboxRngPacked) to `idx + 1`, the
    ///      state the human-box sweep needs before it will reach `idx`'s bet queue.
    function _advanceActiveIndexPast(uint48 idx) internal {
        RecyclingState.seedWriteBuffer(address(game), idx ^ 1);
    }

    /// @dev Seed futurePrizePool (future half, bits 128-255 of prizePoolsPacked, slot 2). Preserves nextPrizePool.
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @dev Read claimablePool (uint128 in slot 1, byte 16 -> high 128 bits).
    function _readClaimablePool() internal view returns (uint256) {
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return uint256(uint128(s1 >> 128));
    }

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame (keeps supply consistent).
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }
}
