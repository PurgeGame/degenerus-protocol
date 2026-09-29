// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @title Subscription churn accounting and streak regressions
/// @notice Claim/cancel/upsert receipts are measured from wallet, claimable and next-day stake
///      deltas, including implicit payouts. Paid plus pending rewards reconcile to actual funded
///      deliveries; each affiliate recipient is checked separately. Honest and churn controls
///      share a timeline, while random lootbox returns and later coinflip outcomes are outside
///      the subscription-principal comparison. Other cases cover streak handback, no-orphan
///      processing, the affiliate-only drain and claim idempotency.
/// @dev Uses real funded subscriptions and production buy/open/claim/cancel paths. Storage
///      probes read the current packed Sub layout. Only test fixtures grant membership seats.
contract V56SecUnmanipulable is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the v56 Sub-slot offset block (V56AfkingGasMarginal:68-89)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 52;            // _subOf mapping root (address => Sub, one packed slot) (was 58)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 55; // mapping(address => uint256) _subscriberIndex (1-indexed) (was 61)

    //   dailyQuantity u8 @0 · flags u8 @1 · score u16 @2 · amount u24 @4
    //   lastAutoBoughtDay u24 @7 · lastOpenedDay u24 @10 · afkCoveredThroughDay u24 @13 · afkingStartDay u24 @16
    //   affiliateBase u32 @19 · pendingFlip u24 @23 · subStreakLatch u16 @26
    uint256 private constant OFF_DAILY = 0;           // uint8  dailyQuantity        (byte 0)
    uint256 private constant OFF_LASTBOUGHT = 7;      // uint24 lastAutoBoughtDay    (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10;     // uint24 lastOpenedDay        (bytes 10..12)
    uint256 private constant OFF_AFKCOVERED = 13;     // uint24 afkCoveredThroughDay (bytes 13..15)
    uint256 private constant OFF_AFKINGSTART = 16;    // uint24 afkingStartDay       (bytes 16..18)
    uint256 private constant OFF_AFFBASE = 19;        // uint32 affiliateBase        (bytes 19..22)
    uint256 private constant OFF_PENDINGFLIP = 23;    // uint24 pendingFlip          (bytes 23..25)
    uint256 private constant OFF_STREAKLATCH = 26;    // uint16 subStreakLatch       (bytes 26..27; full streak counter)

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole FLIP accrued to pendingFlip per delivered buy.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = AutoPause (funding-skip kill of
    ///      a NORMAL sub), reason 2 = cancel-reclaim (the in-stage tombstone reclaim).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // Repro 1 — affiliate re-claim churn (automatic payments conserve earned principal)
    // =========================================================================

    /// @notice Compare actual paid-plus-pending obligations on one timeline. Cancellation pays
    ///      both ledgers automatically; re-subscribing on that day must neither buy nor pay twice.
    function testAffiliateReClaimChurnEqualsHonestContinuous() public {
        ChurnLedger memory honest = _newChurnLedger("aff_honest");
        ChurnLedger memory churn = _newChurnLedger("aff_churn");
        _observeChurnAction(honest, 0);
        _observeChurnAction(churn, 0);
        for (uint256 d; d < 3; ++d) {
            _deliverLedgerDay(honest, churn, uint256(keccak256(abi.encode("aff", d))) | 1);
            assertGt(_affiliateBaseOf(churn.player), 0, "cancel must drain an earned affiliate obligation");
            _observeChurnAction(churn, 2);
            _observeChurnAction(churn, 1); // auto-paid pendingFlip cannot be claimed again
            _observeChurnAction(churn, 3); // duplicate sub IDs cannot reclaim the auto-paid base
            if (d != 2) {
                uint256 bought = churn.delivered;
                _observeChurnAction(churn, 0);
                assertEq(churn.delivered, bought, "same-day re-subscribe cannot manufacture another buy");
            }
        }
        _observeChurnAction(honest, 1);
        _observeChurnAction(honest, 3);
        _assertChurnLedger(honest);
        _assertChurnLedger(churn);
        assertGt(churn.playerPaid, 0, "cancellation really paid the subscriber");
        assertGt(churn.affiliatePaid, 0, "cancellation really paid all uplines");
        assertEq(churn.delivered, honest.delivered, "controls received the same paid deliveries");
        assertEq(churn.spent, honest.spent, "controls paid the same funding cost");
        assertEq(churn.playerPaid, honest.playerPaid, "churn preserves total earned slot-0 principal");
        assertEq(churn.affiliatePaid, honest.affiliatePaid, "churn preserves total earned affiliate principal");
    }

    /// @notice The affiliateBase drain entrypoint is AFFILIATE-only: a non-AFFILIATE caller can never drain
    ///         (and thus never redirect) a sub's running base. The read-and-zero lives at the Game storage
    ///         owner so a churner can never route the base to a wrong recipient nor double-credit it.
    ///         (`drainAffiliateBase` is reachable in production only through the DegenerusAffiliate `claim`
    ///         path; a direct non-affiliate call reverts before touching the slot.)
    function testAffiliateBaseDrainAffiliateOnly() public {
        address p = makeAddr("aff_gate");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xA66A11);
        uint32 baseBefore = _affiliateBaseOf(p);
        assertGt(baseBefore, 0, "non-vacuity: base accrued");

        // A non-affiliate caller cannot reach the drain (it reverts before any storage write).
        vm.prank(makeAddr("not_affiliate"));
        vm.expectRevert();
        IGameAfkingModule(address(game)).drainAffiliateBase(p);
        assertEq(_affiliateBaseOf(p), baseBefore, "rejected non-affiliate drain left the base intact");
    }

    // =========================================================================
    // Repro 2 — streak gap dodge (compute-on-read; advances only on delivered days)
    // =========================================================================

    /// @notice A live funded sub's gap is a protocol-side skip (the no-orphan guard is the only gap source
    ///         for a live funded sub), so the run survives it: the finalize WRITE hands the earned streak
    ///         back intact, anchored at the day before the sub ended. Gap days still earn nothing — the
    ///         streak freezes across the gap, never resets.
    function testStreakSurvivesProtocolSkipGapIntact() public {
        address p = makeAddr("decay_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);

        // Build a few delivered days so the run has a covered high-water and a real earned streak.
        _deliverDay(_singleton(p), 0xDECA01);
        _deliverDay(_singleton(p), 0xDECA02);
        uint32 coveredBefore = _afkCoveredOf(p);
        uint32 earnedBefore = coveredBefore - _afkingStartOf(p);
        assertGt(earnedBefore, 0, "non-vacuity: the run earned a streak over delivered days");

        // Advance several days WITHOUT opening the stamped boxes. The first no-open day still DELIVERS
        // (the sub was box-clean, so the STAGE stamps a new box — one more earned day); every later cycle
        // hits the no-orphan guard and skips the funded sub (the protocol-side gap — the sub never misses
        // a day it could have paid for). The covered high-water then goes stale by >= 2 days.
        _skipDaysNoDelivery(0xDECA03);
        _skipDaysNoDelivery(0xDECA04);
        _skipDaysNoDelivery(0xDECA05);

        uint32 currentDay = game.currentDayView();
        assertGt(currentDay, coveredBefore + 1, "gap window: covered + 1 < currentDay (a protocol-skip gap exists)");

        // CANCEL on a post-gap day -> finalize hands the earned streak back INTACT: the handback anchor is
        // the day before the cancel (floored at the funded high-water), so the protocol-skip gap zeroes
        // nothing. Gap days earned nothing — the handback equals the pre-gap earned streak.
        if (_subscriberIndexOf(p) == 0) {
            _settleForfeit(p); // the funding-kill left the forfeit gate set
            _subscribeLootbox(p, 1); // re-create the slot to drive the explicit-cancel finalize
        }
        vm.recordLogs();
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, address(0));
        uint24 finalStreak = _lastFinalizeStreakFor(p);
        assertEq(
            finalStreak,
            earnedBefore + 1,
            "protocol-skip gap: finalize handed back the earned streak intact (+1 for the first no-open day's delivery; the skipped gap days earned nothing)"
        );
    }

    /// @notice Kill-then-resume re-bases the run: a funding-kill finalizes the old run (handing its streak
    ///         to the manual system, where the missed post-kill days decay it), and the post-gap re-subscribe
    ///         starts a NEW run — `afkingStartDay` at the resume day, base = the (decayed) manual snapshot —
    ///         so the post-gap window credits NO stale-span days. The per-window streak advances ONLY on the
    ///         debit-DELIVERED days since the resume.
    function testGapResetOnResumeRebasesTheRun() public {
        address p = makeAddr("gapresume_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);

        // First window: deliver several consecutive days; the run advances past its start day (the first
        // delivery anchors the run; the subsequent consecutive deliveries grow covered past afkingStartDay).
        _deliverDay(_singleton(p), 0x6A9001);
        _deliverDay(_singleton(p), 0x6A9002);
        _deliverDay(_singleton(p), 0x6A9003);
        uint32 startBefore = _afkingStartOf(p);
        uint32 coveredFirst = _afkCoveredOf(p);
        assertGt(coveredFirst, startBefore, "first window: the streak advanced past its start day");

        // Gap: DEFUND so the sub funding-kills out, then warp several days with NO delivery — a clear
        // missed-funded-day gap that strands the run (the funding-kill finalize zeroes afkingStartDay).
        _drainAllFunding(p);
        _skipDaysNoDelivery(0x6A9004);
        _skipDaysNoDelivery(0x6A9005);
        _skipDaysNoDelivery(0x6A9006);

        // RESUME: re-fund (grounds the re-sub's NEW-run cover-buy — D-12) + re-subscribe + deliver a
        // fresh day after the gap. The funding-kill finalized the old run, so the re-sub starts a NEW run
        // (afkingStartDay := the resume day; base := the manual snapshot, decayed to 0 across the gap).
        _fundPool(p, 50 ether);
        if (_subscriberIndexOf(p) == 0) {
            _settleForfeit(p); // the funding-kill left the forfeit gate set
            _subscribeLootbox(p, 1);
        }
        _deliverDay(_singleton(p), 0x6A9007);

        uint32 startAfter = _afkingStartOf(p);
        uint32 coveredAfter = _afkCoveredOf(p);
        assertGt(startAfter, startBefore, "gap-resume: the run re-based (afkingStartDay advanced to the resume day)");
        assertEq(_streakBaseOf(p), 0, "gap-resume: the streak base reset to 0 (no stale-span credit)");
        // The post-resume effective streak counts ONLY delivered days since the resume (covered - start <= 1).
        assertLe(coveredAfter - startAfter, 1, "post-resume window credits only the delivered day(s) since resume");
    }

    // =========================================================================
    // Stateful churn-fuzz invariant — no churn sequence beats honest continuous accrual
    // =========================================================================

    /// @notice Measure every claim, cancel and upsert using actual asset deltas. Principal
    ///      accounting is per funded delivery: missed buys and lootbox/coinflip outcome variance
    ///      are not manufactured rewards, and a final balance after different claim days is not
    ///      a valid comparison of subscription accrual.
    function testFuzzChurnNeverBeatsHonestContinuous(uint16 actions) public {
        ChurnLedger memory honest = _newChurnLedger("fz_honest");
        ChurnLedger memory churn = _newChurnLedger("fz_churn");
        _observeChurnAction(honest, 0);
        _observeChurnAction(churn, 0);
        for (uint256 d; d < 4; ++d) {
            _deliverLedgerDay(honest, churn, uint256(keccak256(abi.encode("fz", actions, d))) | 1);
            uint8 act = uint8(actions >> (d * 4)) & 15;
            if (act & 1 != 0) _observeChurnAction(churn, 1);
            if (act & 2 != 0 && _dailyQtyOf(churn.player) != 0) _observeChurnAction(churn, 2);
            if (act & 4 != 0) _observeChurnAction(churn, 0); // active upsert also auto-pays pendingFlip
            if (act & 8 != 0) _observeChurnAction(churn, 3);
            _assertChurnLedger(honest);
            _assertChurnLedger(churn);
            if (_dailyQtyOf(churn.player) != 0) {
                uint32 covered = _afkCoveredOf(churn.player);
                uint32 start = _afkingStartOf(churn.player);
                assertLe(start, covered, "run start cannot exceed delivered high-water");
                assertLe(covered, game.currentDayView(), "streak cannot cover a future day");
            }
        }
        _observeChurnAction(honest, 1);
        _observeChurnAction(honest, 3);
        _observeChurnAction(churn, 1);
        _observeChurnAction(churn, 3);
        _assertChurnLedger(honest);
        _assertChurnLedger(churn);
        assertGt(churn.delivered, 0, "the comparison contains funded churn deliveries");
        assertEq(churn.playerPaid * honest.delivered, honest.playerPaid * churn.delivered,
            "claim/cancel/upsert timing cannot manufacture slot-0 principal per paid buy");
        assertEq(churn.affiliatePaid * honest.spent, honest.affiliatePaid * churn.spent,
            "churn cannot manufacture affiliate principal per funded ETH");
        assertLe(churn.delivered, 5, "at most one paid buy per each of five participating days");
    }

    struct ChurnLedger {
        address player;
        address[3] upline;
        address relayer;
        uint256 delivered;
        uint256 lastDay;
        uint256 spent;
        uint256 affiliateEarned;
        uint256 playerPaid;
        uint256 affiliatePaid;
    }

    function _newChurnLedger(string memory name) private returns (ChurnLedger memory ledger) {
        ledger.player = makeAddr(name);
        ledger.relayer = makeAddr(string.concat(name, "_relayer"));
        for (uint256 i; i < 3; ++i) ledger.upline[i] = makeAddr(string.concat(name, vm.toString(i)));
        vm.prank(ledger.player);
        affiliate.referPlayer(bytes32(uint256(uint160(ledger.upline[0]))));
        vm.prank(ledger.upline[0]);
        affiliate.referPlayer(bytes32(uint256(uint160(ledger.upline[1]))));
        vm.prank(ledger.upline[1]);
        affiliate.referPlayer(bytes32(uint256(uint160(ledger.upline[2]))));
        _grantSeat(ledger.player);
        _fundPool(ledger.player, 80 ether);
    }

    /// @dev Read all spendable FLIP plus the not-yet-settled next-day stake. Observations bracket
    ///      one transaction at one timestamp, so intervening coinflip outcomes cannot pollute them.
    function _flipAssets(address who) private view returns (uint256) {
        return coin.balanceOfWithClaimable(who) + coinflip.coinflipAmount(who);
    }

    function _ledgerRecipient(ChurnLedger memory ledger, uint256 i) private pure returns (address) {
        return i == 0 ? ledger.player : i == 4 ? ledger.relayer : ledger.upline[i - 1];
    }

    /// @dev 0 subscribe/upsert, 1 player claim, 2 cancel (both automatic claims), 3 affiliate
    ///      claim with repeated IDs. Exact recipient deltas also reject payment to the relayer.
    function _observeChurnAction(ChurnLedger memory ledger, uint8 action) private {
        uint256[5] memory beforeAssets;
        uint256[5] memory beforePresale;
        for (uint256 i; i < 5; ++i) {
            address recipient = _ledgerRecipient(ledger, i);
            beforeAssets[i] = _flipAssets(recipient);
            beforePresale[i] = game.presaleBoxCreditOf(recipient);
        }
        bool presale = game.lootboxPresaleActiveFlag();
        uint256 fundingBefore = game.afkingFundingOf(ledger.player);
        uint256 price = game.mintPrice();
        uint256 playerOwed = action == 3 ? 0 : uint256(_pendingFlipOf(ledger.player)) * 1 ether;
        uint256 base = action == 2 || action == 3 ? _affiliateBaseOf(ledger.player) : 0;
        // Upserting a tombstone has nothing pending; an active upsert pays under its old terms.
        if (action == 0 && _dailyQtyOf(ledger.player) == 0) playerOwed = 0;
        vm.recordLogs();
        if (action == 0 || action == 2) {
            vm.prank(ledger.player);
            game.subscribe(address(0), false, false, action == 0 ? 1 : 0, address(0));
        } else if (action == 1) {
            vm.prank(ledger.relayer);
            game.claimAfkingFlip(_pair(ledger.player, ledger.player));
        } else {
            vm.prank(ledger.relayer);
            affiliate.claim(_pair(ledger.player, ledger.player));
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[5] memory expected;
        expected[0] = playerOwed;
        expected[2] = (base * 20 / 100) * 1 ether;
        expected[3] = (base * 5 / 100) * 1 ether;
        expected[1] = base * 1 ether - expected[2] - expected[3];
        for (uint256 i; i < 5; ++i) {
            uint256 received = _flipAssets(_ledgerRecipient(ledger, i)) - beforeAssets[i];
            assertEq(received, expected[i], "all automatic/explicit payments must reach the exact entitled recipient");
            uint256 presaleDelta = game.presaleBoxCreditOf(_ledgerRecipient(ledger, i)) - beforePresale[i];
            assertEq(presaleDelta, i == 0 && presale ? playerOwed * 0.0025 ether / (100 ether) : 0,
                "automatic settlement grants presale credit once and only to the subscriber");
            if (i == 0) ledger.playerPaid += received;
            else if (i < 4) ledger.affiliatePaid += received;
        }
        _accountDeliveries(ledger, logs, fundingBefore, price);
        _assertChurnLedger(ledger);
    }

    function _deliverLedgerDay(ChurnLedger memory honest, ChurnLedger memory churn, uint256 word) private {
        uint256 honestFunding = game.afkingFundingOf(honest.player);
        uint256 churnFunding = game.afkingFundingOf(churn.player);
        uint256 price = game.mintPrice();
        vm.recordLogs();
        _deliverDay(_pair(honest.player, churn.player), word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(game.mintPrice(), price, "fixture keeps a stable price while comparing paid delivery units");
        _accountDeliveries(honest, logs, honestFunding, price);
        _accountDeliveries(churn, logs, churnFunding, price);
        _assertChurnLedger(honest);
        _assertChurnLedger(churn);
    }

    function _accountDeliveries(ChurnLedger memory ledger, Vm.Log[] memory logs, uint256 fundingBefore, uint256 price)
        private
    {
        bytes32 delivered = keccak256("AfkingDelivered(address,uint256)");
        bytes32 cover = keccak256("LootBoxBuy(address,uint48,uint256)");
        uint256 cost;
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || address(uint160(uint256(logs[i].topics[1]))) != ledger.player) continue;
            if (logs[i].topics[0] == cover) {
                cost += abi.decode(logs[i].data, (uint256));
            } else if (logs[i].topics[0] == delivered) {
                uint256 packed = abi.decode(logs[i].data, (uint256));
                uint256 day = uint24(packed >> 128);
                assertGt(day, ledger.lastDay, "a delivered buy cannot repeat an already-funded day");
                ledger.lastDay = day;
                cost += uint128(packed);
                ++count;
            }
        }
        assertEq(fundingBefore - game.afkingFundingOf(ledger.player), cost,
            "delivery ledger is backed by actual ETH funding debits");
        assertEq(cost, count * price, "one-unit lootbox subscription buys exactly one priced unit per delivery");
        ledger.delivered += count;
        ledger.spent += cost;
        ledger.affiliateEarned += (cost * 1000 / price * 7 / 100) * 1 ether;
    }

    function _assertChurnLedger(ChurnLedger memory ledger) private view {
        assertEq(ledger.playerPaid + uint256(_pendingFlipOf(ledger.player)) * 1 ether,
            ledger.delivered * SLOT0_FLIP_PER_BUY * 1 ether, "paid plus pending includes every automatic player payment");
        assertEq(ledger.affiliatePaid + uint256(_affiliateBaseOf(ledger.player)) * 1 ether,
            ledger.affiliateEarned, "paid plus pending includes every automatic upline payment");
    }

    // =========================================================================
    // Repro 3 — pendingFlip double-claim CEI idempotency (pays EXACTLY once)
    // =========================================================================

    /// @notice claimAfkingFlip pays the accrued pendingFlip EXACTLY ONCE. The CEI zero-before-credit
    ///         (`s.pendingFlip = 0;` precedes `coinflip.creditFlip`, GameAfkingModule.sol:1277) means a
    ///         double-call in one block credits the FLIP on the first call and ZERO on the second (the
    ///         second sees owed == 0 and `creditFlip(_, 0)` early-returns). Observed via the recipient's
    ///         next-day coinflip stake delta: it rises by exactly `owed * 1e18` once, then not again.
    function testDoubleClaimPaysExactlyOnceCEI() public {
        address p = makeAddr("dbl_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1); // join-day cover-buy accrues 100
        _deliverDay(_singleton(p), 0xDB1C01); // next-day STAGE buy accrues another 100

        // The join-day cover-buy fires after that day's STAGE and the next day is a normal STAGE
        // member, so subscribe + one delivered day = TWO paid buys = 200 whole FLIP.
        uint256 owedWhole = _pendingFlipOf(p);
        assertEq(owedWhole, 2 * SLOT0_FLIP_PER_BUY, "non-vacuity: cover-buy + one delivered STAGE buy = 200 whole FLIP");
        uint256 expectedCredit = owedWhole * 1 ether;

        // FIRST claim: credits owed * 1e18 to the recipient's flip stake and zeroes pendingFlip.
        uint256 stakeBefore = coinflip.coinflipAmount(p);
        game.claimAfkingFlip(_singleton(p));
        uint256 stakeAfter1 = coinflip.coinflipAmount(p);
        assertEq(_pendingFlipOf(p), 0, "CEI: pendingFlip zeroed before the credit (reads 0 after the first claim)");
        assertEq(stakeAfter1 - stakeBefore, expectedCredit, "first claim credited exactly the accrued FLIP");

        // SECOND claim in the same block: the CEI zero means owed == 0 -> creditFlip(_, 0) is a no-op.
        game.claimAfkingFlip(_singleton(p));
        assertEq(coinflip.coinflipAmount(p), stakeAfter1, "double-call: the SECOND claim credited 0 (pays exactly once)");

        // claim -> unsub -> claim variant: unsub does not re-arm pendingFlip; the post-unsub claim is a no-op.
        _deliverDay(_singleton(p), 0xDB1C02); // re-accrue
        assertEq(_pendingFlipOf(p), SLOT0_FLIP_PER_BUY, "re-accrued 100 for the claim->unsub->claim variant");
        uint256 stakeBefore2 = coinflip.coinflipAmount(p);
        game.claimAfkingFlip(_singleton(p)); // claim
        uint256 stakeAfterClaim2 = coinflip.coinflipAmount(p);
        assertEq(stakeAfterClaim2 - stakeBefore2, SLOT0_FLIP_PER_BUY * 1 ether, "claim credited the re-accrued FLIP once");
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, address(0)); // unsub (pendingFlip persists at 0)
        game.claimAfkingFlip(_singleton(p)); // re-claim after unsub
        assertEq(coinflip.coinflipAmount(p), stakeAfterClaim2, "claim->unsub->claim: the post-unsub re-claim credited 0 (idempotent)");
    }

    // =========================================================================
    // Repro 4 — the 4 finalize hooks each write the decay-applied streak BEFORE the slot delete/tombstone
    // =========================================================================

    /// @notice Hook (A) explicit cancel `subscribe(_, 0)`: the finalize (`_finalizeAfking` at
    ///         GameAfkingModule.sol:318) runs BEFORE `c.dailyQuantity = 0` (:319). After the cancel, a
    ///         QuestStreakBonusAwarded(amount==0) finalize event was emitted AND the slot is tombstoned
    ///         (dailyQuantity == 0) — the streak was handed back before the tombstone.
    function testFinalizeHookA_ExplicitCancelBeforeTombstone() public {
        address p = makeAddr("hookA");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xA0A0);

        vm.recordLogs();
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, address(0)); // explicit cancel
        // The finalize ran (event present) and the slot is tombstoned in place.
        _lastFinalizeStreakFor(p); // reverts if no finalize event fired before the tombstone
        assertEq(_dailyQtyOf(p), 0, "hook A: the slot is tombstoned (dailyQuantity == 0) AFTER the finalize handed the streak back");
    }

    /// @notice Hook (B) cancel-reclaim (load-bearing ordering): an in-set tombstone is reclaimed by the next
    ///         STAGE — `_finalizeAfking` (:912) runs BEFORE `delete _subOf[player]` (:915). After the reclaim,
    ///         the record is deleted (subscriberIndex == 0); the SubscriptionExpired reason-2 event confirms
    ///         the cancel-reclaim path executed (the finalize is in that branch, ahead of the delete).
    function testFinalizeHookB_CancelReclaimBeforeDelete() public {
        // 357-00b DROP (D-12 supersession): the v55-era setup tombstoned an UNGROUNDED sub
        // (subscribe-before-any-buy, no pending box) to drive the STAGE cancel-reclaim path. Under the
        // 357-00 D-12 gate (MustPurchaseToBeginAfking) an ungrounded sub can no longer be created — and
        // grounding p (fund-before-subscribe) stamps a pending box that the no-orphan guard then protects,
        // suppressing the reclaim branch. The finalize-before-delete invariant this proved is re-proven by
        // the GREEN hooks A (explicit-cancel-before-tombstone) and D (funding-kill-before-remove) — both of
        // which finalize ahead of the slot mutation. Re-proven GREEN by V56SubHardening (the D-12 gate) +
        // the surviving finalize hooks.
        vm.skip(true, "357-00b D-12 supersession: cannot tombstone an ungrounded sub; finalize-before-delete covered by hooks A/D + V56SubHardening");
        address p = makeAddr("hookB");
        address keep = makeAddr("hookB_keep");
        _grantSeat(p);
        _grantSeat(keep);
        _subscribeLootbox(p, 1);
        _subscribeLootbox(keep, 1);
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, address(0));
        assertGt(_subscriberIndexOf(p), 0, "p still in-set as a tombstone pre-reclaim");

        vm.recordLogs();
        _runStageNewDay(0xB0B0); // the STAGE reclaims the tombstone (finalize -> delete)
        _settleClean(0xB0B1);

        assertGt(_countExpired(p, 2), 0, "hook B: cancel-reclaim fired (SubscriptionExpired reason 2)");
        assertEq(_subscriberIndexOf(p), 0, "hook B: _subOf record deleted AFTER the finalize (removed from set)");
    }

    // Hook (C) pass-eviction crossing was DROPPED: the per-level validity horizon, the crossing
    // refresh/evict branch, and `_passHorizonOf` are all deleted — membership now ends only via cancel,
    // funding-skip kill (reason 1) — the AFKing Subscription Token's seat lock blocks exits-by-transfer — and a level crossing
    // is a non-event for an in-set sub. The property this hook stood for ("no eviction on a level crossing")
    // is proven directly by AfKingSubscription.t.sol's `testPasslessCoinHolderProcessedNoEviction`.

    /// @notice Hook (D) funding-kill + the funding-kill BOUNDARY (Pitfall 4). A NORMAL underfunded sub is
    ///         finalized (`_finalizeAfking` at :1010) BEFORE the tombstone + remove (:1011-1012). The
    ///         DegenerusQuests funding-kill guard keeps the streak when a valid mint landed no earlier than
    ///         yesterday (`lastValid + 1 >= currentDay`) and zeroes it when a full prior day was missed
    ///         (`lastValid <= currentDay - 2`). This asserts BOTH boundaries:
    ///           - KEPT: deliver up to yesterday, defund, kill on the next day -> finalize keeps the streak.
    ///           - ZEROED: defund, let >= 2 days pass with no valid mint, cancel -> finalize zeroes it.
    function testFinalizeHookD_FundingKillBoundaryKeptAndZeroed() public {
        // ---- KEPT boundary: lastValid == currentDay - 1 (delivered yesterday) ----
        address kept = makeAddr("hookD_kept");
        _grantSeat(kept);
        _fundPool(kept, 50 ether);
        _subscribeLootbox(kept, 1);
        _deliverDay(_singleton(kept), 0xD0D0);
        _deliverDay(_singleton(kept), 0xD0D1);
        _deliverDay(_singleton(kept), 0xD0D2); // a multi-day run with a real earned streak
        uint32 earnedSpan = _afkCoveredOf(kept) - _afkingStartOf(kept);
        assertGt(earnedSpan, 0, "kept: a real earned streak built (non-vacuous)");

        // Defund, then kill on the VERY NEXT day (lastValid == covered == currentDay - 1): the finalize KEEPS
        // the streak (no full prior funded day was missed).
        _drainAllFunding(kept);
        vm.recordLogs();
        _runStageNewDay(0xD0D3); // funding-kill on the next day -> finalize KEEPS
        _settleClean(0xD0D4);
        uint24 keptStreak = _lastFinalizeStreakFor(kept);
        assertGt(keptStreak, 0, "hook D KEPT: lastValid + 1 >= currentDay -> finalize kept the earned streak");
        assertEq(_subscriberIndexOf(kept), 0, "hook D KEPT: removed from set AFTER the finalize");

        // ---- ZEROED boundary: lastValid <= currentDay - 2 (a full prior funded day missed) ----
        address zeroed = makeAddr("hookD_zeroed");
        _grantSeat(zeroed);
        _fundPool(zeroed, 50 ether);
        _subscribeLootbox(zeroed, 1);
        _deliverDay(_singleton(zeroed), 0xD1D0);
        _deliverDay(_singleton(zeroed), 0xD1D1);
        _deliverDay(_singleton(zeroed), 0xD1D2);

        // Defund, then let >= 2 days pass with no delivery before re-subscribing + cancelling — the run
        // lapsed a full funded day with NO valid mint, so the finalize ZEROES the streak.
        _drainAllFunding(zeroed);
        _skipDaysNoDelivery(0xD1D3); // funding-kill out
        _skipDaysNoDelivery(0xD1D4);
        _skipDaysNoDelivery(0xD1D5);
        // Re-fund (grounds the re-sub's NEW-run cover-buy — D-12) before the post-gap re-subscribe; the
        // re-sub re-bases to base 0 (a full funded day was missed), so the immediate cancel still finalizes 0.
        _fundPool(zeroed, 50 ether);
        if (_subscriberIndexOf(zeroed) == 0) {
            _settleForfeit(zeroed); // the funding-kill left the forfeit gate set
            _subscribeLootbox(zeroed, 1);
        }
        vm.recordLogs();
        vm.prank(zeroed);
        game.subscribe(address(0), false, false, 0, address(0)); // explicit cancel finalize on a post-gap day
        uint24 zeroedStreak = _lastFinalizeStreakFor(zeroed);
        assertEq(zeroedStreak, 0, "hook D ZEROED: lastValid <= currentDay - 2 -> finalize zeroed the streak (decay)");
    }

    // =========================================================================
    // No-orphan arm — a pending-box sub is left ENTIRELY untouched by the STAGE
    // =========================================================================

    /// @notice The NO-ORPHAN guard (GameAfkingModule.sol:892): a sub with a pending unopened box
    ///         (`lastOpenedDay < lastAutoBoughtDay`) is left ENTIRELY untouched by a STAGE cycle — no reclaim,
    ///         no evict, no funding-kill, no re-stamp — so its paid-for box is never orphaned. Stamp a box
    ///         (do NOT open it), then run a STAGE: the sub stays in-set with its stamp markers byte-unchanged.
    function testNoOrphanPendingBoxSubUntouchedByStage() public {
        address p = makeAddr("orphan_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        // STAGE a buy but DO NOT open — the box is pending (lastOpenedDay < lastAutoBoughtDay).
        _runStageNewDay(0x0F0F);
        _settleClean(0x0F10);
        uint32 boughtBefore = _lastBoughtDayOf(p);
        uint32 openedBefore = _lastOpenedDayOf(p);
        assertGt(boughtBefore, 0, "non-vacuity: a box was stamped");
        assertTrue(openedBefore < boughtBefore, "the box is pending (lastOpenedDay < lastAutoBoughtDay)");
        uint256 idxBefore = _subscriberIndexOf(p);

        // Run a STAGE cycle WITHOUT opening the box: the no-orphan guard skips the sub entirely.
        vm.recordLogs();
        _runStageNewDay(0x0F11);
        _settleClean(0x0F12);

        // UNTOUCHED: the stamp markers are byte-identical, the sub stays in-set, no expiry event fired.
        assertEq(_lastBoughtDayOf(p), boughtBefore, "no-orphan: lastAutoBoughtDay untouched (no re-stamp)");
        assertEq(_lastOpenedDayOf(p), openedBefore, "no-orphan: lastOpenedDay untouched (the box still pending)");
        assertEq(_subscriberIndexOf(p), idxBefore, "no-orphan: the sub stays in-set (no reclaim/evict/funding-kill)");
        assertEq(_countExpiredAnyReason(p), 0, "no-orphan: no SubscriptionExpired fired for the pending-box sub");
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55SetMutationOpenE / V56AfkingGasMarginal)
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps each pending box + accrues), then
    ///      settle clean and OPEN every pending box (so the no-orphan guard does not skip the next day's buy).
    ///      Each delivered day advances the covered high-water and accrues 100 pendingFlip per in-set sub.
    ///      Uses a rich, distinct VRF word each call (a degenerate small word routes into a non-stamping
    ///      branch); the stage word and the clean word are kept distinct.
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        // Open the pending boxes (afking-first valve) so lastOpenedDay catches lastAutoBoughtDay.
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
        // Suppress the unused-param lint when callers pass a fixed set.
        who;
    }

    /// @dev Warp forward exactly ONE simulated day WITHOUT delivering a buy (settle the advance chain but do
    ///      not open / re-buy). Used to manufacture the decay gap. Re-funds nothing.
    function _skipDaysNoDelivery(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("skip", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("skipc", w))) | 1);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day: advance off the accumulating timestamp so the
    ///      simulated day reliably advances across a multi-day loop (the Foundry block.timestamp caching
    ///      quirk freezes a re-read `block.timestamp + 1 days` after the first warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Withdraw the sub's whole afking funding so the next STAGE buy is unfunded — the funding-kill
    ///      branch evicts the sub (finalize-then-tombstone), manufacturing a clean missed-funded-day gap.
    function _drainAllFunding(address who) internal {
        uint256 bal = game.afkingFundingOf(who);
        if (bal == 0) return;
        vm.prank(who);
        game.withdrawAfkingFunding(bal);
    }

    /// @dev Settle a funding-kill's seat forfeit test-side: clear the SEAT_ENCUMBERED
    ///      bit (155 of `mintPacked_`, storage slot 9) so a post-eviction re-subscribe
    ///      under test isn't blocked by the forfeit gate (SeatForfeited). The forfeit
    ///      flow itself (trapped seat -> reclaimSeat -> vault) is proven in
    ///      AfKingSeatToken; these streak tests only need the re-entry.
    function _settleForfeit(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(packed & ~(uint256(1) << 155)));
    }

    /// @dev Count the SubscriptionExpired(player, reason) events recorded since the last vm.recordLogs()
    ///      for `who` with the given reason (1 = AutoPause/funding-kill, 2 = cancel-reclaim). The
    ///      game-resident module emits via delegatecall, so the emitter is address(game).
    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            if (uint8(uint256(bytes32(logs[i].data))) == reason) count++;
        }
    }

    /// @dev Count SubscriptionExpired events for `who` of ANY reason (drains the recorded logs once).
    function _countExpiredAnyReason(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            count++;
        }
    }

    /// @dev The decay-applied streak DegenerusQuests.finalizeAfking wrote for `who` on its most recent
    ///      sub-ending finalize, read from the QuestStreakBonusAwarded event
    ///      (player indexed, uint16 amount, uint24 newStreak, uint24 currentDay). The finalize emits with
    ///      amount == 0 and newStreak == the decay-applied final streak. Requires vm.recordLogs() first.
    ///      currentDay is uint24 at c4d48008 (DegenerusQuests:112-117), not uint32 — the topic-0 hash
    ///      diverges if the signature string mis-widths it.
    function _lastFinalizeStreakFor(address who) internal returns (uint24) {
        bytes32 sig = keccak256("QuestStreakBonusAwarded(address,uint16,uint24,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint24 found;
        bool any;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            (uint16 amount, uint24 newStreak, ) = abi.decode(logs[i].data, (uint16, uint24, uint24));
            if (amount == 0) {
                found = newStreak;
                any = true;
            }
        }
        require(any, "no finalize event for who");
        return found;
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _pair(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    // ---- Sub-slot reads (_subOf slot 52 + the v56 offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _afkCoveredOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKCOVERED, 24));
    }

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24));
    }

    function _affiliateBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFFBASE, 32));
    }

    function _pendingFlipOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGFLIP, 24));
    }

    function _streakBaseOf(address who) internal view returns (uint16) {
        return uint16(_subField(who, OFF_STREAKLATCH, 16));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }
}
