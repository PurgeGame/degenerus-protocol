// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/// @dev Data source interface for deity boon state from the game contract.
interface IDeityBoonDataSource {
    /// @notice Get the raw boon state for a deity holder.
    /// @param deity Address of the deity pass holder.
    /// @return dailySeed VRF-derived daily entropy seed for boon selection.
    /// @return day Current day index.
    /// @return usedMask Bitmask of boon slots already consumed today.
    /// @return decimatorOpen Whether decimator boons are available this level.
    /// @return deityPassAvailable Whether deity pass boons are eligible.
    function deityBoonData(address deity) external view returns (
        uint256 dailySeed,
        uint24 day,
        uint8 usedMask,
        bool decimatorOpen,
        bool deityPassAvailable
    );
}

/// @title DeityBoonViewer
/// @notice Standalone view contract for computing deity boon slot types.
///         Reads raw state from DegenerusGame.deityBoonData() and applies the
///         weighted random selection logic to determine boon types per slot.
contract DeityBoonViewer {

    uint8 private constant DEITY_DAILY_BOON_COUNT = 3;

    // Boon type IDs
    uint8 private constant DEITY_BOON_COINFLIP_5 = 1;
    uint8 private constant DEITY_BOON_COINFLIP_10 = 2;
    uint8 private constant DEITY_BOON_COINFLIP_25 = 3;
    uint8 private constant DEITY_BOON_QUEST_SHIELD = 4;
    uint8 private constant DEITY_BOON_LOOTBOX_5 = 5;
    uint8 private constant DEITY_BOON_LOOTBOX_15 = 6;
    uint8 private constant DEITY_BOON_PURCHASE_5 = 7;
    uint8 private constant DEITY_BOON_PURCHASE_15 = 8;
    uint8 private constant DEITY_BOON_PURCHASE_25 = 9;
    uint8 private constant DEITY_BOON_DECIMATOR_10 = 13;
    uint8 private constant DEITY_BOON_DECIMATOR_25 = 14;
    uint8 private constant DEITY_BOON_DECIMATOR_50 = 15;
    uint8 private constant DEITY_BOON_WHALE_10 = 16;
    uint8 private constant DEITY_BOON_ACTIVITY_10 = 17;
    uint8 private constant DEITY_BOON_ACTIVITY_25 = 18;
    uint8 private constant DEITY_BOON_ACTIVITY_50 = 19;
    uint8 private constant DEITY_BOON_LOOTBOX_25 = 22;
    uint8 private constant DEITY_BOON_WHALE_20 = 23;
    uint8 private constant DEITY_BOON_WHALE_35 = 24;
    uint8 private constant DEITY_BOON_DEITY_PASS_10 = 25;
    uint8 private constant DEITY_BOON_DEITY_PASS_20 = 26;
    uint8 private constant DEITY_BOON_DEITY_PASS_35 = 27;
    uint8 private constant DEITY_BOON_WHALE_PASS = 28;
    uint8 private constant DEITY_BOON_LAZY_PASS_10 = 29;
    uint8 private constant DEITY_BOON_LAZY_PASS_25 = 30;
    uint8 private constant DEITY_BOON_LAZY_PASS_50 = 31;
    uint8 private constant DEITY_BOON_DEGEN_ETH_4 = 32;
    uint8 private constant DEITY_BOON_DEGEN_ETH_8 = 33;
    uint8 private constant DEITY_BOON_DEGEN_ETH_12 = 34;
    uint8 private constant DEITY_BOON_DEGEN_FLIP_4 = 35;
    uint8 private constant DEITY_BOON_DEGEN_FLIP_8 = 36;
    uint8 private constant DEITY_BOON_DEGEN_FLIP_12 = 37;
    uint8 private constant DEITY_BOON_DEGEN_WWXRP_4 = 38;
    uint8 private constant DEITY_BOON_DEGEN_WWXRP_8 = 39;
    uint8 private constant DEITY_BOON_DEGEN_WWXRP_12 = 40;
    uint8 private constant DEITY_BOON_CRAPS_5 = 41;
    uint8 private constant DEITY_BOON_CRAPS_10 = 42;
    uint8 private constant DEITY_BOON_CRAPS_15 = 43;

    // Boon weights
    uint16 private constant W_COINFLIP_5 = 200;
    uint16 private constant W_COINFLIP_10 = 40;
    uint16 private constant W_COINFLIP_25 = 8;
    uint16 private constant W_LOOTBOX_5 = 200;
    uint16 private constant W_LOOTBOX_15 = 30;
    uint16 private constant W_LOOTBOX_25 = 8;
    uint16 private constant W_PURCHASE_5 = 400;
    uint16 private constant W_PURCHASE_15 = 80;
    uint16 private constant W_PURCHASE_25 = 16;
    uint16 private constant W_DECIMATOR_10 = 40;
    uint16 private constant W_DECIMATOR_25 = 8;
    uint16 private constant W_DECIMATOR_50 = 2;
    uint16 private constant W_WHALE_10 = 28;
    uint16 private constant W_WHALE_20 = 10;
    uint16 private constant W_WHALE_35 = 2;
    uint16 private constant W_DEITY_PASS_10 = 28;
    uint16 private constant W_DEITY_PASS_20 = 10;
    uint16 private constant W_DEITY_PASS_35 = 2;
    uint16 private constant W_ACTIVITY_10 = 100;
    uint16 private constant W_ACTIVITY_25 = 30;
    uint16 private constant W_ACTIVITY_50 = 4;
    uint16 private constant W_QUEST_SHIELD = 200;
    uint16 private constant W_WHALE_PASS = 2;
    uint16 private constant W_LAZY_PASS_10 = 30;
    uint16 private constant W_LAZY_PASS_25 = 8;
    uint16 private constant W_LAZY_PASS_50 = 2;
    uint16 private constant W_DEGEN_ETH_4 = 200;
    uint16 private constant W_DEGEN_ETH_8 = 50;
    uint16 private constant W_DEGEN_ETH_12 = 10;
    uint16 private constant W_DEGEN_FLIP_4 = 200;
    uint16 private constant W_DEGEN_FLIP_8 = 50;
    uint16 private constant W_DEGEN_FLIP_12 = 10;
    uint16 private constant W_DEGEN_WWXRP_4 = 200;
    uint16 private constant W_DEGEN_WWXRP_8 = 200;
    uint16 private constant W_DEGEN_WWXRP_12 = 200;
    uint16 private constant W_CRAPS_5 = 200;
    uint16 private constant W_CRAPS_10 = 40;
    uint16 private constant W_CRAPS_15 = 8;
    uint16 private constant W_TOTAL = 2856;
    uint16 private constant W_PRE_DECIMATOR = 982;
    uint16 private constant W_DECIMATOR_ALL = 50;
    uint16 private constant W_PRE_DEITY_PASS = 1072;
    uint16 private constant W_DEITY_PASS_ALL = 40;

    /// @notice Compute deity boon slots for a given deity.
    /// @param game Address of the DegenerusGame contract.
    /// @param deity The deity address to query.
    /// @return slots Array of 3 boon type IDs for today's slots.
    /// @return usedMask Bitmask of slots already used today.
    /// @return day Current day index.
    function deityBoonSlots(
        address game,
        address deity
    ) external view returns (uint8[3] memory slots, uint8 usedMask, uint24 day) {
        (
            uint256 dailySeed,
            uint24 d,
            uint8 mask,
            ,

        ) = IDeityBoonDataSource(game).deityBoonData(deity);

        day = d;
        usedMask = mask;

        // No seed yet (today's VRF word hasn't landed): return no boons rather
        // than a fabricated menu that won't match the real ones.
        if (dailySeed == 0) return (slots, usedMask, day);

        // Static modulus + static mapping — mirrors LootboxModule._deityBoonForSlot: the
        // menu is fixed the moment the word lands and never remaps with eligibility.
        // Decimator and deity-pass tiers are excluded unconditionally (those families are
        // lootbox-only, so a gift slot never arrives dead): the reduced roll skips both
        // bands, and every menu slot is always issuable.
        for (uint8 i = 0; i < DEITY_DAILY_BOON_COUNT; ) {
            uint256 seed = uint256(keccak256(abi.encode(dailySeed, deity, d, i)));
            uint256 roll = seed % (W_TOTAL - W_DECIMATOR_ALL - W_DEITY_PASS_ALL);
            if (roll >= W_PRE_DECIMATOR) roll += W_DECIMATOR_ALL;
            if (roll >= W_PRE_DEITY_PASS) roll += W_DEITY_PASS_ALL;
            slots[i] = _boonFromRoll(roll);
            unchecked { ++i; }
        }
    }

    /// @dev Map a weighted random roll to a boon type ID over the static full table.
    /// @param roll Random value in [0, W_TOTAL).
    /// @return Boon type ID constant.
    function _boonFromRoll(uint256 roll) internal pure returns (uint8) {
        uint256 cursor = 0;
        cursor += W_COINFLIP_5;
        if (roll < cursor) return DEITY_BOON_COINFLIP_5;
        cursor += W_COINFLIP_10;
        if (roll < cursor) return DEITY_BOON_COINFLIP_10;
        cursor += W_COINFLIP_25;
        if (roll < cursor) return DEITY_BOON_COINFLIP_25;
        cursor += W_LOOTBOX_5;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_5;
        cursor += W_LOOTBOX_15;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_15;
        cursor += W_LOOTBOX_25;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_25;
        cursor += W_PURCHASE_5;
        if (roll < cursor) return DEITY_BOON_PURCHASE_5;
        cursor += W_PURCHASE_15;
        if (roll < cursor) return DEITY_BOON_PURCHASE_15;
        cursor += W_PURCHASE_25;
        if (roll < cursor) return DEITY_BOON_PURCHASE_25;
        cursor += W_DECIMATOR_10;
        if (roll < cursor) return DEITY_BOON_DECIMATOR_10;
        cursor += W_DECIMATOR_25;
        if (roll < cursor) return DEITY_BOON_DECIMATOR_25;
        cursor += W_DECIMATOR_50;
        if (roll < cursor) return DEITY_BOON_DECIMATOR_50;
        cursor += W_WHALE_10;
        if (roll < cursor) return DEITY_BOON_WHALE_10;
        cursor += W_WHALE_20;
        if (roll < cursor) return DEITY_BOON_WHALE_20;
        cursor += W_WHALE_35;
        if (roll < cursor) return DEITY_BOON_WHALE_35;
        cursor += W_DEITY_PASS_10;
        if (roll < cursor) return DEITY_BOON_DEITY_PASS_10;
        cursor += W_DEITY_PASS_20;
        if (roll < cursor) return DEITY_BOON_DEITY_PASS_20;
        cursor += W_DEITY_PASS_35;
        if (roll < cursor) return DEITY_BOON_DEITY_PASS_35;
        cursor += W_ACTIVITY_10;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_10;
        cursor += W_ACTIVITY_25;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_25;
        cursor += W_ACTIVITY_50;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_50;
        cursor += W_QUEST_SHIELD;
        if (roll < cursor) return DEITY_BOON_QUEST_SHIELD;
        cursor += W_WHALE_PASS;
        if (roll < cursor) return DEITY_BOON_WHALE_PASS;
        cursor += W_LAZY_PASS_10;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_10;
        cursor += W_LAZY_PASS_25;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_25;
        cursor += W_LAZY_PASS_50;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_50;
        cursor += W_DEGEN_ETH_4;
        if (roll < cursor) return DEITY_BOON_DEGEN_ETH_4;
        cursor += W_DEGEN_ETH_8;
        if (roll < cursor) return DEITY_BOON_DEGEN_ETH_8;
        cursor += W_DEGEN_ETH_12;
        if (roll < cursor) return DEITY_BOON_DEGEN_ETH_12;
        cursor += W_DEGEN_FLIP_4;
        if (roll < cursor) return DEITY_BOON_DEGEN_FLIP_4;
        cursor += W_DEGEN_FLIP_8;
        if (roll < cursor) return DEITY_BOON_DEGEN_FLIP_8;
        cursor += W_DEGEN_FLIP_12;
        if (roll < cursor) return DEITY_BOON_DEGEN_FLIP_12;
        cursor += W_DEGEN_WWXRP_4;
        if (roll < cursor) return DEITY_BOON_DEGEN_WWXRP_4;
        cursor += W_DEGEN_WWXRP_8;
        if (roll < cursor) return DEITY_BOON_DEGEN_WWXRP_8;
        cursor += W_DEGEN_WWXRP_12;
        if (roll < cursor) return DEITY_BOON_DEGEN_WWXRP_12;
        cursor += W_CRAPS_5;
        if (roll < cursor) return DEITY_BOON_CRAPS_5;
        cursor += W_CRAPS_10;
        if (roll < cursor) return DEITY_BOON_CRAPS_10;
        return DEITY_BOON_CRAPS_15;
    }
}
