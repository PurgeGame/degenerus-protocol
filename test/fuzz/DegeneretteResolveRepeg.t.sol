// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";

/// @title DegeneretteResolveRepeg -- batch-partitioning invariance of queued-bet resolution.
/// @notice Bets are queued per RNG index (`degeneretteQueue[index]`, id = queue position + 1).
///         `resolveDegeneretteBets(index, betIds)` is PERMISSIONLESS and pays NO keeper reward
///         of any kind -- the flat ~1-FLIP "loser" reward, the >=3-successful-resolutions gate,
///         `BatchAlreadyTaken`, and the zero-resolved `NoWork()` revert this file used to test
///         all belonged to the removed `game.degeneretteResolve(players, betIds)` keeper-crank
///         helper and have no replacement (confirmed absent from contracts/ by grep). Unresolved
///         bets settle automatically once their index's box entries clear, via the human-box
///         sweep (`game.openBoxes`, unrewarded, or `game.mineFlip`, rewarded to the CALLER based
///         on the walk-unit work actually done -- see KeeperFaucetResistance.t.sol and
///         DegeneretteSweep.t.sol for that reward's own faucet-safety and equivalence proofs).
///
///         What remains meaningful here: the cross-bet payout accumulator
///         (`DegenerusGameDegeneretteModule.ResolveAcc`) sums ETH/FLIP per owner and flushes once
///         per owner-run, purely additively. This file proves that additivity end-to-end -- the
///         SAME set of queued bets must settle to byte-identical player balances whether resolved
///         in one `resolveDegeneretteBets` call, across several separate calls, or picked up by
///         the automatic sweep -- so a caller's choice of batch partitioning (or a caller simply
///         never showing up, leaving the sweep to do it) can never move value.
contract DegeneretteResolveRepeg is DeployProtocol {
    // =========================================================================
    // Storage slot constants (confirmed via `forge inspect ... storage`)
    // =========================================================================

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;
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
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }

    // =========================================================================
    // Batch-partitioning invariance
    // =========================================================================

    /// @notice The player's total resolution deltas (ETH claimable / claimablePool / FLIP minted)
    ///         are byte-identical no matter how a caller partitions or delivers the same set of
    ///         queued bets: one `resolveDegeneretteBets` call for all three, three separate
    ///         single-bet calls, or the automatic `openBoxes` sweep never called by the player at
    ///         all. Also proves the sweep result matches hand resolution exactly for a mixed
    ///         ETH/FLIP batch (DegeneretteSweep.t.sol proves the single-bet and resume-across-
    ///         calls shapes of this same property; this file owns the batch-partitioning angle).
    function testResolutionDeltasIndependentOfBatchPartitioning() public {
        _seedFuturePrizePool(1_000_000 ether);

        // Word chosen so the FLIP bet (betId 2) WINS its bet-keyed survival flip
        // (keccak(word, player, betId, BET_SURVIVAL_TAG) & 1 == 1) -- keeps the FLIP
        // non-vacuity assert live under every partitioning.
        uint48 index = 1;
        uint256 word = uint256(keccak256("repeg_partition_independence_v1"));
        while (uint256(keccak256(abi.encode(word, player, uint256(2), BET_SURVIVAL_TAG))) & 1 == 0) ++word;
        uint32 ticket = _winningTicketFor(index, word);

        _fundFlip(player, 1_000 ether);
        uint64 b0 = _placeBet(CURRENCY_ETH, 0.01 ether, 2, ticket);
        uint64 b1 = _placeBet(CURRENCY_FLIP, 200 ether, 2, ticket);
        uint64 b2 = _placeBet(CURRENCY_ETH, 0.01 ether, 2, ticket);

        _injectLootboxRngWord(index, word);

        uint256 preClaimable = game.claimableWinningsOf(player);
        uint256 preClaimablePool = _readClaimablePool();
        uint256 preFlip = coin.balanceOf(player);

        uint256 snap = vm.snapshotState();

        // --- A: all 3 bets in ONE resolveDegeneretteBets call ---
        uint64[] memory allIds = new uint64[](3);
        allIds[0] = b0;
        allIds[1] = b1;
        allIds[2] = b2;
        game.resolveDegeneretteBets(index, allIds);

        uint256 claimableDeltaA = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDeltaA = _readClaimablePool() - preClaimablePool;
        uint256 flipDeltaA = coin.balanceOf(player) - preFlip;
        assertEq(game.degeneretteBetInfo(index, b0), 0, "Run A: bet 0 resolved");
        assertEq(game.degeneretteBetInfo(index, b1), 0, "Run A: bet 1 resolved");
        assertEq(game.degeneretteBetInfo(index, b2), 0, "Run A: bet 2 resolved");

        // --- B: revert, resolve the SAME 3 bets in THREE separate single-bet calls ---
        vm.revertToState(snap);
        uint64[] memory one = new uint64[](1);
        one[0] = b0;
        game.resolveDegeneretteBets(index, one);
        one[0] = b1;
        game.resolveDegeneretteBets(index, one);
        one[0] = b2;
        game.resolveDegeneretteBets(index, one);

        uint256 claimableDeltaB = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDeltaB = _readClaimablePool() - preClaimablePool;
        uint256 flipDeltaB = coin.balanceOf(player) - preFlip;

        // --- C: revert, resolve the SAME 3 bets via the automatic sweep (no caller-driven
        // resolveDegeneretteBets call at all) ---
        vm.revertToState(snap);
        _advanceActiveIndexPast(index);
        game.openBoxes(type(uint256).max);

        uint256 claimableDeltaC = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDeltaC = _readClaimablePool() - preClaimablePool;
        uint256 flipDeltaC = coin.balanceOf(player) - preFlip;
        assertEq(game.degeneretteBetInfo(index, b0), 0, "Run C: sweep resolved bet 0");
        assertEq(game.degeneretteBetInfo(index, b1), 0, "Run C: sweep resolved bet 1");
        assertEq(game.degeneretteBetInfo(index, b2), 0, "Run C: sweep resolved bet 2");

        assertEq(claimableDeltaA, claimableDeltaB,
            "batch-invariant: ETH claimable delta identical, one call vs three separate calls");
        assertEq(claimableDeltaA, claimableDeltaC,
            "batch-invariant: ETH claimable delta identical, one call vs the automatic sweep");
        assertEq(claimablePoolDeltaA, claimablePoolDeltaB,
            "batch-invariant: claimablePool delta identical, one call vs three separate calls");
        assertEq(claimablePoolDeltaA, claimablePoolDeltaC,
            "batch-invariant: claimablePool delta identical, one call vs the automatic sweep");
        assertEq(flipDeltaA, flipDeltaB,
            "batch-invariant: FLIP mint delta identical, one call vs three separate calls");
        assertEq(flipDeltaA, flipDeltaC,
            "batch-invariant: FLIP mint delta identical, one call vs the automatic sweep");

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
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Move the active lootbox RNG index (low 48 bits of lootboxRngPacked) to `idx + 1`, the
    ///      state the human-box sweep needs before it will reach `idx`'s bet queue.
    function _advanceActiveIndexPast(uint48 idx) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | (uint256(idx) + 1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(packed));
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
