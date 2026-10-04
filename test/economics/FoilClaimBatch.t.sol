// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Advance the environment without replaying hundreds of unrelated game days.
///      Claims and draws still run through the production facade and modules.
contract FoilMatchTimeSeeder is DegenerusGame {
    function liveWithReusedWords(uint24 newLevel) external returns (uint256) {
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        if (newLevel != 0) level = newLevel;
        _recordDailyRng(dailyIdx - 1, 12345);
        _recordDailyRng(dailyIdx, 67890);
        return dailyIdx;
    }
    function recorded(uint24 day) external view returns (uint256) { return _recordedDailyWord(day); }
    function purchaseAt(uint24 targetLevel) external {
        level = targetLevel - 1;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = false;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        _setRngRequestActive(false);
    }
}

/// @title FoilClaimBatch — behavioural coverage for claimFoilMatchMany
/// @notice The batch claimer is handed out as one shared tuple list that many senders may
///         submit; the first to land settles every tuple. These tests pin the three
///         properties that flow from that: mismatched arrays reject up front, a dead
///         opening tuple reverts the whole call (StaleBatch) so a later sender sees the
///         failure in simulation, and a dead tuple PAST the opener is skipped so one stale
///         entry cannot poison the remaining claims.
/// @dev Claimable tuples are discovered by snapshot-probing the singular entry point, so
///      the tests bind to real wins rather than hard-coded indices.
contract FoilClaimBatch is DeployProtocol {
    uint256 private _lastFulfilledReqId;

    uint256 private constant FOIL_BUYERS = 6;
    uint256 private constant TICKET_BUYERS = 6;

    error LengthMismatch();
    error StaleBatch();

    struct Tuple {
        address player;
        uint24 day;
        uint8 ticketIndex;
    }

    address[FOIL_BUYERS] private _fb;
    uint24 private _buyDay;
    uint24 private _endDay;

    bytes32 private constant FOIL_CLAIMED_SIG =
        keccak256("FoilMatchClaimed(address,uint24,uint256,uint8,uint256)");

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _runScenario();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cycle driving (mirrors FoilPackEV: a NotTimeYet "nothing to do" tick is benign)
    // ──────────────────────────────────────────────────────────────────────

    function _advance() internal {
        try game.mineFlip() {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        if (!game.rngLocked()) _finishReadConsumers();
        _advance();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            try mockVRF.fulfillRandomWords(reqId, vrfWord == 0 ? 1 : vrfWord) {} catch {}
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            _advance();
        }
    }

    /// @dev Domain string and arguments match FoilPackEV exactly: the draws these tests
    ///      need are the ones that scenario is already known to produce.
    function _seed(uint256 a, uint256 b) internal pure returns (uint256 w) {
        w = uint256(keccak256(abi.encode("foilEV", a, b)));
        if (w == 0) w = 1;
    }

    /// @dev Buy and generate real packs. Once a live board seals, plant that board in
    ///      each pack's last line to guarantee batch wins without retaining old claims.
    ///      The cohort tests separately verify generated-line/bucket conservation.
    function _runScenario() internal {
        uint256 nPurchaseDays = 30;
        uint24 lvl = game.level();
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl + 1);
        uint256 foilCost = 10 * priceWei; // FOIL_PACK_TICKETS = 10
        uint256 ticketQty = (foilCost * 4 * 100) / priceWei; // one whole ticket = 4*TICKET_SCALE units

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            _fb[i] = makeAddr(string(abi.encodePacked("foil", vm.toString(i))));
            vm.deal(_fb[i], 1_000 ether);
            vm.prank(_fb[i]);
            try game.purchase{value: foilCost}(_fb[i], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {} catch {}
        }
        for (uint256 i = 0; i < TICKET_BUYERS; i++) {
            address tb = makeAddr(string(abi.encodePacked("tkt", vm.toString(i))));
            vm.deal(tb, 1_000 ether);
            vm.prank(tb);
            try game.purchase{value: foilCost}(tb, ticketQty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }

        _buyDay = game.currentDayView();

        address whale = makeAddr("whale");
        vm.deal(whale, 1_000_000 ether);
        for (uint256 d = 0; d < nPurchaseDays + 50; d++) {
            if (!game.jackpotPhase()) {
                uint256 pw = PriceLookupLib.priceForLevel(game.level() + 1);
                vm.prank(whale);
                try game.purchase{value: 50 * pw}(whale, 50 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
            }
            _completeDay(_seed(nPurchaseDays, d));
            _endDay = game.currentDayView();
            (uint32 board, uint24 drawLevel) = _foilDraw(_endDay);
            bytes32 outer = keccak256(abi.encode(uint256(drawLevel & 3), uint256(58)));
            bytes32 firstSlot = keccak256(abi.encode(_fb[0], outer));
            uint256 first = uint256(vm.load(address(game), firstSlot));
            if (first >> 255 != 0 && uint24(first) <= _endDay && drawLevel != 0) {
                for (uint256 i; i < FOIL_BUYERS; ++i) {
                    bytes32 slot = keccak256(abi.encode(_fb[i], outer));
                    uint256 record = uint256(vm.load(address(game), slot));
                    assertTrue(record >> 255 != 0, "real pack materialized");
                    vm.store(address(game), slot, bytes32((record & ~(uint256(type(uint32).max) << 152)) | (uint256(board) << 152)));
                }
                return;
            }
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        revert("batch fixture did not generate a live foil board");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Discovery: find tuples that genuinely settle, without consuming them
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Probe the singular entry point under a snapshot so the marker set by a
    ///      successful claim is rolled back; the returned tuples are still claimable.
    function _findClaimable(uint256 want) internal returns (Tuple[] memory found) {
        Tuple[] memory buf = new Tuple[](want);
        uint256 n;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < FOIL_BUYERS && n < want; i++) {
            for (uint24 day = _buyDay; day <= _endDay && n < want; day++) {
                if (game.rngWordForDay(day) == 0) continue;
                for (uint8 ti = 0; ti < 4 && n < want; ti++) {
                    try game.claimFoilMatch(_fb[i], day, ti) {
                        buf[n++] = Tuple(_fb[i], day, ti);
                    } catch {}
                }
            }
        }
        vm.revertToState(snap);

        found = new Tuple[](n);
        for (uint256 i = 0; i < n; i++) found[i] = buf[i];
    }

    function _explode(Tuple[] memory t)
        internal
        pure
        returns (address[] memory p, uint24[] memory d, uint8[] memory ti)
    {
        p = new address[](t.length);
        d = new uint24[](t.length);
        ti = new uint8[](t.length);
        for (uint256 i = 0; i < t.length; i++) {
            p[i] = t[i].player;
            d[i] = t[i].day;
            ti[i] = t[i].ticketIndex;
        }
    }

    /// @dev A tuple that can never settle: ticketIndex is out of the 0-3 domain.
    function _deadTuple(address player) internal pure returns (Tuple memory) {
        return Tuple(player, 1, 9);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Tests
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Array-length disagreement rejects before any claim is attempted.
    function test_lengthMismatch_reverts() public {
        address[] memory p = new address[](2);
        uint24[] memory d = new uint24[](1);
        uint8[] memory ti = new uint8[](2);
        vm.expectRevert(LengthMismatch.selector);
        game.claimFoilMatchMany(p, d, ti);
    }

    /// @notice A non-claimable opening tuple reverts the whole call, so a sender handed an
    ///         already-swept list sees the failure in simulation instead of paying to walk it.
    function test_deadOpener_revertsStaleBatch() public {
        Tuple[] memory good = _findClaimable(2);
        require(good.length == 2, "scenario produced no claimable tuples");

        Tuple[] memory batch = new Tuple[](3);
        batch[0] = _deadTuple(_fb[0]); // dead opener
        batch[1] = good[0];
        batch[2] = good[1];

        (address[] memory p, uint24[] memory d, uint8[] memory ti) = _explode(batch);
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(p, d, ti);
    }

    /// @notice Re-submitting an already-swept list reverts: the opener's marker is set, so
    ///         the second sender aborts at one tuple instead of walking the whole list.
    function test_resubmitSweptList_revertsStaleBatch() public {
        Tuple[] memory good = _findClaimable(3);
        require(good.length >= 2, "scenario produced too few claimable tuples");

        (address[] memory p, uint24[] memory d, uint8[] memory ti) = _explode(good);

        // First sender settles the list.
        game.claimFoilMatchMany(p, d, ti);

        // Second sender, same calldata: opener is spent.
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(p, d, ti);
    }

    /// @notice A dead tuple PAST the opener is skipped, not fatal: the tuples after it
    ///         still settle, which is the property that lets one list cover many claims.
    function test_deadTuplePastOpener_isSkipped() public {
        Tuple[] memory good = _findClaimable(2);
        require(good.length == 2, "scenario produced too few claimable tuples");

        Tuple[] memory batch = new Tuple[](3);
        batch[0] = good[0];
        batch[1] = _deadTuple(_fb[0]); // dead in the middle
        batch[2] = good[1];

        (address[] memory p, uint24[] memory d, uint8[] memory ti) = _explode(batch);
        game.claimFoilMatchMany(p, d, ti); // must not revert

        // Both good tuples are consumed: re-claiming either now fails.
        vm.expectRevert();
        game.claimFoilMatch(good[0].player, good[0].day, good[0].ticketIndex);
        vm.expectRevert();
        game.claimFoilMatch(good[1].player, good[1].day, good[1].ticketIndex);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Day-shape storage probes and the face table
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Storage slots (scripts/layout/golden/DegenerusGame.json): `dailyFoilDraw` packs a
    ///      day's main set [0..31] and level [64..] (bits [32..63] reserved, always zero);
    ///      `foilRecord[L & 3][player]` stores the exact level at [208..231] and
    ///      `dailyFoilDraw[day & 1]` stores its exact draw day at [217..240].
    uint256 private constant FOIL_DRAW_SLOT = 60;
    uint256 private constant FOIL_RECORD_SLOT = 58;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant PRIZE_POOLS_SLOT = 2;

    bytes32 private constant FOIL_SEED_TAG = keccak256("foil-seed");
    uint256 private constant FOIL_FACES_T8 = 80_000;

    /// @dev Authenticate the exact day in dailyFoilDraw[day & 1]. Bits [32..63] are reserved
    ///      and always read zero.
    function _foilDraw(uint24 day) internal view returns (uint32 mainSet, uint24 lvl) {
        uint256 draw = uint256(vm.load(address(game), keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT))));
        if (uint24(draw >> 217) != day) return (0, 0);
        mainSet = uint32(draw);
        lvl = uint24(draw >> 64);
    }

    /// @dev Every real win pays the table's faces for its score: 16 / 48 / 280 / 3,200 / 80,000.
    function test_winsPayTheFaceTable() public {
        Tuple[] memory t = _findClaimable(12);
        assertGt(t.length, 0, "the scenario produced no claimable win");
        uint256[9] memory faces;
        faces[4] = 16;
        faces[5] = 48;
        faces[6] = 280;
        faces[7] = 3_200;
        faces[8] = 80_000;
        for (uint256 i; i < t.length; ++i) {
            vm.recordLogs();
            game.claimFoilMatch(t[i].player, t[i].day, t[i].ticketIndex);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool seen;
            for (uint256 k; k < logs.length; ++k) {
                if (logs[k].topics.length == 0 || logs[k].topics[0] != FOIL_CLAIMED_SIG) continue;
                (, uint8 tier, uint256 paid) = abi.decode(logs[k].data, (uint256, uint8, uint256));
                assertEq(paid, faces[tier], "a win paid off the face table");
                seen = true;
            }
            assertTrue(seen, "a settled claim logged no FoilMatchClaimed");
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Every day shape pays the flat face table (and a T=8 whale-pass credit)
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The SAME derivation `_deriveFoilLines` performs for one ticket index: four
    ///      boosted [QQ][CCC][SSS] quadrant bytes off (entropy, buyer, level,
    ///      FOIL_SEED_TAG, ticketIndex).
    function _deriveFoilLine(
        address buyer,
        uint24 lvl,
        uint256 entropy,
        uint16 multBps,
        uint256 ticketIndex
    ) internal pure returns (uint32) {
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(multBps);
        uint256 seed = uint256(keccak256(abi.encode(entropy, buyer, lvl, FOIL_SEED_TAG, ticketIndex)));
        uint8 tA = DegenerusTraitUtils.foilTrait(uint64(seed), cut);
        uint8 tB = DegenerusTraitUtils.foilTrait(uint64(seed >> 64), cut) | 64;
        uint8 tC = DegenerusTraitUtils.foilTrait(uint64(seed >> 128), cut) | 128;
        uint8 tD = DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) | 192;
        return uint32(tA) | (uint32(tB) << 8) | (uint32(tC) << 16) | (uint32(tD) << 24);
    }

    /// @dev Force dailyFoilDraw[day]'s main set to `sel`, preserving the level bits the REAL
    ///      writer (emitDailyWinningTraits / the daily jackpot stage) set. Every quadrant byte then
    ///      equals the claimant's own line byte-for-byte, so the match scores a guaranteed
    ///      tier 8 (symbol AND color both match every quadrant) regardless of what the day's
    ///      real board actually rolled — only the win set is forced, never the level.
    function _forceWinSetToLine(uint24 day, uint32 sel) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT));
        uint256 draw = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((draw & ~uint256(type(uint32).max)) | uint256(sel)));
    }

    /// @dev Buy one foil pack for `p` at whichever level is active right now (mirrors
    ///      `_activeTicketLevel()`'s purchase-phase / jackpot-phase split), and read back
    ///      the record the buy froze.
    function _buyFoilPackNow(address p) internal returns (uint24 lvl, uint24 resolveDay, uint16 multBps) {
        vm.deal(p, 1_000 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        lvl = game.jackpotPhase() ? game.level() : game.level() + 1;
        vm.prank(p);
        game.purchase{value: 10 * priceWei}(p, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        bytes32 inner = keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT));
        uint256 rec = uint256(vm.load(address(game), keccak256(abi.encode(p, inner))));
        multBps = uint16(rec >> 24);
        for (uint256 i; i < 50 && rec >> 255 == 0; ++i) {
            _tick();
            rec = uint256(vm.load(address(game), keccak256(abi.encode(p, inner))));
        }
        assertTrue(rec >> 255 != 0, "new foil cohort generated");
        resolveDay = uint24(rec);
    }

    /// @dev Seed the live next-pool half (slot 2, low 128 bits) up to targetNext, mirroring
    ///      DailyRngStallRecovery's harness shortcut for crossing a level's pool target
    ///      without a slow organic purchase ramp.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_SLOT),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }

    function _fulfillPendingVrf() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0 || reqId == _lastFulfilledReqId) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("flat-face", reqId)))) {
            _lastFulfilledReqId = reqId;
        } catch {}
    }

    /// @dev One advance tick: fulfill whatever VRF request is pending, then call
    ///      mineFlip(). A failing call (nothing due yet) warps a day so the next tick
    ///      has something to do. Single-step (unlike `_completeDay`'s bounded drain loop)
    ///      so a caller can observe a one-tick state flip — e.g. `jackpotPhase()` going
    ///      true the instant the level-1 -> level-1's-own-jackpot-phase transition lands —
    ///      instead of the drain loop running straight through it.
    function _tick() internal {
        _fulfillPendingVrf();
        uint256 requestBefore = mockVRF.lastRequestId();
        (bool ok, ) = address(game).call{gas: 12_000_000}(abi.encodeWithSignature("mineFlip()"));
        // A refused optional midday request may now return a successful no-op.
        // Move to the next daily boundary instead of replaying that same refusal.
        bool waitingForDaily = mockVRF.lastRequestId() == requestBefore
            && game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.RequestMidday);
        if (!ok || waitingForDaily) vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev Gates on dailyFoilDraw itself, not rngWordForDay: inside the jackpot phase the
    ///      day's RNG word can seal (and even unlock the NEXT day's request) across several
    ///      single-step ticks before the jackpot-daily stage that actually writes
    ///      dailyFoilDraw[day] runs — gating on the word alone would force-write a win set
    ///      onto a still-empty record (level 0: the zero value, not a real day shape).
    function _tickUntilSealed(uint24 day, uint256 maxTicks) internal {
        for (uint256 i; i < maxTicks; ++i) {
            if (uint24(uint256(vm.load(address(game), keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT)))) >> 217) == day) return;
            _tick();
        }
        revert("harness: day never sealed within the bound");
    }

    function _tickUntilJackpotPhase(uint256 maxTicks) internal {
        for (uint256 i; i < maxTicks; ++i) {
            if (game.jackpotPhase()) return;
            _tick();
        }
        revert("harness: level 1 never entered its own jackpot phase");
    }

    function _tickUntilPurchasePhase(uint256 maxTicks) internal {
        for (uint256 i; i < maxTicks; ++i) {
            if (!game.jackpotPhase()) return;
            _tick();
        }
        revert("harness: level 1's jackpot phase never ended");
    }

    /// @dev Force the day's win set to `player`'s own ticket-0 line (a guaranteed tier 8),
    ///      claim it, and assert the flat rule: the event's `faces` (which is also the
    ///      magnitude staked into the spin — see `_payFoilTier`) equals the plain T=8 face
    ///      table entry, the whale-pass credit is exactly one, and dailyFoilDraw's reserved
    ///      bits [32..63] read zero.
    function _assertFlatFaceTable(
        address player,
        uint24 day,
        uint24 lvl,
        uint16 multBps,
        string memory tag
    ) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT));
        (, uint24 recordedLvl) = _foilDraw(day);
        assertEq(uint256(recordedLvl), uint256(lvl), string.concat(tag, ": dailyFoilDraw level mismatch"));
        uint256 reserved = (uint256(vm.load(address(game), slot)) >> 32) & type(uint32).max;
        assertEq(reserved, 0, string.concat(tag, ": dailyFoilDraw bits 32..63 must read zero"));

        uint256 record = uint256(vm.load(address(game), keccak256(abi.encode(player, keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT))))));
        uint32 sel = uint32(record >> 56);
        multBps;
        _forceWinSetToLine(day, sel);

        // Allow the daily draw to release its frozen pool before a forced ETH payout.
        for (uint256 i; i < 100 && game.rngLocked(); ++i) _tick();
        assertFalse(game.rngLocked(), "daily lock released before the face-table claim");
        uint256 passesBefore = game.whalePassClaimAmount(player);
        vm.recordLogs();
        game.claimFoilMatch(player, day, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool seen;
        for (uint256 k; k < logs.length; ++k) {
            if (logs[k].topics.length == 0 || logs[k].topics[0] != FOIL_CLAIMED_SIG) continue;
            (, uint8 tier, uint256 paid) = abi.decode(logs[k].data, (uint256, uint8, uint256));
            assertEq(uint256(tier), 8, string.concat(tag, ": forced line did not score tier 8"));
            assertEq(paid, FOIL_FACES_T8, string.concat(tag, ": faces did not match the face table"));
            seen = true;
        }
        assertTrue(seen, string.concat(tag, ": forced claim logged no FoilMatchClaimed"));

        uint256 gained = game.whalePassClaimAmount(player) - passesBefore;
        assertEq(gained, 1, string.concat(tag, ": T=8 whale-pass credit must be exactly one"));
    }

    /// @notice Every day shape — level 1's purchase day, level 1's own jackpot day, and a
    ///         level >= 2 purchase day — pays a foil match at exactly the face table and
    ///         grants exactly one whale-pass credit on a T=8. All three dailyFoilDraw records
    ///         below are written by the real advance chain — emitDailyWinningTraits (level 1)
    ///         and the daily jackpot stage (the jackpot day and level 2) — never by the harness; only
    ///         the WIN SET is forced, to a guaranteed tier-8 line, so RNG luck cannot leave any
    ///         of the three shapes untested.
    function test_faceTablePaysFlatAcrossDayShapes() public {
        // ---- Level-1 purchase day.
        address p1 = makeAddr("flat-lvl1");
        (uint24 lvl1, uint24 resolve1, uint16 mult1) = _buyFoilPackNow(p1);
        assertEq(uint256(lvl1), 1, "harness: must buy during level 1's purchase phase");
        _driveUntilSealedByWarp(resolve1, 10);
        _assertFlatFaceTable(p1, resolve1, lvl1, mult1, "level-1 purchase day");

        // ---- Trip level 1's own pool target (BOOTSTRAP_PRIZE_POOL = 50 ether) and step,
        // one advance at a time, to the exact tick the transition lands — so a foil pack
        // bought right after is bought BEFORE that jackpot cycle's own daily jackpot call,
        // landing its resolveDay squarely inside the still-open jackpot phase.
        _seedNextPrizePool(60 ether);
        _tickUntilJackpotPhase(20);
        assertTrue(game.jackpotPhase(), "harness: must have entered level 1's own jackpot phase");

        // ---- Jackpot day. `level` is bumped at the transition's own RNG request (ahead of
        // `_endPhase`), so jackpot-phase foil buys already route to the post-increment level —
        // the same L a level-1 purchase day recorded.
        address p2 = makeAddr("flat-jkpt");
        (uint24 lvl2, uint24 resolve2, uint16 mult2) = _buyFoilPackNow(p2);
        assertEq(uint256(lvl2), 1, "harness: jackpot-phase foil buys route to the current level");
        _tickUntilSealed(resolve2, 30);
        _assertFlatFaceTable(p2, resolve2, lvl2, mult2, "jackpot day");

        // ---- Ride out the rest of level 1's jackpot phase into level 2's purchase phase.
        _tickUntilPurchasePhase(30);
        assertFalse(game.jackpotPhase(), "harness: level 1's jackpot phase must have ended");

        // ---- Level >= 2 purchase day.
        address p3 = makeAddr("flat-lvl2");
        (uint24 lvl3, uint24 resolve3, uint16 mult3) = _buyFoilPackNow(p3);
        assertGe(uint256(lvl3), 2, "harness: must buy during a level >= 2 purchase phase");
        _driveUntilSealedByWarp(resolve3, 10);
        _assertFlatFaceTable(p3, resolve3, lvl3, mult3, "level >= 2 purchase day");
    }

    /// @dev Ordinary-purchase-phase day driver (no phase-transition risk): warp a day, run
    ///      `_completeDay`'s bounded drain, repeat until `day` seals. Distinct from `_tick`
    ///      because here overshoot cannot skip a shape we care about.
    function _driveUntilSealedByWarp(uint24 day, uint256 maxDays) internal {
        for (uint256 i; i < maxDays; ++i) {
            if (uint24(uint256(vm.load(address(game), keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT)))) >> 217) == day) return;
            _completeDay(uint256(keccak256(abi.encode("flat-face-day", day, i))));
            if (uint24(uint256(vm.load(address(game), keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT)))) >> 217) == day) return;
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        revert("harness: day never sealed within the bound");
    }

    bytes32 private constant BOX_SPIN_SIG = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");
    bytes32 private constant NO_MATCH = keccak256("NoClaimableMatch()");
    uint256 private constant SEEDED = uint256(1) << 216;

    function _drawWord() private view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(_endDay & 1), FOIL_DRAW_SLOT))));
    }

    function _setDrawWord(uint256 w) private {
        vm.store(address(game), keccak256(abi.encode(uint256(_endDay & 1), FOIL_DRAW_SLOT)), bytes32(w));
    }

    function _deferMatch(uint256 daysLater, uint24 newLevel) private {
        vm.warp(vm.getBlockTimestamp() + daysLater * 1 days);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(FoilMatchTimeSeeder).runtimeCode);
        FoilMatchTimeSeeder(payable(address(game))).liveWithReusedWords(newLevel);
        if (daysLater >= 2) {
            assertEq(FoilMatchTimeSeeder(payable(address(game))).recorded(_endDay), 0, "original word overwritten");
        }
        vm.etch(address(game), runtime);
        assertFalse(game.livenessTriggered(), "fixture remains live");
    }

    function _forcePayoutSeed(uint128 seed) private {
        _setDrawWord((_drawWord() & ~(uint256(type(uint128).max) << 88)) | (uint256(seed) << 88));
    }

    function _forceTier(uint8 tier) private {
        uint32 board = uint32(_drawWord());
        uint32 line;
        for (uint256 q; q < 4; ++q) {
            // Every symbol hits (+1); the first tier-4 colors also hit (+1).
            uint8 part = uint8(board >> (8 * q));
            if (q >= tier - 4) part ^= 8;
            line |= uint32(part) << (8 * q);
        }
        uint24 lvl = uint24(_drawWord() >> 64);
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT))));
        uint256 record = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((record & ~(uint256(type(uint32).max) << 152)) | (uint256(line) << 152)));
    }

    function _claimPrimarySpin(uint8 expectedTier) private returns (bytes32 digest, uint256 gross, uint256 ethPaid) {
        uint256 beforePasses = game.whalePassClaimAmount(_fb[0]);
        vm.recordLogs();
        game.claimFoilMatch(_fb[0], _endDay, 3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool matchSeen;
        bool spinSeen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == FOIL_CLAIMED_SIG) {
                (, uint8 tier,) = abi.decode(logs[i].data, (uint256, uint8, uint256));
                assertEq(tier, expectedTier);
                matchSeen = true;
            }
            if (!spinSeen && logs[i].topics[0] == BOX_SPIN_SIG) {
                digest = keccak256(logs[i].data);
                (,, gross, ethPaid) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                spinSeen = true;
            }
        }
        assertTrue(matchSeen && spinSeen, "real match and primary payout executed");
        assertEq(game.whalePassClaimAmount(_fb[0]) - beforePasses, expectedTier == 8 ? 1 : 0);
    }

    function test_persistentSeed_realDrawRecordsCommittedWord() public view {
        uint256 draw = _drawWord();
        uint256 word = game.rngWordForDay(_endDay);
        assertGt(word, 1, "real daily word");
        assertTrue(draw & SEEDED != 0);
        uint128 expected = uint128(uint256(keccak256(abi.encode(word, _endDay, keccak256("foil-payout-seed")))));
        assertEq(uint128(draw >> 88), expected);
        assertEq(uint32(draw >> 32), 0, "reserved board gap");
        assertEq(uint24(draw >> 217), _endDay, "exact retained draw day");
    }

    function test_expiry_allTiersCurrenciesSameOnFollowingDay() public {
        for (uint8 tier = 4; tier <= 8; ++tier) {
            for (uint256 currency; currency < 3; ++currency) {
                uint256 snapshot = vm.snapshotState();
                uint128 seed;
                for (;; ++seed) {
                    uint256 c = uint256(keccak256(abi.encode(uint256(seed), uint256(_endDay), uint256(3), keccak256("foil-currency")))) % 100;
                    if ((c < 40 ? 0 : c < 80 ? 1 : 2) == currency) break;
                }
                _forcePayoutSeed(seed);
                _forceTier(tier);
                uint256 ready = vm.snapshotState();
                (bytes32 prompt,,) = _claimPrimarySpin(tier);
                vm.revertToState(ready);
                _deferMatch(1, 0);
                (bytes32 delayed,,) = _claimPrimarySpin(tier);
                assertEq(delayed, prompt, "currency/spin/gross/ETH unchanged with identical pools");
                vm.expectRevert(bytes4(NO_MATCH));
                game.claimFoilMatch(_fb[0], _endDay, 3);
                vm.revertToState(snapshot);
            }
        }
    }

    function _setFuturePool(uint128 amount) private {
        uint256 pools = uint256(vm.load(address(game), bytes32(uint256(2))));
        vm.store(address(game), bytes32(uint256(2)), bytes32(uint256(uint128(pools)) | (uint256(amount) << 128)));
    }

    function test_persistentSeed_livePoolChangesEthShareButNotSpin() public {
        _forceTier(4);
        // Find a winning ETH payout using the real resolver, not a mirrored payout formula.
        bool found;
        for (uint128 seed; seed < 100; ++seed) {
            uint256 c = uint256(keccak256(abi.encode(uint256(seed), uint256(_endDay), uint256(3), keccak256("foil-currency")))) % 100;
            if (c >= 40) continue;
            _forcePayoutSeed(seed);
            uint256 ready = vm.snapshotState();
            _setFuturePool(1_000_000 ether);
            (, uint256 promptGross, uint256 promptEth) = _claimPrimarySpin(4);
            vm.revertToState(ready);
            if (promptEth == 0) continue;
            // Change live pricing without skipping a century queue-recycling boundary.
            _deferMatch(1, 21);
            _setFuturePool(0);
            (, uint256 delayedGross, uint256 delayedEth) = _claimPrimarySpin(4);
            assertEq(delayedGross, promptGross, "fixed spin, saved activity, historical level price");
            assertEq(delayedEth, 0, "empty live pool converts ETH share to recirculation");
            assertGt(promptEth, delayedEth, "waiting can change realized ETH despite fixed entropy");
            found = true;
            break;
        }
        assertTrue(found, "winning ETH vector exercised");
    }

    function test_persistentSeed_zeroSeedIsValidButUnseededRecordIsNot() public {
        _forcePayoutSeed(0);
        uint256 seeded = _drawWord();
        _setDrawWord(seeded & ~SEEDED);
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay, 3);
        _setDrawWord(seeded);
        _deferMatch(1, 0);
        _claimPrimarySpin(8);
    }

    function test_expiry_batchClaimsOnFollowingDayAndReplay() public {
        _deferMatch(1, 0);
        address[] memory players = new address[](2);
        uint24[] memory days_ = new uint24[](2);
        uint8[] memory tickets = new uint8[](2);
        for (uint256 i; i < 2; ++i) { players[i] = _fb[i]; days_[i] = _endDay; tickets[i] = 3; }
        game.claimFoilMatchMany(players, days_, tickets);
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(bytes4(NO_MATCH));
            game.claimFoilMatch(players[i], _endDay, 3);
        }
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(players, days_, tickets);
    }

    function test_expiry_rejectsSecondFollowingDayEvenWithRetainedRecords() public {
        uint256 draw = _drawWord();
        _deferMatch(2, 0);
        assertEq(_drawWord(), draw, "expiry does not depend on slot replacement");
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay, 3);

        address[] memory players = new address[](1);
        uint24[] memory days_ = new uint24[](1);
        uint8[] memory tickets = new uint8[](1);
        players[0] = _fb[0]; days_[0] = _endDay; tickets[0] = 3;
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(players, days_, tickets);
    }

    function test_reuse_drawAndClaimBanksRollOverWithoutReplayingPriorWins() public {
        uint256 draw = _drawWord();
        game.claimFoilMatch(_fb[0], _endDay, 3);
        for (uint24 delta = 1; delta <= 2; ++delta) {
            _deferMatch(1, 0);
            uint24 day = _endDay + delta;
            uint256 current = (draw & ~(uint256(type(uint24).max) << 217)) | (uint256(day) << 217);
            vm.store(address(game), keccak256(abi.encode(uint256(day & 1), FOIL_DRAW_SLOT)), bytes32(current));
            game.claimFoilMatch(_fb[0], day, 3);
            vm.expectRevert(bytes4(NO_MATCH));
            game.claimFoilMatch(_fb[0], day, 3);
        }
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay, 3);
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay + 1, 3);
        uint256 markers = uint256(vm.load(address(game), keccak256(abi.encode(_fb[0], uint256(59)))));
        assertEq(uint24(markers >> (uint256((_endDay + 2) & 1) * 32)), _endDay + 2);
        assertEq(uint24(markers >> (uint256((_endDay + 1) & 1) * 32)), _endDay + 1);
    }

    function test_reuse_fourTicketsHaveIndependentClaimBits() public {
        uint256 draw = _drawWord();
        uint24 lvl = uint24(draw >> 64);
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT))));
        uint256 pack = uint256(vm.load(address(game), slot));
        uint256 lines;
        for (uint256 i; i < 4; ++i) lines |= uint256(uint32(draw)) << (56 + i * 32);
        pack = (pack & ~(uint256(type(uint128).max) << 56)) | lines;
        vm.store(address(game), slot, bytes32(pack));
        for (uint256 i; i < 4; ++i) game.claimFoilMatch(_fb[0], _endDay, i);
        for (uint256 i; i < 4; ++i) {
            vm.expectRevert(bytes4(NO_MATCH));
            game.claimFoilMatch(_fb[0], _endDay, i);
        }
    }

    function test_reuse_rejectsMismatchedDrawAndPackTags() public {
        uint256 draw = _drawWord();
        _setDrawWord((draw & ~(uint256(type(uint24).max) << 217)) | (uint256(_endDay + 2) << 217));
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay, 3);
        _setDrawWord(draw);

        uint24 lvl = uint24(draw >> 64);
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT))));
        uint256 pack = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((pack & ~(uint256(type(uint24).max) << 208)) | (uint256(lvl + 4) << 208)));
        vm.expectRevert(bytes4(NO_MATCH));
        game.claimFoilMatch(_fb[0], _endDay, 3);
        vm.store(address(game), slot, bytes32(pack));
        _claimPrimarySpin(8);
    }

    function test_reuse_realPurchaseProtectsLivePackThenOverwritesExpiredSlot() public {
        uint24 oldLevel = uint24(_drawWord() >> 64);
        uint24 nextLevel = oldLevel + 4;
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(oldLevel & 3), FOIL_RECORD_SLOT))));
        uint256 oldRecord = uint256(vm.load(address(game), slot));
        // A previously settled gold award must not mark the replacement pack as paid.
        oldRecord |= uint256(1) << 232;
        vm.store(address(game), slot, bytes32(oldRecord));
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(FoilMatchTimeSeeder).runtimeCode);
        FoilMatchTimeSeeder(payable(address(game))).purchaseAt(nextLevel);
        vm.etch(address(game), runtime);

        uint256 cost = 10 * PriceLookupLib.priceForLevel(nextLevel);
        for (uint256 delta; delta < 2; ++delta) {
            uint256 beforeBalance = _fb[0].balance;
            uint256 beforeGameBalance = address(game).balance;
            vm.expectRevert(bytes4(keccak256("FoilRecordBusy()")));
            vm.prank(_fb[0]);
            game.purchase{value: cost}(_fb[0], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
            assertEq(_fb[0].balance, beforeBalance, "rejected buy keeps buyer funds");
            assertEq(address(game).balance, beforeGameBalance, "rejected buy keeps game funds");
            assertEq(uint256(vm.load(address(game), slot)), oldRecord, "live pack metadata and all lines survive");
            _deferMatch(1, 0);
        }

        vm.prank(_fb[0]);
        game.purchase{value: cost}(_fb[0], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        uint256 replacement = uint256(vm.load(address(game), slot));
        assertEq(uint24(replacement >> 208), nextLevel, "same physical slot carries new exact level");
        assertEq(uint128(replacement >> 56), 0, "old four lines cleared");
        assertEq(uint24(replacement), 0, "new pack waits for a fresh eligible draw");
        assertEq(uint24(replacement >> 184), 0, "old generation day cleared");
        assertEq(replacement & ((uint256(1) << 232) | (uint256(1) << 255)), 0, "gold paid and ready flags cleared");
        assertGt(uint16(replacement >> 24), 0, "new purchase freezes its own boost");
        DegenerusGameLens lens = new DegenerusGameLens();
        assertFalse(lens.foilRecordOf(address(game), oldLevel, _fb[0]).present, "old logical record disappears");
        assertTrue(lens.foilRecordOf(address(game), nextLevel, _fb[0]).present, "new logical record remains");
        vm.expectRevert(bytes4(keccak256("FoilAlreadyBought()")));
        vm.prank(_fb[0]);
        game.purchase{value: cost}(_fb[0], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
    }

    function test_reuse_realPurchaseCannotReplaceUndrainedPack() public {
        uint24 oldLevel = uint24(_drawWord() >> 64);
        uint24 nextLevel = oldLevel + 4;
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(oldLevel & 3), FOIL_RECORD_SLOT))));
        uint256 pending = uint256(vm.load(address(game), slot)) & ~(uint256(1) << 255);
        vm.store(address(game), slot, bytes32(pending));
        _deferMatch(4, 0);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(FoilMatchTimeSeeder).runtimeCode);
        FoilMatchTimeSeeder(payable(address(game))).purchaseAt(nextLevel);
        vm.etch(address(game), runtime);
        uint256 beforeBalance = _fb[0].balance;
        uint256 beforeGameBalance = address(game).balance;
        uint256 cost = 10 * PriceLookupLib.priceForLevel(nextLevel);
        vm.expectRevert(bytes4(keccak256("FoilRecordBusy()")));
        vm.prank(_fb[0]);
        game.purchase{value: cost}(_fb[0], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        assertEq(_fb[0].balance, beforeBalance);
        assertEq(address(game).balance, beforeGameBalance);
        assertEq(uint256(vm.load(address(game), slot)), pending, "paid undrained pack survives");
    }

    function test_persistentSeed_domainEligibilityAndTerminalGuards() public {
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], 0, 3);
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], uint256(_endDay) + (1 << 24), 3);
        uint256 futureDay = game.currentDayView() + 1;
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], futureDay, 3);
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], _endDay, 4);
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(makeAddr("no-pack"), _endDay, 3);
        uint256 draw = _drawWord();
        _setDrawWord(0);
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], _endDay, 3);
        _setDrawWord(draw);
        uint24 lvl = uint24(draw >> 64);
        bytes32 slot = keccak256(abi.encode(_fb[0], keccak256(abi.encode(uint256(lvl & 3), FOIL_RECORD_SLOT))));
        uint256 pack = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(pack & ~(uint256(1) << 255)));
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], _endDay, 3);
        vm.store(address(game), slot, bytes32((pack & ~uint256(type(uint24).max)) | uint256(_endDay + 1)));
        vm.expectRevert(bytes4(NO_MATCH)); game.claimFoilMatch(_fb[0], _endDay, 3);
        vm.store(address(game), slot, bytes32(pack));
        vm.warp(vm.getBlockTimestamp() + 40 days);
        assertTrue(game.livenessTriggered());
        vm.expectRevert(bytes4(keccak256("GameOver()")));
        game.claimFoilMatch(_fb[0], _endDay, 3);
    }
}
