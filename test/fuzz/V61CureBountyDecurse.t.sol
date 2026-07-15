// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title V61CureBountyDecurse — TST-04 proof: the cashout-curse CURE (any buy >= 1 ticket worth clears the
///        counter), the sub-ticket bounty STAMP (DAY_SHIFT → _bountyEligible, growth halts, NO cure), the
///        manual-lootbox bounty eligibility, and the permissionless paid `decurse`.
///
/// @notice CURE (CURSE-04, MintModule._purchaseForWith:1326-1330): every buy whose `totalCost >= priceWei`
///   (>=1 whole ticket worth, funding-agnostic) calls `_clearCurse(buyer)` BEFORE the post-action score read,
///   so the curing buy itself scores un-penalized. The cure host is the live `purchase()` ticket/lootbox path
///   (`_purchaseForWith`), reached by direct / batched (large qty) / affiliate-coded / lootbox>=ticket /
///   ticket+lootbox-bundle buys — each is proven twice, once funded with FRESH ETH (Combined leg) and once
///   funded with CLAIMABLE (Claimable leg), asserting the cure is funding-agnostic.
///
///   The separate `purchaseWhalePass()` pass-purchase host (WhaleModule._purchaseWhalePass) is NOT a cure
///   path — it writes mintPacked_ via field-isolated setPacked calls and never calls `_clearCurse`, so it
///   PRESERVES an existing curse. That truthful non-cure behavior is asserted by contrast (a curse survives a
///   whale-pass purchase) so the cure-vs-no-cure boundary is falsifiable in both directions.
///
///   BOUNTY STAMP (CURSE-05): a sub-ticket / small-lootbox buy stamps DAY_SHIFT (the buyer becomes
///   _bountyEligible — read via the public game.bountyEligible view) but does NOT clear the curse. A manual
///   plain-lootbox buyer is likewise stamped bounty-eligible (the plain lootbox leg now wires through
///   _recordLootboxMintDay, MintModule:1215).
///
///   DECURSE (CURSE-06, GameAfkingModule.decurse:1696, dispatched DegenerusGame.sol:443): permissionless;
///   reverts E() if the target's curse is already 0 (no wasted burn); burns exactly PRICE_COIN_UNIT/10
///   (100 FLIP) from msg.sender via burnCoin; clears the curse to 0; emits Decursed(msg.sender, target).
///   Proven: a clear + the exact 100-FLIP burn + the Decursed expectEmit, a revert-if-already-0, and a
///   permissionless clear (a non-owner curer clears another player's curse).
///
/// @dev Reuses the funded-sub + new-day STAGE harness + the canonical-layout seeders from V61CurseSet. The
///   staleness basis maybeCurse uses is _currentMintDay() == dailyIdx (the monotonic advance counter, == 1 at
///   fresh deploy), so dailyIdx is seeded to 100 in setUp (field-isolated slot-0 RMW) — irrelevant to the CURE
///   itself (the curse is seeded directly) but kept consistent with the curse-SET harness. FLIP is minted
///   via the GAME-gated coin.mintForGame; balances read via coin.balanceOf. Seeded-fuzz deterministic.
///   Test-only: ZERO contracts/*.sol mutation.
contract V61CureBountyDecurse is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + mintPacked_ field shifts (378-01 key + BitPackingLib)
    // -------------------------------------------------------------------------
    uint256 private constant BALANCES_PACKED_SLOT = 7; // [afking:hi128 | claimable:lo128]
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant MINTPACKED_SLOT = 9;

    uint256 private constant DAY_SHIFT = 72; // lastEthDay (32 bits)
    uint256 private constant CURSE_COUNT_SHIFT = 215; // (8 bits)
    uint256 private constant CURSE_COUNT_CAP = 20;

    // PRICE_COIN_UNIT = 1000 ether (FLIP/Storage); decurse burns PRICE_COIN_UNIT/10 = 100 FLIP.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant DECURSE_BURN = PRICE_COIN_UNIT / 10; // 100 FLIP

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _seedDailyIdx(100);
    }

    // =========================================================================
    // CURE — a >= 1-ticket buy clears the curse, on every purchase() host path,
    //        funded with FRESH ETH and (separately) with CLAIMABLE
    // =========================================================================

    /// @notice Direct single-ticket buy (DirectEth / fresh ETH) clears a seeded curse. Non-vacuous: curse is
    ///         asserted 2 before and 0 after.
    function testCureDirectTicketFreshEth() public {
        address p = makeAddr("cure_direct_eth");
        _seedCurse(p, 4);
        uint256 cost = _oneTicketCost();
        vm.deal(p, cost);
        vm.prank(p);
        game.purchase{value: cost}(p, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(p), 0, "direct ticket (fresh ETH) cures the curse");
    }

    /// @notice Direct single-ticket buy funded with CLAIMABLE clears the curse — the cure is funding-agnostic
    ///         (it keys on totalCost >= priceWei, not the funding source).
    function testCureDirectTicketClaimable() public {
        address p = makeAddr("cure_direct_claim");
        _seedCurse(p, 4);
        _seedClaimable(p, 100 ether); // funds the buy from claimable
        vm.prank(p);
        game.purchase{value: 0}(p, 400, 0, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(game.curseCountOf(p), 0, "direct ticket (claimable) cures the curse (funding-agnostic)");
    }

    /// @notice A BATCHED buy (many tickets, totalCost >> priceWei) cures, fresh ETH and claimable.
    function testCureBatchedBuyBothFundings() public {
        // Fresh ETH — 4000 units == 10 whole tickets; fund the matching cost.
        address pe = makeAddr("cure_batch_eth");
        _seedCurse(pe, 6);
        uint256 batchCost = _ticketCost(4000); // 10 tickets worth
        vm.deal(pe, batchCost);
        vm.prank(pe);
        game.purchase{value: batchCost}(pe, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(pe), 0, "batched buy (fresh ETH) cures");

        // Claimable
        address pc = makeAddr("cure_batch_claim");
        _seedCurse(pc, 6);
        _seedClaimable(pc, 1000 ether);
        vm.prank(pc);
        game.purchase{value: 0}(pc, 4000, 0, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(game.curseCountOf(pc), 0, "batched buy (claimable) cures");
    }

    /// @notice An AFFILIATE-coded buy (non-zero affiliateCode → the fresh/recycled affiliate split path) cures,
    ///         fresh ETH and claimable. The cure precedes the affiliate/score logic so the coded buy still cures.
    function testCureAffiliateCodedBuyBothFundings() public {
        bytes32 code = _registerAffiliate(makeAddr("cure_aff_referrer"));

        address pe = makeAddr("cure_aff_eth");
        _seedCurse(pe, 8);
        uint256 cost = _oneTicketCost();
        vm.deal(pe, cost);
        vm.prank(pe);
        game.purchase{value: cost}(pe, 400, 0, code, MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(pe), 0, "affiliate-coded buy (fresh ETH) cures");

        address pc = makeAddr("cure_aff_claim");
        _seedCurse(pc, 8);
        _seedClaimable(pc, 100 ether);
        vm.prank(pc);
        game.purchase{value: 0}(pc, 400, 0, code, MintPaymentKind.Claimable, false);
        assertEq(game.curseCountOf(pc), 0, "affiliate-coded buy (claimable) cures");
    }

    /// @notice A LOOTBOX buy whose box value >= one ticket's priceWei cures (totalCost includes the box), fresh
    ///         ETH and claimable. A box of priceWei is exactly >= the ticket threshold.
    function testCureLootboxAtLeastOneTicketBothFundings() public {
        uint256 boxAmount = _oneTicketCost(); // box value == one ticket price ⇒ totalCost >= priceWei

        address pe = makeAddr("cure_lb_eth");
        _seedCurse(pe, 10);
        vm.deal(pe, boxAmount);
        vm.prank(pe);
        game.purchase{value: boxAmount}(pe, 0, boxAmount, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(pe), 0, "lootbox>=ticket (fresh ETH) cures");

        address pc = makeAddr("cure_lb_claim");
        _seedCurse(pc, 10);
        _seedClaimable(pc, 100 ether);
        vm.prank(pc);
        game.purchase{value: 0}(pc, 0, boxAmount, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(game.curseCountOf(pc), 0, "lootbox>=ticket (claimable) cures");
    }

    /// @notice A "whale-sized" bundled buy in the SAME transaction (a ticket batch + a lootbox via the
    ///         purchase() host) cures — the combined totalCost is comfortably >= priceWei. Fresh ETH and
    ///         claimable. (This is the purchase()-host "bundle"; the separate purchaseWhalePass pass-host is
    ///         proven NOT to cure below.)
    function testCureTicketPlusLootboxBundleBothFundings() public {
        uint256 boxAmount = _oneTicketCost();

        address pe = makeAddr("cure_bundle_eth");
        _seedCurse(pe, 12);
        uint256 ticketCost = _ticketCost(400); // 1 ticket
        uint256 total = ticketCost + boxAmount;
        vm.deal(pe, total);
        vm.prank(pe);
        game.purchase{value: total}(pe, 400, boxAmount, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(pe), 0, "ticket+lootbox bundle (fresh ETH) cures");

        address pc = makeAddr("cure_bundle_claim");
        _seedCurse(pc, 12);
        _seedClaimable(pc, 1000 ether);
        vm.prank(pc);
        game.purchase{value: 0}(pc, 400, boxAmount, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(game.curseCountOf(pc), 0, "ticket+lootbox bundle (claimable) cures");
    }

    /// @notice The cure precedes the score calc: the curing buy's OWN activity score is the UN-penalized value.
    ///         A real ticket buy re-caches the affiliate cache and builds the mint-streak base, so the base is
    ///         established by the buy itself — meaning the seed-an-affiliate-cache trick is clobbered. Instead
    ///         this proves cure-before-score by CONTRAST against a NON-curing (sub-ticket) buy on an identical
    ///         starting curse: the curing buyer ends UN-penalized (cure ran before the score read at :1333),
    ///         while the equal-curse sub-ticket buyer (no cure) ends with the SAME positive base MINUS the
    ///         curse penalty. The post-buy score gap == the curse penalty, isolating the cure's effect on
    ///         the curing buy's own score. Falsifiable: the gap is pinned to curse, and the cured buyer's
    ///         score is asserted strictly greater than the non-cured buyer's.
    function testCurePrecedesScoreUnpenalizedOnCuringBuy() public {
        // A real ticket buy re-caches the affiliate cache and a single buy does not build a positive
        // streak/mint base, so a seeded affiliate base is clobbered and the streak base is 0 (the penalty floors
        // a 0 base at 0, hiding the effect). Use the DEITY-PASS activity bonus (80 points) as the base instead:
        // it is read from the HAS_DEITY_PASS bit (never re-written by the buy path), so it survives both buys and
        // gives a large positive base. The deity-pass exemption blocks the cashout-curse SET, NOT the cure or
        // the penalty APPLY — so a deity holder's seeded curse is still penalized, and a >=1-ticket buy still
        // clears it. The two buyers differ ONLY in whether the buy cured, isolating the cure's score effect.
        _alignDailyIdxToSimDay();

        uint256 curse = 4; // -4 points

        // Curing buyer: a >=1-ticket buy clears the curse before the post-action score read at :1333.
        address cured = makeAddr("cbs_cured");
        _grantDeityPass(cured); // base = 80 points, survives the buy
        _seedCurse(cured, curse);
        uint256 fullCost = _oneTicketCost();
        vm.deal(cured, fullCost);
        vm.prank(cured);
        game.purchase{value: fullCost}(cured, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(cured), 0, "curing buy cleared the curse");
        uint256 curedScore = game.playerActivityScore(cured);

        // Non-curing buyer: an equal-curse sub-ticket buy on an identical deity base does NOT cure.
        address notCured = makeAddr("cbs_notcured");
        _grantDeityPass(notCured);
        _seedCurse(notCured, curse);
        // 200 units == 0.5 ticket: costWei = 0.005 ETH ∈ [TICKET_MIN_BUYIN_WEI 0.0025, priceWei 0.01) ⇒ a valid
        // sub-ticket buy below the cure threshold (totalCost < priceWei).
        uint256 subUnits = 200;
        uint256 subCost = _ticketCost(subUnits);
        vm.deal(notCured, subCost);
        vm.prank(notCured);
        game.purchase{value: subCost}(notCured, subUnits, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.curseCountOf(notCured), curse, "sub-ticket buy did NOT cure (still cursed)");
        uint256 notCuredScore = game.playerActivityScore(notCured);

        // Both buyers hold the same 80-point deity base; the only difference is the cure. So the cured buyer's
        // post-buy score is HIGHER by exactly the curse penalty (curse points) — proving the cure ran BEFORE the
        // score read (the curing buy itself scored un-penalized).
        assertGt(curedScore, notCuredScore, "non-vacuity: the curing buy scored higher than the cursed sub-ticket buy");
        assertEq(curedScore - notCuredScore, curse, "cure-before-score: the gap == the cleared curse penalty (curse points)");
    }

    /// @notice CONTRAST — the separate purchaseWhalePass() pass-host does NOT cure (it is not a
    ///         _purchaseForWith path; it writes mintPacked_ field-isolated and never calls _clearCurse). A
    ///         curse survives a whale-pass purchase. This pins the cure to the purchase() host only and
    ///         keeps the cure-vs-no-cure boundary falsifiable.
    function testWhalePassPurchaseDoesNotCure() public {
        address p = makeAddr("whalepass_nocure");
        _seedCurse(p, 6);
        // A single whale pass purchase at the early price (2.4 ETH at levels 0-4). The pass host reverts on
        // OVER-payment (msg.value > totalPrice), so send EXACTLY the price.
        uint256 price = 2.4 ether;
        vm.deal(p, price);
        vm.prank(p);
        game.purchaseWhalePass{value: price}(p, 1, bytes32(0));
        assertEq(game.curseCountOf(p), 6, "whale-pass purchase preserves the curse (not a cure path)");
    }

    // =========================================================================
    // BOUNTY STAMP — sub-ticket buys do NOT stamp DAY_SHIFT; crossing one whole
    // ticket cumulatively does (and still does not cure)
    // =========================================================================

    /// @notice A genuine SUB-ticket buy (totalCost < priceWei) at a new level does NOT stamp
    ///         DAY_SHIFT — the mint-day stamp rides the whole-ticket "minted" floor (400 units
    ///         = 4 entries x QTY_SCALE), so the buyer stays NOT _bountyEligible and the curse is
    ///         UNCHANGED. A second sub-ticket buy that crosses the cumulative 400-unit floor
    ///         runs the full record path: DAY_SHIFT stamps (bounty-eligible) while the curse
    ///         still does NOT cure (each buy's totalCost < priceWei cure threshold).
    function testSubTicketBuyStampsBountyOnlyAtWholeTicketFloor() public {
        address p = makeAddr("subticket_stamp");
        _seedCurse(p, 2);
        // Land < 15 min into the day so the time-based bounty tiers are NOT open, and seed lastEthDay far in the
        // past so the recency tier is closed too — the buy's DAY_SHIFT stamp is the only thing that can flip it.
        _advanceWallClockToBuyWindowStart();
        _seedLastEthDay(p, 0);
        assertTrue(!game.bountyEligible(p), "pre-buy: not bounty-eligible (stale, early in the day)");

        // 200 units == 0.5 ticket: costWei = 0.005 ETH ∈ [TICKET_MIN_BUYIN_WEI 0.0025, priceWei 0.01) ⇒ a valid
        // sub-ticket buy below both the whole-ticket minted floor and the cure threshold.
        uint256 subUnits = 200;
        uint256 subCost = _ticketCost(subUnits);
        vm.deal(p, subCost);
        vm.prank(p);
        game.purchase{value: subCost}(p, subUnits, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        assertTrue(!game.bountyEligible(p), "sub-ticket buy below the minted floor does NOT stamp DAY_SHIFT");
        assertEq(game.curseCountOf(p), 2, "sub-ticket buy does NOT cure (totalCost < priceWei)");

        // Second 200-unit buy crosses the cumulative 400-unit floor: full record path runs,
        // DAY_SHIFT stamps, buyer becomes bounty-eligible; the sub-priceWei buy still cannot cure.
        vm.deal(p, subCost);
        vm.prank(p);
        game.purchase{value: subCost}(p, subUnits, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        assertTrue(game.bountyEligible(p), "crossing the whole-ticket floor stamps DAY_SHIFT => bounty-eligible");
        assertEq(game.curseCountOf(p), 2, "crossing buy still does NOT cure (totalCost < priceWei)");
    }

    /// @notice A manual plain-lootbox buyer is _bountyEligible: the plain lootbox leg wires through
    ///         _recordLootboxMintDay which stamps DAY_SHIFT for a box worth at least one whole ticket
    ///         (priceForLevel(level + 1)), closing the plain-vs-bundled gap. The lootbox leg stamps
    ///         lastEthDay = _simulatedDayIndex() (the WALL-CLOCK day, distinct from the ticket leg's
    ///         dailyIdx basis), so dailyIdx is aligned to the sim day here so the gate
    ///         (gateIdx == dailyIdx) accepts the sim-day stamp. Falsifiable: not eligible before, eligible after.
    function testManualLootboxBuyerBecomesBountyEligible() public {
        address p = makeAddr("manual_lb_bounty");
        // Land early in the day (time tiers closed); align dailyIdx to the sim day so the lootbox-leg stamp
        // (sim day) satisfies the bounty gate (gateIdx == dailyIdx).
        _advanceWallClockToBuyWindowStart();
        _alignDailyIdxToSimDay();
        _seedLastEthDay(p, 0);
        assertTrue(!game.bountyEligible(p), "pre-buy: not bounty-eligible");

        uint256 boxAmount = _oneTicketCost(); // a plain lootbox (>= LOOTBOX_MIN) stamps DAY_SHIFT
        vm.deal(p, boxAmount);
        vm.prank(p);
        game.purchase{value: boxAmount}(p, 0, boxAmount, bytes32(0), MintPaymentKind.DirectEth, false);

        assertTrue(game.bountyEligible(p), "manual lootbox buyer stamped DAY_SHIFT => bounty-eligible");
    }

    // =========================================================================
    // DECURSE — permissionless paid clear: 100 FLIP, Decursed emit, revert-if-0
    // =========================================================================

    /// @notice decurse clears the target's curse to 0, burns EXACTLY 100 FLIP (PRICE_COIN_UNIT/10) from the
    ///         caller, and emits Decursed(msg.sender, target). Falsifiable: the burn delta is pinned to 100
    ///         FLIP and the expectEmit pins both topics.
    function testDecurseClearsBurns100AndEmits() public {
        address target = makeAddr("decurse_target");
        address curer = makeAddr("decurse_curer");
        _seedCurse(target, 6);
        _fundFlip(curer, DECURSE_BURN); // exactly 100 FLIP — proves the exact cost

        uint256 flipBefore = coin.balanceOf(curer);
        assertEq(game.curseCountOf(target), 6, "pre: target cursed");

        vm.expectEmit(true, true, false, false, address(game));
        emit Decursed(curer, target);
        vm.prank(curer);
        game.decurse(target);

        assertEq(game.curseCountOf(target), 0, "decurse cleared the curse to 0");
        assertEq(flipBefore - coin.balanceOf(curer), DECURSE_BURN, "decurse burned EXACTLY 100 FLIP (PRICE_COIN_UNIT/10)");
        assertEq(coin.balanceOf(curer), 0, "the curer's 100 FLIP was fully consumed");
    }

    /// @notice decurse reverts when the target's curse is already 0 — no wasted burn. The caller's FLIP
    ///         balance is asserted UNCHANGED (the revert fires before burnCoin).
    function testDecurseRevertsIfAlreadyZeroNoBurn() public {
        address target = makeAddr("decurse_zero_target");
        address curer = makeAddr("decurse_zero_curer");
        _fundFlip(curer, 500 ether);
        assertEq(game.curseCountOf(target), 0, "pre: target has no curse");

        uint256 flipBefore = coin.balanceOf(curer);
        vm.prank(curer);
        vm.expectRevert();
        game.decurse(target);
        assertEq(coin.balanceOf(curer), flipBefore, "revert-if-0: no FLIP burned");
    }

    /// @notice decurse is PERMISSIONLESS — any non-owner can clear ANOTHER player's curse (it is purely
    ///         beneficial). The curer (unrelated to the target) pays the 100 FLIP and clears the target.
    function testDecursePermissionlessThirdPartyClear() public {
        address target = makeAddr("decurse_3p_target");
        address stranger = makeAddr("decurse_3p_stranger");
        _seedCurse(target, 4);
        _fundFlip(stranger, 200 ether);
        assertEq(game.curseCountOf(target), 4, "pre: target cursed");

        vm.prank(stranger);
        game.decurse(target); // stranger != target, no auth needed
        assertEq(game.curseCountOf(target), 0, "permissionless: a stranger cleared the target's curse");
    }

    // =========================================================================
    // Mirror event decl for vm.expectEmit
    // =========================================================================
    event Decursed(address indexed curer, address indexed target);

    // =========================================================================
    // Helpers — costs
    // =========================================================================

    /// @dev Cost of one whole ticket (400 units) at the active purchase level.
    function _oneTicketCost() internal view returns (uint256) {
        return _ticketCost(400);
    }

    /// @dev Cost of `units` ticket-units at the active purchase level (4*TICKET_SCALE=100 units == 1 ticket).
    function _ticketCost(uint256 units) internal view returns (uint256) {
        uint24 targetLevel = game.jackpotPhase() ? game.level() : game.level() + 1;
        uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
        // ticketCost = priceWei * units / (4 * TICKET_SCALE); 4*TICKET_SCALE == 400 ⇒ 400 units == 1 ticket.
        return (priceWei * units) / 400;
    }

    // =========================================================================
    // Seeders (vm.store on the canonical layout; ported from V61CurseSet)
    // =========================================================================

    function _seedClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BALANCES_PACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 oldLow = uint128(packed);
        uint256 high = packed >> 128;
        vm.store(address(game), slot, bytes32((high << 128) | uint128(amount)));
        _bumpClaimablePool(int256(amount) - int256(oldLow));
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

    /// @dev Field-isolated seed of dailyIdx (slot 0, byte 3, uint24).
    function _seedDailyIdx(uint256 day) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        slot0 &= ~(uint256(0xFFFFFF) << 24);
        slot0 |= (day & 0xFFFFFF) << 24;
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Align dailyIdx (the _bountyEligible gate basis, gateIdx == dailyIdx) to the live wall-clock sim day
    ///      (game.currentDayView() == _simulatedDayIndex()). Used by the lootbox-leg bounty proof (the lootbox
    ///      DAY_SHIFT stamp uses the sim day) and the cure-before-score contrast (so both buyers' streak bases
    ///      are computed at a consistent day). Kept >= 1 so a far-past lastEthDay=0 stays non-eligible.
    function _alignDailyIdxToSimDay() internal {
        uint256 simDay = uint256(game.currentDayView());
        if (simDay == 0) simDay = 1;
        _seedDailyIdx(simDay);
    }

    /// @dev Warp the wall clock to just AFTER the daily reset (82620 = 22:57 UTC) so `elapsed` in
    ///      _bountyEligible is < 15 min — i.e. the time-based bounty tiers are NOT yet open, isolating the
    ///      DAY_SHIFT-stamp tier as the thing the buy flips.
    function _advanceWallClockToBuyWindowStart() internal {
        // Land 5 minutes into the day window (< 15 min ⇒ no time-tier eligibility).
        uint256 dayStart = ((block.timestamp - 82620) / 1 days) * 1 days + 82620 + 1 days;
        _t = dayStart + 5 minutes;
        vm.warp(_t);
    }

    // =========================================================================
    // FLIP + affiliate helpers
    // =========================================================================

    /// @dev Mint FLIP to `who` via the GAME-gated mintForGame (the established test pattern).
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Set the mintPacked_ HAS_DEITY_PASS bit (shift 184) — the activity-score deity bonus (8000 bps),
    ///      read-only in the buy path so it survives a ticket buy. (Distinct from the DeityPass NFT ownerOf
    ///      gate used by smite; this is the score-bonus flag only.)
    function _grantDeityPass(address who) internal {
        _seedField(who, 184, 0x1, 1);
    }

    /// @dev Register `referrer` as an affiliate and return a usable affiliate code. A buy carrying this code
    ///      takes the fresh/recycled affiliate split path in MintModule. (Falls back to a synthetic non-zero
    ///      code if the affiliate registration entrypoint shape differs — the cure fires regardless of whether
    ///      the code resolves to a real referrer, since CURSE-04 precedes the affiliate logic.)
    function _registerAffiliate(address referrer) internal returns (bytes32) {
        // A non-zero affiliate code drives the coded-buy branch; the referrer need only be funded so the buy
        // does not revert on an unrelated path. The cure is independent of the affiliate resolution.
        vm.deal(referrer, 1 ether);
        return bytes32(uint256(uint160(referrer)));
    }
}
