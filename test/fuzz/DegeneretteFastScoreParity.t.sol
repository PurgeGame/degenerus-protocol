// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @notice Differential proof that the straight-line trait unpack and the branch-free score are
///         byte-identical to the loop forms they replaced. The reference functions below are the
///         retired production code, copied verbatim.
contract DegeneretteFastScoreParityTest is Test {
    DegeneretteMathHarness private h;

    uint256 private constant PLAYER_TICKET_TAG = 0x446567656e506c61796572; // DegenPlayer
    uint256 private constant WWXRP_RIG_SALT = 0x52494721; // RIG!
    uint8 private constant CURRENCY_WWXRP = 3;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    // ---------------------------------------------------------------------
    // Retired reference implementations (verbatim)
    // ---------------------------------------------------------------------

    function _refTraits(uint256 rand) private pure returns (uint32) {
        return uint32(_refDegTrait(uint64(rand)))
            | (uint32(_refDegTrait(uint64(rand >> 64)) | 64) << 8)
            | (uint32(_refDegTrait(uint64(rand >> 128)) | 128) << 16)
            | (uint32(_refDegTrait(uint64(rand >> 192)) | 192) << 24);
    }

    function _refDegTrait(uint64 rnd) private pure returns (uint8) {
        uint8 color = uint8(rnd) & 7;
        uint8 symbol = uint8(rnd >> 32) & 7;
        return (color << 3) | symbol;
    }

    function _refScore(uint32 playerTraits, uint32 resultTraits, uint8 heroQuadrant)
        private pure returns (uint8 score, uint8 goldMatches)
    {
        uint32 diff = playerTraits ^ resultTraits;
        for (uint8 q; q < 4; ++q) {
            uint8 d = uint8(diff >> (q * 8));
            if ((d & 7) == 0) score += q == heroQuadrant ? 2 : 1;
            if ((d & 0x38) == 0) {
                ++score;
                if (((playerTraits >> (q * 8)) & 0x38) == 0x38) ++goldMatches;
            }
        }
    }

    function _refTicket(uint256 seed, uint8 symbol) private pure returns (uint32 traits) {
        traits = _refTraits(EntropyLib.hash2(seed, PLAYER_TICKET_TAG));
        uint32 shift = uint32(symbol >> 3) * 8;
        traits = (traits & ~(uint32(7) << shift)) | (uint32(symbol & 7) << shift);
    }

    // ---------------------------------------------------------------------
    // Score: exhaustive
    // ---------------------------------------------------------------------

    function _assertScore(uint32 p, uint32 r, uint8 hero) private view {
        (uint8 s, uint8 g) = h.score(p, r, hero);
        (uint8 rs, uint8 rg) = _refScore(p, r, hero);
        assertEq(s, rs, "score");
        assertEq(g, rg, "gold");
    }

    function _setLane(uint32 word, uint256 q, uint256 lane) private pure returns (uint32) {
        uint256 shift = q * 8;
        return uint32((uint256(word) & ~(uint256(0xFF) << shift)) | ((lane & 0xFF) << shift));
    }

    /// @dev Every (player lane, result lane) pair of 6-bit values, in every quadrant, for every
    ///      hero position (0..3, an absent 4, and 255), with the other three lanes held in each
    ///      of three contexts: all missing, all gold-matching, and a fixed mixed pattern. The
    ///      quadrant tag bits 6-7 are set as production packs them.
    function _exhaustLane(uint256 q, uint32 ctxP, uint32 ctxR) private view {
        uint8[6] memory heroes = [uint8(0), 1, 2, 3, 4, 255];
        uint256 tag = q << 6;
        for (uint256 pv; pv < 64; ++pv) {
            uint32 p = _setLane(ctxP, q, pv | tag);
            for (uint256 rv; rv < 64; ++rv) {
                uint32 r = _setLane(ctxR, q, rv | tag);
                for (uint256 i; i < 6; ++i) {
                    _assertScore(p, r, heroes[i]);
                }
            }
        }
    }

    function testScoreExhaustiveLane0() public view { _exhaustAllContexts(0); }
    function testScoreExhaustiveLane1() public view { _exhaustAllContexts(1); }
    function testScoreExhaustiveLane2() public view { _exhaustAllContexts(2); }
    function testScoreExhaustiveLane3() public view { _exhaustAllContexts(3); }

    function _exhaustAllContexts(uint256 q) private view {
        // All other lanes miss both symbol and color.
        _exhaustLane(q, 0xC0804000, 0xC0804000 | 0x09090909);
        // All other lanes match symbol and a gold color (the largest counts the multiply sums).
        _exhaustLane(q, 0xC0804000 | 0x3F3F3F3F, 0xC0804000 | 0x3F3F3F3F);
        // Mixed: lane-by-lane symbol-only, color-only, gold, miss.
        _exhaustLane(q, 0xC0804000 | 0x3F3F1A05, 0xC0804000 | 0x3E073A1D);
    }

    /// @dev Every combination of per-lane match classes across all four lanes at once: symbol
    ///      match or miss x color match or miss x player color gold or not (8 classes, 8^4
    ///      joint patterns), for every hero position. Together with the per-lane sweep this
    ///      covers every carry pattern the one-multiply lane sum can meet.
    function testScoreExhaustiveJointMatchClasses() public view {
        // (player lane, result lane) representatives, 6-bit [CCC][SSS].
        uint8[8] memory pl = [uint8(0x05), 0x05, 0x05, 0x05, 0x3D, 0x3D, 0x3D, 0x3D];
        uint8[8] memory rl = [uint8(0x05), 0x06, 0x0D, 0x0E, 0x3D, 0x3E, 0x2D, 0x2E];
        uint8[6] memory heroes = [uint8(0), 1, 2, 3, 4, 255];
        for (uint256 c; c < 4096; ++c) {
            uint32 p = 0xC0804000;
            uint32 r = 0xC0804000;
            for (uint256 q; q < 4; ++q) {
                uint256 k = (c >> (q * 3)) & 7;
                p = uint32(uint256(p) | (uint256(pl[k]) << (q * 8)));
                r = uint32(uint256(r) | (uint256(rl[k]) << (q * 8)));
            }
            for (uint256 i; i < 6; ++i) {
                _assertScore(p, r, heroes[i]);
            }
        }
    }

    /// @dev Any uint32 inputs, including tag bits production never sets, and any hero byte.
    function testFuzzScoreMatchesReference(uint32 p, uint32 r, uint8 hero) public view {
        _assertScore(p, r, hero);
    }

    /// @dev Bits above each argument's width (possible for sub-word values built in assembly) are
    ///      ignored: the result equals the reference on the truncated values. Pins the hero mask.
    function testFuzzDirtyUpperBitsIgnored(uint256 pWord, uint256 rWord, uint256 heroWord) public view {
        (uint8 s, uint8 g) = h.scoreDirty(pWord, rWord, heroWord);
        (uint8 rs, uint8 rg) = _refScore(uint32(pWord), uint32(rWord), uint8(heroWord));
        assertEq(s, rs, "score");
        assertEq(g, rg, "gold");
    }

    function testDirtyHeroByteKeepsTheHeroBonus() public view {
        for (uint256 q; q < 4; ++q) {
            // Symbol match in lane q only; a clean hero q scores 2 there.
            uint32 p = uint32(0xC0804000 | (uint256(5) << (q * 8)));
            uint32 r = uint32(0xC0804000 | 0x0F0F0F0F);
            r = uint32((uint256(r) & ~(uint256(0x07) << (q * 8))) | (uint256(5) << (q * 8)));
            (uint8 clean,) = h.score(p, r, uint8(q));
            (uint8 dirty,) = h.scoreDirty(p, r, q | (uint256(0xABCD) << 8));
            assertEq(dirty, clean, "dirty hero byte lost the bonus");
            assertGe(clean, 2);
        }
    }

    // ---------------------------------------------------------------------
    // Traits: exhaustive per lane + fuzz
    // ---------------------------------------------------------------------

    /// @dev Each lane reads a 3-bit color at 64q and a 3-bit symbol at 64q+32. Sweep all 64
    ///      combinations per lane, with every other bit of the word filled by noise.
    function testTraitsExhaustivePerLane() public view {
        for (uint256 n; n < 4; ++n) {
            uint256 noise = uint256(keccak256(abi.encode("parity-noise", n)));
            for (uint256 q; q < 4; ++q) {
                for (uint256 v; v < 64; ++v) {
                    uint256 clear = ~((uint256(7) << (64 * q)) | (uint256(7) << (64 * q + 32)));
                    uint256 rand = (noise & clear) | ((v & 7) << (64 * q)) | ((v >> 3) << (64 * q + 32));
                    assertEq(h.traits(rand), _refTraits(rand), "traits");
                }
            }
        }
        assertEq(h.traits(0), _refTraits(0));
        assertEq(h.traits(type(uint256).max), _refTraits(type(uint256).max));
    }

    function testFuzzTraitsMatchReference(uint256 rand) public view {
        assertEq(h.traits(rand), _refTraits(rand));
    }

    function testFuzzTicketMatchesReference(uint256 seed, uint8 symbol) public view {
        symbol = uint8(bound(symbol, 0, 31));
        assertEq(h.ticket(seed, symbol), _refTicket(seed, symbol));
    }

    // ---------------------------------------------------------------------
    // Whole spin: every currency, chosen and random hero
    // ---------------------------------------------------------------------

    function testFuzzSpinMatchesReference(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        public
        view
    {
        symbol = uint8(bound(symbol, 0, 32));
        uint8[3] memory currencies = [uint8(0), 1, CURRENCY_WWXRP];
        currency = currencies[bound(currency, 0, 2)];
        (uint32 pt, uint32 rt, uint8 hq, uint8 s, uint8 g) = h.spin(seed, houseSeed, symbol, currency);

        uint8 sym = h.hero(seed, symbol);
        uint32 refPt = _refTicket(seed, sym);
        uint32 refRt = _refTraits(houseSeed);
        if (currency == CURRENCY_WWXRP) {
            refRt = h.rig(refPt, refRt, sym >> 3, EntropyLib.hash2(seed, WWXRP_RIG_SALT));
        }
        (uint8 refS, uint8 refG) = _refScore(refPt, refRt, sym >> 3);
        assertEq(pt, refPt, "player traits");
        assertEq(rt, refRt, "result traits");
        assertEq(hq, sym >> 3, "hero quadrant");
        assertEq(s, refS, "score");
        assertEq(g, refG, "gold");
    }
}
