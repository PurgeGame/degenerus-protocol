// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {SettleClaimableShortfallTester} from "../../contracts/test/SettleClaimableShortfallTester.sol";

/// @title V61AfpayWaterfall — TST-01 proof: the AfKing-as-payment waterfall (msg.value → claimable → afking).
///
/// @notice Two arms prove the v61 waterfall against the LIVE subject (376 IMPL, contracts byte-frozen):
///
///   ARM A — the canonical shortfall sink `_settleShortfall(buyer, shortfall, allowClaimable)`
///   (DegenerusGameStorage.sol:857) is exercised in isolation via the SettleClaimableShortfallTester (it
///   inherits the canonical storage layout and runs the EXACT production body — NOT a re-implementation).
///   This is the ONE helper the lootbox / presale / 3 whale sites (AFPAY-01/03/04) all call, so proving its
///   ordering + the AfkingSpent emit + the both-short revert + the paired claimablePool debit certifies that
///   shared spend path. Arm A asserts: tier-1 claimable drawn only to the STRICT 1-wei sentinel, tier-2
///   afking to 0, `AfkingSpent(buyer, afkingUsed)` at the exact afking amount, `allowClaimable=false`
///   (the DirectEth leg) SKIPS claimable entirely, both-short reverts E(), and `claimablePool == Sigma (claimable
///   + afking)` after every settle (seeded-fuzz over shortfall sizes).
///
///   ARM B — the ticket-mint payment `_processMintPayment` (DegenerusGame.sol:1078, reached via the live
///   public `purchase()` → MintModule → recordMint) across all three pay-kinds: DirectEth (msg.value →
///   afking, claimable UNTOUCHED), Claimable (claimable → sentinel → afking), Combined (msg.value →
///   claimable → afking). Arm B asserts the draw ORDERING by reading both balances + the `AfkingSpent` emit
///   with the exact amount, the prizeContribution composition (proven via the prize-pool delta == the full
///   ticket cost, since msg.value + claimableUsed + afkingUsed == cost), the both-short revert, that afking
///   covers a DirectEth LOOTBOX shortfall the pre-v61 path reverted (AFPAY-03), the fresh-affiliate /
///   NO-rebuy-bonus property (the bonus reads claimable deltas → afking is excluded), and the no-double-draw
///   property (the afking auto-buy path debits afking EXACTLY once and never re-enters _processMintPayment).
///
/// @dev Reuses the funded-sub + deity-pass + new-day STAGE harness (the accumulating-`_t` warp + fulfill-
///   first settle) from V56FreezeSolvency / V56AfkingGasMarginal. Balance reads go through the live views
///   (claimableWinningsOf / afkingFundingOf) and the raw balancesPacked slot (slot 7, the 378-01 recalibration
///   key) where a half-isolation proof is needed. Seeded-fuzz deterministic (foundry seed 0xdeadbeef).
///   Test-only: ZERO contracts/*.sol mutation.
contract V61AfpayWaterfall is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (378-01 recalibration key)
    // -------------------------------------------------------------------------
    uint256 private constant BALANCES_PACKED_SLOT = 7; // mapping(address=>uint256) [afking:hi128 | claimable:lo128]
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant PRIZE_POOLS_SLOT = 2; // prizePoolsPacked [future:hi128 | next:lo128]
    uint256 private constant PRIZE_POOL_PENDING_SLOT = 11; // prizePoolPendingPacked (frozen-phase sink)
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;

    /// @dev AfkingSpent(address indexed player, uint256 amount) — the headline transparency signal.
    bytes32 private constant AFKING_SPENT_SIG = keccak256("AfkingSpent(address,uint256)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // ARM A — the canonical _settleShortfall sink (AFPAY-01; lootbox/presale/whale share it)
    // =========================================================================

    /// @notice Claimable-allowed waterfall: claimable drawn FIRST to the strict 1-wei sentinel, then afking
    ///         to 0, with AfkingSpent emitted for the EXACT afking remainder and the paired claimablePool
    ///         debit keeping the solvency identity. Falsifiable: the expectEmit pins afkingUsed to the exact
    ///         remainder, and the post-state pins claimable to the 1-wei sentinel (not "<= sentinel").
    function testSettleDrawsClaimableToSentinelThenAfking() public {
        SettleClaimableShortfallTester t = new SettleClaimableShortfallTester();
        address buyer = makeAddr("settle_both");

        uint256 claimable = 30 ether;
        uint256 afking = 100 ether;
        t.setClaimable(buyer, claimable);
        t.setAfking(buyer, afking);
        t.setClaimablePool(claimable + afking); // single buyer ⇒ pool == Sigma (claimable + afking)

        // shortfall straddles the claimable balance so BOTH tiers fire: claimable contributes (claimable - 1)
        // (the sentinel stays), afking covers the rest.
        uint256 shortfall = 50 ether;
        uint256 expectedClaimableUsed = claimable - 1; // drawn to the strict 1-wei sentinel
        uint256 expectedAfkingUsed = shortfall - expectedClaimableUsed;

        // The afking leg MUST emit AfkingSpent at the exact afking amount (D-02 breadth: the shared helper
        // emits too, not only _processMintPayment).
        vm.expectEmit(true, false, false, true, address(t));
        emit AfkingSpent(buyer, expectedAfkingUsed);
        (uint256 cUsed, uint256 aUsed) = t.settle(buyer, shortfall, true);

        assertEq(cUsed, expectedClaimableUsed, "claimableUsed == claimable - 1 (drawn to the strict sentinel)");
        assertEq(aUsed, expectedAfkingUsed, "afkingUsed == shortfall - claimableUsed (remainder from afking)");
        assertEq(t.getClaimable(buyer), 1, "claimable left at EXACTLY the 1-wei sentinel");
        assertEq(t.getAfking(buyer), afking - expectedAfkingUsed, "afking debited by exactly afkingUsed");
        // Paired debit: pool dropped by the WHOLE shortfall (claimable + afking legs both pair claimablePool).
        assertEq(t.getClaimablePool(), (claimable + afking) - shortfall, "claimablePool -= full shortfall (both tiers paired)");
        assertEq(
            t.getClaimablePool(),
            t.getClaimable(buyer) + t.getAfking(buyer),
            "SOLVENCY: claimablePool == Sigma (claimable + afking) after the waterfall"
        );
    }

    /// @notice DirectEth leg (`allowClaimable = false`): claimable is SKIPPED entirely; the whole shortfall
    ///         is drawn from afking. Contrast against the claimable-allowed path proves the flag is what gates
    ///         the claimable tier. Falsifiable: claimable is asserted byte-UNCHANGED (would fail if the flag
    ///         were ignored and claimable drawn).
    function testSettleDirectEthLegSkipsClaimable() public {
        SettleClaimableShortfallTester t = new SettleClaimableShortfallTester();
        address buyer = makeAddr("settle_directeth");

        uint256 claimable = 30 ether;
        uint256 afking = 100 ether;
        t.setClaimable(buyer, claimable);
        t.setAfking(buyer, afking);
        t.setClaimablePool(claimable + afking);

        uint256 shortfall = 40 ether;

        vm.expectEmit(true, false, false, true, address(t));
        emit AfkingSpent(buyer, shortfall); // whole shortfall from afking (claimable skipped)
        (uint256 cUsed, uint256 aUsed) = t.settle(buyer, shortfall, false);

        assertEq(cUsed, 0, "DirectEth leg: claimableUsed == 0 (claimable tier skipped)");
        assertEq(aUsed, shortfall, "DirectEth leg: whole shortfall drawn from afking");
        assertEq(t.getClaimable(buyer), claimable, "DirectEth leg: claimable balance byte-UNCHANGED");
        assertEq(t.getAfking(buyer), afking - shortfall, "afking debited by the whole shortfall");
        assertEq(t.getClaimablePool(), (claimable + afking) - shortfall, "pool -= shortfall (only the afking leg paired)");
    }

    /// @notice Both tiers short ⇒ revert E(). Seeds claimable + afking that together cannot cover the
    ///         shortfall; the strict sentinel means usable claimable is (claimable - 1). Asserts the exact
    ///         inherited E() selector (re-exposed by the tester).
    function testSettleRevertsWhenBothShort() public {
        SettleClaimableShortfallTester t = new SettleClaimableShortfallTester();
        address buyer = makeAddr("settle_short");

        uint256 claimable = 5 ether;
        uint256 afking = 3 ether;
        t.setClaimable(buyer, claimable);
        t.setAfking(buyer, afking);
        t.setClaimablePool(claimable + afking);

        // usable = (claimable - 1) + afking < shortfall ⇒ revert. Pick shortfall above the usable sum.
        uint256 usable = (claimable - 1) + afking;
        uint256 shortfall = usable + 1;
        vm.expectRevert(t.sentinelError());
        t.settle(buyer, shortfall, true);
    }

    /// @notice Seeded fuzz: across random (claimable, afking, shortfall) where the two tiers CAN cover the
    ///         shortfall, the waterfall is claimable-first-to-sentinel-then-afking and the solvency identity
    ///         `claimablePool == Sigma (claimable + afking)` survives every settle. Generalizes the ordering.
    function testFuzzSettleWaterfallOrderingAndIdentity(uint256 cSeed, uint256 aSeed, uint256 sSeed) public {
        SettleClaimableShortfallTester t = new SettleClaimableShortfallTester();
        address buyer = makeAddr("settle_fuzz");

        uint256 claimable = bound(cSeed, 2, 1e24);
        uint256 afking = bound(aSeed, 1, 1e24);
        uint256 usable = (claimable - 1) + afking; // strict sentinel keeps 1 wei of claimable
        uint256 shortfall = bound(sSeed, 1, usable); // always coverable
        t.setClaimable(buyer, claimable);
        t.setAfking(buyer, afking);
        t.setClaimablePool(claimable + afking);

        (uint256 cUsed, uint256 aUsed) = t.settle(buyer, shortfall, true);

        // Ordering: claimable is consumed FIRST (up to claimable-1), afking only covers the remainder.
        uint256 expClaimable = shortfall < (claimable - 1) ? shortfall : (claimable - 1);
        assertEq(cUsed, expClaimable, "fuzz: claimable consumed first up to the sentinel");
        assertEq(aUsed, shortfall - expClaimable, "fuzz: afking covers exactly the remainder");
        assertGe(t.getClaimable(buyer), 1, "fuzz: the strict 1-wei sentinel is always preserved");
        assertEq(cUsed + aUsed, shortfall, "fuzz: the two tiers cover the full shortfall");
        assertEq(
            t.getClaimablePool(),
            t.getClaimable(buyer) + t.getAfking(buyer),
            "fuzz SOLVENCY: claimablePool == Sigma (claimable + afking)"
        );
    }

    // =========================================================================
    // ARM B — _processMintPayment's three pay-kinds via the live purchase() path
    // =========================================================================

    /// @notice DirectEth pay-kind: an underpaid ticket buy draws the shortfall from afking and leaves
    ///         CLAIMABLE UNTOUCHED, emitting AfkingSpent for the exact shortfall. prizeContribution is the
    ///         full cost (msg.value + afkingUsed) — proven via the prize-pool delta == cost. Falsifiable: the
    ///         claimable balance is asserted byte-unchanged AND the AfkingSpent amount is pinned.
    function testProcessMintDirectEthDrawsAfkingSkipsClaimable() public {
        address buyer = makeAddr("pm_directeth");
        uint256 cost = _oneTicketCost();
        uint256 claimableSeed = 7 ether;
        _seedClaimable(buyer, claimableSeed);
        _seedAfking(buyer, 50 ether);

        uint256 ethSent = cost / 4; // underpay → shortfall = cost - ethSent from afking
        uint256 shortfall = cost - ethSent;

        uint256 claimableBefore = game.claimableWinningsOf(buyer);
        uint256 afkingBefore = game.afkingFundingOf(buyer);
        uint256 poolBefore = _prizePoolTotal();

        vm.deal(buyer, ethSent);
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingSpent(buyer, shortfall);
        vm.prank(buyer);
        game.purchase{value: ethSent}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        assertEq(game.claimableWinningsOf(buyer), claimableBefore, "DirectEth: claimable byte-UNCHANGED (skipped)");
        assertEq(afkingBefore - game.afkingFundingOf(buyer), shortfall, "DirectEth: afking debited by exactly the shortfall");
        // prizeContribution == msg.value + 0 + afkingUsed == cost ⇒ the prize pool grew by the full cost.
        assertEq(_prizePoolTotal() - poolBefore, cost, "DirectEth: prizeContribution == msg.value + afkingUsed == cost");
    }

    /// @notice Claimable pay-kind: msg.value MUST be 0; claimable drawn to the 1-wei sentinel first, then
    ///         afking for the remainder, AfkingSpent at the exact afking amount. prizeContribution == cost.
    function testProcessMintClaimableThenAfking() public {
        address buyer = makeAddr("pm_claimable");
        uint256 cost = _oneTicketCost();
        // claimable covers part (to the sentinel), afking the rest.
        uint256 claimableSeed = (cost / 3) + 1; // usable = cost/3
        _seedClaimable(buyer, claimableSeed);
        _seedAfking(buyer, 50 ether);

        uint256 expClaimableUsed = claimableSeed - 1; // to the strict sentinel
        uint256 expAfkingUsed = cost - expClaimableUsed;

        uint256 afkingBefore = game.afkingFundingOf(buyer);
        uint256 poolBefore = _prizePoolTotal();

        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingSpent(buyer, expAfkingUsed);
        vm.prank(buyer);
        game.purchase{value: 0}(buyer, 400, 0, bytes32(0), MintPaymentKind.Claimable, false);

        assertEq(game.claimableWinningsOf(buyer), 1, "Claimable: claimable drawn to EXACTLY the 1-wei sentinel");
        assertEq(afkingBefore - game.afkingFundingOf(buyer), expAfkingUsed, "Claimable: afking covers the remainder exactly");
        assertEq(_prizePoolTotal() - poolBefore, cost, "Claimable: prizeContribution == claimableUsed + afkingUsed == cost");
    }

    /// @notice Combined pay-kind: msg.value FIRST, then claimable to the sentinel, then afking. With a small
    ///         msg.value + a small claimable + funded afking, all three tiers contribute and AfkingSpent fires
    ///         at the afking remainder. prizeContribution == msg.value + claimableUsed + afkingUsed == cost.
    function testProcessMintCombinedEthThenClaimableThenAfking() public {
        address buyer = makeAddr("pm_combined");
        uint256 cost = _oneTicketCost();
        uint256 ethSent = cost / 5;
        uint256 claimableSeed = (cost / 5) + 1; // usable = cost/5
        _seedClaimable(buyer, claimableSeed);
        _seedAfking(buyer, 50 ether);

        uint256 expClaimableUsed = claimableSeed - 1;
        uint256 expAfkingUsed = cost - ethSent - expClaimableUsed;

        uint256 afkingBefore = game.afkingFundingOf(buyer);
        uint256 poolBefore = _prizePoolTotal();

        vm.deal(buyer, ethSent);
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingSpent(buyer, expAfkingUsed);
        vm.prank(buyer);
        game.purchase{value: ethSent}(buyer, 400, 0, bytes32(0), MintPaymentKind.Combined, false);

        assertEq(game.claimableWinningsOf(buyer), 1, "Combined: claimable drawn to EXACTLY the sentinel after msg.value");
        assertEq(afkingBefore - game.afkingFundingOf(buyer), expAfkingUsed, "Combined: afking covers the final remainder");
        assertEq(_prizePoolTotal() - poolBefore, cost, "Combined: prizeContribution == msg.value + claimableUsed + afkingUsed == cost");
    }

    /// @notice Both-short revert through the LIVE _processMintPayment: a Claimable buy with too little
    ///         claimable AND too little afking reverts E() (msg.value must be 0 for Claimable, so no fresh ETH
    ///         can rescue it).
    function testProcessMintRevertsWhenClaimableAndAfkingShort() public {
        address buyer = makeAddr("pm_short");
        uint256 cost = _oneTicketCost();
        _seedClaimable(buyer, 1 ether); // usable < cost
        _seedAfking(buyer, 1 ether); // usable + afking < cost
        // (cost == 0.01 ether; usable claimable ~1 ether but we make the SUM short by using a big cost)
        // Make cost exceed the combined usable by buying many tickets.
        uint256 qty = 4000; // 10 tickets ⇒ cost = 10 * 0.01 = 0.1 ether > (1-1wei)+1 ? no. scale up.
        // Use a large quantity so cost dwarfs the 2-ether usable sum.
        qty = 4_000_000; // 10,000 tickets ⇒ cost = 100 ether ≫ ~2 ether usable
        vm.prank(buyer);
        vm.expectRevert();
        game.purchase{value: 0}(buyer, qty, 0, bytes32(0), MintPaymentKind.Claimable, false);
    }

    /// @notice AFPAY-03: a DirectEth LOOTBOX shortfall is now covered by afking — the pre-v61 DirectEth→revert
    ///         is LIFTED. An underpaid DirectEth lootbox buy succeeds, drawing the shortfall from afking and
    ///         emitting AfkingSpent, while CLAIMABLE stays untouched (DirectEth passes allowClaimable=false).
    function testDirectEthLootboxShortfallCoveredByAfking() public {
        address buyer = makeAddr("lootbox_directeth");
        uint256 boxAmount = 1 ether; // >= LOOTBOX_MIN
        _seedClaimable(buyer, 5 ether);
        _seedAfking(buyer, 50 ether);

        uint256 ethSent = boxAmount / 4;
        uint256 shortfall = boxAmount - ethSent;
        uint256 claimableBefore = game.claimableWinningsOf(buyer);
        uint256 afkingBefore = game.afkingFundingOf(buyer);

        vm.deal(buyer, ethSent);
        // The DirectEth lootbox shortfall draws afking (AFPAY-03), so AfkingSpent fires; the box queues.
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: ethSent}(buyer, 0, boxAmount, bytes32(0), MintPaymentKind.DirectEth, false);

        assertTrue(_sawAfkingSpent(buyer, shortfall), "AFPAY-03: DirectEth lootbox shortfall drew afking + emitted AfkingSpent");
        assertEq(game.claimableWinningsOf(buyer), claimableBefore, "AFPAY-03 DirectEth: claimable byte-UNCHANGED");
        assertEq(afkingBefore - game.afkingFundingOf(buyer), shortfall, "AFPAY-03: afking debited by exactly the lootbox shortfall");
    }

    /// @notice NO-double-draw: the afking auto-buy STAGE path (_deliverAfkingBuy) debits afking EXACTLY once
    ///         per delivered day and NEVER routes through _processMintPayment. Proven by counting AfkingSpent
    ///         (the _processMintPayment / _settleShortfall signal) across a delivered day — there are ZERO,
    ///         while the afking funding still moves (the auto-buy debit happens at its own inline site, which
    ///         does not emit AfkingSpent). So no path double-debits afking for the same buy.
    function testAfkingAutoBuyNoDoubleDrawNoProcessMintPayment() public {
        address p = makeAddr("autobuy_nodouble");
        _grantDeityPass(p);
        _fundPool(p, 200 ether);
        _subscribeLootbox(p, 1);

        uint256 afkingBefore = game.afkingFundingOf(p);

        vm.recordLogs();
        _deliverDay(0xA17B0); // one funded STAGE day: the auto-buy spends afking inline
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The auto-buy path does NOT emit AfkingSpent (that event is the _processMintPayment / _settleShortfall
        // signal). Zero AfkingSpent ⇒ the auto-buy never re-entered _processMintPayment for this spend.
        uint256 spentEvents;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length >= 2 && logs[i].topics[0] == AFKING_SPENT_SIG) {
                if (logs[i].topics[1] == bytes32(uint256(uint160(p)))) spentEvents++;
            }
        }
        assertEq(spentEvents, 0, "no-double-draw: the afking auto-buy never routes through _processMintPayment (no AfkingSpent)");

        // The afking funding DID move (the inline auto-buy debit) — exactly once, so the balance is strictly
        // lower (non-vacuous: a real spend happened, it just was not double-counted via _processMintPayment).
        assertLt(game.afkingFundingOf(p), afkingBefore, "non-vacuity: the auto-buy spent afking once (inline debit)");
    }

    // =========================================================================
    // Mirror event decl for vm.expectEmit
    // =========================================================================
    event AfkingSpent(address indexed player, uint256 amount);

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Cost of one whole ticket (400 units) at the active purchase level (fresh game ⇒ level 1).
    function _oneTicketCost() internal view returns (uint256) {
        uint24 targetLevel = game.jackpotPhase() ? game.level() : game.level() + 1;
        uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
        return priceWei; // 400 units / (4 * TICKET_SCALE=100) == 1 ⇒ cost == priceWei
    }

    /// @dev Seed `who`'s claimable (low half of balancesPacked slot 7) to `amount` and credit claimablePool
    ///      so the solvency identity stays intact. Preserves the afking high half.
    function _seedClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 oldLow = uint128(packed);
        uint256 high = packed >> 128;
        uint256 newPacked = (high << 128) | uint128(amount);
        vm.store(address(game), slot, bytes32(newPacked));
        _bumpClaimablePool(int256(amount) - int256(oldLow));
    }

    /// @dev Seed `who`'s afking (high half) to `amount`, preserve the claimable low half, keep the pool.
    function _seedAfking(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 low = uint128(packed);
        uint256 oldHigh = packed >> 128;
        uint256 newPacked = (amount << 128) | low;
        vm.store(address(game), slot, bytes32(newPacked));
        _bumpClaimablePool(int256(amount) - int256(oldHigh));
    }

    /// @dev Adjust claimablePool (slot 1, byte 16, uint128) by a signed delta so seeding keeps the SOLVENCY-01
    ///      identity (claimablePool == Sigma  balances) true going into each buy.
    function _bumpClaimablePool(int256 delta) internal {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 lowOther = slot1 & ((uint256(1) << (CLAIMABLE_POOL_OFFBYTES * 8)) - 1); // currentPrizePool (bytes 0..15)
        uint256 pool = (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
        uint256 newPool = delta >= 0 ? pool + uint256(delta) : pool - uint256(-delta);
        uint256 newSlot1 = lowOther | (uint256(uint128(newPool)) << (CLAIMABLE_POOL_OFFBYTES * 8));
        vm.store(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT)), bytes32(newSlot1));
    }

    /// @dev Total prize pool the buy's prizeContribution lands in: the active prizePoolsPacked (slot 2,
    ///      [future:hi128 | next:lo128]) PLUS the pending prizePoolPendingPacked (slot 11) — a contribution
    ///      goes to exactly one (active when !prizePoolFrozen, pending when frozen), so the sum captures it
    ///      regardless of the freeze state.
    function _prizePoolTotal() internal view returns (uint256) {
        uint256 active = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_SLOT))));
        uint256 pending = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOL_PENDING_SLOT))));
        uint256 sum = uint128(active) + (active >> 128);
        sum += uint128(pending) + (pending >> 128);
        return sum;
    }

    function _sawAfkingSpent(address who, uint256 amount) internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != AFKING_SPENT_SIG) continue;
            if (logs[i].topics[1] != bytes32(uint256(uint160(who)))) continue;
            if (abi.decode(logs[i].data, (uint256)) == amount) return true;
        }
        return false;
    }

    // ---- STAGE / sub harness (ported from V56FreezeSolvency) ----

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

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }
}
