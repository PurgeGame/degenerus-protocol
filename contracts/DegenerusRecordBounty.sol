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

import {ContractAddresses} from "./ContractAddresses.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Vault interface for DGVE ownership check (admin render surface auth).
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Optional external renderer interface (v1). Owns the ENTIRE token
///         metadata: a non-empty return IS the tokenURI, verbatim — any URI
///         scheme (data:, ipfs://, https://), name, description, attributes
///         and image included.
/// @dev A reverting or empty external render falls back to the internal
///      metadata; the staticcall is not gas-capped, and the renderer is
///      owner-set and trusted.
interface IRecordBountyRendererV1 {
    function tokenURI(
        uint256 tokenId,
        address holder,
        uint256 mark,
        uint256 sinceDay,
        uint256 daysHeld,
        string calldata recordName,
        string calldata outlineColor,
        string calldata backgroundColor
    ) external view returns (string memory);
}

/// @title DegenerusRecordBounty
/// @notice Soulbound ERC721 trophy for the five all-time record bounties
///         (tokenId = RECORD_KIND_*: 0 flip, 1 degenerette spin, 2 luckbox
///         deposit, 3 ticket buy, 4 dice run). All five mint at deploy to the
///         VAULT; from then on Coinflip force-moves a trophy to whoever
///         ratchets that record's mark — every new mark moves it, clearing the
///         claim bar is not required. Holders can never transfer. Cosmetic only:
///         nothing game-side reads this contract.
contract DegenerusRecordBounty {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotAuthorized();
    error InvalidToken();
    error ZeroAddress();
    error InvalidColor();
    error Soulbound();

    // -------------------------------------------------------------------------
    // Events (ERC721)
    // -------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event RendererUpdated(address indexed previousRenderer, address indexed newRenderer);
    event RenderColorsUpdated(string outlineColor, string backgroundColor);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @dev How many record kinds there are — tokenIds 0..KINDS-1.
    uint256 private constant KINDS = 5;
    /// @dev Current holder per record kind (tokenId 0-4).
    address[5] private _holders;
    /// @dev The standing mark per kind, in that record's unit (flip: FLIP wei;
    ///      spin and luckbox: ETH wei; buy: whole tickets; dice run: score basis
    ///      points, 10,000 = 1x). Display-only mirror of Coinflip's biggest*Ever
    ///      marks.
    uint128[5] private _marks;
    /// @dev Day the CURRENT holder took the trophy (holder clock, not mark
    ///      clock: a holder out-ratcheting their own record keeps their day).
    uint24[5] private _sinceDays;
    mapping(address => uint256) private _balances;

    IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);
    address public renderer;

    string private _outlineColor = "#3f1a82";
    string private _backgroundColor = "#d9d9d9";

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        _;
    }

    constructor() {
        // Every trophy starts with the VAULT — the protocol itself, not a person —
        // and the first player to put a mark on a record takes its trophy from
        // there. An unclaimed record parks with the body that owns the protocol's
        // other unassigned property rather than with its deployer.
        uint24 today = GameTimeLib.currentDayIndex();
        _balances[ContractAddresses.VAULT] = KINDS;
        for (uint256 i; i < KINDS; ++i) {
            _holders[i] = ContractAddresses.VAULT;
            _sinceDays[i] = today;
            emit Transfer(address(0), ContractAddresses.VAULT, i);
        }

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "bounty.degenerus.eth")
            );
            ok;
        }
    }

    // -------------------------------------------------------------------------
    // Coinflip-Only Record Move
    // -------------------------------------------------------------------------

    /// @notice Stamp record `kind`'s new mark and hand its trophy to `to`.
    /// @dev COINFLIP only — called from `_armBigRecord` on every mark ratchet,
    ///      so the trophy tracks the record holder, never the claim. A raw
    ///      ownership write with NO ERC721Receiver callback: the move rides
    ///      inside deposits and bets and must never depend on recipient code.
    ///      A holder beating their own mark keeps their since-day (the days-held
    ///      clock measures the holder, not the mark).
    /// @param kind Record kind = tokenId (0-4).
    /// @param to The player who set the new mark.
    /// @param value The new mark, in the record's unit (uint128-bound by every
    ///        arming path — see Coinflip._armBigRecord).
    function recordSet(uint8 kind, address to, uint256 value) external {
        if (msg.sender != ContractAddresses.COINFLIP) revert NotAuthorized();
        if (kind >= KINDS) revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();

        _marks[kind] = uint128(value);
        address from = _holders[kind];
        if (from != to) {
            unchecked {
                _balances[from] -= 1;
                _balances[to] += 1;
            }
            _holders[kind] = to;
            _sinceDays[kind] = GameTimeLib.currentDayIndex();
            emit Transfer(from, to, kind);
        }
    }

    // -------------------------------------------------------------------------
    // Record Views
    // -------------------------------------------------------------------------

    /// @notice A trophy's live record state.
    /// @param tokenId Record kind (0-4).
    /// @return holder Current record holder.
    /// @return mark The standing mark, in the record's unit.
    /// @return sinceDay Day the current holder took the trophy.
    /// @return daysHeld Whole days the current holder has held it.
    function recordInfo(
        uint256 tokenId
    ) public view returns (address holder, uint128 mark, uint24 sinceDay, uint256 daysHeld) {
        if (tokenId >= KINDS) revert InvalidToken();
        holder = _holders[tokenId];
        mark = _marks[tokenId];
        sinceDay = _sinceDays[tokenId];
        uint24 today = GameTimeLib.currentDayIndex();
        daysHeld = today > sinceDay ? today - sinceDay : 0;
    }

    // -------------------------------------------------------------------------
    // ERC721 Metadata
    // -------------------------------------------------------------------------

    function name() external pure returns (string memory) { return "The BIGGEST Degenerus"; }
    function symbol() external pure returns (string memory) { return "BIGGEST"; }

    /// @notice Set optional external renderer — it owns the entire token
    ///         metadata, not just the art. Set to address(0) to disable.
    /// @param newRenderer Address of the new renderer contract (or zero to use internal).
    function setRenderer(address newRenderer) external onlyOwner {
        address prev = renderer;
        renderer = newRenderer;
        emit RendererUpdated(prev, newRenderer);
    }

    /// @notice Set on-chain render colors.
    /// @param outlineColor Hex color for the card outline, rings and wordmark (e.g. #3f1a82).
    /// @param backgroundColor Hex color for the card background.
    function setRenderColors(
        string calldata outlineColor,
        string calldata backgroundColor
    ) external onlyOwner {
        if (!_isHexColor(outlineColor) || !_isHexColor(backgroundColor)) {
            revert InvalidColor();
        }
        _outlineColor = outlineColor;
        _backgroundColor = backgroundColor;
        emit RenderColorsUpdated(outlineColor, backgroundColor);
    }

    /// @notice Read active render colors.
    function renderColors() external view returns (string memory outlineColor, string memory backgroundColor) {
        return (_outlineColor, _backgroundColor);
    }

    /// @notice On-chain metadata: the record's name, standing mark (in its own
    ///         unit) and the current holder's days-held count, over the default
    ///         Degenerus badge art.
    /// @dev An owner-set external renderer owns the WHOLE metadata: a non-empty
    ///      return is this function's result verbatim. The internal JSON+SVG
    ///      renders only when the renderer is unset, the call fails, or it
    ///      returns empty (fallback). The staticcall is not gas-capped, so
    ///      tokenURI integrity relies on the owner setting a sane renderer.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        (address holder, uint128 mark, uint24 sinceDay, uint256 daysHeld) = recordInfo(tokenId);
        string memory recordName = _recordName(tokenId);

        address rendererAddr = renderer;
        if (rendererAddr != address(0)) {
            (bool ok, string memory extUri) = _tryRenderExternal(
                rendererAddr,
                tokenId,
                holder,
                mark,
                sinceDay,
                daysHeld,
                recordName
            );
            if (ok && bytes(extUri).length != 0) {
                return extUri;
            }
        }

        string memory svg = _renderSvgInternal(tokenId);
        string memory json = string(abi.encodePacked(
            '{"name":"', recordName,
            '","description":"A trophy certifying that the holder is one of the biggest degenerates on Earth.",',
            '"attributes":[{"trait_type":"Record","value":"', recordName,
            '"},{"trait_type":"Record Size","value":"', _formatMark(tokenId, mark),
            '"},{"display_type":"number","trait_type":"Days Held","value":', Strings.toString(daysHeld),
            '}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /// @dev Record name per kind, matching Coinflip's RECORD_KIND_* order and
    ///      the website's record titles.
    function _recordName(uint256 tokenId) private pure returns (string memory) {
        if (tokenId == 0) return "The Biggest Flip";
        if (tokenId == 1) return "The Biggest Degenerette";
        if (tokenId == 2) return "The Biggest Luckbox";
        if (tokenId == 3) return "The Biggest Pack Ripped";
        return "The Biggest Dice Run";
    }

    /// @dev All-caps card label per kind (the website's record-rail labels).
    function _recordLabel(uint256 tokenId) private pure returns (string memory) {
        if (tokenId == 0) return "BIGGEST FLIP";
        if (tokenId == 1) return "BIGGEST DEGENERETTE";
        if (tokenId == 2) return "BIGGEST LUCKBOX";
        if (tokenId == 3) return "BIGGEST PACK RIPPED";
        return "BIGGEST DICE RUN";
    }

    /// @dev The mark in display units: flip in whole FLIP (records sit at or
    ///      above the 200k-FLIP floor, so wei dust is noise), the two ETH-wei
    ///      records with 4 decimals, the buy record as its raw ticket count, and
    ///      the dice run as the multiple its score basis points name.
    function _formatMark(uint256 tokenId, uint128 mark) private pure returns (string memory) {
        if (tokenId == 0) {
            return string(abi.encodePacked(Strings.toString(uint256(mark) / 1 ether), " FLIP"));
        }
        if (tokenId == 3) {
            return string(abi.encodePacked(Strings.toString(uint256(mark)), " tickets"));
        }
        if (tokenId == 4) {
            bytes memory d = new bytes(2);
            uint256 frac2 = (uint256(mark) % 10_000) / 100;
            d[1] = bytes1(uint8(48 + (frac2 % 10)));
            d[0] = bytes1(uint8(48 + (frac2 / 10)));
            return string(abi.encodePacked(Strings.toString(uint256(mark) / 10_000), ".", d, "x"));
        }
        uint256 whole = uint256(mark) / 1 ether;
        uint256 frac4 = (uint256(mark) % 1 ether) / 1e14;
        bytes memory f = new bytes(4);
        for (uint256 k; k < 4; ++k) {
            f[3 - k] = bytes1(uint8(48 + (frac4 % 10)));
            frac4 /= 10;
        }
        return string(abi.encodePacked(Strings.toString(whole), ".", f, " ETH"));
    }

    /// @dev Default art: the protocol card carrying one big badge — outer ring
    ///      in the outline color, middle #111, inner #fff — with a bold "D"
    ///      monogram in the inner circle, the record's label at the card foot
    ///      and the DEGENERUS wordmark under it.
    function _renderSvgInternal(uint256 tokenId) private view returns (string memory) {
        string memory outline = _outlineColor;
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-51 -51 102 102">'
            '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',
            _backgroundColor,
            '" stroke="',
            outline,
            '" stroke-width="2.2"/>'
            '<circle cy="-5" r="34" fill="',
            outline,
            '"/><circle cy="-5" r="26" fill="#111"/><circle cy="-5" r="21" fill="#fff"/>'
            '<text y="5.5" text-anchor="middle" font-family="Arial,sans-serif" font-size="30" font-weight="bold" fill="',
            outline,
            '">D</text>'
            '<text y="38" text-anchor="middle" font-family="Arial,sans-serif" font-size="7" font-weight="bold" fill="#111">',
            _recordLabel(tokenId),
            '</text>'
            '<text y="47" text-anchor="middle" font-family="Arial,sans-serif" font-size="8" font-weight="bold" fill="',
            outline,
            '">DEGENERUS</text>'
            "</svg>"
        ));
    }

    function _tryRenderExternal(
        address rendererAddr,
        uint256 tokenId,
        address holder,
        uint256 mark,
        uint256 sinceDay,
        uint256 daysHeld,
        string memory recordName
    ) private view returns (bool ok, string memory uri) {
        try IRecordBountyRendererV1(rendererAddr).tokenURI(
            tokenId,
            holder,
            mark,
            sinceDay,
            daysHeld,
            recordName,
            _outlineColor,
            _backgroundColor
        ) returns (string memory out) {
            if (bytes(out).length == 0) return (false, "");
            return (true, out);
        } catch {
            return (false, "");
        }
    }

    function _isHexColor(string memory c) private pure returns (bool) {
        bytes memory b = bytes(c);
        if (b.length != 7 || b[0] != "#") return false;
        for (uint256 i = 1; i < 7; ++i) {
            bytes1 ch = b[i];
            bool digit = ch >= "0" && ch <= "9";
            bool lower = ch >= "a" && ch <= "f";
            bool upper = ch >= "A" && ch <= "F";
            if (!(digit || lower || upper)) return false;
        }
        return true;
    }

    // -------------------------------------------------------------------------
    // ERC165
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x80ac58cd  // IERC721
            || id == 0x5b5e139f  // IERC721Metadata
            || id == 0x01ffc9a7; // IERC165
    }

    // -------------------------------------------------------------------------
    // ERC721 Views
    // -------------------------------------------------------------------------

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) external view returns (address ownerAddr) {
        if (tokenId >= KINDS) revert InvalidToken();
        ownerAddr = _holders[tokenId];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (tokenId >= KINDS) revert InvalidToken();
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    // -------------------------------------------------------------------------
    // ERC721 Mutations (soulbound — all transfers blocked)
    // -------------------------------------------------------------------------

    function approve(address, uint256) external pure {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) external pure {
        revert Soulbound();
    }

    function transferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert Soulbound();
    }
}
