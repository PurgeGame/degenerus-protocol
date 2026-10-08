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
import {WalletTableLib} from "./libraries/WalletTableLib.sol";

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
 *        with 0% kickback, no tx required. Custom codes start at 2^192, so the two namespaces
 *        cannot collide.
 *      - Kickback: 0-25% of reward returned to referred player (custom codes only)
 *      - Affiliate payouts + quest bonuses via coinflip.creditFlip; kickback returned to caller
 *      - Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+)
 *      - Recycled ETH rewards: 5% (all levels)
 *      - Leaderboard: tracks top affiliate per level for a DGNRS pool reward at level transition
 *      - Identity: code owners, uplines, earnings, scores and the per-level leader are keyed by
 *        the uint32 Game wallet ID. Referral words are keyed by the player ID. VAULT and SDGNRS are the constant IDs 1 and 2.
 *
 * @dev SECURITY:
 *      - Access control: payAffiliate / payAffiliateCombined / referSmurf (game only); claim (permissionless settlement)
 *      - Referral locking: invalid codes lock slot (REF_CODE_LOCKED sentinel)
 *      - Fixed contract addresses at deploy (no re-pointing)
 */

/// @notice Interface for quest handler calls from the affiliate contract.
interface IDegenerusQuestsAffiliate {
    /// @notice Record affiliate quest progress and return reward.
    /// @dev Declares only the leading `reward` word of the callee's return data;
    ///      surplus returndata is ignored per ABI decoding rules. Affiliate passes the nonzero
    ///      stored ID of the winning owner or upline.
    /// @return reward Quest reward amount earned (0 if quest not completed).
    function handleAffiliate(uint32 id, uint256 amount)
        external returns (uint256 reward);
}

/// @notice Interface for crediting FLIP stakes directly via the coinflip contract.
interface ICoinflipAffiliate {
    /// @notice Credit FLIP to a single wallet.
    function creditFlip(uint32 id, uint256 amount) external;
}

/// @notice Game-side accessor for the afking affiliate-base PULL.
/// @dev The atomic read-and-zero of a sub's accrued `affiliateBase` (the running unclaimed flat-7%
///      affiliate balance, WHOLE FLIP) happens AT THE STORAGE OWNER (the Game / GameAfkingModule via
///      delegatecall) — guardrail 1: the affiliate `claim` consumer can NEVER pre-load the
///      bases into a memory array, so a duplicate sub in `subs[]` drains 0 the second time. The accessor
///      is AFFILIATE-gated on the Game side (only `ContractAddresses.AFFILIATE` may drain).
interface IGameAfkingDrain {
    /// @notice Atomic read-and-zero of a sub's accrued affiliate base (whole FLIP).
    /// @return base The drained whole-FLIP affiliate base (0 if already drained / never accrued).
    function drainAffiliateBase(uint32 id) external returns (uint256 base);

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
    event Affiliate(uint256 amount, bytes32 indexed code, uint32 senderId);
    /// @notice Emitted when a player's permanent referral code is set.
    event ReferralUpdated(
        uint32 indexed player,
        bytes32 indexed code,
        uint32 indexed referrerId,
        bool locked
    );
    /// @notice Emitted when affiliate earnings are recorded for a level.
    /// @dev The protocol's highest-volume event, so it carries only what nothing else does.
    ///      Dropped as sibling-derivable within the receipt: `amount` (the delta of this
    ///      affiliate's `newTotal` at this level), `sender` (the buyer on purchase paths, the
    ///      affiliate itself on the claim path), `code` (the ReferralUpdated projection —
    ///      `_setReferral` is the sole writer of playerReferralCode and always emits;
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
    event AffiliateEarningsRecorded(uint32 indexed affiliateId, uint256 packed);

    /// @dev `AffiliateEarningsRecorded.packed` field offset.
    uint256 private constant AFF_EARN_TOTAL_SHIFT = 24;
    /// @notice Emitted when the top affiliate for a level changes.
    event AffiliateTopUpdated(
        uint24 indexed level,
        uint32 indexed affiliateId,
        uint96 score
    );

    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not the game contract.
    error OnlyAuthorized();


    /// @notice Thrown when code creation is given a zero owner or a reserved-range code, or referral bootstrapping a zero player.
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
     * @notice Custom affiliate code ownership and kickback configuration.
     * @dev One storage slot, 112 of 256 bits used.
     *
     * STORAGE LAYOUT (LSB -> MSB):
     * +-----------------------------------------------------------+
     * | [0:32]    ownerId   uint32  owner's wallet ID (0 = none)   |
     * | [32:40]   kickback  uint8   kickback % (0-25)              |
     * | [40:72]   upline1   uint32  immutable first hop ID         |
     * | [72:104]  upline2   uint32  immutable second hop ID        |
     * | [104:112] flags     uint8   upline cache validity |
     * +-----------------------------------------------------------+
     */
    struct AffiliateCodeInfo {
        uint32 ownerId; // receives affiliate rewards; 0 for an unused code
        uint8 kickback; // code-specific percentage (0-25)
        uint32 upline1; // permanent wallet ID, only when its flag is valid
        uint32 upline2; // permanent wallet ID, only when its flag is valid
        uint8 flags; // bits 1/2: upline cache validity
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
    /// @dev `_levelScore` word: bits [0:128) level total, [128:224) leader score,
    ///      [224:256) leader wallet ID.
    uint256 private constant TOTAL_SCORE_MASK = type(uint128).max;
    uint256 private constant TOP_SHIFT = 128;
    /// @dev Earnings word: amount [0:128), upline IDs [128:160)/[160:192), valid bits 192/193.
    uint256 private constant EARNINGS_MASK = type(uint128).max;
    uint256 private constant UPLINE1_VALID = uint256(1) << 64;
    uint256 private constant UPLINE2_VALID = uint256(1) << 65;

