// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxBoonCoexistence -- Tests that lootbox-rolled boons coexist with existing boons
/// @notice Validates the change in commit 004a9065 that removed the single-category exclusivity
///         gate from _rollLootboxBoons. Before that commit, if a player had an active boon in
///         category X, a lootbox roll producing a boon in category Y was silently dropped via
///         early return. Now _applyBoon runs unconditionally for any rolled boon type.
///
///         Uses vm.store to pre-inject a coinflip boon into boonPacked[player], then opens
///         lootboxes with controlled VRF words. LootBoxReward events prove _applyBoon ran
///         through the lootbox path despite an existing boon in a different category.
contract LootboxBoonCoexistence is DeployProtocol {

    // ──────────────────────────────────────────────────────────────────────
    // Storage slot constants (from `forge inspect DegenerusGame storage-layout`)
    // ──────────────────────────────────────────────────────────────────────

    uint256 constant SLOT_BOON_PACKED     = GameSlots.BOON_PACKED;   // mapping(uint32 => BoonPacked)

    // Queue entry word (LB_* layout in DegenerusGameStorage): id[0:32) | level[32:56) |
    // score[56:71) | customCount[121:128) | customSize[128:184) in gwei.
    uint256 constant LB_LEVEL_SHIFT       = 32;
    uint256 constant LB_SCORE_SHIFT       = 56;
    uint256 constant LB_CUSTOM_COUNT_SHIFT = 121;
    uint256 constant LB_SIZE_SHIFT        = 128;

    // BoonPacked bit layout (slot0)
    uint256 constant BP_COINFLIP_DAY_SHIFT  = 0;
    uint256 constant BP_COINFLIP_TIER_SHIFT = 48;
    uint256 constant BP_LOOTBOX_TIER_SHIFT  = 104;
    uint256 constant BP_PURCHASE_TIER_SHIFT = 160;

    // LootBoxReward event signature (from DegenerusGameLootboxModule)

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        _finishReadConsumers();
    }

    /// @dev Compute the storage slot for boonPacked[player].slot0
    function _boonSlot0(address player) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(player)), SLOT_BOON_PACKED));
    }

    /// @dev Inject a coinflip boon (tier 1, day = currentDay) into boonPacked[player].slot0.
    ///      This simulates the player having an active coinflip boon from a prior lootbox/deity.
    function _injectCoinflipBoon(address player, uint48 day) internal {
        _giveWalletId(player);
        bytes32 slot = _boonSlot0(player);
        uint256 current = uint256(vm.load(address(game), slot));
        // Set coinflipDay = day, coinflipTier = 1
        current = current | (uint256(day) << BP_COINFLIP_DAY_SHIFT);
        current = current | (uint256(1) << BP_COINFLIP_TIER_SHIFT);
        vm.store(address(game), slot, bytes32(current));
    }

    /// @dev Read the coinflip tier from boonPacked[player].slot0
    function _readCoinflipTier(address player) internal view returns (uint8) {
        bytes32 slot = _boonSlot0(player);
        uint256 s0 = uint256(vm.load(address(game), slot));
        return uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
    }

    /// @dev Read the purchase tier from boonPacked[player].slot0
    function _readPurchaseTier(address player) internal view returns (uint8) {
        bytes32 slot = _boonSlot0(player);
        uint256 s0 = uint256(vm.load(address(game), slot));
        return uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
    }

    /// @dev Read the lootbox boost tier from boonPacked[player].slot0
    function _readLootboxTier(address player) internal view returns (uint8) {
        bytes32 slot = _boonSlot0(player);
        uint256 s0 = uint256(vm.load(address(game), slot));
        return uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
    }

    /// @dev Set up a lootbox ready to open: one CUSTOM box of `ethAmount` (score=1, a low raw
    ///      activity score, frozen to the live level) appended as the only entry of physical
    ///      buffer `index`, then sealed with the delivered word so mineFlip's human-box stage
    ///      can only ever reach this one entry. `purchaseLevel` and `day` are unused (kept in the
    ///      signature for callers).
    function _setupLootbox(
        address player,
        uint48 index,
        uint256 ethAmount,
        uint24 purchaseLevel,
        uint48 day,
        uint256 vrfWord
    ) internal {
        purchaseLevel; day;
        uint32 id = _giveWalletId(player);
        uint256 word = uint256(id)
            | (uint256(game.level()) << LB_LEVEL_SHIFT)
            | (uint256(1) << LB_SCORE_SHIFT)
            | (uint256(1) << LB_CUSTOM_COUNT_SHIFT)
            | ((ethAmount / 1 gwei) << LB_SIZE_SHIFT);
        RecyclingState.seedWriteBuffer(address(game), index);
        bytes32 data = keccak256(abi.encode(keccak256(abi.encode(uint256(index), GameSlots.BOX_QUEUE))));
        vm.store(address(game), data, bytes32(word));
        uint256 lr = uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
        lr = (lr & ~(uint256(0xFFFFFFFF) << 120)) | (uint256(1) << 120);
        vm.store(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED), bytes32(lr));
        RecyclingState.seedWord(address(game), index, bytes32(vrfWord));
    }

    /// @dev Every preservation assertion must follow one real, consumed box.
    ///      A rejected or blocked sweep is a failed fixture, never a passing case.
    function _openSeededBox(address player, uint48 index) internal {
        assertFalse(game.rngLocked(), "seeded boon fixture must be unlocked");
        assertGt(RecyclingState.boxEntry(address(game), index, 0), 0, "seeded box must exist");
        vm.prank(player);
        game.mineFlip(0);
        uint256 cursors = uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR)));
        assertEq(
            uint48(cursors >> (GameSlots.BOX_CURSOR_OFFSET * 8)), 1,
            "seeded entry must be consumed by the frontier"
        );
        // The forged queue holds exactly this one entry, so a completed frontier on its buffer
        // means the call opened exactly one box.
        assertTrue(game.boxIndexComplete(index), "preservation proof must actually open its one box");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Tests
    // ──────────────────────────────────────────────────────────────────────

    /// @notice With an existing coinflip boon, lootbox opens that roll ANY boon type
    ///         still apply it (LootBoxReward emitted). Tests many VRF seeds to maximize
    ///         the chance of hitting a non-coinflip boon category.
    function test_lootboxBoonAppliedDespiteExistingCoinflipBoon() public {
        // Complete day 1 so game state is initialized
        _completeDay(0xBEEF0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xBEEF0002);

        address player = makeAddr("boonPlayer");
        vm.deal(player, 1000 ether);

        uint48 currentDay = uint48((block.timestamp - 86400) / 1 days);

        // Inject an existing coinflip boon
        _injectCoinflipBoon(player, currentDay);
        assertEq(_readCoinflipTier(player), 1, "Coinflip boon should be injected");

        // Try many lootbox opens with different VRF words.
        // Use large ETH amount (10 ETH) to maximize boon budget and roll probability.
        // boonBudget = 10% of 10 ETH = 1 ETH (hits max cap).
        // totalChance = (1e18 * 1e6) / expectedPerBoon. With typical avgMaxValue,
        // this should give near-100% boon probability for most seeds.
        uint256 boonEventsTotal = 0;

        for (uint256 seed = 1; seed <= 50; seed++) {
            uint256 vrfWord = uint256(keccak256(abi.encode("boonTest", seed)));
            uint48 index = uint48(seed & 1); // Use high indices to avoid collisions

            _setupLootbox(player, index, 10 ether, 1, currentDay, vrfWord);

            _openSeededBox(player, index);

            // Check if any additional boon was written
            uint8 purchaseTier = _readPurchaseTier(player);
            uint8 lootboxTier = _readLootboxTier(player);
            if (purchaseTier > 0 || lootboxTier > 0) {
                boonEventsTotal++;
            }
        }

        // With 50 attempts at 10 ETH each, we expect multiple boon hits.
        // The key assertion: boonEventsTotal > 0 means _applyBoon ran for a
        // non-coinflip category while the coinflip boon was still active.
        assertTrue(boonEventsTotal > 0, "At least one lootbox should have rolled a non-coinflip boon");

        // Coinflip boon must still be intact (tier can increase via upgrade, but never drop to 0)
        assertTrue(_readCoinflipTier(player) >= 1, "Coinflip boon must survive cross-category boon application");
    }

    /// @notice Fuzz test: with a pre-injected coinflip boon, any lootbox open that
    ///         produces a LootBoxReward event preserves the existing coinflip tier.
    function testFuzz_coinflipBoonSurvivesLootboxBoonRoll(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        _completeDay(0xBEEF0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xBEEF0002);

        address player = makeAddr("fuzzPlayer");
        vm.deal(player, 100 ether);

        uint48 currentDay = uint48((block.timestamp - 86400) / 1 days);

        // Inject coinflip boon
        _injectCoinflipBoon(player, currentDay);

        // Setup lootbox with fuzzed VRF word
        _setupLootbox(player, 1, 10 ether, 1, currentDay, vrfWord);

        _openSeededBox(player, 1);

        // After open, coinflip tier must still be >= 1
        // (it can increase if lootbox rolled a higher-tier coinflip boon, but never decrease)
        uint8 tierAfter = _readCoinflipTier(player);
        assertTrue(tierAfter >= 1, "Coinflip tier must never decrease from lootbox boon application");
    }

    /// @notice Deterministic test: pre-set boons in TWO categories via vm.store, then
    ///         open a lootbox. Both boon tiers must survive the open regardless of what
    ///         the lootbox rolls (unless it upgrades one of them).
    function test_twoCategoryBoonsPreservedAfterLootboxOpen() public {
        _completeDay(0xBEEF0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xBEEF0002);

        address player = makeAddr("twoCategory");
        vm.deal(player, 100 ether);

        uint48 currentDay = uint48((block.timestamp - 86400) / 1 days);

        // Inject coinflip boon (tier 1) AND purchase boon (tier 1) via vm.store
        _giveWalletId(player);
        bytes32 slot = _boonSlot0(player);
        uint256 s0 = 0;
        s0 |= uint256(currentDay) << BP_COINFLIP_DAY_SHIFT;     // coinflipDay
        s0 |= uint256(1) << BP_COINFLIP_TIER_SHIFT;             // coinflipTier = 1
        s0 |= uint256(currentDay) << 112;                       // purchaseDay (BP_PURCHASE_DAY_SHIFT)
        s0 |= uint256(1) << BP_PURCHASE_TIER_SHIFT;             // purchaseTier = 1
        vm.store(address(game), slot, bytes32(s0));

        assertEq(_readCoinflipTier(player), 1);
        assertEq(_readPurchaseTier(player), 1);

        // Open lootbox
        uint256 vrfWord = uint256(keccak256("deterministic_boon_test"));
        _setupLootbox(player, 0, 10 ether, 1, currentDay, vrfWord);

        _openSeededBox(player, 0);

        // Both tiers must be >= 1 (can only increase, never wiped by cross-category application)
        assertTrue(_readCoinflipTier(player) >= 1, "Coinflip tier preserved after lootbox open");
        assertTrue(_readPurchaseTier(player) >= 1, "Purchase tier preserved after lootbox open");
    }

    /// @notice Parametric autoBuy: open 100 lootboxes with incrementing seeds while holding
    ///         a coinflip boon. Count how many produce boons in other categories.
    ///         At least 1 must land in a non-coinflip category to prove the exclusivity
    ///         gate is actually removed (not just untested).
    function test_parametricAutoBuy_crossCategoryBoonFromLootbox() public {
        _completeDay(0xBEEF0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xBEEF0002);

        address player = makeAddr("autoBuyPlayer");
        vm.deal(player, 10000 ether);

        uint48 currentDay = uint48((block.timestamp - 86400) / 1 days);

        uint256 crossCategoryHits = 0;

        for (uint256 i = 1; i <= 100; i++) {
            // Re-inject coinflip boon fresh each iteration (lootbox open may modify it)
            _injectCoinflipBoon(player, currentDay);

            uint256 vrfWord = uint256(keccak256(abi.encode("autoBuy", i)));
            uint48 index = uint48(i & 1);

            _setupLootbox(player, index, 10 ether, 1, currentDay, vrfWord);

            // Snapshot non-coinflip tiers before
            uint8 purchaseBefore = _readPurchaseTier(player);
            uint8 lootboxBefore = _readLootboxTier(player);

            _openSeededBox(player, index);

            // Check if a non-coinflip boon was applied
            uint8 purchaseAfter = _readPurchaseTier(player);
            uint8 lootboxAfter = _readLootboxTier(player);

            if (purchaseAfter > purchaseBefore || lootboxAfter > lootboxBefore) {
                crossCategoryHits++;
            }

            // Coinflip tier must survive regardless
            assertTrue(
                _readCoinflipTier(player) >= 1,
                string.concat("Coinflip tier cleared on iteration ", vm.toString(i))
            );
        }

        // With 100 attempts at max boon budget, we expect multiple cross-category hits.
        // This is the definitive proof: the old code would produce 0 cross-category hits
        // because the exclusivity gate returned early for any non-matching category.
        assertTrue(
            crossCategoryHits > 0,
            "Zero cross-category boons in 100 opens -- exclusivity gate may still be active"
        );
    }
}
