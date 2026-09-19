// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract GenesisQueueSeeder is DegenerusGameStorage {
    function queue(address owner, uint24 lvl, uint32 entries) external {
        _queueEntries(owner, lvl, entries, false);
    }
}

contract DeityGenesisBatchGasTest is DeployProtocol {
    function setUp() public {
        _deployProtocol(false);
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
            uint24 key = lvl > 5 ? lvl | uint24(1 << 22) : lvl;
            bytes32 lengthSlot = keccak256(abi.encode(uint256(key), uint256(12)));
            bytes32 wordSlot = keccak256(abi.encode(lengthSlot));
            bytes32 ownerLengthSlot = keccak256(abi.encode(uint256(lvl), uint256(67)));
            bytes32 firstRecord = keccak256(abi.encode(ownerLengthSlot));
            bytes32 secondRecord = bytes32(uint256(firstRecord) + 1);
            uint256 lengthWrites;
            uint256 wordWrites;
            uint256 ownerLengthWrites;
            uint256 firstRecordWrites;
            uint256 secondRecordWrites;
            for (uint256 i; i < writes.length; ++i) {
                if (writes[i] == lengthSlot) ++lengthWrites;
                if (writes[i] == wordSlot) ++wordWrites;
                if (writes[i] == ownerLengthSlot) ++ownerLengthWrites;
                if (writes[i] == firstRecord) ++firstRecordWrites;
                if (writes[i] == secondRecord) ++secondRecordWrites;
            }
            assertEq(lengthWrites, 1, "one queue length write for both owners");
            assertEq(wordWrites, 1, "one packed queue word write for both owners");
            assertEq(ownerLengthWrites, 1, "one registry length write for both owners");
            assertEq(firstRecordWrites, 1, "one complete Vault owner/owed write");
            assertEq(secondRecordWrites, 1, "one complete sDGNRS owner/owed write");
            assertEq(uint256(vm.load(address(game), lengthSlot)), 2);
            assertEq(uint256(vm.load(address(game), wordSlot)), 1 | (uint256(2) << 32));
            assertEq(uint32(TQ.owed(address(game), key, address(vault)) >> 8), 4);
            assertEq(uint32(TQ.owed(address(game), key, address(sdgnrs)) >> 8), 4);
        }
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
        uint24 farSix = uint24(1 << 22) | 6;
        TQ.setOwed(address(game), farSix, address(vault), TQ.owed(address(game), farSix, address(vault)) | 37);

        game.initProtocolDeity();

        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint24 key = lvl > 5 ? lvl | uint24(1 << 22) : lvl;
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
        assertEq(uint8(TQ.owed(address(game), farSix, address(vault))), 37, "fractional entries survive");
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
