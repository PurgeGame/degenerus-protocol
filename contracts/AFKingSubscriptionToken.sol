// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title AFKing Subscription Token
 * @author Burnie Degenerus
 * @notice The afking seat license: holding at least 1 seat is the sole
 *         credential for an afking-mode subscription on the game. A
 *         2,000-serial ERC721 collection with fully on-chain SVG art —
 *         each claimer picks their seat's symbol (0-31) plus ANY 24-bit
 *         RGB background and trim color, cosmetic only (the game reads
 *         nothing but balanceOf).
 *
 * @dev SEAT MODEL (sub <=> seat):
 *      - Fixed 2,000 serials, minted only through three bounded tranches:
 *        2 permanent construction seats — serial 1 to SDGNRS, serial 2 to
 *        the VAULT (default colors; neither has an ERC721-out path, so both
 *        protocol self-subscribers hold their seats forever) — a 1,000-seat
 *        FREE tranche claimed by pass buyers (the game latches lifetime
 *        eligibility on pass acquisition; first 1,000 claims win), and a
 *        998-seat VAULT tranche: the vault holds a mint ALLOWANCE (never
 *        further pre-minted tokens) and grants claim rights via its
 *        owner-gated afkingGrant — locked until the free tranche's 1,000
 *        are fully claimed, so paid seats can never crowd out free ones.
 *        2 + 1,000 + 998 = 2,000: the tranche accounting IS the supply cap
 *        (MAX_SERIAL is a fail-loud backstop).
 *      - The game gates subscribe on balanceOf >= 1. Ownership is checked
 *        ONLY there; the seat lock below blocks an active subscriber's
 *        last-seat transfer until they unsubscribe (or are evicted).
 *
 * @dev SEAT LOCK (the only nonstandard ERC721 transfer behavior):
 *      Whenever a transfer takes a sender's balance to exactly 0, it
 *      STATICCALLs the game's subInfo view and reverts SeatInUse while the
 *      sender has an ACTIVE afking subscription. The seat is the credential
 *      (sub <=> seat), so an active subscriber cannot part with their last
 *      seat — they manually unsubscribe (or get evicted) first, and then
 *      the seat is free to sell. Multi-seat holders and plain holders are
 *      never blocked; a self-transfer nets to a nonzero balance and never
 *      triggers the check. The game call is read-only — mints cannot cross
 *      to zero, and there is no burn path.
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

/// @dev Game views consumed by this token: subInfo backs the seat lock
///      (only `active` — the first return — is read: true while the holder
///      has a live afking subscription); mintPackedFor backs the free-claim
///      eligibility check (the SEAT_CLAIMED bit is the lifetime latch the
///      whale module sets on every pass acquisition).
interface ISeatGameViews {
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

    /// @notice Thrown when a transfer would empty an active subscriber's
    ///         balance — unsubscribe (or be evicted) before selling the seat
    error SeatInUse();

    /// @notice Caller has no seat to claim: not latched eligible game-side,
    ///         free tranche exhausted or already used, and no vault grant
    error NotEligible();

    /// @notice Vault grants are locked until all 1,000 free-tranche seats
    ///         are claimed
    error FreeTrancheOpen();

    /// @notice Grant would exceed the vault's 998-seat allowance
    error GrantExceedsTranche();

    /// @notice Thrown when a claim-rights grant is not from the vault
    error OnlyVault();

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

    /// @notice A seat was claimed with its buyer-chosen traits
    /// @param owner Claimer (and initial owner) of the seat
    /// @param tokenId Serial minted (1-2000)
    /// @param symbolId Chosen icon (0-31)
    /// @param bgRgb Chosen 24-bit background color
    /// @param trimRgb Chosen 24-bit trim color
    /// @param freeTranche True for a free-tranche claim, false for a vault-granted claim
    event SeatClaimed(
        address indexed owner,
        uint256 indexed tokenId,
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb,
        bool freeTranche
    );

