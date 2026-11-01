// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {MissingWordDrainHarness, TerminalSinkStub} from "../repro/DegradeTerminalMissingWord.t.sol";

/// @dev Etch overlay that puts the Game in one of the states from which an ending starts, then
///      adds paid deities, a bystander claim and Degenesis balances through the production
///      storage setters. Every measured call runs the production runtime (restored after seeding).
contract DeityRefundSeeder is DegenerusGame, BucketSeed {
    function terminalPaidSlot() external pure returns (bytes32 slot) {
        assembly ("memory-safe") { slot := gameOverStatePacked.slot }
    }

    /// @dev Caught-up game whose last completed day finished `ago` seconds ago, `age` completed
    ///      days after the level's purchase start. age 30 with ago 1 day is the purchase timeout.
    ///      Winning buckets for `word` sit at the terminal ticket level (lvl + 1).
    function seedIdle(uint256 word, uint24 lvl, uint24 age, uint256 ago) external {
        uint24 day = _wallDay();
        level = lvl;
        dailyIdx = day - 1;
        purchaseStartDay = dailyIdx - age;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - ago);
        lastDailyRequestWallDay = _wallDayAt(lastDailyCompletedAt);
        _setLevelPrizePool(lvl, 1000 ether);
        ticketsFullyProcessed = true;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(lvl + 1, traits[q], 5000, uint160(0x7E000000 + uint256(q) * 0x100000));
        }
    }

    /// @dev A daily request sent `sentAgo` seconds ago and never answered, with a recent completion,
    ///      so only the request's own 14-day window can end the game.
    function seedRequestStall(uint24 lvl, uint256 sentAgo) external {
        TQ.retireCompleted(address(this), lvl);
        uint24 day = _wallDay();
        purchaseStartDay = day - 10;
        dailyIdx = day - 15;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = true;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 777;
        _setRngRequest(777);
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp - sentAgo);
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
    }

    /// @dev Paid deities after the two genesis deities, in registration order.
    function seedDeities(uint96[] calldata prices) external {
        for (uint256 i; i < prices.length; ++i) {
            uint32 id = _seedDeity(address(uint160(0xD3170000 + i)));
            deityPassPricePaid[id] = prices[i];
        }
    }

    /// @dev A bystander's earned claim, as a payout would leave it: ledger and claimablePool together.
    function seedBystander(address who, uint256 amount) external {
        _creditClaimableLogged(_seedWallet(who), amount);
        claimablePool += uint128(amount);
    }

    /// @dev Restricted Degenesis balances inside claimablePool: the Vault budget and sDGNRS AFKing.
    function seedDegenesis(uint128 vault, uint128 sdgnrsAfking) external {
        degenesisVaultBudget = vault;
        balancesPacked[SDGNRS_WALLET_ID] += uint256(sdgnrsAfking) << 128;
        claimablePool += vault + sdgnrsAfking;
    }
}

