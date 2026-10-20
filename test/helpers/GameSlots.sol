// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title GameSlots
/// @notice DegenerusGame storage roots for tests that address Game storage by slot number
///         (`vm.load` / `vm.store` / raw `sload`). One constant per declared variable, named after
///         it; `*_OFFSET` is the byte offset of a variable packed into a shared slot.
/// @dev `test/fuzz/StorageSlotPins.t.sol` asserts every constant here against the compiled
///      `.slot` / `.offset` of its variable. When the layout moves, update the numbers here and
///      that test tells you which ones are wrong. Never derive a slot by arithmetic on another.
library GameSlots {
    uint256 internal constant PURCHASE_START_DAY = 0;
    uint256 internal constant DAILY_IDX = 0;
    uint256 internal constant DAILY_IDX_OFFSET = 3;
    uint256 internal constant RNG_REQUEST_TIME = 0;
    uint256 internal constant RNG_REQUEST_TIME_OFFSET = 6;
    uint256 internal constant LEVEL = 0;
    uint256 internal constant LEVEL_OFFSET = 12;
    uint256 internal constant JACKPOT_PHASE_FLAG = 0;
    uint256 internal constant JACKPOT_PHASE_FLAG_OFFSET = 15;
    uint256 internal constant JACKPOT_COUNTER = 0;
    uint256 internal constant JACKPOT_COUNTER_OFFSET = 16;
    uint256 internal constant LAST_PURCHASE_DAY = 0;
    uint256 internal constant LAST_PURCHASE_DAY_OFFSET = 17;
    uint256 internal constant DECIMATOR_FLAGS = 0;
    uint256 internal constant DECIMATOR_FLAGS_OFFSET = 18;
    uint256 internal constant RNG_LOCKED_FLAG = 0;
    uint256 internal constant RNG_LOCKED_FLAG_OFFSET = 19;
    uint256 internal constant PHASE_TRANSITION_ACTIVE = 0;
    uint256 internal constant PHASE_TRANSITION_ACTIVE_OFFSET = 20;
    uint256 internal constant GAME_OVER = 0;
    uint256 internal constant GAME_OVER_OFFSET = 21;
    uint256 internal constant DAILY_JACKPOT_COIN_TICKETS_PENDING = 0;
    uint256 internal constant DAILY_JACKPOT_COIN_TICKETS_PENDING_OFFSET = 22;
    uint256 internal constant JACKPOT_FLAGS = 0;
    uint256 internal constant JACKPOT_FLAGS_OFFSET = 23;
    uint256 internal constant TICKETS_FULLY_PROCESSED = 0;
    uint256 internal constant TICKETS_FULLY_PROCESSED_OFFSET = 24;
    uint256 internal constant TICKET_WRITE_SLOT = 0;
    uint256 internal constant TICKET_WRITE_SLOT_OFFSET = 25;
    uint256 internal constant PRIZE_POOL_FROZEN = 0;
    uint256 internal constant PRIZE_POOL_FROZEN_OFFSET = 26;
    uint256 internal constant DEGENESIS_CLOSED = 0;
    uint256 internal constant DEGENESIS_CLOSED_OFFSET = 27;
    uint256 internal constant SUBS_FULLY_PROCESSED = 0;
    uint256 internal constant SUBS_FULLY_PROCESSED_OFFSET = 28;
    uint256 internal constant HUMAN_READ_COMPLETE = 0;
    uint256 internal constant HUMAN_READ_COMPLETE_OFFSET = 29;
    uint256 internal constant RNG_FLAGS_AND_NUDGES = 0;
    uint256 internal constant RNG_FLAGS_AND_NUDGES_OFFSET = 30;
    uint256 internal constant CURRENT_PRIZE_POOL = 1;
    uint256 internal constant CLAIMABLE_POOL = 1;
    uint256 internal constant CLAIMABLE_POOL_OFFSET = 16;
    uint256 internal constant PRIZE_POOLS_PACKED = 2;
    uint256 internal constant RNG_WORD_CURRENT = 3;
    uint256 internal constant VRF_REQUEST_ID = 4;
    uint256 internal constant RNG_REQUEST_DAY = 5;
    uint256 internal constant RNG_GAP_APPLIED = 5;
    uint256 internal constant RNG_GAP_APPLIED_OFFSET = 3;
    uint256 internal constant LAST_VRF_PROCESSED_TIMESTAMP = 5;
    uint256 internal constant LAST_VRF_PROCESSED_TIMESTAMP_OFFSET = 4;
    uint256 internal constant TICKET_BUFFER_LEVELS = 5;
    uint256 internal constant TICKET_BUFFER_LEVELS_OFFSET = 10;
    uint256 internal constant LOAN_SEIZE_CURSOR = 5;
    uint256 internal constant LOAN_SEIZE_CURSOR_OFFSET = 16;
    uint256 internal constant TRAIT_BUCKET_STALE = 5;
    uint256 internal constant TRAIT_BUCKET_STALE_OFFSET = 23;
    uint256 internal constant DEC_ENTRIES_LEVEL = 5;
    uint256 internal constant DEC_ENTRIES_LEVEL_OFFSET = 24;
    uint256 internal constant FOIL_SLOT_RETAINED = 56;
    uint256 internal constant FOIL_SLOT_RETAINED_OFFSET = 19;
    uint256 internal constant LOANS = 78;
    uint256 internal constant LOANS_DUE = 79;
    uint256 internal constant LOANS_DUE_COUNT = 80;
    uint256 internal constant DAILY_TICKET_BUDGETS_PACKED = 6;
    uint256 internal constant BALANCES_PACKED = 7;
    uint256 internal constant LVL_TRAIT_ENTRY = 8;
    uint256 internal constant MINT_PACKED = 9;
    uint256 internal constant WALLET_IDS = 76;
    uint256 internal constant RNG_WORD_BY_DAY = 10;
    uint256 internal constant PRIZE_POOL_PENDING_PACKED = 11;
    uint256 internal constant TICKET_QUEUE = 12;
    uint256 internal constant WALLETS = 13;
    uint256 internal constant TICKET_CURSOR = 14;
    uint256 internal constant TICKET_LEVEL = 14;
    uint256 internal constant TICKET_LEVEL_OFFSET = 4;
    uint256 internal constant SNAP_SHIFT = 14;
    uint256 internal constant SNAP_SHIFT_OFFSET = 7;
    uint256 internal constant SNAP_LEVEL = 14;
    uint256 internal constant SNAP_LEVEL_OFFSET = 8;
    uint256 internal constant SNAP_PENDING_SHIFT = 14;
    uint256 internal constant SNAP_PENDING_SHIFT_OFFSET = 11;
    uint256 internal constant TICKET_ROUND = 14;
    uint256 internal constant TICKET_ROUND_OFFSET = 12;
    uint256 internal constant TICKET_SOLO_OFFSET = 14;
    uint256 internal constant TICKET_SOLO_OFFSET_OFFSET = 16;
    uint256 internal constant DEGENERETTE_CURSOR = 14;
    uint256 internal constant DEGENERETTE_CURSOR_OFFSET = 20;
    uint256 internal constant DEGENERETTE_READ_COUNT = 14;
    uint256 internal constant DEGENERETTE_READ_COUNT_OFFSET = 26;
    uint256 internal constant DEGENESIS_VAULT_BUDGET = 15;
    uint256 internal constant DEGENESIS_CREDIT = 16;
    uint256 internal constant GAME_OVER_STATE_PACKED = 17;
    uint256 internal constant DEGENERETTE_QUEUE = 18;
    uint256 internal constant OPERATOR_APPROVALS = 19;
    uint256 internal constant LEVEL_PRIZE_POOL = 20;
    uint256 internal constant PLAYER_CLAIM_WORD = 21;
    uint256 internal constant LEVEL_DGNRS_PACKED = 22;
    uint256 internal constant DEITY_PASS_PRICE_PAID = 23;
    uint256 internal constant DEITY_PASS_IDS = 24;
    uint256 internal constant DEITY_BY_SYMBOL = 25;
    uint256 internal constant DEGENESIS_ACTIVE = 26;
    uint256 internal constant VRF_COORDINATOR = 27;
    uint256 internal constant VRF_KEY_HASH = 28;
    uint256 internal constant VRF_SUBSCRIPTION_ID = 29;
    uint256 internal constant LOOTBOX_RNG_PACKED = 30;
    uint256 internal constant RNG_DAY_TAGS = 31;
    uint256 internal constant DEITY_BOON_PACKED = 32;
    uint256 internal constant DEITY_BOON_RECIPIENT_DAY = 33;
    uint256 internal constant DEGENERETTE_RECORD_BOUNTY = 34;
    uint256 internal constant EARLY_TICKET_LEVEL = 35;
    uint256 internal constant LOOTBOX_EV_CAP_PACKED = 36;
    uint256 internal constant DEC_BATTLE_ENTRIES = 37;
    uint256 internal constant DEC_BATTLE_ROUNDS = 38;
    uint256 internal constant DEC_BATTLE_HEAP = 39;
    uint256 internal constant DEC_BATTLE_PLAYERS = 40;
    uint256 internal constant DAILY_HERO_WAGERS = 41;
    uint256 internal constant YIELD_ACCUMULATOR = 42;
    uint256 internal constant CENTURY_BONUS_USED = 43;
    uint256 internal constant DEITY_PASS_SALES = 44;
    uint256 internal constant PROTOCOL_BOON_POOLS = 45;
    uint256 internal constant PROTOCOL_BOON_ENTRIES = 46;
    uint256 internal constant BOON_PACKED = 47;
    uint256 internal constant SUB_META = 48;
    uint256 internal constant SUBSCRIBERS = 49;
    uint256 internal constant SUB_CURSOR = 50;
    uint256 internal constant SUB_OPEN_CURSOR = 50;
    uint256 internal constant SUB_OPEN_CURSOR_OFFSET = 2;
    uint256 internal constant AFKING_RESET_DAY = 50;
    uint256 internal constant AFKING_RESET_DAY_OFFSET = 4;
    uint256 internal constant BOX_CURSOR = 50;
    uint256 internal constant BOX_CURSOR_OFFSET = 7;
    uint256 internal constant BOX_READ_COUNT = 50;
    uint256 internal constant BOX_READ_COUNT_OFFSET = 13;
    uint256 internal constant SDGNRS_BONUS_LEVEL = 50;
    uint256 internal constant SDGNRS_BONUS_LEVEL_OFFSET = 17;
    uint256 internal constant PENDING_BOX_COUNT = 50;
    uint256 internal constant PENDING_BOX_COUNT_OFFSET = 20;
    uint256 internal constant SUB_BOX_COUNT = 50;
    uint256 internal constant SUB_BOX_COUNT_OFFSET = 22;
    uint256 internal constant AFKING_COHORT_PRICE_MILLI = 50;
    uint256 internal constant AFKING_COHORT_PRICE_MILLI_OFFSET = 24;
    uint256 internal constant AFKING_PROTOCOL_FLAGS = 50;
    uint256 internal constant AFKING_PROTOCOL_FLAGS_OFFSET = 26;
    uint256 internal constant AFKING_ENDPOINT_DAY = 50;
    uint256 internal constant AFKING_ENDPOINT_DAY_OFFSET = 27;
    uint256 internal constant BOX_QUEUE = 51;
    uint256 internal constant FOIL_RECORD = 52;
    uint256 internal constant FOIL_MATCH_CLAIMED = 53;
    uint256 internal constant DAILY_FOIL_DRAW = 54;
    uint256 internal constant FOIL_QUEUE = 55;
    uint256 internal constant FOIL_CURSOR = 56;
    uint256 internal constant FOIL_GENERATION_DAY = 56;
    uint256 internal constant FOIL_GENERATION_DAY_OFFSET = 4;
    uint256 internal constant FOIL_FIRST_DRAW_DAY = 56;
    uint256 internal constant FOIL_FIRST_DRAW_DAY_OFFSET = 7;
    uint256 internal constant FOIL_WRITE_SLOT = 56;
    uint256 internal constant FOIL_WRITE_SLOT_OFFSET = 10;
    uint256 internal constant FOIL_WRITE_COUNT = 56;
    uint256 internal constant FOIL_WRITE_COUNT_OFFSET = 11;
    uint256 internal constant FOIL_READ_COUNT = 56;
    uint256 internal constant FOIL_READ_COUNT_OFFSET = 15;
    uint256 internal constant DEITY_RECIPIENT_BOON_COUNT = 57;
    uint256 internal constant GOLDEN_TICKET = 58;
    uint256 internal constant MIDDAY_RNG_CREDIT = 59;
    uint256 internal constant CENTURY_PRIZE_POOLS = 60;
    uint256 internal constant TICKET_SEATS = 61;
    uint256 internal constant TICKET_GENERATION_START_BLOCK = 62;
    uint256 internal constant DEAD_TALLY_POS = 63;
    uint256 internal constant DEAD_TALLY_FOIL_DAY = 63;
    uint256 internal constant DEAD_TALLY_FOIL_DAY_OFFSET = 4;
    uint256 internal constant DEAD_TALLY_FOIL_IDX = 63;
    uint256 internal constant DEAD_TALLY_FOIL_IDX_OFFSET = 7;
    uint256 internal constant DEAD_TALLY_STAGE = 63;
    uint256 internal constant DEAD_TALLY_STAGE_OFFSET = 11;
    uint256 internal constant DEAD_TRAIT_COUNT = 63;
    uint256 internal constant DEAD_TRAIT_COUNT_OFFSET = 12;
    uint256 internal constant DEAD_UNCREATED = 63;
    uint256 internal constant DEAD_UNCREATED_OFFSET = 14;
    uint256 internal constant DEAD_CREATED = 63;
    uint256 internal constant DEAD_CREATED_OFFSET = 22;
    uint256 internal constant DEAD_POT = 64;
    uint256 internal constant DEAD_TOTAL = 64;
    uint256 internal constant DEAD_TOTAL_OFFSET = 16;
    uint256 internal constant DEAD_UNCREATED_LEFT = 64;
    uint256 internal constant DEAD_UNCREATED_LEFT_OFFSET = 24;
    uint256 internal constant DEAD_CLAIMED = 65;
    uint256 internal constant DEC_BATTLE_QUEUE = 66;
    uint256 internal constant TRAIT_BUCKET_LIVE = 67;
    uint256 internal constant TICKET_PENDING = 69;
    uint256 internal constant JACKPOT_WORK = 70;
    uint256 internal constant FAR_FUTURE_OWED = 72;
    uint256 internal constant DEC_PREVIOUS_STACK = 73;
    uint256 internal constant DEC_PREVIOUS_COUNT = 73;
    uint256 internal constant DEC_PREVIOUS_COUNT_OFFSET = 8;
    uint256 internal constant DEC_JACKPOT_PLANS = 74;
    uint256 internal constant DEC_GENERATED_OWNERS = 75;
    uint256 internal constant DEGENESIS_WORD = 81;
    uint256 internal constant DEGENESIS_DAYS = 82;
    uint256 internal constant DEGENESIS_ORDERS = 83;
}

