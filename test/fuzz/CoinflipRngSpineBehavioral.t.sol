// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CoinflipRngSpineBehavioral — MECH-03 RNG-spine behavioral net
///
/// @notice The pre-existing attestation
///         `RngFreezeAndRemovalProofs.t.sol::testWinLossRngPathByteUnmodified` is a
///         SOURCE-STRING occurrence count (`vm.readFile` + count of
///         `"bool win = (rngWord & 1) == 1;"`). It is blind to: a callsite arg swap
///         (e.g. `(seedWord & 1)` instead of `(rngWord & 1)`); a perturbation of the
///         reward path `seedWord = keccak(rngWord, epoch)` / `roll = seedWord % 20`; and
///         the `_storeDayResult` / `_dayResult` `>= 50` win-packing threshold.
///
///         This suite is the BEHAVIORAL complement: it drives the live
///         `processCoinflipPayouts` with a known `rngWord` and pins the resolved
///         day-result as a PURE FUNCTION of the frozen `(bonus, rngWord, epoch)` triple,
///         reconstructed by an in-test mirror of the contract's exact arithmetic:
///
///           win        = (rngWord & 1) == 1                       (50/50 roll, bit 0)
///           seedWord   = keccak256(abi.encodePacked(rngWord, epoch))
///           roll       = seedWord % 20
///           reward     = roll==0 ? 50 : roll==1 ? 150 : (seedWord % 38) + 78
///           reward    += bonus                                    (unchecked add)
///           storedByte = win ? reward : 1                         (loss sentinel = 1)
///           readback   = (rewardPercent == storedByte, win == storedByte >= 50)
///
///         Each assertion pins the EXACT value the correct code produces, so a mutant
///         that swaps the win-bit source, alters the seedWord keccak/epoch mix, shifts
///         the `% 20` roll selection, or moves the `>= 50` packing threshold yields a
///         different value and FAILS the readback.
///
/// @dev Full gambit mutation campaign on processCoinflipPayouts / _storeDayResult /
///      _dayResult remains CI-resumable (v63/v64 precedent — not run inline here).
contract CoinflipRngSpineBehavioral is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    // Mirror of the contract's private reward branches (Coinflip.sol:145-148, :859-886).
    uint16 internal constant EXTRA_MIN_PERCENT = 78;
    uint16 internal constant EXTRA_RANGE = 38;
    uint16 internal constant FIXED_UNLUCKY = 50; // roll == 0
    uint16 internal constant FIXED_LUCKY = 150; // roll == 1
    uint16 internal constant WIN_THRESHOLD = 50; // _dayResult: win = byte >= 50

    function setUp() public {
        _deployProtocol();
    }

    // =====================================================================
    // In-test mirror of the day-result as a PURE FUNCTION of (bonus, rngWord, epoch).
    // This is the oracle the live contract is asserted against. It threads the SAME
    // inputs through the SAME arithmetic, so a divergence between mirror and live can
    // only come from the live code having been mutated off the spine.
    // =====================================================================

    /// @dev Reconstruct the day's reward percent purely from the frozen inputs.
    function _expectedReward(uint8 bonus, uint256 rngWord, uint24 epoch)
        internal
        pure
        returns (uint16 reward)
    {
        uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));
        uint256 roll = seedWord % 20;
        if (roll == 0) {
            reward = FIXED_UNLUCKY;
        } else if (roll == 1) {
            reward = FIXED_LUCKY;
        } else {
            reward = uint16((seedWord % EXTRA_RANGE) + EXTRA_MIN_PERCENT);
        }
        unchecked {
            reward += bonus;
        }
    }

    /// @dev The win bit is the LOW bit of the raw rngWord (NOT of the keccak-mixed seedWord).
    function _expectedWin(uint256 rngWord) internal pure returns (bool) {
        return (rngWord & 1) == 1;
    }

    /// @dev Stored 8-bit lane: a win banks its reward (>= 50); a loss banks the sentinel 1.
    function _expectedStoredByte(uint8 bonus, uint256 rngWord, uint24 epoch)
        internal
        pure
        returns (uint16)
    {
        if (!_expectedWin(rngWord)) return 1;
        return _expectedReward(bonus, rngWord, epoch);
    }

    /// @dev Resolve `epoch` as the GAME with `(bonus, word)`, then read back the packed result.
    function _resolveAndRead(uint8 bonus, uint256 word, uint24 epoch)
        internal
        returns (uint16 rewardPercent, bool win)
    {
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(bonus, word, epoch);
        (rewardPercent, win) = coinflip.getCoinflipDayResult(epoch);
    }

    // =====================================================================
    // MECH-03 — day-result is the pure function of the frozen daily word.
    // =====================================================================

    /// @notice Behavioral: across every reward-roll branch and every day-bonus the advance
    ///         module emits ({0, 2, 6}), the live stored/reconstructed result equals the
    ///         pure-function mirror EXACTLY — both the win bit (= rngWord & 1) and the
    ///         reward byte (= keccak(rngWord, epoch)-derived). A callsite arg swap, a
    ///         seedWord/epoch mix change, or a roll-threshold shift diverges from the
    ///         mirror and fails here.
    function testDayResultIsPureFunctionOfWord() public {
        uint8[3] memory bonuses = [0, 2, 6];
        // Pin a different roll branch per case via crafted words (win bit set), so the
        // 50-branch, 150-branch and normal [78,115] branch are all exercised live.
        for (uint256 b = 0; b < bonuses.length; b++) {
            uint8 bonus = bonuses[b];
            // roll == 0 branch (reward 50, the threshold floor)
            _assertMatchesMirror(bonus, _wordForRoll(uint24(30 + b), 0, true), uint24(30 + b));
            // roll == 1 branch (reward 150)
            _assertMatchesMirror(bonus, _wordForRoll(uint24(40 + b), 1, true), uint24(40 + b));
            // normal branch (a representative non-0/1 roll)
            _assertMatchesMirror(bonus, _wordForRoll(uint24(50 + b), 7, true), uint24(50 + b));
            // a loss in each bonus class (win bit clear -> sentinel)
            _assertMatchesMirror(bonus, _wordForRoll(uint24(60 + b), 7, false), uint24(60 + b));
        }
    }

    /// @notice The win bit is sourced from the RAW rngWord, NOT the keccak-mixed seedWord.
    ///         Drives a word whose rngWord low bit and seedWord low bit DISAGREE in each
    ///         direction, and asserts the live win classification follows rngWord&1. A
    ///         mutant reading `(seedWord & 1)` (the most natural arg-swap a string test
    ///         cannot see) classifies these days oppositely and fails.
    function testWinBitFollowsRawWordNotSeedWord() public {
        // Case A: rngWord&1 == 1 (win) but seedWord&1 == 0 — only the raw-word reading wins.
        uint24 epochA = 70;
        uint256 wordA = _wordWithBitDisagreement(epochA, true);
        (uint16 rA, bool winA) = _resolveAndRead(0, wordA, epochA);
        assertTrue(winA, "rngWord&1==1 -> WIN even though seedWord&1==0 (win bit is raw word)");
        assertGe(rA, WIN_THRESHOLD, "win banks reward >= threshold");
        assertEq(rA, _expectedStoredByte(0, wordA, epochA), "win byte == pure-function mirror");

        // Case B: rngWord&1 == 0 (loss) but seedWord&1 == 1 — only the raw-word reading loses.
        uint24 epochB = 71;
        uint256 wordB = _wordWithBitDisagreement(epochB, false);
        (uint16 rB, bool winB) = _resolveAndRead(0, wordB, epochB);
        assertFalse(winB, "rngWord&1==0 -> LOSS even though seedWord&1==1 (win bit is raw word)");
        assertEq(rB, 1, "loss banks the sentinel byte 1");
    }

    /// @notice The reward byte is keyed to `keccak(rngWord, epoch)`: the SAME rngWord at
    ///         DIFFERENT epochs yields DIFFERENT reward rolls (epoch is mixed into the
    ///         seed). Pins the seedWord = keccak(rngWord, epoch) path against a mutant
    ///         that drops or alters the epoch term. Each resolved byte still equals its
    ///         own pure-function mirror.
    function testRewardDependsOnEpochThroughSeedMix() public {
        // A fixed winning raw word; vary only the epoch.
        uint256 word = (uint256(keccak256("mech03_fixed_raw_word")) | 1);
        uint16[6] memory live;
        uint24[6] memory epochs = [uint24(80), 81, 82, 83, 84, 85];
        for (uint256 i = 0; i < epochs.length; i++) {
            (uint16 r, bool won) = _resolveAndRead(0, word, epochs[i]);
            assertTrue(won, "fixed odd word is a win at every epoch (bit 0 set)");
            assertEq(
                r,
                _expectedStoredByte(0, word, epochs[i]),
                "reward byte == keccak(rngWord, epoch) mirror at this epoch"
            );
            live[i] = r;
        }
        // The epoch term must actually move the reward: with the epoch dropped from the
        // seed, every byte would be identical. Assert at least two epochs differ.
        bool anyDiffer;
        for (uint256 i = 1; i < epochs.length; i++) {
            if (live[i] != live[0]) anyDiffer = true;
        }
        assertTrue(anyDiffer, "epoch is mixed into the reward seed (rewards are not epoch-constant)");
    }

    /// @notice The resolved day-result is INDEPENDENT of player-controllable state. A
    ///         player mints and changes game state (level mint streak, balances) BETWEEN
    ///         two otherwise-identical resolutions on twin epochs; the live result still
    ///         equals the pure-function mirror, unchanged by the player's actions. The
    ///         only inputs that move the result are the frozen (bonus, rngWord, epoch).
    function testDayResultIndependentOfPlayerControllableState() public {
        // Pre-state resolution: a clean epoch resolved against the mirror.
        uint24 epoch1 = 90;
        uint256 word = _wordForRoll(epoch1, 7, true);
        (uint16 rBefore, bool winBefore) = _resolveAndRead(0, word, epoch1);
        assertEq(rBefore, _expectedStoredByte(0, word, epoch1), "pre-action byte == mirror");
        assertTrue(winBefore, "pre-action win");

        // A player mutates protocol state through the public API: a real mint moves the
        // player's balances, mint-streak and the day's purchase accounting.
        address player = makeAddr("mech03_player");
        vm.deal(player, 100 ether);
        vm.prank(player);
        game.purchase{value: 10 ether}(
            player,
            400,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth, false
        );

        // Post-action resolution: the SAME (bonus, rngWord-derived roll) on a twin epoch
        // crafted to hit the SAME roll branch and reward. The reward of a given roll is a
        // pure function of seedWord, so a word giving the same seedWord roll on a fresh
        // epoch reproduces the byte. Independence: the player's state change did not move
        // the resolved result off its mirror prediction.
        uint24 epoch2 = 91;
        uint256 word2 = _wordForExactReward(epoch2, _expectedReward(0, word, epoch1), true);
        (uint16 rAfter, bool winAfter) = _resolveAndRead(0, word2, epoch2);
        assertEq(rAfter, _expectedStoredByte(0, word2, epoch2), "post-action byte == mirror");
        assertTrue(winAfter, "post-action win");
        assertEq(
            rAfter,
            rBefore,
            "identical reward across a player-state mutation (result independent of player-controllable state)"
        );
    }

    // =====================================================================
    // Internal helpers — word search + the per-case mirror assertion.
    // =====================================================================

    /// @dev Assert the live resolved result for `(bonus, word, epoch)` matches the mirror
    ///      EXACTLY on both legs (reward byte + win bit).
    function _assertMatchesMirror(uint8 bonus, uint256 word, uint24 epoch) internal {
        (uint16 rLive, bool winLive) = _resolveAndRead(bonus, word, epoch);
        assertEq(
            rLive,
            _expectedStoredByte(bonus, word, epoch),
            "live reward byte == pure-function mirror"
        );
        assertEq(
            winLive,
            _expectedWin(word),
            "live win bit == (rngWord & 1) (pure-function mirror)"
        );
        // The packing threshold is pinned by the cross-check: a win reads >= 50, a loss < 50.
        if (winLive) {
            assertGe(rLive, WIN_THRESHOLD, "win banks a byte >= the 50 packing threshold");
        } else {
            assertLt(rLive, WIN_THRESHOLD, "loss banks the sub-threshold sentinel");
        }
    }

    /// @dev The reward roll the contract computes: roll = keccak(rngWord, epoch) % 20.
    function _rollOf(uint256 rngWord, uint24 epoch) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(rngWord, epoch))) % 20;
    }

    /// @dev Find a word at `epoch` whose reward roll equals `targetRoll`, with the win bit
    ///      set to `win`. The low bit pins win/loss; the high bits are searched so the
    ///      roll branch is selected independently of the win bit.
    function _wordForRoll(uint24 epoch, uint256 targetRoll, bool win)
        internal
        pure
        returns (uint256 word)
    {
        for (uint256 i = 0; i < 200_000; i++) {
            uint256 candidate = (i << 1) | (win ? 1 : 0);
            if (_rollOf(candidate, epoch) == targetRoll) {
                return candidate;
            }
        }
        revert("no word found for target roll");
    }

    /// @dev Find a WINNING word at `epoch` (low bit set) whose full reconstructed reward
    ///      (no bonus) equals `targetReward`. Used to reproduce an exact byte on a fresh
    ///      epoch despite the epoch being mixed into the seed.
    function _wordForExactReward(uint24 epoch, uint16 targetReward, bool win)
        internal
        pure
        returns (uint256 word)
    {
        for (uint256 i = 0; i < 400_000; i++) {
            uint256 candidate = (i << 1) | (win ? 1 : 0);
            if (_expectedReward(0, candidate, epoch) == targetReward) {
                return candidate;
            }
        }
        revert("no word found for target reward");
    }

    /// @dev Find a word at `epoch` where the RAW low bit and the SEEDWORD low bit DISAGREE:
    ///      - rawWins == true  : rngWord&1 == 1 AND seedWord&1 == 0 (raw says win, seed says loss)
    ///      - rawWins == false : rngWord&1 == 0 AND seedWord&1 == 1 (raw says loss, seed says win)
    ///      This isolates the win-bit SOURCE so a `(seedWord & 1)` arg-swap mutant diverges.
    function _wordWithBitDisagreement(uint24 epoch, bool rawWins)
        internal
        pure
        returns (uint256 word)
    {
        for (uint256 i = 0; i < 200_000; i++) {
            uint256 candidate = (i << 1) | (rawWins ? 1 : 0);
            uint256 seedLow = uint256(keccak256(abi.encodePacked(candidate, epoch))) & 1;
            // raw low bit is (rawWins ? 1 : 0); require seed low bit to be the OPPOSITE.
            if (seedLow == (rawWins ? 0 : 1)) {
                return candidate;
            }
        }
        revert("no bit-disagreement word found");
    }
}
