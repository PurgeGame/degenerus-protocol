// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.38;

import {StorageCensusLongRunTest} from "../census/StorageCensusLongRun.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice The census's real lifecycle with paid mining and individually capped calls.
/// @dev Run with FOUNDRY_ISOLATE=true. This is Foundry transaction-isolation evidence,
/// not a paid Geth replay. Rewards stay in the real ledger throughout the whole run;
/// no comparison removes them or resets the resulting state to a zero-fee reference.
contract NativePaidLifecycleTest is StorageCensusLongRunTest {
    uint256 private constant TX_CAP = 16_777_216;
    uint256 private constant BASE_FEE = 1 gwei;
    bytes32 private constant WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");
    bytes32 private constant STAKE = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 private constant TRANSFER = keccak256("Transfer(address,address,uint256)");
    uint32 private keeperId;
    uint32 private calibration;
    uint256 private paidCalls;
    uint256 private minedCalls;
    uint256 private latePaidCalls;
    uint256 private rewardSum;
    uint256 private supplyIncreases;
    uint256 private supplyDecreases;
    address[] private holders;
    mapping(address => bool) private knownHolder;
    mapping(uint24 => uint256) private expectedStake;

    struct Terms {
        uint256 price;
        uint256 rate;
        uint256 factor;
        uint8 first;
    }

    function setUp() public override {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "paid lifecycle requires transaction isolation");
        super.setUp();
        keeperId = _giveWalletId(CENSUS_KEEPER);
        uint256 requestedCalibration = vm.envOr("NATIVE_PAID_MULTIPLIER", uint256(10_000));
        require(requestedCalibration <= type(uint32).max, "calibration does not fit uint32");
        calibration = uint32(requestedCalibration);
        require(calibration == 0 || calibration >= 2_500, "unsupported calibration");
        // FLIP starts with zero circulating supply. Seed every fixture recipient
        // (including later direct float mints); discover further endpoints below.
        _holder(address(this));
        _holder(CENSUS_KEEPER);
        for (uint256 i; i < cast.length; ++i) _holder(cast[i]);
        _holder(address(game));
        _holder(address(coin));
        _holder(address(coinflip));
        _holder(address(vault));
        _holder(address(sdgnrs));
        _holder(address(gnrus));
        _holder(address(affiliate));
        _holder(address(jackpots));
        _holder(address(recordBounty));
        _holder(address(ownerGovernance));
        _holder(address(deityPass));
        _holder(address(wwxrp));
        _holder(address(parimutuel));
        _holder(address(crapsBattle));
        _supply();
    }

    function _terms() private view returns (Terms memory t) {
        t.price = game.mintPrice();
        t.first = game.nextMinerAction();
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_TIME)));
        uint256 requestTime = uint48(packed >> (8 * GameSlots.RNG_REQUEST_TIME_OFFSET));
        uint256 reset = block.timestamp - (block.timestamp - 82_620) % 1 days;
        uint256 due = requestTime > reset ? requestTime : reset;
        uint256 steps = block.timestamp > due ? (block.timestamp - due) / 30 minutes : 0;
        if (steps > 4) steps = 4;
        uint256 rateCap = 500_000_000 * (2 ** steps);
        t.rate = BASE_FEE < rateCap ? BASE_FEE : rateCap;
        t.factor = 3_000 + 4_500 * steps;
        if (game.rngLocked()) t.factor *= 2;
        uint256 pass = game.mintPackedFor(CENSUS_KEEPER);
        uint256 passType = (pass >> 144) & 3;
        if ((pass >> 172) & 1 != 0 ||
            ((passType == 1 || passType == 3) && uint24(pass >> 120) >= game.currentLvl())) {
            t.factor *= 2;
        }
    }

    function _ctx(string memory, bool, address from, address to, uint256 value, bytes memory data)
        internal override returns (bool ok, bytes memory ret)
    {
        bool mining = to == address(game) && bytes4(data) == game.mineRun.selector;
        Terms memory terms;
        if (mining) {
            terms = _terms();
            data = abi.encodeCall(game.mineRun, (calibration));
        }
        _holder(from);
        _holder(to);
        // Recompute before each call because the inherited scenario deliberately
        // mints player floats outside _ctx. No event amount enters this oracle.
        _supply();
        uint256 supplyBefore = coin.totalSupply();
        vm.resumeGasMetering();
        vm.startStateDiffRecording();
        vm.recordLogs();
        uint256 actualCallGas;
        (ok, ret, actualCallGas) = this.cappedTransaction(from, to, value, data);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 creates = this.collectCreations();
        vm.pauseGasMetering();
        censusCreates += creates;
        ++censusTxs;
        if (!ok) ++censusFailedTxs;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.emitter == address(coin) && entry.topics.length == 3 && entry.topics[0] == TRANSFER) {
                // Foundry retains attempted logs even for reverted child frames.
                // Endpoints merely expand the candidate set; read actual balances.
                _holder(address(uint160(uint256(entry.topics[1]))));
                _holder(address(uint160(uint256(entry.topics[2]))));
            }
        }
        _supply();
        uint256 supplyAfter = coin.totalSupply();
        if (!ok) assertEq(supplyAfter, supplyBefore, "rejected action must not change FLIP supply");
        if (supplyAfter > supplyBefore) supplyIncreases += supplyAfter - supplyBefore;
        else supplyDecreases += supplyBefore - supplyAfter;
        if (mining && ok) _paid(terms, logs, actualCallGas);
    }

    function cappedTransaction(address from, address to, uint256 value, bytes calldata data)
        external returns (bool ok, bytes memory ret, uint256 actualCallGas)
    {
        require(msg.sender == address(this));
        // Set after entering this fresh isolated frame: Foundry resets block fee fields
        // at a transaction boundary. The tip must not enter the reward calculation.
        vm.fee(BASE_FEE);
        vm.txGasPrice(BASE_FEE + 2 gwei);
        uint256 intrinsic = 21_000;
        for (uint256 i; i < data.length; ++i) intrinsic += data[i] == 0 ? 4 : 16;
        require(intrinsic < TX_CAP);
        vm.prank(from, from);
        uint256 beforeCall = gasleft();
        (ok, ret) = to.call{gas: TX_CAP - intrinsic, value: value}(data);
        actualCallGas = beforeCall - gasleft();
    }

    function collectCreations() external returns (uint256 count) {
        require(msg.sender == address(this));
        Vm.AccountAccess[] memory access = vm.stopAndReturnStateDiff();
        for (uint256 i; i < access.length; ++i) {
            for (uint256 j; j < access[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = access[i].storageAccesses[j];
                if (a.isWrite && !a.reverted && a.previousValue == 0 && a.newValue != 0) ++count;
            }
        }
    }

    function _holder(address who) private {
        if (who == address(0) || knownHolder[who]) return;
        knownHolder[who] = true;
        holders.push(who);
    }

    function _supply() private view {
        uint256 actualBalances;
        for (uint256 i; i < holders.length; ++i) actualBalances += coin.balanceOf(holders[i]);
        assertEq(actualBalances, coin.totalSupply(), "real FLIP holder balances must sum to circulating supply");
    }

    function _paid(Terms memory t, Vm.Log[] memory logs, uint256 actualCallGas) private {
        uint256 workCount;
        uint256 bountyCount;
        uint256 used;
        uint256 reward;
        uint256 bounty;
        uint256 stakeCount;
        uint256 credit;
        uint256 newTotal;
        uint24 creditDay;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.topics.length == 0) continue;
            if (entry.emitter == address(game) && entry.topics[0] == WORK) {
                assertEq(address(uint160(uint256(entry.topics[1]))), CENSUS_KEEPER, "reward caller");
                uint8 first;
                (first, used, reward) = abi.decode(entry.data, (uint8, uint256, uint256));
                assertEq(first, t.first, "first action uses the pre-call state");
                ++workCount;
            } else if (entry.emitter == address(game) && entry.topics[0] == BOUNTY) {
                (, bounty) = abi.decode(entry.data, (uint8, uint256));
                assertEq(address(uint160(uint256(entry.topics[1]))), CENSUS_KEEPER, "bounty recipient");
                ++bountyCount;
            } else if (entry.emitter == address(coinflip) && entry.topics[0] == STAKE &&
                uint32(uint256(entry.topics[1])) == keeperId) {
                creditDay = uint24(uint256(entry.topics[2]));
                (credit, newTotal) = abi.decode(entry.data, (uint256, uint256));
                ++stakeCount;
            }
        }
        assertEq(workCount, 1, "exactly one completed work event");
        assertLt(used, TX_CAP, "reported execution gas fits the transaction cap");
        assertLe(used, actualCallGas, "reported reward gas cannot exceed independently measured call gas");
        uint256 expected;
        if (t.first != 1 && !game.gameOver() && used > 1_000_000) {
            // Independent legacy 18-decimal equation, normalized only at the boundary.
            uint256 raw = (used - 1_000_000) * t.rate * 1000 ether * t.factor / (t.price * 10_000);
            expected = raw / 1 ether;
            if (raw > 0 && expected == 0) expected = 1;
        }
        assertEq(reward, expected, "independent paid-miner reward equation");
        assertEq(bountyCount, expected == 0 ? 0 : 1, "bounty multiplicity");
        assertEq(bounty, expected, "bounty agrees with independent entitlement");
        assertEq(stakeCount, expected == 0 ? 0 : 1, "keeper receives exactly one reward credit");
        if (expected != 0) {
            assertEq(creditDay, coinflip.requestedDailyIdx() + 1, "credit belongs to the next requested flip day");
            uint256 room = type(uint32).max - expectedStake[creditDay];
            uint256 accepted = expected > room ? room : expected;
            expectedStake[creditDay] += accepted;
            assertEq(credit, accepted, "accepted stake must match remaining capacity");
            assertEq(newTotal, expectedStake[creditDay], "event stake reconciles to ghost ledger");
            assertEq(coinflip.coinflipAmount(CENSUS_KEEPER), expectedStake[creditDay], "real keeper ledger matches entitlement");
            ++paidCalls;
            if (game.currentLvl() >= 10) ++latePaidCalls;
            rewardSum += expected;
        }
        ++minedCalls;
    }

    function _censusEnd() internal override {
        assertGe(game.currentLvl(), TARGET_LEVEL, "paid lifecycle must actually reach level 31");
        assertEq(censusMineReverts, 0, "no unexpected crank revert under the cap");
        assertGt(minedCalls, 100, "non-vacuous capped mining");
        assertGt(paidCalls, 25, "non-vacuous paid mining");
        assertGt(latePaidCalls, 10, "paid mining must continue across mature levels");
        assertGt(supplyIncreases, 0, "real circulating FLIP increases reached");
        assertGt(supplyDecreases, 0, "real circulating FLIP decreases reached");
        console.log("PAID_LIFECYCLE_LEVEL", game.currentLvl());
        console.log("PAID_LIFECYCLE_CALLS", censusTxs);
        console.log("PAID_LIFECYCLE_MINER_CALLS", minedCalls);
        console.log("PAID_LIFECYCLE_PAID_CALLS", paidCalls);
        console.log("PAID_LIFECYCLE_LATE_PAID_CALLS", latePaidCalls);
        console.log("PAID_LIFECYCLE_REWARD", rewardSum);
        console.log("PAID_LIFECYCLE_SUPPLY_INCREASES", supplyIncreases);
        console.log("PAID_LIFECYCLE_SUPPLY_DECREASES", supplyDecreases);
        console.log("PAID_LIFECYCLE_HOLDERS", holders.length);
    }
}