/// @title CrapsSlots
/// @notice CrapsBattle storage roots tests address by slot number. Pinned by
///         `test/fuzz/StorageSlotPins.t.sol` against a `CrapsBattleStorage` harness.
library CrapsSlots {
    uint256 internal constant DAY_STAKED = 9;
    uint256 internal constant HIGH_FIELD = 11;

    uint256 internal constant PASS_CREDITS_BY_ID = 14;
    uint256 internal constant FIRST_WINDOW_DAY = 18;
    uint256 internal constant FIRST_WINDOW_DAY_OFFSET = 8;
}

/// @title GameSlotKeys
/// @notice Derived storage keys for ID-keyed Game state, for tests reading a deployed Game.
library GameSlotKeys {
    /// @dev Wallet-table element `id` (key 0-159, smurf owner 160-191, half passes 192-255).
    function walletElement(uint32 id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + id);
    }

    function walletId(address player) internal pure returns (bytes32) {
        return keccak256(abi.encode(player, GameSlots.WALLET_IDS));
    }

    /// @dev Read the forward registry directly, without an extra Game call in call-count fixtures.
    function mintPacked(address player) internal view returns (bytes32) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        uint32 id = uint32(uint256(vm.load(ContractAddresses.GAME, walletId(player))));
        return mintPacked(id);
    }

    function mintPacked(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, GameSlots.MINT_PACKED));
    }

    /// @dev `balancesPacked[id]` (claimable low 128 | afking high 128).
    function balances(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), GameSlots.BALANCES_PACKED));
    }

    /// @dev `id`'s 85-bit subscriber lane and set position + 1 (0 = not a member), read
    ///      straight from storage. Lane: id 0-31, quantity-1 32-34, tickets 35, score code
    ///      36-45, checkpoint day 46-67, removal pending 68, checkpoint streak 69-84.
    function subLane(address game, uint32 id) internal view returns (uint256 lane, uint256 position1) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        uint256 meta = uint256(vm.load(game, keccak256(abi.encode(uint256(id >> 2), GameSlots.SUB_META))));
        position1 = uint64(meta >> ((id & 3) * 64)) & 0x7ff;
        if (position1 == 0) return (0, 0);
        uint256 position = position1 - 1;
        uint256 word = uint256(vm.load(game, bytes32(uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS))) + position / 3)));
        lane = (word >> ((position % 3) * 85)) & ((uint256(1) << 85) - 1);
    }

    /// @dev `id`'s daily quantity, 0 for a non-member.
    function subQuantity(address game, uint32 id) internal view returns (uint256) {
        (uint256 lane, uint256 position1) = subLane(game, id);
        return position1 == 0 ? 0 : ((lane >> 32) & 7) + 1;
    }

    /// @dev True while `id` holds an unopened AFKing box of the current cohort: the count is
    ///      nonzero, the sub sits in the box section, the opener cursor has not passed it, and a
    ///      protocol seat bought into the cohort.
    function afkingBoxPending(address game, uint32 id) internal view returns (bool) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        (, uint256 position) = subLane(game, id);
        if (position == 0) return false;
        uint256 packed = uint256(vm.load(game, bytes32(GameSlots.PENDING_BOX_COUNT)));
        if (uint16(packed >> (8 * GameSlots.PENDING_BOX_COUNT_OFFSET)) == 0) return false;
        if (position > uint16(packed >> (8 * GameSlots.SUB_BOX_COUNT_OFFSET))) return false;
        uint8 flags = uint8(packed >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET));
        if (id == 1 && flags & 1 == 0) return false;
        if (id == 2 && flags & 2 == 0) return false;
        return position - 1 >= uint16(packed >> (8 * GameSlots.SUB_OPEN_CURSOR_OFFSET));
    }

    /// @dev Day whose box `id` has opened: the cohort's stamp day, one earlier while its box is
    ///      pending; 0 for a non-member.
    function afkingOpenedDay(address game, uint32 id) internal view returns (uint32) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        (, uint256 position) = subLane(game, id);
        if (position == 0) return 0;
        uint32 stamp = uint24(uint256(vm.load(game, bytes32(GameSlots.AFKING_RESET_DAY))) >> (8 * GameSlots.AFKING_RESET_DAY_OFFSET));
        return afkingBoxPending(game, id) ? stamp - 1 : stamp;
    }

    /// @dev Root of any `mapping(uint32 => ...)` at `root`, keyed by wallet ID.
    function byId(uint32 id, uint256 root) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), root));
    }
}
