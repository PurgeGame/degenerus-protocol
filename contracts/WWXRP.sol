// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "./libraries/EntropyLib.sol";
import {RngTags} from "./libraries/RngTags.sol";

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

/**
 * @title WWXRP (Worthless Wrapped XRP)
 * @author Burnie Degenerus
 * @notice An ERC20 joke prize token with a daily burn draw.
 *
 * @dev WARNING: THIS IS A JOKE TOKEN!
 *      - There is NO backing asset behind WWXRP
 *      - It is a pure mint/burn game reward with no redemption path
 *
 * @dev FEATURES:
 *      - Standard ERC20 functionality (transfer, approve, etc.)
 *      - mintPrize(): Authorized minters can award WWXRP prizes
 *      - creditPrize()/withdraw(): unminted per-account prizes, minted on withdrawal
 *      - vaultMintTo(): Vault or its current owner can mint any amount for free
 *      - Trusted minters: the DGVE governance executor may register or
 *        revoke any address as a minter/burner alongside the pinned game
 *        contracts, so future games can pay and take WWXRP. This is
 *        deliberate and total: WWXRP is the protocol's inflationary side coin
 *        and the vault is its sovereign; nothing here bounds what a trusted
 *        address may mint or burn.
 *      - enterDraw()/claim(): daily burn draw for a fixed FLIP prize
 *      - Century BAF incinerator: a level-x99 enterDraw() burn also bets on the
 *        upcoming x00 BAF skipping — when the BAF gate skips, one
 *        burn-weighted winner is credited a share of the FLIP the armed BAF
 *        day's direct depositors staked and lost (flip credit, not ETH)
 *
 * @dev DAILY DRAW (per participation day d):
 *      - A player burns at least 25 WWXRP via enterDraw() for an account it may
 *        act for; the entry belongs to that account and the burn comes from
 *        the account's payee.
 *      - Every entrant maps to exactly one of 10 buckets for day d:
 *        bucket = keccak(domain, chainid, this, d, walletId) % 10, keyed by the
 *        entrant's permanent Game wallet ID (an entrant without one registers on
 *        entry). All of a wallet's burns on a day share that bucket; the player
 *        cannot pick it.
 *      - Each burn snapshots the player's activity score, consumes any live
 *        WWXRP boon (+4/8/12%), and records
 *        effectiveScore = amount * multBps * (10_000 + boonBps) / 1e8 — whole-WWXRP
 *        units, where multBps rescales the shared Decimator curve
 *        (1.0x-1.7833x) to 1.0x-3.0x. Activity affects only winner weight
 *        within a bucket — never prize odds or size.
 *      - Settlement entropy is rngWordForDay(d + 1), the word recorded for
 *        the FOLLOWING day. Four domain-separated hashes of it decide, in
 *        order: BIG gate (1/365), else SMALL gate (1/30), winning bucket
 *        (%10), and a weighted winner roll in [0, bucket total score).
 *      - BIG pays 100,000 FLIP; SMALL pays 10,000 FLIP; BIG suppresses SMALL.
 *        Prizes are paid as coinflip stake credit (Coinflip.creditFlip, the
 *        game's standard reward channel), never as a direct wallet mint.
 *        If the selected bucket has no entries the day is a dud: no reroll,
 *        no prize, no state write.
 *      - Resolution is fully lazy: losing days and empty-bucket days need no
 *        transaction. claim(day, entryIndex) recomputes the outcome from the
 *        immutable word and verifies the supplied entry's cumulative interval
 *        in O(1) storage reads. Claiming is permissionless but always credits
 *        the prize to the player recorded in the winning entry. A claim for day d
 *        opens when word d+1 is recorded and closes when the day-(d+3) request
 *        goes out (logical days d+1 and d+2). Three tagged storage banks recycle
 *        expired daily headers and entries: day d+3's entries open at that same
 *        request, so a bank is reused only after its day's claims close; historical
 *        getters return zero after overwrite.
 *
 * @dev DRAW SECURITY — WHY day d SETTLES ON WORD d+1:
 *      A normal daily request advances the logical index before its word can
 *      arrive. enterDraw() reads that index from Game slot 0, so normal word
 *      d+1 is unknowable while participation day d remains open. Entries after
 *      game over are unguarded: WWXRP is worthless then.
 *      Thus a recorded word for
 *      day d+1 while entry is open is structurally impossible — the same
 *      settlement-blindness model as coinflip deposits, which also stay open
 *      through the daily lock and settle on the next word. reverseFlip
 *      nudges move only the coinflip; this draw reads the raw recorded
 *      word. No fallback word exists: a game whose VRF dies ends
 *      deterministically without any word, so entry carries no stall
 *      gate; burns into a dead game's days simply never settle. The draw
 *      has no owner, no parameter mutation, and no override of RNG, winner,
 *      probability, prize, or recipient.
 *
 * @dev SECURITY:
 *      - Uses Solidity 0.8+ overflow protection
 *      - Draw claim follows checks-effects-interactions (day marked claimed
 *        before the coinflip credit); no token in the flow has transfer hooks
 */

import {ContractAddresses} from "./ContractAddresses.sol";
import {ActivityCurveLib} from "./libraries/ActivityCurveLib.sol";

/// @dev Minimal Game surface consumed by the daily draw and generic WWXRP boon hook.
interface IDrawGame {
    function acquiredBuyer(uint32 id) external view returns (uint32 buyerId);
    /// @notice DegenerusGame's recorded VRF word for `day` (0 if none recorded yet).
    function rngWordForDay(uint24 day) external view returns (uint256);

    /// @notice Activity score for an existing account; may refresh its affiliate-score cache.
    function playerActivityScoreCachedById_g975(uint32 id) external returns (uint256 score);

    /// @notice Game's wallet-ID hook: the existing ID, or with `allocate` a new one (paid
    ///         admission applies; a non-ETH token burn cannot bypass the free-ID threshold).
    function registerWallet_g9539(address owner, bool allocate) external returns (uint32 id);

    /// @notice `player`'s permanent Game wallet ID (0 = none; never allocates).
    function walletIdOf_g3120(address player) external view returns (uint32);

    /// @notice Resolve account `id` for `caller`: key, payee and whether `caller` may act for it
    ///         (its key, a smurf's owner, or an approved operator). Reverts for an unallocated
    ///         or zero `id`; never reverts on authorization. `enterDraw` requires `authorized`.
    function resolveAccount_g7029(uint32 id, address caller)
        external view returns (address key, address payee, bool authorized);

    /// @notice DegenerusGame's current level.
    function currentLvl() external view returns (uint24);

    /// @notice Consume wallet `id`'s WWXRP boon through the caller-specific Game dispatch
    ///         (0 returns 0).
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16);

    /// @notice DegenerusGame's raw storage read (read-only).
    function extsload_g2807007(bytes32 slot) external view returns (bytes32);
}

