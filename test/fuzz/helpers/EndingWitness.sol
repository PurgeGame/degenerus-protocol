// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {GamePoolSlots} from "../../helpers/GamePoolSlots.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";

/// @title EndingWitness -- was a terminal latch due when the engine took it?
/// @notice Read raw Game storage immediately before a mining call, at the same timestamp,
///         and re-derive from this file's own arithmetic whether a documented ending could
///         fire: the deadman (14 days after the last certified daily completion), a VRF
///         request left unpublished for 14 days, or the purchase timeout (30 logical days
///         into a purchase phase whose next pool is still at or below its target). If the
///         engine latches terminal state (`gameOver` or the terminal entry bit) across a
///         call for which `due` was false, the ending was premature.
/// @dev Mirrors `DegenerusGameStorage._endingReason`, including `_prizePoolTarget`: the
///      previous level's recorded pool (zero once its recycled slot holds another level, as
///      the engine reads it), raised at century levels to the curved multiple of the newest
///      completed century's pool. Constants mirror `_VRF_DEAD_TIMEOUT`,
///      `_PURCHASE_TIMEOUT_DAYS` and the `CENTURY_FLOOR_*` curve. The inputs are the
///      engine's own clocks; `AdvanceLivenessHandler` separately checks that an idle,
///      sealed day stamped its completion, so the deadman clock cannot go stale silently.
library EndingWitness {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant VRF_DEAD_TIMEOUT = 14 days;
    uint256 internal constant PURCHASE_TIMEOUT_DAYS = 30;
    uint256 internal constant CENTURY_FLOOR_BPS = 20_000;
    uint256 internal constant CENTURY_FLOOR_MID_BPS = 15_000;
    uint256 internal constant CENTURY_FLOOR_TOP_BPS = 13_000;
    uint256 internal constant CENTURY_FLOOR_MID_THRESHOLD = 500_000 ether;
    uint256 internal constant CENTURY_FLOOR_TOP_THRESHOLD = 1_000_000 ether;

    uint256 private constant TERMINAL_ENTRY_BIT = 253; // rngFlagsAndNudges bit 13
    uint256 private constant REQUEST_ACTIVE_BIT = 254; // rngFlagsAndNudges bit 14
    uint256 private constant SESSION_PUBLISHED_BIT = 255; // rngFlagsAndNudges bit 15
    uint256 private constant LR_GO_DEAD_SHIFT = 232;
    uint256 private constant LR_GO_SWAP_SHIFT = 248;

    /// @notice Terminal state is latched: `gameOver`, or the terminal entry bit set before it.
    function latched(address game) internal view returns (bool) {
        uint256 s0 = _slot0(game);
        return uint8(s0 >> (GameSlots.GAME_OVER_OFFSET * 8)) != 0 || (s0 >> TERMINAL_ENTRY_BIT) & 1 != 0;
    }

    /// @notice Some documented ending is due at the current timestamp.
    function due(address game) internal view returns (bool) {
        return deadmanDue(game) || vrfDeadDue(game) || purchaseTimeoutDue(game);
    }

    function lastCompletedAt(address game) internal view returns (uint256) {
        uint256 word = uint256(VM.load(game, bytes32(GameSlots.LAST_DAILY_COMPLETED_AT)));
        return uint48(word >> (GameSlots.LAST_DAILY_COMPLETED_AT_OFFSET * 8));
    }

    function deadmanDue(address game) internal view returns (bool) {
        return block.timestamp >= lastCompletedAt(game) + VRF_DEAD_TIMEOUT;
    }

    function vrfDeadDue(address game) internal view returns (bool) {
        uint256 s0 = _slot0(game);
        if ((s0 >> SESSION_PUBLISHED_BIT) & 1 != 0) return false;
        uint256 requested = uint48(s0 >> (GameSlots.RNG_REQUEST_TIME_OFFSET * 8));
        if (block.timestamp < requested + VRF_DEAD_TIMEOUT) return false;
        if ((s0 >> REQUEST_ACTIVE_BIT) & 1 != 0) return true;
        uint256 lr = uint256(VM.load(game, bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
        return (lr >> LR_GO_DEAD_SHIFT) & 0xFF != 0 || (lr >> LR_GO_SWAP_SHIFT) & 1 != 0;
    }

    function purchaseTimeoutDue(address game) internal view returns (bool) {
        uint256 s0 = _slot0(game);
        uint256 startDay = uint24(s0);
        uint256 day = uint24(s0 >> (GameSlots.DAILY_IDX_OFFSET * 8));
        bool jackpot = uint8(s0 >> (GameSlots.JACKPOT_PHASE_FLAG_OFFSET * 8)) != 0;
        bool lastPurchaseDay = uint8(s0 >> (GameSlots.LAST_PURCHASE_DAY_OFFSET * 8)) != 0;
        if (lastPurchaseDay || jackpot || day < startDay || day - startDay < PURCHASE_TIMEOUT_DAYS) return false;
        if (day - startDay == PURCHASE_TIMEOUT_DAYS && !dailyComplete(game)) return false;
        if (GameTimeLib.currentDayIndexAt(block.timestamp) <= GameTimeLib.currentDayIndexAt(lastCompletedAt(game))) {
            return false;
        }
        uint24 lvl = uint24(s0 >> (GameSlots.LEVEL_OFFSET * 8));
        uint256 next = uint128(uint256(VM.load(game, bytes32(GameSlots.PRIZE_POOLS_PACKED))));
        return next <= prizePoolTarget(game, lvl + 1);
    }

    /// @notice The next-pool target `nextPrizePool` must exceed for `purchaseLvl` (>= 1).
    function prizePoolTarget(address game, uint24 purchaseLvl) internal view returns (uint256 target) {
        target = GamePoolSlots.read(game, purchaseLvl - 1);
        if (purchaseLvl % 100 != 0) return target;
        uint256 completed = uint256(VM.load(game, bytes32(GameSlots.CENTURY_PRIZE_POOLS)));
        if (completed == 0) return target;
        uint256 i = completed - 1;
        uint256 base = uint256(keccak256(abi.encode(GameSlots.CENTURY_PRIZE_POOLS)));
        uint256 snap = uint128(uint256(VM.load(game, bytes32(base + i / 2))) >> ((i % 2) * 128));
        uint256 multBps = snap > CENTURY_FLOOR_TOP_THRESHOLD ? CENTURY_FLOOR_TOP_BPS
            : snap > CENTURY_FLOOR_MID_THRESHOLD ? CENTURY_FLOOR_MID_BPS : CENTURY_FLOOR_BPS;
        uint256 centuryFloor = snap * multBps / 10_000;
        if (centuryFloor > target) target = centuryFloor;
    }

    function dailyComplete(address game) internal view returns (bool) {
        uint256 word = uint256(VM.load(game, bytes32(GameSlots.DAILY_COMPLETE)));
        return uint8(word >> (GameSlots.DAILY_COMPLETE_OFFSET * 8)) != 0;
    }

    function lastDailyRequestWallDay(address game) internal view returns (uint24) {
        uint256 word = uint256(VM.load(game, bytes32(GameSlots.LAST_DAILY_REQUEST_WALL_DAY)));
        return uint24(word >> (GameSlots.LAST_DAILY_REQUEST_WALL_DAY_OFFSET * 8));
    }

    function _slot0(address game) private view returns (uint256) {
        return uint256(VM.load(game, bytes32(0)));
    }
}
