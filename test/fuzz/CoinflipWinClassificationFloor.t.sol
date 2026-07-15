// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipWinClassificationFloor — every resolved WIN reads back as a win
/// @notice Pins the win-classification floor in Coinflip's 3-state packed day result.
///
///         processCoinflipPayouts stores, per resolved day, an 8-bit lane:
///           0      = unresolved
///           1      = resolved loss (sentinel)
///           50..156 = resolved win, holding that day's reward percent
///         _dayResult / getCoinflipDayResult derive `win = byte >= 50`. The contract
///         is only self-consistent if EVERY win stores a byte >= 50, i.e. the reward
///         percent of a win can never land in the misread band [2, 49].
///
///         Reward percent is set by `roll = seedWord % 20`:
///           roll == 0      -> 50   (fixed unlucky branch)
///           roll == 1      -> 150  (fixed lucky branch)
///           otherwise      -> (seedWord % 38) + 78  ∈ [78, 115]  (normal branch)
///         then a frozen day bonus of {0, 2, 6} (the only values the advance module
///         passes) is added. The minimum across all branches is the fixed-50 branch
///         with bonus 0 == 50, exactly the classification threshold; the maximum is
///         150 + 6 == 156 <= 255 (no byte overflow truncating a win into the band).
///
///         These tests drive REAL wins through processCoinflipPayouts across every
///         roll branch and bonus value, and assert getCoinflipDayResult(day).win is
///         true with rewardPercent >= 50 for each — so any mutation that lowers a
///         reward floor below 50 (or overflows 156 past 255) produces a win that
///         reads back as a loss, failing the readback assertion.
contract CoinflipWinClassificationFloor is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    // Mirror of the contract's private classification threshold and reward branches.
    // These are the values the live code MUST hold for win/loss readback to be sound.
    uint16 internal constant CLASSIFICATION_THRESHOLD = 50; // _dayResult: win = byte >= 50
    uint16 internal constant EXTRA_MIN_PERCENT = 78; // normal-branch floor
    uint16 internal constant EXTRA_RANGE = 38; // normal-branch span -> max 78+37 = 115
    uint16 internal constant FIXED_UNLUCKY = 50; // roll == 0
    uint16 internal constant FIXED_LUCKY = 150; // roll == 1
    uint8 internal constant MAX_DAY_BONUS = 6; // advance module passes {0, 2, 6}

    function setUp() public {
        _deployProtocol();
    }

    /// @dev Wall clock just inside GameTimeLib day `d` (matches CoinflipCarryClaim).
    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }

    /// @dev The reward roll inside processCoinflipPayouts: seedWord = keccak(rngWord, epoch),
    ///      roll = seedWord % 20. Mirrored so the test can target a specific branch.
    function _roll(uint256 rngWord, uint24 epoch) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(rngWord, epoch))) % 20;
    }

    /// @dev Find a WINNING word (low bit set, so `rngWord & 1 == 1`) whose reward roll
    ///      equals `targetRoll` at day `epoch`. Searches the high bits while keeping bit 0
    ///      set, so win/loss and the reward branch are pinned independently.
    function _winningWordForRoll(uint24 epoch, uint256 targetRoll)
        internal
        pure
        returns (uint256 word)
    {
        for (uint256 i = 0; i < 100_000; i++) {
            uint256 candidate = (i << 1) | 1; // odd => win
            if (_roll(candidate, epoch) == targetRoll) {
                return candidate;
            }
        }
        revert("no winning word found for target roll");
    }

    /// @dev Resolve `epoch` as the GAME with the given win word and day bonus, with the
    ///      wall clock at `epoch` (production timing). Returns the readback.
    function _resolveWinAndRead(uint24 epoch, uint256 word, uint8 bonus)
        internal
        returns (uint16 rewardPercent, bool win)
    {
        _warpToDay(epoch);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(bonus, word, epoch);
        (rewardPercent, win) = coinflip.getCoinflipDayResult(epoch);
    }

    /// @notice Structural floor: every reward branch (and the classification threshold)
    ///         keeps a win's stored byte at or above the win threshold, and the maximum
    ///         possible byte never overflows uint8 (which would truncate a win below 50).
    function test_RewardFloorsNeverEnterMisreadBand() public pure {
        // The classification threshold must stay at the win floor it was designed for:
        // if it rose above 50, fixed-50 wins would misread as losses; the rest of the
        // suite pins it from the live side, this documents the constant it targets.
        assertEq(CLASSIFICATION_THRESHOLD, 50, "win threshold is 50");

        // Every branch's MINIMUM win byte (bonus 0) is >= the classification threshold,
        // so no win can store a byte in the misread band [2, 49].
        assertGe(FIXED_UNLUCKY, CLASSIFICATION_THRESHOLD, "roll==0 branch (50) >= 50");
        assertGe(FIXED_LUCKY, CLASSIFICATION_THRESHOLD, "roll==1 branch (150) >= 50");
        assertGe(EXTRA_MIN_PERCENT, CLASSIFICATION_THRESHOLD, "normal floor (78) >= 50");

        // The maximum possible stored byte is the lucky branch plus the largest day
        // bonus; it must fit in a uint8 lane, else a high win would wrap below 50.
        uint256 maxByte = uint256(FIXED_LUCKY) + uint256(MAX_DAY_BONUS); // 156
        assertLe(maxByte, 255, "max win byte 156 fits uint8 lane (no overflow)");

        // The normal branch's maximum (78 + 37) also stays a valid in-band win.
        uint256 normalMax = uint256(EXTRA_MIN_PERCENT) + (EXTRA_RANGE - 1); // 115
        assertGe(normalMax, CLASSIFICATION_THRESHOLD, "normal max (115) >= 50");
        assertLe(uint256(normalMax) + MAX_DAY_BONUS, 255, "normal max + bonus fits uint8");
    }

    /// @notice Behavioral: a real win on the FIXED-UNLUCKY branch (roll==0, reward 50,
    ///         no bonus) — the tightest case, exactly at the threshold — reads back as a
    ///         WIN. A mutant that lowered the 50 branch or raised the threshold misreads
    ///         this win as a loss.
    function test_FixedUnluckyWinReadsAsWin() public {
        uint24 epoch = 3;
        uint256 word = _winningWordForRoll(epoch, 0);
        (uint16 r, bool win) = _resolveWinAndRead(epoch, word, 0);
        assertTrue(win, "roll==0 win classified as a win");
        assertEq(r, 50, "roll==0 stores exactly 50");
        assertGe(r, CLASSIFICATION_THRESHOLD, "stored byte stays at/above the win floor");
    }

    /// @notice Behavioral: a real win on the FIXED-LUCKY branch (roll==1, reward 150)
    ///         with the maximum day bonus (+6) — the largest possible stored byte (156) —
    ///         reads back as a WIN and does not overflow the uint8 lane into the band.
    function test_FixedLuckyWinWithMaxBonusReadsAsWin() public {
        uint24 epoch = 4;
        uint256 word = _winningWordForRoll(epoch, 1);
        (uint16 r, bool win) = _resolveWinAndRead(epoch, word, MAX_DAY_BONUS);
        assertTrue(win, "roll==1 win classified as a win");
        assertEq(r, 156, "roll==1 + bonus 6 stores 156 (no overflow)");
        assertGe(r, CLASSIFICATION_THRESHOLD, "max win byte stays above the win floor");
    }

    /// @notice Behavioral: a real win on the NORMAL branch (roll in [2,19], reward in
    ///         [78,115]) reads back as a WIN at or above the floor. Drives several
    ///         distinct normal rolls so the [78,115] span is exercised, not a single point.
    function test_NormalBranchWinsReadAsWin() public {
        // roll values 2,5,9,15,19 are all in the normal branch; each lands a winning
        // word with a reward in [78,115] + bonus, and must classify as a win.
        uint256[5] memory rolls = [uint256(2), 5, 9, 15, 19];
        for (uint256 i = 0; i < rolls.length; i++) {
            uint24 epoch = uint24(10 + i);
            uint256 word = _winningWordForRoll(epoch, rolls[i]);
            // alternate bonus across {0, 2, 6} to exercise the bonus add on this branch
            uint8 bonus = uint8([uint256(0), 2, 6][i % 3]);
            (uint16 r, bool win) = _resolveWinAndRead(epoch, word, bonus);
            assertTrue(win, "normal-branch win classified as a win");
            assertGe(r, EXTRA_MIN_PERCENT, "normal reward at/above its floor (78)");
            assertLe(r, uint16(EXTRA_MIN_PERCENT + (EXTRA_RANGE - 1) + MAX_DAY_BONUS), "normal reward within [78,121]");
            assertGe(r, CLASSIFICATION_THRESHOLD, "normal-branch win stays above the win floor");
        }
    }

    /// @notice Cross-check: a real LOSS stores the sentinel and reads back as a loss with
    ///         a sub-threshold byte, confirming the band below 50 means loss (so the win
    ///         assertions above are the meaningful half of the classification).
    function test_LossReadsAsLossBelowThreshold() public {
        uint24 epoch = 20;
        // Even word => bit 0 clear => loss; roll branch is irrelevant for a loss.
        uint256 word = uint256(keccak256(abi.encodePacked("loss_word", epoch))) & ~uint256(1);
        (uint16 r, bool win) = _resolveWinAndRead(epoch, word, 0);
        assertFalse(win, "even-word day is a loss");
        assertLt(r, CLASSIFICATION_THRESHOLD, "loss sentinel sits below the win floor");
        assertEq(r, 1, "loss stores the sentinel byte 1");
    }
}
