// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

/**
 * @title BurnieClaimLibrary
 * @notice External library to reduce BurnieCoin contract size
 * @dev Contains claim processing logic for daily and afKing flips
 */
library BurnieClaimLibrary {
    // Constants matching BurnieCoin
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 0.01 ether;
    uint32 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 45;

    struct CoinflipDayResult {
        uint16 rewardPercent;
        bool win;
    }

    struct ClaimParams {
        bool isDaily;
        address player;
        bool deepAutoRebuy;
        uint48 latest;
        uint48 start;
        bool rebuyActive;
        uint256 keepMultiple;
        uint256 carry;
        bool afKingMode;
        bool dailyOnlyPenalty;
        bool hasDeityPass;
        uint48 windowSize;
        uint48 minClaimable;
        IDegenerusGame degenerusGame;
        IDegenerusJackpots jackpots;
        IWrappedWrappedXRP wwxrp;
    }

    struct ClaimState {
        uint256 mintable;
        uint256 winningBafCredit;
        uint256 lossCount;
        uint256 carry;
        uint48 processed;
    }

    /**
     * @notice Process claim loop for daily or afKing flips
     * @param params Claim parameters
     * @param coinflipBalance Daily flip balance mapping
     * @param afKingBalance AfKing flip balance mapping
     * @param coinflipResults Daily flip results
     * @param afKingResults AfKing flip results
     * @return state Updated claim state
     */
    function processClaimLoop(
        ClaimParams memory params,
        mapping(uint48 => mapping(address => uint256)) storage coinflipBalance,
        mapping(uint48 => mapping(address => uint256)) storage afKingBalance,
        mapping(uint48 => CoinflipDayResult) storage coinflipResults,
        mapping(uint48 => CoinflipDayResult) storage afKingResults
    ) external returns (ClaimState memory state) {
        bool deep = params.deepAutoRebuy && params.rebuyActive;

        uint48 cursor;
        unchecked { cursor = params.start + 1; }
        state.processed = params.start;
        state.carry = params.carry;

        uint32 remaining;
        if (deep) {
            uint48 available = params.latest > params.start ? params.latest - params.start : 0;
            uint48 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX ? AUTO_REBUY_OFF_CLAIM_DAYS_MAX : available;
            remaining = uint32(cap);
        } else {
            remaining = uint32(params.windowSize);
        }

        // Main claim loop
        while (remaining != 0 && cursor <= params.latest) {
            CoinflipDayResult storage result = params.isDaily
                ? coinflipResults[cursor]
                : afKingResults[cursor];

            if (result.rewardPercent == 0 && !result.win) break;

            uint256 stake = params.isDaily
                ? coinflipBalance[cursor][params.player]
                : afKingBalance[cursor][params.player];

            if (stake != 0) {
                uint256 payout;
                if (result.win) {
                    unchecked {
                        uint256 bonusPercent = uint256(result.rewardPercent);
                        payout = stake + (stake * bonusPercent) / 100;
                    }
                    if (params.rebuyActive) {
                        state.carry += payout;
                    } else {
                        state.mintable += payout;
                    }
                    if (!params.hasDeityPass && !params.dailyOnlyPenalty) {
                        state.winningBafCredit += payout;
                    }
                } else {
                    state.lossCount++;
                }

                // Clear stake
                if (params.isDaily) {
                    coinflipBalance[cursor][params.player] = 0;
                } else {
                    afKingBalance[cursor][params.player] = 0;
                }
            }

            state.processed = cursor;
            unchecked {
                cursor++;
                remaining--;
            }
        }

        // Handle auto-rebuy carry and keep-multiple logic
        if (params.rebuyActive && state.carry != 0) {
            uint256 reservable = params.keepMultiple;
            if (state.carry > reservable) {
                uint256 mintNow = state.carry - reservable;
                state.mintable += mintNow;
                state.carry = reservable;
            }
        }

        return state;
    }

    /**
     * @notice Finalize claim by crediting BAF and awarding WWXRP
     * @param player Player address
     * @param winningBafCredit BAF credit amount
     * @param lossCount Number of losses
     * @param isDaily Whether this is daily flips
     * @param jackpots Jackpots contract
     * @param wwxrp WWXRP contract
     * @param degenerusGame Game contract
     */
    function finalizeClaim(
        address player,
        uint256 winningBafCredit,
        uint256 lossCount,
        bool isDaily,
        IDegenerusJackpots jackpots,
        IWrappedWrappedXRP wwxrp,
        IDegenerusGame degenerusGame
    ) external {
        if (winningBafCredit != 0) {
            uint24 level = degenerusGame.level();
            uint24 bafLvl = _bafBracketLevel(level);
            jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
        }

        if (isDaily && lossCount != 0) {
            wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
        }
    }

    /// @dev Calculate BAF bracket level (same as BurnieCoin)
    function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {
        if (lvl >= 200) return 200;
        if (lvl >= 100) return 100;
        if (lvl >= 50) return 50;
        if (lvl >= 25) return 25;
        if (lvl >= 10) return 10;
        return lvl;
    }
}
