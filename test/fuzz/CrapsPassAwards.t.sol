// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

/// @title Whale/deity purchases bank Craps pass credits
/// @notice Below level 10 a whale pass banks one normal Craps day-pass credit per pass bought
///         (lootbox untouched at 10%), and a deity pass banks one HIGH-ROLLER credit with the
///         lootbox halved to 5%. From level 10 the whale award stops entirely and the deity
///         award becomes one normal credit with the full 10% lootbox. The gate is level < 10,
///         held here at both sides of the boundary.
contract CrapsPassAwards is DeployProtocol {
    event CrapsPassesCredited(uint32 indexed playerId, bool highRoller, uint256 count);
    event LootBoxBuy(uint32 indexed buyer, uint48 indexed index, uint32 position, uint256 amount);

    uint256 private constant WHALE_EARLY_PRICE = 2.4 ether;
    uint256 private constant WHALE_STANDARD_PRICE = 4 ether;
    uint256 private constant DEITY_FIRST_PRICE = 24 ether;

    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("pass_award_buyer");
        vm.deal(buyer, 5_000 ether);
        _giveWalletId(buyer);
    }

    /// @dev game.level = lvl: uint24 at slot 0, byte offset 12 (bit 96). Reaching `lvl` means every
    ///      level through it has materialized its queues. Queue slots recycle 1..100 under a level tag
    ///      (c729ecfc9), so an unretired genesis queue would refuse the pass's own far-future binding
    ///      (lvl + 100 shares lvl's slot) with E().
    function _setLevel(uint24 lvl) private {
        TicketQueueStorage.retireCompleted(address(game), lvl);
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFFFFFF) << 96;
        vm.store(
            address(game),
            bytes32(uint256(0)),
            bytes32((slot0 & ~mask) | (uint256(lvl) << 96))
        );
    }

    function _buyWhale(address who, uint256 qty, uint256 unitPrice) private {
        vm.prank(who);
        game.purchaseWhalePass{value: unitPrice * qty}(0, qty, bytes32(0));
    }

    function _buyDeity(address who, uint8 symbolId) private {
        vm.prank(who);
        game.purchaseDeityPass{value: DEITY_FIRST_PRICE}(0, symbolId, bytes32(0));
    }

    // ── Whale: one normal credit per pass below level 10, nothing from 10 ────

    function testWhaleAwardPerPassBelowLevel10() public {
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(game.walletIdOf(buyer), false, 3);
        _buyWhale(buyer, 3, WHALE_EARLY_PRICE);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 3, "quantity-3 buy banks 3 normal passes");
        assertEq(high, 0, "whale award never touches the high lane");
    }

    function testWhaleAwardAtBoundaryLevel9() public {
        _setLevel(9);
        _buyWhale(buyer, 1, WHALE_STANDARD_PRICE);

        (uint256 normal,) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 1, "level 9 is below the gate and earns");
    }

    function testWhaleNoAwardFromLevel10() public {
        _setLevel(10);
        _buyWhale(buyer, 2, WHALE_STANDARD_PRICE);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 0, "level 10 purchase banks nothing");
        assertEq(high, 0, "level 10 purchase banks nothing");
    }

    // ── Deity: high credit + 5% lootbox below 10; normal credit + 10% from 10 ─

    function testDeityHighPassAndHalvedLootboxBelowLevel10() public {
        // The lootbox leg lands first (5% of the 24 ETH price), then the table credit.
        vm.expectEmit(true, false, false, true, address(game));
        emit LootBoxBuy(_fixtureId(buyer), 0, 0, DEITY_FIRST_PRICE / 20);
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(game.walletIdOf(buyer), true, 1);
        _buyDeity(buyer, 4);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 0, "early deity award is high-lane only");
        assertEq(high, 1, "early deity banks one high-roller pass");
    }

    function testDeityHighPassAtBoundaryLevel9() public {
        _setLevel(9);
        _buyDeity(buyer, 5);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 0, "level 9 deity is still the early award");
        assertEq(high, 1, "level 9 deity banks the high pass");
    }

    function testDeityNormalPassAndFullLootboxFromLevel10() public {
        _setLevel(10);
        vm.expectEmit(true, false, false, true, address(game));
        emit LootBoxBuy(_fixtureId(buyer), 0, 0, DEITY_FIRST_PRICE / 10);
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(game.walletIdOf(buyer), false, 1);
        _buyDeity(buyer, 7);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 1, "level-10+ deity banks one normal pass");
        assertEq(high, 0, "the high award is pre-level-10 only");
    }

    // ── Saturation: a full lane drops the excess, the purchase still lands ───

    function testSaturatedLaneDropsExcessAndPurchaseSucceeds() public {
        uint32 buyerId = game.walletIdOf(buyer);
        vm.prank(address(game));
        crapsBattle.creditPasses(buyerId, type(uint32).max, 0);

        _buyWhale(buyer, 2, WHALE_EARLY_PRICE);

        (uint256 normal,) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, type(uint32).max, "lane saturates instead of reverting");
    }

    // ── Awarded credits spend end to end through applyCrapsPasses ────────────

    function testAwardedNormalPassReservesAFutureDay() public {
        _buyWhale(buyer, 1, WHALE_EARLY_PRICE);
        uint24 today = crapsBattle.currentDayIndex();

        vm.prank(buyer);
        crapsBattle.applyCrapsPasses(today + 1, 1, false);

        (uint256 normal,) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 0, "the credit is spent");
        assertEq(
            crapsBattle.dayStateOf(today + 1, buyer),
            crapsBattle.DAY_SEATED(),
            "the awarded pass seats a future day"
        );
    }

    function testAwardedHighPassReservesAFutureHighDay() public {
        _buyDeity(buyer, 12);
        uint24 today = crapsBattle.currentDayIndex();

        vm.prank(buyer);
        crapsBattle.applyCrapsPasses(today + 1, 1, true);

        (, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(high, 0, "the credit is spent");
        assertTrue(
            crapsBattle.daySeatIsHigh(today + 1, buyer),
            "the deity award seats a HIGH future day"
        );
    }
}
