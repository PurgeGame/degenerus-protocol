// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title GenesisDailyQuestSeed — the deploy day carries a seeded daily quest pair.
///
/// @notice The DegenerusQuests constructor stamps the deploy day's daily quests with
///         fixed types (no VRF exists at deploy): slot 0 MINT_ETH — the roll's own
///         always-slot — and slot 1 DEGENERETTE_ETH, placeable from genesis with
///         progress credited at placement. The rolled-day bitmap bit is set so the
///         seed is a real rolled day for streak accounting, and rollDailyQuest's
///         same-day idempotency guard holds the pair for the whole deploy day; the
///         first entropy roll lands on day two.
contract GenesisDailyQuestSeed is DeployProtocol {
    uint8 private constant QUEST_TYPE_MINT_ETH = 1;
    uint8 private constant QUEST_TYPE_DEGENERETTE_ETH = 7;
    uint8 private constant CURRENCY_ETH = 0;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant QUEST_BITMAP_SLOT = 4;

    address private player;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("genesis_player");
        vm.deal(player, 100 ether);
        vm.deal(address(game), 1_000 ether);

        // placeDegeneretteBet reverts while lootboxRngIndex == 0. Production crosses
        // that at the deploy day's first advance request; mirror the post-crank state
        // (shape shared with BigRecordArming).
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
    }

    function testDeployDayCarriesTheSeededPair() public {
        QuestInfo[2] memory q = quests.getActiveQuests();
        uint24 day0 = uint24(game.currentDayView());
        assertEq(q[0].day, day0, "slot 0 must be stamped for the deploy day");
        assertEq(
            q[0].questType,
            QUEST_TYPE_MINT_ETH,
            "slot 0 carries the always-MINT_ETH type"
        );
        assertEq(q[1].day, day0, "slot 1 must be stamped for the deploy day");
        assertEq(
            q[1].questType,
            QUEST_TYPE_DEGENERETTE_ETH,
            "slot 1 carries the seeded DEGENERETTE_ETH type"
        );
        // The seed marks a real rolled day for the streak machinery.
        uint256 word = uint256(
            vm.load(
                address(quests),
                keccak256(
                    abi.encode(uint256(uint16(day0 >> 8)), QUEST_BITMAP_SLOT)
                )
            )
        );
        assertTrue(
            (word >> uint8(day0)) & 1 == 1,
            "the deploy day must be marked rolled in the bitmap"
        );
    }

    function testDeployDayPairCompletesInOrder() public {
        // Slot 1 is the bonus slot — locked until the slot-0 primary completes
        // (the standing daily design) — so clear MINT_ETH with a ticket buy first.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        vm.prank(player);
        game.purchase{value: priceWei * 4}(
            player,
            1600,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
        (bool slot0, ) = quests.questCompletionToday(player);
        assertTrue(
            slot0,
            "a deploy-day ticket buy completes the seeded MINT_ETH primary"
        );

        // Daily DEGENERETTE_ETH target = min(mintPrice * 2, 0.5 ether); one 0.5 ETH
        // spin clears it at any price.
        vm.prank(player);
        game.placeDegeneretteBet{value: 0.5 ether}(
            player,
            CURRENCY_ETH,
            0.5 ether,
            1,
            0x00010203,
            0
        );
        (, bool slot1) = quests.questCompletionToday(player);
        assertTrue(
            slot1,
            "a deploy-day ETH degenerette bet then completes the seeded slot-1 quest"
        );
    }

    function testSameDayRollIsANoOpAndNextDayReplaces() public {
        uint24 day0 = uint24(game.currentDayView());
        vm.prank(address(game));
        quests.rollDailyQuest(
            day0,
            uint256(keccak256("entropy")),
            false,
            false,
            false
        );
        QuestInfo[2] memory q = quests.getActiveQuests();
        assertEq(
            q[1].questType,
            QUEST_TYPE_DEGENERETTE_ETH,
            "the same-day roll must not replace the seeded pair"
        );

        vm.prank(address(game));
        quests.rollDailyQuest(
            day0 + 1,
            uint256(keccak256("entropy2")),
            false,
            false,
            false
        );
        q = quests.getActiveQuests();
        assertEq(q[0].day, day0 + 1, "the next-day roll re-stamps normally");
        assertEq(
            q[0].questType,
            QUEST_TYPE_MINT_ETH,
            "slot 0 stays the always-MINT_ETH slot"
        );
    }
}
