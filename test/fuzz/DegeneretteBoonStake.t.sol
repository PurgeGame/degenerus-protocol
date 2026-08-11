// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DegeneretteBoonStake -- the degenerette stake boon (+4/8/12%, per currency)
/// @notice The boon inflates the PACKED bet's per-spin stake and nothing else. The four
///         properties that matter:
///
///         1. SOLVENCY. Collection, the prize-pool credit and the pending-ETH ledger all
///            run on the RAW total; only the packed payout basis carries the bonus. An ETH
///            bet must therefore move exactly what the player paid into the pool -- never
///            the boosted figure -- or the boon would mint an unfunded ETH obligation.
///         2. LANE ISOLATION. Each currency has its own independent boon lane; lanes
///            coexist, and a bet reads and spends ONLY its own currency's lane, so a
///            worthless WWXRP spin can never burn a held ETH boon.
///         3. LANE ENCODING. Each 24-bit lane packs [day:21 | isDeity:1 | tier:2] with
///            bps = tier x 400. A slip here silently pays the wrong bonus or reads the
///            wrong lane, which no weight-table test would catch.
///         4. FUNDER GATING. Only the player or an approved operator spends the boon; an
///            unapproved gift bet must leave it untouched (a dust gift could burn it).
///
/// @dev The boon is written straight into `boonPacked[player].slot1` rather than fished out
///      of a lootbox roll: at 200/2,608 for the commonest tier a roll-driven fixture would be
///      flaky and could not reach a CHOSEN tier at all. The apply path that writes this field
///      is covered by BoonStaticDiscard; this suite owns the consume path.
contract DegeneretteBoonStake is DeployProtocol {
    // --- Storage slots (mirror BoonStaticDiscard / DegeneretteHeroScore) ---
    uint256 private constant SLOT_BOON_PACKED = 50;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    // --- BoonPacked slot1 degenerette lanes (DegenerusGameStorage): three independent
    // per-currency 24-bit lanes at 184/208/232, each [day:21 | isDeity:1 | tier:2].
    uint256 private constant BP_DEGEN_LANE0_SHIFT = 184;
    uint256 private constant BP_DEGEN_LANE_MASK = 0xFFFFFF;
    uint256 private constant BP_DEGEN_LANE_DAY_SHIFT = 3;
    uint256 private constant BP_DEGEN_LANE_DEITY_BIT = 0x4;

    // --- Packed bet layout (DegeneretteModule) ---
    uint256 private constant DEGEN_AMOUNT_SHIFT = 42;
    uint256 private constant MASK_128 = (uint256(1) << 128) - 1;

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev Enforcement-site caps (DegeneretteModule). WWXRP is deliberately uncapped.
    uint256 private constant CAP_ETH = 10 ether;
    uint256 private constant CAP_FLIP = 100_000 ether;

    /// @dev Lootbox-rolled boons live `stampDay + 2`; deity-granted ones die at midnight.
    uint24 private constant EXPIRY_DAYS = 2;

    bytes32 private constant BET_PLACED_SIG =
        keccak256("BetPlaced(address,uint32,uint64,uint256)");

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("degenBoonPlayer");
        vm.deal(player, 10_000 ether);

        // Placement requires lootboxRngIndex >= 1 with its word still unset.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _boonSlot1(address who) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(who, SLOT_BOON_PACKED))) + 1);
    }

    function _laneShift(uint8 currency) internal pure returns (uint256) {
        return
            BP_DEGEN_LANE0_SHIFT +
            uint256(currency == CURRENCY_WWXRP ? 2 : currency) *
            24;
    }

    function _readTier(address who, uint8 currency) internal view returns (uint8) {
        return
            uint8(
                (uint256(vm.load(address(game), _boonSlot1(who))) >>
                    _laneShift(currency)) & 0x3
            );
    }

    /// @dev Write a degenerette lane boon directly (tier 1-3 = +4/8/12%). `isDeity` marks
    ///      a deity gift (valid on its day only); otherwise the boon is lootbox-rolled
    ///      (2-day window). The other currency lanes are left as they are.
    function _grantBoon(
        address who,
        uint8 currency,
        uint8 tier,
        uint24 stampDay,
        bool isDeity
    ) internal {
        uint256 s1 = uint256(vm.load(address(game), _boonSlot1(who)));
        uint256 shift = _laneShift(currency);
        uint256 lane = (uint256(stampDay & 0x1FFFFF) << BP_DEGEN_LANE_DAY_SHIFT) |
            (isDeity ? BP_DEGEN_LANE_DEITY_BIT : 0) |
            tier;
        s1 = (s1 & ~(BP_DEGEN_LANE_MASK << shift)) | (lane << shift);
        vm.store(address(game), _boonSlot1(who), bytes32(s1));
    }

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _fundWwxrp(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
    }

    /// @dev Place a bet and return the per-spin stake the module actually PACKED (the payout
    ///      basis), read off BetPlaced. `packed` is the event's only non-indexed field.
    function _placeAndReadPackedStake(
        uint8 currency,
        uint128 perSpin,
        uint8 spins
    ) internal returns (uint256 stakePerSpin) {
        uint256 ethValue = currency == CURRENCY_ETH
            ? uint256(perSpin) * spins
            : 0;
        vm.recordLogs();
        vm.prank(player);
        game.placeDegeneretteBet{value: ethValue}(
            address(0),
            currency,
            perSpin,
            spins,
            0x01020304,
            1
        );
        return _lastPackedStake();
    }

    /// @dev Place a single-spin ETH bet FOR `forPlayer` from `caller` (a gift when the
    ///      caller is unapproved, an operator bet when approved) and return the packed
    ///      per-spin stake.
    function _placeEthFromAndReadPackedStake(
        address caller,
        address forPlayer,
        uint128 perSpin
    ) internal returns (uint256 stakePerSpin) {
        vm.recordLogs();
        vm.prank(caller);
        game.placeDegeneretteBet{value: perSpin}(
            forPlayer,
            CURRENCY_ETH,
            perSpin,
            1,
            0x01020304,
            1
        );
        return _lastPackedStake();
    }

    function _lastPackedStake() internal returns (uint256 stakePerSpin) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != BET_PLACED_SIG) continue;
            uint256 packed = abi.decode(logs[i].data, (uint256));
            return (packed >> DEGEN_AMOUNT_SHIFT) & MASK_128;
        }
        revert("BetPlaced not emitted");
    }

    /// @dev futurePrizePool occupies bits [104..207] (POOL_FUTURE_SHIFT = 104, 104-bit halves).
    function _futurePrizePool() internal view returns (uint256) {
        uint256 pools = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        return (pools >> 104) & ((uint256(1) << 104) - 1);
    }

    // =========================================================================
    // 1. Solvency: the bonus rides the packed basis, never the collected funds
    // =========================================================================

    /// @notice An ETH boon inflates the packed per-spin stake by exactly its BPS while the
    ///         player pays -- and the prize pool receives -- only the RAW total. This is the
    ///         solvency spine of the whole feature: were collection to run on the boosted
    ///         figure the bet would credit ETH the player never sent.
    function test_ethBoonBoostsPackedStakeButNotCollectedFunds() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false); // ETH +12%

        uint128 perSpin = 1 ether;
        uint256 balBefore = player.balance;
        uint256 poolBefore = _futurePrizePool();

        uint256 stake = _placeAndReadPackedStake(CURRENCY_ETH, perSpin, 1);

        assertEq(stake, 1.12 ether, "packed stake must carry the +12% bonus");
        assertEq(balBefore - player.balance, 1 ether, "player paid more than the raw bet");
        assertEq(
            _futurePrizePool() - poolBefore,
            1 ether,
            "pool credited the boosted figure: unfunded ETH obligation"
        );
    }

    /// @notice The bonus is spread across the spins, so a multi-spin bet's TOTAL basis grows
    ///         by the BPS (bar sub-spin integer dust) rather than each spin growing by it.
    function test_bonusIsSpreadAcrossSpinsNotAppliedPerSpin() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false); // ETH +12%

        uint128 perSpin = 0.5 ether;
        uint8 spins = 4; // raw total 2 ETH, bonus 0.24 ETH, 0.06 ETH per spin
        uint256 stake = _placeAndReadPackedStake(CURRENCY_ETH, perSpin, spins);

        assertEq(stake, 0.56 ether, "per-spin bonus is the total bonus / spinCount");
        assertEq(stake * spins, 2.24 ether, "total basis = raw total + 12%");
    }

    // =========================================================================
    // 2. Currency targeting
    // =========================================================================

    /// @notice A bet in a different currency neither consumes nor sweeps the boon: it waits
    ///         for a bet in its own currency. Without this a 1-token WWXRP spin would burn a
    ///         held ETH +12%.
    function test_mismatchedCurrencyLeavesBoonIntactForItsOwnBet() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false); // ETH +12%

        _fundFlip(player, 1_000 ether);
        uint256 flipStake = _placeAndReadPackedStake(CURRENCY_FLIP, 100 ether, 1);
        assertEq(flipStake, 100 ether, "FLIP bet took an ETH boon's bonus");
        assertEq(_readTier(player, CURRENCY_ETH), 3, "FLIP bet consumed a boon it could not use");

        _fundWwxrp(player, 1_000 ether);
        uint256 wwxrpStake = _placeAndReadPackedStake(CURRENCY_WWXRP, 10 ether, 1);
        assertEq(wwxrpStake, 10 ether, "WWXRP bet took an ETH boon's bonus");
        assertEq(_readTier(player, CURRENCY_ETH), 3, "WWXRP bet consumed a boon it could not use");

        // The ETH bet it was actually for still gets it.
        uint256 ethStake = _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1);
        assertEq(ethStake, 1.12 ether, "boon did not survive to its own currency");
        assertEq(_readTier(player, CURRENCY_ETH), 0, "boon not cleared after its matching bet");
    }

    /// @notice One boon, one bet: the second bet in the same currency is unboosted.
    function test_boonIsSpentOnceThenGone() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 1, today, false); // ETH +4%

        assertEq(_placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1), 1.04 ether, "first bet");
        assertEq(_placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1), 1 ether, "boon paid twice");
    }

    // =========================================================================
    // 3. Tier encoding -- all nine draws round-trip to the right currency AND size
    // =========================================================================

    /// @notice Sweep tier 1-3 in every lane and assert it pays the documented bonus on
    ///         the documented currency. This is the encode/decode round trip that the
    ///         weight walk cannot check: a mis-shifted lane pays FLIP money on an ETH boon.
    function test_allNineTiersDecodeToTheirCurrencyAndBps() public {
        uint24 today = game.currentDayView();
        uint256[3] memory bps = [uint256(400), uint256(800), uint256(1200)];

        // Every lane holds tier 1/2/3 = +4/8/12%.
        for (uint256 step = 0; step < 3; step++) {
            // --- ETH ---
            _grantBoon(player, CURRENCY_ETH, uint8(1 + step), today, false);
            uint256 got = _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1);
            assertEq(got, uint256(1 ether) + (uint256(1 ether) * bps[step]) / 10_000, "ETH tier bps");

            // --- FLIP ---
            _grantBoon(player, CURRENCY_FLIP, uint8(1 + step), today, false);
            _fundFlip(player, 10_000 ether);
            got = _placeAndReadPackedStake(CURRENCY_FLIP, 1_000 ether, 1);
            assertEq(
                got,
                uint256(1_000 ether) + (uint256(1_000 ether) * bps[step]) / 10_000,
                "FLIP tier bps"
            );

            // --- WWXRP ---
            _grantBoon(player, CURRENCY_WWXRP, uint8(1 + step), today, false);
            _fundWwxrp(player, 10_000 ether);
            got = _placeAndReadPackedStake(CURRENCY_WWXRP, 1_000 ether, 1);
            assertEq(
                got,
                uint256(1_000 ether) + (uint256(1_000 ether) * bps[step]) / 10_000,
                "WWXRP tier bps"
            );
        }
    }

    /// @notice The three currency lanes are INDEPENDENT: all three boons coexist, and each
    ///         bet consumes only its own currency's lane, leaving the other two in place.
    ///         No currency can displace or spend another's boon.
    function test_currencyLanesCoexistAndConsumeIndependently() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 1, today, false); // ETH +4%
        _grantBoon(player, CURRENCY_FLIP, 3, today, false); // FLIP +12%
        _grantBoon(player, CURRENCY_WWXRP, 2, today, false); // WWXRP +8%

        // The FLIP bet spends the FLIP lane alone.
        _fundFlip(player, 10_000 ether);
        assertEq(
            _placeAndReadPackedStake(CURRENCY_FLIP, 1_000 ether, 1),
            1_120 ether,
            "FLIP lane did not pay its own bet"
        );
        assertEq(_readTier(player, CURRENCY_FLIP), 0, "FLIP lane not spent");
        assertEq(_readTier(player, CURRENCY_ETH), 1, "ETH lane touched by a FLIP bet");
        assertEq(_readTier(player, CURRENCY_WWXRP), 2, "WWXRP lane touched by a FLIP bet");

        // The remaining lanes still pay their own bets.
        assertEq(
            _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1),
            1.04 ether,
            "ETH lane did not survive the FLIP consume"
        );
        _fundWwxrp(player, 10_000 ether);
        assertEq(
            _placeAndReadPackedStake(CURRENCY_WWXRP, 1_000 ether, 1),
            1_080 ether,
            "WWXRP lane did not survive the other consumes"
        );
    }

    // =========================================================================
    // 4. Caps
    // =========================================================================

    /// @notice The ETH bonus is computed on the first 10 ETH of the bet only, so an
    ///         oversized bet is boosted on the capped slice.
    function test_ethCapBindsAboveTenEth() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false); // ETH +12%

        // 25 ETH total, well past the 10 ETH cap.
        uint128 perSpin = 5 ether;
        uint8 spins = 5;
        uint256 stake = _placeAndReadPackedStake(CURRENCY_ETH, perSpin, spins);

        uint256 expectedBonusTotal = (CAP_ETH * 1200) / 10_000; // 1.2 ETH, not 3 ETH
        assertEq(stake, perSpin + expectedBonusTotal / spins, "ETH cap did not bind");
        assertLt(stake * spins, 28 ether, "uncapped 12% of 25 ETH leaked through");
    }

    /// @notice Same for FLIP at 100k.
    function test_flipCapBindsAboveHundredThousand() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_FLIP, 3, today, false); // FLIP +12%

        uint128 perSpin = 300_000 ether;
        _fundFlip(player, 1_000_000 ether);
        uint256 stake = _placeAndReadPackedStake(CURRENCY_FLIP, perSpin, 1);

        uint256 expectedBonus = (CAP_FLIP * 1200) / 10_000; // 12k FLIP, not 36k
        assertEq(stake, perSpin + expectedBonus, "FLIP cap did not bind");
    }

    /// @notice WWXRP is deliberately UNCAPPED -- it is worthless by design, so a percentage
    ///         of an arbitrarily large WWXRP bet moves no real value. A cap appearing here
    ///         would be an unintended behaviour change.
    function test_wwxrpHasNoCap() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_WWXRP, 3, today, false); // WWXRP +12%

        uint128 perSpin = 500_000 ether; // far past both sibling caps
        _fundWwxrp(player, 1_000_000 ether);
        uint256 stake = _placeAndReadPackedStake(CURRENCY_WWXRP, perSpin, 1);

        assertEq(stake, perSpin + (uint256(perSpin) * 1200) / 10_000, "WWXRP was capped");
    }

    // =========================================================================
    // 5. Expiry
    // =========================================================================

    /// @notice A DEITY-granted boon is valid on its grant day only: the next day's bet gets
    ///         nothing and the field is swept.
    function test_deityGrantedBoonDiesAtMidnight() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, true); // deity gift

        vm.warp(block.timestamp + 1 days);
        assertGt(game.currentDayView(), today, "day did not roll");

        uint256 stake = _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1);
        assertEq(stake, 1 ether, "expired deity boon still paid");
        assertEq(_readTier(player, CURRENCY_ETH), 0, "expired deity boon not swept");
    }

    /// @notice A LOOTBOX-rolled boon keeps its 2-day window: live on stampDay + 2, dead on
    ///         stampDay + 3.
    function test_lootboxRolledBoonLivesTwoDaysThenExpires() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false);

        vm.warp(block.timestamp + uint256(EXPIRY_DAYS) * 1 days);
        assertEq(
            _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1),
            1.12 ether,
            "boon died inside its 2-day window"
        );

        // Re-grant and step one day past the window.
        _grantBoon(player, CURRENCY_ETH, 3, today, false);
        vm.warp(block.timestamp + 1 days);
        assertEq(
            _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1),
            1 ether,
            "boon outlived its 2-day window"
        );
        assertEq(_readTier(player, CURRENCY_ETH), 0, "expired boon not swept");
    }

    // =========================================================================
    // 6. No-boon regression
    // =========================================================================

    /// @notice A player with no boon is untouched on every currency -- the inline tier read
    ///         short-circuits before the nested dispatch, and the packed stake is the raw one.
    function test_noBoonLeavesEveryCurrencyUnchanged() public {
        assertEq(_placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1), 1 ether, "ETH");

        _fundFlip(player, 10_000 ether);
        assertEq(_placeAndReadPackedStake(CURRENCY_FLIP, 1_000 ether, 1), 1_000 ether, "FLIP");

        _fundWwxrp(player, 10_000 ether);
        assertEq(_placeAndReadPackedStake(CURRENCY_WWXRP, 1_000 ether, 1), 1_000 ether, "WWXRP");
    }

    // =========================================================================
    // 7. Funder gating -- gifts never spend the recipient's boon
    // =========================================================================

    /// @notice An UNAPPROVED caller gifting a bet must not spend the recipient's boon:
    ///         a minimum-size dust gift could otherwise burn a held +12% before the
    ///         player's own bet ever sees it.
    function test_giftBetLeavesRecipientBoonUntouched() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false);

        address gifter = makeAddr("degenBoonGifter");
        vm.deal(gifter, 1 ether);
        uint256 stake = _placeEthFromAndReadPackedStake(gifter, player, 0.005 ether);

        assertEq(stake, 0.005 ether, "gift bet collected the recipient's boon");
        assertEq(_readTier(player, CURRENCY_ETH), 3, "gift burned the held boon");

        // The player's own next bet still collects it.
        assertEq(
            _placeAndReadPackedStake(CURRENCY_ETH, 1 ether, 1),
            1.12 ether,
            "boon lost after the gift"
        );
    }

    /// @notice An APPROVED operator spends the player's funds AND the player's boon --
    ///         the approval is the trust boundary; only unapproved gifters are locked out.
    function test_approvedOperatorSpendsTheBoon() public {
        uint24 today = game.currentDayView();
        _grantBoon(player, CURRENCY_ETH, 3, today, false);

        address operator = makeAddr("degenBoonOperator");
        vm.prank(player);
        game.setOperatorApproval(operator, true);

        vm.deal(operator, 2 ether);
        uint256 stake = _placeEthFromAndReadPackedStake(operator, player, 1 ether);
        assertEq(stake, 1.12 ether, "approved operator could not spend the boon");
        assertEq(_readTier(player, CURRENCY_ETH), 0, "boon not consumed by the operator bet");
    }
}
