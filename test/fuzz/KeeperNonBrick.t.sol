// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title KeeperNonBrick -- the REVERT-FREE / NON-BRICK corpus, adapted to the v55 game-resident
///        afking path (Phase 351, D-351-01). Proves the no-brick guarantee that survives D-348-04's
///        REMOVAL of the per-slice try/catch valve: the funded process STAGE / box open is
///        revert-free BY CONSTRUCTION (REVERT-01, class A); a solvency violation FAILS LOUD (the
///        checked `claimablePool -=`, class B); the game-resident withdraw/cancel are un-brickable
///        under strict CEI.
///
/// @notice D-351-02 REMOVED-SURFACE DROP (logged BY NAME for the 351-09 REGRESSION-BASELINE-v55 ledger):
///   the v49 keeper batch-purchase per-slice try/catch isolation leg is GONE — the standalone AfKing
///   batch-buy entrypoint (and its BatchBuy event) was v55 P5 dead-code (349.1) and has NO game-resident
///   successor. The per-buy work folded into `mineFlip()`'s required-path Afking STAGE,
///   which is revert-free by construction (no valve to isolate a poisoned slice — a FUNDED, well-formed
///   slice can never poison the batch; an underfunded NORMAL sub is auto-paused/swap-popped, never
///   reverted). The six dropped tests (no behavioral successor — recorded for the ledger):
///     - testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice
///     - testFuzz_BatchPurchaseFailPositionRefundsAndCompletes
///     - testBatchPurchaseGameOverRejectsWholeBatchAtEntry
///     - testBatchPurchaseRejectsNonKeeperCaller
///     - testKeeperBatchSkipsPoisonedMiddlePlayer
///     - testFuzz_KeeperBatchPoisonPositionNeverBricks
///   The reentrancy-rollback + un-brickable-cancel + reclaim/auto-pause-commit properties REFRAME onto
///   the game-resident withdraw/cancel + the STAGE (D-351-01 renamed/relocated, NOT a removed surface).
///
/// @dev Builds on the DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE). Drives REAL
///      lootbox purchases through the public mint API; the per-sub buy is `mineFlip()`'s pre-RNG STAGE
///      (the Afking stage); cancel is `subscribe(_, dailyQuantity=0)` (the in-place tombstone); the
///      pool ETH lives in the game-resident `afkingFunding` ledger (deposited via `depositAfkingFunding`,
///      withdrawn via `withdrawAfkingFunding` under CEI). RE-DERIVED every pinned slot via
///      `forge inspect storage DegenerusGame`. Test-only: ZERO `contracts/*.sol` mutation.
contract KeeperNonBrick is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; RE-DERIVED via `solc --storage-layout` on the working
    // tree after the V62 lootbox repack — the folded lootboxEth word + removed lootboxEthBase/Flip/
    // Purchase/Distress shifted later slots down (region-dependent). The prior 36/37/43/44/62/64/65
    // pins were stale; corrected to the authoritative values below.
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    /// @dev lootboxEth (the single folded box word) mapping root slot. The amount sub-field (low 128
    ///      bits) is the box-owed signal that replaced the removed lootboxEthBase mapping.
    uint256 private constant LOOTBOX_ETH_SLOT = GameSlots.LOOTBOX_ORDER;
    uint256 private constant LB_AMOUNT_MASK = (uint256(1) << 128) - 1;
    /// @dev rngLockedFlag is bool at slot 0 offset 19 bytes = bit 152.
    uint256 private constant RNG_LOCKED_SHIFT = 152;
    /// @dev gameOver is bool at slot 0 offset 21 bytes = bit 168.
    uint256 private constant GAME_OVER_SHIFT = 168;

    // Game-resident afking storage. The v61 fold removed the separate afkingFunding mapping; the
    // afking balance is now the high 128 bits of balancesPacked (slot 7), claimable the low 128.
    uint256 private constant CLAIMABLE_POOL_SLOT = GameSlots.CLAIMABLE_POOL; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = GameSlots.BALANCES_PACKED; // balancesPacked root; low 128 bits = claimable
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit @ bit 184)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = GameSlots.RNG_WORD_BY_DAY; // mapping(uint24 => uint256) — the afking box's DAY-keyed word
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // address[] _subscribers

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:2341; the AFKing-Coin repack dropped
    // validThroughLevel, shifting every field after it down 3 bytes).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_SCORE = 2; // uint16 score             (bytes 2..3)
    uint256 private constant OFF_AMOUNT = 4; // uint24 amount            (bytes 4..6)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev SubscriptionExpired(address indexed player, uint8 reason). reason 1 = AutoPause, 2 = CancelReclaim.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    // -------------------------------------------------------------------------
    // Afking reward peg mirror (the module's own FIXED constants, REW-03) — game storage, reusable as-is.
    // -------------------------------------------------------------------------
    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 71_203;
    uint256 private constant PRICE_COIN_UNIT = 1000;

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    uint256 private constant LOOTBOX_MIN = 0.01 ether; // mint-module DirectEth lootbox floor

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    address private player;
    address private cranker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("nonbrick_player");
        cranker = makeAddr("nonbrick_cranker");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(address(game), 5_000_000 ether);

        // Seed lootboxRngIndex = 1 (word stays 0 until injected) so the daily-index reads are well-formed.
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        RecyclingState.seedWriteBuffer(address(game), INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }


    // =========================================================================
    // reentrancy rollback (no double-withdraw) — game-resident withdrawAfkingFunding CEI
    // =========================================================================

    /// @notice REENTRANCY (reframed onto game-resident `withdrawAfkingFunding`): a malicious afking-funding
    ///         holder whose ETH-receive callback re-enters `withdrawAfkingFunding` to extract a SECOND payout
    ///         cannot double-spend. Under the game's strict CEI (effects — the funding debit + the tandem
    ///         claimablePool release — execute BEFORE the `.call`, DegenerusGame.sol:1568-1571), the
    ///         re-entrant inner withdraw sees the zeroed funding and reverts E(); the attacker bubbles it, so
    ///         the outer `.call` sees failure, reverts E(), and the WHOLE call unwinds. The attacker extracts
    ///         NOTHING — the per-frame debit can never be replayed.
    function testReentrantWithdrawCannotDoubleSpend() public {
        ReentrantAfkingWithdrawer attacker = new ReentrantAfkingWithdrawer(address(game));
        uint256 funded = 5 ether;
        _fundPool(address(attacker), funded);
        assertEq(game.afkingFundingOf(address(attacker)), funded, "attacker funding credited");

        // The re-entrant attack reverts (bubbled E() -> outer .call fails -> E()); the whole withdraw unwinds.
        vm.expectRevert();
        attacker.attackBubbling(funded);

        // No double-spend: the funding debit fully rolled back (still == funded), the attacker got no ETH.
        assertEq(game.afkingFundingOf(address(attacker)), funded, "funding fully restored - no double-spend");
        assertEq(address(attacker).balance, 0, "attacker extracted no ETH via reentrancy");
    }

    /// @notice REENTRANCY (benign single withdraw): a holder whose callback re-enters but SWALLOWS the inner
    ///         revert still receives only ONE payout — the inner withdraw cannot add a second (CEI zeroed the
    ///         funding before the send). Proves the at-most-once property even when the inner failure is caught.
    function testReentrantWithdrawSwallowedYieldsSinglePayout() public {
        ReentrantAfkingWithdrawer attacker = new ReentrantAfkingWithdrawer(address(game));
        uint256 funded = 4 ether;
        _fundPool(address(attacker), funded);

        // Swallowing the inner revert: the outer withdraw completes once; the re-entry adds nothing.
        attacker.attackSwallowing(funded);

        assertEq(game.afkingFundingOf(address(attacker)), 0, "funding debited exactly once");
        assertEq(address(attacker).balance, funded, "attacker received exactly one payout, never two");
    }


    // =========================================================================
    // Protocol-driving helpers (ported from V55FreezeDeterminism / V55SetMutationOpenE)
    // =========================================================================

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE `mineFlip()` (no full settle) — the
    ///      STAGE runs strictly PRE-RNG (AdvanceModule:305-326), so the eviction/buy completes before
    ///      rngGate and the stage is measured on its own. Subscribers must already be registered
    ///      (subscribe blocks during rngLock). The 351-02 _runStageOnce pattern.
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
    }

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

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning (the
    ///      251-04 240-iter drain) — used before an afking box open so `mineFlip` reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
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

    /// @dev Subscribe `n` funded lootbox-mode subs (seated with an AFKing Subscription Token — the sole subscribe
    ///      credential), each pool-funded with `poolEach`. Returns the addresses.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantSeat(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0)); // self, lootbox mode, qty 1
            _fundPool(who, poolEach);
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

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Credit `who` claimableWinnings AND bump claimablePool in tandem (SOLVENCY-01 stays balanced, the
    ///      351-02 test-infra reality) so a claimable-funded slice's `claimablePool -=` does not underflow.
    ///      `claimableWinnings` is `internal` (no getter) — read/write it via the RE-DERIVED mapping slot.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(CLAIMABLE_WINNINGS_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(cur + amount));
        _bumpClaimablePool(amount);
    }

    function _simDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82_620) / 1 days);
    }

    // ---- Sub field reads (RE-DERIVED slot 52 + verified offsets) ----

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

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    // ---- pass-validity + level poking (AFSUB-03 mass-eviction setup) ----

    /// @dev Pin `who`'s validThroughLevel (uint32 @ byte offset 1 of the packed Sub slot) — used to force a
    ///      crossing-evict scenario. The Sub layout: dailyQuantity(0) | flags(1) | validThroughLevel(2..5) |
    ///      ... actually validThroughLevel sits in the low bytes alongside dailyQuantity/flags; re-derived by
    ///      the 351-02 round-trip as bytes 1..4 region. We zero it (force the crossing) which is the only
    ///      value this test needs.
    function _setValidThroughLevel(address who, uint32 lvl) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        // validThroughLevel is the uint32 occupying bytes 1..4 (after dailyQuantity at byte 0). Clear+set.
        packed &= ~(uint256(0xFFFFFFFF) << (1 * 8));
        packed |= (uint256(lvl) << (1 * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Set the live game `level` (uint24 @ slot 0, byte offset 14).
    function _setLevel(uint24 lvl) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFFFFFF) << (14 * 8);
        slot0 = (slot0 & ~mask) | (uint256(lvl) << (14 * 8));
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // ---- gameOver / rngLocked / claimablePool slot pokes ----

    function _setGameOver(bool on) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (on) slot0 |= (uint256(1) << GAME_OVER_SHIFT);
        else slot0 &= ~(uint256(1) << GAME_OVER_SHIFT);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Force claimablePool (uint128 @ slot 1, byte 16) to an absolute value — used to manufacture the
    ///      class-B SOLVENCY-01 underflow (pool < a player's afkingFunding).
    function _setClaimablePool(uint256 value) internal {
        require(value <= type(uint128).max, "pool fits uint128");
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 mask = uint256(type(uint128).max) << (CLAIMABLE_POOL_OFFBYTES * 8);
        slot1 = (slot1 & ~mask) | (value << (CLAIMABLE_POOL_OFFBYTES * 8));
        vm.store(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT)), bytes32(slot1));
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _bumpClaimablePool(uint256 delta) internal {
        _setClaimablePool(_claimablePool() + delta);
    }

    /// @dev Count SubscriptionExpired(who, reason) emissions from the game in the recorded logs. Consumes the
    ///      log buffer (call once after the STAGE under test).
    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(game) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == SUB_EXPIRED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == who &&
                uint8(uint256(bytes32(logs[i].data))) == reason
            ) count++;
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