/// @title DeityRefundEligibility
/// @notice Paid deity-pass refunds happen only on the deterministic (dead or stalled) ending at
///         levels 0-9. A normal purchase-timeout ending refunds nothing and sends the whole
///         distributable balance to the terminal ticket prizes; level 10 and above never refunds.
///         Refund credits are told apart from ticket winnings by the aggregate event, the
///         claimablePool the drain reports, and the deities' own ledgers.
abstract contract DeityRefundBase is DeployProtocol {
    uint256 internal constant WORD = uint256(keccak256("cold-terminal-full-payout")) | 1;
    uint256 internal constant CAP = 20 ether;
    bytes32 internal constant REFUNDS_SIG = keccak256("DeityPassRefundsSettled(uint256)");
    bytes32 internal constant DRAINED_SIG = keccak256("GameOverDrained(uint24,uint256,uint256)");
    bytes32 internal constant RELEASED_SIG = keccak256("DegenesisFundsReleased(uint256,uint256)");
    bytes32 internal constant FIXED_SIG = keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)");
    bytes32 internal constant WIN_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    bytes internal realCode;
    bytes32 internal paidSlot;
    uint256 internal constant GAS = 11_500_000 - 21_192;

    struct Spec {
        uint24 lvl;
        uint96[] prices; // paid deities after the two genesis deities, purchase order
        uint256 slack; // funds above claimablePool when the ending starts
        uint256 bystander; // an earned claim reserved in claimablePool
        uint128 vault; // Degenesis Vault budget
        uint128 sdgnrs; // sDGNRS AFKing funding
    }

    struct Obs {
        uint256 refundEvents;
        uint256 refunds;
        uint256 drainedEvents;
        uint256 available;
        uint256 poolAtDrain;
        uint256 released;
        uint256 fixedEvents;
        uint24 fixedLevel;
        uint256 pot;
        uint256 awarded;
        uint256 calls;
    }

    function setUp() public virtual {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint24 lastSealedDay = game.currentWallDayView() - 1;
        _seedLogicalFixtureDay(lastSealedDay);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, WORD, lastSealedDay);
        realCode = address(game).code;
        vm.etch(address(game), type(DeityRefundSeeder).runtimeCode);
        paidSlot = DeityRefundSeeder(payable(address(game))).terminalPaidSlot();
        vm.etch(address(game), realCode);
    }

    function _seeder() internal returns (DeityRefundSeeder s) {
        vm.etch(address(game), type(DeityRefundSeeder).runtimeCode);
        s = DeityRefundSeeder(payable(address(game)));
    }

    function _restore() internal {
        vm.etch(address(game), realCode);
    }

    function _owner(uint256 i) internal pure returns (address) {
        return address(uint160(0xD3170000 + i));
    }

    /// @dev Add the spec's holdings and fund the Game with claimablePool + slack. Returns the pool.
    function _fund(Spec memory s) internal returns (uint256 pool) {
        DeityRefundSeeder seeder = _seeder();
        seeder.seedDeities(s.prices);
        if (s.bystander != 0) seeder.seedBystander(address(0xB157), s.bystander);
        if (s.vault != 0 || s.sdgnrs != 0) seeder.seedDegenesis(s.vault, s.sdgnrs);
        _restore();
        pool = game.claimablePoolView();
        vm.deal(address(game), pool + s.slack);
    }

    function _terminalPaid() internal view returns (bool) {
        return (uint256(vm.load(address(game), paidSlot)) >> 48) & 0xff != 0;
    }

    function _observe(Obs memory o, Vm.Log[] memory logs) internal pure {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].emitter != ContractAddresses.GAME) continue;
            bytes32 t = logs[i].topics[0];
            if (t == REFUNDS_SIG) {
                ++o.refundEvents;
                o.refunds += abi.decode(logs[i].data, (uint256));
            } else if (t == DRAINED_SIG) {
                ++o.drainedEvents;
                (, o.available, o.poolAtDrain) = abi.decode(logs[i].data, (uint24, uint256, uint256));
            } else if (t == RELEASED_SIG) {
                (uint256 v, uint256 s) = abi.decode(logs[i].data, (uint256, uint256));
                o.released += v + s;
            } else if (t == FIXED_SIG) {
                ++o.fixedEvents;
                o.fixedLevel = uint24(uint256(logs[i].topics[1]));
                (o.pot,,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            } else if (t == WIN_SIG) {
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                o.awarded += amount;
            }
        }
    }

    /// @dev One engine call at `gas_`, its logs folded into `o`.
    function _mine(Obs memory o, uint256 gas_) internal {
        vm.recordLogs();
        (bool ok,) = address(game).call{gas: gas_}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        ok;
        _observe(o, vm.getRecordedLogs());
        ++o.calls;
    }

    function _fulfil() internal returns (bool done) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(id);
        if (fulfilled) return false;
        mockVRF.fulfillRandomWords(id, WORD);
        return true;
    }

    /// @dev Deterministic ending: no entropy is used, so requests are left unanswered.
    function _runDead(Obs memory o) internal {
        for (uint256 i; i < 60 && !_terminalPaid(); ++i) _mine(o, 10_000_000);
        assertTrue(game.gameOver(), "the ending latched gameOver");
        assertTrue(_terminalPaid(), "the ending finished");
    }

    /// @dev Normal ending: the decision, the (empty) loan book, then the ending's own terminal
    ///      request, answered with the word the buckets were seeded for.
    function _runNormal(Obs memory o) internal {
        _startNormal(o);
        _finishNormal(o);
    }

    function _startNormal(Obs memory o) internal {
        _mine(o, GAS); // decision
        _mine(o, GAS); // the loan book
        _mine(o, GAS); // terminal request
        assertFalse(game.gameOver(), "the payout waits for the terminal word");
    }

    function _finishNormal(Obs memory o) internal {
        _fulfil();
        for (uint256 i; i < 16 && !_terminalPaid(); ++i) {
            _fulfil();
            _mine(o, GAS);
        }
        assertTrue(_terminalPaid(), "the normal ending finished");
    }

    // ---------------------------------------------------------------- reference model

    /// @dev FIFO refund per deity (genesis deities first, no basis) against `budget`.
    function _expected(uint96[] memory prices, uint256 budget) internal pure returns (uint256 total, uint256[] memory each) {
        each = new uint256[](prices.length);
        for (uint256 i; i < prices.length && budget != 0; ++i) {
            uint256 r = prices[i];
            if (r > CAP) r = CAP;
            if (r > budget) r = budget;
            each[i] = r;
            budget -= r;
            total += r;
        }
    }

    function _ledgers(uint256 n) internal view returns (uint256[] memory l) {
        l = new uint256[](n);
        for (uint256 i; i < n; ++i) l[i] = game.claimableWinningsOf(_owner(i));
    }

    function _prices(uint256 n, uint256 seed) internal pure returns (uint96[] memory p) {
        p = new uint96[](n);
        for (uint256 i; i < n; ++i) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            p[i] = uint96((h % 3 == 0 ? 0 : 1 ether + (h >> 8) % 60 ether));
        }
    }

    /// @dev Assert a deterministic ending's accounting against the reference model.
    function _assertDead(Spec memory s, Obs memory o, uint256 pool, uint256[] memory before_) internal view {
        bool refundsEligible = s.lvl < 10;
        (uint256 want, uint256[] memory each) = _expected(s.prices, refundsEligible ? s.slack : 0);
        uint256 released = uint256(s.vault) + s.sdgnrs;
        assertEq(o.refunds, want, "aggregate refund equals the capped FIFO model");
        assertEq(o.refundEvents, want == 0 ? 0 : 1, "one aggregate event exactly when something is refunded");
        uint256[] memory afterL = _ledgers(s.prices.length);
        for (uint256 i; i < each.length; ++i) {
            assertEq(afterL[i] - before_[i], each[i], "each deity is credited its own refund");
        }
        // Conservation: reserved claims + refunds + the terminal pot are exactly the funds; the
        // Degenesis balances left the reservation without enlarging the refund budget.
        uint256 funds = pool + s.slack;
        uint256 poolAfter = pool - released + want;
        assertEq(game.claimablePoolView(), poolAfter, "claimablePool = reserved - released + refunds");
        assertLe(want, s.slack, "refunds never exceed the pre-release distributable budget");
        uint256 avail = funds - poolAfter;
        assertEq(avail, s.slack + released - want, "terminal pot = distributable + released - refunds");
        if (avail == 0) {
            assertEq(o.drainedEvents, 0, "nothing distributable: no drain event");
            assertEq(o.fixedEvents, 0, "nothing distributable: no pot fixed");
        } else {
            assertEq(o.drainedEvents, 1);
            assertEq(o.available, avail, "drain reports the exact terminal budget");
            assertEq(o.poolAtDrain, poolAfter, "drain reports claimablePool after refunds and release");
            assertEq(o.fixedEvents, 1, "deterministic ending fixes its pot once");
            assertEq(o.pot, avail, "the fixed pot is the whole terminal budget");
        }
    }
}

