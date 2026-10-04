// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Craps} from "../../contracts/Craps.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {
    IDegenerusGameDecimatorModule,
    IDegenerusGameRngModule
} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @dev Setup only: the seal, run/rank/pay and request gates are production. The two workers
/// are the engine's own (mineFlip's Decimator and RequestMidday stages), delegatecalled here in
/// the Game's storage as the engine dispatches them. All unrelated consumers start complete,
/// isolating Decimator.
contract UnpushedDecimatorSessionSeeder is DegenerusGameStorage {
    function prime(uint24 lvl, uint256 word, uint128 pool) external {
        level = lvl - 1;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        _recordDailyRng(dailyIdx, word);
        rngWordCurrent = word;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(true);
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        _pendingBoxCount = 0;
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 100_000);
        claimablePool = pool;
        _setDecWindowOpen(true);
        decBattleRounds[lvl].openedDay = dailyIdx;
    }

    function closeWindow() external { _setDecWindowOpen(false); }

    /// @dev The Decimator stage worker; returns its result and the gas the delegatecall used.
    function runDecimator(uint256 allowance) external returns (MineFlipGas.Result memory r, uint256 used) {
        uint256 g0 = gasleft();
        (bool ok, bytes memory data) = ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameDecimatorModule.runDecimatorWork.selector, allowance)
        );
        used = g0 - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        r = abi.decode(data, (MineFlipGas.Result));
    }

    /// @dev The RequestMidday stage worker, the engine's only mid-day request path, for the caller.
    function requestMidday() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_RNG_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameRngModule.requestMinerRng.selector)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function terminalWord(uint256 word) external {
        _setRngTerminal();
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2);
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngComplete(false);
        // Deliberately leave gameOver false: the ending has not paid out yet.
    }
}

/// @dev Equal stacks have equal scores, making every retained ordering decision
/// depend on the session's independently derived tiebreak key.
contract UnpushedDecimatorFlatEngine {
    function settleSlipBounded(uint256, uint256, uint256, uint256, bytes32,
        uint256 bankroll, address, uint256, uint256) external pure returns (Craps.SlipResult memory r)
    {
        r.peakBankroll = bankroll;
        r.totalRolls = 30;
    }
}

