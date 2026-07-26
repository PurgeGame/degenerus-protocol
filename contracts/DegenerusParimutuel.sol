// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {ICoinflip} from "./interfaces/ICoinflip.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";

/**
 * @title DegenerusParimutuel
 * @author Burnie Degenerus
 * @notice A parimutuel market on whether the next level's target growth beats the prior
 *         level's. Opened during the jackpot phase, denominated in FLIP, one fixed-size
 *         bet per address.
 *
 * @dev THE SUBJECT. A level's growth is the level-over-level RATIO of the achieved pool,
 *      read straight off the ratchet the game already records:
 *
 *          growth(L) = ratchet(L) / ratchet(L-1)
 *
 *      Round L is bet during level L's jackpot phase and resolves OVER iff
 *      growth(L+1) > growth(L). A ratio rather than a difference because the pools compound:
 *      absolute level-over-level deltas grow with the game, so a difference would drift
 *      toward OVER over time, where a rate stays comparable across the whole run. It also
 *      keeps every term unsigned — a level that achieves less than its predecessor is just
 *      a ratio below 1 — and cross-multiplying makes the comparison exact (see _outcome).
 *
 *      The benchmark is settled the instant the round opens: growth(L) is already banked
 *      when level L's jackpot phase begins. Settlement one level later re-reads the
 *      identical expression, shifted by one.
 *
 *      NO SETTLEMENT WRITE. The outcome is a pure function of three ratchet entries the
 *      game already stores, so nothing pushes a result here and no round-settlement
 *      storage exists. A claim derives its own outcome from game.growthState(round) and
 *      writes only the claimant's own bit. ratchet(round + 1) == 0 is the unsettled
 *      predicate — each entry is 0 until its level transitions and its banked value
 *      forever after, which is what makes a settled round's answer permanent.
 *
 *      CENTURY BOUNDARIES SCORE NORMALLY. _endPhase overwrites levelPrizePool[x00] with
 *      futurePool/3 as the reachable x01 ratchet base, so that entry is both distorted and
 *      — for the whole of the century's jackpot phase, before the overwrite lands — still
 *      holding the achieved value. Scoring a boundary round off it would let the same round
 *      answer one way during that phase and the other way after, paying both sides and
 *      minting FLIP. The game instead serves every century term from its pushed achieved
 *      pool (see growthState), which is written once at the transition and never touched
 *      again, so x99, x00 and x01 are ordinary rounds measuring real growth.
 *
 *      ROUND 0 IS SKIPPED. growthState(0) reports no ratchet terms — the placement path has
 *      no round to name — so round 0 could never settle and a stake left there would strand.
 *      Round 1 needs no case of its own: its reference is the synthetic BOOTSTRAP_PRIZE_POOL,
 *      which is written at construction and equally permanent.
 *
 *      FLIP NEUTRALITY. Stakes are burned at placement and re-minted to winners through
 *      the standard coinflip credit rail, so the market mints nothing net. Floor-division
 *      dust is never minted, and a round whose winning side is empty leaves the losing
 *      side burned — both leave the mechanism net-deflationary, never inflationary.
 *
 *      GAME OVER. FLIP is tombstoned at GAMEOVER, so an unresolved book needs no unwind
 *      rule: every position in the game becomes worthless together. Rounds simply stop
 *      settling, because no further level banks a pool.
 */