/// @notice Endings driven through the real engine (`mineRun`), their states seeded by etch overlay.
contract DeityRefundEligibilityTest is DeityRefundBase {
    // ---------------------------------------------------------------- state builders

    function _deadSpec(uint24 lvl, uint96[] memory prices, uint256 slack) internal pure returns (Spec memory s) {
        s.lvl = lvl;
        s.prices = prices;
        s.slack = slack;
    }

    /// @dev Request unanswered past 14 days: the dead ending, every ending detail from storage.
    function _dead(Spec memory s) internal returns (Obs memory o, uint256 pool, uint256[] memory before_) {
        _seeder().seedRequestStall(s.lvl, 15 days);
        _restore();
        pool = _fund(s);
        assertTrue(game.livenessTriggered(), "stalled request: ending on");
        before_ = _ledgers(s.prices.length);
        _runDead(o);
    }

    function _normal(Spec memory s) internal returns (Obs memory o, uint256 pool) {
        _seeder().seedIdle(WORD, s.lvl, 30, 1 days);
        _restore();
        pool = _fund(s);
        assertTrue(game.livenessTriggered(), "purchase timeout: ending on");
        _runNormal(o);
    }

    function _assertNormal(Spec memory s, Obs memory o, uint256 pool) internal view {
        uint256 released = uint256(s.vault) + s.sdgnrs;
        assertEq(o.refundEvents, 0, "a normal ending emits no refund event");
        assertEq(o.refunds, 0);
        assertEq(o.fixedEvents, 0, "no deterministic pot on a normal ending");
        uint256 avail = s.slack + released;
        if (avail == 0) {
            assertEq(o.drainedEvents, 0);
        } else {
            assertEq(o.drainedEvents, 1);
            assertEq(o.available, avail, "the full distributable balance is the terminal prize budget");
            assertEq(o.poolAtDrain, pool - released, "claimablePool carries no refund credit");
            // The prizes credit exactly what was awarded on top of the reserved claims.
            assertApproxEqAbs(o.awarded, avail, 400, "the terminal tickets receive the whole budget");
            assertEq(game.claimablePoolView(), pool - released + o.awarded, "reserved claims + awards = claimablePool");
        }
    }

    // ---------------------------------------------------------------- normal ending: never a refund

    function _normalAt(uint24 lvl) internal {
        Spec memory s = _deadSpec(lvl, _prices(30, lvl), 5000 ether);
        s.vault = 3 ether;
        s.sdgnrs = 1 ether;
        (Obs memory o, uint256 pool) = _normal(s);
        _assertNormal(s, o, pool);
        assertTrue(game.gameOver());
    }

    function test_NormalEnding_Level0_PaidDeities_NoRefund() public { _normalAt(0); }
    function test_NormalEnding_Level9_PaidDeities_NoRefund() public { _normalAt(9); }
    function test_NormalEnding_Level10_NoRefund() public { _normalAt(10); }
    function test_NormalEnding_Level100_NoRefund() public { _normalAt(100); }

    /// @dev The cold-terminal shape: 30 paid deities at 20 ETH and 5,000 ETH leave the whole 5,000
    ///      for the terminal tickets (previously 600 ETH of it went to refunds).
    function test_NormalEnding_ThirtyFullPriceDeities_WholePotToTickets() public {
        uint96[] memory p = new uint96[](30);
        for (uint256 i; i < 30; ++i) p[i] = 20 ether;
        Spec memory s = _deadSpec(9, p, 5000 ether);
        (Obs memory o, uint256 pool) = _normal(s);
        _assertNormal(s, o, pool);
        assertEq(o.available, 5000 ether);
    }

    /// forge-config: default.fuzz.runs = 6
    function testFuzz_NormalEnding_NeverRefunds(uint24 lvlSeed, uint8 n, uint256 seed, uint256 slack, uint128 vault, uint128 sd)
        public
    {
        Spec memory s = _deadSpec(uint24(bound(lvlSeed, 0, 400)), _prices(bound(n, 0, 30), seed), bound(slack, 0, 6000 ether));
        s.vault = uint128(bound(vault, 0, 50 ether));
        s.sdgnrs = uint128(bound(sd, 0, 50 ether));
        s.bystander = bound(seed, 0, 100 ether);
        (Obs memory o, uint256 pool) = _normal(s);
        _assertNormal(s, o, pool);
    }

    // ---------------------------------------------------------------- deterministic ending

    function _deadAt(uint24 lvl, uint96[] memory prices, uint256 slack) internal returns (Obs memory o) {
        Spec memory s = _deadSpec(lvl, prices, slack);
        uint256 pool;
        uint256[] memory before_;
        (o, pool, before_) = _dead(s);
        _assertDead(s, o, pool, before_);
    }

    function test_DeadEnding_Level0_CappedRefunds() public {
        Obs memory o = _deadAt(0, _prices(30, 1), 5000 ether);
        assertGt(o.refunds, 0, "paid deities refunded at level 0");
    }

    function test_DeadEnding_Level9_CappedRefunds() public {
        Obs memory o = _deadAt(9, _prices(30, 2), 5000 ether);
        assertGt(o.refunds, 0, "paid deities refunded at level 9");
    }

    function test_DeadEnding_Level10AndAbove_NoRefund() public {
        uint24[3] memory levels = [uint24(10), 11, 250];
        for (uint256 i; i < levels.length; ++i) {
            uint256 snap = vm.snapshotState();
            Obs memory o = _deadAt(levels[i], _prices(30, 3), 5000 ether);
            assertEq(o.refundEvents, 0, "no refund event at level 10 and above");
            assertEq(o.refunds, 0);
            assertTrue(o.fixedEvents == 1 && o.pot == 5000 ether, "the whole balance is the dead pot");
            vm.revertToState(snap);
        }
    }

    /// @dev Level 9 pays level 10 tickets; eligibility follows the game level (9), not the ticket level.
    function test_Level9Ending_PaysLevel10Tickets_RefundFollowsGameLevel() public {
        uint256 snap = vm.snapshotState();
        Obs memory o = _deadAt(9, _prices(5, 4), 5000 ether);
        assertEq(o.fixedLevel, 10, "level 10 tickets are paid");
        assertGt(o.refunds, 0, "refunds follow game level 9");
        vm.revertToState(snap);
        o = _deadAt(10, _prices(5, 4), 5000 ether);
        assertEq(o.fixedLevel, 11, "level 11 tickets are paid");
        assertEq(o.refunds, 0, "game level 10: no refund");
    }

    function test_PricesCapsAndZeroBasis() public {
        // discounted (12), exactly the cap (20), above the cap (27 and 30), no recorded payment (0).
        uint96[] memory p = new uint96[](5);
        p[0] = 12 ether;
        p[1] = 20 ether;
        p[2] = 27 ether;
        p[3] = 0;
        p[4] = 30 ether;
        Spec memory s = _deadSpec(4, p, 1000 ether);
        (Obs memory o, uint256 pool, uint256[] memory b) = _dead(s);
        _assertDead(s, o, pool, b);
        assertEq(o.refunds, 12 ether + 20 ether + 20 ether + 0 + 20 ether, "actual price, cap, cap, zero, cap");
        uint256[] memory a = _ledgers(5);
        assertEq(a[0] - b[0], 12 ether);
        assertEq(a[1] - b[1], 20 ether);
        assertEq(a[2] - b[2], 20 ether);
        assertEq(a[3] - b[3], 0);
        assertEq(a[4] - b[4], 20 ether);
    }

    function test_InsufficientFunds_FifoBudget_ClaimsStayReserved() public {
        uint96[] memory p = new uint96[](3);
        p[0] = 20 ether;
        p[1] = 20 ether;
        p[2] = 20 ether;
        Spec memory s = _deadSpec(2, p, 30 ether);
        s.bystander = 7 ether;
        (Obs memory o, uint256 pool, uint256[] memory b) = _dead(s);
        _assertDead(s, o, pool, b);
        assertEq(o.refunds, 30 ether, "the whole budget is refunded, first deities first");
        uint256[] memory a = _ledgers(3);
        assertEq(a[0] - b[0], 20 ether);
        assertEq(a[1] - b[1], 10 ether);
        assertEq(a[2] - b[2], 0);
        assertEq(o.drainedEvents, 0, "nothing is left for the terminal pot");
        assertEq(game.claimableWinningsOf(address(0xB157)), 7 ether + 1, "the earned claim stays reserved (plus the registration sentinel)");
    }

    function test_ZeroDistributable_NoRefundNoPot() public {
        Spec memory s = _deadSpec(3, _prices(10, 5), 0);
        s.bystander = 9 ether;
        (Obs memory o, uint256 pool, uint256[] memory b) = _dead(s);
        _assertDead(s, o, pool, b);
        assertEq(o.refunds, 0);
        assertEq(o.refundEvents, 0);
        assertEq(game.claimablePoolView(), pool);
    }

    /// @dev Released Degenesis balances join the ticket prizes after the refund budget is fixed.
    function test_DegenesisRelease_JoinsPrizesNotRefundBudget() public {
        uint96[] memory p = new uint96[](2);
        p[0] = 20 ether;
        p[1] = 20 ether;
        Spec memory s = _deadSpec(6, p, 15 ether);
        s.vault = 40 ether;
        s.sdgnrs = 10 ether;
        (Obs memory o, uint256 pool, uint256[] memory b) = _dead(s);
        _assertDead(s, o, pool, b);
        assertEq(o.refunds, 15 ether, "refund budget excludes the 50 ETH released");
        assertEq(o.released, 50 ether);
        assertEq(o.available, 15 ether + 50 ether - 15 ether, "released funds are prizes");
        assertEq(o.pot, 50 ether);
    }

    /// forge-config: default.fuzz.runs = 48
    function testFuzz_DeadEnding_RefundsMatchModelAndConserve(
        uint24 lvlSeed, uint8 n, uint256 seed, uint256 slack, uint128 vault, uint128 sd, uint256 bystander
    ) public {
        Spec memory s = _deadSpec(uint24(bound(lvlSeed, 0, 14)), _prices(bound(n, 0, 30), seed), bound(slack, 0, 800 ether));
        if (seed % 4 == 0) s.slack = bound(slack, 0, 45 ether); // budget tighter than the refunds
        s.vault = uint128(bound(vault, 0, 100 ether));
        s.sdgnrs = uint128(bound(sd, 0, 100 ether));
        s.bystander = bound(bystander, 0, 100 ether);
        (Obs memory o, uint256 pool, uint256[] memory b) = _dead(s);
        _assertDead(s, o, pool, b);
    }

    // ---------------------------------------------------------------- stall deadlines

    uint256 private constant FOURTEEN = 14 days;

    /// @dev No completed day for exactly 14 days: the ending is the deterministic one, even with VRF answering.
    function test_NoCompletionFor14Days_StallRefunds() public {
        Spec memory s = _deadSpec(5, _prices(12, 6), 1000 ether);
        _seeder().seedIdle(WORD, 5, 5, FOURTEEN - 1);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(12);
        assertFalse(game.livenessTriggered(), "one second short: the deadline alone does nothing");
        Obs memory o;
        _mine(o, 10_000_000);
        assertFalse(game.gameOver(), "one second short: no ending");
        assertEq(o.refundEvents, 0, "one second short: no refund");
        assertEq(o.fixedEvents, 0);
        vm.warp(block.timestamp + 1);
        assertTrue(game.livenessTriggered(), "exactly 14 days");
        for (uint256 i; i < 60 && !_terminalPaid(); ++i) {
            _fulfil();
            _mine(o, 10_000_000);
        }
        assertTrue(_terminalPaid());
        assertEq(o.fixedEvents, 1, "the deterministic ending: a fixed pot, no draw");
        assertEq(o.awarded, 0);
        _assertDead(s, o, pool, b);
        assertGt(o.refunds, 0);
    }

    /// @dev An unpublished request reaching its 14-day deadline is the same stall.
    function test_RequestUnanswered14Days_StallRefunds() public {
        Spec memory s = _deadSpec(8, _prices(12, 7), 1000 ether);
        _seeder().seedRequestStall(8, FOURTEEN - 1);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(12);
        assertFalse(game.livenessTriggered(), "one second short: the request deadline alone does nothing");
        Obs memory o;
        _mine(o, 10_000_000);
        assertFalse(game.gameOver());
        assertEq(o.refundEvents, 0);
        vm.warp(block.timestamp + 1);
        assertTrue(game.livenessTriggered(), "request unanswered for exactly 14 days");
        _runDead(o);
        _assertDead(s, o, pool, b);
        assertGt(o.refunds, 0);
    }

    // ---------------------------------------------------------------- normal ending that stalls

    /// @dev The terminal request goes unanswered: the stall takes the ending over before setup commits.
    function test_NormalTerminalRequestLaterStalls_RefundsBecomeEligible() public {
        Spec memory s = _deadSpec(4, _prices(12, 8), 2000 ether);
        s.vault = 2 ether;
        _seeder().seedIdle(WORD, 4, 30, 1 days);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(12);
        Obs memory o;
        _startNormal(o); // the ending's own terminal request is out and unanswered
        assertFalse(game.gameOver());
        assertEq(o.refundEvents, 0, "no refund while the ending is the normal one");
        vm.warp(block.timestamp + FOURTEEN);
        for (uint256 i; i < 60 && !_terminalPaid(); ++i) _mine(o, 10_000_000);
        assertTrue(_terminalPaid());
        assertEq(o.fixedEvents, 1, "the stall ended it deterministically");
        assertEq(o.awarded, 0, "no terminal draw ran");
        _assertDead(s, o, pool, b);
        assertGt(o.refunds, 0);
    }

    /// @dev The terminal word is recorded, then the daily deadman fires before the payout commits.
    function test_NormalTerminalWordApplied_ThenStall_RefundsBecomeEligible() public {
        Spec memory s = _deadSpec(4, _prices(12, 9), 2000 ether);
        _seeder().seedIdle(WORD, 4, 30, 1 days);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(12);
        Obs memory o;
        _startNormal(o);
        _fulfil();
        _mine(o, GAS); // applies the terminal word
        assertFalse(game.gameOver(), "word applied; payout not yet committed");
        assertEq(o.refundEvents, 0);
        vm.warp(block.timestamp + FOURTEEN);
        for (uint256 i; i < 60 && !_terminalPaid(); ++i) _mine(o, 10_000_000);
        assertTrue(_terminalPaid());
        assertEq(o.fixedEvents, 1);
        _assertDead(s, o, pool, b);
        assertGt(o.refunds, 0);
    }

    /// @dev Level 10 and above stay refund-free on the switched ending too.
    function test_NormalThenStall_AtLevel10_NoRefund() public {
        Spec memory s = _deadSpec(10, _prices(12, 10), 2000 ether);
        _seeder().seedIdle(WORD, 10, 30, 1 days);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(12);
        Obs memory o;
        _startNormal(o);
        vm.warp(block.timestamp + FOURTEEN);
        for (uint256 i; i < 60 && !_terminalPaid(); ++i) _mine(o, 10_000_000);
        _assertDead(s, o, pool, b);
        assertEq(o.refundEvents, 0);
    }

    // ---------------------------------------------------------------- repeats, allowances, delays

    /// @dev Small allowances split the deterministic ending over many calls; the refund is credited once.
    function test_LimitedAllowances_RefundsOnce_RepeatedCallsNeverRefundAgain() public {
        Spec memory s = _deadSpec(5, _prices(30, 11), 3000 ether);
        s.vault = 2 ether;
        _seeder().seedRequestStall(5, 15 days);
        _restore();
        uint256 pool = _fund(s);
        uint256[] memory b = _ledgers(30);
        Obs memory o;
        for (uint256 i; i < 120 && !_terminalPaid(); ++i) _mine(o, 3_000_000);
        assertTrue(_terminalPaid(), "finished under limited allowances");
        assertEq(o.refundEvents, 1, "one aggregate refund event across every checkpoint");
        _assertDead(s, o, pool, b);
        uint256 poolDone = game.claimablePoolView();
        // Repeated calls, and the final sweep window, never refund again.
        for (uint256 i; i < 5; ++i) _mine(o, 3_000_000);
        uint256[] memory a = _ledgers(30);
        (, uint256[] memory each) = _expected(s.prices, s.slack);
        for (uint256 i; i < 30; ++i) assertEq(a[i] - b[i], each[i], "ledgers hold a single refund");
        vm.warp(block.timestamp + 45 days);
        for (uint256 i; i < 8; ++i) _mine(o, 10_000_000);
        assertEq(o.refundEvents, 1, "no second refund");
        assertEq(o.refunds, _expectedTotal(s), "the refund total is unchanged");
        assertLe(game.claimablePoolView(), poolDone, "later work never adds a refund reservation");
    }

    function _expectedTotal(Spec memory s) internal pure returns (uint256 t) {
        (t,) = _expected(s.prices, s.slack);
    }

    /// @dev The normal payout starts (gameOver set) and processing is then delayed past the
    ///      stall deadline: the later calls resume the payout and never refund.
    function test_NormalPayoutStarted_ThenDelayed_NoRetroactiveRefund() public {
        Spec memory s = _deadSpec(5, _prices(30, 12), 5000 ether);
        _seeder().seedIdle(WORD, 5, 30, 1 days);
        _restore();
        uint256 pool = _fund(s);
        Obs memory o;
        _startNormal(o);
        _fulfil();
        _mine(o, GAS); // applies the terminal word
        // Admit the setup but not the whole payout.
        uint256 g = 2_800_000;
        for (uint256 i; i < 40 && !game.gameOver(); ++i) _mine(o, g);
        assertTrue(game.gameOver(), "setup committed");
        assertFalse(_terminalPaid(), "payout not finished: processing is now delayed");
        assertEq(o.refundEvents, 0);
        vm.warp(block.timestamp + 20 days);
        assertTrue(game.livenessTriggered());
        for (uint256 i; i < 80 && !_terminalPaid(); ++i) _mine(o, GAS);
        assertTrue(_terminalPaid());
        assertEq(o.refundEvents, 0, "no retroactive refund after gameOver is set");
        assertEq(o.fixedEvents, 0, "the normal payout stays a draw");
        assertEq(o.poolAtDrain, pool, "claimablePool at the drain carries no refund credit");
        assertApproxEqAbs(o.awarded, o.available, 400);
    }
}