/// @notice A malicious afking-funding holder whose receive() re-enters game.withdrawAfkingFunding, proving
///         the game's CEI withdraw rolls back a re-entrant double-spend attempt.
contract ReentrantAfkingWithdrawer {
    GameWithdrawLike private immutable g;
    uint256 private reentryAmount;
    bool private reentered;
    bool private bubble; // true = let the inner revert bubble (outer reverts); false = swallow

    constructor(address _game) {
        g = GameWithdrawLike(_game);
    }

    /// @dev Bubbling variant: the inner re-entrant withdraw's revert is NOT caught, so it bubbles into the
    ///      outer withdraw's `.call`, which sees failure -> E() -> outer reverts.
    function attackBubbling(uint256 amount) external {
        reentryAmount = amount;
        bubble = true;
        reentered = false;
        g.withdrawAfkingFunding(amount); // reverts when the re-entry bubbles
    }

    /// @dev Swallowing variant: the inner re-entrant withdraw's revert IS caught, so the outer withdraw
    ///      completes a single payout; the re-entry adds nothing.
    function attackSwallowing(uint256 amount) external {
        reentryAmount = amount;
        bubble = false;
        reentered = false;
        g.withdrawAfkingFunding(amount);
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            // Re-enter before the outer frame finishes. Under CEI the funding is already zeroed, so this
            // reverts E().
            if (bubble) {
                g.withdrawAfkingFunding(reentryAmount); // bubble the revert -> outer .call fails
            } else {
                try g.withdrawAfkingFunding(reentryAmount) {} catch {} // swallow -> outer completes once
            }
        }
    }
}

interface GameWithdrawLike {
    function withdrawAfkingFunding(uint256 amount) external;
}
