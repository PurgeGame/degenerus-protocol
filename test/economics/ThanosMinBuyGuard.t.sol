// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title ThanosMinBuyGuard — a ticket buy that the snap divide would truncate to zero reverts
/// @notice Under a thanos declaration a plain ticket's PRICE is unchanged and the accumulated
///         (player, level) entry balance is divided by 2^s once at drain time. The divide runs on
///         `owed * 100 + rem` scaled units, so a buy smaller than 2^s scaled units truncates to
///         exactly zero on its own, and the probabilistic remainder settle cannot recover it —
///         `rem == 0` always loses the roll. Such a buy would pay full price for nothing.
///         `_callTicketPurchase` rejects it instead.
/// @dev The guard sits in `_callTicketPurchase`, the single choke point every ticket-purchase path
///      funnels through — the ETH/claimable/combined body (`_purchaseForWithCached`, itself reached
///      from `purchase`, the foil orchestrator's `purchaseWith`, `buyLootboxAndPresaleBox`, and the
///      far-future salvage ticket leg) AND `_redeemFlipFor`, which does NOT go through that body.
///      Both callers are player-initiated, so a revert there cannot reach the advance chain; the
///      award legs queue straight into `_queueEntries`/`_queueEntriesScaled`, which stay unguarded.
///      Its exponent is read from `targetLevel` — the routed level the entries actually queue at —
///      so the guard and the drain can never disagree about which level's declaration applies.
///
///      The 40M-entry floor that moves `snapShift` for real is not constructible in a scenario, so
///      the exponent is poked with a read-modify-write `vm.store`. The pair of assertions either
///      side of the truncating shift is what keeps that poke honest: if it silently stopped
///      landing, the reverting case would pass a buy and fail the test.
contract ThanosMinBuyGuard is DeployProtocol {
    /// @dev snapShift is a uint8 at slot 14, byte 7 — packed with ticketCursor (bytes 0-3) and
    ///      ticketLevel (bytes 4-6). Read from scripts/layout/golden/DegenerusGame.json; the layout
    ///      oracle fails the build if the field moves.
    uint256 private constant SNAP_SLOT = 14;
    uint256 private constant SNAP_BYTE = 7;

    /// @dev ticketRedemptionOpen: slot 0, byte 30. Pre-latching it opens the FLIP purchase window
    ///      without driving a whole cycle (see FlipRedeemWindow.t.sol for the gate's own coverage).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant WINDOW_OPEN_SHIFT = 240;

    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;
    uint256 private constant QTY_SCALE = 100;
    uint256 private constant LOOTBOX_MIN = 0.01 ether;

    uint24 private _routedLvl;
    uint256 private _priceWei;
    /// @dev Smallest purchase that clears TICKET_MIN_BUYIN_WEI — the worst case for the guard.
    uint256 private _minQty;
    /// @dev Smallest exponent that truncates `_minQty` to zero (its bit length).
    uint8 private _killShift;

    address private _buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _buyer = makeAddr("thanos_min_buyer");
        vm.deal(_buyer, 100 ether);

        // Fresh deploy sits in the purchase phase, so buys route to level + 1.
        _routedLvl = game.level() + 1;
        _priceWei = PriceLookupLib.priceForLevel(_routedLvl);
        _minQty =
            (TICKET_MIN_BUYIN_WEI * 4 * QTY_SCALE + _priceWei - 1) /
            _priceWei;
        while ((_minQty >> _killShift) != 0) {
            _killShift++;
        }

        // Pin the fixture. These are derived above, not assumed, but a price-table or floor change
        // that moved them would silently change what the tests below exercise.
        assertEq(_priceWei, 0.01 ether, "routed-level price drifted");
        assertEq(_minQty, 100, "min buy-in quantity drifted (0.25 ticket = 1 entry)");
        assertEq(_killShift, 7, "truncating shift for the min buy drifted");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev Read-modify-write so ticketCursor / ticketLevel in the same slot survive.
    function _forceSnapShift(uint8 s) internal {
        bytes32 slot = bytes32(SNAP_SLOT);
        uint256 v = uint256(vm.load(address(game), slot));
        v &= ~(uint256(0xff) << (SNAP_BYTE * 8));
        v |= uint256(s) << (SNAP_BYTE * 8);
        vm.store(address(game), slot, bytes32(v));
    }

    function _openFlipWindow() internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT_0)));
        s0 |= uint256(1) << WINDOW_OPEN_SHIFT;
        vm.store(address(game), bytes32(SLOT_0), bytes32(s0));
    }

    function _buyEth(uint256 qty, uint256 lootBoxAmount) internal returns (bool ok) {
        uint256 cost = (_priceWei * qty) / (4 * QTY_SCALE) + lootBoxAmount;
        vm.prank(_buyer);
        (ok, ) = address(game).call{value: cost}(
            abi.encodeWithSignature(
                "purchase(address,uint256,uint256,bytes32,uint8,bool)",
                _buyer,
                qty,
                lootBoxAmount,
                bytes32(0),
                uint8(MintPaymentKind.DirectEth),
                false
            )
        );
    }

    function _redeemFlip(uint256 qty) internal returns (bool ok) {
        vm.prank(_buyer);
        (ok, ) = address(game).call(
            abi.encodeWithSignature("redeemFlip(address,uint256)", _buyer, qty)
        );
    }

    function _owed() internal view returns (uint32) {
        return game.entriesOwedView(_routedLvl, _buyer);
    }

    // ------------------------------------------------------------------
    // ETH path — the guard's red/green pair
    // ------------------------------------------------------------------

    /// @notice At the truncating exponent the smallest clearing buy reverts rather than charging.
    function testMinBuyRevertsAtTruncatingShift() public {
        _forceSnapShift(_killShift);
        uint256 balBefore = _buyer.balance;
        assertFalse(
            _buyEth(_minQty, 0),
            "a buy the snap divide would zero must revert"
        );
        assertEq(_owed(), 0, "no entries may be queued by a rejected buy");
        assertEq(_buyer.balance, balBefore, "a rejected buy must not be charged");
    }

    /// @notice One exponent below, the same buy survives the divide and is accepted.
    function testMinBuySurvivesJustBelowTruncatingShift() public {
        _forceSnapShift(_killShift - 1);
        assertTrue(
            _buyEth(_minQty, 0),
            "a buy that survives the divide must be accepted"
        );
        assertEq(_owed(), 1, "the accepted buy must queue its entry");
    }

    /// @notice With no declaration in force the guard is a no-op on the same buy.
    function testMinBuyAcceptedAtShiftZero() public {
        assertTrue(_buyEth(_minQty, 0), "shift 0 must not gate the min buy");
        assertEq(_owed(), 1, "the accepted buy must queue its entry");
    }

    /// @notice The guard bounds only sub-floor buys: at the maximum exponent a buy of >= 2^8 scaled
    ///         units still goes through, so the valve is not turned into a ticket-sale halt.
    function testAboveFloorBuyAcceptedAtMaxShift() public {
        _forceSnapShift(8);
        uint256 qty = 4 * QTY_SCALE; // one whole ticket = 400 scaled units
        assertTrue(_buyEth(qty, 0), "a buy above the 2^8 floor must be accepted");
        assertEq(_owed(), 4, "the accepted buy must queue its four entries");
    }

    /// @notice A lootbox-only purchase carries no ticket leg, so it never reaches the guard even at
    ///         the maximum exponent.
    function testLootboxOnlyBuyUnaffectedAtMaxShift() public {
        _forceSnapShift(8);
        assertTrue(
            _buyEth(0, LOOTBOX_MIN),
            "a lootbox-only buy must not be gated by the ticket-leg guard"
        );
    }

    // ------------------------------------------------------------------
    // FLIP redemption — the path that bypasses _purchaseForWithCached
    // ------------------------------------------------------------------

    /// @notice redeemFlip reaches _callTicketPurchase directly, never through the ETH purchase
    ///         body, so it needs the same coverage: the guard must hold there too.
    function testRedeemFlipRevertsAtTruncatingShift() public {
        _openFlipWindow();
        vm.prank(address(game));
        coin.mintForGame(_buyer, 1_000_000 ether);

        _forceSnapShift(_killShift);
        assertFalse(
            _redeemFlip(_minQty),
            "a FLIP redemption the snap divide would zero must revert"
        );
        assertEq(_owed(), 0, "no entries may be queued by a rejected redemption");

        _forceSnapShift(_killShift - 1);
        assertTrue(
            _redeemFlip(_minQty),
            "a FLIP redemption that survives the divide must be accepted"
        );
        assertEq(_owed(), 1, "the accepted redemption must queue its entry");
    }
}
