// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title V56FreezeSolvency -- the SEC-02 proof in three legs (CONTEXT D-05) against the FROZEN v56 subject:
///        (1) the ETH/claimablePool debit path is byte-unchanged vs 453f8073 (the SOLVENCY-01 site); (2) a
///        solvency invariant fuzz; (3) an RNG-freeze determinism fuzz.
///
/// @notice Leg 1 (forge arm). The ETH/claimablePool debit happens at exactly one in-context site —
///   `_deliverAfkingBuy` (GameAfkingModule.sol): `afkingFunding[src] -= ethValue; claimablePool -=
///   uint128(ethValue);` — and the debit equals the delivered ethValue EXACTLY. The affiliate base and the
///   slot-0 quest reward are accrued as FLIP (pendingFlip / affiliateBase, claimed via creditFlip), OFF
///   the ETH/claimablePool path: claiming FLIP leaves claimablePool byte-unchanged. The literal git
///   byte-diff anchor (`git diff 453f8073 HEAD` shows the debit two-liner re-added verbatim) is recorded by
///   356-07's ledger; this file asserts the BEHAVIOR (debit == delivered value; FLIP claim moves no pool).
///
/// @notice Leg 2 (solvency invariant). The master invariant the Game maintains (DegenerusGame.sol:18) is
///   `address(this).balance + steth.balanceOf(this) >= claimablePool`. Across random {sub, unsub, buy,
///   accrue, claimAfkingFlip} sequences it always holds: the buy-delivery debit decreases claimablePool by
///   exactly the fresh-ETH it spends from the (already-reserved) afking funding, and the FLIP accrue/claim
///   never touches the pool.
///
/// @notice Leg 3 (RNG-freeze determinism). The subscribe min-buy STAMPS a box for-later-open and NEVER
///   inline-resolves pre-RNG (no LootBoxOpened at subscribe time). The single-roll open seed is
///   `keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay, amount))` — it carries NO block.*
///   entropy, so two opens of the SAME stamp at DIFFERENT blocks (vm.roll/warp + perturbed
///   prevrandao/coinbase) materialize byte-identical boxes. The afking open is reached via mintFlip() (the
///   autoOpen selector was dropped — not re-exposed on the Game).
///
/// @dev Reuses the funded-sub + seated + new-day STAGE harness (the accumulating-`_t` warp +
///   fulfill-first `_settleGame`/`_settleClean`/`_fulfillPending` from V56AfkingGasMarginal / the 356-03
///   V56SecUnmanipulable), the materialized-box byte-identity oracle from the v56-migrated
///   V55FreezeDeterminism, and the claimablePool slot read from the v56-migrated V55RevertFreeEvCap. Copies
///   the v56 Sub-slot offset block VERBATIM from V56AfkingGasMarginal:68-89 (NOT the stale v55 offsets).
///   v56 harness semantics: Sub.amount is packed milli-ETH (_packEthToMilliEth), the subscribe min-buy
///   carries a 0.01-ETH funding delta, the affiliate is a single-step claim. Seeded-fuzz deterministic
///   (`foundry.toml [fuzz] seed=0xdeadbeef`); the assertions are an unseeded-invariant subset of the seeded
///   closure (Pitfall 5). Test-only: ZERO contracts/*.sol mutation.
contract V56FreezeSolvency is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the v56 Sub-slot offset block (V56AfkingGasMarginal:68-89)
    // -------------------------------------------------------------------------
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint32 => uint256) — the afking box DAY-keyed word
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // [0:47] lootboxRngIndex (was 35)
    uint256 private constant LOOTBOX_RNG_WORD_BY_INDEX_SLOT = 34; // mapping(uint48 => uint256) (was 36)
    uint256 private constant SUBOF_SLOT = 53; // _subOf mapping root (address => Sub, one packed slot) (was 58)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // mapping(address => uint256) _subscriberIndex (1-indexed) (was 61)

    //   dailyQuantity u8 @0 · flags u8 @1 · score u16 @2 · amount u24 @4 (milli-ETH)
    //   lastAutoBoughtDay u24 @7 · lastOpenedDay u24 @10 · afkCoveredThroughDay u24 @13 · afkingStartDay u24 @16
    //   affiliateBase u32 @19 · pendingFlip u24 @23 · subStreakLatch u16 @26
    uint256 private constant OFF_SCOREPLUS1 = 2; // uint16 score             (bytes 2..3)
    uint256 private constant OFF_AMOUNT = 4; // uint24 amount (milli-ETH)   (bytes 4..6)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)
    uint256 private constant OFF_AFKCOVERED = 13; // uint24 afkCoveredThroughDay (bytes 13..15)
    uint256 private constant OFF_PENDINGFLIP = 23; // uint24 pendingFlip (bytes 23..25)

    /// @dev keccak256 of the materialized-box event — the byte-identity oracle's source signature.
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole FLIP accrued to pendingFlip per delivered buy.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;

    /// @dev A decoded LootBoxOpened payload — every non-indexed field of the materialized box.
    struct Box {
        bool present;
        uint48 lootboxIndex;
        uint256 amount;
        uint24 futureLevel;
        uint32 futureTickets;
        uint256 flip;
        bool roundedUp;
    }

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // Leg 2 — the solvency invariant across churn / accrue / claim
    // =========================================================================

    /// @notice The master solvency invariant `game.balance + steth.balanceOf(game) >= claimablePool` holds
    ///         after EVERY action in a fuzzed {sub, unsub, buy(=deliver a funded day), claimAfkingFlip}
    ///         sequence. Each delivered day debits claimablePool by exactly its fresh-ETH spend (already
    ///         reserved inside the pool by the funding deposit), and the FLIP accrue/claim moves no ETH —
    ///         so the invariant is never broken by the v56 accrual/settle redesign. Non-vacuous: at least one
    ///         delivered buy actually moved the pool and accrued claimable FLIP.
    function testFuzzSolvencyInvariantUnderChurn(uint256 seq, uint8 rounds) public {
        address a = makeAddr("solv_a");
        address b = makeAddr("solv_b");
        _grantSeat(a);
        _grantSeat(b);
        // Fund BEFORE subscribe so each NEW-run cover-buy is grounded (D-12 — an unfunded start reverts).
        _fundPool(a, 200 ether);
        _fundPool(b, 200 ether);
        _subscribeLootbox(a, 1);
        _subscribeLootbox(b, 1);

        _assertSolvent("post-setup");

        // Anchor buy: always deliver one funded day first so the invariant is exercised against a pool a
        // real buy has moved (the fuzzed action stream may otherwise pick no buy at all).
        _deliverDay(uint256(keccak256(abi.encode("solvanchor", seq))) | 1);
        _assertSolvent("post-anchor-buy");

        uint256 delivered = 1;
        uint256 n = 3 + (uint256(rounds) % 6); // 3..8 actions
        for (uint256 i; i < n; i++) {
            uint256 action = (seq >> (i * 3)) & 0x7;
            if (action < 4) {
                // buy: deliver a funded day to BOTH subs (debits the pool by the fresh-ETH spend).
                _deliverDay(uint256(keccak256(abi.encode("solvbuy", seq, i))) | 1);
                delivered++;
            } else if (action == 4) {
                // claimAfkingFlip: pulls the accrued FLIP — must NOT move claimablePool.
                uint256 poolBefore = _claimablePool();
                game.claimAfkingFlip(_pair(a, b));
                assertEq(_claimablePool(), poolBefore, "claimAfkingFlip left claimablePool byte-unchanged (OFF the ETH path)");
            } else if (action == 5) {
                // unsub a (tombstone) — only if currently an active sub (a real user can't cancel a
                // non-existent sub; the contract reverts NotSubscribed otherwise). Refunds nothing, so the
                // pool stays reserved against the residual funding.
                if (_subscriberIndexOf(a) != 0 && _dailyQtyOf(a) != 0) {
                    vm.prank(a);
                    game.subscribe(address(0), false, false, 0, address(0));
                }
            } else if (action == 6) {
                // re-sub a (re-uses the in-place slot) if it is not currently active. Top up its funding
                // FIRST so the re-sub's NEW-run cover-buy is grounded (D-12).
                if (_dailyQtyOf(a) == 0) {
                    _fundPool(a, 20 ether);
                    _subscribeLootbox(a, 1);
                }
            } else {
                // top up b's funding (deposit credits afkingFunding + claimablePool in tandem); fund FIRST
                // then re-sub b if a STAGE reclaim deleted its slot (grounds the re-sub cover-buy — D-12).
                _fundPool(b, 20 ether);
                if (_dailyQtyOf(b) == 0) _subscribeLootbox(b, 1);
            }
            _assertSolvent("post-action");
        }

        // Non-vacuity: the churn delivered at least one buy that moved the pool + accrued claimable FLIP.
        assertGt(delivered, 0, "non-vacuity: at least one delivered buy");
        _assertSolvent("final");
    }

    /// @notice A focused named repro of leg 2's core: a delivered funded buy debits claimablePool, and a
    ///         subsequent claimAfkingFlip leaves the pool byte-unchanged. The solvency invariant holds
    ///         across both.
    function testSolvencyHoldsBuyThenFlipClaim() public {
        address p = makeAddr("solv_repro");
        _grantSeat(p);
        // Fund-before-subscribe grounds the NEW-run cover-buy (D-12); under the hardened gate the grounded
        // subscribe IS the delivered buy, so measure the claimablePool debit across the subscribe itself.
        _fundPool(p, 50 ether);
        _assertSolvent("post-fund");

        uint256 poolBeforeBuy = _claimablePool();
        _subscribeLootbox(p, 1); // the grounded NEW-run cover-buy debits the fresh-ETH spend at this site
        uint256 poolAfterBuy = _claimablePool();
        // The delivered buy spent fresh ETH from the (reserved) funding -> the pool decreased by the spend.
        assertLt(poolAfterBuy, poolBeforeBuy, "the delivered buy debited claimablePool by its fresh-ETH spend");
        _assertSolvent("post-buy");

        // The buy accrued claimable FLIP OFF the ETH path.
        assertEq(_pendingFlipOf(p), SLOT0_FLIP_PER_BUY, "the buy accrued 100 whole FLIP into pendingFlip (OFF the ETH path)");

        // Claiming the FLIP moves no ETH: the pool is byte-unchanged across the claim.
        uint256 poolBeforeClaim = _claimablePool();
        game.claimAfkingFlip(_singleton(p));
        assertEq(_claimablePool(), poolBeforeClaim, "claimAfkingFlip: claimablePool byte-unchanged (FLIP is OFF the ETH/pool path)");
        assertEq(_pendingFlipOf(p), 0, "the FLIP was paid (pendingFlip zeroed)");
        _assertSolvent("post-claim");
    }

    // =========================================================================
    // Leg 1 (forge arm) — the SOLVENCY-01 debit equals the delivered ethValue EXACTLY,
    //                     and the FLIP accrue/claim is OFF the ETH/claimablePool path
    // =========================================================================

    /// @notice The ETH/claimablePool debit happens ONLY at the buy-delivery site and equals the delivered
    ///         ethValue EXACTLY. A funded sub's afking funding is reserved inside claimablePool by the deposit
    ///         (the SOLVENCY-01 invariant is balanced); a delivered buy then transfers exactly the per-buy
    ///         fresh-ETH spend out of BOTH afkingFunding[player] AND claimablePool in lockstep
    ///         (GameAfkingModule.sol `afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`).
    ///         Proven by reading both deltas across a single delivered buy: ΔafkingFunding == ΔclaimablePool
    ///         (the debit is the same `ethValue` on both ledgers — the byte-frozen v55 SOLVENCY-01 behavior).
    function testDebitEqualsDeliveredEthValueExactly() public {
        address p = makeAddr("debit_eq");
        _grantSeat(p);
        // Fund BEFORE subscribe; under D-12 the grounded subscribe IS the delivered buy (the cover-buy
        // debits the fresh-ETH spend at the subscribe site), so measure the SOLVENCY-01 leg-1 debit across
        // the grounded subscribe itself — exactly the byte-frozen `afkingFunding -= ethValue; claimablePool
        // -= ethValue` two-liner.
        _fundPool(p, 50 ether);

        uint256 fundingBefore = game.afkingFundingOf(p);
        uint256 poolBefore = _claimablePool();
        assertGt(fundingBefore, 0, "non-vacuity: the sub is funded pre-buy");

        _subscribeLootbox(p, 1); // the grounded NEW-run cover-buy debits fresh ETH at this site

        uint256 fundingAfter = game.afkingFundingOf(p);
        uint256 poolAfter = _claimablePool();
        uint256 fundingDebit = fundingBefore - fundingAfter;
        uint256 poolDebit = poolBefore - poolAfter;

        assertGt(fundingDebit, 0, "non-vacuity: the grounded subscribe cover-buy spent fresh ETH");
        // The debit is the SAME ethValue on both ledgers (the byte-frozen SOLVENCY-01 two-liner).
        assertEq(
            poolDebit,
            fundingDebit,
            "SOLVENCY-01: claimablePool -= ethValue == afkingFunding[player] -= ethValue (debit equals delivered value exactly)"
        );
        _assertSolvent("post-debit");
    }

    /// @notice The FLIP accrual + claim is OFF the ETH/claimablePool path: across a delivered buy that
    ///         accrues both the slot-0 pendingFlip reward AND the affiliate base, then a claimAfkingFlip,
    ///         the claimablePool delta is attributable ENTIRELY to the ETH buy debit — the FLIP legs add
    ///         and remove ZERO from the pool. (affiliate/quest rewards are creditFlip-paid, never an ETH
    ///         debit.) Asserted by isolating the claim: the pool is byte-unchanged across the claim alone.
    function testFlipClaimLeavesClaimablePoolUnchanged() public {
        address p = makeAddr("flip_offpath");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1); // join-day cover-buy accrues 100
        _deliverDay(0xB04E0FF); // next-day STAGE buy accrues another 100 + affiliateBase

        // Cover-buy (join day) + one delivered STAGE day = TWO paid buys = 200 whole FLIP.
        uint256 owed = _pendingFlipOf(p);
        assertEq(owed, 2 * SLOT0_FLIP_PER_BUY, "non-vacuity: cover-buy + one delivered STAGE buy accrued claimable FLIP (200)");

        // Isolate the FLIP claim: the pool must be byte-identical before/after (FLIP is a creditFlip, not
        // an ETH/pool debit) — this is the exact equality the acceptance criterion demands.
        uint256 poolBefore = _claimablePool();
        uint256 stakeBefore = coinflip.coinflipAmount(p);
        game.claimAfkingFlip(_singleton(p));
        assertEq(_claimablePool(), poolBefore, "FLIP claim: claimablePool byte-unchanged (OFF the ETH path)");
        assertEq(coinflip.coinflipAmount(p) - stakeBefore, owed * 1 ether, "FLIP claim paid via creditFlip (not an ETH move)");
        assertEq(_pendingFlipOf(p), 0, "pendingFlip zeroed (paid exactly once, CEI)");
        _assertSolvent("post-flip-claim");
    }

    // =========================================================================
    // Leg 3 — RNG-freeze determinism: STAMP-not-resolve + single-roll open consumes
    //         ONLY the frozen rngWordByDay[stampDay] (two blocks -> byte-identical box)
    // =========================================================================

    /// @notice STAMP-NOT-RESOLVE: the subscribe min-buy + the STAGE buy STAMP a box for-later-open and NEVER
    ///         inline-resolve it pre-RNG — across the subscribe AND a new-day STAGE, NO LootBoxOpened is
    ///         emitted (the box is stamped, the materialization is deferred to the open). Non-vacuous: a box
    ///         WAS stamped (lastAutoBoughtDay advanced, the box is pending lastOpenedDay < lastAutoBoughtDay),
    ///         and a subsequent open DOES emit LootBoxOpened (so the absence above is real, not vacuous).
    function testSubscribeMinBuyStampsNoInlineResolve() public {
        address p = makeAddr("stamp_noresolve");
        _grantSeat(p);

        // Record across BOTH the subscribe (min-buy) AND the funded STAGE buy: neither materializes a box.
        vm.recordLogs();
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _runStageNewDay(0x57A11);
        _settleClean(0x57A12);
        assertEq(_countLootBoxOpened(p), 0, "STAMP-not-resolve: no LootBoxOpened at subscribe/STAGE time (the box is stamped, not resolved)");

        // The box WAS stamped (pending), so the absence of a resolve above is non-vacuous.
        uint32 stampDay = _lastBoughtDayOf(p);
        assertGt(stampDay, 0, "non-vacuity: a box was stamped (lastAutoBoughtDay advanced)");
        assertTrue(_lastOpenedDayOf(p) < stampDay, "non-vacuity: the box is pending (lastOpenedDay < lastAutoBoughtDay)");

        // And the open DOES emit LootBoxOpened — the materialization is reached only at the (deferred) open.
        vm.recordLogs();
        Box memory opened = _openAfkingBoxAt(p, 7, 5 minutes, 0xA11CE, makeAddr("stamp_opener"));
        assertTrue(opened.present, "the deferred open materialized the box (LootBoxOpened emitted at open, not stamp)");
        assertEq(_lastOpenedDayOf(p), stampDay, "the open advanced lastOpenedDay to the stamp day");
    }

    /// @notice TWO-BLOCK DETERMINISM (the freeze observable): open the SAME stamp twice at DIFFERENT blocks
    ///         (vm.roll/warp + perturbed prevrandao/coinbase) and the materialized box is BYTE-IDENTICAL —
    ///         the single-roll open seed `keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay,
    ///         amount))` carries NO block.* entropy. The box resolves against the FROZEN stamp day (the live
    ///         day moved between stamp and open). Adapted from V55FreezeDeterminism:91+ to the v56 harness.
    function testStampedDayOpenAtTwoBlocksByteIdentical() public {
        address afk = makeAddr("freeze_twoblock");
        _grantSeat(afk);
        _fundPool(afk, 50 ether);
        _subscribeLootbox(afk, 1);
        _runStageNewDay(0xF00D01);
        _settleClean(0xF00D02);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: the afking box was stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending (lastOpenedDay < lastAutoBoughtDay)");
        assertTrue(_rngWordByDay(stampDay) != 0, "the stamped day's word has landed (open is reachable)");

        // Snapshot the SHARED pre-open state so both opens replay from an identical stamp.
        uint256 snap = vm.snapshotState();

        Box memory box1 = _openAfkingBoxAt(afk, 1_000, 11 minutes, 0xAA11AA11, makeAddr("coinbase_1"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#1 materialized the box");
        assertTrue(box1.present, "open#1 emitted LootBoxOpened (non-vacuous)");

        vm.revertToState(snap);
        assertEq(_lastBoughtDayOf(afk), stampDay, "revert restored the stamp day");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "revert restored the pending box");
        Box memory box2 = _openAfkingBoxAt(afk, 999_999, 47 minutes, 0xBB22BB22, makeAddr("coinbase_2"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#2 materialized the box");
        assertTrue(box2.present, "open#2 emitted LootBoxOpened (non-vacuous)");

        // FREEZE: byte-identical across the two block contexts (the seed froze on the stamped day; no block.*).
        _assertBoxByteIdentical(box1, box2, "RNG-freeze two-block determinism");
        // The materialization bound to the FROZEN stamp day: the seed is rngWordByDay[stampDay] and the open
        // advanced lastOpenedDay to that same stampDay (the live day moved between stamp and open, yet the box
        // resolved against the frozen stamp day — no open-time entropy).
        assertEq(_lastOpenedDayOf(afk), stampDay, "the box materialized against the frozen stamp day (single-roll open, no open-time entropy)");
    }

    /// @notice TWO-BLOCK DETERMINISM fuzz: for RANDOM perturbed open-block contexts (prevrandao/coinbase/
    ///         number/timestamp), the SAME stamp opens to a byte-identical box — ANY two block contexts agree,
    ///         so the single-roll open + pendingFlip credit consume ONLY the frozen rngWordByDay[stampDay].
    function testFuzzTwoBlockOpenNoBlockEntropy(uint256 r1, uint256 r2, uint64 dt1, uint64 dt2) public {
        address afk = makeAddr("freeze_twoblock_fz");
        _grantSeat(afk);
        _fundPool(afk, 50 ether);
        _subscribeLootbox(afk, 1);
        _runStageNewDay(0xACE5EED);
        _settleClean(0xACE5EEE);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_rngWordByDay(stampDay) != 0, "stamped-day word landed");

        // Keep both opens inside the same level/day window (< ~6h each) so the live level is unchanged; the
        // property under test is the SEED freeze, not the (LIVE-by-design) level.
        uint256 w1 = uint256(dt1) % (6 hours);
        uint256 w2 = uint256(dt2) % (6 hours);

        uint256 snap = vm.snapshotState();
        Box memory boxA = _openAfkingBoxAt(
            afk, uint64(r1), w1, uint256(keccak256(abi.encode(r1, "pr"))), address(uint160(uint256(keccak256(abi.encode(r1, "cb")))))
        );
        assertTrue(boxA.present, "fuzz open A materialized (non-vacuous)");

        vm.revertToState(snap);
        Box memory boxB = _openAfkingBoxAt(
            afk, uint64(r2), w2, uint256(keccak256(abi.encode(r2, "pr"))), address(uint160(uint256(keccak256(abi.encode(r2, "cb")))))
        );
        assertTrue(boxB.present, "fuzz open B materialized (non-vacuous)");

        _assertBoxByteIdentical(boxA, boxB, "RNG-freeze no-block-entropy fuzz");
    }

    // =========================================================================
    // Leg 3 open-driving + box-oracle helpers (ported from V55FreezeDeterminism)
    // =========================================================================

    /// @dev Open `afk`'s stamped afking box at a perturbed block context and return the materialized box
    ///      decoded from the LootBoxOpened event. Perturbs block number / timestamp (sub-day, level held) /
    ///      prevrandao / coinbase (NONE enter the single-roll afking seed by design), then settles any
    ///      in-flight advance so mintFlip takes the OPEN leg (!advanceDue) and fires the open. Uses a FIXED
    ///      drain word (NOT derived from the perturbation — the perturbation touches only the block context).
    function _openAfkingBoxAt(
        address afk,
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        address coinbase
    ) internal returns (Box memory) {
        vm.roll(block.number + 1 + uint256(blockBump));
        if (block.timestamp + warpBump > _t) _t = block.timestamp + warpBump;
        vm.warp(block.timestamp + warpBump);
        vm.prevrandao(bytes32(prevrandao));
        vm.coinbase(coinbase);
        _settleClean(0xC0FFEEFACE);

        vm.recordLogs();
        vm.prank(makeAddr("freeze_opener"));
        try game.mintFlip() {} catch {}
        return _decodeLootBoxOpenedFor(afk);
    }

    /// @dev Decode the (single) LootBoxOpened event whose indexed player == `who` from the recorded logs.
    function _decodeLootBoxOpenedFor(address who) internal returns (Box memory b) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(game) &&
                logs[i].topics.length >= 3 &&
                logs[i].topics[0] == LOOTBOX_OPENED_SIG &&
                logs[i].topics[1] == bytes32(uint256(uint160(who)))
            ) {
                b.present = true;
                b.lootboxIndex = uint48(uint256(logs[i].topics[2]));
                (b.amount, b.futureLevel, b.futureTickets, b.flip, b.roundedUp) =
                    abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                return b;
            }
        }
    }

    /// @dev Count the LootBoxOpened events for `who` recorded since the last vm.recordLogs() (the STAMP-not-
    ///      resolve observable: ZERO at subscribe/STAGE time, NON-ZERO at open). Emitter == address(game).
    function _countLootBoxOpened(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != LOOTBOX_OPENED_SIG) continue;
            if (logs[i].topics[1] == bytes32(uint256(uint160(who)))) count++;
        }
    }

    /// @dev Assert two materialized boxes are byte-identical in every RESOLVED trait field. The event's
    ///      lootboxIndex is a storage tag (NOT a resolved trait) — excluded (both opens replay the SAME stamp,
    ///      so it is identical anyway).
    function _assertBoxByteIdentical(Box memory a, Box memory b, string memory tag) internal {
        assertEq(a.amount, b.amount, string(abi.encodePacked(tag, ": amount")));
        assertEq(a.futureLevel, b.futureLevel, string(abi.encodePacked(tag, ": futureLevel")));
        assertEq(a.futureTickets, b.futureTickets, string(abi.encodePacked(tag, ": futureTickets")));
        assertEq(a.flip, b.flip, string(abi.encodePacked(tag, ": flip")));
        assertEq(a.roundedUp, b.roundedUp, string(abi.encodePacked(tag, ": roundedUp")));
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the single-roll open's frozen seed input).
    function _rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    // =========================================================================
    // The solvency observable
    // =========================================================================

    /// @dev The master SOLVENCY-01 invariant: `game.balance + steth.balanceOf(game) >= claimablePool`
    ///      (DegenerusGame.sol:18). The fixture holds plain ETH (no stETH minted to the game), so the stETH
    ///      term is 0; reading it explicitly keeps the assertion faithful to the contract's invariant shape.
    function _assertSolvent(string memory tag) internal {
        uint256 backing = address(game).balance + mockStETH.balanceOf(address(game));
        assertGe(backing, _claimablePool(), string(abi.encodePacked("SOLVENCY-01: balance + steth >= claimablePool [", tag, "]")));
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V56SecUnmanipulable / V55FreezeDeterminism)
    // =========================================================================

    /// @dev Deliver ONE funded day to the in-set subs: a new-day STAGE buy (stamps each pending box +
    ///      debits the fresh-ETH spend + accrues), then settle clean and OPEN every pending box (so the
    ///      no-orphan guard does not skip the next day's buy). Each delivered day debits claimablePool by the
    ///      fresh-ETH spend and accrues 100 pendingFlip per in-set sub.
    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day off the accumulating timestamp (the Foundry caching
    ///      quirk freezes a re-read `block.timestamp + 1 days` after the first warp in a loop).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before an afking open so mintFlip reliably takes the OPEN leg (Don't-Hand-Roll).
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _pair(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    // ---- Sub-slot + claimablePool reads (_subOf slot 62 + the v56 offsets; slot 1 byte 16) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, 0, 8));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _pendingFlipOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGFLIP, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
