// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDeityPassRendererV1} from "./DegenerusDeityPass.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface ICustomizableDeityPass {
    function ownerOf(uint256 tokenId) external view returns (address);
    function renderColors() external view returns (string memory, string memory, string memory);
}

/// @title DeityPassCustomizationRenderer
/// @notice Optional V1 renderer for existing deity passes. All settings are cosmetic.
/// @dev Deploy with the existing pass address, then its Vault owner calls setRenderer.
///      This contract never calls a game mutation or changes collection administration.
contract DeityPassCustomizationRenderer is IDeityPassRendererV1 {
    error InvalidPass();
    error InvalidToken();
    error NotTokenOwner();
    error OnlyPass();
    error InvalidColor();
    error UnsupportedSymbolInk();
    error InvalidGeometry();

    struct Colors {
        string rimColor;
        string badgeBackgroundColor;
        string symbolColor;
        string backgroundColor;
        string outlineColor;
    }

    /// @dev All dimensions are hundredths of an SVG card unit (100 units wide).
    struct Geometry {
        uint16 radius;
        int16 centerX;
        int16 centerY;
    }

    struct Customization {
        Colors colors;
        Geometry geometry;
        uint8 overrideMask;
    }

    event TokenColorsUpdated(uint256 indexed tokenId, Colors overrides, uint8 overrideMask);
    event TokenGeometryUpdated(uint256 indexed tokenId, Geometry geometry, bool overridden);
    event TokenCustomizationCleared(uint256 indexed tokenId);
    /// @dev Emitted by this renderer, NOT by the NFT. Indexers must watch this address.
    event MetadataUpdate(uint256 indexed tokenId);

    uint8 public constant RIM = 1;
    uint8 public constant BADGE_BACKGROUND = 2;
    uint8 public constant SYMBOL = 4;
    uint8 public constant BACKGROUND = 8;
    uint8 public constant OUTLINE = 16;
    uint8 public constant GEOMETRY = 32;

    uint16 private constant MIN_RADIUS = 1200;
    uint16 private constant DEFAULT_RADIUS = 4600;
    // Card edge 50 minus half its 2.2-unit outline = 48.9.
    uint16 private constant INNER_HALF_EXTENT = 4890;
    uint16 private constant INNER_CORNER_RADIUS = 1090;
    uint16 private constant ICON_VB = 512;
    bytes6 private constant GOLD_HEX = "ab8d3f";

    ICustomizableDeityPass public immutable pass;
    mapping(uint256 => Customization) private _customizations;

    constructor(address passAddress) {
        if (passAddress.code.length == 0) revert InvalidPass();
        pass = ICustomizableDeityPass(passAddress);
    }

    modifier onlyTokenOwner(uint256 tokenId) {
        if (_ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        _;
    }

    /// @notice Replace the five color overrides. Empty string inherits that field's default.
    /// @dev No operator approvals are consulted. Crypto tokens must leave symbolColor empty.
    ///      Geometry is unchanged. Omitted/empty fields clear their prior overrides.
    function setTokenColors(uint256 tokenId, Colors calldata colors) external onlyTokenOwner(tokenId) {
        uint8 mask;
        if (_validateColor(colors.rimColor)) mask |= RIM;
        if (_validateColor(colors.badgeBackgroundColor)) mask |= BADGE_BACKGROUND;
        if (_validateColor(colors.symbolColor)) mask |= SYMBOL;
        if (_validateColor(colors.backgroundColor)) mask |= BACKGROUND;
        if (_validateColor(colors.outlineColor)) mask |= OUTLINE;
        if (tokenId < 8 && (mask & SYMBOL) != 0) revert UnsupportedSymbolInk();
        Customization storage c = _customizations[tokenId];
        c.colors = colors;
        c.overrideMask = (c.overrideMask & GEOMETRY) | mask;
        emit TokenColorsUpdated(tokenId, colors, c.overrideMask);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Atomically set radius and both coordinates; enlargement checks the current proposal as a whole.
    function setTokenGeometry(uint256 tokenId, Geometry calldata geometry) external onlyTokenOwner(tokenId) {
        if (!isValidGeometry(geometry.radius, geometry.centerX, geometry.centerY)) revert InvalidGeometry();
        Customization storage c = _customizations[tokenId];
        c.geometry = geometry;
        c.overrideMask |= GEOMETRY;
        emit TokenGeometryUpdated(tokenId, geometry, true);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Clear all five colors while retaining size and position.
    function clearTokenColors(uint256 tokenId) external onlyTokenOwner(tokenId) {
        Customization storage c = _customizations[tokenId];
        delete c.colors;
        c.overrideMask &= GEOMETRY;
        emit TokenColorsUpdated(tokenId, c.colors, c.overrideMask);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Restore default radius and centered position without changing colors.
    function clearTokenGeometry(uint256 tokenId) external onlyTokenOwner(tokenId) {
        Customization storage c = _customizations[tokenId];
        delete c.geometry;
        c.overrideMask &= ~GEOMETRY;
        emit TokenGeometryUpdated(tokenId, Geometry(DEFAULT_RADIUS, 0, 0), false);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Clear every override; future collection color changes are inherited again.
    function clearTokenCustomization(uint256 tokenId) external onlyTokenOwner(tokenId) {
        delete _customizations[tokenId];
        emit TokenCustomizationCleared(tokenId);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Raw overrides. Empty colors inherit; geometry is meaningful only with mask bit 32 set.
    function tokenCustomization(uint256 tokenId) external view returns (Customization memory) {
        _ownerOf(tokenId);
        return _customizations[tokenId];
    }

    /// @notice Effective colors/geometry and override flags; symbolColor is empty for crypto artwork.
    function effectiveTokenStyle(uint256 tokenId)
        external
        view
        returns (Colors memory colors, Geometry memory geometry, uint8 overrideMask)
    {
        _ownerOf(tokenId);
        (string memory outline, string memory background, string memory ink) = pass.renderColors();
        return _effectiveStyle(tokenId, outline, background, ink);
    }

    /// @notice Geometry limits in hundredths of a card unit. Default center is (0,0).
    function geometryBounds()
        external
        pure
        returns (
            uint16 unitsPerSvgUnit,
            uint16 minRadius,
            uint16 maxRadius,
            uint16 defaultRadius,
            uint16 innerHalfExtent,
            uint16 innerCornerRadius
        )
    {
        return (100, MIN_RADIUS, INNER_HALF_EXTENT, DEFAULT_RADIUS, INNER_HALF_EXTENT, INNER_CORNER_RADIUS);
    }

    /// @notice Inclusive bounds for BOTH axes at this radius; every edge/corner combination is safe.
    function positionBounds(uint16 radius) public pure returns (int16 minCenter, int16 maxCenter) {
        if (radius < MIN_RADIUS || radius > INNER_HALF_EXTENT) revert InvalidGeometry();
        maxCenter = int16(INNER_HALF_EXTENT - radius);
        minCenter = -maxCenter;
    }

    /// @dev Because radius >= 12 > the inner corner radius 10.9, these axis bounds
    ///      also suffice at rounded corners. The whole circle fits, not just its center.
    ///      Rings have no stroke; source icon strokes scale with the entire badge.
    function isValidGeometry(uint16 radius, int16 centerX, int16 centerY) public pure returns (bool) {
        if (radius < MIN_RADIUS || radius > INNER_HALF_EXTENT) return false;
        (int16 lo, int16 hi) = positionBounds(radius);
        return centerX >= lo && centerX <= hi && centerY >= lo && centerY <= hi;
    }

    /// @notice Existing V1 hook. Symbol identity/artwork always come from the bound pass.
    function render(
        uint256 tokenId,
        uint8 quadrant,
        uint8 symbolIdx,
        string calldata,
        string calldata iconPath,
        bool isCrypto,
        string calldata outlineColor,
        string calldata backgroundColor,
        string calldata nonCryptoSymbolColor
    ) external view override returns (string memory) {
        if (msg.sender != address(pass)) revert OnlyPass();
        (Colors memory colors, Geometry memory geometry,) =
            _effectiveStyle(tokenId, outlineColor, backgroundColor, nonCryptoSymbolColor);
        // Preserve the legacy gold Dice 6 template from COLLECTION defaults.
        // Holder overrides do not couple the five independent color pickers.
        bool goldDice6 = tokenId == 29 && _isGoldHex(outlineColor) && _isGoldHex(nonCryptoSymbolColor);
        return _renderSvg(iconPath, quadrant, symbolIdx, isCrypto, colors, geometry, goldDice6);
    }

    function _effectiveStyle(uint256 tokenId, string memory outline, string memory background, string memory ink)
        private
        view
        returns (Colors memory colors, Geometry memory geometry, uint8 mask)
    {
        Customization storage c = _customizations[tokenId];
        mask = c.overrideMask;
        colors.rimColor =
            (mask & RIM) != 0 ? c.colors.rimColor : tokenId == 0 ? "#ed0e11" : tokenId == 6 ? "#30d100" : outline;
        colors.badgeBackgroundColor = (mask & BADGE_BACKGROUND) != 0
            ? c.colors.badgeBackgroundColor
            : tokenId == 29 && _isGoldHex(outline) && _isGoldHex(ink) ? "#111111" : "#ffffff";
        colors.symbolColor = tokenId < 8 ? "" : (mask & SYMBOL) != 0 ? c.colors.symbolColor : ink;
        colors.backgroundColor = (mask & BACKGROUND) != 0 ? c.colors.backgroundColor : background;
        colors.outlineColor = (mask & OUTLINE) != 0 ? c.colors.outlineColor : outline;
        geometry = (mask & GEOMETRY) != 0 ? c.geometry : Geometry(DEFAULT_RADIUS, 0, 0);
    }

    function _ownerOf(uint256 tokenId) private view returns (address owner) {
        if (tokenId >= 32) revert InvalidToken();
        owner = pass.ownerOf(tokenId); // Unminted IDs revert with the pass's InvalidToken().
        if (owner == address(0)) revert InvalidToken();
    }

    function _validateColor(string calldata color) private pure returns (bool overridden) {
        if (bytes(color).length == 0) return false;
        if (!_isHexColor(color)) revert InvalidColor();
        return true;
    }

    function _renderSvg(
        string memory iconPath,
        uint8 quadrant,
        uint8 symbolIdx,
        bool isCrypto,
        Colors memory colors,
        Geometry memory geometry,
        bool goldDice6
    ) private pure returns (string memory) {
        uint32 scale = uint32((uint256(56) * _symbolFitScale(quadrant, symbolIdx)) / ICON_VB);
        int256 translation = -(int256(uint256(ICON_VB)) * int256(uint256(scale))) / 2;
        string memory symbolGroup = string.concat(
            "<g transform='",
            _mat6(scale, translation, translation),
            "'>",
            isCrypto ? "<g>" : string.concat("<g fill='", colors.symbolColor, "' stroke='", colors.symbolColor, "'>"),
            goldDice6 ? "<style>#ico circle{fill:#111}</style>" : "",
            iconPath,
            "</g></g>"
        );
        // Scale is floored to 6 decimals, so the rendered radius never exceeds
        // its validated value. Translation is exact. No non-scaling strokes.
        string memory badge = string.concat(
            "<g id='badge' transform='",
            _mat6(
                uint32(uint256(geometry.radius) * 1_000_000 / DEFAULT_RADIUS),
                int256(geometry.centerX) * 10_000,
                int256(geometry.centerY) * 10_000
            ),
            "'><circle r=\"46\" fill=\"",
            colors.rimColor,
            "\"/><circle r=\"35\" fill=\"",
            goldDice6 ? "#fff" : "#111",
            "\"/><circle r=\"28\" fill=\"",
            colors.badgeBackgroundColor,
            "\"/>",
            symbolGroup,
            "</g>"
        );
        // 104-unit viewBox includes the card's full outer stroke (extent 51.1).
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-52 -52 104 104">',
            '<rect x="-50" y="-50" width="100" height="100" rx="12" fill="',
            colors.backgroundColor,
            '" stroke="',
            colors.outlineColor,
            '" stroke-width="2.2"/>',
            badge,
            "</svg>"
        );
    }

    /// @dev True when `c` is the canonical gold #ab8d3f, case-insensitively — the
    ///      setter accepts any of 0-9a-fA-F, so an uppercase pass is still gold.
    function _isGoldHex(string memory c) private pure returns (bool) {
        bytes memory b = bytes(c);
        if (b.length != 7 || b[0] != "#") return false;
        bytes6 got;
        for (uint256 i; i < 6; ++i) {
            bytes1 ch = b[i + 1];
            if (ch >= "A" && ch <= "F") ch = bytes1(uint8(ch) + 32);
            got |= bytes6(ch) >> (i * 8);
        }
        return got == GOLD_HEX;
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

    function _mat6(uint32 s1e6, int256 tx1e6, int256 ty1e6) private pure returns (string memory) {
        string memory s = _dec6(uint256(s1e6));
        return string(abi.encodePacked("matrix(", s, " 0 0 ", s, " ", _dec6s(tx1e6), " ", _dec6s(ty1e6), ")"));
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
