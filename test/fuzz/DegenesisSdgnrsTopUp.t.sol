// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @dev Test-only stand-in for the Game facade's code at the GAME address: forwards by delegatecall
///      into the real Degenesis module, so `topUpSdgnrsAfking_g318` runs in the Game's storage exactly
///      as the AFKing STAGE nests it. `vm.etch` keeps the Game's storage.
contract DegenesisModuleForwarder {
    fallback() external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(32, data), mload(data)) }
            return(add(32, data), mload(data))
        }
    }
}

interface IDegenesisTopUp {
    function topUpSdgnrsAfking_g318() external;
}

/// @title DegenesisSdgnrsTopUp -- sDGNRS AFKing top-up before the once-per-level whale attempt (check 10)
/// @notice Spec §8: need = max(10 ETH - afking, 0), topUp = min(need, claimable - 1); the whale
///         budget is a quarter of the remaining claimable. A reclassification inside claimablePool,
///         kept when no group is bought; the whale buy spends claimable and leaves AFKing funding
///         as the reserve behind the daily deliveries, which spend claimable first. The unit cases run the module entry
///         in the Game's storage through an etched forwarder; the level-1 cases run the real STAGE
///         on the Degenesis timeline, with sDGNRS's two balances written in storage (claimablePool
///         in tandem) just before the STAGE so the example's numbers are exact.
contract DegenesisSdgnrsTopUp is DegenesisFixture {
    uint8 internal constant ACTION_PREPARE_SUBSCRIPTIONS = 14;
    bytes32 internal constant WHALE_SIG = keccak256("WhalePassPurchased(uint32,uint256,uint256)");
    bytes32 internal constant CLAIMABLE_SPENT_SIG = keccak256("ClaimableSpent(uint32,uint256,uint256,uint8,uint256)");
    bytes32 internal constant AFKING_SPENT_SIG = keccak256("AfkingSpent(uint32,uint256)");

    /// @dev Write sDGNRS's claimable and AFKing halves, moving claimablePool by the backed change
    ///      (claimable above the unbacked 1-wei sentinel, plus AFKing) and backing it with ETH.
    function _setSdgnrs(uint256 claimable, uint256 afking) internal {
        bytes32 key = keccak256(abi.encode(uint256(SDGNRS_ID), GameSlots.BALANCES_PACKED));
        uint256 old = uint256(vm.load(address(game), key));
        uint256 oldBacked = (uint128(old) > 1 ? uint128(old) - 1 : 0) + (old >> 128);
        uint256 newBacked = (claimable > 1 ? claimable - 1 : 0) + afking;
        vm.store(address(game), key, bytes32((afking << 128) | claimable));
        uint256 s1 = _slot(GameSlots.CLAIMABLE_POOL);
        uint256 pool = (s1 >> 128) + newBacked - oldBacked;
        vm.store(address(game), bytes32(GameSlots.CLAIMABLE_POOL), bytes32((s1 & type(uint128).max) | (pool << 128)));
        if (newBacked > oldBacked) vm.deal(address(game), address(game).balance + newBacked - oldBacked);
    }

    function _topUpDirect() internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), address(new DegenesisModuleForwarder()).code);
        IDegenesisTopUp(address(game)).topUpSdgnrsAfking_g318();
        vm.etch(address(game), code);
    }

    // ------------------------------------------------------------------ the module entry

    /// @notice The spec example: 80 ETH claimable and 4 ETH AFKing become 74 and 10; claimablePool
    ///         is unchanged.
    function test_SpecExample_80_4_Becomes_74_10_PoolUnchanged() public {
        _setSdgnrs(80 ether, 4 ether);
        uint256 pool = _claimablePool();
        _topUpDirect();
        assertEq(_claimableOf(SDGNRS_ID), 74 ether, "claimable 74");
        assertEq(_afkingOf(SDGNRS_ID), 10 ether, "AFKing 10");
        assertEq(_claimablePool(), pool, "a reclassification: claimablePool unchanged");
    }

    function test_TopUp_NoOpAtOrAboveTarget() public {
        _setSdgnrs(80 ether, 10 ether);
        _topUpDirect();
        assertEq(_claimableOf(SDGNRS_ID), 80 ether, "no move at the target");
        _setSdgnrs(80 ether, 12 ether);
        _topUpDirect();
        assertEq(_afkingOf(SDGNRS_ID), 12 ether, "not a floor that pulls down");
        assertEq(_claimableOf(SDGNRS_ID), 80 ether, "claimable untouched");
    }

    /// @notice Short claimable moves all but the 1-wei sentinel; sentinel-only claimable moves nothing.
    function test_TopUp_PreservesSentinel() public {
        _setSdgnrs(3 ether, 2 ether);
        uint256 pool = _claimablePool();
        _topUpDirect();
        assertEq(_claimableOf(SDGNRS_ID), 1, "sentinel kept");
        assertEq(_afkingOf(SDGNRS_ID), 5 ether - 1, "everything above it moved");
        assertEq(_claimablePool(), pool, "claimablePool unchanged");
        _setSdgnrs(1, 0);
        _topUpDirect();
        assertEq(_packed(SDGNRS_ID), 1, "nothing to move");
    }

    // ------------------------------------------------------------------ the real STAGE at level 1

    /// @dev Run the Degenesis week with the next pool past 50 ETH (real ticket buys), so the day-9
    ///      request turbos into level 1, then stop at day 10's subscription STAGE (ahead of its
    ///      request), where sDGNRS's first whale attempt runs.
    function _toFirstWhaleAttempt() internal {
        address alice = _player("alice", 70 ether);
        _buyTickets(alice, 6700);
        _drain();
        _driveThrough(GameTimeLib.MAIN_LAUNCH_DAY);
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY + 1, 1 hours);
        _stepTo(ACTION_PREPARE_SUBSCRIPTIONS);
        assertEq(_level(), 1, "fixture: level 1, the first level with a whale attempt");
        uint256 latch = _slot(GameSlots.SDGNRS_BONUS_LEVEL) >> (GameSlots.SDGNRS_BONUS_LEVEL_OFFSET * 8);
        assertEq(uint24(latch), 0, "fixture: no attempt yet (none at level 0)");
    }

    struct StageLog {
        uint256 topUp; // AfkingFunded(sDGNRS) amount
        uint256 claimableAfterTopUp; // ClaimableSpent newBalance of the top-up
        bool bought;
        uint256 passes;
        uint256 price;
        uint256 afkingSpentBeforeWhale;
        uint256 claimableSpent;
    }

    /// @dev The top-up emits ClaimableSpent(sDGNRS, topUp, newBalance) then AfkingFunded(sDGNRS,
    ///      topUp); the whale purchase then emits WhalePassPurchased(sDGNRS, passes, price).
    function _readStage(Vm.Log[] memory logs) internal view returns (StageLog memory r) {
        bool topped;
        uint256 lastClaimableSpent;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics.length < 2 || uint32(uint256(l.topics[1])) != SDGNRS_ID) continue;
            if (l.topics[0] == CLAIMABLE_SPENT_SIG) {
                (uint256 amount, uint256 balance,,) = abi.decode(l.data, (uint256, uint256, uint8, uint256));
                lastClaimableSpent = balance;
                r.claimableSpent += amount;
            } else if (l.topics[0] == AFKING_FUNDED_SIG && !topped) {
                r.topUp = abi.decode(l.data, (uint256));
                r.claimableAfterTopUp = lastClaimableSpent;
                topped = true;
            } else if (l.topics[0] == WHALE_SIG) {
                (r.passes, r.price) = abi.decode(l.data, (uint256, uint256));
                r.bought = true;
            } else if (l.topics[0] == AFKING_SPENT_SIG && !r.bought) {
                r.afkingSpentBeforeWhale += abi.decode(l.data, (uint256));
            }
        }
    }

    /// @notice The spec example at the real first attempt (level 1, 2.4 ETH passes): the top-up
    ///         moves 6 ETH (80/4 -> 74/10), the whale budget is 74/4 = 18.5 ETH, one group of five
    ///         is bought for 12 ETH out of claimable, AFKing is not drawn by the whale buy, and the
    ///         daily delivery then spends claimable, leaving the 10 ETH reserve whole.
    function test_FirstWhaleAttempt_TopsUpThenBuysFromClaimable() public {
        _toFirstWhaleAttempt();
        _setSdgnrs(80 ether, 4 ether);
        vm.recordLogs();
        _drain();
        StageLog memory r = _readStage(vm.getRecordedLogs());
        assertEq(r.topUp, 6 ether, "top-up 6 ETH");
        assertEq(r.claimableAfterTopUp, 74 ether, "claimable 74 after the top-up");
        assertTrue(r.bought, "a 12 ETH group fits 18.5 ETH");
        assertEq(r.passes, 5, "one group");
        assertEq(r.price, 12 ether, "at the early price");
        assertEq(r.afkingSpentBeforeWhale, 0, "the whale buy draws no AFKing funding");
        assertEq(_afkingOf(SDGNRS_ID), 10 ether, "the daily delivery leaves the reserve whole");
        // The same drain can credit jackpot prizes; inspect gross debits, not the net balance.
        assertGt(r.claimableSpent, r.topUp + r.price, "the daily delivery spent claimable after the whale buy");
    }

    /// @notice A top-up is kept when the recalculated budget buys no group: 50 ETH claimable and
    ///         no AFKing become 40/10, and 40/4 = 10 ETH is short of the 12 ETH group.
    function test_FirstWhaleAttempt_TopUpPersistsWhenGroupSkipped() public {
        _toFirstWhaleAttempt();
        _setSdgnrs(50 ether, 0);
        vm.recordLogs();
        _drain();
        StageLog memory r = _readStage(vm.getRecordedLogs());
        assertEq(r.topUp, 10 ether, "topped up to the 10 ETH target");
        assertEq(r.claimableAfterTopUp, 40 ether, "claimable 40");
        assertFalse(r.bought, "no group fits 10 ETH");
        uint256 latch = _slot(GameSlots.SDGNRS_BONUS_LEVEL) >> (GameSlots.SDGNRS_BONUS_LEVEL_OFFSET * 8);
        assertEq(uint24(latch), 1, "the attempt latched level 1");
        assertEq(_afkingOf(SDGNRS_ID), 10 ether, "the top-up stayed in AFKing");
        assertGt(r.claimableSpent, r.topUp, "the daily delivery spent claimable");
    }

    /// @notice No top-up and no whale attempt at level 0: across the Degenesis week sDGNRS's
    ///         deliveries spend claimable first and leave its Degenesis-funded AFKing untouched.
    function test_LevelZero_NoTopUp_DeliveriesSpendClaimableFirst() public {
        address alice = _player("alice", 0);
        _earnCredit(alice, 10 ether);
        _drain();
        _driveDay(2);
        _buyDegenesis(alice, 4 ether);
        _driveDay(3);
        uint256 afking = _afkingOf(SDGNRS_ID);
        assertGt(afking, 0, "fixture: cohort 1 funded sDGNRS");
        _setSdgnrs(100 ether, afking);
        vm.recordLogs();
        _driveThrough(8);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 afkingSpends;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || uint32(uint256(logs[i].topics[1])) != SDGNRS_ID) continue;
            if (logs[i].topics[0] == AFKING_SPENT_SIG) ++afkingSpends;
        }
        assertEq(afkingSpends, 0, "deliveries never draw AFKing while claimable covers them");
        assertGe(_afkingOf(SDGNRS_ID), afking, "AFKing funding untouched");
        assertGt(_readStage(logs).claimableSpent, 0, "deliveries spent claimable");
        assertEq(_level(), 0, "still level 0");
    }
}
