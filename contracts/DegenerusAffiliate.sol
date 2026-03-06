// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

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
 *      - Access control: payAffiliate (coin/game)
 *      - Referral locking: invalid codes lock slot (REF_CODE_LOCKED sentinel)
 *      - Fixed contract addresses at deploy (no re-pointing)
 */

/// @notice Interface for crediting FLIP tokens to players via the coin contract.
/// @dev Called to distribute affiliate rewards.
interface IDegenerusCoinAffiliate {
    /// @notice Credit BURNIE directly to a player's wallet balance.
    /// @param player Recipient address.
    /// @param amount Amount of BURNIE (18 decimals).
    function creditCoin(address player, uint256 amount) external;

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
 * - DegenerusGame: Calls payAffiliate() for purchase flows
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
    /// @notice Emitted when a player's referral code is set or updated.
    /// @param player The player whose referral code changed.
    /// @param code The stored referral code (REF_CODE_LOCKED for locked).
    /// @param referrer The resolved referrer address (vault if locked/default).
    /// @param locked True if referral is locked to the vault sentinel.
    event ReferralUpdated(
        address indexed player,
        bytes32 indexed code,
        address indexed referrer,
        bool locked
    );
    /// @notice Emitted when affiliate earnings are recorded for a level.
    /// @param level The game level.
    /// @param affiliate The affiliate receiving credit.
    /// @param amount The scaled amount credited for leaderboard (pre-rakeback, excludes quest bonus).
    /// @param newTotal The affiliate's new total for this level.
    /// @param sender The player whose action generated the reward.
    /// @param code The referral code used.
    /// @param isFreshEth True if reward was from fresh ETH, false if recycled.
    event AffiliateEarningsRecorded(
        uint24 indexed level,
        address indexed affiliate,
        uint256 amount,
        uint256 newTotal,
        address indexed sender,
        bytes32 code,
        bool isFreshEth
    );
    /// @notice Emitted when the top affiliate for a level changes.
    /// @param level The game level.
    /// @param player The new top affiliate.
    /// @param score The new top score (uint96-capped).
    event AffiliateTopUpdated(
        uint24 indexed level,
        address indexed player,
        uint96 score
    );
    /// @notice Emitted when an affiliate code updates its payout mode.
    /// @param owner Owner of the affiliate code.
    /// @param code Affiliate code.
    /// @param mode New payout mode (0=coinflip, 1=degenerette credit, 2=50% coin, 50% discarded).
    event AffiliatePayoutModeUpdated(
        address indexed owner,
        bytes32 indexed code,
        uint8 mode
    );
    /// @notice Emitted when pending Degenerette credit changes.
    /// @param player Player whose credit changed.
    /// @param credited True if credit was added, false if consumed.
    /// @param amount Delta amount.
    /// @param newBalance Updated pending credit balance.
    event DegeneretteCreditUpdated(
        address indexed player,
        bool credited,
        uint256 amount,
        uint256 newBalance
    );

    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not in the authorized set (coin, game, lootbox).
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
     * STORAGE LAYOUT (32 bytes, 22 bytes used):
     * +----------------------------------------------------+
     * | [0:20]  owner     address   Code owner/recipient   |
     * | [20:21] rakeback  uint8     Rakeback % (0-25)      |
     * | [21:22] mode      uint8     Payout mode (0-2)      |
     * | [22:32] unused    ---       10 bytes padding       |
     * +----------------------------------------------------+
     */
    struct AffiliateCodeInfo {
        address owner; // 20 bytes - receives affiliate rewards
        uint8 rakeback; // 1 byte - percentage returned to referred player (0-25)
        uint8 payoutMode; // 1 byte - 0=coinflip, 1=degenerette credit, 2=50% coin (rest discarded)
    }

    /// @notice Affiliate payout routing mode.
    /// @dev 0=coinflip credit (default), 1=degenerette credit bucket, 2=50% coin (remaining 50% discarded).
    enum PayoutMode {
        Coinflip,
        Degenerette,
        SplitCoinflipCoin
    }

    // =====================================================================
    //                            CONSTANTS
    // =====================================================================

