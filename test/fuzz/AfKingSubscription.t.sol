// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AfKingSubscription -- the game-resident AFKing subscription acceptance properties: a seat is
///        the only credential and a passless holder is processed with no eviction (AFSUB-02/03), subscribe
///        charges no FLIP and buys nothing (AFSUB-01), a mineFlip whose advance runs the subscriber pass
///        emits one creditFlip_g317 bounty (REW-02), and subscribe authorization follows the account rule
///        while third parties may only add to a subscriber's own prepaid bucket (OPENE-04).
contract AfKingSubscription is DeployProtocol {


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

    /// @dev keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)") — one per creditFlip_g317.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    /// @dev Game-resident module event signature (emitter == address(game) via delegatecall).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // Task 3a — Coin credential: no process-pass re-check, no crossing machinery
    // (the pass horizon + refresh/evict crossing branch does not exist — a seat is the only
    // credential, burned once when a new run starts)
    // =========================================================================

    /// @notice A coin-holding, PASSLESS subscriber is processed across the STAGE with
    ///         no credential re-check: no eviction event, no FLIP burn, stays in the
    ///         iterable set with dailyQuantity preserved. This is the successor of the
    ///         crossing refresh/evict pair — level crossings are now a non-event for
    ///         subscription membership.
    function testPasslessCoinHolderProcessedNoEviction() public {
        address seated = makeAddr("seated_no_pass");
        _grantSeat(seated); // the coin IS the credential; no pass anywhere
        _fundPool(seated, 1 ether);
        _subscribeLootboxMode(seated, 1);
        uint256 fundedBefore = game.afkingFundingOf(seated);
        assertEq(fundedBefore, 1 ether, "signup buys nothing");

        uint256 flipBefore = coin.balanceOf(seated);

        vm.recordLogs();
        _runStageOnce();

        assertEq(_countEventFor(address(game), SUB_EXPIRED_SIG, seated), 0, "no eviction: coin held");
        assertEq(coin.balanceOf(seated), flipBefore, "no FLIP burned during the STAGE");
        assertGt(_dailyQtyOf(seated), 0, "sub stays active");
        assertGt(_subscriberIndexOf(seated), 0, "sub stays in the iterable set");
        assertLt(game.afkingFundingOf(seated), fundedBefore, "the next day's pass bought");
    }

    // =========================================================================
    // Task 3b — AFSUB-01: no FLIP prepay window at subscribe; horizon-encoded only
    // =========================================================================

    /// @notice AFSUB-01: subscribe NEVER charges FLIP. A no-pass subscriber's FLIP balance is
    ///         UNCHANGED across subscribe; their `validThroughLevel` is encoded as `_passHorizonOf`
    ///         (zero for a no-pass subscriber).
    function testSubscribeNoFlipChargeRegardlessOfPass() public {
        // Formerly skipped (357-00d): the pass gate rejected a passless subscribe at every
        // level. The AFKing Subscription Token credential resurrects this coverage — a passless,
        // coin-holding subscriber is first-class. AFSUB-01 (no FLIP charge at subscribe)
        // is the property under test; the coin gate charges nothing either.
        address nopass = makeAddr("subscribe_nopass");
        uint256 seat = _grantSeat(nopass);
        _fundPool(nopass, 1 ether); // the deposit is ETH, not FLIP
        uint256 nopassBefore = coin.balanceOf(nopass); // == 0
        vm.prank(nopass);
        game.subscribe(0, true, 1, seat); // MUST NOT revert; charges no FLIP
        assertEq(coin.balanceOf(nopass), nopassBefore, "AFSUB-01: no FLIP burned at subscribe (no pass)");
        assertGt(_dailyQtyOf(nopass), 0, "passless coin-holder subscribed");
        assertEq(game.afkingFundingOf(nopass), 1 ether, "subscribe buys nothing");
    }

    // =========================================================================
    // Task 3c — Single-creditFlip_g317 mineFlip bounty (REW-02 / PLACE-02)
    // =========================================================================

    /// @notice REW-02 (PLACE-02 bounty folded into advance): the REWARDED entrypoint is the
    ///         parameterless `mineFlip()` router. A mineFlip() whose advance leg runs the buy STAGE
    ///         emits AT MOST ONE creditFlip_g317 to the caller (never per-item) — the one-bounty-per-tx
    ///         property. (The advance leg pays `unit·2·mult`; a `mult==0` gameover advance pays none.)
    function testMintFlipEmitsAtMostOneBuyBounty() public {
        // Enough buying subscribers that one call's buy STAGE measures above the unpaid first 1M
        // (two measured ~0.35M, 32 ~0.39M, 160 ~1.54M: about 9k per stamped subscriber), so a per-item
        // credit would show.
        address[] memory subs = new address[](160);
        for (uint256 i; i < subs.length; i++) {
            subs[i] = makeAddr(string(abi.encodePacked("buy_s", vm.toString(i))));
            _setupHealthyBuyingSub(subs[i]);
        }

        address keeper = makeAddr("bounty_keeper");
        _giveWalletId(keeper);

        // mineFlip composes every admitted chunk (the buy STAGE for both subscribers among them) and
        // pays ONE measured-gas reward at the end. The reward prices gas above the unpaid first 1M
        // at min(basefee, cap); Foundry's default basefee is zero, which would price it at zero.
        vm.fee(1 gwei);
        // Subscribing buys nothing; the next day's buy STAGE is the work under test.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < subs.length; i++) {
            assertEq(game.afkingFundingOf(subs[i]), 1 ether, "fixture: no subscriber has bought yet");
        }
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip(0);
        uint256 credits = _countCreditFlipTo(keeper);
        uint256 reward;
        uint256 works;
        for (uint256 i; i < _logsCache.length; i++) {
            if (_logsCache[i].emitter == address(game) && _logsCache[i].topics.length >= 2
                && _logsCache[i].topics[0] == keccak256("MinerWork(address,uint8,uint256,uint256)")) {
                (, uint256 used, uint256 paid) = abi.decode(_logsCache[i].data, (uint8, uint256, uint256));
                emit log_named_uint("buy-stage mineFlip execution gas", used);
                reward = paid;
                ++works;
            }
        }
        assertEq(works, 1, "one measured miner call");
        for (uint256 i; i < subs.length; i++) {
            assertLt(game.afkingFundingOf(subs[i]), 1 ether, "the call ran the buy STAGE for every subscriber");
        }
        assertGt(reward, 0, "nonvacuity: the call measured above the unpaid 1M at a nonzero base fee");
        assertEq(credits, 1, "exactly one bounty creditFlip_g317 per mineFlip tx, never per item (REW-02)");
    }

    // =========================================================================
    // Task 3d — account-rule subscribe auth and the prepaid bucket (OPENE-04)
    // =========================================================================

    /// @notice A caller that is neither the account's payee nor its approved operator cannot
    ///         subscribe for it; once approved, the same call is honored.
    function testUnapprovedCallerRefusedThenHonored() public {
        address s = makeAddr("auth_s");
        address m = makeAddr("auth_m");
        uint32 sId = _aid(s);
        uint256 seat = _grantSeat(s);

        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(sId, true, 1, seat);

        vm.prank(s);
        game.setOperatorApproval(0, m, true);
        vm.prank(m);
        game.subscribe(sId, true, 1, seat);
        assertGt(_subscriberIndexOf(s), 0, "the approved operator started S's run");
    }

    /// @notice A third party may fund a subscriber's own prepaid bucket, and the daily buy
    ///         draws from it; revoking nothing is needed because no one else's funds are ever drawn.
    function testThirdPartyDepositFundsTheSubscribersOwnBucket() public {
        address s = makeAddr("dep_s");
        uint256 seat = _grantSeat(s);
        uint32 sId = _aid(s);
        vm.prank(s);
        game.subscribe(0, true, 1, seat);
        address funder = makeAddr("dep_funder");
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        game.depositAfkingFunding{value: 1 ether}(sId);
        assertEq(game.afkingFundingOf(s), 1 ether, "the deposit lands in S's bucket");
        assertEq(game.afkingFundingOf(funder), 0, "nothing in the funder's bucket");

        _runStageOnce();
        assertLt(game.afkingFundingOf(s), 1 ether, "the daily buy drew S's bucket");
        assertGt(_subscriberIndexOf(s), 0);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE mineFlip() (no full settle) —
    ///      the STAGE is strictly PRE-RNG so the crossing refresh/evict completes before rngGate and the
    ///      stage is measured on its own. Subscribers must already be registered (subscribe blocks
    ///      during rngLock).
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
    }

    /// @dev Settle the game to a clean state: drive mineFlip + deliver the mock VRF word until
    ///      advanceDue() is false and we are not rng-locked (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip(0);
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

    /// @dev Current game level (game.level() auto-getter for the `uint24 public level` storage var).
    function _currentLevel() internal view returns (uint24) {
        return game.level();
    }

    /// @dev Subscribe `who` in LOOTBOX mode (so the box STAGE materializes a stamp), dailyQuantity q.
    function _subscribeLootboxMode(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest, self-funded
    }

    /// @dev A fully-healthy buying sub (lootbox mode, seated with an AFKing Subscription Token, funded).
    function _setupHealthyBuyingSub(address who) internal {
        _grantSeat(who);
        _fundPool(who, 1 ether);
        _subscribeLootboxMode(who, 1);
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding).
    function _fundPool(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    // ---- Lane reads ----

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(GameSlotKeys.subQuantity(address(game), game.walletIdOf_g3120(who)));
    }

    /// @dev `who`'s set position + 1; 0 = not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    Vm.Log[] private _logsCache;
    bool private _logsCacheReady;

    function _drain() internal {
        if (!_logsCacheReady) {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            delete _logsCache;
            for (uint256 i; i < logs.length; i++) _logsCache.push(logs[i]);
            _logsCacheReady = true;
        }
    }

    function _countEvent(address emitter, bytes32 sig) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (_logsCache[i].emitter == emitter && _logsCache[i].topics.length > 0 && _logsCache[i].topics[0] == sig) count++;
        }
    }

    function _countEventFor(address emitter, bytes32 sig, address who) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (
                _logsCache[i].emitter == emitter &&
                _logsCache[i].topics.length >= 2 &&
                _logsCache[i].topics[0] == sig &&
                uint32(uint256(_logsCache[i].topics[1])) == game.walletIdOf_g3120(who)
            ) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose indexed player == `to` (the bounty recipient).
    function _countCreditFlipTo(address to) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (
                _logsCache[i].emitter == address(coinflip) &&
                _logsCache[i].topics.length >= 2 &&
                _logsCache[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                uint256(_logsCache[i].topics[1]) == game.walletIdOf_g3120(to)
            ) count++;
        }
    }
}
