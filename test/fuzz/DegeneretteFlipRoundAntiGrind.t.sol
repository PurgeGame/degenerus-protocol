// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @title DegeneretteFlipRoundAntiGrind — the 100-FLIP collapse is fixed at VRF fulfillment,
///        not at settle time, however the caller composes the batch.
///
/// @notice `resolveDegeneretteBets(address player, uint64[] betIds)` is PERMISSIONLESS and takes
///         a CALLER-CHOSEN `betIds[]` array. The per-bet FLIP payouts sum into one `acc.flipMint`
///         and mint in a single flush. That combination is the one real grind this design has to
///         defend against:
///
///           If the 100-FLIP collapse ran on the SUMMED `acc.flipMint` at the flush, a settler
///           could enumerate batch partitions off-chain against the ALREADY-COMMITTED VRF word,
///           and pick the split whose remainders round up most often — a free, repeatable edge
///           worth up to ~100 FLIP per bet, available to anyone, on bets they do not even own.
///
///         The defence is that the collapse runs PER BET on a `betId`-keyed word
///         (`EntropyLib.hash2(rngWord, betId ^ FLIP_ROUND_TAG)`), so the outcome of every bet is
///         determined the moment the VRF word lands and batching is a pure no-op on value.
///
/// @notice This file proves that BEHAVIOURALLY, not structurally: the same set of bets, against
///         the same injected word, must mint the IDENTICAL total FLIP whether they are settled
///         one-per-transaction, all in one batch, or in one batch in reverse order. The
///         structural companion (the absence of any `FlipRoundLib` reference at the flush) lives
///         in `test/stat/FlipHundredsInvariant.test.js` [04a]; this file is the one that fails if
///         the "simplify it later — just round once at the flush" refactor is ever made.
///
/// @dev Scaffold (setUp, slot constants, bet placement, RNG injection) is a faithful copy of
///      `DegeneretteResolveRepeg.t.sol`, which in turn copies `DegeneretteFreezeResolution.t.sol`.
///      CROSS-CITE: .planning/PLAN-FLIP-ROUND-HUNDREDS.md §4.
contract DegeneretteFlipRoundAntiGrind is DeployProtocol {
    // =========================================================================
    // Storage slot constants (confirmed via `forge inspect ... storage`)
    // =========================================================================

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;
    /// @dev lootboxRngPacked; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 38;
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
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
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

    /// @notice One batch, one-per-transaction, and one reversed batch must all mint the same
    ///         total FLIP. Any collapse applied to the caller-composed aggregate would break at
    ///         least one of the three, because the remainder being rounded would differ.
    function testBatchCompositionCannotMoveTheFlipTotal() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("flip-round-anti-grind"));

        uint64[] memory ids = _placeWinningFlipBets(index, word);
        _injectLootboxRngWord(index, word);

        // Leg A — all bets in one batch.
        uint256 snap = vm.snapshotState();
        uint256 batchTotal = _resolveAndMeasure(ids);
        vm.revertToState(snap);

        // Leg B — one bet per transaction. If the collapse keyed on the batch instead of the
        // bet, this leg would round `BET_COUNT` separate remainders instead of one summed
        // remainder, and the totals would diverge.
        snap = vm.snapshotState();
        uint256 singleTotal;
        uint256 nonZeroMints;
        for (uint256 i; i < ids.length; i++) {
            uint64[] memory one = new uint64[](1);
            one[0] = ids[i];
            uint256 minted = _resolveAndMeasure(one);
            if (minted != 0) {
                ++nonZeroMints;
                // Every surviving payout here clears the threshold, so each one must land on
                // a whole 100-FLIP multiple on its own — not merely in aggregate.
                assertEq(
                    minted % FlipRoundLib.FLIP_ROUND_UNIT,
                    0,
                    "a per-bet FLIP mint is not a whole 100-FLIP multiple"
                );
                assertGt(
                    minted,
                    FlipRoundLib.FLIP_ROUND_THRESHOLD,
                    "stake sizing must keep every paid bet above the threshold, or the test is vacuous"
                );
            }
            singleTotal += minted;
        }
        vm.revertToState(snap);

        // Leg C — one batch, reverse order. Ordering is another degree of freedom a settler
        // controls for free.
        snap = vm.snapshotState();
        uint64[] memory reversed = new uint64[](ids.length);
        for (uint256 i; i < ids.length; i++) {
            reversed[i] = ids[ids.length - 1 - i];
        }
        uint256 reversedTotal = _resolveAndMeasure(reversed);
        vm.revertToState(snap);

        // Non-vacuity: the survival flip must have left something to round, and at least two
        // bets must have paid, or "batching cannot move the total" is trivially true.
        assertGt(batchTotal, 0, "no FLIP was minted - the fixture pays nothing");
        assertGe(
            nonZeroMints,
            2,
            "fewer than two bets survived their flip - the batch has no partition freedom to test"
        );

        assertEq(
            batchTotal,
            singleTotal,
            "settling one-per-tx paid a different total than one batch: the collapse is keyed on the BATCH, not the bet"
        );
        assertEq(
            batchTotal,
            reversedTotal,
            "reordering the batch moved the total: the collapse depends on settle-time ordering"
        );
        assertEq(
            batchTotal % FlipRoundLib.FLIP_ROUND_UNIT,
            0,
            "the summed mint is not a whole 100-FLIP multiple"
        );
    }

    /// @notice Every proper subset settles to the same per-bet value as the full batch, so no
    ///         partition of the bet set beats any other. This is the property a grinder would
    ///         actually search over, checked directly against every 2-way split.
    function testEveryPartitionPaysTheSameTotal() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("flip-round-partition-search"));

        uint64[] memory ids = _placeWinningFlipBets(index, word);
        _injectLootboxRngWord(index, word);

        uint256 snap = vm.snapshotState();
        uint256 wholeTotal = _resolveAndMeasure(ids);
        vm.revertToState(snap);

        // Walk every non-trivial 2-way split of the bet set by bitmask. With BET_COUNT = 6
        // that is 62 partitions — the whole search space a settler could enumerate.
        uint256 masks = (1 << BET_COUNT) - 1;
        for (uint256 mask = 1; mask < masks; mask++) {
            snap = vm.snapshotState();

            uint256 leftLen;
            for (uint256 i; i < BET_COUNT; i++) {
                if (mask & (1 << i) != 0) ++leftLen;
            }
            uint64[] memory left = new uint64[](leftLen);
            uint64[] memory right = new uint64[](BET_COUNT - leftLen);
            uint256 l;
            uint256 r;
            for (uint256 i; i < BET_COUNT; i++) {
                if (mask & (1 << i) != 0) {
                    left[l++] = ids[i];
                } else {
                    right[r++] = ids[i];
                }
            }

            uint256 splitTotal = _resolveAndMeasure(left) +
                _resolveAndMeasure(right);

            assertEq(
                splitTotal,
                wholeTotal,
                "a batch partition paid a different total than the whole set - the collapse is grindable"
            );

            vm.revertToState(snap);
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Place `BET_COUNT` FLIP bets that all self-match on spin 0 (so they win and have a
    ///      payout to round), funded up front.
    function _placeWinningFlipBets(uint48 index, uint256 word)
        internal
        returns (uint64[] memory ids)
    {
        _fundFlip(
            player,
            uint256(FLIP_PER_SPIN) * SPINS * BET_COUNT + 1 ether
        );
        uint32 ticket = _winningTicketFor(index, word);

        ids = new uint64[](BET_COUNT);
        for (uint256 i; i < BET_COUNT; i++) {
            ids[i] = _placeBet(CURRENCY_FLIP, FLIP_PER_SPIN, SPINS, ticket);
        }
    }

    /// @dev Resolve `betIds` from the keeper and return the FLIP minted to `player`.
    ///      Resolution is permissionless and only ever credits the bet owner, so the keeper
    ///      needs no approval — which is exactly why batch composition is attacker-controlled.
    function _resolveAndMeasure(uint64[] memory betIds)
        internal
        returns (uint256 minted)
    {
        if (betIds.length == 0) return 0;
        uint256 before = coin.balanceOf(player);
        vm.prank(keeper);
        game.resolveDegeneretteBets(player, betIds);
        minted = coin.balanceOf(player) - before;
    }

    /// @dev Place a Degenerette bet for `player` and return its betId (nonce).
    function _placeBet(
        uint8 currency,
        uint128 perTicket,
        uint8 spins,
        uint32 ticket
    ) internal returns (uint64 betId) {
        vm.prank(player);
        game.placeDegeneretteBet(
            address(0),
            currency,
            perTicket,
            spins,
            ticket,
            0
        );
        betId = _betNonce(player);
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
        bytes32 slot = keccak256(
            abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT))
        );
        vm.store(address(game), slot, bytes32(rngWord));
    }

    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(
            abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT))
        );
        return uint64(uint256(vm.load(address(game), slot)));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        uint256 newPacked = (currentPacked &
            ~(((uint256(1) << 104) - 1) << 104)) | (targetFuture << 104);
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
