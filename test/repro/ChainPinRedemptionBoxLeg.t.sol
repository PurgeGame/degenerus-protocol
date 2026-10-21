// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ChainPinFundHarness} from "./ChainPinRedemptionLedger.t.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

/// @notice A-F2 / I2: the inline redemption box leg (`Game.resolveRedemptionLootbox`, reached from
///         `sDGNRS.runRedemptionWork`) must never revert, in particular never with the shared ticket-queue
///         collision guard (selector 0x92bbf6e8: `_bindTicketQueue` / `_setEntryOwed`). A revert there stops
///         stage 1 and with it every later daily request.
///
///         The driver plays the real engine day by day (purchases with boxes, whale, lazy and deity passes,
///         ticket-mode AFKing subscribers, real sDGNRS burns that close into live batches, pool seeding that
///         turns levels over every few days, optional level teleports that stress queue parity and the
///         100-slot far-future ring). The miner is called with small gas so its chain stops between stages.
///         At every state where an RNG consumer stage is open (stage 1 runs first in it), a probe calls the
///         box leg as sDGNRS with a fuzzed beneficiary, size (0.01 ETH to 2,000 ETH, one to twenty boxes),
///         activity score, entropy and batch tag. Real settlements run in the same loop: a selected
///         Redemption action that reverts, or that the Game's stage view would block, fails the test.
///         The funding identities (reserve <= claimablePool, custody + reserve >= pending value) are checked
///         at every step of the real engine as well.
contract ChainPinRedemptionBoxLeg is DeployProtocol {
    uint256 internal constant N = 6;
    bytes32 internal constant ENTRIES_QUEUED = keccak256("EntriesQueued(uint32,uint24,uint32)");
    bytes4 internal constant TICKET_GUARD = 0x92bbf6e8;
    /// @dev Gas metering stays on (the miner's meters must see real gas), so the day loops stop before the test's
    ///      own gas runs out.
    uint256 internal constant GAS_FLOOR = 1_500_000_000;

    address[] internal cast;
    uint32[] internal ids;
    uint256[] internal seats;
    uint256 internal simTime;
    uint256 internal salt;

    // Non-vacuity tallies.
    uint256 internal nProbes;
    uint256 internal nProbeNormal;
    uint256 internal nProbeFar;
    uint256 internal nBurns;
    uint256 internal nRedemptionSteps;
    uint256 internal nBatchesSettled;
    uint256 internal nSubscribed;
    uint256 internal nPasses;
    uint256 internal nSteps;
    uint256 internal nFails;
    uint256 internal nWaitBreaks;
    uint256 internal nCapHits;
    uint256 internal lastCapAct;
    uint256 internal lastFailAct;
    bytes4 internal lastFailSel;
    uint24 internal startLevel;
    uint24 internal maxLevel;
    mapping(uint256 => uint256) internal offsetHits; // target level - level at the probe

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000 ether);
        vm.deal(address(game), 50_000 ether);
        _etchFund(abi.encodeCall(ChainPinFundHarness.fund, (5_000 ether)));
        simTime = block.timestamp;
        for (uint256 i; i < N; ++i) {
            address who = address(uint160(0xB0B0000 + i));
            cast.push(who);
            vm.deal(who, 200_000 ether);
            ids.push(_giveWalletId(who));
        }
        ids.push(1); // the Vault, a claimant through its allowlisted burn doors
        uint256 share = sdgnrs.totalSupply() * 15 / 1000;
        vm.startPrank(address(game));
        for (uint256 i; i < N; ++i) sdgnrs.transferFromPool(sDGNRS.Pool.Reward, cast[i], share);
        vm.stopPrank();
        _finishSubscriptionWindow();
        for (uint256 i; i < 3; ++i) seats.push(_grantSeat(cast[i]));
    }

    // ---------------------------------------------------------------------
    // Test entry points
    // ---------------------------------------------------------------------

    /// @notice Fuzz over action schedules and the level teleport (queue parity and ring slot of the start level).
    /// forge-config: default.fuzz.runs = 6
    function testFuzz_boxLegNeverTripsTicketGuard(uint256 seed, uint256 jumpSel) public {
        _run(seed, jumpSel, 30);
    }

    /// @notice Non-vacuity: a fixed organic run reaches several levels, opens real settlements, probes at
    ///         near-level and far-future keys, and queues tickets for many different target offsets.
    function test_driverExercisesTheBoxLegNonVacuously() public {
        _run(0xA11CE, 0, 40);
        console.log("maxLevel", maxLevel);
        console.log("level", game.level(), "steps", nSteps);
        console.log("fails", nFails, "waits", nWaitBreaks);
        console.log("capHits", nCapHits, "lastCapAct", lastCapAct);
        console.log("lastFailAct", lastFailAct);
        console.logBytes4(lastFailSel);
        console.log("probes", nProbes, "burns", nBurns);
        console.log("settled", nBatchesSettled, "subs", nSubscribed);
        assertGe(maxLevel, startLevel + 3, "the engine turned levels over");
        assertGt(nProbes, 12, "probes ran");
        assertGt(nProbeNormal, 0, "probes wrote normal-key tickets");
        assertGt(nProbeFar, 0, "probes wrote far-future tickets");
        assertGt(nBurns, 0, "real sDGNRS burns were submitted");
        assertGt(nBatchesSettled, 0, "real redemption batches settled inline");
        assertGt(nRedemptionSteps, 0, "the miner selected the Redemption action");
        assertGt(nSubscribed, 0, "ticket-mode AFKing subscribers existed");
        assertGt(nPasses, 0, "whale/lazy/deity passes queued far-future tickets");
        uint256 distinct;
        for (uint256 o = 1; o <= 51; ++o) if (offsetHits[o] != 0) ++distinct;
        assertGt(distinct, 10, "box rolls reached many target levels");
    }

    // ---------------------------------------------------------------------
    // Driver
    // ---------------------------------------------------------------------

    function _etchFund(bytes memory call_) internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(ChainPinFundHarness).runtimeCode);
        (bool ok,) = address(game).call(call_);
        require(ok, "fund harness");
        vm.etch(address(game), code);
    }

    function _rand() internal returns (uint256) {
        salt = uint256(keccak256(abi.encode(salt, block.timestamp, nSteps)));
        return salt;
    }

    function _run(uint256 seed, uint256 jumpSel, uint256 days_) internal {
        salt = seed;
        startLevel = game.level();
        // Organic play to level 2 (the teleport needs a live level >= 2).
        uint256 d;
        for (; d < 80 && game.level() < 2 && !game.gameOver() && gasleft() > GAS_FLOOR; ++d) _playDay(_rand(), d);
        if (jumpSel % 5 != 0 && game.level() >= 2 && !game.gameOver()) {
            uint24 target = jumpSel % 2 == 0
                ? uint24(3 + (jumpSel >> 1) % 330)
                : uint24(100 * (1 + (jumpSel >> 1) % 4) - 1 - (jumpSel >> 4) % 3);
            vm.mockCall(ContractAddresses.GNRUS, abi.encodeWithSignature("pickCharity(uint24)"), abi.encode());
            _jumpLevel(target);
            vm.deal(address(game), address(game).balance + 20_000 ether);
            startLevel = target;
        }
        for (uint256 k; k < days_ && !game.gameOver() && gasleft() > GAS_FLOOR; ++k) _playDay(_rand(), d + k);
    }

    /// @dev Teleport a live game (level >= 2) to `lvl`: the level, both trait-buffer stamps, and every skipped
    ///      level's queues retired (same recipe as the census boundary campaigns).
    function _jumpLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(0)));
        s0 = (s0 & ~(uint256(0xFFFFFF) << 96)) | (uint256(lvl) << 96);
        vm.store(address(game), bytes32(0), bytes32(s0));
        uint256 s5 = uint256(vm.load(address(game), bytes32(uint256(5))));
        uint48 stamps = uint48(uint256(lvl) << ((lvl & 1) * 24) | uint256(lvl + 1) << (((lvl + 1) & 1) * 24));
        vm.store(address(game), bytes32(uint256(5)), bytes32((s5 & ~(uint256(type(uint48).max) << 80)) | (uint256(stamps) << 80)));
        TicketQueueStorage.retireCompleted(address(game), lvl + 1);
    }

    function _seedNextPool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        if (uint128(packed) >= targetNext) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((packed & ~uint256(type(uint128).max)) | targetNext));
    }

    function _fulfillPending(uint256 r) internal returns (bool answered) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (done) return false;
        mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode(r, req))) | 2);
        return true;
    }

    function _playDay(uint256 r, uint256) internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        if (r % 5 != 0) _seedNextPool(game.prizePoolTargetView() + 0.01 ether);
        for (uint256 a; a < 4; ++a) _act(uint256(keccak256(abi.encode(r, a))));
        _drive(r);
        // Signup opens once the day is complete: ticket-mode AFKing subscribers join for tomorrow.
        for (uint256 i; i < 3; ++i) {
            if ((r >> (i * 4)) % 3 != 0) continue;
            vm.prank(cast[i]);
            try game.subscribe{value: 20 ether}(0, true, uint8(1 + (r >> (i * 8 + 12)) % 3), seats[i]) {
                ++nSubscribed;
            } catch {}
        }
        uint24 lvl = game.level();
        if (lvl > maxLevel) maxLevel = lvl;
    }

    function _act(uint256 r) internal {
        address who = cast[(r >> 8) % N];
        uint256 kind = r % 11;
        uint256 price = game.mintPrice();
        if (kind <= 3) {
            uint256 tix = 1 + (r >> 16) % 30;
            uint256 pick = (r >> 24) % 5;
            uint256 box = pick == 0 ? 0 : pick == 1 ? 0.05 ether : pick == 2 ? 1 ether : pick == 3 ? 6 ether : 40 ether;
            vm.prank(who);
            try game.purchase{value: tix * price + box + 1 ether}(
                0, tix * 400, box == 0 ? 0 : BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false
            ) {} catch {}
        } else if (kind == 4 || kind == 5) {
            vm.prank(who);
            try game.purchaseWhalePass{value: 4 ether * (1 + (r >> 16) % 3) + 1 ether}(0, 1 + (r >> 16) % 3, bytes32(0)) {
                ++nPasses;
            } catch {}
        } else if (kind == 6) {
            vm.prank(who);
            try game.purchaseLazyPass{value: 10 ether}(0, bytes32(0)) {
                ++nPasses;
            } catch {}
        } else if (kind == 7) {
            vm.prank(who);
            try game.purchaseDeityPass{value: 150 ether}(0, uint8((r >> 16) % 32), bytes32(0)) {
                ++nPasses;
            } catch {}
        } else if (kind == 9) {
            uint256 bal = sdgnrs.balanceOf(who);
            if (bal != 0) {
                vm.prank(who);
                try sdgnrs.burn(bal / (3 + (r >> 16) % 40) + 1) {
                    ++nBurns;
                } catch {}
            }
        }
        // kind 10: idle.
    }

    function _drive(uint256 r) internal {
        bool wasSettling = sdgnrs.redemptionSettlementPending();
        for (uint256 j; j < 400; ++j) {
            if (j == 399) {
                ++nCapHits;
                lastCapAct = game.nextMinerAction();
            }
            ++nSteps;
            uint256 rj = uint256(keccak256(abi.encode(r, j)));
            _fulfillPending(rj);
            uint8 act = game.nextMinerAction();
            if (act == 0) break; // Idle
            if (act == 2) {
                ++nWaitBreaks;
                break; // Wait on a word nobody can answer
            }
            if (act == 8) {
                ++nRedemptionSteps;
                assertEq(game.rngConsumerStage(), 1, "A-F1: a selected Redemption action meets RedemptionStageBlocked");
            }
            if (rj % 3 != 0) _probe(rj);
            uint256 gas_ = [uint256(900_000), 1_500_000, 3_000_000, 6_000_000][(rj >> 8) & 3];
            bool ok;
            bytes memory data;
            // A refusal for gas is retried with more; anything else on stage 1 is the brick.
            for (uint256 attempt; attempt < 3; ++attempt) {
                (ok, data) = address(game).call{gas: attempt == 0 ? gas_ : attempt == 1 ? 16_000_000 : 28_000_000}(
                    abi.encodeWithSignature("mineFlip(uint32)", uint32(0))
                );
                if (ok) break;
            }
            if (!ok && act == 8) revert(string.concat("STAGE 1 REVERTED: ", vm.toString(data)));
            _assertFunding();
            bool settling = sdgnrs.redemptionSettlementPending();
            if (wasSettling && !settling) ++nBatchesSettled;
            wasSettling = settling;
            if (!ok) {
                ++nFails;
                lastFailAct = act;
                lastFailSel = bytes4(data);
                break;
            }
        }
    }

    function _assertFunding() internal {
        uint256 reserve = game.redemptionReserve();
        assertLe(reserve, game.claimablePoolView(), "A-F4: redemption reserve exceeds claimablePool");
        assertGe(reserve, sdgnrs.pendingRedemptionEthValue(), "A-F3: Game reserve < pending redemption value");
    }

    // ---------------------------------------------------------------------
    // Probe: the box leg at the current state
    // ---------------------------------------------------------------------

    function _amount(uint256 r) internal pure returns (uint256) {
        uint256 pick = r % 8;
        if (pick == 0) return 0.01 ether;
        if (pick == 1) return 0.01 ether + (r >> 8) % 1 ether;
        if (pick == 2) return 1 ether + (r >> 8) % 19 ether;
        if (pick == 3) return 19 ether + (r >> 8) % 3 ether; // straddles the 20-box switch
        if (pick == 4) return 20 ether + (r >> 8) % 400 ether;
        if (pick == 5) return 1_000 ether + (r >> 8) % 2_000 ether;
        if (pick == 6) return 40_000 ether + (r >> 8) % 4_000_000 ether;
        return 1 ether;
    }

    function _probe(uint256 r) internal {
        uint8 stage = game.rngConsumerStage();
        if (stage == 0 || stage == 7) return; // no consumer open: stage 1 cannot run here
        uint32 id = ids[(r >> 3) % ids.length];
        uint256 amount = _amount(r >> 11);
        uint16 score = uint16((r >> 40) % 65535);
        uint256 word = uint256(keccak256(abi.encode(r, "box")));
        uint32 batch = uint32(r >> 90);
        uint24 lvl = game.level();
        // Sizes beyond what an actor buys are probed on a snapshot: their ticket and prize-pool consequences would
        // otherwise swamp the engine that the later steps drive.
        bool isolate = amount > 420 ether;
        uint256 snap;
        if (isolate) snap = vm.snapshotState();
        // The leg draws the protected reserve: stock it with exactly this order's value (ETH included).
        vm.deal(address(game), address(game).balance + amount);
        _etchFund(abi.encodeCall(ChainPinFundHarness.fundReserve, (amount)));
        vm.recordLogs();
        vm.prank(address(sdgnrs));
        (bool ok, bytes memory data) = address(game).call(
            abi.encodeCall(game.resolveRedemptionLootbox, (id, amount, word, score, batch))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (!ok) {
            string memory why = bytes4(data) == TICKET_GUARD ? "TICKET QUEUE COLLISION GUARD 0x92bbf6e8" : "BOX LEG REVERTED";
            revert(string.concat(
                why, " level ", vm.toString(uint256(lvl)), " amount ", vm.toString(amount), " id ", vm.toString(uint256(id)),
                " data ", vm.toString(data)
            ));
        }
        if (isolate) {
            assertTrue(vm.revertToState(snap));
            return;
        }
        ++nProbes;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != ENTRIES_QUEUED) continue;
            (uint24 target,) = abi.decode(logs[i].data, (uint24, uint32));
            uint256 off = uint256(target) - lvl;
            if (off <= 51) ++offsetHits[off];
            if (off <= 1) ++nProbeNormal;
            else ++nProbeFar;
        }
    }
}