    /// @notice Maximum bonus points an affiliate can earn from recent earnings.
    /// @dev Applied to mint trait rolls; capped at 50 points (50%).
    uint256 private constant AFFILIATE_BONUS_MAX = 50;
    uint8 private constant MAX_RAKEBACK_PCT = 25;
    uint16 private constant REWARD_SCALE_FRESH_L1_3_BPS = 2_500;
    uint16 private constant REWARD_SCALE_FRESH_L4P_BPS = 2_000;
    uint16 private constant REWARD_SCALE_RECYCLED_BPS = 500;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant LOOTBOX_TAPER_START_SCORE = 15_000;
    uint16 private constant LOOTBOX_TAPER_END_SCORE = 25_500;
    uint16 private constant LOOTBOX_TAPER_MIN_BPS = 5_000;
    /// @notice Max BURNIE commission an affiliate can earn from a single sender per level.
    /// @dev At 20% fresh ETH rate, this caps after 2.5 ETH spend from that sender.
    uint256 private constant MAX_COMMISSION_PER_REFERRER_PER_LEVEL = 0.5 ether;
    bytes32 private constant AFFILIATE_ROLL_TAG = keccak256("affiliate-payout-roll-v1");

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

    /// @notice Pending Degenerette credit balances by player.
    mapping(address => uint256) private pendingDegeneretteCredit;

    /// @notice Top affiliate per game level for bonus calculations.
    /// @dev Private storage; use affiliateTop() view to read.
    ///      Updated in _updateTopAffiliate() when affiliate exceeds current top.
    mapping(uint24 => PlayerScore) private affiliateTopByLevel;

    /// @notice Commission earned by affiliate from specific sender per level.
    /// @dev Tracks cumulative BURNIE earned: level → affiliate → sender → amount.
    ///      Used to enforce MAX_COMMISSION_PER_REFERRER_PER_LEVEL cap.
    mapping(uint24 => mapping(address => mapping(address => uint256))) private affiliateCommissionFromSender;

    // =====================================================================
    //                              CONSTRUCTOR
    // =====================================================================

