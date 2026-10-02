// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";
import {CrapsCustomTerms} from "./CrapsCustomTerms.sol";

/// @title CrapsEngine
/// @notice The table's stateless computations: custom-definition validation and two pure
///         dice entry points. The table uses `settleRanked` to resolve runs.
/// @dev Holds no storage, takes no constructor arguments, has no owner and no upgrade path.
///      `CrapsBattle` reaches it by STATICCALL at the pinned `ContractAddresses.CRAPS_ENGINE`,
///      which is what keeps the table itself under the EIP-170 ceiling: the engine's whole
///      closure — board, scatter, shooter loop — compiles here and nowhere else. Anyone may call
///      it; it can only compute. Custom validation also reads the close-time deadline against the clock.
contract CrapsEngine is Craps, CrapsCustomTerms {
    /// @notice Validate and pack a custom table's immutable definition.
    function customDefinition(uint32 played, uint8 bankMult, uint16 goalMult, uint24 stakeUnits, uint40 closeTime, bool multiEntry, uint16 highRollerMult) external view returns (uint256)
    {
        return _customDefinition(played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult);
    }

    /// @notice Play one slip to its stop.
    /// @param packedChips  The slip's named chips, ten three-bit legs, the dark side last.
    /// @param chipFlip     Whole FLIP per chip at this slot.
    /// @param scatterHash  The owner-keyed draw that throws the unnamed chips.
    /// @param scatterCount How many of the ten chips the dice place.
    /// @param seed         The window's shooter seed.
    /// @param bankroll     The bankroll the run starts on, in wei.
    /// @param goal         The bankroll that latches a Goal, in wei.
    /// @param player       The slip's owner, who seasons the survival coin.
    /// @param boost        The shooter-boost terms, zero for a custom battle.
    /// @return r The run: bankroll in and out, its peak, hands, units, rolls and the stop.
    function settleSlip(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) external pure returns (SlipResult memory r) {
        r = _play(packedChips, chipFlip, scatterHash, scatterCount, seed, bankroll, goal, player, boost);
    }

    /// @notice `settleSlip` with no goal, under the caller's shooter cap and roll budget. The
    ///         Decimator bounds its runs this way. Both are clamped to the engine's own limits.
    /// @param bounds The shooter cap in the low 16 bits and the roll budget above them. A budget
    ///        under `_MAX_ROLLS` is exact: the run stops at that many rolls, and chips still on
    ///        the table in the cut hand count at face value when the high point is sampled.
    function settleSlipBounded(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        address player,
        uint256 boost,
        uint256 bounds
    ) external pure returns (SlipResult memory r) {
        uint256 cap = bounds & 0xFFFF;
        uint256 rollBudget = bounds >> 16;
        if (cap > _MAX_SLIP_HANDS) cap = _MAX_SLIP_HANDS;
        if (rollBudget > _SLIP_ROLL_BUDGET) rollBudget = _SLIP_ROLL_BUDGET;
        Bets memory board = _boardFrom(packedChips, chipFlip);
        _scatterInto(board, scatterHash, chipFlip, scatterCount);
        r = _settleSlip(board, seed, bankroll, 0, cap, rollBudget, player, boost);
    }

    /// @notice `settleSlip` with the table's MERIT COMPOSITE (`_rankOf`) in the fifth word, in
    ///         place of the escalated units the table never reads. What `CrapsBattle` calls: the
    ///         comparator runs here, beside the dice, instead of in the table's bytecode.
    /// @dev Same parameters and the same run as `settleSlip`; only `unitsPlayed` differs.
    function settleRanked(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) external pure returns (SlipResult memory r) {
        r = _play(packedChips, chipFlip, scatterHash, scatterCount, seed, bankroll, goal, player, boost);
        r.unitsPlayed = _rankOf(r);
    }

    /// @notice Full normal battle settlement, shared by paid and awarded entries.
    /// @dev bankrollIn becomes the rounded payment; unitsPlayed becomes the unscaled merit rank.
    ///      Every seat of a field throws the same dice. An awarded entry keys its board scatter,
    ///      survival coin to its own bet id rather than its wallet, so repeat
    ///      awards to one wallet stay separate runs. Every field uses the shared 600-roll
    ///      between-shooter budget and 1,111-roll absolute ceiling.
    function settleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll,
        uint256 goal, uint48 bound, uint256 field, uint256 word) external pure returns (SlipResult memory r)
    {
        uint256 key = header >> 224 == 0
            ? uint160(header)
            : uint160(_hash3(word, 0x4a61636b706f7441776172646564, betId));
        uint256 chips = (header >> 160) & 0x3fffffff;
        uint256 placed;
        for (uint256 i; i < 30; i += 3) placed += (chips >> i) & 7;
        bytes32 seed = bytes32(_hash3(uint256(keccak256("degenerus.lootbox.craps.v1")), word, bound));
        uint256 boost;
        if (bound < 1 << 40) {
            boost = _shooterBoostTerms(placed);
            uint256 n = field >> 64;
            if (n != 0) {
                uint256 seat = uint64(field);
                if (seat == 0) seat = uint64(betId);
                uint256 offset = (seat + n - 1 - (_hash2(ROTATING_SHOOTER_TAG, uint256(seed)) % n)) % n;
                if (offset < _MAX_SLIP_HANDS) boost |= (offset + 1) << _BOOST_TURN_SHIFT;
            }
        }
        r = _play(chips, chipFlip, _hash3(word, 0x437261707353636174746572, key),
            10 - placed, seed, bankroll, goal, address(uint160(key)), boost);
        r.unitsPlayed = _rankOf(r);
        uint256 paid = r.stop == SlipStop.Bust ? 0 : r.bankrollOut;
        r.bankrollIn = paid > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(paid, _hash3(word, 0x4372617073526f756e64, betId))
            : FlipRoundLib.floorWholeFlip(paid);
    }

    function _play(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) private pure returns (SlipResult memory r) {
        Bets memory board = _boardFrom(packedChips, chipFlip);
        _scatterInto(board, scatterHash, chipFlip, scatterCount);
        r = _settleSlip(board, seed, bankroll, goal, _MAX_SLIP_HANDS, _SLIP_ROLL_BUDGET, player, boost);
    }
}
