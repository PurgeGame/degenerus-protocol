// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";

/**
 * @title DegenerusAffiliate
 * @author Burnie Degenerus
 * @notice Multi-tier affiliate referral system with configurable rakeback.
 *
 * @dev ARCHITECTURE:
 *      - 3-tier referral: Player → Affiliate (base) → Upline1 (20%) → Upline2 (4%)
 *      - Rakeback: 0-25% of reward returned to referred player
 *      - Affiliate payouts + quest bonuses via creditFlip; rakeback returned to caller
 *      - Fresh ETH rewards: 25% (levels 1-3), 20% (levels 4+)
 *      - Recycled ETH rewards: 5% (all levels)
 *      - Leaderboard: tracks top affiliate per level for mint trait bonus
 *
 * @dev SECURITY:
 *      - Access control: payAffiliate (coin/gamepieces)
 *      - Referral locking: invalid codes lock slot (REF_CODE_LOCKED sentinel)
 *      - Fixed contract addresses at deploy (no re-pointing)
 */

/// @notice Interface for crediting FLIP tokens to players via the coin contract.
/// @dev Called to distribute affiliate rewards.
interface IDegenerusCoinAffiliate {
    /// @notice Credit FLIP to a single player.
    /// @param player Recipient address.
    /// @param amount Amount of FLIP (18 decimals).
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit FLIP to up to 3 players in a single call (gas optimization).
    /// @param players Array of 3 recipient addresses (unused slots should be address(0)).
    /// @param amounts Array of 3 amounts corresponding to each player.
    function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;

    /// @notice Calculate and record quest progress for affiliate earnings.
    /// @param player The affiliate receiving the base reward.
    /// @param amount The base affiliate amount (before quest bonus).
    /// @return Additional quest reward amount to add to the payout.
    function affiliateQuestReward(address player, uint256 amount) external returns (uint256);
}

/**
 * @title DegenerusAffiliate
 * @notice Multi-tier affiliate referral system with leaderboard tracking.
 * @dev Central hub for all affiliate-related operations in the Degenerus ecosystem.
 *
 * INTEGRATION POINTS:
 * - DegenerusGamepieces: Calls payAffiliate() for ticket purchases
 */
