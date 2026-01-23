// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IIconRendererRegular32Assets
/// @notice Interface for accessing large SVG fragments for IconRendererRegular32
interface IIconRendererRegular32Assets {
    function orangeKingIcon() external pure returns (string memory);
    function kingGoldIcon(string memory goldHex) external pure returns (string memory);
}

/// @title IconRendererRegular32Assets
/// @notice On-chain storage for large SVG fragments used by IconRendererRegular32
contract IconRendererRegular32Assets is IIconRendererRegular32Assets {
    // Hair variant for the orange King icon (Cards quadrant).
    string private constant ORANGE_KING_ICON = "<g id='ico' transform='translate(-24 -42) scale(1.25)'><g transform='translate(111.6 0) scale(0.57369)'><path d='M 90 165 L 90 290 L 205 290 L 320 290 L 318 1122 L 315 1950 L 203 1950 L 90 1950 L 90 2080 L 90 2210 L 460 2210 L 830 2210 L 830 2080 L 830 1950 L 733 1950 L 635 1950 L 635 1730 L 635 1515 L 749 1367 L 870 1227 L 1240 1950 L 1125 1950 L 1010 1950 L 1010 2080 L 1010 2210 L 1410 2210 L 1810 2210 L 1810 2080 L 1810 1950 L 1705 1950 L 1600 1950 L 1577 1950 L 1458 1690 L 1090 951 L 1227 752 L 1602 290 L 1721 290 L 1810 290 L 1810 165 L 1810 40 L 1410 40 L 1010 40 L 1010 170 L 1010 290 L 1116 290 L 1221 290 L 1199 290 L 644 1049 L 640 672 L 640 290 L 735 290 L 830 290 L 830 165 L 830 40 L 460 40 L 90 40 L 90 165 Z' transform='translate(-35.95489 198.694) scale(0.236721 0.28265)'/><g transform='translate(-138 30) scale(1.1 0.62)'><g transform='scale(0.853333)'><defs><clipPath id='king-hair-clip'><path d='M 539 89 C 530.2 83 509.8 79.7 504 84 C 498.2 88.3 510.5 107.7 504 115 C 497.5 122.3 498 135.2 465 128 C 432 120.8 347.7 73.3 298 63 C 248.3 52.7 152.8 50.2 124 60 C 95.2 69.8 53.8 95.8 41 121 C 28.2 146.2 27.3 219.7 38 240 C 48.7 260.3 68.5 255.2 77 270 C 85.5 284.8 55.7 333.8 66 367 C 76.3 400.2 120.5 434.2 129 459 C 137.5 483.8 129.8 519.2 122 532 C 114.2 544.8 74.2 563.8 78 573 C 81.8 582.2 168.3 587.2 185 577 C 201.7 566.8 221.5 525.3 227 501 C 232.5 476.7 223.5 415 228 391 C 232.5 367 246.3 343.3 264 329 C 281.7 314.7 330.7 301.8 366 300 C 401.3 298.2 470 312.5 500 300 C 530 287.5 561.5 258.2 571 231 C 580.5 203.8 575.2 143.8 571 125 C 566.8 106.2 547.8 95 539 89 Z'/></clipPath></defs><path d='M 539 89 C 530.2 83 509.8 79.7 504 84 C 498.2 88.3 510.5 107.7 504 115 C 497.5 122.3 498 135.2 465 128 C 432 120.8 347.7 73.3 298 63 C 248.3 52.7 152.8 50.2 124 60 C 95.2 69.8 53.8 95.8 41 121 C 28.2 146.2 27.3 219.7 38 240 C 48.7 260.3 68.5 255.2 77 270 C 85.5 284.8 55.7 333.8 66 367 C 76.3 400.2 120.5 434.2 129 459 C 137.5 483.8 129.8 519.2 122 532 C 114.2 544.8 74.2 563.8 78 573 C 81.8 582.2 168.3 587.2 185 577 C 201.7 566.8 221.5 525.3 227 501 C 232.5 476.7 223.5 415 228 391 C 232.5 367 246.3 343.3 264 329 C 281.7 314.7 330.7 301.8 366 300 C 401.3 298.2 470 312.5 500 300 C 530 287.5 561.5 258.2 571 231 C 580.5 203.8 575.2 143.8 571 125 C 566.8 106.2 547.8 95 539 89 Z' fill='#FAD807' stroke='none'/><g clip-path='url(#king-hair-clip)' fill='none' stroke='#000' stroke-width='8' stroke-linecap='round' stroke-linejoin='round'><path d='M 150 135 C 230 85 370 70 520 105'/><path d='M 140 185 C 235 135 380 120 505 150'/><path d='M 145 245 C 250 210 385 205 475 225'/><path d='M 150 300 C 175 355 170 420 140 475'/></g><path d='M 539 89 C 530.2 83 509.8 79.7 504 84 C 498.2 88.3 510.5 107.7 504 115 C 497.5 122.3 498 135.2 465 128 C 432 120.8 347.7 73.3 298 63 C 248.3 52.7 152.8 50.2 124 60 C 95.2 69.8 53.8 95.8 41 121 C 28.2 146.2 27.3 219.7 38 240 C 48.7 260.3 68.5 255.2 77 270 C 85.5 284.8 55.7 333.8 66 367 C 76.3 400.2 120.5 434.2 129 459 C 137.5 483.8 129.8 519.2 122 532 C 114.2 544.8 74.2 563.8 78 573 C 81.8 582.2 168.3 587.2 185 577 C 201.7 566.8 221.5 525.3 227 501 C 232.5 476.7 223.5 415 228 391 C 232.5 367 246.3 343.3 264 329 C 281.7 314.7 330.7 301.8 366 300 C 401.3 298.2 470 312.5 500 300 C 530 287.5 561.5 258.2 571 231 C 580.5 203.8 575.2 143.8 571 125 C 566.8 106.2 547.8 95 539 89 Z' fill='none' stroke='#000' stroke-width='12' stroke-linejoin='round' stroke-linecap='round'/></g></g></g></g>";
    string private constant KING_ICON_OPEN =
        "<g id='ico' transform='translate(-51.3 -42) scale(1.25)'><g transform='translate(111.6 0) scale(0.57369)'>";
    string private constant KING_CROWN_PATH_1 =
        "M512,152.469c0-21.469-17.422-38.875-38.891-38.875c-21.484,0-38.906,17.406-38.906,38.875c0,10.5,4.172,20.016,10.938,27c-26.453,54.781-77.016,73.906-116.203,56.594c-34.906-15.438-47.781-59.563-52.141-93.75c14.234-7.484,23.938-22.391,23.938-39.594C300.734,78.016,280.719,58,256,58c-24.703,0-44.734,20.016-44.734,44.719c0,17.203,9.703,32.109,23.938,39.594c-4.359,34.188-17.234,78.313-52.141,93.75c-39.188,17.313-89.75-1.813-116.203-56.594c6.766-6.984,10.938-16.5,10.938-27c0-21.469-17.422-38.875-38.891-38.875C17.422,113.594,0,131,0,152.469c0,19.781,14.781,36.078,33.875,38.547l44.828,164.078h354.594l44.828-164.078C497.234,188.547,512,172.25,512,152.469z";
    string private constant KING_CROWN_PATH_2 =
        "M455.016,425.063c0,15.984-12.953,28.938-28.953,28.938H85.938C69.953,454,57,441.047,57,425.063v-2.406c0-16,12.953-28.953,28.938-28.953h340.125c16,0,28.953,12.953,28.953,28.953V425.063z";
    string private constant KING_LETTER_PATH =
        "<path d='M 90 165 L 90 290 L 205 290 L 320 290 L 318 1122 L 315 1950 L 203 1950 L 90 1950 L 90 2080 L 90 2210 L 460 2210 L 830 2210 L 830 2080 L 830 1950 L 733 1950 L 635 1950 L 635 1730 L 635 1515 L 749 1367 L 870 1227 L 1240 1950 L 1125 1950 L 1010 1950 L 1010 2080 L 1010 2210 L 1410 2210 L 1810 2210 L 1810 2080 L 1810 1950 L 1705 1950 L 1600 1950 L 1577 1950 L 1458 1690 L 1090 951 L 1227 752 L 1602 290 L 1721 290 L 1810 290 L 1810 165 L 1810 40 L 1410 40 L 1010 40 L 1010 170 L 1010 290 L 1116 290 L 1221 290 L 1199 290 L 644 1049 L 640 672 L 640 290 L 735 290 L 830 290 L 830 165 L 830 40 L 460 40 L 90 40 L 90 165 Z' transform='translate(2.11511 198.694) scale(0.236721 0.28265)'/>";
    string private constant KING_ICON_CLOSE = "</g></g>";

    function orangeKingIcon() external pure override returns (string memory) {
        return ORANGE_KING_ICON;
    }

    function kingGoldIcon(string memory goldHex) external pure override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    KING_ICON_OPEN,
                    "<g transform='translate(16.4 -5.3) scale(0.85 0.45)'><path fill='",
                    goldHex,
                    "' stroke='",
                    goldHex,
                    "' d='",
                    KING_CROWN_PATH_1,
                    "'/><path fill='",
                    goldHex,
                    "' stroke='",
                    goldHex,
                    "' d='",
                    KING_CROWN_PATH_2,
                    "'/></g>",
                    KING_LETTER_PATH,
                    KING_ICON_CLOSE
                )
            );
    }
}
