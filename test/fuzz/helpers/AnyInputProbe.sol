// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../../../contracts/storage/DegenerusGameStorage.sol";

/// @title AnyInputProbe -- read-only views over Game storage for AnyInputHandler's guided claim doors
/// @notice Runtime is etched over the Game for one staticcall and the production code is put back,
///         so every view reads live Game storage through the production layout. The views only
///         locate a holding a real player would cite (a bingo row, a dead-ending holding, a gold
///         or match foil pack); the claim itself then runs on the production runtime, which
///         re-checks everything. Gates mirror the claim paths' own checks so a candidate the
///         production claim refuses shows up as a refusal in the handler's report.
contract AnyInputProbe is DegenerusGameStorage {
    uint256 private constant DEAD_REF_QUEUED = 1;

    // ------------------------------------------------------------------ bingo

    /// @notice First (owner, symbol) among `ids` that holds all eight colors of one symbol at `lvl`,
    ///         with the occurrence index per color. Buckets longer than `maxScan` are scanned in part.
    function findBingo(uint24 lvl, uint32[] calldata ids, uint256 maxScan)
        external
        view
        returns (bool found, uint256 who, uint8 symbol, uint32[8] memory slots)
    {
        if (gameOver || _ticketLevelRetired(lvl)) return (false, 0, 0, slots);
        uint256 n = ids.length;
        // first[i * 256 + trait] = occurrence index + 1 of ids[i] in that trait's bucket.
        uint32[] memory first = new uint32[](n * 256);
        for (uint256 trait; trait < 256; ++trait) {
            uint256 len = _bucketLengthUnchecked(lvl, trait);
            if (len > maxScan) len = maxScan;
            uint256 word;
            for (uint256 k; k < len; ++k) {
                if ((k & 7) == 0) word = _bucketWordAtUnchecked(lvl, uint8(trait), k);
                uint32 owner = _bucketIdFromWord(word, k);
                for (uint256 i; i < n; ++i) {
                    if (owner == ids[i] && first[i * 256 + trait] == 0) first[i * 256 + trait] = uint32(k + 1);
                }
            }
        }
        for (uint256 i; i < n; ++i) {
            if (ids[i] == 0 || _bingoClaimed(lvl, ids[i])) continue;
            for (uint256 s; s < 32; ++s) {
                uint256 base = ((s >> 3) << 6) | (s & 7);
                bool all = true;
                for (uint256 c; c < 8 && all; ++c) {
                    uint32 at = first[i * 256 + (base | (c << 3))];
                    if (at == 0) all = false;
                    else slots[c] = at - 1;
                }
                if (all) return (true, i, uint8(s), slots);
            }
        }
    }

    function bingoClaimed(uint24 lvl, uint32 id) external view returns (bool) {
        return _bingoClaimed(lvl, id);
    }

    // ------------------------------------------------------------------ dead-VRF ending

    /// @notice Up to `maxRefs` unclaimed terminal-level holdings of `id` and the amount claimDeadVrf
    ///         credits for them, by the claim's own share arithmetic. Empty when no deterministic
    ///         payout is open.
    function deadRefs(uint32 id, uint256 maxRefs, uint256 maxScan)
        external
        view
        returns (uint256[] memory refs, uint256 expected, uint256 weight)
    {
        refs = new uint256[](maxRefs);
        uint256 total = deadTotal;
        uint256 count;
        if (id == 0 || total == 0 || _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) {
            assembly ("memory-safe") { mstore(refs, 0) }
            return (refs, 0, 0);
        }
        uint256 pot = deadPot;
        uint24 lvl = _gameOverTicketLevel(level);
        uint8 shift = _snapShiftFor(lvl);
        uint24[3] memory keys = [_tqReadKey(lvl), _tqWriteKey(lvl), _tqFarFutureKey(lvl)];
        uint256 left = deadUncreatedLeft;
        for (uint256 j; j < 3 && count < maxRefs; ++j) {
            if (j == 1 && keys[1] == keys[0]) continue;
            uint80 packed = _entryPacked(keys[j], id);
            uint256 w = uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
            if (shift != 0 && packed & SNAP_DONE_BIT == 0) w >>= shift;
            if (w == 0 || weight + w > left) continue;
            refs[count++] = (DEAD_REF_QUEUED << 248) | (uint256(keys[j]) << 32) | id;
            weight += w;
            expected += (pot * w) / total;
        }
        if (!_ticketLevelRetired(lvl)) {
            uint256 traits = deadTraitCount;
            uint256 perTrait = traits == 0 ? 0 : (pot * uint256(deadCreated) * QTY_SCALE) / total / traits;
            for (uint256 trait; trait < 256 && count < maxRefs; ++trait) {
                uint256 n = _bucketLengthUnchecked(lvl, trait);
                uint256 scan = n > maxScan ? maxScan : n;
                for (uint256 k; k < scan && count < maxRefs; ++k) {
                    if (_bucketIdAtUnchecked(lvl, uint8(trait), k) != id) continue;
                    if (deadClaimed[(trait << 64) | (k >> 8)] & (uint256(1) << (k & 255)) != 0) continue;
                    refs[count++] = (trait << 64) | k;
                    expected += perTrait / n;
                }
            }
        }
        assembly ("memory-safe") { mstore(refs, count) }
    }

    // ------------------------------------------------------------------ foil packs

    /// @notice A pack of `id` at `lvl` whose gold claim is open and pays (3+ golds, under two
    ///         all-gold tickets, not yet settled).
    function goldenOpen(uint32 id, uint24 lvl) external view returns (bool) {
        if (_livenessTriggered()) return false;
        uint256 record = _foilRecordWord(id, lvl);
        if (record & _FOIL_READY == 0 || !_foilGoldClaimOpen(uint24(record >> _FOIL_GENERATED_DAY_SHIFT))) return false;
        if (record & _FOIL_GOLD_CLAIMED != 0) return false;
        uint32[4] memory lines = _foilStoredLines(id, lvl);
        uint256 golds;
        uint256 allGold;
        for (uint256 i; i < 4; ++i) {
            uint256 inLine;
            for (uint256 q; q < 4; ++q) {
                if (((uint8(lines[i] >> (8 * q)) >> 3) & 7) == 7) ++inLine;
            }
            golds += inLine;
            if (inLine == 4) ++allGold;
        }
        return golds >= 3 && allGold < 2;
    }

    /// @notice `id` already holds this cycle's one foil pack (the buy would refuse).
    function foilBought(uint32 id) external view returns (bool) {
        return _foilBoughtThisLevel(id, _activeTicketLevel());
    }

    /// @notice Report view: the pack record, its gold count and whether its gold window is open.
    function foilStatus(uint32 id, uint24 lvl) external view returns (uint256 record, uint256 golds, bool open) {
        record = _foilRecordWord(id, lvl);
        uint32[4] memory lines = _foilStoredLines(id, lvl);
        for (uint256 i; i < 4; ++i) {
            for (uint256 q; q < 4; ++q) if (((uint8(lines[i] >> (8 * q)) >> 3) & 7) == 7) ++golds;
        }
        open = _foilGoldClaimOpen(uint24(record >> _FOIL_GENERATED_DAY_SHIFT));
    }

    function goldClaimed(uint32 id, uint24 lvl) external view returns (bool) {
        return _foilRecordWord(id, lvl) & _FOIL_GOLD_CLAIMED != 0;
    }

    /// @notice A (draw day, ticket) of `id`'s pack that scores 4+ against an open draw and is unclaimed.
    function foilMatchOpen(uint32 id) external view returns (bool found, uint24 day, uint8 ticket) {
        if (_livenessTriggered() || rngLockedFlag) return (false, 0, 0);
        uint256 today = _latestFoilDrawDay();
        for (uint256 back; back < 2 && back < today; ++back) {
            uint256 d = today - back;
            uint256 draw = _foilDrawWord(d);
            if (draw & _FOIL_DRAW_SEEDED == 0) continue;
            uint32 winSet = uint32(draw);
            uint256 record = _foilRecordWord(id, uint24(draw >> 64));
            if (record & _FOIL_READY == 0 || d < uint24(record)) continue;
            for (uint256 t; t < 4; ++t) {
                if (_foilMatchAlreadyClaimed(id, uint24(d), t)) continue;
                uint32 sel = uint32(record >> (_FOIL_LINES_SHIFT + t * 32));
                uint256 score;
                for (uint256 q; q < 4; ++q) {
                    uint8 s = uint8(sel >> (8 * q));
                    uint8 w = uint8(winSet >> (8 * q));
                    if ((s & 7) == (w & 7)) score += ((s >> 3) & 7) == ((w >> 3) & 7) ? 2 : 1;
                }
                if (score >= 4) return (true, uint24(d), uint8(t));
            }
        }
    }

    function foilMatchMarked(uint32 id, uint24 day, uint256 ticket) external view returns (bool) {
        return _foilMatchAlreadyClaimed(id, day, ticket);
    }
}
