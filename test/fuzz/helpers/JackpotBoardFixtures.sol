// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Fixed preimages for exact 24-bit trait-board scenarios. Each pair is the first
/// two positive integers whose H(word, TRAIT_BOARD_TAG) has the requested low bits.
/// The assertion checks the fixture against the domain on every use; no production
/// RNG is mocked or overridden. Variant 1 lets a later draw use a distinct root.
library JackpotBoardFixtures {
    function wordFor(uint8[4] memory colors, uint8[4] memory symbols, bool second)
        internal pure returns (uint256 word)
    {
        uint256 wanted;
        for (uint256 i; i < 4; ++i) wanted |= ((uint256(colors[i]) << 3) | symbols[i]) << (6 * i);
        if (wanted == 0x755345) word = second ? 53543781 : 44331048;
        else if (wanted == 0x75537d) word = second ? 64105863 : 60682928;
        else if (wanted == 0x755f7d) word = second ? 27334177 : 5858498;
        else if (wanted == 0x77df7d) word = second ? 78043909 : 51564454;
        else if (wanted == 0x91b489) word = second ? 17076976 : 7573103;
        else if (wanted == 0xd3beb9) word = second ? 16914956 : 13072686;
        else if (wanted == 0xe38e38) word = second ? 22132194 : 13933070;
        else if (wanted == 0xe79e79) word = second ? 49451987 : 3404655;
        else if (wanted == 0xebaeba) word = second ? 49362453 : 44318912;
        else if (wanted == 0xefbefb) word = second ? 106533157 : 55759364;
        else if (wanted == 0xf3beb9) word = second ? 52744475 : 9078497;
        else if (wanted == 0xf3cf3c) word = second ? 76595118 : 55816479;
        else if (wanted == 0xf7df7d) word = second ? 35209326 : 33523583;
        else if (wanted == 0xfbefbe) word = second ? 47607477 : 19431925;
        else if (wanted == 0xffffff) word = second ? 50598512 : 7179938;
        else revert("unregistered board fixture");
        require(uint256(keccak256(abi.encode(word, keccak256("degenerus.jackpot.trait-board")))) & 0xffffff == wanted,
            "board fixture domain changed");
    }
}
