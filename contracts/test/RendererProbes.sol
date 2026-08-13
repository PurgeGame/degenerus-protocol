// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title RendererProbes
/// @notice Test-only external renderers for DegenerusDeityPass and
///         AFKingSubscriptionToken, covering the three fallback branches their
///         tokenURI distinguishes: a non-empty return (the renderer owns the
///         whole SVG), an empty return, and a revert. Both token contracts treat
///         the latter two as "use the internal renderer", so these probes pin
///         that the gold Dice 6 exception never reaches an owner-selected
///         renderer's output and never suppresses the internal fallback.
/// @dev Not deployed by the protocol; referenced only from tests.

/// @dev Returns a fixed non-empty SVG — the renderer owns the entire output.
contract DeityPassRendererOk {
    string public constant OUT = "<svg id='external-deity'/>";

    function render(
        uint256,
        uint8,
        uint8,
        string calldata,
        string calldata,
        bool,
        string calldata,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return OUT;
    }
}

/// @dev Returns the empty string — tokenURI must fall back to the internal SVG.
contract DeityPassRendererEmpty {
    function render(
        uint256,
        uint8,
        uint8,
        string calldata,
        string calldata,
        bool,
        string calldata,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return "";
    }
}

/// @dev Reverts — tokenURI must catch and fall back to the internal SVG.
contract DeityPassRendererRevert {
    error Nope();

    function render(
        uint256,
        uint8,
        uint8,
        string calldata,
        string calldata,
        bool,
        string calldata,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        revert Nope();
    }
}

/// @dev Returns a fixed non-empty SVG — the renderer owns the entire output.
contract SeatRendererOk {
    string public constant OUT = "<svg id='external-seat'/>";

    function render(
        uint256,
        uint8,
        uint24,
        uint24,
        string calldata,
        string calldata,
        bool,
        bool,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return OUT;
    }
}

/// @dev Returns the empty string — tokenURI must fall back to the internal SVG.
contract SeatRendererEmpty {
    function render(
        uint256,
        uint8,
        uint24,
        uint24,
        string calldata,
        string calldata,
        bool,
        bool,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        return "";
    }
}

/// @dev Reverts — tokenURI must catch and fall back to the internal SVG.
contract SeatRendererRevert {
    error Nope();

    function render(
        uint256,
        uint8,
        uint24,
        uint24,
        string calldata,
        string calldata,
        bool,
        bool,
        string calldata,
        string calldata
    ) external pure returns (string memory) {
        revert Nope();
    }
}
