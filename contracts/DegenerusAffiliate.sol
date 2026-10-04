// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {ContractAddresses} from "./ContractAddresses.sol";
import {AffiliateIdentityLib} from "./libraries/AffiliateIdentityLib.sol";

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";

/**
 * @title DegenerusAffiliate
 * @author Burnie Degenerus
 * @notice Multi-tier affiliate referral system with configurable kickback.
 *
 * @dev ARCHITECTURE:
 *      - 3-tier referral: Player → Affiliate (75%) / Upline1 (20%) / Upline2 (5%) winner-takes-all roll
 *      - Default codes: every address has an implicit code (bytes32(uint256(uint160(addr))))
 *        with 0% kickback, no tx required. Custom codes use high bytes (string-encoded),
 *        so the two namespaces cannot collide.
 *      - Kickback: 0-25% of reward returned to referred player (custom codes only)
 *      - Affiliate payouts + quest bonuses via coinflip.creditFlip; kickback returned to caller
 *      - Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+)
 *      - Recycled ETH rewards: 5% (all levels)
 *      - Leaderboard: tracks top affiliate per level for a DGNRS pool reward at level transition
 *
 * @dev SECURITY:
 *      - Access control: payAffiliate / payAffiliateCombined (game only); claim (permissionless settlement)
 *      - Referral locking: invalid codes lock slot (REF_CODE_LOCKED sentinel)
 *      - Fixed contract addresses at deploy (no re-pointing)
 */

/// @notice Interface for quest handler calls from the affiliate contract.
interface IDegenerusQuestsAffiliate {
    /// @notice Record affiliate quest progress and return reward.
    /// @dev Declares only the leading `reward` word of the callee's return data;
    ///      surplus returndata is ignored per ABI decoding rules.
    /// @param player The affiliate receiving the base reward.
    /// @param amount The base affiliate amount (before quest bonus).
    /// @return reward Quest reward amount earned (0 if quest not completed).
    function handleAffiliate(address player, uint256 amount)
        external returns (uint256 reward);
}

/// @notice Interface for crediting FLIP stakes directly via the coinflip contract.
interface ICoinflipAffiliate {
    /// @notice Credit FLIP to a single player.
    /// @param player Recipient address.
    /// @param amount Amount of FLIP (0 decimals).
    function creditFlip(address player, uint256 amount) external;
}

