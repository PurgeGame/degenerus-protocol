// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract GoldSixHarness is DegenerusGameTicketModule {
    function prepare(uint24 lvl, address who) external returns (uint256 owner) {
        level = lvl;
        _setTicketBufferLevel(lvl);
        owner = uint256(_registerEntryOwner(who, lvl) >> OWNER_IDX_SHIFT) - 1;
    }
    function taken(uint24 lvl) external view returns (bool) { return _goldSixTaken(lvl); }
    function writeKey(uint24 lvl) external view returns (uint24) { return _tqWriteKey(lvl); }
    function count(uint24 lvl, uint8 trait) external view returns (uint256) { return _bucketLength(lvl, trait); }
    function first(uint24 lvl, uint8 trait) external view returns (address) { return _bucketOwnerAtUnchecked(lvl, trait, 0); }
    function seedGold(uint24 lvl, uint256 owner) external { _bucketAppendRun(_traitBufferBase(lvl), 253, owner, 1, lvl); }
    function deity(uint8 trait, address who) external returns (address, uint256) {
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = who;
        return (_traitDeity(trait), _deityVirtualCount(trait, 100, who));
    }
    function queue(address who, uint32 scaled) external { _queueEntriesScaled(who, level, scaled, false); }
    function commit(uint256 word) external {
        ticketWriteSlot = !ticketWriteSlot;
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
    }
}

