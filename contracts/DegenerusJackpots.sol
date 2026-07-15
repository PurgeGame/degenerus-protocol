// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*+==============================================================================+
  |                        DEGENERUS JACKPOTS CONTRACT                           |
  |                                                                              |
  |  Standalone contract managing the BAF (Big Ass Flip) jackpot system.         |
  |  Decimator logic is handled in the game decimator module.                    |
  +==============================================================================+*/

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {EntropyLib} from "./libraries/EntropyLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

// ===========================================================================
// External Interfaces
// ===========================================================================

/// @notice View interface for coin contract jackpot-related queries.
/// @dev Used to retrieve coinflip statistics for leaderboards.
interface IDegenerusCoinJackpotView {
    /// @notice Get top coinflip bettor from the last 24-hour window.
    /// @return player Top bettor address.
    /// @return score Bettor's score.
    function coinflipTopLastDay() external view returns (address player, uint96 score);
}

// ===========================================================================
// Contract
// ===========================================================================

/// @title DegenerusJackpots
/// @author Burnie Degenerus
/// @notice Standalone contract managing the BAF jackpot system.
/// @dev Coinflip forwards flips into this contract; game calls to resolve jackpots.
///      - BAF: Leaderboard-based distribution to top coinflip bettors
///      - Decimator: handled in the game decimator module
/// @custom:security-contact burnie@degener.us
contract DegenerusJackpots is IDegenerusJackpots {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in jackpot operations.                   |
      +======================================================================+*/

    /// @notice Thrown when a function restricted to COIN or COINFLIP is called by another address.
    error OnlyCoin();

    /// @notice Thrown when a function restricted to the game contract is called by another address.
    error OnlyGame();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Events for tracking BAF state changes for indexers.                 |
      +======================================================================+*/

    /// @notice Emitted when a player's BAF flip stake is recorded.
    /// @param player Address of the player.
    /// @param lvl Current game level (BAF bracket).
    /// @param amount Amount added this flip.
    /// @param newTotal Player's new total stake for this level.
    event BafFlipRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint256 amount,
        uint256 newTotal
    );

    /// @notice Emitted when a BAF bracket is skipped because the daily flip lost.
    /// @param lvl Level whose BAF was skipped.
    /// @param day Day index on which the skip occurred.
    event BafSkipped(uint24 indexed lvl, uint24 day);

    /*+======================================================================+
      |                              STRUCTS                                 |
      +======================================================================+
      |  Data structures for BAF leaderboard tracking.                       |
      +======================================================================+*/

    /// @notice Leaderboard entry for BAF coinflip stakes.
    /// @dev Packed into single slot: address (160) + score (96) = 256 bits.
    struct PlayerScore {
        /// @notice Player address.
        address player;
        /// @notice Weighted coinflip stake (whole tokens, capped at uint96.max).
        uint96 score;
    }

    /// @notice Per-player BAF state for a bracket level.
    /// @dev Packed into single slot: total (192) + epoch (64) = 256 bits.
    ///      A total whose epoch is stale (bracket already resolved) reads as zero.
    struct BafPlayer {
        /// @notice Accumulated winning-flip stake (saturates at uint192.max).
        uint192 total;
        /// @notice Bracket epoch the total belongs to.
        uint64 epoch;
    }

    /// @notice Per-level BAF bracket state.
    /// @dev Packed into single slot: epoch (64) + topLen (8). Both are touched by
    ///      every flip credit, so sharing a slot makes the second read warm.
    struct BafLevel {
        /// @notice Epoch counter, incremented on jackpot resolution (lazy-resets player totals).
        uint64 epoch;
        /// @notice Current length of the bafTop board (0-4).
        uint8 topLen;
    }

    /*+======================================================================+
      |                            CONSTANT STATE                            |
      +======================================================================+
      |  Trusted contract addresses fixed at deployment.                     |
      +======================================================================+*/

    /// @notice Coinflip contract for coinflip stats queries (constant).
    IDegenerusCoinJackpotView internal constant coin = IDegenerusCoinJackpotView(ContractAddresses.COINFLIP);

    /// @notice Core game contract for jackpot resolution and player queries (constant).
    IDegenerusGame internal constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);


    /*+======================================================================+
      |                            CONSTANTS                                 |
      +======================================================================+
      |  Fixed values for prize calculations and BAF configuration.          |
      +======================================================================+*/

    /// @dev Fixed number of scatter rounds to keep BAF gas bounded.
    uint8 private constant BAF_SCATTER_ROUNDS = 50;


    /*+======================================================================+
      |                         BAF STATE STORAGE                            |
      +======================================================================+
      |  Per-player BAF totals and top-4 leaderboard per level.              |
      +======================================================================+*/

    /// @notice Accumulated coinflip stake + owning epoch per player per BAF bracket level.
    mapping(uint24 => mapping(address => BafPlayer)) internal bafPlayer;

    /// @notice Top-4 coinflip bettors for BAF per level (sorted by score descending).
    mapping(uint24 => PlayerScore[4]) internal bafTop;

    /// @notice Epoch counter + bafTop board length per BAF bracket level.
    mapping(uint24 => BafLevel) internal bafLevel;

    /// @notice Day index of the most recent BAF jackpot resolution (any bracket).
    uint24 internal lastBafResolvedDay;

    /*+======================================================================+
      |                      MODIFIERS & ACCESS CONTROL                      |
      +======================================================================+
      |  Access control for trusted callers only.                            |
      +======================================================================+*/

    /// @dev Restricts function to the coinflip contract.
    /// @custom:reverts OnlyCoin When caller is not the coinflip contract.
    modifier onlyCoin() {
        if (msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();
        _;
    }

    /// @dev Restricts function to game contract only.
    /// @custom:reverts OnlyGame When caller is not the game contract.
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    /*+======================================================================+
      |                      COINFLIP CONTRACT HOOKS                         |
      +======================================================================+
      |  Called by Coinflip to record coinflip activity.                     |
      |  These hooks build state used by jackpot resolution.                 |
      +======================================================================+*/

    /// @notice Record a coinflip win for BAF score tracking.
    /// @dev Called by COINFLIP when a player's winnings settle. VAULT accrues a BAF score like any
    ///      player — so it can rank in the score-ranked ticket slices whose tickets it holds — but
    ///      is kept OFF the top-4 leaderboard (no _updateBafTop), so it can never take the
    ///      top-bettor slices. sDGNRS gets no BAF score at all: it is skipped upstream at the
    ///      recordBafFlip call site (its free per-level flips would otherwise dominate the slices).
    /// @param player Address of the player.
    /// @param lvl Current game level (BAF bracket).
    /// @param amount Winning coinflip payout credited to the player's BAF score.
    /// @custom:access Restricted to COINFLIP via onlyCoin modifier.
    function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin {
        uint64 currentEpoch = bafLevel[lvl].epoch;
        BafPlayer memory ps = bafPlayer[lvl][player];
        // A stale epoch means the bracket already resolved: restart the total from zero.
        uint256 total = ps.epoch == currentEpoch ? ps.total : 0;
        unchecked { total += amount; }
        if (total > type(uint192).max) total = type(uint192).max;
        bafPlayer[lvl][player] = BafPlayer({total: uint192(total), epoch: currentEpoch});

        // VAULT accrues a score (above) but stays off the leaderboard: it can never win the
        // top-bettor slices, while still ranking in the score-ranked ticket slices it holds.
        if (player != ContractAddresses.VAULT) {
            _updateBafTop(lvl, player, total);
        }
        emit BafFlipRecorded(player, lvl, amount, total);
    }

    /*+========================================================================+
      |                      BAF JACKPOT RESOLUTION                            |
      +========================================================================+
      |  Distributes ETH prize pool to various winner categories.              |
      |                                                                        |
      |  PRIZE DISTRIBUTION:                                                   |
      |  +-------------------------------------------------------------------+ |
      |  | 10% | Top BAF bettor for this level                               | |
      |  |  5% | Top coinflip bettor from last 24h window                    | |
      |  |  5% | Random pick: 3rd or 4th BAF slot                            | |
      |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)    | |
      |  |  5% | Far-future ticket holders 2nd draw (3% 1st / 2% 2nd)        | |
      |  | 45% | Scatter 1st place (50 rounds x 4 multi-level trait tickets) | |
      |  | 25% | Scatter 2nd place (50 rounds x 4 multi-level trait tickets) | |
      |  +-------------------------------------------------------------------+ |
      |                                                                        |
      |  ELIGIBILITY:                                                          |
      |  * Non-zero address only (no streak requirement)                       |
      |                                                                        |
      |  SECURITY:                                                             |
      |  • VRF-derived randomness for all random selections                    |
      |  • Entropy chained via keccak256 for independence                      |
      |  • Unfilled prizes returned via returnAmountWei                        |
      |  • Unfilled scatter rounds return to future pool                       |
      +========================================================================+*/

    /// @notice Resolve the BAF jackpot for a level.
    /// @dev Distributes poolWei across multiple winner categories with eligibility checks.
    ///      Returns arrays of winners/amounts plus unawarded amount for recycling.
    ///      Clears leaderboard state after resolution.
    /// @param poolWei Total ETH prize pool for distribution.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return winners Array of winner addresses.
    /// @return amounts Array of prize amounts corresponding to winners.
    /// @return returnAmountWei Unawarded prize amount to return to caller.
    /// @custom:access Restricted to game contract via onlyGame modifier.
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    )
        external
        override
        onlyGame
        returns (address[] memory winners, uint256[] memory amounts, uint256 returnAmountWei)
    {
        uint256 P = poolWei;
        // Max distinct winners: 1 (top BAF) + 1 (top flip) + 1 (pick) + 4 (far-future x2) + 50 + 50 (scatter) = 107.
        address[] memory tmpW = new address[](107);
        uint256[] memory tmpA = new uint256[](107);
        uint256 n;
        uint256 toReturn;

        uint256 entropy = rngWord;
        uint256 salt;
        // The bracket epoch is fixed for the whole resolution: read it once and
        // thread it through every per-candidate score read.
        uint64 currentEpoch = bafLevel[lvl].epoch;

        {
            // Slice A: 10% to the top BAF bettor for the level.
            uint256 topPrize = P / 10;
            (address w, ) = _bafTop(lvl, 0);
            if (_creditOrRefund(w, topPrize, tmpW, tmpA, n)) {
                unchecked {
                    ++n;
                }
            } else {
                toReturn += topPrize;
            }
        }

        {
            // Slice A2: 5% to the top coinflip bettor from the last day window.
            uint256 topPrize = P / 20;
            (address w, ) = coin.coinflipTopLastDay();
            if (_creditOrRefund(w, topPrize, tmpW, tmpA, n)) {
                unchecked {
                    ++n;
                }
            } else {
                toReturn += topPrize;
            }
        }

        {
            unchecked {
                ++salt;
            }
            entropy = EntropyLib.hash2(entropy, salt);
            uint256 prize = P / 20;
            uint8 pick = 2 + uint8(entropy & 1);
            (address w, ) = _bafTop(lvl, pick);
            // Slice B: 5% to either the 3rd or 4th BAF leaderboard slot (pseudo-random tie-break).
            if (_creditOrRefund(w, prize, tmpW, tmpA, n)) {
                unchecked {
                    ++n;
                }
            } else {
                toReturn += prize;
            }
        }

        // Slices D and D2: two independent 5% draws to far-future ticket holders
        // (3% 1st / 2% 2nd by BAF score). The ++salt at the head of each pass keeps
        // the salt/entropy sequence (2 then 3 after slice B) and draw independence.
        for (uint256 pass; pass < 2; ) {
            unchecked { ++salt; }
            entropy = EntropyLib.hash2(entropy, salt);
            address[] memory farTickets = degenerusGame.sampleFarFutureTickets(entropy);

            uint256 farFirst = (P * 3) / 100;
            uint256 farSecond = P / 50;

            address best;
            uint256 bestScore;
            address second;
            uint256 secondScore;

            uint256 fLen = farTickets.length;
            for (uint256 i; i < fLen; ) {
                address cand = farTickets[i];
                uint256 score = _bafScore(cand, lvl, currentEpoch);
                // Select strictly by positive BAF score (same rule as the scatter slice): a
                // zero-score candidate never populates best/second, so a far-future set with no
                // BAF activity leaves best/second address(0) and the share returns to the pool
                // unpaid rather than paying an unearned holder.
                if (score > bestScore) {
                    second = best;
                    secondScore = bestScore;
                    best = cand;
                    bestScore = score;
                } else if (score > secondScore && cand != best) {
                    second = cand;
                    secondScore = score;
                }
                unchecked { ++i; }
            }

            if (_creditOrRefund(best, farFirst, tmpW, tmpA, n)) {
                unchecked { ++n; }
            } else {
                toReturn += farFirst;
            }
            if (_creditOrRefund(second, farSecond, tmpW, tmpA, n)) {
                unchecked { ++n; }
            } else {
                toReturn += farSecond;
            }
            unchecked { ++pass; }
        }

        // Scatter slice: 200 total draws (4 tickets * 50 rounds). Per round, take top-2 by BAF score.
        // Unfilled rounds return their per-round share to future pool.
        {
            // Slice E: scatter tickets from trait sampler so casual participants can land smaller cuts.
            uint256 scatterTop = (P * 45) / 100;
            uint256 scatterSecond = P / 4;
            address[50] memory firstWinners;
            address[50] memory secondWinners;
            uint256 firstCount;
            uint256 secondCount;
            bool isCentury = (lvl % 100 == 0);

            // Fixed rounds of 4-ticket sampling to keep gas bounded per call.
            for (uint8 round = 0; round < BAF_SCATTER_ROUNDS; ) {
                unchecked {
                    ++salt;
                }
                entropy = EntropyLib.hash2(entropy, salt);

                // Level targeting varies by BAF type:
                // Non-x00: 20 rounds from lvl, 30 rounds random from lvl+1..lvl+4
                // x00:     4 rounds lvl, 8 rounds lvl+1..lvl+3, 38 random from past 99
                uint24 targetLvl;
                if (isCentury) {
                    if (round < 4) targetLvl = lvl;
                    else if (round < 12) targetLvl = lvl + 1 + uint24(entropy % 3);
                    else targetLvl = lvl - 1 - uint24(entropy % 99);
                } else {
                    if (round < 20) targetLvl = lvl;
                    else targetLvl = lvl + 1 + uint24(entropy % 4);
                }

                (, address[] memory tickets) = degenerusGame.sampleTraitEntriesAtLevel(targetLvl, entropy);

                // Pick up to 4 tickets from the sampled set.
                uint256 limit = tickets.length;
                if (limit > 4) limit = 4;

                address best;
                uint256 bestScore;
                address second;
                uint256 secondScore;

                for (uint256 i; i < limit; ) {
                    address cand = tickets[i];
                    uint256 score = _bafScore(cand, lvl, currentEpoch);
                    if (score > bestScore) {
                        second = best;
                        secondScore = bestScore;
                        best = cand;
                        bestScore = score;
                    } else if (score > secondScore && cand != best) {
                        second = cand;
                        secondScore = score;
                    }
                    unchecked {
                        ++i;
                    }
                }

                // Bucket winners if eligible and capacity not exceeded; otherwise refund their would-be share later.
                if (best != address(0)) {
                    firstWinners[firstCount] = best;
                    unchecked {
                        ++firstCount;
                    }
                }
                if (second != address(0)) {
                    secondWinners[secondCount] = second;
                    unchecked {
                        ++secondCount;
                    }
                }

                unchecked {
                    ++round;
                }
            }

            // Per-round fixed share: empty rounds return to future pool.
            uint256 perRoundFirst = scatterTop / BAF_SCATTER_ROUNDS;
            uint256 perRoundSecond = scatterSecond / BAF_SCATTER_ROUNDS;

            // Return unfilled rounds + integer division dust.
            toReturn += scatterTop - perRoundFirst * firstCount;
            toReturn += scatterSecond - perRoundSecond * secondCount;

            for (uint256 i; i < firstCount; ) {
                tmpW[n] = firstWinners[i];
                tmpA[n] = perRoundFirst;
                unchecked {
                    ++n;
                    ++i;
                }
            }

            for (uint256 i; i < secondCount; ) {
                tmpW[n] = secondWinners[i];
                tmpA[n] = perRoundSecond;
                unchecked {
                    ++n;
                    ++i;
                }
            }

        }

        winners = tmpW;
        amounts = tmpA;
        assembly ("memory-safe") {
            mstore(winners, n)
            mstore(amounts, n)
        }

        // Clean up leaderboard state for this level: clear the board entries, then
        // reset the length and bump the epoch in a single slot write.
        {
            uint8 boardLen = bafLevel[lvl].topLen;
            for (uint8 i; i < boardLen; ) {
                delete bafTop[lvl][i];
                unchecked { ++i; }
            }
            unchecked {
                bafLevel[lvl] = BafLevel({epoch: currentEpoch + 1, topLen: 0});
            }
        }
        // Day computed locally: identical to game.currentDayView() (pure GameTimeLib
        // wall-clock) without the external call.
        lastBafResolvedDay = GameTimeLib.currentDayIndex();
        return (winners, amounts, toReturn);
    }

    /// @notice Mark a BAF bracket as skipped because the daily flip lost.
    /// @dev Bumps lastBafResolvedDay so pre-skip winning-flip credit is filtered
    ///      out of future claims (Coinflip gates winningBafCredit on
    ///      cursor > lastBafResolvedDay). Leaderboard state for lvl is left
    ///      as-is — no new writes ever target a past bracket, so clearing
    ///      would only burn gas.
    /// @param lvl Level whose BAF was skipped.
    /// @custom:access Restricted to game contract via onlyGame modifier.
    function markBafSkipped(uint24 lvl) external onlyGame {
        // Day computed locally: identical to game.currentDayView() (pure GameTimeLib
        // wall-clock) without the external call.
        uint24 today = GameTimeLib.currentDayIndex();
        lastBafResolvedDay = today;
        emit BafSkipped(lvl, today);
    }

    /*+======================================================================+
      |                      INTERNAL HELPER FUNCTIONS                       |
      +======================================================================+
      |  Utility functions for bucket packing and scoring.                   |
      +======================================================================+*/

    /// @dev Credit prize to non-zero winner or return false for refund.
    ///      Writes to preallocated buffers if winner is valid.
    /// @param candidate Potential winner address.
    /// @param prize Prize amount in wei.
    /// @param winnersBuf Pre-allocated winners array.
    /// @param amountsBuf Pre-allocated amounts array.
    /// @param idx Current write index.
    /// @return credited True if winner was credited (eligible and non-zero prize).
    function _creditOrRefund(
        address candidate,
        uint256 prize,
        address[] memory winnersBuf,
        uint256[] memory amountsBuf,
        uint256 idx
    ) private pure returns (bool credited) {
        if (prize == 0) return false;
        if (candidate != address(0)) {
            winnersBuf[idx] = candidate;
            amountsBuf[idx] = prize;
            return true;
        }
        return false;
    }

    /*+======================================================================+
      |                      BAF LEADERBOARD HELPERS                         |
      +======================================================================+
      |  Maintain sorted top-4 leaderboard per level.                        |
      +======================================================================+*/

    /// @dev Get player's BAF score for a level.
    /// @param player Address to query.
    /// @param lvl Level number.
    /// @param currentEpoch The bracket's current epoch (read once per resolution by callers).
    /// @return Accumulated coinflip total (0 if the stored epoch is stale).
    function _bafScore(address player, uint24 lvl, uint64 currentEpoch) private view returns (uint256) {
        BafPlayer memory ps = bafPlayer[lvl][player];
        if (ps.epoch != currentEpoch) return 0;
        return ps.total;
    }

    /// @dev Convert raw score to capped uint96 (whole tokens only).
    /// @param s Raw score in base units.
    /// @return Capped score in whole tokens.
    function _score96(uint256 s) private pure returns (uint96) {
        uint256 wholeTokens = s / 1 ether;
        if (wholeTokens > type(uint96).max) {
            wholeTokens = type(uint96).max;
        }
        return uint96(wholeTokens);
    }

    /// @dev Update top-4 BAF leaderboard with new stake.
    ///      Maintains sorted order (highest score first).
    ///      Handles existing player update, new player insertion, and capacity management.
    /// @param lvl Level number.
    /// @param player Address.
    /// @param stake New total stake for player.
    function _updateBafTop(uint24 lvl, address player, uint256 stake) private {
        uint96 score = _score96(stake);
        PlayerScore[4] storage board = bafTop[lvl];
        uint8 len = bafLevel[lvl].topLen;

        // Check if player already on leaderboard
        uint8 existing = 4; // sentinel: not found
        for (uint8 i; i < len; ) {
            if (board[i].player == player) {
                existing = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Case 1: Player already on board - shift down and re-place if improved
        // (same shift-then-place idiom as Cases 2/3; strict > keeps tie order).
        if (existing < 4) {
            if (score <= board[existing].score) return; // No improvement
            uint8 idx = existing;
            while (idx > 0 && score > board[idx - 1].score) {
                board[idx] = board[idx - 1];
                unchecked {
                    --idx;
                }
            }
            board[idx] = PlayerScore({player: player, score: score});
            return;
        }

        // Case 2: Board not full - insert in sorted position
        if (len < 4) {
            uint8 insert = len;
            while (insert > 0 && score > board[insert - 1].score) {
                board[insert] = board[insert - 1];
                unchecked {
                    --insert;
                }
            }
            board[insert] = PlayerScore({player: player, score: score});
            bafLevel[lvl].topLen = len + 1;
            return;
        }

        // Case 3: Board full - replace bottom if score is higher
        if (score <= board[3].score) return; // Not good enough
        uint8 idx2 = 3;
        while (idx2 > 0 && score > board[idx2 - 1].score) {
            board[idx2] = board[idx2 - 1];
            unchecked {
                --idx2;
            }
        }
        board[idx2] = PlayerScore({player: player, score: score});
    }

    /// @dev Get player at leaderboard position.
    /// @param lvl Level number.
    /// @param idx Position (0 = top).
    /// @return player Address at position (address(0) if empty).
    /// @return score Player's score.
    function _bafTop(uint24 lvl, uint8 idx) private view returns (address player, uint96 score) {
        uint8 len = bafLevel[lvl].topLen;
        if (idx >= len) return (address(0), 0);
        PlayerScore memory entry = bafTop[lvl][idx];
        return (entry.player, entry.score);
    }

    /*+======================================================================+
      |                         VIEW FUNCTIONS                               |
      +======================================================================+*/

    /// @notice Day index of the most recent BAF jackpot resolution.
    function getLastBafResolvedDay() external view returns (uint24) {
        return lastBafResolvedDay;
    }
}
