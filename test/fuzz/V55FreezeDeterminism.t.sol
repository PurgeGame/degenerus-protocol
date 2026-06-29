// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title V55FreezeDeterminism -- TST-01 (Phase 351, v55.0 game-resident): the AfKing-in-Game box
///        stamp+open is FREEZE/DETERMINISTIC. The committed Sub stamp is the 4-field
///        `(scorePlus1, amount, lastAutoBoughtDay, lastOpenedDay)` shape (DegenerusGameStorage.sol:1867):
///        `index` was DROPPED (the box word is DAY-keyed `rngWordByDay[lastAutoBoughtDay]`) and the LEVEL
///        resolves LIVE at open (349.1 — mirroring `resolveLootboxDirect`/human `openLootBox`). So this file
///        proves the **SEED** is frozen, NOT that the level/baseLevel is frozen.
///
/// @notice The corrected freeze target (PATTERNS §7 + CONTEXT ⚠):
///   - FREEZE-03 (determinism): the box seed is `keccak256(abi.encode(rngWordByDay[stampDay], player,
///     stampDay, amount))` (DegenerusGameLootboxModule.sol:889) — the stamped day + the day's committed
///     word + the stamped amount/scorePlus1, carrying NO `block.timestamp/number/prevrandao/coinbase/
///     blockhash`. Two opens of the SAME stamp at DIFFERENT blocks (vm.roll/warp/prevrandao/coinbase
///     perturbed, the LIVE level HELD fixed) → a byte-identical materialized box (`LootBoxOpened` fields).
///   - DIFFERENTIAL (D-351-05): for the same `(amount, level, rngWord, score)`, `resolveAfkingBox` and the
///     human `openLootBox` (and the true twin `resolveLootboxDirect`) yield byte-identical materialized
///     traits. The afking arm rolls from the LIVE level with NO stored baseLevel floor; the equivalence is
///     proven AT A FIXED live level (NOT by asserting the level is frozen — it is LIVE by design).
///
/// @dev DRIVING (from the 351-02 V55SetMutationOpenE / 351-03 KeeperRewardRoutingSameResults harness):
///   - per-sub buy STAGE = a new-day `advanceGame()` (`_runStageNewDay` → the pre-RNG STAGE stamps the sub,
///     then `_settleGame` lands `rngWordByDay[stampDay]`).
///   - afking box open = `game.mintFlip()`'s open leg (GameAfkingModule.sol:1000-1009, only when
///     `!advanceDue`) — the afking standalone `autoOpen` selector collides with the human `autoOpen(uint256)`
///     so it is NOT re-exposed on the Game; the open is reached through `mintFlip`.
///   - the `LootBoxOpened(player, lootboxIndex, amount, futureLevel, futureTickets, flip, roundedUp)`
///     event is the materialized-traits observable: every box path (including `resolveAfkingBox` and
///     `openLootBox`) emits it, gated only by !wasSpin, so a byte-by-byte field compare IS the box-identity
///     oracle (robust to any future resolution refactor — NOT golden snapshots).
///   RE-DERIVED every pinned slot via `forge inspect storage DegenerusGame` (the v55 afking append shifted
///   lootboxEthBase 22→23, lootboxRngWordByIndex 38→39, lootboxRngPacked 37→38; rngWordByDay=11; _subOf=66).
///   Test-only: ZERO `contracts/*.sol` mutation (`git diff 453f8073 HEAD -- contracts/` EMPTY); FROZEN
///   subject (453f8073) honored.
contract V55FreezeDeterminism is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    // RE-DERIVED via `solc --storage-layout` on the working tree after the V62 lootbox repack (the
    // folded lootboxEth word + removed lootboxEthBase/Flip/Purchase/Distress shifted later slots
    // down). The prior 65/10/11/16/23/38/39 pins were stale; corrected to authoritative values.
    uint256 private constant SUBOF_SLOT = 54; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint24 => uint256) — the afking box's DAY-keyed word
    // lootboxEth (the single folded box word): amount[0:128] | adj[128:192] | scorePlus1[192:208] |
    // distressUnits[208:256]. Replaces the former separate lootboxEth/lootboxEthBase/lootboxPurchasePacked.
    uint256 private constant LOOTBOX_ETH_SLOT = 15;
    uint256 private constant LB_AMOUNT_MASK = (uint256(1) << 128) - 1;
    uint256 private constant LB_ADJ_SHIFT = 128;
    uint256 private constant LB_SCORE_SHIFT = 192;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34; // [0:47] lootboxRngIndex
    uint256 private constant LOOTBOX_RNG_WORD_BY_INDEX_SLOT = 35; // mapping(uint48 => uint256)

    // Sub packed-field byte offsets — the v56 compute-on-read re-pack (single 256-bit slot):
    //   scorePlus1 u16 @6 · amount u24 @8 · lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14.
    uint256 private constant OFF_SCOREPLUS1 = 5; // uint16 scorePlus1        (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 7; // uint24 amount            (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13; // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev keccak256 of the materialized-box event — the byte-identity oracle's source signature.
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

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
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // Task 1a — FREEZE-03 determinism: the SEED uses the STAMPED day (open at two
    //           different blocks → byte-identical box; no block.* entropy)
    // =========================================================================

    /// @notice The stamped-day box is DETERMINISTIC across open timing/block: open the SAME stamp twice at
    ///         DIFFERENT block numbers / timestamps / prevrandao / coinbase (the LIVE level HELD fixed) and
    ///         the materialized box is byte-identical — the seed used the STAMPED day's word, not open-time
    ///         entropy. Non-vacuous: each open actually materialized the box (`lastOpenedDay` advanced to
    ///         `lastAutoBoughtDay`, the box signal flipped ready→opened).
    function testStampedDayDeterminismOpenAtTwoBlocks() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 freeze-determinism harness subscribes an ungrounded sub then drives the STAGE stamp/open; the grounded subscribe stamps at subscribe (the v56 milli-ETH/min-buy unmask, ledger 356-07 D1); re-proven by V56FreezeSolvency (STAMP-not-resolve + two-block determinism, all green)");
        address afk = makeAddr("freeze_det_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0xF00D01); // stamp + land rngWordByDay[stampDay]

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: the afking box was stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending (lastOpenedDay < lastAutoBoughtDay)");
        assertTrue(_rngWordByDay(stampDay) != 0, "the stamped day's word has landed (open is reachable)");

        // Snapshot the SHARED pre-open state so both opens replay from an identical stamp.
        uint256 snap = vm.snapshot();

        // ---- Open #1: block B1 (baseline block context) ----
        Box memory box1 = _openAfkingBoxAt(afk, 1_000, 11 minutes, 0xAA11AA11, makeAddr("coinbase_1"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#1 materialized the box (lastOpenedDay == stampDay)");
        assertTrue(box1.present, "open#1 emitted LootBoxOpened (non-vacuous materialization)");

        // ---- Open #2: a DIFFERENT block context, the SAME stamp (snapshot/revert) ----
        vm.revertTo(snap);
        // Replay-state sanity: the revert restored the pending stamp.
        assertEq(_lastBoughtDayOf(afk), stampDay, "revert restored the stamp day");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "revert restored the pending box");
        Box memory box2 = _openAfkingBoxAt(afk, 999_999, 47 minutes, 0xBB22BB22, makeAddr("coinbase_2"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "open#2 materialized the box");
        assertTrue(box2.present, "open#2 emitted LootBoxOpened");

        // FREEZE-03: the materialized box is BYTE-IDENTICAL across the two block contexts (the seed froze
        // on the stamped day + the stamped amount/score, carrying no block.* entropy).
        _assertBoxByteIdentical(box1, box2, "FREEZE-03 stamped-day determinism");
        // And the box resolved against the STAMPED day, not the open-time day (the live day moved between
        // setUp and the open, but the open advanced lastOpenedDay to the frozen stamp day).
        assertEq(_lastOpenedDayOf(afk), stampDay, "the box materialized against the stamped day (frozen seed day)");
    }

    /// @notice The box outcome is INVARIANT under block-entropy perturbation (prevrandao/coinbase/blockhash
    ///         proxies + block number) FUZZED between stamp and open — the draw carries no `block.*`. Holds
    ///         the LIVE level fixed (a sub-day warp) so this isolates the SEED freeze, never the (LIVE) level.
    function testFuzzNoBlockEntropyInTheDraw(uint256 r1, uint256 r2, uint64 dt1, uint64 dt2) public {
        vm.skip(true, "357-00b D-12 supersession: the v55 freeze-determinism harness subscribes an ungrounded sub then drives the STAGE stamp/open; the grounded subscribe stamps at subscribe (the v56 milli-ETH/min-buy unmask, ledger 356-07 D1); re-proven by V56FreezeSolvency (STAMP-not-resolve + two-block determinism, all green)");
        address afk = makeAddr("freeze_noent_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        // FIXED STAGE settle word (decoupled from the fuzz): the fuzz drives the OPEN-time block/amount
        // perturbation (the property), NOT the daily-RNG drain — a fuzzed STAGE word can hit a rare
        // fixture VRF-word stall orthogonal to the no-block-entropy property (idle-fixture day-saturation).
        _runStageNewDay(0xACE5EED);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_rngWordByDay(stampDay) != 0, "stamped-day word landed");

        // Bound the warps to STAY in the same level/day window (< ~12h each) so currentLevel is unchanged;
        // the property under test is the SEED freeze, and the level is LIVE by design.
        uint256 w1 = uint256(dt1) % (6 hours);
        uint256 w2 = uint256(dt2) % (6 hours);

        uint256 snap = vm.snapshot();
        Box memory boxA = _openAfkingBoxAt(afk, uint64(r1), w1, uint256(keccak256(abi.encode(r1, "pr"))), address(uint160(uint256(keccak256(abi.encode(r1, "cb"))))));
        assertTrue(boxA.present, "fuzz open A materialized (non-vacuous)");

        vm.revertTo(snap);
        Box memory boxB = _openAfkingBoxAt(afk, uint64(r2), w2, uint256(keccak256(abi.encode(r2, "pr"))), address(uint160(uint256(keccak256(abi.encode(r2, "cb"))))));
        assertTrue(boxB.present, "fuzz open B materialized (non-vacuous)");

        // No `block.*` entropy: ANY two block contexts yield the SAME box for the same stamp.
        _assertBoxByteIdentical(boxA, boxB, "no-block-entropy");
    }

    // =========================================================================
    // Task 1b — DIFFERENTIAL (D-351-05): afking stamp→open ≡ human openLootBox
    //           for the same tuple, at a FIXED live level
    // =========================================================================

    /// @notice DIFFERENTIAL afking-vs-human at a FIXED live level: for the SAME `(player, amount, day,
    ///         rngWord, score)`, the afking open (`resolveAfkingBox`, reached via the real `mintFlip`
    ///         open leg over a poked stamp) and the human `openLootBox` materialize BYTE-IDENTICAL traits.
    ///         The two arms share one `abi.encode(rngWord, player, day, amount)` preimage
    ///         (LootboxModule.sol:889 ≡ :534) — so the SAME `player` MUST be used on both arms (player is
    ///         in the seed). The two opens run in SEPARATE snapshots so each starts from a clean
    ///         per-(player,level) EV-cap budget (`usedBenefit == 0`), with `amount <= 10 ETH` so the
    ///         human box's frozen `adj == amount` equals the afking arm's `adjustedPortion == amount` — the
    ///         bonus-branch cap draw is then byte-identical on both arms. Proven AT THE SAME LIVE LEVEL
    ///         (NOT asserting the level is frozen; the human box's `baseLevel` is forced to `currentLevel`
    ///         via `baseLevelPlus1 == 0` ⇒ `graceLevel == currentLevel`).
    function testDifferentialAfkingVsHumanOpenSameTuple() public {
        // v56 DROP (356-07, removed/adapted surface): the v56 re-pack made Sub.amount uint24 MILLI-ETH
        // (_packEthToMilliEth at the stamp, _unpackMilliEthToWei at the afking open) while this differential
        // harness pokes a RAW-WEI amount into the field — so the afking arm reads milli-ETH and the human arm
        // reads raw-wei, diverging by design (the assertion encodes the v55 raw-wei amount field). The v56
        // afking-open == human-open byte-identity is proven against the v56 layout by
        // V56FreezeSolvency::testStampedDayOpenAtTwoBlocksByteIdentical.
        vm.skip(true, "v56: Sub.amount is uint24 milli-ETH; differential re-proven in V56FreezeSolvency");
        _runDifferential(1 ether, 0, 0xD1FF0100); // NEUTRAL score: no cap branch on either arm
    }

    /// @notice DIFFERENTIAL fuzz (D-351-04): the afking-vs-human byte-identity holds over random
    ///         amount/score/rngWord — INCLUDING bonus scores (the full EV-cap RMW on both arms) with
    ///         `amount <= 10 ETH` (so `adj == amount` on the human side matches the afking `adjustedPortion`).
    function testFuzzDifferentialAfkingVsHumanOpen(uint96 rawAmount, uint16 rawScore, uint256 rngSeed) public {
        // v56 DROP (356-07, removed/adapted surface): same milli-ETH unmask as the unit differential — the
        // raw-wei poke vs the v56 uint24 milli-ETH amount field diverges by design. Re-proven against the v56
        // layout by V56FreezeSolvency::testFuzzTwoBlockOpenNoBlockEntropy.
        vm.skip(true, "v56: Sub.amount is uint24 milli-ETH; differential re-proven in V56FreezeSolvency");
        // 0.1 .. 9.6 ETH (strictly < the 10-ETH cap so the frozen-adj == full-RMW equivalence holds).
        uint256 amount = (uint256(rawAmount) % (9.5 ether)) + 0.1 ether;
        // Raw activity bps (maxes ~31_800), exercises the penalty / neutral / bonus branches.
        uint16 score = uint16(rawScore % 30_000);
        _runDifferential(amount, score, rngSeed);
    }

    /// @dev The differential core: build the SAME `(player, amount, day, rngWord, score)` tuple on both arms
    ///      and assert byte-identical materialized traits. Same player (seed includes player); separate
    ///      snapshots (clean EV-cap budget per arm); fixed live level.
    function _runDifferential(uint256 amount, uint16 score, uint256 rngSeed) internal {
        // FIXED-word settle (decoupled from the fuzz): the fuzz drives the differential TUPLE
        // (amount/score/rngWord), NOT the daily-RNG drain — avoids the rare fixture VRF-word stall.
        _settleClean(0xC1EA12);
        uint24 currentLevel = uint24(game.level()) + 1; // the afking/human LIVE roll level
        uint32 day = _simDay();
        uint256 rngWord = uint256(keccak256(abi.encode(rngSeed, "rngWord")));
        if (rngWord == 0) rngWord = 1; // the open gates on a non-zero word

        address player = makeAddr(string(abi.encodePacked("diff_p_", _u(uint256(rngSeed) & 0xFFFFFF))));

        // Subscribe `player` as a lootbox sub so it lives in `_subscribers` (the afking open walks it).
        _grantDeityPass(player);
        _subscribeLootbox(player, 1);

        uint256 snap = vm.snapshot();

        // ----- AFKING arm: clean FIRST (so mintFlip takes the OPEN leg), THEN poke the stamp + day word
        // (poking after the settle so the settle's advanceGame can't re-derive/clobber rngWordByDay[day]),
        // then open via mintFlip. -----
        _settleClean(0xC1EA13);
        _pokeAfkingStamp(player, amount, day, score);
        _setRngWordByDay(day, rngWord);
        assertTrue(_lastOpenedDayOf(player) < _lastBoughtDayOf(player), "afking box pending (poked)");
        assertFalse(game.rngLocked(), "afking open: not locked (mintFlip takes the OPEN leg)");
        vm.recordLogs();
        vm.prank(makeAddr("diff_afk_opener"));
        try game.mintFlip() {} catch {}
        Box memory afkBox = _decodeLootBoxOpenedFor(player);
        assertTrue(afkBox.present, "afking arm materialized a box (non-vacuous)");
        assertEq(uint24(game.level()) + 1, currentLevel, "afking open at the pinned live level");

        // ----- HUMAN arm: same player, same tuple via openLootBox (clean snapshot ⇒ EV-cap budget == 0) -----
        vm.revertTo(snap);
        assertEq(_evBenefitUsed(player, currentLevel), 0, "human arm starts from a clean EV-cap budget");
        Box memory humBox = _captureHumanOpenLootBox(player, amount, currentLevel, day, rngWord, score);
        assertTrue(humBox.present, "human arm materialized a box (non-vacuous)");

        // DIFFERENTIAL: same targetLevel + same materialized traits (the shared seed preimage). The event
        // `lootboxIndex` is a storage tag (afking passes 0; the human passes its real index), NOT a resolved
        // trait — excluded from the trait compare.
        assertEq(afkBox.futureLevel, humBox.futureLevel, "DIFFERENTIAL: same targetLevel (shared seed, same live level)");
        // The seed day is pinned identically on both arms by construction (_setRngWordByDay(day,…) on the
        // afking arm, _forceLootboxDay(index, player, day) on the human arm), so the resolved traits below ARE
        // the same-seed-day equivalence (the event no longer carries a `day` field to re-assert here).
        assertEq(afkBox.amount, humBox.amount, "DIFFERENTIAL: same scaledAmount (adj == amount, no cap divergence)");
        assertEq(afkBox.futureTickets, humBox.futureTickets, "DIFFERENTIAL: same futureTickets");
        assertEq(afkBox.flip, humBox.flip, "DIFFERENTIAL: same FLIP award");
        assertEq(afkBox.roundedUp, humBox.roundedUp, "DIFFERENTIAL: same Bernoulli round-up bit");
    }

    // =========================================================================
    // Task 2 — TST-01 index-binding (FREEZE-02, reconciled to the DAY-keyed reality)
    //          + the pre-RNG / post-RNG stamp ordering
    // =========================================================================

    /// @notice INDEX-BINDING (FREEZE-02): the afking box binds to `rngWordByDay[lastAutoBoughtDay]` (the
    ///         stamped DAY's word), NOT to any lootbox-index-keyed word. A mid-day `requestLootboxRng` index
    ///         advance fired BETWEEN stamp and open — modelled as the index advance's post-state: increment
    ///         `lootboxRngPacked[0:47]` AND write a DIVERGENT word into the new `lootboxRngWordByIndex[idx]`
    ///         — does NOT re-bind the box: the materialized box is byte-identical to the box opened WITHOUT
    ///         the advance (the box never picks up the later/stale index word — no interleave). Proven via
    ///         the determinism snapshot idiom (open the SAME stamp with vs. without the advance).
    function testIndexBindingMidDayAdvanceDoesNotRebind() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 freeze-determinism harness subscribes an ungrounded sub then drives the STAGE stamp/open; the grounded subscribe stamps at subscribe (the v56 milli-ETH/min-buy unmask, ledger 356-07 D1); re-proven by V56FreezeSolvency (STAMP-not-resolve + two-block determinism, all green)");
        address afk = makeAddr("idxbind_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0x1DB11D); // stamp + land rngWordByDay[stampDay]

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_rngWordByDay(stampDay) != 0, "the stamped day's word landed");

        uint256 snap = vm.snapshot();

        // ---- Open WITHOUT the mid-day index advance (the baseline binding) ----
        Box memory baseline = _openAfkingBoxAt(afk, 7, 9 minutes, 0x0B0B, makeAddr("idx_cb_base"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "baseline open materialized the box");
        assertTrue(baseline.present, "baseline box present (non-vacuous)");

        // ---- Open WITH a mid-day requestLootboxRng index advance between stamp and open ----
        vm.revertTo(snap);
        // Model the advance's post-state: bump the live lootbox index and seed the NEW index slot with a
        // DIVERGENT word (a later/stale index-keyed word the box must NOT pick up).
        uint48 idxBefore = _liveLootboxIndex();
        uint48 idxAfter = idxBefore + 1;
        _advanceLootboxIndex(idxAfter);
        _forceLootboxWord(idxAfter, uint256(keccak256("a-divergent-index-word-the-box-must-ignore")));
        assertEq(_liveLootboxIndex(), idxAfter, "non-vacuity: the lootbox index advanced mid-day");
        Box memory withAdvance = _openAfkingBoxAt(afk, 7, 9 minutes, 0x0B0B, makeAddr("idx_cb_adv"));
        assertEq(_lastOpenedDayOf(afk), stampDay, "advance open materialized the box");
        assertTrue(withAdvance.present, "advanced box present (non-vacuous)");

        // INDEX-BINDING: the box bound to `rngWordByDay[stampDay]` on BOTH opens — the mid-day index advance
        // (and its divergent index word) did NOT re-bind it. Byte-identical => no interleave / no stale
        // -index attach.
        _assertBoxByteIdentical(baseline, withAdvance, "FREEZE-02 index-binding (day-keyed, advance-invariant)");
    }

    /// @notice PRE-RNG / POST-RNG ordering: the box's readiness gate is `lastOpenedDay < lastAutoBoughtDay
    ///         && rngWordByDay[lastAutoBoughtDay] != 0` (GameAfkingModule.sol:918-921). The STAGE stamps the
    ///         sub PRE-RNG (before `rngGate` commits `rngWordByDay[day]`), so the box is NOT openable while
    ///         the stamped day's word is still zero, and becomes openable the moment it lands. Asserted via
    ///         the OBSERVABLE consequence (the private `_afkingBoxReady` is reached through the open leg):
    ///         with the word zeroed, `mintFlip`'s open leg materializes NOTHING (box stays pending); once
    ///         the word lands, the SAME stamp opens. Non-vacuous control: the post-RNG open succeeds.
    function testPreRngStampNotOpenableUntilWordLands() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 freeze-determinism harness subscribes an ungrounded sub then drives the STAGE stamp/open; the grounded subscribe stamps at subscribe (the v56 milli-ETH/min-buy unmask, ledger 356-07 D1); re-proven by V56FreezeSolvency (STAMP-not-resolve + two-block determinism, all green)");
        address afk = makeAddr("prerng_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0x9A9A9A);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending pre-open");

        // ---- PRE-RNG: zero the stamped day's word (model the pre-`rngGate` window) ----
        uint256 savedWord = _rngWordByDay(stampDay);
        assertTrue(savedWord != 0, "control: the word DID land (so zeroing it models the pre-RNG window)");
        _setRngWordByDay(stampDay, 0);
        _settleGame(0xBADBAD); // clean any advance so mintFlip routes to the OPEN leg

        vm.prank(makeAddr("prerng_opener_a"));
        try game.mintFlip() {} catch {}
        // READY is FALSE while the word is zero: the box did NOT materialize (still pending).
        assertTrue(
            _lastOpenedDayOf(afk) < stampDay,
            "PRE-RNG: box NOT openable while rngWordByDay[stampDay] == 0 (_afkingBoxReady false)"
        );

        // ---- POST-RNG: the stamped day's word lands -> the SAME stamp becomes openable ----
        _setRngWordByDay(stampDay, savedWord == 0 ? uint256(keccak256("post-rng-word")) : savedWord);
        _settleGame(0xF1F1F1);
        vm.prank(makeAddr("prerng_opener_b"));
        try game.mintFlip() {} catch {}
        // READY flips true across the word commit: the box materialized (the pre-RNG/post-RNG boundary).
        assertEq(
            _lastOpenedDayOf(afk),
            stampDay,
            "POST-RNG: box opens once rngWordByDay[stampDay] lands (_afkingBoxReady false -> true)"
        );
    }

    /// @notice INDEX-BINDING fuzz (D-351-04): for a RANDOM mid-day index advance (random index delta +
    ///         random divergent index word + random open-block), the box still binds to the stamped day's
    ///         word — byte-identical to the no-advance baseline. The advance timing/magnitude never leaks
    ///         into the afking draw.
    function testFuzzIndexBindingAdvanceInvariant(uint16 idxDelta, uint256 divergentWord, uint64 blk) public {
        vm.skip(true, "357-00b D-12 supersession: the v55 freeze-determinism harness subscribes an ungrounded sub then drives the STAGE stamp/open; the grounded subscribe stamps at subscribe (the v56 milli-ETH/min-buy unmask, ledger 356-07 D1); re-proven by V56FreezeSolvency (STAMP-not-resolve + two-block determinism, all green)");
        address afk = makeAddr("idxbind_fuzz_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        // FIXED STAGE settle word (decoupled from the fuzz): the fuzzed `divergentWord`/`idxDelta`/`blk`
        // exercise the INDEX-binding property, NOT the daily-RNG drain — a fuzzed STAGE settle word can
        // hit a rare fixture VRF-word stall (advanceDue/rngLocked won't drain) that is orthogonal to the
        // property under test (the donor / 351-02/03 idle-fixture day-saturation reality).
        _runStageNewDay(0xACE5EED);

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_rngWordByDay(stampDay) != 0, "stamped-day word landed");

        uint256 snap = vm.snapshot();
        Box memory baseline = _openAfkingBoxAt(afk, blk, 3 minutes, 0xC0DE, makeAddr("idxf_cb_base"));
        assertTrue(baseline.present, "baseline box present");

        vm.revertTo(snap);
        uint48 idxAfter = _liveLootboxIndex() + 1 + uint48(idxDelta);
        _advanceLootboxIndex(idxAfter);
        if (divergentWord == 0) divergentWord = 1;
        _forceLootboxWord(idxAfter, divergentWord);
        Box memory withAdvance = _openAfkingBoxAt(afk, blk, 3 minutes, 0xC0DE, makeAddr("idxf_cb_adv"));
        assertTrue(withAdvance.present, "advanced box present");

        _assertBoxByteIdentical(baseline, withAdvance, "FREEZE-02 index-binding fuzz");
    }

    // =========================================================================
    // Open-driving helpers (the afking open + the differential arms)
    // =========================================================================

    /// @dev Open `afk`'s stamped afking box at a perturbed block context and return the materialized box
    ///      decoded from the `LootBoxOpened` event. Perturbs block number / timestamp (sub-day, level held)
    ///      / prevrandao / coinbase, then settles any in-flight advance so `mintFlip` takes the OPEN leg
    ///      (`!advanceDue`), and fires the afking open via `mintFlip`. The open is recipient-isolated to
    ///      `afk` (the box owner is the event's indexed player).
    function _openAfkingBoxAt(
        address afk,
        uint64 blockBump,
        uint256 warpBump,
        uint256 prevrandao,
        address coinbase
    ) internal returns (Box memory) {
        // Perturb the block context (NONE of these enter the afking seed by design).
        vm.roll(block.number + 1 + uint256(blockBump));
        vm.warp(block.timestamp + warpBump);
        vm.prevrandao(bytes32(prevrandao));
        vm.coinbase(coinbase);
        // Settle any in-flight advance so `mintFlip` routes to the OPEN leg (not the advance leg) and the
        // open is not blocked by `rngLockedFlag` (RD-3). Use a FIXED, reliable drain word (NOT derived from
        // the block perturbation — the perturbation must touch only the block context, never the VRF drain)
        // and DEMAND a clean (`!advanceDue && !rngLocked`) state before opening, so the open is the OPEN leg.
        _settleClean(0xC0FFEE_FACE);

        vm.recordLogs();
        vm.prank(makeAddr("freeze_opener"));
        try game.mintFlip() {} catch {}
        return _decodeLootBoxOpenedFor(afk);
    }

    /// @dev Poke `player`'s in-set Sub stamp to the differential tuple: `amount` (uint24, bytes 8..10),
    ///      `scorePlus1 = score+1` (bytes 6..7), `lastAutoBoughtDay = day` (bytes 11..13), and
    ///      `lastOpenedDay = day-1` (bytes 14..16) so `_afkingBoxReady` sees a PENDING box
    ///      (`lastOpenedDay < lastAutoBoughtDay`). The real `_openAfkingBox` then reads EXACTLY
    ///      `(sub.amount, sub.lastAutoBoughtDay, rngWordByDay[day], sub.scorePlus1-1)` (GameAfkingModule.sol
    ///      :901-907) — so the open's seed preimage is the poked tuple, materialized via the genuine path.
    function _pokeAfkingStamp(address player, uint256 amount, uint32 day, uint16 score) internal {
        bytes32 slot = keccak256(abi.encode(player, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        // Clear + set scorePlus1 (16b @ byte 6), amount (24b @ byte 8), lastAutoBoughtDay (24b @ byte 11),
        // lastOpenedDay (24b @ byte 14).
        packed &= ~(uint256(0xFFFF) << (OFF_SCOREPLUS1 * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_AMOUNT * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_LASTBOUGHT * 8));
        packed &= ~(uint256(0xFFFFFF) << (OFF_LASTOPENED * 8));
        packed |= uint256(uint16(score) + 1) << (OFF_SCOREPLUS1 * 8);
        packed |= (amount & uint256(0xFFFFFF)) << (OFF_AMOUNT * 8);
        packed |= uint256(day) << (OFF_LASTBOUGHT * 8);
        packed |= uint256(day == 0 ? 0 : day - 1) << (OFF_LASTOPENED * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Capture the human arm: buy a real lootbox-mode box at the live level, force its per-index word +
    ///      day + score + adj + amount so the seed preimage `(rngWord, player, day, amount)` and the EV
    ///      inputs MATCH the afking arm exactly, then open it SAME-day with `baseLevelPlus1 == 0` so
    ///      `graceLevel == currentLevel` (baseLevel == currentLevel). Returns the decoded box.
    function _captureHumanOpenLootBox(
        address player,
        uint256 amount,
        uint24 currentLevel,
        uint32 day,
        uint256 rngWord,
        uint16 score
    ) internal returns (Box memory) {
        // Buy a box on the human path at the live level. The buy queues at the live lootbox index.
        uint48 index = _liveLootboxIndex();
        vm.deal(player, amount + 1 ether);
        vm.prank(player);
        game.purchase{value: amount + 0.01 ether}(player, 400, amount, bytes32(0), MintPaymentKind.DirectEth, false);

        // Force the human box's per-index word + per-(index,player) day to MATCH the afking seed preimage
        // (the human seed reads `rngWord = lootboxRngWordByIndex[index]` and `day = lootboxDay[index][player]`,
        // 0 => currentDay; pin both so `(rngWord, player, day, amount)` is byte-identical to the afking arm).
        _forceLootboxWord(index, rngWord);
        _forceLootboxDay(index, player, day);
        // lootboxPurchasePacked: scorePlus1 = score+1 (matches the afking EV input), adj = amount (so the
        // bonus-branch frozen-adj == the afking full-RMW adjustedPortion for amount <= cap), baseLevelPlus1
        // = 0 (=> graceLevel == currentLevel, so the human baseLevel == the afking live currentLevel).
        _forceLootboxPurchasePacked(index, player, score, amount);
        // Pin the box `amount` field (bits[0:232] of lootboxEth) so the seed's `amount` term matches.
        _forceLootboxAmount(index, player, amount, currentLevel);

        assertTrue(_lootboxAmountRaw(index, player) == amount, "human box amount pinned to the tuple");

        vm.recordLogs();
        vm.prank(player);
        game.openBox(player, index);
        Box memory b = _decodeLootBoxOpenedFor(player);
        // Belt-and-braces: the human box opened at the SAME live level (baseLevel == currentLevel), so the
        // differential is a fixed-live-level equivalence (not a level-frozen claim).
        assertEq(uint24(game.level()) + 1, currentLevel, "human open at the same live currentLevel (fixed-level differential)");
        return b;
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

    /// @dev Assert two materialized boxes are byte-identical in every RESOLVED trait field. The event's
    ///      `lootboxIndex` is a storage tag (afking passes 0; the human passes its real index), NOT a
    ///      resolved trait — excluded from the determinism compare (which replays the SAME afking stamp,
    ///      so the index is 0 on both sides anyway, but the differential reuses this helper's trait subset).
    function _assertBoxByteIdentical(Box memory a, Box memory b, string memory tag) internal {
        assertEq(a.amount, b.amount, string(abi.encodePacked(tag, ": amount")));
        assertEq(a.futureLevel, b.futureLevel, string(abi.encodePacked(tag, ": futureLevel")));
        assertEq(a.futureTickets, b.futureTickets, string(abi.encodePacked(tag, ": futureTickets")));
        assertEq(a.flip, b.flip, string(abi.encodePacked(tag, ": flip")));
        assertEq(a.roundedUp, b.roundedUp, string(abi.encodePacked(tag, ": roundedUp")));
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55SetMutationOpenE / KeeperRewardRoutingSameResults)
    // =========================================================================

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev A robust settle that DEMANDS a clean (`!advanceDue && !rngLocked`) state before returning — a
    ///      larger drain budget than `_settleGame` (some perturbed fixture states need >60 advance/fulfill
    ///      cycles to converge). Used before an afking open so `mintFlip` reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
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

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _simDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82_620) / 1 days);
    }

    // ---- Sub field reads (RE-DERIVED slot 66 + verified offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    // ---- DAY-keyed afking word + EV-cap budget reads ----

    function _rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    function _evBenefitUsed(address who, uint24 lvl) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(who, uint256(47))); // lootboxEvBenefitUsedByLevel root = slot 47
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), uint256(inner)))));
    }

    // ---- live lootbox index (slot 38 bits[0:47]) ----

    function _liveLootboxIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))));
    }

    /// @dev Advance the live lootbox RNG index to `newIndex` (lootboxRngPacked bits[0:47]), preserving every
    ///      upper-bit field — the post-state of a mid-day `requestLootboxRng` index advance.
    function _advanceLootboxIndex(uint48 newIndex) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        packed &= ~((uint256(1) << 48) - 1); // clear bits[0:47]
        packed |= uint256(newIndex);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(packed));
    }

    // ---- human box forcing (so its seed preimage matches the afking arm) ----

    function _lootboxLeaf(uint256 rootSlot, uint48 index, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(index), rootSlot));
        return keccak256(abi.encode(who, uint256(inner)));
    }

    /// @dev Set the DAY-keyed afking word `rngWordByDay[day] = word` (the afking open's seed input).
    function _setRngWordByDay(uint32 day, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT))), bytes32(word));
    }

    function _forceLootboxWord(uint48 index, uint256 word) internal {
        bytes32 leaf = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_BY_INDEX_SLOT)));
        vm.store(address(game), leaf, bytes32(word));
    }

    /// @dev Post-repack the open seed carries NO day term (the box binds to the per-index word,
    ///      not a stored day). The former lootboxDay mapping is gone — kept as a no-op so callers
    ///      that pinned a day to match a (now-removed) day preimage term still type-check.
    function _forceLootboxDay(uint48 index, address who, uint32 day) internal {
        index; who; day; // no-op: the resolution no longer reads a per-(index,player) day
    }

    /// @dev The frozen EV inputs (scorePlus1 + adj) now ride in the SINGLE folded lootboxEth word,
    ///      not a separate lootboxPurchasePacked slot. Pin scorePlus1 = score+1 (the EV input) and
    ///      adj = amount (the cap-eligible portion; for amount <= 10 ETH this equals the afking arm's
    ///      adjustedPortion, so the bonus branch is byte-identical). Folded together with the amount
    ///      in _forceLootboxAmount — this writes the score+adj sub-fields, preserving the amount.
    function _forceLootboxPurchasePacked(uint48 index, address who, uint16 score, uint256 amount) internal {
        bytes32 leaf = _lootboxLeaf(LOOTBOX_ETH_SLOT, index, who);
        uint256 word = uint256(vm.load(address(game), leaf));
        // Clear adj[128:192] + scorePlus1[192:208], then set them (amount[0:128] preserved).
        word &= ~(uint256(0xFFFFFFFFFFFFFFFF) << LB_ADJ_SHIFT);
        word &= ~(uint256(0xFFFF) << LB_SCORE_SHIFT);
        word |= (uint256(uint64(amount)) << LB_ADJ_SHIFT);
        word |= (uint256(uint16(score) + 1) << LB_SCORE_SHIFT);
        vm.store(address(game), leaf, bytes32(word));
    }

    /// @dev The single folded lootboxEth word (slot 15): amount[0:128] is the box-owed signal that
    ///      drives the EV roll. purchaseLevel is gone (vestigial — the box rolls from the LIVE level
    ///      at open). Set the amount sub-field; the score/adj sub-fields are written separately by
    ///      _forceLootboxPurchasePacked (the open reads scorePlus1 + adj + amount from this one word).
    function _forceLootboxAmount(uint48 index, address who, uint256 amount, uint24 currentLevel) internal {
        currentLevel; // no longer stored — the box rolls from the live level at open
        bytes32 leaf = _lootboxLeaf(LOOTBOX_ETH_SLOT, index, who);
        uint256 word = uint256(vm.load(address(game), leaf));
        word &= ~LB_AMOUNT_MASK;
        word |= (amount & LB_AMOUNT_MASK);
        vm.store(address(game), leaf, bytes32(word));
    }

    function _lootboxAmountRaw(uint48 index, address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), _lootboxLeaf(LOOTBOX_ETH_SLOT, index, who))) & LB_AMOUNT_MASK;
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