    /// @dev Protocol wallet IDs (reserved by the Game at construction).
    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;
    /// @dev Code-info flags: both upline caches valid.
    uint8 private constant UPLINES_VALID = 6;
    /// @dev Referral words below this bound (other than 0 and REF_CODE_LOCKED) are default-code
    ///      words `DEFAULT_ID_TAG | ownerId`; custom codes are created only at or above it.
    uint256 private constant DEFAULT_WORD_END = uint256(1) << 192;
    uint256 private constant DEFAULT_ID_TAG = uint256(1) << 32;
    // Input namespace between address codes and custom codes; never stored as an address.
    uint256 private constant ACCOUNT_CODE_TAG = uint256(1) << 160;
    /// @dev Packed referral resolution: owner ID [0:32), kickback [32:40), no-referrer bit 40.
    uint256 private constant NO_REFERRER = uint256(1) << 40;
    uint256 private constant NO_REFERRER_REF = NO_REFERRER | VAULT_ID;

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

    /// @notice Mapping from custom affiliate code (bytes32) to ownership info.
    /// @dev codes are permanent once created; owner cannot be changed.
    mapping(bytes32 => AffiliateCodeInfo) private _affiliateCode;

    /// @notice Per-level earnings and immutable upline cache, keyed by affiliate wallet ID.
    /// @dev Used for leaderboard calculations and activity score bonus points.
    ///      Low 128 bits are whole FLIP; high bits cache two permanent wallet IDs and validity.
    ///      Direct affiliate earnings only; upline rewards are excluded for gas.
    ///      Kickback does not reduce the tracked score.
    mapping(uint24 => mapping(uint32 => uint256)) private affiliateCoinEarned;

    /// @notice Player's referral word: 0 = not yet set, REF_CODE_LOCKED = permanently locked,
    ///         bit32 + low32 owner ID = resolved default referral, otherwise a custom code.
    /// @dev Private to prevent external manipulation; no public getter.
    mapping(uint32 => bytes32) private playerReferralCode;

    /// @notice Per-level affiliate total packed with the leader.
    /// @dev Bits [0:128): running sum, the exact denominator for score-proportional DGNRS
    ///      claim distribution (saturating; unreachable). Bits [128:224): the leader's
    ///      uint96-capped score. Bits [224:256): the leader's wallet ID. Every earning already
    ///      rewrites this word, so tracking the lead reads and writes no other slot.
    mapping(uint24 => uint256) private _levelScore;

    /// @notice A code's owner address, wallet ID (0 for an unknown code) and kickback.
    /// @dev Default codes resolve to their own address with 0% kickback.
    function affiliateCode(bytes32 code) external view returns (address owner, uint32 ownerId, uint8 kickback) {
        if (uint256(code) <= type(uint160).max) {
            owner = address(uint160(uint256(code)));
            ownerId = game.walletIdentityOf(owner);
            return (ownerId == 0 ? owner : WalletTableLib.ownerOf(ownerId), ownerId, 0);
        }
        if (uint256(code) >> 32 == ACCOUNT_CODE_TAG >> 32) {
            ownerId = uint32(uint256(code));
            if (ownerId == 0 || uint256(game.extsload(bytes32(WalletTableLib.OWNERS_SLOT))) <= ownerId) return (address(0), 0, 0);
            return (WalletTableLib.ownerOf(ownerId), ownerId, 0);
        }
        AffiliateCodeInfo storage info = _affiliateCode[code];
        ownerId = info.ownerId;
        kickback = info.kickback;
        owner = ownerId == 0 ? address(0) : _ownerKey(code, ownerId);
    }

    // =====================================================================
    //                              CONSTRUCTOR
    // =====================================================================

    /// @notice Wires the VAULT and sDGNRS codes as each other's referrer, then records the
    ///         deploy-time bootstrap affiliate codes and referrals.
    /// @dev Game and Ticket deploy first, so every bootstrap owner and player receives a
    ///      permanent ID immediately. All runtime referral traversal reads ID-keyed records.
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

        // VAULT refers via DGNRS and SDGNRS via VAULT, so each code's uplines are the other
        // protocol wallet and then its own owner.
        _affiliateCode[AFFILIATE_CODE_VAULT] = AffiliateCodeInfo({
            ownerId: VAULT_ID,
            kickback: 0, upline1: SDGNRS_ID, upline2: VAULT_ID, flags: UPLINES_VALID
        });
        _affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({
            ownerId: SDGNRS_ID,
            kickback: 0, upline1: VAULT_ID, upline2: SDGNRS_ID, flags: UPLINES_VALID
        });
        emit Affiliate(1, AFFILIATE_CODE_VAULT, VAULT_ID);
        emit Affiliate(1, AFFILIATE_CODE_DGNRS, SDGNRS_ID);