/// @notice The refund rule on the real purchase path: the price paid is recorded by
///         `purchaseDeityPass` and the endings are reached by real days and a real unanswered request.
contract DeityRefundRealFlowTest is DegenesisFixture {
    bytes32 internal constant REFUNDS_SIG_ = keccak256("DeityPassRefundsSettled(uint256)");
    bytes32 internal constant DRAINED_SIG_ = keccak256("GameOverDrained(uint24,uint256,uint256)");

    address internal deity;
    uint32 internal deityId;

    function setUp() public override {
        super.setUp();
        _driveDay(2);
        deity = _player("deity", 200 ether);
        vm.prank(deity);
        game.purchaseDeityPass{value: 60 ether}(0, 7, bytes32(0));
        deityId = game.walletIdOf_g3120(deity);
    }

    function _recordedPrice() internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(deityId), GameSlots.DEITY_PASS_PRICE_PAID))));
    }

    struct Run {
        uint256 refunds;
        uint256 refundEvents;
        uint256 drainedPool;
        uint256 released;
        uint256 poolBefore;
    }

    function _paid() internal view returns (bool) {
        return uint8(_slot(GameSlots.GAME_OVER_STATE_PACKED) >> 48) != 0;
    }

    function _end(bool answer) internal returns (Run memory r) {
        r.poolBefore = _claimablePool();
        for (uint256 i; i < 400 && !(game.gameOver() && _paid()); ++i) {
            if (answer) _fulfillPending();
            vm.recordLogs();
            _tryMine();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
                bytes32 t = logs[j].topics[0];
                if (t == REFUNDS_SIG_) {
                    ++r.refundEvents;
                    r.refunds += abi.decode(logs[j].data, (uint256));
                } else if (t == DRAINED_SIG_) {
                    (,, r.drainedPool) = abi.decode(logs[j].data, (uint24, uint256, uint256));
                } else if (t == RELEASED_SIG) {
                    (uint256 v, uint256 s) = abi.decode(logs[j].data, (uint256, uint256));
                    r.released += v + s;
                }
            }
        }
        assertTrue(game.gameOver() && _paid(), "ending finished");
    }

    /// @dev A real above-cap purchase refunds 20 ETH when the request stalls for 14 days.
    function test_RealPurchase_StalledRequest_RefundsCap() public {
        uint256 price = _recordedPrice();
        assertGe(price, 24 ether, "the recorded price is the real purchase price");
        _warpDay(4, 1 hours);
        _drain(false, 400);
        assertTrue(game.rngLocked(), "day 4's request is out");
        uint256 sentAt = block.timestamp;
        uint256 before_ = game.claimableWinningsOf(deity);
        vm.warp(sentAt + 14 days + 1);
        assertTrue(game.livenessTriggered(), "14 days without completion");
        Run memory r = _end(false);
        uint256 expectedRefund = price > 20 ether ? 20 ether : price;
        assertEq(r.refunds, expectedRefund, "the recorded price, capped at 20 ETH");
        assertEq(r.refundEvents, 1);
        assertEq(game.claimableWinningsOf(deity) - before_, expectedRefund, "credited to the deity's ledger");
        assertEq(r.drainedPool, r.poolBefore - r.released + expectedRefund, "claimablePool at the drain");
    }

    /// @dev The same buyer on the purchase-timeout ending (VRF alive, the game simply stops) gets nothing back.
    function test_RealPurchase_PurchaseTimeout_NoRefund() public {
        uint256 before_ = game.claimableWinningsOf(deity);
        uint256 day = 3;
        for (; day <= 40; ++day) {
            _warpDay(day, 1 hours);
            if (game.livenessTriggered()) break;
            _drain();
        }
        assertTrue(game.livenessTriggered(), "the purchase deadline fired");
        assertFalse(game.gameOver(), "the ending has not started yet");
        assertEq(game.currentLvl(), 0, "still level 0: refund-eligible by level");
        assertFalse(_vrfStalled(), "VRF alive: this is the purchase timeout");
        Run memory r = _end(true);
        assertEq(r.refundEvents, 0, "a normal ending refunds nothing");
        assertEq(r.refunds, 0);
        assertEq(r.drainedPool, r.poolBefore - r.released, "claimablePool carries no refund credit");
        // The deity can still win terminal ticket prizes; it is never credited a refund.
        assertGe(game.claimableWinningsOf(deity), before_, "the deity ledger never falls");
    }

    function _vrfStalled() internal view returns (bool) {
        return block.timestamp >= uint256((_slot(GameSlots.LAST_DAILY_COMPLETED_AT) >> 128) & type(uint48).max) + 14 days;
    }
}

