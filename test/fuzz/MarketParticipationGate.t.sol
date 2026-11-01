// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @title MarketParticipationGate -- `Quests.marketBetGates` admits real participation only
/// @notice Registration, curse stacks and the unused mint-word bits (147 and 224..255) never open the
///         prediction-market gate; a ticket purchase or a deity pass does.
contract MarketParticipationGateTest is DeployProtocol {
    address private owner;
    uint32 private main;
    uint256 private price;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        owner = makeAddr("gate-owner");
        main = _giveWalletId(owner);
        vm.deal(owner, 100 ether);
        vm.deal(address(game), 1_000 ether);
        price = game.mintPrice();
    }

    function _word() private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.mintPacked(main)));
    }

    function test_RegistrationAndCurseAreNotParticipationATicketIs() public {
        (bool mayBet, bool earnsReward, uint32 id) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "registration is not participation");
        assertFalse(earnsReward);
        assertEq(id, main);

        vm.store(address(game), GameSlotKeys.mintPacked(main),
            bytes32(_word() | (uint256(1) << BitPackingLib.CURSE_COUNT_SHIFT)));
        (mayBet, earnsReward,) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "a curse is not participation");
        assertFalse(earnsReward);

        vm.prank(owner);
        game.purchaseOrderFor{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        (mayBet,, id) = quests.marketBetGates(main, 1);
        assertTrue(mayBet, "a ticket purchase qualifies");
        assertEq(id, main);
    }

    function testFuzz_UnusedBitsAndCurseOnlyCannotBet(uint32 high, bool bit147, uint8 curse) public {
        uint256 word = (uint256(high) << 224) | (bit147 ? uint256(1) << 147 : 0)
            | (uint256(curse & 31) << BitPackingLib.CURSE_COUNT_SHIFT);
        vm.store(address(game), GameSlotKeys.mintPacked(main), bytes32(word));
        (bool mayBet, bool earnsReward, uint32 id) = quests.marketBetGates(main, 1);
        assertFalse(mayBet, "unused bits and curses grant no market access");
        assertFalse(earnsReward);
        assertEq(id, main);
    }

    function test_RealDeityPassQualifies() public {
        vm.prank(owner);
        game.purchaseDeityPass{value: 30 ether}(0, 3, 0);
        assertGe(game.playerActivityScoreById(main), 120);
        (bool mayBet,,) = quests.marketBetGates(main, 1);
        assertTrue(mayBet, "a deity pass is participation");
    }
}
