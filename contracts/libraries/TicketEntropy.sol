// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Versioned identities for deterministic ticket streams and replay.
library TicketEntropy {
    uint8 internal constant ORDINARY_ZERO = 0x20;
    uint8 internal constant ORDINARY_ONE = 0x21;
    uint8 internal constant FUTURE = 0x22;
    uint8 internal constant FOIL = 0x23;
    uint256 private constant REMAINDER_DOMAIN = uint256(keccak256("DEGENERUS_TICKET_REMAINDER_V2"));

    function identity(uint24 queueKey, uint24 level, uint256 queueIndex, address player)
        internal pure returns (uint256)
    {
        require(queueIndex <= type(uint32).max);
        uint8 domain = queueKey & (1 << 22) != 0 ? FUTURE
            : queueKey & (1 << 23) != 0 ? ORDINARY_ONE : ORDINARY_ZERO;
        return (uint256(domain) << 248) | (uint256(level) << 224)
            | (queueIndex << 192) | (uint256(uint160(player)) << 32);
    }

    function remainder(uint256 stream, uint256 entropy, uint8 fraction) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(REMAINDER_DOMAIN, stream, entropy))) % 100 < fraction;
    }
}
