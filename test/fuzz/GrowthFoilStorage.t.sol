// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "../helpers/QaSlots.sol";

import {GrowthFoilFixture} from "../gas/GrowthFoilHotPathGas.t.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract GrowthFoilStorageTest is GrowthFoilFixture {
    /// @dev The ineligible gate reuses a mint word; compare all combinations of
    /// activity/loyalty, curses-only, quota-only, deity fallback, and afking against its policy.
    function testFuzz_MarketGatePolicy(uint256 mintData, uint24 rawLevel, bool afking, bool deity) public {
        uint24 lvl = uint24(bound(rawLevel, 0, type(uint24).max - 1));
        mintData = deity ? mintData | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT)
            : mintData & ~(uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        vm.mockCall(address(game), abi.encodeWithSignature("mintPackedOfId_g5372(uint32)", pid), abi.encode(mintData));
        vm.store(address(quests), keccak256(abi.encode(uint256(pid), QaSlots.STATE)), bytes32(uint256(afking ? type(uint24).max : 0) << 208));
        uint24 unitsLevel = uint24(mintData >> BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT);
        bool activity = (unitsLevel == lvl || unitsLevel == lvl + 1) && uint16(mintData >> BitPackingLib.LEVEL_UNITS_SHIFT) >= 400;
        uint256 passType = (mintData >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3;
        bool activePass = deity || ((passType == 1 || passType == 3)
            && uint24(mintData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) >= lvl);
        bool liveStreak = uint24(mintData >> BitPackingLib.LEVEL_STREAK_SHIFT) >= 5
            && uint256(uint24(mintData >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT)) + 1 >= lvl;
        bool expectedReward = activePass || (activity && liveStreak) || afking;
        (bool mayBet, bool earnsReward, uint32 gateId) = quests.marketBetGates(game.walletIdOf_g3120(PLAYER), lvl);
        assertEq(earnsReward, expectedReward);
        assertEq(gateId, pid, "the gate preserves the selected wallet ID");
        uint256 gameplayFields = mintData & ((uint256(1) << 224) - 1) & ~(uint256(1) << 147)
            & ~(uint256(31) << BitPackingLib.CURSE_COUNT_SHIFT);
        assertEq(mayBet, expectedReward || gameplayFields != 0);
    }

    function test_FoilZeroSpendStillSyncsAndFloors() public {
        (, , , uint32 snapshot, ) = _foil(0);
        assertEq(snapshot, 0);
        bytes32 word = vm.load(address(quests), keccak256(abi.encode(uint256(pid), QaSlots.STATE)));
        assertEq(uint24(uint256(word) >> 48), DAY);
        assertEq(uint16(uint256(word) >> 72), 12);
    }
}
