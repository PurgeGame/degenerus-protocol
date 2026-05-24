// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CrankOpenBoxWorstCaseGas -- GAS-01 open-box worst-case measurement (Phase 319 Plan 02)
///
/// @notice `crankBoxes(maxCount)` (DegenerusGame.sol:1592) walks `boxPlayers[index]` from the
///         self-partitioning cursor and opens each ready box via `try this._crankOpenBox` ->
///         `_openLootBoxFor` -> the SAME `_resolveLootboxCommon` body as the bet path. The per-box
///         reward is FLAT (`CRANK_OPEN_BOX_GAS_UNITS * 0.5 gwei`), so there is no multi-spin
///         amplification inside one box: a single READY, un-opened box that materializes is the
///         per-box maximum by construction (319-GAS-DERIVATION.md §2). A box the RngNotReady (G2,
///         :1603) or already-opened (G4, :1618) guards skip costs only the cheap SLOAD skip, which is
///         strictly less than a real open.
///
///         Per `feedback_gas_worst_case`, this harness ASSERTS the box is queued, RNG-ready, and
///         un-opened (so the materialization actually runs) BEFORE the measurement is trusted, then
///         asserts the measured gas < the REAL mainnet 30M block gas limit. It MEASURES only; Plan 05
///         owns the `CRANK_OPEN_BOX_GAS_UNITS` calibration. The single-box marginal is emitted via
///         `log_named_uint` as the Plan 05 calibration input.
///
/// @dev Live `DeployProtocol` fixture (the crank writes Game storage). Clones the `CrankNonBrick`
///      box-enqueue helper (a real lootbox-mode `game.purchase{value:..}(...DirectEth)` deposit fires
///      the first-deposit `lootboxEthBase == 0` signal -> `enqueueBoxForCrank`, MintModule:999) and the
///      `CrankFaucetResistance` RNG-word inject helper. Test-only: no contracts/*.sol mutated.
contract CrankOpenBoxWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 35; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 35;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 36;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 19;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      test harness; the GAS-01 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev Mirror of the resolve-bet 10-spin worst case measured by CrankResolveBetWorstCaseGas
    ///      (Task 1, 726,944 gas at the same fixture). Used by Test C as a conservative upper bound:
    ///      a single box materialization (~10x cheaper, 319-GAS-DERIVATION.md §2) must sit far below
    ///      this. Treated as a loose ceiling, not an exact equality, since warm/cold state shifts the
    ///      precise number; the structural claim is "single box << 10-spin worst case".
    uint256 internal constant RESOLVE_BET_10SPIN_WORST_CASE_REF_GAS = 726_944;

    uint256 private constant FIXED_WORD = uint256(keccak256("crank_open_box_worst_case_word"));
    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit box

    address private boxOwner;
    address private cranker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        boxOwner = makeAddr("open_box_owner");
        cranker = makeAddr("open_box_cranker");
        vm.deal(boxOwner, 100_000 ether);
        vm.deal(cranker, 100_000 ether);
        vm.deal(address(game), 1_000_000 ether);
    }

    // =========================================================================
    // Test A — single-box materialization worst case (the per-box marginal)
    // =========================================================================

    /// @notice GAS-01 / GAS-06: with exactly one box queued (a real lootbox-mode deposit firing the
    ///         first-deposit enqueue) and the RNG word present at the index, measure `crankBoxes(1)`
    ///         gas -> the per-box marginal that calibrates CRANK_OPEN_BOX_GAS_UNITS. Asserts the box
    ///         is queued, RNG-ready, and un-opened (the worst-case preconditions) BEFORE the
    ///         measurement is trusted; asserts the measured gas < 30M mainnet; asserts (non-vacuity)
    ///         the box actually opened. Tests A/B/C are folded into this one test to share the
    ///         single enqueue + the single bracketed `crankBoxes(1)` measurement.
    function testWorstCaseOpenBoxSingleMaterializationFitsBlockGasLimit() public {
        uint48 index = _activeLootboxIndex();

        // Enqueue exactly one real box (first-deposit signal) then land the index's RNG word.
        _buyBox(boxOwner, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);

        // assert-is-worst-case preconditions (319-GAS-DERIVATION.md §2(c)): the box is queued
        // (first-deposit signal present), RNG-ready (word != 0 so the :1603 gate does NOT skip the
        // whole index), and un-opened (lootboxEthBase != 0 so the materialization actually runs).
        assertGt(_lootboxEthBase(index, boxOwner), 0, "worst case: box is queued + un-opened (first-deposit signal present)");
        assertTrue(_lootboxRngWord(index) != 0, "worst case: index is RNG-ready (word != 0, not the :1603 skip)");

        // Measure opening exactly ONE queued box (the per-box marginal).
        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.crankBoxes(1);
        uint256 gasUsed = gasBefore - gasleft();

        // Non-vacuity (Test B): the box actually opened — its first-deposit signal is zeroed on open,
        // NOT a :1603 wordless-index early-return (which would leave lootboxEthBase intact).
        assertEq(_lootboxEthBase(index, boxOwner), 0, "non-vacuity: the queued box actually opened (signal zeroed)");

        // The per-box marginal fits the REAL mainnet block gas limit.
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: single-box materialization worst case fits under the 30M mainnet block gas limit"
        );

        // Calibration sanity (Test C): the single-box marginal is materially LESS than the resolve-bet
        // 10-spin worst case (a resolve-bet worst case is ~10 box materializations, §2) — confirming
        // CRANK_OPEN_BOX_GAS_UNITS and CRANK_RESOLVE_BET_GAS_UNITS will differ markedly.
        assertLt(
            gasUsed,
            RESOLVE_BET_10SPIN_WORST_CASE_REF_GAS,
            "single-box marginal is materially below the resolve-bet 10-spin worst case (~10x a box)"
        );

        // The calibration input Plan 05 reads from the test log.
        emit log_named_uint("worst_case_open_box_single_materialization_gas", gasUsed);
        emit log_named_uint("resolve_bet_10spin_worst_case_ref_gas", RESOLVE_BET_10SPIN_WORST_CASE_REF_GAS);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Buy a real lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> enqueueBoxForCrank (MintModule:999).
    ///      Mirrors CrankNonBrick._buyBox: tickets + a >= LOOTBOX_MIN DirectEth lootbox slice.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 35).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 36).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Read lootboxRngWordByIndex[index] (slot 36).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read lootboxEthBase[index][who] (slot 19) — the first-deposit signal, zeroed on open.
    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }
}
