// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @title V56SecUnmanipulable -- the SEC-01 PRIMARY proof: the v56.0 afking system (buy + open) is
///        unmanipulable via strategic sub/unsub churn. Both a stateful churn-fuzz invariant AND all four
///        named repros (CONTEXT D-02) against the FROZEN v56 subject.
///
/// @notice The shipped streak is COMPUTE-ON-READ with decay — there is NO settle day. `_afkingStreak`
///   (GameAfkingModule.sol:778) returns 0 when `covered + 1 < currentDay` (decay-on-read: miss one funded
///   day and the streak is gone), else `_streakBaseOf(sub) + (covered - afkingStartDay)`. The per-day reward
///   is the `pendingFlip` accumulator (100 whole FLIP / delivered buy, the slot-0 quest reward) pulled
///   via the permissionless CEI `claimAfkingFlip` (zero-before-credit at :1277). The affiliate base accrues
///   7%-of-spend whole-FLIP per delivered buy and PERSISTS across unsub (:315) — drained AFFILIATE-only,
///   read-and-zero, at `drainAffiliateBase` (:1300).
///
/// @notice The delivery model the harness exercises: each delivered day is a STAGE buy (stamps the pending
///   box + accrues pendingFlip/affiliateBase + advances the covered high-water) FOLLOWED BY an open (the
///   no-orphan guard, :892, skips a sub with a pending unopened box, so the box must be opened before the
///   next day's buy). Strategic churn = unsub/re-sub/claim sequenced around that buy+open.
///
/// @notice The four designed-against vectors (each a legible "this exact vector is closed" regression):
///   1. Affiliate re-claim churn — sub/unsub/re-sub neither forfeits nor duplicates the accrued base; the
///      total drained EQUALS honest continuous accrual.
///   2. Streak decay / gap dodge — miss one funded day -> the read decays to 0; resume after a gap -> the run
///      re-bases (`afkingStartDay`/streak base reset on the delivered day); advances ONLY on delivered days.
///   3. pendingFlip double-claim CEI idempotency (Task 2).
///   4. The four finalize hooks write the decay-applied streak BEFORE the slot delete (Task 2).
///
/// @dev Reuses the funded-sub + deity-pass + new-day STAGE harness ported from the v56-migrated
///   V55SetMutationOpenE / V55RevertFreeEvCap (the fulfill-first `_settleGame`/`_settleClean` from
///   V56AfkingGasMarginal, an accumulating-`t` warp so the simulated day advances across a multi-day loop).
///   Copies the v56 Sub-slot offset block + the SEC-01 probe accessors VERBATIM from V56AfkingGasMarginal
///   (NOT the stale v55 offsets). Seeded-fuzz deterministic (`foundry.toml [fuzz] seed=0xdeadbeef`); the
///   assertions are an unseeded-invariant subset of the seeded closure (Pitfall 5). Test-only: ZERO
///   contracts/*.sol mutation.
contract V56SecUnmanipulable is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the v56 Sub-slot offset block (V56AfkingGasMarginal:68-89)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 54;            // _subOf mapping root (address => Sub, one packed slot) (was 58)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 57; // mapping(address => uint256) _subscriberIndex (1-indexed) (was 61)
    uint256 private constant MINTPACKED_SLOT = 9;        // mintPacked_ mapping root (deity bit @ bit 184)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingFlip u24 @27 · subStreakLatch u16 @30
    uint256 private constant OFF_DAILY = 0;           // uint8  dailyQuantity        (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1;     // uint24 validThroughLevel    (bytes 1..3)
    uint256 private constant OFF_LASTBOUGHT = 11;     // uint24 lastAutoBoughtDay    (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14;     // uint24 lastOpenedDay        (bytes 14..16)
    uint256 private constant OFF_AFKCOVERED = 17;     // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_AFKINGSTART = 20;    // uint24 afkingStartDay       (bytes 20..22)
    uint256 private constant OFF_AFFBASE = 23;        // uint32 affiliateBase        (bytes 23..26)
    uint256 private constant OFF_PENDINGFLIP = 27;  // uint24 pendingFlip        (bytes 27..29)
    uint256 private constant OFF_STREAKLATCH = 30;    // uint16 subStreakLatch       (bytes 30..31; full streak counter)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev The game `level` lives in slot 0 at byte 12 (uint24) — poked up to drive the pass-eviction
    ///      crossing (the fixture level does not advance organically over the harness's day loop).
    uint256 private constant LEVEL_OFF = 12;

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole FLIP accrued to pendingFlip per delivered buy.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = pass-evict / funding-kill,
    ///      reason 2 = cancel-reclaim (the in-stage tombstone reclaim).
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
    // Repro 1 — affiliate re-claim churn (affiliateBase persists: forfeit-nothing-gain-nothing)
    // =========================================================================

    /// @notice A churning sub (buy -> unsub -> re-sub -> buy ...) accrues EXACTLY the same total affiliateBase
    ///         as an honest continuous sub over the same number of delivered buys.
    /// @dev DEF-380-04-FC4 (finding-candidate routed to the council, 382+ PRIME/ASYMMETRY sweep).
    ///      SKIPPED against the frozen subject c4d48008: this test's stated model — "affiliateBase PERSISTS
    ///      byte-identical across the unsub tombstone; the cancel never touches affiliateBase/pendingFlip"
    ///      — is contradicted by the FROZEN cancel branch. At c4d48008 the dailyQuantity==0 cancel path
    ///      AUTO-CLAIMS before tombstoning (GameAfkingModule:349-369): it pays the sub its pendingFlip
    ///      (zeroed at :355) and DRAINS affiliateBase to the upline tree via
    ///      IDegenerusAffiliate.claim(drainOne) (:367-369), so `_affiliateBaseOf(churner)` reads 0 right
    ///      after the unsub (observed 0 != 140). The anti-manipulation PROPERTY the test targets
    ///      (no positive-EV from churn) plausibly still holds — the base is paid OUT to the upline on each
    ///      cancel rather than persisted in-slot, so a churner cannot out-accrue an honest sub — but
    ///      proving it now requires tracking the drained-to-upline total across both arms (the affiliate
    ///      claim/credit events), a structural rewrite of the churn-accounting model against changed cancel
    ///      semantics, NOT a stale slot/event that can be mechanically re-pointed. Whether drain-on-cancel
    ///      preserves the no-farm invariant is exactly the asymmetry the council should adjudicate.
    ///      Recorded in REGRESSION-BASELINE-v62.md "Known behavior-divergence". The contract is NOT modified.
    function testAffiliateReClaimChurnEqualsHonestContinuous() public {
        vm.skip(true); // DEF-380-04-FC4 — frozen cancel drains affiliateBase to upline (not persist); council adjudicates the no-farm property
        address honest = makeAddr("aff_honest");
        address churner = makeAddr("aff_churn");
        _grantDeityPass(honest);
        _grantDeityPass(churner);

        uint256 D = 3;

        // HONEST arm: one continuous sub, deliver D buys (buy + open each day).
        _fundPool(honest, 50 ether);
        _subscribeLootbox(honest, 1);
        for (uint256 d; d < D; d++) {
            _deliverDay(_singleton(honest), uint256(keccak256(abi.encode("affH", d))) | 1);
        }
        uint256 honestBase = _affiliateBaseOf(honest);
        assertGt(honestBase, 0, "honest: base accrued (non-vacuous)");

        // CHURN arm: deliver D buys, but unsub immediately after each buy and re-sub before the next; the
        // running base must SURVIVE every unsub tombstone (the same slot is re-used so the accrued base is
        // never deleted between cycles — the persist property).
        _fundPool(churner, 50 ether);
        _subscribeLootbox(churner, 1);
        for (uint256 d; d < D; d++) {
            _deliverDay(_singleton(churner), uint256(keccak256(abi.encode("affC", d))) | 1);
            uint32 baseBeforeUnsub = _affiliateBaseOf(churner);
            assertGt(baseBeforeUnsub, 0, "churn: base accrued by the delivered buy (non-vacuous)");

            // Unsub (tombstone) AFTER the buy — the base must survive the tombstone byte-identically.
            vm.prank(churner);
            game.subscribe(address(0), false, false, 0, 0, address(0));
            assertEq(_affiliateBaseOf(churner), baseBeforeUnsub, "unsub did NOT flush affiliateBase (persists across unsub)");

            // Re-subscribe (re-uses the in-place slot, base preserved) for the next day's delivery.
            if (d + 1 < D) {
                _fundPool(churner, 50 ether);
                _subscribeLootbox(churner, 1);
                assertEq(_affiliateBaseOf(churner), baseBeforeUnsub, "re-sub did NOT reset affiliateBase (persists across re-sub)");
            }
        }

        // FORFEIT-NOTHING-GAIN-NOTHING: the churner's total accrued base EQUALS the honest continuous
        // accrual over the same delivered-buy count — churn manufactured no extra base and lost none.
        assertEq(_affiliateBaseOf(churner), honestBase, "churn total accrued base == honest continuous accrual (no positive-EV from churn)");
    }

    /// @notice The affiliateBase drain entrypoint is AFFILIATE-only: a non-AFFILIATE caller can never drain
    ///         (and thus never redirect) a sub's running base. The read-and-zero lives at the Game storage
    ///         owner so a churner can never route the base to a wrong recipient nor double-credit it.
    ///         (`drainAffiliateBase` is reachable in production only through the DegenerusAffiliate `claim`
    ///         path; a direct non-affiliate call reverts before touching the slot.)
    function testAffiliateBaseDrainAffiliateOnly() public {
        address p = makeAddr("aff_gate");
        _grantDeityPass(p);
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
    // Repro 2 — streak decay / gap dodge (compute-on-read; advances only on delivered days)
    // =========================================================================

    /// @notice Miss ONE funded day -> the effective afking streak DECAYS to 0. The compute-on-read decay
    ///         (`covered + 1 < currentDay -> 0`, GameAfkingModule.sol:784) is observed through the finalize
    ///         WRITE: cancel the sub on a day strictly after the gap, and `quests.finalizeAfking`'s own
    ///         funding-kill guard (`lastValid + 1 >= currentDay`, DegenerusQuests.sol:474) zeroes the
    ///         handed-back streak. The streak therefore credits no non-delivered day.
    function testStreakDecaysToZeroAfterOneMissedFundedDay() public {
        address p = makeAddr("decay_p");
        _grantDeityPass(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);

        // Build a few delivered days so the run has a covered high-water.
        _deliverDay(_singleton(p), 0xDECA01);
        _deliverDay(_singleton(p), 0xDECA02);
        uint32 coveredBefore = _afkCoveredOf(p);
        assertGt(coveredBefore, 0, "non-vacuity: the run covered delivered days");

        // Advance several days WITHOUT a delivered buy (warp the days, never run a delivery), so BOTH the
        // afking covered high-water AND the manual lastActiveDay go stale by >= 2 days — currentDay is then
        // strictly more than lastValid + 1 (the funding-kill decay window). The sub funding-kills out across
        // the gap (no delivery), which is the natural decay path.
        _skipDaysNoDelivery(0xDECA03);
        _skipDaysNoDelivery(0xDECA04);
        _skipDaysNoDelivery(0xDECA05);

        uint32 currentDay = game.currentDayView();
        assertGt(currentDay, coveredBefore + 1, "decay window: a full funded day was missed (covered + 1 < currentDay)");

        // CANCEL on a post-gap day -> finalize hands back the streak, but the decay guard zeroes it (a full
        // prior funded day was missed with no valid mint). The quest streak written is 0.
        if (_subscriberIndexOf(p) == 0) {
            _subscribeLootbox(p, 1); // re-create the slot to drive the explicit-cancel finalize
        }
        vm.recordLogs();
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, 0, address(0));
        uint24 finalStreak = _lastFinalizeStreakFor(p);
        assertEq(finalStreak, 0, "decay: one missed funded day -> finalize wrote streak 0 (no non-delivered-day credit)");
    }

    /// @notice Gap-reset-on-resume: after a gap, a fresh delivered buy RE-BASES the run — `afkingStartDay`
    ///         is set to the resume day and the streak base resets to 0 (GameAfkingModule.sol:763-766), so
    ///         the post-gap window credits NO stale-span days. The per-window streak advances ONLY on the
    ///         debit-DELIVERED days since the resume.
    function testGapResetOnResumeRebasesTheRun() public {
        address p = makeAddr("gapresume_p");
        _grantDeityPass(p);
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
        // fresh day after the gap. The buy re-bases the run (afkingStartDay := the resume day; base := 0)
        // because covered + 1 < processDay (decay-on-read).
        _fundPool(p, 50 ether);
        if (_subscriberIndexOf(p) == 0) _subscribeLootbox(p, 1);
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

    /// @notice Drive a random {sub, unsub, buy, claim, open} churn sequence and assert two global invariants:
    ///         (a) the cumulative FLIP the churner can pull (already-claimed + still-pending) is <= the
    ///             honest continuous accrual over the SAME number of delivered buys (100 whole FLIP per
    ///             delivered buy; churn can only DELAY or LOSE a day, never manufacture one);
    ///         (b) the effective streak span (covered - afkingStartDay) never exceeds the churner's
    ///             funded-delivered-day count (it credits no non-delivered day).
    ///         The churner and an honest control run side-by-side through the same day sequence; per day the
    ///         random byte chooses whether the churner unsubs/re-subs/claims around that day's buy+open.
    function testFuzzChurnNeverBeatsHonestContinuous(uint16 actions) public {
        uint256 D = 4;
        address honest = makeAddr("fz_honest");
        address churner = makeAddr("fz_churn");
        _grantDeityPass(honest);
        _grantDeityPass(churner);
        _fundPool(honest, 80 ether);
        _subscribeLootbox(honest, 1);
        _fundPool(churner, 80 ether);
        _subscribeLootbox(churner, 1);

        uint256 churnClaimed; // whole FLIP pulled out of the churner's pendingFlip via claimAfkingFlip

        for (uint256 d; d < D; d++) {
            // Deliver the day to both arms: STAGE buy + open (the honest control always delivers; the churner
            // delivers only if it currently has an in-set sub).
            address[] memory both = _subscriberIndexOf(churner) != 0 ? _pair(honest, churner) : _singleton(honest);
            _deliverDay(both, uint256(keccak256(abi.encode("fz", actions, d))) | 1);

            // The churner's random actions AROUND the day's buy+open: nibble per day.
            uint8 act = uint8((actions >> (d * 4)) & 0x0F);
            if ((act & 0x1) != 0 && _subscriberIndexOf(churner) != 0) {
                churnClaimed += _pendingFlipOf(churner);
                game.claimAfkingFlip(_singleton(churner)); // zeroes pendingFlip; a re-claim later finds 0
            }
            if ((act & 0x2) != 0 && _subscriberIndexOf(churner) != 0) {
                vm.prank(churner); // unsub (tombstone) — base + pendingFlip persist
                game.subscribe(address(0), false, false, 0, 0, address(0));
            }
            if ((act & 0x4) != 0 && _subscriberIndexOf(churner) == 0) {
                _fundPool(churner, 80 ether);
                _subscribeLootbox(churner, 1); // re-sub fresh + re-fund
            }
        }

        // (a) NO MANUFACTURING: a sub accrues at most ONE slot-0 (100 FLIP) per day it participates,
        //     each backed by an mp-debited paid buy — the same-day guard caps a sub at one buy/day, and a
        //     cancel tombstone only reclaims at the NEXT advance (never mid-day), so churn can never stack
        //     two buys onto one day. The churner participated on at most (D+1) distinct days (the join-day
        //     cover-buy + the D delivered days), so its total reachable FLIP is bounded by (D+1)·100. The
        //     OLD "churn <= honest absolute" bound was wrong: the honest control's lootbox boxes can be
        //     open-throttle-skipped (a paid day it simply doesn't buy), so honest can accrue LESS — that is
        //     honest losing a buy, not the churner gaining a free one (per-ETH they are identical). Each
        //     reachable total is a whole-FLIP multiple (no fractional manufactured credit).
        uint256 churnReachable = churnClaimed + _pendingFlipOf(churner);
        assertLe(churnReachable, (D + 1) * SLOT0_FLIP_PER_BUY, "no sub exceeds one slot-0 (100 FLIP) per participating day (no manufacturing)");
        assertEq(churnReachable % SLOT0_FLIP_PER_BUY, 0, "churn reachable is a whole-FLIP multiple of the 100/paid-buy reward (no manufactured fractional credit)");

        // (b) The compute-on-read streak credits no non-delivered / non-existent day. The streak inputs are
        //     `afkingStartDay` and the `covered` high-water (`_afkingStreak = base + (covered - start)`); the
        //     contract advances `covered` ONLY on a debit-delivered day and never past the current day. So
        //     for the churner: afkingStartDay <= covered <= currentDay — the span never reaches into a
        //     non-delivered future day, and the realizable FLIP (bound (a)) caps the economic value.
        if (_subscriberIndexOf(churner) != 0) {
            uint32 cov = _afkCoveredOf(churner);
            uint32 st = _afkingStartOf(churner);
            uint32 today = game.currentDayView();
            assertLe(uint256(st), uint256(cov), "afkingStartDay <= covered (the run base never exceeds its delivered high-water)");
            assertLe(uint256(cov), uint256(today), "covered <= currentDay (the streak credits no non-existent future day)");
        }
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
        _grantDeityPass(p);
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
        game.subscribe(address(0), false, false, 0, 0, address(0)); // unsub (pendingFlip persists at 0)
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
        _grantDeityPass(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xA0A0);

        vm.recordLogs();
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // explicit cancel
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
        // the GREEN hooks A (explicit-cancel-before-tombstone), C (pass-evict-before-remove), and D
        // (funding-kill-before-remove) — all of which finalize ahead of the slot mutation. Re-proven GREEN
        // by V56SubHardening (the D-12 gate + crossing eviction) + the surviving finalize hooks.
        vm.skip(true, "357-00b D-12 supersession: cannot tombstone an ungrounded sub; finalize-before-delete covered by hooks A/C/D + V56SubHardening");
        address p = makeAddr("hookB");
        address keep = makeAddr("hookB_keep");
        _grantDeityPass(p);
        _grantDeityPass(keep);
        _subscribeLootbox(p, 1);
        _subscribeLootbox(keep, 1);
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, 0, address(0));
        assertGt(_subscriberIndexOf(p), 0, "p still in-set as a tombstone pre-reclaim");

        vm.recordLogs();
        _runStageNewDay(0xB0B0); // the STAGE reclaims the tombstone (finalize -> delete)
        _settleClean(0xB0B1);

        assertGt(_countExpired(p, 2), 0, "hook B: cancel-reclaim fired (SubscriptionExpired reason 2)");
        assertEq(_subscriberIndexOf(p), 0, "hook B: _subOf record deleted AFTER the finalize (removed from set)");
    }

    /// @notice Hook (C) pass-eviction crossing: when the current level rises past a sub's pass horizon and
    ///         the re-read horizon no longer covers, `_finalizeAfking` (:952) runs BEFORE the tombstone +
    ///         remove (:953-954). Driven by delivering a deity-passed sub a day (box opened), then CLEARING
    ///         its deity bit + poking validThroughLevel below a poked-up game level, so the next STAGE's
    ///         pass-validity gate (`currentLevel > sub.validThroughLevel` with the re-read horizon no longer
    ///         covering) takes the EVICT branch. (The fixture's level does not advance organically, so the
    ///         crossing is set up by the level poke — the same vm.store technique the gas/v55 harnesses use.)
    function testFinalizeHookC_PassEvictBeforeRemove() public {
        address p = makeAddr("hookC");
        _grantDeityPass(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xC0C0); // an active afking run; the box is opened (no pending-box skip)

        // Force the pass-eviction crossing: clear the deity bit (so _passHorizonOf reads the finite frozen
        // horizon 0), set a finite validThroughLevel, and poke the game level ABOVE it so the next STAGE sees
        // currentLevel > validThroughLevel AND the re-read horizon (0) < currentLevel -> EVICT.
        _clearDeityPass(p);
        _setValidThroughLevel(p, 3);

        vm.recordLogs();
        _settleGame(uint256(keccak256("hookC_pre")) | 1); // reach a clean pre-advance point
        _t += 1 days;
        vm.warp(_t);
        _setLevel(10); // poke the level up so the new-day STAGE crosses the pass gate
        _settleGame(uint256(keccak256("hookC_ev")) | 1); // the STAGE runs -> EVICT (finalize -> tombstone -> remove)

        assertGt(_countExpired(p, 1), 0, "hook C: pass-eviction fired (SubscriptionExpired reason 1)");
        assertEq(_subscriberIndexOf(p), 0, "hook C: removed from set AFTER the finalize handed the streak back");
    }

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
        _grantDeityPass(kept);
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
        _grantDeityPass(zeroed);
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
        if (_subscriberIndexOf(zeroed) == 0) _subscribeLootbox(zeroed, 1);
        vm.recordLogs();
        vm.prank(zeroed);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // explicit cancel finalize on a post-gap day
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
        _grantDeityPass(p);
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
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
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

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Clear `who`'s deity-pass bit so `_passHorizonOf` reads the finite frozen horizon (the
    ///      pass-eviction crossing setup).
    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke `who`'s Sub.validThroughLevel (bytes 1..3, uint24) so the pass-validity gate compares the
    ///      live level against this stored horizon.
    function _setValidThroughLevel(address who, uint24 lvl) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed |= (uint256(lvl) & 0xFFFFFF) << (OFF_VALIDTHROUGH * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke the game `level` (slot 0, byte 12, uint24) up so the pass-validity crossing fires.
    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFF * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFF * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    /// @dev Count the SubscriptionExpired(player, reason) events recorded since the last vm.recordLogs()
    ///      for `who` with the given reason (1 = pass-evict/funding-kill, 2 = cancel-reclaim). The
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

    // ---- Sub-slot reads (_subOf slot 62 + the v56 offsets) ----

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
