// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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
 * @title WWXRP (Wacky Wrapped XRP)
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
 *      - vaultMintTo(): Vault can mint from its uncirculating reserve
 *      - Vault escrow: the vault holds no circulating WWXRP — transfers and
 *        mints targeting it de-circulate into its mint allowance, and its
 *        burns (WWXRP bets) spend from that allowance (FLIP model)
 *      - enter()/claim(): daily burn draw for a fixed FLIP prize
 *      - Century BAF incinerator: a level-x99 enter() burn also bets on the
 *        upcoming x00 BAF skipping — one burn-weighted winner is paid 25% of
 *        the would-be BAF pool game-side when the century flip loses
 *
 * @dev DAILY DRAW (per participation day d):
 *      - A player burns at least 25 WWXRP via enter(); the burn and the
 *        recorded entry always belong to msg.sender.
 *      - Every address maps to exactly one of 10 buckets for day d:
 *        bucket = keccak(domain, chainid, this, d, player) % 10. All of an
 *        address's burns on a day share that bucket; the player cannot pick it.
 *      - Each burn snapshots the player's activity score and records
 *        effectiveScore = amount * multBps / (10_000 * 1e18) — whole-WWXRP
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
 *        the prize to the player recorded in the winning entry.
 *
 * @dev DRAW SECURITY — WHY day d SETTLES ON WORD d+1:
 *      rngWordByDay[X] is only ever written for days X <= the current wall
 *      day (AdvanceModule _applyDailyRng / _backfillGapDays), and the
 *      RNGREUSE clamp guarantees a word requested on day R resolves only
 *      days <= R — so the value of word d+1 is unknowable until day d has
 *      already closed. enter() derives the day from GameTimeLib (the exact
 *      pure math behind the game's own day index), so a recorded word for
 *      day d+1 while entry is open is structurally impossible — the same
 *      settlement-blindness model as coinflip deposits, which also stay open
 *      through the daily lock and settle on the next word. reverseFlip
 *      nudges are committed blind (blocked while a request is in flight) at
 *      compounding FLIP cost. Accepted residual: the game-over
 *      historical/prevrandao fallback words (partially predictable) exist
 *      only after a 14+ day VRF stall — a terminally broken game whose FLIP
 *      has no remaining redemption path, and whose terminal jackpot already
 *      runs on that same by-design fallback — so entry carries no stall
 *      gate; burns into a dead game's days simply never settle. The draw has
 *      no owner, no parameter mutation, and no override of RNG, winner,
 *      probability, prize, or recipient.
 *
 * @dev SECURITY:
 *      - Uses Solidity 0.8+ overflow protection
 *      - Draw claim follows checks-effects-interactions (day marked claimed
 *        before the coinflip credit); no token in the flow has transfer hooks
 */

import {ContractAddresses} from "./ContractAddresses.sol";
import {ActivityCurveLib} from "./libraries/ActivityCurveLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

/// @dev Minimal Game surface consumed by the daily draw (views only; the
///      draw never mutates game state).
interface IDrawGame {
    function rngWordForDay(uint24 day) external view returns (uint256);

    function playerActivityScore(
        address player
    ) external view returns (uint256);

    function level() external view returns (uint24);
}

/// @dev Coinflip stake-credit channel for draw prizes (WWXRP is an authorized
///      flip creditor alongside game/quests/affiliate/admin/sDGNRS).
interface IDrawCoinflip {
    function creditFlip(address player, uint256 amount) external;
}

contract WWXRP {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Standard ERC20 events plus vault allowance tracking                 |
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

    /// @notice Emitted when the vault spends from its uncirculating allowance
    /// @param spender VAULT when spent via _burn's vault path (WWXRP bets),
    ///        or the token contract (address(this)) when minted out via vaultMintTo
    /// @param amount Amount spent from allowance
    event VaultAllowanceSpent(address indexed spender, uint256 amount);

    /// @notice Emitted when WWXRP bound for the vault is escrowed to its mint allowance
    /// @param sender The original transfer sender when routed via _transfer,
    ///        or address(0) on a direct mint to the vault
    /// @param amount Amount added to the vault's mint allowance (18 decimals)
    event VaultEscrowRecorded(address indexed sender, uint256 amount);

    /// @notice Emitted for every recorded daily-draw entry
    /// @param day Participation day (settles on rngWordForDay(day + 1))
    /// @param player Entrant (always msg.sender of the burn)
    /// @param bucket Deterministic bucket for (day, player)
    /// @param entryIndex Index of this entry within the bucket
    /// @param burnAmount WWXRP burned (18 decimals)
    /// @param effectiveScore Activity-weighted score recorded for this burn
    ///        (whole-WWXRP units)
    /// @param cumulativeScore Bucket cumulative score endpoint after this burn
    ///        (whole-WWXRP units)
    event DrawEntered(
        uint24 indexed day,
        address indexed player,
        uint8 bucket,
        uint32 entryIndex,
        uint256 burnAmount,
        uint256 effectiveScore,
        uint256 cumulativeScore
    );

    /// @notice Emitted when a day's draw prize is claimed
    /// @param day Participation day that won
    /// @param winner Player recorded in the winning entry (prize recipient)
    /// @param big True for the BIG prize, false for SMALL
    /// @param prize FLIP amount credited as coinflip stake (18 decimals)
    /// @param bucket Winning bucket
    /// @param entryIndex Winning entry index within the bucket
    event DrawClaimed(
        uint24 indexed day,
        address indexed winner,
        bool big,
        uint256 prize,
        uint8 bucket,
        uint32 entryIndex
    );

    /// @notice Emitted for every recorded century BAF-incinerator entry
    /// @param bracket Century bracket the burn bets on (level x00)
    /// @param player Entrant (always msg.sender of the burn)
    /// @param entryIndex Index of this entry within the bracket
    /// @param burnAmount WWXRP burned (18 decimals)
    /// @param effectiveScore Activity-weighted score recorded for this burn
    ///        (wei units — full precision)
    /// @param cumulativeScore Bracket cumulative score endpoint after this
    ///        burn (wei units)
    event IncineratorEntered(
        uint24 indexed bracket,
        address indexed player,
        uint32 entryIndex,
        uint256 burnAmount,
        uint256 effectiveScore,
        uint256 cumulativeScore
    );

    /// @notice Emitted when a skipped century BAF resolves its incinerator draw
    /// @param bracket Century bracket whose BAF skipped (level x00)
    /// @param winner Player recorded in the winning entry (paid game-side)
    /// @param poolWei ETH pool credited to the winner by the game
    /// @param roll Winner roll in [0, totalScore)
    /// @param totalScore Bracket total effective score (wei units)
    event IncineratorResolved(
        uint24 indexed bracket,
        address indexed winner,
        uint256 poolWei,
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

    /// @notice Thrown when caller is not the vault
    error OnlyVault();

    /// @notice Thrown when vault allowance is insufficient
    error InsufficientVaultAllowance();

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

    /*+======================================================================+
      |                         ERC20 STATE                                  |
      +======================================================================+
      |  Standard ERC20 metadata and balances                                |
      +======================================================================+*/

    /// @notice Token name (a parody; not affiliated with or backed by XRP)
    string public constant name = "Wacky Wrapped XRP";

    /// @notice Token symbol
    string public constant symbol = "WWXRP";

    /// @notice Number of decimals
    uint8 public constant decimals = 18;

    /// @notice Total circulating supply of WWXRP (excludes vault allowance)
    uint256 public totalSupply;

    /// @notice Initial uncirculating reserve (1B WWXRP, 18 decimals)
    uint256 public constant INITIAL_VAULT_ALLOWANCE = 1_000_000_000 ether;

    /// @notice Remaining uncirculating reserve the vault can mint from.
    ///         Grows when WWXRP is transferred or minted to the vault (escrow).
    uint256 public vaultAllowance = INITIAL_VAULT_ALLOWANCE;

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

    /// @dev Vault contract address authorized to mint from uncirculating reserve
    address internal constant MINTER_VAULT = ContractAddresses.VAULT;

    /// @dev Game views consumed by the daily draw (day index, daily word,
    ///      activity score, VRF freshness, game-over flag)
    IDrawGame private constant game = IDrawGame(ContractAddresses.GAME);

    /// @dev Coinflip contract credited with draw prizes (FLIP-denominated stake)
    IDrawCoinflip private constant coinflip =
        IDrawCoinflip(ContractAddresses.COINFLIP);

    /// @notice Number of equal draw buckets every participation day
    uint256 public constant BUCKET_COUNT = 10;

    /// @notice BIG draw prize (FLIP, 18 decimals), gated at 1/365 per day
    uint256 public constant BIG_PRIZE = 100_000 ether;

    /// @notice SMALL draw prize (FLIP, 18 decimals), gated at 1/30 when BIG misses
    uint256 public constant SMALL_PRIZE = 10_000 ether;

    /// @notice Minimum WWXRP burn per draw entry (18 decimals)
    uint256 public constant MIN_BURN = 25 ether;

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

    /// @dev Draw accumulators are denominated in WHOLE WWXRP (sub-token dust
    ///      burns but adds no weight): uint96 then holds ~7.9e28 tokens per
    ///      (day, bucket) — headroom for an arbitrarily inflationary supply.
    uint256 private constant SCORE_UNIT = 1 ether;

    /// @dev Domain tags for the draw's bucket hash and four outcome hashes
    bytes32 private constant DOM_BUCKET = "WWXRP_DRAW_BUCKET";
    bytes32 private constant DOM_BIG = "WWXRP_DRAW_BIG";
    bytes32 private constant DOM_SMALL = "WWXRP_DRAW_SMALL";
    bytes32 private constant DOM_WIN_BUCKET = "WWXRP_DRAW_WIN_BUCKET";
    bytes32 private constant DOM_WINNER = "WWXRP_DRAW_WINNER";

    /// @dev Domain tag for the BAF-incinerator winner roll
    bytes32 private constant DOM_INCIN_WINNER = "WWXRP_INCIN_WINNER";

    /*+======================================================================+
      |                          DAILY DRAW STATE                            |
      +======================================================================+
      |  One packed header word per (day, bucket) and one packed word per    |
      |  entry. Winner verification is O(1): an entry stores its cumulative  |
      |  score endpoint; the previous entry's endpoint is the interval start.|
      +======================================================================+*/

    /// @dev Header per (day, bucket):
    ///      bits [0..95]    whole WWXRP burned (analytics / future scaling input)
    ///      bits [96..191]  total effective score (last cumulative endpoint,
    ///                      whole-WWXRP units)
    ///      bits [192..223] entry count
    ///      Key: (day << 8) | bucket.
    mapping(uint256 => uint256) private _drawHeader;

    /// @dev Entry per (day, bucket, index):
    ///      bits [0..95]    cumulative effective score endpoint (exclusive,
    ///                      whole-WWXRP units)
    ///      bits [96..255]  player address
    ///      Key: (day << 40) | (bucket << 32) | index. Never zero for a
    ///      recorded entry (endpoint >= 25 units via MIN_BURN at 1.0x).
    mapping(uint256 => uint256) private _drawEntry;

    /// @notice True once a day's draw prize has been claimed
    mapping(uint24 => bool) public dayClaimed;

    /*+======================================================================+
      |                    CENTURY BAF-INCINERATOR STATE                       |
      +======================================================================+
      |  Burn-weighted entries recorded during a level x99, betting that the |
      |  next century BAF (level x00) skips. Interval accounting mirrors the |
      |  daily draw but is keyed by bracket and denominated in full wei.     |
      +======================================================================+*/

    /// @dev Unlike the whole-token daily draw, incinerator scores are full
    ///      18-decimal wei: the supply is uncapped-inflationary, so no
    ///      whole-token uint96 bound can be guaranteed. uint192 for the
    ///      bracket total (~6.3e57 wei at a 3x activity ceiling) is safe for
    ///      any reachable supply; entry endpoints get a full uint256 slot.

    /// @dev Header per bracket (level x00):
    ///      bits [0..191]   total effective score (last cumulative endpoint,
    ///                      wei units)
    ///      bits [192..223] entry count
    mapping(uint24 => uint256) private _incinHeader;

    /// @notice One incinerator interval entry (two slots: full-precision
    ///         endpoint + player).
    struct IncinEntry {
        /// @notice Cumulative effective score endpoint (exclusive, wei units).
        uint256 cum;
        /// @notice Entrant credited if the winner roll lands in this interval.
        address player;
    }

    /// @dev Entry per (bracket, index). Key: (bracket << 32) | index. The
    ///      resolve binary search touches only the cum slot per probe; the
    ///      player slot is read once for the winner.
    mapping(uint256 => IncinEntry) private _incinEntry;

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

    /// @notice Total supply including uncirculating vault allowance
    /// @dev Used by dashboards to show circulation + reserve.
    function supplyIncUncirculated() external view returns (uint256) {
        return totalSupply + vaultAllowance;
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

    /// @dev Internal transfer helper - moves tokens between addresses.
    ///      The vault holds no circulating WWXRP: an amount routed to it
    ///      de-circulates into the vault's mint allowance instead (same
    ///      escrow model as FLIP).
    /// @param from The source address
    /// @param to The destination address
    /// @param amount The amount to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();

        balanceOf[from] -= amount;

        if (to == MINTER_VAULT) {
            unchecked {
                // amount <= sender balance <= totalSupply
                totalSupply -= amount;
                vaultAllowance += amount;
            }
            emit Transfer(from, address(0), amount);
            emit VaultEscrowRecorded(from, amount);
            return;
        }

        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    /// @dev Internal mint helper - creates new tokens.
    ///      A mint targeting the vault escrows to its allowance (never a
    ///      circulating balance), so prize channels that can pay the vault
    ///      (coinflip loss rewards, lootbox faces, BAF consolation) feed the
    ///      reserve instead of stranding tokens.
    /// @param to The recipient of newly minted tokens
    /// @param amount The amount to mint
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        if (to == MINTER_VAULT) {
            vaultAllowance += amount;
            emit VaultEscrowRecorded(address(0), amount);
            return;
        }

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal burn helper - destroys tokens.
    ///      The vault holds no circulating WWXRP: its burns (WWXRP Degenerette
    ///      bets via burnForGame) spend the mint allowance instead, so the
    ///      vault stays a full player on every WWXRP surface.
    /// @param from The address to burn tokens from
    /// @param amount The amount to burn
    function _burn(address from, uint256 amount) internal {
        if (from == MINTER_VAULT) {
            uint256 allowanceVault = vaultAllowance;
            if (amount > allowanceVault) revert InsufficientVaultAllowance();
            unchecked {
                vaultAllowance = allowanceVault - amount;
            }
            emit VaultAllowanceSpent(from, amount);
            return;
        }

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
    /// @dev Only callable by authorized minters (game/coinflip/jackpots contracts).
    /// @param to Recipient of the minted WWXRP
    /// @param amount Amount to mint (18 decimals)
    /// @custom:reverts OnlyMinter When caller is not an authorized minter
    /// @custom:reverts ZeroAddress When to is address(0)
    function mintPrize(address to, uint256 amount) external {
        if (
            msg.sender != MINTER_GAME &&
            msg.sender != MINTER_COINFLIP &&
            msg.sender != MINTER_JACKPOTS
        ) {
            revert OnlyMinter();
        }

        _mint(to, amount);
    }

    /// @notice Mint WWXRP to a recipient from the vault's uncirculating reserve
    /// @dev Only callable by the vault contract. Reduces vault allowance and mints to recipient.
    /// @param to Recipient address
    /// @param amount Amount to mint (18 decimals)
    /// @custom:reverts OnlyVault When caller is not the vault
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts InsufficientVaultAllowance When amount exceeds remaining allowance
    function vaultMintTo(address to, uint256 amount) external {
        if (msg.sender != MINTER_VAULT) revert OnlyVault();

        uint256 allowanceVault = vaultAllowance;
        if (amount > allowanceVault) revert InsufficientVaultAllowance();
        unchecked {
            vaultAllowance = allowanceVault - amount;
        }
        _mint(to, amount);
        emit VaultAllowanceSpent(address(this), amount);
    }

    /// @notice Burn WWXRP for game bets
    /// @dev Only callable by the game contract. Silently returns if amount is zero.
    /// @param from Address to burn from
    /// @param amount Amount to burn (18 decimals)
    /// @custom:reverts OnlyMinter When caller is not the game contract
    /// @custom:reverts InsufficientBalance When from has insufficient balance
    function burnForGame(address from, uint256 amount) external {
        if (msg.sender != MINTER_GAME) revert OnlyMinter();
        if (amount == 0) return;
        _burn(from, amount);
    }

    /*+======================================================================+
      |                        DAILY DRAW: ENTRY                             |
      +======================================================================+*/

    /// @notice Burn WWXRP from the caller for a weighted entry in today's draw.
    ///         During a level x99 the same burn also enters the century
    ///         BAF-incinerator draw for the upcoming x00 bracket.
    /// @dev The burned balance and the entry belong to msg.sender only — no
    ///      beneficiary parameter, so nobody can burn another player's balance
    ///      or attach another player's activity score. Multiple burns per day
    ///      are allowed; each records its own activity snapshot and interval.
    ///      Entry stays open during the daily RNG lock (like flip deposits):
    ///      the lock covers TODAY's word while this entry settles on
    ///      TOMORROW's, which cannot exist yet — structurally, since the game
    ///      only ever records words for days <= the current wall day, so no
    ///      in-path check is needed. The
    ///      incinerator piggyback needs no such care: its deciding word's
    ///      request bumps the level off x99 first (see
    ///      _recordIncineratorEntry).
    /// @param amount WWXRP to burn (18 decimals, at least MIN_BURN). The full
    ///        amount burns; winner weight counts whole WWXRP only.
    /// @custom:reverts BelowMinBurn When amount is under 25 WWXRP.
    /// @custom:reverts ScoreOverflow When the bucket entry count would overflow.
    /// @custom:reverts InsufficientBalance When the caller's balance is short.
    function enter(uint256 amount) external {
        if (amount < MIN_BURN) revert BelowMinBurn();

        // Same pure wall-clock math as the game's own day index — no external
        // call needed. Words for day+1 cannot exist yet: the game only ever
        // records words for days <= the current wall day.
        uint24 day = GameTimeLib.currentDayIndex();
        uint8 bucket = bucketOf(day, msg.sender);
        // Activity snapshot at burn time; never re-read at claim. Score is
        // whole-WWXRP-denominated (one truncation, after the bps weighting).
        uint256 multBps = drawMultBps(game.playerActivityScore(msg.sender));
        uint256 effective = (amount * multBps) / (BPS * SCORE_UNIT);

        uint256 hKey = _drawHeaderKey(day, bucket);
        uint256 header = _drawHeader[hKey];
        uint256 raw = header & type(uint96).max;
        uint256 total = (header >> 96) & type(uint96).max;
        uint256 count = header >> 192;

        uint256 newRaw = raw + amount / SCORE_UNIT;
        uint256 newTotal = total + effective;
        if (count >= type(uint32).max) revert ScoreOverflow();
        // Saturate rather than revert: a capped bucket keeps accepting burns.
        // Post-cap entries record zero-width intervals (cumEnd == cumStart ==
        // cap), so they carry no winner weight and can never falsely verify.
        if (newRaw > type(uint96).max) newRaw = type(uint96).max;
        if (newTotal > type(uint96).max) newTotal = type(uint96).max;

        _drawHeader[hKey] = newRaw | (newTotal << 96) | ((count + 1) << 192);
        _drawEntry[_drawEntryKey(day, bucket, uint32(count))] =
            newTotal |
            (uint256(uint160(msg.sender)) << 96);

        // Level-x99 burns double as century BAF-incinerator entries: the same
        // burn and activity multiplier also arm the next x00 bracket's skip
        // draw (at full wei precision there — no whole-token truncation).
        uint24 lvl = game.level();
        if (lvl % 100 == 99) {
            _recordIncineratorEntry(lvl + 1, amount, multBps);
        }

        _burn(msg.sender, amount);

        emit DrawEntered(
            day,
            msg.sender,
            bucket,
            uint32(count),
            amount,
            effective,
            newTotal
        );
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
        (bool big, uint8 bucket, uint256 roll, uint256 total) = _outcome(day);
        // _outcome reverts NoPrize/WordUnavailable; empty bucket is a dud.
        if (total == 0) revert EmptyWinningBucket();
        if (dayClaimed[day]) revert AlreadyClaimed();

        uint256 entry = _drawEntry[_drawEntryKey(day, bucket, entryIndex)];
        if (entry == 0) revert EntryMissing();
        uint256 cumEnd = entry & type(uint96).max;
        uint256 cumStart = entryIndex == 0
            ? 0
            : _drawEntry[_drawEntryKey(day, bucket, entryIndex - 1)] &
                type(uint96).max;
        if (roll < cumStart || roll >= cumEnd) revert NotWinningEntry();

        dayClaimed[day] = true;
        address winner = address(uint160(entry >> 96));
        uint256 prize = big ? BIG_PRIZE : SMALL_PRIZE;
        coinflip.creditFlip(winner, prize);

        emit DrawClaimed(day, winner, big, prize, bucket, entryIndex);
    }

    /*+======================================================================+
      |                        DAILY DRAW: VIEWS                             |
      +======================================================================+*/

    /// @notice Deterministic draw bucket for (day, player). Domain-separated
    ///         by chain and deployment address; identical for all of a
    ///         player's burns on a day.
    function bucketOf(uint24 day, address player) public view returns (uint8) {
        return
            uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            DOM_BUCKET,
                            block.chainid,
                            address(this),
                            day,
                            player
                        )
                    )
                ) % BUCKET_COUNT
            );
    }

    /// @notice Winner-weight multiplier in bps for an activity score: the
    ///         Decimator curve shape rescaled from 1.0x-1.7833x to 1.0x-3.0x.
    function drawMultBps(uint256 activityScore) public pure returns (uint256) {
        uint256 base = ActivityCurveLib.decMultBps(activityScore);
        // Saturate: the library caps at MULT_MAX_BPS already; clamp defends
        // the subtraction ordering regardless.
        if (base >= ActivityCurveLib.MULT_MAX_BPS) return BPS + TARGET_SPAN_BPS;
        return
            BPS +
            ((base - ActivityCurveLib.MULT_MIN_BPS) * TARGET_SPAN_BPS) /
            BASE_SPAN_BPS;
    }

    /// @notice Draw bucket totals for a (day, bucket).
    /// @return rawBurned Whole WWXRP burned into the bucket (dust excluded).
    /// @return totalScore Total effective (activity-weighted) score in
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
        uint256 header = _drawHeader[_drawHeaderKey(day, bucket)];
        rawBurned = header & type(uint96).max;
        totalScore = (header >> 96) & type(uint96).max;
        entryCount = uint32(header >> 192);
    }

    /// @notice A recorded draw entry's player and cumulative score endpoint
    ///         (whole-WWXRP units).
    function entryAt(
        uint24 day,
        uint8 bucket,
        uint32 index
    ) external view returns (address player, uint256 cumulativeScore) {
        uint256 entry = _drawEntry[_drawEntryKey(day, bucket, index)];
        player = address(uint160(entry >> 96));
        cumulativeScore = entry & type(uint96).max;
    }

    /// @notice Non-reverting draw outcome preview for indexers/UI.
    /// @return wordAvailable True once rngWordForDay(day + 1) is recorded.
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
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) return (false, false, false, 0, 0, 0, dayClaimed[day]);
        wordAvailable = true;
        claimed = dayClaimed[day];
        big = _drawHash(DOM_BIG, day, word) % BIG_GATE == 0;
        bool small = !big &&
            _drawHash(DOM_SMALL, day, word) % SMALL_GATE == 0;
        if (!big && !small) return (true, false, false, 0, 0, 0, claimed);
        winningBucket = uint8(
            _drawHash(DOM_WIN_BUCKET, day, word) % BUCKET_COUNT
        );
        uint256 header = _drawHeader[_drawHeaderKey(day, winningBucket)];
        totalScore = (header >> 96) & type(uint96).max;
        if (totalScore == 0) {
            // Gate hit but the bucket is empty: dud day, no prize, no reroll.
            return (true, false, big, winningBucket, 0, 0, claimed);
        }
        prize = true;
        roll = _drawHash(DOM_WINNER, day, word) % totalScore;
    }

    /// @notice Locate the winning entry for a prize day by binary search over
    ///         the strictly increasing cumulative endpoints. View-only helper
    ///         for claim callers/indexers; never used in state-changing paths.
    /// @return found True when the day has a prize and a winning entry.
    /// @return entryIndex Index to pass to claim().
    /// @return player Recorded winner.
    function findWinningEntry(
        uint24 day
    ) external view returns (bool found, uint32 entryIndex, address player) {
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) return (false, 0, address(0));
        bool big = _drawHash(DOM_BIG, day, word) % BIG_GATE == 0;
        if (!big && _drawHash(DOM_SMALL, day, word) % SMALL_GATE != 0) {
            return (false, 0, address(0));
        }
        uint8 bucket = uint8(
            _drawHash(DOM_WIN_BUCKET, day, word) % BUCKET_COUNT
        );
        uint256 header = _drawHeader[_drawHeaderKey(day, bucket)];
        uint256 total = (header >> 96) & type(uint96).max;
        if (total == 0) return (false, 0, address(0));
        uint256 roll = _drawHash(DOM_WINNER, day, word) % total;

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
        return (true, lo, address(uint160(entry >> 96)));
    }

    /*+======================================================================+
      |                       CENTURY BAF INCINERATOR                        |
      +======================================================================+
      |  A hedge on the century BAF's 50/50 fire gate: daily-draw burns made |
      |  during a level x99 (via enter()) also arm the next x00 bracket and  |
      |  pay one burn-weighted winner iff that level's BAF skips (daily flip |
      |  lost). The ETH pool is game-side — 25% of the would-be BAF pool,    |
      |  credited claimable by the advance path.                             |
      +======================================================================+*/

    /// @dev Record an incinerator entry riding a daily-draw burn during a
    ///      level x99. The burn itself happened in enter(); this only appends
    ///      the bracket-keyed interval entry, weighting the FULL 18-decimal
    ///      amount by the same activity multiplier the carrying entry
    ///      snapshotted (no whole-token truncation). The level increments to
    ///      x00 in the same transaction that requests the VRF word whose
    ///      bit 0 decides the BAF fire gate, so enter()'s level check alone
    ///      closes entries before the deciding word can exist — no separate
    ///      rng-lock gate is needed. On a fired (won) BAF the bracket's
    ///      entries are simply never resolved: the burn was the losing side
    ///      of the hedge (the daily-draw entry it rode on still settles
    ///      normally).
    /// @param bracket Century bracket being armed (level x00).
    /// @param amount WWXRP burned by the carrying enter() (18 decimals).
    /// @param multBps Activity multiplier snapshotted by the carrying entry.
    /// @custom:reverts ScoreOverflow When the bracket entry count would overflow.
    function _recordIncineratorEntry(
        uint24 bracket,
        uint256 amount,
        uint256 multBps
    ) private {
        uint256 effective = (amount * multBps) / BPS;

        uint256 header = _incinHeader[bracket];
        uint256 total = header & type(uint192).max;
        uint256 count = header >> 192;

        uint256 newTotal = total + effective;
        if (count >= type(uint32).max) revert ScoreOverflow();
        // Saturate rather than revert (same policy as the daily draw): a
        // capped bracket keeps accepting burns; post-cap entries record
        // zero-width intervals and carry no winner weight.
        if (newTotal > type(uint192).max) newTotal = type(uint192).max;

        _incinHeader[bracket] = newTotal | ((count + 1) << 192);
        IncinEntry storage e = _incinEntry[
            _incinEntryKey(bracket, uint32(count))
        ];
        e.cum = newTotal;
        e.player = msg.sender;

        emit IncineratorEntered(
            bracket,
            msg.sender,
            uint32(count),
            amount,
            effective,
            newTotal
        );
    }

    /// @notice Resolve a skipped century BAF's incinerator draw to one winner.
    /// @dev Called by the game's advance path exactly once per skipped x00
    ///      bracket, in the same call that processes the skip — the caller
    ///      credits poolWei to the returned winner claimable-side. Returns
    ///      address(0) when the bracket has no entries (caller then leaves
    ///      the full pool in futurePool). Winner selection is a
    ///      domain-separated roll over the burn-weighted cumulative
    ///      intervals, located by binary search.
    /// @param bracket Skipped century bracket (level x00).
    /// @param rngWord VRF word of the transition that skipped the BAF.
    /// @param poolWei ETH the caller pays the winner (event data only here).
    /// @return winner Recorded winner, or address(0) for an empty bracket.
    /// @custom:reverts OnlyMinter When caller is not the game contract.
    function resolveIncinerator(
        uint24 bracket,
        uint256 rngWord,
        uint256 poolWei
    ) external returns (address winner) {
        if (msg.sender != MINTER_GAME) revert OnlyMinter();

        uint256 header = _incinHeader[bracket];
        uint256 total = header & type(uint192).max;
        if (total == 0) return address(0);

        uint256 roll = uint256(
            keccak256(
                abi.encodePacked(
                    DOM_INCIN_WINNER,
                    address(this),
                    bracket,
                    rngWord
                )
            )
        ) % total;

        // Smallest index whose cumulative endpoint exceeds the roll.
        uint32 lo = 0;
        uint32 hi = uint32(header >> 192) - 1;
        while (lo < hi) {
            uint32 mid = lo + (hi - lo) / 2;
            if (_incinEntry[_incinEntryKey(bracket, mid)].cum > roll) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        winner = _incinEntry[_incinEntryKey(bracket, lo)].player;

        emit IncineratorResolved(bracket, winner, poolWei, roll, total);
    }

    /// @notice Incinerator bracket totals.
    /// @return totalScore Total effective (activity-weighted) score in wei
    ///         units.
    /// @return entryCount Number of entries recorded.
    function incineratorInfo(
        uint24 bracket
    ) external view returns (uint256 totalScore, uint32 entryCount) {
        uint256 header = _incinHeader[bracket];
        totalScore = header & type(uint192).max;
        entryCount = uint32(header >> 192);
    }

    /// @notice A recorded incinerator entry's player and cumulative score
    ///         endpoint (wei units).
    function incineratorEntryAt(
        uint24 bracket,
        uint32 index
    ) external view returns (address player, uint256 cumulativeScore) {
        IncinEntry storage e = _incinEntry[_incinEntryKey(bracket, index)];
        player = e.player;
        cumulativeScore = e.cum;
    }

    function _incinEntryKey(
        uint24 bracket,
        uint32 index
    ) private pure returns (uint256) {
        return (uint256(bracket) << 32) | index;
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
        returns (bool big, uint8 bucket, uint256 roll, uint256 total)
    {
        uint256 word = game.rngWordForDay(day + 1);
        if (word == 0) revert WordUnavailable();
        big = _drawHash(DOM_BIG, day, word) % BIG_GATE == 0;
        if (!big && _drawHash(DOM_SMALL, day, word) % SMALL_GATE != 0) {
            revert NoPrize();
        }
        bucket = uint8(_drawHash(DOM_WIN_BUCKET, day, word) % BUCKET_COUNT);
        total = (_drawHeader[_drawHeaderKey(day, bucket)] >> 96) &
            type(uint96).max;
        if (total != 0) {
            roll = _drawHash(DOM_WINNER, day, word) % total;
        }
    }

    /// @dev Domain-separated outcome hash over the immutable next-day word.
    ///      The word is game-global; this address keys the derivation away
    ///      from every other consumer of the same word.
    function _drawHash(
        bytes32 domain,
        uint24 day,
        uint256 word
    ) private view returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(domain, address(this), day, word))
            );
    }

    function _drawHeaderKey(
        uint24 day,
        uint8 bucket
    ) private pure returns (uint256) {
        return (uint256(day) << 8) | bucket;
    }

    function _drawEntryKey(
        uint24 day,
        uint8 bucket,
        uint32 index
    ) private pure returns (uint256) {
        return (uint256(day) << 40) | (uint256(bucket) << 32) | index;
    }
}