/// @dev The module harness of the missing-word fallback, with paid deities seeded.
contract DeityRefundWordHarness is MissingWordDrainHarness {
    function seedDeities(uint96[] calldata prices) external {
        for (uint256 i; i < prices.length; ++i) {
            uint32 id = _seedDeity(address(uint160(0xD3170000 + i)));
            deityPassPricePaid[id] = prices[i];
        }
    }

    function refundOf(uint256 i) external view returns (uint256) {
        return _claimableOf(_walletIdOf(address(uint160(0xD3170000 + i))));
    }
}

/// @notice Missing-word fallback. The normal ending's drain with funds and no terminal word latches
///         the deterministic ending and returns before any refund side effect; the next setup
///         refunds eligible paid deities. The state is the repository's module-harness state
///         (no chain path produces it), not a production-path state.
contract DeityRefundMissingWordTest is DeployProtocol {
    bytes32 internal constant REFUNDS_SIG = keccak256("DeityPassRefundsSettled(uint256)");

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 500 days);
    }

    function _run(uint24 lvl) internal returns (uint256 firstRefunds, uint256 laterRefunds, uint256 laterEvents, uint256 ledgerSum) {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 100 days);
        vm.etch(ContractAddresses.GAME, type(DeityRefundWordHarness).runtimeCode);
        DeityRefundWordHarness h = DeityRefundWordHarness(ContractAddresses.GAME);
        vm.etch(ContractAddresses.GNRUS, type(TerminalSinkStub).runtimeCode);
        vm.etch(ContractAddresses.SDGNRS, type(TerminalSinkStub).runtimeCode);
        vm.etch(ContractAddresses.COIN, type(TerminalSinkStub).runtimeCode);
        vm.mockCall(ContractAddresses.STETH_TOKEN, abi.encodeWithSignature("balanceOf(address)", address(h)), abi.encode(uint256(0)));
        uint24 day = h.seed(lvl);
        uint96[] memory prices = new uint96[](4);
        prices[0] = 12 ether;
        prices[1] = 25 ether;
        prices[2] = 0;
        prices[3] = 20 ether;
        h.seedDeities(prices);
        vm.deal(address(h), 1000 ether);
        uint256[4] memory base;
        for (uint256 i; i < 4; ++i) base[i] = h.refundOf(i);

        vm.recordLogs();
        h.runGameOverAdvance(day, lvl, gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == REFUNDS_SIG) firstRefunds += abi.decode(logs[i].data, (uint256));
        }
        (bool ended, uint256 dead,,,,) = h.endingState();
        assertFalse(ended, "first call: latch only");
        assertEq(dead, 1, "deterministic ending latched");
        for (uint256 i; i < 4; ++i) assertEq(h.refundOf(i), base[i], "no credit from the latching call");

        vm.recordLogs();
        for (uint256 i; i < 8; ++i) h.runGameOverAdvance{gas: 10_000_000}(day, lvl, 6_700_000);
        logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == REFUNDS_SIG) {
                laterRefunds += abi.decode(logs[i].data, (uint256));
                ++laterEvents;
            }
        }
        (ended,,,,,) = h.endingState();
        assertTrue(ended);
        for (uint256 i; i < 4; ++i) ledgerSum += h.refundOf(i) - base[i];
    }

    function test_MissingWord_Level0_LatchesThenRefunds() public {
        (uint256 first, uint256 later, uint256 events, uint256 ledgers) = _run(0);
        assertEq(first, 0, "the latching call refunds nothing");
        assertEq(later, 12 ether + 20 ether + 0 + 20 ether, "later setup refunds paid deities, capped");
        assertEq(events, 1);
        assertEq(ledgers, later);
    }

    function test_MissingWord_Level9_LatchesThenRefunds() public {
        (uint256 first, uint256 later,, uint256 ledgers) = _run(9);
        assertEq(first, 0);
        assertEq(later, 52 ether);
        assertEq(ledgers, 52 ether);
    }

    function test_MissingWord_Level10_NeverRefunds() public {
        (uint256 first, uint256 later, uint256 events, uint256 ledgers) = _run(10);
        assertEq(first, 0);
        assertEq(later, 0);
        assertEq(events, 0);
        assertEq(ledgers, 0);
    }
}
