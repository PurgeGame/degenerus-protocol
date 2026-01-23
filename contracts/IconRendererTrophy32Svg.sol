// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
+=======================================================================================================+
|                                    IconRendererTrophy32Svg                                            |
|                         SVG Generation Engine for Degenerus Trophy Tokens                             |
+=======================================================================================================+
|                                                                                                       |
|  ARCHITECTURE OVERVIEW                                                                                |
|  ---------------------                                                                                |
|  IconRendererTrophy32Svg generates the actual SVG image content for trophy tokens. It is called       |
|  by IconRendererTrophy32 (the metadata wrapper) and returns raw SVG strings.                          |
|                                                                                                       |
|  +--------------------------------------------------------------------------------------------------+ |
|  |                              RENDERING PIPELINE                                                  | |
|  |                                                                                                  | |
|  |   DegenerusTrophies.tokenURI()                                                                   | |
|  |          |                                                                                       | |
|  |          ▼                                                                                       | |
|  |   IconRendererTrophy32.tokenURI() --- Generates JSON metadata                                   |  |
|  |          |                                                                                       | |
|  |          ▼                                                                                       | |
|  |   IconRendererTrophy32Svg.trophySvg() --- THIS CONTRACT --- Returns raw SVG                     |  |
|  |          |                                                                                       | |
|  |          +-► Icons32Data.data() --- Retrieves symbol path data                                  |  |
|  |          +-► IconColorRegistry --- Resolves color overrides                                     |  |
|  |          +-► TrophySvgAssets --- BAF animation (if applicable)                                  |  |
|  |          +-► DegenerusAffiliate --- Referrer lookup for color cascade                           |  |
|  +--------------------------------------------------------------------------------------------------+ |
|                                                                                                       |
|  +--------------------------------------------------------------------------------------------------+ |
|  |                              TROPHY TYPES & RENDERING                                            | |
|  |                                                                                                  | |
|  |   EXTERMINATOR TROPHY                                                                            | |
|  |   +- Shows the eliminated trait symbol in center ring                                           |  |
|  |   +- Ring color matches the trait's palette color                                               |  |
|  |   +- May be inverted (negative filter) based on game state                                      |  |
|  |   +- Corner glyphs indicate trophy type                                                         |  |
|  |                                                                                                  | |
|  |   AFFILIATE TROPHY                                                                               | |
|  |   +- Shows affiliate badge icon in center                                                       |  |
|  |   +- Default blue ring (palette index 4)                                                        |  |
|  |   +- Custom ring color via setTopAffiliateColor()                                               |  |
|  |   +- No corner glyphs (affiliate-specific styling)                                              |  |
|  |                                                                                                  | |
|  |   BAF TROPHY                                                                                     | |
|  |   +- Shows animated coin flip (from TrophySvgAssets)                                            |  |
|  |   +- Gold ring color (palette index 7)                                                          |  |
|  |   +- 6-second SMIL animation loop                                                               |  |
|  |                                                                                                  | |
|  |   DEITY TROPHY                                                                                   | |
|  |   +- Shows DGNRS burning ETH logo in center                                                     |  |
|  |   +- Silver ring color (palette index 6)                                                        |  |
|  |                                                                                                  | |
|  +--------------------------------------------------------------------------------------------------+ |
|                                                                                                       |
|  +--------------------------------------------------------------------------------------------------+ |
|  |                              SVG STRUCTURE (102x102 viewBox centered at 0,0)                     | |
|  |                                                                                                  | |
|  |   <svg viewBox="-51 -51 102 102">                                                               |  |
|  |     <defs>                                                                                       | |
|  |       <filter id="inv"> --- Color inversion filter for highlighting                             |  |
|  |     </defs>                                                                                      | |
|  |     <rect> --- Outer rounded square (100x100, customizable fill/stroke)                         |  |
|  |     <g> --- Ring group (outer/middle/inner circles)                                             |  |
|  |       <circle fill="ringColor"> --- Outer colored ring                                          |  |
|  |       <circle fill="bandColor"> --- Middle dark band                                            |  |
|  |       <circle fill="coreColor"> --- Inner white core                                            |  |
|  |     </g>                                                                                         | |
|  |     <g clip-path="..."> --- Symbol clipped to inner circle                                      |  |
|  |       <path> --- The actual icon/symbol                                                         |  |
|  |     </g>                                                                                         | |
|  |     <g> --- Corner glyphs (exterminator + deity)                                                |  |
|  |   </svg>                                                                                         | |
|  +--------------------------------------------------------------------------------------------------+ |
|                                                                                                       |
+=======================================================================================================+*/

