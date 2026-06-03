// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @title V56SubHardening -- the D-14 positive proofs for the 357-00 subscribe-hardening gates
///        (D-11 pass-required / D-12 purchase-grounded / D-13 VAULT/sDGNRS bootstrap exemption) and the
///        F-356-01 drainAffiliateBase Game dispatch-stub reachability. Run against the re-frozen audit
///        subject HEAD' = ac5f1e033a785d18a9f0b89b7de5d05268431dbd (the sole .sol commit of phase 357).
///
/// @notice The three 357-00 gates as built (GameAfkingModule.subscribe, the UPSERT branch):
///   - D-11 (NoPass, :369): `if (!exemptSub && s.validThroughLevel < level) revert NoPass();` where
///     `s.validThroughLevel = _passHorizonOf(subscriber)` (:364) — the deity sentinel `type(uint24).max`
///     always covers; a finite frozenUntilLevel covers iff it reaches the live `level`. Fires on ANY
///     UPSERT subscribe (new OR re-sub) whose stored horizon is below the live level.
///   - D-12 (MustPurchaseToBeginAfking, :483): in the NEW-run leg (`!wasActive`), when the subscriber is
///     not grounded on a real purchase — neither `done[0]` (manual slot-0 today) NOR a funded in-tx
///     cover-buy executes — the start reverts. VAULT/sDGNRS take the `else if (exemptSub)` base-0
///     bootstrap branch (:475) instead of reverting.
///   - D-13 (exemptSub, :359-360): `subscriber == ContractAddresses.VAULT || subscriber ==
///     ContractAddresses.SDGNRS` short-circuits BOTH gates, keyed on the un-spoofable resolved
///     subscriber identity (:278). Load-bearing for the construction-time VAULT/sDGNRS self-subscribe.
///   - The per-iter crossing eviction (:969 `currentLevel > sub.validThroughLevel`) is KEPT — a pass
///     valid at subscribe can be outgrown; the STAGE re-reads the horizon and EVICTS (tombstone) without
///     reverting.
///
/// @notice F-356-01 (drainAffiliateBase Game dispatch stub, DegenerusGame.sol:428): the guard-less
///   delegatecall to GAME_AFKING_MODULE.drainAffiliateBase (mirrors claimAfkingBurnie), `_revertDelegate`
///   on failure, `data.length == 0` guard, `abi.decode(data,(uint256))` return tail (mirrors
///   runDecimatorJackpot). The module impl owns the AFFILIATE-only access gate
///   (GameAfkingModule.sol:1328 `if (msg.sender != ContractAddresses.AFFILIATE) revert NotApproved()`),
///   which under delegatecall sees `msg.sender` as the caller of the Game stub. So the affiliate path
///   (msg.sender == AFFILIATE) drains-and-zeroes; any other caller reverts NotApproved().
///
/// @dev Copies the V56SecUnmanipulable harness VERBATIM (the v56 Sub-slot offset block + the delivery
///   helpers + the deity/level/validThroughLevel pokes + the funded/unfunded pool helpers — NOT the stale
///   v55 offsets), adding a finite-(non-deity)-pass poke and a level poke for the D-11 finite/negative
///   arms. Test-only: ZERO contracts/*.sol mutation.
contract V56SubHardening is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the v56 Sub-slot offset block (V56SecUnmanipulable:44-67)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 66;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // mapping(address => uint256) _subscriberIndex (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 10;       // mintPacked_ mapping root (deity bit @ 184, frozenUntil @ 128)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31
    uint256 private constant OFF_DAILY = 0;           // uint8  dailyQuantity        (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1;     // uint24 validThroughLevel    (bytes 1..3)
    uint256 private constant OFF_LASTBOUGHT = 11;     // uint24 lastAutoBoughtDay    (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14;     // uint24 lastOpenedDay        (bytes 14..16)
    uint256 private constant OFF_AFKCOVERED = 17;     // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_AFKINGSTART = 20;    // uint24 afkingStartDay       (bytes 20..22)
    uint256 private constant OFF_AFFBASE = 23;        // uint32 affiliateBase        (bytes 23..26)
    uint256 private constant OFF_PENDINGBURNIE = 27;  // uint32 pendingBurnie        (bytes 27..30)
    uint256 private constant OFF_STREAKLATCH = 31;    // uint8  subStreakLatch       (byte 31)

    uint256 private constant DEITY_SHIFT = 184;       // HAS_DEITY_PASS_SHIFT in mintPacked_
    uint256 private constant FROZEN_UNTIL_SHIFT = 128; // FROZEN_UNTIL_LEVEL_SHIFT (uint24) in mintPacked_

    /// @dev The game `level` lives in slot 0 at byte 14 (uint24) — poked up to drive the D-11 negative /
    ///      finite-pass arms and the crossing eviction (the fixture level does not advance organically).
    uint256 private constant LEVEL_OFF = 14;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = pass-evict / funding-kill.
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
    // D-11 — pass-required subscribe (NoPass on the UPSERT branch)
    // =========================================================================

    /// @notice D-11 NEGATIVE: a passless EOA whose stored horizon (`_passHorizonOf == 0`) is below the
    ///         live level reverts NoPass() on an UPSERT subscribe (dailyQuantity >= 1). The fixture level
    ///         is poked up so `validThroughLevel(0) < level` holds (at level 0 the gate is vacuously
    ///         satisfied). NoPass fires at :369, ahead of the D-12 grounding gate, so the EOA is funded
    ///         to isolate the pass failure.
    function testD11PasslessEoaRevertsNoPass() public {
        address p = makeAddr("d11_nopass");
        _setLevel(5);                 // currentLevel = 5 > validThroughLevel(0) for a passless EOA
        _fundPool(p, 50 ether);       // funded, so the revert can ONLY be NoPass (not MustPurchase)
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("NoPass()"));
        game.subscribe(address(0), false, false, 1, 0, address(0));
        assertEq(_subscriberIndexOf(p), 0, "D-11: the passless sub was never created");
    }

    /// @notice D-11 POSITIVE (finite pass): an EOA whose finite frozenUntilLevel horizon reaches the live
    ///         level passes D-11 and subscribes successfully (funded so D-12 is also satisfied). Proves a
    ///         non-deity pass covering currentLevel clears the gate.
    function testD11FinitePassCoveringCurrentLevelSubscribes() public {
        address p = makeAddr("d11_finite");
        _setLevel(5);
        _grantFinitePass(p, 9);       // frozenUntilLevel = 9 >= level(5) -> horizon covers
        _fundPool(p, 50 ether);
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, 0, address(0)); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-11: finite-pass sub created");
        assertEq(_validThroughLevelOf(p), 9, "D-11: validThroughLevel stamped to the finite horizon");
    }

    /// @notice D-11 POSITIVE (deity bypass): a deity holder (deity bit set -> horizon == type(uint24).max)
    ///         subscribes at any level. The sentinel always covers, so the gate never reverts for deity.
    function testD11DeityHolderBypassesPassGate() public {
        address p = makeAddr("d11_deity");
        _setLevel(5);
        _grantDeityPass(p);           // _passHorizonOf == type(uint24).max
        _fundPool(p, 50 ether);
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, 0, address(0)); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-11: deity sub created (sentinel covers)");
        assertEq(_validThroughLevelOf(p), uint32(type(uint24).max), "D-11: deity validThroughLevel == sentinel");
    }

    // =========================================================================
    // D-12 — purchase-grounded subscribe (MustPurchaseToBeginAfking on the unfunded NEW run)
    // =========================================================================

    /// @notice D-12 NEGATIVE: a pass-holding (deity, so D-11 is cleared) but UNFUNDED EOA reverts
    ///         MustPurchaseToBeginAfking() on a NEW-run UPSERT subscribe — neither bought-today (`done[0]`)
    ///         nor a funded in-tx cover-buy, so the start would free-ride the advance gate. The revert is
    ///         the D-12 leg at :483 (the unfunded NEW-run else branch), NOT NoPass (the deity bit clears
    ///         D-11), isolating the grounding failure.
    function testD12UnfundedEoaRevertsMustPurchase() public {
        address p = makeAddr("d12_unfunded");
        _grantDeityPass(p);           // clears D-11; isolates the D-12 grounding failure
        // NO _fundPool: afkingFunding[p] == 0 -> the cover-buy is unfunded -> the NEW-run start reverts.
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("MustPurchaseToBeginAfking()"));
        game.subscribe(address(0), false, false, 1, 0, address(0));
        assertEq(_subscriberIndexOf(p), 0, "D-12: the unfunded sub was never created");
    }

    /// @notice D-12 POSITIVE (funded): a pass-holding EOA pre-funded so the in-tx cover-buy executes
    ///         subscribes successfully (the funded NEW-run leg at :462-474 keeps the snapshot + delivers
    ///         the buy). No MustPurchase revert.
    function testD12FundedEoaSubscribes() public {
        address p = makeAddr("d12_funded");
        _grantDeityPass(p);
        _fundPool(p, 50 ether);       // funds the cover-buy -> grounded NEW run
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, 0, address(0)); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-12: funded sub created");
        assertEq(_lastBoughtDayOf(p), uint32(game.currentDayView()), "D-12: the funded cover-buy delivered today");
    }

    /// @notice D-12 POSITIVE (already-bought-today re-sub): an ACTIVE sub re-subscribe (`wasActive`) skips
    ///         the NEW-run grounding gate entirely — D-12 fires only on the NEW-run leg. A funded sub that
    ///         already delivered today re-subscribes with no MustPurchase revert (the no-orphan / bought-
    ///         today skip preserves the run). Proves D-12 never reverts a genuinely-grounded re-subscribe.
    function testD12ActiveResubAlreadyGroundedNoRevert() public {
        address p = makeAddr("d12_resub");
        _grantDeityPass(p);
        _fundPool(p, 80 ether);       // fund BEFORE subscribe so the NEW-run cover-buy is grounded (D-12)
        _subscribeLootbox(p, 1);      // grounded NEW run (deity clears D-11, funded clears D-12)
        _deliverDay(_singleton(p), 0xD12E50); // an active funded run; box opened, bought today
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: the sub is active");
        // Re-subscribe the active sub (wasActive == true) — the NEW-run D-12 gate is not on this path.
        vm.prank(p);
        game.subscribe(address(0), false, false, 1, 0, address(0)); // MUST NOT revert (grounded re-sub)
        assertGt(_subscriberIndexOf(p), 0, "D-12: grounded re-sub stays active (no MustPurchase revert)");
    }

    // =========================================================================
    // D-13 — VAULT / sDGNRS bootstrap exemption (no pass + unfunded still subscribes)
    // =========================================================================

    /// @notice D-13 (VAULT exempt): VAULT subscribes with NO pass and UNFUNDED and is NOT reverted by
    ///         either gate — the `exemptSub` short-circuit (D-11 via `!exemptSub`, D-12 via the
    ///         `else if (exemptSub)` base-0 bootstrap). Drives the gate against a poked-up level so a
    ///         non-exempt no-pass sub WOULD trip NoPass, proving the carve-out is what lets VAULT through.
    ///         Self-subscribe shape (`subscribe(address(this), ...)`) keyed on the resolved identity.
    function testD13VaultExemptSubscribesNoPassUnfunded() public {
        _setLevel(5);                 // a non-exempt no-pass sub at this level would revert NoPass
        vm.prank(ContractAddresses.VAULT);
        game.subscribe(ContractAddresses.VAULT, true, false, 1, 0, address(0)); // no pass, unfunded
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "D-13: VAULT exempt subscribe succeeded (no NoPass / no MustPurchase)");
    }

    /// @notice D-13 (sDGNRS exempt): sDGNRS subscribes with NO pass and UNFUNDED and is NOT reverted —
    ///         the same pinned-identity exemption. Both protocol self-subscribers bootstrap at
    ///         construction with no pass + no funds; the gates MUST carve them out or deploy breaks.
    function testD13SdgnrsExemptSubscribesNoPassUnfunded() public {
        _setLevel(5);
        vm.prank(ContractAddresses.SDGNRS);
        game.subscribe(ContractAddresses.SDGNRS, true, false, 1, 0, address(0)); // no pass, unfunded
        assertGt(_subscriberIndexOf(ContractAddresses.SDGNRS), 0, "D-13: sDGNRS exempt subscribe succeeded (no NoPass / no MustPurchase)");
    }

    // =========================================================================
    // Crossing eviction KEPT — a pass valid at subscribe is still evicted when outgrown
    // =========================================================================

    /// @notice The per-iter crossing eviction (:969) is KEPT under D-11/D-12: a sub with a pass VALID at
    ///         subscribe (deity sentinel) is later EVICTED via the crossing path (tombstone, reason-1
    ///         SubscriptionExpired, MUST NOT revert) once the deity bit is cleared + validThroughLevel is
    ///         poked below a poked-up level. Mirrors V56SecUnmanipulable's Hook-C eviction proof: D-11 is
    ///         a subscribe-time gate; the crossing eviction remains the runtime outgrow handler.
    function testCrossingEvictionStillEvictsOutgrownPass() public {
        address p = makeAddr("crossing_evict");
        _grantDeityPass(p);           // valid pass AT subscribe (sentinel covers)
        _fundPool(p, 50 ether);       // fund BEFORE subscribe so the grounded NEW run is created (D-12)
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xC10551); // an active afking run; box opened (no pending-box skip)
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: sub active before the crossing");

        // Force the outgrow crossing: clear the deity bit (horizon -> finite 0), set a finite
        // validThroughLevel, poke the level above it -> the next STAGE takes the EVICT branch.
        _clearDeityPass(p);
        _setValidThroughLevel(p, 3);

        vm.recordLogs();
        _settleGame(uint256(keccak256("evict_pre")) | 1);
        _t += 1 days;
        vm.warp(_t);
        _setLevel(10);                // currentLevel(10) > validThroughLevel(3) -> crossing fires
        _settleGame(uint256(keccak256("evict_go")) | 1); // STAGE runs -> EVICT (MUST NOT revert)

        assertGt(_countExpired(p, 1), 0, "crossing: pass-eviction fired (SubscriptionExpired reason 1)");
        assertEq(_subscriberIndexOf(p), 0, "crossing: the outgrown sub was evicted (removed from set)");
    }

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
        _grantDeityPass(p);
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
        _grantDeityPass(p);
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
    // Protocol-driving helpers (ported VERBATIM from V56SecUnmanipulable + the finite-pass poke)
    // =========================================================================

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
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Grant `who` a FINITE (non-deity) pass horizon: poke mintPacked_ FROZEN_UNTIL_LEVEL_SHIFT
    ///      (bit 128, uint24) to `horizon` so `_passHorizonOf` returns that finite value (deity bit clear).
    function _grantFinitePass(address who, uint24 horizon) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << DEITY_SHIFT);             // ensure NOT deity (finite-horizon read)
        packed &= ~(uint256(0xFFFFFF) << FROZEN_UNTIL_SHIFT);
        packed |= (uint256(horizon) & 0xFFFFFF) << FROZEN_UNTIL_SHIFT;
        vm.store(address(game), slot, bytes32(packed));
    }

    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _setValidThroughLevel(address who, uint24 lvl) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed |= (uint256(lvl) & 0xFFFFFF) << (OFF_VALIDTHROUGH * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke the game `level` (slot 0, byte 14, uint24) so the D-11 negative/finite arms and the
    ///      crossing eviction fire (the fixture level does not advance organically over the harness loop).
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

    // ---- Sub-slot reads (slot 66 + the v56 offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _validThroughLevelOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_VALIDTHROUGH, 24));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _affiliateBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFFBASE, 32));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }
}
