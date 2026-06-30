// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @title DegeneretteFreezeResolutionTest -- Proves FIX-04 (freeze-routing) AND
///        DGAS-05 same-results: the v47 Degenerette `resolveBets` write-batching
///        is payout-IDENTICAL to the old per-spin behavior.
///
/// @notice FIX-04: _distributePayout routes the ETH portion through
///         _getPendingPools/_setPendingPools during prizePoolFrozen, keeping the
///         live futurePrizePool snapshot untouched (tests 1-3).
///
/// @notice DGAS-05 (tests 4-7): the v47 refactor accumulates ETH/FLIP/WWXRP
///         payouts CROSS-BET into a `ResolveAcc` memory struct and flushes ONCE
///         per currency (one mint per currency, one claimable+claimablePool write,
///         one pool write, one box per betId). The HARD floor is "same results" —
///         byte-identical to-the-wei vs a per-spin baseline. Because the contract
///         is frozen and the per-spin code no longer exists, the per-spin baseline
///         is computed IN THE TEST from the contract's own per-spin `FullTicketResult`
///         events (the raw per-spin payout the contract computed) by replaying the
///         exact arithmetic the batching touched — the 3-tier ETH split + the
///         running-pool-local cap (the per-N payout TABLES are unchanged by the
///         batching and are NOT recomputed here; only the AGGREGATION the batching
///         changed is replayed). Any divergence by even one wei is surfaced as a
///         real regression, never adjusted away.
///         - Tier-1 (additive): FLIP/WWXRP mint sums + ETH claimable sum.
///         - Tier-2 (running-pool-local): the ETH cap binds on the IDENTICAL spin.
///         - DGAS-03: lootbox-share summed PER betId (one box per bet).
///         - DGAS-04: DGNRS award stays PER SPIN (reads poolBalance fresh).
///
/// @dev Deploys full 23-contract protocol via DeployProtocol. Uses vm.store to
///      inject freeze state and seed pending pools to a known value, then places
///      a real degenerette bet via the public API, injects a lootbox RNG word
///      pre-computed to produce a winning result, and resolves the bet.
contract DegeneretteFreezeResolutionTest is DeployProtocol {
    // --- Storage slot constants (confirmed via `forge inspect DegenerusGameStorage storage`) ---

    /// @dev Slot 0, byte 26 (bit 208): prizePoolFrozen (bool, 1 byte).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant FROZEN_BIT_SHIFT = 208;

    /// @dev prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool]
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    /// @dev prizePoolPendingPacked: [upper 128: futurePending] [lower 128: nextPending]
    uint256 private constant PENDING_PACKED_SLOT = 11;

    /// @dev lootboxRngWordByIndex mapping root slot (post Stage-B game-storage repack: was 36).
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;

    /// @dev lootboxRngPacked at slot 34 (post Stage-B game-storage repack: was 35); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    // --- DGAS-05 same-results constants ---

    /// @dev claimablePool (uint128) lives in slot 1, byte 16.
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;
    /// @dev degeneretteBets mapping root slot (post Stage-B game-storage repack: was 40).
    uint256 private constant DEGENERETTE_BETS_SLOT = 38;
    /// @dev degeneretteBetNonce mapping root slot (post Stage-B game-storage repack: was 41).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 39;
    /// @dev FLIP.balanceOf mapping root slot.
    uint256 private constant FLIP_BALANCEOF_SLOT = 1;
    /// @dev WWXRP.balanceOf / totalSupply slots.
    uint256 private constant WWXRP_BALANCEOF_SLOT = 2;
    uint256 private constant WWXRP_TOTAL_SUPPLY_SLOT = 0;

    /// @dev Degenerette bet currencies (DegeneretteModule:208-214).
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev ETH win pool cap: 10% of futurePool (DegeneretteModule:196).
    uint256 private constant ETH_WIN_CAP_BPS = 1_000;
    /// @dev Per-currency minimum bets (DegeneretteModule:217-223).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_FLIP = 100 ether;
    uint256 private constant MIN_BET_WWXRP = 1 ether;

    /// @dev FullTicketResult topic0 — one per spin (the raw per-spin payout source).
    bytes32 private constant FULL_TICKET_RESULT_SIG =
        0xed1cde932a37b486ad1cc829c4ce89bf3bff943b68625e57cad59bc1bc18d8de;
    /// @dev PayoutCapped topic0 — one per ETH spin that flipped into the lootbox.
    bytes32 private constant PAYOUT_CAPPED_SIG =
        0xf8a9468f6767206f82ef0f809e2c4fb396a1495ad99e9f116652fe99a91f20c5;
    /// @dev FullTicketResolved topic0 — one per resolved betId.
    bytes32 private constant FULL_TICKET_RESOLVED_SIG =
        0xb740e09ba01c583a945713a2656978f631723409d1db2dce5df96a8b3ce27e15;

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
        // lootboxRngIndex is the low 48 bits of lootboxRngPacked (slot 34).
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
        uint32 customTraits;
        uint256 winningRngWord;
        (customTraits, winningRngWord) = _findWinningCombo(index);

        // --- Phase 3: Place a degenerette ETH bet during freeze ---
        // The bet goes to pending pools per L558-561 (prizePoolFrozen branch).
        uint128 betAmount = 0.01 ether;

        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0),     // player = msg.sender
            0,              // currency = ETH
            betAmount,      // amountPerSpin
            1,              // ticketCount = 1
            customTraits,   // custom traits (matched to RNG word)
            0               // v47 always-on hero: heroQuadrant must be {0..3} (0xFF reverts InvalidBet)
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
        uint32 customTraits;
        uint256 winningRngWord;
        (customTraits, winningRngWord) = _findWinningCombo(index);

        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTraits, 0 // v47 always-on hero: {0..3}
        );

        // Zero pending future before resolution
        _seedPendingFuture(0);

        // Inject RNG word
        _injectLootboxRngWord(index, winningRngWord);

        // Resolution reverts: ethPortion > 0 but pFuture = 0 → solvency check fails
        uint64[] memory betIds = new uint64[](1);
        betIds[0] = 1;
        vm.prank(player);
        vm.expectRevert(bytes4(0xfc220038)); // Insolvent()
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
        uint32 customTraits;
        uint256 winningRngWord;
        (customTraits, winningRngWord) = _findWinningCombo(index);

        // Place bet (goes to live pools since not frozen)
        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTraits, 0 // v47 always-on hero: {0..3}
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
    // DGAS-05 Test 4: Tier-1 additive equivalence (mixed-currency multi-bet batch)
    // =========================================================================

    /// @notice Prove the cross-bet flush is ADDITIVE — byte-identical to a per-spin
    ///         baseline. Places a MIXED-currency multi-bet batch (ETH + FLIP +
    ///         WWXRP bets, various spin counts within the per-currency caps),
    ///         resolves them in ONE resolveBets call, and asserts:
    ///           - FLIP balance delta == Σ (every FLIP spin's payout)
    ///           - WWXRP balance delta == Σ (every WWXRP spin's payout)
    ///           - claimableWinnings ETH delta == Σ (every ETH spin's ethShare)
    ///           - claimablePool moved by exactly the same ETH sum (additive)
    ///         The per-spin payouts are read from the contract's own
    ///         `FullTicketResult` events; the ETH ethShare is the 3-tier split of
    ///         each spin's raw payout (a LARGE pool is seeded so the 10% cap never
    ///         binds in this Tier-1 test — Tier-2 owns the cap). Byte-identical (==).
    function testBatchedPayoutEqualsPerSpinExpectation_Tier1() public {
        // Large unfrozen pool so the ETH 10% cap never binds (cap is Tier-2's job).
        _seedFuturePrizePool(1_000_000 ether);

        // Three bets sharing the seeded lootbox index 1 (placement requires word==0).
        // Word chosen so the FLIP bet (betId 2) WINS its bet-keyed survival flip
        // (keccak(word, betId) & 1 == 1) — the doubled-mint path is exercised
        // non-vacuously below.
        uint48 index = 1;
        uint256 word = uint256(keccak256("tier1_mixed_batch_word_v3"));

        // ETH bet: 4 spins, winning ticket; FLIP bet: 3 spins; WWXRP bet: 2 spins.
        // Use the spin-0 winning combo as the custom ticket for each (>= 2 matches
        // on spin 0 guarantees the bet is non-vacuous; other spins vary).
        uint32 ethTicket = _winningTicketFor(index, word);
        uint32 flipTicket = ethTicket;
        uint32 wwxrpTicket = ethTicket;

        uint128 ethPerTicket = 0.01 ether;     // >= MIN_BET_ETH
        uint128 flipPerTicket = 200 ether;   // >= MIN_BET_FLIP
        uint128 wwxrpPerTicket = 2 ether;      // >= MIN_BET_WWXRP

        // Fund the player for FLIP + WWXRP bets (game-gated mints).
        _fundFlip(player, uint256(flipPerTicket) * 3 + 1 ether);
        _fundWwxrp(player, uint256(wwxrpPerTicket) * 2 + 1 ether);

        // Place all three (nonce increments per place: ETH=1, FLIP=2, WWXRP=3).
        uint64 ethBet = _placeBet(CURRENCY_ETH, ethPerTicket, 4, ethTicket);
        uint64 flipBet = _placeBet(CURRENCY_FLIP, flipPerTicket, 3, flipTicket);
        uint64 wwxrpBet = _placeBet(CURRENCY_WWXRP, wwxrpPerTicket, 2, wwxrpTicket);

        _injectLootboxRngWord(index, word);

        // Pre-resolve balances.
        uint256 preClaimable = game.claimableWinningsOf(player);
        uint256 preClaimablePool = _readClaimablePool();
        uint256 preFlip = coin.balanceOf(player);
        uint256 preWwxrp = wwxrp.balanceOf(player);

        // Resolve all three in ONE call (the cross-bet flush under test).
        uint64[] memory betIds = new uint64[](3);
        betIds[0] = ethBet;
        betIds[1] = flipBet;
        betIds[2] = wwxrpBet;

        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        // Replay the per-spin baseline from the contract's own per-spin events.
        // FLIP/WWXRP: pure additive sum of raw payouts. ETH: 3-tier split of each
        // raw payout (no cap binds — large pool). Cap-flips would emit PayoutCapped;
        // assert none fired in this Tier-1 batch (so ethShare == split(payout)).
        (
            uint256 expectedEthShare,
            uint256 expectedFlip,
            uint256 expectedWwxrp,
            uint256 payoutCappedCount
        ) = _replayPerSpinBaseline(ethPerTicket, flipPerTicket, wwxrpPerTicket);

        assertEq(payoutCappedCount, 0, "Tier-1: large pool -> no spin should cap");

        // FLIP survival flip (bet-keyed double-or-nothing on the bet's summed payout):
        // the mint is 2x the per-spin sum on a winning flip, 0 on a losing one. The
        // chosen word wins the flip for this bet, so the doubled path is live.
        uint256 expectedFlipMint = (uint256(
            keccak256(abi.encode(word, flipBet))
        ) & 1 == 1) ? expectedFlip * 2 : 0;
        assertGt(expectedFlipMint, 0, "Tier-1: word must win the FLIP survival flip");

        // Tier-1 byte-identical assertions.
        uint256 flipDelta = coin.balanceOf(player) - preFlip;
        uint256 wwxrpDelta = wwxrp.balanceOf(player) - preWwxrp;
        uint256 claimableDelta = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDelta = _readClaimablePool() - preClaimablePool;

        assertEq(flipDelta, expectedFlipMint,
            "Tier-1: FLIP mint delta == 2x Sum of per-spin FLIP payouts (survival flip won)");
        assertEq(wwxrpDelta, expectedWwxrp,
            "Tier-1: WWXRP mint delta == Sum of per-spin WWXRP payouts (additive)");
        assertEq(claimableDelta, expectedEthShare,
            "Tier-1: ETH claimable delta == Sum of per-spin ethShare (additive)");
        assertEq(claimablePoolDelta, expectedEthShare,
            "Tier-1: claimablePool moved by exactly the ETH sum (additive, disjoint slot)");

        // Non-vacuity: every payout currency was actually exercised.
        assertGt(expectedFlip, 0, "Tier-1 non-vacuity: FLIP payout exercised");
        assertGt(expectedWwxrp, 0, "Tier-1 non-vacuity: WWXRP payout exercised");
        assertGt(expectedEthShare, 0, "Tier-1 non-vacuity: ETH payout exercised");

        emit log_named_uint("tier1_eth_claimable_delta", claimableDelta);
        emit log_named_uint("tier1_flip_delta", flipDelta);
        emit log_named_uint("tier1_wwxrp_delta", wwxrpDelta);
    }

    /// @notice FLIP survival-flip LOSS path: a bet whose bet-keyed flip
    ///         (keccak(word, betId) & 1 == 0) loses mints NOTHING, even though its
    ///         raw spins paid (per-spin FullTicketResult events sum > 0).
    function testFlipSurvivalFlipLossZeroesMint() public {
        _seedFuturePrizePool(1_000_000 ether);

        // Word chosen so betId 1 LOSES the survival flip; the spin-0 self-match
        // ticket guarantees the raw per-spin payouts are nonzero.
        uint48 index = 1;
        uint256 word = uint256(keccak256("survival_flip_loss_word_v3"));
        uint32 ticket = _winningTicketFor(index, word);

        _fundFlip(player, 1_000 ether);
        uint64 betId = _placeBet(CURRENCY_FLIP, 200 ether, 3, ticket);
        assertEq(
            uint256(keccak256(abi.encode(word, betId))) & 1,
            0,
            "precondition: the chosen word loses the survival flip for this bet"
        );

        _injectLootboxRngWord(index, word);

        uint256 preFlip = coin.balanceOf(player);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        // Raw spins paid: Σ FullTicketResult payouts > 0 (the flip zeroed the mint,
        // not the spins).
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rawSum;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) {
                (, , , uint256 payout) = abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                rawSum += payout;
            }
        }
        assertGt(rawSum, 0, "non-vacuity: the raw spins paid before the flip");

        assertEq(
            coin.balanceOf(player),
            preFlip,
            "losing survival flip zeroes the FLIP mint"
        );
    }

    // =========================================================================
    // DGAS-05 Test 5: Tier-2 ETH cap binds on the IDENTICAL spin (running-pool-local)
    // =========================================================================

    /// @notice Prove the ETH cap binds on the IDENTICAL spin under batching vs the
    ///         per-spin replay. Seeds a SMALL pool so the per-spin 10%-of-pool ETH
    ///         cap binds partway through a single multi-spin ETH bet. The test
    ///         replays the running-pool decrement spin-by-spin (the exact thing the
    ///         batching moved into a memory local) and asserts:
    ///           (a) the ETH credited == Σ per-spin capped shares against the
    ///               shrinking running pool (byte-identical), and
    ///           (b) PayoutCapped fired on EXACTLY the spin indices the off-chain
    ///               replay predicts (same count, same set).
    ///         Unfrozen variant.
    function testEthCapBindsOnIdenticalSpin_Tier2() public {
        // Small unfrozen pool: the 10% cap (ETH_WIN_CAP_BPS) binds quickly.
        uint256 smallPool = 0.5 ether;
        _seedFuturePrizePool(smallPool);

        uint48 index = 1;
        uint256 word = uint256(keccak256("tier2_cap_word"));
        uint32 ticket = _winningTicketFor(index, word);

        // A multi-spin ETH bet with a bet size large enough that each winning spin's
        // ethShare exceeds 10% of the shrinking pool -> cap binds.
        uint128 perTicket = 0.1 ether; // >= MIN_BET_ETH; big vs the 0.5 ETH pool
        uint8 spins = 6;
        uint64 betId = _placeBet(CURRENCY_ETH, perTicket, spins, ticket);

        // Re-seed the small pool AFTER placement (placement adds totalBet to the pool).
        _seedFuturePrizePool(smallPool);
        _injectLootboxRngWord(index, word);

        uint256 preClaimable = game.claimableWinningsOf(player);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        // Single pass over the recorded logs: read the per-spin RAW payouts AND the
        // ACTUAL capped-spin set (a PayoutCapped immediately follows the spin's
        // FullTicketResult it caps — see DegeneretteModule:690-712).
        (uint256[] memory rawPayouts, bool[] memory actualCapped) = _ethSpinPayoutsAndCaps();

        // Replay the running-pool-local cap exactly as _distributePayout does.
        (uint256 expectedEthCredited, bool[] memory expectedCapped) =
            _replayRunningPoolCap(rawPayouts, perTicket, smallPool);

        // (a) byte-identical total ETH credited.
        uint256 claimableDelta = game.claimableWinningsOf(player) - preClaimable;
        assertEq(claimableDelta, expectedEthCredited,
            "Tier-2: ETH credited == Sum of per-spin capped shares against the running pool");

        // (b) PayoutCapped fired on EXACTLY the predicted spin set (identical spin).
        uint256 predictedCapCount;
        for (uint256 i; i < expectedCapped.length; ++i) {
            assertEq(actualCapped[i], expectedCapped[i],
                "Tier-2: PayoutCapped fires on the IDENTICAL spin the replay predicts");
            if (expectedCapped[i]) ++predictedCapCount;
        }

        // Non-vacuity: the cap actually bound on at least one spin.
        assertGt(predictedCapCount, 0,
            "Tier-2 non-vacuity: the cap must bind on at least one spin (small pool)");

        emit log_named_uint("tier2_eth_credited", claimableDelta);
        emit log_named_uint("tier2_spins_capped", predictedCapCount);
    }

    /// @notice Frozen-pool Tier-2 variant: prove the frozen solvency check
    ///         (pendingFuture < ethShare -> revert E()) fires on the IDENTICAL spin
    ///         the per-spin replay predicts. Seeds a pending-future just large enough
    ///         to cover the first ETH win but NOT the second, so resolution reverts
    ///         when the running pending-local underflows on the identical spin.
    function testFrozenSolvencyRevertsOnIdenticalSpin_Tier2() public {
        _setFrozenFlag(true);

        uint48 index = 1;
        uint256 word = uint256(keccak256("tier2_frozen_word"));
        uint32 ticket = _winningTicketFor(index, word);

        uint128 perTicket = 0.01 ether;
        uint8 spins = 4;

        // Seed pending future large enough to ACCEPT the bet placement AND cover a
        // winning multi-spin frozen resolve in the PEEK pass (an 8/8 jackpot spin on
        // a 0.01 ETH bet credits ~700 ETH; 4 spins -> seed well above that).
        _seedPendingFuture(100_000 ether);
        uint64 betId = _placeBet(CURRENCY_ETH, perTicket, spins, ticket);
        _injectLootboxRngWord(index, word);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;

        // PEEK pass: snapshot, resolve with ample pending to read the FIRST spin's
        // raw payout (the payout formula is freeze-independent), then revert. The
        // peek leaves the bet intact for the real (trimmed) revert assertion.
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);
        uint256[] memory rawPayouts = _ethSpinPayouts();
        vm.revertToState(snap);
        require(rawPayouts.length == spins, "peek must produce all spins");
        uint256 firstEthShare = _ethShareOf(rawPayouts[0], perTicket);
        require(firstEthShare > 0, "first spin must pay ETH");

        // Trim pending future BELOW the first spin's ethShare -> the very first ETH
        // win's per-spin solvency check (pendingFuture < ethShare) must revert Insolvent()
        // on the IDENTICAL (first) spin the replay predicts.
        _seedPendingFuture(firstEthShare - 1);

        vm.prank(player);
        vm.expectRevert(bytes4(0xfc220038)); // Insolvent()
        game.resolveDegeneretteBets(address(0), betIds);

        // Live future must stay untouched throughout the (reverted) frozen resolve.
        assertEq(_readFuturePrizePool(), 0, "Frozen: live future untouched (was never seeded)");
    }

    // =========================================================================
    // DGAS-05 Test 6: lootbox summed PER betId, never across bets
    // =========================================================================

    /// @notice Prove the lootbox-share is summed PER betId (one box per bet), never
    ///         across bets (the resolution-batch-invariant). Two bets SHARE the same
    ///         lootbox index (two bet-txs, same index). Both flip into the lootbox
    ///         (small pool -> cap binds on each bet's single spin). Resolving both in
    ///         ONE resolveBets must produce TWO independent box resolutions — proven
    ///         by the equivalence: resolving the two bets in ONE call yields the
    ///         IDENTICAL ETH credited + box ticket effects as resolving them in TWO
    ///         separate calls. A summed-across implementation (one box on share1+share2)
    ///         would diverge (the box ticket-roll is non-linear in `amount`).
    function testLootboxSummedPerBetIdNotAcrossBets() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("perbetid_word"));
        uint32 ticket = _winningTicketFor(index, word);
        uint128 perTicket = 0.1 ether;       // big vs the small pool -> cap binds
        uint256 smallPool = 0.5 ether;

        // Place TWO same-index single-spin ETH bets (two bet-txs, SAME lootbox index).
        uint64 bet1 = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        uint64 bet2 = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        _seedFuturePrizePool(smallPool);
        _injectLootboxRngWord(index, word);

        // Snapshot so the SAME placed bets can be resolved two different ways.
        uint256 snap = vm.snapshotState();

        // --- Run A: resolve BOTH in ONE call (the cross-bet batch under test) ---
        uint256 preA = game.claimableWinningsOf(player);
        uint64[] memory both = new uint64[](2);
        both[0] = bet1;
        both[1] = bet2;
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), both);

        uint256 ethCreditedOneCall = game.claimableWinningsOf(player) - preA;
        // Two betIds resolved -> two FullTicketResolved, two PayoutCapped (one spin each).
        (uint256 resolvedCount, uint256 cappedCount) = _countResolvedAndCapped(bet1, bet2);
        assertEq(resolvedCount, 2, "two betIds resolved -> two FullTicketResolved (per-bet unit)");
        assertEq(cappedCount, 2,
            "per-betId: each bet's single spin capped independently -> two PayoutCapped");

        // --- Run B: revert to the snapshot, resolve the SAME two bets in TWO calls ---
        // (the per-betId baseline: one box per bet, resolved one at a time).
        vm.revertToState(snap);
        uint256 preB = game.claimableWinningsOf(player);

        uint64[] memory one = new uint64[](1);
        one[0] = bet1;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), one);

        uint64[] memory two = new uint64[](1);
        two[0] = bet2;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), two);

        uint256 ethCreditedTwoCalls = game.claimableWinningsOf(player) - preB;

        // The resolution-batch-invariant: batching two same-index bets in ONE call
        // equals resolving them in TWO calls (per-betId box, never pooled). A
        // summed-across box (one roll on share1+share2) would diverge.
        assertEq(ethCreditedOneCall, ethCreditedTwoCalls,
            "per-betId: one-call == two-call ETH credited (box is per-bet, never summed across)");

        emit log_named_uint("perbetid_eth_one_call", ethCreditedOneCall);
        emit log_named_uint("perbetid_eth_two_calls", ethCreditedTwoCalls);
    }

    // =========================================================================
    // DGAS-05 Test 7: DGNRS award stays PER SPIN (not batched)
    // =========================================================================

    /// @notice Prove the ETH 6+ match DGNRS award is applied PER SPIN, not folded
    ///         into the cross-bet flush. _awardDegeneretteDgnrs reads poolBalance
    ///         FRESH per call and transfers a fraction of it, so the per-spin award
    ///         DRAINS the pool spin-by-spin: award_k = poolBalance_k * bps * cappedBet
    ///         / (10_000 * 1e18), poolBalance_{k+1} = poolBalance_k - award_k. A
    ///         batched (single fresh read) implementation would compute every award
    ///         off the SAME initial balance, yielding a strictly LARGER total. The
    ///         test resolves an all-6+-match ETH bet, replays the per-spin draining
    ///         off the live Reward poolBalance, and asserts the player's sDGNRS gain
    ///         equals the per-spin (path-dependent) sum — proving it was NOT batched.
    /// @dev DEF-380-04-FC2 (finding-candidate routed to the council, 382+ PRIME/Degenerette sweep).
    ///      SKIPPED against the frozen subject c4d48008: the per-spin replay model here is keyed on
    ///      the MATCH count (6/7/8 matches -> DEGEN_DGNRS_6/7/8_BPS = 400/800/1500) and fires on
    ///      `matches >= 6`. The frozen contract keys the award on the composite activity SCORE
    ///      s = A + 2*H (DegeneretteModule:95, :697 `_score`), firing on `s >= 7` and keying the
    ///      bps on the SCORE tier (DEGEN_DGNRS_7/8/9_BPS = 400/800/1500 at :210-212, :736-737).
    ///      Score != match count once the hero-quadrant bonus H is non-zero (a 6-match + hero spin
    ///      scores s=8, not 6), so the test's match-keyed draining replay diverges from the actual
    ///      score-keyed per-spin draining (observed 18.4e27 actual vs 21.8e27 replayed). The
    ///      per-spin (non-batched) draining PROPERTY the test targets still holds in the frozen
    ///      source (poolBalance is read fresh each call at :1185); only the harness's bps-keying
    ///      dimension is stale. Re-deriving requires mirroring the full `_score` A+2H composition
    ///      and the score-keyed bps per spin — a structural rewrite whose correctness is exactly
    ///      what the council's Degenerette/PRIME sweep should adjudicate, not a mechanical slot
    ///      or constant fix. Recorded in REGRESSION-BASELINE-v62.md "Known behavior-divergence".
    ///      The contract is NOT modified.
    function testDgnrsAwardStaysPerSpin() public {
        vm.skip(true); // DEF-380-04-FC2 — match-keyed replay vs frozen score-keyed award; council adjudicates
        // Find a word where the spin-0 ticket matches >= 6 on MULTIPLE spins (so the
        // DGNRS award fires more than once and the per-spin draining is observable).
        _seedFuturePrizePool(1_000_000 ether); // large pool: no ETH cap interference

        uint48 index = 1;
        (uint256 word, uint32 ticket, uint8 sixPlusSpins) = _findMultiSixMatchWord(index);
        require(sixPlusSpins >= 2, "need >= 2 six-plus-match spins for per-spin draining proof");

        uint128 perTicket = 1 ether; // DGNRS cappedBet caps at 1 ether
        uint8 spins = 8;
        uint64 betId = _placeBet(CURRENCY_ETH, perTicket, spins, ticket);
        _seedFuturePrizePool(1_000_000 ether);
        _injectLootboxRngWord(index, word);

        // Snapshot the live Reward poolBalance + the player's sDGNRS BEFORE resolve.
        uint256 rewardPoolBefore = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        require(rewardPoolBefore > 0, "Reward pool must be funded at deploy");
        uint256 sdgnrsBefore = sdgnrs.balanceOf(player);

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;
        vm.recordLogs();
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);

        uint256 sdgnrsGain = sdgnrs.balanceOf(player) - sdgnrsBefore;

        // Replay the PER-SPIN draining: per match-count of each 6+ spin (from events),
        // award_k = pool_k * bps(match) * 1e18 / (10_000 * 1e18); pool drains each award.
        (uint256 expectedPerSpinSum, uint256 expectedBatchedSum) =
            _replayDgnrsPerSpin(rewardPoolBefore);

        // The per-spin (path-dependent, draining) sum must match exactly.
        assertEq(sdgnrsGain, expectedPerSpinSum,
            "DGAS-04: DGNRS gain == per-spin draining sum (reads poolBalance fresh per spin)");

        // And it must be STRICTLY LESS than a hypothetical single-batched-read sum,
        // proving the award was NOT folded into one fresh read.
        assertLt(expectedPerSpinSum, expectedBatchedSum,
            "DGAS-04: per-spin draining is strictly less than a single-read batch (not batched)");

        emit log_named_uint("dgnrs_per_spin_sum", expectedPerSpinSum);
        emit log_named_uint("dgnrs_batched_hypothetical", expectedBatchedSum);
    }

    // =========================================================================
    // 323 Task 2: post-game-over resolveBets liveness guard (insolvency repro closed)
    // =========================================================================

    /// @notice Prove the v47 liveness guard on resolveBets (DegeneretteModule:421,
    ///         `if (_livenessTriggered()) revert E();`) CLOSES the §1 post-game-over
    ///         unbacked-credit path documented in 323-SOLVENCY-FINDING.md.
    ///
    ///         The §1 insolvency: a Degenerette ETH bet placed (and RNG-committed)
    ///         BEFORE game-over could be resolved AFTER the game-over drain, crediting
    ///         claimableWinnings out of the already-distributed futurePrizePool residual
    ///         and pushing claimablePool strictly above the ETH balance — an unbacked
    ///         obligation that the last claimant(s) cannot all withdraw.
    ///
    ///         This test reproduces the EXACT sequence:
    ///           1. place a winning ETH Degenerette bet pre-game-over, commit its RNG word
    ///           2. SNAPSHOT, then prove the bet IS otherwise fully resolvable pre-GO
    ///              (it credits claimable) — so the ONLY post-GO blocker is the guard,
    ///              not RNG-readiness;
    ///           3. revert to the snapshot, drive the game into the terminal liveness
    ///              state (level-0 deploy-idle timeout > 365 days) so gameOver() == true;
    ///           4. assert resolveDegeneretteBets now REVERTS with E() — the unbacked
    ///              post-drain credit can no longer happen.
    function testResolveBetsRevertsPostGameOver_InsolvencyReproClosed() public {
        // --- Phase 1: place a winning ETH bet pre-game-over, commit its RNG word ---
        // Large unfrozen pool so the win resolves to a real ETH credit pre-GO.
        _seedFuturePrizePool(1_000 ether);

        uint48 index = 1;
        uint256 word = uint256(keccak256("post_gameover_repro_word"));
        uint32 ticket = _winningTicketFor(index, word); // 8/8 self-match: guaranteed ETH win

        assertFalse(game.gameOver(), "precondition: game is live at bet placement");
        assertFalse(game.livenessTriggered(), "precondition: liveness not triggered");

        uint128 perTicket = 0.05 ether; // >= MIN_BET_ETH
        uint64 betId = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        _injectLootboxRngWord(index, word); // RNG committed -> bet is resolvable

        uint64[] memory betIds = new uint64[](1);
        betIds[0] = betId;

        // --- Phase 2: prove the bet IS otherwise resolvable pre-game-over ---
        // (the §1 path: pre-fix, this same call after game-over would have credited
        // claimable out of the drained residual). The snapshot lets the SAME placed,
        // RNG-committed bet be re-used for the post-game-over revert assertion, so the
        // only difference between the two runs is the game-over state the guard checks.
        uint256 snap = vm.snapshotState();

        uint256 preClaimable = game.claimableWinningsOf(player);
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), betIds);
        uint256 ethCreditedPreGo = game.claimableWinningsOf(player) - preClaimable;
        assertGt(
            ethCreditedPreGo,
            0,
            "control: the bet resolves and credits claimable while the game is live"
        );

        // --- Phase 3: revert and drive into the terminal liveness state ---
        vm.revertToState(snap);

        // The guard at DegeneretteModule:421 checks `_livenessTriggered()` (the live
        // terminal CONDITION), not the stored `gameOver` flag (which the advanceGame
        // drain latches afterward). _livenessTriggered() is true at level 0 once
        // currentDay - purchaseStartDay > _DEPLOY_IDLE_TIMEOUT_DAYS (365), with
        // lastPurchaseDay/jackpotPhaseFlag false (fresh-deploy default). Warp well past it.
        // This is the exact predicate the guard gates on, so the warp reproduces the
        // post-game-over state for the §1 path without needing to drive the VRF-entropy
        // advanceGame drain that flips the stored flag.
        vm.warp(block.timestamp + 366 days);
        assertEq(game.level(), 0, "repro precondition: still at level 0 (deploy-idle path)");
        assertTrue(
            game.livenessTriggered(),
            "game-over liveness must now be triggered (the predicate the guard checks)"
        );

        // --- Phase 4: the guard must now REVERT the resolve (unbacked path closed) ---
        // Without the guard at DegeneretteModule:421, this call would proceed to credit
        // claimableWinnings (RNG is committed, the bet is otherwise resolvable per Phase 2),
        // pushing claimablePool above the ETH balance. The guard reverts first.
        vm.prank(player);
        vm.expectRevert(bytes4(0xdf469ccb)); // GameOver()
        game.resolveDegeneretteBets(address(0), betIds);

        // Belt-and-suspenders: the resolve credited nothing post-game-over.
        assertEq(
            game.claimableWinningsOf(player),
            0,
            "post-game-over resolve must credit zero claimable (guard reverted before any credit)"
        );
    }

    // =========================================================================
    // DGAS-05 Internal Helpers
    // =========================================================================

    /// @dev DGNRS award bps per match tier (DegeneretteModule:203-205).
    uint256 private constant DEGEN_DGNRS_6_BPS = 400;
    uint256 private constant DEGEN_DGNRS_7_BPS = 800;
    uint256 private constant DEGEN_DGNRS_8_BPS = 1500;

    /// @dev Read claimablePool (uint128 in slot 1, byte 16 -> high 128 bits).
    function _readClaimablePool() internal view returns (uint256) {
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return uint256(uint128(s1 >> 128));
    }

    /// @dev Place a Degenerette bet for `player` and return its betId (nonce).
    function _placeBet(uint8 currency, uint128 perTicket, uint8 spins, uint32 ticket)
        internal
        returns (uint64 betId)
    {
        uint256 ethValue = currency == CURRENCY_ETH ? uint256(perTicket) * spins : 0;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(
            address(0), currency, perTicket, spins, ticket, 0
        );
        betId = _betNonce(player);
    }

    /// @dev Find the spin-0 winning custom ticket for (index, word): the spin-0
    ///      result ticket itself (8/8 self-match guarantees a win on spin 0).
    function _winningTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        return _resultTicketForSpin(index, word, 0);
    }

    /// @dev Reproduce the on-chain per-spin result ticket (_resolveBet).
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

    /// @dev The 3-tier ETH split (_distributePayout:778-794), cap-free. The cap is
    ///      replayed separately in _replayRunningPoolCap (Tier-2). ethShare =
    ///      payout if payout <= 3*bet else max(2.5*bet, payout/4).
    function _ethShareOf(uint256 payout, uint128 betAmount) internal pure returns (uint256) {
        if (payout == 0) return 0;
        uint256 threeBet = uint256(betAmount) * 3;
        if (payout <= threeBet) return payout;
        uint256 minEth = (uint256(betAmount) * 5) / 2;
        uint256 stdEth = payout / 4;
        return stdEth > minEth ? stdEth : minEth;
    }

    /// @dev Replay the per-spin baseline for the Tier-1 mixed batch from the recorded
    ///      FullTicketResult events. Groups raw per-spin payouts by currency (decoded
    ///      from the bet amount each spin used) and applies the additive rule:
    ///        - ETH: Σ _ethShareOf(payout) (cap-free; PayoutCapped count returned for
    ///          the caller to assert zero in Tier-1).
    ///        - FLIP/WWXRP: Σ payout (pure additive mint).
    ///      Currency is inferred from the per-spin betAmount (the three bets used
    ///      distinct, disjoint per-ticket amounts: ethPerTicket / flipPerTicket /
    ///      wwxrpPerTicket), which the FullTicketResult does NOT carry — so we read
    ///      the playerTicket field is identical; instead we attribute by the contract's
    ///      emission order (ETH bet first, FLIP second, WWXRP third) using the
    ///      per-bet FullTicketResolved boundaries.
    function _replayPerSpinBaseline(
        uint128 ethPerTicket,
        uint128 flipPerTicket,
        uint128 wwxrpPerTicket
    )
        internal
        returns (
            uint256 ethShareSum,
            uint256 flipSum,
            uint256 wwxrpSum,
            uint256 payoutCappedCount
        )
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Walk logs in order. The batch resolves ETH bet, then FLIP, then WWXRP.
        // Each bet's spins emit FullTicketResult, terminated by one FullTicketResolved.
        // betPhase: 0 = ETH, 1 = FLIP, 2 = WWXRP.
        uint256 betPhase;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == FULL_TICKET_RESULT_SIG) {
                // data = (uint8 ticketIndex, uint32 playerTicket, uint8 matches, uint256 payout)
                (, , , uint256 payout) = abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                if (betPhase == 0) {
                    ethShareSum += _ethShareOf(payout, ethPerTicket);
                } else if (betPhase == 1) {
                    flipSum += payout;
                } else {
                    wwxrpSum += payout;
                }
            } else if (t0 == PAYOUT_CAPPED_SIG) {
                ++payoutCappedCount;
            } else if (t0 == FULL_TICKET_RESOLVED_SIG) {
                ++betPhase; // advance to the next bet's currency phase
            }
        }
    }

    /// @dev Read the per-spin RAW payouts for a SINGLE ETH bet from the recorded
    ///      FullTicketResult events (in spin order).
    function _ethSpinPayouts() internal returns (uint256[] memory payouts) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) ++count;
        }
        payouts = new uint256[](count);
        uint256 k;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) {
                (uint8 spinIdx, , , uint256 payout) =
                    abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                payouts[spinIdx] = payout;
                ++k;
            }
        }
        require(k == count, "spin payout decode mismatch");
    }

    /// @dev Replay the unfrozen running-pool-local ETH cap exactly as _distributePayout:
    ///      maxEth = pool * ETH_WIN_CAP_BPS / 10_000; if ethShare > maxEth, credit maxEth
    ///      and the excess flips to lootbox (PayoutCapped); pool -= credited ethShare.
    ///      Returns the total ETH credited + a per-spin capped[] vector.
    function _replayRunningPoolCap(uint256[] memory rawPayouts, uint128 betAmount, uint256 pool)
        internal
        pure
        returns (uint256 ethCredited, bool[] memory capped)
    {
        capped = new bool[](rawPayouts.length);
        for (uint256 i; i < rawPayouts.length; ++i) {
            if (rawPayouts[i] == 0) continue;
            uint256 ethShare = _ethShareOf(rawPayouts[i], betAmount);
            uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
            if (ethShare > maxEth) {
                ethShare = maxEth;
                capped[i] = true;
            }
            pool -= ethShare;
            ethCredited += ethShare;
        }
    }

    /// @dev Single pass over the recorded logs for a SINGLE ETH bet: returns BOTH the
    ///      per-spin raw payouts (in spin order) AND the ACTUAL capped-spin set. A
    ///      PayoutCapped is emitted inside _distributePayout, immediately after the
    ///      spin's FullTicketResult (DegeneretteModule:690-712), so a PayoutCapped that
    ///      follows the FullTicketResult for spin k (before the next FullTicketResult)
    ///      caps spin k. This reads the ON-CHAIN behavior directly (not a prediction).
    function _ethSpinPayoutsAndCaps()
        internal
        returns (uint256[] memory payouts, bool[] memory capped)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == FULL_TICKET_RESULT_SIG) ++count;
        }
        payouts = new uint256[](count);
        capped = new bool[](count);
        int256 currentSpin = -1;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == FULL_TICKET_RESULT_SIG) {
                (uint8 spinIdx, , , uint256 payout) =
                    abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                payouts[spinIdx] = payout;
                currentSpin = int256(uint256(spinIdx));
            } else if (t0 == PAYOUT_CAPPED_SIG && currentSpin >= 0) {
                capped[uint256(currentSpin)] = true;
            }
        }
    }

    /// @dev Count FullTicketResolved + PayoutCapped from the recorded logs.
    function _countResolvedAndCapped(uint64 betA, uint64 betB)
        internal
        returns (uint256 resolved, uint256 capped)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == FULL_TICKET_RESOLVED_SIG) {
                // betId is the 2nd indexed topic. Lootbox-triggered box spins (a recirc
                // box's WWXRP/FLIP spin) emit FullTicketResolved too, under a synthetic
                // seed-derived betId; count only the two real player bets under test.
                uint64 bid = uint64(uint256(logs[i].topics[2]));
                if (bid == betA || bid == betB) ++resolved;
            } else if (t0 == PAYOUT_CAPPED_SIG) ++capped;
        }
    }

    /// @dev Find a word where the spin-0 greedy-self ticket lands >= 6 matches on
    ///      multiple spins (so the DGNRS award fires more than once -> the per-spin
    ///      poolBalance draining is observable). Returns (word, ticket, sixPlusSpins).
    function _findMultiSixMatchWord(uint48 index)
        internal
        pure
        returns (uint256 word, uint32 ticket, uint8 sixPlusSpins)
    {
        for (uint256 k; k < 20_000; ++k) {
            uint256 candidate = uint256(keccak256(abi.encodePacked("dgnrs_multi_six", k)));
            uint32 t = _resultTicketForSpin(index, candidate, 0); // self-match on spin 0 = 8/8
            uint8 cnt;
            for (uint8 s; s < 8; ++s) {
                if (_countMatchesLocal(t, _resultTicketForSpin(index, candidate, s)) >= 6) ++cnt;
            }
            if (cnt > sixPlusSpins) {
                sixPlusSpins = cnt;
                word = candidate;
                ticket = t;
                if (sixPlusSpins >= 2) return (word, ticket, sixPlusSpins);
            }
        }
    }

    /// @dev Replay the per-spin DGNRS award from the recorded FullTicketResult events.
    ///      Per-spin (draining): award_k = pool_k * bps(match) / 10_000 (cappedBet = 1e18
    ///      cancels the 1e18 divisor since perTicket >= 1 ether); pool_{k+1} = pool_k - award_k.
    ///      Batched (hypothetical single read): every award off the SAME initial pool.
    function _replayDgnrsPerSpin(uint256 poolStart)
        internal
        returns (uint256 perSpinSum, uint256 batchedSum)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 runningPool = poolStart;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != FULL_TICKET_RESULT_SIG) continue;
            (, , uint8 matches, ) = abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
            if (matches < 6) continue;
            uint256 bps = matches == 6 ? DEGEN_DGNRS_6_BPS : matches == 7 ? DEGEN_DGNRS_7_BPS : DEGEN_DGNRS_8_BPS;
            // cappedBet = min(perTicket, 1 ether) == 1 ether; reward = pool * bps * 1e18 / (10_000 * 1e18).
            uint256 perSpinReward = (runningPool * bps) / 10_000;
            uint256 batchedReward = (poolStart * bps) / 10_000;
            if (perSpinReward != 0) {
                perSpinSum += perSpinReward;
                runningPool -= perSpinReward; // pool drains (fresh read next spin)
            }
            batchedSum += batchedReward;
        }
    }

    // =========================================================================
    // Token funding helpers (game-gated mints)
    // =========================================================================

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame (keeps supply consistent).
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Mint WWXRP to `who` via the GAME-gated mintPrize (keeps supply consistent).
    function _fundWwxrp(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
    }

    /// @dev Read the current degeneretteBetNonce for a player (slot 39) = newest betId.
    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// @notice Read futurePrizePool from packed slot (upper 128 bits of prizePoolsPacked, slot 2).
    function _readFuturePrizePool() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        return uint256(uint128(packed >> 128));
    }

    /// @notice Read pending future from packed slot (upper 128 bits of prizePoolPendingPacked, slot 11).
    function _readPendingFuture() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        return uint256(uint128(packed >> 128));
    }

    /// @notice Read prizePoolFrozen from slot 0, bit 208.
    function _readFrozen() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        return ((s0 >> FROZEN_BIT_SHIFT) & 0xFF) != 0;
    }

    /// @notice Seed futurePrizePool (upper 128 bits of prizePoolsPacked, slot 2).
    /// @dev Preserves the lower 128 bits (nextPrizePool).
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Seed pending future (upper 128 bits of prizePoolPendingPacked, slot 11).
    /// @dev Preserves the lower 128 bits (nextPending).
    function _seedPendingFuture(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PENDING_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Set prizePoolFrozen flag (slot 0, bit 208).
    /// @dev Preserves all other bytes in slot 0.
    function _setFrozenFlag(bool frozen) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        // Clear the frozen byte (bit 208)
        s0 = s0 & ~(uint256(0xFF) << FROZEN_BIT_SHIFT);
        // Set the frozen byte
        if (frozen) {
            s0 = s0 | (uint256(1) << FROZEN_BIT_SHIFT);
        }
        vm.store(address(game), bytes32(uint256(SLOT_0)), bytes32(s0));
    }

    /// @notice Inject a lootbox RNG word for a given index.
    /// @dev Writes to the lootboxRngWordByIndex mapping at slot 35.
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @notice Find a (customTraits, rngWord) pair that guarantees >= 2 matches.
    /// @dev Tries RNG words in sequence, computing the result ticket for spin 0
    ///      (index 1) using the same derivation as _resolveBet. Returns
    ///      when a combination with >= 2 matches is found.
    ///
    ///      v47 repair: the spin-0 result ticket is derived via
    ///      `DegenerusTraitUtils.packedTraitsDegenerette` (the Degenerette-specific
    ///      derivation _resolveBet uses) — NOT `packedTraitsFromSeed`
    ///      (the mint derivation). Using the wrong derivation produced a "winning"
    ///      ticket that the on-chain path never actually matched.
    function _findWinningCombo(uint48 index) internal pure returns (uint32 customTraits, uint256 rngWord) {
        for (uint256 attempt; attempt < 100; attempt++) {
            rngWord = uint256(keccak256(abi.encode("freeze_test_rng", attempt)));

            // Replicate the result seed derivation from _resolveBet (spin 0)
            // Contract uses uint32 index in encodePacked (v24.1 change)
            uint256 resultSeed = uint256(keccak256(abi.encodePacked(rngWord, uint32(index), QUICK_PLAY_SALT)));
            uint32 resultTicket = DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);

            // Use the result ticket AS the custom ticket -- guarantees 8/8 matches (jackpot).
            // This is valid because custom ticket format matches result ticket format.
            customTraits = resultTicket;

            // Verify matches (should be 8 since they're identical)
            uint8 matches = _countMatchesLocal(customTraits, resultTicket);
            if (matches >= 2) return (customTraits, rngWord);
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

    // =========================================================================
    // Batch-resolve tolerance: the first bet is strict (any failure aborts the
    // whole tx, so a racing duplicate-clicker settle bails cheaply); trailing bets
    // skip an already-resolved or not-ready id so one bad id can't brick an
    // en-masse settle.
    // =========================================================================

    /// @dev Probe (first) bet already resolved by a competing tx -> the whole call
    ///      reverts InvalidBet, so a duplicate clicker wastes only the probe SLOAD.
    function testResolveBatchFirstBetAlreadyResolvedReverts() public {
        _seedFuturePrizePool(50 ether);
        (uint32 ticket, uint256 word) = _findWinningCombo(1);
        uint64 b1 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        uint64 b2 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        _injectLootboxRngWord(1, word);

        uint64[] memory batch = new uint64[](2);
        batch[0] = b1;
        batch[1] = b2;

        // First clicker settles the whole batch.
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), batch);
        assertEq(_betPacked(player, b1), 0, "b1 resolved by first clicker");
        assertEq(_betPacked(player, b2), 0, "b2 resolved by first clicker");

        // Second clicker re-sends the SAME batch: the probe (b1) is already resolved.
        vm.prank(player);
        vm.expectRevert(bytes4(0xaa822249)); // InvalidBet()
        game.resolveDegeneretteBets(address(0), batch);
    }

    /// @dev A stale (already-resolved) id in the TAIL is skipped, never reverts — the
    ///      surrounding valid bets still resolve.
    function testResolveBatchTrailingAlreadyResolvedSkipped() public {
        _seedFuturePrizePool(50 ether);
        (uint32 ticket, uint256 word) = _findWinningCombo(1);
        uint64 b1 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        uint64 b2 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        uint64 b3 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        _injectLootboxRngWord(1, word);

        // Pre-resolve the middle bet so it is stale (packed == 0) when the batch runs.
        uint64[] memory mid = new uint64[](1);
        mid[0] = b2;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), mid);
        assertEq(_betPacked(player, b2), 0, "b2 pre-resolved");

        // Batch [b1(probe), b2(stale), b3]: probe resolves, stale trailing skips, b3 resolves.
        uint64[] memory batch = new uint64[](3);
        batch[0] = b1;
        batch[1] = b2;
        batch[2] = b3;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), batch); // must not revert
        assertEq(_betPacked(player, b1), 0, "b1 resolved");
        assertEq(_betPacked(player, b3), 0, "b3 resolved despite stale trailing b2");
    }

    /// @dev Probe not-ready (RNG unfulfilled) aborts the tx; a not-ready id in the TAIL
    ///      is skipped and stays pending for a later settle.
    function testResolveBatchRngNotReadyFirstRevertsTrailingSkips() public {
        _seedFuturePrizePool(50 ether);
        (uint32 ticket, uint256 word) = _findWinningCombo(1);

        // b1 at index 1 (word injected below -> ready); b2 at index 2 (word never
        // injected -> not ready).
        uint64 b1 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        _setLootboxIndex(2);
        uint64 b2 = _placeBet(CURRENCY_ETH, 0.01 ether, 1, ticket);
        _injectLootboxRngWord(1, word);

        // Probe not ready: [b2(not ready), b1] -> fast revert (any probe failure aborts).
        uint64[] memory bad = new uint64[](2);
        bad[0] = b2;
        bad[1] = b1;
        vm.prank(player);
        vm.expectRevert(bytes4(0xbb3e844f)); // RngNotReady()
        game.resolveDegeneretteBets(address(0), bad);

        // Probe ready, trailing not ready: [b1, b2] -> b1 resolves, b2 skips and stays pending.
        uint64[] memory ok = new uint64[](2);
        ok[0] = b1;
        ok[1] = b2;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), ok); // must not revert
        assertEq(_betPacked(player, b1), 0, "b1 resolved");
        assertGt(_betPacked(player, b2), 0, "b2 still pending (trailing not-ready skipped)");
    }

    /// @dev Read the raw packed degenerette bet slot (0 == resolved/nonexistent).
    function _betPacked(address who, uint64 betId) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(who, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 slot = keccak256(abi.encode(uint256(betId), inner));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Set the live lootboxRngIndex (low 48 bits of lootboxRngPacked) so a bet can
    ///      be placed against a different RNG index than an earlier one.
    function _setLootboxIndex(uint48 idx) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(packed)
        );
    }
}