    constructor(
        address[] memory bootstrapOwners,
        bytes32[] memory bootstrapCodes,
        uint8[] memory bootstrapRakebacks,
        address[] memory bootstrapPlayers,
        bytes32[] memory bootstrapReferralCodes
    ) {
        if (
            bootstrapOwners.length != bootstrapCodes.length ||
            bootstrapOwners.length != bootstrapRakebacks.length ||
            bootstrapPlayers.length != bootstrapReferralCodes.length
        ) revert Insufficient();

        affiliateCode[AFFILIATE_CODE_VAULT] = AffiliateCodeInfo({
            owner: ContractAddresses.VAULT,
            rakeback: 0,
            payoutMode: uint8(PayoutMode.Coinflip)
        });
        affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({
            owner: ContractAddresses.DGNRS,
            rakeback: 0,
            payoutMode: uint8(PayoutMode.Coinflip)
        });
        emit Affiliate(1, AFFILIATE_CODE_VAULT, ContractAddresses.VAULT);
        emit Affiliate(1, AFFILIATE_CODE_DGNRS, ContractAddresses.DGNRS);

        _setReferralCode(ContractAddresses.VAULT, AFFILIATE_CODE_DGNRS);
        _setReferralCode(ContractAddresses.DGNRS, AFFILIATE_CODE_VAULT);
        emit Affiliate(0, AFFILIATE_CODE_DGNRS, ContractAddresses.VAULT);
        emit Affiliate(0, AFFILIATE_CODE_VAULT, ContractAddresses.DGNRS);

        uint256 len = bootstrapOwners.length;
        for (uint256 i; i < len; ) {
            _createAffiliateCode(
                bootstrapOwners[i],
                bootstrapCodes[i],
                bootstrapRakebacks[i]
            );
            unchecked {
                ++i;
            }
        }

        uint256 referralLen = bootstrapPlayers.length;
        for (uint256 i; i < referralLen; ) {
            _bootstrapReferral(
                bootstrapPlayers[i],
                bootstrapReferralCodes[i]
            );
            unchecked {
                ++i;
            }
        }
    }

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
        _createAffiliateCode(msg.sender, code_, rakebackPct);
    }

    /// @notice Set payout mode for an affiliate code owned by the caller.
    /// @param code_ Affiliate code to configure.
    /// @param mode Routing mode.
    function setAffiliatePayoutMode(bytes32 code_, PayoutMode mode) external {
        AffiliateCodeInfo storage info = affiliateCode[code_];
        if (info.owner != msg.sender) revert Insufficient();
        uint8 modeRaw = uint8(mode);
        if (info.payoutMode != modeRaw) {
            info.payoutMode = modeRaw;
        }
        emit AffiliatePayoutModeUpdated(msg.sender, code_, modeRaw);
    }

    /// @notice Get payout mode for an affiliate code.
    /// @param code_ Affiliate code to query.
    /// @return mode Current payout mode.
    function affiliatePayoutMode(bytes32 code_) external view returns (PayoutMode mode) {
        return PayoutMode(affiliateCode[code_].payoutMode);
    }

    /// @notice View pending Degenerette credit balance for a player.
    /// @param player Address to query.
    /// @return amount Pending credit amount (18 decimals).
    function pendingDegeneretteCreditOf(address player) external view returns (uint256 amount) {
        return pendingDegeneretteCredit[player];
    }

    /// @notice Consume pending Degenerette credit for a player.
    /// @dev Access: game contract only.
    /// @param player Player address.
    /// @param amount Amount requested to consume.
    /// @return consumed Amount consumed.
    function consumeDegeneretteCredit(
        address player,
        uint256 amount
    ) external returns (uint256 consumed) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyAuthorized();
        if (player == address(0) || amount == 0) return 0;
        uint256 balance = pendingDegeneretteCredit[player];
        if (balance == 0) return 0;

        consumed = amount <= balance ? amount : balance;
        uint256 newBalance;
        unchecked {
            newBalance = balance - consumed;
        }
        pendingDegeneretteCredit[player] = newBalance;
        emit DegeneretteCreditUpdated(player, false, consumed, newBalance);
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
        _setReferralCode(msg.sender, code_);
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
 * ACCESS: coin or game only.
     *
     * REWARD FLOW:
     * +--------------------------------------------------------------------+
     * | 1. Resolve referral code (stored or provided)                      |
     * | 2. Apply reward percentage based on ETH type and level             |
     * | 3. Update leaderboard (full untapered amount)                      |
     * | 4. Apply lootbox activity taper if applicable                      |
     * | 5. Calculate rakeback (returned to caller for player credit)       |
     * | 6. Pay direct affiliate (base - rakeback)                          |
     * | 7. Pay upline1 (20% of scaled amount)                              |
     * | 8. Pay upline2 (20% of upline1 share = 4%)                         |
     * | 9. Quest rewards added on top                                     |
     * +--------------------------------------------------------------------+
     *
     * REWARD RATES:
     * - Fresh ETH (levels 1-3): 25%
     * - Fresh ETH (levels 4+): 20%
     * - Recycled ETH (all levels): 5%
     *
     * LOOTBOX TAPER (fresh ETH only):
     * - Activity score < 150: no taper (100% payout)
     * - Activity score 150-255: linear taper from 100% to 50%
     * - Activity score >= 255: 50% payout floor
     * - Leaderboard tracking always uses full untapered amount.
     *
     * @param amount Base reward amount (18 decimals).
     * @param code Affiliate code provided with the transaction (may be bytes32(0)).
     * @param sender The player making the purchase.
     * @param lvl Current game level (for join tracking and leaderboard).
     * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
     * @param lootboxActivityScore Buyer's activity score in BPS for lootbox taper (0 = no taper).
     * @return playerRakeback Amount of rakeback to credit to the player (caller handles minting and batching).
     */
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        address sender,
        uint24 lvl,
        bool isFreshEth,
        uint16 lootboxActivityScore
    ) external returns (uint256 playerRakeback) {
        // -----------------------------------------------------------------
        // ACCESS CONTROL
        // -----------------------------------------------------------------
        // SECURITY: Only trusted contracts can distribute affiliate rewards.
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.GAME
        ) revert OnlyAuthorized();

        // -----------------------------------------------------------------
        // REFERRAL RESOLUTION
        // -----------------------------------------------------------------
        bytes32 storedCode = playerReferralCode[sender];
        AffiliateCodeInfo memory info;
        bool infoSet;
        AffiliateCodeInfo memory vaultInfo = AffiliateCodeInfo({
            owner: ContractAddresses.VAULT,
            rakeback: 0,
            payoutMode: uint8(PayoutMode.Coinflip)
        });

        if (storedCode == bytes32(0)) {
            // No stored code - resolve provided code or default to VAULT.
            if (code == bytes32(0)) {
                // Blank referral: lock to VAULT as default.
                _setReferralCode(sender, REF_CODE_LOCKED);
                storedCode = AFFILIATE_CODE_VAULT;
                info = vaultInfo;
            } else {
                AffiliateCodeInfo storage candidate = affiliateCode[code];
                if (
                    candidate.owner == address(0) ||
                    candidate.owner == sender
                ) {
                    // Invalid/self-referral: lock to VAULT as default.
                    _setReferralCode(sender, REF_CODE_LOCKED);
                    storedCode = AFFILIATE_CODE_VAULT;
                    info = vaultInfo;
                } else {
                    // Valid code: store it permanently.
                    _setReferralCode(sender, code);
                    info = candidate;
                    storedCode = code;
                }
            }
            infoSet = true;
        } else {
            if (code != bytes32(0) && code != storedCode && _vaultReferralMutable(storedCode)) {
                AffiliateCodeInfo storage candidate = affiliateCode[code];
                if (candidate.owner != address(0) && candidate.owner != sender) {
                    _setReferralCode(sender, code);
                    info = candidate;
                    storedCode = code;
                    infoSet = true;
                }
            }
            if (!infoSet) {
                if (storedCode == REF_CODE_LOCKED) {
                    storedCode = AFFILIATE_CODE_VAULT;
                    info = vaultInfo;
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
        uint8 payoutMode = info.payoutMode;

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
            rewardScaleBps = lvl <= 3
                ? REWARD_SCALE_FRESH_L1_3_BPS
                : REWARD_SCALE_FRESH_L4P_BPS;
        } else {
            // Recycled ETH: 5%
            rewardScaleBps = REWARD_SCALE_RECYCLED_BPS;
        }
        uint256 scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
        if (scaledAmount == 0) {
            emit Affiliate(amount, storedCode, sender);
            return 0;
        }

        // -----------------------------------------------------------------
        // PER-REFERRER COMMISSION CAP
        // -----------------------------------------------------------------
        // Cap commission from any single sender to 0.5 ETH BURNIE per level.
        // This prevents a single whale from dominating an affiliate's earnings.
        {
            uint256 alreadyEarned = affiliateCommissionFromSender[lvl][affiliateAddr][sender];
            if (alreadyEarned >= MAX_COMMISSION_PER_REFERRER_PER_LEVEL) {
                // Cap fully reached - no more commission from this sender this level.
                emit Affiliate(amount, storedCode, sender);
                return 0;
            }
            uint256 remainingCap = MAX_COMMISSION_PER_REFERRER_PER_LEVEL - alreadyEarned;
            if (scaledAmount > remainingCap) {
                scaledAmount = remainingCap;
            }
            affiliateCommissionFromSender[lvl][affiliateAddr][sender] = alreadyEarned + scaledAmount;
        }

        // Update leaderboard tracking (full amount, before any lootbox taper).
        uint256 newTotal = earned[affiliateAddr] + scaledAmount;
        earned[affiliateAddr] = newTotal;
        emit AffiliateEarningsRecorded(
            lvl,
            affiliateAddr,
            scaledAmount,
            newTotal,
            sender,
            storedCode,
            isFreshEth
        );
        _updateTopAffiliate(affiliateAddr, newTotal, lvl);

        // Taper payout for high-activity lootbox buyers (leaderboard already recorded full amount).
        if (lootboxActivityScore >= LOOTBOX_TAPER_START_SCORE) {
            scaledAmount = _applyLootboxTaper(scaledAmount, lootboxActivityScore);
        }

        // Calculate rakeback (returned to player) and affiliate share.
        uint256 affiliateShareBase;
        uint256 rakebackShare;
        if (rakebackPct == 0) {
            affiliateShareBase = scaledAmount;
        } else {
            rakebackShare = (scaledAmount * uint256(rakebackPct)) / 100;
            affiliateShareBase = scaledAmount - rakebackShare;
        }

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
                uint256 bonus2 = scaledAmount / 25; // 20% of 20% = 4%
                uint256 questReward2 = coin.affiliateQuestReward(upline2, bonus2);
                uint256 totalUpline2 = bonus2 + questReward2;

                players[cursor] = upline2;
                amounts[cursor] = totalUpline2;
                unchecked {
                    ++cursor;
                }
            }
        }

        // Distribute rewards.
        // If multiple recipients exist, roll a single weighted winner and pay
        // the combined amount. This preserves each recipient's EV:
        // P(win_i) = amount_i / totalAmount.
        if (cursor == 1) {
            _routeAffiliateReward(players[0], amounts[0], payoutMode);
        } else {
            uint256 totalAmount;
            for (uint256 i; i < cursor; ) {
                totalAmount += amounts[i];
                unchecked {
                    ++i;
                }
            }

            if (totalAmount != 0) {
                address winner = _rollWeightedAffiliateWinner(
                    players,
                    amounts,
                    cursor,
                    totalAmount,
                    sender,
                    storedCode
                );
                _routeAffiliateReward(winner, totalAmount, payoutMode);
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
    function affiliateTop(uint24 lvl) external view returns (address player, uint96 score) {
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
        uint256 ethUnit = 1 ether;
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

    /// @dev Set player's referral code and emit a normalized event for indexers.
    function _setReferralCode(address player, bytes32 code) private {
        playerReferralCode[player] = code;
        bool locked = code == REF_CODE_LOCKED;
        address referrer;
        if (locked || code == AFFILIATE_CODE_VAULT) {
            referrer = ContractAddresses.VAULT;
        } else {
            referrer = affiliateCode[code].owner;
        }
        emit ReferralUpdated(player, code, referrer, locked);
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
        if (code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) return ContractAddresses.VAULT;
        return affiliateCode[code].owner;
    }

    /// @dev Shared code registration logic for user-created and constructor-bootstrapped codes.
    function _createAffiliateCode(
        address owner,
        bytes32 code_,
        uint8 rakebackPct
    ) private {
        if (owner == address(0)) revert Zero();
        // SECURITY: Prevent reserved values from being claimed.
        if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();
        // SECURITY: Cap rakeback to prevent affiliate from giving away all rewards.
        if (rakebackPct > MAX_RAKEBACK_PCT) revert InvalidRakeback();
        AffiliateCodeInfo storage info = affiliateCode[code_];
        // SECURITY: First-come-first-served; codes cannot be overwritten.
        if (info.owner != address(0)) revert Insufficient();
        affiliateCode[code_] = AffiliateCodeInfo({
            owner: owner,
            rakeback: rakebackPct,
            payoutMode: uint8(PayoutMode.Coinflip)
        });
        emit Affiliate(1, code_, owner); // 1 = code created
    }

    /// @dev Referral assignment logic for constructor bootstrapping.
    function _bootstrapReferral(address player, bytes32 code_) private {
        if (player == address(0)) revert Zero();
        AffiliateCodeInfo storage info = affiliateCode[code_];
        address referrer = info.owner;
        if (referrer == address(0) || referrer == player) revert Insufficient();
        if (playerReferralCode[player] != bytes32(0)) revert Insufficient();
        _setReferralCode(player, code_);
        emit Affiliate(0, code_, player); // 0 = player referred
    }

    /// @dev Route affiliate rewards by code-configured payout mode.
    ///      Amounts are already BURNIE-denominated (MintModule converts via _ethToBurnieValue).
    function _routeAffiliateReward(
        address player,
        uint256 amount,
        uint8 modeRaw
    ) private {
        if (player == address(0) || amount == 0) return;
        if (modeRaw == uint8(PayoutMode.Degenerette)) {
            uint256 newBalance = pendingDegeneretteCredit[player] + amount;
            pendingDegeneretteCredit[player] = newBalance;
            emit DegeneretteCreditUpdated(player, true, amount, newBalance);
            return;
        }
        if (modeRaw == uint8(PayoutMode.SplitCoinflipCoin)) {
            uint256 coinAmount = amount >> 1;
            coin.creditCoin(player, coinAmount);
            return;
        }
        // Default mode: coinflip (modeRaw=0 or unknown).
        coin.creditFlip(player, amount);
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
            emit AffiliateTopUpdated(lvl, player, score);
        }
    }

    /// @dev Reduce affiliate payout for high-activity lootbox buyers.
    ///      Linear taper: 100% at score 15000 → 50% at score 25500+.
    function _applyLootboxTaper(uint256 amt, uint16 score) private pure returns (uint256) {
        if (score >= LOOTBOX_TAPER_END_SCORE) {
            return (amt * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;
        }
        uint256 excess = uint256(score) - LOOTBOX_TAPER_START_SCORE;
        uint256 range = uint256(LOOTBOX_TAPER_END_SCORE) - LOOTBOX_TAPER_START_SCORE;
        uint256 reductionBps = (BPS_DENOMINATOR - LOOTBOX_TAPER_MIN_BPS) * excess / range;
        return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;
    }

    /// @dev Select one recipient with probability proportional to their amount.
    function _rollWeightedAffiliateWinner(
        address[3] memory players,
        uint256[3] memory amounts,
        uint256 count,
        uint256 totalAmount,
        address sender,
        bytes32 storedCode
    ) private view returns (address winner) {
        uint48 currentDay = GameTimeLib.currentDayIndex();

        uint256 entropy = uint256(
            keccak256(
                abi.encodePacked(
                    AFFILIATE_ROLL_TAG,
                    currentDay,
                    sender,
                    storedCode
                )
            )
        );
        uint256 roll = entropy % totalAmount;

        uint256 running;
        for (uint256 i; i < count; ) {
            running += amounts[i];
            if (roll < running) return players[i];
            unchecked {
                ++i;
            }
        }
        // Should be unreachable for totalAmount > 0, but keep deterministic fallback.
        return players[0];
    }
}
