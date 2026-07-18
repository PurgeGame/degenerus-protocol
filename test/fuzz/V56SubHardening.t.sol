// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @title V56SubHardening -- the D-14 positive proofs for the 357-00 subscribe-hardening gates
///        (D-11 coin-required / D-12 purchase-grounded / D-13 VAULT/sDGNRS bootstrap exemption) and the
///        F-356-01 drainAffiliateBase Game dispatch-stub reachability. Run against the re-frozen audit
///        subject HEAD' = ac5f1e033a785d18a9f0b89b7de5d05268431dbd (the sole .sol commit of phase 357).
///
/// @notice The 357-00 gates as built (GameAfkingModule.subscribe, the UPSERT branch), post the
///         AFKing Subscription Token credential swap (sub <=> coin: `Sub.validThroughLevel` / `_passHorizonOf` /
///         `NoPass()` / `SubscriptionExtendedFree` all DELETED from the module):
///   - D-11 (NoCoin, :419): `if (!exemptSub && ISeatToken(AFKING_SUB_TOKEN).balanceOf(subscriber) == 0) revert
///     NoCoin();` — a single balanceOf staticcall, checked at subscribe ONLY. Deity confers nothing for
///     afking gating anymore (a deity holder without a coin still reverts NoCoin); any seated (>= 1 coin)
///     subscriber clears it regardless of level.
///   - D-12 (MustPurchaseToBeginAfking, :561): in the NEW-run leg (`!wasActive`), when the subscriber is
///     not grounded on a real purchase — neither `done[0]` (manual slot-0 today) NOR a funded in-tx
///     cover-buy executes — the start reverts. VAULT/sDGNRS take the `else if (exemptSub)` base-0
///     bootstrap branch instead of reverting.
///   - D-13 (exemptSub, :410-411): `subscriber == ContractAddresses.VAULT || subscriber ==
///     ContractAddresses.SDGNRS` short-circuits BOTH gates, keyed on the un-spoofable resolved
///     subscriber identity. Load-bearing for the construction-time VAULT/sDGNRS self-subscribe, which
///     predates the coin's deploy (the coin seeds them 999/1 on construction, after they have already
///     self-subscribed through this identity carve).
///   - Level-crossing membership eviction is GONE: a sub is never evicted by a level change. Membership
///     ends only via cancel or funding-skip kill (SubscriptionExpired reason 1); the coin's seat lock
///     blocks an active sub's last-coin transfer (SeatInUse) until manual unsub/eviction. The STAGE runs a
///     seated sub through arbitrary level changes untouched.
///
/// @notice F-356-01 (drainAffiliateBase Game dispatch stub, DegenerusGame.sol:428): the guard-less
///   delegatecall to GAME_AFKING_MODULE.drainAffiliateBase (mirrors claimAfkingFlip), `_revertDelegate`
///   on failure, `data.length == 0` guard, `abi.decode(data,(uint256))` return tail (mirrors
///   runDecimatorJackpot). The module impl owns the AFFILIATE-only access gate
///   (GameAfkingModule.sol:1328 `if (msg.sender != ContractAddresses.AFFILIATE) revert NotApproved()`),
///   which under delegatecall sees `msg.sender` as the caller of the Game stub. So the affiliate path
///   (msg.sender == AFFILIATE) drains-and-zeroes; any other caller reverts NotApproved().
///
/// @dev Copies the V56SecUnmanipulable harness VERBATIM for the delivery helpers + the funded/unfunded
///   pool helpers, with the Sub-slot offset block RE-DERIVED for the post-coin-gate packed layout
///   (`validThroughLevel` deleted from the struct — every field at/after the old byte-1 slot shifts down
///   3 bytes) and a `_grantSeat`-driven credential poke replacing the deity/finite-pass/validThroughLevel
///   pokes. Test-only: ZERO contracts/*.sol mutation.
contract V56SubHardening is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the Sub-slot offset block (post-coin-gate layout;
    // validThroughLevel deleted, every later field shifted down 3 bytes)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 53;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // mapping(address => uint256) _subscriberIndex (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 9;        // mintPacked_ mapping root (deity bit @ 184)

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
    uint256 private constant OFF_STREAKLATCH = 26;    // uint16 subStreakLatch       (bytes 26..27)

    uint256 private constant DEITY_SHIFT = 184;       // HAS_DEITY_PASS_SHIFT in mintPacked_ (bounty-eligibility tier only; confers nothing for afking gating)

    /// @dev The game `level` lives in slot 0 at byte 12 (uint24) — poked up to drive the level-crossing
    ///      membership-survival proof (the fixture level does not advance organically).
    uint256 private constant LEVEL_OFF = 12;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = funding-skip kill; reason 2 =
    ///      cancel-tombstone reclaim. Neither is level-crossing related anymore.
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
    // D-11 — coin-required subscribe (NoCoin on the UPSERT branch)
    // =========================================================================

    /// @notice D-11 NEGATIVE: an EOA holding NO AFKing Subscription Token reverts NoCoin() on an UPSERT subscribe
    ///         (dailyQuantity >= 1) — the sole afking credential (sub <=> coin), checked with a single
    ///         balanceOf staticcall at subscribe. NoCoin fires ahead of the D-12 grounding gate, so the
    ///         EOA is funded to isolate the credential failure.
    function testD11CoinlessEoaRevertsNoCoin() public {
        address p = makeAddr("d11_nocoin");
        _fundPool(p, 50 ether);       // funded, so the revert can ONLY be NoCoin (not MustPurchase)
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("NoCoin()"));
        game.subscribe(address(0), false, false, 1, address(0));
        assertEq(_subscriberIndexOf(p), 0, "D-11: the coinless sub was never created");
    }

    /// @notice D-11 POSITIVE: an EOA holding >= 1 AFKing Subscription Token (granted via `_grantSeat`, no pass anywhere
    ///         — the pass/horizon machinery is deleted) clears D-11 and subscribes successfully (funded so
    ///         D-12 is also satisfied). The successor of the old finite-pass-covers-the-level proof: the
    ///         coin gate has no level dependence at all.
    function testD11SeatedEoaSubscribes() public {
        address p = makeAddr("d11_seated");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, address(0)); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-11: seated sub created");
    }

    /// @notice D-11 (deity confers nothing for afking gating): a deity holder WITHOUT an AFKing Subscription Token still
    ///         reverts NoCoin() — the successor of the old deity-sentinel-bypass proof. Deity is a
    ///         bounty-eligibility tier only now; it has no bearing on the afking credential.
    function testD11DeityHolderWithoutCoinRevertsNoCoin() public {
        address p = makeAddr("d11_deity_nocoin");
        _grantDeityPass(p);           // deity bit set — confers nothing for the coin gate
        _fundPool(p, 50 ether);       // funded, so the revert can ONLY be NoCoin (not MustPurchase)
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("NoCoin()"));
        game.subscribe(address(0), false, false, 1, address(0));
        assertEq(_subscriberIndexOf(p), 0, "D-11: a deity holder without a coin is still rejected (NoCoin)");
    }

    // =========================================================================
    // D-12 — purchase-grounded subscribe (MustPurchaseToBeginAfking on the unfunded NEW run)
    // =========================================================================

    /// @notice D-12 NEGATIVE: a seated (coin-holding, so D-11 is cleared) but UNFUNDED EOA reverts
    ///         MustPurchaseToBeginAfking() on a NEW-run UPSERT subscribe — neither bought-today (`done[0]`)
    ///         nor a funded in-tx cover-buy, so the start would free-ride the advance gate. The revert is
    ///         the D-12 leg (the unfunded NEW-run else branch), NOT NoCoin (the seat clears D-11),
    ///         isolating the grounding failure.
    function testD12UnfundedEoaRevertsMustPurchase() public {
        address p = makeAddr("d12_unfunded");
        _grantSeat(p);                // clears D-11; isolates the D-12 grounding failure
        // NO _fundPool: afkingFunding[p] == 0 -> the cover-buy is unfunded -> the NEW-run start reverts.
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("MustPurchaseToBeginAfking()"));
        game.subscribe(address(0), false, false, 1, address(0));
        assertEq(_subscriberIndexOf(p), 0, "D-12: the unfunded sub was never created");
    }

    /// @notice D-12 POSITIVE (funded): a seated EOA pre-funded so the in-tx cover-buy executes subscribes
    ///         successfully (the funded NEW-run leg keeps the snapshot + delivers the buy). No MustPurchase
    ///         revert.
    function testD12FundedEoaSubscribes() public {
        address p = makeAddr("d12_funded");
        _grantSeat(p);
        _fundPool(p, 50 ether);       // funds the cover-buy -> grounded NEW run
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, address(0)); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-12: funded sub created");
        assertEq(_lastBoughtDayOf(p), uint32(game.currentDayView()), "D-12: the funded cover-buy delivered today");
    }

    /// @notice D-12 POSITIVE (already-bought-today re-sub): an ACTIVE sub re-subscribe (`wasActive`) skips
    ///         the NEW-run grounding gate entirely — D-12 fires only on the NEW-run leg. A funded sub that
    ///         already delivered today re-subscribes with no MustPurchase revert (the no-orphan / bought-
    ///         today skip preserves the run). Proves D-12 never reverts a genuinely-grounded re-subscribe.
    function testD12ActiveResubAlreadyGroundedNoRevert() public {
        address p = makeAddr("d12_resub");
        _grantSeat(p);
        _fundPool(p, 80 ether);       // fund BEFORE subscribe so the NEW-run cover-buy is grounded (D-12)
        _subscribeLootbox(p, 1);      // grounded NEW run (seat clears D-11, funded clears D-12)
        _deliverDay(_singleton(p), 0xD12E50); // an active funded run; box opened, bought today
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: the sub is active");
        // Re-subscribe the active sub (wasActive == true) — the NEW-run D-12 gate is not on this path.
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, address(0)); // MUST NOT revert (grounded re-sub)
        assertGt(_subscriberIndexOf(p), 0, "D-12: grounded re-sub stays active (no MustPurchase revert)");
    }

    // =========================================================================
    // D-13 — VAULT / sDGNRS bootstrap exemption (no coin + unfunded still subscribes)
    // =========================================================================

    /// @notice D-13 (VAULT exempt): VAULT subscribes with NO AFKing Subscription Token and UNFUNDED and is NOT reverted
    ///         by either gate — the `exemptSub` short-circuit (D-11 via `!exemptSub`, D-12 via the
    ///         `else if (exemptSub)` base-0 bootstrap). Load-bearing: VAULT self-subscribes at
    ///         construction, BEFORE the coin exists in the deploy order. Self-subscribe shape
    ///         (`subscribe(address(this), ...)`) keyed on the resolved identity.
    function testD13VaultExemptSubscribesNoCoinUnfunded() public {
        vm.prank(ContractAddresses.VAULT);
        game.subscribe(ContractAddresses.VAULT, true, false, 1, address(0)); // no coin, unfunded
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "D-13: VAULT exempt subscribe succeeded (no NoCoin / no MustPurchase)");
    }

    /// @notice D-13 (sDGNRS exempt): sDGNRS subscribes with NO AFKing Subscription Token and UNFUNDED and is NOT
    ///         reverted — the same pinned-identity exemption. Both protocol self-subscribers bootstrap at
    ///         construction with no coin + no funds (the coin deploys LAST and seeds them 999/1
    ///         afterward); the gates MUST carve them out or deploy breaks.
    function testD13SdgnrsExemptSubscribesNoCoinUnfunded() public {
        vm.prank(ContractAddresses.SDGNRS);
        game.subscribe(ContractAddresses.SDGNRS, true, false, 1, address(0)); // no coin, unfunded
        assertGt(_subscriberIndexOf(ContractAddresses.SDGNRS), 0, "D-13: sDGNRS exempt subscribe succeeded (no NoCoin / no MustPurchase)");
    }

    // =========================================================================
    // Crossing eviction SUPERSEDED — a seated sub survives level changes / STAGE
    // processing without eviction. The pass/horizon crossing gate (the per-iter
    // `currentLevel > sub.validThroughLevel` re-read that used to refresh-or-evict)
    // is DELETED along with `Sub.validThroughLevel` / `_passHorizonOf`. Membership
    // is no longer level-dependent at all: it ends only via cancel, funding-skip
    // kill (SubscriptionExpired reason 1); the coin's seat lock blocks an active sub's last-coin transfer.
    // =========================================================================

    /// @notice A seated (coin-holding) sub is carried through an arbitrary level change across the STAGE
    ///         with NO eviction: still in the set, dailyQuantity intact, no SubscriptionExpired of any
    ///         reason. Successor of the old outgrown-pass eviction proof — a level crossing is now a
    ///         non-event for subscription membership.
    function testSeatedSubSurvivesLevelCrossingNoEviction() public {
        address p = makeAddr("crossing_survives");
        _grantSeat(p);                 // the coin is the sole credential; no pass anywhere
        _fundPool(p, 50 ether);        // fund BEFORE subscribe so the grounded NEW run is created (D-12)
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xC10551); // an active afking run; box opened (no pending-box skip)
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: sub active before the crossing");

        vm.recordLogs();
        _settleGame(uint256(keccak256("cross_pre")) | 1);
        _t += 1 days;
        vm.warp(_t);
        _setLevel(10);                 // poke the level up across a fresh-day STAGE pass
        _settleGame(uint256(keccak256("cross_go")) | 1); // STAGE runs -> no eviction branch exists anymore

        assertEq(_countExpired(p, 1), 0, "crossing: no funding-skip kill fired (the sub stayed funded)");
        assertEq(_countExpired(p, 2), 0, "crossing: no cancel-tombstone reclaim fired (never cancelled)");
        assertGt(_subscriberIndexOf(p), 0, "crossing: the seated sub was NOT evicted by the level change");
        assertGt(_dailyQtyOf(p), 0, "crossing: dailyQuantity preserved across the crossing");
    }

    // =========================================================================
    // CHURN-IDEMPOTENCY (HEAD''' = 7b0b2a0b) — the NEW-run subscribe per-day slot-0
    // guard: subscribe -> funded cover-buy -> cancel -> subscribe (same day) accrues
    // the flat per-day slot-0 FLIP (pendingFlip) EXACTLY ONCE, not once-per-cycle.
    // The cancel branch tombstones in place (dailyQuantity = 0, record kept), so the
    // lastAutoBoughtDay stamp survives the unsub; the re-subscribe re-enters the NEW
    // run (wasActive == false) but now takes the new `else if (s.lastAutoBoughtDay ==
    // uint24(today))` guard (:451) — keep the snapshot, skip a SECOND cover-buy, no
    // slot-0 re-accrual. Mirrors the active-sub re-subscribe guard at :395.
    // =========================================================================

    /// @notice CHURN-IDEMPOTENCY: a seated + funded EOA subscribes (a grounded NEW run whose funded
    ///         cover-buy stamps `lastAutoBoughtDay = today` and accrues the flat per-day slot-0 FLIP into
    ///         `pendingFlip` ONCE), then churns subscribe(dailyQuantity 0) [cancel] -> subscribe N times
    ///         in the SAME day. After every same-day churn cycle `pendingFlip` is UNCHANGED — the per-day
    ///         flat slot-0 reward is accrued EXACTLY ONCE, not N×. Pre-HEAD''' the NEW-run cover-buy guarded
    ///         only on the manual `done[0]` (which an afking buy never sets), so each re-subscribe re-ran the
    ///         cover-buy and re-accrued the flat reward; the HEAD''' guard (`s.lastAutoBoughtDay ==
    ///         uint24(today)`) closes that. Seated (clears D-11; the coin persists unspent across cancel/
    ///         re-subscribe cycles) + funded (grounds D-12) so the churn loop actually reaches the cover-buy
    ///         on the FIRST subscribe.
    function testChurnSameDayAccruesSlot0Once() public {
        address p = makeAddr("churn_idempotency");
        _grantSeat(p);                 // clears D-11 for every cycle (the coin is never spent by subscribe)
        _fundPool(p, 200 ether);       // funds the FIRST cover-buy (grounds D-12) + leaves headroom

        // FIRST subscribe — a grounded NEW run; the funded cover-buy stamps lastAutoBoughtDay = today and
        // accrues the flat slot-0 FLIP into pendingFlip ONCE.
        _subscribeLootbox(p, 1);
        uint32 today = uint32(game.currentDayView());
        assertEq(_lastBoughtDayOf(p), today, "non-vacuity: the first funded cover-buy stamped today");
        uint32 pendingAfterFirst = _pendingFlipOf(p);
        assertGt(pendingAfterFirst, 0, "non-vacuity: the first cover-buy accrued the flat slot-0 FLIP");

        // Churn N times in the SAME day: cancel (dailyQuantity = 0) -> re-subscribe. The frozen cancel
        // branch (GameAfkingModule:349-363) AUTO-CLAIMS before tombstoning — it pays out the accrued
        // pendingFlip via coinflip.creditFlip and zeroes the slot (c.pendingFlip = 0 at :355) — so
        // pendingFlip reads 0 right after each cancel. The re-subscribe is a NEW run (wasActive == false,
        // stored dailyQuantity is 0) but lastAutoBoughtDay == today, so the idempotency guard at :521 keeps
        // the snapshot and SKIPS a second cover-buy -> NO slot-0 re-accrual. So after each cancel/re-sub
        // cycle pendingFlip stays 0: the per-day flat reward was accrued (and paid out) EXACTLY ONCE,
        // never re-accrued per cycle. (The drain-on-cancel is the c4d48008 behavior; the prior model
        // expected pendingFlip to PERSIST unchanged at 100, which the auto-claim cancel contradicts.)
        for (uint256 i; i < 5; i++) {
            _subscribeLootbox(p, 0);   // cancel — auto-claims + zeroes pendingFlip, tombstones in place
            assertEq(_dailyQtyOf(p), 0, "cancel wrote the dailyQuantity=0 tombstone in place");
            assertEq(_pendingFlipOf(p), 0, "cancel auto-claimed + zeroed pendingFlip (drain-on-cancel)");
            _subscribeLootbox(p, 1);   // re-subscribe SAME day — the NEW-run idempotency guard fires
            assertGt(_subscriberIndexOf(p), 0, "re-subscribe keeps the sub active");
            assertEq(_dailyQtyOf(p), 1, "re-subscribe restored the dailyQuantity (a NEW run, wasActive==false)");
            assertEq(_lastBoughtDayOf(p), today, "the stamp survived the churn (still today)");
            assertEq(
                _pendingFlipOf(p),
                0,
                "CHURN-IDEMPOTENCY: re-subscribe does NOT re-accrue the slot-0 flat reward (guard skips the cover-buy; cancel already paid it out)"
            );
        }

        // NEXT-day subscribe (lastAutoBoughtDay != today) DOES a fresh funded cover-buy — the guard only
        // skips a SAME-day re-entry. Roll a clean fresh day, re-subscribe, assert the stamp advances AND
        // the cover-buy accrues exactly one fresh slot-0. Measured as a DELTA so it holds whether or not
        // the settle reclaimed the cancelled tombstone first (reclaim wipes the cancelled run's unclaimed
        // pendingFlip — a cancelled sub forfeits unclaimed FLIP unless it claims before the sweep,
        // consistent with ticket subs; either way the new-day cover-buy adds one fresh 100).
        _subscribeLootbox(p, 0);       // cancel before the day roll (so the next subscribe is a NEW run)
        _settleClean(uint256(keccak256("churn_nextday")) | 1);
        _t += 1 days;
        vm.warp(_t);
        _settleClean(uint256(keccak256("churn_nextday2")) | 1);
        uint32 nextDay = uint32(game.currentDayView());
        require(nextDay > today, "fixture: the day actually rolled forward");
        uint32 pendingBeforeNextDay = _pendingFlipOf(p);
        _subscribeLootbox(p, 1);       // NEW run on the fresh day — lastAutoBoughtDay != today -> fresh buy
        assertEq(_lastBoughtDayOf(p), nextDay, "NEXT-day subscribe did a fresh funded cover-buy (stamp advanced)");
        assertEq(
            _pendingFlipOf(p) - pendingBeforeNextDay,
            pendingAfterFirst,
            "NEXT-day cover-buy accrued exactly one fresh slot-0 (a real new day is not suppressed)"
        );
    }

    // =========================================================================
    // LEVEL-0 PASS GATE — SUPERSEDED. The old `(validThroughLevel == 0 ||
    // validThroughLevel < level)` boundary was specific to the deleted pass/horizon
    // gate; the AFKing Subscription Token credential (D-11, above) has no level dependence
    // whatsoever, so there is no level-0 boundary left to exercise. The D-11 /
    // D-13 sections above already cover coinless/seated/deity-without-coin/
    // VAULT-SDGNRS-exempt subscribe, and none of those outcomes vary with level.
    // =========================================================================

    // =========================================================================
    // F-356-01 — the drainAffiliateBase Game dispatch stub is reachable + AFFILIATE-only
    // =========================================================================

    /// @notice F-356-01 reachability: the NEW DegenerusGame.drainAffiliateBase(sub) dispatch stub
    ///         (:428, guard-less delegatecall to GAME_AFKING_MODULE) is now reachable from the affiliate
    ///         path. Pranked as ContractAddresses.AFFILIATE (the caller the DegenerusAffiliate.claim()
    ///         drain loop routes through), the stub delegatecalls the module impl whose `msg.sender ==
    ///         AFFILIATE` access gate (:1328) is satisfied, so it drains-and-zeroes the accrued
    ///         affiliateBase and returns it. Pre-357-00 this call reverted (no stub + no fallback) ->
    ///         claim() reverted (the F-356-01 bug). NOW it succeeds.
    function testDrainAffiliateBaseReachableFromAffiliatePath() public {
        address p = makeAddr("drain_reach");
        _grantSeat(p);
        _fundPool(p, 50 ether);       // fund BEFORE subscribe so the grounded NEW run is created (D-12)
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xD4A10B); // accrue affiliateBase via a delivered buy
        uint32 baseBefore = _affiliateBaseOf(p);
        assertGt(baseBefore, 0, "non-vacuity: affiliateBase accrued");

        // The affiliate-path call (msg.sender == AFFILIATE) reaches the NEW Game stub, which delegatecalls
        // the module impl past its AFFILIATE-only gate -> drains-and-zeroes, returns the drained base.
        vm.prank(ContractAddresses.AFFILIATE);
        uint256 drained = game.drainAffiliateBase(p);
        assertEq(drained, uint256(baseBefore), "F-356-01: the stub returned the accrued base (reachable + decoded)");
        assertEq(_affiliateBaseOf(p), 0, "F-356-01: the affiliate path zeroed the base (read-and-zero)");
    }

    /// @notice F-356-01 AFFILIATE-only: a NON-affiliate caller routed through the SAME Game dispatch stub
    ///         reverts NotApproved() (the module impl's access gate, propagated verbatim by
    ///         `_revertDelegate`), leaving the base intact. Proves the new stub did NOT widen access — it
    ///         is reachable ONLY for the affiliate, never a third party redirecting another sub's base.
    function testDrainAffiliateBaseStubAffiliateOnly() public {
        address p = makeAddr("drain_gate");
        _grantSeat(p);
        _fundPool(p, 50 ether);       // fund BEFORE subscribe so the grounded NEW run is created (D-12)
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xD4A106);
        uint32 baseBefore = _affiliateBaseOf(p);
        assertGt(baseBefore, 0, "non-vacuity: affiliateBase accrued");

        // A non-affiliate caller hits the module impl's AFFILIATE-only gate -> NotApproved() bubbles back
        // through the Game stub's _revertDelegate before any storage write.
        vm.prank(makeAddr("not_affiliate"));
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.drainAffiliateBase(p);
        assertEq(_affiliateBaseOf(p), baseBefore, "F-356-01: the rejected non-affiliate drain left the base intact");
    }

    // =========================================================================
    // 357 advance-incentive redesign (HEAD'' = 61315ecd) — advanceGame is pure
    // liveness; the must-mint ladder is the SOFT pay-gate _bountyEligible(addr),
    // surfaced as game.bountyEligible(addr). mintFlip() reads it BEFORE the
    // self-call and pays the advance bounty only when mult>0 && eligible.
    // =========================================================================

    /// @notice advanceGame LIVENESS: a coinless / unfunded non-DGVE EOA, in the first seconds of a fresh
    ///         day (dailyIdx >= 2), can crank advanceGame() with NO MustMintToday revert — that error was
    ///         removed; the advance work is unconditionally permitted. The pre-357 hard gate would have
    ///         reverted a fresh non-minter in the first 15 min; HEAD'' does not. We settle clean, warp one
    ///         day so advanceDue() is true, position 5s past the boundary (below the 15-min window so the
    ///         caller is NOT even bounty-eligible), and assert the crank succeeds.
    function testAdvanceGameLivenessFreshNonMinterNotGated() public {
        // Settle the protocol clean so the next day-roll makes exactly one advance due.
        _settleClean(uint256(keccak256("live_settle")) | 1);
        // Roll to a fresh day, positioned a few seconds past the boundary (< 15 min in).
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance is due on the fresh day");

        address keeper = makeAddr("fresh_keeper"); // coinless, unfunded, non-DGVE, no afking sub
        assertFalse(game.bountyEligible(keeper), "first-15-min fresh non-minter is NOT bounty-eligible");

        // The advance WORK is permissionless — no MustMintToday (that error no longer exists). It may
        // request VRF / partially process, but it must NOT revert for any removed mint-gate reason.
        vm.prank(keeper);
        game.advanceGame(); // MUST NOT revert
        // Liveness held: the advance ran (it consumed the due-state or requested the word).
        assertTrue(!game.advanceDue() || game.rngLocked(), "advanceGame ran the due work (no gate revert)");
    }

    /// @notice bountyEligible truth table @ HEAD'': false for a fresh non-minter/non-DGVE in the first
    ///         15 min; true after 30 min elapsed; true for a deity holder; true for an active afking sub;
    ///         true for the DGVE owner (CREATOR). The same-day-minter tier is covered by the funded-buy
    ///         arm below (a delivered cover-buy stamps DAY_SHIFT). The time tiers read block.timestamp
    ///         arithmetic ((ts - 82620) % 1 days); the deity/sub/DGVE tiers are time-independent.
    function testBountyEligibleTruthTable() public {
        // Settle past the genesis day so dailyIdx >= 2 — the `gateIdx == 0` first-day branch makes
        // EVERYONE eligible (nothing to earn against yet), which would mask the per-tier checks below.
        _settleClean(uint256(keccak256("be_settle")) | 1);
        // Land deterministically in the first-15-min window of a fresh day.
        _warpToDayBoundary(5);
        require(game.currentDayView() >= 2, "fixture: past the gateIdx==0 first-day bypass");

        // (1) fresh non-minter, non-DGVE, no coin, no sub, < 15 min in -> ineligible.
        address fresh = makeAddr("be_fresh");
        assertFalse(game.bountyEligible(fresh), "fresh non-minter <15min: ineligible");

        // (2) deity holder -> eligible at any time (the deity tier short-circuits before the clock).
        //     Deity confers nothing for afking gating; this is a bounty-eligibility tier only.
        address deity = makeAddr("be_deity");
        _grantDeityPass(deity);
        assertTrue(game.bountyEligible(deity), "deity holder: eligible");

        // (3) active afking sub -> eligible (dailyQuantity != 0; the auto-buy participation tier).
        address sub = makeAddr("be_sub");
        _grantSeat(sub);                // clears D-11 so the sub can be created
        _fundPool(sub, 50 ether);      // grounds D-12
        _subscribeLootbox(sub, 1);
        assertTrue(_dailyQtyOf(sub) != 0, "fixture: the afking sub is active");
        assertTrue(game.bountyEligible(sub), "active afking sub: eligible");

        // (4) DGVE majority owner (CREATOR holds 100% DGVE + a permanent deity pass) -> eligible.
        assertTrue(game.bountyEligible(ContractAddresses.CREATOR), "DGVE owner (CREATOR): eligible");

        // (5) the SAME fresh non-minter becomes eligible once 30+ min have elapsed into the day (the
        //     anyone-tier). Advance the clock 31 min and re-read — the only state change is time.
        _t += 31 minutes;
        vm.warp(_t);
        assertTrue(game.bountyEligible(fresh), "after 30 min: anyone-tier flips the fresh keeper eligible");
    }

    /// @notice mintFlip pay soft-gate (ELIGIBLE): a deity-holding keeper cranking mintFlip when an
    ///         advance is due earns the advance bounty (coinflipAmount strictly increases). The deity tier
    ///         makes the keeper eligible regardless of the clock, so mult>0 && eligible -> bountyEarned>0.
    function testMintFlipEligibleKeeperEarnsAdvanceBounty() public {
        _settleClean(uint256(keccak256("pay_e_settle")) | 1);
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance due so mintFlip runs the advance leg");

        address keeper = makeAddr("pay_eligible");
        _grantDeityPass(keeper);       // eligible via the deity tier (time-independent)
        assertTrue(game.bountyEligible(keeper), "fixture: the keeper is bounty-eligible");

        uint256 before = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        game.mintFlip();             // advance leg runs; mult>0 && eligible -> bounty credited
        assertGt(coinflip.coinflipAmount(keeper), before, "ELIGIBLE keeper earned a nonzero advance bounty");
    }

    /// @notice mintFlip pay soft-gate (INELIGIBLE): a fresh non-minter keeper (first 15 min, no coin,
    ///         no sub, non-DGVE) cranking mintFlip still performs the advance WORK but earns ZERO
    ///         advance bounty (mult>0 but !eligible -> bountyEarned == 0; the creditFlip is skipped).
    ///         Directional invariant: the work is done (advance consumed), the keeper's flip balance is
    ///         byte-unchanged.
    function testMintFlipIneligibleKeeperEarnsZeroButWorkRuns() public {
        _settleClean(uint256(keccak256("pay_i_settle")) | 1);
        _warpToDayBoundary(5);         // < 15 min in
        assertTrue(game.advanceDue(), "fixture: advance due so mintFlip runs the advance leg");

        address keeper = makeAddr("pay_ineligible"); // coinless, unfunded, non-DGVE, no sub
        assertFalse(game.bountyEligible(keeper), "fixture: the keeper is NOT bounty-eligible");

        uint256 before = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        game.mintFlip();             // advance work runs regardless; bounty withheld
        assertEq(coinflip.coinflipAmount(keeper), before, "INELIGIBLE keeper earned ZERO advance bounty");
        // The work still ran (the due-state was consumed or the word was requested) — pure liveness.
        assertTrue(!game.advanceDue() || game.rngLocked(), "the advance work ran for the ineligible keeper too");
    }

    /// @notice Vault keeper routing: DegenerusVault.gameAdvance() now routes through game.mintFlip()
    ///         (earning the bounty); it performs the crank when work is due and reverts NoWork() when
    ///         idle. The vault is owner-gated (onlyVaultOwner) — prank as CREATOR (the DGVE majority
    ///         owner, also a permanent deity holder -> always eligible). Both arms asserted.
    function testVaultGameAdvanceRoutesThroughMintFlip() public {
        // Idle arm first: settle clean, do NOT roll the day -> nothing due -> NoWork().
        _settleClean(uint256(keccak256("vault_idle")) | 1);
        // Commit bounded human-frontier housekeeping across finalized empty indices first;
        // the wrapper's idle assertion is about a genuinely stationary router.
        game.openBoxes(1_000);
        require(!game.advanceDue(), "fixture: clean so the idle arm is genuine");
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        vault.gameAdvance();

        // Work-due arm: roll a fresh day -> advance due -> gameAdvance cranks via mintFlip (no revert).
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance due for the vault crank");
        vm.prank(ContractAddresses.CREATOR);
        vault.gameAdvance();           // MUST NOT revert — routes through mintFlip and does the work
        assertTrue(!game.advanceDue() || game.rngLocked(), "vault.gameAdvance ran the due advance work");
    }

    /// @notice sDGNRS keeper routing: sDGNRS.gameAdvance() routes through game.mintFlip()
    ///         and is PERMISSIONLESS (no owner gate). It performs the crank when work is due and reverts
    ///         NoWork() when idle. (sDGNRS self-subscribed at construction -> it holds an afking sub, so
    ///         when it is the msg.sender of mintFlip it is bounty-eligible — but the routing/NoWork
    ///         behavior is what this proves.)
    function testSdgnrsGameAdvanceRoutesThroughMintFlip() public {
        // Idle arm: clean, no day-roll -> NoWork().
        _settleClean(uint256(keccak256("sdgnrs_idle")) | 1);
        // Commit bounded human-frontier housekeeping across finalized empty indices first;
        // the wrapper's idle assertion is about a genuinely stationary router.
        game.openBoxes(1_000);
        require(!game.advanceDue(), "fixture: clean so the idle arm is genuine");
        vm.prank(makeAddr("anyone_sdgnrs")); // permissionless — any caller
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        sdgnrs.gameAdvance();

        // Work-due arm: roll a fresh day -> advance due -> gameAdvance cranks via mintFlip (no revert).
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance due for the sDGNRS crank");
        vm.prank(makeAddr("anyone_sdgnrs2"));
        sdgnrs.gameAdvance();          // MUST NOT revert — routes through mintFlip and does the work
        assertTrue(!game.advanceDue() || game.rngLocked(), "sdgnrs.gameAdvance ran the due advance work");
    }

    // =========================================================================
    // Protocol-driving helpers (ported VERBATIM from V56SecUnmanipulable, minus the deleted
    // pass/horizon pokes — the credential poke is `_grantSeat` from DeployProtocol)
    // =========================================================================

    /// @dev Warp to a fresh day boundary + `offsetSeconds` (the daily reset is 82620s past midnight).
    ///      Lands deterministically in the first seconds of a NEW day so advanceDue() is true and the
    ///      bounty time-tiers (15-min / 30-min) are below threshold. Mirrors the v56 gas-marginal
    ///      `_warpToBoundary` day-roll, threaded through the accumulating-timestamp workaround.
    function _warpToDayBoundary(uint256 offsetSeconds) internal {
        uint256 dayLen = 1 days;
        uint256 reset = 82620;
        uint256 cur = block.timestamp;
        uint256 idx = (cur - reset) / dayLen;
        uint256 nextBoundary = (idx + 1) * dayLen + reset + offsetSeconds;
        _t = nextBoundary;
        vm.warp(_t);
    }

    uint256 private _deliverNonce;

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps each pending box + accrues), then
    ///      settle clean and OPEN every pending box (so the no-orphan guard does not skip the next buy).
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
        who;
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
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

    /// @dev Deity bit only — a bounty-eligibility tier now; confers nothing for the afking coin gate.
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke the game `level` (slot 0, byte 12, uint24) to drive the level-crossing
    ///      membership-survival proof (the fixture level does not advance organically over the harness loop).
    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFF * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFF * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            if (uint8(uint256(bytes32(logs[i].data))) == reason) count++;
        }
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    // ---- Sub-slot reads (_subOf slot 53 + the post-coin-gate offsets) ----

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

    function _affiliateBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFFBASE, 32));
    }

    function _pendingFlipOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGFLIP, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }
}
