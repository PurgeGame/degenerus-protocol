// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev The DeadVrfEnding seeder plus the post-swap probes this repro needs. Etched only to
///      seed and to read; every measured call runs the production DegenerusGame runtime.
contract PostSwapSeeder is DeadVrfSeeder {
    /// @dev Occurrences across all 256 trait buckets of `lvl`.
    function bucketTotal(uint24 lvl) external view returns (uint256 total) {
        for (uint256 t; t < 256; ++t) total += _bucketLength(lvl, t);
    }

    function jackpotPaid() external view returns (uint256) {
        return _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK);
    }

    function inventoryDigest(uint24 lvl) external view returns (bytes32 digest) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            digest = keccak256(abi.encode(digest, t, n));
            for (uint256 i; i < n; ++i) {
                digest = keccak256(abi.encode(digest, _bucketOwnerAt(lvl, uint8(t), i)));
            }
        }
    }

}

/// @notice Low supplied gas may pause or revert a post-swap drain, but must never
///         advance terminal payouts past unpaid tickets or change the eventual awards.
contract TerminalDrainPostSwapStarvationTest is DeployProtocol {
    uint24 private constant LVL = 5000; // purchase phase: the terminal ticket level is LVL + 1
    uint24 private constant TLVL = LVL + 1;

    bytes private realCode;
    uint32[] private cohortPos;
    address[] private cohort;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 200 days);
        vm.deal(address(game), 100 ether);
        realCode = address(game).code;
    }

    // ---------------------------------------------------------------- harness helpers

    function _seeder() private returns (PostSwapSeeder s) {
        vm.etch(address(game), type(PostSwapSeeder).runtimeCode);
        s = PostSwapSeeder(payable(address(game)));
    }

    function _restore() private {
        vm.etch(address(game), realCode);
    }

    function _queues() private returns (uint256 readLen, uint256 writeLen, uint256 swapped) {
        (readLen, writeLen, swapped) = _seeder().terminalQueues(TLVL);
        _restore();
    }

    function _bucketTotal() private returns (uint256 total) {
        total = _seeder().bucketTotal(TLVL);
        _restore();
    }

    function _jackpotPaid() private returns (uint256 paid) {
        paid = _seeder().jackpotPaid();
        _restore();
    }

    /// @dev Entries still owed across the whole seeded cohort, and how many owners owe any.
    function _owedTotal() private returns (uint256 owed, uint256 owing) {
        PostSwapSeeder s = _seeder();
        for (uint256 i; i < cohortPos.length; ++i) {
            uint256 o = s.owedAt(TLVL, cohortPos[i]);
            owed += o;
            if (o != 0) ++owing;
        }
        _restore();
    }

    function _cohortClaimable() private view returns (uint256 sum) {
        for (uint256 i; i < cohort.length; ++i) sum += game.claimableWinningsOf(cohort[i]);
    }

    /// @dev ETH the game holds beyond what it owes as claimable: what the final sweep takes.
    function _unallocated() private view returns (uint256) {
        uint256 held = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 owed = game.claimablePoolView();
        return held > owed ? held - owed : 0;
    }

    /// @dev Real flow from a deadline-past, caught-up, VRF-alive purchase phase with the whole
    ///      terminal cohort on the WRITE side: call 1 performs the ending's one swap and sends
    ///      the terminal request, `word` lands, call 2 applies it. Then `preBatches` gas-limited
    ///      drain batches. Ends one call before the batch under test.
    function _toPostSwapWorded(uint256 owners, uint32 entries, uint256 word, uint256 preBatches) private {
        PostSwapSeeder s = _seeder();
        s.seedDeadlineWithLandedCohort(LVL, 0xB0B5);
        for (uint256 i; i < owners; ++i) {
            address who = address(uint160(0xD00D0000 + i + 1));
            cohort.push(who);
            cohortPos.push(s.seedQueued(TLVL, true, who, entries, 0));
        }
        _restore();
        assertTrue(game.livenessTriggered(), "deadline passed, caught up, VRF alive");

        uint256 req0 = mockVRF.lastRequestId();
        game.mineFlip(0); // the one terminal swap + terminal request
        (uint256 rl, uint256 wl, uint256 sw) = _queues();
        assertEq(sw, 1, "swap latch set");
        assertEq(rl, owners, "the cohort moved to the read side");
        assertEq(wl, 0, "write side empty");
        uint256 req = mockVRF.lastRequestId();
        assertGt(req, req0, "terminal request sent");

        mockVRF.fulfillRandomWords(req, word);
        game.mineFlip(0); // applies the terminal word; returns before any drain
        assertTrue(game.rngWordForDay(game.currentDayView()) != 0, "terminal word recorded");
        assertFalse(game.gameOver(), "not over yet");
        (rl,,) = _queues();
        assertEq(rl, owners, "nothing drained yet");
        assertEq(_bucketTotal(), 0, "every trait bucket at drainLevel is empty before the drain");
        assertGt(_unallocated(), 0, "distributable funds exist");

        for (uint256 i; i < preBatches; ++i) {
            _coolEngine();
            game.mineFlip{gas: 3_500_000}(0);
            assertFalse(game.gameOver(), "pre-batch returned before the payout");
        }
        (rl,,) = _queues();
        assertGt(rl, 0, "cohort still queued at the batch under test");
    }

    function _coolEngine() private {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
    }

    function _assertNoPrematurePayout() private {
        (uint256 queued,,) = _queues();
        (uint256 owed,) = _owedTotal();
        if (queued != 0 || owed != 0) {
            assertFalse(game.gameOver(), "unpaid cohort must precede terminal setup");
            assertEq(_jackpotPaid(), 0, "unpaid cohort must precede payout completion");
        }
    }

    function _finish() private {
        for (uint256 i; i < 100 && _jackpotPaid() == 0; ++i) {
            _coolEngine();
            game.mineFlip{gas: 12_000_000}(0);
            _assertNoPrematurePayout();
        }
        assertTrue(game.gameOver(), "ending completes");
        assertEq(_jackpotPaid(), 1, "all payout quadrants complete");
        (uint256 queued,,) = _queues();
        (uint256 owed,) = _owedTotal();
        assertEq(queued, 0, "read queue released");
        assertEq(owed, 0, "entire paid cohort materialized");
    }

    function _payoutTranscript() private returns (bytes32 digest) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)")) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
            }
        }
    }

    function _settledState() private returns (bytes32 digest) {
        digest = _seeder().inventoryDigest(TLVL);
        _restore();
        digest = keccak256(abi.encode(digest, game.claimablePoolView(), _unallocated(),
            game.claimableWinningsOf(ContractAddresses.VAULT), game.claimableWinningsOf(ContractAddresses.SDGNRS)));
        for (uint256 i; i < cohort.length; ++i) {
            digest = keccak256(abi.encode(digest, game.claimableWinningsOf(cohort[i])));
        }
    }

    function _sweep(uint256 owners, uint32 entries, uint256 preBatches, bool expectAwards) private {
        uint256 word = uint256(keccak256(abi.encode("w", uint256(0))));
        _toPostSwapWorded(owners, entries, word, preBatches);
        uint256 base = vm.snapshotState();
        vm.recordLogs();
        _finish();
        bytes32 expectedTranscript = _payoutTranscript();
        bytes32 expectedState = _settledState();
        // Retain the adversarial empty-board case, and separately prove that the
        // populated case exercises the event filter and actual recipient credits.
        if (expectAwards) {
            assertTrue(expectedTranscript != bytes32(0), "baseline records actual terminal awards");
            assertGt(_cohortClaimable(), 0, "baseline awards reach the paid cohort");
        } else {
            assertEq(expectedTranscript, bytes32(0), "empty winning board has no draw awards");
            assertEq(_cohortClaimable(), 0, "empty winning board has no cohort credit");
        }
        uint256[11] memory limits = [uint256(100_000), 400_000, 700_000, 1_000_000,
            1_500_000, 2_000_000, 2_500_000, 3_000_000, 4_000_000, 6_000_000, 9_500_000];
        uint256 pauses;
        uint256 partialDrains;
        for (uint256 i; i < limits.length; ++i) {
            assertTrue(vm.revertToState(base));
            uint256 createdBefore = _bucketTotal();
            _coolEngine();
            vm.recordLogs();
            (bool ok,) = address(game).call{gas: limits[i]}(abi.encodeCall(game.mineFlip, (uint32(0))));
            _assertNoPrematurePayout();
            if (!game.gameOver()) ++pauses;
            (uint256 queued,,) = _queues();
            if (ok && queued != 0 && _bucketTotal() > createdBefore) ++partialDrains;
            _finish();
            assertEq(_payoutTranscript(), expectedTranscript, "supplied gas cannot change ordered awards");
            assertEq(_settledState(), expectedState, "supplied gas cannot forfeit or reorder any cohort entry");
        }
        assertGt(pauses, 0, "sweep exercises starved checkpoints");
        assertGt(partialDrains, 0, "sweep exercises successful partial drains");
    }

    function test_starvedPostSwapBatchCannotForfeitTheCohort() public {
        _sweep(24, 60, 0, false);
    }

    function test_starvedLaterPostSwapBatchCannotForfeitTheCohort() public {
        _sweep(8, 2000, 1, true);
    }
}
