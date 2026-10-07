// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title TurboBafTicketFloor — BAF award tickets rolled onto the floor level under turbo.
///
/// @notice `_awardJackpotTickets` rolls a winner's lootbox leg into ticket entries at a level
///         >= the passed floor, and the roll's 30% leg can land ON the floor exactly. In a
///         NORMAL x10 jackpot phase the floor `lvl` is safe: the entries queue into the write
///         slot, jackpot day 2's swap commits them, and the jackpot-phase drain names lvl. A
///         TURBO phase (jackpotFlags >= 2) collapses all draws inside one RNG lock —
///         no further swap ever fires for the level (mid-day requests are locked out), and the
///         transition moves every later drain to lvl + 1 and beyond — so a floor-level award
///         queued during the collapse would sit at a key no drain ever names again.
///         `runBafJackpot` therefore latches the floor at lvl + 1 into the award record when the
///         flag reads >= 2, and the award stage (Advance stage 19) rolls every lootbox leg from it.
///
///         Drive: turbo-chain levels from genesis (seed the next pool over target every
///         purchase day, so each level collapses in one locked chain), deposit coinflips
///         daily so the buyer accrues BAF bracket-10 score (recordBafFlip on claim), and let
///         level 10's collapsed chain run its BAF. Reachability is asserted (turbo flag, the award
///         stage drained = epoch bump by `finalizeBaf`, award calls and BAF rolls observed, every
///         roll from the turbo floor), then: no entries may remain at level 10's queue keys.
contract TurboBafTicketFloor is DeployProtocol {
    address private buyer = address(0xB4A1);
    address private crank = address(0xC4A9);
    address private lateBuyer = address(0x1A7E);

    uint256 private simTime;

    bytes32 private constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    bytes32 private constant ETH_WIN_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 private constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    uint8 private constant STAGE_JACKPOT_BAF_AWARDS = 19;
    uint256 private constant BAF_TRAIT_SENTINEL = 420;
    uint256 private bafAwardCalls;
    uint256 private bafEthWins;
    uint256 private bafRolls;
    uint256 private bafRollsOffFloor;

    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev Clock offset folded into every fulfillment word (word = keccak(simTime, reqId)).
    ///      Chosen so the level-10 BAF's daily-flip bit lands 1 (a skipped BAF would leave
    ///      the floor path unexercised; the epoch reachability assert guards against that).
    uint256 private constant WORD_NUDGE = 1;

    function setUp() public {
        _deployProtocol();
        // Derive simTime arithmetically from ONE pre-warp timestamp read: a second
        // block.timestamp read after vm.warp can be CSE'd to the pre-warp value,
        // which would silently drop WORD_NUDGE from every fulfillment word.
        simTime = block.timestamp + 1 days + WORD_NUDGE;
        vm.warp(simTime);
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 500_000 ether);
        vm.deal(lateBuyer, 100 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
        // FLIP stake for daily coinflip deposits (BAF score accrues on claimed wins).
        deal(address(coin), buyer, 5_000_000 ether, true);
    }

    function testTurboBafFloorAwardsDoNotStrandAtTheCollapsedLevel() public {
        vm.pauseGasMetering();
        _driveThroughLevelTenTurbo();

        // Reachability: the level-10 phase collapsed under turbo and its BAF resolved.
        assertGe(
            _jackpotFlags(),
            2,
            "harness: level 10 must have collapsed under turbo (flag preserved as bonus latch)"
        );
        assertEq(
            _bafEpoch(10),
            1,
            "harness: the level-10 BAF must have resolved (epoch bump), not skipped"
        );
        // The award stage drained inside the collapsed chain: its calls ran, it paid awards, and
        // every lootbox roll started at the turbo floor.
        assertGt(bafAwardCalls, 0, "harness: the level-10 BAF awards are paid by the award stage");
        assertGt(bafRolls, 0, "harness: BAF lootbox legs rolled tickets");
        assertEq(bafRollsOffFloor, 0, "every BAF roll starts at the turbo floor (lvl + 1)");

        // Let the next level's purchase days drain the lvl+1 queues normally.
        _runFullDay();
        _runFullDay();

        assertEq(
            _queueLen(10) + _queueLen(10 | TICKET_SLOT_BIT),
            0,
            "no BAF award entries may strand at the collapsed level's queue keys"
        );
        assertEq(
            _owedOf(10, buyer) + _owedOf(10 | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may strand at the collapsed level"
        );
    }

    /// @notice The x0 evening latch (tier 2) keeps purchases open for the rest of the
    ///         sealed day, so a mid-day lootbox request can fire inside the window. Its
    ///         ticket-buffer swap must be refused: the next daily request is the
    ///         transition that collapses every draw under its lock, so a swapped cohort
    ///         crossed by a stall would sit write-side through the collapse — safe but
    ///         drawless. Drive: reach the level-10 latch day, fire a mid-day request
    ///         between two buys, assert no buffer flip while the isolated next-level
    ///         future pool activates, then cross WITHOUT fulfilling
    ///         (stall promotion) and run the collapse out. Nothing may strand at the
    ///         x0 level's keys.
    function testLatchDayMiddayRequestRefusesTheSwap() public {
        vm.pauseGasMetering();
        _driveToLevelTenLatchDay();

        _buyTickets();
        uint24 currentWriteKey = _ticketWriteSlot() ? 10 | TICKET_SLOT_BIT : 10;
        uint256 currentOwed = _owedOf(currentWriteKey, buyer);
        assertGt(_queueLen(11 | (uint24(1) << 22)), 0, "the ordinary daily left next-level tickets unminted");
        bool swapped = _middayRequest();
        assertFalse(
            swapped,
            "the latch-day mid-day request must not flip the ticket buffer"
        );
        assertFalse(
            _ticketsFullyProcessed(),
            "the mid-day request starts the isolated next-level batch"
        );
        assertEq((uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 224) & 0xFF, 2,
            "only the future pool is committed by this mid-day request");
        assertEq(_owedOf(currentWriteKey, buyer), currentOwed,
            "current-level tickets stay in the write buffer for the final daily request");
        _buyTicketsFor(lateBuyer);

        // Cross without fulfilling: the stalled request resolves via promotion or
        // orphan backfill, and the transition collapses the whole phase.
        _runPromotedCrossingDay();
        require(
            _level() >= 10,
            "harness: the level-10 transition must have run"
        );

        // Let the next level's purchase days drain any trailing keys.
        _runFullDay();
        _runFullDay();

        assertEq(
            _queueLen(10) + _queueLen(10 | TICKET_SLOT_BIT),
            0,
            "no cohort may strand at the collapsed x0 level's queue keys"
        );
        assertEq(
            _owedOf(10, buyer) + _owedOf(10 | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may strand at the collapsed x0 level"
        );
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    /// @dev Turbo-chain from genesis until level 10's jackpot phase has completed: every
    ///      purchase day seeds the next pool over target (purchaseDays <= 1 arms turbo), buys
    ///      tickets into the building level, and deposits coinflips for BAF score.
    function _driveThroughLevelTenTurbo() internal {
        // Settle the deploy-warp day first: warping over an un-advanced day makes the
        // next chain gap-backfill (purchaseStartDay += gap), which pushes purchaseDays
        // past 1 and structurally disarms turbo.
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(!game.gameOver(), "harness: gameOver before level 10");
            if (_level() >= 10 && !game.jackpotPhase()) return;
            if (!game.jackpotPhase()) {
                // Seed just over the ratcheting target (target(L+1) = levelPrizePool[L])
                // so every level arms turbo while the pools stay small enough that BAF
                // winner slices remain below the whale-pass threshold (ticket rolls).
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            vm.recordLogs();
            _runFullDay();
            _scanBafAwards(vm.getRecordedLogs());
        }
        revert("harness: never completed level 10");
    }

    /// @dev Counts the level-10 award-stage calls and BAF award events (the BAF sentinel trait).
    function _scanBafAwards(Vm.Log[] memory logs) internal {
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
            bytes32 sig = logs[j].topics[0];
            if (sig == ADVANCE_SIG) {
                (uint8 stage, uint24 lvl) = abi.decode(logs[j].data, (uint8, uint24));
                if (stage == STAGE_JACKPOT_BAF_AWARDS && lvl == 10) ++bafAwardCalls;
            } else if (sig == ETH_WIN_SIG && uint256(logs[j].topics[3]) == BAF_TRAIT_SENTINEL) {
                ++bafEthWins;
            } else if (sig == TICKET_WIN_SIG && uint256(logs[j].topics[3]) == BAF_TRAIT_SENTINEL) {
                ++bafRolls;
                (, uint24 source,,) = abi.decode(logs[j].data, (uint32, uint24, uint256, bool));
                if (source != 11 || uint256(logs[j].topics[2]) < 11) ++bafRollsOffFloor;
            }
        }
    }

    /// @dev Turbo-chain levels 1-9 (same seeding as above), stopping ON the day the
    ///      level-10 evening latch fires: lastPurchaseDay with the tier-2 flag, the
    ///      phase not yet entered — the x0 last-purchase window. purchaseInfo's lvl
    ///      runs one behind the level being sold, so the latch day reads lvl == 9.
    function _driveToLevelTenLatchDay() internal {
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(
                !game.gameOver(),
                "harness: gameOver before the level-10 latch"
            );
            (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9) {
                require(
                    _jackpotFlags() == 1,
                    "harness: the x0 latch must be tier 2"
                );
                return;
            }
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            _runFullDayUntilX0Latch();
        }
        revert("harness: never reached the level-10 latch day");
    }

    /// @dev `_runFullDay`, stopping at the call that seals the x0 latch: the engine would
    ///      otherwise go on to send the miner's own mid-day request in the latch window, and the
    ///      test fires that window's request itself.
    function _runFullDayUntilX0Latch() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
            (uint24 lvl, , bool lastPurchaseDay_, bool locked, ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9 && (!locked || (_jackpotFlags() == 1 && _requestInFlight()))) break;
        }
    }

    /// @dev True while the VRF coordinator holds an unanswered request.
    function _requestInFlight() internal view returns (bool) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (, , bool fulfilled) = mockVRF.pendingRequests(id);
        return !fulfilled;
    }

    /// @dev Run the advance chain to exhaustion on the current (already-warped) day.
    function _settleToday() internal {
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
        }
    }

    /// @dev levelPrizePool[lvl] — the mapping sits at slot 23. levelPrizePool[L] is the
    ///      target the NEXT level's pool must exceed; 0 until first recorded.
    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = uint256(
            vm.load(
                address(game),
                keccak256(abi.encode(uint256(lvl), GameSlots.LEVEL_PRIZE_POOL))
            )
        );
        return v < 50 ether ? 50 ether : v;
    }

    function _tryCoinflipDeposit() internal {
        vm.prank(buyer);
        try coinflip.depositCoinflip(0, 500) {} catch {}
    }

    // ---------------------------------------------------------------------
    // Helpers (shared shape with MiddaySwapJackpotCohort)
    // ---------------------------------------------------------------------

    /// @dev One driver step. The engine composes every admitted checkpoint into a call and the
    ///      miner now sends its own mid-day request whenever one is eligible (a shut Craps window
    ///      on the write buffer). The driver models the original keeper flow: each call gets the
    ///      smallest admitting allowance from a realistic ladder, and an optional mid-day request
    ///      is left to the test (treated as idle). Returns false when no work was done.
    function _mine() internal returns (bool) {
        if (game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.RequestMidday)) return false;
        uint256[6] memory ladder = [uint256(1_500_000), 2_500_000, 3_500_000, 5_000_000, 9_000_000, 16_777_216];
        for (uint256 r; r < ladder.length; ++r) {
            (bool ok, bytes memory err) = address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
            if (bytes4(err) != MineFlipGas.InsufficientExecutionGas.selector) return false;
        }
        return false;
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        // Bit 0 set: every daily flip wins, so the level-10 BAF resolves instead of skipping.
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId))) | 1;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _buyTickets() internal {
        _buyTicketsFor(buyer);
    }

    function _buyTicketsFor(address player) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(player);
        game.purchase{value: (priceWei * 4000) / 400}(
            0,
            4000,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    /// @dev Cross the day boundary and run the whole advance chain to the day seal.
    function _runFullDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
        }
    }

    /// @dev Buy a lootbox and fire a mid-day lootbox request; report whether the
    ///      ticket buffer flipped (shared shape with MiddaySwapJackpotCohort).
    function _middayRequest() internal returns (bool swapped) {
        // The window's mid-day request is whichever comes first: the miner sends its own as soon
        // as one is eligible (craps windows ride the normal RNG round), possibly while the
        // previous session's reads finish. Otherwise the crank sends it, funded by a lootbox.
        bool before = _ticketWriteSlot();
        if (_requestInFlight()) return false;
        if (_settleReadsUntilRequest()) return _ticketWriteSlot() != before;
        vm.prank(buyer);
        game.purchase{value: 2 ether}(
            0,
            0,
            BoxOrderLib.boCustom(2 ether),
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
        before = _ticketWriteSlot();
        uint256 priorReq = mockVRF.lastRequestId();
        vm.prank(crank);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("mineFlip()")
        );
        require(ok && mockVRF.lastRequestId() > priorReq, "harness: mineFlip must issue the mid-day request");
        swapped = _ticketWriteSlot() != before;
    }

    /// @dev Finish the session in flight with the smallest admitting allowances. Returns true,
    ///      leaving the word unanswered, as soon as the miner composes its own mid-day request.
    function _settleReadsUntilRequest() internal returns (bool minerRequested) {
        for (uint256 i; i < 300; ++i) {
            _fulfillPending();
            uint256 id = mockVRF.lastRequestId();
            (,, bool fulfilled) = mockVRF.pendingRequests(id);
            if (game.rngComplete() && (id == 0 || fulfilled)) return false;
            uint256[6] memory ladder = [uint256(2_700_000), 3_500_000, 4_500_000, 6_000_000, 9_000_000, 16_777_216];
            bool progressed;
            for (uint256 r; r < ladder.length && !progressed; ++r) {
                (bool ok, bytes memory err) = address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip()"));
                if (ok) progressed = true;
                else if (bytes4(err) == bytes4(keccak256("NoWork()"))) return false;
                else require(bytes4(err) == MineFlipGas.InsufficientExecutionGas.selector, "harness: reads settle");
            }
            require(progressed, "harness: reads settle within a realistic allowance");
            if (mockVRF.lastRequestId() != id) return true;
        }
        revert("harness: reads never settled");
    }

    /// @dev Cross the day boundary WITHOUT fulfilling the outstanding request, then
    ///      run the chain to exhaustion (fulfilling from the first loop entry on).
    function _runPromotedCrossingDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("mineFlip()")
        );
        ok; // the promotion entry may or may not revert once its stage breaks
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            ok = _mine();
            if (game.jackpotPhase()) _assertLateTicketsMaterialized();
            if (!ok) break;
        }
        _assertLateTicketsMaterialized();
    }

    function _assertLateTicketsMaterialized() internal view {
        assertEq(_owedOf(10, lateBuyer) + _owedOf(10 | TICKET_SLOT_BIT, lateBuyer), 0,
            "late tickets must leave the queue before the turbo jackpot");
        uint256 materialized;
        for (uint16 trait; trait < 256; ++trait) {
            (uint24 count,,) = game.getEntries(uint8(trait), 10, 0, type(uint32).max, lateBuyer);
            materialized += count;
        }
        assertEq(materialized, 40, "every post-request ticket must materialize before the collapse completes");
    }

    /// @dev Seed the live next-pool half (slot 2, low 128 bits) up to targetNext.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(2)),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }

    // ---- storage probes ----

    /// @dev _ticketQueueLength(key): queue roots recycle physical slots under an absolute-level
    ///      tag, so read the authenticated length for the logical key.
    function _queueLen(uint24 key) internal view returns (uint256) {
        return TicketQueueStorage.length(address(game), key);
    }

    /// @dev _owedOf(key, player) >> 8 — the mapping sits at slot 13.
    function _owedOf(
        uint24 key,
        address player
    ) internal view returns (uint256) {
        return uint32(TicketQueueStorage.owed(address(game), key, player) >> 8);
    }

    /// @dev level — slot 0, bytes [12:15).
    function _level() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 96);
    }

    /// @dev jackpotCounter — slot 0, byte 16.
    function _jackpotCounter() internal view returns (uint8) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(s0 >> 128);
    }

    /// @dev jackpotFlags — slot 0, byte 23.
    function _jackpotFlags() internal view returns (uint8) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(s0 >> 184);
    }

    /// @dev ticketsFullyProcessed — slot 0, byte 24 bit 0.
    function _ticketsFullyProcessed() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 192) & 1) != 0;
    }

    /// @dev Ticket write-slot parity bit — slot 0, byte 25 bit 0.
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 200) & 1) != 0;
    }

    /// @dev jackpots.bafLevel[lvl].epoch — the mapping sits at Jackpots slot 2; epoch is
    ///      the low uint64 of the packed struct slot.
    function _bafEpoch(uint24 lvl) internal view returns (uint64) {
        return
            uint64(
                uint256(
                    vm.load(
                        address(jackpots),
                        keccak256(abi.encode(uint256(lvl), uint256(2)))
                    )
                )
            );
    }
}