contract GoldSixRulesTest is Test {
    GoldSixHarness private h;
    address private constant A = address(0xA11CE);
    address private constant B = address(0xB0B);
    function setUp() public { h = new GoldSixHarness(); }

    function naturalRun(uint256 stream, uint256 word) private pure returns (uint8[16] memory traits) {
        uint64 s = uint64(uint256(keccak256(abi.encode(stream, word, uint256(0))))) | 1;
        unchecked {
            s *= 6364136223846793005;
            for (uint256 i; i < 16; ++i) {
                s = s * 6364136223846793005 + 1;
                traits[i] = DegenerusTraitUtils.traitFromWord(s) | uint8((i & 3) << 6);
            }
        }
    }
    function wordWithGold(uint256 stream) private pure returns (uint256 word) {
        for (word = 2; ; ++word) {
            uint8[16] memory traits = naturalRun(stream, word);
            for (uint256 i; i < 16; ++i) if (traits[i] == 253) return word;
        }
    }
    /// @dev Commit `word` as the cohort's entropy and drain it through the live ticket worker.
    function drain(uint256 word, uint24 anchor) private {
        h.commit(word);
        MineFlipGas.Result memory r = h.runTicketWork(anchor, 9_000_000);
        assertTrue(r.done, "the queued solo run drains in one call");
    }
    /// @dev One owner queued alone at `lvl` owing 16 whole entries drains as a single solo trait
    ///      run on identity(read key, lvl, 0, owner). Returns that stream; the caller commits.
    function queueSolo(uint24 lvl, address who) private returns (uint256 stream) {
        h.queue(who, 1600);
        stream = TicketEntropy.identity(h.writeKey(lvl), lvl, 0, who);
    }
    function testSoloCapAcrossOwnersAndRecycledLevelPreservesEveryOtherTrait() public {
        h.prepare(1, A);
        assertFalse(h.taken(1));
        uint256 stream = queueSolo(1, A);
        uint256 word = wordWithGold(stream);
        uint8[16] memory natural = naturalRun(stream, word);
        uint256[256] memory raw;
        for (uint256 i; i < 16; ++i) ++raw[natural[i]];
        drain(word, 2);
        assertEq(h.count(1, 253), 1);
        assertTrue(h.taken(1));
        assertFalse(h.taken(2));
        assertFalse(h.taken(3), "new level ignores older parity before preparation");
        assertEq(h.first(1, 253), A);
        h.prepare(1, B);
        // Another owner's run at the same level whose natural pattern also rolls the gold six.
        stream = queueSolo(1, B);
        word = wordWithGold(stream);
        natural = naturalRun(stream, word);
        for (uint256 i; i < 16; ++i) ++raw[natural[i]];
        drain(word, 2);
        uint256 total;
        uint256 gold;
        for (uint256 t; t < 256; ++t) {
            uint256 n = h.count(1, uint8(t));
            total += n;
            if (t >= 248) gold += n;
            else assertEq(n, raw[t], "non-gold-dice traits unchanged");
        }
        uint256 rawGold;
        for (uint256 t = 248; t < 256; ++t) rawGold += raw[t];
        assertEq(total, 32);
        assertEq(gold, rawGold);
        assertEq(h.count(1, 253), 1);
        assertEq(h.first(1, 253), A);
        h.prepare(3, B);
        assertFalse(h.taken(3));
        vm.expectRevert();
        h.taken(1);
        stream = queueSolo(3, B);
        drain(wordWithGold(stream), 4);
        assertEq(h.count(3, 253), 1, "new full level resets the cap despite parity reuse");
        assertTrue(h.taken(3));
        assertEq(h.first(3, 253), B);
    }
    function roundWord() private pure returns (uint256 word) {
        for (word = 2; ; ++word) {
            uint256 seed = uint256(keccak256(abi.encode(uint24(1), uint32(0), word)));
            if ((DegenerusTraitUtils.traitFromWord(uint64(seed >> 192)) >> 3) == 7) return word;
        }
    }
    function testRoundCapAndRandomRotationPreserveOriginalOwnerIdentities() public {
        uint256 owner = h.prepare(1, A);
        for (uint256 i; i < 8; ++i) h.queue(address(uint160(0x1000 + i)), 400);
        uint256 word = roundWord();
        uint256 snapshot = vm.snapshotState();
        for (uint256 preclaimed; preclaimed < 2; ++preclaimed) {
            if (preclaimed != 0) h.seedGold(1, owner);
            h.commit(word);
            MineFlipGas.Result memory r = h.runTicketWork(2, 9_000_000);
            assertTrue(r.done);
            assertEq(h.count(1, 253), 1);
            uint256 total;
            uint256 gold;
            for (uint256 t; t < 256; ++t) {
                total += h.count(1, uint8(t));
                if (t >= 248) gold += h.count(1, uint8(t));
            }
            assertEq(total, 32 + preclaimed);
            assertEq(gold, 8 + preclaimed);
            if (preclaimed != 0) assertEq(h.first(1, 253), A);
            else {
                uint256 seed = uint256(keccak256(abi.encode(uint24(1), uint32(0), word)));
                uint256 rot = (seed >> 232) & 7;
                uint256 seat = (13 - rot) & 7;
                uint256 physical = TicketEntropy.queueIndex(seat, TicketEntropy.queueStart(1, 8, word), 8);
                assertEq(h.first(1, 253), address(uint160(0x1000 + physical)));
                assertTrue(vm.revertToStateAndDelete(snapshot));
            }
        }
    }
    function testGoldSixHasNoVirtualDeityWhileOtherDiceKeepTheirs() public {
        (address who, uint256 count) = h.deity(253, A);
        assertEq(who, address(0));
        assertEq(count, 0);
        for (uint8 t = 248; t < 255; ++t) {
            if (t == 253) continue;
            (who, count) = h.deity(t, A);
            assertEq(who, A);
            assertEq(count, 1);
        }
        (who, count) = h.deity(245, A); // silver six keeps normal deity treatment
        assertEq(who, A);
        assertEq(count, 1);
    }
    function testReplacementAndDailyKeepRates() public pure {
        uint256[8] memory picks;
        uint256 kept;
        for (uint256 word; word < 4200; ++word) {
            uint8 replacement = GoldSixLib.replacement(word);
            require(replacement >= 248 && replacement != 253);
            ++picks[replacement & 7];
            uint8 daily = GoldSixLib.daily(253, word);
            if (daily == 253) ++kept;
            else require(daily == replacement);
            require(GoldSixLib.daily(uint8(word % 253), word) == uint8(word % 253));
        }
        require(kept > 580 && kept < 820, "keep rate near one sixth");
        for (uint256 s; s < 8; ++s) if (s != 5) require(picks[s] > 480 && picks[s] < 720, "seven balanced replacements");
    }
    function testFuzzRotationHashMatchesOriginalAbiEncoding(uint24 key, uint32 count, uint256 word) public pure {
        uint256 expected = count < 2 ? 0 : uint256(keccak256(abi.encode(
            keccak256("DEGENERUS_TICKET_ROTATION_V1"), key, uint256(count), word
        ))) % count;
        assertEq(TicketEntropy.queueStart(key, count, word), expected);
    }
    function testRotationSpansEveryStartingWallet() public pure {
        uint256[17] memory starts;
        for (uint256 word = 2; word < 1702; ++word) {
            uint256 start = TicketEntropy.queueStart(1, 17, word);
            ++starts[start];
            uint256 seen;
            for (uint256 i; i < 17; ++i) seen |= uint256(1) << TicketEntropy.queueIndex(i, start, 17);
            require(seen == (1 << 17) - 1, "rotation visits each wallet exactly once");
        }
        for (uint256 i; i < 17; ++i) require(starts[i] > 50 && starts[i] < 150, "no permanent first wallet");
    }
}
