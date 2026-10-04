// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GrowthFoilFixture} from "../gas/GrowthFoilHotPathGas.t.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract GrowthFoilStorageTest is GrowthFoilFixture {
    function _assertPosition(uint24 round, bool over, bool paid) private view {
        (, , , , uint8 side, bool claimed, , uint256 payout) = parimutuel.marketState(PLAYER, round);
        assertEq(side, over ? 1 : 2);
        assertEq(claimed, paid);
        assertEq(payout, 0);
    }

    /// @dev Every possible lane is exercised, including bit 252 and the next word.
    function test_AllRoundLanesRemainClaimableAcrossWords() public {
        uint24[] memory rounds = new uint24[](65);
        for (uint24 i; i < 65; ++i) {
            rounds[i] = 64 + i;
            _bet(rounds[i], true);
            vm.prank(address(game)); parimutuel.recordGrowth(rounds[i], true);
        }
        assertEq(parimutuel.claim(PLAYER, rounds), 65_000);
        for (uint24 i; i < 65; ++i) _assertPosition(rounds[i], true, true);
        assertEq(parimutuel.claim(PLAYER, rounds), 0);
    }

    function testFuzz_AncientClaimsPreserveSiblingRounds(uint24 rawRound, uint8 rawLane, bool firstOver, bool secondOver) public {
        // Exercise all uint24 storage keys, including the maximum; the live
        // level-quest gate has its own checked level+1 ceiling below that value.
        vm.mockCall(address(quests), abi.encodeWithSelector(quests.marketBetGates.selector, PLAYER), abi.encode(true, false));
        uint24 first = uint24(bound(rawRound, 64, type(uint24).max));
        uint24 second = (first & ~uint24(63)) | uint24(rawLane & 63);
        if (second == first) second ^= 1;
        uint24 distant = first ^ uint24(1 << 23);
        if (distant == 0) distant = 1;
        _bet(first, firstOver); _bet(second, secondOver); _bet(distant, true);
        vm.prank(address(game)); parimutuel.recordGrowth(first, true);
        vm.prank(address(game)); parimutuel.recordGrowth(second, true);
        vm.prank(address(game)); parimutuel.recordGrowth(distant, true);
        uint24[] memory rounds = new uint24[](5);
        rounds[0] = distant; rounds[1] = first; rounds[2] = first; rounds[3] = second; rounds[4] = distant;
        assertEq(parimutuel.claim(PLAYER, rounds), 1_000 * (1 + (firstOver ? 1 : 0) + (secondOver ? 1 : 0)));
        _assertPosition(first, firstOver, firstOver);
        _assertPosition(second, secondOver, secondOver);
        _assertPosition(distant, true, true);
        _open(first); vm.prank(PLAYER); vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        parimutuel.placeBet(PLAYER, !firstOver);
    }

    /// @dev The ineligible gate reuses a mint word; compare all combinations of
    /// activity/loyalty, curses-only, deity fallback, and afking against its policy.
    function testFuzz_MarketGatePolicy(uint256 mintData, uint24 rawLevel, bool afking, bool deity) public {
        uint24 lvl = uint24(bound(rawLevel, 0, type(uint24).max - 1));
        vm.mockCall(address(game), abi.encodeWithSignature("mintPackedFor(address)", PLAYER), abi.encode(mintData));
        vm.mockCall(address(game), abi.encodeWithSignature("hasDeityPass(address)", PLAYER), abi.encode(deity));
        vm.store(address(quests), keccak256(abi.encode(PLAYER, uint256(1))), bytes32(uint256(afking ? 1 : 0) << 104));
        uint24 unitsLevel = uint24(mintData >> 104);
        bool activity = (unitsLevel == lvl || unitsLevel == lvl + 1) && uint16(mintData >> 228) >= 400;
        bool loyalty = uint24(mintData >> 48) >= 5 || (uint24(mintData >> 128) != 0 && ((mintData >> 152) & 3) != 0) || deity;
        bool expectedReward = (activity && loyalty) || afking;
        (bool mayBet, bool earnsReward) = quests.marketBetGates(PLAYER, lvl);
        assertEq(earnsReward, expectedReward);
        assertEq(mayBet, expectedReward || (mintData & ~(uint256(255) << BitPackingLib.CURSE_COUNT_SHIFT)) != 0);
    }

    function test_FoilZeroSpendStillSyncsAndFloors() public {
        (, , , uint32 snapshot, ) = _foil(0);
        assertEq(snapshot, 0);
        bytes32 word = vm.load(address(quests), keccak256(abi.encode(PLAYER, uint256(1))));
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
        bytes32 playerWord = keccak256(abi.encode(PLAYER, uint256(1)));
        vm.store(address(quests), playerWord, bytes32(word));
        if ((seed & 8) != 0) _mintData(ELIGIBLE);
        // Days between the old anchor and today are actual rolled days, so lapse
        // synchronization exercises shields rather than treating all days as stalls.
        for (uint24 day = 2; day <= DAY + 1; ++day) {
            vm.prank(address(game)); quests.rollDailyQuest(day, seed, false, true, false);
        }
        if ((seed & 7) == 0) { spend = 0; flipQty = 0; loot = 0; }
        bytes memory callData = abi.encodeWithSelector(quests.handleFoilPurchase.selector,
            PLAYER, uint256(spend % 1 ether), uint32(flipQty), uint256(loot % 1 ether), 0.05 ether, 0.05 ether);
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs(); vm.prank(address(game));
        (bool okNew, bytes memory retNew) = address(quests).call(callData);
        bytes32 logsNew = keccak256(abi.encode(vm.getRecordedLogs()));
        bytes32 levelWord = keccak256(abi.encode(PLAYER, uint256(3)));
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
