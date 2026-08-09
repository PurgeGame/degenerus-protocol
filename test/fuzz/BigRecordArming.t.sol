// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BigRecordArmingTest — pins the game-side arming of the all-time records.
///
/// @notice Coinflip owns the four records and the shared pool (ruleset pinned in
///         BigRecordPool.t.sol). This suite pins what the GAME side feeds it:
///         - Degenerette bet: ETH bets only, candidate = the bet's TOTAL ETH (the
///           whole transaction's wager, spins included), gated on the 1 ETH floor.
///         - Lootbox deposit: purchase-path deposits only, candidate = THIS deposit's
///           raw purchased ETH (no boon boost), never the box total — whale-pass and
///           afking covers write the same (index, player) box slot and must stay
///           invisible.
///         - Ticket buy: whole tickets counted raw off the pre-boost quantity, gated
///           on the 100-ticket floor.
///         A claim pays flip credit inside Coinflip; the box itself is never inflated.
contract BigRecordArmingTest is DeployProtocol {
    uint256 private constant LOOTBOX_ETH_SLOT = 15;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant LB_AMOUNT_MASK = (uint256(1) << 128) - 1;

    uint256 private constant SPIN_MIN_ETH = 1 ether;
    uint256 private constant BOX_MIN_ETH = 5 ether;
    uint256 private constant BUY_MIN_TICKETS = 100;
    uint256 private constant SHARE_FLOOR_BPS = 500;

    /// @dev Level-1 ticket price; purchases below target level 1 in this fixture.
    uint256 private constant TICKET_PRICE = 0.01 ether;

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;

    address private player;
    address private rival;

    function setUp() public {
        _deployProtocol();
        _skipDays(1);

        player = makeAddr("arming_player");
        rival = makeAddr("arming_rival");
        vm.deal(player, 100_000 ether);
        vm.deal(rival, 100_000 ether);
        vm.deal(address(game), 100_000 ether);

        // placeDegeneretteBet reverts when lootboxRngIndex == 0; seed it to 1. The
        // word at index 1 stays 0 (unfulfilled), which is the state placement requires.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );

        _seedFuturePrizePool(50_000 ether);
    }

    // ---------------------------------------------------------------------
    // Degenerette spin
    // ---------------------------------------------------------------------

    /// @notice A bet totalling under the 1 ETH floor never arms; at the floor it
    ///         bootstraps.
    function testSpinFloorGatesTheArm() public {
        _placeEth(player, uint128(SPIN_MIN_ETH - 1), 1);
        assertEq(coinflip.biggestSpinEver(), 0, "sub-floor bet never arms");

        _placeEth(player, uint128(SPIN_MIN_ETH), 1);
        assertEq(
            coinflip.biggestSpinEver(),
            SPIN_MIN_ETH,
            "a bet at the floor bootstraps the record"
        );
    }

    /// @notice The record unit is the bet's TOTAL ETH — the whole transaction's wager,
    ///         spins included.
    function testSpinUnitIsBetTotal() public {
        _placeEth(player, 0.6 ether, 2); // 1.2 ETH total, 0.6 per spin
        assertEq(
            coinflip.biggestSpinEver(),
            1.2 ether,
            "the candidate is the transaction's total wager"
        );
    }

    /// @notice Non-ETH currencies never touch the record.
    function testFlipCurrencyBetNeverArms() public {
        vm.prank(address(game));
        coin.mintForGame(player, 10_000 ether);
        vm.prank(player);
        game.placeDegeneretteBet(
            address(0),
            CURRENCY_FLIP,
            1_000 ether,
            1,
            0x00010203,
            0
        );
        assertEq(coinflip.biggestSpinEver(), 0, "FLIP bets stay off the record");
    }

    /// @notice A gifted bet arms normally — the ETH is real and the record belongs to
    ///         the bet owner.
    function testGiftedBetArms() public {
        vm.prank(rival);
        game.placeDegeneretteBet{value: 2 ether}(
            player,
            CURRENCY_ETH,
            2 ether,
            1,
            0x00010203,
            0
        );
        assertEq(coinflip.biggestSpinEver(), 2 ether, "gifted bets arm the record");
    }

    /// @notice A 20%-beat spin claims flip credit for the bettor inside Coinflip.
    function testSpinClaimPaysFlipCredit() public {
        _placeEth(player, 10 ether, 1);
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;

        _placeEth(rival, 12 ether, 1); // exactly mark + mark/5
        assertEq(
            coinflip.coinflipAmount(rival),
            expected,
            "the claim lands as the bettor's next-day flip stake"
        );
    }

    // ---------------------------------------------------------------------
    // Lootbox deposit
    // ---------------------------------------------------------------------

    /// @notice A deposit under the 5 ETH floor never arms, however many accumulate.
    function testBoxFloorGatesTheArm() public {
        _buyBox(player, 3 ether);
        _buyBox(player, 3 ether);
        assertEq(coinflip.biggestLuckboxEver(), 0, "sub-floor deposits never arm");

        _buyBox(player, BOX_MIN_ETH);
        assertEq(
            coinflip.biggestLuckboxEver(),
            BOX_MIN_ETH,
            "a deposit at the floor bootstraps the record"
        );
    }

    /// @notice ETH already sitting in a box is invisible: whale-pass and afking covers
    ///         write the same (index, player) box slot without arming, so the candidate
    ///         must be the deposit, never the box total.
    function testPreExistingBoxEthIsInvisible() public {
        _buyBox(player, 10 ether); // standing record

        address sneak = makeAddr("sneak");
        vm.deal(sneak, 1_000 ether);
        _presetBox(sneak, 500 ether); // as if funded by whale pass / afking cover
        _buyBox(sneak, BOX_MIN_ETH); // over the floor, far under the record

        assertEq(
            coinflip.biggestLuckboxEver(),
            10 ether,
            "pre-existing box ETH cannot ratchet the record"
        );
    }

    /// @notice Each deposit is judged alone: splitting a big buy across deposits
    ///         cannot reach a bar a single deposit of the same total would clear.
    function testSplitBoxDepositsAreJudgedIndividually() public {
        _buyBox(player, 10 ether);

        _buyBox(rival, 6 ether);
        _buyBox(rival, 6 ether); // box total 12 ETH, neither deposit beats 10

        assertEq(
            coinflip.biggestLuckboxEver(),
            10 ether,
            "neither half beat the standing record"
        );
        assertEq(_boxOf(rival), 12 ether, "the box still accumulated both halves");
    }

    /// @notice A claim pays flip credit and leaves the box exactly at its deposits —
    ///         the box is never inflated. Asserted on the pool decrement: the box buy
    ///         also completes the seeded deploy-day MINT_ETH quest, whose reward lands
    ///         in the same flip-stake observable.
    function testBoxClaimPaysFlipCreditNotBoxInflation() public {
        _buyBox(player, 10 ether);
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;

        _buyBox(rival, 12 ether); // exactly 10 + 10/5

        assertEq(_boxOf(rival), 12 ether, "the box holds the deposit alone");
        assertEq(
            coinflip.recordPool(),
            pool - expected,
            "the claim drew exactly its share from the pool"
        );
    }

    // ---------------------------------------------------------------------
    // Ticket buy
    // ---------------------------------------------------------------------

    /// @notice A buy under 100 tickets never arms; at the floor the mark is the raw
    ///         whole-ticket count.
    function testBuyFloorGatesTheArmAndUnitIsRawTickets() public {
        _buyTickets(player, 99);
        assertEq(coinflip.biggestBuyEver(), 0, "99 tickets never arm");

        _buyTickets(player, 100);
        assertEq(
            coinflip.biggestBuyEver(),
            BUY_MIN_TICKETS,
            "the mark is whole tickets, raw off the pre-boost quantity"
        );
    }

    /// @notice A 20%-beat buy claims its pool share. Asserted on the pool decrement:
    ///         a ticket buy also credits quest/recycle flip stake of its own, so the
    ///         buyer's stake is not a clean observable for the claim.
    function testBuyClaimPaysFlipCredit() public {
        _buyTickets(player, 100);
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;

        _buyTickets(rival, 120); // exactly 100 + 100/5
        assertEq(coinflip.biggestBuyEver(), 120, "the claim ratchets the mark");
        assertEq(
            coinflip.recordPool(),
            pool - expected,
            "the claim drew exactly its share from the pool"
        );
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _skipDays(uint256 numDays) internal {
        vm.warp(vm.getBlockTimestamp() + numDays * 1 days);
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        uint256 newPacked = (currentPacked &
            ~(((uint256(1) << 104) - 1) << 104)) | (targetFuture << 104);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32(newPacked)
        );
    }

    function _placeEth(address who, uint128 perSpin, uint8 spins) internal {
        vm.prank(who);
        game.placeDegeneretteBet{value: uint256(perSpin) * spins}(
            address(0),
            CURRENCY_ETH,
            perSpin,
            spins,
            0x00010203,
            0
        );
    }

    function _buyBox(address who, uint256 amount) internal {
        if (who.balance < amount) vm.deal(who, amount + 1 ether);
        vm.prank(who);
        game.purchase{value: amount}(
            who,
            0,
            amount,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    /// @dev Buy `tickets` whole tickets with ETH (quantity unit = quarter-tickets x100).
    function _buyTickets(address who, uint256 tickets) internal {
        uint256 qty = tickets * 400;
        uint256 cost = tickets * TICKET_PRICE;
        vm.prank(who);
        game.purchase{value: cost}(
            who,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    function _lootboxIndex() internal view returns (uint48) {
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        return uint48(lrPacked & 0xFFFFFFFFFFFF);
    }

    function _boxSlot(address who) internal view returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(_lootboxIndex(), LOOTBOX_ETH_SLOT));
        return keccak256(abi.encode(who, inner));
    }

    function _boxOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), _boxSlot(who))) & LB_AMOUNT_MASK;
    }

    /// @dev Stand in for a whale-pass / afking-cover deposit: put ETH in the box
    ///      without going through the purchase path that arms the record.
    function _presetBox(address who, uint256 amount) internal {
        bytes32 slot = _boxSlot(who);
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & ~LB_AMOUNT_MASK) | (amount & LB_AMOUNT_MASK);
        vm.store(address(game), slot, bytes32(word));
    }
}
