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
/// @dev BurnieCoin forwards flips into this contract; game calls to resolve jackpots.
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

    /// @notice Thrown when a function restricted to the coin contract is called by another address.
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

    /// @dev Bit offset in winnerMask for scatter winner flags.
    ///      First 128 bits for direct winners, upper bits for scatter.
    uint256 private constant BAF_SCATTER_MASK_OFFSET = 128;

    /// @dev Number of scatter winners receiving ticket-routing treatment.
    ///      Last 40 scatter winners get winnerMask flags set.
    uint8 private constant BAF_SCATTER_TICKET_WINNERS = 40;

    /// @dev Fixed number of scatter rounds to keep BAF gas bounded.
    uint8 private constant BAF_SCATTER_ROUNDS = 50;


    /*+======================================================================+
      |                         BAF STATE STORAGE                            |
      +======================================================================+
      |  Per-player BAF totals and top-4 leaderboard per level.              |
      +======================================================================+*/

    /// @notice Accumulated coinflip stake per player per BAF bracket level.
    mapping(uint24 => mapping(address => uint256)) internal bafTotals;

    /// @notice Top-4 coinflip bettors for BAF per level (sorted by score descending).
    mapping(uint24 => PlayerScore[4]) internal bafTop;

    /// @notice Current length of bafTop array for each level (0-4).
    mapping(uint24 => uint8) internal bafTopLen;

    /// @notice Epoch counter per BAF bracket, incremented on jackpot resolution.
    mapping(uint24 => uint256) internal bafEpoch;

    /// @notice Player's last-known epoch per BAF bracket (for lazy reset).
    mapping(uint24 => mapping(address => uint256)) internal bafPlayerEpoch;

    /// @notice Day index of the most recent BAF jackpot resolution (any bracket).
    uint48 internal lastBafResolvedDay;

    /*+======================================================================+
      |                      MODIFIERS & ACCESS CONTROL                      |
      +======================================================================+
      |  Access control for trusted callers only.                            |
      +======================================================================+*/

    /// @dev Restricts function to coin or coinflip contract.
    /// @custom:reverts OnlyCoin When caller is not the coin or coinflip contract.
    modifier onlyCoin() {
        if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP) revert OnlyCoin();
        _;
    }

    /// @dev Restricts function to game contract only.
    /// @custom:reverts OnlyGame When caller is not the game contract.
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    /*+======================================================================+
      |                      COIN CONTRACT HOOKS                             |
      +======================================================================+
      |  Called by BurnieCoin to record coinflip activity.                   |
      |  These hooks build state used by jackpot resolution.                 |
      +======================================================================+*/

    /// @notice Record a coinflip stake for BAF leaderboard tracking.
    /// @dev Called by coin contract on every manual coinflip. Silently ignores vault address.
    /// @param player Address of the player.
    /// @param lvl Current game level (BAF bracket).
    /// @param amount Raw coinflip stake amount.
    /// @custom:access Restricted to coin contract via onlyCoin modifier.
    function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin {
        if (player == ContractAddresses.VAULT) return;

        uint256 currentEpoch = bafEpoch[lvl];
        if (bafPlayerEpoch[lvl][player] != currentEpoch) {
            bafPlayerEpoch[lvl][player] = currentEpoch;
            bafTotals[lvl][player] = 0;
        }

        uint256 total = bafTotals[lvl][player];
        unchecked { total += amount; }
        bafTotals[lvl][player] = total;

        _updateBafTop(lvl, player, total);
        emit BafFlipRecorded(player, lvl, amount, total);
    }

    /*+======================================================================+
      |                      BAF JACKPOT RESOLUTION                          |
      +======================================================================+
      |  Distributes ETH prize pool to various winner categories.            |
      |                                                                      |
      |  PRIZE DISTRIBUTION:                                                 |
      |  +-----------------------------------------------------------------+ |
      |  | 10% | Top BAF bettor for this level                             | |
      |  |  5% | Top coinflip bettor from last 24h window                  | |
      |  |  5% | Random pick: 3rd or 4th BAF slot                          | |
      |  |  5% | Far-future ticket holders (3% 1st / 2% 2nd by BAF score)  | |
      |  |  5% | Far-future ticket holders 2nd draw (3% 1st / 2% 2nd)      | |
      |  | 45% | Scatter 1st place (50 rounds x 4 multi-level trait tickets) | |
      |  | 25% | Scatter 2nd place (50 rounds x 4 multi-level trait tickets) | |
      |  +-----------------------------------------------------------------+ |
      |                                                                      |
      |  ELIGIBILITY:                                                        |
      |  * Non-zero address only (no streak requirement)                     |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • VRF-derived randomness for all random selections                  |
      |  • Entropy chained via keccak256 for independence                    |
      |  • Unfilled prizes returned via returnAmountWei                      |
      |  • winnerMask flags scatter winners for ticket routing               |
      +======================================================================+*/

    /// @notice Resolve the BAF jackpot for a level.
    /// @dev Distributes poolWei across multiple winner categories with eligibility checks.
    ///      Returns arrays of winners/amounts plus winnerMask for scatter ticket handling.
    ///      Clears leaderboard state after resolution.
    /// @param poolWei Total ETH prize pool for distribution.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return winners Array of winner addresses.
    /// @return amounts Array of prize amounts corresponding to winners.
    /// @return winnerMask Bitmask indicating scatter winners (high bits) for ticket routing.
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
        returns (address[] memory winners, uint256[] memory amounts, uint256 winnerMask, uint256 returnAmountWei)
    {
        uint256 P = poolWei;
        // Max distinct winners: 1 (top BAF) + 1 (top flip) + 1 (pick) + 4 (far-future x2) + 50 + 50 (scatter) = 107.
        address[] memory tmpW = new address[](107);
        uint256[] memory tmpA = new uint256[](107);
        uint256 n;
        uint256 toReturn;
        uint256 mask;

        uint256 entropy = rngWord;
        uint256 salt;

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
            entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
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

        // Slice D: 5% to far-future ticket holders (3% 1st / 2% 2nd by BAF score).
        {
            unchecked { ++salt; }
            entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
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
                uint256 score = _bafScore(cand, lvl);
                if (score > bestScore || best == address(0)) {
                    second = best;
                    secondScore = bestScore;
                    best = cand;
                    bestScore = score;
                } else if ((score > secondScore || second == address(0)) && cand != best) {
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
        }

        // Slice D2: 5% to far-future ticket holders, 2nd independent draw (3% 1st / 2% 2nd by BAF score).
        {
            unchecked { ++salt; }
            entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));
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
                uint256 score = _bafScore(cand, lvl);
                if (score > bestScore || best == address(0)) {
                    second = best;
                    secondScore = bestScore;
                    best = cand;
                    bestScore = score;
                } else if ((score > secondScore || second == address(0)) && cand != best) {
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
        }

        // Scatter slice: 200 total draws (4 tickets * 50 rounds). Per round, take top-2 by BAF score.
        // Game applies special ticket handling for the last BAF_SCATTER_TICKET_WINNERS scatter winners via `winnerMask`.
        {
            // Slice E: scatter tickets from trait sampler so casual participants can land smaller cuts.
            uint256 scatterTop = (P * 45) / 100;
            uint256 scatterSecond = P / 4;
            address[50] memory firstWinners;
            address[50] memory secondWinners;
            uint256 firstCount;
            uint256 secondCount;
            uint256 scatterStart = n;

            bool isCentury = (lvl % 100 == 0);

            // Fixed rounds of 4-ticket sampling to keep gas bounded per call.
            for (uint8 round = 0; round < BAF_SCATTER_ROUNDS; ) {
                unchecked {
                    ++salt;
                }
                entropy = uint256(keccak256(abi.encodePacked(entropy, salt)));

                // Level targeting varies by BAF type:
                // Non-x00: 20 rounds lvl+1, 10 each lvl+2/+3/+4
                // x00:     4 rounds lvl+1, 4 each lvl+2/+3, 38 random from past 99
                uint24 targetLvl;
                if (isCentury) {
                    if (round < 4) targetLvl = lvl + 1;
                    else if (round < 8) targetLvl = lvl + 2;
                    else if (round < 12) targetLvl = lvl + 3;
                    else {
                        uint24 maxBack = lvl > 99 ? 99 : lvl - 1;
                        targetLvl = maxBack > 0 ? lvl - 1 - uint24(entropy % maxBack) : lvl;
                    }
                } else {
                    if (round < 20) targetLvl = lvl + 1;
                    else if (round < 30) targetLvl = lvl + 2;
                    else if (round < 40) targetLvl = lvl + 3;
                    else targetLvl = lvl + 4;
                }

                (, address[] memory tickets) = degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy);

                // Pick up to 4 tickets from the sampled set.
                uint256 limit = tickets.length;
                if (limit > 4) limit = 4;

                address best;
                uint256 bestScore;
                address second;
                uint256 secondScore;

                for (uint256 i; i < limit; ) {
                    address cand = tickets[i];
                    uint256 score = _bafScore(cand, lvl);
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

            if (firstCount == 0) {
                toReturn += scatterTop;
            } else {
                uint256 per = scatterTop / firstCount;
                uint256 rem = scatterTop - per * firstCount;
                toReturn += rem;
                if (per != 0) {
                    for (uint256 i; i < firstCount; ) {
                        tmpW[n] = firstWinners[i];
                        tmpA[n] = per;
                        unchecked {
                            ++n;
                            ++i;
                        }
                    }
                }
            }

            if (secondCount == 0) {
                toReturn += scatterSecond;
            } else {
                uint256 per2 = scatterSecond / secondCount;
                uint256 rem2 = scatterSecond - per2 * secondCount;
                toReturn += rem2;
                if (per2 != 0) {
                    for (uint256 i; i < secondCount; ) {
                        tmpW[n] = secondWinners[i];
                        tmpA[n] = per2;
                        unchecked {
                            ++n;
                            ++i;
                        }
                    }
                }
            }

            uint256 scatterCount = n - scatterStart;
            if (scatterCount != 0) {
                uint256 targetSpecialCount = scatterCount < BAF_SCATTER_TICKET_WINNERS
                    ? scatterCount
                    : BAF_SCATTER_TICKET_WINNERS;
                for (uint256 i; i < targetSpecialCount; ) {
                    uint256 idx = (scatterStart + scatterCount - 1) - i;
                    mask |= (uint256(1) << (BAF_SCATTER_MASK_OFFSET + idx));
                    unchecked {
                        ++i;
                    }
                }
            }
        }

        winners = tmpW;
        amounts = tmpA;
        assembly ("memory-safe") {
            mstore(winners, n)
            mstore(amounts, n)
        }

        winnerMask = mask;

        // Clean up leaderboard state for this level
        _clearBafTop(lvl);
        unchecked { ++bafEpoch[lvl]; }
        lastBafResolvedDay = degenerusGame.currentDayView();
        return (winners, amounts, winnerMask, toReturn);
    }

    /*+======================================================================+
      |                      INTERNAL HELPER FUNCTIONS                       |
      +======================================================================+
      |  Utility functions for bucket packing and scoring.                    |
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
    /// @return Accumulated coinflip total (0 if player not in this level).
    function _bafScore(address player, uint24 lvl) private view returns (uint256) {
        if (bafPlayerEpoch[lvl][player] != bafEpoch[lvl]) return 0;
        return bafTotals[lvl][player];
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
        uint8 len = bafTopLen[lvl];

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

        // Case 1: Player already on board - update and re-sort if improved
        if (existing < 4) {
            if (score <= board[existing].score) return; // No improvement
            board[existing].score = score;
            // Bubble up if score increased
            uint8 idx = existing;
            while (idx > 0 && board[idx].score > board[idx - 1].score) {
                PlayerScore memory tmp = board[idx - 1];
                board[idx - 1] = board[idx];
                board[idx] = tmp;
                unchecked {
                    --idx;
                }
            }
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
            bafTopLen[lvl] = len + 1;
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
        uint8 len = bafTopLen[lvl];
        if (idx >= len) return (address(0), 0);
        PlayerScore memory entry = bafTop[lvl][idx];
        return (entry.player, entry.score);
    }

    /// @dev Clear leaderboard state for a level after jackpot resolution.
    /// @param lvl Level number.
    function _clearBafTop(uint24 lvl) private {
        uint8 len = bafTopLen[lvl];
        if (len != 0) {
            delete bafTopLen[lvl];
        }
        for (uint8 i; i < len; ) {
            delete bafTop[lvl][i];
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                         VIEW FUNCTIONS                               |
      +======================================================================+*/

    /// @notice Day index of the most recent BAF jackpot resolution.
    function getLastBafResolvedDay() external view returns (uint48) {
        return lastBafResolvedDay;
    }
}
