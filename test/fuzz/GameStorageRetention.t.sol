// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

contract GameRetentionHarness is DegenerusGameRngUtils {
    function stamp(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function append(uint24 lvl, uint8 trait, uint32 id, uint256 count, bool lanes) external {
        if (lanes) _bucketAppendLanes(_traitBufferBase(lvl), trait, id, 1, lvl);
        else _bucketAppendRun(_traitBufferBase(lvl), trait, id, count, lvl);
    }
    function bitmap(uint24 lvl) external view returns (uint256 logical, uint256 physical, uint8 stale) {
        return (_traitBitmap(lvl), traitBucketLive[lvl & 1], traitBucketStale);
    }
    function length(uint24 lvl, uint8 trait) external view returns (uint256) {
        return _bucketLengthUnchecked(lvl, trait);
    }
    function idAt(uint24 lvl, uint8 trait, uint256 index) external view returns (uint32) {
        return _bucketIdAtUnchecked(lvl, trait, index);
    }
    function extsload_g8132(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
    function swapFoil() external { _swapFoilSlot(); }
    function foilWord() external view returns (uint256 word) {
        assembly ("memory-safe") { word := sload(foilCursor.slot) }
    }
    function seedSeventhClose(uint128 claimable, uint128 afking) external {
        degenesisClosed = 6;
        degenesisActive = 0;
        degenesisDays[7] = 0;
        balancesPacked[SDGNRS_WALLET_ID] = uint256(claimable) | (uint256(afking) << 128);
        claimablePool = claimable + afking;
    }
    function closeSeventh() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(
            abi.encodeWithSignature("prepareDegenesis_g47(uint24)", GameTimeLib.MAIN_LAUNCH_DAY)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
    function balances() external view returns (uint128 claimable, uint128 afking, uint128 pool) {
        uint256 packed = balancesPacked[SDGNRS_WALLET_ID];
        return (uint128(packed), uint128(packed >> 128), claimablePool);
    }
}

contract RetainedBoonHarness is DegenerusGameBoxModule {
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16) { return _consumeActionBoon(id); }
    function seed(uint256 s0) external { boonPacked[7].slot0 = s0; }
    function today() external view returns (uint24) { return _gameDay(); }
    function setDay(uint24 day) external { dailyIdx = day; }
}

contract RetainedTicketBudgetHarness is DegenerusGameJackpotModule {
    function seedDone(uint8 kind) external {
        dailyTicketBudgetsPacked = DAILY_TICKET_BUDGET_RETAINED | (uint256(1) << 8);
        dailyJackpotCoinTicketsPending = true;
        _startJackpotWork(0, 0, 1, kind, 4, false, false);
    }
    function budget() external view returns (uint256) { return dailyTicketBudgetsPacked; }
}

contract GameRetentionTest is Test {
    uint256 private constant RETAINED = uint256(1) << 255;
    GameRetentionHarness private h;
    DegenerusGameLens private lens;

    function setUp() public {
        h = new GameRetentionHarness();
        lens = new DegenerusGameLens();
    }

    function test_BoonConsumeAndExpiryRetainSlotZero() public {
        vm.etch(ContractAddresses.GAME, address(new RetainedBoonHarness()).code);
        RetainedBoonHarness boon = RetainedBoonHarness(ContractAddresses.GAME);
        boon.setDay(1);
        uint24 day = boon.today();
        boon.seed(RETAINED | day | (uint256(3) << 48));
        assertEq(boon.consumeCoinflipBoon_g2902(7), 2500);
        (uint256 s0,) = boon.boonPacked(7);
        assertEq(s0, RETAINED);
        assertFalse(boon.checkAndClearExpiredBoon(7), "sentinel is not a live boon");
        boon.seed(RETAINED | (uint256(day) << 200) | (uint256(3) << 248));
        vm.warp(block.timestamp + 5 days);
        boon.setDay(day + 5);
        assertFalse(boon.checkAndClearExpiredBoon(7));
        (s0,) = boon.boonPacked(7);
        assertEq(s0, RETAINED, "whale expiry preserves bit 255");
    }

    function test_LastDailyTicketStageRetainsBudgetWord() public {
        RetainedTicketBudgetHarness jackpot = new RetainedTicketBudgetHarness();
        jackpot.seedDone(6);
        jackpot.runDailyJackpotTickets(123, 5_000_000);
        assertEq(jackpot.budget(), uint256(1) << 73);
    }
}

contract DegenesisExcessRetentionTest is DeployProtocol {
    GameRetentionHarness private h;
    bytes32 private constant EXCESS_EVENT = keccak256("DegenesisAfkingExcessClaimable(uint256)");

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), address(new GameRetentionHarness()).code);
        h = GameRetentionHarness(address(game));
    }

    function test_FoilCursorWordRetainedAcrossEmptySwaps() public {
        uint256 beforeWord = h.foilWord();
        assertGt(beforeWord, 0, "constructor allocates retained cursor word");
        h.swapFoil();
        assertGt(h.foilWord(), 0);
        h.swapFoil();
        assertEq(h.foilWord(), beforeWord, "empty round-trip never clears the sentinel");
    }

    function test_SeventhCloseMovesOnlyExcessAboveTenEth() public { _close(15 ether); }
    function test_SeventhCloseKeepsExactlyTenEth() public { _close(10 ether); }
    function test_SeventhCloseKeepsBelowTenEth() public { _close(8 ether); }

    function _close(uint128 afking) private {
        uint128 claimable = uint128(3 ether + 1);
        h.seedSeventhClose(claimable, afking);
        vm.recordLogs();
        h.closeSeventh();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 excess = afking > 10 ether ? afking - 10 ether : 0;
        (uint128 afterClaimable, uint128 afterAfking, uint128 pool) = h.balances();
        assertEq(afterClaimable, uint256(claimable) + excess);
        assertEq(afterAfking, uint256(afking) - excess);
        assertEq(pool, uint256(claimable) + afking, "reclassification leaves pool total unchanged");
        uint256 events;
        uint256 spentEvents;
        uint256 creditEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("AfkingSpent(uint32,uint256)")) {
                ++spentEvents;
                assertEq(uint256(logs[i].topics[1]), 2);
                assertEq(abi.decode(logs[i].data, (uint256)), excess);
            }
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("PlayerCredited(uint32,uint256)")) {
                ++creditEvents;
                assertEq(uint256(logs[i].topics[1]), 2);
                assertEq(abi.decode(logs[i].data, (uint256)), excess);
            }
            if (logs[i].emitter == address(game) && logs[i].topics[0] == EXCESS_EVENT) {
                ++events;
                assertEq(abi.decode(logs[i].data, (uint256)), excess);
            }
        }
        assertEq(events, excess == 0 ? 0 : 1);
        assertEq(spentEvents, events);
        assertEq(creditEvents, events);
        h.closeSeventh();
        (uint128 twiceClaimable, uint128 twiceAfking, uint128 twicePool) = h.balances();
        assertEq(twiceClaimable, afterClaimable);
        assertEq(twiceAfking, afterAfking);
        assertEq(twicePool, pool);
    }
}
