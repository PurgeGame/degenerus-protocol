// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @title V56FreezeSolvency -- the SEC-02 proof in three legs against the frozen subject:
///        (1) the ETH/claimablePool debit path (one in-context site, the delivered buy); (2) a
///        solvency invariant fuzz; (3) an RNG-freeze determinism fuzz.
///
/// @notice Leg 1. The ETH/claimablePool debit happens at exactly one in-context site -- the funded
///   delivery in the subscriber pass -- and the pool moves by the delivered value EXACTLY. Rewards are
///   derived from checkpoints and paid as FLIP (creditFlip_g317) at settlement, OFF the ETH/claimablePool
///   path: claiming FLIP leaves claimablePool byte-unchanged.
///
/// @notice Leg 2. The master invariant the Game maintains is
///   `address(this).balance + steth.balanceOf(this) >= claimablePool`. Across random {sub, unsub, buy,
///   claimAfkingFlip, top-up} sequences it always holds: the delivery debit decreases claimablePool by
///   exactly the ETH it spends from the (already-reserved) afking funding, and FLIP settlement never
///   touches the pool.
///
/// @notice Leg 3. The daily pass STAMPS a box for-later-open and NEVER inline-resolves it pre-RNG (no
///   LootBoxOpened at signup or at the pass). The single-roll open seed carries NO block.* entropy, so
///   two opens of the SAME stamp at DIFFERENT blocks (vm.roll/warp + perturbed prevrandao/coinbase)
///   materialize byte-identical boxes. The afking open is reached only through mineFlip().
contract V56FreezeSolvency is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf_g3120(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    /// @dev Wallet IDs of `a`, registering any that hold none.
    function _aids(address[] memory a) internal returns (uint32[] memory ids) {
        ids = new uint32[](a.length);
        for (uint256 i; i < a.length; ++i) ids[i] = _aid(a[i]);
    }

    uint256 private constant CLAIMABLE_POOL_SLOT = GameSlots.CLAIMABLE_POOL; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;

    /// @dev keccak256 of the materialized-box event — the byte-identity oracle's source signature.
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");

    /// @dev Whole FLIP a box-mode unit earns per credited day.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;
    DegenerusGameLens private lens;

    /// @dev A decoded LootBoxOpened payload — every non-indexed field of the materialized box.
    struct Box {
        bool present;
        bytes32 resultsDigest;
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
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // Leg 2 — the solvency invariant across churn / accrue / claim
    // =========================================================================

    /// @notice The master solvency invariant `game.balance + steth.balanceOf(game) >= claimablePool` holds
    ///         after EVERY action in a fuzzed {sub, unsub, buy(=deliver a funded day), claimAfkingFlip,
    ///         top-up} sequence. Each delivered day debits claimablePool by exactly its ETH spend (already
    ///         reserved inside the pool by the funding deposit), and FLIP settlement moves no ETH.
    ///         Non-vacuous: at least one delivered buy actually moved the pool.
    function testFuzzSolvencyInvariantUnderChurn(uint256 seq, uint8 rounds) public {
        address a = makeAddr("solv_a");
        address b = makeAddr("solv_b");
        _grantSeat(a);
        _grantSeat(b);
        _fundPool(a, 200 ether);
        _fundPool(b, 200 ether);
        _subscribeLootbox(a, 1);
        _subscribeLootbox(b, 1);

        _assertSolvent("post-setup");

        // Anchor buy: always deliver one funded day first so the invariant is exercised against a pool a
        // real buy has moved (the fuzzed action stream may otherwise pick no buy at all).
        uint256 poolBeforeAnchor = _claimablePool();
        _deliverDay(uint256(keccak256(abi.encode("solvanchor", seq))) | 1);
        assertLt(_claimablePool(), poolBeforeAnchor, "non-vacuity: the anchor buy moved the pool");
        _assertSolvent("post-anchor-buy");

        uint256 n = 3 + (uint256(rounds) % 6); // 3..8 actions
        for (uint256 i; i < n; i++) {
            uint256 action = (seq >> (i * 3)) & 0x7;
            if (action < 4) {
                // buy: deliver a funded day to BOTH subs (debits the pool by the ETH spend).
                _deliverDay(uint256(keccak256(abi.encode("solvbuy", seq, i))) | 1);
            } else if (action == 4) {
                // claimAfkingFlip: pays the elapsed FLIP — must NOT move claimablePool.
                uint256 poolBefore = _claimablePool();
                game.claimAfkingFlip(_aids(_pair(a, b)));
                assertEq(_claimablePool(), poolBefore, "claimAfkingFlip left claimablePool byte-unchanged (OFF the ETH path)");
            } else if (action == 5) {
                // cancel a: the record is removed at once; the residual funding stays reserved in the pool.
                if (_subscriberIndexOf(a) != 0) {
                    vm.prank(a);
                    game.subscribe(0, false, 0, 0);
                }
            } else if (action == 6) {
                // re-sub a (a new run) if it is not currently a member.
                if (_subscriberIndexOf(a) == 0) {
                    _fundPool(a, 20 ether);
                    _subscribeLootbox(a, 1);
                }
            } else {
                // top up b's funding (deposit credits afkingFunding + claimablePool in tandem).
                _fundPool(b, 20 ether);
                if (_subscriberIndexOf(b) == 0) _subscribeLootbox(b, 1);
            }
            _assertSolvent("post-action");
        }
        _assertSolvent("final");
    }

    /// @notice A focused named repro of leg 2's core: a delivered funded buy debits claimablePool, and a
    ///         subsequent claimAfkingFlip leaves the pool byte-unchanged. The solvency invariant holds
    ///         across both.
    function testSolvencyHoldsBuyThenFlipClaim() public {
        address p = makeAddr("solv_repro");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _assertSolvent("post-fund");

        uint256 poolBeforeSignup = _claimablePool();
        _subscribeLootbox(p, 1);
        assertEq(_claimablePool(), poolBeforeSignup, "signup buys nothing: the pool is untouched");

        uint256 poolBeforeBuy = _claimablePool();
        _deliverDay(0xB04E0F1);
        assertLt(_claimablePool(), poolBeforeBuy, "the delivered buy debited claimablePool by its spend");
        _assertSolvent("post-buy");
        assertEq(_owedFlip(p), SLOT0_FLIP_PER_BUY, "the delivered day owes 100 whole FLIP (OFF the ETH path)");

        uint256 poolBeforeClaim = _claimablePool();
        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_claimablePool(), poolBeforeClaim, "claimAfkingFlip: claimablePool byte-unchanged (FLIP is OFF the ETH/pool path)");
        assertEq(_flipClaimed(p), SLOT0_FLIP_PER_BUY, "the FLIP was paid");
        assertEq(_owedFlip(p), 0, "nothing owed after the claim");
        _assertSolvent("post-claim");
    }

    // =========================================================================
    // Leg 1 (forge arm) — the debit equals the delivered value EXACTLY,
    //                     and the FLIP settlement is OFF the ETH/claimablePool path
    // =========================================================================

    /// @notice The ETH/claimablePool debit happens ONLY at the buy-delivery site and equals the delivered
    ///         value EXACTLY. A funded sub's afking funding is reserved inside claimablePool by the deposit;
    ///         a preparation call that delivers moves exactly the sum of the AfkingDelivered values out of
    ///         claimablePool, and the subscriber's own prepaid balance drops by its own delivered value.
    function testDebitEqualsDeliveredValueExactly() public {
        address p = makeAddr("debit_eq");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _settleClean(0xDEB17);
        _t += 1 days;
        vm.warp(_t);

        uint32 id = game.walletIdOf_g3120(p);
        uint256 fundingDebit;
        uint256 poolDebit;
        uint256 delivered;
        for (uint256 i; i < DRAIN_MAX_ITERATIONS && delivered == 0; ++i) {
            uint256 poolBefore = _claimablePool();
            uint256 fundingBefore = game.afkingFundingOf(p);
            vm.recordLogs();
            game.mineRun(0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 total;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics.length < 2
                    || logs[j].topics[0] != keccak256("AfkingDelivered(uint32,uint256)")) continue;
                uint256 wei_ = uint128(abi.decode(logs[j].data, (uint256)));
                total += wei_;
                if (uint32(uint256(logs[j].topics[1])) == id) delivered = wei_;
            }
            if (delivered != 0) {
                fundingDebit = fundingBefore - game.afkingFundingOf(p);
                poolDebit = poolBefore - _claimablePool();
                assertEq(poolDebit, total, "claimablePool moved by exactly the delivered values");
            }
        }
        assertGt(delivered, 0, "non-vacuity: the sub's buy was delivered");
        assertEq(fundingDebit, delivered, "the prepaid balance paid exactly the delivered value");
        _assertSolvent("post-debit");
    }

    /// @notice The FLIP settlement is OFF the ETH/claimablePool path: across a delivered buy that owes both
    ///         the member reward AND the affiliate base, a claimAfkingFlip leaves the pool byte-unchanged.
    function testFlipClaimLeavesClaimablePoolUnchanged() public {
        address p = makeAddr("flip_offpath");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(0xB04E0FF);

        DegenerusGameLens.SubFull memory owed = lens.subInfoFullById(address(game), game.walletIdOf_g3120(p));
        assertEq(owed.owedFlip, SLOT0_FLIP_PER_BUY, "non-vacuity: one delivered day owes the member reward");
        assertEq(owed.owedAffiliateBase, 70, "and the affiliate base");

        uint256 poolBefore = _claimablePool();
        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_claimablePool(), poolBefore, "FLIP claim: claimablePool byte-unchanged (OFF the ETH path)");
        assertEq(_flipClaimed(p), owed.owedFlip, "FLIP claim paid via creditFlip_g317 (not an ETH move)");
        assertEq(_owedFlip(p), 0, "owed zeroed (paid exactly once)");
        _assertSolvent("post-flip-claim");
    }

    // =========================================================================
    // Leg 3 — RNG-freeze determinism: STAMP-not-resolve + single-roll open consumes
    //         ONLY the frozen _recordedDailyWord(stampDay) (two blocks -> byte-identical box)
    // =========================================================================

    /// @notice STAMP-NOT-RESOLVE: signup buys nothing and the pass STAMPS a box for-later-open without
    ///         inline-resolving it pre-RNG — across the signup AND a new-day pass, NO LootBoxOpened is
    ///         emitted. Non-vacuous: a box WAS stamped (it is pending), and a subsequent open DOES emit
    ///         LootBoxOpened.
    function testPassStampsNoInlineResolve() public {
        address p = makeAddr("stamp_noresolve");
        _grantSeat(p);

        vm.recordLogs();
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        assertEq(_countLootBoxOpened(p), 0, "no LootBoxOpened at signup");
        assertFalse(GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(p)), "signup stamps no box");
        _settleGame(0x57A10);
        vm.recordLogs();
        _stampNewDay(0x57A11);
        assertEq(_countLootBoxOpened(p), 0, "STAMP-not-resolve: no LootBoxOpened at the pass (the box is stamped, not resolved)");

        // The box WAS stamped (pending), so the absence of a resolve above is non-vacuous.
        uint32 stampDay = _resetDay();
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(p)), "non-vacuity: a box was stamped and is pending");
        assertTrue(_lastOpenedDayOf(p) < stampDay, "the opened day trails the stamp day");

        // And the open DOES emit LootBoxOpened — the materialization is reached only at the (deferred) open.
        vm.recordLogs();
        Box memory opened = _openAfkingBoxAt(p, 7, 5 minutes, 0xA11CE, makeAddr("stamp_opener"));
        assertTrue(opened.present, "the deferred open materialized the box (LootBoxOpened emitted at open, not stamp)");
        assertEq(_lastOpenedDayOf(p), stampDay, "the open advanced the opened day to the stamp day");
    }

    /// @notice TWO-BLOCK DETERMINISM (the freeze observable): open the SAME stamp twice at DIFFERENT blocks
    ///         (vm.roll/warp + perturbed prevrandao/coinbase) and the materialized box is BYTE-IDENTICAL —
    ///         the single-roll open seed carries NO block.* entropy. The box resolves against the FROZEN
    ///         stamp day (the live day moved between stamp and open).
    function testStampedDayOpenAtTwoBlocksByteIdentical() public {
        address afk = makeAddr("freeze_twoblock");
        _grantSeat(afk);
        _fundPool(afk, 50 ether);
        _subscribeLootbox(afk, 1);
        _stampNewDay(0xF00D01);

        uint32 stampDay = _resetDay();
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(afk)), "non-vacuity: the afking box was stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending (opened day trails the stamp day)");

        // Snapshot the SHARED pre-open state (stamp taken, its day's request in flight) so both opens
        // replay from an identical stamp; each open delivers the same word and runs the session.
        uint256 snap = vm.snapshotState();

        Box memory box1 = _openAfkingBoxAt(afk, 1_000, 11 minutes, 0xAA11AA11, makeAddr("coinbase_1"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#1 materialized the box");
        assertTrue(box1.present, "open#1 emitted a box result (non-vacuous)");
        assertTrue(_rngWordByDay(stampDay) != 0, "the stamped day's word landed before its open");

        vm.revertToState(snap);
        assertEq(_resetDay(), stampDay, "revert restored the stamp day");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "revert restored the pending box");
        Box memory box2 = _openAfkingBoxAt(afk, 999_999, 47 minutes, 0xBB22BB22, makeAddr("coinbase_2"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#2 materialized the box");
        assertTrue(box2.present, "open#2 emitted a box result (non-vacuous)");

        // FREEZE: byte-identical across the two block contexts (the seed froze on the stamped day; no block.*).
        _assertBoxByteIdentical(box1, box2, "RNG-freeze two-block determinism");
    }

    /// @notice TWO-BLOCK DETERMINISM fuzz: for RANDOM perturbed open-block contexts (prevrandao/coinbase/
    ///         number/timestamp), the SAME stamp opens to a byte-identical box — ANY two block contexts agree,
    ///         so the single-roll open consumes ONLY the frozen _recordedDailyWord(stampDay).
    function testFuzzTwoBlockOpenNoBlockEntropy(uint256 r1, uint256 r2, uint64 dt1, uint64 dt2) public {
        address afk = makeAddr("freeze_twoblock_fz");
        _grantSeat(afk);
        _fundPool(afk, 50 ether);
        _subscribeLootbox(afk, 1);
        _stampNewDay(0xACE5EED);

        uint32 stampDay = _resetDay();
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(afk)), "non-vacuity: stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "stamp pending its day's word");

        // Keep both opens inside the same level/day window (< ~6h each) so the live level is unchanged; the
        // property under test is the SEED freeze, not the (LIVE-by-design) level.
        uint256 w1 = uint256(dt1) % (6 hours);
        uint256 w2 = uint256(dt2) % (6 hours);

        uint256 snap = vm.snapshotState();
        Box memory boxA = _openAfkingBoxAt(
            afk, uint64(r1), w1, uint256(keccak256(abi.encode(r1, "pr"))), address(uint160(uint256(keccak256(abi.encode(r1, "cb")))))
        );
        assertTrue(boxA.present, "fuzz open A materialized (non-vacuous)");
        assertTrue(_rngWordByDay(stampDay) != 0, "stamped-day word landed");

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
    ///      prevrandao / coinbase (NONE enter the single-roll afking seed by design), then delivers the
    ///      stamped day's word and runs the session: the open is its AFKing consumer step. Uses a FIXED
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

        vm.recordLogs();
        _settleClean(0xC0FFEEFACE);
        vm.prank(makeAddr("freeze_opener"));
        try game.mineRun(0) {} catch {}
        return _decodeLootBoxOpenedFor(afk);
    }

    /// @dev Include plain boxes, spins and their nested results in the byte-identity digest.
    function _decodeLootBoxOpenedFor(address who) internal returns (Box memory b) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || logs[i].topics[1] != bytes32(uint256(game.walletIdOf_g3120(who)))) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic != LOOTBOX_OPENED_SIG
                && topic != keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")) continue;
            b.present = true;
            b.resultsDigest = keccak256(abi.encode(b.resultsDigest, logs[i].topics, logs[i].data));
            if (topic == LOOTBOX_OPENED_SIG) {
                b.lootboxIndex = uint48(uint256(logs[i].topics[2]));
                (b.amount, b.futureLevel, b.futureTickets, b.flip, b.roundedUp) =
                    abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
            }
        }
    }

    /// @dev Count the LootBoxOpened events for `who` recorded since the last vm.recordLogs() (the STAMP-not-
    ///      resolve observable: ZERO at subscribe/STAGE time, NON-ZERO at open). Emitter == address(game).
    function _countLootBoxOpened(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != LOOTBOX_OPENED_SIG &&
                logs[i].topics[0] != keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")) continue;
            if (logs[i].topics[1] == bytes32(uint256(game.walletIdOf_g3120(who)))) count++;
        }
    }

    /// @dev Assert two materialized boxes are byte-identical in every RESOLVED trait field. The event's
    ///      lootboxIndex is a storage tag (NOT a resolved trait) — excluded (both opens replay the SAME stamp,
    ///      so it is identical anyway).
    function _assertBoxByteIdentical(Box memory a, Box memory b, string memory tag) internal {
        assertEq(a.resultsDigest, b.resultsDigest, string(abi.encodePacked(tag, ": all box results")));
        assertEq(a.amount, b.amount, string(abi.encodePacked(tag, ": amount")));
        assertEq(a.futureLevel, b.futureLevel, string(abi.encodePacked(tag, ": futureLevel")));
        assertEq(a.futureTickets, b.futureTickets, string(abi.encodePacked(tag, ": futureTickets")));
        assertEq(a.flip, b.flip, string(abi.encodePacked(tag, ": flip")));
        assertEq(a.roundedUp, b.roundedUp, string(abi.encodePacked(tag, ": roundedUp")));
    }

    /// @dev Read the DAY-keyed afking word `_recordedDailyWord(day)` (the single-roll open's frozen seed input).
    function _rngWordByDay(uint32 day) internal view returns (uint256) {
        return RecyclingState.dailyWord(address(game), uint24(day));
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
    ///      fresh-ETH spend and owes 100 whole FLIP per in-set box sub.
    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day off the accumulating timestamp (the Foundry caching
    ///      quirk freezes a re-read `block.timestamp + 1 days` after the first warp in a loop).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    /// @dev Finish the current day, then open a NEW day up to its daily request: the subscriber
    ///      preparation stamps each funded sub's box for that day, and the request commits the day's
    ///      word, which is left undelivered (the box stays pending until its session's AFKing step).
    function _stampNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < DRAIN_MAX_ITERATIONS && mockVRF.lastRequestId() == before; ++i) game.mineRun(0);
        assertGt(mockVRF.lastRequestId(), before, "harness: the new day's request is in flight");
    }

    function _settleGame(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineRun(0);
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before an afking open so mineFlip reliably takes the OPEN leg (Don't-Hand-Roll).
    function _settleClean(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
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
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
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

    // ---- Lane reads + claimablePool ----

    function _resetDay() internal view returns (uint32) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_RESET_DAY)))
            >> (GameSlots.AFKING_RESET_DAY_OFFSET * 8));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return GameSlotKeys.afkingOpenedDay(address(game), game.walletIdOf_g3120(who));
    }

    /// @dev `who`'s set position + 1; 0 = not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
    }

    function _owedFlip(address who) internal view returns (uint256) {
        return lens.subInfoFullById(address(game), game.walletIdOf_g3120(who)).owedFlip;
    }

    /// @dev Whole FLIP the AfkingFlipClaimed events recorded since the last vm.recordLogs() paid `who`.
    function _flipClaimed(address who) internal returns (uint256 total) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AfkingFlipClaimed(uint32,uint256)");
        uint32 id = game.walletIdOf_g3120(who);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            total += abi.decode(logs[i].data, (uint256));
        }
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
