// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";

contract SeedInputSeeder is DegenerusGame {
    function seed(address player, uint256 word, uint256 amount, bool presale) external {
        // Reaching level 10 means every earlier level's queues materialized. Queue slots recycle
        // 1..100 under a level tag (c729ecfc9): an unretired genesis queue would refuse the
        // box's own future-level queue binding.
        TQ.retireCompleted(address(this), 10);
        level = 10;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((2) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(1) + 1) & 1) << 12);
        rngWordCurrent = word; _setRngSessionPublished(true); _setRngComplete(false);
        // A delivered read cohort reaches its human boxes only after its tickets materialized
        // (consumer order: tickets, redemption, AFKing, human boxes; 60d31f775).
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        boxCursor = 0;
        if (presale) presaleBoxEth[1][player] = amount;
        else lootboxOrder[1][player] = (uint256(10) << LB_LEVEL_SHIFT) |
            (uint256(1) << LB_CUSTOM_COUNT_SHIFT) |
            ((amount / LB_CUSTOM_SCALE) << LB_CUSTOM_SIZE_SHIFT);
        // Box-order migration: the removed per-(player,index) `openBox` read the leg mappings
        // above directly; its sweep replacement only ever finds a box by walking
        // boxPlayers[index & 1], which a real purchase pushes to on first deposit. This seeder
        // forges the leg mappings straight, so enqueue here too (index 1 is already finalized
        // above via LR_INDEX = 2, and index/cursor default to 1/0 on a fresh deploy).
        boxPlayers[1].push(player);
    }

    function afking(address player, uint256 amount, uint256 word) external {
        (bool ok, bytes memory result) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeCall(IDegenerusGameLootboxModule.resolveAfkingBox, (player, amount, uint24(100), word, uint16(0)))
        );
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
}

/// @dev Compare production resolutions from identical snapshots. Value is allowed to size
///      awards; it must not choose a different target-level roll or presale reward branch.
contract RandomnessSeedInputsTest is DeployProtocol {
    address private constant PLAYER = address(0xB0B);
    bytes32 private constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant PRESALE = keccak256("PresaleBoxOpened(address,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 private constant SPIN = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(SeedInputSeeder).runtimeCode);
        vm.deal(address(game), 100 ether);
        vm.deal(address(sdgnrs), 100 ether);
    }

    function _resolve(uint8 route, uint256 word, uint256 amount) private returns (uint256 result) {
        SeedInputSeeder host = SeedInputSeeder(payable(address(game)));
        host.seed(PLAYER, word, amount, route == 3);
        vm.recordLogs();
        if (route == 0 || route == 3) game.mineFlip();
        else if (route == 1) host.afking(PLAYER, amount, word);
        else {
            vm.prank(address(sdgnrs));
            game.resolveRedemptionLootbox{value: amount}(PLAYER, amount, word, 0);
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        // The box's own result is the first one emitted. A capped ETH spin recirculates its
        // excess into a further box whose events follow; that box is not this draw's identity.
        for (uint256 i; i < logs.length && !found; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (route == 3 && logs[i].topics[0] == PRESALE) {
                (, , uint256 dgnrs, uint256 wwxrp, , ,) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                result = dgnrs != 0 ? 1 : wwxrp != 0 ? 2 : 0;
                found = true;
            } else if (route != 3 && logs[i].topics[0] == OPENED) {
                (, uint24 target,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                result = target;
                found = true;
            } else if (route != 3 && logs[i].topics[0] == SPIN) {
                (uint64 betId,,,) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                // The box-spin id is derived from its seed; payout and survival are not identity.
                result = uint256(betId) | (uint256(1) << 255);
                found = true;
            }
        }
        assertTrue(found, "production resolution emitted its result");
    }

    function testFuzz_BoxAmountDoesNotRerollIdentity(uint256 word, uint8 routeSeed) public {
        // Final words 0 and 1 are never published (they leave a request waiting, 60d31f775):
        // map them into the deliverable domain instead of rejecting runs.
        word = word < 2 ? word + 2 : word;
        uint8 route = routeSeed % 4;
        if (route != 3) {
            uint256 seed = route == 0
                ? uint256(keccak256(abi.encode(word, PLAYER, uint256(0x426f784f70656e), uint256(1))))
                : route == 1
                    ? uint256(keccak256(abi.encode(word, PLAYER, uint256(0x41666b696e67426f78), uint256(100))))
                    : uint256(keccak256(abi.encode(word, PLAYER, uint256(0x526564656d7074696f6e426f78))));
            uint256 rewardRoll = uint16(seed >> 40) % 20;
            // Pass denomination intentionally chooses passes or a fallback spin from
            // the award size. Compare identity only when both sizes take the same branch.
            vm.assume(rewardRoll != 15 && rewardRoll != 16);
        }
        uint256 snapshot = vm.snapshotState();
        uint256 first = _resolve(route, word, 1 ether);
        vm.revertToState(snapshot);
        assertEq(_resolve(route, word, 2 ether), first, "amount must not change the draw");
    }

    /// @dev Pinned seed whose ETH spin caps at 2 ETH and recirculates the excess into a further box.
    function test_BoxAmountIdentityWithCappedSpinRecirculation() public {
        testFuzz_BoxAmountDoesNotRerollIdentity(18720, 108);
    }
}
