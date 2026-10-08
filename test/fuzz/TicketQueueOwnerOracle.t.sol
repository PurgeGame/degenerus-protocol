// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";

/// @dev Sensitivity controls for the raw queue oracle, not a production registry model proof.
contract TicketQueueOwnerOracleTest is Test {
    address private constant HOST = address(0xA11CE);
    address private constant VAULT = address(0xB001);
    address private constant SDGNRS = address(0xB002);
    address private constant SELLER = address(0xB004);
    uint24 private constant LEVEL = 4;

    function setUp() public {
        vm.store(HOST, bytes32(TQ.OWNERS), bytes32(uint256(6)));
        _root(1, VAULT);
        _root(2, SDGNRS);
        _root(4, SELLER);
        // Queue a child of the seller without inventing a forward address entry for it.
        _word(5, uint256(4) << 160);
        bytes32 queue = keccak256(abi.encode(uint256(TQ.queueKey(LEVEL)), TQ.QUEUE));
        vm.store(HOST, queue, bytes32(uint256(1) | uint256(LEVEL) << 32));
        vm.store(HOST, keccak256(abi.encode(queue)), bytes32(uint256(5)));
    }

    function _word(uint32 id, uint256 word) private {
        vm.store(HOST, bytes32(uint256(keccak256(abi.encode(TQ.OWNERS))) + id), bytes32(word));
    }

    function _root(uint32 id, address key) private {
        _word(id, uint160(key));
        vm.store(HOST, keccak256(abi.encode(key, TQ.MINT)), bytes32(uint256(id)));
    }

    function checkQueue() external view { TQ.assertQueue(HOST, LEVEL); }

    function test_OrdinaryChildAndRootMetadata() public {
        _word(4, uint256(uint160(SELLER)) | uint256(123) << 192);
        this.checkQueue();
        assertEq(TQ.ownerAt(HOST, LEVEL, LEVEL, 0), SELLER);
    }

    function test_AcquiredFamilyAndSellerReregistration() public {
        for (uint32 buyer = 1; buyer <= 2; ++buyer) {
            _word(4, uint256(uint160(SELLER)) | uint256(buyer) << 160);
            vm.store(HOST, keccak256(abi.encode(SELLER, TQ.MINT)), bytes32(uint256(4) << 32));
            this.checkQueue();
            assertEq(TQ.ownerAt(HOST, LEVEL, LEVEL, 0), buyer == 1 ? VAULT : SDGNRS);
            _root(6, SELLER);
            vm.store(HOST, bytes32(TQ.OWNERS), bytes32(uint256(7)));
            this.checkQueue();
        }
    }

    function test_RejectsNonProtocolBuyer() public {
        _word(4, uint256(uint160(SELLER)) | uint256(5) << 160);
        vm.expectRevert("invalid acquired buyer");
        this.checkQueue();
    }

    function test_RejectsChildCycle() public {
        _word(5, uint256(5) << 160);
        vm.expectRevert("invalid subaccount owner");
        this.checkQueue();
    }

    function test_RejectsMissingRootKey() public {
        _word(4, uint256(1) << 160);
        vm.expectRevert("owner root missing key");
        this.checkQueue();
    }

    function test_RejectsBrokenBuyerRegistry() public {
        _word(4, uint256(uint160(SELLER)) | uint256(1) << 160);
        vm.store(HOST, keccak256(abi.encode(VAULT, TQ.MINT)), bytes32(uint256(2)));
        vm.expectRevert("buyer identity mismatch");
        this.checkQueue();
    }

    function test_RejectsBrokenOrdinaryRegistry() public {
        vm.store(HOST, keccak256(abi.encode(SELLER, TQ.MINT)), bytes32(uint256(2)));
        vm.expectRevert("wallet identity mismatch");
        this.checkQueue();
    }
}
