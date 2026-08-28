// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @title Whale/deity purchases bank Craps pass credits
/// @notice Below level 10 a whale pass banks one normal Craps day-pass credit per pass bought
///         (lootbox untouched at 10%), and a deity pass banks one HIGH-ROLLER credit with the
///         lootbox halved to 5%. From level 10 the whale award stops entirely and the deity
///         award becomes one normal credit with the full 10% lootbox. The gate is level < 10,
///         held here at both sides of the boundary.
///
///         The presale box's FLIP branch tosses a committed coin: half the boxes pay the
///         collapsed roll as coinflip credit untouched, half denominate the WHOLE roll into
///         passes at the regular box units (22,800 normal, 19x high above twenty normal units,
///         fraction Bernoulli-rounded), capped at twelve high passes with the rest staying
///         coinflip credit; a sub-pass roll whose fraction loses pays the WWXRP dud.
contract CrapsPassAwards is DeployProtocol {
    event CrapsPassesCredited(address indexed player, bool highRoller, uint256 count);
    event LootBoxBuy(address indexed buyer, uint48 indexed index, uint256 amount);

    uint256 private constant WHALE_EARLY_PRICE = 2.4 ether;
    uint256 private constant WHALE_STANDARD_PRICE = 4 ether;
    uint256 private constant DEITY_FIRST_PRICE = 24 ether;

    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("pass_award_buyer");
        vm.deal(buyer, 5_000 ether);
    }

    /// @dev game.level = lvl: uint24 at slot 0, byte offset 12 (bit 96).
    function _setLevel(uint24 lvl) private {
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
        game.purchaseWhalePass{value: unitPrice * qty}(who, qty, bytes32(0));
    }

    function _buyDeity(address who, uint8 symbolId) private {
        vm.prank(who);
        game.purchaseDeityPass{value: DEITY_FIRST_PRICE}(who, symbolId, bytes32(0));
    }

    // ── Whale: one normal credit per pass below level 10, nothing from 10 ────

    function testWhaleAwardPerPassBelowLevel10() public {
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(buyer, false, 3);
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
        emit LootBoxBuy(buyer, 0, DEITY_FIRST_PRICE / 20);
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(buyer, true, 1);
        _buyDeity(buyer, 0);

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
        emit LootBoxBuy(buyer, 0, DEITY_FIRST_PRICE / 10);
        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(buyer, false, 1);
        _buyDeity(buyer, 7);

        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(buyer);
        assertEq(normal, 1, "level-10+ deity banks one normal pass");
        assertEq(high, 0, "the high award is pre-level-10 only");
    }

    // ── Saturation: a full lane drops the excess, the purchase still lands ───

    function testSaturatedLaneDropsExcessAndPurchaseSucceeds() public {
        vm.prank(address(game));
        crapsBattle.creditPasses(buyer, type(uint32).max, 0);

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

    // ── Presale box: a committed coin toss picks FLIP or all-passes ──────────

    event PresaleBoxOpened(
        address indexed player,
        uint48 indexed index,
        uint256 amount,
        uint256 flip,
        uint256 dgnrs,
        uint256 wwxrp,
        bool closing,
        uint32 normalPasses,
        uint32 highPasses
    );

    uint256 private constant SLOT_PRESALE_BOX_CREDIT = 17;
    uint256 private constant SLOT_LOOTBOX_RNG_PACKED = 33;
    uint256 private constant SLOT_LOOTBOX_RNG_WORD = 34;
    uint256 private constant NORMAL_UNIT = 22_800 ether;
    uint256 private constant HIGH_UNIT = 19 * 22_800 ether;
    uint256 private constant HIGH_CAP = 12;
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    uint256 private constant PASS_ROUND_TAG = 0x50617373526f756e64; // "PassRound"
    uint256 private constant PASS_SIDE_TAG = 0x5061737353696465; // "PassSide"
    uint256 private constant WWXRP_DUD = 1 ether;

    /// @dev Buy one fully-ETH-funded presale box at the current index (credit seeded first).
    function _buyPresaleBox(address who, uint256 amount) private returns (uint48 index) {
        vm.store(
            address(game),
            keccak256(abi.encode(who, SLOT_PRESALE_BOX_CREDIT)),
            bytes32(amount)
        );
        vm.deal(who, amount);
        index = uint48(
            uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED))) & 0xFFFFFFFFFFFF
        );
        vm.prank(who);
        game.buyPresaleBox{value: amount}(who, amount);
    }

    function _setWord(uint48 index, uint256 word) private {
        vm.store(
            address(game),
            keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_RNG_WORD)),
            bytes32(word)
        );
    }

    function _seedOf(uint256 word, address who, uint256 amount) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(word, keccak256("PRESALE_BOX"), who, amount)));
    }

    /// @dev A word landing the FLIP branch (outcome < 50) on the requested variance band and
    ///      side of the FLIP-or-passes toss.
    function _flipWord(address who, uint256 amount, bool highVariance, bool passSide)
        private
        pure
        returns (uint256 w)
    {
        for (w = 1; w < 200_000; ++w) {
            uint256 seed = _seedOf(w, who, amount);
            if (uint16(seed) % 100 >= 50) continue;
            if ((uint16(seed >> 80) % 20 >= 16) != highVariance) continue;
            if ((EntropyLib.hash2(seed, PASS_SIDE_TAG) & 1 == 1) != passSide) continue;
            return w;
        }
        revert("no word found");
    }

    /// @dev Mirrors the presale FLIP branch through the 100-FLIP collapse (level-0 price).
    function _mirrorFlipOut(uint256 word, address who, uint256 amount)
        private
        pure
        returns (uint256 flipOut)
    {
        uint256 seed = _seedOf(word, who, amount);
        uint256 vr = uint16(seed >> 80) % 20;
        uint256 bps = vr < 16 ? 14_098 + vr * 1_158 : 74_534 + (vr - 16) * 22_890;
        flipOut = (((amount * bps) / 10_000) * 1000 ether) / 0.01 ether;
        flipOut = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(seed, FLIP_ROUND_TAG))
            : FlipRoundLib.floorWholeFlip(flipOut);
    }

    /// @dev Mirrors the all-passes side: whole roll, box units, Bernoulli fraction, 12-high cap.
    function _expectedPasses(uint256 seed, uint256 flipOut)
        private
        pure
        returns (uint32 n, uint32 h, uint256 flipLeft)
    {
        bool hp = flipOut > 20 * NORMAL_UNIT;
        uint256 unit = hp ? HIGH_UNIT : NORMAL_UNIT;
        uint256 cnt = flipOut / unit;
        if (hp && cnt >= HIGH_CAP) {
            cnt = HIGH_CAP;
            flipLeft = flipOut - HIGH_CAP * HIGH_UNIT;
        } else {
            uint256 rem = flipOut % unit;
            if (rem != 0 && EntropyLib.hash2(seed, PASS_ROUND_TAG) % unit < rem) ++cnt;
        }
        if (hp) h = uint32(cnt);
        else n = uint32(cnt);
    }

    function testPresaleFlipSidePaysTheRollUntouched() public {
        address p = makeAddr("presale_flip_side");
        uint256 amount = 1 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _flipWord(p, amount, false, false);
        _setWord(index, word);

        uint256 flipOut = _mirrorFlipOut(word, p, amount);
        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, flipOut, 0, 0, false, 0, 0);
        game.openBox(p, index);

        (uint256 cn, uint256 ch) = crapsBattle.passCreditsOf(p);
        assertEq(cn | ch, 0, "the FLIP side banks no passes");
    }

    function testPresalePassSideConvertsTheWholeRollNormalLane() public {
        address p = makeAddr("presale_normal");
        uint256 amount = 1 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _flipWord(p, amount, false, true);
        _setWord(index, word);

        uint256 flipOut = _mirrorFlipOut(word, p, amount);
        (uint32 n, uint32 h, uint256 flipLeft) = _expectedPasses(_seedOf(word, p, amount), flipOut);
        assertGt(n, 0, "scenario shape: at least one normal pass");
        assertEq(h, 0, "scenario shape: below the high switch");
        assertEq(flipLeft, 0, "scenario shape: uncapped side pays no FLIP");

        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(p, false, n);
        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, 0, 0, 0, false, n, 0);
        game.openBox(p, index);

        (uint256 cn, uint256 ch) = crapsBattle.passCreditsOf(p);
        assertEq(cn, n, "normal credits banked");
        assertEq(ch, 0, "no high credits in the normal lane");
    }

    function testPresalePassSideHighLaneBelowCap() public {
        address p = makeAddr("presale_high");
        uint256 amount = 10 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _flipWord(p, amount, false, true);
        _setWord(index, word);

        uint256 flipOut = _mirrorFlipOut(word, p, amount);
        (uint32 n, uint32 h,) = _expectedPasses(_seedOf(word, p, amount), flipOut);
        assertEq(n, 0, "scenario shape: the lane switch is exclusive");
        assertGt(h, 0, "scenario shape: at least one high pass");
        assertLt(h, HIGH_CAP, "scenario shape: under the cap");

        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(p, true, h);
        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, 0, 0, 0, false, 0, h);
        game.openBox(p, index);

        (uint256 cn, uint256 ch) = crapsBattle.passCreditsOf(p);
        assertEq(cn, 0, "no normal credits in the high lane");
        assertEq(ch, h, "high credits banked");
    }

    function testPresaleHighCapBindsAndExcessStaysFlip() public {
        address p = makeAddr("presale_whale");
        uint256 amount = 30 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _flipWord(p, amount, true, true);
        _setWord(index, word);

        uint256 flipOut = _mirrorFlipOut(word, p, amount);
        assertGt(flipOut / HIGH_UNIT, HIGH_CAP, "scenario shape: the cap must bind");
        (, uint32 h, uint256 flipLeft) = _expectedPasses(_seedOf(word, p, amount), flipOut);
        assertEq(h, HIGH_CAP, "capped at twelve high passes");
        assertGt(flipLeft, 0, "the rest of the roll stays FLIP");

        vm.expectEmit(address(crapsBattle));
        emit CrapsPassesCredited(p, true, HIGH_CAP);
        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, flipLeft, 0, 0, false, 0, uint32(HIGH_CAP));
        game.openBox(p, index);

        (, uint256 ch) = crapsBattle.passCreditsOf(p);
        assertEq(ch, HIGH_CAP, "twelve high credits banked");
        assertEq(HIGH_CAP * HIGH_UNIT + flipLeft, flipOut, "the excess above the cap stays FLIP");
    }

    /// @dev A word putting a sub-pass roll on the pass side with the fraction's Bernoulli
    ///      landing as requested.
    function _subPassWord(address who, uint256 amount, bool win) private pure returns (uint256 w) {
        for (w = 1; w < 500_000; ++w) {
            uint256 seed = _seedOf(w, who, amount);
            if (uint16(seed) % 100 >= 50) continue;
            if (uint16(seed >> 80) % 20 >= 16) continue; // low band keeps the roll sub-pass
            if (EntropyLib.hash2(seed, PASS_SIDE_TAG) & 1 != 1) continue;
            uint256 flipOut = _mirrorFlipOut(w, who, amount);
            if (flipOut == 0 || flipOut >= NORMAL_UNIT) continue;
            bool won = EntropyLib.hash2(seed, PASS_ROUND_TAG) % NORMAL_UNIT < flipOut;
            if (won == win) return w;
        }
        revert("no word found");
    }

    function testPresaleSubPassBernoulliWinPaysOneWholePass() public {
        address p = makeAddr("presale_bernoulli_win");
        uint256 amount = 0.05 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _subPassWord(p, amount, true);
        _setWord(index, word);

        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, 0, 0, 0, false, 1, 0);
        game.openBox(p, index);

        (uint256 cn,) = crapsBattle.passCreditsOf(p);
        assertEq(cn, 1, "the winning fraction pays one whole normal pass");
    }

    function testPresaleSubPassBernoulliLossPaysTheWwxrpDud() public {
        address p = makeAddr("presale_bernoulli_loss");
        uint256 amount = 0.05 ether;
        uint48 index = _buyPresaleBox(p, amount);
        uint256 word = _subPassWord(p, amount, false);
        _setWord(index, word);

        vm.expectEmit(address(game));
        emit PresaleBoxOpened(p, index, amount, 0, 0, WWXRP_DUD, false, 0, 0);
        game.openBox(p, index);

        (uint256 cn, uint256 ch) = crapsBattle.passCreditsOf(p);
        assertEq(cn | ch, 0, "the losing fraction banks no passes");
        assertEq(wwxrp.balanceOf(p), WWXRP_DUD, "the dud lands instead");
    }
}
