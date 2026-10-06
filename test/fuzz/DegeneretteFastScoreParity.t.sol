// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @notice Differential proof that the straight-line producers and the branch-free score equal
///         plain scalar loop forms on every valid board: the player holds exactly one wild, at
///         the hero lane; any house lane may be wild; wilds carry zero color bits; bit 7 is zero.
contract DegeneretteFastScoreParityTest is Test {
    DegeneretteMathHarness private h;

    uint256 private constant PLAYER_TICKET_TAG = 0x446567656e506c61796572; // DegenPlayer
    uint256 private constant WWXRP_RIG_SALT = 0x52494721; // RIG!
    uint8 private constant CURRENCY_WWXRP = 3;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    // ---------------------------------------------------------------------
    // Scalar references
    // ---------------------------------------------------------------------

    function _refOrdinary(uint256 rand) private pure returns (uint32 t) {
        for (uint256 q; q < 4; ++q) {
            uint256 lane = rand >> (64 * q);
            t |= uint32(((lane & 7) << 3) | ((lane >> 32) & 7)) << uint32(q * 8);
        }
    }

    function _refHouse(uint256 rand) private pure returns (uint32 t) {
        for (uint256 q; q < 4; ++q) {
            uint256 lane = rand >> (64 * q);
            uint256 b = (lane >> 3) & 15 == 0 ? 0x40 | ((lane >> 32) & 7) : ((lane & 7) << 3) | ((lane >> 32) & 7);
            t |= uint32(b) << uint32(q * 8);
        }
    }

    function _refScore(uint32 p, uint32 r) private pure returns (uint8 score, uint8 wilds) {
        for (uint256 q; q < 4; ++q) {
            uint8 a = uint8(p >> (q * 8));
            uint8 b = uint8(r >> (q * 8));
            bool aw = a & 0x40 != 0;
            bool bw = b & 0x40 != 0;
            if (a & 7 == b & 7) ++score;
            if (aw && bw) score += 2;
            else if (aw || bw) ++score;
            else if ((a >> 3) & 7 == (b >> 3) & 7) ++score;
            if (bw) ++wilds;
        }
    }

    function _refTicket(uint256 seed, uint8 symbol) private pure returns (uint32 traits) {
        traits = _refOrdinary(EntropyLib.hash2(seed, PLAYER_TICKET_TAG));
        uint32 shift = uint32(symbol >> 3) * 8;
        traits = (traits & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (symbol & 7)) << shift);
    }

    /// @dev Force a raw word into a valid player ticket for `hero`, or a valid house word.
    function _validPlayer(uint32 raw, uint256 hero) private pure returns (uint32 p) {
        for (uint256 q; q < 4; ++q) {
            uint32 lane = (raw >> uint32(q * 8)) & 0xFF;
            lane = q == hero ? 0x40 | (lane & 7) : lane & 0x3F;
            p |= lane << uint32(q * 8);
        }
    }

    function _validHouse(uint32 raw, uint256 wildMask) private pure returns (uint32 r) {
        for (uint256 q; q < 4; ++q) {
            uint32 lane = (raw >> uint32(q * 8)) & 0xFF;
            lane = (wildMask >> q) & 1 == 1 ? 0x40 | (lane & 7) : lane & 0x3F;
            r |= lane << uint32(q * 8);
        }
    }

    function _assertScore(uint32 p, uint32 r) private view {
        (uint8 s, uint8 w) = h.score(p, r);
        (uint8 rs, uint8 rw) = _refScore(p, r);
        assertEq(s, rs, "score");
        assertEq(w, rw, "wilds");
    }

    function _setLane(uint32 word, uint256 q, uint256 lane) private pure returns (uint32) {
        uint256 shift = q * 8;
        return uint32((uint256(word) & ~(uint256(0xFF) << shift)) | ((lane & 0xFF) << shift));
    }

    // ---------------------------------------------------------------------
    // Score: exhaustive
    // ---------------------------------------------------------------------

    /// @dev Every valid (player lane, house lane) pair in lane q, for every hero position, with
    ///      the other lanes in three valid contexts: all missing, all at their maximum points,
    ///      and a mixed pattern including house wilds.
    function _exhaustLane(uint256 q, uint32 ctxP, uint32 ctxR, uint256 ctxWilds) private view {
        for (uint256 hero; hero < 4; ++hero) {
            uint32 baseP = _validPlayer(ctxP, hero);
            uint32 baseR = _validHouse(ctxR, ctxWilds & ~(uint256(1) << q));
            uint256 playerValues = q == hero ? 8 : 64;
            for (uint256 pv; pv < playerValues; ++pv) {
                uint32 p = _setLane(baseP, q, q == hero ? 0x40 | pv : pv);
                for (uint256 rv; rv < 72; ++rv) {
                    _assertScore(p, _setLane(baseR, q, rv < 64 ? rv : 0x40 | (rv - 64)));
                }
            }
        }
    }

    function _exhaustAllContexts(uint256 q) private view {
        _exhaustLane(q, 0x00000000, 0x09090909, 0);
        _exhaustLane(q, 0x3F3F3F3F, 0x3F3F3F3F, 15);
        _exhaustLane(q, 0x3F3F1A05, 0x3E073A1D, 5);
    }

    function testScoreExhaustiveLane0() public view { _exhaustAllContexts(0); }
    function testScoreExhaustiveLane1() public view { _exhaustAllContexts(1); }
    function testScoreExhaustiveLane2() public view { _exhaustAllContexts(2); }
    function testScoreExhaustiveLane3() public view { _exhaustAllContexts(3); }

    /// @dev Every combination of per-lane classes across all four lanes, for every hero:
    ///      symbol hit/miss x house ordinary-equal / ordinary-different / wild. Covers every
    ///      carry pattern the one-multiply lane sum can meet.
    function testScoreExhaustiveJointClasses() public view {
        uint8[6] memory house = [uint8(0x05), 0x06, 0x0D, 0x0E, 0x45, 0x46];
        for (uint256 hero; hero < 4; ++hero) {
            for (uint256 c; c < 1296; ++c) {
                uint32 p;
                uint32 r;
                uint256 k = c;
                for (uint256 q; q < 4; ++q) {
                    p |= uint32(q == hero ? 0x45 : 0x05) << uint32(q * 8);
                    r |= uint32(house[k % 6]) << uint32(q * 8);
                    k /= 6;
                }
                _assertScore(p, r);
            }
        }
    }

    function testFuzzScoreMatchesReferenceOnValidBoards(uint32 rawP, uint32 rawR, uint8 hero, uint8 wildMask)
        public
        view
    {
        _assertScore(_validPlayer(rawP, hero % 4), _validHouse(rawR, wildMask % 16));
    }

    // ---------------------------------------------------------------------
    // Producers: exhaustive per lane + fuzz
    // ---------------------------------------------------------------------

    /// @dev Each lane reads color at 64q, the wild nibble at 64q+3 and symbol at 64q+32. Sweep all
    ///      color/symbol pairs and every wild nibble per lane, other bits filled by noise.
    function testProducersExhaustivePerLane() public view {
        for (uint256 n; n < 2; ++n) {
            uint256 noise = uint256(keccak256(abi.encode("parity-noise", n)));
            for (uint256 q; q < 4; ++q) {
                uint256 clear = ~((uint256(0x7F) << (64 * q)) | (uint256(7) << (64 * q + 32)));
                for (uint256 v; v < 64; ++v) {
                    for (uint256 nib; nib < 16; nib += (v % 4 == 0 ? 1 : 5)) {
                        uint256 rand = (noise & clear) | ((v & 7) << (64 * q)) | (nib << (64 * q + 3))
                            | ((v >> 3) << (64 * q + 32));
                        assertEq(h.traits(rand), _refHouse(rand), "house");
                        assertEq(h.ordinaryTraits(rand), _refOrdinary(rand), "ordinary");
                    }
                }
            }
        }
        assertEq(h.traits(0), 0x40404040, "an all-zero seed is four wild symbol-0 lanes");
        assertEq(h.traits(type(uint256).max), _refHouse(type(uint256).max));
    }

    function testFuzzProducersMatchReference(uint256 rand) public view {
        assertEq(h.traits(rand), _refHouse(rand));
        assertEq(h.ordinaryTraits(rand), _refOrdinary(rand));
    }

    function testFuzzTicketMatchesReference(uint256 seed, uint8 symbol) public view {
        symbol = uint8(bound(symbol, 0, 23));
        assertEq(h.ticket(seed, symbol), _refTicket(seed, symbol));
    }

    // ---------------------------------------------------------------------
    // Whole spin: every currency, chosen and random hero
    // ---------------------------------------------------------------------

    function testFuzzSpinMatchesReference(uint256 seed, uint256 houseSeed, uint8 symbol, uint8 currency)
        public
        view
    {
        symbol = uint8(bound(symbol, 0, 24));
        if (symbol == 24) symbol = 32;
        uint8[3] memory currencies = [uint8(0), 1, CURRENCY_WWXRP];
        currency = currencies[bound(currency, 0, 2)];
        (uint32 pt, uint32 rt, uint8 s, uint8 w) = h.spin(seed, houseSeed, symbol, currency);

        uint8 sym = h.hero(seed, symbol);
        uint32 refPt = _refTicket(seed, sym);
        uint32 refRt = _refHouse(houseSeed);
        if (currency == CURRENCY_WWXRP) {
            refRt = h.rig(refPt, refRt, sym >> 3, EntropyLib.hash2(seed, WWXRP_RIG_SALT));
        }
        (uint8 refS, uint8 refW) = _refScore(refPt, refRt);
        assertEq(pt, refPt, "player traits");
        assertEq(rt, refRt, "result traits");
        assertEq(s, refS, "score");
        assertEq(w, refW, "wilds");
    }
}
