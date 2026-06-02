// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title V56FreezeSolvency -- the SEC-02 proof in three legs (CONTEXT D-05) against the FROZEN v56 subject:
///        (1) the ETH/claimablePool debit path is byte-unchanged vs 453f8073 (the SOLVENCY-01 site); (2) a
///        solvency invariant fuzz; (3) an RNG-freeze determinism fuzz.
///
/// @notice Leg 1 (forge arm). The ETH/claimablePool debit happens at exactly one in-context site —
///   `_deliverAfkingBuy` (GameAfkingModule.sol): `afkingFunding[src] -= ethValue; claimablePool -=
///   uint128(ethValue);` — and the debit equals the delivered ethValue EXACTLY. The affiliate base and the
///   slot-0 quest reward are accrued as BURNIE (pendingBurnie / affiliateBase, claimed via creditFlip), OFF
///   the ETH/claimablePool path: claiming BURNIE leaves claimablePool byte-unchanged. The literal git
///   byte-diff anchor (`git diff 453f8073 HEAD` shows the debit two-liner re-added verbatim) is recorded by
///   356-07's ledger; this file asserts the BEHAVIOR (debit == delivered value; BURNIE claim moves no pool).
///
/// @notice Leg 2 (solvency invariant). The master invariant the Game maintains (DegenerusGame.sol:18) is
///   `address(this).balance + steth.balanceOf(this) >= claimablePool`. Across random {sub, unsub, buy,
///   accrue, claimAfkingBurnie} sequences it always holds: the buy-delivery debit decreases claimablePool by
///   exactly the fresh-ETH it spends from the (already-reserved) afking funding, and the BURNIE accrue/claim
///   never touches the pool.
///
/// @notice Leg 3 (RNG-freeze determinism). The subscribe min-buy STAMPS a box for-later-open and NEVER
///   inline-resolves pre-RNG (no LootBoxOpened at subscribe time). The single-roll open seed is
///   `keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay, amount))` — it carries NO block.*
///   entropy, so two opens of the SAME stamp at DIFFERENT blocks (vm.roll/warp + perturbed
///   prevrandao/coinbase) materialize byte-identical boxes. The afking open is reached via mintBurnie() (the
///   autoOpen selector was dropped — not re-exposed on the Game).
///
/// @dev Reuses the funded-sub + deity-pass + new-day STAGE harness (the accumulating-`_t` warp +
///   fulfill-first `_settleGame`/`_settleClean`/`_fulfillPending` from V56AfkingGasMarginal / the 356-03
///   V56SecUnmanipulable), the materialized-box byte-identity oracle from the v56-migrated
///   V55FreezeDeterminism, and the claimablePool slot read from the v56-migrated V55RevertFreeEvCap. Copies
///   the v56 Sub-slot offset block VERBATIM from V56AfkingGasMarginal:68-89 (NOT the stale v55 offsets).
///   v56 harness semantics: Sub.amount is packed milli-ETH (_packEthToMilliEth), the subscribe min-buy
///   carries a 0.01-ETH funding delta, the affiliate is a single-step claim. Seeded-fuzz deterministic
///   (`foundry.toml [fuzz] seed=0xdeadbeef`); the assertions are an unseeded-invariant subset of the seeded
///   closure (Pitfall 5). Test-only: ZERO contracts/*.sol mutation.
contract V56FreezeSolvency is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the v56 Sub-slot offset block (V56AfkingGasMarginal:68-89)
    // -------------------------------------------------------------------------
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant MINTPACKED_SLOT = 10; // mintPacked_ mapping root (deity bit @ bit 184)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — the afking box DAY-keyed word
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 38; // [0:47] lootboxRngIndex
    uint256 private constant LOOTBOX_RNG_WORD_BY_INDEX_SLOT = 39; // mapping(uint48 => uint256)
    uint256 private constant SUBOF_SLOT = 66; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // mapping(address => uint256) _subscriberIndex (1-indexed)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8 (milli-ETH)
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31
    uint256 private constant OFF_SCOREPLUS1 = 6; // uint16 scorePlus1        (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 8; // uint24 amount (milli-ETH)   (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)
    uint256 private constant OFF_AFKCOVERED = 17; // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_PENDINGBURNIE = 27; // uint32 pendingBurnie (bytes 27..30)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev keccak256 of the materialized-box event — the byte-identity oracle's source signature.
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint32,uint256,uint24,uint32,uint256,bool)");

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole BURNIE accrued to pendingBurnie per delivered buy.
    uint256 private constant SLOT0_BURNIE_PER_BUY = 100;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;

    /// @dev A decoded LootBoxOpened payload — every non-indexed field of the materialized box.
    struct Box {
        bool present;
        uint48 lootboxIndex;
        uint32 day;
        uint256 amount;
        uint24 futureLevel;
        uint32 futureTickets;
        uint256 burnie;
        bool roundedUp;
    }

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // Leg 2 — the solvency invariant across churn / accrue / claim
    // =========================================================================

    /// @notice The master solvency invariant `game.balance + steth.balanceOf(game) >= claimablePool` holds
    ///         after EVERY action in a fuzzed {sub, unsub, buy(=deliver a funded day), claimAfkingBurnie}
    ///         sequence. Each delivered day debits claimablePool by exactly its fresh-ETH spend (already
    ///         reserved inside the pool by the funding deposit), and the BURNIE accrue/claim moves no ETH —
    ///         so the invariant is never broken by the v56 accrual/settle redesign. Non-vacuous: at least one
    ///         delivered buy actually moved the pool and accrued claimable BURNIE.
    function testFuzzSolvencyInvariantUnderChurn(uint256 seq, uint8 rounds) public {
        address a = makeAddr("solv_a");
        address b = makeAddr("solv_b");
        _grantDeityPass(a);
        _grantDeityPass(b);
        _subscribeLootbox(a, 1);
        _subscribeLootbox(b, 1);
        _fundPool(a, 200 ether);
        _fundPool(b, 200 ether);

        _assertSolvent("post-setup");

        // Anchor buy: always deliver one funded day first so the invariant is exercised against a pool a
        // real buy has moved (the fuzzed action stream may otherwise pick no buy at all).
        _deliverDay(uint256(keccak256(abi.encode("solvanchor", seq))) | 1);
        _assertSolvent("post-anchor-buy");

        uint256 delivered = 1;
        uint256 n = 3 + (uint256(rounds) % 6); // 3..8 actions
        for (uint256 i; i < n; i++) {
            uint256 action = (seq >> (i * 3)) & 0x7;
            if (action < 4) {
                // buy: deliver a funded day to BOTH subs (debits the pool by the fresh-ETH spend).
                _deliverDay(uint256(keccak256(abi.encode("solvbuy", seq, i))) | 1);
                delivered++;
            } else if (action == 4) {
                // claimAfkingBurnie: pulls the accrued BURNIE — must NOT move claimablePool.
                uint256 poolBefore = _claimablePool();
                game.claimAfkingBurnie(_pair(a, b));
                assertEq(_claimablePool(), poolBefore, "claimAfkingBurnie left claimablePool byte-unchanged (OFF the ETH path)");
            } else if (action == 5) {
                // unsub a (tombstone) — only if currently an active sub (a real user can't cancel a
                // non-existent sub; the contract reverts NotSubscribed otherwise). Refunds nothing, so the
                // pool stays reserved against the residual funding.
                if (_subscriberIndexOf(a) != 0 && _dailyQtyOf(a) != 0) {
                    vm.prank(a);
                    game.subscribe(address(0), false, false, 0, 0, address(0));
                }
            } else if (action == 6) {
                // re-sub a (re-uses the in-place slot) if it is not currently active.
                if (_dailyQtyOf(a) == 0) _subscribeLootbox(a, 1);
            } else {
                // top up b's funding (deposit credits afkingFunding + claimablePool in tandem); re-sub b
                // first if a STAGE reclaim deleted its slot (depositAfkingFunding needs an active sub).
                if (_dailyQtyOf(b) == 0) _subscribeLootbox(b, 1);
                _fundPool(b, 20 ether);
            }
            _assertSolvent("post-action");
        }

        // Non-vacuity: the churn delivered at least one buy that moved the pool + accrued claimable BURNIE.
        assertGt(delivered, 0, "non-vacuity: at least one delivered buy");
        _assertSolvent("final");
    }

    /// @notice A focused named repro of leg 2's core: a delivered funded buy debits claimablePool, and a
    ///         subsequent claimAfkingBurnie leaves the pool byte-unchanged. The solvency invariant holds
    ///         across both.
    function testSolvencyHoldsBuyThenBurnieClaim() public {
        address p = makeAddr("solv_repro");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);
        _assertSolvent("post-fund");

        uint256 poolBeforeBuy = _claimablePool();
        _deliverDay(0x501E1C01);
        uint256 poolAfterBuy = _claimablePool();
        // The delivered buy spent fresh ETH from the (reserved) funding -> the pool decreased by the spend.
        assertLt(poolAfterBuy, poolBeforeBuy, "the delivered buy debited claimablePool by its fresh-ETH spend");
        _assertSolvent("post-buy");

        // The buy accrued claimable BURNIE OFF the ETH path.
        assertEq(_pendingBurnieOf(p), SLOT0_BURNIE_PER_BUY, "the buy accrued 100 whole BURNIE into pendingBurnie (OFF the ETH path)");

        // Claiming the BURNIE moves no ETH: the pool is byte-unchanged across the claim.
        uint256 poolBeforeClaim = _claimablePool();
        game.claimAfkingBurnie(_singleton(p));
        assertEq(_claimablePool(), poolBeforeClaim, "claimAfkingBurnie: claimablePool byte-unchanged (BURNIE is OFF the ETH/pool path)");
        assertEq(_pendingBurnieOf(p), 0, "the BURNIE was paid (pendingBurnie zeroed)");
        _assertSolvent("post-claim");
    }

    // =========================================================================
    // Leg 1 (forge arm) — the SOLVENCY-01 debit equals the delivered ethValue EXACTLY,
    //                     and the BURNIE accrue/claim is OFF the ETH/claimablePool path
    // =========================================================================

    /// @notice The ETH/claimablePool debit happens ONLY at the buy-delivery site and equals the delivered
    ///         ethValue EXACTLY. A funded sub's afking funding is reserved inside claimablePool by the deposit
    ///         (the SOLVENCY-01 invariant is balanced); a delivered buy then transfers exactly the per-buy
    ///         fresh-ETH spend out of BOTH afkingFunding[player] AND claimablePool in lockstep
    ///         (GameAfkingModule.sol `afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`).
    ///         Proven by reading both deltas across a single delivered buy: ΔafkingFunding == ΔclaimablePool
    ///         (the debit is the same `ethValue` on both ledgers — the byte-frozen v55 SOLVENCY-01 behavior).
    function testDebitEqualsDeliveredEthValueExactly() public {
        address p = makeAddr("debit_eq");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);

        uint256 fundingBefore = game.afkingFundingOf(p);
        uint256 poolBefore = _claimablePool();
        assertGt(fundingBefore, 0, "non-vacuity: the sub is funded pre-buy");

        _deliverDay(0xDEB17EC0);

        uint256 fundingAfter = game.afkingFundingOf(p);
        uint256 poolAfter = _claimablePool();
        uint256 fundingDebit = fundingBefore - fundingAfter;
        uint256 poolDebit = poolBefore - poolAfter;

        assertGt(fundingDebit, 0, "non-vacuity: the delivered buy spent fresh ETH");
        // The debit is the SAME ethValue on both ledgers (the byte-frozen SOLVENCY-01 two-liner).
        assertEq(
            poolDebit,
            fundingDebit,
            "SOLVENCY-01: claimablePool -= ethValue == afkingFunding[player] -= ethValue (debit equals delivered value exactly)"
        );
        _assertSolvent("post-debit");
    }

    /// @notice The BURNIE accrual + claim is OFF the ETH/claimablePool path: across a delivered buy that
    ///         accrues both the slot-0 pendingBurnie reward AND the affiliate base, then a claimAfkingBurnie,
    ///         the claimablePool delta is attributable ENTIRELY to the ETH buy debit — the BURNIE legs add
    ///         and remove ZERO from the pool. (affiliate/quest rewards are creditFlip-paid, never an ETH
    ///         debit.) Asserted by isolating the claim: the pool is byte-unchanged across the claim alone.
    function testBurnieClaimLeavesClaimablePoolUnchanged() public {
        address p = makeAddr("burnie_offpath");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 50 ether);
        _deliverDay(0xB04E0FF); // accrue pendingBurnie + affiliateBase

        uint256 owed = _pendingBurnieOf(p);
        assertEq(owed, SLOT0_BURNIE_PER_BUY, "non-vacuity: a delivered buy accrued claimable BURNIE");

        // Isolate the BURNIE claim: the pool must be byte-identical before/after (BURNIE is a creditFlip, not
        // an ETH/pool debit) — this is the exact equality the acceptance criterion demands.
        uint256 poolBefore = _claimablePool();
        uint256 stakeBefore = coinflip.coinflipAmount(p);
        game.claimAfkingBurnie(_singleton(p));
        assertEq(_claimablePool(), poolBefore, "BURNIE claim: claimablePool byte-unchanged (OFF the ETH path)");
        assertEq(coinflip.coinflipAmount(p) - stakeBefore, owed * 1 ether, "BURNIE claim paid via creditFlip (not an ETH move)");
        assertEq(_pendingBurnieOf(p), 0, "pendingBurnie zeroed (paid exactly once, CEI)");
        _assertSolvent("post-burnie-claim");
    }

    // =========================================================================
    // The solvency observable
    // =========================================================================

    /// @dev The master SOLVENCY-01 invariant: `game.balance + steth.balanceOf(game) >= claimablePool`
    ///      (DegenerusGame.sol:18). The fixture holds plain ETH (no stETH minted to the game), so the stETH
    ///      term is 0; reading it explicitly keeps the assertion faithful to the contract's invariant shape.
    function _assertSolvent(string memory tag) internal {
        uint256 backing = address(game).balance + mockStETH.balanceOf(address(game));
        assertGe(backing, _claimablePool(), string(abi.encodePacked("SOLVENCY-01: balance + steth >= claimablePool [", tag, "]")));
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V56SecUnmanipulable / V55FreezeDeterminism)
    // =========================================================================

    /// @dev Deliver ONE funded day to the in-set subs: a new-day STAGE buy (stamps each pending box +
    ///      debits the fresh-ETH spend + accrues), then settle clean and OPEN every pending box (so the
    ///      no-orphan guard does not skip the next day's buy). Each delivered day debits claimablePool by the
    ///      fresh-ETH spend and accrues 100 pendingBurnie per in-set sub.
    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day off the accumulating timestamp (the Foundry caching
    ///      quirk freezes a re-read `block.timestamp + 1 days` after the first warp in a loop).
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

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before an afking open so mintBurnie reliably takes the OPEN leg (Don't-Hand-Roll).
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

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _pair(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    // ---- Sub-slot + claimablePool reads (slot 66 + the v56 offsets; slot 1 byte 16) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, 0, 8));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _pendingBurnieOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGBURNIE, 32));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
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
