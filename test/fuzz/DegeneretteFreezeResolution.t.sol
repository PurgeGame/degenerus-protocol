// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

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
/// @dev Bets are one word in `degeneretteQueue[index & 1]` (id = queue position + 1), resolved
///      only by mineFlip's in-order Degenerette read-consumer stage, which walks the queue in
///      ascending position. A bet resolves once every box AND bet at every index <= its own is
///      resolved. The "pending bet is not settled post-game-over" invariant is held by
///      testResolveBetsRevertsPostGameOver_InsolvencyReproClosed: once `_livenessTriggered()`, no
///      read stage is eligible and the engine's only work is the terminal path.
///      The per-spin `DegeneretteResult` event is gone, replaced by ONE `DegeneretteResolved`
///      per bet carrying every spin's (playerTraits, score, house wilds) as packed bytes
///      (see test/helpers/DegeneretteQueue.sol `spinAt`). Per-spin RAW payouts (before the ETH
///      3-tier split / pool cap and before the FLIP survival flip / 100-FLIP rounding) are
///      recomputed off-chain via `DegeneretteMathHarness.payout(score, wilds, currency, stake,
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
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;

    /// @dev prizePoolPendingPacked: [upper 128: futurePending] [lower 128: nextPending]
    uint256 private constant PENDING_PACKED_SLOT = GameSlots.PRIZE_POOL_PENDING_PACKED;

    /// @dev lootboxRngWordByIndex mapping root slot (post Stage-B game-storage repack: was 36).
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;

    /// @dev lootboxRngPacked at slot 34 (post Stage-B game-storage repack: was 35); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;

    /// @dev Salt used in degenerette bet resolution for the first spin.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    /// @dev Mirrors `DegenerusGameDegeneretteModule.FLIP_ROUND_TAG` (private there), the
    ///      domain separator the 100-FLIP award collapse is keyed under.
    uint256 private constant BET_SURVIVAL_TAG = 0x446567656e537572766976616c; // "DegenSurvival"
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"

    // --- DGAS-05 same-results constants ---

    /// @dev claimablePool (uint128) lives in slot 1, byte 16.
    uint256 private constant CLAIMABLE_POOL_SLOT = GameSlots.CLAIMABLE_POOL;
    /// @dev FLIP.balanceOf mapping root slot.
    uint256 private constant FLIP_BALANCEOF_SLOT = 1;

    /// @dev Degenerette bet currencies (DegeneretteModule:208-214).
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;

    /// @dev ETH win pool cap: 10% of futurePool (DegeneretteModule:196).
    uint256 private constant ETH_WIN_CAP_BPS = 1_000;
    /// @dev Per-currency minimum bets (DegeneretteModule:217-223).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_FLIP = 100;

    /// @dev PayoutCapped topic0 — one per ETH spin that flipped into the lootbox. Event shape
    ///      is unchanged: PayoutCapped(address indexed player, uint256 cappedEthPayout, uint256 excessConverted).
    bytes32 private constant PAYOUT_CAPPED_SIG = keccak256("PayoutCapped(uint32,uint256,uint256)");
    /// @dev BoxSpin topic0 — one per internal (non-placed-bet) Degenerette spin, e.g. a bet's
    ///      lootbox-share recirculating into a nested WWXRP/FLIP/ETH box roll.
    bytes32 private constant BOX_SPIN_SIG =
        keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");

    address private player;
    uint32 private playerId;

    function setUp() public {
        _deployProtocol();
        // Deployed AFTER the protocol: DeployProtocol pins every contract to a deployer nonce, so
        // a deployment before it shifts the whole address map (setUp then reverts in Coinflip).
        math = new DegeneretteMathHarness();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("degen_freeze_player");
        vm.deal(player, 1000 ether);
        playerId = _giveWalletId(player);

        // Fund the game contract with ETH to back the pool injections
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet reverts with E() when lootboxRngIndex == 0.
        // Seed it to 1 so the bet check passes. The word at index 1 starts
        // as 0 (no pending RNG), which is the required state for bet placement.
        // lootboxRngIndex is the low 48 bits of lootboxRngPacked (slot 34).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
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
        game.placeDegeneretteBet{value: betAmount}(0, 0, betAmount, 1, uint8(customTraits & 7));

        // Live pools should have increased (unfrozen path uses _setPrizePools)
        uint256 postBetLiveFuture = _readFuturePrizePool();
        assertEq(postBetLiveFuture, preLiveFuture + betAmount,
            "Unfrozen: live future should increase by bet amount");

        // Pending should be untouched
        assertEq(_readPendingFuture(), prePendingFuture,
            "Unfrozen: pending future should be untouched");

        // Inject RNG word, finalize the index, and resolve it through the engine.
        _injectLootboxRngWord(index, winningRngWord);

        _resolveCohort();

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
    ///         symbol at the same index/word produces identical player traits, score and wilds
    ///         per spin regardless of owner, currency or queue position. (Doors removal: the
    ///         sweep always walks the queue in ascending position, so "which id resolves first"
    ///         is no longer caller-selectable; the shared-board claim itself — the part this
    ///         test actually proves — is unaffected and is proven here off a single sweep call.)
    function test_SharedBoardAcrossPlayersCurrenciesAndBets() public {
        uint256 word = uint256(keccak256("shared-period-board"));
        while (!_spin0Pays(1, word)) ++word;
        uint32 pick = _winningTicketFor(1, word);
        address firstPlayer = player;
        uint64 first = _placeBet(CURRENCY_ETH, 0.01 ether, 3, pick);
        address secondPlayer = makeAddr("second_board_player");
        player = secondPlayer;
        _fundFlip(player, 10_000);
        _placeBet(CURRENCY_FLIP, 100, 1, pick); // decoy bet shifts the queue position
        uint64 second = _placeBet(CURRENCY_FLIP, 200, 3, pick);
        _injectLootboxRngWord(1, word);


        vm.recordLogs();
        _resolveCohort();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (, uint32 firstResultTraits, bytes memory firstSpins) = _decodeResolved(logs, 1, first);
        (, uint32 secondResultTraits, bytes memory secondSpins) = _decodeResolved(logs, 1, second);
        assertEq(firstResultTraits, pick, "shared spin-0 house board matches the picked ticket");
        assertEq(secondResultTraits, pick, "shared spin-0 house board matches the picked ticket");
        assertEq(firstSpins.length, 3 * 5, "first bet ran 3 spins");
        assertEq(secondSpins.length, 3 * 5, "second bet ran 3 spins");
        for (uint8 s; s < 3; ++s) {
            (uint32 pt1, uint8 sc1, uint8 w1) = DQ.spinAt(firstSpins, s);
            (uint32 pt2, uint8 sc2, uint8 w2) = DQ.spinAt(secondSpins, s);
            assertEq(pt1, pt2, "same symbol -> identical player traits regardless of owner/currency/order");
            assertEq(sc1, sc2, "every spin uses the shared board (score identical across bets)");
            assertEq(w1, w2, "house wild counts identical across bets");
        }
        player = firstPlayer;
    }

    function testBatchedPayoutEqualsPerSpinExpectation_Tier1() public {
        // Large unfrozen pool so the ETH 10% cap never binds (cap is Tier-2's job).
        _seedFuturePrizePool(1_000_000 ether);

        // Both bets share the seeded lootbox index 1 (placement requires word==0).
        // Word chosen so the FLIP bet (betId 2) WINS its bet-keyed survival flip
        // (keccak(word, playerId, betId, BET_SURVIVAL_TAG) & 1 == 1) — the doubled-mint path is exercised
        // non-vacuously below.
        uint48 index = 1;
        uint256 word = uint256(keccak256("tier1_mixed_batch_word_v3"));
        while (!_spin0Pays(index, word) || EntropyLib.hash4(word, uint256(playerId), 2, BET_SURVIVAL_TAG) & 1 == 0) {
            ++word;
        }

        // ETH bet: four spins; FLIP bet: three spins. WWXRP can still arise from nested boxes.
        // Use the spin-0 house symbol as the hero for each (a paying spin 0 makes the bet
        // non-vacuous; other spins vary).
        uint32 ethTicket = _winningTicketFor(index, word);
        uint32 flipTicket = ethTicket;

        uint128 ethPerTicket = 0.01 ether;     // >= MIN_BET_ETH
        uint128 flipPerTicket = 2_000;   // >= MIN_BET_FLIP

        // Fund the player for the FLIP bet.
        _fundFlip(player, uint256(flipPerTicket) * 3 + 1);

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

        vm.recordLogs();
        _resolveCohort();
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
            keccak256(abi.encode(word, uint256(playerId), flipBet, BET_SURVIVAL_TAG))
        ) & 1 == 1) ? expectedFlip * 2 : 0;
        assertGt(rawFlipMint, 0, "Tier-1: word must win the FLIP survival flip");

        // The award granule then collapses the SURVIVED total onto a whole 100-FLIP
        // multiple. Replicated here from the same inputs the module uses, so this stays a
        // byte-identical amount assertion rather than a tolerance: the collapse is keyed on
        // hash4(rngWord, playerId, betId, FLIP_ROUND_TAG), all fixed at fulfillment.
        uint256 expectedFlipMint = _gateFlipAward(
            rawFlipMint,
            EntropyLib.hash4(word, uint256(playerId), flipBet, FLIP_ROUND_TAG)
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
    ///         (keccak(word, playerId, betId, BET_SURVIVAL_TAG) & 1 == 0) loses mints NOTHING, even though its
    ///         raw spins paid (recomputed per-spin payout sum > 0).
    function testFlipSurvivalFlipLossZeroesMint() public {
        _seedFuturePrizePool(1_000_000 ether);

        // Word chosen so betId 1 LOSES the survival flip and spin 0 pays, so the raw
        // per-spin payouts are nonzero.
        uint48 index = 1;
        uint256 word = uint256(keccak256("survival_flip_loss_word_v3"));
        while (!_spin0Pays(index, word) || EntropyLib.hash4(word, uint256(playerId), 1, BET_SURVIVAL_TAG) & 1 == 1) {
            ++word;
        }
        uint32 ticket = _winningTicketFor(index, word);

        _fundFlip(player, 1_000);
        uint64 betId = _placeBet(CURRENCY_FLIP, 200, 3, ticket);
        assertEq(
            uint256(keccak256(abi.encode(word, uint256(playerId), betId, BET_SURVIVAL_TAG))) & 1,
            0,
            "precondition: the chosen word loses the survival flip for this bet"
        );

        // Capture stake/activity BEFORE resolving -- degeneretteBetInfo zeroes after resolve.
        uint256 betWord = game.degeneretteBetInfo(index, betId);
        uint16 activity = DQ.activity(betWord);
        uint128 stake = DQ.stake(betWord);

        _injectLootboxRngWord(index, word);

        uint256 preFlip = coin.balanceOf(player);


        vm.recordLogs();
        _resolveCohort();
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
        while (!_spin0Pays(index, word)) ++word;
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


        vm.recordLogs();
        _resolveCohort();
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

    // =========================================================================
    // DGAS-05 Test 6: lootbox summed PER betId, never across bets
    // =========================================================================

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
    ///      anymore — the engine always walks the queue in order. Run B instead gas-starves the
    ///      FIRST mineFlip so only bet1 fits (each bet is admitted only while the remaining
    ///      allowance covers its declared bound), then drains the rest — reproducing "resolve
    ///      bet1, then bet2, in two separate txs" exactly.
    function testLootboxSummedPerBetIdNotAcrossBets() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("perbetid_word"));
        while (!_spin0Pays(index, word)) ++word;
        uint32 ticket = _winningTicketFor(index, word);
        // A paying spin pays at least 0.225 ETH at minimum activity, above the cap. Both bets stay under the 1 ETH
        // biggest-spin floor so neither arms a record claim: equal declared admissions, so a
        // gas-starved call that admits bet1 cannot also admit bet2.
        uint128 perTicket = 0.5 ether;
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
        vm.recordLogs();
        _resolveCohort();

        uint256 ethCreditedOneCall = game.claimableWinningsOf(player) - preA;
        // Two bets resolved -> two DegeneretteResolved, two PayoutCapped (one spin each).
        (uint256 resolvedCount, uint256 cappedCount) = _countResolvedAndCapped(bet1, bet2);
        assertEq(resolvedCount, 2, "two bets resolved -> two DegeneretteResolved (per-bet unit)");
        assertEq(cappedCount, 2,
            "per-betId: each bet's single spin capped independently -> two PayoutCapped");

        // --- Run B: revert to the snapshot, resolve the SAME two bets in TWO calls ---
        // (the per-betId baseline: one box per bet, resolved one at a time).
        vm.revertToState(snap);
        uint256 preB = game.claimableWinningsOf(player);

        // The walk-unit budget is now a gas allowance (60d31f775): the starved first call gets the
        // smallest allowance that resolves any bet, which admits bet1 and refuses bet2.
        assertEq(_crankOneBet(), 1, "Run B call 1: exactly one bet fits the starved allowance");
        assertEq(_betPacked(bet1), 0, "Run B call 1: bet1 alone resolved");
        assertGt(_betPacked(bet2), 0, "Run B call 1: bet2 left queued (budget-starved)");

        _resolveCohort();
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

    /// @notice Two independently replayed score-7 ETH spins must debit successively smaller
    ///      Reward balances. Nested box awards are accounted separately, including other pools.
    /// @dev Offline Keccak search (.planning/wild-color/find_dgnrs_word.py): index 1, word 116141,
    ///      symbol 0, 25 spins have S7 at spin 12 and spin 17, with every other score below 7. The
    ///      reference checks all 25 emitted player tickets, scores and wild counts, so the vector
    ///      cannot silently become vacuous.
    function testDgnrsAwardStaysPerSpin() public {
        uint48 index = 1;
        uint256 word = 116_141;
        uint8 symbol = 0;
        uint8 spinCount = 25;
        uint64 betId = _placeBet(CURRENCY_ETH, 1 ether, spinCount, symbol);
        assertEq(DQ.stake(_betPacked(betId)), 1 ether, "unboosted stake reaches the DGNRS cap exactly");
        _seedFuturePrizePool(1_000_000 ether);
        _injectLootboxRngWord(index, word);


        uint256[5] memory poolsBefore;
        for (uint8 i; i < 5; ++i) poolsBefore[i] = sdgnrs.poolBalance(sDGNRS.Pool(i));
        uint256 rewardBefore = poolsBefore[uint8(sDGNRS.Pool.Reward)];
        assertGt(rewardBefore, 0, "Reward pool is funded");
        uint256 playerBefore = sdgnrs.balanceOf(player);
        uint256 treasuryBefore = sdgnrs.balanceOf(address(sdgnrs));
        vm.recordLogs();
        _resolveCohort();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_betPacked(betId), 0, "the real sweep consumed the placed bet");

        (, uint32 firstHouse, bytes memory spins) = _decodeResolved(logs, index, betId);
        assertEq(spins.length, uint256(spinCount) * 5, "all committed spins resolved");
        assertEq(firstHouse, Ref.house(word, uint32(index), 0, false), "independent first house ticket");
        uint256 qualifiers;
        for (uint8 i; i < spinCount; ++i) {
            uint32 expectedPlayer = Ref.player(word, uint32(index), symbol, i, false);
            (uint8 score, uint8 wilds) = Ref.score(expectedPlayer, Ref.house(word, uint32(index), i, false));
            (uint32 actualPlayer, uint8 actualScore, uint8 actualWilds) = DQ.spinAt(spins, i);
            assertEq(actualPlayer, expectedPlayer, "independent player ticket for every spin");
            assertEq(actualScore, score, "independent composite score for every spin");
            assertEq(actualWilds, wilds, "independent house wild count for every spin");
            if (score >= 7) {
                assertTrue(i == 12 || i == 17, "the deterministic high-score positions remain pinned");
                assertEq(score, 7, "both qualifying spins use the S7 tier");
                ++qualifiers;
            }
        }
        assertEq(qualifiers, 2, "two nonzero awards make stale-pool pricing observable");
        (uint256[] memory awards, uint256 expectedParent, uint256 staleParent) = _replayDgnrsPerSpin(rewardBefore, spins);
        assertLt(expectedParent, staleParent, "fresh per-spin depletion differs from a single initial balance");
        uint256 nested = _assertDgnrsPoolTransfers(logs, awards, poolsBefore);
        assertEq(sdgnrs.balanceOf(player) - playerBefore, expectedParent + nested,
            "player balance reconciles independent parent awards plus separately itemized child awards");
        assertEq(treasuryBefore - sdgnrs.balanceOf(address(sdgnrs)), expectedParent + nested,
            "treasury debits exactly the full parent and child award total");
        emit log_named_uint("dgnrs_parent_per_spin", expectedParent);
        emit log_named_uint("dgnrs_parent_stale_hypothetical", staleParent);
        emit log_named_uint("dgnrs_nested_box_awards", nested);
    }

    /// @dev Parent high-score awards precede this bet's recirculated box. Verify each parent
    ///      transfer separately; then reconcile any child transfers by pool and final balances.
    ///      Child amounts are itemized here, not assumed absent or priced as parent-spin awards.
    function _assertDgnrsPoolTransfers(Vm.Log[] memory logs, uint256[] memory awards, uint256[5] memory poolsBefore)
        private view returns (uint256 nested)
    {
        bytes32 transferSig = keccak256("PoolTransfer(uint8,address,uint256)");
        uint256[5] memory debited;
        uint256 parent;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(sdgnrs) || logs[i].topics.length != 3
                || logs[i].topics[0] != transferSig) continue;
            uint256 pool = uint256(logs[i].topics[1]);
            address recipient = address(uint160(uint256(logs[i].topics[2])));
            uint256 paid = abi.decode(logs[i].data, (uint256));
            assertEq(recipient, player, "each reward in the isolated bet goes to its owner");
            assertLt(pool, 5, "known pool identifier");
            debited[pool] += paid;
            if (parent < awards.length) {
                assertEq(pool, uint8(sDGNRS.Pool.Reward), "parent high-score awards debit Reward");
                assertEq(paid, awards[parent], "each parent spin prices the remaining Reward balance");
                ++parent;
            } else {
                nested += paid;
            }
        }
        assertEq(parent, awards.length, "every independently replayed parent award was actually transferred");
        for (uint8 i; i < 5; ++i) {
            assertEq(poolsBefore[i] - sdgnrs.poolBalance(sDGNRS.Pool(i)), debited[i],
                "every parent/child transfer reconciles to its actual pool debit");
        }
    }

    // =========================================================================
    // 323 Task 2: post-game-over resolveBets liveness guard (insolvency repro closed)
    // =========================================================================

    /// @notice Prove the liveness guard (the read-consumer stage selector returns 0 once
    ///         `_livenessTriggered()`, so mineFlip selects only the terminal path) CLOSES the §1
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
    ///           4. assert no read stage is eligible and the engine's terminal step resolves
    ///              nothing — the bet stays queued and credits nothing, so the unbacked
    ///              post-drain credit cannot happen.
    function testResolveBetsRevertsPostGameOver_InsolvencyReproClosed() public {
        // --- Phase 1: place a winning ETH bet pre-game-over, commit its RNG word ---
        // Large unfrozen pool so the win resolves to a real ETH credit pre-GO.
        _seedFuturePrizePool(1_000 ether);

        uint48 index = 1;
        uint256 word = uint256(keccak256("post_gameover_repro_word"));
        while (!_spin0Pays(index, word)) ++word;
        uint32 ticket = _winningTicketFor(index, word); // paying spin 0: a real ETH win

        assertFalse(game.gameOver(), "precondition: game is live at bet placement");
        assertFalse(game.livenessTriggered(), "precondition: liveness not triggered");

        uint128 perTicket = 0.05 ether; // >= MIN_BET_ETH
        uint64 betId = _placeBet(CURRENCY_ETH, perTicket, 1, ticket);
        _injectLootboxRngWord(index, word); // RNG committed -> bet is resolvable
 // finalize the index so the sweep can reach it

        // --- Phase 2: prove the bet IS otherwise resolvable pre-game-over ---
        // (the §1 path: pre-fix, this same call after game-over would have credited
        // claimable out of the drained residual). The snapshot lets the SAME placed,
        // RNG-committed bet be re-used for the post-game-over no-op assertion, so the
        // only difference between the two runs is the game-over state the guard checks.
        uint256 snap = vm.snapshotState();

        uint256 preClaimable = game.claimableWinningsOf(player);
        _resolveCohort();
        uint256 ethCreditedPreGo = game.claimableWinningsOf(player) - preClaimable;
        assertGt(
            ethCreditedPreGo,
            0,
            "control: the bet resolves and credits claimable while the game is live"
        );

        // --- Phase 3: revert and drive into the terminal liveness state ---
        vm.revertToState(snap);

        // The guard checks `_livenessTriggered()` (the live terminal CONDITION), not the
        // stored `gameOver` flag (which the mineFlip drain latches afterward).
        // _livenessTriggered() is true at level 0 once
        // currentDay - purchaseStartDay > _DEPLOY_IDLE_TIMEOUT_DAYS (365), with
        // lastPurchaseDay/jackpotPhaseFlag false (fresh-deploy default). Warp well past it.
        // This is the exact predicate the guard gates on, so the warp reproduces the
        // post-game-over state for the §1 path without needing to drive the VRF-entropy
        // mineFlip drain that flips the stored flag.
        vm.warp(block.timestamp + 366 days);
        assertEq(game.level(), 0, "repro precondition: still at level 0 (deploy-idle path)");
        assertTrue(
            game.livenessTriggered(),
            "game-over liveness must now be triggered (the predicate the guard checks)"
        );

        // --- Phase 4: the engine must NOT settle the pending bet post-game-over ---
        uint256 preClaimablePostGo = game.claimableWinningsOf(player);
        assertEq(preClaimablePostGo, 0, "precondition: no claimable yet post-revert");
        assertGt(
            game.degeneretteBetInfo(index, betId),
            0,
            "post-game-over: the bet remains queued, unresolved"
        );

        // Bets resolve only as an engine read consumer. Once liveness triggers, no read stage
        // is eligible: the engine's only work is the terminal path, which resolves no pending bet.
        assertEq(game.rngConsumerStage(), 0, "no read consumer runs once liveness triggers");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal), "only the terminal path remains");
        vm.recordLogs();
        game.mineFlip(0);
        assertEq(_countTopic(vm.getRecordedLogs(), DQ.RESOLVED_SIG), 0, "the terminal step resolves no pending bet");
        assertEq(game.claimableWinningsOf(player), 0, "the terminal step credits the bettor nothing");
    }

    // =========================================================================
    // DGAS-05 Internal Helpers
    // =========================================================================

    /// @dev Reward-pool percentages for the current composite score tiers S7/S8/S9.
    uint256 private constant DEGEN_DGNRS_7_BPS = 204;
    uint256 private constant DEGEN_DGNRS_8_BPS = 466;
    uint256 private constant DEGEN_DGNRS_9_BPS = 1010;

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
        game.placeDegeneretteBet{value: ethValue}(0, currency, perTicket, spins, uint8(ticket & 7));
        betId = DQ.lastBetId(vm, address(game), _activeIndex());
    }

    /// @dev The active lootbox RNG index (low 48 bits of lootboxRngPacked, slot 33).
    function _activeIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev The spin-0 house ticket for (index, word); callers bet its lane-0 symbol as the hero,
    ///      so the hero lane scores at least 2. `_spin0Pays` selects words where spin 0 pays.
    function _winningTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        return _resultTicketForSpin(index, word, 0);
    }

    /// @dev Whether spin 0 pays (S >= 3) for the hero symbol taken from the house's lane 0.
    function _spin0Pays(uint48 index, uint256 word) internal pure returns (bool) {
        uint32 house = _resultTicketForSpin(index, word, 0);
        (uint8 score,) = Ref.score(Ref.player(word, uint32(index), uint8(house & 7), 0, false), house);
        return score >= 3;
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
            (, uint8 score, uint8 wilds) = DQ.spinAt(spins, i);
            payouts[i] = math.payout(score, wilds, currency, stake, activity);
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

    /// @dev Called only after every emitted ticket/score/wilds tuple has passed the independent
    ///      reference replay. Each award uses the pool left by earlier awards; stake is one ETH.
    function _replayDgnrsPerSpin(uint256 poolStart, bytes memory spins)
        internal pure returns (uint256[] memory awards, uint256 perSpinSum, uint256 staleSum)
    {
        uint256 n = spins.length / 5;
        awards = new uint256[](n);
        uint256 count;
        uint256 runningPool = poolStart;
        for (uint256 i; i < n; ++i) {
            (, uint8 score,) = DQ.spinAt(spins, i);
            if (score < 7) continue;
            uint256 bps = score == 7 ? DEGEN_DGNRS_7_BPS : score == 8 ? DEGEN_DGNRS_8_BPS : DEGEN_DGNRS_9_BPS;
            uint256 reward = runningPool * bps / 10_000;
            awards[count++] = reward;
            perSpinSum += reward;
            runningPool -= reward;
            staleSum += poolStart * bps / 10_000;
        }
        assembly ("memory-safe") { mstore(awards, count) }
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
    /// @dev Seals the cohort and marks the reusable word ready.
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
        // The day itself is sealed (dailyIdx = today, tickets drained), as after a mid-day request:
        // the delivered cohort's read consumers are the engine's only work, so mineFlip stops when
        // the cohort completes instead of preparing the next day.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Bets resolve as the Degenerette read consumer of the published word, reached only by
    ///      mineFlip. One unbounded call runs the cohort's whole consumer chain.
    function _resolveCohort() internal {
        vm.prank(makeAddr("degen_freeze_crank"));
        game.mineFlip(0);
    }

    /// @dev One mineFlip given the smallest allowance that still resolves a bet: the engine admits a
    ///      bet only while the remaining allowance covers its declared bound, so at the minimum the
    ///      call resolves exactly the next bet. Found by bisection over snapshots of the same state.
    function _crankOneBet() internal returns (uint256 resolved) {
        uint256 lo = 300_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            vm.prank(makeAddr("degen_freeze_crank"));
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            uint256 n = ok ? _countTopic(vm.getRecordedLogs(), DQ.RESOLVED_SIG) : 0;
            vm.revertToStateAndDelete(snap);
            if (n != 0) hi = mid;
            else lo = mid;
        }
        vm.recordLogs();
        vm.prank(makeAddr("degen_freeze_crank"));
        game.mineFlip{gas: hi}(0);
        resolved = _countTopic(vm.getRecordedLogs(), DQ.RESOLVED_SIG);
    }

    function _countTopic(Vm.Log[] memory logs, bytes32 topic) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics.length != 0 && logs[i].topics[0] == topic) ++n;
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
        for (uint256 attempt; attempt < 1000; attempt++) {
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
            if (matches >= 2 && _spin0Pays(index, rngWord)) return (customTraits, rngWord);
        }
        revert("Could not find winning combo in 1000 attempts");
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

    /// @dev Read the queued bet word at (index 1, betId); 0 == resolved/nonexistent.
    function _betPacked(uint64 betId) internal view returns (uint256) {
        return game.degeneretteBetInfo(1, betId);
    }
}
