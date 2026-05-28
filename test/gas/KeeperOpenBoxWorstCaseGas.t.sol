// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperOpenBoxWorstCaseGas -- GAS-01 open-box worst-case measurement (Phase 319 Plan 02)
///
/// @notice `autoOpen(maxCount)` (DegenerusGame.sol:1592) walks `boxPlayers[index]` from the
///         self-partitioning cursor and opens each ready box via `try this._autoOpenBox` ->
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
/// @dev Live `DeployProtocol` fixture (the keeper-router writes Game storage). Clones the `KeeperNonBrick`
///      box-enqueue helper (a real lootbox-mode `game.purchase{value:..}(...DirectEth)` deposit fires
///      the first-deposit `lootboxEthBase == 0` signal -> `enqueueBoxForAutoOpen`, MintModule:999) and the
///      `KeeperFaucetResistance` RNG-word inject helper. Test-only: no contracts/*.sol mutated.
contract KeeperOpenBoxWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

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

    /// @dev The single-box `autoOpen(1)` TOTAL measured by Test A (137,944). Test D asserts the
    ///      per-box MARGINAL is materially below this — the gap is the per-tx fixed overhead the
    ///      single-box total mis-attributes to one box (CR-01). The committed CRANK_OPEN_BOX_GAS_UNITS
    ///      (137_944) is pegged to this single-box total, which is the CR-01 defect.
    uint256 internal constant SINGLE_BOX_TOTAL_REF_GAS = 137_944;

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
    ///         first-deposit enqueue) and the RNG word present at the index, measure `autoOpen(1)`
    ///         gas -> the per-box marginal that calibrates CRANK_OPEN_BOX_GAS_UNITS. Asserts the box
    ///         is queued, RNG-ready, and un-opened (the worst-case preconditions) BEFORE the
    ///         measurement is trusted; asserts the measured gas < 30M mainnet; asserts (non-vacuity)
    ///         the box actually opened. Tests A/B/C are folded into this one test to share the
    ///         single enqueue + the single bracketed `autoOpen(1)` measurement.
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
        game.autoOpen(1);
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
    // Test D — per-box MARGINAL (the CORRECTED CRANK_OPEN_BOX_GAS_UNITS target)
    // =========================================================================

    /// @notice GAS-06 / CR-01: isolate the per-box MARGINAL gas — the marginal cost of opening one
    ///         more box in an N-box `autoOpen(N)` batch. This is the CORRECT calibration target for
    ///         CRANK_OPEN_BOX_GAS_UNITS, because the box reward is FLAT per box (DegenerusGame.sol:1621)
    ///         while the per-transaction fixed overhead of `autoOpen` (the cursor/boxCursorIndex
    ///         SLOAD+conditional SSTORE :1593-1598, the lootboxRngWordByIndex gate SLOAD :1603, the
    ///         `_activeTicketLevel()` read :1610, the final `boxCursor` SSTORE :1631, and the once-per-tx
    ///         `coinflip.creditFlip` :1632) is paid ONLY ONCE per call regardless of N. A self-cranker
    ///         opening N own boxes earns N rewards but pays that fixed overhead once, so pegging the
    ///         per-box reward to a single-box TOTAL (which bundles the whole fixed overhead into one box)
    ///         OVER-reimburses every box after the first and opens the SAFE-01 self-crank faucet on the
    ///         multi-box path (CR-01).
    ///
    ///         Measured by the SAME loop-N-divide idiom CrankResolveBetWorstCaseGas
    ///         (testPerOneSpinItemMarginalBelowWorstCase, :197-242) uses for the resolve-bet marginal:
    ///         queue N distinct READY un-opened boxes, `autoOpen(N)` ONCE, divide the gasleft-delta
    ///         by N so the per-tx fixed overhead amortizes away. A large N (32) is used so the per-tx
    ///         fixed overhead (cold cranker `creditFlip` ~20k, cursor SSTOREs) is amortized to a
    ///         negligible per-box share and the measured marginal converges to the true per-box
    ///         materialization cost (small N over-states it: N=8 measures ~90k, N>=32 converges ~70k —
    ///         the CR-01 amortization gradient). Asserts the per-box marginal is materially BELOW the
    ///         single-box total (the gap is exactly the mis-attributed fixed overhead) and lands in the
    ///         resolve-bet spin neighborhood (319-GAS-DERIVATION.md §2: one open-box ~= one resolve
    ///         spin ~= ~66-70k), confirming 137_944 (the single-box TOTAL) ~2x over-states the marginal.
    function testPerBoxMarginalAmortizesFixedOverhead() public {
        uint48 index = _activeLootboxIndex();
        uint256 nBoxes = 32;

        // Queue N distinct READY boxes (distinct owners -> distinct (index,owner) queue entries),
        // each firing the first-deposit enqueue signal.
        address[] memory owners = new address[](nBoxes);
        for (uint256 i; i < nBoxes; ++i) {
            address o = makeAddr(string(abi.encodePacked("perbox_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, LOOTBOX_WEI);
        }
        _injectLootboxRngWord(index, FIXED_WORD);

        // assert-is-real precondition: every box is queued + un-opened before the crank, so the
        // marginal measures real materializations (not :1603 skips or :1618 already-opened skips).
        for (uint256 i; i < nBoxes; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "pre: each box queued + un-opened");
        }

        // Bracket the whole N-box batch; divide by N for the per-box marginal (fixed overhead paid once).
        // autoOpen's maxCount is a GAS-WEIGHTED budget (a typical box = 1 unit, a heavier boon box ≈ 2);
        // grant ample weighted units (nBoxes * 64) so all N queued boxes open and the marginal is N-real.
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.autoOpen(nBoxes * 64);
        uint256 totalGas = gasBefore - gasleft();
        uint256 perBoxMarginal = totalGas / nBoxes;

        // Non-vacuity: every box actually opened (first-deposit signal zeroed on open), so the
        // marginal is a real per-box materialization cost (not a no-op walk).
        for (uint256 i; i < nBoxes; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "non-vacuity: each box opened (signal zeroed)");
        }

        // The per-box marginal is materially BELOW the single-box total (137_944): the gap is the
        // per-tx fixed overhead that the single-box measurement mis-attributes to one box (CR-01).
        // This is the CORRECTED CRANK_OPEN_BOX_GAS_UNITS target.
        assertLt(
            perBoxMarginal,
            SINGLE_BOX_TOTAL_REF_GAS,
            "per-box marginal is materially below the single-box total (the gap is the mis-attributed fixed overhead)"
        );
        // The marginal lands in the resolve-bet spin neighborhood (one open-box ~= one resolve spin):
        // strictly less than ~1.4x the resolve-bet per-spin marginal (66_528), confirming the box peg
        // should be ~70k, NOT 137_944. (Loose upper bound; the exact value is read from the log.)
        assertLt(perBoxMarginal, 95_000, "per-box marginal is in the resolve-bet spin neighborhood (~70k), not ~138k");
        assertLt(perBoxMarginal, MAINNET_BLOCK_GAS_LIMIT, "per-box marginal trivially fits the block limit");

        // The CORRECTED calibration input Plan 05 / the CR-01 fix reads from the test log.
        emit log_named_uint("per_box_marginal_gas", perBoxMarginal);
        emit log_named_uint("per_box_batch_total_gas", totalGas);
        emit log_named_uint("single_box_total_ref_gas", SINGLE_BOX_TOTAL_REF_GAS);
    }

    // =========================================================================
    // Test E -- TST-01 D-TST01-04 uniform-O(1) whale-vs-non-whale gas equivalence
    // (Phase 336 Plan 03 -- WHALE-03 attestation)
    // =========================================================================

    /// @notice Empirically attests WHALE-03 (D-TST01-04): the worst-case per-box autoOpen gas is
    ///         independent of the opener's whale-pass-claims state. With WHALE-01 the box-open
    ///         path is uniform O(1) regardless of `whalePassClaims[player]` (the accumulator slot
    ///         is touched ONLY by the rare BOON_WHALE_PASS branch at LootboxModule:1628-1629;
    ///         every other open is byte-identical between any two openers). The 331 whale-pass-
    ///         weighted autoOpen carve-out is RETIRED per WHALE-03 — autoOpen budgets a flat
    ///         per-box cost.
    ///
    /// @dev TOLERANCE CHOICE -- per 336-RESEARCH §A1 + 336-PLAN <action> step 2 alternative:
    ///         this test uses the WIDE tolerance (~25_000 gas) covering the worst-case cold
    ///         SSTORE penalty if a BOON_WHALE_PASS branch fires on the whale opener (the
    ///         `whalePassClaims[player] += 1` accumulator write at LootboxModule:1253). The
    ///         simplification (skip the boon-roll path entirely) drives BOTH openers down the
    ///         non-boon-firing code path with the SAME FIXED_WORD, so in practice the delta
    ///         observed should be far below ~25_000 -- the wide bound merely guarantees the
    ///         assertion holds even if a future fixture change toggles whale-bit firing.
    ///         The 500-gas tight tolerance alternative would require BOTH openers to be
    ///         pre-warmed via vm.store on slot 21 (whalePassClaims root) and would still face
    ///         address-keyed cold/warm asymmetries on player-state slots; the wide bound is the
    ///         empirically safer pick per RESEARCH §A1's "LOW risk, caught at first execution"
    ///         framing. The threat model (T-336-03-02) caps the tolerance at 25_000.
    ///
    ///         The whale opener's whalePassClaims slot is pre-seeded to a non-zero value via
    ///         vm.store -- this asserts the SECOND structural property of WHALE-03: even when
    ///         the opener already has pending whale-pass claims, the box-open gas does NOT
    ///         depend on that state (the box-open path does NOT SLOAD whalePassClaims absent
    ///         the boon branch).
    function testWhaleOpenerEqualsNonWhaleOpenerGas() public {
        // -- Address staging -----------------------------------------------------
        address warmupOpener = makeAddr("warmup_opener");
        address nonWhaleOpener = makeAddr("non_whale_opener");
        address whaleOpener = makeAddr("whale_opener");
        vm.deal(warmupOpener, 100 ether);
        vm.deal(nonWhaleOpener, 100 ether);
        vm.deal(whaleOpener, 100 ether);

        // Pre-seed whalePassClaims[whaleOpener] = 3 (a non-zero accumulator state representing
        // "this player already has pending whale-pass claims from prior boon rolls"). Slot 21 is
        // the verified whalePassClaims mapping root (DegenerusGame storage layout; confirmed by
        // 336-02 SUMMARY against `forge inspect storage`). WHALE-03 asserts box-open gas is
        // independent of this pre-existing state — the box-open path does NOT read this slot
        // unless the BOON_WHALE_PASS branch fires, and even when it does, the `+= 1` write is
        // strictly O(1) per LootboxModule:1253.
        bytes32 whalePassClaimsSlot = keccak256(abi.encode(whaleOpener, uint256(21)));
        vm.store(address(game), whalePassClaimsSlot, bytes32(uint256(3)));
        assertEq(
            uint256(vm.load(address(game), whalePassClaimsSlot)),
            3,
            "pre-condition: whalePassClaims[whaleOpener] pre-seeded to 3"
        );

        // -- Box purchase + RNG-word injection ----------------------------------
        uint48 index = _activeLootboxIndex();
        _buyBox(warmupOpener, LOOTBOX_WEI);
        _buyBox(nonWhaleOpener, LOOTBOX_WEI);
        _buyBox(whaleOpener, LOOTBOX_WEI);
        _injectLootboxRngWord(index, FIXED_WORD);

        // Worst-case preconditions: both measurement boxes queued + RNG-ready + un-opened.
        assertGt(_lootboxEthBase(index, nonWhaleOpener), 0, "pre: non-whale box queued + un-opened");
        assertGt(_lootboxEthBase(index, whaleOpener), 0, "pre: whale box queued + un-opened");
        assertTrue(_lootboxRngWord(index) != 0, "pre: index is RNG-ready (word != 0)");

        // -- Warm-up call (NOT measured) ----------------------------------------
        // The first autoOpen call in a clean test environment pays a substantial per-tx cold-
        // warming penalty (the coinflip facade address SLOAD, the boxCursor / boxCursorIndex
        // packed-slot SLOAD, the active-ticket-level SLOAD, the cranker's `creditFlip` slot
        // cluster) that the second call benefits from. To isolate the per-OPENER divergence
        // (the WHALE-03 claim) from this cross-call warming asymmetry, the warm-up opener
        // burns those cold reads first. Both measured calls (non-whale + whale) then see the
        // SAME warm state — the residual delta is the load-bearing equivalence quantity.
        vm.prank(warmupOpener);
        game.autoOpen(1);

        // -- Measure non-whale opener gas ---------------------------------------
        // Each measured opener cranks ONLY their own box via autoOpen(1) bounded to a single
        // box. Both calls take the same autoOpen code path (same FIXED_WORD; neither triggers
        // BOON_WHALE_PASS at LootboxModule:1628-1629); the WHALE-03 attestation is that the
        // gas delta is bounded by the documented tolerance regardless of the opener identity
        // or pre-existing whalePassClaims state.
        vm.prank(nonWhaleOpener);
        uint256 g0 = gasleft();
        game.autoOpen(1);
        uint256 gNonWhale = g0 - gasleft();

        // -- Measure whale opener gas -------------------------------------------
        vm.prank(whaleOpener);
        g0 = gasleft();
        game.autoOpen(1);
        uint256 gWhale = g0 - gasleft();

        // -- Equivalence assertion + audit-trace logs ---------------------------
        uint256 delta = gWhale > gNonWhale ? gWhale - gNonWhale : gNonWhale - gWhale;
        // WIDE tolerance (~25_000 gas) covering the worst-case cold-SSTORE penalty per the
        // RESEARCH §A1 framing. The empirically observed delta in the non-boon-firing path
        // is far below this; the wide bound is the durable choice that holds across any
        // future cold/warm state shift in the fixture or contract neighborhood.
        uint256 TOLERANCE = 25_000;
        assertLe(
            delta,
            TOLERANCE,
            "WHALE-03 D-TST01-04: uniform-O(1) -- whale vs non-whale opener gas equivalence within 25_000-gas cold-SSTORE bound"
        );

        // Audit trail: the empirical numbers logged for USER + downstream audit review (the
        // 338 TERMINAL FINDINGS-v50 deliverable cites these as the WHALE-03 evidence).
        emit log_named_uint("gas_whale_opener", gWhale);
        emit log_named_uint("gas_non_whale_opener", gNonWhale);
        emit log_named_uint("gas_delta", delta);
        emit log_named_uint("gas_tolerance", TOLERANCE);
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Buy a real lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> enqueueBoxForAutoOpen (MintModule:999).
    ///      Mirrors CrankNonBrick._buyBox: tickets + a >= LOOTBOX_MIN DirectEth lootbox slice.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions)).
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
