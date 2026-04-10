// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";

/// @title DegeneretteFreezeResolutionTest -- Proves FIX-04: Degenerette ETH
///        resolution succeeds during prizePoolFrozen, routing payouts through
///        the pending pool side-channel instead of the live futurePrizePool.
///
/// @notice The bug: _distributePayout previously reverted with E() whenever
///         prizePoolFrozen was true, blocking all degenerette ETH bet resolution
///         during jackpot phase. The fix routes the ETH portion through
///         _getPendingPools/_setPendingPools (matching the bet-placement pattern
///         at L558-561), keeping the live futurePrizePool snapshot untouched.
///
/// @dev Deploys full 23-contract protocol via DeployProtocol. Uses vm.store to
///      inject freeze state and seed pending pools to a known value, then places
///      a real degenerette ETH bet via the public API, injects a lootbox RNG word
///      pre-computed to produce a winning result, and resolves the bet. Asserts
///      ETH conservation: live futurePrizePool untouched, pending pool debited,
///      player credited.
contract DegeneretteFreezeResolutionTest is DeployProtocol {
    // --- Storage slot constants (confirmed via `forge inspect DegenerusGameStorage storage`) ---

    /// @dev Slot 0, byte 29 (bit 232): prizePoolFrozen (bool, 1 byte).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant FROZEN_BIT_SHIFT = 232;

    /// @dev prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool]
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    /// @dev prizePoolPendingPacked: [upper 128: futurePending] [lower 128: nextPending]
    uint256 private constant PENDING_PACKED_SLOT = 11;

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 39;

    /// @dev lootboxRngPacked at slot 38; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 38;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("degen_freeze_player");
        vm.deal(player, 1000 ether);

        // Fund the game contract with ETH to back the pool injections
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet reverts with E() when lootboxRngIndex == 0.
        // Seed it to 1 so the bet check passes. The word at index 1 starts
        // as 0 (no pending RNG), which is the required state for bet placement.
        // lootboxRngIndex is the low 48 bits of lootboxRngPacked (slot 38).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
    }

    // =========================================================================
    // Test 1: Resolution during freeze succeeds with winning bet,
    //         ETH conservation holds
    // =========================================================================

    /// @notice Prove degenerette ETH resolution during prizePoolFrozen:
    ///         - Does not revert (pre-fix: reverted with E())
    ///         - Live futurePrizePool is UNTOUCHED (per D-05)
    ///         - Pending future accumulator is debited by exactly ethPortion
    ///         - Player receives claimable ETH credit equal to ethPortion
    ///         - Conservation: pendingDebit == playerClaimable
    function testDegeneretteFreezeResolutionEthConserved() public {
        // --- Phase 1: Set up freeze state ---

        // Seed the live futurePrizePool to 50 ether (to prove it stays untouched)
        _seedFuturePrizePool(50 ether);

        // Set prizePoolFrozen = true
        _setFrozenFlag(true);

        // Seed pending future accumulator large enough to cover worst-case degenerette
        // ETH payout (8-match win can exceed 4000 ETH on a 0.01 ETH bet).
        _seedPendingFuture(10_000 ether);

        // Record pre-bet state
        uint256 preLiveFuture = _readFuturePrizePool();
        uint256 prePendingFuture = _readPendingFuture();
        assertEq(preLiveFuture, 50 ether, "Pre-bet live future should be 50 ETH");
        assertEq(prePendingFuture, 10_000 ether, "Pre-bet pending future should be 10000 ETH");

        // --- Phase 2: Find a winning RNG word ---
        // Pre-compute an RNG word that produces a result ticket with >= 2 matches
        // against our custom ticket. This guarantees _distributePayout is called.
        uint48 index = 1; // default lootboxRngIndex
        uint32 customTicket;
        uint256 winningRngWord;
        (customTicket, winningRngWord) = _findWinningCombo(index);

        // --- Phase 3: Place a degenerette ETH bet during freeze ---
        // The bet goes to pending pools per L558-561 (prizePoolFrozen branch).
        uint128 betAmount = 0.01 ether;

        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0),     // player = msg.sender
            0,              // currency = ETH
            betAmount,      // amountPerTicket
            1,              // ticketCount = 1
            customTicket,   // custom traits (matched to RNG word)
            0xFF            // no hero quadrant
        );

        // Record post-bet state: pending future should have increased by betAmount
        uint256 postBetPendingFuture = _readPendingFuture();
        uint256 postBetLiveFuture = _readFuturePrizePool();
        assertEq(postBetLiveFuture, preLiveFuture, "Live future must be untouched after freeze bet");
        assertEq(postBetPendingFuture, prePendingFuture + betAmount,
            "Pending future should include the bet deposit");

        // --- Phase 4: Inject RNG word and resolve the bet ---
        _injectLootboxRngWord(index, winningRngWord);

        // Record pre-resolve state
        uint256 preResolvePendingFuture = _readPendingFuture();
        uint256 preResolveClaimable = game.claimableWinningsOf(player);
        assertEq(preResolveClaimable, 0, "Player should have no claimable before resolve");

        // Resolve the bet (betId = 1, first bet for this player).
        // Pre-fix: this call would revert with E() because prizePoolFrozen was true.
        uint64[] memory betIds = new uint64[](1);
        betIds[0] = 1;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        // --- Phase 5: Assert ETH conservation ---
        uint256 postResolvePendingFuture = _readPendingFuture();
        uint256 postResolveLiveFuture = _readFuturePrizePool();
        uint256 postResolveClaimable = game.claimableWinningsOf(player);

        // CRITICAL: Live futurePrizePool UNTOUCHED (per D-05)
        assertEq(postResolveLiveFuture, preLiveFuture,
            "Live futurePrizePool must remain exactly 50 ETH (untouched during freeze)");

        // Player must have received a nonzero ETH credit (we engineered a winning RNG word)
        assertGt(postResolveClaimable, 0, "Player must have nonzero claimable (winning bet)");

        // Pending future was debited by exactly the ETH portion credited to the player
        uint256 pendingDebit = preResolvePendingFuture - postResolvePendingFuture;
        assertEq(pendingDebit, postResolveClaimable,
            "ETH conservation: pending pool debit must equal player's claimable ETH credit");

        // The pending pool was not over-debited (conservation: debit <= what was available)
        assertLe(pendingDebit, preResolvePendingFuture,
            "Pending pool debit must not exceed what was available");

        emit log_named_uint("Pending debit (ETH portion)", pendingDebit);
        emit log_named_uint("Player claimable", postResolveClaimable);
        emit log_named_uint("Post live future", postResolveLiveFuture);
        emit log_named_uint("Post pending future", postResolvePendingFuture);
    }

    // =========================================================================
    // Test 2: Zero pending future during freeze -- ETH capped to zero,
    //         resolution succeeds without revert
    // =========================================================================

    /// @notice With insufficient pending future, resolution reverts with E()
    ///         (solvency check: pFuture < ethPortion).
    function testDegeneretteFreezeResolutionZeroPendingReverts() public {
        _setFrozenFlag(true);

        // Seed pending future to enough for the bet placement (bet adds to pending),
        // then zero it before resolution.
        _seedPendingFuture(1 ether);

        // Seed live future to prove it stays untouched
        _seedFuturePrizePool(50 ether);

        // Find a winning combo to ensure _distributePayout is actually called
        uint48 index = 1;
        uint32 customTicket;
        uint256 winningRngWord;
        (customTicket, winningRngWord) = _findWinningCombo(index);

        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTicket, 0xFF
        );

        // Zero pending future before resolution
        _seedPendingFuture(0);

        // Inject RNG word
        _injectLootboxRngWord(index, winningRngWord);

        // Resolution reverts: ethPortion > 0 but pFuture = 0 → solvency check fails
        uint64[] memory betIds = new uint64[](1);
        betIds[0] = 1;
        vm.prank(player);
        vm.expectRevert(bytes4(0x92bbf6e8)); // E()
        game.resolveDegeneretteBets(address(0), betIds);

        // Live future untouched
        assertEq(_readFuturePrizePool(), 50 ether, "Live future must remain untouched");
    }

    // =========================================================================
    // Test 3: Unfrozen path regression (behavior unchanged)
    // =========================================================================

    /// @notice Prove unfrozen path works identically to before (regression test).
    ///         Bet goes to live pools, resolution debits live futurePrizePool,
    ///         pending pools are untouched throughout.
    function testDegeneretteUnfrozenPathRegression() public {
        // NOT frozen (default state)
        assertFalse(_readFrozen(), "Should start unfrozen");

        // Seed live futurePrizePool
        _seedFuturePrizePool(100 ether);

        uint256 preLiveFuture = _readFuturePrizePool();
        uint256 prePendingFuture = _readPendingFuture();

        // Find a winning combo for a winning resolve
        uint48 index = 1;
        uint32 customTicket;
        uint256 winningRngWord;
        (customTicket, winningRngWord) = _findWinningCombo(index);

        // Place bet (goes to live pools since not frozen)
        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTicket, 0xFF
        );

        // Live pools should have increased (unfrozen path uses _setPrizePools)
        uint256 postBetLiveFuture = _readFuturePrizePool();
        assertEq(postBetLiveFuture, preLiveFuture + betAmount,
            "Unfrozen: live future should increase by bet amount");

        // Pending should be untouched
        assertEq(_readPendingFuture(), prePendingFuture,
            "Unfrozen: pending future should be untouched");

        // Inject RNG word and resolve
        _injectLootboxRngWord(index, winningRngWord);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = 1;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        // Live future should have decreased (debited by ETH payout)
        uint256 postResolveLiveFuture = _readFuturePrizePool();
        assertLt(postResolveLiveFuture, postBetLiveFuture,
            "Unfrozen: live future should decrease after winning resolve");

        // Player should have claimable ETH
        uint256 postClaimable = game.claimableWinningsOf(player);
        assertGt(postClaimable, 0, "Unfrozen: player should have claimable from winning bet");

        // Unfrozen conservation: live pool debit == player claimable
        uint256 liveDebit = postBetLiveFuture - postResolveLiveFuture;
        assertEq(liveDebit, postClaimable,
            "Unfrozen: live pool debit must equal player claimable");

        // Pending still untouched
        assertEq(_readPendingFuture(), prePendingFuture,
            "Unfrozen: pending future should remain untouched after resolve");
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// @notice Read futurePrizePool from packed slot (upper 128 bits of slot 3).
    function _readFuturePrizePool() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        return uint256(uint128(packed >> 128));
    }

    /// @notice Read pending future from packed slot (upper 128 bits of slot 14).
    function _readPendingFuture() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        return uint256(uint128(packed >> 128));
    }

    /// @notice Read prizePoolFrozen from slot 0, bit 232.
    function _readFrozen() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        return ((s0 >> FROZEN_BIT_SHIFT) & 0xFF) != 0;
    }

    /// @notice Seed futurePrizePool (upper 128 bits of slot 3).
    /// @dev Preserves the lower 128 bits (nextPrizePool).
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Seed pending future (upper 128 bits of slot 14).
    /// @dev Preserves the lower 128 bits (nextPending).
    function _seedPendingFuture(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PENDING_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Set prizePoolFrozen flag (slot 0, bit 232).
    /// @dev Preserves all other bytes in slot 0.
    function _setFrozenFlag(bool frozen) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        // Clear the frozen byte (bit 232)
        s0 = s0 & ~(uint256(0xFF) << FROZEN_BIT_SHIFT);
        // Set the frozen byte
        if (frozen) {
            s0 = s0 | (uint256(1) << FROZEN_BIT_SHIFT);
        }
        vm.store(address(game), bytes32(uint256(SLOT_0)), bytes32(s0));
    }

    /// @notice Inject a lootbox RNG word for a given index.
    /// @dev Writes to the lootboxRngWordByIndex mapping at slot 39.
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @notice Find a (customTicket, rngWord) pair that guarantees >= 2 matches.
    /// @dev Tries RNG words in sequence, computing the result ticket for spin 0
    ///      (index 1) using the same derivation as _resolveFullTicketBet. Returns
    ///      when a combination with >= 2 matches is found.
    function _findWinningCombo(uint48 index) internal pure returns (uint32 customTicket, uint256 rngWord) {
        for (uint256 attempt; attempt < 100; attempt++) {
            rngWord = uint256(keccak256(abi.encode("freeze_test_rng", attempt)));

            // Replicate the result seed derivation from _resolveFullTicketBet (spin 0)
            // Contract uses uint32 index in encodePacked (v24.1 change)
            uint256 resultSeed = uint256(keccak256(abi.encodePacked(rngWord, uint32(index), QUICK_PLAY_SALT)));
            uint32 resultTicket = DegenerusTraitUtils.packedTraitsFromSeed(resultSeed);

            // Use the result ticket AS the custom ticket -- guarantees 8/8 matches (jackpot).
            // This is valid because custom ticket format matches result ticket format.
            customTicket = resultTicket;

            // Verify matches (should be 8 since they're identical)
            uint8 matches = _countMatchesLocal(customTicket, resultTicket);
            if (matches >= 2) return (customTicket, rngWord);
        }
        revert("Could not find winning combo in 100 attempts");
    }

    /// @notice Local match counting (mirrors DegeneretteModule._countMatches).
    function _countMatchesLocal(uint32 a, uint32 b) internal pure returns (uint8 matches) {
        for (uint8 q; q < 4; q++) {
            uint8 aQuad = uint8(a >> (q * 8));
            uint8 bQuad = uint8(b >> (q * 8));
            if (((aQuad >> 3) & 7) == ((bQuad >> 3) & 7)) matches++; // color
            if ((aQuad & 7) == (bQuad & 7)) matches++;                // symbol
        }
    }
}
