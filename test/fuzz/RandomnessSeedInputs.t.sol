// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract SeedInputSeeder is DegenerusGame, WalletSeed {
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
        // One sealed entry for `player` at read buffer 1, position 0: a presale-only entry or one
        // custom box of `amount`, at level 10.
        uint256 entry = uint256(_seedWallet(player)) | (uint256(10) << LB_LEVEL_SHIFT);
        if (presale) entry |= amount << LB_PRESALE_SHIFT;
        else entry |= (uint256(1) << LB_CUSTOM_COUNT_SHIFT) | ((amount / LB_SIZE_UNIT) << LB_SIZE_SHIFT);
        uint256[] storage q = boxQueue[1];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            sstore(keccak256(0x00, 0x20), entry)
        }
        boxReadCount = 1;
        boxCursor = 0;
    }

    function afking(address player, uint256 amount, uint256 word) external {
        (bool ok, bytes memory result) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeCall(IDegenerusGameLootboxModule.resolveAfkingBox, (player, _seedWallet(player), amount, uint24(100), word, uint16(0)))
        );
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
}

/// @dev Compare production resolutions from identical snapshots. Value is allowed to size
///      awards; it must not choose a different target-level roll or presale reward branch.
contract RandomnessSeedInputsTest is DeployProtocol {
    address private constant PLAYER = address(0xB0B);
    uint256 private constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    uint256 private constant BOX_OPEN_TAG = 0x426f784f70656e;
    uint256 private constant AFKING_BOX_TAG = 0x41666b696e67426f78;
    bytes32 private constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant PRESALE = keccak256("PresaleBoxOpened(address,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 private constant SPIN = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(SeedInputSeeder).runtimeCode);
        vm.deal(address(game), 100 ether);
        vm.deal(address(sdgnrs), 100 ether);
        _giveWalletId(PLAYER);
    }

    function _resolve(uint8 route, uint256 word, uint256 amount) private returns (uint256 result) {
        SeedInputSeeder host = SeedInputSeeder(payable(address(game)));
        host.seed(PLAYER, word, amount, route == 3);
        vm.recordLogs();
        if (route == 0 || route == 3) game.mineFlip();
        else if (route == 1) host.afking(PLAYER, amount, word);
        else {
            uint32 id = game.walletIdOf(PLAYER);
            vm.prank(address(sdgnrs));
            game.resolveRedemptionLootbox{value: amount}(PLAYER, id, amount, word, 0, 1);
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
            // First-box seeds by route, keyed by the wallet ID: the queued entry at (buffer 1,
            // position 0), the AFKing box at its frozen day 100, the redemption order's box 1.
            uint256 id = game.walletIdOf(PLAYER);
            uint256 seed = route == 0
                ? uint256(keccak256(abi.encode(
                    uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, word, uint256(1), uint256(0)))), id, BOX_OPEN_TAG, uint256(1))))
                : route == 1
                    ? uint256(keccak256(abi.encode(word, id, AFKING_BOX_TAG, uint256(100))))
                    : uint256(keccak256(abi.encode(word, id, BOX_OPEN_TAG, uint256(1))));
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

    /// @dev Pinned queued-entry word (route 0) whose first box draws the ETH spin and recirculates
    ///      part of its payout into a further box; found from the seed formula for the player's
    ///      wallet ID at (buffer 1, position 0).
    function test_BoxAmountIdentityWithCappedSpinRecirculation() public {
        testFuzz_BoxAmountDoesNotRerollIdentity(3, 108);
    }
}
