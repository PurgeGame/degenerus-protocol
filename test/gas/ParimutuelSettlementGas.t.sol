// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @notice Parimutuel settlement stage gas on the real protocol (real Parimutuel, Coinflip and
///         Game). Each figure is one call measured with the touched accounts cooled first, so
///         storage and account access are cold as in a fresh transaction. Winners' Coinflip stake
///         lanes are fresh (zero) unless the case says otherwise: a zero-to-nonzero lane write is
///         the per-winner worst case GROWTH_SETTLE_GAS must cover.
contract ParimutuelSettlementGasTest is DeployProtocol {
    bytes4 private constant GROWTH_STATE = bytes4(keccak256("growthState(uint24)"));
    bytes4 private constant MARKET_GATES = bytes4(keccak256("marketBetGates(uint32,uint24)"));
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    uint256 private constant STAKE = 1_000;
    uint256 private constant SETTLEMENT_SLOT = 4; // DegenerusParimutuel.growthSettlement
    uint256 private constant STAKE_ROOT = 0; // Coinflip.coinflipStakePacked
    uint256 private constant PENDING_BIT = GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET * 8 + 11;
    uint256 private constant CHUNK = MineFlipGasBounds.GROWTH_SETTLE_WINNERS;

    uint256 private nonce;
    uint256 private simTime;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
    }

    // ---------------------------------------------------------------- helpers

    function _open(uint24 round) private {
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0))
        );
    }

    function _newBettor() private returns (address who, uint32 id) {
        who = address(uint160(0xBE70_0000 + ++nonce));
        id = _giveWalletId(who);
    }

    function _bet(address who, uint32 id, bool over) private {
        vm.mockCall(address(quests), abi.encodeWithSelector(MARKET_GATES, id), abi.encode(true, false, id));
        vm.prank(address(game));
        coin.mintForGame(who, STAKE);
        vm.prank(who);
        parimutuel.placeBet(0, over);
    }

    /// @dev `n` new winners on OVER plus one UNDER loser, sealed OVER.
    function _round(uint24 round, uint256 n) private returns (address[] memory who, uint32[] memory ids) {
        _open(round);
        who = new address[](n);
        ids = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            (who[i], ids[i]) = _newBettor();
            _bet(who[i], ids[i], true);
        }
        (address loser, uint32 loserId) = _newBettor();
        _bet(loser, loserId, false);
        vm.prank(address(game));
        parimutuel.recordGrowth(round, true);
    }

    /// @dev The same wallets win again on `round` (their stake lanes for the target day are
    ///      already nonzero), plus one new loser.
    function _repeatRound(uint24 round, address[] memory who, uint32[] memory ids) private {
        _open(round);
        for (uint256 i; i < who.length; ++i) _bet(who[i], ids[i], true);
        (address loser, uint32 loserId) = _newBettor();
        _bet(loser, loserId, false);
        vm.prank(address(game));
        parimutuel.recordGrowth(round, true);
    }

    function _cursor() private view returns (uint24 round, uint256 paid) {
        uint256 w = uint256(vm.load(address(parimutuel), bytes32(SETTLEMENT_SLOT)));
        round = uint24(w);
        paid = uint64(w >> 24);
    }

    function _stake(uint32 id) private view returns (uint256) {
        uint24 day = GameTimeLib.currentDayIndex() + 1;
        bytes32 outer = keccak256(abi.encode(uint256(day >> 3), STAKE_ROOT));
        uint256 w = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint256(id), outer))));
        return uint32(w >> ((uint256(day) & 7) << 5));
    }

    function _settleCold(uint256 maxWinners) private returns (uint256 used, bool done) {
        vm.cool(address(parimutuel));
        vm.cool(address(coinflip));
        vm.prank(address(game));
        uint256 g0 = gasleft();
        done = parimutuel.settleGrowth(maxWinners);
        used = g0 - gasleft();
    }

    // ---------------------------------------------------------------- measurements

    /// The declared stage weight: one cold chunk of GROWTH_SETTLE_WINNERS winners whose
    /// Coinflip stake lanes are all fresh.
    function test_ColdChunkOfFreshWinnersFitsDeclaredWeight() public {
        (, uint32[] memory ids) = _round(1, CHUNK);
        for (uint256 i; i < ids.length; ++i) assertEq(_stake(ids[i]), 0, "fixture: fresh lanes");
        (uint256 used, bool done) = _settleCold(CHUNK);
        console.log("settleGrowth(100), 100 fresh cold winners:", used);
        console.log("GROWTH_SETTLE_GAS:", MineFlipGasBounds.GROWTH_SETTLE_GAS);
        assertFalse(done, "a full chunk ends on the boundary");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1);
        assertEq(paid, CHUNK);
        assertEq(_stake(ids[0]), (STAKE * (CHUNK + 1)) / CHUNK);
        assertLe(used, MineFlipGasBounds.GROWTH_SETTLE_GAS, "cold fresh chunk within the declared weight");
    }

    /// Repeat winners: the same 100 wallets win a second round on the same stake day, so each
    /// lane write is nonzero-to-nonzero (cold slot).
    function test_ColdChunkOfRepeatWinners() public {
        (address[] memory who, uint32[] memory ids) = _round(1, CHUNK);
        vm.prank(address(game));
        parimutuel.settleGrowth(CHUNK);
        vm.prank(address(game));
        assertTrue(parimutuel.settleGrowth(CHUNK));
        _repeatRound(2, who, ids);
        assertGt(_stake(ids[0]), 0, "fixture: lanes already credited today");
        (uint256 used, ) = _settleCold(CHUNK);
        console.log("settleGrowth(100), 100 repeat winners (nonzero lanes), cold:", used);
        assertLe(used, MineFlipGasBounds.GROWTH_SETTLE_GAS);
    }

    /// Two consecutive chunks in one transaction: the second runs with the Parimutuel and
    /// Coinflip accounts warm (its winners' lanes are still fresh).
    function test_WarmSecondChunk() public {
        _round(1, 2 * CHUNK);
        (uint256 first, ) = _settleCold(CHUNK);
        vm.prank(address(game));
        uint256 g0 = gasleft();
        parimutuel.settleGrowth(CHUNK);
        uint256 second = g0 - gasleft();
        console.log("settleGrowth(100), first cold chunk of 200:", first);
        console.log("settleGrowth(100), second chunk, accounts warm:", second);
        assertLe(first, MineFlipGasBounds.GROWTH_SETTLE_GAS);
    }

    /// A chunk spanning a round boundary: 50 winners left on round 1, a step, then 49 fresh
    /// winners of round 2 (the step spends one unit of the budget).
    function test_ChunkSpanningRoundBoundary() public {
        _round(1, 150);
        vm.prank(address(game));
        parimutuel.settleGrowth(CHUNK);
        _round(2, CHUNK);
        vm.recordLogs();
        (uint256 used, bool done) = _settleCold(CHUNK);
        console.log("settleGrowth(100) spanning rounds 1->2 (50 + step + 49 winners), cold:", used);
        assertFalse(done);
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 2);
        assertEq(paid, 49);
        assertLe(used, MineFlipGasBounds.GROWTH_SETTLE_GAS);
    }

    function _driveDay() private {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 j; j < 200; ++j) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(reqId)))) {} catch {}
            }
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (!ok) break;
        }
    }

    function _executionGas(Vm.Log[] memory logs) private view returns (uint256 executionGas) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (uint8 firstAction, uint256 used, ) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                assertEq(firstAction, 19);
                executionGas = used;
            }
        }
    }

    /// The whole Game stage: one mineFlip whose only work is a cold 100-winner chunk, measured as
    /// the engine's own MinerWork executionGas and as the caller's total.
    function test_MineFlipStageChunk() public {
        _driveDay();
        assertTrue(game.nextMinerAction() != 19, "fixture: idle engine");
        _round(1, CHUNK);
        vm.clearMockedCalls();
        bytes32 slot = bytes32(GameSlots.RNG_FLAGS_AND_NUDGES);
        vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) | (uint256(1) << PENDING_BIT)));
        assertEq(game.nextMinerAction(), 19);

        address keeper = address(0xC1A9);
        _giveWalletId(keeper);
        vm.fee(1 gwei);
        vm.cool(address(game));
        vm.cool(address(parimutuel));
        vm.cool(address(coinflip));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.recordLogs();
        vm.prank(keeper);
        uint256 g0 = gasleft();
        game.mineFlip{gas: 4_400_000}(0);
        uint256 total = g0 - gasleft();
        uint256 executionGas = _executionGas(vm.getRecordedLogs());
        console.log("mineFlip GrowthSettle stage, 100 fresh cold winners, MinerWork.executionGas:", executionGas);
        console.log("mineFlip GrowthSettle stage, caller-measured total incl. bounty credit:", total);
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 2, "completed round cursor is released in the same call");
        assertEq(paid, 0);
        assertLe(executionGas, MineFlipGasBounds.GROWTH_SETTLE_GAS + MineFlipGasBounds.ENGINE_BOUNDARY);
    }
}
