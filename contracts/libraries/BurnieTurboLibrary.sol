// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

/**
 * @title BurnieTurboLibrary
 * @notice External library for turbo flip resolution logic
 * @dev Reduces BurnieCoin contract size by externalizing complex turbo logic
 */
library BurnieTurboLibrary {
    // Constants matching BurnieCoin
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint32 private constant TURBO_DECIMATOR_PAYOUT_BPS = 90_000;
    uint32 private constant TURBO_DECIMATOR_PAYOUT_BPS_MAX = 100_000;
    uint8 private constant TURBO_DECIMATOR_LANES = 10;
    uint16 private constant ACTIVITY_SCORE_MAX_NO_EXTRA_BPS = 10_500;
    bytes32 private constant TURBO_FLIP_PAYOUT_TAG = keccak256("TURBO_FLIP_PAYOUT");

    event TurboFlipResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    event TurboDecimatorResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 winningLane,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    event TurboDecimatorDgnrsResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 winningLane,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    struct TurboFlipResult {
        uint256 totalPayout;
        uint256 bafCredit;
    }

    /**
     * @notice Resolve turbo flip stakes
     * @param caller Player address
     * @param lootboxIndex Lootbox RNG index
     * @param amountPerFlip Amount per flip
     * @param flipCount Number of flips
     * @param betOnLoss Whether betting on loss
     * @param rngWord RNG word
     * @param hasDeityPass Whether player has deity pass
     * @param jackpots Jackpots contract
     * @param degenerusGame Game contract
     * @return result Flip resolution result
     */
    function resolveTurboFlips(
        address caller,
        uint48 lootboxIndex,
        uint256 amountPerFlip,
        uint8 flipCount,
        bool betOnLoss,
        uint256 rngWord,
        bool hasDeityPass,
        IDegenerusJackpots jackpots,
        IDegenerusGame degenerusGame
    ) external returns (TurboFlipResult memory result) {
        uint256 payoutSeed = uint256(
            keccak256(
                abi.encodePacked(
                    TURBO_FLIP_PAYOUT_TAG,
                    rngWord,
                    lootboxIndex
                )
            )
        );

        for (uint256 i = 0; i < flipCount; ) {
            uint256 flipSeed = uint256(keccak256(abi.encodePacked(rngWord, lootboxIndex, i)));
            bool flipWin = (flipSeed % 2) == 0;
            if (betOnLoss) flipWin = !flipWin;

            uint16 rewardBps;
            uint256 payout;
            if (flipWin) {
                payoutSeed = uint256(keccak256(abi.encodePacked(payoutSeed)));
                rewardBps = _turboFlipRewardBps(payoutSeed);
                uint32 payoutBps = _turboPayoutBps(
                    caller,
                    rewardBps,
                    30_000,
                    jackpots,
                    degenerusGame
                );
                payout = (amountPerFlip * uint256(payoutBps)) / BPS_DENOMINATOR;
                result.totalPayout += payout;

                if (!hasDeityPass) {
                    result.bafCredit += payout;
                }
            }

            emit TurboFlipResolved(caller, lootboxIndex, flipWin, payout, rewardBps);

            unchecked { i++; }
        }

        return result;
    }

    /**
     * @notice Resolve decimator stake (BURNIE or DGNRS)
     * @param caller Player address
     * @param lootboxIndex Lootbox index
     * @param stakeAmount Stake amount
     * @param playerLane Player's lane
     * @param rngWord RNG word
     * @param isDgnrs Whether this is DGNRS stake
     * @param jackpots Jackpots contract
     * @param degenerusGame Game contract
     * @return payout Amount won
     */
    function resolveDecimatorStake(
        address caller,
        uint48 lootboxIndex,
        uint256 stakeAmount,
        uint8 playerLane,
        uint256 rngWord,
        bool isDgnrs,
        IDegenerusJackpots jackpots,
        IDegenerusGame degenerusGame
    ) external returns (uint256 payout) {
        if (stakeAmount == 0) return 0;

        uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, lootboxIndex, uint256(2))));
        uint8 winningLane = uint8(seed % TURBO_DECIMATOR_LANES);
        bool win = playerLane == winningLane;

        uint32 payoutBps = TURBO_DECIMATOR_PAYOUT_BPS;
        if (win) {
            payoutBps = _turboPayoutBps(
                caller,
                TURBO_DECIMATOR_PAYOUT_BPS,
                TURBO_DECIMATOR_PAYOUT_BPS_MAX,
                jackpots,
                degenerusGame
            );
            payout = (stakeAmount * uint256(payoutBps)) / BPS_DENOMINATOR;
        }

        if (isDgnrs) {
            emit TurboDecimatorDgnrsResolved(
                caller,
                lootboxIndex,
                winningLane,
                win,
                payout,
                payoutBps
            );
        } else {
            emit TurboDecimatorResolved(
                caller,
                lootboxIndex,
                winningLane,
                win,
                payout,
                payoutBps
            );
        }

        return payout;
    }

    /// @dev Calculate turbo flip reward BPS (same logic as BurnieCoin)
    function _turboFlipRewardBps(uint256 seed) private pure returns (uint16) {
        uint256 roll = seed % 100;
        if (roll < 50) return 5_000;
        if (roll < 95) {
            uint256 range = 15_000 - 7_800;
            uint256 position = (seed / 100) % range;
            return uint16(7_800 + position);
        }
        return 15_000;
    }

    /// @dev Calculate turbo payout BPS with activity score bonus
    function _turboPayoutBps(
        address player,
        uint32 baseBps,
        uint32 maxBps,
        IDegenerusJackpots,
        IDegenerusGame degenerusGame
    ) private view returns (uint32) {
        if (maxBps <= baseBps) return baseBps;

        uint256 multBps = degenerusGame.playerActivityScore(player);
        if (multBps <= BPS_DENOMINATOR) return baseBps;

        uint256 capped = multBps;
        if (capped > ACTIVITY_SCORE_MAX_NO_EXTRA_BPS) {
            capped = ACTIVITY_SCORE_MAX_NO_EXTRA_BPS;
        }
        uint256 bonusBps = capped - BPS_DENOMINATOR;
        uint256 maxBonusBps = uint256(ACTIVITY_SCORE_MAX_NO_EXTRA_BPS) - BPS_DENOMINATOR;

        uint256 adjustedBps = uint256(baseBps) +
            (uint256(maxBps - baseBps) * bonusBps) / maxBonusBps;
        if (adjustedBps > maxBps) return maxBps;
        return uint32(adjustedBps);
    }
}
