// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @dev Fixed preimages for exact 24-bit trait-board scenarios. Each pair is the first
/// two positive integers whose H(uint256(72), word) has the requested low bits.
/// The assertion checks the fixture against the domain on every use; no production
/// RNG is mocked or overridden. Variant 1 lets a later draw use a distinct root.
library JackpotBoardFixtures {
    function wordFor(uint8[4] memory colors, uint8[4] memory symbols, bool second)
        internal pure returns (uint256 word)
    {
        uint256 wanted;
        for (uint256 i; i < 4; ++i) wanted |= ((uint256(colors[i]) << 3) | symbols[i]) << (6 * i);
        if (wanted == 0x755345) word = second ? 27166945 : 18951641;
        else if (wanted == 0x75537d) word = second ? 15697704 : 13600967;
        else if (wanted == 0x755f7d) word = second ? 9410402 : 6157171;
        else if (wanted == 0x77df7d) word = second ? 26424790 : 21979202;
        else if (wanted == 0x91b489) word = second ? 85693364 : 6161265;
        else if (wanted == 0xd3beb9) word = second ? 9237097 : 8709469;
        else if (wanted == 0xe38e38) word = second ? 115094363 : 27831323;
        else if (wanted == 0xe79e79) word = second ? 27743950 : 7788382;
        else if (wanted == 0xebaeba) word = second ? 23112019 : 21493549;
        else if (wanted == 0xefbefb) word = second ? 46349275 : 10792618;
        else if (wanted == 0xf3beb9) word = second ? 19376837 : 2556849;
        else if (wanted == 0xf3cf3c) word = second ? 58241170 : 49654184;
        else if (wanted == 0xf7df7d) word = second ? 15793507 : 5768389;
        else if (wanted == 0xfbefbe) word = second ? 44047714 : 7509117;
        else if (wanted == 0xffffff) word = second ? 67430875 : 56564504;
        else revert("unregistered board fixture");
        require(uint256(keccak256(abi.encode(uint256(72), word))) & 0xffffff == wanted,
            "board fixture domain changed");
    }
}
