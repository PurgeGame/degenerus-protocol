// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "../../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../../contracts/libraries/FlipRoundLib.sol";
import {CrapsPriceLib} from "../../../contracts/libraries/CrapsPriceLib.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";

/// @title DegenesisReference -- spec model of one Degenesis order's outcome (spec §3-§5)
/// @notice Written from docs/GENESIS-BOX-DESIGN.md, not from the module: the category split
///         (50/40/10), the FLIP ladder scaled by base(day)/2 x earlyBonus x K/(K+V) and converted
///         at the level-1 price, the 100-FLIP collapse and pass denomination, and the sDGNRS award
///         x * Q * [5000, 15000] / (V * 10_000). The draw extractors are the module's
///         domain-separated hashes. Stateful suites compare each DegenesisOrderResolved with it.
library DegenesisReference {
    uint256 internal constant UNIT = 0.0001 ether;
    uint256 internal constant AMOUNT_MASK = (uint256(1) << 38) - 1;
    uint256 internal constant LANE_MASK = (uint256(1) << 85) - 1;
    uint256 internal constant T_EARLY = 20_000_000_000 * 1e12;
    uint256 internal constant T_LATE = 10_000_000_000 * 1e12;
    uint256 internal constant K_UNITS = 460_000;
    uint256 internal constant BONUS_WINDOW = 6 hours;
    uint256 internal constant LOW_BASE = 14_098;
    uint256 internal constant LOW_STEP = 1158;
    uint256 internal constant HIGH_BASE = 74_534;
    uint256 internal constant HIGH_STEP = 22_890;
    uint256 internal constant MAX_LADDER_BPS = HIGH_BASE + 3 * HIGH_STEP;
    uint256 internal constant HIGH_PASS_CAP = 12;
    uint256 internal constant PRICE_COIN_UNIT = 1000;
    uint256 internal constant ORDER_DOMAIN = 0x446567656e657369734f72646572;
    uint256 internal constant CATEGORY_TAG = 0x44656743617465676f7279;
    uint256 internal constant SIZE_TAG = 0x44656753697a65;
    uint256 internal constant PASS_TAG = 0x5061737353696465;
    uint256 internal constant FLIP_ROUND_TAG = 0x466c6970526f756e64;
    uint256 internal constant BOX_PASS_ROUND_TAG = 0x50617373526f756e64;

    struct Outcome {
        uint32 id;
        uint256 amount;
        uint256 flip;
        uint256 dgnrs;
        uint256 wwxrp;
        uint32 normalPasses;
        uint32 highPasses;
    }

    function target(uint256 c) internal pure returns (uint256) {
        return c <= 3 ? T_EARLY : T_LATE;
    }

    /// @dev Q = min(floor(2.5T), floor(R * 2 / 3)).
    function q(uint256 c, uint256 pool) internal pure returns (uint256 out) {
        out = target(c) * 5 / 2;
        uint256 cap = pool * 2 / 3;
        if (cap < out) out = cap;
    }

    /// @dev Unrounded FLIP: ladder bps x (2.5 - 0.125(day-1))/2 x (1 + 0.05(1 - s/6h)) x K/(K+V),
    ///      at PRICE_COIN_UNIT FLIP per level-1 ticket price.
    function flipRaw(uint256 units, uint256 flipBps, uint256 day, uint256 secs, uint256 volumeUnits)
        internal
        pure
        returns (uint256)
    {
        uint256 s = secs > BONUS_WINDOW ? BONUS_WINDOW : secs;
        return (units * UNIT * PRICE_COIN_UNIT * flipBps * (21 - day) * (453_600 - s) * K_UNITS)
            / (uint256(10_000) * 16 * 432_000 * (K_UNITS + volumeUnits) * PriceLookupLib.priceForLevel(1));
    }

    function ladderBps(uint256 size) internal pure returns (uint256) {
        uint256 roll = size % 20;
        return roll < 16 ? LOW_BASE + roll * LOW_STEP : HIGH_BASE + (roll - 16) * HIGH_STEP;
    }

    /// @dev FLIP value of an outcome: coin credit plus passes at their pass units.
    function flipValue(uint256 flip, uint256 normalPasses, uint256 highPasses) internal pure returns (uint256) {
        return flip + normalPasses * CrapsPriceLib.NORMAL_VALUE + highPasses * CrapsPriceLib.HIGH_VALUE;
    }

    /// @dev Ceiling on one order's FLIP value: the top ladder rung with the full early bonus, plus
    ///      one collapse step and one Bernoulli pass round-up.
    function orderFlipValueCeiling(uint256 units, uint256 day, uint256 volumeUnits) internal pure returns (uint256) {
        return flipRaw(units, MAX_LADDER_BPS, day, 0, volumeUnits) + FlipRoundLib.FLIP_ROUND_UNIT
            + CrapsPriceLib.HIGH_VALUE;
    }

    function outcome(uint256 word, uint256 day, uint256 index, uint256 lane, uint256 volumeUnits, uint256 qBudget)
        internal
        pure
        returns (Outcome memory o)
    {
        o.id = uint32(lane);
        uint256 units = (lane >> 32) & AMOUNT_MASK;
        uint256 secs = (lane & LANE_MASK) >> 70;
        o.amount = units * UNIT;
        uint256 seed = EntropyLib.hash4(ORDER_DOMAIN, word, (day << 32) | index, o.id);
        uint256 cat = EntropyLib.hash2(seed, CATEGORY_TAG) % 100;
        uint256 size = EntropyLib.hash2(seed, SIZE_TAG);
        if (cat < 50) {
            uint256 flipOut = flipRaw(units, ladderBps(size), day, secs, volumeUnits);
            if (flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD) {
                flipOut = FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(seed, FLIP_ROUND_TAG));
            }
            if (flipOut == 0) {
                o.wwxrp = 1;
            } else if (EntropyLib.hash2(seed, PASS_TAG) & 1 == 1) {
                bool highPass = flipOut > CrapsPriceLib.HIGH_SWITCH;
                uint256 passUnit = highPass ? CrapsPriceLib.HIGH_VALUE : CrapsPriceLib.NORMAL_VALUE;
                uint256 passCount = flipOut / passUnit;
                uint256 rest;
                if (highPass && passCount >= HIGH_PASS_CAP) {
                    passCount = HIGH_PASS_CAP;
                    rest = flipOut - HIGH_PASS_CAP * CrapsPriceLib.HIGH_VALUE;
                } else {
                    uint256 rem = flipOut % passUnit;
                    if (rem != 0 && EntropyLib.hash2(seed, BOX_PASS_ROUND_TAG) % passUnit < rem) ++passCount;
                }
                flipOut = rest;
                if (passCount == 0) o.wwxrp = 1;
                else if (highPass) o.highPasses = uint32(passCount);
                else o.normalPasses = uint32(passCount);
            }
            o.flip = flipOut;
        } else if (cat < 90) {
            o.dgnrs = (units * qBudget * (5000 + size % 10_001)) / (volumeUnits * 10_000);
            if (o.dgnrs == 0) o.wwxrp = 1;
        } else {
            o.wwxrp = 1;
        }
    }
}
