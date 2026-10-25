// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionCloseHarness} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Seeds every storage field the miner selector and the Game's `_rngConsumerStage` read. Inherits the Game,
///      so `rngConsumerStage_g379()` runs the Game's compiled copy while `nextMinerAction()` delegates to the
///      deployed MinerModule, whose compiled copy of the same source is the one the selector used.
contract ChainPinStageHarness is DegenerusGame {
    struct Seed {
        bool gameOver;
        bool locked;
        bool active;
        bool published;
        bool complete;
        bool ticketsDone;
        bool humanDone;
        bool bit13;
        bool midDay;
        bool lastPurchase;
        bool jackpot;
        bool hardStall;
        bool goLatch;
        bool goDead;
        bool wordRecorded;
        bool nextPoolMet;
        bool degPending;
        bool decQueued;
        bool crapsRead;
        bool boxesPending;
        uint24 level;
        uint24 purchaseStart;
        uint24 dailyIdx;
        uint24 requestDay;
        uint48 requestTime;
        uint256 word;
    }

    function seed(Seed calldata s) external {
        gameOver = s.gameOver;
        rngLockedFlag = s.locked;
        if (s.active) _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId); else _clearRngRequest();
        _setRngSessionPublished(s.published);
        _setRngComplete(s.complete);
        ticketsFullyProcessed = s.ticketsDone;
        humanReadComplete = s.humanDone;
        if (s.bit13) rngFlagsAndNudges |= uint16(1) << 13;
        else rngFlagsAndNudges &= ~(uint16(1) << 13);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, s.midDay ? 1 : 0);
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, s.goLatch ? 1 : 0);
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, s.goDead ? 1 : 0);
        lastPurchaseDay = s.lastPurchase;
        jackpotPhaseFlag = s.jackpot;
        dailyComplete = s.complete;
        lastDailyCompletedAt = uint48(block.timestamp - (s.hardStall ? 14 days : 1 days));
        lastDailyRequestWallDay = _wallDay() - 1;
        level = s.level;
        purchaseStartDay = s.purchaseStart;
        dailyIdx = s.dailyIdx;
        rngRequestDay = s.requestDay;
        rngRequestTime = s.requestTime;
        rngWordCurrent = s.word;
        _setPrizePools(s.nextPoolMet ? type(uint128).max : 0, 0);
        if (s.wordRecorded) _recordDailyRng(s.dailyIdx, 0x1234);
        _pendingBoxCount = s.boxesPending ? 1 : 0;
        degeneretteReadCount = s.degPending ? 1 : 0;
        degeneretteCursor = 0;
        decBattleQueue = s.decQueued ? 1 : 0;
        uint256 craps = uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer());
        lootboxRngPacked = s.crapsRead ? lootboxRngPacked | craps : lootboxRngPacked & ~craps;
    }
}

/// @dev Seeds Game-side redemption funding: sDGNRS's Game claimable (inside claimablePool) and the protected
///      redemption reserve (inside claimablePool), the two stores live settlement draws from.
contract ChainPinFundHarness is DegenerusGame {
    function fund(uint256 amount) external {
        _creditClaimableLogged(SDGNRS_WALLET_ID, amount);
        claimablePool += uint128(amount);
    }

    function fundReserve(uint256 amount) external {
        _setRedemptionReserve(_redemptionReserve() + amount);
        claimablePool += uint128(amount);
    }
}

