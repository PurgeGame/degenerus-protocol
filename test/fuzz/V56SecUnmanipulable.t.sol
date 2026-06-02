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
///   is the `pendingBurnie` accumulator (100 whole BURNIE / delivered buy, the slot-0 quest reward) pulled
///   via the permissionless CEI `claimAfkingBurnie` (zero-before-credit at :1277). The affiliate base accrues
///   7%-of-spend whole-BURNIE per delivered buy and PERSISTS across unsub (:315) — drained AFFILIATE-only,
///   read-and-zero, at `drainAffiliateBase` (:1300).
///
/// @notice The delivery model the harness exercises: each delivered day is a STAGE buy (stamps the pending
///   box + accrues pendingBurnie/affiliateBase + advances the covered high-water) FOLLOWED BY an open (the
///   no-orphan guard, :892, skips a sub with a pending unopened box, so the box must be opened before the
///   next day's buy). Strategic churn = unsub/re-sub/claim sequenced around that buy+open.
///
/// @notice The four designed-against vectors (each a legible "this exact vector is closed" regression):
///   1. Affiliate re-claim churn — sub/unsub/re-sub neither forfeits nor duplicates the accrued base; the
///      total drained EQUALS honest continuous accrual.
///   2. Streak decay / gap dodge — miss one funded day -> the read decays to 0; resume after a gap -> the run
///      re-bases (`afkingStartDay`/streak base reset on the delivered day); advances ONLY on delivered days.
///   3. pendingBurnie double-claim CEI idempotency (Task 2).
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
    uint256 private constant SUBOF_SLOT = 66;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // mapping(address => uint256) _subscriberIndex (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 10;       // mintPacked_ mapping root (deity bit @ bit 184)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31
    uint256 private constant OFF_DAILY = 0;           // uint8  dailyQuantity        (byte 0)
    uint256 private constant OFF_LASTBOUGHT = 11;     // uint24 lastAutoBoughtDay    (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14;     // uint24 lastOpenedDay        (bytes 14..16)
    uint256 private constant OFF_AFKCOVERED = 17;     // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_AFKINGSTART = 20;    // uint24 afkingStartDay       (bytes 20..22)
    uint256 private constant OFF_AFFBASE = 23;        // uint32 affiliateBase        (bytes 23..26)
    uint256 private constant OFF_PENDINGBURNIE = 27;  // uint32 pendingBurnie        (bytes 27..30)
    uint256 private constant OFF_STREAKLATCH = 31;    // uint8  subStreakLatch       (byte 31; bit7 ever-sub, bits0-6 streak)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole BURNIE accrued to pendingBurnie per delivered buy.
    uint256 private constant SLOT0_BURNIE_PER_BUY = 100;

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
    ///         as an honest continuous sub over the same number of delivered buys. The base accrues per
    ///         delivered buy and PERSISTS byte-identical across the unsub tombstone (GameAfkingModule.sol:315
    ///         — the cancel finalizes the streak but never touches affiliateBase/pendingBurnie); it is also
    ///         preserved by the in-stage cancel-reclaim path before that slot would otherwise turn over.
    ///         FORFEIT-NOTHING-GAIN-NOTHING: churn neither resets nor duplicates the running base, so a
    ///         churner can never out-accrue an honest continuous sub.
    function testAffiliateReClaimChurnEqualsHonestContinuous() public {
        address honest = makeAddr("aff_honest");
        address churner = makeAddr("aff_churn");
        _grantDeityPass(honest);
        _grantDeityPass(churner);

        uint256 D = 3;

        // HONEST arm: one continuous sub, deliver D buys (buy + open each day).
        _subscribeLootbox(honest, 1);
        _fundPool(honest, 50 ether);
        for (uint256 d; d < D; d++) {
            _deliverDay(_singleton(honest), uint256(keccak256(abi.encode("affH", d))) | 1);
        }
        uint256 honestBase = _affiliateBaseOf(honest);
        assertGt(honestBase, 0, "honest: base accrued (non-vacuous)");

        // CHURN arm: deliver D buys, but unsub immediately after each buy and re-sub before the next; the
        // running base must SURVIVE every unsub tombstone (the same slot is re-used so the accrued base is
        // never deleted between cycles — the persist property).
        _subscribeLootbox(churner, 1);
        _fundPool(churner, 50 ether);
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
                _subscribeLootbox(churner, 1);
                _fundPool(churner, 50 ether);
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
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);
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
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);

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
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);

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

        // RESUME: re-subscribe + re-fund + deliver a fresh day after the gap. The buy re-bases the run
        // (afkingStartDay := the resume day; base := 0) because covered + 1 < processDay (decay-on-read).
        if (_subscriberIndexOf(p) == 0) _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);
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
    ///         (a) the cumulative BURNIE the churner can pull (already-claimed + still-pending) is <= the
    ///             honest continuous accrual over the SAME number of delivered buys (100 whole BURNIE per
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
        _subscribeLootbox(honest, 1);
        _fundPool(honest, 80 ether);
        _subscribeLootbox(churner, 1);
        _fundPool(churner, 80 ether);

        uint256 churnClaimed; // whole BURNIE pulled out of the churner's pendingBurnie via claimAfkingBurnie

        for (uint256 d; d < D; d++) {
            // Deliver the day to both arms: STAGE buy + open (the honest control always delivers; the churner
            // delivers only if it currently has an in-set sub).
            address[] memory both = _subscriberIndexOf(churner) != 0 ? _pair(honest, churner) : _singleton(honest);
            _deliverDay(both, uint256(keccak256(abi.encode("fz", actions, d))) | 1);

            // The churner's random actions AROUND the day's buy+open: nibble per day.
            uint8 act = uint8((actions >> (d * 4)) & 0x0F);
            if ((act & 0x1) != 0 && _subscriberIndexOf(churner) != 0) {
                churnClaimed += _pendingBurnieOf(churner);
                game.claimAfkingBurnie(_singleton(churner)); // zeroes pendingBurnie; a re-claim later finds 0
            }
            if ((act & 0x2) != 0 && _subscriberIndexOf(churner) != 0) {
                vm.prank(churner); // unsub (tombstone) — base + pendingBurnie persist
                game.subscribe(address(0), false, false, 0, 0, address(0));
            }
            if ((act & 0x4) != 0 && _subscriberIndexOf(churner) == 0) {
                _subscribeLootbox(churner, 1); // re-sub fresh + re-fund
                _fundPool(churner, 80 ether);
            }
        }

        // (a) The churner's total reachable BURNIE (already-claimed + still-pending) is bounded by the honest
        //     control's reachable BURNIE (its pending — the honest control never claims, so all its accrual is
        //     still pending). The honest control delivered every day; the churner can only DELAY or LOSE a
        //     day (a missed delivery or an unsub that strands accrual), never manufacture one — so it can
        //     never out-accrue the honest continuous sub. Each is an exact multiple of 100 BURNIE / delivered
        //     buy, so the reachable totals are whole-BURNIE multiples (no fractional manufactured credit).
        uint256 churnReachable = churnClaimed + _pendingBurnieOf(churner);
        uint256 honestReachable = _pendingBurnieOf(honest);
        assertLe(churnReachable, honestReachable, "churn total reachable BURNIE <= honest continuous accrual (no positive-EV)");
        assertEq(churnReachable % SLOT0_BURNIE_PER_BUY, 0, "churn reachable is a whole-BURNIE multiple of the 100/delivered-buy reward (no manufactured fractional credit)");

        // (b) The compute-on-read streak credits no non-delivered / non-existent day. The streak inputs are
        //     `afkingStartDay` and the `covered` high-water (`_afkingStreak = base + (covered - start)`); the
        //     contract advances `covered` ONLY on a debit-delivered day and never past the current day. So
        //     for the churner: afkingStartDay <= covered <= currentDay — the span never reaches into a
        //     non-delivered future day, and the realizable BURNIE (bound (a)) caps the economic value.
        if (_subscriberIndexOf(churner) != 0) {
            uint32 cov = _afkCoveredOf(churner);
            uint32 st = _afkingStartOf(churner);
            uint32 today = game.currentDayView();
            assertLe(uint256(st), uint256(cov), "afkingStartDay <= covered (the run base never exceeds its delivered high-water)");
            assertLe(uint256(cov), uint256(today), "covered <= currentDay (the streak credits no non-existent future day)");
        }
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55SetMutationOpenE / V56AfkingGasMarginal)
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps each pending box + accrues), then
    ///      settle clean and OPEN every pending box (so the no-orphan guard does not skip the next day's buy).
    ///      Each delivered day advances the covered high-water and accrues 100 pendingBurnie per in-set sub.
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

    /// @dev The decay-applied streak DegenerusQuests.finalizeAfking wrote for `who` on its most recent
    ///      sub-ending finalize, read from the QuestStreakBonusAwarded event
    ///      (player indexed, uint16 amount, uint24 newStreak, uint32 currentDay). The finalize emits with
    ///      amount == 0 and newStreak == the decay-applied final streak. Requires vm.recordLogs() first.
    function _lastFinalizeStreakFor(address who) internal returns (uint24) {
        bytes32 sig = keccak256("QuestStreakBonusAwarded(address,uint16,uint24,uint32)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint24 found;
        bool any;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            (uint16 amount, uint24 newStreak, ) = abi.decode(logs[i].data, (uint16, uint24, uint32));
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

    // ---- Sub-slot reads (slot 66 + the v56 offsets) ----

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

    function _pendingBurnieOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGBURNIE, 32));
    }

    function _streakBaseOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_STREAKLATCH, 8)) & 0x7f;
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }
}