/// @dev DGVE governance executor check for the trusted-minter registry.
interface IDrawVaultOwner {
    /// @notice Checks the pinned DGVE governance executor, as implemented by DegenerusVault.
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev Coinflip stake-credit channel for draw prizes (WWXRP is an authorized flip creditor).
interface IDrawCoinflip {
    /// @notice Coinflip's credit of `amount` FLIP stake to wallet `id` (0 is a no-op).
    function creditFlip_g317(uint32 id, uint256 amount) external;
    /// @notice The armed BAF draw day and its book: the whole-FLIP principal sum of every
    ///         direct deposit that staked the armed day, and the entry count.
    function bafDrawInfo() external view returns (uint24 day, uint96 totalWeight, uint32 entryCount);
    /// @notice A flip day's stored result. An unresolved day reads (0, false).
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win);
}

contract WWXRP {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Standard ERC20 events and draw settlement tracking                  |
      +======================================================================+*/

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from The sender address (address(0) for mints)
    /// @param to The recipient address (address(0) for burns)
    /// @param amount The amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when an allowance is set via approve
    /// @param owner The token owner granting the allowance
    /// @param spender The address authorized to spend
    /// @param amount The approved spending limit
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Unminted WWXRP awarded to a Game account, after the game reward scale.
    event PrizeCredited(uint32 indexed id, uint256 amount, uint256 claimableAfter);
    event PrizeWithdrawn(uint32 indexed id, address indexed payee, uint256 amount);
    event PrizeConsumed(uint32 indexed id, uint256 amount, uint256 claimableAfter);

    /// @notice Emitted for every recorded daily-draw entry
    /// @param day Participation day (settles on rngWordForDay(day + 1))
    /// @param player Wallet ID of the entrant account
    /// @param bucket Deterministic bucket for (day, entrant wallet ID)
    /// @param entryIndex Index of this entry within the bucket
    /// @param burnAmount WWXRP burned (0 decimals)
    /// @param effectiveScore Activity- and boon-weighted score recorded for this burn
    ///        (whole-WWXRP units)
    /// @param cumulativeScore Bucket cumulative score endpoint after this burn
    ///        (whole-WWXRP units)
    event DrawEntered(
        uint24 indexed day,
        uint32 indexed player,
        uint8 bucket,
        uint32 entryIndex,
        uint256 burnAmount,
        uint256 effectiveScore,
        uint256 cumulativeScore
    );

    /// @notice Emitted when a day's draw prize is claimed
    /// @param day Participation day that won
    /// @param winnerId Wallet ID recorded in the winning entry (prize recipient)
    /// @param big True for the BIG prize, false for SMALL
    /// @param prize FLIP amount credited as coinflip stake (0 decimals)
    /// @param bucket Winning bucket
    /// @param entryIndex Winning entry index within the bucket
    event DrawClaimed(
        uint24 indexed day,
        uint32 indexed winnerId,
        bool big,
        uint256 prize,
        uint8 bucket,
        uint32 entryIndex
    );

    /// @notice Emitted for every recorded century BAF-incinerator entry
    /// @param bracket Century bracket the burn bets on (level x00)
    /// @param player Wallet ID of the entrant account
    /// @param entryIndex Index of this entry within the bracket
    /// @param burnAmount WWXRP burned (0 decimals)
    /// @param effectiveScore Activity- and boon-weighted score recorded for this burn
    ///        (whole-WWXRP units, the same weight as the carrying daily entry)
    /// @param cumulativeScore Bracket cumulative score endpoint after this
    ///        burn (whole-WWXRP units)
    event IncineratorEntered(
        uint24 indexed bracket,
        uint32 indexed player,
        uint32 entryIndex,
        uint256 burnAmount,
        uint256 effectiveScore,
        uint256 cumulativeScore
    );

    /// @notice Emitted when the vault owner registers or revokes a trusted minter/burner.
    /// @param account The address whose trust changed.
    /// @param trusted True when the address may now mint and burn; false when revoked.
    event TrustedMinterSet(address indexed account, bool trusted);

    /// @notice Emitted when the vault owner sets the game mint scale.
    /// @param scale New whole-number multiplier on the requested amount (1 = 1x).
    event GameMintScaleSet(uint256 scale);

    /// @notice Emitted when a skipped century BAF resolves its incinerator draw
    /// @param bracket Century bracket whose BAF skipped (level x00)
    /// @param winnerId Wallet ID recorded in the winning entry (paid as flip credit)
    /// @param flipAward FLIP credited to the winner by the game as flip credit
    /// @param roll Winner roll in [0, totalScore)
    /// @param totalScore Bracket total effective score (whole-WWXRP units)
    event IncineratorResolved(
        uint24 indexed bracket,
        uint32 indexed winnerId,
        uint256 flipAward,
        uint256 roll,
        uint256 totalScore
    );

    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts                             |
      +======================================================================+*/

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when sender has insufficient token balance
    error InsufficientBalance();

    /// @notice Thrown when spender has insufficient allowance
    error InsufficientAllowance();

    /// @notice Thrown when caller is not an authorized minter
    error OnlyMinter();

    /// @notice Thrown when the caller is not the pinned DGVE governance executor
    error NotVaultOwner();

    /// @notice Thrown when a draw burn is below the 25 WWXRP minimum
    error BelowMinBurn();

    /// @notice Thrown when a draw bucket's or incinerator bracket's entry
    ///         count would overflow (score accumulators saturate instead)
    error ScoreOverflow();

    /// @notice Thrown when claiming a day whose settlement word is not yet
    ///         recorded
    error WordUnavailable();

    /// @notice Thrown when claiming a day where neither prize gate hit
    error NoPrize();

    /// @notice Thrown when the selected winning bucket has no entries (dud)
    error EmptyWinningBucket();

    /// @notice Thrown when the supplied entry index does not exist
    error EntryMissing();

    /// @notice Thrown when the supplied entry's interval misses the roll
    error NotWinningEntry();

    /// @notice Thrown when the day's draw prize was already claimed
    error AlreadyClaimed();

    /// @notice Thrown when the caller may not act for the account: it is neither the account's
    ///         key, a smurf's owner, nor an approved operator
    error NotApproved();

    /*+======================================================================+
      |                         ERC20 STATE                                  |
      +======================================================================+
      |  Standard ERC20 metadata and balances                                |
      +======================================================================+*/

    /// @notice Token name (a parody; not affiliated with or backed by XRP)
    string public constant name = "Worthless Wrapped XRP";

    /// @notice Token symbol
    string public constant symbol = "WWXRP";

    /// @notice Number of decimals
    uint8 public constant decimals = 0;

    /// @notice Total minted WWXRP less burns, including tokens held by the vault.
    uint256 public totalSupply;

    /// @notice Mapping of address to WWXRP balance
    mapping(address => uint256) public balanceOf;

    /// @notice Mapping of owner to spender to approved amount
    mapping(address => mapping(address => uint256)) public allowance;

    /*+======================================================================+
      |                    WIRED CONTRACTS & CONSTANTS                       |
      +======================================================================+
      |  All external dependencies are compile-time constants sourced from   |
      |  ContractAddresses. No storage slots consumed for wiring.            |
      +======================================================================+*/

    /// @dev Game contract address authorized to mint WWXRP
    address internal constant MINTER_GAME = ContractAddresses.GAME;

    /// @dev Coinflip contract address authorized to mint WWXRP
    address internal constant MINTER_COINFLIP = ContractAddresses.COINFLIP;

    /// @dev Jackpots contract address authorized to mint WWXRP (skipped-BAF consolation)
    address internal constant MINTER_JACKPOTS = ContractAddresses.JACKPOTS;

    /// @dev Vault contract address authorized to mint without a reserve limit
    address internal constant MINTER_VAULT = ContractAddresses.VAULT;

    /// @dev Draw views and WWXRP boon consumption (day indexing is computed locally).
    IDrawGame private constant game = IDrawGame(ContractAddresses.GAME);
    IDrawVaultOwner private constant vaultOwner = IDrawVaultOwner(ContractAddresses.VAULT);

    /// @dev Coinflip contract credited with draw prizes (FLIP-denominated stake)
    IDrawCoinflip private constant coinflip =
        IDrawCoinflip(ContractAddresses.COINFLIP);

    /// @notice Number of equal draw buckets every participation day
    uint256 public constant BUCKET_COUNT = 10;

    /// @notice BIG draw prize (FLIP, 0 decimals), gated at 1/365 per day
    uint256 public constant BIG_PRIZE = 100_000;

    /// @notice SMALL draw prize (FLIP, 0 decimals), gated at 1/30 when BIG misses
    uint256 public constant SMALL_PRIZE = 10_000;

    /// @notice Minimum WWXRP burn per draw entry (0 decimals)
    uint256 public constant MIN_BURN = 25;

    /// @dev Prize gate moduli
    uint256 private constant BIG_GATE = 365;
    uint256 private constant SMALL_GATE = 30;

    /// @dev Rescale span: decMultBps's 1.0x-1.7833x maps onto 1.0x-3.0x.
    ///      multBps = 10_000 + (base - 10_000) * 20_000 / 7_833, exact at
    ///      both endpoints (10_000 -> 10_000, 17_833 -> 30_000).
    uint256 private constant BASE_SPAN_BPS =
        ActivityCurveLib.MULT_MAX_BPS - ActivityCurveLib.MULT_MIN_BPS; // 7_833
    uint256 private constant TARGET_SPAN_BPS = 20_000;
    uint256 private constant BPS = 10_000;

    /// @dev Where DegenerusGame keeps a wallet's WWXRP boon: `boonPacked` is the wallet-ID-keyed
    ///      mapping at the compiler-pinned Game root below. Its lane is 24 bits at bit 232 of the second word;
    ///      its low two bits are the tier (0 = no boon). Read-only, used to skip the consume
    ///      dispatch for a wallet holding no WWXRP boon; pinned against the Game layout.
    uint256 internal constant GAME_BOON_PACKED_SLOT = 36;
    uint256 private constant GAME_WWXRP_LANE_SHIFT = 232;
    uint256 private constant GAME_LANE_TIER_MASK = 0x3;

    /// @dev Domain tag for the draw's bucket hash
    bytes32 private constant DOM_BUCKET = "WWXRP_DRAW_BUCKET";

    /// @dev Incinerator award, in basis points of the FLIP the armed BAF day's direct
    ///      depositors staked and then lost when that day's flip came up tails, as summed
    ///      by the coinflip's BAF draw book (whole FLIP); paid as flip credit, never ETH.
    uint256 private constant INCINERATOR_FLIP_BPS = 1_000;

    /*+======================================================================+
      |                          DAILY DRAW STATE                            |
      +======================================================================+
      |  One packed header word per (day, bucket) and one packed word per    |
      |  entry. Winner verification is O(1): an entry stores its cumulative  |
      |  score endpoint; the previous entry's endpoint is the interval start.|
      +======================================================================+*/

    /// @dev Entry per (day, bucket, index):
    ///      bits [0..95]    cumulative effective score endpoint (exclusive,
    ///                      whole-WWXRP units)
    ///      bits [96..127]  entrant wallet ID
    ///      Key: ((day % 3) << 40) | (bucket << 32) | index. Only entries below
    ///      the exact-day tagged header's count are live. Never zero for a
    ///      recorded entry (endpoint >= 25 units via MIN_BURN at 1.0x).
    mapping(uint256 => uint256) private _drawEntry;

    /// @dev Claimed-day bitmap: bit (day & 255) of word day >> 8.
    mapping(uint24 => uint256) private _dayClaimed;

    /// @notice True once a day's draw prize has been claimed.
    function dayClaimed(uint24 day) public view returns (bool) {
        return (_dayClaimed[day >> 8] & (uint256(1) << (day & 255))) != 0;
    }

    /*+======================================================================+
      |                    CENTURY BAF-INCINERATOR STATE                     |
      +======================================================================+
      |  Burn-weighted entries recorded during a level x99, betting that the |
      |  next century BAF (level x00) skips. Interval accounting mirrors the |
      |  daily draw but is keyed by bracket, with a uint192 accumulator.     |
      +======================================================================+*/

    /// @notice One incinerator interval entry in one slot: the endpoint (the bracket total
    ///         saturates at uint192.max, so every endpoint fits) and the entrant's wallet ID.
    struct IncinEntry {
        /// @notice Cumulative effective score endpoint (exclusive, whole-WWXRP units).
        uint192 cum;
        /// @notice Wallet ID credited if the winner roll lands in this interval.
        uint32 id;
    }

    /// @dev Entry by index, authenticated by the bracket header and count. The
    ///      resolve binary search reads one slot per probe.
    mapping(uint256 => IncinEntry) private _incinEntry;

    /// @notice Addresses the vault owner has registered as minters/burners alongside the
    ///         pinned game contracts (future games).
    mapping(address => bool) public trustedMinter;

    /// @notice Whole-number multiplier on WWXRP mints and prize credits the pinned game contracts request
    ///         (Game and its modules, Coinflip, Jackpots): 1 = 1x, 0 = no game minting, no
    ///         upper bound. Set by the vault owner. Trusted-minter apps, vault mints and this
    ///         contract's own draw payouts are not scaled.
    uint256 public gameMintScale = 1;

    constructor() {
        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "wwxrp.degenerus.eth")
            );
            ok;
        }
    }

    /// @notice Earned WWXRP awaiting withdrawal or gameplay consumption, keyed by account ID.
    /// @dev Unminted rewards are outside ERC20 totalSupply and never shared between subaccounts.
    /// @dev Balance plus one; untouched zero is also empty. Economic cap is uint256.max-1.
    mapping(uint32 => uint256) private _claimable;

    function claimable(uint32 id) public view returns (uint256) {
        uint256 stored = _claimable[id];
        return stored == 0 ? 0 : stored - 1;
    }

    /*+======================================================================+
      |                       ERC20 FUNCTIONS                                |
      +======================================================================+
      |  Standard ERC20 implementation                                       |
      +======================================================================+*/

    /// @notice Approve spender to transfer up to amount on behalf of caller
    /// @param spender The address authorized to spend
    /// @param amount The maximum amount that can be spent
    /// @return True on success
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens from caller to recipient
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return True on success
    /// @custom:reverts ZeroAddress When from or to is address(0)
    /// @custom:reverts InsufficientBalance When caller has insufficient balance
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens from sender to recipient using caller's allowance
    /// @dev If allowance is type(uint256).max, it is treated as unlimited and not decremented
    /// @param from The source address
    /// @param to The destination address
    /// @param amount The amount to transfer
    /// @return True on success
    /// @custom:reverts InsufficientAllowance When caller has insufficient allowance
    /// @custom:reverts ZeroAddress When from or to is address(0)
    /// @custom:reverts InsufficientBalance When from has insufficient balance
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @dev Moves tokens between ordinary ERC20 balances, including the vault's.
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @dev Creates tokens in the recipient's balance, SATURATING at the supply ceiling. The vault
    ///      owner can mint any amount, so a checked add would let it push totalSupply to the top
    ///      and make every later mint (prize withdrawals, pinned-minter mints) panic. Clamped
    ///      instead, a mint past the ceiling mints what fits; a balance never exceeds
    ///      totalSupply, so the balance add cannot overflow either.
    ///      A zero recipient mints nothing rather than reverting.
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) return;
        uint256 room = type(uint256).max - totalSupply;
        if (amount > room) amount = room;
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @dev Destroys tokens from an existing balance.
    function _burn(address from, uint256 amount) internal {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /*+======================================================================+
      |                       PRIVILEGED MINT/BURN FUNCTIONS                 |
      +======================================================================+
      |  Allows authorized minters to create/destroy WWXRP                   |
      +======================================================================+*/

    /// @notice Mint WWXRP to a recipient (for lootbox/game/consolation prizes)
    /// @dev Callable by the pinned minters (game/coinflip/jackpots) or a trusted minter. A zero
    ///      recipient mints nothing. A pinned game mint is multiplied by gameMintScale,
    ///      saturating at 2^256 - 1, so the scaled path cannot revert on the amount; a trusted
    ///      minter's amount is unscaled. Every mint is clamped to the supply room in _mint.
    /// @param to Recipient of the minted WWXRP
    /// @param amount Amount to mint (0 decimals), before the game mint scale
    /// @custom:reverts OnlyMinter When caller is not an authorized minter
    function mintPrize(address to, uint256 amount) external {
        _mint(to, _scaledPrize(amount));
    }

    /// @notice Credit a prize without minting tokens or resolving a wallet address.
    /// @dev Producers supply an allocated ID. Zero is a no-op. Both multiplication and the
    ///      per-account sum saturate, so vault-controlled inflation cannot brick settlement.
    function creditPrize(uint32 id, uint256 amount) external {
        amount = _scaledPrize(amount);
        if (id == 0 || amount == 0) return;
        uint256 prior = claimable(id);
        uint256 room = type(uint256).max - 1 - prior;
        if (amount > room) amount = room;
        if (amount == 0) return;
        _claimable[id] = prior + amount + 1;
        emit PrizeCredited(id, amount, prior + amount);
    }

    /// @dev Scale exactly once, at award time. Trusted apps award exact units.
    function _scaledPrize(uint256 amount) private view returns (uint256) {
        if (msg.sender == MINTER_GAME || msg.sender == MINTER_COINFLIP || msg.sender == MINTER_JACKPOTS) {
            uint256 scale = gameMintScale;
            return scale != 0 && amount > type(uint256).max / scale ? type(uint256).max : amount * scale;
        }
        if (!trustedMinter[msg.sender]) revert OnlyMinter();
        return amount;
    }

    /// @notice Mint earned rewards to the selected account's owner (0 = caller).
    /// @param amount Maximum to withdraw; zero withdraws all available rewards.
    /// @dev Operators may trigger withdrawal but cannot redirect it. Any amount that cannot
    ///      fit below the ERC20 supply ceiling remains claimable instead of being discarded.
    function withdraw(uint32 id, uint256 amount) external returns (uint256 withdrawn) {
        address payee = msg.sender;
        if (id == 0) {
            id = game.walletIdOf_g3120(msg.sender);
            if (id == 0) return 0;
        } else {
            bool authorized;
            (, payee, authorized) = game.resolveAccount_g7029(id, msg.sender);
            if (!authorized) revert NotApproved();
        }
        return _withdrawPrize(id, payee, amount);
    }

    /// @notice Permissionless acquired-account collection; no caller fee or recipient override.
    function withdrawAcquired(uint32 id) external returns (uint256) {
        uint32 buyer = game.acquiredBuyer(id);
        if (buyer == 0) revert NotApproved();
        return _withdrawPrize(id, buyer == 1 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS, 0);
    }

    function _withdrawPrize(uint32 id, address payee, uint256 amount) private returns (uint256 withdrawn) {
        uint256 balance = claimable(id);
        withdrawn = amount == 0 || amount > balance ? balance : amount;
        uint256 room = type(uint256).max - totalSupply;
        if (withdrawn > room) withdrawn = room;
        if (withdrawn == 0) return 0;
        _claimable[id] = balance - withdrawn + 1;
        _mint(payee, withdrawn);
        emit PrizeWithdrawn(id, payee, withdrawn);
    }

    /// @dev Consume this account's rewards first, returning only the held-token shortfall.
    ///      Unminted consumption never touches ERC20 balances or totalSupply.
    function _consumePrize(uint32 id, uint256 amount) private returns (uint256 shortfall) {
        uint256 balance = claimable(id);
        uint256 used = amount < balance ? amount : balance;
        if (used != 0) {
            _claimable[id] = balance - used + 1;
            emit PrizeConsumed(id, used, balance - used);
        }
        return amount - used;
    }

    /// @notice Spend an account's claimable WWXRP, then its owner's held tokens if necessary.
    /// @dev Game or trusted app only; the caller owns the gameplay authorization check.
    function burnForAccount(uint32 id, uint256 amount) external {
        if (msg.sender != MINTER_GAME && !trustedMinter[msg.sender]) revert OnlyMinter();
        if (amount == 0) return;
        if (id == 0) revert InsufficientBalance();
        uint256 shortfall = _consumePrize(id, amount);
        if (shortfall != 0) {
            (, address payee, ) = game.resolveAccount_g7029(id, address(0));
            _burn(payee, shortfall);
        }
    }

    /// @notice Set the scale applied to WWXRP the game prints (vault owner only).
    /// @dev 1 = 1x (the deploy default), 0 stops game awards, no upper bound. Applies to awards
    ///      requested by the Game and its modules, Coinflip and Jackpots; the game's own
    ///      events keep reporting the unscaled amount; Transfer and PrizeCredited report the scaled award. The
    ///      scale applies when a producer awards a mint or claimable credit. Withdrawals do
    ///      not rescale earned credits. A prize awarded while scale is 0 pays nothing; an
    ///      unsettled BAF consolation uses the scale when its claim credits the account.
    /// @param scale New whole-number multiplier on the requested amount.
    /// @custom:reverts NotVaultOwner When the caller is not the vault owner.
    function setGameMintScale(uint256 scale) external {
        if (!vaultOwner.isVaultOwner(msg.sender)) revert NotVaultOwner();
        gameMintScale = scale;
        emit GameMintScaleSet(scale);
    }

    /// @notice Register or revoke a trusted minter/burner (vault owner only).
    /// @dev Total by design: a trusted address may mint any amount to anyone through
    ///      mintPrize, burn any balance through burnForGame or burnForAccount, and consume any
    ///      player's WWXRP boon through consumeBoon, exactly as the pinned game contracts can.
    ///      The vault owner is the pinned DGVE approval executor.
    /// @param account The address to trust or revoke.
    /// @param trusted True to register, false to revoke.
    /// @custom:reverts NotVaultOwner When the caller is not the vault owner.
    /// @custom:reverts ZeroAddress When account is address(0).
    function setTrustedMinter(address account, bool trusted) external {
        if (!vaultOwner.isVaultOwner(msg.sender)) revert NotVaultOwner();
        if (account == address(0)) revert ZeroAddress();
        trustedMinter[account] = trusted;
        emit TrustedMinterSet(account, trusted);
    }

    /// @notice Consume a player's WWXRP boon for a trusted app action and return its bonus BPS.
    /// @dev The app decides how to apply the bonus and must consume it in the same transaction
    ///      as the action. Reverting that action restores the boon. This hook does not burn
    ///      tokens and does not call the app; mintPrize and burnForGame never consume boons.
    ///      Trusted-minter status is the whole permission: no per-player approval, since
    ///      a trusted minter can already burn any balance through burnForGame.
    ///      The boon is keyed by the player's Game wallet ID; a wallet without one has no boon
    ///      (the Game returns 0 for ID 0).
    /// @custom:reverts OnlyMinter When the caller is not currently a trusted minter.
    function consumeBoon(uint32 playerId) external returns (uint16 boonBps) {
        if (!trustedMinter[msg.sender]) revert OnlyMinter();
        return game.consumeCoinflipBoon_g2902(playerId);
    }

    /// @notice Mint any amount of WWXRP for free (a zero recipient mints nothing).
    /// @dev Callable by the Vault or its pinned DGVE governance executor.
    ///      No reserve, allocation, payment or per-call mint limit applies.
    function vaultMintTo(address to, uint256 amount) external {
        if (msg.sender != MINTER_VAULT && !vaultOwner.isVaultOwner(msg.sender)) revert NotVaultOwner();
        _mint(to, amount);
    }

    /// @notice Burn WWXRP for game bets
    /// @dev Callable by the game contract or a trusted minter. Silently returns if amount is zero.
    /// @param from Address to burn from
    /// @param amount Amount to burn (0 decimals)
    /// @custom:reverts OnlyMinter When caller is neither the game contract nor a trusted minter
    /// @custom:reverts InsufficientBalance When from has insufficient balance
    function burnForGame(address from, uint256 amount) external {
        if (msg.sender != MINTER_GAME && !trustedMinter[msg.sender]) revert OnlyMinter();
        if (amount == 0) return;
        _burn(from, amount);
    }

    /*+======================================================================+
      |                        DAILY DRAW: ENTRY                             |
      +======================================================================+*/

    /// @notice Burn WWXRP for a weighted entry of account `id` in today's draw.
    ///         During a level x99 the same burn also enters the century
    ///         BAF-incinerator draw for the upcoming x00 bracket.
    /// @dev Authorized: `id == 0` is the caller (no Game resolution call); any other
    ///      ID needs Game `resolveAccount` to authorize the caller (the account's key,
    ///      a smurf's owner or an approved operator). The WWXRP burns from the
    ///      account's payee; the activity score, the entry, the bucket and the boon
    ///      are the account's, keyed by its wallet ID. The entry pays, so a
    ///      first-time self entrant registers its Game wallet ID. Multiple burns per day
    ///      are allowed; each records its own activity snapshot and interval. One live
    ///      WWXRP boon boosts both draw weights from that burn; the token burn is unchanged.
    ///      Entry stays open during the daily RNG lock (like flip deposits):
    ///      the lock covers TODAY's word while this entry settles on
    ///      TOMORROW's, which cannot exist yet — structurally, since the game
    ///      only ever records words for requested logical days, so no
    ///      in-path check is needed. The
    ///      incinerator piggyback needs no such care: its deciding word's
    ///      request bumps the level off x99 first (see
    ///      _recordIncineratorEntry).
    /// @param id Account the entry belongs to (0 = caller).
    /// @param amount WWXRP to burn (0 decimals, at least MIN_BURN). The full
    ///        amount burns; winner weight counts whole WWXRP only.
    /// @custom:reverts BelowMinBurn When amount is under 25 WWXRP.
    /// @custom:reverts NotApproved When the caller may not act for `id`.
    /// @custom:reverts ScoreOverflow When the bucket entry count would overflow.
    /// @custom:reverts InsufficientBalance When the payee's balance is short.
    /// @custom:reverts E (Game) When `id` is unallocated, or a new self entrant must
    ///                 register past paid admission.
    function enterDraw(uint32 id, uint256 amount) external {
        if (amount < MIN_BURN) revert BelowMinBurn();
        // The requested logical day lives in Game slot 0 bits 24..47.
        uint256 gameHeader = uint256(game.extsload_g2807007(bytes32(0)));
        address payee = msg.sender;
        if (id != 0) {
            bool authorized;
            (, payee, authorized) = game.resolveAccount_g7029(id, msg.sender);
            if (!authorized) revert NotApproved();
        }

        uint24 day = uint24(gameHeader >> 24);
        // Self entrants resolve or register through the canonical Game registry before
        // activity and reward records use the ID. Registration follows the free-ID policy;
        // this token burn does not provide a qualifying ETH quote beyond that limit.
        if (id == 0) id = game.walletIdOf_g3120(msg.sender);
        if (id == 0) id = game.registerWallet_g9539(msg.sender, true);
        uint256 score = game.playerActivityScoreCachedById_g975(id);
        // Consume once for the whole burn. Both draws share the same activity/boon snapshot;
        // both daily and century weights floor to whole WWXRP at the same BPS boundaries.
        // The Game's consume returns 0 with no write and no event when the WWXRP lane's tier is
        // 0, so reading the lane first and skipping the dispatch for an empty lane is exact.
        uint16 boonBps;
        if (_holdsWwxrpBoon(id)) boonBps = game.consumeCoinflipBoon_g2902(id);
        uint8 bucket = _bucketOf(day, id);
        uint256 multBps = drawMultBps(score);
        uint256 effective = _entryWeight(amount, multBps, boonBps);

        uint256 header = _readDrawHeader(day, bucket);
        uint256 raw = header & type(uint96).max;
        uint256 total = (header >> 96) & type(uint96).max;
        uint256 count = uint32(header >> 192);

        uint256 rawHeadroom = type(uint96).max - raw;
        uint256 newRaw = raw + (amount > rawHeadroom ? rawHeadroom : amount);
        uint256 newTotal = total + effective;
        if (count >= type(uint32).max) revert ScoreOverflow();
        // Saturate rather than revert: a capped bucket keeps accepting burns.
        // Post-cap entries record zero-width intervals (cumEnd == cumStart ==
        // cap), so they carry no winner weight and can never falsely verify.
        if (newTotal > type(uint96).max) newTotal = type(uint96).max;

        uint256 headerSlot = _drawHeaderSlot(day, bucket);
        uint256 packedHeader = newRaw | (newTotal << 96) | ((count + 1) << 192) | ((uint256(day) + 1) << 224);
        assembly ("memory-safe") { sstore(headerSlot, packedHeader) }
        _drawEntry[_drawEntryKey(day, bucket, uint32(count))] = newTotal | (uint256(id) << 96);

        // Level-x99 burns double as century BAF-incinerator entries: the same
        // burn and weight also arm the next x00 bracket's skip draw, against its
        // uint192 accumulator.
        uint24 lvl = game.currentLvl();
        if (lvl % 100 == 99) {
            _recordIncineratorEntry(lvl + 1, id, amount, effective);
        }

        uint256 shortfall = _consumePrize(id, amount);
        if (shortfall != 0) _burn(payee, shortfall);

        emit DrawEntered(
            day,
            id,
            bucket,
            uint32(count),
            amount,
            effective,
            newTotal
        );
    }

    /// @dev True when wallet `id`'s WWXRP boon lane in the Game has a nonzero tier (live or
    ///      expired; the consume clears an expired lane and pays 0).
    function _holdsWwxrpBoon(uint32 id) private view returns (bool) {
        bytes32 slot;
        unchecked {
            // Struct member addressing wraps, as Solidity's own does.
            slot = bytes32(uint256(keccak256(abi.encode(id, GAME_BOON_PACKED_SLOT))) + 1);
        }
        return (uint256(game.extsload_g2807007(slot)) >> GAME_WWXRP_LANE_SHIFT) & GAME_LANE_TIER_MASK != 0;
    }

    /// @dev Both multipliers are at least 1x. Amounts above the century's uint192 cap can
    ///      return that cap immediately; all other products fit uint256 (192 amount bits,
    ///      <=15 activity bits and <=17 boon-factor bits). Clamp before adding to either
    ///      accumulator so even an admin-minted uint256.max balance can enter safely.
    function _entryWeight(uint256 amount, uint256 multBps, uint16 boonBps) private pure returns (uint256) {
        uint256 cap = type(uint192).max;
        if (amount > cap) return cap;
        uint256 effective = (amount * multBps * (BPS + boonBps)) / (BPS * BPS);
        return effective > cap ? cap : effective;
    }

    /*+======================================================================+
      |                        DAILY DRAW: CLAIM                             |
      +======================================================================+*/

    /// @notice Claim a winning draw day. Permissionless: anyone may execute,
    ///         but the prize is always credited to the player stored in the
    ///         winning entry, as coinflip stake (never a direct wallet mint).
    /// @dev Recomputes the full outcome from the immutable next-day word and
    ///      verifies the supplied entry's cumulative interval in O(1) reads.
    ///      Losing days and empty-bucket days revert without writing state.
    /// @param day Participation day to claim.
    /// @param entryIndex Winning entry's index within the winning bucket.
    /// @custom:reverts WordUnavailable When rngWordForDay(day + 1) is 0.
    /// @custom:reverts NoPrize When neither gate hit for the day.
    /// @custom:reverts EmptyWinningBucket When the selected bucket has no score.
    /// @custom:reverts EntryMissing When entryIndex has no entry.
    /// @custom:reverts NotWinningEntry When the roll is outside the interval.
    /// @custom:reverts AlreadyClaimed When the day was already paid.
    function claim(uint24 day, uint32 entryIndex) external {
        (bool big, uint8 bucket, uint256 roll, uint256 total, uint32 count) = _outcome(day);
        // _outcome reverts NoPrize/WordUnavailable; empty bucket is a dud.
        if (total == 0) revert EmptyWinningBucket();
        if (dayClaimed(day)) revert AlreadyClaimed();
        // A reused bank may retain a longer previous day's tail. Its entries
        // are not members of this draw, even if their cumulative interval fits.
        if (entryIndex >= count) revert EntryMissing();

        uint256 entry = _drawEntry[_drawEntryKey(day, bucket, entryIndex)];
        if (entry == 0) revert EntryMissing();
        uint256 cumEnd = entry & type(uint96).max;
        uint256 cumStart = entryIndex == 0
            ? 0
            : _drawEntry[_drawEntryKey(day, bucket, entryIndex - 1)] &
                type(uint96).max;
        if (roll < cumStart || roll >= cumEnd) revert NotWinningEntry();

        _dayClaimed[day >> 8] |= uint256(1) << (day & 255);
        uint32 winner = uint32(entry >> 96);
        uint256 prize = big ? BIG_PRIZE : SMALL_PRIZE;
        coinflip.creditFlip_g317(winner, prize);

        emit DrawClaimed(day, winner, big, prize, bucket, entryIndex);
    }

    /*+======================================================================+
      |                        DAILY DRAW: VIEWS                             |
      +======================================================================+*/

    /// @notice Deterministic draw bucket for (day, wallet ID). Domain-separated
    ///         by chain and deployment address; identical for all of a
    ///         wallet's burns on a day. ID 0 never enters and has no bucket:
    ///         it returns BUCKET_COUNT.
    function bucketOf(uint24 day, uint32 id) external view returns (uint8) {
        if (id == 0) return uint8(BUCKET_COUNT);
        return _bucketOf(day, id);
    }

    /// @dev The bucket hash over the entrant's admitted wallet ID.
    function _bucketOf(uint24 day, uint32 id) private view returns (uint8) {
        return
            uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            DOM_BUCKET,
                            block.chainid,
                            address(this),
                            day,
                            id
                        )
                    )
                ) % BUCKET_COUNT
            );
    }

    /// @notice Winner-weight multiplier in bps for an activity score: the
    ///         Decimator curve shape rescaled from 1.0x-1.7833x to 1.0x-3.0x.
    function drawMultBps(uint256 activityScore) public pure returns (uint256) {
        // decMultBps returns a value in [MULT_MIN_BPS, MULT_MAX_BPS], so the rescale
        // lands in [BPS, BPS + TARGET_SPAN_BPS].
        uint256 base = ActivityCurveLib.decMultBps(activityScore);
        return
            BPS +
            ((base - ActivityCurveLib.MULT_MIN_BPS) * TARGET_SPAN_BPS) /
            BASE_SPAN_BPS;
    }

    /// @notice Draw bucket totals for a (day, bucket); zero after that bank is reused.
    /// @return rawBurned WWXRP burned into the bucket (saturating at uint96 max).
    /// @return totalScore Total effective (activity/boon-weighted) score in
    ///         whole-WWXRP units.
    /// @return entryCount Number of entries recorded.
    function bucketInfo(
        uint24 day,
        uint8 bucket
    )
        external
        view
        returns (uint256 rawBurned, uint256 totalScore, uint32 entryCount)
    {
        uint256 header = _readDrawHeader(day, bucket);
        rawBurned = header & type(uint96).max;
        totalScore = (header >> 96) & type(uint96).max;
        entryCount = uint32(header >> 192);
    }

    /// @notice A recorded draw entry's wallet ID and cumulative score endpoint
    ///         (whole-WWXRP units). Returns zero for an overwritten day or an index
    ///         outside that day's live count, including tails from a previous draw.
    function entryAt(
        uint24 day,
        uint8 bucket,
        uint32 index
    ) external view returns (uint32 id, uint256 cumulativeScore) {
        if (index >= uint32(_readDrawHeader(day, bucket) >> 192)) return (0, 0);
        uint256 entry = _drawEntry[_drawEntryKey(day, bucket, index)];
        id = uint32(entry >> 96);
        cumulativeScore = entry & type(uint96).max;
    }

    /// @notice Non-reverting draw outcome preview for indexers/UI.
    /// @return wordAvailable True when the day's claim window is open and rngWordForDay(day + 1) is recorded.
    /// @return prize True when a gate hit AND the winning bucket has entries.
    /// @return big True when the BIG gate hit.
    /// @return winningBucket Selected bucket (only meaningful when a gate hit).
    /// @return roll Winner roll in [0, totalScore) (0 when no prize).
    /// @return totalScore Winning bucket's total effective score.
    /// @return claimed True once the day's prize was credited.
    function previewOutcome(
        uint24 day
    )
        external
        view
        returns (
            bool wordAvailable,
            bool prize,
            bool big,
            uint8 winningBucket,
            uint256 roll,
            uint256 totalScore,
            bool claimed
        )
    {
        if (!_drawClaimOpen(day)) return (false, false, false, 0, 0, 0, dayClaimed(day));
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) return (false, false, false, 0, 0, 0, dayClaimed(day));
        wordAvailable = true;
        claimed = dayClaimed(day);
        big = EntropyLib.hash2(RngTags.WWXRP_BIG, word) % BIG_GATE == 0;
        bool small = !big &&
            EntropyLib.hash2(RngTags.WWXRP_SMALL, word) % SMALL_GATE == 0;
        if (!big && !small) return (true, false, false, 0, 0, 0, claimed);
        winningBucket = uint8(
            EntropyLib.hash2(RngTags.WWXRP_BUCKET, word) % BUCKET_COUNT
        );
        uint256 header = _readDrawHeader(day, winningBucket);
        totalScore = (header >> 96) & type(uint96).max;
        if (totalScore == 0) {
            // Gate hit but the bucket is empty: dud day, no prize, no reroll.
            return (true, false, big, winningBucket, 0, 0, claimed);
        }
        prize = true;
        roll = EntropyLib.hash2(RngTags.WWXRP_WINNER, word) % totalScore;
    }

    /// @notice Locate the winning entry for a prize day by binary search over
    ///         the nondecreasing cumulative endpoints (saturated entries are
    ///         zero-width and can never win). View-only helper
    ///         for claim callers/indexers; never used in state-changing paths.
    /// @return found True when the day has a prize and a winning entry.
    /// @return entryIndex Index to pass to claim().
    /// @return id Recorded winner's wallet ID.
    function findWinningEntry(
        uint24 day
    ) external view returns (bool found, uint32 entryIndex, uint32 id) {
        if (!_drawClaimOpen(day)) return (false, 0, 0);
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) return (false, 0, 0);
        bool big = EntropyLib.hash2(RngTags.WWXRP_BIG, word) % BIG_GATE == 0;
        if (!big && EntropyLib.hash2(RngTags.WWXRP_SMALL, word) % SMALL_GATE != 0) {
            return (false, 0, 0);
        }
        uint8 bucket = uint8(
            EntropyLib.hash2(RngTags.WWXRP_BUCKET, word) % BUCKET_COUNT
        );
        uint256 header = _readDrawHeader(day, bucket);
        uint256 total = (header >> 96) & type(uint96).max;
        if (total == 0) return (false, 0, 0);
        uint256 roll = EntropyLib.hash2(RngTags.WWXRP_WINNER, word) % total;

        // Smallest index whose cumulative endpoint exceeds the roll.
        uint32 lo = 0;
        uint32 hi = uint32(header >> 192) - 1;
        while (lo < hi) {
            uint32 mid = lo + (hi - lo) / 2;
            if (
                (_drawEntry[_drawEntryKey(day, bucket, mid)] &
                    type(uint96).max) > roll
            ) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        uint256 entry = _drawEntry[_drawEntryKey(day, bucket, lo)];
        return (true, lo, uint32(entry >> 96));
    }

    /*+======================================================================+
      |                       CENTURY BAF INCINERATOR                        |
      +======================================================================+
      |  A hedge on the century BAF's 50/50 fire gate: daily-draw burns made |
      |  during a level x99 (via enterDraw()) also arm the x00 bracket and   |
      |  pay one burn-weighted winner iff that level's BAF skips. The        |
      |  award is FLIP, not ETH: INCINERATOR_FLIP_BPS of the armed day's     |
      |  BAF draw book, credited as coinflip stake by this contract. The     |
      |  would-be BAF pool rolls forward whole in futurePool.                |
      +======================================================================+*/

    /// @dev Record an incinerator entry riding a daily-draw burn during a
    ///      level x99. The carrying enterDraw() burns the WWXRP; this only appends
    ///      the bracket-keyed interval entry with the same floored activity/boon
    ///      weight as the daily entry. The level increments to
    ///      x00 in the same transaction that requests the VRF word whose
    ///      tagged hash decides the BAF fire gate, so enterDraw()'s level check alone
    ///      closes entries before the deciding word can exist — no separate
    ///      rng-lock gate is needed. On a fired (won) BAF the bracket's
    ///      entries are simply never resolved: the burn was the losing side
    ///      of the hedge (the daily-draw entry it rode on still settles
    ///      normally).
    /// @param bracket Century bracket being armed (level x00).
    /// @param id The entrant's wallet ID.
    /// @param amount WWXRP burned by the carrying enterDraw() (0 decimals).
    /// @param effective Activity/boon weight computed by the carrying entry (whole WWXRP).
    /// @custom:reverts ScoreOverflow When the bracket entry count would overflow.
    function _recordIncineratorEntry(
        uint24 bracket,
        uint32 id,
        uint256 amount,
        uint256 effective
    ) private {
        uint256 header = _incineratorHeader(bracket);
        uint256 total = header & type(uint192).max;
        uint256 count = uint32(header >> 192);

        uint256 newTotal = total + effective;
        if (count >= type(uint32).max) revert ScoreOverflow();
        // Saturate rather than revert (same policy as the daily draw): a
        // capped bracket keeps accepting burns; post-cap entries record
        // zero-width intervals and carry no winner weight.
        if (newTotal > type(uint192).max) newTotal = type(uint192).max;

        _incinHeader = newTotal | ((count + 1) << 192) | (uint256(bracket) << 224);
        IncinEntry storage entry = _incinEntry[count];
        uint256 packed = newTotal | (uint256(id) << 192);
        assembly ("memory-safe") { sstore(entry.slot, packed) }

        emit IncineratorEntered(
            bracket,
            id,
            uint32(count),
            amount,
            effective,
            newTotal
        );
    }

    /// @notice Resolve a skipped century BAF's incinerator draw to one winner and
    ///         credit the prize: INCINERATOR_FLIP_BPS of the FLIP the armed BAF day's
    ///         direct depositors burned and lost on that tails flip, as flip credit.
    /// @dev Called by the game's advance path exactly once per skipped x00
    ///      bracket, in the same call that processes the skip. The lost total is
    ///      the coinflip's draw book for the armed day (whole FLIP); the book closed
    ///      at the day boundary, before the transition word was requested. Returns
    ///      0 when the bracket has no entries. A winner with an empty book —
    ///      or one whose armed day won, or never resolved — is still drawn and logged,
    ///      with a zero award. Winner selection is a
    ///      domain-separated roll over the burn-weighted cumulative intervals,
    ///      located by binary search.
    /// @param bracket Skipped century bracket (level x00).
    /// @param rngWord VRF word of the transition that skipped the BAF.
    /// @return winnerId Recorded winner's wallet ID, or 0 for an empty bracket.
    /// @custom:reverts OnlyMinter When caller is not the game contract.
    function resolveIncinerator(
        uint24 bracket,
        uint256 rngWord
    ) external returns (uint32 winnerId) {
        if (msg.sender != MINTER_GAME) revert OnlyMinter();

        uint256 header = _incineratorHeader(bracket);
        uint256 total = header & type(uint192).max;
        if (total == 0) return 0;

        uint256 roll = uint256(
            EntropyLib.hash2(RngTags.WWXRP_INCINERATOR, rngWord)
        ) % total;

        // Smallest index whose cumulative endpoint exceeds the roll.
        uint32 lo = 0;
        uint32 hi = uint32(header >> 192) - 1;
        while (lo < hi) {
            uint32 mid = lo + (hi - lo) / 2;
            if (_incinEntry[mid].cum > roll) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        winnerId = _incinEntry[lo].id;

        // Pay only against a book that actually lost. The skip gate is a tagged hash of the
        // transition's word, independent of the armed day's coinflip, so the armed day's stored
        // result decides the award: a day that won, or one that never resolved, funds nothing.
        (uint24 armedDay, uint96 lostFlip, ) = coinflip.bafDrawInfo();
        (uint16 rewardPercent, bool armedWin) = coinflip.getCoinflipDayResult(armedDay);
        uint256 flipAward = (!armedWin && rewardPercent != 0)
            ? (uint256(lostFlip) * INCINERATOR_FLIP_BPS) / 10_000
            : 0;
        if (flipAward != 0) coinflip.creditFlip_g317(winnerId, flipAward);

        emit IncineratorResolved(bracket, winnerId, flipAward, roll, total);
    }

    /// @notice Incinerator bracket totals.
    /// @return totalScore Total effective (activity/boon-weighted) score in whole-WWXRP
    ///         units.
    /// @return entryCount Number of entries recorded.
    function incineratorInfo(
        uint24 bracket
    ) external view returns (uint256 totalScore, uint32 entryCount) {
        uint256 header = _incineratorHeader(bracket);
        totalScore = header & type(uint192).max;
        entryCount = uint32(header >> 192);
    }

    /// @notice A recorded incinerator entry's wallet ID and cumulative score
    ///         endpoint (whole-WWXRP units).
    function incineratorEntryAt(
        uint24 bracket,
        uint32 index
    ) external view returns (uint32 id, uint256 cumulativeScore) {
        if (index >= uint32(_incineratorHeader(bracket) >> 192)) return (0, 0);
        IncinEntry memory e = _incinEntry[index];
        id = e.id;
        cumulativeScore = e.cum;
    }

    function _incineratorHeader(uint24 bracket) private view returns (uint256) {
        uint256 header = _incinHeader;
        return uint24(header >> 224) == bracket ? header : 0;
    }

    /*+======================================================================+
      |                      DAILY DRAW: INTERNAL                            |
      +======================================================================+*/

    /// @dev Reverting outcome resolution for claim().
    function _outcome(
        uint24 day
    )
        private
        view
        returns (bool big, uint8 bucket, uint256 roll, uint256 total, uint32 count)
    {
        if (!_drawClaimOpen(day)) revert WordUnavailable();
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) revert WordUnavailable();
        big = EntropyLib.hash2(RngTags.WWXRP_BIG, word) % BIG_GATE == 0;
        if (!big && EntropyLib.hash2(RngTags.WWXRP_SMALL, word) % SMALL_GATE != 0) {
            revert NoPrize();
        }
        bucket = uint8(EntropyLib.hash2(RngTags.WWXRP_BUCKET, word) % BUCKET_COUNT);
        uint256 header = _readDrawHeader(day, bucket);
        total = (header >> 96) & type(uint96).max;
        count = uint32(header >> 192);
        if (total != 0) {
            roll = EntropyLib.hash2(RngTags.WWXRP_WINNER, word) % total;
        }
    }

    /// @dev Authentication is mandatory before any entry read: reused words have
    ///      no tag of their own, and a shorter replacement leaves old tail slots.
    function _drawHeaderSlot(uint24 day, uint8 bucket) private pure returns (uint256 slot) {
        unchecked {
            uint256 index = uint256(day % 3) * BUCKET_COUNT + bucket;
            assembly ("memory-safe") { slot := add(_drawHeader.slot, index) }
        }
    }

    function _readDrawHeader(uint24 day, uint8 bucket) private view returns (uint256 header) {
        if (bucket >= BUCKET_COUNT) return 0;
        uint256 slot = _drawHeaderSlot(day, bucket);
        assembly ("memory-safe") { header := sload(slot) }
        if (uint32(header >> 224) != uint256(day) + 1) return 0;
    }

    /// @dev Day d's claims close at the day-(d+3) request (Game slot 0 bits 24..47, the same
    ///      requested day `enterDraw` keys on), which opens day d+3's entries in day d's bank.
    ///      The opening half is the caller's `rngWordForDay(d + 1) != 0`: the Game retains a
    ///      word only while it is the latest applied result or the one before it.
    function _drawClaimOpen(uint24 participationDay) private view returns (bool) {
        if (participationDay == type(uint24).max) return false;
        uint256 requested = uint24(uint256(game.extsload_g2807007(bytes32(0))) >> 24);
        return requested <= uint256(participationDay) + 2;
    }

    function _drawEntryKey(
        uint24 day,
        uint8 bucket,
        uint32 index
    ) private pure returns (uint256) {
        return (uint256(day % 3) << 40) | (uint256(bucket) << 32) | index;
    }

    /// @dev Header per (day, bucket):
    ///      bits [0..95]    WWXRP burned (analytics only; saturating)
    ///      bits [96..191]  total effective score (last cumulative endpoint,
    ///                      whole-WWXRP units)
    ///      bits [192..223] entry count
    ///      bits [224..255] participation day + 1 (zero means never initialized)
    ///      Indexed by [day % 3][bucket], with ten buckets. Participation day d + 3 reuses
    ///      day d's bank; its entries open at the day-(d + 3) request, the same request that
    ///      closes day d's claims (`_drawClaimOpen`).
    uint256[10][3] private _drawHeader;

    /// @dev Reused incinerator header, authenticated by its bracket:
    ///      bits [0..191]   total effective score (last cumulative endpoint,
    ///                      whole-WWXRP units)
    ///      bits [192..223] entry count
    ///      bits [224..247] bracket
    uint256 private _incinHeader;
}
