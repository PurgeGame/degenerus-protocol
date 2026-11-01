// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {AccountFixture} from "./AccountFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @notice Credit-only box, spin and losing-bet resolution identify the account by ID and never
///         load its wallet element or mint history.
contract BoxResolutionIdsTest is AccountFixture {
    uint32 private accountId;

    function setUp() public {
        _setUpAccountFixture();
        (, accountId) = _wallet("resolution_owner");
    }

    function _assertNoIdentityReads(bytes32[] memory reads) private view {
        for (uint256 i; i < reads.length; ++i) {
            assertNotEq(reads[i], GameSlotKeys.walletElement(accountId), "credit-only resolution loaded the account's payee");
            assertNotEq(reads[i], GameSlotKeys.mintPacked(accountId), "credit-only resolution read mint history");
        }
    }

    /// @dev Resolve the account's one-box order on `word`; true when every log came from the Game
    ///      or Coinflip, i.e. the box only credited state by ID (no token payout).
    function _creditOnly(uint256 entry, uint256 word, uint24 lvl) private returns (bool) {
        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, lvl))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) && logs[i].emitter != address(coinflip)) return false;
        }
        return true;
    }

    function _queued() private {
        uint24 searchLvl = game.currentLvl() + 1;
        uint256 searchEntry = uint256(accountId) | (uint256(10) << 32) | (uint256(1) << 77);
        uint256 word;
        for (uint256 k = 1; k < 500; ++k) {
            uint256 snap = vm.snapshotState();
            bool creditOnly = _creditOnly(searchEntry, k, searchLvl);
            vm.revertToState(snap);
            if (creditOnly) {
                word = k;
                break;
            }
        }
        assertGt(word, 0, "fixture: a credit-only box word");
        uint24 lvl = game.currentLvl() + 1;
        // One 0.01 ETH box (10 units, quantity 1) for the account.
        uint256 entry = uint256(accountId) | (uint256(10) << 32) | (uint256(1) << 77);
        vm.record();
        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, lvl))
        );
        (bytes32[] memory reads,) = vm.accesses(address(game));
        _assertNoIdentityReads(reads);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == topic) {
                assertEq(uint256(logs[i].topics[1]), accountId, "event retains the account's identity");
                ++count;
            }
        }
        assertEq(count, 1, "one resolution event");
    }

    function test_QueuedFlipCreditNeedsNoAddressLookup() public { _queued(); }

    function test_AutomaticSpinsEmitAccountIdWithoutAddressLookup() public {
        vm.record();
        vm.recordLogs();
        ext.x_delegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeCall(
            DegenerusGameDegeneretteModule.resolveFlipSpinsFromBox, (accountId, 3000 ether, uint16(305), uint256(123), uint8(3))
        ));
        ext.x_delegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeCall(
            DegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox, (accountId, 1 ether, uint16(305), uint256(456), uint8(3))
        ));
        (bytes32[] memory reads,) = vm.accesses(address(game));
        _assertNoIdentityReads(reads);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")) {
                assertEq(uint256(logs[i].topics[1]), accountId, "spin identifies the account");
                ++count;
            }
        }
        assertEq(count, 2);
    }

    function test_LosingPlacedBetNeedsNoAddressLookup() public {
        _openBetBuffer();
        vm.recordLogs();
        vm.prank(makeAddr("resolution_owner"));
        game.betDegenerette{value: 0.01 ether}(accountId, 0, 0.01 ether, 1, 3);
        (uint64 betId,) = _placedBetId(vm.getRecordedLogs());
        uint256 word = 2;
        for (;; ++word) {
            (uint8 score,) = Ref.score(
                Ref.player(word, uint32(BET_INDEX), 3, 0, false), Ref.house(word, uint32(BET_INDEX), 0, false)
            );
            if (score == 1) break;
        }
        vm.record();
        Vm.Log[] memory logs = _resolveBet(word, betId);
        (bytes32[] memory reads,) = vm.accesses(address(game));
        _assertNoIdentityReads(reads);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == BET_RESOLVED) {
                (uint256 payout,,) = abi.decode(logs[i].data, (uint256, uint32, bytes));
                assertEq(payout, 0, "the regression exercises a loss");
                assertEq(uint256(logs[i].topics[1]), accountId);
            }
        }
    }
}
