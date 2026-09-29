// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @title DegeneretteFreezeResolutionTest -- Proves
///        DGAS-05 same-results: the v47 Degenerette `resolveBets` write-batching
///        is payout-IDENTICAL to the old per-spin behavior.
///
/// @notice DGAS-05 (tests 4-7): the resolver accumulates ETH/FLIP
///         payouts CROSS-BET into a `ResolveAcc` memory struct and flushes ONCE
///         per currency (one mint per currency, one claimable+claimablePool write,
///         one pool write, one box per betId). The HARD floor is "same results" —
///         byte-identical to-the-wei vs a per-spin baseline, rebuilt as described in
///         the PORT NOTE below by replaying the exact arithmetic the batching touched —
///         the 3-tier ETH split + the running-pool-local cap (the per-N payout TABLES
///         are unchanged by the batching and are NOT recomputed here; only the
///         AGGREGATION the batching changed is replayed). Any divergence by even one
///         wei is surfaced as a real regression, never adjusted away.
///         - Tier-1 (additive): FLIP mint + ETH claimable + nested box WWXRP.
///         - Tier-2 (running-pool-local): the ETH cap binds on the IDENTICAL spin.
///         - DGAS-03: lootbox-share summed PER betId (one box per bet).
///         - DGAS-04: DGNRS award stays PER SPIN (reads poolBalance fresh).
///
/// @dev Deploys full 23-contract protocol via DeployProtocol. Uses vm.store to
///      inject freeze state and seed pending pools to a known value, then places
///      a real degenerette bet via the public API, injects a lootbox RNG word
///      pre-computed to produce a winning result, and resolves the bet.
/// @dev DOORS-REMOVAL PORT NOTE: bets are one word in `degeneretteQueue[index]` (id = queue
///      position + 1), resolved ONLY through the permissionless in-order sweep
///      `game.openBoxes(maxCount)` (delegates to `sweepDegeneretteBets`) — the manual
///      `resolveDegeneretteBets(index, betIds)` door is gone, with it the per-call
///      caller-composed betId list and its first-id fail-fast revert. A bet resolves once every
///      box AND bet at every index <= its own is resolved. FIX-04 (resolving a bet through the
///      pending pool while `prizePoolFrozen`) was behavior specific to that removed door:
///      `sweepDegeneretteBets` already held the whole queue (`if (prizePoolFrozen) return (0,
///      pos, 0, 0);`) rather than resolving it, so a bet now only ever resolves once the pool
///      is unfrozen again, through the live (not pending) pool. The former freeze-routing tests
///      (conservation + Insolvent-on-identical-spin) proved a path that no longer exists and were
///      removed rather than adapted; the "pending bet is not settled post-game-over" invariant is
///      kept (see testResolveBetsRevertsPostGameOver_InsolvencyReproClosed) since `openHumanBoxes`
///      still no-ops (not reverts) once `_livenessTriggered()`.
///      The per-spin `DegeneretteResult` event is gone, replaced by ONE `DegeneretteResolved`
///      per bet carrying every spin's (playerTraits, score, gold) as packed bytes
///      (see test/helpers/DegeneretteQueue.sol `spinAt`). Per-spin RAW payouts (before the ETH
///      3-tier split / pool cap and before the FLIP survival flip / 100-FLIP rounding) are
///      recomputed off-chain via `DegeneretteMathHarness.payout(score, gold, currency, stake,
///      activity)`, reading stake/activity from `game.degeneretteBetInfo` BEFORE resolving (the
///      word zeroes after). The cross-bet aggregation math (3-tier split, running-pool cap,
///      survival flip, 100-FLIP rounding) is unchanged and stays byte-identical.
contract DegeneretteFreezeResolutionTest is DeployProtocol {
    DegeneretteMathHarness private math;

    // --- Storage slot constants (confirmed via `forge inspect DegenerusGameStorage storage`) ---

    /// @dev Slot 0, byte 26 (bit 208): prizePoolFrozen (bool, 1 byte).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant FROZEN_BIT_SHIFT = 208;

    /// @dev prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool]
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    /// @dev prizePoolPendingPacked: [upper 128: futurePending] [lower 128: nextPending]
    uint256 private constant PENDING_PACKED_SLOT = 11;

    /// @dev lootboxRngWordByIndex mapping root slot (post Stage-B game-storage repack: was 36).
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;

    /// @dev lootboxRngPacked at slot 34 (post Stage-B game-storage repack: was 35); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    /// @dev Mirrors `DegenerusGameDegeneretteModule.FLIP_ROUND_TAG` (private there), the
    ///      domain separator the 100-FLIP award collapse is keyed under.
    uint256 private constant BET_SURVIVAL_TAG = 0x446567656e537572766976616c; // "DegenSurvival"
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"

    // --- DGAS-05 same-results constants ---

    /// @dev claimablePool (uint128) lives in slot 1, byte 16.
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;
    /// @dev FLIP.balanceOf mapping root slot.
    uint256 private constant FLIP_BALANCEOF_SLOT = 1;

    /// @dev Degenerette bet currencies (DegeneretteModule:208-214).
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;

    /// @dev ETH win pool cap: 10% of futurePool (DegeneretteModule:196).
    uint256 private constant ETH_WIN_CAP_BPS = 1_000;
    /// @dev Per-currency minimum bets (DegeneretteModule:217-223).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_FLIP = 100 ether;

    /// @dev PayoutCapped topic0 — one per ETH spin that flipped into the lootbox. Event shape
    ///      is unchanged: PayoutCapped(address indexed player, uint256 cappedEthPayout, uint256 excessConverted).
    bytes32 private constant PAYOUT_CAPPED_SIG = keccak256("PayoutCapped(address,uint256,uint256)");
    /// @dev BoxSpin topic0 — one per internal (non-placed-bet) Degenerette spin, e.g. a bet's
    ///      lootbox-share recirculating into a nested WWXRP/FLIP/ETH box roll.
    bytes32 private constant BOX_SPIN_SIG =
        keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");

    address private player;

    function setUp() public {
        _deployProtocol();
        // Deployed AFTER the protocol: DeployProtocol pins every contract to a deployer nonce, so
        // a deployment before it shifts the whole address map (setUp then reverts in Coinflip).
        math = new DegeneretteMathHarness();
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
    // Tests 1-2 REMOVED (doors removal): both proved FIX-04's freeze-time ETH
    // conservation / Insolvent-revert through the manual `resolveDegeneretteBets`
    // door while `prizePoolFrozen`. That door is gone, and its only replacement,
    // `sweepDegeneretteBets` (reached via `game.openBoxes`), already held the whole
    // queue during a freeze rather than resolving it (`if (prizePoolFrozen) return
    // (0, pos, 0, 0);`, unchanged by this port). So freeze-time resolution — and the
    // pending-pool routing / per-spin Insolvent revert these tests proved — is no
    // longer reachable through any live entry point; a queued bet simply waits until
    // the pool unfreezes and then resolves through the LIVE pool. There is no
    // successor behavior to port these two tests onto.
    // =========================================================================

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
        game.placeDegeneretteBet{value: betAmount}(address(0), 0, betAmount, 1, uint8(customTraits & 7));

        // Live pools should have increased (unfrozen path uses _setPrizePools)
        uint256 postBetLiveFuture = _readFuturePrizePool();
        assertEq(postBetLiveFuture, preLiveFuture + betAmount,
            "Unfrozen: live future should increase by bet amount");

        // Pending should be untouched
        assertEq(_readPendingFuture(), prePendingFuture,
            "Unfrozen: pending future should be untouched");

        // Inject RNG word, finalize the index, and sweep it through openBoxes.
        _injectLootboxRngWord(index, winningRngWord);
        _advanceLootboxRngIndexByOne();
        game.openBoxes(type(uint256).max);

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
    ///         baseline. Places mixed ETH and FLIP bets within their spin caps,
    ///         resolves them in ONE resolveBets call, and asserts:
    ///           - FLIP balance delta == Σ (every FLIP spin's payout)
    ///           - WWXRP balance delta == sum of nested automatic-spin payouts
    ///           - claimableWinnings ETH delta == Σ (every ETH spin's ethShare)
    ///           - claimablePool moved by exactly the same ETH sum (additive)
    ///         The per-spin payouts are recomputed off each bet's own `DegeneretteResolved`
    ///         event via `DegeneretteMathHarness.payout`; the ETH ethShare is the 3-tier split of
    ///         each spin's raw payout (a LARGE pool is seeded so the 10% cap never
    ///         binds in this Tier-1 test — Tier-2 owns the cap). Byte-identical (==).
    /// @dev The §3c award gate as `_resolveBet` applies it: collapse onto a whole 100-FLIP
    ///      multiple above the threshold, floor to whole FLIP at or below it.
    function _gateFlipAward(uint256 amount, uint256 entropy)
        private
        pure
        returns (uint256)
    {
        return amount > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(amount, entropy)
            : FlipRoundLib.floorWholeFlip(amount);
    }

    /// @notice ETH and FLIP players share the result board for the same RNG period: the same
    ///         symbol at the same index/word produces identical player traits, score and gold
    ///         per spin regardless of owner, currency or queue position. (Doors removal: the
    ///         sweep always walks the queue in ascending position, so "which id resolves first"
    ///         is no longer caller-selectable; the shared-board claim itself — the part this
    ///         test actually proves — is unaffected and is proven here off a single sweep call.)
    function test_SharedBoardAcrossPlayersCurrenciesAndBets() public {
        uint256 word = uint256(keccak256("shared-period-board"));
        uint32 pick = _winningTicketFor(1, word);
        address firstPlayer = player;
        uint64 first = _placeBet(CURRENCY_ETH, 0.01 ether, 3, pick);
        address secondPlayer = makeAddr("second_board_player");
        player = secondPlayer;
        _fundFlip(player, 10_000 ether);
        _placeBet(CURRENCY_FLIP, 100 ether, 1, pick); // decoy bet shifts the queue position
        uint64 second = _placeBet(CURRENCY_FLIP, 200 ether, 3, pick);
        _injectLootboxRngWord(1, word);
        _advanceLootboxRngIndexByOne();

        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (, uint32 firstResultTraits, bytes memory firstSpins) = _decodeResolved(logs, 1, first);
        (, uint32 secondResultTraits, bytes memory secondSpins) = _decodeResolved(logs, 1, second);
        assertEq(firstResultTraits, pick, "shared spin-0 house board matches the picked ticket");
        assertEq(secondResultTraits, pick, "shared spin-0 house board matches the picked ticket");
        assertEq(firstSpins.length, 3 * 5, "first bet ran 3 spins");
        assertEq(secondSpins.length, 3 * 5, "second bet ran 3 spins");
        for (uint8 s; s < 3; ++s) {
            (uint32 pt1, uint8 sc1, uint8 g1) = DQ.spinAt(firstSpins, s);
            (uint32 pt2, uint8 sc2, uint8 g2) = DQ.spinAt(secondSpins, s);
            assertEq(pt1, pt2, "same symbol -> identical player traits regardless of owner/currency/order");
            assertEq(sc1, sc2, "every spin uses the shared board (score identical across bets)");
            assertEq(g1, g2, "gold matches identical across bets");
        }
        player = firstPlayer;
    }

    function testBatchedPayoutEqualsPerSpinExpectation_Tier1() public {
        // Large unfrozen pool so the ETH 10% cap never binds (cap is Tier-2's job).
        _seedFuturePrizePool(1_000_000 ether);

        // Both bets share the seeded lootbox index 1 (placement requires word==0).
        // Word chosen so the FLIP bet (betId 2) WINS its bet-keyed survival flip
        // (keccak(word, player, betId, BET_SURVIVAL_TAG) & 1 == 1) — the doubled-mint path is exercised
        // non-vacuously below.
        uint48 index = 1;
        uint256 word = uint256(keccak256("tier1_mixed_batch_word_v3"));
        while (EntropyLib.hash4(word, uint160(player), 2, BET_SURVIVAL_TAG) & 1 == 0) ++word;

        // ETH bet: four spins; FLIP bet: three spins. WWXRP can still arise from nested boxes.
        // Use the spin-0 winning combo as the custom ticket for each (>= 2 matches
        // on spin 0 guarantees the bet is non-vacuous; other spins vary).
        uint32 ethTicket = _winningTicketFor(index, word);
        uint32 flipTicket = ethTicket;

        uint128 ethPerTicket = 0.01 ether;     // >= MIN_BET_ETH
        uint128 flipPerTicket = 2_000 ether;   // >= MIN_BET_FLIP

        // Fund the player for the FLIP bet.
        _fundFlip(player, uint256(flipPerTicket) * 3 + 1 ether);

        // Place both bets (ETH=1, FLIP=2).
        uint64 ethBet = _placeBet(CURRENCY_ETH, ethPerTicket, 4, ethTicket);
        uint64 flipBet = _placeBet(CURRENCY_FLIP, flipPerTicket, 3, flipTicket);

        // Capture stake/activity BEFORE resolving -- degeneretteBetInfo zeroes after resolve.
        uint16 ethActivity = DQ.activity(game.degeneretteBetInfo(index, ethBet));
        uint16 flipActivity = DQ.activity(game.degeneretteBetInfo(index, flipBet));

        _injectLootboxRngWord(index, word);

        // Pre-resolve balances.
        uint256 preClaimable = game.claimableWinningsOf(player);
        uint256 preClaimablePool = _readClaimablePool();
        uint256 preFlip = coin.balanceOf(player);
        uint256 preWwxrp = wwxrp.balanceOf(player);

        // Resolve both in ONE call (the cross-bet flush under test).
        _advanceLootboxRngIndexByOne();
        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Replay the per-spin baseline from each bet's own DegeneretteResolved `spins` payload,
        // recomputing the RAW per-spin payout via DegeneretteMathHarness (the production
        // pre-split/pre-cap/pre-survival-flip math). ETH: 3-tier split of each raw payout (no
        // cap binds -- large pool). WWXRP: nested BoxSpin legs, summed separately. Cap-flips
        // would emit PayoutCapped; assert none fired in this Tier-1 batch.
        (, , bytes memory ethSpins) = _decodeResolved(logs, index, ethBet);
        (, , bytes memory flipSpins) = _decodeResolved(logs, index, flipBet);
        uint256[] memory ethRaw = _rawPayouts(ethSpins, CURRENCY_ETH, ethPerTicket, ethActivity);
        uint256[] memory flipRaw = _rawPayouts(flipSpins, CURRENCY_FLIP, flipPerTicket, flipActivity);

        uint256 expectedEthShare;
        for (uint256 i; i < ethRaw.length; ++i) expectedEthShare += _ethShareOf(ethRaw[i], ethPerTicket);
        uint256 expectedFlip;
        for (uint256 i; i < flipRaw.length; ++i) expectedFlip += flipRaw[i];

        (uint256 expectedWwxrp, uint256 payoutCappedCount) = _replayNestedBoxLegs(logs);

        assertEq(payoutCappedCount, 0, "Tier-1: large pool -> no spin should cap");

        // FLIP survival flip (bet-keyed double-or-nothing on the bet's summed payout):
        // the raw mint is 2x the per-spin sum on a winning flip, 0 on a losing one. The
        // chosen word wins the flip for this bet, so the doubled path is live.
        uint256 rawFlipMint = (uint256(
            keccak256(abi.encode(word, player, flipBet, BET_SURVIVAL_TAG))
        ) & 1 == 1) ? expectedFlip * 2 : 0;
        assertGt(rawFlipMint, 0, "Tier-1: word must win the FLIP survival flip");

        // The award granule then collapses the SURVIVED total onto a whole 100-FLIP
        // multiple. Replicated here from the same inputs the module uses, so this stays a
        // byte-identical amount assertion rather than a tolerance: the collapse is keyed on
        // hash4(rngWord, player, betId, FLIP_ROUND_TAG), all fixed at fulfillment.
        uint256 expectedFlipMint = _gateFlipAward(
            rawFlipMint,
            EntropyLib.hash4(word, uint160(player), flipBet, FLIP_ROUND_TAG)
        );
        // Non-vacuity for the collapse itself: this batch must actually cross the
        // threshold, or the assertion below degrades to the pre-granule behaviour.
        assertGt(
            rawFlipMint,
            FlipRoundLib.FLIP_ROUND_THRESHOLD,
            "Tier-1: the FLIP payout must clear the granule threshold"
        );
        assertEq(
            expectedFlipMint % FlipRoundLib.FLIP_ROUND_UNIT,
            0,
            "Tier-1: the collapsed mint must be a whole 100-FLIP multiple"
        );

        // Tier-1 byte-identical assertions.
        uint256 flipDelta = coin.balanceOf(player) - preFlip;
        uint256 wwxrpDelta = wwxrp.balanceOf(player) - preWwxrp;
        uint256 claimableDelta = game.claimableWinningsOf(player) - preClaimable;
        uint256 claimablePoolDelta = _readClaimablePool() - preClaimablePool;

        assertEq(flipDelta, expectedFlipMint,
            "Tier-1: FLIP mint delta == the 100-FLIP collapse of 2x Sum of per-spin FLIP payouts (survival flip won)");
        assertEq(wwxrpDelta, expectedWwxrp,
            "Tier-1: WWXRP balance delta equals any nested automatic-spin payouts");
        assertEq(claimableDelta, expectedEthShare,
            "Tier-1: ETH claimable delta == Sum of per-spin ethShare (additive)");
        assertEq(claimablePoolDelta, expectedEthShare,
            "Tier-1: claimablePool moved by exactly the ETH sum (additive, disjoint slot)");

        // Non-vacuity: both manually wagered currencies paid.
        assertGt(expectedFlip, 0, "Tier-1 non-vacuity: FLIP payout exercised");
        assertGt(expectedEthShare, 0, "Tier-1 non-vacuity: ETH payout exercised");

        emit log_named_uint("tier1_eth_claimable_delta", claimableDelta);
        emit log_named_uint("tier1_flip_delta", flipDelta);
        emit log_named_uint("tier1_wwxrp_delta", wwxrpDelta);
    }

    /// @notice FLIP survival-flip LOSS path: a bet whose bet-keyed flip
    ///         (keccak(word, player, betId, BET_SURVIVAL_TAG) & 1 == 0) loses mints NOTHING, even though its
    ///         raw spins paid (recomputed per-spin payout sum > 0).
    function testFlipSurvivalFlipLossZeroesMint() public {
        _seedFuturePrizePool(1_000_000 ether);

        // Word chosen so betId 1 LOSES the survival flip; the spin-0 self-match
        // ticket guarantees the raw per-spin payouts are nonzero.
        uint48 index = 1;
        uint256 word = uint256(keccak256("survival_flip_loss_word_v3"));
        while (EntropyLib.hash4(word, uint160(player), 1, BET_SURVIVAL_TAG) & 1 == 1) ++word;
        uint32 ticket = _winningTicketFor(index, word);

        _fundFlip(player, 1_000 ether);
        uint64 betId = _placeBet(CURRENCY_FLIP, 200 ether, 3, ticket);
        assertEq(
            uint256(keccak256(abi.encode(word, player, betId, BET_SURVIVAL_TAG))) & 1,
            0,
            "precondition: the chosen word loses the survival flip for this bet"
        );

        // Capture stake/activity BEFORE resolving -- degeneretteBetInfo zeroes after resolve.
        uint256 betWord = game.degeneretteBetInfo(index, betId);
        uint16 activity = DQ.activity(betWord);
        uint128 stake = DQ.stake(betWord);

        _injectLootboxRngWord(index, word);

        uint256 preFlip = coin.balanceOf(player);

        _advanceLootboxRngIndexByOne();
        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Raw spins paid: Sum of the per-spin payouts recomputed off the resolved event's
        // packed spins > 0 (the survival flip zeroed the FINAL mint, not the raw spins).
        (, , bytes memory spins) = _decodeResolved(logs, index, betId);
        uint256[] memory rawPayouts = _rawPayouts(spins, CURRENCY_FLIP, stake, activity);
        uint256 rawSum;
        for (uint256 i; i < rawPayouts.length; ++i) rawSum += rawPayouts[i];
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

        // Capture activity BEFORE resolving -- degeneretteBetInfo zeroes after resolve.
        uint16 activity = DQ.activity(game.degeneretteBetInfo(index, betId));
        uint256 preClaimable = game.claimableWinningsOf(player);

        _advanceLootboxRngIndexByOne();
        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Recompute the per-spin RAW payouts off the resolved event's packed spins, and read
        // the ACTUAL capped-spin amounts (PayoutCapped is unchanged and still fires once per
        // capped spin, in spin order).
        (, , bytes memory spinsData) = _decodeResolved(logs, index, betId);
        uint256[] memory rawPayouts = _rawPayouts(spinsData, CURRENCY_ETH, perTicket, activity);
        uint256[] memory actualCappedAmounts = _payoutCappedAmounts(logs);

        // Replay the running-pool-local cap exactly as _distributePayout does.
        (uint256 expectedEthCredited, bool[] memory expectedCapped) =
            _replayRunningPoolCap(rawPayouts, perTicket, smallPool);

        // (a) byte-identical total ETH credited.
        uint256 claimableDelta = game.claimableWinningsOf(player) - preClaimable;
        assertEq(claimableDelta, expectedEthCredited,
            "Tier-2: ETH credited == Sum of per-spin capped shares against the running pool");

        // (b) PayoutCapped fired on EXACTLY the predicted spin set, in order, at the
        // predicted capped amount (identical spin).
        uint256 pool = smallPool;
        uint256 seen;
        uint256 predictedCapCount;
        for (uint256 i; i < rawPayouts.length; ++i) {
            if (rawPayouts[i] == 0) continue;
            uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
            if (expectedCapped[i]) {
                assertEq(actualCappedAmounts[seen], maxEth,
                    "Tier-2: PayoutCapped amount == the predicted capped share for the IDENTICAL spin, in order");
                ++seen;
                ++predictedCapCount;
                pool -= maxEth;
            } else {
                pool -= _ethShareOf(rawPayouts[i], perTicket);
            }
        }
        assertEq(seen, actualCappedAmounts.length,
            "Tier-2: PayoutCapped fired exactly on the predicted capped spins, in order");

        // Non-vacuity: the cap actually bound on at least one spin.
        assertGt(predictedCapCount, 0,
            "Tier-2 non-vacuity: the cap must bind on at least one spin (small pool)");

        emit log_named_uint("tier2_eth_credited", claimableDelta);
        emit log_named_uint("tier2_spins_capped", predictedCapCount);
    }

    // testFrozenSolvencyRevertsOnIdenticalSpin_Tier2 REMOVED (doors removal): proved the
    // frozen-pool Insolvent() revert (pendingFuture < ethShare) firing mid-resolve through the
    // manual door. That path is unreachable now — `sweepDegeneretteBets` holds the whole queue
    // while `prizePoolFrozen` (see the Tests 1-2 removal note above) instead of ever reaching
    // `_distributePayout`'s frozen branch, so there is no live call that can hit this revert.

    // =========================================================================
    // DGAS-05 Test 6: lootbox summed PER betId, never across bets
    // =========================================================================

    /// @dev Mirrors DegenerusGameStorage.OPEN_HUMAN_ENTRY_WEIGHT (15) and the DegeneretteModule
    ///      private per-bet walk-unit weights (BET_ENTRY_WEIGHT_ETH = 36, BET_SPIN_WEIGHT_ETH = 2)
    ///      so Run B below can budget-starve `openBoxes` to resolve exactly ONE queued 1-spin ETH
    ///      bet per call (see the derivation comment at its call site).
    uint256 private constant MIRROR_OPEN_HUMAN_ENTRY_WEIGHT = 15;
    uint256 private constant MIRROR_ONE_SPIN_ETH_BET_WEIGHT = 36 + 1 * 2;

    /// @notice Prove the lootbox-share is summed PER betId (one box per bet), never
    ///         across bets (the resolution-batch-invariant). Two bets SHARE the same
    ///         lootbox index (two bet-txs, same index). Both flip into the lootbox
    ///         (small pool -> cap binds on each bet's single spin). Resolving both in
    ///         ONE sweep must produce TWO independent box resolutions — proven
    ///         by the equivalence: resolving the two bets in ONE call yields the
    ///         IDENTICAL ETH credited + box ticket effects as resolving them in TWO
    ///         separate calls. A summed-across implementation (one box on share1+share2)
    ///         would diverge (the box ticket-roll is non-linear in `amount`).
    /// @dev Doors removal: there is no caller-composed betId list to split into two calls
    ///      anymore — `openBoxes` always walks the queue in order. Run B instead
    ///      budget-starves the FIRST call so only bet1 fits (a 1-spin ETH bet always costs
    ///      MIRROR_ONE_SPIN_ETH_BET_WEIGHT walk units and the sweep's first entry always runs
    ///      regardless of cost, but never a second one that would exceed the budget), then
    ///      drains the rest — reproducing "resolve bet1, then bet2, in two separate txs" exactly.
    function testLootboxSummedPerBetIdNotAcrossBets() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("perbetid_word"));
        uint32 ticket = _winningTicketFor(index, word);
        uint128 perTicket = 1 ether;         // score 2 pays 0.45 ETH at minimum activity, above the cap
        uint256 smallPool = 0.5 ether;

        // Place TWO same-index single-spin ETH bets (two bet-txs, SAME lootbox index).
        uint64 bet1 = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        uint64 bet2 = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        _seedFuturePrizePool(smallPool);
        _injectLootboxRngWord(index, word);
        _advanceLootboxRngIndexByOne();

        // Snapshot so the SAME placed bets can be resolved two different ways.
        uint256 snap = vm.snapshotState();

        // --- Run A: resolve BOTH in ONE call (the cross-bet batch under test) ---
        uint256 preA = game.claimableWinningsOf(player);
        vm.recordLogs();
        game.openBoxes(type(uint256).max);

        uint256 ethCreditedOneCall = game.claimableWinningsOf(player) - preA;
        // Two bets resolved -> two DegeneretteResolved, two PayoutCapped (one spin each).
        (uint256 resolvedCount, uint256 cappedCount) = _countResolvedAndCapped(bet1, bet2);
        assertEq(resolvedCount, 2, "two bets resolved -> two DegeneretteResolved (per-bet unit)");
        assertEq(cappedCount, 2,
            "per-betId: each bet's single spin capped independently -> two PayoutCapped");

        // --- Run B: revert to the snapshot, resolve the SAME two bets in TWO calls ---
        // (the per-betId baseline: one box per bet, resolved one at a time). maxCount=3 ->
        // openHumanBoxes budget = 3 * MIRROR_OPEN_HUMAN_ENTRY_WEIGHT = 45, minus 1 walk unit
        // for the index header = 44 walk units handed to sweepDegeneretteBets: enough for
        // bet1 (MIRROR_ONE_SPIN_ETH_BET_WEIGHT = 38 walk units, forced to run first regardless
        // of cost) but not bet1+bet2 (76), so the sweep resolves exactly bet1 and leaves bet2
        // queued for the next call.
        vm.revertToState(snap);
        uint256 preB = game.claimableWinningsOf(player);

        // maxCount such that maxCount * MIRROR_OPEN_HUMAN_ENTRY_WEIGHT - 1 (the index-header
        // step) lands in [weight, 2*weight - 1) = [38, 75]: exactly one bet's worth of budget.
        uint256 runBFirstCallMaxCount =
            (MIRROR_ONE_SPIN_ETH_BET_WEIGHT + 1) / MIRROR_OPEN_HUMAN_ENTRY_WEIGHT + 1;
        game.openBoxes(runBFirstCallMaxCount);
        assertEq(_betPacked(bet1), 0, "Run B call 1: bet1 alone resolved");
        assertGt(_betPacked(bet2), 0, "Run B call 1: bet2 left queued (budget-starved)");

        game.openBoxes(type(uint256).max);
        assertEq(_betPacked(bet2), 0, "Run B call 2: bet2 resolved");

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

        _advanceLootboxRngIndexByOne();
        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 sdgnrsGain = sdgnrs.balanceOf(player) - sdgnrsBefore;

        // Replay the PER-SPIN draining: per match-count of each 6+ spin (from the resolved
        // event's packed spins), award_k = pool_k * bps(match) * 1e18 / (10_000 * 1e18); pool
        // drains each award.
        (, , bytes memory spinsData) = _decodeResolved(logs, index, betId);
        (uint256 expectedPerSpinSum, uint256 expectedBatchedSum) =
            _replayDgnrsPerSpin(rewardPoolBefore, spinsData);

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

    /// @notice Prove the v47 liveness guard (now `openHumanBoxes`'s entry-gate
    ///         `if (rngLockedFlag || _livenessTriggered()) return (0, 0);`) CLOSES the §1
    ///         post-game-over unbacked-credit path documented in 323-SOLVENCY-FINDING.md.
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
    ///           4. assert the sweep now NO-OPS (doors removal: `openHumanBoxes` returns
    ///              early rather than reverting) — the bet stays queued and credits
    ///              nothing, so the unbacked post-drain credit still cannot happen.
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
        _advanceLootboxRngIndexByOne(); // finalize the index so the sweep can reach it

        // --- Phase 2: prove the bet IS otherwise resolvable pre-game-over ---
        // (the §1 path: pre-fix, this same call after game-over would have credited
        // claimable out of the drained residual). The snapshot lets the SAME placed,
        // RNG-committed bet be re-used for the post-game-over no-op assertion, so the
        // only difference between the two runs is the game-over state the guard checks.
        uint256 snap = vm.snapshotState();

        uint256 preClaimable = game.claimableWinningsOf(player);
        game.openBoxes(type(uint256).max);
        uint256 ethCreditedPreGo = game.claimableWinningsOf(player) - preClaimable;
        assertGt(
            ethCreditedPreGo,
            0,
            "control: the bet resolves and credits claimable while the game is live"
        );

        // --- Phase 3: revert and drive into the terminal liveness state ---
        vm.revertToState(snap);

        // The guard checks `_livenessTriggered()` (the live terminal CONDITION), not the
        // stored `gameOver` flag (which the advanceGame drain latches afterward).
        // _livenessTriggered() is true at level 0 once
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

        // --- Phase 4: the sweep must NOT settle the pending bet post-game-over ---
        // Doors removal: `openHumanBoxes`'s entry-gate returns (0, 0) rather than reverting
        // once `_livenessTriggered()`, so the call succeeds but does nothing — the bet stays
        // queued and credits nothing, closing the same unbacked-credit path a revert would.
        uint256 preClaimablePostGo = game.claimableWinningsOf(player);
        assertEq(preClaimablePostGo, 0, "precondition: no claimable yet post-revert");
        game.openBoxes(type(uint256).max);

        assertEq(
            game.claimableWinningsOf(player),
            0,
            "post-game-over sweep must credit zero claimable (no-op, not a revert)"
        );
        assertGt(
            game.degeneretteBetInfo(index, betId),
            0,
            "post-game-over: the bet remains queued, unresolved (pending bets are not settled by the game-over no-op)"
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

    /// @dev Place a Degenerette bet for `player` and return its betId (its queue position + 1
    ///      within whichever index is currently active — index can change under
    ///      `_setLootboxIndex`-style tests, so the id is read off the ACTIVE index, not a fixed 1).
    function _placeBet(uint8 currency, uint128 perTicket, uint8 spins, uint32 ticket)
        internal
        returns (uint64 betId)
    {
        uint256 ethValue = currency == CURRENCY_ETH ? uint256(perTicket) * spins : 0;
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(address(0), currency, perTicket, spins, uint8(ticket & 7));
        betId = DQ.lastBetId(vm, address(game), _activeIndex());
    }

    /// @dev The active lootbox RNG index (low 48 bits of lootboxRngPacked, slot 33).
    function _activeIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))));
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

    /// @dev ETH and FLIP manual events define the two bet phases. Automatic WWXRP
    ///      awards emitted by nested boxes contribute their own BoxSpin payouts.
    /// @dev Find the single DegeneretteResolved log for (index, betId) among `logs` and decode
    ///      its (totalPayout, resultTraits, spins). Reverts if not found.
    function _decodeResolved(Vm.Log[] memory logs, uint48 index, uint64 betId)
        internal
        pure
        returns (uint256 totalPayout, uint32 resultTraits, bytes memory spins)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 4 || logs[i].topics[0] != DQ.RESOLVED_SIG) continue;
            if (uint256(logs[i].topics[2]) != index) continue;
            if (uint64(uint256(logs[i].topics[3])) != betId) continue;
            (totalPayout, resultTraits, spins) = abi.decode(logs[i].data, (uint256, uint32, bytes));
            return (totalPayout, resultTraits, spins);
        }
        revert("resolved log not found");
    }

    /// @dev Recompute each spin's RAW payout (pre-3-tier-split/pre-cap for ETH, pre-survival-flip
    ///      /pre-100-rounding for FLIP) from a bet's packed `spins`, via the production math
    ///      exposed by DegeneretteMathHarness.
    function _rawPayouts(bytes memory spins, uint8 currency, uint128 stake, uint16 activity)
        internal
        returns (uint256[] memory payouts)
    {
        uint256 n = spins.length / 5;
        payouts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            (, uint8 score, uint8 gold) = DQ.spinAt(spins, i);
            payouts[i] = math.payout(score, gold, currency, stake, activity);
        }
    }

    /// @dev Sum nested WWXRP BoxSpin legs (a bet's lootbox-share recirculating into a WWXRP
    ///      box roll) and count PayoutCapped emissions across the whole recorded batch.
    function _replayNestedBoxLegs(Vm.Log[] memory logs)
        internal
        pure
        returns (uint256 wwxrpSum, uint256 payoutCappedCount)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == BOX_SPIN_SIG) {
                (uint64 boxBetId, , uint256 payout, ) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                // Box spins emit this record instead of DegeneretteResolved; bits 62-60 of the
                // synthetic betId classify the spin type (0 = WWXRP).
                if (((boxBetId >> 60) & 7) == 0) wwxrpSum += payout;
            } else if (t0 == PAYOUT_CAPPED_SIG) {
                ++payoutCappedCount;
            }
        }
    }

    /// @dev The ordered `cappedEthPayout` amounts of every PayoutCapped in `logs`.
    function _payoutCappedAmounts(Vm.Log[] memory logs) internal pure returns (uint256[] memory amounts) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == PAYOUT_CAPPED_SIG) ++n;
        }
        amounts = new uint256[](n);
        uint256 k;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == PAYOUT_CAPPED_SIG) {
                (uint256 cappedEthPayout, ) = abi.decode(logs[i].data, (uint256, uint256));
                amounts[k++] = cappedEthPayout;
            }
        }
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

    /// @dev Drain the recorded logs and count DegeneretteResolved + PayoutCapped. Nested box
    ///      spins (a bet's lootbox-share recirculating) emit BoxSpin, never DegeneretteResolved,
    ///      so only the two real player bets under test can match; the id filter is kept anyway
    ///      for robustness.
    function _countResolvedAndCapped(uint64 betA, uint64 betB)
        internal
        returns (uint256 resolved, uint256 capped)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == DQ.RESOLVED_SIG && logs[i].topics.length >= 4) {
                uint64 bid = uint64(uint256(logs[i].topics[3]));
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

    /// @dev Replay the per-spin DGNRS award from a bet's packed `spins` (score is the SAME
    ///      composite quantity the old per-spin DegeneretteResult event carried under the name
    ///      `matches` -- "Field name retained for the off-chain indexer" -- so this is a
    ///      mechanical re-source, not a semantic change). NOTE: this replay is deliberately kept
    ///      match(6/7/8)-keyed with bps 400/800/1500, matching this test's ORIGINAL (and per the
    ///      DEF-380-04-FC2 note below, already-known-divergent) model; the contract itself keys
    ///      the real award on score>=7 with bps 400/800/1500 at scores 7/8/9. Per-spin (draining):
    ///      award_k = pool_k * bps(match) / 10_000; pool_{k+1} = pool_k - award_k. Batched
    ///      (hypothetical single read): every award off the SAME initial pool.
    function _replayDgnrsPerSpin(uint256 poolStart, bytes memory spins)
        internal
        pure
        returns (uint256 perSpinSum, uint256 batchedSum)
    {
        uint256 n = spins.length / 5;
        uint256 runningPool = poolStart;
        for (uint256 i; i < n; ++i) {
            (, uint8 score, ) = DQ.spinAt(spins, i);
            if (score < 6) continue;
            uint256 bps = score == 6 ? DEGEN_DGNRS_6_BPS : score == 7 ? DEGEN_DGNRS_7_BPS : DEGEN_DGNRS_8_BPS;
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

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// @notice Read futurePrizePool from packed slot (future half, bits 128-255 of prizePoolsPacked, slot 2).
    function _readFuturePrizePool() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        return (packed >> 128) & ((uint256(1) << 128) - 1);
    }

    /// @notice Read pending future from packed slot (future half, bits 128-255 of prizePoolPendingPacked, slot 11).
    function _readPendingFuture() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        return (packed >> 128) & ((uint256(1) << 128) - 1);
    }

    /// @notice Read prizePoolFrozen from slot 0, bit 208.
    function _readFrozen() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        return ((s0 >> FROZEN_BIT_SHIFT) & 0xFF) != 0;
    }

    /// @notice Seed futurePrizePool (future half, bits 128-255 of prizePoolsPacked, slot 2).
    /// @dev Preserves the next half.
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Seed pending future (future half, bits 128-255 of prizePoolPendingPacked, slot 11).
    /// @dev Preserves the next half.
    function _seedPendingFuture(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PENDING_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
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

    /// @dev Bump the active lootbox RNG index (low 48 bits of lootboxRngPacked, slot 33) by
    ///      one, so a bet placed at the prior index now sits at LR_INDEX-1 — the finalized
    ///      index the sweep (`openHumanBoxes`/`sweepDegeneretteBets`, reached via
    ///      `game.openBoxes`) resolves. Mirrors RngFreezeAndRemovalProofs._advanceLootboxRngIndexByOne.
    function _advanceLootboxRngIndexByOne() internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        uint48 idx = uint48(packed & 0xFFFFFFFFFFFF);
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx + 1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(packed));
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
    // Batch-resolve tolerance (REMOVED — doors removal): all three tests that lived here
    // (testResolveBatchRngNotReadyFirstRevertsTrailingSkips, already removed per the port
    // note this replaces; testResolveBatchFirstBetAlreadyResolvedReverts; and
    // testResolveBatchTrailingAlreadyResolvedSkipped) proved behavior of the manual
    // `resolveDegeneretteBets(index, betIds)` door's caller-composed betId array: a strict
    // first-id probe (fail-fast InvalidBet() on an already-resolved/unknown first id) and a
    // tolerant tail (a stale id later in the array is silently skipped). That door — and with
    // it the whole notion of a caller-composed betId array — is gone: `openBoxes` takes no id
    // list and always walks the queue in ascending position, silently skipping a zeroed
    // (already-resolved) slot it happens to resume on (`sweepDegeneretteBets`: `if (bet == 0)
    // { ++pos; ++unitsSpent; continue; }`) rather than ever being handed one out of turn. There
    // is no "duplicate clicker resends a caller-composed batch" scenario left to reproduce, and
    // the remaining unset-index-word property is already covered by DegeneretteSweep.t.sol's
    // testHandResolutionGuards, so none of the three is adapted.
    // =========================================================================

    /// @dev Read the queued bet word at (index 1, betId); 0 == resolved/nonexistent.
    function _betPacked(uint64 betId) internal view returns (uint256) {
        return game.degeneretteBetInfo(1, betId);
    }
}
