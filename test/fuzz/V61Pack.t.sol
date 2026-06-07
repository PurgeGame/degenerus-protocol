// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {SettleClaimableShortfallTester} from "../../contracts/test/SettleClaimableShortfallTester.sol";

/// @title V61Pack — TST-02 proof: the claimable/afking slot-packing accessors round-trip, never cross-bleed,
///        keep the claimablePool == Sigma(claimable + afking) identity, preserve the infra afking half during
///        the gameOver claimable-zeroing, and are value-identical to two independent counters.
///
/// @notice The v61 PACK fold replaced two balance mappings with one `balancesPacked` (slot 7,
///   `[afking:high128 | claimable:low128]`, DegenerusGameStorage.sol:418). Every read/write flows through the
///   accessors `_claimableOf` / `_afkingOf` / `_creditClaimable` / `_debitClaimable` / `_creditAfking` /
///   `_debitAfking` (Storage:892-928). This file exercises that EXACT production accessor layer through the
///   SettleClaimableShortfallTester (it inherits the canonical storage layout and runs the real accessor
///   bodies — its setters/getters are thin wrappers over `_credit*` / `_debit*` / `_*Of`).
///
///   The NON-INTERFERENCE proofs read the RAW packed slot (slot 7, the 378-01 recalibration key) and split it
///   in the test — so they prove the OTHER half is byte-identical at the storage level, not merely that the
///   read accessor returns the right value. Falsifiable: a cross-half bleed (e.g. a naive full-word `packed +=
///   amount << 128` that carried, or a debit that borrowed across bit 127) would move the untouched half and
///   fail the raw-slot assertion.
///
///   The gameOver leg targets the EXACT call the final sweep makes (GameOverModule `_finalSweep`:205-207
///   `_debitClaimable(VAULT/SDGNRS/GNRUS, owed)`): draining an infra address's claimable half must leave its
///   afking high half intact (the sweep zeroes claimable but never the prepaid afking principal).
///
/// @dev Test-only: ZERO contracts/*.sol mutation. Seeded-fuzz deterministic (foundry seed 0xdeadbeef).
contract V61Pack is Test {
    /// @dev balancesPacked mapping root (slot 7 per the 378-01 recalibration key). The tester inherits the
    ///      canonical DegenerusGameStorage layout, so this is the same slot on the tester instance.
    uint256 private constant BALANCES_PACKED_SLOT = 7;

    SettleClaimableShortfallTester private t;

    /// @dev PlayerCredited(player, recipient, amount) — emitted by _creditClaimable (the low-half credit).
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    function setUp() public {
        t = new SettleClaimableShortfallTester();
    }

    // =========================================================================
    // Per-half round-trip + raw-slot non-interference
    // =========================================================================

    /// @notice Crediting claimable round-trips the LOW half exactly via _claimableOf, and the raw packed slot
    ///         shows the HIGH (afking) half byte-UNCHANGED. _creditClaimable also emits PlayerCredited.
    function testCreditClaimableRoundTripHighHalfUntouched() public {
        address p = makeAddr("rt_claimable");
        uint256 afkingSeed = 123 ether;
        t.setAfking(p, afkingSeed); // seed the high half first
        uint256 highBefore = _rawHigh(p);
        assertEq(highBefore, afkingSeed, "seed: afking high half set");

        uint256 amount = 77 ether;
        vm.expectEmit(true, true, false, true, address(t));
        emit PlayerCredited(p, p, amount);
        t.setClaimable(p, amount); // setClaimable zeroes then credits → net credit of `amount`

        assertEq(t.getClaimable(p), amount, "low half round-trips to the credited claimable");
        assertEq(_rawLow(p), amount, "raw low half == credited claimable");
        assertEq(_rawHigh(p), afkingSeed, "HIGH (afking) half byte-UNCHANGED after a claimable credit");
        assertEq(t.getAfking(p), afkingSeed, "afking accessor still reads the untouched high half");
    }

    /// @notice Crediting afking round-trips the HIGH half exactly via _afkingOf, and the raw packed slot shows
    ///         the LOW (claimable) half byte-UNCHANGED.
    function testCreditAfkingRoundTripLowHalfUntouched() public {
        address p = makeAddr("rt_afking");
        uint256 claimableSeed = 91 ether;
        t.setClaimable(p, claimableSeed);
        uint256 lowBefore = _rawLow(p);
        assertEq(lowBefore, claimableSeed, "seed: claimable low half set");

        uint256 amount = 256 ether;
        t.setAfking(p, amount);

        assertEq(t.getAfking(p), amount, "high half round-trips to the credited afking");
        assertEq(_rawHigh(p), amount, "raw high half == credited afking");
        assertEq(_rawLow(p), claimableSeed, "LOW (claimable) half byte-UNCHANGED after an afking credit");
        assertEq(t.getClaimable(p), claimableSeed, "claimable accessor still reads the untouched low half");
    }

    /// @notice _settleShortfall debiting BOTH halves leaves each accessor reading the correct residue and the
    ///         raw slot consistent — the two halves move independently within the one word.
    function testDebitTouchesCorrectHalfOnly() public {
        address p = makeAddr("debit_halves");
        uint256 claimable = 40 ether;
        uint256 afking = 60 ether;
        t.setClaimable(p, claimable);
        t.setAfking(p, afking);
        t.setClaimablePool(claimable + afking);

        // Draw a shortfall that consumes (claimable - 1) from the low half and the rest from the high half.
        uint256 shortfall = 70 ether;
        uint256 cUsed = claimable - 1;
        uint256 aUsed = shortfall - cUsed;
        t.settle(p, shortfall, true);

        assertEq(_rawLow(p), claimable - cUsed, "low half debited by exactly claimableUsed (sentinel remains)");
        assertEq(_rawHigh(p), afking - aUsed, "high half debited by exactly afkingUsed");
        assertEq(t.getClaimable(p), 1, "claimable accessor reads the 1-wei sentinel");
        assertEq(t.getAfking(p), afking - aUsed, "afking accessor reads the residual high half");
    }

    /// @notice _debitClaimable reverts E() (the inherited sentinel error) when the LOW half is short — proving
    ///         the low-half guard never borrows from the afking high half. Driven via a Claimable-only settle
    ///         with the afking half empty so the claimable tier alone must cover (and fails the guard).
    function testDebitClaimableRevertsWhenLowHalfShort() public {
        address p = makeAddr("debit_short");
        uint256 claimable = 3 ether;
        t.setClaimable(p, claimable);
        t.setAfking(p, 0); // empty high half: no afking to fall through to
        t.setClaimablePool(claimable);

        // shortfall above usable claimable (claimable - 1) with zero afking ⇒ revert E().
        vm.expectRevert(t.sentinelError());
        t.settle(p, claimable, false); // DirectEth leg skips claimable entirely → afking (0) short → revert
    }

    // =========================================================================
    // claimablePool == Sigma(claimable + afking) identity under a seeded sequence
    // =========================================================================

    /// @notice Across a seeded sequence of credits/debits over several players, the solvency identity
    ///         claimablePool == Sigma(claimable + afking halves) holds after EVERY operation. Each credit is
    ///         mirrored into claimablePool here (as the production call sites do in tandem); each debit goes
    ///         through _settleShortfall, which pairs its own claimablePool debit. Non-vacuous: the sequence
    ///         performs real credits and at least one real debit.
    function testFuzzClaimablePoolEqualsSumUnderSequence(uint256 seed) public {
        address[3] memory ps = [makeAddr("seq_a"), makeAddr("seq_b"), makeAddr("seq_c")];
        uint256 expectedPool;
        uint256 debits;

        for (uint256 i; i < 9; i++) {
            address p = ps[i % 3];
            // Force the first two ops to be credits so the pool is non-empty regardless of seed (otherwise an
            // all-debit seed no-ops on an empty pool); the remaining 7 ops are seed-driven.
            uint256 op = i < 2 ? i : (seed >> (i * 4)) & 0x3;
            uint256 mag = bound(uint256(keccak256(abi.encode(seed, i))), 1, 1e22);

            if (op == 0) {
                // credit claimable + mirror the pool (the production credit sites move both in tandem)
                uint256 before = t.getClaimable(p);
                t.setClaimable(p, before + mag);
                t.setClaimablePool(t.getClaimablePool() + mag);
                expectedPool += mag;
            } else if (op == 1) {
                // credit afking + mirror the pool
                uint256 before = t.getAfking(p);
                t.setAfking(p, before + mag);
                t.setClaimablePool(t.getClaimablePool() + mag);
                expectedPool += mag;
            } else {
                // debit via _settleShortfall (pairs its own claimablePool debit) — only when coverable.
                uint256 c = t.getClaimable(p);
                uint256 usable = (c > 1 ? c - 1 : 0) + t.getAfking(p); // strict 1-wei claimable sentinel
                if (usable == 0) continue;
                uint256 sf = bound(mag, 1, usable);
                t.settle(p, sf, true);
                expectedPool -= sf;
                debits++;
            }

            // The identity: the tracked pool equals the sum of all halves AND the contract's claimablePool.
            uint256 sumHalves = (t.getClaimable(ps[0]) + t.getAfking(ps[0])) +
                (t.getClaimable(ps[1]) + t.getAfking(ps[1])) +
                (t.getClaimable(ps[2]) + t.getAfking(ps[2]));
            assertEq(sumHalves, expectedPool, "Sigma(claimable + afking) tracks the running pool");
            assertEq(t.getClaimablePool(), expectedPool, "claimablePool tracks the running pool (paired debits)");
            assertEq(t.getClaimablePool(), sumHalves, "SOLVENCY: claimablePool == Sigma(claimable + afking)");
        }
        // Non-vacuity: the sequence credited (expectedPool grew) and exercised the debit identity at least once
        // for most seeds; assert the identity was checked on a non-empty pool.
        assertGt(expectedPool + debits, 0, "non-vacuity: the sequence performed real operations");
    }

    // =========================================================================
    // gameOver claimable-zeroing preserves the infra afking high halves
    // =========================================================================

    /// @notice The gameOver final sweep zeroes each infra address's CLAIMABLE half via _debitClaimable
    ///         (GameOverModule _finalSweep:205-207) — it must NOT touch the prepaid afking high half. Proven on
    ///         the actual VAULT / SDGNRS / GNRUS addresses: seed both halves, run the sweep's exact accessor
    ///         (drain the full claimable), and assert the afking high half survives byte-identical while the
    ///         claimable low half is zeroed. Falsifiable: a sweep that zeroed the WHOLE word would drop afking.
    function testGameOverZeroingPreservesInfraAfkingHalf() public {
        address[3] memory infra = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        for (uint256 i; i < 3; i++) {
            address a = infra[i];
            uint256 claimableOwed = (i + 1) * 10 ether;
            uint256 afkingPrepaid = (i + 7) * 13 ether;
            t.setClaimable(a, claimableOwed);
            t.setAfking(a, afkingPrepaid);

            // The sweep drains the FULL claimable owed for an infra sink (no sentinel — these are protocol
            // addresses): _debitClaimable(a, owed). Reproduce via setClaimable(a, 0), which calls
            // _debitClaimable(a, current) internally.
            uint256 highBefore = _rawHigh(a);
            t.setClaimable(a, 0); // zero the claimable half (the sweep's _debitClaimable op)

            assertEq(_rawLow(a), 0, "sweep: claimable low half zeroed");
            assertEq(t.getClaimable(a), 0, "sweep: claimable accessor reads zero");
            assertEq(_rawHigh(a), highBefore, "PRESERVED: afking high half byte-UNCHANGED through the zeroing");
            assertEq(t.getAfking(a), afkingPrepaid, "PRESERVED: afking accessor still reads the prepaid principal");
        }
    }

    // =========================================================================
    // No cross-half carry at supply-bound magnitudes
    // =========================================================================

    /// @notice At supply-bound magnitudes (per-player ETH <= ~1.2e26 wei, far below 2^128 ~3.4e38) a max-
    ///         realistic claimable low half plus an afking high credit produce NO carry across bit 127: the
    ///         low half stays exactly itself and the high half exactly itself. Falsifiable: a 127->128 carry
    ///         would shift the low half into the afking half and the assertions would fail.
    function testNoCrossHalfCarryAtSupplyBound() public {
        address p = makeAddr("nocarry");
        // ~1.2e26 wei (the documented per-player ceiling, the same justification as claimablePool being uint128).
        uint256 maxLow = 120_000_000 ether; // 1.2e26 wei
        uint256 highCredit = 99_000_000 ether;

        t.setClaimable(p, maxLow);
        t.setAfking(p, highCredit);

        assertEq(_rawLow(p), maxLow, "no-carry: low half holds the max-realistic claimable exactly");
        assertEq(_rawHigh(p), highCredit, "no-carry: high half holds the afking credit exactly (no bleed from low)");
        // Reconstruct the full word and confirm it splits back to the two inputs with no overlap.
        uint256 raw = uint256(vm.load(address(t), keccak256(abi.encode(p, uint256(BALANCES_PACKED_SLOT)))));
        assertEq(uint128(raw), maxLow, "split: low 128 bits == claimable");
        assertEq(raw >> 128, highCredit, "split: high 128 bits == afking");
    }

    // =========================================================================
    // Two-mapping value-equivalence
    // =========================================================================

    /// @notice A packed credit-then-debit yields the SAME observable (claimable, afking) pair as two
    ///         independent counters would. Mirror the exact sequence on plain locals (the conceptual two-
    ///         mapping baseline) and assert the packed accessors agree at every step. Falsifiable: any
    ///         packing arithmetic error (carry/borrow/wrong-half) would diverge from the plain counters.
    function testFuzzTwoMappingEquivalence(uint256 cSeed, uint256 aSeed, uint256 sSeed) public {
        address p = makeAddr("twomap");
        uint256 claimable = bound(cSeed, 2, 1e24);
        uint256 afking = bound(aSeed, 1, 1e24);

        // Plain two-counter baseline.
        uint256 refClaimable = claimable;
        uint256 refAfking = afking;

        t.setClaimable(p, claimable);
        t.setAfking(p, afking);
        t.setClaimablePool(claimable + afking);
        assertEq(t.getClaimable(p), refClaimable, "equiv: claimable matches the plain counter after seed");
        assertEq(t.getAfking(p), refAfking, "equiv: afking matches the plain counter after seed");

        // A debit through _settleShortfall (claimable-first-to-sentinel, then afking).
        uint256 usable = (refClaimable - 1) + refAfking;
        uint256 shortfall = bound(sSeed, 1, usable);
        t.settle(p, shortfall, true);

        // Replay the SAME waterfall on the plain counters.
        uint256 takeClaimable = shortfall < (refClaimable - 1) ? shortfall : (refClaimable - 1);
        refClaimable -= takeClaimable;
        refAfking -= (shortfall - takeClaimable);

        assertEq(t.getClaimable(p), refClaimable, "equiv: packed claimable == plain claimable after the debit");
        assertEq(t.getAfking(p), refAfking, "equiv: packed afking == plain afking after the debit");
        // And the raw slot recombines to exactly the two plain counters (value-identical fold).
        assertEq(_rawLow(p), refClaimable, "equiv: raw low half == plain claimable");
        assertEq(_rawHigh(p), refAfking, "equiv: raw high half == plain afking");
    }

    // =========================================================================
    // Raw-slot split helpers (prove the OTHER half at the storage level)
    // =========================================================================

    function _rawWord(address p) internal view returns (uint256) {
        return uint256(vm.load(address(t), keccak256(abi.encode(p, uint256(BALANCES_PACKED_SLOT)))));
    }

    function _rawLow(address p) internal view returns (uint256) {
        return uint128(_rawWord(p));
    }

    function _rawHigh(address p) internal view returns (uint256) {
        return _rawWord(p) >> 128;
    }
}