        _setReferral(VAULT_ID, AFFILIATE_CODE_DGNRS, AFFILIATE_CODE_DGNRS, SDGNRS_ID);
        _setReferral(SDGNRS_ID, AFFILIATE_CODE_VAULT, AFFILIATE_CODE_VAULT, VAULT_ID);
        emit Affiliate(0, AFFILIATE_CODE_DGNRS, VAULT_ID);
        emit Affiliate(0, AFFILIATE_CODE_VAULT, SDGNRS_ID);

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
     *      Creation registers the caller's wallet ID.
     *
     * VALIDATION:
     * - uint256(code_) >= 2^192 (below it lie the sentinels, the address-derived default
     *   codes and the default-code referral words)
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
     *      A default code's owner registers its wallet ID here (affiliate code owners are the
     *      one third-party registration).
     *
     * VALIDATION:
     * - caller must not already have a referral code set
     * - code_ must resolve to a valid owner (custom or default)
     * - code_ owner must not be the caller (no self-referral)
     *
     * @param code_ The affiliate code to register under.
     */
    function referPlayer(bytes32 code_) external {
        // A referral allocates an ID under the same free-admission threshold as other
        // nonpaying hooks. Above it, the caller must already have a qualifying paid entry.
        uint32 playerId = game.registerWallet(msg.sender, true);
        // SECURITY: Every assigned referral is permanent.
        if (playerReferralCode[playerId] != bytes32(0)) revert Insufficient();
        // SECURITY: Prevent invalid codes and self-referral.
        (uint256 ref, bytes32 word) = _referralTarget(code_, playerId);
        if (ref == 0) revert Insufficient();
        _setReferral(playerId, word, code_, uint32(ref));
        emit Affiliate(0, code_, playerId); // 0 = player referred
    }

    /**
     * @notice Get the referrer address for a player.
     * @dev Never returns address(0): resolves to the VAULT when the player has no valid
     *      referrer (code unset, locked or vault-coded).
     *      Chains are not acyclic (VAULT and SDGNRS refer each other; mutual player referrals
     *      are allowed); payouts walk at most two upline hops from the direct referrer.
     * @param player The player to look up.
     * @return The referrer's address (the VAULT when the player has no real referrer).
     */
    function getReferrer(address player) external view returns (address) {
        (uint32 id, bytes32 code) = _referrerView(game.walletIdOf(player));
        return _ownerKey(code, id);
    }

    /**
     * @notice Get the referrer's wallet ID for a player (ID twin of getReferrer).
     * @dev View; never allocates. VAULT (1) when the player has no valid referrer.
     * @param player The player to look up.
     * @return id The referrer's wallet ID.
     */
    function getReferrerId(address player) external view returns (uint32 id) {
        (id, ) = _referrerView(game.walletIdOf(player));
    }

    /**
     * @notice The three referrer hops of a player as wallet IDs (deity-pass reward chain).
     * @dev View; never allocates. Each hop is the referrer of the previous hop's wallet, so an
     *      unreferred chain reads (1, 2, 1). A zero hop zeroes every later hop.
     * @param player The player to look up.
     * @return affiliate Direct referrer's wallet ID.
     * @return upline1 The direct referrer's referrer.
     * @return upline2 upline1's referrer.
     */
    function referrerIds(address player)
        external
        view
        returns (uint32 affiliate, uint32 upline1, uint32 upline2)
    {
        bytes32 code;
        (affiliate, code) = _referrerView(game.walletIdOf(player));
        if (affiliate == 0) return (0, 0, 0);
        (upline1, code) = _referrerView(affiliate);
        if (upline1 == 0) return (affiliate, 0, 0);
        (upline2, ) = _referrerView(upline1);
    }

    /// @notice External owner of an account's referrer.
    function getReferrerById(uint32 playerId) external view returns (address) {
        (uint32 id, bytes32 code) = _referrerView(playerId);
        return _ownerKey(code, id);
    }

    /// @notice Referrer of an account without a wallet-table lookup.
    function getReferrerIdById(uint32 playerId) external view returns (uint32 id) {
        (id, ) = _referrerView(playerId);
    }

    /// @notice Three referrer hops, directly from account IDs.
    function referrerIdsById(uint32 playerId) external view returns (uint32 affiliate, uint32 upline1, uint32 upline2) {
        (affiliate, ) = _referrerView(playerId);
        (upline1, ) = _referrerView(affiliate);
        (upline2, ) = _referrerView(upline1);
    }

    /// @notice Compute the default affiliate code for any address.
    /// @dev Pure helper for frontend link generation: bytes32(uint256(uint160(addr))).
    function defaultCode(address addr) external pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Zero-kickback referral code for an allocated account, including a subaccount.
    function defaultCodeById(uint32 id) external pure returns (bytes32) {
        return bytes32(ACCOUNT_CODE_TAG | id);
    }

    // =====================================================================
    //                    GAMEPLAY ENTRYPOINTS
    // =====================================================================