contract DegenerusAffiliate {
    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted on affiliate code creation, referral registration, and reward payouts.
    /// @param amount Context-dependent: 1 = code created, 0 = player referred, >1 = base input amount.
    /// @param code The affiliate code involved (indexed for efficient log filtering).
    /// @param sender The player or affiliate address involved.
    event Affiliate(uint256 amount, bytes32 indexed code, address sender);

    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not in the authorized set (coin, gamepieces).
    error OnlyAuthorized();

    /// @notice Thrown when attempting to create an affiliate code with zero or reserved value.
    error Zero();

    /// @notice Generic insufficient condition error (code taken, invalid referral, ETH forward fail).
    error Insufficient();

    /// @notice Thrown when rakeback percentage exceeds the maximum allowed (25%).
    error InvalidRakeback();

    // =====================================================================
    //                              TYPES
    // =====================================================================

    /**
     * @notice Packed struct for leaderboard tracking (fits in single slot).
     * @dev Used in affiliateTopByLevel mapping to track best performer per level.
     *
     * STORAGE LAYOUT (32 bytes):
     * +----------------------------------------------------+
     * | [0:20]  player   address   Top affiliate address   |
     * | [20:32] score    uint96    Raw BURNIE earned       |
     * +----------------------------------------------------+
     */
    struct PlayerScore {
        address player; // 20 bytes - address of top affiliate
        uint96 score; // 12 bytes - raw 18-decimal amount (capped to uint96 max)
    }

    /**
     * @notice Affiliate code ownership and rakeback configuration.
     * @dev Packed into single storage slot for gas efficiency.
     *
     * STORAGE LAYOUT (32 bytes, 11 bytes used):
     * +----------------------------------------------------+
     * | [0:20]  owner     address   Code owner/recipient   |
     * | [20:21] rakeback  uint8     Rakeback % (0-25)      |
     * | [21:32] unused    ---       11 bytes padding       |
     * +----------------------------------------------------+
     */
    struct AffiliateCodeInfo {
        address owner; // 20 bytes - receives affiliate rewards
        uint8 rakeback; // 1 byte - percentage returned to referred player (0-25)
    }

    // =====================================================================
    //                            CONSTANTS
    // =====================================================================

    /// @notice Maximum bonus points an affiliate can earn from recent earnings.
    /// @dev Applied to mint trait rolls; capped at 50 points (50%).
    uint256 private constant AFFILIATE_BONUS_MAX = 50;

    /// @notice Sentinel value indicating a player's referral slot is permanently locked.
    /// @dev Set when a player makes an invalid referral attempt (self-referral, unknown code)
    ///      after the game has started. Prevents gaming by trying multiple codes.
    bytes32 private constant REF_CODE_LOCKED = bytes32(uint256(1));
    bytes32 private constant AFFILIATE_CODE_VAULT = bytes32("VAULT");
    bytes32 private constant AFFILIATE_CODE_DGNRS = bytes32("DGNRS");

    /// @notice BurnieCoin contract for FLIP token operations (constant).
    IDegenerusCoinAffiliate internal constant coin = IDegenerusCoinAffiliate(ContractAddresses.COIN);
    /// @notice Game contract for presale status checks (constant).
    IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);

    // =====================================================================
    //                        AFFILIATE STATE
    // =====================================================================

    /// @notice Mapping from affiliate code (bytes32) to ownership info.
    /// @dev codes are permanent once created; owner cannot be changed.
    ///      Reserved value: bytes32(0) = invalid, bytes32(1) = REF_CODE_LOCKED sentinel.
    mapping(bytes32 => AffiliateCodeInfo) public affiliateCode;

    /// @notice Per-level earnings tracking: level → affiliate → raw token amount.
    /// @dev Used for leaderboard calculations and activity score bonus points.
    ///      Amounts include 18 decimal places; divide by 1 ether for whole tokens.
    ///      Direct affiliate earnings only; upline rewards are excluded for gas.
    ///      Rakeback does not reduce the tracked score.
    mapping(uint24 => mapping(address => uint256)) private affiliateCoinEarned;

    /// @notice Player's chosen referral code (or REF_CODE_LOCKED if locked).
    /// @dev Private to prevent external manipulation; no public getter.
    ///      bytes32(0) = not yet set, REF_CODE_LOCKED = permanently locked.
    mapping(address => bytes32) private playerReferralCode;

    /// @notice Top affiliate per game level for bonus calculations.
    /// @dev Private storage; use affiliateTop() view to read.
    ///      Updated in _updateTopAffiliate() when affiliate exceeds current top.
    mapping(uint24 => PlayerScore) private affiliateTopByLevel;

    // =====================================================================
    //                              CONSTRUCTOR
    // =====================================================================

    constructor() {
        affiliateCode[AFFILIATE_CODE_VAULT] = AffiliateCodeInfo({
            owner: ContractAddresses.VAULT,
            rakeback: 0
        });
        affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({
            owner: ContractAddresses.DGNRS,
            rakeback: 0
        });
        emit Affiliate(1, AFFILIATE_CODE_VAULT, ContractAddresses.VAULT);
        emit Affiliate(1, AFFILIATE_CODE_DGNRS, ContractAddresses.DGNRS);

        playerReferralCode[ContractAddresses.VAULT] = AFFILIATE_CODE_DGNRS;
        playerReferralCode[ContractAddresses.DGNRS] = AFFILIATE_CODE_VAULT;
        emit Affiliate(0, AFFILIATE_CODE_DGNRS, ContractAddresses.VAULT);
        emit Affiliate(0, AFFILIATE_CODE_VAULT, ContractAddresses.DGNRS);
    }

    /**
     * @notice Initialize affiliate contract with trusted contract addresses.
     * @dev All dependencies are fixed at deploy time via ContractAddresses.
     */
    // =====================================================================
    //                    EXTERNAL PLAYER ENTRYPOINTS
    // =====================================================================

    /**
     * @notice Create a new affiliate code owned by the caller.
     * @dev Anyone can create an affiliate code. Codes are permanent and cannot be
     *      transferred or deleted. The rakeback percentage determines how much of
     *      the affiliate reward is returned to referred players as an incentive.
     *
     * VALIDATION:
     * - code_ != bytes32(0) (reserved for "no code")
     * - code_ != REF_CODE_LOCKED (reserved sentinel value)
     * - code_ not already taken
     * - rakebackPct <= 25 (max 25% rakeback)
     *
     * @param code_ The affiliate code to claim (typically a short string cast to bytes32).
     * @param rakebackPct Percentage of rewards returned to referred players (0-25).
     */
    function createAffiliateCode(bytes32 code_, uint8 rakebackPct) external {
        // SECURITY: Prevent reserved values from being claimed.
        if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();
        // SECURITY: Cap rakeback to prevent affiliate from giving away all rewards.
        if (rakebackPct > 25) revert InvalidRakeback();
        AffiliateCodeInfo storage info = affiliateCode[code_];
        // SECURITY: First-come-first-served; codes cannot be overwritten.
        if (info.owner != address(0)) revert Insufficient();
        affiliateCode[code_] = AffiliateCodeInfo({owner: msg.sender, rakeback: rakebackPct});
        emit Affiliate(1, code_, msg.sender); // 1 = code created
    }

    /**
     * @notice Register the caller as referred by an affiliate code.
     * @dev This is the explicit user-initiated way to set a referrer.
     *      Alternatively, referrers can be set implicitly during payAffiliate().
     *      Once set (or locked), cannot be changed.
     *
     * VALIDATION:
     * - code_ must exist (owner != address(0))
     * - code_ owner must not be the caller (no self-referral)
     * - caller must not already have a referral code set
     *
     * @param code_ The affiliate code to register under.
     */
    function referPlayer(bytes32 code_) external {
        AffiliateCodeInfo storage info = affiliateCode[code_];
        address referrer = info.owner;
        // SECURITY: Prevent invalid codes and self-referral.
        if (referrer == address(0) || referrer == msg.sender) revert Insufficient();
        bytes32 existing = playerReferralCode[msg.sender];
        // SECURITY: Only allow setting referrer once, except VAULT referrals during presale.
        if (existing != bytes32(0) && !_vaultReferralMutable(existing)) revert Insufficient();
        playerReferralCode[msg.sender] = code_;
        emit Affiliate(0, code_, msg.sender); // 0 = player referred
    }

    /**
     * @notice Get the referrer address for a player.
     * @dev Returns address(0) if player has no valid referrer.
     * @param player The player to look up.
     * @return The referrer's address, or address(0) if none.
     */
    function getReferrer(address player) external view returns (address) {
        return _referrerAddress(player);
    }

    // =====================================================================
    //                    GAMEPLAY ENTRYPOINTS
    // =====================================================================

    /**
     * @notice Process affiliate rewards for a purchase or gameplay action.
     * @dev Core payout logic. Handles referral resolution, reward scaling,
     *      and multi-tier distribution.
     *
     * ACCESS: coin or gamepieces only.
     *
     * REWARD FLOW:
     * +--------------------------------------------------------------------+
     * | 1. Resolve referral code (stored or provided)                      |
     * | 2. Apply reward percentage based on ETH type and level             |
     * | 3. Calculate rakeback (returned to caller for player credit)       |
     * | 4. Pay direct affiliate (base - rakeback)                          |
     * | 5. Pay upline1 (20% of scaled amount)                              |
     * | 6. Pay upline2 (20% of upline1 share = 4%)                         |
     * | 7. Quest rewards added on top                                     |
     * +--------------------------------------------------------------------+
     *
     * REWARD RATES:
     * - Fresh ETH (levels 1-3): 25%
     * - Fresh ETH (levels 4+): 20%
     * - Recycled ETH (all levels): 5%
     *
     * @param amount Base reward amount (18 decimals).
     * @param code Affiliate code provided with the transaction (may be bytes32(0)).
     * @param sender The player making the purchase.
     * @param lvl Current game level (for join tracking and leaderboard).
     * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
     * @return playerRakeback Amount of rakeback to credit to the player (caller handles minting; Gamepieces bundles for gas).
     */
    function payAffiliate(uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth) external returns (uint256 playerRakeback) {
        // -----------------------------------------------------------------
        // ACCESS CONTROL
        // -----------------------------------------------------------------
        // SECURITY: Only trusted contracts can distribute affiliate rewards.
        if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.GAMEPIECES) revert OnlyAuthorized();

        // -----------------------------------------------------------------
        // REFERRAL RESOLUTION
        // -----------------------------------------------------------------
        bytes32 storedCode = playerReferralCode[sender];
        AffiliateCodeInfo memory info;
        bool infoSet;

        if (storedCode == bytes32(0)) {
            // No stored code - resolve provided code or default to VAULT.
            AffiliateCodeInfo storage candidate = affiliateCode[code];
            if (
                candidate.owner == address(0) ||
                candidate.owner == sender
            ) {
                // Blank/invalid/self-referral: lock to VAULT as default.
                playerReferralCode[sender] = REF_CODE_LOCKED;
                storedCode = AFFILIATE_CODE_VAULT;
                info = AffiliateCodeInfo({owner: ContractAddresses.VAULT, rakeback: 0});
            } else {
                // Valid code: store it permanently.
                playerReferralCode[sender] = code;
                info = candidate;
                storedCode = code;
            }
            infoSet = true;
        } else {
            if (_vaultReferralMutable(storedCode)) {
                AffiliateCodeInfo storage candidate = affiliateCode[code];
                if (candidate.owner != address(0) && candidate.owner != sender) {
                    playerReferralCode[sender] = code;
                    info = candidate;
                    storedCode = code;
                    infoSet = true;
                }
            }
            if (!infoSet) {
                if (storedCode == REF_CODE_LOCKED) {
                    storedCode = AFFILIATE_CODE_VAULT;
                    info = AffiliateCodeInfo({
                        owner: ContractAddresses.VAULT,
                        rakeback: 0
                    });
                } else {
                    // Use the stored code.
                    info = affiliateCode[storedCode];
                }
            }
        }

        // -----------------------------------------------------------------
        // REWARD CALCULATION SETUP
        // -----------------------------------------------------------------
        address affiliateAddr = info.owner;
        uint8 rakebackPct = info.rakeback;

        // -----------------------------------------------------------------
        // REWARD CALCULATION
        // -----------------------------------------------------------------
        mapping(address => uint256) storage earned = affiliateCoinEarned[lvl];

        // Apply reward percentage based on ETH type and level.
        // - Fresh ETH (levels 1-3): 25%
        // - Fresh ETH (levels 4+): 20%
        // - Recycled ETH: 5%
        uint256 rewardScaleBps;
        if (isFreshEth) {
            // Fresh ETH: 25% for first 3 levels, 20% for levels 4+
            rewardScaleBps = lvl <= 3 ? 2_500 : 2_000;
        } else {
            // Recycled ETH: 5%
            rewardScaleBps = 500;
        }
        uint256 scaledAmount = (amount * rewardScaleBps) / 10_000;

        // Calculate rakeback (returned to player) and affiliate share.
        uint256 rakebackShare = (scaledAmount * uint256(rakebackPct)) / 100;
        uint256 affiliateShareBase = scaledAmount - rakebackShare;

        // Update leaderboard tracking (uses pre-rakeback base amount, ignores quest bonuses).
        uint256 newTotal = earned[affiliateAddr] + scaledAmount;
        earned[affiliateAddr] = newTotal;
        _updateTopAffiliate(affiliateAddr, newTotal, lvl);

        playerRakeback = rakebackShare;
        // Upline rewards are paid out but not tracked for leaderboard scores (gas).

        // -----------------------------------------------------------------
        // DISTRIBUTION
        // -----------------------------------------------------------------
        // Batch recipients for gas efficiency.
        address[3] memory players;
        uint256[3] memory amounts;
        uint256 cursor;

        // Add quest reward bonus on top of base affiliate share.
        uint256 questReward = coin.affiliateQuestReward(affiliateAddr, affiliateShareBase);
        uint256 totalFlipAward = affiliateShareBase + questReward;

        players[cursor] = affiliateAddr;
        amounts[cursor] = totalFlipAward;
        unchecked {
            ++cursor;
        }

        // -------------------------------------------------------------
        // UPLINE TIER 1 (20% of scaled amount)
        // -------------------------------------------------------------
        address upline = _referrerAddress(affiliateAddr);
        if (upline != address(0)) {
            uint256 baseBonus = scaledAmount / 5; // 20%
            uint256 questRewardUpline = coin.affiliateQuestReward(upline, baseBonus);
            uint256 totalUpline = baseBonus + questRewardUpline;

            players[cursor] = upline;
            amounts[cursor] = totalUpline;
            unchecked {
                ++cursor;
            }

            // ---------------------------------------------------------
            // UPLINE TIER 2 (20% of tier 1 = 4% of original)
            // ---------------------------------------------------------
            address upline2 = _referrerAddress(upline);
            if (upline2 != address(0)) {
                uint256 bonus2 = baseBonus / 5; // 20% of 20% = 4%
                uint256 questReward2 = coin.affiliateQuestReward(upline2, bonus2);
                uint256 totalUpline2 = bonus2 + questReward2;

                players[cursor] = upline2;
                amounts[cursor] = totalUpline2;
                unchecked {
                    ++cursor;
                }
            }
        }

        // Distribute rewards (single call vs batch for gas efficiency).
        if (cursor != 0) {
            if (cursor == 1) {
                coin.creditFlip(players[0], amounts[0]);
            } else {
                coin.creditFlipBatch(players, amounts);
            }
        }

        emit Affiliate(amount, storedCode, sender);
        return playerRakeback;
    }

    // =====================================================================
    //                              VIEWS
    // =====================================================================

    /**
     * @notice Get the top affiliate for a given game level.
     * @dev Returns the affiliate with the highest earnings for that level.
     *      Used for trophies and jackpot affiliate selection.
     * @param lvl The game level to query.
     * @return player Address of the top affiliate.
     * @return score Their score in BURNIE base units (18 decimals).
     */
    function affiliateTop(uint24 lvl) public view returns (address player, uint96 score) {
        PlayerScore memory stored = affiliateTopByLevel[lvl];
        return (stored.player, stored.score);
    }

    /**
     * @notice Get an affiliate's base earnings score for a level.
     * @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
     * @param lvl The game level to query.
     * @param player The affiliate address to query.
     * @return score The base affiliate score (18 decimals).
     */
    function affiliateScore(uint24 lvl, address player) external view returns (uint256 score) {
        return affiliateCoinEarned[lvl][player];
    }

    /**
     * @notice Calculate the affiliate bonus points for a player.
     * @dev Sums the player's affiliate scores for the previous 5 levels.
     *      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
     *
     * @param currLevel The current game level.
     * @param player The player to calculate bonus for.
     * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
     */
    function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
        if (player == address(0) || currLevel == 0) return 0;
        uint256 sum;
        unchecked {
            for (uint8 offset = 1; offset <= 5; ) {
                if (currLevel <= offset) break;
                uint24 lvl = currLevel - offset;
                sum += affiliateCoinEarned[lvl][player];
                ++offset;
            }
        }

        if (sum == 0) return 0;
        uint256 ethUnit = 1 ether / ContractAddresses.COST_DIVISOR;
        points = sum / ethUnit;
        return points > AFFILIATE_BONUS_MAX ? AFFILIATE_BONUS_MAX : points;
    }

    // =====================================================================
    //                        INTERNAL HELPERS
    // =====================================================================

    /// @dev Allow VAULT-referred players to update referral only during presale.
    function _vaultReferralMutable(bytes32 code) private view returns (bool) {
        if (code != REF_CODE_LOCKED && code != AFFILIATE_CODE_VAULT) return false;
        return game.lootboxPresaleActiveFlag();
    }

    /**
     * @notice Get the referrer's address for a player.
     * @dev Returns address(0) if player has no valid referrer.
     * @param player The player to look up.
     * @return The referrer's address.
     */
    function _referrerAddress(address player) private view returns (address) {
        bytes32 code = playerReferralCode[player];
        if (code == bytes32(0)) return address(0);
        if (code == REF_CODE_LOCKED) code = AFFILIATE_CODE_VAULT;
        address owner = affiliateCode[code].owner;
        if (code == AFFILIATE_CODE_VAULT && owner == address(0)) return ContractAddresses.VAULT;
        return owner;
    }

    /**
     * @notice Convert a raw amount to a uint96 score in base units.
     * @dev Caps at uint96 max to prevent overflow/truncation errors.
     *      uint96 max ≈ 7.9e28 base units (~79 billion tokens).
     * @param s Raw amount (18 decimals).
     * @return Raw token amount (18 decimals) as uint96.
     */
    function _score96(uint256 s) private pure returns (uint96) {
        // SECURITY: Cap at max to prevent truncation errors.
        if (s > type(uint96).max) {
            return type(uint96).max;
        }
        return uint96(s);
    }

    /**
     * @notice Update the top affiliate for a level if the new score beats current.
     * @dev Only updates storage if score exceeds current top.
     *      Leaderboard tracking is per-level (resets each level).
     * @param player The affiliate whose score is being checked.
     * @param total The affiliate's new total earnings (raw, 18 decimals).
     * @param lvl The game level.
     */
    function _updateTopAffiliate(address player, uint256 total, uint24 lvl) private {
        uint96 score = _score96(total);
        PlayerScore memory current = affiliateTopByLevel[lvl];
        if (score > current.score) {
            affiliateTopByLevel[lvl] = PlayerScore({player: player, score: score});
        }
    }
}
