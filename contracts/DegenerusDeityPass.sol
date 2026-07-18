// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
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

/// @dev Vault interface for DGVE ownership check.
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Optional external renderer interface (v1).
/// @dev A reverting or empty external render falls back to the internal renderer;
///      the staticcall is not gas-capped, and the renderer is owner-set and trusted.
interface IDeityPassRendererV1 {
    function render(
        uint256 tokenId,
        uint8 quadrant,
        uint8 symbolIdx,
        string calldata symbolName,
        string calldata iconPath,
        bool isCrypto,
        string calldata outlineColor,
        string calldata backgroundColor,
        string calldata nonCryptoSymbolColor
    ) external view returns (string memory);
}

/// @title DegenerusDeityPass
/// @notice Soulbound ERC721 for deity passes. 32 tokens max (one per symbol).
///         Transfers are permanently disabled. tokenId = symbolId (0-31).
contract DegenerusDeityPass {
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
    event RenderColorsUpdated(string outlineColor, string backgroundColor, string nonCryptoSymbolColor);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    IDegenerusVaultOwner private constant vault = IDegenerusVaultOwner(ContractAddresses.VAULT);
    address public renderer;

    uint16 private constant ICON_VB = 512;

    /// @dev The three-ring badge radii on the ±50 card: one big badge with
    ///      the ticket renderer's ring ratios (mid = 0.78 × outer, inner =
    ///      0.62 × outer, integer-floored), sized to leave a 4-unit gutter
    ///      inside the card stroke.
    uint32 private constant RING_OUTER = 46;
    uint32 private constant RING_MID = 35;
    uint32 private constant RING_INNER = 28;

    string private _outlineColor = "#3f1a82";
    string private _backgroundColor = "#d9d9d9";
    string private _nonCryptoSymbolColor = "#111111";

    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotAuthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // ERC721 Metadata
    // -------------------------------------------------------------------------

    function name() external pure returns (string memory) { return "Degenerus Deity Pass"; }
    function symbol() external pure returns (string memory) { return "DEITY"; }

    /// @notice Set optional external renderer. Set to address(0) to disable.
    /// @param newRenderer Address of the new renderer contract (or zero to use internal).
    function setRenderer(address newRenderer) external onlyOwner {
        address prev = renderer;
        renderer = newRenderer;
        emit RendererUpdated(prev, newRenderer);
    }

    /// @notice Set on-chain render colors.
    /// @param outlineColor Hex color for the card outline (e.g. #3f1a82).
    /// @param backgroundColor Hex color for the card background.
    /// @param nonCryptoSymbolColor Hex color for non-crypto symbols.
    function setRenderColors(
        string calldata outlineColor,
        string calldata backgroundColor,
        string calldata nonCryptoSymbolColor
    ) external onlyOwner {
        if (!_isHexColor(outlineColor) || !_isHexColor(backgroundColor) || !_isHexColor(nonCryptoSymbolColor)) {
            revert InvalidColor();
        }
        _outlineColor = outlineColor;
        _backgroundColor = backgroundColor;
        _nonCryptoSymbolColor = nonCryptoSymbolColor;
        emit RenderColorsUpdated(outlineColor, backgroundColor, nonCryptoSymbolColor);
    }

    /// @notice Read active render colors.
    function renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor) {
        return (_outlineColor, _backgroundColor, _nonCryptoSymbolColor);
    }

    /// @notice On-chain SVG metadata for each deity pass.
    /// @dev Uses the internal renderer by default; an owner-set external renderer may override.
    ///      A reverting or empty return falls back to internal render. The staticcall is not
    ///      gas-capped, so tokenURI integrity relies on the owner setting a sane renderer.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();

        IIcons32 icons = IIcons32(ContractAddresses.ICONS_32);
        string memory iconPath = icons.data(tokenId);
        uint8 quadrant = uint8(tokenId / 8);
        uint8 symbolIdx = uint8(tokenId % 8);
        string memory symbolName = icons.symbol(quadrant, symbolIdx);
        if (bytes(symbolName).length == 0) {
            symbolName = string(abi.encodePacked("Dice ", Strings.toString(symbolIdx + 1)));
        }
        bool isCrypto = quadrant == 0;

        // External renderer first; the internal render runs only when the
        // renderer is unset, the call fails, or it returns empty (fallback).
        string memory svg;
        address rendererAddr = renderer;
        if (rendererAddr != address(0)) {
            (bool ok, string memory extSvg) = _tryRenderExternal(
                rendererAddr,
                tokenId,
                quadrant,
                symbolIdx,
                symbolName,
                iconPath,
                isCrypto
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
                isCrypto
            );
        }

        string memory json = string(abi.encodePacked(
            '{"name":"Deity Pass #', Strings.toString(tokenId), ' - ', symbolName,
            '","description":"Degenerus Deity Pass. Grants divine authority over the ',
            symbolName, ' symbol.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /// @dev The protocol's three-ring badge, one big badge centered on the
    ///      card: outer ring in the outline color, middle #111, inner #fff,
    ///      the pass's symbol fitted into the inner circle. Crypto symbols
    ///      keep source colors; non-crypto symbols use the settable ink.
    function _renderSvgInternal(
        string memory iconPath,
        uint8 quadrant,
        uint8 symbolIdx,
        bool isCrypto
    ) private view returns (string memory) {
        uint32 fitSym1e6 = _symbolFitScale(quadrant, symbolIdx);
        uint32 sSym1e6 = uint32((uint256(2) * RING_INNER * fitSym1e6) / ICON_VB);
        // Center the scaled icon: translate by -(viewBox * scale) / 2 on each
        // axis. Icons are stored pre-normalized to the 512 box (each path
        // carries its own wrapper transform), so box-centering is exact.
        int256 t = -(int256(uint256(ICON_VB)) * int256(uint256(sSym1e6))) / 2;

        // Crypto symbols keep their source colors; non-crypto symbols are
        // tinted by ATTRIBUTE inheritance (fill/stroke on the wrapper group),
        // so explicit fills inside an icon — dice pips, cutouts — survive.
        string memory colorOpen;
        if (isCrypto) {
            colorOpen = "'><g style='vector-effect:non-scaling-stroke'>";
        } else {
            string memory ncColor = _nonCryptoSymbolColor;
            colorOpen = string(
                abi.encodePacked(
                    "'><g fill='",
                    ncColor,
                    "' stroke='",
                    ncColor,
                    "' style='vector-effect:non-scaling-stroke'>"
                )
            );
        }
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
            _backgroundColor,
            '" stroke="',
            _outlineColor,
            '" stroke-width="2.2"/>',
            _rings(_outlineColor),
            symbolGroup,
            "</svg>"
        ));
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
        uint8 quadrant,
        uint8 symbolIdx,
        string memory symbolName,
        string memory iconPath,
        bool isCrypto
    ) private view returns (bool ok, string memory svg) {
        try IDeityPassRendererV1(rendererAddr).render(
            tokenId,
            quadrant,
            symbolIdx,
            symbolName,
            iconPath,
            isCrypto,
            _outlineColor,
            _backgroundColor,
            _nonCryptoSymbolColor
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
        ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0)) revert InvalidToken();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert InvalidToken();
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

    // -------------------------------------------------------------------------
    // Game-Only Mint
    // -------------------------------------------------------------------------

    /// @notice Mint a deity pass. Only callable by the game contract during purchase.
    /// @param to Recipient address for the minted pass.
    /// @param tokenId Symbol ID to mint (0-31, must not already exist).
    function mint(address to, uint256 tokenId) external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        if (tokenId >= 32) revert InvalidToken();
        if (_owners[tokenId] != address(0)) revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();

        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

}