contract UnpushedDecimatorRngSafety is DeployProtocol {
    uint24 private constant LVL = 5;
    uint128 private constant POOL = 4 ether;
    uint256 private constant WORD = 0xDEC1A470;
    uint64 private constant COUNT = 40;
    bytes32 private constant COIN = keccak256("decimator.battle.final-coin.v1");
    bytes32 private constant TIE = keccak256("decimator.battle.tie.v1");
    bytes private gameCode;
    bytes private seedCode;
    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 2 days);
        mockVRF.fundSubscription(1, 1000e18);
        lens = new DegenerusGameLens();
        gameCode = address(game).code;
        seedCode = address(new UnpushedDecimatorSessionSeeder()).code;
        _seed(abi.encodeCall(UnpushedDecimatorSessionSeeder.prime, (LVL, WORD, POOL)));
        // The warp leaves scheduled Craps maintenance owed, which also refuses a mid-day request
        // (RngModule: _minerMaintenancePending). Run it through the table's own permissionless
        // keeper while the primed session is complete, so every refusal below answers to the
        // Decimator read consumer alone.
        _quietCrapsTable();
        vm.etch(ContractAddresses.CRAPS_ENGINE, address(new UnpushedDecimatorFlatEngine()).code);
        for (uint64 id = 1; id <= COUNT; ++id) {
            vm.prank(ContractAddresses.COIN);
            game.recordDecBurn(address(uint160(0xD000 + id)), LVL, 1000 ether, 10_000, 0);
        }
        _seed(abi.encodeCall(UnpushedDecimatorSessionSeeder.closeWindow, ()));
        vm.prank(address(game));
        assertEq(game.runDecimatorJackpot(POOL, LVL, WORD), 0);
    }

    function _seed(bytes memory data) private {
        vm.etch(address(game), seedCode);
        (bool ok, bytes memory reason) = address(game).call(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        vm.etch(address(game), gameCode);
    }

    /// @dev One call into the seeder overlay at the game address, `callGas` bounding it (0 = all).
    function _overlay(bytes memory data, uint256 callGas) private returns (bool ok, bytes memory result) {
        vm.etch(address(game), seedCode);
        (ok, result) = callGas == 0 ? address(game).call(data) : address(game).call{gas: callGas}(data);
        vm.etch(address(game), gameCode);
    }

    /// @dev One Decimator stage call with `callGas` as its gas and allowance (0 = all gas).
    function _runDecimator(uint256 callGas) private returns (MineFlipGas.Result memory r, uint256 used) {
        (bool ok, bytes memory data) = _overlay(
            abi.encodeCall(UnpushedDecimatorSessionSeeder.runDecimator, (callGas == 0 ? gasleft() : callGas)), callGas
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (r, used) = abi.decode(data, (MineFlipGas.Result, uint256));
    }

    function _requestBlocked() private {
        assertEq(RecyclingState.currentWord(address(game)), WORD);
        (bool ok, bytes memory reason) = _overlay(abi.encodeCall(UnpushedDecimatorSessionSeeder.requestMidday, ()), 0);
        assertFalse(ok, "the mid-day request is refused while the round reads the word");
        assertEq(bytes4(reason), bytes4(keccak256("RngNotReady()")));
        assertEq(RecyclingState.currentWord(address(game)), WORD);
    }

    function _key(uint64 id) private pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE, WORD, LVL, id))) & ~uint256(type(uint64).max)) | id;
    }

    // The Decimator worker runs under the allowance it is given, admitting each step by its
    // declared bound and carrying on into the next phase while the rest still covers it:
    // RUN_ALLOWANCE admits a heads run and a cold frame, so a call runs only a few of the flat
    // engine's cheap heads; PAY_ALLOWANCE admits one PAYMENT plus its tail.
    uint256 private constant RUN_ALLOWANCE =
        GasBounds.DECIMATOR_RUN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 100_000;
    uint256 private constant PAY_ALLOWANCE = 230_000;

    function test_ActiveWordSurvivesEveryWorkerCheckpointUntilRequest() public {
        _requestBlocked();
        uint64 champion;
        for (uint64 id = 1; id <= COUNT; ++id) {
            if (uint256(keccak256(abi.encode(COIN, WORD, LVL, id))) & 1 == 0) continue;
            if (champion == 0 || _key(id) > _key(champion)) champion = id;
        }
        DegenerusGameStorage.DecBattleRound memory r;
        uint256 checkpoints;
        for (uint256 i; i < 2 * COUNT; ++i) {
            DegenerusGameStorage.DecBattleRound memory before = lens.decBattleRoundOf(address(game), LVL);
            uint256 allowance = before.phase == 2 ? PAY_ALLOWANCE : RUN_ALLOWANCE;
            (, uint256 used) = _runDecimator(allowance);
            assertLe(used, allowance, "each call stays inside its allowance");
            r = lens.decBattleRoundOf(address(game), LVL);
            assertTrue(r.cursor > before.cursor || r.phase > before.phase || r.paid > before.paid,
                "each bounded call makes progress");
            if (r.phase > 1) {
                assertEq(r.cursor, COUNT, "every entrant ran before ranking");
                assertEq(r.winners, 4);
                assertEq(r.champion, champion, "ranking uses the same active word as every run");
            }
            if (r.phase == 3) break;
            if (r.phase == 2) assertEq(lens.decWinnerAt(address(game), LVL, 0).key, _key(champion));
            // Every checkpoint before completion, in any phase, keeps the word and refuses a request.
            _requestBlocked();
            ++checkpoints;
        }
        assertEq(r.phase, 3);
        assertGt(checkpoints, 1, "the round spans bounded calls");
        uint256 sum;
        for (uint64 id = 1; id <= COUNT; ++id) sum += game.claimableWinningsOf(address(uint160(0xD000 + id)));
        assertEq(sum, POOL, "all payouts finish before the next request");
        // With the round complete the engine issues the mid-day request itself.
        uint256 requestBefore = mockVRF.lastRequestId();
        game.mineFlip();
        assertGt(mockVRF.lastRequestId(), requestBefore);
        assertEq(RecyclingState.currentWord(address(game)), 0, "only the completed round releases its word");
        vm.expectRevert(); lens.decWinnerAt(address(game), LVL, 0);
    }

    function test_TerminalReplacementWordCannotResumeOldNormalBattleBeforeGameOver() public {
        _runDecimator(RUN_ALLOWANCE);
        DegenerusGameStorage.DecBattleRound memory started = lens.decBattleRoundOf(address(game), LVL);
        assertEq(started.phase, 1, "the normal battle is part-run when the terminal word lands");
        assertGt(started.cursor, 0);
        assertLt(started.cursor, COUNT);
        bytes memory beforeRound = abi.encode(started);
        _seed(abi.encodeCall(UnpushedDecimatorSessionSeeder.terminalWord, (uint256(0xDEADCAFE))));
        assertFalse(game.gameOver());
        assertEq(RecyclingState.currentWord(address(game)), 0xDEADCAFE);
        (MineFlipGas.Result memory r, uint256 used) = _runDecimator(0);
        assertEq(r.rewardBasis, 0);
        // A refused resume admits no run at all, so the worker call spends less than the
        // smallest declared step (a tails run).
        assertLt(used, GasBounds.DECIMATOR_TAILS_GAS_MAX);
        assertFalse(r.progressed);
        assertEq(abi.encode(lens.decBattleRoundOf(address(game), LVL)), beforeRound);
        vm.expectRevert(); lens.decWinnerAt(address(game), LVL, 0);
    }
}
