// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";

/// @title BoonStaticDiscard -- static boon table, discard-at-delivery, deity exclusions
/// @notice Boon outcomes are pure functions of (word, player, amount). LOOTBOX draws walk
///         the full 2,608-weight table with dec + deity tiers always present. Live state
///         only keep-vs-discards the already-determined type, and ONLY for permanently dead
///         outcomes (deity-pass tiers when a pass is held or supply is capped); decimator
///         tiers always deliver and bank for a later window (BoonDiscarded, no write).
///         DEITY menu rolls exclude the dec and deity-pass bands UNCONDITIONALLY (those
///         families are lootbox-only), so every gift slot is always issuable and issuance
///         has no rolled-type revert path at all.
contract BoonStaticDiscard is DeployProtocol {

    // Storage slots (from `forge inspect DegenerusGame storage-layout`, see
    // LootboxBoonCoexistence which pins the same values).
    uint256 constant SLOT_BOON_PACKED = 50; // mapping(address => BoonPacked)
    uint256 constant SLOT_LOOTBOX_ETH = 15; // mapping(uint48 => mapping(address => uint256))
    uint256 constant SLOT_LOOTBOX_WORD = 34; // mapping(uint48 => uint256)

    uint256 constant LB_SCORE_SHIFT = 24;
    uint256 constant LB_CUSTOM_COUNT_SHIFT = 105;
    uint256 constant LB_CUSTOM_SIZE_SHIFT = 113;
    uint256 constant LB_CUSTOM_SCALE = 1e12;

    // BoonPacked field shifts (DegenerusGameStorage)
    uint256 constant BP_DECIMATOR_TIER_SHIFT = 168; // slot0
    uint256 constant BP_DEITY_PASS_TIER_SHIFT = 72; // slot1

    // Boon type ids (LootboxModule)
    uint8 constant BOON_DECIMATOR_10 = 13;
    uint8 constant BOON_DECIMATOR_50 = 15;
    uint8 constant BOON_DEITY_PASS_10 = 25;
    uint8 constant BOON_DEITY_PASS_35 = 27;

    bytes32 constant BOON_DISCARDED_SIG = keccak256("BoonDiscarded(address,uint8)");

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function _nestedMappingSlot(uint256 baseSlot, uint48 index, address player) internal pure returns (bytes32) {
        bytes32 outerSlot = keccak256(abi.encode(uint256(index), baseSlot));
        return keccak256(abi.encode(player, outerSlot));
    }

    function _simpleMappingSlot(uint256 baseSlot, uint48 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(index), baseSlot));
    }

    function _setupLootbox(address player, uint48 index, uint256 ethAmount, uint256 vrfWord) internal {
        // One CUSTOM box of `ethAmount`, score=1, frozen to the live level (see
        // LootboxBoonCoexistence._setupLootbox for the same migration pattern).
        uint256 packed = uint256(game.level())
            | (uint256(1) << LB_SCORE_SHIFT)
            | (uint256(1) << LB_CUSTOM_COUNT_SHIFT)
            | ((ethAmount / LB_CUSTOM_SCALE) << LB_CUSTOM_SIZE_SHIFT);
        vm.store(address(game), _nestedMappingSlot(SLOT_LOOTBOX_ETH, index, player), bytes32(packed));
        vm.store(address(game), _simpleMappingSlot(SLOT_LOOTBOX_WORD, index), bytes32(vrfWord));
    }

    function _boonSlot(address player, uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(player, SLOT_BOON_PACKED))) + offset);
    }

    /// @notice At a level with the decimator window SHUT, dec-tier draws must still be
    ///         DELIVERED (the tier field is written), never discarded: a lootbox-sourced
    ///         decimator boon carries no time expiry, so it banks for the next burn window.
    ///         Drawing dec tiers here at all is impossible under the old eligibility-gated
    ///         table, which excluded them from the walk entirely outside a window.
    function test_decDrawOutsideWindowIsDeliveredNotDiscarded() public {
        _completeDay(0xD15C0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xD15C0002);

        address player = makeAddr("discardPlayer");
        vm.deal(player, 10 ether);

        uint256 decDiscards;
        for (uint256 i = 1; i <= 150; i++) {
            uint256 vrfWord = uint256(keccak256(abi.encode("staticDiscard", i)));
            uint48 index = uint48(5000 + i);
            _setupLootbox(player, index, 10 ether, vrfWord);

            vm.recordLogs();
            vm.prank(player);
            try game.openBox(player, index) {} catch { continue; }

            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics[0] != BOON_DISCARDED_SIG) continue;
                uint8 boonType = uint8(abi.decode(logs[j].data, (uint8)));
                // Only the deity-pass family may ever discard, and only when permanently
                // dead. This player holds no pass and supply is open, so nothing should.
                assertFalse(
                    boonType >= BOON_DECIMATOR_10 && boonType <= BOON_DECIMATOR_50,
                    "decimator draw was discarded: it banks for the next window"
                );
                decDiscards++;
            }
        }
        assertEq(decDiscards, 0, "unexpected discard in an all-deliverable fixture");

        // Non-vacuity: over 150 near-certain boon hits the static table must actually have
        // drawn a decimator tier at some point, and it must be sitting in the tier field.
        // (Zero would mean the walk is still eligibility-gated -- the regression this guards.)
        uint256 s0 = uint256(vm.load(address(game), _boonSlot(player, 0)));
        assertGt(
            uint256(uint8(s0 >> BP_DECIMATOR_TIER_SHIFT)),
            0,
            "no decimator tier banked: static table not in effect"
        );
    }

    bytes32 constant DEITY_BOON_ISSUED_SIG =
        keccak256("DeityBoonIssued(address,address,uint24,uint8,uint8)");

    /// @notice Module-side twin of the viewer test: issue ALL THREE slots through the real
    ///         issueDeityBoon path and read the emitted boonType. No slot may revert (the
    ///         always-issuable property) and no issued type may come from the excluded
    ///         families. This catches a band-arithmetic slip shared with the viewer mirror,
    ///         which the viewer-only test cannot.
    function test_deityIssueAllSlotsAndTypesExcludeBands() public {
        _completeDay(0xD15C0005);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xD15C0006);

        DeityBoonViewer viewer = new DeityBoonViewer();
        address deity = makeAddr("parityDeity");
        vm.deal(deity, 100 ether);
        vm.prank(deity);
        game.purchaseDeityPass{value: 24 ether}(deity, 5, bytes32(0));

        (uint8[3] memory menu, , ) = viewer.deityBoonSlots(address(game), deity);

        for (uint8 s2 = 0; s2 < 3; s2++) {
            address recipient = makeAddr(string(abi.encodePacked("parityRecipient", s2)));
            vm.recordLogs();
            vm.prank(deity);
            game.issueDeityBoon(deity, recipient, s2);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool found;
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics[0] != DEITY_BOON_ISSUED_SIG) continue;
                (uint8 slotEmitted, uint8 boonType) = abi.decode(logs[j].data, (uint8, uint8));
                assertEq(slotEmitted, s2, "slot mismatch");
                assertEq(boonType, menu[s2], "module type diverges from viewer menu");
                assertFalse(
                    boonType >= BOON_DECIMATOR_10 && boonType <= BOON_DECIMATOR_50,
                    "module issued a dec tier"
                );
                assertFalse(
                    boonType >= BOON_DEITY_PASS_10 && boonType <= BOON_DEITY_PASS_35,
                    "module issued a deity-pass tier"
                );
                found = true;
            }
            assertTrue(found, "DeityBoonIssued not emitted");
        }
    }

    /// @notice The deity three-slot menu excludes the decimator AND deity-pass families
    ///         unconditionally (they are lootbox-only), so every gift slot is always
    ///         issuable: across many candidate deities, no menu slot may ever show either
    ///         family. Under the full 2,608-weight table ~3.5% of 600 sampled slots would --
    ///         zero here proves the two-band skip is live in the viewer's mirror.
    function test_deityMenuNeverContainsDecOrDeityTiers() public {
        _completeDay(0xD15C0003);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xD15C0004);

        DeityBoonViewer viewer = new DeityBoonViewer();
        for (uint256 i = 0; i < 200; i++) {
            address cand = makeAddr(string(abi.encodePacked("menuDeity", i)));
            (uint8[3] memory slots, , ) = viewer.deityBoonSlots(address(game), cand);
            for (uint8 s = 0; s < 3; s++) {
                assertFalse(
                    slots[s] >= BOON_DECIMATOR_10 && slots[s] <= BOON_DECIMATOR_50,
                    "dec tier in deity menu"
                );
                assertFalse(
                    slots[s] >= BOON_DEITY_PASS_10 && slots[s] <= BOON_DEITY_PASS_35,
                    "deity-pass tier in deity menu"
                );
                assertTrue(slots[s] != 0, "empty slot with a live daily seed");
            }
        }
    }
}