    /**
     * @notice Permanently refer a new smurf through its current main account, with zero kickback.
     * @dev GAME only, once at creation, after the main's upstream referral was resolved.
     *      Game validates the ordinary parent and fresh child. Store its current gameplay ID,
     *      not the address's permanent identity (which may belong to a liquidated main).
     *      Registers nobody and moves no value. All nonzero referral words are permanent.
     * @param ownerId The smurf owner's wallet ID.
     * @param smurfId The new smurf's wallet ID.
     */
    function referSmurf(uint32 ownerId, uint32 smurfId) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyAuthorized();
        if (ownerId == 0 || smurfId == 0 || ownerId == smurfId
            || playerReferralCode[ownerId] == bytes32(0) || playerReferralCode[smurfId] != bytes32(0)) {
            revert Insufficient();
        }
        bytes32 word = bytes32(DEFAULT_ID_TAG | ownerId);
        _setReferral(smurfId, word, word, ownerId);
    }

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

     * @param senderId The player's wallet ID (seeds the winner roll; the winner leg equal to it
     *        is skipped). A zero `amount` rolls no winner, so it may be 0 then.
     * @param lvl Current game level (for join tracking and leaderboard).
     * @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
     * @param lootboxActivityScore Buyer's activity score (whole points) for lootbox taper (0 = no taper; 100+ triggers linear taper to 25% floor at 255).
     * @return playerKickback Amount of kickback to credit to the player (caller handles minting and batching).
     */
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        uint32 senderId,
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
        (uint256 ref, bytes32 routeCode) = _resolveReferral(code, senderId);

        // -----------------------------------------------------------------
        // REWARD CALCULATION
        // -----------------------------------------------------------------
        // Apply reward percentage based on ETH type and level.
        // - Fresh ETH (levels 1-3, paid at level + 1): 25%
        // - Fresh ETH (levels 4+): 20%
        // - Recycled ETH: 5%
        uint256 scaledAmount;
        {
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
            scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR;
        }
        if (scaledAmount != 0) {
            // Taper payout for high-activity lootbox buyers before leaderboard tracking.
            if (lootboxActivityScore >= LOOTBOX_TAPER_START_SCORE) {
                scaledAmount = _applyLootboxTaper(scaledAmount, lootboxActivityScore);
            }

            // Calculate kickback (returned to player) and affiliate share.
            uint256 kickbackPct = uint8(ref >> 32);
            if (kickbackPct != 0) {
                playerKickback = (scaledAmount * kickbackPct) / 100;
            }

            (uint32 winner, uint256 credit) =
                _settleShare(ref, routeCode, senderId, lvl, scaledAmount, scaledAmount - playerKickback);
            if (credit != 0) coinflip.creditFlip(winner, credit);
        }

        emit Affiliate(amount, routeCode, senderId);
    }

    /**
     * @notice Purchase-path affiliate settlement for all of a buy's legs in ONE call.
     * @dev GAME-only. Folds the up-to-four per-leg payAffiliate calls (ticket fresh/recycled +
     *      lootbox fresh/recycled) into a single frame: resolves the referral once, scales each leg
     *      at its own rate (fresh/recycled bps, taper on the lootbox-fresh leg) so per-component
     *      rounding matches the separate calls, pools the scaled total into ONE leaderboard write
     *      (all legs credit the same affiliate at the same level), then rolls ONE winner on the
     *      shared (day, senderId, code) entropy and credits the winner via ONE quest hop. The winner
     *      credit is RETURNED, not paid here, so the caller batches it with the buyer's credit into
     *      one Coinflip write: `creditFlipPair(senderId, playerKickback, winnerId, winnerCredit)`.
     *      The winner is rolled among stored owner and upline IDs, so nothing is decoded.
     *      payAffiliate (foil path) is left unchanged.
     * @param code Referral code supplied with the buy (resolved + locked once).

     * @param senderId The buyer's wallet ID (seeds the winner roll).
     * @param lvl Leaderboard level for all legs (ticket and lootbox both freeze at level + 1).
     * @param tktFreshFlip Ticket-leg fresh spend in FLIP base units (fresh bps).
     * @param tktRecycledFlip Ticket-leg recycled spend in FLIP base units (recycled bps).
     * @param lbFreshFlip Lootbox-leg fresh spend in FLIP base units (fresh bps, tapered).
     * @param lbRecycledFlip Lootbox-leg recycled spend in FLIP base units (recycled bps).
     * @param lbFreshScore Activity score tapering the lootbox-fresh leg (0 = no taper).
     * @return winnerId Wallet ID of the single rolled recipient of the pooled affiliate share
     *         (0 when no share accrued).
     * @return winnerCredit FLIP owed the winner (share + quest reward); 0 if none or
     *         winnerId == senderId.
     * @return playerKickback FLIP kickback owed the buyer (summed across legs).
     * @custom:reverts OnlyAuthorized When caller is not the GAME contract.
     */
    function payAffiliateCombined(
        bytes32 code,
        uint32 senderId,
        uint24 lvl,
        uint256 tktFreshFlip,
        uint256 tktRecycledFlip,
        uint256 lbFreshFlip,
        uint256 lbRecycledFlip,
        uint16 lbFreshScore
    )
        external
        returns (uint32 winnerId, uint256 winnerCredit, uint256 playerKickback)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyAuthorized();
        (uint256 ref, bytes32 routeCode) = _resolveReferral(code, senderId);

        // Scale each leg at its OWN rate (fresh/recycled bps, taper on the lootbox-fresh leg) so
        // per-component rounding matches four separate calls; then pool. All four legs credit the
        // same affiliate at the same level, so the leaderboard takes ONE read-modify-write.
        uint256 sumScaled;
        (sumScaled, playerKickback) = _scaleLegs(
            lvl, lbFreshScore, uint8(ref >> 32), tktFreshFlip, tktRecycledFlip, lbFreshFlip, lbRecycledFlip
        );
        if (sumScaled == 0) return (0, 0, playerKickback);
        (winnerId, winnerCredit) =
            _settleShare(ref, routeCode, senderId, lvl, sumScaled, sumScaled - playerKickback);
    }

    /// @dev Book `scaled` to the owner's level earnings and roll the winner of `shareBase`.
    ///      Returns the winner's credit (share plus its quest reward), or 0 when nothing is owed:
    ///      no share, or the rolled winner is the buyer. A buyer without a referrer pays its share
    ///      to VAULT or SDGNRS with no quest hop.
    function _settleShare(
        uint256 ref,
        bytes32 routeCode,
        uint32 senderId,
        uint24 lvl,
        uint256 scaled,
        uint256 shareBase
    ) private returns (uint32 winnerId, uint256 winnerCredit) {
        uint32 ownerId = uint32(ref);
        bool noReferrer = ref & NO_REFERRER != 0;
        uint256 earningsWord = affiliateCoinEarned[lvl][ownerId];
        if (shareBase != 0) {
            (winnerId, earningsWord) = _purchaseWinner(routeCode, ownerId, senderId, noReferrer, earningsWord);
        }
        // Cache fills share the existing earnings write. Commit before the quest call.
        _recordEarnings(lvl, ownerId, scaled, earningsWord);
        if (shareBase != 0) {
            if (noReferrer) {
                winnerCredit = shareBase;
            } else if (winnerId != senderId) {
                winnerCredit = shareBase + quests.handleAffiliate(winnerId, shareBase);
            }
        }
    }

    /// @dev The four legs of a purchase (ticket fresh, ticket recycled, lootbox fresh, lootbox
    ///      recycled; the lootbox-fresh leg tapered by `lbFreshScore`), each scaled at its own
    ///      rate, pooled.
    function _scaleLegs(
        uint24 lvl,
        uint16 lbFreshScore,
        uint8 kickbackPct,
        uint256 tktFreshFlip,
        uint256 tktRecycledFlip,
        uint256 lbFreshFlip,
        uint256 lbRecycledFlip
    ) private pure returns (uint256 sumScaled, uint256 kickback) {
        (uint256 sc, uint256 kb) = _scaleLeg(tktFreshFlip, true, lvl, 0, kickbackPct);
        sumScaled = sc;
        kickback = kb;
        (sc, kb) = _scaleLeg(tktRecycledFlip, false, lvl, 0, kickbackPct);
        sumScaled += sc;
        kickback += kb;
        (sc, kb) = _scaleLeg(lbFreshFlip, true, lvl, lbFreshScore, kickbackPct);
        sumScaled += sc;
        kickback += kb;
        (sc, kb) = _scaleLeg(lbRecycledFlip, false, lvl, 0, kickbackPct);
        sumScaled += sc;
        kickback += kb;
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

    /// @dev Resolve the buyer's referral, storing the supplied code (or the lock) on first use.
    ///      Returns the packed resolution (owner ID [0:32), kickback [32:40), no-referrer bit 40)
    ///      and the canonical route code: the code as supplied (a default code is the owner's
    ///      address), or AFFILIATE_CODE_VAULT for a buyer without a referrer.
    function _resolveReferral(bytes32 code, uint32 senderId)
        private
        returns (uint256 ref, bytes32 routeCode)
    {
        if (senderId == 0) revert Insufficient();
        uint256 stored = uint256(playerReferralCode[senderId]);
        if (stored == 0) {
            if (code != bytes32(0)) {
                bytes32 word;
                (ref, word) = _referralTarget(code, senderId);
                if (ref != 0) {
                    _setReferral(senderId, word, code, uint32(ref));
                    return (ref, uint256(word) < DEFAULT_WORD_END ? word : code);
                }
            }
            _setReferral(senderId, REF_CODE_LOCKED, REF_CODE_LOCKED, VAULT_ID);
            return (NO_REFERRER_REF, AFFILIATE_CODE_VAULT);
        }
        if (stored == uint256(REF_CODE_LOCKED)) return (NO_REFERRER_REF, AFFILIATE_CODE_VAULT);
        if (stored < DEFAULT_WORD_END) return (uint32(stored), bytes32(stored));
        return (_customRef(bytes32(stored)), bytes32(stored));
    }

    /// @dev Validate a supplied code for `sender` and build its referral word. Returns a zero
    ///      resolution for a sentinel, an unknown code or a self-referral. A default code
    ///      given as an address registers that wallet subject to admission policy. An ID input
    ///      must name an allocated account. Both formats store the same tagged ID word.
    function _referralTarget(bytes32 code, uint32 senderId)
        private
        returns (uint256 ref, bytes32 word)
    {
        uint256 c = uint256(code);
        if (c <= type(uint160).max) {
            if (c <= uint256(REF_CODE_LOCKED)) return (0, 0);
            uint32 id = game.registerWalletIdentity(address(uint160(c)));
            if (id == senderId) return (0, 0);
            return (id, bytes32(DEFAULT_ID_TAG | id));
        }
        if (c >> 32 == ACCOUNT_CODE_TAG >> 32) {
            uint32 id = uint32(c);
            if (id == 0 || id == senderId || uint256(game.extsload(bytes32(WalletTableLib.OWNERS_SLOT))) <= id) return (0, 0);
            return (id, bytes32(DEFAULT_ID_TAG | id));
        }
        AffiliateCodeInfo storage info = _affiliateCode[code];
        uint32 ownerId = info.ownerId;
        if (ownerId == 0 || ownerId == senderId) {
            return (0, 0);
        }
        return (uint256(ownerId) | (uint256(info.kickback) << 32), code);
    }

    /// @dev Owner ID and kickback of an existing custom code.
    function _customRef(bytes32 code) private view returns (uint256) {
        AffiliateCodeInfo storage info = _affiliateCode[code];
        return uint256(info.ownerId) | (uint256(info.kickback) << 32);
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
     *      Recipients are paid directly via `creditFlip` by wallet ID (FLIP; no ETH/`claimablePool` touch).
     * @param subs Afking subscribers to settle; all must share the same direct affiliate `A` (from subs[0]).
     */
    function claim(uint32[] calldata subs) external {
        if (subs.length == 0) return;

        // Resolve the upline chain ONCE from subs[0]. `A != sub` is guaranteed by the referral layer
        // (self-referral resolves to VAULT), so the 75% leg never skips to a buyer.
        (uint32 a, bytes32 routeCode, ) = _referrerOf(subs[0]);
        bool noReferrer = a == VAULT_ID;
        uint24 lvl = afkingDrain.level() + 1;
        uint256 earningsWord = affiliateCoinEarned[lvl][a];
        uint256 uplines;
        if (!noReferrer) {
            uint256 cache = _routeCache(routeCode, earningsWord);
            uint32 u;
            (u, cache) = _payoutUpline(routeCode, a, false, cache);
            uplines = u;
            (u, cache) = _payoutUpline(routeCode, a, true, cache);
            uplines |= uint256(u) << 32;
            earningsWord = (earningsWord & EARNINGS_MASK) | (cache << 128);
        }

        (uint256 sumB, uint256 skipU1, uint256 skipU2) = _drainSubs(subs, a, uplines);
        if (sumB == 0) return; // nothing accrued / already drained — no-op (idempotent re-claim)

        if (noReferrer) {
            // No referrer: 50/50 VAULT/sDGNRS, remainder to VAULT (whole FLIP).
            uint256 sdgnrsShare = sumB / 2;
            coinflip.creditFlip(VAULT_ID, sumB - sdgnrsShare);
            coinflip.creditFlip(SDGNRS_ID, sdgnrsShare);
            return;
        }

        // 75/20/5 split, floored with the remainder to A so the parts never exceed sumB.
        uint256 u1Share = ((sumB - skipU1) * 20) / 100;
        uint256 u2Share = ((sumB - skipU2) * 5) / 100;

        // Leaderboard credit to A at the next level (level() + 1, the level the subs' tickets buy
        // into; sumB already uses whole-token units).
        _recordEarnings(lvl, a, sumB, earningsWord);

        // Pay the (at most 3) recipients directly. creditFlip is a pure ledger add (recordAmount=0).
        coinflip.creditFlip(a, sumB - u1Share - u2Share);
        if (u1Share != 0) coinflip.creditFlip(uint32(uplines), u1Share);
        if (u2Share != 0) coinflip.creditFlip(uint32(uplines >> 32), u2Share);
    }

    /// @dev Drain every sub's accrued base, checking each resolves to the direct affiliate `a`.
    ///      An upline that IS the sub (the rare mutual-referral cycle) forfeits its cut of that
    ///      sub's base into A's remainder; it is never paid back to the sub. `uplines` packs the
    ///      two upline IDs (zero for a no-referrer batch); only a sub with a nonzero base, and so a
    ///      nonzero ID, is compared.
    function _drainSubs(uint32[] calldata subs, uint32 a, uint256 uplines)
        private
        returns (uint256 sumB, uint256 skipU1, uint256 skipU2)
    {
        uint256 n = subs.length;
        for (uint256 i; i < n; ) {
            uint32 subId = subs[i];
            // SAME-AFFILIATE batch: every sub MUST resolve to the same direct affiliate (mixed reverts).
            // subs[0] defines `a`, so only later entries need the check.
            if (i != 0) {
                (uint32 r, , ) = _referrerOf(subId);
                if (r != a) revert Insufficient();
            }

            // Atomic read-and-zero at the storage owner: a duplicate sub drains 0 the second time.
            uint256 b = afkingDrain.drainAffiliateBase(subId);
            if (b != 0) {
                sumB += b;
                if (subId == uint32(uplines)) skipU1 += b;
                if (subId == uint32(uplines >> 32)) skipU2 += b;
            }

            unchecked { ++i; }
        }
    }

    // =====================================================================
    //                              VIEWS
    // =====================================================================

    /**
     * @notice Get the top affiliate for a given game level.
     * @dev Returns the affiliate with the highest earnings for that level.
     *      Used to pay the top affiliate a DGNRS pool reward at level transition; the Game
     *      decodes the ID once per level for that transfer.
     * @param lvl The game level to query.
     * @return id Wallet ID of the top affiliate (0 when the level has no leader).
     * @return score Their score in FLIP base units (0 decimals).
     */
    function affiliateTop(uint24 lvl) external view returns (uint32 id, uint96 score) {
        uint256 lead = _levelScore[lvl] >> TOP_SHIFT;
        return (uint32(lead >> 96), uint96(lead));
    }

    /**
     * @notice Get an affiliate's base earnings score for a level.
     * @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
     * @param lvl The game level to query.
     * @param id Wallet ID of the affiliate to query (0 returns 0).
     * @return score The base affiliate score (0 decimals).
     */
    function affiliateScore(uint24 lvl, uint32 id) external view returns (uint256 score) {
        return affiliateCoinEarned[lvl][id] & EARNINGS_MASK;
    }

    /**
     * @notice Get the total affiliate score across all affiliates for a level.
     * @dev Sum of all affiliateCoinEarned for this level. Used as the exact
     *      denominator for score-proportional DGNRS claim distribution.
     * @param lvl The game level to query.
     * @return total The total affiliate score (0 decimals).
     */
    function totalAffiliateScore(uint24 lvl) external view returns (uint256 total) {
        return _levelScore[lvl] & TOTAL_SCORE_MASK;
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
     * @param id Wallet ID of the player to calculate bonus for (0 returns 0).
     * @return points Bonus points (0 to AFFILIATE_BONUS_MAX).
     */
    function affiliateBonusPointsBest(uint24 currLevel, uint32 id) external view returns (uint256 points) {
        if (currLevel == 0) return 0;
        // Σ score[lvl] × priceForLevel(lvl): ETH-volume product still carrying the
        // PRICE_COIN_UNIT and fresh-rate scale factors (normalized out below). Bounded
        // far below overflow: score is capped by real FLIP accrual, price ≤ 0.24 ether.
        uint256 sumProduct;
        unchecked {
            for (uint8 offset = 1; offset <= 5; ) {
                if (currLevel <= offset) break;
                uint24 lvl = currLevel - offset;
                sumProduct +=
                    (affiliateCoinEarned[lvl][id] & EARNINGS_MASK) *
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

    /// @dev Store a player's referral word and emit the normalized event for indexers.
    ///      `code` is the code as supplied; `word` adds the owner ID for a default code.
    function _setReferral(uint32 player, bytes32 word, bytes32 code, uint32 referrerId) private {
        playerReferralCode[player] = word;
        emit ReferralUpdated(player, code, referrerId, word == REF_CODE_LOCKED);
    }

    /// @dev Only this helper writes earnings. Metadata never enters score math or events.
    function _recordEarnings(uint24 lvl, uint32 ownerId, uint256 amount, uint256 word) private {
        uint256 total = (word & EARNINGS_MASK) + amount;
        if (total > EARNINGS_MASK) revert EarningsOverflow();
        affiliateCoinEarned[lvl][ownerId] = (word & ~EARNINGS_MASK) | total;
        emit AffiliateEarningsRecorded(ownerId, uint256(lvl) | (total << AFF_EARN_TOTAL_SHIFT));
        _recordScore(ownerId, total, amount, lvl);
    }

    /// @dev Roll the purchase winner on the (day, buyer ID, route code) entropy: VAULT/SDGNRS
    ///      evenly for a buyer without a referrer, else 75% owner, 20% upline1, 5% upline2.
    function _purchaseWinner(bytes32 code, uint32 ownerId, uint32 buyerId, bool noReferrer, uint256 word)
        private returns (uint32 winner, uint256 updatedWord)
    {
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            AFFILIATE_ROLL_TAG, GameTimeLib.currentDayIndex(), buyerId, code
        )));
        if (noReferrer) {
            return (entropy % 2 == 0 ? VAULT_ID : SDGNRS_ID, word);
        }
        uint256 roll = entropy % 20;
        if (roll < 15) return (ownerId, word);
        uint256 cache = _routeCache(code, word);
        (winner, cache) = _payoutUpline(code, ownerId, roll == 19, cache);
        updatedWord = (word & EARNINGS_MASK) | (cache << 128);
    }

    /// @dev Both caches belong to the same owner and contain only immutable IDs. A valid
    ///      field is identical in both copies; an invalid field is zero, so OR merges them.
    ///      Default codes have no code info, so they skip its read.
    function _routeCache(bytes32 code, uint256 word) private view returns (uint256 cache) {
        cache = word >> 128;
        if (uint256(code) >= DEFAULT_WORD_END) {
            AffiliateCodeInfo storage info = _affiliateCode[code];
            cache |= uint256(info.upline1) | (uint256(info.upline2) << 32)
                | (uint256(info.flags >> 1) << 64);
        }
    }

    /// @dev Referrer of `player` from its stored ID or custom-code word:
    ///      (wallet ID, canonical route code, stable). An unset word reads as VAULT and is not
    ///      stable (the player may still be referred); every other word is permanent.
    function _referrerOf(uint32 player) private view returns (uint32 id, bytes32 routeCode, bool stable) {
        uint256 w = uint256(playerReferralCode[player]);
        if (w == 0) return (VAULT_ID, AFFILIATE_CODE_VAULT, false);
        if (w == uint256(REF_CODE_LOCKED)) return (VAULT_ID, AFFILIATE_CODE_VAULT, true);
        if (w < DEFAULT_WORD_END) return (uint32(w), bytes32(w), true);
        return (uint32(_customRef(bytes32(w))), bytes32(w), true);
    }

    /// @dev View twin of `_referrerOf`, omitting link stability.
    function _referrerView(uint32 player) private view returns (uint32 id, bytes32 routeCode) {
        uint256 w = uint256(playerReferralCode[player]);
        if (w == 0 || w == uint256(REF_CODE_LOCKED)) return (VAULT_ID, AFFILIATE_CODE_VAULT);
        if (w < DEFAULT_WORD_END) return (uint32(w), bytes32(w));
        return (_affiliateCode[bytes32(w)].ownerId, bytes32(w));
    }

    /// @dev Resolve the external payout address only for an address convenience view.
    function _ownerKey(bytes32, uint32 id) private view returns (address) {
        if (id == VAULT_ID) return ContractAddresses.VAULT;
        return WalletTableLib.ownerOf(id);
    }

    /// @dev Cache immutable links resolved from ID-keyed referral records. The caller folds
    ///      cache fills into its existing earnings write or initial custom-code write.
    /// @param code Canonical stored route: tagged ID or custom code.
    /// @param ownerId The owner's wallet ID.
    function _payoutUpline(bytes32 code, uint32 ownerId, bool second, uint256 cache)
        private returns (uint32 recipient, uint256 updatedCache)
    {
        updatedCache = cache;
        if (second && cache & UPLINE2_VALID != 0) {
            return (uint32(cache >> 32), cache);
        }
        bool firstStable;
        bytes32 hop;
        if (cache & UPLINE1_VALID != 0) {
            recipient = uint32(cache);
            firstStable = true;
        } else {
            (recipient, hop, firstStable) = _referrerOf(ownerId);
            if (firstStable) updatedCache |= uint256(recipient) | UPLINE1_VALID;
        }
        if (second) {
            bool secondStable;
            (recipient, , secondStable) = _referrerOf(recipient);
            if (firstStable && secondStable) {
                updatedCache |= (uint256(recipient) << 32) | UPLINE2_VALID;
            }
        }
    }

    /// @dev Shared code registration logic for user-created and constructor-bootstrapped codes.
    function _createAffiliateCode(
        address owner,
        bytes32 code_,
        uint8 kickbackPct
    ) private {
        if (owner == address(0)) revert Zero();
        // SECURITY: Codes below 2^192 are the sentinels, the address-derived default codes and
        // the default-code referral words; none may be claimed.
        if (uint256(code_) < DEFAULT_WORD_END) revert Zero();
        // SECURITY: Cap kickback to prevent affiliate from giving away all rewards.
        if (kickbackPct > MAX_KICKBACK_PCT) revert InvalidKickback();
        AffiliateCodeInfo storage info = _affiliateCode[code_];
        // SECURITY: First-come-first-served; codes cannot be overwritten.
        if (info.ownerId != 0) revert Insufficient();
        uint32 ownerId = game.registerWallet(owner, true);
        (, uint256 cache) = _payoutUpline(code_, ownerId, true, 0);
        uint8 flags = uint8(cache >> 64) << 1;
        _affiliateCode[code_] = AffiliateCodeInfo({
            ownerId: ownerId,
            kickback: kickbackPct,
            upline1: uint32(cache),
            upline2: uint32(cache >> 32),
            flags: flags
        });
        emit Affiliate(1, code_, ownerId); // 1 = code created

    }

    /// @dev Assign a bootstrap referral after every bootstrap code owner has an ID.
    function _bootstrapReferral(address player, bytes32 code_) private {
        if (player == address(0)) revert Zero();
        uint32 referrerId = _affiliateCode[code_].ownerId;
        if (referrerId == 0) revert Insufficient();
        uint32 playerId = game.registerWallet(player, true);
        if (referrerId == playerId || playerReferralCode[playerId] != bytes32(0)) revert Insufficient();
        _setReferral(playerId, code_, code_, referrerId);
        emit Affiliate(0, code_, playerId);
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
     * @dev One read-modify-write of the packed `_levelScore` word, which also holds the
     *      leader's score and ID. Ties keep the earlier leader. The total saturates at
     *      uint128 max (unreachable) so it never spills into the leader bits.
     * @param id The affiliate whose score is being checked.
     * @param total The affiliate's new total earnings (raw, 0 decimals).
     * @param added The amount added to the level total by this earning.
     * @param lvl The game level.
     */
    function _recordScore(uint32 id, uint256 total, uint256 added, uint24 lvl) private {
        uint256 packed = _levelScore[lvl];
        uint256 sum = (packed & TOTAL_SCORE_MASK) + added;
        if (sum > TOTAL_SCORE_MASK) sum = TOTAL_SCORE_MASK;
        uint256 lead = packed >> TOP_SHIFT;
        uint96 score = _score96(total);
        if (score > uint96(lead)) {
            lead = uint256(score) | (uint256(id) << 96);
            emit AffiliateTopUpdated(lvl, id, score);
        }
        _levelScore[lvl] = sum | (lead << TOP_SHIFT);
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
