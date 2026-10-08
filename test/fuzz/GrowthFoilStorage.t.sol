// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GrowthFoilFixture} from "../gas/GrowthFoilHotPathGas.t.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract GrowthFoilStorageTest is GrowthFoilFixture {
    /// @dev The ineligible gate reuses a mint word; compare all combinations of
    /// activity/loyalty, curses-only, quota-only, deity fallback, and afking against its policy.
    function testFuzz_MarketGatePolicy(uint256 mintData, uint24 rawLevel, bool afking, bool deity) public {
        uint24 lvl = uint24(bound(rawLevel, 0, type(uint24).max - 1));
        mintData = deity ? mintData | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT)
            : mintData & ~(uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        vm.mockCall(address(game), abi.encodeWithSignature("mintPackedOfId(uint32)", pid), abi.encode(mintData));
        vm.store(address(quests), keccak256(abi.encode(uint256(pid), uint256(1))), bytes32(uint256(afking ? 1 : 0) << 104));
        uint24 unitsLevel = uint24(mintData >> BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT);
        bool activity = (unitsLevel == lvl || unitsLevel == lvl + 1) && uint16(mintData >> BitPackingLib.LEVEL_UNITS_SHIFT) >= 400;
        bool loyalty = uint24(mintData >> 48) >= 5 || (uint24(mintData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) != 0 && ((mintData >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3) != 0) || deity;
        bool expectedReward = (activity && loyalty) || afking;
        (bool mayBet, bool earnsReward, uint32 gateId) = quests.marketBetGates(game.walletIdOf(PLAYER), lvl);
        assertEq(earnsReward, expectedReward);
        assertEq(gateId, pid, "the gate preserves the selected wallet ID");
        uint256 gameplayFields = mintData & ((uint256(1) << BitPackingLib.SMURF_COUNT_SHIFT) - 1)
            & ~(uint256(31) << BitPackingLib.CURSE_COUNT_SHIFT);
        assertEq(mayBet, expectedReward || gameplayFields != 0);
    }

    function test_FoilZeroSpendStillSyncsAndFloors() public {
        (, , , uint32 snapshot, ) = _foil(0);
        assertEq(snapshot, 0);
        bytes32 word = vm.load(address(quests), keccak256(abi.encode(uint256(pid), uint256(1))));
        assertEq(uint24(uint256(word) >> 48), DAY);
        assertEq(uint16(uint256(word) >> 72), 12);
    }

    /// @dev Optional differential oracle: archive the pre-change runtimes and set
    /// CUSTOMER_GROWTH_FOIL_REFERENCE to the JSON file (under contracts/ per Foundry
    /// read permissions). Ordinary runs still execute the independent policy/lane tests.
    function testFuzz_FoilMatchesArchivedRuntime(uint256 seed, uint128 spend, uint16 flipQty, uint128 loot) public {
        string memory path = vm.envOr("CUSTOMER_GROWTH_FOIL_REFERENCE", string(""));
        if (bytes(path).length == 0) { vm.skip(true); return; }
        bytes memory oldCode = vm.parseJsonBytes(vm.readFile(path), ".DegenerusQuests");
        // Vary real packed player fields, including stale progress/completion flags,
        // shield use, streak saturation and afking callback routing.
        uint24 anchor = uint24(seed % DAY);
        uint24 syncDay = uint24((seed >> 8) % (DAY + 1));
        uint256 word = uint256(anchor) | (uint256(anchor) << 24) | (uint256(syncDay) << 48)
            | (uint256(uint16(seed >> 32)) << 72) | (uint256(uint16(seed >> 48)) << 88)
            | (((seed >> 64) & 1) << 104) | (uint256(anchor) << 112) | (uint256(anchor) << 136)
            | (uint256(uint16(seed >> 72)) << 160) | (uint256(uint16(seed >> 88)) << 176)
            | (((seed >> 104) & 3) << 192) | (uint256(uint8(seed >> 112)) << 200)
            | (uint256(uint8(seed >> 120)) << 208);
        bytes32 playerWord = keccak256(abi.encode(uint256(pid), uint256(1)));
        vm.store(address(quests), playerWord, bytes32(word));
        if ((seed & 8) != 0) _mintData(ELIGIBLE);
        // Days between the old anchor and today are actual rolled days, so lapse
        // synchronization exercises shields rather than treating all days as stalls.
        for (uint24 day = 2; day <= DAY + 1; ++day) {
            vm.prank(address(game)); quests.rollDailyQuest(day, seed, false, true, false);
        }
        if ((seed & 7) == 0) { spend = 0; flipQty = 0; loot = 0; }
        bytes memory callData = abi.encodeWithSelector(quests.handleFoilPurchase.selector,
            pid, uint256(spend % 1 ether), uint32(flipQty), uint256(loot % 1 ether), 0.05 ether, 0.05 ether);
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs(); vm.prank(address(game));
        (bool okNew, bytes memory retNew) = address(quests).call(callData);
        bytes32 logsNew = keccak256(abi.encode(vm.getRecordedLogs()));
        bytes32 levelWord = keccak256(abi.encode(uint256(pid), uint256(2)));
        bytes32 stateNew = keccak256(abi.encode(
            vm.load(address(quests), playerWord), vm.load(address(quests), levelWord)
        ));
        uint256 stakeNew = coinflip.coinflipAmount(PLAYER);
        vm.revertToState(snapshot);
        vm.etch(address(quests), oldCode);
        vm.recordLogs(); vm.prank(address(game));
        (bool okOld, bytes memory retOld) = address(quests).call(callData);
        assertEq(okNew, okOld, "success");
        assertEq(retNew, retOld, "return data");
        assertEq(logsNew, keccak256(abi.encode(vm.getRecordedLogs())), "ordered events");
        assertEq(stateNew, keccak256(abi.encode(
            vm.load(address(quests), playerWord), vm.load(address(quests), levelWord)
        )), "daily and level quest state");
        assertEq(stakeNew, coinflip.coinflipAmount(PLAYER), "reward stake");
    }
}