/// @notice A-F1: the Game's compiled `_rngConsumerStage` (read by `sDGNRS.runRedemptionWork` through
///         `game.rngConsumerStage_g379()`) must agree with the MinerModule copy the selector used. A selected
///         Redemption action must never meet `RedemptionStageBlocked`, which would stop stage 1 for good.
contract ChainPinConsumerStage is DeployProtocol {
    uint256 internal redemptionHits;
    uint256 internal deadlineHits;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 400 days);
        _seedLogicalFixtureDay(409);
    }

    function _bit(uint256 h, uint256 k, uint256 oneIn) private pure returns (bool) {
        return (h >> (k * 8)) % oneIn == 0;
    }

    /// @dev Mostly-ready baseline for stage 1; each condition flips with probability 1/oneIn.
    function _seed(uint256 salt, uint24 today, uint256 oneIn) private view returns (ChainPinStageHarness.Seed memory s) {
        uint256 h = uint256(keccak256(abi.encode(salt, "bits")));
        uint256 g = uint256(keccak256(abi.encode(salt, "bits2")));
        s.gameOver = _bit(h, 0, oneIn * 2);
        s.locked = _bit(h, 1, oneIn);
        s.active = _bit(h, 2, oneIn);
        s.published = !_bit(h, 3, oneIn);
        s.complete = _bit(h, 4, oneIn);
        s.ticketsDone = !_bit(h, 5, oneIn);
        s.humanDone = _bit(h, 6, 2);
        s.bit13 = _bit(h, 7, oneIn * 2);
        s.midDay = _bit(h, 8, oneIn);
        s.lastPurchase = _bit(h, 9, 4);
        s.jackpot = _bit(h, 10, 4);
        s.hardStall = _bit(h, 11, oneIn * 2);
        s.goLatch = _bit(h, 12, oneIn * 2);
        s.goDead = _bit(h, 13, oneIn * 2);
        s.wordRecorded = _bit(h, 14, 3);
        s.nextPoolMet = _bit(h, 15, 3);
        s.degPending = _bit(g, 0, oneIn);
        s.decQueued = _bit(g, 1, oneIn);
        s.crapsRead = _bit(g, 2, oneIn);
        s.boxesPending = _bit(g, 3, oneIn);
        s.level = uint24((g >> 40) % 3 == 0 ? 0 : 1 + (g >> 48) % 150);
        // Thirty completed logical rounds at every level; place the boundary near today.
        uint24 span = 30;
        s.purchaseStart = uint24(uint256(today) + (g >> 64) % 5 - 2 - span);
        uint256 idxPick = (g >> 72) % 6;
        s.dailyIdx = idxPick < 3 ? today - 1 : idxPick == 3 ? today : idxPick == 4 ? today - 2 : today - 31;
        s.requestDay = uint24(uint256(today) - (g >> 80) % 3);
        uint256 timePick = (g >> 88) % 4;
        s.requestTime = uint48(
            timePick == 0 ? block.timestamp : timePick == 1 ? block.timestamp - 14 days - 1
                : timePick == 2 ? block.timestamp - 13 days : block.timestamp - 1 hours
        );
        s.word = (g >> 96) % 5 == 0 ? 0 : (g >> 96) % 7 == 0 ? 1 : (g >> 100) | 2;
    }

    /// @dev Runs one seeded state and returns whether the selector chose Redemption.
    function _check(ChainPinStageHarness.Seed memory s, bool pending) internal returns (bool redemption) {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ChainPinStageHarness).runtimeCode);
        ChainPinStageHarness(payable(address(game))).seed(s);
        vm.etch(address(game), original);
        vm.mockCall(address(sdgnrs), abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(pending));
        uint8 action = game.nextMinerAction();
        uint8 stage = game.rngConsumerStage_g379();
        // Redemption = 7 ... CertifyRead = 13: the consumer branch maps stage n to action n + 6.
        if (action >= 7 && action <= 13) assertEq(stage, action - 6, "selected consumer action != Game stage");
        // A Game stage 1 must have been selected as Redemption (no loan seizure is pending in these states).
        if (stage == 1) assertEq(action, 7, "Game stage 1 not selected as Redemption");
        redemption = action == 7;
        if (redemption) {
            assertEq(stage, 1, "selected Redemption would hit RedemptionStageBlocked");
            ++redemptionHits;
            if (game.currentDayView_g542950() > uint256(s.purchaseStart) + 30) ++deadlineHits;
        }
    }

    function _today() internal view returns (uint24) {
        return uint24(game.currentDayView_g542950());
    }

    /// @notice Fuzz over storage states, with the purchase-deadline boundary day and the VRF deadman edge
    ///         inside the seeded ranges.
    /// forge-config: default.fuzz.runs = 400
    function testFuzz_selectedRedemptionNeverMeetsStageBlocked(uint256 salt, bool pending) public {
        uint256 oneIn = 6 + (salt >> 200) % 20;
        _check(_seed(salt, _today(), oneIn), pending);
    }

    /// @notice The exact state in which the only virtual predicate (`_pastDeadlineTriggered`, overridden only
    ///         in the MintModule) matters: past the purchase deadline on a caught-up day with nothing
    ///         rescuing the level. The Game ends it; the selector must not offer stage 1.
    function test_pastDeadlineBoundaryAgreement() public {
        uint24 today = _today();
        for (uint24 offset; offset < 5; ++offset) {
            for (uint256 variant; variant < 4; ++variant) {
                ChainPinStageHarness.Seed memory s = _readySeed(today);
                s.level = variant == 0 ? 0 : 7;
                uint24 span = 30;
                s.purchaseStart = today + 2 - offset - span; // deadline = today + 2 - offset
                s.wordRecorded = variant == 2; // a day that holds its word is finished on it
                s.nextPoolMet = variant == 3; // a met target rescues the level
                _check(s, true);
            }
        }
    }

    /// @notice The control: the ready state selects Redemption and the Game agrees.
    function test_readyStateSelectsRedemption() public {
        assertTrue(_check(_readySeed(_today()), true), "ready state selects Redemption");
        ChainPinStageHarness.Seed memory s = _readySeed(_today());
        s.hardStall = true; // Fourteen real days without completing a round
        assertFalse(_check(s, true), "deadman fired: no stage 1");
        s = _readySeed(_today());
        s.dailyIdx = _today() - 30; // A logical gap alone has no hard-deadline meaning
        assertTrue(_check(s, true), "logical distance alone cannot trigger the hard deadline");
    }

    /// @notice Non-vacuity: the fuzz generator reaches Redemption, and the past-deadline region, in volume.
    function test_generatorReachesRedemptionAndDeadlineRegion() public {
        uint24 today = _today();
        for (uint256 i; i < 300; ++i) {
            _check(_seed(i * 7919 + 13, today, 10), true);
        }
        assertGt(redemptionHits, 10, "generator reaches Redemption");
        assertGt(deadlineHits, 0, "generator reaches the past-deadline region while Redemption is selected");
    }

    function _readySeed(uint24 today) internal view returns (ChainPinStageHarness.Seed memory s) {
        s.published = true;
        s.ticketsDone = true;
        s.level = 7;
        s.purchaseStart = today - 5;
        s.dailyIdx = today - 1;
        s.requestDay = today;
        s.requestTime = uint48(block.timestamp - 1 hours);
        s.word = 0xABCDEF;
    }
}

