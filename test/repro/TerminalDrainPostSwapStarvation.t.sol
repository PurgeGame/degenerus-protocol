// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/DeadVrfEnding.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The DeadVrfEnding seeder plus the post-swap probes this repro needs. Etched only to
///      seed and to read; every measured call runs the production DegenerusGame runtime.
contract PostSwapSeeder is DeadVrfSeeder {
    /// @dev Occurrences across all 256 trait buckets of `lvl`.
    function bucketTotal(uint24 lvl) external view returns (uint256 total) {
        for (uint256 t; t < 256; ++t) total += lvlTraitEntry[lvl][t].length;
    }

    function jackpotPaid() external view returns (uint256) {
        return _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK);
    }

    /// @dev Empty the read queue at `lvl` (length word only, as the drain's own release does).
    ///      Prices the payout-only fall-through on otherwise identical state.
    function releaseReadQueue(uint24 lvl) external {
        _releaseTicketQueue(_tqReadKey(lvl));
    }
}

/// @dev Stands in for the game-over module (delegatecalled): reverts with the gas its frame
///      received, i.e. exactly what the Advance frame hands the payout at that point.
contract PayoutGasProbe {
    fallback() external payable {
        assembly {
            mstore(0, gas())
            revert(0, 32)
        }
    }
}

