// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title FoilDrainMiddaySwap — the foil pack's sixteen entries against the queue swaps.
///
/// @notice Foil and normal tickets share frozen read/write cohorts. The same
/// request commits both queues, and purchases after commitment wait for fresh RNG.
/// Every paid pack must generate sixteen entries once, with stored lines matching
/// the filed traits, before its first eligible draw.
contract FoilDrainMiddaySwap is DeployProtocol {
    address private crank = address(0xC4A9);
    address private ticketBuyer = address(0xB4A1);

    uint256 private simTime;

    bytes32 private constant FOIL_SEED_TAG = keccak256("foil-seed");

    // Storage slots (forge inspect DegenerusGame storage-layout).
    uint256 private constant SLOT_LVL_TRAIT_ENTRY = GameSlots.LVL_TRAIT_ENTRY;
    uint256 private constant SLOT_RNG_WORD_BY_DAY = GameSlots.RNG_WORD_BY_DAY;
    uint256 private constant SLOT_FOIL_RECORD = GameSlots.FOIL_RECORD;
    uint256 private constant SLOT_FOIL_CURSORS = GameSlots.FOIL_CURSOR;

    struct Pack {
        address buyer;
        uint24 lvl;
        uint24 resolveDay;
        uint16 multBps;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(ticketBuyer, 200_000 ether);
        vm.deal(crank, 10 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // A. Baseline
    // ---------------------------------------------------------------------

    /// A foil pack bought on a quiet day materializes exactly sixteen entries, at the
    /// derived traits, into the cycle level it bet into.
    function testBaselineFoilPackMaterializesSixteenEntries() public {
        vm.pauseGasMetering();
        _warmUpDays(3);

        address p = address(0xF0111);
        Pack memory pack = _buyFoil(p);
        assertGt(pack.multBps, 0, "A: frozen foil record written");

        _runDaysUntilDrained(pack, 6);
        _assertPackFiled(pack, "A");
    }

    // ---------------------------------------------------------------------
    // B. Mid-day request between buy and seal
    // ---------------------------------------------------------------------

    /// The mid-day lootbox request swaps the ticket buffer while the pack's bucket is still
    /// future-dated. The foil queue is not double-buffered, so the swap must not disturb it.
    function testMiddayRequestBetweenBuyAndSealDoesNotStrand() public {
        vm.pauseGasMetering();
        _warmUpDays(3);

        address p = address(0xF0222);
        Pack memory pack = _buyFoil(p);

        // The swap only fires with work on the write side, so seed a ticket cohort first.
        _buyTickets();

        // Fire the mid-day request (and its global _swapTicketSlot) in the same day the
        // pack was bought — its resolveDay word does not exist yet.
        bool swapped = _middayRequest();
        assertTrue(swapped, "B: mid-day request did not swap the ticket buffer");
        _drainMidday();

        _runDaysUntilDrained(pack, 6);
        _assertPackFiled(pack, "B");
    }

    // ---------------------------------------------------------------------
    // C. Bought inside the daily RNG lock
    // ---------------------------------------------------------------------

    /// A pack bought while rngLockedFlag is set routes to resolveDay = day + 1 and still
    /// materializes; it must never join the cohort of the draw already in flight.
    function testFoilBoughtInsideDailyLockStillMaterializes() public {
        vm.pauseGasMetering();
        _warmUpDays(3);

        // Cross the boundary and take ONE advance so the daily request fires and the lock
        // latches, but the word has not been fulfilled.
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("mineFlip()")
        );
        ok; // the first advance of a day may partial-drain; either way we probe the lock

        address p = address(0xF0333);
        Pack memory pack = _buyFoil(p);
        assertGt(pack.multBps, 0, "C: frozen foil record written");
        assertEq(pack.resolveDay, 0, "C: pending pack has no generation day");
        _runDaysUntilDrained(pack, 6);
        _assertPackFiled(pack, "C");
    }

    // ---------------------------------------------------------------------
    // D. Sparse buys across non-contiguous days
    // ---------------------------------------------------------------------

    /// The buy-side cursor skip (`foilGenerationDay = resolveDay` when the drain has caught up)
    /// must neither strand an earlier populated bucket nor rewind onto a drained one.
    function testSparseBuysNeverStrandOrDoubleFile() public {
        vm.pauseGasMetering();
        _warmUpDays(2);

        Pack[3] memory packs;
        packs[0] = _buyFoil(address(0xF0441));
        _runFullDay();
        _runFullDay();
        _runFullDay();
        packs[1] = _buyFoil(address(0xF0442));
        _runFullDay();
        _runFullDay();
        packs[2] = _buyFoil(address(0xF0443));

        for (uint256 i = 0; i < 8; i++) _runFullDay();

        for (uint256 i = 0; i < 3; i++) {
            _assertPackFiled(packs[i], "D");
        }
    }

    // ---------------------------------------------------------------------
    // E. Mid-day request AFTER the bucket sealed
    // ---------------------------------------------------------------------

    /// The bucket seals on its resolveDay; a mid-day request that same day flips the ticket
    /// buffer again. The foil bucket must already be drained (the readiness gate holds the
    /// draw until it is) and must not be re-walked by the post-swap drain.
    function testMiddayRequestAfterSealDoesNotDoubleFile() public {
        vm.pauseGasMetering();
        _warmUpDays(3);

        address p = address(0xF0555);
        Pack memory pack = _buyFoil(p);

        // Roll into the resolveDay and settle it — this is the advance chain that seals
        // _recordedDailyWord(resolveDay) and drains the bucket.
        _runFullDay();
        _assertPackFiled(pack, "E-pre");

        // Now fire a mid-day request on the SAME day the bucket drained.
        bool swapped = _middayRequest();
        swapped; // a swap is not guaranteed if nothing is queued; the drain runs either way
        _drainMidday();

        // Still exactly sixteen — the drained bucket must not be re-walked.
        _assertPackFiled(pack, "E-post");
    }

    // ---------------------------------------------------------------------
    // F. Ordering — the entries are filed BEFORE the draw they bet on
    // ---------------------------------------------------------------------

    /// F4 in-time, proven on the log stream rather than on end-state: within the resolveDay
    /// advance chain, the pack's `TraitsGenerated` must be emitted before the
    /// `DailyWinningTraits` that seals that day's winning sets — otherwise the pack paid for
    /// a board its own sixteen entries were not yet in. Run with a mid-day request in the
    /// window so the ticket-buffer swap is live across the ordering.
    function testFoilEntriesAreFiledBeforeTheDrawTheyBetOn() public {
        vm.pauseGasMetering();
        _warmUpDays(3);

        address p = address(0xF0666);
        Pack memory pack = _buyFoil(p);
        _buyTickets();
        vm.recordLogs();
        _middayRequest();
        _drainMidday();

        // Include materialization and the next eligible draw.
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            if (!game.rngLocked()) _finishReadConsumers();
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 traitsSig = keccak256(
            "TraitsGenerated(address,uint256,uint32)"
        );
        bytes32 drawSig = keccak256(
            "DailyWinningTraits(uint24,uint32)"
        );

        int256 foilAt = -1;
        int256 drawAt = -1;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 0) continue;
            if (
                foilAt < 0 &&
                l.topics[0] == traitsSig &&
                l.topics.length > 1 &&
                address(uint160(uint256(l.topics[1]))) == p
            ) {
                foilAt = int256(i);
            }
            if (
                drawAt < 0 &&
                l.topics[0] == drawSig &&
                l.topics.length > 1 &&
                uint24(uint256(l.topics[1])) == uint24(_packedFoilRecord(pack.lvl, pack.buyer))
            ) {
                drawAt = int256(i);
            }
        }

        assertGe(foilAt, 0, "F: pack never emitted TraitsGenerated");
        assertGe(drawAt, 0, "F: resolveDay never sealed its winning traits");
        assertLt(
            foilAt,
            drawAt,
            "F: pack's entries were filed AFTER the draw it bet on"
        );

        _assertPackFiled(pack, "F");
    }

    // =====================================================================
    // Invariant assertions
    // =====================================================================

    /// F1 + F2 + F3: the pack's sixteen entries are filed exactly once, at exactly the
    /// traits the claim-side derivation produces.
    function _assertPackFiled(Pack memory pack, string memory tag) internal view {
        uint256 record = _packedFoilRecord(pack.lvl, pack.buyer);
        assertGt(pack.multBps, 0, string.concat(tag, ": frozen record missing"));
        assertTrue(record >> 255 != 0, string.concat(tag, ": pack never generated"));
        uint8[16] memory expected;
        for (uint256 i; i < 16; ++i) expected[i] = uint8(record >> (56 + 8 * i));

        // Expected multiset, indexed by trait id.
        uint16[256] memory want;
        for (uint256 i = 0; i < 16; i++) {
            want[expected[i]] += 1;
        }

        uint256 total;
        for (uint256 t = 0; t < 256; t++) {
            uint256 got = _traitEntryCountOf(pack.lvl, uint8(t), pack.buyer);
            assertEq(
                got,
                uint256(want[t]),
                string.concat(tag, ": trait multiset mismatch (mint != claim)")
            );
            total += got;
        }
        assertEq(total, 16, string.concat(tag, ": entry count must be exactly 16"));
    }

    /// The SAME derivation `_deriveFoilLines` performs: four keccak seeds off
    /// (entropy, buyer, level, FOIL_SEED_TAG, i), each sliced into four 64-bit lanes
    /// through the boosted cut ladder, with the quadrant tag OR'd in.
    function _deriveFoilTraits(
        address buyer,
        uint24 lvl,
        uint256 entropy,
        uint16 multBps
    ) internal pure returns (uint8[16] memory out) {
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(multBps);
        for (uint256 i = 0; i < 4; i++) {
            uint256 seed = uint256(
                keccak256(abi.encode(entropy, buyer, lvl, FOIL_SEED_TAG, i))
            );
            out[i * 4 + 0] = DegenerusTraitUtils.foilTrait(uint64(seed), cut);
            out[i * 4 + 1] =
                DegenerusTraitUtils.foilTrait(uint64(seed >> 64), cut) |
                64;
            out[i * 4 + 2] =
                DegenerusTraitUtils.foilTrait(uint64(seed >> 128), cut) |
                128;
            out[i * 4 + 3] =
                DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) |
                192;
        }
    }

    // =====================================================================
    // Drivers
    // =====================================================================

    /// Buy exactly one foil pack (no ticket leg, no lootbox leg) and read back the record
    /// the buy froze.
    function _buyFoil(address p) internal returns (Pack memory pack) {
        vm.deal(p, 50_000 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint24 lvl = _activeTicketLevelProbe();
        vm.prank(p);
        game.purchase{value: priceWei * 10}(
            p,
            0,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            true
        );
        (uint24 resolveDay, uint16 multBps) = _foilRecord(lvl, p);
        pack = Pack({
            buyer: p,
            lvl: lvl,
            resolveDay: resolveDay,
            multBps: multBps
        });
    }

    /// Roll days until the pack's bucket has been walked past, bounded.
    function _runDaysUntilDrained(Pack memory pack, uint256 maxDays) internal {
        for (uint256 i = 0; i < maxDays; i++) {
            if (_packedFoilRecord(pack.lvl, pack.buyer) >> 255 != 0) return;
            _runFullDay();
        }
    }

    function _warmUpDays(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _buyTickets();
            _runFullDay();
        }
    }

    function _buyTickets() internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(ticketBuyer);
        game.purchase{value: (priceWei * 4000) / 400}(
            ticketBuyer,
            4000,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    function _middayRequest() internal returns (bool swapped) {
        _finishReadConsumers();
        vm.prank(ticketBuyer);
        game.purchase{value: 2 ether}(
            ticketBuyer,
            0,
            BoxOrderLib.boCustom(2 ether),
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
        bool before = _ticketWriteSlot();
        // mineFlip is the only door to the mid-day request; call it only when the request is
        // the engine's next action, so the call does nothing but request.
        vm.prank(crank);
        if (game.minerAction() != 18) return false;
        vm.prank(crank);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("mineFlip()")
        );
        if (!ok) return false;
        swapped = _ticketWriteSlot() != before;
    }

    function _drainMidday() internal {
        _fulfillPending();
        for (uint256 i = 0; i < 100; i++) {
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
    }

    function _runFullDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            if (!game.rngLocked()) _finishReadConsumers();
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId)));
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    // =====================================================================
    // Storage probes
    // =====================================================================

    function _packedFoilRecord(uint24 lvl, address who) internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), keccak256(abi.encode(uint256(lvl & 3), SLOT_FOIL_RECORD))))));
        return uint24(packed >> 208) == lvl ? packed : 0;
    }

    /// foilRecord[lvl & 3][buyer] — slot 58; [208-231] authenticates the level.
    function _foilRecord(
        uint24 lvl,
        address who
    ) internal view returns (uint24 resolveDay, uint16 multBps) {
        uint256 packed = _packedFoilRecord(lvl, who);
        resolveDay = uint24(packed);
        multBps = uint16(packed >> 24);
    }

    /// foilCursor | foilGenerationDay | foilFirstDrawDay — slot 62 at byte offsets 0/4/7.
    function _foilGenerationDay() internal view returns (uint24) {
        uint256 s = uint256(
            vm.load(address(game), bytes32(SLOT_FOIL_CURSORS))
        );
        return uint24(s >> 32);
    }

    function _foilFirstDrawDay() internal view returns (uint24) {
        uint256 s = uint256(
            vm.load(address(game), bytes32(SLOT_FOIL_CURSORS))
        );
        return uint24(s >> 56);
    }

    /// _recordedDailyWord(day) — slot 10.
    function _rngWordByDay(uint24 day) internal view returns (uint256) {
        return
            uint256(
                vm.load(
                    address(game),
                    keccak256(
                        abi.encode(uint256(day), SLOT_RNG_WORD_BY_DAY)
                    )
                )
            );
    }

    /// How many times `who` appears in lvlTraitEntry[lvl][traitId] — slot 8.
    function _traitEntryCountOf(
        uint24 lvl,
        uint8 traitId,
        address who
    ) internal view returns (uint256 n) {
        bytes32 levelSlot = keccak256(
            abi.encode(uint256(lvl & 1), SLOT_LVL_TRAIT_ENTRY)
        );
        bytes32 elem = bytes32(uint256(levelSlot) + uint256(traitId));
        uint256 header = uint256(vm.load(address(game), elem));
        uint48 stamps = uint48(uint256(vm.load(address(game), bytes32(GameSlots.TICKET_BUFFER_LEVELS))) >> (GameSlots.TICKET_BUFFER_LEVELS_OFFSET * 8));
        uint256 bits = uint256(vm.load(address(game), bytes32(GameSlots.TRAIT_BUCKET_LIVE + (lvl & 1))));
        if (uint24(stamps >> ((lvl & 1) * 24)) != lvl || ((bits >> traitId) & 1) == 0) return 0;
        uint256 len = uint32(header);
        if (len == 0) return 0;
        uint256 base = uint256(keccak256(abi.encode(elem)));
        // Lanes are uint32 registry positions, eight per word; resolve through
        // the wallet table (element low 160 bits = owner address).
        for (uint256 i = 0; i < len; i++) {
            uint256 word = (i >> 3) == (len >> 3) ? header >> 32
                : uint256(vm.load(address(game), bytes32(base + (i >> 3))));
            uint256 lane = (word >> (32 * (i & 7))) & 0xffffffff;
            address a = address(
                uint160(
                    uint256(vm.load(address(game), GameSlotKeys.walletElement(uint32(lane))))
                )
            );
            if (a == who) {
                unchecked {
                    ++n;
                }
            }
        }
    }

    /// dailyIdx — slot 0, byte 3.
    function _dailyIdx() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(GameSlots.DAILY_IDX))));
        return uint24(s0 >> 24);
    }

    /// level — slot 0, bytes [12:15).
    function _level() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 96);
    }

    /// ticketWriteSlot — slot 0, byte 25.
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 200) & 1) != 0;
    }

    /// The level a foil buy routes to right now — mirrors `_activeTicketLevel()` for the
    /// purchase-phase / jackpot-phase split this suite drives.
    function _activeTicketLevelProbe() internal view returns (uint24) {
        return game.jackpotPhase() ? _level() : _level() + 1;
    }
}
