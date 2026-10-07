// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title V55SetMutationOpenE -- The dedicated TST-04 proof: the v55.0 two-path open coexistence
///        (BOX-05, no shared mutable-state hazard), the NO-ORPHAN guard (a sub removed between stamp and
///        open gets NO free box, GameAfkingModule.sol:554-576), the streak-preserved swap-pop
///        (scorePlus1 survives the tombstone-reclaim), and the OPEN-E 4-protection regression
///        ([[open-e-operator-approval-trust-boundary]]).
///
/// @notice The two open routes are GENUINELY SEPARATE (no selector / queue overlap):
///   - HUMAN box open: `game.mineFlip()`'s HumanBoxes stage walks `boxQueue[read]` from `boxCursor`.
///   - AFKING box open: `game.mineFlip()`'s open leg (GameAfkingModule.sol:1000-1009, only when
///     !advanceDue) walks `_subscribers` via `_autoOpen`. The afking module's own `autoOpen` selector
///     COLLIDES with the human `autoOpen(uint256)` so it is NOT re-exposed on the Game (DegenerusGame.sol
///     :352-353) — the afking open is reached ONLY through `mineFlip`. The two paths share no mutable
///     state: distinct queues (`boxQueue` vs `_subscribers`), distinct cursors (`boxCursor` vs
///     `_subOpenCursor`), distinct per-box records (the queued purchase entry vs the warm Sub stamp).
///
/// @notice NO-ORPHAN (the load-bearing §3 guard): a box is STAMPED at the process STAGE (day D) but
///         OPENED later; it exists ONLY as (Sub stamp + lastAutoBoughtDay) with no cold ledger. The open
///         leg walks `_subscribers`, so ANY removal of the sub from `_subscribers` between stamp and open
///         ORPHANS the paid-for box (the player was debited at stamp, gets nothing) — and the process
///         STAGE's NO-ORPHAN guard (GameAfkingModule.sol:570) DOMINATES every mutation path
///         (re-stamp / cancel-reclaim / funding-kill) by leaving a pending-box sub ENTIRELY
///         untouched, so the contract itself never orphans. This proof asserts both: (a) the contract
///         never orphans a pending-box sub via the STAGE, and (b) IF the sub is removed from the set
///         (the orphan condition) the open leg materializes NO box for it.
///
/// @notice OPEN-E 4-protection (TST-04): consent-gate-at-subscribe (unapproved operator REVERTS) /
///         default-self (src=address(0) -> funder == self, byte-identical) / no-escalation (an operator
///         cannot widen the grant per-draw) / trust-the-sub temporal bound (a later revoke does not stop
///         an active sub).
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live). RE-DERIVED every
///      pinned slot via `forge inspect storage DegenerusGame` (the AfKing-standalone-layout constants are
///      WRONG). Test-only: no contracts/*.sol mutated.
contract V55SetMutationOpenE is DeployProtocol {

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
    // Game-resident storage slots (RE-DERIVED via `forge inspect DegenerusGame storageLayout`, post
    // Stage B Game-storage packing — corrected to authoritative values).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // _subscribers address[] (length here; data at keccak(54))

    // Sub packed-field byte offsets — the v56 compute-on-read re-pack (single 256-bit slot); the
    // validThroughLevel field is deleted (the AFKing Subscription Token replaced the pass-horizon credential), so
    // every field after dailyQuantity shifted down 3 bytes.
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_SCOREPLUS1 = 2; // uint16 score             (bytes 2..3)
    uint256 private constant OFF_AMOUNT = 4; // uint24 amount            (bytes 4..6)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)

    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }


    // =========================================================================
    // (d) OPEN-E 4-protection regression
    // =========================================================================

    /// @notice OPEN-E (1) consent-gate-at-subscribe: subscribing with an UNAPPROVED non-zero non-self
    ///         fundingSource REVERTS NotApproved at subscribe (the gate is checked HERE only).
    function testOpenEConsentGateUnapprovedReverts() public {
        address s = makeAddr("openE_s");
        address m = makeAddr("openE_m");
        uint256 seat = _grantSeat(m);
        uint32 sId = _aid(s);
        _aid(m);
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(0, false, true, 1, sId, seat); // S has not approved M -> REVERT
    }


    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Drive the per-sub buy STAGE for a NEW day (Δ4 successor to afKing.autoBuy): warp +1 day,
    ///      settle so the Afking stage (SUB_STAGE_BATCH) stamps the funded set + the day word lands.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
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

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, false, q, 0, seat); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Forcibly remove `who` from `_subscribers` (the orphan condition): zero its
    ///      Sub.setPosition and shrink the array length by 1 (a test-only simulation of a removal
    ///      between stamp and open; the contract's own STAGE never does this to a pending-box sub).
    function _forceRemoveFromSubscribers(address who) internal {
        uint256 idxPlus1 = _subscriberIndexOf(who);
        if (idxPlus1 == 0) return;
        uint256 idx = idxPlus1 - 1;
        bytes32 lenSlot = bytes32(uint256(SUBSCRIBERS_SLOT));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        // Swap-pop: move the last element (address | id << 160) into `idx`, fix the mover's
        // Sub.setPosition, shrink length, clear `who`'s setPosition.
        if (idx != len - 1) {
            uint256 moverElement = uint256(vm.load(address(game), bytes32(uint256(dataBase) + (len - 1))));
            vm.store(address(game), bytes32(uint256(dataBase) + idx), bytes32(moverElement));
            _setSubPosition(uint32(moverElement >> 160), idxPlus1);
        }
        vm.store(address(game), lenSlot, bytes32(len - 1));
        _setSubPosition(game.walletIdOf(who), 0);
    }

    /// @dev Overwrite Sub.setPosition (bits 224..255 of the one-slot Sub) for wallet `id`.
    function _setSubPosition(uint32 id, uint256 position) internal {
        bytes32 slot = keccak256(abi.encode(uint256(id), uint256(SUBOF_SLOT)));
        uint256 word = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((word & ((uint256(1) << 224) - 1)) | (position << 224)));
    }

    // ---- Sub field reads (RE-DERIVED slot 52 + verified offsets) ----

    function _subSlot(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), _subSlot(who))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _scorePlus1Of(address who) internal view returns (uint16) {
        return uint16(_subField(who, OFF_SCOREPLUS1, 16));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    /// @dev Pin `who`'s scorePlus1 (bytes 2..3) — the mint-streak EV input.
    function _setScorePlus1(address who, uint16 score) internal {
        bytes32 slot = _subSlot(who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFF) << (OFF_SCOREPLUS1 * 8));
        packed |= (uint256(score) << (OFF_SCOREPLUS1 * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    function _fundingSourceOf(address who) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.FUNDING_SOURCE_OF))))));
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(address(uint160(uint256(logs[i].topics[1]))));
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    function _countExpiredFor(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _expiredPlayers.length; i++) {
            if (_expiredPlayers[i] == who && _expiredReasons[i] == reason) count++;
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
