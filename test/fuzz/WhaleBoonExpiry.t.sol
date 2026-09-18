// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title WhaleBoonExpiry -- Regression test for the whale-boon time-expiry fix in
///        checkAndClearExpiredBoon (DegenerusGameBoonModule, whale section, ~line 303-318).
/// @notice Before the fix, a lootbox-rolled whale discount (BP_WHALE_DAY_SHIFT=200,
///         BP_WHALE_TIER_SHIFT=248) never time-expired -- only a deity-day mismatch
///         (BP_DEITY_WHALE_DAY_SHIFT=224) cleared it. A lapsed lootbox-rolled tier therefore
///         blocked any lower re-roll forever, since _applyBoon only ever upgrades an existing
///         tier. The fix adds `else if (currentDay > whaleDayLocal + 4)`, mirroring the
///         lazy-pass lane's 4-day lapse window, so a lapsed lootbox-rolled discount clears and
///         a fresh (possibly lower) tier can land again.
///
///         Storage: uses vm.store to pre-inject whale-lane bits directly into
///         boonPacked[player].slot0 -- same technique and same SLOT_BOON_PACKED = 50 constant
///         as LootboxBoonCoexistence.t.sol (re-verified below against the working tree's
///         storage layout; see the note on _triggerSweep for why a plain `forge inspect`
///         could not be re-run standalone in this session).
///
///         Trigger: checkAndClearExpiredBoon has no direct Game-level entrypoint -- no
///         DegenerusGame wrapper forwards its selector, and DegenerusGame has no fallback(),
///         so an arbitrary-selector call on the deployed Game reverts. The only reachable path
///         from a full-protocol harness is indirect: `game.openBox` (LootboxModule) delegatecalls
///         into GAME_BOON_MODULE's rollBoxBoons/rollBoxBoonTiers, both of which route through
///         DegenerusGameBoonModule._boxBoonContext, which runs
///         `if (bp.slot0 != 0 || bp.slot1 != 0) checkAndClearExpiredBoon(player);`
///         unconditionally, before any new boon is drawn or budget-gated. So opening one
///         10-ether custom-tier box (identical setup to LootboxBoonCoexistence.t.sol's
///         _setupLootbox) reliably exercises the sweep regardless of what that box rolls.
contract WhaleBoonExpiry is DeployProtocol {
    // ──────────────────────────────────────────────────────────────────────
    // Storage slot constants (identical to LootboxBoonCoexistence.t.sol --
    // from `forge inspect DegenerusGame storage-layout` on the working tree,
    // post Stage B Game-storage packing).
    // ──────────────────────────────────────────────────────────────────────
    uint256 constant SLOT_BOON_PACKED  = 50;   // mapping(address => BoonPacked)
    uint256 constant SLOT_LOOTBOX_ETH  = 15;   // mapping(uint48 => mapping(address => uint256)) (packed order word)
    uint256 constant SLOT_LOOTBOX_WORD = 34;   // mapping(uint48 => uint256) lootboxRngWordByIndex

    // Packed lootboxOrder bit layout (mirrors DegenerusGameStorage lootboxOrder -- see LB_* there).
    uint256 constant LB_SCORE_SHIFT        = 24;  // score        [24:39]
    uint256 constant LB_CUSTOM_COUNT_SHIFT = 105; // customCount  [105:113]
    uint256 constant LB_CUSTOM_SIZE_SHIFT  = 113; // customSize   [113:161] @1e12
    uint256 constant LB_CUSTOM_SCALE       = 1e12;

    // BoonPacked slot0 whale-lane bit layout (DegenerusGameStorage.sol).
    uint256 constant BP_WHALE_DAY_SHIFT       = 200; // uint24 whaleDay
    uint256 constant BP_DEITY_WHALE_DAY_SHIFT = 224; // uint24 deityWhaleDay
    uint256 constant BP_WHALE_TIER_SHIFT      = 248; // uint8  whaleTier
    // Whale lane occupies bits 200..255 -- the full top 56 bits of slot0.
    uint256 constant BP_WHALE_CLEAR = ~(uint256(type(uint56).max) << BP_WHALE_DAY_SHIFT);


    function setUp() public {
        _deployProtocol();
        // The day index is time-derived (`currentDayView` == `_simulatedDayIndex`), so a plain
        // warp moves it; no advance is needed for the sweep, which runs off the box open. Land
        // well past day 5 so `currentDay - 5` in the lapsed case cannot underflow.
        vm.warp(block.timestamp + 8 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers (mirrors LootboxBoonCoexistence.t.sol)
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Compute the storage slot for boonPacked[player].slot0
    function _boonSlot0(address player) internal pure returns (bytes32) {
        return keccak256(abi.encode(player, SLOT_BOON_PACKED));
    }

    /// @dev Compute the storage slot for a nested mapping: base[index][player]
    function _nestedMappingSlot(uint256 baseSlot, uint48 index, address player) internal pure returns (bytes32) {
        bytes32 outerSlot = keccak256(abi.encode(uint256(index), baseSlot));
        return keccak256(abi.encode(player, outerSlot));
    }

    /// @dev Compute the storage slot for a simple mapping: base[index]
    function _simpleMappingSlot(uint256 baseSlot, uint48 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(index), baseSlot));
    }

    /// @dev Inject a whale boon into boonPacked[player].slot0: whaleDay, deityWhaleDay
    ///      (0 = lootbox-rolled, non-zero = deity-granted) and whaleTier. Clears only bits
    ///      200..255 first, so any other packed lane already present is left untouched --
    ///      mirrors the contract's own targeted bitmask discipline (BP_WHALE_CLEAR).
    function _injectWhaleBoon(address player, uint24 whaleDay, uint24 deityWhaleDay, uint8 tier) internal {
        bytes32 slot = _boonSlot0(player);
        uint256 current = uint256(vm.load(address(game), slot));
        current &= BP_WHALE_CLEAR;
        current |= uint256(whaleDay) << BP_WHALE_DAY_SHIFT;
        current |= uint256(deityWhaleDay) << BP_DEITY_WHALE_DAY_SHIFT;
        current |= uint256(tier) << BP_WHALE_TIER_SHIFT;
        vm.store(address(game), slot, bytes32(current));
    }

    /// @dev Read the whale lane (whaleDay, deityWhaleDay, whaleTier) from slot0.
    function _readWhaleLane(address player)
        internal
        view
        returns (uint24 whaleDay, uint24 deityWhaleDay, uint8 tier)
    {
        bytes32 slot = _boonSlot0(player);
        uint256 s0 = uint256(vm.load(address(game), slot));
        whaleDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        deityWhaleDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
        tier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
    }

    /// @dev True iff the entire whale lane (bits 200..255 of slot0) reads zero.
    function _whaleLaneIsZero(address player) internal view returns (bool) {
        (uint24 whaleDay, uint24 deityWhaleDay, uint8 tier) = _readWhaleLane(player);
        return whaleDay == 0 && deityWhaleDay == 0 && tier == 0;
    }

    /// @dev Set up a lootbox ready to open: one CUSTOM box of `ethAmount`, score=1, frozen to
    ///      the live level -- identical shape to LootboxBoonCoexistence.t.sol's _setupLootbox.
    function _setupLootbox(address player, uint48 index, uint256 ethAmount) internal {
        uint256 customUnits = ethAmount / LB_CUSTOM_SCALE;
        uint256 packed = uint256(game.level())
            | (uint256(1) << LB_SCORE_SHIFT)
            | (uint256(1) << LB_CUSTOM_COUNT_SHIFT)
            | (customUnits << LB_CUSTOM_SIZE_SHIFT);
        vm.store(address(game), _nestedMappingSlot(SLOT_LOOTBOX_ETH, index, player), bytes32(packed));

        uint256 vrfWord = uint256(keccak256(abi.encode("whaleBoonExpiry", player, index)));
        vm.store(address(game), _simpleMappingSlot(SLOT_LOOTBOX_WORD, index), bytes32(vrfWord));
    }

    /// @dev Trigger checkAndClearExpiredBoon by opening a lootbox: LootboxModule's per-tier
    ///      resolver delegatecalls into GAME_BOON_MODULE's rollBoxBoons, which routes through
    ///      _boxBoonContext -- unconditionally sweeping expired boons (since our injected whale
    ///      bits leave slot0 != 0) before anything else in the call happens.
    function _triggerSweep(address player, uint48 index) internal {
        _setupLootbox(player, index, 10 ether);
        vm.prank(player);
        game.openBox(player, index);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Tests
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Case 1: whaleDay = currentDay - 5 (one day past the 4-day window), no deity
    ///         day. The fix's `currentDay > whaleDayLocal + 4` branch must fire and the whole
    ///         whale lane (bits 200..255) must read 0 after the sweep.
    function test_lapsedLootboxWhaleBoonClears() public {
        address player = makeAddr("whaleLapsed");
        vm.deal(player, 100 ether);

        uint24 currentDay = game.currentDayView();
        _injectWhaleBoon(player, currentDay - 5, 0, 3);

        (uint24 whaleDayBefore, uint24 deityDayBefore, uint8 tierBefore) = _readWhaleLane(player);
        assertEq(tierBefore, 3, "whale tier should be seeded at 3");
        assertEq(whaleDayBefore, currentDay - 5, "whaleDay should be seeded 5 days back");
        assertEq(deityDayBefore, 0, "deityWhaleDay should be seeded at 0 (lootbox-rolled)");

        _triggerSweep(player, 5001);

        assertTrue(_whaleLaneIsZero(player), "lapsed whale lane (bits 200..255) must read 0 after the sweep");
    }

    /// @notice Case 2: whaleDay = currentDay - 2 (still inside the 4-day window), no deity
    ///         day. The lane must be completely untouched by the sweep.
    function test_freshLootboxWhaleBoonSurvivesSweep() public {
        address player = makeAddr("whaleFresh");
        vm.deal(player, 100 ether);

        uint24 currentDay = game.currentDayView();
        _injectWhaleBoon(player, currentDay - 2, 0, 3);

        _triggerSweep(player, 5002);

        (uint24 whaleDayAfter, uint24 deityWhaleDayAfter, uint8 tierAfter) = _readWhaleLane(player);
        assertEq(tierAfter, 3, "whale tier must survive inside the 4-day window");
        assertEq(whaleDayAfter, currentDay - 2, "whaleDay must be untouched inside the 4-day window");
        assertEq(deityWhaleDayAfter, 0, "deityWhaleDay must stay 0");
    }

    /// @notice Case 3: deity-granted whale boon (deityWhaleDay == whaleDay == currentDay).
    ///         A same-day sweep must leave it untouched (pre-existing behaviour, unchanged by
    ///         this fix -- the deity-day-mismatch branch is checked first and short-circuits
    ///         the new time-window branch). Advancing one day so currentDay != deityWhaleDay
    ///         must then clear it on the next sweep.
    function test_deityWhaleBoonSurvivesSameDaySweepThenClearsNextDay() public {
        address player = makeAddr("whaleDeity");
        vm.deal(player, 100 ether);

        uint24 currentDay = game.currentDayView();
        _injectWhaleBoon(player, currentDay, currentDay, 3);

        _triggerSweep(player, 5003);

        (uint24 whaleDaySame, uint24 deityWhaleDaySame, uint8 tierSame) = _readWhaleLane(player);
        assertEq(tierSame, 3, "deity whale boon must survive a same-day sweep");
        assertEq(whaleDaySame, currentDay, "whaleDay untouched on a same-day sweep");
        assertEq(deityWhaleDaySame, currentDay, "deityWhaleDay untouched on a same-day sweep");

        // Advance one day so currentDay no longer matches the stamped deity day.
        vm.warp(block.timestamp + 1 days);
        uint24 newDay = game.currentDayView();
        assertGt(newDay, currentDay, "day must have advanced past the deity stamp");

        _triggerSweep(player, 5004);

        assertTrue(_whaleLaneIsZero(player), "deity whale lane must clear once currentDay != deityWhaleDay");
    }
}
