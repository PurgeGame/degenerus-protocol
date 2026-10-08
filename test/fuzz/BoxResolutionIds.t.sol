// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SmurfFixture} from "./SmurfFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

contract BoxResolutionIdsTest is SmurfFixture {
    uint32 private ownerId;
    uint32 private smurfId;

    function setUp() public {
        _setUpSmurfFixture();
        address owner;
        (owner, ownerId) = _wallet("resolution_owner");
        _grantSmurfBase(owner, 1);
        smurfId = _createSmurf(owner);
    }

    function _assertNoIdentityReads(bytes32[] memory reads) private view {
        for (uint256 i; i < reads.length; ++i) {
            assertNotEq(reads[i], GameSlotKeys.walletElement(smurfId), "credit-only resolution loaded the account owner");
            assertNotEq(reads[i], GameSlotKeys.walletElement(ownerId), "credit-only resolution loaded the payee");
            assertNotEq(reads[i], GameSlotKeys.mintPacked(smurfId), "credit-only resolution read mint history during credit-only resolution");
        }
    }

    function _queued(bool presale) private {
        uint256 word;
        for (uint256 k = 1; ; ++k) {
            uint256 root = uint256(keccak256(abi.encode(uint256(0x5175657565644f72646572), k, uint256(0), uint256(0))));
            if (presale) {
                uint256 seed = uint256(keccak256(abi.encode(root, uint256(smurfId), keccak256("PRESALE_BOX"), uint256(0))));
                if (uint16(seed) % 100 >= 50) continue;
                if (uint256(keccak256(abi.encode(seed, uint256(0x5061737353696465)))) & 1 != 0) continue;
            } else {
                uint256 seed = uint256(keccak256(abi.encode(root, uint256(smurfId), uint256(0x426f784f70656e), uint256(1))));
                if (uint16(seed >> 40) % 20 != 14) continue;
                uint256 boonSeed = uint256(keccak256(abi.encode(root, uint256(smurfId), uint256(0x426f78426f6f6e), uint256(0))));
                if (uint32(uint256(keccak256(abi.encode(boonSeed, uint256(0)))) >> 120) % 1_000_000 < 900_000) continue;
            }
            word = k;
            break;
        }
        uint24 lvl = game.level() + 1;
        uint256 entry = uint256(smurfId);
        if (presale) entry |= uint256(0.01 ether) << 185;
        else entry |= (uint256(lvl) << 32) | (uint256(1) << 121) | (uint256(0.01 ether / 1 gwei) << 128);
        vm.record();
        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeCall(DegenerusGameLootboxModule.resolveHumanBoxOrder, (uint48(0), uint256(0), entry, word, lvl))
        );
        (bytes32[] memory reads,) = vm.accesses(address(game));
        _assertNoIdentityReads(reads);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = presale
            ? keccak256("PresaleBoxOpened(uint32,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)")
            : keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == topic) {
                assertEq(uint256(logs[i].topics[1]), smurfId, "event retains the smurf's identity");
                ++count;
            }
        }
        assertEq(count, 1, "one resolution event");
    }

    function test_QueuedFlipCreditNeedsNoAddressLookup() public { _queued(false); }
    function test_PresaleFlipCreditNeedsNoAddressLookup() public { _queued(true); }

    function test_AutomaticSpinsEmitSmurfIdWithoutAddressLookup() public {
        vm.record();
        vm.recordLogs();
        ext.x_delegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeCall(
            DegenerusGameDegeneretteModule.resolveFlipSpinsFromBox, (smurfId, 3000 ether, uint16(305), uint256(123), uint8(3))
        ));
        ext.x_delegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeCall(
            DegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox, (smurfId, 1 ether, uint16(305), uint256(456), uint8(3))
        ));
        (bytes32[] memory reads,) = vm.accesses(address(game));
        _assertNoIdentityReads(reads);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")) {
                assertEq(uint256(logs[i].topics[1]), smurfId, "spin identifies the smurf");
                ++count;
            }
        }
        assertEq(count, 2);
    }

    function test_LosingPlacedBetNeedsNoAddressLookup() public {
        _openBetBuffer();
        vm.recordLogs();
        vm.prank(makeAddr("resolution_owner"));
        game.placeDegeneretteBet{value: 0.01 ether}(smurfId, 0, 0.01 ether, 1, 3);
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
                assertEq(uint256(logs[i].topics[1]), smurfId);
            }
        }
    }
}
