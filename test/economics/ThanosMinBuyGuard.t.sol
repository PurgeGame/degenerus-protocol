// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title ThanosMinBuyGuard — a dust ticket buy the snap divide would zero reverts
/// @notice Under a thanos declaration a plain ticket's PRICE is unchanged and the accumulated
///         (player, level) entry balance is divided by 2^s once at drain. The divide runs on
///         `owed * 100 + rem` scaled units, so a buy smaller than 2^s scaled units truncates to
///         exactly zero on its own, and the probabilistic remainder settle cannot recover it —
///         `rem == 0` always loses the roll. Such a buy would pay full price for nothing.
///         `_callTicketPurchase` rejects it.
/// @dev The guard is deliberately scoped to buys under SNAP_CHECK_MAX_UNITS (16 units = 0.04
///      tickets): reading the exponent costs a cold SLOAD on a slot no purchase otherwise touches
///      (slot 14, shared with ticketCursor / ticketLevel), so only a dust-sized buy pays for it.
///      A buy at or above 16 units still truncates once s exceeds 4 — that gap is ACCEPTED, and
///      `testAboveGateNotCheckedAtMaxShift` pins it so it reads as a choice, not an oversight.
///
///      The fixture pokes `level` to 29 so buys route to level 30, where the price is 0.08 ETH and
///      TICKET_MIN_BUYIN_WEI floors a legal buy at 13 units — inside the gate. At the 0.01 ETH
///      intro price the floor is 100 units, above the gate, so the guard is unreachable there and
///      a test written at a fresh deploy's level would be vacuous. Level 30 is deliberately not a
///      century milestone, keeping the x00 bonus path out of the picture.
///
///      snapShift is poked with a read-modify-write `vm.store` — the 40M-entry declaration floor
///      is not constructible in a scenario. The pair of assertions either side of the truncating
///      shift is what keeps the poke honest: if it silently stopped landing, the reverting case
///      would pass a buy and fail the test.
contract ThanosMinBuyGuard is DeployProtocol {
    /// @dev snapShift: slot 14, byte 7 — packed with ticketCursor (bytes 0-3) and ticketLevel
    ///      (bytes 4-6). `level`: slot 0, bytes 12-14 (uint24). Both read from
    ///      scripts/layout/golden/DegenerusGame.json; the layout oracle fails the build on a move.
    uint256 private constant SNAP_SLOT = 14;
    uint256 private constant SNAP_BYTE = 7;
    uint256 private constant LEVEL_SLOT = 0;
    uint256 private constant LEVEL_BYTE = 12;

    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;
    uint256 private constant QTY_SCALE = 100;
    uint256 private constant LOOTBOX_MIN = 0.01 ether;
    /// @dev Mirrors MintModule.SNAP_CHECK_MAX_UNITS (0.04 tickets).
    uint256 private constant SNAP_CHECK_MAX_UNITS = 16;

    /// @dev Routed level 30 => 0.08 ETH, the cheapest price whose min legal buy is under the gate.
    uint24 private constant BASE_LEVEL = 29;

    uint24 private _routedLvl;
    uint256 private _priceWei;
    /// @dev Smallest buy that clears TICKET_MIN_BUYIN_WEI — the worst case for the guard.
    uint256 private _minQty;
    /// @dev Smallest exponent that truncates `_minQty` to zero (its bit length).
    uint8 private _killShift;

    address private _buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _buyer = makeAddr("thanos_min_buyer");
        vm.deal(_buyer, 100 ether);

        _forceLevel(BASE_LEVEL);
        // Purchase phase (jackpotPhaseFlag clear on a fresh deploy) routes buys to level + 1.
        _routedLvl = BASE_LEVEL + 1;
        _priceWei = PriceLookupLib.priceForLevel(_routedLvl);
        _minQty =
            (TICKET_MIN_BUYIN_WEI * 4 * QTY_SCALE + _priceWei - 1) /
            _priceWei;
        while ((_minQty >> _killShift) != 0) {
            _killShift++;
        }

        // Pin the fixture. These are derived above, not assumed, but a price-table or floor change
        // that moved them would silently change what the tests below exercise — including moving
        // _minQty out of the gate, which would make every assertion vacuous.
        assertEq(game.level(), BASE_LEVEL, "level poke did not land");
        assertEq(_priceWei, 0.08 ether, "routed-level price drifted");
        assertEq(_minQty, 13, "min buy-in quantity drifted");
        assertLt(_minQty, SNAP_CHECK_MAX_UNITS, "min buy must sit INSIDE the guard's gate");
        assertEq(_killShift, 4, "truncating shift for the min buy drifted");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev Read-modify-write so slot-mates survive.
    function _pokeByte3(uint256 slot, uint256 byteOff, uint24 v) internal {
        uint256 cur = uint256(vm.load(address(game), bytes32(slot)));
        cur &= ~(uint256(0xffffff) << (byteOff * 8));
        cur |= uint256(v) << (byteOff * 8);
        vm.store(address(game), bytes32(slot), bytes32(cur));
    }

    function _forceLevel(uint24 lvl) internal {
        _pokeByte3(LEVEL_SLOT, LEVEL_BYTE, lvl);
    }

    function _forceSnapShift(uint8 s) internal {
        uint256 cur = uint256(vm.load(address(game), bytes32(SNAP_SLOT)));
        cur &= ~(uint256(0xff) << (SNAP_BYTE * 8));
        cur |= uint256(s) << (SNAP_BYTE * 8);
        vm.store(address(game), bytes32(SNAP_SLOT), bytes32(cur));
    }

    function _buyEth(uint256 qty, uint256 lootBoxAmount) internal returns (bool ok) {
        uint256 cost = (_priceWei * qty) / (4 * QTY_SCALE) + lootBoxAmount;
        // The third parameter is a packed box order, not a wei amount: the same spend buys
        // ONE custom box of that size (BoxOrderLib's documented migration rule).
        uint256 boxOrder = lootBoxAmount == 0 ? 0 : BoxOrderLib.boCustom(lootBoxAmount);
        vm.prank(_buyer);
        (ok, ) = address(game).call{value: cost}(
            abi.encodeWithSignature(
                "purchase(address,uint256,uint256,bytes32,uint8,bool)",
                _buyer,
                qty,
                boxOrder,
                bytes32(0),
                uint8(MintPaymentKind.DirectEth),
                false
            )
        );
    }

    function _owed() internal view returns (uint32) {
        return game.entriesOwedView(_routedLvl, _buyer);
    }

    // ------------------------------------------------------------------
    // The guard's red/green pair
    // ------------------------------------------------------------------

    /// @notice At the truncating exponent the smallest legal buy reverts rather than charging.
    function testMinBuyRevertsAtTruncatingShift() public {
        _forceSnapShift(_killShift);
        uint256 balBefore = _buyer.balance;
        assertFalse(
            _buyEth(_minQty, 0),
            "a dust buy the snap divide would zero must revert"
        );
        assertEq(_owed(), 0, "no entries may be queued by a rejected buy");
        assertEq(_buyer.balance, balBefore, "a rejected buy must not be charged");
    }

    /// @notice One exponent below, the same buy survives the divide and is accepted.
    /// @dev The accepted leg is asserted by the CHARGE, not by entriesOwedView: 13 scaled units is
    ///      0.13 of an entry, so it accumulates in the packed remainder byte and the whole-entry
    ///      view still reads 0. The charge is what distinguishes this from the reverting twin.
    function testMinBuySurvivesJustBelowTruncatingShift() public {
        _forceSnapShift(_killShift - 1);
        uint256 balBefore = _buyer.balance;
        assertTrue(
            _buyEth(_minQty, 0),
            "a dust buy that survives the divide must be accepted"
        );
        assertLt(_buyer.balance, balBefore, "the accepted buy must be charged");
    }

    /// @notice With no declaration in force the guard is a no-op on the same buy.
    function testMinBuyAcceptedAtShiftZero() public {
        uint256 balBefore = _buyer.balance;
        assertTrue(_buyEth(_minQty, 0), "shift 0 must not gate the min buy");
        assertLt(_buyer.balance, balBefore, "the accepted buy must be charged");
    }

    // ------------------------------------------------------------------
    // The gate's deliberate limits
    // ------------------------------------------------------------------

    /// @notice ACCEPTED GAP, pinned so it reads as a choice: a buy at or above the gate is never
    ///         tested against the exponent, so at a deep declaration it still queues entries the
    ///         drain will divide away. Paying a cold SLOAD on every purchase to catch this was
    ///         judged not worth it; revisit if a deep shift is ever actually declared.
    function testAboveGateNotCheckedAtMaxShift() public {
        _forceSnapShift(8);
        assertTrue(
            _buyEth(SNAP_CHECK_MAX_UNITS, 0),
            "a buy at the gate boundary is not exponent-checked and must go through"
        );
    }

    /// @notice A whole-ticket buy is unaffected at the maximum exponent — the guard bounds only
    ///         dust, so the valve is not turned into a ticket-sale halt.
    function testWholeTicketAcceptedAtMaxShift() public {
        _forceSnapShift(8);
        assertTrue(
            _buyEth(4 * QTY_SCALE, 0),
            "a one-ticket buy must be accepted at any exponent"
        );
        assertEq(_owed(), 4, "the accepted buy must queue its four entries");
    }

    /// @notice A lootbox-only purchase carries no ticket leg, so it never reaches the guard.
    function testLootboxOnlyBuyUnaffectedAtMaxShift() public {
        _forceSnapShift(8);
        assertTrue(
            _buyEth(0, LOOTBOX_MIN),
            "a lootbox-only buy must not be gated by the ticket-leg guard"
        );
    }
}
