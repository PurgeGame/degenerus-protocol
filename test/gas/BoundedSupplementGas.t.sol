// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {BoundedPublicSeeder} from "./BoundedPublicPathGas.t.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract BoundedRngQueueSeeder is CrapsBattleStorage {
    function clearQueue(uint48 index) external {
        uint64[] storage slots = _rngSlots[index];
        assembly ("memory-safe") { sstore(slots.slot, 0) }
        _rngSlotCursor[index] = 1;
    }
    function pending(uint48 index) external view returns (uint256) {
        return _rngSlots[index].length - _rngCursor(index);
    }
    function entrants(uint64 slot) external view returns (uint32) { return uint32(_loadBattle(bytes32(uint256(slot)))); }
}

contract BoundedSupplementGasTest is BoundedDeployProtocol, BoundedGasProbe {
    address private constant PLAYER = address(0xA11CE);
    uint32 private constant BOARD = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    function setUp() public {
        _deployBounded(true);
        vm.etch(address(crapsBattle), vm.getDeployedCode("CrapsBattle.sol:CrapsBattle"));
        vm.warp(block.timestamp + 20 days);
        bytes memory original = address(game).code;
        vm.etch(address(game), vm.getDeployedCode("BoundedPublicPathGas.t.sol:BoundedPublicSeeder"));
        BoundedPublicSeeder(address(game)).seed(PLAYER);
        vm.etch(address(game), original);
        vm.deal(PLAYER, 1000 ether);
        vm.deal(address(game), 1000 ether);
        vm.prank(address(game)); coin.mintForGame(PLAYER, 10_000_000);
        uint24 day = game.currentDayView();
        vm.prank(address(game)); quests.rollDailyQuest(day, 123, false, false, false);
        RecyclingState.seedWriteBuffer(address(game), 1);
    }
    function test_P4_ActualMaximumEditableSlateFlush() public {
        for (uint8 i = 3; i < 20; ++i) {
            vm.startPrank(ContractAddresses.OWNER_GOVERNANCE);
            gnrus.setCharity(i, address(uint160(0xC000 + i)));
            gnrus.setCharity(i, address(uint160(0xD000 + i)));
            vm.stopPrank();
        }
        assertEq(gnrus.pendingEditSet(), ((1 << 20) - 1) ^ 7, "all seventeen mutable slots queued");
        uint24 level = gnrus.currentLevel();
        _measureBounded("P4_actual_flush17", address(gnrus), address(game), 0,
            abi.encodeCall(gnrus.pickCharity, (level)), false);
        assertEq(gnrus.pendingEditSet(), 0, "seventeen edits flushed");
        assertEq(gnrus.currentLevel(), level + 1);
        for (uint8 i = 3; i < 20; ++i) assertEq(gnrus.getCharity(i), address(uint160(0xD000 + i)));
    }
    function _clear(uint48 index) private {
        bytes memory original = address(crapsBattle).code;
        vm.etch(address(crapsBattle), vm.getDeployedCode("BoundedSupplementGas.t.sol:BoundedRngQueueSeeder"));
        BoundedRngQueueSeeder(address(crapsBattle)).clearQueue(index);
        vm.etch(address(crapsBattle), original);
    }
    function _pending(uint48 index) private returns (uint256 count) {
        bytes memory original = address(crapsBattle).code;
        vm.etch(address(crapsBattle), vm.getDeployedCode("BoundedSupplementGas.t.sol:BoundedRngQueueSeeder"));
        count = BoundedRngQueueSeeder(address(crapsBattle)).pending(index);
        vm.etch(address(crapsBattle), original);
    }
    function _field(uint256 period) private returns (uint64 slot) {
        vm.prank(PLAYER); crapsBattle.enterBonusBattle(0, period, BOARD, 1);
        slot = uint64(uint256(game.currentDayView()) * 8 + period + 1);
        bytes memory original = address(crapsBattle).code;
        vm.etch(address(crapsBattle), vm.getDeployedCode("BoundedSupplementGas.t.sol:BoundedRngQueueSeeder"));
        assertGt(BoundedRngQueueSeeder(address(crapsBattle)).entrants(slot), 0, "real field is populated");
        vm.etch(address(crapsBattle), original);
    }
    function _register(string memory label, uint48 index, bool populated) private {
        RecyclingState.seedWriteBuffer(address(game), index);
        vm.prank(address(game)); crapsBattle.openBonusDay();
        uint64 first = _field(1);
        uint64 second = _field(2);
        _clear(index);
        JackpotBattle table = JackpotBattle(address(crapsBattle));
        if (populated) { vm.prank(address(crapsBattle)); table.registerRngSlot(index, first, bytes32(uint256(first))); }
        assertEq(_pending(index), populated ? 1 : 0);
        _measureBounded(label, address(table), address(table), 0,
            abi.encodeCall(table.registerRngSlot, (index, second, bytes32(uint256(second)))), false);
        assertEq(_pending(index), populated ? 2 : 1, "registration appended exactly one field");
    }
    function test_C3_ActualFirstRegistration() public { _register("C3_actual_first", 1, false); }
    function test_C3_ActualSecondRegistration() public { _register("C3_actual_second", 1, true); }
    function test_C3_OppositeBuffer() public { _register("C3_opposite_first", 0, false); }
}
