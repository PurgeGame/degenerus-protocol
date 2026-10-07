// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";

/// @dev Explicit empty dependencies, with counters proving the selected transitions ran.
///      Unknown selectors revert. These stubs do not establish dependency integration safety.
contract FSMEmptyDependencies {
    uint256 public requests;
    uint256 public settlements;
    uint24 public lastSettlementDay;
    uint256 public battleLocks;
    uint256 public charityPicks;
    uint256 public burns;

    function requestRandomWords(VRFRandomWordsRequest calldata) external returns (uint256) {
        return ++requests;
    }

    function isVaultOwner(address) external pure returns (bool) {
        return true;
    }

    function minerMaintenancePending() external pure returns (bool) { return false; }

    /// @dev sDGNRS read-consumer probe (`_rngConsumerStage`): no live redemption.
    function redemptionSettlementPending() external pure returns (bool) { return false; }

    // Checkpoint witnesses written by the empty jackpot legs at the moment each runs, so a single
    // composed mineFlip (60d31f775) still proves what the day looked like at each checkpoint.
    uint256 public battles;
    uint256 public dailies;
    uint24 public battleSealedDay;
    uint256 public battleDayWord;
    uint256 public settlementsAtBattle;
    uint256 public battlesAtDaily;
    uint24 public dailySealedDay;

    function noteBattle(uint24 sealedDay, uint256 dayWord) external {
        ++battles;
        battleSealedDay = sealedDay;
        battleDayWord = dayWord;
        settlementsAtBattle = settlements;
    }

    function noteDaily(uint24 sealedDay) external {
        ++dailies;
        battlesAtDaily = battles;
        dailySealedDay = sealedDay;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function poolBalance(IsDGNRS.Pool) external pure returns (uint256) {
        return 0;
    }

    function affiliateTop(uint24) external pure returns (uint32, uint96) {
        return (0, 0);
    }

    function closeRedemptionBatch(uint256) external pure returns (uint256) { return 0; }
    function resolveTerminalRedemptions() external pure {}

    function burnAtGameOver() external {
        ++burns;
    }

    function tombstoneAtGameOver() external {
        ++burns;
    }

    function lockJackpotBattle(uint24, uint256, uint24) external {
        ++battleLocks;
    }
    function openBonusDay() external pure {}

    function pickCharity(uint24) external {
        ++charityPicks;
    }
    function rollDailyQuest(uint24, uint256, bool, bool, bool) external pure {}

    function processCoinflipPayouts(uint8, uint256, uint24 day) external {
        ++settlements;
        lastSettlementDay = day;
    }

    uint24 public gapStart;
    uint24 public gapEnd;

    /// @dev Stalled days settle in one compact gap call over [start, end) (60d31f775), one
    ///      settlement per skipped day.
    function processCoinflipGap(uint256, uint24 start, uint24 end) external {
        settlements += end - start;
        gapStart = start;
        gapEnd = end;
    }
}

/// @dev Empty battle/daily legs only, at the engine's current checkpointed selectors (60d31f775).
///      This stub changes no field being proved; the actual Advance module performs the dailyIdx
///      write and request unlock after this leg returns. Each leg reports the sealed day (and the
///      battle the day's word) to the dependency witness at the moment it runs.
contract FSMEmptyJackpotModule is DegenerusGameStorage {
    function runPurchaseJackpotBattle(uint24, uint256, uint256) external returns (MineFlipGas.Result memory result) {
        FSMEmptyDependencies(ContractAddresses.COINFLIP).noteBattle(dailyIdx, _recordedDailyWord(rngRequestDay));
        dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING;
        result.progressed = true;
        result.done = true;
    }
    function runDailyJackpot(bool, uint24, uint256, uint256) external returns (MineFlipGas.Result memory result) {
        FSMEmptyDependencies(ContractAddresses.COINFLIP).noteDaily(dailyIdx);
        result.progressed = true;
        result.done = true;
    }
}

/// @dev Test setup and read access only; all three claimed state transitions execute production
///      Advance/GameOver bytecode. Recording a delivered word models the VRF callback input.
contract FSMAdvanceHarness is DegenerusGameMinerModule {
    /// @dev Mirrors only the Game retry forwarding stub; Admin ownership is covered by
    ///      DailyRngStallRecovery using the actual Admin contract.
    function retryRng() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
    function seed(uint24 initialLevel, uint24 initialDay, uint24 purchaseDay, bool lastPurchase) external {
        level = initialLevel;
        dailyIdx = initialDay;
        purchaseStartDay = purchaseDay;
        lastPurchaseDay = lastPurchase;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = _simulatedDayIndex();
        lootboxRngPacked = 0;
        // vm.etch does not run Storage's inline initializers. Install the same idle
        // genesis authority and nonzero waiting metadata before invoking production transitions.
        rngFlagsAndNudges = (uint16(1) << 8) | (uint16(1) << 15);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = 1;
        vrfRequestId = 1;
        humanReadComplete = true;
        vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
    }

    function recordDeliveredWord(uint256 word) external {
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
    }

    /// @dev An empty game whose deterministic ending is latched and whose (empty) tally is
    ///      complete, ended by the production terminal worker mineFlip's Terminal stage runs.
    function drainEmptyDeadGame(uint24 day) external {
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
        deadTallyStage = 3;
        (bool ok,) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeCall(DegenerusGameGameOverModule.runGameOverAdvance, (day, level, gasleft()))
        );
        require(ok, "empty terminal drain failed");
    }

    function sealedDay() external view returns (uint24) {
        return dailyIdx;
    }

    function requestState() external view returns (bool, uint48, uint256) {
        return (rngLockedFlag, rngRequestTime, vrfRequestId);
    }

    function requestActive() external view returns (bool) { return _rngRequestActive(); }
    function retrySpent() external view returns (bool) { return _rngRetrySpent(); }

    function wordAt(uint24 day) external view returns (uint256) {
        return _recordedDailyWord(day);
    }

    function battlePending() external view returns (bool) {
        return _jackpotBattlePending();
    }
}