/// @notice Redemption funding, escrow and century identities, checked at every step of a multi-call
///         live settlement (A-F3, A-F4, F-B8, S1 F9, A-F7). A-F5 and A-F6 are pinned by
///         test/invariant/RedemptionAccounting.t.sol (invariant_INV_04_TokenConservation).
contract ChainPinRedemptionLedger is RedemptionFixture {
    address[] internal holders;
    uint256 internal steps;

    function setUp() public override {
        super.setUp();
        address dave = makeAddr("dave");
        address erin = makeAddr("erin");
        _giveWalletId(dave);
        _giveWalletId(erin);
        holders.push(alice);
        holders.push(bob);
        holders.push(carol);
        holders.push(dave);
        holders.push(erin);
        // Wide holder shares: alice takes three pools (63% of supply), so a burn can exceed 57% of the holder base
        // (where the 175% maximum payout is capped by free backing).
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Affiliate, alice, sdgnrs.poolBalance(sDGNRS.Pool.Affiliate));
        sdgnrs.transferFromPool(sDGNRS.Pool.Lootbox, alice, sdgnrs.poolBalance(sDGNRS.Pool.Lootbox));
        sdgnrs.transferFromPool(sDGNRS.Pool.Whale, alice, sdgnrs.poolBalance(sDGNRS.Pool.Whale));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, dave, sdgnrs.poolBalance(sDGNRS.Pool.Reward) / 2);
        sdgnrs.transferFromPool(sDGNRS.Pool.Degenesis, erin, sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) / 3);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Harness helpers
    // ---------------------------------------------------------------------

    function _r(uint256 seed, uint256 k) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, k)));
    }

    /// @dev sDGNRS's Game claimable += amount, with the ETH behind it in the Game.
    function _fundOrdinary(uint256 amount) private {
        vm.deal(address(game), address(game).balance + amount);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(ChainPinFundHarness).runtimeCode);
        ChainPinFundHarness(payable(address(game))).fund(amount);
        vm.etch(address(game), code);
    }

    /// @dev Smallest live burn the admission floor accepts, priced exactly as `burn` prices it.
    function _liveMinBurn() private view returns (uint256) {
        uint256 base = sdgnrs.totalSupply() + _escrow();
        (uint256 money,) = sdgnrs.previewBurnValue(base);
        if (money == 0) return type(uint256).max;
        return (sdgnrs.MIN_REDEMPTION_VALUE() * base + money - 1) / money;
    }

    /// @dev The production close hook (`_closeRedemptionBatch`): release, price, pull, debit, send.
    function _closeProduction() private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
    }

    /// @dev S1 F9 on the live state: the pull the sDGNRS close would report is strictly below the sDGNRS
    ///      claimable (it leaves the registration sentinel), then the production hook runs without `Insolvent`.
    function _closeAssertingPull() private returns (uint256 pull) {
        // The production close first releases the previous batch's leftover reserve into the claimable.
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve();
        uint256 snap = vm.snapshotState();
        vm.prank(address(game));
        pull = sdgnrs.closeRedemptionBatch(claimable);
        if (claimable == 0) assertEq(pull, 0, "F9: pull from an empty claimable");
        else assertLt(pull, claimable, "F9: pull must stay at or below claimable - 1");
        assertTrue(vm.revertToState(snap));
        _closeProduction();
        assertEq(game.redemptionReserve(), pull, "the whole pull is the Game redemption reserve");
        assertGe(game.claimableWinningsOf(address(sdgnrs)), 1, "F9: the claimable sentinel survives the close");
    }

    /// @dev Burns for up to five holders (a holder may burn several times into the open batch).
    function _burnRound(uint256 seed) private returns (uint256 burned) {
        uint256 count = 1 + _r(seed, 1) % 6;
        for (uint256 i; i < count; ++i) {
            address who = holders[_r(seed, 10 + i) % holders.length];
            uint256 bal = sdgnrs.balanceOf(who);
            if (bal == 0) continue;
            uint256 minBurn = _liveMinBurn();
            if (bal < minBurn) continue;
            uint256 pick = _r(seed, 20 + i) % 4;
            uint256 amount = pick == 0 ? bal : pick == 1 ? bal / 2 : minBurn + _r(seed, 30 + i) % (bal - minBurn + 1);
            if (amount < minBurn) amount = minBurn;
            if (amount > bal) amount = bal;
            vm.prank(who);
            try sdgnrs.burn(amount) {
                ++burned;
            } catch {}
        }
    }

    /// @dev Σ of the rolled shares not yet paid in `id`: the open claims' floored shares of the batch payout
    ///      (the maximum before resolution).
    function _remainingRolled(uint32 id) private view returns (uint256 sum) {
        (uint256 tokens, uint256 payout,,,,) = sdgnrs.redemptionBatches(id);
        if (tokens == 0) return 0;
        for (uint256 i; i < holders.length; ++i) {
            (uint256 t,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(holders[i]), id);
            sum += payout * t / tokens;
        }
    }

    /// @dev A-F3 / A-F4 / F-B8 after any step: the reserve sits inside claimablePool and covers every
    ///      unpaid rolled share and the pending redemption value.
    function _assertLedger(uint32 id) private {
        uint256 reserve = game.redemptionReserve();
        assertLe(reserve, game.claimablePoolView(), "A-F4: redemption reserve exceeds claimablePool");
        uint256 remaining = _remainingRolled(id);
        assertGe(reserve, remaining, "A-F3: Game reserve < remaining rolled shares");
        assertGe(reserve, sdgnrs.pendingRedemptionEthValue(), "A-F3: Game reserve < pending redemption value");
        assertGe(sdgnrs.pendingRedemptionEthValue(), remaining, "pending value below remaining rolled shares");
        ++steps;
    }

    function _runSteps(uint256 seed, uint32 id) private {
        uint256 word = _wordForRoll(uint16(21 + _r(seed, 50) % 155));
        settlementWord = word;
        _mockSettlingStage();
        bool done;
        for (uint256 i; i < 60 && !done; ++i) {
            uint256 r = _r(seed, 100 + i);
            // A tiny allowance with first-unit permission runs exactly one unit (resolve, then one claim).
            uint256 allowance = r % 3 == 0 ? 9_000_000 : MineFlipGas.budget(1, 10_000, true);
            if (((r >> 8) & 3) == 0) {
                // ETH forced into sDGNRS mid-settlement changes neither live pricing nor the reserve.
                (uint256 priceBefore,) = sdgnrs.previewBurnValue(1e18);
                uint256 reserveBefore = game.redemptionReserve();
                vm.deal(address(sdgnrs), address(sdgnrs).balance + (r >> 16) % 3 ether);
                (uint256 priceAfter,) = sdgnrs.previewBurnValue(1e18);
                assertEq(priceAfter, priceBefore, "custody ETH moved the live price");
                assertEq(game.redemptionReserve(), reserveBefore);
            }
            vm.prank(address(game));
            done = sdgnrs.runRedemptionWork(word, allowance).done;
            _assertLedger(id);
        }
        assertTrue(done, "settlement finished");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "all rolled value paid or released");
        assertEq(_remainingRolled(id), 0, "no unpaid share remains");
        vm.clearMockedCalls();
    }

    // ---------------------------------------------------------------------
    // A-F3 / A-F4 / F-B8 / F9
    // ---------------------------------------------------------------------

    /// @notice Fuzz: funding size, holder shares, rolls and call sizes over up to three consecutive batches,
    ///         asserting the reserve identities after every call.
    /// forge-config: default.fuzz.runs = 150
    function testFuzz_fundingIdentitiesAtEveryStep(uint256 seed) public {
        uint256 batches = 1 + _r(seed, 0) % 3;
        for (uint256 b; b < batches; ++b) {
            uint256 s = _r(seed, 1000 + b);
            _fundOrdinary(0.2 ether + _r(s, 1) % 400 ether);
            // Custody ETH is irrelevant to live settlement; sometimes present, sometimes not.
            vm.deal(address(sdgnrs), _r(s, 3) % 3 == 0 ? _r(s, 4) % 50 ether : 0);
            if (_burnRound(s) == 0) continue;
            if (!sdgnrs.redemptionSettlementPending()) {
                uint32 id = _openBatchId();
                _closeAssertingPull();
                _assertLedger(id);
                _runSteps(s, id);
            }
        }
    }

    /// @notice Deterministic extreme: a 63% holder at the maximum roll. The maximum payout is capped at free
    ///         backing, so the pull equals everything but the sentinel; every leg draws the Game reserve and the
    ///         lootbox legs consume claimablePool.
    function test_extremeShareRidesTheLedgerEverywhere() public {
        _fundOrdinary(100 ether);
        uint256 poolBefore = game.claimablePoolView();
        uint256 bal = sdgnrs.balanceOf(alice);
        vm.prank(alice);
        sdgnrs.burn(bal);
        uint32 id = _openBatchId();
        uint256 pull = _closeAssertingPull();
        assertGt(pull, 50 ether, "the close isolates a large Game ledger reserve");
        _assertLedger(id);
        settlementWord = _wordForRoll(175);
        _mockSettlingStage();
        bool done;
        for (uint256 i; i < 30 && !done; ++i) {
            vm.prank(address(game));
            done = sdgnrs.runRedemptionWork(settlementWord, MineFlipGas.budget(1, 10_000, true)).done;
            _assertLedger(id);
        }
        assertTrue(done);
        assertLt(game.claimablePoolView(), poolBefore, "the lootbox legs left claimablePool with the value");
        assertGt(steps, 2, "several asserted steps");
    }

    /// @notice F9 across the full range of batch sizes against a claimable-only backing.
    /// forge-config: default.fuzz.runs = 200
    function testFuzz_pullStaysBelowClaimable(uint256 shareBps, uint256 ordinary) public {
        ordinary = bound(ordinary, 1 ether, 1_000 ether);
        shareBps = bound(shareBps, 1, 6300);
        _fundOrdinary(ordinary);
        uint256 amount = sdgnrs.totalSupply() * shareBps / 10_000;
        uint256 bal = sdgnrs.balanceOf(alice);
        if (amount > bal) amount = bal;
        if (amount == 0 || amount < _liveMinBurn()) return;
        vm.prank(alice);
        sdgnrs.burn(amount);
        uint32 id = _openBatchId();
        _closeAssertingPull();
        _assertLedger(id);
    }

    // ---------------------------------------------------------------------
    // A-F7: holder base <= centurySupplyCheckpoint at every x00 recycle
    // ---------------------------------------------------------------------

    function _holderBase() private view returns (uint256) {
        return sdgnrs.totalSupply() + _escrow();
    }

    /// @notice Random sequences of live burns (escrow), batch closes and settlements, pool self-awards,
    ///         wrapped burns, liquidations and century recycles. The holder base never exceeds the checkpoint,
    ///         so `recycleCentury`'s `checkpoint - base` never reverts.
    /// forge-config: default.fuzz.runs = 120
    function testFuzz_holderBaseNeverExceedsCenturyCheckpoint(uint256 seed) public {
        uint256 recycles;
        _fundOrdinary(10_000 ether);
        for (uint256 i; i < 16; ++i) {
            uint256 r = _r(seed, i);
            uint256 op = r % 8;
            if (op == 0 || op == 1) {
                address who = holders[(r >> 8) % 3];
                uint256 bal = sdgnrs.balanceOf(who);
                uint256 minBurn = _liveMinBurn();
                if (bal >= minBurn) {
                    uint256 amount = minBurn + (r >> 16) % (bal - minBurn + 1);
                    vm.prank(who);
                    try sdgnrs.burn(amount) {} catch {}
                }
            } else if (op == 2) {
                if (!sdgnrs.redemptionSettlementPending() && _escrow() != 0) {
                    _closeProduction();
                    settlementWord = _wordForRoll(uint16(21 + (r >> 8) % 155));
                    _mockSettlingStage();
                    for (uint256 k; k < 40 && sdgnrs.redemptionSettlementPending(); ++k) _work(9_000_000);
                    vm.clearMockedCalls();
                }
            } else if (op == 3) {
                uint256 avail = sdgnrs.poolBalance(sDGNRS.Pool(uint8((r >> 8) % 4)));
                if (avail != 0) {
                    vm.prank(address(game));
                    sdgnrs.transferFromPool(sDGNRS.Pool(uint8((r >> 8) % 4)), address(sdgnrs), (r >> 16) % avail + 1);
                }
            } else if (op == 4) {
                vm.prank(address(game));
                sdgnrs.burnForLiquidation(holders[(r >> 8) % holders.length]);
            } else if (op == 5) {
                uint256 vaultBal = dgnrs.balanceOf(ContractAddresses.VAULT);
                uint256 minBurn = _liveMinBurn();
                if (vaultBal >= minBurn && game.walletIdOf_g3120(ContractAddresses.VAULT) != 0) {
                    vm.prank(ContractAddresses.VAULT);
                    try sdgnrs.burnWrapped(minBurn + (r >> 16) % (vaultBal / 20 + 1)) {} catch {}
                }
            } else {
                uint24 century = uint24(sdgnrs.lastRecycledCentury() + 1);
                uint256 base = _holderBase();
                assertLe(base, sdgnrs.centurySupplyCheckpoint(), "A-F7: holder base above the checkpoint at recycle");
                vm.prank(address(game));
                sdgnrs.recycleCentury(century * 100, r);
                ++recycles;
                assertEq(sdgnrs.centurySupplyCheckpoint(), _holderBase(), "the recycle restamps the post-mint base");
            }
            assertLe(_holderBase(), sdgnrs.centurySupplyCheckpoint(), "A-F7: holder base above the checkpoint");
        }
        // Closing recycle after the sequence settles whatever was left.
        uint24 closing = uint24(sdgnrs.lastRecycledCentury() + 1) * 100;
        vm.prank(address(game));
        sdgnrs.recycleCentury(closing, seed);
    }

    /// @notice Directed: a refill mint followed by a self-award burn, a liquidation and a live burn before the
    ///         next x00.
    function test_refillThenBurnsThenNextRecycle() public {
        _fundOrdinary(10_000 ether);
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(sdgnrs), sdgnrs.poolBalance(sDGNRS.Pool.Whale) / 2);
        sdgnrs.recycleCentury(100, 53);
        vm.stopPrank();
        assertEq(sdgnrs.centurySupplyCheckpoint(), _holderBase());
        uint256 bal = sdgnrs.balanceOf(alice);
        vm.prank(alice);
        sdgnrs.burn(bal / 3);
        vm.startPrank(address(game));
        sdgnrs.burnForLiquidation(bob);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, address(sdgnrs), 1e12);
        vm.stopPrank();
        assertLe(_holderBase(), sdgnrs.centurySupplyCheckpoint());
        vm.prank(address(game));
        sdgnrs.recycleCentury(200, 54);
        assertEq(sdgnrs.centurySupplyCheckpoint(), _holderBase());
    }
}