    /// @notice The vault granted seat claim rights from its 998-seat allowance
    /// @param to Grantee who may now claimSeat
    /// @param amount Claim rights granted
    /// @param granted Lifetime total granted after this call (<= 998)
    event VaultSeatsGranted(address indexed to, uint256 amount, uint256 granted);

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

    /*+======================================================================+
      |                          WIRED CONTRACTS                             |
      +======================================================================+*/

    /// @dev Game contract: seat-lock subInfo view + free-claim eligibility
    ///      latch (mintPackedFor)
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

    /// @notice True once an address has used its one-per-address-lifetime
    ///         free-tranche claim (the game-side eligibility latch stays set
    ///         forever; this is the claimed half of eligible-not-yet-claimed)
    mapping(address => bool) public seatClaimed;

    /// @notice Outstanding vault-granted claim rights per address
    mapping(address => uint256) public vaultGrants;

    /// @notice Optional external renderer (address(0) = internal only)
    address public renderer;

    /// @notice Next serial to mint (serials are 1-2000; monotonic, no burn)
    uint16 public nextSerial;

    /// @notice Free-tranche seats claimed so far (of FREE_TRANCHE)
    uint16 public freeClaims;

    /// @notice Vault claim rights granted lifetime (of VAULT_TRANCHE)
    uint16 public vaultGranted;

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        _;
    }

    constructor() {
        // The protocol self-subscribers' permanent seats: serial 1 to SDGNRS,
        // serial 2 to the VAULT (default colors). Neither has an ERC721-out
        // path — the vault sells claim RIGHTS (vaultGrant), never tokens — so
        // both hold real seats forever and the game's coin gate and the seat
        // lock need no protocol special cases.
        nextSerial = 1;
        _mintSeat(ContractAddresses.SDGNRS, 0, DEFAULT_BG, DEFAULT_TRIM);
        _mintSeat(ContractAddresses.VAULT, 0, DEFAULT_BG, DEFAULT_TRIM);
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

    /// @notice Claim a seat with chosen traits. Free tranche first: an
    ///         address the game latched eligible (any pass acquisition —
    ///         whale/lazy/deity purchase, whale-pass claim, or a deity
    ///         purchase's conferred affiliate pass; one latch per
    ///         address, lifetime) claims free while fewer than 1,000 free
    ///         seats are out and its own free claim is unused. Otherwise a
    ///         vault-granted claim right is consumed.
    /// @param symbolId Icon for the seat's on-chain art (0-31), cosmetic only
    /// @param bgRgb Any 24-bit RGB card background (e.g. 0xff8800), cosmetic only
    /// @param trimRgb Any 24-bit RGB card trim (outline stroke), cosmetic only
    /// @return tokenId Serial minted to the caller
    /// @custom:reverts InvalidTrait When symbolId >= 32
    /// @custom:reverts NotEligible When no free claim is available to the
    ///                 caller and it holds no vault grant
    function claimSeat(
        uint8 symbolId,
        uint24 bgRgb,
        uint24 trimRgb
    ) external returns (uint256 tokenId) {
        if (symbolId >= 32) revert InvalidTrait();

        uint256 free = freeClaims;
        if (
            free < FREE_TRANCHE &&
            !seatClaimed[msg.sender] &&
            (game.mintPackedFor(msg.sender) >>
                BitPackingLib.SEAT_CLAIMED_SHIFT) &
                1 !=
            0
        ) {
            seatClaimed[msg.sender] = true;
            unchecked {
                freeClaims = uint16(free + 1);
            }
            tokenId = _mintSeat(msg.sender, symbolId, bgRgb, trimRgb);
            emit SeatClaimed(msg.sender, tokenId, symbolId, bgRgb, trimRgb, true);
        } else {
            uint256 grants = vaultGrants[msg.sender];
            if (grants == 0) revert NotEligible();
            unchecked {
                vaultGrants[msg.sender] = grants - 1;
            }
            tokenId = _mintSeat(msg.sender, symbolId, bgRgb, trimRgb);
            emit SeatClaimed(msg.sender, tokenId, symbolId, bgRgb, trimRgb, false);
        }
    }

    /// @notice Grant seat claim rights from the vault's 998-seat allowance
    ///         (vault only — reached through the vault's owner-gated
    ///         afkingGrant). Grantees mint via claimSeat with their own
    ///         traits. Locked until the free tranche's 1,000 seats are all
    ///         claimed, so paid seats can never crowd out free ones.
    /// @param to Grantee address
    /// @param amount Claim rights to grant
    /// @custom:reverts OnlyVault When caller is not the vault contract
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts FreeTrancheOpen While fewer than 1,000 free seats are claimed
    /// @custom:reverts GrantExceedsTranche When lifetime grants would pass 998
    function vaultGrant(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        if (to == address(0)) revert ZeroAddress();
        if (freeClaims < FREE_TRANCHE) revert FreeTrancheOpen();
        uint256 granted = uint256(vaultGranted) + amount;
        if (granted > VAULT_TRANCHE) revert GrantExceedsTranche();
        vaultGranted = uint16(granted);
        vaultGrants[to] += amount;
        emit VaultSeatsGranted(to, amount, granted);
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
    ///         empties an active subscriber's balance reverts SeatInUse
    ///         (unsubscribe or be evicted first; the cancel tombstone reads
    ///         inactive immediately, so the seat sells in the very next tx).
    /// @custom:reverts InvalidToken When the serial is not minted or `from` is not its owner
    /// @custom:reverts ZeroAddress When to is address(0)
    /// @custom:reverts NotAuthorized When caller is neither owner, approved, nor operator
    /// @custom:reverts SeatInUse When this transfer would empty the balance of
    ///                 an active subscriber
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
        // check, so it can never trigger. The game call is read-only.
        if (_balances[from] == 0) {
            (bool active, , , ) = game.subInfo(from);
            if (active) revert SeatInUse();
        }
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

    /// @notice On-chain SVG metadata for each seat. LIVE lock state: a seat
    ///         is "Locked" while its holder has an active afking subscription
    ///         and this is their only seat (the seat lock would block its
    ///         transfer); it renders a corner padlock and a Status attribute.
    ///         Metadata is dynamic — it flips back to "Transferable" the
    ///         moment the holder unsubscribes, is evicted, or gains a second
    ///         seat.
    /// @dev Uses the internal renderer by default; an owner-set external renderer may override.
    ///      A reverting or empty return falls back to internal render. The staticcall is not
    ///      gas-capped, so tokenURI integrity relies on the owner setting a sane renderer.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        (uint8 symbolId, uint24 bgRgb, uint24 trimRgb) = seatTraits(tokenId);

        bool seatLocked;
        {
            address holder = _owners[tokenId];
            (bool active, , , ) = game.subInfo(holder);
            seatLocked = active && _balances[holder] == 1;
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

        // External renderer first; the internal render runs only when the
        // renderer is unset, the call fails, or it returns empty (fallback).
        string memory svg;
        address rendererAddr = renderer;
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
            svg = _renderSvgInternal(
                iconPath,
                quadrant,
                symbolIdx,
                isCrypto,
                seatLocked,
                backgroundColor,
                trimColor
            );
        }

        string memory json = string(abi.encodePacked(
            '{"name":"AFK Sub #', Strings.toString(tokenId), ' - ', symbolName,
            '","description":"AFKing seat license. Holding a seat is the sole credential for an afking-mode subscription.",',
            '"attributes":[{"trait_type":"Symbol","value":"', symbolName,
            '"},{"trait_type":"Background","value":"', backgroundColor,
            '"},{"trait_type":"Trim","value":"', trimColor,
            '"},{"trait_type":"Status","value":"',
            seatLocked ? "Locked - seat in use" : "Transferable",
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
        string memory trimColor
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
            _rings(trimColor),
            symbolGroup,
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
    function _rings(string memory outer) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<circle r="',
            Strings.toString(uint256(RING_OUTER)),
            '" fill="',
            outer,
            '"/><circle r="',
            Strings.toString(uint256(RING_MID)),
            '" fill="#111"/><circle r="',
            Strings.toString(uint256(RING_INNER)),
            '" fill="#fff"/>'
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