import "@openzeppelin/contracts/utils/Strings.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import "./interfaces/IconRendererTypes.sol";
import {ITrophySvgAssets} from "./TrophySvgAssets.sol";
import {RendererLibrary} from "./libraries/RendererLibrary.sol";
import {ColorResolver} from "./libraries/ColorResolver.sol";

// -----------------------------------------------------------------------------
// INTERFACE
// -----------------------------------------------------------------------------

/// @title IIconRendererTrophy32Svg
/// @notice Interface for trophy SVG generation
/// @dev Called by IconRendererTrophy32 to generate the image portion of metadata
interface IIconRendererTrophy32Svg {
    /// @notice Parameters for trophy SVG generation
    struct SvgParams {
        uint256 tokenId;           // Trophy token ID
        uint16 exterminatedTrait;  // Trait ID (0-255) or sentinel (0xFFFE/0xFFFA)
        bool isAffiliate;          // True if affiliate trophy type
        bool isBaf;                // True if BAF trophy type
        bool isDeity;              // True if Deity trophy type
        uint24 lvl;                // Game level when trophy was earned
        bool invertFlag;           // Visual inversion flag from game
    }

    /// @notice Generate SVG image for a trophy token
    /// @param params Trophy parameters (tokenId, type, level, etc.)
    /// @return The complete SVG markup string
    function trophySvg(SvgParams calldata params) external view returns (string memory);
}

// -----------------------------------------------------------------------------
// CONTRACT
// -----------------------------------------------------------------------------

