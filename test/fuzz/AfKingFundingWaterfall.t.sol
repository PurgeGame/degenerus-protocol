// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title AfKingFundingWaterfall -- Proves the v55.0 game-resident afking per-player funding waterfall
///        (SUB-05), the two-tier pinned-identity funding-skip kill (SUB-06), the OPEN-E shared funding
///        source ETH-routing (OPENE-02/03 + LANDMINE A), and the pass-eviction-preserves-fundingSource
///        property. The funding waterfall now debits the IN-CONTEXT `afkingFunding[src]` SLOAD
///        (GameAfkingModule.sol:709, the `claimablePool -=` tandem at :710) — NOT a cross-contract
///        staticcall. Feeds TST-02's "fuzz random FUNDED well-formed slice inputs" (CONTEXT D-351-04).
///
/// @notice Funding waterfall (SUB-05), inside the process STAGE per player (GameAfkingModule._resolveBuy
///         :440-496):
///   - drainGameCreditFirst == false -> DirectEth, ethValue = cost (pays afkingFunding ETH only).
///   - drainGameCreditFirst == true:
///       * claimable cred > cost          -> Claimable, ethValue = 0 (pays from claimable only).
///       * 1 < cred <= cost               -> Combined,  ethValue = cost - (cred - 1) (afkingFunding tops up).
///       * cred <= 1                      -> DirectEth, ethValue = cost.
///   - afkingFunding[src] < ethValue       -> InsufficientPool funding skip (the kill / exempt branch).
///
/// @notice Two-tier skip-kill (SUB-06), on the InsufficientPool funding skip (GameAfkingModule.sol:661-682):
///   - a NORMAL sub is CANCELLED via swap-pop (dailyQuantity 0, SubscriptionExpired(player,1)),
///     continuing WITHOUT advancing the cursor.
///   - the VAULT and SDGNRS subs are EXEMPT -- they persist (no-op-and-retry, PlayerSkipped(player,3),
///     stay in the set), keyed on the UN-SPOOFABLE pinned ContractAddresses.VAULT / SDGNRS identity.
///   - NO settable exemption flag exists: the exemption is purely the pinned-address equality branch.
///
/// @notice OPEN-E four-protection re-attest (the per-day ETH draw routing surface):
///   - Consent-gate-at-subscribe: a non-zero non-self fundingSource MUST be operator-approved by the
///     source for the subscriber AT subscribe (GameAfkingModule.sol:259-265); no later re-check.
///   - Default-self: subscribe with fundingSource = address(0) stores `_fundingSourceOf == address(0)`
///     and the STAGE resolves `src = player` (self-pay) -- the ETH draw debits the subscriber's own
///     afkingFunding bucket.
///   - No-escalation: a revoke AFTER subscribe does NOT escalate; the STAGE keeps debiting S until S defunds.
///   - Trust-the-sub: the sub is the consent unit (revoke is moot; stop = M cancels or S defunds).
///
/// @notice PASS-EVICTION-PRESERVES-FUNDINGSOURCE: at the EVICT branch the STAGE writes only
///         `sub.dailyQuantity = 0; _removeFromSet(player)` -- the OTHER Sub fields are NOT deleted (only
///         the cancel-tombstone RECLAIM path does `delete _subOf[player]`). A sub evicted at a level
///         crossing leaves `_fundingSourceOf[player]` readable post-eviction.
///
/// @dev D-351-01 deltas applied: afKing.subscribe -> game.subscribe; afKing.autoBuy -> the mineFlip()
///      STAGE; afKing.poolOf -> afkingFundingOf; afKing.depositFor -> depositAfkingFunding; the standalone
///      afKing.setMode/setDrainGameCreditFirst setters (GONE) -> the flags are set via game.subscribe;
///      the deleted standalone-contract source-grep -> repointed to GameAfkingModule.sol. RE-DERIVED
///      every pinned slot via `forge inspect storage DegenerusGame`. Test-only: no contracts/*.sol mutated.
contract AfKingFundingWaterfall is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root
    uint256 private constant FUNDINGSOURCE_SLOT = GameSlots.FUNDING_SOURCE_OF; // _fundingSourceOf mapping root
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit)
    uint256 private constant GAME_CLAIMABLE_SLOT = GameSlots.BALANCES_PACKED; // claimableWinnings mapping root

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:2341; the AFKing-Coin repack dropped
    // validThroughLevel entirely — sub <=> coin is the sole credential now — shifting every field
    // after it down 3 bytes).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9)

    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;

    bytes32 private constant SKIPPED_SIG = keccak256("PlayerSkipped(uint32,uint8)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev Per-player funding-SOURCE afkingFunding snapshot — the charged ETH slice = the source delta
    ///      across the STAGE (the storage-stamp oracle, the GASOPT-04 successor to the deleted AutoBought).
    mapping(address => uint256) private _srcFundBefore;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }


    // =========================================================================
    // Task 3c -- No settable exemption flag (grep-clean, complements the runtime tests)
    // =========================================================================

    /// @notice SUB-06 spoof-resistance: the exemption is the pinned-address equality branch ONLY. A
    ///         source grep over the game-resident GameAfkingModule.sol finds zero settable-exemption
    ///         symbols; the ONLY exemption surface is the pinned-address equality (present).
    /// @dev    Δ: repointed from the deleted `contracts/AfKing.sol` to `contracts/modules/GameAfkingModule.sol`.
    function testNoSettableExemptionFlagSymbol() public view {
        string memory src = vm.readFile("contracts/modules/GameAfkingModule.sol");
        assertFalse(_contains(src, "isExempt"), "no isExempt symbol (no settable exemption flag)");
        assertFalse(_contains(src, "exemptFlag"), "no exemptFlag symbol");
        assertFalse(_contains(src, "skipKillExempt"), "no skipKillExempt symbol");
        assertTrue(_contains(src, "ContractAddresses.VAULT"), "the pinned-VAULT exemption branch exists");
        assertTrue(_contains(src, "ContractAddresses.SDGNRS"), "the pinned-SDGNRS exemption branch exists");
    }


    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE mineFlip() (no full settle) — the
    ///      STAGE is strictly PRE-RNG so the funding waterfall / eviction completes before rngGate, and a
    ///      single advance never reaches the level-transition charity call. Subs must be pre-registered.
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
    }

    /// @dev Arm the charged-slice oracle for the single tracked sub, run the STAGE once, drain logs.
    ///      (The waterfall tests track exactly one sub for the ethValue assertion; the kill tests use
    ///      `_runStageOnce` + `_capture` directly.)
    function _stageCapture(address tracked) internal {
        _armSlice(tracked);
        vm.recordLogs();
        _runStageOnce();
        _capture();
    }

    /// @dev Settle the game to a clean state (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev Set up a cross-account sub: source S approves M on the game, M self-subscribes with
    ///      fundingSource = S (ticket mode, qty 1).
    function _approvedSourceSub(string memory sLabel, string memory mLabel) internal returns (address s, address m) {
        s = makeAddr(sLabel);
        m = makeAddr(mLabel);
        uint32 sId = _aid(s);
        uint32 mId = _aid(m);
        uint256 seat = _grantSeat(m);
        vm.prank(s);
        game.setAfkingFundingApproval(0, mId, true); // S approves M's key -> fundingSource = S honored at subscribe
        vm.prank(m);
        game.subscribe(0, false, true, 1, sId, seat); // ticket mode, qty 1, source = S
    }

    /// @dev Per-day cost for qty `q` = mintPrice * q. Ticket mode.
    function _cost(uint256 q) internal view returns (uint256) {
        return game.mintPrice() * q;
    }

    /// @dev Subscribe a fresh player in TICKET mode (so the box-open leg never sees it), qty 1, granted
    ///      deity so it survives any crossing (the funding waterfall, not pass-gating, is the subject).
    function _subscribeHealthy(string memory prefix, bool drainFirst) internal returns (address who) {
        who = makeAddr(string(abi.encodePacked(prefix, "p")));
        _grantDeityPass(who);
        _aid(who);
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, drainFirst, true, 1, 0, seat); // self, drainFirst, ticket mode, qty 1
    }

    /// @dev Prep an existing SUB-09 sub (VAULT/SDGNRS) to REACH the funding waterfall: re-subscribe it in
    ///      ticket + drain-first mode (the standalone setMode/setDrainGameCreditFirst setters are GONE —
    ///      the flags are set via subscribe), sentinel claimable so DirectEth ethValue == cost. Bucket
    ///      left empty by the caller.
    function _prepExemptSub(address who) internal {
        vm.prank(who);
        game.subscribe(0, /*drainFirst*/ true, /*useTickets*/ true, 1, 0, 0); // exempt: no seat burned
        _setClaimable(who, 1); // sentinel -> DirectEth
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding).
    function _fundPool(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Force `who`'s claimableWinnings to `amount` (RE-DERIVED slot 7) AND credit `claimablePool`
    ///      (slot 1, offset 16, uint128) in TANDEM so the SOLVENCY-01 invariant
    ///      `claimablePool == Σ claimableWinnings + Σ afkingFunding` holds — otherwise the contract's
    ///      `claimablePool -=` on a claimable-funded buy underflows (a test-fixture artifact, not a
    ///      contract bug). Mirrors the contract's own tandem credit.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 cwSlot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(GAME_CLAIMABLE_SLOT)));
        uint256 prev = uint256(vm.load(address(game), cwSlot));
        vm.store(address(game), cwSlot, bytes32(amount));
        // claimablePool += (amount - prev) in tandem (keep the master invariant balanced).
        bytes32 s1 = bytes32(uint256(1));
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint128 pool = uint128(p1 >> 128); // claimablePool at offset 16 (the high 128 bits of slot 1)
        if (amount >= prev) {
            pool += uint128(amount - prev);
        } else {
            uint128 dec = uint128(prev - amount);
            pool = pool >= dec ? pool - dec : 0;
        }
        p1 = (p1 & ((uint256(1) << 128) - 1)) | (uint256(pool) << 128);
        vm.store(address(game), s1, bytes32(p1));
    }

    /// @dev Grant `who` the permanent deity bit (RE-DERIVED slot 10) — an activity-score/bounty-tier
    ///      flag, unrelated to the AFKing Subscription Token subscribe credential.
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev SUPERSEDED (AFKing Subscription Token credential change): the level-crossing eviction branch this
    ///      helper targeted (`validThroughLevel` + the refresh-or-evict check) is DELETED — a sub
    ///      is never evicted by level changes anymore, only by cancel, funding-skip kill, or the
    ///      coin's seat lock (an active sub's last coin cannot transfer; unsub first). Kept only so `testPassEvictionPreservesFundingSourceStorage` (already
    ///      skipped, D-12 supersession) still compiles; it now just clears `lastAutoBoughtDay` and
    ///      bumps `game.level` to 1 (uint24 at slot 0 bytes 14..16), which no longer forces any
    ///      eviction.
    function _forceCrossingDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 mask = uint256(0xFFFFFF) << (OFF_LASTBOUGHT * 8);
        packed &= ~mask;
        vm.store(address(game), slot, bytes32(packed));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    // ---- Sub field reads + the source-delta charged-slice oracle ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    function _fundingSourceOf(address who) internal view returns (address) {
        uint32 id = uint32(uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(FUNDINGSOURCE_SLOT))))));
        return id == 0 ? address(0) : _fixturePayee(id);
    }

    /// @dev The current process-day stamp of the fixture (so "bought this STAGE" is robust). The STAGE
    ///      stamps lastAutoBoughtDay = the process day; a fresh buy advances it past the snapshot.
    mapping(address => uint32) private _baselineBoughtDay;

    /// @dev The ethValue charged for `who` this STAGE, re-expressed from the funding-SOURCE bucket delta.
    ///      Returns type(uint256).max if `who` was NOT bought this STAGE. Captures the source baseline on
    ///      first touch via `_srcFundBefore` populated in `_stageCapture` (see `_armSlice`).
    function _chargedFor(address who) internal view returns (uint256) {
        if (_lastBoughtDayOf(who) <= _baselineBoughtDay[who]) return type(uint256).max;
        address src = _fundingSourceOf(who);
        if (src == address(0)) src = who;
        return _srcFundBefore[who] - game.afkingFundingOf(src);
    }

    /// @dev Per-test arming of the charged-slice oracle: record each tracked sub's funding-source bucket
    ///      + day baseline BEFORE the STAGE. Called explicitly by tests that read `_chargedFor`.
    function _armSlice(address who) internal {
        _baselineBoughtDay[who] = _lastBoughtDayOf(who);
        address src = _fundingSourceOf(who);
        if (src == address(0)) src = who;
        _srcFundBefore[who] = game.afkingFundingOf(src);
    }

    // ---- Event drain ----

    Vm.Log[] private _capturedLogs;

    function _capture() internal {
        _capturedLogs = vm.getRecordedLogs();
    }

    function _countSkipped(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(game) &&
                L.topics.length >= 2 &&
                L.topics[0] == SKIPPED_SIG &&
                uint32(uint256(L.topics[1])) == game.walletIdOf(who)
            ) {
                uint8 r = abi.decode(L.data, (uint8));
                if (r == reason) count++;
            }
        }
    }

    function _countExpired(address who) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(game) &&
                L.topics.length >= 2 &&
                L.topics[0] == SUB_EXPIRED_SIG &&
                uint32(uint256(L.topics[1])) == game.walletIdOf(who)
            ) count++;
        }
    }

    /// @dev Substring search over the contract source (for the grep-clean exemption-flag assertion).
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}
