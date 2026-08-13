// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title AFKing Subscription Token
 * @author Burnie Degenerus
 * @notice The afking seat license: holding at least 1 seat is the sole
 *         credential for an afking-mode subscription on the game. A
 *         2,000-serial ERC721 collection with fully on-chain SVG art. A seat
 *         is MINTED to its holder (no claim step): pass acquisition mints one
 *         game-side, and the vault mints from its own tranche. Art starts at a
 *         deterministic default and every holder may restyle it — symbol (0-31)
 *         plus ANY 24-bit RGB background and trim — cosmetic only (the game
 *         reads nothing but balanceOf).
 *
 * @dev SEAT MODEL (sub <=> seat):
 *      - Fixed 2,000 serials, minted only through three bounded tranches:
 *        2 permanent construction seats — serial 1 to SDGNRS, serial 2 to
 *        the VAULT (default colors; neither has an ERC721-out path, so both
 *        protocol self-subscribers hold their seats forever) — a 1,000-seat
 *        FREE tranche minted to pass buyers as they acquire (one per address
 *        for life, enforced by the game's SEAT_CLAIMED latch; past 1,000 a
 *        pass simply confers no seat), and a 998-seat VAULT tranche the vault
 *        mints directly to any recipient via its owner-gated afkingSeatMint —
 *        locked until the free tranche's 1,000 are gone, so paid seats can
 *        never crowd out free ones.
 *        2 + 1,000 + 998 = 2,000: the tranche accounting IS the supply cap
 *        (MAX_SERIAL is a fail-loud backstop).
 *      - The game gates subscribe on balanceOf >= 1. Ownership is checked
 *        ONLY there; the seat lock below blocks an encumbered holder's
 *        last-seat transfer until they unsubscribe cleanly (an eviction
 *        forfeits the seat instead — see EVICTION FORFEIT).
 *
 * @dev SEAT LOCK (the only nonstandard ERC721 transfer behavior):
 *      Whenever a transfer takes a sender's balance to exactly 0, it
 *      STATICCALLs the game's subInfo view and mintPackedFor's
 *      SEAT_ENCUMBERED bit and reverts SeatInUse while either holds: an
 *      ACTIVE afking subscription, or a still-set encumbrance latch (an
 *      eviction forfeit awaiting reclaimSeat). The seat is the credential
 *      (sub <=> seat), so an active subscriber cannot part with their last
 *      seat — a manual unsubscribe clears both and frees the seat to sell
 *      in the next tx. Multi-seat holders and plain holders are never
 *      blocked; a self-transfer nets to a nonzero balance and never
 *      triggers the check. The game calls here are read-only — mints
 *      cannot cross to zero, and there is no burn path.
 *
 * @dev EVICTION FORFEIT (reclaimSeat): the game's subscribe sets the
 *      holder's SEAT_ENCUMBERED latch and only a manual cancel clears it,
 *      so an evicted (funding-killed) sub leaves the bit set with no
 *      active sub — the provable forfeit state. While it holds: the seat
 *      lock traps the holder's last seat, tokenURI renders the evicted
 *      WWXRP art, the game refuses a fresh subscribe (SeatForfeited), and
 *      ANYONE may call reclaimSeat to force-transfer exactly one of the
 *      holder's seats to the VAULT (which re-sells via its owner-gated
 *      afkingSeatTransfer). The reclaim then clears the latch through the
 *      game's AFKING_SUB_TOKEN-only clearSeatEncumbrance, ending the
 *      forfeit: no second seat is seizable, remaining seats transfer
 *      freely, and the address may subscribe again once it holds a seat.
 *
 * @dev ART (the protocol's three-ring ticket badge, one big badge instead
 *      of four quadrants): a rounded card filled with the buyer's
 *      background RGB and stroked with the buyer's trim RGB, carrying one
 *      large concentric-ring badge — outer ring in the trim RGB, middle
 *      #111, inner #fff (the ticket renderer's 1 : 0.78 : 0.62 radii) —
 *      with the buyer-chosen Icons32 symbol fitted into the inner circle.
 *      Crypto symbols keep their source colors; non-crypto symbols are
 *      inked in the trim RGB (as tickets ink them in the trait color).
 *      Free 24-bit picks, stored per token. An owner-set external renderer
 *      may override; a reverting or empty external render falls back to
 *      the internal renderer.
 */

import {ContractAddresses} from "./ContractAddresses.sol";
import {BitPackingLib} from "./libraries/BitPackingLib.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Icons32 data contract interface for SVG path data and symbol names.
interface IIcons32 {
    /// @notice Get the SVG path data for icon at index i.
    /// @param i Icon index (0-31).
    function data(uint256 i) external view returns (string memory);

    /// @notice Get the human-readable symbol name.
    /// @param quadrant Quadrant index (0-3, 8 symbols each).
    /// @param idx Symbol index within the quadrant (0-7).
    function symbol(uint256 quadrant, uint8 idx) external view returns (string memory);
}

