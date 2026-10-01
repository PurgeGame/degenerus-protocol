// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Vm} from "forge-std/Vm.sol";

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
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _runScenario();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cycle driving (mirrors FoilPackEV: a NotTimeYet "nothing to do" tick is benign)
    // ──────────────────────────────────────────────────────────────────────

    function _advance() internal {
        try game.advanceGame() {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
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

    /// @dev Replays FoilPackEV's N=30 scenario move for move — same cohorts in the same
    ///      order, same whale cadence, same seeds — because RNG here is a function of the
    ///      whole purchase history. Dropping the ticket cohort or changing the seed domain
    ///      shifts every draw and the graded matches stop landing (P(score >= 4) ~ 0.0035
    ///      per comparison, so wins only accumulate across the full sweep).
    ///      Day advance goes through vm.getBlockTimestamp(): this whole scenario runs in
    ///      one setUp frame, where via-IR CSEs a chained `block.timestamp + 1 days` into a
    ///      single value and the clock never moves.
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
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        _endDay = game.currentDayView();
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
            for (uint24 day = _buyDay + 1; day <= _endDay && n < want; day++) {
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
    ///      `foilRecord[L][player]` holds the pack's resolveDay in its low 24 bits and multBps
    ///      at [24..39]; `rngWordByDay` is what the pack's four lines derive from.
    uint256 private constant FOIL_DRAW_SLOT = 60;
    uint256 private constant FOIL_RECORD_SLOT = 58;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant PRIZE_POOLS_SLOT = 2;

    bytes32 private constant FOIL_SEED_TAG = keccak256("foil-seed");
    uint256 private constant FOIL_FACES_T8 = 80_000;

    /// @dev dailyFoilDraw[day]: main set [0..31], level [64..87]. Bits [32..63] are reserved
    ///      and always read zero.
    function _foilDraw(uint24 day) internal view returns (uint32 mainSet, uint24 lvl) {
        uint256 draw = uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT))));
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
    ///      writer (emitDailyWinningTraits / payDailyJackpot) set. Every quadrant byte then
    ///      equals the claimant's own line byte-for-byte, so the match scores a guaranteed
    ///      tier 8 (symbol AND color both match every quadrant) regardless of what the day's
    ///      real board actually rolled — only the win set is forced, never the level.
    function _forceWinSetToLine(uint24 day, uint32 sel) internal {
        (, uint24 lvl) = _foilDraw(day);
        vm.store(
            address(game),
            keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT)),
            bytes32(uint256(sel) | (uint256(lvl) << 64))
        );
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
        bytes32 inner = keccak256(abi.encode(uint256(lvl), FOIL_RECORD_SLOT));
        uint256 rec = uint256(vm.load(address(game), keccak256(abi.encode(p, inner))));
        resolveDay = uint24(rec);
        multBps = uint16(rec >> 24);
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
    ///      advanceGame(). A failing call (nothing due yet) warps a day so the next tick
    ///      has something to do. Single-step (unlike `_completeDay`'s bounded drain loop)
    ///      so a caller can observe a one-tick state flip — e.g. `jackpotPhase()` going
    ///      true the instant the level-1 -> level-1's-own-jackpot-phase transition lands —
    ///      instead of the drain loop running straight through it.
    function _tick() internal {
        _fulfillPendingVrf();
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        if (!ok) vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev Gates on dailyFoilDraw itself, not rngWordForDay: inside the jackpot phase the
    ///      day's RNG word can seal (and even unlock the NEXT day's request) across several
    ///      single-step ticks before the jackpot-daily stage that actually writes
    ///      dailyFoilDraw[day] runs — gating on the word alone would force-write a win set
    ///      onto a still-empty record (level 0: the zero value, not a real day shape).
    function _tickUntilSealed(uint24 day, uint256 maxTicks) internal {
        for (uint256 i; i < maxTicks; ++i) {
            if (uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT)))) != 0) return;
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
        bytes32 slot = keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT));
        (, uint24 recordedLvl) = _foilDraw(day);
        assertEq(uint256(recordedLvl), uint256(lvl), string.concat(tag, ": dailyFoilDraw level mismatch"));
        uint256 reserved = (uint256(vm.load(address(game), slot)) >> 32) & type(uint32).max;
        assertEq(reserved, 0, string.concat(tag, ": dailyFoilDraw bits 32..63 must read zero"));

        uint32 sel = _deriveFoilLine(player, lvl, game.rngWordForDay(day), multBps, 0);
        _forceWinSetToLine(day, sel);

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
    ///         and payDailyJackpot (the jackpot day and level 2) — never by the harness; only
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
            if (uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), FOIL_DRAW_SLOT)))) != 0) return;
            _completeDay(uint256(keccak256(abi.encode("flat-face-day", day, i))));
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        revert("harness: day never sealed within the bound");
    }
}
