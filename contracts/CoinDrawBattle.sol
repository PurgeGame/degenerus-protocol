// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

/// @title CoinDrawBattle
/// @notice The daily fill draw's craps battle: a closed field the game writes, played out
///         and ranked in the call that draws it.
/// @dev Holds no storage and has no owner. The game hands it the draw's wallets, the draw's FLIP
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
///      each wallet's own scattered board, the house's shooter-profit boost, and the rotating
///      shooter passed seat by seat in first-drawn order. Each run plays the scheduled Dice Run
///      shape — a bankroll five rounds deep, all ten chips thrown by the dice, a goal at five
///      times the bankroll that latches as a protected reserve — at most `_ROLL_CAP` rolls and
///      `_HAND_CAP` shooters.
///      A run that busts pays nothing; one that reaches either cap or
///      latches the goal pays the bankroll it stopped on, per unit. The pot goes whole to the paid run with the highest
///      ending bankroll, the earlier-drawn wallet on a tie; with no paid run it is not minted.
///      Each wallet's run payout and the pot land on the protocol's award figures: the
///      whole-FLIP floor up to `FLIP_ROUND_THRESHOLD`, the expectation-preserving 100-FLIP
///      granule above it, keyed per wallet off the word.
///
///      THE GAS. `_ROLL_CAP` is under one hand's `_MAX_ROLLS`, which makes it exact (see
///      `_settleSlip`): the last hand is cut where the cap runs out and refunds what is still
///      live. So the dice work is bounded by entrants x (`_HAND_CAP` hands + `_ROLL_CAP` rolls)
///      however they fall: 7.475M for a full field at both caps (test/craps/CoinDrawBattle.t.sol).
contract CoinDrawBattle is Craps {
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
    /// @param paid        FLIP owed for the run, all units, excluding the pot.
    event CoinDrawBattleRun(
        uint24 indexed level,
        address indexed player,
        uint256 units,
        uint256 bankrollOut,
        uint256 rolls,
        uint256 paid
    );

    /// @notice The pot's winner.
    /// @param level  The highest minted level when the day drew it (see `CoinDrawBattleRun`).
    /// @param winner The paid run with the highest ending bankroll.
    /// @param pot    FLIP owed on top of its run.
    event CoinDrawBattlePot(uint24 indexed level, address indexed winner, uint256 pot);

    /// @dev Domain tags for the field's shared dice and each wallet's board scatter off the day's word.
    uint256 private constant COIN_DRAW_DICE_TAG = 0x436f696e4472617744696365; // "CoinDrawDice"
    uint256 private constant COIN_DRAW_SCATTER_TAG = 0x436f696e4472617753636174746572; // "CoinDrawScatter"
    uint256 private constant COIN_DRAW_ROUND_TAG = 0x436f696e44726177526f756e64; // "CoinDrawRound"

    /// @notice The shooter-profit boost every run plays: `CrapsBattle._shooterBoostTerms(0)`, the
    ///         scheduled row for a board the dice threw whole — 15% of shooters eligible, +32% on
    ///         an eligible shooter's profit. The seat's rotation turn rides above it.
    uint256 internal constant _BOOST_TERMS = 0x200F;

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
    uint256 internal constant _BANKROLL_UNIT = 300 ether;

    /// @notice The scheduled Dice Run shape: rounds of depth, goal multiple, chips per board.
    uint256 internal constant _DEPTH = 5;
    uint256 internal constant _GOAL_MULT = 5;
    uint256 internal constant _CHIPS = 10;

    /// @dev The widest chip whose ten-chip leg still fits a board leg's uint24, kept a multiple of
    ///      6 so a clamped bankroll stays a multiple of 300.
    uint256 private constant _MAX_CHIP = (type(uint24).max / _CHIPS / 6) * 6;

    /// @notice Play the battle and return what each wallet is owed.
    /// @param level    The highest minted level when the day drew the battle, carried onto the events.
    /// @param entrants The draw's wallets in draw order; repeats are extra units.
    /// @param amount   The draw's whole FLIP budget, in wei: two thirds stakes, the rest the pot.
    /// @param word     The day's word.
    /// @return players Each distinct wallet, first-drawn order.
    /// @return owed    FLIP to credit each, pot included; zero for a bust.
    function resolve(uint24 level, address[] calldata entrants, uint256 amount, uint256 word)
        external
        returns (address[] memory players, uint256[] memory owed)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        uint256 stakes = (amount * 2) / 3;
        uint256 units = entrants.length;
        if (units > stakes / _BANKROLL_UNIT) units = stakes / _BANKROLL_UNIT;
        if (units == 0) return (players, owed);

        players = new address[](units);
        owed = new uint256[](units);
        uint256[] memory held = new uint256[](units);
        uint256 n;
        uint256 seen;
        unchecked {
            for (uint256 i; i < units; ++i) {
                address e = entrants[i];
                // An unused low-byte bit proves this wallet is new. A set bit is
                // only a possible repeat: collisions still take the exact scan.
                // This preserves first-drawn order without scanning for most of
                // a usual field's distinct wallets; even all-colliding wallets
                // do no more scans than before.
                uint256 bit = uint256(1) << uint8(uint160(e));
                uint256 j = n;
                if (seen & bit != 0) {
                    j = 0;
                    while (j < n && players[j] != e) ++j;
                }
                if (j == n) {
                    players[n] = e;
                    ++n;
                    seen |= bit;
                }
                ++held[j];
            }
        }
        assembly ("memory-safe") {
            mstore(players, n)
            mstore(owed, n)
        }

        // Each unit's share floored to a whole multiple of 300 FLIP, then the chip is exactly a
        // fiftieth of it (`_DEPTH` boards of `_CHIPS` chips), so every budget plays the same shape;
        // what the floor leaves of a unit's share joins the pot.
        uint256 chipFlip = (stakes / units / _BANKROLL_UNIT) * (_BANKROLL_UNIT / (_DEPTH * _CHIPS * 1 ether));
        if (chipFlip > _MAX_CHIP) chipFlip = _MAX_CHIP;
        uint256 bankroll = chipFlip * (_DEPTH * _CHIPS * 1 ether);
        bytes32 dice = bytes32(_hash2(word, COIN_DRAW_DICE_TAG));
        // THE ROTATING SHOOTER, as a scheduled window draws it: one start for the field off the
        // shared seed, then seat by seat in first-drawn order, wrapping at the distinct count. A
        // turn past `_HAND_CAP` is never reached.
        uint256 start = _hash2(ROTATING_SHOOTER_TAG, uint256(dice)) % n;
        uint256 best;
        uint256 winner = type(uint256).max;
        for (uint256 j; j < n; ) {
            address p = players[j];
            Bets memory b;
            _scatterInto(b, _hash3(word, COIN_DRAW_SCATTER_TAG, uint160(p)), chipFlip, _CHIPS);
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
                _BOOST_TERMS | (turn << _BOOST_TURN_SHIFT)
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
            }
            uint256 pay;
            unchecked {
                pay = out * held[j];
            }
            pay = _award(pay, _hash3(word, COIN_DRAW_ROUND_TAG, uint160(p)));
            owed[j] = pay;
            emit CoinDrawBattleRun(level, p, held[j], r.bankrollOut, r.totalRolls, pay);
            unchecked { ++j; }
        }
        if (winner != type(uint256).max) {
            uint256 pot = _award(amount - bankroll * units, _hash2(word, COIN_DRAW_ROUND_TAG));
            owed[winner] += pot;
            emit CoinDrawBattlePot(level, players[winner], pot);
        }
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
