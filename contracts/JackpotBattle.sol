// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {JackpotBattleFieldLib} from "./libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

/// @title JackpotBattle
/// @notice The daily jackpot battle: a closed craps field the game writes, played out
///         and ranked in the call that draws it.
/// @dev Holds no storage and has no owner. The game hands it the draw's wallets, saved boards and entry counts, the draw's FLIP
///      budget and the day's word; it plays every run in memory and returns what each wallet is
///      owed, which the game credits in one batch. Nothing is staked, seated or stored, so there
///      is nothing to settle later and no door for anyone else to enter by — the field and the
///      pot are fixed before the word exists, which makes the whole battle a jackpot result.
///
///      THE FORMAT. Two thirds of the budget are the entrants' stakes and the pot is everything
///      else: the remaining third plus whatever the 300-FLIP bankroll floor leaves unstaked.
///      Every unit of
///      stake is one equal bankroll, a whole multiple of 300 FLIP; a wallet drawn more than once holds that many units
///      but still plays ONE run on one unit's bankroll, and the units multiply only what that run
///      pays. The field plays as a scheduled window's seats do: one set of dice for everyone,
///      each wallet's saved board and scatter, the scheduled boost for its named-chip count, and the rotating
///      shooter passed seat by seat in first-drawn order. Each run plays the scheduled Dice Run
///      shape — a bankroll five rounds deep, up to seven saved chips plus random chips to ten, a goal at five
///      times the bankroll that latches as a protected reserve — at most `_ROLL_CAP` rolls and
///      `_HAND_CAP` shooters.
///      A run that busts pays nothing; one that reaches either cap or
///      latches the goal pays the bankroll it stopped on, per unit. The pot goes whole to the paid run with the highest
///      ending bankroll, the earlier-drawn wallet on a tie; with no paid run it is not minted.
///      One independently salted roll multiplies every run payout and the pot: 90% at 0.5x,
///      9% at 3x, 0.9% at 20x and 0.1% at 100x (mean 1x). It does not change the field,
///      bankrolls, dice, ranking or jackpot scores. The multiplied awards then land on the protocol's award figures: the
///      whole-FLIP floor up to `FLIP_ROUND_THRESHOLD`, the expectation-preserving 100-FLIP
///      granule above it, keyed per wallet off the word.
///
///      THE GAS. `_ROLL_CAP` is under one hand's `_MAX_ROLLS`, which makes it exact (see
///      `_settleSlip`): the last hand is cut where the cap runs out and refunds what is still
///      live. So the dice work is bounded by entrants x (`_HAND_CAP` hands + `_ROLL_CAP` rolls)
///      however they fall: a tested 7.475M gas allowance for a full field at both caps (test/craps/JackpotBattle.t.sol).
contract JackpotBattle is Craps {
    /// @notice Thrown when anyone but the game calls `resolve`.
    error OnlyGame();

    /// @notice One wallet's run.
    /// @param level       The highest minted level when the battle's day drew it (the purchase
    ///                    level on a purchase day, level + 1 on a jackpot day); the field comes
    ///                    from the unminted levels above it.
    /// @param player      The wallet.
    /// @param units       Times the draw picked it; what its run pays is multiplied by this.
    /// @param bankrollOut What the run stopped on, per unit, before any bust is voided.
    /// @param rolls       Dice rolls the run took.
    /// @param paid        FLIP owed for the run, all units and the draw multiplier, excluding the pot.
    /// @param chips       Saved board actually played, in the canonical paid-entry encoding.
    event JackpotBattleRun(
        uint24 indexed level,
        address indexed player,
        uint256 units,
        uint256 bankrollOut,
        uint256 rolls,
        uint256 paid,
        uint32 chips
    );

    /// @notice The pot's winner.
    /// @param level  The highest minted level when the day drew it (see `JackpotBattleRun`).
    /// @param winner The paid run with the highest ending bankroll.
    /// @param pot    FLIP owed on top of its run.
    event JackpotBattlePot(uint24 indexed level, address indexed winner, uint256 pot);

    /// @notice The draw-wide payout multiplier, applied before award rounding.
    /// @param baseBudget    Unmultiplied budget used to size the field, bankrolls and base pot.
    /// @param multiplierBps 5,000, 30,000, 200,000 or 1,000,000; does not multiply RIU/record awards.
    event JackpotBattleMultiplier(uint24 indexed level, uint256 baseBudget, uint256 multiplierBps);

    /// @dev Separate domains for dice, scatter, rounding and the draw-wide payout multiplier.
    uint256 private constant JACKPOT_BATTLE_DICE_TAG = 0x436f696e4472617744696365; // "CoinDrawDice"
    uint256 private constant JACKPOT_BATTLE_SCATTER_TAG = 0x436f696e4472617753636174746572; // "CoinDrawScatter"
    uint256 private constant JACKPOT_BATTLE_ROUND_TAG = 0x436f696e44726177526f756e64; // "CoinDrawRound"
    uint256 private constant JACKPOT_BATTLE_MULTIPLIER_TAG = 0x436f696e447261774d756c7469706c696572; // "CoinDrawMultiplier"

    /// @notice Most dice rolls one run may take. Exact, being under `_MAX_ROLLS`.
    uint256 internal constant _ROLL_CAP = 200;

    /// @notice Most shooters one run may play: 0.01% of 200,000 runs simulated under these terms
    ///         reach it, the longest at 24. It exists to prove the dice work, not to shape play;
    ///         a run it stops pays the bankroll it holds, as the roll cap's does.
    uint256 internal constant _HAND_CAP = 22;

    /// @notice The bankroll granule and the smallest per-unit bankroll: every run starts on a
    ///         whole multiple of 300 FLIP, as every scheduled table does, so its board is a
    ///         multiple of 60 and its chip a multiple of 6 (the place 6/8 7:6 payout lands exact).
    ///         A budget too small to give every drawn unit 300 plays fewer units, from the front.
    uint256 internal constant _BANKROLL_UNIT = JackpotBattleFieldLib.BANKROLL_UNIT;

    /// @notice The scheduled Dice Run shape: rounds of depth, goal multiple, chips per board.
    uint256 internal constant _DEPTH = 5;
    uint256 internal constant _GOAL_MULT = 5;
    uint256 internal constant _CHIPS = 10;

    /// @dev The widest chip whose ten-chip leg still fits a board leg's uint24, kept a multiple of
    ///      6 so a clamped bankroll stays a multiple of 300.
    uint256 private constant _MAX_CHIP = (type(uint24).max / _CHIPS / 6) * 6;

    /// @notice Play the battle and return what each wallet is owed.
    /// @param level    The highest minted level when the day drew the battle, carried onto the events.
    /// @param entrants Unique wallets in first-drawn order, packed with boards and units by JackpotBattleFieldLib.
    /// @param amount   The draw's whole FLIP budget, in wei: two thirds stakes, the rest the pot.
    /// @param word     The day's word.
    /// @return players Each distinct wallet, first-drawn order.
    /// @return owed    FLIP to credit each, pot included; zero for a bust.
    /// @return jackpotWinner The pot winner, also the sole RIU/record candidate.
    /// @return peakFlip That winner's completed-shooter high point in whole FLIP; zero unless Goal latched.
    /// @return score   High point over one unit's starting bankroll, in basis points. Extra units do not multiply it.
    function resolve(uint24 level, uint256[] calldata entrants, uint256 amount, uint256 word)
        external
        returns (address[] memory players, uint256[] memory owed, address jackpotWinner, uint256 peakFlip, uint256 score)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        uint256 stakes = (amount * 2) / 3;
        uint256 n = entrants.length;
        if (n == 0) return (players, owed, address(0), 0, 0);
        uint256 multiplierBps = _multiplierBps(_hash2(word, JACKPOT_BATTLE_MULTIPLIER_TAG));
        emit JackpotBattleMultiplier(level, amount, multiplierBps);
        players = new address[](n);
        owed = new uint256[](n);
        uint256 units;
        for (uint256 j; j < n; ++j) units += entrants[j] >> JackpotBattleFieldLib.UNITS_SHIFT;

        // Each unit's share floored to a whole multiple of 300 FLIP, then the chip is exactly a
        // fiftieth of it (`_DEPTH` boards of `_CHIPS` chips), so every budget plays the same shape;
        // what the floor leaves of a unit's share joins the pot.
        uint256 chipFlip = (stakes / units / _BANKROLL_UNIT) * (_BANKROLL_UNIT / (_DEPTH * _CHIPS * 1 ether));
        if (chipFlip > _MAX_CHIP) chipFlip = _MAX_CHIP;
        uint256 bankroll = chipFlip * (_DEPTH * _CHIPS * 1 ether);
        bytes32 dice = bytes32(_hash2(word, JACKPOT_BATTLE_DICE_TAG));
        // THE ROTATING SHOOTER, as a scheduled window draws it: one start for the field off the
        // shared seed, then seat by seat in first-drawn order, wrapping at the distinct count. A
        // turn past `_HAND_CAP` is never reached.
        uint256 start = _hash2(ROTATING_SHOOTER_TAG, uint256(dice)) % n;
        uint256 best;
        uint256 winner = type(uint256).max;
        uint256 scratch;
        assembly ("memory-safe") { scratch := mload(0x40) }
        for (uint256 j; j < n; ) {
            // Only scalar results escape a run. Keep the output arrays below this pointer,
            // and reuse the board/engine workspace instead of growing it for all 50 wallets.
            assembly ("memory-safe") { mstore(0x40, scratch) }
            uint256 entry = entrants[j];
            address p = address(uint160(entry));
            players[j] = p;
            // Align the caller-supplied compact board with the shared storage codec.
            (uint32 chips, uint256 placed) = CrapsPreferenceLib.decode(
                entry >> (JackpotBattleFieldLib.BOARD_SHIFT - CrapsPreferenceLib.SHIFT)
            );
            Bets memory b;
            if (chips != 0) b = _boardFrom(chips, chipFlip);
            _scatterInto(b, _hash3(word, JACKPOT_BATTLE_SCATTER_TAG, uint160(p)), chipFlip, _CHIPS - placed);
            uint256 turn;
            unchecked {
                turn = (j + n - start) % n + 1;
            }
            SlipResult memory r = _settleSlip(
                b,
                dice,
                bankroll,
                bankroll * _GOAL_MULT,
                _HAND_CAP,
                _ROLL_CAP,
                p,
                _shooterBoostTerms(placed) | (turn << _BOOST_TURN_SHIFT)
            );
            // A cap is checked before affordability, so reaching either one means the run was
            // stopped holding its bankroll, never busted; the engine reports it as a bust only
            // because it came before the goal.
            uint256 out = r.stop == SlipStop.Goal || r.totalRolls >= _ROLL_CAP || r.handsPlayed == _HAND_CAP
                ? r.bankrollOut
                : 0;
            if (out > best) {
                best = out;
                winner = j;
                peakFlip = r.stop == SlipStop.Goal ? r.peakBankroll / 1 ether : 0;
            }
            uint256 pay;
            unchecked {
                pay = out * (entry >> JackpotBattleFieldLib.UNITS_SHIFT);
            }
            pay = _award(pay * multiplierBps / 10_000, _hash3(word, JACKPOT_BATTLE_ROUND_TAG, uint160(p)));
            owed[j] = pay;
            emit JackpotBattleRun(level, p, entry >> JackpotBattleFieldLib.UNITS_SHIFT, r.bankrollOut, r.totalRolls, pay, chips);
            unchecked { ++j; }
        }
        if (winner != type(uint256).max) {
            uint256 pot = _award((amount - bankroll * units) * multiplierBps / 10_000, _hash2(word, JACKPOT_BATTLE_ROUND_TAG));
            owed[winner] += pot;
            jackpotWinner = players[winner];
            score = (peakFlip * 10_000) / (bankroll / 1 ether);
            emit JackpotBattlePot(level, jackpotWinner, pot);
        }
    }

    /// @dev 900 half-size, 90 triple, nine 20x and one 100x bucket per thousand. Mean = 1x.
    function _multiplierBps(uint256 entropy) internal pure returns (uint256) {
        uint256 roll = entropy % 1_000;
        if (roll < 900) return 5_000;
        if (roll < 990) return 30_000;
        if (roll < 999) return 200_000;
        return 1_000_000;
    }

    /// @dev The protocol's two-band award figure (as CrapsBattle settles a slip): the 100-FLIP
    ///      granule, expectation-preserving, once it is a small slice of the award; the whole-FLIP
    ///      floor at or below `FLIP_ROUND_THRESHOLD`.
    function _award(uint256 amount, uint256 entropy) private pure returns (uint256) {
        return amount > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(amount, entropy)
            : FlipRoundLib.floorWholeFlip(amount);
    }
}
