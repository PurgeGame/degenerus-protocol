// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title V61CurseSet — TST-03 proof: the cashout-curse SET (+2 on a stale ghost-cashout), every exemption
///        (by contrast), the curse*100-bps activity-score penalty (floored 0, across consumers + the public
///        view + a frozen snapshot), the min(2N, cap) stacking with cap saturation (no uint8 wrap), and the
///        same-day-second-claim sentinel revert.
///
/// @notice The SET lives in GameAfkingModule.maybeCurse (delegatecall target from the Game's public
///   claimWinnings, DegenerusGame.sol:1572): after a successful claim it adds a saturating +2 stack UNLESS a
///   cheapest-first bail fires — infra (VAULT/SDGNRS/GNRUS), gameOver, a non-stale claim (lastEthDay + 5 >
///   _currentMintDay()), a deity-pass holder, a whale/lazy-pass holder (frozenUntilLevel >= level &&
///   bundleType ∈ {1,3}), an active afker (_subOf[p].dailyQuantity != 0), or an already-capped counter
///   (CURSE_COUNT_CAP = 20). claimWinningsStethFirst (the vault-only path) NEVER calls maybeCurse.
///
///   Every exemption is proven BY CONTRAST: the exempt actor's curseCountOf stays 0 while an otherwise-
///   identical NON-exempt actor's curseCountOf becomes 2 — so a removed bail would flip the contrast and fail
///   the test (not a bare absolute-zero check that a no-op would also pass).
///
///   The penalty (MintStreakUtils._playerActivityScore:322-326 `penaltyBps = curse * 100; bonusBps = bonusBps
///   > penaltyBps ? bonusBps - penaltyBps : 0`) is proven against the public playerActivityScore view AND a
///   frozen snapshot (the afking lootbox sub's `scorePlus1`, GameAfkingModule:863-870, frozen at delivery and
///   read from the Sub slot). To exercise the APPLY independently of the SET, the curse counter is seeded
///   directly via vm.store — the active-afker exemption blocks the SET, never the APPLY.
///
/// @dev Reuses the funded-sub + new-day STAGE harness from V56FreezeSolvency. Staleness is controlled by
///   warping the day clock (lastEthDay stays 0 for a vm.store-seeded claimant ⇒ stale once _currentMintDay()
///   >= 5). Seeded-fuzz deterministic (foundry seed 0xdeadbeef). Test-only: ZERO contracts/*.sol mutation.
contract V61CurseSet is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + mintPacked_ field shifts (378-01 key + BitPackingLib)
    // -------------------------------------------------------------------------
    uint256 private constant BALANCES_PACKED_SLOT = 7; // [afking:hi128 | claimable:lo128]
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant SUBOF_SLOT = 62;

    // mintPacked_ field shifts (BitPackingLib).
    uint256 private constant DAY_SHIFT = 72; // lastEthDay (32 bits)
    uint256 private constant FROZEN_UNTIL_LEVEL_SHIFT = 128; // (24 bits)
    uint256 private constant WHALE_BUNDLE_TYPE_SHIFT = 152; // (2 bits)
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS (1 bit)
    uint256 private constant AFFILIATE_BONUS_LEVEL_SHIFT = 185; // (24 bits)
    uint256 private constant AFFILIATE_BONUS_POINTS_SHIFT = 209; // (6 bits)
    uint256 private constant CURSE_COUNT_SHIFT = 215; // (8 bits)

    uint256 private constant OFF_SCOREPLUS1 = 6; // uint16 scorePlus1 in the Sub slot (V56 offset)
    uint256 private constant CURSE_COUNT_CAP = 20;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        // maybeCurse's staleness basis is _currentMintDay() == dailyIdx (the monotonic advance counter, NOT
        // the wall clock). At fresh deploy dailyIdx == 1, so a lastEthDay-0 claimant would read as non-stale
        // (0 + 5 > 1). Seed dailyIdx to 100 (field-isolated RMW on slot 0) so a lastEthDay-0 claimant is stale
        // by construction (0 + 5 <= 100), and a "today" claimant (lastEthDay == 100) is non-stale.
        _seedDailyIdx(100);
    }

    // =========================================================================
    // SET: +2 on a stale ghost-cashout via the public claimWinnings
    // =========================================================================

    /// @notice A stale (>=5d inactive) claimant who cashes out via the PUBLIC claimWinnings gets curseCountOf
    ///         == 2. Non-vacuous: curseCountOf is asserted 0 BEFORE the claim and exactly 2 after.
    function testStaleCashoutSetsCursePlusTwo() public {
        address p = makeAddr("set_stale");
        _seedClaimable(p, 10 ether); // claimable to cash out; lastEthDay stays 0 ⇒ stale at day ~30
        assertEq(game.curseCountOf(p), 0, "pre: no curse");

        vm.prank(p);
        game.claimWinnings(p);

        assertEq(game.curseCountOf(p), 2, "stale cashout SET: curse += 2");
    }

    // =========================================================================
    // Exemptions — each proven BY CONTRAST (exempt == 0 vs non-exempt == 2)
    // =========================================================================

    /// @notice Infra (VAULT/SDGNRS/GNRUS) is never cursed (the redemption-snapshot-integrity skip), while an
    ///         equivalent ordinary stale claimant IS cursed. The contrast proves the infra bail.
    function testInfraExemptByContrast() public {
        address[3] memory infra = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        for (uint256 i; i < 3; i++) {
            _seedClaimable(infra[i], 10 ether);
            vm.prank(infra[i]);
            game.claimWinnings(infra[i]);
            assertEq(game.curseCountOf(infra[i]), 0, "infra exempt: curse stays 0");
        }
        // Contrast: an ordinary stale claimant in the same conditions IS cursed.
        assertEq(_cashoutCurseOf(makeAddr("infra_contrast")), 2, "contrast: ordinary stale claimant cursed +2");
    }

    /// @notice A non-stale claimant (lastEthDay close to the current day) is NOT cursed, while a stale one is.
    function testNonStaleExemptByContrast() public {
        address fresh = makeAddr("nonstale");
        _seedClaimable(fresh, 10 ether);
        _seedLastEthDay(fresh, _currentDay()); // claimed/minted "today" ⇒ lastEthDay + 5 > currentDay ⇒ exempt
        vm.prank(fresh);
        game.claimWinnings(fresh);
        assertEq(game.curseCountOf(fresh), 0, "non-stale exempt: curse stays 0");

        assertEq(_cashoutCurseOf(makeAddr("stale_contrast")), 2, "contrast: stale claimant cursed +2");
    }

    /// @notice A deity-pass holder is exempt, while a pass-less equivalent stale claimant is cursed.
    function testDeityPassExemptByContrast() public {
        address deity = makeAddr("deity_exempt");
        _seedClaimable(deity, 10 ether);
        _grantDeityPass(deity);
        vm.prank(deity);
        game.claimWinnings(deity);
        assertEq(game.curseCountOf(deity), 0, "deity-pass exempt: curse stays 0");

        assertEq(_cashoutCurseOf(makeAddr("deity_contrast")), 2, "contrast: pass-less stale claimant cursed +2");
    }

    /// @notice A whale/lazy-pass holder (frozenUntilLevel >= level && bundleType ∈ {1,3}) is exempt, while an
    ///         equivalent pass-less stale claimant is cursed.
    function testWhalePassExemptByContrast() public {
        address whale = makeAddr("whale_exempt");
        _seedClaimable(whale, 10 ether);
        _grantWhalePass(whale, 1); // bundleType 1 (10-level), frozenUntilLevel high
        vm.prank(whale);
        game.claimWinnings(whale);
        assertEq(game.curseCountOf(whale), 0, "whale-pass exempt: curse stays 0");

        assertEq(_cashoutCurseOf(makeAddr("whale_contrast")), 2, "contrast: pass-less stale claimant cursed +2");
    }

    /// @notice An active afker (_subOf[p].dailyQuantity != 0) is exempt, while a non-subscribed equivalent
    ///         stale claimant is cursed. The active afker is set up with a real funded subscription.
    function testActiveAfkerExemptByContrast() public {
        address afk = makeAddr("afker_exempt");
        _grantDeityPass(afk); // pass-required subscribe gate; deity covers it
        _fundPool(afk, 50 ether);
        _subscribeLootbox(afk, 1); // dailyQuantity != 0 now
        // Seed claimable AFTER subscribing so the claim has something to cash out (subscribe doesn't credit
        // claimable). The deity pass would ALSO exempt — so prove the afker bail in isolation by clearing the
        // deity bit first, leaving ONLY the active-afker condition.
        _clearDeityPass(afk);
        _seedClaimable(afk, 10 ether);
        assertTrue(_dailyQtyOf(afk) != 0, "setup: active afker (dailyQuantity != 0)");

        vm.prank(afk);
        game.claimWinnings(afk);
        assertEq(game.curseCountOf(afk), 0, "active-afker exempt: curse stays 0");

        assertEq(_cashoutCurseOf(makeAddr("afker_contrast")), 2, "contrast: non-subscribed stale claimant cursed +2");
    }

    /// @notice gameOver suppresses the SET: post-gameOver a stale cashout does NOT curse (proven by driving
    ///         the game to its terminal state), while a pre-gameOver equivalent stale claimant IS cursed.
    function testGameOverExemptByContrast() public {
        // Contrast first (pre-gameOver), since the gameOver path is terminal for the fixture.
        assertEq(_cashoutCurseOf(makeAddr("go_contrast")), 2, "contrast: pre-gameOver stale claimant cursed +2");

        address p = makeAddr("go_exempt");
        _seedClaimable(p, 10 ether);
        _forceGameOver();
        assertTrue(game.gameOver(), "setup: gameOver active");

        // Post-gameOver the claim pays out (claimable + afking merge) but maybeCurse bails on the gameOver
        // guard — curseCountOf stays 0.
        vm.prank(p);
        game.claimWinnings(p);
        assertEq(game.curseCountOf(p), 0, "gameOver exempt: curse stays 0");
    }

    // =========================================================================
    // The vault-only claimWinningsStethFirst NEVER curses
    // =========================================================================

    /// @notice claimWinningsStethFirst (restricted to the VAULT; vault-only self-claim) NEVER triggers
    ///         maybeCurse — a stale VAULT self-claim leaves curseCountOf at 0. (VAULT is also infra-exempt, so
    ///         this is doubly safe; the load-bearing fact is that the vault path never even calls maybeCurse.)
    function testStethFirstClaimNeverCurses() public {
        _seedClaimable(ContractAddresses.VAULT, 10 ether);
        vm.prank(ContractAddresses.VAULT);
        game.claimWinningsStethFirst();
        assertEq(game.curseCountOf(ContractAddresses.VAULT), 0, "claimWinningsStethFirst: never curses (vault-only path)");
    }

    // =========================================================================
    // Penalty: curse*100 bps, floored 0, across the public view + a frozen snapshot
    // =========================================================================

    /// @notice The public playerActivityScore view drops by EXACTLY curse*100 bps vs an un-cursed twin with an
    ///         identical positive base score. Falsifiable: the delta is pinned to curse*100 (not "<= base").
    function testPenaltyOnPublicViewExactBps() public {
        address cursed = makeAddr("pen_cursed");
        address twin = makeAddr("pen_twin");
        _seedAffiliateBase(cursed, 6); // +600 bps base (6 affiliate points at the current level)
        _seedAffiliateBase(twin, 6);
        _seedCurse(cursed, 4); // 4 points ⇒ -400 bps

        uint256 base = game.playerActivityScore(twin);
        uint256 penalized = game.playerActivityScore(cursed);
        assertEq(base, 600, "twin base score == 600 bps (6 affiliate points)");
        assertEq(penalized, base - 400, "cursed score == base - curse*100 (4*100)");
    }

    /// @notice The penalty floors at 0: a curse whose penalty exceeds the base score zeroes the score (never
    ///         underflows). curse=20 ⇒ -2000 bps applied to a 600-bps base ⇒ 0.
    function testPenaltyFlooredAtZero() public {
        address p = makeAddr("pen_floor");
        _seedAffiliateBase(p, 6); // +600 bps
        _seedCurse(p, 20); // -2000 bps > base
        assertEq(game.playerActivityScore(p), 0, "penalty floors the score at 0 (no underflow)");
    }

    /// @notice The penalty is visible in a FROZEN SNAPSHOT consumer: a funded lootbox sub's `scorePlus1`
    ///         (frozen at delivery, GameAfkingModule:863-870) is lower for a cursed sub than an un-cursed twin
    ///         by exactly the curse*100-bps penalty. Both subs share an identical positive base (affiliate
    ///         cache). The curse is seeded directly (the APPLY is independent of the active-afker SET bail).
    function testPenaltyOnFrozenAfkingSnapshot() public {
        address cursed = _setupFundedSub("snap_cursed");
        address twin = _setupFundedSub("snap_twin");
        _seedAffiliateBase(cursed, 6);
        _seedAffiliateBase(twin, 6);
        _seedCurse(cursed, 2); // -200 bps

        _deliverDay(0x5C0E); // freezes scorePlus1 for both subs at this delivery

        uint256 snapCursed = _scorePlus1Of(cursed);
        uint256 snapTwin = _scorePlus1Of(twin);
        assertGt(snapTwin, 1, "non-vacuity: the twin froze a positive score (scorePlus1 > 1)");
        // scorePlus1 == activityScore + 1; the cursed snapshot is exactly 200 bps lower.
        assertEq(snapTwin - snapCursed, 200, "frozen snapshot: cursed scorePlus1 lower by curse*100 (2*100)");
    }

    // =========================================================================
    // Stacking → min(2N, cap); saturates at the cap, never wraps the uint8
    // =========================================================================

    /// @notice N stale cashouts across N distinct days stack to min(2N, CURSE_COUNT_CAP). Pushing past the cap
    ///         leaves the counter at EXACTLY 20 (never wraps to a small uint8 value). Seeded fuzz over N.
    function testFuzzStackingSaturatesAtCapNoWrap(uint8 nSeed) public {
        address p = makeAddr("stack");
        uint256 n = bound(uint256(nSeed), 1, 15); // up to 30 raw points ⇒ exercises the 20-cap saturation
        _seedClaimable(p, 1000 ether);

        for (uint256 i; i < n; i++) {
            // Advance the day so each cashout is a fresh stale event (lastEthDay stays 0 the whole time, and
            // the claim leaves a sentinel so re-seeding is not needed — top up to keep claimable > 1).
            _t += 1 days;
            vm.warp(_t);
            _topUpClaimable(p, 5 ether);
            vm.prank(p);
            game.claimWinnings(p);

            uint256 expected = (2 * (i + 1)) > CURSE_COUNT_CAP ? CURSE_COUNT_CAP : 2 * (i + 1);
            assertEq(game.curseCountOf(p), expected, "stacking: curseCountOf == min(2N, cap)");
        }
        // After the loop the counter never exceeded the cap and is a valid uint8 (no wrap).
        assertLe(game.curseCountOf(p), CURSE_COUNT_CAP, "saturation: never exceeds the cap");
        if (n >= 10) assertEq(game.curseCountOf(p), CURSE_COUNT_CAP, "saturation: pinned at exactly 20 once past the cap");
    }

    // =========================================================================
    // Same-day second claim reverts (sentinel) → no in-day stacking
    // =========================================================================

    /// @notice A same-day SECOND claim reverts (the 1-wei sentinel means the second claim has nothing to
    ///         cash out ⇒ claimWinnings reverts E()), so the curse cannot stack twice within one day.
    function testSameDaySecondClaimRevertsNoInDayStack() public {
        address p = makeAddr("sameday");
        _seedClaimable(p, 10 ether);

        vm.prank(p);
        game.claimWinnings(p); // first claim: drains to the sentinel, sets curse to 2
        assertEq(game.curseCountOf(p), 2, "first claim cursed +2");

        // Second claim same day: claimable is at the 1-wei sentinel ⇒ nothing to claim ⇒ revert.
        vm.prank(p);
        vm.expectRevert();
        game.claimWinnings(p);

        assertEq(game.curseCountOf(p), 2, "no in-day stacking: curse unchanged after the reverted second claim");
    }

    // =========================================================================
    // Helpers — curse SET driver + contrast
    // =========================================================================

    /// @dev Drive a clean ordinary stale cashout for a FRESH address and return the resulting curse count.
    function _cashoutCurseOf(address p) internal returns (uint8) {
        _seedClaimable(p, 10 ether);
        vm.prank(p);
        game.claimWinnings(p);
        return game.curseCountOf(p);
    }

    function _setupFundedSub(string memory name) internal returns (address a) {
        a = makeAddr(name);
        _grantDeityPass(a);
        _fundPool(a, 100 ether);
        _subscribeLootbox(a, 1);
        _clearDeityPass(a); // remove the deity score bonus so the affiliate base is the sole positive score
    }

    // =========================================================================
    // Seeders (vm.store on the canonical layout)
    // =========================================================================

    function _seedClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 oldLow = uint128(packed);
        uint256 high = packed >> 128;
        vm.store(address(game), slot, bytes32((high << 128) | uint128(amount)));
        _bumpClaimablePool(int256(amount) - int256(oldLow));
    }

    function _topUpClaimable(address who, uint256 delta) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 low = uint128(packed);
        uint256 high = packed >> 128;
        vm.store(address(game), slot, bytes32((high << 128) | uint128(low + delta)));
        _bumpClaimablePool(int256(delta));
    }

    function _bumpClaimablePool(int256 delta) internal {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 lowOther = slot1 & ((uint256(1) << (CLAIMABLE_POOL_OFFBYTES * 8)) - 1);
        uint256 pool = (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
        uint256 newPool = delta >= 0 ? pool + uint256(delta) : pool - uint256(-delta);
        vm.store(
            address(game),
            bytes32(uint256(CLAIMABLE_POOL_SLOT)),
            bytes32(lowOther | (uint256(uint128(newPool)) << (CLAIMABLE_POOL_OFFBYTES * 8)))
        );
    }

    function _seedField(address who, uint256 shift, uint256 mask, uint256 value) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(mask << shift);
        packed |= (value & mask) << shift;
        vm.store(address(game), slot, bytes32(packed));
    }

    function _seedCurse(address who, uint256 points) internal {
        _seedField(who, CURSE_COUNT_SHIFT, 0xFF, points);
    }

    function _seedLastEthDay(address who, uint256 day) internal {
        _seedField(who, DAY_SHIFT, 0xFFFFFFFF, day);
    }

    /// @dev Seed the cached affiliate bonus (points at the CURRENT level) so the player has a positive base
    ///      activity score that the curse penalty can be measured against. Sets both the points and the level
    ///      so the cache is considered current by _playerActivityScore.
    function _seedAffiliateBase(address who, uint256 points) internal {
        _seedField(who, AFFILIATE_BONUS_POINTS_SHIFT, 0x3F, points); // 6-bit field
        _seedField(who, AFFILIATE_BONUS_LEVEL_SHIFT, 0xFFFFFF, game.level()); // cache "current"
    }

    function _grantDeityPass(address who) internal {
        _seedField(who, DEITY_SHIFT, 0x1, 1);
    }

    function _clearDeityPass(address who) internal {
        _seedField(who, DEITY_SHIFT, 0x1, 0);
    }

    /// @dev Grant a whale/lazy pass: bundleType (1 or 3) + frozenUntilLevel high enough to cover the level.
    function _grantWhalePass(address who, uint256 bundleType) internal {
        _seedField(who, FROZEN_UNTIL_LEVEL_SHIFT, 0xFFFFFF, uint256(game.level()) + 100);
        _seedField(who, WHALE_BUNDLE_TYPE_SHIFT, 0x3, bundleType);
    }

    // =========================================================================
    // Reads
    // =========================================================================

    /// @dev The staleness basis maybeCurse uses: _currentMintDay() == dailyIdx (slot 0, byte 3, uint24) when
    ///      non-zero. Read it directly so the non-stale contrast seeds lastEthDay to the live mint day.
    function _currentDay() internal view returns (uint256) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (slot0 >> 24) & 0xFFFFFF;
    }

    /// @dev Field-isolated seed of dailyIdx (slot 0, byte 3, uint24) — preserves every other slot-0 field
    ///      (purchaseStartDay, level, gameOver, the FSM flags).
    function _seedDailyIdx(uint256 day) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        slot0 &= ~(uint256(0xFFFFFF) << 24);
        slot0 |= (day & 0xFFFFFF) << 24;
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, 0, 8));
    }

    function _scorePlus1Of(address who) internal view returns (uint256) {
        return _subField(who, OFF_SCOREPLUS1, 16);
    }

    // =========================================================================
    // gameOver trigger
    // =========================================================================

    /// @dev Force the terminal gameOver state by setting the liveness/timeout reachable path: warp past the
    ///      level-0 deploy-idle timeout and advance until gameOver latches.
    function _forceGameOver() internal {
        // Level 0 deploy-idle timeout fires liveness; advancing then drains to terminal gameOver.
        _t += 400 days;
        vm.warp(_t);
        for (uint256 d; d < 240 && !game.gameOver(); d++) {
            _fulfillPending(uint256(keccak256(abi.encode("go", d))) | 1);
            if (game.advanceDue() || game.rngLocked()) {
                try game.advanceGame() {} catch {}
            }
            _fulfillPending(uint256(keccak256(abi.encode("go2", d))) | 1);
            if (!game.advanceDue() && !game.rngLocked() && !game.gameOver()) {
                // nudge the clock so the timeout path keeps progressing
                _t += 1 days;
                vm.warp(_t);
            }
        }
    }

    // =========================================================================
    // STAGE / sub harness (ported from V56FreezeSolvency)
    // =========================================================================

    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
    }

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
        game.subscribe(address(0), false, false, q, 0, address(0));
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }
}
