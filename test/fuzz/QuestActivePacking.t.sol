// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "../helpers/QaSlots.sol";

import {Test} from "forge-std/Test.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";

contract QuestActivePackingTest is Test {
    DegenerusQuests internal quests;
    uint32 internal constant PLAYER = 0xB071;

    function setUp() public {
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("currentDayView_g542950()"), abi.encode(uint24(1)));
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("currentLvl()"), abi.encode(uint24(24)));
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("decimatorActive()"), abi.encode(false));
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("mintPrice()"), abi.encode(uint256(0.04 ether)));
        DegenerusQuests implementation = new DegenerusQuests();
        quests = DegenerusQuests(ContractAddresses.QUESTS);
        vm.etch(address(quests), address(implementation).code);
        vm.store(address(quests), bytes32(QaSlots.ACTIVE), vm.load(address(implementation), bytes32(QaSlots.ACTIVE)));
    }

    function test_GenesisDailySeedPreservesLevelQuest() public view {
        uint256 active = uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)));
        assertEq(uint8(active >> 128), 1, "genesis MINT_ETH");
        assertEq(uint8(active >> 136), 1, "genesis epoch");
        assertEq(vm.load(address(quests), bytes32(QaSlots.LEVEL)), bytes32(0), "mapping base slot holds no data");
        QuestInfo[2] memory daily = quests.getActiveQuests();
        assertEq(daily[0].questType, 1);
        assertEq(daily[1].questType, 7);
    }

    function testFuzz_DailyAndLevelRollsPreserveEachOther(uint256 entropy, uint8 version) public {
        uint256 beforeWord = uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)));
        // Exercise the wrap boundary as well as ordinary epochs, retaining the seeded daily pair.
        uint256 seeded = (beforeWord & ~(uint256(255) << 136)) | (uint256(version) << 136);
        vm.store(address(quests), bytes32(QaSlots.ACTIVE), bytes32(seeded));
        vm.prank(ContractAddresses.GAME);
        quests.rollLevelQuest(entropy);
        uint256 rolled = uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)));
        assertEq(uint128(rolled), uint128(seeded), "level roll preserves both daily quests");
        assertEq(uint8(rolled >> 136), uint8(uint256(version) + 1), "version wraps exactly once");
        uint24 nextDay = uint24(beforeWord) + 1;
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(nextDay, entropy, false, false, false);
        uint256 afterWord = uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)));
        assertEq(afterWord >> 128, rolled >> 128, "daily roll preserves level type/version");
        assertEq(uint24(afterWord), nextDay);
        assertEq(uint24(afterWord >> 64), nextDay);
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(nextDay, ~entropy, true, true, true);
        assertEq(uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE))), afterWord, "same-day roll stays idempotent");
    }

    function test_DailyRollDoesNotResetLevelProgress() public {
        vm.prank(ContractAddresses.GAME);
        quests.handlePurchase_g23478(1, PLAYER, 0.01 ether, 0, 0, 0.04 ether, 0.04 ether);
        bytes32 progressSlot = keccak256(abi.encode(uint256(PLAYER), QaSlots.LEVEL));
        uint256 progress = uint256(vm.load(address(quests), progressSlot));
        assertEq(uint128(progress >> 8), 0.01 ether);
        uint24 day = uint24(uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)))) + 1;
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(day, 123, true, false, false);
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("currentDayView_g542950()"), abi.encode(day));
        vm.prank(ContractAddresses.GAME);
        quests.handlePurchase_g23478(day, PLAYER, 0.01 ether, 0, 0, 0.04 ether, 0.04 ether);
        progress = uint256(vm.load(address(quests), progressSlot));
        assertEq(uint8(progress), 1);
        assertEq(uint128(progress >> 8), 0.02 ether, "daily roll keeps level accumulation");
    }

    function test_PurchaseReturnsAfkingFlagFromQuestWord() public {
        vm.prank(ContractAddresses.GAME);
        (,,,, bool afking) = quests.handlePurchase_g23478(1, PLAYER, 0.01 ether, 0, 0, 0.04 ether, 0.04 ether);
        assertFalse(afking);
        uint24 day = uint24(uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE))));
        vm.prank(ContractAddresses.GAME);
        quests.beginAfking(PLAYER, day);
        vm.prank(ContractAddresses.GAME);
        (,,,, afking) = quests.handlePurchase_g23478(1, PLAYER, 0.01 ether, 0, 0, 0.04 ether, 0.04 ether);
        assertTrue(afking);
        vm.prank(ContractAddresses.GAME);
        quests.finalizeAfking(PLAYER, 0, day, day);
        vm.prank(ContractAddresses.GAME);
        (,,,, afking) = quests.handlePurchase_g23478(1, PLAYER, 0.01 ether, 0, 0, 0.04 ether, 0.04 ether);
        assertFalse(afking);
    }
}