/// @notice After the ending's one ticket-slot swap, a starved drain batch must not be reported as
///         "no batch": the same transaction would fall through to handleGameOverDrain +
///         _unlockRng, latch gameOver with the cohort still queued, and leave its share for the
///         final sweep — a caller-chosen gas limit forfeiting the whole post-swap cohort.
///         `_terminalDrainBatch` re-raises an empty or EmptyRevert failure in both phases, so a
///         starved batch reverts. Without that, only a margin protected the cohort: with every
///         trait bucket at drainLevel empty the payout pays nobody and is cheap (~228k cold),
///         and the most a starved batch was measured to leave it was ~188k. The sweep drives
///         every starved depth (the worker, or the nested round drain) and asserts no limit
///         forfeits the cohort.
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

    function _isStarved(bytes memory err) private pure returns (bool) {
        return err.length == 0 || (err.length == 4 && bytes4(err) == DegenerusGameStorage.EmptyRevert.selector);
    }

    /// @dev Real flow from a deadline-past, caught-up, VRF-alive purchase phase with the whole
    ///      terminal cohort on the WRITE side: call 1 performs the ending's one swap and sends
    ///      the terminal request, `word` lands, call 2 applies it. Then `preBatches` full-gas
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
        game.advanceGame(); // the one terminal swap + terminal request
        (uint256 rl, uint256 wl, uint256 sw) = _queues();
        assertEq(sw, 1, "swap latch set");
        assertEq(rl, owners, "the cohort moved to the read side");
        assertEq(wl, 0, "write side empty");
        uint256 req = mockVRF.lastRequestId();
        assertGt(req, req0, "terminal request sent");

        mockVRF.fulfillRandomWords(req, word);
        game.advanceGame(); // applies the terminal word; returns before any drain
        assertTrue(game.rngWordForDay(game.currentDayView()) != 0, "terminal word recorded");
        assertFalse(game.gameOver(), "not over yet");
        (rl,,) = _queues();
        assertEq(rl, owners, "nothing drained yet");
        assertEq(_bucketTotal(), 0, "every trait bucket at drainLevel is empty before the drain");
        assertGt(_unallocated(), 0, "distributable funds exist");

        for (uint256 i; i < preBatches; ++i) {
            game.advanceGame();
            assertFalse(game.gameOver(), "pre-batch returned before the payout");
        }
        (rl,,) = _queues();
        assertGt(rl, 0, "cohort still queued at the batch under test");
    }

    // ---------------------------------------------------------------- the sweep

    struct Sweep {
        uint256 batchGas; // full-gas cost of the batch under test
        uint256 minBatchOkGas; // smallest limit at which that batch ran
        uint256 payoutGas; // payout-only fall-through (queue released), full gas
        uint256 payoutMinGas; // smallest limit completing the payout-only call
        uint256 payoutNeed; // gas the payout frame receives at payoutMinGas (it needs at most this)
        uint256 payoutCohortPaid; // what the payout-only call credits the cohort (0: winning buckets empty)
        uint256 payoutDeityPaid; // ...and the protocol deities (0: no deity symbol among the winners)
        uint256 maxFallthrough; // most gas a starved batch leaves the payout frame (probe)
        uint256 maxFallthroughAt; // the limit at which that peak occurred
        uint256 nestedOogCount; // starved limits whose leftover shows the nested frame OOG'd
        uint256 workerOogCount; // starved limits whose leftover shows the worker frame OOG'd
        uint256 leakGas; // largest leaking limit
        uint256 leakLow; // smallest leaking limit
        uint256 leakCount;
        uint256 witnessGas; // largest limit that reverted EmptyRevert / empty data
        uint256 witnessCount;
    }

    function _sweep(uint256 owners, uint32 entries, uint256 word, uint256 preBatches, uint256 divisor)
        private
        returns (Sweep memory r)
    {
        _toPostSwapWorded(owners, entries, word, preBatches);
        uint256 base = vm.snapshotState();
        bytes memory goCode = ContractAddresses.GAME_GAMEOVER_MODULE.code;

        _measurePayout(r);
        vm.revertToState(base);

        // Full-gas batch: runs, returns before the payout, leaves the cohort partly queued.
        uint256 before = _bucketTotal();
        uint256 g0 = gasleft();
        game.advanceGame();
        r.batchGas = g0 - gasleft();
        assertFalse(game.gameOver(), "a batch call returns before the payout");
        assertGt(_bucketTotal(), before, "the batch drained tickets into the buckets");
        vm.revertToState(base);

        uint256 step = r.batchGas / divisor;
        uint256 top = r.batchGas + r.batchGas / 10;
        uint256 bottom = r.batchGas / 8;

        // Probe pass: the game-over module replaced by a probe that reports the gas it received.
        // A starved batch that is swallowed reaches it; its reading is the payout's budget.
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, type(PayoutGasProbe).runtimeCode);
        uint256 probed = vm.snapshotState();
        r.minBatchOkGas = type(uint256).max;
        for (uint256 g = top; g > bottom; g -= step) {
            vm.revertToState(probed);
            try game.advanceGame{gas: g}() {
                if (g < r.minBatchOkGas) r.minBatchOkGas = g;
            } catch (bytes memory err) {
                if (err.length == 32) {
                    uint256 e = abi.decode(err, (uint256));
                    if (e > r.maxFallthrough) {
                        r.maxFallthrough = e;
                        r.maxFallthroughAt = g;
                    }
                    // Nested (round-drain) OOG: the payout gets the Advance AND worker reserves,
                    // ~3% of the limit; worker OOG: only the Advance reserve, ~1.5%.
                    if (e * 1000 > g * 22) ++r.nestedOogCount;
                    else ++r.workerOogCount;
                }
            }
        }
        vm.revertToState(base);
        assertEq(keccak256(ContractAddresses.GAME_GAMEOVER_MODULE.code), keccak256(goCode), "real module restored");

        // Real pass.
        uint256 leakRl;
        uint256 leakOwed;
        uint256 leakOwing;
        uint256 leakUnalloc;
        uint256 leakCohortPaid;
        uint256 leakDeityPaid;
        for (uint256 g = top; g > bottom; g -= step) {
            vm.revertToState(base);
            try game.advanceGame{gas: g}() {
                if (game.gameOver() || _jackpotPaid() != 0) {
                    (uint256 rl,,) = _queues();
                    (uint256 owed, uint256 owing) = _owedTotal();
                    if (rl != 0 || owed != 0) {
                        if (r.leakGas == 0) {
                            r.leakGas = g;
                            leakRl = rl;
                            leakOwed = owed;
                            leakOwing = owing;
                            leakUnalloc = _unallocated();
                            leakCohortPaid = _cohortClaimable();
                            leakDeityPaid = game.claimableWinningsOf(ContractAddresses.VAULT)
                                + game.claimableWinningsOf(ContractAddresses.SDGNRS);
                        }
                        r.leakLow = g;
                        ++r.leakCount;
                    }
                }
            } catch (bytes memory err) {
                if (_isStarved(err)) {
                    if (r.witnessGas == 0) r.witnessGas = g;
                    ++r.witnessCount;
                } else {
                    emit log_named_bytes("unexpected revert", err);
                    emit log_named_uint("  at gas", g);
                }
            }
        }
        vm.revertToState(base);

        emit log_named_uint("owners", owners);
        emit log_named_uint("entries each", entries);
        emit log_named_uint("terminal word", word);
        emit log_named_uint("pre-batches", preBatches);
        emit log_named_uint("sweep step", step);
        emit log_named_uint("batchGas (full-gas batch under test)", r.batchGas);
        emit log_named_uint("minBatchOkGas (smallest limit the batch ran at)", r.minBatchOkGas);
        emit log_named_uint("payoutGas (payout-only fall-through, full gas)", r.payoutGas);
        emit log_named_uint("payoutMinGas (smallest limit completing it)", r.payoutMinGas);
        emit log_named_uint("payoutNeed (payout frame's gas at payoutMinGas)", r.payoutNeed);
        emit log_named_uint("payout-only: cohort credited (wei)", r.payoutCohortPaid);
        emit log_named_uint("payout-only: protocol deities credited (wei)", r.payoutDeityPaid);
        emit log_named_uint("maxFallthrough (most gas a starved batch leaves the payout frame)", r.maxFallthrough);
        emit log_named_uint("  at limit", r.maxFallthroughAt);
        emit log_named_uint("starved limits, nested round-drain OOG", r.nestedOogCount);
        emit log_named_uint("starved limits, worker-frame OOG", r.workerOogCount);
        emit log_named_uint("witnessGas (largest EmptyRevert/empty revert)", r.witnessGas);
        emit log_named_uint("witnessCount", r.witnessCount);
        emit log_named_uint("leakGas (largest leaking limit)", r.leakGas);
        emit log_named_uint("leakLow (smallest leaking limit)", r.leakLow);
        emit log_named_uint("leakCount", r.leakCount);

        // Honest completion from the same state, for the forfeiture comparison.
        uint256 unallocBefore = _unallocated();
        for (uint256 i; i < 100 && !game.gameOver(); ++i) game.advanceGame();
        assertTrue(game.gameOver(), "honest ending completes");
        (uint256 hrl,,) = _queues();
        (uint256 hOwed,) = _owedTotal();
        emit log_named_uint("unallocated before the ending (wei)", unallocBefore);
        emit log_named_uint("honest: cohort credited (wei)", _cohortClaimable());
        emit log_named_uint(
            "honest: protocol deities credited (wei)",
            game.claimableWinningsOf(ContractAddresses.VAULT) + game.claimableWinningsOf(ContractAddresses.SDGNRS)
        );
        emit log_named_uint("honest: left for the final sweep (wei)", _unallocated());
        emit log_named_uint("honest: read queue left", hrl);
        emit log_named_uint("honest: entries owed left", hOwed);
        if (r.leakGas != 0) {
            emit log_named_uint("leak: read queue left", leakRl);
            emit log_named_uint("leak: entries owed left", leakOwed);
            emit log_named_uint("leak: owners still owed", leakOwing);
            emit log_named_uint("leak: cohort credited (wei)", leakCohortPaid);
            emit log_named_uint("leak: protocol deities credited (wei)", leakDeityPaid);
            emit log_named_uint("leak: left for the final sweep (wei)", leakUnalloc);
        }
        vm.revertToState(base);
    }

    /// @dev The payout-only fall-through on the state under test: read queue released, buckets
    ///      as they are. Full-gas cost, the smallest limit completing it, and what the payout
    ///      frame receives at that limit.
    function _measurePayout(Sweep memory r) private {
        _seeder().releaseReadQueue(TLVL);
        _restore();
        uint256 post = vm.snapshotState();
        uint256 g0 = gasleft();
        game.advanceGame();
        r.payoutGas = g0 - gasleft();
        assertTrue(game.gameOver(), "payout-only call ends the game");
        r.payoutCohortPaid = _cohortClaimable();
        r.payoutDeityPaid =
            game.claimableWinningsOf(ContractAddresses.VAULT) + game.claimableWinningsOf(ContractAddresses.SDGNRS);
        uint256 lo;
        uint256 hi = r.payoutGas * 2;
        while (hi - lo > 16) {
            uint256 mid = (lo + hi) / 2;
            vm.revertToState(post);
            bool done;
            try game.advanceGame{gas: mid}() {
                done = game.gameOver();
            } catch {}
            if (done) hi = mid;
            else lo = mid;
        }
        r.payoutMinGas = hi;
        vm.revertToState(post);
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, type(PayoutGasProbe).runtimeCode);
        try game.advanceGame{gas: r.payoutMinGas}() {
            revert("probe must revert");
        } catch (bytes memory err) {
            assertEq(err.length, 32, "probe reading");
            r.payoutNeed = abi.decode(err, (uint256));
        }
    }

    /// @dev A terminal word whose four winning traits hold no entry at the states below and
    ///      name no protocol-deity symbol, so the payout pays nobody: its cheapest form.
    function _emptyBoardWord() private pure returns (uint256) {
        return uint256(keccak256(abi.encode("w", uint256(0))));
    }

    function _assertNoForfeit(Sweep memory r) private pure {
        assertEq(r.payoutCohortPaid + r.payoutDeityPaid, 0, "harness: the payout under test pays nobody");
        assertGt(r.witnessCount, 0, "the scan reached starved calls");
        assertLt(r.maxFallthrough, r.payoutNeed, "a starved batch leaves the payout less than it needs");
        assertEq(r.leakGas, 0, "a starved post-swap batch forfeited the terminal cohort");
    }

    /// @dev The pre-swap test's cohort shape (24 owners x 60 entries), now post-swap: the first
    ///      post-swap batch (cold-level derated budget), every trait bucket at drainLevel empty.
    function test_starvedPostSwapBatchCannotForfeitTheCohort() public {
        _assertNoForfeit(_sweep(24, 60, _emptyBoardWord(), 0, 1024));
    }

    /// @dev The closest shape found: few owners with large balances, so nearly the whole batch
    ///      is the nested round drain, on the second post-swap batch (the full budget, no cold-level derate).
    ///      The first batch left the four winning buckets empty, so the payout is still free.
    function test_starvedLaterPostSwapBatchCannotForfeitTheCohort() public {
        _assertNoForfeit(_sweep(8, 2000, _emptyBoardWord(), 1, 1024));
    }
}
