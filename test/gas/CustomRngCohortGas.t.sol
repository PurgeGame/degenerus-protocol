// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Actual paid custom seats, actual engine and Game keeper routing. Every
/// measured call starts cold and is offered the unmodified transaction ceiling.
contract CustomRngCohortGasTest is DeployProtocol {
    uint256 private constant CAP = 10_000_000;
    uint256 private constant SEATS = 320;
    uint32 private constant BOARD = 1 | (uint32(1) << 3) | (uint32(1) << 6)
        | (uint32(1) << 9) | (uint32(1) << 12) | (uint32(1) << 15) | (uint32(1) << 18);

    function test_ColdKeeperDrainsDeepHighCustomFieldAndCommitsFinalization() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 128 && (game.advanceDue() || game.rngLocked()); ++i) {
            game.mineFlip(0);
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, 0xB00757);
            }
        }
        assertFalse(game.rngLocked());
        _finishReadConsumers();
        crapsBattle.setBattleCreator(address(this), true);
        uint64 slot = crapsBattle.createBattle(300, 25, 1000, 75,
            uint40(vm.getBlockTimestamp() + 60), true, 255);
        for (uint256 i; i < SEATS; ++i) {
            address player = address(uint160(0xC0570000 + i));
            vm.prank(address(game));
            coin.mintForGame(player, 5_000_000 ether); // Includes the inactive-wallet 5% surcharge.
            vm.prank(player);
            crapsBattle.enterBattle(slot, BOARD, 255);
        }
        vm.warp(vm.getBlockTimestamp() + 60);
        // Craps windows ride the normal RNG round (6d0e64b09): the close binds the field to the
        // write buffer and makes no request of its own; the ordinary mid-day request, for which a
        // closed window on the write buffer is work that waives the pending-value gates, seals it.
        uint256 requestBefore = mockVRF.lastRequestId();
        uint48 buffer = crapsBattle.closeBattle(slot);
        assertEq(mockVRF.lastRequestId(), requestBefore, "the close makes no request of its own");
        assertEq(buffer, RecyclingState.writeBuffer(address(game)), "the shut field binds the write buffer");
        game.mineFlip(0);
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, requestBefore, "the ordinary mid-day request seals the shut field");
        assertEq(RecyclingState.readBuffer(address(game)), buffer, "the request sealed the field's buffer");
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled, "custom close requests its fresh session");
        mockVRF.fulfillRandomWords(request, uint256(keccak256("cold deep high custom")) | 2);
        game.mineFlip(0); // Publication is required before any consumer uses the word.
        (bytes32 key,,) = crapsBattle.customBattleOf(slot);
        uint256 maxGas;
        uint256 finalGas;
        uint256 calls;
        while (!crapsBattle.battleOf(key).finalized && calls < 256) {
            vm.cool(address(game));
            vm.cool(address(crapsBattle));
            vm.cool(address(coin));
            vm.cool(address(coinflip));
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            vm.cool(ContractAddresses.JACKPOT_BATTLE);
            uint256 beforeGas = gasleft();
            game.mineFlip{gas: CAP - 21_192}(0);
            uint256 used = beforeGas - gasleft() + 21_192;
            assertLt(used, CAP, "custom cohort keeper transaction exceeds the ceiling");
            if (used > maxGas) maxGas = used;
            if (crapsBattle.battleOf(key).finalized) finalGas = used;
            ++calls;
        }
        assertTrue(crapsBattle.battleOf(key).finalized, "paid seats and winner must finish");
        assertEq(crapsBattle.battleOf(key).resolved, SEATS, "every paid seat settled");
        assertGt(calls, 1, "field must require resumable batches");
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) & (uint256(1) << (250 + buffer)), 0);
        assertEq(RecyclingState.readBuffer(address(game)), buffer, "draining never replaces the session");
        emit log_named_uint("custom cold maximum keeper gas", maxGas);
        emit log_named_uint("custom cold finalization keeper gas", finalGas);
        emit log_named_uint("custom keeper calls", calls);
    }
}
