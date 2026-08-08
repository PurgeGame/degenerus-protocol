// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DegeneretteBiggestSpinBonusTest — pins the biggest-ETH-spin record bonus.
///
/// @notice An ETH Degenerette spin that beats the all-time `amountPerSpin` record by a
///         tenth claims a bonus applied to BOTH payout legs at resolve. The bonus starts
///         at a 5% floor, accrues 0.2%/day since the LAST CLAIM, and clamps at 50%.
///
/// @dev The behaviours pinned here are the ones a refactor would quietly break:
///      - The clock is stamped on the game's FIRST ETH spin (bootstrap). An unstamped
///        zero would read the whole day index as elapsed and max the very next claim.
///      - A bare ratchet (larger, but under +10%) raises the bar and MUST leave the day
///        stamp alone, or a 1-wei ratchet zeroes an accrued pot for everyone.
///      - The bonus is applied per-leg AFTER the 3-tier split. Scaling `payout` before it
///        pushes a tier-1 outcome (payout <= 3*bet) past the boundary into tier 2, which
///        drops the ETH leg to the 2.5*bet floor — the player's cash FALLS on a bonused
///        win. Pinned by asserting a tier-1 spin still pays 100% ETH after the bonus.
///      - Non-ETH currencies never touch the record and never carry a bonus.
///
///      The record and clock are `internal`, so they are read straight out of slot 16
///      (presaleBoxEthSold | biggestDegeneretteEthEver | biggestDegeneretteDay), which is
///      also a live check that the three stay packed in one slot.
contract DegeneretteBiggestSpinBonusTest is DeployProtocol {
    /// @dev Slot 16 packs presaleBoxEthSold (uint96, byte 0), biggestDegeneretteEthEver
    ///      (uint128, byte 12) and biggestDegeneretteDay (uint24, byte 28). Byte offset 12
    ///      is bit 96; byte offset 28 is bit 224.
    uint256 private constant BIGGEST_SPIN_SLOT = 16;
    uint256 private constant RECORD_SHIFT = 96;
    uint256 private constant RECORD_DAY_SHIFT = 224;

    uint256 private constant DEGENERETTE_BETS_SLOT = 37;
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 38;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    /// @dev Mirrors DegeneretteModule.DEGEN_BONUS_BPS_SHIFT (private there).
    uint256 private constant DEGEN_BONUS_BPS_SHIFT = 220;

    /// @dev Mirrors the module's biggest-spin constants (all private there).
    uint256 private constant FLOOR_BPS = 500;
    uint256 private constant PER_DAY_BPS = 20;
    uint256 private constant CEIL_BPS = 5_000;

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    uint256 private constant MIN_BET_ETH = 5 ether / 1000;
    uint256 private constant MIN_BET_FLIP = 100 ether;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    bytes32 private constant RESULT_SIG =
        keccak256("DegeneretteResult(address,uint64,uint8,uint32,uint8,uint256)");
    bytes32 private constant RESOLVED_SIG =
        keccak256("DegeneretteResolved(address,uint64,uint8,uint256,uint32)");

    address private player;

    function setUp() public {
        _deployProtocol();
        _skipDays(1);

        player = makeAddr("biggest_spin_player");
        vm.deal(player, 100_000 ether);
        vm.deal(address(game), 100_000 ether);

        // placeDegeneretteBet reverts when lootboxRngIndex == 0; seed it to 1. The word
        // at index 1 stays 0 (unfulfilled), which is the state placement requires.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        _seedFuturePrizePool(50_000 ether);
    }

    // ---------------------------------------------------------------------
    // Record + clock bookkeeping
    // ---------------------------------------------------------------------

    /// @notice The game's first ETH spin sets the mark and starts the clock, but has no
    ///         bar to clear by a tenth, so it claims nothing.
    function testFirstEthSpinBootstrapsClockWithoutClaiming() public {
        assertEq(_record(), 0, "record starts unset");

        uint24 day = _dayIndex();
        uint64 betId = _placeEth(1 ether, 1);

        assertEq(_record(), 1 ether, "first ETH spin sets the record");
        assertEq(_recordDay(), day, "first ETH spin stamps the clock");
        assertEq(_bonusBpsOf(betId), 0, "bootstrap claims no bonus");
    }

    /// @notice A larger spin under the +10% bar ratchets the record but must NOT restamp
    ///         the clock — otherwise a dust ratchet zeroes an accrued pot.
    function testSubThresholdRatchetLeavesClockAlone() public {
        uint24 day0 = _dayIndex();
        _placeEth(1 ether, 1);

        _skipDays(30);

        // +9.99%: strictly larger, strictly under record + record/10.
        uint64 betId = _placeEth(1.0999 ether, 1);

        assertEq(_record(), 1.0999 ether, "sub-threshold spin still ratchets the record");
        assertEq(_recordDay(), day0, "sub-threshold spin leaves the clock stamped at bootstrap");
        assertEq(_bonusBpsOf(betId), 0, "sub-threshold spin claims nothing");
    }

    /// @notice A spin at exactly +10% claims, and the bonus is the floor plus per-day
    ///         accrual measured from the last claim.
    function testClaimAtExactThresholdPaysAccruedBonus() public {
        _placeEth(1 ether, 1);

        uint256 elapsed = 30;
        _skipDays(elapsed);
        uint24 dayAtClaim = _dayIndex();

        // Exactly record + record/10.
        uint64 betId = _placeEth(1.1 ether, 1);

        assertEq(
            _bonusBpsOf(betId),
            FLOOR_BPS + PER_DAY_BPS * elapsed,
            "claim pays floor + 0.2%/day since the last claim"
        );
        assertEq(_recordDay(), dayAtClaim, "a claim restamps the clock");
        assertEq(_record(), 1.1 ether, "a claim also ratchets the record");
    }

    /// @notice Accrual is measured from the last CLAIM, not the last ratchet: a
    ///         sub-threshold ratchet in between must not reset the pot.
    function testAccrualSurvivesInterveningRatchet() public {
        _placeEth(1 ether, 1);

        _skipDays(20);
        _placeEth(1.05 ether, 1); // ratchet only — under the bar

        _skipDays(20);
        // Bar is now 1.05 + 0.105 = 1.155.
        uint64 betId = _placeEth(1.2 ether, 1);

        assertEq(
            _bonusBpsOf(betId),
            FLOOR_BPS + PER_DAY_BPS * 40,
            "accrual runs from the bootstrap claim across the intervening ratchet"
        );
    }

    /// @notice The ceiling is reached exactly 225 days after a claim: 500 + 20*225 == 5000.
    function testAccrualReachesCeilingAtDay225() public {
        _placeEth(1 ether, 1);

        _skipDays(225);
        uint64 atCeiling = _placeEth(1.1 ether, 1);
        assertEq(_bonusBpsOf(atCeiling), CEIL_BPS, "225 days reaches the ceiling exactly");
    }

    /// @notice Past the ceiling the accrual clamps rather than running on. Held under the
    ///         level-0 idle timeout (365 days), which would otherwise trip GameOver.
    function testAccrualClampsPastCeiling() public {
        _placeEth(1 ether, 1);

        // 320 days would accrue to 500 + 6400 = 6900 bps unclamped.
        _skipDays(320);
        uint64 pastCeiling = _placeEth(1.1 ether, 1);
        assertEq(_bonusBpsOf(pastCeiling), CEIL_BPS, "accrual clamps at the ceiling");
    }

    /// @notice A claim resets the pot to the floor.
    function testClaimResetsPotToFloor() public {
        _placeEth(1 ether, 1);
        _skipDays(100);
        _placeEth(1.1 ether, 1); // claims the accrued pot

        uint64 next = _placeEth(1.3 ether, 1); // same day, immediately after
        assertEq(_bonusBpsOf(next), FLOOR_BPS, "a fresh claim pays the floor");
    }

    /// @notice A spin under the entry floor never touches the record slot — the gate that
    ///         keeps the cold SLOAD off nearly all ETH bets. It must also be unable to
    ///         bootstrap the record, or the floor would not hold.
    function testSpinBelowEntryFloorNeverTouchesRecord() public {
        uint64 tiny = _placeEth(uint128(MIN_BET_ETH), 1);
        assertEq(_record(), 0, "a sub-floor spin cannot bootstrap the record");
        assertEq(_recordDay(), 0, "a sub-floor spin cannot start the clock");
        assertEq(_bonusBpsOf(tiny), 0, "a sub-floor spin claims nothing");

        uint64 justUnder = _placeEth(1 ether - 1, 1);
        assertEq(_record(), 0, "one wei under the floor is still out");
        assertEq(_bonusBpsOf(justUnder), 0, "one wei under the floor claims nothing");

        // Exactly at the floor engages the mechanic.
        uint64 atFloor = _placeEth(1 ether, 1);
        assertEq(_record(), 1 ether, "the floor itself bootstraps the record");
        assertEq(_bonusBpsOf(atFloor), 0, "bootstrap still claims nothing");
    }

    /// @notice Once a record stands, a sub-floor spin still cannot disturb it.
    function testSubFloorSpinCannotDisturbStandingRecord() public {
        _placeEth(5 ether, 1);
        uint24 stamped = _recordDay();

        _skipDays(40);
        _placeEth(uint128(MIN_BET_ETH), 1);

        assertEq(_record(), 5 ether, "record unchanged by a sub-floor spin");
        assertEq(_recordDay(), stamped, "clock unchanged by a sub-floor spin");
    }

    /// @notice FLIP and WWXRP bets never touch the record and never carry a bonus.
    function testNonEthCurrenciesNeverTouchTheRecord() public {
        _placeEth(1 ether, 1);
        _skipDays(50);

        _fundFlip(player, 1_000_000 ether);
        uint64 flipBet = _place(CURRENCY_FLIP, uint128(MIN_BET_FLIP * 100), 1);

        assertEq(_record(), 1 ether, "a FLIP bet leaves the ETH record untouched");
        assertEq(_bonusBpsOf(flipBet), 0, "a FLIP bet carries no record bonus");
    }

    // ---------------------------------------------------------------------
    // Payout application
    // ---------------------------------------------------------------------

    /// @notice The claimed bonus scales the bet's total payout. Per-leg rounding leaves at
    ///         most 1 wei per leg with the house, so the total lands within 2 wei/spin of
    ///         the exact scaling of the raw per-spin sums.
    function testBonusScalesResolvedTotalPayout() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("biggest_spin_bonus_word"));
        uint32 ticket = _winningTicketFor(index, word);

        _placeEth(1 ether, 1); // bootstrap the record + clock (clears the entry floor)

        uint256 elapsed = 30;
        _skipDays(elapsed);

        uint8 spins = 4;
        uint64 betId = _placeEthTicket(2 ether, spins, ticket);
        uint256 bps = _bonusBpsOf(betId);
        assertEq(bps, FLOOR_BPS + PER_DAY_BPS * elapsed, "bet claimed the accrued pot");

        _injectRngWord(index, word);

        vm.recordLogs();
        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), ids);

        (uint256 rawSum, uint256 total, uint256 spinCount) = _rawSumAndResolvedTotal();
        assertGt(rawSum, 0, "non-vacuity: the bet must have won something");

        uint256 expected = rawSum + (rawSum * bps) / 10_000;
        assertApproxEqAbs(
            total,
            expected,
            2 * spinCount,
            "resolved total == raw per-spin sum scaled by the claimed bonus"
        );
        assertGt(total, rawSum, "the bonus strictly increased the payout");
    }

    /// @notice The bonus is applied AFTER the 3-tier split, so a tier-1 spin
    ///         (payout <= 3*bet) still pays 100% ETH. Scaling `payout` before the split
    ///         would push it into tier 2 and drop the ETH leg to the 2.5*bet floor —
    ///         the bonused win would pay LESS cash than the unbonused one.
    ///         The case is chosen to DISCRIMINATE: an all-gold pick (N=4) scoring S=2 pays
    ///         2.81x bet at 100% ROI, so it sits inside tier 1 — but 2.81 * 1.5 = 4.21 is
    ///         past the 3x boundary. Under the correct per-leg order the spin pays its whole
    ///         bonused payout as ETH; under a pre-split scaling it would fall into tier 2 and
    ///         credit only the 2.5x bet floor, LESS cash than the same win unbonused.
    function testTierOneSpinStaysAllEthUnderBonus() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("biggest_spin_tier1_word"));
        uint128 bet = 2 ether;

        _placeEth(1 ether, 1);
        // 225+ days puts the claim at the 50% ceiling — the widest the bonus ever gets, so
        // the tier boundary is crossed by the largest margin the mechanic can produce.
        _skipDays(225);

        (uint32 ticket, uint8 hero) = _allGoldScoreTwoTicket(index, word);

        uint64 betId = _placeEthTicket(bet, 1, ticket, hero);
        assertEq(_bonusBpsOf(betId), CEIL_BPS, "bet claimed the ceiling bonus");

        _injectRngWord(index, word);

        uint256 preClaimable = game.claimableWinningsOf(player);
        vm.recordLogs();
        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), ids);

        (uint256 rawSum, uint256 total, ) = _rawSumAndResolvedTotal();
        assertGt(rawSum, 0, "non-vacuity: the S=2 spin must have paid");
        assertLe(rawSum, uint256(bet) * 3, "precondition: the raw payout really is tier 1");
        assertGt(
            rawSum + (rawSum * CEIL_BPS) / 10_000,
            uint256(bet) * 3,
            "discriminating: a pre-split scaling WOULD have crossed into tier 2"
        );

        // Tier 1 has no lootbox leg, so the whole bonused payout lands in claimable ETH.
        uint256 credited = game.claimableWinningsOf(player) - preClaimable;
        assertEq(credited, total, "a tier-1 spin pays its whole bonused payout as ETH");
        assertEq(
            credited,
            rawSum + (rawSum * CEIL_BPS) / 10_000,
            "the ETH leg carries the full bonus, no tier-2 floor collapse"
        );
    }

    /// @notice A multi-spin bet claims once and the bonus applies to every spin — the
    ///         wager scales with the spin count, so the bonus does too. No arbitrage
    ///         against a single-spin claim at the same record size.
    function testMultiSpinBetClaimsOnceAndBonusesEverySpin() public {
        uint48 index = 1;
        uint256 word = uint256(keccak256("biggest_spin_multispin_word"));
        uint32 ticket = _winningTicketFor(index, word);

        _placeEth(1 ether, 1);
        _skipDays(10);

        uint8 spins = 25; // MAX_SPINS_ETH
        uint64 betId = _placeEthTicket(1.5 ether, spins, ticket);
        uint256 bps = _bonusBpsOf(betId);
        assertEq(bps, FLOOR_BPS + PER_DAY_BPS * 10, "the 25-spin bet claims exactly once");

        _injectRngWord(index, word);

        vm.recordLogs();
        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;
        vm.prank(player);
        game.resolveDegeneretteBets(address(0), ids);

        (uint256 rawSum, uint256 total, uint256 spinCount) = _rawSumAndResolvedTotal();
        assertEq(spinCount, spins, "every spin emitted a result");
        assertGt(rawSum, 0, "non-vacuity");
        assertApproxEqAbs(
            total,
            rawSum + (rawSum * bps) / 10_000,
            2 * spinCount,
            "the bonus applied across all 25 spins"
        );
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Mint FLIP to `who` through the GAME-gated entrypoint.
    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _record() internal view returns (uint256) {
        uint256 slot = uint256(vm.load(address(game), bytes32(BIGGEST_SPIN_SLOT)));
        return (slot >> RECORD_SHIFT) & ((uint256(1) << 128) - 1);
    }

    function _recordDay() internal view returns (uint24) {
        uint256 slot = uint256(vm.load(address(game), bytes32(BIGGEST_SPIN_SLOT)));
        return uint24((slot >> RECORD_DAY_SHIFT) & 0xFFFFFF);
    }

    /// @dev Advance the clock by whole days. Reads the current time through the cheatcode
    ///      rather than `block.timestamp`: the optimizer treats a bare TIMESTAMP read as
    ///      movable across `vm.warp` (an opaque external call), so `vm.warp(block.timestamp
    ///      + N)` can be CSE'd onto one read or sunk past an earlier warp — either way the
    ///      clock silently fails to advance as written. `vm.getBlockTimestamp()` is itself an
    ///      external call, so it cannot be reordered against the warps around it.
    function _skipDays(uint256 numDays) internal {
        vm.warp(vm.getBlockTimestamp() + numDays * 1 days);
    }

    /// @dev The live day index, computed exactly as `_simulatedDayIndex()` does.
    function _dayIndex() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex();
    }

    function _bonusBpsOf(uint64 betId) internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), _betSlot(player, betId)));
        return (packed >> DEGEN_BONUS_BPS_SHIFT) & 0xFFFF;
    }

    function _betSlot(address who, uint64 betId) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(who, DEGENERETTE_BETS_SLOT));
        return keccak256(abi.encode(betId, inner));
    }

    function _betNonce(address who) internal view returns (uint64) {
        return uint64(
            uint256(
                vm.load(
                    address(game),
                    keccak256(abi.encode(who, DEGENERETTE_BET_NONCE_SLOT))
                )
            )
        );
    }

    function _placeEth(uint128 perSpin, uint8 spins) internal returns (uint64) {
        return _placeEthTicket(perSpin, spins, 0x00010203);
    }

    function _placeEthTicket(uint128 perSpin, uint8 spins, uint32 ticket)
        internal
        returns (uint64)
    {
        return _placeEthTicket(perSpin, spins, ticket, 0);
    }

    function _placeEthTicket(uint128 perSpin, uint8 spins, uint32 ticket, uint8 hero)
        internal
        returns (uint64)
    {
        vm.prank(player);
        game.placeDegeneretteBet{value: uint256(perSpin) * spins}(
            address(0), CURRENCY_ETH, perSpin, spins, ticket, hero
        );
        return _betNonce(player);
    }

    function _place(uint8 currency, uint128 perSpin, uint8 spins) internal returns (uint64) {
        vm.prank(player);
        game.placeDegeneretteBet(address(0), currency, perSpin, spins, 0x00010203, 0);
        return _betNonce(player);
    }

    function _winningTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        return _resultTicketForSpin(index, word, 0);
    }

    function _resultTicketForSpin(uint48 index, uint256 word, uint8 spinIdx)
        internal
        pure
        returns (uint32)
    {
        uint256 resultSeed = spinIdx == 0
            ? uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)))
            : uint256(keccak256(abi.encodePacked(word, uint32(index), spinIdx, QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev Build an all-gold (N=4) pick that scores EXACTLY S=2 against the spin-0 result:
    ///      the hero quadrant matches on symbol (+2) but not colour, and the other three
    ///      miss on symbol. Colour is gated behind symbol, so the three misses contribute
    ///      nothing. Every pick colour is gold (7), which selects the N4 payout table —
    ///      2.81x bet at S=2, the case that straddles the 3x tier boundary under a 50% bonus.
    ///      The hero is placed on a quadrant whose RESULT colour is not gold, so the hero's
    ///      colour cannot match and lift the score to 3.
    function _allGoldScoreTwoTicket(uint48 index, uint256 word)
        internal
        pure
        returns (uint32 ticket, uint8 hero)
    {
        uint32 result = _resultTicketForSpin(index, word, 0);

        hero = 4;
        for (uint8 q; q < 4; ++q) {
            if (((uint8(result >> (q * 8)) >> 3) & 7) != 7) {
                hero = q;
                break;
            }
        }
        // A result with all four quadrants gold is a 1-in-50k word; the fixtures here are
        // fixed constants, so this is a construction guard rather than a live branch.
        require(hero < 4, "no non-gold result quadrant for the hero");

        for (uint8 q; q < 4; ++q) {
            uint8 rSym = uint8(result >> (q * 8)) & 7;
            // Hero keeps the result's symbol (+2); the rest are shifted off it (miss).
            uint8 sym = q == hero ? rSym : uint8((rSym + 1) & 7);
            ticket |= uint32(uint8((uint8(7) << 3) | sym)) << uint32(q * 8);
        }
    }

    function _rawSumAndResolvedTotal()
        internal
        returns (uint256 rawSum, uint256 total, uint256 spinCount)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == RESULT_SIG) {
                (, , , uint256 payout) = abi.decode(
                    logs[i].data,
                    (uint8, uint32, uint8, uint256)
                );
                rawSum += payout;
                ++spinCount;
            } else if (logs[i].topics[0] == RESOLVED_SIG) {
                (, uint256 totalPayout, ) = abi.decode(
                    logs[i].data,
                    (uint8, uint256, uint32)
                );
                total = totalPayout;
            }
        }
    }

    function _injectRngWord(uint48 index, uint256 word) internal {
        vm.store(
            address(game),
            keccak256(abi.encode(index, LOOTBOX_RNG_WORD_SLOT)),
            bytes32(word)
        );
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
}
