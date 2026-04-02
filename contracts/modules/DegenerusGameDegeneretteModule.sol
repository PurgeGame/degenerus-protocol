// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

/// @notice Minimal interface for WWXRP game burn/mint operations.
interface IWrappedWrappedXRP {
    /// @notice Mints WWXRP tokens as a prize to the recipient.
    /// @param to The address to receive the minted tokens.
    /// @param amount The amount of tokens to mint.
    function mintPrize(address to, uint256 amount) external;

    /// @notice Burns WWXRP tokens from a player for game participation.
    /// @param from The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burnForGame(address from, uint256 amount) external;
}

/**
 * @title DegenerusGameDegeneretteModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling Degenerette symbol-roll bets.
 * @dev Uses lootbox RNG index/word for randomness. All storage reads/writes operate
 *      on the inherited DegenerusGameStorage. Supports ETH, BURNIE, and WWXRP currencies.
 */
contract DegenerusGameDegeneretteModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    /// @notice Thrown when RNG word is not yet available for bet resolution.
    error RngNotReady();

    /// @notice Thrown when caller is not approved to act on behalf of player.
    error NotApproved();

    /// @notice Thrown when bet parameters are invalid (zero amount, below minimum, invalid spec, etc.).
    error InvalidBet();

    /// @notice Thrown when an unsupported currency type is specified.
    error UnsupportedCurrency();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a bet is placed (either mode).
    /// @param player The address that placed the bet.
    /// @param index The lootbox RNG index this bet is tied to.
    /// @param betId The unique bet identifier for this player.
    /// @param packed The packed bet data.
    event BetPlaced(
        address indexed player,
        uint48 indexed index,
        uint64 indexed betId,
        uint256 packed
    );

    /// @notice Emitted when Full Ticket bets are resolved.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param ticketCount Number of spins resolved.
    /// @param totalPayout Total payout across all tickets.
    /// @param resultTicket The spin-0 result ticket (additional spin results are derived per spinIndex).
    event FullTicketResolved(
        address indexed player,
        uint64 indexed betId,
        uint8 ticketCount,
        uint256 totalPayout,
        uint32 resultTicket
    );

    /// @notice Emitted for each individual Full Ticket result.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param ticketIndex Index of this ticket (0 to count-1).
    /// @param playerTicket The player's ticket traits.
    /// @param matches Number of attribute matches (0-8).
    /// @param payout Payout for this ticket.
    event FullTicketResult(
        address indexed player,
        uint64 indexed betId,
        uint8 ticketIndex,
        uint32 playerTicket,
        uint8 matches,
        uint256 payout
    );

    /// @notice Emitted when ETH payout exceeds pool cap and excess is converted to lootbox.
    /// @param player The player address.
    /// @param cappedEthPayout The ETH payout after capping.
    /// @param excessConverted The excess ETH value converted to lootbox rewards.
    event PayoutCapped(
        address indexed player,
        uint256 cappedEthPayout,
        uint256 excessConverted
    );

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Reverts with the provided reason bytes from a delegatecall failure.
    /// @param reason The revert reason bytes from the failed call.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Reverts if msg.sender is not the player and not an approved operator.
    /// @param player The player address to check approval for.
    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    /// @dev Resolves the player address, defaulting to msg.sender if zero address is passed.
    ///      Validates operator approval if player differs from msg.sender.
    /// @param player The player address (or zero for msg.sender).
    /// @return resolved The resolved player address.
    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) {
            _requireApproved(player);
        }
        return player;
    }

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    /// @dev Reference to the WWXRP token contract for burn/mint operations.
    IWrappedWrappedXRP internal constant wwxrp =
        IWrappedWrappedXRP(ContractAddresses.WWXRP);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Activity score threshold for mid-tier ROI (75% in bps).
    uint16 private constant ACTIVITY_SCORE_MID_BPS = 7_500;

    /// @dev Activity score threshold for high-tier ROI (255% in bps).
    uint16 private constant ACTIVITY_SCORE_HIGH_BPS = 25_500;

    /// @dev Maximum activity score cap (305% in bps, deity pass theoretical max).
    uint16 private constant ACTIVITY_SCORE_MAX_BPS = 30_500;

    /// @dev Minimum ROI in basis points (90%).
    uint16 private constant ROI_MIN_BPS = 9_000;

    /// @dev Mid-tier ROI in basis points (95%).
    uint16 private constant ROI_MID_BPS = 9_500;

    /// @dev High-tier ROI in basis points (99.5%).
    uint16 private constant ROI_HIGH_BPS = 9_950;

    /// @dev Maximum ROI in basis points (99.9%).
    uint16 private constant ROI_MAX_BPS = 9_990;

    /// @dev Bonus ROI for ETH bets in basis points (+5%), redistributed to high buckets.
    uint16 private constant ETH_ROI_BONUS_BPS = 500;

    /// @dev WWXRP high-value ROI base in basis points (90%).
    ///      Used as the target ROI for full-ticket bonus redistribution
    ///      (matches 5-8 + jackpot).
    uint16 private constant WWXRP_HIGH_ROI_BASE_BPS = 9_000;

    /// @dev WWXRP high-value ROI max in basis points (109.9%).
    uint16 private constant WWXRP_HIGH_ROI_MAX_BPS = 10_990;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IStakedDegenerusStonk private constant sdgnrs =
        IStakedDegenerusStonk(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool)
    uint16 private constant DEGEN_DGNRS_6_BPS = 400; // 4% per ETH
    uint16 private constant DEGEN_DGNRS_7_BPS = 800; // 8% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 1500; // 15% per ETH

    /// @dev Currency type identifier for ETH.
    uint8 private constant CURRENCY_ETH = 0;

    /// @dev Currency type identifier for BURNIE token.
    uint8 private constant CURRENCY_BURNIE = 1;

    /// @dev Currency type identifier for WWXRP token.
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev Minimum bet amount for ETH (0.005 ETH on mainnet).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;

    /// @dev Minimum bet amount for BURNIE (100 tokens with 18 decimals).
    uint256 private constant MIN_BET_BURNIE = 100 ether;

    /// @dev Minimum bet amount for WWXRP (1 token with 18 decimals).
    uint256 private constant MIN_BET_WWXRP = 1 ether;

    /// @dev Maximum spins per bet (encoded as ticketCount in packed bet).
    uint8 private constant MAX_SPINS_PER_BET = 10;

    // -------------------------------------------------------------------------
    // Quick Play Constants
    // -------------------------------------------------------------------------

    /// @dev Salt for quick play ticket generation.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    /// @dev Base payout multipliers in centi-x (divide by 100 for multiplier).
    ///      Index = match count. Base payouts at 100% ROI: 0x, 0x, 1.90x, 4.75x, 15x, 42.5x, 195x, 1000x, 100000x
    ///      Scaled by activity score ROI (90%-99.9%).
    ///      Packed as 32 bits each: [matches*32 .. matches*32+31]
    ///      Total EV at 100% ROI: 99.99% (just under 100%)
    uint256 private constant QUICK_PLAY_BASE_PAYOUTS_PACKED =
        (uint256(0) << 0) | // 0 matches: 0x
            (uint256(0) << 32) | // 1 match: 0x
            (uint256(190) << 64) | // 2 matches: 1.90x base
            (uint256(475) << 96) | // 3 matches: 4.75x base
            (uint256(1500) << 128) | // 4 matches: 15x base
            (uint256(4250) << 160) | // 5 matches: 42.5x base
            (uint256(19500) << 192) | // 6 matches: 195x base
            (uint256(100000) << 224); // 7 matches: 1,000x base

    /// @dev Base payout for 8 matches (jackpot). 10,000,000 centi-x = 100,000x at 100% ROI.
    uint256 private constant QUICK_PLAY_BASE_PAYOUT_8_MATCHES = 10_000_000;

    // -------------------------------------------------------------------------
    // WWXRP Bonus EV Redistribution (Full Ticket)
    // -------------------------------------------------------------------------
    //
    // Bonus EV for WWXRP high-activity bettors is concentrated into unlikely
    // outcomes by scaling the bonus ROI portion per match bucket:
    //   - 10% of bonus EV → bucket 5
    //   - 30% of bonus EV → each of buckets 6, 7, 8
    //
    // Factors below are derived from uniform-ticket probabilities (all weights=10)
    // and the new payout table (0, 0, 1.78x, 4.75x, 15x, 54x, 248x, 1280x, 100000x).
    uint256 private constant WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
    uint256 private constant WWXRP_BONUS_FACTOR_BUCKET5 = 1_531_388;
    uint256 private constant WWXRP_BONUS_FACTOR_BUCKET6 = 13_016_797;
    uint256 private constant WWXRP_BONUS_FACTOR_BUCKET7 = 57_745_766;
    uint256 private constant WWXRP_BONUS_FACTOR_BUCKET8 = 30_027_799;

    // -------------------------------------------------------------------------
    // Packed Bet Layout
    // -------------------------------------------------------------------------
    //
    // MODE 1: Full Ticket (4 traits, match-based payouts)
    // packed (uint256):
    // [0]        mode (1 bit): 1=full ticket
    // [1]        isRandom (1 bit): must be 0 (no random tickets)
    // [2..33]    customTicket (32 bits): packed traits (required)
    // [34..41]   ticketCount (8 bits): spin count (1..MAX_SPINS_PER_BET)
    // [42..43]   currency (2 bits)
    // [44..171]  amountPerTicket (128 bits)
    // [172..219] index (48 bits)
    // [220..235] activityScore (16 bits)
    // [236]      hasCustom (1 bit): must be 1
    // [237..239] hero (3 bits): [0]=enabled, [1..2]=quadrant (0-3)
    //
    // EXACT EV NORMALIZATION (Per-Outcome Product-of-Ratios):
    // Full Ticket payouts are adjusted to ensure EXACT equal EV regardless of trait
    // selection. For each quadrant, the ratio P(uniform outcome) / P(actual outcome)
    // is computed, and the product of all 4 ratios is the payout multiplier.
    //
    // Per quadrant (color weight wC, symbol weight wS, total weight space = 75):
    //   Both match:  num *= 100,   den *= wC * wS
    //   One match:   num *= 1300,  den *= 75*(wC+wS) - 2*wC*wS
    //   No match:    num *= 4225,  den *= (75-wC) * (75-wS)
    //
    // This gives mathematically exact equal EV for all possible ticket configurations.
    //
    // -------------------------------------------------------------------------

    /// @dev Bet mode: full ticket (4 traits, match payouts).
    uint8 private constant MODE_FULL_TICKET = 1;

    // Full Ticket bit positions
    uint256 private constant FT_TICKET_SHIFT = 2;
    uint256 private constant FT_COUNT_SHIFT = 34;
    uint256 private constant FT_CURRENCY_SHIFT = 42;
    uint256 private constant FT_AMOUNT_SHIFT = 44;
    uint256 private constant FT_INDEX_SHIFT = 172;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;
    uint256 private constant FT_HAS_CUSTOM_SHIFT = 236;
    uint256 private constant FT_HERO_SHIFT = 237; // 3 bits: [0]=enabled, [1..2]=quadrant

    // Hero quadrant multipliers (EV-neutral per-match-count)
    // When hero quadrant both-matches: boost. Otherwise: penalty.
    // Constraint: P(hero|M) * boost(M) + (1-P(hero|M)) * penalty = HERO_SCALE for each M.
    // Penalty is 5% (9500/10000). Boost varies per M=2..7, packed 16 bits each.
    // M=2: 23500, M=3: 14166, M=4: 11833, M=5: 10900, M=6: 10433, M=7: 10166
    uint256 private constant HERO_BOOST_PACKED = 0x27b628c12a942e3937565bcc;
    uint16 private constant HERO_PENALTY = 9500;
    uint16 private constant HERO_SCALE = 10_000;

    // Common masks
    uint256 private constant MASK_2 = 0x3;
    uint256 private constant MASK_3 = 0x7;
    uint256 private constant MASK_8 = 0xFF;
    uint256 private constant MASK_16 = 0xFFFF;
    uint256 private constant MASK_32 = 0xFFFFFFFF;
    uint256 private constant MASK_48 = (uint256(1) << 48) - 1;
    uint256 private constant MASK_128 = (uint256(1) << 128) - 1;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// @notice Places Full Ticket bets (4 traits, match-based payouts).
    /// @dev Single chosen-attribute ticket only (no random).
    ///      ticketCount is treated as "spin count": each spin resolves independently but shares
    ///      the same lootbox RNG index/word (derived per spin).
    /// @param player The player address (use zero address for msg.sender).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1..MAX_SPINS_PER_BET).
    /// @param customTicket Custom packed traits. Format: [D:24-31][C:16-23][B:8-15][A:0-7].
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable {
        _placeDegeneretteBet(
            _resolvePlayer(player),
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        );
    }

    /// @notice Places Full Ticket bets using pending affiliate Degenerette credit.
    /// @notice Resolves one or more pending bets for a player.
    /// @dev Requires RNG word to be available. Processes wins by minting tokens or crediting ETH.
    /// @param player The player address (use zero address for msg.sender).
    /// @param betIds Array of bet IDs to resolve.
    function resolveBets(address player, uint64[] calldata betIds) external {
        player = _resolvePlayer(player);
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            _resolveBet(player, betIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internal Bet Logic
    // -------------------------------------------------------------------------

    /// @dev Internal implementation for placing Full Ticket bets.
    function _placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) private {
        uint256 totalBet = _placeDegeneretteBetCore(
            player,
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        );

        _collectBetFunds(player, currency, totalBet, msg.value);

        // Quest progress for Degenerette bets (slot 1 only).
        if (currency == CURRENCY_ETH || currency == CURRENCY_BURNIE) {
            quests.handleDegenerette(
                player,
                totalBet,
                currency == CURRENCY_ETH
            );
        }
    }

    function _placeDegeneretteBetCore(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) private returns (uint256 totalBet) {
        if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET)
            revert InvalidBet();
        if (amountPerTicket == 0) revert InvalidBet();

        uint48 index = lootboxRngIndex;
        if (index == 0) revert E();
        if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();

        _validateMinBet(currency, amountPerTicket);

        totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        (uint32 questStreak, , , ) = questView.playerQuestStates(player);
        uint16 activityScore = uint16(
            _playerActivityScore(player, questStreak, level + 1)
        );

        // Pack the bet (isRandom=false, hasCustom=true always)
        uint256 packed = _packFullTicketBet(
            customTicket,
            ticketCount,
            currency,
            amountPerTicket,
            index,
            activityScore,
            heroQuadrant
        );

        uint64 nonce = degeneretteBetNonce[player];
        unchecked {
            ++nonce;
        }
        degeneretteBetNonce[player] = nonce;

        degeneretteBets[player][nonce] = packed;
        emit BetPlaced(player, index, nonce, packed);

        // Track hero wagers and player ETH stats (ETH bets only)
        if (currency == CURRENCY_ETH) {
            // 1. Daily hero symbol tracking
            if (heroQuadrant < 4) {
                uint48 day = _simulatedDayIndex();
                uint8 heroSymbol = uint8(customTicket >> (heroQuadrant * 8)) &
                    7;
                uint256 wagerUnit = totalBet / 1e12;
                if (wagerUnit > 0) {
                    uint256 wPacked = dailyHeroWagers[day][heroQuadrant];
                    uint256 shift = uint256(heroSymbol) * 32;
                    uint256 current = (wPacked >> shift) & 0xFFFFFFFF;
                    uint256 updated = current + wagerUnit;
                    if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF;
                    wPacked =
                        (wPacked & ~(uint256(0xFFFFFFFF) << shift)) |
                        (updated << shift);
                    dailyHeroWagers[day][heroQuadrant] = wPacked;
                }
            }

            // 2. Per-player per-level ETH wagered
            uint24 lvl = level;
            uint256 playerTotal = playerDegeneretteEthWagered[player][lvl] +
                totalBet;
            playerDegeneretteEthWagered[player][lvl] = playerTotal;
            uint256 topPacked = topDegeneretteByLevel[lvl];
            uint256 topAmount = topPacked >> 160;
            uint256 playerScaled = playerTotal / 1e12;
            if (playerScaled > topAmount) {
                topDegeneretteByLevel[lvl] =
                    (playerScaled << 160) |
                    uint256(uint160(player));
            }
        }
    }

    /// @dev Validates minimum bet amount for currency.
    function _validateMinBet(uint8 currency, uint128 amount) private pure {
        if (currency == CURRENCY_ETH) {
            if (uint256(amount) < MIN_BET_ETH) revert InvalidBet();
        } else if (currency == CURRENCY_BURNIE) {
            if (uint256(amount) < MIN_BET_BURNIE) revert InvalidBet();
        } else if (currency == CURRENCY_WWXRP) {
            if (uint256(amount) < MIN_BET_WWXRP) revert InvalidBet();
        } else {
            revert UnsupportedCurrency();
        }
    }

    /// @dev Processes bet funds (burn tokens, handle ETH, check pool).
    function _collectBetFunds(
        address player,
        uint8 currency,
        uint256 totalBet,
        uint256 ethPaid
    ) private {
        if (currency == CURRENCY_ETH) {
            // Check ETH payment covers bet, or pull from claimable
            if (ethPaid > totalBet) revert InvalidBet();
            if (ethPaid < totalBet) {
                uint256 fromClaimable = totalBet - ethPaid;
                if (claimableWinnings[player] <= fromClaimable)
                    revert InvalidBet();
                claimableWinnings[player] -= fromClaimable;
                claimablePool -= fromClaimable;
            }

            // Update pool and pending
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(totalBet));
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next, future + uint128(totalBet));
            }
            lootboxRngPendingEth += totalBet;
            // No max payout check needed: ETH payouts are capped at 10% of pool at distribution
            // time, so solvency is guaranteed regardless of jackpot size
        } else if (currency == CURRENCY_BURNIE) {
            coin.burnCoin(player, totalBet);
            lootboxRngPendingBurnie += totalBet;
        } else if (currency == CURRENCY_WWXRP) {
            wwxrp.burnForGame(player, totalBet);
        }
    }

    /// @dev Resolves a bet (determines mode from packed data).
    function _resolveBet(address player, uint64 betId) private {
        uint256 packed = degeneretteBets[player][betId];
        if (packed == 0) revert InvalidBet();

        _resolveFullTicketBet(player, betId, packed);
    }

    /// @dev Resolves a Full Ticket bet.
    function _resolveFullTicketBet(
        address player,
        uint64 betId,
        uint256 packed
    ) private {
        // Decode packed bet
        uint32 customTicket = uint32((packed >> FT_TICKET_SHIFT) & MASK_32);
        uint8 ticketCount = uint8((packed >> FT_COUNT_SHIFT) & MASK_8);
        uint8 currency = uint8((packed >> FT_CURRENCY_SHIFT) & MASK_2);
        uint128 amountPerTicket = uint128(
            (packed >> FT_AMOUNT_SHIFT) & MASK_128
        );
        uint48 index = uint48((packed >> FT_INDEX_SHIFT) & MASK_48);
        uint16 activityScore = uint16((packed >> FT_ACTIVITY_SHIFT) & MASK_16);
        uint256 heroBits = (packed >> FT_HERO_SHIFT) & MASK_3;
        bool heroEnabled = (heroBits & 1) != 0;
        uint8 heroQuadrant = uint8(heroBits >> 1);

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        delete degeneretteBets[player][betId];

        uint256 roiBps = _roiBpsFromScore(activityScore);
        // WWXRP high-value ROI target for bonus redistribution (0 if not WWXRP)
        uint256 wwxrpHighRoi = (currency == CURRENCY_WWXRP)
            ? _wwxrpHighValueRoi(activityScore)
            : 0;

        uint32 playerTicket = customTicket;

        uint256 totalPayout;
        uint32 firstResultTicket;

        for (uint8 spinIdx; spinIdx < ticketCount; ) {
            // Spin results are derived deterministically from the lootbox RNG word + index.
            // For backwards compatibility, spin 0 uses the legacy seed (no spinIdx mixed in).
            uint256 resultSeed = spinIdx == 0
                ? uint256(
                    keccak256(abi.encodePacked(rngWord, index, QUICK_PLAY_SALT))
                )
                : uint256(
                    keccak256(
                        abi.encodePacked(
                            rngWord,
                            index,
                            spinIdx,
                            QUICK_PLAY_SALT
                        )
                    )
                );
            uint32 resultTicket = DegenerusTraitUtils.packedTraitsFromSeed(
                resultSeed
            );
            if (spinIdx == 0) {
                firstResultTicket = resultTicket;
            }

            // Count matches
            uint8 matches = _countMatches(playerTicket, resultTicket);

            // Calculate payout (includes per-outcome rarity adjustment for equal EV)
            uint256 payout = _fullTicketPayout(
                playerTicket,
                resultTicket,
                matches,
                currency,
                amountPerTicket,
                roiBps,
                wwxrpHighRoi,
                heroEnabled,
                heroQuadrant
            );

            emit FullTicketResult(
                player,
                betId,
                spinIdx,
                playerTicket,
                matches,
                payout
            );

            if (payout != 0) {
                totalPayout += payout;

                // Ensure each ETH win resolves into an independent lootbox outcome
                // (avoid identical lootbox results when multiple spins share the same payout amount).
                uint256 lootboxWord = spinIdx == 0
                    ? rngWord
                    : uint256(
                        keccak256(
                            abi.encodePacked(
                                rngWord,
                                index,
                                spinIdx,
                                bytes1(0x4c)
                            )
                        )
                    ); // 'L'
                _distributePayout(player, currency, payout, lootboxWord);
            }

            // Award sDGNRS from Reward pool on 6+ match ETH bets
            if (currency == CURRENCY_ETH && matches >= 6) {
                _awardDegeneretteDgnrs(player, amountPerTicket, matches);
            }

            unchecked {
                ++spinIdx;
            }
        }

        emit FullTicketResolved(
            player,
            betId,
            ticketCount,
            totalPayout,
            firstResultTicket
        );
    }

    /// @dev Distributes payout to player. ETH payouts: 25% as ETH (capped at 10% of pool),
    ///      75% + any excess above cap converted to lootbox rewards.
    /// @param player The player to receive the payout.
    /// @param currency The currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param payout The payout amount.
    /// @param rngWord The RNG word for lootbox conversion (only used for ETH).
    function _distributePayout(
        address player,
        uint8 currency,
        uint256 payout,
        uint256 rngWord
    ) private {
        if (currency == CURRENCY_ETH) {
            // Split: 25% as ETH, 75% as lootbox
            uint256 ethPortion = payout / 4;
            uint256 lootboxPortion = payout - ethPortion;

            if (prizePoolFrozen) {
                // During freeze, route ETH payouts through the pending pool side-channel
                // (matching the bet-placement pattern at L558-561). The live futurePrizePool
                // snapshot that advanceGame/runRewardJackpots operates on is UNTOUCHED.
                // Pending future was credited by purchases during freeze; we debit it here.
                // No percentage cap: degenerette payouts are never a significant portion
                // of the total future pool, so the full ethPortion is debited directly.
                (uint128 pNext, uint128 pFuture) = _getPendingPools();

                // Solvency check: pending accumulator must cover the ETH payout
                if (uint256(pFuture) < ethPortion) revert E();

                // BAF-SAFE: _setPendingPools write completes before _addClaimableEth (no stale local).
                // DegeneretteModule._addClaimableEth has no auto-rebuy path (no pool writes).
                // _resolveLootboxDirect -> LootboxModule has zero pool writes.
                _setPendingPools(pNext, pFuture - uint128(ethPortion));
                _addClaimableEth(player, ethPortion);
            } else {
                // Unfrozen path: debit the live futurePrizePool directly (unchanged from original).
                uint256 pool = _getFuturePrizePool();

                // Cap ETH portion at 10% of pool, excess goes to lootbox
                // After capping, ethPortion <= pool*10% < pool, so no solvency check needed
                uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
                if (ethPortion > maxEth) {
                    lootboxPortion += ethPortion - maxEth;
                    ethPortion = maxEth;
                    emit PayoutCapped(player, ethPortion, lootboxPortion);
                }
                unchecked {
                    pool -= ethPortion;
                }
                _setFuturePrizePool(pool);
                _addClaimableEth(player, ethPortion);
            }

            // Convert 75% (+ any cap excess) to lootbox rewards
            if (lootboxPortion > 0) {
                _resolveLootboxDirect(player, lootboxPortion, rngWord);
            }
        } else if (currency == CURRENCY_BURNIE) {
            coin.mintForGame(player, payout);
        } else if (currency == CURRENCY_WWXRP) {
            wwxrp.mintPrize(player, payout);
        }
    }

    /// @dev Delegates to the lootbox open module to resolve lootbox rewards directly.
    ///      Applies activity-score EV multiplier (80-135%) to match regular lootbox opens.
    function _resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    player,
                    amount,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    // -------------------------------------------------------------------------
    // Packed Bet Helpers
    // -------------------------------------------------------------------------

    /// @dev Packs a Full Ticket bet for storage.
    function _packFullTicketBet(
        uint32 customTicket,
        uint8 ticketCount,
        uint8 currency,
        uint128 amountPerTicket,
        uint48 index,
        uint16 activityScore,
        uint8 heroQuadrant
    ) private pure returns (uint256 packed) {
        packed =
            uint256(MODE_FULL_TICKET) |
            (uint256(customTicket) << FT_TICKET_SHIFT) |
            (uint256(ticketCount) << FT_COUNT_SHIFT) |
            (uint256(currency) << FT_CURRENCY_SHIFT) |
            (uint256(amountPerTicket) << FT_AMOUNT_SHIFT) |
            (uint256(index) << FT_INDEX_SHIFT) |
            (uint256(activityScore) << FT_ACTIVITY_SHIFT) |
            (uint256(1) << FT_HAS_CUSTOM_SHIFT);
        // Hero quadrant: 3 bits at FT_HERO_SHIFT — [0]=enabled, [1..2]=quadrant
        if (heroQuadrant < 4) {
            packed |=
                (uint256(1) | (uint256(heroQuadrant) << 1)) <<
                FT_HERO_SHIFT;
        }
    }

    // -------------------------------------------------------------------------
    // Bet Math + Outcome
    // -------------------------------------------------------------------------

    /// @dev Computes per-outcome EV normalization multiplier as num/den.
    ///      For each quadrant, computes the ratio of uniform outcome probability
    ///      to actual outcome probability. The product of 4 ratios normalizes EV.
    ///
    ///      This gives EXACT equal EV for all possible ticket configurations,
    ///      accounting for different trait weights (8, 9, or 10 per bucket).
    ///
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @return num Numerator of the normalization ratio.
    /// @return den Denominator of the normalization ratio.
    function _evNormalizationRatio(
        uint32 playerTicket,
        uint32 resultTicket
    ) private pure returns (uint256 num, uint256 den) {
        unchecked {
            num = 1;
            den = 1;

            for (uint8 q = 0; q < 4; ) {
                uint256 shift = uint256(q) * 8;

                // Extract player color/symbol bucket indices
                uint256 pColor = (playerTicket >> (shift + 3)) & 7;
                uint256 pSymbol = (playerTicket >> shift) & 7;
                // Extract result color/symbol bucket indices
                uint256 rColor = (resultTicket >> (shift + 3)) & 7;
                uint256 rSymbol = (resultTicket >> shift) & 7;

                // Compute weights: bucket 0-3 = 10, 4-6 = 9, 7 = 8
                uint256 wC = 10 - (pColor > 3 ? 1 : 0) - (pColor > 6 ? 1 : 0);
                uint256 wS = 10 - (pSymbol > 3 ? 1 : 0) - (pSymbol > 6 ? 1 : 0);

                bool colorMatch = (pColor == rColor);
                bool symbolMatch = (pSymbol == rSymbol);

                if (colorMatch && symbolMatch) {
                    // Both match: uniform P = 100/5625, actual P = wC*wS/5625
                    num *= 100;
                    den *= wC * wS;
                } else if (colorMatch || symbolMatch) {
                    // One match: uniform P = 1300/5625
                    // actual P = [75*(wC+wS) - 2*wC*wS] / 5625
                    num *= 1300;
                    den *= 75 * (wC + wS) - 2 * wC * wS;
                } else {
                    // No match: uniform P = 4225/5625, actual P = (75-wC)*(75-wS)/5625
                    num *= 4225;
                    den *= (75 - wC) * (75 - wS);
                }

                ++q;
            }
        }
    }

    /// @dev Counts matching attributes between player and result tickets.
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @return matches Number of matching attributes (0-8).
    function _countMatches(
        uint32 playerTicket,
        uint32 resultTicket
    ) private pure returns (uint8 matches) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));

            // Color = bits 5-3 (category bucket, ignoring quadrant bits 7-6)
            uint8 pColor = (pQuad >> 3) & 7;
            uint8 rColor = (rQuad >> 3) & 7;
            if (pColor == rColor) {
                unchecked {
                    ++matches;
                }
            }

            // Symbol = bits 2-0 (sub-bucket)
            uint8 pSymbol = pQuad & 7;
            uint8 rSymbol = rQuad & 7;
            if (pSymbol == rSymbol) {
                unchecked {
                    ++matches;
                }
            }

            unchecked {
                ++q;
            }
        }
    }

    /// @dev Maps match count to a WWXRP bonus bucket.
    /// @return bucket 0=none, 5/6/7/8 for matches.
    function _wwxrpBonusBucket(
        uint8 matches
    ) private pure returns (uint8 bucket) {
        if (matches < 5) return 0;
        return matches; // 5,6,7,8
    }

    /// @dev Returns bonus ROI (bps) for a bucket given total bonus ROI (bps).
    function _wwxrpBonusRoiForBucket(
        uint8 bucket,
        uint256 bonusRoiBps
    ) private pure returns (uint256 bonusBps) {
        uint256 factor;
        if (bucket == 5) factor = WWXRP_BONUS_FACTOR_BUCKET5;
        else if (bucket == 6) factor = WWXRP_BONUS_FACTOR_BUCKET6;
        else if (bucket == 7) factor = WWXRP_BONUS_FACTOR_BUCKET7;
        else if (bucket == 8) factor = WWXRP_BONUS_FACTOR_BUCKET8;
        else return 0;

        bonusBps = (bonusRoiBps * factor) / WWXRP_BONUS_FACTOR_SCALE;
    }

    /// @dev Calculates Full Ticket payout based on matches and activity score ROI.
    ///      Applies per-outcome rarity multiplier to ensure equal EV regardless of trait selection.
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @param matches Number of attribute matches (0-8).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 3=WWXRP).
    /// @param betAmount The bet amount per ticket.
    /// @param roiBps The ROI in basis points (from activity score).
    /// @param wwxrpHighRoi The WWXRP high-value ROI (0 if not WWXRP).
    /// @return payout The payout amount (rarity-adjusted).
    function _fullTicketPayout(
        uint32 playerTicket,
        uint32 resultTicket,
        uint8 matches,
        uint8 currency,
        uint128 betAmount,
        uint256 roiBps,
        uint256 wwxrpHighRoi,
        bool heroEnabled,
        uint8 heroQuadrant
    ) private pure returns (uint256 payout) {
        uint256 basePayoutBps = _getBasePayoutBps(matches);

        // Bonus ROI is redistributed into 5+ match buckets
        uint256 effectiveRoi = roiBps;
        if (currency == CURRENCY_WWXRP && wwxrpHighRoi > roiBps) {
            uint8 bucket = _wwxrpBonusBucket(matches);
            if (bucket != 0) {
                uint256 bonusRoi = wwxrpHighRoi - roiBps;
                uint256 bonusBucket = _wwxrpBonusRoiForBucket(bucket, bonusRoi);
                effectiveRoi = roiBps + bonusBucket;
            }
        } else if (currency == CURRENCY_ETH) {
            uint8 bucket = _wwxrpBonusBucket(matches);
            if (bucket != 0) {
                uint256 bonusBucket = _wwxrpBonusRoiForBucket(
                    bucket,
                    ETH_ROI_BONUS_BPS
                );
                effectiveRoi = roiBps + bonusBucket;
            }
        }

        // Apply ROI scaling: payout = betAmount * basePayout * roiBps / 10000 / 100
        // basePayout is in "centi-x" (178 = 1.78x), roiBps is in bps (9000 = 90%)
        // Final: betAmount * basePayout * roiBps / 1_000_000
        payout =
            (uint256(betAmount) * basePayoutBps * effectiveRoi) /
            1_000_000;

        // Apply per-outcome EV normalization to ensure EXACT equal EV
        // regardless of trait selection. Product of 4 per-quadrant probability ratios.
        (uint256 evNum, uint256 evDen) = _evNormalizationRatio(
            playerTicket,
            resultTicket
        );
        payout = (payout * evNum) / evDen;

        // Hero quadrant: boost payout when hero quadrant both-matches, penalize otherwise.
        // EV-neutral per match count: P(hero|M)*boost(M) + (1-P(hero|M))*penalty = 1.
        // No adjustment for M<2 (payout=0) or M=8 (hero always matches, can't offset).
        if (heroEnabled && matches >= 2 && matches < 8) {
            payout = _applyHeroMultiplier(
                payout,
                playerTicket,
                resultTicket,
                matches,
                heroQuadrant
            );
        }
    }

    /// @dev Applies the hero quadrant boost/penalty to a payout.
    ///      Checks if the hero quadrant's color AND symbol both match.
    ///      If yes: multiply by boost(M). If no: multiply by penalty.
    function _applyHeroMultiplier(
        uint256 payout,
        uint32 playerTicket,
        uint32 resultTicket,
        uint8 matches,
        uint8 heroQuadrant
    ) private pure returns (uint256) {
        uint256 shift = uint256(heroQuadrant) * 8;
        bool colorMatch = ((playerTicket >> (shift + 3)) & 7) ==
            ((resultTicket >> (shift + 3)) & 7);
        bool symbolMatch = ((playerTicket >> shift) & 7) ==
            ((resultTicket >> shift) & 7);

        uint256 multiplier;
        if (colorMatch && symbolMatch) {
            // Hero quadrant fully matched — look up per-M boost
            multiplier =
                (HERO_BOOST_PACKED >> (uint256(matches - 2) * 16)) &
                MASK_16;
        } else {
            multiplier = HERO_PENALTY;
        }
        return (payout * multiplier) / HERO_SCALE;
    }

    /// @dev Gets the base payout multiplier in centi-x for a match count.
    /// @param matches Number of matches (0-8).
    /// @return Base payout in centi-x (190 = 1.90x at 100% ROI).
    function _getBasePayoutBps(uint8 matches) private pure returns (uint256) {
        if (matches >= 8) return QUICK_PLAY_BASE_PAYOUT_8_MATCHES;
        return
            (QUICK_PLAY_BASE_PAYOUTS_PACKED >> (uint256(matches) * 32)) &
            0xFFFFFFFF;
    }

    // -------------------------------------------------------------------------
    // Payout Math
    // -------------------------------------------------------------------------

    /// @dev Computes ROI in basis points based on activity score.
    ///      Curve: quadratic 90%→95% (0-75% activity), linear 95%→99.5% (75-255% activity),
    ///      linear 99.5%→99.9% (255-305% activity).
    /// @param score The activity score in basis points.
    /// @return roiBps The ROI in basis points.
    function _roiBpsFromScore(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score > ACTIVITY_SCORE_MAX_BPS) {
            score = ACTIVITY_SCORE_MAX_BPS;
        }

        if (score <= ACTIVITY_SCORE_MID_BPS) {
            // Quadratic segment: 0% to 75% activity → 90% to 95% ROI
            uint256 xNum = score;
            uint256 xDen = ACTIVITY_SCORE_MID_BPS;
            uint256 term1 = (1000 * xNum) / xDen;
            uint256 term2 = (500 * xNum * xNum) / (xDen * xDen);
            roiBps = ROI_MIN_BPS + term1 - term2;
        } else if (score <= ACTIVITY_SCORE_HIGH_BPS) {
            // Linear segment: 75% to 255% activity → 95% to 99.5% ROI
            uint256 delta = score - ACTIVITY_SCORE_MID_BPS;
            uint256 span = ACTIVITY_SCORE_HIGH_BPS - ACTIVITY_SCORE_MID_BPS;
            uint256 roiDelta = ROI_HIGH_BPS - ROI_MID_BPS;
            roiBps = ROI_MID_BPS + (delta * roiDelta) / span;
        } else {
            // Linear segment: 255% to 305% activity → 99.5% to 99.9% ROI
            uint256 delta = score - ACTIVITY_SCORE_HIGH_BPS;
            uint256 span = ACTIVITY_SCORE_MAX_BPS - ACTIVITY_SCORE_HIGH_BPS;
            uint256 roiDelta = ROI_MAX_BPS - ROI_HIGH_BPS;
            roiBps = ROI_HIGH_BPS + (delta * roiDelta) / span;
        }

        // ETH bonus is redistributed in full-ticket payouts (not added here).
    }

    /// @dev Calculates WWXRP high-value ROI based on activity score.
    ///      Used as the target ROI for full-ticket bonus redistribution into
    ///      5+ match buckets.
    ///      Scales from 90.0% base to 109.9% max.
    /// @param score The activity score in basis points.
    /// @return roiBps The WWXRP high-value ROI in basis points.
    function _wwxrpHighValueRoi(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score > ACTIVITY_SCORE_MAX_BPS) {
            score = ACTIVITY_SCORE_MAX_BPS;
        }

        // Linear scale from 90.0% (9000 bps) to 109.9% (10990 bps)
        roiBps =
            WWXRP_HIGH_ROI_BASE_BPS +
            (score * (WWXRP_HIGH_ROI_MAX_BPS - WWXRP_HIGH_ROI_BASE_BPS)) /
            ACTIVITY_SCORE_MAX_BPS;
    }

    // -------------------------------------------------------------------------
    // Claimable ETH Credit
    // -------------------------------------------------------------------------

    /// @dev Adds ETH to a player's claimable winnings balance.
    /// @param beneficiary The address to credit.
    /// @param weiAmount The amount in wei to credit.
    function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
        if (weiAmount == 0) return;
        claimablePool += weiAmount;
        _creditClaimable(beneficiary, weiAmount);
    }

    /// @dev Award sDGNRS from Reward pool on 6+ match Degenerette ETH bets.
    ///      Reward scales by bet size (capped at 1 ETH) and match tier.
    function _awardDegeneretteDgnrs(
        address player,
        uint256 betWei,
        uint8 matchCount
    ) private {
        uint256 bps;
        if (matchCount == 6) bps = DEGEN_DGNRS_6_BPS;
        else if (matchCount == 7) bps = DEGEN_DGNRS_7_BPS;
        else bps = DEGEN_DGNRS_8_BPS;

        uint256 poolBalance = sdgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Reward
        );
        if (poolBalance == 0) return;

        uint256 cappedBet = betWei > 1 ether ? 1 ether : betWei;
        uint256 reward = (poolBalance * bps * cappedBet) / (10_000 * 1 ether);
        if (reward == 0) return;

        sdgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Reward,
            player,
            reward
        );
    }
}