/// @dev Game surface consumed by this token: subInfo backs the seat lock
///      (only `active` — the first return — is read: true while the holder
///      has a live afking subscription); mintPackedFor backs the seat lock /
///      forfeit checks (the SEAT_ENCUMBERED bit) — the game keeps its own
///      SEAT_CLAIMED latch as the once-per-address mint gate, and this token
///      no longer reads it; clearSeatEncumbrance is
///      the one mutator — AFKING_SUB_TOKEN-only game-side, called by
///      reclaimSeat after seizing a forfeited seat.
interface ISeatGameViews {
    function clearSeatEncumbrance(address holder) external;

    function subInfo(
        address player
    )
        external
        view
        returns (
            bool active,
            uint8 dailyQuantity,
            uint24 afkingStartDay,
            uint24 afkCoveredThroughDay
        );

    function mintPackedFor(address player) external view returns (uint256);
}

/// @dev Vault interface for DGVE ownership check (admin surface auth).
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Optional external renderer interface (v1).
/// @dev A reverting or empty external render falls back to the internal renderer;
///      the staticcall is not gas-capped, and the renderer is owner-set and trusted.
interface ISeatRendererV1 {
    function render(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string calldata symbolName,
        string calldata iconPath,
        bool isCrypto,
        bool seatLocked,
        string calldata backgroundColor,
        string calldata trimColor
    ) external view returns (string memory);
}