/// @notice Game-side accessor for the afking affiliate-base PULL.
/// @dev The atomic read-and-zero of a sub's accrued `affiliateBase` (the running unclaimed flat-7%
///      affiliate balance, WHOLE FLIP) happens AT THE STORAGE OWNER (the Game / GameAfkingModule via
///      delegatecall) — guardrail 1: the affiliate `claim` consumer can NEVER pre-load the
///      bases into a memory array, so a duplicate sub in `subs[]` drains 0 the second time. The accessor
///      is AFFILIATE-gated on the Game side (only `ContractAddresses.AFFILIATE` may drain).
interface IGameAfkingDrain {
    /// @notice Atomic read-and-zero of a sub's accrued affiliate base (whole FLIP).
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained / never accrued).
    function drainAffiliateBase(address sub) external returns (uint256 base);

    /// @notice Current game level (the claim-time level basis for the leaderboard write).
    /// @return Current jackpot level (starts at 0).
    function level() external view returns (uint24);
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
    /// @notice Emitted when a player's permanent referral code is set.
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
    /// @param affiliate The affiliate receiving credit.
    /// @param packed The two payload fields in one word; layout below.
    /// @dev The protocol's highest-volume event, so it carries only what nothing else does.
    ///      Dropped as sibling-derivable within the receipt: `amount` (the delta of this
    ///      affiliate's `newTotal` at this level), `sender` (the buyer on purchase paths, the
    ///      affiliate itself on the claim path), `code` (the ReferralUpdated projection —
    ///      `_setReferralCode` is the sole writer of playerReferralCode and always emits;
    ///      a projection value of REF_CODE_LOCKED books here as AFFILIATE_CODE_VAULT), and
    ///      `targetDay` (the CoinflipStakeUpdated sibling), and `isFreshEth` — which no
    ///      consumer read and which could not mean what its name said: payAffiliateCombined
    ///      pools four fresh and recycled legs into ONE emit, so it reported "fresh" for a
    ///      recycled-only purchase. The fresh/recycled rate split still drives the payout
    ///      (see `_scaleLeg`); it is simply not a fact this event can carry honestly.
    ///      What remains rides ONE word rather than five 32-byte slots.
    ///      Packed layout (LSB -> MSB):
    ///      - [0..23]   level: the level this credit books against. Deliberately not a topic —
    ///                  nothing filters by it, and it is not always the current level (the
    ///                  claim path books at level + 1).
    ///      - [24..255] newTotal: the affiliate's running total at that level — the
    ///                  leaderboard state itself. A single credit's amount is this minus the
    ///                  prior total. Note the winner-takes-all payout roll may pay an upline
    ///                  instead; the recipient is the coinflip credit in the same receipt,
    ///                  never this field. 232 bits is far above any reachable FLIP-scaled
    ///                  total, so the shift never truncates.
    ///      Widths are load-bearing: no version field rides this word, so a width change must
    ///      rename the event rather than shift bits under a live decoder.
    event AffiliateEarningsRecorded(address indexed affiliate, uint256 packed);

    /// @dev `AffiliateEarningsRecorded.packed` field offset.
    uint256 private constant AFF_EARN_TOTAL_SHIFT = 24;
    /// @notice Emitted when the top affiliate for a level changes.
    /// @param level The game level.
    /// @param player The new top affiliate.
    /// @param score The new top score (uint96-capped).
    event AffiliateTopUpdated(
        uint24 indexed level,
        address indexed player,
        uint96 score
    );

    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not the game contract.
    error OnlyAuthorized();


    /// @notice Thrown when code creation is given a zero owner or a zero/reserved code, or referral bootstrapping a zero player.
    error Zero();

    /// @notice Generic insufficient condition error (code taken, invalid referral, array length mismatch).
    error Insufficient();

    /// @notice Thrown when kickback percentage exceeds the maximum allowed (25%).
    error InvalidKickback();

    /// @notice Per-affiliate whole-token earnings exceed the packed amount field.
    error EarningsOverflow();

    // =====================================================================
    //                              TYPES
    // =====================================================================

    /**
     * @notice Affiliate code ownership and kickback configuration.
     * @dev Packed into single storage slot for gas efficiency.
     *
     * STORAGE LAYOUT (32 bytes, 30 bytes used):
     * +----------------------------------------------------+
     * | [0:20]  owner     address   Code owner/recipient   |
     * | [20:21] kickback  uint8     Kickback % (0-25)      |
     * | [21:25] upline1   uint32    immutable first hop ID  |
     * | [25:29] upline2   uint32    immutable second hop ID |
     * | [29:30] flags     uint8     registration/cache bits |
     * | [30:32] unused    ---       2 bytes padding        |
     * +----------------------------------------------------+
     */
    struct AffiliateCodeInfo {
        address owner; // 20 bytes - receives affiliate rewards
        uint8 kickback; // bits 160..167: code-specific percentage (0-25)
        uint32 upline1; // bits 168..199: permanent wallet ID, only when its flag is valid
        uint32 upline2; // bits 200..231: permanent wallet ID, only when its flag is valid
        uint8 flags; // bit 0: registered at creation; bits 1/2: immutable upline cache validity
    }

    // =====================================================================
    //                            CONSTANTS
    // =====================================================================

    /// @notice Maximum bonus points an affiliate can earn from recent earnings.
    /// @dev Contributes to the player's activity score (lootbox EV, ticket bonus, Degenerette ROI); capped at 50 points (50%).
    uint256 private constant AFFILIATE_BONUS_MAX = 50;
    uint8 private constant MAX_KICKBACK_PCT = 25;
    uint16 private constant REWARD_SCALE_FRESH_L1_3_BPS = 2_500;
    uint16 private constant REWARD_SCALE_FRESH_L4P_BPS = 2_000;
    uint16 private constant REWARD_SCALE_RECYCLED_BPS = 500;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant LOOTBOX_TAPER_START_SCORE = 100;
    uint16 private constant LOOTBOX_TAPER_END_SCORE = 255;
    uint16 private constant LOOTBOX_TAPER_MIN_BPS = 2_500;
    /// @dev FLIP base units per whole ticket (mirrors the Game's PRICE_COIN_UNIT).
    ///      Converts a level's FLIP-basis affiliate score back to ETH via that
    ///      level's ticket price: ethValue = score * priceForLevel(lvl) / PRICE_COIN_UNIT.
    uint256 private constant PRICE_COIN_UNIT = 1000;
    /// @dev Early-exit bound for the bonus-points window scan: the score-price product
    ///      at which weighted referred volume reaches the 25 ETH points cap.
    uint256 private constant BONUS_CAP_VOLUME_PRODUCT =
        (25 ether * uint256(REWARD_SCALE_FRESH_L4P_BPS) * PRICE_COIN_UNIT) /
            BPS_DENOMINATOR;
    bytes32 private constant AFFILIATE_ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    /// @dev `_totalAffiliateScore` word: bits [0:160) level total, bits [160:256) leader score.
    uint256 private constant TOTAL_SCORE_MASK = type(uint160).max;
    uint256 private constant TOP_SCORE_SHIFT = 160;
    /// @dev Earnings word: amount [0:128), upline IDs [128:160)/[160:192), valid bits 192/193.
    uint256 private constant EARNINGS_MASK = type(uint128).max;
    uint256 private constant UPLINE1_VALID = uint256(1) << 64;
    uint256 private constant UPLINE2_VALID = uint256(1) << 65;

    /// @notice Sentinel value indicating a player's referral slot is permanently locked.
    /// @dev Set when a player makes an invalid referral attempt (self-referral, unknown code)
    ///      after the game has started. Prevents gaming by trying multiple codes.
    bytes32 private constant REF_CODE_LOCKED = bytes32(uint256(1));
    bytes32 private constant AFFILIATE_CODE_VAULT = bytes32("VAULT");
    bytes32 private constant AFFILIATE_CODE_DGNRS = bytes32("DGNRS");

    /// @notice DegenerusQuests contract for direct quest handler calls (constant).
    IDegenerusQuestsAffiliate internal constant quests = IDegenerusQuestsAffiliate(ContractAddresses.QUESTS);
    /// @notice Coinflip contract for direct flip crediting (constant).
    ICoinflipAffiliate internal constant coinflip = ICoinflipAffiliate(ContractAddresses.COINFLIP);
    /// @notice Game contract for the shared permanent wallet registry (constant).
    IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);
    /// @notice Game-side afking accessor for the affiliate-base PULL drain + claim-time level (constant).
    /// @dev Same address as `game` (the GameAfkingModule runs in the Game's storage context via
    ///      delegatecall); a distinct typed handle for the `drainAffiliateBase` / `level` calls the
    ///      flat-7% deterministic-split PULL consumes.
    IGameAfkingDrain internal constant afkingDrain = IGameAfkingDrain(ContractAddresses.GAME);

    // =====================================================================
    //                        AFFILIATE STATE
    // =====================================================================

    /// @notice Mapping from affiliate code (bytes32) to ownership info.
    /// @dev codes are permanent once created; owner cannot be changed.
    ///      Reserved value: bytes32(0) = invalid, bytes32(1) = REF_CODE_LOCKED sentinel.
    mapping(bytes32 => AffiliateCodeInfo) private _affiliateCode;

    /// @notice Original code-info ABI; default codes always retain implicit ownership.
    function affiliateCode(bytes32 code) external view returns (address owner, uint8 kickback) {
        AffiliateCodeInfo storage info = _affiliateCode[code];
        return (info.owner, info.kickback);
    }

    /// @notice Shared permanent ID of the resolved code owner, or zero before first registration.
    function affiliateWalletId(bytes32 code) external view returns (uint32) {
        return AffiliateIdentityLib.walletId(_resolveCodeOwner(code));
    }

    event AffiliateOwnerRegistered(bytes32 indexed code, address indexed owner, uint32 id);

    /// @notice Per-level earnings and immutable upline cache, keyed by affiliate.
    /// @dev Used for leaderboard calculations and activity score bonus points.
    ///      Low 128 bits are whole FLIP; high bits cache two permanent wallet IDs and validity.
    ///      Direct affiliate earnings only; upline rewards are excluded for gas.
    ///      Kickback does not reduce the tracked score.
    mapping(uint24 => mapping(address => uint256)) private affiliateCoinEarned;

    /// @notice Player's chosen referral code (or REF_CODE_LOCKED if locked).
    /// @dev Private to prevent external manipulation; no public getter.
    ///      bytes32(0) = not yet set, REF_CODE_LOCKED = permanently locked.
    mapping(address => bytes32) private playerReferralCode;

    /// @notice Top affiliate per game level for bonus calculations.
    /// @dev Private storage; use affiliateTop() view to read. Written by _recordScore only
    ///      when the lead changes; the leader's score lives in `_totalAffiliateScore`.
    mapping(uint24 => address) private affiliateTopByLevel;

    /// @notice Total affiliate score across all affiliates for a level, packed with the
    ///      leader's score.
    /// @dev Bits [0:160): running sum, the exact denominator for score-proportional DGNRS
    ///      claim distribution. Bits [160:256): the leader's uint96-capped score. Every
    ///      earning already rewrites this word, so checking the lead reads no other slot.
    mapping(uint24 => uint256) private _totalAffiliateScore;

    // =====================================================================
    //                              CONSTRUCTOR
    // =====================================================================

    /// @notice Wires the VAULT and sDGNRS default codes as each other's referrer, then
    ///         registers the deploy-time bootstrap affiliate codes and referrals.
    /// @param bootstrapOwners Owners of the bootstrap affiliate codes to create.
    /// @param bootstrapCodes Bootstrap affiliate codes, one per owner.
    /// @param bootstrapKickbacks Kickback percentage per bootstrap code.
    /// @param bootstrapPlayers Players to register a bootstrap referral for.
    /// @param bootstrapReferralCodes Referral code each bootstrap player is registered under.
    constructor(
        address[] memory bootstrapOwners,
        bytes32[] memory bootstrapCodes,
        uint8[] memory bootstrapKickbacks,
        address[] memory bootstrapPlayers,
        bytes32[] memory bootstrapReferralCodes
    ) {
        if (
            bootstrapOwners.length != bootstrapCodes.length ||
            bootstrapOwners.length != bootstrapKickbacks.length ||
            bootstrapPlayers.length != bootstrapReferralCodes.length
        ) revert Insufficient();

        _affiliateCode[AFFILIATE_CODE_VAULT] = AffiliateCodeInfo({
            owner: ContractAddresses.VAULT,
            kickback: 0, upline1: 0, upline2: 0, flags: 0
        });
        _affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({
            owner: ContractAddresses.SDGNRS,
            kickback: 0, upline1: 0, upline2: 0, flags: 0
        });
        emit Affiliate(1, AFFILIATE_CODE_VAULT, ContractAddresses.VAULT);
        emit Affiliate(1, AFFILIATE_CODE_DGNRS, ContractAddresses.SDGNRS);

        _setReferralCode(ContractAddresses.VAULT, AFFILIATE_CODE_DGNRS);
        _setReferralCode(ContractAddresses.SDGNRS, AFFILIATE_CODE_VAULT);
        emit Affiliate(0, AFFILIATE_CODE_DGNRS, ContractAddresses.VAULT);
        emit Affiliate(0, AFFILIATE_CODE_VAULT, ContractAddresses.SDGNRS);

        uint256 len = bootstrapOwners.length;
        for (uint256 i; i < len; ) {
            _createAffiliateCode(
                bootstrapOwners[i],
                bootstrapCodes[i],
                bootstrapKickbacks[i]
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

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "affiliate.degenerus.eth")
            );
            ok;
        }
    }

    // =====================================================================
    //                    EXTERNAL PLAYER ENTRYPOINTS
    // =====================================================================

    /**
     * @notice Create a new affiliate code owned by the caller.
     * @dev Anyone can create an affiliate code. Codes are permanent and cannot be
     *      transferred or deleted. The kickback percentage determines how much of
     *      the affiliate reward is returned to referred players as an incentive.
     *
     * VALIDATION:
     * - code_ != bytes32(0) (reserved for "no code")
     * - code_ != REF_CODE_LOCKED (reserved sentinel value)
     * - code_ not in address-derived range (uint256(code_) <= type(uint160).max)
     * - kickbackPct <= 25 (max 25% kickback)
     * - code_ not already taken
     *
     * @param code_ The affiliate code to claim (typically a short string cast to bytes32).
     * @param kickbackPct Percentage of rewards returned to referred players (0-25).
     */
    function createAffiliateCode(bytes32 code_, uint8 kickbackPct) external {
        _createAffiliateCode(msg.sender, code_, kickbackPct);
    }

    /**
     * @notice Register the caller as referred by an affiliate code.
     * @dev This is the explicit user-initiated way to set a referrer.
     *      Accepts both custom codes and default address-derived codes.
     *      Alternatively, referrers can be set implicitly during payAffiliate().
     *      Once set, cannot be changed, including VAULT and locked defaults during presale.
     *
     * VALIDATION:
     * - code_ must resolve to a valid owner (custom or default)
     * - code_ owner must not be the caller (no self-referral)
     * - caller must not already have a referral code set
     *
     * @param code_ The affiliate code to register under.
     */
    function referPlayer(bytes32 code_) external {
        address referrer = _resolveCodeOwner(code_);
        // SECURITY: Prevent invalid codes and self-referral.
        if (referrer == address(0) || referrer == msg.sender) revert Insufficient();
        bytes32 existing = playerReferralCode[msg.sender];
        // SECURITY: Every assigned referral is permanent.
        if (existing != bytes32(0)) revert Insufficient();
        _setReferralCode(msg.sender, code_);
        emit Affiliate(0, code_, msg.sender); // 0 = player referred
    }

    /**
     * @notice Get the referrer address for a player.
     * @dev Never returns address(0): resolves to the VAULT when the player has no valid
     *      referrer (code unset, locked, vault-coded, or its owner unresolvable). Chains are
     *      not acyclic (VAULT and SDGNRS refer each other; mutual player referrals are
     *      allowed); payouts walk at most two upline hops from the direct referrer.
     * @param player The player to look up.
     * @return The referrer's address (the VAULT when the player has no real referrer).
     */
    function getReferrer(address player) external view returns (address) {
        return _referrerAddress(player);
    }

    /// @notice Compute the default affiliate code for any address.
    /// @dev Pure helper for frontend link generation: bytes32(uint256(uint160(addr))).
    function defaultCode(address addr) external pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // =====================================================================
    //                    GAMEPLAY ENTRYPOINTS
    // =====================================================================

    /**
     * @notice Process affiliate rewards for a purchase or gameplay action.
     * @dev Core payout logic. Handles referral resolution, reward scaling,
     *      and multi-tier distribution.
     *
 * ACCESS: game only.
     *
     * REWARD FLOW:
     * +--------------------------------------------------------------------+
     * | 1. Resolve referral code (stored or provided)                      |
     * | 2. Apply reward percentage based on ETH type and level             |
     * | 3. Apply lootbox activity taper if applicable                      |
     * | 4. Update leaderboard (post-taper amount)                          |
     * | 5. Calculate kickback (returned to caller for player credit)       |
     * | 6. Roll 75/20/5 between affiliate, upline1, upline2                |
     * | 7. Winner gets full pot (scaled - kickback) + quest reward         |
     * +--------------------------------------------------------------------+
     *
     * REWARD RATES:
     * - Fresh ETH (levels 1-3): 25% (REWARD_SCALE_FRESH_L1_3_BPS = 2500)
     * - Fresh ETH (levels 4+): 20% (REWARD_SCALE_FRESH_L4P_BPS = 2000)
     * - Recycled ETH (all levels): 5% (REWARD_SCALE_RECYCLED_BPS = 500)
     *
     * LOOTBOX TAPER (fresh ETH only):
     * - Activity score < 100: no taper (100% payout)
     * - Activity score 100-255: linear taper from 100% to 25%
     * - Activity score >= 255: 25% payout floor (LOOTBOX_TAPER_MIN_BPS = 2500)
     *
     * @param amount Base reward amount (0 decimals).
     * @param code Affiliate code provided with the transaction (may be bytes32(0)).
     * @param sender The player making the purchase.
     * @param lvl Current game level (for join tracking and leaderboard).
     * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
     * @param lootboxActivityScore Buyer's activity score (whole points) for lootbox taper (0 = no taper; 100+ triggers linear taper to 25% floor at 255).
     * @return playerKickback Amount of kickback to credit to the player (caller handles minting and batching).
     */
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        address sender,
        uint24 lvl,
        bool isFreshEth,
        uint16 lootboxActivityScore
    ) external returns (uint256 playerKickback) {
        // -----------------------------------------------------------------
        // ACCESS CONTROL
        // -----------------------------------------------------------------
        // SECURITY: Only the game contract can distribute affiliate rewards.
        if (msg.sender != ContractAddresses.GAME) revert OnlyAuthorized();

        // -----------------------------------------------------------------
        // REFERRAL RESOLUTION
        // -----------------------------------------------------------------
        (address affiliateAddr, uint8 kickbackPct, bytes32 storedCode, bool noReferrer) =
            _resolveReferral(sender, code);

        uint256 earningsWord = affiliateCoinEarned[lvl][affiliateAddr];
        _ensureBootstrapIdentity(storedCode, affiliateAddr, earningsWord);

        // -----------------------------------------------------------------
        // REWARD CALCULATION
        // -----------------------------------------------------------------
        // Apply reward percentage based on ETH type and level.
        // - Fresh ETH (levels 1-3, paid at level + 1): 25%
        // - Fresh ETH (levels 4+): 20%
        // - Recycled ETH: 5%
        uint256 rewardScaleBps;
        if (isFreshEth) {
            // Fresh ETH: 25% at levels 1-3, 20% at levels 4+ (lvl is the paying level + 1)
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

        // Taper payout for high-activity lootbox buyers before leaderboard tracking.
        if (lootboxActivityScore >= LOOTBOX_TAPER_START_SCORE) {
            scaledAmount = _applyLootboxTaper(scaledAmount, lootboxActivityScore);
        }

        // Calculate kickback (returned to player) and affiliate share.
        uint256 affiliateShareBase;
        uint256 kickbackShare;
        if (kickbackPct == 0) {
            affiliateShareBase = scaledAmount;
        } else {
            kickbackShare = (scaledAmount * uint256(kickbackPct)) / 100;
            affiliateShareBase = scaledAmount - kickbackShare;
        }

        playerKickback = kickbackShare;

        address winner;
        if (affiliateShareBase != 0) {
            (winner, earningsWord) = _purchaseWinner(storedCode, affiliateAddr, sender, noReferrer, earningsWord);
        }
        // Cache fills share the existing earnings write. Commit before quest/credit calls.
        _recordEarnings(lvl, affiliateAddr, scaledAmount, earningsWord);
        if (affiliateShareBase != 0) {
            if (noReferrer) {
                coinflip.creditFlip(winner, affiliateShareBase);
            } else if (winner != sender) {
                uint256 questReward = quests.handleAffiliate(winner, affiliateShareBase);
                coinflip.creditFlip(winner, affiliateShareBase + questReward);
            }
        }

        emit Affiliate(amount, storedCode, sender);
        return playerKickback;
    }

    /**
     * @notice Purchase-path affiliate settlement for all of a buy's legs in ONE call.
     * @dev GAME-only. Folds the up-to-four per-leg payAffiliate calls (ticket fresh/recycled +
     *      lootbox fresh/recycled) into a single frame: resolves the referral once, scales each leg
     *      at its own rate (fresh/recycled bps, taper on the lootbox-fresh leg) so per-component
     *      rounding matches the separate calls, pools the scaled total into ONE leaderboard write
     *      (all legs credit the same affiliate at the same level), then rolls ONE winner on the
     *      shared (day, sender, code) entropy and credits the winner via ONE quest hop. The winner
     *      credit is RETURNED, not paid here, so the caller batches it with the buyer's credit into
     *      one Coinflip write. payAffiliate (foil path) is left unchanged.
     * @param code Referral code supplied with the buy (resolved + locked once).
     * @param sender The buyer.
     * @param lvl Leaderboard level for all legs (ticket and lootbox both freeze at level + 1).
     * @param tktFreshFlip Ticket-leg fresh spend in FLIP base units (fresh bps).
     * @param tktRecycledFlip Ticket-leg recycled spend in FLIP base units (recycled bps).
     * @param lbFreshFlip Lootbox-leg fresh spend in FLIP base units (fresh bps, tapered).
     * @param lbRecycledFlip Lootbox-leg recycled spend in FLIP base units (recycled bps).
     * @param lbFreshScore Activity score tapering the lootbox-fresh leg (0 = no taper).
     * @return winner Single rolled recipient of the pooled affiliate share.
     * @return winnerCredit FLIP owed the winner (share + quest reward); 0 if none or winner==sender.
     * @return playerKickback FLIP kickback owed the buyer (summed across legs).
     * @custom:reverts OnlyAuthorized When caller is not the GAME contract.
     */
    function payAffiliateCombined(
        bytes32 code,
        address sender,
        uint24 lvl,
        uint256 tktFreshFlip,
        uint256 tktRecycledFlip,
        uint256 lbFreshFlip,
        uint256 lbRecycledFlip,
        uint16 lbFreshScore
    )
        external
        returns (address winner, uint256 winnerCredit, uint256 playerKickback)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyAuthorized();
        (
            address affiliateAddr,
            uint8 kickbackPct,
            bytes32 storedCode,
            bool noReferrer
        ) = _resolveReferral(sender, code);
        uint256 earningsWord = affiliateCoinEarned[lvl][affiliateAddr];
        _ensureBootstrapIdentity(storedCode, affiliateAddr, earningsWord);

        // Scale each leg at its OWN rate (fresh/recycled bps, taper on the lootbox-fresh leg) so
        // per-component rounding matches four separate calls; then pool. All four legs credit the
        // same affiliate at the same level, so the leaderboard takes ONE read-modify-write.
        uint256 sumScaled;
        {
            (uint256 sc, uint256 kb) = _scaleLeg(tktFreshFlip, true, lvl, 0, kickbackPct);
            sumScaled += sc;
            playerKickback += kb;
            (sc, kb) = _scaleLeg(tktRecycledFlip, false, lvl, 0, kickbackPct);
            sumScaled += sc;
            playerKickback += kb;
            (sc, kb) = _scaleLeg(lbFreshFlip, true, lvl, lbFreshScore, kickbackPct);
            sumScaled += sc;
            playerKickback += kb;
            (sc, kb) = _scaleLeg(lbRecycledFlip, false, lvl, 0, kickbackPct);
            sumScaled += sc;
            playerKickback += kb;
        }
        if (sumScaled == 0) return (address(0), 0, playerKickback);

        uint256 sumShareBase = sumScaled - playerKickback;
        if (sumShareBase != 0) {
            (winner, earningsWord) = _purchaseWinner(storedCode, affiliateAddr, sender, noReferrer, earningsWord);
        }
        _recordEarnings(lvl, affiliateAddr, sumScaled, earningsWord);
        if (sumShareBase != 0) {
            if (noReferrer) {
                winnerCredit = sumShareBase;
            } else if (winner != sender) {
                winnerCredit = sumShareBase + quests.handleAffiliate(winner, sumShareBase);
            }
        }
    }

    /// @dev Pure per-leg affiliate scaling: scale at the leg's bps (fresh L1-3 25% / L4+ 20%,
    ///      recycled 5%), apply the lootbox taper, and split off the buyer kickback. The caller
    ///      pools the scaled amounts into one leaderboard write, so this touches no state.
    function _scaleLeg(
        uint256 flipAmount,
        bool isFresh,
        uint24 lvl,
        uint16 score,
        uint8 kickbackPct
    ) private pure returns (uint256 scaled, uint256 kickback) {
        if (flipAmount == 0) return (0, 0);
        uint256 rewardScaleBps = isFresh
            ? (lvl <= 3 ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS)
            : REWARD_SCALE_RECYCLED_BPS;
        scaled = (flipAmount * rewardScaleBps) / BPS_DENOMINATOR;
        if (scaled == 0) return (0, 0);
        if (score >= LOOTBOX_TAPER_START_SCORE) {
            scaled = _applyLootboxTaper(scaled, score);
        }
        if (kickbackPct != 0) {
            kickback = (scaled * uint256(kickbackPct)) / 100;
        }
    }

    /// @dev Resolve + lock the buyer's referral once (exact extraction of payAffiliate's resolution
    ///      block). Returns the affiliate address, kickback %, normalized stored code, and whether
    ///      the buyer has no real referrer (VAULT default).
    function _resolveReferral(address sender, bytes32 code)
        private
        returns (address affiliateAddr, uint8 kickbackPct, bytes32 storedCode, bool noReferrer)
    {
        storedCode = playerReferralCode[sender];
        if (storedCode == bytes32(0)) {
            if (code == bytes32(0)) {
                _setReferralCode(sender, REF_CODE_LOCKED);
                storedCode = AFFILIATE_CODE_VAULT;
                affiliateAddr = ContractAddresses.VAULT;
                noReferrer = true;
            } else {
                (address resolved, uint8 resolvedKickback) = _resolveCodeInfo(code);
                if (resolved == address(0) || resolved == sender) {
                    _setReferralCode(sender, REF_CODE_LOCKED);
                    storedCode = AFFILIATE_CODE_VAULT;
                    affiliateAddr = ContractAddresses.VAULT;
                    noReferrer = true;
                } else {
                    _setReferralCode(sender, code);
                    affiliateAddr = resolved;
                    kickbackPct = resolvedKickback;
                    storedCode = code;
                }
            }
        } else if (storedCode == REF_CODE_LOCKED) {
            storedCode = AFFILIATE_CODE_VAULT;
            affiliateAddr = ContractAddresses.VAULT;
            noReferrer = true;
        } else {
            (affiliateAddr, kickbackPct) = _resolveCodeInfo(storedCode);
        }
    }

    // =====================================================================
    //              AFKING AFFILIATE — FLAT-7% DETERMINISTIC-SPLIT PULL
    // =====================================================================

    /**
     * @notice Settle a batch of afking subs' accrued affiliate base to the upline chain.
     * @dev Permissionless. Every sub in `subs` must resolve to the same direct affiliate `A` (mixed
     *      batches revert), so the chain A / U1 / U2 is resolved once. Each sub's accrued `affiliateBase`
     *      is drained atomically at the storage owner via `drainAffiliateBase` — a duplicate sub drains 0
     *      the second time, so it can't be double-counted. The batch total `sumB` is split 75/20/5
     *      (A 75% / U1 20% / U2 5%), floored with the remainder to A so the parts never exceed `sumB`.
     *      `skipU1`/`skipU2` reduce that upline's share for the rare case where the upline is itself
     *      the sub; the freed portion folds into A's remainder (A is never the sub — self-referral
     *      resolves to VAULT). No-referrer subs split 50/50 VAULT/sDGNRS.
     *      The split is fixed (no roll, no seed), so claiming on any day yields the same result.
     *      Recipients are paid directly via `creditFlip` (FLIP; no ETH/`claimablePool` touch).
     * @param subs Afking subscribers to settle; all must share the same direct affiliate `A` (from subs[0]).
     */
    function claim(address[] calldata subs) external {
        uint256 n = subs.length;
        if (n == 0) return;

        // Resolve the upline chain ONCE from subs[0]. `A != sub` is guaranteed by the referral layer
        // (self-referral resolves to VAULT), so the 75% leg never skips to a buyer.
        address a = _referrerAddress(subs[0]);
        bool noReferrer = a == ContractAddresses.VAULT;
        bytes32 routeCode = playerReferralCode[subs[0]];
        if (routeCode == bytes32(0) || routeCode == REF_CODE_LOCKED) routeCode = AFFILIATE_CODE_VAULT;
        uint24 lvl = afkingDrain.level() + 1;
        uint256 earningsWord = affiliateCoinEarned[lvl][a];
        _ensureBootstrapIdentity(routeCode, a, earningsWord);
        address u1;
        address u2;
        if (!noReferrer) {
            uint256 cache = _routeCache(routeCode, earningsWord);
            (u1, cache) = _payoutUpline(a, false, cache);
            (u2, cache) = _payoutUpline(a, true, cache);
            earningsWord = (earningsWord & EARNINGS_MASK) | (cache << 128);
        }

        uint256 sumB;
        uint256 skipU1;
        uint256 skipU2;

        for (uint256 i; i < n; ) {
            address sub = subs[i];
            // SAME-AFFILIATE batch: every sub MUST resolve to the same direct affiliate (mixed reverts).
            // subs[0] defines `a`, so only later entries need the check.
            if (i != 0 && _referrerAddress(sub) != a) revert Insufficient();

            // Atomic read-and-zero at the storage owner: a duplicate sub drains 0 the second time.
            uint256 b = afkingDrain.drainAffiliateBase(sub);
            if (b != 0) {
                sumB += b;
                // The rare mutual-referral cycle (an upline IS the sub): that upline's cut for
                // this base folds into A's remainder — it is never paid back to the sub.
                if (!noReferrer) {
                    if (sub == u1) skipU1 += b;
                    if (sub == u2) skipU2 += b;
                }
            }

            unchecked { ++i; }
        }

        if (sumB == 0) return; // nothing accrued / already drained — no-op (idempotent re-claim)

        if (noReferrer) {
            // No referrer: 50/50 VAULT/sDGNRS, remainder to VAULT (whole FLIP).
            uint256 sdgnrsShare = sumB / 2;
            uint256 vaultShare = sumB - sdgnrsShare;
            coinflip.creditFlip(ContractAddresses.VAULT, vaultShare);
            coinflip.creditFlip(ContractAddresses.SDGNRS, sdgnrsShare);
            return;
        }

        // 75/20/5 split, floored with the remainder to A so the parts never exceed sumB.
        uint256 u1Share = ((sumB - skipU1) * 20) / 100;
        uint256 u2Share = ((sumB - skipU2) * 5) / 100;
        uint256 aShare = sumB - u1Share - u2Share;

        // Leaderboard credit to A at the next level (level() + 1, the level the subs' tickets buy
        // into; sumB already uses whole-token units).
        _recordEarnings(lvl, a, sumB, earningsWord);

        // Pay the (at most 3) recipients directly. creditFlip is a pure ledger add (recordAmount=0).
        coinflip.creditFlip(a, aShare);
        if (u1Share != 0) coinflip.creditFlip(u1, u1Share);
        if (u2Share != 0) coinflip.creditFlip(u2, u2Share);
    }

    // =====================================================================
    //                              VIEWS
    // =====================================================================

    /**
     * @notice Get the top affiliate for a given game level.
     * @dev Returns the affiliate with the highest earnings for that level.
     *      Used to pay the top affiliate a DGNRS pool reward at level transition.
     * @param lvl The game level to query.
     * @return player Address of the top affiliate.
     * @return score Their score in FLIP base units (0 decimals).
     */
    function affiliateTop(uint24 lvl) external view returns (address player, uint96 score) {
        return (affiliateTopByLevel[lvl], uint96(_totalAffiliateScore[lvl] >> TOP_SCORE_SHIFT));
    }

    /**
     * @notice Get an affiliate's base earnings score for a level.
     * @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
     * @param lvl The game level to query.
     * @param player The affiliate address to query.
     * @return score The base affiliate score (0 decimals).
     */
    function affiliateScore(uint24 lvl, address player) external view returns (uint256 score) {
        return affiliateCoinEarned[lvl][player] & EARNINGS_MASK;
    }

    /**
     * @notice Get the total affiliate score across all affiliates for a level.
     * @dev Sum of all affiliateCoinEarned for this level. Used as the exact
     *      denominator for score-proportional DGNRS claim distribution.
     * @param lvl The game level to query.
     * @return total The total affiliate score (0 decimals).
     */
    function totalAffiliateScore(uint24 lvl) external view returns (uint256 total) {
        return _totalAffiliateScore[lvl] & TOTAL_SCORE_MASK;
    }

    /**
     * @notice Calculate the affiliate bonus points for a player.
     * @dev Sums the player's affiliate scores for the previous 5 levels, converting
     *      each level's FLIP-basis score to weighted referred ETH volume: score ×
     *      that level's ticket price / PRICE_COIN_UNIT, normalized by the 20% L4+
     *      fresh reward rate — so fresh referred ETH counts ~1:1 (recycled 0.25×,
     *      levels 0-3 fresh 1.25×). Tiered rate on that volume: 4 points per ETH
     *      for the first 5 ETH (20 pts), then 1.5 points per ETH for the next
     *      20 ETH (30 pts). Cap: 50 at 25 ETH.
     *
     * @param currLevel The current game level.
     * @param player The player to calculate bonus for.
     * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
     */
    function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points) {
        if (player == address(0) || currLevel == 0) return 0;
        // Σ score[lvl] × priceForLevel(lvl): ETH-volume product still carrying the
        // PRICE_COIN_UNIT and fresh-rate scale factors (normalized out below). Bounded
        // far below overflow: score is capped by real FLIP accrual, price ≤ 0.24 ether.
        uint256 sumProduct;
        unchecked {
            for (uint8 offset = 1; offset <= 5; ) {
                if (currLevel <= offset) break;
                uint24 lvl = currLevel - offset;
                sumProduct +=
                    (affiliateCoinEarned[lvl][player] & EARNINGS_MASK) *
                    PriceLookupLib.priceForLevel(lvl);
                // Points hit the AFFILIATE_BONUS_MAX cap at 25 ETH of weighted
                // volume; further reads cannot change the result.
                if (sumProduct >= BONUS_CAP_VOLUME_PRODUCT) break;
                ++offset;
            }
        }

        // Weighted referred ETH volume in wei.
        uint256 volEth = (sumProduct * BPS_DENOMINATOR) /
            (uint256(REWARD_SCALE_FRESH_L4P_BPS) * PRICE_COIN_UNIT);
        if (volEth == 0) return 0;
        if (volEth <= 5 ether) {
            points = (volEth * 4) / 1 ether;
        } else {
            points = 20 + ((volEth - 5 ether) * 3) / 2 ether;
        }
        return points > AFFILIATE_BONUS_MAX ? AFFILIATE_BONUS_MAX : points;
    }

    // =====================================================================
    //                        INTERNAL HELPERS
    // =====================================================================

    /// @dev Set player's referral code and emit a normalized event for indexers.
    function _setReferralCode(address player, bytes32 code) private {
        playerReferralCode[player] = code;
        bool locked = code == REF_CODE_LOCKED;
        address referrer;
        if (locked || code == AFFILIATE_CODE_VAULT) {
            referrer = ContractAddresses.VAULT;
        } else {
            referrer = _resolveCodeOwner(code);
        }
        // Affiliate deploys before Game. Bootstrap only sets referrals; first runtime use
        // registers their owners without assuming Game exists during construction.
        if (address(this).code.length != 0) {
            if (_affiliateCode[code].flags & 1 == 0) {
                _requireIdentity(locked ? AFFILIATE_CODE_VAULT : code, referrer);
            }
        }
        emit ReferralUpdated(player, code, referrer, locked);
    }

    /// @dev Defaults can only be assigned at runtime, where _setReferralCode registers
    ///      their owner. Runtime custom creation registers too. Only constructor codes need
    ///      this deferred check; their first earnings in a level certify registration without
    ///      allocating another storage slot or rewriting the code word.
    function _ensureBootstrapIdentity(bytes32 code, address owner, uint256 earningsWord) private {
        if (earningsWord != 0) return;
        AffiliateCodeInfo storage info = _affiliateCode[code];
        if (info.owner != address(0) && info.flags & 1 == 0) _requireIdentity(code, owner);
    }

    function _requireIdentity(bytes32 code, address owner) private returns (uint32 id) {
        id = AffiliateIdentityLib.walletId(owner);
        if (id == 0) {
            id = game.registerAffiliateOwner(owner, true);
            emit AffiliateOwnerRegistered(code, owner, id);
        }
    }

    /// @dev Only this helper writes earnings. Metadata never enters score math or events.
    function _recordEarnings(uint24 lvl, address owner, uint256 amount, uint256 word) private {
        uint256 total = (word & EARNINGS_MASK) + amount;
        if (total > EARNINGS_MASK) revert EarningsOverflow();
        affiliateCoinEarned[lvl][owner] = (word & ~EARNINGS_MASK) | total;
        emit AffiliateEarningsRecorded(owner, uint256(lvl) | (total << AFF_EARN_TOTAL_SHIFT));
        _recordScore(owner, total, amount, lvl);
    }

    function _purchaseWinner(bytes32 code, address owner, address buyer, bool noReferrer, uint256 word)
        private view returns (address winner, uint256 updatedWord)
    {
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            AFFILIATE_ROLL_TAG, GameTimeLib.currentDayIndex(), buyer, code
        )));
        if (noReferrer) {
            return (entropy % 2 == 0 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS, word);
        }
        uint256 roll = entropy % 20;
        if (roll < 15) return (owner, word);
        uint256 cache = _routeCache(code, word);
        (winner, cache) = _payoutUpline(owner, roll == 19, cache);
        updatedWord = (word & EARNINGS_MASK) | (cache << 128);
    }

    /// @dev Both caches belong to the same owner and contain only immutable IDs. A valid
    ///      field is identical in both copies; an invalid field is zero, so OR merges them.
    function _routeCache(bytes32 code, uint256 word) private view returns (uint256 cache) {
        AffiliateCodeInfo storage info = _affiliateCode[code];
        cache = (word >> 128) | uint256(info.upline1) | (uint256(info.upline2) << 32)
            | (uint256(info.flags >> 1) << 64);
    }

    function _stableReferrer(address owner) private view returns (address referrer, bool stable) {
        bytes32 code = playerReferralCode[owner];
        if (code == bytes32(0)) return (ContractAddresses.VAULT, false);
        if (code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) {
            return (ContractAddresses.VAULT, true);
        }
        referrer = _resolveCodeOwner(code);
        if (referrer == address(0)) return (ContractAddresses.VAULT, false);
        return (referrer, true);
    }

    /// @dev Cache only immutable links. Missing IDs fall back to address resolution;
    ///      routing never allocates an upline ID. The caller folds cache fills into its
    ///      existing earnings write (or the initial custom-code write).
    function _payoutUpline(address owner, bool second, uint256 cache)
        private view returns (address recipient, uint256 updatedCache)
    {
        updatedCache = cache;
        if (second && cache & UPLINE2_VALID != 0) {
            return (AffiliateIdentityLib.ownerOf(uint32(cache >> 32)), cache);
        }
        bool firstStable;
        if (cache & UPLINE1_VALID != 0) {
            recipient = AffiliateIdentityLib.ownerOf(uint32(cache));
            firstStable = true;
        } else {
            (recipient, firstStable) = _stableReferrer(owner);
            if (firstStable) {
                uint32 id = AffiliateIdentityLib.walletId(recipient);
                if (id != 0) updatedCache |= uint256(id) | UPLINE1_VALID;
            }
        }
        if (second) {
            bool secondStable;
            (recipient, secondStable) = _stableReferrer(recipient);
            if (firstStable && secondStable) {
                uint32 id = AffiliateIdentityLib.walletId(recipient);
                if (id != 0) updatedCache |= (uint256(id) << 32) | UPLINE2_VALID;
            }
        }
    }

    /// @dev Resolve code owner: custom code lookup first, then address-derived default code.
    ///      Returns address(0) only if code is unregistered AND not a valid default code.
    function _resolveCodeOwner(bytes32 code) private view returns (address) {
        address owner = _affiliateCode[code].owner;
        if (owner != address(0)) return owner;
        // Default code: low 20 bytes encode the owner address directly.
        if (uint256(code) <= type(uint160).max) {
            return address(uint160(uint256(code)));
        }
        return address(0);
    }

    /// @dev Resolve code owner and kickback with a single storage read: custom code lookup
    ///      first, then address-derived default code (0% kickback). Owner is address(0) only
    ///      if the code is unregistered AND not a valid default code.
    function _resolveCodeInfo(bytes32 code) private view returns (address owner, uint8 kickback) {
        AffiliateCodeInfo storage ci = _affiliateCode[code];
        owner = ci.owner;
        kickback = ci.kickback;
        if (owner == address(0) && uint256(code) <= type(uint160).max) {
            // Default code: low 20 bytes encode the owner address directly.
            owner = address(uint160(uint256(code)));
            kickback = 0;
        }
    }

    /**
     * @notice Get the referrer's address for a player.
     * @dev Returns VAULT if player has no referrer or is locked to VAULT.
     * @param player The player to look up.
     * @return The referrer's address (VAULT as fallback).
     */
    function _referrerAddress(address player) private view returns (address) {
        bytes32 code = playerReferralCode[player];
        if (code == bytes32(0) || code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) return ContractAddresses.VAULT;
        address owner = _resolveCodeOwner(code);
        if (owner == address(0)) return ContractAddresses.VAULT;
        return owner;
    }

    /// @dev Shared code registration logic for user-created and constructor-bootstrapped codes.
    function _createAffiliateCode(
        address owner,
        bytes32 code_,
        uint8 kickbackPct
    ) private {
        if (owner == address(0)) revert Zero();
        // SECURITY: Prevent reserved values from being claimed.
        if (code_ == bytes32(0) || code_ == REF_CODE_LOCKED) revert Zero();
        // SECURITY: Reject codes in the address-derived default code range (low 160 bits only).
        if (uint256(code_) <= type(uint160).max) revert Zero();
        // SECURITY: Cap kickback to prevent affiliate from giving away all rewards.
        if (kickbackPct > MAX_KICKBACK_PCT) revert InvalidKickback();
        AffiliateCodeInfo storage info = _affiliateCode[code_];
        // SECURITY: First-come-first-served; codes cannot be overwritten.
        if (info.owner != address(0)) revert Insufficient();
        // Runtime custom-code creation establishes the shared identity immediately.
        // Constructor bootstrap precedes Game deployment and defers registration to use.
        uint8 flags;
        uint256 cache;
        if (address(this).code.length != 0) {
            _requireIdentity(code_, owner);
            (, cache) = _payoutUpline(owner, true, 0);
            flags = 1 | uint8(cache >> 64) << 1;
        }
        _affiliateCode[code_] = AffiliateCodeInfo({
            owner: owner,
            kickback: kickbackPct,
            upline1: uint32(cache),
            upline2: uint32(cache >> 32),
            flags: flags
        });
        emit Affiliate(1, code_, owner); // 1 = code created

    }

    /// @dev Referral assignment logic for constructor bootstrapping.
    function _bootstrapReferral(address player, bytes32 code_) private {
        if (player == address(0)) revert Zero();
        AffiliateCodeInfo storage info = _affiliateCode[code_];
        address referrer = info.owner;
        if (referrer == address(0) || referrer == player) revert Insufficient();
        if (playerReferralCode[player] != bytes32(0)) revert Insufficient();
        _setReferralCode(player, code_);
        emit Affiliate(0, code_, player); // 0 = player referred
    }

    /**
     * @notice Convert a raw amount to a uint96 score in base units.
     * @dev Caps at uint96 max to prevent overflow/truncation errors.
     *      uint96 max ≈ 7.9e28 whole FLIP.
     * @param s Raw amount (0 decimals).
     * @return Raw token amount (0 decimals) as uint96.
     */
    function _score96(uint256 s) private pure returns (uint96) {
        // SECURITY: Cap at max to prevent truncation errors.
        if (s > type(uint96).max) {
            return type(uint96).max;
        }
        return uint96(s);
    }

    /**
     * @notice Add an earning to the level total and take the lead if it beats the leader.
     * @dev One read-modify-write of the packed `_totalAffiliateScore` word; the leader
     *      address slot is written only when the lead changes. Ties keep the earlier leader.
     *      The total saturates at uint160 max (unreachable) so it never spills into the
     *      leader bits.
     * @param player The affiliate whose score is being checked.
     * @param total The affiliate's new total earnings (raw, 0 decimals).
     * @param added The amount added to the level total by this earning.
     * @param lvl The game level.
     */
    function _recordScore(address player, uint256 total, uint256 added, uint24 lvl) private {
        uint256 packed = _totalAffiliateScore[lvl];
        uint256 sum = (packed & TOTAL_SCORE_MASK) + added;
        if (sum > TOTAL_SCORE_MASK) sum = TOTAL_SCORE_MASK;
        uint256 leader = packed >> TOP_SCORE_SHIFT;
        uint96 score = _score96(total);
        if (score > leader) {
            leader = score;
            // A continuing leader raises its score on every referred purchase. Keep the
            // score/event update, but do not rewrite the unchanged address each time.
            if (affiliateTopByLevel[lvl] != player) affiliateTopByLevel[lvl] = player;
            emit AffiliateTopUpdated(lvl, player, score);
        }
        _totalAffiliateScore[lvl] = sum | (leader << TOP_SCORE_SHIFT);
    }

    /// @dev Reduce affiliate payout for high-activity lootbox buyers.
    ///      Linear taper on the whole-point activity score: 100% at score 100 → 25% at 255+.
    function _applyLootboxTaper(uint256 amt, uint16 score) private pure returns (uint256) {
        if (score >= LOOTBOX_TAPER_END_SCORE) {
            return (amt * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;
        }
        uint256 reductionBps;
        unchecked {
            // score is in [LOOTBOX_TAPER_START_SCORE, LOOTBOX_TAPER_END_SCORE) here — the call-site
            // gate and the early return above bound it — so the subtractions cannot underflow and
            // the bps product fits comfortably in uint256.
            uint256 excess = uint256(score) - LOOTBOX_TAPER_START_SCORE;
            uint256 range = uint256(LOOTBOX_TAPER_END_SCORE) - LOOTBOX_TAPER_START_SCORE;
            reductionBps = (BPS_DENOMINATOR - LOOTBOX_TAPER_MIN_BPS) * excess / range;
        }
        return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;
    }

}
