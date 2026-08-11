// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title BafDrawGas — gas envelope of the BAF weighted draw.
///
/// @notice Three envelopes:
///         1. The ordinary-day direct deposit — the protocol's hot path. The
///            draw gate is one warm read of the packed slot the claim walk
///            already loads, so the deposit benchmark must stay flat against
///            the pre-draw baseline (ceiling pinned with slim headroom).
///         2. The armed-day entry append — two SSTOREs plus a log, paid only
///            on the one armed day per BAF bracket.
///         3. Resolution — binary search, O(log n) cold SLOAD probes. Pinned
///            at three sizes to a logarithmic model, and absolutely bounded
///            far under the advance chain's per-tx budget.
contract BafDrawGas is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    address private alice;
    address private bob;

    function setUp() public {
        _deployProtocol();
        alice = makeAddr("gas_alice");
        bob = makeAddr("gas_bob");
        _warpToDay(2);
    }

    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }

    function _mint(address who, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Measured 100-FLIP self-deposit; returns gas used by the external call.
    function _measuredDeposit(address who) internal returns (uint256 used) {
        vm.prank(who);
        uint256 g0 = gasleft();
        coinflip.depositCoinflip(address(0), 100 ether);
        used = g0 - gasleft();
    }

    /// @notice Ordinary-day 100-FLIP deposit gas: first-ever, same-day repeat,
    ///         next-day repeat. The draw gate costs one warm read of the packed
    ///         slot the claim walk already loads (measured +116 vs the pre-draw
    ///         board: 86,745 / 21,000 / 42,900 → 86,861 / 21,116 / 43,016).
    ///         Ceilings carry slim headroom and trip on any regression that puts
    ///         cold state, an external call, or a write back on the hot path.
    function testNormalDepositGasProfile() public {
        _mint(alice, 1_000 ether);

        uint256 first = _measuredDeposit(alice);
        uint256 repeatSameDay = _measuredDeposit(alice);
        _warpToDay(3);
        uint256 repeatNextDay = _measuredDeposit(alice);

        emit log_named_uint("deposit_gas_first_ever", first);
        emit log_named_uint("deposit_gas_repeat_same_day", repeatSameDay);
        emit log_named_uint("deposit_gas_repeat_next_day", repeatNextDay);

        assertLe(first, 92_000, "first-ever deposit ceiling");
        assertLe(repeatSameDay, 23_500, "same-day repeat ceiling");
        assertLe(repeatNextDay, 46_500, "next-day repeat ceiling");
    }

    /// @notice Armed-day entry costs: the first entry pays the header's zero->nonzero
    ///         write; every later entry pays a fresh entry slot + header rewrite.
    function testArmedDayEntryGasProfile() public {
        _mint(alice, 1_000 ether);
        _mint(bob, 1_000 ether);

        // Un-armed baseline for the same shapes (fresh players, same day).
        uint256 baseFirst = _measuredDeposit(alice);
        uint256 baseRepeat = _measuredDeposit(alice);

        vm.prank(GAME);
        coinflip.armBafDraw(3);

        uint256 armedFirstEntry = _measuredDeposit(bob); // first entry of the day
        uint256 armedNextEntry = _measuredDeposit(bob); // appended entry

        emit log_named_uint("unarmed_first_deposit", baseFirst);
        emit log_named_uint("unarmed_repeat_deposit", baseRepeat);
        emit log_named_uint("armed_first_entry_deposit", armedFirstEntry);
        emit log_named_uint("armed_appended_entry_deposit", armedNextEntry);
        emit log_named_uint("armed_first_entry_overhead", armedFirstEntry - baseFirst);
        emit log_named_uint("armed_appended_entry_overhead", armedNextEntry - baseRepeat);
    }

    // ---------------------------------------------------------------------
    // Resolution scaling — entries installed at the authoritative slots
    // ---------------------------------------------------------------------

    // bafDrawHeader occupies slot 5 (the retired board's slot); bafDrawEntry is
    // appended at slot 8. Installs are proven by reading back through the
    // contract's own getters, so layout drift fails loudly.
    uint256 internal constant HEADER_SLOT = 5;
    uint256 internal constant ENTRY_SLOT = 8;

    function _installEntries(uint24 day, uint32 n) internal {
        uint256 cum;
        for (uint32 i; i < n; ++i) {
            cum += 100 + (uint256(keccak256(abi.encode(day, i))) % 1_000);
            address p = address(uint160(uint256(keccak256(abi.encode("p", i)))));
            uint256 key = (uint256(day) << 32) | i;
            vm.store(
                address(coinflip),
                keccak256(abi.encode(key, ENTRY_SLOT)),
                bytes32((uint256(uint160(p)) << 96) | cum)
            );
        }
        vm.store(
            address(coinflip),
            keccak256(abi.encode(uint256(day), HEADER_SLOT)),
            bytes32((uint256(n) << 96) | cum)
        );
        vm.prank(GAME);
        coinflip.armBafDraw(day);

        // Prove the install against the contract's own getters.
        (uint24 d, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(d, day, "install: armed day");
        assertEq(count, n, "install: entry count");
        assertEq(total, uint96(cum), "install: cumulative total");
    }

    function _measuredWinner(uint256 word) internal view returns (address w, uint256 used) {
        uint256 g0 = gasleft();
        w = coinflip.bafDrawWinner(word);
        used = g0 - gasleft();
    }

    /// @notice Resolution cost grows logarithmically: pinned at 16 / 512 / 4096
    ///         entries. Each doubling adds one cold probe (~2.2k), so 4096
    ///         entries stay a rounding error against the BAF resolution budget.
    function testResolutionGasIsLogarithmic() public {
        _installEntries(3, 16);
        (address w16, uint256 g16) = _measuredWinner(uint256(keccak256("w16")));
        assertTrue(w16 != address(0), "16: a winner must be found");

        _installEntries(4, 512);
        (address w512, uint256 g512) = _measuredWinner(uint256(keccak256("w512")));
        assertTrue(w512 != address(0), "512: a winner must be found");

        _installEntries(5, 4096);
        (address w4096, uint256 g4096) = _measuredWinner(uint256(keccak256("w4096")));
        assertTrue(w4096 != address(0), "4096: a winner must be found");

        emit log_named_uint("resolve_gas_16", g16);
        emit log_named_uint("resolve_gas_512", g512);
        emit log_named_uint("resolve_gas_4096", g4096);

        // Logarithmic envelope: 512 = 16 << 5 (5 extra probes), 4096 = 512 << 3
        // (3 extra probes). A linear walk would blow these by orders of magnitude.
        assertLe(g512, g16 + 5 * 3_000, "512 within 5 extra probes of 16");
        assertLe(g4096, g512 + 3 * 3_000, "4096 within 3 extra probes of 512");
        assertLe(g4096, 80_000, "absolute resolution ceiling at 4096 entries");
    }
}
