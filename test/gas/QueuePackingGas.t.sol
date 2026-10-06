// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Overlay seeds the claim and reads the inherited layout; measured calls use live bytecode.
contract QueuePackingGasSeeder is DegenerusGame, WalletSeed {
    function claimFor(address player) external { _seedHalfPasses(player, 4); }

    /// @dev Level 111 reuses level 1's physical near-queue slot (queue slots recycle under an
    ///      absolute-level tag) and a wallet's pending word keeps one lane pair per level parity,
    ///      so the raw jump to level 110 first models level 1 as fully drained: every queued
    ///      owner's level-1 balance consumed and both level-1 queues released, as the drain
    ///      leaves them.
    function emptyPurchaseLevel() external {
        _seedDrainedQueue(_tqWriteKey(1));
        _seedDrainedQueue(_tqReadKey(1));
        level = 110;
        _seedWallet(address(1));
    }

    function _seedDrainedQueue(uint24 key) private {
        uint256 n = _ticketQueueLength(key);
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        for (uint256 i; i < n; ++i) {
            uint32 id = _tqPositionAt(q, i);
            if (_entryPacked(key, id) != 0) _setEntryOwed(key, id, 0);
        }
        _releaseTicketQueue(key);
    }

    function queued(uint24 lvl, address player) external view returns (uint80) {
        // Same routing as the queue sinks: levels above the mint ceiling wait unminted in the
        // far-future key space; minted levels take the double-buffer write key.
        uint24 key = lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
        return _owedOf(key, player);
    }
}

/// @dev setUp is a separate transaction: all measured buyers and storage accesses start cold.
contract QueuePackingPurchaseGas is DeployProtocol {
    address internal constant BUYER = address(0xABC123);

    function setUp() public {
        _deployProtocol();
        vm.deal(BUYER, 100 ether);
    }

    function test_FirstTimePurchase_ExistingQueueWord_Cold() public {
        vm.prank(BUYER);
        uint256 beforeGas = gasleft();
        game.purchase{value: 0.01 ether}(BUYER, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        emit log_named_uint("QUEUE_FIRST_PURCHASE_EXISTING_WORD", beforeGas - gasleft());
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        uint80 owed = QueuePackingGasSeeder(payable(address(game))).queued(1, BUYER);
        assertEq(uint32(owed >> 8), 4);
        assertGt(owed >> 48, 1, "gas fixture must use a nonzero registry index");
    }
}

contract QueuePackingEmptyPurchaseGas is DeployProtocol {
    address internal constant BUYER = address(0xABC124);

    function setUp() public {
        _deployProtocol();
        vm.deal(BUYER, 100 ether);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        QueuePackingGasSeeder(payable(address(game))).emptyPurchaseLevel();
        vm.etch(address(game), code);
    }

    function test_FirstTimePurchase_FreshQueueWord_Cold() public {
        vm.prank(BUYER);
        uint256 beforeGas = gasleft();
        game.purchase{value: 0.04 ether}(BUYER, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        emit log_named_uint("QUEUE_FIRST_PURCHASE_FRESH_WORD", beforeGas - gasleft());
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        uint80 owed = QueuePackingGasSeeder(payable(address(game))).queued(111, BUYER);
        assertEq(uint32(owed >> 8), 4);
        assertGt(owed >> 48, 1, "gas fixture must use a nonzero registry index");
    }
}

/// @dev A real paid first purchase establishes the wallet's ID before a later-level purchase.
contract QueuePackingReturningPurchaseGas is DeployProtocol {
    address internal constant BUYER = address(0xABC126);
    function setUp() public {
        _deployProtocol();
        vm.deal(BUYER, 100 ether);
        vm.prank(BUYER);
        game.purchase{value: 0.01 ether}(BUYER, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        QueuePackingGasSeeder(payable(address(game))).emptyPurchaseLevel();
        vm.etch(address(game), code);
    }
    function test_ReturningWallet_LaterLevel_Cold() public {
        vm.prank(BUYER);
        uint256 beforeGas = gasleft();
        game.purchase{value: 0.04 ether}(BUYER, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        emit log_named_uint("QUEUE_RETURNING_PURCHASE_LATER_LEVEL", beforeGas - gasleft());
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        uint80 owed = QueuePackingGasSeeder(payable(address(game))).queued(111, BUYER);
        assertEq(uint32(owed >> 8), 4);
        assertGt(owed >> 48, 1);
    }
}

contract QueuePackingWhaleClaimGas is DeployProtocol {
    address internal constant BUYER = address(0xABC125);

    function setUp() public {
        _deployProtocol();
        bytes memory code = address(game).code;
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        QueuePackingGasSeeder(payable(address(game))).claimFor(BUYER);
        vm.etch(address(game), code);
    }

    function test_WhaleClaim_All100Levels_Cold() public {
        uint256 beforeGas = gasleft();
        game.claimWhalePass(BUYER);
        emit log_named_uint("QUEUE_WHALE_CLAIM_100_LEVELS", beforeGas - gasleft());
        vm.etch(address(game), type(QueuePackingGasSeeder).runtimeCode);
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint80 owed = QueuePackingGasSeeder(payable(address(game))).queued(lvl, BUYER);
            assertEq(uint32(owed >> 8), 4, "all 100 levels must receive entries");
            assertGt(owed >> 48, 1, "gas fixture must use a nonzero registry index");
        }
    }
}
