// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract GenesisQueueSeeder is DegenerusGameStorage, WalletSeed {
    function setLevel(uint24 lvl) external { level = lvl; }
    function queue(address owner, uint24 lvl, uint32 entries) external {
        _queueEntries(_seedWallet(owner), lvl, entries, false);
    }
}

contract DeityGenesisBatchGasTest is DeployProtocol {
    /// @dev `_mintCeiling()` at genesis: level 0, no last-purchase latch -> level + 1. Level 1 is
    ///      the only minted level; the genesis deities' levels 2..100 wait unminted in the
    ///      far-future key space (initProtocolDeity routes `lvl > _mintCeiling()` there).
    uint24 private constant GENESIS_MINT_CEILING = 1;

    function _genesisKey(uint24 lvl) private pure returns (uint24) {
        return lvl > GENESIS_MINT_CEILING ? lvl | uint24(1 << 22) : lvl;
    }

    function setUp() public {
        _deployProtocol(false);
        assertEq(game.level(), 0, "fixture: genesis level anchors GENESIS_MINT_CEILING");
    }

    function testColdBatchFitsTransactionCapAndWritesEachQueueWordOnce() public {
        vm.record();
        uint256 beforeGas = gasleft();
        game.initProtocolDeity{gas: 16_777_216 - 21_064}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("both genesis deities including intrinsic", used);
        assertLt(used, 16_777_216);
        (, bytes32[] memory writes) = vm.accesses(address(game));
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint24 key = _genesisKey(lvl);
            bytes32 lengthSlot = keccak256(abi.encode(uint256(key), uint256(12)));
            bytes32 wordSlot = keccak256(abi.encode(lengthSlot));
            bytes32 pendingRoot = bytes32(uint256(78));
            uint256 owedWrites = lvl == 1 ? 1 : lvl <= 8 ? 7 : lvl >= 97 ? 4 : 8;
            bytes32 firstRecord = lvl == 1 ? keccak256(abi.encode(uint256(1), pendingRoot))
                : bytes32(uint256(keccak256(abi.encode(uint256(1), uint256(81)))) + (lvl - 1) / 8);
            bytes32 secondRecord = lvl == 1 ? keccak256(abi.encode(uint256(2), pendingRoot))
                : bytes32(uint256(keccak256(abi.encode(uint256(2), uint256(81)))) + (lvl - 1) / 8);
            uint256 lengthWrites;
            uint256 wordWrites;
            uint256 firstRecordWrites;
            uint256 secondRecordWrites;
            for (uint256 i; i < writes.length; ++i) {
                if (writes[i] == lengthSlot) ++lengthWrites;
                if (writes[i] == wordSlot) ++wordWrites;
                if (writes[i] == firstRecord) ++firstRecordWrites;
                if (writes[i] == secondRecord) ++secondRecordWrites;
            }
            assertEq(lengthWrites, 1, "one queue length write for both owners");
            assertEq(wordWrites, 1, "one packed queue word write for both owners");
            assertEq(firstRecordWrites, owedWrites, "Vault updates each covered lane");
            assertEq(secondRecordWrites, owedWrites, "sDGNRS updates each covered lane");
            assertEq(uint256(vm.load(address(game), lengthSlot)), 2);
            assertEq(uint256(vm.load(address(game), wordSlot)), 1 | (uint256(2) << 32));
            assertEq(uint32(TQ.owed(address(game), key, address(vault)) >> 8), 4);
            assertEq(uint32(TQ.owed(address(game), key, address(sdgnrs)) >> 8), 4);
        }
        uint256 registryWrites;
        uint256 vaultWrites;
        uint256 sdgnrsWrites;
        bytes32 firstOwner = keccak256(abi.encode(uint256(67)));
        for (uint256 i; i < writes.length; ++i) {
            if (writes[i] == bytes32(uint256(67))) ++registryWrites;
            if (writes[i] == firstOwner) ++vaultWrites;
            if (writes[i] == bytes32(uint256(firstOwner) + 1)) ++sdgnrsWrites;
        }
        assertEq(registryWrites, 2, "registry length changes only on first registration");
        assertEq(vaultWrites, 1, "Vault identity stored once across all levels");
        assertEq(sdgnrsWrites, 1, "sDGNRS identity stored once across all levels");
        assertEq(deityPass.ownerOf(0), address(vault));
        assertEq(deityPass.ownerOf(6), address(sdgnrs));
    }

    function testBatchPreservesPartialTailsAndExistingProtocolEntries() public {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(GenesisQueueSeeder).runtimeCode);
        for (uint160 i = 1; i <= 7; ++i) {
            GenesisQueueSeeder(address(game)).queue(address(1000 + i), 1, uint32(i * 4));
        }
        GenesisQueueSeeder(address(game)).queue(address(vault), 6, 12);
        GenesisQueueSeeder(address(game)).queue(address(sdgnrs), 6, 8);
        GenesisQueueSeeder(address(game)).queue(address(vault), 7, 12);
        vm.etch(address(game), original);
        TQ.setOwed(address(game), 1, address(1001), TQ.owed(address(game), 1, address(1001)) | 37);

        game.initProtocolDeity();

        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint24 key = _genesisKey(lvl);
            TQ.assertQueue(address(game), key);
            assertEq(uint32(TQ.owed(address(game), key, address(vault)) >> 8),
                lvl == 6 || lvl == 7 ? 16 : 4);
            assertEq(uint32(TQ.owed(address(game), key, address(sdgnrs)) >> 8), lvl == 6 ? 12 : 4);
            bytes32 lengthSlot = keccak256(abi.encode(uint256(key), uint256(12)));
            assertEq(uint256(vm.load(address(game), lengthSlot)), lvl == 1 ? 9 : 2);
        }
        for (uint160 i = 1; i <= 7; ++i) {
            assertEq(uint32(TQ.owed(address(game), 1, address(1000 + i)) >> 8), i * 4);
        }
        assertEq(uint8(TQ.owed(address(game), 1, address(1001))), 37, "fractional entries survive");
    }

    function testGenesisCannotSeedExpiredLevelsAfterAdvancement() public {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(GenesisQueueSeeder).runtimeCode);
        GenesisQueueSeeder(address(game)).setLevel(1);
        vm.etch(address(game), original);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.initProtocolDeity();
        assertEq(deityPass.balanceOf(address(vault)), 0);
        assertEq(deityPass.balanceOf(address(sdgnrs)), 0);
    }

    function testOnlyCreatorCanInitializeAndRegistrationPreventsRepeats() public {
        vm.expectRevert(DegenerusGameStorage.E.selector);
        vm.prank(address(0xBAD));
        game.initProtocolDeity();
        vm.expectRevert(DegenerusGameStorage.E.selector);
        vm.prank(address(vault));
        game.initProtocolDeity();
        vm.expectRevert(DegenerusGameStorage.E.selector);
        vm.prank(address(sdgnrs));
        game.initProtocolDeity();
        game.initProtocolDeity();
        vm.expectRevert(bytes4(keccak256("AlreadyOwnsDeityPass()")));
        game.initProtocolDeity();
        assertEq(deityPass.balanceOf(address(vault)), 1);
        assertEq(deityPass.balanceOf(address(sdgnrs)), 1);
    }
}