/// @title IconRendererTrophy32Svg
/// @notice SVG generation engine for Degenerus trophy tokens
/// @dev Generates SVG images based on trophy type (Exterminator, Affiliate, BAF, Deity)
contract IconRendererTrophy32Svg is IIconRendererTrophy32Svg, ColorResolver {
    using Strings for uint256;

    // ---------------------------------------------------------------------
    // CONSTANTS & WIRING
    // ---------------------------------------------------------------------

    /// @dev Icon path data source
    IIcons32 internal constant icons = IIcons32(ContractAddresses.ICONS_32);

    /// @dev Trophy SVG assets (BAF animation)
    ITrophySvgAssets internal constant assets = ITrophySvgAssets(ContractAddresses.TROPHY_SVG_ASSETS);

    /// @dev Trophy ERC721 contract
    IERC721Lite internal constant trophies = IERC721Lite(ContractAddresses.TROPHIES);

    // ---------------------------------------------------------------------
    // CONSTANTS
    // ---------------------------------------------------------------------

    /// @dev Sentinel value indicating BAF trophy type in trait field
    uint16 private constant BAF_TRAIT_SENTINEL = 0xFFFA;
    uint16 private constant BAF_FLIP_VB = 130;
    uint32 private constant INNER_SQUARE_SIDE = 88;
    uint16 private constant DGNRS_ICON_VB = 300;
    uint32 private constant DGNRS_TROPHY_SCALE_1e6 = 180_000;
    uint8 private constant ETH_SYMBOL_INDEX = 6;
    uint32 private constant ETH_CENTER_FIT_1e6 = 650_000;
    int256 private constant ETH_ICON_CENTER_X_1e6 = 196_868_210;
    int256 private constant ETH_ICON_CENTER_Y_1e6 = 256_076_369;
    int256 private constant ETH_ICON_SHIFT_X_1e6 = -4_058_800;
    int256 private constant ETH_ICON_SHIFT_Y_1e6 = 0;
    uint32 private constant ETH_FLAME_SCALE_1e6 = 233_000;
    int16 private constant ETH_FLAME_X_OFFSET = 7;
    int16 private constant ETH_FLAME_Y_SIDE = 9;
    int16 private constant ETH_FLAME_Y_MID = 14;
    uint8 private constant DEITY_TROPHY_COLOR_IDX = 6;
    string private constant BASE_CORNER_TRANSFORM = "matrix(0.51 0 0 0.51 -6.12 -6.12)";
    string private constant FLAME_CORNER_TRANSFORM = "matrix(0.02810 0 0 0.02810 -12.03 -9.082)";
    uint32 private constant TOP_AFFILIATE_FIT_1e6 = (760_000 * 936) / 1_000;
    int256 private constant VIEWBOX_HEIGHT_1E6 = 120 * 1_000_000;
    int256 private constant TOP_AFFILIATE_SHIFT_DOWN_1E6 = 3_200_000;
    int256 private constant TOP_AFFILIATE_UPWARD_1E6 = (VIEWBOX_HEIGHT_1E6 * 4) / 100; // 4% of total height

    function trophySvg(SvgParams calldata params) external view override returns (string memory) {
        uint256 tokenId = params.tokenId;
        uint16 exterminatedTrait = params.exterminatedTrait;
        bool isAffiliate = params.isAffiliate;
        bool isBaf = params.isBaf;
        bool isDeity = params.isDeity;
        uint24 lvl = params.lvl;

        uint32 innerSide = INNER_SQUARE_SIDE;
        bool isExtermination = !isAffiliate && !isBaf && !isDeity;

        bool isTopAffiliate = isAffiliate && exterminatedTrait == 0xFFFE;
        bool isBafAward = isBaf && exterminatedTrait == BAF_TRAIT_SENTINEL;
        uint8 six = uint8(exterminatedTrait) & 0x3F;
        uint8 dataQ;
        uint8 colIdx;
        uint8 symIdx;
        if (isDeity) {
            dataQ = 0;
            colIdx = DEITY_TROPHY_COLOR_IDX;
            symIdx = 0;
        } else {
            dataQ = uint8(exterminatedTrait) >> 6;
            if (isBafAward) {
                dataQ = 3;
                six = 0x38; // quadrant 3, color idx 7, symbol 0
            }
            colIdx = isTopAffiliate ? 4 : (six >> 3);
            symIdx = isTopAffiliate ? 0 : (six & 0x07);
        }

        string memory ringOuterColor;
        {
            string memory defaultColor = _paletteColor(colIdx, lvl);
            if (isTopAffiliate) {
                string memory custom = registry.topAffiliateColor(ContractAddresses.TROPHIES, tokenId);
                ringOuterColor = bytes(custom).length != 0 ? custom : defaultColor;
            } else {
                ringOuterColor = defaultColor;
            }
        }

        string memory border = _resolveColorSafe(ContractAddresses.TROPHIES, tokenId, 0, ringOuterColor);

        string memory flameColor = _resolveColorSafe(ContractAddresses.TROPHIES, tokenId, 1, "#111");

        uint32 pct2 = registry.trophyOuter(ContractAddresses.TROPHIES, tokenId);
        uint32 rOut2 = (pct2 <= 1) ? 44 : uint32((uint256(innerSide) * pct2) / 2_000_000);
        uint32 rMid2 = uint32((uint256(rOut2) * RendererLibrary.RATIO_MID_1e6) / 1_000_000);
        uint32 rIn2 = uint32((uint256(rOut2) * RendererLibrary.RATIO_IN_1e6) / 1_000_000);
        if (isBafAward) {
            uint32 scale = 690_000;
            int256 center = int256(uint256(BAF_FLIP_VB) * uint256(scale)) / 2;
            int256 adjustX = 4_400_000; // shift right ~4.4px
            int256 adjustY = 2_600_000; // shift down ~2.6px
            int256 offsetX = -center + adjustX;
            int256 offsetY = -center + adjustY;
            string memory anim = string(
                abi.encodePacked("<g transform='", RendererLibrary.mat6(scale, offsetX, offsetY), "'>", assets.bafFlipSymbol(), "</g>")
            );

            return _composeSvg(RendererLibrary.svgHeader(border, _resolveColorSafe(ContractAddresses.TROPHIES, tokenId, 3, "#d9d9d9")), anim, isExtermination);
        }

        string memory symbolGroup;
        if (isDeity) {
            string memory ethPath = icons.data(ETH_SYMBOL_INDEX);
            string memory flamePath = icons.diamond();
            symbolGroup = _ethTrophySymbol(flamePath, ethPath, rIn2);
        } else {
            string memory iconPath;
            uint16 w;
            uint16 h;
            uint256 iconIndex = isTopAffiliate ? 32 : (uint256(dataQ) * 8 + uint256(symIdx));
            iconPath = icons.data(iconIndex);
            w = RendererLibrary.ICON_VB;
            h = RendererLibrary.ICON_VB;
            uint16 m = w > h ? w : h;
            if (m == 0) m = 1;

            uint32 fitSym1e6 = _symbolFitScale(isTopAffiliate, dataQ, symIdx);
            uint32 sSym1e6 = uint32((uint256(2) * rIn2 * fitSym1e6) / m);

            (int256 txm, int256 tyn) = _symbolTranslate(w, h, sSym1e6, isTopAffiliate);

            // Crypto quadrant symbols (dataQ == 0) should render with their native path colors,
            // not the ring color. Others stay tinted to the ring.
            if (dataQ == 0 && !isTopAffiliate) {
                symbolGroup = string(
                    abi.encodePacked(
                        "<g transform='",
                        RendererLibrary.mat6(sSym1e6, txm, tyn),
                        "'><g style='vector-effect:non-scaling-stroke'>",
                        iconPath,
                        "</g></g>"
                    )
                );
            } else {
                bool solidFill = (!isTopAffiliate && dataQ == 0 && (symIdx == 1 || symIdx == 5));
                symbolGroup = string(
                    abi.encodePacked(
                        "<g transform='",
                        RendererLibrary.mat6(sSym1e6, txm, tyn),
                        "'><g fill='",
                        ringOuterColor,
                        "' stroke='",
                        solidFill ? "none" : ringOuterColor,
                        "' style='vector-effect:non-scaling-stroke'>",
                        iconPath,
                        "</g></g>"
                    )
                );
            }
        }

        string memory ringsAndSymbol = string(
            abi.encodePacked(
                RendererLibrary.rings(ringOuterColor, flameColor, _resolveColorSafe(ContractAddresses.TROPHIES, tokenId, 2, "#fff"), rOut2, rMid2, rIn2, 0, 0),
                "<defs><clipPath id='ct2'><circle cx='0' cy='0' r='",
                uint256(rIn2).toString(),
                "'/></clipPath></defs>",
                "<g clip-path='url(#ct2)'>",
                symbolGroup,
                "</g>"
            )
        );

        bool invertTrophy = isExtermination && ((lvl == 90) ? !params.invertFlag : params.invertFlag);
        if (invertTrophy) {
            ringsAndSymbol = string(abi.encodePacked('<g filter="url(#inv)">', ringsAndSymbol, "</g>"));
        }

        bool includeCorners = isExtermination || isDeity;
        return _composeSvg(
            RendererLibrary.svgHeader(
                border,
                _resolveColorSafe(ContractAddresses.TROPHIES, tokenId, 3, "#d9d9d9")
            ),
            ringsAndSymbol,
            includeCorners
        );
    }


    function _cornerGlyph(string memory cornerTransform) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "<g transform='",
                    cornerTransform,
                    "'><path d='M13 21h-5.5l-1.5 7-1.5-7H-1V1h14z'/></g>"
                )
            );
    }

    function _composeSvg(
        string memory head,
        string memory inner,
        bool includeCorners
    ) private pure returns (string memory) {
        string memory corners = includeCorners
            ? string(abi.encodePacked(_cornerGlyph(BASE_CORNER_TRANSFORM), _cornerGlyph(FLAME_CORNER_TRANSFORM)))
            : "";
        return string(abi.encodePacked(head, inner, corners, RendererLibrary.svgFooter()));
    }

    function _dgnrsTrophySymbol(
        string memory fillColor
    ) private pure returns (string memory) {
        uint32 scale1e6 = DGNRS_TROPHY_SCALE_1e6;
        int256 center = (int256(uint256(DGNRS_ICON_VB)) * int256(uint256(scale1e6))) / 2;
        int256 offsetX = -center;
        int256 offsetY = -center;
        return
            string(
                abi.encodePacked(
                    "<g transform='",
                    RendererLibrary.mat6(scale1e6, offsetX, offsetY),
                    "'><path fill='",
                    fillColor,
                    "' d='M252.472,129.074c-35.063,1.018-81.701,5.444-133.099,14.293c-51.4,8.846-62.426-5.467-67.398-21.439c-5.63-18.084,0.212-27.206,0.212-27.206c33.263-5.405,36.17-26.597,35.337-38.658c-3.323,4.165-8.413,6.899-12.634,7.058c-3.024,0.11-12.306-9.346-27.274,5.832c0.834-8.314-3.143-13.805-13.254-16.631C23.987,49.41,16.032,63.42,0.223,49.414c-3.326,44.068,31.594,45.308,31.594,45.308c-14.225,78.259,45.009,118.089,46.028,122.857c1.021,4.759-15.999,9.523-12.938,14.298c3.065,4.76,23.83,3.746,36.088,1.354c59.566,15.655,72.466,18.708,143.647,17.031c57.279-1.369,56.638-51.767,54.944-69.499C296.259,145.907,287.535,128.051,252.472,129.074z'/><ellipse cx='234' cy='132' rx='8' ry='5' fill='#fff'/></g>"
                )
            );
    }

    function _ethTrophySymbol(
        string memory flamePath,
        string memory ethPath,
        uint32 rIn2
    ) private pure returns (string memory) {
        uint32 scale1e6 = _scaleFromInner(rIn2, ETH_CENTER_FIT_1e6);
        int256 txMicro = -(ETH_ICON_CENTER_X_1e6 * int256(uint256(scale1e6))) / 1_000_000 + ETH_ICON_SHIFT_X_1e6;
        int256 tyMicro = -(ETH_ICON_CENTER_Y_1e6 * int256(uint256(scale1e6))) / 1_000_000 + ETH_ICON_SHIFT_Y_1e6;
        return
            string(
                abi.encodePacked(
                    '<defs><clipPath id="ethc2"><circle cx="0" cy="0" r="',
                    uint256(rIn2).toString(),
                    '"/></clipPath></defs>',
                    '<g transform="',
                    RendererLibrary.mat6(scale1e6, txMicro, tyMicro),
                    '"><g style="vector-effect:non-scaling-stroke">',
                    ethPath,
                    "</g></g>",
                    _ethFlame(flamePath, -ETH_FLAME_X_OFFSET, ETH_FLAME_Y_SIDE),
                    _ethFlame(flamePath, 0, ETH_FLAME_Y_MID),
                    _ethFlame(flamePath, ETH_FLAME_X_OFFSET, ETH_FLAME_Y_SIDE)
                )
            );
    }

    function _ethFlame(
        string memory flamePath,
        int16 cx,
        int16 cy
    ) private pure returns (string memory) {
        uint32 scale1e6 = ETH_FLAME_SCALE_1e6;
        int256 txMicro = int256(int32(cx)) * 1_000_000;
        int256 tyMicro = int256(int32(cy)) * 1_000_000;
        return
            string(
                abi.encodePacked(
                    '<g transform="',
                    RendererLibrary.mat6(scale1e6, txMicro, tyMicro),
                    '"><g clip-path="url(#ethc2)">',
                    '<path fill="#ff3300" stroke="none" transform="matrix(0.13 0 0 0.13 -56 -41)" d="',
                    flamePath,
                    '"/></g></g>'
                )
            );
    }

    function _scaleFromInner(
        uint32 rIn2,
        uint32 fit1e6
    ) private pure returns (uint32) {
        return uint32((uint256(2) * rIn2 * fit1e6) / RendererLibrary.ICON_VB);
    }


    function _paletteColor(uint8 idx, uint24 level) private pure returns (string memory) {
        uint24 rgb = _paletteColorRGB(idx, level);
        return RendererLibrary.rgbToHex(rgb);
    }

    function _paletteColorRGB(uint8 idx, uint24 level) private pure returns (uint24) {
        uint24 rgb = RendererLibrary.paletteColorRGB(idx & 0x07);
        int16 delta = RendererLibrary.variantBias(idx & 0x07);
        if ((idx & 0x07) == 5 || idx == 7 || level == 0) {
            return rgb;
        }
        uint8 levelGroup = uint8(((level - 1) % 24) / 8);
        if (levelGroup == 0) {
            return rgb;
        }
        if (levelGroup == 1) {
            delta = delta > 0 ? int16(delta / 2) : int16(-((-delta) / 2));
        }
        return _toneChannel(rgb, delta);
    }

    function _toneChannel(uint24 rgb, int16 delta) private pure returns (uint24) {
        int256 d = int256(delta);
        int256 r = int256(uint256(uint16(rgb >> 16))) + d;
        int256 g = int256(uint256(uint16((rgb >> 8) & 0xff))) + d;
        int256 b = int256(uint256(uint16(rgb & 0xff))) + d;
        if (r < 0) r = 0;
        if (g < 0) g = 0;
        if (b < 0) b = 0;
        if (r > 255) r = delta > 0 ? int256(255) : int256(0);
        if (g > 255) g = delta > 0 ? int256(255) : int256(0);
        if (b > 255) b = delta > 0 ? int256(255) : int256(0);
        return (uint24(uint16(uint256(r))) << 16) | (uint24(uint16(uint256(g))) << 8) | uint24(uint16(uint256(b)));
    }



    function _symbolFitScale(bool isTopAffiliate, uint8 quadrant, uint8 symbolIdx) private pure returns (uint32) {
        if (isTopAffiliate) return TOP_AFFILIATE_FIT_1e6;
        if (quadrant == 0 && (symbolIdx == 1 || symbolIdx == 5)) return 790_000;
        if (quadrant == 2 && (symbolIdx == 1 || symbolIdx == 5)) return 820_000;
        if (quadrant == 1 && symbolIdx == 6) return 820_000;
        if (quadrant == 3 && symbolIdx == 7) return 780_000;
        return 890_000;
    }

    function _symbolTranslate(
        uint16 w,
        uint16 h,
        uint32 sSym1e6,
        bool isTopAffiliate
    ) private pure returns (int256 txm, int256 tyn) {
        int256 scale = int256(uint256(sSym1e6));
        int256 w1e6 = int256(uint256(w)) * scale;
        int256 h1e6 = int256(uint256(h)) * scale;
        txm = -w1e6 / 2;
        tyn = -h1e6 / 2;
        if (isTopAffiliate && h > w) {
            int256 shift = (h1e6 * TOP_AFFILIATE_UPWARD_1E6) / VIEWBOX_HEIGHT_1E6;
            tyn -= shift;
            txm += TOP_AFFILIATE_SHIFT_DOWN_1E6;
        }
    }
}