/// @dev Minimal ERC721 receiver interface for the safe-transfer variants.
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract AFKingSubscriptionToken {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    /// @notice Caller is neither owner, approved, nor operator for the token
    ///         (or the admin caller does not hold >50.1% of DGVE)
    error NotAuthorized();

    /// @notice Token does not exist (or wrong `from` on transfer)
    error InvalidToken();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice symbolId >= 32 at claim
    error InvalidTrait();

    /// @notice Thrown when a transfer would empty an encumbered holder's
    ///         balance — an active subscriber unsubscribes before selling the
    ///         seat; an evicted holder's seat is forfeit until reclaimSeat
    error SeatInUse();

    /// @notice reclaimSeat target's holder is not in the eviction-forfeit
    ///         state (SEAT_ENCUMBERED set with no active sub)
    error NotEvicted();

    /// @notice Vault-tranche mints are locked until all 1,000 free-tranche
    ///         seats are minted
    error FreeTrancheOpen();

    /// @notice Mint would exceed the vault's 998-seat tranche
    error GrantExceedsTranche();

    /// @notice Thrown when a vault-tranche mint is not from the vault
    error OnlyVault();

    /// @notice Caller is not the GAME contract
    error OnlyGame();

    /// @notice Safe transfer to a contract that did not accept the token
    error UnsafeRecipient();

    /// @notice Thrown when a mint would exceed the 2,000-serial max supply
    ///         (unreachable through the tranche accounting; fail-loud backstop)
    error SupplyCapped();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    /// @notice ERC721 transfer (from = address(0) for mints)
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @notice ERC721 single-token approval
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /// @notice ERC721 operator approval
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    /// @notice Emitted when a seat is minted — on pass acquisition (game-driven) or
    ///         from the vault's 998-seat tranche. Art is the deterministic default and
    ///         is restylable at any time via setSeatTraits.
    /// @param to Seat recipient
    /// @param tokenId Serial minted
    /// @param symbolId Default icon index
    /// @param bgRgb Default background
    /// @param trimRgb Default trim
    event SeatMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    );

    /// @notice The vault minted seats from its 998-seat tranche
    /// @param to Seat recipient
    /// @param amount Seats minted in this call
    /// @param minted Lifetime total minted from the tranche after this call (<= 998)
    event VaultSeatsMinted(address indexed to, uint256 amount, uint256 minted);

    /// @notice An evicted holder's forfeited seat was reclaimed to the vault
    /// @param holder Evicted holder the seat was seized from
    /// @param tokenId Serial force-transferred to the VAULT
    event SeatReclaimed(address indexed holder, uint256 indexed tokenId);

    /// @notice Emitted when a seat owner restyles their card art.
    /// @param tokenId Seat serial restyled
    /// @param symbolId New icon index (0-31)
    /// @param bgRgb New 24-bit background
    /// @param trimRgb New 24-bit trim
    event SeatRestyled(
        uint256 indexed tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    );

    /// @notice External renderer changed
    event RendererUpdated(address indexed previousRenderer, address indexed newRenderer);

    /*+======================================================================+
      |                            CONSTANTS                                 |
      +======================================================================+*/

    /// @notice Free-tranche size: first 1,000 claims by latched-eligible
    ///         pass buyers
    uint256 public constant FREE_TRANCHE = 1000;

    /// @notice Vault claim-rights allowance (SDGNRS and the vault each hold
    ///         a construction seat; 2 + 1,000 + 998 = the 2,000-serial supply)
    uint256 public constant VAULT_TRANCHE = 998;

    /// @notice Hard serial cap — the tranche accounting sums to exactly this
    uint256 public constant MAX_SERIAL = 2000;

    /// @dev Default colors for the two construction seats: the deity-pass
    ///      card look (light ground, purple trim).
    uint24 private constant DEFAULT_BG = 0xd9d9d9;
    uint24 private constant DEFAULT_TRIM = 0x3f1a82;

    uint16 private constant ICON_VB = 512;

    /// @dev The three-ring badge radii on the ±50 card: one big badge with
    ///      the ticket renderer's ring ratios (mid = 0.78 × outer, inner =
    ///      0.62 × outer, integer-floored), sized to leave a 4-unit gutter
    ///      inside the card stroke.
    uint32 private constant RING_OUTER = 46;
    uint32 private constant RING_MID = 35;
    uint32 private constant RING_INNER = 28;

    /// @dev Dice 6 — quadrant 3 index 5, since quadrant = symbolId / 8.
    uint8 private constant GOLD_DICE6_SYMBOL_ID = 29;
    /// @dev The website's canonical gold trim.
    uint24 private constant GOLD_RGB = 0xAB8D3F;
    /// @dev Darkens the Dice 6 pips without touching the shared Icons32 slot: the
    ///      six pips carry an explicit fill="#fff", and a presentation attribute
    ///      loses to any CSS rule, so this flips them where the icon data cannot
    ///      be changed. Scoped to `#ico` so the badge rings — siblings of the
    ///      symbol group — keep their own fills, and the die body (a <rect>, no
    ///      fill of its own) still inherits the gold trim.
    string private constant GOLD_DICE6_PIP_STYLE = "<style>#ico circle{fill:#111}</style>";

    /*+======================================================================+
      |                          WIRED CONTRACTS                             |
      +======================================================================+*/

    /// @dev Game contract: seat-lock subInfo view + the SEAT_ENCUMBERED
    ///      forfeit latch (mintPackedFor)
    ISeatGameViews private constant game =
        ISeatGameViews(ContractAddresses.GAME);

    /// @dev Vault DGVE-majority check gating the admin render surface
    IDegenerusVaultOwner private constant vault =
        IDegenerusVaultOwner(ContractAddresses.VAULT);

    /*+======================================================================+
      |                             STORAGE                                  |
      +======================================================================+*/

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @dev Traits packed 4 per slot: the 64-bit lane at bit offset
    ///      ((tokenId & 3) << 6) of word (tokenId >> 2) holds
    ///      (trimRgb << 29) | (bgRgb << 5) | symbolId (53 bits used).
    mapping(uint256 => uint256) private _traitWords;

    /// @notice Optional external renderer (address(0) = internal only)
    address public renderer;

    /// @notice Next serial to mint (serials are 1-2000; monotonic, no burn)
    uint16 public nextSerial;

    /// @notice Free-tranche seats minted so far (of FREE_TRANCHE)
    uint16 public freeClaims;

    /// @notice Vault-tranche seats minted lifetime (of VAULT_TRANCHE)
    uint16 public vaultGranted;

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        _;
    }

    constructor() {
        // The protocol self-subscribers' permanent seats: serial 1 to SDGNRS,
        // serial 2 to the VAULT (default colors). Neither leaves: SDGNRS has no
        // transfer surface, and the seat lock binds a last seat held by an active
        // subscriber, which both perpetually are (the vault's 998-seat tranche
        // mints fresh serials to others, so selling never touches this one). Both
        // hold real seats forever and the game's coin gate and the seat lock need
        // no protocol special cases.
        nextSerial = 1;
        _mintSeat(ContractAddresses.SDGNRS, 0, DEFAULT_BG, DEFAULT_TRIM);
        _mintSeat(ContractAddresses.VAULT, 0, DEFAULT_BG, DEFAULT_TRIM);

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "afking.degenerus.eth")
            );
            ok;
        }
    }

    /*+======================================================================+
      |                         ERC721 METADATA                              |
      +======================================================================+*/

    function name() external pure returns (string memory) { return "AFKing Subscription Token"; }
    function symbol() external pure returns (string memory) { return "AFK"; }

    /// @notice Seats minted so far (serials 1..totalSupply; no burn path)
    function totalSupply() external view returns (uint256) {
        return uint256(nextSerial) - 1;
    }

    /*+======================================================================+
      |                            CLAIM FLOW                                |
      +======================================================================+*/

    /// @notice Mint a free-tranche seat directly to a pass acquirer (GAME only).
    /// @dev Called by the game on every pass acquisition, so a seat arrives WITHOUT a
    ///      separate claim step. Traits are seeded deterministically from (recipient,
    ///      serial) and the holder may restyle them at any time via `setSeatTraits` — the
    ///      art was always designed to be changeable, so nothing is lost by not choosing
    ///      at mint. No entropy is read: the seed is cosmetic-only and never touches a VRF
    ///      word, so this is outside the RNG-freeze surface entirely.
    ///
    ///      Silent no-op (never a revert) on an exhausted 1,000-seat tranche and on the
    ///      zero address, because this rides inside a purchase and must never brick one.
    ///      Past the tranche a pass simply confers no seat; the vault's separate 998-seat
    ///      tranche is untouched by this path.
    ///
    ///      The one-per-address limit is GAME-side, not here: the caller sets its
    ///      SEAT_CLAIMED latch before calling and mints only on the transition, so this
    ///      function mints whatever it is handed. Neither construction-seat holder is
    ///      excluded, so each can reach a mint once as a deity purchase's conferred
    ///      affiliate — the VAULT when the buyer has no referrer, SDGNRS through the
    ///      built-in DGNRS code it owns. One extra seat apiece, for their lifetimes.
    /// @param to Pass acquirer receiving the seat
    /// @custom:reverts OnlyGame When the caller is not the GAME contract
    function mintSeatFor(address to) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (to == address(0)) return;
        uint256 free = freeClaims;
        if (free >= FREE_TRANCHE) return;
        unchecked {
            freeClaims = uint16(free + 1);
        }
        _mintDefaultSeat(to);
    }

    /// @dev Mint one seat with deterministic default art seeded from (recipient, serial).
    ///      Cosmetic only — no VRF word is read, so this sits outside the RNG-freeze
    ///      surface entirely, and the holder may restyle at any time.
    function _mintDefaultSeat(address to) private returns (uint256 tokenId) {
        uint256 seed = uint256(keccak256(abi.encode(to, nextSerial)));
        uint8 symbolId = uint8(seed & 31);
        uint24 bgRgb = uint24((seed >> 8) & 0xFFFFFF);
        uint24 trimRgb = uint24((seed >> 32) & 0xFFFFFF);
        tokenId = _mintSeat(to, symbolId, bgRgb, trimRgb);
        emit SeatMinted(to, tokenId, symbolId, bgRgb, trimRgb);
    }

    /// @notice Restyle a seat you own. Traits are cosmetic and freely mutable by design.
    /// @dev Clears the serial's 64-bit trait lane before writing, so a restyle REPLACES
    ///      rather than ORs into the previous value (the mint path can assume a zero lane;
    ///      this one cannot).
    ///      The VAULT may additionally restyle the SDGNRS-held construction seat (serial 1).
    ///      SDGNRS is a protocol contract with no admin surface, so that seat's art would
    ///      otherwise be frozen at the constructor defaults forever; the vault (owner-gated
    ///      on its side, `afkingSeatRestyle`) is its steward. Cosmetic only — it confers no
    ///      authority over the seat itself, which SDGNRS still owns and which has no
    ///      ERC721-out path.
    /// @param tokenId Seat serial to restyle
    /// @param symbolId Icon index (0-31)
    /// @param bgRgb 24-bit card background
    /// @param trimRgb 24-bit card trim
    /// @custom:reverts NotAuthorized When the caller neither owns the seat nor is the VAULT
    ///                 restyling the SDGNRS construction seat
    /// @custom:reverts InvalidTrait When symbolId >= 32
    function setSeatTraits(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) external {
        address holder = _owners[tokenId];
        if (
            holder != msg.sender &&
            !(holder == ContractAddresses.SDGNRS &&
                msg.sender == ContractAddresses.VAULT)
        ) revert NotAuthorized();
        if (symbolId >= 32) revert InvalidTrait();
        uint256 shift = (tokenId & 3) << 6;
        uint256 word = _traitWords[tokenId >> 2];
        word &= ~(uint256(0xFFFFFFFFFFFFFFFF) << shift);
        _traitWords[tokenId >> 2] =
            word |
            (((uint256(trimRgb) << 29) | (uint256(bgRgb) << 5) | symbolId) <<
                shift);
        emit SeatRestyled(tokenId, symbolId, bgRgb, trimRgb);
    }

    /// @notice Mint seats from the vault's 998-seat tranche straight to a
    ///         recipient (vault only — reached through the vault's owner-gated
    ///         afkingSeatMint), each with default art the recipient may
    ///         restyle. Locked until the free tranche's 1,000 seats are all
    ///         out, so paid seats can never crowd out free ones.
    /// @param to Seat recipient
    /// @param amount Seats to mint
    /// @custom:reverts OnlyVault When caller is not the vault contract
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts FreeTrancheOpen While fewer than 1,000 free seats are out
    /// @custom:reverts GrantExceedsTranche When lifetime tranche mints would pass 998
    function vaultMintSeats(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        if (to == address(0)) revert ZeroAddress();
        if (freeClaims < FREE_TRANCHE) revert FreeTrancheOpen();
        uint256 minted = uint256(vaultGranted) + amount;
        if (minted > VAULT_TRANCHE) revert GrantExceedsTranche();
        vaultGranted = uint16(minted);
        for (uint256 i; i < amount; ) {
            _mintDefaultSeat(to);
            unchecked {
                ++i;
            }
        }
        emit VaultSeatsMinted(to, amount, minted);
    }

    /// @dev Mint the next serial with packed traits. The three tranches
    ///      (2 construction + 1,000 free + 998 vault) sum to MAX_SERIAL
    ///      exactly, so the cap check is an unreachable fail-loud backstop.
    function _mintSeat(
        address to,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) private returns (uint256 tokenId) {
        tokenId = nextSerial;
        if (tokenId > MAX_SERIAL) revert SupplyCapped();
        unchecked {
            nextSerial = uint16(tokenId + 1);
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        _traitWords[tokenId >> 2] |=
            ((uint256(trimRgb) << 29) | (uint256(bgRgb) << 5) | symbolId) <<
            ((tokenId & 3) << 6);
        emit Transfer(address(0), to, tokenId);
    }

    /// @notice A seat's buyer-chosen traits
    /// @param tokenId Serial to query
    /// @return symbolId Icon index (0-31)
    /// @return bgRgb 24-bit background color
    /// @return trimRgb 24-bit trim color
    /// @custom:reverts InvalidToken When the serial is not minted
    function seatTraits(
        uint256 tokenId
    ) public view returns (uint8 symbolId, uint24 bgRgb, uint24 trimRgb) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        uint256 packed = (_traitWords[tokenId >> 2] >>
            ((tokenId & 3) << 6)) & 0xFFFFFFFFFFFFFFFF;
        symbolId = uint8(packed & 31);
        bgRgb = uint24((packed >> 5) & 0xFFFFFF);
        trimRgb = uint24((packed >> 29) & 0xFFFFFF);
    }

    /*+======================================================================+
      |                          ERC721 VIEWS                                |
      +======================================================================+*/

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address ownerAddr) {
        ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0)) revert InvalidToken();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(
        address ownerAddr,
        address operator
    ) external view returns (bool) {
        return _operatorApprovals[ownerAddr][operator];
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x80ac58cd  // IERC721
            || id == 0x5b5e139f  // IERC721Metadata
            || id == 0x01ffc9a7; // IERC165
    }

    /*+======================================================================+
      |                        ERC721 MUTATIONS                              |
      +======================================================================+*/

    /// @notice Approve one address to transfer a specific seat
    /// @custom:reverts NotAuthorized When caller is neither owner nor operator
    function approve(address approved, uint256 tokenId) external {
        address ownerAddr = ownerOf(tokenId);
        if (
            msg.sender != ownerAddr &&
            !_operatorApprovals[ownerAddr][msg.sender]
        ) revert NotAuthorized();
        _tokenApprovals[tokenId] = approved;
        emit Approval(ownerAddr, approved, tokenId);
    }

    /// @notice Set or clear operator approval over all of caller's seats
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Transfer a seat — enforces the seat lock: a transfer that
    ///         empties an encumbered holder's balance reverts SeatInUse.
    ///         A manual unsubscribe clears both halves of the lock (the
    ///         cancel tombstone reads inactive and the encumbrance latch is
    ///         cleared in the same tx), so a clean leaver's seat sells in
    ///         the very next tx; an evicted holder's latch stays set, so
    ///         their last seat is trapped until reclaimSeat forfeits it.
    /// @custom:reverts InvalidToken When the serial is not minted or `from` is not its owner
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts NotAuthorized When caller is neither owner, approved, nor operator
    /// @custom:reverts SeatInUse When this transfer would empty the balance of
    ///                 an active subscriber or an unreclaimed evicted holder
    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ZeroAddress();
        address ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0) || ownerAddr != from) revert InvalidToken();
        if (
            msg.sender != ownerAddr &&
            !_operatorApprovals[ownerAddr][msg.sender] &&
            _tokenApprovals[tokenId] != msg.sender
        ) revert NotAuthorized();

        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);

        // Seat lock: a self-transfer nets to the original balance before this
        // check, so it can never trigger. Both game calls are read-only.
        // Blocked while EITHER holds — an active sub, or a still-set
        // SEAT_ENCUMBERED latch (an eviction forfeit awaiting reclaimSeat).
        if (_balances[from] == 0) {
            (bool active, , , ) = game.subInfo(from);
            if (
                active ||
                (game.mintPackedFor(from) >>
                    BitPackingLib.SEAT_ENCUMBERED_SHIFT) &
                    1 !=
                0
            ) revert SeatInUse();
        }
    }

    /// @notice Collect an eviction forfeit: force-transfer `tokenId` from its
    ///         evicted holder to the VAULT and clear the holder's encumbrance
    ///         latch. Permissionless — the holder is in the forfeit state
    ///         (SEAT_ENCUMBERED set with no active sub) only after an eviction,
    ///         so there is nothing to grief: the seizure target is fixed (the
    ///         VAULT) and exactly one seat per eviction is seizable (the latch
    ///         clear below ends the forfeit). The evicted holder may call this
    ///         themselves to settle up and re-enter with another seat. The
    ///         vault re-sells repossessions via its owner-gated
    ///         afkingSeatTransfer.
    /// @param tokenId Serial to seize; must be owned by an evicted holder.
    /// @custom:reverts InvalidToken When the serial is not minted
    /// @custom:reverts NotEvicted When the holder has an active sub or no
    ///                 encumbrance latch set (nothing is forfeit)
    function reclaimSeat(uint256 tokenId) external {
        address holder = ownerOf(tokenId);
        (bool active, , , ) = game.subInfo(holder);
        if (
            active ||
            (game.mintPackedFor(holder) >>
                BitPackingLib.SEAT_ENCUMBERED_SHIFT) &
                1 ==
            0
        ) revert NotEvicted();

        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[holder] -= 1;
            _balances[ContractAddresses.VAULT] += 1;
        }
        _owners[tokenId] = ContractAddresses.VAULT;
        emit Transfer(holder, ContractAddresses.VAULT, tokenId);

        // Settle the forfeit game-side: clears SEAT_ENCUMBERED (this token is
        // the only authorized caller), so no second seat is seizable and the
        // holder may subscribe again once they hold a seat.
        game.clearSeatEncumbrance(holder);
        emit SeatReclaimed(holder, tokenId);
    }

    /// @notice transferFrom + ERC721Receiver acceptance check for contracts
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice transferFrom + ERC721Receiver acceptance check for contracts
    /// @custom:reverts UnsafeRecipient When the recipient contract does not
    ///                 return the onERC721Received selector
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            if (
                IERC721Receiver(to).onERC721Received(
                    msg.sender,
                    from,
                    tokenId,
                    data
                ) != IERC721Receiver.onERC721Received.selector
            ) revert UnsafeRecipient();
        }
    }

    /*+======================================================================+
      |                       ADMIN RENDER SURFACE                           |
      +======================================================================+*/

    /// @notice Set optional external renderer. Set to address(0) to disable.
    /// @param newRenderer Address of the new renderer contract (or zero to use internal).
    function setRenderer(address newRenderer) external onlyOwner {
        address prev = renderer;
        renderer = newRenderer;
        emit RendererUpdated(prev, newRenderer);
    }

    /*+======================================================================+
      |                             TOKEN URI                                |
      +======================================================================+*/

    /// @notice On-chain SVG metadata for each seat. LIVE state, dynamic per
    ///         holder: a seat is "Locked" while the seat lock would block its
    ///         transfer (the holder is encumbered — active sub or unreclaimed
    ///         eviction — and this is their only seat), rendering a corner
    ///         padlock and a Status attribute; it reads "Transferable" again
    ///         the moment the holder unsubscribes cleanly or gains a second
    ///         seat. An EVICTED holder's seats render the forfeit art instead:
    ///         the WWXRP mark (the XRP glyph, Icons32 index 0) near-full-card
    ///         with NO badge rings, a WWXRP wordmark at the card foot, and
    ///         Status "Evicted - reclaimable" — flipping back to the normal
    ///         badge art as soon as the seat is reclaimed to the vault (a
    ///         clean holder again) or the forfeit is otherwise settled.
    /// @dev Uses the internal renderer by default; an owner-set external renderer may override.
    ///      A reverting or empty return falls back to internal render. The staticcall is not
    ///      gas-capped, so tokenURI integrity relies on the owner setting a sane renderer.
    ///      Evicted seats always internal-render (the renderer interface carries no
    ///      evicted flag).
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        (uint8 symbolId, uint24 bgRgb, uint24 trimRgb) = seatTraits(tokenId);

        bool seatLocked;
        bool evicted;
        {
            address holder = _owners[tokenId];
            (bool active, , , ) = game.subInfo(holder);
            bool encumbered = (game.mintPackedFor(holder) >>
                BitPackingLib.SEAT_ENCUMBERED_SHIFT) &
                1 !=
                0;
            evicted = encumbered && !active;
            seatLocked = (active || encumbered) && _balances[holder] == 1;
        }

        IIcons32 icons = IIcons32(ContractAddresses.ICONS_32);
        string memory iconPath = icons.data(symbolId);
        uint8 quadrant = symbolId / 8;
        uint8 symbolIdx = symbolId % 8;
        string memory symbolName = icons.symbol(quadrant, symbolIdx);
        if (bytes(symbolName).length == 0) {
            symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));
        }
        bool isCrypto = quadrant == 0;
        string memory backgroundColor = _rgbToHex(bgRgb);
        string memory trimColor = _rgbToHex(trimRgb);

        // Evicted seats always internal-render the forfeit art; otherwise the
        // external renderer runs first and the internal render is the fallback
        // (renderer unset, call fails, or empty return).
        string memory svg;
        address rendererAddr = evicted ? address(0) : renderer;
        if (rendererAddr != address(0)) {
            (bool ok, string memory extSvg) = _tryRenderExternal(
                rendererAddr,
                tokenId,
                symbolId,
                bgRgb,
                trimRgb,
                symbolName,
                iconPath,
                isCrypto,
                seatLocked
            );
            if (ok && bytes(extSvg).length != 0) {
                svg = extSvg;
            }
        }
        if (bytes(svg).length == 0) {
            svg = evicted
                ? _renderEvictedSvg(
                    icons.data(0),
                    seatLocked,
                    backgroundColor,
                    trimColor
                )
                : _renderSvgInternal(
                    iconPath,
                    quadrant,
                    symbolIdx,
                    isCrypto,
                    seatLocked,
                    backgroundColor,
                    trimColor,
                    symbolId == GOLD_DICE6_SYMBOL_ID && trimRgb == GOLD_RGB
                );
        }

        string memory json = string(abi.encodePacked(
            '{"name":"AFK Sub #', Strings.toString(tokenId), ' - ', symbolName,
            '","description":"AFKing seat license. Holding a seat is the sole credential for an afking-mode subscription.",',
            '"attributes":[{"trait_type":"Symbol","value":"', symbolName,
            '"},{"trait_type":"Background","value":"', backgroundColor,
            '"},{"trait_type":"Trim","value":"', trimColor,
            '"},{"trait_type":"Status","value":"',
            evicted
                ? "Evicted - reclaimable"
                : seatLocked
                    ? "Locked - seat in use"
                    : "Transferable",
            '"}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /// @dev The protocol's three-ring badge, one big badge centered on the
    ///      card: outer ring in the trim color, middle #111, inner #fff,
    ///      symbol fitted into the inner circle. Non-crypto symbols are
    ///      inked in the trim color (crypto symbols keep source colors).
    function _renderSvgInternal(
        string memory iconPath,
        uint8 quadrant,
        uint8 symbolIdx,
        bool isCrypto,
        bool seatLocked,
        string memory backgroundColor,
        string memory trimColor,
        bool goldDice6
    ) private pure returns (string memory) {
        uint32 fitSym1e6 = _symbolFitScale(quadrant, symbolIdx);
        uint32 sSym1e6 = uint32((uint256(2) * RING_INNER * fitSym1e6) / ICON_VB);
        // Center the scaled icon: translate by -(viewBox * scale) / 2 on each
        // axis. Icons are stored pre-normalized to the 512 box (each path
        // carries its own wrapper transform), so box-centering is exact.
        int256 t = -(int256(uint256(ICON_VB)) * int256(uint256(sSym1e6))) / 2;

        // Crypto symbols keep their source colors; non-crypto symbols are
        // tinted by ATTRIBUTE inheritance (fill/stroke on the wrapper group),
        // so explicit fills inside an icon — dice pips, cutouts — survive.
        string memory colorOpen = isCrypto
            ? string("'><g style='vector-effect:non-scaling-stroke'>")
            : string(
                abi.encodePacked(
                    "'><g fill='",
                    trimColor,
                    "' stroke='",
                    trimColor,
                    "' style='vector-effect:non-scaling-stroke'>"
                )
            );
        string memory symbolGroup = string(
            abi.encodePacked(
                "<g transform='",
                _mat6(sSym1e6, t, t),
                colorOpen,
                goldDice6 ? GOLD_DICE6_PIP_STYLE : "",
                iconPath,
                "</g></g>"
            )
        );

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'
            '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',
            backgroundColor,
            '" stroke="',
            trimColor,
            '" stroke-width="2.2"/>',
            _rings(trimColor, goldDice6),
            symbolGroup,
            seatLocked ? _lockGlyph() : "",
            "</svg>"
        ));
    }

    /// @dev Evicted-seat forfeit art: the card in the holder's colors carrying
    ///      the WWXRP mark — the XRP glyph (source colors, passed in from
    ///      Icons32 index 0) blown up near-full-card with NO badge rings,
    ///      centered 4 units above center — over a WWXRP wordmark at the card
    ///      foot, plus the padlock while the seat lock traps this seat.
    function _renderEvictedSvg(
        string memory xrpPath,
        bool seatLocked,
        string memory backgroundColor,
        string memory trimColor
    ) private pure returns (string memory) {
        // 76-unit glyph box on the ±50 card, leaving the foot row for the
        // wordmark: scale = 76e6 / 512; center via the box-centering translate,
        // then lift the glyph 4 units.
        uint32 sSym1e6 = uint32((uint256(76) * 1_000_000) / ICON_VB);
        int256 t = -(int256(uint256(ICON_VB)) * int256(uint256(sSym1e6))) / 2;
        string memory glyph = string(
            abi.encodePacked(
                "<g transform='",
                _mat6(sSym1e6, t, t - 4_000_000),
                "'><g style='vector-effect:non-scaling-stroke'>",
                xrpPath,
                "</g></g>"
            )
        );
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'
            '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',
            backgroundColor,
            '" stroke="',
            trimColor,
            '" stroke-width="2.2"/>',
            glyph,
            '<text y="45" text-anchor="middle" font-family="Arial,sans-serif" font-size="11" font-weight="bold" fill="',
            trimColor,
            '">WWXRP</text>',
            seatLocked ? _lockGlyph() : "",
            "</svg>"
        ));
    }

    /// @dev Corner padlock shown while the seat lock binds this token: a
    ///      dark disc with a white padlock at the card's bottom-right,
    ///      outside the outer ring — legible on any player color pick.
    function _lockGlyph() private pure returns (string memory) {
        return
            '<circle cx="36" cy="36" r="11" fill="#111" stroke="#fff" stroke-width="1.5"/>'
            '<path d="M31.5 35 v-3.5 a4.5 4.5 0 0 1 9 0 V35" fill="none" stroke="#fff" stroke-width="2.2"/>'
            '<rect x="29.5" y="34.5" width="13" height="9" rx="1.8" fill="#fff"/>';
    }

    /// @dev Concentric badge rings centered on the card (cx/cy default 0).
    ///      `inverted` swaps the middle and inner fills for the gold Dice 6 only.
    function _rings(string memory outer, bool inverted) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<circle r="',
            Strings.toString(uint256(RING_OUTER)),
            '" fill="',
            outer,
            '"/><circle r="',
            Strings.toString(uint256(RING_MID)),
            '" fill="',
            inverted ? "#fff" : "#111",
            '"/><circle r="',
            Strings.toString(uint256(RING_INNER)),
            '" fill="',
            inverted ? "#111" : "#fff",
            '"/>'
        ));
    }

    function _tryRenderExternal(
        address rendererAddr,
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string memory symbolName,
        string memory iconPath,
        bool isCrypto,
        bool seatLocked
    ) private view returns (bool ok, string memory svg) {
        try ISeatRendererV1(rendererAddr).render(
            tokenId,
            symbolId,
            bgRgb,
            trimRgb,
            symbolName,
            iconPath,
            isCrypto,
            seatLocked,
            _rgbToHex(bgRgb),
            _rgbToHex(trimRgb)
        ) returns (string memory out) {
            if (bytes(out).length == 0) return (false, "");
            return (true, out);
        } catch {
            return (false, "");
        }
    }

    function _rgbToHex(uint24 rgb) private pure returns (string memory) {
        uint8 r = uint8(rgb >> 16);
        uint8 g = uint8(rgb >> 8);
        uint8 b = uint8(rgb);
        bytes memory buf = new bytes(7);
        buf[0] = "#";
        buf[1] = _hexChar(r >> 4);
        buf[2] = _hexChar(r & 0x0F);
        buf[3] = _hexChar(g >> 4);
        buf[4] = _hexChar(g & 0x0F);
        buf[5] = _hexChar(b >> 4);
        buf[6] = _hexChar(b & 0x0F);
        return string(buf);
    }

    function _hexChar(uint8 nibble) private pure returns (bytes1) {
        uint8 v = nibble & 0x0F;
        return bytes1(v + (v < 10 ? 48 : 87));
    }

    /// @dev Per-icon fit inside the inner circle — the original game's
    ///      hand-calibrated table (750000 base × 95% default, per-icon
    ///      adjustments), matched to the icon set in Icons32Data.
    function _symbolFitScale(uint8 quadrant, uint8 symbolIdx) private pure returns (uint32) {
        uint32 f = 712_500; // 95% of the 750000 base fit
        if (quadrant == 1 && symbolIdx == 6) {
            // Sagittarius
            f = uint32((uint256(f) * 722_500) / 1_000_000);
        } else if (quadrant == 2 && symbolIdx == 7) {
            // Ace
            f = uint32((uint256(f) * 130_000) / 100_000);
        } else if (quadrant == 3 && (symbolIdx == 6 || symbolIdx == 7)) {
            // Dice 7 / Dice 8
            f = uint32((uint256(f) * 110_000) / 100_000);
        } else if (quadrant == 0 && symbolIdx == 6) {
            // Ethereum
            f = uint32((uint256(f) * 110_000) / 100_000);
        } else if (quadrant == 2 && symbolIdx == 5) {
            // Heart
            f = uint32((uint256(f) * 95_000) / 100_000);
        } else if (quadrant == 0 && (symbolIdx == 3 || symbolIdx == 7)) {
            // Monero / Bitcoin: full fit
            f = 1_000_000;
        }
        return f;
    }

    function _mat6(
        uint32 s1e6,
        int256 tx1e6,
        int256 ty1e6
    ) private pure returns (string memory) {
        string memory s = _dec6(uint256(s1e6));
        return string(
            abi.encodePacked(
                "matrix(",
                s,
                " 0 0 ",
                s,
                " ",
                _dec6s(tx1e6),
                " ",
                _dec6s(ty1e6),
                ")"
            )
        );
    }

    function _dec6(uint256 x) private pure returns (string memory) {
        uint256 i = x / 1_000_000;
        uint256 f = x % 1_000_000;
        return string(abi.encodePacked(Strings.toString(i), ".", _pad6(uint32(f))));
    }

    function _dec6s(int256 x) private pure returns (string memory) {
        if (x < 0) {
            return string(abi.encodePacked("-", _dec6(uint256(-x))));
        }
        return _dec6(uint256(x));
    }

    function _pad6(uint32 f) private pure returns (string memory) {
        bytes memory b = new bytes(6);
        for (uint256 k; k < 6; ++k) {
            b[5 - k] = bytes1(uint8(48 + (f % 10)));
            f /= 10;
        }
        return string(b);
    }
}
