// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Craps} from "../../contracts/Craps.sol";

/// @dev Setup only: the public game dispatch, seal, run/rank/pay and request gates
/// are production. All unrelated consumers start complete, isolating Decimator.
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

    function _requestBlocked() private {
        assertEq(RecyclingState.currentWord(address(game)), WORD);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        assertEq(RecyclingState.currentWord(address(game)), WORD);
    }

    function _key(uint64 id) private pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE, WORD, LVL, id))) & ~uint256(type(uint64).max)) | id;
    }

    function test_ActiveWordSurvivesPartialRunsRankingAndEveryPayoutUntilRequest() public {
        _requestBlocked();
        DegenerusGameStorage.DecBattleRound memory r;
        uint64 previous;
        for (uint256 i; previous < COUNT && i < COUNT; ++i) {
            (, uint256 charged,) = game.settleDecimatorWinners(122);
            assertLe(charged, 122, "partial call stays inside its allowance");
            r = lens.decBattleRoundOf(address(game), LVL);
            assertGt(r.cursor, previous);
            previous = r.cursor;
            assertEq(r.phase, 1);
            _requestBlocked();
        }
        assertEq(r.cursor, COUNT, "every entrant ran before ranking");
        game.settleDecimatorWinners(72); // Ranking is a separately reserved bounded step.
        r = lens.decBattleRoundOf(address(game), LVL);
        assertEq(r.phase, 2);
        assertEq(r.winners, 4);
        uint64 champion;
        for (uint64 id = 1; id <= COUNT; ++id) {
            if (uint256(keccak256(abi.encode(COIN, WORD, LVL, id))) & 1 == 0) continue;
            if (champion == 0 || _key(id) > _key(champion)) champion = id;
        }
        assertEq(r.champion, champion, "ranking uses the same active word as every run");
        assertEq(lens.decWinnerAt(address(game), LVL, 0).key, _key(champion));
        _requestBlocked();
        for (uint256 i; i < r.winners; ++i) {
            game.settleDecimatorWinners(22); // Call reserve plus exactly one ETH award.
            if (i + 1 < r.winners) _requestBlocked();
        }
        r = lens.decBattleRoundOf(address(game), LVL);
        assertEq(r.phase, 3);
        uint256 sum;
        for (uint64 id = 1; id <= COUNT; ++id) sum += game.claimableWinningsOf(address(uint160(0xD000 + id)));
        assertEq(sum, POOL, "all payouts finish before the next request");
        uint256 requestBefore = mockVRF.lastRequestId();
        game.requestLootboxRng();
        assertGt(mockVRF.lastRequestId(), requestBefore);
        assertEq(RecyclingState.currentWord(address(game)), 0, "only the completed round releases its word");
        vm.expectRevert(); lens.decWinnerAt(address(game), LVL, 0);
    }

    function test_TerminalReplacementWordCannotResumeOldNormalBattleBeforeGameOver() public {
        game.settleDecimatorWinners(50);
        bytes memory beforeRound = abi.encode(lens.decBattleRoundOf(address(game), LVL));
        _seed(abi.encodeCall(UnpushedDecimatorSessionSeeder.terminalWord, (uint256(0xDEADCAFE))));
        assertFalse(game.gameOver());
        assertEq(RecyclingState.currentWord(address(game)), 0xDEADCAFE);
        (uint256 settled, uint256 used, bool moved) = game.settleDecimatorWinners(2500);
        assertEq(settled, 0);
        assertEq(used, 0);
        assertFalse(moved);
        assertEq(abi.encode(lens.decBattleRoundOf(address(game), LVL)), beforeRound);
        vm.expectRevert(); lens.decWinnerAt(address(game), LVL, 0);
    }
}
