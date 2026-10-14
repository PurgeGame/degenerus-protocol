// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title ForkPins -- the single source of truth for the mainnet-fork suite.
/// @notice scripts/lib/patchForFork.js parses these constants (name = literal;) to patch
///         ContractAddresses.sol, so the compiled protocol and the fork fixture can never disagree:
///         the fixture reverts if the build was patched for a different block or dependency set.
///         Every value below was read from mainnet at FORK_BLOCK:
///           - STETH: Lido stETH proxy (symbol "stETH", Lido contract version 4 = Lido v3).
///           - LINK: the ERC-677 LINK token (symbol "LINK").
///           - VRF_COORDINATOR: Chainlink VRF v2.5 coordinator. Its LINK() is LINK, its
///             LINK_NATIVE_FEED() is LINK_ETH_FEED, s_config() = (minConfirmations 3, maxGasLimit
///             2.5M, ...), MAX_NUM_WORDS 500, MAX_REQUEST_CONFIRMATIONS 200.
///           - LINK_ETH_FEED: Chainlink "LINK / ETH" aggregator proxy, 18 decimals.
///           - VRF_KEY_HASH: the coordinator's registered 500 gwei lane
///             (s_provingKeys(VRF_KEY_HASH) = (exists true, maxGas 500 gwei)).
///         FORK_BLOCK was chosen ~2 minutes after a LINK/ETH round so the feed reads fresh
///         (updatedAt 1792018259, 96 s old) and stays inside its 1-day staleness window for the
///         intra-day steps the suite takes.
library ForkPins {
    uint256 internal constant FORK_BLOCK = 26193851;
    uint256 internal constant FORK_TIMESTAMP = 1792018355;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant VRF_COORDINATOR = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    address internal constant LINK_ETH_FEED = 0xDC530D9457755926550b59e8ECcdaE7624181557;
    bytes32 internal constant VRF_KEY_HASH = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;

    /// @dev Lido v3's Accounting contract (LidoLocator.accounting() at FORK_BLOCK): the only caller
    ///      Lido.processClStateUpdate accepts. The oracle report's consensus-layer balance update is
    ///      replayed through it to simulate a positive rebase.
    address internal constant LIDO_ACCOUNTING = 0x23ED611be0e1a820978875C0122F92260804cdDf;
}
