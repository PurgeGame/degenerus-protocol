// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

error BadBattleTerms();

/// @dev Shared custom-table bounds and packing. Storage-free; only CrapsEngine deploys
///      the validation code, while CrapsBattle uses the same constants to decode terms.
abstract contract CrapsCustomTerms {
    /// @notice Granularity of battle stakes, seeds and tier boosts.
    uint256 internal constant _BATTLE_STAKE_UNIT = 100 ether;
    /// @notice Chips in every round. An entrant places zero through seven; the draw scatters the rest.
    uint256 internal constant _BONUS_CHIPS = 10;
    /// @dev Ceiling imposed by the scoreboard's 18-bit stake field.
    uint256 internal constant _BSTAKE_MAX = 0x3FFFF;
    uint256 internal constant _CB_BANK_SHIFT = 28;
    uint256 internal constant _CB_CLOSE_SHIFT = 73;
    uint256 internal constant _CB_GOAL_SHIFT = 33;
    /// @dev A custom battle's high-roller multiple, bits 114..122: literal 0..256, where 0 is a
    ///      battle with no high lane and 1 is not a multiple at all.
    uint256 internal constant _CB_HIGH_SHIFT = 114;
    /// @dev Bit 113 of a custom battle's terms: one address may take as many seats as it pays for.
    uint256 internal constant _CB_MULTI_BIT = 1 << 113;
    uint256 internal constant _CB_STAKE_SHIFT = 43;
    /// @notice Maximum custom-battle bankroll depth, in rounds.
    uint256 internal constant _MAX_BANKROLL_MULT = 25;
    /// @notice Maximum goal, as a multiple of the battle bankroll.
    uint256 internal constant _MAX_GOAL_MULT = 1000;
    /// @notice The ceiling on a CUSTOM battle's high-roller multiple. A creator names any figure
    ///         from two to here, or zero to run the battle without a high lane at all.
    uint256 internal constant _MAX_HIGH_MULT = 256;
    /// @notice The largest round a battle may post. A BLANK ticket leaves all ten chips to the
    ///         dice and they may land on ONE leg, so the whole round has to fit the resolver's
    ///         `uint24` leg — the table maximum `Craps` documents. `_CB_PLAYED_MASK` is only how
    ///         wide the stored field is, and a round between the two would silently truncate the
    ///         board it was paid for.
    uint256 internal constant _MAX_ROUND_FLIP = type(uint24).max;
    /// @notice Minimum bankroll for a custom battle, in whole FLIP.
    uint256 internal constant _MIN_BANKROLL_FLIP = 300;
    /// @notice Minimum goal, as a multiple of the battle bankroll.
    uint256 internal constant _MIN_BATTLE_GOAL_MULT = 5;
    /// @notice A funded custom field cannot hold one of the four admission slots indefinitely.
    uint256 internal constant _MAX_CUSTOM_DURATION = 7 days;

    function _customDefinition(
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) internal view returns (uint256 terms) {
        // THE WHOLE DEFINITION, vetted in one pass. A round is ten whole chips or it is not a
        // round; the bankroll runs a bounded number of them; the goal sits in its band; the bounty
        // fits the scoreboard's granule field; the close time is valid; and a high
        // lane is either absent or a real multiple — zero runs no lane, while one is the ordinary
        // seat under another name and would make the two entry modes indistinguishable.
        bool durationTooLong;
        unchecked { durationTooLong = uint256(closeTime) - block.timestamp > _MAX_CUSTOM_DURATION; }
        if (
            played == 0 || played % _BONUS_CHIPS != 0 || played > _MAX_ROUND_FLIP || bankMult == 0
                || bankMult > _MAX_BANKROLL_MULT || goalMult < _MIN_BATTLE_GOAL_MULT || goalMult > _MAX_GOAL_MULT
                || stakeUnits > _BSTAKE_MAX || closeTime <= block.timestamp
                || durationTooLong
                || highRollerMult == 1 || highRollerMult > _MAX_HIGH_MULT
        ) revert BadBattleTerms();
        unchecked {
            uint256 bankroll = uint256(played) * bankMult;
            // The table's entry floor, and the bounty ceiling: a bounty rides alongside the
            // bankroll and may never exceed it. Zero is legal and leaves an empty pot to race for.
            if (bankroll < _MIN_BANKROLL_FLIP || uint256(stakeUnits) * (_BATTLE_STAKE_UNIT / 1 ether) > bankroll) {
                revert BadBattleTerms();
            }
            terms = uint256(played) | (uint256(bankMult) << _CB_BANK_SHIFT) | (uint256(goalMult) << _CB_GOAL_SHIFT)
                | (uint256(stakeUnits) << _CB_STAKE_SHIFT)
                | (uint256(closeTime) << _CB_CLOSE_SHIFT) | (multiEntry ? _CB_MULTI_BIT : 0)
                | (uint256(highRollerMult) << _CB_HIGH_SHIFT);
        }
    }
}
