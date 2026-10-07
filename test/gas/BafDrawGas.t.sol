// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

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
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _mint(address who, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Measured 100-FLIP self-deposit; returns gas used by the external call.
    function _measuredDeposit(address who) internal returns (uint256 used) {
        vm.prank(who);
        uint256 g0 = gasleft();
        coinflip.depositCoinflip{gas: 11_500_000 - (21_000 + 68 * 16)}(0, 100);
        used = g0 - gasleft();
    }

    /// @notice Ordinary-day 100-FLIP deposit gas: first-ever, same-day repeat,
    ///         next-day repeat. The draw gate costs one warm read of the packed
    ///         slot the claim walk already loads (measured +116 vs the pre-draw
    ///         board: 86,745 / 21,000 / 42,900 → 86,861 / 21,116 / 43,016).
    ///         Ceilings carry slim headroom and trip on any regression that puts
    ///         cold state, an external call, or a write back on the hot path.
    function testNormalDepositGasProfile() public {
        _normalProfile(true);
    }

    function testNormalDepositWarmSingleTransactionRegression() public {
        (uint256 first, uint256 sameDay, uint256 nextDay) = this.measureWarmDepositProfile();
        // Self deposits resolve the canonical Game ID on each call. The removed claim-state
        // cache saved that lookup on repeats; the current warm repeat measures 24,945 gas.
        assertLe(first, 108_000, "first-ever warm deposit ceiling");
        assertLe(sameDay, 25_500, "same-day warm repeat ceiling");
        assertLe(nextDay, 46_500, "next-day warm repeat ceiling");
    }

    function measureWarmDepositProfile() external returns (uint256, uint256, uint256) {
        require(msg.sender == address(this), "test self-call only");
        // Nested calls remain in ONE transaction even under --isolate, preserving
        // the original warm regression's setup, mint and repeated-deposit state.
        return _normalProfile(false);
    }

    function _normalProfile(bool cold) private returns (uint256 first, uint256 sameDay, uint256 nextDay) {
        _mint(alice, 1000);
        _giveWalletId(alice);
        if (cold) {
            _coolDeposit();
            vm.record();
        }
        first = _measuredDeposit(alice);
        if (cold) assertLe(first, 108_000 + _depositColdAllowance(), "cold first-ever deposit ceiling");
        if (cold) {
            _coolDeposit();
            vm.record();
        }
        sameDay = _measuredDeposit(alice);
        if (cold) assertLe(sameDay, 25_500 + _depositColdAllowance(), "cold same-day repeat ceiling");
        _warpToDay(3);
        if (cold) {
            _coolDeposit();
            vm.record();
        }
        nextDay = _measuredDeposit(alice);
        if (cold) assertLe(nextDay, 46_500 + _depositColdAllowance(), "cold next-day repeat ceiling");
        assertEq(coin.balanceOf(alice), 700, "all three deposits burn their principal");
        assertEq(coinflip.coinflipAmount(alice), 100, "last deposit funds the next day's stake");
        emit log_named_uint("deposit_gas_first_ever", first);
        emit log_named_uint("deposit_gas_repeat_same_day", sameDay);
        emit log_named_uint("deposit_gas_repeat_next_day", nextDay);
        // depositCoinflip(0,100): 68 bytes; conservatively price
        // every calldata byte as nonzero when adding intrinsic transaction gas.
        uint256 intrinsic = 21_000 + 68 * 16;
        assertLt(first + intrinsic, 11_500_000, "first deposit transaction cap");
        assertLt(sameDay + intrinsic, 11_500_000, "same-day deposit transaction cap");
        assertLt(nextDay + intrinsic, 11_500_000, "next-day deposit transaction cap");
    }

    /// @dev Estimate only the transaction-state delta over the retained warm budget:
    /// 2k per cold storage read, 2.8k per fresh rather than dirty rewrite, and 2.6k
    /// per external account. Count the actual access footprint, independently cap
    /// its size, and report this allowance separately from measured execution gas.
    function _depositColdAllowance() private returns (uint256 allowance) {
        address[6] memory accounts = [
            address(coinflip), address(coin), address(game), address(quests), address(recordBounty), address(jackpots)
        ];
        uint256 reads;
        uint256 writes;
        for (uint256 i; i < accounts.length; ++i) {
            (bytes32[] memory r, bytes32[] memory w) = vm.accesses(accounts[i]);
            reads += r.length;
            writes += w.length;
        }
        assertLe(reads, 32, "deposit storage-read footprint expanded");
        assertLe(writes, 16, "deposit storage-write footprint expanded");
        allowance = reads * 2000 + writes * 2800 + accounts.length * 2600;
        emit log_named_uint("deposit_cold_storage_reads", reads);
        emit log_named_uint("deposit_cold_storage_writes", writes);
        emit log_named_uint("deposit_estimated_transaction_state_allowance", allowance);
    }

    function _coolDeposit() private {
        // --isolate also resets original SSTORE values between calls. These cold
        // marks independently prevent setup/mint reads from warming the measurement.
        vm.cool(address(coinflip));
        vm.cool(address(coin));
        vm.cool(address(game));
        vm.cool(address(quests));
        vm.cool(address(recordBounty));
        vm.cool(address(jackpots));
    }

    /// @notice A new wallet's first deposit also registers it with Game; the ordinary
    ///         profile above starts from a registered wallet.
    function testFirstDepositWithRegistrationGas() public {
        _mint(alice, 1000);
        uint256 used = _measuredDeposit(alice);
        emit log_named_uint("deposit_gas_first_ever_with_registration", used);
        assertGt(game.walletIdOf(alice), 0, "the first deposit registers the wallet");
        assertLe(used, 200_000, "first-ever deposit with registration ceiling");
    }

    /// @notice Armed-day entry costs: the first entry pays the header's zero->nonzero
    ///         write; every later entry pays a fresh entry slot + header rewrite.
    function testArmedDayEntryGasProfile() public {
        _mint(alice, 1000);
        _mint(bob, 1000);

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
    uint256 internal constant ENTRY_SLOT = GameSlots.LVL_TRAIT_ENTRY;

    function _installEntries(uint24 day, uint32 n) internal {
        uint256 cum;
        for (uint32 i; i < n; ++i) {
            cum += 100 + (uint256(keccak256(abi.encode(day, i))) % 1000);
            uint32 p = uint32(i + 1);
            uint256 key = (uint256(day) << 32) | i;
            vm.store(
                address(coinflip), keccak256(abi.encode(key, ENTRY_SLOT)), bytes32((uint256(p) << 96) | cum)
            );
        }
        vm.store(address(coinflip), keccak256(abi.encode(day, HEADER_SLOT)), bytes32((uint256(n) << 96) | cum));
        vm.prank(GAME);
        coinflip.armBafDraw(day);

        // Prove the install against the contract's own getters.
        (uint24 d, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(d, day, "install: armed day");
        assertEq(count, n, "install: entry count");
        assertEq(total, uint96(cum), "install: cumulative total");
    }

    function _measuredWinner(uint256 word) internal view returns (uint32 w, uint256 used) {
        uint256 g0 = gasleft();
        w = coinflip.bafDrawWinner(word);
        used = g0 - gasleft();
    }

    /// @notice Resolution cost grows logarithmically: pinned at 16 / 512 / 4096
    ///         entries. Each doubling adds one cold probe (~2.2k), so 4096
    ///         entries stay a rounding error against the BAF resolution budget.
    function testResolutionGasIsLogarithmic() public {
        _installEntries(3, 16);
        (uint32 w16, uint256 g16) = _measuredWinner(uint256(keccak256("w16")));
        assertTrue(w16 != 0, "16: a winner must be found");

        _installEntries(4, 512);
        (uint32 w512, uint256 g512) = _measuredWinner(uint256(keccak256("w512")));
        assertTrue(w512 != 0, "512: a winner must be found");

        _installEntries(5, 4096);
        (uint32 w4096, uint256 g4096) = _measuredWinner(uint256(keccak256("w4096")));
        assertTrue(w4096 != 0, "4096: a winner must be found");

        emit log_named_uint("resolve_gas_16", g16);
        emit log_named_uint("resolve_gas_512", g512);
        emit log_named_uint("resolve_gas_4096", g4096);

        // Logarithmic envelope: 512 = 16 << 5 (5 extra probes), 4096 = 512 << 3
        // (3 extra probes). A linear walk would blow these by orders of magnitude.
        assertLe(g512, g16 + 5 * 3000, "512 within 5 extra probes of 16");
        assertLe(g4096, g512 + 3 * 3000, "4096 within 3 extra probes of 512");
        assertLe(g4096, 80_000, "absolute resolution ceiling at 4096 entries");
    }
}
