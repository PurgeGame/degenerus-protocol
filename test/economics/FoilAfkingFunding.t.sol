// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title FoilAfkingFunding — the foil premium is funded by the same mix as every other purchase
/// @notice The foil leg used to stop the spend waterfall after claimable and revert, so a player
///         holding only prepaid afking could not buy a pack that the same bucket would have bought
///         tickets, lootboxes, whale passes and degenerette bets with. It now runs the canonical
///         `_settleShortfall` waterfall — fresh ETH, then claimable to the 1-wei sentinel (skipped
///         on DirectEth), then prepaid afking — identical to the ticket leg's `_processMintPayment`.
///         This file pins each tier, the reclassification that rides with it (afking is own
///         principal, so it pays the FRESH affiliate rate and stays OUT of the recycle-bonus
///         basis), the presale box credit the leg now accrues, and the solvency identity across
///         an afking-funded buy.
/// @dev Every buy here happens in the opening purchase phase, so `_activeTicketLevel()` is
///      `level + 1` and the pack costs exactly `FOIL_PACK_TICKETS * priceForLevel(level + 1)`
///      (snapShift is 0 — the exponent case is pinned by FoilSnapPayout).
contract FoilAfkingFunding is DeployProtocol {
    /// @dev FOIL_PACK_TICKETS — the pack is priced at ten ticket prices.
    uint256 private constant FOIL_PACK_TICKETS = 10;

    /// @dev `balancesPacked` is a mapping at slot 7 (low 128 = claimable winnings, high 128 =
    ///      prepaid afking) and `claimablePool` is the HIGH half of slot 1. Read from
    ///      scripts/layout/golden/DegenerusGame.json; the storage layout oracle fails the build
    ///      if either moves. The afking half is seeded through the production
    ///      `depositAfkingFunding` entrypoint — only claimable, which has no permissionless
    ///      credit path, is poked, and the poke is read-modify-write so it cannot clobber it.
    uint256 private constant BALANCES_PACKED_SLOT = 7;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    function _foilCost() internal view returns (uint256) {
        return FOIL_PACK_TICKETS * PriceLookupLib.priceForLevel(game.level() + 1);
    }

    /// @dev Set `who`'s claimable winnings to `amt`, keeping the afking half, the `claimablePool`
    ///      total and the contract's ETH backing in step so the solvency identity still holds.
    function _seedClaimable(address who, uint256 amt) internal {
        bytes32 slot = keccak256(abi.encode(who, BALANCES_PACKED_SLOT));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 prev = uint128(packed);
        vm.store(
            address(game),
            slot,
            bytes32(((packed >> 128) << 128) | amt)
        );

        uint256 s1 = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = uint128(s1);
        uint256 pool = s1 >> 128;
        if (amt >= prev) {
            pool += (amt - prev);
            vm.deal(address(game), address(game).balance + (amt - prev));
        } else {
            pool -= (prev - amt);
        }
        vm.store(
            address(game),
            bytes32(CLAIMABLE_POOL_SLOT),
            bytes32((pool << 128) | lower)
        );
    }

    function _fundAfking(address who, uint256 amt) internal {
        vm.deal(who, who.balance + amt);
        vm.prank(who);
        game.depositAfkingFunding{value: amt}(who);
    }

    function _buyFoil(address who, uint256 ethSent, MintPaymentKind kind) internal {
        vm.prank(who);
        game.purchase{value: ethSent}(who, 0, 0, bytes32(0), kind, true);
    }

    function _newPlayer(string memory label) internal returns (address who) {
        who = makeAddr(label);
        vm.deal(who, 1_000 ether);
    }

    /// @dev The pack record has no public getter, so its presence is proven the way the game
    ///      itself reads it: the one-per-cycle cap IS the non-zero record slot, so a second buy
    ///      at the same level must revert FoilAlreadyBought.
    function _assertPackRecorded(address who) internal {
        // Resolve the cost BEFORE arming expectRevert — the price read is an external staticcall
        // and would otherwise be the call the cheatcode inspects.
        uint256 cost = _foilCost();
        vm.deal(who, who.balance + 1_000 ether);
        vm.prank(who);
        vm.expectRevert(bytes4(keccak256("FoilAlreadyBought()")));
        game.purchase{value: cost}(who, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Tier 3: afking covers the shortfall
    // ──────────────────────────────────────────────────────────────────────

    /// @dev DirectEth skips claimable but NOT afking — the exact asymmetry the ticket leg has
    ///      always had. Half the cost arrives as fresh ETH; the prepaid bucket covers the rest.
    function test_directEthShortfallDrawsAfking() public {
        address p = _newPlayer("foilAfkDirect");
        uint256 cost = _foilCost();
        uint256 fresh = cost / 2;
        uint256 shortfall = cost - fresh;

        _seedClaimable(p, 5 ether); // must be left untouched by DirectEth
        _fundAfking(p, shortfall + 1 ether);

        uint256 afkBefore = game.afkingFundingOf(p);
        uint256 claimBefore = game.claimableWinningsOf(p);

        _buyFoil(p, fresh, MintPaymentKind.DirectEth);

        assertEq(
            game.afkingFundingOf(p),
            afkBefore - shortfall,
            "afking covers exactly the DirectEth shortfall"
        );
        assertEq(
            game.claimableWinningsOf(p),
            claimBefore,
            "DirectEth must not touch claimable"
        );
        _assertPackRecorded(p);
    }

    /// @dev A zero-fresh-ETH afking-only buy: the whole premium comes out of the prepaid bucket,
    ///      which is what "funded like every other purchase" means in the limit.
    function test_afkingOnlyBuySucceeds() public {
        address p = _newPlayer("foilAfkOnly");
        uint256 cost = _foilCost();
        _fundAfking(p, cost);

        _buyFoil(p, 0, MintPaymentKind.DirectEth);

        assertEq(game.afkingFundingOf(p), 0, "afking fully drawn");
        _assertPackRecorded(p);
    }

    /// @dev Combined runs both lower tiers in order: claimable first, down to the 1-wei sentinel,
    ///      then afking for the remainder. The sentinel is what proves the ordering — a waterfall
    ///      that reached for afking first would leave claimable whole.
    function test_combinedWaterfallClaimableThenAfking() public {
        address p = _newPlayer("foilAfkCombined");
        uint256 cost = _foilCost();
        uint256 claimable = cost / 4;

        _seedClaimable(p, claimable);
        _fundAfking(p, cost);

        uint256 afkBefore = game.afkingFundingOf(p);
        // claimable pays `claimable - 1` (the sentinel survives); afking pays the rest.
        uint256 expectedAfkDraw = cost - (claimable - 1);

        _buyFoil(p, 0, MintPaymentKind.Combined);

        assertEq(game.claimableWinningsOf(p), 1, "claimable drawn to the 1-wei sentinel");
        assertEq(
            game.afkingFundingOf(p),
            afkBefore - expectedAfkDraw,
            "afking covers what claimable could not"
        );
    }

    /// @dev Both lower tiers exhausted: the buy fails closed on every pay kind rather than
    ///      under-charging or half-delivering a pack.
    function test_insolventWhenBothTiersShort() public {
        uint256 cost = _foilCost();
        bytes4 insolvent = bytes4(keccak256("Insolvent()"));

        address a = _newPlayer("foilShortDirect");
        _fundAfking(a, cost - 1);
        vm.prank(a);
        vm.expectRevert(insolvent);
        game.purchase{value: 0}(a, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);

        address b = _newPlayer("foilShortCombined");
        _seedClaimable(b, cost / 4);
        _fundAfking(b, cost / 4);
        vm.prank(b);
        vm.expectRevert(insolvent);
        game.purchase{value: 0}(b, 0, 0, bytes32(0), MintPaymentKind.Combined, true);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Basis reclassification: afking is own principal, not recycled winnings
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The recycle bonus pays 10% back in FLIP on claimable spent at or above three whole
    ///      tickets. The pack costs ten, so a fully claimable-funded buy always clears the bar and
    ///      a fully afking-funded one must not — afking is the player's own deposited principal,
    ///      the same classification the ticket leg gives it (fresh-rate affiliate, no recycle
    ///      bonus). Equality against the all-fresh-ETH buy is the assertion that would break if
    ///      afking ever leaked into the recycled basis.
    function test_afkingPaysFreshRateAndSkipsRecycleBonus() public {
        uint256 cost = _foilCost();

        address freshBuyer = _newPlayer("foilBasisFresh");
        _buyFoil(freshBuyer, cost, MintPaymentKind.DirectEth);
        uint256 freshFlip = coinflip.coinflipAmount(freshBuyer);

        address afkBuyer = _newPlayer("foilBasisAfk");
        _fundAfking(afkBuyer, cost);
        _buyFoil(afkBuyer, 0, MintPaymentKind.DirectEth);
        uint256 afkFlip = coinflip.coinflipAmount(afkBuyer);

        address claimBuyer = _newPlayer("foilBasisClaim");
        _seedClaimable(claimBuyer, cost + 1);
        _buyFoil(claimBuyer, 0, MintPaymentKind.Claimable);
        uint256 claimFlip = coinflip.coinflipAmount(claimBuyer);

        assertEq(afkFlip, freshFlip, "afking-funded foil credits exactly what fresh ETH does");
        assertGt(claimFlip, afkFlip, "only the claimable-funded buy earns the recycle bonus");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Presale box credit
    // ──────────────────────────────────────────────────────────────────────

    /// @dev While the box presale is open, every ETH spend accrues 25% spendable box credit —
    ///      the ticket/lootbox leg and all three pass buys do it on their gross price. The foil
    ///      premium now does too, on `cost`, independent of which tier funded it.
    function test_foilAccruesPresaleBoxCredit() public {
        uint256 cost = _foilCost();

        address freshBuyer = _newPlayer("foilCreditFresh");
        _buyFoil(freshBuyer, cost, MintPaymentKind.DirectEth);
        assertEq(
            game.presaleBoxCreditOf(freshBuyer),
            cost / 4,
            "fresh-funded foil accrues 25% of the gross premium"
        );

        address afkBuyer = _newPlayer("foilCreditAfk");
        _fundAfking(afkBuyer, cost);
        _buyFoil(afkBuyer, 0, MintPaymentKind.DirectEth);
        assertEq(
            game.presaleBoxCreditOf(afkBuyer),
            cost / 4,
            "afking-funded foil accrues the same credit"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // Solvency
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The spine invariant: `claimablePool` is the sum of every player's claimable winnings
    ///      and prepaid afking. The foil leg no longer debits the pool itself — `_settleShortfall`
    ///      pairs the two tiers' draws into one decrement — so a drift here would mean the pool
    ///      and the per-player balances came apart on the new path.
    function test_solvencyIdentityHoldsAcrossAfkingFoil() public {
        address p = _newPlayer("foilSolvency");
        uint256 cost = _foilCost();

        _seedClaimable(p, cost / 4);
        _fundAfking(p, cost);

        uint256 poolBefore = game.claimablePoolView();
        uint256 ownedBefore = game.claimableWinningsOf(p) + game.afkingFundingOf(p);

        _buyFoil(p, 0, MintPaymentKind.Combined);

        uint256 poolAfter = game.claimablePoolView();
        uint256 ownedAfter = game.claimableWinningsOf(p) + game.afkingFundingOf(p);

        assertEq(
            poolBefore - poolAfter,
            ownedBefore - ownedAfter,
            "pool decrement equals the buyer's combined claimable + afking draw"
        );
        assertGe(
            address(game).balance,
            poolAfter,
            "claimable pool stays backed by contract ETH"
        );
    }
}
