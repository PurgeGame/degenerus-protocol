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

/**
 * @title AFKing Subscription Token
 * @author Burnie Degenerus
 * @notice The afking seat: starting an afking-mode subscription on the game
 *         burns one seat held by the subscribing account's payee. An ERC721
 *         collection with fully on-chain SVG art. A seat is MINTED to its
 *         holder (no claim step): buying a pass mints one game-side, and the
 *         vault mints more once the free tranche is gone. Art starts at a
 *         deterministic default and every holder may restyle it — symbol
 *         (0-31) plus ANY 24-bit RGB background and trim — cosmetic only.
 *
 * @dev SEAT MODEL (one seat per subscription):
 *      - Mints: 2 construction seats — serial 1 to SDGNRS, serial 2 to the
 *        VAULT (default colors); a 1,000-seat FREE tranche minted to pass
 *        buyers when they buy (one per account for life, enforced by the
 *        game's SEAT_CLAIMED latch; a smurf's seat goes to its owner; past
 *        1,000 a pass confers no seat); and vault mints to any recipient via
 *        the vault's owner-gated afkingSeatMint, refused until the free
 *        tranche is gone and allowed only while live seats plus the game's
 *        subscriber-set length stay within SEAT_CAP.
 *      - Burns: the game's subscribe calls consumeSeat when it starts a new
 *        run (never for the exempt VAULT/SDGNRS subscriptions). Changing a
 *        live run burns nothing.
 *      - Every non-exempt subscriber-set entry burned a seat, so the cap on
 *        vault mints also bounds the set the game iterates each day.
 *      - Serials count up and are never reused; totalSupply is the live count.
 *      - Transfers are plain ERC721 and read nothing from the game.
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
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Icons32 data contract interface for SVG path data and symbol names.
interface IIcons32 {
    /// @notice Get the SVG path data for icon at index i.
    /// @param i Icon index (0-31).
    /// @return The icon's SVG path data.
    function data(uint256 i) external view returns (string memory);

    /// @notice Get the human-readable symbol name.
    /// @param quadrant Quadrant index (0-3, 8 symbols each).
    /// @param idx Symbol index within the quadrant (0-7).
    /// @return The symbol's human-readable name.
    function symbol(uint256 quadrant, uint8 idx) external view returns (string memory);
}

/// @dev Game surface consumed by this token: the subscriber-set length for the capped
///      vault mint. Transfers read nothing from the Game.
interface ISeatGameViews {
    /// @notice Length of the Game's AFKing subscriber set (live subs, the two exempt protocol
    ///         subs and tombstones awaiting reclaim), as implemented by DegenerusGame.
    function subscriberSetLength() external view returns (uint256);
}

/// @dev Vault interface for DGVE ownership check (admin surface auth).
interface IDegenerusVaultOwner {
    /// @notice Checks DGVE-majority vault ownership, as implemented by DegenerusVault.
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Optional external renderer interface.
/// @dev A reverting or empty external render falls back to the internal renderer;
///      the staticcall is not gas-capped, and the renderer is owner-set and trusted.
interface ISeatRenderer {
    /// @notice Renders a seat's full SVG/metadata art, as implemented by the owner-set renderer.
    function render(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string calldata symbolName,
        string calldata iconPath,
        bool isCrypto
    ) external view returns (string memory);
}

/// @dev Minimal ERC721 receiver interface for the safe-transfer variants.
interface IERC721Receiver {
    /// @notice Standard ERC721 receiver hook, called on safe transfers to contract recipients.
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

    /// @notice symbolId >= 32 on a restyle
    error InvalidTrait();

    /// @notice Vault mints are refused until all 1,000 free-tranche seats are
    ///         minted
    error FreeTrancheOpen();

    /// @notice A vault mint would take live seats plus the game's subscriber
    ///         set past SEAT_CAP
    error SeatCapReached();

    /// @notice Thrown when a vault mint is not from the vault
    error OnlyVault();

    /// @notice Caller is not the GAME contract
    error OnlyGame();

    /// @notice Safe transfer to a contract that did not accept the token
    error UnsafeRecipient();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    /// @notice ERC721 transfer (from = address(0) for mints, to = address(0) for burns)
    /// @param from Previous holder (zero on mint).
    /// @param to New holder (zero on burn).
    /// @param tokenId The seat's serial.
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @notice ERC721 single-token approval
    /// @param owner The seat's current holder.
    /// @param approved The address approved to transfer it (zero clears the approval).
    /// @param tokenId The seat's serial.
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /// @notice ERC721 operator approval
    /// @param owner The account granting the operator approval.
    /// @param operator The address approved (or unapproved) to manage all of owner's seats.
    /// @param approved True to approve, false to revoke.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    /// @notice Emitted when a seat is minted — on a pass PURCHASE (game-driven) or
    ///         by a vault mint. Art is the deterministic default and is restylable at
    ///         any time via setSeatTraits.
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

    /// @notice The vault minted seats
    /// @param to Seat recipient
    /// @param amount Seats minted in this call
    event VaultSeatsMinted(address indexed to, uint256 amount);

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
    /// @param previousRenderer The renderer being replaced (zero if none was set).
    /// @param newRenderer The renderer now in effect (zero disables the external renderer).
    event RendererUpdated(address indexed previousRenderer, address indexed newRenderer);

    /*+======================================================================+
      |                            CONSTANTS                                 |
      +======================================================================+*/

    /// @notice Free-tranche size: first 1,000 claims by latched-eligible
    ///         pass buyers
    uint256 public constant FREE_TRANCHE = 1000;

    /// @notice A vault mint must leave live seats plus the game's subscriber-set
    ///         length at or below this
    uint256 public constant SEAT_CAP = 2000;

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

    /// @dev Game contract: the subscriber-set length read by the capped vault mint
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

    /// @notice Next serial to mint (serials start at 1, count up and are never reused)
    uint32 public nextSerial;

    /// @notice Free-tranche seats minted so far (of FREE_TRANCHE)
    uint16 public freeClaims;

    /// @dev Live seats: minted minus burned; never above SEAT_CAP.
    uint16 private liveSeats;

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        _;
    }

    /// @notice Mints the two protocol self-subscriber seats and registers this contract's
    ///         ENS reverse name.
    constructor() {
        // The protocol self-subscribers' construction seats: serial 1 to SDGNRS,
        // serial 2 to the VAULT (default colors). Their own subscriptions are exempt
        // from the seat burn. SDGNRS has no transfer surface, so serial 1 never
        // leaves; the vault may transfer serial 2 like any seat it holds.
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

    /// @notice The collection name.
    function name() external pure returns (string memory) { return "AFKing Subscription Token"; }
    /// @notice The collection symbol.
    function symbol() external pure returns (string memory) { return "AFK"; }

    /// @notice Live seats: minted minus burned by subscriptions.
    function totalSupply() external view returns (uint256) {
        return liveSeats;
    }

    /*+======================================================================+
      |                      PASS-PURCHASE MINT FLOW                        |
      +======================================================================+*/

    /// @notice Mint a free-tranche seat directly to a pass purchaser (GAME only).
    /// @dev Called by the game on every pass PURCHASE, so a seat arrives WITHOUT a
    ///      separate claim step. Won and conferred passes never reach here — the seat
    ///      is a perk of paying for a pass, not of receiving one. Traits are seeded
    ///      deterministically from (recipient, serial) and the holder may restyle them at
    ///      any time via `setSeatTraits` — the
    ///      art was always designed to be changeable, so nothing is lost by not choosing
    ///      at mint. No entropy is read: the seed is cosmetic-only and never touches a VRF
    ///      word, so this is outside the RNG-freeze surface entirely.
    ///
    ///      Silent no-op (never a revert) on an exhausted 1,000-seat tranche and on the
    ///      zero address, because this rides inside a purchase and must never brick one.
    ///      Past the tranche a pass simply confers no seat. Every free mint precedes the
    ///      first vault mint, so this path needs no cap check.
    ///
    ///      The one-per-account limit is GAME-side, not here: the caller sets the buying
    ///      account's SEAT_CLAIMED latch before calling and mints only on the transition,
    ///      so this function mints whatever it is handed. The game never calls it for a
    ///      won or conferred pass, including a deity purchase's affiliate reward.
    /// @param to The buying account's payee (its own key, or a smurf's owner)
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

    /// @notice Mint seats straight to a recipient (vault only — reached through the
    ///         vault's owner-gated afkingSeatMint), each with default art the recipient
    ///         may restyle. Refused until the free tranche's 1,000 seats are all out, so
    ///         paid seats never crowd out free ones; then allowed while live seats plus
    ///         `amount` plus the game's subscriber-set length stay within SEAT_CAP. Each
    ///         subscription removed from the set frees one more.
    /// @param to Seat recipient
    /// @param amount Seats to mint
    /// @custom:reverts OnlyVault When caller is not the vault contract
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts FreeTrancheOpen While fewer than 1,000 free seats are out
    /// @custom:reverts SeatCapReached When live seats + amount + the subscriber-set
    ///                 length would pass SEAT_CAP
    function vaultMintSeats(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        if (to == address(0)) revert ZeroAddress();
        if (freeClaims < FREE_TRANCHE) revert FreeTrancheOpen();
        if (uint256(liveSeats) + amount + game.subscriberSetLength() > SEAT_CAP)
            revert SeatCapReached();
        for (uint256 i; i < amount; ) {
            _mintDefaultSeat(to);
            unchecked {
                ++i;
            }
        }
        emit VaultSeatsMinted(to, amount);
    }

    /// @notice Burn seat `seatId` held by `holder` to start a subscription run (GAME only).
    /// @dev The game calls this from subscribe before it writes a new run; `holder` is
    ///      the subscribing account's payee, which the game has already authorized, so no
    ///      ERC721 approval is consulted. Never called for the exempt VAULT/SDGNRS
    ///      subscriptions. Makes no external call. The burned serial is never reminted,
    ///      so its approval and trait lane are left behind unreadable.
    /// @param holder The subscribing account's payee (never the zero address)
    /// @param seatId Seat serial to burn
    /// @custom:reverts OnlyGame When the caller is not the GAME contract
    /// @custom:reverts InvalidToken When `holder` does not hold `seatId`
    function consumeSeat(address holder, uint256 seatId) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (_owners[seatId] != holder) revert InvalidToken();
        unchecked {
            _balances[holder] -= 1;
            liveSeats -= 1;
        }
        delete _owners[seatId];
        emit Transfer(holder, address(0), seatId);
    }

    /// @dev Mint the next serial with packed traits.
    function _mintSeat(
        address to,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) private returns (uint256 tokenId) {
        tokenId = nextSerial;
        unchecked {
            nextSerial = uint32(tokenId + 1);
            liveSeats += 1;
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

    /// @notice Seat count held by `account`.
    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    /// @notice Current holder of seat `tokenId`.
    function ownerOf(uint256 tokenId) public view returns (address ownerAddr) {
        ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0)) revert InvalidToken();
    }

    /// @notice The address approved to transfer seat `tokenId` (zero if none).
    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
        return _tokenApprovals[tokenId];
    }

    /// @notice Whether `operator` is approved to manage all of `ownerAddr`'s seats.
    function isApprovedForAll(
        address ownerAddr,
        address operator
    ) external view returns (bool) {
        return _operatorApprovals[ownerAddr][operator];
    }

    /// @notice Declares support for IERC721, IERC721Metadata and IERC165.
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

    /// @notice Transfer a seat (plain ERC721; reads nothing from the game).
    /// @custom:reverts InvalidToken When the serial is not minted or `from` is not its owner
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts NotAuthorized When caller is neither owner, approved, nor operator
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

    /// @notice On-chain SVG metadata for each live seat: the seat's own art and traits.
    /// @dev Uses the internal renderer by default; an owner-set external renderer may override.
    ///      A reverting or empty return falls back to internal render. The staticcall is not
    ///      gas-capped, so tokenURI integrity relies on the owner setting a sane renderer.
    /// @custom:reverts InvalidToken When the serial is not live (never minted, or burned)
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        (uint8 symbolId, uint24 bgRgb, uint24 trimRgb) = seatTraits(tokenId);

        uint8 symbolIdx = symbolId % 8;
        string memory symbolName = IIcons32(ContractAddresses.ICONS_32).symbol(symbolId / 8, symbolIdx);
        if (bytes(symbolName).length == 0) {
            symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));
        }
        string memory svg = _renderSvg(tokenId, symbolId, bgRgb, trimRgb, symbolName);
        string memory backgroundColor = _rgbToHex(bgRgb);
        string memory trimColor = _rgbToHex(trimRgb);

        string memory json = string(abi.encodePacked(
            '{"name":"AFK Sub #', Strings.toString(tokenId), ' - ', symbolName,
            '","description":"AFKing seat. Starting an afking-mode subscription burns one seat.",',
            '"attributes":[{"trait_type":"Symbol","value":"', symbolName,
            '"},{"trait_type":"Background","value":"', backgroundColor,
            '"},{"trait_type":"Trim","value":"', trimColor,
            '"}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /// @dev The seat's SVG: the external renderer first, the internal render as the
    ///      fallback (renderer unset, call fails, or empty return). Quadrant =
    ///      symbolId / 8; quadrant 0 holds the crypto symbols.
    function _renderSvg(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string memory symbolName
    ) private view returns (string memory svg) {
        string memory iconPath = IIcons32(ContractAddresses.ICONS_32).data(symbolId);
        svg = _tryRenderExternal(tokenId, symbolId, bgRgb, trimRgb, symbolName, iconPath, symbolId < 8);
        if (bytes(svg).length == 0) {
            svg = _renderSvgInternal(
                iconPath,
                symbolId / 8,
                symbolId % 8,
                symbolId < 8,
                _rgbToHex(bgRgb),
                _rgbToHex(trimRgb),
                symbolId == GOLD_DICE6_SYMBOL_ID && trimRgb == GOLD_RGB
            );
        }
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
            "</svg>"
        ));
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

    /// @dev The owner-set renderer's SVG, or empty when no renderer is set or the
    ///      call reverts (an empty return also reads as empty).
    function _tryRenderExternal(
        uint256 tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        string memory symbolName,
        string memory iconPath,
        bool isCrypto
    ) private view returns (string memory svg) {
        address rendererAddr = renderer;
        if (rendererAddr == address(0)) return svg;
        try ISeatRenderer(rendererAddr).render(
            tokenId,
            symbolId,
            bgRgb,
            trimRgb,
            symbolName,
            iconPath,
            isCrypto
        ) returns (string memory out) {
            svg = out;
        } catch {}
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