contract DegenerusParimutuel {
    // =========================================================================
    // Wiring
    // =========================================================================

    IDegenerusGame private constant game =
        IDegenerusGame(ContractAddresses.GAME);
    IDegenerusCoin private constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    ICoinflip private constant coinflip =
        ICoinflip(ContractAddresses.COINFLIP);
    IDegenerusQuests private constant quests =
        IDegenerusQuests(ContractAddresses.QUESTS);

    // =========================================================================
    // Constants
    // =========================================================================

    /// @dev The single growth-bet stake: one whole ticket at PRICE_COIN_UNIT. Fixed rather
    ///      than chosen, so the two pools are counts and every winner is paid the same.
    uint256 public constant STAKE = 1_000 ether;

    /// @dev Participation-quest reward on the first day betting is open, before the
    ///      per-day decay. Parimutuel pays the last mover best, since the final bettor sees
    ///      the book before committing; a decaying reward prices that advantage back out
    ///      without a hard cutoff.
    uint256 public constant QUEST_BASE = 150 ether;

    uint8 private constant SIDE_OVER = 1;
    uint8 private constant SIDE_UNDER = 2;
    uint8 private constant SIDE_MASK = 3;
    uint8 private constant CLAIMED_BIT = 4;

    // =========================================================================
    // Storage
    // =========================================================================

    /// @dev Per-round side counts: overCount in the low 128 bits, underCount in the high 128.
    ///      One slot, and a placement is a single read-modify-write of it.
    mapping(uint24 => uint256) private roundCounts;

    /// @dev Per-round bets: the low two bits carry the side, bit 2 marks the payout taken.
    ///      Keyed by round then player so a round left unclaimed is never destroyed by the
    ///      next round's placement.
    mapping(uint24 => mapping(address => uint8)) private bets;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice The caller may not act on the player's behalf.
    error NotApproved();

    /// @notice No round is open for betting: outside the jackpot phase — game over
    ///         included, since no phase ever opens again — or on round 0, which can
    ///         never settle.
    error MarketClosed();

    /// @notice The player already holds a bet on the open round.
    error AlreadyBet();

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a growth bet is placed.
    /// @param player The player the bet belongs to.
    /// @param round The round's level.
    /// @param over True for the OVER side (growth accelerates), false for UNDER.
    /// @param questReward FLIP credited for the participation quest (0 if not eligible).
    event BetPlaced(
        address indexed player,
        uint24 indexed round,
        bool over,
        uint256 questReward
    );

    /// @notice Emitted when a winning growth bet is claimed.
    /// @param player The bettor being paid.
    /// @param round The round's level.
    /// @param outcome The round's derived outcome (1 = OVER, 2 = UNDER).
    /// @param payout FLIP credited: the stake plus a pro-rata share of the losing side.
    event BetClaimed(
        address indexed player,
        uint24 indexed round,
        uint8 outcome,
        uint256 payout
    );

    // =========================================================================
    // Construction
    // =========================================================================

    constructor() {
        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "parimutuel.degenerus.eth")
            );
            ok;
        }
    }

    // =========================================================================
    // Betting
    // =========================================================================

    /// @notice Place the growth bet for the open round.
    /// @dev Gated, not permissionless: the bet spends the player's FLIP, so only the player
    ///      or an approved operator may place it. One fixed-size bet per address per round —
    ///      there is no amount to choose and no averaging in, which is what makes the choice
    ///      to commit early against a thin book a real decision rather than a mechanical one.
    /// @param player The player the bet belongs to (zero address for msg.sender).
    /// @param over True to bet that growth accelerates, false to bet that it does not.
    function placeBet(address player, bool over) external {
        if (player == address(0)) player = msg.sender;
        if (
            player != msg.sender &&
            !game.isOperatorApproved(player, msg.sender)
        ) revert NotApproved();

        (, , , uint24 round, bool open, uint8 phaseDay) = game.growthState(0);
        // Round 0 is the sole unscoreable round — growthState reports no ratchet terms
        // for it, so it could never settle and a stake left there would strand.
        if (!open || round == 0) revert MarketClosed();
        if (bets[round][player] != 0) revert AlreadyBet();

        bets[round][player] = over ? SIDE_OVER : SIDE_UNDER;
        // overCount occupies the low half, underCount the high half, so each side increments
        // by its own unit and the two can never carry into one another.
        roundCounts[round] += over ? 1 : (uint256(1) << 128);

        coin.burnCoin(player, STAKE);

        uint256 reward = quests.recordGrowthBet(
            player,
            round,
            _questReward(phaseDay)
        );
        emit BetPlaced(player, round, over, reward);
    }

    /// @notice Claim payouts for the named settled rounds.
    /// @dev Permissionless: a claim only ever credits the bettor, so any caller may settle
    ///      any player's rounds. Rounds that are unsettled, unbet, already claimed, or lost
    ///      are skipped rather than reverted, so one stale id cannot brick a batch.
    /// @param player The bettor to pay (zero address for msg.sender).
    /// @param rounds The round levels to claim.
    /// @return total FLIP credited across the batch.
    function claim(
        address player,
        uint24[] calldata rounds
    ) external returns (uint256 total) {
        if (player == address(0)) player = msg.sender;

        uint256 len = rounds.length;
        for (uint256 i; i < len; ) {
            total += _claim(player, rounds[i]);
            unchecked {
                ++i;
            }
        }

        if (total != 0) coinflip.creditFlip(player, total);
    }

    /// @notice Pay every winner on one settled round.
    /// @dev The settlement crank. A round's outcome and its per-winner payout are
    ///      properties of the ROUND, not of the claimant, so both are derived once for the
    ///      whole list and the credits land as one creditFlipBatch call: settling a
    ///      hundred bettors costs one growthState call, one roundCounts read and one
    ///      credit call, where a hundred single claims would repeat all three.
    ///
    ///      Permissionless for the same reason as claim — a payout can only ever reach the
    ///      bettor who placed the bet. Addresses that did not bet, lost, or already claimed
    ///      are skipped rather than reverted, so a duplicate or junk entry cannot brick the
    ///      batch, and an unsettled round pays nobody instead of failing.
    /// @param round The round to settle.
    /// @param players The bettors to pay.
    /// @return total FLIP credited across the batch.
    function claimRound(
        uint24 round,
        address[] calldata players
    ) external returns (uint256 total) {
        uint8 outcome = _outcome(round);
        if (outcome == 0) return 0;

        // An empty winning side has nobody to pay — and no divisor. The named path never
        // meets this case (it derives the payout only after matching a winner's bet), so
        // the guard lives here, where the payout is derived before any bet is read.
        uint256 packed = roundCounts[round];
        uint256 winCount = outcome == SIDE_OVER
            ? uint128(packed)
            : packed >> 128;
        if (winCount == 0) return 0;
        uint256 payout = _payoutFrom(packed, outcome);

        // Credits land through one creditFlipBatch call rather than one credit per
        // winner. The arrays stay list-shaped: a skipped entry leaves its slot zeroed,
        // and the batch ignores zero entries by contract.
        uint256 len = players.length;
        address[] memory winners = new address[](len);
        uint256[] memory payouts = new uint256[](len);
        for (uint256 i; i < len; ) {
            address player = players[i];
            uint8 bet = bets[round][player];
            // A repeated address fails this on its second pass: the first already set the
            // claimed bit.
            if ((bet & SIDE_MASK) == outcome && (bet & CLAIMED_BIT) == 0) {
                bets[round][player] = bet | CLAIMED_BIT;
                winners[i] = player;
                payouts[i] = payout;
                total += payout;
                emit BetClaimed(player, round, outcome, payout);
            }
            unchecked {
                ++i;
            }
        }

        if (total != 0) coinflip.creditFlipBatch(winners, payouts);
    }

    /// @dev Settle one round for one player. Returns the payout, or 0 when there is
    ///      nothing to pay.
    function _claim(address player, uint24 round) private returns (uint256) {
        uint8 bet = bets[round][player];
        if (bet == 0 || (bet & CLAIMED_BIT) != 0) return 0;

        uint8 outcome = _outcome(round);
        if (outcome == 0 || (bet & SIDE_MASK) != outcome) return 0;

        uint256 payout = _payout(round, outcome);
        bets[round][player] = bet | CLAIMED_BIT;
        emit BetClaimed(player, round, outcome, payout);
        return payout;
    }

    // =========================================================================
    // Scoring
    // =========================================================================

    /// @dev A round's outcome, derived from the game's ratchet entries. 0 while the round's
    ///      successor level has not yet banked its entry.
    ///
    ///      The benchmark is fixed the moment the round opens — it is the growth the level
    ///      just delivered — and settlement re-reads the identical expression one level on:
    ///
    ///          growth(L) = ratchet[L] / ratchet[L-1]
    ///          round L resolves OVER iff growth(L+1) > growth(L)
    ///
    ///      Cross-multiplied, so the comparison is exact integer arithmetic with no
    ///      division, no rounding, and no signed terms:
    ///
    ///          next / curr > curr / prev   <=>   next * prev > curr * curr
    ///
    ///      Both denominators are guaranteed non-zero: levels bank in order, so a non-zero
    ///      `next` implies a non-zero `curr`, and every round below it has banked too —
    ///      leaving `prev` either a banked entry, a completed century's pushed pool, or,
    ///      at round 1, the seeded ratchet[0].
    function _outcome(uint24 round) private view returns (uint8) {
        (uint256 prev, uint256 curr, uint256 next, , , ) = game.growthState(
            round
        );
        return _outcomeFrom(prev, curr, next);
    }

    /// @dev The comparison itself, split out so a caller that already holds the round's
    ///      terms scores them without a second growthState call.
    function _outcomeFrom(
        uint256 prev,
        uint256 curr,
        uint256 next
    ) private pure returns (uint8) {
        if (next == 0) return 0;
        // Strictly greater: the line is the level's own growth rate, and OVER must clear
        // it outright — a push belongs to the UNDER.
        return next * prev > curr * curr ? SIDE_OVER : SIDE_UNDER;
    }

    /// @dev What one winning bet on `round` pays.
    function _payout(
        uint24 round,
        uint8 outcome
    ) private view returns (uint256) {
        return _payoutFrom(roundCounts[round], outcome);
    }

    /// @dev The payout arithmetic over an already-loaded counts word. A winning bet exists
    ///      whenever this is called, so the winning count is at least 1. An empty losing
    ///      side needs no special case — the numerator collapses to the winning count and
    ///      the payout is exactly the stake back.
    function _payoutFrom(
        uint256 packed,
        uint8 outcome
    ) private pure returns (uint256) {
        uint256 overCount = uint128(packed);
        uint256 underCount = packed >> 128;
        uint256 winCount = outcome == SIDE_OVER ? overCount : underCount;
        return (STAKE * (overCount + underCount)) / winCount;
    }

    /// @dev The participation-quest reward for a bet placed on jackpot-phase day
    ///      `phaseDay`: halved per day, floored to a whole FLIP so the ladder reads as
    ///      round numbers rather than trailing halves — 150 / 75 / 37 / 18 across the
    ///      phase's four jackpot days.
    ///
    ///      Days 0 and 1 share the top tier deliberately. The counter reads 0 from the
    ///      transition until the first daily jackpot settles — usually later the same
    ///      day — and 1 from then until day 2's processing. Folding 0 into 1 prices that
    ///      whole first day at 150 rather than dropping a tier minutes in when the
    ///      first settlement lands. It is also what a closed market quotes.
    function _questReward(uint8 phaseDay) private pure returns (uint256) {
        uint256 step = phaseDay == 0 ? 0 : phaseDay - 1;
        return ((QUEST_BASE / 1 ether) >> step) * 1 ether;
    }

    // =========================================================================
    // Views
    // =========================================================================

    /// @notice The open round, plus one player's position on a round of interest.
    /// @param player The player whose position to report (address(0) for none).
    /// @param round The round to report the position for — the open round while betting,
    ///        or any past round when checking what is claimable.
    /// @return openRound The round a bet placed now would join (0 when betting is closed).
    /// @return overCount Bets on the OVER side of `round`.
    /// @return underCount Bets on the UNDER side of `round`.
    /// @return questReward FLIP a bet placed right now would earn from the quest.
    /// @return side The player's side on `round`: 1 = OVER, 2 = UNDER (0 = no bet).
    /// @return claimed True once the player has taken the payout for `round`.
    /// @return outcome `round`'s outcome (0 = unsettled).
    /// @return payout FLIP claimable now (0 if unsettled, lost, or already claimed).
    function marketState(
        address player,
        uint24 round
    )
        external
        view
        returns (
            uint24 openRound,
            uint128 overCount,
            uint128 underCount,
            uint256 questReward,
            uint8 side,
            bool claimed,
            uint8 outcome,
            uint256 payout
        )
    {
        // One call, not two: growthState carries the phase half whatever round it is asked
        // about, so asking about `round` answers the position half as well. Round 0 needs
        // no guard of its own — growthState reports no terms for it, and a zero `next` is
        // already the unsettled reading.
        (
            uint256 prev,
            uint256 curr,
            uint256 next,
            uint24 lvl,
            bool open,
            uint8 phaseDay
        ) = game.growthState(round);
        if (open && lvl != 0) openRound = lvl;
        questReward = _questReward(phaseDay);

        uint256 packed = roundCounts[round];
        overCount = uint128(packed);
        underCount = uint128(packed >> 128);

        uint8 bet = bets[round][player];
        side = bet & SIDE_MASK;
        claimed = (bet & CLAIMED_BIT) != 0;
        outcome = _outcomeFrom(prev, curr, next);
        if (side != 0 && !claimed && side == outcome) {
            payout = _payoutFrom(packed, outcome);
        }
    }
}
