// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameWhaleModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @dev Stand-in for the Game facade's code: forwards every call by delegatecall into the real
///      whale module, so `purchaseWhalePassForSdgnrs_g470` runs in the Game's storage context
///      exactly as the AFKing stage nests it. `vm.etch` keeps the Game's storage.
contract SaturationWhaleForwarder is DegenerusGameStorage {
    function currentDayView_g542950() external view returns (uint24) {
        return dailyIdx;
    }

    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }

    fallback() external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(32, data), mload(data)) }
            return(add(32, data), mload(data))
        }
    }
}

/// @title LevelCountSaturation
/// @notice A saturated mint-level count must not revert pass activation: the claim, the lazy pass
///         and the automatic sDGNRS whale purchase (a mining-stage call) all saturate the add at
///         the uint24 maximum.
contract LevelCountSaturation is DeployProtocol {
    uint24 private constant MAX = type(uint24).max;
    uint256 private constant LEVEL_OFFBYTES = 12; // `level` uint24 @ slot 0, byte 12

    bytes private _facadeCode;
    address private alice = address(0xA11CE);

    function setUp() public {
        _deployProtocol();
        _facadeCode = address(game).code;
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
    }

    function _count(address who) private view returns (uint24) {
        return uint24((game.mintPackedFor(who) >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24);
    }

    function _setCount(address who, uint24 count) private {
        bytes32 slot = GameSlotKeys.mintPacked(game.walletIdOf_g3120(who));
        uint256 word = uint256(vm.load(address(game), slot));
        word &= ~(BitPackingLib.MASK_24 << BitPackingLib.LEVEL_COUNT_SHIFT);
        word |= uint256(count) << BitPackingLib.LEVEL_COUNT_SHIFT;
        vm.store(address(game), slot, bytes32(word));
    }

    function test_lazyPass_succeedsWithSaturatedCount() public {
        _giveWalletId(alice);
        _setCount(alice, MAX);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        assertEq(_count(alice), MAX, "count stays saturated");
    }

    function test_lazyPass_clampsInsteadOfWrapping() public {
        _giveWalletId(alice);
        _setCount(alice, MAX - 3);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        assertEq(_count(alice), MAX, "10 levels past MAX - 3 clamp to MAX");
    }

    function test_claimWhalePass_succeedsWithSaturatedCount() public {
        uint32 id = _giveWalletId(alice);
        _setCount(alice, MAX);
        bytes32 element = GameSlotKeys.walletElement(id);
        vm.store(address(game), element, bytes32(uint256(vm.load(address(game), element)) + (uint256(2) << 192)));
        game.claimWhalePass(id);
        assertEq(_count(alice), MAX, "count stays saturated");
        assertEq(uint256(vm.load(address(game), element)) >> 192, 0, "half passes consumed");
    }

    function test_sdgnrsWhaleDelivery_succeedsWithSaturatedCount() public {
        _setCount(ContractAddresses.SDGNRS, MAX);
        uint24 day = game.currentDayView_g542950();
        _setLevel(1);
        _setClaimable(ContractAddresses.SDGNRS, 48 ether);
        vm.etch(address(game), address(new SaturationWhaleForwarder()).code);
        uint256 paid = IDegenerusGameWhaleModule(address(game)).purchaseWhalePassForSdgnrs_g470(day);
        vm.etch(address(game), _facadeCode);
        assertEq(paid, 5, "five paid passes delivered");
        assertEq(_count(ContractAddresses.SDGNRS), MAX, "count stays saturated");
    }

    function _setLevel(uint24 lvl) private {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (lvl > uint24(s0 >> (LEVEL_OFFBYTES * 8))) TQ.retireCompleted(address(game), lvl + 1);
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= uint256(lvl) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    /// @dev Claimable (low 128 bits) set to `amount`, with claimablePool moved in tandem.
    function _setClaimable(address who, uint256 amount) private {
        uint256 mask128 = (uint256(1) << 128) - 1;
        bytes32 slot = GameSlotKeys.balances(game.walletIdOf_g3120(who));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 prev = packed & mask128;
        vm.store(address(game), slot, bytes32((packed & ~mask128) | amount));

        bytes32 poolSlot = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 p1 = uint256(vm.load(address(game), poolSlot));
        uint256 pool = (p1 >> 128) + amount - prev;
        vm.store(address(game), poolSlot, bytes32((p1 & mask128) | (pool << 128)));
    }
}
