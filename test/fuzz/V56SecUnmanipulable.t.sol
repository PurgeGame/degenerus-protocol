// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @title Subscription churn accounting and streak regressions
/// @notice Claim/cancel/upsert receipts are measured from wallet, claimable and next-day stake
///      deltas, including implicit payouts. Paid plus owed rewards reconcile to actual funded
///      deliveries; each affiliate recipient is checked separately. Honest and churn controls
///      share a timeline, while random lootbox returns and later coinflip outcomes are outside
///      the subscription-principal comparison. Other cases cover streak handback, the
///      affiliate-only drain, claim idempotency and expiry.
/// @dev Uses real funded subscriptions and production buy/open/claim/cancel paths. Rewards derive
///      from the checkpoint, so every state change settles both sides first; the lens mirrors the
///      owed amounts. Only test fixtures grant membership seats.
contract V56SecUnmanipulable is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf_g3120(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    /// @dev Wallet IDs of `a`, registering any that hold none.
    function _aids(address[] memory a) internal returns (uint32[] memory ids) {
        ids = new uint32[](a.length);
        for (uint256 i; i < a.length; ++i) ids[i] = _aid(a[i]);
    }

    /// @dev Whole FLIP a one-unit box-mode member earns per credited day.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    DegenerusGameLens private lens;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = unfunded, reason 2 = seized.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // Repro 1 — affiliate re-claim churn (automatic payments conserve earned principal)
    // =========================================================================

    /// @notice Compare actual paid-plus-owed obligations on one timeline. Cancellation pays
    ///      both sides; re-subscribing on that day must neither buy nor pay twice.
    function testAffiliateReClaimChurnEqualsHonestContinuous() public {
        ChurnLedger memory honest = _newChurnLedger("aff_honest");
        ChurnLedger memory churn = _newChurnLedger("aff_churn");
        _observeChurnAction(honest, 0);
        _observeChurnAction(churn, 0);
        for (uint256 d; d < 3; ++d) {
            _deliverLedgerDay(honest, churn, uint256(keccak256(abi.encode("aff", d))) | 1);
            assertGt(_owed(churn.player).owedAffiliateBase, 0, "cancel must settle an earned affiliate obligation");
            _observeChurnAction(churn, 2);
            _observeChurnAction(churn, 1); // a cancelled member has nothing left to claim
            _observeChurnAction(churn, 3); // duplicate sub IDs cannot reclaim the settled base
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

    /// @notice The base drain entrypoint is AFFILIATE-only: a non-AFFILIATE caller can never settle
    ///         (and thus never redirect) a sub's owed base. (`drainAffiliateBases` is reachable in
    ///         production only through the DegenerusAffiliate `claim` path; a direct non-affiliate
    ///         call reverts before touching the lane.)
    function testAffiliateBaseDrainAffiliateOnly() public {
        address p = makeAddr("aff_gate");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xA66A11);
        uint256 owedBefore = _owed(p).owedAffiliateBase;
        uint32 cpBefore = _checkpointDayOf(p);
        assertGt(owedBefore, 0, "non-vacuity: base owed");

        uint32 subscriberId = game.walletIdOf_g3120(p);
        vm.prank(makeAddr("not_affiliate"));
        vm.expectRevert(bytes4(keccak256("NotApproved()")));
        game.drainAffiliateBases(subscriberId, 0);
        assertEq(_owed(p).owedAffiliateBase, owedBefore, "rejected non-affiliate drain left the base owed");
        assertEq(_checkpointDayOf(p), cpBefore, "and the checkpoint unmoved");
    }

    // =========================================================================
    // Repro 2 — streak gap dodge (compute-on-read; advances only on delivered days)
    // =========================================================================

    /// @notice A delayed RNG session cannot erase or manufacture funded streak days: the endpoint (and
    ///         so the derived streak) moves only when a pass completes.
    function testStreakSurvivesDelayedSessionAndOrderedCatchup() public {
        address p = makeAddr("decay_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xDECA01);
        _deliverDay(_singleton(p), 0xDECA02);
        _t += 1 days;
        vm.warp(_t);
        for (uint256 i; i < 64 && !game.rngLocked(); ++i) game.mineRun(0);
        assertTrue(game.rngLocked());
        DegenerusGameLens.SubFull memory before = _owed(p);
        _t += 3 days;
        vm.warp(_t);
        DegenerusGameLens.SubFull memory waited = _owed(p);
        assertEq(waited.endpoint, before.endpoint, "wall time cannot move the endpoint");
        assertEq(waited.effectiveStreak, before.effectiveStreak, "wall time cannot earn funded days");
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("RngLocked()"));
        game.subscribe(0, false, 0, 0);
        _settleClean(0xDECA03);
        _finishSubscriptionWindow();
        DegenerusGameLens.SubFull memory caught = _owed(p);
        assertGt(caught.effectiveStreak, before.effectiveStreak, "catchup delivers the missed logical days");
        vm.recordLogs();
        vm.prank(p);
        game.subscribe(0, false, 0, 0);
        assertEq(_lastFinalizeStreakFor(p), caught.effectiveStreak, "the derived streak is what is handed back");
    }

    /// @notice Kill-then-resume re-bases the run: an unfunded expiry finalizes the old run (handing its streak
    ///         to the manual system, where the missed post-kill days decay it), and the post-gap re-subscribe
    ///         starts a NEW run — run start at the resume day, checkpoint streak = the (decayed) manual
    ///         snapshot — so the post-gap window credits NO stale-span days.
    function testGapResetOnResumeRebasesTheRun() public {
        address p = makeAddr("gapresume_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);

        _deliverDay(_singleton(p), 0x6A9001);
        _deliverDay(_singleton(p), 0x6A9002);
        _deliverDay(_singleton(p), 0x6A9003);
        uint32 startBefore = _owed(p).runStartDay;
        uint256 streakFirst = _owed(p).effectiveStreak;
        assertGt(streakFirst, 2, "first window: the streak advanced");

        // Gap: DEFUND so the sub expires, then several days with NO delivery.
        _drainAllFunding(p);
        _skipDaysNoDelivery(0x6A9004);
        _skipDaysNoDelivery(0x6A9005);
        _skipDaysNoDelivery(0x6A9006);
        assertEq(_subscriberIndexOf(p), 0, "the unfunded run expired");

        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        DegenerusGameLens.SubFull memory resumed = _owed(p);
        assertGt(resumed.runStartDay, startBefore, "gap-resume: the run re-based to the resume day");
        assertEq(resumed.checkpointStreak, 0, "gap-resume: the streak base reset to 0 (no stale-span credit)");
        assertEq(resumed.owedFlip, 0, "nothing owed at signup");
        _deliverDay(_singleton(p), 0x6A9007);
        assertLe(_owed(p).effectiveStreak, 1, "post-resume window credits only the delivered day since resume");
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
            if (act & 4 != 0) _observeChurnAction(churn, 0); // an active upsert settles both sides first
            if (act & 8 != 0) _observeChurnAction(churn, 3);
            _assertChurnLedger(honest);
            _assertChurnLedger(churn);
            if (_dailyQtyOf(churn.player) != 0) {
                DegenerusGameLens.SubFull memory f = _owed(churn.player);
                assertLe(f.checkpointDay, f.endpoint, "checkpoint cannot pass the endpoint");
                assertLe(f.endpoint, game.currentDayView_g542950(), "streak cannot cover a future day");
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

    /// @dev 0 subscribe/upsert, 1 player claim, 2 cancel, 3 affiliate claim with repeated IDs; each
    ///      settles both sides. Exact recipient deltas also reject payment to the relayer.
    function _observeChurnAction(ChurnLedger memory ledger, uint8 action) private {
        uint256[5] memory beforeAssets;
        for (uint256 i; i < 5; ++i) {
            address recipient = _ledgerRecipient(ledger, i);
            beforeAssets[i] = _flipAssets(recipient);
        }
        uint256 fundingBefore = game.afkingFundingOf(ledger.player);
        uint256 price = game.mintPrice();
        // Every action on a live run settles both sides first; a non-member has nothing owed.
        DegenerusGameLens.SubFull memory owed = _owed(ledger.player);
        uint256 playerOwed = owed.owedFlip;
        uint256 base = owed.owedAffiliateBase;
        vm.recordLogs();
        if (action == 0 || action == 2) {
            uint256 seat = _grantSeat(ledger.player);
            vm.prank(ledger.player);
            game.subscribe(0, false, action == 0 ? 1 : 0, seat);
        } else if (action == 1) {
            vm.prank(ledger.relayer);
            game.claimAfkingFlip(_aids(_pair(ledger.player, ledger.player)));
        } else {
            vm.prank(ledger.relayer);
            affiliate.claim(_aids(_pair(ledger.player, ledger.player)));
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[5] memory expected;
        expected[0] = playerOwed;
        expected[2] = base * 20 / 100;
        expected[3] = base * 5 / 100;
        expected[1] = base - expected[2] - expected[3];
        for (uint256 i; i < 5; ++i) {
            uint256 received = _flipAssets(_ledgerRecipient(ledger, i)) - beforeAssets[i];
            assertEq(received, expected[i], "all automatic/explicit payments must reach the exact entitled recipient");
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
        bytes32 delivered = keccak256("AfkingDelivered(uint32,uint256)");
        bytes32 spent = keccak256("ClaimableSpent(uint32,uint256,uint256,uint8,uint256)");
        uint256 claimableLeg;
        uint256 cost;
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || uint32(uint256(logs[i].topics[1])) != game.walletIdOf_g3120(ledger.player)) continue;
            if (logs[i].topics[0] == spent) {
                (uint256 leg,,,) = abi.decode(logs[i].data, (uint256, uint256, uint8, uint256));
                claimableLeg += leg;
            } else if (logs[i].topics[0] == delivered) {
                uint256 packed = abi.decode(logs[i].data, (uint256));
                uint256 day = uint24(packed >> 128);
                assertGt(day, ledger.lastDay, "a delivered buy cannot repeat an already-funded day");
                ledger.lastDay = day;
                cost += uint128(packed);
                ++count;
            }
        }
        assertEq(fundingBefore - game.afkingFundingOf(ledger.player) + claimableLeg, cost,
            "delivery ledger is backed by actual prepaid and claimable debits");
        assertEq(cost, count * price, "one-unit lootbox subscription buys exactly one priced unit per delivery");
        ledger.delivered += count;
        ledger.spent += cost;
        ledger.affiliateEarned += cost * 1000 / price * 7 / 100;
    }

    function _assertChurnLedger(ChurnLedger memory ledger) private view {
        DegenerusGameLens.SubFull memory owed = _owed(ledger.player);
        assertEq(ledger.playerPaid + owed.owedFlip,
            ledger.delivered * SLOT0_FLIP_PER_BUY, "paid plus owed covers every delivered day's player reward");
        assertEq(ledger.affiliatePaid + owed.owedAffiliateBase,
            ledger.affiliateEarned, "paid plus owed covers every delivered day's upline reward");
    }

    // =========================================================================
    // Repro 3 — claim double-claim idempotency (pays EXACTLY once)
    // =========================================================================

    /// @notice claimAfkingFlip pays the elapsed days EXACTLY ONCE. Settlement moves the checkpoint to
    ///         the endpoint before anything is credited, so a second claim in the same block finds
    ///         nothing; a cancel after a claim finds nothing either.
    function testDoubleClaimPaysExactlyOnce() public {
        address p = makeAddr("dbl_p");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1); // signup buys and credits nothing
        _deliverDay(_singleton(p), 0xDB1C01); // the next day's pass is the first credited day
        assertEq(_owed(p).owedFlip, SLOT0_FLIP_PER_BUY, "non-vacuity: one delivered day owes 100 whole FLIP");

        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), SLOT0_FLIP_PER_BUY, "first claim credited exactly the elapsed day");
        assertEq(_owed(p).owedFlip, 0, "nothing owed after the claim");

        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), 0, "double-call: the SECOND claim credited 0 (pays exactly once)");

        // claim -> cancel -> claim variant: the cancel finds nothing owed and the re-claim finds no member.
        _deliverDay(_singleton(p), 0xDB1C02);
        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), SLOT0_FLIP_PER_BUY, "claim credited the new day once");
        vm.recordLogs();
        vm.prank(p);
        game.subscribe(0, false, 0, 0);
        assertEq(_flipClaimed(p), 0, "the cancel settled nothing more");
        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), 0, "claim->cancel->claim: the post-cancel re-claim credits 0");
    }

    // =========================================================================
    // Repro 4 — the finalize hooks hand the streak back BEFORE the record is removed
    // =========================================================================

    /// @notice Hook (A) explicit cancel `subscribe(_, 0)`: the finalize runs, and the record is removed
    ///         at once (no tombstone), after the streak was handed back.
    function testFinalizeHookA_ExplicitCancelRemovesAfterFinalize() public {
        address p = makeAddr("hookA");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xA0A0);

        vm.recordLogs();
        vm.prank(p);
        game.subscribe(0, false, 0, 0); // explicit cancel
        _lastFinalizeStreakFor(p); // reverts if no finalize event fired
        assertEq(_subscriberIndexOf(p), 0, "hook A: the record is gone after the finalize handed the streak back");
    }

    // Hook (C) pass-eviction crossing was DROPPED: the per-level validity horizon, the crossing
    // refresh/evict branch, and `_passHorizonOf` are all deleted — membership now ends only via cancel,
    // funding-skip kill (reason 1) — the AFKing Subscription Token's seat lock blocks exits-by-transfer — and a level crossing
    // is a non-event for an in-set sub. The property this hook stood for ("no eviction on a level crossing")
    // is proven directly by AfKingSubscription.t.sol's `testPasslessCoinHolderProcessedNoEviction`.

    /// @notice Hook (D) unfunded expiry + its BOUNDARY. A NORMAL underfunded sub is finalized
    ///         (`_finalizeAfking`) BEFORE it is removed. The
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
        assertGt(_owed(kept).effectiveStreak, 0, "kept: a real earned streak built (non-vacuous)");

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
        // The re-sub re-bases to the decayed manual streak (a full funded day was missed), so the
        // immediate cancel still finalizes 0.
        _fundPool(zeroed, 50 ether);
        assertEq(_subscriberIndexOf(zeroed), 0, "the unfunded run expired");
        _subscribeLootbox(zeroed, 1);
        vm.recordLogs();
        vm.prank(zeroed);
        game.subscribe(0, false, 0, 0); // explicit cancel finalize on a post-gap day
        uint24 zeroedStreak = _lastFinalizeStreakFor(zeroed);
        assertEq(zeroedStreak, 0, "hook D ZEROED: lastValid <= currentDay - 2 -> finalize zeroed the streak (decay)");
    }

    /// @notice A paid stamp survives a delay and funding withdrawal; the engine opens it
    /// before the next pass can evict the now-unfunded member.
    function testPendingBoxOpensBeforeNextDayFundingEviction() public {
        address p = makeAddr("orphan_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _t += 1 days;
        vm.warp(_t);
        for (uint256 i; i < 64 && !game.rngLocked(); ++i) game.mineRun(0);
        assertTrue(game.rngLocked());
        uint32 id = game.walletIdOf_g3120(p);
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), id), "the day's box is paid and pending");
        _drainAllFunding(p);
        _t += 1 days;
        vm.warp(_t);
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), id), "the paid box survives the delay");
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("RngLocked()"));
        game.subscribe(0, true, 1, 0);
        vm.recordLogs();
        _settleClean(0x0F10);
        _finishSubscriptionWindow();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool opened;
        bool evicted;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || uint32(uint256(logs[i].topics[1])) != id) continue;
            if (logs[i].topics[0] == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")) opened = true;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG) {
                assertTrue(opened, "paid box must open before eviction");
                evicted = true;
            }
        }
        assertTrue(opened && evicted, "both real lifecycle steps happened");
        assertEq(_subscriberIndexOf(p), 0);
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55SetMutationOpenE / V56AfkingGasMarginal)
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps each pending box + accrues), then
    ///      settle clean and OPEN every pending box before the next day's preparation.
    ///      Each delivered day advances the endpoint and owes 100 whole FLIP per in-set box sub.
    ///      Uses a rich, distinct VRF word each call (a degenerate small word routes into a non-stamping
    ///      branch); the stage word and the clean word are kept distinct.
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        // Mine any remaining box stages so every stamped box is opened.
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
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
        _finishReadConsumers();
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineRun(0);
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
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
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest
    }

    function _owed(address who) internal view returns (DegenerusGameLens.SubFull memory) {
        return lens.subInfoFullById(address(game), game.walletIdOf_g3120(who));
    }

    /// @dev Whole FLIP the AfkingFlipClaimed events recorded since the last vm.recordLogs() paid `who`.
    function _flipClaimed(address who) internal returns (uint256 total) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AfkingFlipClaimed(uint32,uint256)");
        uint32 id = game.walletIdOf_g3120(who);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            total += abi.decode(logs[i].data, (uint256));
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Withdraw the sub's whole afking funding so the next STAGE buy is unfunded — the funding-kill
    ///      branch expires the sub (finalize-then-remove), manufacturing a clean missed-funded-day gap.
    function _drainAllFunding(address who) internal {
        uint256 bal = game.afkingFundingOf(who);
        if (bal == 0) return;
        vm.prank(who);
        game.withdrawAfkingFunding(0, bal);
    }

    /// @dev Count the SubscriptionExpired(player, reason) events recorded since the last vm.recordLogs()
    ///      for `who` with the given reason (1 = AutoPause/funding-kill, 2 = cancel-reclaim). The
    ///      game-resident module emits via delegatecall, so the emitter is address(game).
    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf_g3120(who)) continue;
            if (uint8(uint256(bytes32(logs[i].data))) == reason) count++;
        }
    }

    /// @dev Count SubscriptionExpired events for `who` of ANY reason (drains the recorded logs once).
    function _countExpiredAnyReason(address who) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf_g3120(who)) continue;
            count++;
        }
    }

    /// @dev The decay-applied streak DegenerusQuests.finalizeAfking wrote for `who` on its most recent
    ///      sub-ending finalize, read from the QuestStreakBonusAwarded event
    ///      (player ID indexed, uint16 amount, uint24 newStreak, uint24 currentDay). The finalize emits with
    ///      amount == 0 and newStreak == the decay-applied final streak. Requires vm.recordLogs() first.
    ///      currentDay is uint24 at c4d48008 (DegenerusQuests:112-117), not uint32 — the topic-0 hash
    ///      diverges if the signature string mis-widths it.
    function _lastFinalizeStreakFor(address who) internal returns (uint24) {
        bytes32 sig = keccak256("QuestStreakBonusAwarded(uint32,uint16,uint24,uint24)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint24 found;
        bool any;
        uint32 whoId = game.walletIdOf_g3120(who);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != whoId) continue;
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

    // ---- Lane reads ----

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(GameSlotKeys.subQuantity(address(game), game.walletIdOf_g3120(who)));
    }

    /// @dev `who`'s set position + 1; 0 = not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
    }

    function _checkpointDayOf(address who) internal view returns (uint32) {
        (uint256 lane,) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
        return uint32((lane >> 46) & ((uint256(1) << 22) - 1));
    }
}