/// @title Bounded production FSM transitions and separate arithmetic models
/// @notice The first three checks execute actual production state writers under explicit empty
///         dependency stubs. They are not universal proofs over all functions or reachable states.
/// @dev Terminal covers empty drain then one advance before the 30-day sweep; level covers a fresh
///      last-purchase request plus its single same-day retry; dailyIdx covers a 0..7-day gap and a
///      complete empty purchase-day seal at two boundary days. The Foundry carrier retains all uint16 days.
///      The five remaining checks are copied arithmetic models,
///      not production accounting proofs. Foundry fuzz wrappers exercise the same bounded carriers.
///      halmos --contract GameFSMSymbolicTest --loop 8 --solver-timeout-assertion 120000
contract GameFSMSymbolicTest is Test {
    FSMAdvanceHarness private machine;

    function setUp() public {
        // Etching avoids the production module's deployment size constraint on test-only accessors.
        machine = FSMAdvanceHarness(ContractAddresses.GAME);
        vm.etch(address(machine), type(FSMAdvanceHarness).runtimeCode);
        vm.deal(address(machine), 0);
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, type(DegenerusGameGameOverModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, type(DegenerusGameAdvanceModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_RNG_MODULE, type(DegenerusGameRngModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, type(FSMEmptyJackpotModule).runtimeCode);
        // The engine drains the (empty) ticket queues and the delivered cohort's (empty) human
        // boxes on its own path (60d31f775); both run production bytecode.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(DegenerusGameTicketModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_AFKING_MODULE, type(GameAfkingModule).runtimeCode);
        bytes memory deps = type(FSMEmptyDependencies).runtimeCode;
        vm.etch(ContractAddresses.VRF_COORDINATOR, deps);
        vm.etch(ContractAddresses.VAULT, deps);
        vm.etch(ContractAddresses.STETH_TOKEN, deps);
        vm.etch(ContractAddresses.SDGNRS, deps);
        vm.etch(ContractAddresses.AFFILIATE, deps);
        vm.etch(ContractAddresses.GNRUS, deps);
        vm.etch(ContractAddresses.COIN, deps);
        vm.etch(ContractAddresses.COINFLIP, deps);
        vm.etch(ContractAddresses.CRAPS, deps);
        vm.etch(ContractAddresses.QUESTS, deps);
        vm.etch(ContractAddresses.GAME_MINT_MODULE, deps);
    }

    function _dayStart(uint24 day) private pure returns (uint256) {
        return (uint256(day) - 1 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;
    }

    /// @dev A production revert is an assertion failure, including panic codes that Halmos's
    ///      default assertion-only panic filter would otherwise treat as discarded paths.
    function _mustCall(bytes memory data) private returns (bytes memory result) {
        bool ok;
        (ok, result) = address(machine).call(data);
        assert(ok);
    }

    function check_emptyTerminal_latchAndAdvance(uint16 initialLevel, uint8 elapsedDays) public {
        vm.assume(elapsedDays < 30);
        vm.warp(_dayStart(50) + 120);
        machine.seed(initialLevel, 10, 10, false);
        assert(!machine.gameOver());
        _mustCall(abi.encodeCall(FSMAdvanceHarness.drainEmptyDeadGame, (50)));
        assert(machine.gameOver());
        assert(FSMEmptyDependencies(ContractAddresses.COIN).burns() == 1);
        vm.warp(block.timestamp + uint256(elapsedDays) * 1 days);
        // Before the 30-day sweep a finished ending has no engine work: mineFlip reverts NoWork and
        // changes nothing (an idle engine refuses the call instead of returning, be793ed7c).
        (bool ok, bytes memory result) = address(machine).call(abi.encodeCall(DegenerusGameMinerModule.mineFlip, ()));
        assert(!ok);
        assert(result.length == 4 && bytes4(result) == DegenerusGameMinerModule.NoWork.selector);
        assert(machine.gameOver());
        assert(machine.sealedDay() == 10);
        assert(machine.level() == initialLevel);
    }

    /// @dev More branch-solving time prunes impossible queue-loop continuations; no input restriction.
    /// @custom:halmos --solver-timeout-branching 100ms
    function check_lastPurchase_promotesOnceAcrossRetry(uint16 initialLevel) public {
        vm.warp(_dayStart(31) + 120);
        machine.seed(initialLevel, 30, 30, true);
        _mustCall(abi.encodeCall(DegenerusGameMinerModule.mineFlip, ()));
        assert(machine.level() == uint24(initialLevel) + 1);
        (bool locked, uint48 requestTime, uint256 requestId) = machine.requestState();
        assert(locked && requestId == 1);
        assert(FSMEmptyDependencies(ContractAddresses.VRF_COORDINATOR).requests() == 1);
        assert(FSMEmptyDependencies(ContractAddresses.GNRUS).charityPicks() == 1);
        assert(FSMEmptyDependencies(ContractAddresses.CRAPS).battleLocks() == 1);

        vm.warp(block.timestamp + 20 hours + 2);
        vm.prank(ContractAddresses.ADMIN);
        _mustCall(abi.encodeCall(FSMAdvanceHarness.retryRng, ()));
        (bool stillLocked, uint48 retryTime, uint256 retryId) = machine.requestState();
        assert(stillLocked && retryId == 2);
        assert(FSMEmptyDependencies(ContractAddresses.VRF_COORDINATOR).requests() == 2);
        assert(retryTime == requestTime && machine.retrySpent());
        assert(machine.level() == uint24(initialLevel) + 1);
        assert(machine.sealedDay() == 30);
        assert(FSMEmptyDependencies(ContractAddresses.GNRUS).charityPicks() == 1);
        assert(FSMEmptyDependencies(ContractAddresses.CRAPS).battleLocks() == 1);
    }

    /// @notice Explicit finite boundary scenarios, not a universal calendar proof.
    /// @dev Covers each gap 0..7 at initial day1 and65535. The full uint16 calendar remains
    ///      covered by the separate Foundry fuzz carrier; its wider symbolic attempt is unproved.
    function check_dailyIdx_boundaryScenarios(uint8 scenario) public {
        vm.assume(scenario < 16);
        for (uint8 gap; gap < 8; ++gap) {
            if (scenario == gap) {
                _dailyIdx_gapThenSeal(1, gap);
                return;
            }
            if (scenario == gap + 8) {
                _dailyIdx_gapThenSeal(type(uint16).max, gap);
                return;
            }
        }
        assert(false);
    }

    function _dailyIdx_gapThenSeal(uint16 initialDay, uint8 gap) private {
        vm.assume(initialDay != 0 && gap <= 7);
        uint24 day = uint24(initialDay) + uint24(gap) + 1;
        vm.warp(_dayStart(day) + 120);
        machine.seed(1, initialDay, initialDay, false);
        _mustCall(abi.encodeCall(DegenerusGameMinerModule.mineFlip, ()));
        assert(machine.sealedDay() == initialDay);
        assert(FSMEmptyDependencies(ContractAddresses.VRF_COORDINATOR).requests() == 1);
        machine.recordDeliveredWord(42);
        // One mineFlip composes the delivered day's checkpoints (60d31f775): publish, tickets, the gap
        // and word application, the battle, the purchase daily and its seal, then the read consumers.
        // The jackpot legs' witnesses record the state each checkpoint saw.
        _mustCall(abi.encodeCall(DegenerusGameMinerModule.mineFlip, ()));
        FSMEmptyDependencies deps = FSMEmptyDependencies(ContractAddresses.COINFLIP);
        uint24 afterGap = gap == 0 ? uint24(initialDay) : day - 1;
        assert(afterGap >= initialDay);
        assert(machine.wordAt(day) == 42);
        assert(deps.settlements() == uint256(gap) + 1);
        assert(deps.lastSettlementDay() == day);
        // The skipped days are exactly the ones between the sealed day and the delivered day.
        if (gap != 0) assert(deps.gapStart() == uint24(initialDay) + 1 && deps.gapEnd() == day);
        else assert(deps.gapEnd() == 0);
        // At the battle checkpoint: the gap was applied, the word recorded, every coinflip day settled.
        assert(deps.battles() == 1);
        assert(deps.battleSealedDay() == afterGap);
        assert(deps.battleDayWord() == 42);
        assert(deps.settlementsAtBattle() == uint256(gap) + 1);
        // The empty battle's own checkpoint completes before the purchase daily runs and seals.
        assert(!machine.battlePending());
        assert(deps.dailies() == 1);
        assert(deps.battlesAtDaily() == 1);
        assert(deps.dailySealedDay() == afterGap);
        assert(machine.sealedDay() == day);
        (bool locked, uint48 requestTime, uint256 requestId) = machine.requestState();
        assert(!locked && !machine.requestActive() && requestTime != 0 && requestId == 1);
        assert(machine.level() == 1);
        assert(FSMEmptyDependencies(ContractAddresses.COINFLIP).settlements() == uint256(gap) + 1);
        (bool repeated,) = address(machine).call(abi.encodeCall(DegenerusGameMinerModule.mineFlip, ()));
        assert(!repeated);
        assert(machine.sealedDay() == day);
    }

    function testFuzz_emptyTerminal_latchAndAdvance(uint16 level, uint8 elapsed) public {
        check_emptyTerminal_latchAndAdvance(level, elapsed % 30);
    }

    function testFuzz_lastPurchase_promotesOnceAcrossRetry(uint16 level) public {
        check_lastPurchase_promotesOnceAcrossRetry(level);
    }

    function testFuzz_dailyIdx_gapThenSeal(uint16 day, uint8 gap) public {
        _dailyIdx_gapThenSeal(day == 0 ? 1 : day, gap % 8);
    }

    // =========================================================================
    // Property 4: Sentinel pattern correctness
    // =========================================================================

    /// @notice claimableWinnings sentinel: after claim, value is exactly 1
    function check_sentinel_claim(uint256 amount) public pure {
        // Model the _claimWinningsInternal logic:
        // if (amount <= 1) revert -- skip these
        if (amount <= 1) return;

        // claimableWinnings[player] = 1 (sentinel)
        uint256 afterClaim = 1;
        // payout = amount - 1
        uint256 payout;
        unchecked {
            payout = amount - 1;
        }

        assert(afterClaim == 1);
        assert(payout == amount - 1);
        assert(payout < amount);
        assert(payout > 0); // since amount > 1, payout > 0
    }

    /// @notice claimablePool accounting: payout = amount - 1, pool decremented by payout
    function check_claim_pool_accounting(uint256 claimablePool, uint256 amount) public pure {
        if (amount <= 1) return;
        if (claimablePool < amount - 1) return; // would underflow

        uint256 payout;
        unchecked {
            payout = amount - 1;
        }

        uint256 poolAfter = claimablePool - payout;

        // Pool should decrease by exactly payout
        assert(poolAfter == claimablePool - payout);
        // Pool should retain the 1 wei sentinel contribution
        assert(poolAfter == claimablePool - amount + 1);
    }

    // =========================================================================
    // Property 5: Credit-then-pool invariant
    // =========================================================================

    /// @notice When _creditClaimable adds X to individual, caller must add X to pool
    /// @dev Models the dual-accounting invariant
    function check_credit_pool_balance(uint256 poolBefore, uint256 individualBefore, uint256 creditAmount) public pure {
        if (creditAmount == 0) return;
        if (poolBefore > type(uint256).max - creditAmount) return;
        if (individualBefore > type(uint256).max - creditAmount) return;

        // _creditClaimable: individual += creditAmount
        uint256 individualAfter;
        unchecked {
            individualAfter = individualBefore + creditAmount;
        }

        // Caller: pool += creditAmount
        uint256 poolAfter = poolBefore + creditAmount;

        // Invariant: individual increment == pool increment
        assert(individualAfter - individualBefore == poolAfter - poolBefore);
        assert(individualAfter - individualBefore == creditAmount);
    }

    // =========================================================================
    // Property 6: Pre-reservation accounting (DecimatorModule model)
    // =========================================================================

    /// @notice Decimator: pre-reserve then deduct maintains balance
    function check_decimator_prereserve(
        uint256 poolBefore,
        uint256 poolReserved,
        uint256 ethPortion,
        uint256 lootboxPortion
    ) public pure {
        if (poolReserved == 0) return;
        if (ethPortion + lootboxPortion != poolReserved) return;
        if (poolBefore > type(uint256).max - poolReserved) return;

        // Step 1: Pre-reserve full amount
        uint256 poolAfterReserve = poolBefore + poolReserved;

        // Step 2: Deduct lootbox portion (not claimable)
        if (poolAfterReserve < lootboxPortion) return;
        uint256 poolAfterDeduct = poolAfterReserve - lootboxPortion;

        // Result: pool increased by ethPortion only
        assert(poolAfterDeduct == poolBefore + ethPortion);
    }

    // =========================================================================
    // Property 7: Auto-rebuy return value correctness
    // =========================================================================

    /// @notice When auto-rebuy fires: reserved returned, ethSpent goes to pool
    function check_autorebuy_split(uint256 weiAmount, uint256 reserved, uint256 ethSpent) public pure {
        if (weiAmount == 0) return;
        // rebuyAmount = weiAmount - reserved
        if (reserved > weiAmount) return;
        uint256 rebuyAmount = weiAmount - reserved;

        // ethSpent <= rebuyAmount (baseTickets * ticketPrice <= rebuyAmount)
        if (ethSpent > rebuyAmount) return;

        // dust = rebuyAmount - ethSpent (dropped)
        uint256 dust = rebuyAmount - ethSpent;

        // Conservation: weiAmount = reserved + ethSpent + dust
        assert(reserved + ethSpent + dust == weiAmount);
    }
}
