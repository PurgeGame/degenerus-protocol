// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameMiner} from "../../contracts/modules/GameMiner.sol";

import "forge-std/Test.sol";
import {MinerHarness} from "../helpers/MinerHarness.sol";
import {DegenerusGameDailyModule} from "../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameEndgameModule} from "../../contracts/modules/DegenerusGameEndgameModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
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
    uint256 public vaultSettles;

    function depositCoinflip(uint32 id, uint256 amount) external {
        require(id == 1 && amount == 0, "only the Vault banking checkpoint");
        ++vaultSettles;
    }

    function requestRandomWords(VRFRandomWordsRequest calldata) external returns (uint256) {
        return ++requests;
    }

    function isVaultOwner(address) external pure returns (bool) {
        return true;
    }

    function minerMaintenancePending_g11976() external pure returns (bool) { return false; }

    /// @dev sDGNRS read-consumer probe (`_rngConsumerStage`): no live redemption.
    function redemptionSettlementPending() external pure returns (bool) { return false; }

    // Checkpoint witnesses written by the empty jackpot legs at the moment each runs, so a single
    // composed mineFlip (60d31f775) still proves what the day looked like at each checkpoint.
    uint256 public battles;
    uint24 public battleSealedDay;
    uint256 public battleDayWord;
    uint256 public settlementsAtBattle;

    function noteBattle(uint24 sealedDay, uint256 dayWord) external {
        ++battles;
        battleSealedDay = sealedDay;
        battleDayWord = dayWord;
        settlementsAtBattle = settlements;
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

    function lockJackpotBattle(uint24, uint256, uint24) external returns (bool) {
        ++battleLocks;
        battleComplete = false;
        return true;
    }
    bool private battleComplete;
    function jackpotProgress() external view returns (uint64, uint256, bool, bool) {
        return (0, 0, true, battleComplete);
    }
    function runDailyBattleWork(uint256) external returns (MineFlipGas.Result memory result) {
        FSMAdvanceHarness machine = FSMAdvanceHarness(ContractAddresses.GAME);
        FSMEmptyDependencies(ContractAddresses.COINFLIP).noteBattle(
            machine.sealedDay(), machine.wordAt(machine.requestDay())
        );
        battleComplete = true;
        result.progressed = true;
        result.done = true;
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

    uint24 public requestedDailyIdx;
    function onDailyRequest(uint24 day) external { requestedDailyIdx = day; }

}

/// @dev Test setup and reads only; all daily, RNG and terminal state writers are production code.
contract FSMAdvanceHarness is MinerHarness {
    /// @dev Mirrors only the Game retry forwarding stub; Admin ownership is covered by
    ///      DailyRngStallRecovery using the actual Admin contract.
    function retryRng() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
    function seed(uint24 initialLevel, uint24 initialDay, uint24 purchaseDay, bool lastPurchase) external {
        level = initialLevel;
        degenesisClosed = 7; // These post-bootstrap FSM carriers have no Degenesis work.
        dailyIdx = initialDay;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay() - 1;
        purchaseStartDay = purchaseDay;
        lastPurchaseDay = lastPurchase;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = initialDay + 1;
        lootboxRngPacked = 0;
        // vm.etch does not run Storage's inline initializers. Install the same idle
        // genesis authority and nonzero waiting metadata before invoking production transitions.
        rngFlagsAndNudges = (uint16(1) << 8) | (uint16(1) << 15);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = 1;
        vrfRequestId = 0;
        humanReadComplete = true;
        _redemptionReserveStored = 1;
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

    function complete() external view returns (bool) { return dailyComplete; }

    function sealedDay() external view returns (uint24) {
        return dailyIdx;
    }

    function requestState() external view returns (bool, uint48, uint256) {
        return (rngLockedFlag, rngRequestTime, vrfRequestId);
    }

    function requestDay() external view returns (uint24) { return rngRequestDay; }
    function requestActive() external view returns (bool) { return _rngRequestActive(); }
    function retrySpent() external view returns (bool) { return _rngRetrySpent(); }

    function wordAt(uint24 day) external view returns (uint256) {
        return _recordedDailyWord(day);
    }

    function battlePending() external view returns (bool) {
        return _jackpotBattlePending();
    }
}

/// @title Bounded production FSM transitions, executed by Foundry's EVM
/// @notice Production state writers run under explicit empty dependency stubs. The three
///         carriers retain their uint16 level/day domains and retry/terminal assertions.
/// @dev Halmos 0.3.3 models each GAS opcode as an unconstrained f_gas read: it can increase
///      within a frame or exceed the transaction limit. These metered production paths therefore
///      remain real-EVM fuzz tests, plus all 16 explicit day/gap boundaries. No symbolic gas or
///      universal liveness proof is claimed. Arithmetic-only checks live in the next contract.
contract GameFSMProductionTransitionTest is Test {
    FSMAdvanceHarness private machine;

    function setUp() public {
        // Etching avoids the production module's deployment size constraint on test-only accessors.
        machine = FSMAdvanceHarness(ContractAddresses.GAME);
        vm.etch(address(machine), type(FSMAdvanceHarness).runtimeCode);
        vm.deal(address(machine), 0);
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, type(DegenerusGameEndgameModule).runtimeCode);
        // RNG, Advance and jackpot code share Daily. Stub only the external empty
        // Craps dependency; run the actual consolidated daily state writers.
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, type(DegenerusGameDailyModule).runtimeCode);
        // The engine drains the (empty) ticket queues and the delivered cohort's (empty) human
        // boxes on its own path (60d31f775); both run production bytecode.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(DegenerusGameTicketModule).runtimeCode);
        vm.etch(ContractAddresses.GAME_AFKING_MODULE, type(DegenerusGameBoxModule).runtimeCode);
        bytes memory deps = type(FSMEmptyDependencies).runtimeCode;
        vm.etch(ContractAddresses.VRF_COORDINATOR, deps);
        vm.etch(ContractAddresses.VAULT, deps);
        vm.etch(ContractAddresses.STETH_TOKEN, deps);
        vm.etch(ContractAddresses.SDGNRS, deps);
        vm.etch(ContractAddresses.AFFILIATE, deps);
        vm.etch(ContractAddresses.GNRUS, deps);
        vm.etch(ContractAddresses.DGNRS, deps);
        vm.etch(ContractAddresses.COIN, deps);
        vm.etch(ContractAddresses.COINFLIP, deps);
        vm.etch(ContractAddresses.CRAPS, deps);
        vm.etch(ContractAddresses.QUESTS, deps);
        // Mint aliases Endgame; do not overwrite the production terminal worker.
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

    function _emptyTerminal_latchAndAdvance(uint16 initialLevel, uint8 elapsedDays) private {
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
        (bool ok, bytes memory result) = address(machine).call(abi.encodeCall(MinerHarness.mineFlip, (uint32(0))));
        assert(!ok);
        assert(result.length == 4 && bytes4(result) == GameMiner.NoWork.selector);
        assert(machine.gameOver());
        assert(machine.sealedDay() == 10);
        assert(machine.level() == initialLevel);
    }

    function _lastPurchase_promotesOnceAcrossRetry(uint16 initialLevel) private {
        vm.warp(_dayStart(31) + 120);
        machine.seed(initialLevel, 30, 30, true);
        _mustCall(abi.encodeCall(MinerHarness.mineFlip, (uint32(0))));
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
        assert(machine.sealedDay() == 31);
        assert(FSMEmptyDependencies(ContractAddresses.GNRUS).charityPicks() == 1);
        assert(FSMEmptyDependencies(ContractAddresses.CRAPS).battleLocks() == 1);
    }

    /// @notice Explicit finite reset-delay scenarios with exactly one logical request.
    /// @dev Covers each reset delay 0..7 at logical day 1 and 65535. The uint16 domain remains
    ///      covered by the separate Foundry fuzz carrier; its wider symbolic attempt is unproved.
    function _dailyIdx_boundaryScenario(uint8 scenario) private {
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
        uint24 requested = uint24(initialDay) + 1;
        uint24 wall = requested + uint24(gap);
        vm.warp(_dayStart(wall) + 120);
        machine.seed(1, initialDay, initialDay, false);
        _mustCall(abi.encodeCall(MinerHarness.mineFlip, (uint32(0))));
        assert(machine.sealedDay() == requested);
        FSMEmptyDependencies deps = FSMEmptyDependencies(ContractAddresses.COINFLIP);
        assert(deps.requestedDailyIdx() == requested);
        assert(FSMEmptyDependencies(ContractAddresses.VRF_COORDINATOR).requests() == 1);
        machine.recordDeliveredWord(42);
        vm.recordLogs();
        for (uint256 i; i < 8 && !machine.complete(); ++i)
            _mustCall(abi.encodeCall(MinerHarness.mineFlip, (uint32(0))));
        assert(machine.complete());
        assert(machine.wordAt(requested) == 42);
        assert(deps.settlements() == 1 && deps.lastSettlementDay() == requested);
        assert(deps.battles() == 1);
        assert(deps.battleSealedDay() == requested);
        assert(deps.battleDayWord() == 42 && deps.settlementsAtBattle() == 1);
        assert(!machine.battlePending());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 dailyLegs;
        bool battleFinished;
        bool boardRecorded;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                if (stage == 17) battleFinished = true;
                if (stage == 6) { assert(battleFinished && boardRecorded); ++dailyLegs; }
            }
            if (logs[i].topics[0] == keccak256("DailyWinningTraits(uint24,uint32)")) {
                assert(battleFinished && !boardRecorded);
                assert(uint24(uint256(logs[i].topics[1])) == requested);
                boardRecorded = true;
            }
        }
        assert(dailyLegs == 1 && machine.sealedDay() == requested);
        (bool locked, uint48 requestTime, uint256 requestId) = machine.requestState();
        assert(!locked && !machine.requestActive() && requestTime != 0 && requestId == 0);
        assert(machine.level() == 1);
        (bool repeated,) = address(machine).call(abi.encodeCall(MinerHarness.mineFlip, (uint32(0))));
        assert(!repeated && machine.sealedDay() == requested);
    }

    function testFuzz_emptyTerminal_latchAndAdvance(uint16 level, uint8 elapsed) public {
        _emptyTerminal_latchAndAdvance(level, elapsed % 30);
    }

    function testFuzz_lastPurchase_promotesOnceAcrossRetry(uint16 level) public {
        _lastPurchase_promotesOnceAcrossRetry(level);
    }

    function testFuzz_dailyIdx_gapThenSeal(uint16 day, uint8 gap) public {
        _dailyIdx_gapThenSeal(day == 0 ? 1 : day, gap % 8);
    }

    function test_dailyIdx_AllBoundaryScenarios() public {
        uint256 initialState = vm.snapshotState();
        for (uint8 scenario; scenario < 16; ++scenario) {
            _dailyIdx_boundaryScenario(scenario);
            assertTrue(vm.revertToState(initialState), "restore the same initial machine for every boundary");
        }
    }
}

/// @title Arithmetic accounting models; these are not proofs of complete production flows.
contract GameFSMSymbolicTest is Test {
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

    function test_claimPoolCounterexampleReplay() public pure {
        check_claim_pool_accounting((uint256(1) << 255) - 1, uint256(1) << 255);
        check_claim_pool_accounting(1, 2);
        check_claim_pool_accounting(type(uint256).max, type(uint256).max);
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
        // Group the sentinel subtraction before debiting: pool == amount - 1 is valid.
        // Reconstructing the original pool also checks conservation without an intermediate underflow.
        assert(poolAfter + (amount - 1) == claimablePool);
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
        // Express the existing partition domain without overflowing while checking admission.
        if (ethPortion > poolReserved || lootboxPortion != poolReserved - ethPortion) return;
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
