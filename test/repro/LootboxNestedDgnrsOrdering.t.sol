// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {SigFigLib} from "../../contracts/libraries/SigFigLib.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title LootboxNestedDgnrsOrdering
/// @notice Regression for a parent box entry that wins DGNRS, recursively resolves an ETH-spin
///         lootbox that also wins DGNRS, then wins DGNRS again. The parent must settle before
///         recursion and reload the live Lootbox-pool balance afterward.
contract LootboxNestedDgnrsOrdering is DeployProtocol {
    address private constant PLAYER = address(0xBEEF);
    uint48 private constant GENESIS_INDEX = 1;
    uint256 private constant CUSTOM_SIZE = 10 ether;
    uint256 private constant BOX_ORDER = (uint256(3) << 24) | ((CUSTOM_SIZE / 1e12) << 32);
    uint256 private constant RNG_WORD = 0x9b1ce;

    bytes32 private constant DGNRS_BATCH_SIG = keccak256("LootBoxDgnrsBatch(address,uint256,uint256)");
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
    }

    function testParentDgnrsIsSettledAndSnapshotReloadedAcrossNestedEthSpin() public {
        vm.deal(PLAYER, 31 ether);
        vm.prank(PLAYER);
        game.purchase{value: 30 ether}(PLAYER, 0, BOX_ORDER, bytes32(0), MintPaymentKind.DirectEth, false);

        _landWord(RNG_WORD);

        uint256 poolBefore = _lootboxPool();
        uint256 balanceBefore = sdgnrs.balanceOf(PLAYER);

        vm.recordLogs();
        uint256 gasBefore = gasleft();
        game.openBox(PLAYER, GENESIS_INDEX);
        uint256 gasUsed = gasBefore - gasleft();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256[3] memory requested;
        uint256[3] memory paid;
        uint256 batchCount;
        uint256 parentAmount;
        uint256 parentOpenCount;

        for (uint256 i; i < logs.length; ++i) {
            VmSafe.Log memory entry = logs[i];
            if (entry.emitter != address(game) || entry.topics.length < 2) continue;
            if (entry.topics[1] != bytes32(uint256(uint160(PLAYER)))) continue;

            if (entry.topics[0] == DGNRS_BATCH_SIG) {
                assertLt(batchCount, 3, "unexpected extra DGNRS settlement batch");
                (requested[batchCount], paid[batchCount]) = abi.decode(entry.data, (uint256, uint256));
                ++batchCount;
            } else if (
                entry.topics[0] == LOOTBOX_OPENED_SIG && entry.topics.length == 3
                    && uint48(uint256(entry.topics[2])) == GENESIS_INDEX
            ) {
                (uint256 amount,,,,) = abi.decode(entry.data, (uint256, uint24, uint32, uint256, bool));
                parentAmount = amount;
                ++parentOpenCount;
            }
        }

        // The middle ETH-spin uses BoxSpin instead of the all-zero LootBoxOpened schema.
        assertEq(parentOpenCount, 2, "fixture did not open both parent DGNRS boxes");
        assertEq(batchCount, 3, "parent/child/parent DGNRS must settle as three batches");
        for (uint256 i; i < batchCount; ++i) {
            assertGt(requested[i], 0, "fixture batch must request DGNRS");
            assertEq(paid[i], requested[i], "fixture pool must remain solvent");
        }

        // Box three is the later parent DGNRS roll. It must price from the balance after the
        // pre-recursion parent batch and the nested child batch, not the entry's old snapshot.
        uint256 seed3 = EntropyLib.hash4(RNG_WORD, uint256(uint160(PLAYER)), CUSTOM_SIZE, 3);
        uint256 boonBudget = parentAmount / 10;
        if (boonBudget > 1 ether) boonBudget = 1 ether;
        uint256 rollAmount = parentAmount - boonBudget;
        uint256 liveBeforeThird = poolBefore - paid[0] - paid[1];
        uint256 expectedFresh = _dgnrsReward(rollAmount, seed3, liveBeforeThird);
        uint256 expectedStale = _dgnrsReward(rollAmount, seed3, poolBefore);

        assertEq(requested[2], expectedFresh, "later parent roll did not reload live pool");
        assertNotEq(expectedFresh, expectedStale, "fixture must distinguish fresh and stale pool");

        uint256 totalPaid = paid[0] + paid[1] + paid[2];
        assertEq(poolBefore - _lootboxPool(), totalPaid, "pool debit mismatch");
        assertEq(sdgnrs.balanceOf(PLAYER) - balanceBefore, totalPaid, "player credit mismatch");

        emit log_named_uint("nested_dgnrs_open_gas", gasUsed);
        emit log_named_uint("stale_third_dgnrs", expectedStale);
        emit log_named_uint("fresh_third_dgnrs", expectedFresh);
    }

    function _dgnrsReward(uint256 amount, uint256 entropy, uint256 poolBalance) private pure returns (uint256 reward) {
        uint256 tierRoll = uint24(entropy >> 56) % 1000;
        uint256 ppm;
        if (tierRoll < 795) ppm = 10;
        else if (tierRoll < 945) ppm = 390;
        else if (tierRoll < 995) ppm = 800;
        else ppm = 8000;

        reward = SigFigLib.floorToThreeSigFigs((poolBalance * ppm * amount) / (1_000_000 * 1 ether));
        if (reward > poolBalance) reward = poolBalance;
    }

    function _lootboxPool() private view returns (uint256) {
        return IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Lootbox);
    }

    function _landWord(uint256 vrfWord) private {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
        _settleClean(vrfWord);
    }

    function _settleGame(uint256 vrfWord) private {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; ++d) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) private {
        for (uint256 d; d < 240; ++d) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == _lastFulfilledReqId || reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (!fulfilled) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
    }
}
