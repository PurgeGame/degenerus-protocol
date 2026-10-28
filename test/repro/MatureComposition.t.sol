// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MultiLevelHandler} from "../fuzz/handlers/MultiLevelHandler.sol";
import {SolvencyObligations} from "../fuzz/helpers/SolvencyObligations.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameFunding} from "../helpers/GameFunding.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Composes mature-level loans, pass collateral, live and terminal redemption and real
///         day/level transitions. Every seed must reach all witnesses; an ignored revert or a
///         level-0 walk cannot pass. The level-10 opening is setup, never counted as fuzz progress.
/// @dev VRF and stETH are the standard mocks. Initial holder allocation and a backed sDGNRS
///      claimable credit are fixture setup. No test write changes a level, deadline, loan,
///      redemption reserve, account owner or terminal flag. Measured calls use production code.
contract MatureCompositionTest is DeployProtocol {
    address private constant REPAYER = address(0xC011A);
    address private constant DEFAULTER = address(0xC011B);
    address private constant HOLDER = address(0xC011C);
    address private constant DRIVER = address(0xC011D);
    uint256 private constant PRINCIPAL = 0.05 ether;
    uint256 private constant MINE_GAS = 15_000_000;
    bytes32 private constant REPAID = keccak256("LoanRepaid(uint32,address,uint256)");
    bytes32 private constant SEIZED = keccak256("LoanSeized(uint32,uint32)");

    DegenerusGameLens private lens;
    uint24 private openingLevel;
    uint24 private due;
    uint32[2] private borrowers;
    uint32[2] private lenders;
    uint256[2] private repaid;
    uint256[2] private seized;
    uint256 private seed;
    uint256 private miningCalls;
    uint256 private vrfAnswers;
    uint256 private postOpeningTransitions;
    uint256 private reserveObservations;
    uint256 private liveBatch;
    uint256 private liveTokens;
    uint256 private lastLevel;
    uint256 private liveMaximumReserve;
    uint256 private liveBase;
    uint256 private closeWitnesses;
    uint256 private repaymentLedgerWitnesses;
    uint256 private seizureLedgerWitnesses;
    uint256 private liveClaims;
    uint256 private liveCreditWitnesses;
    uint256 private lastWord;
    uint24 private terminalTicketLevel;
    uint256 private terminalPot;
    uint256 private terminalWeight;

    struct LoanSnapshot {
        uint256 repayer;
        uint256 defaulter;
        uint256 lender;
        uint256 pool;
        uint256 backing;
        uint256 paidCount;
        uint256 seizedCount;
    }

    struct StepSnapshot {
        LoanSnapshot loan;
        uint8 action;
        bool pricing;
        uint256 expectedBase;
        uint256 expectedReserve;
        uint256 holderClaimable;
        bool liveUnpaid;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        MultiLevelHandler opening = new MultiLevelHandler(game, mockVRF, 1);
        opening.scriptedOpening();
        assertGe(game.currentLvl(), 10, "real mature opening");
        _drain(true);
        openingLevel = game.currentLvl();
        lastLevel = openingLevel;
        miningCalls = 0;
        vrfAnswers = 0;
        postOpeningTransitions = 0;
        reserveObservations = 0;
        lens = new DegenerusGameLens();
        vm.deal(REPAYER, 100 ether);
        vm.deal(DEFAULTER, 100 ether);
        vm.deal(HOLDER, 100 ether);
        vm.deal(DRIVER, 100_000 ether);
        _giveWalletId(HOLDER);
        // Real native funding keeps request-boundary pricing independent of a VRF refill
        // and permits an independently priced subscription refund at the final sweep.
        vm.deal(address(this), 100 ether);
        mockVRF.fundSubscriptionWithNative{value: 100 ether}(1);
        GameFunding.credit(2, 100 ether);
        uint256 allocation = sdgnrs.totalSupply() / 100;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, HOLDER, allocation), allocation);
        _solvent();
    }

    /// forge-config: default.fuzz.runs = 64
    /// forge-config: deep.fuzz.runs = 256
    function testFuzz_matureLoansRedemptionsAndTerminalConserve(uint256 entropy) public {
        seed = entropy;
        due = openingLevel + 2;
        // Both actor orderings are explored, but both repayment and seizure are mandatory.
        if (entropy & 1 == 0) {
            _passAndBorrow(REPAYER, 0);
            _passAndBorrow(DEFAULTER, 1);
        } else {
            _passAndBorrow(DEFAULTER, 1);
            _passAndBorrow(REPAYER, 0);
        }
        vm.prank(REPAYER);
        game.depositAfkingFunding{value: _fullTerm()}(borrowers[0]);
        _submitLiveRedemption();

        // Purchase quantities, cash amounts and VRF words vary after the opening. The
        // campaign cannot pass unless the real engine crosses two additional level boundaries.
        for (uint256 day; day < 60 && (game.currentLvl() < due || _anyLoan()); ++day) {
            assertFalse(game.gameOver(), "healthy funded progression ended early");
            _emptyDefaulter();
            (, , , bool locked, uint256 price) = game.purchaseInfo_g1027();
            assertFalse(locked, "prior session drained");
            uint256 box = (60 + uint256(keccak256(abi.encode(entropy, day))) % 61) * 1 ether;
            uint256 qty = 400 * (1 + (entropy >> (day % 32)) % 10);
            uint256 cost = price * qty / 400 + box;
            vm.prank(DRIVER);
            game.purchaseOrderFor{value: cost}(0, qty, BoxOrderLib.boCustomFloor(box), bytes32(0),
                MintPaymentKind.DirectEth, false);
            _solvent();
            vm.warp(vm.getBlockTimestamp() + 1 days + 1);
            _drain(true);
        }
        assertGe(game.currentLvl(), due, "randomized walk must advance beyond opening");
        assertGe(postOpeningTransitions, 2, "two observed post-opening transitions");
        assertGt(miningCalls, 0, "actual mining");
        assertGt(vrfAnswers, 0, "actual fulfillment");
        assertGt(reserveObservations, 0, "redemption reserve existed during composition");
        assertEq(repaid[0], 1, "funded loan repaid once");
        assertEq(seized[0], 0, "funded loan not seized");
        assertEq(repaid[1], 0, "unfunded loan not repaid");
        assertEq(seized[1], 1, "unfunded loan seized once");
        assertFalse(_anyLoan(), "both due loans retired");
        (, address owner0,) = game.resolveAccount_g7029(borrowers[0], address(0));
        (, address owner1,) = game.resolveAccount_g7029(borrowers[1], address(0));
        assertEq(owner0, REPAYER, "repaid ownership retained");
        assertEq(owner1, address(sdgnrs), "defaulted ownership transferred to lender");
        assertEq(game.acquiredBuyer(borrowers[1]), lenders[1], "acquisition names correct lender");
        vm.prank(DEFAULTER);
        vm.expectRevert();
        game.setOperatorApproval(borrowers[1], DEFAULTER, true);
        (uint128 pending,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(HOLDER), uint32(liveBatch));
        assertEq(pending, 0, "live redemption retired");
        assertGt(liveTokens, 0, "nonzero live redemption");
        assertEq(liveClaims, 1, "live claim paid exactly once");
        assertEq(liveCreditWitnesses, 1, "actual live direct credit reconciled");
        assertEq(closeWitnesses, 1, "independent live close pricing observed");
        assertEq(repaymentLedgerWitnesses, 1, "repayment debit and credit observed");
        assertEq(seizureLedgerWitnesses, 1, "seizure ledger observed");
        _solvent();
        _terminalRedemptionAndSweep();
    }

    /// @notice Fixed regression for an expensive live ticket-drain scenario. End at the
    ///         required loan checkpoint and settle the remaining paid ticket cohort.
    function test_matureQueuedWorkTerminal_21090() public {
        testFuzz_matureLoansRedemptionsAndTerminalConserve(21090);
    }

    function _passAndBorrow(address player, uint256 index) private {
        vm.prank(player);
        game.purchaseWhalePass{value: 4 ether}(0, 1, bytes32(0));
        uint32 id = game.walletIdOf_g3120(player);
        assertGt(id, 2, "pass allocated real player");
        borrowers[index] = id;
        DegenerusGameLens.LoanQuote memory quote = lens.previewBorrow(address(game), id, due, PRINCIPAL);
        assertTrue(quote.eligible, "real pass collateral admits loan");
        assertEq(quote.principal, PRINCIPAL, "requested principal");
        uint256 cash = _cash(player);
        uint256 lenderFunds = _cashLedger(address(sdgnrs));
        vm.prank(player);
        game.borrow(id, due, PRINCIPAL, PRINCIPAL - quote.ticketWei);
        assertEq(_cash(player) - cash, PRINCIPAL - quote.ticketWei, "loan pays cash once");
        assertEq(lenderFunds - _cashLedger(address(sdgnrs)), PRINCIPAL, "loan debits lender once");
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
        assertEq(info.principal, PRINCIPAL, "loan record principal");
        assertEq(info.startLevel, openingLevel, "loan begins at mature level");
        assertEq(info.dueLevel, due, "due level");
        assertEq(info.lenderId, 2, "sDGNRS lender");
        lenders[index] = info.lenderId;
        _solvent();
    }

    function _submitLiveRedemption() private {
        (uint32 batch,,, uint256 escrow) = sdgnrs.redemptionBatchState();
        liveBatch = batch;
        uint256 amount = sdgnrs.balanceOf(HOLDER) / 4;
        uint256 supply = sdgnrs.totalSupply();
        uint256 tokens = sdgnrs.balanceOf(HOLDER);
        vm.prank(HOLDER);
        sdgnrs.burn(amount);
        (,,, uint256 afterEscrow) = sdgnrs.redemptionBatchState();
        assertEq(supply - sdgnrs.totalSupply(), amount, "burn removed from supply");
        assertEq(tokens - sdgnrs.balanceOf(HOLDER), amount, "burn removed from holder");
        assertEq(afterEscrow - escrow, amount, "burn kept in holder base escrow");
        liveTokens = amount;
    }

    function _drain(bool answer) private {
        for (uint256 i; i < 500; ++i) {
            if (answer) _fulfill();
            uint8 action = game.nextMinerAction();
            if (action == 0) return;
            assertTrue(action != 2, "unexpected unanswered request");
            if (due != 0 && game.currentLvl() >= due && _open(borrowers[1])) _emptyDefaulter();
            _mineOne(action);
            // Stop at the required mature checkpoint. Unrelated ticket work can be huge;
            // the ending below must settle that outstanding cohort through production code.
            if (answer && due != 0 && game.currentLvl() >= due && !_anyLoan() && liveClaims == 1) return;
        }
        fail("engine failed to drain within bounded calls");
    }

    function _mineOne(uint8 action) private {
        // The public calibration argument can stop after the mandatory first unit.
        // Isolate due-loan settlement from unrelated jackpot/afking credits, and the
        // first batch close from preceding engine work, without writing game state.
        StepSnapshot memory s;
        s.action = action;
        s.pricing = liveBatch != 0 && closeWitnesses == 0;
        s.liveUnpaid = liveBatch != 0 && liveClaims == 0;
        if (s.liveUnpaid) s.holderClaimable = game.claimableWinningsOf(HOLDER);
        if (action == 19) s.loan = _loanSnapshot();
        if (s.pricing && (action == 16 || action == 17)) {
            (s.expectedBase, s.expectedReserve) = _liveCloseQuote();
        }
        vm.recordLogs();
        vm.prank(DRIVER);
        game.mineRun{gas: MINE_GAS}(action == 19 || s.pricing ? type(uint32).max : 0);
        ++miningCalls;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _observe(logs);
        if (s.liveUnpaid && liveClaims == 1) _checkLiveHolderCredit(logs, s.holderClaimable);
        if (action == 19) _checkLoanLedger(s.loan);
        _checkClose(s);
        _solvent();
    }

    function _checkLiveHolderCredit(Vm.Log[] memory logs, uint256 before) private {
        uint256 total = liveBase * (21 + uint256(keccak256(abi.encode(uint256(84), lastWord))) % 155) / 100;
        if (total > liveMaximumReserve) total = liveMaximumReserve;
        uint256 boxIncome;
        uint32 holderId = game.walletIdOf_g3120(HOLDER);
        // This holder has no purchased tickets, subscription or placed bets before this
        // claim. Its only additional ETH income in this call can come from the redemption
        // lootbox's synthetic ETH spin. BoxSpin reports the priced reward independently of
        // PlayerCredited; folding that reward prevents it masking an omitted direct credit.
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1
                && logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)")
                && uint32(uint256(logs[i].topics[1])) == holderId) {
                (,,, uint256 ethShare) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                boxIncome += ethShare;
            }
        }
        assertEq(game.claimableWinningsOf(HOLDER), before + total / 2 + boxIncome,
            "exact live direct credit plus separately priced box income");
        ++liveCreditWitnesses;
    }

    function _checkClose(StepSnapshot memory s) private {
        if (!s.pricing || (s.action != 16 && s.action != 17)) return;
        (, uint96 payout, uint96 base,,,) = sdgnrs.redemptionBatches(uint32(liveBatch));
        assertGt(s.expectedBase, 0, "priced nonempty live batch");
        assertEq(base, s.expectedBase, "independent close price");
        assertEq(payout, s.expectedReserve, "independent close maximum");
        assertEq(game.redemptionReserve(), s.expectedReserve, "priced value moved into reserve");
        liveBase = s.expectedBase;
        liveMaximumReserve = s.expectedReserve;
        ++closeWitnesses;
    }

    function _fulfill() private {
        uint256 request = mockVRF.lastRequestId();
        if (request == 0) return;
        (,, bool done) = mockVRF.pendingRequests(request);
        if (!done) {
            lastWord = uint256(keccak256(abi.encode(seed, request))) | 2;
            mockVRF.fulfillRandomWords(request, lastWord);
            ++vrfAnswers;
        }
    }

    function _observe(Vm.Log[] memory logs) private {
        uint256 level = game.currentLvl();
        assertGe(level, lastLevel, "level monotonic");
        if (level > lastLevel) postOpeningTransitions += level - lastLevel;
        lastLevel = level;
        if (game.redemptionReserve() != 0) ++reserveObservations;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs) && logs[i].topics.length >= 3
                && logs[i].topics[0] == keccak256("RedemptionClaimed(uint32,uint32,uint16,uint256,uint256,uint256)")
                && uint32(uint256(logs[i].topics[1])) == game.walletIdOf_g3120(HOLDER)
                && uint32(uint256(logs[i].topics[2])) == liveBatch) {
                (uint16 roll, uint256 direct, uint256 box,) = abi.decode(logs[i].data, (uint16,uint256,uint256,uint256));
                (uint80 tokens,,,,,) = sdgnrs.redemptionBatches(uint32(liveBatch));
                assertEq(tokens, liveTokens, "only modeled tokens in live batch");
                assertEq(roll, 21 + uint256(keccak256(abi.encode(uint256(84), lastWord))) % 155, "tagged redemption roll");
                uint256 total = liveBase * roll / 100;
                if (total > liveMaximumReserve) total = liveMaximumReserve;
                assertGt(liveMaximumReserve, 0, "close reserve observed before resolution");
                assertEq(direct, total / 2, "live direct half");
                assertEq(box, total - direct, "live lootbox half (fixture above dust floor)");
                ++liveClaims;
            }
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] == keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)")) {
                assertEq(terminalPot, 0, "terminal payout priced once");
                terminalTicketLevel = uint24(uint256(logs[i].topics[1]));
                (uint256 pot, uint256 created, uint256 uncreated,) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                terminalPot = pot;
                terminalWeight = created * 100 + uncreated;
            }
            for (uint256 j; j < 2; ++j) {
                if (borrowers[j] == 0 || uint32(uint256(logs[i].topics[1])) != borrowers[j]) continue;
                if (logs[i].topics[0] == REPAID) {
                    ++repaid[j];
                    assertEq(abi.decode(logs[i].data, (uint256)), _fullTerm(), "independent full-term repayment");
                } else if (logs[i].topics[0] == SEIZED) ++seized[j];
                assertLe(repaid[j] + seized[j], 1, "exactly-once loan closure");
            }
        }
    }

    function _liveCloseQuote() private view returns (uint256 base, uint256 maximum) {
        (,,, uint256 escrow) = sdgnrs.redemptionBatchState();
        uint256 stored = game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve();
        uint256 money = stored > 1 ? stored - 1 : 0;
        if (money > type(uint96).max) money = type(uint96).max;
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        money = money > reserved ? money - reserved : 0;
        base = money * liveTokens / (sdgnrs.totalSupply() + escrow) / 1e9 * 1e9;
        maximum = base * 175 / 100;
        if (maximum > money) maximum = money;
    }

    function _loanSnapshot() private view returns (LoanSnapshot memory s) {
        s.repayer = _idLedger(borrowers[0]);
        s.defaulter = _idLedger(borrowers[1]);
        s.lender = _idLedger(2);
        s.pool = game.claimablePoolView();
        s.backing = _cash(address(game));
        s.paidCount = repaid[0];
        s.seizedCount = seized[1];
    }

    function _checkLoanLedger(LoanSnapshot memory before) private {
        uint256 paid = repaid[0] - before.paidCount;
        uint256 taken = seized[1] - before.seizedCount;
        assertEq(paid + taken, 1, "exactly one isolated due loan settled");
        uint256 owed = paid * _fullTerm();
        assertEq(_idLedger(borrowers[0]), before.repayer - owed, "exact repayment debit");
        assertEq(_idLedger(2), before.lender + owed, "exact repayment lender credit");
        assertEq(_idLedger(borrowers[1]), before.defaulter, "seizure preserves depleted ledger");
        assertEq(game.claimablePoolView(), before.pool, "loan settlement preserves aggregate liability");
        assertEq(_cash(address(game)), before.backing, "loan settlement preserves game backing");
        repaymentLedgerWitnesses += paid;
        seizureLedgerWitnesses += taken;
    }

    function _emptyDefaulter() private {
        if (borrowers[1] == 0 || !_open(borrowers[1])) return;
        uint256 claim = game.claimableWinningsOf(DEFAULTER);
        if (claim > 1) {
            vm.prank(DEFAULTER);
            game.claimClaimable(borrowers[1]);
        }
        uint256 prepaid = game.afkingFundingOf(DEFAULTER);
        if (prepaid != 0) {
            vm.prank(DEFAULTER);
            game.withdrawAfkingFunding(borrowers[1], prepaid);
        }
    }

    function _terminalRedemptionAndSweep() private {
        assertTrue(game.nextMinerAction() != 0, "terminal composition starts with unfinished live work");
        (uint32 batch,,,) = sdgnrs.redemptionBatchState();
        uint256 amount = sdgnrs.balanceOf(HOLDER) / 3;
        assertGt(amount, 0, "remaining holder balance");
        vm.prank(HOLDER);
        sdgnrs.burn(amount);
        vm.warp(vm.getBlockTimestamp() + 14 days + 1);
        _drain(false);
        assertTrue(game.gameOver(), "real dead-VRF terminal path");
        _claimQueuedEndingShare();
        (uint32 open,,, uint256 escrow) = sdgnrs.redemptionBatchState();
        assertEq(open, batch, "terminal does not close an open batch");
        uint256 stored = game.claimableWinningsOf(address(sdgnrs));
        uint256 backing = _cash(address(sdgnrs)) + (stored > 1 ? stored - 1 : 0)
            + game.redemptionReserve();
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        uint256 available = backing > reserved ? backing - reserved : 0;
        uint256 expected = available * amount / (sdgnrs.totalSupply() + escrow);
        uint256 before = _cash(HOLDER);
        uint32 holderId = game.walletIdOf_g3120(HOLDER);
        vm.prank(HOLDER);
        sdgnrs.claimRedemption(holderId, batch);
        assertEq(_cash(HOLDER) - before, expected, "terminal unwind pays independent pro-rata value");
        (uint128 pending,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(HOLDER), batch);
        assertEq(pending, 0, "terminal claim retired");
        vm.prank(HOLDER);
        vm.expectRevert();
        sdgnrs.claimRedemption(holderId, batch);
        _solvent();
        _assertFinalSweep();
        assertEq(repaid[0], 1, "repayment never repeated at ending");
        assertEq(seized[1], 1, "seizure never repeated at ending");
    }

    /// @dev The global pot/tally are the fixed terminal quote; this independently prices
    ///      a raw retained queue holding and verifies its owner credit, withdrawal and
    ///      one-time retirement. It does not claim to independently reconstruct every trait.
    function _claimQueuedEndingShare() private {
        assertGt(terminalPot, 0, "deterministic terminal pot fixed");
        assertGt(terminalWeight, 0, "terminal cohort retained");
        uint32 driverId = game.walletIdOf_g3120(DRIVER);
        uint24 key;
        uint256 weight;
        for (uint256 domain; domain < 3 && weight == 0; ++domain) {
            key = terminalTicketLevel | (domain == 0 ? uint24(0) : domain == 1 ? uint24(1 << 23) : uint24(1 << 22));
            uint80 packed = TicketQueueStorage.owedById(address(game), key, driverId);
            weight = uint256(uint32(packed >> 8)) * 100 + uint8(packed);
        }
        assertGt(weight, 0, "paid driver tickets remain claimable without materialization");
        uint256 expected = terminalPot * weight / terminalWeight;
        assertGt(expected, 0, "nonzero queued ending payout");
        uint256[] memory refs = new uint256[](1);
        refs[0] = uint256(1) << 248 | uint256(key) << 32 | driverId;
        uint256 before = _idLedger(driverId);
        uint256 pool = game.claimablePoolView();
        vm.prank(HOLDER);
        game.claimDeadVrf(driverId, refs);
        assertEq(_idLedger(driverId) - before, expected, "queued share credits owner, not permissionless caller");
        assertEq(game.claimablePoolView() - pool, expected, "queued share reserves exact liability");
        vm.expectRevert();
        game.claimDeadVrf(driverId, refs);
        uint256 claimable = game.claimableWinningsOf(DRIVER);
        uint256 cash = _cash(DRIVER);
        vm.prank(DRIVER);
        game.claimClaimable(driverId);
        assertEq(_cash(DRIVER) - cash, claimable - 1, "ending ticket value withdraws once");
        _solvent();
    }

    function _assertFinalSweep() private {
        // A late callback after terminal settlement only clears the mock coordinator's
        // outstanding request, allowing cancellation to exercise the actual native refund.
        _fulfill();
        assertEq(mockVRF.pendingCount(1), 0, "subscription can refund");
        (, uint96 nativeRefund,,,) = mockVRF.getSubscription(1);
        assertGt(nativeRefund, 0, "nonvacuous native refund");
        uint256[3] memory before = [_cash(address(vault)), _cash(address(sdgnrs)), _cash(address(gnrus))];
        uint256[3] memory expected = [_idLedger(1), _idLedger(2) + game.redemptionReserve(), _idLedger(3)];
        uint256 funds = _cash(address(game));
        uint256 owed = expected[0] + expected[1] + expected[2];
        if (funds >= owed) {
            uint256 remainder = funds - owed;
            expected[0] += remainder / 3;
            expected[1] += remainder / 3;
            expected[2] += remainder - 2 * (remainder / 3);
        } else {
            expected[0] = expected[0] * funds / owed;
            expected[1] = expected[1] * funds / owed;
            expected[2] = funds - expected[0] - expected[1];
        }
        uint256 coordinatorBefore = _cash(address(mockVRF));
        uint256 adminBefore = _cash(address(admin));
        uint256 sinks = _terminalCustody();
        vm.warp(vm.getBlockTimestamp() + 31 days);
        _drain(false);
        assertEq(_cash(address(game)), 0, "healthy assets fully swept");
        assertEq(_cash(address(vault)) - before[0], expected[0] + nativeRefund, "Vault entitlement plus VRF refund");
        assertEq(_cash(address(sdgnrs)) - before[1], expected[1], "sDGNRS entitlement");
        assertEq(_cash(address(gnrus)) - before[2], expected[2], "GNRUS entitlement and rounding remainder");
        assertEq(coordinatorBefore - _cash(address(mockVRF)), nativeRefund, "native refund leaves coordinator");
        assertEq(_cash(address(admin)), adminBefore, "refund routes directly to Vault");
        assertEq(_terminalCustody(), sinks, "terminal sweep conserves ETH plus stETH custody");
    }

    function _terminalCustody() private view returns (uint256) {
        return _cash(address(game)) + _cash(address(sdgnrs)) + _cash(address(vault)) + _cash(address(gnrus))
            + _cash(address(admin)) + _cash(address(mockVRF));
    }
    function _cash(address account) private view returns (uint256) {
        return account.balance + mockStETH.balanceOf(account);
    }
    function _cashLedger(address account) private view returns (uint256) {
        return game.claimableWinningsOf(account) + game.afkingFundingOf(account);
    }
    function _idLedger(uint32 id) private view returns (uint256) {
        (uint128 claimable, uint128 afking) = lens.accountBalances(address(game), id);
        return uint256(claimable) + afking;
    }
    function _fullTerm() private pure returns (uint256) { return PRINCIPAL * 110 / 100; }
    function _open(uint32 id) private view returns (bool) {
        return id != 0 && lens.loanOf(address(game), id).principal != 0;
    }
    function _anyLoan() private view returns (bool) { return _open(borrowers[0]) || _open(borrowers[1]); }
    function _solvent() private view {
        assertGe(SolvencyObligations.backing(game), SolvencyObligations.obligations(game), "composed solvency");
    }
}
